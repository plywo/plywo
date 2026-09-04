module Plywo
  module Rails
    module Evidence
      EVENT_NAME = "plywo.side_effect"
      ATTRIBUTION_EVENT_NAME = "plywo.attribution"

      def self.side_effect(type, **attributes)
        ActiveSupport::Notifications.instrument(
          EVENT_NAME,
          attributes.merge(type: type.to_s, execution_id: Current.plywo_execution_id)
        )
      end

      def self.attribute_next_line(signal, path:, confidence: "explicit")
        source = caller_locations(1, 1).first
        attribute(
          signal,
          path:,
          line: source.lineno + 1,
          confidence:
        )
      end

      def self.attribute(signal, path:, line:, confidence: "explicit")
        ActiveSupport::Notifications.instrument(
          ATTRIBUTION_EVENT_NAME,
          signal: signal.to_s,
          path: path.to_s,
          start_line: Integer(line),
          end_line: Integer(line),
          confidence: confidence.to_s,
          execution_id: Current.plywo_execution_id
        )
      end
    end
  end
end
