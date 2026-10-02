#!/usr/bin/env python3
"""Post-process GLB files exported by assimp from SCP:CB .b3d models.

- embeds referenced textures (looked up by basename in --texdir)
- removes non-triangle primitives (B3D debug lines)
- splits the single long B3D animation into named clips (frame ranges @ fps)

usage: glbtool.py in.glb out.glb --texdir DIR [--fps 20] [--clip name:start:end ...]
"""
import argparse, json, os, struct
import numpy as np

COMP = {5126: np.float32, 5123: np.uint16, 5125: np.uint32, 5121: np.uint8}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def load(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF"
    off = 12
    j = None
    binc = b""
    while off < len(b):
        ln, typ = struct.unpack("<II", b[off:off + 8])
        data = b[off + 8:off + 8 + ln]
        if typ == 0x4E4F534A:
            j = json.loads(data)
        elif typ == 0x004E4942:
            binc = data
        off += 8 + ln
    return j, bytearray(binc)


def compact(j, binc):
    """drop unreferenced accessors / bufferViews (old animation data)"""
    used_acc = set()
    for m in j.get("meshes", []):
        for pr in m["primitives"]:
            used_acc.update(pr["attributes"].values())
            if "indices" in pr:
                used_acc.add(pr["indices"])
            for t in pr.get("targets", []):
                used_acc.update(t.values())
    for a in j.get("animations", []):
        for sm in a["samplers"]:
            used_acc.update([sm["input"], sm["output"]])
    for sk in j.get("skins", []):
        if "inverseBindMatrices" in sk:
            used_acc.add(sk["inverseBindMatrices"])
    acc_map = {}
    new_acc = []
    for i, a in enumerate(j.get("accessors", [])):
        if i in used_acc:
            acc_map[i] = len(new_acc)
            new_acc.append(a)
    used_bv = {a["bufferView"] for a in new_acc if "bufferView" in a}
    used_bv |= {im["bufferView"] for im in j.get("images", []) if "bufferView" in im}
    bv_map = {}
    new_bv = []
    out = bytearray()
    for i, bv in enumerate(j.get("bufferViews", [])):
        if i not in used_bv:
            continue
        while len(out) % 4:
            out += b"\0"
        o = bv.get("byteOffset", 0)
        data = binc[o:o + bv["byteLength"]]
        nb = dict(bv)
        nb["byteOffset"] = len(out)
        out += data
        bv_map[i] = len(new_bv)
        new_bv.append(nb)
    for a in new_acc:
        if "bufferView" in a:
            a["bufferView"] = bv_map[a["bufferView"]]
    for im in j.get("images", []):
        if "bufferView" in im:
            im["bufferView"] = bv_map[im["bufferView"]]
    for m in j.get("meshes", []):
        for pr in m["primitives"]:
            pr["attributes"] = {k: acc_map[v] for k, v in pr["attributes"].items()}
            if "indices" in pr:
                pr["indices"] = acc_map[pr["indices"]]
            if "targets" in pr:
                pr["targets"] = [{k: acc_map[v] for k, v in t.items()} for t in pr["targets"]]
    for a in j.get("animations", []):
        for sm in a["samplers"]:
            sm["input"] = acc_map[sm["input"]]
            sm["output"] = acc_map[sm["output"]]
    for sk in j.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = acc_map[sk["inverseBindMatrices"]]
    j["accessors"] = new_acc
    j["bufferViews"] = new_bv
    return out


def save(path, j, binc):
    binc = compact(j, binc)
    while len(binc) % 4:
        binc += b"\0"
    j["buffers"] = [{"byteLength": len(binc)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    out = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(binc))
    out += struct.pack("<II", len(js), 0x4E4F534A) + js
    out += struct.pack("<II", len(binc), 0x004E4942) + bytes(binc)
    open(path, "wb").write(out)


def read_acc(j, binc, i):
    a = j["accessors"][i]
    bv = j["bufferViews"][a["bufferView"]]
    dt = COMP[a["componentType"]]
    n = NCOMP[a["type"]]
    start = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 0)
    item = np.dtype(dt).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(bytes(binc), dtype=np.uint8)
        rows = [raw[start + k * stride:start + k * stride + item] for k in range(a["count"])]
        arr = np.frombuffer(b"".join(r.tobytes() for r in rows), dtype=dt)
    else:
        arr = np.frombuffer(bytes(binc[start:start + item * a["count"]]), dtype=dt)
    return arr.reshape(a["count"], n) if n > 1 else arr.copy()


def add_view(j, binc, data):
    while len(binc) % 4:
        binc += b"\0"
    off = len(binc)
    binc += data
    j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": len(data)})
    return len(j["bufferViews"]) - 1


def add_acc(j, binc, arr, typ):
    arr = np.ascontiguousarray(arr, dtype=np.float32)
    bv = add_view(j, binc, arr.tobytes())
    acc = {"bufferView": bv, "componentType": 5126, "count": int(arr.shape[0]), "type": typ}
    if typ == "SCALAR":
        acc["min"] = [float(arr.min())]
        acc["max"] = [float(arr.max())]
    j["accessors"].append(acc)
    return len(j["accessors"]) - 1


def sample(t, v, at, is_quat):
    if at <= t[0]:
        return v[0]
    if at >= t[-1]:
        return v[-1]
    k = int(np.searchsorted(t, at)) - 1
    f = (at - t[k]) / max(1e-9, t[k + 1] - t[k])
    a, b = v[k], v[k + 1].copy()
    if is_quat:
        if np.dot(a, b) < 0:
            b = -b
        r = a * (1 - f) + b * f
        return r / max(1e-9, np.linalg.norm(r))
    return a * (1 - f) + b * f


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("inp")
    ap.add_argument("out")
    ap.add_argument("--texdir", required=True)
    ap.add_argument("--fps", type=float, default=20.0)
    ap.add_argument("--clip", action="append", default=[])
    ap.add_argument("--noanim", action="store_true")
    ap.add_argument("--wrap", default="", help="rotx,roty,scale applied via a new root node")
    ap.add_argument("--rename", action="append", default=[], help="old=new texture basename")
    o = ap.parse_args()
    j, binc = load(o.inp)
    ren = dict(r.split("=", 1) for r in o.rename)

    # embed images
    for img in j.get("images", []):
        uri = img.pop("uri", None)
        if uri is None:
            continue
        base = os.path.basename(uri.replace("\\", "/"))
        base = ren.get(base, base)
        cands = [f for f in os.listdir(o.texdir) if f.lower() == base.lower()]
        if not cands:
            stem = os.path.splitext(base)[0].lower()
            cands = [f for f in os.listdir(o.texdir) if os.path.splitext(f)[0].lower() == stem]
        if not cands:
            print("  !! texture not found:", base)
            img["uri"] = base
            continue
        p = os.path.join(o.texdir, cands[0])
        # re-encode as PNG (some SCP:CB JPEGs are progressive) and cap the size
        from PIL import Image
        import io
        im = Image.open(p)
        im = im.convert("RGBA" if im.mode in ("RGBA", "LA", "P") else "RGB")
        if max(im.size) > 1024:
            im.thumbnail((1024, 1024))
        bio = io.BytesIO()
        im.save(bio, "PNG", optimize=True)
        img["bufferView"] = add_view(j, binc, bio.getvalue())
        img["mimeType"] = "image/png"

    # drop non triangle primitives
    for m in j.get("meshes", []):
        m["primitives"] = [p for p in m["primitives"] if p.get("mode", 4) == 4]
    used = {i for i, m in enumerate(j.get("meshes", [])) if m["primitives"]}
    for n in j.get("nodes", []):
        if "mesh" in n and n["mesh"] not in used:
            del n["mesh"]
            n.pop("skin", None)

    # materials: matte-ish defaults
    for mat in j.get("materials", []):
        pbr = mat.setdefault("pbrMetallicRoughness", {})
        pbr["metallicFactor"] = 0.0
        pbr["roughnessFactor"] = 0.85
        pbr["baseColorFactor"] = [1, 1, 1, 1]
        mat.pop("extensions", None)

    if o.noanim:
        j.pop("animations", None)
        j.pop("skins", None)
        for n in j.get("nodes", []):
            n.pop("skin", None)
    if o.clip and j.get("animations"):
        src = j["animations"][0]
        new_anims = []
        for spec in o.clip:
            name, s, e = spec.split(":")
            ts, te = float(s) / o.fps, float(e) / o.fps
            samplers, channels = [], []
            for ch in src["channels"]:
                sm = src["samplers"][ch["sampler"]]
                t = read_acc(j, binc, sm["input"]).astype(np.float64).reshape(-1)
                v = read_acc(j, binc, sm["output"]).astype(np.float64)
                is_q = ch["target"]["path"] == "rotation"
                if len(t) == 1:
                    nt, nv = np.array([0.0]), v[:1]
                else:
                    mask = (t > ts) & (t < te)
                    nt = np.concatenate([[ts], t[mask], [te]])
                    nv = np.stack([sample(t, v, ts, is_q)] + list(v[mask]) + [sample(t, v, te, is_q)])
                    nt = nt - ts
                ti = add_acc(j, binc, nt, "SCALAR")
                vi = add_acc(j, binc, nv, "VEC4" if is_q else "VEC3")
                samplers.append({"input": ti, "output": vi, "interpolation": "LINEAR"})
                channels.append({"sampler": len(samplers) - 1, "target": ch["target"]})
            new_anims.append({"name": name, "samplers": samplers, "channels": channels})
        j["animations"] = new_anims
    if o.wrap:
        rx, ry, sc = (float(v) for v in o.wrap.split(","))
        import math
        def q_axis(ax, deg):
            h = math.radians(deg) / 2
            v = [0.0, 0.0, 0.0]
            v[ax] = math.sin(h)
            return v + [math.cos(h)]
        def qmul(a, b):
            ax, ay, az, aw = a
            bx, by, bz, bw = b
            return [aw*bx + ax*bw + ay*bz - az*by, aw*by - ax*bz + ay*bw + az*bx,
                    aw*bz + ax*by - ay*bx + az*bw, aw*bw - ax*bx - ay*by - az*bz]
        q = qmul(q_axis(1, ry), q_axis(0, rx))
        sc_idx = j.get("scene", 0)
        roots = j["scenes"][sc_idx]["nodes"]
        j["nodes"].append({"name": "FixRoot", "rotation": q, "scale": [sc, sc, sc], "children": roots})
        j["scenes"][sc_idx]["nodes"] = [len(j["nodes"]) - 1]
    save(o.out, j, binc)
    print("wrote", o.out, os.path.getsize(o.out) // 1024, "KB")


if __name__ == "__main__":
    main()
