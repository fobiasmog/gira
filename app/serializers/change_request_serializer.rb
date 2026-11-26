# JSON for a request for a step of a change (spec change-requests;
# add-change-requests design.md, decision 6): its kind and state, its change
# with the change's reported phase, and who asked for it, took it and
# finished or cancelled it, and when.
#
# users: the users it names, by id, with what their cards need, where the
# caller loaded them for many requests at once.
class ChangeRequestSerializer
  # The users that requests name, with their agents and avatars, by id, in
  # a fixed number of queries.
  def self.users_for(requests, extra_ids: [])
    ids = requests.flat_map { |request| [ request.requested_by_id, request.taken_by_id, request.finished_by_id ] } + extra_ids
    User.where(id: ids.compact.uniq).includes(:agent, avatar_attachment: :blob).index_by(&:id)
  end

  # change: the request's change, which the caller may have at hand.
  def initialize(request, phase:, change: request.change, users: nil)
    @request = request
    @change = change
    @phase = phase
    @users = users || self.class.users_for([ request ])
  end

  def as_json(*)
    { id: @request.id, kind: @request.kind, state: @request.state,
      change: { id: @change.id, name: @change.name, phase: @phase },
      requested_by: card(@request.requested_by_id), taken_by: card(@request.taken_by_id), finished_by: card(@request.finished_by_id),
      created_at: @request.created_at, taken_at: @request.taken_at, finished_at: @request.finished_at }
  end

  private
    def card(id)
      UserSerializer.new(@users.fetch(id)).card if id
    end
end
