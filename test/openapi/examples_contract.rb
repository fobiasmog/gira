require_relative "support"
require "support/image_files"

# One example per documented operation (design.md, decision 3): the documented
# success request, made with an API token. Each test expects the operation's
# documented success status, and the hook checks the response against the
# document. two is a member of goal and owns its read-write token.
class OpenapiExamplesContract < OpenapiContractTest
  include ImageFiles

  TOKEN = "glnr_two_goal_read_write"

  EXAMPLES = {
    "showProfile" => -> { get api_me_path, headers: token },
    "listProjects" => -> { get api_projects_path, headers: token },
    "showProject" => -> { get api_project_path(@project), headers: token },
    "showBoard" => -> { get api_project_board_path(@project), headers: token },
    "listColumns" => -> { get api_project_statuses_path(@project), headers: token },
    "listMembers" => -> { get api_project_members_path(@project), headers: token },

    "listTasks" => -> { get api_project_tasks_path(@project, view: "backlog"), headers: token },
    "createTask" => -> { post api_project_tasks_path(@project), params: { title: "From the API", important: true, assignee_id: users(:two).id }, headers: token, as: :json },
    "showTask" => -> { get api_project_task_path(@project, @task.key), headers: token },
    "updateTask" => -> { patch api_project_task_path(@project, @task), params: { title: "Renamed", deadline: 3.days.from_now.iso8601, milestone_id: @milestone.id }, headers: token, as: :json },
    "archiveTask" => -> { delete api_project_task_path(@project, @task), headers: token },
    "placeTask" => -> { put api_project_task_placement_path(@project, @task), params: { status_id: statuses(:goal_work).id, position: 0 }, headers: token, as: :json },
    "setTaskLabel" => -> { put api_project_task_label_path(@project, @task), params: { label_id: @label.id }, headers: token, as: :json },
    "removeTaskLabel" => -> { delete api_project_task_label_path(@project, @task), headers: token },
    "setTaskSprint" => -> { put api_project_task_sprint_path(@project, @task), params: { sprint_id: @sprint.id }, headers: token, as: :json },
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

    "listMilestones" => -> { get api_project_milestones_path(@project, view: "deleted"), headers: token },
    "createMilestone" => -> { post api_project_milestones_path(@project), params: { title: "Beta" }, headers: token, as: :json },
    "showMilestone" => -> { get api_project_milestone_path(@project, @milestone), headers: token },
    "deleteMilestone" => -> { delete api_project_milestone_path(@project, @milestone), headers: token },
    "recoverMilestone" => -> { post api_project_milestone_recovery_path(@project, @deleted_milestone), headers: token },

    "listSprints" => -> { get api_project_sprints_path(@project, view: "available"), headers: token },
    "createSprint" => -> do
      post api_project_sprints_path(@project), params: { title: "Sprint 3", starts_on: 2.weeks.from_now.to_date, ends_on: 3.weeks.from_now.to_date, activate: true }, headers: token, as: :json
    end,
    "activateSprint" => -> { post api_project_sprint_activation_path(@project, @planned), headers: token },
    "archiveSprint" => -> { post api_project_sprint_archival_path(@project, @sprint), params: { carry_to_sprint_id: @planned.id }, headers: token, as: :json },
    "listSprintTasks" => -> { get api_project_sprint_tasks_path(@project, @sprint), headers: token },

    "downloadFile" => -> { get file_path(@attachment.signed_id), headers: token },
    "downloadFilePreview" => -> { get file_path(@attachment.signed_id, variant: "preview"), headers: token }
  }.freeze

  setup do
    @project = projects(:goal)
    users(:two).send(:attach_default_avatar)
    @label = @project.labels.create!(title: "backend")
    @milestone = @project.milestones.create!(title: "Release")
    @sprint = @project.sprints.create!(title: "Sprint 1", starts_on: Date.current, ends_on: 1.week.from_now, active: true)
    @planned = @project.sprints.create!(title: "Sprint 2", starts_on: 1.week.from_now, ends_on: 2.weeks.from_now)
    @deleted_milestone = @project.milestones.create!(title: "Dropped").tap(&:delete!)
    @task = @project.tasks.create!(title: "Documented", description: "**Markdown**", creator: users(:two), assignee: users(:one),
      status: statuses(:goal_todo), label: @label, sprint: @sprint, milestone: @milestone, deadline: 2.days.from_now, important: true)
    @subtask = @project.tasks.create!(title: "Step one", creator: users(:two), parent: @task)
    @task.comments.create!(author: users(:one), body: "A comment")
    @comment = @task.comments.create!(author: users(:two), body: "Mine")
    with_file = @task.comments.new(author: users(:one), body: "A screenshot")
    with_file.attach_uploads([ image_upload(format: "png") ])
    with_file.save!
    @attachment = with_file.attachments.first.blob
    @sprint.carry_over_to(@planned)
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
