require "test_helper"

class AskTest < ActiveSupport::TestCase
  def setup
    FileUtils.rm_rf(Ask::DIR)
    FileUtils.mkdir_p(Factory.publish_dir)
    @page = File.join(Factory.publish_dir, "ask-test-#{SecureRandom.hex(4)}.html")
    File.write(@page, "<html><body><form></form></body></html>")
  end

  def teardown
    FileUtils.rm_rf(Ask::DIR)
    File.delete(@page) if File.exist?(@page)
  end

  test "opening a prompt stores it and hands back an id" do
    id = Ask.open!(path: File.basename(@page), title: "Pick one")
    assert_match(/\A[0-9a-f]{16}\z/, id)
    assert_equal "Pick one", Ask.find(id)["title"]
    assert_not Ask.answered?(Ask.find(id))
  end

  test "an answer is what unblocks the waiting tool call" do
    id = Ask.open!(path: File.basename(@page))
    assert Ask.answer!(id, { "plan" => "cards" })
    prompt = Ask.find(id)
    assert Ask.answered?(prompt)
    assert_equal({ "plan" => "cards" }, prompt["answer"])
  end

  test "a dismissal counts as answered, so nobody waits on someone who left" do
    id = Ask.open!(path: File.basename(@page))
    Ask.answer!(id, nil, dismissed: true)
    assert Ask.answered?(Ask.find(id))
  end

  test "answering something that does not exist is a no-op, not an error" do
    assert_not Ask.answer!("0" * 16, {})
  end

  test "ids that could escape the directory are refused outright" do
    assert_nil Ask.find("../../etc/passwd")
    assert_nil Ask.find("nope")
  end

  test "pages outside the publish dir are refused" do
    assert Ask.page_for("path" => File.basename(@page))
    assert_nil Ask.page_for("path" => "../appsmoothly/config/master.key")
    assert_nil Ask.page_for("path" => "/etc/passwd")
    assert_nil Ask.page_for("path" => "does-not-exist.html")
  end
end
