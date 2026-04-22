---
name: analyze
description: Run evidence-driven investigation before deciding on a fix
---

# Analyze

Use this skill for root-cause analysis, architecture diagnosis, or questions that ask "why".

## Workflow

1. State the observed result.
2. Generate at least two competing hypotheses.
3. Gather evidence for and against each hypothesis.
4. Down-rank explanations that require extra assumptions.
5. Return the current best explanation, the main unknown, and the next discriminating check.

## Quality bar

- Distinguish observation from inference.
- Prefer file evidence, runtime evidence, and direct inspection over intuition.
- Include evidence against your leading explanation.
- Do not jump directly into implementation unless the user asks for a fix.

## Suggested delegation

- `architect` for architecture or cross-file reasoning
- `debugger` for failure isolation
- `planner` for scoping the next investigation steps

## Output

- Observed result
- Ranked hypotheses
- Evidence for each
- Evidence against each
- Best current explanation
- Critical unknown
- Recommended next step
