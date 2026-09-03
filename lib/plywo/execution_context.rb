module Plywo
  class ExecutionContext
    def initialize(app)
      @app = app
    end

    def call(env)
      Current.set(
        plywo_execution_id: env["HTTP_X_PLYWO_EXECUTION_ID"],
        plywo_run_id: env["HTTP_X_PLYWO_RUN_ID"],
        plywo_subject: env["HTTP_X_PLYWO_SUBJECT"]
      ) do
        status, headers, body = @app.call(env)
        headers["X-Plywo-Execution-Id"] ||= Current.plywo_execution_id if Current.plywo_execution_id
        [status, headers, body]
      end
    end
  end
end
