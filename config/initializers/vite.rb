# ViteHelper settings. VITE_DEV_SERVER_HOST also feeds the development CSP.
Rails.application.configure do
  config.x.vite.dev_server = "http://#{ENV.fetch("VITE_DEV_SERVER_HOST", "localhost:5173")}" if Rails.env.development? && ENV["VITE_DEV_SERVER"] != "off"
  config.x.vite.manifest_path = Rails.env.test? ? Rails.root.join("test/fixtures/files/vite/manifest.json") : Rails.root.join("public/vite/.vite/manifest.json")
  config.x.vite.cache_manifest = Rails.env.production?
end
