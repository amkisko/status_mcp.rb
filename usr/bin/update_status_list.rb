#!/usr/bin/env ruby
# frozen_string_literal: true

require "net/http"
require "json"
require "fileutils"
require "nokogiri"
require "openssl"

# URL of the awesome-status README
README_URL = "https://raw.githubusercontent.com/amkisko/awesome-status/refs/heads/main/README.md"
# Path to save the JSON data
DATA_PATH = File.expand_path("../../assets/data.json", __dir__)

def fetch_readme
  uri = URI(README_URL)
  http = Net::HTTP.new(uri.host, uri.port)
  http.use_ssl = true
  http.verify_mode = OpenSSL::SSL::VERIFY_PEER

  # Set ca_file directly - this is the simplest and most reliable approach
  # Try SSL_CERT_FILE first, then default cert file
  ca_file = if ENV["SSL_CERT_FILE"] && File.file?(ENV["SSL_CERT_FILE"])
    ENV["SSL_CERT_FILE"]
  elsif File.exist?(OpenSSL::X509::DEFAULT_CERT_FILE)
    OpenSSL::X509::DEFAULT_CERT_FILE
  end

  http.ca_file = ca_file if ca_file

  request = Net::HTTP::Get.new(uri)
  response = http.request(request)

  unless response.is_a?(Net::HTTPSuccess)
    abort "Failed to fetch README: #{response.code} #{response.message}"
  end

  response.body
end

def parse_readme(content)
  services = []

  # Parse markdown bullet list format: * Service Name - [link text](url), [link text](url), ...
  content.each_line do |line|
    next unless line.strip.start_with?("* ")

    # Extract service name (everything before the first " - ")
    match = line.match(/^\*\s+(.+?)\s+-\s+(.+)$/)
    next unless match

    name = match[1].strip
    links_part = match[2]

    links = {}

    # Extract links: [text](url)
    links_part.scan(/\[([^\]]+)\]\(([^)]+)\)/).each do |text, url|
      key = text.downcase.strip
      links[key] = url
    end

    next if links.empty?

    # Categorize links
    status_url = find_link(links, ["official status", "status page", "status"])
    website_url = find_link(links, ["website", "official website", "homepage"])
    security_url = find_link(links, ["security", "security page", "security advisories"])
    support_url = find_link(links, ["support page", "support", "help", "customer support"])

    # Collect auxiliary URLs (everything else)
    categorized_urls = [status_url, website_url, security_url, support_url].compact
    aux_urls = links.reject { |key, value|
      categorized_urls.include?(value)
    }.values

    services << {
      "name" => name,
      "status_url" => status_url,
      "website_url" => website_url,
      "security_url" => security_url,
      "support_url" => support_url,
      "aux_urls" => aux_urls
    }
  end

  services
end

def find_link(links, keywords)
  keywords.each do |keyword|
    return links[keyword] if links.key?(keyword)
  end
  nil
end

def save_json(data)
  FileUtils.mkdir_p(File.dirname(DATA_PATH))
  File.write(DATA_PATH, JSON.pretty_generate(data))
  puts "Saved #{data.size} services to #{DATA_PATH}"
end

puts "Fetching awesome-status README..."
content = fetch_readme

puts "Parsing content..."
data = parse_readme(content)

puts "Saving data..."
save_json(data)

puts "Done!"
