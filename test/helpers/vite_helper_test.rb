require "test_helper"

class ViteHelperTest < ActionView::TestCase
  include ApplicationHelper

  MANIFEST = JSON.parse(Rails.root.join("test/fixtures/files/vite/manifest.json").read)

  test "production: stylesheets, the module script and modulepreload for every imported chunk" do
    html = vite_tags(dev_server: nil, manifest: MANIFEST)

    assert_dom_equal <<~HTML.squish, html.squish
      <link rel="stylesheet" href="/vite/assets/application-789aaa.css">
      <link rel="stylesheet" href="/vite/assets/vendor-222ccc.css">
      <script src="/vite/assets/application-abc123.js" type="module"></script>
      <link rel="modulepreload" href="/vite/assets/vendor-def456.js">
      <link rel="modulepreload" href="/vite/assets/shared-111bbb.js">
    HTML
  end

  test "development: the Vite client and the entry from the dev server" do
    html = vite_tags(dev_server: "http://localhost:5173", manifest: nil)

    assert_dom_equal <<~HTML.squish, html.squish
      <script src="http://localhost:5173/vite/@vite/client" type="module"></script>
      <script src="http://localhost:5173/vite/app/frontend/entrypoints/application.ts" type="module"></script>
    HTML
  end

  test "an unknown entry raises" do
    assert_raises(KeyError) { vite_tags("missing.ts", dev_server: nil, manifest: MANIFEST) }
  end

  test "the Sentry DSN tag is emitted only in production and only with a DSN" do
    assert_nil sentry_meta_tag(dsn: "https://k@o0.ingest.sentry.io/1", enabled: false)
    assert_nil sentry_meta_tag(dsn: nil, enabled: true)
    assert_dom_equal '<meta name="sentry-dsn" content="https://k@o0.ingest.sentry.io/1">',
      sentry_meta_tag(dsn: "https://k@o0.ingest.sentry.io/1", enabled: true)
  end
end
