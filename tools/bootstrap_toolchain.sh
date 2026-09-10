#!/usr/bin/env bash
# =============================================================================
# OpenWorld RPG — idempotent toolchain bootstrap
# -----------------------------------------------------------------------------
# All heavy tools live in /tmp/rpg-toolchain/ (EPHEMERAL — never in the repo).
# Safe to re-run at the start of every session and every CI job: existing,
# version-verified tools are skipped; broken/missing ones are re-downloaded.
#
# Usage:
#   tools/bootstrap_toolchain.sh                 # editor only (default)
#   tools/bootstrap_toolchain.sh --editor        # Godot editor binary
#   tools/bootstrap_toolchain.sh --templates     # + Android export templates
#   tools/bootstrap_toolchain.sh --authoring     # + Tiled/Pixelorama/LPC/crunch
# Env:
#   TOOLCHAIN_DIR  override install root (default /tmp/rpg-toolchain)
# =============================================================================
set -euo pipefail

ROOT="${TOOLCHAIN_DIR:-/tmp/rpg-toolchain}"
BIN="$ROOT/bin"
DL="$ROOT/downloads"
mkdir -p "$BIN" "$DL"

# ----- Pinned versions (see DECISIONS.md #1) --------------------------------
GODOT_TAG="4.4.1-stable"            # release tag on GitHub
GODOT_VERSION="4.4.1"               # `--version` prefix we verify against
GODOT_TPL_DIR_NAME="4.4.1.stable"   # export-template folder name Godot expects
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"
GODOT_ZIP="Godot_v${GODOT_TAG}_linux.x86_64.zip"
GODOT_TPL="Godot_v${GODOT_TAG}_export_templates.tpz"

TILED_URL="https://github.com/mapeditor/tiled/releases/download/v1.11.2/Tiled-1.11.2_Linux-22.04-x86_64.AppImage"
PIXELORAMA_URL="https://github.com/Orama-Interactive/Pixelorama/releases/download/v1.0.5/Pixelorama-Linux-64bit.zip"
LPC_REPO="https://github.com/LiberatedPixelCup/Universal-LPC-Spritesheet-Character-Generator"
CRUNCH_REPO="https://github.com/ChevyRay/crunch"

log()  { printf '\033[1;34m[bootstrap]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[bootstrap][warn]\033[0m %s\n' "$*" >&2; }

fetch() { # fetch <url> <dest>
  local url="$1" dest="$2"
  if [ -f "$dest" ]; then log "cached: $dest"; return 0; fi
  log "download: $url"
  curl -fL --retry 3 --retry-delay 2 -o "$dest.part" "$url"
  mv "$dest.part" "$dest"
}

ensure_sha_sums() {
  if [ ! -s "$DL/SHA512-SUMS.txt" ]; then
    fetch "$BASE_URL/SHA512-SUMS.txt" "$DL/SHA512-SUMS.txt" || {
      warn "SHA512-SUMS.txt unavailable — skipping checksum verification"
      return 1
    }
  fi
  return 0
}

verify_sha() { # verify_sha <file> <upstream-filename>
  local f="$1" name="$2" expected
  ensure_sha_sums || return 0
  expected=$(awk -v n="$name" '$2 == "*"n || $2 == n {print $1}' "$DL/SHA512-SUMS.txt" | head -n1)
  if [ -z "$expected" ]; then warn "no checksum entry for $name"; return 0; fi
  if ! ( cd "$(dirname "$f")" && echo "$expected  $(basename "$f")" | sha512sum -c - >/dev/null 2>&1 ); then
    warn "checksum MISMATCH for $name — removing corrupted download"
    rm -f "$f"
    return 1
  fi
  log "sha512 ok: $name"
  return 0
}

godot_ok() {
  [ -x "$BIN/godot" ] && "$BIN/godot" --version 2>/dev/null | grep -q "$GODOT_VERSION"
}

