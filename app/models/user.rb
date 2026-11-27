class User < ApplicationRecord
  LANGUAGES = %w[en ru].freeze
  CONTACT_SERVICES = %w[fb vk tg ig slack].freeze
  MAX_FAILED_SIGN_INS = 10
  LOCK_DURATION = 1.hour

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :projects, through: :memberships
  # Personal tokens only, so nothing that lists, counts or deletes a user's
  # tokens reaches connection tokens: those end with their MCP connection
  # (McpConnection). The user's connection tokens are api_tokens.of_connections.
  has_many :api_tokens, -> { personal }, dependent: :delete_all
  # Present for agents only (spec agents): the row that makes this account an
  # agent. Authorization asks agent?, never the address's domain.
  has_one :agent
  # Runners it owns (spec agent-runners), revoked ones included: a runner
  # is never deleted, since its leases and workspaces name it.
  has_many :runners, dependent: nil
  has_one_attached :avatar

  # Everyone but deleted agents, who keep their memberships so that they can
  # be restored, but are left out wherever people are listed or accepted
  # (add-agents design.md, decision 8).
  scope :active, -> { where.not(id: Agent.deleted.select(:user_id)) }

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  # has_secure_password already rejects passwords over 72 bytes (the bcrypt limit).
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :lang, inclusion: { in: LANGUAGES }
  validate :contact_links_are_https_urls
  validate :address_is_not_reserved, if: :email_address_changed?, unless: :agent?
  validate :agents_are_never_admins

  after_create :attach_default_avatar
  # Changing or resetting the password revokes every API token (design.md,
  # decision 8) and ends every MCP connection (add-mcp-oauth design.md,
  # decision 7). Sessions are ended by the controllers, which keep the current one.
  after_update_commit -> { api_tokens.delete_all; McpConnection.end_all_for(self) }, if: :saved_change_to_password_digest?

  # Single use: confirming changes confirmed_at, and changing the address
  # invalidates links sent to the old one.
  generates_token_for :email_confirmation, expires_in: 24.hours do
    [ email_address, confirmed_at&.to_i ]
  end

  # Single use: unlocking clears locked_until.
  generates_token_for :unlock, expires_in: LOCK_DURATION do
    locked_until&.to_i
  end

  # The person with this address. An agent is not found: every flow that
  # starts from an address answers for an agent's as for an unknown one
  # (spec user-auth, "Agent accounts cannot sign in").
  def self.find_person_by_email(email_address)
    find_by(email_address: email_address).then { |user| user unless user&.agent? }
  end

  # Distinct users who share at least one non-archived project with this
  # user: people and agents, but not deleted agents.
  def teammates
    shared = Membership.where(project_id: projects.kept.select(:id)).select(:user_id)
    User.active.where(id: shared).where.not(id: id)
  end

  def teammate_of?(other)
    teammates.exists?(other.id)
  end

  # Ids of non-archived projects both users belong to.
  def shared_project_ids_with(other)
    projects.kept.where(id: other.projects.kept.select(:id)).pluck(:id)
  end

  def agent?
    agent.present?
  end

  def confirmed?
    confirmed_at.present?
  end

  def confirm!
    update!(confirmed_at: Time.current)
  end

  def locked?
    locked_until.present? && locked_until.future?
  end

  # Counts a wrong password. The tenth consecutive one locks the account for
  # an hour and emails an unlock link. Attempts while locked are not counted.
  def register_failed_sign_in!
    just_locked = false

    with_lock do
      next if locked?

      attempts = locked_until ? 1 : failed_login_attempts + 1 # an expired lock starts a new count
      just_locked = attempts >= MAX_FAILED_SIGN_INS
      update_columns(failed_login_attempts: attempts, locked_until: (LOCK_DURATION.from_now if just_locked))
    end

    AccountMailer.unlock(self).deliver_later if just_locked
  end

  def unlock!
    update_columns(failed_login_attempts: 0, locked_until: nil)
  end
  alias_method :reset_failed_sign_ins!, :unlock!

  # Checks the current password re-entered in settings (design.md, decision
  # 7). It shares the sign-in lockout: a wrong password counts as a failed
  # attempt, a correct one resets the count, and while the account is locked
  # every password is refused without being counted.
  def verify_reentered_password(password)
    return false if locked?

    if authenticate(password.to_s)
      reset_failed_sign_ins!
      true
    else
      register_failed_sign_in!
      false
    end
  end

  # Merges submitted links into the stored ones; an empty value removes a link.
  def merge_contact_links(links)
    self.contact_links = contact_links.merge(links.to_h.stringify_keys.slice(*CONTACT_SERVICES)).compact_blank
  end

  # Replaces the avatar with an uploaded image after checking its real type
  # and size. Returns false, with an error on :avatar, when it is refused.
  def replace_avatar(file)
    if (violation = Avatar::UPLOAD_POLICY.violation(file))
      errors.add(:avatar, violation)
      return false
    end

    avatar.attach(io: StringIO.new(Avatar.reencode(file)), filename: "avatar.webp", content_type: "image/webp", identify: false)
    true
  rescue Avatar::InvalidImage
    errors.add(:avatar, :content_type_not_allowed)
    false
  end

  private
    def attach_default_avatar
      avatar.attach(io: StringIO.new(Avatar.default_png), filename: "avatar.png", content_type: "image/png", identify: false)
    end

    # Addresses on the agent domain are generated for agents only (spec
    # user-auth, "Agent domain is reserved"). The whole domain is refused, so
    # the answer never says whether an agent has the address.
    def address_is_not_reserved
      errors.add(:email_address, :reserved) if Agent.reserved_address?(email_address)
    end

    def agents_are_never_admins
      errors.add(:admin, :invalid) if admin? && agent?
    end

    def contact_links_are_https_urls
      contact_links.each do |service, url|
        errors.add(:contact_links, :invalid_service, service: service) unless CONTACT_SERVICES.include?(service)
        errors.add(:contact_links, :invalid_url, service: service) unless https_url?(url)
      end
    end

    def https_url?(url)
      return false unless url.is_a?(String) && url.length <= 255

      uri = URI.parse(url)
      uri.is_a?(URI::HTTPS) && uri.host.present?
    rescue URI::InvalidURIError
      false
    end
end
