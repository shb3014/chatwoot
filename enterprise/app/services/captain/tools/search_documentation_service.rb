class Captain::Tools::SearchDocumentationService < Captain::Tools::BaseService
  def name
    'search_documentation'
  end

  def description
    'Search and retrieve documentation from knowledge base'
  end

  def parameters
    {
      type: 'object',
      properties: {
        search_query: {
          type: 'string',
          description: 'The search query to look up in the documentation.'
        }
      },
      required: ['search_query']
    }
  end

  def execute(arguments)
    query = arguments['search_query']
    Rails.logger.info { "#{self.class.name}: #{query}" }

    # Search both responses (FAQs) and articles
    responses = assistant.responses.approved.search(query)
    articles = search_articles(query)

    return 'No documentation found for the given query' if responses.empty? && articles.empty?

    results = []
    results.concat(responses.map { |response| format_response(response) })
    results.concat(articles.map { |article| format_article(article) })
    results.join
  end

  private

  def search_articles(query)
    return [] unless assistant.account.feature_enabled?('help_center_embedding_search')

    # Get embedding for the query
    embedding = Captain::Llm::EmbeddingService.new.get_embedding(query)

    # Search through all article embeddings without filtering by category/locale/status
    # to get the most relevant results
    article_ids = ArticleEmbedding.nearest_neighbors(:embedding, embedding, distance: 'cosine')
                                  .limit(5)
                                  .pluck(:article_id)

    Article.where(id: article_ids)
  rescue StandardError => e
    Rails.logger.error { "Error searching articles: #{e.message}" }
    []
  end

  def format_response(response)
    formatted_response = "
        Question: #{response.question}
        Answer: #{response.answer}
        "
    if response.documentable.present? && response.documentable.try(:external_link)
      formatted_response += "
          Source: #{response.documentable.external_link}
          "
    end

    formatted_response
  end

  def format_article(article)
    formatted_article = "
        Article Title: #{article.title}
        Description: #{article.description}
        Content: #{article.content}
        "
    if article.try(:slug).present?
      formatted_article += "
          Source: /articles/#{article.slug}
          "
    end

    formatted_article
  end
end
