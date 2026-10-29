"""Renders CC0 Poly Haven tree models into impostor textures (cut-out
pictures) for cheap, realistic roadside trees on phones.

  blender -b --factory-startup -P tools/blender/bake_impostors.py

Sources (downloaded separately, not in the repo) live in ../flowline_raw/trees.
Output: assets/env/trees/<name>_<view>.png (RGBA) + <name>.json with the
tree's height/width in metres.
"""
import json
import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "..", "flowline_raw", "trees")
OUT = os.path.join(ROOT, "assets", "env", "trees")
TREES = {
    "island_tree_02": "island_tree_02/island_tree_02_1k.gltf",
    "fir_sapling_medium": "fir_sapling_medium/fir_sapling_medium_1k.gltf",
}
RES = (512, 1024)


def setup_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.film_transparent = True
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.resolution_x, scene.render.resolution_y = RES
    scene.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.62, 0.70, 0.80, 1)
    bg.inputs[1].default_value = 0.8
    scene.world = world
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(45), 0, math.radians(-30))
    scene.collection.objects.link(sun)
    return scene


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in objs:
        if o.type != "MESH":
            continue
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def groups(objs):
    """Clusters mesh objects into separate trees by horizontal position."""
    out = []
    for o in [o for o in objs if o.type == "MESH"]:
        lo, hi = bounds([o])
        c = (lo + hi) / 2
        for g in out:
            if abs(g["c"].x - c.x) < 1.5 and abs(g["c"].y - c.y) < 1.5:
                g["objs"].append(o)
                break
        else:
            out.append({"c": c, "objs": [o]})
    return [g["objs"] for g in out]


def render_group(scene, name, objs, all_objs):
    for o in all_objs:
        o.hide_render = o.type == "MESH" and o not in objs
    lo, hi = bounds(objs)
    center = (lo + hi) / 2
    h = hi.z - lo.z
    w = max(hi.x - lo.x, hi.y - lo.y) * 1.04
    if h >= w:
        rx, ry = max(128, int(1024 * w / h) // 8 * 8), 1024
    else:
        rx, ry = 1024, max(128, int(1024 * h / w) // 8 * 8)
    scene.render.resolution_x, scene.render.resolution_y = rx, ry
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(h, w) * 1.01
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, ang in (("a", 0.0), ("b", math.pi / 2)):
        d = 50.0
        cam.location = (center.x + math.sin(ang) * d, center.y - math.cos(ang) * d, (lo.z + hi.z) / 2)
        cam.rotation_euler = (math.pi / 2, 0, ang)
        scene.render.filepath = os.path.join(OUT, "%s_%s.png" % (name, view))
        bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)
    meta = {"height": cam_h(h, w, ry, rx), "width": cam_h(h, w, ry, rx) * rx / ry}
    with open(os.path.join(OUT, name + ".json"), "w") as f:
        json.dump(meta, f, indent=1)
    print("IMPOSTOR", name, rx, ry, meta)


def cam_h(h, w, ry, rx):
    # ortho_scale covers the larger image side
    s = max(h, w) * 1.01
    return s if ry >= rx else s * ry / rx


def main():
    os.makedirs(OUT, exist_ok=True)
    for f in os.listdir(OUT):
        os.remove(os.path.join(OUT, f))
    for name, rel in TREES.items():
        scene = setup_scene()
        bpy.ops.import_scene.gltf(filepath=os.path.join(RAW, rel))
        objs = list(scene.objects)
        for m in bpy.data.materials:  # alpha-tested leaves render crisply
            if hasattr(m, "surface_render_method"):
                m.surface_render_method = "DITHERED"
        for i, g in enumerate(groups(objs)):
            render_group(scene, "%s_%d" % (name, i), g, objs)


main()
