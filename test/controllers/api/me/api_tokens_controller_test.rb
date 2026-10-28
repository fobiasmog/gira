require "test_helper"

# Spec api-tokens, "Create a personal API token", "Token creation requires the
# current password", "List and revoke tokens" and "Token rate limits". one is
# a member of goal only and has one fixture token.
class Api::Me::ApiTokensControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = users(:one)
    sign_in_as @user
  end

  def create_token(**overrides)
    params = { name: "CI", project_id: projects(:goal).id, access: "read_write", expires_in_days: 90, current_password: PASSWORD }
    post api_me_api_tokens_path, params: params.merge(overrides).compact, as: :json
  end

  def field_errors
    response.parsed_body.dig("error", "fields")
  end

  test "successful creation: the value is returned once and the token is listed and works" do
    freeze_time do
      assert_difference -> { @user.api_tokens.count }, 1 do
        create_token
      end

      assert_response :created
      body = response.parsed_body
      assert_match(/\Aglnr_\w{40}\z/, body["token"])
      assert_equal [ "CI", "read_write", body["token"].last(4) ], body.values_at("name", "access", "last_characters")
      assert_equal({ "id" => projects(:goal).id, "title" => "Goalner", "short_name" => "GOAL" }, body["project"])
      assert_equal 90.days.from_now, Time.zone.parse(body["expires_at"])
    end

    value = response.parsed_body["token"]
    get api_me_api_tokens_path
    assert_includes response.parsed_body.map { |token| token["name"] }, "CI"

    sign_out
    get api_project_board_path(projects(:goal)), headers: { "Authorization" => "Bearer #{value}" }
    assert_response :success
  end

  test "expiry over a year is rejected" do
    assert_no_difference -> { ApiToken.count } do
      create_token(expires_in_days: 366)
    end

    assert_response :unprocessable_content
    assert field_errors["expires_in_days"].present?
  end

  test "no expiry is rejected" do
    assert_no_difference -> { ApiToken.count } do
      create_token(expires_in_days: nil)
    end

    assert_response :unprocessable_content
    assert field_errors["expires_in_days"].present?
  end

  test "a project the user does not belong to, or an archived one, is rejected" do
    archived = Project.create!(title: "Old", short_name: "OLD", owner: @user).tap(&:archive!)

    [ projects(:side), archived ].each do |project|
      assert_no_difference -> { ApiToken.count } do
        create_token(project_id: project.id)
      end

      assert_response :unprocessable_content
      assert_equal [ "Project is invalid" ], field_errors["project_id"]
    end
  end

  test "invalid name and access are rejected" do
    assert_no_difference -> { ApiToken.count } do
      create_token(name: "", access: "admin")
    end

    assert_response :unprocessable_content
    assert_equal %w[access name], field_errors.keys.sort
  end

  test "token limit: a user with 20 unexpired tokens cannot create another" do
    19.times { |n| @user.api_tokens.issue(project: projects(:goal), name: "T#{n}", access: "read", expires_in_days: 30).save! }
    assert_equal 20, @user.api_tokens.active.count

    assert_no_difference -> { ApiToken.count } do
      create_token
    end

    assert_response :unprocessable_content
    assert_equal [ "You can have at most 20 active API tokens. Revoke one to create another." ], field_errors["base"]
  end

  test "expired tokens are not listed and do not count toward the limit" do
    18.times { |n| @user.api_tokens.issue(project: projects(:goal), name: "T#{n}", access: "read", expires_in_days: 30).save! }
    expired = @user.api_tokens.issue(project: projects(:goal), name: "Expired", access: "read", expires_in_days: 1).tap(&:save!)
    expired.update_column(:expires_at, 1.minute.ago)

    get api_me_api_tokens_path
    assert_not_includes response.parsed_body.map { |token| token["id"] }, expired.id
    assert_equal 19, response.parsed_body.size

    create_token
    assert_response :created
  end

  test "wrong password: rejected, no token, and the attempt counts toward lockout" do
    assert_no_difference -> { ApiToken.count } do
      create_token(current_password: "not my password")
    end

    assert_response :unprocessable_content
    assert_equal [ "current_password" ], field_errors.keys
    assert_equal 1, @user.reload.failed_login_attempts
  end

  test "locked account: rejected with the same error as a wrong password, even with the correct one" do
    create_token(current_password: "not my password")
    wrong = response.parsed_body
    @user.update_columns(locked_until: 30.minutes.from_now)

    assert_no_difference -> { ApiToken.count } do
      create_token
    end

    assert_response :unprocessable_content
    assert_equal wrong, response.parsed_body
  end

  test "a correct password resets the failed-attempt count" do
    @user.update_columns(failed_login_attempts: 5)

    create_token

    assert_response :created
    assert_equal 0, @user.reload.failed_login_attempts
  end

  test "listing does not reveal values" do
    create_token
    value = response.parsed_body["token"]

    get api_me_api_tokens_path

    assert_response :success
    assert_not_includes response.body, value
    assert_not_includes response.body, "glnr_"
    entry = response.parsed_body.find { |token| token["name"] == "CI" }
    assert_equal value.last(4), entry["last_characters"]
    assert_equal %w[access created_at expires_at id last_characters last_used_at name project], entry.keys.sort
  end

  test "only the user's own tokens are listed" do
    get api_me_api_tokens_path

    assert_equal [ api_tokens(:one_goal_read_write).id ], response.parsed_body.map { |token| token["id"] }
  end

  test "revoke: the token stops working at once" do
    token = api_tokens(:one_goal_read_write)

    delete api_me_api_token_path(token)

    assert_response :no_content
    get api_project_board_path(projects(:goal)), headers: { "Authorization" => "Bearer glnr_one_goal_read_write" }
    assert_response :unauthorized
  end

  test "another user's token: 404, and it keeps working" do
    delete api_me_api_token_path(api_tokens(:two_goal_read))

    assert_response :not_found
    get api_project_board_path(projects(:goal)), headers: { "Authorization" => "Bearer glnr_two_goal_read" }
    assert_response :success
  end

  test "creation burst: the eleventh token within an hour gets 429 and is not created" do
    10.times do
      create_token
      assert_response :created
    end

    assert_no_difference -> { ApiToken.count } do
      create_token
    end
    assert_response :too_many_requests
  end
end
