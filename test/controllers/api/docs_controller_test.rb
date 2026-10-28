require "test_helper"

# Spec api-documentation, "Interactive API documentation".
class Api::DocsControllerTest < ActionDispatch::IntegrationTest
  test "signed-in user opens the docs: the viewer is mounted on the document" do
    sign_in_as users(:one)

    get api_docs_path

    assert_response :success
    assert_select "title", "API reference"
    assert_select "main#api-docs[data-document-url=?]", api_openapi_document_path
    assert_select "script[type=module][src=?]", "/vite/assets/api-docs-aaa111.js"
    assert_select "link[rel=stylesheet][href=?]", "/vite/assets/api-docs-bbb222.css"
    assert_select "script[src*=application]", count: 0
  end

  test "visitor without a session: sent to sign-in, then back to the docs" do
    get api_docs_path
    assert_redirected_to new_session_path

    sign_in_with users(:one).email_address

    assert_redirected_to api_docs_url
  end

  test "token request: 403 token_not_allowed, even with a session" do
    sign_in_as users(:two)

    get api_docs_path, headers: { "Authorization" => "Bearer glnr_two_goal_read_write" }

    assert_response :forbidden
    assert_equal "token_not_allowed", response.parsed_body.dig("error", "code")
  end

  test "an invalid token gets 401 with the JSON envelope" do
    get api_docs_path, headers: { "Authorization" => "Bearer glnr_unknown" }

    assert_response :unauthorized
    assert_equal "invalid_token", response.parsed_body.dig("error", "code")
  end
end
