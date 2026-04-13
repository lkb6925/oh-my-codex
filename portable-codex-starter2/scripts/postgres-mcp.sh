#!/usr/bin/env bash
set -Eeuo pipefail

if [[ -z "${POSTGRES_READONLY_URL:-}" ]]; then
  echo "[ERROR] POSTGRES_READONLY_URL is not set." >&2
  echo "[HINT] Export a read-only DSN, then retry." >&2
  exit 1
fi

exec npx -y @modelcontextprotocol/server-postgres "${POSTGRES_READONLY_URL}"
