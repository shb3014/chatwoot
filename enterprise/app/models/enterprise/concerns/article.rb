module Enterprise::Concerns::Article
  extend ActiveSupport::Concern

  included do
    after_save :add_article_embedding, if: -> { saved_change_to_title? || saved_change_to_description? || saved_change_to_content? }

    def self.add_article_embedding_association
      has_many :article_embeddings, dependent: :destroy_async
    end

    add_article_embedding_association

    def self.vector_search(params)
      embedding = Captain::Llm::EmbeddingService.new.get_embedding(params['query'])
      records = joins(
        :category
      ).search_by_category_slug(
        params[:category_slug]
      ).search_by_category_locale(params[:locale]).search_by_author(params[:author_id]).search_by_status(params[:status])
      filtered_article_ids = records.pluck(:id)

      # Fetch nearest neighbors and their distances, then filter directly

      # experimenting with filtering results based on result threshold
      # distance_threshold = 0.2
      # if using add the filter block to the below query
      # .filter { |ae| ae.neighbor_distance <= distance_threshold }

      article_ids = ArticleEmbedding.where(article_id: filtered_article_ids)
                                    .nearest_neighbors(:embedding, embedding, distance: 'cosine')
                                    .limit(5)
                                    .pluck(:article_id)

      # Fetch the articles by the IDs obtained from the nearest neighbors search
      where(id: article_ids)
    end
  end

  def add_article_embedding
    Rails.logger.info { "add_article_embedding being called for Article #{id}" }
    return unless account.feature_enabled?('help_center_embedding_search')

    Rails.logger.info { "add_article_embedding called for Article #{id}" }

    Portal::ArticleIndexingJob.perform_later(self)
  end

  def generate_and_save_article_seach_terms
    terms = generate_article_search_terms
    article_embeddings.destroy_all
    terms.each { |term| article_embeddings.create!(term: term) }
  end

  def article_to_search_terms_prompt
    <<~SYSTEM_PROMPT_MESSAGE
      For the provided article content, generate potential search query keywords and snippets that can be used to generate the embeddings.
      Ensure the search terms are as diverse as possible but capture the essence of the article and are super related to the articles.
      Don't return any terms if there aren't any terms of relevance.
      Always return results in valid JSON of the following format
      {
        "search_terms": []
      }
    SYSTEM_PROMPT_MESSAGE
  end

  def generate_article_search_terms
    api_key = captain_open_ai_api_key
    raise 'CAPTAIN_OPEN_AI_API_KEY not configured' if api_key.blank?

    messages = [
      { role: 'system', content: article_to_search_terms_prompt },
      { role: 'user', content: "title: #{title} \n description: #{description} \n content: #{content}" }
    ]
    headers = { 'Content-Type' => 'application/json', 'Authorization' => "Bearer #{api_key}" }
    body = { model: openai_model, messages: messages, response_format: { type: 'json_object' } }.to_json
    Rails.logger.info "Requesting Chat GPT with body: #{body}"
    response = HTTParty.post(openai_api_url, headers: headers, body: body)
    Rails.logger.info "Chat GPT response: #{response.body}"

    return [] unless response.parsed_response&.dig('choices', 0, 'message', 'content')

    content = response.parsed_response['choices'][0]['message']['content']
    # Strip markdown code fences if present (some models like DeepSeek wrap JSON in ```json ... ```)
    content = content.strip.gsub(/\A```json\n/, '').gsub(/\n```\z/, '')

    JSON.parse(content)['search_terms']
  end

  private

  def openai_api_url
    endpoint = captain_open_ai_endpoint
    endpoint = endpoint.chomp('/')

    return endpoint if endpoint.end_with?('/v1/chat/completions')
    return "#{endpoint}/chat/completions" if endpoint.end_with?('/v1')

    "#{endpoint}/v1/chat/completions"
  end

  def openai_model
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')&.value.presence || ENV.fetch('OPENAI_GPT_MODEL', 'gpt-4o-mini')
  end

  def captain_open_ai_endpoint
    api_key_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    endpoint = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT')&.value

    return api_key_value if api_key_value.present? && api_key_value.match?(%r{\Ahttps?://}) && endpoint.blank?

    endpoint.presence || 'https://api.openai.com'
  end

  def captain_open_ai_api_key
    api_key_value = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value
    return api_key_value unless api_key_value.present? && api_key_value.match?(%r{\Ahttps?://})

    ENV.fetch('OPENAI_API_KEY', nil)
  end
end
