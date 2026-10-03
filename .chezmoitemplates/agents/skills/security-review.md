---
name: security-review
description: Perform a structured security review of code, dependencies, configuration, or a repository. Use when the user asks for a security review, vulnerability audit, OWASP review, secret scan, or dependency risk review. This is a standalone scan of code at rest, not a review of a diff or PR; for those, use deep-review.
---

# Security Review

Review the requested scope. If no scope is provided, focus on the most security-sensitive parts of the codebase.

## Review Checklist

Analyze the code against the following vulnerability categories.

### OWASP Top 10

- **A01 Broken Access Control**: Missing authorization checks, privilege escalation, IDOR (Insecure Direct Object References), CORS misconfiguration
- **A02 Cryptographic Failures**: Weak algorithms (MD5, SHA1, DES), hardcoded keys, insecure transmission (HTTP), improper certificate validation
- **A03 Injection**: SQL injection, NoSQL injection, OS command injection, LDAP injection, XPath injection, template injection
- **A04 Insecure Design**: Missing threat modeling, insecure design patterns, lack of rate limiting or anti-automation
- **A05 Security Misconfiguration**: Default credentials, unnecessary features enabled, verbose error messages, missing security headers
- **A06 Vulnerable and Outdated Components**: Outdated dependencies with known CVEs, unmaintained libraries
- **A07 Identification and Authentication Failures**: Weak passwords, missing MFA, insecure session management, credential exposure
- **A08 Software and Data Integrity Failures**: Insecure deserialization, unsigned updates, CI/CD pipeline integrity issues
- **A09 Security Logging and Monitoring Failures**: Missing audit logs, insufficient logging of security events, log injection
- **A10 Server-Side Request Forgery (SSRF)**: Unvalidated URLs in server-side requests, internal network exposure

### Additional Vulnerability Categories

- **Cross-Site Scripting (XSS)**: Reflected, stored, and DOM-based XSS; missing output encoding; unsafe use of `innerHTML`, `eval`, `dangerouslySetInnerHTML`
- **Secret and Credential Leakage**: Hardcoded API keys, tokens, passwords, private keys; secrets in version-controlled files or environment variable misuse
- **Input Validation**: Missing or insufficient validation, path traversal, file upload vulnerabilities, regex denial of service (ReDoS)
- **Cross-Site Request Forgery (CSRF)**: Missing CSRF tokens, SameSite cookie attributes
- **Security Headers**: Missing `Content-Security-Policy`, `X-Frame-Options`, `Strict-Transport-Security`, `X-Content-Type-Options`
- **Dependency Vulnerabilities**: Known CVEs in third-party packages; check `package.json`, `requirements.txt`, `go.mod`, etc.
- **Race Conditions and TOCTOU**: Time-of-check to time-of-use issues, concurrent access to shared resources without proper locking
- **Unsafe Randomness**: Use of non-cryptographic random number generators for security-sensitive operations

## Report Format

### Executive Summary

A 2-4 sentence overall risk assessment: severity distribution and the most critical issues.

### Findings

Ordered by severity. For each finding include:

- ID: `VULN-001`, `VULN-002`, ...
- Severity: Critical, High, Medium, Low, or Informational
- Category, e.g. SQL Injection, Hardcoded Secret
- Location with file and line
- Description: what the vulnerability is and why it is dangerous
- Evidence with a short code snippet or concrete behavior
- Remediation with concrete fix guidance

### Risk Summary Table

All findings grouped by severity (Critical to Informational), with ID, category, and location.

### Recommendations

Prioritized next steps beyond individual fixes, such as adopting a secrets manager or enabling dependency scanning in CI.

## Guardrails

- Do not include long code excerpts.
- Distinguish confirmed vulnerabilities from hardening suggestions.
- Do not modify code unless the user explicitly asks for fixes.
