# Email confirmation. The emailed link opens a page whose button confirms the
# address, so a GET never changes state (spec security-baseline).
class ConfirmationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { render_rate_limited_page }
  before_action :set_user_by_token, only: %i[ show update ]

  # Form to re-send the confirmation link.
  def new
  end

  # Same response whether or not the address has an unconfirmed account.
  def create
    user = User.find_by(email_address: params[:email_address])
    AccountMailer.confirmation(user).deliver_later if user && !user.confirmed?

    redirect_to new_session_path, notice: t("confirmations.sent")
  end

  def show
  end

  def update
    @user.confirm!
    redirect_to new_session_path, notice: t("confirmations.confirmed")
  end

  private
    def set_user_by_token
      @user = User.find_by_token_for!(:email_confirmation, params[:token])
    rescue ActiveSupport::MessageVerifier::InvalidSignature, ActiveRecord::RecordNotFound
      redirect_to new_confirmation_path, alert: t("confirmations.invalid")
    end
end
