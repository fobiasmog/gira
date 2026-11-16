class Project < ApplicationRecord
  DEFAULT_COLUMNS = [ "To Do", "Work", "Done" ].freeze
  SHORT_NAME_FORMAT = /\A[A-Z][A-Z0-9]{1,9}\z/

  belongs_to :owner, class_name: "User"
  has_many :memberships, dependent: :destroy
  has_many :members, through: :memberships, source: :user
  has_many :statuses, -> { order(:position) }, dependent: :destroy, inverse_of: :project
  has_many :tasks, dependent: :destroy
  # After tasks, which reference them, and before milestones, which they reference.
  has_many :openspec_changes, dependent: :destroy
  has_many :sprints, dependent: :destroy
  has_many :milestones, dependent: :destroy
  has_many :labels, dependent: :destroy
  has_many :invitations, dependent: :destroy
  has_many :api_tokens, dependent: :delete_all

  scope :kept, -> { where(archived_at: nil) }

  validates :title, presence: true, length: { maximum: 100 }
  validates :short_name, format: { with: SHORT_NAME_FORMAT }

  after_create :add_owner_as_member, :create_default_columns

  def owned_by?(user)
    owner_id == user.id
  end

  def member?(user)
    memberships.exists?(user: user)
  end

  # The members to show and choose from: people and agents by name, without
  # deleted agents, whose memberships are only kept so that they can be
  # restored (add-agents design.md, decision 8). Loaded with what their cards need.
  def listed_members
    members.active.with_attached_avatar.includes(:agent).order(:name)
  end

  # Hides the project and its content from every member. The data stays in
  # the database for operators to recover; API tokens for it are deleted, so
  # they stay revoked if it is restored.
  def archive!
    transaction do
      update!(archived_at: Time.current)
      api_tokens.delete_all
    end
  end

  def done_status
    statuses.find_by(done: true)
  end

  def first_status
    statuses.first
  end

  def active_sprint
    sprints.kept.find_by(active: true)
  end

  # Ends a user's membership; tasks assigned to them in this project become
  # unassigned, and their API tokens for it are deleted for good. The owner
  # cannot leave or be removed.
  #
  # An agent is not removed from its only non-archived project, where nobody
  # could see it any more: it is deleted instead (spec agents, "Agents in
  # projects"). Agent tokens name no project, so none is deleted here: those
  # of a removed agent, and those a removed person issued, stop reaching this
  # project through Current#projects.
  def remove_member!(user)
    raise ArgumentError, "the owner cannot leave the project" if owned_by?(user)
    raise Agent::LastProject if user.agent&.last_project?(self)

    transaction do
      tasks.where(assignee: user).update_all(assignee_id: nil, updated_at: Time.current)
      memberships.where(user: user).destroy_all
      api_tokens.where(user: user).delete_all
    end
  end

  # The next task number, taken atomically so concurrent creations never get
  # the same one (design.md, Decision 8). Uncached: the query cache would
  # otherwise replay the first result within a request.
  def next_task_number!
    self.class.uncached do
      self.class.connection.select_value(<<~SQL.squish, "Next task number", [ id ]).to_i
        UPDATE projects SET last_task_number = last_task_number + 1 WHERE id = $1 RETURNING last_task_number
      SQL
    end
  end

  private
    def add_owner_as_member
      memberships.create!(user: owner)
    end

    def create_default_columns
      DEFAULT_COLUMNS.each_with_index do |title, index|
        statuses.create!(title: title, position: index, done: index == DEFAULT_COLUMNS.size - 1)
      end
    end
end
