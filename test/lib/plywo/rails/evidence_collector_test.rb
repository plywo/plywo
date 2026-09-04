require "test_helper"

class PlywoRailsEvidenceCollectorTest < ActiveSupport::TestCase
  test "collects Rails evidence only for the active execution" do
    execution_id = "execution-under-test"

    measurements = Plywo::Rails::EvidenceCollector.capture(execution_id:) do
      Current.set(plywo_execution_id: execution_id) do
        ActiveSupport::Notifications.instrument("sql.active_record", name: "Demo SQL", cached: false)
        ActiveSupport::Notifications.instrument("enqueue.active_job")
        ActiveSupport::Notifications.instrument("process_action.action_controller", status: 200)
        Plywo::Rails::Evidence.side_effect(:email)
      end

      Current.set(plywo_execution_id: "another-execution") do
        ActiveSupport::Notifications.instrument("sql.active_record", name: "Other SQL", cached: false)
        ActiveSupport::Notifications.instrument("enqueue.active_job")
      end
    end

    assert_equal 1, measurements.fetch("sql_queries")
    assert_equal 1, measurements.fetch("background_jobs")
    assert_equal 1, measurements.fetch("emails")
    assert_equal 1, measurements.fetch("http_requests")
    assert_equal 0, measurements.fetch("errors")
    assert_operator measurements.fetch("duration_ms"), :>=, 0
  end

  test "captures the project callsite for a real SQL query" do
    execution_id = "execution-with-sql-source"
    collector = Plywo::Rails::EvidenceCollector.new(execution_id:)
    query_line = nil

    collector.capture do
      Current.set(plywo_execution_id: execution_id) do
        query_line = __LINE__ + 1
        ApplicationRecord.connection.select_value("SELECT 1")
      end
    end

    source = collector.attributions.fetch("sql_queries").first

    assert_equal "test/lib/plywo/rails/evidence_collector_test.rb", source.fetch("path")
    assert_equal query_line, source.fetch("start_line")
    assert_equal query_line, source.fetch("end_line")
    assert_equal "runtime", source.fetch("confidence")
  end

  test "captures the project enqueue callsite for a real background job" do
    execution_id = "execution-with-job-source"
    collector = Plywo::Rails::EvidenceCollector.new(execution_id:)
    enqueue_line = nil

    measurements = collector.capture do
      Current.set(plywo_execution_id: execution_id) do
        enqueue_line = __LINE__ + 1
        DemoNotificationJob.perform_later(execution_id)
      end
    end

    source = collector.attributions.fetch("background_jobs").first

    assert_equal 1, measurements.fetch("background_jobs")
    assert_equal "test/lib/plywo/rails/evidence_collector_test.rb", source.fetch("path")
    assert_equal enqueue_line, source.fetch("start_line")
    assert_equal enqueue_line, source.fetch("end_line")
    assert_equal "runtime", source.fetch("confidence")
  end

  test "captures the project delivery callsite for a real email" do
    execution_id = "execution-with-email-source"
    collector = Plywo::Rails::EvidenceCollector.new(execution_id:)
    delivery_line = nil

    measurements = collector.capture do
      Current.set(plywo_execution_id: execution_id) do
        delivery_line = __LINE__ + 1
        DemoMailer.notification(execution_id).deliver_now
      end
    end

    source = collector.attributions.fetch("emails").first

    assert_equal 1, measurements.fetch("emails")
    assert_equal "test/lib/plywo/rails/evidence_collector_test.rb", source.fetch("path")
    assert_equal delivery_line, source.fetch("start_line")
    assert_equal delivery_line, source.fetch("end_line")
    assert_equal "runtime", source.fetch("confidence")
  end
end
