# Integration tests that run with CSRF protection switched on, as in
# production. The test environment disables it for every other test.
class ForgeryProtectedIntegrationTest < ActionDispatch::IntegrationTest
  setup do
    @original_allow_forgery_protection = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
  end

  teardown do
    ActionController::Base.allow_forgery_protection = @original_allow_forgery_protection
  end
end
