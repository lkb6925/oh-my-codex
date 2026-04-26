#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
ROOT_NAME="$(basename "${ROOT_DIR}")"

SESSION_NAME="${FACTORY_SESSION_NAME:-factory-night-${ROOT_NAME}}"
RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
OMX_COMMAND="${OMX_COMMAND:-omx}"
OMX_BIN="${OMX_BIN:-omx}"
OMX_ARGS="${OMX_ARGS:-}"
FACTORY_REQUIRE_STRUCTURED_INPUT="${FACTORY_REQUIRE_STRUCTURED_INPUT:-0}"
FACTORY_COMMAND_POLICY="${FACTORY_COMMAND_POLICY:-strict}"
FACTORY_ALLOW_NON_OMX_COMMAND="${FACTORY_ALLOW_NON_OMX_COMMAND:-0}"
FACTORY_OMX_DEFAULT_FLAGS="${FACTORY_OMX_DEFAULT_FLAGS:---tmux --madmax --high}"
FACTORY_OMX_BLOCKLIST_REGEX="${FACTORY_OMX_BLOCKLIST_REGEX:-(^|[[:space:]])(--unsafe|--danger|--destructive|--no-sandbox)([[:space:]]|$)}"
FACTORY_OMX_AUTO_UPDATE="${FACTORY_OMX_AUTO_UPDATE:-0}"
# Default is omx team. FACTORY_NIGHT_EXEC_MODE=exec is an explicit
# alternate omx exec path; override FACTORY_NIGHT_EXEC_COMMAND only when needed.
FACTORY_NIGHT_EXEC_MODE="${FACTORY_NIGHT_EXEC_MODE:-team}"
FACTORY_NIGHT_TEAM_SPEC="${FACTORY_NIGHT_TEAM_SPEC:-${FACTORY_TEAM_SPEC:-4:executor}}"
FACTORY_NIGHT_TASK_FILE="${FACTORY_NIGHT_TASK_FILE:-}"
FACTORY_NIGHT_TASK="${FACTORY_NIGHT_TASK:-}"
FACTORY_NIGHT_DEFAULT_TASK="${FACTORY_NIGHT_DEFAULT_TASK:-Continue the repository from the current state using the project files, logs, and internet clues available to you. Work autonomously, do not ask the user questions unless truly blocked, write tests and checkpoints as needed, and only report when you have a complete result or a real blocker.}"
# Use the non-bwrap exec sandbox by default for factory exec mode; prior
# codex exec sessions in this environment failed before user code with:
# "bwrap: loopback: Failed RTM_NEWADDR: Operation not permitted".
FACTORY_NIGHT_EXEC_COMMAND="${FACTORY_NIGHT_EXEC_COMMAND:-omx exec --dangerously-bypass-approvals-and-sandbox --json}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_LOG="${RUN_DIR}/run-${TIMESTAMP}.log"
META_FILE="${RUN_DIR}/latest-run.json"
EVENT_LOG="${RUN_DIR}/factory-night-events.log"

mkdir -p "${RUN_DIR}"
find "${RUN_DIR}" -type f \( -name 'run-*.log' -o -name 'watch-*.log' -o -name 'launch-*.sh' \) -mtime +7 -delete 2>/dev/null || true

NIGHT_TASK=""
NIGHT_TASK_SOURCE="default"
if [[ -n "${FACTORY_NIGHT_TASK_FILE}" ]]; then
  if [[ ! -f "${FACTORY_NIGHT_TASK_FILE}" ]]; then
    echo "[ERROR] FACTORY_NIGHT_TASK_FILE does not exist: ${FACTORY_NIGHT_TASK_FILE}" >&2
    exit 1
  fi
  NIGHT_TASK="$(cat "${FACTORY_NIGHT_TASK_FILE}")"
  NIGHT_TASK_SOURCE="file"
elif [[ -n "${FACTORY_NIGHT_TASK}" ]]; then
  NIGHT_TASK="${FACTORY_NIGHT_TASK}"
  NIGHT_TASK_SOURCE="env"
elif [[ "$#" -gt 0 ]]; then
  NIGHT_TASK="$*"
  NIGHT_TASK_SOURCE="args"
else
  NIGHT_TASK="${FACTORY_NIGHT_DEFAULT_TASK}"
  NIGHT_TASK_SOURCE="default"
