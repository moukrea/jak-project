#!/usr/bin/env python3
"""probe_c58_lipschitz.py — `phys-collide-depth` EST-ELLE 1-LIPSCHITZIENNE, ET QUE VAUT LA BORNE ?

NATURE   : un RAPPORT SANS DIMENSION |d(a)-d(b)| / |a-b|, plus des LONGUEURS en unites de jeu
           (4096 u = 1 m). Ni une amplitude ni une frequence : la question est arithmetique.
REPERE   : monde a la POSE DE BIND du mesh LIVRE (`out/jak1/fr3/skin/keira-hd-lod0.glb`),
           volumes replaces par la meme formule que `c38_nested_volumes.py`.
LECTURE HORS DEFAUT : un rapport > 1 + 1e-5 REFUTE la prediction gravee par le manager.

La transcription de `phys-collide-depth` (jak-hd-physics.gc:1064-1157) est INTEGRALE ici :
elle inclut `rlink`, la branche degeneree `a2 <= 1e-6`, la branche `dd < 1e-6`, la correction
du parametre optimal t*, LA BRANCHE `d < 0.001` (qui rend `want` et pas `want - d`), et
l'ecretage a 0. Rien n'est simplifie : c'est ce qui decide.
"""
import sys, os
import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
from c38_glb import Glb

MESH   = os.path.join(REPO, 'out/jak1/fr3/skin/keira-hd-lod0.glb')
CHAINS = os.path.join(REPO, 'recharged_assets/physics_chains.txt')
U = 4096.0
SEED = 20260820

# ==================================================================================================
# 1. LE PREDICAT DU MOTEUR, A LA LETTRE — VERSION SCALAIRE (une transcription, pas une reecriture)
# ==================================================================================================
def engine_depth(p, ca, cb, ra, rb, capsule, rlink, cone_off=0):
    """`phys-collide-depth` : profondeur ECRETEE A 0 (ce que la fonction RETOURNE)."""
    cx = float(ca[0]); cy = float(ca[1]); cz = float(ca[2]); rr = ra
    if capsule:
        ax = cb[0] - ca[0]; ay = cb[1] - ca[1]; az = cb[2] - ca[2]
        dd = ax*ax + ay*ay + az*az
        dr = rb - ra
        a2 = dd - dr*dr
        if dd < 0.000001:
            rr = rb if rb > ra else ra
        elif a2 <= 0.000001 and cone_off == 0:
            if ra >= rb:
                cx, cy, cz, rr = ca[0], ca[1], ca[2], ra
            else:
                cx, cy, cz, rr = cb[0], cb[1], cb[2], rb
        else:
            px = p[0] - ca[0]; py = p[1] - ca[1]; pz = p[2] - ca[2]
            dot = px*ax + py*ay + pz*az
            t0 = dot / dd
            if a2 > 0.000001 and cone_off == 0 and dr != 0.0:
                qx = px - ax*t0; qy = py - ay*t0; qz = pz - az*t0
                yy = np.sqrt(qx*qx + qy*qy + qz*qz)
                t0 = t0 + (dr*yy) / (np.sqrt(dd) * np.sqrt(a2))
            if t0 < 0.0: t0 = 0.0
            if t0 > 1.0: t0 = 1.0
            cx = ca[0] + ax*t0; cy = ca[1] + ay*t0; cz = ca[2] + az*t0
            rr = ra + dr*t0
    dx = p[0]-cx; dy = p[1]-cy; dz = p[2]-cz
    d = np.sqrt(dx*dx + dy*dy + dz*dz)
    want = rr + rlink
    if d >= want:
        return 0.0
    if d < 0.001:
        return want
    return want - d


