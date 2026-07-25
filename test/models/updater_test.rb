require "test_helper"

class UpdaterTest < ActiveSupport::TestCase
  test "status reports the checkout against its upstream" do
    result = Updater.stub :fetch!, nil do   # don't hit the network in the suite
      Updater.status
    end
    assert_equal %i[available behind current latest], result.keys.sort
    assert_kind_of Integer, result[:behind]
    assert_includes [true, false], result[:available]
    assert_equal result[:behind].positive?, result[:available]
  end

  test "available? mirrors whether the checkout is behind" do
    Updater.stub(:behind_count, 3) { assert Updater.available? }
    Updater.stub(:behind_count, 0) { assert_not Updater.available? }
  end

  test "a failure anywhere degrades to 'nothing to update' rather than raising" do
    Updater.stub :fetch!, -> { raise "no network" } do
      assert_equal({ current: nil, latest: nil, behind: 0, available: false }, Updater.status)
    end
  end
end
