# In-app feedback for the operators (spec feedback).
class Feedback
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :reason, :string
  attribute :message, :string

  validates :reason, presence: true, length: { maximum: 100 }
  validates :message, presence: true, length: { maximum: 5_000 }

  def deliver_from(user)
    return false if invalid?

    FeedbackMailer.feedback(user, reason: reason, message: message).deliver_later
    true
  end
end
