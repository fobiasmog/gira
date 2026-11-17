# Importing an OpenSpec change's tasks.md into the project's open change of
# that name (spec openspec-changes; add-openspec-changes design.md, decision
# 7). Reading a change back is opening it (Api::Projects::ChangesController).
class Api::Projects::OpenspecChangesController < Api::BaseController
  include ProjectScoped
  allow_token_access only: :create

  # 201 when the import created the change, 200 when the change was open
  # already, and 409 keys_missing with the change's marked text when a
  # re-import carries no mark at all.
  def create
    result = Change::Import.new(project: @project, user: Current.user, name: params[:name], artifacts: artifacts_param).run!
    render json: ChangeSerializer.new(result.change).detail, status: result.created ? :created : :ok
  rescue Change::Import::KeysMissing => error
    render json: { error: { code: "keys_missing", message: MESSAGES.fetch(:keys_missing) }, tasks_text: error.change.current_tasks_text },
      status: :conflict
  end

  private
    # A plain hash of the artifacts sent, or whatever else was sent, which the
    # import refuses.
    def artifacts_param
      artifacts = params[:artifacts]
      artifacts.is_a?(ActionController::Parameters) ? artifacts.to_unsafe_h : artifacts
    end
end
