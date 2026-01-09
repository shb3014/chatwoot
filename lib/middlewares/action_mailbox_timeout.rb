## frozen_string_literal: true

module Middlewares
  class ActionMailboxTimeout
    ACTION_MAILBOX_RELAY_PATH = '/rails/action_mailbox/relay/inbound_emails'
    DEFAULT_TIMEOUT_SECONDS = 120

    def initialize(app)
      @app = app
    end

    def call(env)
      path = env['PATH_INFO'].to_s
      if path == ACTION_MAILBOX_RELAY_PATH
        env['rack.timeout.service_timeout'] = action_mailbox_timeout_seconds
      end

      @app.call(env)
    end

    private

    def action_mailbox_timeout_seconds
      Integer(
        ENV.fetch(
          'ACTION_MAILBOX_RACK_TIMEOUT',
          ENV.fetch('RACK_TIMEOUT_SERVICE_TIMEOUT', DEFAULT_TIMEOUT_SECONDS.to_s)
        )
      )
    rescue ArgumentError, TypeError
      DEFAULT_TIMEOUT_SECONDS
    end
  end
end

