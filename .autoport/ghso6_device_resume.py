#!/usr/bin/env python3
"""Ghd-skin-origin-stretch cycle 6 — resume d'un BRAS APPAREIL en lignes de porte :
HDSTRETCHCOUNT (l'etirement compte par le code, aux DEUX sites), HDMOVES (ce que le personnage a
fait, compte par les entrees d'etat) et HDATTRIB (un os etire = un os, sa longueur, son point de
fuite, le CHEMIN DE CODE qui a produit la matrice).

Chaque scene est un lancement du jeu : compteurs Merc2 (HDSKINLEN) et GOAL (HDLEN/HDLEN2/HDMOVES)
repartent de zero ; on prend le DERNIER battement par scene et on SOMME. Minutes REELLES =
horodatage logcat du premier paquet HD dessine (HDSKINMODEL <char>-hd-lod0) au dernier battement
HDSKINLEN de la scene. `os_etires` = ce que le GPU a CONSOMME (le symptome, la ou l'owner regarde) ;
le compte squelette est publie a cote, jamais a la place.

usage : ghso6_device_resume.py <tag> <inject> <marqueurs de chaque scene>...
"""
import re
import sys
from datetime import datetime

TS = re.compile(r'^(\d\d-\d\d \d\d:\d\d:\d\d\.\d+) (.*)$')
SRC = {0: 'aucun-pose-stock', 1: 'reciblage-mode0', 2: 'reciblage-mode3', 3: 'reciblage-mode1',
       4: 'colle', 5: 'filet-repare', 6: 'filet-perime-repare', 7: 'pose-de-secours',
       8: 'garde-saute', 9: 'controle-positif-inject'}
MODEL = {0: 'jak', 1: 'daxter', 2: 'keira', 3: 'samos', 4: 'jak', 5: 'jak', 6: 'daxter', 7: 'keira',
         8: 'samos', 9: 'jak', 10: 'jak'}


def kv(line):
    return dict(re.findall(r'(\w+)=([^\s]+)', line))


