require "test_helper"
require "support/fake_room_service"
require "support/live_kit_test_helper"

class ProjectCallTest < ActiveSupport::TestCase
  include LiveKitTestHelper

  setup do
    @rooms = ProjectCall.room_service = FakeRoomService.new
    @project = projects(:goal)
    @call = ProjectCall.new(@project)
  end

  teardown { ProjectCall.room_service = nil }

  test "a member's token joins this project's room only, sends camera and microphone only, and lasts 10 minutes" do
    freeze_time do
      claims = jwt_claims(@call.token_for(users(:two)))

      assert_equal "devkey", claims["iss"]
      assert_equal users(:two).id.to_s, claims["sub"]
      assert_equal "User Two", claims["name"]
      assert_equal 10.minutes.from_now.to_i, claims["exp"]
      assert_equal({ "roomJoin" => true, "room" => "project-#{@project.id}", "canPublish" => true,
                     "canPublishSources" => %w[camera microphone], "canSubscribe" => true, "canPublishData" => false },
        claims["video"])
    end
  end

  test "a token carries no personal data beyond the name" do
    claims = jwt_claims(@call.token_for(users(:two)))

    assert_equal %w[exp iss name nbf sub video], claims.keys.sort
    assert_no_match(/two@example\.com/, claims.to_json)
  end

  test "token_ttl in the settings shortens the token's lifetime" do
    with_livekit(Rails.configuration.x.livekit.merge(token_ttl: 30.seconds)) do
      freeze_time { assert_equal 30.seconds.from_now.to_i, jwt_claims(@call.token_for(users(:one)))["exp"] }
    end
  end

  test "lists only current members, in the order LiveKit lists them" do
    @rooms.join(@call.room, users(:two).id, users(:stranger).id, "not-a-user", users(:one).id)

    assert_equal [ users(:two), users(:one) ], @call.participants
  end

  test "another project's room is not this call" do
    @rooms.join(ProjectCall.new(projects(:side)).room, users(:two).id)

    assert_empty @call.participants
  end

  test "participants are asked from LiveKit at most every 5 seconds" do
    @rooms.join(@call.room, users(:one).id)
    assert_equal [ users(:one) ], @call.participants

    @rooms.join(@call.room, users(:two).id)
    assert_equal [ users(:one) ], @call.participants

    travel 6.seconds
    assert_equal [ users(:one), users(:two) ], @call.participants
  end

  test "no participants while LiveKit cannot be reached" do
    @rooms.join(@call.room, users(:one).id)
    @rooms.unavailable = true

    assert_empty @call.participants
  end

  test "evicts a member and ends the call" do
    @rooms.join(@call.room, users(:one).id, users(:two).id)

    @call.evict(users(:two))
    assert_equal [ [ @call.room, users(:two).id.to_s ] ], @rooms.removed

    @call.close
    assert_equal [ @call.room ], @rooms.deleted
  end

  test "unavailable without a media server: nobody is in the call and nothing is asked" do
    @rooms.join(@call.room, users(:one).id)

    with_livekit(nil) do
      assert_not @call.available?
      assert_empty @call.participants
      @call.evict(users(:one))
      @call.close
    end

    assert_empty @rooms.removed
    assert_empty @rooms.deleted
  end
end
