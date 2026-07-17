require "test_helper"
require "tmpdir"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @app = apps(:blog)
    @root = Dir.mktmpdir
    ENV["RAF_PROJECTS_DIR"] = @root
    FileUtils.mkdir_p(File.join(@root, "blog", ".git")) # @app.ready?
  end

  teardown do
    FileUtils.remove_entry(@root)
    ENV.delete("RAF_PROJECTS_DIR")
  end

  test "create slugs the prompt into a row and hands it to claude" do
    launched = nil
    TmuxSession.stub :launch, ->(app, name, **opts) { launched = [app.name, name, opts] } do
      post sessions_path(@app), params: { prompt: "Fix the CSV export bug" }
    end
    assert_redirected_to session_path(@app, "fix-the-csv-export-bug")
    assert Session.exists?(app: @app, name: "fix-the-csv-export-bug")
    assert_equal ["blog", "fix-the-csv-export-bug", { prompt: "Fix the CSV export bug" }], launched
  end

  test "create with a blank prompt bounces with an alert" do
    TmuxSession.stub :launch, ->(*) { flunk "must not launch" } do
      post sessions_path(@app), params: { prompt: "   " }
    end
    assert_redirected_to sessions_path(@app)
    assert_equal 0, Session.count
  end

  test "destroy kills tmux and deletes the row" do
    Session.create!(app: @app, name: "old-work", title: "old")
    killed = nil
    TmuxSession.stub :kill, ->(_app, name) { killed = name } do
      delete session_path(@app, "old-work")
    end
    assert_equal "old-work", killed
    assert_not Session.exists?(app: @app, name: "old-work")
  end

  test "show wakes an asleep session by resuming claude" do
    Session.create!(app: @app, name: "old-work", title: "old")
    args = nil
    TmuxSession.stub :for, [] do
      TmuxSession.stub :launch, ->(_app, name, **opts) { args = [name, opts] } do
        get session_path(@app, "old-work")
      end
    end
    assert_response :success
    assert_equal ["old-work", { resume: true }], args
  end

  test "show of an unknown name never creates a workspace" do
    TmuxSession.stub :for, [] do
      TmuxSession.stub :launch, ->(*) { flunk "must not launch" } do
        get session_path(@app, "typo-name")
      end
    end
    assert_response :success
  end
end
