#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -f ".env" ]]; then
  # shellcheck disable=SC1091
  set -a
  source ".env"
  set +a
fi

postgres_mcp_dsn="${POSTGRES_MCP_DSN:-${POSTGRES_READONLY_URL:-}}"

if [[ -z "${postgres_mcp_dsn}" ]]; then
  echo "[ERROR] POSTGRES_MCP_DSN is not set." >&2
  echo "[HINT] Export POSTGRES_MCP_DSN (preferred) or POSTGRES_READONLY_URL (legacy), then retry." >&2
  exit 1
fi

exec npx -y @modelcontextprotocol/server-postgres "${postgres_mcp_dsn}"
