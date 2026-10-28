# Projects (spec projects).
class Api::ProjectsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ index show ]
  skip_before_action :set_project, only: %i[ index create ]
  before_action :require_owner!, only: %i[ update destroy ]

  def index
    projects = Current.projects.order(:title)
    render json: projects.map { |project| ProjectSerializer.new(project, viewer: Current.user) }
  end

  def show
    render json: ProjectSerializer.new(@project, viewer: Current.user)
  end

  def create
    project = Project.create!(project_params.merge(owner: Current.user))
    render json: ProjectSerializer.new(project, viewer: Current.user), status: :created
  end

  def update
    @project.update!(project_params)
    render json: ProjectSerializer.new(@project, viewer: Current.user)
  end

  # Archives the project for everyone.
  def destroy
    @project.archive!
    head :no_content
  end

  private
    def project_params
      params.permit(:title, :short_name)
    end
end
