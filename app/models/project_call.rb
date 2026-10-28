# A project's call (spec team-call): one LiveKit room per project, joined with
# access tokens the application issues to members only (team-call design.md,
# Decision 5). Calls are available only when a media server is configured in
# config.x.livekit.
class ProjectCall
  PARTICIPANTS_CACHE_TTL = 5.seconds

  # Tests swap in an in-memory fake. Without one, the configured server's API
  # is called.
  class_attribute :room_service, instance_accessor: false

  def self.settings
    Rails.configuration.x.livekit.presence
  end

  def self.identity(user)
    user.id.to_s
  end

  def initialize(project)
    @project = project
  end

  def available?
    settings.present?
  end

  def url
    settings&.dig(:url)
  end

  def room
    "project-#{@project.id}"
  end

  # Valid for this project's call only, for camera and microphone only, and
  # carrying no personal data but the member's name.
  def token_for(user)
    LiveKit::AccessToken.new(
      api_key: settings.fetch(:api_key), api_secret: settings.fetch(:api_secret),
      identity: self.class.identity(user), name: user.name, ttl: settings.fetch(:token_ttl, LiveKit::AccessToken::TTL),
      video: { roomJoin: true, room: room, canPublish: true, canPublishSources: %w[camera microphone],
               canSubscribe: true, canPublishData: false }
    ).to_jwt
  end

  # The project's current members in the call, in the order LiveKit lists
  # them. A stale or foreign identity is never shown. Empty when the media
  # server cannot be asked.
  def participants
    return [] unless available?

    ids = participant_identities.filter_map { |identity| Integer(identity, exception: false) }
    @project.members.with_attached_avatar.where(id: ids).sort_by { |member| ids.index(member.id) }
  end

  # Takes a user out of the call.
  def evict(user)
    room_service&.remove_participant(room, self.class.identity(user))
  end

  # Ends the call for everybody in it.
  def close
    room_service&.delete_room(room)
  end

  private
    def settings
      self.class.settings
    end

    def room_service
      return unless available?

      self.class.room_service || LiveKit::RoomService.new(**settings.slice(:url, :api_key, :api_secret))
    end

    # Cached briefly, so every board polling the call asks LiveKit at most
    # every few seconds per project.
    def participant_identities
      Rails.cache.fetch([ "project_call", @project.id, "identities" ], expires_in: PARTICIPANTS_CACHE_TTL) do
        room_service.list_participants(room).reject { |participant| participant["state"] == "DISCONNECTED" }.pluck("identity")
      end
    rescue LiveKit::RoomService::Unavailable => error
      # Not reported: a development machine without a running LiveKit server
      # would report on every poll.
      Rails.logger.warn("Call participants of project #{@project.id} unavailable: #{error.message}")
      []
    rescue LiveKit::RoomService::Error => error
      Rails.error.report(error, handled: true, source: "project_call")
      []
    end
end
