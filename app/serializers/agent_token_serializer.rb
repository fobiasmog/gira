# JSON for an agent token, for everyone who can see the agent (spec agents,
# "List and revoke agent tokens"). Never includes the value, only its last
# four characters; the value is added to the response that issues it alone.
class AgentTokenSerializer
  def initialize(api_token)
    @api_token = api_token
  end

  def as_json(*)
    {
      id: @api_token.id,
      name: @api_token.name,
      issuer: UserSerializer.new(@api_token.issuer).card,
      access: @api_token.access,
      channels: @api_token.channel_list,
      last_characters: @api_token.last_characters,
      created_at: @api_token.created_at,
      last_used_at: @api_token.last_used_at
    }
  end

  # For the response that issues the token: the only time its value is shown.
  # With it, where an MCP client connects (MCP_RESOURCE_URL): the web client
  # cannot tell from its own origin, which in development is another port.
  def with_value
    as_json.merge(token: @api_token.value, mcp_url: Oauth.resource)
  end
end
