# frozen_string_literal: true

module StatusMcp
  class FetchBudget
    class ExhaustedError < Error; end

    def self.monotonic_now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def initialize(max_requests:, deadline_seconds:)
      @remaining = max_requests
      @deadline_at = self.class.monotonic_now + deadline_seconds
    end

    def consume!
      raise ExhaustedError, "Fetch hop budget exceeded" if @remaining <= 0
      if self.class.monotonic_now >= @deadline_at
        raise ExhaustedError, "Fetch deadline exceeded"
      end

      @remaining -= 1
    end
  end
end
