require "application_system_test_case"

# The consent page in a browser that enforces form-action on the redirect
# that follows a form submission (spec security-baseline, "Consent page form
# action" and "Consent redirect in the browser"; add-mcp-oauth design.md,
# decision 6). The client's loopback redirect URI is this test server under
# its other loopback name, so it is another origin than the consent page.
class OauthConsentSystemTest < ApplicationSystemTestCase
  setup do
    skip "the redirect target must be another loopback name of the test server" if ENV["SELENIUM_REMOTE_URL"]

    @client = Oauth::Application.create!(name: "Local tool", redirect_uri: "http://localhost/robots.txt", registration: "dcr")
    sign_in users(:two).email_address, "correct horse battery"
    @port = Capybara.current_session.server.port
    @redirect_uri = "http://localhost:#{@port}/robots.txt"
    # The browser's log buffer still holds earlier pages' entries.
    page.driver.browser.logs.get(:browser)
  end

  def visit_consent_page
    pkce = Base64.urlsafe_encode64(Digest::SHA256.digest("verifier-" * 6), padding: false)
    visit "/oauth/authorize?" + { response_type: "code", client_id: @client.uid, redirect_uri: @redirect_uri,
      scope: "read write", state: "xyz", code_challenge: pkce, code_challenge_method: "S256" }.to_query
    assert_selector "h1", text: "localhost wants to access your Goalner account"
  end

  def response_policy(path)
    evaluate_async_script(<<~JS, path)
      const [path, done] = arguments
      fetch(path).then((response) => done(response.headers.get("Content-Security-Policy")))
    JS
  end

  def assert_no_policy_violations
    console = page.driver.browser.logs.get(:browser)
    assert_empty console.select { |entry| entry.message.match?(/Content Security Policy|form-action|Refused/i) }.map(&:message)
  end

  test "approving reaches the client's loopback redirect URI with a code" do
    visit_consent_page
    choose "Read and write"
    click_button "Approve"

    assert_current_path %r{\Ahttp://localhost:#{@port}/robots\.txt\?code=[^&]+&state=xyz\z}, url: true
    assert_no_policy_violations
    assert_equal "read write", Oauth::AccessGrant.sole.scopes.to_s
  end

  test "denying reaches the client's loopback redirect URI with access_denied" do
    visit_consent_page
    click_button "Deny"

    assert_current_path %r{\Ahttp://localhost:#{@port}/robots\.txt\?error=access_denied&.*state=xyz}, url: true
    assert_no_policy_violations
    assert_empty Oauth::AccessGrant.all
  end

  test "the consent page allows exactly its own origin and the redirect origin; the sign-in page only its own" do
    visit_consent_page
    page_policy = response_policy(current_url)
    sign_in_policy = response_policy(new_session_path)

    assert_equal [ "'self'", "http://localhost:#{@port}" ], page_policy[/form-action ([^;]+)/, 1].split
    assert_equal [ "'self'" ], sign_in_policy[/form-action ([^;]+)/, 1].split
    assert_no_policy_violations
  end
end
