#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
ROOT_NAME="$(basename "${ROOT_DIR}")"

JSON_MODE=0
if [[ "${1:-}" == "--json" ]]; then
  JSON_MODE=1
fi

SESSION_NAME="${FACTORY_SESSION_NAME:-factory-night-${ROOT_NAME}}"
RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
META_FILE="${RUN_DIR}/latest-run.json"
LAST_ALERT_FILE="${RUN_DIR}/latest-alert.json"
REQUIRE_REVIEW_FOR_POWEROFF="${REQUIRE_REVIEW_FOR_POWEROFF:-0}"

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
last_alert_severity=""
last_alert_code=""
if [[ -n "${last_alert_file}" ]]; then
  last_alert_severity="$(json_field_from_file "${last_alert_file}" "severity")"
  last_alert_code="$(json_field_from_file "${last_alert_file}" "alert_code")"
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
if [[ "${session_exists}" != "true" && "${run_state}" == "running" ]]; then
  run_state="stalled"
fi

remaining_actions=()
if [[ "${push_state}" == "needs_push" ]]; then
  remaining_actions+=("push_commits")
elif [[ "${push_state}" == "no_upstream" ]]; then
  remaining_actions+=("set_upstream")
elif [[ "${push_state}" == "behind_remote" ]]; then
  remaining_actions+=("sync_with_remote")
elif [[ "${push_state}" == "diverged" ]]; then
  remaining_actions+=("resolve_divergence")
fi
if [[ "${dirty}" == "dirty" ]]; then
  remaining_actions+=("clean_working_tree")
fi
if [[ "${last_review_verdict}" == "unknown" ]]; then
  if [[ "${REQUIRE_REVIEW_FOR_POWEROFF}" == "1" ]]; then
    remaining_actions+=("run_senior_review")
  fi
elif [[ "${last_review_verdict}" != "approved" && "${last_review_verdict}" != "pass" ]]; then
  remaining_actions+=("resolve_review_findings")
fi
if [[ "${session_exists}" == "true" ]]; then
  remaining_actions+=("stop_factory_session")
fi

remaining_actions_json="$(printf '%s\n' "${remaining_actions[@]}" | node -e '
  const fs = require("fs");
  const raw = fs.readFileSync(0, "utf8").split("\n").map((line) => line.trim()).filter(Boolean);
  process.stdout.write(JSON.stringify(raw));
')"

poweroff_ready="false"
if [[ "${#remaining_actions[@]}" -eq 0 ]]; then
  poweroff_ready="true"
fi

if [[ "${JSON_MODE}" == "1" ]]; then
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  node -e '
    const payload = {
      schema_version: "1.3",
      generated_at: process.argv[1],
      run_state: process.argv[2],
      session_name: process.argv[3],
      session_exists: process.argv[4] === "true",
      branch: process.argv[5],
      dirty: process.argv[6] === "dirty",
      latest_commit: process.argv[7],
      latest_log: process.argv[8],
      log_age_seconds: process.argv[9] === "" ? null : Number(process.argv[9]),
      meta_file: process.argv[10],
      meta_age_seconds: process.argv[11] === "" ? null : Number(process.argv[11]),
      omx_status: process.argv[12],
      push_state: process.argv[13],
      last_review_verdict: process.argv[14],
      last_alert_file: process.argv[15],
      last_alert_severity: process.argv[16],
      last_alert_code: process.argv[17],
      poweroff_ready: process.argv[18] === "true",
      require_review_for_poweroff: process.argv[19] === "1",
      remaining_manual_actions: JSON.parse(process.argv[20] || "[]")
    };
    process.stdout.write(`${JSON.stringify(payload, null, 2)}\n`);
  ' "${generated_at}" "${run_state}" "${SESSION_NAME}" "${session_exists}" "${branch}" "${dirty}" "${latest_commit}" "${latest_log}" "${log_age_seconds}" "${META_FILE}" "${meta_age_seconds}" "${omx_status}" "${push_state}" "${last_review_verdict}" "${last_alert_file}" "${last_alert_severity}" "${last_alert_code}" "${poweroff_ready}" "${REQUIRE_REVIEW_FOR_POWEROFF}" "${remaining_actions_json}"
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
echo "  last_alert_severity: ${last_alert_severity:-none}"
echo "  last_alert_code: ${last_alert_code:-none}"
echo "  require_review_for_poweroff: ${REQUIRE_REVIEW_FOR_POWEROFF}"
echo "  poweroff_ready: ${poweroff_ready}"
echo "  remaining_manual_actions: ${remaining_actions[*]:-none}"
