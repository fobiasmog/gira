# Asking for a step of a change (spec change-requests, "Ask for a step";
# add-change-requests design.md, decision 6): explore, propose, implement or
# archive, with an optional comment posted as the asker's, which asks for no
# reply. A waiting reply request gives way to the new request.
class Api::Projects::Changes::RequestsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :create

  def create
    change = @project.project_changes.find_by_ref!(params[:change_id])
    request = ChangeRequest.ask!(change:, kind: params[:kind].to_s, by: Current.user, comment: comment_param)
    render json: ChangeRequestSerializer.new(request, change:, phase: change.phase_reported), status: :created
  end

  private
    # A text, or none.
    def comment_param
      comment = params[:comment]
      return comment if comment.nil? || comment.is_a?(String)

      raise ActiveRecord::RecordInvalid, ChangeRequest.new.tap { |request| request.errors.add(:comment, "must be a text") }
    end
end
