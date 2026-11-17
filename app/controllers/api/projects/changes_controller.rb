# Changes (spec changes): listing, creating and opening them. A change in a
# path is named by its id or, when open, by its name (Change.find_by_ref!).
class Api::Projects::ChangesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ index show create ]

  VIEWS = %w[open archived].freeze

  # ?view=open (default): newest first; ?view=archived: most recently
  # archived first.
  def index
    changes = case params.fetch(:view, "open").presence_in(VIEWS)
    when "open" then @project.project_changes.kept.newest_first
    when "archived" then @project.project_changes.archived.order(archived_at: :desc, id: :desc)
    else raise ActiveRecord::RecordNotFound
    end

    render json: ChangeSerializer.list(changes)
  end

  def show
    render json: ChangeSerializer.new(@project.project_changes.find_by_ref!(params[:id])).detail
  end

  # Under the project's lock, as an import is, so that two requests for one
  # name get a validation error rather than the unique index's.
  def create
    change = @project.with_lock { @project.project_changes.create!(name: params[:name]) }
    render json: ChangeSerializer.new(change), status: :created
  end
end
