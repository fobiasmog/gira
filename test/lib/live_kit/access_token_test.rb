require "test_helper"
require "support/live_kit_test_helper"

class LiveKit::AccessTokenTest < ActiveSupport::TestCase
  include LiveKitTestHelper

  NOW = Time.utc(2026, 10, 22, 12)

  test "is an HS256 JWT signed with the API secret" do
    header, payload, signature = token.to_jwt.split(".")

    assert_equal({ "alg" => "HS256", "typ" => "JWT" }, JSON.parse(Base64.urlsafe_decode64(header)))
    assert_equal OpenSSL::HMAC.digest("SHA256", "secret", "#{header}.#{payload}"), Base64.urlsafe_decode64(signature)
    assert_not_equal OpenSSL::HMAC.digest("SHA256", "other secret", "#{header}.#{payload}"), Base64.urlsafe_decode64(signature)
  end

  test "carries the API key, identity, name, validity and video grant, and expires after 10 minutes" do
    claims = jwt_claims(token.to_jwt(now: NOW))

    assert_equal({ "iss" => "devkey", "sub" => "7", "name" => "Alice", "nbf" => NOW.to_i, "exp" => (NOW + 10.minutes).to_i,
                   "video" => { "roomJoin" => true, "room" => "project-1" } }, claims)
  end

  test "a shorter lifetime" do
    claims = jwt_claims(token(ttl: 30.seconds).to_jwt(now: NOW))

    assert_equal NOW.to_i + 30, claims["exp"]
  end

  test "leaves out the identity and name when there are none" do
    claims = jwt_claims(LiveKit::AccessToken.new(api_key: "devkey", api_secret: "secret", video: { roomAdmin: true }).to_jwt)

    assert_equal %w[exp iss nbf video], claims.keys.sort
  end

  private
    def token(**options)
      LiveKit::AccessToken.new(api_key: "devkey", api_secret: "secret", identity: "7", name: "Alice",
        video: { roomJoin: true, room: "project-1" }, **options)
    end
end
