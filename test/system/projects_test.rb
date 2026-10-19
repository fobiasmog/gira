require "application_system_test_case"

# Spec web-client: projects, project settings, members and invitations.
class ProjectsTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  setup { @project = projects(:goal) }

  test "create a project" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects"
    click_link "New project", match: :first

    fill_in "Project title", with: "Moonshot"
    fill_in "Short name", with: "moon"
    assert_field "Short name", with: "MOON"
    click_button "Create project"

    assert_current_path %r{/app/projects/\d+/board}
    project = Project.find_by!(title: "Moonshot")
    assert_current_path "/app/projects/#{project.id}/board"
    assert_selector ".column h2", text: "To Do"
    within(".side-nav") { assert_link "Moonshot" }
  end

  test "validation error: the message is shown under the short-name field and the input is kept" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/new"

    fill_in "Project title", with: "Bad key"
    fill_in "Short name", with: "1X"
    click_button "Create project"

    assert_invalid_field "Short name"
    short_name = find_field("Short name")
    error = find("##{short_name["aria-describedby"].split.first}")
    assert_match(/short name/i, error.text)
    assert_field "Project title", with: "Bad key"
    assert_field "Short name", with: "1X"
    assert_nil Project.find_by(title: "Bad key")
  end

  test "owner-only settings: a member who is not the owner gets no settings entry" do
    sign_in users(:two).email_address, PASSWORD
    visit "/app/projects/#{@project.id}/board"
    assert_selector ".column h2", text: "To Do"

    within(".side-nav") do
      assert_link "Board"
      assert_no_link "Project settings"
    end

    visit "/app/projects/#{@project.id}/settings"
    assert_selector "h1", text: "Page not found"
  end

  test "the owner renames the project, changes its short name and archives it" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{@project.id}/board"
    within(".side-nav") { click_link "Project settings" }

    fill_in "Project title", with: "Goalner 2"
    fill_in "Short name", with: "GO"
    click_button "Save"
    assert_text "Project saved"
    within(".side-nav") { assert_text "Goalner 2" }
    assert_equal [ "Goalner 2", "GO" ], @project.reload.slice(:title, :short_name).values

    click_button "Archive project"
    within("dialog[open]") { click_button "Archive project" }
    assert_text "“Goalner 2” was archived"
    assert_current_path "/app/projects"
    within(".side-nav") { assert_no_text "Goalner 2" }
    assert @project.reload.archived_at
  end

  test "invite by email, see the pending invitation and revoke it" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{@project.id}/members"
    assert_text "User Two"

    fill_in "Email address", with: "friend@example.com"
    click_button "Send invitation"
    assert_text "Invitation sent."
    within("section[aria-labelledby=pending-heading]") { assert_text "friend@example.com" }

    click_button "Revoke the invitation for friend@example.com"
    assert_text "Invitation for friend@example.com revoked"
    assert_text "No pending invitations."
    assert @project.invitations.find_by!(email: "friend@example.com").revoked_at
  end

  test "an invalid address is rejected next to the field" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{@project.id}/members"

    fill_in "Email address", with: "not an address"
    click_button "Send invitation"

    assert_invalid_field "Email address"
    assert_text "No pending invitations."
  end

  test "the owner removes a member" do
    sign_in users(:one).email_address, PASSWORD
    visit "/app/projects/#{@project.id}/members"

    click_button "Remove User Two from the project"
    within("dialog[open]") { click_button "Delete" }

    assert_text "User Two was removed from the project"
    assert_not @project.member?(users(:two))
  end

  test "a member leaves the project" do
    sign_in users(:two).email_address, PASSWORD
    visit "/app/projects/#{@project.id}/members"
    assert_no_button "Remove User One from the project"

    click_button "Leave project"
    within("dialog[open]") { click_button "Leave project" }

    assert_text "You left “Goalner”"
    assert_current_path "/app/projects"
    within(".side-nav") { assert_no_link "Goalner", href: "/app/projects/#{@project.id}/board" }
    assert_not @project.member?(users(:two))
  end
end
