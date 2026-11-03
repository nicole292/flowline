"""Procedural vehicle generator for FLOWLINE.

Builds original, fictional vehicles from a handful of design parameters and
exports each one as a GLB (Y-up, facing -Z in Godot) plus preview renders.

Run:
  blender -b -P tools/blender/build_cars.py -- [--only name,name] [--no-render]

Every material is named so the game can override it at runtime:
  Paint, Glass, Trim, Chrome, Tire, Rim, Headlight, Taillight
Wheels are separate nodes named Wheel_FL / Wheel_FR / Wheel_RL / Wheel_RR with
their pivot at the hub, spinning around local X. Motorcycles (BIKES) have two,
Wheel_F and Wheel_R, and carry their rider in the Body mesh (material Suit).
"""

import math
import os
import random
import sys

import bmesh
import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import human  # noqa: E402  (posed MakeHuman bodies for riders and cockpit hands)
from mathutils import Matrix, Vector
from mathutils.bvhtree import BVHTree

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_DIR = os.path.join(ROOT, "assets", "vehicles")
PREVIEW_DIR = os.path.join(ROOT, "previews")

# ---------------------------------------------------------------------------
# Vehicle specs. t runs 0 (rear bumper) -> 1 (front bumper).
# belt: list of (t, z) beltline keys; zb: underside keys; cabin keys in t.
# ---------------------------------------------------------------------------

def spec(**kw):
    base = dict(
        L=4.5, W=1.88, wb=2.70, wb_shift=0.0, wr=0.34, tw=0.24, rim=0.68,
        clr=0.16, roof=1.36, crown=0.035,
        cab_rear=0.18, rw_top=0.33, ws_top=0.56, cab_front=0.68,
        bpillar=True, tumble=1.0, roof_w=0.70,
        halfw=[(0, .86), (.06, .96), (.18, 1.0), (.82, 1.0), (.94, .93), (1, .78)],
        belt=None, zb=None,
        tail="bar", head="slim", exhaust=2, spokes=5, paint=(0.6, 0.6, 0.6),
        bed=False, box=None, mirrors=True, stations=56, doors=4, trunk=False,
        chrome_belt=False, plate=True,
        flare=0.028, spoiler=None, splitter=False, fins=False, vents=False,
        side_intake=False, two_tone=False, kit=False, twin_spokes=False,
    )
    base.update(kw)
    clr = base["clr"]
    if base["zb"] is None:
        base["zb"] = [(0, clr + .22), (.04, clr + .07), (.12, clr), (.88, clr),
                      (.965, clr + .05), (1, clr + .13)]
    # Modern proportions: taller, blunter nose and bigger wheels.
    if base["belt"] and not base["box"]:
        base["belt"] = [(t, z + (0.075 * (t - 0.82) / 0.18 if t > 0.82 else 0.0)) for t, z in base["belt"]]
    base["wr"] *= 1.06
    base["roof_w"] = min(0.84, base["roof_w"] + 0.07)
    return base


CARS = {
    # ---- player cars ------------------------------------------------------
    "kestrel": spec(doors=2, kit=True,   # hot hatch
        L=4.06, W=1.82, wb=2.58, wr=0.34, tw=0.26, rim=0.72, roof=1.40, clr=0.13,
        cab_rear=0.05, rw_top=0.16, ws_top=0.56, cab_front=0.71,
        belt=[(0, .86), (.05, .93), (.3, .92), (.7, .86), (.9, .80), (1, .66)],
        tail="pair", paint=(0.85, 0.12, 0.08), spokes=6, roof_w=0.72,
        flare=0.05, spoiler="lip", splitter=True, exhaust=-2, two_tone=True),
    "vanta": spec(doors=2, trunk=True, kit=True,   # sport coupe (starter)
        L=4.48, W=1.92, wb=2.66, wr=0.35, tw=0.27, rim=0.74, roof=1.25, clr=0.12,
        cab_rear=0.17, rw_top=0.37, ws_top=0.555, cab_front=0.665,
        belt=[(0, .83), (.08, .90), (.35, .86), (.66, .79), (.9, .70), (1, .58)],
        paint=(0.06, 0.20, 0.55), spokes=5, twin_spokes=True,
        flare=0.05, spoiler="duck", splitter=True, fins=True, two_tone=True),
    "meridian": spec(doors=4, trunk=True, chrome_belt=True, kit=True,   # super-saloon
        L=4.86, W=1.89, wb=2.92, wr=0.355, tw=0.27, rim=0.74, roof=1.42, clr=0.13,
        cab_rear=0.19, rw_top=0.31, ws_top=0.585, cab_front=0.70,
        belt=[(0, .90), (.08, .96), (.3, .95), (.7, .88), (.9, .81), (1, .68)],
        paint=(0.12, 0.12, 0.13), spokes=10, tail="bar", exhaust=4,
        flare=0.04, spoiler="duck", splitter=True, fins=True),
    "brute": spec(doors=2, trunk=True, kit=True,   # muscle car, long hood
        L=4.78, W=1.96, wb=2.80, wr=0.365, tw=0.30, rim=0.72, roof=1.30, clr=0.13,
        cab_rear=0.20, rw_top=0.35, ws_top=0.52, cab_front=0.615,
        belt=[(0, .88), (.06, .94), (.4, .90), (.62, .86), (.92, .82), (1, .72)],
        tail="pair", paint=(0.90, 0.55, 0.05), spokes=5, exhaust=4,
        flare=0.055, spoiler="duck", vents=True, splitter=True, two_tone=True),
    "halcyon": spec(doors=2, trunk=False, kit=True,   # fastback grand tourer
        L=4.76, W=1.97, wb=2.84, wr=0.36, tw=0.29, rim=0.74, roof=1.23, clr=0.12,
        cab_rear=0.12, rw_top=0.40, ws_top=0.53, cab_front=0.615,
        belt=[(0, .82), (.06, .88), (.35, .84), (.62, .80), (.9, .72), (1, .60)],
        tail="bar", paint=(0.05, 0.22, 0.17), spokes=10, twin_spokes=True, exhaust=4,
        flare=0.05, spoiler="duck", splitter=True, fins=True, vents=True),
    "solstice": spec(doors=2, kit=True,   # mid-engine supercar
        L=4.56, W=2.02, wb=2.70, wb_shift=-0.05, wr=0.355, tw=0.30, rim=0.76, roof=1.13,
        clr=0.10, crown=0.03,
        cab_rear=0.30, rw_top=0.43, ws_top=0.53, cab_front=0.67,
        halfw=[(0, .90), (.05, .98), (.2, 1.0), (.5, .965), (.7, 1.0), (.86, .99), (.95, .92), (1, .74)],
        belt=[(0, .82), (.06, .86), (.3, .80), (.6, .74), (.79, .80), (.92, .66), (1, .50)],
        zb=[(0, .36), (.04, .19), (.12, .11), (.9, .11), (.97, .14), (1, .24)],
        paint=(0.80, 0.80, 0.82), spokes=10, roof_w=0.66, tail="bar",
        flare=0.06, spoiler="duck", side_intake=True, splitter=True, fins=True, two_tone=True),
    "vortex": spec(doors=2, kit=True,   # winged hypercar
        L=4.72, W=2.08, wb=2.76, wb_shift=-0.06, wr=0.36, tw=0.32, rim=0.77, roof=1.09,
        clr=0.09, crown=0.03,
        cab_rear=0.34, rw_top=0.45, ws_top=0.545, cab_front=0.68,
        halfw=[(0, .92), (.05, .99), (.2, 1.0), (.5, .955), (.7, 1.0), (.86, .99), (.95, .91), (1, .72)],
        belt=[(0, .80), (.06, .84), (.3, .80), (.6, .72), (.79, .79), (.92, .63), (1, .47)],
        zb=[(0, .33), (.04, .17), (.12, .10), (.9, .10), (.97, .13), (1, .22)],
        paint=(0.95, 0.38, 0.05), spokes=6, twin_spokes=True, roof_w=0.62, tail="bar",
        exhaust=-2, flare=0.07, spoiler="wing", side_intake=True, splitter=True, fins=True,
        two_tone=True),
    # ---- traffic ----------------------------------------------------------
    "t_sedan": spec(doors=4, trunk=True, 
        L=4.65, W=1.80, wb=2.75, wr=0.33, roof=1.47, clr=0.16,
        cab_rear=0.20, rw_top=0.32, ws_top=0.60, cab_front=0.71,
        belt=[(0, .90), (.08, .96), (.3, .95), (.7, .90), (.9, .84), (1, .72)],
        tail="pair", paint=(0.75, 0.76, 0.78), spokes=6, exhaust=1),
    "t_hatch": spec(
        L=3.95, W=1.74, wb=2.50, wr=0.31, roof=1.48, clr=0.15,
        cab_rear=0.05, rw_top=0.15, ws_top=0.58, cab_front=0.72,
        belt=[(0, .88), (.05, .95), (.3, .94), (.7, .90), (.9, .84), (1, .70)],
        tail="pair", paint=(0.20, 0.42, 0.30), spokes=0, exhaust=1),
    "t_suv": spec(
        L=4.75, W=1.93, wb=2.85, wr=0.38, tw=0.26, roof=1.76, clr=0.24,
        cab_rear=0.03, rw_top=0.08, ws_top=0.63, cab_front=0.735, roof_w=0.76,
        belt=[(0, 1.08), (.05, 1.12), (.3, 1.12), (.7, 1.07), (.9, 1.02), (1, .90)],
        tail="pair", paint=(0.10, 0.11, 0.12), spokes=6, exhaust=1),
    "t_van": spec(doors=2, 
        L=5.25, W=2.00, wb=3.30, wb_shift=0.1, wr=0.36, roof=2.30, clr=0.20,
        cab_rear=0.005, rw_top=0.012, ws_top=0.80, cab_front=0.875, roof_w=0.82,
        bpillar=False,
        halfw=[(0, .97), (.04, 1.0), (.9, 1.0), (.96, .95), (1, .84)],
        belt=[(0, 1.10), (.05, 1.12), (.7, 1.12), (.9, 1.04), (1, .92)],
        zb=[(0, .40), (.03, .24), (.1, .20), (.9, .20), (.97, .26), (1, .40)],
        tail="pillar", paint=(0.92, 0.92, 0.90), spokes=0, exhaust=0),
    "t_pickup": spec(
        L=5.35, W=1.96, wb=3.30, wr=0.39, tw=0.27, roof=1.86, clr=0.26,
        cab_rear=0.36, rw_top=0.375, ws_top=0.64, cab_front=0.73, roof_w=0.80,
        belt=[(0, 1.12), (.05, 1.17), (.4, 1.16), (.7, 1.12), (.9, 1.08), (1, .96)],
        bed=True, tail="pillar", paint=(0.55, 0.10, 0.08), spokes=6, exhaust=1),
    "t_truck": spec(doors=2,   # box truck: short cab + cargo box
        L=7.6, W=2.30, wb=4.4, wb_shift=-0.2, wr=0.48, tw=0.30, roof=2.55, clr=0.38,
        cab_rear=0.68, rw_top=0.69, ws_top=0.86, cab_front=0.92, roof_w=0.84,
        bpillar=False,
        halfw=[(0, 1.0), (.7, 1.0), (.95, .97), (1, .88)],
        belt=[(0, 1.35), (.7, 1.35), (.9, 1.32), (1, 1.22)],
        zb=[(0, .62), (.02, .55), (.1, .52), (.9, .50), (.97, .55), (1, .70)],
        box=dict(t0=0.0, t1=0.665, h=3.45), tail="pillar", paint=(0.95, 0.95, 0.95),
        spokes=0, exhaust=0, mirrors=True),
    "t_bus": spec(doors=2,   # coach: one long glass band, near-vertical ends
        L=12.0, W=2.50, wb=6.0, wb_shift=0.4, wr=0.52, tw=0.32, roof=3.25, clr=0.40,
        cab_rear=0.006, rw_top=0.012, ws_top=0.955, cab_front=0.985, roof_w=0.92,
        bpillar=False, stations=72, pillar_every=7,
        halfw=[(0, .98), (.03, 1.0), (.97, 1.0), (1, .95)],
        belt=[(0, 1.80), (.5, 1.80), (.9, 1.74), (1, 1.62)],
        zb=[(0, .58), (.02, .44), (.1, .42), (.9, .42), (.98, .44), (1, .58)],
        tail="pillar", paint=(0.92, 0.92, 0.90), spokes=0, exhaust=0),
}

# ---------------------------------------------------------------------------
# Small math helpers
# ---------------------------------------------------------------------------

