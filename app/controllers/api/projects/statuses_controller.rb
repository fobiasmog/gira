# Board columns (spec project-board, "Manage columns" and "Done column").
class Api::Projects::StatusesController < Api::BaseController
  include ProjectScoped
  before_action :set_status, only: %i[ update destroy ]

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
      @project.statuses.reload.map { |status| status.slice(:id, :title, :color, :position, :done) }
    end
end
