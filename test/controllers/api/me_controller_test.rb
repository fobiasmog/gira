require "test_helper"
require "support/image_files"

class Api::MeControllerTest < ActionDispatch::IntegrationTest
  include ImageFiles

  setup do
    @user = users(:one)
    sign_in_as @user
  end

  test "returns the own profile" do
    get api_me_path

    assert_response :success
    assert_equal({ "id" => @user.id, "name" => "User One", "email_address" => "one@example.com", "lang" => "en",
                   "contact_links" => {}, "admin" => false, "avatar_url" => nil }, response.parsed_body)
  end

  test "update name and language" do
    patch api_me_path, params: { name: "Юзер", lang: "ru" }, as: :json

    assert_response :success
    assert_equal [ "Юзер", "ru" ], [ @user.reload.name, @user.lang ]

    patch api_me_path, params: { name: "" }, as: :json
    assert_includes response.parsed_body.dig("error", "fields", "name"), "Имя не может быть пустым"
  end

  test "unsupported language" do
    patch api_me_path, params: { lang: "de" }, as: :json

    assert_response :unprocessable_content
    assert response.parsed_body.dig("error", "fields", "lang").present?
    assert_equal "en", @user.reload.lang
  end

  test "name longer than 100 characters" do
    patch api_me_path, params: { name: "a" * 101 }, as: :json

    assert_response :unprocessable_content
    assert_equal "User One", @user.reload.name
  end

  test "contact links: a partial update keeps the other links" do
    @user.update!(contact_links: { "tg" => "https://t.me/one" })

    patch api_me_path, params: { contact_links: { slack: "https://example.slack.com/team/U1" } }, as: :json

    assert_response :success
    assert_equal({ "tg" => "https://t.me/one", "slack" => "https://example.slack.com/team/U1" }, @user.reload.contact_links)
  end

  test "contact links: an empty value removes the link" do
    @user.update!(contact_links: { "tg" => "https://t.me/one", "vk" => "https://vk.com/one" })

    patch api_me_path, params: { contact_links: { tg: "" } }, as: :json

    assert_equal({ "vk" => "https://vk.com/one" }, @user.reload.contact_links)
  end

  test "contact links: script and non-https URLs are rejected" do
    [ "javascript:alert(1)", "http://t.me/one", "https://#{"a" * 250}.com" ].each do |url|
      patch api_me_path, params: { contact_links: { tg: url } }, as: :json

      assert_response :unprocessable_content, url
      assert response.parsed_body.dig("error", "fields", "contact_links").present?
    end
    assert_equal({}, @user.reload.contact_links)
  end

  test "contact links: unknown services are ignored" do
    patch api_me_path, params: { contact_links: { myspace: "https://myspace.com/one" } }, as: :json

    assert_equal({}, @user.reload.contact_links)
  end

  test "another user's profile cannot be changed" do
    patch api_me_path, params: { id: users(:two).id, name: "Hacked" }, as: :json

    assert_equal "User Two", users(:two).reload.name
  end
end
