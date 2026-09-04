class PlywoExecution < ApplicationRecord
  ACTIVE_STATUSES = %w[queued running].freeze
  TERMINAL_STATUSES = %w[completed ignored failed].freeze
  STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze
  OUTCOMES = %w[allow review block infra_failure stale manual_review_required].freeze

  validates :execution_id, :source, :scenario_id, :baseline_sha, :candidate_sha, :status, presence: true
  validates :execution_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  def claim!
    claimed = self.class.where(id:, status: "queued").update_all(
      status: "running",
      started_at: Time.current,
      finished_at: nil,
      failure: nil,
      outcome: nil,
      attempt_count: attempt_count + 1,
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
      outcome: behavioral_outcome(payload),
      result: payload,
      failure: nil,
      finished_at: Time.current
    )
  end

  def ignore!(reason)
    reason = reason.to_s
    outcome = reason.start_with?("stale") ? "stale" : "manual_review_required"
    update!(status: "ignored", outcome:, failure: reason, finished_at: Time.current)
  end

  def fail!(error)
    message = "#{error.class}: #{error.message}".truncate(2_000)
    update!(status: "failed", outcome: "infra_failure", failure: message, finished_at: Time.current)
  end

  def rerunnable?
    status == "failed" && outcome == "infra_failure"
  end

  def requeue!
    requeued = self.class.where(id:, status: "failed", outcome: "infra_failure").update_all(
      status: "queued",
      outcome: nil,
      decision: nil,
      result: {},
      failure: nil,
      started_at: nil,
      finished_at: nil,
      updated_at: Time.current
    )

    reload if requeued == 1
    requeued == 1
  end

  private

  def behavioral_outcome(payload)
    recommendation = payload.dig("result", "merge_recommendation") || payload.dig("result", "decision")

    case recommendation
    when "allow", "no_regression" then "allow"
    when "review" then "review"
    when "block", "regression" then "block"
    else "manual_review_required"
    end
  end
end
