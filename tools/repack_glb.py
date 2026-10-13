"""Re-encode images inside GLB files as JPEG to shrink them. Usage: python3 repack_glb.py file.glb ..."""
import json, struct, sys, io
from PIL import Image
def repack(path, q=82, max_size=None):
    b = open(path, "rb").read()
    jl = struct.unpack("<I", b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bl = struct.unpack("<I", b[off:off + 4])[0]
    binc = b[off + 8: off + 8 + bl]
    views = j["bufferViews"]
    img_views = {im["bufferView"] for im in j.get("images", []) if "bufferView" in im}
    new_bin = bytearray(); new_views = []
    for i, v in enumerate(views):
        data = binc[v.get("byteOffset", 0): v.get("byteOffset", 0) + v["byteLength"]]
        if i in img_views:
            im = Image.open(io.BytesIO(data)).convert("RGB")
            if max_size and max(im.size) > max_size: im = im.resize((max_size, max_size), Image.LANCZOS)
            o = io.BytesIO(); im.save(o, "JPEG", quality=q, optimize=True); data = o.getvalue()
        while len(new_bin) % 4: new_bin.append(0)
        nv = dict(v); nv["byteOffset"] = len(new_bin); nv["byteLength"] = len(data); nv["buffer"] = 0
        new_bin += data; new_views.append(nv)
    while len(new_bin) % 4: new_bin.append(0)
    j["bufferViews"] = new_views; j["buffers"] = [{"byteLength": len(new_bin)}]
    for im in j.get("images", []): im["mimeType"] = "image/jpeg"
    js = json.dumps(j, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    out = b"glTF" + struct.pack("<II", 2, 12 + 8 + len(js) + 8 + len(new_bin))
    out += struct.pack("<I", len(js)) + b"JSON" + js + struct.pack("<I", len(new_bin)) + b"BIN\x00" + bytes(new_bin)
    open(path, "wb").write(out)
for p in sys.argv[1:]:
    repack(p); print(p)
