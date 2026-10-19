# Deletes invitations whose link has expired and that were never accepted.
# Scheduled daily in config/recurring.yml.
class PurgeExpiredInvitationsJob < ApplicationJob
  def perform
    Invitation.expired.where(accepted_at: nil).in_batches.delete_all
  end
end
