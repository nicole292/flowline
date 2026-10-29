"""Packs a Godot web export into a Claude artifact folder.

    python tools/web/pack_artifact.py build/web2 build/artifact

Artifact files must be <= 15 MB each, so the engine (.wasm) and game data
(.pck) are gzipped and split into parts; the page's loader fetches the parts,
joins and un-gzips them in the browser, and hands Godot normal responses.
"""
import gzip
import json
import os
import shutil
import sys

PART = 14_000_000

SRC, DST = sys.argv[1], sys.argv[2]
os.makedirs(DST, exist_ok=True)
for f in os.listdir(DST):
    os.remove(os.path.join(DST, f))


def pack(src_name, prefix, ctype):
    raw = open(os.path.join(SRC, src_name), "rb").read()
    gz = gzip.compress(raw, 9)
    parts = []
    for i in range(0, len(gz), PART):
        name = "%s%d.wasm" % (prefix, i // PART)
        with open(os.path.join(DST, name), "wb") as f:
            f.write(gz[i:i + PART])
        parts.append(name)
    print(src_name, len(raw), "->", len(gz), parts)
    return {"parts": parts, "type": ctype, "size": len(raw), "packed": len(gz)}


spec = {
    "index.wasm": pack("index.wasm", "engine", "application/wasm"),
    "index.pck": pack("index.pck", "data", "application/octet-stream"),
}
for f in ("index.js", "index.audio.worklet.js", "index.audio.position.worklet.js"):
    shutil.copy(os.path.join(SRC, f), os.path.join(DST, f))
shutil.copy(os.path.join(SRC, "index.apple-touch-icon.png"), os.path.join(DST, "icon.png"))

godot_cfg = {"args": [], "canvasResizePolicy": 2, "emscriptenPoolSize": 8,
             "ensureCrossOriginIsolationHeaders": False, "executable": "index", "experimentalVK": False,
             "fileSizes": {"index.pck": spec["index.pck"]["size"], "index.wasm": spec["index.wasm"]["size"]},
             "focusCanvas": True, "gdextensionLibs": [], "godotPoolSize": 4}
total_mb = (spec["index.pck"]["packed"] + spec["index.wasm"]["packed"]) / 1e6

template = open(os.path.join(os.path.dirname(__file__), "page_template.html"), encoding="utf-8").read()
page = (template.replace("__PARTS__", json.dumps(spec))
        .replace("__GODOT_CONFIG__", json.dumps(godot_cfg))
        .replace("__TOTAL_MB__", "%.0f" % total_mb))
with open(os.path.join(DST, "flowline.html"), "w", encoding="utf-8") as f:
    f.write(page)
print("total download %.1f MB" % total_mb, sorted(os.listdir(DST)))
