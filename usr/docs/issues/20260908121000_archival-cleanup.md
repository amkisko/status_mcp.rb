# Archival cleanup

## Participants

Andrei Makarov

## Decisions

Stay on main. Do not open a patch or feature branch for this pass.

Ship unpublished 0.1.1 on main before GitHub archive. Published RubyGems and GitHub release remain 0.1.0 until gem push of 0.1.1.

Point README Status at status-cli for new status-page CLI and automation work. Keep this gem in low-priority support.

Do not archive GitHub, GitLab, or Codeberg until the operator asks after 0.1.1 is on RubyGems.

Leave catalog-only fetch_status as an open product decision. Do not implement it in this pass.

## Effects

GitHub had no open issues and no open pull requests. Remote heads were only main.

Local leftover branch patch/fetch-budgets-and-json-cve sat behind main. Its fetch-budget and advisory work is on the 0.1.1 commit. The local branch is deleted.

Stale origin/dependabot tracking refs were pruned. GitHub no longer has those heads.

README Status now names status-cli as the preferred new surface.

Quality on the 0.1.1 tree: bundle exec rspec spec/status_mcp/fetch_status_security_spec.rb spec/status_mcp/server_spec.rb:428, 10 examples, 0 failures. bundle exec rspec, 193 examples, 0 failures. make lint: rubocop 21 files, no offenses; rbs validate succeeded.

GitHub archive is not done in this pass.

## Next

Publish gem 0.1.1 with gem push from a TTY that can complete MFA.

After RubyGems accepts 0.1.1, tag 0.1.1 with no v prefix and cut a matching GitHub release.

Archive GitHub when the operator asks. GitLab and Codeberg archive wait for the same ask.

Catalog-only fetch_status remains open.

## Source

usr/docs/changelogs/20260904180000_fetch-budgets-and-json-cve.md
usr/docs/issues/20260904174500_engineering-and-dependency-audit.md
https://github.com/amkisko/status_mcp.rb
https://github.com/amkisko/status-cli.rs
https://rubygems.org/gems/status_mcp
