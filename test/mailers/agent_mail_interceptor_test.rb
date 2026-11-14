require "test_helper"

# Spec agents, "Agents never receive email"; add-agents design.md, decision 3:
# whatever mailer writes to an agent's address, nothing is delivered there.
class AgentMailInterceptorTest < ActionMailer::TestCase
  class ProbeMailer < ApplicationMailer
    def probe(to:, cc: nil, bcc: nil)
      mail(to: to, cc: cc, bcc: bcc, subject: "Probe", body: "probe")
    end
  end

  setup { @agent = create_agent(projects(:goal)) }

  test "a message to an agent is not delivered" do
    [ AccountMailer.unlock(@agent.user), PasswordsMailer.reset(@agent.user), AccountMailer.confirmation(@agent.user),
      AccountMailer.attempted_registration(@agent.user) ].each(&:deliver_now)

    assert_empty ActionMailer::Base.deliveries
  end

  test "an assignment email to an agent is not delivered" do
    task = projects(:goal).tasks.create!(title: "Ship it", creator: users(:one), assignee: @agent.user, status: statuses(:goal_todo))

    TaskMailer.assigned(task, assigner: users(:one)).deliver_now

    assert_empty ActionMailer::Base.deliveries
  end

  test "a message to a person and an agent reaches only the person" do
    ProbeMailer.probe(to: [ "two@example.com", @agent.user.email_address ], cc: @agent.user.email_address,
      bcc: [ @agent.user.email_address.upcase, "one@example.com" ]).deliver_now

    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "two@example.com" ], mail.to
    assert_empty Array(mail.cc)
    assert_equal [ "one@example.com" ], mail.bcc
  end

  test "any address on the agent domain is dropped, whether or not an agent has it" do
    ProbeMailer.probe(to: "nobody-0000@agents.goalner.com").deliver_now

    assert_empty ActionMailer::Base.deliveries
  end

  test "mail to people is delivered as before" do
    ProbeMailer.probe(to: "two@example.com").deliver_now

    assert_equal [ "two@example.com" ], ActionMailer::Base.deliveries.sole.to
  end

  test "only the mailer is logged for a dropped message" do
    output = StringIO.new
    original = Rails.logger
    Rails.logger = ActiveSupport::Logger.new(output)

    ProbeMailer.probe(to: @agent.user.email_address).deliver_now

    assert_includes output.string, "AgentMailInterceptorTest::ProbeMailer"
    assert_not_includes output.string, @agent.user.email_address
  ensure
    Rails.logger = original
  end
end
