class ReadinessController < ApplicationController
  def show
    result = Plywo::Runtime::Readiness.new.call
    render json: result.to_h, status: result.ready? ? :ok : :service_unavailable
  end
end
