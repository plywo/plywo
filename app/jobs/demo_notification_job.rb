class DemoNotificationJob < ApplicationJob
  def perform
    Net::HTTP.get(URI.parse(Plywo::Demo::LoopbackHttpServer.url(delay_ms: 75)))
  end
end
