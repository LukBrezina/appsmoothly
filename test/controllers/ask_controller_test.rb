require "test_helper"

class AskControllerTest < ActionDispatch::IntegrationTest
  def setup
    FileUtils.rm_rf(Ask::DIR)
    FileUtils.mkdir_p(Factory.publish_dir)
    @name = "ask-ctrl-#{SecureRandom.hex(4)}.html"
    File.write(File.join(Factory.publish_dir, @name), "<html><body><h1>Pick</h1></body></html>")
  end

  def teardown
    FileUtils.rm_rf(Ask::DIR)
    File.delete(File.join(Factory.publish_dir, @name))
  end

  def open_prompt
    post ask_open_path, params: { path: @name, title: "Pick one" }
    JSON.parse(response.body)["id"]
  end

  test "the tool opens a prompt and gets an id" do
    id = open_prompt
    assert_response :success
    assert_match(/\A[0-9a-f]{16}\z/, id)
  end

  test "the page is served with the reply shim appended" do
    get ask_path(open_prompt)
    assert_response :success
    assert_includes response.body, "<h1>Pick</h1>"
    assert_includes response.body, "/answer" # the shim knows where to post
  end

  test "an unknown prompt is a 404 rather than a stack trace" do
    get ask_path("0" * 16)
    assert_response :not_found
  end

  test "the answer comes back to whoever is polling" do
    id = open_prompt
    post ask_answer_path(id), params: { answer: { plan: "cards" } }
    assert_response :success

    get ask_result_path(id), params: { timeout: 0 }
    body = JSON.parse(response.body)
    assert_equal "answered", body["status"]
    assert_equal({ "plan" => "cards" }, body["answer"])
  end

  test "polling an unanswered prompt says so instead of hanging forever" do
    get ask_result_path(open_prompt), params: { timeout: 0 }
    assert_equal "waiting", JSON.parse(response.body)["status"]
  end

  test "closing the pop-up is reported, so claude stops waiting" do
    id = open_prompt
    post ask_answer_path(id), params: { dismissed: "1" }
    get ask_result_path(id), params: { timeout: 0 }
    assert JSON.parse(response.body)["dismissed"]
  end
end
