module Plywo
  class AsyncDeltaDiagnosis
    ENQUEUE_TO_START_DOMINANT_SHARE = 70.0
    WORKER_RUNTIME_DOMINANT_SHARE = 30.0

    def self.call(queue_wait:, worker_wall:)
      return unknown unless available?(queue_wait) && available?(worker_wall)

      queue_delta = numeric(queue_wait.fetch("delta"))
      worker_delta = numeric(worker_wall.fetch("delta"))
      return unknown if queue_delta.nil? || worker_delta.nil?

      unless queue_wait.fetch("regression", false) || worker_wall.fetch("regression", false)
        return no_regression(queue_delta:, worker_delta:)
      end

      positive_queue_delta = [ queue_delta, 0.0 ].max
      positive_worker_delta = [ worker_delta, 0.0 ].max
      positive_total = positive_queue_delta + positive_worker_delta
      return unknown if positive_total.zero?

      queue_share = ((positive_queue_delta / positive_total) * 100).round(1)
      classification = if queue_share >= ENQUEUE_TO_START_DOMINANT_SHARE
        "enqueue_to_start_regression"
      elsif queue_share <= WORKER_RUNTIME_DOMINANT_SHARE
        "worker_runtime_regression"
      else
        "mixed_async_regression"
      end

      {
        "classification" => classification,
        "queue_wait_delta_ms" => queue_delta.round(1),
        "worker_wall_delta_ms" => worker_delta.round(1),
        "positive_async_delta_ms" => positive_total.round(1),
        "enqueue_to_start_delta_share_percent" => queue_share,
        "dominant_delta_share_percent" => [ queue_share, 100.0 - queue_share ].max.round(1)
      }
    end

    def self.available?(signal)
      signal.fetch("available", true)
    end
    private_class_method :available?

    def self.no_regression(queue_delta:, worker_delta:)
      {
        "classification" => "no_async_regression",
        "queue_wait_delta_ms" => queue_delta.round(1),
        "worker_wall_delta_ms" => worker_delta.round(1),
        "positive_async_delta_ms" => [ [ queue_delta, 0.0 ].max + [ worker_delta, 0.0 ].max, 0.0 ].max.round(1),
        "enqueue_to_start_delta_share_percent" => nil,
        "dominant_delta_share_percent" => nil
      }
    end
    private_class_method :no_regression

    def self.unknown
      {
        "classification" => "unknown",
        "queue_wait_delta_ms" => nil,
        "worker_wall_delta_ms" => nil,
        "positive_async_delta_ms" => nil,
        "enqueue_to_start_delta_share_percent" => nil,
        "dominant_delta_share_percent" => nil
      }
    end
    private_class_method :unknown

    def self.numeric(value)
      return value.to_f if value.is_a?(Numeric)

      Float(value)
    rescue ArgumentError, TypeError
      nil
    end
    private_class_method :numeric
  end
end
