"""Lecteur GLB minimal, partage par les sondes du cycle 38.

NATURE / REPERE / LIGNE DE BASE (SPEC-keira-physique 7) — declares ici parce que tout
consommateur de ce module herite de ces trois reponses :
  NATURE  : des POSITIONS et des POIDS statiques. Aucune vitesse, aucune variance, aucune frame.
  REPERE  : l'espace MONDE de la pose de BIND, obtenu en composant les transformations de noeud
            depuis la racine de la scene. C'est le seul repere ou deux volumes portes par des
            joints DIFFERENTS sont comparables ; le repere local d'un joint ne le permet pas.
  BASE    : le domaine (nombre de sommets, nombre de joints) est publie par l'appelant avec
            chaque taux, pour qu'aucun pourcentage ne sorte d'un domaine vide.
"""
import json, struct
import numpy as np

_CSIZE = {5120:1, 5121:1, 5122:2, 5123:2, 5125:4, 5126:4}
_CNP   = {5120:'i1', 5121:'u1', 5122:'i2', 5123:'u2', 5125:'u4', 5126:'f4'}
_NCOMP = {'SCALAR':1, 'VEC2':2, 'VEC3':3, 'VEC4':4, 'MAT4':16}


class Glb:
    def __init__(self, path):
        self.path = path
        raw = open(path, 'rb').read()
        assert raw[:4] == b'glTF', path
        jlen = struct.unpack('<I', raw[12:16])[0]
        self.j = json.loads(raw[20:20 + jlen])
        off = 20 + jlen
        self.bin = b''
        while off < len(raw):
            clen, ctype = struct.unpack('<II', raw[off:off + 8])
            if ctype == 0x004E4942:
                self.bin = raw[off + 8:off + 8 + clen]
            off += 8 + clen + ((-clen) % 4)

    def acc(self, i):
        """Lit un accesseur en numpy, en respectant byteStride (donnees entrelacees)."""
        a = self.j['accessors'][i]
        n, nc = a['count'], _NCOMP[a['type']]
        ct = a['componentType']
        bv = self.j['bufferViews'][a.get('bufferView', 0)]
        base = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        stride = bv.get('byteStride') or _CSIZE[ct] * nc
        itm = _CSIZE[ct] * nc
        buf = np.frombuffer(self.bin, dtype=np.uint8)
        idx = (base + np.arange(n) * stride)[:, None] + np.arange(itm)[None, :]
        out = buf[idx].reshape(-1).tobytes()
        arr = np.frombuffer(out, dtype=np.dtype('<' + _CNP[ct])).reshape(n, nc)
        return arr.astype(np.float64) if ct == 5126 else arr

    # ---- hierarchie -----------------------------------------------------------------------
    def node_local(self, ni):
        nd = self.j['nodes'][ni]
        if 'matrix' in nd:
            return np.array(nd['matrix'], dtype=np.float64).reshape(4, 4).T
        m = np.eye(4)
        if 'scale' in nd:
            m = np.diag(list(nd['scale']) + [1.0]) @ m
        if 'rotation' in nd:
            x, y, z, w = nd['rotation']
            r = np.array([
                [1-2*(y*y+z*z), 2*(x*y-z*w),   2*(x*z+y*w)],
                [2*(x*y+z*w),   1-2*(x*x+z*z), 2*(y*z-x*w)],
                [2*(x*z-y*w),   2*(y*z+x*w),   1-2*(x*x+y*y)]], dtype=np.float64)
            rm = np.eye(4); rm[:3, :3] = r
            m = rm @ m
        if 'translation' in nd:
            tm = np.eye(4); tm[:3, 3] = nd['translation']
            m = tm @ m
        return m

    def world(self):
        """Matrice monde-bind de CHAQUE noeud, par descente depuis les racines de la scene."""
        n = len(self.j['nodes'])
        W = [None] * n
        # La scene ne liste que le noeud de mesh : le squelette est enracine ailleurs.
        # On descend donc depuis TOUTES les vraies racines de la foret (tout noeud qui
        # n'est l'enfant de personne), sinon 106 joints sur 106 restent sans matrice.
        kids = set()
        for nd in self.j['nodes']:
            kids.update(nd.get('children', []))
        roots = [i for i in range(n) if i not in kids]
        stack = [(r, np.eye(4)) for r in roots]
        while stack:
            ni, par = stack.pop()
            m = par @ self.node_local(ni)
            W[ni] = m
            for c in self.j['nodes'][ni].get('children', []):
                stack.append((c, m))
        return W

    # ---- peau -----------------------------------------------------------------------------
    def skin(self):
        sk = self.j['skins'][0]
        joints = sk['joints']
        names = [self.j['nodes'][i].get('name', f'node{i}') for i in joints]
        return joints, names


    def joint_world(self):
        """Matrice monde-bind de chaque JOINT, par inversion de sa inverseBindMatrix.

        POURQUOI PAS LA HIERARCHIE DE NOEUDS : dans ce fichier les 214 noeuds portent tous une
        transformation IDENTITE — les os sont litteralement a l'origine (piege connu du registre,
        « un-posed frames: bones at origin »). La pose de bind n'y vit que dans le skin, sous
        forme des `inverseBindMatrices`. La matrice monde-bind du joint est donc l'INVERSE de la
        sienne, et c'est la seule lecture qui rende des positions non nulles.
        """
        sk = self.j['skins'][0]
        ibm = self.acc(sk['inverseBindMatrices']).reshape(-1, 4, 4).transpose(0, 2, 1)
        return np.linalg.inv(ibm)

    def geometry(self):
        """Sommets en MONDE-BIND, plus (joint_idx_dans_le_skin, poids) par sommet.

        Les positions sont transformees par la matrice monde du NOEUD qui porte la primitive,
        exactement comme le fait un rendu a la pose de bind.
        """
        W = self.world()
        P, J, V = [], [], []
        for ni, nd in enumerate(self.j['nodes']):
            if 'mesh' not in nd:
                continue
            M = W[ni] if W[ni] is not None else np.eye(4)
            for pr in self.j['meshes'][nd['mesh']]['primitives']:
                at = pr['attributes']
                p = self.acc(at['POSITION'])
                p = (M[:3, :3] @ p.T).T + M[:3, 3]
                P.append(p)
                if 'JOINTS_0' in at:
                    J.append(self.acc(at['JOINTS_0']).astype(np.int32))
                    V.append(self.acc(at['WEIGHTS_0']).astype(np.float64))
                else:
                    J.append(np.zeros((len(p), 4), np.int32))
                    V.append(np.zeros((len(p), 4)))
        return np.vstack(P), np.vstack(J), np.vstack(V)
