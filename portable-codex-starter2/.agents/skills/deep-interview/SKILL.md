---
name: deep-interview
description: Clarify vague requests through a one-question-at-a-time interview
---

# Deep Interview

Use this skill when the request is broad, ambiguous, or likely to cause rework if executed immediately.

## Workflow

1. Identify the weakest missing dimension:
   - intent
   - desired outcome
   - scope
   - non-goals
   - success criteria
2. Ask one focused question.
3. Use the answer to tighten the next question.
4. Keep pushing until the task has clear boundaries and a definition of done.
5. End by summarizing the clarified spec before handing off to `plan`, `architect`, or `executor`.

## Rules

- Ask one question at a time.
- Prefer intent and boundaries before implementation detail.
- Revisit an earlier answer if it still hides assumptions.
- Do not keep interviewing once the task is execution-ready.

## Exit criteria

The task is interview-complete when:
- the user outcome is explicit
- scope and non-goals are explicit
- success criteria are concrete
- the next implementation step is obvious
