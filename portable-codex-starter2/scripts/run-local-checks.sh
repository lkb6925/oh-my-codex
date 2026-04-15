#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

LOCK_FILE="${HARNESS_LOCK_FILE:-.harness.lock}"
LOCK_DIR="${HARNESS_LOCK_DIR:-.harness.lock.d}"
HARNESS_LOCK_MODE="${HARNESS_LOCK_MODE:-mkdir}"
LOCK_MODE="none"

if [[ "${HARNESS_LOCK_MODE}" != "mkdir" && "${HARNESS_LOCK_MODE}" != "flock" && "${HARNESS_LOCK_MODE}" != "auto" ]]; then
  echo "[ERROR] HARNESS_LOCK_MODE must be one of: mkdir, flock, auto" >&2
  exit 1
fi

try_flock_lock() {
  if ! command -v flock >/dev/null 2>&1; then
    return 1
  fi
  exec 9>"${LOCK_FILE}"
  if ! flock -n 9; then
    echo "[ERROR] harness lock is active: ${LOCK_FILE}" >&2
    exit 1
  fi
  LOCK_MODE="flock"
  return 0
}

try_mkdir_lock() {
  if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
    echo "[ERROR] harness lock is active: ${LOCK_DIR}" >&2
    exit 1
  fi
  LOCK_MODE="mkdir"
}

if [[ "${HARNESS_LOCK_MODE}" == "flock" ]]; then
  try_flock_lock || { echo "[ERROR] flock requested but unavailable on this host." >&2; exit 1; }
elif [[ "${HARNESS_LOCK_MODE}" == "auto" ]]; then
  if ! try_flock_lock; then
    try_mkdir_lock
  fi
else
  try_mkdir_lock
fi

cleanup_lock() {
  if [[ "${LOCK_MODE}" == "flock" ]]; then
    flock -u 9 || true
  elif [[ "${LOCK_MODE}" == "mkdir" ]]; then
    rmdir "${LOCK_DIR}" 2>/dev/null || true
  fi
}
trap cleanup_lock EXIT

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/load-env.sh"
codex_load_env

strict_checks="${STRICT_LOCAL_CHECKS:-0}"
allow_build_only_review="${ALLOW_BUILD_ONLY_REVIEW:-0}"
test_timeout_seconds="${TEST_TIMEOUT_SECONDS:-600}"
review_round="${REVIEW_ROUND:-1}"

local_checks_log="${LOCAL_CHECKS_LOG_PATH:-.tmp-local-checks-round${review_round}.log}"
test_output_file="${TEST_OUTPUT_PATH:-.tmp-test-output-round${review_round}.txt}"
summary_file="${LOCAL_CHECKS_SUMMARY_PATH:-.tmp-local-checks-round${review_round}.summary.json}"

: > "${local_checks_log}"
: > "${test_output_file}"

has_npm_script() {
  local script_name="$1"
  node -e '
    const fs = require("fs");
    try {
      const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
      process.exit(pkg && pkg.scripts && pkg.scripts[process.argv[1]] ? 0 : 1);
    } catch {
      process.exit(1);
    }
  ' "$script_name"
}

run_npm_check() {
  local script_name="$1"
  local output_file="$2"

  if ! has_npm_script "$script_name"; then
    echo "[SKIP] ${script_name} (package.json script not found)"
    {
      echo "=== ${script_name} ==="
      echo "[SKIP] package.json script not found"
    } >> "${output_file}"
    return 2
  fi

  echo "[INFO] Running ${script_name}..."
  if command -v timeout >/dev/null 2>&1; then
    if timeout "${test_timeout_seconds}" npm run "$script_name" >> "${output_file}" 2>&1; then
      echo "[PASS] ${script_name}"
      return 0
    fi
    local exit_code=$?
    if [[ "${exit_code}" -eq 124 ]]; then
      echo "[FAIL] ${script_name} (TIMEOUT after ${test_timeout_seconds}s - avoid watch mode)"
      echo "[TIMEOUT] ${script_name} exceeded ${test_timeout_seconds}s; disable watch mode." >> "${output_file}"
      return 1
    fi
  else
    if npm run "$script_name" >> "${output_file}" 2>&1; then
      echo "[PASS] ${script_name}"
      return 0
    fi
  fi

  echo "[FAIL] ${script_name}"
  return 1
}

