# The OpenSpec change a card or subtask belongs to (spec openspec-changes;
# add-openspec-changes design.md, decision 1). Whether it is a card or an
# item follows from parent_id.
class AddOpenspecChangeToTasks < ActiveRecord::Migration[8.1]
  def change
    add_reference :tasks, :openspec_change, foreign_key: true
  end
end
