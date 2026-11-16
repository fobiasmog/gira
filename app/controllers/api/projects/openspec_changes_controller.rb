# OpenSpec changes (spec openspec-changes; add-openspec-changes design.md,
# decision 7): importing a change's tasks.md, and reading a change by name.
class Api::Projects::OpenspecChangesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: %i[ show create ]

  def show
    render json: change_json(@project.openspec_changes.find_by!(name: params[:name].to_s))
  end

  # 201 for a first import, 200 for a later one, and 409 keys_missing with
  # the change's marked text when a re-import carries no mark at all.
  def create
    result = OpenspecChange::Import.new(project: @project, user: Current.user, name: params[:name], artifacts: artifacts_param).run!
    render json: change_json(result.change), status: result.created ? :created : :ok
  rescue OpenspecChange::Import::KeysMissing => error
    render json: { error: { code: "keys_missing", message: MESSAGES.fetch(:keys_missing) }, tasks: error.change.current_tasks_text },
      status: :conflict
  end

  private
    # A plain hash of the artifacts sent, or whatever else was sent, which the
    # import refuses.
    def artifacts_param
      artifacts = params[:artifacts]
      artifacts.is_a?(ActionController::Parameters) ? artifacts.to_unsafe_h : artifacts
    end

    def change_json(change)
      cards = change.tasks.kept.roots.in_column_order.includes(:project)
      {
        id: change.id,
        name: change.name,
        milestone: change.milestone.slice(:id, :title).merge(change.milestone.progress),
        imported_by: UserSerializer.new(change.imported_by).card,
        imported_at: change.imported_at,
        tasks: change.current_tasks_text,
        cards: TaskSerializer.cards(cards)
      }
    end
end
