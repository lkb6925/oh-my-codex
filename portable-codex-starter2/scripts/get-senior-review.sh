#!/usr/bin/env bash
set -Eeuo pipefail

strict_checks="${STRICT_LOCAL_CHECKS:-0}"
test_timeout_seconds="${TEST_TIMEOUT_SECONDS:-600}"
round_arg="${1:-}"
round="${round_arg:-${SENIOR_REVIEW_ROUND:-1}}"
test_output_file=".tmp-test-output-round${round}.txt"
local_checks_log=".tmp-local-checks-round${round}.log"
review_output_file=".tmp-gemini-review-round${round}.json"

env_file="${ENV_FILE:-}"
if [[ -z "${env_file}" ]]; then
  if [[ -f ".env.local" ]]; then
    env_file=".env.local"
  elif [[ -f ".env" ]]; then
    env_file=".env"
  fi
fi

if [[ -n "${env_file}" ]]; then
  # shellcheck disable=SC1091
  set -a
  source "${env_file}"
  set +a
  echo "[INFO] Loaded environment file: ${env_file}"
fi

export GEMINI_TEST_OUTPUT_PATH="${test_output_file}"
export GEMINI_LOCAL_CHECKS_PATH="${local_checks_log}"

if [[ ! "${round}" =~ ^[12]$ ]]; then
  echo "[ERROR] SENIOR_REVIEW_ROUND must be 1 or 2. Max 2 rounds allowed."
  exit 1
fi

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
    timeout_exit_code=$?
    if [[ "${timeout_exit_code}" -eq 124 ]]; then
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

echo "[INFO] Running local checks..."
lint_state="skip"
if run_npm_check "lint" "${local_checks_log}"; then
  lint_state="pass"
else
  case $? in
    1) lint_state="fail" ;;
    2) lint_state="skip" ;;
  esac
fi

typecheck_state="skip"
if run_npm_check "typecheck" "${local_checks_log}"; then
  typecheck_state="pass"
else
  case $? in
    1) typecheck_state="fail" ;;
    2) typecheck_state="skip" ;;
  esac
fi

test_state="skip"
if run_npm_check "test" "${test_output_file}"; then
  test_state="pass"
else
  case $? in
    1) test_state="fail" ;;
    2) test_state="skip" ;;
  esac
fi

build_state="skip"
if run_npm_check "build" "${local_checks_log}"; then
  build_state="pass"
else
  case $? in
    1) build_state="fail" ;;
    2) build_state="skip" ;;
  esac
fi

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
  echo "[HINT] Add a non-watch \"test\" script (recommended) or ensure \"build\" passes."
  exit 1
fi

if [[ "${strict_checks}" != "1" ]]; then
  if [[ "${typecheck_state}" == "fail" ]]; then
    echo "[WARN] typecheck failed (non-strict mode)."
  elif [[ "${typecheck_state}" == "skip" ]]; then
    echo "[WARN] typecheck script missing (non-strict mode)."
  fi

  if [[ "${test_state}" != "pass" && "${build_state}" != "pass" ]]; then
    echo "[WARN] Neither test nor build passed (non-strict mode)."
  fi
fi

echo "[INFO] Requesting Gemini Senior Architect review..."
tmp_output="${review_output_file}.tmp"
node scripts/gemini-reviewer.mjs > "${tmp_output}"
mv "${tmp_output}" "${review_output_file}"
cp "${review_output_file}" .tmp-gemini-review.json

echo "[INFO] Review complete. Results saved to ${review_output_file}"
cat "${review_output_file}"

if [[ "${round}" == "2" ]]; then
  node scripts/review-gate.mjs --file "${review_output_file}" --final
else
  node scripts/review-gate.mjs --file "${review_output_file}"
fi
