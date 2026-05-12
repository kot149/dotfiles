Perform a comprehensive security review of the codebase$ARGUMENTS.

## Scope

If `$ARGUMENTS` is provided, focus the review on the specified file(s), directory, or feature area. Otherwise, review the entire codebase or the most security-sensitive parts.

## Review Checklist

Analyze the code against the following vulnerability categories:

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

Produce a structured report with the following sections:

### Executive Summary
A brief (2–4 sentence) overall risk assessment: severity distribution and most critical issues.

### Findings

For each finding, provide:

| Field | Content |
|---|---|
| **ID** | VULN-001, VULN-002, ... |
| **Severity** | Critical / High / Medium / Low / Informational |
| **Category** | e.g., SQL Injection, Hardcoded Secret |
| **Location** | File path and line number(s) |
| **Description** | What the vulnerability is and why it is dangerous |
| **Evidence** | Relevant code snippet |
| **Remediation** | Concrete fix with example code if applicable |

### Risk Summary Table

List all findings grouped by severity (Critical → Informational) with ID, category, and location.

### Recommendations

Prioritized list of actionable next steps beyond individual fixes (e.g., adopt a secrets manager, enable dependency scanning in CI, implement a WAF).
