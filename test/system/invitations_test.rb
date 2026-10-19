require "application_system_test_case"

class InvitationsTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  setup { @project = projects(:goal) }

  def invite(email)
    @project.invitations.create!(email: email, inviter: users(:one), token_digest: "unused", expires_at: 1.day.from_now)
      .issue_token!
  end

  test "a matching user accepts the invitation" do
    token = invite(users(:stranger).email_address)

    visit invitation_path(token)
    click_link "Sign in to accept"
    sign_in users(:stranger).email_address, PASSWORD
    click_button "Accept invitation"

    assert_current_path "/app/projects/#{@project.id}/board"  # the SPA opens the project board
    assert @project.member?(users(:stranger))
  end

  test "a different account is refused" do
    token = invite("someone.else@example.com")

    sign_in users(:stranger).email_address, PASSWORD
    visit invitation_path(token)

    assert_text "This invitation was sent to another email address."
    assert_no_button "Accept invitation"
  end

  test "an expired link is refused" do
    token = invite(users(:stranger).email_address)
    sign_in users(:stranger).email_address, PASSWORD

    travel 8.days do
      visit invitation_path(token)
      assert_text "This invitation link is invalid, has expired or was already used."
    end
    assert_not @project.member?(users(:stranger))
  end

  test "a new user signs up from the invitation and then accepts" do
    token = invite("newcomer@example.com")

    visit invitation_path(token)
    click_link "Create an account"
    assert_field "Email", with: "newcomer@example.com"
    fill_in "Name", with: "Newcomer"
    fill_in "Password", with: "a long password"
    click_button "Sign up"
    assert_text "Check your email to finish signing up."

    visit link_in(last_email_to("newcomer@example.com"), "/confirmations/")
    click_button "Confirm my email"
    assert_text "Your email address is confirmed."
    sign_in "newcomer@example.com", "a long password"

    assert_current_path invitation_path(token)
    click_button "Accept invitation"
    assert_current_path "/app/projects/#{@project.id}/board"  # the SPA opens the project board
    assert @project.member?(User.find_by!(email_address: "newcomer@example.com"))
  end
end
