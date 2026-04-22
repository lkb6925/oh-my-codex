#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
ROOT_NAME="$(basename "${ROOT_DIR}")"

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

SESSION_NAME="${FACTORY_SESSION_NAME:-factory-night-${ROOT_NAME}}"
RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
WATCH_INTERVAL_SECONDS="${WATCH_INTERVAL_SECONDS:-60}"
LOG_STALL_SECONDS="${LOG_STALL_SECONDS:-1800}"
META_STALL_SECONDS="${META_STALL_SECONDS:-1800}"
OMX_UNAVAILABLE_LIMIT="${OMX_UNAVAILABLE_LIMIT:-3}"
SUSPECTED_LOOP_LIMIT="${SUSPECTED_LOOP_LIMIT:-5}"
WATCH_MAX_CYCLES="${WATCH_MAX_CYCLES:-0}"
WATCH_LOG="${RUN_DIR}/watch-$(date -u +%Y%m%dT%H%M%SZ).log"
ALERT_SNAPSHOT_FILE="${RUN_DIR}/latest-alert.json"
META_FILE="${RUN_DIR}/latest-run.json"

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

write_alert_snapshot() {
  local status_json="$1"
  local reason_text="$2"
  local severity="$3"
  local suggested_action="$4"
  local alert_code="$5"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs");
      const outputPath = process.argv[1];
      const cycle = Number(process.argv[2]);
      const reason = process.argv[3];
      const severity = process.argv[4];
      const suggestedAction = process.argv[5];
      const alertCode = process.argv[6];
      const timestamp = process.argv[7];
      let status = {};
      try {
        status = JSON.parse(fs.readFileSync(0, "utf8"));
      } catch {
        status = {};
      }
      const payload = {
        schema_version: "1.0",
        generated_at: timestamp,
        cycle,
        reason,
        severity,
        alert_code: alertCode,
        suggested_action: suggestedAction,
        run_state: status.run_state ?? null,
        session_exists: status.session_exists ?? null,
        latest_log: status.latest_log ?? null,
        log_age_seconds: status.log_age_seconds ?? null,
        meta_age_seconds: status.meta_age_seconds ?? null,
        omx_status: status.omx_status ?? null
      };
      fs.writeFileSync(outputPath, `${JSON.stringify(payload, null, 2)}\n`, "utf8");
    ' "${ALERT_SNAPSHOT_FILE}" "${cycle_count}" "${reason_text}" "${severity}" "${suggested_action}" "${alert_code}" "${timestamp}" <<< "${status_json}"
    return 0
  fi

  if [[ "${JSON_QUERY_TOOL}" == "jq" ]]; then
    jq -n \
      --arg generated_at "${timestamp}" \
      --arg reason "${reason_text}" \
      --arg severity "${severity}" \
      --arg suggested_action "${suggested_action}" \
      --arg alert_code "${alert_code}" \
      --argjson cycle "${cycle_count}" \
      --argjson status "${status_json}" \
      '{
        schema_version: "1.0",
        generated_at: $generated_at,
        cycle: $cycle,
        reason: $reason,
        severity: $severity,
        alert_code: $alert_code,
        suggested_action: $suggested_action,
        run_state: $status.run_state,
        session_exists: $status.session_exists,
        latest_log: $status.latest_log,
        log_age_seconds: $status.log_age_seconds,
        meta_age_seconds: $status.meta_age_seconds,
        omx_status: $status.omx_status
      }' > "${ALERT_SNAPSHOT_FILE}"
  fi
}

update_run_state_on_alert() {
  local next_status="$1"
  local next_phase="$2"
  if [[ ! -f "${META_FILE}" ]]; then
    return 0
  fi
  node -e '
    const fs = require("fs");
    const filePath = process.argv[1];
    const status = process.argv[2];
    const phase = process.argv[3];
    try {
      const parsed = JSON.parse(fs.readFileSync(filePath, "utf8"));
      parsed.status = status;
      parsed.phase = phase;
      fs.writeFileSync(filePath, `${JSON.stringify(parsed, null, 2)}\n`, "utf8");
    } catch {
      process.exit(0);
    }
  ' "${META_FILE}" "${next_status}" "${next_phase}"
}

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
    severity="medium"
    suggested_action="inspect_factory_status"
    alert_code="factory_alert_generic"
    next_run_status="stalled"
    next_run_phase="alert_detected"
    if [[ "${reason[*]}" == *"tmux session missing"* ]]; then
      severity="high"
      alert_code="factory_session_missing"
      suggested_action="restart_factory_night_session"
      next_run_phase="session_missing"
    elif [[ "${reason[*]}" == *"omx status unavailable"* ]]; then
      severity="high"
      alert_code="factory_omx_unavailable"
      suggested_action="verify_omx_runtime_and_credentials"
      next_run_phase="omx_unavailable"
    elif [[ "${reason[*]}" == *"run log stale"* || "${reason[*]}" == *"run metadata stale"* ]]; then
      severity="medium"
      alert_code="factory_stale_activity"
      suggested_action="check_run_log_and_consider_restart"
      next_run_phase="stale_activity"
    elif [[ "${reason[*]}" == *"suspected_loop"* ]]; then
      severity="medium"
      alert_code="factory_suspected_loop"
      suggested_action="inspect_review_artifacts_and_adjust_workflow"
      next_run_phase="suspected_loop"
    fi

    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "[WARN] ${ts} :: ${reason[*]} (severity=${severity})" | tee -a "${WATCH_LOG}"
    write_alert_snapshot "${status_json}" "${reason[*]}" "${severity}" "${suggested_action}" "${alert_code}"
    update_run_state_on_alert "${next_run_status}" "${next_run_phase}"
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
