module Plywo
  module Github
    class CheckRenderer
      NAME = "Plywo / Behavioral Diff".freeze
      CONCLUSIONS = {
        "allow" => "success",
        "review" => "neutral",
        "block" => "failure"
      }.freeze
      ANNOTATION_LEVELS = {
        "critical" => "failure",
        "high" => "failure",
        "medium" => "warning",
        "low" => "notice"
      }.freeze
      SIGNAL_LABELS = CommentRenderer::SIGNAL_LABELS

      def self.call(payload:, run_url: nil)
        new(payload:, run_url:).call
      end

      def initialize(payload:, run_url: nil)
        @payload = payload
        @run_url = run_url
      end

      def call
        {
          "name" => NAME,
          "conclusion" => CONCLUSIONS.fetch(result.fetch("merge_recommendation")),
          "title" => title,
          "summary" => summary,
          "annotations" => annotations
        }
      end

      private

      def result
        @payload.fetch("result")
      end

      def findings
        result.fetch("findings")
      end

      def title
        case result.fetch("merge_recommendation")
        when "allow"
          "No behavioral regression detected"
        when "review"
          "Behavior changed - review required"
        when "block"
          "Behavioral regression detected"
        end
      end

      def summary
        lines = [ decision_line ]
        lines << "[Open execution](#{@run_url})" if @run_url
        lines.concat([ "", "| Signal | Baseline | Candidate | Change |", "| --- | ---: | ---: | ---: |" ])

        result.fetch("signals").each do |signal, values|
          marker = values.fetch("regression") ? " ⚠️" : ""
          lines << "| #{SIGNAL_LABELS.fetch(signal, signal)} | #{format_value(signal, values.fetch("baseline"))} | " \
            "#{format_value(signal, values.fetch("candidate"))} | #{values.fetch("display_delta")}#{marker} |"
        end

        unless findings.empty?
          lines.concat([ "", "### Findings", "" ])
          findings.each do |finding|
            lines << "- **#{finding.fetch("severity").upcase}** - `#{finding.fetch("reason_code")}` - " \
              "#{SIGNAL_LABELS.fetch(finding.fetch("signal"), finding.fetch("signal"))}"
          end
        end

        lines.join("\n")
      end

      def annotations
        findings.filter_map do |finding|
          source = finding["source"]
          next unless source

          {
            "path" => source.fetch("path"),
            "start_line" => source.fetch("start_line"),
            "end_line" => source.fetch("end_line"),
            "annotation_level" => ANNOTATION_LEVELS.fetch(finding.fetch("severity"), "warning"),
            "title" => "Plywo: #{SIGNAL_LABELS.fetch(finding.fetch("signal"), finding.fetch("signal"))}",
            "message" => annotation_message(finding)
          }
        end.first(50)
      end

      def annotation_message(finding)
        signal = finding.fetch("signal")
        "#{finding.fetch("reason_code")}: #{SIGNAL_LABELS.fetch(signal, signal)} changed from " \
          "#{format_value(signal, finding.fetch("baseline"))} to #{format_value(signal, finding.fetch("candidate"))} " \
          "(#{display_percent(finding.fetch("delta_percent"))})."
      end

      def decision_line
        recommendation = result.fetch("merge_recommendation").upcase
        return "**#{recommendation}** - no behavioral regression detected." if findings.empty?

        label = findings.one? ? "regression" : "regressions"
        "**#{recommendation}** - #{findings.size} behavioral #{label} detected."
      end

      def format_value(signal, value)
        signal == "duration_ms" ? format("%.1f ms", value) : value.to_i.to_s
      end

      def display_percent(value)
        value.positive? ? "+#{value}%" : "#{value}%"
      end
    end
  end
end
