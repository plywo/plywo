require "test_helper"

class PlywoExecutorLocalAdapterTest < ActiveSupport::TestCase
  test "delegates the portable request to the existing local runner" do
    requests = []
    runner = Object.new
    runner.define_singleton_method(:call) do |execution:|
      requests << execution
      { "result" => { "decision" => "allow" } }
    end

    request = Plywo::Executor::Request.new(
      schema_version: "1",
      execution_id: "github-123",
      scenario_id: "scenario",
      baseline_sha: "base",
      candidate_sha: "head",
      attempt_number: 1,
      context: {}
    )

    result = Plywo::Executor::LocalAdapter.new(runner:).call(request:)

    assert_equal [ request ], requests
    assert_equal "allow", result.dig("result", "decision")
  end
end
