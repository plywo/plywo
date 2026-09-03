module Demo
  class BehaviorController < ApplicationController
    skip_forgery_protection

    PROFILES = {
      "warmup" => { sql_queries: 0, background_jobs: 0, emails: 0, delay_ms: 0 },
      "baseline" => { sql_queries: 14, background_jobs: 1, emails: 1, delay_ms: 15 },
      "candidate" => { sql_queries: 47, background_jobs: 3, emails: 2, delay_ms: 90 }
    }.freeze

    def create
      profile = PROFILES.fetch(Current.plywo_subject.to_s, PROFILES.fetch("baseline"))

      ApplicationRecord.uncached do
        profile.fetch(:sql_queries).times do
          ApplicationRecord.connection.select_value("SELECT 1")
        end
      end

      profile.fetch(:background_jobs).times do
        DemoNotificationJob.perform_later(Current.plywo_execution_id)
      end

      profile.fetch(:emails).times do
        Plywo::Rails::Evidence.side_effect(:email, provider: "demo")
      end

      sleep(profile.fetch(:delay_ms) / 1000.0)

      render json: {
        ok: true,
        run_id: Current.plywo_run_id,
        execution_id: Current.plywo_execution_id,
        subject: Current.plywo_subject
      }
    end
  end
end
