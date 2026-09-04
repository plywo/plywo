module Demo
  class ProcessProofController < ApplicationController
    skip_forgery_protection

    def create
      job = DemoAsyncEvidenceJob.perform_later

      render json: {
        ok: true,
        run_id: Current.plywo_run_id,
        execution_id: Current.plywo_execution_id,
        subject: Current.plywo_subject,
        job_id: job.job_id
      }
    end
  end
end
