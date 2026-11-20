require "application_system_test_case"

# Spec web-client: "Board change tabs", "Board change summary", "Archiving a
# change", "Changes screen" and "New change dialog".
class ChangesTest < ApplicationSystemTestCase
  setup do
    @project = projects(:goal)
    @user = users(:one)
    sign_in @user.email_address, "correct horse battery"
  end

  def create_change(name)
    @project.project_changes.create!(name: name)
  end

  def task(title, change: nil, status: :goal_todo)
    @project.tasks.create!(title: title, creator: @user, status: statuses(status), change: change)
  end

  def import(name, text)
    Change::Import.new(project: @project, user: @user, name: name, artifacts: { "tasks" => text }).run!.change
  end

  def board_path(suffix = "") = "/app/projects/#{@project.id}/board#{suffix}"

  def visit_board(suffix = "")
    visit board_path(suffix)
    assert_selector ".column h2", text: "To Do"
  end

  def selected_tab
    find("[role=tablist] [role=tab][aria-selected=true]")
  end

  def summary
    find("section[aria-label='Change']")
  end

  def change_section(name)
    find(".change", text: name) { |section| section.find(".change__name").text == name }
  end

  def waiting_for_people(change)
    change.comments.create!(author: create_agent(@project, name: "Fish #{change.name}").user, body: "A question?")
  end

  # Board change tabs

  test "switch change: the tab is selected, the address names it, and the board shows its tasks" do
    labels = create_change("add-labels")
    export = travel(1.minute) { create_change("export-csv") }
    task("Labels task", change: labels)
    task("Export task", change: export)
    visit_board("/changes/add-labels")
    assert_text "Labels task"

    click_link "export-csv"

    assert_current_path board_path("/changes/export-csv")
    assert_selector "[role=tab][aria-selected=true]", text: "export-csv"
    assert_text "Export task"
    assert_no_text "Labels task"
    assert_selector "[role=tabpanel][aria-labelledby='#{selected_tab[:id]}']"
  end

  test "default tab: the newest open change; tabs list changes newest first, then other tasks and New change" do
    create_change("add-labels")
    travel(1.minute) { create_change("fix-login") }
    create_change("old-work").archive!
    visit_board

    assert_equal "fix-login", selected_tab.find(".ellipsis").text
    tabs = all("[role=tablist] [role=tab]").map { |tab| tab.find(".ellipsis").text }
    assert_equal [ "fix-login", "add-labels", "Other tasks" ], tabs
    assert_button "New change"
    within(summary) { assert_link "fix-login" }
  end

  test "no open change: Other tasks is shown, and the tab row holds only it and New change" do
    task("Loose task")
    visit_board

    assert_equal [ "Other tasks" ], all("[role=tablist] [role=tab]").map(&:text)
    assert_selector "[role=tab][aria-selected=true]", text: "Other tasks"
    assert_text "Loose task"
    assert_button "New change"
  end

  test "reload shows the same tab" do
    create_change("add-labels")
    export = travel(-1.minute) { create_change("export-csv") }
    task("Export task", change: export)
    visit_board("/changes/export-csv")

    page.driver.browser.navigate.refresh

    assert_selector ".column h2", text: "To Do"
    assert_equal "export-csv", selected_tab.find(".ellipsis").text
    assert_text "Export task"
  end

  test "an archived change in the address: the default tab with a message" do
    create_change("add-labels").archive!
    create_change("fix-login")
    visit_board("/changes/add-labels")

    assert_selector "[role=status]", text: "The change “add-labels” is archived or does not exist."
    assert_equal "fix-login", selected_tab.find(".ellipsis").text
  end

  test "the tabs work by keyboard as a tab list" do
    create_change("add-labels")
    travel(1.minute) { create_change("fix-login") }
    visit_board

    selected_tab.send_keys(:arrow_right)
    assert_equal "add-labels", evaluate_script("document.activeElement.querySelector('.ellipsis').textContent")
    page.driver.browser.action.send_keys(:end).perform
    assert_equal "Other tasks", evaluate_script("document.activeElement.textContent.trim()")
    page.driver.browser.action.send_keys(:space).perform

    assert_current_path board_path("/other")
    assert_selector "[role=tab][aria-selected=true]", text: "Other tasks"
    assert_equal [ "0", "-1", "-1" ].sort, all("[role=tab]").map { |tab| tab[:tabindex] }.sort
  end

  test "phase and waiting marker: each change tab shows its phase, and the marker when it is waiting for people" do
    export = create_change("export-csv").tap { |change| change.update!(phase: "exploring") }
    travel(-1.minute) { create_change("add-labels") }.update!(phase: "implementing")
    waiting_for_people(export)
    visit_board

    export_tab = find("[role=tab]", text: "export-csv")
    labels_tab = find("[role=tab]", text: "add-labels")
    within(export_tab) do
      assert_selector ".phase-pill", text: "Exploring"
      assert_selector ".waiting-marker", text: "Waiting for you", visible: :all
    end
    within(labels_tab) do
      assert_selector ".phase-pill", text: "Implementing"
      assert_no_selector ".waiting-marker", visible: :all
    end
    assert_match(/Waiting for you/, export_tab[:textContent])
  end

  test "add a task to a change's board: it belongs to that change" do
    labels = create_change("add-labels")
    visit_board("/changes/add-labels")

    within(".column", text: "To Do", match: :first) do
      click_button "Add task to To Do"
      find_field("Task title").send_keys("Fix flaky test", :enter)
      assert_text "Fix flaky test"
    end

    assert_equal labels, Task.find_by!(title: "Fix flaky test").change
    within(selected_tab) { assert_no_selector ".change-tabs__count" }
  end

  # Board change summary

  test "a change in progress: Open the change links to its page, with the cards done, and no phase or archive action" do
    labels = create_change("add-labels").tap { |change| change.update!(phase: "implementing") }
    3.times { |i| task("Open #{i}", change: labels, status: i.even? ? :goal_todo : :goal_work) }
    task("Finished", change: labels, status: :goal_done)
    task("Not in the change")
    visit_board("/changes/add-labels")

    within(summary) do
      assert_link "Open the change", href: "/app/projects/#{@project.id}/changes/add-labels"
      assert_no_selector ".phase-pill"
      assert_text "1 of 4 done"
      assert_selector "[role=progressbar][aria-valuenow='1'][aria-valuemax='4']"
      assert_selector ".progress-bar__fill[style*='25%']"
      assert_no_button "Archive only"
    end
    within(selected_tab) { assert_no_text "1/4" }
    assert_no_text "Not in the change"

    within(summary) { click_link "Open the change" }
    assert_current_path "/app/projects/#{@project.id}/changes/add-labels"
  end

  test "more tabs than fit: no scrollbar, a mouse wheel scrolls the row, and it fades into New change until its end" do
    12.times { |i| create_change("a-rather-long-change-name-#{i}") }
    visit_board

    assert_selector ".change-tabs__new.change-tabs__new--fade"
    assert_equal "none", evaluate_script("getComputedStyle(document.querySelector('[role=tablist]')).scrollbarWidth")

    execute_script("document.querySelector('[role=tablist]').dispatchEvent(new WheelEvent('wheel', { deltaY: 200, bubbles: true, cancelable: true }))")
    assert_operator evaluate_script("document.querySelector('[role=tablist]').scrollLeft"), :>, 0, "a mouse wheel scrolls the row sideways"

    execute_script("const row = document.querySelector('[role=tablist]'); row.scrollLeft = row.scrollWidth")
    assert_no_selector ".change-tabs__new--fade"
  end

  test "tabs that fit: no fade" do
    create_change("add-labels")
    visit_board

    assert_selector ".change-tabs__new"
    assert_no_selector ".change-tabs__new--fade"
  end

  test "the board of other tasks has no summary" do
    create_change("add-labels")
    task("Loose task")
    visit_board("/other")

    assert_text "Loose task"
    assert_no_selector "section[aria-label='Change']"
  end

  test "the summary in Russian" do
    @user.update!(lang: "ru")
    create_change("add-labels")
    visit "/app/projects/#{@project.id}/board"

    within("section[aria-label='Изменение']") do
      assert_text "Готово 0 из 0"
      assert_link "Открыть изменение"
      assert_no_button "Только в архив"
    end
    assert_selector "[role=tab]", text: "Другие задачи"
  end

  # Archiving a change

  test "archiving with unfinished cards warns, and still archives; the board then shows the default tab" do
    import("add-labels", "## 1. Model\n- [x] 1.1 Table\n## 2. API\n- [ ] 2.1 Routes\n## 3. Docs\n- [ ] 3.1 README\n## 4. UI\n- [ ] 4.1 Dialog\n")
    travel(-1.minute) { create_change("export-csv") }
    visit "/app/projects/#{@project.id}/changes/add-labels"

    click_button "Archive only"
    within("dialog[open]") do
      assert_text "Archive only: “add-labels”"
      assert_text "3 cards are not done."
      assert_text "Agents may still be working on them. They stay with the archived change and leave the board."
      click_button "Archive only"
    end

    assert_text "“add-labels” was archived"
    assert @project.project_changes.find_by!(name: "add-labels").archived?
    visit_board
    assert_no_selector "[role=tab]", text: "add-labels"
    assert_selector "[role=tablist] [role=tab][aria-selected=true] .ellipsis", exact_text: "export-csv"
  end

  test "archiving a change whose cards are all done asks for confirmation without a warning" do
    done = create_change("add-labels")
    task("Finished", change: done, status: :goal_done)
    visit "/app/projects/#{@project.id}/changes/add-labels"

    click_button "Archive only"
    within("dialog[open]") do
      assert_text "“add-labels” leaves the board, and its tasks stay with it."
      assert_text "No agent is asked: the OpenSpec change is not archived and its specs are not synced."
      assert_no_text "not done"
      click_button "Archive only"
    end

    assert_text "“add-labels” was archived"
    visit_board
    assert_no_selector "[role=tab]", text: "add-labels"
    assert_selector "[role=tab][aria-selected=true]", text: "Other tasks"
  end

  # New change dialog

  test "typing a name lowercases it and turns spaces into hyphens, and shows the format" do
    visit_board

    click_button "New change"
    within("dialog[open]") do
      find_field("Name").send_keys("Export CSV")
      assert_field "Name", with: "export-csv"
      assert_text "Lowercase letters and digits joined by single hyphens"
    end
  end

  test "a taken name: the dialog stays open with the server's error at the field" do
    create_change("add-labels")
    visit_board

    click_button "New change"
    within("dialog[open]") do
      fill_in "Name", with: "add-labels"
      click_button "Create change"
      assert_invalid_field "Name"
      assert_text "Name has already been taken"
    end
    assert_equal 1, @project.project_changes.count
  end

  test "pick an agent: the agents with their states, and the new change's page says Fish is picked" do
    fish = create_agent(@project, name: "Fish").user
    heron = create_agent(@project, name: "Heron").user
    owl = create_agent(@project, name: "Owl").user
    @project.project_changes.create!(name: "export-csv", phase: "exploring").update!(agent: fish, agent_taken_at: Time.current)
    [ fish, heron ].each { |agent| @project.memberships.find_by!(user: agent).update!(checked_in_at: 1.minute.ago) }
    @project.memberships.find_by!(user: owl).update!(checked_in_at: 2.hours.ago)
    visit_board

    click_button "New change"
    within("dialog[open]") do
      fill_in "Name", with: "add-tags"
      assert_equal [ "Any free agent", "Fish — on export-csv", "Heron — free", "Owl — offline" ], all("select option").map(&:text)
      select "Fish — on export-csv", from: "Agent"
      click_button "Create change"
    end

    assert_no_selector "dialog[open]"
    assert_equal fish, @project.project_changes.find_by!(name: "add-tags").agent
    visit "/app/projects/#{@project.id}/changes/add-tags"
    assert_select "Agent", selected: "Fish — on export-csv"
    assert_text "will take it"
  end

  test "from the board: the dialog closes and the board shows the new change's tab" do
    create_change("add-labels")
    visit_board

    click_button "New change"
    within("dialog[open]") do
      fill_in "Name", with: "fix-login"
      click_button "Create change"
    end

    assert_no_selector "dialog[open]"
    assert_current_path board_path("/changes/fix-login")
    # The address changes first; the tab is selected once the board has loaded it.
    assert_selector "[role=tablist] [role=tab][aria-selected=true] .ellipsis", exact_text: "fix-login"
    assert_equal %w[fix-login add-labels], all("[role=tablist] [role=tab] .ellipsis").map(&:text).first(2)
  end

  # Changes screen

  test "add a task to a change: no field on the screen, and a task added on its board is listed under it" do
    export = create_change("export-csv")
    visit "/app/projects/#{@project.id}/changes"

    within(change_section("export-csv")) do
      assert_text "No tasks in this change yet."
      assert_no_field type: "text"
      assert_no_button "Create"
    end

    task("Rate limiting", change: export)
    visit "/app/projects/#{@project.id}/changes"
    within(change_section("export-csv")) do
      assert_text "Rate limiting"
      assert_text "1 task in total"
    end
  end

  test "move a task to the other tasks: it leaves the change and keeps its column" do
    login = create_change("fix-login")
    create_change("export-csv")
    task("TEST-9", change: login, status: :goal_work)
    visit "/app/projects/#{@project.id}/changes"

    within(change_section("fix-login")) { click_button "Move GOAL-1" }
    click_button "Other tasks"

    assert_text "GOAL-1 moved to the other tasks"
    within(change_section("fix-login")) { assert_text "No tasks in this change yet." }
    moved = Task.find_by!(title: "TEST-9")
    assert_equal [ nil, statuses(:goal_work) ], [ moved.change, moved.status ]

    visit_board("/other")
    within(".column", text: "Work", match: :first) { assert_text "TEST-9" }
  end

  test "cards of tasks.md offer no move menu, a task added by hand does" do
    labels = import("add-labels", "## 1. Model\n- [ ] 1.1 Table\n")
    task("Added by hand", change: labels)
    visit "/app/projects/#{@project.id}/changes"

    within(change_section("add-labels")) do
      card = labels.tasks.roots.find_by!(in_tasks_md: true)
      within(".row-list > li", text: card.title) do
        assert_no_button "Move #{card.key}"
        assert_text "tasks.md"
      end
      assert_button "Move GOAL-3"
    end
  end

  test "open changes as sections with counts; archive one, and expand it below the open ones" do
    labels = create_change("add-labels")
    task("Unfinished", change: labels, status: :goal_work)
    task("Finished", change: labels, status: :goal_done)
    visit "/app/projects/#{@project.id}/changes"

    within(change_section("add-labels")) do
      assert_text "2 tasks in total"
      assert_text "Work 1"
      assert_text "Done 1"
      assert_selector "button[aria-expanded=true][aria-label='Tasks of add-labels']"
      click_button "Archive only: add-labels"
    end
    within("dialog[open]") do
      assert_text "1 card is not done."
      click_button "Archive only"
    end

    assert_text "“add-labels” was archived"
    assert_text "There are no open changes."
    find("summary", text: "Archived changes (1)").click
    within(".archived-change", text: "add-labels") do
      assert_link "add-labels", href: "/app/projects/#{@project.id}/changes/#{labels.id}"
      assert_no_text "Unfinished"
      click_button "Tasks of add-labels"
      assert_text "Unfinished"
      within(".row-list > li", text: "Finished") { assert_text "Done" }
    end
  end

  test "a section can be closed and opened again" do
    labels = create_change("add-labels")
    task("Model", change: labels)
    visit "/app/projects/#{@project.id}/changes"

    within(change_section("add-labels")) do
      assert_text "Model"
      click_button "Tasks of add-labels"
      assert_selector "button[aria-expanded=false]"
      assert_no_text "Model"
      click_button "Tasks of add-labels"
      assert_text "Model"
    end
  end

  test "phase and waiting marker: a section header shows the phase, the marker, and the name linking to the page" do
    export = create_change("export-csv").tap { |change| change.update!(phase: "proposed") }
    travel(-1.minute) { create_change("fix-login") }
    waiting_for_people(export)
    visit "/app/projects/#{@project.id}/changes"

    within(change_section("export-csv").find(".change__header")) do
      assert_selector ".phase-pill", text: "Proposed"
      assert_selector ".waiting-marker", visible: :all
      assert_link "export-csv", href: "/app/projects/#{@project.id}/changes/export-csv"
    end
    within(change_section("fix-login").find(".change__header")) do
      assert_selector ".phase-pill", text: "Idea"
      assert_no_selector ".waiting-marker", visible: :all
    end

    click_link "export-csv"
    assert_current_path "/app/projects/#{@project.id}/changes/export-csv"
  end

  test "with an idea: the change's page shows it" do
    visit "/app/projects/#{@project.id}/changes"

    click_button "New change"
    within("dialog[open]") do
      fill_in "Name", with: "export-csv"
      fill_in "Idea", with: "People want a project's tasks as **CSV**."
      click_button "Create change"
    end

    assert_text "Change “export-csv” created"
    change_section("export-csv").click_link("export-csv")
    within("section[aria-labelledby='change-idea']") do
      assert_text "People want a project's tasks as CSV."
      assert_selector "strong", text: "CSV"
    end
    assert_equal "People want a project's tasks as **CSV**.", @project.project_changes.find_by!(name: "export-csv").idea
  end

  test "an idea too long: the dialog stays open with the error at the idea" do
    visit_board

    click_button "New change"
    within("dialog[open]") do
      fill_in "Name", with: "export-csv"
      find_field("Idea").execute_script("this.value = 'a'.repeat(100001); this.dispatchEvent(new Event('input'))")
      click_button "Create change"
      assert_invalid_field "Idea"
    end
    assert_equal 0, @project.project_changes.count
  end

  test "a new change from the changes screen" do
    visit "/app/projects/#{@project.id}/changes"

    click_button "New change"
    within("dialog[open]") do
      find_field("Name").send_keys("Fix Login")
      click_button "Create change"
    end

    assert_text "Change “fix-login” created"
    assert change_section("fix-login")
  end
end
