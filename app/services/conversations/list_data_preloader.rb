# Batch-preloads message-related data for a collection of conversations,
# eliminating N+1 queries in list views (index, filter).
#
# Instead of 3-4 per-conversation queries (latest message, non-activity message,
# unread count), this uses PostgreSQL DISTINCT ON and GROUP BY to fetch all data
# in a constant number of queries regardless of conversation count.
class Conversations::ListDataPreloader
  def self.preload(conversations)
    new(conversations).preload
  end

  def initialize(conversations)
    @conversations = conversations
  end

  def preload
    @conversations.load if @conversations.respond_to?(:load) && !@conversations.loaded?
    records = @conversations.respond_to?(:to_a) ? @conversations.to_a : Array(@conversations)
    return if records.empty?

    conv_ids = records.map(&:id)

    latest = batch_load_latest_messages(conv_ids)
    non_activity = batch_load_latest_non_activity_messages(conv_ids)
    unread = batch_compute_unread_counts(conv_ids)

    records.each do |conv|
      conv.cached_latest_message = latest[conv.id]
      conv.cached_latest_non_activity_message = non_activity[conv.id]
      conv.cached_unread_count = unread[conv.id] || 0
    end
  end

  private

  # Uses DISTINCT ON to get exactly one (latest) message per conversation in a single query.
  def batch_load_latest_messages(conv_ids)
    msgs = Message.unscoped
                  .select('DISTINCT ON (conversation_id) messages.*')
                  .where(conversation_id: conv_ids)
                  .order(Arel.sql('conversation_id, created_at DESC'))
                  .to_a

    eager_load_message_associations(msgs)
    msgs.index_by(&:conversation_id)
  end

  # Uses DISTINCT ON to get exactly one (latest non-activity) message per conversation.
  def batch_load_latest_non_activity_messages(conv_ids)
    msgs = Message.unscoped
                  .select('DISTINCT ON (conversation_id) messages.*')
                  .where(conversation_id: conv_ids)
                  .where.not(message_type: Message.message_types[:activity])
                  .order(Arel.sql('conversation_id, id DESC'))
                  .to_a

    eager_load_message_associations(msgs)
    msgs.index_by(&:conversation_id)
  end

  # Single GROUP BY query to count unread incoming messages across all conversations.
  def batch_compute_unread_counts(conv_ids)
    Message.unscoped
           .where(conversation_id: conv_ids, message_type: Message.message_types[:incoming])
           .joins('INNER JOIN conversations ON conversations.id = messages.conversation_id')
           .where('conversations.agent_last_seen_at IS NULL OR messages.created_at > conversations.agent_last_seen_at')
           .group('messages.conversation_id')
           .count
  end

  def eager_load_message_associations(msgs)
    return if msgs.empty?

    ActiveRecord::Associations::Preloader.new(
      records: msgs,
      associations: [
        :conversation,
        { conversation: :contact_inbox },
        { attachments: [{ file_attachment: [:blob] }] },
        { sender: { avatar_attachment: [:blob] } }
      ]
    ).call
  end
end
