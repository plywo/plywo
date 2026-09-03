module Plywo
  module Rails
    module Evidence
      EVENT_NAME = "plywo.side_effect"

      def self.side_effect(type, **attributes)
        ActiveSupport::Notifications.instrument(
          EVENT_NAME,
          attributes.merge(type: type.to_s, execution_id: Current.plywo_execution_id)
        )
      end
    end
  end
end
