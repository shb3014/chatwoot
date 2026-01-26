require 'rails_helper'

RSpec.describe Captain::MessageFeedbackService do
  let(:account) { create(:account) }
  let(:agent) { create(:user, account: account) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account) }
  let(:service) { described_class.new(message, agent) }

  before do
    allow(Captain::Logger).to receive(:info)
    allow(Captain::Logger).to receive(:error)
    allow(Captain::Logger).to receive(:warn)
  end

  describe '#initialize' do
    it 'sets message, agent, and conversation' do
      expect(service.instance_variable_get(:@message)).to eq(message)
      expect(service.instance_variable_get(:@agent)).to eq(agent)
      expect(service.instance_variable_get(:@conversation)).to eq(conversation)
    end
  end

  describe '#record_feedback' do
    context 'with valid parameters' do
      it 'creates a new feedback record' do
        expect do
          service.record_feedback(rating: 1, feedback_type: 'helpful', notes: 'Great answer!')
        end.to change(CaptainMessageFeedback, :count).by(1)
      end

      it 'returns success with feedback object' do
        result = service.record_feedback(rating: 1, feedback_type: 'helpful')

        expect(result[:success]).to be true
        expect(result[:feedback]).to be_a(CaptainMessageFeedback)
        expect(result[:feedback].rating).to eq(1)
        expect(result[:feedback].feedback_type).to eq('helpful')
      end

      it 'associates feedback with message, conversation, and agent' do
        result = service.record_feedback(rating: -1, feedback_type: 'incorrect')
        feedback = result[:feedback]

        expect(feedback.message_id).to eq(message.id)
        expect(feedback.conversation_id).to eq(conversation.id)
        expect(feedback.rated_by_id).to eq(agent.id)
      end

      it 'updates conversation state with feedback' do
        state_service = instance_double(Captain::ConversationStateService)
        allow(Captain::ConversationStateService).to receive(:new).with(conversation).and_return(state_service)
        allow(state_service).to receive(:update_solution_feedback)

        service.record_feedback(rating: 1, feedback_type: 'helpful')

        expect(state_service).to have_received(:update_solution_feedback).with(message.id, 'helpful')
      end

      it 'logs successful feedback recording' do
        service.record_feedback(rating: 1, feedback_type: 'helpful')

        expect(Captain::Logger).to have_received(:info).with(
          '[MessageFeedback] Feedback recorded',
          hash_including(
            message_id: message.id,
            conversation_id: conversation.id,
            agent_id: agent.id,
            rating: 1,
            feedback_type: 'helpful'
          )
        )
      end

      it 'accepts optional notes parameter' do
        result = service.record_feedback(
          rating: 1,
          feedback_type: 'helpful',
          notes: 'Very detailed and accurate'
        )

        expect(result[:feedback].notes).to eq('Very detailed and accurate')
      end

      it 'uses default feedback label based on rating when feedback_type is nil' do
        state_service = instance_double(Captain::ConversationStateService)
        allow(Captain::ConversationStateService).to receive(:new).and_return(state_service)
        allow(state_service).to receive(:update_solution_feedback)

        service.record_feedback(rating: 1)
        expect(state_service).to have_received(:update_solution_feedback).with(message.id, 'helpful')

        service2 = described_class.new(create(:message, conversation: conversation), agent)
        service2.record_feedback(rating: -1)
        expect(state_service).to have_received(:update_solution_feedback).with(anything, 'unhelpful')
      end
    end

    context 'updating existing feedback' do
      let!(:existing_feedback) do
        create(:captain_message_feedback,
               message: message,
               rated_by: agent,
               rating: 1,
               feedback_type: 'helpful')
      end

      it 'updates existing feedback instead of creating new one' do
        expect do
          service.record_feedback(rating: -1, feedback_type: 'unhelpful')
        end.not_to change(CaptainMessageFeedback, :count)
      end

      it 'updates feedback attributes' do
        service.record_feedback(rating: -1, feedback_type: 'incorrect', notes: 'Wrong information')
        existing_feedback.reload

        expect(existing_feedback.rating).to eq(-1)
        expect(existing_feedback.feedback_type).to eq('incorrect')
        expect(existing_feedback.notes).to eq('Wrong information')
      end
    end

    context 'with invalid parameters' do
      it 'returns failure when rating is invalid' do
        result = service.record_feedback(rating: 5)

        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end

      it 'logs error when saving fails' do
        service.record_feedback(rating: 999) # Invalid rating

        expect(Captain::Logger).to have_received(:error).with(
          '[MessageFeedback] Failed to save feedback',
          hash_including(message_id: message.id)
        )
      end

      it 'returns validation errors' do
        result = service.record_feedback(rating: 999)

        expect(result[:success]).to be false
        expect(result[:errors]).to be_an(Array)
      end
    end
  end

  describe '#record_resolution' do
    context 'when feedback exists' do
      let!(:feedback) do
        create(:captain_message_feedback,
               message: message,
               rated_by: agent,
               rating: 1)
      end

      it 'updates resolution status' do
        result = service.record_resolution(
          resolved: true,
          resolution_method: 'captain_solution'
        )

        expect(result[:success]).to be true
        feedback.reload
        expect(feedback.issue_resolved).to be true
        expect(feedback.resolution_method).to eq('captain_solution')
      end

      it 'logs resolution recording' do
        service.record_resolution(resolved: true, resolution_method: 'escalated')

        expect(Captain::Logger).to have_received(:info).with(
          '[MessageFeedback] Resolution recorded',
          hash_including(
            message_id: message.id,
            conversation_id: conversation.id,
            resolved: true,
            method: 'escalated'
          )
        )
      end

      it 'accepts various resolution methods' do
        %w[captain_solution agent_different_solution escalated].each do |method|
          result = service.record_resolution(resolved: true, resolution_method: method)
          expect(result[:success]).to be true

          feedback.reload
          expect(feedback.resolution_method).to eq(method)
        end
      end

      it 'handles unresolved cases' do
        result = service.record_resolution(resolved: false, resolution_method: 'escalated')

        expect(result[:success]).to be true
        feedback.reload
        expect(feedback.issue_resolved).to be false
      end
    end

    context 'when feedback does not exist' do
      it 'returns failure' do
        result = service.record_resolution(
          resolved: true,
          resolution_method: 'captain_solution'
        )

        expect(result[:success]).to be false
        expect(result[:error]).to eq('Feedback not found')
      end

      it 'logs warning when feedback not found' do
        service.record_resolution(resolved: true, resolution_method: 'escalated')

        expect(Captain::Logger).to have_received(:warn).with(
          '[MessageFeedback] No feedback found to update resolution',
          hash_including(
            message_id: message.id,
            agent_id: agent.id
          )
        )
      end
    end

    context 'with invalid resolution data' do
      let!(:feedback) do
        create(:captain_message_feedback,
               message: message,
               rated_by: agent)
      end

      it 'returns failure with errors' do
        result = service.record_resolution(
          resolved: true,
          resolution_method: 'invalid_method'
        )

        expect(result[:success]).to be false
        expect(result[:errors]).to be_present
      end
    end
  end

  describe '#get_feedback' do
    context 'when feedback exists' do
      let!(:feedback) do
        create(:captain_message_feedback,
               message: message,
               rated_by: agent,
               rating: 1,
               feedback_type: 'helpful')
      end

      it 'returns the feedback record' do
        result = service.get_feedback

        expect(result).to eq(feedback)
        expect(result.rating).to eq(1)
        expect(result.feedback_type).to eq('helpful')
      end
    end

    context 'when feedback does not exist' do
      it 'returns nil' do
        result = service.get_feedback
        expect(result).to be_nil
      end
    end

    context 'with multiple agents' do
      let(:another_agent) { create(:user, account: account) }
      let!(:feedback1) { create(:captain_message_feedback, message: message, rated_by: agent) }
      let!(:feedback2) { create(:captain_message_feedback, message: message, rated_by: another_agent) }

      it 'returns only the specified agent\'s feedback' do
        result = service.get_feedback
        expect(result).to eq(feedback1)
        expect(result).not_to eq(feedback2)
      end
    end
  end

  describe 'integration with ConversationStateService' do
    it 'updates conversation state with helpful feedback' do
      state_service = Captain::ConversationStateService.new(conversation)
      allow(Captain::ConversationStateService).to receive(:new).with(conversation).and_return(state_service)

      # Track a solution first
      state_service.track_solution_attempt('reset_password', message.id)

      # Record feedback
      service.record_feedback(rating: 1, feedback_type: 'helpful')

      # Verify state was updated
      solution = state_service.state[:attempted_solutions].find { |s| s[:message_id] == message.id }
      expect(solution[:agent_feedback]).to eq('helpful')
    end

    it 'updates conversation state with negative feedback types' do
      state_service = Captain::ConversationStateService.new(conversation)
      allow(Captain::ConversationStateService).to receive(:new).with(conversation).and_return(state_service)

      state_service.track_solution_attempt('update_app', message.id)
      service.record_feedback(rating: -1, feedback_type: 'incorrect')

      solution = state_service.state[:attempted_solutions].find { |s| s[:message_id] == message.id }
      expect(solution[:agent_feedback]).to eq('incorrect')
    end
  end

  describe 'edge cases' do
    it 'handles nil feedback_type gracefully' do
      result = service.record_feedback(rating: 0)

      expect(result[:success]).to be true
      expect(result[:feedback].feedback_type).to be_nil
    end

    it 'handles empty notes' do
      result = service.record_feedback(rating: 1, feedback_type: 'helpful', notes: '')

      expect(result[:success]).to be true
      expect(result[:feedback].notes).to eq('')
    end

    it 'handles concurrent feedback updates' do
      # Simulate race condition - both requests try to create feedback
      service.record_feedback(rating: 1)
      feedback2 = service.record_feedback(rating: -1)

      # Should update the same record, not create duplicates
      expect(CaptainMessageFeedback.where(message: message, rated_by: agent).count).to eq(1)

      # Last update should win
      expect(feedback2[:feedback].rating).to eq(-1)
    end
  end
end
