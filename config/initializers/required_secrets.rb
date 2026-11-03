# Refuses to boot production when a required secret is missing instead of
# falling back to a default (spec security-baseline, "Secrets management").
# Every key is documented in config/credentials.example.yml.
module RequiredSecrets
  class MissingError < StandardError; end

  # MCP_SERVICE_KEY and MCP_RESOURCE_URL: the connection token exchange and
  # the audience of MCP access tokens (add-mcp-oauth design.md, decision 11).
  ENV_KEYS = %w[DATABASE_URL MCP_SERVICE_KEY MCP_RESOURCE_URL].freeze

  CREDENTIAL_KEYS = [
    %i[smtp address], %i[smtp user_name], %i[smtp password], %i[smtp domain],
    %i[mailer host], %i[mailer from],
    %i[sentry backend_dsn], %i[sentry frontend_dsn],
    %i[feedback operators_email],
    %i[mcp jwt_private_key]
  ].freeze

  def self.missing(env: ENV, credentials: Rails.application.credentials)
    missing = ENV_KEYS.select { |key| env[key].blank? }
    missing << "secret_key_base" if env["SECRET_KEY_BASE"].blank? && credentials.dig(:secret_key_base).blank?
    missing + CREDENTIAL_KEYS.select { |path| credentials.dig(*path).blank? }.map { |path| path.join(".") }
  end

  def self.verify!(**sources)
    missing = missing(**sources)
    return if missing.empty?

    raise MissingError, "Missing required production secrets: #{missing.join(', ')}. " \
      "See config/credentials.example.yml."
  end
end

# The Docker image build precompiles assets with SECRET_KEY_BASE_DUMMY and no secrets.
RequiredSecrets.verify! if Rails.env.production? && ENV["SECRET_KEY_BASE_DUMMY"].blank?
