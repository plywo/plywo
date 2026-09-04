module Plywo
  module Rails
    class EvidenceCollector
      MEASUREMENT_SIGNALS = %w[sql_queries background_jobs emails http_requests errors].freeze

      attr_reader :attributions

      def self.capture(execution_id:, &block)
        new(execution_id:).capture(&block)
      end

      def initialize(execution_id:)
        @execution_id = execution_id
        @measurements = MEASUREMENT_SIGNALS.index_with(0)
        @attributions = Hash.new { |hash, key| hash[key] = [] }
      end

      def capture
        subscribers = subscribe
        started_at = monotonic_time
        internal_started_at = InternalOperation.elapsed_seconds
        yield
        @measurements.merge("duration_ms" => elapsed_ms(started_at, internal_started_at))
      rescue StandardError
        @measurements["errors"] += 1 if @measurements["errors"].zero?
        raise
      ensure
        subscribers&.each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
      end

      private

      def subscribe
        [
          ActiveSupport::Notifications.subscribe(Evidence::OBSERVATION_EVENT_NAME) { |event| record_observation(event.payload) },
          ActiveSupport::Notifications.subscribe(Evidence::ATTRIBUTION_EVENT_NAME) { |event| record_attribution(event.payload) }
        ]
      end

      def record_observation(payload)
        return unless payload[:execution_id].to_s == @execution_id.to_s

        signal = payload.fetch(:signal).to_s
        return unless MEASUREMENT_SIGNALS.include?(signal)

        @measurements[signal] += 1
        append_observation_source(signal, payload[:source])
      end

      def append_observation_source(signal, source)
        return unless source.respond_to?(:to_h)

        location = source.to_h.symbolize_keys
        return unless location[:path] && location[:start_line]

        append_attribution(
          signal,
          path: location.fetch(:path).to_s,
          start_line: Integer(location.fetch(:start_line)),
          end_line: Integer(location.fetch(:end_line, location.fetch(:start_line))),
          confidence: location.fetch(:confidence, "runtime").to_s
        )
      end

      def record_attribution(payload)
        return unless payload[:execution_id].to_s == @execution_id.to_s

        append_attribution(
          payload.fetch(:signal).to_s,
          path: payload.fetch(:path).to_s,
          start_line: Integer(payload.fetch(:start_line)),
          end_line: Integer(payload.fetch(:end_line)),
          confidence: payload.fetch(:confidence).to_s
        )
      end

      def append_attribution(signal, path:, start_line:, end_line:, confidence:)
        location = {
          "path" => path,
          "start_line" => start_line,
          "end_line" => end_line,
          "confidence" => confidence
        }
        @attributions[signal] << location unless @attributions[signal].include?(location)
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started_at, internal_started_at)
        wall_elapsed = monotonic_time - started_at
        internal_elapsed = InternalOperation.elapsed_seconds - internal_started_at
        product_elapsed = [ wall_elapsed - internal_elapsed, 0.0 ].max
        (product_elapsed * 1000).round(1)
      end
    end
  end
end
