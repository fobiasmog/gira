# Agents for tests (spec agents). They are created through the model rather
# than from fixtures, so the member lists that other tests count stay as they
# are.
module AgentTestHelper
  # An agent in project, created by one of its members.
  def create_agent(project, name: "Fish", created_by: project.owner)
    Agent.create_in!(project, name: name, created_by: created_by)
  end

  # Issues a token for agent as issuer would, and returns its value.
  def issue_agent_token(agent, issuer:, access: :read_write, channels: %w[api mcp], name: "runner")
    ApiToken.issue_for_agent(agent, issuer: issuer, name: name, access: access, channels: channels).tap(&:save!).value
  end

  def bearer(value)
    { "Authorization" => "Bearer #{value}" }
  end

  # Makes Agent::Handle.generate answer addresses first, then real ones.
  def with_handles(*addresses)
    original = Agent::Handle.method(:generate)
    Agent::Handle.define_singleton_method(:generate) { addresses.shift || original.call }
    yield
  ensure
    Agent::Handle.define_singleton_method(:generate, original)
  end
end

ActiveSupport.on_load(:active_support_test_case) do
  include AgentTestHelper
end
