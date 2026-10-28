# Loads the project of a project-scoped API request through the current user's
# memberships, narrowed by the API token if any (design.md, Decision 7). A
# missing project, an archived project, a project the user does not belong to
# and one outside the token's reach are all the same 404.
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private
    def set_project
      @project = Current.projects.find(params[:project_id] || params[:id])
    end

    def require_owner!
      raise Api::BaseController::Forbidden unless @project.owned_by?(Current.user)
    end
end
