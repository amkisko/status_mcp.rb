# Fetch budgets and json advisory floor

## Participants

Andrei Makarov

## Decisions

Clamp list_services limit to 200 and fetch_status max_length to 10000.

Cap fetch_status at two feed probes, six HTTP hops including redirects, and a 20 second wall clock. Raise MAX_FEED_PROBES or MAX_FETCH_REQUESTS when a vendor needs a longer hop chain.

Stream response bodies in chunks and raise ResponseSizeExceededError before the buffer holds more than 1MB. Content-Length still exits early.

Re-raise UnsafeUrlError and ResponseSizeExceededError from inner fetch rescues so a failed feed probe cannot swallow a blocked destination or oversized body.

Bump json to 2.21.2 on every lockfile and declare json >= 2.21.2 in the gemspec so downstream consumers get the GHSA-9hj4-r449-hfvc floor.

Floor nokogiri at 1.19.4 and rack at 3.2.6 in the gemspec. Align Gemfile.lock with those patched lines and with addressable 2.9.0 and concurrent-ruby 1.3.8. Appraisal locks already had the patched nokogiri and rack pins.

Pin vcr >= 6.4.0 so Ruby 4.0 can load spec_helper. CGI.parse is gone there.

Scan *.gemfile.lock in the advisory job. Pin actions/checkout v7 on test and trunk workflows to match the advisory workflow. Add Dependabot bundler for /gemfiles.

Keep fetch_status as live HTTP. Catalog-only mode stays an open product decision.

## Effects

FetchStatusTool now initializes StatusMcp::FetchBudget per call. NetworkPolicy private-method specs that call fetch_with_redirects without a budget still run; consume is optional.

README, CHANGELOG 0.1.1, and the .start spec list four tools and Ruby 3.4.

Later pass 20260904182800 ran bundle exec rspec: 193 examples, 0 failures. bundle-audit check --no-update is clean on Gemfile.lock, gemfiles/ruby34.gemfile.lock, and gemfiles/ruby40.gemfile.lock.

## Next

Tag and publish 0.1.1 when the maintainer wants a release.

Catalog-only fetch_status remains open.

## Source

usr/docs/issues/20260904174500_engineering-and-dependency-audit.md
usr/docs/dependencies/20260904174500_json-cve-2026-71847.md
usr/docs/dependencies/20260904182800_root-lock-advisory-alignment.md
usr/docs/dependencies/20260904182800_vcr-cgi-parse-ruby-40.md
lib/status_mcp/fetch_budget.rb
lib/status_mcp/server.rb
status_mcp.gemspec
CHANGELOG.md
README.md
.github/workflows/dependency-audit.yml
.github/workflows/test.yml
.github/dependabot.yml
