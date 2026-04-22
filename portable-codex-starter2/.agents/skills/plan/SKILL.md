---
name: plan
description: Produce an actionable implementation plan before coding
---

# Plan

Use this skill when the user wants a concrete work plan before implementation.

## Workflow

1. Inspect the relevant repository context before asking questions.
2. If the request is vague, ask one focused clarifying question at a time.
3. Break the work into explicit, testable steps.
4. Call out risks, tradeoffs, and verification requirements.
5. If the task is high-risk, pressure-test the plan with `architect` or `critic` before finalizing it.

## Plan contents

- Requirements summary
- Non-goals
- Acceptance criteria
- Implementation steps
- Risks and mitigations
- Verification steps

## Guardrails

- Do not write code while in planning mode unless the user changes direction.
- Do not ask the user for codebase facts you can inspect directly.
- Keep the plan right-sized to the task.
