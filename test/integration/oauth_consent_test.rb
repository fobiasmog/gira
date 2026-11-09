require "test_helper"

# Consent and what follows it (spec mcp-authorization, "Sign-in before
# consent", "Consent page", "Consent decision", "Access tokens", "Refresh
# tokens" and "Token revocation endpoint"; add-mcp-oauth design.md, decision 6).
class OauthConsentTest < ActionDispatch::IntegrationTest
  setup do
    @claude = oauth_applications(:claude_ai)
    @claude_code = oauth_applications(:claude_code)
    @cursor = oauth_applications(:cursor)
  end

  # Sign-in before consent

  test "signed out: sign-in, then back to the same request" do
    params = authorization_params(@claude)

    get oauth_authorization_path(params)
    assert_redirected_to new_session_path

    sign_in_with users(:two).email_address
    assert_redirected_to oauth_authorization_url(params)
    follow_redirect!

    assert_response :success
    assert_select "h1", "claude.ai wants to access your Goalner account"
    assert_select "input[name=code_challenge][value=?]", params[:code_challenge]
    assert_select "input[name=state][value=?]", "state-123"
  end

  test "signed out: approving or denying needs a session" do
    post oauth_authorization_path, params: authorization_params(@claude).merge(access: "read")
    assert_redirected_to new_session_path
    delete oauth_authorization_path, params: authorization_params(@claude)
    assert_redirected_to new_session_path
    assert_empty Oauth::AccessGrant.all
  end

  # Consent page

  test "claude.ai: the host, the client's name, the all-projects statement, and read-only preselected" do
    sign_in_as users(:two)
    get oauth_authorization_path(authorization_params(@claude, scope: "read write"))

    assert_response :success
    assert_select "h1 strong", "claude.ai"
    assert_select "p", "The app calls itself Claude."
    assert_select "p", "Its details are published by claude.ai."
    assert_select "p", /all of your projects, including the ones you join later/
    assert_select "input[type=radio][name=access][value=read][checked]"
    assert_select "input[type=radio][name=access][value=read_write]:not([checked])"
    assert_select ".consent__warning", count: 0
    assert_select "input[type=password]", count: 0
  end

  test "the original request travels in both forms" do
    sign_in_as users(:two)
    params = authorization_params(@claude)
    get oauth_authorization_path(params)

    %w[form.consent__form form.consent__deny].each do |form|
      params.except(:response_type).each do |name, value|
        assert_select "#{form} input[type=hidden][name=?][value=?]", name.to_s, value.to_s
      end
    end
  end

  test "loopback client: the warning about an app on this device" do
    sign_in_as users(:two)
    get oauth_authorization_path(authorization_params(@claude_code, redirect_uri: "http://127.0.0.1:43123/callback"))

    assert_select "h1 strong", "127.0.0.1"
    assert_select ".consent__warning", /only to an app running on this device/
  end

  test "a client with a loopback and an HTTPS redirect URI gets no warning" do
    sign_in_as users(:two)
    get oauth_authorization_path(authorization_params(@cursor, redirect_uri: "http://127.0.0.1:43123/callback"))

    assert_select ".consent__warning", count: 0
  end

  test "read scope only: no read-write option" do
    sign_in_as users(:two)
    get oauth_authorization_path(authorization_params(@claude, scope: "read"))

    assert_select "input[name=access][value=read][checked]"
    assert_select "input[name=access][value=read_write]", count: 0
  end

  test "in Russian" do
    users(:two).update!(lang: "ru")
    sign_in_as users(:two)
    get oauth_authorization_path(authorization_params(@claude_code, redirect_uri: "http://localhost:4000/callback"))

    assert_select "h1", "localhost запрашивает доступ к вашему аккаунту Goalner"
    assert_select ".consent__warning", /только приложение на этом устройстве/
    assert_select "button[type=submit]", "Разрешить"
    assert_select "button[type=submit]", "Отклонить"
  end

  # Consent decision

  test "approve read-only: the access token carries only read" do
    tokens = connect(users(:two), @claude, access: "read", scope: "read write")

    assert_equal "read", tokens["scope"]
    assert_equal "read", decode_access_token(tokens["access_token"]).first["scope"]
  end

  test "approve read-write" do
    tokens = connect(users(:two), @claude, access: "read_write", scope: "read write")

    assert_equal "read write", decode_access_token(tokens["access_token"]).first["scope"]
  end

  test "a hand-edited read_write on a request that asked only for read still issues read" do
    tokens = connect(users(:two), @claude, access: "read_write", scope: "read")

    assert_equal "read", decode_access_token(tokens["access_token"]).first["scope"]
  end

  test "no scope requested: read" do
    sign_in_as users(:two)
    params = authorization_params(@claude).except(:scope)
    get oauth_authorization_path(params)
    assert_select "input[name=access][value=read_write]", count: 0

    assert_equal "read", exchange_code(approve(params, access: "read_write"), @claude)["scope"]
  end

  test "a scope outside read and write is refused" do
    sign_in_as users(:two)
    get oauth_authorization_path(authorization_params(@claude, scope: "read admin"))
    assert_equal "invalid_scope", redirect_query(response.location)["error"]

    post oauth_authorization_path, params: authorization_params(@claude, scope: "read admin").merge(access: "read")
    assert_equal "invalid_scope", redirect_query(response.location)["error"]
    assert_empty Oauth::AccessGrant.all
  end

  test "the code is bound to the user, the client, the PKCE challenge and the redirect URI" do
    sign_in_as users(:two)
    params = authorization_params(@claude)
    code = approve(params)

    grant = Oauth::AccessGrant.sole
    assert_equal [ users(:two).id, @claude.id, params[:code_challenge], "S256", @claude.redirect_uris.first ],
      [ grant.resource_owner_id, grant.application_id, grant.code_challenge, grant.code_challenge_method, grant.redirect_uri ]
    assert_equal 600, grant.expires_in
    assert_not_equal code, grant.token
  end

  test "deny: access_denied at the client, and nothing created" do
    sign_in_as users(:two)
    params = authorization_params(@claude)
    get oauth_authorization_path(params)

    assert_no_difference -> { Oauth::AccessGrant.count + Oauth::AccessToken.count } do
      delete oauth_authorization_path, params: params
    end

    assert response.location.start_with?("https://claude.ai/api/mcp/auth_callback?")
    assert_equal "access_denied", redirect_query(response.location)["error"]
    assert_equal "state-123", redirect_query(response.location)["state"]
  end

  test "code reused: invalid_grant" do
    sign_in_as users(:two)
    code = approve(authorization_params(@claude))
    assert exchange_code(code, @claude)["access_token"]

    assert_equal "invalid_grant", exchange_code(code, @claude)["error"]
    assert_response :bad_request
  end

  test "a code expires after 10 minutes" do
    sign_in_as users(:two)
    code = approve(authorization_params(@claude))
    travel 601.seconds

    assert_equal "invalid_grant", exchange_code(code, @claude)["error"]
  end

  # Access tokens

  test "code exchange: an access token for the MCP resource that expires in 1 hour, and a refresh token" do
    tokens = connect(users(:two), @claude)

    claims = decode_access_token(tokens["access_token"]).first
    assert_equal goalner_url("/mcp"), claims["aud"]
    assert_equal 1.hour.to_i, claims["exp"] - claims["iat"]
    assert_equal 3600, tokens["expires_in"]
    assert tokens["refresh_token"].present?
  end

  test "wrong verifier: invalid_grant, and nothing issued" do
    sign_in_as users(:two)
    code = approve(authorization_params(@claude))

    assert_no_difference -> { Oauth::AccessToken.count } do
      assert_equal "invalid_grant", exchange_code(code, @claude, pkce: new_pkce)["error"]
    end
  end

  test "a missing verifier, another client or another redirect URI: nothing issued" do
    sign_in_as users(:two)
    code = approve(authorization_params(@claude))

    post oauth_token_path, params: { grant_type: "authorization_code", code: code, client_id: @claude.uid, redirect_uri: @claude.redirect_uris.first }
    assert_equal "invalid_request", response.parsed_body["error"]
    assert_equal "invalid_grant", exchange_code(code, @cursor, redirect_uri: @claude.redirect_uris.first)["error"]
    assert_equal "invalid_grant", exchange_code(code, @claude, redirect_uri: "https://claude.ai/other")["error"]
    assert_empty Oauth::AccessToken.all
  end

  # Refresh tokens

  test "refresh: a new access token with the same scope and a new refresh token" do
    tokens = connect(users(:two), @claude, access: "read_write")
    refreshed = refresh(tokens["refresh_token"], @claude)

    assert_response :success
    assert_not_equal tokens["access_token"], refreshed["access_token"]
    assert_not_equal tokens["refresh_token"], refreshed["refresh_token"]
    assert_equal "read write", refreshed["scope"]
    assert_equal "read write", decode_access_token(refreshed["access_token"]).first["scope"]
  end

  test "a refresh token of another client is refused" do
    tokens = connect(users(:two), @claude)

    assert_equal "invalid_grant", refresh(tokens["refresh_token"], @cursor)["error"]
  end

  # Token revocation endpoint

  test "client revokes: refreshing with the revoked refresh token gets invalid_grant" do
    tokens = connect(users(:two), @claude)

    post oauth_revoke_path, params: { token: tokens["refresh_token"], token_type_hint: "refresh_token", client_id: @claude.uid }
    assert_response :success

    assert_equal "invalid_grant", refresh(tokens["refresh_token"], @claude)["error"]
  end

  test "a client cannot revoke another client's token" do
    tokens = connect(users(:two), @claude)

    post oauth_revoke_path, params: { token: tokens["refresh_token"], client_id: @cursor.uid }
    assert_response :forbidden

    assert refresh(tokens["refresh_token"], @claude)["access_token"]
  end
end
