require "test_helper"

class GithubWebhookDeliveryTest < ActiveSupport::TestCase
  test "claims a delivery only once" do
    delivery = GithubWebhookDelivery.create!(delivery_id: "delivery-1", event: "pull_request", action: "synchronize")

    assert delivery.claim!
    assert_equal "processing", delivery.status
    refute delivery.claim!
  end

  test "recognizes pull request execution triggers" do
    delivery = GithubWebhookDelivery.new(event: "pull_request", action: "synchronize")
    assert delivery.runnable_pull_request?

    delivery.action = "edited"
    refute delivery.runnable_pull_request?
  end
end
