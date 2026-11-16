# Assignment notifications (spec notifications, "Assignment email"). Called
# only after a successful save; sends nothing for self-assignment, when the
# assignee did not change, or when the assignee is an agent. An agent that
# assigns a task to a person is named like any other assigner.
module TaskAssignment
  module_function

  def notify(task, previous_assignee_id:, actor:)
    return if task.assignee_id.nil? || task.assignee_id == previous_assignee_id || task.assignee_id == actor.id
    return if task.assignee.agent?

    TaskMailer.assigned(task, assigner: actor).deliver_later
  end
end
