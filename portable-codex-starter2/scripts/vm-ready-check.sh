#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/load-env.sh"
codex_load_env

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
require_gemini="${FACTORY_REQUIRE_GEMINI_API_KEY:-0}"
require_cmd git || status=1
require_cmd node || status=1
require_cmd npm || status=1
require_cmd bash || status=1
require_cmd tmux || status=1

if [[ -n "${GEMINI_API_KEY:-}" ]]; then
  echo "[PASS] GEMINI_API_KEY is set"
else
  if [[ "${require_gemini}" == "1" ]]; then
    echo "[FAIL] GEMINI_API_KEY is missing (FACTORY_REQUIRE_GEMINI_API_KEY=1)"
    status=1
  else
    echo "[INFO] GEMINI_API_KEY is not set in this shell; senior-review is optional unless FACTORY_REQUIRE_GEMINI_API_KEY=1."
  fi
fi

if grep -Eq "postgres(ql)?://" .codex/config.toml; then
  if [[ "${strict_preflight}" == "1" ]]; then
    echo "[FAIL] Detected a hardcoded postgres URL in .codex/config.toml (VM_PREFLIGHT_STRICT=1)"
    status=1
  else
    echo "[WARN] Detected a hardcoded postgres URL in .codex/config.toml. Move it to POSTGRES_MCP_DSN."
  fi
else
  echo "[PASS] No hardcoded postgres URL found in .codex/config.toml"
fi

if [[ -n "${POSTGRES_MCP_DSN:-}" ]]; then
  echo "[PASS] POSTGRES_MCP_DSN is set"
else
  if [[ "${strict_preflight}" == "1" ]]; then
    echo "[FAIL] POSTGRES_MCP_DSN is missing (VM_PREFLIGHT_STRICT=1)"
    status=1
  else
    echo "[WARN] POSTGRES_MCP_DSN is missing in this shell. If VM injects it at runtime, you can ignore this warning."
  fi
fi

echo "[INFO] Running kit doctor..."
node scripts/doctor.mjs --target "${ROOT_DIR}" || status=1

if [[ ${status} -ne 0 ]]; then
  echo "[ERROR] VM preflight failed. Fix the failing checks above."
  exit 1
fi

echo "[INFO] VM preflight passed. You can run: STRICT_LOCAL_CHECKS=1 bash scripts/get-senior-review.sh 1"
