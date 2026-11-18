# One line of a change's history (spec changes, "Change history";
# add-change-conversation design.md, decision 4): a move to another phase, or
# an import with the paths of the files it brought, tasks.md included. Who
# made it is its actor. Being reported in Done is never an event.
class ChangeEvent < ApplicationRecord
  KINDS = %w[phase import].freeze

  belongs_to :change
  belongs_to :actor, class_name: "User"

  validates :kind, inclusion: { in: KINDS }
  validates :phase, inclusion: { in: Change::PHASES }, if: -> { kind == "phase" }
  validates :phase, absence: true, if: -> { kind == "import" }
  validates :paths, presence: true, if: -> { kind == "import" }
  validates :paths, absence: true, if: -> { kind == "phase" }
end
