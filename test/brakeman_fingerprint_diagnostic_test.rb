require "test_helper"
require "json"
require "open3"

class BrakemanFingerprintDiagnosticTest < ActiveSupport::TestCase
  test "prints the exact service executor warning fingerprint" do
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

    assert_equal 1, warnings.length, "Expected exactly one ServiceExecutor Execute warning: #{warnings.inspect}"

    warning = warnings.fetch(0)
    flunk "BRAKEMAN_SERVICE_EXECUTOR_FINGERPRINT=#{warning.fetch("fingerprint")}\n#{JSON.pretty_generate(warning)}"
  end
end
