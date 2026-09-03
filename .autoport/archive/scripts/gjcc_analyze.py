#!/usr/bin/env python3
"""gjcc_analyze.py — Gjak1-crate-collision : depouille UNE course.

Une caisse est « sans collision » quand elle est VISIBLE (hid=0) et que sa forme n'est
pas utilisable par le joueur : pas de primitive racine (rp=0), pas de maillage lie
(mesh=0), un masque a zero (as=0 ou with=0), ou — et c'est le chemin silencieux —
elle n'est sur AUCUNE des listes que `fill-from-foreground-using-box` parcourt (onlist=0).

Le verdict est publie PAR COURSE, jamais agrege : « des fois aucunes » rend une course
propre non concluante, donc une moyenne noierait les courses cassees.
"""
import re, sys, collections

def kv(line):
    return dict(re.findall(r'(\w+)=(#?[-\w.,/]+)', line))

def main(path, tag):
    txt = open(path, errors='replace').read()
    crates = collections.OrderedDict()   # aid -> dict of observations
    scans  = collections.OrderedDict()   # scan tag -> sum dict
    for line in txt.splitlines():
        if 'GJCC-CRATE' in line:
            d = kv(line)
            aid = d.get('aid')
            if aid is None: continue
            st  = int(d.get('tag', -1))
            if st >= 900:   # 900/901/902 = controle positif, hors recensement
                bucket = crates.setdefault(('CTRL', st), {})
            else:
                bucket = crates.setdefault(aid, {})
            live = d.get('live') == '1'
            hid  = d.get('hid') == '1'
            bad = False
            if live and not hid:
                bad = (d.get('rp') == '0' or d.get('mesh') == '0'
                       or d.get('onlist') == '0'
                       or d.get('as') in ('#x0', '0') or d.get('with') in ('#x0', '0'))
                bucket['seen'] = True
                bucket['bad'] = bucket.get('bad', False) or bad
                if bad:
                    bucket.setdefault('why', []).append(
                        'rp=%s mesh=%s onlist=%s as=%s with=%s scan=%s' %
                        (d.get('rp'), d.get('mesh'), d.get('onlist'), d.get('as'), d.get('with'), d.get('tag')))
                bucket['look'] = d.get('look')
                bucket['pos']  = (d.get('x'), d.get('y'), d.get('z'))
        elif 'GJCC-SUM' in line:
            d = kv(line)
            scans[d.get('tag')] = d

    tested = [a for a, b in crates.items() if not isinstance(a, tuple) and b.get('seen')]
    bad    = [a for a in tested if crates[a].get('bad')]

    nocon = len(re.findall(r'GJCC-NOCON', txt))
    ovf   = len(re.findall(r'Exceeded max number of collide-cache prims', txt))
    nomesh= len(re.findall(r'Failed to find collision meshes', txt))

    # occupation maximale des pools sur la course
    def peak(field, idx=1):
        vals = []
        for d in scans.values():
            v = d.get(field)
            if v and ',' in v:
                try: vals.append(int(v.split(',')[0]))
                except ValueError: pass
        return max(vals) if vals else -1
    def cap(field):
        for d in scans.values():
            v = d.get(field)
            if v and '/' in v:
                try: return int(v.split('/')[-1])
                except ValueError: pass
        return -1
    ccp = max([int(d.get('ccprims', 0)) for d in scans.values()] or [-1])
    cct = max([int(d.get('cctris', 0)) for d in scans.values()] or [-1])

    print("COURSE %s  fichier=%s" % (tag, path))
    print("  scans=%d  caisses_vues=%d  caisses_sans_collision=%d"
          % (len(scans), len(tested), len(bad)))
    print("  pools (pic parcouru/capacite) : uhbp=%d/%d hbp=%d/%d hbo=%d/%d plist=%d/%d"
          % (peak('uhbp'), cap('uhbp'), peak('hbp'), cap('hbp'),
             peak('hbo'), cap('hbo'), peak('plist'), cap('plist')))
    print("  collide-cache pic : prims=%d/100 tris=%d" % (ccp, cct))
    print("  GJCC-NOCON=%d  ccprim-overflow=%d  find-collision-meshes-fail=%d" % (nocon, ovf, nomesh))
    for a in bad:
        print("  CAISSE SANS COLLISION aid=%s look=%s pos=%s  %s"
              % (a, crates[a].get('look'), crates[a].get('pos'), crates[a]['why'][0]))
    # controle positif
    for st in (900, 901, 902):
        d = scans.get(str(st))
        if d:
            print("  CONTROLE tag=%s nocol=%s vis=%s" % (st, d.get('nocol'), d.get('vis')))
    print("CRATEREPRO course=%s caisses_testees=%d caisses_sans_collision=%d niveau=training"
          % (tag, len(tested), len(bad)))

if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else '?')
