module Plywo
  module Github
    class CommentRenderer
      MARKER = "<!-- plywo:behavioral-diff:v1 -->".freeze
      SIGNAL_LABELS = {
        "duration_ms" => "Request time",
        "sql_queries" => "SQL queries",
        "background_jobs" => "Background jobs",
        "emails" => "Emails",
        "http_requests" => "HTTP requests",
        "errors" => "Runtime errors"
      }.freeze
      SEVERITY_ICONS = {
        "critical" => "🔴",
        "high" => "🔴",
        "medium" => "🟠",
        "low" => "🟡"
      }.freeze

      def self.markdown(payload:, context: {})
        new(payload:, context:).markdown
      end

      def initialize(payload:, context: {})
        @payload = payload
        @context = context.transform_keys(&:to_s)
      end

      def markdown
        lines = [ MARKER, "## 🟣 Plywo · Behavioral Review", "", summary_callout, "" ]
        lines.concat(signal_table)
        lines.concat(findings_section)
        lines.concat(execution_section)
        lines.concat(bootstrap_note) if bootstrap_baseline?
        lines.concat(footer)
        lines.join("\n")
      end

      private

      def result
        @payload.fetch("result")
      end

      def findings
        result.fetch("findings")
      end

      def executions
        @payload.fetch("executions")
      end

      def summary_callout
        if findings.empty?
          "> [!TIP]\n> **No behavioral regression detected.** Merge recommendation: **ALLOW**."
        else
          counts = findings.group_by { |finding| finding.fetch("severity") }.transform_values(&:size)
          severity_summary = %w[critical high medium low].filter_map do |severity|
            "#{counts.fetch(severity)} #{severity}" if counts.key?(severity)
          end.join(" · ")

          "> [!WARNING]\n> **Behavior changed while the functional scenario still passes.** " \
            "Merge recommendation: **#{result.fetch("merge_recommendation").upcase}** · " \
            "#{findings.size} regressions · #{severity_summary}."
        end
      end

      def signal_table
        lines = [
          "| Signal | Baseline | PR candidate | Change | Verdict |",
          "| --- | ---: | ---: | ---: | --- |"
        ]

        result.fetch("signals").each do |signal, values|
          verdict = values.fetch("regression") ? "⚠️ Regression" : "✅ Stable"
          lines << "| **#{SIGNAL_LABELS.fetch(signal, signal)}** | #{format_value(signal, values.fetch("baseline"))} | " \
            "#{format_value(signal, values.fetch("candidate"))} | **#{values.fetch("display_delta")}** | #{verdict} |"
        end

        [ "### Runtime diff", "", *lines, "" ]
      end

      def findings_section
        return [] if findings.empty?

        lines = [ "<details open>", "<summary><strong>Findings</strong> · #{findings.size} detected</summary>", "" ]
        findings.each do |finding|
          severity = finding.fetch("severity")
          signal = finding.fetch("signal")
          lines << "- #{SEVERITY_ICONS.fetch(severity, "⚪")} **#{severity.upcase}** · " \
            "`#{finding.fetch("reason_code")}` · **#{SIGNAL_LABELS.fetch(signal, signal)}** · " \
            "#{format_value(signal, finding.fetch("baseline"))} → #{format_value(signal, finding.fetch("candidate"))} " \
            "(#{display_percent(finding.fetch("delta_percent"))})"
        end
        lines.concat([ "", "</details>", "" ])
      end

      def execution_section
        baseline = executions.fetch("baseline")
        candidate = executions.fetch("candidate")

        [
          "<details>",
          "<summary><strong>Execution context</strong></summary>",
          "",
          "| Subject | Ref | SHA | Functional | Correlation |",
          "| --- | --- | --- | --- | --- |",
          "| Baseline | `#{context("baseline_label", "dogfood baseline")}` | `#{short_sha(context("baseline_sha", "synthetic"))}` | " \
            "#{status_icon(baseline)} | #{correlation_icon(baseline)} |",
          "| Candidate | `#{context("candidate_label", "candidate")}` | `#{short_sha(context("candidate_sha", "unknown"))}` | " \
            "#{status_icon(candidate)} | #{correlation_icon(candidate)} |",
          "",
          "Run: `#{@payload.fetch("run_id")}`  ",
          "Scenario: `#{@payload.fetch("scenario_id")}`",
          "",
          "</details>",
          ""
        ]
      end

      def bootstrap_note
        [
          "> [!NOTE]",
          "> This is the bootstrap dogfood run. The PR base currently has no runnable Rails subject, so the baseline execution is a deterministic baseline profile, not a process started from `main`. Git base/head SHAs are still attached. Once this PR lands, subsequent PRs can run executable `main` vs PR head directly.",
          ""
        ]
      end

      def footer
        links = []
        links << "[Actions run](#{context("run_url")})" if context("run_url")
        links << "`#{context("repository")}`" if context("repository")
        links << "PR ##{context("pr_number")}" if context("pr_number")

        [ "---", "<sub>#{([ "Plywo v0.0.1" ] + links).join(" · ")}</sub>" ]
      end

      def format_value(signal, value)
        signal == "duration_ms" ? format("%.1f ms", value) : value.to_i.to_s
      end

      def display_percent(value)
        value.positive? ? "+#{value}%" : "#{value}%"
      end

      def status_icon(execution)
        execution.fetch("status") == "passed" ? "✅ passed" : "❌ failed"
      end

      def correlation_icon(execution)
        execution.fetch("correlation_confirmed") ? "✅ confirmed" : "❌ missing"
      end

      def short_sha(value)
        value.to_s == "synthetic" ? value : value.to_s[0, 8]
      end

      def bootstrap_baseline?
        context("bootstrap_baseline") == true || context("bootstrap_baseline") == "1"
      end

      def context(key, fallback = nil)
        @context.fetch(key, fallback)
      end
    end
  end
end
