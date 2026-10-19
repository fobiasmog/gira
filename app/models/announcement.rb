# An operator announcement in Markdown (spec notifications, "In-app
# announcements"). Published with `bin/rails announcements:publish`.
class Announcement < ApplicationRecord
  has_many :dismissals, class_name: "AnnouncementDismissal", dependent: :delete_all

  validates :body, presence: true, length: { maximum: 10_000 }

  # What a user sees, oldest first: announcements published since they
  # signed up, plus the welcome announcement that was current when they did.
  # Dismissed ones are left out.
  def self.visible_to(user)
    welcome = where(welcome: true).where(created_at: ..user.created_at).order(created_at: :desc).limit(1)
    where(welcome: false).where(created_at: user.created_at..).or(where(id: welcome))
      .where.not(id: AnnouncementDismissal.where(user: user).select(:announcement_id))
      .order(:created_at, :id)
  end

  def self.dismiss_all_for(user)
    rows = visible_to(user).ids.map { |id| { announcement_id: id, user_id: user.id } }
    AnnouncementDismissal.insert_all(rows, unique_by: %i[announcement_id user_id]) if rows.any?
  end
end
