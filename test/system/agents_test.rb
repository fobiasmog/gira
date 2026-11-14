require "application_system_test_case"

# Spec web-client, "Agents screen", "Agent marker" and "Screens". goal: one
# (owner, signed in here as a plain member would be: two) and two.
class AgentsTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  setup do
    @project = projects(:goal)
    @user = users(:two) # a member of goal and side, not goal's owner
    sign_in @user.email_address, PASSWORD
  end

  def visit_agents(project = @project)
    visit "/app/projects/#{project.id}/agents"
    assert_selector "h1", text: "Agents"
  end

  def open_actions(name)
    click_button "Actions for #{name}"
  end

  def fill_in_agent_form(name: "Fish", token: "runner", channel: "MCP only", access: "Read and write", password: PASSWORD)
    within("dialog[open]") do
      fill_in "Agent name", with: name
      fill_in "Token name", with: token
      choose access
      choose channel
      fill_in "Current password", with: password
    end
  end

  test "agents entry: every member finds Agents among the project's sections" do
    visit "/app/projects/#{@project.id}/board"

    within("nav[aria-label='Menu']") { click_link "Agents" }

    assert_selector "h1", text: "Agents"
    assert_text "This project has no agents yet."
    assert_current_path "/app/projects/#{@project.id}/agents"
  end

  test "create with MCP: the value is shown once with a warning and an MCP client configuration, and the agent is listed" do
    visit_agents
    click_button "New agent"
    fill_in_agent_form
    click_button "Create agent"

    token = nil
    within("dialog[open]") do
      assert_text "Copy it now. It will not be shown again."
      token = find_field("Token").value
      assert_match(/\Aglnr_\w{40}\z/, token)
      # The MCP endpoint is the server's (MCP_RESOURCE_URL), not this page's origin.
      assert_not_equal "#{evaluate_script("location.origin")}/mcp", Oauth.resource
      assert_equal %(claude mcp add --transport http goalner #{Oauth.resource} --header "Authorization: Bearer #{token}"),
        find_field("Add Goalner to Claude Code").value
      config = JSON.parse(find_field("MCP client configuration").value)
      assert_equal [ Oauth.resource, "Bearer #{token}" ], [ config.dig("mcpServers", "goalner", "url"), config.dig("mcpServers", "goalner", "headers", "Authorization") ]
      assert_link "How to connect an MCP client", href: "/docs/mcp"
      assert_no_link "API reference" # an MCP-only token does not work at the API

      execute_script("navigator.clipboard.writeText = async (text) => { window.__copied = text }")
      click_button "Copy command"
      assert_equal find_field("Add Goalner to Claude Code").value, evaluate_script("window.__copied")
      click_button "Done"
    end

    within(".agents") do
      assert_text "Fish"
      assert_text "Added by User Two"
      assert_text "1 token"
    end
    assert_no_text token
    agent = Agent.joins(:user).find_by!(users: { name: "Fish" })
    assert @project.member?(agent.user)
    assert_equal [ "runner", "read_write", "mcp", @user ], agent.tokens.sole.values_at(:name, :access, :channels, :issuer)
  end

  test "a token that works at the API links to the API documentation" do
    visit_agents
    click_button "New agent"
    fill_in_agent_form channel: "API and MCP", access: "Read-only"
    click_button "Create agent"

    within("dialog[open]") do
      assert_link "API reference", href: "/api/docs"
      assert_field "MCP client configuration"
    end
  end

  test "wrong password: the error is under the password field and the other fields keep their values" do
    visit_agents
    click_button "New agent"
    fill_in_agent_form password: "wrong password"
    click_button "Create agent"

    within("dialog[open]") do
      assert_invalid_field "Current password"
      assert_field "Agent name", with: "Fish"
      assert_field "Token name", with: "runner"
      assert_checked_field "MCP only"
      assert_checked_field "Read and write"
    end
    assert_equal 0, Agent.count
  end

  test "only project: removing is not offered where the agent has no other project, and deleting is" do
    create_agent(@project, name: "Fish")
    owl = create_agent(@project, name: "Owl")
    projects(:side).memberships.create!(user: owl.user)
    visit_agents

    open_actions "Fish"
    assert_button "Tokens"
    assert_button "Rename"
    assert_button "Delete"
    assert_no_button "Remove from the project"
    send_keys :escape

    open_actions "Owl"
    click_button "Remove from the project"
    within("dialog[open]") { click_button "Remove from the project" }

    assert_text "Owl was removed from the project"
    within(".agents") { assert_no_text "Owl" }
    assert_not @project.member?(owl.user)
    assert projects(:side).member?(owl.user)
  end

  test "delete, after confirming, and restore from the deleted group, with no tokens" do
    fish = create_agent(@project, name: "Fish")
    issue_agent_token(fish, issuer: @user)
    visit_agents

    open_actions "Fish"
    click_button "Delete"
    within("dialog[open]") do
      assert_text "Its tokens stop working for good"
      click_button "Delete"
    end

    assert_text "Fish was deleted"
    assert_text "This project has no agents yet."
    assert fish.reload.deleted?

    find("summary", text: "Deleted agents").click
    click_button "Restore Fish"

    assert_text "Fish was restored. Issue a new token for it."
    within(".agents") do
      assert_text "Fish"
      assert_text "0 tokens"
    end
    assert_no_selector "summary", text: "Deleted agents"
    assert_not fish.reload.deleted?
  end

  test "tokens: listed with issuer, access and channels, issued with the value shown once, and revoked after confirming" do
    fish = create_agent(@project, name: "Fish")
    issue_agent_token(fish, issuer: users(:one), name: "older", access: :read, channels: %w[api])
    visit_agents

    open_actions "Fish"
    click_button "Tokens"
    within("dialog[open]") do
      assert_text "older"
      assert_text "Read-only · API only · ends in"
      assert_text "Issued by User One"
      assert_text "never used"

      fill_in "Token name", with: "runner"
      choose "MCP only"
      fill_in "Current password", with: PASSWORD
      click_button "Issue token"

      assert_text "New token “runner” for Fish"
      assert_match(/\Aglnr_\w{40}\z/, find_field("Token").value)
      assert_text "Read and write · MCP only · ends in"
      click_button "Revoke token older"
    end
    # The confirmation is a dialog of its own, inside the tokens dialog.
    within("dialog[open] dialog[open]") do
      assert_text "Anything using it stops working at once"
      click_button "Revoke"
    end

    assert_text "Token “older” revoked"
    assert_equal [ "runner" ], fish.tokens.pluck(:name)
  end

  test "add an agent from another project, and rename it" do
    owl = create_agent(projects(:side), name: "Owl")
    visit_agents

    click_button "Add an existing agent"
    within("dialog[open]") do
      assert_text "In Side project"
      click_button "Add Owl to this project"
      assert_text "Your other projects have no agents to add."
      click_button "Close", match: :first
    end
    within(".agents") { assert_text "Owl" }
    assert @project.member?(owl.user)

    open_actions "Owl"
    click_button "Rename"
    within("dialog[open]") do
      fill_in "Agent name", with: "Scout"
      click_button "Save"
    end

    assert_text "Renamed to Scout"
    within(".agents") { assert_text "Scout" }
    assert_equal "Scout", owl.user.reload.name
  end

  # Spec web-client, "Strict CSP compatibility" and "Accessibility baseline",
  # for the new screen and its dialogs.
  test "the Agents screen works under the production policy and from the keyboard" do
    create_agent(@project, name: "Owl")
    page.driver.browser.logs.get(:browser) # the buffer still holds earlier tests' entries
    visit_agents
    execute_script(<<~JS)
      window.__violations = []
      document.addEventListener("securitypolicyviolation", (e) => window.__violations.push(`${e.violatedDirective} ${e.blockedURI}`))
    JS
    focused_dialog = -> { evaluate_script("document.activeElement.closest('dialog')?.tagName.toLowerCase()") }
    focused_label = -> { evaluate_script("document.activeElement.getAttribute('aria-label') || document.activeElement.textContent.trim()") }

    # Creating: opened and submitted from the keyboard, closed with Escape.
    find_button("New agent").send_keys(:enter)
    assert_selector "dialog[open]", text: "New agent"
    assert_equal "dialog", focused_dialog.call, "focus moves into the dialog"
    fill_in_agent_form channel: "API and MCP"
    find_field("Current password").send_keys(:enter)
    within("dialog[open]") { assert_field "MCP client configuration" }
    find("dialog[open]").send_keys(:escape)
    assert_no_selector "dialog[open]"
    assert_equal "New agent", focused_label.call, "focus returns to the button that opened the dialog"

    # The value is gone once the dialog is closed. The browser closes the
    # dialog before the page hears of it, so wait for the page to drop it.
    assert_no_selector ".reveal", visible: :all
    click_button "New agent"
    within("dialog[open]") do
      assert_field "Agent name", with: ""
      assert_no_field "Token", exact: true
    end
    find("dialog[open]").send_keys(:escape)

    # An agent's menu and the dialogs it opens.
    { "Tokens" => "Tokens of Owl", "Rename" => "Rename Owl", "Delete" => "Delete Owl" }.each do |item, title|
      find_button("Actions for Owl").send_keys(:enter)
      click_button item
      assert_selector "dialog[open]", text: title
      assert_equal "dialog", focused_dialog.call, "focus moves into “#{title}”"
      find("dialog[open]").send_keys(:escape)
      assert_no_selector "dialog[open]"
      assert_equal "Actions for Owl", focused_label.call, "focus returns after “#{title}”"
    end

    find_button("Add an existing agent").send_keys(:enter)
    assert_selector "dialog[open]", text: "Add an existing agent"
    find("dialog[open]").send_keys(:escape)
    assert_equal "Add an existing agent", focused_label.call

    assert_empty evaluate_script("window.__violations")
    origins = evaluate_script("performance.getEntriesByType('resource').map((e) => new URL(e.name).origin)").uniq
    assert_equal [ evaluate_script("location.origin") ], origins
    console = page.driver.browser.logs.get(:browser)
    assert_empty console.select { |entry| entry.message.start_with?("security") }, "CSP violations in the console"
    assert_empty console.select { |entry| entry.level == "SEVERE" }.map(&:message), "errors in the console"
  end

  # Agent marker

  test "card: an agent assignee carries the marker, named in words" do
    fish = create_agent(@project, name: "Fish")
    @project.tasks.create!(title: "Fish's task", creator: @user, assignee: fish.user, status: statuses(:goal_todo))
    @project.tasks.create!(title: "Bob's task", creator: @user, assignee: @user, status: statuses(:goal_todo))

    visit "/app/projects/#{@project.id}/board"

    within(".card", text: "Fish's task") do
      assert_selector "[data-agent]"
      assert_selector ".card__assignee", text: "Assigned to Fish (agent)", visible: :all
    end
    within(".card", text: "Bob's task") do
      assert_no_selector "[data-agent]"
      assert_selector ".card__assignee", text: "Assigned to User Two", visible: :all
    end
  end

  test "assignee picker: an agent is offered with the marker and a deleted one is not offered" do
    create_agent(@project, name: "Fish")
    create_agent(@project, name: "Owl").delete!
    task = @project.tasks.create!(title: "Pick me", creator: @user, status: statuses(:goal_todo))
    visit "/app/projects/#{@project.id}/tasks/#{task.key}"

    find("button[aria-label^='Change Assignee:']").click
    assert_button "Fish (agent)"
    assert_no_button "Owl", exact: false
    click_button "Fish (agent)"

    assert_selector "button[aria-label='Change Assignee: Fish (agent)']"
    within("button[aria-label^='Change Assignee:']") { assert_selector ".chip", text: "Agent" }
  end

  test "comment by a deleted agent: the author carries the agent marker and is marked as deleted" do
    owl = create_agent(@project, name: "Owl")
    task = @project.tasks.create!(title: "History", creator: @user, status: statuses(:goal_todo))
    task.comments.create!(author: owl.user, body: "Done with this")
    task.comments.create!(author: @user, body: "Thanks")
    owl.delete!

    visit "/app/projects/#{@project.id}/tasks/#{task.key}"

    within(".comment", text: "Done with this") do
      assert_selector "[data-agent]"
      assert_selector ".chip", text: "Deleted agent"
    end
    within(".comment", text: "Thanks") do
      assert_no_selector "[data-agent]"
      assert_no_selector ".chip"
    end
  end

  test "team list and dashboard: agents are marked, and handled from the Agents screen" do
    create_agent(@project, name: "Fish")

    visit "/app/projects/#{@project.id}/members"
    within(".member", text: "Fish") do
      assert_selector ".chip", text: "Agent"
      assert_no_button "Remove Fish from the project"
      click_link "Agents"
    end
    assert_selector "h1", text: "Agents"

    visit "/app"
    assert_selector "option", text: "Fish (agent)"
  end
end
