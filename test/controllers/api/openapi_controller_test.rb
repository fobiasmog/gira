require "test_helper"

# Spec api-documentation, "Interactive API documentation".
class Api::OpenapiControllerTest < ActionDispatch::IntegrationTest
  test "download the document: YAML for a signed-in user" do
    sign_in_as users(:one)

    get api_openapi_document_path

    assert_response :success
    assert_equal "application/yaml", response.media_type
    assert_equal "private, no-store", response.headers["Cache-Control"]
    assert_equal "3.1.0", YAML.safe_load(response.body).fetch("openapi")
  end

  test "an anonymous request gets 401 JSON" do
    get api_openapi_document_path

    assert_response :unauthorized
    assert_equal "unauthorized", response.parsed_body.dig("error", "code")
  end

  test "token request: 403 token_not_allowed" do
    get api_openapi_document_path, headers: { "Authorization" => "Bearer glnr_two_goal_read" }

    assert_response :forbidden
    assert_equal "token_not_allowed", response.parsed_body.dig("error", "code")
  end
end
