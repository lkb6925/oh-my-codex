#!/usr/bin/env bash
# Shared env loader for starter scripts.
# Safe to source multiple times.

codex_load_env() {
  local env_file="${ENV_FILE:-}"
  local require_explicit="${REQUIRE_EXPLICIT_ENV_FILE:-0}"
  local allow_override="${CODEX_ENV_OVERRIDE:-0}"

  if [[ -z "${env_file}" ]] && [[ "${CI:-}" == "true" || "${require_explicit}" == "1" ]]; then
    echo "[ERROR] ENV_FILE must be explicitly set in CI/production mode." >&2
    return 1
  fi

  if [[ -z "${env_file}" ]]; then
    if [[ -f ".env.local" ]]; then
      env_file=".env.local"
    elif [[ -f ".env" ]]; then
      env_file=".env"
    fi
  fi

  if [[ -n "${env_file}" ]]; then
    if [[ ! -f "${env_file}" ]]; then
      echo "[ERROR] ENV_FILE is set but file does not exist: ${env_file}" >&2
      return 1
    fi

    declare -a candidate_keys=()
    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -z "${line}" || "${line}" == \#* ]] && continue
      if [[ "${line}" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        candidate_keys+=("${BASH_REMATCH[1]}")
      elif [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)= ]]; then
        candidate_keys+=("${BASH_REMATCH[1]}")
      fi
    done < "${env_file}"

    declare -A existing_values=()
    if [[ "${allow_override}" != "1" ]]; then
      for key in "${candidate_keys[@]}"; do
        if [[ -v "${key}" ]]; then
          existing_values["${key}"]="${!key}"
        fi
      done
    fi

    # shellcheck disable=SC1090
    set -a
    source "${env_file}"
    set +a

    if [[ "${allow_override}" != "1" ]]; then
      for key in "${!existing_values[@]}"; do
        export "${key}=${existing_values[$key]}"
      done
      if [[ "${#existing_values[@]}" -gt 0 ]]; then
        echo "[INFO] Preserved ${#existing_values[@]} pre-existing env vars (set CODEX_ENV_OVERRIDE=1 to allow overwrite)."
      fi
    fi

    export CODEX_LOADED_ENV_FILE="${env_file}"
    echo "[INFO] Loaded environment file: ${env_file}"
  fi

  return 0
}
