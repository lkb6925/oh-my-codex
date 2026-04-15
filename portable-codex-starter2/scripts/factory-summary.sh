#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
latest_checks="$(ls -1t .tmp-local-checks-round*.summary.json 2>/dev/null | head -n 1 || true)"
latest_review="$(ls -1t .tmp-gemini-review-round*.json 2>/dev/null | head -n 1 || true)"
latest_log="$(ls -1t "${RUN_DIR}"/run-*.log 2>/dev/null | head -n 1 || true)"
jq_available=0
if command -v jq >/dev/null 2>&1; then
  jq_available=1
fi

branch="$(git branch --show-current 2>/dev/null || echo unknown)"
commit="$(git log --oneline -n 1 2>/dev/null | head -n 1)"
state="clean"
[[ -n "$(git status --short 2>/dev/null)" ]] && state="dirty"

echo "# Factory Summary"
echo ""
echo "- Branch: ${branch}"
echo "- Commit: ${commit}"
echo "- Working tree: ${state}"

if [[ -n "${latest_checks}" ]]; then
  echo "- Latest checks: ${latest_checks}"
  if [[ "${jq_available}" == "1" && -f "${latest_checks}" ]]; then
    if jq -e . "${latest_checks}" >/dev/null 2>&1; then
      echo "  - lint: $(jq -r '.lint // \"unknown\"' "${latest_checks}")"
      echo "  - typecheck: $(jq -r '.typecheck // \"unknown\"' "${latest_checks}")"
      echo "  - test: $(jq -r '.test // \"unknown\"' "${latest_checks}")"
      echo "  - build: $(jq -r '.build // \"unknown\"' "${latest_checks}")"
    else
      echo "  - [warn] checks summary JSON is malformed; raw file retained."
    fi
  else
    echo "  - [warn] jq missing or checks summary file unavailable; skipping structured checks summary."
  fi
else
  echo "- Latest checks: none"
fi

if [[ -n "${latest_review}" ]]; then
  echo "- Latest review: ${latest_review}"
  if [[ "${jq_available}" == "1" && -f "${latest_review}" ]]; then
    if jq -e . "${latest_review}" >/dev/null 2>&1; then
      echo "  - verdict: $(jq -r '.verdict // \"unknown\"' "${latest_review}")"
      echo "  - issue_count: $(jq -r '(.issues // []) | length' "${latest_review}")"
    else
      echo "  - [warn] review JSON is malformed; raw file retained."
    fi
  else
    echo "  - [warn] jq missing or review file unavailable; skipping structured review summary."
  fi
else
  echo "- Latest review: none"
fi

if [[ -n "${latest_log}" ]]; then
  echo ""
  echo "## Run log tail (${latest_log})"
  if [[ -f "${latest_log}" ]]; then
    tail -n 40 "${latest_log}"
  else
    echo "[warn] run log file is missing."
  fi
else
  echo ""
  echo "## Run log tail"
  echo "[info] no run logs found in ${RUN_DIR}."
fi

if [[ "${jq_available}" != "1" ]]; then
  echo ""
  echo "[warn] jq not found; structured JSON fields could not be parsed."
fi
