# Sign-up (spec user-auth, "Email and password registration" and
# "Registration does not reveal existing accounts").
class RegistrationsController < ApplicationController
  allow_unauthenticated_access
  rate_limit to: 5, within: 1.hour, only: :create, with: -> { render_rate_limited_page }

  # ?email= prefills the address, as linked from an invitation.
  def new
    @user = User.new(email_address: params[:email])
  end

  # A new address gets an account and a confirmation email. An address that
  # already has an account gets a warning email to its owner instead. The
  # visitor sees the same "check your email" response either way.
  def create
    @user = User.new(params.expect(user: %i[name email_address password]).merge(lang: I18n.locale))

    if registered_elsewhere?(@user)
      AccountMailer.attempted_registration(User.find_by!(email_address: @user.email_address)).deliver_later
      redirect_to new_session_path, notice: t("registrations.check_email")
    elsif @user.save
      AccountMailer.confirmation(@user).deliver_later
      redirect_to new_session_path, notice: t("registrations.check_email")
    else
      @user.errors.delete(:email_address, :taken) # never reveal that an address is registered
      render :new, status: :unprocessable_content
    end
  rescue ActiveRecord::RecordNotUnique
    redirect_to new_session_path, notice: t("registrations.check_email")
  end

  private
    # True when the only problem with the submission is that the email is taken,
    # so a valid-looking registration for an existing address is not revealed by
    # a validation error.
    def registered_elsewhere?(user)
      return false if user.valid?

      taken = user.errors.where(:email_address, :taken)
      taken.any? && user.errors.size == taken.size
    end
end
