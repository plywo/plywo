module Plywo
  module Rails
    class DurableEvidenceBuffer
      PERSISTING_KEY = :plywo_durable_evidence_persisting

      class << self
        def capture(execution_id:, producer_kind:, producer_name:, producer_id:)
          events = []
          subscriber = ActiveSupport::Notifications.subscribe(Evidence::OBSERVATION_EVENT_NAME) do |event|
            payload = event.payload
            next unless payload[:execution_id].to_s == execution_id.to_s

            events << event_attributes(
              payload,
              producer_kind:,
              producer_name:,
              producer_id:
            )
          end

          yield
        rescue StandardError => error
          events << error_attributes(
            execution_id:,
            producer_kind:,
            producer_name:,
            producer_id:,
            error:
          )
          raise
        ensure
          ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
          persist(events) if events&.any?
        end

        def persisting?
          ActiveSupport::IsolatedExecutionState[PERSISTING_KEY] == true
        end

        private

        def event_attributes(payload, producer_kind:, producer_name:, producer_id:)
          source = payload[:source] || {}
          now = Time.current

          {
            execution_id: payload.fetch(:execution_id).to_s,
            run_id: payload[:run_id]&.to_s,
            subject: payload[:subject]&.to_s,
            signal: payload.fetch(:signal).to_s,
            path: source[:path]&.to_s,
            start_line: source[:start_line],
            end_line: source[:end_line],
            confidence: source[:confidence]&.to_s,
            attributes: payload[:attributes] || {},
            producer_kind: producer_kind.to_s,
            producer_name: producer_name.to_s,
            producer_id: producer_id&.to_s,
            occurred_at: payload[:occurred_at] || now,
            created_at: now,
            updated_at: now
          }
        end

        def error_attributes(execution_id:, producer_kind:, producer_name:, producer_id:, error:)
          now = Time.current

          {
            execution_id: execution_id.to_s,
            signal: "errors",
            attributes: { "error_class" => error.class.name },
            producer_kind: producer_kind.to_s,
            producer_name: producer_name.to_s,
            producer_id: producer_id&.to_s,
            occurred_at: now,
            created_at: now,
            updated_at: now
          }
        end

        def persist(events)
          ActiveSupport::IsolatedExecutionState[PERSISTING_KEY] = true
          PlywoEvidenceEvent.insert_all!(events)
        ensure
          ActiveSupport::IsolatedExecutionState.delete(PERSISTING_KEY)
        end
      end
    end
  end
end
