# frozen_string_literal: true

require "fast_mcp"
require "json"
require "net/http"
require "uri"
require "openssl"
require "nokogiri"
require_relative "../status_mcp"

module StatusMcp
  class Server
    def self.start
      server = FastMcp::Server.new(name: "status_mcp", version: StatusMcp::VERSION)

      server.register_tool(SearchServicesTool)
      server.register_tool(GetServiceDetailsTool)
      server.register_tool(ListServicesTool)
      server.register_tool(FetchStatusTool)

      server.start
    end

    class BaseTool < FastMcp::Tool
      protected

      def load_data
        unless File.exist?(StatusMcp::DATA_PATH)
          return []
        end

        JSON.parse(File.read(StatusMcp::DATA_PATH))
      rescue JSON::ParserError
        []
      end

      def format_service(service)
        output = "## #{service["name"]}\n"

        output += "- **Official Status**: #{service["status_url"]}\n" if service["status_url"]
        output += "- **Website**: #{service["website_url"]}\n" if service["website_url"]
        output += "- **Security**: #{service["security_url"]}\n" if service["security_url"]
        output += "- **Support**: #{service["support_url"]}\n" if service["support_url"]

        if service["aux_urls"]&.any?
          output += "- **Other Links**: #{service["aux_urls"].join(", ")}\n"
        end

        output
      end

      # Calculate Levenshtein distance between two strings
      def levenshtein_distance(str1, str2)
        m = str1.length
        n = str2.length
        return n if m.zero?
        return m if n.zero?

        d = Array.new(m + 1) { Array.new(n + 1) }

        (0..m).each { |i| d[i][0] = i }
        (0..n).each { |j| d[0][j] = j }

        (1..m).each do |i|
          (1..n).each do |j|
            cost = (str1[i - 1] == str2[j - 1]) ? 0 : 1
            d[i][j] = [
              d[i - 1][j] + 1,      # deletion
              d[i][j - 1] + 1,      # insertion
              d[i - 1][j - 1] + cost # substitution
            ].min
          end
        end

        d[m][n]
      end

      # Calculate similarity ratio between two strings (0.0 to 1.0)
      def similarity_ratio(str1, str2)
        return 1.0 if str1 == str2
        return 0.0 if str1.empty? || str2.empty?

        max_len = [str1.length, str2.length].max
        distance = levenshtein_distance(str1, str2)
        1.0 - (distance.to_f / max_len)
      end

      # Find services using fuzzy matching
      def find_services_fuzzy(services, query, threshold: 0.6)
        query_lower = query.downcase.strip
        return [] if query_lower.empty?

        results = []

        services.each do |service|
          name = service["name"]
          name_lower = name.downcase

          # Exact match (case-insensitive)
          if name_lower == query_lower
            results << {service: service, score: 1.0, match_type: :exact}
            next
          end

          # Substring match
          if name_lower.include?(query_lower) || query_lower.include?(name_lower)
            # Higher score for longer matches
            match_length = [name_lower.length, query_lower.length].min
            score = match_length.to_f / [name_lower.length, query_lower.length].max
            results << {service: service, score: score, match_type: :substring}
            next
          end

          # Fuzzy match using Levenshtein distance
          similarity = similarity_ratio(name_lower, query_lower)
          if similarity >= threshold
            results << {service: service, score: similarity, match_type: :fuzzy}
          end
        end

        # Sort by score (highest first), then by name
        results.sort_by { |r| [-r[:score], r[:service]["name"]] }
      end
    end

    class SearchServicesTool < BaseTool
      tool_name "search_services"
      description "Search for services by name (supports fuzzy matching)"

      arguments do
        required(:query).filled(:string).description("Search query")
      end

      def call(query:)
        services = load_data
        fuzzy_results = find_services_fuzzy(services, query, threshold: 0.5)

        if fuzzy_results.empty?
          "No services found matching '#{query}'"
        else
          # Deduplicate by service name (case-insensitive)
          seen = {}
          unique_results = fuzzy_results.select do |r|
            name_key = r[:service]["name"]&.downcase
            if seen[name_key]
              false
            else
              seen[name_key] = true
              true
            end
          end

          # Limit to top 20 results
          unique_results.first(20).map { |r| format_service(r[:service]) }.join("\n\n")
        end
      end
    end

    class GetServiceDetailsTool < BaseTool
      tool_name "get_service_details"
      description "Get detailed status links for a specific service (supports fuzzy matching)"

      arguments do
        required(:name).filled(:string).description("Service name (exact or fuzzy match)")
      end

      def call(name:)
        services = load_data
        fuzzy_results = find_services_fuzzy(services, name, threshold: 0.6)

        if fuzzy_results.empty?
          "Service '#{name}' not found"
        elsif fuzzy_results.first[:match_type] == :exact || fuzzy_results.first[:score] >= 0.9
          # Exact match or very high confidence - return the best match
          format_service(fuzzy_results.first[:service])
        elsif fuzzy_results.length == 1
          # Single fuzzy match - return it
          format_service(fuzzy_results.first[:service])
        else
          # Multiple matches - show the best one but mention alternatives
          best_match = fuzzy_results.first
          alternatives = fuzzy_results[1..2].map { |r| r[:service]["name"] }.compact

          output = format_service(best_match[:service])
          if alternatives.any?
            output += "\n\n**Note**: Did you mean one of these? #{alternatives.join(", ")}"
          end
          output
        end
      end
    end

    class ListServicesTool < BaseTool
      tool_name "list_services"
      description "List all available services (limited to first 50 if too many)"

      arguments do
        optional(:limit).filled(:integer).description("Limit number of results (default 50)")
      end

      def call(limit: 50)
        services = load_data
        limit ||= 50

        list = services.take(limit).map { |s| s["name"] }

        response = "Available services (#{list.size}/#{services.size}):\n"
        response += list.join(", ")

        if services.size > limit
          response += "\n... and #{services.size - limit} more."
        end

        response
      end
    end

    class FetchStatusTool < BaseTool
      # Maximum response size (1MB) to protect against zip bombs and crawler protection pages
      MAX_RESPONSE_SIZE = 1 * 1024 * 1024 # 1MB

      tool_name "fetch_status"
      description "Fetch status from a status_url with HTML purification. Extracts latest status, history, and messages from status pages."

      arguments do
        required(:status_url).filled(:string).description("Status page URL to fetch")
        optional(:max_length).filled(:integer).description("Maximum length of extracted text in characters (default: 10000)")
      end

      def call(status_url:, max_length: 10000)
        # Try incident.io API first (only if we detect it's an incident.io page)
        api_info = nil
        api_url = nil
        # Only try incident.io API for known incident.io domains or if we detect it
        if might_be_incident_io?(status_url)
          begin
            api_url = build_incident_io_api_url(status_url)
            if api_url
              api_info = fetch_and_parse_incident_io_api(api_url, max_length)
              # If API returns error, don't use it
              if api_info&.dig(:error)&.include?("404")
                api_info = nil
              end
            end
          rescue => e
            # Not an incident.io page or API failed, continue with other methods
          end
        end

        # Try RSS/Atom feeds (they're more reliable for JS-rendered pages)
        feed_urls = build_feed_urls(status_url)
        feed_info = nil
        successful_feed_url = nil

        if !api_info || (!api_info[:history]&.any? && !api_info[:latest_status])
          feed_urls.each do |feed_url|
            feed_info = fetch_and_parse_feed(feed_url, max_length)
            if feed_info && (feed_info[:history]&.any? || feed_info[:latest_status])
              successful_feed_url = feed_url
              break
            end
          rescue => e
            # Try next feed URL
            next
          end
        end

        # Fetch main status page (as fallback or supplement)
        main_info = nil
        begin
          main_info = fetch_and_extract(status_url, max_length)
        rescue => e
          # If we have feed info, that's okay
          main_info = {latest_status: nil, history: [], messages: [], error: nil} unless feed_info
        end

        # Try to fetch history page if it exists
        history_url = build_history_url(status_url)
        history_info = nil

        if history_url && history_url != status_url
          begin
            history_info = fetch_and_extract(history_url, max_length, history_only: true)
          rescue => e
            # Silently fail if history page doesn't exist or has errors
            # This is expected for many status pages
          end
        end

        # Merge results (prioritize API data, then feed data, then HTML)
        combined_history = []
        if api_info && api_info[:history]&.any?
          combined_history.concat(api_info[:history])
        end
        if feed_info && feed_info[:history]&.any?
          combined_history.concat(feed_info[:history])
        end
        combined_history.concat(main_info[:history] || []) if main_info && main_info[:history]
        combined_history.concat(history_info[:history] || []) if history_info && history_info[:history]

        # Remove duplicates (simple text-based deduplication)
        combined_history = combined_history.uniq { |item| item[0..100] }

        # Determine latest status (prioritize API, then HTML page, then feed)
        # HTML page is more reliable than feed fallback statuses
        latest_status = api_info[:latest_status] if api_info && api_info[:latest_status]
        latest_status ||= main_info[:latest_status] if main_info && main_info[:latest_status]
        # Only use feed status if HTML didn't find one (feed statuses are often fallbacks)
        latest_status ||= feed_info[:latest_status] if feed_info && feed_info[:latest_status]

        # Get HTTP status code from main page (most reliable)
        http_status_code = main_info[:http_status_code] if main_info && main_info[:http_status_code]

        # Only include errors if they're meaningful
        final_error = nil
        if main_info && main_info[:error] && !main_info[:error].empty?
          # Don't show JS-rendered page errors if we got data from feeds/API
          final_error = if main_info[:error].include?("JavaScript-rendered") && (feed_info && (feed_info[:history]&.any? || feed_info[:latest_status]) || api_info && (api_info[:history]&.any? || api_info[:latest_status]))
            # JS-rendered page but we got data from other sources, that's fine
            nil
          else
            main_info[:error]
          end
        # Only show feed/API errors if we didn't get any useful data from HTML
        elsif !main_info || !main_info[:latest_status]
          if feed_info && feed_info[:error] && !feed_info[:error].empty? && !feed_info[:history]&.any? && !feed_info[:latest_status]
            # Don't show "Not a valid RSS or Atom feed" - it's not really an error, just no feed available
            unless feed_info[:error].include?("Not a valid RSS or Atom feed")
              final_error = feed_info[:error]
            end
          elsif api_info && api_info[:error] && !api_info[:error].empty? && !api_info[:history]&.any? && !api_info[:latest_status]
            final_error = api_info[:error]
          end
        end

        {
          status_url: status_url,
          api_url: api_url,
          feed_url: successful_feed_url,
          history_url: history_url,
          latest_status: latest_status,
          history: combined_history.first(20), # Limit to 20 most recent
          messages: (api_info && api_info[:messages]) || (feed_info && feed_info[:messages]) || (main_info && main_info[:messages]) || [],
          extracted_at: Time.now.iso8601,
          error: final_error,
          http_status_code: http_status_code
        }
      rescue => e
        error_message = if e.is_a?(StatusMcp::ResponseSizeExceededError)
          "Response size limit exceeded: #{e.message}"
        else
          "Error fetching status: #{e.message}"
        end

        {
          status_url: status_url,
          error: error_message,
          latest_status: nil,
          history: [],
          messages: []
        }
      end

      def fetch_with_redirects(url, max_redirects: 5, accept: "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8")
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
          http.read_timeout = 10
          http.open_timeout = 10

          request = Net::HTTP::Get.new(uri)
          request["User-Agent"] = "Mozilla/5.0 (compatible; StatusMcp/1.0)"
          request["Accept"] = accept

          response = http.request(request)

          # Handle redirects (301, 302, 307, 308)
          if response.is_a?(Net::HTTPRedirection) && response["location"]
            redirect_count += 1
            location = response["location"]
            # Handle relative redirects
            current_url = URI.join(current_url, location).to_s
            next
          end

          # Check response size before returning (protect against zip bombs and crawler protection)
          if response.is_a?(Net::HTTPSuccess)
            # Check Content-Length header first if available (optimization to avoid reading large bodies)
            content_length = response["Content-Length"]
            if content_length
              content_length_int = content_length.to_i
              if content_length_int > MAX_RESPONSE_SIZE
                raise StatusMcp::ResponseSizeExceededError.new(content_length_int, MAX_RESPONSE_SIZE, uri: uri.to_s)
              end
            end

            # Read body and check actual size (Content-Length might be missing or incorrect)
            response_body = response.body || ""
            response_size = response_body.bytesize
            if response_size > MAX_RESPONSE_SIZE
              raise StatusMcp::ResponseSizeExceededError.new(response_size, MAX_RESPONSE_SIZE, uri: uri.to_s)
            end
          end

          return response
        end

        # Too many redirects
        raise "Too many redirects (max: #{max_redirects})"
      end

      def fetch_and_extract(url, max_length, history_only: false)
        response = fetch_with_redirects(url)
        http_status_code = response.code.to_i

        unless response.is_a?(Net::HTTPSuccess)
          return {
            error: "Failed to fetch: #{response.code} #{response.message}",
            http_status_code: http_status_code,
            latest_status: nil,
            history: [],
            messages: []
          }
        end

        html_body = response.body || ""
        # Additional size check (already checked in fetch_with_redirects, but double-check for safety)
        if html_body.bytesize > MAX_RESPONSE_SIZE
          raise StatusMcp::ResponseSizeExceededError.new(html_body.bytesize, MAX_RESPONSE_SIZE, uri: url)
        end

        uri = URI(url)

        # Validate and parse HTML
        doc = validate_and_parse_html(html_body, uri)

        # Extract status information and include HTTP status code
        if history_only
          {
            latest_status: nil,
            history: extract_history(doc),
            messages: [],
            http_status_code: http_status_code
          }
        else
          extract_status_info(doc, max_length).merge(http_status_code: http_status_code)
        end
      end

      def build_history_url(status_url)
        uri = URI(status_url)

        # Don't build history URL if we're already on a history page
        return nil if uri.path.end_with?("/history")

        # Common patterns for history pages
        base_path = uri.path.chomp("/")

        # Try /history
        history_path = base_path.empty? ? "/history" : "#{base_path}/history"
        history_uri = uri.dup
        history_uri.path = history_path

        history_uri.to_s
      end

      def might_be_incident_io?(status_url)
        # Known incident.io domains
        incident_io_domains = [
          "status.openai.com",
          "status.notion.so",
          "status.zapier.com",
          "status.buffer.com"
        ]

        uri = URI(status_url)
        return true if incident_io_domains.include?(uri.host)

        # Could add HTML check here in the future
        false
      end

      def build_incident_io_api_url(status_url)
        uri = URI(status_url)

        # Check if this looks like an incident.io status page
        # Pattern: https://status.example.com/proxy/status.example.com
        host = uri.host

        # Build the incident.io API URL
        api_path = "/proxy/#{host}"
        api_uri = uri.dup
        api_uri.path = api_path

        api_uri.to_s
      end

      def fetch_and_parse_incident_io_api(api_url, max_length)
        response = fetch_with_redirects(api_url, accept: "application/json")

        unless response.is_a?(Net::HTTPSuccess)
          return {
            error: "Failed to fetch API: #{response.code} #{response.message}",
            latest_status: nil,
            history: [],
            messages: []
          }
        end

        json_body = response.body || ""
        # Additional size check (already checked in fetch_with_redirects, but double-check for safety)
        if json_body.bytesize > MAX_RESPONSE_SIZE
          raise StatusMcp::ResponseSizeExceededError.new(json_body.bytesize, MAX_RESPONSE_SIZE, uri: api_url)
        end

        # Parse JSON response
        parse_incident_io_api(json_body, max_length)
      rescue StatusMcp::ResponseSizeExceededError
        # Re-raise response size errors
        raise
      rescue JSON::ParserError => e
        {
          error: "Error parsing API JSON: #{e.message}",
          latest_status: nil,
          history: [],
          messages: []
        }
      rescue => e
        {
          error: "Error fetching API: #{e.message}",
          latest_status: nil,
          history: [],
          messages: []
        }
      end

      def parse_incident_io_api(json_body, max_length)
        data = JSON.parse(json_body)
        summary = data["summary"] || {}

        ongoing_incidents = summary["ongoing_incidents"] || []
        scheduled_maintenances = summary["scheduled_maintenances"] || []
        components = summary["components"] || []

        history_items = []
        messages = []
        latest_status = nil

        # Extract from ongoing incidents
        ongoing_incidents.each do |incident|
          title = incident["name"] || "Ongoing Incident"
          status = incident["status"] || "Investigating"
          description = incident["description"] || ""

          # Clean HTML from description if present
          if description.include?("<")
            desc_doc = Nokogiri::HTML(description)
            description = desc_doc.text.strip
          end

          item_text = "#{title} - Status: #{status}"
          item_text += " - #{description[0..300]}" if description && !description.empty?

          history_items << purify_text(item_text)

          # Use first incident's status as latest status
          latest_status ||= status
        end

        # Extract from scheduled maintenances
        scheduled_maintenances.each do |maintenance|
          title = maintenance["name"] || "Scheduled Maintenance"
          status = maintenance["status"] || "Scheduled"
          description = maintenance["description"] || ""

          # Clean HTML from description if present
          if description.include?("<")
            desc_doc = Nokogiri::HTML(description)
            description = desc_doc.text.strip
          end

          scheduled_for = maintenance["scheduled_for"] || ""
          scheduled_until = maintenance["scheduled_until"] || ""

          item_text = "#{title} - Status: #{status}"
          item_text += " - Scheduled: #{scheduled_for}" if scheduled_for && !scheduled_for.empty?
          item_text += " until #{scheduled_until}" if scheduled_until && !scheduled_until.empty?
          item_text += " - #{description[0..300]}" if description && !description.empty?

          history_items << purify_text(item_text)
        end

        # Determine overall status if no incidents
        unless latest_status
          if ongoing_incidents.empty? && scheduled_maintenances.empty?
            # Check component statuses
            all_operational = components.all? do |comp|
              comp_status = comp["status"] || comp["operational_status"]
              comp_status&.downcase&.include?("operational") || comp_status.nil?
            end

            if all_operational
              latest_status = "Operational"
            else
              # Find non-operational components
              non_operational = components.select do |comp|
                comp_status = comp["status"] || comp["operational_status"]
                comp_status && !comp_status.downcase.include?("operational")
              end

              latest_status = if non_operational.any?
                "Degraded Performance"
              else
                "Operational"
              end
            end
          else
            latest_status = "See incidents"
          end
        end

        # Truncate if needed
        total_length = history_items.join("\n").length
        if total_length > max_length
          history_items = truncate_array(history_items, max_length)
        end

        {
          latest_status: latest_status,
          history: history_items,
          messages: messages
        }
      end

      def build_feed_urls(status_url)
        uri = URI(status_url)
        base_path = uri.path.chomp("/")

        # Common RSS/Atom feed patterns
        feed_patterns = [
          "/feed.rss",
          "/feed.atom",
          "/rss",
          "/atom",
          "/feed",
          "/status.rss",
          "/status.atom"
        ]

        feed_urls = []
        feed_patterns.each do |pattern|
          feed_path = base_path.empty? ? pattern : "#{base_path}#{pattern}"
          feed_uri = uri.dup
          feed_uri.path = feed_path
          feed_urls << feed_uri.to_s
        end

        feed_urls
      end

      def fetch_and_parse_feed(feed_url, max_length)
        response = fetch_with_redirects(feed_url, accept: "application/rss+xml,application/atom+xml,application/xml,text/xml,*/*;q=0.9")

        unless response.is_a?(Net::HTTPSuccess)
          return {
            error: "Failed to fetch feed: #{response.code} #{response.message}",
            latest_status: nil,
            history: [],
            messages: []
          }
        end

        feed_body = response.body || ""
        # Additional size check (already checked in fetch_with_redirects, but double-check for safety)
        if feed_body.bytesize > MAX_RESPONSE_SIZE
          raise StatusMcp::ResponseSizeExceededError.new(feed_body.bytesize, MAX_RESPONSE_SIZE, uri: feed_url)
        end

        # Parse RSS/Atom feed
        parse_feed(feed_body, max_length)
      rescue StatusMcp::ResponseSizeExceededError
        # Re-raise response size errors
        raise
      rescue => e
        {
          error: "Error parsing feed: #{e.message}",
          latest_status: nil,
          history: [],
          messages: []
        }
      end

      def parse_feed(feed_body, max_length)
        doc = Nokogiri::XML(feed_body)

        # Determine feed type (RSS or Atom)
        is_atom = doc.root&.name == "feed" || doc.at("feed")
        is_rss = doc.root&.name == "rss" || doc.at("rss")

        unless is_rss || is_atom
          return {
            error: "Not a valid RSS or Atom feed",
            latest_status: nil,
            history: [],
            messages: []
          }
        end

        history_items = []
        latest_status = nil

        if is_rss
          # Parse RSS feed
          items = doc.css("item")
          items.each do |item|
            title = item.css("title").first&.text&.strip || ""
            description = item.css("description").first&.text&.strip || ""
            pub_date = item.css("pubDate").first&.text&.strip || ""

            # Clean HTML from description
            if description.include?("<")
              desc_doc = Nokogiri::HTML(description)
              # Remove lists and other HTML elements, get clean text
              desc_doc.css("ul, ol, li, br").each { |el| el.replace("\n") }
              description = desc_doc.text.strip
              # Normalize whitespace
              description = description.gsub(/\n{2,}/, "\n").gsub(/[ \t]{2,}/, " ").strip
            end

            # Extract status from description (look for "Status: ..." patterns)
            # Try to get just the status word (Resolved, Operational, etc.)
            status_match = description.match(/Status:\s*([A-Za-z]+)/i) || title.match(/Status:\s*([A-Za-z]+)/i)
            if status_match && !latest_status
              status_word = status_match[1].strip
              # Only use if it's a known status word
              if status_word.match?(/^(Resolved|Operational|Degraded|Down|Investigating|Monitoring|Identified|Partial|Major|Minor)$/i)
                latest_status = status_word
              end
            end

            # Build history item (clean up description first)
            # Remove status line and component lists from description for cleaner output
            clean_description = description.dup
            clean_description = clean_description.gsub(/Status:\s*[^\n]+/i, "").strip
            clean_description = clean_description.gsub(/Affected components[^\n]*/i, "").strip
            clean_description = clean_description.gsub(/\(Operational\)/i, "").strip
            clean_description = clean_description.gsub(/\n{2,}/, "\n").strip

            item_text = title.to_s
            if clean_description && !clean_description.empty? && clean_description.length > 10
              item_text += " - #{clean_description[0..500]}" # Limit description length
            end
            item_text += " (#{pub_date})" if pub_date && !pub_date.empty?

            history_items << purify_text(item_text) if item_text.length >= 20
          end
        elsif is_atom
          # Parse Atom feed
          entries = doc.css("entry")
          entries.each do |entry|
            title = entry.css("title").first&.text&.strip || ""
            content = entry.css("content").first&.text&.strip || entry.css("summary").first&.text&.strip || ""
            updated = entry.css("updated").first&.text&.strip || entry.css("published").first&.text&.strip || ""

            # Clean HTML from content
            if content.include?("<")
              content_doc = Nokogiri::HTML(content)
              # Remove lists and other HTML elements, get clean text
              content_doc.css("ul, ol, li, br").each { |el| el.replace("\n") }
              content = content_doc.text.strip
              # Normalize whitespace
              content = content.gsub(/\n{2,}/, "\n").gsub(/[ \t]{2,}/, " ").strip
            end

            # Extract status from content (look for "Status: ..." patterns)
            # Try to get just the status word (Resolved, Operational, etc.)
            status_match = content.match(/Status:\s*([A-Za-z]+)/i) || title.match(/Status:\s*([A-Za-z]+)/i)
            if status_match && !latest_status
              status_word = status_match[1].strip
              # Only use if it's a known status word
              if status_word.match?(/^(Resolved|Operational|Degraded|Down|Investigating|Monitoring|Identified|Partial|Major|Minor)$/i)
                latest_status = status_word
              end
            end

            # Build history item (clean up content first)
            # Remove status line and component lists from content for cleaner output
            clean_content = content.dup
            clean_content = clean_content.gsub(/Status:\s*[^\n]+/i, "").strip
            clean_content = clean_content.gsub(/Affected components[^\n]*/i, "").strip
            clean_content = clean_content.gsub(/\(Operational\)/i, "").strip
            clean_content = clean_content.gsub(/\n{2,}/, "\n").strip

            item_text = title.to_s
            if clean_content && !clean_content.empty? && clean_content.length > 10
              item_text += " - #{clean_content[0..500]}" # Limit content length
            end
            item_text += " (#{updated})" if updated && !updated.empty?

            history_items << purify_text(item_text) if item_text.length >= 20
          end
        end

        # Determine overall status from feed title or latest item
        unless latest_status
          feed_title = doc.css("channel > title, feed > title").first&.text&.strip
          # Only use feed title if it's a short status word, not a page title
          if feed_title && feed_title.length < 50 && feed_title.match?(/^(operational|degraded|down|outage|incident|maintenance|all systems operational)$/i)
            latest_status = feed_title
          elsif history_items.any?
            # Check if all items are scheduled maintenance (not actual incidents)
            scheduled_count = history_items.count { |item| item.match?(/scheduled|maintenance/i) && !item.match?(/incident|outage|degraded|down|investigating/i) }

            # Check if all items are resolved
            resolved_count = history_items.count { |item| item.match?(/resolved|operational/i) && !item.match?(/investigating|monitoring|identified/i) }

            # If all are scheduled maintenance or all resolved, likely operational
            latest_status = if scheduled_count == history_items.length || (resolved_count == history_items.length && history_items.length > 0)
              "Operational"
            # If there are active incidents (investigating, monitoring, identified)
            elsif history_items.any? { |item| item.match?(/investigating|monitoring|identified|degraded|down|outage/i) && !item.match?(/resolved|operational/i) }
              "See recent incidents"
            # If we have history but can't determine, default to operational (better than "See recent incidents")
            else
              "Operational"
            end
          end
        end

        # Truncate if needed
        total_length = history_items.join("\n").length
        if total_length > max_length
          history_items = truncate_array(history_items, max_length)
        end

        {
          latest_status: latest_status,
          history: history_items,
          messages: []
        }
      end

      private

      def validate_and_parse_html(body, uri)
        # Check for common crawler protection patterns (more specific)
        protection_patterns = [
          /checking your browser.*?before accessing/i,
          /ddos protection.*?checking/i,
          /access denied.*?cloudflare/i,
          /please wait.*?cloudflare/i,
          /captcha.*?verification/i,
          /rate limit.*?exceeded/i,
          /blocked.*?security/i
        ]

        if protection_patterns.any? { |pattern| body.match?(pattern) }
          raise "Response appears to be a crawler protection page"
        end

        # Check if response is actually HTML
        unless body.strip.start_with?("<!DOCTYPE", "<html", "<HTML") || body.include?("<html")
          raise "Response does not appear to be HTML"
        end

        doc = Nokogiri::HTML(body)

        # Check if this is a JavaScript-rendered page (React, Vue, Angular, etc.)
        js_rendered_indicators = [
          /<div[^>]*id=["']root["'][^>]*>\s*<\/div>/i,
          /<div[^>]*id=["']app["'][^>]*>\s*<\/div>/i,
          /You need to enable JavaScript/i,
          /<noscript>.*?enable.*?javascript/i,
          /react.*?root|vue.*?app|angular.*?app/i
        ]

        is_js_rendered = js_rendered_indicators.any? { |pattern| body.match?(pattern) }

        # Check if HTML is empty or appears to be an error page
        # For JS-rendered pages, allow shorter content
        min_length = is_js_rendered ? 20 : 50
        if doc.text.strip.length < min_length
          if is_js_rendered
            raise "HTML response appears to be a JavaScript-rendered page with no server-side content"
          else
            raise "HTML response appears to be empty or too short"
          end
        end

        # Check for common error page indicators (but be more specific)
        error_indicators = [
          /^error 404$/i,
          /^page not found$/i,
          /^access denied$/i,
          /^forbidden$/i,
          /^internal server error$/i,
          /404.*?not found/i,
          /error.*?404/i
        ]

        # Only flag as error if it's clearly an error page (title or main heading)
        title = doc.css("title").first&.text&.strip
        main_heading = doc.css("h1").first&.text&.strip

        if (title && error_indicators.any? { |pattern| title.match?(pattern) }) ||
            (main_heading && error_indicators.any? { |pattern| main_heading.match?(pattern) })
          raise "HTML response appears to be an error page"
        end

        doc
      rescue Nokogiri::XML::SyntaxError => e
        raise "Failed to parse HTML: #{e.message}"
      end

      def extract_status_info(doc, max_length)
        # Remove unwanted elements
        doc.css("nav, header, footer, .navigation, .sidebar, script, style, .cookie-banner, .privacy-banner, .advertisement, .ads").remove

        # Common status page patterns
        # 1. Status indicators (operational, degraded, down, etc.)
        latest_status = extract_latest_status(doc)

        # 2. Recent incidents/updates/history
        history = extract_history(doc)

        # 3. Messages/announcements
        messages = extract_messages(doc)

        # Truncate if needed
        status_text = latest_status || ""
        history_text = history.join("\n")
        messages_text = messages.join("\n")
        total_text = [status_text, history_text, messages_text].reject(&:empty?).join("\n")

        if total_text.length > max_length
          # Truncate proportionally, giving priority to status and history
          status_length = status_text.length
          history_length = history_text.length
          messages_length = messages_text.length
          total_length = total_text.length

          if total_length > 0
            status_max = [(max_length * 0.3).to_i, status_length].min if status_length > 0
            history_max = [(max_length * 0.5).to_i, history_length].min if history_length > 0
            messages_max = [(max_length * 0.2).to_i, messages_length].min if messages_length > 0

            latest_status = truncate_text(latest_status, status_max) if latest_status && status_max
            history = truncate_array(history, history_max) if history_max
            messages = truncate_array(messages, messages_max) if messages_max
          end
        end

        {
          latest_status: latest_status,
          history: history,
          messages: messages
        }
      end

      def extract_latest_status(doc)
        # First, check for component status lists (common pattern: "Component Name ? Operational")
        # Look for patterns like "Component ? Operational" or lists of components with status
        component_status_pattern = /([A-Za-z0-9\s-]+)\s+[?•]\s+(Operational|Degraded|Down|Outage|Maintenance)/i
        all_text = doc.text

        # Count operational vs non-operational components
        operational_matches = all_text.scan(component_status_pattern)
        if operational_matches.any?
          operational_count = operational_matches.count { |m| m[1]&.match?(/operational/i) }
          non_operational = operational_matches.reject { |m| m[1]&.match?(/operational/i) }

          # If all components are operational, return "Operational"
          if non_operational.empty? && operational_count > 0
            return "Operational"
          # If some are non-operational, check for active incidents
          elsif non_operational.any?
            # Check if there are active incidents (Investigating, Monitoring, Identified)
            if all_text.match?(/Investigating|Monitoring|Identified/i) && !all_text.match?(/Resolved|Completed/i)
              return "Degraded Performance"
            elsif non_operational.any? { |m| m[1]&.match?(/down|outage/i) }
              return "Partial Outage"
            else
              return "Degraded Performance"
            end
          end
        end

        # Try common status page selectors
        status_selectors = [
          ".status-indicator",
          ".status",
          "[class*='status-indicator']",
          "[data-status]",
          ".component-status",
          ".operational-status",
          ".current-status",
          "div[class*='indicator'][class*='status']",
          ".page-status",
          "main .status:first-of-type",
          ".status-page-status",
          "[data-component-status]",
          ".unresolved-incident",
          ".resolved-incident",
          "h1[class*='status']",
          "h2[class*='status']"
        ]

        status_text = nil
        status_selectors.each do |selector|
          element = doc.css(selector).first
          next unless element

          # Remove nested navigation and UI elements
          element.css("nav, .navigation, .menu, a, button, .button, .link").remove

          # Get text and clean it
          text = element.text.strip
          next if text.empty? || text.length < 3
          next if text.length > 300 # Too long, probably not a status indicator

          # Check for status keywords
          if text.match?(/operational|degraded|down|outage|incident|maintenance|all systems|resolved|investigating|partial|major|minor/i)
            status_text = text
            break
          end
        end

        # If no specific status found, try to find main content area
        unless status_text
          main_content = doc.css("main, .content, .status-content, .page-content, article, [role='main']").first
          if main_content
            # Remove UI elements from main content
            main_content.css("nav, header, footer, .navigation, .sidebar, .menu, form, input, button, .header, .footer").remove

            # Look for status-like text in first few headings
            headings = main_content.css("h1, h2, h3").first(5)
            headings.each do |heading|
              text = heading.text.strip
              # Check if it's a status (short and contains status keywords)
              # Exclude page structure patterns
              if text.length > 3 && text.length <= 200 &&
                  text.match?(/operational|degraded|down|outage|incident|maintenance|all systems|resolved|investigating|partial|major|minor/i) &&
                  !text.match?(/^(Support|Log in|Sign up|Subscribe|Email|Get|Visit|Click|Home|About)/i) &&
                  !text.match?(/Status.*Incident History|Incident History.*Status|.*Status.*-.*Incident/i)
                status_text = text
                break
              end
            end

            # If headings didn't work, try first short paragraph
            unless status_text
              paragraphs = main_content.css("p").first(5)
              short_paras = paragraphs.select { |p|
                text = p.text.strip
                text.length < 200 && text.length > 10 &&
                  text.match?(/operational|degraded|down|outage|incident|maintenance|all systems|resolved|investigating|partial|major|minor/i)
              }
              if short_paras.any?
                status_text = short_paras.first.text.strip
              end
            end
          end
        end

        # Fallback: extract from title (but filter out common page titles)
        unless status_text
          title = doc.css("title").first&.text&.strip
          if title && !title.match?(/^(Status|System Status|Service Status|.*Status)$/i)
            # Only use title if it's short and looks like a status
            if title.length < 100 && title.match?(/operational|degraded|down|outage|incident|maintenance/i)
              status_text = title
            end
          end
        end

        text = purify_text(status_text)
        # Filter out if it looks like navigation or UI
        return nil if text && (text.match?(/^(Support|Log in|Sign up|Subscribe|Email|Get|Visit|Click|Home|About)/i) || text.split(/\s+/).length > 20)
        # Filter out page structure patterns like "Service Status - Incident History"
        return nil if text&.match?(/Status.*Incident History|Incident History.*Status/i)
        text
      end

      def extract_history(doc)
        # Common history/incident selectors
        history_selectors = [
          ".incident",
          ".incident-list",
          ".history",
          ".timeline",
          ".status-update",
          ".update",
          "[class*='incident']",
          "[class*='history']",
          "[class*='timeline']",
          "[class*='update']",
          ".recent-incidents",
          ".past-incidents",
          "[data-incident]",
          ".incident-item",
          ".history-item",
          "article[class*='incident']",
          "article[class*='update']"
        ]

        history_items = []

        history_selectors.each do |selector|
          elements = doc.css(selector)
          next if elements.empty?

          elements.first(15).each do |element|
            # Remove nested navigation and UI elements
            element.css("nav, .navigation, .menu, script, style, .close, .dismiss, button, .button").remove

            text = element.text.strip
            next if text.empty? || text.length < 20

            # Clean up the text
            text = purify_text(text)
            history_items << text if text.length >= 20
          end

          break if history_items.any?
        end

        # If no specific history found, try to extract from main content
        if history_items.empty?
          main_content = doc.css("main, .content, article, [role='main']").first
          if main_content
            # Remove UI elements
            main_content.css("nav, header, footer, .navigation, .sidebar, .menu, form, input, button, .header, .footer").remove

            # Look for list items, sections, or divs that might be history
            items = main_content.css("li, .item, .entry, section, article, div[class*='incident'], div[class*='update'], div[class*='history']").first(20)
            items.each do |item|
              # Skip if it's too small or looks like navigation
              next if item.css("nav, .navigation, .menu").any?

              text = item.text.strip
              next if text.empty? || text.length < 20
              next if text.length > 2000 # Too long, probably not a single history item

              # Check if it looks like a status update (has date, time, or status keywords)
              if text.match?(/\d{4}|\d{1,2}\/\d{1,2}|\d{1,2}-\d{1,2}|\d{1,2}:\d{2}|UTC|EST|PST|operational|degraded|resolved|investigating|incident|outage|maintenance|update|resolved/i)
                cleaned = purify_text(text)
                history_items << cleaned if cleaned.length >= 20
              end
            end
          end
        end

        history_items.first(20) # Limit to 20 most recent
      end

      def extract_messages(doc)
        # Common message/announcement selectors
        message_selectors = [
          ".message",
          ".announcement",
          ".alert",
          ".notification",
          "[class*='message']",
          "[class*='announcement']",
          "[class*='alert']",
          ".banner-message",
          ".status-message"
        ]

        messages = []

        message_selectors.each do |selector|
          elements = doc.css(selector)
          next if elements.empty?

          elements.first(5).each do |element|
            element.css("script, style, .close, .dismiss").remove
            text = element.text.strip
            next if text.empty? || text.length < 10

            messages << purify_text(text)
          end

          break if messages.any?
        end

        messages.first(5) # Limit to 5 messages
      end

      def purify_text(text)
        return nil unless text

        # Remove common UI text patterns
        text = text.gsub(/Notifications.*?signed in.*?reload/im, "")
        text = text.gsub(/You must be signed in.*?reload/im, "")
        text = text.gsub(/There was an error.*?reload/im, "")
        text = text.gsub(/Please reload this page.*?/im, "")
        text = text.gsub(/Loading.*?/im, "")
        text = text.gsub(/Cookie|Privacy|Accept|Decline/i, "") if text.length < 50

        # Clean up whitespace
        text = text.gsub(/\n{3,}/, "\n\n")
        text = text.gsub(/[ \t]{2,}/, " ")
        text = text.strip

        # Remove excessive blank lines
        text.gsub(/\n{3,}/, "\n\n")
      end

      def truncate_text(text, max_length)
        return text unless text && text.length > max_length

        # Try to cut at a reasonable point (sentence or paragraph boundary)
        truncated = text[0..max_length]
        cut_point = truncated.rindex(/[.!?]\s+/) || truncated.rindex(/\n\n/) || truncated.rindex(/\n/) || max_length
        truncated[0..cut_point].strip + "..."
      end

      def truncate_array(items, max_total_length)
        return [] if items.empty?

        result = []
        current_length = 0

        items.each do |item|
          item_length = item.length
          if current_length + item_length <= max_total_length
            result << item
            current_length += item_length
          else
            # Try to fit partial item
            remaining = max_total_length - current_length
            if remaining > 100 # Only add if we have meaningful space left
              truncated_item = truncate_text(item, remaining)
              result << truncated_item
            end
            break
          end
        end

        result
      end
    end
  end
end
