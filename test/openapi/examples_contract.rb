require_relative "support"
require "support/image_files"

# One example per documented operation (design.md, decision 3): the documented
# success request, made with an API token. Each test expects the operation's
# documented success status, and the hook checks the response against the
# document. two is a member of goal and owns its read-write token.
class OpenapiExamplesContract < OpenapiContractTest
  include ImageFiles

  TOKEN = "glnr_two_goal_read_write"
  OPENSPEC_TASKS = "## 1. Model\n\n- [x] 1.1 Add the table\n- [ ] 1.2 Add the model\n  - with validations\n\n## 2. API\n\n- [ ] 2.1 Add the routes\n"

  EXAMPLES = {
    "showProfile" => -> { get api_me_path, headers: token },
    "listProjects" => -> { get api_projects_path, headers: token },
    "showProject" => -> { get api_project_path(@project), headers: token },
    "showBoard" => -> { get api_project_board_path(@project), headers: token },
    "listColumns" => -> { get api_project_statuses_path(@project), headers: token },
    "listMembers" => -> { get api_project_members_path(@project), headers: token },

    "listTasks" => -> { get api_project_tasks_path(@project, view: "board", change_id: "add-labels"), headers: token },
    "createTask" => -> do
      post api_project_tasks_path(@project), params: { title: "From the API", important: true, assignee_id: users(:two).id, change_id: @change.id }, headers: token, as: :json
    end,
    "showTask" => -> { get api_project_task_path(@project, @task.key), headers: token },
    "updateTask" => -> { patch api_project_task_path(@project, @task), params: { title: "Renamed", deadline: 3.days.from_now.iso8601 }, headers: token, as: :json },
    "archiveTask" => -> { delete api_project_task_path(@project, @task), headers: token },
    "placeTask" => -> { put api_project_task_placement_path(@project, @task), params: { status_id: statuses(:goal_work).id, position: 0 }, headers: token, as: :json },
    "setTaskLabel" => -> { put api_project_task_label_path(@project, @task), params: { label_id: @label.id }, headers: token, as: :json },
    "removeTaskLabel" => -> { delete api_project_task_label_path(@project, @task), headers: token },
    "setTaskChange" => -> { put api_project_task_change_path(@project, @task), params: { change_id: @other_change.id }, headers: token, as: :json },
    "listSubtasks" => -> { get api_project_task_subtasks_path(@project, @task), headers: token },
    "createSubtask" => -> { post api_project_task_subtasks_path(@project, @task), params: { title: "A step" }, headers: token, as: :json },
    "completeSubtask" => -> { put api_project_task_completion_path(@project, @subtask), headers: token },
    "reopenSubtask" => -> { delete api_project_task_completion_path(@project, @subtask), headers: token },

    "listComments" => -> { get api_project_task_comments_path(@project, @task), headers: token },
    "createComment" => -> do
      post api_project_task_comments_path(@project, @task), params: { body: "See the screenshot", attachments: [ image_upload(format: "png") ] }, headers: token
      assert_equal 1, response.parsed_body["attachments"].size, "the multipart example uploads an attachment"
    end,
    "updateComment" => -> { patch api_comment_path(@comment), params: { body: "Edited **from the API**" }, headers: token, as: :json },
    "deleteComment" => -> { delete api_comment_path(@comment), headers: token },

    "listLabels" => -> { get api_project_labels_path(@project), headers: token },
    "createLabel" => -> { post api_project_labels_path(@project), params: { title: "frontend" }, headers: token, as: :json },

    "listChanges" => -> { get api_project_changes_path(@project, view: "archived"), headers: token },
    "createChange" => -> { post api_project_changes_path(@project), params: { name: "fix-login" }, headers: token, as: :json },
    "showChange" => -> do
      Change::Import.new(project: @project, user: users(:two), name: "add-labels", artifacts: { "tasks" => OPENSPEC_TASKS }).run!
      get api_project_change_path(@project, "add-labels"), headers: token
    end,
    "archiveChange" => -> { post api_project_change_archival_path(@project, @change.id), headers: token },
    "listChangeTasks" => -> { get api_project_change_tasks_path(@project, "add-labels"), headers: token },

    "importOpenspecChange" => -> do
      post api_project_openspec_changes_path(@project), params: { name: "export-csv", artifacts: { tasks: OPENSPEC_TASKS } }, headers: token, as: :json
    end,

    "downloadFile" => -> { get file_path(@attachment.signed_id), headers: token },
    "downloadFilePreview" => -> { get file_path(@attachment.signed_id, variant: "preview"), headers: token }
  }.freeze

  setup do
    @project = projects(:goal)
    users(:two).send(:attach_default_avatar)
    @label = @project.labels.create!(title: "backend")
    @change = @project.project_changes.create!(name: "add-labels")
    @other_change = @project.project_changes.create!(name: "fix-login-flow")
    @project.project_changes.create!(name: "dropped").archive!
    @task = @project.tasks.create!(title: "Documented", description: "**Markdown**", creator: users(:two), assignee: users(:one),
      status: statuses(:goal_todo), label: @label, change: @change, deadline: 2.days.from_now, important: true)
    @subtask = @project.tasks.create!(title: "Step one", creator: users(:two), parent: @task)
    @task.comments.create!(author: users(:one), body: "A comment")
    @comment = @task.comments.create!(author: users(:two), body: "Mine")
    with_file = @task.comments.new(author: users(:one), body: "A screenshot")
    with_file.attach_uploads([ image_upload(format: "png") ])
    with_file.save!
    @attachment = with_file.attachments.first.blob
  end

  # The view agents find their work with (spec tasks, "Tasks assigned to the
  # requester"), made with an agent's token.
  test "listTasks, assigned to the token's owner" do
    agent = create_agent(@project, name: "Fish")
    @project.tasks.create!(title: "Fish's task", creator: users(:two), assignee: agent.user, status: statuses(:goal_work))
    @project.tasks.create!(title: "Fish's subtask", creator: agent.user, assignee: agent.user, parent: @task)

    get api_project_tasks_path(@project, view: "assigned"), headers: bearer(issue_agent_token(agent, issuer: users(:two), channels: %w[api]))

    assert_response :success
    assert_equal [ "Fish's subtask", "Fish's task" ], response.parsed_body.map { |card| card["title"] }
  end

  test "showProfile and listMembers with an agent's token" do
    agent = create_agent(@project, name: "Fish")
    headers = bearer(issue_agent_token(agent, issuer: users(:two), access: :read))

    get api_me_path, headers: headers
    assert_response :success
    assert response.parsed_body["agent"]

    get api_project_members_path(@project), headers: headers
    assert_response :success
    assert_includes response.parsed_body.map { |member| member.values_at("name", "agent") }, [ "Fish", true ]
  end

  # Task requests take keys as well as ids (spec tasks, "Name a task by id
  # or key in every task request").
  test "completeSubtask and placeTask by key" do
    put api_project_task_completion_path(@project, @subtask.key), headers: token
    assert_response :success

    put api_project_task_placement_path(@project, @task.key), params: { status_id: statuses(:goal_work).id }, headers: token, as: :json
    assert_response :success
  end

  test "importOpenspecChange again: 200" do
    post api_project_openspec_changes_path(@project), params: { name: "export-csv", artifacts: { tasks: OPENSPEC_TASKS } }, headers: token, as: :json
    post api_project_openspec_changes_path(@project), params: { name: "export-csv", artifacts: { tasks: response.parsed_body["tasks_text"] } }, headers: token, as: :json

    assert_response :ok
  end

  test "importOpenspecChange into a change created first: 200" do
    post api_project_openspec_changes_path(@project), params: { name: "add-labels", artifacts: { tasks: OPENSPEC_TASKS } }, headers: token, as: :json

    assert_response :ok
    assert_equal [ [ "Documented", false ], [ "add-labels: 1. Model", true ], [ "add-labels: 2. API", true ] ],
      response.parsed_body["cards"].map { |card| card.values_at("title", "in_tasks_md") }.sort
  end

  test "showBoard of a change, by name, and showChange of a change never imported" do
    get api_project_board_path(@project, change_id: "add-labels"), headers: token
    assert_response :success
    assert_equal [ @task.id ], response.parsed_body["tasks"].map { |card| card["id"] }

    get api_project_change_path(@project, @other_change.id), headers: token
    assert_response :success
    assert_nil response.parsed_body["tasks_text"]
  end

  test "setTaskChange to null, and listChanges of open changes" do
    put api_project_task_change_path(@project, @task.key), params: { change_id: nil }, headers: token, as: :json
    assert_response :success

    get api_project_changes_path(@project), headers: token
    assert_equal %w[fix-login-flow add-labels], response.parsed_body.map { |change| change["name"] }
  end

  test "every documented operation has an example" do
    assert_empty OpenapiContractTest.operations.map(&:id) - EXAMPLES.keys, "documented operations without an example"
  end

  EXAMPLES.each do |operation_id, example|
    test operation_id do
      operation = OpenapiContractTest.operations.find { |candidate| candidate.id == operation_id }
      assert operation, "#{operation_id} is not in the document"

      instance_exec(&example)

      assert_equal operation.success_status, response.status, "#{operation}: #{response.body.first(500)}"
    end
  end

  private
    def token
      bearer(TOKEN)
    end
end
