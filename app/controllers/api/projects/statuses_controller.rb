# Board columns (spec project-board, "List columns", "Manage columns" and
# "Done column"). API tokens may only list them (spec api-tokens).
class Api::Projects::StatusesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :index
  before_action :set_status, only: %i[ update destroy ]

  def index
    render json: columns
  end

  def create
    board.add_column(title: params.require(:title))
    render json: columns, status: :created
  end

  # Renames and/or moves a column.
  def update
    board.rename_column(@status, title: params[:title]) if params.key?(:title)
    board.move_column(@status, position: params[:position]) if params.key?(:position)
    render json: columns
  end

  def destroy
    board.delete_column(@status)
    render json: columns
  end

  private
    def board
      Board.new(@project)
    end

    def set_status
      @status = @project.statuses.find(params[:id])
    end

    def columns
      @project.statuses.reload.map { |status| StatusSerializer.new(status) }
    end
end
