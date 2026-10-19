require "test_helper"

class Api::Projects::InvitationsControllerTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  setup do
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  def invite(email, project: @project)
    perform_enqueued_jobs do
      post api_project_invitations_path(project), params: { email: email }, as: :json
    end
  end

  def mails_to(address)
    ActionMailer::Base.deliveries.select { |mail| mail.to.include?(address) }
  end

  def token_in(mail)
    mail.text_part.decoded[%r{/invitations/([\w-]+)}, 1]
  end

  test "inviting a registered user sends a link but does not add them yet" do
    invite users(:stranger).email_address

    assert_response :accepted
    assert_equal "Invitation sent.", response.parsed_body["message"]
    assert_equal 1, mails_to("stranger@example.com").size
    assert_not @project.member?(users(:stranger))
  end

  test "inviting an unknown email creates no account and emails a link without any password" do
    assert_no_difference -> { User.count } do
      invite "newcomer@example.com"
    end

    mail = mails_to("newcomer@example.com").sole
    assert_match %r{/invitations/[\w-]{40,}}, mail.text_part.decoded
    assert_no_match(/password|пароль/i, mail.text_part.decoded + mail.html_part.decoded)
  end

  test "registered, unknown and member addresses get the same response" do
    responses = [ users(:stranger).email_address, "newcomer@example.com", users(:two).email_address ].map do |email|
      invite email
      [ response.status, response.body ]
    end

    assert_equal 1, responses.uniq.size
  end

  test "inviting an existing member sends no email" do
    invite users(:two).email_address.upcase

    assert_response :accepted
    assert_empty ActionMailer::Base.deliveries
    assert_not @project.invitations.exists?(email: users(:two).email_address)
  end

  test "re-inviting re-sends the pending invitation and extends its expiry" do
    invite "newcomer@example.com"

    travel 3.days do
      assert_no_difference -> { Invitation.count } do
        invite "Newcomer@Example.com"
      end
      assert_in_delta 7.days.from_now, @project.invitations.sole.expires_at, 1.minute
    end
    assert_equal 2, mails_to("newcomer@example.com").size
  end

  test "only a digest of the token is stored" do
    invite "newcomer@example.com"

    token = token_in(mails_to("newcomer@example.com").sole)
    invitation = @project.invitations.sole
    assert_not_equal token, invitation.token_digest
    assert_equal Invitation.digest(token), invitation.token_digest
  end

  test "a malformed address is a validation error" do
    invite "not an email"

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "email").present?
  end

  test "members see pending invitations with email and expiry" do
    invite "newcomer@example.com"
    @project.invitations.create!(email: "old@example.com", inviter: users(:one), token_digest: "x", expires_at: 1.day.ago)
    sign_in_as users(:two)

    get api_project_invitations_path(@project)

    assert_equal [ "newcomer@example.com" ], response.parsed_body.map { |i| i["email"] }
    assert response.parsed_body.first["expires_at"].present?
  end

  test "the owner revokes a pending invitation and its link stops working" do
    sign_in_as users(:two)
    invite "newcomer@example.com"
    token = token_in(mails_to("newcomer@example.com").sole)
    sign_in_as users(:one)

    delete api_project_invitation_path(@project, @project.invitations.sole)

    assert_response :no_content
    assert_nil Invitation.find_usable(token)
  end

  test "the inviter can revoke, another member cannot" do
    invite "newcomer@example.com"
    invitation = @project.invitations.sole
    sign_in_as users(:two)

    delete api_project_invitation_path(@project, invitation)
    assert_response :forbidden
    assert_nil invitation.reload.revoked_at

    sign_in_as users(:one)
    delete api_project_invitation_path(@project, invitation)
    assert_response :no_content
  end

  test "non-members cannot invite" do
    invite "newcomer@example.com", project: projects(:side)

    assert_response :not_found
    assert_empty ActionMailer::Base.deliveries
  end

  test "over the limit: the twenty-first invitation in an hour gets 429 and sends nothing" do
    other = Project.create!(title: "Other", short_name: "OTH", owner: users(:one))
    20.times { |i| invite "person#{i}@example.com", project: i.even? ? @project : other }
    ActionMailer::Base.deliveries.clear

    invite "person21@example.com"

    assert_response :too_many_requests
    assert_empty ActionMailer::Base.deliveries
  end
end
