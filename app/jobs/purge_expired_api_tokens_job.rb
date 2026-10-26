# Deletes API tokens past their expiry. They already no longer authenticate;
# this keeps the table small. Scheduled daily in config/recurring.yml.
class PurgeExpiredApiTokensJob < ApplicationJob
  def perform
    ApiToken.expired.in_batches.delete_all
  end
end
