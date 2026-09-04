module Plywo
  module Github
    class RepositoryCapabilityProvider
      def initialize(root: ::Rails.root, execution_model: PlywoExecution, authentication: nil)
        @root = root
        @execution_model = execution_model
        @authentication = authentication
      end

      def call(request:)
        execution = @execution_model.find_by(execution_id: request.execution_id)
        return unless execution

        installation_id = execution.context["installation_id"]
        return unless installation_id

        repository = request.context.fetch("repository")
        owner, name = repository.split("/", 2)
        raise ArgumentError, "Executor repository must use owner/name form" if owner.to_s.empty? || name.to_s.empty?

        token = authentication.installation_token(
          installation_id:,
          repositories: [ name ],
          permissions: { contents: "read" }
        )

        Plywo::Executor::RepositoryCapability.new(token: token.value)
      end

      private

      def authentication
        @authentication ||= AppAuthentication.from_env(root: @root)
      end
    end
  end
end
