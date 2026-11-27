require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
# require "action_mailbox/engine"
# require "action_text/engine"
require "action_view/railtie"
# require "action_cable/engine"
require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Goalner
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    # goalner_worker is bin/goalner-worker's, which runs without the app.
    config.autoload_lib(ignore: %w[assets goalner_worker tasks])

    # Files are only served through FilesController, which checks project
    # membership (design.md, Decision 7). Active Storage's public routes are off.
    config.active_storage.draw_routes = false

    # turbo-rails is only present as a dependency of mission_control-jobs; its
    # Turbo Native navigation routes are not used.
    config.turbo.draw_routes = false

    config.i18n.available_locales = %i[en ru]
    config.i18n.default_locale = :en

    # The public domain Goalner is served from. Test and development defaults
    # of the OAuth issuer and resource derive from it; production sets them
    # with MCP_ISSUER and MCP_RESOURCE_URL (config/deploy.yml).
    config.x.domain = "goalner.com"

    # The domain of agents' generated addresses (spec agents, "Agent
    # accounts"). It accepts no mail: its DNS publishes a null MX record.
    config.x.agents.email_domain = "agents.#{config.x.domain}"

    # How long an agent counts as online after its last check-in, its last
    # take of a request (spec change-requests, "Check-ins"): three minutes
    # unless AGENT_ONLINE_SECONDS says otherwise. bin/goalner-worker takes
    # every 10 seconds while it waits, and every 30 during a run.
    online_seconds = Integer(ENV.fetch("AGENT_ONLINE_SECONDS", "180"), 10)
    raise ArgumentError, "AGENT_ONLINE_SECONDS must be a positive number of seconds" unless online_seconds.positive?
    config.x.agents.online_window = online_seconds.seconds

    # How long a lease of an agent to a runner lives after its last renewal,
    # its run token's last take of a request (spec agent-runners, "Renewing
    # and ending a lease"; add-runners-and-workspaces design.md, decision 2):
    # five minutes unless AGENT_LEASE_SECONDS says otherwise.
    lease_seconds = Integer(ENV.fetch("AGENT_LEASE_SECONDS", "300"), 10)
    raise ArgumentError, "AGENT_LEASE_SECONDS must be a positive number of seconds" unless lease_seconds.positive?
    config.x.agents.lease_window = lease_seconds.seconds

    # How to connect MCP clients: the README's MCP section (McpGuidesController).
    config.x.mcp.guide_url = "https://github.com/fobiasmog/gira#mcp-server"

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
