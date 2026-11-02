module GoalnerMcp
  # A thread-safe cache of at most max_size entries that each expire ttl
  # seconds after being written. Reading an entry makes it the most recently
  # used; writing past max_size drops the least recently used.
  class LruCache
    def initialize(max_size:, ttl:, clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @max_size = max_size
      @ttl = ttl
      @clock = clock
      @entries = {}
      @mutex = Mutex.new
    end

    def read(key)
      @mutex.synchronize do
        value, expires_at = @entries.delete(key)
        next unless expires_at && expires_at > @clock.call

        @entries[key] = [ value, expires_at ]
        value
      end
    end

    def write(key, value)
      @mutex.synchronize do
        @entries.delete(key)
        @entries[key] = [ value, @clock.call + @ttl ]
        @entries.shift while @entries.size > @max_size
      end
      value
    end

    def delete(key)
      @mutex.synchronize { @entries.delete(key) }
      nil
    end

    def size
      @mutex.synchronize { @entries.size }
    end
  end
end
