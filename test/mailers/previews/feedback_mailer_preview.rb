class FeedbackMailerPreview < ActionMailer::Preview
  def feedback
    FeedbackMailer.feedback(User.new(id: 1, email_address: "ada@example.com"), reason: "bug", message: "The board does not load.")
  end
end
