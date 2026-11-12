module Resteze
  # A mutex-guarded state hash for objects shared by every thread in a
  # process, such as a module's RateLimiter and Authenticator. Including
  # classes call `initialize_state` from their constructor and keep all
  # mutable state in the hash rather than in instance variables.
  module SynchronizedState
    def initialize_state
      @state_mutex = Mutex.new
      @state       = {}
    end

    # A deep-copied snapshot of the state.
    def state
      synchronize(&:deep_dup)
    end

    def update_state(**values)
      synchronize { |state| state.merge!(values) }
    end

    # Yields the live state hash under the lock. Re-entrant, so `state` and
    # `update_state` may be called inside the block.
    def synchronize
      return yield(@state) if @state_mutex.owned?

      @state_mutex.synchronize { yield(@state) }
    end
  end
end
