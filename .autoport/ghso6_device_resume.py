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
       8: 'garde-saute', 9: 'controle-positif-inject', 10: 'colle-par-le-garde-d-echelle-mode1'}
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
               cmd_judged=0, cmd_bones=0, cmd_frames=0, cmd_nostock=0, scl_bones=0, scl_frames=0,
               ring_ok=0, ring_bad=0, ring_nostamp=0, ring_judged=0, ring_far=0,
               stock_w_bad=0, hd_w_bad=0, scl_abs_bones=0, scl_unjudged=0)
    goal = dict(imgs=0, etimgs=0, etos=0, nan=0, drvstale=0, origine=0, blend=0, inject=0, minutes=0.0,
                cmdos=0, cmdimgs=0, sclos=0, sclimgs=0, sclep=0, drawdev=0, mtxdev=0, mtxjuges=0, mtxskel=0,
                asmdiff=0, wocc=0, wimgs=0,
                rjimgs=0, rjsauts=0, rjnan=0, rjskip=0, tpimgs=0, tpose=0, normocc=0, normimgs=0, normzero=0, normcalls=0)
    rj_worst = 0.0
    rj_worst_ok = 0.0
    rj_offmax = 0.0
    tp_hdmin, tp_hdmax, tp_pmin, tp_pmax = 100, 0, 100, 0
    norm_worst = 0.0
    normarm_seen = set()
    blend_ev = []
    rj_ev = []
    tp_ev = []
    w_worst = 0.0
    affarm_seen = set()
    scl_worst = 0.0
    goal_scl_worst = 0.0
    sclarm_seen = set()
    sclep_ev = []
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
        hl4 = [kv(l) for t, l in lines if l.startswith('HDLEN4 ')]
        hl5 = [kv(l) for t, l in lines if l.startswith('HDLEN5 ')]
        hl6 = [kv(l) for t, l in lines if l.startswith('HDLEN6 ')]
        hl7 = [kv(l) for t, l in lines if l.startswith('HDLEN7 ')]
        hl8 = [kv(l) for t, l in lines if l.startswith('HDLEN8 ')]
        hl9 = [kv(l) for t, l in lines if l.startswith('HDLEN9 ')]
        hl10 = [kv(l) for t, l in lines if l.startswith('HDLEN10 ')]
        hl11 = [kv(l) for t, l in lines if l.startswith('HDLEN11 ')]
        hm = [kv(l) for t, l in lines if l.startswith('HDMOVES ')]
        hb = [kv(l) for t, l in lines if l.startswith('HDHB ')]
        wall = [kv(l) for t, l in lines if l.startswith('HDWALL ')]
        scene = wall[-1].get('scene', path) if wall else path
        # attribution : evenements squelette (4 lignes) et GPU (1 ligne)
        cur = None
        mcur = None
        for t, l in lines:
            if l.startswith('HDSTRETCHINJECT '):
                inj_seen.add(kv(l).get('value', '?'))
            if l.startswith('HDSCALEARM '):
                sclarm_seen.add(kv(l).get('value', '?'))
            if l.startswith('HDAFFINEARM '):
                affarm_seen.add(kv(l).get('value', '?'))
            if l.startswith('HDBLEND '):
                e = kv(l); e['scene'] = scene; blend_ev.append(e)
            elif l.startswith('HDBLEND2 ') and blend_ev:
                blend_ev[-1].update(kv(l))
            if l.startswith('HDRJEV '):
                e = kv(l); e['scene'] = scene; rj_ev.append(e)
            elif l.startswith('HDRJEV2 ') and rj_ev:
                rj_ev[-1].update(kv(l))
            if l.startswith('HDTPEV '):
                e = kv(l); e['scene'] = scene; tp_ev.append(e)
            elif l.startswith('HDTPEV2 ') and tp_ev:
                tp_ev[-1].update(kv(l))
            if l.startswith('HDSCLEP '):
                sclep_ev.append(kv(l))
            elif l.startswith('HDSCLEP2 ') and sclep_ev:
                sclep_ev[-1].update(kv(l))
            if l.startswith('HDMTXDEV '):
                mcur = kv(l)
            elif l.startswith('HDMTXREF ') and mcur is not None:
                mcur.update(kv(l))
                e = mcur
                w3 = float(e.get('w3', 1.0) or 1.0)
                attribs.append(
                    f"HDATTRIB site=bones-mtx-calc scene={scene} modele={MODEL.get(int(e.get('entry', 0)), '?')} os={e.get('k')} "
                    f"parent={e.get('p')} longueur_squelette_m={e.get('len_skel_m')} longueur_matrice_merc_m={e.get('len_mtx_m')} "
                    f"squelette_vs_post_m={e.get('skel_vs_post_m')} w0={e.get('w0')} w1={e.get('w1')} w2={e.get('w2')} w3={e.get('w3')} "
                    f"asm_vs_produit_generique_u={e.get('asm_vs_goal_max_u')} "
                    f"chemin={'bones-mtx-calc-w3-different-de-1-fois-cam3-origine-du-monde' if abs(w3 - 1.0) > 1e-4 else 'bones-mtx-calc-w3-egal-1-autre'}")
                mcur = None
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
            elif l.startswith('HDLENG6 ') and cur is not None:
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
                    f"vitesse_m_s={e.get('vitesse_m_s')} echelle_base=({e.get('scl0')},{e.get('scl1')},{e.get('scl2')}) "
                    f"echelle_aberrante={e.get('sclbad')} parent_pilote={e.get('ep')} echelle_parent_pilote={e.get('sclep')}")
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
                    f"image={e.get('frame')} lignes_base={e.get('rows')} translation_brute={e.get('t')} estampille_ok={e.get('stamp_ok')} "
                    f"goal_camera={e.get('goal_cam')} ecart_goal_m={e.get('d_goal_m')}")
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
                    f"n_etires_paquet={e.get('n_stretched')} image={e.get('frame')} lignes_base={e.get('rows')} lignes_parent={e.get('prows')} "
                    f"translation_brute={e.get('t')} estampille_ok={e.get('stamp_ok')} goal_camera={e.get('goal_cam')} ecart_goal_m={e.get('d_goal_m')}")
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
        scl_worst = max(scl_worst, float(last.get('scl_worst', 0) or 0))
        if hl4:
            for k in ('sclos', 'sclimgs', 'sclep'):
                goal[k] += int(hl4[-1].get(k, 0) or 0)
            goal_scl_worst = max(goal_scl_worst, float(hl4[-1].get('pire_scl', 0) or 0))
        if hl5:
            for k in ('drawdev', 'mtxdev', 'mtxjuges', 'mtxskel'):
                goal[k] += int(hl5[-1].get(k, 0) or 0)
        if hl6:
            goal['asmdiff'] += int(hl6[-1].get('asmdiff', 0) or 0)
        if hl7:
            for k in ('wocc', 'wimgs'):
                goal[k] += int(hl7[-1].get(k, 0) or 0)
            w_worst = max(w_worst, float(hl7[-1].get('pire_w', 0) or 0))
        if hl8:
            for k in ('rjimgs', 'rjsauts', 'rjnan'):
                goal[k] += int(hl8[-1].get(k, 0) or 0)
            rj_worst = max(rj_worst, float(hl8[-1].get('pire_saut_m', 0) or 0))
            rj_worst_ok = max(rj_worst_ok, float(hl8[-1].get('pire_saut_ok_m', 0) or 0))
            rj_offmax = max(rj_offmax, float(hl8[-1].get('ecart_trans_max_m', 0) or 0))
        if hl9:
            for k in ('tpimgs', 'tpose'):
                goal[k] += int(hl9[-1].get(k, 0) or 0)
            tp_hdmin = min(tp_hdmin, int(hl9[-1].get('hd_poses_min', 100) or 100))
            tp_hdmax = max(tp_hdmax, int(hl9[-1].get('hd_poses_max', 0) or 0))
            tp_pmin = min(tp_pmin, int(hl9[-1].get('pilote_poses_min', 100) or 100))
            tp_pmax = max(tp_pmax, int(hl9[-1].get('pilote_poses_max', 0) or 0))
        if hl10:
            for k in ('normocc', 'normimgs', 'normzero', 'normcalls'):
                goal[k] += int(hl10[-1].get(k, 0) or 0)
            norm_worst = max(norm_worst, float(hl10[-1].get('pire_w_prod', 0) or 0))
            normarm_seen.add(hl10[-1].get('normarme', '?'))
        if hl11:
            goal['rjskip'] += int(hl11[-1].get('rjskip_titre_ou_reference', 0) or 0)
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
    print(f"# garde d'echelle vu par le jeu (HDSCALEARM value=) : {','.join(sorted(sclarm_seen)) or 'ABSENT (defaut GOAL = 0)'}")
    print(f"# correctif AFFINE vu par le jeu (HDAFFINEARM value=) : {','.join(sorted(affarm_seen)) or 'ABSENT (defaut GOAL = 1)'}")
    for e in sclep_ev[:60]:
        print(f"HDATTRIB site=squelette-garde-echelle modele={MODEL.get(int(e.get('entry', 0)), '?')} os={e.get('k')} pilote={e.get('e')} "
              f"parent_pilote={e.get('ep')} arme={e.get('arme')} echelle_parent=({e.get('r0')},{e.get('r1')},{e.get('r2')}) det={e.get('det')} "
              f"anim={e.get('anim')} etat={e.get('st')} chemin={'colle-par-le-garde-d-echelle-mode1' if e.get('arme') == '1' else 'reciblage-mode1-inverse-du-parent-a-echelle-aberrante'}")
    for a in attribs[:200]:
        print(a)
    # os_etires (cycle 6e) = la chaine HD de bout en bout : squelette ecrit vs commande du reciblage
    # (cmdos), echelle de la base vs echelle du pilote (x2), longueur CONSOMMEE par le GPU vs longueur
    # ECRITE (ring_far), matrice merc produite vs squelette (mtxdev). La comparaison a la reference
    # STOCK (cmd_bones) est publiee A PART : le paquet stock porte lui-meme le w != 1 que le correctif
    # retire du chemin HD (stock_w_bad), donc sa position n'est plus une commande fiable — c'est
    # l'instrument qui le mesure, pas une hypothese.
    # os_etires = os RENDUS ou ECRITS a plus de 0,25 m de la pose COMMANDEE par l'animation en cours
    # (owner 21:05 : « pas dans un sens ou ils sont censes s'etirer, pas lie a l'animation ») :
    #   - squelette : position ecrite contre le produit du reciblage de la MEME image (tous joints) ;
    #   - GPU : position consommee contre la commande derivee du paquet STOCK du pilote, MEME image
    #     (joints en mode 0, ~55 % des os juges).
    # La longueur contre le REPOS DE BIND n'est PAS le verdict : mesure Redmi dev6-inj1, Daxter
    # k=5 et k=32 rendent 5 x leur repos pendant `sidekick-attack-from-jump` avec un ecart de
    # 0,0000 m a la commande — l'animation ND etire ces os (squash & stretch), le modele stock
    # aussi. Elle reste publiee comme diagnostic (`os_longueur`).
    print(f"HDSTRETCHCOUNT bras={tag} plateforme=redmi inject={inj} scenes={scenes} minutes={wall_s/60:.4f} "
          f"minutes_de_jeu_moteur={goal['minutes']:.4f} secondes_pad={pad_s} images={gpu['hd_frames']} "
          f"os_etires={goal['cmdos'] + gpu['scl_bones'] + goal['sclos'] + gpu['ring_far'] + goal['mtxdev']} critere=squelette-vs-pose-commandee-0.25m+echelle-vs-commande-x2+longueur-consommee-vs-ecrite-0.25m+matrice-merc-vs-squelette-0.25m "
          f"os_ecart_vs_reference_stock={gpu['cmd_bones']} reference_stock_w_hors_1={gpu['stock_w_bad']} hd_w_hors_1={gpu['hd_w_bad']} "
          f"affine_arme={','.join(sorted(affarm_seen)) or '1'} matrices_pilotes_non_affines={goal['wocc']} images_non_affines={goal['wimgs']} pire_w={w_worst:.6f} "
          f"os_matrice_merc_vs_squelette={goal['mtxdev']} os_juges_bones_mtx_calc={goal['mtxjuges']} squelette_change_apres_post={goal['mtxskel']} os_changes_avant_draw={goal['drawdev']} asm_vs_generique={goal['asmdiff']} "
          f"os_echelle_gpu={gpu['scl_bones']} images_echelle_gpu={gpu['scl_frames']} pire_echelle_gpu={scl_worst:.2f} "
          f"os_echelle_squelette={goal['sclos']} images_echelle_squelette={goal['sclimgs']} pire_echelle_squelette={goal_scl_worst:.2f} "
          f"parents_pilotes_echelle_aberrante={goal['sclep']} "
          f"os_ecart_goal_gpu={gpu['ring_far']} os_compares_goal={gpu['ring_judged']} os_mauvais_ecrits_par_goal={gpu['ring_ok']} "
          f"os_mauvais_corrompus_apres_ecriture={gpu['ring_bad']} paquets_sans_estampille={gpu['ring_nostamp']} "
          f"os_etires_gpu_commande={gpu['cmd_bones']} os_etires_squelette_commande={goal['cmdos']} "
          f"images_etirees={gpu['cmd_frames'] + goal['cmdimgs']} os_juges={gpu['bones_judged']} "
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
    # cycle 7 — LA CAUSE nommee par le code : w3 de la matrice d'image AVANT normalisation, a cote
    # de la somme des poids de melange de la meme image (joint.gc). Egaux = le w EST cette somme.
    for e in blend_ev[:40]:
        try:
            eq = abs(float(e.get('w1', 0)) - float(e.get('somme_poids', 0))) < 1e-4
        except ValueError:
            eq = False
        print(f"HDATTRIB site=melange scene={e.get('scene')} w3_matrice0={e.get('w0')} w3_matrice1={e.get('w1')} "
              f"somme_poids_melange={e.get('somme_poids')} requetes={e.get('nreq')} canaux={e.get('canaux')} "
              f"anim0={e.get('anim0')} interp0={e.get('interp0')} anim1={e.get('anim1')} interp1={e.get('interp1')} "
              f"w3_egal_somme={1 if eq else 0} normalise={e.get('arme')} "
              f"chemin={'joint.gc-finalize-frame-matrices-0-1-somme-ponderee-des-canaux-w3-egale-somme-des-poids' if eq else 'joint.gc-finalize-frame-matrices-0-1-w3-different-de-la-somme-des-poids-AUTRE-CAUSE'}")
    for e in rj_ev[:40]:
        print(f"HDATTRIB site=racine scene={e.get('scene')} modele={MODEL.get(int(e.get('entry', 0)), '?')} os={e.get('k')} pilote={e.get('e')} "
              f"saut_m={e.get('saut_m')} ecart_trans_m={e.get('ecart_trans_m')} w3_pilote={e.get('w3_pilote')} chemin_os={SRC.get(int(e.get('src', 0) or 0), '?')} "
              f"anim={e.get('anim')} etat={e.get('st')} affine_arme={e.get('arme')} norm_production={e.get('normarme')} "
              f"chemin={'controle-positif-inject-bind' if e.get('src') == '9' else ('colonne-w-forcee-sans-division-xyz-reste-a-s.t' if e.get('arme') == '1' else ('matrice-pilote-homogene-non-normalisee' if e.get('arme') == '0' else 'AUTRE-a-attribuer'))}")
    for e in tp_ev[:40]:
        print(f"HDATTRIB site=tpose scene={e.get('scene')} modele={MODEL.get(int(e.get('entry', 0)), '?')} hd_poses={e.get('hd_poses')} "
              f"pilote_poses={e.get('pilote_poses')} anim={e.get('anim')} etat={e.get('st')} affine_arme={e.get('arme')} inject={e.get('inject')} "
              f"chemin={'controle-positif-inject-bind' if e.get('inject') == '2' else 'rig-HD-au-repos-pendant-que-le-pilote-est-pose-a-attribuer'}")
    # LA LIGNE DE PORTE DU CYCLE 7 (owner 03/09 : modele entier transpose + t-pose)
    print(f"HDROOTJUMP bras={tag} plateforme=redmi inject={inj} scenes={scenes} minutes={wall_s/60:.4f} "
          f"images={goal['rjimgs']} sauts_racine={goal['rjsauts']} images_tpose={goal['tpose']} "
          f"critere_saut=os-HD-de-reference-moins-root-trans-du-pilote-saute-de-plus-de-2m-entre-deux-images "
          f"pire_saut_m={rj_worst:.3f} pire_saut_sous_seuil_m={rj_worst_ok:.3f} ecart_trans_max_m={rj_offmax:.3f} sauts_non_finis={goal['rjnan']} images_non_jugees_titre_ou_reference_hors_20m={goal['rjskip']} "
          f"critere_tpose=rig-HD-moins-de-15pct-de-joints-hors-bind-pendant-que-le-pilote-en-a-plus-de-30pct "
          f"images_tpose_jugees={goal['tpimgs']} hd_poses_min_pct={tp_hdmin} hd_poses_max_pct={tp_hdmax} pilote_poses_min_pct={tp_pmin} pilote_poses_max_pct={tp_pmax} "
          f"os_hd_vs_stock_gpu={gpu['cmd_bones']} stock_w_hors_1={gpu['stock_w_bad']} hd_w_hors_1={gpu['hd_w_bad']} "
          f"matrices_pilotes_non_affines_lues={goal['wocc']} normalisations_production={goal['normocc']} images_normalisees={goal['normimgs']} "
          f"non_normalisables={goal['normzero']} pire_w_production={norm_worst:.6f} images_finalisees={goal['normcalls']} "
          f"affine_arme={','.join(sorted(affarm_seen)) or '2'} norm_production_arme={','.join(sorted(normarm_seen)) or '?'} "
          f"inject_shots={goal['inject']} modeles={','.join(modeles) if modeles else 'aucun'}")
    print(f"HDMOVES bras={tag} plateforme=redmi distance_m={mv_dist:.1f} "
          f"vitesse_moy_m_s={(sum(mv_speed)/len(mv_speed)) if mv_speed else 0.0:.2f} "
          f"sauts={mv['sauts']} demi_tours={mv['demi_tours']} coups={mv['coups']} spins={mv['spins']}")


if __name__ == '__main__':
    main()
