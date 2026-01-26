module Captain
  class MessageFeedbackService
    def initialize(message, agent)
      @message = message
      @agent = agent
      @conversation = message.conversation
    end

    def record_feedback(rating:, feedback_type: nil, notes: nil)
      # Find or create feedback record
      feedback = CaptainMessageFeedback.find_or_initialize_by(
        message: @message,
        rated_by: @agent
      )

      feedback.assign_attributes(
        conversation: @conversation,
        rating: rating,
        feedback_type: feedback_type,
        notes: notes
      )

      if feedback.save
        # Update conversation state with feedback
        update_conversation_state(feedback)

        Captain::Logger.info(
          '[MessageFeedback] Feedback recorded',
          message_id: @message.id,
          conversation_id: @conversation.id,
          agent_id: @agent.id,
          rating: rating,
          feedback_type: feedback_type
        )

        { success: true, feedback: feedback }
      else
        Captain::Logger.error(
          '[MessageFeedback] Failed to save feedback',
          message_id: @message.id,
          errors: feedback.errors.full_messages
        )

        { success: false, errors: feedback.errors.full_messages }
      end
    end

    def record_resolution(resolved:, resolution_method:)
      feedback = CaptainMessageFeedback.find_by(message: @message, rated_by: @agent)

      unless feedback
        Captain::Logger.warn(
          '[MessageFeedback] No feedback found to update resolution',
          message_id: @message.id,
          agent_id: @agent.id
        )
        return { success: false, error: 'Feedback not found' }
      end

      if feedback.update(
        issue_resolved: resolved,
        resolution_method: resolution_method
      )
        Captain::Logger.info(
          '[MessageFeedback] Resolution recorded',
          message_id: @message.id,
          conversation_id: @conversation.id,
          resolved: resolved,
          method: resolution_method
        )

        { success: true, feedback: feedback }
      else
        { success: false, errors: feedback.errors.full_messages }
      end
    end

    def get_feedback
      CaptainMessageFeedback.find_by(message: @message, rated_by: @agent)
    end

    private

    def update_conversation_state(feedback)
      state_service = ConversationStateService.new(@conversation)

      # Map feedback type to simplified format for state tracking
      feedback_label = if feedback.rating > 0
                         feedback.feedback_type || 'helpful'
                       elsif feedback.rating < 0
                         feedback.feedback_type || 'unhelpful'
                       else
                         feedback.feedback_type || 'neutral'
                       end

      state_service.update_solution_feedback(@message.id, feedback_label)
    end
  end
end
