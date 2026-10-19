# Browser features the application never uses (spec security-baseline,
# "Transport and browser hardening"). Rails' own `permissions_policy` DSL still
# emits the legacy Feature-Policy header, so the standard header is sent as a
# default header on every response instead.
Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] =
  "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
