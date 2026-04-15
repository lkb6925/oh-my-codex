#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
META_FILE="${RUN_DIR}/latest-run.json"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
FINAL_SUMMARY_FILE="${RUN_DIR}/final-summary-${TIMESTAMP}.md"
FINISH_STATE_FILE="${RUN_DIR}/latest-finish.json"
PUSH_ON_FINISH="${FACTORY_PUSH_ON_FINISH:-1}"
STOP_SESSION_ON_FINISH="${FACTORY_STOP_SESSION_ON_FINISH:-0}"
SESSION_NAME="${FACTORY_SESSION_NAME:-factory-night}"

mkdir -p "${RUN_DIR}"

status_json() {
  bash scripts/factory-status.sh --json
}

json_field() {
  local json_payload="$1"
  local field_name="$2"
  node -e '
    const raw = process.argv[1];
    const field = process.argv[2];
    try {
      const parsed = JSON.parse(raw);
      const value = parsed[field];
      if (value === undefined || value === null) {
        process.stdout.write("");
      } else {
        process.stdout.write(String(value));
      }
    } catch {
      process.stdout.write("");
    }
  ' "${json_payload}" "${field_name}"
}

json_array_field() {
  local json_payload="$1"
  local field_name="$2"
  node -e '
    const raw = process.argv[1];
    const field = process.argv[2];
    try {
      const parsed = JSON.parse(raw);
      const value = parsed[field];
      if (!Array.isArray(value)) {
        process.stdout.write("[]");
      } else {
        process.stdout.write(JSON.stringify(value));
      }
    } catch {
      process.stdout.write("[]");
    }
  ' "${json_payload}" "${field_name}"
}

echo "[INFO] Generating final summary: ${FINAL_SUMMARY_FILE}"
bash scripts/factory-summary.sh > "${FINAL_SUMMARY_FILE}"

current_status="$(status_json)"
initial_push_state="$(json_field "${current_status}" "push_state")"
push_attempted="false"
push_result="skipped"

if [[ "${PUSH_ON_FINISH}" == "1" ]]; then
  if [[ "${initial_push_state}" == "needs_push" ]]; then
    push_attempted="true"
    if git push; then
      push_result="success"
    else
      push_result="failed"
      echo "[WARN] git push failed during factory finish."
    fi
  elif [[ "${initial_push_state}" == "pushed" ]]; then
    push_result="already_pushed"
  else
    push_result="not_pushable"
  fi
fi

if [[ "${STOP_SESSION_ON_FINISH}" == "1" ]]; then
  if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
    tmux kill-session -t "${SESSION_NAME}" || true
  fi
fi

final_status="$(status_json)"
poweroff_ready="$(json_field "${final_status}" "poweroff_ready")"
push_state="$(json_field "${final_status}" "push_state")"
last_review_verdict="$(json_field "${final_status}" "last_review_verdict")"
session_exists="$(json_field "${final_status}" "session_exists")"
remaining_actions_json="$(json_array_field "${final_status}" "remaining_manual_actions")"

final_status_label="stalled"
final_phase="finish_pending"
finished_at_value="${FINISHED_AT}"
if [[ "${poweroff_ready}" == "true" ]]; then
  final_status_label="completed"
  final_phase="finish_complete"
elif [[ "${session_exists}" == "true" ]]; then
  final_status_label="running"
  final_phase="finish_requested"
  finished_at_value="null"
elif [[ "${push_state}" == "needs_push" || "${push_state}" == "no_upstream" || "${push_state}" == "diverged" || "${push_state}" == "behind_remote" ]]; then
  final_status_label="stalled"
  final_phase="awaiting_push"
elif [[ "${last_review_verdict}" != "approved" && "${last_review_verdict}" != "pass" ]]; then
  final_status_label="stalled"
  final_phase="awaiting_review_resolution"
else
  final_status_label="failed"
  final_phase="finish_incomplete"
fi

node -e '
  const fs = require("fs");
  const path = process.argv[1];
  const statusLabel = process.argv[2];
  const phase = process.argv[3];
  const finishedAtRaw = process.argv[4];
  const poweroffReady = process.argv[5] === "true";
  const remainingActions = JSON.parse(process.argv[6]);
  const pushState = process.argv[7];
  const reviewVerdict = process.argv[8];
  const summaryPath = process.argv[9];
  const repoPath = process.argv[10];
  const branch = process.argv[11];
  let payload = {};
  try {
    payload = JSON.parse(fs.readFileSync(path, "utf8"));
  } catch {
    payload = {};
  }
  payload.repo_path = payload.repo_path ?? repoPath;
  payload.branch = payload.branch ?? branch;
  payload.status = statusLabel;
  payload.phase = phase;
  payload.finished_at = finishedAtRaw === "null" ? null : finishedAtRaw;
  payload.poweroff_ready = poweroffReady;
  payload.remaining_manual_actions = remainingActions;
  payload.push_state = pushState;
  payload.last_review_verdict = reviewVerdict;
  payload.final_summary_file = summaryPath;
  fs.writeFileSync(path, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
' "${META_FILE}" "${final_status_label}" "${final_phase}" "${finished_at_value}" "${poweroff_ready}" "${remaining_actions_json}" "${push_state}" "${last_review_verdict}" "${FINAL_SUMMARY_FILE}" "${ROOT_DIR}" "$(git branch --show-current 2>/dev/null || echo unknown)"

cat > "${FINISH_STATE_FILE}" <<JSON
{
  "schema_version": "1.0",
  "generated_at": "${FINISHED_AT}",
  "summary_file": "${FINAL_SUMMARY_FILE}",
  "push_attempted": ${push_attempted},
  "push_result": "${push_result}",
  "push_state": "${push_state}",
  "last_review_verdict": "${last_review_verdict}",
  "poweroff_ready": ${poweroff_ready},
  "remaining_manual_actions": ${remaining_actions_json}
}
JSON

echo "[INFO] factory-finish complete."
echo "[INFO] summary: ${FINAL_SUMMARY_FILE}"
echo "[INFO] finish state: ${FINISH_STATE_FILE}"
echo "[INFO] poweroff_ready=${poweroff_ready} push_state=${push_state} review=${last_review_verdict}"
