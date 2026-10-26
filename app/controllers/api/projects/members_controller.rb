# Project members (spec project-membership, "Member list and removal").
class Api::Projects::MembersController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :index
  before_action :require_owner!, only: :destroy

  def index
    members = @project.members.with_attached_avatar.order(:name)
    render json: members.map { |member| UserSerializer.new(member).card }
  end

  # The owner removes a member; their tasks in the project become unassigned.
  def destroy
    member = @project.members.find(params[:id])
    raise Forbidden if @project.owned_by?(member)

    @project.remove_member!(member)
    head :no_content
  end
end
