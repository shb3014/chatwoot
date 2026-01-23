class Captain::Llm::FaqGeneratorService < Llm::BaseOpenAiService
  def initialize(content, language = 'english')
    super()
    @language = language
    @content = content
  end

  def generate
    response = @client.chat(parameters: chat_parameters)
    parse_response(response)
  rescue OpenAI::Error => e
    captain_logger.warn "OpenAI API Error: #{e.message}"
    []
  end

  private

  attr_reader :content, :language

  def chat_parameters
    prompt = Captain::Llm::SystemPromptsService.faq_generator(language)
    {
      model: @model,
      response_format: { type: 'json_object' },
      messages: [
        {
          role: 'system',
          content: prompt
        },
        {
          role: 'user',
          content: content
        }
      ]
    }
  end

  def parse_response(response)
    content = response.dig('choices', 0, 'message', 'content')
    return [] if content.nil?

    JSON.parse(content.strip).fetch('faqs', [])
  rescue JSON::ParserError => e
    captain_logger.warn "Error in parsing GPT processed response: #{e.message}"
    []
  end

  def captain_logger
    Captain::Logger.logger
  end
end
