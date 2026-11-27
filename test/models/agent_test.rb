require "test_helper"
require "open3"

# Spec agents, "Agent accounts"; add-agents design.md, decisions 1, 2 and 4.
class AgentTest < ActiveSupport::TestCase
  ADDRESS = /\A[a-z]+-[a-z]+-\d{4}@agents\.goalner\.com\z/

  test "an agent is an account of its own, with a generated address and its creator recorded" do
    agent = create_agent(projects(:goal), name: "Fish", created_by: users(:two))
    user = agent.user

    assert_equal "Fish", user.name
    assert_match ADDRESS, user.email_address
    assert_equal users(:two), agent.created_by
    assert user.agent?
    assert user.confirmed?
    assert_equal "en", user.lang
    assert_not user.admin?
    assert user.avatar.attached?
  end

  test "the agent becomes a member of the project at once" do
    agent = create_agent(projects(:goal))

    assert projects(:goal).member?(agent.user)
    assert_not projects(:side).member?(agent.user)
  end

  test "nobody knows the agent's password" do
    agent = create_agent(projects(:goal))

    assert_not agent.user.authenticate("")
    assert_not agent.user.authenticate(agent.user.email_address)
  end

  test "an invalid name creates nothing" do
    assert_no_difference [ -> { User.count }, -> { Agent.count }, -> { Membership.count } ] do
      error = assert_raises(ActiveRecord::RecordInvalid) { create_agent(projects(:goal), name: "") }
      assert error.record.errors.of_kind?(:name, :blank)
      assert_raises(ActiveRecord::RecordInvalid) { create_agent(projects(:goal), name: "a" * 101) }
    end
  end

  test "a generated address that is taken is generated again" do
    taken = create_agent(projects(:goal)).user.email_address

    agent = with_handles(taken, taken, "calm-owl-0042@agents.goalner.com") { create_agent(projects(:goal), name: "Owl") }

    assert_equal "calm-owl-0042@agents.goalner.com", agent.user.email_address
  end

  test "creation gives up after five taken addresses" do
    taken = create_agent(projects(:goal)).user.email_address

    assert_no_difference -> { User.count } do
      assert_raises(ActiveRecord::RecordInvalid) { with_handles(*[ taken ] * 5) { create_agent(projects(:goal)) } }
    end
  end

  test "generated addresses use the configured agent domain" do
    assert_equal "agents.#{Rails.configuration.x.domain}", Agent.email_domain
    100.times { assert_match ADDRESS, Agent::Handle.generate }
  end

  test "people are not agents" do
    assert_not users(:one).agent?
  end

  test "an agent is never an administrator" do
    user = create_agent(projects(:goal)).user
    user.admin = true

    assert_not user.valid?
    assert user.errors.of_kind?(:admin, :invalid)
  end

  test "addresses on the agent domain are reserved for agents" do
    person = User.new(name: "Ada", email_address: "Ada@Agents.Goalner.com ", password: "a long password")

    assert_not person.valid?
    assert person.errors.of_kind?(:email_address, :reserved)
    assert Agent.reserved_address?("silver-fish-4821@agents.goalner.com")
    assert_not Agent.reserved_address?("fish@goalner.com")
    assert_not Agent.reserved_address?("fish@agents.goalner.com.example")
  end

  test "active users are everyone but deleted agents" do
    kept = create_agent(projects(:goal), name: "Fish")
    deleted = create_agent(projects(:goal), name: "Owl")
    deleted.update!(deleted_at: Time.current)

    active = User.active

    assert_includes active, users(:one)
    assert_includes active, kept.user
    assert_not_includes active, deleted.user
    assert_equal [ "Fish", "User One", "User Two" ], projects(:goal).members.active.order(:name).map(&:name)
  end

  # Decision 4

  test "an agent is visible through a shared non-archived project, deleted or not" do
    fish = create_agent(projects(:goal), name: "Fish")
    owl = create_agent(projects(:side), name: "Owl")
    owl.update!(deleted_at: Time.current)

    assert_equal [ fish ], Agent.visible_to(users(:one)).to_a
    assert_equal [ fish, owl ], Agent.visible_to(users(:two)).order(:id).to_a
    assert_equal [ owl ], Agent.visible_to(users(:stranger)).to_a
    assert_empty Agent.visible_to(users(:unconfirmed))
  end

  test "an agent is not visible through an archived project" do
    fish = create_agent(projects(:side))
    projects(:side).archive!

    assert_empty Agent.visible_to(users(:stranger))
    assert_empty Agent.visible_to(users(:two)).where(id: fish.id)
  end

  test "an agent's creator sees it only through a shared project" do
    fish = create_agent(projects(:side), created_by: users(:stranger))
    projects(:side).remove_member!(users(:stranger))

    assert_not_includes Agent.visible_to(users(:stranger)), fish
    assert projects(:side).member?(fish.user)
  end

  # Decision 8: soft deletion

  test "delete!: tokens are gone, open tasks are unassigned in every project, and memberships and finished work stay" do
    fish = create_agent(projects(:goal), name: "Fish")
    projects(:side).memberships.create!(user: fish.user)
    issue_agent_token(fish, issuer: users(:two))
    open_here = projects(:goal).tasks.create!(title: "Open", creator: users(:one), assignee: fish.user, status: statuses(:goal_work))
    open_there = projects(:side).tasks.create!(title: "Open", creator: users(:two), assignee: fish.user, status: statuses(:side_todo))
    done = projects(:goal).tasks.create!(title: "Done", creator: users(:one), assignee: fish.user, status: statuses(:goal_done))
    archived = projects(:goal).tasks.create!(title: "Archived", creator: users(:one), assignee: fish.user, status: statuses(:goal_todo))
    archived.archive!
    others = projects(:goal).tasks.create!(title: "Bob's", creator: users(:one), assignee: users(:two), status: statuses(:goal_todo))

    freeze_time do
      fish.delete!

      assert_equal Time.current, fish.deleted_at
    end

    assert fish.deleted?
    assert_empty fish.tokens
    assert_equal [ nil, nil ], [ open_here, open_there ].map { |task| task.reload.assignee_id }
    assert_equal [ fish.user.id, fish.user.id, users(:two).id ], [ done, archived, others ].map { |task| task.reload.assignee_id }
    assert projects(:goal).member?(fish.user)
    assert projects(:side).member?(fish.user)
    assert_includes Agent.deleted, fish
    assert_not_includes Agent.kept, fish
  end

  test "restore!: active again, with no tokens and no assignments brought back" do
    fish = create_agent(projects(:goal), name: "Fish")
    issue_agent_token(fish, issuer: users(:two))
    task = projects(:goal).tasks.create!(title: "Open", creator: users(:one), assignee: fish.user, status: statuses(:goal_todo))
    fish.delete!

    fish.restore!

    assert_not fish.reload.deleted?
    assert_empty fish.tokens
    assert_nil task.reload.assignee_id
    assert_includes projects(:goal).listed_members, fish.user
  end

  test "an agent's last project is its only non-archived one" do
    fish = create_agent(projects(:goal))
    assert fish.last_project?(projects(:goal))

    projects(:side).memberships.create!(user: fish.user)
    assert_not fish.last_project?(projects(:goal))

    projects(:side).archive!
    assert fish.last_project?(projects(:goal))
    assert_raises(Agent::LastProject) { projects(:goal).remove_member!(fish.user) }
    assert projects(:goal).member?(fish.user)
  end

  # Check-ins (spec change-requests; add-change-requests design.md, decision 9)

  test "online while the last check-in is younger than the online window, 3 minutes by default" do
    assert_equal 3.minutes, Agent.online_window
    assert Agent.online?(2.minutes.ago)
    assert_not Agent.online?(4.minutes.ago)
    assert_not Agent.online?(nil)
  end

  test "the online window follows the configuration" do
    original = Rails.configuration.x.agents.online_window
    Rails.configuration.x.agents.online_window = 10.minutes

    assert Agent.online?(5.minutes.ago)
    assert_not Agent.online?(11.minutes.ago)
  ensure
    Rails.configuration.x.agents.online_window = original
  end

  test "AGENT_ONLINE_SECONDS sets the online window at boot, and a value that is not a positive number refuses to boot" do
    out, _err, status = Open3.capture3({ "AGENT_ONLINE_SECONDS" => "600" }, "bin/rails", "runner", "puts Agent.online_window.to_i", chdir: Rails.root.to_s)
    assert status.success?
    assert_equal "600", out.strip

    %w[0 -5 3m].each do |value|
      _out, err, status = Open3.capture3({ "AGENT_ONLINE_SECONDS" => value }, "bin/rails", "runner", "puts :booted", chdir: Rails.root.to_s)
      assert_not status.success?, value
      assert_match(/AGENT_ONLINE_SECONDS|invalid value for Integer/, err, value)
    end
  end

  # Agent settings (add-runners-and-workspaces)

  test "set settings: a model and instructions, kept exactly as written" do
    agent = create_agent(projects(:goal))
    instructions = "Keep commits small.\n\n  Ask before adding gems.  "

    agent.update!(model: "opus", instructions:)

    assert_equal [ "opus", instructions ], [ agent.reload.model, agent.instructions ]
    assert agent.update(model: "claude-opus-5-5_x.1")
  end

  test "created with settings, or without: both are optional" do
    heron = Agent.create_in!(projects(:goal), name: "Heron", created_by: users(:one), model: "sonnet", instructions: "Ask before adding gems.")
    fish = create_agent(projects(:goal))

    assert_equal [ "sonnet", "Ask before adding gems." ], [ heron.model, heron.instructions ]
    assert_equal [ nil, nil ], [ fish.model, fish.instructions ]
  end

  test "clear the model and the instructions: empty is unset" do
    agent = create_agent(projects(:goal))
    agent.update!(model: "opus", instructions: "Keep commits small.")

    agent.update!(model: "", instructions: "")
    assert_equal [ nil, nil ], [ agent.reload.model, agent.instructions ]

    agent.update!(model: "opus", instructions: "Keep commits small.")
    agent.update!(model: nil, instructions: nil)
    assert_equal [ nil, nil ], [ agent.reload.model, agent.instructions ]
  end

  test "invalid model or instructions: refused, and the settings are unchanged" do
    agent = create_agent(projects(:goal))
    agent.update!(model: "opus")

    [ "opus 4", "opus[1m]", "модель", "a" * 101 ].each do |model|
      assert_not agent.update(model:), model
      assert agent.errors.include?(:model)
      agent.reload
    end
    assert_not agent.update(instructions: "a" * 10_001)
    agent.reload
    assert agent.update(instructions: "a" * 10_000)
    assert_equal "opus", agent.reload.model
  end

  test "the lease window is 5 minutes unless AGENT_LEASE_SECONDS sets it, and a value that is not a positive number refuses to boot" do
    assert_equal 5.minutes, AgentLease.window

    out, _err, status = Open3.capture3({ "AGENT_LEASE_SECONDS" => "600" }, "bin/rails", "runner", "puts AgentLease.window.to_i", chdir: Rails.root.to_s)
    assert status.success?
    assert_equal "600", out.strip

    _out, err, status = Open3.capture3({ "AGENT_LEASE_SECONDS" => "0" }, "bin/rails", "runner", "puts :booted", chdir: Rails.root.to_s)
    assert_not status.success?
    assert_match(/AGENT_LEASE_SECONDS/, err)
  end
end