def pchip(keys, t):
    """Monotone cubic interpolation (no overshoot) through (t, v) keys."""
    xs = [k[0] for k in keys]
    ys = [k[1] for k in keys]
    if t <= xs[0]:
        return ys[0]
    if t >= xs[-1]:
        return ys[-1]
    n = len(xs)
    h = [xs[i + 1] - xs[i] for i in range(n - 1)]
    d = [(ys[i + 1] - ys[i]) / h[i] for i in range(n - 1)]
    m = [0.0] * n
    m[0], m[-1] = d[0], d[-1]
    for i in range(1, n - 1):
        if d[i - 1] * d[i] <= 0:
            m[i] = 0.0
        else:
            w1 = 2 * h[i] + h[i - 1]
            w2 = h[i] + 2 * h[i - 1]
            m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
    i = max(j for j in range(n - 1) if xs[j] <= t)
    s = (t - xs[i]) / h[i]
    h00 = 2 * s ** 3 - 3 * s ** 2 + 1
    h10 = s ** 3 - 2 * s ** 2 + s
    h01 = -2 * s ** 3 + 3 * s ** 2
    h11 = s ** 3 - s ** 2
    return h00 * ys[i] + h10 * h[i] * m[i] + h01 * ys[i + 1] + h11 * h[i] * m[i + 1]


def lerp(a, b, s):
    return a + (b - a) * s


def clamp01(v):
    return max(0.0, min(1.0, v))


# ---------------------------------------------------------------------------
# Materials
# ---------------------------------------------------------------------------

def make_material(name, color, metallic=0.0, rough=0.5, emit=None, emit_str=0.0, coat=0.0):
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Coat Weight"].default_value = coat
    if emit:
        bsdf.inputs["Emission Color"].default_value = (*emit, 1.0)
        bsdf.inputs["Emission Strength"].default_value = emit_str
    return mat


def materials_for(paint):
    return {
        "Paint": make_material("Paint", paint, 0.55, 0.28, coat=1.0),
        "Glass": make_material("Glass", (0.015, 0.02, 0.028), 0.0, 0.04, coat=0.0),
        "Trim": make_material("Trim", (0.018, 0.018, 0.02), 0.0, 0.55),
        "Chrome": make_material("Chrome", (0.85, 0.85, 0.86), 1.0, 0.12),
        "Tire": make_material("Tire", (0.025, 0.025, 0.027), 0.0, 0.88),
        "Rim": make_material("Rim", (0.62, 0.63, 0.65), 1.0, 0.28),
        "Headlight": make_material("Headlight", (0.85, 0.88, 0.95), 0.2, 0.08,
                                   emit=(1.0, 0.97, 0.9), emit_str=1.5),
        "Taillight": make_material("Taillight", (0.30, 0.01, 0.01), 0.0, 0.15,
                                   emit=(1.0, 0.04, 0.02), emit_str=1.2),
        "TailLens": make_material("TailLens", (0.22, 0.012, 0.012), 0.0, 0.06,
                                  emit=(0.6, 0.02, 0.01), emit_str=0.25),
        "Plate": make_material("Plate", (0.85, 0.85, 0.82), 0.0, 0.35),
        "Gloss": make_material("Gloss", (0.012, 0.012, 0.014), 0.2, 0.08, coat=1.0),
        "Caliper": make_material("Caliper", (0.75, 0.04, 0.03), 0.0, 0.3, coat=0.6),
        "Suit": make_material("Suit", (0.045, 0.045, 0.05), 0.0, 0.62),
        "Accent": make_material("Accent", (0.86, 0.86, 0.87), 0.0, 0.45),
        "Cracked": make_material("Cracked", (0.52, 0.56, 0.58), 0.1, 0.35),
        "Livery": make_material("Livery", (0.03, 0.12, 0.48), 0.3, 0.3, coat=1.0),
        "SirenRed": make_material("SirenRed", (0.9, 0.05, 0.04), 0.0, 0.2, emit=(1.0, 0.05, 0.03), emit_str=4.0),
        "SirenBlue": make_material("SirenBlue", (0.05, 0.2, 1.0), 0.0, 0.2, emit=(0.1, 0.3, 1.0), emit_str=4.0),
        "Gold": make_material("Gold", (0.85, 0.58, 0.16), 1.0, 0.25),
        "Dash": make_material("Dash", (0.03, 0.03, 0.034), 0.0, 0.8),
        "Leather": make_material("Leather", (0.025, 0.025, 0.027), 0.0, 0.55),
        "Glove": make_material("Glove", (0.26, 0.16, 0.09), 0.0, 0.65),
        "Dial": make_material("Dial", (0.015, 0.015, 0.02), 0.0, 0.3, emit=(0.15, 0.45, 0.8), emit_str=0.4),
        "Screen": make_material("Screen", (0.01, 0.015, 0.02), 0.0, 0.08, emit=(0.06, 0.14, 0.24), emit_str=0.35),
        "Headliner": make_material("Headliner", (0.07, 0.07, 0.075), 0.0, 0.95),
        "Mirror": make_material("Mirror", (0.8, 0.82, 0.85), 1.0, 0.03),
        "Shield": shield_material(),
        "Skin": make_material("Skin", (0.62, 0.43, 0.33), 0.0, 0.5),
    }


MAT_ORDER = ["Paint", "Glass", "Trim", "Chrome", "Tire", "Rim", "Headlight", "Taillight",
             "TailLens", "Plate", "Gloss", "Caliper", "Suit", "Accent", "Cracked", "Livery", "SirenRed",
             "SirenBlue", "Gold", "Dash", "Leather", "Glove", "Dial", "Screen", "Headliner", "Mirror", "Shield", "Skin"]


def shield_material():
    """See-through tinted screen for the bike cockpit."""
    mat = make_material("Shield", (0.08, 0.1, 0.12), 0.0, 0.03)
    mat.node_tree.nodes.get("Principled BSDF").inputs["Alpha"].default_value = 0.28
    try:
        mat.surface_render_method = "BLENDED"
    except AttributeError:
        mat.blend_method = "BLEND"
    return mat


class MeshBuilder:
    """Accumulates verts/faces with named materials, then builds one object."""

    def __init__(self):
        self.verts = []
        self.faces = []  # (indices, material name)
        self.creases = []  # (vert a, vert b, crease 0..1)

    def v(self, co):
        self.verts.append(Vector(co))
        return len(self.verts) - 1

    def f(self, idx, mat):
        self.faces.append((tuple(idx), mat))

    def build(self, name, mats, smooth=True):
        mesh = bpy.data.meshes.new(name)
        used = [m for m in MAT_ORDER if any(fm == m for _, fm in self.faces)]
        mesh.from_pydata([tuple(v) for v in self.verts], [], [f for f, _ in self.faces])
        for m in used:
            mesh.materials.append(mats[m])
        for poly, (_, m) in zip(mesh.polygons, self.faces):
            poly.material_index = used.index(m)
            poly.use_smooth = smooth
        mesh.validate()
        mesh.update()
        if self.creases:
            bm = bmesh.new()
            bm.from_mesh(mesh)
            bm.verts.ensure_lookup_table()
            layer = bm.edges.layers.float.get("crease_edge") or bm.edges.layers.float.new("crease_edge")
            for a, b, c in self.creases:
                e = bm.edges.get((bm.verts[a], bm.verts[b]))
                if e:
                    e[layer] = c
            bm.to_mesh(mesh)
            bm.free()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        return obj

    def box(self, center, size, mat, rot=None):
        cx, cy, cz = center
        sx, sy, sz = (s / 2 for s in size)
        rot = rot or Matrix.Identity(3)
        corners = []
        for dz in (-1, 1):
            for dy in (-1, 1):
                for dx in (-1, 1):
                    p = rot @ Vector((dx * sx, dy * sy, dz * sz))
                    corners.append(self.v((cx + p.x, cy + p.y, cz + p.z)))
        c = corners
        for quad in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
            self.f([c[q] for q in quad], mat)

    def revolve(self, profile, segs, mat, offset=(0, 0, 0), cap_end=False):
        """Revolve (radius, axial) profile around the X axis."""
        ox, oy, oz = offset
        rings = []
        for r, ax in profile:
            ring = []
            for s in range(segs):
                a = 2 * math.pi * s / segs
                ring.append(self.v((ox + ax, oy + r * math.cos(a), oz + r * math.sin(a))))
            rings.append(ring)
        for i in range(len(rings) - 1):
            for s in range(segs):
                n = (s + 1) % segs
                self.f([rings[i][s], rings[i][n], rings[i + 1][n], rings[i + 1][s]], mat)
        if cap_end:
            self.f(list(reversed(rings[-1])), mat)
        return rings


# ---------------------------------------------------------------------------
# Body
# ---------------------------------------------------------------------------

def roof_z(sp, t):
    belt = pchip(sp["belt"], t)
    base = belt + sp["crown"]
    R = sp["roof"]
    cr, rw, ws, cf = sp["cab_rear"], sp["rw_top"], sp["ws_top"], sp["cab_front"]
    if t >= cf or t <= cr:
        return base
    if t >= ws:  # windshield: slightly convex rake
        s = (t - ws) / (cf - ws)
        end = pchip(sp["belt"], cf) + sp["crown"]
        return lerp(R, end, s) + 0.035 * math.sin(math.pi * s) * (R - end)
    if t <= rw:  # rear window / hatch
        s = (rw - t) / max(rw - cr, 1e-4)
        end = pchip(sp["belt"], cr) + sp["crown"]
        return lerp(R, end, s ** 1.1) + 0.05 * math.sin(math.pi * s) * (R - end)
    s = (t - rw) / (ws - rw)
    return R + 0.025 * math.sin(math.pi * s)


def section(sp, t):
    """Half cross-section points p0..p10 as (x, z)."""
    L, W = sp["L"], sp["W"]
    h = pchip(sp["halfw"], t) * W / 2
    for wy in (sp["wb"] / 2 + sp["wb_shift"], -sp["wb"] / 2 + sp["wb_shift"]):
        wt = 0.5 + wy / L
        h *= 1.0 + sp["flare"] * math.exp(-((t - wt) / 0.075) ** 2)
    b = pchip(sp["zb"], t)
    e = pchip(sp["belt"], t)
    r = roof_z(sp, t)
    hood = e + sp["crown"]
    span = max(sp["roof"] - hood, 0.05)
    c = clamp01((r - hood) / span) ** 0.6
    rw = sp["roof_w"]
    pts = [
        (0.0, b), (0.80 * h, b), (0.975 * h, b + 0.06), (1.0 * h, b + 0.42 * (e - b)),
        (1.0 * h, b + 0.78 * (e - b)), (0.965 * h, e),
    ]
    hood_x = [0.90, 0.72, 0.52, 0.28, 0.0]
    hood_z = [e + 0.012, e + 0.6 * sp["crown"], e + 0.85 * sp["crown"], e + 0.95 * sp["crown"], hood]
    tum = 1.0 - 0.03 * sp["tumble"]
    cab_x = [0.925, lerp(0.925, rw + 0.10, 0.45) * tum + 0.06 * (1 - tum), rw + 0.10, rw, 0.0]
    cab_z = [e + 0.015, e + 0.52 * (r - e), r - 0.055, r - 0.012, r]
    for hx, hz, cx, cz in zip(hood_x, hood_z, cab_x, cab_z):
        pts.append((lerp(hx, cx, c) * h, lerp(hz, cz, c)))
    return pts


def station_ts(sp):
    n = sp["stations"]
    keys = {sp["cab_rear"], sp["rw_top"], sp["ws_top"], sp["cab_front"]}
    mid = (sp["rw_top"] + sp["ws_top"]) / 2
    if sp["bpillar"]:
        keys |= {mid - 0.012, mid + 0.012}
    if sp["box"]:
        keys |= {sp["box"]["t1"]}
    keys |= {0.012, 0.988}
    ts = sorted(set([i / (n - 1) for i in range(n)]) | keys)
    out = []
    for t in ts:  # drop near-duplicates but always keep key stations
        if out and t - out[-1] < 0.006 and t not in keys:
            continue
        if out and t - out[-1] < 0.006 and out[-1] not in keys:
            out[-1] = t
            continue
        out.append(t)
    return out


