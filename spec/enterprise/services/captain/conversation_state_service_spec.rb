require 'rails_helper'

RSpec.describe Captain::ConversationStateService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:service) { described_class.new(conversation) }
  let(:agent) { create(:user, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account) }

  describe '#initialize' do
    it 'loads existing state from conversation' do
      conversation.update_column(:captain_state, { turn_count: 5 })
      service = described_class.new(conversation)

      expect(service.state[:turn_count]).to eq(5)
    end

    it 'initializes empty state if conversation has no state' do
      expect(service.state).to eq({})
    end

    it 'handles nil captain_state gracefully' do
      conversation.update_column(:captain_state, nil)
      service = described_class.new(conversation)

      expect(service.state).to eq({})
    end
  end

  describe '#track_solution_attempt' do
    it 'adds a solution attempt to the state' do
      allow(Captain::Logger).to receive(:info)

      service.track_solution_attempt('reset_password', message.id)

      expect(service.state[:attempted_solutions]).to be_an(Array)
      expect(service.state[:attempted_solutions].size).to eq(1)

      solution = service.state[:attempted_solutions].first
      expect(solution[:solution]).to eq('reset_password')
      expect(solution[:result]).to eq('suggested')
      expect(solution[:message_id]).to eq(message.id)
      expect(solution[:agent_feedback]).to be_nil
      expect(solution[:timestamp]).to be_present
    end

    it 'keeps only last 10 solution attempts' do
      allow(Captain::Logger).to receive(:info)

      15.times do |i|
        service.track_solution_attempt("solution_#{i}", message.id + i)
      end

      expect(service.state[:attempted_solutions].size).to eq(10)
      expect(service.state[:attempted_solutions].first[:solution]).to eq('solution_5')
    end

    it 'saves state to conversation' do
      allow(Captain::Logger).to receive(:info)

      service.track_solution_attempt('check_network', message.id)
      conversation.reload

      expect(conversation.captain_state['attempted_solutions']).to be_present
      expect(conversation.captain_last_action_at).to be_present
    end

    it 'logs solution tracking' do
      allow(Captain::Logger).to receive(:info)

      service.track_solution_attempt('restart_device', message.id)

      expect(Captain::Logger).to have_received(:info).with(
        '[ConversationState] Solution tracked',
        hash_including(
          conversation_id: conversation.id,
          solution: 'restart_device',
          message_id: message.id
        )
      )
    end
  end

  describe '#update_solution_feedback' do
    before do
      allow(Captain::Logger).to receive(:info)
      allow(Captain::Logger).to receive(:debug)
      service.track_solution_attempt('update_app', message.id)
    end

    it 'updates feedback for an existing solution attempt' do
      service.update_solution_feedback(message.id, 'helpful')

      solution = service.state[:attempted_solutions].find { |s| s[:message_id] == message.id }
      expect(solution[:agent_feedback]).to eq('helpful')
    end

    it 'logs feedback update' do
      allow(Captain::Logger).to receive(:info).and_call_original

      service.update_solution_feedback(message.id, 'unhelpful')

      expect(Captain::Logger).to have_received(:info).with(
        '[ConversationState] Solution feedback updated',
        hash_including(
          conversation_id: conversation.id,
          message_id: message.id,
          feedback: 'unhelpful'
        )
      )
    end

    it 'does nothing if message_id not found' do
      service.update_solution_feedback(99_999, 'helpful')

      # State should remain unchanged
      solution = service.state[:attempted_solutions].first
      expect(solution[:agent_feedback]).to be_nil
    end
  end

  describe '#track_human_takeover' do
    before do
      allow(Captain::Logger).to receive(:info)
      allow(Captain::Logger).to receive(:debug)
      service.instance_variable_set(:@state, { turn_count: 5 })
    end

    it 'records human intervention in state' do
      service.track_human_takeover(agent.id, message.id)

      intervention = service.state[:human_intervention]
      expect(intervention[:happened]).to be true
      expect(intervention[:agent_id]).to eq(agent.id)
      expect(intervention[:at_turn]).to eq(5)
      expect(intervention[:message_id]).to eq(message.id)
      expect(intervention[:timestamp]).to be_present
    end

    it 'updates conversation columns' do
      service.track_human_takeover(agent.id, message.id)
      conversation.reload

      expect(conversation.captain_handed_off_at).to be_present
      expect(conversation.captain_handed_off_by_id).to eq(agent.id)
    end

    it 'logs human takeover' do
      service.track_human_takeover(agent.id, message.id)

      expect(Captain::Logger).to have_received(:info).with(
        '[ConversationState] Human takeover tracked',
        hash_including(
          conversation_id: conversation.id,
          agent_id: agent.id,
          at_turn: 5,
          message_id: message.id
        )
      )
    end
  end

  describe '#track_sentiment' do
    before do
      allow(Captain::Logger).to receive(:debug)
    end

    it 'tracks sentiment for user messages' do
      service.track_sentiment('This is terrible and I am frustrated!', 'user')

      expect(service.state[:sentiment_history]).to be_an(Array)
      expect(service.state[:sentiment_history].size).to eq(1)
      expect(service.state[:sentiment_history].first[:sentiment]).to eq(:negative)
    end

    it 'does not track sentiment for non-user messages' do
      service.track_sentiment('Response from agent', 'agent')

      expect(service.state[:sentiment_history]).to be_nil
    end

    it 'keeps only last 5 sentiment readings' do
      8.times do |i|
        service.track_sentiment("Message #{i}", 'user')
      end

      expect(service.state[:sentiment_history].size).to eq(5)
    end

    context 'sentiment detection' do
      it 'detects positive sentiment' do
        service.track_sentiment('Thank you! This worked perfectly!', 'user')
        expect(service.state[:sentiment_history].last[:sentiment]).to eq(:positive)
      end

      it 'detects negative sentiment' do
        service.track_sentiment('This is awful and useless', 'user')
        expect(service.state[:sentiment_history].last[:sentiment]).to eq(:negative)
      end

      it 'detects neutral sentiment' do
        service.track_sentiment('Hello, I have a question', 'user')
        expect(service.state[:sentiment_history].last[:sentiment]).to eq(:neutral)
      end

      it 'detects Chinese positive keywords' do
        service.track_sentiment('谢谢，太好了！', 'user')
        expect(service.state[:sentiment_history].last[:sentiment]).to eq(:positive)
      end

      it 'detects Chinese negative keywords' do
        service.track_sentiment('太糟糕了，我很生气', 'user')
        expect(service.state[:sentiment_history].last[:sentiment]).to eq(:negative)
      end
    end
  end

  describe '#increment_turn_count' do
    it 'increments turn count from 0' do
      allow(Captain::Logger).to receive(:debug)

      service.increment_turn_count
      expect(service.state[:turn_count]).to eq(1)
    end

    it 'increments existing turn count' do
      allow(Captain::Logger).to receive(:debug)
      service.instance_variable_set(:@state, { turn_count: 7 })

      service.increment_turn_count
      expect(service.state[:turn_count]).to eq(8)
    end

    it 'saves state after incrementing' do
      allow(Captain::Logger).to receive(:debug)

      service.increment_turn_count
      conversation.reload

      expect(conversation.captain_state['turn_count']).to eq(1)
    end
  end

  describe '#update_issue_summary' do
    it 'updates the issue summary in state' do
      service.update_issue_summary('Password reset not working')

      expect(service.state[:issue_summary]).to eq('Password reset not working')
    end

    it 'saves state to conversation' do
      service.update_issue_summary('Unable to login')
      conversation.reload

      expect(conversation.captain_state['issue_summary']).to eq('Unable to login')
    end
  end

  describe '#should_suggest_escalation?' do
    before do
      allow(Captain::Logger).to receive(:info)
      allow(Captain::Logger).to receive(:debug)
    end

    it 'suggests escalation when turn count exceeds 10' do
      service.instance_variable_set(:@state, { turn_count: 11 })

      expect(service.should_suggest_escalation?).to be true
      expect(service.state[:escalation_suggested]).to be true
      expect(service.state[:escalation_reasons]).to include('too_many_turns')
    end

    it 'suggests escalation when solutions are repeated 3+ times' do
      allow(service).to receive(:repeated_suggestions_count).and_return(3)

      expect(service.should_suggest_escalation?).to be true
      expect(service.state[:escalation_reasons]).to include('repeated_suggestions')
    end

    it 'suggests escalation when user is frustrated' do
      # Set up sentiment history to trigger angry frustration level
      service.instance_variable_set(:@state, {
                                      sentiment_history: [
                                        { sentiment: :negative, timestamp: 1 },
                                        { sentiment: :negative, timestamp: 2 },
                                        { sentiment: :negative, timestamp: 3 }
                                      ]
                                    })

      expect(service.should_suggest_escalation?).to be true
      expect(service.state[:escalation_reasons]).to include('user_frustrated')
    end

    it 'does not suggest escalation when conditions are not met' do
      service.instance_variable_set(:@state, { turn_count: 3 })

      expect(service.should_suggest_escalation?).to be false
      expect(service.state[:escalation_suggested]).to be_falsey
    end

    it 'logs escalation suggestion' do
      service.instance_variable_set(:@state, { turn_count: 15 })

      service.should_suggest_escalation?

      expect(Captain::Logger).to have_received(:info).with(
        '[ConversationState] Escalation suggested',
        hash_including(
          conversation_id: conversation.id,
          turn_count: 15
        )
      )
    end
  end

  describe '#get_conversation_summary' do
    before do
      allow(Captain::Logger).to receive(:info)
      allow(Captain::Logger).to receive(:debug)

      service.instance_variable_set(:@state, {
                                      issue_summary: 'Connection problem',
                                      attempted_solutions: [{ solution: 'restart', result: 'suggested' }],
                                      turn_count: 5,
                                      sentiment_history: [{ sentiment: :neutral }]
                                    })
    end

    it 'returns comprehensive conversation summary' do
      summary = service.get_conversation_summary

      expect(summary[:issue]).to eq('Connection problem')
      expect(summary[:attempted_solutions]).to be_an(Array)
      expect(summary[:turn_count]).to eq(5)
      expect(summary[:sentiment_trend]).to be_present
      expect(summary[:should_escalate]).to be_in([true, false])
      expect(summary[:human_took_over]).to be_in([true, false])
    end

    it 'includes human intervention details when present' do
      service.instance_variable_set(:@state, {
                                      human_intervention: {
                                        happened: true,
                                        agent_id: agent.id,
                                        at_turn: 3
                                      }
                                    })

      summary = service.get_conversation_summary
      expect(summary[:human_took_over]).to be true
      expect(summary[:human_intervention][:agent_id]).to eq(agent.id)
    end
  end

  describe '#reset_state' do
    it 'clears all state' do
      allow(Captain::Logger).to receive(:info)
      service.instance_variable_set(:@state, { turn_count: 10, issue_summary: 'Test' })

      service.reset_state

      expect(service.state).to eq({})
    end

    it 'saves empty state to conversation' do
      allow(Captain::Logger).to receive(:info)
      service.instance_variable_set(:@state, { turn_count: 5 })

      service.reset_state
      conversation.reload

      expect(conversation.captain_state).to eq({})
    end

    it 'logs state reset' do
      allow(Captain::Logger).to receive(:info)

      service.reset_state

      expect(Captain::Logger).to have_received(:info).with(
        '[ConversationState] State reset',
        conversation_id: conversation.id
      )
    end
  end

  describe 'private methods' do
    describe '#calculate_sentiment_trend' do
      it 'returns :calm for empty sentiment history' do
        service.instance_variable_set(:@state, {})
        summary = service.get_conversation_summary

        expect(summary[:sentiment_trend]).to eq(:calm)
      end

      it 'returns :happy for mostly positive sentiments' do
        service.instance_variable_set(:@state, {
                                        sentiment_history: [
                                          { sentiment: :positive },
                                          { sentiment: :positive }
                                        ]
                                      })
        summary = service.get_conversation_summary

        expect(summary[:sentiment_trend]).to be_in([:happy, :calm])
      end

      it 'returns :frustrated for 2 negative sentiments' do
        service.instance_variable_set(:@state, {
                                        sentiment_history: [
                                          { sentiment: :negative },
                                          { sentiment: :negative }
                                        ]
                                      })
        summary = service.get_conversation_summary

        expect(summary[:sentiment_trend]).to eq(:frustrated)
      end

      it 'returns :angry for 3 negative sentiments' do
        service.instance_variable_set(:@state, {
                                        sentiment_history: [
                                          { sentiment: :negative },
                                          { sentiment: :negative },
                                          { sentiment: :negative }
                                        ]
                                      })
        summary = service.get_conversation_summary

        expect(summary[:sentiment_trend]).to eq(:angry)
      end
    end

    describe '#repeated_suggestions_count' do
      it 'counts repeated suggestions correctly' do
        allow(Captain::Logger).to receive(:info)
        allow(Captain::Logger).to receive(:debug)

        service.track_solution_attempt('reset', 1)
        service.track_solution_attempt('reset', 2)
        service.track_solution_attempt('update', 3)

        count = service.send(:repeated_suggestions_count)
        expect(count).to eq(1) # 3 total - 2 unique = 1 repeat
      end
    end
  end

  describe 'state persistence' do
    it 'survives conversation reload' do
      allow(Captain::Logger).to receive(:info)
      allow(Captain::Logger).to receive(:debug)

      service.track_solution_attempt('test_solution', message.id)
      service.increment_turn_count

      conversation.reload
      new_service = described_class.new(conversation)

      expect(new_service.state[:turn_count]).to eq(1)
      expect(new_service.state[:attempted_solutions].size).to eq(1)
    end

    it 'handles deep hash structures correctly' do
      allow(Captain::Logger).to receive(:info)

      service.track_human_takeover(agent.id, message.id)
      conversation.reload

      new_service = described_class.new(conversation)
      intervention = new_service.state[:human_intervention]

      expect(intervention).to be_a(Hash)
      expect(intervention[:happened]).to be true
    end
  end
end
