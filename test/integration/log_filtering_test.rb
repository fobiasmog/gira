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

  test "token request logged: the token value is not" do
    output = StringIO.new
    loggers = { Rails => Rails.logger, ActionController::Base => ActionController::Base.logger, ActiveRecord::Base => ActiveRecord::Base.logger }
    loggers.each_key { |owner| owner.logger = ActiveSupport::Logger.new(output) }
    headers = { "Authorization" => "Bearer glnr_two_goal_read_write" }

    get api_project_board_path(projects(:goal)), headers: headers
    post api_project_tasks_path(projects(:goal)), params: { title: "Logged" }, headers: headers, as: :json
    get api_project_tasks_path(projects(:goal), token: "glnr_two_goal_read")

    log = output.string
    assert_includes log, "Api::Projects::TasksController#create"
    assert_no_match(/glnr_two_goal_read/, log)
  ensure
    loggers.each { |owner, logger| owner.logger = logger }
  end
end
