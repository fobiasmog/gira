# One line of a change's history (spec changes, "Change history";
# add-change-conversation design.md, decision 4): a move to another phase, an
# import with the paths of the files it brought, tasks.md included, the
# release of the change's agent, which it names, or a block for the agent's
# full context (add-change-requests design.md, decisions 4 and 13). Who made
# it is its actor. Being reported in Done is never an event, and requests
# are history of their own (ChangeRequest).
class ChangeEvent < ApplicationRecord
  KINDS = %w[phase import release block].freeze

  belongs_to :change
  belongs_to :actor, class_name: "User"
  # The released agent's user.
  belongs_to :agent, class_name: "User", optional: true

  validates :kind, inclusion: { in: KINDS }
  validates :phase, inclusion: { in: Change::PHASES }, if: -> { kind == "phase" }
  validates :phase, absence: true, unless: -> { kind == "phase" }
  validates :paths, presence: true, if: -> { kind == "import" }
  validates :paths, absence: true, unless: -> { kind == "import" }
  validates :agent, presence: true, if: -> { kind == "release" }
  validates :agent, absence: true, unless: -> { kind == "release" }
end
