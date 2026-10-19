# Serves the single-page application for every path under /app (design.md,
# Decision 5). The SPA loads its data from /api, starting with GET /api/me.
class SpaController < ApplicationController
  layout "spa"

  def show
  end
end
