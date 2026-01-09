# frozen_string_literal: true

# Only increase rack-timeout for ActionMailbox relay endpoint.
# Large emails with multiple attachments can take longer to persist (Active Storage/S3),
# and we don't want to increase timeouts for the entire application.
require 'rack-timeout'
require Rails.root.join('lib/middlewares/action_mailbox_timeout')

Rails.application.config.middleware.insert_before Rack::Timeout, Middlewares::ActionMailboxTimeout

