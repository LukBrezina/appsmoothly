require "open3"

# Keeps the factory itself current. The factory is a git checkout (see
# bin/update); "is there a new version?" is answered by git against its
# upstream, the same way Agent.alive? asks tmux — no version table, no state.
#
# The terminal page polls #status; when it's behind, it offers an Update button
# that hits #run!, which shells out to bin/update (pull, bundle, migrate,
# rebuild, restart). Updating the factory is never claude's job — claude works
# in the app dir on the user's app, not in this checkout — so it's the one bit
# of box maintenance the UI owns.
module Updater
  DIR = Rails.root.to_s              # the factory checkout
  FETCH_TTL = 300                    # seconds between upstream fetches (polling page)
  FETCH_TIMEOUT = 15                 # seconds before a slow fetch is abandoned

  @fetched_at = nil

  module_function

  # Everything the page needs to decide whether to offer an update. Best-effort:
  # a box with no network (or no upstream) simply reports "nothing to update".
  def status
    fetch!
    behind = behind_count
    { current: short("HEAD"), latest: short("@{upstream}"), behind: behind, available: behind.positive? }
  rescue StandardError
    { current: nil, latest: nil, behind: 0, available: false }
  end

  def available? = behind_count.positive?

  # Run bin/update fully detached. It ends by restarting the service, which would
  # kill a child still attached to this request — its own process group + setsid
  # (via bin/update's shell) keeps pull/bundle/migrate running to completion, and
  # output tails into log/update.log so a failed update is inspectable.
  def run!
    log = Rails.root.join("log/update.log").to_s
    pid = Process.spawn(Rails.root.join("bin/update").to_s,
                        { %i[out err] => [log, "a"], chdir: DIR, pgroup: true })
    Process.detach(pid)
    true
  end

  # --- git plumbing --------------------------------------------------------

  # Refresh the upstream ref, at most once per FETCH_TTL so a polling page (and
  # several open tabs) don't hammer the network. Stamps the time even on failure
  # to avoid retry storms; the next successful poll picks things up.
  def fetch!
    now = Time.now.to_i
    return if @fetched_at && now - @fetched_at < FETCH_TTL
    @fetched_at = now
    Open3.capture3("timeout", FETCH_TIMEOUT.to_s, "git", "-C", DIR, "fetch", "--quiet")
  rescue StandardError
    nil
  end

  def behind_count = git("rev-list", "--count", "HEAD..@{upstream}").to_i

  def short(ref) = git("rev-parse", "--short", ref).presence

  def git(*args)
    out, _err, status = Open3.capture3("git", "-C", DIR, *args)
    status.success? ? out.strip : ""
  rescue StandardError
    ""
  end
end
