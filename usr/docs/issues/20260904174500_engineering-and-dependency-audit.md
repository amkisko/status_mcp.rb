# Engineering and dependency audit

0.1.0 local MCP server that serves a bundled awesome-status catalog and fetches caller-chosen public status URLs.

Later pass 20260904180000 implemented the ranked code, lockfile, README, and CI fixes. Catalog-only fetch_status stayed open. See usr/docs/changelogs/20260904180000_fetch-budgets-and-json-cve.md.

Later pass 20260904182800: bundle exec rspec ran 193 examples, 0 failures. bundle-audit check --no-update is clean on all three lockfiles after json 2.21.2, vcr 6.4.0, and root-lock alignment of nokogiri, rack, addressable, and concurrent-ruby. Finding 3 json pin is closed. Finding 8 mixed appraisal current pins with the root lock; the coverage job uses Gemfile.lock. See usr/docs/dependencies/20260904182800_root-lock-advisory-alignment.md and usr/docs/dependencies/20260904182800_vcr-cgi-parse-ruby-40.md.

## Decisions

The first pass was review only. The follow-up shipped hop and wall-clock budgets, limit clamps, streaming body cap, json 2.21.2, README and CHANGELOG 0.1.1, and advisory-job coverage of *.gemfile.lock. fetch_status remains live HTTP.

The 20260904182800 pass found vcr 6.3.1 on the root lock could not load spec_helper on Ruby 4.0.2. Appraisal already used vcr 6.4.0. Gemspec now asks vcr ~> 6.3, >= 6.4.0. Root Gemfile.lock also lagged appraisal on nokogiri, rack, addressable, and concurrent-ruby. Gemspec floors nokogiri >= 1.19.4 and rack >= 3.2.6.

Rank is danger, then certainty, then impact, then fix cost. Observed facts stay separate from inference.

## Effects

### Pipeline

MCP STDIN and STDOUT enter FastMcp. Tool handlers read assets/data.json on every call. fetch_status then issues sequential Net::HTTP GETs to public hosts. There is no cache, queue, or named RSS, heap, CPU, or energy ceiling. Egress is JSON and text to the MCP client. STDERR is swallowed unless DEBUG is set.

NetworkPolicy still fail-closes private, loopback, link-local, reserved, and userinfo destinations and pins the resolved address on each hop, including redirects. That closes the direct SSRF path recorded in usr/docs/issues/20260730141001_status-fetch-destination-policy.md. Residual risk is public-host amplification and post-download body size.

### Ranked findings

1. Shipped 20260904180000. fetch_status still accepts any public HTTP or HTTPS URL. Hop budget is six requests including redirects. Feed probes are two. Wall clock is 20 seconds via FetchBudget. Bodies stream in chunks and raise before the buffer holds more than 1MB. Catalog-only mode remains an open Next from the destination-policy note.

2. Shipped 20260904180000. list_services limit clamps to 200. fetch_status max_length clamps to 10000.

3. Closed 20260904182800. Lockfiles now pin json 2.21.2. Gemspec declares json >= 2.21.2. bundle-audit no longer lists this advisory. The original finding was json 2.21.1 on all three locks, CVE-2026-71847 / GHSA-9hj4-r449-hfvc, a heap use-after-free in JSON::ResumableParser#partial_value. This gem calls JSON.parse. Evidence: usr/docs/dependencies/20260904174500_json-cve-2026-71847.md.

4. Shipped 20260904180000. README, CHANGELOG 0.1.1, and the gemspec agree on Ruby 3.4, four tools, and live fetch_status.

