module Enterprise::Public::Api::V1::Portals::ArticlesController
  # Minimum query length to use the (paid) embedding-based vector search.
  # Shorter queries are handled by cheap keyword search (or skipped entirely)
  # to avoid burning embedding API credits on every keystroke from a search box
  # that fires per-input change.
  MIN_EMBEDDING_QUERY_LENGTH = 3

  private

  def search_articles
    if @portal.account.feature_enabled?('help_center_embedding_search') &&
       embedding_query_long_enough?(list_params[:query])
      @articles = @articles.vector_search(list_params)
    else
      super
    end
  end

  def embedding_query_long_enough?(query)
    query.to_s.strip.length >= MIN_EMBEDDING_QUERY_LENGTH
  end
end
