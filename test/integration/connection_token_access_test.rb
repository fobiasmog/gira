require "test_helper"

# What a connection token reaches (spec api-tokens, "Connection tokens",
# "Token reach is limited to its project", "List and revoke tokens" and
# "Token lifetime and revocation"; add-mcp-oauth design.md, decision 8). two
# is a member of goal and side.
class ConnectionTokenAccessTest < ActionDispatch::IntegrationTest
  setup do
    @goal = projects(:goal)
    @side = projects(:side)
    @api_token, @access_token = create_connection_token(users(:two))
    @headers = { "Authorization" => "Bearer #{@api_token.value}" }
  end

  def project_ids
    get api_projects_path, headers: @headers
    assert_response :success
    response.parsed_body.map { |project| project["id"] }.sort
  end

  test "connection token project list: every non-archived project of the owner" do
    old = Project.create!(title: "Old", short_name: "OLD", owner: users(:two))
    old.archive!

    assert_equal [ @goal.id, @side.id ].sort, project_ids
  end

  test "a project joined later is reached" do
    joined = Project.create!(title: "Joined", short_name: "JOIN", owner: users(:one))
    joined.memberships.create!(user: users(:two))

    assert_includes project_ids, joined.id
  end

  test "connection token after leaving: 404 for that project, and the others keep working" do
    task = @side.tasks.create!(title: "Kept", creator: users(:two), status: @side.first_status)
    @goal.remove_member!(users(:two))

    get api_project_tasks_path(@goal), headers: @headers
    assert_response :not_found
    get api_project_task_path(@side, task), headers: @headers
    assert_response :success
    assert ApiToken.exists?(@api_token.id)
  end

  test "connection token outlives no project: archiving one leaves the token working for the others" do
    @goal.archive!

    assert ApiToken.exists?(@api_token.id)
    get api_project_tasks_path(@goal), headers: @headers
    assert_response :not_found
    get api_project_tasks_path(@side), headers: @headers
    assert_response :success
  end

  test "a read-write connection token writes in every project, as its owner" do
    [ @goal, @side ].each do |project|
      post api_project_tasks_path(project), params: { title: "From Claude" }, headers: @headers, as: :json
      assert_response :created
      assert_equal users(:two), project.tasks.find_by!(title: "From Claude").creator
    end
  end

  test "read-only connection: insufficient_scope for writes" do
    read_only, = create_connection_token(users(:two), scopes: "read")

    assert_no_difference -> { Task.count } do
      post api_project_tasks_path(@goal), params: { title: "Nope" }, headers: { "Authorization" => "Bearer #{read_only.value}" }, as: :json
    end
    assert_response :forbidden
    assert_equal "insufficient_scope", response.parsed_body.dig("error", "code")
    assert read_only.read?
  end

  test "endpoints closed to tokens stay closed" do
    get api_me_api_tokens_path, headers: @headers
    assert_response :forbidden
    patch api_project_path(@goal), params: { title: "Renamed" }, headers: @headers, as: :json
    assert_response :forbidden
  end

  test "a revoked access token ends its connection token at once" do
    @access_token.revoke

    get api_projects_path, headers: @headers
    assert_response :unauthorized
  end

  test "deleting the access token deletes its connection tokens" do
    @access_token.destroy!

    assert_not ApiToken.exists?(@api_token.id)
  end

  test "the connection token expires with its access token" do
    assert_in_delta @access_token.expires_at, @api_token.expires_at, 1
    travel 1.hour + 1.second

    get api_projects_path, headers: @headers
    assert_response :unauthorized
  end

  test "not a personal token: not listed, and not counted toward the limit of 20" do
    sign_in_as users(:two)
    get api_me_api_tokens_path

    assert_not_includes response.parsed_body.map { |token| token["id"] }, @api_token.id
    assert_equal users(:two).api_tokens.active.count, response.parsed_body.size

    (ApiToken::MAX_ACTIVE_PER_USER - users(:two).api_tokens.active.count).times do |n|
      ApiToken.issue(user: users(:two), project: @goal, name: "T#{n}", access: "read", expires_in_days: 30).save!
    end
    assert_equal ApiToken::MAX_ACTIVE_PER_USER + 1, ApiToken.where(user: users(:two)).active.count
  end

  test "connection token id: revoking it is a 404, and the connection keeps working" do
    sign_in_as users(:two)
    delete api_me_api_token_path(@api_token)

    assert_response :not_found
    assert ApiToken.exists?(@api_token.id)
    get api_projects_path, headers: @headers
    assert_response :success
  end

  test "a password change deletes connection tokens too" do
    users(:two).update!(password: "another long password")

    assert_not ApiToken.exists?(@api_token.id)

    get api_projects_path, headers: @headers
    assert_response :unauthorized
  end
end
