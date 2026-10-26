require "test_helper"

class PurgeExpiredApiTokensJobTest < ActiveJob::TestCase
  test "deletes expired tokens and keeps active ones" do
    active = api_tokens(:two_goal_read_write)
    expired = api_tokens(:two_goal_expired)

    PurgeExpiredApiTokensJob.perform_now

    assert ApiToken.exists?(active.id)
    assert_not ApiToken.exists?(expired.id)
  end
end
