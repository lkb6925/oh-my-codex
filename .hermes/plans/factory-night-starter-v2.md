# Factory-Night Starter v2 Implementation Plan

> For Hermes: execute this plan with subagent-driven-development. Keep root scripts and `portable-codex-starter2/` mirrored unless a deliberate divergence is documented.

**Goal:** Upgrade the starter into a factory-night-first harness that supports parallel worktrees, event-driven hooks, structured run state, API-first senior review, and clear `watch` / `summary` / `finish` lifecycle commands.

**Architecture:**
This starter should remain an overlay harness, not a runtime replacement. Keep the runtime light, preserve VM-local state, and make every night-session artifact machine-readable. The end state is: one command to launch, one command to watch, one command to summarize, one command to finish, with reviewer and env handling stable enough for unattended overnight work.

**Tech Stack:**
Bash, Node.js ESM scripts, tmux, git, jq, existing OMX/Hermes/Codex scripts, optional filesystem hooks/plugins.

---

## Non-goals

- Do not replace OMX, Hermes, or Codex runtime internals.
- Do not add remote/cloud automation unless the starter already uses it.
- Do not require new always-on daemons.
- Do not introduce CLI-only reviewer dependencies.

---

## Task 1: Define the factory-night lifecycle contract

**Objective:** Make the lifecycle boundaries explicit so the harness has one clear model for run, watch, summary, and finish.

**Files:**
- Modify: `portable-codex-starter2/README.md`
- Modify: `portable-codex-starter2/docs/automation-playbook.md`
- Modify: `portable-codex-starter2/AGENTS.md`
- Mirror any user-facing wording into the root overlay if needed

**Changes:**
- Document the meaning of:
  - `factory:night` = launch and run
  - `factory:watch` = continuous monitoring
  - `factory:summary` = status briefing
  - `factory:finish` = finalization / push / shutdown
- Add a short “when to use which command” section.
- Clarify that `factory-night` is for autonomous execution, while the other commands are read-only or finishing operations.
- State explicitly that overnight runs should not emit conversational turn-end replies while work is still in progress; they should keep acting until complete or genuinely blocked.

**Verification:**
- Read the docs and ensure the lifecycle is explainable in under 1 minute.
- Confirm the four command names are consistently described.

---

## Task 2: Add structured run-state and checkpoint manifest support

**Objective:** Replace ad hoc logs with a consistent run-state manifest so watch/summary/finish can reason about the run mechanically.

**Files:**
- Modify: `portable-codex-starter2/scripts/factory-night.sh`
- Modify: `portable-codex-starter2/scripts/factory-status.sh`
- Modify: `portable-codex-starter2/scripts/factory-watch.sh`
- Modify: `portable-codex-starter2/scripts/factory-summary.sh`
- Modify: `portable-codex-starter2/scripts/factory-finish.sh`
- Modify: `portable-codex-starter2/scripts/run-local-checks.sh`
- Add or modify: `.omx/runs/latest-run.json` schema generation logic

**Changes:**
- Ensure every run writes a machine-readable manifest with at least:
  - `status`
  - `phase`
  - `repo_path`
  - `branch`
  - `session_name`
  - `started_at`
  - `last_update_at`
  - `latest_checks`
  - `latest_review`
  - `push_state`
  - `poweroff_ready`
- Make watch/summary/finish read the same manifest instead of inferring too much from logs alone.
- Keep durable checkpoints under `.omx/checkpoints/` and runtime state under `.omx/runs/`.

**Verification:**
- Start a run and confirm the manifest is created.
- Run `factory:watch --once` and `factory:summary` and confirm both read the same state.
- Confirm no runtime logs are copied into install artifacts.

---

## Task 3: Add event-driven hooks for turn-complete and blocker tracking

**Objective:** Make the harness reactive so it records progress and blockers automatically instead of relying only on manual checks.

**Files:**
- Modify or add: `portable-codex-starter2/.omx/hooks/*`
- Modify: `portable-codex-starter2/scripts/install.mjs`
- Modify: `portable-codex-starter2/scripts/factory-night.sh`
- Modify: `portable-codex-starter2/scripts/factory-watch.sh`
- Modify: `portable-codex-starter2/scripts/factory-summary.sh`

**Changes:**
- Add a hook/plugin layer that can record:
  - turn completion
  - review completion
  - blocker / failure events
  - alert snapshots
- Keep hooks lightweight and local.
- Make hook output feed `.omx/runs/latest-run.json` and alert snapshots.

**Verification:**
- Trigger a sample event and confirm an alert or progress record is written.
- Confirm hooks do not break install portability.

---

## Task 4: Standardize agent roles and parallel worktree behavior

**Objective:** Make role separation explicit and support parallel worker patterns as a first-class workflow.

**Files:**
- Modify: `portable-codex-starter2/.codex/agents/*.toml`
- Modify: `portable-codex-starter2/README.md`
- Modify: `portable-codex-starter2/AGENTS.md`
- Modify: `portable-codex-starter2/scripts/factory-night.sh`
- Add: `portable-codex-starter2/docs/agent-contracts.md` if needed

