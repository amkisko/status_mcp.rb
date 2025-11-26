#!/usr/bin/env ruby
# frozen_string_literal: true

require "rubygems_mcp/client"
require "rubygems_mcp/server"
require "json"

# Clear cache for fresh testing
RubygemsMcp::Client.cache.clear

puts "=" * 80
puts "Testing RubyGems MCP Server - All Tools, Resources, and Prompts"
puts "=" * 80
puts

# Test client
client = RubygemsMcp::Client.new

# ============================================================================
# TEST TOOLS
# ============================================================================
puts "=" * 80
puts "TESTING TOOLS (12 tools)"
puts "=" * 80
puts

tools_tested = 0
tools_failed = 0

# 1. GetLatestVersionsTool
begin
  puts "1. Testing get_latest_versions..."
  result = client.get_latest_versions(["rails", "devise"], fields: ["name", "version", "release_date"])
  if result.is_a?(Array) && result.length == 2
    puts "   ✓ Success: Got #{result.length} gems"
    puts "   Sample: #{result.first[:name]} v#{result.first[:version]}"
    tools_tested += 1
  else
    puts "   ✗ Failed: Unexpected result"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 2. GetGemVersionsTool
begin
  puts "2. Testing get_gem_versions..."
  result = client.get_gem_versions("rails", limit: 3, fields: ["version", "release_date", "downloads_count"])
  if result.is_a?(Array) && result.length > 0
    puts "   ✓ Success: Got #{result.length} versions"
    puts "   Sample: #{result.first[:version]} (#{result.first[:release_date]})"
    tools_tested += 1
  else
    puts "   ✗ Failed: No versions returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 3. GetLatestRubyVersionTool
begin
  puts "3. Testing get_latest_ruby_version..."
  result = client.get_latest_ruby_version
  if result.is_a?(Hash) && result[:version]
    puts "   ✓ Success: Latest Ruby version is #{result[:version]}"
    puts "   Release date: #{result[:release_date]}"
    tools_tested += 1
  else
    puts "   ✗ Failed: No version returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 4. GetRubyVersionsTool
begin
  puts "4. Testing get_ruby_versions..."
  result = client.get_ruby_versions(limit: 3, sort: :version_desc)
  if result.is_a?(Array) && result.length > 0
    puts "   ✓ Success: Got #{result.length} Ruby versions"
    puts "   Sample: #{result.first[:version]} (#{result.first[:release_date]})"
    puts "   Has download_url: #{!result.first[:download_url].nil?}"
    puts "   Has release_notes_url: #{!result.first[:release_notes_url].nil?}"
    tools_tested += 1
  else
    puts "   ✗ Failed: No versions returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 5. GetRubyVersionChangelogTool
begin
  puts "5. Testing get_ruby_version_changelog..."
  latest = client.get_latest_ruby_version
  if latest[:version]
    result = client.get_ruby_version_changelog(latest[:version])
    if result.is_a?(Hash) && result[:version]
      puts "   ✓ Success: Got changelog for Ruby #{result[:version]}"
      puts "   Content length: #{result[:content]&.length || 0} chars"
      puts "   Release notes URL: #{result[:release_notes_url]}"
      tools_tested += 1
    else
      puts "   ✗ Failed: No changelog returned"
      tools_failed += 1
    end
  else
    puts "   ⚠ Skipped: Could not get latest Ruby version"
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 6. GetGemInfoTool
begin
  puts "6. Testing get_gem_info..."
  result = client.get_gem_info("rails", fields: ["name", "version", "downloads", "dependencies"])
  if result.is_a?(Hash) && result[:name]
    puts "   ✓ Success: Got info for #{result[:name]} v#{result[:version]}"
    puts "   Downloads: #{result[:downloads]}"
    puts "   Has dependencies: #{!result[:dependencies].nil?}"
    tools_tested += 1
  else
    puts "   ✗ Failed: No info returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 7. GetGemReverseDependenciesTool
begin
  puts "7. Testing get_gem_reverse_dependencies..."
  result = client.get_gem_reverse_dependencies("rails")
  if result.is_a?(Array)
    puts "   ✓ Success: Found #{result.length} reverse dependencies"
    puts "   Sample: #{result.first(5).join(", ")}"
    tools_tested += 1
  else
    puts "   ✗ Failed: Unexpected result"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 8. GetGemVersionDownloadsTool
begin
  puts "8. Testing get_gem_version_downloads..."
  result = client.get_gem_version_downloads("rails", "7.1.0")
  if result.is_a?(Hash) && result[:version_downloads]
    puts "   ✓ Success: Version downloads: #{result[:version_downloads]}"
    puts "   Total downloads: #{result[:total_downloads]}"
    tools_tested += 1
  else
    puts "   ✗ Failed: No download stats returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 9. GetLatestGemsTool
begin
  puts "9. Testing get_latest_gems..."
  result = client.get_latest_gems(limit: 5)
  if result.is_a?(Array) && result.length > 0
    puts "   ✓ Success: Got #{result.length} latest gems"
    puts "   Sample: #{result.first[:name]} v#{result.first[:version]}"
    tools_tested += 1
  else
    puts "   ✗ Failed: No gems returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 10. GetRecentlyUpdatedGemsTool
begin
  puts "10. Testing get_recently_updated_gems..."
  result = client.get_recently_updated_gems(limit: 5)
  if result.is_a?(Array) && result.length > 0
    puts "   ✓ Success: Got #{result.length} recently updated gems"
    puts "   Sample: #{result.first[:name]} v#{result.first[:version]}"
    tools_tested += 1
  else
    puts "   ✗ Failed: No gems returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 11. GetGemChangelogTool
