require "test_helper"

class GithubWebhookDeliveryTest < ActiveSupport::TestCase
  test "claims a delivery only once" do
    delivery = GithubWebhookDelivery.create!(delivery_id: "delivery-1", event: "pull_request", action: "synchronize")

    assert delivery.claim!
    assert_equal "processing", delivery.status
    refute delivery.claim!
  end

  test "uses database-authoritative time for lifecycle transitions despite host clock skew" do
    database_now = Time.utc(2026, 9, 5, 1, 10, 0)
    delivery = GithubWebhookDelivery.create!(delivery_id: "delivery-clock", event: "pull_request", action: "synchronize")

    with_database_clock(database_now) do
      travel_to(database_now + 12.hours) do
        assert delivery.claim!
      end
    end

    delivery.reload
    assert_equal database_now, delivery.started_at
    assert_equal database_now, delivery.updated_at

    with_database_clock(database_now + 5) do
      travel_to(database_now - 1.day) do
        delivery.complete!
      end
    end

    assert_equal database_now + 5, delivery.reload.finished_at
  end

  test "supports explicit lifecycle time for deterministic callers" do
    delivery = GithubWebhookDelivery.create!(delivery_id: "delivery-explicit", event: "pull_request", action: "synchronize")
    now = Time.utc(2026, 9, 5, 1, 20, 0)

    assert delivery.claim!(now:)
    assert_equal now, delivery.started_at

    delivery.ignore!("not runnable", now: now + 1)
    assert_equal now + 1, delivery.finished_at
  end

  test "recognizes pull request execution triggers" do
    delivery = GithubWebhookDelivery.new(event: "pull_request", action: "synchronize")
    assert delivery.runnable_pull_request?

    delivery.action = "edited"
    refute delivery.runnable_pull_request?
  end
end
