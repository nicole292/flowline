"""Real human bodies for FLOWLINE: the MakeHuman base mesh (CC0) posed by its
default skeleton with a small linear-blend skinning step, no armature needed.

Source files (MakeHuman 1.x, assets released under CC0 1.0), kept outside the
repo in flowline_raw/makehuman: base.obj, default.mhskel, default_weights.mhw.

Coordinates: Blender, metres, z up, the body facing +y (its left side at -x).
A pose is a set of targets: where the pelvis sits, how far the spine leans,
where each wrist goes and how the hand is oriented (finger direction and the
index -> little finger direction), how far the fingers curl, where the ankles go.
Arms and legs are solved as two-bone chains.
"""

import json
import math
import os

from mathutils import Matrix, Quaternion, Vector

RAW = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", "..", "flowline_raw", "makehuman"))

_cache = {}
## Which way the palm faces relative to finger x (index -> little finger), per hand.
PALM = {"L": -1.0, "R": 1.0}


def _to_blender(x, y, z):
    # OBJ is y-up decimetres facing +z; turn it to z-up metres facing +y.
    return Vector((-x * 0.1, z * 0.1, y * 0.1))


def load():
    if _cache:
        return _cache
    verts, faces, group = [], [], None
    with open(os.path.join(RAW, "base.obj")) as f:
        for line in f:
            if line.startswith("v "):
                verts.append(_to_blender(*map(float, line.split()[1:4])))
            elif line.startswith("g "):
                group = line.split()[1]
            elif line.startswith("f ") and group == "body":
                faces.append([int(t.split("/")[0]) - 1 for t in line.split()[1:]])
    skel = json.load(open(os.path.join(RAW, "default.mhskel")))
    joints = {k: sum((verts[i] for i in v), Vector()) / len(v) for k, v in skel["joints"].items()}
    bones = {}
    for name, b in skel["bones"].items():
        bones[name] = {"parent": b["parent"], "head": joints[b["head"]], "tail": joints[b["tail"]]}
    weights = {}
    for bone, pairs in json.load(open(os.path.join(RAW, "default_weights.mhw")))["weights"].items():
        for v, w in pairs:
            weights.setdefault(v, []).append((bone, w))
    _cache.update(verts=verts, faces=faces, bones=bones, weights=weights)
    return _cache


def _order(bones):
    out, seen = [], set()

    def visit(n):
        if n in seen:
            return
        p = bones[n]["parent"]
        if p:
            visit(p)
        seen.add(n)
        out.append(n)
    for n in bones:
        visit(n)
    return out


def _frame(fdir, lat):
    f = fdir.normalized()
    l = (lat - f * lat.dot(f)).normalized()
    return Matrix((f, l, f.cross(l))).transposed()  # columns: finger, lateral, normal


def _two_bone(a, target, l1, l2, pole):
    d = target - a
    dist = min(d.length, (l1 + l2) * 0.999)
    dn = d.normalized()
    x = (l1 * l1 - l2 * l2 + dist * dist) / (2 * dist)
    h = math.sqrt(max(l1 * l1 - x * x, 0.0))
    p = (pole - dn * pole.dot(dn)).normalized()
    return a + dn * x + p * h


