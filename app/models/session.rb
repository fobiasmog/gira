# A signed-in browser (spec user-auth, "Sessions"). Stores the user agent and
# timestamps, never an IP address.
class Session < ApplicationRecord
  IDLE_TIMEOUT = 14.days
  TOUCH_INTERVAL = 1.hour

  belongs_to :user

  scope :active, -> { where(updated_at: IDLE_TIMEOUT.ago..) }
  scope :idle, -> { where(updated_at: ...IDLE_TIMEOUT.ago) }

  def self.find_active(id)
    active.find_by(id: id) if id
  end

  def needs_touch?
    updated_at < TOUCH_INTERVAL.ago
  end
end