fi

if [[ "${FACTORY_NIGHT_EXEC_MODE}" != "exec" && "${FACTORY_NIGHT_EXEC_MODE}" != "interactive" && "${FACTORY_NIGHT_EXEC_MODE}" != "team" ]]; then
  echo "[ERROR] FACTORY_NIGHT_EXEC_MODE must be 'team', 'exec', or 'interactive'." >&2
  exit 1
fi

if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "exec" && -z "${NIGHT_TASK}" ]]; then
  echo "[ERROR] factory-night exec mode requires a task. Set FACTORY_NIGHT_TASK, FACTORY_NIGHT_TASK_FILE, or pass a prompt as arguments." >&2
  exit 1
fi

if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "team" && -z "${NIGHT_TASK}" ]]; then
  echo "[ERROR] factory-night team mode requires a task. Set FACTORY_NIGHT_TASK, FACTORY_NIGHT_TASK_FILE, or pass a prompt as arguments." >&2
  exit 1
fi

NIGHT_TASK_FILE="${RUN_DIR}/night-task-${TIMESTAMP}.txt"
printf '%s' "${NIGHT_TASK}" > "${NIGHT_TASK_FILE}"
NIGHT_PROMPT_FILE="${RUN_DIR}/night-task-${TIMESTAMP}.md"
NIGHT_LAST_MESSAGE_FILE="${RUN_DIR}/night-last-message-${TIMESTAMP}.md"
NIGHT_TEAM_HELPER_SCRIPT="${RUN_DIR}/night-team-launch-${TIMESTAMP}.sh"
if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "exec" ]]; then
  NIGHT_TASK="${NIGHT_TASK}" NIGHT_PROMPT_FILE="${NIGHT_PROMPT_FILE}" python3 - <<'PY'
from pathlib import Path
import os
prompt = f"""You are operating in factory-night silent job mode.

User task:
{os.environ['NIGHT_TASK']}

Operating rules:
- Use the repository, logs, tests, available tools, and internet clues to work autonomously.
- Do not ask the user questions unless a true blocker prevents progress.
- Keep acting until the task is completed or a hard blocker is reached.
- Write durable artifacts and checkpoints as you go.
- Return only a concise completion report at the end.
"""
Path(os.environ['NIGHT_PROMPT_FILE']).write_text(prompt, encoding='utf-8')
PY
fi

if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "team" ]]; then
  cat > "${NIGHT_TEAM_HELPER_SCRIPT}" <<EOF
#!/usr/bin/env bash
set -Eeuo pipefail
TASK_FILE="\${1:?task file required}"
TEAM_SPEC="\${2:?team spec required}"
REPO_ROOT="\$(git rev-parse --show-toplevel)"
WORKTREE_ROOT="\${FACTORY_NIGHT_TEAM_WORKTREE_ROOT:-${RUN_DIR}/team-worktrees}"
mkdir -p "\${WORKTREE_ROOT}"
WORKTREE_DIR="\$(mktemp -d "\${WORKTREE_ROOT}/leader-XXXXXX")"
cleanup() {
  git -C "\${REPO_ROOT}" worktree remove --force "\${WORKTREE_DIR}" >/dev/null 2>&1 || rm -rf "\${WORKTREE_DIR}"
}
trap cleanup EXIT
mkdir -p "\${WORKTREE_ROOT}"
git -C "\${REPO_ROOT}" worktree add --detach "\${WORKTREE_DIR}" HEAD >/dev/null
cd "\${WORKTREE_DIR}"
TASK="\$(cat "\${TASK_FILE}")"
unset TMUX TMUX_PANE
exec omx team "\${TEAM_SPEC}" "\${TASK}"
EOF
  chmod +x "${NIGHT_TEAM_HELPER_SCRIPT}"
  FACTORY_COMMAND_POLICY="permissive"
  OMX_COMMAND="bash ${NIGHT_TEAM_HELPER_SCRIPT} ${NIGHT_TASK_FILE} ${FACTORY_NIGHT_TEAM_SPEC}"
  OMX_ARGS=""
  OMX_INPUT_MODE="factory_night_team"
fi

if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "exec" ]]; then
  FACTORY_COMMAND_POLICY="strict"
  OMX_COMMAND="${FACTORY_NIGHT_EXEC_COMMAND} --output-last-message ${NIGHT_LAST_MESSAGE_FILE}"
  OMX_ARGS=""
  OMX_INPUT_MODE="factory_night_exec"
