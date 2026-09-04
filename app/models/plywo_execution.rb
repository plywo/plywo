class PlywoExecution < ApplicationRecord
  ACTIVE_STATUSES = %w[queued running].freeze
  TERMINAL_STATUSES = %w[completed ignored failed].freeze
  STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze

  validates :execution_id, :source, :scenario_id, :baseline_sha, :candidate_sha, :status, presence: true
  validates :execution_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }

  def claim!
    claimed = self.class.where(id:, status: "queued").update_all(
      status: "running",
      started_at: Time.current,
      finished_at: nil,
      failure: nil,
      updated_at: Time.current
    )

    reload if claimed == 1
    claimed == 1
  end

  def complete!(payload)
    decision = payload.dig("result", "decision")
    update!(
      status: "completed",
      decision:,
      result: payload,
      failure: nil,
      finished_at: Time.current
    )
  end

  def ignore!(reason)
    update!(status: "ignored", failure: reason.to_s, finished_at: Time.current)
  end

  def fail!(error)
    message = "#{error.class}: #{error.message}".truncate(2_000)
    update!(status: "failed", failure: message, finished_at: Time.current)
  end
end
