require "application_system_test_case"

# Spec web-client, "Change page" and "Requests on the change page"; spec
# markdown-content, "One feature set for editing and display" and "Read-only
# Markdown views".
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

  def request_area = find("section[aria-labelledby='change-request']")

  def ask(change, kind) = ChangeRequest.ask!(change:, kind:, by: @user)

  # agent is on change, and checked in a minute ago.
  def put_on(change, agent)
    change.update!(agent:, agent_taken_at: Time.current)
    check_in(agent)
    change
  end

  def check_in(agent, at: 1.minute.ago) = @project.memberships.find_by!(user: agent).update!(checked_in_at: at)

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

  # Phases

  test "phase menu: an open change shows its phases and offers no menu to choose one" do
    @project.project_changes.create!(name: "export-csv", phase: "proposed")
    visit_change("export-csv")

    within(steps) { assert_selector "li[aria-current=step]", text: "Proposed" }
    assert_no_field "Phase"
    within(".change-header") { assert_no_select }
  end

  test "a change whose cards are all done is reported Done" do
    change = @project.project_changes.create!(name: "add-labels")
    @project.tasks.create!(title: "Card", creator: @user, change:, status: statuses(:goal_done))
    change.update!(phase: "implementing")
    visit_change("add-labels")

    within(steps) do
      assert_selector "li[aria-current=step]", text: "Done"
      assert_selector "li", text: /\AImplementing\s+\(passed\)\z/
    end
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

  test "archived change: its idea, thread and files, and no idea editing, comment field or Archive" do
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
    assert_no_button "Archive only"
    assert_no_button "Comment actions"
    assert_no_selector "section[aria-labelledby='change-request']"
    assert_no_button "Start exploring"
    assert_no_button "Cancel request"
    assert_no_field "Agent"
  end

  test "archived change with its agent: no request button, Cancel request, Release or agent menu" do
    change = put_on(@project.project_changes.create!(name: "fix-login", phase: "implementing"), @fish)
    ask(change, "archive")
    change.archive!(by: @user)
    visit_change(change.id)

    assert_text "This change was archived on"
    assert_no_button "Archive and sync specs"
    assert_no_button "Cancel request"
    assert_no_button "Release Fish"
    assert_no_field "Agent"
  end

  # Requests on the change page

  test "start exploring: the request waits for a free agent, with Cancel request instead of Start exploring" do
    change = @project.project_changes.create!(name: "export-csv")
    visit_change("export-csv")

    within(request_area) { assert_field "Agent", with: "" }
    click_button "Start exploring"

    within(request_area) do
      assert_select "Agent", selected: "Any free agent"
      assert_text "will take it"
      assert_button "Cancel request"
    end
    assert_no_button "Start exploring"
    assert_equal [ [ "explore", "waiting" ] ], change.requests.pluck(:kind, :state)
  end

  test "button for the phase: Implement in Proposed" do
    @project.project_changes.create!(name: "export-csv", phase: "proposed")
    visit_change("export-csv")

    assert_button "Implement"
    assert_no_button "Start exploring"
  end

  test "comment with the step: the comment is in the thread, the field is empty, and the implement request is open" do
    change = @project.project_changes.create!(name: "export-csv", phase: "proposed")
    visit_change("export-csv")

    within(thread) { fill_in "Comment", with: "Start with the API." }
    within(request_area) do
      assert_text "Your comment below goes with it."
      click_button "Implement"
    end

    within(thread) do
      assert_selector ".comment", text: "Start with the API."
      assert_field "Comment", with: ""
    end
    within(request_area) { assert_button "Cancel request" }
    assert_equal [ [ "implement", "waiting" ] ], change.requests.pluck(:kind, :state)
    assert_equal [ "Start with the API." ], change.comments.pluck(:body)
  end

  test "queued for a busy agent: the request is queued for Fish, who is on export-csv" do
    put_on(@project.project_changes.create!(name: "export-csv", phase: "exploring"), @fish)
    @project.project_changes.create!(name: "add-tags", agent: @fish)
    visit_change("add-tags")

    click_button "Start exploring"

    within(request_area) do
      assert_button "Cancel request"
      assert_select "Agent", selected: "Fish — on export-csv"
      assert_text "will take it"
    end
  end

  test "taken request: Fish has been working on it since it took it, with Cancel request and Release Fish" do
    change = @project.project_changes.create!(name: "export-csv", phase: "proposed")
    ask(change, "implement")
    ChangeRequest.take!(project: @project, agent: @fish)
    visit_change("export-csv")

    within(request_area) do
      assert_selector "[role=status]", text: "Fish has been working on it since"
      assert_button "Cancel request"
      assert_button "Release Fish"
      assert_no_field "Agent"
    end
  end

  test "blocked: the tab shows the waiting marker, and the page says Fish's context is full and offers Release Fish" do
    change = @project.project_changes.create!(name: "export-csv", phase: "proposed")
    ask(change, "implement")
    ChangeRequest.take!(project: @project, agent: @fish)
    Change.block_for_full_context!(project: @project, agent: @fish)

    visit "/app/projects/#{@project.id}/board/changes/export-csv"
    assert_selector "[role=tab] .waiting-marker"
    visit_change("export-csv")

    within(request_area) do
      assert_selector "[role=status]", text: "The context of Fish is full. The change is blocked until you release Fish."
      assert_button "Release Fish"
    end
  end

  test "agent picks it up: without reloading, the page shows Fish working, then Fish's questions and no open request" do
    change = @project.project_changes.create!(name: "export-csv")
    ask(change, "explore")
    visit_change("export-csv")
    within(request_area) { assert_select "Agent", selected: "Any free agent" }

    request = ChangeRequest.take!(project: @project, agent: @fish)
    using_wait_time(15) do
      within(request_area) { assert_selector "[role=status]", text: "Fish has been working on it since" }
    end

    request.finish!(by: @fish, outcome: "done", comment: "Should archived tasks go into the file?")
    using_wait_time(15) do
      within(thread) { assert_selector ".comment", text: "Should archived tasks go into the file?" }
    end
    assert_no_button "Cancel request"
    assert_button "Write the proposal"
  end

  test "cancel: no open request, and Start exploring again" do
    change = @project.project_changes.create!(name: "export-csv")
    ask(change, "explore")
    visit_change("export-csv")

    click_button "Cancel request"

    assert_button "Start exploring"
    assert_no_button "Cancel request"
    assert_equal "cancelled", change.requests.sole.state
  end

  test "pick another agent: Heron is picked" do
    heron = create_agent(@project, name: "Heron").user
    check_in(heron)
    change = @project.project_changes.create!(name: "add-tags", agent: @fish)
    visit_change("add-tags")
    within(request_area) { assert_select "Agent", selected: "Fish — offline" }

    within(request_area) { select "Heron — free", from: "Agent" }

    within(request_area) { assert_select "Agent", selected: "Heron — free" }
    assert_text "Heron is picked"
    assert_equal heron, change.reload.agent
  end

  test "release: no agent, the agent menu, and a line saying that the member released Fish" do
    change = put_on(@project.project_changes.create!(name: "export-csv", phase: "exploring"), @fish)
    visit_change("export-csv")
    within(request_area) { assert_selector "[role=status]", text: "Fish is on this change" }

    click_button "Release Fish"

    within(request_area) do
      assert_field "Agent", with: ""
      assert_no_button "Release Fish"
    end
    within(thread) { assert_selector ".thread-event", text: "User One released Fish (agent)" }
    assert_nil change.reload.agent
  end

  test "reply note: posting asks Fish to reply" do
    put_on(@project.project_changes.create!(name: "export-csv", phase: "exploring"), @fish)
    visit_change("export-csv")

    within(thread) { assert_text "Posting asks Fish to reply." }
  end

  test "request lines in the thread: the member asking for exploring, Fish taking and finishing it, then Fish's questions" do
    change = @project.project_changes.create!(name: "export-csv")
    ask(change, "explore")
    ChangeRequest.take!(project: @project, agent: @fish).finish!(by: @fish, outcome: "done", comment: "Archived tasks too?")
    visit_change("export-csv")

    within(thread) do
      items = all("ol > li").map(&:text)
      assert_match(/User One asked for exploring/, items[0])
      assert_match(/Fish \(agent\) started exploring/, items[1])
      assert_match(/Fish \(agent\) moved the change to Exploring/, items[2])
      assert_match(/Fish \(agent\) finished exploring/, items[3])
      assert_match(/Archived tasks too\?/, items[4])
    end
  end

  test "archive from the page: the page shows the archived change by its id" do
    change = @project.project_changes.create!(name: "fix-login")
    visit_change("fix-login")

    click_button "Archive only"
    within("dialog[open]") { click_button "Archive only" }

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

    within("section[aria-label='Change']") { click_link "Open the change" }
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

    click_button "Написать предложение"
    assert_text "User One: запрошено — написание предложения"
    assert_text "возьмётся за работу"
  end
end
