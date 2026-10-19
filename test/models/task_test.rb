require "test_helper"

class TaskTest < ActiveSupport::TestCase
  self.use_transactional_tests = false # the concurrency test needs committed rows visible to two connections

  setup do
    @project = Project.create!(title: "Numbers", short_name: "NUM", owner: users(:one))
  end

  teardown do
    @project.tasks.delete_all
    @project.statuses.delete_all
    @project.memberships.delete_all
    @project.delete
  end

  test "the first task of a project is number 1 and its key uses the short name" do
    task = @project.tasks.create!(title: "First", creator: users(:one))

    assert_equal 1, task.number
    assert_equal "NUM-1", task.key
    assert_equal 2, @project.tasks.create!(title: "Second", creator: users(:one)).number
  end

  test "concurrent creation gets distinct numbers" do
    numbers = 2.times.map do
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          10.times.map { Project.find(@project.id).tasks.create!(title: "t", creator: users(:one)).number }
        end
      end
    end.flat_map(&:value)

    assert_equal (1..20).to_a, numbers.sort
  end
end
