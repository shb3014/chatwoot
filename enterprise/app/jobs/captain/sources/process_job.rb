class Captain::Sources::ProcessJob < ApplicationJob
  queue_as :low

  def perform(source)
    source.update!(status: :processing)

    case source.source_type
    when 'web_url'
      process_web_url(source)
    when 'pdf'
      process_pdf(source)
    end

    compute_embedding(source)
    source.update!(status: :active)
  rescue StandardError => e
    source.update!(
      status: :failed,
      metadata: (source.metadata || {}).merge('error' => e.message)
    )
    Rails.logger.error("Captain::Sources::ProcessJob failed for source #{source.id}: #{e.message}")
  end

  private

  def process_web_url(source)
    crawler = Captain::Tools::SimplePageCrawlService.new(source.external_link)

    title = crawler.page_title || source.title
    content = crawler.body_text_content || ''

    source.update!(
      title: title.truncate(255),
      content: content.truncate(200_000)
    )
  end

  def process_pdf(source)
    return unless source.pdf_file.attached?

    # Extract text content from PDF using pdf-reader
    text_content = extract_pdf_text(source)
    source.update!(content: text_content.truncate(200_000))
  end

  def extract_pdf_text(source)
    Tempfile.create(['pdf_source', '.pdf'], binmode: true) do |temp_file|
      temp_file.write(source.pdf_file.download)
      temp_file.close

      reader = PDF::Reader.new(temp_file.path)
      reader.pages.map(&:text).join("\n\n")
    end
  rescue StandardError => e
    Rails.logger.error("PDF text extraction failed for source #{source.id}: #{e.message}")
    ''
  end

  def compute_embedding(source)
    return if source.content.blank?

    embedding = Captain::Llm::EmbeddingService.new.get_embedding(source.embedding_content)
    source.update!(embedding: embedding)
  end
end
