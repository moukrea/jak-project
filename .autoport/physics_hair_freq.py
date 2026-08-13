#!/usr/bin/env python3
"""physics_hair_freq.py — DEPLACE LA RESONANCE DES CHAINES DE CHEVEUX, ET RIEN D'AUTRE.

Phase Grecharged-secondary-motion, defaut PRIORITE 1 `hair-gradient`.

CE QU'IL FAUT SAVOIR AVANT DE LIRE LE CODE — la grandeur, son repere, sa nature.
  NATURE   : une FREQUENCE PROPRE (Hz), pas une amplitude. Elle ne se lit pas dans le
             tableau, elle se CALCULE depuis les parametres livres et les longueurs d'os
             que le moteur publie lui-meme (`bones_m`).
  REPERE   : sans objet — un rapport de frequences est sans dimension et sans repere.
  QUAND LE DEFAUT EST ABSENT : f_pointe / f_pilotage >> 1. Le pilotage de la salle vaut
             1/36 frame = 1.667 Hz (phys-room.gc, PHYSROOM-PERIOD).

LE MECANISME, ET IL EST ARITHMETIQUE, PAS UNE OPINION.
Le moteur pose w = 2*pi*stiffness/sqrt(mass) et k2 = (w*dt)^2, puis k_l = k2*(lmean/bl_l)^2
(jak-hd-physics.gc:2691-2693 et 3016-3019). La frequence propre du maillon l vaut donc

    f_l = (stiffness / sqrt(mass)) * (lmean / bl_l)          [Hz]

et son amortissement reduit zeta_l = damping / (2 * 2*pi*f_l/60).

Pour `lbang` tel que livre (stiffness 1.05, mass 1.35, os libres 0.0962 et 0.1914 m) :
    f_milieu = 1.351 Hz   zeta = 1.27      f_pointe = 0.679 Hz   zeta = 2.53
Les deux maillons sont donc SOUS le pilotage (1.667 Hz) et tres suramortis. Au-dessus de sa
resonance un oscillateur repond en 1/(w/wn)^2 : la pointe est etouffee 13x plus fort que le
milieu, et le rapport theta2/theta1 s'inverse. C'est exactement ce que l'owner decrit
(« le milieu bouge, les pointes sont ancrees ») et ce que ROOM-GRADIENT mesure.

CE QUE CE SCRIPT CHANGE, ET C'EST UN SEUL DEGRE DE LIBERTE PAR CHAINE : la position de la
resonance. `stiffness` est recalculee pour placer la frequence du maillon de POINTE sur une
cible, et `damping` est recalculee pour tenir un amortissement reduit constant a cette
nouvelle frequence — sans quoi changer la raideur changerait aussi zeta et on ne saurait
plus lequel des deux a agi.

CE QU'IL NE CHANGE PAS : `couple`, le gain de la pseudo-force du repere accelere. Le moteur
l'applique a une ACCELERATION deja exprimee en u/frame^2, donc sa valeur physique est 1.0 et
elle en est deja proche (0.70). Le toucher melangerait « ou est la resonance » et « quelle
force recoit la chaine » dans la meme course.

CE QU'IL CORRIGE EN MEME TEMPS, ET CE N'EST PAS UN SECOND REGLAGE (`--keep-sag`, par defaut).
L'affaissement gravitaire est une reponse QUASI-STATIQUE : sag = gravity*|g|/k, donc il varie
en 1/s^2 quand on deplace la resonance d'un facteur s. Ce n'est pas une hypothese, c'est
mesure — course du 2026-08-12, `--ftip 3.0` avec `gravity` laisse tel quel :
    lmidhair  sag 0.0357 -> 0.0124   rapport 2.88   contre s^2 = 2.8798 attendu
    backhair  sag 0.0317 -> 0.0111   rapport 2.86   contre s^2 = 2.4998
    lbang     sag 0.1182 -> 0.0098   rapport 12.1   contre s^2 = 19.53
Laisser tomber l'affaissement serait changer DEUX choses (la forme de la reponse en frequence
ET le gain statique) en n'en declarant qu'une. `gravity` est donc multiplie par s^2, ce qui
tient le gain statique EXACTEMENT constant : la seule chose qui change reste la position de
la resonance. C'est la gate FLOOR-WEAK qui a rendu ce point visible — elle lit la reponse au
plus faible stimulus, et le plus faible stimulus de la salle EST la gravite.
"""
import argparse
import math
import re
import sys

