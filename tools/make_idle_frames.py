#!/usr/bin/env python3

"""Pastes generated pose art into the composed LPC sheets (H5.5 idle, H7.2 attack).

Why this exists
---------------
An enemy that holds IDLE for 18-32 s used to stand on two 4 fps breathing frames
— a statue with a twitch. The LPC layer library this project vendors only ships
those two idle frames per direction, so more idle art has to be generated. The
same is true of an attack a character "owns": LPC ships one shared slash block,
so a hero's swing could not be his own. Both are generated art.

Inputs (on the magenta chroma screen the art pipeline keys against, as a grid of
equal cells — four columns in LPC's own direction order n, w, s, e):

    assets/lpc/_idle_src/<sheet>.png    2 rows  (weight shift, look-around)
    assets/lpc/_attack_src/<sheet>.png  4 rows  (the poses of one swing)
    assets/lpc/_cast_src/<sheet>.png    4 rows  (the poses of one cast)

Outputs (into the composed sheet `assets/lpc/<sheet>.png`):

    idle        columns 2-3 of every direction row -> loop [base, shift, breath, look]
    slash       columns 0-3 of every direction row -> a four-pose melee attack
    spellcast  columns 0-3 of every direction row -> a four-pose cast
           (columns 4+ of those rows are cleared, so the block holds exactly the
            frames that will be played)

`assets/lpc/pose_frames.json` is the manifest: which sheets carry which art, and
how many frames. `scripts/data/pose_art.gd` is the only thing at runtime that
reads it, and a sheet that is not in it keeps its original LPC frames.
`lpc_compose.py` calls `patch_sheet()` after composing, so recomposing a sheet
cannot throw the generated art away.

The pasted frames are not dropped in as-is. Each pose is

  * keyed off the chroma screen (with a despill pass, as tools/make_ui_icons.py),
  * cut out by empty-projection runs, so a pose is never mixed with its neighbour
    even if the generator spaced them unevenly,
  * mirrored back if the generator drew a side profile facing the wrong way
    (silhouette IoU against the frame the sheet already has for that direction),
  * scaled uniformly to the height of that same reference frame and pasted onto
    its baseline and horizontal centre, so a frame cannot float, sink or change
    size,
  * palette-snapped to the colours of the reference frame, so generated art
    arrives in the sheet's palette instead of its own.

Usage
-----
    python3 tools/make_idle_frames.py                 # patch every source
    python3 tools/make_idle_frames.py enemy_wolf ...  # patch named sheets
    python3 tools/make_idle_frames.py --check         # verify, exit 1 on problems

NOTE: the generated sources (`_idle_src/`, `_attack_src/`, `_cast_src/`) are
development-time inputs. They are parked in /tmp between batches to keep the
workspace inside its size budget (`tools/pose_sources.sh restore` brings them
back); `--check` and `--status` read only the composed sheets and the manifest.
"""
import json
import os
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from sheet_png import save_sheet  # noqa: E402  (exact-palette sheet writer)

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SHEET_DIR = os.path.join(ROOT, "assets", "lpc")
SRC_DIRS = {
    "idle": os.path.join(SHEET_DIR, "_idle_src"),
    "slash": os.path.join(SHEET_DIR, "_attack_src"),
    "spellcast": os.path.join(SHEET_DIR, "_cast_src"),
}
MANIFEST = os.path.join(SHEET_DIR, "pose_frames.json")

FRAME = 64
COLS = 13
ROWS = 20
DIRS = ["n", "w", "s", "e"]          # LPC row order inside an animation block
# Animation block index of each patched block: 0 idle, 1 walk, 2 slash, 3 spellcast.
# Ranged enemies attack on the spellcast block (enemy.gd plays it while winding
# up), so a caster's generated attack art belongs there and not in the slash block.
BLOCK_ROW = {"idle": 0, "slash": 2, "spellcast": 3}
POSE_ROWS = {"idle": 2, "slash": 4, "spellcast": 4}  # rows in the generated source
FIRST_COL = {"idle": 2, "slash": 0, "spellcast": 0}
KEEP_COLS = {"idle": 4, "slash": 4, "spellcast": 4}  # columns kept in the block
PATCHED_ANIMS = ("idle", "slash", "spellcast")
KEY_TOLERANCE = 96
ALPHA_CUTOFF = 120
# Below this mean per-channel difference a "new" frame is really frame 0 again.
MIN_FRAME_DIFFERENCE = 4.0
# Below this silhouette overlap a generated pose is probably not this character.
LOW_MATCH_WARN = 0.70
EXIT_OK, EXIT_PROBLEM = 0, 1


