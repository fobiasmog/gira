# A runner (spec agent-runners; add-runners-and-workspaces design.md,
# decision 1): the credential of a machine that runs agents, owned by the
# person who created it. Its secret proves which machine is calling, and
# lets it lease the agents its owner can see and keep the workspaces of their
# changes, and nothing else: it is no API token, and it never acts as its
# owner.
#
# Only a SHA-256 digest of the secret is stored. The value is readable from
# #secret on the object that issued it, to be shown once. Rotating replaces
# it, and revoking ends the runner for good; both end its leases. A runner is
# never deleted, since its leases and workspaces name it. A password change
# leaves it as it is.
class Runner < ApplicationRecord
  PREFIX = "glnr_runner_"
  MAX_PER_USER = 10
  MAX_NAME_LENGTH = 100
  # last_contact_at is recorded to within this.
  CONTACT_INTERVAL = 1.minute

  belongs_to :user
  has_many :leases, class_name: "AgentLease", dependent: nil
  has_many :workspaces, dependent: nil

  scope :active, -> { where(revoked_at: nil) }

  validates :name, presence: true, length: { maximum: MAX_NAME_LENGTH }
  validate :owner_has_room, on: :create

  attr_reader :secret

  # A new, unsaved runner with a fresh secret: "glnr_runner_" and 40 base58
  # characters, about 234 bits of randomness.
  def self.issue(attributes = {})
    new(attributes).tap(&:generate_secret)
  end

  # The runner that is not revoked with this secret, or nil.
  def self.find_active_by_secret(value)
    return if value.blank? || !value.start_with?(PREFIX)

    active.find_by(token_digest: ApiToken.digest(value))
  end

  def revoked?
    revoked_at.present?
  end

  def generate_secret
    @secret = PREFIX + SecureRandom.base58(40)
    self.token_digest = ApiToken.digest(@secret)
    self.last_characters = @secret.last(4)
  end

  # A new secret, readable from #secret: the old one stops at once, and so
  # does every lease (and run token) it made. The name and the workspaces
  # stay.
  def rotate_secret!
    transaction do
      generate_secret
      save!
      end_leases!
    end
  end

  # Ends the runner and every lease of it, for good.
  def revoke!
    transaction do
      update!(revoked_at: Time.current) unless revoked?
      end_leases!
    end
  end

  # Records contact at most once a minute.
  def touch_contact!
    update_column(:last_contact_at, Time.current) if last_contact_at.nil? || last_contact_at < CONTACT_INTERVAL.ago
  end

  private
    def end_leases!
      leases.unended.find_each(&:end!)
    end

    # A person has at most MAX_PER_USER runners that are not revoked.
    def owner_has_room
      return if user.nil? || self.class.active.where(user_id: user_id).count < MAX_PER_USER

      errors.add(:base, :too_many, count: MAX_PER_USER)
    end
end
