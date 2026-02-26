class AddIndexMessagesOnConversationIdCreatedAtDesc < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Composite index optimized for the most frequent query pattern:
    # "get the latest message(s) for a conversation" (conversation.messages.last).
    # The DESC ordering on created_at eliminates a sort step for these queries.
    add_index :messages, [:conversation_id, :created_at],
              order: { created_at: :desc },
              name: 'index_messages_on_conversation_id_created_at_desc',
              algorithm: :concurrently
  end
end
