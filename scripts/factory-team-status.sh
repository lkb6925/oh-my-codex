#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"
ROOT_NAME="$(basename "${ROOT_DIR}")"
TEAM_RUNTIME_ROOT="${FACTORY_TEAM_RUNTIME_ROOT:-${XDG_RUNTIME_DIR:-/tmp}/factory-team}"
RUN_DIR="${TEAM_RUNTIME_ROOT}/${ROOT_NAME}"
META_FILE="${FACTORY_TEAM_META_FILE:-${RUN_DIR}/latest-run.json}"

meta_team_name() {
  local team_name=""
  local repo_path=""
  if [[ -f "${META_FILE}" ]]; then
    team_name="$(node -e '
      const fs = require("fs");
      try {
        const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        process.stdout.write(p.team_name || "");
      } catch {}
    ' "${META_FILE}")"
    repo_path="$(node -e '
      const fs = require("fs");
      try {
        const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        process.stdout.write(p.repo_path || "");
      } catch {}
    ' "${META_FILE}" 2>/dev/null || true)"
  fi
  if [[ -z "${team_name}" && -n "${repo_path}" && -d "${repo_path}/.omx/state/team" ]]; then
    team_name="$(find "${repo_path}/.omx/state/team" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | head -n 1 | xargs -r basename 2>/dev/null || true)"
  fi
  printf '%s' "${team_name}"
}

meta_repo_path() {
  if [[ -f "${META_FILE}" ]]; then
    node -e '
      const fs = require("fs");
      try {
        const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
        process.stdout.write(p.repo_path || "");
      } catch {}
    ' "${META_FILE}"
  fi
}

DEFAULT_TEAM_NAME="$(meta_team_name)"
REPO_PATH="$(meta_repo_path)"
if [[ -n "${REPO_PATH}" && -d "${REPO_PATH}" ]]; then
  cd "${REPO_PATH}"
fi
TEAM_NAME="${1:-${FACTORY_TEAM_SESSION_NAME:-${DEFAULT_TEAM_NAME:-factory-team-${ROOT_NAME}}}}"
JSON_MODE=0
if [[ "${1:-}" == "--json" || "${2:-}" == "--json" ]]; then
  JSON_MODE=1
  if [[ "${1:-}" == "--json" ]]; then
    TEAM_NAME="${FACTORY_TEAM_SESSION_NAME:-${DEFAULT_TEAM_NAME:-factory-team-${ROOT_NAME}}}"
  fi
fi

if ! command -v omx >/dev/null 2>&1; then
  echo "[ERROR] omx is required for factory-team-status." >&2
  exit 1
fi

if [[ "${JSON_MODE}" == "1" ]]; then
  omx team status "${TEAM_NAME}" --json
else
  omx team status "${TEAM_NAME}" --tail-lines "${FACTORY_TEAM_TAIL_LINES:-120}"
fi
