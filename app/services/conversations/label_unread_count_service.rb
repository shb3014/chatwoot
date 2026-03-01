class Conversations::LabelUnreadCountService
  def initialize(account)
    @account = account
  end

  def perform
    rows = ActiveRecord::Base.connection.select_all(query)
    rows.each_with_object({}) do |row, hash|
      hash[row['label_title']] = row['unread_count']
    end
  end

  private

  def query
    ActiveRecord::Base.sanitize_sql_array([<<~SQL.squish, { account_id: @account.id }])
      SELECT TRIM(label) AS label_title, COUNT(DISTINCT conversations.id) AS unread_count
      FROM conversations
      CROSS JOIN LATERAL unnest(string_to_array(conversations.cached_label_list, ',')) AS label
      WHERE conversations.account_id = :account_id
        AND conversations.cached_label_list IS NOT NULL
        AND conversations.cached_label_list != ''
        AND (
          conversations.agent_last_seen_at IS NULL
          OR EXISTS (
            SELECT 1 FROM messages
            WHERE messages.conversation_id = conversations.id
              AND messages.account_id = conversations.account_id
              AND messages.message_type = #{Message.message_types[:incoming]}
              AND messages.created_at > conversations.agent_last_seen_at
          )
        )
      GROUP BY TRIM(label)
    SQL
  end
end
