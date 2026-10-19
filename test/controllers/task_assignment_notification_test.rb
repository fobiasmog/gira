require "test_helper"

# Assignment emails (spec notifications, "Assignment email").
class TaskAssignmentNotificationTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @task = @project.tasks.create!(title: "Ship it", description: "secret plans", creator: users(:one), status: statuses(:goal_todo))
    @task.comments.create!(author: users(:one), body: "private remark")
    sign_in_as users(:one) # "Alice"
  end

  def assign(user_id, **extra)
    perform_enqueued_jobs do
      patch api_project_task_path(@project, @task.id), params: { assignee_id: user_id, **extra }, as: :json
    end
  end

  test "assign to a teammate: one email naming the assigner and the task key, with a link" do
    users(:two).update!(lang: "ru")

    assign users(:two).id

    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "two@example.com" ], mail.to
    assert_equal "User One назначает вам GOAL-1", mail.subject
    body = mail.text_part.decoded
    assert_includes body, "GOAL-1"
    assert_includes body, "http://example.com/app/projects/#{@project.id}/tasks/GOAL-1"
    assert_no_match(/secret plans|private remark/, body + mail.html_part.decoded)
  end

  test "self-assignment sends nothing" do
    assign users(:one).id

    assert_empty ActionMailer::Base.deliveries
  end

  test "an unchanged assignee sends nothing" do
    @task.update!(assignee: users(:two))

    assign users(:two).id, title: "Renamed"

    assert_empty ActionMailer::Base.deliveries
  end

  test "a rejected update sends nothing" do
    assign users(:two).id, title: ""

    assert_response :unprocessable_content
    assert_empty ActionMailer::Base.deliveries
  end

  test "assigning on creation notifies too" do
    perform_enqueued_jobs do
      post api_project_tasks_path(@project), params: { title: "New", assignee_id: users(:two).id }, as: :json
    end

    assert_equal [ "two@example.com" ], ActionMailer::Base.deliveries.sole.to
  end

  test "emails are queued, not sent during the request" do
    assert_enqueued_with(job: MailDeliveryJob) do
      patch api_project_task_path(@project, @task.id), params: { assignee_id: users(:two).id }, as: :json
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test "failed deliveries are retried" do
    assert_includes MailDeliveryJob.rescue_handlers.map(&:first), "Net::OpenTimeout"
  end
end
