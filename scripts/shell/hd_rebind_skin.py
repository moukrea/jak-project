#!/usr/bin/env python3
# scripts/shell/hd_rebind_skin.py — RELIER une piece dessinee a l'os qui porte reellement
# l'element sur lequel elle repose, AU POINT DE PRODUCTION.
#
# POURQUOI CET OUTIL EXISTE (Gjak-hd-rig-strap, owner 2026-08-29)
# ---------------------------------------------------------------------------------------------
# « la boucle en metal de la sangle dans son dos, il semblerait qu'elle soit attachee aux
#   mouvements des epaules, donc elle bouge separement de la sangle c'est bizarre et glitchy. »
#
# Mesure sur le modele LIVRE `out/jak1/fr3/skin/jak-hd-lod0.glb` : la boucle est un ILOT
# TOPOLOGIQUE separe de 8 sommets / 8 triangles, texture `jak-orig-armor`, au CENTRE du dos
# (bbox x[-0.0732,0.1701] y[1.9496,2.1860] z[-0.3930,-0.3692]), et 7 de ses 8 sommets sont
# lies a `LshoulderPad` — l'os de l'EPAULETTE, dont la pose de bind est exactement celle de
# `Lshould`. La sangle sur laquelle la boucle repose, elle, est liee a `chest`.
#
# CE QUI REND LE DIAGNOSTIC IRREFUTABLE, ET QUI EST LE CRITERE QUE CET OUTIL APPLIQUE :
# SIX des huit sommets de la boucle sont GEOMETRIQUEMENT COINCIDENTS (position de bind
# identique au 1e-6 pres) avec des sommets de la sangle et de la sacoche — et ces quatorze
# jumeaux portent TOUS `chest:1.0000`. Deux sommets a la meme position lies a des os
# DIFFERENTS se separent des que ces os divergent : c'est une DECHIRURE GARANTIE, lisible
# sans aucune course, sans aucun jugement visuel. C'est exactement « ca bouge separement ».
#
# L'outil ne devine donc pas l'os cible : il l'ADOPTE des jumeaux, et il PUBLIE l'accord ou le
# desaccord pour chaque sommet touche.
#
# CE QU'IL NE FAIT PAS, ET POURQUOI
# ---------------------------------------------------------------------------------------------
# Il ne REPARENTE aucun joint, il ne CREE ni ne SUPPRIME de joint, il ne touche a aucune
# position ni a aucun triangle. Deux raisons, toutes deux mesurees :
#   1. le nombre de joints et de sommets doit rester identique (contrat de phase) ;
#   2. une hierarchie de joints ne voyage que par `recharged_assets/hd_anim/<char>-ag.go`, dont
#      le producteur (`scripts/shell/build_hd_actor_artgroup.sh`) n'est appele par AUCUNE chaine
#      de livraison — le `jak-hd-ag.go` du zip livre le 2026-08-30 datait du 2026-08-05. Un
#      correctif pose la n'atteindrait jamais l'owner. Les POIDS DE PEAU, eux, sont refabriques
#      a chaque bake et partent dans `fr3/enhanced/GAME.fr3`. On corrige donc le lien la ou la
#      chaine de livraison le regenere.
# Le changement est neutre en pose de bind par construction : le skinning compose M_j . IBM_j,
# qui vaut l'identite au repos pour TOUT j, donc aucun sommet ne bouge a la pose d'auteur.
#
# NON IDEMPOTENT, ET C'EST VOULU. Le spec decrit ce qu'il faut faire AU MAILLAGE ISSU DU
# DONNEUR, et chaque directive porte un `expect=<n>` dur. Relance sur sa PROPRE sortie, ou sur un
# donneur dont le jeu de sommets a change, il ECHOUE BRUYAMMENT au lieu de s'appliquer a moitie en
# silence — c'est exactement le mode d'echec que cette phase existe pour fermer. Dans la chaine
# reelle il ne voit jamais que le glb frais de `prep_hd_actor_glb.py` + reskin. Il n'ecrit pas non
# plus son fichier de sortie quand une post-condition tombe : l'entree reste intacte.
#
# Usage:
#   python3 hd_rebind_skin.py --in <rig>.glb --out <rig>.glb --spec <char>-rebind-skin.txt
#                             [--report r.txt]
#
# GRAMMAIRE DU SPEC (une directive par ligne ; `#` commentaire ; ligne vide ignoree)
#   solidify <joint> tex=<texture> box=<x0>,<x1>,<y0>,<y1>,<z0>,<z1> expect=<n>
#       Tout sommet DESSINE par la piece de texture <texture> et dont la position de bind est
#       dans la boite recoit 100 % de <joint>. `expect=<n>` est une POST-CONDITION DURE : si le
#       nombre de sommets apparies n'est pas EXACTEMENT <n>, l'outil ECHOUE. Un correctif qui
#       s'applique a zero sommet en silence est le mode d'echec que cette phase existe pour
#       fermer (« HD bake silent skip »), il ne peut donc pas passer inapercu.
#
#   weld-to-twin <joint> box=<x0>,<x1>,<y0>,<y1>,<z0>,<z1> expect=<n>
#       Tout sommet DESSINE de la boite qui porte une influence de <joint> ADOPTE la liaison de
#       ses JUMEAUX COINCIDENTS — les sommets a la MEME position de bind qui, eux, ne portent PAS
#       <joint>. La valeur adoptee n'est donc pas choisie : elle est LUE sur le modele.
#       Un groupe sans jumeau, ou dont les jumeaux ne s'accordent pas entre eux, est LAISSE INTACT
#       et signale — jamais devine. `expect=<n>` compte les emplacements REECRITS, et c'est une
#       post-condition dure au meme titre que ci-dessus.
#       Toutes les copies coincidentes du meme sommet geometrique sont traitees ENSEMBLE : n'en
#       reecrire qu'une (par exemple en filtrant sur la texture) fabriquerait une NOUVELLE
#       divergence a la place de celle qu'on ferme.
import argparse
import collections
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from retarget_hd_models import (read_glb, consolidate_buffers, read_accessor,  # noqa: E402
                                write_glb, skin_info)


