require "test_helper"

class PlywoRailsInternalOperationTest < ActiveSupport::TestCase
  test "is active only inside guarded work and supports nesting" do
    assert_not Plywo::Rails::InternalOperation.active?

    Plywo::Rails::InternalOperation.call do
      assert Plywo::Rails::InternalOperation.active?

      Plywo::Rails::InternalOperation.call do
        assert Plywo::Rails::InternalOperation.active?
      end

      assert Plywo::Rails::InternalOperation.active?
    end

    assert_not Plywo::Rails::InternalOperation.active?
  end

  test "restores state when guarded work raises" do
    assert_raises(RuntimeError) do
      Plywo::Rails::InternalOperation.call do
        assert Plywo::Rails::InternalOperation.active?
        raise "guard proof failure"
      end
    end

    assert_not Plywo::Rails::InternalOperation.active?
  end
end
