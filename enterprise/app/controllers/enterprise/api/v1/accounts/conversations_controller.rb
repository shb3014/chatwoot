module Enterprise::Api::V1::Accounts::ConversationsController
  extend ActiveSupport::Concern

  def inbox_assistant
    assistant = @conversation.inbox.captain_assistant

    if assistant
      render json: { assistant: { id: assistant.id, name: assistant.name } }
    else
      render json: { assistant: nil }
    end
  end

  def summarize
    force = ActiveModel::Type::Boolean.new.cast(params[:force])

    unless force
      # Conversations with an exclusive label are fully classified; return existing summary (if any) without regenerating.
      if @conversation.has_exclusive_label?
        render json: { summary: @conversation.captain_summary }
        return
      end

      existing_summary = @conversation.captain_summary
      if existing_summary.present? && existing_summary['generated_at'].present?
        generated_at = begin
          Time.parse(existing_summary['generated_at'])
        rescue StandardError
          nil
        end
        if generated_at && generated_at > 1.hour.ago
          render json: { summary: existing_summary }
          return
        end
      end
    end

    # Generate a new summary synchronously
    result = Captain::Llm::ConversationSummarizationService.new(@conversation).generate
    if result
      render json: { summary: @conversation.reload.captain_summary }
    else
      render json: { error: 'Failed to generate summary' }, status: :unprocessable_entity
    end
  end

  def permitted_update_params
    super.merge(params.permit(:sla_policy_id))
  end

  private

  def copilot_params
    params.permit(:previous_history, :message, :assistant_id)
  end
end
