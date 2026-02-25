#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Fetch dependencies and build the project (caches compiled artifacts)
cargo fetch
cargo build
