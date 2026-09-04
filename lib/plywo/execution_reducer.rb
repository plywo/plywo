module Plywo
  class ExecutionReducer
    COUNTABLE_SIGNALS = BehavioralDiff::SIGNALS.keys.reject { |signal| signal == "duration_ms" }.freeze

    def self.call(execution:)
      new(execution:).call
    end

    def initialize(execution:)
      @execution = deep_stringify_keys(execution)
    end

    def call
      measurements = @execution.fetch("measurements").dup
      attributions = normalized_attributions(@execution.fetch("attributions", {}))

      durable_observations.each do |observation|
        signal = observation.fetch("signal")
        measurements[signal] = measurements.fetch(signal, 0).to_f + 1 if COUNTABLE_SIGNALS.include?(signal)
        append_attribution(attributions, signal, observation)
      end

      normalize_numeric_measurements!(measurements)

      @execution.merge(
        "measurements" => measurements,
        "attributions" => attributions,
        "evidence" => {
          "foreground" => true,
          "durable_observations" => durable_observations.size
        }
      )
    end

    private

    def durable_observations
      @durable_observations ||= Array(@execution["durable_observations"]).map { |observation| deep_stringify_keys(observation) }
    end

    def append_attribution(attributions, signal, observation)
      return unless observation["path"] && observation["start_line"] && observation["end_line"]

      location = {
        "path" => observation.fetch("path"),
        "start_line" => Integer(observation.fetch("start_line")),
        "end_line" => Integer(observation.fetch("end_line")),
        "confidence" => observation.fetch("confidence", "runtime")
      }
      attributions[signal] ||= []
      attributions[signal] << location unless attributions[signal].include?(location)
    end

    def normalized_attributions(attributions)
      attributions.each_with_object({}) do |(signal, locations), result|
        result[signal.to_s] = Array(locations).map { |location| deep_stringify_keys(location) }
      end
    end

    def normalize_numeric_measurements!(measurements)
      measurements.each do |signal, value|
        next unless COUNTABLE_SIGNALS.include?(signal)
        next unless value.is_a?(Float) && value.to_i == value

        measurements[signal] = value.to_i
      end
    end

    def deep_stringify_keys(value)
      case value
      when Hash
        value.each_with_object({}) do |(key, nested), result|
          result[key.to_s] = deep_stringify_keys(nested)
        end
      when Array
        value.map { |nested| deep_stringify_keys(nested) }
      else
        value
      end
    end
  end
end
