require "application_system_test_case"

# Spec web-client, "Screens" (task details), and comments.
class TaskPageTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @user = users(:one)
    @task = @project.tasks.create!(title: "Plan the release", creator: @user, status: statuses(:goal_todo))
    sign_in @user.email_address, "correct horse battery"
  end

  def visit_task(task = @task)
    visit "/app/projects/#{@project.id}/tasks/#{task.key}"
    assert_selector "h1", text: task.title
  end

  def choose(field, option)
    find("button[aria-label^='Change #{field}:']").click
    click_button option
  end

  def eventually(&condition)
    Timeout.timeout(5) { sleep 0.1 until condition.call }
  rescue Timeout::Error
    flunk "condition not met"
  end

  def temp_file(name, content)
    Rails.root.join("tmp", name).tap { |path| File.write(path, content) }.to_s
  end

  test "edit the title, status, assignee, deadline and importance" do
    visit_task

    click_button "Edit title"
    find_field("Task title").send_keys([ :control, "a" ], "Plan the big release", :enter)
    assert_selector "h1", text: "Plan the big release"
    eventually { @task.reload.title == "Plan the big release" }

    choose "Status", "Work"
    eventually { @task.reload.status == statuses(:goal_work) }
    find("button[aria-label^='Change Status:']").click
    assert_button "Done"
    assert_no_button "Backlog" # every task is in a column; the backlog is a matter of sprints
    click_button "To Do"
    eventually { @task.reload.status == statuses(:goal_todo) }

    choose "Assignee", "User Two"
    assert_selector "button[aria-label='Change Assignee: User Two']"
    eventually { @task.reload.assignee == users(:two) }

    deadline = find_field("Deadline")
    expected = evaluate_script("new Date('2026-11-01T10:30').toISOString()")
    execute_script("arguments[0].value = '2026-11-01T10:30'; arguments[0].dispatchEvent(new Event('change', { bubbles: true }))", deadline)
    eventually { @task.reload.deadline == Time.iso8601(expected) }
    click_button "Remove deadline"
    eventually { @task.reload.deadline.nil? }

    click_button "Important"
    assert_selector "button[aria-pressed=true]", text: "Important"
    eventually { @task.reload.important }
  end

  test "edit the milestone, label and sprint" do
    milestone = @project.milestones.create!(title: "Version 2")
    sprint = @project.sprints.create!(title: "Sprint 7", starts_on: Date.current, ends_on: 2.weeks.from_now.to_date)
    @project.labels.create!(title: "Backend")
    visit_task

    choose "Milestone", "Version 2"
    eventually { @task.reload.milestone == milestone }

    choose "Label", "Backend"
    eventually { @task.reload.label&.title == "Backend" }
    find("button[aria-label^='Change Label:']").click
    fill_in "New label", with: "Frontend"
    find_field("New label").send_keys(:enter)
    eventually { @task.reload.label&.title == "Frontend" }
    choose "Label", "No label"
    eventually { @task.reload.label.nil? }

    choose "Sprint", "Sprint 7"
    eventually { @task.reload.sprint == sprint }
    choose "Sprint", "No sprint"
    eventually { @task.reload.sprint.nil? }
  end

  test "add and complete subtasks" do
    visit_task

    fill_in "New subtask", with: "Write release notes"
    find_field("New subtask").send_keys(:enter)
    assert_link "Write release notes"
    subtask = @task.subtasks.reload.first
    assert_equal "Write release notes", subtask.title

    check "#{subtask.key} done"
    eventually { subtask.reload.status&.done? }

    click_link "Write release notes"
    assert_selector "h1", text: "Write release notes"
    assert_checked_field "Mark as complete"
  end

  # Spec web-client, "Subtask progress on the task page".
  test "partly done subtasks show their progress, which follows completion" do
    subtasks = 5.times.map do |i|
      @project.tasks.create!(title: "Step #{i + 1}", creator: @user, parent: @task, status: statuses(i < 3 ? :goal_done : :goal_todo))
    end
    visit_task

    within("section[aria-labelledby=task-subtasks]") do
      assert_text "3 of 5 done"
      assert_selector "[role=progressbar][aria-valuenow='3'][aria-valuemax='5']"

      check "#{subtasks[3].key} done"
      assert_text "4 of 5 done"
      assert_selector "[role=progressbar][aria-valuenow='4'][aria-valuemax='5']"
    end
    eventually { subtasks[3].reload.done? }
  end

  test "a task without subtasks shows no subtask progress" do
    visit_task

    within("section[aria-labelledby=task-subtasks]") do
      assert_field "New subtask"
      assert_no_selector "[role=progressbar]"
      assert_no_text "done"
    end
  end

  test "the comment heading counts the comments" do
    @task.comments.create!(author: users(:two), body: "First")
    @task.comments.create!(author: users(:two), body: "Second")
    visit_task

    within("#task-comments") { assert_selector ".badge", text: "2" }
  end

  test "post a comment with an attachment, edit it and delete it" do
    visit_task

    fill_in "Comment", with: "See the **plan** attached"
    attach_file "Attach files", temp_file("plan.txt", "step one\nstep two\n"), make_visible: true
    assert_text "plan.txt"
    click_button "Post comment"

    within(".comment") do
      assert_selector "strong", text: "plan"
      assert_link "plan.txt"
    end
    comment = @task.comments.reload.first
    assert_equal [ "plan.txt" ], comment.attachments.map { |a| a.filename.to_s }

    within(".comment") do
      click_button "Comment actions"
      click_button "Edit comment"
    end
    find(".comment textarea").send_keys([ :control, "a" ], "Updated plan")
    within(".comment") { click_button "Save" }
    within(".comment") { assert_text "Updated plan" }
    eventually { comment.reload.body == "Updated plan" }

    within(".comment") do
      click_button "Comment actions"
      click_button "Delete comment"
    end
    within("dialog[open]") { click_button "Delete" }
    assert_text "No comments yet"
    eventually { comment.reload.deleted_at.present? }
  end

  test "attachments of a disallowed type are refused before uploading" do
    visit_task

    fill_in "Comment", with: "Here is a program"
    attach_file "Attach files", temp_file("setup.exe", "MZ"), make_visible: true

    assert_text "setup.exe is not an allowed file type."
    assert_button "Post comment", disabled: true
    click_button "Remove setup.exe"
    assert_button "Post comment", disabled: false
  end

  test "another member's comment cannot be edited" do
    @task.comments.create!(author: users(:two), body: "Their words")
    visit_task

    within(".comment") do
      assert_text "Their words"
      assert_no_button "Comment actions"
      assert_no_button "Edit comment", visible: :all
      assert_no_button "Delete comment", visible: :all
    end
  end

  test "archive the task" do
    visit_task

    click_button "Archive task"
    within("dialog[open]") { click_button "Archive task" }

    assert_text "#{@task.key} was moved to the archive"
    assert_current_path "/app/projects/#{@project.id}/board"
    assert_no_text "Plan the release"
    assert @task.reload.archived_at
  end
end
