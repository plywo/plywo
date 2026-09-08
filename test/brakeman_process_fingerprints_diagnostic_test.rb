require "test_helper"
require "json"
require "open3"

class BrakemanProcessFingerprintsDiagnosticTest < ActiveSupport::TestCase
  test "prints the exact process executor warning fingerprints" do
    stdout, stderr, status = Open3.capture3(
      "bundle", "exec", "brakeman",
      "--quiet",
      "--format", "json",
      "--no-exit-on-warn"
    )

    assert status.success?, "Brakeman diagnostic scan failed: #{stderr}"

    report = JSON.parse(stdout)
    warnings = report.fetch("warnings").select do |warning|
      warning.fetch("check_name") == "Execute" &&
        warning.fetch("file") == "lib/plywo/subject/service_executor.rb"
    end

    assert_equal 2, warnings.length,
      "Expected exactly two visible ServiceExecutor Execute warnings: #{warnings.inspect}"

    diagnostic = warnings.map do |warning|
      {
        "fingerprint" => warning.fetch("fingerprint"),
        "line" => warning.fetch("line"),
        "code" => warning.fetch("code")
      }
    end

    flunk "BRAKEMAN_PROCESS_EXECUTOR_FINGERPRINTS=#{JSON.generate(diagnostic)}"
  end
end
