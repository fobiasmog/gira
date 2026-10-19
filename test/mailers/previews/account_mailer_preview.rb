# Preview at http://localhost:3000/rails/mailers (add ?locale=ru for Russian).
class AccountMailerPreview < ActionMailer::Preview
  def confirmation = AccountMailer.confirmation(user)
  def attempted_registration = AccountMailer.attempted_registration(user)
  def unlock = AccountMailer.unlock(user)

  private
    def user
      User.new(id: 1, name: "Ada Lovelace", email_address: "ada@example.com", lang: params[:locale] || "en", created_at: Time.current)
    end
end
