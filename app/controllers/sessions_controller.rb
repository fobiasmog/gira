class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[ new create ]
  rate_limit to: 10, within: 3.minutes, only: :create, with: -> { render_rate_limited_page }

  def new
  end

  # Unknown email, wrong password and locked account all get the same error.
  # authenticate_by takes comparable time whether or not the email exists.
  # An agent's address is answered like an unknown one, whatever the
  # password, and its failures are not counted: agents never sign in (spec
  # user-auth, "Agent accounts cannot sign in").
  def create
    credentials = params.permit(:email_address, :password)

    if (user = User.authenticate_by(credentials)) && !user.agent?
      sign_in_verified user
    else
      User.find_person_by_email(credentials[:email_address])&.register_failed_sign_in!
      refuse_sign_in
    end
  end

  def destroy
    terminate_session
    redirect_to root_path, status: :see_other
  end

  private
    def sign_in_verified(user)
      if user.locked?
        refuse_sign_in
      elsif !user.confirmed?
        redirect_to new_confirmation_path, alert: t("sessions.unconfirmed")
      else
        user.reset_failed_sign_ins!
        start_new_session_for user
        redirect_to after_authentication_url
      end
    end

    def refuse_sign_in
      flash.now[:alert] = t("sessions.invalid")
      render :new, status: :unprocessable_content
    end
end
