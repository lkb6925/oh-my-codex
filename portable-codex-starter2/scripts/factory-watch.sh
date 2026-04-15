#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

JSON_QUERY_TOOL="jq"
if ! command -v jq >/dev/null 2>&1; then
  if command -v node >/dev/null 2>&1; then
    JSON_QUERY_TOOL="node"
    echo "[WARN] jq not found; falling back to node-based JSON parsing."
  else
    echo "[ERROR] jq or node is required for JSON parsing." >&2
    exit 1
  fi
fi

ONCE_MODE=0
if [[ "${1:-}" == "--once" ]]; then
  ONCE_MODE=1
fi

SESSION_NAME="${FACTORY_SESSION_NAME:-factory-night}"
RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-60}"
LOG_STALL_SECONDS="${LOG_STALL_SECONDS:-1800}"
META_STALL_SECONDS="${META_STALL_SECONDS:-1800}"
OMX_UNAVAILABLE_LIMIT="${OMX_UNAVAILABLE_LIMIT:-3}"
SUSPECTED_LOOP_LIMIT="${SUSPECTED_LOOP_LIMIT:-5}"
WATCH_MAX_CYCLES="${WATCH_MAX_CYCLES:-0}"
WATCH_LOG="${RUN_DIR}/watch-$(date -u +%Y%m%dT%H%M%SZ).log"

mkdir -p "${RUN_DIR}"
omx_unavailable_count=0
loop_suspect_count=0
prev_log_size=""
prev_checks_mtime=""
prev_review_mtime=""
cycle_count=0
stop_requested=0

extract_json_field() {
  local json="$1"
  local field="$2"
  if [[ "${JSON_QUERY_TOOL}" == "jq" ]]; then
    echo "${json}" | jq -r ".${field}"
    return 0
  fi
  node -e '
    let raw = "";
    process.stdin.on("data", (chunk) => { raw += chunk; });
    process.stdin.on("end", () => {
      try {
        const parsed = JSON.parse(raw);
        const key = process.argv[1];
        const value = parsed[key];
        if (value === null || value === undefined) {
          process.stdout.write("null");
          return;
        }
        process.stdout.write(String(value));
      } catch {
        process.stdout.write("null");
      }
    });
  ' "${field}" <<< "${json}"
}

request_stop() {
  stop_requested=1
}

trap request_stop INT TERM

echo "[INFO] factory-watch started; events -> ${WATCH_LOG}" | tee -a "${WATCH_LOG}"
if [[ "${ONCE_MODE}" == "1" ]]; then
  echo "[INFO] running in --once mode" | tee -a "${WATCH_LOG}"
fi
if [[ "${WATCH_MAX_CYCLES}" =~ ^[0-9]+$ ]] && (( WATCH_MAX_CYCLES > 0 )); then
  echo "[INFO] WATCH_MAX_CYCLES=${WATCH_MAX_CYCLES}" | tee -a "${WATCH_LOG}"
fi

while true; do
  cycle_count=$((cycle_count + 1))
  status_json="$(bash scripts/factory-status.sh --json)"
  session_exists="$(extract_json_field "${status_json}" "session_exists")"
  latest_log="$(extract_json_field "${status_json}" "latest_log")"
  log_age="$(extract_json_field "${status_json}" "log_age_seconds")"
  meta_age="$(extract_json_field "${status_json}" "meta_age_seconds")"
  omx_status="$(extract_json_field "${status_json}" "omx_status")"

  alert=0
  reason=()
  log_progress="false"

  if [[ "${session_exists}" != "true" ]]; then
    alert=1
    reason+=("tmux session missing")
  fi

  if [[ "${latest_log}" != "" && "${latest_log}" != "null" && "${log_age}" != "" && "${log_age}" != "null" ]]; then
    if [[ "${log_age}" =~ ^[0-9]+$ ]] && (( log_age > LOG_STALL_SECONDS )); then
      alert=1
      reason+=("run log stale (${log_age}s)")
    else
      if [[ -f "${latest_log}" ]]; then
        current_log_size="$(stat -c %s "${latest_log}")"
        if [[ "${prev_log_size}" != "" && "${current_log_size}" != "${prev_log_size}" ]]; then
          log_progress="true"
        fi
        prev_log_size="${current_log_size}"
      fi
    fi
  fi

  if [[ "${meta_age}" != "" && "${meta_age}" != "null" && "${meta_age}" =~ ^[0-9]+$ ]] && (( meta_age > META_STALL_SECONDS )); then
    alert=1
    reason+=("run metadata stale (${meta_age}s)")
  fi

  if [[ "${omx_status}" != "available" ]]; then
    omx_unavailable_count=$((omx_unavailable_count + 1))
  else
    omx_unavailable_count=0
  fi

  if (( omx_unavailable_count >= OMX_UNAVAILABLE_LIMIT )); then
    alert=1
    reason+=("omx status unavailable ${omx_unavailable_count} times")
  fi

  latest_checks="$(ls -1t .tmp-local-checks-round*.summary.json 2>/dev/null | head -n 1 || true)"
  latest_review="$(ls -1t .tmp-gemini-review-round*.json 2>/dev/null | head -n 1 || true)"
  checks_mtime=""
  review_mtime=""
  [[ -n "${latest_checks}" && -f "${latest_checks}" ]] && checks_mtime="$(stat -c %Y "${latest_checks}")"
  [[ -n "${latest_review}" && -f "${latest_review}" ]] && review_mtime="$(stat -c %Y "${latest_review}")"

  if [[ "${log_progress}" == "true" && "${checks_mtime}" == "${prev_checks_mtime}" && "${review_mtime}" == "${prev_review_mtime}" ]]; then
    loop_suspect_count=$((loop_suspect_count + 1))
  else
    loop_suspect_count=0
  fi
  prev_checks_mtime="${checks_mtime}"
  prev_review_mtime="${review_mtime}"

  if (( loop_suspect_count >= SUSPECTED_LOOP_LIMIT )); then
    alert=1
    reason+=("suspected_loop: logs update without new check/review artifacts")
  fi

  if (( alert == 1 )); then
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "[WARN] ${ts} :: ${reason[*]}" | tee -a "${WATCH_LOG}"
    bash scripts/factory-status.sh | tee -a "${WATCH_LOG}"
  fi

  if [[ "${ONCE_MODE}" == "1" ]]; then
    echo "[INFO] --once complete after cycle ${cycle_count}" | tee -a "${WATCH_LOG}"
    break
  fi

  if [[ "${WATCH_MAX_CYCLES}" =~ ^[0-9]+$ ]] && (( WATCH_MAX_CYCLES > 0 )) && (( cycle_count >= WATCH_MAX_CYCLES )); then
    echo "[INFO] WATCH_MAX_CYCLES reached (${WATCH_MAX_CYCLES}); exiting." | tee -a "${WATCH_LOG}"
    break
  fi

  if (( stop_requested == 1 )); then
    echo "[INFO] stop requested; exiting watch loop." | tee -a "${WATCH_LOG}"
    break
  fi

  if ! sleep "${WATCH_INTERVAL_SECONDS}"; then
    echo "[ERROR] sleep command failed; exiting watch loop to avoid runaway state." | tee -a "${WATCH_LOG}" >&2
    exit 1
  fi
done
