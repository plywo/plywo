require "rbconfig"
require "tmpdir"

module Plywo
  module Rails
    class SolidQueueExecution
      DEFAULT_START_TIMEOUT_SECONDS = 10.0
      DEFAULT_QUIESCENCE_TIMEOUT_SECONDS = 10.0
      DEFAULT_QUIET_PERIOD_SECONDS = 0.05

      def self.call(execution_id:, **options)
        new(execution_id:, **options).call
      end

      def initialize(execution_id:, start_timeout_seconds: DEFAULT_START_TIMEOUT_SECONDS,
                     quiescence_timeout_seconds: DEFAULT_QUIESCENCE_TIMEOUT_SECONDS,
                     quiet_period_seconds: DEFAULT_QUIET_PERIOD_SECONDS)
        @execution_id = execution_id.to_s
        @start_timeout_seconds = Float(start_timeout_seconds)
        @quiescence_timeout_seconds = Float(quiescence_timeout_seconds)
        @quiet_period_seconds = Float(quiet_period_seconds)
      end

      def call
        initial_jobs = correlated_queue_jobs
        raise "Expected Solid Queue to contain correlated work for execution #{execution_id}" if initial_jobs.empty?

        validate_serialized_context!(initial_jobs)

        supervisor_pid = nil
        supervisor_status = nil
        worker_pids = []
        quiescence = nil
        worker_log = nil

        Dir.mktmpdir("plywo-solid-queue-execution") do |directory|
          log_path = File.join(directory, "solid-queue.log")

          File.open(log_path, "w") do |log|
            supervisor_pid = Process.spawn(
              worker_environment,
              RbConfig.ruby,
              File.join(::Rails.root, "bin/jobs"),
              "--skip-recurring",
              chdir: ::Rails.root.to_s,
              out: log,
              err: log
            )
          end

          begin
            worker_pids = wait_for_workers
            quiescence = ExecutionQuiescence.wait(
              execution_id:,
              timeout_seconds: quiescence_timeout_seconds,
              quiet_period_seconds:
            )
            Process.kill("TERM", supervisor_pid)
            _, supervisor_status = Process.wait2(supervisor_pid)
            supervisor_pid = nil
          ensure
            terminate(supervisor_pid) if supervisor_pid
          end

          worker_log = File.read(log_path)
        end

        raise "Solid Queue supervisor exited unsuccessfully:\n#{worker_log}" unless supervisor_status&.success?

        jobs = correlated_queue_jobs
        validate_serialized_context!(jobs)

        {
          "executions" => execution_provenance(jobs),
          "quiescence" => quiescence,
          "transport" => {
            "name" => "solid_queue",
            "worker_pids" => worker_pids,
            "worker_process_isolated" => worker_pids.none? { |pid| pid == Process.pid }
          }
        }
      end

      private

      attr_reader :execution_id, :start_timeout_seconds, :quiescence_timeout_seconds, :quiet_period_seconds

      def correlated_work_items
        PlywoExecutionWorkItem.where(execution_id:, kind: "active_job").order(:id)
      end

      def correlated_queue_jobs
        work_ids = correlated_work_items.pluck(:work_id)
        return [] if work_ids.empty?

        SolidQueue::Job.where(active_job_id: work_ids).order(:id).to_a
      end

      def validate_serialized_context!(jobs)
        jobs.each do |job|
          context = job.arguments.fetch(ActiveJobExecutionContext::CONTEXT_KEY)
          raise "Solid Queue job #{job.active_job_id} lost execution id" unless context.fetch("plywo_execution_id").to_s == execution_id
        end
      end

      def execution_provenance(jobs)
        work_items = correlated_work_items.index_by(&:work_id)

        jobs.map do |job|
          context = job.arguments.fetch(ActiveJobExecutionContext::CONTEXT_KEY)
          work_item = work_items.fetch(job.active_job_id)

          {
            "job_class" => job.class_name,
            "job_id" => job.active_job_id,
            "provider_job_id" => job.id,
            "queue_name" => job.queue_name,
            "execution_id" => context.fetch("plywo_execution_id"),
            "run_id" => context.fetch("plywo_run_id"),
            "subject" => context.fetch("plywo_subject"),
            "source" => "application_enqueue",
            "transport" => "solid_queue",
            "work_status" => work_item.status,
            "transport_finished" => job.finished_at.present?
          }
        end
      end

      def wait_for_workers
        started_at = monotonic_time

        loop do
          pids = SolidQueue::Process.where(kind: "Worker").pluck(:pid)
          return pids if pids.any?

          if monotonic_time - started_at >= start_timeout_seconds
            raise "Solid Queue worker did not register within #{start_timeout_seconds}s"
          end

          sleep 0.05
        end
      end

      def worker_environment
        {
          "PLYWO_SOLID_QUEUE" => "1",
          "SOLID_QUEUE_SKIP_RECURRING" => "true",
          "JOB_CONCURRENCY" => "1"
        }
      end

      def terminate(pid)
        Process.kill("TERM", pid)
        Process.wait(pid)
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      end

      def monotonic_time
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
