require "pathname"

module Plywo
  module Subject
    class RailsCaptureRuntime
      SUBJECT_OWNED_MARKERS = [
        "lib/plywo/rails/evidence_collector.rb",
        "lib/plywo/rails/execution_quiescence.rb",
        "app/models/current.rb",
        "app/models/plywo_evidence_event.rb",
        "app/models/plywo_execution_work_item.rb"
      ].freeze

      def script_for(root:, tool_root:)
        root = Pathname(root).expand_path
        tool_root = Pathname(tool_root).expand_path

        if subject_owned?(root)
          tool_root.join("script", "plywo_capture_subject.rb")
        else
          tool_root.join("script", "plywo_capture_portable_rails.rb")
        end
      end

      def mode_for(root:)
        subject_owned?(Pathname(root).expand_path) ? "subject_owned_rails" : "tool_owned_portable_rails"
      end

      private

      def subject_owned?(root)
        SUBJECT_OWNED_MARKERS.all? { |relative_path| root.join(relative_path).file? }
      end
    end
  end
end
