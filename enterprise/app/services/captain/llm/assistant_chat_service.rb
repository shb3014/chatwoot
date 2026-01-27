require 'openai'

class Captain::Llm::AssistantChatService < Llm::BaseOpenAiService
  include Captain::ChatHelper

  def initialize(assistant: nil, conversation: nil)
    super()

    @assistant = assistant
    @conversation = conversation
    @messages = [system_message]
    @response = ''
    register_tools
  end

  # additional_message: A single message (String) from the user that should be appended to the chat.
  #                    It can be an empty String or nil when you only want to supply historical messages.
  # message_history:   An Array of already formatted messages that provide the previous context.
  # role:              The role for the additional_message (defaults to `user`).
  #
  # NOTE: Parameters are provided as keyword arguments to improve clarity and avoid relying on
  # positional ordering.
  def generate_response(additional_message: nil, message_history: [], role: 'user')
    @messages += message_history
    learned_context = learned_conversation_context(additional_message, message_history)
    @messages << { role: 'system', content: learned_context } if learned_context.present?
    @messages << { role: role, content: additional_message } if additional_message.present?
    request_chat_completion
  end

  private

  def register_tools
    @tool_registry = Captain::ToolRegistryService.new(@assistant, user: nil, conversation: @conversation)
    @tool_registry.register_tool(Captain::Tools::SearchDocumentationService)
  end

  def system_message
    {
      role: 'system',
      content: Captain::Llm::SystemPromptsService.assistant_response_generator(@assistant.name, @assistant.config['product_name'], @assistant.config)
    }
  end

  def learned_conversation_context(additional_message, message_history)
    query = additional_message.presence || last_user_message_from_history(message_history)
    return if query.blank?
    return if @assistant.blank?

    Captain::Llm::LearnedConversationsContextService.new(
      assistant: @assistant,
      conversation: @conversation,
      query: query
    ).build
  end

  def last_user_message_from_history(message_history)
    message = message_history.reverse.find { |entry| entry[:role] == 'user' }
    message&.fetch(:content, nil)
  end

  def persist_message(message, message_type = 'assistant')
    # No need to implement
  end
end
