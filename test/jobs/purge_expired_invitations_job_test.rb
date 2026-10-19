require "test_helper"

class PurgeExpiredInvitationsJobTest < ActiveJob::TestCase
  test "deletes expired, unaccepted invitations only" do
    project = projects(:goal)
    build = ->(email, **attributes) do
      project.invitations.create!(email: email, inviter: users(:one), token_digest: SecureRandom.hex, expires_at: 1.day.from_now, **attributes)
    end
    usable = build.("usable@example.com")
    expired = build.("expired@example.com", expires_at: 1.day.ago)
    accepted = build.("accepted@example.com", expires_at: 1.day.ago, accepted_at: 2.days.ago)

    PurgeExpiredInvitationsJob.perform_now

    assert Invitation.exists?(usable.id)
    assert Invitation.exists?(accepted.id)
    assert_not Invitation.exists?(expired.id)
  end
end