def face_material(sp, t0, t1, k):
    tm = (t0 + t1) / 2
    cr, rw, ws, cf = sp["cab_rear"], sp["rw_top"], sp["ws_top"], sp["cab_front"]
    mid = (rw + ws) / 2
    if sp["box"] and tm < sp["box"]["t1"]:
        return "Trim" if k >= 6 else "Paint"
    if sp["bed"] and tm < cr and k >= 6:
        return "Trim"
    if k in (0, 1):  # underside + black sill
        return "Trim"
    if k == 5 and cr + 0.015 < tm < cf - 0.02:  # window seal / belt moulding
        return "Chrome" if sp["chrome_belt"] else "Trim"
    pillar = "Gloss" if sp["two_tone"] else "Paint"
    if k in (6, 7) and not sp["box"] and (cr <= tm <= rw or ws <= tm <= cf):
        if not (cr + 0.015 < tm < cf - 0.02) or tm <= rw:
            return pillar  # C/D pillars beside the rear glass: body colour, like real cars
    if k in (6, 7):  # side glass band
        if cr + 0.015 < tm < cf - 0.02:
            if sp["bpillar"] and mid - 0.012 <= tm <= mid + 0.012:
                return "Trim"
            every = sp.get("pillar_every", 0)  # coach: a pillar between each window
            if every and int(tm * (sp["stations"] - 1)) % every == 0:
                return "Trim"
            return "Glass"
        return "Paint"
    if k == 9:  # windshield / rear window centre
        if ws <= tm <= cf or cr <= tm <= rw:
            return "Glass"
    if k == 8 and ws <= tm <= cf:  # A-pillars: gloss black on sporty cars
        return "Gloss" if sp["kit"] or sp["two_tone"] else "Paint"
    if k == 8 and cr <= tm <= rw:
        return pillar
    if sp["two_tone"] and k in (8, 9) and rw < tm < ws:  # gloss black roof
        return "Gloss"
    return "Paint"


def build_body(sp, mats):
    L = sp["L"]
    ts = station_ts(sp)
    mb = MeshBuilder()
    rings = []
    for t in ts:
        half = section(sp, t)
        y = -L / 2 + t * L
        loop = [(x, z) for x, z in half] + [(-x, z) for x, z in reversed(half[1:-1])]
        rings.append([mb.v((x, y, z)) for x, z in loop])
    npts = len(rings[0])
    nhalf = 11

    def k_of(j):  # loop index -> half-section face index
        return j if j < nhalf - 1 else (npts - 1 - j)

    for i in range(len(rings) - 1):
        for j in range(npts):
            jn = (j + 1) % npts
            mat = face_material(sp, ts[i], ts[i + 1], k_of(j))
            mb.f([rings[i][j], rings[i][jn], rings[i + 1][jn], rings[i + 1][j]], mat)
        # character lines: sill, shoulder, glass line, roof rail
        for k, c in ((2, 0.5), (5, 0.75), (6, 0.9), (8, 0.55)):
            for j in (k, npts - k):
                mb.creases.append((rings[i][j], rings[i + 1][j], c))
    for ring in (rings[0], rings[-1]):
        for j in range(npts):
            mb.creases.append((ring[j], ring[(j + 1) % npts], 0.55))
    # end caps: two inset rings then an n-gon, so subdivision keeps a firm edge
    for ring, sign in ((rings[0], -1), (rings[-1], 1)):
        cen = sum((mb.verts[v] for v in ring), Vector()) / len(ring)
        prev = ring
        # more, gentler rings: a small centre n-gon keeps subdivision from
        # pinching the tail panel into V-shaped creases
        for scale, push in ((0.985, 0.007), (0.90, 0.016), (0.74, 0.021), (0.52, 0.023), (0.26, 0.024)):
            inner = []
            for v in ring:
                p = mb.verts[v]
                q = cen + (p - cen) * scale
                q.y = p.y + sign * push
                inner.append(mb.v(q))
            for j in range(npts):
                jn = (j + 1) % npts
                quad = [prev[j], prev[jn], inner[jn], inner[j]]
                mb.f(quad if sign > 0 else list(reversed(quad)), "Paint")
            prev = inner
        mb.f(prev if sign < 0 else list(reversed(prev)), "Paint")
        mb.flat_last = getattr(mb, "flat_last", []) + [len(mb.faces) - 1]
    obj = mb.build("Body", mats)
    # flat-shade the planar cap centres (no subdivision shading pinch)
    for fi in mb.flat_last:
        obj.data.polygons[fi].use_smooth = False
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()
    apply_modifier(obj, "SUBSURF", levels=1)
    return obj


def apply_modifier(obj, kind, **props):
    mod = obj.modifiers.new(kind.lower(), kind)
    for k, v in props.items():
        setattr(mod, k, v)
    if kind == "SUBSURF":
        mod.render_levels = props.get("levels", 1)
    bpy.context.view_layer.objects.active = obj
    for o in bpy.context.selected_objects:
        o.select_set(False)
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=mod.name)


def wheel_positions(sp):
    W, wb, wr, tw = sp["W"], sp["wb"], sp["wr"], sp["tw"]
    out = []
    for name, sy, sx in (("Wheel_FL", 1, -1), ("Wheel_FR", 1, 1), ("Wheel_RL", -1, -1), ("Wheel_RR", -1, 1)):
        t = 0.5 + (sy * wb / 2 + sp["wb_shift"]) / sp["L"]
        h = pchip(sp["halfw"], t) * W / 2
        x = sx * (h - tw / 2 - 0.035)
        out.append((name, Vector((x, sy * wb / 2 + sp["wb_shift"], wr))))
    return out


def cut_arches(body, sp, mats):
    wr, tw = sp["wr"], sp["tw"]
    for _, pos in wheel_positions(sp):
        mb = MeshBuilder()
        r = wr + 0.042
        side = 1 if pos.x > 0 else -1
        x_in = pos.x - side * (tw / 2 + 0.06)
        x_out = pos.x + side * 0.6
        prof = [(0.0001, x_in), (r, x_in), (r, x_out), (0.0001, x_out)]
        mb.revolve(prof, 40, "Trim", offset=(0, pos.y, pos.z))
        cutter = mb.build("ArchCutter", mats, smooth=False)
        bm = bmesh.new()
        bm.from_mesh(cutter.data)
        bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(cutter.data)
        bm.free()
        mod = body.modifiers.new("arch", "BOOLEAN")
        mod.operation = "DIFFERENCE"
        mod.solver = "EXACT"
        mod.material_mode = "TRANSFER"
        mod.object = cutter
        bpy.context.view_layer.objects.active = body
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cutter, do_unlink=True)


def cut_panel_gaps(body, sp, mats):
    """Thin dark grooves for door, hood and boot shut lines."""
    L, W = sp["L"], sp["W"]
    gap = 0.007
    mb = MeshBuilder()

    def y_of(t):
        return -L / 2 + t * L

    zb_mid = pchip(sp["zb"], 0.5)
    cr, rw, ws, cf = sp["cab_rear"], sp["rw_top"], sp["ws_top"], sp["cab_front"]
    door_lines = []
    if sp["doors"] == 4:
        door_lines = [cf - 0.012, (rw + ws) / 2, cr + 0.05]
    elif sp["doors"] == 2:
        door_lines = [cf - 0.012, max(cr + 0.04, rw - 0.03)]
    if sp["box"]:
        door_lines = [cf - 0.012, sp["box"]["t1"] + 0.02]
    for t in door_lines:
        belt = pchip(sp["belt"], t)
        z0, z1 = zb_mid + 0.10, belt - 0.005
        for side in (-1, 1):
            h = pchip(sp["halfw"], t) * W / 2
            mb.box((side * (h + 0.05), y_of(t), (z0 + z1) / 2), (0.12, gap, z1 - z0), "Trim")
    # hood shut line just ahead of the windshield, boot line behind the rear glass
    lids = [cf + 0.03]
    if sp["trunk"]:
        lids.append(cr - 0.02)
    for t in lids:
        if t <= 0.02 or t >= 0.98:
            continue
        belt = pchip(sp["belt"], t)
        h = pchip(sp["halfw"], t) * W / 2
        mb.box((0, y_of(t), belt + 0.08), (2 * h * 0.86, gap, 0.16), "Trim")
    if not mb.faces:
        return
    cutter = mb.build("GapCutter", mats, smooth=False)
    mod = body.modifiers.new("gaps", "BOOLEAN")
    mod.operation = "DIFFERENCE"
    mod.solver = "EXACT"
    mod.material_mode = "TRANSFER"
    mod.object = cutter
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.modifier_apply(modifier=mod.name)
    bpy.data.objects.remove(cutter, do_unlink=True)


# ---------------------------------------------------------------------------
# Details that hug the body surface
# ---------------------------------------------------------------------------

class Surface:
    """Ray-casts against the finished body so details sit exactly on it."""

    def __init__(self, obj):
        dg = bpy.context.evaluated_depsgraph_get()
        self.tree = BVHTree.FromObject(obj, dg)

    def y_extent(self, x, z, front):
        sign = 1 if front else -1
        hit = self.tree.ray_cast(Vector((x, sign * 20.0, z)), Vector((0, -sign, 0)))
        return None if hit[0] is None else hit[0].y

    def x_extent(self, y, z, side):
        hit = self.tree.ray_cast(Vector((side * 5.0, y, z)), Vector((-side, 0, 0)))
        return None if hit[0] is None else hit[0].x


def ribbon(mb, surf, xs, z, height, front, mat, out=0.018, inset=0.05, curve=None):
    """Light/grille strip following the nose or tail surface."""
    sign = 1 if front else -1
    cols = []
    for x in xs:
        zz = z + (curve(x) if curve else 0.0)
        y = surf.y_extent(x, zz, front)
        if y is None:
            continue
        cols.append([
            mb.v((x, y + sign * out, zz + height / 2)),
            mb.v((x, y + sign * out, zz - height / 2)),
            mb.v((x, y - sign * inset, zz - height / 2)),
            mb.v((x, y - sign * inset, zz + height / 2)),
        ])
    if len(cols) < 2:
        return
    for i in range(len(cols) - 1):
        a, b = cols[i], cols[i + 1]
        for k in range(4):
            kn = (k + 1) % 4
            quad = [a[k], a[kn], b[kn], b[k]]
            mb.f(quad if not front else list(reversed(quad)), mat)
    mb.f(cols[0] if front else list(reversed(cols[0])), mat)
    mb.f(list(reversed(cols[-1])) if front else cols[-1], mat)


def build_kit(sp, surf, mb, hr, hf, zb_r, zb_f):
    """Aero and styling parts: splitter, diffuser fins, spoilers, vents, intakes."""
    L, W = sp["L"], sp["W"]

    def y_of(t):
        return -L / 2 + t * L

    if sp["splitter"]:
        y = surf.y_extent(0.0, zb_f + 0.05, True)
        if y is not None:
            mb.box((0, y - 0.02, zb_f + 0.012), (2 * 0.84 * hf, 0.16, 0.022), "Gloss")
    if sp["fins"]:
        for i in range(7):
            x = lerp(-0.5, 0.5, i / 6) * hr
            y = surf.y_extent(x, zb_r + 0.06, False)
            if y is not None:
                mb.box((x, y - 0.012, zb_r + 0.075), (0.012, 0.09, 0.085), "Gloss")
    sp_type = sp["spoiler"]
    if sp_type == "lip":  # roof spoiler over the hatch glass
        t = sp["rw_top"] - 0.005
        z = roof_z(sp, t) + 0.015
        w = pchip(sp["halfw"], t) * W * sp["roof_w"] * 1.05
        mb.box((0, y_of(t) - 0.12, z), (w, 0.30, 0.035), "Paint",
               rot=Matrix.Rotation(math.radians(-6), 3, "X"))
    elif sp_type == "duck":  # ducktail lip on the boot edge
        t = 0.035
        z = roof_z(sp, t) + 0.02
        w = pchip(sp["halfw"], t) * W * 0.86
        mb.box((0, y_of(t), z), (w, 0.20, 0.045), "Paint",
               rot=Matrix.Rotation(math.radians(-10), 3, "X"))
    elif sp_type == "wing":  # carbon rear wing on swan-neck uprights
        t = 0.08
        deck = roof_z(sp, t)
        y = y_of(t)
        span = pchip(sp["halfw"], t) * W * 0.96
        for sx in (-0.30, 0.30):
            mb.box((sx * span, y + 0.02, deck + 0.13), (0.035, 0.12, 0.26), "Gloss")
        mb.box((0, y, deck + 0.25), (span, 0.36, 0.04), "Gloss",
               rot=Matrix.Rotation(math.radians(-9), 3, "X"))
        for sx in (-0.5, 0.5):
            mb.box((sx * span, y, deck + 0.26), (0.02, 0.40, 0.14), "Gloss")
    if sp["vents"]:  # twin bonnet vents
        for sx in (-1, 1):
            t = 0.80
            z = roof_z(sp, t)
            mb.box((sx * 0.30 * hf, y_of(t), z + 0.004), (0.20, 0.36, 0.022), "Gloss")
    if sp["side_intake"]:  # dark intakes ahead of the rear wheels
        t = sp["cab_rear"] - 0.03
        zm = (pchip(sp["zb"], t) + pchip(sp["belt"], t)) / 2 + 0.03
        for sx in (-1, 1):
            x = surf.x_extent(y_of(t), zm, sx)
            if x is not None:
                mb.box((x - sx * 0.01, y_of(t), zm), (0.035, 0.46, 0.17), "Gloss",
                       rot=Matrix.Rotation(math.radians(-12 * sx), 3, "Z"))


