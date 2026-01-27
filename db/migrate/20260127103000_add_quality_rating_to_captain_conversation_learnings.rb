class AddQualityRatingToCaptainConversationLearnings < ActiveRecord::Migration[7.0]
  def change
    add_column :captain_conversation_learnings, :quality_rating, :integer
  end
end
