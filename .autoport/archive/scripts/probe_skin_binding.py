"""Independent check: does the SHIPPED keira glb carry mismatched JOINTS_0/WEIGHTS_0 bindings?

Reads the mesh the bake preserved (out/jak1/fr3/skin/keira-hd-lod0.glb) and, for every distinct
(JOINTS_0, WEIGHTS_0) attribute pair used by a primitive, reports how much weight mass sits on
`prejoint` and on the physics joints. A healthy prepped glb has ONE pair and zero mass on prejoint.
"""
import sys, os
from collections import Counter

sys.path.insert(0, '/home/emeric/code/jak-project/.autoport')
os.chdir('/home/emeric/code/jak-project')
from physics_c7_reskin import read_glb, consolidate_buffers, read_accessor, skin_info

G = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
js, bufs = read_glb(G)
binc = consolidate_buffers(js, bufs)
names, _, _ = skin_info(js, binc)
print('mesh   :', G)
print('joints :', len(names))

keys = Counter()
for mesh in js.get('meshes', []):
    for pr in mesh.get('primitives', []):
        at = pr['attributes']
        keys[(at['JOINTS_0'], at['WEIGHTS_0'])] += 1

print('\ndistinct (JOINTS_0, WEIGHTS_0) pairs across primitives:')
for k, v in sorted(keys.items()):
    print('    J=%-4s W=%-4s -> %d primitive(s)' % (k[0], k[1], v))
if len(keys) > 1:
    print('    >> MORE THAN ONE PAIR: the writer left primitives on different attribute sets.')

WATCH = ('prejoint', 'hair', 'Hair', 'pantFlap', 'Ear', 'Boob', 'bang', 'Bang', 'midhair', 'Midhair')
for (aj, aw), n in sorted(keys.items()):
    J = read_accessor(js, binc, aj).astype(int)
    W = read_accessor(js, binc, aw).astype(float)
    mass = {}
    nz = {}
    for c in range(J.shape[1]):
        col_j, col_w = J[:, c], W[:, c]
        for ji, w in zip(col_j, col_w):
            if w > 0:
                mass[ji] = mass.get(ji, 0.0) + float(w)
                nz[ji] = nz.get(ji, 0) + 1
    print('\n--- key J=%s W=%s  (%d prims, %d verts) ---' % (aj, aw, n, len(J)))
    print('    total weight mass = %.2f' % sum(mass.values()))
    hits = [i for i in mass if any(t in names[i] for t in WATCH)]
    for i in sorted(hits, key=lambda i: -mass[i])[:14]:
        print('    %-18s verts=%-5d mass=%.2f' % (names[i], nz[i], mass[i]))
    pre = [i for i in mass if 'prejoint' in names[i]]
    print('    PREJOINT total: verts=%d mass=%.2f'
          % (sum(nz[i] for i in pre), sum(mass[i] for i in pre)))
