# An agent (spec agents; add-agents design.md). An agent is an account of its
# own: a users row, which makes it a member, an assignee, a creator and an
# author like anyone else, with this row beside it. It never signs in and
# acts only through agent tokens (ApiToken.of_agents).
#
# - created_by is information only: it gives that user no rights.
# - Whoever shares a non-archived project with an agent can see and handle
#   it, deleted or not (visible_to).
# - Deleting is soft and keeps memberships, so those members can restore it.
class Agent < ApplicationRecord
  # Removing an agent from its only non-archived project is refused: nobody
  # could see it afterwards (spec agents, "Agents in projects").
  class LastProject < StandardError; end

  # Tries at a free generated address before giving up (design decision 2).
  HANDLE_ATTEMPTS = 5

  belongs_to :user
  belongs_to :created_by, class_name: "User"

  scope :kept, -> { where(deleted_at: nil) }
  scope :deleted, -> { where.not(deleted_at: nil) }
  scope :visible_to, ->(user) { where(user_id: Membership.where(project_id: user.projects.kept.select(:id)).select(:user_id)) }
  scope :of_project, ->(project) { where(user_id: project.memberships.select(:user_id)) }

  delegate :name, to: :user

  class << self
    def email_domain
      Rails.configuration.x.agents.email_domain
    end

    # Whether an address is on the agent domain, where only generated
    # addresses live: people cannot register or be invited with one.
    def reserved_address?(email)
      email.to_s.strip.downcase.end_with?("@#{email_domain}")
    end

    # A new agent that is a member of project at once, without an invitation.
    def create_in!(project, name:, created_by:)
      transaction do
        create_account!(name: name, created_by: created_by).tap { |agent| project.memberships.create!(user: agent.user) }
      end
    end

    private
      # The account never signs in: its password is random and kept nowhere,
      # and it counts as confirmed, so no flow treats it as half-registered.
      # A generated address that is taken is generated again.
      def create_account!(name:, created_by:)
        attempts = 0
        begin
          attempts += 1
          transaction(requires_new: true) do
            user = User.new(name: name, email_address: Handle.generate, password: SecureRandom.base58(64), confirmed_at: Time.current, lang: "en")
            user.build_agent(created_by: created_by)
            user.save!
            user.agent
          end
        rescue ActiveRecord::RecordNotUnique
          attempts < HANDLE_ATTEMPTS ? retry : raise
        rescue ActiveRecord::RecordInvalid => error
          attempts < HANDLE_ATTEMPTS && error.record.errors.of_kind?(:email_address, :taken) ? retry : raise
        end
      end
  end

  def deleted?
    deleted_at.present?
  end

  # Its tokens. User#api_tokens holds personal tokens only, so it is empty
  # for an agent (design decision 5).
  def tokens
    ApiToken.of_agents.where(user_id: user_id)
  end

  # Whether project is the only non-archived project it belongs to.
  def last_project?(project)
    user.projects.kept.where.not(id: project.id).none?
  end

  # Soft deletion (spec agents, "Delete an agent"): its tokens are gone for
  # good and its open tasks are unassigned, in every project. Memberships
  # stay, and done and archived tasks keep it as assignee, for history.
  def delete!
    return if deleted?

    transaction do
      update!(deleted_at: Time.current)
      tokens.delete_all
      Task.kept.not_done.where(assignee_id: user_id).update_all(assignee_id: nil, updated_at: Time.current)
    end
  end

  # Active again in every project it belongs to, with no tokens and no
  # assignments (spec agents, "Restore an agent").
  def restore!
    update!(deleted_at: nil)
  end
end
