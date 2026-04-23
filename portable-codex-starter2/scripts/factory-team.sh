#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${FACTORY_TEAM_WORKDIR:-$(pwd)}"
cd "${WORK_DIR}"
ROOT_DIR="$(pwd -P)"
ROOT_NAME="$(basename "${ROOT_DIR}")"

TEAM_RUNTIME_ROOT="${FACTORY_TEAM_RUNTIME_ROOT:-${XDG_RUNTIME_DIR:-/tmp}/factory-team}"
RUN_DIR="${TEAM_RUNTIME_ROOT}/${ROOT_NAME}"
TEAM_SPEC_DEFAULT="${FACTORY_TEAM_SPEC:-4:executor}"
TEAM_SESSION_NAME="${FACTORY_TEAM_SESSION_NAME:-factory-team-${ROOT_NAME}}"
TEAM_NAME_HINT="${FACTORY_TEAM_NAME_HINT:-${TEAM_SESSION_NAME}}"
TEAM_TASK_FILE="${FACTORY_TEAM_TASK_FILE:-}"
TEAM_TASK="${FACTORY_TEAM_TASK:-}"
TEAM_ALLOW_DIRTY="${FACTORY_TEAM_ALLOW_DIRTY:-0}"
TEAM_FALLBACK="${FACTORY_TEAM_FALLBACK:-1}"
TEAM_DRY_RUN="${FACTORY_TEAM_DRY_RUN:-0}"
TEAM_AUTO_UPDATE="${FACTORY_TEAM_AUTO_UPDATE:-0}"
TEAM_FALLBACK_COMMAND="${FACTORY_TEAM_FALLBACK_COMMAND:-bash scripts/factory-night.sh}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_LOG="${RUN_DIR}/team-${TIMESTAMP}.log"
META_FILE="${RUN_DIR}/latest-run.json"
LAUNCH_SCRIPT="${RUN_DIR}/launch-${TEAM_SESSION_NAME}.sh"

mkdir -p "${RUN_DIR}"

if [[ -n "${TEAM_TASK_FILE}" && -z "${TEAM_TASK}" ]]; then
  if [[ ! -f "${TEAM_TASK_FILE}" ]]; then
    echo "[ERROR] FACTORY_TEAM_TASK_FILE does not exist: ${TEAM_TASK_FILE}" >&2
    exit 1
  fi
  TEAM_TASK="$(cat "${TEAM_TASK_FILE}")"
fi

if [[ "$#" -gt 0 ]]; then
  if [[ "${1:-}" == "--spec" ]]; then
    shift
    TEAM_SPEC_DEFAULT="${1:-${TEAM_SPEC_DEFAULT}}"
    shift || true
  elif [[ "${1:-}" == "--task-file" ]]; then
    shift
    TEAM_TASK_FILE="${1:-}"
    shift || true
    if [[ -n "${TEAM_TASK_FILE}" ]]; then
      if [[ ! -f "${TEAM_TASK_FILE}" ]]; then
        echo "[ERROR] --task-file path does not exist: ${TEAM_TASK_FILE}" >&2
        exit 1
      fi
      TEAM_TASK="$(cat "${TEAM_TASK_FILE}")"
    fi
  elif [[ "${1:-}" == "--fallback" ]]; then
    shift
    TEAM_FALLBACK_COMMAND="${1:-${TEAM_FALLBACK_COMMAND}}"
    shift || true
  fi
fi

if [[ -z "${TEAM_TASK}" && "$#" -gt 0 ]]; then
  TEAM_TASK="$*"
elif [[ -z "${TEAM_TASK}" && -t 0 ]]; then
  TEAM_TASK="${FACTORY_TEAM_DEFAULT_TASK:-parallel factory-night lane using omx team with dedicated worktrees}"
fi

if [[ -z "${TEAM_TASK}" ]]; then
  echo "[ERROR] missing team task. Set FACTORY_TEAM_TASK or pass a task string." >&2
  echo "[HINT] Example: FACTORY_TEAM_TASK='fix tests and stage review lane' bash scripts/factory-team.sh" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "[ERROR] factory-team requires a git repository." >&2
  exit 1
fi

working_tree_dirty=0
if [[ -n "$(git status --short 2>/dev/null)" ]]; then
  working_tree_dirty=1
fi

if [[ "${working_tree_dirty}" == "1" && "${TEAM_ALLOW_DIRTY}" != "1" ]]; then
  if [[ "${TEAM_FALLBACK}" == "1" ]]; then
    echo "[WARN] working tree is dirty; falling back to: ${TEAM_FALLBACK_COMMAND}" >&2
    node scripts/harness-event.mjs --event factory_team_fallback --details "dirty-working-tree -> ${TEAM_FALLBACK_COMMAND}" >/dev/null 2>&1 || true
    exec bash -lc "${TEAM_FALLBACK_COMMAND}"
  fi
  echo "[ERROR] working tree is dirty. Commit/stash first or set FACTORY_TEAM_ALLOW_DIRTY=1." >&2
  exit 1
fi

if ! command -v omx >/dev/null 2>&1; then
  if [[ "${TEAM_FALLBACK}" == "1" ]]; then
    echo "[WARN] omx not found; falling back to: ${TEAM_FALLBACK_COMMAND}" >&2
    node scripts/harness-event.mjs --event factory_team_fallback --details "missing-omx -> ${TEAM_FALLBACK_COMMAND}" >/dev/null 2>&1 || true
    exec bash -lc "${TEAM_FALLBACK_COMMAND}"
  fi
  echo "[ERROR] omx is not available on PATH." >&2
  exit 1
