---
name: git-master
description: Provide git-focused guidance for clean commits and history hygiene
---

# Git Master

Use this skill when the task is about commit shape, branch hygiene, rebasing, or preparing changes for review.

## Workflow

1. Inspect repository status and current diff.
2. Group changes into logical commit units.
3. Call out risky history operations before performing them.
4. Prefer non-interactive, reproducible git commands.
5. Keep unrelated changes out of the final history.

## Guardrails

- Do not rewrite history unless the user clearly wants that.
- Do not discard user changes.
- Prefer intentional commit boundaries over one giant commit.
