module Plywo
  module Rails
    class DurableEvidenceBuffer
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
          InternalOperation.active?
        end

        private

        def event_attributes(payload, producer_kind:, producer_name:, producer_id:)
          source = payload[:source] || {}
          now = Time.current

          event_row(
            execution_id: payload.fetch(:execution_id),
            run_id: payload[:run_id],
            subject: payload[:subject],
            signal: payload.fetch(:signal),
            path: source[:path],
            start_line: source[:start_line],
            end_line: source[:end_line],
            confidence: source[:confidence],
            payload: payload[:attributes] || {},
            producer_kind:,
            producer_name:,
            producer_id:,
            occurred_at: payload[:occurred_at] || now,
            now:
          )
        end

        def error_attributes(execution_id:, producer_kind:, producer_name:, producer_id:, error:)
          now = Time.current

          event_row(
            execution_id:,
            run_id: Current.plywo_run_id,
            subject: Current.plywo_subject,
            signal: "errors",
            path: nil,
            start_line: nil,
            end_line: nil,
            confidence: nil,
            payload: { "error_class" => error.class.name },
            producer_kind:,
            producer_name:,
            producer_id:,
            occurred_at: now,
            now:
          )
        end

        def event_row(execution_id:, run_id:, subject:, signal:, path:, start_line:, end_line:, confidence:,
                      payload:, producer_kind:, producer_name:, producer_id:, occurred_at:, now:)
          {
            execution_id: execution_id.to_s,
            run_id: run_id&.to_s,
            subject: subject&.to_s,
            signal: signal.to_s,
            path: path&.to_s,
            start_line:,
            end_line:,
            confidence: confidence&.to_s,
            payload:,
            producer_kind: producer_kind.to_s,
            producer_name: producer_name.to_s,
            producer_id: producer_id&.to_s,
            occurred_at:,
            created_at: now,
            updated_at: now
          }
        end

        def persist(events)
          InternalOperation.call do
            PlywoEvidenceEvent.insert_all!(events)
          end
        end
      end
    end
  end
end
