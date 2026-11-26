require "test_helper"

# Two agents take a request of one project at the same moment (spec
# change-requests, "Take a request", "Two agents at once"; add-change-requests
# design.md, decision 5). Each takes in its own thread with its own database
# connection, so the test runs outside a transaction and deletes what it
# created.
class RequestClaimRaceTest < ActionDispatch::IntegrationTest
  self.use_transactional_tests = false

  setup do
    @project = projects(:goal)
    @agents = %w[Fish Heron].map { |name| create_agent(@project, name:) }
    @tokens = @agents.map { |agent| issue_agent_token(agent, issuer: users(:one)) }
    @change = @project.project_changes.create!(name: "export-csv")
    ChangeRequest.ask!(change: @change, kind: "explore", by: users(:one))
  end

  teardown do
    user_ids = @agents.map(&:user_id)
    ChangeEvent.where(change: @change).delete_all
    ChangeRequest.where(change: @change).delete_all
    @change.delete
    ApiToken.where(user_id: user_ids).delete_all
    Membership.where(user_id: user_ids).delete_all
    Agent.where(user_id: user_ids).delete_all
    User.where(id: user_ids).delete_all
  end

  test "one of two agents gets the only waiting request, and the other none" do
    go = Queue.new
    threads = @tokens.map do |token|
      Thread.new do
        session = open_session
        go.pop
        session.post claim_api_project_requests_path(@project), headers: bearer(token), as: :json
        [ session.response.status, session.response.parsed_body["request"] ]
      end
    end
    2.times { go << true }
    results = threads.map(&:value)

    assert_equal [ 200, 200 ], results.map(&:first)
    taken = results.map(&:last).compact
    assert_equal 1, taken.size, results.inspect
    winner = @agents.find { |agent| agent.name == taken.sole.dig("taken_by", "name") }
    assert_equal [ winner.user_id, true ], [ @change.reload.agent_id, @change.agent_on? ]
  end
end
