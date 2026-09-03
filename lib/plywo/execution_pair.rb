module Plywo
  class ExecutionPair
    def self.call(baseline:, candidate:)
      new(baseline:, candidate:).call
    end

    def initialize(baseline:, candidate:)
      @baseline = stringify_keys(baseline)
      @candidate = stringify_keys(candidate)
    end

    def call
      validate_identity!

      {
        "schema_version" => "1",
        "run_id" => @baseline.fetch("run_id"),
        "scenario_id" => @baseline.fetch("scenario_id"),
        "executions" => {
          "baseline" => @baseline,
          "candidate" => @candidate
        },
        "result" => BehavioralDiff.call(
          baseline: @baseline.fetch("measurements"),
          candidate: @candidate.fetch("measurements")
        )
      }
    end

    private

    def validate_identity!
      return if @baseline.fetch("run_id") == @candidate.fetch("run_id") &&
        @baseline.fetch("scenario_id") == @candidate.fetch("scenario_id")

      raise ArgumentError, "baseline and candidate must share run_id and scenario_id"
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
    end
  end
end