5. Partial. lib/status_mcp/server.rb is still large. The remaining send(: cluster in server_spec.rb was left. fetch_status_security_spec.rb now proves destination policy, hop cap, deadline, body cap, and clamps through tool.call. .start registers FetchStatusTool. Split of server.rb stays a Next.

6. load_data parses the 492023-byte catalog on every tool call. search_services runs Levenshtein over catalog names. Unbenchmarked. Claims of cost stay inference until a bench exists.

7. Shipped 20260904180000. The advisory job finds Gemfile.lock or *.gemfile.lock. Dependabot bundler covers /gemfiles. test.yml and trunk check pin actions/checkout v7. The missed scan would have hidden the root-lock lag in finding 8, not a json mismatch on appraisal.

8. Later-pass correction 20260904182800. The first pass described nokogiri 1.19.4 and rack 3.2.6 as current. That matched appraisal, not Gemfile.lock. Root lock at that time pinned nokogiri 1.18.10, rack 3.2.4, addressable 2.8.8, and concurrent-ruby 1.3.5. The coverage job in test.yml uses the root lock. After json 2.21.2, bundle-audit still failed on Gemfile.lock for those four packages. Appraisal locks were already clean. Shipped: Gemfile.lock now nokogiri 1.19.4, rack 3.2.7, addressable 2.9.0, concurrent-ruby 1.3.8. Gemspec floors nokogiri >= 1.19.4 and rack >= 3.2.6. rack stays declared for fast-mcp. fast-mcp 1.6.0 is current on the registry. GitHub last push is 2025-12-15. Watch cluster unchanged. Evidence: usr/docs/dependencies/20260904182800_root-lock-advisory-alignment.md.

Fetched HTML and feed text return to the MCP client. An agent that follows that text as instruction is a learned-systems concern. That path was not demonstrated. STDERR suppression hides fetch failures from the operator unless DEBUG is set.

### Dependency graph

Direct runtime: fast-mcp ~> 1.6, nokogiri ~> 1.18, rack ~> 3.2, base64 ~> 0.3. Ruby >= 3.4.

Hot-path libyears from RubyGems created_at dates, audit day 2026-09-04:

json 2.21.1 to 2.21.2 is 0.047 years.
rack 3.2.6 to 3.2.7 is 0.367 years.
zeitwerk 2.8.2 to 2.8.3 is 0.189 years.
fast-mcp, nokogiri, base64, addressable, and dry-schema are current.
Hot-path total lag about 0.60 years. Average across those eight packages about 0.075 years. Major-version distance on the hot path is 0. Compact graph, low lag band.

Dev lag that is blocked by the Gemfile is not hot-path neglect. rbs is requested ~> 3.9 while 4.2.0 exists. simplecov is requested ~> 0.22 while 1.1.1 exists.

bundle-audit database: 1241 advisories, last updated 2026-09-04 08:47:17 -0400, commit 478717d12497338b42f77c0e237f5f6b83d94127.

OSINT: fast-mcp 1.6.0 published 2025-09-28, about 2.49 million downloads, MIT, MFA on the gem, GitHub yjacquin/fast-mcp, 1189 stars, 66 open issues, last push 2025-12-15. nokogiri 1.19.4 published 2026-06-18, sparklemotion/nokogiri, 6278 stars, 124 open issues, last push 2026-08-31. rack 3.2.6, latest 3.2.7 on 2026-08-13. base64 0.3.0 current. addressable 2.9.0 current. dry-schema 1.16.0 current. GitHub stats for ruby/json timed out.

### Tests

Present and real: NetworkPolicy examples for loopback, private IPv6, localhost DNS, userinfo, and redirect-to-private. FetchStatusTool behavior coverage exists in server_spec.rb. fetch_status_security_spec.rb now proves loopback, private, userinfo, redirect-to-private via tool.call, feed hop cap, wall-clock deadline via FetchBudget.monotonic_now, 2MB body without Content-Length, max_length clamp, list_services limit clamp, and .start registration of FetchStatusTool.

Futile relative to spec/README.md: the remaining private-method send(: cluster in server_spec.rb.

Later pass 20260904182800: bundle exec rspec, 193 examples, 0 failures.

### Validation this session

First pass: wc -l on lib and spec files. server.rb 1255, server_spec.rb 2249, network_policy.rb 55, fetch_status_security_spec.rb 44. Catalog: 1721 services, 492023 bytes. bundle-audit update succeeded. bundle-audit check failed on all three lockfiles with json 2.21.1. bundle outdated listed json, rack, zeitwerk on the runtime graph.

Later pass 20260904182800: bundle exec rspec, 193 examples, 0 failures. bundle-audit check --no-update: No vulnerabilities found on Gemfile.lock, gemfiles/ruby34.gemfile.lock, and gemfiles/ruby40.gemfile.lock. Advisory DB unchanged from the first pass. vcr 6.3.1 on the root lock failed to load spec_helper on Ruby 4.0.2 until vcr 6.4.0.

## Next

- Tag and publish 0.1.1 when the maintainer wants a release.
- Catalog-only fetch_status remains an open product decision.
- Split server.rb by tool when a later behavior change already requires a file touch.
- Bench catalog load and Levenshtein before claiming cost.
- Decide whether STDERR should stay silent for MCP STDIO hygiene.

## Source

- lib/status_mcp/server.rb
- lib/status_mcp/network_policy.rb
- spec/status_mcp/server_spec.rb
- spec/status_mcp/fetch_status_security_spec.rb
- status_mcp.gemspec
- README.md
- CHANGELOG.md
- Gemfile.lock
- gemfiles/ruby34.gemfile.lock
- gemfiles/ruby40.gemfile.lock
- .github/workflows/dependency-audit.yml
- .github/workflows/test.yml
- .github/dependabot.yml
- usr/docs/issues/20260730141001_status-fetch-destination-policy.md
- usr/docs/dependencies/20260904174500_json-cve-2026-71847.md
- usr/docs/dependencies/20260904182800_root-lock-advisory-alignment.md
- usr/docs/dependencies/20260904182800_vcr-cgi-parse-ruby-40.md
- usr/docs/changelogs/20260904180000_fetch-budgets-and-json-cve.md
- https://github.com/ruby/json/security/advisories/GHSA-9hj4-r449-hfvc
- https://osv.dev/vulnerability/GHSA-9hj4-r449-hfvc
- https://rubygems.org/gems/json
- https://github.com/yjacquin/fast-mcp
- https://github.com/sparklemotion/nokogiri
