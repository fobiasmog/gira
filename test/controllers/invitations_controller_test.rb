require "test_helper"

class InvitationsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @project = projects(:goal)
    @invitation = @project.invitations.create!(email: users(:stranger).email_address, inviter: users(:one),
      token_digest: Invitation.digest("valid-token"), expires_at: 7.days.from_now)
  end

  test "matching user accepts: becomes a member and the link is used up" do
    sign_in_as users(:stranger)

    get invitation_path("valid-token")
    assert_select "button", "Accept invitation"
    assert_not @project.member?(users(:stranger)), "opening the link must not accept"

    post invitation_acceptance_path("valid-token")
    assert_redirected_to app_path("projects/#{@project.id}")
    assert @project.member?(users(:stranger))

    post invitation_acceptance_path("valid-token")
    assert_response :not_found
  end

  test "different account: acceptance is refused" do
    users(:stranger).memberships.destroy_all
    other = User.create!(name: "Other", email_address: "other@example.com", password: "a long password", confirmed_at: Time.current)
    sign_in_as other

    post invitation_acceptance_path("valid-token")

    assert_response :forbidden
    assert_select ".flash--alert", /another email address/
    assert_not @project.member?(other)
  end

  test "an unconfirmed matching account cannot accept" do
    users(:stranger).update_columns(confirmed_at: nil)
    sign_in_as users(:stranger)

    post invitation_acceptance_path("valid-token")

    assert_response :forbidden
    assert_not @project.member?(users(:stranger))
  end

  test "expired invitation: acceptance is refused and no membership is created" do
    sign_in_as users(:stranger)

    travel 8.days do
      get invitation_path("valid-token")
      assert_response :not_found

      post invitation_acceptance_path("valid-token")
      assert_response :not_found
    end
    assert_not @project.member?(users(:stranger))
  end

  test "an invitation to an archived project cannot be accepted" do
    @project.archive!
    sign_in_as users(:stranger)

    post invitation_acceptance_path("valid-token")

    assert_response :not_found
    assert_not @project.member?(users(:stranger))
  end

  test "visitors are offered sign-in and sign-up and brought back afterwards" do
    get invitation_path("valid-token")

    assert_response :success
    assert_select "a[href=?]", new_registration_path(email: users(:stranger).email_address)
    sign_in_with users(:stranger).email_address
    assert_redirected_to invitation_url("valid-token")
  end
end
