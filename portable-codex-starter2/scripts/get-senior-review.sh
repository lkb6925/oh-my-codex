#!/usr/bin/env bash
set -Eeuo pipefail

strict_checks="${STRICT_LOCAL_CHECKS:-0}"

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

  if ! has_npm_script "$script_name"; then
    echo "[SKIP] ${script_name} (package.json script not found)"
    return 2
  fi

  echo "[INFO] Running ${script_name}..."
  if npm run "$script_name"; then
    echo "[PASS] ${script_name}"
    return 0
  fi

  echo "[FAIL] ${script_name}"
  return 1
}

echo "[INFO] Running local checks..."
lint_state="skip"
if run_npm_check "lint"; then
  lint_state="pass"
else
  case $? in
    1) lint_state="fail" ;;
    2) lint_state="skip" ;;
  esac
fi

typecheck_state="skip"
if run_npm_check "typecheck"; then
  typecheck_state="pass"
else
  case $? in
    1) typecheck_state="fail" ;;
    2) typecheck_state="skip" ;;
  esac
fi

test_state="skip"
if run_npm_check "test"; then
  test_state="pass"
else
  case $? in
    1) test_state="fail" ;;
    2) test_state="skip" ;;
  esac
fi

echo "[INFO] Local checks summary: lint=${lint_state} typecheck=${typecheck_state} test=${test_state}"

if [[ "${strict_checks}" == "1" ]] && [[ "${lint_state}" == "fail" || "${typecheck_state}" == "fail" || "${test_state}" == "fail" ]]; then
  echo "[ERROR] STRICT_LOCAL_CHECKS=1 and at least one local check failed."
  exit 1
fi

if [[ "${strict_checks}" == "1" ]] && [[ "${typecheck_state}" == "skip" || "${test_state}" == "skip" ]]; then
  echo "[ERROR] STRICT_LOCAL_CHECKS=1 requires both typecheck and test scripts."
  echo "[HINT] Add npm scripts for \"typecheck\" and \"test\" (TDD-first recommended), then retry."
  exit 1
fi

echo "[INFO] Requesting Gemini Senior Architect review..."
tmp_output=".tmp-gemini-review.json.tmp"
node scripts/gemini-reviewer.mjs > "${tmp_output}"
mv "${tmp_output}" .tmp-gemini-review.json

echo "[INFO] Review complete. Results saved to .tmp-gemini-review.json"
cat .tmp-gemini-review.json