fi

if ! command -v script >/dev/null 2>&1; then
  echo "[ERROR] script command not found; cannot allocate a real TTY for omx team." >&2
  exit 1
fi

if ! command -v tmux >/dev/null 2>&1; then
  echo "[ERROR] tmux is required for factory-team orchestration." >&2
  exit 1
fi

TEAM_COMMAND_RENDERED="$(printf '%q ' omx team "${TEAM_SPEC_DEFAULT}" "${TEAM_TASK}")"
TEAM_COMMAND_RENDERED="${TEAM_COMMAND_RENDERED% }"
TEAM_TTY_COMMAND="env OMX_AUTO_UPDATE=$(printf '%q' "${TEAM_AUTO_UPDATE}") ${TEAM_COMMAND_RENDERED}"

if [[ "${TEAM_DRY_RUN}" == "1" ]]; then
  echo "[DRY-RUN] ${TEAM_TTY_COMMAND}"
  exit 0
fi

cat > "${LAUNCH_SCRIPT}" <<LAUNCH
#!/usr/bin/env bash
set -Eeuo pipefail
cd "${ROOT_DIR}"

update_meta() {
  local exit_code="\$1"
  local finished_at
  local final_status
  local final_phase
  local team_name=""
  finished_at="\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ -d "${ROOT_DIR}/.omx/state/team" ]]; then
    team_name="\$(find "${ROOT_DIR}/.omx/state/team" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1 | xargs -r basename 2>/dev/null || true)"
  fi
  if [[ -z "\${team_name}" && -s "${RUN_LOG}" ]]; then
    team_name="\$(grep -oE 'Team started: [a-z0-9-]+' "${RUN_LOG}" | tail -n 1 | awk '{print \$3}' || true)"
  fi
  if [[ "\${exit_code}" == "0" ]]; then
    final_status="running"
    final_phase="team_launched"
  else
    final_status="failed"
    final_phase="team_launch_failed"
  fi
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const status = process.argv[2];
    const phase = process.argv[3];
    const finishedAt = process.argv[4];
    const exitCode = Number(process.argv[5]);
    const teamName = process.argv[6];
    try {
      const payload = JSON.parse(fs.readFileSync(path, "utf8"));
      payload.status = status;
      payload.phase = phase;
      payload.finished_at = finishedAt;
      payload.exit_code = exitCode;
      if (teamName) {
        payload.team_name = teamName;
      }
      fs.writeFileSync(path, JSON.stringify(payload, null, 2) + "\n", "utf8");
    } catch {
      process.stderr.write("[WARN] failed to update team metadata\n");
    }
  ' "${META_FILE}" "\${final_status}" "\${final_phase}" "\${finished_at}" "\${exit_code}" "\${team_name}"
}

trap 'rc=\$?; update_meta "\$rc"' EXIT

echo "[INFO] factory-team start \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${RUN_LOG}"
script -q -f -a -e -c "${TEAM_TTY_COMMAND}" "${RUN_LOG}"
LAUNCH
chmod +x "${LAUNCH_SCRIPT}"

tmux new-session -d -s "${TEAM_SESSION_NAME}" "bash '${LAUNCH_SCRIPT}'"

cat > "${META_FILE}" <<JSON
{
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo_path": "${ROOT_DIR}",
  "branch": "$(git branch --show-current 2>/dev/null || echo unknown)",
  "session_name": "${TEAM_SESSION_NAME}",
  "team_name_hint": "${TEAM_NAME_HINT}",
  "status": "running",
  "phase": "launched",
  "finished_at": null,
  "execution_mode": "omx-team",
  "team_spec": "${TEAM_SPEC_DEFAULT}",
  "team_task": $(printf '%s' "${TEAM_TASK}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "team_fallback_command": "${TEAM_FALLBACK_COMMAND}",
  "team_allow_dirty": "${TEAM_ALLOW_DIRTY}",
  "team_dry_run": "${TEAM_DRY_RUN}",
  "run_log": "${RUN_LOG}",
  "runtime_root": "${TEAM_RUNTIME_ROOT}",
  "team_name": null,
  "last_update_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_event": "factory_team_started",
  "last_event_details": "${TEAM_SESSION_NAME}"
}
JSON

if [[ "${TEAM_DRY_RUN}" == "1" ]]; then
  echo "[DRY-RUN] ${TEAM_TTY_COMMAND}"
  exit 0
fi

node scripts/harness-event.mjs --event factory_team_started --details "${TEAM_SESSION_NAME}" >/dev/null 2>&1 || true
team_name="$(node -e 'const fs=require("fs"); try { const p=JSON.parse(fs.readFileSync(process.argv[1], "utf8")); process.stdout.write(p.team_name || ""); } catch {}' "${META_FILE}")"

echo "[INFO] factory-team session started: ${TEAM_SESSION_NAME}"
echo "[INFO] team spec: ${TEAM_SPEC_DEFAULT}"
echo "[INFO] team task: ${TEAM_TASK}"
if [[ -n "${team_name}" ]]; then
  echo "[INFO] team name: ${team_name}"
fi
echo "[INFO] run log: ${RUN_LOG}"
