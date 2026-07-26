require "test_helper"

class UiChannelTest < ActionCable::Channel::TestCase
  def setup
    FileUtils.rm_rf(Ask::DIR)
    FileUtils.mkdir_p(Factory.publish_dir)
    @name = "ui-chan-#{SecureRandom.hex(4)}.html"
    File.write(File.join(Factory.publish_dir, @name), "<html><body>hi</body></html>")
    @token = Factory.verifier.generate(Agent::NAME, expires_in: 1.hour)
  end

  def teardown
    FileUtils.rm_rf(Ask::DIR)
    File.delete(File.join(Factory.publish_dir, @name))
  end

  test "a bad token is refused" do
    subscribe token: "forged"
    assert subscription.rejected?
  end

  # The one that matters: a phone drops the socket whenever it backgrounds, so a
  # question asked while it slept would otherwise be lost — push notification,
  # then an empty screen.
  test "a question asked while they were away is waiting when they reconnect" do
    id = Ask.open!(path: @name, title: "Still open")
    subscribe token: @token
    assert subscription.confirmed?
    assert_equal [{ "id" => id, "title" => "Still open", "wait" => true }], transmissions
  end

  test "questions they already answered are not re-opened" do
    id = Ask.open!(path: @name, title: "Done with this")
    Ask.answer!(id, { "ok" => "yes" })
    subscribe token: @token
    assert_empty transmissions
  end

  test "a dismissed question stays closed" do
    id = Ask.open!(path: @name, title: "Nope")
    Ask.answer!(id, nil, dismissed: true)
    subscribe token: @token
    assert_empty transmissions
  end

  test "show_page never re-opens itself, having asked nothing" do
    Ask.open!(path: @name, title: "Just a chart", wait: false)
    subscribe token: @token
    assert_empty transmissions
  end

  test "yesterday's unanswered question does not ambush them today" do
    id = Ask.open!(path: @name, title: "Ancient")
    stale = Ask.find(id).merge("created_at" => 3.hours.ago.to_i)
    Ask.write(id, stale)
    subscribe token: @token
    assert_empty transmissions
  end
end
