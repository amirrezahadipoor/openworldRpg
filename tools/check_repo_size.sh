#!/usr/bin/env bash
# Hard gate: the repo (working tree + .git) must stay under 120 MB.
# Run locally before big commits and in CI on every push.
set -euo pipefail
cd "$(git rev-parse --show-toplevel 2>/dev/null || echo .)"

LIMIT_MB=120
SIZE_MB=$(du -sm . | cut -f1)

echo "repo size: ${SIZE_MB} MB (limit ${LIMIT_MB} MB)"

# List the 10 heaviest paths to make pruning easy when we're near budget.
echo "--- heaviest paths ---"
du -ah . 2>/dev/null | sort -rh | head -n 10

if [ "$SIZE_MB" -gt "$LIMIT_MB" ]; then
  echo "::error::Repo exceeds the ${LIMIT_MB} MB budget — prune/re-encode before pushing."
  exit 1
fi
echo "size budget OK ✓"
