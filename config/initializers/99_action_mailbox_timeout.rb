# frozen_string_literal: true

# Only increase rack-timeout for ActionMailbox relay endpoint.
# Large emails with multiple attachments can take longer to persist (Active Storage/S3),
# and we don't want to increase timeouts for the entire application.
require 'rack-timeout'
require Rails.root.join('lib/middlewares/action_mailbox_timeout')

# Ensure this runs before Rack::Timeout so per-request overrides take effect.
Rails.application.config.middleware.insert_before 0, Middlewares::ActionMailboxTimeout

