require "test_helper"

# Client ID metadata documents are paused (harden-mcp-oauth design.md,
# decision 12): no fetch, no stored document client, and dynamic
# registration as before. Other tests run with documents on.
class OauthClientMetadataDocumentsPausedTest < ActionDispatch::IntegrationTest
  setup do
    Rails.configuration.x.oauth.client_metadata_documents = false
    sign_in_as users(:two)
  end

  test "the metadata does not offer them, so clients register dynamically" do
    get "/.well-known/oauth-authorization-server"

    assert_equal false, response.parsed_body["client_id_metadata_document_supported"]
    assert_equal "https://goalner.com/oauth/register", response.parsed_body["registration_endpoint"]
  end

  test "a new document URL gets the error page, without a fetch" do
    url = "https://inspector.example/oauth/metadata"
    get oauth_authorization_path(response_type: "code", client_id: url, redirect_uri: "https://inspector.example/callback",
      scope: "read", state: "state-123", code_challenge: new_pkce.challenge, code_challenge_method: "S256")

    assert_response :bad_request
    assert_select "code", "invalid_client"
    assert_nil response.location
    assert_not Oauth::Application.exists?(uid: url)
  end

  test "a stored document client gets the error page, and approving issues no code" do
    params = authorization_params(oauth_applications(:claude_ai))

    get oauth_authorization_path(params)
    assert_response :bad_request
    assert_select "code", "invalid_client"

    post oauth_authorization_path, params: params.merge(access: "read")
    assert_response :bad_request
    assert_empty Oauth::AccessGrant.all
  end

  test "a dynamically registered client still gets the consent page" do
    get oauth_authorization_path(authorization_params(oauth_applications(:cursor)))

    assert_response :success
    assert_select "h1", /wants to access your Goalner account/
  end
end
