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
        timeout = action_mailbox_timeout_seconds
        env['rack.timeout.service_timeout'] = timeout
        # If the app is under load, requests can sit in Puma's queue.
        # Increase wait timeout for this endpoint to avoid premature rack-timeout failures.
        env['rack.timeout.wait_timeout'] = action_mailbox_wait_timeout_seconds(timeout)
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

    def action_mailbox_wait_timeout_seconds(default_value)
      Integer(ENV.fetch('ACTION_MAILBOX_RACK_WAIT_TIMEOUT', default_value.to_s))
    rescue ArgumentError, TypeError
      default_value
    end
  end
end

