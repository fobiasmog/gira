# An API token (spec api-tokens). It acts for its user, read-only or
# read-write, until it expires or is deleted. Only a SHA-256 digest of the
# value is stored (design.md, decision 6): the value itself is readable from
# #value on the object that issued it, to be shown once.
#
# - A personal token reaches one project, and its user manages it.
# - A connection token (add-mcp-oauth design.md, decision 8) is issued only
#   to the MCP server, for an MCP connection's access token. It reaches all
#   of its user's projects (Current#projects), expires with the access token,
#   and stops authenticating once that is revoked. It goes with its access
#   token's row.
class ApiToken < ApplicationRecord
  PREFIX = "glnr_"
  MAX_LIFETIME_DAYS = 365
  MAX_ACTIVE_PER_USER = 20
  TOUCH_INTERVAL = 1.hour
  MAX_NAME_LENGTH = 100

  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :oauth_access_token, class_name: "Oauth::AccessToken", optional: true

  enum :access, { read: "read", read_write: "read_write" }, validate: true

  scope :active, -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }
  scope :personal, -> { where(oauth_access_token_id: nil) }
  # Replaces personal, so the user's connection tokens are
  # user.api_tokens.of_connections. It drops any earlier condition on
  # oauth_access_token_id, so narrow by access token after it.
  scope :of_connections, -> { unscope(where: :oauth_access_token_id).where.not(oauth_access_token_id: nil) }

  # Days from creation to expiry; required when a personal token is created.
  attribute :expires_in_days, :integer

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :project, presence: true, if: :personal?
  validates :expires_in_days, numericality: { only_integer: true, in: 1..MAX_LIFETIME_DAYS }, on: :create, if: :personal?

  before_create { self.expires_at = expires_in_days.days.from_now if personal? }

  attr_reader :value

  # A new, unsaved token with a fresh value: "glnr_" and 40 base58
  # characters, about 234 bits of randomness.
  def self.issue(attributes = {})
    new(attributes).tap { |api_token| api_token.value = PREFIX + SecureRandom.base58(40) }
  end

  # A connection token whose access token was revoked, by disconnecting or
  # by its connection ending, is not found.
  def self.find_active_by_value(value)
    return if value.blank?

    active.left_joins(:oauth_access_token).where(oauth_access_tokens: { revoked_at: nil }).find_by(token_digest: digest(value))
  end

  # A connection token for a connection's access token: named after the
  # client (cut to the 100 characters a name may have, so no stored client
  # name can make the exchange fail), with the connection's access, expiring
  # with the access token (to the second, as the JWT's exp claim does).
  def self.issue_for_connection!(access_token)
    issue(user_id: access_token.resource_owner_id, oauth_access_token: access_token, name: access_token.application.name.first(MAX_NAME_LENGTH),
      access: access_token.includes_scope?("write") ? :read_write : :read, expires_at: access_token.expires_at.floor).tap(&:save!)
  end

  def self.digest(value)
    OpenSSL::Digest::SHA256.hexdigest(value)
  end

  def personal?
    oauth_access_token_id.nil? && oauth_access_token.nil?
  end

  def connection?
    !personal?
  end

  def value=(value)
    @value = value
    self.token_digest = self.class.digest(value)
    self.last_characters = value.last(4)
  end

  # Records use at most hourly, like Session.
  def touch_last_used!
    update_column(:last_used_at, Time.current) if last_used_at.nil? || last_used_at < TOUCH_INTERVAL.ago
  end
end
