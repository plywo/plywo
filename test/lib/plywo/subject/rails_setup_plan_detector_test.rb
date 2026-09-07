require "test_helper"
require "tmpdir"

class PlywoSubjectRailsSetupPlanDetectorTest < ActiveSupport::TestCase
  Configuration = Data.define(:persistence)

  test "detects reproducible Rails bootstrap and database preparation" do
    with_subject do |root|
      write(root, "Gemfile", "source \"https://rubygems.org\"\ngem \"rails\"\n")
      write(root, "Gemfile.lock", "BUNDLED WITH\n   2.6.9\n")
      write(root, "bin/rails", "#!/usr/bin/env ruby\n")
      write(root, "bin/setup", "#!/usr/bin/env ruby\n")
      write(root, ".ruby-version", "3.4.10\n")

      plan = detector.call(
        root:,
        configuration: Configuration.new(persistence: "auto")
      )

      assert_equal "rails", plan.framework
      assert_equal "ruby.bundle", plan.steps_for("bootstrap").sole.operation
      assert_equal "Gemfile.lock", plan.steps_for("bootstrap").sole.details.fetch("lockfile")
      assert_equal "rails.db_prepare", plan.steps_for("prepare").sole.operation
      assert_equal [ "bin/rails", "db:prepare" ], plan.steps_for("prepare").sole.details.fetch("command")
      assert_equal "auto", plan.steps_for("prepare").sole.details.fetch("persistence_mode")
      assert_equal "subject.state_cleanup", plan.steps_for("cleanup").sole.operation
      assert_equal true, plan.evidence.fetch("bin_setup")
      assert_equal ".ruby-version", plan.evidence.fetch("ruby_version")
    end
  end

  test "returns nil when Rails evidence is absent" do
    with_subject do |root|
      write(root, "package.json", "{}\n")

      assert_nil detector.call(
        root:,
        configuration: Configuration.new(persistence: "auto")
      )
    end
  end

  test "fails closed when a Rails subject has no committed lockfile" do
    with_subject do |root|
      write(root, "Gemfile", "source \"https://rubygems.org\"\n")
      write(root, "bin/rails", "#!/usr/bin/env ruby\n")

      error = assert_raises(Plywo::Subject::RailsSetupPlanDetector::Error) do
        detector.call(
          root:,
          configuration: Configuration.new(persistence: "auto")
        )
      end

      assert_equal "Rails subject requires a committed Gemfile.lock for reproducible setup", error.message
    end
  end

  private

  def detector
    @detector ||= Plywo::Subject::RailsSetupPlanDetector.new
  end

  def with_subject
    Dir.mktmpdir("plywo-setup-plan-") do |directory|
      yield Pathname(directory)
    end
  end

  def write(root, relative_path, content)
    path = root.join(relative_path)
    FileUtils.mkdir_p(path.dirname)
    path.write(content)
  end
end