CH = "recharged_assets/physics_chains.txt"

ROOM = ".autoport/reports/Grecharged-secondary-motion/keira-room-table.txt"

# Longueurs d'os LIVREES PAR LE MOTEUR (`bones_m` du tableau de la salle), en metres.
# Le maillon 0 est verrouille (rootlock=1) sur toutes ces chaines : les maillons LIBRES
# sont les suivants, et ce sont eux seuls qui entrent dans lmean (jak-hd-physics.gc:3394).
#
# CETTE TABLE ETAIT ECRITE EN DUR, ET ELLE A PERIME EN SILENCE. L'injection de joint du
# 2026-08-13 a fait passer `lbang` de 3 a 4 maillons ; la table, elle, en portait toujours 3.
# Le script calculait donc lmean sur les os d'AVANT et rendait une frequence propre fausse de
# 26 % (1.070 Hz publie contre 1.353 Hz reelle) — c'est-a-dire exactement la grandeur qu'il
# existe pour tenir. C'est la meme classe de panne que les tables de comptage de joints deja
# rencontrees : une COPIE d'un fait qui vit ailleurs, qui derive des que l'original bouge.
#
# La copie est donc supprimee. Les longueurs sont LUES dans le tableau de la salle, c'est-a-dire
# publiees par le moteur lui-meme sur le rig courant, et le script REFUSE de tourner si le
# tableau manque ou si le nombre d'os n'est pas celui de la chaine livree. Il ne peut plus
# calculer sur une geometrie qui n'existe plus : la panne est rendue impossible au point de
# production au lieu d'etre detectable apres coup (DIRECTIVES, regle de non-destruction).
HAIR = ("lbang", "rbang", "backhair", "lmidhair", "rmidhair")


def read_bones(room_path, chains_path):
    """nom -> [longueurs d'os, en metres], lues dans `bones_m` du tableau de la salle.

    Verifie contre le fichier de chaines LIVRE que le compte d'os est bien celui de la chaine :
    une chaine de N joints publie N longueurs (maillon 0 = ancre -> joint 0)."""
    try:
        txt = open(room_path, errors="ignore").read()
    except OSError as e:
        raise SystemExit("REFUS: tableau de salle illisible (%s). Lance une course d'abord : "
                         "les longueurs d'os se lisent dans `bones_m`, elles ne se supposent pas."
                         % e)
    njoint = {}
    for ln in open(chains_path, errors="ignore"):
        if ln.startswith("chain "):
            cur = ln.split()[1]
            njoint[cur] = 0
        elif ln.startswith("j ") and njoint:
            njoint[cur] += 1
    bones = {}
    for m in re.finditer(r"^\s*chain (\S+)\s+links=(\d+).*?bones_m=([0-9.,]+)\s*$",
                         txt, re.M):
        name, links, vals = m.group(1), int(m.group(2)), m.group(3)
        b = [float(v) for v in vals.split(",") if v]
        if len(b) != links:
            raise SystemExit("REFUS: %s publie %d longueurs pour %d maillons — tableau incoherent"
                             % (name, len(b), links))
        if name in njoint and njoint[name] != links:
            raise SystemExit("REFUS: %s a %d joints dans le fichier livre mais %d maillons dans "
                             "le tableau — la course ne mesure pas la chaine livree."
                             % (name, njoint[name], links))
        bones[name] = b
    manque = [c for c in HAIR if c not in bones]
    if manque:
        raise SystemExit("REFUS: pas de bones_m pour %s dans %s" % (",".join(manque), room_path))
    return bones


def get(line, key, default=None):
    m = re.search(r"\b%s=([0-9.]+)" % key, line)
    return float(m.group(1)) if m else default


