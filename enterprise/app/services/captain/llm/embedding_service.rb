require 'openai'

class Captain::Llm::EmbeddingService < Llm::BaseOpenAiService
  class EmbeddingsError < StandardError; end

  def self.embedding_model
    @embedding_model = InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || OpenAiConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: self.class.embedding_model)
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
    response.dig('data', 0, 'embedding')
  rescue StandardError => e
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end
end
