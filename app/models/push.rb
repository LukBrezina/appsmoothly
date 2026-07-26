require "json"
require "fileutils"
require "web-push"

# Web Push: lets the box ping the browser when Claude finishes a turn — the only
# way to reach a backgrounded phone, since iOS gives a browser tab no
# notifications at all (it has to be an installed PWA fed by a real push).
#
# True to the factory, there's no database. Two small JSON files under tmp/ hold
# the VAPID keypair and the browser subscriptions; the page re-sends its
# subscription on every load, so a wipe just re-populates. bin/bell-watch reads
# the very same files from the tmux server for the no-browser-attached case.
module Push
  # Per environment, because the test suite wipes this directory wholesale and
  # Rails.root does not change between them: sharing it meant `bin/rails test`
  # deleting the box's VAPID keypair and every phone subscribed to it, silently
  # unsubscribing the owner mid-session.
  DIR   = Rails.root.join("tmp", Rails.env.test? ? "push-test" : "push")
  KEYS  = DIR.join("vapid.json")
  SUBS  = DIR.join("subscriptions.json")
  STAMP = DIR.join("last-notified")
  DEBOUNCE = 4 # seconds — collapse the two triggers (channel sees the bell + bell-watch)
  # The VAPID `sub` claim. Apple validates it and answers 403 BadJwtToken for an
  # address whose domain has no TLD, so it has to be a real mailto (or https
  # URL) — the box's own domain is the one thing we always have. Keep
  # bin/bell-watch's copy in step.
  SUBJECT  = "mailto:claude@#{ENV["APPSMOOTHLY_DOMAIN"].presence || "appsmoothly.com"}".freeze
  LOCK = Mutex.new

  module_function

  # A stable VAPID keypair, generated once and kept so existing subscriptions
  # stay valid across restarts. The public half is what the browser subscribes with.
  def public_key = vapid["public_key"]

  def vapid
    @vapid ||= read_json(KEYS) || LOCK.synchronize { read_json(KEYS) || generate_vapid }
  end

  def generate_vapid
    key = WebPush.generate_key
    data = { "public_key" => key.public_key, "private_key" => key.private_key }
    write_json(KEYS, data)
    data
  end

  # Remember a browser subscription (dedup by endpoint).
  def subscribe(sub)
    endpoint = sub["endpoint"].to_s
    return if endpoint.empty?
    LOCK.synchronize do
      subs = load_subs.reject { |s| s["endpoint"] == endpoint }
      write_json(SUBS, subs << sub)
    end
  end

  # Fire "Claude is done" to every subscribed browser, debounced so the channel
  # and bell-watch don't double-notify. Best-effort; dead subscriptions are pruned.
  def notify_done!
    return unless throttle!
    broadcast(title: "Claude", body: "Claude is done — your turn.")
  end

  # A pop-up is waiting for them. Not throttled with the turn bell: this one is
  # a direct question, and it is worth interrupting a backgrounded phone for.
  def notify_asked!(title = nil)
    broadcast(title: "Claude needs you", body: title.presence || "There's something to look at.")
  end

  def broadcast(title:, body:)
    subs = load_subs
    return if subs.empty?
    v = vapid
    message = JSON.generate(title: title, body: body)
    alive = subs.reject { |sub| dead?(sub, message, v) }
    LOCK.synchronize { write_json(SUBS, alive) } if alive.size != subs.size
  end

  # Sends one push; returns true only when the subscription is gone for good.
  def dead?(sub, message, v)
    WebPush.payload_send(
      message: message, endpoint: sub["endpoint"],
      p256dh: sub.dig("keys", "p256dh"), auth: sub.dig("keys", "auth"),
      vapid: { subject: SUBJECT, public_key: v["public_key"], private_key: v["private_key"] },
      urgency: "high"
    )
    false
  rescue WebPush::ExpiredSubscription
    true
  rescue StandardError
    false # transient (network / push service) — keep it, retry next time
  end

  # --- files ---------------------------------------------------------------

  def load_subs = read_json(SUBS) || []

  # File-based so the channel and the separate bell-watch process share one clock.
  def throttle!
    now = Time.now.to_f
    last = File.exist?(STAMP) ? File.read(STAMP).to_f : 0.0
    return false if now - last < DEBOUNCE
    write_raw(STAMP, now.to_s)
    true
  rescue StandardError
    true
  end

  def read_json(path)
    JSON.parse(File.read(path)) if File.exist?(path)
  rescue StandardError
    nil
  end

  def write_json(path, data) = write_raw(path, JSON.generate(data))

  def write_raw(path, str)
    FileUtils.mkdir_p(DIR)
    File.write(path, str)
  end
end
