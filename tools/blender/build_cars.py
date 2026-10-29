"""Procedural vehicle generator for FLOWLINE.

Builds original, fictional vehicles from a handful of design parameters and
exports each one as a GLB (Y-up, facing -Z in Godot) plus preview renders.

Run:
  blender -b -P tools/blender/build_cars.py -- [--only name,name] [--no-render]

Every material is named so the game can override it at runtime:
  Paint, Glass, Trim, Chrome, Tire, Rim, Headlight, Taillight
Wheels are separate nodes named Wheel_FL / Wheel_FR / Wheel_RL / Wheel_RR with
their pivot at the hub, spinning around local X.
"""

import math
import os
import sys

import bmesh
import bpy
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
        bed=False, box=None, mirrors=True, stations=56,
    )
    base.update(kw)
    clr = base["clr"]
    if base["zb"] is None:
        base["zb"] = [(0, clr + .26), (.04, clr + .08), (.12, clr), (.88, clr),
                      (.96, clr + .07), (1, clr + .22)]
    return base


CARS = {
    # ---- player cars ------------------------------------------------------
    "kestrel": spec(  # compact hot hatch, starter car
        L=4.06, W=1.80, wb=2.58, wr=0.33, roof=1.43, clr=0.15,
        cab_rear=0.05, rw_top=0.16, ws_top=0.56, cab_front=0.71,
        belt=[(0, .86), (.05, .93), (.3, .92), (.7, .86), (.9, .80), (1, .66)],
        tail="pair", paint=(0.85, 0.12, 0.08), spokes=6, roof_w=0.72),
    "vanta": spec(  # sport coupe
        L=4.48, W=1.90, wb=2.66, wr=0.345, roof=1.27, clr=0.13,
        cab_rear=0.17, rw_top=0.37, ws_top=0.555, cab_front=0.665,
        belt=[(0, .83), (.08, .90), (.35, .86), (.66, .79), (.9, .70), (1, .58)],
        paint=(0.06, 0.20, 0.55), spokes=5),
    "meridian": spec(  # executive sedan
        L=4.86, W=1.87, wb=2.92, wr=0.35, roof=1.44, clr=0.15,
        cab_rear=0.19, rw_top=0.31, ws_top=0.585, cab_front=0.70,
        belt=[(0, .90), (.08, .96), (.3, .95), (.7, .88), (.9, .81), (1, .68)],
        paint=(0.12, 0.12, 0.13), spokes=10, tail="bar"),
    "brute": spec(  # muscle car, long hood
        L=4.78, W=1.94, wb=2.80, wr=0.36, tw=0.27, roof=1.33, clr=0.14,
        cab_rear=0.20, rw_top=0.35, ws_top=0.52, cab_front=0.615,
        belt=[(0, .88), (.06, .94), (.4, .90), (.62, .86), (.92, .82), (1, .72)],
        tail="pair", paint=(0.90, 0.55, 0.05), spokes=5, exhaust=2),
    "solstice": spec(  # mid-engine supercar
        L=4.56, W=2.00, wb=2.70, wb_shift=-0.05, wr=0.35, tw=0.29, roof=1.14,
        clr=0.11, crown=0.03,
        cab_rear=0.30, rw_top=0.43, ws_top=0.53, cab_front=0.67,
        halfw=[(0, .90), (.05, .98), (.2, 1.0), (.5, .965), (.7, 1.0), (.86, .99), (.95, .92), (1, .74)],
        belt=[(0, .82), (.06, .86), (.3, .80), (.6, .74), (.79, .80), (.92, .66), (1, .50)],
        zb=[(0, .36), (.04, .19), (.12, .11), (.9, .11), (.97, .14), (1, .24)],
        paint=(0.80, 0.80, 0.82), spokes=10, roof_w=0.66, tail="bar"),
    # ---- traffic ----------------------------------------------------------
    "t_sedan": spec(
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
    "t_van": spec(
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
    "t_truck": spec(  # box truck: short cab + cargo box
        L=7.6, W=2.30, wb=4.4, wb_shift=-0.2, wr=0.48, tw=0.30, roof=2.55, clr=0.38,
        cab_rear=0.68, rw_top=0.69, ws_top=0.86, cab_front=0.92, roof_w=0.84,
        bpillar=False,
        halfw=[(0, 1.0), (.7, 1.0), (.95, .97), (1, .88)],
        belt=[(0, 1.35), (.7, 1.35), (.9, 1.32), (1, 1.22)],
        zb=[(0, .62), (.02, .55), (.1, .52), (.9, .50), (.97, .55), (1, .70)],
        box=dict(t0=0.0, t1=0.665, h=3.45), tail="pillar", paint=(0.95, 0.95, 0.95),
        spokes=0, exhaust=0, mirrors=True),
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
    }


MAT_ORDER = ["Paint", "Glass", "Trim", "Chrome", "Tire", "Rim", "Headlight", "Taillight"]


class MeshBuilder:
    """Accumulates verts/faces with named materials, then builds one object."""

    def __init__(self):
        self.verts = []
        self.faces = []  # (indices, material name)

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
    tum = 1.0 - 0.06 * sp["tumble"]
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
    if k in (6, 7):  # side glass band
        if cr + 0.015 < tm < cf - 0.02:
            if sp["bpillar"] and mid - 0.012 <= tm <= mid + 0.012:
                return "Trim"
            return "Glass"
        return "Paint"
    if k == 9:  # windshield / rear window centre
        if ws <= tm <= cf or cr <= tm <= rw:
            return "Glass"
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
    # end caps: two inset rings then an n-gon, so subdivision keeps a firm edge
    for ring, sign in ((rings[0], -1), (rings[-1], 1)):
        cen = sum((mb.verts[v] for v in ring), Vector()) / len(ring)
        prev = ring
        for scale, push in ((0.965, 0.014), (0.72, 0.038)):
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
    obj = mb.build("Body", mats)
    # make normals point outward
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
        r = wr + 0.055
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

    # --- tail lights ---
    tz = belt_r - 0.09
    if sp["tail"] == "bar":
        xs = [lerp(-0.86 * hr, 0.86 * hr, i / (n * 2)) for i in range(n * 2 + 1)]
        ribbon(mb, surf, xs, tz, 0.055, False, "Taillight")
        for s in (-1, 1):
            xs = [s * lerp(0.62 * hr, 0.88 * hr, i / 6) for i in range(7)]
            ribbon(mb, surf, sorted(xs), tz - 0.05, 0.06, False, "Taillight")
    elif sp["tail"] == "pair":
        for s in (-1, 1):
            xs = sorted(s * lerp(0.48 * hr, 0.88 * hr, i / 8) for i in range(9))
            ribbon(mb, surf, xs, tz, 0.11, False, "Taillight")
    else:  # tall pillar lights (vans, trucks)
        for s in (-1, 1):
            xs = sorted(s * lerp(0.80 * hr, 0.92 * hr, i / 3) for i in range(4))
            ribbon(mb, surf, xs, (zb_r + belt_r) / 2 + 0.05, 0.42, False, "Taillight")
    # rear diffuser / bumper insert
    xs = [lerp(-0.74 * hr, 0.74 * hr, i / (n * 2)) for i in range(n * 2 + 1)]
    ribbon(mb, surf, xs, zb_r + 0.06, 0.10, False, "Trim", out=0.01)
    # exhausts
    for e in range(sp["exhaust"]):
        x = (0.45 if sp["exhaust"] == 1 else (-0.5 + e)) * hr
        if sp["exhaust"] == 2:
            x = (-0.55 if e == 0 else 0.55) * hr
        y = surf.y_extent(x, zb_r + 0.07, False)
        if y is None:
            continue
        prof = [(0.040, 0.0), (0.046, 0.0), (0.046, -0.09), (0.040, -0.09)]
        sub = MeshBuilder()
        sub.revolve(prof, 16, "Chrome")
        pipe = sub.build("Exhaust%d" % e, mats)
        pipe.rotation_euler = (0, 0, math.pi / 2)
        pipe.location = (x, y + 0.02, zb_r + 0.07)
        pipe.parent = body

    # --- headlights ---
    hz = belt_f - 0.09
    for s in (-1, 1):
        xs = sorted(s * lerp(0.42 * hf, 0.90 * hf, i / 10) for i in range(11))
        lift = (lambda x, s=s: 0.03 * ((abs(x) / hf - 0.42) / 0.48))
        ribbon(mb, surf, xs, hz, 0.06 if sp["head"] == "slim" else 0.11, True, "Headlight",
               curve=lift)
    # grille + lower intake
    xs = [lerp(-0.36 * hf, 0.36 * hf, i / 12) for i in range(13)]
    ribbon(mb, surf, xs, (zb_f + belt_f) / 2 - 0.03, 0.12, True, "Trim", out=0.006)
    xs = [lerp(-0.70 * hf, 0.70 * hf, i / 20) for i in range(21)]
    ribbon(mb, surf, xs, zb_f + 0.07, 0.07, True, "Trim", out=0.006)

    # --- mirrors ---
    if sp["mirrors"]:
        t = sp["cab_front"] - 0.03
        z = pchip(sp["belt"], t) + 0.075
        y = -L / 2 + t * L
        for s in (-1, 1):
            x = surf.x_extent(y, z - 0.03, s) or s * W / 2
            mb.box((x + s * 0.06, y, z), (0.14, 0.10, 0.085), "Paint")
            mb.box((x + s * 0.01, y - 0.01, z - 0.02), (0.05, 0.05, 0.03), "Trim")
            mb.box((x + s * 0.075, y - 0.052, z), (0.11, 0.006, 0.065), "Chrome")

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
    if sp["box"]:
        apply_modifier(obj, "BEVEL", width=0.03, segments=2, limit_method="ANGLE")


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
            mb.box((face_x, c.y, c.z), (0.03, rr * 0.92 - 0.06, width), "Rim", rot=rot)
    else:  # plain steel wheel with hubcap
        cap = [(rr * 0.88, w2 - 0.05), (rr * 0.8, w2 - 0.03), (rr * 0.3, w2 - 0.018), (0.001, w2 - 0.016)]
        mb.revolve(cap, seg, "Rim")
    hub = [(0.075, face_x - 0.02), (0.075, face_x + 0.02), (0.04, face_x + 0.03), (0.001, face_x + 0.03)]
    mb.revolve(hub, 16, "Chrome")
    # brake disc + caliper (visible through spokes)
    disc = [(rr * 0.78, -0.01), (rr * 0.78, 0.01)]
    mb.revolve(disc, seg, "Chrome", cap_end=True)
    mb.box((0.0, 0.0, rr * 0.62), (0.07, 0.16, 0.09), "Paint" if sp["spokes"] >= 5 else "Trim")
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
    body.data.set_sharp_from_angle(angle=math.radians(50))
    build_details(sp, body, mats)
    body.parent = root
    for wname, pos in wheel_positions(sp):
        w = build_wheel(sp, wname, pos, mats)
        w.parent = root
    return root


def export(root, path):
    for o in bpy.context.scene.objects:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True,
                              export_apply=True, export_yup=True)


def render_previews(name, sp):
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x, scene.render.resolution_y = 960, 540
    scene.render.film_transparent = False
    world = bpy.data.worlds.new("W")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.55, 0.65, 0.8, 1)
    bg.inputs[1].default_value = 0.9
    scene.world = world
    bpy.ops.mesh.primitive_plane_add(size=60)
    ground = bpy.context.active_object
    ground.data.materials.append(make_material("Ground", (0.12, 0.12, 0.13), 0, 0.8))
    sun = bpy.data.objects.new("Sun", bpy.data.lights.new("Sun", "SUN"))
    sun.data.energy = 4.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    scene.collection.objects.link(sun)
    cam = bpy.data.objects.new("Cam", bpy.data.cameras.new("Cam"))
    cam.data.lens = 50
    scene.collection.objects.link(cam)
    scene.camera = cam
    d = sp["L"] * 1.45
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


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = None
    if "--only" in argv:
        only = argv[argv.index("--only") + 1].split(",")
    os.makedirs(OUT_DIR, exist_ok=True)
    os.makedirs(PREVIEW_DIR, exist_ok=True)
    for name, sp in CARS.items():
        if only and name not in only:
            continue
        root = build_car(name, sp)
        tris = sum(len(p.vertices) - 2 for o in bpy.context.scene.objects if o.type == "MESH"
                   for p in o.data.polygons)
        export(root, os.path.join(OUT_DIR, name + ".glb"))
        print("BUILT %s tris=%d" % (name, tris))
        if "--no-render" not in argv:
            render_previews(name, sp)


main()
