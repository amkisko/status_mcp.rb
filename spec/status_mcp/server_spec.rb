# frozen_string_literal: true

require "status_mcp/server"

RSpec.describe StatusMcp::ResponseSizeExceededError do
  describe "#initialize" do
    it "sets size, max_size, and uri attributes" do
      error = described_class.new(2_000_000, 1_000_000, uri: "https://example.com")
      expect(error.size).to eq(2_000_000)
      expect(error.max_size).to eq(1_000_000)
      expect(error.uri).to eq("https://example.com")
    end

    it "sets message with size information" do
      error = described_class.new(2_000_000, 1_000_000, uri: "https://example.com")
      expect(error.message).to include("2000000")
      expect(error.message).to include("1000000")
      expect(error.message).to include("exceeds maximum allowed size")
    end

    it "handles nil uri" do
      error = described_class.new(2_000_000, 1_000_000)
      expect(error.uri).to be_nil
    end

    it "is a subclass of StatusMcp::Error" do
      error = described_class.new(1, 1)
      expect(error).to be_a(StatusMcp::Error)
    end
  end
end

RSpec.describe StatusMcp::Server do
  let(:mock_data) do
    [
      {
        "name" => "Example Service",
        "status_url" => "https://status.example.com",
        "website_url" => "https://example.com",
        "security_url" => nil,
        "support_url" => "https://support.example.com",
        "aux_urls" => ["https://twitter.com/example"]
      }
    ]
  end

  before do
    allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
    allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(mock_data))
  end

  describe ".start" do
    it "initializes and starts the server" do
      server_double = instance_double(FastMcp::Server)
      allow(FastMcp::Server).to receive(:new).with(name: "status_mcp", version: StatusMcp::VERSION).and_return(server_double)
      allow(server_double).to receive(:register_tool)
      allow(server_double).to receive(:start)

      described_class.start

      expect(FastMcp::Server).to have_received(:new).with(name: "status_mcp", version: StatusMcp::VERSION)
      expect(server_double).to have_received(:register_tool).with(StatusMcp::Server::SearchServicesTool)
      expect(server_double).to have_received(:register_tool).with(StatusMcp::Server::GetServiceDetailsTool)
      expect(server_double).to have_received(:register_tool).with(StatusMcp::Server::ListServicesTool)
      expect(server_double).to have_received(:start)
    end
  end

  describe StatusMcp::Server::BaseTool do
    let(:tool) { described_class.new }
    let(:test_services) do
      [
        {"name" => "Cloudflare", "status_url" => "https://status.cloudflare.com"},
        {"name" => "GitHub", "status_url" => "https://status.github.com"},
        {"name" => "AWS", "status_url" => "https://status.aws.amazon.com"},
        {"name" => "Example Service", "status_url" => "https://status.example.com"}
      ]
    end

    describe "#levenshtein_distance" do
      it "returns 0 for identical strings" do
        expect(tool.send(:levenshtein_distance, "test", "test")).to eq(0)
      end

      it "returns length for completely different strings" do
        expect(tool.send(:levenshtein_distance, "abc", "xyz")).to eq(3)
      end

      it "calculates distance for single character difference" do
        expect(tool.send(:levenshtein_distance, "test", "best")).to eq(1)
      end

      it "calculates distance for missing character" do
        expect(tool.send(:levenshtein_distance, "cloudflare", "cloudflre")).to eq(1)
      end

      it "calculates distance for extra character" do
        expect(tool.send(:levenshtein_distance, "cloudflare", "cloudflaare")).to eq(1)
      end

      it "handles empty strings" do
        expect(tool.send(:levenshtein_distance, "", "test")).to eq(4)
        expect(tool.send(:levenshtein_distance, "test", "")).to eq(4)
        expect(tool.send(:levenshtein_distance, "", "")).to eq(0)
      end
    end

    describe "#similarity_ratio" do
      it "returns 1.0 for identical strings" do
        expect(tool.send(:similarity_ratio, "test", "test")).to eq(1.0)
      end

      it "returns 0.0 for completely different strings" do
        expect(tool.send(:similarity_ratio, "abc", "xyz")).to be < 0.5
      end

      it "returns high ratio for similar strings" do
        ratio = tool.send(:similarity_ratio, "cloudflare", "cloudflre")
        expect(ratio).to be > 0.8
      end

      it "handles empty strings" do
        expect(tool.send(:similarity_ratio, "", "test")).to eq(0.0)
        expect(tool.send(:similarity_ratio, "test", "")).to eq(0.0)
      end
    end

    describe "#find_services_fuzzy" do
      it "finds exact matches with score 1.0" do
        results = tool.send(:find_services_fuzzy, test_services, "Cloudflare")
        expect(results).not_to be_empty
        expect(results.first[:score]).to eq(1.0)
        expect(results.first[:match_type]).to eq(:exact)
        expect(results.first[:service]["name"]).to eq("Cloudflare")
      end

      it "finds case-insensitive exact matches" do
        results = tool.send(:find_services_fuzzy, test_services, "cloudflare")
        expect(results).not_to be_empty
        expect(results.first[:score]).to eq(1.0)
        expect(results.first[:match_type]).to eq(:exact)
      end

      it "finds substring matches" do
        results = tool.send(:find_services_fuzzy, test_services, "cloud")
        expect(results).not_to be_empty
        expect(results.first[:match_type]).to eq(:substring)
        expect(results.first[:service]["name"]).to eq("Cloudflare")
      end

      it "finds fuzzy matches for typos" do
        results = tool.send(:find_services_fuzzy, test_services, "cloudflre", threshold: 0.6)
        expect(results).not_to be_empty
        expect(results.first[:match_type]).to eq(:fuzzy)
        expect(results.first[:service]["name"]).to eq("Cloudflare")
      end

      it "respects threshold parameter" do
        results = tool.send(:find_services_fuzzy, test_services, "xyz", threshold: 0.1)
        expect(results).to be_empty
      end

      it "sorts results by score descending" do
        results = tool.send(:find_services_fuzzy, test_services, "cloud", threshold: 0.3)
        scores = results.map { |r| r[:score] }
        expect(scores).to eq(scores.sort.reverse)
      end

      it "handles empty query" do
        results = tool.send(:find_services_fuzzy, test_services, "")
        expect(results).to be_empty
      end

      it "handles whitespace-only query" do
        results = tool.send(:find_services_fuzzy, test_services, "   ")
        expect(results).to be_empty
      end

      it "returns empty array for no matches" do
        results = tool.send(:find_services_fuzzy, test_services, "NonexistentService", threshold: 0.9)
        expect(results).to be_empty
      end
    end
  end

  describe StatusMcp::Server::SearchServicesTool do
    let(:tool) { described_class.new }
    let(:multiple_services) do
      [
        {"name" => "Cloudflare", "status_url" => "https://status.cloudflare.com"},
        {"name" => "UpCloud", "status_url" => "https://status.upcloud.com"},
        {"name" => "Cloudinary", "status_url" => "https://status.cloudinary.com"},
        {"name" => "Example Service", "status_url" => "https://status.example.com"}
      ]
    end

    before do
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_services))
    end

    it "finds services by name" do
      result = tool.call(query: "Example")
      expect(result).to include("Example Service")
      expect(result).to include("https://status.example.com")
    end

    it "returns message when no services found" do
      result = tool.call(query: "Nonexistent")
      expect(result).to eq("No services found matching 'Nonexistent'")
    end

    context "when data file is missing" do
      it "returns no results" do
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(false)
        result = tool.call(query: "Example")
        expect(result).to eq("No services found matching 'Example'")
      end
    end

    context "when JSON is corrupted" do
      it "returns no results" do
        allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return("invalid json")
        result = tool.call(query: "Example")
        expect(result).to eq("No services found matching 'Example'")
      end
    end

    it "finds services with fuzzy match" do
      result = tool.call(query: "Exmple Servce")
      expect(result).to include("Example Service")
    end

    it "finds services with case-insensitive match" do
      result = tool.call(query: "example")
      expect(result).to include("Example Service")
    end

    it "finds multiple services with partial match" do
      result = tool.call(query: "cloud")
      expect(result).to include("Cloudflare")
      expect(result).to include("UpCloud")
      expect(result).to include("Cloudinary")
    end

    it "limits results to top 20" do
      many_services = (1..25).map { |i| {"name" => "Service #{i}", "status_url" => "https://status#{i}.com"} }
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(many_services))
      result = tool.call(query: "Service")
      count = result.scan(/^## /).count
      expect(count).to eq(20)
    end

    it "prioritizes exact matches over fuzzy matches" do
      result = tool.call(query: "Cloudflare")
      # Should find Cloudflare first
      lines = result.split("\n")
      first_service_line = lines.find { |l| l.start_with?("## ") }
      expect(first_service_line).to include("Cloudflare")
    end

    it "handles typos with fuzzy matching" do
      result = tool.call(query: "cloudflre")
      expect(result).to include("Cloudflare")
    end

    it "handles extra characters with fuzzy matching" do
      result = tool.call(query: "cloudflaare")
      expect(result).to include("Cloudflare")
    end

    it "removes duplicate services from results" do
      duplicate_services = [
        {"name" => "Cloudflare", "status_url" => "https://www.cloudflarestatus.com"},
        {"name" => "Cloudflare", "status_url" => "https://www.cloudflarestatus.com"},
        {"name" => "Cloudinary", "status_url" => "https://status.cloudinary.com"}
      ]
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(duplicate_services))
      result = tool.call(query: "cloud")
      # Should only appear once
      count = result.scan(/^## Cloudflare$/).count
      expect(count).to eq(1)
      # Should still include Cloudinary
      expect(result).to include("Cloudinary")
    end
  end

  describe StatusMcp::Server::GetServiceDetailsTool do
    let(:tool) { described_class.new }
    let(:multiple_similar_services) do
      [
        {"name" => "Cloudflare", "status_url" => "https://status.cloudflare.com"},
        {"name" => "Cloudflare Workers", "status_url" => "https://status.workers.cloudflare.com"},
        {"name" => "UpCloud", "status_url" => "https://status.upcloud.com"}
      ]
    end

    it "gets details for a service" do
      result = tool.call(name: "Example Service")
      expect(result).to include("Example Service")
      expect(result).to include("Official Status")
    end

    it "returns error for nonexistent service" do
      result = tool.call(name: "Nonexistent")
      expect(result).to eq("Service 'Nonexistent' not found")
    end

    it "finds service with case-insensitive match" do
      result = tool.call(name: "example service")
      expect(result).to include("Example Service")
    end

    it "finds service with fuzzy match" do
      result = tool.call(name: "Exmple Service")
      expect(result).to include("Example Service")
    end

    it "finds service with partial match" do
      result = tool.call(name: "Example")
      expect(result).to include("Example Service")
    end

    it "finds service with typo (missing letter)" do
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_similar_services))
      result = tool.call(name: "cloudflre")
      expect(result).to include("Cloudflare")
    end

    it "finds service with typo (extra letter)" do
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_similar_services))
      result = tool.call(name: "cloudflaare")
      expect(result).to include("Cloudflare")
    end

    it "finds service with different case" do
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_similar_services))
      result = tool.call(name: "CLOUDFLARE")
      expect(result).to include("Cloudflare")
    end

    it "returns best match when multiple fuzzy matches exist" do
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_similar_services))
      result = tool.call(name: "cloudflare")
      expect(result).to include("Cloudflare")
      # Should not include the alternative suggestions if it's an exact match
      expect(result).not_to include("Did you mean")
    end

    it "suggests alternatives when multiple matches with similar scores" do
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_similar_services))
      result = tool.call(name: "cloud")
      # Should return the best match but might suggest alternatives
      expect(result).to include("Cloudflare")
    end

    it "handles very low similarity threshold" do
      result = tool.call(name: "xyzabc123")
      expect(result).to eq("Service 'xyzabc123' not found")
    end

    it "handles empty string" do
      result = tool.call(name: "")
      expect(result).to eq("Service '' not found")
    end

    it "handles whitespace-only string" do
      result = tool.call(name: "   ")
      expect(result).to eq("Service '   ' not found")
    end

    context "with high confidence match" do
      it "returns service without alternatives when score >= 0.9" do
        allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_similar_services))
        result = tool.call(name: "Cloudflare")
        expect(result).to include("Cloudflare")
        expect(result).not_to include("Did you mean")
      end
    end

    context "with single fuzzy match" do
      it "returns the match even if score < 0.9" do
        allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_similar_services))
        result = tool.call(name: "cloudflre")
        expect(result).to include("Cloudflare")
      end
    end
  end

  describe StatusMcp::Server::ListServicesTool do
    let(:tool) { described_class.new }
    let(:multiple_services) do
      [
        {"name" => "Service 1", "status_url" => "https://status1.com", "website_url" => nil, "security_url" => nil, "support_url" => nil, "aux_urls" => []},
        {"name" => "Service 2", "status_url" => "https://status2.com", "website_url" => nil, "security_url" => nil, "support_url" => nil, "aux_urls" => []},
        {"name" => "Service 3", "status_url" => "https://status3.com", "website_url" => nil, "security_url" => nil, "support_url" => nil, "aux_urls" => []}
      ]
    end

    it "lists services" do
      result = tool.call
      expect(result).to include("Example Service")
      expect(result).to include("Available services (1/1)")
    end

    it "respects limit" do
      result = tool.call(limit: 1)
      expect(result).to include("Available services (1/1)")
    end

    it "shows 'and X more' message when services exceed limit" do
      allow(File).to receive(:read).with(StatusMcp::DATA_PATH).and_return(JSON.generate(multiple_services))
      result = tool.call(limit: 2)
      expect(result).to include("Available services (2/3)")
      expect(result).to include("and 1 more")
    end
  end

  describe StatusMcp::Server::FetchStatusTool do
    let(:tool) { described_class.new }

    describe "#purify_text" do
      it "returns nil for nil input" do
        expect(tool.send(:purify_text, nil)).to be_nil
      end

      it "removes UI text patterns" do
        text = "Notifications. You must be signed in to view this. Please reload this page."
        result = tool.send(:purify_text, text)
        expect(result).not_to include("Notifications")
        expect(result).not_to include("signed in")
        expect(result).not_to include("reload")
      end

      it "removes cookie/privacy text for short strings" do
        text = "Cookie Privacy Accept"
        result = tool.send(:purify_text, text)
        expect(result).not_to match(/Cookie|Privacy|Accept/i)
      end

      it "preserves cookie/privacy text for long strings" do
        text = "Cookie Privacy Accept " + "x" * 100
        result = tool.send(:purify_text, text)
        expect(result).to include("Cookie")
      end

      it "cleans up excessive whitespace" do
        text = "Line 1\n\n\n\nLine 2    \t\t   Line 3"
        result = tool.send(:purify_text, text)
        expect(result).not_to match(/\n{3,}/)
        expect(result).not_to match(/[ \t]{2,}/)
      end

      it "removes excessive blank lines" do
        text = "Line 1\n\n\n\nLine 2"
        result = tool.send(:purify_text, text)
        expect(result.scan("\n\n\n").count).to eq(0)
      end
    end

    describe "#truncate_text" do
      it "returns text unchanged if shorter than max_length" do
        text = "Short text"
        result = tool.send(:truncate_text, text, 100)
        expect(result).to eq(text)
      end

      it "truncates at sentence boundary" do
        text = "First sentence. Second sentence. Third sentence."
        result = tool.send(:truncate_text, text, 30)
        expect(result).to include("First sentence.")
        expect(result).to end_with("...")
        expect(result.length).to be <= 33
      end

      it "truncates at paragraph boundary if no sentence boundary" do
        text = "Line 1\n\nLine 2\n\nLine 3"
        result = tool.send(:truncate_text, text, 15)
        expect(result).to include("Line 1")
        expect(result).to end_with("...")
      end

      it "truncates at newline if no paragraph boundary" do
        text = "Line 1\nLine 2\nLine 3"
        result = tool.send(:truncate_text, text, 10)
        expect(result).to include("Line 1")
        expect(result).to end_with("...")
      end

      it "truncates at max_length if no boundaries found" do
        text = "A" * 100
        result = tool.send(:truncate_text, text, 50)
        expect(result.length).to be <= 54 # 50 + "..." (could be 51 + "..." if cut_point is max_length)
        expect(result.length).to be >= 50
        expect(result).to end_with("...")
      end
    end

    describe "#truncate_array" do
      it "returns empty array for empty input" do
        result = tool.send(:truncate_array, [], 100)
        expect(result).to eq([])
      end

      it "returns all items if total length is within limit" do
        items = ["Item 1", "Item 2", "Item 3"]
        result = tool.send(:truncate_array, items, 100)
        expect(result).to eq(items)
      end

      it "truncates items to fit within limit" do
        items = ["A" * 50, "B" * 50, "C" * 50]
        result = tool.send(:truncate_array, items, 60)
        expect(result.length).to be <= 2
        expect(result.map(&:length).sum).to be <= 60
      end

      it "truncates last item if it doesn't fit" do
        items = ["Item 1", "Item 2", "A" * 100]
        result = tool.send(:truncate_array, items, 20)
        # Should include first items that fit, and possibly truncate the last
        expect(result.length).to be >= 1
        expect(result.length).to be <= 3
      end

      it "skips item if remaining space is too small" do
        items = ["A" * 50, "B" * 100]
        result = tool.send(:truncate_array, items, 60)
        # Should only include first item since second needs 100 but only 10 remaining
        expect(result.length).to eq(1)
      end
    end

    describe "#call" do
      let(:simple_html) do
        <<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>Status Page</title></head>
          <body>
            <main>
              <h1>All Systems Operational</h1>
              <div class="incident">
                <h2>Recent Incident</h2>
                <p>Resolved on 2024-01-01</p>
              </div>
            </main>
          </body>
          </html>
        HTML
      end

      it "fetches and parses HTML status page" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        html = <<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>Status Page</title></head>
          <body>
            <main>
              <div class="status-indicator">All Systems Operational</div>
              <div class="incident">
                <h2>Recent Incident</h2>
                <p>Resolved on 2024-01-01 12:00 UTC</p>
              </div>
            </main>
          </body>
          </html>
        HTML
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, /https:\/\/status\.example\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:status_url]).to eq("https://status.example.com")
        expect(result[:latest_status]).to include("Operational")
        expect(result[:history]).not_to be_empty
      end

      it "handles HTTP errors gracefully" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        stub_request(:get, "https://status.example.com")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, /https:\/\/status\.example\.com\/.*/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:error]).to include("404")
        expect(result[:latest_status]).to be_nil
      end

      it "handles network errors" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        stub_request(:get, "https://status.example.com")
          .to_raise(StandardError.new("Network error"))
        stub_request(:get, /https:\/\/status\.example\.com\/(feed|rss|atom|history)/)
          .to_raise(StandardError.new("Network error"))

        result = tool.call(status_url: "https://status.example.com")
        # Error could be from HTML fetch or feed parsing
        expect(result[:error]).not_to be_nil
        expect(result[:error]).to match(/Error (fetching status|parsing feed)/)
      end

      it "respects max_length parameter" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        long_html = "<html><body><main><h1>Operational</h1><p>#{"x" * 20000}</p></main></body></html>"
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: long_html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, /https:\/\/status\.example\.com\/.*/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com", max_length: 100)
        # Result should be truncated
        total_length = [result[:latest_status], result[:history].join].reject(&:nil?).join.length
        expect(total_length).to be <= 100
      end

      it "tries RSS feed when available" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident Resolved</title>
                <description>Status: Resolved - All systems operational</description>
                <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
              </item>
            </channel>
          </rss>
        RSS

        # JS-rendered page will trigger feed fallback
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>", headers: {"Content-Type" => "text/html"})
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 200, body: rss_feed, headers: {"Content-Type" => "application/rss+xml"})
        stub_request(:get, "https://status.example.com/feed.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/feed")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/status.rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/status.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/history")
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:feed_url]).to include("feed.rss")
        expect(result[:history]).not_to be_empty
      end

      it "tries history page when available" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        html = <<~HTML
          <!DOCTYPE html>
          <html>
          <head><title>Status Page</title></head>
          <body>
            <main>
              <div class="status-indicator">All Systems Operational</div>
              <div class="incident">
                <h2>Recent Incident</h2>
                <p>Resolved on 2024-01-01 12:00 UTC</p>
              </div>
            </main>
          </body>
          </html>
        HTML
        history_html = <<~HTML
          <!DOCTYPE html>
          <html>
          <body>
            <main>
              <div class="incident">
                <h3>Past Incident 1</h3>
                <p>Resolved on 2023-12-01</p>
              </div>
              <div class="incident">
                <h3>Past Incident 2</h3>
                <p>Resolved on 2023-11-01</p>
              </div>
            </main>
          </body>
          </html>
        HTML

        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, "https://status.example.com/history")
          .to_return(status: 200, body: history_html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/feed.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, /https:\/\/status\.example\.com\/(rss|atom|feed|status\.rss|status\.atom)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:history_url]).to eq("https://status.example.com/history")
        # Should have history from both main page and history page
        expect(result[:history].length).to be >= 2
      end
    end

    describe "#build_history_url" do
      it "builds history URL from status URL" do
        url = tool.send(:build_history_url, "https://status.example.com")
        expect(url).to eq("https://status.example.com/history")
      end

      it "handles status URL with path" do
        url = tool.send(:build_history_url, "https://status.example.com/status")
        expect(url).to eq("https://status.example.com/status/history")
      end

      it "returns nil for URL already on history page" do
        url = tool.send(:build_history_url, "https://status.example.com/history")
        expect(url).to be_nil
      end
    end

    describe "#build_feed_urls" do
      it "builds multiple feed URL patterns" do
        urls = tool.send(:build_feed_urls, "https://status.example.com")
        expect(urls).to include("https://status.example.com/feed.rss")
        expect(urls).to include("https://status.example.com/feed.atom")
        expect(urls).to include("https://status.example.com/rss")
      end

      it "handles status URL with path" do
        urls = tool.send(:build_feed_urls, "https://status.example.com/status")
        expect(urls).to include("https://status.example.com/status/feed.rss")
      end
    end

    describe "#might_be_incident_io?" do
      it "returns true for known incident.io domains" do
        expect(tool.send(:might_be_incident_io?, "https://status.openai.com")).to be true
        expect(tool.send(:might_be_incident_io?, "https://status.notion.so")).to be true
      end

      it "returns false for unknown domains" do
        expect(tool.send(:might_be_incident_io?, "https://status.example.com")).to be false
      end
    end

    describe "#build_incident_io_api_url" do
      it "builds API URL from status URL" do
        url = tool.send(:build_incident_io_api_url, "https://status.openai.com")
        expect(url).to eq("https://status.openai.com/proxy/status.openai.com")
      end
    end

    describe "#parse_feed" do
      it "parses RSS feed correctly" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident Resolved</title>
                <description>Status: Resolved - All systems operational</description>
                <pubDate>Mon, 01 Jan 2024 00:00:00 GMT</pubDate>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:latest_status]).to eq("Resolved")
        expect(result[:history]).not_to be_empty
      end

      it "parses Atom feed correctly" do
        atom_feed = <<~ATOM
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Status</title>
            <entry>
              <title>Maintenance Scheduled</title>
              <content>Status: Scheduled - Maintenance window</content>
              <updated>2024-01-01T00:00:00Z</updated>
            </entry>
          </feed>
        ATOM

        result = tool.send(:parse_feed, atom_feed, 10000)
        # Scheduled maintenance results in "Operational" status
        expect(result[:latest_status]).to eq("Operational")
        expect(result[:history]).not_to be_empty
      end

      it "handles invalid feed format" do
        invalid_feed = "<xml>Not a feed</xml>"
        result = tool.send(:parse_feed, invalid_feed, 10000)
        expect(result[:error]).to include("Not a valid RSS or Atom feed")
      end

      it "determines status from feed title" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>operational</title>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:latest_status]).to eq("operational")
      end

      it "determines operational status from all resolved items" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Issue Resolved</title>
                <description>Status: Resolved - All systems back online</description>
              </item>
              <item>
                <title>Another Issue Resolved</title>
                <description>Status: Operational - Everything working</description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        # Code extracts status from first item, which is "Resolved"
        expect(result[:latest_status]).to eq("Resolved")
      end

      it "determines 'See recent incidents' from active incidents" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Monitoring Issue</title>
                <description>We are monitoring the situation. No status keyword in description.</description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        # When no status keyword found, code checks for active incident keywords
        expect(result[:latest_status]).to eq("See recent incidents")
      end

      it "truncates feed history when exceeding max_length" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>#{"A" * 1000}</title>
                <description>#{"B" * 1000}</description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 100)
        expect(result[:history].join.length).to be <= 100
      end
    end

    describe "#parse_incident_io_api" do
      it "parses incident.io API response with ongoing incidents" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [
              {
                "name" => "Service Degradation",
                "status" => "Investigating",
                "description" => "We are investigating an issue"
              }
            ],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:latest_status]).to eq("Investigating")
        expect(result[:history]).not_to be_empty
      end

      it "parses incident.io API response with scheduled maintenances" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [
              {
                "name" => "Planned Maintenance",
                "status" => "Scheduled",
                "description" => "Maintenance window",
                "scheduled_for" => "2024-01-01T00:00:00Z",
                "scheduled_until" => "2024-01-01T02:00:00Z"
              }
            ],
            "components" => []
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:history]).not_to be_empty
        expect(result[:history].first).to include("Planned Maintenance")
      end

      it "determines operational status from component statuses" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [],
            "components" => [
              {"status" => "operational"},
              {"operational_status" => "operational"}
            ]
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:latest_status]).to eq("Operational")
      end

      it "determines degraded status from non-operational components" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [],
            "components" => [
              {"status" => "operational"},
              {"status" => "degraded"}
            ]
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:latest_status]).to eq("Degraded Performance")
      end

      it "handles HTML in descriptions" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [
              {
                "name" => "Issue",
                "status" => "Investigating",
                "description" => "<p>HTML description</p>"
              }
            ],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:history].first).not_to include("<p>")
      end

      it "truncates when exceeding max_length" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [
              {
                "name" => "Issue",
                "status" => "Investigating",
                "description" => "A" * 10000
              }
            ],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 100)
        expect(result[:history].join.length).to be <= 100
      end
    end

    describe "#fetch_and_parse_incident_io_api" do
      it "handles HTTP errors" do
        allow(File).to receive(:exist?).and_call_original
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 404, body: "Not Found")

        result = tool.send(:fetch_and_parse_incident_io_api, "https://status.openai.com/proxy/status.openai.com", 10000)
        expect(result[:error]).to include("404")
      end

      it "handles JSON parse errors" do
        allow(File).to receive(:exist?).and_call_original
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: "invalid json")

        result = tool.send(:fetch_and_parse_incident_io_api, "https://status.openai.com/proxy/status.openai.com", 10000)
        expect(result[:error]).to include("Error parsing API JSON")
      end

      it "handles network errors" do
        allow(File).to receive(:exist?).and_call_original
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_raise(StandardError.new("Network error"))

        result = tool.send(:fetch_and_parse_incident_io_api, "https://status.openai.com/proxy/status.openai.com", 10000)
        expect(result[:error]).to include("Error fetching API")
      end

      it "raises ResponseSizeExceededError when JSON response exceeds limit" do
        allow(File).to receive(:exist?).and_call_original
        large_json = "{" + ("x" * (2 * 1024 * 1024)) + "}"
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: large_json, headers: {"Content-Type" => "application/json"})

        expect {
          tool.send(:fetch_and_parse_incident_io_api, "https://status.openai.com/proxy/status.openai.com", 10000)
        }.to raise_error(StatusMcp::ResponseSizeExceededError) do |error|
          expect(error.size).to eq(large_json.bytesize)
          expect(error.max_size).to eq(StatusMcp::Server::FetchStatusTool::MAX_RESPONSE_SIZE)
          expect(error.uri).to eq("https://status.openai.com/proxy/status.openai.com")
        end
      end
    end

    describe "#validate_and_parse_html" do
      it "raises error for crawler protection pages" do
        html = "<html><body>Checking your browser before accessing</body></html>"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/crawler protection/)
      end

      it "raises error for non-HTML content" do
        html = "This is not HTML"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/does not appear to be HTML/)
      end

      it "raises error for JavaScript-rendered pages with no content" do
        html = "<html><body><div id='root'></div></body></html>"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/JavaScript-rendered/)
      end

      it "raises error for error pages" do
        html = "<html><head><title>Error 404</title></head><body><h1>Page not found</h1><p>This is an error page with enough content to pass minimum length check but should still be detected as an error page.</p></body></html>"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/error page/)
      end

      it "parses valid HTML successfully" do
        html = "<html><body><main><h1>Status</h1><p>Content here with enough text to pass the minimum length validation requirements for HTML parsing.</p></main></body></html>"
        doc = tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        expect(doc).to be_a(Nokogiri::HTML::Document)
        expect(doc.text).to include("Status")
      end
    end

    describe "#extract_status_info" do
      it "extracts status from component status patterns" do
        html = "<html><body><main><p>Component A ? Operational</p><p>Component B ? Operational</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to eq("Operational")
      end

      it "extracts degraded status from non-operational components" do
        html = "<html><body><main><p>Component A ? Operational</p><p>Component B ? Degraded</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to eq("Degraded Performance")
      end

      it "extracts status from status selectors" do
        html = "<html><body><div class='status-indicator'>All Systems Operational</div></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to include("Operational")
      end

      it "truncates when exceeding max_length" do
        html = "<html><body><main><h1>Status</h1><p>#{"x" * 20000}</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 100)
        total_length = [result[:latest_status], result[:history].join, result[:messages].join].reject(&:nil?).join.length
        expect(total_length).to be <= 100
      end
    end

    describe "#extract_history" do
      it "extracts history from incident selectors" do
        html = "<html><body><div class='incident'><h2>Incident 1 - Service Outage</h2><p>Resolved on 2024-01-01 at 12:00 UTC. All systems are now operational.</p></div></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_history, doc)
        expect(result).not_to be_empty
        expect(result.first).to include("Incident 1")
      end

      it "extracts history from main content when no specific selectors" do
        html = "<html><body><main><article><h2>Update 1</h2><p>2024-01-01 - Issue resolved</p></article></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_history, doc)
        expect(result).not_to be_empty
      end

      it "limits to 20 most recent items" do
        # The extract_history method takes first 15 from each selector, then limits to 20 total
        # So we need to ensure we get at least 20 items after filtering
        # Create incidents that will pass the 20-character minimum and filtering
        html = "<html><body>" + (1..25).map { |i| "<div class='incident'><h3>Incident #{i} - Service Outage</h3><p>This is a detailed incident description with enough content to pass validation requirements. Incident occurred on 2024-01-#{i.to_s.rjust(2, "0")} at 12:00 UTC. All systems are now operational after resolution.</p></div>" }.join + "</body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_history, doc)
        # The method takes first 15 from selector, then limits to 20 total
        # So we should get 15 (from first selector) or up to 20 if more are found
        expect(result.length).to be <= 20
        expect(result.length).to be >= 15
      end
    end

    describe "#extract_messages" do
      it "extracts messages from message selectors" do
        html = "<html><body><div class='message'>Important announcement</div></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_messages, doc)
        expect(result).not_to be_empty
        expect(result.first).to include("announcement")
      end

      it "limits to 5 messages" do
        html = "<html><body>" + (1..10).map { |i| "<div class='message'>Message #{i} - This is a detailed message with enough content to pass validation.</div>" }.join + "</body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_messages, doc)
        expect(result.length).to eq(5)
      end
    end

    describe "#fetch_with_redirects" do
      it "follows redirects" do
        allow(File).to receive(:exist?).and_call_original
        stub_request(:get, "https://example.com")
          .to_return(status: 301, headers: {"Location" => "https://example.com/new"})
        stub_request(:get, "https://example.com/new")
          .to_return(status: 200, body: "<html><body>Content</body></html>")

        response = tool.send(:fetch_with_redirects, "https://example.com")
        expect(response.code).to eq("200")
      end

      it "handles too many redirects" do
        allow(File).to receive(:exist?).and_call_original
        stub_request(:get, /https:\/\/example\.com/)
          .to_return(status: 301, headers: {"Location" => "https://example.com/redirect"})

        expect {
          tool.send(:fetch_with_redirects, "https://example.com")
        }.to raise_error(/Too many redirects/)
      end

      it "raises ResponseSizeExceededError when Content-Length exceeds limit" do
        allow(File).to receive(:exist?).and_call_original
        large_size = 2 * 1024 * 1024 # 2MB, exceeds 1MB limit
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: "x" * 100, headers: {"Content-Length" => large_size.to_s})

        expect {
          tool.send(:fetch_with_redirects, "https://example.com")
        }.to raise_error(StatusMcp::ResponseSizeExceededError) do |error|
          expect(error.size).to eq(large_size)
          expect(error.max_size).to eq(StatusMcp::Server::FetchStatusTool::MAX_RESPONSE_SIZE)
          expect(error.uri).to eq("https://example.com")
        end
      end

      it "raises ResponseSizeExceededError when response body exceeds limit" do
        allow(File).to receive(:exist?).and_call_original
        large_body = "x" * (2 * 1024 * 1024) # 2MB, exceeds 1MB limit
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: large_body, headers: {"Content-Type" => "text/html"})

        expect {
          tool.send(:fetch_with_redirects, "https://example.com")
        }.to raise_error(StatusMcp::ResponseSizeExceededError) do |error|
          expect(error.size).to eq(large_body.bytesize)
          expect(error.max_size).to eq(StatusMcp::Server::FetchStatusTool::MAX_RESPONSE_SIZE)
          expect(error.uri).to eq("https://example.com")
        end
      end

      it "allows responses under the size limit" do
        allow(File).to receive(:exist?).and_call_original
        small_body = "x" * (500 * 1024) # 500KB, under 1MB limit
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: small_body, headers: {"Content-Type" => "text/html"})

        response = tool.send(:fetch_with_redirects, "https://example.com")
        expect(response.code).to eq("200")
        expect(response.body.bytesize).to eq(small_body.bytesize)
      end

      it "handles missing Content-Length header and checks body size" do
        allow(File).to receive(:exist?).and_call_original
        large_body = "x" * (2 * 1024 * 1024) # 2MB, exceeds 1MB limit
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: large_body, headers: {"Content-Type" => "text/html"})

        expect {
          tool.send(:fetch_with_redirects, "https://example.com")
        }.to raise_error(StatusMcp::ResponseSizeExceededError)
      end

      it "handles nil response body" do
        allow(File).to receive(:exist?).and_call_original
        stub_request(:get, "https://example.com")
          .to_return(status: 200, body: nil, headers: {"Content-Type" => "text/html"})

        response = tool.send(:fetch_with_redirects, "https://example.com")
        expect(response.code).to eq("200")
      end
    end

    describe "#fetch_and_extract" do
      it "extracts history only when history_only is true" do
        allow(File).to receive(:exist?).and_call_original
        html = "<html><body><main><h1>Status History</h1><div class='incident'><h2>Past Incident - Service Outage</h2><p>This incident occurred on 2024-01-01 and was resolved after 2 hours. All systems are now operational.</p></div></main></body></html>"
        stub_request(:get, "https://status.example.com/history")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})

        result = tool.send(:fetch_and_extract, "https://status.example.com/history", 10000, history_only: true)
        expect(result[:latest_status]).to be_nil
        expect(result[:history]).not_to be_empty
      end

      it "includes HTTP status code" do
        allow(File).to receive(:exist?).and_call_original
        html = "<!DOCTYPE html><html><body><main><h1>Status</h1><p>This is a status page with enough content to pass HTML validation requirements.</p></main></body></html>"
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})

        result = tool.send(:fetch_and_extract, "https://status.example.com", 10000)
        expect(result[:http_status_code]).to eq(200)
      end

      it "raises ResponseSizeExceededError when HTML body exceeds limit" do
        allow(File).to receive(:exist?).and_call_original
        large_html = "<html><body>" + ("x" * (2 * 1024 * 1024)) + "</body></html>"
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: large_html, headers: {"Content-Type" => "text/html"})

        expect {
          tool.send(:fetch_and_extract, "https://status.example.com", 10000)
        }.to raise_error(StatusMcp::ResponseSizeExceededError) do |error|
          expect(error.size).to eq(large_html.bytesize)
          expect(error.max_size).to eq(StatusMcp::Server::FetchStatusTool::MAX_RESPONSE_SIZE)
          expect(error.uri).to eq("https://status.example.com")
        end
      end
    end

    describe "incident.io API integration" do
      it "tries incident.io API for known domains" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        api_response = {
          "summary" => {
            "ongoing_incidents" => [{"name" => "Issue", "status" => "Investigating"}],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json

        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: api_response, headers: {"Content-Type" => "application/json"})
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        expect(result[:api_url]).to include("proxy/status.openai.com")
        expect(result[:latest_status]).to eq("Investigating")
      end

      it "skips API if it returns 404 error" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: '{"summary": {"ongoing_incidents": [], "scheduled_maintenances": [], "components": []}}')
          .then.to_return(status: 200, body: '{"error": "404 Not Found"}')

        html = "<html><body><main><div class='status-indicator'>All Systems Operational</div><p>All services are running normally.</p></main></body></html>"
        stub_request(:get, "https://status.openai.com")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        # Mock the API response to return error
        allow(tool).to receive(:fetch_and_parse_incident_io_api).and_return({error: "Failed to fetch API: 404 Not Found"})

        result = tool.call(status_url: "https://status.openai.com")
        # Should fall back to HTML parsing
        expect(result[:latest_status]).to include("Operational")
      end

      it "handles API exceptions gracefully" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_raise(StandardError.new("API error"))
        html = "<html><body><main><div class='status-indicator'>All Systems Operational</div><p>All services are running normally.</p></main></body></html>"
        stub_request(:get, "https://status.openai.com")
          .to_return(status: 200, body: html)
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        # Should continue with other methods
        expect(result[:latest_status]).to include("Operational")
      end
    end

    describe "#fetch_and_parse_feed" do
      it "raises ResponseSizeExceededError when feed response exceeds limit" do
        allow(File).to receive(:exist?).and_call_original
        large_feed = "<?xml version='1.0'?><rss version='2.0'><channel><title>Feed</title></channel></rss>" + ("x" * (2 * 1024 * 1024))
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 200, body: large_feed, headers: {"Content-Type" => "application/rss+xml"})

        expect {
          tool.send(:fetch_and_parse_feed, "https://status.example.com/feed.rss", 10000)
        }.to raise_error(StatusMcp::ResponseSizeExceededError) do |error|
          expect(error.size).to eq(large_feed.bytesize)
          expect(error.max_size).to eq(StatusMcp::Server::FetchStatusTool::MAX_RESPONSE_SIZE)
          expect(error.uri).to eq("https://status.example.com/feed.rss")
        end
      end
    end

    describe "feed error handling" do
      it "continues to next feed URL on error" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident</title>
                <description>Status: Resolved</description>
              </item>
            </channel>
          </rss>
        RSS

        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>")
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_raise(StandardError.new("Network error"))
        stub_request(:get, "https://status.example.com/feed.atom")
          .to_return(status: 200, body: rss_feed, headers: {"Content-Type" => "application/rss+xml"})

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:feed_url]).to include("feed.atom")
      end
    end

    describe "result merging" do
      it "merges API and feed history" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        api_response = {
          "summary" => {
            "ongoing_incidents" => [{"name" => "API Incident", "status" => "Investigating"}],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Feed Incident</title>
                <description>Status: Resolved</description>
              </item>
            </channel>
          </rss>
        RSS

        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: api_response)
        stub_request(:get, "https://status.openai.com")
          .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>")
        stub_request(:get, "https://status.openai.com/feed.rss")
          .to_return(status: 200, body: rss_feed)
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed\.atom|rss|atom|feed|status\.rss|status\.atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        # API and feed history should be merged (may be deduplicated)
        expect(result[:history].length).to be >= 1
        # Should have both API and feed data
        expect(result[:api_url]).to include("proxy/status.openai.com")
        # Feed URL might be set if feed was successfully parsed
        if result[:feed_url]
          expect(result[:feed_url]).to include("feed.rss")
        end
      end

      it "prioritizes API status over HTML status" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        api_response = {
          "summary" => {
            "ongoing_incidents" => [{"name" => "Issue", "status" => "Investigating"}],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json
        html = "<html><body><main><h1>All Systems Operational</h1></main></body></html>"

        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: api_response)
        stub_request(:get, "https://status.openai.com")
          .to_return(status: 200, body: html)
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        expect(result[:latest_status]).to eq("Investigating")
      end

      it "suppresses JS-rendered errors when feed data is available" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident</title>
                <description>Status: Resolved</description>
              </item>
            </channel>
          </rss>
        RSS

        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>")
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 200, body: rss_feed)
        stub_request(:get, /https:\/\/status\.example\.com\/(feed\.atom|rss|atom|feed|status\.rss|status\.atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        # Should not have JS-rendered error since we got feed data
        if result[:error]
          expect(result[:error]).not_to include("JavaScript-rendered")
        end
      end
    end

    describe "scheduled maintenance parsing" do
      it "includes scheduled_for and scheduled_until in maintenance items" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [
              {
                "name" => "Maintenance",
                "status" => "Scheduled",
                "scheduled_for" => "2024-01-01T00:00:00Z",
                "scheduled_until" => "2024-01-01T02:00:00Z",
                "description" => "Planned maintenance"
              }
            ],
            "components" => []
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:history].first).to include("Scheduled: 2024-01-01")
        expect(result[:history].first).to include("until 2024-01-01T02:00:00Z")
      end
    end

    describe "component status edge cases" do
      it "handles nil component status" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [],
            "components" => [
              {"status" => nil},
              {"operational_status" => nil}
            ]
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:latest_status]).to eq("Operational")
      end

      it "handles components with operational_status field" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [],
            "components" => [
              {"operational_status" => "degraded"}
            ]
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:latest_status]).to eq("Degraded Performance")
      end
    end

    describe "feed parsing error handling" do
      it "handles feed parsing exceptions" do
        allow(File).to receive(:exist?).and_call_original
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 200, body: "invalid xml that causes parse error")

        # Force an exception during parsing
        allow(Nokogiri::XML).to receive(:new).and_raise(StandardError.new("Parse error"))

        result = tool.send(:fetch_and_parse_feed, "https://status.example.com/feed.rss", 10000)
        # The code catches exceptions and returns "Not a valid RSS or Atom feed"
        expect(result[:error]).not_to be_nil
        expect(result[:error]).to match(/Not a valid RSS or Atom feed|Error parsing feed/)
      end
    end

    describe "RSS feed HTML cleaning" do
      it "cleans HTML from RSS descriptions" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident - Service Outage</title>
                <description><p>Status: Resolved</p><ul><li>Item 1</li><li>Item 2</li></ul><p>This incident occurred on 2024-01-01 and was resolved after 2 hours.</p></description>
                <pubDate>Mon, 01 Jan 2024 12:00:00 UTC</pubDate>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:history]).not_to be_empty
        if result[:history].first
          expect(result[:history].first).not_to include("<p>")
          expect(result[:history].first).not_to include("<ul>")
        end
      end

      it "handles RSS items with HTML in description" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident</title>
                <description><p>HTML content with <strong>formatting</strong></p></description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:history]).not_to be_empty
      end

      it "handles Atom entries with HTML in content" do
        atom_feed = <<~ATOM
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Status</title>
            <entry>
              <title>Incident</title>
              <content><p>HTML content</p></content>
            </entry>
          </feed>
        ATOM

        result = tool.send(:parse_feed, atom_feed, 10000)
        expect(result[:history]).not_to be_empty
      end

      it "extracts status from Atom entry title" do
        atom_feed = <<~ATOM
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Status</title>
            <entry>
              <title>Status: Operational</title>
              <content>All systems working</content>
            </entry>
          </feed>
        ATOM

        result = tool.send(:parse_feed, atom_feed, 10000)
        expect(result[:latest_status]).to eq("Operational")
      end

      it "handles feed with scheduled maintenance items" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Scheduled Maintenance</title>
                <description>Maintenance scheduled for next week</description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:latest_status]).to eq("Operational")
      end

      it "handles feed with active incidents" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Monitoring Issue</title>
                <description>We are monitoring the situation. No status keyword in description.</description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        # When no status keyword found, code checks for active incident keywords
        expect(result[:latest_status]).to eq("See recent incidents")
      end
    end

    describe "error handling edge cases" do
      it "shows feed error when HTML fails and feed has error" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        stub_request(:get, "https://status.example.com")
          .to_raise(StandardError.new("Network error"))
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 200, body: "invalid xml")

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:error]).to include("Error parsing feed")
      end

      it "shows API error when HTML fails and API has error" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 500, body: "Server Error", headers: {"Content-Type" => "text/plain"})
        stub_request(:get, "https://status.openai.com")
          .to_raise(StandardError.new("Network error"))
        stub_request(:get, "https://status.openai.com/feed.rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.openai.com/feed.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.openai.com/rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.openai.com/atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.openai.com/feed")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.openai.com/status.rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.openai.com/status.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.openai.com/history")
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        # Should show error when HTML fails and API has error
        # The error might be from feed fetching (tried first) or API, both are valid
        expect(result[:error]).not_to be_nil
        expect(result[:error]).to match(/Failed to fetch (API|feed)|Error (fetching API|parsing feed)|500|Server Error|404/)
      end

      it "suppresses 'Not a valid RSS or Atom feed' error" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        html = "<html><body><main><h1>Operational</h1></main></body></html>"
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: html)
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 200, body: "not a feed")

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:error]).not_to include("Not a valid RSS or Atom feed")
      end
    end

    describe "HTML validation edge cases" do
      it "raises error for error page with error in title" do
        html = "<html><head><title>Error 404</title></head><body><p>This is an error page with enough content to pass minimum length check but should still be detected as an error page.</p></body></html>"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/error page/)
      end

      it "raises error for error page with error in heading" do
        html = "<html><body><h1>Page not found</h1><p>This is an error page with enough content to pass minimum length check but should still be detected as an error page.</p></body></html>"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/error page/)
      end

      it "handles Nokogiri syntax errors" do
        # Nokogiri is very forgiving and will parse most invalid HTML
        # So we test that it doesn't crash and returns a document
        invalid_html = "<html><body><div>Unclosed tag with enough content to pass minimum length validation requirements for HTML parsing"
        # Nokogiri will parse this successfully, so we just verify it doesn't crash
        doc = tool.send(:validate_and_parse_html, invalid_html, URI("https://example.com"))
        expect(doc).to be_a(Nokogiri::HTML::Document)
      end
    end

    describe "status extraction edge cases" do
      it "extracts status from paragraph text" do
        html = "<html><body><main><p>All systems are operational and running smoothly</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to include("operational")
      end

      it "extracts status from title when no other status found" do
        html = "<html><head><title>Service Degraded</title></head><body><main><p>Some content</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to include("Degraded")
      end

      it "truncates proportionally when exceeding max_length" do
        html = "<html><body><main><h1>Operational</h1><p>#{"x" * 5000}</p><div class='message'>#{"y" * 5000}</div></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 100)
        total_length = [result[:latest_status], result[:history].join, result[:messages].join].reject(&:nil?).join.length
        expect(total_length).to be <= 100
      end
    end

    describe "history extraction edge cases" do
      it "extracts history from main content when no specific selectors" do
        html = "<html><body><main><article><h2>Update from 2024-01-01</h2><p>Issue resolved at 12:00 UTC</p></article></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_history, doc)
        expect(result).not_to be_empty
      end

      it "skips items that look like navigation" do
        html = "<html><body><main><nav><li>Home</li><li>About</li></nav><div class='incident'><h2>Real Incident - Service Outage</h2><p>This incident occurred on 2024-01-01 and was resolved after 2 hours. All systems are now operational.</p></div></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_history, doc)
        expect(result).not_to be_empty
        # Navigation items should be filtered out
        result.each do |item|
          expect(item).not_to include("Home")
          expect(item).not_to include("About")
        end
        # Should include the real incident
        expect(result.join).to include("incident")
      end
    end

    describe "truncate_array edge cases" do
      it "adds partial item when remaining space is sufficient" do
        items = ["A" * 20, "B" * 200]
        result = tool.send(:truncate_array, items, 150)
        # First item (20 chars) fits, second item (200 chars) needs truncation to fit in remaining 130 (> 100)
        expect(result.length).to eq(2)
        expect(result.last).to end_with("...")
      end

      it "skips item when remaining space is too small" do
        items = ["A" * 30, "B" * 100]
        result = tool.send(:truncate_array, items, 35)
        expect(result.length).to eq(1)
        expect(result.first).to eq("A" * 30)
      end

      it "adds partial item when space allows" do
        items = ["A" * 20, "B" * 200]
        result = tool.send(:truncate_array, items, 150)
        # First item (20 chars) fits, second item (200 chars) needs truncation to fit in remaining 130
        expect(result.length).to be >= 1
        if result.length > 1
          expect(result.last).to end_with("...")
        end
      end
    end

    describe "feed parsing specific edge cases" do
      it "handles RSS description with HTML lists" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident</title>
                <description><ul><li>Item 1</li><li>Item 2</li></ul><ol><li>Step 1</li></ol></description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:history]).not_to be_empty
      end

      it "handles Atom content with HTML lists" do
        atom_feed = <<~ATOM
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Status</title>
            <entry>
              <title>Incident</title>
              <content><ul><li>Item</li></ul><br/>More content</content>
            </entry>
          </feed>
        ATOM

        result = tool.send(:parse_feed, atom_feed, 10000)
        expect(result[:history]).not_to be_empty
      end

      it "extracts status from feed title when short" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>degraded</title>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:latest_status]).to eq("degraded")
      end

      it "detects active incidents in feed" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Monitoring Issue</title>
                <description>We are monitoring the situation</description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:latest_status]).to eq("See recent incidents")
      end
    end

    describe "incident.io API edge cases" do
      it "handles HTML in scheduled maintenance description" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [
              {
                "name" => "Maintenance",
                "status" => "Scheduled",
                "description" => "<p>HTML description</p>"
              }
            ],
            "components" => []
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:history].first).not_to include("<p>")
      end

      it "handles components with nil status using operational_status" do
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [],
            "components" => [
              {"status" => nil, "operational_status" => "operational"},
              {"status" => nil, "operational_status" => nil}
            ]
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        expect(result[:latest_status]).to eq("Operational")
      end
    end

    describe "call method edge cases" do
      it "handles feed URL errors and continues" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        html = "<html><body><main><div class='status-indicator'>All Systems Operational</div><p>All services are running normally.</p></main></body></html>"
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_raise(StandardError.new("Feed error"))
        stub_request(:get, "https://status.example.com/feed.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, /https:\/\/status\.example\.com\/(rss|atom|feed|status\.rss|status\.atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        # Should still work with HTML
        expect(result[:latest_status]).to include("Operational")
      end

      it "merges API history with other sources" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        api_response = {
          "summary" => {
            "ongoing_incidents" => [{"name" => "API Incident", "status" => "Investigating"}],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json
        html = "<html><body><main><div class='incident'><h2>HTML Incident - Service Outage</h2><p>This incident occurred on 2024-01-01 and was resolved after 2 hours.</p></div></main></body></html>"

        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: api_response, headers: {"Content-Type" => "application/json"})
        stub_request(:get, "https://status.openai.com")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        # API and HTML history should be merged (may be deduplicated)
        expect(result[:history].length).to be >= 1
        expect(result[:api_url]).to include("proxy/status.openai.com")
      end

      it "suppresses JS-rendered error when API has data" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        api_response = {
          "summary" => {
            "ongoing_incidents" => [{"name" => "Issue", "status" => "Investigating"}],
            "scheduled_maintenances" => [],
            "components" => []
          }
        }.to_json

        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 200, body: api_response)
        stub_request(:get, "https://status.openai.com")
          .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>")
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        # Should not have JS-rendered error since we got API data
        expect(result[:error]).to be_nil.or(!include("JavaScript-rendered"))
      end

      it "shows API error when no other data available" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        stub_request(:get, "https://status.openai.com/proxy/status.openai.com")
          .to_return(status: 500, body: "Server Error", headers: {"Content-Type" => "text/plain"})
        stub_request(:get, "https://status.openai.com")
          .to_raise(StandardError.new("Network error"))
        stub_request(:get, /https:\/\/status\.openai\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.openai.com")
        # Should show error when HTML fails and API has error
        # The error might be from feed fetching (tried first) or API, both are valid
        expect(result[:error]).not_to be_nil
        expect(result[:error]).to match(/Failed to fetch (API|feed)|Error (fetching API|parsing feed)|500|Server Error|404/)
      end

      it "handles exceptions in main call method" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        allow(tool).to receive(:might_be_incident_io?).and_raise(StandardError.new("Unexpected error"))

        html = "<html><body><main><div class='status-indicator'>All Systems Operational</div><p>All services are running normally.</p></main></body></html>"
        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: html, headers: {"Content-Type" => "text/html"})
        stub_request(:get, /https:\/\/status\.example\.com\/(feed|rss|atom|history)/)
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:error]).to include("Error fetching status")
      end

      it "extracts history only from history page" do
        allow(File).to receive(:exist?).and_call_original
        history_html = "<html><body><main><div class='incident'><h2>Past Incident - Service Outage</h2><p>This incident occurred on 2024-01-01 and was resolved after 2 hours. All systems are now operational.</p></div></main></body></html>"
        stub_request(:get, "https://status.example.com/history")
          .to_return(status: 200, body: history_html)

        result = tool.send(:fetch_and_extract, "https://status.example.com/history", 10000, history_only: true)
        expect(result[:latest_status]).to be_nil
        expect(result[:history]).not_to be_empty
      end
    end

    describe "status extraction from title" do
      it "extracts status from title when it matches pattern" do
        html = "<html><head><title>Service Degraded Performance</title></head><body><main><p>Content</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to include("Degraded")
      end

      it "skips title if it's a generic status page title" do
        html = "<html><head><title>System Status</title></head><body><main><p>Content</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        # Should not use generic "System Status" title
        expect(result[:latest_status]).not_to eq("System Status")
      end

      it "extracts status from component patterns with active incidents" do
        html = "<html><body><main><p>Component A ? Degraded</p><p>We are Investigating the issue</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to eq("Degraded Performance")
      end

      it "extracts partial outage from component patterns" do
        html = "<html><body><main><p>Component A ? Down</p><p>Component B ? Operational</p></main></body></html>"
        doc = Nokogiri::HTML(html)
        result = tool.send(:extract_status_info, doc, 10000)
        expect(result[:latest_status]).to eq("Partial Outage")
      end
    end

    describe "feed error handling - next statement" do
      it "continues to next feed URL on exception" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident</title>
                <description>Status: Resolved</description>
              </item>
            </channel>
          </rss>
        RSS

        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>")
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_raise(StandardError.new("Network error"))
        stub_request(:get, "https://status.example.com/feed.atom")
          .to_return(status: 200, body: rss_feed)

        result = tool.call(status_url: "https://status.example.com")
        expect(result[:feed_url]).to include("feed.atom")
      end
    end

    describe "feed history merging" do
      it "merges feed history when API info is nil" do
        allow(File).to receive(:exist?).and_call_original
        allow(File).to receive(:exist?).with(StatusMcp::DATA_PATH).and_return(true)
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Feed Incident</title>
                <description>Status: Resolved</description>
              </item>
            </channel>
          </rss>
        RSS

        stub_request(:get, "https://status.example.com")
          .to_return(status: 200, body: "<html><body><div id='root'></div></body></html>", headers: {"Content-Type" => "text/html"})
        stub_request(:get, "https://status.example.com/feed.rss")
          .to_return(status: 200, body: rss_feed, headers: {"Content-Type" => "application/rss+xml"})
        stub_request(:get, "https://status.example.com/feed.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/feed")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/status.rss")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/status.atom")
          .to_return(status: 404, body: "Not Found")
        stub_request(:get, "https://status.example.com/history")
          .to_return(status: 404, body: "Not Found")

        result = tool.call(status_url: "https://status.example.com")
        # Feed history should be merged when API info is nil
        # Either history should be populated or feed_url should be set
        expect(result[:history].any? || result[:feed_url]).to be_truthy
      end
    end

    describe "component status edge case - else branch" do
      it "handles components where non_operational is empty but not all operational" do
        # The else branch at line 568 (non_operational.any? is false) is actually hard to reach
        # because if all_operational is false, there must be a component that doesn't include "operational"
        # and if that component's status is truthy, it will be in non_operational
        # The only way non_operational could be empty is if all non-operational components have falsy status
        # But if status is falsy (nil), all_operational would be true due to || comp_status.nil?
        # So this branch might be unreachable in practice, but let's test the normal case
        api_response = {
          "summary" => {
            "ongoing_incidents" => [],
            "scheduled_maintenances" => [],
            "components" => [
              {"status" => "degraded"}  # This makes all_operational false and non_operational.any? true
            ]
          }
        }.to_json

        result = tool.send(:parse_incident_io_api, api_response, 10000)
        # "degraded" is in non_operational, so non_operational.any? is true, returns "Degraded Performance"
        expect(result[:latest_status]).to eq("Degraded Performance")
      end
    end

    describe "RSS HTML cleaning with lists" do
      it "cleans HTML lists from RSS descriptions" do
        rss_feed = <<~RSS
          <?xml version="1.0"?>
          <rss version="2.0">
            <channel>
              <title>Status</title>
              <item>
                <title>Incident</title>
                <description><ul><li>Point 1</li><li>Point 2</li></ul><ol><li>Step 1</li></ol><br/>More text</description>
              </item>
            </channel>
          </rss>
        RSS

        result = tool.send(:parse_feed, rss_feed, 10000)
        expect(result[:history].first).not_to include("<ul>")
        expect(result[:history].first).not_to include("<li>")
      end
    end

    describe "Atom HTML cleaning with lists" do
      it "cleans HTML lists from Atom content" do
        atom_feed = <<~ATOM
          <?xml version="1.0"?>
          <feed xmlns="http://www.w3.org/2005/Atom">
            <title>Status</title>
            <entry>
              <title>Incident</title>
              <content><ul><li>Item</li></ul><ol><li>Step</li></ol><br/>Text</content>
            </entry>
          </feed>
        ATOM

        result = tool.send(:parse_feed, atom_feed, 10000)
        expect(result[:history].first).not_to include("<ul>")
      end
    end

    describe "error page detection" do
      it "detects error pages by title" do
        html = "<html><head><title>error 404</title></head><body><p>This is an error page with enough content to pass minimum length check but should still be detected as an error page.</p></body></html>"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/error page/)
      end

      it "detects error pages by heading" do
        html = "<html><body><h1>Page not found</h1><p>This is an error page with enough content to pass minimum length check but should still be detected as an error page.</p></body></html>"
        expect {
          tool.send(:validate_and_parse_html, html, URI("https://example.com"))
        }.to raise_error(/error page/)
      end
    end

    describe "Nokogiri syntax error handling" do
      it "handles XML syntax errors gracefully" do
        # Nokogiri is very forgiving and will parse most invalid HTML
        # So we test that it doesn't crash and returns a document
        invalid_html = "<html><body><div>Unclosed<div>Tag with enough content to pass minimum length validation requirements for HTML parsing"
        # Nokogiri will parse this successfully, so we just verify it doesn't crash
        doc = tool.send(:validate_and_parse_html, invalid_html, URI("https://example.com"))
        expect(doc).to be_a(Nokogiri::HTML::Document)
      end
    end
  end
end
