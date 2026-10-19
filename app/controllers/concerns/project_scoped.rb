# Loads the project of a project-scoped API request through the current user's
# memberships (design.md, Decision 7). A missing project, an archived project
# and a project the user does not belong to are all the same 404.
module ProjectScoped
  extend ActiveSupport::Concern

  included do
    before_action :set_project
  end

  private
    def set_project
      @project = Current.user.projects.kept.find(params[:project_id] || params[:id])
    end

    def require_owner!
      raise Api::BaseController::Forbidden unless @project.owned_by?(Current.user)
    end
end