def engine_depth_v(P, ca, cb, ra, rb, capsule, rlink, cone_off=0):
    """Meme fonction, vectorisee sur un tableau (N,3). Verifiee contre la scalaire."""
    ca = np.asarray(ca, float); cb = np.asarray(cb, float)
    N = len(P)
    if not capsule:
        C = np.repeat(ca[None, :], N, 0); RR = np.full(N, ra)
    else:
        a = cb - ca
        dd = float(a @ a); dr = rb - ra; a2 = dd - dr*dr
        if dd < 0.000001:
            C = np.repeat(ca[None, :], N, 0); RR = np.full(N, max(ra, rb))
        elif a2 <= 0.000001 and cone_off == 0:
            c0, r0 = (ca, ra) if ra >= rb else (cb, rb)
            C = np.repeat(c0[None, :], N, 0); RR = np.full(N, r0)
        else:
            pv = P - ca[None, :]
            t0 = (pv @ a) / dd
            if a2 > 0.000001 and cone_off == 0 and dr != 0.0:
                q = pv - a[None, :] * t0[:, None]
                yy = np.sqrt((q*q).sum(1))
                t0 = t0 + (dr*yy) / (np.sqrt(dd)*np.sqrt(a2))
            t0 = np.clip(t0, 0.0, 1.0)
            C = ca[None, :] + a[None, :]*t0[:, None]
            RR = ra + dr*t0
    D = np.sqrt(((P - C)**2).sum(1))
    want = RR + rlink
    out = np.where(D >= want, 0.0, np.where(D < 0.001, want, want - D))
    return out


def engine_depth_vd(P, ca, cb, ra, rb, capsule, rlink, cone_off=0):
    """(profondeur, d) — `d` sert UNIQUEMENT a savoir si la branche `d < 0.001` a joue."""
    ca = np.asarray(ca, float); cb = np.asarray(cb, float)
    N = len(P)
    if not capsule:
        C = np.repeat(ca[None, :], N, 0); RR = np.full(N, ra)
    else:
        a = cb - ca
        dd = float(a @ a); dr = rb - ra; a2 = dd - dr*dr
        if dd < 0.000001:
            C = np.repeat(ca[None, :], N, 0); RR = np.full(N, max(ra, rb))
        elif a2 <= 0.000001 and cone_off == 0:
            c0, r0 = (ca, ra) if ra >= rb else (cb, rb)
            C = np.repeat(c0[None, :], N, 0); RR = np.full(N, r0)
        else:
            pv = P - ca[None, :]
            t0 = (pv @ a) / dd
            if a2 > 0.000001 and cone_off == 0 and dr != 0.0:
                q = pv - a[None, :] * t0[:, None]
                yy = np.sqrt((q*q).sum(1))
                t0 = t0 + (dr*yy) / (np.sqrt(dd)*np.sqrt(a2))
            t0 = np.clip(t0, 0.0, 1.0)
            C = ca[None, :] + a[None, :]*t0[:, None]
            RR = ra + dr*t0
    D = np.sqrt(((P - C)**2).sum(1))
    want = RR + rlink
    out = np.where(D >= want, 0.0, np.where(D < 0.001, want, want - D))
    return out, D


# ==================================================================================================
# 2. LA GEOMETRIE LIVREE — 56 volumes, pose de bind, unites de jeu
# ==================================================================================================
def load_volumes():
    g = Glb(MESH)
    joints, names = g.skin()
    JW = g.joint_world()
    idx = {n: i for i, n in enumerate(names)}

    def rot(i):
        Uu, S, Vt = np.linalg.svd(JW[i][:3, :3]); return Uu @ Vt

    def jpos(n):
        return JW[idx[n]][:3, 3] * U

    vols = []
    for ln in open(CHAINS):
        t = ln.split()
        if not t: continue
        if t[0] == 'collider' and len(t) >= 4:
            n = t[1]
            if n not in idx: continue
            r = float(t[2].split('=')[1])
            off = np.array([float(x) for x in t[3].split('=')[1].split(',')])
            c = jpos(n) + rot(idx[n]) @ off
            vols.append(dict(name='sphere:'+n, ca=c, cb=c, ra=r, rb=r, cap=False))
        elif t[0] == 'capsule' and len(t) >= 5:
            a, b = t[1], t[2]
            if a not in idx or b not in idx: continue
            vols.append(dict(name='caps:%s->%s' % (a, b), ca=jpos(a), cb=jpos(b),
                             ra=float(t[3].split('=')[1]), rb=float(t[4].split('=')[1]), cap=True))
    return vols


