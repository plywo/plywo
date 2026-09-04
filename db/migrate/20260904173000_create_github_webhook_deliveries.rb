class CreateGithubWebhookDeliveries < ActiveRecord::Migration[8.1]
  def change
    create_table :github_webhook_deliveries do |t|
      t.string :delivery_id, null: false
      t.string :event, null: false
      t.string :action
      t.bigint :installation_id
      t.string :repository
      t.integer :pull_request_number
      t.string :base_sha
      t.string :head_sha
      t.string :status, null: false, default: "accepted"
      t.text :failure
      t.datetime :started_at
      t.datetime :finished_at
      t.timestamps
    end

    add_index :github_webhook_deliveries, :delivery_id, unique: true
    add_index :github_webhook_deliveries, %i[repository pull_request_number]
    add_index :github_webhook_deliveries, :status
  end
end
