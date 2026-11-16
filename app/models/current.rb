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
  #
  # An agent token's user is the agent. It reaches the agent's projects that
  # its issuer belongs to as well, as they are at this request, so a token
  # never reaches a project its issuer cannot (spec agents, "Agent token
  # reach"; add-agents design.md, decision 6).
  def projects
    projects = user.projects.kept
    return projects unless api_token

    if api_token.personal?
      projects.where(id: api_token.project_id)
    elsif api_token.agent?
      projects.where(id: api_token.issuer.projects.kept.select(:id))
    else
      projects
    end
  end
end
