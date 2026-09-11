#!/usr/bin/env bash
# Park / restore the generated pose sources.
#
# `_attack_src/`, `_idle_src/` and `_cast_src/` hold the image generator's raw
# output — the inputs `tools/make_idle_frames.py` pastes into the composed sheets.
# They are never read at runtime, no check needs them, and at ~7 MB they do not
# fit the workspace size budget next to the sheets they already produced. Park
# them in /tmp between batches, restore them before a re-patch.
#
# The same is true of the *other* generator inputs: the UI icon sources, the
# banner source, the pickup-art sources and the vendored LPC layer sheets. None of
# them are read at runtime and no gate needs them — only the art tools do, and only
# while re-patching. They are parked the same way, under their own paths, and CI
# never touches them (verified: no workflow references them).
#
#   tools/pose_sources.sh park      # move the sources out of the repo
#   tools/pose_sources.sh restore   # bring them back (from /tmp, or from the last
#                                   # commit that carried them)
#
# Sources that were never committed at all are still recoverable while they are
# unreferenced — they sit in the object store until a gc prunes them:
#   git fsck --no-reflogs --unreachable | grep blob     # candidate ids
#   git cat-file blob <id> > /tmp/ws-scratch/pose-sources/idle/npc_x.png
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
PARK="${POSE_PARK:-/tmp/ws-scratch/pose-sources}"
DIRS=(assets/lpc/_attack_src assets/lpc/_idle_src assets/lpc/_cast_src)
# Generator inputs parked as a group, keeping their repo-relative paths so restore
# is a mirror image of park.
EXTRA_DIRS=(
  assets/ui/_src
  assets/ui/icons/_src
  assets/world/_src
  assets/source/lpc_layers
)

case "${1:-}" in
  park)
    for d in "${DIRS[@]}"; do
      kind="$(basename "$d" | sed 's/^_//; s/_src$//')"
      mkdir -p "$PARK/$kind"
      find "$d" -maxdepth 1 -name '*.png' -exec mv {} "$PARK/$kind/" \;
    done
    for d in "${EXTRA_DIRS[@]}"; do
      [ -d "$d" ] || continue
      # Recursive: lpc_layers is a tree of subdirectories, and the paths are kept
      # so restore is a mirror image of park.
      find "$d" -type f -name '*.png' | while read -r f; do
        rel="${f#"$d"/}"
        mkdir -p "$PARK/$d/$(dirname "$rel")"
        mv "$f" "$PARK/$d/$rel"
      done
      find "$d" -type d -empty -delete 2>/dev/null || true
      mkdir -p "$d"
    done
    echo "sources parked in $PARK ($(du -sm "$PARK" | cut -f1) MB)"
    ;;
  restore)
    missing=""
    for d in "${DIRS[@]}"; do
      kind="$(basename "$d" | sed 's/^_//; s/_src$//')"
      if [ -d "$PARK/$kind" ]; then
        find "$PARK/$kind" -maxdepth 1 -name '*.png' -exec mv {} "$d/" \;
      fi
      [ -n "$(find "$d" -maxdepth 1 -name '*.png' -print -quit)" ] || missing="$missing $d"
    done
    if [ -n "$missing" ]; then
      sha="$(git log --diff-filter=D --max-count=1 --format=%H -- assets/lpc/_attack_src | head -1)"
      if [ -n "$sha" ]; then
        echo "not in $PARK; restoring from the commit before $sha"
        # Write the files straight into the worktree: `git checkout -- <dirs>`
        # would stage them again and undo the point of parking them.
        git ls-tree -r --name-only "$sha^" -- "${DIRS[@]}" | while read -r f; do
          case "$f" in *.png) git show "$sha^:$f" > "$f" ;; esac
        done
      else
        echo "nothing to restore from — regenerate the art instead" >&2
        exit 1
      fi
    fi
    for d in "${EXTRA_DIRS[@]}"; do
      if [ -d "$PARK/$d" ]; then
        find "$PARK/$d" -type f -name '*.png' | while read -r f; do
          rel="${f#"$PARK/$d"/}"
          mkdir -p "$d/$(dirname "$rel")"
          mv "$f" "$d/$rel"
        done
      fi
      if [ -z "$(find "$d" -maxdepth 1 -name '*.png' -print -quit 2>/dev/null)" ]; then
        # Not in the park: take it back out of history (it was committed, then
        # parked - the blobs are still in the objects the commits point at).
        sha="$(git log --diff-filter=D --max-count=1 --format=%H -- "$d" | head -1)"
        if [ -n "$sha" ]; then
          echo "$d: restoring from the commit before $sha"
          git ls-tree -r --name-only "$sha^" -- "$d" | while read -r f; do
            case "$f" in *.png) mkdir -p "$(dirname "$f")"; git show "$sha^:$f" > "$f" ;; esac
          done
        fi
      fi
    done
    for d in "${DIRS[@]}" "${EXTRA_DIRS[@]}"; do
      printf '%-28s %s source(s)\n' "$d" "$(find "$d" -maxdepth 1 -name '*.png' 2>/dev/null | wc -l)"
    done
    ;;
  *)
    echo "usage: tools/pose_sources.sh {park|restore}" >&2
    exit 2
    ;;
esac
