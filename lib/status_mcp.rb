# frozen_string_literal: true

require "json"
require "fast_mcp"
require_relative "status_mcp/version"

module StatusMcp
  class Error < StandardError; end

  class ResponseSizeExceededError < Error
    attr_reader :size, :max_size, :uri

    def initialize(size, max_size, uri: nil)
      @size = size
      @max_size = max_size
      @uri = uri
      super("Response size (#{size} bytes) exceeds maximum allowed size (#{max_size} bytes). This may indicate crawler protection or zip bomb.")
    end
  end

  DATA_PATH = File.expand_path("../assets/data.json", __dir__)
end
