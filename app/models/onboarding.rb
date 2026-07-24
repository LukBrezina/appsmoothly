# First run. Claude is the only thing that has to be set up before the box is
# usable, because it can't sign itself in — everything after that (GitHub, the
# code, the database, going live) claude walks the user through in the terminal.
# The factory stores no credentials; claude keeps its own under $HOME.
module Onboarding
  TMUX = "login".freeze
  STARTER_REPO = "https://github.com/LukBrezina/appsmoothly-starter-app".freeze
  GIT_URL = %r{\A(https://|git@)[\w.@:/~-]+\z}
  DEFAULT_PROMPT = "Set me up this project.".freeze

  module_function

  def installed?
    File.executable?(File.expand_path("~/.local/bin/claude")) ||
      !!system("which", "claude", out: File::NULL, err: File::NULL)
  end

  # Linux keeps OAuth in ~/.claude/.credentials.json; macOS uses the keychain
  # but records the account in ~/.claude.json — check both.
  def ready?
    File.exist?(File.expand_path("~/.claude/.credentials.json")) ||
      quiet_read("~/.claude.json").include?("oauthAccount")
  end

  # A browser terminal running plain `claude`, which offers its sign-in flow
  # when there are no credentials yet.
  def launch!
    return if running?

    Factory.clean_tmux!
    system("tmux", "new-session", "-d", "-s", TMUX, "-c", Dir.home)
    Agent.style(TMUX)
    system("tmux", "send-keys", "-t", TMUX, "claude", "Enter")
  end

  def running? = !!system("tmux", "has-session", "-t", "=#{TMUX}", out: File::NULL, err: File::NULL)

  # The sign-in session has served its purpose once claude has credentials.
  def tidy!
    return unless ready? && running?
    system("tmux", "kill-session", "-t", "=#{TMUX}", out: File::NULL, err: File::NULL)
  end

  # Claude's sign-in URL can't be copied out of the browser terminal: tmux
  # mouse mode swallows the selection, and the TUI hard-wraps the URL with real
  # newlines anyway. Scrape it from the pane and show it as a link.
  def login_url
    return unless running?
    extract_url(`tmux capture-pane -p -t '#{TMUX}'`)
  end

  def extract_url(text)
    text.gsub(/ +$/, "")[%r{https://\S+(?:\n\S+)*}]&.delete("\n")
  end

  # The typed task claude starts with. "starter"/a git address become a clone;
  # anything else just opens claude and lets it ask.
  def first_prompt(choice, repo = nil)
    url = choice == "repo" ? repo.to_s.strip[GIT_URL] : (STARTER_REPO if choice == "starter")
    return DEFAULT_PROMPT unless url

    "Set me up this project: clone #{url} into this folder, get it running, " \
      "and show me how it looks. Explain what it is in plain language as you go."
  end

  def quiet_read(path) = (File.read(File.expand_path(path)) rescue "") # rubocop:disable Style/RescueModifier
end
