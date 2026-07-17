require "shellwords"

# A live tmux session belonging to an app — the runtime half of Session
# (which owns identity/lifecycle in the DB). Nothing here touches the
# database. Naming convention: "<app>--<session>".
class TmuxSession
  # Runs app hooks from config/rails_app_factory.rb (see that file's docs)
  HOOK_RUNNER = Rails.root.join("bin/hook").to_s
  PANE_FILTER = '#{&&:#{pane_active},#{window_active}}' # active pane only = one line per session
  PANE_FORMAT = '#S;#{session_attached};#{session_created};#{pane_current_command};#{pane_title}'

  attr_reader :app, :name, :attached, :created_at, :command, :title
  alias attached? attached

  def initialize(app:, name:, attached: false, created_at: Time.current, command: "starting", title: nil)
    @app, @name, @attached, @created_at, @command, @title = app, name, attached, created_at, command, title
  end

  class << self
    def for(app)
      host = Socket.gethostname
      prefix = "#{app.name}--"
      `tmux list-panes -a -f '#{PANE_FILTER}' -F '#{PANE_FORMAT}' 2>/dev/null`.lines.filter_map { |line|
        full, attached, created, command, title = line.chomp.split(";", 5)
        next unless full&.start_with?(prefix)
        title = nil if title.to_s.strip.empty? || title == host # hostname = tmux's default title
        new(app:, name: full.delete_prefix(prefix), attached: attached.to_i.positive?,
            created_at: Time.zone.at(created.to_i), command:, title:)
      }.sort_by(&:created_at)
    end

    # Worktree on a fresh branch + tmux session with two windows:
    # 0 "claude" (what the browser attaches to) and 1 "server" (setup + bin/dev).
    # prompt: kicks the agent off with the user's typed task.
    # resume: relaunches a slept session (reboot) — same worktree, agent
    # continues its previous conversation there.
    def launch(app, name, prompt: nil, resume: false)
      full = "#{app.name}--#{name}"
      port = Factory.free_port
      worktree = worktree_path(full)
      FileUtils.mkdir_p(Factory.worktrees_dir)
      system("git", "-C", app.path, "worktree", "add", "-b", "raf/#{name}", worktree) ||
        system("git", "-C", app.path, "worktree", "add", worktree, "raf/#{name}") # branch exists → reattach
      Factory.clean_tmux!
      env = { "PORT" => port.to_s, "BINDING" => "0.0.0.0", "RAF_APP" => app.name, "RAF_SESSION" => name }
      env.merge!(app.s3_env) if app.backups_configured? # lets a pulled prod DB serve its S3 attachments in dev
      system("tmux", "new-session", "-d", "-s", full, "-c", worktree,
             *env.flat_map { |key, value| ["-e", "#{key}=#{value}"] })
      style(full)
      system("tmux", "rename-window", "-t", full, "claude")
      agent = resume ? "#{app.agent} --continue" : [app.agent, prompt&.shellescape].compact.join(" ")
      system("tmux", "send-keys", "-t", full, agent, "Enter")
      system("tmux", "new-window", "-d", "-t", full, "-n", "server", "-c", worktree)
      system("tmux", "send-keys", "-t", "#{full}:server", "'#{HOOK_RUNNER}' setup server", "Enter")
    end

    # `rails new` runs visibly inside a "<app>--setup" session the user can watch.
    def launch_setup(app)
      FileUtils.mkdir_p(Factory.projects_dir)
      Factory.clean_tmux!
      system("tmux", "new-session", "-d", "-s", "#{app.name}--setup", "-c", Factory.projects_dir)
      style("#{app.name}--setup")
      command = "'#{Rails.root.join("bin/create-app")}' '#{app.name}'"
      command << " '#{app.repo_url}'" if app.repo_url.present? # validated: no spaces or quotes
      system("tmux", "send-keys", "-t", "#{app.name}--setup", command, "Enter")
    end

    def kill(app, name)
      full = "#{app.name}--#{name}"
      port = `tmux show-environment -t '#{full}' PORT 2>/dev/null`[/PORT=(\d+)/, 1]
      system("tmux", "kill-session", "-t", full)
      worktree = worktree_path(full)
      return unless File.directory?(worktree)

      env = { "RAF_APP" => app.name, "RAF_SESSION" => name }
      env["PORT"] = port if port
      # ponytail: synchronous — keep teardown hooks quick (drop a DB, stop a service)
      system(env, HOOK_RUNNER, "teardown", chdir: worktree)
      # branch raf/<name> survives on purpose — the session's commits stay reachable
      system("git", "-C", app.path, "worktree", "remove", "--force", worktree)
    end

    def worktree_path(full_name) = File.join(Factory.worktrees_dir, full_name)

    # mouse on: otherwise xterm turns wheel scrolling into arrow keys (shell
    # history). status-style: match the factory's pastel palette per session.
    def style(target)
      system("tmux", "set-option", "-t", target, "mouse", "on")
      system("tmux", "set-option", "-t", target, "status-style", "bg=#e8e0d0,fg=#857d6b")
      # "on" (not the default "external") lets apps inside tmux set the
      # clipboard too (claude's "c to copy") — the browser xterm turns the
      # resulting OSC 52 into a real clipboard write (see shared/_terminal).
      system("tmux", "set-option", "-s", "set-clipboard", "on")
    end
  end

  def tmux_name = "#{app.name}--#{name}"
  def setup? = name == "setup"
  def claude? = command == app.agent || command.match?(/\A\d+(\.\d+)+\z/) # claude's process title is its version number
  def display_command = claude? ? app.agent : command

  def port
    return @port if defined?(@port)
    @port = `tmux show-environment -t '#{tmux_name}' PORT 2>/dev/null`[/PORT=(\d+)/, 1]&.to_i
  end

  def preview_url(host) = port && "http://#{host}:#{port}"

  def as_json(host)
    { name:, attached: attached?, command: display_command, title:, claude: claude?, preview_url: preview_url(host) }
  end
end
