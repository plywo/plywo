require "test_helper"
require "tmpdir"

class PlywoSubjectSetupPlanCompilerTest < ActiveSupport::TestCase
  Configuration = Data.define(:persistence)

  class Detector
    def initialize(plan: nil)
      @plan = plan
    end

    def call(root:, configuration:)
      @plan
    end
  end

  test "returns the single detected setup plan" do
    plan = setup_plan("rails")
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new(plan:) ]
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      assert_same plan, compiler.call(
        root: Pathname(directory),
        configuration: Configuration.new(persistence: "auto")
      )
    end
  end

  test "records declared executor runtime capabilities in plan evidence" do
    plan = Plywo::Subject::SetupPlan.new(
      framework: "rails",
      steps: [],
      evidence: { "framework" => "rails" }
    )
    capabilities = Plywo::Subject::RuntimeCapabilities.new(
      runtimes: { ruby: "3.4.10", node: "24.0.0" },
      package_managers: { pnpm: "10.0.0" }
    )
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new(plan:) ],
      runtime_capabilities: capabilities
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      compiled = compiler.call(
        root: Pathname(directory),
        configuration: Configuration.new(persistence: "auto")
      )

      assert_equal "rails", compiled.evidence.fetch("framework")
      assert_equal capabilities.to_h, compiled.evidence.fetch("executor_runtime_capabilities")
      refute_same plan, compiled
    end
  end

  test "fails closed when no detector can compile the subject" do
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new ]
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      error = assert_raises(Plywo::Subject::SetupPlanCompiler::Error) do
        compiler.call(
          root: Pathname(directory),
          configuration: Configuration.new(persistence: "auto")
        )
      end

      assert_includes error.message, "Could not compile a subject setup plan"
    end
  end

  test "fails closed when multiple detectors claim the subject" do
    compiler = Plywo::Subject::SetupPlanCompiler.new(
      detectors: [ Detector.new(plan: setup_plan("rails")), Detector.new(plan: setup_plan("other")) ]
    )

    Dir.mktmpdir("plywo-plan-compiler-") do |directory|
      error = assert_raises(Plywo::Subject::SetupPlanCompiler::Error) do
        compiler.call(
          root: Pathname(directory),
          configuration: Configuration.new(persistence: "auto")
        )
      end

      assert_includes error.message, "Ambiguous subject setup plan"
      assert_includes error.message, "other, rails"
    end
  end

  private

  def setup_plan(framework)
    Plywo::Subject::SetupPlan.new(
      framework:,
      steps: [
        {
          phase: "cleanup",
          operation: "subject.state_cleanup",
          provenance: "executor_default"
        }
      ]
    )
  end
end
