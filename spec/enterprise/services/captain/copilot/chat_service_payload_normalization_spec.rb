require 'rails_helper'

RSpec.describe Captain::Copilot::ChatService do
  describe '#normalize_copilot_response_payload' do
    let(:service) { described_class.allocate }

    it 'maps response into content and drops unsupported keys' do
      payload = {
        'reasoning' => 'chain of thought',
        'response' => 'Please check the order status in Seller Central.',
        'reply_suggestion' => true,
        'customer_language' => 'en',
        'sources' => [{ 'title' => 'A', 'url' => 'https://example.com' }]
      }

      normalized = service.send(:normalize_copilot_response_payload, payload)

      expect(normalized).to eq(
        'content' => 'Please check the order status in Seller Central.',
        'reply_suggestion' => true,
        'customer_language' => 'en',
        'sources' => [{ 'title' => 'A', 'url' => 'https://example.com' }]
      )
    end

    it 'keeps content when already present' do
      payload = {
        'content' => 'Direct content from model.',
        'response' => 'should not overwrite',
        'translation' => '模型直接内容。'
      }

      normalized = service.send(:normalize_copilot_response_payload, payload)

      expect(normalized).to eq(
        'content' => 'Direct content from model.',
        'translation' => '模型直接内容。'
      )
    end
  end

  describe '#persist_assistant_message_fallback' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
    let(:service) { described_class.allocate }

    before do
      service.instance_variable_set(:@copilot_thread, copilot_thread)
    end

    it 'persists a fallback assistant message when buffered message is missing' do
      response = { 'content' => 'Fallback content', 'reply_suggestion' => true }

      expect do
        service.send(:persist_assistant_message_fallback, response)
      end.to change(CopilotMessage, :count).by(1)

      message = CopilotMessage.last
      expect(message.message_type).to eq('assistant')
      expect(message.message['content']).to eq('Fallback content')
    end
  end

  describe '#broadcast_streaming_reset' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
    let(:service) { described_class.allocate }

    before do
      service.instance_variable_set(:@user, user)
      service.instance_variable_set(:@copilot_thread, copilot_thread)
      service.instance_variable_set(:@account, account)
    end

    it 'broadcasts an empty terminal streaming payload' do
      expect(ActionCable.server).to receive(:broadcast).with(
        user.pubsub_token,
        hash_including(
          event: 'copilot.message.streaming',
          data: hash_including(
            account_id: account.id,
            copilot_thread_id: copilot_thread.id,
            content: '',
            thinking: '',
            translation: ''
          )
        )
      )

      service.send(:broadcast_streaming_reset)
    end
  end

  describe '#broadcast_persisted_assistant_message' do
    let(:account) { create(:account) }
    let(:user) { create(:user, account: account) }
    let(:assistant) { create(:captain_assistant, account: account) }
    let(:copilot_thread) { create(:captain_copilot_thread, account: account, user: user, assistant: assistant) }
    let(:record) { create(:captain_copilot_message, copilot_thread: copilot_thread, account: account, message_type: 'assistant') }
    let(:service) { described_class.allocate }

    before do
      service.instance_variable_set(:@user, user)
      service.instance_variable_set(:@account, account)
    end

    it 'broadcasts copilot.message.created payload directly' do
      expect(ActionCable.server).to receive(:broadcast).with(
        user.pubsub_token,
        hash_including(
          event: 'copilot.message.created',
          data: hash_including(
            id: record.id,
            account_id: account.id
          )
        )
      )

      service.send(:broadcast_persisted_assistant_message, record)
    end
  end
end
