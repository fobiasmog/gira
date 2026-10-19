require "open3"
require "json"

# Boots the app with the production configuration in a separate process and
# performs Rack requests against it, so tests can assert behaviour that only
# exists in production (HTTPS redirect, HSTS, the production CSP). Secrets are
# not needed: SECRET_KEY_BASE_DUMMY skips the required-secrets check, and none
# of the probed paths touch the database.
module ProductionProbe
  SCRIPT = <<~RUBY
    requests = JSON.parse(ARGV.fetch(0))
    results = requests.map do |request|
      status, headers, _body = Rails.application.call(Rack::MockRequest.env_for(request.fetch("url"), request.fetch("env", {})))
      { status: status, headers: headers.to_h }
    end
    puts "PROBE:" + JSON.generate(results)
  RUBY

  def self.request(*requests)
    env = { "RAILS_ENV" => "production", "SECRET_KEY_BASE_DUMMY" => "1",
            "DATABASE_URL" => "postgres://probe@127.0.0.1:1/probe", "RAILS_LOG_LEVEL" => "fatal" }
    out, err, status = Open3.capture3(env, "bin/rails", "runner", SCRIPT, JSON.generate(requests), chdir: Rails.root.to_s)
    raise "production probe failed:\n#{err}" unless status.success?

    JSON.parse(out.lines.grep(/\APROBE:/).last.delete_prefix("PROBE:"))
  end
end
