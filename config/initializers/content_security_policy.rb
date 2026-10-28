# Content Security Policy (spec security-baseline, "Content Security Policy").
# Everything comes from the application's own origin. The only third-party
# destinations are the Sentry ingest host, for the SPA's error reports, and the
# media server for calls when one is configured.
# Development additionally allows the Vite dev server, and nothing else. Its
# origin is also a form-action target there: forms posted to Rails on port 3000
# may end in a redirect to /app, which SpaController sends to the dev server.
# There, the Vite client injects stylesheets as <style> elements; they carry a
# per-request nonce that the SPA layout exposes in <meta property="csp-nonce">.

Rails.application.configure do
  sentry_dsn = Rails.application.credentials.dig(:sentry, :frontend_dsn)
  sentry_ingest = URI(sentry_dsn).then { |uri| "#{uri.scheme}://#{uri.host}" } if sentry_dsn.present?

  vite_dev_server = ENV.fetch("VITE_DEV_SERVER_HOST", "localhost:5173") if Rails.env.development? && ENV["VITE_DEV_SERVER"] != "off"
  vite_http = [ "http://#{vite_dev_server}" ] if vite_dev_server
  vite_ws = [ "ws://#{vite_dev_server}" ] if vite_dev_server

  # The media server's WebSocket origin and its HTTP equivalent, which the call
  # client asks after a failed connection (config.x.livekit, set in the
  # environment files). Read on every request, so tests can switch calls off.
  media_server = lambda do
    url = Rails.configuration.x.livekit&.dig(:url) or next []
    uri = URI(url)
    origin = "#{uri.host}#{":#{uri.port}" if uri.port != uri.default_port}"
    [ "#{uri.scheme}://#{origin}", "#{uri.scheme.sub("ws", "http")}://#{origin}" ]
  end

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.script_src :self, *vite_http
    policy.style_src :self, *vite_http
    policy.font_src :self, *vite_http
    policy.img_src :self, :data, :blob, *vite_http
    policy.connect_src -> { [ :self, *sentry_ingest, *vite_http, *vite_ws, *media_server.call ] }
    policy.frame_src :self
    policy.form_action :self, *vite_http
    policy.object_src :none
    policy.base_uri :self
    policy.frame_ancestors :none
  end

  if vite_dev_server
    config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
    config.content_security_policy_nonce_directives = %w[style-src]
  end
end
