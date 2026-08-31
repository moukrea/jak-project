#!/usr/bin/env python3
"""gjcc_verdict.py — Gjak1-crate-collision : verdict PHYSIQUE d'UNE course.

Le verdict est celui de l'owner, pas un compteur interne : on lache le joueur au-dessus de
chaque caisse et on regarde ou il S'ARRETE.
  - il repose sur la caisse (dy ~ 8368 u = 2,04 m, hauteur du dessus)  -> SOLIDE
  - il finit au niveau de la base alors que la caisse est VIVANTE et VISIBLE -> TRAVERSEE

Une caisse dont le processus n'existe pas au moment du verdict (live=0) n'est pas comptee :
elle n'est pas dessinee, donc elle n'est pas le defaut que l'owner decrit (F1).
Une caisse dont le joueur a GLISSE (il finit a plus de 1,5 m du centre en XZ) n'est pas
comptee non plus : le test n'a pas eu lieu.
"""
import re, sys, os

SOLID_DY   = 4096.0     # 1 m : la marche entre « debout dessus » (~8368) et « au sol » (~0)
SLIDE_XZ   = 6144.0     # 1,5 m : au-dela le joueur a glisse a cote, le test n'a pas eu lieu

def kv(l): return dict(re.findall(r'(\w+)=(#?[-\w.]+)', l))

def load_wp(path):
    wp = {}
    for line in open(path):
        f = line.split()
        if len(f) >= 7:
            wp[int(f[5])] = (float(f[1]), float(f[3]), f[6])   # aid -> (x, z, nom)
    return wp

def run(path, tag, wp):
    txt = open(path, errors='replace').read()
    tested, bad, notborn, slid = set(), {}, set(), set()
    landings = 0
    for line in txt.splitlines():
        if 'GJCC-LAND' not in line: continue
        d = kv(line)
        aid = int(d['aid']); dy = float(d['dy'])
        if d.get('live') != '1':
            notborn.add(aid); continue
        cx, cz, nom = wp.get(aid, (None, None, '?'))
        if cx is not None:
            if abs(float(d['px']) - cx) > SLIDE_XZ or abs(float(d['pz']) - cz) > SLIDE_XZ:
                slid.add(aid); continue
        tested.add(aid); landings += 1
        if dy < SOLID_DY:
            bad[aid] = (nom, dy, d.get('onlist'), d.get('mesh'), d.get('hid'))
    sums = [kv(l) for l in re.findall(r'^.*GJCC-SUM .*$', txt, re.M)]
    bm  = sorted({int(s['birthmax']) for s in sums if 'birthmax' in s}) if sums else []
    rt  = sorted({int(s['runtime'])  for s in sums if 'runtime'  in s}) if sums else []
    fix = {s.get('fix') for s in sums if 'fix' in s}
    fps = re.findall(r'GJCC-FPS target=(\d+) spf=([\d.]+)', txt)
    print("COURSE %s" % tag)
    print("  fps=%s  fix=%s  birth-max observe=%s  run-time us=%s"
          % (fps[-1] if fps else '?', fix or '?', bm[:6], rt[:3]))
    print("  caisses DISTINCTES testees (vivantes+dessinees)   = %d  (%d lachers)" % (len(tested), landings))
    print("  caisses SANS COLLISION                            = %d" % len(bad))
    print("  non nees au verdict (hors compte, non dessinees)  = %d" % len(notborn))
    print("  glissees a cote (test non concluant, hors compte) = %d" % len(slid))
    for aid, (nom, dy, onl, msh, hid) in sorted(bad.items()):
        print("    TRAVERSEE aid=%d %s dy=%.0f (hid=%s onlist=%s mesh=%s : nee, dessinee, enregistree)"
              % (aid, nom, dy, hid, onl, msh))
    return len(tested), len(bad)

if __name__ == '__main__':
    wp = load_wp('.autoport/gjcc_waypoints.txt')
    for a in sys.argv[1:]:
        tag = os.path.basename(a).replace('gjcc-', '').replace('.txt', '')
        t, b = run(a, tag, wp)
        print("CRATEREPRO course=%s caisses_testees=%d caisses_sans_collision=%d niveau=training" % (tag, t, b))
        print()
