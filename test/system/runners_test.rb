require "application_system_test_case"

# Spec web-client, "Runners screen" and "Screens" ("Runners entry"); spec
# agent-runners, "Runners" and "List, rotate and revoke runners". one is a
# member of goal.
class RunnersTest < ApplicationSystemTestCase
  PASSWORD = "correct horse battery"

  setup do
    @user = users(:one)
    sign_in @user.email_address, PASSWORD
  end

  def visit_runners
    visit "/app/settings/runners"
    assert_selector "h2", text: "Your runners"
  end

  test "runners entry: the settings include Runners" do
    visit "/app/settings/profile"

    click_link "Runners"

    assert_current_path "/app/settings/runners"
    assert_text "You have no runners yet."
  end

  test "create and copy: the secret is shown once with a copy control, a warning and the register command, and the runner is listed" do
    visit_runners

    fill_in "Runner name", with: "laptop"
    fill_in "Current password", with: PASSWORD
    click_button "Create runner"

    assert_text "Copy the secret now. It will not be shown again."
    secret = find_field("Runner secret").value
    assert_match(/\Aglnr_runner_\w{40}\z/, secret)
    assert_field "Register command", with: "bin/goalner-worker register --url #{evaluate_script('location.origin')} --token #{secret}"
    execute_script("navigator.clipboard.writeText = async (text) => { window.__copied = text }")
    click_button "Copy secret"
    assert_equal secret, evaluate_script("window.__copied")
    click_button "Copy command"
    assert_equal find_field("Register command").value, evaluate_script("window.__copied")

    within(".runners") do
      assert_text "laptop"
      assert_text "Secret ends in #{secret.last(4)}"
      assert_text "never contacted Goalner"
      assert_text "Runs no agent"
    end
    assert_equal Runner.find_active_by_secret(secret), @user.runners.sole

    visit "/app/settings/profile"
    visit_runners
    assert_no_field "Runner secret"
    assert_no_text secret
  end

  test "wrong password: the error is under the password field and the name keeps its value" do
    visit_runners

    fill_in "Runner name", with: "laptop"
    fill_in "Current password", with: "wrong password"
    click_button "Create runner"

    assert_invalid_field "Current password"
    assert_field "Runner name", with: "laptop"
    assert_empty @user.runners
  end

  test "list: the agents a runner runs now and its last contact" do
    runner = Runner.issue(user: @user, name: "laptop").tap(&:save!)
    runner.touch_contact!
    AgentLease.lease!(agent: create_agent(projects(:goal), name: "Fish"), runner:)

    visit_runners

    within(".runner", text: "laptop") do
      assert_text "Runs Fish"
      assert_text "last contact"
    end
  end

  test "rotate a running runner's secret: the dialog says Fish will stop, and the new secret is shown once with the register command" do
    runner = Runner.issue(user: @user, name: "laptop").tap(&:save!)
    old_secret = runner.secret
    lease = AgentLease.lease!(agent: create_agent(projects(:goal), name: "Fish"), runner:)
    visit_runners

    click_button "Rotate the secret of laptop"
    within("dialog[open]") do
      assert_text "Fish will stop."
      fill_in "Current password", with: "wrong password"
      click_button "Rotate secret"
      assert_invalid_field "Current password"
      fill_in "Current password", with: PASSWORD
      click_button "Rotate secret"

      assert_text "Copy the secret now. It will not be shown again."
      secret = find_field("Runner secret").value
      assert_match(/\Aglnr_runner_\w{40}\z/, secret)
      assert_field "Register command", with: /--token #{secret}\z/
      click_button "Done"
    end

    within(".runner", text: "laptop") { assert_text "Runs no agent" }
    assert_nil Runner.find_active_by_secret(old_secret)
    assert lease.reload.ended?
  end

  test "revoke a running runner: the confirmation says Fish will stop, and the runner disappears from the list" do
    runner = Runner.issue(user: @user, name: "laptop").tap(&:save!)
    AgentLease.lease!(agent: create_agent(projects(:goal), name: "Fish"), runner:)
    visit_runners

    click_button "Revoke laptop"
    within("dialog[open]") do
      assert_text "Revoke laptop? Its secret stops working for good. Fish will stop."
      click_button "Revoke"
    end

    assert_text "Runner “laptop” revoked"
    assert_text "You have no runners yet."
    assert runner.reload.revoked?
  end

  test "the password change form says that runners keep working" do
    visit "/app/settings/security"

    assert_text "Your runners keep working"
  end
end