def put(line, key, val):
    return re.sub(r"\b%s=[0-9.]+" % key, "%s=%.4f" % (key, val), line, count=1)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--ftip", type=float, required=True,
                    help="frequence propre visee pour le maillon de POINTE, en Hz")
    ap.add_argument("--zeta", type=float, default=0.35,
                    help="amortissement reduit vise sur ce meme maillon")
    ap.add_argument("--chains", default=",".join(HAIR),
                    help="chaines a deplacer (defaut: les cinq chaines de cheveux)")
    ap.add_argument("--gravity", type=float, default=None,
                    help="valeur ABSOLUE du gain de gravite, au lieu du s^2 de --keep-sag. "
                         "Le s^2 exact (x19.5 sur les meches fines) tient l'affaissement mais "
                         "fait CEDER la contrainte de longueur : ROOM-STRETCH 0.0190 -> 0.0558, "
                         "soit 5.6 %% d'allongement d'os contre un plafond de 3 %% (course du "
                         "2026-08-12). Le gain physique de ce terme est 1.0 — il multiplie une "
                         "acceleration reelle — et toute valeur au-dessus est une constante "
                         "choisie, qui se declare comme telle avec ses deux marges.")
    ap.add_argument("--no-keep-sag", action="store_true",
                    help="ne PAS tenir le gain statique constant (laisse l'affaissement tomber "
                         "en 1/s^2) — sert a isoler l'effet dans une course de diagnostic")
    ap.add_argument("--file", default=CH)
    ap.add_argument("--room", default=ROOM,
                    help="tableau de salle d'ou les longueurs d'os sont LUES")
    a = ap.parse_args()
    BONES = read_bones(a.room, a.file)
    want = [c for c in a.chains.split(",") if c]

    src = open(a.file, errors="ignore").read().split("\n")
    out, done = [], {}
    for ln in src:
        m = re.match(r"^chain (\S+) ", ln)
        if not m or m.group(1) not in want:
            out.append(ln)
            continue
        name = m.group(1)
        if name not in BONES:
            print("REFUS: %s n'a pas de longueurs d'os mesurees" % name, file=sys.stderr)
            return 1
        bones = BONES[name]
        free = bones[1:]                       # rootlock=1 sur les cinq
        lmean = sum(free) / len(free)
        btip = free[-1]
        stiff0, mass = get(ln, "stiffness"), get(ln, "mass")
        damp0 = get(ln, "damping")
        f0_tip = (stiff0 / math.sqrt(mass)) * (lmean / btip)
        # stiffness telle que f_pointe == ftip
        stiff = a.ftip * math.sqrt(mass) / (lmean / btip)
        # damping telle que zeta_pointe == zeta  (zeta = damping / (2*sqrt(k2a)))
        damp = 2.0 * a.zeta * (2.0 * math.pi * a.ftip / 60.0)
        ln = put(put(ln, "stiffness", stiff), "damping", damp)
        # le gain statique reste constant : sag = gravity*|g|/k et k varie en s^2
        s = a.ftip / f0_tip
        grav0 = get(ln, "gravity")
        grav = grav0
        if a.gravity is not None:
            grav = a.gravity
            ln = put(ln, "gravity", grav)
        elif not a.no_keep_sag and grav0 is not None:
            grav = grav0 * s * s
            ln = put(ln, "gravity", grav)
        out.append(ln)
        done[name] = (f0_tip, a.ftip, stiff0, stiff, damp0, damp, grav0, grav,
                      [(stiff / math.sqrt(mass)) * (lmean / b) for b in free])

    missing = [c for c in want if c not in done]
    if missing:
        print("REFUS: chaine(s) introuvable(s) dans %s: %s" % (a.file, ",".join(missing)),
              file=sys.stderr)
        return 1
    open(a.file, "w").write("\n".join(out))

    print("HAIRFREQ ftip=%.2f Hz zeta=%.2f   (pilotage de la salle : 1.667 Hz)" % (a.ftip, a.zeta))
    for n in want:
        f0, f1, s0, s1, d0, d1, g0, g1, fl = done[n]
        print("  %-9s f_pointe %.3f -> %.3f Hz  stiffness %.2f -> %.4f  damping %.2f -> %.4f"
              "  gravity %.2f -> %.4f   f_maillons %s"
              % (n, f0, f1, s0, s1, d0, d1, g0 or 0.0, g1 or 0.0,
                 " ".join("%.2f" % x for x in fl)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