def pose(spec):
    """Returns (verts, faces, dominant bone per vertex) for a posed body.

    spec keys: pelvis (Vector), lean (radians forward), head_pitch (radians,
    + looks down), wrist_L/R, finger_L/R (finger direction), lateral_L/R
    (index -> little finger), curl (degrees per finger joint), thumb_curl,
    ankle_L/R, elbow_pole_L/R, knee_pole_L/R, foot_dir.
    """
    h = load()
    bones = h["bones"]
    R, M, head_p = {}, {}, {}
    lean = spec.get("lean", 0.0)
    spine = ["spine05", "spine04", "spine03", "spine02", "spine01"]
    for name in _order(bones):
        b = bones[name]
        par = b["parent"]
        if par is None:  # hips tip forward with the back
            head_p[name] = Vector(spec["pelvis"])
            rot = Quaternion(Vector((1, 0, 0)), -lean * 0.3)
        else:
            head_p[name] = M[par] @ b["head"]
            rot = R[par]
        side = "L" if name.endswith(".L") else "R"
        sx = -1.0 if side == "L" else 1.0
        if name in spine:
            k = spine.index(name) + 1
            rot = Quaternion(Vector((1, 0, 0)), -lean * (0.45 + 0.55 * k / len(spine)))
        elif name.startswith("neck") or name == "head":
            # The neck follows the back part way; the head comes up to look down the road.
            k = {"neck01": 0.7, "neck02": 0.45, "neck03": 0.2}.get(name, 0.0)
            rot = Quaternion(Vector((1, 0, 0)), -lean * k - spec.get("head_pitch", 0.0) * (1.0 - k))
        elif name.startswith(("upperarm01", "lowerarm01", "upperleg01", "lowerleg01")):
            arm = name.startswith(("upperarm", "lowerarm"))
            top = "upperarm01" if arm else "upperleg01"
            mid = "lowerarm01" if arm else "lowerleg01"
            end = "wrist" if arm else "foot"
            s = head_p[top + "." + side] if name.startswith(top) else None
            if name.startswith(top):
                l1 = (bones[mid + "." + side]["head"] - b["head"]).length
                l2 = (bones[end + "." + side]["head"] - bones[mid + "." + side]["head"]).length
                tgt = Vector(spec[("wrist_" if arm else "ankle_") + side])
                pole = Vector(spec.get(("elbow_pole_" if arm else "knee_pole_") + side,
                                       (sx, 0, -0.6) if arm else (sx * 0.3, 1, 0)))
                joint = _two_bone(s, tgt, l1, l2, pole)
                spec.setdefault("_joint", {})[top + side] = (joint, tgt)
                rest = bones[mid + "." + side]["head"] - b["head"]
                rot = rest.rotation_difference(joint - s)
            else:
                joint, tgt = spec["_joint"][top + side]
                rest = bones[end + "." + side]["head"] - b["head"]
                rot = rest.rotation_difference(tgt - joint)
                if arm:  # let the forearm carry some of the hand's twist
                    hand = _hand_rot(spec, bones, side)
                    rot = rot.slerp(hand, 0.35)
        elif name.startswith(("upperarm02", "lowerleg02", "upperleg02")):
            rot = R[par]
        elif name.startswith("lowerarm02"):
            rot = R[par].slerp(_hand_rot(spec, bones, side), 0.6)
        elif name.startswith(("wrist", "metacarpal")):
            rot = _hand_rot(spec, bones, side)
        elif name.startswith("finger"):
            hand = _hand_rot(spec, bones, side)
            f = _hand_frame(spec, side)
            axis = f.col[0].cross(f.col[2] * PALM[side])  # curls the fingers towards the palm
            seg = int(name.split("-")[1].split(".")[0])
            thumb = name.startswith("finger1")
            per = spec.get("thumb_curl", 20.0) if thumb else spec.get("curl", 55.0)
            ang = math.radians(per) * seg
            if thumb:
                axis = (axis + f.col[0] * 0.6).normalized()
            rot = Quaternion(axis, ang) @ hand
        elif name.startswith("foot") or name.startswith("toe"):
            fd = Vector(spec.get("foot_dir", (0, 1, -0.3)))
            rest = bones["toe3-1." + side]["head"] - bones["foot." + side]["head"]
            rot = rest.rotation_difference(fd)
        R[name] = rot
        M[name] = Matrix.Translation(head_p[name]) @ rot.to_matrix().to_4x4() @ Matrix.Translation(-b["head"])
    out = []
    dom = []
    for i, v in enumerate(h["verts"]):
        ws = h["weights"].get(i)
        if not ws:
            out.append(M["root"] @ v)
            dom.append("root")
            continue
        tot = sum(w for _, w in ws)
        p = Vector()
        for bone, w in ws:
            p += (M[bone] @ v) * (w / tot)
        out.append(p)
        dom.append(max(ws, key=lambda t: t[1])[0])
    return out, h["faces"], dom, head_p


def palm_normal(spec, side):
    f = _hand_frame(spec, side)
    return f.col[2] * PALM[side]


def wrist_for(grip, finger, lateral, side, palm_gap=0.03, reach=0.085):
    """Where the wrist goes so the palm closes round `grip`."""
    spec = {"finger_" + side: finger, "lateral_" + side: lateral}
    f = Vector(finger).normalized()
    return Vector(grip) - f * reach - palm_normal(spec, side) * palm_gap


def _hand_frame(spec, side):
    return _frame(Vector(spec["finger_" + side]), Vector(spec["lateral_" + side]))


def _hand_rot(spec, bones, side):
    key = "_hand" + side
    if key not in spec:
        rest = _frame(bones["finger3-1." + side]["head"] - bones["wrist." + side]["head"],
                      bones["finger5-1." + side]["head"] - bones["finger2-1." + side]["head"])
        spec[key] = (_hand_frame(spec, side) @ rest.inverted()).to_quaternion()
    return spec[key]


def hand_offset(side):
    """Rest-pose vector from the wrist to the middle of the palm, for placing wrists."""
    b = load()["bones"]
    return (b["finger3-1." + side]["head"] - b["wrist." + side]["head"]) * 0.6
