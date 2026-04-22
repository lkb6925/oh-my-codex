---
name: tdd
description: Enforce a test-first implementation loop
---

# TDD

Use this skill when the user wants test-first delivery or when behavior must be locked before coding.

## Workflow

1. Write or identify the next failing test.
2. Run it and confirm it fails for the right reason.
3. Implement the smallest change that makes it pass.
4. Run the relevant tests again.
5. Refactor only after the test is green.
6. Repeat.

## Rules

- No production code before a failing test for the new behavior.
- Keep each cycle narrow.
- If a test passes on the first run, the test is probably not proving the behavior you think it is.

## Output

- Red phase
- Green phase
- Refactor phase
- Test evidence
