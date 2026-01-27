module Captain
  class ConversationStateService
    attr_reader :state

    def initialize(conversation)
      @conversation = conversation
      @state = load_or_initialize_state
    end

    # Track when Captain suggests a solution
    def track_solution_attempt(solution_id, message_id)
      @state[:attempted_solutions] ||= []
      @state[:attempted_solutions] << {
        solution: solution_id,
        result: 'suggested',
        timestamp: Time.current.to_i,
        message_id: message_id,
        agent_feedback: nil
      }
      # Keep only last 10 attempts to avoid bloat
      @state[:attempted_solutions] = @state[:attempted_solutions].last(10)
      save_state

      Captain::Logger.info(
        '[ConversationState] Solution tracked',
        conversation_id: @conversation.id,
        solution: solution_id,
        message_id: message_id,
        total_attempts: @state[:attempted_solutions].size
      )
    end

    # Update when agent provides feedback
    def update_solution_feedback(message_id, feedback)
      @state[:attempted_solutions] ||= []
      solution = @state[:attempted_solutions].find { |s| s[:message_id] == message_id }
      return unless solution

      solution[:agent_feedback] = feedback
      save_state

      Captain::Logger.info(
        '[ConversationState] Solution feedback updated',
        conversation_id: @conversation.id,
        message_id: message_id,
        feedback: feedback
      )
    end

    # Record when human agent takes over
    def track_human_takeover(agent_id, message_id)
      @state[:human_intervention] = {
        happened: true,
        agent_id: agent_id,
        at_turn: @state[:turn_count] || 0,
        timestamp: Time.current.to_i,
        message_id: message_id
      }

      @conversation.update_columns(
        captain_handed_off_at: Time.current,
        captain_handed_off_by_id: agent_id
      )

      save_state

      Captain::Logger.info(
        '[ConversationState] Human takeover tracked',
        conversation_id: @conversation.id,
        agent_id: agent_id,
        at_turn: @state[:turn_count],
        message_id: message_id
      )
    end

    # Track sentiment from user messages
    def track_sentiment(message_content, sender_type)
      return unless sender_type == 'user'

      sentiment = detect_sentiment(message_content)
      @state[:sentiment_history] ||= []
      @state[:sentiment_history] << {
        sentiment: sentiment,
        timestamp: Time.current.to_i
      }
      # Keep only last 5 sentiment readings
      @state[:sentiment_history] = @state[:sentiment_history].last(5)
      save_state

      Captain::Logger.debug(
        '[ConversationState] Sentiment tracked',
        conversation_id: @conversation.id,
        sentiment: sentiment,
        trend: calculate_sentiment_trend
      )
    end

    # Increment turn count
    def increment_turn_count
      @state[:turn_count] ||= 0
      @state[:turn_count] += 1
      save_state

      Captain::Logger.debug(
        '[ConversationState] Turn count incremented',
        conversation_id: @conversation.id,
        turn_count: @state[:turn_count]
      )
    end

    # Update issue summary (extracted from first few messages)
    def update_issue_summary(summary)
      @state[:issue_summary] = summary
      save_state
    end

    # Check if should suggest escalation (not force!)
    def should_suggest_escalation?
      reasons = []

      # Too many turns without resolution
      reasons << :too_many_turns if (@state[:turn_count] || 0) > 10

      # Same solution suggested multiple times
      reasons << :repeated_suggestions if repeated_suggestions_count >= 3

      # User is frustrated or angry
      reasons << :user_frustrated if frustration_level == :angry

      if reasons.any?
        @state[:escalation_suggested] = true
        @state[:escalation_reasons] = reasons.map(&:to_s)
        save_state

        Captain::Logger.info(
          '[ConversationState] Escalation suggested',
          conversation_id: @conversation.id,
          reasons: reasons,
          turn_count: @state[:turn_count]
        )
      end

      reasons.any?
    end

    # Get conversation summary for UI or prompts
    def get_conversation_summary
      {
        issue: @state[:issue_summary],
        attempted_solutions: @state[:attempted_solutions] || [],
        sentiment_trend: calculate_sentiment_trend,
        turn_count: @state[:turn_count] || 0,
        should_escalate: should_suggest_escalation?,
        escalation_reasons: @state[:escalation_reasons] || [],
        marked_for_review: marked_for_review?,
        human_took_over: @state[:human_intervention].present?,
        human_intervention: @state[:human_intervention]
      }
    end

    # Reset state (useful for testing or manual intervention)
    def reset_state
      @state = {}
      save_state

      Captain::Logger.info(
        '[ConversationState] State reset',
        conversation_id: @conversation.id
      )
    end

    private

    def load_or_initialize_state
      state = @conversation.captain_state || {}
      # Ensure it's a hash with symbol keys
      state.is_a?(Hash) ? state.deep_symbolize_keys : {}
    end

    def save_state
      # Convert to JSON-compatible hash (string keys)
      json_state = @state.deep_stringify_keys
      @conversation.update_columns(
        captain_state: json_state,
        captain_last_action_at: Time.current
      )
    end

    def marked_for_review?
      # Check if conversation has the "记录" label
      @conversation.labels.exists?(name: '记录')
    end

    def detect_sentiment(message_content)
      # Simple keyword-based sentiment detection
      # TODO: Could be enhanced with LLM-based sentiment analysis

      negative_keywords = [
        'frustrated', 'angry', 'upset', 'terrible', 'awful', 'horrible',
        'worst', 'hate', 'useless', 'broken', 'doesn\'t work',
        '生气', '沮丧', '糟糕', '讨厌', '没用', '坏了'
      ]

      positive_keywords = [
        'thanks', 'thank you', 'great', 'perfect', 'excellent',
        'awesome', 'solved', 'worked', 'fixed', 'resolved',
        '谢谢', '太好了', '完美', '解决了', '好的'
      ]

      content_lower = message_content.downcase
      negative_count = negative_keywords.count { |kw| content_lower.include?(kw) }
      positive_count = positive_keywords.count { |kw| content_lower.include?(kw) }

      if negative_count > positive_count && negative_count > 0
        :negative
      elsif positive_count > negative_count && positive_count > 0
        :positive
      else
        :neutral
      end
    end

    def calculate_sentiment_trend
      history = @state[:sentiment_history] || []
      return :calm if history.empty?

      recent = history.last(3)
      negative_count = recent.count { |h| h[:sentiment] == 'negative' || h[:sentiment] == :negative }
      positive_count = recent.count { |h| h[:sentiment] == 'positive' || h[:sentiment] == :positive }

      case negative_count
      when 0
        positive_count > 0 ? :happy : :calm
      when 1
        :slightly_concerned
      when 2
        :frustrated
      else
        :angry
      end
    end

    def repeated_suggestions_count
      attempts = @state[:attempted_solutions] || []
      solutions = attempts.map { |a| a[:solution] }
      # Count unique solutions vs total attempts
      total_attempts = solutions.size
      unique_solutions = solutions.uniq.size
      total_attempts - unique_solutions
    end

    def frustration_level
      calculate_sentiment_trend
    end
  end
end
