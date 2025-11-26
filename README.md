# status_mcp

[![Gem Version](https://badge.fury.io/rb/status_mcp.svg)](https://badge.fury.io/rb/status_mcp) [![Test Status](https://github.com/amkisko/status_mcp.rb/actions/workflows/test.yml/badge.svg)](https://github.com/amkisko/status_mcp.rb/actions/workflows/test.yml) [![codecov](https://codecov.io/gh/amkisko/status_mcp.rb/graph/badge.svg)](https://codecov.io/gh/amkisko/status_mcp.rb)

Ruby gem providing status page information from [awesome-status](https://github.com/amkisko/awesome-status) via MCP (Model Context Protocol) server tools. Integrates with MCP-compatible clients like Cursor IDE, Claude Desktop, and other MCP-enabled tools.

Sponsored by [Kisko Labs](https://www.kiskolabs.com).

<a href="https://www.kiskolabs.com">
  <img src="kisko.svg" width="200" alt="Sponsored by Kisko Labs" />
</a>

## Requirements

- **Ruby 3.1 or higher** (Ruby 3.0 and earlier are not supported)

## Quick Start

```bash
gem install status_mcp
```

### Cursor IDE Configuration

For Cursor IDE, create or update `.cursor/mcp.json` in your project:

```json
{
  "mcpServers": {
    "status": {
      "command": "gem",
      "args": ["exec", "status_mcp"],
      "env": {
        "RUBY_VERSION": "3.4.7"
      }
    }
  }
}
```

**Note**: Using `gem exec` ensures the correct Ruby version is used.

### Claude Desktop Configuration

For Claude Desktop, edit the MCP configuration file:

**macOS**: `~/Library/Application Support/Claude/claude_desktop_config.json`  
**Windows**: `%APPDATA%\Claude\claude_desktop_config.json`

```json
{
  "mcpServers": {
    "status": {
      "command": "gem",
      "args": ["exec", "status_mcp"],
      "env": {
        "RUBY_VERSION": "3.4.7"
      }
    }
  }
}
```

**Note**: After updating the configuration, restart Claude Desktop for changes to take effect.

### Running the MCP Server manually

After installation, you can start the MCP server immediately:

```bash
# With bundler
gem install status_mcp && bundle exec status_mcp

# Or if installed globally
status_mcp
```

The server will start and communicate via STDIN/STDOUT using the MCP protocol.

## Features

- **Status Page Information**: Access to over 1700 status page links from `awesome-status`
- **MCP Server Integration**: Ready-to-use MCP server with tools for searching and retrieving status page details
- **No Authentication Required**: All data is bundled with the gem
- **Offline Capable**: Once installed, the data is available locally

## MCP Tools

The MCP server provides the following tools:

1. **search_services** - Search for services by name
   - Parameters: `query` (string)

2. **get_service_details** - Get detailed status links for a specific service
   - Parameters: `name` (string)

3. **list_services** - List all available services (limited to first 50 if too many)
   - Parameters: `limit` (optional integer, default: 50)

## Development

```bash
# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Run tests across multiple Ruby versions
bundle exec appraisal install
bundle exec appraisal rspec

# Run linting
bundle exec standardrb --fix
```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/amkisko/status_mcp.rb.

For more information, see [CONTRIBUTING.md](CONTRIBUTING.md).

## Security

If you discover a security vulnerability, please report it responsibly. See [SECURITY.md](SECURITY.md) for details.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
