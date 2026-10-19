# Error tracking with personal data disabled (spec security-baseline,
# "Privacy-preserving logs and error tracking"; design.md, Decision 14).
# Users are identified by internal id only (see ApplicationController).

# Second line of defence behind `data_collection`: strips request bodies,
# cookies, IP addresses and any user field other than the id from every event.
SentryScrubber = lambda do |event, _hint|
  if (request = event.request)
    request.data = nil
    request.cookies = nil
    request.headers = request.headers&.reject { |name, _| name.match?(/cookie|authorization|forwarded|real-ip|csrf/i) }
    request.env = request.env&.except("REMOTE_ADDR", "HTTP_X_FORWARDED_FOR", "HTTP_X_REAL_IP")
  end
  event.user = event.user.slice(:id) if event.user
  event
end

Sentry.init do |config|
  config.dsn = Rails.application.credentials.dig(:sentry, :backend_dsn)
  config.enabled_environments = %w[production]

  # sentry-ruby 7.1 replaces `send_default_pii = false` with these settings.
  config.data_collection.user_info = false
  config.data_collection.cookies.mode = :off
  config.data_collection.http_bodies = []
  config.data_collection.stack_frame_variables = false
  config.data_collection.database_query_data = false

  config.before_send = SentryScrubber
  config.rails.register_error_subscriber = true
end
