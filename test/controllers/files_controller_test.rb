require "test_helper"

class FilesControllerTest < ActionDispatch::IntegrationTest
  setup do
    # two shares project "goal" with one; stranger shares nothing with one.
    users(:two).send(:attach_default_avatar)
    @url = file_path(users(:two).avatar.blob.signed_id)
  end

  test "an avatar is served to its owner and to teammates as a download" do
    [ users(:two), users(:one) ].each do |viewer|
      sign_in_as viewer
      get @url

      assert_response :success, viewer.name
      assert_equal "image/png", response.media_type
      assert_match(/\Aattachment;/, response.headers["Content-Disposition"])
      assert_equal "nosniff", response.headers["X-Content-Type-Options"]
    end
  end

  test "a former teammate gets 404" do
    projects(:goal).remove_member!(users(:two))
    sign_in_as users(:one)

    get @url

    assert_response :not_found
  end

  test "a stranger gets 404" do
    sign_in_as users(:stranger)
    users(:stranger).memberships.destroy_all

    get @url

    assert_response :not_found
  end

  test "an anonymous request is not served" do
    get @url

    assert_redirected_to new_session_path
  end

  test "a tampered or unknown file id is 404" do
    sign_in_as users(:one)

    get file_path("not-a-signed-id")
    assert_response :not_found

    get file_path(users(:two).avatar.blob.signed_id, variant: "huge")
    assert_response :not_found
  end
end