def build_details(sp, body, mats):
    surf = Surface(body)
    W, L = sp["W"], sp["L"]
    hr = pchip(sp["halfw"], 0.02) * W / 2
    hf = pchip(sp["halfw"], 0.98) * W / 2
    belt_r = pchip(sp["belt"], 0.02)
    belt_f = pchip(sp["belt"], 0.98)
    zb_r = pchip(sp["zb"], 0.05)
    zb_f = pchip(sp["zb"], 0.95)
    mb = MeshBuilder()
    n = 14

    # --- tail lights: dark red lens with a lit inner strip ---
    tz = belt_r - 0.09
    if sp["tail"] == "bar":
        xs = [lerp(-0.86 * hr, 0.86 * hr, i / (n * 2)) for i in range(n * 2 + 1)]
        ribbon(mb, surf, xs, tz, 0.07, False, "TailLens", out=0.012)
        ribbon(mb, surf, xs, tz + 0.012, 0.018, False, "Taillight", out=0.016)
        for s in (-1, 1):
            xs = sorted(s * lerp(0.60 * hr, 0.88 * hr, i / 6) for i in range(7))
            ribbon(mb, surf, xs, tz - 0.045, 0.05, False, "Taillight", out=0.014)
    elif sp["tail"] == "pair":
        for s in (-1, 1):
            xs = sorted(s * lerp(0.46 * hr, 0.88 * hr, i / 8) for i in range(9))
            ribbon(mb, surf, xs, tz, 0.12, False, "TailLens", out=0.012)
            xs = sorted(s * lerp(0.52 * hr, 0.84 * hr, i / 6) for i in range(7))
            ribbon(mb, surf, xs, tz + 0.02, 0.022, False, "Taillight", out=0.016)
            ribbon(mb, surf, xs, tz - 0.028, 0.022, False, "Taillight", out=0.016)
    else:  # tall pillar lights (vans, trucks)
        for s in (-1, 1):
            xs = sorted(s * lerp(0.80 * hr, 0.92 * hr, i / 3) for i in range(4))
            zc = (zb_r + belt_r) / 2 + 0.05
            ribbon(mb, surf, xs, zc, 0.42, False, "TailLens", out=0.012)
            ribbon(mb, surf, xs, zc + 0.1, 0.08, False, "Taillight", out=0.016)
            ribbon(mb, surf, xs, zc - 0.1, 0.08, False, "Taillight", out=0.016)
    # rear diffuser / bumper insert
    xs = [lerp(-0.74 * hr, 0.74 * hr, i / (n * 2)) for i in range(n * 2 + 1)]
    ribbon(mb, surf, xs, zb_r + 0.06, 0.10, False, "Trim", out=0.01)
    # exhausts
    pipes = {0: [], 1: [0.45], 2: [-0.55, 0.55], 4: [-0.66, -0.50, 0.50, 0.66],
             -2: [-0.07, 0.07]}[sp["exhaust"]]
    rad = 0.052 if sp["kit"] else 0.046
    for e, fx in enumerate(pipes):
        x = fx * hr
        y = surf.y_extent(x, zb_r + 0.07, False)
        if y is None:
            continue
        prof = [(rad - 0.007, 0.0), (rad, 0.0), (rad, -0.09), (rad - 0.007, -0.09)]
        sub = MeshBuilder()
        sub.revolve(prof, 16, "Chrome")
        pipe = sub.build("Exhaust%d" % e, mats)
        pipe.rotation_euler = (0, 0, math.pi / 2)
        pipe.location = (x, y + 0.02, zb_r + 0.07)
        pipe.parent = body

    # --- headlights: chrome reflector housing, DRL strip and projector ---
    hz = belt_f - 0.09
    for s in (-1, 1):
        xs = sorted(s * lerp(0.42 * hf, 0.90 * hf, i / 10) for i in range(11))
        lift = (lambda x, s=s: 0.03 * ((abs(x) / hf - 0.42) / 0.48))
        tall = 0.075 if sp["head"] == "slim" else 0.12
        housing = "Gloss" if sp["kit"] else "Chrome"
        ribbon(mb, surf, xs, hz, tall, True, housing, out=0.008, curve=lift)
        ribbon(mb, surf, xs, hz + tall * 0.5 - 0.012, 0.014, True, "Headlight", out=0.013, curve=lift)
        if sp["kit"]:  # second LED line on the outer half: a two-stripe signature
            xs2 = sorted(s * lerp(0.66 * hf, 0.90 * hf, i / 6) for i in range(7))
            ribbon(mb, surf, xs2, hz - tall * 0.5 + 0.014, 0.012, True, "Headlight", out=0.013, curve=lift)
        for fx in ((0.55, 0.70) if sp["kit"] else (0.62,)):
            px = s * fx * hf
            py = surf.y_extent(px, hz, True)
            if py is not None:
                mb.box((px, py + 0.006, hz - 0.008), (0.055, 0.02, 0.04), "Headlight")
    # grille + lower intake
    xs = [lerp(-0.48 * hf, 0.48 * hf, i / 16) for i in range(17)]
    ribbon(mb, surf, xs, (zb_f + belt_f) / 2 - 0.01, 0.17, True, "Trim", out=0.006)
    xs = [lerp(-0.76 * hf, 0.76 * hf, i / 22) for i in range(23)]
    ribbon(mb, surf, xs, zb_f + 0.08, 0.09, True, "Trim", out=0.006)

    # --- body kit ---
    build_kit(sp, surf, mb, hr, hf, zb_r, zb_f)

    # --- number plates: white plate, dark frame and characters ---
    if sp["plate"]:
        rng = random.Random(len(sp["belt"]) * 31 + int(L * 100))
        for front, z in ((False, zb_r + 0.27), (True, zb_f + 0.16)):
            y = surf.y_extent(0.0, z, front)
            if y is None:
                continue
            sg = 1 if front else -1
            mb.box((0, y + sg * 0.004, z), (0.53, 0.012, 0.125), "Trim")
            mb.box((0, y + sg * 0.009, z), (0.50, 0.008, 0.105), "Plate")
            x = -0.20
            for c in range(7):
                if c == 2:
                    x += 0.03
                w = 0.036 if rng.random() > 0.3 else 0.026
                mb.box((x + w / 2, y + sg * 0.0135, z), (w * 0.8, 0.003, 0.064), "Trim")
                x += 0.056

    # --- door handles ---
    cr, rw, ws, cf = sp["cab_rear"], sp["rw_top"], sp["ws_top"], sp["cab_front"]
    handle_ts = [(rw + ws) / 2 + 0.03]
    if sp["doors"] == 4:
        handle_ts.append(cr + 0.08)
    if sp["box"]:
        handle_ts = [sp["box"]["t1"] + 0.05]
    for t in handle_ts:
        z = pchip(sp["belt"], t) - 0.085
        y = -L / 2 + t * L
        for s in (-1, 1):
            x = surf.x_extent(y, z, s)
            if x is not None:
                mb.box((x + s * 0.008, y, z), (0.022, 0.14, 0.028), "Chrome" if sp["chrome_belt"] else "Paint")

    # --- third brake light along the top of the rear glass ---
    if not sp["box"] and not sp["bed"]:
        z = roof_z(sp, sp["rw_top"]) - 0.035
        y = surf.y_extent(0.0, z, False)
        if y is not None:
            mb.box((0, y - 0.006, z), (0.36, 0.02, 0.022), "Taillight")

    # --- pickup bed wall caps / cargo box ---
    if sp["box"]:
        bx = sp["box"]
        y0 = -L / 2 + bx["t0"] * L + 0.02
        y1 = -L / 2 + bx["t1"] * L
        hw = W / 2 + 0.02
        z0 = pchip(sp["belt"], 0.3) - 0.02
        mb.box((0, (y0 + y1) / 2, (z0 + bx["h"]) / 2), (2 * hw, y1 - y0, bx["h"] - z0), "Paint")
        # rear doors seam + bumper bar
        mb.box((0, y0 - 0.006, (z0 + bx["h"]) / 2), (0.02, 0.02, bx["h"] - z0 - 0.1), "Trim")
        mb.box((0, y0 - 0.03, zb_r - 0.02), (2 * hw - 0.2, 0.10, 0.12), "Trim")
        for s in (-1, 1):
            mb.box((s * (hw - 0.08), y0 - 0.012, z0 + 0.25), (0.10, 0.03, 0.30), "Taillight")
    obj = mb.build("Details", mats, smooth=False)
    obj.parent = body
    build_rounded_parts(sp, surf, body, mats)
    if sp["box"]:
        apply_modifier(obj, "BEVEL", width=0.03, segments=2, limit_method="ANGLE")


def build_rounded_parts(sp, surf, body, mats):
    """Mirrors and the roof antenna: boxes with a heavy bevel, so they read as
    moulded parts instead of blocks."""
    W, L = sp["W"], sp["L"]
    mb = MeshBuilder()
    if sp["mirrors"]:
        t = sp["cab_front"] - 0.03
        z = pchip(sp["belt"], t) + 0.075
        y = -L / 2 + t * L
        for s in (-1, 1):
            x = surf.x_extent(y, z - 0.03, s) or s * W / 2
            yaw = Matrix.Rotation(math.radians(-8 * s), 3, "Z")
            mb.box((x + s * 0.02, y + 0.01, z - 0.025), (0.07, 0.06, 0.035), "Trim")   # arm
            mb.box((x + s * 0.09, y, z), (0.17, 0.11, 0.095), "Paint", rot=yaw)   # housing
            mb.box((x + s * 0.095, y - 0.058, z - 0.002), (0.145, 0.012, 0.075), "Chrome", rot=yaw)
    if not sp["box"] and sp["roof"] < 2.0:
        t = sp["rw_top"] + 0.035
        z = roof_z(sp, t)
        mb.box((0, -L / 2 + t * L, z + 0.018), (0.05, 0.16, 0.045), "Gloss",
               rot=Matrix.Rotation(math.radians(8), 3, "X"))
    if not mb.faces:
        return
    obj = mb.build("Rounded", mats, smooth=True)
    obj.parent = body
    apply_modifier(obj, "BEVEL", width=0.022, segments=3)


# ---------------------------------------------------------------------------
# Wheels
# ---------------------------------------------------------------------------

def build_wheel(sp, name, pos, mats):
    wr, tw = sp["wr"], sp["tw"]
    rr = wr * sp["rim"]
    seg = 36
    mb = MeshBuilder()
    w2 = tw / 2
    tire = [
        (rr * 0.98, -w2 + 0.01), (wr - 0.035, -w2), (wr - 0.008, -w2 + 0.025),
        (wr, -w2 + 0.06), (wr, w2 - 0.06), (wr - 0.008, w2 - 0.025), (wr - 0.035, w2),
        (rr * 0.98, w2 - 0.01),
    ]
    mb.revolve(tire, seg, "Tire")
    # rim barrel + lip
    barrel = [(rr * 0.98, w2 - 0.01), (rr, w2 - 0.005), (rr * 0.93, w2 - 0.02),
              (rr * 0.90, -w2 + 0.03), (rr * 0.98, -w2 + 0.01)]
    mb.revolve(barrel, seg, "Rim")
    # dark dish behind the spokes
    dish = [(rr * 0.91, w2 - 0.045), (rr * 0.25, w2 - 0.075), (0.001, w2 - 0.075)]
    mb.revolve(dish, seg, "Trim")
    face_x = w2 - 0.035
    if sp["spokes"] > 0:
        for s in range(sp["spokes"]):
            a = 2 * math.pi * s / sp["spokes"]
            rot = Matrix.Rotation(a, 3, "X")
            mid = (rr * 0.92 + 0.07) / 2
            c = rot @ Vector((0, mid, 0))
            width = 0.075 if sp["spokes"] <= 6 else 0.04
            if sp["twin_spokes"]:
                for off in (-0.13, 0.13):
                    r2 = Matrix.Rotation(a + off * 6 / max(sp["spokes"], 1), 3, "X")
                    c2 = r2 @ Vector((0, mid, 0))
                    mb.box((face_x, c2.y, c2.z), (0.03, rr * 0.92 - 0.06, width * 0.45), "Rim", rot=r2)
            else:
                mb.box((face_x, c.y, c.z), (0.03, rr * 0.92 - 0.06, width), "Rim", rot=rot)
    else:  # plain steel wheel with hubcap
        cap = [(rr * 0.88, w2 - 0.05), (rr * 0.8, w2 - 0.03), (rr * 0.3, w2 - 0.018), (0.001, w2 - 0.016)]
        mb.revolve(cap, seg, "Rim")
    hub = [(0.075, face_x - 0.02), (0.075, face_x + 0.02), (0.04, face_x + 0.03), (0.001, face_x + 0.03)]
    mb.revolve(hub, 16, "Chrome")
    # brake disc + caliper (visible through spokes)
    disc = [(rr * 0.78, -0.01), (rr * 0.78, 0.01)]
    mb.revolve(disc, seg, "Chrome", cap_end=True)
    mb.box((0.0, 0.0, rr * 0.62), (0.07, 0.16, 0.09), "Caliper" if sp["kit"] else "Trim")
    obj = mb.build(name, mats)
    obj.location = pos
    if pos.x < 0:
        obj.rotation_euler = (0, 0, math.pi)
    return obj


