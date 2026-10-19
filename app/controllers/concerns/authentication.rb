module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private
    def authenticated?
      resume_session
    end

    def require_authentication
      resume_session || request_authentication
    end

    def resume_session
      Current.session ||= find_session_by_cookie
    end

    # Sessions idle for more than 14 days are ignored (and purged daily by
    # PurgeIdleSessionsJob). Use is recorded at most hourly, and each time the
    # cookie's expiry moves 14 days ahead.
    def find_session_by_cookie
      Session.find_active(cookies.signed[:session_id]).tap do |session|
        if session&.needs_touch?
          session.touch
          set_session_cookie(session)
        end
      end
    end

    def request_authentication
      session[:return_to_after_authenticating] = request.url if request.get? || request.head?
      redirect_to new_session_path
    end

    def after_authentication_url
      session.delete(:return_to_after_authenticating) || app_url
    end

    def start_new_session_for(user)
      # A fresh Rails session (and CSRF token) for the signed-in user, keeping
      # only the page they originally asked for.
      return_to = session[:return_to_after_authenticating]
      reset_session
      session[:return_to_after_authenticating] = return_to if return_to
      user.sessions.create!(user_agent: request.user_agent).tap do |session|
        Current.session = session
        set_session_cookie(session)
      end
    end

    def set_session_cookie(session)
      cookies.signed[:session_id] = {
        value: session.id, expires: Session::IDLE_TIMEOUT, httponly: true, same_site: :lax, secure: request.ssl?
      }
    end

    def terminate_session
      Current.session.destroy
      cookies.delete(:session_id)
    end
end
