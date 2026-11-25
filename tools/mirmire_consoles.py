#!/usr/bin/env python3
# SPDX-License-Identifier: GPL-3.0-or-later
"""Writes the console folders of the models added for Mirmire (CC-BY-4.0, from Sketchfab; see each LICENSE.txt):
the manifest, the scene (the glb instanced as Model, scaled to its real size, turned to face the front, its base or
centre on the origin) and the seat. Sizes were measured on the imported glbs; real sizes from the consoles' specs.

Usage: python3 tools/mirmire_consoles.py
"""
import math
import pathlib

CONSOLES = pathlib.Path(__file__).resolve().parent.parent / "app/carousel/consoles"

# folder: platform, version, name, model name, glb box (position, size) in its own units, real width in mm,
#         turn about Y in degrees, handheld (centred, leant back) or not (base on the floor), budget,
#         seat (mm, in the model's axes), seat turn, way in, nodes hidden (what came with the model)
MODELS = {
    "steam_deck": dict(platform="mirmire_steam", version="1010", name="Steam", model_name="Steam Deck",
        box=((-4.45679, -1.37988, -0.10425), (8.91358, 3.46243, 1.47797)), width=298, turn=0, handheld=True,
        budget=48000, seat=(110, 50, -10), seat_turn=(0, 180, 0), way_in=(0, 1, 0), source="steam_deck.glb"),
    "steam_deck_streaming": dict(platform="mirmire_streaming", version="1010-stream", name="Streaming", model_name="Steam Deck",
        box=((-4.45679, -1.37988, -0.10425), (8.91358, 3.46243, 1.47797)), width=298, turn=0, handheld=True,
        budget=48000, seat=(110, 50, -10), seat_turn=(0, 180, 0), way_in=(0, 1, 0), source="../steam_deck/steam_deck.glb"),
    "atari2600": dict(platform="atari2600", version="cx2600", name="Atari 2600", model_name="Heavy Sixer",
        box=((-1.755, 0.0, -1.175), (3.51, 0.66, 2.35)), width=345, turn=0, handheld=False, budget=65000,
        seat=(0, 85, -20), seat_turn=(0, 180, 0), way_in=(0, 1, 0),
        hide=["pitfall_0", "space invaders_1", "super breakout_2", "right_controller_4", "left_controller_6", "atari2600_9/signal_cable_8"]),
    "atarilynx": dict(platform="mirmire_atarilynx", version="pag-0201", name="Lynx", model_name="Lynx I",
        box=((-0.09298, 0.000149, -0.026976), (0.185787, 0.074769, 0.031055)), width=273, turn=0, handheld=True,
        budget=22000, seat=(60, 54, -12), seat_turn=(0, 180, 0), way_in=(0, 1, 0)),
    "3ds_xl": dict(platform="3ds", version="spr-001", name="3DS", model_name="3DS XL",
        box=((-0.509991, -0.252457, -0.418782), (1.110143, 0.873754, 1.147355)), width=156, turn=0, handheld=True,
        budget=10000, seat=(40, -20, -60), seat_turn=(0, 180, 0), way_in=(0, 0, -1)),
    "wiiu": dict(platform="mirmire_wiiu", version="wup-101", name="Wii U", model_name="Wii U",
        box=((-0.66118, 0.113307, -0.412181), (1.262885, 0.226734, 0.823349)), width=268, turn=-90, handheld=False,
        budget=66000, seat=(0, 23, 0), seat_turn=(-90, 0, 0), way_in=(0, 0, 1)),
    "ps3": dict(platform="mirmire_ps3", version="cechg", name="PlayStation 3", model_name="Original",
        box=((-0.171025, -0.05279, -0.12802), (0.328373, 0.099646, 0.277908)), width=325, turn=180, handheld=False,
        budget=33000, seat=(0, 50, 0), seat_turn=(-90, 0, 0), way_in=(0, 0, 1)),
    "saturn": dict(platform="saturn", version="hst-3200", name="Saturn", model_name="Model 1",
        box=((-18.48399, -0.063024, -9.628647), (22.85049, 6.856087, 20.39934)), width=260, turn=0, handheld=False,
        budget=215000, seat=(0, 75, -20), seat_turn=(-90, 0, 0), way_in=(0, 1, 0)),
    # Converted from a CAD model (STEP) by tools: already in this app's units, centred, facing the front, painted.
    "gamegear": dict(platform="gamegear", version="2110", name="Game Gear", model_name="Game Gear",
        box=((-1.046943, -0.569629, -0.200555), (2.093886, 1.139258, 0.401109)), width=209.3886, turn=0, handheld=True,
        budget=34000, seat=(0, 22.3, -13), seat_turn=(0, 180, 0), way_in=(0, 1, 0)),
    "ngpc": dict(platform="mirmire_ngpc", version="neop10000", name="Neo Geo Pocket Color", model_name="Pocket Color",
        box=((-9.18397, -4.47755, -2.471877), (18.36794, 8.989063, 4.867896)), width=130, turn=0, handheld=True,
        budget=10000, seat=(0, 14.3, 0.9), seat_turn=(0, 180, 0), way_in=(0, 1, 0),
        hide_root="Sketchfab_model/NeoGeo2_fbx/RootNode", hide=["Cartridge", "CartridgeOut"]),
    "ngp": dict(platform="mirmire_ngp", version="neop10000-mono", name="Neo Geo Pocket", model_name="Pocket",
        box=((-9.18397, -4.47755, -2.471877), (18.36794, 8.989063, 4.867896)), width=130, turn=0, handheld=True,
        budget=10000, seat=(0, 14.3, 0.9), seat_turn=(0, 180, 0), way_in=(0, 1, 0), source="../ngpc/ngpc.glb",
        hide_root="Sketchfab_model/NeoGeo2_fbx/RootNode", hide=["Cartridge", "CartridgeOut"]),
}

