#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/load-env.sh"
codex_load_env

round_arg="${1:-}"
round="${round_arg:-${SENIOR_REVIEW_ROUND:-1}}"
if [[ ! "${round}" =~ ^[12]$ ]]; then
  echo "[ERROR] SENIOR_REVIEW_ROUND must be 1 or 2. Max 2 rounds allowed."
  exit 1
fi

local_checks_log=".tmp-local-checks-round${round}.log"
test_output_file=".tmp-test-output-round${round}.txt"
summary_file=".tmp-local-checks-round${round}.summary.json"
review_output_file=".tmp-gemini-review-round${round}.json"

export REVIEW_ROUND="${round}"
export LOCAL_CHECKS_LOG_PATH="${local_checks_log}"
export TEST_OUTPUT_PATH="${test_output_file}"
export LOCAL_CHECKS_SUMMARY_PATH="${summary_file}"
export GEMINI_TEST_OUTPUT_PATH="${test_output_file}"
export GEMINI_LOCAL_CHECKS_PATH="${local_checks_log}"

bash scripts/run-local-checks.sh

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
