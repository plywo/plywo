class GithubPullRequestExecutionLeaseReaperJob < ApplicationJob
  queue_as :default

  def perform(now = Time.current)
    PlywoExecution
      .where(source: "github_pull_request", status: "running")
      .where("lease_expires_at <= ?", now)
      .find_each do |execution|
        expiry_job_class.perform_later(execution.id, now)
      end
  end

  private

  def expiry_job_class
    GithubPullRequestExecutionLeaseExpiryJob
  end
end