# ---------------------------------------------------------------------------
# Scene / export / preview
# ---------------------------------------------------------------------------

def clear_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def build_car(name, sp):
    clear_scene()
    mats = materials_for(sp["paint"])
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    body = build_body(sp, mats)
    cut_arches(body, sp, mats)
    cut_panel_gaps(body, sp, mats)
    body.data.set_sharp_from_angle(angle=math.radians(50))
    build_details(sp, body, mats)
    body.parent = root
    for wname, pos in wheel_positions(sp):
        w = build_wheel(sp, wname, pos, mats)
        w.parent = root
    return root


def bake_ao(sp):
    """Bakes ambient occlusion into a colour attribute on every mesh, with a
    ground plane present so wheel arches and sills darken naturally."""
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 48
    if scene.world is None:
        scene.world = bpy.data.worlds.new("BakeWorld")
    scene.world.light_settings.distance = 0.55
    bpy.ops.mesh.primitive_plane_add(size=sp["L"] * 3)
    ground = bpy.context.active_object
    meshes = [o for o in scene.objects if o.type == "MESH" and o != ground]
    for o in meshes:
        attr = o.data.color_attributes.new("AO", "BYTE_COLOR", "POINT")
        o.data.color_attributes.active_color = attr
    for o in meshes:
        for x in scene.objects:
            x.select_set(False)
        o.select_set(True)
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.bake(type="AO", target="VERTEX_COLORS")
    bpy.data.objects.remove(ground, do_unlink=True)


def export(root, path):
    for o in bpy.context.scene.objects:
        o.select_set(True)
    kw = dict(filepath=path, export_format="GLB", use_selection=True, export_apply=True, export_yup=True)
    try:
        bpy.ops.export_scene.gltf(**kw, export_vertex_color="ACTIVE")
    except TypeError:
        bpy.ops.export_scene.gltf(**kw, export_colors=True)


def render_previews(name, sp):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x, scene.render.resolution_y = 960, 540
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    hdri = os.path.join(ROOT, "..", "flowline_raw", "hdri", "sky_2k.hdr")
    if os.path.exists(hdri):
        env = world.node_tree.nodes.new("ShaderNodeTexEnvironment")
        env.image = bpy.data.images.load(hdri)
        world.node_tree.links.new(env.outputs["Color"], bg.inputs["Color"])
        bg.inputs[1].default_value = 1.0
    else:
        bg.inputs[0].default_value = (0.55, 0.65, 0.8, 1)
    scene.world = world
    # show the baked AO in previews, like the game does
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        if bsdf is None or bsdf.inputs["Base Color"].is_linked:
            continue
        ca = nt.nodes.new("ShaderNodeVertexColor")
        ca.layer_name = "AO"
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 1.0
        mix.inputs["A"].default_value = bsdf.inputs["Base Color"].default_value
        nt.links.new(ca.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    bpy.ops.mesh.primitive_plane_add(size=60)
    ground = bpy.context.active_object
    ground.data.materials.append(make_material("Ground", (0.12, 0.12, 0.13), 0, 0.8))
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    d = sp["L"] * (2.3 if sp["L"] < 3 else 1.45)  # bikes are short: stand further back
    shots = {"front": (math.radians(35), 1), "rear": (math.radians(200), 1), "chase": (math.radians(180), 0)}
    for shot, (ang, _) in shots.items():
        if shot == "chase":
            cam.location = (0, -sp["L"] * 1.6, sp["roof"] + 1.0)
        else:
            cam.location = (d * math.sin(ang), d * math.cos(ang), 1.6)
        target = Vector((0, 0, sp["roof"] * 0.45))
        direction = target - cam.location
        cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(PREVIEW_DIR, "%s_%s.png" % (name, shot))
        bpy.ops.render.render(write_still=True)


# ---------------------------------------------------------------------------
# Motorcycles. Built from lofted superellipse sections and tubes; y runs
# rear -> front, z up, the ground at z = 0. "sport" is a faired bike with a
# tucked rider, "naked" an upright roadster with a round headlight.
# ---------------------------------------------------------------------------

BIKES = {
    "raptor": dict(style="sport", L=2.05, roof=1.45, wr=0.30, spokes=3,
                   paint=(0.10, 0.45, 0.85)),
    "nomad": dict(style="naked", L=2.0, roof=1.75, wr=0.30, spokes=5,
                  paint=(0.20, 0.22, 0.20)),
    "t_moto": dict(style="naked", L=2.0, roof=1.75, wr=0.29, spokes=5,
                   paint=(0.55, 0.05, 0.05)),
}


def loft(mb, secs, mat, segs=18, n=2.4):
    """Closed tube through (y, zc, half_width, half_height) sections."""
    e = 2.0 / n
    rings = []
    for y, zc, hw, hh in secs:
        ring = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            c, s_ = math.cos(a), math.sin(a)
            x = hw * math.copysign(abs(c) ** e, c)
            z = zc + hh * math.copysign(abs(s_) ** e, s_)
            ring.append(mb.v((x, y, z)))
        rings.append(ring)
    for i in range(len(rings) - 1):
        for k in range(segs):
            m = (k + 1) % segs
            mb.f([rings[i][k], rings[i][m], rings[i + 1][m], rings[i + 1][k]], mat)
    for ring, (y, zc, _, _) in ((rings[0], secs[0]), (rings[-1], secs[-1])):
        c = mb.v((0, y, zc))
        for k in range(segs):
            mb.f([c, ring[(k + 1) % segs], ring[k]], mat)


def tube(mb, a, b, r, mat, r2=None, segs=10):
    """Capped cylinder from point a to point b (radius r, tapering to r2)."""
    a, b = Vector(a), Vector(b)
    d = (b - a).normalized()
    ref = Vector((0, 0, 1)) if abs(d.z) < 0.9 else Vector((1, 0, 0))
    u = d.cross(ref).normalized()
    w = d.cross(u)
    rings = []
    for p, rad in ((a, r), (b, r2 if r2 is not None else r)):
        rings.append([mb.v(p + (u * math.cos(2 * math.pi * k / segs) + w * math.sin(2 * math.pi * k / segs)) * rad)
                      for k in range(segs)])
    for k in range(segs):
        m = (k + 1) % segs
        mb.f([rings[0][k], rings[0][m], rings[1][m], rings[1][k]], mat)
    for ring, p in ((rings[0], a), (rings[1], b)):
        c = mb.v(p)
        for k in range(segs):
            mb.f([c, ring[(k + 1) % segs], ring[k]], mat)


def ellipsoid(mb, c, radii, mat, tilt=0.0, segs=16, rings=10):
    """Ellipsoid at c with radii (x, y, z); its y axis is tipped up by `tilt` radians about x."""
    rot = Matrix.Rotation(tilt, 3, "X")
    c = Vector(c)
    rx, ry, rz = radii
    top = mb.v(c + rot @ Vector((0, 0, rz)))
    bot = mb.v(c + rot @ Vector((0, 0, -rz)))
    loops = []
    for i in range(1, rings):
        ph = math.pi * i / rings - math.pi / 2
        loop = []
        for k in range(segs):
            a = 2 * math.pi * k / segs
            p = Vector((rx * math.cos(ph) * math.cos(a), ry * math.cos(ph) * math.sin(a), rz * math.sin(ph)))
            loop.append(mb.v(c + rot @ p))
        loops.append(loop)
    for k in range(segs):
        m = (k + 1) % segs
        mb.f([bot, loops[0][m], loops[0][k]], mat)
        mb.f([top, loops[-1][k], loops[-1][m]], mat)
    for i in range(len(loops) - 1):
        for k in range(segs):
            m = (k + 1) % segs
            mb.f([loops[i][k], loops[i][m], loops[i + 1][m], loops[i + 1][k]], mat)


def limb(mb, joints, radii, mat):
    """A chain of tubes with a ball at every joint so the bends look round."""
    for i in range(len(joints) - 1):
        tube(mb, joints[i], joints[i + 1], radii[i], mat, radii[i + 1])
    for j, r in zip(joints, radii):
        ellipsoid(mb, j, (r, r, r), mat, segs=10, rings=6)


def build_bike_body(sp, mats):
    mb = MeshBuilder()
    wr = sp["wr"]
    sport = sp["style"] == "sport"
    fy = 0.70 if sport else 0.68   # front axle
    ry = -0.70                     # rear axle
    head = (0, 0.50 if sport else 0.52, 0.93)  # steering head
    # Engine, tank, seat and tail.
    loft(mb, [(-0.30, 0.50, 0.12, 0.16), (-0.08, 0.49, 0.17, 0.22), (0.22, 0.48, 0.17, 0.21),
              (0.42, 0.52, 0.10, 0.14)], "Trim")
    loft(mb, [(-0.12, 0.89, 0.14, 0.07), (0.05, 0.95, 0.18, 0.11), (0.27, 0.97, 0.18, 0.11),
              (0.44, 0.93, 0.12, 0.08), (0.51, 0.90, 0.05, 0.04)], "Paint")
    loft(mb, [(-0.55 if sport else -0.6, 0.90, 0.11, 0.03), (-0.30, 0.89, 0.14, 0.04),
              (-0.10, 0.87, 0.14, 0.045)], "Trim")
    tail_end = -0.96 if sport else -0.80
    loft(mb, [(-0.12, 0.80, 0.15, 0.08), (-0.45, 0.85, 0.13, 0.07), (tail_end + 0.2, 0.91, 0.09, 0.06),
              (tail_end, 0.94, 0.04, 0.04)], "Paint")
    mb.box((0, tail_end + 0.03, 0.93), (0.11, 0.03, 0.04), "Taillight")
    tube(mb, (0, tail_end + 0.12, 0.86), (0, tail_end - 0.02, 0.68), 0.018, "Trim")
    mb.box((0, tail_end - 0.03, 0.62), (0.19, 0.008, 0.12), "Plate")
    if sport:
        # Belly pan and the full fairing with a screen and twin lamps.
        loft(mb, [(-0.05, 0.38, 0.15, 0.10), (0.25, 0.36, 0.19, 0.13), (0.50, 0.45, 0.17, 0.15),
                  (0.62, 0.56, 0.11, 0.11)], "Paint")
        loft(mb, [(0.18, 0.70, 0.20, 0.17), (0.45, 0.74, 0.23, 0.20), (0.70, 0.78, 0.20, 0.17),
                  (0.88, 0.80, 0.12, 0.10), (0.98, 0.80, 0.04, 0.04)], "Paint")
        loft(mb, [(0.48, 1.00, 0.16, 0.03), (0.68, 0.97, 0.15, 0.025), (0.86, 0.91, 0.09, 0.02)], "Glass")
        for sx in (-1, 1):
            mb.box((sx * 0.075, 0.955, 0.80), (0.075, 0.04, 0.035), "Headlight",
                   rot=Matrix.Rotation(sx * -0.35, 3, "Z"))
            tube(mb, (sx * 0.2, 0.70, 0.92), (sx * 0.27, 0.68, 0.98), 0.012, "Trim")
            mb.box((sx * 0.29, 0.68, 0.99), (0.10, 0.03, 0.055), "Trim")
    else:
        # Round lamp, no fairing, a little clock on the bars.
        loft(mb, [(0.60, 0.92, 0.10, 0.10), (0.70, 0.92, 0.105, 0.105), (0.75, 0.92, 0.095, 0.095)],
             "Trim", n=2.0)
        loft(mb, [(0.745, 0.92, 0.085, 0.085), (0.775, 0.92, 0.06, 0.06)], "Headlight", n=2.0)
        mb.box((0, 0.50, 1.05), (0.12, 0.06, 0.07), "Trim", rot=Matrix.Rotation(-0.5, 3, "X"))
        for sx in (-1, 1):
            # Exposed frame rails and chrome engine covers.
            tube(mb, (sx * 0.05, head[1], head[2]), (sx * 0.13, -0.25, 0.76), 0.025, "Paint")
            tube(mb, (sx * 0.13, -0.25, 0.76), (sx * 0.13, -0.15, 0.42), 0.025, "Paint")
            ellipsoid(mb, (sx * 0.17, 0.05, 0.42), (0.03, 0.12, 0.10), "Chrome")
            tube(mb, (sx * 0.06, 0.50, 0.97), (sx * 0.06, 0.44, 1.06), 0.015, "Chrome")
            tube(mb, (sx * 0.30, 0.42, 1.10), (sx * 0.30, 0.48, 1.17), 0.01, "Trim")
            mb.box((sx * 0.31, 0.48, 1.18), (0.09, 0.025, 0.06), "Trim")
        tube(mb, (-0.36, 0.40, 1.08), (0.36, 0.40, 1.08), 0.016, "Trim")
    # Front fork, yoke and bars.
    for sx in (-1, 1):
        mid = (sx * 0.09, lerp(fy, head[1], 0.55), lerp(wr, head[2], 0.55))
        tube(mb, (sx * 0.09, fy, wr), mid, 0.04, "Trim")
        tube(mb, mid, (sx * 0.09, head[1], head[2]), 0.03, "Chrome")
        if sport:
            tube(mb, (sx * 0.10, head[1] - 0.02, head[2]), (sx * 0.31, head[1] - 0.08, head[2] - 0.03), 0.016, "Trim")
        # Swingarm and foot pegs.
        tube(mb, (sx * 0.11, -0.12, 0.45), (sx * 0.10, ry, wr), 0.035, "Trim", r2=0.028)
        tube(mb, (sx * 0.12, -0.22, 0.42), (sx * 0.21, -0.22, 0.42), 0.012, "Chrome")
    mb.box((0, head[1], head[2] + 0.01), (0.24, 0.10, 0.035), "Chrome")
    loft(mb, [(fy - 0.17, wr + 0.29, 0.065, 0.02), (fy, wr + 0.32, 0.075, 0.025),
              (fy + 0.17, wr + 0.27, 0.065, 0.02)], "Paint")
    build_bike_details(mb, sp, fy, ry)
    # Exhaust: header under the engine to a can on the right.
    tube(mb, (0.08, 0.25, 0.26), (0.15, -0.25, 0.32), 0.035, "Chrome")
    tube(mb, (0.15, -0.25, 0.32), (0.18, -0.62 if sport else -0.55, 0.55), 0.06, "Trim", r2=0.05)
    body = mb.build("Body", mats)
    bm = bmesh.new()
    bm.from_mesh(body.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(body.data)
    bm.free()
    body.data.set_sharp_from_angle(angle=math.radians(55))
    for part in build_rider_real(sp, mats):
        part.parent = body
    # Side stand on the left, folded out: the game shows it (and hides the
    # rider) when the bike is parked in the garage, leaning onto it.
    st = MeshBuilder()
    tube(st, (-0.11, -0.08, 0.40), (-0.30, -0.12, 0.05), 0.015, "Trim")
    st.box((-0.30, -0.12, 0.04), (0.06, 0.05, 0.012), "Trim")
    stand = st.build("Stand", mats)
    stand.parent = body
    return body, fy, ry


def build_bike_wheel(name, pos, sp, mats):
    wr = sp["wr"]
    tw = 0.17 if name == "Wheel_R" else 0.13
    rr = wr * 0.68
    w2 = tw / 2
    seg = 32
    mb = MeshBuilder()
    mb.revolve([(rr * 0.97, -w2 + 0.01), (wr - 0.06, -w2), (wr - 0.02, -w2 * 0.7), (wr, 0.0),
                (wr - 0.02, w2 * 0.7), (wr - 0.06, w2), (rr * 0.97, w2 - 0.01)], seg, "Tire")
    mb.revolve([(rr * 0.97, w2 - 0.01), (rr, w2 - 0.004), (rr * 0.93, w2 * 0.4), (rr * 0.93, -w2 * 0.4),
                (rr, -w2 + 0.004), (rr * 0.97, -w2 + 0.01)], seg, "Rim")
    for k in range(sp["spokes"]):
        a = 2 * math.pi * k / sp["spokes"]
        rot = Matrix.Rotation(a, 3, "X")
        c = rot @ Vector((0, (rr * 0.93 + 0.05) / 2, 0))
        mb.box((0, c.y, c.z), (tw * 0.35, rr * 0.93 - 0.05, 0.035), "Rim", rot=rot)
    mb.revolve([(0.055, -w2 * 0.8), (0.055, w2 * 0.8)], 16, "Chrome", cap_end=True)
    discs = (-0.05, 0.05) if name == "Wheel_F" else (-0.06,)
    for x in discs:
        mb.revolve([(rr * 0.8, x - 0.003), (rr * 0.8, x + 0.003)], seg, "Chrome", cap_end=True)
        mb.box((x * 1.25, -rr * 0.55, rr * 0.5), (0.04, 0.09, 0.07), "Caliper")
    obj = mb.build(name, mats)
    obj.location = pos
    return obj


def build_bike(name, sp):
    clear_scene()
    mats = materials_for(sp["paint"])
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    body, fy, ry = build_bike_body(sp, mats)
    body.parent = root
    for wname, y in (("Wheel_F", fy), ("Wheel_R", ry)):
        build_bike_wheel(wname, Vector((0, y, sp["wr"])), sp, mats).parent = root
    return root


# ---------------------------------------------------------------------------
# Mesh helpers for the riders, wrecks and cockpits.
# ---------------------------------------------------------------------------

def assign_faces(obj, mats, rule):
    """rule(center, normal, current material name) -> new material name or None."""
    me = obj.data
    names = [m.name for m in me.materials]
    for poly in me.polygons:
        cur = names[poly.material_index] if names else None
        new = rule(poly.center, poly.normal, cur)
        if new and new != cur:
            if new not in names:
                me.materials.append(mats[new])
                names.append(new)
            poly.material_index = names.index(new)


def xform_since(mb, start, m, offset=(0, 0, 0)):
    """Transforms the vertices added to mb since index `start`."""
    o = Vector(offset)
    for i in range(start, len(mb.verts)):
        mb.verts[i] = m @ mb.verts[i] + o


# ---------------------------------------------------------------------------
# Rider: one smooth body in race leathers. Shoulders, arms and the outer leg
# carry the bike's colour, the flanks white; gloves, boots and knee sliders
# black; the helmet has a chin bar, a visor and (sport) an aero spoiler.
# ---------------------------------------------------------------------------

HAND_BONES = ("wrist", "metacarpal", "finger")


def human_object(name, verts, faces, dom, mats, mat_of, keep=None, target=7000, inflate=None):
    """Mesh from a posed body; mat_of(bone, centre, normal) picks each face's material."""
    if keep is not None:
        faces = [f for f in faces if all(keep[i] for i in f)]
    used = sorted({i for f in faces for i in f})
    remap = {v: k for k, v in enumerate(used)}
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(verts[i]) for i in used], [], [[remap[i] for i in f] for f in faces])
    me.validate()
    if inflate:  # clothing thickness: push each vertex out along its normal
        for v in me.vertices:
            v.co += v.normal * inflate(dom[used[v.index]])
        me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    names = []
    for poly, f in zip(me.polygons, faces):
        bones = [dom[i] for i in f]
        bone = max(set(bones), key=bones.count)
        m = mat_of(bone, poly.center, poly.normal)
        if m not in names:
            names.append(m)
            me.materials.append(mats[m])
        poly.material_index = names.index(m)
        poly.use_smooth = True
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    if tris > target:
        dec = obj.modifiers.new("Thin", "DECIMATE")
        dec.ratio = target / tris
    return obj


