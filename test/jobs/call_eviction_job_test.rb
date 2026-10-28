require "test_helper"
require "support/fake_room_service"
require "support/live_kit_test_helper"

class CallEvictionJobTest < ActiveJob::TestCase
  include LiveKitTestHelper

  setup do
    @rooms = ProjectCall.room_service = FakeRoomService.new
    @project = projects(:goal)
    @room = ProjectCall.new(@project).room
    @rooms.join(@room, users(:one).id, users(:two).id)
  end

  teardown { ProjectCall.room_service = nil }

  test "takes a member out of the project's call" do
    CallEvictionJob.perform_now(@project, users(:two))

    assert_equal [ [ @room, users(:two).id.to_s ] ], @rooms.removed
    assert_equal [ users(:one).id.to_s ], @rooms.rooms[@room]
  end

  test "without a user, ends the call for everybody" do
    CallEvictionJob.perform_now(@project)

    assert_equal [ @room ], @rooms.deleted
    assert_empty @rooms.removed
  end

  test "does nothing without a media server" do
    with_livekit(nil) do
      CallEvictionJob.perform_now(@project, users(:two))
      CallEvictionJob.perform_now(@project)
    end

    assert_empty @rooms.removed
    assert_empty @rooms.deleted
  end

  test "tries again while the media server cannot be reached" do
    @rooms.unavailable = true

    assert_enqueued_with(job: CallEvictionJob, args: [ @project, users(:two) ]) do
      CallEvictionJob.perform_now(@project, users(:two))
    end

    @rooms.unavailable = false
    perform_enqueued_jobs
    assert_equal [ [ @room, users(:two).id.to_s ] ], @rooms.removed
  end
end
