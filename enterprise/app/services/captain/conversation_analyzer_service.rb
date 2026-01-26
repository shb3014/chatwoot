module Captain
  # Analyzes a single conversation to detect patterns, resolution status, and effectiveness
  class ConversationAnalyzerService
    def initialize(conversation)
      @conversation = conversation
      @messages = conversation.messages.order(:created_at)
    end

    def analyze
      {
        conversation_id: @conversation.id,
        total_turns: @messages.count,
        captain_turns: captain_messages.count,
        agent_turns: agent_messages.count,
        customer_turns: customer_messages.count,
        resolution: detect_resolution,
        captain_helped: estimate_captain_effectiveness,
        human_intervention: detect_human_intervention,
        issue_category: detect_issue_category,
        solution_type: detect_solution_type,
        duration_minutes: calculate_duration,
        has_captain_state: @conversation.captain_state.present?
      }
    end

    private

    def detect_resolution
      # Check explicit resolution
      return { status: :resolved, confidence: :high } if @conversation.resolved?

      # Check for positive sentiment in last messages
      last_customer_messages = customer_messages.last(3)
      return { status: :likely_resolved, confidence: :medium } if positive_sentiment_in_messages?(last_customer_messages)

      # Check for follow-up conversation (indicates unresolved)
      return { status: :unresolved, confidence: :high, follow_up: true } if has_follow_up_conversation?

      # Conversation abandoned without clear resolution
      return { status: :abandoned, confidence: :medium } if conversation_abandoned?

      { status: :unknown, confidence: :low }
    end

    def estimate_captain_effectiveness
      # If human agent intervened
      if agent_messages.any?
        first_agent_message = agent_messages.first
        agent_turn_time = first_agent_message.created_at
        captain_turns_before = captain_messages.where('created_at < ?', agent_turn_time).count

        if captain_turns_before == 0
          return { helped: :not_used, turns_before_agent: 0 }
        elsif captain_turns_before >= 5
          return { helped: :not_effective, turns_before_agent: captain_turns_before }
        else
          return { helped: :partial, turns_before_agent: captain_turns_before }
        end
      end

      # No human intervention
      return { helped: :fully_resolved, turns_before_agent: nil } if @conversation.resolved?

      # Captain responded but outcome unclear
      return { helped: :unknown, turns_before_agent: nil } if captain_messages.any?

      { helped: :not_applicable, turns_before_agent: nil }
    end

    def detect_human_intervention
      first_agent_message = agent_messages.first
      return nil unless first_agent_message

      captain_before = captain_messages.where('created_at < ?', first_agent_message.created_at).count

      {
        happened: true,
        at_turn: captain_before + customer_messages.where('created_at < ?', first_agent_message.created_at).count,
        agent_id: first_agent_message.sender_id,
        timestamp: first_agent_message.created_at.to_i,
        captain_turns_before: captain_before
      }
    end

    def detect_issue_category
      # Analyze first customer message for issue type
      first_message = customer_messages.first&.content || ''
      content_lower = first_message.downcase

      case content_lower
      when /password|login|access|sign in|登录|密码/
        :authentication
      when /wifi|connection|network|internet|connect|网络|连接/
        :connectivity
      when /battery|charge|power|电池|充电/
        :battery
      when /order|shipping|delivery|track|订单|发货|物流/
        :order_status
      when /refund|return|cancel|退款|退货|取消/
        :order_issue
      when /setup|install|配置|安装/
        :setup
      when /error|bug|problem|issue|错误|问题/
        :technical_issue
      when /how to|how do|怎么|如何/
        :how_to
      else
        :other
      end
    end

    def detect_solution_type
      # Analyze Captain's responses for solution patterns
      captain_content = captain_messages.pluck(:content).join(' ').downcase

      return :no_captain_response if captain_content.blank?

      if captain_content.match?(/reset|restart|重启|重置/)
        :reset_solution
      elsif captain_content.match?(/update|upgrade|更新|升级/)
        :update_solution
      elsif captain_content.match?(/check|verify|confirm|检查|确认/)
        :diagnostic_solution
      elsif captain_content.match?(/settings|configuration|设置|配置/)
        :configuration_solution
      elsif captain_content.match?(/documentation|manual|guide|说明|文档/)
        :documentation_provided
      else
        :informational
      end
    end

    def calculate_duration
      return nil if @messages.empty?

      first_time = @messages.first.created_at
      last_time = @messages.last.created_at
      ((last_time - first_time) / 60.0).round(2) # minutes
    end

    def captain_messages
      @captain_messages ||= @messages.where(sender_type: 'AgentBot')
    end

    def agent_messages
      @agent_messages ||= @messages.where(sender_type: 'User')
                                   .where.not(sender_id: nil)
                                   .where("sender_id IN (SELECT id FROM users WHERE type = 'User')")
    end

    def customer_messages
      @customer_messages ||= @messages.incoming
    end

    def positive_sentiment_in_messages?(messages)
      return false if messages.empty?

      positive_keywords = ['thanks', 'thank you', 'solved', 'worked', 'great', 'perfect', 'fixed',
                           '谢谢', '解决了', '好的', '太好了', '完美']
      content = messages.map(&:content).join(' ').downcase
      positive_keywords.any? { |kw| content.include?(kw) }
    end

    def has_follow_up_conversation?
      # Check if there's another conversation from same contact within 24 hours after this one
      @conversation.contact.conversations
                   .where('created_at > ? AND created_at < ?',
                          @conversation.created_at + 1.minute,
                          @conversation.created_at + 24.hours)
                   .where.not(id: @conversation.id)
                   .exists?
    end

    def conversation_abandoned?
      # Consider abandoned if last message was from Captain or agent, and > 24 hours ago
      last_message = @messages.last
      return false unless last_message

      last_message.sender_type != 'Contact' && last_message.created_at < 24.hours.ago
    end
  end
end
