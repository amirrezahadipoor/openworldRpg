#!/usr/bin/env python3
"""Pastes generated idle-only frames into the composed LPC character sheets (H5.5).

Why this exists
---------------
An enemy that holds IDLE for 18-32 s (H5.1) used to stand on two 4 fps breathing
frames, i.e. it read as a statue with a twitch. The LPC layer library that the
rest of the sprites are composed from only ships those two idle frames, so more
idle art has to come from the image generator.

Input: `assets/lpc/_idle_src/<sheet>.png` — one generated sheet per character on
the magenta chroma screen the art pipeline keys against, laid out as a grid of
eight poses: four columns in LPC's own direction order (n, w, s, e) and two rows
(weight shifted onto one leg, then a look-around pose with the head turned).

Output: idle columns 2 and 3 of every direction row of `assets/lpc/<sheet>.png`
are filled with those poses, so the idle block becomes four frames:

    column  0      1       2        3
            base   breath  shift    look-around
    loop    0      2       1        3        (IDLE_LOOP in scripts/enemies/enemy.gd)

The pasted frames are not dropped in as-is. Each pose is

  * keyed off the chroma screen (with a despill pass, the same way the UI icons
    in tools/make_ui_icons.py are),
  * cut out by empty-projection runs, so a pose is never mixed with its
    neighbour even if the generator spaced them unevenly,
  * mirrored back if the generator drew a side profile facing the wrong way
    (silhouette IoU against the frame the sheet already has for that direction),
  * scaled uniformly to the height of that same reference frame and pasted onto
    its baseline and horizontal centre, so an idle frame cannot float, sink or
    change size between frames,
  * palette-snapped to the colours of the reference frame, so the generated art
    inherits the composed sheet's palette instead of arriving with its own.

Files that were never patched are simply not in `assets/lpc/idle_frames.json`,
and the runtime falls back to the sheet's own two-frame idle for them.

Usage
-----
    python3 tools/make_idle_frames.py                 # patch every source
    python3 tools/make_idle_frames.py enemy_wolf ...  # patch named sheets
    python3 tools/make_idle_frames.py --check         # verify, exit 1 on problems

Re-run tools/lpc_compose.py first if the sheet itself was recomposed (that
overwrites the idle columns); `lpc_compose.py` calls `patch_sheet()` itself when
a source exists, so in practice `python3 tools/lpc_compose.py` is enough.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SHEET_DIR = os.path.join(ROOT, "assets", "lpc")
SRC_DIR = os.path.join(SHEET_DIR, "_idle_src")
MANIFEST = os.path.join(SHEET_DIR, "idle_frames.json")

FRAME = 64
COLS = 13
ROWS = 20
DIRS = ["n", "w", "s", "e"]          # LPC row order inside an animation block
IDLE_BLOCK_ROW = 0                   # block 0 of the composed sheet
FIRST_EXTRA_COL = 2                  # columns 0 and 1 are the sheet's own frames
EXTRA_COLS = [2, 3]
POSE_ROWS = ["shift", "look"]
KEY_TOLERANCE = 96
ALPHA_CUTOFF = 120
# Below this mean per-channel difference a "new" idle frame is really frame 0.
MIN_FRAME_DIFFERENCE = 4.0

EXIT_OK, EXIT_PROBLEM = 0, 1


# --- chroma key -------------------------------------------------------------

def key_out(img: Image.Image) -> Image.Image:
    """Drop the magenta screen and its soft pink fringe (see make_ui_icons.py)."""
    arr = np.asarray(img.convert("RGBA"), dtype=np.int16)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    near_screen = ((np.abs(r - 255) < KEY_TOLERANCE)
                   & (np.abs(g - 0) < KEY_TOLERANCE)
                   & (np.abs(b - 255) < KEY_TOLERANCE))
    fringed = (r > 120) & (b > 110) & (g < 110) & ((r + b) > (2.1 * g).astype(np.int16))
    cut = near_screen | fringed
    out = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    out[cut] = (0, 0, 0, 0)
    # Despill: nothing in these palettes is purple, so red-blue dominance at a
    # surviving pixel is still screen bleed from the antialiased edge.
    rr, gg, bb, aa = (out[..., 0].astype(np.int16), out[..., 1].astype(np.int16),
                      out[..., 2].astype(np.int16), out[..., 3])
    spill = (aa > 0) & (rr > 100) & (bb > 100) & (gg < 0.55 * np.minimum(rr, bb))
    out[spill] = (0, 0, 0, 0)
    return Image.fromarray(out, "RGBA")


# --- cutting the generated grid into poses ----------------------------------

def _runs(occupied: np.ndarray, min_size: int = 4) -> list:
    """Group an occupied/empty projection into (start, end) runs of occupied."""
    runs = []
    start = None
    for i, filled in enumerate(occupied):
        if filled and start is None:
            start = i
        elif not filled and start is not None:
            if i - start >= min_size:
                runs.append((start, i))
            start = None
    if start is not None and len(occupied) - start >= min_size:
        runs.append((start, len(occupied)))
    return runs


def split_poses(img: Image.Image) -> dict:
    """Cut eight poses out by empty-projection runs; returns {(dir, pose): box}."""
    alpha = np.asarray(img.getchannel("A"), dtype=np.uint8) > 0
    col_runs = _runs(alpha.any(axis=0).tolist())
    # Drop slivers (stray specks) — a column of a real pose is always wide.
    col_runs = [r for r in col_runs if r[1] - r[0] >= 8]
    if len(col_runs) != len(DIRS):
        raise ValueError("expected %d pose columns, found %d %s"
                         % (len(DIRS), len(col_runs), col_runs))
    boxes = {}
    for d_i, (x0, x1) in enumerate(col_runs):
        band = alpha[:, x0:x1]
        row_runs = [r for r in _runs(band.any(axis=1).tolist()) if r[1] - r[0] >= 8]
        if len(row_runs) != len(POSE_ROWS):
            raise ValueError("column %s: expected %d poses, found %d %s"
                             % (DIRS[d_i], len(POSE_ROWS), len(row_runs), row_runs))
        for p_i, (y0, y1) in enumerate(row_runs):
            sub = band[y0:y1, :]                 # band is already column-cropped
            ys, xs = np.nonzero(sub)
            boxes[(DIRS[d_i], POSE_ROWS[p_i])] = (
                x0 + int(xs.min()), y0 + int(ys.min()),
                x0 + int(xs.max()) + 1, y0 + int(ys.max()) + 1)
    return boxes


# --- pasting one pose into a sheet cell -------------------------------------

def _frame_rgba(sheet: Image.Image, row: int, col: int) -> Image.Image:
    x, y = col * FRAME, row * FRAME
    return sheet.crop((x, y, x + FRAME, y + FRAME))


def _palette(*frames: Image.Image) -> np.ndarray:
    cols = []
    for f in frames:
        arr = np.asarray(f, dtype=np.uint8).reshape(-1, 4)
        cols.append(arr[arr[:, 3] > ALPHA_CUTOFF][:, :3])
    return np.unique(np.concatenate(cols), axis=0).astype(np.int16)


def _snap_to_palette(rgb: np.ndarray, palette: np.ndarray) -> np.ndarray:
    """Nearest-colour match per pixel, against the target frame's own palette."""
    px = rgb.astype(np.int32)
    best = np.zeros_like(px)
    step = 4096
    for i in range(0, len(px), step):
        chunk = px[i:i + step]
        dist = ((chunk[:, None, :] - palette[None, :, :].astype(np.int32)) ** 2).sum(-1)
        best[i:i + step] = palette[dist.argmin(axis=1)].astype(np.int32)
    return best.astype(np.uint8)


