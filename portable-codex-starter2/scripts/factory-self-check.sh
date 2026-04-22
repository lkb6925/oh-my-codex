#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
ALERT_FILE="${RUN_DIR}/latest-alert.json"
STATUS_JSON="$(bash scripts/factory-status.sh --json)"

required_status_keys=(
  schema_version
  generated_at
  run_state
  push_state
  last_review_verdict
  poweroff_ready
  remaining_manual_actions
)

for key in "${required_status_keys[@]}"; do
  if ! node -e '
    const payload = JSON.parse(process.argv[1]);
    const key = process.argv[2];
    process.exit(Object.prototype.hasOwnProperty.call(payload, key) ? 0 : 1);
  ' "${STATUS_JSON}" "${key}"; then
    echo "[ERROR] factory-status missing key: ${key}" >&2
    exit 1
  fi
done

if [[ -f "${ALERT_FILE}" ]]; then
  required_alert_keys=(schema_version generated_at severity suggested_action alert_code)
  for key in "${required_alert_keys[@]}"; do
    if ! node -e '
      const fs = require("fs");
      const payload = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      const key = process.argv[2];
      process.exit(Object.prototype.hasOwnProperty.call(payload, key) ? 0 : 1);
    ' "${ALERT_FILE}" "${key}"; then
      echo "[ERROR] latest-alert.json missing key: ${key}" >&2
      exit 1
    fi
  done
fi

echo "[PASS] factory self-check passed."
