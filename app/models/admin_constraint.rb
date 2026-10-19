# Routing constraint for operational interfaces: matches only requests whose
# signed session cookie belongs to an active session (same idle expiry as
# everywhere else) of an administrator. Everyone else gets no route: 404.
module AdminConstraint
  module_function

  def matches?(request)
    session = Session.find_active(request.cookie_jar.signed[:session_id])
    session&.user&.admin? || false
  end
end
