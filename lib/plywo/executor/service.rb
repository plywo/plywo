module Plywo
  module Executor
    class Service
      Error = Class.new(StandardError)
      RequestConflict = Class.new(Error)
      RequestInProgress = Class.new(Error)
      ClaimLost = Class.new(Error)

      def initialize(adapter:, request_model: PlywoExecutorRequest, lease_seconds: nil)
        @adapter = adapter
        @request_model = request_model
        @lease_seconds = Integer(
          lease_seconds || ENV.fetch("PLYWO_EXECUTOR_SERVICE_REQUEST_LEASE_SECONDS", PlywoExecutorRequest::DEFAULT_LEASE_SECONDS)
        )
      end

      def call(idempotency_key:, request_payload:)
        request = Request.from_h(request_payload)
        canonical_payload = request.to_h
        acquisition = acquire(idempotency_key:, request_payload: canonical_payload)

        case acquisition.state
        when :completed
          Result.from_h(acquisition.record.result)
        when :in_progress
          raise RequestInProgress, "Executor request is already processing"
        when :execute
          execute_and_complete(acquisition:, request:)
        else
          raise Error, "Unsupported executor request acquisition state #{acquisition.state.inspect}"
        end
      end

      private

      def acquire(idempotency_key:, request_payload:)
        @request_model.acquire!(
          idempotency_key:,
          request_payload:,
          lease_seconds: @lease_seconds
        )
      rescue PlywoExecutorRequest::DigestMismatch => error
        raise RequestConflict, error.message
      end

      def execute_and_complete(acquisition:, request:)
        result = @adapter.call(request:)
        unless result.is_a?(Result)
          result = Result.failure(TypeError.new("Executor service adapter must return Plywo::Executor::Result"))
        end

        return result if acquisition.record.complete_claim!(
          claim_token: acquisition.claim_token,
          result_payload: result.to_h
        )

        current = @request_model.find(acquisition.record.id)
        return Result.from_h(current.result) if current.status == "completed"

        raise ClaimLost, "Executor request claim expired before completion"
      rescue StandardError => error
        raise if error.is_a?(Error)

        result = Result.failure(error)
        return result if acquisition.record.complete_claim!(
          claim_token: acquisition.claim_token,
          result_payload: result.to_h
        )

        raise ClaimLost, "Executor request claim expired while handling a worker failure"
      end
    end
  end
end
