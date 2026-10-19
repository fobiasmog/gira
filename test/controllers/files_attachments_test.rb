require "test_helper"
require "support/image_files"

# Attachment access control (spec comments, "Attachment access control").
class FilesAttachmentsTest < ActionDispatch::IntegrationTest
  include ImageFiles

  setup do
    @project = projects(:goal)
    task = @project.tasks.create!(title: "t", creator: users(:one), status: statuses(:goal_todo))
    @comment = task.comments.new(author: users(:one), body: "file")
    @comment.attach_uploads([ image_upload(format: "png", filename: "secret.png") ])
    @comment.save!
    @url = file_path(@comment.attachments.first.blob.signed_id)
  end

  test "members download the file as an attachment with nosniff" do
    sign_in_as users(:two)

    get @url

    assert_response :success
    assert_match(/\Aattachment; filename="secret.png"/, response.headers["Content-Disposition"])
    assert_equal "nosniff", response.headers["X-Content-Type-Options"]
  end

  test "former member" do
    @project.remove_member!(users(:two))
    sign_in_as users(:two)

    get @url
    assert_response :not_found
    get file_path(@comment.attachments.first.blob.signed_id, variant: "preview")
    assert_response :not_found
  end

  test "a stranger gets 404" do
    sign_in_as users(:stranger)

    get @url

    assert_response :not_found
  end

  test "signed-out request is not served" do
    get @url

    assert_redirected_to new_session_path
  end

  test "attachments of a deleted comment are no longer served" do
    @comment.soft_delete!
    sign_in_as users(:one)

    get @url

    assert_response :not_found
  end

  test "attachments of an archived project are no longer served" do
    @project.archive!
    sign_in_as users(:one)

    get @url

    assert_response :not_found
  end
end
