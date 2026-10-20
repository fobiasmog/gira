# Serves the single-page application for every path under /app (design.md,
# Decision 5). The SPA loads its data from /api, starting with GET /api/me.
class SpaController < ApplicationController
  layout "spa"
  prepend_before_action :use_dev_server_origin

  def show
  end

  private
    # Development only: the page must share its origin with the Vite dev
    # server, because browsers refuse an SVG sprite (<use href>) from another
    # origin, whatever its CORS headers. Vite passes every path outside /vite/
    # on to Rails, so a request that reached Rails directly (port 3000) is
    # sent to the same path on the dev server. Cookies are shared across ports.
    def use_dev_server_origin
      dev_server = Rails.configuration.x.vite.dev_server
      return unless dev_server

      origin = URI(dev_server)
      return if request.host == origin.host && request.port == origin.port

      redirect_to "#{dev_server}#{request.fullpath}", allow_other_host: true
    end
end
