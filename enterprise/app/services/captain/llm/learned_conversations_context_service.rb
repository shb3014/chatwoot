module Captain
  module Llm
    class LearnedConversationsContextService
      DEFAULT_LIMIT = 3
      DEFAULT_CANDIDATES = 10
      DEFAULT_THRESHOLD = 0.75
      MIN_RATING = 60

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
                .where('quality_rating IS NULL OR quality_rating >= ?', MIN_RATING)

        scope = scope.nearest_neighbors(:embedding, embedding, distance: 'cosine')
        candidates = fetch_candidates(scope, embedding)
        return [] if candidates.empty?

        records = Captain::ConversationLearning.where(id: candidates.map { |c| c[:id] })
                                               .includes(:conversation)
                                               .index_by(&:id)
        candidates.filter_map { |candidate| records[candidate[:id]] }
      end

      def fetch_candidates(scope, embedding)
        embedding_string = "[#{embedding.join(',')}]"
        candidates = scope.select('id', 'quality_rating', "embedding <=> '#{embedding_string}' as distance")
                          .limit(DEFAULT_CANDIDATES)
        candidates = candidates.select { |c| c.distance < DEFAULT_THRESHOLD }
                               .map { |c| { id: c.id, distance: c.distance, rating: c.quality_rating || 0 } }
        candidates.sort_by do |candidate|
          [-candidate[:rating], candidate[:distance]]
        end.first(DEFAULT_LIMIT)
      end

      def format_results(records)
        lines = records.map do |learning|
          [
            "Issue: #{learning.issue_summary.presence || '-'}",
            "Resolution: #{learning.resolution_summary.presence || '-'}"
          ].join("\n")
        end

        <<~TEXT
          BACKGROUND CONTEXT (this is NOT a citable source - citation numbers like [1], [2] refer ONLY to search_documentation results below, NOT to this section):
          #{lines.join("\n\n")}
        TEXT
      end
    end
  end
end
