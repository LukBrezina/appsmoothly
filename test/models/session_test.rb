require "test_helper"

class SessionTest < ActiveSupport::TestCase
  test "slug_for slugs the prompt, capped and unique per app" do
    app = apps(:blog)
    assert_equal "fix-the-csv-export-bug", Session.slug_for(app, "Fix the CSV export bug!")

    Session.create!(app:, name: "fix-the-csv-export-bug", title: "x")
    assert_equal "fix-the-csv-export-bug-2", Session.slug_for(app, "Fix the CSV export bug")

    long = Session.slug_for(app, "please make the whole login page look much nicer on phones")
    assert_operator long.length, :<=, 48
    assert_match(/\A\w+(?:-\w+)*\z/, long)
  end

  test "slug_for falls back for empty or reserved prompts" do
    app = apps(:blog)
    assert_equal "session", Session.slug_for(app, "🎉🎉")
    assert_equal "session", Session.slug_for(app, "setup")
  end

  test "for merges rows with live tmux, persists claude titles, wraps ops sessions" do
    app = apps(:blog)
    row = Session.create!(app:, name: "add-login", title: "add a login page")
    live = TmuxSession.new(app:, name: "add-login", attached: true, title: "Adding login", command: "2.1.200")
    deploy = TmuxSession.new(app:, name: "deploy", command: "kamal")

    TmuxSession.stub :for, [live, deploy] do
      list = Session.for(app)
      assert_equal %w[add-login deploy], list.map(&:name).sort

      mine = list.find { |s| s.name == "add-login" }
      assert_equal "live", mine.state
      assert_predicate mine, :claude?
      assert_equal "Adding login", row.reload.title # claude's name stuck

      ops = list.find { |s| s.name == "deploy" }
      assert_not ops.persisted?
      assert_equal "idle", ops.state
    end
  end

  test "a row without tmux is asleep, not gone" do
    app = apps(:blog)
    Session.create!(app:, name: "add-login", title: "add a login page")

    TmuxSession.stub :for, [] do
      list = Session.for(app)
      assert_equal 1, list.size
      assert_equal "asleep", list.first.state
      assert_equal "asleep", list.first.display_command
      assert_equal "add a login page", list.first.display_title
      assert_nil list.first.preview_url("host")
    end
  end
end