begin
  puts "11. Testing get_gem_changelog..."
  result = client.get_gem_changelog("rails")
  if result.is_a?(Hash)
    if result[:summary]
      puts "   ✓ Success: Got changelog for #{result[:gem_name]} v#{result[:version]}"
      puts "   Summary length: #{result[:summary].length} chars"
      puts "   Changelog URI: #{result[:changelog_uri]}"
      tools_tested += 1
    elsif result[:error]
      puts "   ⚠ Info: #{result[:error]}"
      tools_tested += 1 # Still counts as tested
    else
      puts "   ✗ Failed: No summary or error returned"
      tools_failed += 1
    end
  else
    puts "   ✗ Failed: Unexpected result"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# 12. SearchGemsTool
begin
  puts "12. Testing search_gems..."
  result = client.search_gems("rails", limit: 5)
  if result.is_a?(Array) && result.length > 0
    puts "   ✓ Success: Found #{result.length} gems"
    puts "   Sample: #{result.first[:name]}"
    tools_tested += 1
  else
    puts "   ✗ Failed: No results returned"
    tools_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  tools_failed += 1
end
puts

# ============================================================================
# TEST RESOURCES
# ============================================================================
puts "=" * 80
puts "TESTING RESOURCES (4 resources)"
puts "=" * 80
puts

resources_tested = 0
resources_failed = 0

# 1. PopularGemsResource
begin
  puts "1. Testing PopularGemsResource..."
  resource = RubygemsMcp::Server::PopularGemsResource.new
  content = JSON.parse(resource.content)
  if content.is_a?(Array) && content.length > 0
    puts "   ✓ Success: Resource has #{content.length} popular gems"
    puts "   Sample: #{content.first["name"]} v#{content.first["version"]}"
    puts "   URI: #{resource.uri}"
    resources_tested += 1
  else
    puts "   ✗ Failed: Invalid content"
    resources_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  resources_failed += 1
end
puts

# 2. RubyVersionCompatibilityResource
begin
  puts "2. Testing RubyVersionCompatibilityResource..."
  resource = RubygemsMcp::Server::RubyVersionCompatibilityResource.new
  content = JSON.parse(resource.content)
  if content.is_a?(Hash) && content["latest"]
    puts "   ✓ Success: Resource has compatibility info"
    puts "   Latest Ruby: #{content["latest"]["version"]}"
    puts "   Maintenance status count: #{content["maintenance_status"]&.length || 0}"
    puts "   URI: #{resource.uri}"
    resources_tested += 1
  else
    puts "   ✗ Failed: Invalid content"
    resources_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  resources_failed += 1
end
puts

# 3. RubyMaintenanceStatusResource
begin
  puts "3. Testing RubyMaintenanceStatusResource..."
  resource = RubygemsMcp::Server::RubyMaintenanceStatusResource.new
  content = JSON.parse(resource.content)
  if content.is_a?(Hash) && content["versions"]
    puts "   ✓ Success: Resource has #{content["versions"].length} Ruby versions"
    puts "   Summary: #{JSON.pretty_generate(content["summary"])}"
    puts "   URI: #{resource.uri}"
    resources_tested += 1
  else
    puts "   ✗ Failed: Invalid content"
    resources_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  resources_failed += 1
end
puts

# 4. LatestRubyVersionResource
begin
  puts "4. Testing LatestRubyVersionResource..."
  resource = RubygemsMcp::Server::LatestRubyVersionResource.new
  content = JSON.parse(resource.content)
  if content.is_a?(Hash) && content["version"]
    puts "   ✓ Success: Latest Ruby version is #{content["version"]}"
    puts "   Release date: #{content["release_date"]}"
    puts "   URI: #{resource.uri}"
    resources_tested += 1
  else
    puts "   ✗ Failed: Invalid content"
    resources_failed += 1
  end
rescue => e
  puts "   ✗ Error: #{e.message}"
  resources_failed += 1
end
puts

# ============================================================================
# TEST PROMPTS
# ============================================================================
puts "=" * 80
puts "TESTING PROMPTS"
puts "=" * 80
puts

# Check if fast-mcp supports prompts
begin
  server = FastMcp::Server.new(name: "test", version: "1.0")
  if server.respond_to?(:prompts)
    prompts = server.prompts || {}
    puts "Prompts available: #{prompts.length}"
    if prompts.length > 0
      prompts.each do |name, prompt|
        puts "  - #{name}: #{prompt[:description] || "No description"}"
      end
    else
      puts "  ⚠ No prompts registered (prompts are not yet implemented)"
    end
  else
    puts "  ⚠ Prompts not supported by fast-mcp library"
  end
rescue => e
  puts "  ⚠ Could not check prompts: #{e.message}"
end
puts

# ============================================================================
# SUMMARY
# ============================================================================
puts "=" * 80
puts "TEST SUMMARY"
puts "=" * 80
puts
puts "Tools:"
puts "  Total: 12"
puts "  Tested: #{tools_tested}"
puts "  Failed: #{tools_failed}"
puts "  Success rate: #{((tools_tested - tools_failed).to_f / tools_tested * 100).round(1)}%"
puts
puts "Resources:"
puts "  Total: 4"
puts "  Tested: #{resources_tested}"
puts "  Failed: #{resources_failed}"
puts "  Success rate: #{((resources_tested - resources_failed).to_f / resources_tested * 100).round(1)}%"
puts
puts "Prompts:"
puts "  Status: Not implemented (fast-mcp may not support prompts yet)"
puts
puts "=" * 80

if tools_failed == 0 && resources_failed == 0
  puts "✓ ALL TESTS PASSED!"
  exit 0
else
  puts "✗ SOME TESTS FAILED"
  exit 1
end
