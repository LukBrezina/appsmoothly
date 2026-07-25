require "shellwords"

# The one claude this box runs. tmux is the only state there is: the session
# exists or it doesn't, and if it doesn't we start it. No rows, no worktrees,
# no lifecycle — claude makes worktrees and extra windows itself if it wants
# them, and the user never sees more than this single terminal.
module Agent
  NAME = "claude"
  SHELLS = %w[sh bash zsh fish].freeze
  GRACE = 10 # seconds to let claude boot before we'd consider re-sending
  FORMAT = '#{pane_current_command};#{session_created}' # single quotes: tmux's #{}, not Ruby's

  # Baked-in defaults so a fresh box just works: light theme (matches the
  # browser terminal), /voice on, auto-approve — and the box briefing that
  # makes claude talk like a person and know how this machine is wired.
  # Per-launch via flags, so the box's global claude config is never touched.
  FLAGS = [
    "--permission-mode auto",
    "--settings #{Rails.root.join('config/claude-settings.json').to_s.shellescape}",
    "--append-system-prompt-file #{Rails.root.join('config/claude-brief.md').to_s.shellescape}"
  ].join(" ").freeze

  module_function

  def alive? = !!system("tmux", "has-session", "-t", "=#{NAME}", out: File::NULL, err: File::NULL)

  # Called on every page load. Starts the session after a reboot, and restarts
  # claude if the user quit out of it and left a bare shell behind.
  def ensure!(prompt: nil)
    Factory.ensure_dirs!
    return start(prompt) if new_session!
    start(prompt) if at_a_shell?
  end

  # Returns true when it actually created the session.
  def new_session!
    return false if alive?

    Factory.clean_tmux!
    Factory.trust!(Factory.app_dir)
    env = ENV.select { |k, _| k.start_with?("APPSMOOTHLY_") }
             .merge("PORT" => Factory::PORT.to_s, "BINDING" => "0.0.0.0")
    system("tmux", "new-session", "-d", "-s", NAME, "-c", Factory.app_dir,
           *env.flat_map { |key, value| ["-e", "#{key}=#{value}"] })
    style(NAME)
    watch_bell(NAME)
    true
  end

  # Stream the pane's output to bell-watch, which fires a Web Push when claude
  # rings the bell (finishes a turn). pipe-pane lives in the tmux server, so this
  # works even with no browser attached — the whole point of notifying a phone
  # that's asleep. Best-effort: if the box has no push set up it just no-ops.
  def watch_bell(target)
    watcher = Rails.root.join("bin/bell-watch").to_s.shellescape
    system("tmux", "pipe-pane", "-t", target, "-O", "exec #{watcher}")
  end

  # `--continue` picks the conversation back up (claude keys history on the
  # working directory), which is what a reboot should do. On a box that has
  # never run it there is nothing to continue, so it exits non-zero and the
  # fallback — with the first prompt, if we have one — runs instead.
  def start(prompt = nil)
    system("tmux", "send-keys", "-t", NAME, command(prompt), "Enter")
  end

  def command(prompt = nil)
    fallback = ["claude", FLAGS, prompt.presence&.shellescape].compact.join(" ")
    "claude #{FLAGS} --continue || #{fallback}"
  end

  # claude's process title is its version number ("2.1.200"), never "claude" —
  # so we detect the opposite: a plain shell sitting at a prompt.
  def at_a_shell?
    command, created = `tmux display-message -p -t '#{NAME}' '#{FORMAT}' 2>/dev/null`.chomp.split(";")
    SHELLS.include?(command) && Time.now.to_i - created.to_i > GRACE
  end

  # mouse on: otherwise xterm turns wheel scrolling into arrow keys (shell
  # history). set-clipboard on: lets claude's "c to copy" reach the browser
  # clipboard as OSC 52 (see shared/_terminal).
  def style(target)
    system("tmux", "set-option", "-t", target, "mouse", "on")
    system("tmux", "set-option", "-t", target, "status-style", "bg=#e8e0d0,fg=#857d6b")
    system("tmux", "set-option", "-s", "set-clipboard", "on")
  end
end
