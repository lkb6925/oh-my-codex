#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
ROOT_NAME="$(basename "${ROOT_DIR}")"

TEAM_RUNTIME_ROOT="${FACTORY_TEAM_RUNTIME_ROOT:-${XDG_RUNTIME_DIR:-/tmp}/factory-team}"
RUN_DIR="${TEAM_RUNTIME_ROOT}/${ROOT_NAME}"
META_FILE="${FACTORY_TEAM_META_FILE:-${RUN_DIR}/latest-run.json}"
SHUTDOWN_LOG_DIR="${FACTORY_TEAM_SHUTDOWN_LOG_DIR:-${RUN_DIR}}"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
REQUESTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
JSON_MODE=0
if [[ "${1:-}" == "--json" ]]; then
  JSON_MODE=1
fi

read_meta_field() {
  local field_name="$1"
  if [[ ! -f "${META_FILE}" ]]; then
    return 0
  fi
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const field = process.argv[2];
    try {
      const parsed = JSON.parse(fs.readFileSync(path, "utf8"));
      const value = parsed[field];
      if (value === undefined || value === null) {
        process.stdout.write("");
      } else {
        process.stdout.write(String(value));
      }
    } catch {
      process.stdout.write("");
    }
  ' "${META_FILE}" "${field_name}"
}

write_json_file() {
  local output_path="$1"
  local payload_json="$2"
  mkdir -p "$(dirname "${output_path}")"
  printf '%s\n' "${payload_json}" > "${output_path}"
}

meta_repo_path="$(read_meta_field repo_path)"
meta_session_name="$(read_meta_field session_name)"
meta_team_name="$(read_meta_field team_name)"
meta_team_name_hint="$(read_meta_field team_name_hint)"
meta_status="$(read_meta_field status)"
meta_phase="$(read_meta_field phase)"

if [[ -n "${meta_repo_path}" && -d "${meta_repo_path}" ]]; then
  cd "${meta_repo_path}"
fi

TEAM_NAME="${1:-${FACTORY_TEAM_SESSION_NAME:-${meta_team_name:-${meta_team_name_hint:-factory-team-${ROOT_NAME}}}}}"
if [[ "${1:-}" == "--json" ]]; then
  TEAM_NAME="${FACTORY_TEAM_SESSION_NAME:-${meta_team_name:-${meta_team_name_hint:-factory-team-${ROOT_NAME}}}}"
fi

if [[ -z "${TEAM_NAME}" ]]; then
  echo "[ERROR] unable to determine team name for shutdown." >&2
  exit 1
fi

if ! command -v omx >/dev/null 2>&1; then
  echo "[ERROR] omx is required for factory-team-shutdown." >&2
  exit 1
fi

force_flag="${FACTORY_TEAM_SHUTDOWN_FORCE:-0}"
confirm_issues_flag="${FACTORY_TEAM_SHUTDOWN_CONFIRM_ISSUES:-0}"
shutdown_log="${SHUTDOWN_LOG_DIR}/shutdown-${TIMESTAMP}.log"
shutdown_state_file="${RUN_DIR}/latest-shutdown.json"
mkdir -p "${SHUTDOWN_LOG_DIR}"

args=(omx team shutdown "${TEAM_NAME}")
if [[ "${force_flag}" == "1" ]]; then
  args+=(--force)
fi
if [[ "${confirm_issues_flag}" == "1" ]]; then
  args+=(--confirm-issues)
fi

set +e
{
  printf '[INFO] requested_at=%s team=%s force=%s confirm_issues=%s\n' "${REQUESTED_AT}" "${TEAM_NAME}" "${force_flag}" "${confirm_issues_flag}"
  "${args[@]}"
} >"${shutdown_log}" 2>&1
exit_code=$?
set -e

shutdown_result="failed"
if [[ "${exit_code}" == "0" ]]; then
  shutdown_result="success"
fi

tmp_shutdown_state="$(mktemp "${shutdown_state_file}.XXXXXX")"
node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const outputPath = process.argv[2];
  const payload = {
    schema_version: "1.0",
    requested_at: process.argv[3],
    finished_at: process.argv[4],
    repo_path: process.argv[5],
    session_name: process.argv[6],
    team_name: process.argv[7],
    team_name_hint: process.argv[8],
    status: process.argv[9],
    phase: process.argv[10],
    force: process.argv[11] === "1",
    confirm_issues: process.argv[12] === "1",
    exit_code: Number(process.argv[13]),
    result: process.argv[14],
    log_file: process.argv[15],
    meta_file: process.argv[16],
  };
  fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
' "${tmp_shutdown_state}" "${REQUESTED_AT}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${meta_repo_path}" "${meta_session_name}" "${TEAM_NAME}" "${meta_team_name_hint}" "${meta_status}" "${meta_phase}" "${force_flag}" "${confirm_issues_flag}" "${exit_code}" "${shutdown_result}" "${shutdown_log}" "${META_FILE}" && mv -f "${tmp_shutdown_state}" "${shutdown_state_file}"


tmp_meta="$(mktemp "${META_FILE}.XXXXXX")"
node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const outputPath = process.argv[2];
  const teamName = process.argv[3];
  const status = process.argv[4];
  const phase = process.argv[5];
  const requestedAt = process.argv[6];
  const finishedAt = process.argv[7];
  const result = process.argv[8];
  const logFile = process.argv[9];
  const shutdownStateFile = process.argv[10];
  try {
    const payload = JSON.parse(fs.readFileSync(path, "utf8"));
    payload.last_update_at = finishedAt;
    payload.last_event = result === "success" ? "factory_team_shutdown_complete" : "factory_team_shutdown_failed";
    payload.last_event_details = `${teamName} -> ${result}`;
    payload.team_name = payload.team_name || teamName || "";
    payload.team_shutdown_requested_at = requestedAt;
    payload.team_shutdown_finished_at = finishedAt;
    payload.team_shutdown_result = result;
    payload.team_shutdown_log = logFile;
    payload.team_shutdown_state_file = shutdownStateFile;
    if (result === "success") {
      payload.status = payload.status === "running" ? "stopped" : payload.status;
      payload.phase = "team_shutdown_complete";
      payload.finished_at = payload.finished_at || finishedAt;
    } else {
      payload.phase = "team_shutdown_failed";
    }
    fs.writeFileSync(outputPath, JSON.stringify(payload, null, 2) + "\n", "utf8");
  } catch {
    process.stderr.write("[WARN] failed to update team metadata after shutdown\n");
  }
' "${META_FILE}" "${tmp_meta}" "${TEAM_NAME}" "${meta_status}" "${meta_phase}" "${REQUESTED_AT}" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${shutdown_result}" "${shutdown_log}" "${shutdown_state_file}" && mv -f "${tmp_meta}" "${META_FILE}"


node scripts/harness-event.mjs --event factory_team_shutdown --details "${TEAM_NAME}:${shutdown_result}" >/dev/null 2>&1 || true

if [[ "${JSON_MODE}" == "1" ]]; then
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    try {
      const payload = JSON.parse(fs.readFileSync(path, "utf8"));
      process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
    } catch {
      process.stdout.write("{}\n");
    }
  ' "${shutdown_state_file}"
  exit "${exit_code}"
fi

echo "[INFO] factory-team shutdown ${shutdown_result}: ${TEAM_NAME}"
echo "[INFO] shutdown log: ${shutdown_log}"
echo "[INFO] shutdown state: ${shutdown_state_file}"
exit "${exit_code}"
