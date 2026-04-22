---
name: doctor
description: Validate that the portable starter is installed in the current repository
---

# Doctor

Use this skill to check whether the current repository has the expected portable Codex starter files.

## Checks

- `AGENTS.md` exists at repository root
- `.codex/agents/` exists and contains custom agent TOMLs
- `.agents/skills/` or `.codex/skills/` exists when skills are expected
- optional `.codex/config.toml` or `.codex/config.toml.example` exists

## Output

- present files
- missing files
- recommended next step to complete installation
