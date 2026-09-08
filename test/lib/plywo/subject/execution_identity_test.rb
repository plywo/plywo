require "test_helper"

class ExecutionIdentityTest < ActiveSupport::TestCase
  test "is disabled when no subject identity environment is declared" do
    identity = Plywo::Subject::ExecutionIdentity.from_env({})

    assert_not identity.enabled?
    assert_equal({}, identity.environment)
    assert_equal({}, identity.environment(workspace: Rails.root))
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

  test "uses a distinct worktree-local HOME for runtime execution" do
    identity = Plywo::Subject::ExecutionIdentity.new(
      uid: 10_001,
      gid: 10_001,
      home: "/home/plywo-subject",
      user: "plywo-subject"
    )
    baseline = Pathname("/tmp/plywo/base")
    candidate = Pathname("/tmp/plywo/candidate")

    baseline_env = identity.environment(workspace: baseline)
    candidate_env = identity.environment(workspace: candidate)

    assert_equal "/tmp/plywo/base/tmp/plywo/home", baseline_env.fetch("HOME")
    assert_equal "/tmp/plywo/candidate/tmp/plywo/home", candidate_env.fetch("HOME")
    assert_not_equal baseline_env.fetch("HOME"), candidate_env.fetch("HOME")
    assert_equal "plywo-subject", baseline_env.fetch("USER")
    assert_equal "plywo-subject", baseline_env.fetch("LOGNAME")
  end

  test "fails closed on partial identity declaration" do
    error = assert_raises(Plywo::Subject::ExecutionIdentity::Error) do
      Plywo::Subject::ExecutionIdentity.from_env(
        "PLYWO_SUBJECT_UID" => "10001",
        "PLYWO_SUBJECT_GID" => "10001"
      )
    end

    assert_includes error.message, "requires PLYWO_SUBJECT_UID, PLYWO_SUBJECT_GID"
    assert_includes error.message, "PLYWO_SUBJECT_HOME, and PLYWO_SUBJECT_USER together"
  end

  test "fails closed on invalid or root uid" do
    invalid = assert_raises(Plywo::Subject::ExecutionIdentity::Error) do
      Plywo::Subject::ExecutionIdentity.from_env(
        "PLYWO_SUBJECT_UID" => "root",
        "PLYWO_SUBJECT_GID" => "10001",
        "PLYWO_SUBJECT_HOME" => "/home/plywo-subject",
        "PLYWO_SUBJECT_USER" => "plywo-subject"
      )
    end
    root = assert_raises(Plywo::Subject::ExecutionIdentity::Error) do
      Plywo::Subject::ExecutionIdentity.from_env(
        "PLYWO_SUBJECT_UID" => "0",
        "PLYWO_SUBJECT_GID" => "10001",
        "PLYWO_SUBJECT_HOME" => "/home/plywo-subject",
        "PLYWO_SUBJECT_USER" => "plywo-subject"
      )
    end

    assert_equal "PLYWO_SUBJECT_UID must be a positive integer", invalid.message
    assert_equal "PLYWO_SUBJECT_UID must be a positive integer", root.message
  end

  test "fails closed when subject uid matches executor uid" do
    skip "executor uid is root and rejected by positive uid validation" if Process.euid.zero?

    error = assert_raises(Plywo::Subject::ExecutionIdentity::Error) do
      Plywo::Subject::ExecutionIdentity.new(
        uid: Process.euid,
        gid: Process.egid.positive? ? Process.egid : 10_001,
        home: "/tmp/plywo-subject",
        user: "plywo-subject"
      )
    end

    assert_match(/must differ from executor uid/, error.message)
  end

  test "fails closed on relative home" do
    error = assert_raises(Plywo::Subject::ExecutionIdentity::Error) do
      Plywo::Subject::ExecutionIdentity.new(
        uid: 10_001,
        gid: 10_001,
        home: "relative/home",
        user: "plywo-subject"
      )
    end

    assert_equal "Subject execution home must be an absolute path", error.message
  end
end
