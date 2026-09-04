require "test_helper"

class GithubPullRequestExecutionLeaseReaperJobTest < ActiveJob::TestCase
  class TestJob < GithubPullRequestExecutionLeaseReaperJob
    attr_accessor :expiry_job_override

    private

    def expiry_job_class
      expiry_job_override
    end
  end

  test "schedules only overdue running GitHub executions" do
    now = Time.utc(2026, 9, 4, 20, 10, 0)
    expired = create_execution
    live = create_execution
    queued = create_execution
    expired.claim!(now: now - 120, lease_seconds: 60)
    live.claim!(now: now - 30, lease_seconds: 60)

    collector = Struct.new(:calls) do
      def perform_later(execution_id, expired_at)
        calls << [ execution_id, expired_at ]
      end
    end.new([])

    job = TestJob.new
    job.expiry_job_override = collector
    job.perform(now)

    assert_equal [ [ expired.id, now ] ], collector.calls
    assert_equal "running", expired.reload.status
    assert_equal "running", live.reload.status
    assert_equal "queued", queued.reload.status
  end

  private

  def create_execution
    PlywoExecution.create!(
      execution_id: "github-#{SecureRandom.hex(16)}",
      source: "github_pull_request",
      scenario_id: "dogfood.git.behavior",
      baseline_sha: "base-sha",
      candidate_sha: "head-sha",
      context: {}
    )
  end
end
