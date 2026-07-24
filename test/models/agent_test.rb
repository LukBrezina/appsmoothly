require "test_helper"
require "tmpdir"

# The one line the whole product hangs on: `claude --continue || claude <prompt>`.
# Run it for real against a fake claude — tmux only types this string.
class AgentTest < ActiveSupport::TestCase
  test "a box with a conversation resumes it and never runs the first prompt" do
    log = run_command(Agent.command("Set me up this project."), continue_works: true)
    assert_equal 1, log.lines.size
    assert_match "--continue", log
    assert_no_match(/Set me up/, log)
  end

  test "a fresh box has nothing to continue, so the first prompt runs instead" do
    log = run_command(Agent.command("Set me up this project."), continue_works: false)
    assert_match "Set me up this project.", log.lines.last
    assert_match "--append-system-prompt-file", log.lines.last # the box briefing is always attached
  end

  test "without a prompt the fallback still opens claude" do
    log = run_command(Agent.command, continue_works: false)
    assert_equal 2, log.lines.size # --continue attempt, then plain claude
  end

  private

  # Fake claude: logs how it was called, and fails on --continue when asked to.
  def run_command(command, continue_works:)
    Dir.mktmpdir do |dir|
      File.write("#{dir}/claude", <<~SH)
        #!/bin/sh
        printf '%s\\n' "$*" >> "$LOG"
        for a in "$@"; do
          [ "$a" = "--continue" ] && exit #{continue_works ? 0 : 1}
        done
        exit 0
      SH
      File.chmod(0o755, "#{dir}/claude")
      system({ "PATH" => "#{dir}:#{ENV['PATH']}", "LOG" => "#{dir}/log" }, "sh", "-c", command)
      File.read("#{dir}/log")
    end
  end
end
