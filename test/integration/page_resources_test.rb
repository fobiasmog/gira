require "test_helper"

# Spec security-baseline, "No third-party scripts or trackers".
class PageResourcesTest < ActionDispatch::IntegrationTest
  PUBLIC_PAGES = %w[/ /?lang=ru /session/new /registration/new /passwords/new /confirmations/new /unlocks/new].freeze

  def external_resources
    css_select("script[src], link[href], img[src], iframe[src], source[src]")
      .map { |node| node["src"] || node["href"] }
      .select { |url| url.match?(%r{\A(?:[a-z]+:)?//}i) }
  end

  test "page resources: every script, stylesheet, font and image comes from the own origin" do
    PUBLIC_PAGES.each do |page|
      get page
      assert_response :success, page
      assert_empty external_resources, page
      assert_no_match(/<script(?![^>]*\bsrc=)[^>]*>|\son[a-z]+=/i, response.body, "#{page} has inline script")
    end

    sign_in_as users(:one)
    get "/app"
    assert_empty external_resources
  end

  test "stylesheets load fonts only from the own origin" do
    Dir[Rails.root.join("app/assets/stylesheets/*.css")].each do |file|
      File.read(file).scan(/url\(([^)]+)\)/).flatten.each do |url|
        assert url.delete(%("')).start_with?("/"), "#{File.basename(file)}: #{url}"
      end
    end
  end
end