def parse(path):
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
    tag, inj, files = sys.argv[1], sys.argv[2], sys.argv[3:]
    gpu = dict(frames=0, hd_frames=0, hd_stretch_frames=0, hd_stretch_bones=0, bones_judged=0,
               torn=0, same=0, nan=0, null=0, rep=0, norig=0, hd_bad_frames=0, hd_bad_bones=0,
               cmd_judged=0, cmd_bones=0, cmd_frames=0, cmd_nostock=0)
    goal = dict(imgs=0, etimgs=0, etos=0, nan=0, drvstale=0, origine=0, blend=0, inject=0, minutes=0.0,
                cmdos=0, cmdimgs=0)
    mv = dict(sauts=0, demi_tours=0, coups=0, spins=0)
    mv_dist = 0.0
    mv_speed = []
    cmd_worst = 0.0
    goal_cmd_worst = 0.0
    wall_s = 0.0
    pad_s = 0
    scenes = 0
    worst_ratio = 0.0
    worst_m = 0.0
    inj_seen = set()
    ents = 0
    attribs = []
    models_gpu = {}
    for path in files:
        lines = parse(path)
        sl = [(t, kv(l)) for t, l in lines if l.startswith('HDSKINLEN ')]
        first_hd = [t for t, l in lines if l.startswith('HDSKINMODEL ') and '-hd-lod' in l and t]
        hl = [kv(l) for t, l in lines if l.startswith('HDLEN ')]
        hl2 = [kv(l) for t, l in lines if l.startswith('HDLEN2 ')]
        hl3 = [kv(l) for t, l in lines if l.startswith('HDLEN3 ')]
        hm = [kv(l) for t, l in lines if l.startswith('HDMOVES ')]
        hb = [kv(l) for t, l in lines if l.startswith('HDHB ')]
        wall = [kv(l) for t, l in lines if l.startswith('HDWALL ')]
        scene = wall[-1].get('scene', path) if wall else path
        # attribution : evenements squelette (4 lignes) et GPU (1 ligne)
        cur = None
        for t, l in lines:
            if l.startswith('HDSTRETCHINJECT '):
                inj_seen.add(kv(l).get('value', '?'))
            if l.startswith('HDLENG '):
                cur = kv(l)
                cur['_t'] = t
            elif l.startswith('HDLENG2 ') and cur is not None:
                cur.update(kv(l))
            elif l.startswith('HDLENG3 ') and cur is not None:
                cur.update(kv(l))
            elif l.startswith('HDLENG4 ') and cur is not None:
                cur.update(kv(l))
            elif l.startswith('HDLENG5 ') and cur is not None:
                cur.update(kv(l))
                e = cur
                src = int(e.get('src', 0))
                try:
                    dorig = float(e.get('dorig_m', 1e9))
                except ValueError:
                    dorig = 1e9
                attribs.append(
                    f"HDATTRIB site=squelette scene={scene} modele={MODEL.get(int(e.get('entry', 0)), '?')} "
                    f"entry={e.get('entry')} os={e.get('k')} parent={e.get('p')} pilote={e.get('e')} mode={e.get('md')} "
                    f"chemin={SRC.get(src, str(src))} chemin_parent={SRC.get(int(e.get('psrc', 0)), '?')} "
                    f"longueur_m={e.get('len_m')} repos_m={e.get('rest_m')} ratio={e.get('ratio')} "
                    f"fuite=({e.get('px')},{e.get('py')},{e.get('pz')}) dist_origine_m={e.get('dorig_m')} "
                    f"est_origine={1 if dorig < 6.0 else 0} dist_personnage_m={e.get('dref_m')} "
                    f"pilote_perime={e.get('drvstale')} canaux={e.get('chans')} anim0={e.get('anim0')} "
                    f"interp0={e.get('interp0')} anim1={e.get('anim1')} etat={e.get('st')} image_sautee={e.get('skipped')} "
                    f"pose_cmd={e.get('cmd')} ecart_commande_m={e.get('ecart_cmd_m')} longueur_commandee_m={e.get('len_cmd_m')} "
                    f"vitesse_m_s={e.get('vitesse_m_s')}")
                cur = None
            elif l.startswith('HDCMDEV '):
                e = kv(l)
                m = e.get('model', '?')
                models_gpu[m] = models_gpu.get(m, 0) + 1
                if e.get('torn') == '1':
                    chemin = 'gpu-lecture-dechiree-goal-reecrit-pendant-le-rendu'
                elif e.get('rep') == '1':
                    chemin = 'gpu-reparation-merc2'
                elif e.get('same') == '1':
                    chemin = 'gpu-matrice-identique-a-l-image-precedente'
                else:
                    chemin = 'gpu-ecart-a-la-pose-commandee-voir-squelette-meme-image'
                attribs.append(
                    f"HDATTRIB site=gpu-commande scene={scene} modele={m} pid={e.get('pid')} pilote_pid={e.get('drv')} "
                    f"os={e.get('k')} pilote={e.get('e')} ecart_commande_m={e.get('dev_m')} ecart_prec_m={e.get('dev_prev_m')} "
                    f"saut_m={e.get('saut_m')} longueur_commandee_m={e.get('len_cmd_m')} longueur_rendue_m={e.get('len_ren_m')} "
                    f"angle_deg={e.get('angle_deg')} rendu_camera={e.get('ren')} commande_camera={e.get('cmd')} "
                    f"chemin={chemin} torn={e.get('torn')} same={e.get('same')} rep={e.get('rep')} stock_gap={e.get('stock_gap')} "
                    f"image={e.get('frame')}")
            elif l.startswith('HDLENEV '):
                e = kv(l)
                m = e.get('model', '?')
                models_gpu[m] = models_gpu.get(m, 0) + 1
                if e.get('nan') == '1':
                    chemin = 'gpu-os-non-fini'
                elif e.get('null') == '1':
                    chemin = 'gpu-matrice-nulle'
                elif e.get('torn') == '1':
                    chemin = 'gpu-lecture-dechiree-goal-reecrit-pendant-le-rendu'
                elif e.get('rep') == '1':
                    chemin = 'gpu-reparation-merc2'
                elif e.get('same') == '1' and e.get('gap') == '1':
                    chemin = 'gpu-matrice-identique-a-l-image-precedente'
                else:
                    chemin = 'gpu-autre-voir-squelette-meme-image'
                attribs.append(
                    f"HDATTRIB site=gpu scene={scene} modele={m} pid={e.get('pid')} os={e.get('k')} "
                    f"parent={e.get('parent')} longueur_m={e.get('len_m')} repos_m={e.get('rest_m')} "
                    f"ratio={e.get('ratio')} fuite_camera={e.get('pos')} parent_camera={e.get('ppos')} "
                    f"chemin={chemin} nan={e.get('nan')} null={e.get('null')} torn={e.get('torn')} "
                    f"same={e.get('same')} psame={e.get('psame')} gap={e.get('gap')} rep={e.get('rep')} "
                    f"n_etires_paquet={e.get('n_stretched')} image={e.get('frame')}")
        if wall:
            pad_s += int(wall[-1].get('secondes', 0))
        if not sl:
            print(f"# scene {scene}: AUCUN battement HDSKINLEN — scene NON COMPTEE")
            continue
        t_last, last = sl[-1]
        t0 = first_hd[0] if first_hd else sl[0][0]
        span = max((t_last - t0).total_seconds() if (t_last and t0) else 0.0, 0.0)
        wall_s += span
        scenes += 1
        for k in gpu:
            gpu[k] += int(last.get(k, 0) or 0)
        worst_ratio = max(worst_ratio, float(last.get('worst_ratio', 0) or 0))
        worst_m = max(worst_m, float(last.get('worst_m', 0) or 0))
        cmd_worst = max(cmd_worst, float(last.get('cmd_worst_m', 0) or 0))
        if hl3:
            for k in ('cmdos', 'cmdimgs'):
                goal[k] += int(hl3[-1].get(k, 0) or 0)
            goal_cmd_worst = max(goal_cmd_worst, float(hl3[-1].get('pire_cmd_m', 0) or 0))
        if hl:
            for k in ('imgs', 'etimgs', 'etos', 'nan'):
                goal[k] += int(hl[-1].get(k, 0) or 0)
        if hl2:
            for k in ('drvstale', 'origine', 'blend', 'inject'):
                goal[k] += int(hl2[-1].get(k, 0) or 0)
            ents |= int(hl2[-1].get('ents', 0) or 0)
        if hb:
            goal['minutes'] += float(hb[-1].get('minutes', 0) or 0)
        if hm:
            for k in mv:
                mv[k] += int(hm[-1].get(k, 0) or 0)
            mv_dist += float(hm[-1].get('distance_m', 0) or 0)
            mv_speed.append(float(hm[-1].get('vitesse_moy_m_s', 0) or 0))
        print(f"# scene {scene}: GPU hd_frames={last.get('hd_frames','?')} hd_stretch_frames={last.get('hd_stretch_frames','?')} "
              f"hd_stretch_bones={last.get('hd_stretch_bones','?')} bones_judged={last.get('bones_judged','?')} "
              f"torn={last.get('torn','?')} same={last.get('same','?')} nan={last.get('nan','?')} null={last.get('null','?')} "
              f"rep={last.get('rep','?')} norig={last.get('norig','?')} worst_ratio={last.get('worst_ratio','?')} "
              f"hd_bad_bones={last.get('hd_bad_bones','?')} cmd_judged={last.get('cmd_judged','?')} cmd_bones={last.get('cmd_bones','?')} "
              f"cmd_nostock={last.get('cmd_nostock','?')} "
              f"| GOAL imgs={hl[-1].get('imgs','?') if hl else '?'} etimgs={hl[-1].get('etimgs','?') if hl else '?'} "
              f"etos={hl[-1].get('etos','?') if hl else '?'} inject={hl2[-1].get('inject','?') if hl2 else '?'} "
              f"| MOVES {hm[-1] if hm else 'ABSENT'} | reel={span/60:.4f} min (pad {wall[-1].get('secondes','?') if wall else '?'} s)")
    modeles = sorted({MODEL[i] for i in range(11) if ents & (1 << i)} | set(models_gpu))
    print(f"# inject vu par le jeu (HDSTRETCHINJECT value=) : {','.join(sorted(inj_seen)) or 'ABSENT (defaut GOAL = 0)'}  demande={inj}")
    for a in attribs[:200]:
        print(a)
    # os_etires = UNION des deux criteres au point de consommation GPU (longueur > 2 x repos + 0,25 m
    # OU ecart > 0,25 m a la pose COMMANDEE par l'animation en cours, derivee du paquet stock du
    # pilote dans la MEME image) ; les deux criteres sont publies a part, et le squelette a cote.
    print(f"HDSTRETCHCOUNT bras={tag} plateforme=redmi inject={inj} scenes={scenes} minutes={wall_s/60:.4f} "
          f"minutes_de_jeu_moteur={goal['minutes']:.4f} secondes_pad={pad_s} images={gpu['hd_frames']} "
          f"os_etires={gpu['hd_bad_bones']} images_etirees={gpu['hd_bad_frames']} os_juges={gpu['bones_judged']} "
          f"os_longueur={gpu['hd_stretch_bones']} images_longueur={gpu['hd_stretch_frames']} "
          f"os_ecart_commande={gpu['cmd_bones']} images_ecart_commande={gpu['cmd_frames']} os_compares_commande={gpu['cmd_judged']} "
          f"pire_ecart_commande_m={cmd_worst:.2f} paquets_sans_stock={gpu['cmd_nostock']} "
          f"torn={gpu['torn']} same={gpu['same']} nan={gpu['nan']} null={gpu['null']} rep={gpu['rep']} sans_rig={gpu['norig']} "
          f"pire_ratio={worst_ratio:.2f} pire_m={worst_m:.2f} "
          f"images_squelette={goal['imgs']} os_etires_squelette={goal['etos']} images_etirees_squelette={goal['etimgs']} "
          f"nan_squelette={goal['nan']} pilote_perime={goal['drvstale']} origine={goal['origine']} melange={goal['blend']} "
          f"os_ecart_commande_squelette={goal['cmdos']} images_ecart_commande_squelette={goal['cmdimgs']} "
          f"pire_ecart_commande_squelette_m={goal_cmd_worst:.3f} "
          f"inject_shots={goal['inject']} modeles={','.join(modeles) if modeles else 'aucun'}")
    print(f"HDMOVES bras={tag} plateforme=redmi distance_m={mv_dist:.1f} "
          f"vitesse_moy_m_s={(sum(mv_speed)/len(mv_speed)) if mv_speed else 0.0:.2f} "
          f"sauts={mv['sauts']} demi_tours={mv['demi_tours']} coups={mv['coups']} spins={mv['spins']}")


if __name__ == '__main__':
    main()
