# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in `status_mcp`, please report it responsibly.

### How to Report

1. **Do NOT** open a public GitHub issue for security vulnerabilities
2. Email security details to: **contact@kiskolabs.com**
3. Include the following information:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if available)

### Response Timeline

- We will acknowledge receipt of your report within **48 hours**
- We will provide an initial assessment within **7 days**
- We will keep you informed of our progress and resolution timeline

### Disclosure Policy

- We will work with you to understand and resolve the issue quickly
- We will credit you for the discovery (unless you prefer to remain anonymous)
- We will publish a security advisory after the vulnerability is patched
- We will coordinate public disclosure with you

## Security Considerations

### Data Access

This gem accesses public status page information from `awesome-status`. No authentication is required.

**What this gem does:**
- Fetches public status page links from `awesome-status` README
- Provides MCP server tools for querying this information locally

**What this gem does NOT do:**
- Store or cache sensitive data
- Require authentication or API keys
- Access private or protected resources
- Execute arbitrary code or commands

### Network Security

- The data update script uses HTTPS to fetch the README
- The gem validates SSL certificates by default (except in the update script where it's explicitly disabled for compatibility, which is safe for public README fetching)

### Input Validation

- Search queries are validated before processing
- The gem handles malformed data gracefully

### Dependency Security

Keep dependencies up to date:

```bash
# Check for security vulnerabilities
bundle audit

# Update dependencies regularly
bundle update
```

## Security Updates

Security updates will be released as patch for the latest version.

For critical security vulnerabilities, we may release a security advisory and recommend immediate upgrade.

## Automation Security

* **Context Isolation:** It is strictly forbidden to include production credentials, API keys, or Personally Identifiable Information (PII) in prompts sent to third-party LLMs or automation services.

* **Supply Chain:** All automated dependencies must be verified.

## Contact

For security concerns, contact: **contact@kiskolabs.com**

For general support, open an issue on GitHub: https://github.com/amkisko/status_mcp.rb/issues
