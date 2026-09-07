require "test_helper"

class PlywoSubjectLifecycleTest < ActiveSupport::TestCase
  Configuration = Data.define(:capture_env)

  class RecordingEnvironment < Plywo::Subject::Environment
    attr_reader :events

    def initialize(events:, fail_on: nil)
      @events = events
      @fail_on = fail_on
    end

    def prepare(root:, execution:, role:)
      events << :prepare
      raise "prepare failed" if @fail_on == :prepare

      { "FROM_ENVIRONMENT" => "1" }
    end

    def start_services(root:, execution:, role:, env:)
      events << :start_services
      raise "start failed" if @fail_on == :start_services
    end

    def healthcheck(root:, execution:, role:, env:)
      events << :healthcheck
      raise "healthcheck failed" if @fail_on == :healthcheck
    end

    def stop_services(root:, execution:, role:, env:)
      events << :stop_services
    end

    def cleanup(root:, execution:, role:)
      events << :cleanup
    end
  end

  class RecordingDiscovery
    def initialize(events:, environment:)
      @events = events
      @environment = environment
    end

    def resolve(root:, configuration:, runtime_env:)
      @events << [ :discover, runtime_env ]
      @environment
    end
  end

  test "orchestrates bootstrap, environment preparation, services, capture block, and teardown" do
    events = []
    environment = RecordingEnvironment.new(events:)
    lifecycle = lifecycle_for(events:, environment:)

    lifecycle.open(
      root: Pathname("/tmp/subject"),
      execution: Object.new,
      role: "base",
      configuration: Configuration.new(capture_env: { "FROM_CAPTURE" => "1" })
    ) do |session|
      events << :capture
      assert_equal "1", session.env.fetch("FROM_ENVIRONMENT")
      assert_equal "1", session.env.fetch("FROM_CAPTURE")
    end

    assert_equal [
      :bootstrap,
      [ :discover, { "FROM_BOOTSTRAP" => "1" } ],
      :prepare,
      :start_services,
      :healthcheck,
      :capture,
      :stop_services,
      :cleanup
    ], events
  end

  test "stops services and cleans up when readiness fails" do
    events = []
    environment = RecordingEnvironment.new(events:, fail_on: :healthcheck)
    lifecycle = lifecycle_for(events:, environment:)

    error = assert_raises(RuntimeError) do
      lifecycle.open(
        root: Pathname("/tmp/subject"),
        execution: Object.new,
        role: "candidate",
        configuration: Configuration.new(capture_env: {})
      ) { flunk "capture must not run" }
    end

    assert_equal "healthcheck failed", error.message
    assert_equal [
      :bootstrap,
      [ :discover, { "FROM_BOOTSTRAP" => "1" } ],
      :prepare,
      :start_services,
      :healthcheck,
      :stop_services,
      :cleanup
    ], events
  end

  test "cleans up without stopping services when preparation fails" do
    events = []
    environment = RecordingEnvironment.new(events:, fail_on: :prepare)
    lifecycle = lifecycle_for(events:, environment:)

    assert_raises(RuntimeError) do
      lifecycle.open(
        root: Pathname("/tmp/subject"),
        execution: Object.new,
        role: "base",
        configuration: Configuration.new(capture_env: {})
      ) { flunk "capture must not run" }
    end

    assert_equal [
      :bootstrap,
      [ :discover, { "FROM_BOOTSTRAP" => "1" } ],
      :prepare,
      :cleanup
    ], events
  end

  private

  def lifecycle_for(events:, environment:)
    bootstrap = lambda do |root:|
      events << :bootstrap
      { "FROM_BOOTSTRAP" => "1" }
    end
    discovery = RecordingDiscovery.new(events:, environment:)

    Plywo::Subject::Lifecycle.new(discovery:, bootstrap:)
  end
end
