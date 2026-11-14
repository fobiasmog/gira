# JSON for a user. The full profile (email, language, contact links) is only
# for the user themself; teammates get the public card.
#
# Every card says whether the user is an agent and, for an agent, whether it
# is deleted (spec agents, "Agents in API responses"). An agent's generated
# address stands where a person's email address does. Callers that render
# many cards preload :agent.
class UserSerializer
  include Rails.application.routes.url_helpers

  def initialize(user)
    @user = user
  end

  def card
    { id: @user.id, name: @user.name, email_address: @user.email_address, avatar_url: avatar_url,
      agent: @user.agent?, deleted: @user.agent&.deleted? || false }
  end

  def profile
    card.merge(lang: @user.lang, contact_links: @user.contact_links, admin: @user.admin)
  end

  private
    def avatar_url
      file_path(@user.avatar.blob.signed_id) if @user.avatar.attached?
    end
end
