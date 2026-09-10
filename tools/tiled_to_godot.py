#!/usr/bin/env python3
"""Tiled JSON -> Godot chunk scene converter (tools pipeline, Phase 2).

Reads world/chunks/chunk_X_Y.json (canonical Tiled JSON export) and emits
world/chunks/chunk_X_Y.tscn containing:
  - ChunkRenderer (packed GID grid + atlas + biome base color)
  - StaticBody2D with greedy-merged collision rects for solid tiles
    (columns 3 hazard, 4 obstacle, 5 wall are solid)
  - one node per Tiled object: chest / sign / lever / waypoint / gate / spawner

Usage: python3 tools/tiled_to_godot.py [chunk_file ...]   (no args = all)
"""
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(__file__), ".."))
CHUNK_DIR = os.path.join(ROOT, "world", "chunks")
TILE = 32
GRID = 32
SOLID_COLS = (3, 4, 5)

BIOME_BASE = {
    0: (0.24, 0.42, 0.25),
    1: (0.46, 0.40, 0.30),
    2: (0.55, 0.58, 0.64),
}

SCRIPTS = {
    "renderer": "res://scripts/world/chunk_renderer.gd",
    "chest": "res://scripts/world/chest.gd",
    "sign": "res://scripts/world/sign.gd",
    "lever": "res://scripts/world/lever.gd",
    "waypoint": "res://scripts/world/waypoint.gd",
    "gate": "res://scripts/world/secret_gate.gd",
    "spawner": "res://scripts/enemies/enemy_spawner.gd",
}


def props_of(obj):
    out = {}
    for p in obj.get("properties", []):
        out[p["name"]] = p["value"]
    return out


def gd_str(s):
    return '"' + str(s).replace("\\", "\\\\").replace('"', '\\"') + '"'


def merge_rects(solid):
    """Greedy: horizontal runs extended downward while the run matches."""
    rects = []
    visited = [[False] * GRID for _ in range(GRID)]
    for y in range(GRID):
        x = 0
        while x < GRID:
            if solid[y][x] and not visited[y][x]:
                x2 = x
                while x2 < GRID and solid[y][x2] and not visited[y][x2]:
                    x2 += 1
                y2 = y
                while y2 + 1 < GRID and all(
                    solid[y2 + 1][k] and not visited[y2 + 1][k] for k in range(x, x2)
                ):
                    y2 += 1
                for yy in range(y, y2 + 1):
                    for xx in range(x, x2):
                        visited[yy][xx] = True
                rects.append((x, y, x2 - x, y2 - y + 1))
                x = x2
            else:
                x += 1
    return rects


