module Captain
  # Service to handle conversation state tracking when Captain responds
  # This should be called from wherever Captain generates messages
  class ConversationHandlerService
    def initialize(conversation, message)
      @conversation = conversation
      @message = message
      @state_service = ConversationStateService.new(conversation)
    end

    # Call this BEFORE generating Captain's response
    def before_response
      # Track sentiment from incoming user message
      @state_service.track_sentiment(@message.content, 'user') if @message.incoming?

      # Increment turn count
      @state_service.increment_turn_count

      # Update issue summary if this is the first few turns
      update_issue_summary if (@state_service.state[:turn_count] || 0) <= 2 && @message.incoming?

      Captain::Logger.info(
        '[ConversationHandler] Before response',
        conversation_id: @conversation.id,
        turn_count: @state_service.state[:turn_count],
        sentiment: @state_service.state[:sentiment_history]&.last
      )
    end

    # Call this AFTER generating Captain's response
    def after_response(captain_message, solution_id: nil)
      # Track solution if one was suggested
      @state_service.track_solution_attempt(solution_id, captain_message.id) if solution_id.present?

      Captain::Logger.info(
        '[ConversationHandler] After response',
        conversation_id: @conversation.id,
        captain_message_id: captain_message.id,
        solution_tracked: solution_id.present?
      )
    end

    # Get context to inject into system prompt
    def get_prompt_context
      summary = @state_service.get_conversation_summary
      return nil if summary[:turn_count] < 2

      context_parts = []

      # Add issue context
      context_parts << "CURRENT ISSUE: #{summary[:issue]}" if summary[:issue].present?

      # Add attempted solutions with feedback
      if summary[:attempted_solutions].any?
        solutions_text = summary[:attempted_solutions].map do |s|
          feedback = s[:agent_feedback] ? " (agent feedback: #{s[:agent_feedback]})" : ''
          "- #{s[:solution]}#{feedback}"
        end.join("\n")

        context_parts << <<~TEXT
          ALREADY ATTEMPTED SOLUTIONS:
          #{solutions_text}

          IMPORTANT: Do NOT suggest these solutions again unless agent feedback was positive.
        TEXT
      end

      # Add sentiment warning
      case summary[:sentiment_trend]
      when :frustrated
        context_parts << '⚠️ USER SENTIMENT: Customer is getting frustrated. Be extra helpful and concise.'
      when :angry
        context_parts << '⚠️⚠️ USER SENTIMENT: Customer is very frustrated. Consider recommending human assistance.'
      end

      # Add turn count warning
      if summary[:turn_count] > 7
        context_parts << "⚠️ TURN COUNT: Turn ##{summary[:turn_count]}. If solution not found soon, suggest human assistance."
      end

      # Add escalation suggestion
      if summary[:should_escalate]
        context_parts << '⚠️ ESCALATION: Multiple indicators suggest this conversation should be escalated to a human agent.'
      end

      context_parts.any? ? context_parts.join("\n\n") : nil
    end

    # Check if should suggest escalation
    def should_suggest_escalation?
      @state_service.should_suggest_escalation?
    end

    # Get escalation message
    def escalation_message
      "\n\n---\n💡 *This conversation has been ongoing for a while. " \
        'Would you like me to connect you with a human specialist for personalized assistance?*'
    end

    private

    def update_issue_summary
      # Extract a simple summary from the first user message
      summary = @message.content.truncate(200)
      @state_service.update_issue_summary(summary)
    end
  end
end
