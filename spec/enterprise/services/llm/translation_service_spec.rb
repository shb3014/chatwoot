require 'rails_helper'

RSpec.describe Llm::TranslationService do
  let(:client) { instance_double(OpenAI::Client) }
  let(:service) { described_class.new }

  before do
    create(:installation_config, name: 'CAPTAIN_OPEN_AI_API_KEY', value: 'test-key')
    allow(OpenAI::Client).to receive(:new).and_return(client)
  end

  describe '#stream_translate_batch' do
    let(:messages) do
      [
        { id: 101, content: 'Hello' },
        { id: 102, content: 'Goodbye' }
      ]
    end

    it 'passes stream callback inside parameters for ruby-openai compatibility' do
      yielded = []

      expect(client).to receive(:chat) do |parameters:|
        stream_proc = parameters[:stream]
        expect(stream_proc).to be_a(Proc)

        stream_proc.call({ 'choices' => [{ 'delta' => { 'content' => '<<<MSG:101>>>你' } }] })
        stream_proc.call({ 'choices' => [{ 'delta' => { 'content' => '好<<<MSG:102>>>再' } }] })
        stream_proc.call({ 'choices' => [{ 'delta' => { 'content' => '见' } }] })
      end

      service.stream_translate_batch(messages, target_language: 'zh_CN') do |message_id, translation|
        yielded << [message_id, translation]
      end

      expect(yielded).to eq([[101, '你好'], [102, '再见']])
    end
  end
end
