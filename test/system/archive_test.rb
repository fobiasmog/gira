require "application_system_test_case"

# Spec markdown-content, "Read-only Markdown views", and the archive screens.
class ArchiveTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @user = users(:one)
    @task = @project.tasks.create!(title: "Old work", creator: @user, status: statuses(:goal_done),
      description: "# Summary\n\n- first point\n- second point\n\n- [x] checked")
    @task.comments.create!(author: users(:two), body: "Done, see **notes**")
    @task.archive!
    sign_in @user.email_address, "correct horse battery"
  end

  test "the archive lists archived tasks" do
    visit "/app/projects/#{@project.id}/archive"

    assert_selector "h1", text: "Archive"
    click_link "Old work"
    assert_current_path "/app/projects/#{@project.id}/archive/#{@task.id}"
  end

  test "archived task description: the heading and list are formatted and cannot be edited" do
    visit "/app/projects/#{@project.id}/archive/#{@task.id}"

    assert_text "This task is archived and can no longer be changed."
    within(".archived-task__description") do
      assert_selector "h1", text: "Summary"
      assert_selector "ul li", text: "first point"
      assert_selector "ul li", text: "second point"
      assert_selector "input[type=checkbox][disabled]"
    end
    assert_no_selector "[contenteditable=true]"
    assert_no_selector ".description-editor"
    assert_no_field "Comment"
    within(".comment") do
      assert_selector "strong", text: "notes"
      assert_no_button "Edit comment"
    end
  end

  test "opening an archived task by its key shows the read-only view" do
    visit "/app/projects/#{@project.id}/tasks/#{@task.key}"

    assert_current_path "/app/projects/#{@project.id}/archive/#{@task.id}"
    assert_text "This task is archived"
  end
end
