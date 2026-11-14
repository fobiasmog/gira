require "test_helper"

# Spec user-auth, "Agent accounts cannot sign in": each flow answers for an
# agent's address exactly as for an address without an account, and sends
# nothing.
class AgentSignInTest < ActionDispatch::IntegrationTest
  include ActionMailer::TestHelper

  PASSWORD = "a password someone set"

  setup do
    @agent = create_agent(projects(:goal))
    @address = @agent.user.email_address
  end

  def answer
    [ response.status, response.location, flash[:alert], flash[:notice] ]
  end

  test "sign-in is refused like an unknown address, even with a password that matches" do
    @agent.user.update!(password: PASSWORD)
    sign_in_with "nobody@example.com", PASSWORD
    unknown = answer

    sign_in_with @address, PASSWORD

    assert_equal unknown, answer
    assert_equal [ 422, I18n.t("sessions.invalid") ], [ response.status, flash[:alert] ]
    assert_not signed_in?
    assert_empty @agent.user.sessions
  end

  test "ten failed sign-ins neither lock the agent nor send an unlock email" do
    assert_no_enqueued_emails do
      10.times do
        Rails.cache.clear # the sign-in rate limit is not what is tested here
        sign_in_with @address, "wrong password"
      end
    end

    user = @agent.user.reload
    assert_not user.locked?
    assert_equal 0, user.failed_login_attempts
  end

  test "a password reset request gets the same answer as an unknown address and sends nothing" do
    post passwords_path, params: { email_address: "nobody@example.com" }
    unknown = answer

    assert_no_enqueued_emails { post passwords_path, params: { email_address: @address } }

    assert_equal unknown, answer
  end

  test "a reset link for an agent does not open the form or change the password" do
    token = @agent.user.password_reset_token

    get edit_password_path(token)
    assert_redirected_to new_password_path

    put password_path(token), params: { password: PASSWORD, password_confirmation: PASSWORD }
    assert_redirected_to new_password_path
    assert_not @agent.user.reload.authenticate(PASSWORD)
  end

  test "a confirmation link request gets the same answer as an unknown address and sends nothing" do
    @agent.user.update_columns(confirmed_at: nil)
    post confirmations_path, params: { email_address: "nobody@example.com" }
    unknown = answer

    assert_no_enqueued_emails { post confirmations_path, params: { email_address: @address } }

    assert_equal unknown, answer
  end

  test "an unlock link request gets the same answer as an unknown address and sends nothing" do
    @agent.user.update_columns(locked_until: 30.minutes.from_now)
    post unlocks_path, params: { email_address: "nobody@example.com" }
    unknown = answer

    assert_no_enqueued_emails { post unlocks_path, params: { email_address: @address } }

    assert_equal unknown, answer
  end
end
