# The application's own routes, with a request path and the verbs for each,
# for tests that check every route (CSRF protection, API token access).
module RouteTable
  def self.routes
    Rails.application.routes.routes.reject { |route| route.internal || route.app.engine? }
  end

  def self.sample_path(route)
    route.path.spec.to_s
      .sub("(.:format)", "")
      .gsub(/\*\w+/, "anything")
      .gsub(/:\w+/, "1")
  end

  def self.verbs(route)
    route.verb.to_s.split("|").reject(&:empty?).presence || %w[GET POST PUT PATCH DELETE]
  end

  def self.endpoint(route)
    "#{route.defaults[:controller]}##{route.defaults[:action]}"
  end
end
