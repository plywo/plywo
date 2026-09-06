class ApplicationJob < ActiveJob::Base
  include Plywo::Rails::ActiveJobExecutionContext
end
