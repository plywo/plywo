class GithubWebhookDelivery < ApplicationRecord
  STATUSES = %w[accepted processing completed ignored failed].freeze
  RUNNABLE_PULL_REQUEST_ACTIONS = %w[opened reopened synchronize ready_for_review].freeze

  validates :delivery_id, :event, :status, presence: true
  validates :delivery_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  def pull_request?
    event == "pull_request"
  end

  def runnable_pull_request?
    pull_request? && action.in?(RUNNABLE_PULL_REQUEST_ACTIONS)
  end

  def claim!
    claimed = self.class.where(id:, status: "accepted").update_all(
      status: "processing",
      started_at: Time.current,
      finished_at: nil,
      failure: nil,
      updated_at: Time.current
    )

    reload if claimed == 1
    claimed == 1
  end

  def complete!
    update!(status: "completed", finished_at: Time.current, failure: nil)
  end

  def ignore!(reason)
    update!(status: "ignored", finished_at: Time.current, failure: reason.to_s)
  end

  def fail!(error)
    message = "#{error.class}: #{error.message}".truncate(2_000)
    update!(status: "failed", failure: message, finished_at: Time.current)
  end
end
