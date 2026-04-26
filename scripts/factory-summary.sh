#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

RUN_DIR="${FACTORY_RUN_DIR:-.omx/runs}"
LATEST_RUN_META="${RUN_DIR}/latest-run.json"
LATEST_SHUTDOWN="${RUN_DIR}/latest-shutdown.json"
LATEST_CHECKS="$(ls -1t .tmp-local-checks-round*.summary.json 2>/dev/null | head -n 1 || true)"
LATEST_REVIEW="$(ls -1t .tmp-gemini-review-round*.json 2>/dev/null | head -n 1 || true)"
LATEST_LOG="$(ls -1t "${RUN_DIR}"/run-*.log 2>/dev/null | head -n 1 || true)"
VERBOSE="${FACTORY_SUMMARY_VERBOSE:-0}"
JQ_AVAILABLE=0
command -v jq >/dev/null 2>&1 && JQ_AVAILABLE=1

branch="$(git branch --show-current 2>/dev/null || echo unknown)"
commit="$(git log --oneline -n 1 2>/dev/null | head -n 1)"
state="clean"
[[ -n "$(git status --short 2>/dev/null)" ]] && state="dirty"

json_field() {
  local file_path="$1"
  local field_name="$2"
  if [[ ! -f "${file_path}" || "${JQ_AVAILABLE}" != "1" ]]; then
    printf ''
    return
  fi
  jq -r --arg field "${field_name}" 'if has($field) and .[$field] != null then .[$field] else "" end' "${file_path}" 2>/dev/null || true
}

json_array_field() {
  local file_path="$1"
  local field_name="$2"
  if [[ ! -f "${file_path}" || "${JQ_AVAILABLE}" != "1" ]]; then
    printf '[]'
    return
  fi
  jq -c --arg field "${field_name}" 'if has($field) and .[$field] != null and (.[$field] | type) == "array" then .[$field] else [] end' "${file_path}" 2>/dev/null || printf '[]'
}

status_line() {
  local label="$1"
  local value="$2"
  if [[ -n "${value}" ]]; then
    printf '%s=%s' "${label}" "${value}"
  else
    printf '%s=none' "${label}"
  fi
}

checks_line="lint=unknown typecheck=unknown test=unknown build=unknown"
if [[ -n "${LATEST_CHECKS}" && "${JQ_AVAILABLE}" == "1" ]]; then
  if jq -e . "${LATEST_CHECKS}" >/dev/null 2>&1; then
    checks_line="lint=$(jq -r '.lint // "unknown"' "${LATEST_CHECKS}") typecheck=$(jq -r '.typecheck // "unknown"' "${LATEST_CHECKS}") test=$(jq -r '.test // "unknown"' "${LATEST_CHECKS}") build=$(jq -r '.build // "unknown"' "${LATEST_CHECKS}")"
  else
    checks_line="invalid-json"
  fi
elif [[ -z "${LATEST_CHECKS}" ]]; then
  checks_line="none"
fi

review_line="verdict=none issues=0"
if [[ -n "${LATEST_REVIEW}" && "${JQ_AVAILABLE}" == "1" ]]; then
  if jq -e . "${LATEST_REVIEW}" >/dev/null 2>&1; then
    review_line="verdict=$(jq -r '.verdict // "unknown"' "${LATEST_REVIEW}") issues=$(jq -r '(.issues // []) | length' "${LATEST_REVIEW}")"
  else
    review_line="invalid-json"
  fi
fi

run_status="$(json_field "${LATEST_RUN_META}" status)"
run_phase="$(json_field "${LATEST_RUN_META}" phase)"
run_mode="$(json_field "${LATEST_RUN_META}" execution_mode)"
run_agent_alive="$(json_field "${LATEST_RUN_META}" agent_alive)"
run_start_commit="$(json_field "${LATEST_RUN_META}" start_commit)"
run_team="$(json_field "${LATEST_RUN_META}" team_name)"
run_team_spec="$(json_field "${LATEST_RUN_META}" night_team_spec)"
if [[ -z "${run_team_spec}" ]]; then
  run_team_spec="$(json_field "${LATEST_RUN_META}" team_spec)"
