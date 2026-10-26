# JSON for a personal API token. Never includes the value, only its last four
# characters; the value is added to the creation response alone.
class ApiTokenSerializer
  def initialize(api_token)
    @api_token = api_token
  end

  def as_json(*)
    {
      id: @api_token.id,
      name: @api_token.name,
      project: @api_token.project.slice(:id, :title, :short_name),
      access: @api_token.access,
      last_characters: @api_token.last_characters,
      expires_at: @api_token.expires_at,
      created_at: @api_token.created_at,
      last_used_at: @api_token.last_used_at
    }
  end
end