def _resize_mask(mask: np.ndarray, size) -> np.ndarray:
    im = Image.fromarray((mask * 255).astype(np.uint8), "L").resize(size, Image.NEAREST)
    return np.asarray(im, dtype=np.uint8) > 127


def _iou(a: np.ndarray, b: np.ndarray) -> float:
    union = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum()) / float(union) if union else 0.0


def normalise_pose(pose: Image.Image, ref: Image.Image) -> Image.Image:
    """Scale a generated pose to the reference frame's build and palette."""
    arr = np.asarray(pose, dtype=np.uint8).copy()
    arr[arr[..., 3] < ALPHA_CUTOFF] = (0, 0, 0, 0)
    pose = Image.fromarray(arr, "RGBA")

    ref_mask = np.asarray(ref.getchannel("A"), dtype=np.uint8) > ALPHA_CUTOFF
    ref_box = ref.getbbox() or (0, 0, FRAME, FRAME)
    ref_mask = ref_mask[ref_box[1]:ref_box[3], ref_box[0]:ref_box[2]]
    size = (ref_box[2] - ref_box[0], ref_box[3] - ref_box[1])

    # Side profiles are the ones a generator is most likely to draw mirrored;
    # pick whichever orientation actually matches the silhouette it must join.
    flipped = pose.transpose(Image.FLIP_LEFT_RIGHT)
    score = {}
    for tag, cand in (("as-is", pose), ("flipped", flipped)):
        mask = np.asarray(cand.getchannel("A"), dtype=np.uint8) > ALPHA_CUTOFF
        score[tag] = _iou(_resize_mask(mask, size), ref_mask)
    if score["flipped"] > score["as-is"] + 0.04:
        pose = flipped

    src_box = pose.getbbox()
    if src_box is None:
        raise ValueError("empty pose")
    pose = pose.crop(src_box)
    scale = size[1] / float(pose.height)
    new_size = (max(1, int(round(pose.width * scale))), size[1])
    pose = pose.resize(new_size, Image.LANCZOS)
    arr = np.asarray(pose, dtype=np.uint8).copy()
    arr[arr[..., 3] < ALPHA_CUTOFF] = (0, 0, 0, 0)
    palette = _palette(ref)
    solid = arr[..., 3] > ALPHA_CUTOFF
    if solid.any():
        arr[..., :3][solid] = _snap_to_palette(arr[..., :3][solid], palette)
    arr[..., 3] = np.where(solid, 255, 0).astype(np.uint8)
    return Image.fromarray(arr, "RGBA")


