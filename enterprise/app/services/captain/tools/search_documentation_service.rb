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
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    captain_logger.info "#{self.class.name}: #{query}"

    # Search responses (FAQs), articles, and captain sources
    responses = assistant.responses.approved.search(query)
    articles = search_articles(query)
    sources = search_sources(query)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    captain_logger.info "#{self.class.name}: results=#{responses.size + articles.size + sources.size} in #{elapsed_ms}ms"

    return 'No documentation found for the given query' if responses.empty? && articles.empty? && sources.empty?

    # Store citable references for the reference list
    @cited_articles = articles.to_a
    @cited_sources = sources.select(&:web_url?).to_a

    results = []
    results.concat(responses.map { |response| format_response(response) })
    results.concat(articles.map { |article| format_article(article) })
    results.concat(sources.map { |source| format_source(source) })

    # Add reference list at the end (articles + citable web URL sources)
    documentation = results.join
    documentation += format_citable_references if @cited_articles.any? || @cited_sources.any?

    documentation
  end

  private

  def search_articles(query)
    user_locale = detect_locale

    # Fast keyword search first (avoids embedding call when it works)
    text_results = search_with_text(query, locale: user_locale, limit: 3)
    return text_results if text_results.present?

    global_text_results = search_with_text(query, locale: nil, limit: 3)
    return global_text_results if global_text_results.present?

    unless assistant.account.feature_enabled?('help_center_embedding_search')
      captain_logger.info "Embedding search disabled, no text matches for '#{query}'"
      return []
    end

    # Get embedding for the query
    embedding = Captain::Llm::EmbeddingService.new.get_embedding(query)

    # 1. Search in user's locale (if present) with threshold 0.7
    # We prioritize locale matches.
    results = []
    results += search_with_embedding(embedding, locale: user_locale, threshold: 0.7, limit: 3) if user_locale.present?

    # 2. Search Global (no locale filter) with threshold 0.7
    # We append these to the locale results.
    global_results = search_with_embedding(embedding, locale: nil, threshold: 0.7, limit: 3)
    results += global_results

    # Deduplicate based on article ID
    results.uniq!(&:id)

    # 3. Fallback: If we don't have enough results (less than 2),
    # perform a broader global search without threshold to ensure we return something.
    if results.size < 2
      captain_logger.info "Insufficient embedding matches (#{results.size}) for '#{query}', falling back to broader search"
      fallback_results = search_with_embedding(embedding, locale: nil, threshold: nil, limit: 2)
      results = (results + fallback_results).uniq(&:id)
    end

    # Return top 3 results
    results.first(3)
  rescue StandardError => e
    captain_logger.warn "Error searching articles: #{e.message}"
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

  def search_with_embedding(embedding, locale: nil, threshold: nil, limit: 3)
    scope = ArticleEmbedding
    scope = scope.joins(:article).where('articles.locale LIKE ?', "#{locale}%") if locale.present?

    # Use nearest_neighbors to get candidates ordered by distance
    scope = scope.nearest_neighbors(:embedding, embedding, distance: 'cosine')

    article_ids = if threshold
                    # To filter by distance safely without raw SQL binding issues:
                    # 1. Select distance explicitly using properly formatted vector string
                    # 2. Filter in Ruby
                    # Ensure embedding is formatted as a vector string '[x,y,z]'
                    embedding_string = "[#{embedding.join(',')}]"
                    candidates = scope.select('article_id', "embedding <=> '#{embedding_string}' as distance")
                                      .limit(limit)

                    candidates.select { |c| c.distance < threshold }.map(&:article_id)
                  else
                    scope.limit(limit).pluck(:article_id)
                  end

    # Retrieve articles and preserve order based on nearest neighbors
    articles = Article.where(id: article_ids).index_by(&:id)
    article_ids.map { |id| articles[id] }.compact
  end

  def search_with_text(query, locale: nil, limit: 3)
    scope = Article.published.where(account_id: assistant.account_id)
    scope = scope.where('articles.locale LIKE ?', "#{locale}%") if locale.present?
    scope.text_search(query).limit(limit)
  end

  def search_sources(query)
    Captain::Source.where(account_id: assistant.account_id).search(query).first(3)
  rescue StandardError => e
    captain_logger.warn "Error searching captain sources: #{e.message}"
    []
  end

  def format_source(source)
    if source.web_url?
      # Web URL sources are citable — include their URL for the LLM to reference
      "
        Source Title: #{source.title}
        Content: #{source.content.to_s.truncate(3000)}
        Source URL: #{source.external_link}
        "
    else
      # PDF and private article sources provide context but must NOT be cited
      "
        [NON-CITABLE CONTEXT — do NOT use citation numbers for this content]
        Source Title: #{source.title}
        Content: #{source.content.to_s.truncate(3000)}
        "
    end
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
      article_url = generate_article_url(article)
      formatted_article += "
          Source: #{article_url}
          "
    end

    formatted_article
  end

  def captain_logger
    Captain::Logger.logger
  end

  def format_citable_references
    return '' if @cited_articles.empty? && @cited_sources.empty?

    references = "\n\n\n**Sources**\n"
    ref_index = 0

    @cited_articles.each do |article|
      ref_index += 1
      article_url = generate_article_url(article)
      locale_label = article.try(:locale).presence || 'unknown'
      references += "\n[#{ref_index}] [#{article.title}](#{article_url}) (locale: #{locale_label})"
    end

    @cited_sources.each do |source|
      ref_index += 1
      references += "\n[#{ref_index}] [#{source.title}](#{source.external_link}) (type: web_url)"
    end

    references
  end

  # Keep legacy method name for backward compatibility
  alias format_article_references format_citable_references

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
