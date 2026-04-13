#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

echo "[INFO] VM preflight started in ${ROOT_DIR}"

require_cmd() {
  local cmd="$1"
  if command -v "$cmd" >/dev/null 2>&1; then
    echo "[PASS] command available: ${cmd}"
    return 0
  fi
  echo "[FAIL] missing command: ${cmd}"
  return 1
}

status=0
strict_preflight="${VM_PREFLIGHT_STRICT:-0}"
require_cmd git || status=1
require_cmd node || status=1
require_cmd npm || status=1

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  echo "[PASS] GEMINI_API_KEY is set"
else
  if [[ "${strict_preflight}" == "1" ]]; then
    echo "[FAIL] GEMINI_API_KEY is missing (VM_PREFLIGHT_STRICT=1)"
    status=1
  else
    echo "[WARN] GEMINI_API_KEY is missing in this shell. If the VM already injects it, you can ignore this warning."
  fi
fi

if grep -q "postgresql://readonly:change-me@localhost/app" .codex/config.toml; then
  if [[ "${strict_preflight}" == "1" ]]; then
    echo "[FAIL] postgres DSN is still placeholder in .codex/config.toml (VM_PREFLIGHT_STRICT=1)"
    status=1
  else
    echo "[WARN] postgres DSN is still placeholder in .codex/config.toml. Replace it on the target VM before using postgres MCP."
  fi
else
  echo "[PASS] postgres DSN placeholder replaced"
fi

echo "[INFO] Running kit doctor..."
node scripts/doctor.mjs --target "${ROOT_DIR}" || status=1

if [[ ${status} -ne 0 ]]; then
  echo "[ERROR] VM preflight failed. Fix the failing checks above."
  exit 1
fi

echo "[INFO] VM preflight passed. You can run: STRICT_LOCAL_CHECKS=1 bash scripts/get-senior-review.sh"
