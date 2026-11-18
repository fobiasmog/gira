require "test_helper"

# Spec change-requests, "Ask for a step" and "Requests for the steps of a
# change"; add-change-requests design.md, decision 6.
class Api::Projects::Changes::RequestsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @change = @project.project_changes.create!(name: "export-csv")
    @fish = create_agent(@project, name: "Fish").user
    sign_in_as users(:one)
  end

  def ask(kind, ref: "export-csv", **params)
    post api_project_change_requests_path(@project, ref), params: { kind:, **params }, as: :json
  end

  def fields = response.parsed_body.dig("error", "fields")

  test "start exploring: 201 with a waiting explore request asked for by the member, and the change still in Idea" do
    ask "explore"

    assert_response :created
    body = response.parsed_body
    assert_equal [ "explore", "waiting", "User One", nil, nil ], [ body["kind"], body["state"], body.dig("requested_by", "name"), body["taken_by"], body["taken_at"] ]
    assert_equal({ "id" => @change.id, "name" => "export-csv", "phase" => "idea" }, body["change"])
    assert body["created_at"].present?
    assert_equal "idea", @change.reload.phase
  end

  test "with a comment: posted by the member, and the change's only open request is the waiting implement request" do
    @change.update!(phase: "proposed")

    ask "implement", comment: "Start with the API."

    assert_response :created
    assert_equal [ [ "Start with the API.", users(:one) ] ], @change.comments.map { |comment| [ comment.body, comment.author ] }
    assert_equal [ [ "implement", "waiting" ] ], @change.requests.unfinished.pluck(:kind, :state)
  end

  test "replacing a reply request that is still waiting" do
    @change.update!(phase: "exploring")
    post api_project_change_comments_path(@project, "export-csv"), params: { body: "No archived tasks." }, as: :json
    reply = @change.requests.sole

    ask "implement"

    assert_response :created
    assert_equal "cancelled", reply.reload.state
    assert_equal "implement", @change.reload.open_request.kind
  end

  test "one open request, or a taken request: 422, and the open request stays as it is" do
    ask "explore"
    ChangeRequest.take!(project: @project, agent: @fish)

    ask "propose"

    assert_response :unprocessable_content
    assert fields["base"].present?
    assert_equal [ [ "explore", "taken" ] ], @change.requests.pluck(:kind, :state)
  end

  test "archived change: 422, and no request is created" do
    @change.archive!

    ask "explore", ref: @change.id

    assert_response :unprocessable_content
    assert fields["base"].present?
    assert_empty @change.requests
  end

  test "reply asked for directly, an unknown kind, or none: 422 on the kind" do
    @change.update!(phase: "exploring")

    [ { kind: "reply" }, { kind: "deploy" }, { kind: nil } ].each do |params|
      post api_project_change_requests_path(@project, "export-csv"), params:, as: :json
      assert_response :unprocessable_content
      assert fields["kind"].present?, params.inspect
    end
    assert_empty @change.requests
  end

  test "an empty, too long or non-text comment: 422 on the comment, nothing created" do
    [ "", "a" * 10_001, { text: "x" } ].each do |comment|
      ask "explore", comment: comment
      assert_response :unprocessable_content
      assert fields["comment"].present?, comment.inspect
    end
    assert_empty @change.requests
    assert_empty @change.comments
  end

  test "a change of another project: 404" do
    foreign = projects(:side).project_changes.create!(name: "theirs")

    post api_project_change_requests_path(projects(:side), foreign.id), params: { kind: "explore" }, as: :json

    assert_response :not_found
    assert_empty foreign.requests
  end
end
