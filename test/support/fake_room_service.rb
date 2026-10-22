# An in-memory stand-in for LiveKit::RoomService (there is no minitest/mock).
# Install it with ProjectCall.room_service = FakeRoomService.new.
class FakeRoomService
  attr_reader :rooms, :removed, :deleted
  attr_accessor :unavailable

  def initialize
    @rooms = Hash.new { |rooms, room| rooms[room] = [] }
    @removed = []
    @deleted = []
    @unavailable = false
  end

  def join(room, *identities)
    rooms[room].concat(identities.map(&:to_s))
  end

  def list_participants(room)
    raise LiveKit::RoomService::Unavailable, "fake outage" if unavailable

    rooms[room].map { |identity| { "identity" => identity, "state" => "ACTIVE" } }
  end

  def remove_participant(room, identity)
    raise LiveKit::RoomService::Unavailable, "fake outage" if unavailable

    @removed << [ room, identity ]
    rooms[room].delete(identity)
    nil
  end

  def delete_room(room)
    raise LiveKit::RoomService::Unavailable, "fake outage" if unavailable

    @deleted << room
    rooms.delete(room)
    nil
  end
end
