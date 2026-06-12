#!/bin/bash
set -euo pipefail

# Only needed for Claude Code on the web sessions
if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Perch is intentionally a single-file, no-build demo: nothing to install today.
# When the MVP adds real tooling (package.json etc.), add the install steps here,
# e.g.:  npm install
exit 0
