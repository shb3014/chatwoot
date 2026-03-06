require 'rails_helper'

RSpec.describe Captain::Llm::ConversationSummarizationService do
  let(:client) { instance_double(OpenAI::Client) }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(Captain::Llm::SystemPromptsService).to receive(:conversation_summarization).and_return('system prompt')
  end

  describe '#generate' do
    let(:openai_response) do
      {
        'choices' => [
          {
            'message' => {
              'content' => {
                summary: 'Customer sent an empty email asking for invoice help',
                labels: []
              }.to_json
            }
          }
        ]
      }
    end

    context 'when email body is empty but sender metadata exists' do
      let(:account) { create(:account) }
      let(:inbox) { create(:inbox, :with_email, account: account) }
      let(:contact) { create(:contact, account: account, email: 'sender@example.com') }
      let(:conversation) do
        create(
          :conversation,
          account: account,
          inbox: inbox,
          contact: contact,
          additional_attributes: { 'mail_subject' => 'Need help with invoice' }
        )
      end

      it 'includes sender context and still generates summary' do
        expect(client).to receive(:chat).with(
          parameters: hash_including(
            messages: array_including(
              hash_including(
                role: 'user',
                content: a_string_including(
                  'Customer Email: sender@example.com',
                  'Mail Subject: Need help with invoice',
                  '(No non-empty message body)'
                )
              )
            )
          )
        ).and_return(openai_response)

        result = described_class.new(conversation).generate

        expect(result).to include(
          'summary' => 'Customer sent an empty email asking for invoice help',
          'labels' => []
        )
        expect(conversation.reload.captain_summary['content']).to eq('Customer sent an empty email asking for invoice help')
      end
    end

    context 'when there is no message body and no email metadata' do
      let(:account) { create(:account) }
      let(:inbox) { create(:inbox, :with_email, account: account) }
      let(:contact) { create(:contact, account: account, email: nil) }
      let(:conversation) do
        create(
          :conversation,
          account: account,
          inbox: inbox,
          contact: contact,
          additional_attributes: {}
        )
      end

      it 'skips summarization' do
        expect(client).not_to receive(:chat)

        expect(described_class.new(conversation).generate).to be_nil
      end
    end
  end
end
