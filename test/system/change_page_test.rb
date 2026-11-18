require "application_system_test_case"

# Spec web-client, "Change page"; spec markdown-content, "One feature set for
# editing and display" and "Read-only Markdown views".
class ChangePageTest < ApplicationSystemTestCase
  TASKS = "## 1. Export\n\n- [ ] 1.1 Add the endpoint\n- [ ] 1.2 Add the button\n"
  PROPOSAL = "# Proposal\n\n## Why\n\nPeople want CSV.\n\n- one row per task\n- no archived tasks\n"
  DESIGN = "# Design\n\n| Option | Chosen |\n|---|---|\n| Streaming | yes |\n"

  setup do
    @project = projects(:goal)
    @user = users(:one)
    @fish = create_agent(@project, name: "Fish").user
    sign_in @user.email_address, "correct horse battery"
  end

  def page_path(ref) = "/app/projects/#{@project.id}/changes/#{ref}"

  def visit_change(ref, marker = "Thread")
    visit page_path(ref)
    assert_selector "h2", text: marker
  end

  def import(name = "export-csv", user: @fish, **files)
    Change::Import.new(project: @project, user:, name:, artifacts: { "tasks" => TASKS, **files.transform_keys(&:to_s) }).run!.change
  end

  def steps = find("ol[aria-label='Phases']")

  def thread = find("section[aria-labelledby='change-thread']")

  def files = find("aside[aria-labelledby='change-files']")

  # Review a proposal; Source of a file; Table in a change file

  test "review a proposal: Idea and Exploring passed, Proposed current, a tab per file, the proposal formatted" do
    change = @project.project_changes.create!(name: "export-csv", idea: "CSV for weekly reports")
    change.move_to!("exploring", by: @fish)
    import(proposal: PROPOSAL, design: DESIGN, specs: { "export" => "## ADDED Requirements\n" })
    visit_change("export-csv")

    within(steps) do
      assert_selector "li", text: /\AIdea\s+\(passed\)\z/
      assert_selector "li", text: /\AExploring\s+\(passed\)\z/
      assert_selector "li[aria-current=step]", text: /\AProposed\s+\(current\)\z/
      assert_selector "li", text: /\AImplementing\z/
      assert_selector "li", text: /\ADone\z/
    end
    within(files) do
      assert_equal %w[proposal.md design.md specs/export/spec.md tasks.md], all("[role=tab]").map(&:text)
      assert_selector "[role=tab][aria-selected=true]", text: "proposal.md"
      within("[role=tabpanel]") do
        assert_selector "h2", text: "Why"
        assert_selector "li", text: "no archived tasks"
        assert_no_text "## Why"
      end
      assert_text "Imported by Fish (agent) on"
    end
  end

  test "source of a file: the design with its table, formatted without a table, then exactly as imported" do
    import(proposal: PROPOSAL, design: DESIGN)
    visit_change("export-csv")

    within(files) do
      click_on "design.md"
      within("[role=tabpanel]") do
        assert_selector "h1", text: "Design"
        assert_no_selector "table"
        assert_text "Streaming"
      end

      click_button "Source"
      assert_selector "button[aria-pressed=true]", text: "Source"
      assert_equal DESIGN.chomp, find("[role=tabpanel] pre").text
      click_on "tasks.md"
      assert_includes find("[role=tabpanel] pre").text, "- [ ] 1.1 Add the endpoint <!-- goalner:GOAL-"
    end
  end

  test "file tabs work by keyboard" do
    import(proposal: PROPOSAL, design: DESIGN)
    visit_change("export-csv")

    within(files) { find("[role=tab][aria-selected=true]").send_keys(:arrow_right) }

    within(files) do
      assert_selector "[role=tab][aria-selected=true]", text: "design.md"
      assert_selector "[role=tabpanel] h1", text: "Design"
    end
    assert_equal "design.md", evaluate_script("document.activeElement.textContent.trim()")
  end

  # Phase menu

  test "phase menu: choosing Implementing marks it current and records the move" do
    @project.project_changes.create!(name: "export-csv").update!(phase: "proposed")
    visit_change("export-csv")

    select "Implementing", from: "Phase"

    assert_text "“export-csv” moved to Implementing"
    within(steps) { assert_selector "li[aria-current=step]", text: "Implementing" }
    within(thread) { assert_text "User One moved the change to Implementing" }
    assert_equal "implementing", @project.project_changes.find_by!(name: "export-csv").phase
  end

  test "a change whose cards are all done is reported Done, and the menu keeps Implementing" do
    change = @project.project_changes.create!(name: "add-labels")
    @project.tasks.create!(title: "Card", creator: @user, change:, status: statuses(:goal_done))
    change.update!(phase: "implementing")
    visit_change("add-labels")

    within(steps) do
      assert_selector "li[aria-current=step]", text: "Done"
      assert_selector "li", text: /\AImplementing\s+\(passed\)\z/
    end
    assert_equal "implementing", find_field("Phase").value
    assert_text "1 of 1 cards done"
  end

  # Idea

  test "edit the idea of a change in Idea" do
    @project.project_changes.create!(name: "export-csv", idea: "First thoughts")
    visit_change("export-csv")
    assert_text "First thoughts"

    click_button "Edit idea"
    find_field("Idea").set("People want **CSV** for reports.")
    click_button "Save"

    within("section[aria-labelledby='change-idea']") { assert_selector "strong", text: "CSV" }
    assert_equal "People want **CSV** for reports.", @project.project_changes.find_by!(name: "export-csv").idea
  end

  test "idea fixed: in Exploring the idea is shown without an edit action" do
    change = @project.project_changes.create!(name: "export-csv", idea: "CSV for weekly reports")
    change.move_to!("exploring", by: @fish)
    visit_change("export-csv")

    assert_text "CSV for weekly reports"
    assert_no_button "Edit idea"
  end

  # Thread

  test "history in the thread: Fish's move to Exploring above Fish's question, with the agent marked" do
    change = @project.project_changes.create!(name: "export-csv")
    travel_to(2.minutes.ago) { change.move_to!("exploring", by: @fish) }
    change.comments.create!(author: @fish, body: "Should archived tasks go into the file?")
    visit_change("export-csv")

    within(thread) do
      items = all("ol > li").map(&:text)
      assert_equal 2, items.size
      assert_match(/Fish \(agent\) moved the change to Exploring/, items.first)
      assert_match(/Should archived tasks go into the file\?/, items.last)
      within(".comment") { assert_text "Agent" }
    end
  end

  test "answer in the thread: the reply is last, and the change is no longer waiting for people" do
    change = @project.project_changes.create!(name: "export-csv")
    change.comments.create!(author: @fish, body: "Should archived tasks go into the file?")
    visit_change("export-csv")
    assert_selector ".waiting-status", text: "Waiting for you"

    within(thread) do
      fill_in "Comment", with: "No archived tasks."
      click_button "Post comment"
      assert_selector ".comment", count: 2
      assert_equal "No archived tasks.", all(".comment").last.find(".comment__text").text
    end

    assert_no_selector ".waiting-status"
    assert_not change.reload.waiting_for_people?
    visit "/app/projects/#{@project.id}/board/changes/export-csv"
    assert_no_selector "[role=tab] .waiting-marker"
  end

  # Archived and unknown changes

  test "archived change: its idea, thread and files, and no phase menu, idea editing, comment field or Archive" do
    change = @project.project_changes.create!(name: "fix-login", idea: "Fix the login")
    change.comments.create!(author: @user, body: "Done with it")
    import("fix-login", proposal: PROPOSAL)
    change.reload.archive!
    visit_change(change.id)

    assert_text "Fix the login"
    within(thread) { assert_text "Done with it" }
    within(files) { assert_selector "[role=tab]", text: "proposal.md" }
    assert_text "This change was archived on"
    assert_no_field "Phase"
    assert_no_button "Edit idea"
    assert_no_field "Comment"
    assert_no_button "Archive"
    assert_no_button "Comment actions"
  end

  test "archive from the page: the page shows the archived change by its id" do
    change = @project.project_changes.create!(name: "fix-login")
    visit_change("fix-login")

    click_button "Archive"
    within("dialog[open]") { click_button "Archive" }

    assert_text "“fix-login” was archived"
    assert_current_path page_path(change.id)
    assert_text "This change was archived on"
    assert change.reload.archived?
  end

  test "unknown change: the page says it is archived or does not exist" do
    visit page_path("no-such-change")

    assert_selector "[role=status]", text: "The change “no-such-change” is archived or does not exist."
  end

  test "the board summary and the changes screen link to the page" do
    @project.project_changes.create!(name: "export-csv")
    visit "/app/projects/#{@project.id}/board"

    within("section[aria-label='Change']") { click_link "export-csv" }
    assert_current_path page_path("export-csv")
    assert_selector "h1", text: "export-csv"

    click_link "Changes", match: :first
    within(".change", text: "export-csv") { click_link "export-csv" }
    assert_current_path page_path("export-csv")
  end

  test "the page in Russian: phases and history lines in the viewer's language" do
    @user.update!(lang: "ru")
    change = @project.project_changes.create!(name: "export-csv")
    change.move_to!("exploring", by: @fish)
    visit page_path("export-csv")

    within("ol[aria-label='Фазы']") { assert_selector "li[aria-current=step]", text: "Исследование" }
    assert_text "Fish (агент): изменение переведено в фазу «Исследование»"
  end
end
