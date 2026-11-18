require "test_helper"
require "support/image_files"

# Spec comments, "Comment on a change" and "Edit and delete own comments";
# spec changes, "Waiting for people"; add-change-conversation design.md,
# decisions 7 and 8.
class Api::Projects::Changes::CommentsControllerTest < ActionDispatch::IntegrationTest
  include ImageFiles

  setup do
    @project = projects(:goal)
    @change = @project.project_changes.create!(name: "export-csv")
    @fish = create_agent(@project)
    sign_in_as users(:one)
  end

  def fish_headers = @fish_headers ||= bearer(issue_agent_token(@fish, issuer: users(:one)))

  def thread(ref = "export-csv")
    get api_project_change_comments_path(@project, ref)
    response.parsed_body
  end

  def waiting?
    get api_project_change_path(@project, "export-csv")
    response.parsed_body["waiting_for_people"]
  end

  test "thread order: oldest first, each with its author and creation time" do
    post api_project_change_comments_path(@project, "export-csv"), params: { body: "Should archived tasks go into the file?" }, headers: fish_headers, as: :json
    assert_response :created
    travel 1.minute
    post api_project_change_comments_path(@project, "export-csv"), params: { body: "No." }, as: :json
    assert_response :created

    comments = thread
    assert_equal [ [ "Should archived tasks go into the file?", "Fish", true ], [ "No.", "User One", false ] ],
      comments.map { |comment| [ comment["body"], comment.dig("author", "name"), comment.dig("author", "agent") ] }
    assert comments.all? { |comment| comment["created_at"].present? }
    assert_equal [ @change.id ] * 2, Comment.order(:id).pluck(:change_id)
    assert_equal [ nil ] * 2, Comment.order(:id).pluck(:task_id)
  end

  test "agent through its token: the comment is listed with Fish as its author" do
    post api_project_change_comments_path(@project, @change.id), params: { body: "Question" }, headers: fish_headers, as: :json

    assert_response :created
    assert_equal @fish.user, @change.comments.sole.author
    assert_equal [ "Fish" ], thread.map { |comment| comment.dig("author", "name") }
  end

  test "agent asked, then answered: waiting for people until a person replies" do
    assert_equal false, waiting?

    post api_project_change_comments_path(@project, "export-csv"), params: { body: "Archived tasks too?" }, headers: fish_headers, as: :json
    assert_equal true, waiting?

    post api_project_change_comments_path(@project, "export-csv"), params: { body: "No." }, as: :json
    assert_equal false, waiting?
  end

  test "archived change: 422, and its earlier comments are still listed by its id" do
    @change.comments.create!(author: users(:two), body: "Earlier")
    @change.archive!

    assert_no_difference -> { Comment.count } do
      post api_project_change_comments_path(@project, @change.id), params: { body: "Late" }, as: :json
    end

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "base").present?
    assert_equal [ "Earlier" ], thread(@change.id).map { |comment| comment["body"] }
  end

  test "an empty or too long comment: 422, nothing posted" do
    assert_no_difference -> { Comment.count } do
      [ "", "a" * 10_001 ].each do |body|
        post api_project_change_comments_path(@project, "export-csv"), params: { body: }, as: :json
        assert_response :unprocessable_content
      end
    end
  end

  test "attachment on a change comment: listed with name, size and preview, and downloaded only by members" do
    png = image_upload(format: "png", width: 900, height: 900, noise: true, filename: "shot.png")

    post api_project_change_comments_path(@project, "export-csv"), params: { body: "See the screenshot", attachments: [ png ] }

    assert_response :created
    file = thread.sole["attachments"].sole
    assert_equal [ "shot.png", "image/png" ], file.values_at("filename", "content_type")
    assert_operator file["byte_size"], :>, 1.megabyte
    assert file["preview_url"].present?

    sign_in_as users(:two)
    get file["url"]
    assert_response :success
    get file["preview_url"]
    assert_response :success

    sign_in_as users(:stranger)
    get file["url"]
    assert_response :not_found
    get file["preview_url"]
    assert_response :not_found
  end

  test "a refused attachment rejects the whole comment" do
    svg = file_upload("<svg xmlns='http://www.w3.org/2000/svg'/>", "x.svg", "image/svg+xml")

    assert_no_difference -> { Comment.count } do
      post api_project_change_comments_path(@project, "export-csv"), params: { body: "x", attachments: [ svg ] }
    end
    assert_response :unprocessable_content
  end

  test "non-members, and changes of other projects: 404" do
    foreign = projects(:side).project_changes.create!(name: "theirs")
    foreign.comments.create!(author: users(:two), body: "Secret")

    get api_project_change_comments_path(@project, foreign.id)
    assert_response :not_found
    post api_project_change_comments_path(@project, foreign.id), params: { body: "x" }, as: :json
    assert_response :not_found

    sign_in_as users(:stranger)
    get api_project_change_comments_path(@project, "export-csv")
    assert_response :not_found
  end

  # Edit and delete own comments

  test "edit and delete own comment on a change" do
    comment = @change.comments.create!(author: users(:one), body: "Mine")

    patch api_comment_path(comment), params: { body: "Edited" }, as: :json
    assert_response :success
    assert_equal "Edited", comment.reload.body

    delete api_comment_path(comment)
    assert_response :no_content
    assert_empty thread
  end

  test "edit or delete someone else's comment on a change: 404, unchanged" do
    comment = @change.comments.create!(author: @fish.user, body: "Theirs")

    patch api_comment_path(comment), params: { body: "Mine now" }, as: :json
    assert_response :not_found
    delete api_comment_path(comment)
    assert_response :not_found
    assert_equal [ "Theirs", nil ], comment.reload.values_at(:body, :deleted_at)
  end

  test "own comment on a change of a project one has left: 404" do
    comment = @change.comments.create!(author: users(:two), body: "Old")
    @project.remove_member!(users(:two))
    sign_in_as users(:two)

    patch api_comment_path(comment), params: { body: "New" }, as: :json
    assert_response :not_found
    assert_equal "Old", comment.reload.body
  end

  test "a deleted comment no longer counts for waiting" do
    @change.comments.create!(author: @fish.user, body: "?")
    answer = @change.comments.create!(author: users(:one), body: "Yes")

    delete api_comment_path(answer)

    assert_equal true, waiting?
  end
end