# --- chroma key -------------------------------------------------------------

def key_out(img: Image.Image) -> Image.Image:
    """Drop the magenta screen and its soft pink fringe (see make_ui_icons.py).

    The screen is a hard requirement of the pipeline: a sheet generated on a
    nearly-white background cannot be cut out at all — the first attempt at the
    husk's attack art arrived that way, and the cutter happily reported one
    enormous "pose". Refuse it here instead, where the message can say why.
    """
    corners = [img.getpixel((0, 0)), img.getpixel((img.width - 1, 0)),
               img.getpixel((0, img.height - 1)), img.getpixel((img.width - 1, img.height - 1))]
    off_screen = [c for c in corners
                  if not (abs(int(c[0]) - 255) < 40 and int(c[1]) < 60 and abs(int(c[2]) - 255) < 40)]
    if off_screen:
        raise ValueError("background is not the magenta chroma screen (corners are %s)"
                         % ", ".join(str(tuple(int(v) for v in c[:3])) for c in corners))
    arr = np.asarray(img.convert("RGBA"), dtype=np.int16)
    r, g, b = arr[..., 0], arr[..., 1], arr[..., 2]
    near_screen = ((np.abs(r - 255) < KEY_TOLERANCE)
                   & (np.abs(g - 0) < KEY_TOLERANCE)
                   & (np.abs(b - 255) < KEY_TOLERANCE))
    fringed = (r > 120) & (b > 110) & (g < 110) & ((r + b) > (2.1 * g).astype(np.int16))
    out = np.asarray(img.convert("RGBA"), dtype=np.uint8).copy()
    out[near_screen | fringed] = (0, 0, 0, 0)
    rr, gg, bb = (out[..., 0].astype(np.int16), out[..., 1].astype(np.int16),
                  out[..., 2].astype(np.int16))
    spill = (out[..., 3] > 0) & (rr > 100) & (bb > 100) & (gg < 0.55 * np.minimum(rr, bb))
    out[spill] = (0, 0, 0, 0)
    return Image.fromarray(out, "RGBA")


# --- cutting the generated grid into poses ----------------------------------

def _runs(occupied, min_size: int = 4) -> list:
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