fi

if [[ "${OMX_COMMAND}" =~ [\;\&\|\<\>\`\$\\\(\)\{\}] ]]; then
  echo "[ERROR] OMX_COMMAND contains unsafe shell metacharacters. Use plain argv style command tokens only." >&2
  exit 1
fi

declare -a OMX_TOKENS=***
OMX_INPUT_MODE="${OMX_INPUT_MODE:-omx_command}"

if [[ -n "${OMX_ARGS}" ]]; then
  if [[ "${OMX_BIN}" =~ [\;\&\|\<\>\`\$\\\(\)\{\}] ]]; then
    echo "[ERROR] OMX_BIN contains unsafe shell metacharacters." >&2
    exit 1
  fi
  if [[ "${OMX_ARGS}" =~ [\;\&\|\<\>\`\$\\\(\)\{\}] ]]; then
    echo "[ERROR] OMX_ARGS contains unsafe shell metacharacters. Use plain argv style tokens only." >&2
    exit 1
  fi
  if [[ "${OMX_COMMAND}" != "omx" ]]; then
    echo "[WARN] OMX_ARGS is set, so OMX_COMMAND is ignored. (input preference: OMX_ARGS + OMX_BIN)"
  fi
  declare -a OMX_ARG_TOKENS=()
  read -r -a OMX_ARG_TOKENS <<< "${OMX_ARGS}"
  OMX_TOKENS=("${OMX_BIN}" "${OMX_ARG_TOKENS[@]}")
  OMX_INPUT_MODE="omx_args"
else
  echo "[WARN] OMX_COMMAND is deprecated. Prefer OMX_BIN + OMX_ARGS for structured launch input."
  if [[ "${FACTORY_REQUIRE_STRUCTURED_INPUT}" == "1" ]]; then
    echo "[ERROR] FACTORY_REQUIRE_STRUCTURED_INPUT=1 requires OMX_ARGS to be set; OMX_COMMAND path is disabled." >&2
    exit 1
  fi
  read -r -a OMX_TOKENS <<< "${OMX_COMMAND}"
fi

if [[ "${#OMX_TOKENS[@]}" -eq 0 ]]; then
  echo "[ERROR] OMX command input produced an empty token list." >&2
  exit 1
fi

if [[ "${FACTORY_COMMAND_POLICY}" != "strict" && "${FACTORY_COMMAND_POLICY}" != "permissive" ]]; then
  echo "[ERROR] FACTORY_COMMAND_POLICY must be 'strict' or 'permissive'." >&2
  exit 1
fi

if [[ "${FACTORY_COMMAND_POLICY}" == "strict" && "${FACTORY_ALLOW_NON_OMX_COMMAND}" != "1" ]]; then
  if [[ "$(basename "${OMX_TOKENS[0]}")" != "omx" ]]; then
    echo "[ERROR] strict policy requires OMX_COMMAND to start with 'omx'."
    echo "[HINT] Set FACTORY_ALLOW_NON_OMX_COMMAND=1 to bypass this guard intentionally." >&2
    exit 1
  fi
fi

if [[ "$(basename "${OMX_TOKENS[0]}")" == "omx" ]]; then
  if ! command -v "${OMX_TOKENS[0]}" >/dev/null 2>&1; then
    echo "[ERROR] OMX binary not found on PATH: ${OMX_TOKENS[0]}" >&2
    exit 1
  fi

  if [[ "${FACTORY_COMMAND_POLICY}" == "strict" ]]; then
    if [[ "${#OMX_TOKENS[@]}" -eq 1 ]]; then
      declare -a DEFAULT_FLAGS=()
      read -r -a DEFAULT_FLAGS <<< "${FACTORY_OMX_DEFAULT_FLAGS}"
      OMX_TOKENS=("${OMX_TOKENS[0]}" "${DEFAULT_FLAGS[@]}")
      echo "[INFO] strict policy expanded bare 'omx' to conservative flags: ${FACTORY_OMX_DEFAULT_FLAGS}"
    fi

    if [[ "${OMX_TOKENS[1]:-}" != "exec" && "${OMX_TOKENS[1]:-}" != "team" ]]; then
      if [[ " ${OMX_TOKENS[*]} " =~ [[:space:]]--no-tmux[[:space:]] ]]; then
        echo "[ERROR] strict policy forbids '--no-tmux' for overnight durability." >&2
        exit 1
      fi

      if ! [[ " ${OMX_TOKENS[*]} " =~ [[:space:]]--tmux[[:space:]] ]]; then
        OMX_TOKENS+=("--tmux")
        echo "[INFO] strict policy appended '--tmux'."
      fi
    fi

    if [[ " ${OMX_TOKENS[*]} " =~ ${FACTORY_OMX_BLOCKLIST_REGEX} ]]; then
      echo "[ERROR] OMX_COMMAND matched blocked risky flag pattern under strict policy." >&2
      exit 1
    fi
  fi
fi

OMX_COMMAND_RENDERED="$(printf '%q ' "${OMX_TOKENS[@]}")"
OMX_COMMAND_RENDERED="${OMX_COMMAND_RENDERED% }"

bash scripts/vm-ready-check.sh

if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  echo "[INFO] tmux session already exists: ${SESSION_NAME}"
  echo "[INFO] Existing session retained (idempotent)."
  echo "[INFO] $(date -u +%Y-%m-%dT%H:%M:%SZ) session exists=${SESSION_NAME}; skipped new launch." >> "${EVENT_LOG}"
  exit 0
fi

LAUNCH_SCRIPT="${RUN_DIR}/launch-${SESSION_NAME}.sh"
if ! command -v script >/dev/null 2>&1; then
  echo "[ERROR] script command not found; cannot allocate a real TTY for omx." >&2
  exit 1
fi

OMX_AUTO_UPDATE_RENDERED="$(printf '%q' "${FACTORY_OMX_AUTO_UPDATE}")"
TTY_COMMAND="env OMX_AUTO_UPDATE=${OMX_AUTO_UPDATE_RENDERED} ${OMX_COMMAND_RENDERED}"
if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "exec" ]]; then
  TTY_COMMAND="${TTY_COMMAND} - < \"${NIGHT_PROMPT_FILE}\""
fi
cat > "${LAUNCH_SCRIPT}" <<LAUNCH
#!/usr/bin/env bash
set -Eeuo pipefail
cd "${ROOT_DIR}"

update_meta() {
  local exit_code="\$1"
  local final_phase="\${2:-launch_complete}"
  local agent_alive="\${3:-false}"
  local finished_at
  local final_status
  finished_at="\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "\${exit_code}" == "0" ]]; then
    final_status="completed"
  else
    final_status="failed"
  fi
  local tmp_meta
  tmp_meta="$(mktemp "${META_FILE}.XXXXXX")"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const outputPath = process.argv[2];
    const status = process.argv[3];
    const phase = process.argv[4];
    const finishedAt = process.argv[5];
    const exitCode = Number(process.argv[6]);
    const agentAlive = process.argv[7] === "true";
    try {
      const payload = JSON.parse(fs.readFileSync(path, "utf8"));
      payload.status = status;
      payload.phase = phase;
      payload.finished_at = finishedAt;
      payload.exit_code = exitCode;
      payload.agent_alive = agentAlive;
      payload.last_update_at = finishedAt;
      payload.last_event = status === "completed" ? "factory_completed" : "factory_failed";
      payload.last_event_details = phase + ":" + exitCode;
      fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
    } catch {
      process.stderr.write("[WARN] failed to update launch metadata\n");
    }
  ' "${META_FILE}" "\${tmp_meta}" "\${final_status}" "\${final_phase}" "\${finished_at}" "\${exit_code}" "\${agent_alive}" && mv -f "\${tmp_meta}" "${META_FILE}"
}

META_FINALIZED=0
trap 'rc=\$?; if [[ "\${META_FINALIZED}" != "1" ]]; then update_meta "\$rc" "launch_complete" "false"; fi' EXIT

echo "[INFO] factory-night start \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${RUN_LOG}"
if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "exec" ]]; then
  echo "[INFO] factory-night exec prompt file: ${NIGHT_PROMPT_FILE}" >> "${RUN_LOG}"
fi
script -q -f -a -e -c "${TTY_COMMAND}" "${RUN_LOG}"
EXEC_RC="\$?"
if [[ "${FACTORY_NIGHT_EXEC_MODE}" == "exec" ]]; then
  META_FINALIZED=1
  update_meta "\${EXEC_RC}" "night_job_complete" "false"
  echo "[INFO] factory-night exec run finished rc=\${EXEC_RC} prompt=${NIGHT_PROMPT_FILE} last_message=${NIGHT_LAST_MESSAGE_FILE}" >> "${EVENT_LOG}"
elif [[ "${FACTORY_NIGHT_EXEC_MODE}" == "team" ]]; then
  META_FINALIZED=1
  update_meta "\${EXEC_RC}" "night_team_complete" "false"
  echo "[INFO] factory-night team run finished rc=\${EXEC_RC} team_spec=${FACTORY_NIGHT_TEAM_SPEC} helper=${NIGHT_TEAM_HELPER_SCRIPT}" >> "${EVENT_LOG}"
fi
LAUNCH

chmod +x "${LAUNCH_SCRIPT}"

tmux new-session -d -s "${SESSION_NAME}" "bash '${LAUNCH_SCRIPT}'"

if [[ "${FACTORY_TMUX_SPLIT_PANE:-0}" == "1" ]]; then
  HUMAN_PANE_SCRIPT="cd $(printf '%q' "${ROOT_DIR}") && echo && echo '[factory-night] Human shell pane ready. Type here, not in the OMX pane.' && echo && exec bash --noprofile --norc"
  if tmux split-window -t "${SESSION_NAME}:0" -h -c "${ROOT_DIR}" bash -lc "${HUMAN_PANE_SCRIPT}"; then
    tmux select-pane -t "${SESSION_NAME}:0.0" -T "${FACTORY_AGENT_PANE_TITLE:-omx-agent}" 2>/dev/null || true
    tmux select-pane -t "${SESSION_NAME}:0.1" -T "${FACTORY_HUMAN_PANE_TITLE:-human-shell}" 2>/dev/null || true
    tmux select-pane -t "${SESSION_NAME}:0.1"
  else
    echo "[WARN] failed to create a dedicated human shell pane; continuing with single-pane mode." >&2
  fi
fi

tmp_meta="$(mktemp "${META_FILE}.XXXXXX")"
cat > "${tmp_meta}" <<JSON
{
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo_path": "${ROOT_DIR}",
  "branch": "$(git branch --show-current 2>/dev/null || echo unknown)",
  "start_commit": "$(git rev-parse HEAD 2>/dev/null || echo unknown)",
  "status": "running",
  "phase": "launched",
  "finished_at": null,
  "session_name": "${SESSION_NAME}",
  "run_log": "${RUN_LOG}",
  "omx_input_mode": "${OMX_INPUT_MODE}",
  "omx_command_raw": "${OMX_COMMAND}",
  "omx_bin": "${OMX_BIN}",
  "omx_args_raw": "${OMX_ARGS}",
  "omx_command_effective": "${OMX_COMMAND_RENDERED}",
  "command_policy": "${FACTORY_COMMAND_POLICY}",
  "night_mode": "${FACTORY_NIGHT_EXEC_MODE}",
  "night_task_source": "${NIGHT_TASK_SOURCE}",
  "night_task": $(printf '%s' "${NIGHT_TASK}" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
  "night_task_file": "${NIGHT_TASK_FILE}",
  "night_prompt_file": "${NIGHT_PROMPT_FILE}",
  "night_last_message_file": "${NIGHT_LAST_MESSAGE_FILE}",
  "night_team_spec": "${FACTORY_NIGHT_TEAM_SPEC}",
  "team_name": "${SESSION_NAME}",
  "night_team_helper_script": "${NIGHT_TEAM_HELPER_SCRIPT}",
  "agent_alive": true,
  "last_update_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "last_event": "factory_started",
  "last_event_details": "${SESSION_NAME}",
  "execution_mode": "${FACTORY_NIGHT_EXEC_MODE}"
}
JSON
mv -f "${tmp_meta}" "${META_FILE}"

echo "[INFO] factory-night session started: ${SESSION_NAME}"
echo "[INFO] run log: ${RUN_LOG}"
echo "[INFO] $(date -u +%Y-%m-%dT%H:%M:%SZ) session started=${SESSION_NAME} run_log=${RUN_LOG}" >> "${EVENT_LOG}"
node scripts/harness-event.mjs --event factory_started --details "${SESSION_NAME}" >/dev/null 2>&1 || true
