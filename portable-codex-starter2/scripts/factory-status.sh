#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

JSON_MODE=0
if [[ "${1:-}" == "--json" ]]; then
  JSON_MODE=1
fi

SESSION_NAME="${FACTORY_SESSION_NAME:-factory-night}"
RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
META_FILE="${RUN_DIR}/latest-run.json"
LAST_ALERT_FILE="${RUN_DIR}/latest-alert.json"

json_field_from_file() {
  local file_path="$1"
  local field_name="$2"
  node -e '
    const fs = require("fs");
    const path = process.argv[1];
    const field = process.argv[2];
    try {
      const parsed = JSON.parse(fs.readFileSync(path, "utf8"));
      const value = parsed[field];
      if (value === null || value === undefined) {
        process.stdout.write("");
      } else {
        process.stdout.write(String(value));
      }
    } catch {
      process.stdout.write("");
    }
  ' "${file_path}" "${field_name}"
}

branch="$(git branch --show-current 2>/dev/null || echo unknown)"
latest_commit="$(git log --oneline -n 1 2>/dev/null | head -n 1)"
dirty="clean"
if [[ -n "$(git status --short 2>/dev/null)" ]]; then
  dirty="dirty"
fi

session_exists="false"
if tmux has-session -t "${SESSION_NAME}" 2>/dev/null; then
  session_exists="true"
fi

latest_log=""
if ls "${RUN_DIR}"/run-*.log >/dev/null 2>&1; then
  latest_log="$(ls -1t "${RUN_DIR}"/run-*.log | head -n 1)"
fi

log_age_seconds=""
if [[ -n "${latest_log}" && -f "${latest_log}" ]]; then
  now="$(date +%s)"
  mtime="$(stat -c %Y "${latest_log}")"
  log_age_seconds="$((now - mtime))"
fi

meta_age_seconds=""
if [[ -f "${META_FILE}" ]]; then
  now="$(date +%s)"
  mtime="$(stat -c %Y "${META_FILE}")"
  meta_age_seconds="$((now - mtime))"
fi

omx_status="unavailable"
if command -v omx >/dev/null 2>&1; then
  if timeout 5 omx status >/tmp/factory-omx-status.txt 2>&1; then
    omx_status="available"
  fi
fi

push_state="unknown"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  if git rev-parse --abbrev-ref @{upstream} >/dev/null 2>&1; then
    ahead_behind="$(git rev-list --left-right --count @{upstream}...HEAD 2>/dev/null || echo "0 0")"
    behind_count="$(echo "${ahead_behind}" | awk '{print $1}')"
    ahead_count="$(echo "${ahead_behind}" | awk '{print $2}')"
    if [[ "${ahead_count}" == "0" && "${behind_count}" == "0" ]]; then
      push_state="pushed"
    elif [[ "${ahead_count}" != "0" && "${behind_count}" == "0" ]]; then
      push_state="needs_push"
    elif [[ "${ahead_count}" == "0" && "${behind_count}" != "0" ]]; then
      push_state="behind_remote"
    else
      push_state="diverged"
    fi
  else
    push_state="no_upstream"
  fi
fi

last_review_verdict=""
latest_review_file="$(ls -1t .tmp-gemini-review-round*.json 2>/dev/null | head -n 1 || true)"
if [[ -n "${latest_review_file}" && -f "${latest_review_file}" ]]; then
  last_review_verdict="$(json_field_from_file "${latest_review_file}" "verdict")"
fi
if [[ -z "${last_review_verdict}" ]]; then
  last_review_verdict="unknown"
fi

last_alert_file=""
if [[ -f "${LAST_ALERT_FILE}" ]]; then
  last_alert_file="${LAST_ALERT_FILE}"
fi

meta_status=""
if [[ -f "${META_FILE}" ]]; then
  meta_status="$(json_field_from_file "${META_FILE}" "status")"
fi
run_state="idle"
if [[ "${session_exists}" == "true" ]]; then
  run_state="running"
elif [[ -n "${meta_status}" ]]; then
  run_state="${meta_status}"
fi

remaining_actions=()
if [[ "${push_state}" != "pushed" ]]; then
  remaining_actions+=("push")
fi
if [[ "${dirty}" == "dirty" ]]; then
  remaining_actions+=("clean_working_tree")
fi
if [[ "${last_review_verdict}" != "approved" && "${last_review_verdict}" != "pass" ]]; then
  remaining_actions+=("resolve_review")
fi
if [[ "${session_exists}" == "true" ]]; then
  remaining_actions+=("stop_factory_session")
fi

remaining_actions_json="[]"
if [[ "${#remaining_actions[@]}" -gt 0 ]]; then
  remaining_actions_json="["
  for action in "${remaining_actions[@]}"; do
    if [[ "${remaining_actions_json}" != "[" ]]; then
      remaining_actions_json+=","
    fi
    remaining_actions_json+="\"${action}\""
  done
  remaining_actions_json+="]"
fi

poweroff_ready="false"
if [[ "${#remaining_actions[@]}" -eq 0 ]]; then
  poweroff_ready="true"
fi

if [[ "${JSON_MODE}" == "1" ]]; then
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  dirty_bool="false"
  log_age_json="null"
  meta_age_json="null"
  if [[ "${dirty}" == "dirty" ]]; then
    dirty_bool="true"
  fi
  if [[ "${log_age_seconds}" =~ ^[0-9]+$ ]]; then
    log_age_json="${log_age_seconds}"
  fi
  if [[ "${meta_age_seconds}" =~ ^[0-9]+$ ]]; then
    meta_age_json="${meta_age_seconds}"
  fi
  cat <<JSON
{
  "schema_version": "1.1",
  "generated_at": "${generated_at}",
  "run_state": "${run_state}",
  "session_name": "${SESSION_NAME}",
  "session_exists": ${session_exists},
  "branch": "${branch}",
  "dirty": ${dirty_bool},
  "latest_commit": "${latest_commit}",
  "latest_log": "${latest_log}",
  "log_age_seconds": ${log_age_json},
  "meta_file": "${META_FILE}",
  "meta_age_seconds": ${meta_age_json},
  "omx_status": "${omx_status}",
  "push_state": "${push_state}",
  "last_review_verdict": "${last_review_verdict}",
  "last_alert_file": "${last_alert_file}",
  "poweroff_ready": ${poweroff_ready},
  "remaining_manual_actions": ${remaining_actions_json}
}
JSON
  exit 0
fi

echo "factory-status"
echo "  session: ${SESSION_NAME} (${session_exists})"
echo "  run_state: ${run_state}"
echo "  branch: ${branch}"
echo "  working_tree: ${dirty}"
echo "  latest_commit: ${latest_commit}"
echo "  latest_log: ${latest_log:-none}"
echo "  log_age_seconds: ${log_age_seconds:-n/a}"
echo "  meta_age_seconds: ${meta_age_seconds:-n/a}"
echo "  omx_status: ${omx_status}"
echo "  push_state: ${push_state}"
echo "  last_review_verdict: ${last_review_verdict}"
echo "  last_alert_file: ${last_alert_file:-none}"
echo "  poweroff_ready: ${poweroff_ready}"
echo "  remaining_manual_actions: ${remaining_actions[*]:-none}"
