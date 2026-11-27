require "test_helper"
require "support/goalner_worker_harness"

# The harness for bin/goalner-worker's tests (add-runners-and-workspaces,
# task 5.1): the worker runs without the app's bundle, against the
# stand-ins.
class GoalnerWorkerHarnessTest < ActiveSupport::TestCase
  include GoalnerWorkerHarness

  test "the worker runs on Ruby's standard library alone, and answers without an agent id" do
    status, output = run_worker

    assert_equal 1, status
    assert_match(/bin\/goalner-worker <agent id>/, output)
    assert_no_match(/bundler|LoadError/i, output)
  end
end