def convert(path):
    with open(path) as f:
        m = json.load(f)
    name = os.path.splitext(os.path.basename(path))[0]
    mx, my = (int(v) for v in re.findall(r"-?\d+", name.split("chunk_")[1]))

    terrain, objects, biome = None, [], 0
    for layer in m["layers"]:
        if layer["type"] == "tilelayer" and layer["name"] == "terrain":
            terrain = layer["data"]
        elif layer["type"] == "objectgroup":
            objects = layer.get("objects", [])
    for p in m.get("properties", []):
        if p["name"] == "biome":
            biome = int(p["value"])

    if terrain is None or len(terrain) != GRID * GRID:
        raise SystemExit(f"{path}: bad terrain layer")

    solid = [[False] * GRID for _ in range(GRID)]
    for i, gid in enumerate(terrain):
        if gid and ((gid - 1) % 8) in SOLID_COLS:
            solid[i // GRID][i % GRID] = True
    rects = merge_rects(solid)

    # ---- emit .tscn ----
    used_scripts = {"renderer"}
    nodes = []
    next_id = 10

    for obj in objects:
        t = obj.get("type", "")
        pr = props_of(obj)
        used_scripts.add(t if t in SCRIPTS else "")
        nid = f"o{next_id}"
        next_id += 1
        if t == "chest":
            nodes.append(
                f'[node name="{nid}" type="Area2D" parent="Objects"]\n'
                f'position = Vector2({obj["x"]}, {obj["y"]})\n'
                f'script = ExtResource("s_chest")\n'
                f'chest_id = {gd_str(obj.get("name", "chest"))}\n'
                f'gold = {int(pr.get("gold", 0))}\n'
                f'item_id = {gd_str(pr.get("item", ""))}\n'
            )
        elif t == "sign":
            nodes.append(
                f'[node name="{nid}" type="Area2D" parent="Objects"]\n'
                f'position = Vector2({obj["x"]}, {obj["y"]})\n'
                f'script = ExtResource("s_sign")\n'
                f'title = {gd_str(pr.get("title", "Sign"))}\n'
                f'text = {gd_str(pr.get("text", ""))}\n'
            )
        elif t == "lever":
            nodes.append(
                f'[node name="{nid}" type="Area2D" parent="Objects"]\n'
                f'position = Vector2({obj["x"]}, {obj["y"]})\n'
                f'script = ExtResource("s_lever")\n'
                f'lever_id = {gd_str(obj.get("name", "lever"))}\n'
                f'gate_id = {gd_str(pr.get("gate", ""))}\n'
            )
        elif t == "waypoint":
            nodes.append(
                f'[node name="{nid}" type="Area2D" parent="Objects"]\n'
                f'position = Vector2({obj["x"]}, {obj["y"]})\n'
                f'script = ExtResource("s_waypoint")\n'
                f'wp_id = {gd_str(obj.get("name", "wp"))}\n'
                f'wp_name = {gd_str(pr.get("label", obj.get("name", "Campfire")))}\n'
            )
        elif t == "gate":
            nodes.append(
                f'[node name="{nid}" type="StaticBody2D" parent="Objects"]\n'
                f'position = Vector2({obj["x"]}, {obj["y"]})\n'
                f'script = ExtResource("s_gate")\n'
                f'gate_id = {gd_str(obj.get("name", "gate"))}\n'
            )
        elif t == "spawner":
            nodes.append(
                f'[node name="{nid}" type="Node2D" parent="Objects"]\n'
                f'position = Vector2({obj["x"]}, {obj["y"]})\n'
                f'script = ExtResource("s_spawner")\n'
                f'archetype = {gd_str(pr.get("archetype", "grunt"))}\n'
                f'count = {int(pr.get("count", 1))}\n'
                f'power_scale = {float(pr.get("power", 1.0))}\n'
            )
        else:
            used_scripts.discard("")
            nodes.append(f"# skipped unknown object type '{t}' ({obj.get('name')})\n")
    used_scripts.discard("")

    ext = [
        ('r_renderer', f'[ext_resource type="Script" path="{SCRIPTS["renderer"]}" id="r_renderer"]'),
        ('r_atlas', '[ext_resource type="Texture2D" path="res://assets/tiles/atlas.png" id="r_atlas"]'),
    ]
    for key in ("chest", "sign", "lever", "waypoint", "gate", "spawner"):
        if key in used_scripts:
            kind = "Script"
            ext.append((f"s_{key}", f'[ext_resource type="{kind}" path="{SCRIPTS[key]}" id="s_{key}"]'))

    subs = []
    for i, (rx, ry, rw, rh) in enumerate(rects):
        subs.append(
            f'[sub_resource type="RectangleShape2D" id="col_{i}"]\n'
            f'size = Vector2({rw * TILE}, {rh * TILE})\n'
        )

    base = BIOME_BASE.get(biome, BIOME_BASE[0])
    tiles_str = "PackedInt32Array(" + ", ".join(str(int(g)) for g in terrain) + ")"

    out = []
    out.append(f'[gd_scene load_steps={len(ext) + len(subs) + 1} format=3]\n')
    out.extend(e[1] + "\n" for e in ext)
    out.append("\n")
    out.extend(s + "\n" for s in subs)
    out.append(f'[node name="{name}" type="Node2D"]\n\n')
    out.append(
        '[node name="Renderer" type="Node2D" parent="."]\n'
        'script = ExtResource("r_renderer")\n'
        f'grid_w = {GRID}\ngrid_h = {GRID}\ntile_size = {TILE}\n'
        f'tiles = {tiles_str}\n'
        'atlas = ExtResource("r_atlas")\n'
        f'base_color = Color({base[0]}, {base[1]}, {base[2]}, 1)\n\n'
    )
    out.append(
        '[node name="Solids" type="StaticBody2D" parent="."]\n'
        'collision_layer = 1\ncollision_mask = 0\n\n'
    )
    for i, (rx, ry, rw, rh) in enumerate(rects):
        cx = rx * TILE + rw * TILE / 2.0
        cy = ry * TILE + rh * TILE / 2.0
        out.append(
            f'[node name="Col{i}" type="CollisionShape2D" parent="Solids"]\n'
            f'position = Vector2({cx:g}, {cy:g})\n'
            f'shape = SubResource("col_{i}")\n\n'
        )
    if nodes:
        out.append('[node name="Objects" type="Node2D" parent="."]\n\n')
        out.extend(n + "\n" for n in nodes)

    dest = os.path.join(CHUNK_DIR, name + ".tscn")
    with open(dest, "w") as f:
        f.write("".join(out))
    return dest


def main():
    files = sys.argv[1:] or sorted(
        os.path.join(CHUNK_DIR, f) for f in os.listdir(CHUNK_DIR) if f.endswith(".json")
    )
    for path in files:
        print("converted", os.path.basename(convert(path)))


if __name__ == "__main__":
    main()
