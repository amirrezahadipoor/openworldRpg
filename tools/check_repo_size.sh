#!/usr/bin/env bash
# Hard gate: the repo (working tree + .git) must stay under 120 MB.
# Run locally before big commits and in CI on every push.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

LIMIT_MB=120
SIZE_MB=$(du -sm . | cut -f1)

echo "repo size: ${SIZE_MB} MB (limit ${LIMIT_MB} MB)"

# Second gate: the checkout's parent is the agent workspace, which has its own
# smaller ceiling (100 MB). The generated import cache lives there and is the
# usual thing that pushes it over, so name it when it is the culprit.
WS_ROOT=$(dirname "$(pwd)")
WS_LIMIT_MB=100
WS_SIZE_MB=$(du -sm "$WS_ROOT" 2>/dev/null | cut -f1 || echo 0)
if [ -n "${WS_SIZE_MB:-}" ] && [ "$WS_SIZE_MB" -gt 0 ]; then
  echo "workspace size: ${WS_SIZE_MB} MB (limit ${WS_LIMIT_MB} MB)"
  CACHE_MB=$(du -sm .godot 2>/dev/null | cut -f1 || echo 0)
  if [ "${CACHE_MB:-0}" -gt 0 ]; then
    echo "  generated import cache (.godot): ${CACHE_MB} MB — delete it before measuring; re-import before testing"
  fi
  if [ "$WS_SIZE_MB" -gt "$WS_LIMIT_MB" ]; then
    echo "::error::Workspace exceeds the ${WS_LIMIT_MB} MB ceiling — move non-essential files out of the workspace."
    exit 1
  fi
fi

# List the 10 heaviest paths to make pruning easy when we're near budget.
# (|| true: head exits early -> SIGPIPE in sort must not trip pipefail.)
echo "--- heaviest paths ---"
{ du -ah . 2>/dev/null | sort -rh | head -n 10; } || true

if [ "$SIZE_MB" -gt "$LIMIT_MB" ]; then
  echo "::error::Repo exceeds the ${LIMIT_MB} MB budget — prune/re-encode before pushing."
  exit 1
fi
echo "size budget OK ✓"
