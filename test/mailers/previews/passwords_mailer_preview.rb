class PasswordsMailerPreview < ActionMailer::Preview
  def reset
    PasswordsMailer.reset(User.take || User.new(name: "Ada", email_address: "ada@example.com", lang: params[:locale] || "en"))
  end
end