fi
run_last_event="$(json_field "${LATEST_RUN_META}" last_event)"
run_last_update_at="$(json_field "${LATEST_RUN_META}" last_update_at)"
shutdown_result="$(json_field "${LATEST_SHUTDOWN}" result)"
shutdown_requested_at="$(json_field "${LATEST_SHUTDOWN}" requested_at)"
shutdown_finished_at="$(json_field "${LATEST_SHUTDOWN}" finished_at)"
shutdown_log="$(json_field "${LATEST_SHUTDOWN}" log_file)"

commits_during_run=""
changed_files_during_run=""
if [[ -n "${run_start_commit}" ]]; then
  commits_during_run="$(git log --oneline --reverse "${run_start_commit}..HEAD" 2>/dev/null || true)"
  changed_files_during_run="$(git diff --name-only "${run_start_commit}..HEAD" 2>/dev/null || true)"
fi

remaining_actions_json="$(json_array_field "${LATEST_RUN_META}" remaining_manual_actions)"
remaining_status_actions=()
if [[ "${remaining_actions_json}" != "[]" ]]; then
  if command -v jq >/dev/null 2>&1; then
    mapfile -t remaining_status_actions < <(printf '%s' "${remaining_actions_json}" | jq -r '.[]')
  elif command -v node >/dev/null 2>&1; then
    mapfile -t remaining_status_actions < <(node -e '
      let raw = "";
      process.stdin.on("data", (chunk) => { raw += chunk; });
      process.stdin.on("end", () => {
        try {
          const parsed = JSON.parse(raw);
          if (Array.isArray(parsed)) {
            for (const item of parsed) {
              process.stdout.write(String(item) + "\n");
            }
          }
        } catch {}
      });
    ' <<< "${remaining_actions_json}")
  fi
fi

if [[ -z "${run_team}" ]]; then
  run_team="factory-team-${ROOT_NAME}"
fi

if [[ -n "${run_start_commit}" ]]; then
  if [[ -n "${commits_during_run}" ]]; then
    commit_block="$(printf '%s\n' "${commits_during_run}" | sed 's/^/- /')"
  else
    commit_block='- none'
  fi
  if [[ -n "${changed_files_during_run}" ]]; then
    changed_files_block="$(printf '%s\n' "${changed_files_during_run}" | sed 's/^/- /')"
  else
    changed_files_block='- none'
  fi
else
  commit_block='- run start commit unavailable'
  changed_files_block='- run start commit unavailable'
fi

printf '# Factory Summary\n'
printf '\n'
printf '## DONE\n'
printf -- '- branch: %s\n' "${branch}"
printf -- '- commit: %s\n' "${commit}"
printf -- '- tree: %s\n' "${state}"
printf -- '- run: status=%s phase=%s mode=%s agent_alive=%s team=%s team_spec=%s last_event=%s last_update_at=%s\n' \
  "${run_status:-unknown}" "${run_phase:-unknown}" "${run_mode:-unknown}" "${run_agent_alive:-unknown}" "${run_team:-unknown}" "${run_team_spec:-unknown}" "${run_last_event:-unknown}" "${run_last_update_at:-unknown}"
printf -- '- commits during run:\n%s\n' "${commit_block}"
printf '\n## KEEP / PRUNE CANDIDATES\n'
printf -- '- files touched during run:\n%s\n' "${changed_files_block}"
printf '\n## NEEDS YOUR DECISION\n'
if [[ "${#remaining_status_actions[@]}" -gt 0 ]]; then
  printf -- '- %s\n' "${remaining_status_actions[*]}"
else
  printf -- '- none\n'
fi
printf '\n## MACHINE / OPERATIONS\n'
printf -- '- checks: %s\n' "${checks_line}"
printf -- '- review: %s\n' "${review_line}"
printf -- '- shutdown: result=%s requested_at=%s finished_at=%s log=%s\n' \
  "${shutdown_result:-none}" "${shutdown_requested_at:-none}" "${shutdown_finished_at:-none}" "${shutdown_log:-none}"

if [[ -n "${LATEST_LOG}" ]]; then
  printf -- '- log: %s\n' "${LATEST_LOG}"
  if [[ "${VERBOSE}" == "1" && -f "${LATEST_LOG}" ]]; then
    printf '\n## log tail (%s)\n' "${LATEST_LOG}"
    tail -n 20 "${LATEST_LOG}"
  fi
else
  printf -- '- log: none\n'
fi
