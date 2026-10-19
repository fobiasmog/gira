module ApplicationHelper
  # The SPA reads its Sentry DSN from this tag. Production only.
  def sentry_meta_tag(dsn: Rails.application.credentials.dig(:sentry, :frontend_dsn), enabled: Rails.env.production?)
    tag.meta(name: "sentry-dsn", content: dsn) if enabled && dsn.present?
  end
end
