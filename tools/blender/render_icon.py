"""Renders the app icon (1024x1024) and a wide store/feature image from the
starter car, lit by the game's HDRI sky.

  blender -b --factory-startup -P tools/blender/render_icon.py
"""
import math
import os

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
CAR = os.path.join(ROOT, "assets", "vehicles", "vanta.glb")
HDRI = os.path.join(ROOT, "assets", "env", "sky.hdr")
OUT = os.path.join(ROOT, "assets", "brand")


def setup():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 96
    scene.cycles.device = "CPU"
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "AgX - Punchy"
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    nt = world.node_tree
    env = nt.nodes.new("ShaderNodeTexEnvironment")
    env.image = bpy.data.images.load(HDRI)
    mapping = nt.nodes.new("ShaderNodeMapping")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    mapping.inputs["Rotation"].default_value = (0, 0, math.radians(200))
    nt.links.new(coord.outputs["Generated"], mapping.inputs["Vector"])
    nt.links.new(mapping.outputs["Vector"], env.inputs["Vector"])
    nt.links.new(env.outputs["Color"], nt.nodes["Background"].inputs["Color"])
    scene.world = world
    bpy.ops.import_scene.gltf(filepath=CAR)
    for m in bpy.data.materials:  # game paint colour + AO from vertex colours
        if not m.use_nodes:
            continue
        b = m.node_tree.nodes.get("Principled BSDF")
        if b is None:
            continue
        if m.name.startswith("Paint"):
            b.inputs["Base Color"].default_value = (0.03, 0.12, 0.42, 1)
            b.inputs["Metallic"].default_value = 0.6
            b.inputs["Roughness"].default_value = 0.25
            b.inputs["Coat Weight"].default_value = 1.0
    # Asphalt ground that fades into the dark
    bpy.ops.mesh.primitive_plane_add(size=40)
    g = bpy.context.active_object
    gm = bpy.data.materials.new("Ground")
    gm.use_nodes = True
    gb = gm.node_tree.nodes["Principled BSDF"]
    gb.inputs["Base Color"].default_value = (0.035, 0.036, 0.04, 1)
    gb.inputs["Roughness"].default_value = 0.35
    g.data.materials.append(gm)
    return scene


def shoot(scene, path, res, loc, target, lens):
    scene.render.resolution_x, scene.render.resolution_y = res
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = lens
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.location = loc
    d = Vector(target) - Vector(loc)
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)
    bpy.data.objects.remove(cam)


def main():
    os.makedirs(OUT, exist_ok=True)
    scene = setup()
    # glTF import: car faces Blender +Y again
    # rear three-quarter view: the light bar is the car's signature
    shoot(scene, os.path.join(OUT, "icon_raw.png"), (1024, 1024), (-3.3, -4.5, 1.15), (0.15, -0.1, 0.55), 30)  # room round the car for the rounded icon mask


main()
