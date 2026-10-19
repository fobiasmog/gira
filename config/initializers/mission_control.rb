# The jobs dashboard is restricted by AdminConstraint and AdminController,
# using the application's own sessions instead of HTTP basic auth. Set during
# initialization (not after_initialize) so it is in place before eager
# loading defines Mission Control's controllers.
MissionControl::Jobs.base_controller_class = "AdminController"
MissionControl::Jobs.http_basic_auth_enabled = false
