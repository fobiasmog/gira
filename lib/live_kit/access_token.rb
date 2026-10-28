require "base64"
require "json"
require "openssl"

# An access token for a LiveKit server: a JWT signed with HS256 using the API
# secret. The server reads the identity from `sub` and the permissions from the
# `video` grant (team-call design.md, Decision 3: no livekit-server-sdk gem).
#
#   LiveKit::AccessToken.new(api_key: "devkey", api_secret: "secret", identity: "7", name: "Alice",
#     video: { roomJoin: true, room: "project-1" }).to_jwt
class LiveKit::AccessToken
  TTL = 10.minutes

  def initialize(api_key:, api_secret:, video:, identity: nil, name: nil, ttl: TTL)
    @api_key = api_key
    @api_secret = api_secret
    @video = video
    @identity = identity
    @name = name
    @ttl = ttl
  end

  def claims(now: Time.current)
    { iss: @api_key, sub: @identity, name: @name, nbf: now.to_i, exp: (now + @ttl).to_i, video: @video }.compact
  end

  def to_jwt(now: Time.current)
    signing_input = [ { alg: "HS256", typ: "JWT" }, claims(now: now) ].map { |part| encode(JSON.generate(part)) }.join(".")
    "#{signing_input}.#{encode(OpenSSL::HMAC.digest("SHA256", @api_secret, signing_input))}"
  end

  private
    def encode(data)
      Base64.urlsafe_encode64(data, padding: false)
    end
end