def grip_pose(grips, finger, lateral, pelvis, lean, **extra):
    """Pose spec with both hands closed round grips[side]."""
    spec = {"pelvis": Vector(pelvis), "lean": lean}
    for side in ("L", "R"):
        f, l = Vector(finger[side]), Vector(lateral[side])
        spec["finger_" + side], spec["lateral_" + side] = f, l
        spec["wrist_" + side] = human.wrist_for(grips[side], f, l, side)
    spec.update(extra)
    return spec


ARM_GIVE = {"upperarm01": 0.1, "upperarm02": 0.3, "lowerarm01": 0.6, "lowerarm02": 0.85}


def reach_to_grips(verts, joints, spec):
    """Closes the last few centimetres between each posed wrist and its grip by
    easing the arm along: the hand moves fully, the upper arm hardly at all,
    blended by the skin weights so nothing tears."""
    weights = human.load()["weights"]
    for side in ("L", "R"):
        off = spec["wrist_" + side] - joints["wrist." + side]
        for i, ws in weights.items():
            tot = sum(w for _, w in ws)
            give = 0.0
            for bone, w in ws:
                if not bone.endswith("." + side):
                    continue
                base = bone.split(".")[0]
                g = 1.0 if base.startswith(HAND_BONES) else ARM_GIVE.get(base, 0.0)
                give += g * w / tot
            if give > 0.0:
                verts[i] = verts[i] + off * give


def build_rider_real(sp, mats):
    """A real (MakeHuman) body in race leathers, posed on the bike: hands closed
    round the grips, feet on the pegs, tucked in (sport) or sitting up."""
    sport = sp["style"] == "sport"
    sx = {"L": -1.0, "R": 1.0}
    if sport:
        grips = {s: Vector((sx[s] * 0.31, 0.43, 0.93)) for s in sx}
        pelvis, lean, pitch, ankle = (0, -0.29, 0.93), 1.0, -0.55, (0.17, -0.22, 0.47)
    else:
        grips = {s: Vector((sx[s] * 0.34, 0.40, 1.08)) for s in sx}
        pelvis, lean, pitch, ankle = (0, -0.22, 0.94), 0.4, -0.15, (0.16, -0.02, 0.46)
    spec = grip_pose(grips, {s: (sx[s] * 0.2, 1, -0.3) for s in sx}, {s: (sx[s], 0, 0) for s in sx},
                     pelvis, lean, head_pitch=pitch, curl=52.0, thumb_curl=18.0, foot_dir=(0, 1, -0.45))
    for s in sx:
        spec["ankle_" + s] = Vector((sx[s] * ankle[0], ankle[1], ankle[2]))
        spec["knee_pole_" + s] = Vector((sx[s] * 0.6, 1, 0.2))
        spec["elbow_pole_" + s] = Vector((sx[s], -0.2, -0.6))
    verts, faces, dom, joints = human.pose(spec)
    reach_to_grips(verts, joints, spec)

    def leathers(bone, c, n):
        out = n.x * (1 if c.x > 0 else -1)
        if bone.startswith(HAND_BONES) or bone.startswith(("foot", "toe", "lowerleg02")):
            return "Trim"  # gloves and boots
        if bone.startswith(("shoulder01", "upperarm", "clavicle")) and out > -0.3:
            return "Paint"
        if bone.startswith("upperleg02") and out > 0.45:
            return "Paint"  # stripe down the outer thigh
        if bone.startswith(("spine03", "spine04")) and abs(n.x) > 0.7:
            return "Accent"  # white flanks
        return "Suit"
    body = human_object("Rider", verts, faces, dom, mats, leathers,
                        inflate=lambda b: 0.005 if b.startswith(HAND_BONES) else 0.016)
    head = [v for v, b in zip(verts, dom) if b == "head"]
    hc = sum(head, Vector()) / len(head)
    mb = MeshBuilder()
    hx, hy, hz = hc.x, hc.y + 0.01, hc.z - 0.02
    n = joints["neck01"]
    ellipsoid(mb, (n.x, n.y, n.z + 0.03), (0.085, 0.085, 0.045), "Suit")  # suit collar
    ellipsoid(mb, (hx, hy, hz), (0.138, 0.165, 0.148), "Paint")
    ellipsoid(mb, (hx, hy + 0.09, hz - 0.075), (0.105, 0.075, 0.06), "Paint")      # chin bar
    ellipsoid(mb, (hx, hy + 0.1, hz + 0.008), (0.113, 0.07, 0.052), "Glass")        # visor
    ellipsoid(mb, (hx, hy - 0.005, hz - 0.12), (0.105, 0.115, 0.035), "Trim")       # neck roll
    ellipsoid(mb, (hx, hy - 0.02, hz + 0.02), (0.14, 0.12, 0.02), "Accent")         # stripe
    if sport:
        mb.box((hx, hy - 0.15, hz + 0.06), (0.11, 0.06, 0.02), "Paint", rot=Matrix.Rotation(-0.35, 3, "X"))
    for s in sx:
        k = joints["lowerleg01." + s]
        mb.box((k.x + sx[s] * 0.065, k.y + 0.02, k.z), (0.015, 0.09, 0.05), "Accent")  # knee slider
    gear = mb.build("RiderGear", mats)
    return [body, gear]


