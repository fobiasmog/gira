require "test_helper"

class RegistrationsControllerTest < ActionDispatch::IntegrationTest
  def register(email_address: "new@example.com", password: "a long password", name: "New Person")
    post registration_path, params: { user: { name: name, email_address: email_address, password: password } }
  end

  test "successful registration creates an unconfirmed account and sends a confirmation email" do
    assert_difference -> { User.count } do
      register
    end

    user = User.find_by!(email_address: "new@example.com")
    assert_not user.confirmed?
    assert_enqueued_email_with AccountMailer, :confirmation, args: [ user ]
    assert_redirected_to new_session_path
    assert_equal I18n.t("registrations.check_email"), flash[:notice]
  end

  test "password too short" do
    assert_no_difference -> { User.count } do
      register password: "a" * 11
    end

    assert_response :unprocessable_content
    assert_select ".errors li", text: /Password is too short/
  end

  test "password too long" do
    assert_no_difference -> { User.count } do
      register password: "a" * 73
    end

    assert_response :unprocessable_content
    assert_select ".errors li", text: /Password is too long/
  end

  test "registering an existing email looks the same as a new registration and warns the owner" do
    register email_address: "fresh@example.com"
    fresh = { status: response.status, location: response.location, notice: flash[:notice] }

    assert_no_difference -> { User.count } do
      register email_address: users(:one).email_address.upcase
    end

    assert_equal fresh, { status: response.status, location: response.location, notice: flash[:notice] }
    assert_enqueued_email_with AccountMailer, :attempted_registration, args: [ users(:one) ]
  end

  test "registering an existing email with an invalid password shows only the password error" do
    register email_address: users(:one).email_address, password: "short"

    assert_response :unprocessable_content
    assert_select ".errors li", count: 1
    assert_select ".errors li", text: /Password/
  end

  test "the account takes the language the visitor used" do
    post registration_path(lang: "ru"), params: { user: { name: "Ива", email_address: "iva@example.com", password: "a long password" } }

    assert_equal "ru", User.find_by!(email_address: "iva@example.com").lang
  end

  test "registration is limited to 5 per hour per IP address" do
    5.times { |i| register email_address: "person#{i}@example.com" }

    assert_no_difference -> { User.count } do
      register email_address: "sixth@example.com"
    end
    assert_response :too_many_requests
    assert_select "h1", I18n.t("shared.rate_limited.title")
  end
end
