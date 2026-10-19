require "test_helper"

class Api::AnnouncementsControllerTest < ActionDispatch::IntegrationTest
  test "lists undismissed announcements oldest first, and dismissing all leaves other users untouched" do
    travel_to 1.day.from_now do
      first = Announcement.create!(body: "**First**")
      travel 1.minute
      second = Announcement.create!(body: "Second")
      sign_in_as users(:one)

      get api_announcements_path
      assert_equal [ first.id, second.id ], response.parsed_body.map { |a| a["id"] }
      assert_equal "**First**", response.parsed_body.first["body"]

      delete api_announcements_path
      assert_response :no_content
      get api_announcements_path
      assert_empty response.parsed_body

      sign_in_as users(:two)
      get api_announcements_path
      assert_equal 2, response.parsed_body.size
    end
  end

  test "a new account receives the current welcome announcement" do
    Announcement.create!(body: "Old welcome", welcome: true, created_at: 2.days.ago)
    Announcement.create!(body: "Welcome!", welcome: true, created_at: 1.day.ago)
    user = User.create!(name: "New", email_address: "new@example.com", password: "a long password", confirmed_at: Time.current)
    sign_in_as user

    get api_announcements_path

    assert_equal [ "Welcome!" ], response.parsed_body.map { |a| a["body"] }
  end

  test "announcements published before an account existed are not shown to it" do
    Announcement.create!(body: "Ancient news", created_at: 1.year.from_now - 2.years)
    sign_in_as users(:one)

    get api_announcements_path

    assert_empty response.parsed_body
  end
end
