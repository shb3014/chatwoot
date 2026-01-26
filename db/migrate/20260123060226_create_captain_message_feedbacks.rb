class CreateCaptainMessageFeedbacks < ActiveRecord::Migration[7.1]
  def change
    create_table :captain_message_feedbacks do |t|
      t.references :message, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true
      t.references :rated_by, null: false, foreign_key: { to_table: :users }

      t.integer :rating, null: false # 1 = 👍, -1 = 👎, 0 = neutral
      t.string :feedback_type # helpful, unhelpful, incorrect, incomplete, too_technical, too_vague
      t.text :notes

      t.boolean :issue_resolved
      t.string :resolution_method # captain_solution, agent_different_solution, escalated

      t.timestamps
    end

    add_index :captain_message_feedbacks, [:message_id, :rated_by_id], unique: true, name: 'index_captain_feedbacks_on_message_and_rater'
  end
end
