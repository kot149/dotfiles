---
name: security-review
description: Perform a structured security review of code, dependencies, configuration, or a repository. Use when the user asks for a security review, vulnerability audit, OWASP review, secret scan, dependency risk review, or security-focused code review.
---

# Security Review

Review the requested scope. If no scope is provided, focus on the most security-sensitive parts of the codebase.

## Checklist

Cover relevant categories:

- OWASP Top 10: access control, cryptographic failures, injection, insecure design, misconfiguration, vulnerable components, authentication failures, data integrity failures, logging/monitoring gaps, SSRF
- XSS: reflected, stored, DOM-based, unsafe HTML sinks, `eval`, `dangerouslySetInnerHTML`
- secrets: hardcoded API keys, tokens, passwords, private keys, credential misuse
- input validation: path traversal, file upload issues, ReDoS, insufficient validation
- CSRF and cookie attributes
- missing security headers
- dependency vulnerabilities and unmaintained packages
- race conditions and TOCTOU
- unsafe randomness in security-sensitive code

## Report Format

Start with findings, ordered by severity. For each finding include:

- ID: `VULN-001`, `VULN-002`, ...
- Severity: Critical, High, Medium, Low, or Informational
- Category
- Location with file and line
- Description and impact
- Evidence with a short code snippet or concrete behavior
- Remediation with concrete fix guidance

Then include:

- Executive summary: 2-4 sentences
- Risk summary table grouped by severity
- Prioritized recommendations beyond individual fixes

## Guardrails

- Do not include long code excerpts.
- Distinguish confirmed vulnerabilities from hardening suggestions.
- Do not modify code unless the user explicitly asks for fixes.
