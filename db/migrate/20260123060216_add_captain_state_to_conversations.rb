class AddCaptainStateToConversations < ActiveRecord::Migration[7.1]
  def change
    add_column :conversations, :captain_state, :jsonb
    add_column :conversations, :captain_last_action_at, :datetime
    add_column :conversations, :captain_handed_off_at, :datetime
    add_column :conversations, :captain_handed_off_by_id, :integer
  end
end
