class ApplicationController < ActionController::Base
  include Authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  before_action :set_error_tracking_user
  around_action :switch_locale

  private
    # Error reports identify users by internal id only.
    def set_error_tracking_user
      Sentry.set_user(Current.user ? { id: Current.user.id } : {})
    end

    # Signed-in users get their profile language. Visitors get the language
    # they picked on a public page (?lang=, remembered in a cookie), else the
    # first supported one from Accept-Language, else English.
    def switch_locale(&action)
      I18n.with_locale(current_locale, &action)
    end

    def current_locale
      return Current.user.lang if authenticated?

      if (picked = params[:lang].presence_in(User::LANGUAGES))
        cookies[:lang] = { value: picked, expires: 1.year, same_site: :lax, secure: request.ssl? }
      end

      picked || cookies[:lang].presence_in(User::LANGUAGES) || accepted_language || I18n.default_locale
    end

    def accepted_language
      request.headers["Accept-Language"].to_s.scan(/\b([a-z]{2})(?:-[a-z]{2})?\b/i).flatten
        .map(&:downcase).find { |lang| User::LANGUAGES.include?(lang) }
    end

    # Pages answer an exceeded rate limit with a "try again later" page and
    # HTTP 429; the request is not processed (spec user-auth, "Authentication rate limits").
    def render_rate_limited_page
      render "shared/rate_limited", status: :too_many_requests
    end
end
