require_relative "support"
require "support/image_files"

# Error responses (spec api-documentation, "Error responses are verified";
# design.md, decision 3): one example per error kind, checked against the
# operation it hits, and the error responses every operation must list.
class OpenapiErrorsContract < OpenapiContractTest
  include ImageFiles

  RESPONSES = {
    "401" => "Unauthorized", "403" => "InsufficientScope", "404" => "NotFound",
    "422" => "ValidationFailed", "429" => "RateLimited"
  }.freeze
  FILE_RESPONSES = { "401" => "FileUnauthorized", "404" => "FileNotFound", "429" => "FileRateLimited" }.freeze
  # Operations for agents only, whose 403 is also agents_only.
  AGENTS_ONLY = %w[claimRequest reportContextFull].freeze

  def error_code
    response.parsed_body.dig("error", "code")
  end

  test "401 invalid_token for an unknown token" do
    get api_me_path, headers: bearer("glnr_unknown")

    assert_response :unauthorized
    assert_equal "invalid_token", error_code
  end

  test "401 invalid_token for an agent's token used where it was not issued for" do
    agent = create_agent(projects(:goal))

    get api_me_path, headers: bearer(issue_agent_token(agent, issuer: users(:two), channels: %w[mcp]))

    assert_response :unauthorized
    assert_equal "invalid_token", error_code
  end

  test "401 invalid_service_key for an agent's token sent with a service key that is not the MCP server's" do
    agent = create_agent(projects(:goal))
    headers = bearer(issue_agent_token(agent, issuer: users(:two), channels: %w[mcp])).merge(ApiTokenAuthentication::SERVICE_KEY_HEADER => "made-up")

    get api_me_path, headers: headers

    assert_response :unauthorized
    assert_equal "invalid_service_key", error_code
  end

  test "403 insufficient_scope for a write with a read-only token" do
    post api_project_tasks_path(projects(:goal)), params: { title: "Nope" }, headers: bearer("glnr_two_goal_read"), as: :json

    assert_response :forbidden
    assert_equal "insufficient_scope", error_code
  end

  test "403 agents_only for a person's token taking a request" do
    post claim_api_project_requests_path(projects(:goal)), headers: bearer("glnr_two_goal_read_write")

    assert_response :forbidden
    assert_equal "agents_only", error_code
  end

  test "404 not_found for another project of the token's owner" do
    get api_project_board_path(projects(:side)), headers: bearer("glnr_two_goal_read")

    assert_response :not_found
    assert_equal "not_found", error_code
  end

  test "422 validation_failed for a label without a title" do
    post api_project_labels_path(projects(:goal)), params: { title: "" }, headers: bearer("glnr_two_goal_read_write"), as: :json

    assert_response :unprocessable_content
    assert_equal "validation_failed", error_code
    assert response.parsed_body.dig("error", "fields", "title").present?
  end

  test "409 keys_missing for a re-import of an OpenSpec change without its marks" do
    text = "## 1. Model\n- [ ] 1.1 Add the table\n"
    Change::Import.new(project: projects(:goal), user: users(:two), name: "add-labels", artifacts: { "tasks" => text }).run!

    post api_project_openspec_changes_path(projects(:goal)), params: { name: "add-labels", artifacts: { tasks: text } }, headers: bearer("glnr_two_goal_read_write"), as: :json

    assert_response :conflict
    assert_equal "keys_missing", error_code
    assert_match(/goalner:GOAL-\d+/, response.parsed_body["tasks_text"])
  end

  test "422 validation_failed for a change name that an open change has" do
    projects(:goal).project_changes.create!(name: "add-labels")

    post api_project_changes_path(projects(:goal)), params: { name: "add-labels" }, headers: bearer("glnr_two_goal_read_write"), as: :json

    assert_response :unprocessable_content
    assert_equal "validation_failed", error_code
    assert response.parsed_body.dig("error", "fields", "name").present?
  end

  test "404 not_found for the board of an archived change" do
    projects(:goal).project_changes.create!(name: "add-labels").archive!

    get api_project_board_path(projects(:goal), change_id: "add-labels"), headers: bearer("glnr_two_goal_read")

    assert_response :not_found
    assert_equal "not_found", error_code
  end

  test "422 validation_failed for moving a card of tasks.md to another change" do
    change = Change::Import.new(project: projects(:goal), user: users(:two), name: "add-labels", artifacts: { "tasks" => "## 1. A\n- [ ] 1.1 B\n" }).run!.change

    put api_project_task_change_path(projects(:goal), change.tasks.roots.first), params: { change_id: nil }, headers: bearer("glnr_two_goal_read_write"), as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "change").present?
  end

  test "422 validation_failed for an OpenSpec text with a foreign mark, naming its line" do
    post api_project_openspec_changes_path(projects(:goal)), params: { name: "add-labels", artifacts: { tasks: "## 1. A\n- [ ] 1.1 B <!-- goalner:GOAL-9999 -->\n" } },
      headers: bearer("glnr_two_goal_read_write"), as: :json

    assert_response :unprocessable_content
    assert_equal [ "Tasks line 2: the mark names no task of this project" ], response.parsed_body.dig("error", "fields", "tasks")
  end

  test "429 rate_limited for the 301st request in a minute" do
    300.times { get api_me_path, headers: bearer("glnr_two_goal_read") }

    get api_me_path, headers: bearer("glnr_two_goal_read")

    assert_response :too_many_requests
    assert_equal "rate_limited", error_code
  end

  test "file downloads: a bodiless 401, and the HTML 404 page" do
    comment = projects(:side).tasks.create!(title: "t", creator: users(:two), status: statuses(:side_todo)).comments.new(author: users(:two), body: "file")
    comment.attach_uploads([ image_upload(format: "png") ])
    comment.save!
    url = file_path(comment.attachments.first.blob.signed_id)

    get url, headers: bearer("glnr_unknown")
    assert_response :unauthorized
    assert_empty response.body

    get url, headers: bearer("glnr_two_goal_read")
    assert_response :not_found
    assert_equal "text/html", response.media_type
  end

  test "every operation lists the error responses it can give" do
    problems = OpenapiContractTest.operations.flat_map do |operation|
      listed = operation.definition.fetch("responses")
      expected = %w[401 429]
      expected << "403" unless operation.method == "GET"
      expected << "404" if operation.path.include?("{")
      expected << "422" if operation.definition["requestBody"]
      shared = operation.path.start_with?("/files/") ? FILE_RESPONSES : RESPONSES
      shared = shared.merge("403" => "AgentsOnly") if AGENTS_ONLY.include?(operation.id)

      expected.filter_map do |status|
        reference = listed.dig(status, "$ref")
        if reference.nil?
          "#{operation} lists no #{status} response"
        elsif reference != "#/components/responses/#{shared.fetch(status)}"
          "#{operation} answers #{status} with #{reference}, not #{shared.fetch(status)}"
        end
      end
    end

    assert_empty problems
  end
end
