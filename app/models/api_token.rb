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
# - An agent token (spec agents; add-agents design.md, decision 5) is issued
#   by a person for an agent, and its user is the agent, so what it changes is
#   the agent's doing. It reaches the agent's projects that its issuer also
#   belongs to (Current#projects), works on the channels it was issued for
#   (ApiTokenAuthentication), and in practice does not expire: it is issued
#   for AGENT_LIFETIME and ends when it is revoked or its agent is deleted.
# - A run token (spec agent-runners, "Run tokens"; add-runners-and-workspaces
#   design.md, decision 2) is an agent token issued with a lease of the agent
#   to a runner, by the runner's owner. Nobody issues, lists or counts it:
#   it authenticates only while its lease lives, and goes when it ends.
class ApiToken < ApplicationRecord
  PREFIX = "glnr_"
  MAX_LIFETIME_DAYS = 365
  # How long an agent token is valid. Long enough to never matter, and still
  # a date: every token has an expiry, so nothing has to handle its absence.
  AGENT_LIFETIME = 100.years
  MAX_ACTIVE_PER_USER = 20
  TOUCH_INTERVAL = 1.hour
  MAX_NAME_LENGTH = 100
  # Where an agent token works: the API, the MCP server, or both. Stored as
  # "api", "mcp" or "api_mcp".
  CHANNELS = %w[api mcp].freeze
  CHANNEL_SETS = %w[api mcp api_mcp].freeze

  belongs_to :user
  belongs_to :project, optional: true
  belongs_to :oauth_access_token, class_name: "Oauth::AccessToken", optional: true
  belongs_to :issuer, class_name: "User", optional: true
  belongs_to :agent_lease, optional: true

  enum :access, { read: "read", read_write: "read_write" }, validate: true

  scope :active, -> { where(expires_at: Time.current..) }
  scope :expired, -> { where(expires_at: ...Time.current) }
  scope :personal, -> { where(oauth_access_token_id: nil, issuer_id: nil) }
  # Each replaces personal, so the user's connection tokens are
  # user.api_tokens.of_connections. They drop any earlier condition on
  # oauth_access_token_id and issuer_id, so narrow by those after them.
  scope :of_connections, -> { unscope(where: %i[oauth_access_token_id issuer_id]).where.not(oauth_access_token_id: nil) }
  scope :of_agents, -> { unscope(where: %i[oauth_access_token_id issuer_id]).where.not(issuer_id: nil) }
  # Agent tokens that people issued: every agent token but run tokens.
  scope :issued_by_people, -> { of_agents.where(agent_lease_id: nil) }

  # Days from creation to expiry; required when a personal token is created.
  attribute :expires_in_days, :integer

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validates :project, presence: true, if: :personal?
  validates :expires_in_days, numericality: { only_integer: true, in: 1..MAX_LIFETIME_DAYS }, on: :create, if: :personal?
  validates :channels, inclusion: { in: CHANNEL_SETS }, if: :agent?
  validate :agent_has_room_for_a_token, on: :create, if: -> { agent? && !run_token? }
  validate :agent_is_not_deleted, on: :create, if: :agent?

  before_create :set_expiry, unless: :connection?

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

  # A new, unsaved token for agent that acts as the agent, issued by a
  # person. Its channels are given as a list: ["api"], ["mcp"] or both.
  def self.issue_for_agent(agent, issuer:, channels: nil, **attributes)
    issue(user_id: agent.user_id, issuer: issuer, **attributes).tap { |api_token| api_token.channel_list = channels }
  end

  # A new, unsaved run token for lease: the leased agent's, issued by the
  # runner's owner, read-write on both channels.
  def self.issue_for_lease(lease)
    issue(user_id: lease.agent_id, issuer: lease.runner.user, agent_lease: lease, name: "Runner #{lease.runner.name}".first(MAX_NAME_LENGTH),
      access: :read_write, channels: "api_mcp")
  end

  def self.digest(value)
    OpenSSL::Digest::SHA256.hexdigest(value)
  end

  def personal?
    !connection? && !agent?
  end

  def connection?
    oauth_access_token_id.present? || oauth_access_token.present?
  end

  def agent?
    issuer_id.present? || issuer.present?
  end

  def run_token?
    agent_lease_id.present? || agent_lease.present?
  end

  def channel_list
    channels.to_s.split("_")
  end

  # Unknown names are kept as they are, so that validation refuses them.
  def channel_list=(names)
    names = Array(names).map(&:to_s)
    self.channels = names.all? { |name| CHANNELS.include?(name) } ? CHANNELS.select { |name| names.include?(name) }.join("_") : names.join("_")
  end

  def channel?(name)
    channel_list.include?(name.to_s)
  end

  # An agent token issued for the API only or for MCP only: the one kind of
  # token for which it matters where a request came from.
  def single_channel?
    agent? && channel_list.one?
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

  private
    # A personal token expires when its user chose, an agent token after
    # AGENT_LIFETIME, whatever was given. A connection token is issued with
    # its access token's expiry.
    def set_expiry
      self.expires_at = agent? ? AGENT_LIFETIME.from_now : expires_in_days.days.from_now
    end

    # An agent has at most MAX_ACTIVE_PER_USER live tokens, whoever issued
    # them. Run tokens do not count.
    def agent_has_room_for_a_token
      return if self.class.issued_by_people.where(user_id: user_id).count < MAX_ACTIVE_PER_USER

      errors.add(:base, :too_many_for_agent, count: MAX_ACTIVE_PER_USER)
    end

    # A deleted agent has no tokens until it is restored.
    def agent_is_not_deleted
      errors.add(:base, :agent_deleted) if Agent.deleted.exists?(user_id: user_id)
    end
end
