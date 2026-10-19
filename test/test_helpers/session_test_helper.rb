module SessionTestHelper
  # The password of every user fixture.
  PASSWORD = "correct horse battery"

  def sign_in_as(user)
    Current.session = user.sessions.create!

    ActionDispatch::TestRequest.create.cookie_jar.tap do |cookie_jar|
      cookie_jar.signed[:session_id] = Current.session.id
      cookies["session_id"] = cookie_jar[:session_id]
    end
  end

  # Signs in through the real form.
  def sign_in_with(email_address, password = PASSWORD)
    post session_path, params: { email_address: email_address, password: password }
  end

  def sign_out
    Current.session&.destroy!
    cookies.delete("session_id")
  end

  def signed_in?
    get app_path
    response.successful?
  end
end

ActiveSupport.on_load(:action_dispatch_integration_test) do
  include SessionTestHelper
end
