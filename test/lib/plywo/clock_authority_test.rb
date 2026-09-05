require "test_helper"

class PlywoClockAuthorityTest < ActiveSupport::TestCase
  test "reads wall time from PostgreSQL clock_timestamp" do
    connection = Minitest::Mock.new
    connection.expect(
      :select_value,
      "2026-09-05 00:40:00+00",
      [ Plywo::ClockAuthority::DATABASE_NOW_SQL, "Plywo database clock" ]
    )

    assert_equal Time.zone.parse("2026-09-05 00:40:00 UTC"), Plywo::ClockAuthority.database_now(connection:)
    connection.verify
  end

  test "monotonic clock never exposes wall-clock time" do
    first = Plywo::ClockAuthority.monotonic_now
    second = Plywo::ClockAuthority.monotonic_now

    assert_kind_of Numeric, first
    assert_operator second, :>=, first
  end
end
