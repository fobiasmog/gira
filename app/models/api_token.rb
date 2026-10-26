# A personal API token (spec api-tokens). It acts for its user in one project,
# read-only or read-write, until it expires or is deleted. Only a SHA-256
# digest of the value is stored (design.md, decision 6): the value itself is
# readable from #value on the object that issued it, to be shown once.
class ApiToken < ApplicationRecord
  PREFIX = "glnr_"
  MAX_LIFETIME_DAYS = 365
  MAX_ACTIVE_PER_USER = 20
  TOUCH_INTERVAL = 1.hour

  belongs_to :user
  belongs_to :project

  enum :access, { read: "read", read_write: "read_write" }, validate: true

  scope :active, -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }

  # Days from creation to expiry; required when a token is created.
  attribute :expires_in_days, :integer

  validates :name, presence: true, length: { maximum: 100 }
  validates :expires_in_days, numericality: { only_integer: true, in: 1..MAX_LIFETIME_DAYS }, on: :create

  before_create { self.expires_at = expires_in_days.days.from_now }

  attr_reader :value

  # A new, unsaved token with a fresh value: "glnr_" and 40 base58
  # characters, about 234 bits of randomness.
  def self.issue(attributes = {})
    new(attributes).tap { |api_token| api_token.value = PREFIX + SecureRandom.base58(40) }
  end

  def self.find_active_by_value(value)
    active.find_by(token_digest: digest(value)) if value.present?
  end

  def self.digest(value)
    OpenSSL::Digest::SHA256.hexdigest(value)
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
