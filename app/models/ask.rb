require "json"
require "fileutils"
require "securerandom"

# A pop-up conversation with the user.
#
# claude writes an ordinary HTML page into ~/public — a question, a form, a
# choice, a preview — and asks the box to put it in front of the user. The page
# appears over the terminal, the user answers it with their thumbs, and the
# answer comes back to claude as the return value of the tool call. That is the
# whole point: the person on the other end is not a programmer, and a form with
# three big buttons beats a paragraph of prose asking them to type a decision.
#
# Same storage story as Push: no database, just small JSON files under tmp/, one
# per prompt. The MCP server (bin/mcp-ui) polls for the answer over loopback
# HTTP, so the file IS the queue and no process has to stay resident.
module Ask
  # Per environment: the suite wipes this directory, and it must not take a
  # question the user is looking at with it (see Push::DIR for the same trap).
  DIR = Rails.root.join("tmp", Rails.env.test? ? "ask-test" : "ask")
  STREAM = "ui".freeze
  TTL = 24 * 60 * 60           # forget prompts nobody answered within a day
  REPLAY = 60 * 60             # ...but only re-open recent ones on reconnect
  LOCK = Mutex.new

  module_function

  # Create a prompt and push it to whatever browser is attached. Returns the id
  # the MCP server polls on.
  def open!(path:, title: nil, wait: true)
    id = SecureRandom.hex(8)
    write(id, "id" => id, "path" => path, "title" => title, "wait" => wait,
              "created_at" => Time.now.to_i)
    ActionCable.server.broadcast(STREAM, { "id" => id, "title" => title, "wait" => wait })
    sweep!
    id
  end

  # The user submitted (or dismissed) the page. Recording it is what unblocks
  # the tool call claude is sitting in.
  def answer!(id, answer, dismissed: false)
    prompt = find(id) or return false
    write(id, prompt.merge("answer" => answer, "dismissed" => dismissed,
                           "answered_at" => Time.now.to_i))
    true
  end

  def answered?(prompt) = prompt.key?("answer") || prompt["dismissed"]

  # Everything still waiting on the user, oldest first.
  #
  # A broadcast only reaches whoever is connected at that instant, and a phone
  # drops the socket every time it backgrounds — so the pop-up was being lost
  # precisely when the push notification was doing its job, and they'd open the
  # app to nothing. UiChannel replays this on every (re)connect. Older than an
  # hour and it's stale enough that appearing unbidden is just confusing.
  def pending
    Dir.glob(DIR.join("*.json"))
       .filter_map { |path| JSON.parse(File.read(path)) rescue nil } # rubocop:disable Style/RescueModifier
       .reject { |prompt| answered?(prompt) }
       .select { |prompt| prompt["wait"] && Time.now.to_i - prompt["created_at"].to_i < REPLAY }
       .sort_by { |prompt| prompt["created_at"].to_i }
       .map { |prompt| prompt.slice("id", "title", "wait") }
  rescue StandardError
    []
  end

  def find(id)
    return nil unless id.to_s.match?(/\A[0-9a-f]{16}\z/) # it lands in a file path
    JSON.parse(File.read(file(id)))
  rescue StandardError
    nil
  end

  # The HTML claude wrote, resolved inside the publish dir and nowhere else —
  # the path arrives from a tool call, so treat it as untrusted input.
  def page_for(prompt)
    root = File.realpath(Factory.publish_dir)
    full = File.realpath(File.expand_path(prompt["path"].to_s, root))
    return nil unless full.start_with?("#{root}/") && File.file?(full)
    File.read(full)
  rescue StandardError
    nil
  end

  # --- files ---------------------------------------------------------------

  def file(id) = DIR.join("#{id}.json")

  def write(id, data)
    LOCK.synchronize do
      FileUtils.mkdir_p(DIR)
      File.write(file(id), JSON.generate(data))
    end
  end

  def sweep!
    Dir.glob(DIR.join("*.json")).each do |f|
      File.delete(f) if Time.now.to_i - File.mtime(f).to_i > TTL
    end
  rescue StandardError
    nil
  end
end
