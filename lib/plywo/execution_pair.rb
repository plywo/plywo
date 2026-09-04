module Plywo
  class ExecutionPair
    def self.call(baseline:, candidate:, changed_paths: [])
      new(baseline:, candidate:, changed_paths:).call
    end

    def initialize(baseline:, candidate:, changed_paths: [])
      @baseline = stringify_keys(baseline)
      @candidate = stringify_keys(candidate)
      @changed_paths = Array(changed_paths).map(&:to_s)
    end

    def call
      validate_identity!
      result = BehavioralDiff.call(
        baseline: @baseline.fetch("measurements"),
        candidate: @candidate.fetch("measurements")
      )
      attach_trusted_sources!(result)

      {
        "schema_version" => "1",
        "run_id" => @baseline.fetch("run_id"),
        "scenario_id" => @baseline.fetch("scenario_id"),
        "executions" => {
          "baseline" => @baseline,
          "candidate" => @candidate
        },
        "result" => result
      }
    end

    private

    def validate_identity!
      return if @baseline.fetch("run_id") == @candidate.fetch("run_id") &&
        @baseline.fetch("scenario_id") == @candidate.fetch("scenario_id")

      raise ArgumentError, "baseline and candidate must share run_id and scenario_id"
    end

    def attach_trusted_sources!(result)
      attributions = @candidate.fetch("attributions", {})

      result.fetch("findings").each do |finding|
        locations = attributions.fetch(finding.fetch("signal"), [])
        source = locations.find do |location|
          location.fetch("confidence", nil) == "explicit" && @changed_paths.include?(location.fetch("path", nil))
        end
        finding["source"] = source if source
      end
    end

    def stringify_keys(hash)
      hash.each_with_object({}) { |(key, value), result| result[key.to_s] = value }
    end
  end
end
