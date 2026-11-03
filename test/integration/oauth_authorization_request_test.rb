require "test_helper"

# Spec mcp-authorization, "Authorization requests"; add-mcp-oauth design.md,
# decisions 1 and 6. Refusals go back to the client's registered redirect
# URI, or to an error page when there is none to trust.
class OauthAuthorizationRequestTest < ActionDispatch::IntegrationTest
  setup do
    @client = oauth_applications(:cursor)
    @claude_code = oauth_applications(:claude_code)
    sign_in_as users(:two)
  end

  def assert_redirected_with_error(error, client: @client)
    assert_response :redirect
    assert response.location.start_with?(client.redirect_uris.first.split("?").first), response.location
    query = redirect_query(response.location)
    assert_equal error, query["error"]
    assert_equal "state-123", query["state"]
    assert_nil query["code"]
  end

  test "missing PKCE" do
    get oauth_authorization_path(authorization_params(@client).except(:code_challenge, :code_challenge_method))

    assert_redirected_with_error "invalid_request"
    assert_equal "Code challenge is required.", redirect_query(response.location)["error_description"]
  end

  test "plain challenge" do
    get oauth_authorization_path(authorization_params(@client, code_challenge_method: "plain"))

    assert_redirected_with_error "invalid_request"
    assert_equal "The code_challenge_method must be S256.", redirect_query(response.location)["error_description"]
  end

  test "plain challenge is refused at consent too" do
    post oauth_authorization_path, params: authorization_params(@client, code_challenge_method: "plain").merge(access: "read")

    assert_redirected_with_error "invalid_request"
    assert_empty Oauth::AccessGrant.all
  end

  test "loopback on any port, for localhost and 127.0.0.1" do
    [ "http://localhost:51234/callback", "http://127.0.0.1:51234/callback", "http://localhost/callback" ].each do |redirect_uri|
      get oauth_authorization_path(authorization_params(@claude_code, redirect_uri: redirect_uri))

      assert_response :success, redirect_uri
      assert_select "h1", /wants to access your Goalner account/
    end
  end

  test "a loopback port does not open other paths, schemes or hosts" do
    [ "http://localhost:51234/other", "https://localhost:51234/callback", "http://localhost.evil.example:51234/callback",
      "http://127.0.0.2:51234/callback" ].each do |redirect_uri|
      get oauth_authorization_path(authorization_params(@claude_code, redirect_uri: redirect_uri))

      assert_response :bad_request, redirect_uri
      assert_select "code", "invalid_redirect_uri"
    end
  end

  test "other resource" do
    get oauth_authorization_path(authorization_params(@client, resource: "https://other.example/mcp"))

    assert_redirected_with_error "invalid_target"
  end

  test "other resource at consent, and at the token endpoint" do
    post oauth_authorization_path, params: authorization_params(@client, resource: "https://other.example/mcp").merge(access: "read")
    assert_redirected_with_error "invalid_target"

    params = authorization_params(@client)
    code = approve(params)
    post oauth_token_path, params: { grant_type: "authorization_code", code: code, code_verifier: @pkce.verifier,
      client_id: @client.uid, redirect_uri: @client.redirect_uris.first, resource: "https://other.example/mcp" }
    assert_response :bad_request
    assert_equal "invalid_target", response.parsed_body["error"]

    tokens = exchange_code(code, @client)
    assert tokens["access_token"].present?, "the refused request left the code unused"
  end

  test "no resource, or Goalner's, is accepted" do
    get oauth_authorization_path(authorization_params(@client).except(:resource))
    assert_response :success
    get oauth_authorization_path(authorization_params(@client, resource: "https://goalner.com/mcp"))
    assert_response :success
  end

  test "response_mode=form_post and fragment are refused with a query redirect" do
    %w[form_post fragment].each do |mode|
      get oauth_authorization_path(authorization_params(@client, response_mode: mode))

      assert_redirected_with_error "unsupported_response_mode"
      assert_not_includes response.location, "#"
    end

    get oauth_authorization_path(authorization_params(@client, response_mode: "query"))
    assert_response :success
  end

  test "a refused parameter with an unregistered redirect URI gets the error page" do
    get oauth_authorization_path(authorization_params(@client, redirect_uri: "https://evil.example/cb", resource: "https://other.example/mcp"))

    assert_response :bad_request
    assert_select "code", "invalid_redirect_uri"
    assert_nil response.location
  end

  test "an unknown client gets the error page" do
    get oauth_authorization_path(authorization_params(@client, client_id: "unknown"))

    assert_response :unauthorized
    assert_select "code", "invalid_client"
  end

  test "error descriptions are in English for a Russian-speaking user" do
    users(:two).update!(lang: "ru")

    get oauth_authorization_path(authorization_params(@client, code_challenge_method: "plain"))

    assert_equal "The code_challenge_method must be S256.", redirect_query(response.location)["error_description"]
    get oauth_authorization_path(authorization_params(@client, client_id: "unknown"))
    assert_select "h1", "Приложение не может подключиться"
  end

  # Remove DoorkeeperLocalhostPorts (config/initializers/doorkeeper.rb) once
  # this fails: Doorkeeper then matches localhost ports on its own.
  test "Doorkeeper itself still does not match localhost on any port" do
    unpatched = Doorkeeper::OAuth::Helpers::URIChecker.method(:matches?).super_method

    assert_not_equal DoorkeeperLocalhostPorts, unpatched.owner
    assert_not unpatched.call("http://localhost:51234/callback", "http://localhost/callback"),
      "Doorkeeper #{Doorkeeper::VERSION::STRING} matches localhost ports: remove DoorkeeperLocalhostPorts"
  end
end
