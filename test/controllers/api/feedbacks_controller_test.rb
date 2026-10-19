require "test_helper"
require "support/forgery_protected_integration_test"

class Api::FeedbacksControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:one) }

  def send_feedback(reason: "bug", message: "The board does not load.")
    perform_enqueued_jobs do
      post api_feedback_path, params: { reason: reason, message: message }, as: :json
    end
  end

  test "feedback sent to the operators with the user's email as reply-to" do
    send_feedback

    assert_response :accepted
    mail = ActionMailer::Base.deliveries.sole
    assert_equal [ "operators@goalner.test" ], mail.to
    assert_equal [ "one@example.com" ], mail.reply_to
    assert_includes mail.body.decoded, "bug"
    assert_includes mail.body.decoded, "The board does not load."
  end

  test "reason and message lengths" do
    [ { reason: "" }, { reason: "a" * 101 }, { message: "" }, { message: "a" * 5_001 } ].each do |invalid|
      send_feedback(**invalid)
      assert_response :unprocessable_content, invalid.inspect
    end
    assert_empty ActionMailer::Base.deliveries
  end

  test "sixth message within an hour gets 429 and sends nothing" do
    5.times { send_feedback }
    ActionMailer::Base.deliveries.clear

    send_feedback

    assert_response :too_many_requests
    assert_empty ActionMailer::Base.deliveries
  end
end

class Api::FeedbacksCsrfTest < ForgeryProtectedIntegrationTest
  test "missing CSRF token: rejected and no email is sent" do
    sign_in_as users(:one)

    perform_enqueued_jobs do
      post api_feedback_path, params: { reason: "bug", message: "hi" }, as: :json
    end

    assert_response :unprocessable_content
    assert_empty ActionMailer::Base.deliveries
  end
end
