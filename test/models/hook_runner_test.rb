require "test_helper"

class HookRunnerTest < ActiveSupport::TestCase
  RUNNER = Rails.root.join("bin/hook").to_s

  test "runs ruby blocks with sh, app, session and port helpers" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/rails_app_factory.rb"), <<~RUBY)
        setup do
          File.write("touched.txt", "\#{app}-\#{session}-\#{port}")
          sh "true"
        end
        teardown do
          File.write("gone.txt", "bye")
        end
      RUBY
      env = { "RAF_APP" => "shop", "RAF_SESSION" => "checkout", "PORT" => "4001" }
      assert system(env, RUNNER, "setup", chdir: dir), "setup hook should succeed"
      assert_equal "shop-checkout-4001", File.read(File.join(dir, "touched.txt"))
      assert system(env, RUNNER, "teardown", chdir: dir)
      assert File.exist?(File.join(dir, "gone.txt"))
    end
  end

  test "scrubs the factory's bundler env so app commands use the app's own bundle" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/rails_app_factory.rb"), <<~RUBY)
        setup { sh "echo RUBYOPT=[$RUBYOPT] BUNDLE_GEMFILE=[$BUNDLE_GEMFILE] > seen.txt" }
      RUBY
      # Mirror the remote: the factory's real bundler env rides into the hook.
      env = { "RUBYOPT" => "-rbundler/setup", "BUNDLE_GEMFILE" => Rails.root.join("Gemfile").to_s }
      assert system(env, RUNNER, "setup", chdir: dir)
      assert_equal "RUBYOPT=[] BUNDLE_GEMFILE=[]", File.read(File.join(dir, "seen.txt")).strip
    end
  end

  test "no config and no scripts is a quiet no-op for teardown" do
    Dir.mktmpdir do |dir|
      assert system(RUNNER, "teardown", chdir: dir)
    end
  end

  test "falls back to bin scripts and fails loudly on a failing command" do
    Dir.mktmpdir do |dir|
      FileUtils.mkdir_p(File.join(dir, "bin"))
      File.write(File.join(dir, "bin/setup-worktree"), "#!/bin/sh\ntouch via-fallback.txt\n")
      File.chmod(0o755, File.join(dir, "bin/setup-worktree"))
      assert system(RUNNER, "setup", chdir: dir)
      assert File.exist?(File.join(dir, "via-fallback.txt"))

      FileUtils.mkdir_p(File.join(dir, "config"))
      File.write(File.join(dir, "config/rails_app_factory.rb"), "setup do\n  sh 'false'\nend\n")
      assert_not system(RUNNER, "setup", chdir: dir), "failing sh should exit nonzero"
    end
  end
end
