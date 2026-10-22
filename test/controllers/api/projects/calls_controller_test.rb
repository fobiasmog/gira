require "test_helper"
require "support/fake_room_service"
require "support/live_kit_test_helper"

class Api::Projects::CallsControllerTest < ActionDispatch::IntegrationTest
  include LiveKitTestHelper

  setup do
    @rooms = ProjectCall.room_service = FakeRoomService.new
    @project = projects(:goal)
    sign_in_as users(:one)
  end

  teardown { ProjectCall.room_service = nil }

  test "nobody in the call" do
    get api_project_call_path(@project)

    assert_response :success
    assert_equal({ "available" => true, "participants" => [] }, response.parsed_body)
  end

  test "lists the members in the call with their cards" do
    @rooms.join(ProjectCall.new(@project).room, users(:two).id, users(:stranger).id)

    get api_project_call_path(@project)

    assert_equal [ "User Two" ], response.parsed_body["participants"].map { |p| p["name"] }
    assert_equal %w[avatar_url email_address id name], response.parsed_body["participants"].first.keys.sort
  end

  test "not a member: 404" do
    @rooms.join(ProjectCall.new(projects(:side)).room, users(:two).id)

    get api_project_call_path(projects(:side))

    assert_response :not_found
    assert_no_match(/User Two/, response.body)
  end

  test "archived project: 404" do
    @project.archive!

    get api_project_call_path(@project)

    assert_response :not_found
  end

  test "an unreachable media server: nobody listed, no error" do
    @rooms.join(ProjectCall.new(@project).room, users(:two).id)
    @rooms.unavailable = true

    get api_project_call_path(@project)

    assert_response :success
    assert_equal({ "available" => true, "participants" => [] }, response.parsed_body)
  end

  test "an unreachable real server: nobody listed, no error" do
    ProjectCall.room_service = nil

    with_livekit(url: "ws://127.0.0.1:1", api_key: "devkey", api_secret: "secret") { get api_project_call_path(@project) }

    assert_response :success
    assert_equal({ "available" => true, "participants" => [] }, response.parsed_body)
  end

  test "no media server configured" do
    with_livekit(nil) { get api_project_call_path(@project) }

    assert_response :success
    assert_equal({ "available" => false, "participants" => [] }, response.parsed_body)
  end
end
