module Plywo
  class BehavioralDiff
    SIGNALS = {
      "duration_ms" => {
        reason_code: "PERFORMANCE_REGRESSION",
        threshold_percent: 20.0,
        threshold_absolute: 20.0,
        severity: "high"
      },
      "sql_queries" => { reason_code: "DATABASE_QUERY_REGRESSION", threshold_percent: 25.0, severity: "high" },
      "background_jobs" => { reason_code: "SIDE_EFFECT_CHANGED", threshold_absolute: 0, severity: "medium" },
      "emails" => { reason_code: "SIDE_EFFECT_CHANGED", threshold_absolute: 0, severity: "high" },
      "http_requests" => { reason_code: "NETWORK_BEHAVIOR_CHANGED", threshold_percent: 25.0, severity: "medium" },
      "errors" => { reason_code: "NEW_RUNTIME_ERROR", threshold_absolute: 0, severity: "critical" }
    }.freeze

    def self.call(baseline:, candidate:)
      new(baseline:, candidate:).call
    end

    def initialize(baseline:, candidate:)
      @baseline = stringify_keys(baseline)
      @candidate = stringify_keys(candidate)
    end

    def call
      signals = {}
      findings = []

      SIGNALS.each do |signal, policy|
        baseline_value = numeric(@baseline.fetch(signal, 0))
        candidate_value = numeric(@candidate.fetch(signal, 0))
        delta = candidate_value - baseline_value
        delta_percent = percent_change(baseline_value, candidate_value)
        regression = regression?(baseline_value, candidate_value, policy)

        signals[signal] = {
          "baseline" => baseline_value,
          "candidate" => candidate_value,
          "delta" => delta,
          "delta_percent" => delta_percent,
          "display_delta" => display_delta(delta, delta_percent),
          "regression" => regression
        }

        next unless regression

        findings << {
          "type" => "behavioral_regression",
          "reason_code" => policy.fetch(:reason_code),
          "severity" => policy.fetch(:severity),
          "signal" => signal,
          "baseline" => baseline_value,
          "candidate" => candidate_value,
          "delta" => delta,
          "delta_percent" => delta_percent
        }
      end

      {
        "schema_version" => "1",
        "status" => "completed",
        "decision" => findings.empty? ? "no_regression" : "regression",
        "merge_recommendation" => block_merge?(findings) ? "block" : (findings.empty? ? "allow" : "review"),
        "signals" => signals,
        "findings" => findings,
        "recommended_action" => recommended_action(findings)
      }
    end

    private

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
    end

    def numeric(value)
      return value if value.is_a?(Numeric)

      Float(value)
    rescue ArgumentError, TypeError
      0
    end

    def percent_change(baseline, candidate)
      return 0.0 if baseline.zero? && candidate.zero?
      return 100.0 if baseline.zero? && candidate.positive?

      (((candidate - baseline) / baseline.to_f) * 100).round(1)
    end

    def regression?(baseline, candidate, policy)
      return false unless candidate > baseline

      delta = candidate - baseline
      absolute_regression = !policy.key?(:threshold_absolute) || delta > policy.fetch(:threshold_absolute)
      percentage_regression = !policy.key?(:threshold_percent) ||
        percent_change(baseline, candidate) > policy.fetch(:threshold_percent)

      absolute_regression && percentage_regression
    end

    def display_delta(delta, delta_percent)
      return "unchanged" if delta.zero?

      sign = delta.positive? ? "+" : ""
      "#{sign}#{delta_percent}%"
    end

    def block_merge?(findings)
      findings.any? { |finding| %w[critical high].include?(finding.fetch("severity")) }
    end

    def recommended_action(findings)
      primary = findings.min_by do |finding|
        %w[critical high medium low].index(finding.fetch("severity")) || 99
      end

      return { "type" => "none" } unless primary

      {
        "type" => "investigate",
        "reason_code" => primary.fetch("reason_code"),
        "signal" => primary.fetch("signal")
      }
    end
  end
end
