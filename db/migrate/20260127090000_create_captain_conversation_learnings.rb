class CreateCaptainConversationLearnings < ActiveRecord::Migration[7.0]
  def change
    create_table :captain_conversation_learnings do |t|
      t.references :account, null: false, foreign_key: true
      t.references :conversation, null: false, foreign_key: true, index: { unique: true }
      t.references :assistant, null: false, foreign_key: { to_table: :captain_assistants }
      t.integer :status, null: false, default: 0
      t.text :issue_summary
      t.text :resolution_summary
      t.vector :embedding, limit: 1536
      t.datetime :learned_at
      t.datetime :last_message_at
      t.timestamps
    end

    add_index :captain_conversation_learnings, :status
    add_index :captain_conversation_learnings, :embedding, using: :ivfflat
  end
end
