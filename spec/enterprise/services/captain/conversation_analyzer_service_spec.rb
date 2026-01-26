require 'rails_helper'

RSpec.describe Captain::ConversationAnalyzerService do
  let(:account) { create(:account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:contact) { create(:contact, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account, contact: contact) }
  let(:service) { described_class.new(conversation) }

  describe '#analyze' do
    context 'with basic conversation' do
      let!(:customer_message) { create(:message, :incoming, conversation: conversation, content: 'I need help') }
      let!(:captain_message) { create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'How can I help?') }

      it 'returns comprehensive analysis hash' do
        result = service.analyze

        expect(result).to include(
          :conversation_id,
          :total_turns,
          :captain_turns,
          :agent_turns,
          :customer_turns,
          :resolution,
          :captain_helped,
          :human_intervention,
          :issue_category,
          :solution_type,
          :duration_minutes
        )
      end

      it 'counts turns correctly' do
        result = service.analyze

        expect(result[:total_turns]).to eq(2)
        expect(result[:captain_turns]).to eq(1)
        expect(result[:customer_turns]).to eq(1)
        expect(result[:agent_turns]).to eq(0)
      end

      it 'includes conversation ID' do
        result = service.analyze
        expect(result[:conversation_id]).to eq(conversation.id)
      end
    end

    context 'resolution detection' do
      it 'detects explicitly resolved conversations' do
        conversation.update(status: 'resolved')
        create(:message, :incoming, conversation: conversation)

        result = service.analyze
        expect(result[:resolution][:status]).to eq(:resolved)
        expect(result[:resolution][:confidence]).to eq(:high)
      end

      it 'detects likely resolved from positive sentiment' do
        create(:message, :incoming, conversation: conversation, content: 'Thanks so much! It worked perfectly!')

        result = service.analyze
        expect(result[:resolution][:status]).to eq(:likely_resolved)
        expect(result[:resolution][:confidence]).to eq(:medium)
      end

      it 'detects unresolved with follow-up conversation' do
        create(:message, :incoming, conversation: conversation, content: 'Still having problems')
        create(:conversation, account: account, contact: contact, created_at: conversation.created_at + 2.hours)

        result = service.analyze
        expect(result[:resolution][:status]).to eq(:unresolved)
        expect(result[:resolution][:follow_up]).to be true
      end

      it 'detects abandoned conversations' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', created_at: 25.hours.ago)

        result = service.analyze
        expect(result[:resolution][:status]).to eq(:abandoned)
      end

      it 'returns unknown for unclear cases' do
        create(:message, :incoming, conversation: conversation, content: 'Hello')
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'Hi', created_at: 1.hour.ago)

        result = service.analyze
        expect(result[:resolution][:status]).to eq(:unknown)
      end
    end

    context 'captain effectiveness estimation' do
      it 'detects not_used when agent responds immediately' do
        create(:message, :incoming, conversation: conversation, content: 'Help needed')
        agent = create(:user, account: account)
        create(:message, conversation: conversation, sender_id: agent.id, sender_type: 'User')

        result = service.analyze
        expect(result[:captain_helped][:helped]).to eq(:not_used)
        expect(result[:captain_helped][:turns_before_agent]).to eq(0)
      end

      it 'detects not_effective when captain has many turns before agent' do
        create(:message, :incoming, conversation: conversation)
        5.times { create(:message, conversation: conversation, sender_type: 'AgentBot') }
        agent = create(:user, account: account)
        create(:message, conversation: conversation, sender_id: agent.id, sender_type: 'User')

        result = service.analyze
        expect(result[:captain_helped][:helped]).to eq(:not_effective)
        expect(result[:captain_helped][:turns_before_agent]).to eq(5)
      end

      it 'detects partial help when captain responds a few times before agent' do
        create(:message, :incoming, conversation: conversation)
        2.times { create(:message, conversation: conversation, sender_type: 'AgentBot') }
        agent = create(:user, account: account)
        create(:message, conversation: conversation, sender_id: agent.id, sender_type: 'User')

        result = service.analyze
        expect(result[:captain_helped][:helped]).to eq(:partial)
        expect(result[:captain_helped][:turns_before_agent]).to eq(2)
      end

      it 'detects fully_resolved when no agent intervention and resolved' do
        conversation.update(status: 'resolved')
        create(:message, :incoming, conversation: conversation)
        create(:message, conversation: conversation, sender_type: 'AgentBot')

        result = service.analyze
        expect(result[:captain_helped][:helped]).to eq(:fully_resolved)
      end

      it 'returns unknown when captain used but unclear outcome' do
        create(:message, :incoming, conversation: conversation)
        create(:message, conversation: conversation, sender_type: 'AgentBot')

        result = service.analyze
        expect(result[:captain_helped][:helped]).to eq(:unknown)
      end
    end

    context 'human intervention detection' do
      it 'detects when human agent intervenes' do
        create(:message, :incoming, conversation: conversation, created_at: 1.hour.ago)
        create(:message, conversation: conversation, sender_type: 'AgentBot', created_at: 55.minutes.ago)
        agent = create(:user, account: account)
        create(:message, conversation: conversation, sender_id: agent.id, sender_type: 'User', created_at: 50.minutes.ago)

        result = service.analyze
        intervention = result[:human_intervention]

        expect(intervention[:happened]).to be true
        expect(intervention[:agent_id]).to eq(agent.id)
        expect(intervention[:captain_turns_before]).to eq(1)
      end

      it 'returns nil when no human intervention' do
        create(:message, :incoming, conversation: conversation)
        create(:message, conversation: conversation, sender_type: 'AgentBot')

        result = service.analyze
        expect(result[:human_intervention]).to be_nil
      end
    end

    context 'issue category detection' do
      it 'detects authentication issues' do
        create(:message, :incoming, conversation: conversation, content: 'I forgot my password')
        result = service.analyze
        expect(result[:issue_category]).to eq(:authentication)
      end

      it 'detects connectivity issues' do
        create(:message, :incoming, conversation: conversation, content: 'WiFi not connecting')
        result = service.analyze
        expect(result[:issue_category]).to eq(:connectivity)
      end

      it 'detects battery issues' do
        create(:message, :incoming, conversation: conversation, content: 'Battery draining quickly')
        result = service.analyze
        expect(result[:issue_category]).to eq(:battery)
      end

      it 'detects order status queries' do
        create(:message, :incoming, conversation: conversation, content: 'Track my order')
        result = service.analyze
        expect(result[:issue_category]).to eq(:order_status)
      end

      it 'detects order issues' do
        create(:message, :incoming, conversation: conversation, content: 'Need a refund')
        result = service.analyze
        expect(result[:issue_category]).to eq(:order_issue)
      end

      it 'detects setup issues' do
        create(:message, :incoming, conversation: conversation, content: 'How to install the app?')
        result = service.analyze
        expect(result[:issue_category]).to eq(:setup)
      end

      it 'detects technical issues' do
        create(:message, :incoming, conversation: conversation, content: 'Getting an error message')
        result = service.analyze
        expect(result[:issue_category]).to eq(:technical_issue)
      end

      it 'detects how-to questions' do
        create(:message, :incoming, conversation: conversation, content: 'How do I change my settings?')
        result = service.analyze
        expect(result[:issue_category]).to eq(:how_to)
      end

      it 'detects Chinese authentication keywords' do
        create(:message, :incoming, conversation: conversation, content: '我忘记了密码')
        result = service.analyze
        expect(result[:issue_category]).to eq(:authentication)
      end

      it 'returns other for unrecognized issues' do
        create(:message, :incoming, conversation: conversation, content: 'Random question')
        result = service.analyze
        expect(result[:issue_category]).to eq(:other)
      end
    end

    context 'solution type detection' do
      it 'detects reset solutions' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'Try resetting your device')
        result = service.analyze
        expect(result[:solution_type]).to eq(:reset_solution)
      end

      it 'detects update solutions' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'Please update to the latest version')
        result = service.analyze
        expect(result[:solution_type]).to eq(:update_solution)
      end

      it 'detects diagnostic solutions' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'Can you check your network settings?')
        result = service.analyze
        expect(result[:solution_type]).to eq(:diagnostic_solution)
      end

      it 'detects configuration solutions' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'Go to settings and change the configuration')
        result = service.analyze
        expect(result[:solution_type]).to eq(:configuration_solution)
      end

      it 'detects documentation provided' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'Here is the documentation')
        result = service.analyze
        expect(result[:solution_type]).to eq(:documentation_provided)
      end

      it 'returns informational for general responses' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: 'Let me help you')
        result = service.analyze
        expect(result[:solution_type]).to eq(:informational)
      end

      it 'detects Chinese reset keywords' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', content: '请重启设备')
        result = service.analyze
        expect(result[:solution_type]).to eq(:reset_solution)
      end

      it 'returns no_captain_response when no captain messages' do
        create(:message, :incoming, conversation: conversation, content: 'Help')
        result = service.analyze
        expect(result[:solution_type]).to eq(:no_captain_response)
      end
    end

    context 'duration calculation' do
      it 'calculates duration in minutes' do
        create(:message, conversation: conversation, created_at: 10.minutes.ago)
        create(:message, conversation: conversation, created_at: 5.minutes.ago)

        result = service.analyze
        expect(result[:duration_minutes]).to be_within(0.5).of(5.0)
      end

      it 'returns nil for empty conversations' do
        conversation_empty = create(:conversation, inbox: inbox, account: account)
        service = described_class.new(conversation_empty)

        result = service.analyze
        expect(result[:duration_minutes]).to be_nil
      end

      it 'handles single message conversations' do
        create(:message, conversation: conversation)

        result = service.analyze
        expect(result[:duration_minutes]).to eq(0.0)
      end
    end

    context 'captain state detection' do
      it 'detects presence of captain state' do
        conversation.update_column(:captain_state, { turn_count: 5 })
        create(:message, conversation: conversation)

        result = service.analyze
        expect(result[:has_captain_state]).to be true
      end

      it 'detects absence of captain state' do
        create(:message, conversation: conversation)

        result = service.analyze
        expect(result[:has_captain_state]).to be false
      end
    end
  end

  describe 'helper methods' do
    describe '#positive_sentiment_in_messages?' do
      it 'detects positive sentiment with English keywords' do
        messages = [
          create(:message, :incoming, conversation: conversation, content: 'Thanks! It worked great!')
        ]

        expect(service.send(:positive_sentiment_in_messages?, messages)).to be true
      end

      it 'detects positive sentiment with Chinese keywords' do
        messages = [
          create(:message, :incoming, conversation: conversation, content: '谢谢！解决了')
        ]

        expect(service.send(:positive_sentiment_in_messages?, messages)).to be true
      end

      it 'returns false for negative messages' do
        messages = [
          create(:message, :incoming, conversation: conversation, content: 'This is terrible')
        ]

        expect(service.send(:positive_sentiment_in_messages?, messages)).to be false
      end

      it 'returns false for empty array' do
        expect(service.send(:positive_sentiment_in_messages?, [])).to be false
      end
    end

    describe '#conversation_abandoned?' do
      it 'detects abandoned conversations' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', created_at: 25.hours.ago)

        expect(service.send(:conversation_abandoned?)).to be true
      end

      it 'does not flag recent conversations' do
        create(:message, conversation: conversation, sender_type: 'AgentBot', created_at: 1.hour.ago)

        expect(service.send(:conversation_abandoned?)).to be false
      end

      it 'does not flag if last message from customer' do
        create(:message, :incoming, conversation: conversation, created_at: 25.hours.ago)

        expect(service.send(:conversation_abandoned?)).to be false
      end
    end
  end
end
