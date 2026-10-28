# Personal API tokens (spec api-tokens, "Create a personal API token" and
# "List and revoke tokens"). Not opened to tokens: only a signed-in session
# manages them. Another user's token is a 404.
class Api::Me::ApiTokensController < Api::BaseController
  include PasswordReentry
  rate_limit_per_user to: 10, within: 1.hour, only: :create, scope: "api_tokens"
  before_action :require_reentered_password, only: :create

  def index
    api_tokens = Current.user.api_tokens.active.includes(:project).order(created_at: :desc, id: :desc)
    render json: api_tokens.map { |api_token| ApiTokenSerializer.new(api_token) }
  end

  # After the rate limit and the password: the project, the token limit, then
  # the token's own validations (design.md, decision 10). The value is
  # returned here and never again.
  def create
    project = Current.user.projects.kept.find_by(id: params[:project_id])
    return render_field_error(:project_id, :invalid) unless project
    if Current.user.api_tokens.active.count >= ApiToken::MAX_ACTIVE_PER_USER
      return render_field_error(:base, :too_many, count: ApiToken::MAX_ACTIVE_PER_USER)
    end

    api_token = Current.user.api_tokens.issue(params.permit(:name, :access, :expires_in_days).merge(project: project))
    if api_token.save
      render json: ApiTokenSerializer.new(api_token).as_json.merge(token: api_token.value), status: :created
    else
      render_validation_errors api_token
    end
  end

  def destroy
    Current.user.api_tokens.find(params[:id]).destroy!
    head :no_content
  end

  private
    def render_field_error(attribute, type, **options)
      message = ActiveModel::Error.new(ApiToken.new, attribute, type, **options).full_message
      render_error :unprocessable_content, :validation_failed, fields: { attribute => [ message ] }
    end
end
