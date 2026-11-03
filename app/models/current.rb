# The credential of the current request: a session (from the cookie) or an API
# token (from the Authorization header), never both (design.md, decision 3).
class Current < ActiveSupport::CurrentAttributes
  attribute :session, :api_token

  def user
    session&.user || api_token&.user
  end

  # The projects this request may reach: the user's non-archived projects,
  # narrowed to the token's project when a personal token authenticated it.
  # A connection token reaches them all (spec api-tokens, "Token reach is
  # limited to its project").
  def projects
    projects = user.projects.kept
    api_token&.personal? ? projects.where(id: api_token.project_id) : projects
  end
end
