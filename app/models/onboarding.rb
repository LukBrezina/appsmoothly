# First-run readiness (the "Get started" page). The factory stores no
# credentials — Claude and gh keep their own (under $HOME, so every session
# inherits them); we only check they exist and open a browser terminal
# (a "factory--<name>" tmux session, same pattern as app sessions) to sign in.
class Onboarding
  LOGINS = {
    "claude-login" => "claude", # the user types /login inside
    "github-login" => "gh auth login --git-protocol https --web && gh auth setup-git"
  }.freeze

  def claude_installed?
    File.executable?(File.expand_path("~/.local/bin/claude")) || command?("claude")
  end

  # Linux keeps OAuth in ~/.claude/.credentials.json; macOS uses the keychain
  # but records the account in ~/.claude.json — check both.
  def claude_ready?
    File.exist?(File.expand_path("~/.claude/.credentials.json")) ||
      quiet_read("~/.claude.json").include?("oauthAccount")
  end

  def gh_installed? = command?("gh")
  def gh_ready? = !!system("gh", "auth", "status", out: File::NULL, err: File::NULL)

  def done? = claude_ready? && gh_ready?

  def launch(name)
    command = LOGINS.fetch(name)
    return if running?(name)

    Factory.clean_tmux!
    system("tmux", "new-session", "-d", "-s", tmux_name(name), "-c", Dir.home)
    TmuxSession.style(tmux_name(name))
    system("tmux", "send-keys", "-t", tmux_name(name), command, "Enter")
  end

  def running?(name) = !!system("tmux", "has-session", "-t", "=#{tmux_name(name)}", err: File::NULL)

  # A sign-in session has served its purpose once its check passes.
  def tidy!
    kill("claude-login") if claude_ready?
    kill("github-login") if gh_ready?
  end

  def tmux_name(name) = "factory--#{name}"

  private

  def kill(name) = system("tmux", "kill-session", "-t", "=#{tmux_name(name)}", err: File::NULL, out: File::NULL)
  def command?(cmd) = !!system("which", cmd, out: File::NULL, err: File::NULL)
  def quiet_read(path) = (File.read(File.expand_path(path)) rescue "") # rubocop:disable Style/RescueModifier
end