def _wnorm(js, bins, idx):
    """Poids en flottants 0..1 quel que soit le type de composant du glb."""
    W = read_accessor(js, bins, idx).astype(np.float64)
    ct = js['accessors'][idx]['componentType']
    if ct == 5121:
        W = W / 255.0
    elif ct == 5123:
        W = W / 65535.0
    return W


def _texname(js, prim):
    mat = prim.get('material')
    if mat is None:
        return '-'
    t = js['materials'][mat].get('pbrMetallicRoughness', {}).get('baseColorTexture', {}).get('index')
    if t is None:
        return js['materials'][mat].get('name', f'mat{mat}')
    return js['images'][js['textures'][t]['source']].get('name', '?')


def _fmt_bind(names, J, W, v):
    return ' '.join(f"{names[J[v, k]]}:{W[v, k]:.4f}"
                    for k in range(J.shape[1]) if W[v, k] > 0) or '(aucune)'


def parse_spec(path):
    ops = []
    for ln, raw in enumerate(open(path), 1):
        line = raw.split('#', 1)[0].strip()
        if not line:
            continue
        tok = line.split()
        if tok[0] not in ('solidify', 'weld-to-twin'):
            raise SystemExit(f"{path}:{ln}: directive inconnue '{tok[0]}' "
                             f"(seules `solidify` et `weld-to-twin` existent)")
        joint = tok[1] if len(tok) > 1 else None
        if not joint:
            raise SystemExit(f"{path}:{ln}: nom de joint manquant")
        kv = {}
        for t in tok[2:]:
            if '=' not in t:
                raise SystemExit(f"{path}:{ln}: champ sans '=' : '{t}'")
            k, v = t.split('=', 1)
            kv[k] = v
        needed = ('tex', 'box', 'expect') if tok[0] == 'solidify' else ('box', 'expect')
        for need in needed:
            if need not in kv:
                raise SystemExit(f"{path}:{ln}: champ '{need}=' manquant")
        for k in kv:
            if k not in needed:
                raise SystemExit(f"{path}:{ln}: champ '{k}=' inattendu pour `{tok[0]}`")
        b = [float(x) for x in kv['box'].split(',')]
        if len(b) != 6:
            raise SystemExit(f"{path}:{ln}: box= attend 6 nombres x0,x1,y0,y1,z0,z1")
        ops.append({'line': ln, 'kind': tok[0], 'joint': joint, 'tex': kv.get('tex'),
                    'box': b, 'expect': int(kv['expect'])})
    if not ops:
        raise SystemExit(f"{path}: aucune directive — un spec vide est une erreur, pas un no-op")
    return ops


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--in', dest='inp', required=True)
    ap.add_argument('--out', dest='out', required=True)
    ap.add_argument('--spec', required=True)
    ap.add_argument('--report', default=None)
    a = ap.parse_args()

    out_lines = []

    def say(s):
        out_lines.append(s)
        print(s)

    ops = parse_spec(a.spec)
    js, bufs = read_glb(a.inp)
    bins = consolidate_buffers(js, bufs)
    names, _ibms, parent = skin_info(js, bins)
    name_to_j = {n: i for i, n in enumerate(names)}

    mesh_list = js.get('meshes', [])
    if len(mesh_list) != 1:
        raise SystemExit(f"{a.inp}: {len(mesh_list)} meshes — cet outil suppose le pool partage "
                         f"unique des rips HD")
    prims = mesh_list[0]['primitives']
    apos = prims[0]['attributes']['POSITION']
    ajnt = prims[0]['attributes']['JOINTS_0']
    awgt = prims[0]['attributes']['WEIGHTS_0']
    for p in prims:
        if (p['attributes']['POSITION'] != apos or p['attributes']['JOINTS_0'] != ajnt
                or p['attributes']['WEIGHTS_0'] != awgt):
            raise SystemExit(f"{a.inp}: les pieces ne partagent pas un seul pool de sommets — "
                             f"l'appariement par index ne serait plus valide")

    P = read_accessor(js, bins, apos).astype(np.float64)
    J = read_accessor(js, bins, ajnt).astype(np.int64)
    W = _wnorm(js, bins, awgt)
    n_joints_before, n_verts_before = len(names), P.shape[0]

    # sommets DESSINES + les pieces qui les dessinent (le pool porte des sommets non references)
    drawn_by_tex = collections.defaultdict(set)
    drawn = set()
    for p in prims:
        tn = _texname(js, p)
        for v in np.unique(read_accessor(js, bins, p['indices']).astype(np.int64).ravel()):
            drawn.add(int(v))
            drawn_by_tex[tn].add(int(v))

    # groupes de sommets COINCIDENTS (meme position de bind), dessines seulement
    groups = collections.defaultdict(list)
    for v in sorted(drawn):
        groups[(round(P[v][0], 6), round(P[v][1], 6), round(P[v][2], 6))].append(v)

    W0, J0 = W.copy(), J.copy()
    say(f"[rebind] entree {a.inp}")
    say(f"[rebind] spec   {a.spec}")
    say(f"[rebind] joints={n_joints_before} sommets={n_verts_before} dessines={len(drawn)}")

    touched = set()
    for op in ops:
        jt = name_to_j.get(op['joint'])
        if jt is None:
            raise SystemExit(f"{a.spec}:{op['line']}: joint '{op['joint']}' absent du rig")
        x0, x1, y0, y1, z0, z1 = op['box']
        if op['kind'] == 'weld-to-twin':
            if not _weld_to_twin(a, op, jt, names, P, J, W, J0, W0, groups, drawn, touched, say):
                _emit(a, out_lines)
                sys.exit(1)
            continue
        pool = drawn_by_tex.get(op['tex'])
        if pool is None:
            raise SystemExit(f"{a.spec}:{op['line']}: aucune piece de texture '{op['tex']}' — "
                             f"textures presentes : {sorted(drawn_by_tex)}")
        sel = sorted(v for v in pool
                     if x0 <= P[v][0] <= x1 and y0 <= P[v][1] <= y1 and z0 <= P[v][2] <= z1)
        say(f"[rebind] solidify {op['joint']} tex={op['tex']} "
            f"box=({x0},{x1})({y0},{y1})({z0},{z1}) -> apparies={len(sel)} attendus={op['expect']}")
        if len(sel) != op['expect']:
            say(f"  !! {a.spec}:{op['line']} : {len(sel)} sommets apparies pour {op['expect']} "
                f"attendus — le correctif ne s'applique PAS a ce qu'il declare")
            _emit(a, out_lines)
            sys.exit(1)
        agree = disagree = notwin = 0
        for v in sel:
            before = _fmt_bind(names, J0, W0, v)
            J[v, :] = 0
            W[v, :] = 0.0
            J[v, 0] = jt
            W[v, 0] = 1.0
            touched.add(v)
            # controle: les JUMEAUX coincidents portent-ils la meme liaison ?
            key = (round(P[v][0], 6), round(P[v][1], 6), round(P[v][2], 6))
            twins = [t for t in groups[key] if t != v and t not in touched]
            if not twins:
                tw = '(aucun jumeau coincident)'
                notwin += 1
            else:
                tb = {_fmt_bind(names, J0, W0, t) for t in twins}
                tw = ' | '.join(sorted(tb))
                if tb == {f"{op['joint']}:1.0000"}:
                    tw += '  ACCORD'
                    agree += 1
                else:
                    tw += '  DESACCORD'
                    disagree += 1
            say(f"    v{v} ({P[v][0]:.4f},{P[v][1]:.4f},{P[v][2]:.4f}) "
                f"AVANT {before} -> APRES {op['joint']}:1.0000 ; jumeaux {tw}")
        say(f"[rebind]   jumeaux : ACCORD={agree} DESACCORD={disagree} SANS-JUMEAU={notwin}")

    # ---- post-conditions dures --------------------------------------------------------------
    if abs(W.sum(axis=1)[sorted(drawn)] - 1.0).max() > 1e-3:
        say("  !! un sommet dessine ne somme plus a 1")
        _emit(a, out_lines)
        sys.exit(1)

    # ecriture: on reecrit EN PLACE les octets des accessors JOINTS_0 / WEIGHTS_0.
    _write_back(js, bins, ajnt, J)
    _write_back(js, bins, awgt, W, weights=True)

    js2, bufs2 = js, [bytes(bins)]
    for bv in js2.get('bufferViews', []):
        bv['buffer'] = 0
    js2['buffers'] = [{'byteLength': len(bins)}]
    write_glb(a.out, js2, bins)

    # relecture du fichier ECRIT : on ne croit pas la variable en memoire
    rjs, rbufs = read_glb(a.out)
    rbins = consolidate_buffers(rjs, rbufs)
    rnames, _r, _rp = skin_info(rjs, rbins)
    rprims = rjs['meshes'][0]['primitives']
    RP = read_accessor(rjs, rbins, rprims[0]['attributes']['POSITION']).astype(np.float64)
    RJ = read_accessor(rjs, rbins, rprims[0]['attributes']['JOINTS_0']).astype(np.int64)
    RW = _wnorm(rjs, rbins, rprims[0]['attributes']['WEIGHTS_0'])
    say(f"[rebind] SORTIE {a.out}")
    say(f"[rebind]   joints AVANT={n_joints_before} APRES={len(rnames)}"
        f"{'' if len(rnames) == n_joints_before else '  !! CHANGE'}")
    say(f"[rebind]   sommets AVANT={n_verts_before} APRES={RP.shape[0]}"
        f"{'' if RP.shape[0] == n_verts_before else '  !! CHANGE'}")
    if len(rnames) != n_joints_before or RP.shape[0] != n_verts_before:
        _emit(a, out_lines)
        sys.exit(1)
    if not np.allclose(RP, P, atol=0.0):
        say("  !! des POSITIONS ont bouge — cet outil ne touche que la peau")
        _emit(a, out_lines)
        sys.exit(1)
    # CONFINEMENT, mesure et non declare : quels sommets ont change de liaison ?
    chg = set()
    for v in range(RP.shape[0]):
        b0 = sorted((int(J0[v, k]), round(float(W0[v, k]), 4))
                    for k in range(J0.shape[1]) if W0[v, k] > 0)
        b1 = sorted((int(RJ[v, k]), round(float(RW[v, k]), 4))
                    for k in range(RJ.shape[1]) if RW[v, k] > 0)
        if b0 != b1:
            chg.add(v)
    say(f"[rebind]   CONFINEMENT : sommets a liaison changee = {len(chg)} ; "
        f"declares = {len(touched)} ; hors declaration = {len(chg - touched)}")
    if chg != touched:
        say(f"  !! l'operation a deborde : {sorted(chg - touched)[:20]}")
        _emit(a, out_lines)
        sys.exit(1)
    _emit(a, out_lines)


