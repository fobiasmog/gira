require "test_helper"

class AdminJobsTest < ActionDispatch::IntegrationTest
  test "an administrator gets the jobs dashboard" do
    users(:one).update!(admin: true)
    sign_in_with users(:one).email_address

    get "/admin/jobs"
    follow_redirect! while response.redirect?

    assert_response :success
    assert_includes response.body, "Mission control"
    assert_match(/script-src 'self' 'nonce-/, response.headers["Content-Security-Policy"])
  end

  test "non-admin opens jobs dashboard: 404" do
    sign_in_with users(:one).email_address

    get "/admin/jobs"

    assert_response :not_found
  end

  test "an anonymous visitor gets 404" do
    get "/admin/jobs"

    assert_response :not_found
  end

  test "an admin whose session went idle gets 404" do
    users(:one).update!(admin: true)
    sign_in_with users(:one).email_address

    travel 15.days do
      get "/admin/jobs"
      assert_response :not_found
    end
  end

  test "regular pages keep the nonce-free policy" do
    get root_path

    assert_no_match(/nonce/, response.headers["Content-Security-Policy"])
  end
end
