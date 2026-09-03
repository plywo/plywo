require "test_helper"

class PlywoGithubCommentRendererTest < ActiveSupport::TestCase
  test "renders a durable GitHub review comment with runtime evidence" do
    payload = Plywo::Demo::DogfoodRunner.call
    markdown = Plywo::Github::CommentRenderer.markdown(
      payload:,
      context: {
        repository: "plywo/plywo",
        pr_number: 1,
        baseline_label: "dogfood baseline",
        baseline_sha: "synthetic",
        candidate_label: "bootstrap/rails-first-slice",
        candidate_sha: "abcdef123456",
        bootstrap_baseline: true
      }
    )

    assert_includes markdown, Plywo::Github::CommentRenderer::MARKER
    assert_includes markdown, "Plywo · Behavioral Review"
    assert_includes markdown, "SQL queries"
    assert_includes markdown, "Merge recommendation: **BLOCK**"
    assert_includes markdown, "bootstrap dogfood run"
  end
end
