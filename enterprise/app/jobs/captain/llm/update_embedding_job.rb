class Captain::Llm::UpdateEmbeddingJob < ApplicationJob
  queue_as :low

  def perform(record, content)
    embedding = Captain::Llm::EmbeddingService.new.get_embedding(content)
    attrs = { embedding: embedding }
    attrs[:status] = :active if record.is_a?(Captain::Source) && record.pending?
    record.update!(attrs)
  end
end
