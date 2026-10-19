# Assignment notifications (spec notifications, "Assignment email"). Called
# only after a successful save; sends nothing for self-assignment or when the
# assignee did not change.
module TaskAssignment
  module_function

  def notify(task, previous_assignee_id:, actor:)
    return if task.assignee_id.nil? || task.assignee_id == previous_assignee_id || task.assignee_id == actor.id

    TaskMailer.assigned(task, assigner: actor).deliver_later
  end
end
