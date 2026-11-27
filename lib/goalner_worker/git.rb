require "open3"

module GoalnerWorker
  # The git commands the worker needs, run in a given directory.
  module Git
    module_function

    def run(directory, *args)
      output, status = Open3.capture2e("git", "-C", directory, *args)
      [ output, status.success? ]
    end

    # The top of the working copy that holds directory, or nil.
    def toplevel(directory)
      return unless File.directory?(directory)

      output, ok = run(directory, "rev-parse", "--show-toplevel")
      File.realpath(output.strip) if ok
    end

    def branch?(clone, branch)
      run(clone, "rev-parse", "--verify", "--quiet", "refs/heads/#{branch}").last
    end

    def commit?(clone, ref)
      run(clone, "rev-parse", "--verify", "--quiet", "#{ref}^{commit}").last
    end

    # The branch checked out in each worktree of clone's repository, by path.
    def worktrees(clone)
      output, ok = run(clone, "worktree", "list", "--porcelain")
      return {} unless ok

      output.split("\n\n").to_h do |entry|
        lines = entry.lines.map(&:chomp)
        path = lines.find { |line| line.start_with?("worktree ") }&.delete_prefix("worktree ")
        branch = lines.find { |line| line.start_with?("branch ") }&.delete_prefix("branch refs/heads/")
        [ path && real(path), branch ]
      end
    end

    def worktree_of?(clone, path, branch)
      worktrees(clone)[real(path)] == branch
    end

    def head(directory)
      output, ok = run(directory, "rev-parse", "HEAD")
      output.strip if ok
    end

    def uncommitted?(directory)
      output, ok = run(directory, "status", "--porcelain")
      !ok || !output.strip.empty?
    end

    # The main working copy of the repository that directory belongs to.
    def main_worktree(directory)
      output, ok = run(directory, "rev-parse", "--path-format=absolute", "--git-common-dir")
      File.dirname(output.strip) if ok
    end

    def real(path)
      File.exist?(path) ? File.realpath(path) : File.expand_path(path)
    end
  end
end
