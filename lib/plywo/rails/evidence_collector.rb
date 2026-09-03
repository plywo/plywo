module Plywo
  module Rails
    class EvidenceCollector
      IGNORED_SQL_NAMES = %w[SCHEMA TRANSACTION CACHE].freeze

      def self.capture(execution_id:, &block)
        new(execution_id:).capture(&block)
      end

      def initialize(execution_id:)
        @execution_id = execution_id
        @measurements = {
          "sql_queries" => 0,
          "background_jobs" => 0,
          "emails" => 0,
          "http_requests" => 0,
          "errors" => 0
        }
      end

      def capture
        subscribers = subscribe
        started_at = monotonic_time
        yield
        @measurements.merge("duration_ms" => elapsed_ms(started_at))
      rescue StandardError
        @measurements["errors"] += 1
        raise
      ensure
        subscribers&.each { |subscriber| ActiveSupport::Notifications.unsubscribe(subscriber) }
      end

      private

      def subscribe
        [
          ActiveSupport::Notifications.subscribe("sql.active_record") { |event| record_sql(event.payload) },
          ActiveSupport::Notifications.subscribe("enqueue.active_job") { record_job },
          ActiveSupport::Notifications.subscribe("enqueue_at.active_job") { record_job },
          ActiveSupport::Notifications.subscribe("process_action.action_controller") { |event| record_request(event.payload) },
          ActiveSupport::Notifications.subscribe(Evidence::EVENT_NAME) { |event| record_side_effect(event.payload) }
        ]
      end

      def record_sql(payload)
        return unless current_execution?
        return if payload[:cached]
        return if IGNORED_SQL_NAMES.include?(payload[:name].to_s)

        @measurements["sql_queries"] += 1
      end

      def record_job
        @measurements["background_jobs"] += 1 if current_execution?
      end

      def record_request(payload)
        return unless current_execution?

        @measurements["http_requests"] += 1
        @measurements["errors"] += 1 if payload[:exception] || payload[:exception_object]
      end

      def record_side_effect(payload)
        return unless payload[:execution_id].to_s == @execution_id.to_s

        @measurements["emails"] += 1 if payload[:type].to_s == "email"
      end

      def current_execution?
        Current.plywo_execution_id.to_s == @execution_id.to_s
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end

      def elapsed_ms(started_at)
        ((monotonic_time - started_at) * 1000).round(1)
      end
    end
  end
end
