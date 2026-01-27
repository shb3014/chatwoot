class AddRejectionFieldsToCaptainConversationLearnings < ActiveRecord::Migration[7.0]
  def change
    add_column :captain_conversation_learnings, :rejection_reason, :text
    add_column :captain_conversation_learnings, :rejected_at, :datetime
  end
end
