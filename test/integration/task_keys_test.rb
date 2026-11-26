require "test_helper"

# Spec tasks, "Name a task by id or key in every task request";
# add-openspec-changes design.md, decision 8.
class TaskKeysTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @card = @project.tasks.create!(title: "Card", creator: users(:one), status: statuses(:goal_todo))
    @subtask = @project.tasks.create!(title: "Item", parent: @card, creator: users(:one))
    sign_in_as users(:one)
  end

  test "complete and reopen a subtask by key" do
    put api_project_task_completion_path(@project, @subtask.key)
    assert_response :success
    assert @subtask.reload.done?

    delete api_project_task_completion_path(@project, @subtask.key)
    assert_response :success
    assert_not @subtask.reload.done?
  end

  test "comment by key" do
    post api_project_task_comments_path(@project, @card.key), params: { body: "By key" }, as: :json
    assert_response :created

    get api_project_task_comments_path(@project, @card.key)
    assert_equal [ "By key" ], response.parsed_body.map { |comment| comment["body"] }
  end

  test "subtasks, placement, change and label by key" do
    post api_project_task_subtasks_path(@project, @card.key), params: { title: "Another" }, as: :json
    assert_response :created
    get api_project_task_subtasks_path(@project, @card.key)
    assert_equal [ "Item", "Another" ], response.parsed_body.map { |task| task["title"] }

    put api_project_task_placement_path(@project, @card.key), params: { status_id: statuses(:goal_work).id }, as: :json
    assert_response :success
    assert_equal statuses(:goal_work), @card.reload.status

    change = @project.project_changes.create!(name: "s1")
    put api_project_task_change_path(@project, @card.key), params: { change_id: change.id }, as: :json
    assert_response :success
    assert_equal change, @card.reload.change

    label = @project.labels.create!(title: "ci")
    put api_project_task_label_path(@project, @card.key), params: { label_id: label.id }, as: :json
    assert_response :success
    delete api_project_task_label_path(@project, @card.key)
    assert_response :success
    assert_nil @card.reload.label
  end

  test "a key is matched by its number, whatever its letters" do
    put api_project_task_completion_path(@project, "OLD-#{@subtask.number}")

    assert_response :success
    assert @subtask.reload.done?
  end

  test "ids still work" do
    put api_project_task_completion_path(@project, @subtask.id)

    assert_response :success
  end

  test "an unknown key, or a key of another project's numbering: 404 and nothing changes" do
    put api_project_task_placement_path(@project, "GOAL-9999"), params: { status_id: statuses(:goal_work).id }, as: :json
    assert_response :not_found

    other = projects(:side).tasks.create!(title: "Elsewhere", creator: users(:two), status: statuses(:side_todo))
    put api_project_task_completion_path(@project, "SIDE-#{other.number + 100}")
    assert_response :not_found
    assert_equal statuses(:goal_todo), @card.reload.status
  end

  test "a card's key on the completion of subtasks: 404" do
    put api_project_task_completion_path(@project, @card.key)

    assert_response :not_found
  end
end
