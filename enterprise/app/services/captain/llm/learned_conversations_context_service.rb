module Captain
  module Llm
    class LearnedConversationsContextService
      DEFAULT_LIMIT = 3
      DEFAULT_THRESHOLD = 0.75

      def initialize(assistant:, conversation:, query:)
        @assistant = assistant
        @conversation = conversation
        @query = query
      end

      def build
        return if @query.blank?
        return if @assistant.blank?

        results = search_learnings
        return if results.blank?

        format_results(results)
      rescue StandardError => e
        Captain::Logger.warn('[LearnedConversations] retrieval failed', error: e.message)
        nil
      end

      private

      def search_learnings
        embedding = Captain::Llm::EmbeddingService.new.get_embedding(@query)
        return [] if embedding.blank?

        scope = Captain::ConversationLearning
                .where(account_id: @assistant.account_id, assistant_id: @assistant.id, status: :learned)
                .where.not(embedding: nil)

        scope = scope.nearest_neighbors(:embedding, embedding, distance: 'cosine')
        ids = fetch_ids(scope, embedding)
        return [] if ids.empty?

        records = Captain::ConversationLearning.where(id: ids).includes(:conversation).index_by(&:id)
        ids.map { |id| records[id] }.compact
      end

      def fetch_ids(scope, embedding)
        embedding_string = "[#{embedding.join(',')}]"
        candidates = scope.select('id', "embedding <=> '#{embedding_string}' as distance")
                          .limit(DEFAULT_LIMIT)
        candidates.select { |c| c.distance < DEFAULT_THRESHOLD }.map(&:id)
      end

      def format_results(records)
        lines = records.each_with_index.map do |learning, index|
          conversation_id = learning.conversation&.display_id || learning.conversation_id
          [
            "#{index + 1}. Conversation #{conversation_id}",
            "   Issue: #{learning.issue_summary.presence || '-'}",
            "   Resolution: #{learning.resolution_summary.presence || '-'}",
            ("   Rating: #{learning.quality_rating}/100" if learning.quality_rating.present?)
          ].compact.join("\n")
        end

        <<~TEXT
          LEARNED CONVERSATIONS (use only if relevant):
          #{lines.join("\n")}
        TEXT
      end
    end
  end
end
