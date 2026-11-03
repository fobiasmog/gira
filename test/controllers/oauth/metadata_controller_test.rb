require "test_helper"

# Spec mcp-authorization, "Authorization server metadata"; add-mcp-oauth
# design.md, decision 3.
class Oauth::MetadataControllerTest < ActionDispatch::IntegrationTest
  test "metadata" do
    get "/.well-known/oauth-authorization-server"

    assert_response :success
    metadata = response.parsed_body
    assert_equal "https://goalner.com", metadata["issuer"]
    assert_equal "https://goalner.com/oauth/authorize", metadata["authorization_endpoint"]
    assert_equal "https://goalner.com/oauth/token", metadata["token_endpoint"]
    assert_equal "https://goalner.com/oauth/register", metadata["registration_endpoint"]
    assert_equal "https://goalner.com/oauth/revoke", metadata["revocation_endpoint"]
    assert_equal [ "S256" ], metadata["code_challenge_methods_supported"]
    assert_includes metadata["token_endpoint_auth_methods_supported"], "none"
    assert_equal true, metadata["client_id_metadata_document_supported"]
  end

  test "only the code flow, query responses and the read and write scopes, without offline_access" do
    get "/.well-known/oauth-authorization-server"

    metadata = response.parsed_body
    assert_equal [ "code" ], metadata["response_types_supported"]
    assert_equal [ "query" ], metadata["response_modes_supported"]
    assert_equal %w[authorization_code refresh_token], metadata["grant_types_supported"]
    assert_equal [ "none" ], metadata["token_endpoint_auth_methods_supported"]
    assert_equal %w[read write], metadata["scopes_supported"]
    assert_not_includes response.body, "offline_access"
  end

  test "the endpoints are the routed ones" do
    get "/.well-known/oauth-authorization-server"

    { "authorization_endpoint" => oauth_authorization_path, "token_endpoint" => oauth_token_path,
      "revocation_endpoint" => oauth_revoke_path }.each do |key, path|
      assert_equal path, URI(response.parsed_body[key]).path, key
    end
  end

  test "public, without a session, for browser clients too" do
    get "/.well-known/oauth-authorization-server"

    assert_equal "*", response.headers["Access-Control-Allow-Origin"]
    assert_nil response.headers["Set-Cookie"]
  end
end
