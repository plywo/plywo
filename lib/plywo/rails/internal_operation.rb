module Plywo
  module Rails
    module InternalOperation
      DEPTH_KEY = :plywo_internal_operation_depth
      STARTED_AT_KEY = :plywo_internal_operation_started_at
      ELAPSED_KEY = :plywo_internal_operation_elapsed_seconds

      class << self
        def call
          previous_depth = depth
          start_outer_operation if previous_depth.zero?
          ActiveSupport::IsolatedExecutionState[DEPTH_KEY] = previous_depth + 1
          yield
        ensure
          finish_outer_operation if previous_depth.to_i.zero?
          restore_depth(previous_depth)
        end

        def active?
          depth.positive?
        end

        def elapsed_seconds
          accumulated = ActiveSupport::IsolatedExecutionState[ELAPSED_KEY].to_f
          return accumulated unless active?

          started_at = ActiveSupport::IsolatedExecutionState[STARTED_AT_KEY]
          return accumulated unless started_at

          accumulated + (monotonic_time - started_at)
        end

        private

        def depth
          ActiveSupport::IsolatedExecutionState[DEPTH_KEY].to_i
        end

        def start_outer_operation
          ActiveSupport::IsolatedExecutionState[STARTED_AT_KEY] = monotonic_time
        end

        def finish_outer_operation
          started_at = ActiveSupport::IsolatedExecutionState.delete(STARTED_AT_KEY)
          return unless started_at

          elapsed = ActiveSupport::IsolatedExecutionState[ELAPSED_KEY].to_f
          ActiveSupport::IsolatedExecutionState[ELAPSED_KEY] = elapsed + (monotonic_time - started_at)
        end

        def restore_depth(previous_depth)
          if previous_depth.to_i.zero?
            ActiveSupport::IsolatedExecutionState.delete(DEPTH_KEY)
          else
            ActiveSupport::IsolatedExecutionState[DEPTH_KEY] = previous_depth
          end
        end

        def monotonic_time
          Process.clock_gettime(Process::CLOCK_MONOTONIC)
        end
      end
    end
  end
end
