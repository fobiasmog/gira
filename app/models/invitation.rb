# An invitation to join a project (spec project-membership). Only a digest of
# the emailed token is stored. Nobody becomes a member, and no account is
# created, until the invited person accepts while signed in with that address.
class Invitation < ApplicationRecord
  LIFETIME = 7.days

  belongs_to :project
  belongs_to :inviter, class_name: "User"

  normalizes :email, with: ->(email) { email.strip.downcase }
  validates :email, presence: true, format: { with: URI::MailTo::EMAIL_REGEXP }, length: { maximum: 255 }

  scope :pending, -> { where(accepted_at: nil, revoked_at: nil) }
  scope :usable, -> { pending.where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  # Invites an address, or re-sends and extends a pending invitation to it.
  # Members are not emailed. Callers answer the same way in every case, so the
  # result never reveals whether an address is registered or a member.
  def self.invite(project:, inviter:, email:)
    invitation = project.invitations.pending.find_or_initialize_by(email: normalize_value_for(:email, email.to_s))
    invitation.inviter = inviter if invitation.new_record?
    invitation.validate! # a malformed address is a validation error, not a secret
    return if project.members.exists?(email_address: invitation.email)

    token = invitation.issue_token!
    InvitationMailer.invite(invitation, token).deliver_later
  end

  def self.find_usable(token)
    usable.joins(:project).merge(Project.kept).find_by(token_digest: digest(token.to_s))
  end

  def self.digest(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  # A new token and a fresh 7-day expiry; earlier links stop working.
  def issue_token!
    SecureRandom.urlsafe_base64(32).tap do |token|
      update!(token_digest: self.class.digest(token), expires_at: LIFETIME.from_now)
    end
  end

  def addressed_to?(user)
    user.confirmed? && user.email_address == email
  end

  def accept!(user)
    transaction do
      project.memberships.find_or_create_by!(user: user)
      update!(accepted_at: Time.current)
    end
  end

  def revocable_by?(user)
    inviter_id == user.id || project.owned_by?(user)
  end

  def revoke!
    update!(revoked_at: Time.current)
  end
end
