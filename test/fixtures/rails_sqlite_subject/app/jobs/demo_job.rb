class DemoJob < ApplicationJob
  def perform
    Widget.count
  end
end
