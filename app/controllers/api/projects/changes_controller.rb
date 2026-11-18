# Changes (spec changes): listing, creating, opening and updating them. A
# change in a path is named by its id or, when open, by its name
# (Change.find_by_ref!).
class Api::Projects::ChangesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ index show create update ]

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
    change = @project.with_lock { @project.project_changes.create!(name: params[:name], idea: idea_param) }
    render json: ChangeSerializer.new(change), status: :created
  end

  # The idea, the phase, or both (add-change-conversation design.md,
  # decision 3). Under the project's lock, so that a phase move and an
  # import of the same change do not interleave.
  def update
    change = @project.with_lock do
      @project.project_changes.find_by_ref!(params[:id]).tap do |change|
        change.idea = idea_param if params.key?(:idea)
        params.key?(:phase) ? change.move_to!(params[:phase], by: Current.user) : change.save!
      end
    end
    render json: ChangeSerializer.new(change).detail
  end

  private
    # A text, or null for no idea.
    def idea_param
      idea = params[:idea]
      return idea if idea.nil? || idea.is_a?(String)

      raise ActiveRecord::RecordInvalid, Change.new.tap { |change| change.errors.add(:idea, "must be a text") }
    end
end
