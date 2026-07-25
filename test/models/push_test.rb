require "test_helper"

class PushTest < ActiveSupport::TestCase
  def setup = reset_push_dir
  def teardown = reset_push_dir

  def reset_push_dir
    FileUtils.rm_rf(Push::DIR)
    Push.instance_variable_set(:@vapid, nil)
  end

  test "generates and persists a stable VAPID keypair" do
    key = Push.public_key
    assert key.present?
    assert File.exist?(Push::KEYS)
    assert_equal key, Push.public_key            # memoized / re-read, not regenerated
  end

  test "stores subscriptions and dedups by endpoint" do
    Push.subscribe("endpoint" => "https://push/a", "keys" => { "p256dh" => "x", "auth" => "y" })
    Push.subscribe("endpoint" => "https://push/a", "keys" => { "p256dh" => "z", "auth" => "y" })
    Push.subscribe("endpoint" => "https://push/b", "keys" => { "p256dh" => "q", "auth" => "y" })
    subs = Push.load_subs
    assert_equal 2, subs.size
    assert_equal "z", subs.find { |s| s["endpoint"] == "https://push/a" }.dig("keys", "p256dh")
  end

  test "throttle collapses rapid triggers" do
    assert Push.throttle!
    assert_not Push.throttle!                     # within DEBOUNCE
  end

  test "notify_done with no subscriptions is a no-op, not an error" do
    assert_nothing_raised { Push.notify_done! }
  end
end