set_state_for() {
  local target_var="$1"
  local script_name="$2"
  local output_file="$3"
  local state="skip"
  if run_npm_check "$script_name" "$output_file"; then
    state="pass"
  else
    case $? in
      1) state="fail" ;;
      2) state="skip" ;;
    esac
  fi
  printf -v "${target_var}" "%s" "${state}"
}

echo "[INFO] Running local checks..."
lint_state="skip"
typecheck_state="skip"
test_state="skip"
build_state="skip"

set_state_for lint_state "lint" "${local_checks_log}"
set_state_for typecheck_state "typecheck" "${local_checks_log}"
set_state_for test_state "test" "${test_output_file}"
set_state_for build_state "build" "${local_checks_log}"

{
  echo "=== summary ==="
  echo "lint=${lint_state}"
  echo "typecheck=${typecheck_state}"
  echo "test=${test_state}"
  echo "build=${build_state}"
} >> "${local_checks_log}"

echo "[INFO] Local checks summary: lint=${lint_state} typecheck=${typecheck_state} test=${test_state} build=${build_state}"

if [[ "${strict_checks}" == "1" ]] && [[ "${lint_state}" == "fail" || "${typecheck_state}" == "fail" || "${test_state}" == "fail" || "${build_state}" == "fail" ]]; then
  echo "[ERROR] STRICT_LOCAL_CHECKS=1 and at least one local check failed."
  exit 1
fi

if [[ "${strict_checks}" == "1" ]] && [[ "${typecheck_state}" == "fail" ]]; then
  echo "[ERROR] typecheck failed. Fix type errors before senior review."
  exit 1
fi

if [[ "${strict_checks}" == "1" ]] && [[ "${test_state}" != "pass" && "${build_state}" != "pass" ]]; then
  echo "[ERROR] STRICT_LOCAL_CHECKS=1 requires at least one strong runtime signal: pass \"test\" or pass \"build\"."
  exit 1
fi

if [[ "${strict_checks}" == "1" ]] && [[ "${test_state}" != "pass" ]]; then
  if [[ "${allow_build_only_review}" == "1" && "${build_state}" == "pass" ]]; then
    echo "[WARN] STRICT_LOCAL_CHECKS=1 but ALLOW_BUILD_ONLY_REVIEW=1 enabled; proceeding with build-only evidence."
  else
    echo "[ERROR] STRICT_LOCAL_CHECKS=1 requires a passing test script."
    exit 1
  fi
fi

if [[ "${strict_checks}" != "1" ]]; then
  [[ "${typecheck_state}" == "fail" ]] && echo "[WARN] typecheck failed (non-strict mode)."
  [[ "${typecheck_state}" == "skip" ]] && echo "[WARN] typecheck script missing (non-strict mode)."
  [[ "${test_state}" != "pass" && "${build_state}" != "pass" ]] && echo "[WARN] Neither test nor build passed (non-strict mode)."
fi

if [[ "${review_round}" == "2" && "${typecheck_state}" != "pass" ]]; then
  echo "[ERROR] Round 2 hard gate: typecheck must pass before requesting Gemini review."
  exit 1
fi

if [[ "${review_round}" == "2" && "${test_state}" != "pass" ]]; then
  if [[ "${allow_build_only_review}" == "1" && "${build_state}" == "pass" ]]; then
    echo "[WARN] Round 2 hard gate override: ALLOW_BUILD_ONLY_REVIEW=1 with passing build."
  else
    echo "[ERROR] Round 2 hard gate: test must pass before requesting Gemini review."
    exit 1
  fi
fi

echo "{\"schema_version\":\"1.0\",\"round\":${review_round},\"strict\":${strict_checks},\"allow_build_only_review\":${allow_build_only_review},\"lint\":\"${lint_state}\",\"typecheck\":\"${typecheck_state}\",\"test\":\"${test_state}\",\"build\":\"${build_state}\",\"log\":\"${local_checks_log}\",\"test_output\":\"${test_output_file}\",\"generated_at\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" > "${summary_file}"

echo "[INFO] Local checks artifacts: ${summary_file}, ${local_checks_log}, ${test_output_file}"
