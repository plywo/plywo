class DemoNotificationJob < ApplicationJob
  def perform
    Net::HTTP.get(URI.parse(Plywo::Demo::LoopbackHttpServer.url))
  end
end
