require "test_helper"

class PurgeIdleSessionsJobTest < ActiveJob::TestCase
  test "deletes only sessions idle for more than 14 days" do
    active = users(:one).sessions.create!
    idle = users(:one).sessions.create!
    idle.update_columns(updated_at: 15.days.ago)

    PurgeIdleSessionsJob.perform_now

    assert Session.exists?(active.id)
    assert_not Session.exists?(idle.id)
  end

  test "is scheduled daily" do
    tasks = ActiveSupport::ConfigurationFile.parse(Rails.root.join("config/recurring.yml")).fetch("production")

    assert_equal "PurgeIdleSessionsJob", tasks.dig("purge_idle_sessions", "class")
    assert_match(/every day/, tasks.dig("purge_idle_sessions", "schedule"))
  end
end
