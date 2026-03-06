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
end
