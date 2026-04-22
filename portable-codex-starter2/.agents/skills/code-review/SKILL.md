---
name: code-review
description: Run a structured code review with severity-ranked findings
---

# Code Review

Use this skill for a review pass over a branch, diff, feature, or file set.

## Review priorities

1. correctness
2. regressions
3. security
4. maintainability
5. performance
6. test coverage

## Workflow

1. Identify the scope.
2. Read the changed code and nearby context.
3. Look for defects, not style trivia.
4. Rank issues by severity.
5. Cite file paths and concrete reasoning.

## Output

- Critical findings
- High findings
- Medium findings
- Low findings
- Open questions
- Overall recommendation

## Guardrails

- Findings first, summary second.
- If there are no findings, say so explicitly.
- Mention testing gaps even when code looks correct.
