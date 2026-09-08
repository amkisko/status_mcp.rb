# Root lock lagged appraisal on published advisories

## Dependency

Gemfile.lock at the start of this pass pinned nokogiri 1.18.10, rack 3.2.4, addressable 2.8.8, and concurrent-ruby 1.3.5. Direct runtime: nokogiri ~> 1.18 and rack ~> 3.2. Transitive: addressable via webmock, concurrent-ruby via the runtime graph. gemfiles/ruby34.gemfile.lock and gemfiles/ruby40.gemfile.lock already pinned nokogiri 1.19.4, rack 3.2.6, addressable 2.9.0, and concurrent-ruby 1.3.7.

The coverage job in .github/workflows/test.yml uses the root lock. The matrix jobs use the appraisal locks.

## Symptom

After json 2.21.2, bundle-audit check --gemfile-lock Gemfile.lock still failed. Unique names: addressable (CVE-2026-35611), concurrent-ruby (CVE-2026-54904, CVE-2026-54905, CVE-2026-54906), nokogiri (GHSA-c4rq-3m3g-8wgx and the 2026 libxml set, patched in 1.19.4), rack (CVE-2026-22860 and later 3.2.x advisories, patched in 3.2.6). The same command on both appraisal locks reported no vulnerabilities. json was not in the advisory list.

nokogiri parses caller-chosen HTML and feeds on the fetch_status path. rack stays declared so fast-mcp can load. addressable and concurrent-ruby sit on the lock graph; this gem's source does not call them.

## Evidence

bundle-audit update on 2026-09-04 used ruby-advisory-db 1241 advisories, last updated 2026-09-04 08:47:17 -0400, commit 478717d12497338b42f77c0e237f5f6b83d94127.

The first audit pass described nokogiri 1.19.4 and rack 3.2.6 as current. That matched appraisal, not Gemfile.lock.

## Suggested fix

Shipped in this pass: conservative bundle update of those four packages on Gemfile.lock (nokogiri 1.19.4, rack 3.2.7, addressable 2.9.0, concurrent-ruby 1.3.8). Gemspec floors nokogiri ~> 1.18, >= 1.19.4 and rack ~> 3.2, >= 3.2.6 so gem consumers resolve the patched lines. rack stays declared for fast-mcp. bundle-audit check is clean on all three lockfiles after this bump.

## Source

Gemfile.lock
gemfiles/ruby34.gemfile.lock
gemfiles/ruby40.gemfile.lock
status_mcp.gemspec
.github/workflows/test.yml
usr/docs/issues/20260904174500_engineering-and-dependency-audit.md
https://github.com/sparklemotion/nokogiri/security/advisories/GHSA-c4rq-3m3g-8wgx
https://github.com/rack/rack/security/advisories/GHSA-mxw3-3hh2-x2mh
https://github.com/sporkmonger/addressable/security/advisories/GHSA-h27x-rffw-24p4
