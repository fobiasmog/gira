# Takes a user out of a project's call, or ends the call for everybody when no
# user is given (spec team-call, "Losing access ends the call"). A job, so
# requests never wait for the media server; retried through short outages.
class CallEvictionJob < ApplicationJob
  retry_on LiveKit::RoomService::Unavailable, wait: 5.seconds, attempts: 12
  discard_on ActiveJob::DeserializationError

  def perform(project, user = nil)
    call = ProjectCall.new(project)
    return unless call.available?

    user ? call.evict(user) : call.close
  end
end