def build_bike_details(mb, sp, fy, ry):
    """Drive chain and sprockets, shocks, radiator, gold forks, fairing vents."""
    wr = sp["wr"]
    sport = sp["style"] == "sport"
    cx = -0.125  # chain on the left
    fz, fr, rr = 0.42, 0.045, 0.105
    fyc = -0.10
    mb.revolve([(fr, cx - 0.006), (fr, cx + 0.006)], 16, "Chrome", offset=(0, fyc, fz), cap_end=True)
    mb.revolve([(rr, cx - 0.004), (rr, cx + 0.004)], 24, "Chrome", offset=(0, ry, wr), cap_end=True)
    tube(mb, (cx, fyc, fz + fr), (cx, ry, wr + rr), 0.007, "Trim", segs=6)
    tube(mb, (cx, fyc, fz - fr), (cx, ry, wr - rr), 0.007, "Trim", segs=6)
    # Chain guard
    mb.box((cx - 0.012, (fyc + ry) / 2, wr + rr + 0.025), (0.01, 0.4, 0.035), "Trim")
    if sport:  # gold upside-down fork lowers, a mono-shock and fairing vents
        for sx in (-1, 1):
            a = Vector((sx * 0.09, fy, wr))
            b = Vector((sx * 0.09, lerp(fy, 0.50, 0.4), lerp(wr, 0.93, 0.4)))
            tube(mb, a, b, 0.043, "Gold")
            for k in range(3):
                mb.box((sx * 0.218, 0.30 + k * 0.07, 0.60 - k * 0.012), (0.012, 0.045, 0.012), "Trim",
                       rot=Matrix.Rotation(-0.5, 3, "X"))
        tube(mb, (0, -0.22, 0.48), (0, -0.40, 0.78), 0.03, "Caliper")
    else:  # twin shocks and an exposed radiator
        for sx in (-1, 1):
            tube(mb, (sx * 0.145, ry + 0.12, wr + 0.06), (sx * 0.145, -0.44, 0.84), 0.018, "Chrome")
            tube(mb, (sx * 0.145, ry + 0.18, wr + 0.14), (sx * 0.145, -0.48, 0.77), 0.03, "Caliper")
        mb.box((0, 0.40, 0.58), (0.30, 0.035, 0.24), "Trim", rot=Matrix.Rotation(0.25, 3, "X"))
        mb.box((0, 0.418, 0.58), (0.27, 0.005, 0.21), "Gloss", rot=Matrix.Rotation(0.25, 3, "X"))
    # Brake lines down the forks
    for sx in (-1, 1):
        tube(mb, (sx * 0.06, 0.48, 0.95), (sx * 0.12, fy - 0.03, wr + 0.12), 0.005, "Trim", segs=5)
    # Rear hugger over the tyre
    loft(mb, [(ry - 0.05, wr + 0.30, 0.07, 0.012), (ry + 0.15, wr + 0.27, 0.075, 0.012),
              (ry + 0.30, wr + 0.18, 0.07, 0.012)], "Trim")


# ---------------------------------------------------------------------------
# Wrecks: a traffic car crushed at one end, the windscreen crazed, the lamps
# smashed and a wheel knocked out of line. Built from the normal car.
# ---------------------------------------------------------------------------

WRECKS = {
    "t_sedan_wreck": ("t_sedan", "front", 1.0, 11),
    "t_hatch_wreck": ("t_hatch", "rear", -1.0, 12),
    "t_suv_wreck": ("t_suv", "front", -1.0, 13),
}


def crush(root, sp, end, side, seed):
    """Crumples one end of the car: every part (body, bumpers, lamps, plate) is
    pushed in, the bonnet buckles, and the hard-hit side folds furthest."""
    MATS_CUR.update({m.name: m for m in bpy.data.materials})
    bpy.context.view_layer.update()
    rng = random.Random(seed)
    parts = [o for o in bpy.context.scene.objects if o.type == "MESH" and not o.name.startswith("Wheel_")]
    sgn = 1.0 if end == "front" else -1.0
    tip = max((o.matrix_world @ v.co).y * sgn for o in parts for v in o.data.vertices)
    zone = 1.15
    hw = sp["W"] / 2
    noise = {}
    for o in parts:
        mw = o.matrix_world
        inv = mw.inverted()
        for v in o.data.vertices:
            w = mw @ v.co
            d = (w.y * sgn - (tip - zone)) / zone
            if d <= 0:
                continue
            key = (round(w.x, 2), round(w.y, 2), round(w.z, 2))  # neighbours share their dent
            if key not in noise:
                noise[key] = Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * 0.014
            bias = 1.0 + 0.55 * side * (w.x / hw)
            w.y -= sgn * 0.55 * d ** 1.4 * max(bias, 0.3)
            w.x *= 1.0 - 0.07 * d
            if w.z > sp["clr"] + 0.35:
                w.z += 0.06 * math.sin(d * math.pi * 2.2) * d  # buckled bonnet / boot lid
            w += noise[key] * d
            v.co = inv @ w
        o.data.update()

    def smash(c, n, cur):
        if cur == "Glass" and n.y * sgn > 0.3 and n.z > 0.15:
            return "Cracked"
        if cur in ("Headlight", "Taillight", "TailLens") and c.y * sgn > tip - zone - 0.3:
            return "Trim"
        return None
    for o in parts:
        assign_faces(o, MATS_CUR, smash)
    # The wheel on the hard-hit corner: knocked in and leaning.
    want = ("Wheel_F" if end == "front" else "Wheel_R") + ("R" if side > 0 else "L")
    for o in root.children:
        if o.name.startswith(want):
            o.rotation_euler.z += 0.38 * -side
            o.rotation_euler.y += 0.22 * side
            o.location.z -= 0.07
            o.location.y -= sgn * 0.2


MATS_CUR = {}


def build_wreck(name, info):
    base, end, side, seed = info
    root = build_car(name, CARS[base])
    crush(root, CARS[base], end, side, seed)
    return root


# ---------------------------------------------------------------------------
# Police car at a crash scene: the traffic saloon in white with a blue band,
# a roof light bar (SirenRed / SirenBlue, flashed by the game) and push bar.
# ---------------------------------------------------------------------------

def build_police(name):
    sp = dict(CARS["t_sedan"])
    sp["paint"] = (0.92, 0.92, 0.93)
    root = build_car(name, sp)
    MATS_CUR.update({m.name: m for m in bpy.data.materials})
    body = next(o for o in root.children if o.name.startswith("Body"))
    zb = sp["clr"]

    def livery(c, n, cur):
        if cur == "Paint" and abs(n.x) > 0.55 and zb + 0.28 < c.z < zb + 0.5:
            return "Livery"
        return None
    assign_faces(body, MATS_CUR, livery)
    top = max(body.data.vertices, key=lambda v: v.co.z).co
    mb = MeshBuilder()
    w = sp["W"] * 0.62
    mb.box((0, top.y, top.z + 0.03), (w, 0.24, 0.05), "Trim")
    mb.box((-w / 4, top.y, top.z + 0.075), (w / 2 - 0.02, 0.2, 0.06), "SirenBlue")
    mb.box((w / 4, top.y, top.z + 0.075), (w / 2 - 0.02, 0.2, 0.06), "SirenRed")
    front = max(v.co.y for v in body.data.vertices)
    for sx in (-1, 1):  # push bar
        tube(mb, (sx * 0.3, front + 0.05, 0.35), (sx * 0.3, front + 0.05, 0.75), 0.025, "Trim")
    tube(mb, (-0.36, front + 0.06, 0.62), (0.36, front + 0.06, 0.62), 0.025, "Trim")
    tube(mb, (-0.36, front + 0.06, 0.42), (0.36, front + 0.06, 0.42), 0.025, "Trim")
    bar = mb.build("LightBar", MATS_CUR)
    bar.parent = body
    return root


# ---------------------------------------------------------------------------
# Cockpits for the first-person view. Laid out around the eye at the origin
# (x right, y forward, z up). The game spins SteerWheel (car) or Bars (bike)
# and stretches the forearms from the shoulders to the Wrist_L / Wrist_R empties.
# ---------------------------------------------------------------------------

def empty(name, loc, parent=None):
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    if parent:
        e.parent = parent
    e.location = loc
    return e


def rim_torus(mb, R, rr_of, mat_of, flat=-0.155, segs=72, ring=12):
    """Steering rim around the local Y axis, flat-bottomed, thicker where gripped."""
    rings = []
    for i in range(segs):
        th = 2 * math.pi * i / segs
        c = Vector((R * math.cos(th), 0, R * math.sin(th)))
        if c.z < flat:
            c.z = flat
        radial = Vector((math.cos(th), 0, math.sin(th))) if c.z > flat else Vector((0, 0, -1))
        rr = rr_of(th)
        ring_v = []
        for k in range(ring):
            ph = 2 * math.pi * k / ring
            p = c + radial * (rr * math.cos(ph)) + Vector((0, 1, 0)) * (rr * 1.15 * math.sin(ph))
            ring_v.append(mb.v(p))
        rings.append((ring_v, mat_of(th)))
    for i in range(segs):
        a, mat = rings[i]
        b, _ = rings[(i + 1) % segs]
        for k in range(ring):
            n = (k + 1) % ring
            mb.f([a[k], b[k], b[n], a[n]], mat)


def extrude_x(mb, profile, x0, x1, mat, slices=10):
    """Closed (y, z) profile swept along x, capped."""
    rows = []
    for i in range(slices + 1):
        x = lerp(x0, x1, i / slices)
        rows.append([mb.v((x, y, z)) for y, z in profile])
    n = len(profile)
    for i in range(slices):
        for k in range(n):
            m = (k + 1) % n
            mb.f([rows[i][k], rows[i][m], rows[i + 1][m], rows[i + 1][k]], mat)
    mb.f(list(reversed(rows[0])), mat)
    mb.f(rows[-1], mat)


def loft_x(mb, secs, mat, cx=0.0, segs=18, n=2.4):
    start = len(mb.verts)
    loft(mb, secs, mat, segs=segs, n=n)
    xform_since(mb, start, Matrix.Identity(3), (cx, 0, 0))


def cockpit_hands(name, grips, finger, lateral, pelvis, lean, mats, mat, parent, curl):
    """Just the hands (and a little wrist) of a body posed to hold `grips`, in
    the parent's local space, plus Wrist_L / Wrist_R empties for the forearms."""
    spec = grip_pose(grips, finger, lateral, pelvis, lean, curl=curl, thumb_curl=22.0)
    for side in ("L", "R"):
        spec["ankle_" + side] = Vector(pelvis) + Vector((0.1 if side == "R" else -0.1, 0.4, -0.5))
    verts, faces, dom, joints = human.pose(spec)
    keep = []
    for i, (v, b) in enumerate(zip(verts, dom)):
        side = "L" if b.endswith(".L") else "R"
        near = (v - joints["wrist." + side]).length < 0.09
        keep.append(b.startswith(HAND_BONES) or (b.startswith("lowerarm02") and near))
        # Only the hands are kept, so put each exactly on its grip even if
        # the body behind could not quite reach.
        if keep[-1]:
            verts[i] = v + (spec["wrist_" + side] - joints["wrist." + side])
    for side in ("L", "R"):  # forearms come from the game; aim them a little up the arm
        w = spec["wrist_" + side]
        e = joints["lowerarm01." + side] + (w - joints["wrist." + side])
        empty("Wrist_" + side, w + (e - w).normalized() * 0.07, parent)
    return human_object(name, verts, faces, dom, mats, lambda b, c, n: mat, keep=keep, target=6000)


