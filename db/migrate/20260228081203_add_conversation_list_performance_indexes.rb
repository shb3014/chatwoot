class AddConversationListPerformanceIndexes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def change
    # Primary sort index: covers the most common query pattern
    # WHERE account_id = ? AND status = ? ORDER BY last_activity_at DESC
    add_index :conversations,
              [:account_id, :status, :last_activity_at],
              order: { last_activity_at: :desc },
              name: 'idx_conv_account_status_last_activity',
              algorithm: :concurrently,
              if_not_exists: true

    # Priority sort index: covers ORDER BY priority DESC NULLS LAST, last_activity_at DESC
    reversible do |dir|
      dir.up do
        execute <<-SQL.squish
          CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_conv_account_status_priority_activity
          ON conversations (account_id, status, priority DESC NULLS LAST, last_activity_at DESC)
        SQL
      end
      dir.down do
        execute <<-SQL.squish
          DROP INDEX IF EXISTS idx_conv_account_status_priority_activity
        SQL
      end
    end

    # Partial index on messages for unread-check EXISTS subquery:
    # WHERE message_type = 0 (incoming) — dramatically speeds up unread_by_agent scope
    add_index :messages,
              [:conversation_id, :created_at],
              where: 'message_type = 0',
              name: 'idx_messages_incoming_conv_created',
              algorithm: :concurrently,
              if_not_exists: true

    # Partial index on messages for DISTINCT ON non-activity messages:
    # WHERE message_type != 2 (not activity) ORDER BY conversation_id, id DESC
    add_index :messages,
              [:conversation_id, :id],
              order: { id: :desc },
              where: 'message_type != 2',
              name: 'idx_messages_conv_non_activity_id_desc',
              algorithm: :concurrently,
              if_not_exists: true
  end
end
