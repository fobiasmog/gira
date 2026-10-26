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

  test "every state-changing route rejects a request without a CSRF token" do
    sign_in_as users(:one)
    session_count = Session.count
    checked = 0

    RouteTable.routes.each do |route|
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
