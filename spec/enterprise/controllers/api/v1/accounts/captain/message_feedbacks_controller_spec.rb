require 'rails_helper'

RSpec.describe 'Api::V1::Accounts::Captain::MessageFeedbacks', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:inbox) { create(:inbox, account: account) }
  let(:conversation) { create(:conversation, inbox: inbox, account: account) }
  let(:message) { create(:message, conversation: conversation, account: account, sender_type: 'AgentBot') }

  def json_response
    JSON.parse(response.body, symbolize_names: true)
  end

  before do
    # Create an inbox member so agents can access the conversation
    create(:inbox_member, inbox: inbox, user: agent)
    allow(Captain::Logger).to receive(:info)
    allow(Captain::Logger).to receive(:error)
  end

  describe 'POST /api/v1/accounts/{account.id}/captain/message_feedbacks' do
    let(:valid_params) do
      {
        message_id: message.id,
        rating: 1,
        feedback_type: 'helpful',
        notes: 'Great response!'
      }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: valid_params,
             as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'creates a new feedback' do
        expect do
          post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
               params: valid_params,
               headers: agent.create_new_auth_token,
               as: :json
        end.to change(CaptainMessageFeedback, :count).by(1)

        expect(response).to have_http_status(:created)
        expect(json_response[:feedback]).to be_present
        expect(json_response[:feedback][:rating]).to eq(1)
        expect(json_response[:feedback][:feedback_type]).to eq('helpful')
      end

      it 'accepts feedback without notes' do
        params = { message_id: message.id, rating: -1, feedback_type: 'unhelpful' }

        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: params,
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
        expect(json_response[:feedback][:notes]).to be_nil
      end

      it 'accepts all valid feedback types' do
        %w[helpful unhelpful incorrect incomplete too_technical too_vague].each do |feedback_type|
          msg = create(:message, conversation: conversation, account: account, sender_type: 'AgentBot')
          params = { message_id: msg.id, rating: 1, feedback_type: feedback_type }

          post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
               params: params,
               headers: agent.create_new_auth_token,
               as: :json

          expect(response).to have_http_status(:created)
          expect(json_response[:feedback][:feedback_type]).to eq(feedback_type)
        end
      end

      it 'updates existing feedback instead of creating duplicate' do
        # Create initial feedback
        create(:captain_message_feedback,
               message: message,
               rated_by: agent,
               rating: 1,
               feedback_type: 'helpful')

        # Try to create another feedback for same message/agent
        expect do
          post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
               params: { message_id: message.id, rating: -1, feedback_type: 'unhelpful' },
               headers: agent.create_new_auth_token,
               as: :json
        end.not_to change(CaptainMessageFeedback, :count)

        expect(response).to have_http_status(:created)

        # Verify feedback was updated
        feedback = CaptainMessageFeedback.find_by(message: message, rated_by: agent)
        expect(feedback.rating).to eq(-1)
        expect(feedback.feedback_type).to eq('unhelpful')
      end

      it 'returns error for invalid rating' do
        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: { message_id: message.id, rating: 999 },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:errors]).to be_present
      end

      it 'returns error for invalid feedback_type' do
        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: { message_id: message.id, rating: 1, feedback_type: 'invalid_type' },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:errors]).to be_present
      end

      it 'returns error when message not found' do
        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: { message_id: 99_999, rating: 1 },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns error when agent does not have access to conversation' do
        other_inbox = create(:inbox, account: account)
        other_conversation = create(:conversation, inbox: other_inbox, account: account)
        other_message = create(:message, conversation: other_conversation, account: account)

        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: { message_id: other_message.id, rating: 1 },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when it is an admin' do
      it 'creates feedback successfully' do
        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: valid_params,
             headers: admin.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:created)
      end
    end
  end

  describe 'PUT /api/v1/accounts/{account.id}/captain/message_feedbacks/{message_id}' do
    let!(:feedback) do
      create(:captain_message_feedback,
             message: message,
             rated_by: agent,
             rating: 1,
             feedback_type: 'helpful')
    end

    let(:update_params) do
      {
        rating: -1,
        feedback_type: 'incorrect',
        notes: 'Actually incorrect',
        issue_resolved: true,
        resolution_method: 'escalated'
      }
    end

    context 'when it is an unauthenticated user' do
      it 'returns unauthorized' do
        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
            params: update_params,
            as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when it is an authenticated agent' do
      it 'updates the feedback' do
        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
            params: update_params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        feedback.reload
        expect(feedback.rating).to eq(-1)
        expect(feedback.feedback_type).to eq('incorrect')
        expect(feedback.notes).to eq('Actually incorrect')
        expect(feedback.issue_resolved).to be true
        expect(feedback.resolution_method).to eq('escalated')
      end

      it 'updates resolution status only' do
        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
            params: { issue_resolved: true, resolution_method: 'captain_solution' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)

        feedback.reload
        expect(feedback.issue_resolved).to be true
        expect(feedback.resolution_method).to eq('captain_solution')
        # Original values should remain
        expect(feedback.rating).to eq(1)
        expect(feedback.feedback_type).to eq('helpful')
      end

      it 'accepts all valid resolution methods' do
        %w[captain_solution agent_different_solution escalated].each do |method|
          put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
              params: { resolution_method: method },
              headers: agent.create_new_auth_token,
              as: :json

          expect(response).to have_http_status(:success)
          feedback.reload
          expect(feedback.resolution_method).to eq(method)
        end
      end

      it 'returns error for invalid resolution_method' do
        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
            params: { resolution_method: 'invalid_method' },
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(json_response[:errors]).to be_present
      end

      it 'returns error when feedback not found' do
        other_message = create(:message, conversation: conversation, account: account)

        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{other_message.id}",
            params: update_params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns error when trying to update another agent\'s feedback' do
        other_agent = create(:user, account: account, role: :agent)
        create(:inbox_member, inbox: inbox, user: other_agent)

        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
            params: update_params,
            headers: other_agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
      end

      it 'returns error when message not found' do
        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/99999",
            params: update_params,
            headers: agent.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:not_found)
      end
    end

    context 'when it is an admin' do
      let!(:admin_feedback) do
        create(:captain_message_feedback,
               message: message,
               rated_by: admin,
               rating: 0)
      end

      it 'updates admin\'s own feedback' do
        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
            params: { rating: 1 },
            headers: admin.create_new_auth_token,
            as: :json

        expect(response).to have_http_status(:success)
      end

      it 'cannot update another user\'s feedback' do
        put "/api/v1/accounts/#{account.id}/captain/message_feedbacks/#{message.id}",
            params: { rating: 1 },
            headers: admin.create_new_auth_token,
            as: :json

        # Should update admin's own feedback, not agent's
        admin_feedback.reload
        expect(admin_feedback.rating).to eq(1)

        feedback.reload
        expect(feedback.rating).to eq(1) # Agent's feedback unchanged
      end
    end
  end

  describe 'authorization' do
    context 'when agent has no access to inbox' do
      let(:other_inbox) { create(:inbox, account: account) }
      let(:other_conversation) { create(:conversation, inbox: other_inbox, account: account) }
      let(:other_message) { create(:message, conversation: other_conversation, account: account) }

      it 'returns not found for create' do
        post "/api/v1/accounts/#{account.id}/captain/message_feedbacks",
             params: { message_id: other_message.id, rating: 1 },
             headers: agent.create_new_auth_token,
             as: :json

        expect(response).to have_http_status(:not_found)
      end
    end
  end
end
