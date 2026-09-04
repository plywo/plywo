class PlywoExecution < ApplicationRecord
  ACTIVE_STATUSES = %w[queued running finalizing].freeze
  CANCELLABLE_STATUSES = %w[queued running].freeze
  LEASED_STATUSES = %w[running finalizing].freeze
  IGNORABLE_STATUSES = (ACTIVE_STATUSES + [ "failed" ]).freeze
  TERMINAL_STATUSES = %w[completed ignored failed cancelled].freeze
  STATUSES = (ACTIVE_STATUSES + TERMINAL_STATUSES).freeze
  OUTCOMES = %w[allow review block infra_failure stale manual_review_required cancelled].freeze
  DEFAULT_LEASE_SECONDS = 30.minutes.to_i

  validates :execution_id, :source, :scenario_id, :baseline_sha, :candidate_sha, :status, presence: true
  validates :execution_id, uniqueness: true
  validates :status, inclusion: { in: STATUSES }
  validates :outcome, inclusion: { in: OUTCOMES }, allow_nil: true

  def self.lease_seconds
    Integer(ENV.fetch("PLYWO_EXECUTION_LEASE_SECONDS", DEFAULT_LEASE_SECONDS))
  end

  def claim!(now: Time.current, lease_seconds: self.class.lease_seconds)
    claimed = self.class.where(id:, status: "queued").update_all(
      status: "running",
      started_at: now,
      heartbeat_at: now,
      lease_expires_at: now + lease_seconds,
      finished_at: nil,
      failure: nil,
      outcome: nil,
      cancellation_reason: nil,
      cancelled_at: nil,
      attempt_count: attempt_count + 1,
      updated_at: now
    )

    reload if claimed == 1
    claimed == 1
  end

  def renew_lease!(now: Time.current, lease_seconds: self.class.lease_seconds)
    renewed = self.class
      .where(id:, status: LEASED_STATUSES)
      .where("lease_expires_at > ?", now)
      .update_all(
        heartbeat_at: now,
        lease_expires_at: now + lease_seconds,
        updated_at: now
      )

    reload if renewed == 1
    renewed == 1
  end

  def lease_expired?(at: Time.current)
    LEASED_STATUSES.include?(status) && lease_expires_at.present? && lease_expires_at <= at
  end

  def expire_lease!(now: Time.current)
    expired = self.class
      .where(id:, status: LEASED_STATUSES)
      .where("lease_expires_at <= ?", now)
      .update_all(
        status: "failed",
        outcome: "infra_failure",
        failure: "Plywo::Executor::LeaseExpired: executor did not finalize before its lease expired",
        lease_expires_at: nil,
        finished_at: now,
        updated_at: now
      )

    reload if expired == 1
    expired == 1
  end

  def begin_finalization!(attempt_number:, now: Time.current)
    finalizing = self.class
      .where(id:, status: "running", attempt_count: Integer(attempt_number))
      .where("lease_expires_at > ?", now)
      .update_all(status: "finalizing", updated_at: now)

    reload if finalizing == 1
    finalizing == 1
  end

  def cancel!(attempt_number: nil, reason: "cancelled", now: Time.current)
    scope = self.class.where(id:, status: CANCELLABLE_STATUSES)
    scope = scope.where(attempt_count: Integer(attempt_number)) unless attempt_number.nil?

    cancelled = scope.update_all(
      status: "cancelled",
      outcome: "cancelled",
      decision: nil,
      result: {},
      failure: nil,
      cancellation_reason: reason.to_s,
      cancelled_at: now,
      lease_expires_at: nil,
      finished_at: now,
      updated_at: now
    )

    reload if cancelled == 1
    cancelled == 1
  end

  def complete!(payload, now: Time.current)
    decision = payload.dig("result", "decision")
    completed = self.class.where(id:, status: LEASED_STATUSES).update_all(
      status: "completed",
      decision:,
      outcome: behavioral_outcome(payload),
      result: payload,
      failure: nil,
      lease_expires_at: nil,
      finished_at: now,
      updated_at: now
    )

    reload if completed == 1
    completed == 1
  end

  def ignore!(reason, now: Time.current)
    reason = reason.to_s
    outcome = reason.start_with?("stale") ? "stale" : "manual_review_required"
    ignored = self.class.where(id:, status: IGNORABLE_STATUSES).update_all(
      status: "ignored",
      outcome:,
      failure: reason,
      lease_expires_at: nil,
      finished_at: now,
      updated_at: now
    )

    reload if ignored == 1
    ignored == 1
  end

  def fail!(error, now: Time.current)
    fail_details!(error_class: error.class.to_s, error_message: error.message, now:)
  end

  def fail_details!(error_class:, error_message:, now: Time.current)
    message = "#{error_class}: #{error_message}".truncate(2_000)
    failed = self.class.where(id:, status: ACTIVE_STATUSES).update_all(
      status: "failed",
      outcome: "infra_failure",
      failure: message,
      lease_expires_at: nil,
      finished_at: now,
      updated_at: now
    )

    reload if failed == 1
    failed == 1
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
      cancellation_reason: nil,
      cancelled_at: nil,
      started_at: nil,
      heartbeat_at: nil,
      lease_expires_at: nil,
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