def _weld_to_twin(a, op, jt, names, P, J, W, J0, W0, groups, drawn, touched, say):
    """Faire adopter, aux sommets qui portent <joint>, la liaison de leurs JUMEAUX COINCIDENTS.

    La valeur n'est pas choisie, elle est LUE : le referent est l'ensemble des sommets qui
    occupent la MEME position de bind et qui, eux, ne portent PAS <joint>. Un groupe sans
    referent, ou dont les referents ne s'accordent pas entre eux, est LAISSE INTACT et signale —
    on ne devine jamais a la place de l'auteur. Toutes les copies coincidentes sont reecrites
    ENSEMBLE : n'en traiter qu'une fabriquerait une nouvelle divergence a la place de l'ancienne.
    """
    x0, x1, y0, y1, z0, z1 = op['box']
    cand = [v for v in sorted(drawn)
            if x0 <= P[v][0] <= x1 and y0 <= P[v][1] <= y1 and z0 <= P[v][2] <= z1
            and any(J0[v, k] == jt and W0[v, k] > 0 for k in range(J0.shape[1]))]
    bykey = {}
    for v in cand:
        bykey.setdefault((round(P[v][0], 6), round(P[v][1], 6), round(P[v][2], 6)), []).append(v)
    say(f"[rebind] weld-to-twin {op['joint']} box=({x0},{x1})({y0},{y1})({z0},{z1}) "
        f"-> candidats={len(cand)} sur {len(bykey)} positions ; attendus={op['expect']}")
    written = []
    for key, vs in sorted(bykey.items()):
        refs = [t for t in groups[key] if t not in vs and t not in touched]
        rb = {_fmt_bind(names, J0, W0, t) for t in refs}
        if not refs:
            say(f"    ({key[0]:.4f},{key[1]:.4f},{key[2]:.4f}) INTACT — aucun jumeau referent")
            continue
        if len(rb) != 1:
            say(f"    ({key[0]:.4f},{key[1]:.4f},{key[2]:.4f}) INTACT — jumeaux en DESACCORD : "
                f"{' | '.join(sorted(rb))}")
            continue
        ref = refs[0]
        for v in vs:
            before = _fmt_bind(names, J0, W0, v)
            J[v, :] = J0[ref, :]
            W[v, :] = W0[ref, :]
            touched.add(v)
            written.append(v)
            say(f"    v{v} ({P[v][0]:.4f},{P[v][1]:.4f},{P[v][2]:.4f}) "
                f"AVANT {before} -> APRES {_fmt_bind(names, J0, W0, ref)} "
                f"(lue sur v{ref}, {len(refs)} jumeau(x) unanime(s))")
    say(f"[rebind]   emplacements reecrits={len(written)} attendus={op['expect']}")
    if len(written) != op['expect']:
        say(f"  !! {a.spec}:{op['line']} : {len(written)} emplacements reecrits pour "
            f"{op['expect']} attendus — le correctif ne s'applique PAS a ce qu'il declare")
        return False
    return True


