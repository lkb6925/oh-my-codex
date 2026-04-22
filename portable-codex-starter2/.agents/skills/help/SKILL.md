---
name: help
description: Explain how this portable starter is meant to be used
---

# Portable Starter Help

Use this starter as a repository-local Codex operating pack.

## What it provides

- `AGENTS.md` for top-level behavior
- custom agents under `.codex/agents/`
- portable skills under `.agents/skills/`
- prompt sources under `prompts/`

## What it does not provide

- no launcher
- no tmux team runtime
- no HUD
- no `.omx/` state machine

## Recommended usage

1. Start with direct execution when the task is clear.
2. Use `deep-interview` if the task is vague.
3. Use `plan` when the user wants a reviewed implementation plan first.
4. Use custom agents for specialist passes.
5. Use `code-review`, `security-review`, `tdd`, or `ai-slop-cleaner` when those workflows fit.

## Maintenance

If you edit prompt sources, regenerate custom agents:

```bash
npm run generate:agents
```
