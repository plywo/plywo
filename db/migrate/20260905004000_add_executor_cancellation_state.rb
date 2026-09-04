class AddExecutorCancellationState < ActiveRecord::Migration[8.1]
  def change
    add_column :plywo_executions, :cancelled_at, :datetime
    add_column :plywo_executions, :cancellation_reason, :string

    add_column :plywo_executor_requests, :cancelled_at, :datetime
    add_column :plywo_executor_requests, :cancellation_reason, :string
  end
end
