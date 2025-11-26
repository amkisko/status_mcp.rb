# frozen_string_literal: true

require "json"
require "fast_mcp"
require_relative "status_mcp/version"

module StatusMcp
  class Error < StandardError; end

  DATA_PATH = File.expand_path("../assets/data.json", __dir__)
end