install_editor() {
  if godot_ok; then log "godot ${GODOT_VERSION} already present ✓"; return 0; fi
  rm -f "$BIN/godot"
  until fetch "$BASE_URL/$GODOT_ZIP" "$DL/$GODOT_ZIP" && verify_sha "$DL/$GODOT_ZIP" "$GODOT_ZIP"; do :; done
  command -v unzip >/dev/null || { warn "unzip missing"; exit 1; }
  unzip -oq "$DL/$GODOT_ZIP" -d "$BIN"
  # The zip contains Godot_v4.4.1-stable_linux.x86_64 — normalize the name.
  local extracted
  extracted=$(find "$BIN" -maxdepth 1 -name "Godot_v${GODOT_TAG}_linux*" | head -n1)
  [ -n "$extracted" ] && mv -f "$extracted" "$BIN/godot"
  chmod +x "$BIN/godot"
  godot_ok || { warn "godot binary failed self-check after install"; exit 1; }
  log "godot ${GODOT_VERSION} installed ✓"
}

install_templates() {
  local dest="$HOME/.local/share/godot/export_templates/$GODOT_TPL_DIR_NAME"
  if [ -d "$dest" ] && [ -n "$(ls -A "$dest" 2>/dev/null)" ]; then
    log "export templates already present ✓"
    return 0
  fi
  until fetch "$BASE_URL/$GODOT_TPL" "$DL/$GODOT_TPL" && verify_sha "$DL/$GODOT_TPL" "$GODOT_TPL"; do :; done
  local tmp="$ROOT/_tpl"
  rm -rf "$tmp"; mkdir -p "$tmp"
  unzip -q "$DL/$GODOT_TPL" -d "$tmp"
  mkdir -p "$(dirname "$dest")"
  rm -rf "$dest"
  mv "$tmp/templates" "$dest"
  rm -rf "$tmp"
  log "export templates installed to $dest ✓"
}

install_authoring() {
  # Tiled (level authoring) -------------------------------------------------
  if [ ! -x "$BIN/tiled" ]; then
    fetch "$TILED_URL" "$BIN/tiled" && chmod +x "$BIN/tiled" || warn "Tiled download failed (authoring-only, continuing)"
  fi
  # Pixelorama (pixel-art retouch) -------------------------------------------
  if [ ! -d "$ROOT/pixelorama" ]; then
    if fetch "$PIXELORAMA_URL" "$DL/pixelorama.zip"; then
      mkdir -p "$ROOT/pixelorama"
      unzip -q "$DL/pixelorama.zip" -d "$ROOT/pixelorama" || warn "Pixelorama unzip failed"
    else
      warn "Pixelorama download failed (authoring-only, continuing)"
    fi
  fi
  # Universal LPC Spritesheet Character Generator ----------------------------
  if [ ! -d "$ROOT/lpc-generator" ]; then
    git clone --depth 1 "$LPC_REPO" "$ROOT/lpc-generator" || warn "LPC generator clone failed"
  fi
  python3 -c "import PIL" 2>/dev/null || warn "python3 PIL missing — LPC generator needs it (pip install pillow)"
  # crunch atlas packer (fallback: Godot's built-in atlas import) ------------
  if ! ls "$ROOT"/crunch-src/crunch >/dev/null 2>&1; then
    if [ ! -d "$ROOT/crunch-src" ]; then
      git clone --depth 1 "$CRUNCH_REPO" "$ROOT/crunch-src" || true
    fi
    if [ -d "$ROOT/crunch-src" ]; then
      ( cd "$ROOT/crunch-src" && make -j"$(nproc)" ) || warn "crunch build failed — falling back to Godot built-in atlasing"
    fi
  fi
  log "authoring tools done ✓"
}

# ----- arg parsing -----------------------------------------------------------
WANT_EDITOR=0 WANT_TEMPLATES=0 WANT_AUTHORING=0
for arg in "$@"; do
  case "$arg" in
    --editor)     WANT_EDITOR=1 ;;
    --templates)  WANT_TEMPLATES=1 ;;
    --authoring)  WANT_AUTHORING=1 ;;
    -h|--help)    grep '^#' "$0" | head -n 20; exit 0 ;;
    *) warn "unknown flag: $arg" ;;
  esac
done
if [ $# -eq 0 ]; then WANT_EDITOR=1; fi

log "toolchain root: $ROOT"
[ "$WANT_EDITOR" -eq 1 ]    && install_editor
[ "$WANT_TEMPLATES" -eq 1 ] && install_templates
[ "$WANT_AUTHORING" -eq 1 ] && install_authoring

echo "$GODOT_TAG $(date -u +%FT%TZ)" > "$ROOT/.bootstrap_ok"
log "bootstrap complete ✓"
