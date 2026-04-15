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

if [[ "${JSON_MODE}" == "1" ]]; then
  generated_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  run_state="idle"
  dirty_bool="false"
  log_age_json="null"
  meta_age_json="null"
  if [[ "${session_exists}" == "true" ]]; then
    run_state="running"
  fi
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
  "schema_version": "1.0",
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
  "omx_status": "${omx_status}"
}
JSON
  exit 0
fi

echo "factory-status"
echo "  session: ${SESSION_NAME} (${session_exists})"
echo "  branch: ${branch}"
echo "  working_tree: ${dirty}"
echo "  latest_commit: ${latest_commit}"
echo "  latest_log: ${latest_log:-none}"
echo "  log_age_seconds: ${log_age_seconds:-n/a}"
echo "  meta_age_seconds: ${meta_age_seconds:-n/a}"
echo "  omx_status: ${omx_status}"
