# Sidekiq job that translates a batch of messages in a single streaming LLM call.
# As each message's translation completes in the stream, it is broadcast to the
# frontend via ActionCable so the agent sees results progressively.
class Captain::TranslationBatchJob < ApplicationJob
  queue_as :default

  def perform(account_id:, user_id:, conversation_id:, messages:, target_language:)
    @account = Account.find(account_id)
    @user = @account.users.find(user_id)
    @conversation_id = conversation_id
    @user_token = @user.pubsub_token

    captain_logger.info "[Translation][Batch] START account=#{account_id} user=#{user_id} " \
                        "conversation=#{conversation_id} messages=#{messages.size} target=#{target_language}"

    service = Llm::TranslationService.new
    service.stream_translate_batch(messages, target_language: target_language) do |msg_id, translation|
      broadcast_message_completed(msg_id, translation)
    end

    broadcast_batch_completed
  rescue StandardError => e
    captain_logger.error "[Translation][Batch] FAILED: #{e.class} — #{e.message}"
    captain_logger.error "[Translation][Batch] Backtrace: #{e.backtrace.first(5).join("\n")}"
    broadcast_batch_completed(error: e.message)
  end

  private

  def broadcast_message_completed(message_id, translation)
    ActionCable.server.broadcast(
      @user_token,
      {
        event: 'translation.message.completed',
        data: {
          account_id: @account.id,
          conversation_id: @conversation_id,
          message_id: message_id,
          translation: translation
        }
      }
    )
  end

  def broadcast_batch_completed(error: nil)
    ActionCable.server.broadcast(
      @user_token,
      {
        event: 'translation.batch.completed',
        data: {
          account_id: @account.id,
          conversation_id: @conversation_id,
          error: error
        }
      }
    )
  end

  def captain_logger
    Captain::Logger.logger
  rescue NameError
    Rails.logger
  end
end
