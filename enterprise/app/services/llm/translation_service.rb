class Llm::TranslationService < Llm::BaseOpenAiService
  def initialize(conversation = nil)
    super(model_type: :fast)
    @conversation = conversation
  end

  def translate_message(message, target_language: nil)
    return message if message.blank?

    target_language ||= determine_target_language
    return message unless target_language

    captain_logger.info "[Translation] START model=#{@model} target_language=#{target_language} " \
                        "content_length=#{message.length} client=#{@client.class.name}"

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @client.chat(parameters: translation_parameters(message, target_language))
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    result = parse_translation_response(response, message)
    usage = response&.dig('usage')
    captain_logger.info "[Translation] OK in #{elapsed_ms}ms " \
                        "response_length=#{result&.length || 0} " \
                        "tokens=#{usage&.to_json || 'N/A'}"
    result

  rescue StandardError => e
    elapsed_ms = if start_time
                   ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
                 else
                   0
                 end
    captain_logger.error "[Translation] FAILED after #{elapsed_ms}ms: #{e.class} — #{e.message}"
    captain_logger.error "[Translation] Backtrace: #{e.backtrace.first(5).join("\n")}"
    message
  end

  # Translate multiple messages in a single streaming LLM call.
  # Messages are concatenated with <<<MSG:id>>> delimiters. As the stream
  # progresses and message boundaries are detected, each completed translation
  # is yielded to the caller via the block.
  #
  # @param messages [Array<Hash>] each with :id and :content keys
  # @param target_language [String]
  # @yield [message_id, translation] called for each completed message
  def stream_translate_batch(messages, target_language:)
    return if messages.blank?

    # ActiveJob deserializes hash keys as strings, so support both symbol and string keys
    msgs = messages.map { |m| m.with_indifferent_access }
    concatenated = msgs.map { |m| "<<<MSG:#{m[:id]}>>>\n#{m[:content]}" }.join("\n")

    total_length = concatenated.length
    captain_logger.info "[Translation][Batch] Streaming START model=#{@model} target=#{target_language} " \
                        "msg_count=#{msgs.size} total_length=#{total_length}"

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    accumulated = +''
    current_msg_id = nil
    emitted_count = 0

    stream_proc = proc do |chunk|
      delta = chunk.dig('choices', 0, 'delta', 'content')
      next unless delta.present?

      accumulated << delta

      # Scan for <<<MSG:id>>> boundaries in the accumulated text
      loop do
        match = accumulated.match(/<<<MSG:(\d+)>>>/)
        break unless match

        if current_msg_id
          # Everything before this marker is the translation of current_msg_id
          translation = accumulated[0...match.begin(0)].strip
          if translation.present?
            yield(current_msg_id, translation)
            emitted_count += 1
          end
        end

        current_msg_id = match[1].to_i
        accumulated = accumulated[(match.end(0))..]
      end
    end

    parameters = batch_translation_parameters(concatenated, target_language)
    @client.chat(parameters: parameters, stream: stream_proc)

    # Emit the last message (after the final <<<MSG:id>>> marker, no trailing marker)
    if current_msg_id && accumulated.strip.present?
      yield(current_msg_id, accumulated.strip)
      emitted_count += 1
    end

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    captain_logger.info "[Translation][Batch] Streaming DONE in #{elapsed_ms}ms " \
                        "emitted=#{emitted_count}/#{msgs.size}"
  end

  private

  def determine_target_language
    conversation_language = @conversation.language
    account_locale = @conversation.account.locale_english_name

    if conversation_language.present?
      captain_logger.info "[Translation] Using conversation language: #{conversation_language}"
      return conversation_language
    end

    if account_locale.present? && account_locale.downcase != 'english'
      captain_logger.info "[Translation] Using account locale: #{account_locale}"
      return account_locale
    end

    detect_language_from_conversation
  end

  def detect_language_from_conversation
    recent_messages = @conversation.messages
                                   .where(message_type: :incoming)
                                   .where(private: false)
                                   .order(created_at: :desc)
                                   .limit(5)
                                   .pluck(:content)
                                   .reject(&:blank?)

    if recent_messages.empty?
      captain_logger.warn '[Translation] No messages available for language detection'
      return nil
    end

    captain_logger.info "[Translation] Detecting language from #{recent_messages.length} messages..."
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    response = @client.chat(
      parameters: {
        model: @model,
        messages: [
          {
            role: 'system',
            content: 'You are a language detection assistant. Analyze the provided conversation messages and identify the primary language used by the user. Return ONLY the language name in English (e.g., "Chinese", "Spanish", "French", "English"). If you cannot determine the language, return "English".'
          },
          {
            role: 'user',
            content: "Detect the language from these messages:\n\n#{recent_messages.join("\n\n")}"
          }
        ]
      }
    )

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    detected = response.dig('choices', 0, 'message', 'content')&.strip
    captain_logger.info "[Translation] Language detected: '#{detected}' in #{elapsed_ms}ms"
    detected.presence
  rescue StandardError => e
    captain_logger.error "[Translation] Language detection failed: #{e.class} — #{e.message}"
    nil
  end

  def batch_translation_parameters(concatenated_content, target_language)
    {
      model: @model,
      messages: [
        {
          role: 'system',
          content: "You are a translation assistant. Translate the following messages to #{target_language}. " \
                   'Each message starts with a <<<MSG:ID>>> marker. ' \
                   'Within each message, text segments may be separated by <<<SEG>>> delimiters. ' \
                   'Preserve every <<<MSG:ID>>> marker and <<<SEG>>> delimiter exactly as-is in the output. ' \
                   'Only translate the human-readable text between markers and delimiters. ' \
                   'Return only the translated content without explanations.'
        },
        {
          role: 'user',
          content: concatenated_content
        }
      ]
    }
  end

  def translation_parameters(message, target_language)
    {
      model: @model,
      messages: [
        {
          role: 'system',
          content: "You are a translation assistant. Translate the following text to #{target_language}. " \
                   'Preserve all original formatting including markdown syntax, line breaks, and lists. ' \
                   'The text may contain <<<SEG>>> delimiters that separate independent segments — ' \
                   'preserve every <<<SEG>>> delimiter exactly as-is in the output. ' \
                   'Only translate the human-readable text between delimiters. ' \
                   'Return only the translated content without explanations.'
        },
        {
          role: 'user',
          content: message
        }
      ]
    }
  end

  def parse_translation_response(response, original_message)
    response.dig('choices', 0, 'message', 'content')&.strip || original_message
  end
end
