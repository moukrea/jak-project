#!/usr/bin/env python3
"""Ghd-skin-origin-stretch cycle 4 — resume d'un BRAS APPAREIL (plusieurs scenes = plusieurs
processus gk, donc plusieurs jeux de compteurs) en UNE ligne HDSTALE au format de la porte.

Chaque scene est un lancement du jeu : les compteurs Merc2 (HDSKIN, cumul depuis le demarrage du
processus) et GOAL (HDHB*, idem) repartent de zero. On prend, par scene, le DERNIER battement de
chacun et on SOMME les scenes. Les minutes publiees sont REELLES (horodatage logcat) : du premier
paquet HD dessine (HDSKINMODEL <char>-hd-lod0) au dernier battement HDSKIN de la scene — le bout
de scene apres le dernier battement n'est compte ni au numerateur ni au denominateur ni au temps.
Les minutes de jeu GOAL (HDHB minutes=) sont publiees a cote, pas a la place.

usage : ghso4_device_resume.py <tag> <finite_arm> <marqueurs de chaque scene>...
"""
import re
import sys
from datetime import datetime

TS = re.compile(r'^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+) (.*)$')


def kv(line):
    return dict(re.findall(r'(\w+)=([^\s]+)', line))


def parse(path):
    """-> liste de (datetime|None, ligne nue)"""
    out = []
    for raw in open(path, errors='replace'):
        raw = raw.rstrip('\n')
        m = TS.match(raw)
        if m:
            t = datetime.strptime('2026-' + m.group(1), '%Y-%m-%d %H:%M:%S.%f')
            out.append((t, m.group(2)))
        else:
            out.append((None, raw))
    return out


def main():
    tag, farm, files = sys.argv[1], sys.argv[2], sys.argv[3:]
    tot = dict(frames=0, bad=0, hd_frames=0, hd_bad=0, nan=0, far=0, missing=0, repaired=0)
    goal = dict(nanimgs=0, passed=0, glued=0, bind=0, point=0, minutes=0.0, fills=0)
    wall_s = 0.0
    pad_s = 0
    models = {}
    anims = {}
    scenes = 0
    worst = 0.0
    farm_seen = set()
    for path in files:
        lines = parse(path)
        sk = [(t, kv(l)) for t, l in lines if l.startswith('HDSKIN ')]
        first_hd = [t for t, l in lines if l.startswith('HDSKINMODEL ') and '-hd-lod' in l and t]
        hb = [kv(l) for t, l in lines if l.startswith('HDHB ')]
        hb7 = [kv(l) for t, l in lines if l.startswith('HDHB7 ')]
        hb8 = [kv(l) for t, l in lines if l.startswith('HDHB8 ')]
        wall = [kv(l) for t, l in lines if l.startswith('HDWALL ')]
        for t, l in lines:
            if l.startswith('HDFINITEARM '):
                farm_seen.add(kv(l).get('value', '?'))
            if l.startswith('HDSKINEV ') and kv(l).get('hd') == '1':
                mname = kv(l).get('model', '?')
                models[mname] = models.get(mname, 0) + 1
            if l.startswith('HDNANSRC2 '):
                a = kv(l).get('anim', '?')
                anims[a] = anims.get(a, 0) + 1
        scene = wall[-1].get('scene', path) if wall else path
        if wall:
            pad_s += int(wall[-1].get('secondes', 0))
        if not sk:
            print(f"# scene {scene}: AUCUN battement HDSKIN — scene NON COMPTEE")
            scenes += 0
            continue
        t_last, last = sk[-1]
        t0 = first_hd[0] if first_hd else sk[0][0]
        span = (t_last - t0).total_seconds() if (t_last and t0) else 0.0
        span = max(span, 0.0)
        wall_s += span
        scenes += 1
        for k_src, k_dst in (('frames', 'frames'), ('bad_frames', 'bad'), ('hd_frames', 'hd_frames'),
                             ('hd_bad_frames', 'hd_bad'), ('hd_nan_bones', 'nan'),
                             ('hd_far_bones', 'far'), ('missing', 'missing'), ('repaired', 'repaired')):
            tot[k_dst] += int(last.get(k_src, 0) or 0)
        worst = max(worst, float(last.get('worst_m', 0) or 0))
        if hb:
            goal['minutes'] += float(hb[-1].get('minutes', 0) or 0)
            goal['fills'] += int(hb[-1].get('fills', 0) or 0)
        if hb7:
            goal['nanimgs'] += int(hb7[-1].get('nanimgs', 0) or 0)
        if hb8:
            for k in ('passed', 'glued', 'bind', 'point'):
                goal[k] += int(hb8[-1].get(k, 0) or 0)
        print(f"# scene {scene}: hd_frames={last.get('hd_frames','?')} hd_bad_frames={last.get('hd_bad_frames','?')} "
              f"hd_nan_bones={last.get('hd_nan_bones','?')} hd_far_bones={last.get('hd_far_bones','?')} "
              f"missing={last.get('missing','?')} repaired={last.get('repaired','?')} worst_m={last.get('worst_m','?')} "
              f"| GOAL nanimgs={hb7[-1].get('nanimgs','?') if hb7 else '?'} passed={hb8[-1].get('passed','?') if hb8 else '?'} "
              f"minutes_jeu={hb[-1].get('minutes','?') if hb else '?'} | reel={span/60:.4f} min (pad {wall[-1].get('secondes','?') if wall else '?'} s)")
    if anims:
        print("# HDNANSRC par animation du pilote : " + ' '.join(f"{a}={n}" for a, n in sorted(anims.items(), key=lambda x: -x[1])))
    if models:
        print("# HDSKINEV (HD) par modele : " + ' '.join(f"{m}={n}" for m, n in models.items()))
    print(f"# filet vu par le jeu (HDFINITEARM value=) : {','.join(sorted(farm_seen)) or 'ABSENT (defaut GOAL = 1)'}  demande={farm}")
    print(f"HDSTALE bras={tag} plateforme=redmi finite_arm={farm} scenes={scenes} minutes={wall_s/60:.4f} "
          f"minutes_de_jeu_moteur={goal['minutes']:.4f} secondes_pad={pad_s} images={tot['hd_frames']} "
          f"images_avec_matrice_perimee={tot['hd_bad']} joints_touches={tot['nan'] + tot['far']} "
          f"nan={tot['nan']} loin={tot['far']} manquants={tot['missing']} repares={tot['repaired']} "
          f"pire_m={worst:.1f} images_toutes={tot['frames']} images_mauvaises_toutes={tot['bad']} "
          f"goal_images_recibl={goal['fills']} goal_nanimgs={goal['nanimgs']} goal_passed={goal['passed']} "
          f"goal_colle={goal['glued']} goal_bind={goal['bind']} goal_point={goal['point']} "
          f"modeles={','.join(models) if models else 'aucun'}")


if __name__ == '__main__':
    main()
