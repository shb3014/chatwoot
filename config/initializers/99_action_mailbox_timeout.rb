# frozen_string_literal: true

# Only increase rack-timeout for ActionMailbox relay endpoint.
# Large emails with multiple attachments can take longer to persist (Active Storage/S3),
# and we don't want to increase timeouts for the entire application.
require 'rack-timeout'
require Rails.root.join('lib/middlewares/action_mailbox_timeout')

# Ensure this runs before Rack::Timeout so per-request overrides take effect.
#
# We observed Rack::Timeout still timing out ActionMailbox relay at 15s, which strongly suggests
# Rack::Timeout is currently wrapping this middleware (i.e. timer starts before we can set env overrides).
# To make this robust across middleware insertion order, we explicitly re-order the stack:
# - place Middlewares::ActionMailboxTimeout before Rack::Timeout
# - ensure Rack::Timeout remains immediately after it
middleware = Rails.application.config.middleware

begin
  middleware.delete(Middlewares::ActionMailboxTimeout)
rescue StandardError
  # noop
end

begin
  middleware.delete(Rack::Timeout)
rescue StandardError
  # noop
end

middleware.insert_before 0, Middlewares::ActionMailboxTimeout
middleware.insert_after Middlewares::ActionMailboxTimeout, Rack::Timeout
