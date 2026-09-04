module Plywo
  module Github
    class CheckRenderer
      NAME = "Plywo / Behavioral Diff".freeze
      CONCLUSIONS = {
        "allow" => "success",
        "review" => "neutral",
        "block" => "failure"
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
          "summary" => summary
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

      def decision_line
        recommendation = result.fetch("merge_recommendation").upcase
        return "**#{recommendation}** - no behavioral regression detected." if findings.empty?

        label = findings.one? ? "regression" : "regressions"
        "**#{recommendation}** - #{findings.size} behavioral #{label} detected."
      end

      def format_value(signal, value)
        signal == "duration_ms" ? format("%.1f ms", value) : value.to_i.to_s
      end
    end
  end
end