# ==================================================================================================
# 3. T1 — LE TEST DE LIPSCHITZ
# ==================================================================================================
RLINKS = [0.0, 340.0, 345.0, 415.0, 431.0]   # 0 + les 4 rayons de lien de chestL/chestR


def lipschitz_volume(v, rng, npairs, cone_off=0):
    """Rend TROIS statistiques, parce qu'une seule melangerait deux regimes :
       - `rmax`   : max du rapport sur TOUS les couples ;
       - `rclean` : max du rapport sur les couples dont AUCUN des deux points n'est dans la
                    coquille `d < 0.001` (la seule branche discontinue du code) ;
       - `emax`   : max de l'EXCES ADDITIF |d(a)-d(b)| - |a-b|, en unites de jeu. C'est LUI qui
                    borne l'erreur d'une inegalite de Lipschitz, pas le rapport."""
    ca, cb = v['ca'], v['cb']
    ext = max(np.linalg.norm(cb-ca), 1.0)
    rmax, rdet = 0.0, None
    rclean, cdet = 0.0, None
    emax, edet = -1e18, None
    eclean, ecdet = -1e18, None       # exces ADDITIF hors coquille : le chiffre decisif
    rfloor, fdet = 0.0, None          # rapport hors coquille ET sep >= 0.01 u (hors bruit flottant)

    def account(P, Q, dA, dB, DA, DB, rl, tag=None):
        nonlocal rmax, rdet, rclean, cdet, emax, edet, eclean, ecdet, rfloor, fdet
        sep = np.linalg.norm(Q-P, axis=1)
        ok = sep > 0
        if not np.any(ok):
            return
        num = np.abs(dA-dB)[ok]
        sp = sep[ok]
        ratio = num/sp
        k = int(np.argmax(ratio))
        if ratio[k] > rmax:
            rmax = float(ratio[k])
            rdet = dict(rl=rl, sep=float(sp[k]), da=float(dA[ok][k]), db=float(dB[ok][k]), tag=tag)
        exc = num - sp
        j = int(np.argmax(exc))
        if exc[j] > emax:
            emax = float(exc[j])
            edet = dict(rl=rl, sep=float(sp[j]), da=float(dA[ok][j]), db=float(dB[ok][j]), tag=tag)
        clean = ok & (DA >= 0.001) & (DB >= 0.001)
        if np.any(clean):
            rc = np.abs(dA-dB)[clean]/sep[clean]
            i = int(np.argmax(rc))
            if rc[i] > rclean:
                rclean = float(rc[i])
                cdet = dict(rl=rl, sep=float(sep[clean][i]), da=float(dA[clean][i]),
                            db=float(dB[clean][i]), tag=tag)
            ec = np.abs(dA-dB)[clean] - sep[clean]
            m = int(np.argmax(ec))
            if ec[m] > eclean:
                eclean = float(ec[m])
                ecdet = dict(rl=rl, sep=float(sep[clean][m]), da=float(dA[clean][m]),
                             db=float(dB[clean][m]), tag=tag)
        fl = clean & (sep >= 0.01)
        if np.any(fl):
            rf = np.abs(dA-dB)[fl]/sep[fl]
            i2 = int(np.argmax(rf))
            if rf[i2] > rfloor:
                rfloor = float(rf[i2])
                fdet = dict(rl=rl, sep=float(sep[fl][i2]), da=float(dA[fl][i2]),
                            db=float(dB[fl][i2]), tag=tag)

    for rl in RLINKS:
        scale = ext + 2.0*(max(v['ra'], v['rb']) + rl)
        mid = 0.5*(ca+cb)
        A = mid[None, :] + (rng.random((npairs, 3))-0.5)*2.0*scale
        step = 10.0**rng.uniform(-6.0, np.log10(2.0*scale), npairs)
        dirn = rng.normal(size=(npairs, 3)); dirn /= np.linalg.norm(dirn, axis=1)[:, None]
        B = A + dirn*step[:, None]
        dA, DA = engine_depth_vd(A, ca, cb, v['ra'], v['rb'], v['cap'], rl, cone_off)
        dB, DB = engine_depth_vd(B, ca, cb, v['ra'], v['rb'], v['cap'], rl, cone_off)
        account(A, B, dA, dB, DA, DB, rl)

        # couples CIBLES de part et d'autre de la surface d = 0.001 : la seule discontinuite
        PP, QQ = [], []
        for _ in range(200):
            tt = rng.random()
            c = ca + (cb-ca)*tt if v['cap'] else ca
            u = rng.normal(size=3); u /= np.linalg.norm(u)
            for eps in (1e-9, 1e-7, 1e-5):
                PP.append(c + u*(0.001 - eps)); QQ.append(c + u*(0.001 + eps))
        PP = np.array(PP); QQ = np.array(QQ)
        dA, DA = engine_depth_vd(PP, ca, cb, v['ra'], v['rb'], v['cap'], rl, cone_off)
        dB, DB = engine_depth_vd(QQ, ca, cb, v['ra'], v['rb'], v['cap'], rl, cone_off)
        account(PP, QQ, dA, dB, DA, DB, rl, tag='d<0.001')
    return rmax, rdet, rclean, cdet, emax, edet, eclean, ecdet, rfloor, fdet


