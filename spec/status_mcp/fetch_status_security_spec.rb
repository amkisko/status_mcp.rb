# frozen_string_literal: true

require "spec_helper"
require "status_mcp/server"

RSpec.describe StatusMcp::Server::FetchStatusTool do
  subject(:tool) { described_class.new }

  before do
    allow(Addrinfo).to receive(:getaddrinfo).and_call_original
    allow(Addrinfo).to receive(:getaddrinfo)
      .with("example.com", anything, nil, :STREAM)
      .and_return([Addrinfo.ip("93.184.216.34")])
    allow(Addrinfo).to receive(:getaddrinfo)
      .with("status.example.com", anything, nil, :STREAM)
      .and_return([Addrinfo.ip("93.184.216.34")])
  end

  it "rejects loopback destinations before making a request" do
    result = tool.call(status_url: "http://127.0.0.1/admin")

    expect(result[:error]).to include("URL destination is not allowed")
    expect(a_request(:get, "http://127.0.0.1/admin")).not_to have_been_made
  end

  it "rejects private IPv6 destinations before making a request" do
    result = tool.call(status_url: "http://[fd00::1]/status")

    expect(result[:error]).to include("URL destination is not allowed")
    expect(a_request(:get, "http://[fd00::1]/status")).not_to have_been_made
  end

  it "rejects hostnames that resolve to a private destination" do
    result = tool.call(status_url: "http://localhost/status")

    expect(result[:error]).to include("URL destination is not allowed")
    expect(a_request(:get, "http://localhost/status")).not_to have_been_made
  end

  it "rejects URL userinfo" do
    result = tool.call(status_url: "https://user:password@example.com/status")

    expect(result[:error]).to include("URL destination is not allowed")
    expect(a_request(:get, "https://user:password@example.com/status")).not_to have_been_made
  end

  it "revalidates redirect destinations" do
    stub_request(:get, %r{https://example\.com/status/})
      .to_return(status: 404, body: "Not Found")
    stub_request(:get, "https://example.com/status")
      .to_return(status: 302, headers: {"Location" => "http://127.0.0.1/admin"})

    result = tool.call(status_url: "https://example.com/status")

    expect(result[:error]).to include("URL destination is not allowed")
    expect(a_request(:get, "http://127.0.0.1/admin")).not_to have_been_made
  end

  it "does not probe every common feed path" do
    stub_request(:get, /https:\/\/status\.example\.com/)
      .to_return(status: 404, body: "Not Found")

    tool.call(status_url: "https://status.example.com")

    expect(a_request(:get, "https://status.example.com/rss")).not_to have_been_made
    expect(a_request(:get, "https://status.example.com/status.rss")).not_to have_been_made
    expect(a_request(:get, "https://status.example.com/status.atom")).not_to have_been_made
  end

  it "stops further fetches after the wall clock deadline" do
    now = 1_000.0
    allow(StatusMcp::FetchBudget).to receive(:monotonic_now) { now }
    stub_request(:get, /https:\/\/status\.example\.com/).to_return do
      now += 30
      {status: 404, body: "Not Found"}
    end

    tool.call(status_url: "https://status.example.com")

    expect(a_request(:get, "https://status.example.com/feed.rss")).to have_been_made
    expect(a_request(:get, "https://status.example.com/feed.atom")).not_to have_been_made
    expect(a_request(:get, "https://status.example.com")).not_to have_been_made
  end

  it "returns a size error when the body exceeds one megabyte without Content-Length" do
    large_body = "x" * (2 * 1024 * 1024)
    stub_request(:get, /https:\/\/status\.example\.com\/(feed|rss|atom|history)/)
      .to_return(status: 404, body: "Not Found")
    stub_request(:get, "https://status.example.com")
      .to_return(status: 200, body: large_body, headers: {"Content-Type" => "text/html"})

    result = tool.call(status_url: "https://status.example.com")

    expect(result[:error]).to include("Response size limit exceeded")
  end

  it "clamps max_length to the extract ceiling" do
    long_html = "<html><body><main><h1>Operational</h1><p>#{"x" * 20_000}</p></main></body></html>"
    stub_request(:get, "https://status.example.com")
      .to_return(status: 200, body: long_html, headers: {"Content-Type" => "text/html"})
    stub_request(:get, /https:\/\/status\.example\.com\/.*/)
      .to_return(status: 404, body: "Not Found")

    result = tool.call(status_url: "https://status.example.com", max_length: 1_000_000)
    total_length = [result[:latest_status], result[:history].join].reject(&:nil?).join.length

    expect(total_length).to be <= described_class::MAX_EXTRACT_LENGTH
  end
end