**Changes:**
- Make planner / architect / executor / debugger role contracts explicit.
- Add guidance for when to use parallel workers and when not to.
- Document a worktree-friendly pattern for independent tasks.
- Make the run scripts prefer parallelization where files do not overlap.

**Verification:**
- Check that each role has a clear responsibility statement.
- Confirm the docs mention parallel workers as the default for independent tasks.

---

## Task 5: Improve code-intel and status summaries

**Objective:** Give Hermes better visibility into the repo state, recent changes, and risky areas.

**Files:**
- Modify: `portable-codex-starter2/scripts/factory-status.sh`
- Modify: `portable-codex-starter2/scripts/factory-summary.sh`
- Modify: `portable-codex-starter2/scripts/factory-watch.sh`
- Modify: `portable-codex-starter2/scripts/factory-finish.sh`
- Optionally add: `portable-codex-starter2/scripts/code-intel.sh`

**Changes:**
- Include in status/summary:
  - dirty files count
  - latest check verdicts
  - latest review verdict
  - branch/commit
  - push state
  - session health
  - stale log warnings
- If useful, generate a compact “what changed since last summary” block.
- Keep output readable in terminal and easy to paste into handoff notes.

**Verification:**
- Compare `factory:status` and `factory:summary` output before/after.
- Confirm summaries are still short enough for factory-night use.

---

## Task 6: Make senior review explicitly API-first and stable

**Objective:** Preserve the reviewer path as the single stable API-based route while accepting VM env aliases cleanly.

**Files:**
- Modify: `portable-codex-starter2/scripts/gemini-reviewer.mjs`
- Modify: `portable-codex-starter2/scripts/get-senior-review.sh`
- Modify: `portable-codex-starter2/scripts/lib/load-env.sh`
- Modify: `portable-codex-starter2/scripts/vm-ready-check.sh`
- Modify: `portable-codex-starter2/docs/mcp-setup.md`
- Modify: `portable-codex-starter2/README.md`
- Mirror the same changes in root overlay files

**Changes:**
- Keep reviewer backend defaulted to `api` only.
- Accept `GEMINI_API_KEY`, `GOOGLE_API_KEY`, and `AI_API_KEY` as aliases for the same reviewer credential.
- Ensure VM env loading reads the reviewer key from `~/.hermes/.env` or shell environment.
- Keep the reviewer path free of CLI/OAuth dependencies.

**Verification:**
- `bash scripts/vm-ready-check.sh`
- `bash scripts/get-senior-review.sh 1`
- Confirm the reviewer path is API-first and the docs say so.

---

## Task 7: Tighten finish semantics and safe shutdown behavior

**Objective:** Make `finish` produce a trustworthy terminal state and optionally stop tmux cleanly.

**Files:**
- Modify: `portable-codex-starter2/scripts/factory-finish.sh`
- Modify: `portable-codex-starter2/scripts/factory-status.sh`
- Modify: `portable-codex-starter2/scripts/factory-summary.sh`
- Modify: `portable-codex-starter2/docs/automation-playbook.md`

**Changes:**
- Make `finish` write a final summary and a finish-state JSON.
- Preserve clear state for:
  - pushed / not pushed
  - poweroff ready / stalled
  - remaining manual actions
- If session shutdown is enabled, kill only the named factory session.

**Verification:**
- Run `factory:finish` in a safe test session.
- Confirm the finish-state file is written and the summary is coherent.

---

## Task 8: Add compatibility/version checks and a regression test path

**Objective:** Prevent silent drift between starter version, VM runtime, and generated overlays.

**Files:**
- Modify: `portable-codex-starter2/scripts/doctor.mjs`
- Modify: `portable-codex-starter2/scripts/install.mjs`
- Modify: `portable-codex-starter2/package.json`
- Modify: `portable-codex-starter2/docs/source-map.md`
- Modify: `portable-codex-starter2/README.md`

**Changes:**
- Add or refine a version/compatibility note.
- Ensure install checks the expected overlay shape.
- Add one stable regression command for the starter harness path.
- Keep docs aligned with the actual commands users will run.

**Verification:**
- `node scripts/doctor.mjs --target /path/to/install`
- `node scripts/install.mjs --target /tmp/starter-test --with-config --core-only`
- Run the updated watch/summary/finish commands against a test install.

---

## Suggested implementation order

1. Lifecycle contract docs
2. Structured run state
3. Hooks / event recording
4. Agent role contracts + worktrees
5. Status / code-intel summaries
6. API-first reviewer stability
7. Finish semantics
8. Compatibility and regression checks

---

## Acceptance criteria

- `factory:night`, `factory:watch`, `factory:summary`, and `factory:finish` are clearly documented and operational.
- The starter keeps VM runtime state local and durable state structured.
- Reviewer uses API-first path and reads VM keys cleanly.
- Parallel worktree behavior and role separation are explicit.
- `watch` catches stalls, `summary` explains state, `finish` closes the loop.
- Root overlay and `portable-codex-starter2/` remain in sync.

---

## Handoff note for execution

When this plan is approved, execute it with subagent-driven-development:
- fresh subagent per task
- spec compliance review first
- code quality review second
- do not move on while review gates are open
