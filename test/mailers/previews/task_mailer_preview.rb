class TaskMailerPreview < ActionMailer::Preview
  def assigned
    lang = params[:locale] || "en"
    project = Project.new(id: 1, title: "Analytical Engine", short_name: "AE")
    task = Task.new(project: project, number: 7, title: "Design the mill", assignee: User.new(name: "Charles", email_address: "charles@example.com", lang: lang))
    TaskMailer.assigned(task, assigner: User.new(name: "Ada Lovelace"))
  end
end
