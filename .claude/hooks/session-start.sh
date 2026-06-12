#!/bin/bash
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then
  # Web sessions: Perch is intentionally a single-file, no-build demo — nothing
  # to install today. When the MVP adds real tooling (package.json etc.), add
  # the install steps here, e.g.:  npm install
  exit 0
fi

# Local sessions: sync the working copy with GitHub so CLAUDE.md and skills
# are always current. Only when it's safe — on main, nothing uncommitted,
# fast-forward only. Anything else: skip silently and let the human decide.
cd "${CLAUDE_PROJECT_DIR:-.}" 2>/dev/null || exit 0
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || exit 0
if [ "$branch" = "main" ] && [ -z "$(git status --porcelain 2>/dev/null)" ]; then
  git pull --ff-only --quiet 2>/dev/null || true
fi
exit 0