def main():
    rng = np.random.default_rng(SEED)
    vols = load_volumes()
    print('== GEOMETRIE LIVREE ==========================================================')
    print('volumes charges : %d   (fichier %s)' % (len(vols), CHAINS))
    ncap = sum(1 for v in vols if v['cap'])
    print('   capsules %d   spheres %d' % (ncap, len(vols)-ncap))
    print()
    print('%-26s %10s %8s %8s %12s  %s' % ('volume', 'L(u)', 'ra', 'rb', 'a2=L^2-dr^2', 'branche'))
    degen = []
    for v in vols:
        if not v['cap']:
            continue
        L = float(np.linalg.norm(v['cb']-v['ca'])); dr = v['rb']-v['ra']
        a2 = L*L - dr*dr
        br = 'DEGENEREE (sphere)' if a2 <= 1e-6 else ('tronc de cone' if dr != 0 else 'capsule')
        if a2 <= 1e-6: degen.append(v['name'])
        print('%-26s %10.2f %8.0f %8.0f %12.1f  %s' % (v['name'], L, v['ra'], v['rb'], a2, br))
    print()
    print('capsules DEGENEREES (une sphere contient l\'autre) : %s'
          % (', '.join(degen) if degen else 'AUCUNE'))
    print()

    # --- controle de transcription : la version vectorisee = la version scalaire ---------------
    bad = 0
    for v in vols[:8]:
        P = v['ca'][None, :] + (rng.random((400, 3))-0.5)*3000.0
        for rl in RLINKS:
            dv = engine_depth_v(P, v['ca'], v['cb'], v['ra'], v['rb'], v['cap'], rl)
            ds = np.array([engine_depth(P[i], v['ca'], v['cb'], v['ra'], v['rb'], v['cap'], rl)
                           for i in range(len(P))])
            bad += int(np.sum(np.abs(dv-ds) > 1e-9))
    print('CONTROLE DE TRANSCRIPTION scalaire vs vectorisee : %d desaccords sur 8 volumes x 5 rl '
          'x 400 points%s' % (bad, '' if bad == 0 else '  <-- LA SONDE EST FAUSSE'))
    print()

    for cone_off in (0, 1):
        tag = 'LIVRAISON (*phys-cone-off* = 0)' if cone_off == 0 \
              else "CONTROLE ARME (*phys-cone-off* = 1, le predicat FAUX d'avant le cycle 22)"
        print('== T1 / LIPSCHITZ — %s ==' % tag)
        gr, grd, gc, gcd, ge, ged = 0.0, None, 0.0, None, -1e18, None
        gec, gecd, gecv = -1e18, None, None
        grf, grfd, grfv = 0.0, None, None
        grv = gcv = gev = None
        per = []
        for v in vols:
            r, rd, c, cd, e, ed, ec, ecd, rf, fd = lipschitz_volume(
                v, np.random.default_rng(SEED + hash(v['name']) % 100000), 4000, cone_off)
            per.append((c, r, e, v['name'], ec, rf))
            if r > gr: gr, grd, grv = r, rd, v['name']
            if c > gc: gc, gcd, gcv = c, cd, v['name']
            if e > ge: ge, ged, gev = e, ed, v['name']
            if ec > gec: gec, gecd, gecv = ec, ecd, v['name']
            if rf > grf: grf, grfd, grfv = rf, fd, v['name']
        print('couples testes : %d  (%d volumes x %d rayons de lien x %d couples)'
              % (len(vols)*len(RLINKS)*4600, len(vols), len(RLINKS), 4600))
        print()
        print('  (A) MAX du rapport HORS de la coquille `d < 0.001`  = %.9f   porte par %s'
              % (gc, gcv))
        if gcd:
            print('        sep=%.3e u  d(a)=%.6f  d(b)=%.6f' % (gcd['sep'], gcd['da'], gcd['db']))
        print('  (B) MAX du rapport sur TOUS les couples             = %.6f   porte par %s'
              % (gr, grv))
        if grd:
            print('        sep=%.3e u  d(a)=%.6f  d(b)=%.6f  branche=%s'
                  % (grd['sep'], grd['da'], grd['db'], grd.get('tag') or 'aleatoire'))
        print('  (C) MAX de l\'EXCES ADDITIF |d(a)-d(b)| - |a-b|     = %.9f u = %.3e m'
              % (ge, ge/U))
        if ged:
            print('        porte par %s  sep=%.3e u  branche=%s'
                  % (gev, ged['sep'], ged.get('tag') or 'aleatoire'))
        print()
        print('  (D) MAX du rapport HORS coquille ET |a-b| >= 0.01 u = %.9f  porte par %s'
              % (grf, grfv))
        if grfd:
            print('        sep=%.4e u  d(a)=%.9f  d(b)=%.9f' % (grfd['sep'], grfd['da'], grfd['db']))
        print('  (E) MAX de l\'EXCES ADDITIF HORS coquille           = %.6e u = %.3e m'
              % (gec, gec/U))
        if gecd:
            print('        porte par %s  sep=%.3e u' % (gecv, gecd['sep']))
        print()
        print('  VERDICT (A) : %s'
              % ('<= 1 + 1e-5  ->  1-LIPSCHITZ hors la coquille'
                 if gc <= 1.0 + 1e-5 else 'RAPPORT > 1 hors coquille'))
        print('  VERDICT (D) : %s'
              % ('<= 1 + 1e-5  ->  1-LIPSCHITZ des que |a-b| >= 0.01 u (2.4 um)'
                 if grf <= 1.0 + 1e-5 else 'RAPPORT > 1 A SEPARATION FRANCHE : PAS 1-LIPSCHITZ'))
        print('  VERDICT (C) : |d(a)-d(b)| <= |a-b| + %.6f u  =  |a-b| + %.3e m'
              % (max(ge, 0.0), max(ge, 0.0)/U))
        per.sort(reverse=True)
        print('  les 6 plus grands rapports HORS coquille, par volume :')
        for c, r, e, nm, ec, rf in per[:6]:
            print('      %-26s clean=%.9f  sep>=0.01u=%.9f  excesclean=%.3e u'
                  % (nm, c, rf, ec))
        print()

    # ============================================================================================
    # T3 — LA CHAINE D'INEGALITES, TESTEE SUR DES CONFIGURATIONS OU LE VOLUME BOUGE
    # ============================================================================================
    print('== T3 / CONTRE-EXEMPLE — res <= |q - rest| TIENT-ELLE QUAND LE VOLUME BOUGE ? ==')
    print('   res = dep - feff,  feff = max(floorc, floors) + 0.30*b0*[le volume porte l\'ancre]')
    print('   dep    = depth(q   ; volume ANIME ca,cb)')
    print('   floorc = depth(rest; volume ANIME ca,cb)      <- MEME volume que dep')
    print('   floors = depth(rest; volume DE REPOS ra,rb)   <- volume DIFFERENT')
    B0 = 602.0
    rng2 = np.random.default_rng(SEED + 7)
    worst_gap = -1e18; worst_cfg = None
    worst_gap_free = -1e18
    NCFG = 60000
    for v in vols:
        L = max(float(np.linalg.norm(v['cb']-v['ca'])), 1.0)
        R = max(v['ra'], v['rb'])
        n = max(200, NCFG//len(vols))
        mid = 0.5*(v['ca']+v['cb'])
        scale = L + 3.0*R
        # le volume ANIME = le volume livre ; le volume DE REPOS = le meme, DEPLACE au hasard
        # (jusqu'a +-1.5 * son echelle : bien plus que ce que le rig fait en une frame)
        for _ in range(n//200):
            shift = (rng2.random(3)-0.5)*3.0*scale
            rot_a = v['ca'] + shift
            rot_b = v['cb'] + shift
            rest = mid + (rng2.random((200, 3))-0.5)*2.0*scale
            q    = mid + (rng2.random((200, 3))-0.5)*2.0*scale
            for rl in (340.0, 431.0):
                floors = engine_depth_v(rest, rot_a, rot_b, v['ra'], v['rb'], v['cap'], rl)
                floorc = engine_depth_v(rest, v['ca'], v['cb'], v['ra'], v['rb'], v['cap'], rl)
                floor0 = np.maximum(floorc, floors)
                for yieldb in (0.0, 0.30*B0):
                    feff = floor0 + yieldb
                    dep = engine_depth_v(q, v['ca'], v['cb'], v['ra'], v['rb'], v['cap'], rl)
                    res = dep - feff
                    disp = np.linalg.norm(q-rest, axis=1)
                    gap = res - disp                    # > 0 = CONTRE-EXEMPLE
                    k = int(np.argmax(gap))
                    if gap[k] > worst_gap:
                        worst_gap = float(gap[k])
                        worst_cfg = dict(vol=v['name'], rl=rl, yb=yieldb, res=float(res[k]),
                                         disp=float(disp[k]), dep=float(dep[k]),
                                         floorc=float(floorc[k]), floors=float(floors[k]))
                    # branche PHYS-VOL-FREE (*phys-col-off* = 1)
                    resf = dep - 1000000000.0
                    worst_gap_free = max(worst_gap_free, float(np.max(resf - disp)))
    print('configurations testees : ~%d (volume de repos DEPLACE au hasard jusqu\'a +-1.5x son '
          'echelle)' % NCFG)
    print('MAX ( res - |q-rest| ) = %.9f u        (> 0 serait un CONTRE-EXEMPLE)' % worst_gap)
    if worst_cfg:
        print('   argmax : %s  rl=%.0f  yield=%.1f  res=%.4f  |q-rest|=%.4f  dep=%.4f  '
              'floorc=%.4f  floors=%.4f'
              % (worst_cfg['vol'], worst_cfg['rl'], worst_cfg['yb'], worst_cfg['res'],
                 worst_cfg['disp'], worst_cfg['dep'], worst_cfg['floorc'], worst_cfg['floors']))
    print('MAX ( res - |q-rest| ) sous PHYS-VOL-FREE (*phys-col-off*=1) = %.3e u' % worst_gap_free)
    # --- configurations CIBLEES sur la coquille `d < 0.001` : q ET rest posees dessus -----------
    wg2, wc2 = -1e18, None
    for v in vols:
        for rl in (340.0, 431.0):
            for _ in range(400):
                tt = rng2.random()
                c = v['ca'] + (v['cb']-v['ca'])*tt if v['cap'] else v['ca']
                u1 = rng2.normal(size=3); u1 /= np.linalg.norm(u1)
                u2 = rng2.normal(size=3); u2 /= np.linalg.norm(u2)
                for (eq, er) in ((0.0005, 0.0015), (0.0015, 0.0005), (0.0005, 0.0005)):
                    q = np.array([c + u1*eq]); rest = np.array([c + u2*er])
                    for shift_s in (0.0, 1.0):
                        sh = (rng2.random(3)-0.5)*3.0*max(1.0, np.linalg.norm(v['cb']-v['ca']))*shift_s
                        floors = engine_depth_v(rest, v['ca']+sh, v['cb']+sh, v['ra'], v['rb'], v['cap'], rl)[0]
                        floorc = engine_depth_v(rest, v['ca'], v['cb'], v['ra'], v['rb'], v['cap'], rl)[0]
                        dep = engine_depth_v(q, v['ca'], v['cb'], v['ra'], v['rb'], v['cap'], rl)[0]
                        for yb in (0.0, 0.30*B0):
                            res = dep - (max(floorc, floors) + yb)
                            disp = float(np.linalg.norm(q[0]-rest[0]))
                            if res - disp > wg2:
                                wg2 = res - disp
                                wc2 = dict(vol=v['name'], rl=rl, res=res, disp=disp,
                                           dep=dep, floorc=floorc, yb=yb)
    print('MAX ( res - |q-rest| ) sur des configurations CIBLEES dans la coquille d<0.001 = %.9f u'
          % wg2)
    if wc2:
        print('   argmax : %s rl=%.0f yield=%.1f res=%.6f |q-rest|=%.6f dep=%.6f floorc=%.6f'
              % (wc2['vol'], wc2['rl'], wc2['yb'], wc2['res'], wc2['disp'], wc2['dep'],
                 wc2['floorc']))
    print()

    # --------------------------------------------------------------------------------------
    # T3b — LE SECOND CONTRIBUTEUR DE `meshpen` : LE FRANCHISSEMENT D'AXE (:2158-2172)
    #   `worst` recoit AUSSI `wv = (-> ub w)`, c.-a-d. la DISTANCE DE `q` A L'AXE du volume,
    #   quand `rest` et `q` sont de part et d'autre de cet axe. Ce terme n'est PAS `dep - feff`
    #   et n'est PAS soumis a `skip` : une borne sur `meshpen` doit le couvrir aussi.
    # --------------------------------------------------------------------------------------
    print('== T3b / FRANCHISSEMENT D\'AXE — wv <= |q - rest| ? ==')

    def axis_dir(P, ca, cb):
        """`phys-axis-dir` : (u unitaire, d) ; d < 0.001 -> la fonction rend #f (masque)."""
        ca = np.asarray(ca, float); cb = np.asarray(cb, float)
        a = cb - ca; dd = float(a @ a)
        if dd >= 0.000001:
            t0 = np.clip(((P - ca[None, :]) @ a)/dd, 0.0, 1.0)
            C = ca[None, :] + a[None, :]*t0[:, None]
        else:
            C = np.repeat(ca[None, :], len(P), 0)
        V = P - C
        d = np.sqrt((V*V).sum(1))
        okm = d >= 0.001
        u = np.zeros_like(V)
        u[okm] = V[okm]/d[okm][:, None]
        return u, d, okm

    rng3 = np.random.default_rng(SEED + 31)
    wworst, wcfg, ncross = -1e18, None, 0
    for v in vols:
        L = max(float(np.linalg.norm(v['cb']-v['ca'])), 1.0)
        R = max(v['ra'], v['rb'])
        mid = 0.5*(v['ca']+v['cb'])
        scale = L + 2.0*R
        for _ in range(6):
            rest = mid + (rng3.random((2000, 3))-0.5)*2.0*scale
            q    = mid + (rng3.random((2000, 3))-0.5)*2.0*scale
            ur, dr_, okr = axis_dir(rest, v['ca'], v['cb'])
            uq, dq_, okq = axis_dir(q,    v['ca'], v['cb'])
            for rl in (340.0, 431.0):
                floor0 = engine_depth_v(rest, v['ca'], v['cb'], v['ra'], v['rb'], v['cap'], rl)
                cross = okr & okq & (floor0 > 0.0) & ((ur*uq).sum(1) < 0.0)
                if not np.any(cross):
                    continue
                ncross += int(np.sum(cross))
                wv = dq_[cross]
                disp = np.linalg.norm((q-rest)[cross], axis=1)
                gap = wv - disp
                k = int(np.argmax(gap))
                if gap[k] > wworst:
                    wworst = float(gap[k])
                    wcfg = dict(vol=v['name'], rl=rl, wv=float(wv[k]), disp=float(disp[k]))
    print('   couples EN FRANCHISSEMENT trouves : %d' % ncross)
    print('   MAX ( wv - |q-rest| ) = %.9f u        (> 0 serait un CONTRE-EXEMPLE)' % wworst)
    if wcfg:
        print('   argmax : %s rl=%.0f  wv=%.4f u  |q-rest|=%.4f u'
              % (wcfg['vol'], wcfg['rl'], wcfg['wv'], wcfg['disp']))
    print()

    # ============================================================================================
    # T2 — LA CONSEQUENCE, CHIFFREE
    # ============================================================================================
    print('== T2 / CONSEQUENCE CHIFFREE ==')
    CEIL = 0.0005
    print('B0 = %.0f u = %.6f m   (physics_chains.txt: b0=602 sur chestL ET chestR)' % (B0, B0/U))
    print('plafond de la gate COLLIDE : %.4f m = %.4f u' % (CEIL, CEIL*U))
    rows = [('SPEC 22 apex   normal',     0.42), ('SPEC 22 apex   exceptionnel', 0.50),
            ('SPEC 22 COM    normal',     0.35), ('SPEC 22 COM    transitoire dur', 0.40)]
    print()
    print('%-32s %8s %10s %12s %14s' % ('ligne de SPEC 22', 'frac B0', 'u', 'm', 'x le plafond'))
    for nm, f in rows:
        u = f*B0; m = u/U
        print('%-32s %8.2f %10.2f %12.6f %14.1f' % (nm, f, u, m, m/CEIL))
    print()
    MEAS = 0.1115
    print('meshpen LIVRE = %.4f m = %.2f u = %.4f B0' % (MEAS, MEAS*U, MEAS*U/B0))
    print('   -> il IMPLIQUE |q - rest| >= %.4f m = %.2f u = %.4f B0 sur le maillon qui le porte'
          % (MEAS, MEAS*U, MEAS*U/B0))
    print('   -> soit x%.2f la borne exceptionnelle de SPEC 22 (0.50 B0)' % (MEAS*U/B0/0.50))
    print('   -> et %.4f m DEPASSE deja le meshpen maximal qu\'une poitrine conforme peut produire '
          '(%.6f m)' % (MEAS, 0.50*B0/U))
    print()
    print('== T2 bis / CE QUE `|q - rest|` EST VRAIMENT — ET LE TERME QUI N\'EST PAS L\'APEX ==')
    print('   rest = bone[kk+1].trans + off            off  = offset TOURNE par la matrice ANIMEE')
    print('   q    = pt                + offs          offs = LE MEME offset tourne par la rotation')
    print('                                                   qui envoie m^ (direction MODELE de')
    print('                                                   l\'os) sur u^ (direction SIMULEE)')
    print('   |offs| = |off| = |o| EXACTEMENT (deux reflexions de Householder = une rotation).')
    print('   Donc |q-rest| <= |pt - bone.trans| + |offs - off|, et |offs-off| = 2|o| sin(theta/2)')
    print('   ou theta = angle(m^, u^). LE SECOND TERME N\'EST PAS UN DEPLACEMENT D\'APEX.')
    print()
    offs_breast = {'lBoob': (-6, 637, -135), 'lBooc': (2, 512, -51),
                   'rBoob': (-14, -617, 124), 'rBooc': (5, -466, 36)}
    print('%-10s %12s %12s %14s' % ('collider', '|o| (u)', '2|o| (u)', 'theta pour 2.048 u'))
    for nm, o in offs_breast.items():
        mo = float(np.linalg.norm(np.array(o, float)))
        th = 2.0*np.degrees(np.arcsin(min(1.0, CEIL*U/(2.0*mo))))
        print('%-10s %12.2f %12.2f %14.4f deg' % (nm, mo, 2.0*mo, th))
    print()
    print('   LECTURE : des que le maillon tourne de ~0.18 deg par rapport a sa direction modele,')
    print('   le SEUL portage de l\'offset deplace le centre du volume de plus que le budget')
    print('   entier de la gate. La borne `res <= |q-rest|` DEVIENT DONC VIDE a cette echelle :')
    print('   elle ne peut pas servir a demontrer que 0.0005 m est atteignable.')


if __name__ == '__main__':
    main()
