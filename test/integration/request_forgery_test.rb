require "test_helper"
require "support/forgery_protected_integration_test"
require "support/route_table"

# Cross-cutting checks over the whole route table (spec security-baseline,
# "Cross-site request forgery protection" and "Safe methods never change state").
class RequestForgeryTest < ForgeryProtectedIntegrationTest
  # Actions that GET or HEAD routes may map to. Anything else is assumed to
  # change state and must not be reachable through a safe method.
  READ_ACTIONS = %w[index show new edit].freeze
  READ_ONLY_EXCEPTIONS = [
    "api/base#route_not_found" # catch-all that only renders the 404 envelope
  ].freeze

  # Endpoints that never read the session, so need no CSRF token (spec
  # security-baseline, "Deny by default"). Each is an ActionController::API,
  # which has neither cookies nor a session.
  SESSIONLESS_ENDPOINTS = [
    "oauth/tokens#create", # OAuth token endpoint: codes and refresh tokens from public clients
    "oauth/tokens#revoke", # OAuth revocation endpoint (RFC 7009), for a client's own tokens
    "oauth/registrations#create", # dynamic client registration (RFC 7591), open to anyone
    "internal/mcp_token_exchanges#create" # connection tokens for the MCP server, behind its service key
  ].freeze

  test "every state-changing route rejects a request without a CSRF token" do
    sign_in_as users(:one)
    session_count = Session.count
    checked = 0

    RouteTable.routes.each do |route|
      next if SESSIONLESS_ENDPOINTS.include?(RouteTable.endpoint(route))

      (RouteTable.verbs(route) - %w[GET HEAD]).each do |verb|
        path = RouteTable.sample_path(route)
        process verb.downcase.to_sym, path, params: { title: "forged" }, as: (path.start_with?("/api/") ? :json : nil)

        assert_equal 422, response.status, "#{verb} #{path} (#{RouteTable.endpoint(route)}) " \
          "answered #{response.status} without a CSRF token"
        checked += 1
      end
    end

    assert_operator checked, :>, 0
    assert_equal session_count, Session.count
  end

  test "the endpoints without CSRF protection cannot read the session" do
    routed = RouteTable.routes.map { |route| RouteTable.endpoint(route) }

    SESSIONLESS_ENDPOINTS.each do |endpoint|
      assert_includes routed, endpoint
      controller = "#{endpoint.split("#").first}_controller".camelize.constantize
      assert_operator controller, :<, ActionController::API, endpoint
      assert_not_includes controller.ancestors, ActionController::Cookies, endpoint
    end
  end

  test "a request with a valid CSRF token is accepted" do
    sign_in_as users(:one)
    get new_session_path
    token = css_select("meta[name=csrf-token]").first["content"]

    delete session_path, headers: { "X-CSRF-Token" => token }
    assert_redirected_to root_path
  end

  test "no GET or HEAD route maps to a state-changing action" do
    offenders = RouteTable.routes.filter_map do |route|
      next unless (RouteTable.verbs(route) & %w[GET HEAD]).any?

      endpoint = RouteTable.endpoint(route)
      next if READ_ACTIONS.include?(route.defaults[:action].to_s) || READ_ONLY_EXCEPTIONS.include?(endpoint)

      "#{route.verb} #{route.path.spec} → #{endpoint}"
    end

    assert_empty offenders
  end
end
