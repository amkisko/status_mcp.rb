#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "openssl"
require "fileutils"
require_relative "../../lib/status_mcp/server"
require_relative "../../lib/status_mcp"

# Allow limiting the number of services to test (useful for quick testing)
LIMIT = ENV["LIMIT"]&.to_i
THREAD_COUNT = ENV["THREADS"] ? ENV["THREADS"].to_i : 10

# Setup logging
log_dir = File.expand_path("../../tmp", __dir__)
FileUtils.mkdir_p(log_dir)
log_file = File.join(log_dir, "test_fetch.log")
log_mutex = Mutex.new

def log_json(log_file, log_mutex, data)
  log_mutex.synchronize do
    File.open(log_file, "a") do |f|
      f.puts JSON.generate(data)
    end
  end
end

# Test the FetchStatusTool with all services from data.json
tool = StatusMcp::Server::FetchStatusTool.new

# Helper to get HTTP status code (with redirect following)
def get_http_status(url, max_redirects: 5)
  current_url = url
  redirect_count = 0

  while redirect_count < max_redirects
    uri = URI(current_url)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = (uri.scheme == "https")
    if http.use_ssl?
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.ca_file = OpenSSL::X509::DEFAULT_CERT_FILE if File.exist?(OpenSSL::X509::DEFAULT_CERT_FILE)
    end
    http.read_timeout = 5
    http.open_timeout = 5

    request = Net::HTTP::Get.new(uri)
    request["User-Agent"] = "Mozilla/5.0 (compatible; StatusMcp/1.0)"

    response = http.request(request)

    # Handle redirects (301, 302, 307, 308)
    if response.is_a?(Net::HTTPRedirection) && response["location"]
      redirect_count += 1
      location = response["location"]
      # Handle relative redirects
      current_url = URI.join(current_url, location).to_s
      next
    end

    return response.code.to_i
  end

  # Too many redirects
  "ERROR: Too many redirects"
rescue => e
  "ERROR: #{e.class.name}"
end

# Load all services - use the actual file path relative to this script
data_path = File.expand_path("../../assets/data.json", __dir__)
services = []
begin
  if File.exist?(data_path)
    services = JSON.parse(File.read(data_path))
  else
    puts "Error: data.json not found at #{data_path}"
    exit 1
  end
rescue JSON::ParserError => e
  puts "Error parsing data.json: #{e.message}"
  exit 1
rescue => e
  puts "Error loading data.json: #{e.message}"
  exit 1
end

# Filter to only services with status_url
services_with_status = services.select { |s| s["status_url"] && !s["status_url"].empty? }

# Apply limit if specified
if LIMIT && LIMIT > 0
  services_with_status = services_with_status.first(LIMIT)
  puts "Note: Testing only first #{LIMIT} services (set LIMIT env var to change)"
end

puts "=" * 80
puts "Testing FetchStatusTool with #{services_with_status.length} services"
puts "Using #{THREAD_COUNT} threads"
puts "Logging to: #{log_file}"
puts "Looking for services with blank or suspicious status..."
puts "=" * 80
puts

# Clear log file and write header
File.write(log_file, "# Status Fetch Test Log - Started at #{Time.now}\n")

problematic_services = []
results_mutex = Mutex.new
completed_count = 0
completed_mutex = Mutex.new

# Process services in parallel
threads = []
queue = Queue.new
services_with_status.each { |s| queue << s }

