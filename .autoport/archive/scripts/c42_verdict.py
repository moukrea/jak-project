#!/usr/bin/env python3
"""C42 — verdict de l'intervention 'borne de repli commensurable a l'os'.
Compare la course AVANT (C41E2-POPCOM, borne absolue) et APRES (C42E3, borne * bl/bl_racine).
Ne juge que des lignes de trace ; n'invente aucune grandeur."""
import sys, collections, math

DN = {5: 'BASE', 4: 'tilt', 0: 'updown', 1: 'leftright', 2: 'accel', 3: 'jerk'}
ORD = [5, 4, 0, 1, 2, 3]

def load(path):
    d = {'GRAD': {}, 'COMWL': {}, 'ACC': {}, 'GRADS': {}, 'STR': {}, 'COMD': {}, 'ROW': [], 'BONE': {}}
    for ln in open(path, errors='replace'):
        p = ln.split()
        if not p: continue
        t = p[0]
        try: kv = dict(x.split('=', 1) for x in p[1:] if '=' in x)
        except ValueError: continue
        if t == 'PHYSGRAD':
            d['GRAD'][(int(kv['c']), int(kv['a']), int(kv['d']), int(kv['l']))] = (float(kv['amp']), float(kv['ang']))
        elif t == 'PHYSGRADS':
            d['GRADS'][(int(kv['c']), int(kv['a']), int(kv['d']), int(kv['l']))] = (float(kv['a0']), float(kv['a1']))
        elif t == 'PHYSCOMWL':
            d['COMWL'][(int(kv['c']), int(kv['a']), int(kv['d']), int(kv['l']))] = (float(kv['ee']), float(kv['jt']))
        elif t == 'PHYSACC':
            d['ACC'][(int(kv['c']), int(kv['a']), int(kv['d']))] = float(kv['acc'])
        elif t == 'PHYSSTR':
            d['STR'][(int(kv['c']), int(kv['a']), int(kv['d']))] = float(kv['el'])
        elif t == 'PHYSBONE':
            d['BONE'][(int(kv['c']), int(kv['l']))] = float(kv['len'])
        elif t == 'PHYSLIM4':
            d['LIM4'] = (float(kv['sat_n']), float(kv['sat_sum']), float(kv['stif_n']))
        elif t == 'PHYSLIMW':
            d['LIMW'] = (float(kv['wall_n']), float(kv['wall_sum']))
    return d

