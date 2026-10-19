require "test_helper"

# Every user-facing email renders in both languages, with no password and no
# task description or comment text.
class MailersTest < ActionMailer::TestCase
  PASSWORD = "correct horse battery"

  setup do
    @task = projects(:goal).tasks.create!(title: "Ship it", description: "SECRET DESCRIPTION", creator: users(:one),
      assignee: users(:two), status: statuses(:goal_todo))
    @task.comments.create!(author: users(:one), body: "SECRET COMMENT")
    @invitation = projects(:goal).invitations.create!(email: "new@example.com", inviter: users(:one),
      token_digest: Invitation.digest("token"), expires_at: 1.week.from_now)
  end

  def emails_for(user)
    {
      confirmation: AccountMailer.confirmation(user),
      attempted_registration: AccountMailer.attempted_registration(user),
      unlock: AccountMailer.unlock(user),
      reset: PasswordsMailer.reset(user),
      invite: InvitationMailer.invite(@invitation, "token"),
      assigned: TaskMailer.assigned(@task, assigner: users(:one))
    }
  end

  { "en" => /Hello|invited|assigned/, "ru" => /Здравствуйте|приглашает|назначает/ }.each do |lang, greeting|
    test "every email renders in #{lang}" do
      [ users(:one), users(:two) ].each { |user| user.update!(lang: lang) }

      emails_for(users(:two)).each do |name, mail|
        text = mail.text_part.decoded
        html = mail.html_part.decoded

        assert_match greeting, text, "#{name} (#{lang})"
        assert_match greeting, html, "#{name} (#{lang})"
        assert_no_match(/translation missing/i, text + html + mail.subject, name)
        assert_no_match(/#{PASSWORD}|SECRET DESCRIPTION|SECRET COMMENT/, text + html, name)
      end
    end
  end

  test "invitations use the invitee's language when they have an account" do
    users(:stranger).update!(lang: "ru")
    invitation = projects(:goal).invitations.create!(email: users(:stranger).email_address, inviter: users(:one),
      token_digest: Invitation.digest("other"), expires_at: 1.week.from_now)

    assert_match(/Приглашение/, InvitationMailer.invite(invitation, "other").subject)
  end

  test "mail is delivered by the retrying background job" do
    assert_equal MailDeliveryJob, ApplicationMailer.delivery_job
  end
end
