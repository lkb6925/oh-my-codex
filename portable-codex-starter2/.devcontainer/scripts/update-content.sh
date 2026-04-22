#!/usr/bin/env bash
set -euo pipefail

if command -v npm >/dev/null 2>&1 && [ -f package-lock.json ]; then
  npm ci
fi

if command -v cargo >/dev/null 2>&1 && [ -f Cargo.toml ]; then
  cargo fetch --locked || cargo fetch
fi
