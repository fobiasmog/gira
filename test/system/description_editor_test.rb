require "application_system_test_case"

# Spec markdown-content, "Description editor" and "Paste Markdown".
class DescriptionEditorTest < ApplicationSystemTestCase
  # Every supported construct, in the form the editor writes it back.
  ROUND_TRIP = <<~MD.chomp
    # Heading one

    ## Heading two

    ### Heading three

    Some **bold**, *italic*, ~~struck~~ and `code` text with a [link](https://example.com/page).

    - First bullet
    - Second bullet
      - Nested bullet

    1. First step
    2. Second step

    - [ ] Open task
    - [x] Done task

    > A quote

    ```ruby
    puts "hi"
    ```

    End
  MD

  setup do
    @project = projects(:goal)
    @user = users(:one)
    @task = @project.tasks.create!(title: "Editor task", creator: @user, status: statuses(:goal_todo))
  end

  def visit_task
    sign_in @user.email_address, "correct horse battery"
    visit "/app/projects/#{@project.id}/tasks/#{@task.key}"
    assert_selector "h1", text: @task.title
  end

  def editor
    find(".description-editor__content")
  end

  def wait_for_description(&condition)
    Timeout.timeout(5) { sleep 0.1 until condition.call(@task.reload.description.to_s) }
  rescue Timeout::Error
    flunk "description not saved as expected, got:\n#{@task.description}"
  end

  test "format and save: Markdown shortcuts, saved as Markdown on blur" do
    visit_task

    editor.click
    editor.send_keys("# Plan", :enter, "- [ ] Buy milk")
    within(editor) do
      assert_selector "h1", text: "Plan"
      assert_selector "ul[data-type=taskList] li", text: "Buy milk"
    end
    find("h1", text: @task.title).click

    wait_for_description { |md| md.include?("# Plan") && md.include?("- [ ] Buy milk") }
  end

  test "the toolbar formats the selection and saves after a pause in typing" do
    visit_task

    editor.click
    editor.send_keys("Important words")
    editor.send_keys([ :shift, :home ])
    click_button "Bold"
    assert_selector "button[aria-label=Bold][aria-pressed=true]"

    wait_for_description { |md| md == "**Important words**" }
  end

  test "toggle a checkbox" do
    @task.update!(description: "- [ ] Write tests\n- [ ] Ship")
    visit_task

    within(editor) { first("input[type=checkbox]").click }

    wait_for_description { |md| md.include?("- [x] Write tests") && md.include?("- [ ] Ship") }
  end

  test "paste a list" do
    visit_task
    editor.click

    execute_script(<<~JS, editor)
      const data = new DataTransfer()
      data.setData("text/plain", "- one\\n- two")
      arguments[0].dispatchEvent(new ClipboardEvent("paste", { clipboardData: data, bubbles: true, cancelable: true }))
    JS

    within(editor) { assert_selector "ul:not([data-type]) > li", count: 2 }
    assert_equal [ "one", "two" ], editor.all("ul > li").map(&:text)
  end

  test "a link is added through the dialog; disallowed addresses are refused" do
    visit_task
    editor.click
    editor.send_keys("Docs")
    editor.send_keys([ :shift, :home ])

    click_button "Link"
    fill_in "Link address", with: "javascript:alert(1)"
    click_button "Save"
    assert_text "Use an address starting with http://, https:// or mailto:"
    fill_in "Link address", with: "https://example.com/docs"
    click_button "Save"

    within(editor) { assert_selector "a[href='https://example.com/docs']", text: "Docs" }
    wait_for_description { |md| md == "[Docs](https://example.com/docs)" }
  end

  test "every supported construct survives a save and reload unchanged" do
    @task.update!(description: ROUND_TRIP)
    visit_task

    within(editor) { find("p", text: "End").click }
    editor.send_keys(:end, "!")
    find("h1", text: @task.title).click
    wait_for_description { |md| md.end_with?("End!") }
    assert_equal ROUND_TRIP.sub(/End\z/, "End!"), @task.description

    page.driver.browser.navigate.refresh
    within(editor) do
      assert_selector "h1", text: "Heading one"
      assert_selector "h2", text: "Heading two"
      assert_selector "h3", text: "Heading three"
      assert_selector "strong", text: "bold"
      assert_selector "em", text: "italic"
      assert_selector "s", text: "struck"
      assert_selector "code", text: "code"
      assert_selector "a[href='https://example.com/page']", text: "link"
      assert_selector "ul li ul li", text: "Nested bullet"
      assert_selector "ol li", count: 2
      assert_selector "li[data-checked=false]", text: "Open task"
      assert_selector "li[data-checked=true]", text: "Done task"
      assert_selector "blockquote", text: "A quote"
      assert_selector "pre code", text: 'puts "hi"'
      assert_text "End!"
    end
  end
end