def stats(vals):
    v = sorted(vals); n = len(v)
    return (v[0], v[n // 2], v[-1], sum(v) / n) if n else (0, 0, 0, 0)

def sec(title): print('\n' + '=' * 96 + '\n' + title + '\n' + '=' * 96)

A = load(sys.argv[1]); B = load(sys.argv[2])
print("AVANT :", sys.argv[1]); print("APRES :", sys.argv[2])

sec("1. LONGUEURS D'OS — inchangees par construction (le rig n'a pas bouge)")
for k in sorted(A['BONE']):
    print(f"   c={k[0]} l={k[1]}  avant={A['BONE'][k]:9.4f}  apres={B['BONE'].get(k, float('nan')):9.4f}")

sec("2. LE REPLI PROPRE DE CHAQUE MAILLON (PHYSGRAD ang, deg, max de fenetre) — LA CIBLE")
print(f"   {'chain':6} {'l':>2} {'drive':10} | {'AVANT min/med/max':>26} | {'APRES min/med/max':>26} | max x")
for c in (0, 1):
    for l in (0, 1):
        for dr in ORD:
            a = [v[1] for k, v in A['GRAD'].items() if k[0] == c and k[3] == l and k[2] == dr]
            b = [v[1] for k, v in B['GRAD'].items() if k[0] == c and k[3] == l and k[2] == dr]
            if not a or not b: continue
            sa, sb = stats(a), stats(b)
            print(f"   c={c:<4} {l:>2} {DN[dr]:10} | {sa[0]:7.2f}{sa[1]:9.2f}{sa[2]:10.2f} | {sb[0]:7.2f}{sb[1]:9.2f}{sb[2]:10.2f} | x{sa[2]/max(sb[2],1e-9):5.2f}")
        print()

sec("3. EXCURSION DU CENTROIDE DE CHAIR PAR MAILLON (PHYSCOMWL ee, en B0) et le JOINT SEUL (jt)")
for c in (0, 1):
    for l in (0, 1):
        a = [v[0] for k, v in A['COMWL'].items() if k[0] == c and k[3] == l]
        b = [v[0] for k, v in B['COMWL'].items() if k[0] == c and k[3] == l]
        aj = [v[1] for k, v in A['COMWL'].items() if k[0] == c and k[3] == l]
        bj = [v[1] for k, v in B['COMWL'].items() if k[0] == c and k[3] == l]
        sa, sb = stats(a), stats(b); ja, jb = stats(aj), stats(bj)
        print(f"   c={c} l={l}  ee  med {sa[1]:.4f} -> {sb[1]:.4f}   max {sa[2]:.4f} -> {sb[2]:.4f}  ({100*(sb[2]-sa[2])/max(sa[2],1e-9):+.1f} %)")
        print(f"            jt  med {ja[1]:.4f} -> {jb[1]:.4f}   max {ja[2]:.4f} -> {jb[2]:.4f}  ({100*(jb[2]-ja[2])/max(ja[2],1e-9):+.1f} %)")

sec("4. LE STIMULUS RECU — il ne doit PAS avoir bouge (l'intervention est en aval)")
for c in (0, 1):
    for dr in ORD:
        a = [v for k, v in A['ACC'].items() if k[0] == c and k[2] == dr]
        b = [v for k, v in B['ACC'].items() if k[0] == c and k[2] == dr]
        if not a: continue
        print(f"   c={c} {DN[dr]:10} recu moyen {sum(a)/len(a):9.3f} -> {sum(b)/len(b):9.3f}   {'IDENTIQUE' if abs(sum(a)-sum(b))<1e-6 else 'DIFFERENT'}")

sec("5. ETAGES DU SOLVEUR (PHYSGRADS) — ce que les contraintes retirent, avant/apres")
for c in (0, 1):
    for l in (0, 1):
        a0 = [v[0] for k, v in A['GRADS'].items() if k[0] == c and k[3] == l]
        a1 = [v[1] for k, v in A['GRADS'].items() if k[0] == c and k[3] == l]
        b0 = [v[0] for k, v in B['GRADS'].items() if k[0] == c and k[3] == l]
        b1 = [v[1] for k, v in B['GRADS'].items() if k[0] == c and k[3] == l]
        print(f"   c={c} l={l}  etage0 (integration seule) max {max(a0):8.2f} -> {max(b0):8.2f}"
              f"   etage1 (apres contraintes) max {max(a1):8.2f} -> {max(b1):8.2f}")

sec("6. ELONGATION RELATIVE (PHYSSTR el) — la contrainte de longueur doit toujours tenir")
for c in (0, 1):
    a = [v for k, v in A['STR'].items() if k[0] == c]; b = [v for k, v in B['STR'].items() if k[0] == c]
    print(f"   c={c}  el max {max(a):.6f} -> {max(b):.6f}")

sec("7. LE SUPPRESSEUR, CHIFFRE (SPEC 7 du contrat) — PHYSLIM4 / PHYSLIMW")
for key, names in (('LIM4', ('sat_n (evenements)', 'sat_sum (unites de jeu)', 'stif_n (sous-pas)')),
                   ('LIMW', ('wall_n', 'wall_sum'))):
    a = A.get(key); b = B.get(key)
    if not a or not b: 
        print(f"   {key} : absent d'une des deux courses"); continue
    for i, nm in enumerate(names):
        print(f"   {nm:28} avant {a[i]:14.2f}   apres {b[i]:14.2f}   ({100*(b[i]-a[i])/max(abs(a[i]),1e-9):+.1f} %)")
sec("8. DISCRIMINANT — l'ecart du MAXIMUM du maillon racine entre pilotages (seuil 25 %)")
for tag, D in (('AVANT', A), ('APRES', B)):
    for c in (0, 1):
        per = {}
        for dr in ORD:
            v = [x[1] for k, x in D['GRAD'].items() if k[0] == c and k[3] == 0 and k[2] == dr]
            if v: per[DN[dr]] = max(v)
        hi, lo = max(per.values()), min(per.values())
        print(f"   {tag} c={c} l=0  max par pilotage " + " · ".join(f"{k} {v:.2f}" for k, v in per.items()))
        print(f"        ecart (hi-lo)/hi = {100*(hi-lo)/hi:.1f} %   -> {'SATURE (non discriminant)' if (hi-lo)/hi < 0.25 else 'discrimine'}")
