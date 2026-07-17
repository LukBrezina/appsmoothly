# A user workspace. The DB row says it exists; tmux says it's running. Rows
# are created from a typed task ("What should Claude work on?"), slugged into
# a name, and removed only on explicit kill — a reboot just puts the session
# to sleep (tmux gone, row and worktree stay; opening it wakes Claude back up).
class Session < ApplicationRecord
  # Factory-driven operations (app creation, go live, rewind) stay tmux-only —
  # they appear in the list as unsaved rows and vanish when their tmux ends.
  RESERVED = %w[setup deploy restore].freeze

  belongs_to :app

  validates :name, presence: true, uniqueness: { scope: :app_id },
                   format: { with: /\A\w+(?:-\w+)*\z/ } # no "--", keeps <app>--<session> unambiguous

  attr_accessor :tmux # live TmuxSession, attached by Session.for; nil = asleep

  class << self
    # The session list the UI shows: rows merged with live tmux state, plus
    # ephemeral entries for live tmux sessions without rows (setup/deploy/…).
    def for(app)
      live = TmuxSession.for(app).index_by(&:name)
      rows = where(app:).to_a
      rows.each do |row|
        row.tmux = live.delete(row.name)
        row.sync_title!
      end
      extras = live.values.map { |t| new(app:, name: t.name, created_at: t.created_at).tap { |s| s.tmux = t } }
      (rows + extras).sort_by(&:created_at)
    end

    # "Fix the CSV export bug" → "fix-the-csv-export-bug"; unique per app.
    def slug_for(app, prompt)
      base = prompt.parameterize.split("-").first(6).join("-")[0, 48].delete_suffix("-")
      base = "session" if base.blank? || RESERVED.include?(base)
      name, n = base, 1
      name = "#{base}-#{n += 1}" while exists?(app:, name:)
      name
    end
  end

  def tmux_name = "#{app.name}--#{name}"
  def alive? = !tmux.nil?
  def attached? = !!tmux&.attached?
  def state = attached? ? "live" : alive? ? "idle" : "asleep"
  def claude? = !!tmux&.claude?
  def port = tmux&.port
  def preview_url(host) = tmux&.preview_url(host)
  def display_command = alive? ? tmux.display_command : "asleep"
  def display_title = tmux&.title || title.presence || name

  # Claude renames its terminal as it works (OSC title); keep the last name.
  def sync_title!
    live = tmux&.title
    update_column(:title, live) if persisted? && live.present? && live != title
  end

  def as_json(host)
    { name:, state:, attached: attached?, command: display_command,
      title: display_title, claude: claude?, preview_url: preview_url(host) }
  end
end
