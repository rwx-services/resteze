module Resteze
  # Rate-limit state reported by an API's response headers. Built by
  # Response#rate_limit and Error#rate_limit from the header names in the
  # module's `rate_limit_headers` configuration.
  class RateLimit
    DEFAULT_HEADERS = {
      limit: "X-RateLimit-Limit",
      remaining: "X-RateLimit-Remaining",
      reset: "X-RateLimit-Reset"
    }.freeze

    attr_reader :limit, :remaining, :reset

    # Returns nil when none of the named headers are present. Values that are
    # not integers are left nil; `reset` is kept as the API sent it (an epoch
    # or a number of seconds, depending on the API).
    def self.from_headers(headers, names = nil)
      names  = DEFAULT_HEADERS.merge(names || {})
      values = names.transform_values { |name| header_value(headers, name) }
      return if values.values.all?(&:nil?)

      new(**values.transform_values { |value| Integer(value.to_s, exception: false) })
    end

    def self.header_value(headers, name)
      (headers || {}).find { |key, _| key.to_s.casecmp?(name) }&.last
    end

    def initialize(limit: nil, remaining: nil, reset: nil)
      @limit     = limit
      @remaining = remaining
      @reset     = reset
    end

    def exhausted?
      !remaining.nil? && remaining.zero?
    end

    def to_h
      { limit:, remaining:, reset: }
    end
  end
end