UNITS_PER_MM = 0.01


def vec(v):
    return "Vector3(%s)" % ", ".join(f"{x:.6g}" for x in v)


def place(model):
    """The Model node's scale and position: the real width, the base (or centre, for a handheld) on the origin."""
    (px, py, pz), (sx, sy, sz) = model["box"]
    scale = model["width"] * UNITS_PER_MM / sx
    cx, cz = px + sx / 2, pz + sz / 2
    cy = py + sy / 2 if model["handheld"] else py
    a = math.radians(model["turn"])
    # Rotation about Y applied to the scaled centre, then moved back to the origin.
    x, y, z = cx * scale, cy * scale, cz * scale
    rx = x * math.cos(a) + z * math.sin(a)
    rz = -x * math.sin(a) + z * math.cos(a)
    return scale, (-rx, -y, -rz)


def main():
    for folder, m in MODELS.items():
        d = CONSOLES / folder
        d.mkdir(exist_ok=True)
        glb = m.get("source", f"{folder}.glb")
        glb_path = f"res://carousel/consoles/{folder}/{glb}" if "/" not in glb else \
            "res://carousel/consoles/" + str(pathlib.PurePosixPath(folder, glb)).replace(f"{folder}/../", "")
        scale, position = place(m)
        pose = (15, 0, 0) if m["handheld"] else (25, 20, 0)
        hidden = "".join(
            f'\n[node name="{h.split("/")[-1]}" parent="Model/{m.get("hide_root", "Sketchfab_model/root/GLTF_SceneRootNode")}{"/" + h.rsplit("/", 1)[0] if "/" in h else ""}"]\nvisible = false\n'
            for h in m.get("hide", []))
        (d / f"{folder}.tscn").write_text(f"""[gd_scene format=3]

[ext_resource type="Script" path="res://carousel/consoles/console_model.gd" id="1"]
[ext_resource type="Resource" path="res://carousel/consoles/{folder}/{folder}_shape.tres" id="2"]
[ext_resource type="PackedScene" path="{glb_path}" id="3"]

[node name="{folder.title().replace('_', '')}" type="Node3D"]
script = ExtResource("1")
shape = ExtResource("2")
way_in = {vec(m["way_in"])}
pose_degrees = {vec(pose)}

[node name="Model" parent="." instance=ExtResource("3")]
transform = Transform3D({_basis(scale, m["turn"])}, {position[0]:.6g}, {position[1]:.6g}, {position[2]:.6g})
{"" if not hidden else '''
[editable path="Model"]
''' + hidden}""")
        (d / f"{folder}_shape.tres").write_text(f"""[gd_resource type="Resource" script_class="SeatShape" load_steps=2 format=3]

[ext_resource type="Script" path="res://carousel/consoles/seat_shape.gd" id="1"]

[resource]
script = ExtResource("1")
seat_centre = {vec(m["seat"])}
seat_degrees = {vec(m["seat_turn"])}
housings = Array[StringName]([])
""")
        (d / "console.tres").write_text(f"""[gd_resource type="Resource" script_class="ConsoleManifest" load_steps=2 format=3]

[ext_resource type="Script" path="res://carousel/consoles/console_manifest.gd" id="1"]

[resource]
script = ExtResource("1")
platform = "{m['platform']}"
version = &"{m['version']}"
is_default = true
name = "{m['name']}"
model_name = "{m['model_name']}"
scene = "res://carousel/consoles/{folder}/{folder}.tscn"
triangle_budget = {m['budget']}
""")
        print(folder, f"scale {scale:.4g}", "position", tuple(round(p, 4) for p in position))


def _basis(scale, turn):
    a = math.radians(turn)
    c, s = math.cos(a) * scale, math.sin(a) * scale
    # Godot writes a basis as its three rows: x row, y row, z row.
    rows = [(c, 0, s), (0, scale, 0), (-s, 0, c)]
    return ", ".join(f"{v:.6g}" for row in rows for v in row)


if __name__ == "__main__":
    main()
