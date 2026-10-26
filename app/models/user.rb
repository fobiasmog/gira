class User < ApplicationRecord
  LANGUAGES = %w[en ru].freeze
  CONTACT_SERVICES = %w[fb vk tg ig slack].freeze
  MAX_FAILED_SIGN_INS = 10
  LOCK_DURATION = 1.hour

  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :memberships, dependent: :destroy
  has_many :projects, through: :memberships
  has_many :api_tokens, dependent: :delete_all
  has_one_attached :avatar

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  # has_secure_password already rejects passwords over 72 bytes (the bcrypt limit).
  validates :password, length: { minimum: 12 }, allow_nil: true
  validates :name, presence: true, length: { maximum: 100 }
  validates :lang, inclusion: { in: LANGUAGES }
  validate :contact_links_are_https_urls

  after_create :attach_default_avatar
  # Changing or resetting the password revokes every API token (design.md,
  # decision 8). Sessions are ended by the controllers, which keep the current one.
  after_update_commit -> { api_tokens.delete_all }, if: :saved_change_to_password_digest?

  # Single use: confirming changes confirmed_at, and changing the address
  # invalidates links sent to the old one.
  generates_token_for :email_confirmation, expires_in: 24.hours do
    [ email_address, confirmed_at&.to_i ]
  end

  # Single use: unlocking clears locked_until.
  generates_token_for :unlock, expires_in: LOCK_DURATION do
    locked_until&.to_i
  end

  # Distinct users who share at least one non-archived project with this user.
  def teammates
    shared = Membership.where(project_id: projects.kept.select(:id)).select(:user_id)
    User.where(id: shared).where.not(id: id)
  end

  def teammate_of?(other)
    teammates.exists?(other.id)
  end

  # Ids of non-archived projects both users belong to.
  def shared_project_ids_with(other)
    projects.kept.where(id: other.projects.kept.select(:id)).pluck(:id)
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
