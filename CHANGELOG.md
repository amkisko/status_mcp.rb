# CHANGELOG

## 0.1.1 (2026-09-08)

- Clamp `list_services` to 200 results and `fetch_status` extract length to 10000 characters
- Bound `fetch_status` HTTP hops and wall clock, and cap HTTP bodies at 1MB before they fill memory
- Fetch status pages live over HTTP; search, details, and list still use the bundled catalog
- Raise the json floor to 2.21.2 and require patched nokogiri 1.19.4 and rack 3.2.6
- Require Ruby 3.4, matching the gemspec and CI

## 0.1.0 (2025-11-26)

- Initial release
- MCP server with tools:
  - `search_services`: Search for services by name
  - `get_service_details`: Get detailed status links for a specific service
  - `list_services`: List all available services
- Data update script `bin/update_status_list` to fetch data from `awesome-status`
- Comprehensive test suite with RSpec
- Full documentation and CI/CD setup
