require "test_helper"
require "support/image_files"

class FilesControllerTest < ActionDispatch::IntegrationTest
  include ImageFiles

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

  # With an API token (spec api-tokens, "File downloads with a token"). two
  # has a token for goal and is also a member of side, with stranger.

  def bearer(value = "glnr_two_goal_read")
    { "Authorization" => "Bearer #{value}" }
  end

  def attachment_url(project)
    task = project.tasks.create!(title: "t", creator: users(:two), status: project.first_status)
    comment = task.comments.new(author: users(:two), body: "file")
    comment.attach_uploads([ image_upload(format: "png", filename: "shot.png") ])
    comment.save!
    file_path(comment.attachments.first.blob.signed_id)
  end

  test "a token downloads an attachment in its project" do
    get attachment_url(projects(:goal)), headers: bearer

    assert_response :success
    assert_match(/\Aattachment; filename="shot.png"/, response.headers["Content-Disposition"])
  end

  test "a token gets 404 for an attachment in another project of its owner" do
    get attachment_url(projects(:side)), headers: bearer

    assert_response :not_found
  end

  test "a token downloads the avatars of its project's members, its owner's included" do
    users(:one).send(:attach_default_avatar)

    [ @url, file_path(users(:one).avatar.blob.signed_id) ].each do |url|
      get url, headers: bearer
      assert_response :success
    end
  end

  test "a token gets 404 for a teammate's avatar outside its project" do
    users(:stranger).send(:attach_default_avatar)
    url = file_path(users(:stranger).avatar.blob.signed_id)
    sign_in_as users(:two)
    get url
    assert_response :success, "precondition: the session sees the teammate's avatar"

    get url, headers: bearer

    assert_response :not_found
  end

  test "an invalid token gets 401, even with a session" do
    sign_in_as users(:two)

    get @url, headers: bearer("glnr_unknown")

    assert_response :unauthorized
    assert_empty response.body
  end
end
