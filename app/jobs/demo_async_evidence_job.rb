class DemoAsyncEvidenceJob < ApplicationJob
  def perform
    ApplicationRecord.connection.select_value("SELECT 1")
    DemoMailer.notification(Current.plywo_execution_id).deliver_now
    Net::HTTP.get(URI.parse(Plywo::Demo::LoopbackHttpServer.url))
  end
end
