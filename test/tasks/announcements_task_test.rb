require "test_helper"

class AnnouncementsTaskTest < ActiveSupport::TestCase
  setup do
    Rails.application.load_tasks if Rake::Task.tasks.empty?
    @task = Rake::Task["announcements:publish"]
    @task.reenable
  end

  test "publishes an announcement from a file" do
    file = Tempfile.new([ "announcement", ".md" ]).tap { |f| f.write("# Hello\n\nNews.") && f.flush }

    with_env("FILE" => file.path, "WELCOME" => "1") do
      assert_output(/Published welcome announcement/) { @task.invoke }
    end

    assert_equal [ "# Hello\n\nNews.", true ], Announcement.last.slice(:body, :welcome).values
  end

  private
    def with_env(values)
      previous = values.to_h { |key, _| [ key, ENV[key] ] }
      values.each { |key, value| ENV[key] = value }
      yield
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
end
