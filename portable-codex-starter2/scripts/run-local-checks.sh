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
script_started_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
script_start_epoch="$(date +%s)"

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
  local started_epoch
  local finished_epoch

  started_epoch="$(date +%s)"
  RUN_EXIT_CODE="null"
  RUN_TIMED_OUT="false"
  RUN_DURATION_SECONDS=0

  if ! has_npm_script "$script_name"; then
    echo "[SKIP] ${script_name} (package.json script not found)"
    {
      echo "=== ${script_name} ==="
      echo "[SKIP] package.json script not found"
    } >> "${output_file}"
    finished_epoch="$(date +%s)"
    RUN_DURATION_SECONDS="$((finished_epoch - started_epoch))"
    return 2
  fi

  echo "[INFO] Running ${script_name}..."
  if command -v timeout >/dev/null 2>&1; then
    if timeout "${test_timeout_seconds}" npm run "$script_name" >> "${output_file}" 2>&1; then
      finished_epoch="$(date +%s)"
      RUN_DURATION_SECONDS="$((finished_epoch - started_epoch))"
      RUN_EXIT_CODE=0
      echo "[PASS] ${script_name}"
      return 0
    fi
    local exit_code=$?
    finished_epoch="$(date +%s)"
    RUN_DURATION_SECONDS="$((finished_epoch - started_epoch))"
    if [[ "${exit_code}" -eq 124 ]]; then
      RUN_EXIT_CODE=124
      RUN_TIMED_OUT="true"
      echo "[FAIL] ${script_name} (TIMEOUT after ${test_timeout_seconds}s - avoid watch mode)"
      echo "[TIMEOUT] ${script_name} exceeded ${test_timeout_seconds}s; disable watch mode." >> "${output_file}"
      return 1
    fi
    RUN_EXIT_CODE="${exit_code}"
  else
    if npm run "$script_name" >> "${output_file}" 2>&1; then
      finished_epoch="$(date +%s)"
      RUN_DURATION_SECONDS="$((finished_epoch - started_epoch))"
      RUN_EXIT_CODE=0
      echo "[PASS] ${script_name}"
      return 0
    fi
    local exit_code=$?
    finished_epoch="$(date +%s)"
    RUN_DURATION_SECONDS="$((finished_epoch - started_epoch))"
    RUN_EXIT_CODE="${exit_code}"
  fi

  echo "[FAIL] ${script_name}"
  return 1
}

set_state_for() {
  local target_var="$1"
  local exit_code_var="$2"
  local duration_var="$3"
  local timed_out_var="$4"
  local script_name="$5"
  local output_file="$6"
  local state="skip"
  local check_exit_code="null"
  local check_duration_seconds=0
  local check_timed_out="false"
  if run_npm_check "$script_name" "$output_file"; then
    state="pass"
  else
    case $? in
      1) state="fail" ;;
      2) state="skip" ;;
    esac
  fi
  check_exit_code="${RUN_EXIT_CODE}"
  check_duration_seconds="${RUN_DURATION_SECONDS}"
  check_timed_out="${RUN_TIMED_OUT}"
  printf -v "${target_var}" "%s" "${state}"
  printf -v "${exit_code_var}" "%s" "${check_exit_code}"
  printf -v "${duration_var}" "%s" "${check_duration_seconds}"
  printf -v "${timed_out_var}" "%s" "${check_timed_out}"
}

write_summary_artifact() {
  local script_exit_code="$1"
  local finished_epoch
  local total_duration_seconds
  local any_timeout="false"
  finished_epoch="$(date +%s)"
  total_duration_seconds="$((finished_epoch - script_start_epoch))"

  if [[ "${lint_timed_out}" == "true" || "${typecheck_timed_out}" == "true" || "${test_timed_out}" == "true" || "${build_timed_out}" == "true" ]]; then
    any_timeout="true"
  fi

  cat > "${summary_file}" <<JSON
{"schema_version":"1.1","round":${review_round},"strict":${strict_checks},"allow_build_only_review":${allow_build_only_review},"lint":"${lint_state}","typecheck":"${typecheck_state}","test":"${test_state}","build":"${build_state}","log":"${local_checks_log}","test_output":"${test_output_file}","started_at":"${script_started_at}","generated_at":"$(date -u +%Y-%m-%dT%H:%M:%SZ)","duration_seconds":${total_duration_seconds},"exit_code":${script_exit_code},"timed_out":${any_timeout},"checks":{"lint":{"state":"${lint_state}","exit_code":${lint_exit_code},"duration_seconds":${lint_duration_seconds},"timed_out":${lint_timed_out}},"typecheck":{"state":"${typecheck_state}","exit_code":${typecheck_exit_code},"duration_seconds":${typecheck_duration_seconds},"timed_out":${typecheck_timed_out}},"test":{"state":"${test_state}","exit_code":${test_exit_code},"duration_seconds":${test_duration_seconds},"timed_out":${test_timed_out}},"build":{"state":"${build_state}","exit_code":${build_exit_code},"duration_seconds":${build_duration_seconds},"timed_out":${build_timed_out}}}}
JSON
}

handle_exit() {
  local script_exit_code="$?"
  write_summary_artifact "${script_exit_code}"
  cleanup_lock
}

trap handle_exit EXIT

echo "[INFO] Running local checks..."
lint_state="skip"
typecheck_state="skip"
test_state="skip"
build_state="skip"
lint_exit_code="null"
typecheck_exit_code="null"
test_exit_code="null"
build_exit_code="null"
lint_duration_seconds=0
typecheck_duration_seconds=0
test_duration_seconds=0
build_duration_seconds=0
lint_timed_out="false"
typecheck_timed_out="false"
test_timed_out="false"
build_timed_out="false"

set_state_for lint_state lint_exit_code lint_duration_seconds lint_timed_out "lint" "${local_checks_log}"
set_state_for typecheck_state typecheck_exit_code typecheck_duration_seconds typecheck_timed_out "typecheck" "${local_checks_log}"
set_state_for test_state test_exit_code test_duration_seconds test_timed_out "test" "${test_output_file}"
set_state_for build_state build_exit_code build_duration_seconds build_timed_out "build" "${local_checks_log}"

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

echo "[INFO] Local checks artifacts: ${summary_file}, ${local_checks_log}, ${test_output_file}"
