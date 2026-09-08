require "test_helper"
require "json"
require "open3"
require "tempfile"

class BrakemanFingerprintDiagnosticTest < ActiveSupport::TestCase
  test "prints the exact service executor warning fingerprints" do
    Tempfile.create([ "brakeman-empty-ignore", ".json" ]) do |ignore|
      ignore.write(JSON.generate("ignored_warnings" => [], "brakeman_version" => "8.0.6"))
      ignore.flush

      stdout, stderr, status = Open3.capture3(
        "bundle", "exec", "brakeman",
        "--quiet",
        "--format", "json",
        "--no-exit-on-warn",
        "--ignore-config", ignore.path
      )

      assert status.success?, "Brakeman diagnostic scan failed: #{stderr}"

      report = JSON.parse(stdout)
      warnings = report.fetch("warnings").select do |warning|
        warning.fetch("check_name") == "Execute" &&
          warning.fetch("file") == "lib/plywo/subject/service_executor.rb"
      end

      assert_equal 2, warnings.length,
        "Expected exactly two ServiceExecutor Execute warnings: #{warnings.inspect}"

      details = warnings.map do |warning|
        runtime = warning.fetch("code").include?("RbConfig.ruby") ? "RUBY" : "NODE"
        "BRAKEMAN_SERVICE_EXECUTOR_#{runtime}_FINGERPRINT=#{warning.fetch("fingerprint")}"
      end.sort

      flunk "#{details.join("\n")}\n#{JSON.pretty_generate(warnings)}"
    end
  end
end
