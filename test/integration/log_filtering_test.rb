require "test_helper"

# Spec security-baseline, "Privacy-preserving logs and error tracking".
class LogFilteringTest < ActionDispatch::IntegrationTest
  test "failed sign-in logged: password and email are filtered" do
    output = StringIO.new
    original = ActionController::Base.logger
    ActionController::Base.logger = ActiveSupport::Logger.new(output)

    post session_path, params: { email_address: "victim@example.com", password: "hunter2-secret" }

    log = output.string
    assert_includes log, %("email_address" => "[FILTERED]")
    assert_includes log, %("password" => "[FILTERED]")
    assert_no_match(/victim@example\.com|hunter2-secret/, log)
  ensure
    ActionController::Base.logger = original
  end
end
