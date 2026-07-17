#!/usr/bin/env python3
# Grecharged-hd-models2: offline software render of a ripped/retargeted GLB.
# Textured (per-vertex UV sample), lambert-shaded, painter-sorted triangles.
# Used for bind-pose garble checks and the rip-vs-jak2-intro source-proof stills.
import io
import json
import struct
import sys

import numpy as np
from PIL import Image

sys.path.insert(0, __file__.rsplit('/', 2)[0] + '/scripts/shell')
from retarget_hd_models import read_glb, consolidate_buffers, read_accessor


def render(glb_path, out_png, yaw_deg=25.0, res=900):
    js, bufs = read_glb(glb_path)
    binc = consolidate_buffers(js, bufs)

    # gather triangles across prims with their material's texture
    tex_cache = {}

    def material_texture(mi):
        if mi in tex_cache:
            return tex_cache[mi]
        img = None
        try:
            mat = js['materials'][mi]
            ti = mat['pbrMetallicRoughness']['baseColorTexture']['index']
            src = js['textures'][ti]['source']
            image = js['images'][src]
            if 'bufferView' in image:
                bv = js['bufferViews'][image['bufferView']]
                raw = bytes(binc[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
            elif image.get('uri', '').startswith('data:'):
                import base64
                raw = base64.b64decode(image['uri'].split(',', 1)[1])
            else:
                raw = None
            if raw:
                img = np.asarray(Image.open(io.BytesIO(raw)).convert('RGB'), dtype=np.float32)
        except Exception:
            img = None
        tex_cache[mi] = img
        return img

    all_tris = []
    all_cols = []
    prims = []
    for mesh in js['meshes']:
        prims.extend(mesh['primitives'])
    pos = read_accessor(js, binc, prims[0]['attributes']['POSITION']).astype(np.float64)
    uv = (read_accessor(js, binc, prims[0]['attributes']['TEXCOORD_0']).astype(np.float64)
          if 'TEXCOORD_0' in prims[0]['attributes'] else None)
    for p in prims:
        idx = read_accessor(js, binc, p['indices']).reshape(-1)
        tris = idx.reshape(-1, 3)
        tex = material_texture(p.get('material', -1))
        if tex is not None and uv is not None:
            h, w, _ = tex.shape
            u = np.clip((uv[:, 0] % 1.0) * (w - 1), 0, w - 1).astype(int)
            v = np.clip((uv[:, 1] % 1.0) * (h - 1), 0, h - 1).astype(int)
            vcol = tex[v, u]
            tcol = vcol[tris].mean(axis=1)
        else:
            tcol = np.full((len(tris), 3), 170.0)
        all_tris.append(tris)
        all_cols.append(tcol)
    tris = np.concatenate(all_tris)
    tcol = np.concatenate(all_cols)

    # camera: yaw around Y, look at bbox center
    yaw = np.deg2rad(yaw_deg)
    R = np.array([[np.cos(yaw), 0, np.sin(yaw)], [0, 1, 0], [-np.sin(yaw), 0, np.cos(yaw)]])
    pts = pos @ R.T
    used = np.unique(tris)
    lo, hi = pts[used].min(axis=0), pts[used].max(axis=0)
    ctr = (lo + hi) / 2
    scale = (res * 0.9) / max(hi[0] - lo[0], hi[1] - lo[1])
    xy = (pts[:, :2] - ctr[:2]) * scale + res / 2
    xy[:, 1] = res - xy[:, 1]
    z = pts[:, 2]

    a, b, c = tris[:, 0], tris[:, 1], tris[:, 2]
    e1 = pts[b] - pts[a]
    e2 = pts[c] - pts[a]
    n = np.cross(e1, e2)
    nl = np.linalg.norm(n, axis=1)
    nl[nl < 1e-12] = 1
    n = n / nl[:, None]
    light = np.array([0.3, 0.6, 0.74])
    lam = 0.35 + 0.65 * np.abs(n @ light)
    shade = np.clip(tcol * lam[:, None], 0, 255).astype(np.uint8)

    order = np.argsort(z[tris].mean(axis=1))  # back-to-front
    from PIL import ImageDraw
    im = Image.new('RGB', (res, res), (24, 24, 28))
    dr = ImageDraw.Draw(im)
    for t in order:
        p0, p1, p2 = xy[tris[t, 0]], xy[tris[t, 1]], xy[tris[t, 2]]
        dr.polygon([tuple(p0), tuple(p1), tuple(p2)], fill=tuple(shade[t]))
    im.save(out_png)
    print(f"{out_png}: {len(tris)} tris, bbox {np.round(hi - lo, 2)}")


if __name__ == '__main__':
    render(sys.argv[1], sys.argv[2], yaw_deg=float(sys.argv[3]) if len(sys.argv) > 3 else 25.0)
