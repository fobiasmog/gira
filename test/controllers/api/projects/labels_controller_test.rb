require "test_helper"

class Api::Projects::LabelsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
    @task = @project.tasks.create!(title: "t", creator: users(:one), status: statuses(:goal_todo))
  end

  test "create and list labels" do
    post api_project_labels_path(@project), params: { title: "bug" }, as: :json
    assert_response :created

    get api_project_labels_path(@project)
    assert_equal [ "bug" ], response.parsed_body.map { |l| l["title"] }
  end

  test "duplicate title, ignoring case" do
    @project.labels.create!(title: "Bug")

    post api_project_labels_path(@project), params: { title: "bug" }, as: :json

    assert_response :unprocessable_content
  end

  test "the same title is allowed in another project" do
    projects(:side).labels.create!(title: "bug")

    post api_project_labels_path(@project), params: { title: "bug" }, as: :json

    assert_response :created
  end

  test "title must be 1 to 30 characters" do
    post api_project_labels_path(@project), params: { title: "a" * 31 }, as: :json
    assert_response :unprocessable_content
  end

  test "replace label" do
    bug = @project.labels.create!(title: "bug")
    feature = @project.labels.create!(title: "feature")
    @task.update!(label: bug)

    put api_project_task_label_path(@project, @task), params: { label_id: feature.id }, as: :json

    assert_response :success
    assert_equal feature, @task.reload.label
  end

  test "label from another project is rejected and the label unchanged" do
    bug = @project.labels.create!(title: "bug")
    @task.update!(label: bug)
    foreign = projects(:side).labels.create!(title: "theirs")

    put api_project_task_label_path(@project, @task), params: { label_id: foreign.id }, as: :json

    assert_response :unprocessable_content
    assert_equal bug, @task.reload.label
  end

  test "remove label" do
    @task.update!(label: @project.labels.create!(title: "bug"))

    delete api_project_task_label_path(@project, @task)

    assert_nil @task.reload.label
  end
end
