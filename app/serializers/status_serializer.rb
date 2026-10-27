# JSON for a board column, the same in the board snapshot, the column list and
# the column change responses (spec project-board).
class StatusSerializer
  def initialize(status)
    @status = status
  end

  def as_json(*)
    @status.slice(:id, :title, :color, :position, :done)
  end
end
