# Deletes sessions unused for longer than Session::IDLE_TIMEOUT. They already
# no longer authenticate; this keeps the table small. Scheduled daily in
# config/recurring.yml.
class PurgeIdleSessionsJob < ApplicationJob
  def perform
    Session.idle.in_batches.delete_all
  end
end