def paste_pose(sheet: Image.Image, row: int, col: int, pose: Image.Image,
               ref: Image.Image) -> None:
    """Paste onto the reference frame's baseline and horizontal centre."""
    ref_box = ref.getbbox() or (0, 0, FRAME, FRAME)
    ref_cx = (ref_box[0] + ref_box[2]) / 2.0
    dx = int(round(ref_cx - pose.width / 2.0))
    dy = int(ref_box[3] - pose.height)
    dx = max(0, min(FRAME - pose.width, dx))            # never spill the cell
    dy = max(0, min(FRAME - pose.height, dy))
    cell = (col * FRAME, row * FRAME)
    sheet.paste((0, 0, 0, 0), (cell[0], cell[1], cell[0] + FRAME, cell[1] + FRAME))
    sheet.paste(pose, (cell[0] + dx, cell[1] + dy), pose)


# --- sheet-level driver -----------------------------------------------------

def patch_sheet(name: str) -> dict:
    """Patch one sheet from its source art. Returns the manifest entry."""
    src_path = os.path.join(SRC_DIR, name + ".png")
    sheet_path = os.path.join(SHEET_DIR, name + ".png")
    if not os.path.exists(src_path):
        raise FileNotFoundError("no idle source for %s (expected %s)" % (name, src_path))
    src = key_out(Image.open(src_path))
    poses = split_poses(src)
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.size != (COLS * FRAME, ROWS * FRAME):
        raise ValueError("%s: unexpected sheet size %s" % (name, sheet.size))
    for d_i, d in enumerate(DIRS):
        row = IDLE_BLOCK_ROW * 4 + d_i
        ref = _frame_rgba(sheet, row, 0)
        for p_i, pose_id in enumerate(POSE_ROWS):
            pose = normalise_pose(src.crop(poses[(d, pose_id)]), ref)
            paste_pose(sheet, row, FIRST_EXTRA_COL + p_i, pose, ref)
    sheet.save(sheet_path, optimize=True)
    return name


def _sources() -> list:
    if not os.path.isdir(SRC_DIR):
        return []
    return sorted(f[:-4] for f in os.listdir(SRC_DIR) if f.endswith(".png"))


