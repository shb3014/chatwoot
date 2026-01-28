require 'openai'

class Captain::Llm::EmbeddingService < Llm::BaseOpenAiService
  class EmbeddingsError < StandardError; end

  def self.embedding_model
    @embedding_model = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || OpenAiConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: self.class.embedding_model)
    cache_key = "#{model}::#{content}"
    cached = embedding_cache[cache_key]
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
    embedding_cache[cache_key] = embedding
    embedding_cache.clear if embedding_cache.size > 100
    embedding
  rescue StandardError => e
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  def embedding_cache
    Thread.current[:captain_embedding_cache] ||= {}
  end
end
