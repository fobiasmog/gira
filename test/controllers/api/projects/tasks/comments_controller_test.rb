require "test_helper"
require "support/image_files"

class Api::Projects::Tasks::CommentsControllerTest < ActionDispatch::IntegrationTest
  include ImageFiles
  include PdfFiles

  setup do
    @project = projects(:goal)
    @task = @project.tasks.create!(title: "t", creator: users(:one), status: statuses(:goal_todo))
    sign_in_as users(:one)
  end

  def post_comment(body, attachments: nil)
    params = { body: body }
    params[:attachments] = attachments if attachments
    post api_project_task_comments_path(@project, @task), params: params
  end

  test "add a comment: it is listed first with the exact text, author and time" do
    @task.comments.create!(author: users(:two), body: "older")

    post_comment "Looks good, see **notes**"
    assert_response :created

    get api_project_task_comments_path(@project, @task)
    first = response.parsed_body.first
    assert_equal "Looks good, see **notes**", first["body"]
    assert_equal "User One", first.dig("author", "name")
    assert first["created_at"].present?
    assert_equal [ "Looks good, see **notes**", "older" ], response.parsed_body.map { |c| c["body"] }
  end

  test "raw HTML in a comment is returned verbatim" do
    post_comment "<img src=x onerror=alert(1)>"

    assert_equal "<img src=x onerror=alert(1)>", response.parsed_body["body"]
  end

  test "empty comment" do
    assert_no_difference -> { Comment.count } do
      post_comment ""
    end
    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "body").present?
  end

  test "comment longer than 10,000 characters" do
    post_comment "a" * 10_001

    assert_response :unprocessable_content
  end

  test "edit someone else's comment" do
    comment = @task.comments.create!(author: users(:two), body: "theirs")

    patch api_comment_path(comment), params: { body: "mine now" }, as: :json
    assert_response :not_found
    delete api_comment_path(comment)
    assert_response :not_found
    assert_equal [ "theirs", nil ], [ comment.reload.body, comment.deleted_at ]
  end

  test "edit and delete own comment" do
    comment = @task.comments.create!(author: users(:one), body: "draft")

    patch api_comment_path(comment), params: { body: "final" }, as: :json
    assert_equal "final", comment.reload.body

    delete api_comment_path(comment)
    assert_response :no_content
    get api_project_task_comments_path(@project, @task)
    assert_empty response.parsed_body
  end

  test "a former member cannot edit their old comments" do
    comment = @task.comments.create!(author: users(:two), body: "old")
    @project.remove_member!(users(:two))
    sign_in_as users(:two)

    patch api_comment_path(comment), params: { body: "edited" }, as: :json

    assert_response :not_found
  end

  test "allowed files: a PDF and a PNG are attached with name, size and preview" do
    pdf = file_upload(pdf_bytes(padding: 3.megabytes), "report.pdf", "application/octet-stream")
    png = image_upload(format: "png", width: 600, height: 600, noise: true, filename: "shot.png")

    post_comment "files", attachments: [ pdf, png ]

    assert_response :created
    files = response.parsed_body["attachments"].sort_by { |a| a["filename"] }
    assert_equal [ "report.pdf", "shot.png" ], files.map { |f| f["filename"] }
    assert_equal [ "application/pdf", "image/png" ], files.map { |f| f["content_type"] }
    assert_operator files.first["byte_size"], :>, 3.megabytes
    assert files.all? { |f| f["preview_url"].present? }

    files.each do |file|
      get file["preview_url"]
      assert_response :success, file["filename"]
      assert_equal "image/webp", response.media_type
      assert_operator Vips::Image.new_from_buffer(response.body, "").width, :<=, 400
    end
  end

  test "plain text and CSV are accepted" do
    post_comment "data", attachments: [ file_upload("hello\n", "notes.txt", "text/plain"),
                                        file_upload("a,b\n1,2\n", "table.csv", "text/csv") ]

    assert_response :created
    assert_equal %w[text/csv text/plain], response.parsed_body["attachments"].map { |a| a["content_type"] }.sort
  end

  test "rejected type: SVG or HTML rejects the whole comment, naming the file" do
    { "logo.svg" => %(<svg xmlns="http://www.w3.org/2000/svg"></svg>),
      "page.html" => %(<!DOCTYPE html><html><body>hi</body></html>),
      "renamed.png" => %(<!DOCTYPE html><html><body>hi</body></html>) }.each do |filename, content|
      assert_no_difference -> { Comment.count } do
        post_comment "with #{filename}", attachments: [ file_upload(content, filename, "image/png") ]
      end
      assert_response :unprocessable_content
      assert_match filename, response.parsed_body.dig("error", "fields", "attachments").join
    end
    assert_equal 0, ActiveStorage::Blob.count
  end

  test "too many files" do
    files = 11.times.map { |i| file_upload("note #{i}", "n#{i}.txt", "text/plain") }

    assert_no_difference -> { Comment.count } do
      post_comment "many", attachments: files
    end
    assert_response :unprocessable_content
  end

  test "a file over 10 MB is rejected" do
    assert_no_difference -> { Comment.count } do
      post_comment "big", attachments: [ file_upload(pdf_bytes(padding: 10.megabytes + 1), "big.pdf", "application/pdf") ]
    end
    assert_response :unprocessable_content
  end

  test "comments cannot be added to an archived task, but remain readable" do
    @task.comments.create!(author: users(:one), body: "before")
    @task.archive!

    post_comment "after"
    assert_response :unprocessable_content

    get api_project_task_comments_path(@project, @task)
    assert_equal [ "before" ], response.parsed_body.map { |c| c["body"] }
  end

  test "non-members cannot read or post comments" do
    sign_in_as users(:stranger)

    get api_project_task_comments_path(@project, @task)
    assert_response :not_found
    post_comment "hi"
    assert_response :not_found
  end
end