THREAD_COUNT.times do
  threads << Thread.new do
    loop do
      begin
        service = queue.pop(true)
      rescue ThreadError
        break # Queue is empty
      end

      next unless service
      status_url = service["status_url"]
      service_name = service["name"]

      begin
        # Get HTTP status code
        http_status = get_http_status(status_url)

        # Fetch status
        result = tool.call(status_url: status_url, max_length: 5000)

        # Use HTTP status code from result if available (most accurate)
        final_http_status = result[:http_status_code] || http_status

        latest_status = result[:latest_status]
        has_error = result[:error] && !result[:error].empty?
        has_history = result[:history] && result[:history].any?

        # Build JSON log entry
        log_entry = {
          service: service_name,
          url: status_url,
          status_code: final_http_status.is_a?(Integer) ? final_http_status : nil,
          extracted_status: latest_status,
          error: result[:error],
          history_count: result[:history]&.length || 0,
          has_feed: !result[:feed_url].nil?,
          feed_url: result[:feed_url],
          api_url: result[:api_url],
          timestamp: Time.now.iso8601
        }

        # Log as JSON
        log_json(log_file, log_mutex, log_entry)

        # Determine if status is problematic
        is_blank = latest_status.nil? || latest_status.empty?
        is_suspicious = false
        suspicion_reasons = []

        unless is_blank
          # Check for suspicious patterns
          status_lower = latest_status.downcase

          # Looks like a generic page title
          if latest_status.match?(/^(Status|System Status|Service Status|.*Status)$/i)
            is_suspicious = true
            suspicion_reasons << "Looks like a page title"
          end

          # Too long (probably extracted wrong content)
          if latest_status.length > 200
            is_suspicious = true
            suspicion_reasons << "Too long (#{latest_status.length} chars)"
          end

          # Doesn't contain status keywords
          unless status_lower.match?(/operational|degraded|down|outage|incident|maintenance|resolved|investigating|monitoring|identified|partial|major|minor|all systems/i)
            is_suspicious = true
            suspicion_reasons << "No status keywords found"
          end

          # Contains navigation/UI text
          if status_lower.match?(/^(support|log in|sign up|subscribe|email|get|visit|click|home|about)/i)
            is_suspicious = true
            suspicion_reasons << "Contains navigation/UI text"
          end
        end

        # Format status for display
        display_status = latest_status || "(blank)"
        # Truncate if too long
        display_status = display_status[0..60] + "..." if display_status.length > 60

        # Consider it problematic if:
        # - Status is blank AND no history AND has error
        # - Status is suspicious
        # - Status is blank AND no history (might be JS-rendered page without feed)
        problem_data = nil
        if is_blank && !has_history && has_error
          problem_data = {
            service: service_name,
            url: status_url,
            status: latest_status || "(blank)",
            issue: "Blank status, no history, has error",
            error: result[:error],
            http_status: final_http_status,
            has_feed: !result[:feed_url].nil?,
            has_history: has_history
          }
        elsif is_suspicious
          problem_data = {
            service: service_name,
            url: status_url,
            status: latest_status,
            issue: "Suspicious status: #{suspicion_reasons.join(", ")}",
            error: result[:error],
            http_status: final_http_status,
            has_feed: !result[:feed_url].nil?,
            has_history: has_history
          }
        elsif is_blank && !has_history
          problem_data = {
            service: service_name,
            url: status_url,
            status: latest_status || "(blank)",
            issue: "Blank status and no history (might be JS-rendered without feed)",
            error: result[:error],
            http_status: final_http_status,
            has_feed: !result[:feed_url].nil?,
            has_history: has_history
          }
        end

        # Thread-safe output and problem tracking
        results_mutex.synchronize do
          completed_mutex.synchronize do
            completed_count += 1
            print "\rTesting #{completed_count}/#{services_with_status.length}: #{service_name}... "
            $stdout.flush
          end

          if problem_data
            problematic_services << problem_data
            puts "⚠️  #{display_status}"
          else
            puts "✅ #{display_status}"
          end
        end
      rescue => e
        # Log error as JSON
        log_entry = {
          service: service_name,
          url: status_url,
          status_code: nil,
          extracted_status: nil,
          error: "#{e.class}: #{e.message}",
          history_count: 0,
          has_feed: false,
          feed_url: nil,
          api_url: nil,
          timestamp: Time.now.iso8601
        }
        log_json(log_file, log_mutex, log_entry)

        problem_data = {
          service: service_name,
          url: status_url,
          status: "(error)",
          issue: "Exception: #{e.class}: #{e.message}",
          error: e.message,
          http_status: nil,
          has_feed: false,
          has_history: false
        }

        results_mutex.synchronize do
          completed_mutex.synchronize do
            completed_count += 1
            print "\rTesting #{completed_count}/#{services_with_status.length}: #{service_name}... "
            $stdout.flush
          end
          problematic_services << problem_data
          puts "❌ ERROR"
        end
      end

      sleep 0.1 # Small delay to be nice to servers
    end
  end
end

# Wait for all threads to complete
threads.each(&:join)
puts "\n"

puts "\n" + "=" * 80
puts "SUMMARY: Found #{problematic_services.length} problematic service(s)"
puts "=" * 80
puts

if problematic_services.any?
  problematic_services.each_with_index do |problem, index|
    puts "#{index + 1}. #{problem[:service]}"
    puts "   URL: #{problem[:url]}"
    puts "   HTTP Status: #{problem[:http_status]}"
    puts "   Status: #{problem[:status]}"
    puts "   Issue: #{problem[:issue]}"
    puts "   Feed: #{problem[:has_feed] ? "Yes" : "No"}"
    puts "   History: #{problem[:has_history] ? "Yes" : "No"}"
    if problem[:error] && !problem[:error].empty?
      puts "   Error: #{problem[:error][0..100]}#{"..." if problem[:error].length > 100}"
    end
    puts
  end
else
  puts "✅ All services have valid status information!"
end

puts "=" * 80
puts "Testing complete!"
puts "Log file: #{log_file}"
puts "=" * 80

# Log summary as JSON
summary_entry = {
  summary: true,
  total_services: services_with_status.length,
  problematic_count: problematic_services.length,
  completed_at: Time.now.iso8601
}
log_json(log_file, log_mutex, summary_entry)
