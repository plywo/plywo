require "test_helper"

class PlywoExecutorRequestTest < ActiveSupport::TestCase
  test "acquires a new idempotent request and completes only the active claim" do
    now = Time.utc(2026, 9, 4, 21, 40, 0)
    acquisition = acquire(now:)

    assert_equal :execute, acquisition.state
    assert_equal "processing", acquisition.record.status
    assert acquisition.claim_token
    assert_equal now + 60, acquisition.record.lease_expires_at

    result = Plywo::Executor::Result.success("result" => { "decision" => "allow" }).to_h
    assert acquisition.record.complete_claim!(
      claim_token: acquisition.claim_token,
      result_payload: result,
      now: now + 10
    )

    record = acquisition.record.reload
    assert_equal "completed", record.status
    assert_equal result, record.result
    assert_nil record.claim_token
    assert_nil record.lease_expires_at
  end

  test "returns a completed result for the same request without another claim" do
    now = Time.utc(2026, 9, 4, 21, 40, 0)
    first = acquire(now:)
    first.record.complete_claim!(
      claim_token: first.claim_token,
      result_payload: Plywo::Executor::Result.success({}).to_h,
      now: now + 1
    )

    duplicate = acquire(now: now + 2)

    assert_equal :completed, duplicate.state
    assert_nil duplicate.claim_token
  end

  test "reports an in-progress duplicate while the claim lease is live" do
    now = Time.utc(2026, 9, 4, 21, 40, 0)
    first = acquire(now:)
    duplicate = acquire(now: now + 30)

    assert_equal :execute, first.state
    assert_equal :in_progress, duplicate.state
    assert_nil duplicate.claim_token
  end

  test "reclaims an expired request with a new claim token" do
    now = Time.utc(2026, 9, 4, 21, 40, 0)
    first = acquire(now:)
    reclaimed = acquire(now: now + 61)

    assert_equal :execute, reclaimed.state
    refute_equal first.claim_token, reclaimed.claim_token
    assert_equal now + 121, reclaimed.record.lease_expires_at

    refute first.record.complete_claim!(
      claim_token: first.claim_token,
      result_payload: Plywo::Executor::Result.success({}).to_h,
      now: now + 62
    )
  end

  test "rejects reuse of an idempotency key for different request content" do
    now = Time.utc(2026, 9, 4, 21, 40, 0)
    acquire(now:)
    changed = request_payload.merge("candidate_sha" => "different-head")

    assert_raises(PlywoExecutorRequest::DigestMismatch) do
      PlywoExecutorRequest.acquire!(
        idempotency_key: "execution:1",
        request_payload: changed,
        now: now + 1,
        lease_seconds: 60
      )
    end
  end

  test "canonical request digests ignore hash key ordering" do
    first = {
      "b" => { "y" => 2, "x" => 1 },
      "a" => [ { "d" => 4, "c" => 3 } ]
    }
    second = {
      "a" => [ { "c" => 3, "d" => 4 } ],
      "b" => { "x" => 1, "y" => 2 }
    }

    assert_equal PlywoExecutorRequest.digest_for(first), PlywoExecutorRequest.digest_for(second)
  end

  private

  def acquire(now:)
    PlywoExecutorRequest.acquire!(
      idempotency_key: "execution:1",
      request_payload:,
      now:,
      lease_seconds: 60
    )
  end

  def request_payload
    {
      "schema_version" => "1",
      "execution_id" => "github-123",
      "scenario_id" => "scenario",
      "baseline_sha" => "base",
      "candidate_sha" => "head",
      "attempt_number" => 1,
      "context" => {
        "repository" => "plywo/plywo",
        "pull_request_number" => 40,
        "baseline_ref" => "main",
        "candidate_ref" => "feature",
        "candidate_repository" => "plywo/plywo"
      }
    }
  end
end
