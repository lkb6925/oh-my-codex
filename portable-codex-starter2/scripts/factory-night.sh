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
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RUN_LOG="${RUN_DIR}/run-${TIMESTAMP}.log"
META_FILE="${RUN_DIR}/latest-run.json"
EVENT_LOG="${RUN_DIR}/factory-night-events.log"

mkdir -p "${RUN_DIR}"
find "${RUN_DIR}" -type f \( -name 'run-*.log' -o -name 'watch-*.log' -o -name 'launch-*.sh' \) -mtime +7 -delete 2>/dev/null || true

if [[ "${OMX_COMMAND}" =~ [\;\&\|\<\>\`\$\\\(\)\{\}] ]]; then
  echo "[ERROR] OMX_COMMAND contains unsafe shell metacharacters. Use plain argv style command tokens only." >&2
  exit 1
fi

declare -a OMX_TOKENS=()
OMX_INPUT_MODE="omx_command"

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

    if [[ " ${OMX_TOKENS[*]} " =~ [[:space:]]--no-tmux[[:space:]] ]]; then
      echo "[ERROR] strict policy forbids '--no-tmux' for overnight durability." >&2
      exit 1
    fi

    if ! [[ " ${OMX_TOKENS[*]} " =~ [[:space:]]--tmux[[:space:]] ]]; then
      OMX_TOKENS+=("--tmux")
      echo "[INFO] strict policy appended '--tmux'."
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
cat > "${LAUNCH_SCRIPT}" <<LAUNCH
#!/usr/bin/env bash
set -Eeuo pipefail
cd "${ROOT_DIR}"

update_meta() {
  local exit_code="\$1"
  local finished_at
  local final_status
  local final_phase
  finished_at="\$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if [[ "\${exit_code}" == "0" ]]; then
    final_status="completed"
    final_phase="launch_complete"
  else
    final_status="failed"
    final_phase="launch_failed"
  fi
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const status = process.argv[2];
    const phase = process.argv[3];
    const finishedAt = process.argv[4];
    const exitCode = Number(process.argv[5]);
    try {
      const payload = JSON.parse(fs.readFileSync(path, "utf8"));
      payload.status = status;
      payload.phase = phase;
      payload.finished_at = finishedAt;
      payload.exit_code = exitCode;
      fs.writeFileSync(path, JSON.stringify(payload, null, 2) + "\n", "utf8");
    } catch {
      process.stderr.write("[WARN] failed to update launch metadata\n");
    }
  ' "${META_FILE}" "\${final_status}" "\${final_phase}" "\${finished_at}" "\${exit_code}"
}

trap 'rc=\$?; update_meta "\$rc"' EXIT

echo "[INFO] factory-night start \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "${RUN_LOG}"
script -q -f -a -e -c "${TTY_COMMAND}" "${RUN_LOG}"
LAUNCH
chmod +x "${LAUNCH_SCRIPT}"

tmux new-session -d -s "${SESSION_NAME}" "bash '${LAUNCH_SCRIPT}'"

cat > "${META_FILE}" <<JSON
{
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "repo_path": "${ROOT_DIR}",
  "branch": "$(git branch --show-current 2>/dev/null || echo unknown)",
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
  "command_policy": "${FACTORY_COMMAND_POLICY}"
}
JSON

echo "[INFO] factory-night session started: ${SESSION_NAME}"
echo "[INFO] run log: ${RUN_LOG}"
echo "[INFO] $(date -u +%Y-%m-%dT%H:%M:%SZ) session started=${SESSION_NAME} run_log=${RUN_LOG}" >> "${EVENT_LOG}"
