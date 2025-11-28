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

    # Store articles for reference list
    @cited_articles = articles.to_a

    results = []
    results.concat(responses.map { |response| format_response(response) })
    results.concat(articles.map.with_index { |article, index| format_article(article, index + 1) })

    # Add reference list at the end
    documentation = results.join
    documentation += format_article_references if @cited_articles.any?

    documentation
  end

  private

  def search_articles(query)
    return [] unless assistant.account.feature_enabled?('help_center_embedding_search')

    # Get embedding for the query
    embedding = Captain::Llm::EmbeddingService.new.get_embedding(query)

    # Try to find articles in the user's locale first
    user_locale = detect_locale
    if user_locale.present?
      articles = search_with_embedding(embedding, locale: user_locale)
      return articles if articles.present?
    end

    # Fallback to global search if no articles found in specific locale
    search_with_embedding(embedding)
  rescue StandardError => e
    Rails.logger.error { "Error searching articles: #{e.message}" }
    []
  end

  def detect_locale
    return nil unless @conversation

    # Check for explicit locale in custom attributes
    locale = @conversation.custom_attributes['locale']

    # Check browser language from conversation or contact
    locale ||= @conversation.additional_attributes['browser_language']
    locale ||= @conversation.contact&.additional_attributes&.dig('browser_language')

    # Extract language code (e.g., 'en-US' -> 'en', 'zh_CN' -> 'zh')
    locale.to_s.split(/[-_]/).first.presence
  end

  def search_with_embedding(embedding, locale: nil)
    scope = ArticleEmbedding
    scope = scope.joins(:article).where("articles.locale LIKE ?", "#{locale}%") if locale.present?

    article_ids = scope.nearest_neighbors(:embedding, embedding, distance: 'cosine')
                       .limit(8)
                       .pluck(:article_id)

    Article.where(id: article_ids)
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

  def format_article(article, reference_number = nil)
    formatted_article = "
        Article Title: #{article.title}
        Description: #{article.description}
        Content: #{article.content}
        "
    if article.try(:slug).present?
      article_url = generate_article_url(article)
      formatted_article += "
          Source [#{reference_number}]: #{article_url}
          "
    end

    formatted_article
  end

  def format_article_references
    return '' if @cited_articles.empty?

    references = "\n\n---\n**Referenced Articles:**\n"
    @cited_articles.each_with_index do |article, index|
      article_url = generate_article_url(article)
      references += "\n[#{index + 1}] #{article.title} - #{article_url}"
    end
    references
  end

  def generate_article_url(article)
    portal = article.portal

    # 生成基础 URL
    base_url = if portal.custom_domain.present?
                 "https://#{portal.custom_domain}"
               else
                 frontend_url = ENV.fetch('FRONTEND_URL', '')
                 "#{frontend_url}/hc/#{portal.slug}"
               end

    # 生成文章路径
    article_path = if portal.custom_domain.present?
                     "/articles/#{article.slug}"
                   else
                     "/articles/#{article.slug}"
                   end

    "#{base_url}#{article_path}"
  end
end
