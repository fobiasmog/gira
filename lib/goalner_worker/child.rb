require "fileutils"

module GoalnerWorker
  # A process the worker runs and watches without blocking: a Claude Code
  # run, or a workspace hook. It runs in a process group of its own, so that
  # stopping it also reaches the test servers and browsers it started, and
  # so that an interrupt from the worker's terminal does not reach it. Its
  # output, standard error included, is read a line at a time, appended to
  # a log file when one is given, and handed to on_line.
  class Child
    TAIL = 2_000

    attr_reader :pid, :status

    def initialize(command, env:, chdir:, log: nil, on_line: nil)
      @command = command
      @env = env
      @chdir = chdir
      @log_path = log
      @on_line = on_line
      @buffer = +""
      @tail = +""
    end

    def start
      reader, writer = IO.pipe
      if @log_path
        FileUtils.mkdir_p(File.dirname(@log_path))
        @log = File.open(@log_path, "a")
      end
      @pid = Process.spawn(@env, *@command, chdir: @chdir, pgroup: true, in: File::NULL, out: writer, err: writer)
      writer.close
      @reader = reader
      self
    end

    def running?
      reap
      @status.nil?
    end

    # Reads what is there within seconds, and returns whether it still runs.
    def pump(seconds)
      if @reader && IO.select([ @reader ], nil, nil, seconds)
        read_available
      elsif !@reader
        sleep seconds
      end
      running?
    end

    # Interrupts it, terminates its process group if it still runs
    # interrupt_grace seconds later, and kills the group terminate_grace
    # seconds after that.
    def stop(interrupt_grace:, terminate_grace:)
      [ [ "INT", interrupt_grace ], [ "TERM", terminate_grace ], [ "KILL", 5 ] ].each do |signal, grace|
        return finish unless running?

        signal_group(signal)
        wait_for_exit(grace)
      end
      finish
    end

    # The last lines it wrote, at most TAIL characters.
    def tail
      @tail.dup
    end

    def success?
      @status.respond_to?(:success?) && @status.success?
    end

    def finish
      read_available
      @reader&.close unless @reader&.closed?
      @log&.close unless @log&.closed?
      self
    end

    private
      def wait_for_exit(seconds)
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + seconds
        while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
          return unless pump(0.1)
        end
      end

      def signal_group(signal)
        Process.kill(signal, -@pid)
      rescue Errno::ESRCH, Errno::EPERM
        nil
      end

      def reap
        return if @status

        pid, status = Process.waitpid2(@pid, Process::WNOHANG)
        @status = status if pid
      rescue Errno::ECHILD
        @status ||= :gone
      end

      def read_available
        return if @reader.nil? || @reader.closed?

        loop do
          @buffer << @reader.read_nonblock(65_536)
        end
      rescue IO::WaitReadable, EOFError
        flush_lines
      end

      def flush_lines
        while (index = @buffer.index("\n"))
          line = @buffer.slice!(0..index)
          @log&.write(line)
          @tail = (@tail + line)[-TAIL..] || (@tail + line)
          @on_line&.call(line)
        end
      end
  end
end
