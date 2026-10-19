class TaskMailer < ApplicationMailer
  # Names the assigner and the task key and links to the task. Never includes
  # the description or comments (spec notifications, "Assignment email").
  def assigned(task, assigner:)
    @task = task
    @assigner = assigner
    @url = app_url("projects/#{task.project_id}/tasks/#{task.key}")

    I18n.with_locale(task.assignee.lang) do
      mail to: task.assignee.email_address, subject: t("task_mailer.assigned.subject", key: task.key, assigner: assigner.name)
    end
  end
end
