require "test_helper"
require "support/forgery_protected_integration_test"
require "support/route_table"

# Authentication by API token (spec api-tokens, "Authenticate API requests with
# a token"; spec security-baseline, "Cross-site request forgery protection").
# CSRF protection is on, as in production. Fixture token values are "glnr_"
# followed by the fixture name; two is a member of goal and side.
class ApiTokenAuthenticationTest < ForgeryProtectedIntegrationTest
  setup { @project = projects(:goal) }

  def bearer(value)
    { "Authorization" => "Bearer #{value}" }
  end

  def csrf_token
    get new_session_path
    css_select("meta[name=csrf-token]").first["content"]
  end

  def error_code
    response.parsed_body.dig("error", "code")
  end

  test "write without a CSRF token: a read-write token creates a task, attributed to its owner" do
    assert_difference -> { @project.tasks.count }, 1 do
      post api_project_tasks_path(@project), params: { title: "From CI" }, headers: bearer("glnr_two_goal_read_write"), as: :json
    end

    assert_response :created
    assert_equal users(:two).id, response.parsed_body.dig("creator", "id")
  end

  test "invalid token with a valid session cookie: 401, and the session is not used" do
    sign_in_as users(:one)

    get api_me_path, headers: bearer("glnr_unknown")

    assert_response :unauthorized
    assert_equal "invalid_token", error_code
  end

  test "token request with a session cookie: an invalid token cannot change data through the session" do
    sign_in_as users(:one)

    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(@project), params: { title: "Forged" }, headers: bearer("glnr_unknown"), as: :json
    end

    assert_response :unauthorized
  end

  test "a malformed Bearer header is token mode too" do
    sign_in_as users(:one)

    [ "Bearer", "Bearer ", "bearer a b", "Bearer glnr_two_goal_read_write extra" ].each do |header|
      get api_me_path, headers: { "Authorization" => header }
      assert_response :unauthorized, header
    end
  end

  test "expired token: 401 with the JSON error envelope" do
    get api_project_tasks_path(@project), headers: bearer("glnr_two_goal_expired")

    assert_response :unauthorized
    assert_equal({ "code" => "invalid_token", "message" => Api::BaseController::MESSAGES[:invalid_token] }, response.parsed_body["error"])
  end

  test "revoked token: 401" do
    api_tokens(:two_goal_read_write).destroy!

    get api_project_tasks_path(@project), headers: bearer("glnr_two_goal_read_write")

    assert_response :unauthorized
  end

  test "a token in the query string or the body does not authenticate" do
    get api_project_tasks_path(@project, token: "glnr_two_goal_read_write", access_token: "glnr_two_goal_read_write")
    assert_response :unauthorized

    post api_project_tasks_path(@project), params: { title: "T", token: "glnr_two_goal_read_write" }, as: :json
    assert_response :unprocessable_content, "a session-mode write without CSRF token is refused first"
  end

  test "web client unchanged: session cookie and CSRF token, no Authorization header" do
    sign_in_as users(:one)

    post api_project_tasks_path(@project), params: { title: "From the browser" }, headers: { "X-CSRF-Token" => csrf_token }, as: :json

    assert_response :created
    assert_equal users(:one).id, response.parsed_body.dig("creator", "id")
  end

  test "an Authorization: Basic header leaves the request to the session and its CSRF check" do
    sign_in_as users(:one)
    basic = { "Authorization" => ActionController::HttpAuthentication::Basic.encode_credentials("staging", "secret") }

    post api_project_tasks_path(@project), params: { title: "Behind basic auth" }, headers: basic.merge("X-CSRF-Token" => csrf_token), as: :json
    assert_response :created
    assert_equal users(:one).id, response.parsed_body.dig("creator", "id")

    post api_project_tasks_path(@project), params: { title: "Forged" }, headers: basic, as: :json
    assert_response :unprocessable_content
  end

  test "an unknown API path with a valid token answers 404" do
    get "/api/nothing/here", headers: bearer("glnr_two_goal_read_write")

    assert_response :not_found
    assert_equal "not_found", error_code
  end

  test "a session-only action refuses a token with 403" do
    get api_teammates_path, headers: bearer("glnr_two_goal_read_write")

    assert_response :forbidden
    assert_equal "token_not_allowed", error_code
  end

  test "using a token records its last use" do
    token = api_tokens(:two_goal_read)
    assert_nil token.last_used_at

    freeze_time do
      get api_project_board_path(@project), headers: bearer("glnr_two_goal_read")
      assert_equal Time.current, token.reload.last_used_at
    end
  end

  # Spec api-tokens, "Token rate limits"

  test "request burst: the 301st request with one token within a minute gets 429 and has no effect" do
    300.times do
      get api_project_board_path(@project), headers: bearer("glnr_two_goal_read_write")
      assert_response :success
    end

    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(@project), params: { title: "One too many" }, headers: bearer("glnr_two_goal_read_write"), as: :json
    end
    assert_response :too_many_requests
    assert_equal "rate_limited", error_code

    get api_project_board_path(@project), headers: bearer("glnr_one_goal_read_write")
    assert_response :success, "another token is not affected"

    travel 1.minute + 1.second
    get api_project_board_path(@project), headers: bearer("glnr_two_goal_read_write")
    assert_response :success, "the limit resets after a minute"
  end

  test "session requests are not limited per token" do
    sign_in_as users(:one)

    301.times { get api_project_board_path(@project) }

    assert_response :success
  end

  # The allowlist (design.md, decision 4)

  # Every controller#action opened to API tokens. Opening another one must
  # change this list, so that it is reviewed.
  OPENED_TO_TOKENS = %w[
    api/base#route_not_found
    api/comments#destroy
    api/comments#update
    api/me#show
    api/projects#index
    api/projects#show
    api/projects/boards#show
    api/projects/labels#create
    api/projects/labels#index
    api/projects/members#index
    api/projects/milestones#create
    api/projects/milestones#destroy
    api/projects/milestones#index
    api/projects/milestones#show
    api/projects/milestones/recoveries#create
    api/projects/sprints#create
    api/projects/sprints#index
    api/projects/sprints/activations#create
    api/projects/sprints/archivals#create
    api/projects/sprints/tasks#index
    api/projects/tasks#create
    api/projects/tasks#destroy
    api/projects/tasks#index
    api/projects/tasks#show
    api/projects/tasks#update
    api/projects/tasks/comments#create
    api/projects/tasks/comments#index
    api/projects/tasks/completions#destroy
    api/projects/tasks/completions#update
    api/projects/tasks/labels#destroy
    api/projects/tasks/labels#update
    api/projects/tasks/placements#update
    api/projects/tasks/sprints#update
    api/projects/tasks/subtasks#create
    api/projects/tasks/subtasks#index
    files#show
  ].freeze

  def opened_to_tokens?(route)
    controller = "#{route.defaults[:controller]}_controller".camelize.constantize
    controller.respond_to?(:token_actions) && controller.token_actions.include?(route.defaults[:action].to_s)
  end

  def row_counts
    connection = ActiveRecord::Base.connection
    connection.tables.sort.to_h { |table| [ table, connection.select_value("SELECT COUNT(*) FROM #{connection.quote_table_name(table)}") ] }
  end

  test "route table: every API action not opened to tokens refuses a read-write token with 403 and changes nothing" do
    counts = row_counts
    checked = 0

    RouteTable.routes.each do |route|
      path = RouteTable.sample_path(route)
      next unless path.start_with?("/api/") && !opened_to_tokens?(route)

      RouteTable.verbs(route).each do |verb|
        process verb.downcase.to_sym, path, params: { title: "token" }, headers: bearer("glnr_two_goal_read_write"), as: :json

        assert_equal [ 403, "token_not_allowed" ], [ response.status, error_code ],
          "#{verb} #{path} (#{RouteTable.endpoint(route)}) answered #{response.status} to a token"
        checked += 1
      end
    end

    assert_operator checked, :>, 0
    assert_equal counts, row_counts
  end

  test "snapshot: the actions opened to tokens are exactly the reviewed list" do
    opened = RouteTable.routes.select { |route| opened_to_tokens?(route) }.map { |route| RouteTable.endpoint(route) }.uniq.sort

    assert_equal OPENED_TO_TOKENS, opened
  end
end
