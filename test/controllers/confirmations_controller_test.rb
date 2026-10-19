require "test_helper"

class ConfirmationsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:unconfirmed) }

  test "opening the link shows a confirmation button without confirming" do
    get confirmation_path(@user.generate_token_for(:email_confirmation))

    assert_response :success
    assert_not @user.reload.confirmed?
  end

  test "confirming through the link works once" do
    token = @user.generate_token_for(:email_confirmation)

    patch confirmation_path(token)
    assert_redirected_to new_session_path
    assert @user.reload.confirmed?

    patch confirmation_path(token)
    assert_redirected_to new_confirmation_path
  end

  test "expired confirmation link" do
    token = @user.generate_token_for(:email_confirmation)

    travel 25.hours do
      patch confirmation_path(token)
    end

    assert_not @user.reload.confirmed?
    assert_redirected_to new_confirmation_path
    assert_equal I18n.t("confirmations.invalid"), flash[:alert]
  end

  test "a link sent to a previous email address stops working" do
    token = @user.generate_token_for(:email_confirmation)
    @user.update!(email_address: "changed@example.com")

    patch confirmation_path(token)

    assert_not @user.reload.confirmed?
  end

  test "re-sending answers the same whether or not the address has an unconfirmed account" do
    post confirmations_path, params: { email_address: @user.email_address }
    assert_enqueued_email_with AccountMailer, :confirmation, args: [ @user ]
    sent = { location: response.location, notice: flash[:notice] }

    assert_no_enqueued_emails do
      post confirmations_path, params: { email_address: "nobody@example.com" }
      post confirmations_path, params: { email_address: users(:one).email_address }
    end
    assert_equal sent, { location: response.location, notice: flash[:notice] }
  end

  test "re-sending is limited to 5 per hour per IP address" do
    5.times { post confirmations_path, params: { email_address: "nobody@example.com" } }

    assert_no_enqueued_emails do
      post confirmations_path, params: { email_address: @user.email_address }
    end
    assert_response :too_many_requests
  end
end
