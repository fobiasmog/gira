# Unlocking an account locked after too many failed sign-ins. The emailed link
# opens a page whose button unlocks the account; a GET never changes state.
class UnlocksController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { render_rate_limited_page }
  before_action :set_user_by_token, only: %i[ show update ]

  # Form to re-send the unlock link.
  def new
  end

  # Same response whether or not the address has a locked account.
  def create
    user = User.find_by(email_address: params[:email_address])
    AccountMailer.unlock(user).deliver_later if user&.locked?

    redirect_to new_session_path, notice: t("unlocks.sent")
  end

  def show
  end

  def update
    @user.unlock!
    redirect_to new_session_path, notice: t("unlocks.unlocked")
  end

  private
    def set_user_by_token
      @user = User.find_by_token_for!(:unlock, params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_unlock_path, alert: t("unlocks.invalid")
    end
end
