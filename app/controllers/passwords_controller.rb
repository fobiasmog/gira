class PasswordsController < ApplicationController
  allow_unauthenticated_access
  before_action :set_user_by_token, only: %i[ edit update ]
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { render_rate_limited_page }

  def new
  end

  # Same response whether or not the address has an account.
  def create
    if user = User.find_by(email_address: params[:email_address])
      PasswordsMailer.reset(user).deliver_later
    end

    redirect_to new_session_path, notice: t("passwords.sent")
  end

  def edit
  end

  # Changing the password invalidates the link (the token is tied to the
  # password salt) and ends every session of the account.
  def update
    if @user.update(params.permit(:password, :password_confirmation).with_defaults(password_confirmation: ""))
      @user.sessions.destroy_all
      redirect_to new_session_path, notice: t("passwords.reset")
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_user_by_token
      @user = User.find_by_password_reset_token!(params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_password_path, alert: t("passwords.invalid")
    end
end
