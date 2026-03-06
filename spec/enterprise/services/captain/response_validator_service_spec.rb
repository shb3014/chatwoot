require 'rails_helper'

RSpec.describe Captain::ResponseValidatorService do
  describe '#validate_response' do
    it 'accepts responses backed by non-documentation tool results' do
      service = described_class.new(strictness: described_class::STRICT)
      service.capture_tool_result('get_conversation', 'Order 114-9894509-5445833 was refunded.')

      result = service.validate_response('A refund was initiated for your order.')

      expect(result[:valid]).to be true
      expect(result[:should_reject]).to be false
      expect(result[:reason]).to eq('Response based on non-documentation tool results')
    end

    it 'rejects informative responses when documentation search returns no results' do
      service = described_class.new(strictness: described_class::MODERATE)
      service.capture_tool_result('search_documentation', 'No documentation found for this query')

      result = service.validate_response('Your product includes a 2-year warranty period.')

      expect(result[:valid]).to be false
      expect(result[:should_reject]).to be true
      expect(result[:reason]).to eq('Response provides information when documentation search returned no results')
    end
  end
end
