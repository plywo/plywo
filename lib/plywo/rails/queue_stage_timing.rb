module Plywo
  module Rails
    class QueueStageTiming
      def self.call(enqueued_at:, started_at:, scheduled_at: nil)
        return unavailable unless enqueued_at && started_at

        queue_wait_ms = milliseconds(started_at - enqueued_at)
        declared_schedule_ms = scheduled_at ? milliseconds(scheduled_at - enqueued_at) : 0.0
        scheduled_delay_ms = [ [ declared_schedule_ms, 0.0 ].max, queue_wait_ms ].min
        dispatch_wait_ms = [ queue_wait_ms - scheduled_delay_ms, 0.0 ].max.round(1)

        {
          "queue_wait_ms" => queue_wait_ms,
          "scheduled_delay_ms" => scheduled_delay_ms.round(1),
          "dispatch_wait_ms" => dispatch_wait_ms
        }
      end

      def self.milliseconds(seconds)
        [ seconds.to_f * 1000.0, 0.0 ].max.round(1)
      end
      private_class_method :milliseconds

      def self.unavailable
        {
          "queue_wait_ms" => nil,
          "scheduled_delay_ms" => nil,
          "dispatch_wait_ms" => nil
        }
      end
      private_class_method :unavailable
    end
  end
end
