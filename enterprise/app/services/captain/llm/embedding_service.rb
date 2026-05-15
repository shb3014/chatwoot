require 'openai'

class Captain::Llm::EmbeddingService < Llm::BaseOpenAiService
  class EmbeddingsError < StandardError; end

  def self.embedding_model
    @embedding_model = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || OpenAiConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: self.class.embedding_model)
    cache_key = "#{model}::#{content}"
    cached = self.class.embedding_cache.read(cache_key)
    return cached if cached

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @client.embeddings(
      parameters: {
        model: model,
        input: content,
        dimensions: 1536
      }
    )

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    Captain::Logger.logger.info "[Captain][EmbeddingService] model=#{model} input_chars=#{content.to_s.length} in #{elapsed_ms}ms"
    embedding = response.dig('data', 0, 'embedding')
    self.class.embedding_cache.write(cache_key, embedding, expires_in: 1.hour)
    embedding
  rescue StandardError => e
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  # Process-wide LRU cache (1024 entries, 1h TTL). Replaces the previous per-thread
  # Hash that effectively disabled caching across requests/sidekiq threads.
  def self.embedding_cache
    @embedding_cache ||= ActiveSupport::Cache::MemoryStore.new(size: 8.megabytes)
  end
end
