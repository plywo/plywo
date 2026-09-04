require "test_helper"

class PlywoGithubCheckPublisherTest < ActiveSupport::TestCase
  class FakePublisher < Plywo::Github::CheckPublisher
    attr_reader :calls

    def initialize(responses)
      @responses = responses
      @calls = []
    end

    private

    def request(method, path, body: nil)
      @calls << { method:, path:, body: }
      @responses.fetch([ method, path ], {})
    end
  end

  test "creates a check when the head has no Plywo check" do
    list_path = "/repos/plywo/plywo/commits/head/check-runs?check_name=Plywo+%2F+Behavioral+Diff&filter=latest"
    publisher = FakePublisher.new([ :get, list_path ] => { "check_runs" => [] })

    action = publisher.upsert(**attributes)

    assert_equal :created, action
    assert_equal :post, publisher.calls.last.fetch(:method)
    assert_equal "head", publisher.calls.last.dig(:body, :head_sha)
  end

  test "updates the existing Plywo check on the same head" do
    list_path = "/repos/plywo/plywo/commits/head/check-runs?check_name=Plywo+%2F+Behavioral+Diff&filter=latest"
    publisher = FakePublisher.new(
      [ :get, list_path ] => { "check_runs" => [ { "id" => 42, "name" => "Plywo / Behavioral Diff" } ] }
    )

    action = publisher.upsert(**attributes)

    assert_equal :updated, action
    assert_equal :patch, publisher.calls.last.fetch(:method)
    assert_equal "/repos/plywo/plywo/check-runs/42", publisher.calls.last.fetch(:path)
  end

  private

  def attributes
    {
      repository: "plywo/plywo",
      head_sha: "head",
      name: "Plywo / Behavioral Diff",
      external_id: "run-1",
      details_url: "https://github.com/plywo/plywo/actions/runs/1",
      conclusion: "success",
      title: "No behavioral regression detected",
      summary: "ALLOW"
    }
  end
end
