"""For each still-torn chain, find the torn edges and report which joints hold the weight on the
LOW side. Those joints are the donors a `grade` rule must take from — measured, never guessed.
"""
import sys, os, re
import numpy as np

sys.path.insert(0, '/home/emeric/code/jak-project/.autoport')
os.chdir('/home/emeric/code/jak-project')
from physics_c7_reskin import read_glb, consolidate_buffers, read_accessor, skin_info

CH = {}
cur = None
for ln in open('recharged_assets/physics_chains.txt', errors='ignore'):
    s = ln.split('#')[0].strip()
    m = re.match(r'^chain (\S+)', s)
    if m:
        cur = m.group(1); CH[cur] = []
    elif s.startswith('j ') and cur:
        CH[cur].append(s.split()[1])

G = 'out/jak1/fr3/skin/keira-hd-lod0.glb'
js, bufs = read_glb(G)
binc = consolidate_buffers(js, bufs)
names, _, _ = skin_info(js, binc)
idx = {n: i for i, n in enumerate(names)}

pos = None
edges = set()
for mesh in js.get('meshes', []):
    for pr in mesh.get('primitives', []):
        at = pr['attributes']
        if pos is None:
            pos = read_accessor(js, binc, at['POSITION'])
            J = np.zeros((len(pos), 4), int); W = np.zeros((len(pos), 4), float)
        if 'indices' not in pr or int(pr.get('mode', 4)) != 4:
            continue
        ind = np.asarray(read_accessor(js, binc, pr['indices'])).reshape(-1).astype(np.int64)
        u = np.unique(ind)
        J[u] = read_accessor(js, binc, at['JOINTS_0'])[u]
        W[u] = read_accessor(js, binc, at['WEIGHTS_0'])[u]
        for i in range(0, (len(ind) // 3) * 3, 3):
            a, b, c = int(ind[i]), int(ind[i+1]), int(ind[i+2])
            for x, y in ((a, b), (b, c), (a, c)):
                edges.add((x, y) if x < y else (y, x))

for ch in ('botstrapL', 'botstrapR', 'kneeflapL', 'kneeflapR'):
    grp = [idx[j] for j in CH.get(ch, []) if j in idx]
    print('\n=== %s   joints=%s ===' % (ch, CH.get(ch)))
    if not grp:
        print('   !! no joint resolved'); continue
    ws = np.zeros(len(W))
    for c in range(4):
        ws += np.where(np.isin(J[:, c], grp), W[:, c], 0.0)
    torn = [(u, v) for (u, v) in edges if abs(ws[u] - ws[v]) > 0.5]
    print('   torn edges: %d' % len(torn))
    low = sorted({(u if ws[u] < ws[v] else v) for (u, v) in torn})
    print('   low-side verts: %d  -> %s' % (len(low), low[:12]))
    mass = {}
    for vi in low:
        for c in range(4):
            if W[vi, c] > 0:
                mass[J[vi, c]] = mass.get(J[vi, c], 0.0) + float(W[vi, c])
    tot = sum(mass.values()) or 1.0
    print('   weight on the low side, by joint:')
    for ji in sorted(mass, key=lambda j: -mass[j])[:6]:
        print('      %-16s %.3f  (%.0f%%)' % (names[ji], mass[ji], 100 * mass[ji] / tot))
    hi = sorted({(v if ws[u] < ws[v] else u) for (u, v) in torn})
    print('   step: low ws max=%.3f   high ws min=%.3f'
          % (max((ws[v] for v in low), default=0), min((ws[v] for v in hi), default=0)))
