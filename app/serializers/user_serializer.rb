# JSON for a user. The full profile (email, language, contact links) is only
# for the user themself; teammates get the public card.
class UserSerializer
  include Rails.application.routes.url_helpers

  def initialize(user)
    @user = user
  end

  def card
    { id: @user.id, name: @user.name, email_address: @user.email_address, avatar_url: avatar_url }
  end

  def profile
    card.merge(lang: @user.lang, contact_links: @user.contact_links, admin: @user.admin)
  end

  private
    def avatar_url
      file_path(@user.avatar.blob.signed_id) if @user.avatar.attached?
    end
end