def _write_back(js, bins, acc_idx, arr, weights=False):
    """Reecrit les octets de l'accessor, dans son type d'origine, sans bouger l'offset."""
    acc = js['accessors'][acc_idx]
    bv = js['bufferViews'][acc['bufferView']]
    ct = acc['componentType']
    base = bv.get('byteOffset', 0) + acc.get('byteOffset', 0)
    if weights:
        if ct == 5126:
            data = arr.astype('<f4')
        elif ct == 5121:
            data = np.rint(arr * 255.0).astype(np.uint8)
        elif ct == 5123:
            data = np.rint(arr * 65535.0).astype('<u2')
        else:
            raise SystemExit(f"WEIGHTS_0 componentType {ct} non supporte")
    else:
        if ct == 5121:
            data = arr.astype(np.uint8)
        elif ct == 5123:
            data = arr.astype('<u2')
        elif ct == 5125:
            data = arr.astype('<u4')
        else:
            raise SystemExit(f"JOINTS_0 componentType {ct} non supporte")
    raw = np.ascontiguousarray(data).tobytes()
    itemsize = len(raw) // acc['count']
    stride = bv.get('byteStride') or itemsize
    if stride == itemsize:
        bins[base:base + len(raw)] = raw
    else:
        for i in range(acc['count']):
            bins[base + i * stride:base + i * stride + itemsize] = raw[i * itemsize:(i + 1) * itemsize]


def _emit(a, lines):
    if a.report:
        with open(a.report, 'w') as f:
            f.write('\n'.join(lines) + '\n')


if __name__ == '__main__':
    main()
