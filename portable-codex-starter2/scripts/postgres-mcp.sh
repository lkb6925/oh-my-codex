#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT_DIR}"

# shellcheck disable=SC1091
source "${ROOT_DIR}/scripts/lib/load-env.sh"
codex_load_env

postgres_mcp_dsn="${POSTGRES_MCP_DSN:-}"

if [[ -z "${postgres_mcp_dsn}" ]]; then
  echo "[ERROR] POSTGRES_MCP_DSN is not set." >&2
  echo "[HINT] Export POSTGRES_MCP_DSN, then retry." >&2
  exit 1
fi

exec npx -y @modelcontextprotocol/server-postgres "${postgres_mcp_dsn}"
