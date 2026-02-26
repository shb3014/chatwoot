class Api::V1::Accounts::Captain::TranslationsController < Api::V1::Accounts::BaseController
  def create
    content = params[:content]
    target_language = params[:target_language]

    return render_could_not_create_error('Content is required') if content.blank?
    return render_could_not_create_error('Target language is required') if target_language.blank?

    captain_logger.info "[Translation][Controller] Received: target_language=#{target_language} " \
                        "content_length=#{content.length} account=#{current_account.id}"
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    service = Llm::TranslationService.new
    translation = service.translate_message(content, target_language: target_language)

    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round
    captain_logger.info "[Translation][Controller] Done in #{elapsed_ms}ms " \
                        "response_length=#{translation&.length || 0}"

    render json: { translation: translation }
  end

  # Batch-translate multiple messages in a single streaming LLM call.
  # Results are delivered progressively via ActionCable.
  def batch_create
    messages = params[:messages]
    target_language = params[:target_language]
    conversation_id = params[:conversation_id]

    return render_could_not_create_error('Messages are required') if messages.blank?
    return render_could_not_create_error('Target language is required') if target_language.blank?

    # Normalize messages to an array of { id:, content: } hashes
    normalized = messages.map { |m| { id: m[:id].to_i, content: m[:content].to_s } }
                         .reject { |m| m[:content].blank? }

    captain_logger.info "[Translation][Controller] Batch received: conversation=#{conversation_id} " \
                        "messages=#{normalized.size} target=#{target_language} account=#{current_account.id}"

    Captain::TranslationBatchJob.perform_later(
      account_id: current_account.id,
      user_id: current_user.id,
      conversation_id: conversation_id.to_i,
      messages: normalized,
      target_language: target_language
    )

    render json: { status: 'streaming', message_count: normalized.size }, status: :accepted
  end

  private

  def captain_logger
    Captain::Logger.logger
  rescue NameError
    Rails.logger
  end
end
