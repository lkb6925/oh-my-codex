---
name: ai-slop-cleaner
description: Clean up bloated or over-abstracted code without changing behavior
---

# AI Slop Cleaner

Use this skill for cleanup, refactor, or deslop work after AI-generated code landed but needs tightening.

## Workflow

1. Lock behavior with targeted tests when practical.
2. Write a cleanup plan before editing.
3. Categorize the main smells:
   - dead code
   - duplication
   - needless abstraction
   - weak naming
   - missing tests
4. Fix one smell class at a time.
5. Re-run verification after each pass.

## Guardrails

- Prefer deletion over additional abstractions.
- Keep the diff bounded.
- Do not change behavior under the name of cleanup.

## Output

- Scope
- Cleanup plan
- Passes completed
- Verification run
- Remaining risks
