require "test_helper"
require "support/image_files"

class Api::Me::AvatarsControllerTest < ActionDispatch::IntegrationTest
  include ImageFiles

  setup do
    @user = User.create!(name: "Ava", email_address: "ava@example.com", password: "a long password", confirmed_at: Time.current)
    sign_in_as @user
    @default_avatar = @user.avatar.blob
  end

  test "new accounts get a generated 256×256 default avatar" do
    assert @user.avatar.attached?
    image = Vips::Image.new_from_buffer(@user.avatar.download, "")
    assert_equal [ 256, 256 ], [ image.width, image.height ]
    assert_equal "image/png", @user.avatar.content_type
  end

  test "valid upload: a large JPEG replaces the avatar, re-encoded to WebP of at most 256×256" do
    upload = image_upload(format: "jpg", width: 1400, height: 1000, noise: true)
    assert_operator upload.size, :>, 1.megabyte

    put api_me_avatar_path, params: { avatar: upload }

    assert_response :success
    avatar = @user.reload.avatar
    assert_not_equal @default_avatar, avatar.blob
    assert_equal "image/webp", avatar.content_type
    image = Vips::Image.new_from_buffer(avatar.download, "")
    assert_equal [ 256, 183 ], [ image.width, image.height ]
    assert_equal "/files/#{avatar.blob.signed_id}", response.parsed_body["avatar_url"]
  end

  test "disguised file: SVG or HTML renamed to avatar.png is rejected and the previous avatar kept" do
    [ %(<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>),
      %(<!DOCTYPE html><html><body><script>alert(1)</script></body></html>) ].each do |content|
      put api_me_avatar_path, params: { avatar: file_upload(content, "avatar.png", "image/png") }

      assert_response :unprocessable_content
      assert response.parsed_body.dig("error", "fields", "avatar").present?
      assert_equal @default_avatar, @user.reload.avatar.blob
    end
  end

  test "too large: a 6 MB PNG is rejected and the previous avatar kept" do
    upload = image_upload(format: "png", width: 1500, height: 1500, noise: true)
    assert_operator upload.size, :>, 5.megabytes

    put api_me_avatar_path, params: { avatar: upload }

    assert_response :unprocessable_content
    assert_equal @default_avatar, @user.reload.avatar.blob
  end
end
