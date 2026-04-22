---
name: build-fix
description: Fix build, typecheck, and compilation failures with minimal changes
---

# Build Fix

Use this skill when the build, typecheck, or compiler is failing and the goal is to get it green with minimal edits.

## Workflow

1. Run the relevant build or typecheck command.
2. Collect the concrete failures.
3. Fix the smallest set of issues required to clear them.
4. Re-run the failing command after each meaningful change.
5. Stop once the build passes.

## Guardrails

- No unrelated refactors.
- No architecture changes unless absolutely required.
- Prefer one fix at a time.
- Report any pre-existing failures that were not introduced by your work.

## Output

- Errors fixed
- Files changed
- Final build status
- Remaining risks
