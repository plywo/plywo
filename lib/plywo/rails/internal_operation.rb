module Plywo
  module Rails
    module InternalOperation
      DEPTH_KEY = :plywo_internal_operation_depth

      class << self
        def call
          previous_depth = depth
          ActiveSupport::IsolatedExecutionState[DEPTH_KEY] = previous_depth + 1
          yield
        ensure
          restore(previous_depth)
        end

        def active?
          depth.positive?
        end

        private

        def depth
          ActiveSupport::IsolatedExecutionState[DEPTH_KEY].to_i
        end

        def restore(previous_depth)
          if previous_depth.to_i.zero?
            ActiveSupport::IsolatedExecutionState.delete(DEPTH_KEY)
          else
            ActiveSupport::IsolatedExecutionState[DEPTH_KEY] = previous_depth
          end
        end
      end
    end
  end
end
