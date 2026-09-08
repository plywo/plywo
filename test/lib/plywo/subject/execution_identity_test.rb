require "test_helper"

class ExecutionIdentityTest < ActiveSupport::TestCase
  test "is disabled when no subject identity environment is declared" do
    identity = Plywo::Subject::ExecutionIdentity.from_env({})

    assert_not identity.enabled?
    assert_equal({}, identity.environment)
    assert_equal({}, identity.spawn_options)
  end

  test "compiles a complete subject identity from environment" do
    identity = Plywo::Subject::ExecutionIdentity.from_env(
      "PLYWO_SUBJECT_UID" => "10001",
      "PLYWO_SUBJECT_GID" => "10002",
      "PLYWO_SUBJECT_HOME" => "/home/plywo-subject",
      "PLYWO_SUBJECT_USER" => "plywo-subject"
    )

    assert identity.enabled?
    assert_equal 10_001, identity.uid
    assert_equal 10_002, identity.gid
    assert_equal({ uid: 10_001, gid: 10_002 }, identity.spawn_options)
    assert_equal(
      {
        "HOME" => "/home/plywo-subject",
        "USER" => "plywo-subject",
        "LOGNAME" => "plywo-subject"
      },
      identity.environment
    )
  end

  test "fails closed on partial identity declaration" do
    error = assert_raises(Plywo::Subject::ExecutionIdentity::Error) do
      Plywo::Subject::ExecutionIdentity.from_env(
        "PLYWO_SUBJECT_UID" => "10001",
        "PLYWO_SUBJECT_GID" => "10001"
      )
    end

    assert_match(/requires PLYWO_SUBJECT_UID, PLYWO_SUBJECT_GID, PLYWO_SUBJECT_HOME, and PLYWO_SUBJECT_USER together/, error.message)
  end

  test "fails closed on invalid uid" do
    error = assert_raises(Plywo::Subject::ExecutionIdentity::Error) do
      Plywo::Subject::ExecutionIdentity.from_env(
        "PLYWO_SUBJECT_UID" => "root",
        "PLYWO_SUBJECT_GID" => "10001",
        "PLYWO_SUBJECT_HOME" => "/home/plywo-subject",
        "PLYWO_SUBJECT_USER" => "plywo-subject"
      )
    end

    assert_equal "PLYWO_SUBJECT_UID must be a non-negative integer", error.message
  end
end
