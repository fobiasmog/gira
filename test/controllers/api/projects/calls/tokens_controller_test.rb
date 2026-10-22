require "test_helper"
require "support/live_kit_test_helper"

class Api::Projects::Calls::TokensControllerTest < ActionDispatch::IntegrationTest
  include LiveKitTestHelper

  setup do
    @project = projects(:goal)
    sign_in_as users(:two)
  end

  test "a member gets the media server's address and a token for the project's call" do
    post api_project_call_token_path(@project)

    assert_response :created
    assert_equal Rails.configuration.x.livekit[:url], response.parsed_body["url"]
    claims = jwt_claims(response.parsed_body["token"])
    assert_equal users(:two).id.to_s, claims["sub"]
    assert_equal "project-#{@project.id}", claims.dig("video", "room")
  end

  test "no personal data beyond the name" do
    post api_project_call_token_path(@project)

    claims = jwt_claims(response.parsed_body["token"])
    assert_equal "User Two", claims["name"]
    assert_equal %w[exp iss name nbf sub video], claims.keys.sort
    assert_no_match(/two@example\.com|avatar/, Base64.urlsafe_decode64(response.parsed_body["token"].split(".").second))
  end

  test "not a member: 404 and no token" do
    sign_in_as users(:one)

    post api_project_call_token_path(projects(:side))

    assert_response :not_found
    assert_nil response.parsed_body["token"]
  end

  test "archived project: 404" do
    @project.archive!

    post api_project_call_token_path(@project)

    assert_response :not_found
  end

  test "too many token requests: the twenty-first within a minute gets 429 and no token" do
    20.times do
      post api_project_call_token_path(@project)
      assert_response :created
    end

    post api_project_call_token_path(@project)

    assert_response :too_many_requests
    assert_equal "rate_limited", response.parsed_body.dig("error", "code")
    assert_nil response.parsed_body["token"]

    travel 61.seconds
    post api_project_call_token_path(@project)
    assert_response :created
  end

  test "no media server configured: 404" do
    with_livekit(nil) { post api_project_call_token_path(@project) }

    assert_response :not_found
  end
end
