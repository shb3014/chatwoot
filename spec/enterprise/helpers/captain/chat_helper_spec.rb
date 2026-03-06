require 'rails_helper'

RSpec.describe Captain::ChatHelper do
  let(:dummy_class) do
    Class.new do
      include Captain::ChatHelper

      attr_reader :messages, :persisted_message

      def initialize(messages:, response_validator:)
        @messages = messages
        @response_validator = response_validator
        @tool_registry = nil
      end

      private

      def persist_message(message, _message_type = 'assistant')
        @persisted_message = message
      end
    end
  end

  describe '#handle_response' do
    let(:rejection_reason) { 'Model responded in ongoing conversation without searching documentation (likely hallucination)' }
    let(:rejected_validation) do
      {
        valid: false,
        should_reject: true,
        reason: rejection_reason
      }
    end

    let(:validator) do
      instance_double(
        Captain::ResponseValidatorService,
        validate_response: rejected_validation,
        tool_results: []
      )
    end

    it 'bypasses no-search rejection for copilot draft prompt and validates content field' do
      messages = [
        { role: 'system', content: 'system context' },
        { role: 'user', content: 'Based on the full conversation, draft a reply to the customer.' }
      ]
      service = dummy_class.new(messages: messages, response_validator: validator)

      response = {
        'choices' => [{
          'message' => {
            'content' => { content: 'Draft reply body' }.to_json
          }
        }]
      }

      expect(validator).to receive(:validate_response).with('Draft reply body').and_return(rejected_validation)
      expect(service).not_to receive(:attempt_validation_retry)

      result = service.send(:handle_response, response)

      expect(result['content']).to eq('Draft reply body')
      expect(service.persisted_message['content']).to eq('Draft reply body')
    end

    it 'still retries rejected no-search responses outside copilot draft flow' do
      messages = [
        { role: 'system', content: 'system context' },
        { role: 'user', content: 'How do I reset the planter?' }
      ]
      service = dummy_class.new(messages: messages, response_validator: validator)

      response = {
        'choices' => [{
          'message' => {
            'content' => { content: 'Please follow these steps.' }.to_json
          }
        }]
      }
      retry_result = { 'response' => 'fallback' }

      expect(validator).to receive(:validate_response).with('Please follow these steps.').and_return(rejected_validation)
      expect(service).to receive(:attempt_validation_retry).once.and_return(retry_result)

      result = service.send(:handle_response, response)
      expect(result).to eq(retry_result)
    end
  end
end
