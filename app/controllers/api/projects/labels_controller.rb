class Api::Projects::LabelsController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ index create ]

  def index
    render json: @project.labels.order(:title).map { |label| label.slice(:id, :title) }
  end

  def create
    label = @project.labels.create!(params.permit(:title))
    render json: label.slice(:id, :title), status: :created
  end
end
