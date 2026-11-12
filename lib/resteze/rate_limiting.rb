module Resteze
  # Drives the API module's RateLimiter through the request lifecycle (see
  # Resteze::RateLimiter). Prepended outermost on Client so that each attempt
  # of a retried request is instrumented and logged on its own. Passes every
  # keyword through untouched, so a client that accepts more than
  # `headers:` and `params:` still works.
  module RateLimiting
    def execute_request(method, path, **)
      limiter = api_module.rate_limiter
      attempt = 0
      sent    = false
      begin
        limiter.before_request(method, path, **)
        sent = true
        super.tap { |response| limiter.track(response) }
      rescue api_module::Error => e
        # A refusal from before_request never went out, so there is nothing
        # to track and nothing to retry.
        raise unless sent

        limiter.track(e)
        raise unless e.is_a?(api_module::RateLimitError) && limiter.retry?(e, attempt += 1)

        sent = false
        limiter.wait(limiter.retry_after(e), error: e) # under on_wait: :raise this raises the 429 itself
        retry
      end
    end
  end
end