def build_cockpit_car(mats):
    root = bpy.data.objects.new("cockpit_car", None)
    bpy.context.scene.collection.objects.link(root)
    cx = 0.37
    mb = MeshBuilder()
    # Dashboard: one soft-touch moulding across the car, with a stitched seam.
    extrude_x(mb, [(0.62, -0.68), (0.60, -0.52), (0.63, -0.42), (0.72, -0.365), (0.90, -0.375),
                   (1.20, -0.45), (1.24, -0.68)], -0.82, 1.56, "Dash", slices=16)
    tube(mb, (-0.82, 0.715, -0.362), (1.56, 0.715, -0.362), 0.004, "Trim", segs=6)
    # Instrument cluster, seen through the top of the wheel: a dark face
    # plate leaning back, two lit dials and a cowl shading them.
    tip = Matrix.Rotation(math.radians(-20), 3, "X")
    mb.box((0, 0.80, -0.32), (0.38, 0.12, 0.13), "Dash")
    mb.box((0, 0.815, -0.205), (0.36, 0.02, 0.17), "Trim", rot=tip)
    mb.box((0, 0.735, -0.118), (0.42, 0.2, 0.022), "Dash", rot=Matrix.Rotation(math.radians(6), 3, "X"))
    for sx in (-1, 1):  # cowl cheeks
        mb.box((sx * 0.2, 0.77, -0.2), (0.022, 0.16, 0.17), "Dash")
    for x in (-0.095, 0.095):
        s = len(mb.verts)
        mb.revolve([(0.062, 0.0), (0.062, 0.008)], 32, "Chrome")
        mb.revolve([(0.058, 0.002), (0.044, 0.002)], 32, "Dial")  # lit scale
        mb.revolve([(0.044, 0.003), (0.001, 0.003)], 32, "Trim")
        mb.box((0.005, 0.012, 0.022), (0.003, 0.004, 0.045), "Caliper", rot=Matrix.Rotation(-0.6, 3, "X"))  # needle
        # Built around +x; turn it to face the driver (-y), tipped up a little.
        xform_since(mb, s, tip @ Matrix.Rotation(-math.pi / 2, 3, "Z"), (x, 0.797, -0.19))
    # Centre screen, vents, console.
    mb.box((cx, 0.74, -0.33), (0.26, 0.012, 0.15), "Trim", rot=Matrix.Rotation(-0.35, 3, "X"))
    mb.box((cx, 0.733, -0.329), (0.24, 0.004, 0.13), "Screen", rot=Matrix.Rotation(-0.35, 3, "X"))
    mb.box((cx, 0.45, -0.66), (0.26, 0.5, 0.16), "Dash")
    # Door top and window sill on the driver's side.
    extrude_x(mb, [(0.0, -0.75), (0.0, -0.40), (0.05, -0.36), (0.6, -0.38), (0.6, -0.75)], -0.74, -0.62, "Dash", 2)
    # Windscreen frame: pillars, header, rear-view mirror.
    # The header sits ~25 degrees above the eye, as in a real saloon, so the
    # top of the view is framed by the roof lining with the mirror hanging off it.
    tube(mb, (-0.80, 1.02, -0.42), (-0.68, 0.62, 0.30), 0.055, "Headliner", r2=0.045)
    tube(mb, (1.54, 1.02, -0.42), (1.42, 0.62, 0.30), 0.055, "Headliner", r2=0.045)
    mb.box((cx, 0.36, 0.33), (2.3, 0.56, 0.04), "Headliner")
    mb.box((cx, 0.62, 0.30), (2.3, 0.06, 0.06), "Headliner")
    for x in (-0.2, cx + 0.5):  # sun visors folded up
        mb.box((x, 0.52, 0.29), (0.5, 0.16, 0.025), "Headliner")
    tube(mb, (cx, 0.58, 0.31), (cx, 0.58, 0.24), 0.008, "Trim")
    mb.box((cx, 0.58, 0.205), (0.26, 0.035, 0.075), "Trim")
    mb.box((cx, 0.561, 0.205), (0.24, 0.004, 0.06), "Mirror")
    # Bonnet beyond the screen, and the wipers parked at its base.
    loft_x(mb, [(1.22, -0.60, 0.86, 0.06), (1.8, -0.625, 0.88, 0.07), (2.5, -0.68, 0.82, 0.06),
                (2.85, -0.73, 0.66, 0.04)], "Paint", cx=cx, n=5.0)
    for x in (cx - 0.35, cx + 0.2):
        tube(mb, (x, 1.24, -0.46), (x + 0.42, 1.26, -0.47), 0.008, "Trim", segs=6)
    dash = mb.build("Dash", mats)
    dash.parent = root
    dash.data.set_sharp_from_angle(angle=math.radians(40))
    # Steering column, tilted back towards the driver.
    col = empty("SteerColumn", (0, 0.52, -0.24), root)
    col.rotation_euler = (math.radians(22), 0, 0)
    tube_mb = MeshBuilder()
    # Forward and down into the dash, so it never shows through the rim.
    tube(tube_mb, (0, 0.04, 0), (0, 0.23, -0.24), 0.04, "Dash", r2=0.055)
    cobj = tube_mb.build("Column", mats)
    cobj.parent = col
    wb = MeshBuilder()
    R = 0.185
    rim_torus(wb, R, lambda th: 0.0165 + 0.004 * max(0.0, math.cos(2 * th)) ** 6,
              lambda th: "Caliper" if abs(th - math.pi / 2) < 0.06 else "Leather")
    for th in (math.radians(185), math.radians(-5)):  # side spokes, a little below centre
        d = Vector((math.cos(th), 0, math.sin(th)))
        wb.box(tuple(d * R * 0.55), (R * 0.75, 0.022, 0.05), "Dash", rot=Matrix.Rotation(-th, 3, "Y"))
        wb.box(tuple(d * R * 0.55 + Vector((0, -0.012, 0))), (R * 0.5, 0.004, 0.012), "Chrome",
               rot=Matrix.Rotation(-th, 3, "Y"))
    wb.box((0, 0, -R * 0.55), (0.05, 0.022, R * 0.6), "Dash")
    ellipsoid(wb, (0, -0.02, -0.005), (0.08, 0.035, 0.065), "Dash")    # airbag boss
    ellipsoid(wb, (0, -0.052, 0.0), (0.02, 0.006, 0.013), "Chrome")     # badge
    for sx in (-1, 1):  # shift paddles
        wb.box((sx * 0.13, 0.04, 0.02), (0.07, 0.008, 0.035), "Trim")
    wheel = wb.build("SteerWheel", mats)
    wheel.parent = col
    # Real hands at quarter to three, fingers wrapped round the rim from the outside.
    sx = {"L": -1.0, "R": 1.0}
    grips = {k: Vector((sx[k] * (R + 0.004), -0.004, 0.02)) for k in sx}
    hands = cockpit_hands("Hands", grips, {k: (sx[k] * -0.25, 1, 0.1) for k in sx},
                          {k: (0, 0, -1) for k in sx}, (0, -0.3, -0.6), -0.2, mats, "Skin", wheel, curl=62.0)
    hands.parent = wheel
    return root


def build_cockpit_bike(mats):
    root = bpy.data.objects.new("cockpit_bike", None)
    bpy.context.scene.collection.objects.link(root)
    mb = MeshBuilder()
    # Tank below the chin with a grippy pad and filler cap.
    loft(mb, [(-0.12, -0.80, 0.15, 0.08), (0.05, -0.74, 0.21, 0.12), (0.30, -0.72, 0.21, 0.12),
              (0.48, -0.76, 0.15, 0.08), (0.56, -0.80, 0.06, 0.04)], "Paint")
    loft(mb, [(-0.10, -0.69, 0.10, 0.012), (0.08, -0.62, 0.12, 0.012)], "Trim")
    s = len(mb.verts)
    mb.revolve([(0.045, 0.0), (0.045, 0.01), (0.001, 0.01)], 20, "Chrome")
    xform_since(mb, s, Matrix.Rotation(-math.pi / 2, 3, "Y"), (0, 0.24, -0.60))
    # Upper fairing, its dark inner face, the screen and the mirrors.
    loft(mb, [(0.62, -0.47, 0.25, 0.13), (0.82, -0.44, 0.26, 0.13), (1.02, -0.47, 0.18, 0.10),
              (1.10, -0.49, 0.06, 0.04)], "Paint")
    loft(mb, [(0.60, -0.40, 0.235, 0.05), (0.66, -0.36, 0.22, 0.04)], "Dash")
    loft(mb, [(0.70, -0.33, 0.20, 0.006), (0.86, -0.25, 0.17, 0.005), (0.98, -0.20, 0.10, 0.004)], "Shield")
    # TFT dash on the fairing stay, facing the rider.
    mb.box((0, 0.70, -0.33), (0.21, 0.05, 0.12), "Trim", rot=Matrix.Rotation(0.6, 3, "X"))
    mb.box((0, 0.68, -0.32), (0.18, 0.004, 0.095), "Screen", rot=Matrix.Rotation(0.6, 3, "X"))
    for sx in (-1, 1):
        tube(mb, (sx * 0.22, 0.80, -0.36), (sx * 0.36, 0.78, -0.27), 0.01, "Trim")
        mb.box((sx * 0.40, 0.78, -0.26), (0.14, 0.05, 0.075), "Paint")
        mb.box((sx * 0.40, 0.752, -0.26), (0.12, 0.004, 0.06), "Mirror")
    static = mb.build("Static", mats)
    static.parent = root
    # Steering head: yoke, clip-ons, switchgear, levers, grips.
    bars = empty("Bars", (0, 0.58, -0.34), root)
    bm = MeshBuilder()
    bm.box((0, 0, 0), (0.27, 0.11, 0.03), "Trim")
    for sx in (-1, 1):
        s = len(bm.verts)
        bm.revolve([(0.032, -0.02), (0.032, 0.02), (0.02, 0.025)], 16, "Gold")
        xform_since(bm, s, Matrix.Rotation(math.pi / 2, 3, "Y"), (sx * 0.1, -0.01, 0.0))
        tube(bm, (sx * 0.1, 0.0, -0.01), (sx * 0.24, -0.05, -0.04), 0.012, "Trim")
        tube(bm, (sx * 0.24, -0.05, -0.04), (sx * 0.36, -0.07, -0.05), 0.018, "Tire")  # grip
        tube(bm, (sx * 0.36, -0.07, -0.05), (sx * 0.375, -0.07, -0.05), 0.02, "Chrome")
        bm.box((sx * 0.215, -0.05, -0.035), (0.05, 0.055, 0.05), "Trim")  # switch cube
        tube(bm, (sx * 0.23, -0.02, -0.03), (sx * 0.37, 0.02, -0.035), 0.008, "Chrome")  # lever
        if sx > 0:
            bm.box((0.17, -0.0, 0.01), (0.05, 0.04, 0.03), "Accent")  # brake reservoir
    bobj = bm.build("BarsMesh", mats)
    bobj.parent = bars
    # Gloved hands closed round the grips, palms on top.
    sx = {"L": -1.0, "R": 1.0}
    grips = {k: Vector((sx[k] * 0.30, -0.065, -0.048)) for k in sx}
    hands = cockpit_hands("Hands", grips, {k: (sx[k] * 0.2, 1, -0.3) for k in sx},
                          {k: (sx[k], 0, 0) for k in sx}, (0, -0.92, -0.12), 1.0, mats, "Trim", bars, curl=52.0)
    hands.parent = bars
    return root


COCKPITS = {"cockpit_car": build_cockpit_car, "cockpit_bike": build_cockpit_bike}


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    extra = [(n, None) for n in list(WRECKS) + ["t_police"] + list(COCKPITS)]
    for name, sp in list(CARS.items()) + list(BIKES.items()) + extra:
        if only and name not in only:
            continue
        if name in COCKPITS:
            clear_scene()
            COCKPITS[name](materials_for((0.5, 0.5, 0.5)))
            export(None, os.path.join(OUT_DIR, name + ".glb"))
            print("BUILT %s" % name)
            continue
        if name in WRECKS:
            sp = CARS[WRECKS[name][0]]
            root = build_wreck(name, WRECKS[name])
        elif name == "t_police":
            sp = CARS["t_sedan"]
            root = build_police(name)
        else:
            root = build_bike(name, sp) if name in BIKES else build_car(name, sp)
        if "--no-ao" not in argv:
            bake_ao(sp)
        tris = sum(len(p.vertices) - 2 for o in bpy.context.scene.objects if o.type == "MESH"
                   for p in o.data.polygons)
        export(root, os.path.join(OUT_DIR, name + ".glb"))
        print("BUILT %s tris=%d" % (name, tris))
        if "--no-render" not in argv:
            render_previews(name, sp)


main()
