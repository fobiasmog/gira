# Helpers for tests around calls (spec team-call).
module LiveKitTestHelper
  # The claims of a JWT, without checking its signature.
  def jwt_claims(jwt)
    JSON.parse(Base64.urlsafe_decode64(jwt.split(".").second))
  end

  # Runs the block with other LiveKit settings (config.x.livekit); nil means
  # no media server is configured.
  def with_livekit(settings)
    original = Rails.configuration.x.livekit
    Rails.configuration.x.livekit = settings
    yield
  ensure
    Rails.configuration.x.livekit = original
  end
end
