# frozen_string_literal: true

require_relative "lib/status_mcp/version"

Gem::Specification.new do |spec|
  spec.name = "status_mcp"
  spec.version = StatusMcp::VERSION
  spec.authors = ["Andrei Makarov"]
  spec.email = ["contact@kiskolabs.com"]

  spec.summary = "Status MCP (Model Context Protocol) server for status page information"
  spec.description = "Ruby gem providing status page information from awesome-status via MCP server tools."
  spec.homepage = "https://github.com/amkisko/status_mcp.rb"
  spec.license = "MIT"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["lib/**/*", "bin/**/*", "assets/**/*", "README.md", "LICENSE*", "CHANGELOG.md"].select { |f| File.file?(f) }
  end
  spec.bindir = "bin"
  spec.executables = ["status_mcp"]
  spec.require_paths = ["lib"]

  spec.required_ruby_version = ">= 3.1"

  spec.add_runtime_dependency "fast-mcp", "~> 1.6"
  spec.add_runtime_dependency "nokogiri", "~> 1.18"
  spec.add_runtime_dependency "rack", "~> 3.2"
  spec.add_runtime_dependency "base64", "~> 0.3"

  spec.add_development_dependency "rspec", "~> 3.13"
  spec.add_development_dependency "webmock", "~> 3.26"
  spec.add_development_dependency "vcr", "~> 6.3"
  spec.add_development_dependency "rake", "~> 13.3"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "rspec_junit_formatter", "~> 0.6"
  spec.add_development_dependency "simplecov-cobertura", "~> 3.1"
  spec.add_development_dependency "standard", "~> 1.52"
  spec.add_development_dependency "appraisal", "~> 2.5"
  spec.add_development_dependency "memory_profiler", "~> 1.1"
  spec.add_development_dependency "rbs", "~> 3.9"
end
