require 'net/http'
require 'json'

namespace :captain do
  desc 'Call Captain playground API via HTTP'
  task :playground_api, [:account_id, :assistant_id, :message, :token] => :environment do |_, args|
    account_id = args[:account_id] || ENV['CAPTAIN_ACCOUNT_ID']
    assistant_id = args[:assistant_id] || ENV['CAPTAIN_ASSISTANT_ID']
    message = args[:message] || ENV['CAPTAIN_MESSAGE'] || 'battery life'
    token = args[:token] || ENV['CAPTAIN_API_TOKEN'] || AccessToken.first&.token
    base_url = ENV['CAPTAIN_API_BASE'].presence || 'http://localhost:3000'

    if assistant_id.present? && account_id.blank?
      assistant = Captain::Assistant.find_by(id: assistant_id)
      account_id = assistant&.account_id
    end

    unless account_id && assistant_id && message && token
      puts 'Usage: rake captain:playground_api[account_id,assistant_id,message,token]'
      puts 'Or set env vars: CAPTAIN_ACCOUNT_ID, CAPTAIN_ASSISTANT_ID, CAPTAIN_MESSAGE, CAPTAIN_API_TOKEN'
      puts 'Defaults: message="battery life", token=AccessToken.first, base_url=http://localhost:3000'
      puts 'Optional: CAPTAIN_API_BASE (default http://localhost:3000)'
      exit 1
    end

    uri = URI.parse("#{base_url}/api/v1/accounts/#{account_id}/captain/assistants/#{assistant_id}/playground")
    payload = {
      message_content: message,
      assistant: {
        message_history: []
      }
    }

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = uri.scheme == 'https'

    request = Net::HTTP::Post.new(uri.request_uri)
    request['Content-Type'] = 'application/json'
    request['api_access_token'] = token
    request.body = payload.to_json

    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = http.request(request)
    elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round

    puts "Status: #{response.code}"
    puts "Elapsed: #{elapsed_ms}ms"
    puts 'Body:'
    puts response.body
  end
end
