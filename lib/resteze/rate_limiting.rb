module Resteze
  # Drives the API module's RateLimiter through the request lifecycle (see
  # Resteze::RateLimiter). Prepended outermost on Client so that each attempt
  # of a retried request is instrumented and logged on its own.
  module RateLimiting
    def execute_request(method, path, headers: {}, params: {})
      limiter = api_module.rate_limiter
      attempt = 0
      sent    = false
      begin
        limiter.before_request(method, path, params:, headers:)
        sent = true
        super.tap { |response| limiter.track(response) }
      rescue api_module::Error => e
        # A refusal from before_request never went out, so there is nothing
        # to track and nothing to retry.
        raise unless sent

        limiter.track(e)
        raise unless e.is_a?(api_module::RateLimitError) && limiter.retry?(e, attempt += 1)

        sent = false
        wait_before_retry(limiter, e)
        retry
      end
    end

    private

    def wait_before_retry(limiter, error)
      wait = limiter.retry_after(error).to_f
      sleep(wait) if wait.positive?
    end
  end
end
