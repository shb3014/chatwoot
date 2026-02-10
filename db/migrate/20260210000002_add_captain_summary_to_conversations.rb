class AddCaptainSummaryToConversations < ActiveRecord::Migration[7.0]
  def change
    add_column :conversations, :captain_summary, :jsonb
  end
end
