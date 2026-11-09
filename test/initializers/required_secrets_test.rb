require "test_helper"
require "open3"

class RequiredSecretsTest < ActiveSupport::TestCase
  COMPLETE_CREDENTIALS = {
    secret_key_base: "x" * 64,
    smtp: { address: "smtp.example.com", user_name: "user", password: "secret", domain: "example.com" },
    mailer: { host: "app.example.com", from: "no-reply@example.com" },
    sentry: { backend_dsn: "https://k@o0.ingest.sentry.io/0", frontend_dsn: "https://k@o0.ingest.sentry.io/1" },
    feedback: { operators_email: "operators@example.com" },
    mcp: { jwt_private_key: "-----BEGIN EC PRIVATE KEY-----" }
  }.freeze

  COMPLETE_ENV = { "DATABASE_URL" => "postgres://db/app", "MCP_SERVICE_KEY" => "key", "MCP_RESOURCE_URL" => "https://goalner.com/mcp",
                   "MCP_ISSUER" => "https://goalner.com" }.freeze

  test "nothing is missing when every secret is configured" do
    assert_empty RequiredSecrets.missing(env: COMPLETE_ENV, credentials: COMPLETE_CREDENTIALS)
  end

  test "names each missing secret" do
    credentials = COMPLETE_CREDENTIALS.merge(smtp: COMPLETE_CREDENTIALS[:smtp].except(:password))

    assert_equal %w[DATABASE_URL MCP_SERVICE_KEY MCP_RESOURCE_URL MCP_ISSUER smtp.password], RequiredSecrets.missing(env: {}, credentials: credentials)
  end

  test "names each MCP secret when it is missing" do
    %w[MCP_SERVICE_KEY MCP_RESOURCE_URL MCP_ISSUER].each do |key|
      assert_equal [ key ], RequiredSecrets.missing(env: COMPLETE_ENV.except(key), credentials: COMPLETE_CREDENTIALS)
    end
    assert_equal [ "mcp.jwt_private_key" ], RequiredSecrets.missing(env: COMPLETE_ENV, credentials: COMPLETE_CREDENTIALS.except(:mcp))
  end

  test "the public development service key counts as missing" do
    env = COMPLETE_ENV.merge("MCP_SERVICE_KEY" => "development-mcp-service-key")

    assert_equal [ "MCP_SERVICE_KEY" ], RequiredSecrets.missing(env: env, credentials: COMPLETE_CREDENTIALS)
  end

  test "production refuses to boot without DATABASE_URL" do
    env = { "RAILS_ENV" => "production", "DATABASE_URL" => nil, "SECRET_KEY_BASE_DUMMY" => nil }
    _out, err, status = Open3.capture3(env, "bin/rails", "runner", "puts :booted", chdir: Rails.root.to_s)

    assert_not status.success?
    assert_includes err, "RequiredSecrets::MissingError"
    assert_match(/Missing required production secrets: DATABASE_URL\b/, err)
  end
end
