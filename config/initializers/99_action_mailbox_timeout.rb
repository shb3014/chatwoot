# frozen_string_literal: true

# Only increase rack-timeout for ActionMailbox relay endpoint.
# Large emails with multiple attachments can take longer to persist (Active Storage/S3),
# and we don't want to increase timeouts for the entire application.
require 'rack-timeout'
require Rails.root.join('lib/middlewares/action_mailbox_timeout')

# Ensure this runs before Rack::Timeout so per-request overrides take effect.
# Note: Some stacks may insert Rack::Timeout at the beginning of the middleware chain.
# In that case, inserting at index 0 is not sufficient because Rack::Timeout would still wrap
# this middleware. Always prefer inserting explicitly before Rack::Timeout when available.
if defined?(Rack::Timeout)
  Rails.application.config.middleware.insert_before Rack::Timeout, Middlewares::ActionMailboxTimeout
else
  Rails.application.config.middleware.insert_before 0, Middlewares::ActionMailboxTimeout
end

