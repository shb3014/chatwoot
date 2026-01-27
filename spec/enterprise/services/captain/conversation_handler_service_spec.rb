require 'rails_helper'

RSpec.describe Captain::ConversationHandlerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:message) { create(:message, :incoming, conversation: conversation, account: account, content: 'I need help with my password') }
  let(:captain_message) { create(:message, conversation: conversation, account: account, sender_type: 'AgentBot') }
  let(:service) { described_class.new(conversation, message) }

  before do
    allow(Captain::Logger).to receive(:info)
    allow(Captain::Logger).to receive(:debug)
  end

  describe '#initialize' do
    it 'sets conversation and message' do
      expect(service.instance_variable_get(:@conversation)).to eq(conversation)
      expect(service.instance_variable_get(:@message)).to eq(message)
    end

    it 'initializes ConversationStateService' do
      state_service = service.instance_variable_get(:@state_service)
      expect(state_service).to be_a(Captain::ConversationStateService)
    end
  end

  describe '#before_response' do
    context 'with incoming user message' do
      it 'tracks sentiment from message content' do
        state_service = instance_double(Captain::ConversationStateService, state: {})
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:track_sentiment)
        allow(state_service).to receive(:increment_turn_count)
        allow(state_service).to receive(:update_issue_summary)

        handler = described_class.new(conversation, message)
        handler.before_response

        expect(state_service).to have_received(:track_sentiment).with(message.content, 'user')
      end

      it 'increments turn count' do
        state_service = instance_double(Captain::ConversationStateService, state: {})
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:track_sentiment)
        allow(state_service).to receive(:increment_turn_count)
        allow(state_service).to receive(:update_issue_summary)

        handler = described_class.new(conversation, message)
        handler.before_response

        expect(state_service).to have_received(:increment_turn_count)
      end

      it 'updates issue summary for first two turns' do
        state_service = instance_double(Captain::ConversationStateService, state: { turn_count: 1 })
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:track_sentiment)
        allow(state_service).to receive(:increment_turn_count)
        allow(state_service).to receive(:update_issue_summary)

        handler = described_class.new(conversation, message)
        handler.before_response

        expect(state_service).to have_received(:update_issue_summary)
      end

      it 'does not update issue summary after turn 2' do
        state_service = instance_double(Captain::ConversationStateService, state: { turn_count: 3 })
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:track_sentiment)
        allow(state_service).to receive(:increment_turn_count)
        allow(state_service).to receive(:update_issue_summary)

        handler = described_class.new(conversation, message)
        handler.before_response

        expect(state_service).not_to have_received(:update_issue_summary)
      end

      it 'logs before response event' do
        service.before_response

        expect(Captain::Logger).to have_received(:info).with(
          '[ConversationHandler] Before response',
          hash_including(
            conversation_id: conversation.id,
            turn_count: anything
          )
        )
      end
    end

    context 'with outgoing message' do
      let(:outgoing_message) { create(:message, conversation: conversation, account: account, message_type: :outgoing) }
      let(:service) { described_class.new(conversation, outgoing_message) }

      it 'does not track sentiment for outgoing messages' do
        state_service = instance_double(Captain::ConversationStateService, state: {})
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:track_sentiment)
        allow(state_service).to receive(:increment_turn_count)

        handler = described_class.new(conversation, outgoing_message)
        handler.before_response

        expect(state_service).not_to have_received(:track_sentiment)
      end
    end
  end

  describe '#after_response' do
    context 'when solution is provided' do
      it 'tracks solution attempt' do
        state_service = instance_double(Captain::ConversationStateService)
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:track_solution_attempt)

        handler = described_class.new(conversation, message)
        handler.after_response(captain_message, solution_id: 'reset_password')

        expect(state_service).to have_received(:track_solution_attempt).with('reset_password', captain_message.id)
      end

      it 'logs after response event with solution' do
        service.after_response(captain_message, solution_id: 'check_network')

        expect(Captain::Logger).to have_received(:info).with(
          '[ConversationHandler] After response',
          hash_including(
            conversation_id: conversation.id,
            captain_message_id: captain_message.id,
            solution_tracked: true
          )
        )
      end
    end

    context 'when no solution is provided' do
      it 'does not track solution attempt' do
        state_service = instance_double(Captain::ConversationStateService)
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:track_solution_attempt)

        handler = described_class.new(conversation, message)
        handler.after_response(captain_message)

        expect(state_service).not_to have_received(:track_solution_attempt)
      end

      it 'logs after response event without solution' do
        service.after_response(captain_message)

        expect(Captain::Logger).to have_received(:info).with(
          '[ConversationHandler] After response',
          hash_including(
            conversation_id: conversation.id,
            solution_tracked: false
          )
        )
      end
    end
  end

  describe '#get_prompt_context' do
    let(:state_service) { Captain::ConversationStateService.new(conversation) }

    before do
      allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
    end

    context 'with minimal conversation history' do
      it 'returns nil when turn count is less than 2' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 1,
          attempted_solutions: [],
          sentiment_trend: :calm,
          should_escalate: false
        )

        handler = described_class.new(conversation, message)
        expect(handler.get_prompt_context).to be_nil
      end
    end

    context 'with conversation history' do
      it 'includes issue summary in context' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 3,
          issue: 'WiFi connection problems',
          attempted_solutions: [],
          sentiment_trend: :calm,
          should_escalate: false
        )

        handler = described_class.new(conversation, message)
        context = handler.get_prompt_context

        expect(context).to include('CURRENT ISSUE: WiFi connection problems')
      end

      it 'includes attempted solutions with feedback' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 3,
          attempted_solutions: [
            { solution: 'reset_router', agent_feedback: 'helpful' },
            { solution: 'check_cables', agent_feedback: nil }
          ],
          sentiment_trend: :calm,
          should_escalate: false
        )

        handler = described_class.new(conversation, message)
        context = handler.get_prompt_context

        expect(context).to include('ALREADY ATTEMPTED SOLUTIONS')
        expect(context).to include('reset_router (agent feedback: helpful)')
        expect(context).to include('check_cables')
        expect(context).to include('Do NOT suggest these solutions again')
      end

      it 'includes frustrated sentiment warning' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 4,
          attempted_solutions: [],
          sentiment_trend: :frustrated,
          should_escalate: false
        )

        handler = described_class.new(conversation, message)
        context = handler.get_prompt_context

        expect(context).to include('⚠️ USER SENTIMENT')
        expect(context).to include('Customer is getting frustrated')
      end

      it 'includes angry sentiment warning' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 4,
          attempted_solutions: [],
          sentiment_trend: :angry,
          should_escalate: false
        )

        handler = described_class.new(conversation, message)
        context = handler.get_prompt_context

        expect(context).to include('⚠️⚠️ USER SENTIMENT')
        expect(context).to include('very frustrated')
      end

      it 'includes turn count warning for high turns' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 8,
          attempted_solutions: [],
          sentiment_trend: :calm,
          should_escalate: false
        )

        handler = described_class.new(conversation, message)
        context = handler.get_prompt_context

        expect(context).to include('⚠️ TURN COUNT')
        expect(context).to include('Turn #8')
      end

      it 'includes escalation suggestion when needed' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 12,
          attempted_solutions: [],
          sentiment_trend: :calm,
          should_escalate: true
        )

        handler = described_class.new(conversation, message)
        context = handler.get_prompt_context

        expect(context).to include('⚠️ ESCALATION')
        expect(context).to include('escalated to a human agent')
      end

      it 'returns nil when no context parts are generated' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 3,
          issue: nil,
          attempted_solutions: [],
          sentiment_trend: :calm,
          should_escalate: false
        )

        handler = described_class.new(conversation, message)
        expect(handler.get_prompt_context).to be_nil
      end

      it 'combines multiple context elements correctly' do
        allow(state_service).to receive(:get_conversation_summary).and_return(
          turn_count: 9,
          issue: 'Login problems',
          attempted_solutions: [
            { solution: 'reset_password', agent_feedback: 'unhelpful' }
          ],
          sentiment_trend: :frustrated,
          should_escalate: true
        )

        handler = described_class.new(conversation, message)
        context = handler.get_prompt_context

        expect(context).to include('CURRENT ISSUE: Login problems')
        expect(context).to include('ALREADY ATTEMPTED SOLUTIONS')
        expect(context).to include('⚠️ USER SENTIMENT')
        expect(context).to include('⚠️ TURN COUNT')
        expect(context).to include('⚠️ ESCALATION')
      end
    end
  end

  describe '#should_suggest_escalation?' do
    it 'delegates to state service' do
      state_service = instance_double(Captain::ConversationStateService)
      allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
      allow(state_service).to receive(:should_suggest_escalation?).and_return(true)

      handler = described_class.new(conversation, message)
      expect(handler.should_suggest_escalation?).to be true
      expect(state_service).to have_received(:should_suggest_escalation?)
    end
  end

  describe '#escalation_message' do
    it 'returns appropriate escalation message' do
      message = service.escalation_message

      expect(message).to include('human specialist')
      expect(message).to include('personalized assistance')
    end

    it 'includes markdown formatting' do
      message = service.escalation_message

      expect(message).to start_with("\n\n---\n")
      expect(message).to include('💡')
    end
  end

  describe 'integration flow' do
    it 'properly tracks a complete conversation turn' do
      # Simulate a complete conversation turn
      service.before_response
      service.after_response(captain_message, solution_id: 'update_app')

      # Reload and verify state
      conversation.reload
      state = conversation.captain_state

      expect(state['turn_count']).to be > 0
      expect(state['attempted_solutions']).to be_present
      expect(state['sentiment_history']).to be_present
    end

    it 'builds appropriate context for subsequent turns' do
      # First turn
      service.before_response
      service.after_response(captain_message, solution_id: 'restart_device')

      # Second turn
      message2 = create(:message, :incoming, conversation: conversation, content: 'That didn\'t work')
      service2 = described_class.new(conversation, message2)
      service2.before_response

      # Get context for third turn
      message3 = create(:message, :incoming, conversation: conversation, content: 'Still having issues')
      service3 = described_class.new(conversation, message3)
      service3.before_response

      context = service3.get_prompt_context
      expect(context).to include('restart_device')
    end
  end

  describe 'private methods' do
    describe '#update_issue_summary' do
      it 'truncates long messages to 200 characters' do
        long_message = create(:message, :incoming,
                              conversation: conversation,
                              content: 'a' * 300)

        handler = described_class.new(conversation, long_message)
        handler.send(:update_issue_summary)

        conversation.reload
        summary = conversation.captain_state['issue_summary']
        expect(summary.length).to be <= 203 # 200 + "..."
      end

      it 'preserves short messages' do
        short_message = create(:message, :incoming,
                               conversation: conversation,
                               content: 'Short message')

        handler = described_class.new(conversation, short_message)
        handler.send(:update_issue_summary)

        conversation.reload
        summary = conversation.captain_state['issue_summary']
        expect(summary).to eq('Short message')
      end
    end
  end
end