def _load_manifest() -> dict:
    if not os.path.exists(MANIFEST):
        return {}
    with open(MANIFEST, "r", encoding="utf-8") as fh:
        return json.load(fh)


def _save_manifest(entries: dict) -> None:
    with open(MANIFEST, "w", encoding="utf-8") as fh:
        json.dump(entries, fh, indent=1, sort_keys=True)
        fh.write("\n")


def _frame_difference(a: np.ndarray, b: np.ndarray) -> float:
    """Mean per-channel difference over the union of two frames' silhouettes.

    Catches the failure that matters: a "new" idle frame that is really the old
    frame again (the two-frame idle would then just play faster).
    """
    solid = (a[..., 3] > ALPHA_CUTOFF) | (b[..., 3] > ALPHA_CUTOFF)
    if not solid.any():
        return 0.0
    return float(np.abs(a[..., :3][solid].astype(np.int16)
                        - b[..., :3][solid].astype(np.int16)).mean())


def check() -> bool:
    """Verify every patched sheet really carries four distinct idle frames."""
    manifest = _load_manifest()
    problems = []
    if not manifest:
        problems.append("manifest %s is empty" % os.path.relpath(MANIFEST, ROOT))
    for name, frames in sorted(manifest.items()):
        path = os.path.join(SHEET_DIR, name + ".png")
        if not os.path.exists(path):
            problems.append("%s: listed in the manifest but the sheet is gone" % name)
            continue
        sheet = Image.open(path).convert("RGBA")
        if sheet.size != (COLS * FRAME, ROWS * FRAME):
            problems.append("%s: sheet size %s" % (name, sheet.size))
            continue
        for d_i, d in enumerate(DIRS):
            row = IDLE_BLOCK_ROW * 4 + d_i
            ref = np.asarray(_frame_rgba(sheet, row, 0), dtype=np.uint8)
            if not (ref[..., 3] > ALPHA_CUTOFF).any():
                problems.append("%s/%s: the sheet's own idle frame is empty" % (name, d))
                continue
            for col in range(1, int(frames)):
                cell = _frame_rgba(sheet, row, col)
                if cell.getbbox() is None:
                    problems.append("%s/%s: idle frame %d is empty" % (name, d, col))
                    continue
                arr = np.asarray(cell, dtype=np.uint8)
                # A pasted frame that came out as a copy of frame 0 (a failed key,
                # a mis-cut pose) would look like the old two-frame idle at 4 fps.
                diff = _frame_difference(ref, arr)
                if diff < MIN_FRAME_DIFFERENCE:
                    problems.append("%s/%s: idle frame %d is a copy of frame 0 (%.1f)"
                                    % (name, d, col, diff))
            if _frame_rgba(sheet, row, int(frames)).getbbox() is not None:
                problems.append("%s/%s: idle block overflows into column %d"
                                % (name, d, int(frames)))
    for p in problems:
        print("  PROBLEM: %s" % p)
    if problems:
        print("IDLE ART: FAILED (%d problems)" % len(problems))
        return False
    total = sum(int(v) for v in manifest.values())
    print("IDLE ART: PASS (%d sheets, %d idle frames each)" % (len(manifest),
                                                              total // max(1, len(manifest))))
    return True


def main() -> None:
    args = [a for a in sys.argv[1:] if a != "--check"]
    if "--check" in sys.argv[1:]:
        sys.exit(EXIT_OK if check() else EXIT_PROBLEM)

    want = args or _sources()
    if not want:
        sys.exit("no idle sources in %s" % os.path.relpath(SRC_DIR, ROOT))
    manifest = _load_manifest()
    failed = []
    for name in want:
        try:
            patch_sheet(name)
        except (FileNotFoundError, ValueError) as exc:
            failed.append("%s: %s" % (name, exc))
            continue
        manifest[name] = 4
        print("  %-24s idle frames patched (shift + look-around x 4 directions)" % name)
    _save_manifest(manifest)
    if failed:
        for f in failed:
            print("  PROBLEM: %s" % f)
        sys.exit(EXIT_PROBLEM)


if __name__ == "__main__":
    main()
