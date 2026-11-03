require "test_helper"

# Spec mcp-authorization, "Dynamic client registration"; add-mcp-oauth
# design.md, decision 5.
class Oauth::RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def register(body = {}, ip: "203.0.113.7", **fields)
    post oauth_registration_path, params: body.merge(fields), as: :json, env: { "REMOTE_ADDR" => ip }
  end

  test "registration" do
    assert_difference -> { Oauth::Application.count } do
      register client_name: "Cursor", redirect_uris: [ "http://127.0.0.1/callback" ]
    end

    assert_response :created
    body = response.parsed_body
    application = Oauth::Application.find_by!(uid: body["client_id"])
    assert_equal "none", body["token_endpoint_auth_method"]
    assert_equal "Cursor", body["client_name"]
    assert_equal [ "http://127.0.0.1/callback" ], body["redirect_uris"]
    assert_equal %w[authorization_code refresh_token], body["grant_types"]
    assert_equal [ "code" ], body["response_types"]
    assert_in_delta Time.current.to_i, body["client_id_issued_at"], 5
    assert application.dcr?
    assert_not application.confidential?
  end

  test "plain HTTP redirect" do
    assert_no_difference -> { Oauth::Application.count } do
      register client_name: "Cursor", redirect_uris: [ "http://example.com/callback" ]
    end

    assert_response :bad_request
    assert_equal "invalid_redirect_uri", response.parsed_body["error"]
  end

  test "other refused redirect URIs and names" do
    [ { redirect_uris: [] }, { redirect_uris: "https://a.example/cb" }, { redirect_uris: [ "https://a.example/cb#x" ] },
      { redirect_uris: [ "javascript:alert(1)" ] }, { redirect_uris: [ "urn:ietf:wg:oauth:2.0:oob" ] },
      { redirect_uris: [ "https://user@a.example/cb" ] }, { redirect_uris: Array.new(11) { "https://a.example/#{it}" } },
      { client_name: "x" * 101, redirect_uris: [ "https://a.example/cb" ] }, {} ].each do |body|
      assert_no_difference -> { Oauth::Application.count } do
        register body
      end
      assert_response :bad_request, body.inspect
    end
  end

  test "registration burst: the 21st from one address within an hour is refused" do
    20.times { |n| register({ client_name: "Bot #{n}", redirect_uris: [ "https://bot.example/cb" ] }) }
    assert_response :created

    assert_no_difference -> { Oauth::Application.count } do
      register client_name: "Bot 21", redirect_uris: [ "https://bot.example/cb" ]
    end
    assert_response :too_many_requests

    register({ client_name: "Elsewhere", redirect_uris: [ "https://bot.example/cb" ] }, ip: "198.51.100.9")
    assert_response :created

    travel 61.minutes
    register client_name: "Later", redirect_uris: [ "https://bot.example/cb" ]
    assert_response :created
  end

  test "a request asking for client_secret_basic is registered as a public client" do
    register client_name: "Server app", redirect_uris: [ "https://app.example/cb" ], token_endpoint_auth_method: "client_secret_basic",
      grant_types: %w[authorization_code client_credentials], response_types: %w[code token]

    assert_response :created
    assert_equal "none", response.parsed_body["token_endpoint_auth_method"]
    assert_equal %w[authorization_code refresh_token], response.parsed_body["grant_types"]
    assert_not Oauth::Application.find_by!(uid: response.parsed_body["client_id"]).confidential?
  end

  test "the response carries no secret" do
    register client_name: "Cursor", redirect_uris: [ "https://cursor.example/cb" ]

    assert_empty response.parsed_body.keys.grep(/secret|registration_access_token|registration_client_uri/)
    assert_nil Oauth::Application.find_by!(uid: response.parsed_body["client_id"]).secret
  end

  test "the client name falls back to the redirect host" do
    register redirect_uris: [ "https://cursor.example/cb" ]

    assert_equal "cursor.example", response.parsed_body["client_name"]
  end

  test "a registered client can be authorized" do
    register client_name: "Cursor", redirect_uris: [ "http://127.0.0.1/callback" ]
    client = Oauth::Application.find_by!(uid: response.parsed_body["client_id"])

    tokens = connect(users(:two), client)

    assert tokens["access_token"].present?
  end
end
