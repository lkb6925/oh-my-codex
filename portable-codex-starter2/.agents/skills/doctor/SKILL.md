---
name: doctor
description: Validate that the portable starter is installed in the current repository
---

# Doctor

Use this skill to check whether the current repository has the expected portable Codex starter files.

## Checks

- `AGENTS.md` exists at repository root
- overlay runtime files exist (`factory`, `factory-night`, scripts, AGENTS)
- existing OMX/Codex agents and skills are preserved unless opt-in starter copies are requested
- optional `.codex/config.toml` or `.codex/config.toml.example` exists

## Output

- present files
- missing files
- recommended next step to complete installation
