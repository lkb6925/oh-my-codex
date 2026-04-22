---
name: security-review
description: Run a security-focused review over code or configuration changes
---

# Security Review

Use this skill for authentication, authorization, secrets handling, input validation, or other trust-boundary changes.

## Review priorities

- hardcoded secrets
- injection risks
- broken access control
- auth and session issues
- insecure defaults
- unsafe dependency choices

## Workflow

1. Define the trust boundary.
2. Inspect how untrusted input enters and flows.
3. Check authz, validation, and output handling.
4. Look for secret exposure and unsafe defaults.
5. Rank findings by severity and recommend remediations.

## Output

- Findings by severity
- File references
- Risk explanation
- Remediation guidance
- Overall security posture
