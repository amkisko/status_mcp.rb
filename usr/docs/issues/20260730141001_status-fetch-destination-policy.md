# Status fetch destination policy

## Decisions

Caller-selected status URLs remain supported, but every outbound request uses one fail-closed policy. Only HTTP and HTTPS are accepted. URL credentials and private, loopback, link-local, multicast, unspecified, documentation, and other reserved IPv4 and IPv6 ranges are rejected.

DNS is resolved before the request, the validated address is pinned on the HTTP connection, and derived incident, feed, history, and redirect URLs are independently revalidated.

## Effects

The direct SSRF path through status_url and its derived requests is closed. Focused tests cover literal loopback and private IPv6 addresses, private DNS results, URL userinfo, and a redirect from a public host to a private address.

The complete make test command passed after the change.

## Next

- Keep future redirect or transport support behind NetworkPolicy.
- Consider a catalog-only mode if deployments do not require arbitrary public status domains.

## Source

- lib/status_mcp/network_policy.rb
- lib/status_mcp/server.rb
- spec/status_mcp/fetch_status_security_spec.rb
- spec/status_mcp/server_spec.rb
