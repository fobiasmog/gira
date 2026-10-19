# Leaving a project (spec projects, "Leave a project").
class Api::Projects::MembershipsController < Api::BaseController
  include ProjectScoped

  def destroy
    raise Forbidden if @project.owned_by?(Current.user)

    @project.remove_member!(Current.user)
    head :no_content
  end
end
