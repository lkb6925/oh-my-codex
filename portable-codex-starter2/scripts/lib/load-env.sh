#!/usr/bin/env bash
# Shared env loader for starter scripts.
# Safe to source multiple times.

codex_load_env() {
  local env_file="${ENV_FILE:-}"
  local require_explicit="${REQUIRE_EXPLICIT_ENV_FILE:-0}"
  local allow_override="${CODEX_ENV_OVERRIDE:-0}"
  local hermes_home="${HERMES_HOME:-$HOME/.hermes}"
  local hermes_env_file="${HERMES_ENV_FILE:-${hermes_home}/.env}"
  local -a env_files=()

  if [[ -z "${env_file}" ]] && [[ "${CI:-}" == "true" || "${require_explicit}" == "1" ]]; then
    echo "[ERROR] ENV_FILE must be explicitly set in CI/production mode." >&2
    return 1
  fi

  if [[ -n "${env_file}" ]]; then
    env_files+=("${env_file}")
  else
    if [[ -f ".env.local" ]]; then
      env_files+=(".env.local")
    elif [[ -f ".env" ]]; then
      env_files+=(".env")
    fi
  fi

  if [[ -f "${hermes_env_file}" ]]; then
    local first_env_file="${env_files[0]:-}"
    if [[ "${hermes_env_file}" != "${first_env_file}" ]]; then
      env_files+=("${hermes_env_file}")
    fi
  fi

  if [[ "${#env_files[@]}" -eq 0 ]]; then
    return 0
  fi

  load_env_file() {
    local file="$1"
    if [[ ! -f "${file}" ]]; then
      if [[ "${file}" == "${env_file}" && -n "${env_file}" ]]; then
        echo "[ERROR] ENV_FILE is set but file does not exist: ${file}" >&2
        return 1
      fi
      return 0
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
    done < "${file}"

    declare -A existing_values=()
    if [[ "${allow_override}" != "1" ]]; then
      for key in "${candidate_keys[@]}"; do
        if [[ -v "${key}" ]]; then
          existing_values["${key}"]="${!key}"
        fi
      done
    fi

    while IFS= read -r line || [[ -n "${line}" ]]; do
      line="${line#"${line%%[![:space:]]*}"}"
      [[ -z "${line}" || "${line}" == \#* ]] && continue

      local key=""
      local value_expr=""
      if [[ "${line}" =~ ^export[[:space:]]+([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value_expr="${BASH_REMATCH[2]}"
      elif [[ "${line}" =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        key="${BASH_REMATCH[1]}"
        value_expr="${BASH_REMATCH[2]}"
      else
        continue
      fi

      raw_value="${value_expr}"
      raw_value="${raw_value#"${raw_value%%[![:space:]]*}"}"
      raw_value="${raw_value%"${raw_value##*[![:space:]]}"}"
      if [[ ${#raw_value} -ge 2 && "${raw_value:0:1}" == '"' && "${raw_value: -1}" == '"' ]]; then
        raw_value="${raw_value:1:-1}"
      elif [[ ${#raw_value} -ge 2 && "${raw_value:0:1}" == "'" && "${raw_value: -1}" == "'" ]]; then
        raw_value="${raw_value:1:-1}"
      fi
      printf -v "${key}" '%s' "${raw_value}"
      export "${key}"
    done < "${file}"

    if [[ "${allow_override}" != "1" ]]; then
      for key in "${!existing_values[@]}"; do
        export "${key}=${existing_values[$key]}"
      done
      if [[ "${#existing_values[@]}" -gt 0 ]]; then
        echo "[INFO] Preserved ${#existing_values[@]} pre-existing env vars (set CODEX_ENV_OVERRIDE=1 to allow overwrite)."
      fi
    fi

    export CODEX_LOADED_ENV_FILE="${file}"
    echo "[INFO] Loaded environment file: ${file}"
  }

  for file in "${env_files[@]}"; do
    load_env_file "${file}" || return 1
  done

  if [[ -z "${GEMINI_API_KEY:-}" && -n "${GOOGLE_API_KEY:-}" ]]; then
    export GEMINI_API_KEY="${GOOGLE_API_KEY}"
    echo "[INFO] Mirrored GOOGLE_API_KEY into GEMINI_API_KEY for Gemini senior-review compatibility."
  elif [[ -z "${GOOGLE_API_KEY:-}" && -n "${GEMINI_API_KEY:-}" ]]; then
    export GOOGLE_API_KEY="${GEMINI_API_KEY}"
    echo "[INFO] Mirrored GEMINI_API_KEY into GOOGLE_API_KEY for Gemini compatibility."
  fi

  return 0
}
