# Drives the OAuth authorization code flow of spec mcp-authorization in
# integration tests: PKCE pairs, authorization requests, consent and the
# token endpoint, and decoding the issued JWTs with the public key.
module OauthTestHelper
  extend ActiveSupport::Concern

  Pkce = Data.define(:verifier, :challenge)

  # Client ID metadata documents are paused in every environment
  # (Oauth.client_metadata_documents?), but their code is kept, so tests run
  # with them on. OauthClientMetadataDocumentsPausedTest checks the default.
  #
  # Fixtures are loaded once per test process, so the fetch time they give
  # the CIMD clients can be minutes old when a test begins, and a request
  # with an unlisted redirect URI would then refetch the document. Every test
  # starts with them just fetched instead (harden-mcp-oauth design.md,
  # decision 10); the test's transaction rolls it back.
  included do
    setup do
      @client_metadata_documents = Rails.configuration.x.oauth.client_metadata_documents
      Rails.configuration.x.oauth.client_metadata_documents = true
      Oauth::Application.cimd.update_all(metadata_fetched_at: Time.current)
    end
    teardown { Rails.configuration.x.oauth.client_metadata_documents = @client_metadata_documents }
  end

  def new_pkce
    verifier = SecureRandom.urlsafe_base64(48)
    Pkce.new(verifier: verifier, challenge: Base64.urlsafe_encode64(Digest::SHA256.digest(verifier), padding: false))
  end

  # The query of an authorization request from application, with a fresh
  # PKCE challenge unless one is given.
  def authorization_params(application, pkce: (@pkce = new_pkce), redirect_uri: application.redirect_uris.first, **overrides)
    { response_type: "code", client_id: application.uid, redirect_uri: redirect_uri, scope: "read write",
      state: "state-123", code_challenge: pkce.challenge, code_challenge_method: "S256", resource: Oauth.resource }
      .merge(overrides).compact
  end

  # Approves on the consent page and returns the code from the redirect.
  def approve(params, access: "read")
    post oauth_authorization_path, params: params.merge(access: access)
    assert_response :redirect
    redirect_query(response.location).fetch("code")
  end

  def exchange_code(code, application, pkce: @pkce, redirect_uri: application.redirect_uris.first)
    post oauth_token_path, params: { grant_type: "authorization_code", code: code, code_verifier: pkce.verifier,
                                     client_id: application.uid, redirect_uri: redirect_uri }
    response.parsed_body
  end

  def refresh(refresh_token, application)
    post oauth_token_path, params: { grant_type: "refresh_token", refresh_token: refresh_token, client_id: application.uid }
    response.parsed_body
  end

  # Signs in as user, approves application with access and exchanges the
  # code: the token response.
  def connect(user, application, access: "read", scope: "read write")
    sign_in_as user
    params = authorization_params(application, scope: scope)
    get oauth_authorization_path(params)
    assert_response :success
    exchange_code(approve(params, access: access), application)
  end

  def redirect_query(location)
    Rack::Utils.parse_query(URI(location).query)
  end

  # An access token of user's connection with application, as the token
  # endpoint issues it, and a connection token for it: [api_token, access_token, jwt].
  def create_connection_token(user, application: oauth_applications(:claude_ai), scopes: "read write")
    access_token = Oauth::AccessToken.create!(application: application, resource_owner_id: user.id, scopes: scopes,
      expires_in: 1.hour.to_i, use_refresh_token: true)
    [ ApiToken.issue_for_connection!(access_token), access_token, access_token.plaintext_token ]
  end

  def jwt_public_key
    OpenSSL::PKey.read(Oauth::JwtGenerator.public_key_pem)
  end

  def decode_access_token(token)
    JWT.decode(token, jwt_public_key, true, algorithm: "ES256", iss: Oauth.issuer, verify_iss: true,
      aud: Oauth.resource, verify_aud: true)
  end
end

ActiveSupport::TestCase.include OauthTestHelper
