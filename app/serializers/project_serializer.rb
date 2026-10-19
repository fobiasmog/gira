class ProjectSerializer
  def initialize(project, viewer:)
    @project = project
    @viewer = viewer
  end

  def as_json(*)
    {
      id: @project.id,
      title: @project.title,
      short_name: @project.short_name,
      owner_id: @project.owner_id,
      owned_by_me: @project.owned_by?(@viewer)
    }
  end
end
