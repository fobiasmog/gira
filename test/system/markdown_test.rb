require "application_system_test_case"

# Spec markdown-content: one feature set, rendered safely.
class MarkdownTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @user = users(:one)
    @task = @project.tasks.create!(title: "Markdown task", creator: @user, status: statuses(:goal_todo))
  end

  def comment(body)
    @task.comments.create!(author: @user, body: body)
  end

  def visit_task
    sign_in @user.email_address, "correct horse battery"
    visit "/app/projects/#{@project.id}/tasks/#{@task.key}"
    assert_selector "h1", text: @task.title
  end

  def assert_no_alert
    assert_raises(Selenium::WebDriver::Error::NoSuchAlertError) { page.driver.browser.switch_to.alert }
  end

  test "image syntax in a comment keeps the alt text and fetches nothing" do
    comment("Look ![x](https://tracker.example/pixel.png) here")
    visit_task

    within(".comment .markdown") do
      assert_text "Look x here"
      assert_no_selector "img"
    end
    requested = evaluate_script("performance.getEntriesByType('resource').map((e) => e.name)")
    assert_empty requested.grep(/tracker\.example/)
  end

  test "a javascript: link in a description is plain text" do
    @task.update!(description: "Please [click](javascript:alert(1)) and [this](data:text/html,hi) and [ok](https://example.com/ok)")
    visit_task

    within(".description-editor__content") do
      assert_text "Please click and this and ok"
      assert_no_selector "a", text: "click"
      assert_no_selector "a", text: "this"
      assert_selector "a[href='https://example.com/ok'][rel='noopener noreferrer nofollow'][target='_blank']", text: "ok"
    end
  end

  test "HTML in a comment creates no elements and runs no script, with or without the Sanitizer API" do
    comment("<img src=x onerror=alert(1)><script>alert(2)</script> <a href=\"javascript:alert(3)\">x</a>")
    visit_task
    assert_comment_html_is_inert

    # Without setHTML the renderer's own output goes in through innerHTML, so
    # the schema alone has to keep the markup out.
    execute_script("delete Element.prototype.setHTML")
    within(".side-nav") { click_link "Board" }
    assert_selector "h2", text: "To Do"
    go_back
    assert_selector "h1", text: @task.title
    assert_comment_html_is_inert
  end

  def assert_comment_html_is_inert
    within(".comment .markdown") do
      assert_text "x"
      assert_no_selector "img", visible: :all
      assert_no_selector "script", visible: :all
      assert_no_selector "a", visible: :all
    end
    assert_no_alert
  end

  test "a comment's bare URL becomes a link and Markdown emphasis is shown" do
    comment("See https://example.com/spec and **note** this, also www.example.org")
    visit_task

    within(".comment .markdown") do
      assert_selector "a[href='https://example.com/spec'][target='_blank'][rel='noopener noreferrer nofollow']", text: "https://example.com/spec"
      assert_selector "a[href='http://www.example.org']"
      assert_selector "strong", text: "note"
    end
  end

  test "tables become plain text and deep headings are capped" do
    @task.update!(description: <<~MD)
      #### Deep heading

      | Name | Role |
      |------|------|
      | Ada  | **Engineer** |

      - [x] Done item
      - [ ] Open item
    MD
    visit_task

    within(".description-editor__content") do
      assert_no_selector "table"
      assert_text "Name | Role"
      assert_text "Ada | Engineer"
      assert_no_selector "h4"
      assert_selector "h3", text: "Deep heading"
      assert_selector "li[data-checked=true]", text: "Done item"
    end
  end
end