def split_poses(img: Image.Image, rows: int) -> dict:
    """Cut the generated grid into poses; returns {(dir, row_index): box}."""
    alpha = np.asarray(img.getchannel("A"), dtype=np.uint8) > 0
    col_runs = [r for r in _runs(alpha.any(axis=0).tolist()) if r[1] - r[0] >= 8]
    if len(col_runs) > len(DIRS):
        # The generator sometimes draws more rotations than LPC has directions
        # (the shaman came back with six). Take the four that sit closest to the
        # four cardinal facings instead of failing: index evenly across the run
        # list, which picks back, both side profiles and front.
        n = len(col_runs)
        pick = [round(i * (n - 1) / float(len(DIRS) - 1)) for i in range(len(DIRS))]
        print("  note: %d pose columns generated, using columns %s for n/w/s/e"
              % (n, pick))
        col_runs = [col_runs[i] for i in pick]
    if len(col_runs) != len(DIRS):
        raise ValueError("expected %d pose columns, found %d %s"
                         % (len(DIRS), len(col_runs), col_runs))
    boxes = {}
    for d_i, (x0, x1) in enumerate(col_runs):
        band = alpha[:, x0:x1]
        row_runs = [r for r in _runs(band.any(axis=1).tolist()) if r[1] - r[0] >= 8]
        if len(row_runs) < rows:
            # Two poses that touch — a raised weapon meeting the pose above it —
            # read as one run, and the generator gives no rule for which. Split
            # the column's ink evenly instead of failing the whole sheet.
            ink = np.nonzero(band.any(axis=1))[0]
            if ink.size:
                y0, y1 = int(ink.min()), int(ink.max()) + 1
                step = (y1 - y0) / float(rows)
                row_runs = [(int(y0 + step * i), int(y0 + step * (i + 1))) for i in range(rows)]
                print("  note: column %s had %d pose rows, split evenly into %d"
                      % (DIRS[d_i], len(_runs(band.any(axis=1).tolist())), rows))
        if len(row_runs) > rows:
            # Extra rows: keep the topmost `rows` runs, which are the ones that
            # start at the character's head rather than at a stray mark below.
            row_runs = row_runs[:rows]
        if len(row_runs) != rows:
            raise ValueError("column %s: expected %d poses, found %d %s"
                             % (DIRS[d_i], rows, len(row_runs), row_runs))
        for p_i, (y0, y1) in enumerate(row_runs):
            sub = band[y0:y1, :]                 # band is already column-cropped
            ys, xs = np.nonzero(sub)
            boxes[(DIRS[d_i], p_i)] = (x0 + int(xs.min()), y0 + int(ys.min()),
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


def normalise_pose(pose: Image.Image, ref: Image.Image, tag: str = "this") -> Image.Image:
    """Scale a generated pose to the reference frame's build and palette."""
    arr = np.asarray(pose, dtype=np.uint8).copy()
    arr[arr[..., 3] < ALPHA_CUTOFF] = (0, 0, 0, 0)
    pose = Image.fromarray(arr, "RGBA")

    ref_box = ref.getbbox() or (0, 0, FRAME, FRAME)
    ref_mask = np.asarray(ref.getchannel("A"), dtype=np.uint8) > ALPHA_CUTOFF
    ref_mask = ref_mask[ref_box[1]:ref_box[3], ref_box[0]:ref_box[2]]
    size = (ref_box[2] - ref_box[0], ref_box[3] - ref_box[1])

    # Side profiles are the ones a generator is most likely to draw mirrored; pick
    # whichever orientation actually matches the silhouette it must join.
    flipped = pose.transpose(Image.FLIP_LEFT_RIGHT)
    score = {}
    for label, cand in (("as-is", pose), ("flipped", flipped)):
        mask = np.asarray(cand.getchannel("A"), dtype=np.uint8) > ALPHA_CUTOFF
        score[label] = _iou(_resize_mask(mask, size), ref_mask)
    if score["flipped"] > score["as-is"] + 0.04:
        pose = flipped

    src_box = pose.getbbox()
    if src_box is None:
        raise ValueError("empty pose")
    pose = pose.crop(src_box)

    # A pose that does not look like the frame it is joining is usually a
    # different character altogether (the first elder idle art arrived as a
    # bearded man in a robe). Silhouette overlap after normalisation is a cheap
    # way to catch that early; it is a warning, not a rejection, because a
    # genuine swing or lunge legitimately differs from a standing frame.
    match = max(score["as-is"], score["flipped"]) if score else 0.0
    if match < LOW_MATCH_WARN:
        print("  note: %s is only %.0f%% like the frame it joins (possible "
              "different character)" % (tag.split("/")[0], 100.0 * match))

    scale = size[1] / float(pose.height)
    pose = pose.resize((max(1, int(round(pose.width * scale))), size[1]), Image.LANCZOS)
    arr = np.asarray(pose, dtype=np.uint8).copy()
    arr[arr[..., 3] < ALPHA_CUTOFF] = (0, 0, 0, 0)
    solid = arr[..., 3] > ALPHA_CUTOFF
    if solid.any():
        arr[..., :3][solid] = _snap_to_palette(arr[..., :3][solid], _palette(ref))
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
    x, y = col * FRAME, row * FRAME
    sheet.paste((0, 0, 0, 0), (x, y, x + FRAME, y + FRAME))
    sheet.paste(pose, (x + dx, y + dy), pose)


# --- sheet-level driver -----------------------------------------------------

def patch_anim(sheet: Image.Image, name: str, anim: str) -> int:
    """Paste one animation's generated poses into a sheet. Returns 0 if no art."""
    src_path = os.path.join(SRC_DIRS[anim], name + ".png")
    if not os.path.exists(src_path):
        return 0
    rows = POSE_ROWS[anim]
    src = key_out(Image.open(src_path))
    poses = split_poses(src, rows)
    pasted = 0
    for d_i, d in enumerate(DIRS):
        row = BLOCK_ROW[anim] * 4 + d_i
        ref = _frame_rgba(sheet, row, 0)
        for p_i in range(rows):
            pose = normalise_pose(src.crop(poses[(d, p_i)]), ref, "%s/%s/%d" % (name, d, p_i))
            paste_pose(sheet, row, FIRST_COL[anim] + p_i, pose, ref)
            pasted += 1
        # Leave the block holding exactly the frames that will be played, so a
        # leftover LPC pose can never be reached by a future frame-count change.
        for col in range(FIRST_COL[anim] + rows, COLS):
            x, y = col * FRAME, row * FRAME
            sheet.paste((0, 0, 0, 0), (x, y, x + FRAME, y + FRAME))
    return pasted


def patch_sheet(name: str) -> dict:
    """Patch one sheet from whatever generated art exists. Returns its manifest entry."""
    sheet_path = os.path.join(SHEET_DIR, name + ".png")
    if not os.path.exists(sheet_path):
        raise FileNotFoundError("no composed sheet %s" % sheet_path)
    sheet = Image.open(sheet_path).convert("RGBA")
    if sheet.size != (COLS * FRAME, ROWS * FRAME):
        raise ValueError("%s: unexpected sheet size %s" % (name, sheet.size))
    entry = {}
    for anim in PATCHED_ANIMS:
        pasted = patch_anim(sheet, name, anim)
        if pasted:
            entry[anim] = KEEP_COLS[anim]
    if entry:
        save_sheet(sheet, sheet_path)
    return entry


def _sources() -> list:
    names = set()
    for d in SRC_DIRS.values():
        if os.path.isdir(d):
            names |= {f[:-4] for f in os.listdir(d) if f.endswith(".png")}
    return sorted(names)


def refresh_manifest(names: list) -> None:
    """Rewrite the manifest entries for `names` from the sources on disk.

    Called by lpc_compose.py after a recompose + re-patch, so the manifest can
    never claim art that a recompose just wiped out.
    """
    manifest = {k: v for k, v in _load_manifest().items()
                if os.path.exists(os.path.join(SHEET_DIR, k + ".png"))}
    for name in names:
        entry = {}
        for anim in PATCHED_ANIMS:
            if os.path.exists(os.path.join(SRC_DIRS[anim], name + ".png")):
                entry[anim] = KEEP_COLS[anim]
        if entry:
            manifest[name] = entry
        else:
            manifest.pop(name, None)
    _save_manifest(manifest)


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
    """Mean per-channel difference over the union of two frames' silhouettes."""
    solid = (a[..., 3] > ALPHA_CUTOFF) | (b[..., 3] > ALPHA_CUTOFF)
    if not solid.any():
        return 0.0
    return float(np.abs(a[..., :3][solid].astype(np.int16)
                        - b[..., :3][solid].astype(np.int16)).mean())


def check() -> bool:
    """Verify every patched sheet really carries the frames it claims."""
    manifest = _load_manifest()
    problems = []
    if not manifest:
        problems.append("manifest %s is empty" % os.path.relpath(MANIFEST, ROOT))
    for name, entry in sorted(manifest.items()):
        path = os.path.join(SHEET_DIR, name + ".png")
        if not os.path.exists(path):
            problems.append("%s: listed in the manifest but the sheet is gone" % name)
            continue
        sheet = Image.open(path).convert("RGBA")
        if sheet.size != (COLS * FRAME, ROWS * FRAME):
            problems.append("%s: sheet size %s" % (name, sheet.size))
            continue
        if not isinstance(entry, dict):
            problems.append("%s: manifest entry is not per-animation" % name)
            continue
        for anim, frames in sorted(entry.items()):
            if anim not in BLOCK_ROW:
                problems.append("%s: unknown animation '%s'" % (name, anim))
                continue
            frames = int(frames)
            if frames != KEEP_COLS[anim]:
                problems.append("%s/%s: %d frames, expected %d"
                                % (name, anim, frames, KEEP_COLS[anim]))
            for d_i, d in enumerate(DIRS):
                row = BLOCK_ROW[anim] * 4 + d_i
                ref = np.asarray(_frame_rgba(sheet, row, 0), dtype=np.uint8)
                if not (ref[..., 3] > ALPHA_CUTOFF).any():
                    problems.append("%s/%s: frame 0 is empty" % (name, d))
                    continue
                for col in range(1, frames):
                    cell = _frame_rgba(sheet, row, col)
                    if cell.getbbox() is None:
                        problems.append("%s/%s: %s frame %d is empty" % (name, d, anim, col))
                        continue
                    diff = _frame_difference(ref, np.asarray(cell, dtype=np.uint8))
                    if diff < MIN_FRAME_DIFFERENCE:
                        problems.append("%s/%s: %s frame %d is a copy of frame 0"
                                        % (name, d, anim, col, diff))
                if _frame_rgba(sheet, row, frames).getbbox() is not None:
                    problems.append("%s/%s: %s block overflows into column %d"
                                    % (name, d, anim, frames))
    for p in problems:
        print("  PROBLEM: %s" % p)
    if problems:
        print("POSE ART: FAILED (%d problems)" % len(problems))
        return False
    counts = {a: sum(1 for e in manifest.values() if int(e.get(a, 0))) for a in PATCHED_ANIMS}
    print("POSE ART: PASS (%d sheets: %d with idle frames, %d with attack poses, "
          "%d with cast poses)" % (len(manifest), counts["idle"], counts["slash"],
                                   counts["spellcast"]))
    return True



def status() -> int:
    """Print which characters still owe generated art, straight from the game's
    own data file and the manifest — so the art queue is read, not guessed."""
    import json
    with open(os.path.join(ROOT, "data", "enemies.json")) as fh:
        enemies = json.load(fh)
    manifest = _load_manifest()
    rows = []
    for key, cfg in sorted(enemies["archetypes"].items()):
        name = str(cfg.get("sheet", "")).split("/")[-1].replace(".png", "")
        if not name:
            continue
        entry = manifest.get(name, {})
        rows.append((key, name, int(entry.get("idle", 0)),
                     int(entry.get("slash", 0)), int(entry.get("spellcast", 0))))
    for key, name, idle, slash, cast in rows:
        marks = ["idle %d" % idle if idle else "idle --"]
        marks.append("attack %d" % slash if slash else "attack --")
        marks.append("cast %d" % cast if cast else "cast --")
        print("  %-16s %-20s %s" % (key, name, "  ".join(marks)))
    idle_done = [r for r in rows if r[2] > 0]
    slash_done = [r for r in rows if r[3] > 0]
    cast_done = [r for r in rows if r[4] > 0]
    print("ART STATUS: %d/%d archetypes have idle art, %d/%d generated attack art, "
          "%d/%d generated cast art"
          % (len(idle_done), len(rows), len(slash_done), len(rows), len(cast_done), len(rows)))
    owed = [r[1] for r in rows if r[2] == 0]
    if owed:
        print("  idle owed: " + ", ".join(owed))
    # Melee archetypes swing on the slash block; ranged ones cast. Report which
    # sheets each still needs, so a generation batch can be planned from this.
    no_melee = [key for key, _n, _i, slash, _c in rows if slash == 0
                and str(enemies["archetypes"][key].get("behavior", "melee")) != "ranged"]
    no_cast = [key for key, _n, _i, _s, cast in rows if cast == 0
               and str(enemies["archetypes"][key].get("behavior", "melee")) == "ranged"]
    if no_melee:
        print("  melee art owed: " + ", ".join(no_melee))
    if no_cast:
        print("  cast art owed: " + ", ".join(no_cast))
    return 0


def main() -> None:
    if "--status" in sys.argv[1:]:
        sys.exit(status())
    if "--check" in sys.argv[1:]:
        sys.exit(EXIT_OK if check() else EXIT_PROBLEM)

    want = [a for a in sys.argv[1:] if not a.startswith("-")] or _sources()
    if not want:
        sys.exit("no generated pose art in %s" % ", ".join(
            os.path.relpath(d, ROOT) for d in SRC_DIRS.values()))
    # Drop entries whose source art is gone (an armed character's stale unarmed
    # poses, say): a sheet must never claim frames it does not have.
    manifest = {k: v for k, v in _load_manifest().items()
                if os.path.exists(os.path.join(SRC_DIRS["idle"], k + ".png"))
                or os.path.exists(os.path.join(SRC_DIRS["slash"], k + ".png"))}
    failed = []
    for name in want:
        try:
            entry = patch_sheet(name)
        except (FileNotFoundError, ValueError) as exc:
            failed.append("%s: %s" % (name, exc))
            continue
        if entry:
            manifest[name] = entry
            print("  %-24s patched %s" % (name, ", ".join(
                "%s x%d poses" % (a, KEEP_COLS[a]) for a in sorted(entry))))
    _save_manifest(manifest)
    if failed:
        for f in failed:
            print("  PROBLEM: %s" % f)
        sys.exit(EXIT_PROBLEM)


if __name__ == "__main__":
    main()
