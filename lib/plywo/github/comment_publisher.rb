require "json"
require "net/http"
require "uri"

module Plywo
  module Github
    class CommentPublisher
      def initialize(token:, api_url: "https://api.github.com")
        @token = token
        @api_url = api_url.sub(%r{/+$}, "")
      end

      def upsert(repository:, pr_number:, body:)
        comments = request(:get, "/repos/#{repository}/issues/#{pr_number}/comments?per_page=100")
        existing = comments.find { |comment| comment.fetch("body", "").include?(CommentRenderer::MARKER) }

        if existing
          request(:patch, "/repos/#{repository}/issues/comments/#{existing.fetch("id")}", body: { body: })
          :updated
        else
          request(:post, "/repos/#{repository}/issues/#{pr_number}/comments", body: { body: })
          :created
        end
      end

      private

      def request(method, path, body: nil)
        uri = URI("#{@api_url}#{path}")
        request_class = { get: Net::HTTP::Get, post: Net::HTTP::Post, patch: Net::HTTP::Patch }.fetch(method)
        http_request = request_class.new(uri)
        http_request["Authorization"] = "Bearer #{@token}"
        http_request["Accept"] = "application/vnd.github+json"
        http_request["X-GitHub-Api-Version"] = "2022-11-28"
        http_request["User-Agent"] = "plywo-ci"
        http_request["Content-Type"] = "application/json" if body
        http_request.body = JSON.generate(body) if body

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(http_request)
        end

        unless response.is_a?(Net::HTTPSuccess)
          raise "GitHub comment publish failed: HTTP #{response.code} #{response.body}"
        end

        response.body.empty? ? nil : JSON.parse(response.body)
      end
    end
  end
end
