# Browser features (spec security-baseline, "Transport and browser hardening"):
# the camera and microphone for calls on the application's own pages only, and
# none of the features the application never uses. Rails' own
# `permissions_policy` DSL still emits the legacy Feature-Policy header, so the
# standard header is sent as a default header on every response instead.
Rails.application.config.action_dispatch.default_headers["Permissions-Policy"] =
  "camera=(self), microphone=(self), geolocation=(), payment=(), usb=()"
