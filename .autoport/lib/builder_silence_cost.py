#!/usr/bin/env python3
"""lib/builder_silence_cost.py — CE QUE LE TICK MUET DU CONSTRUCTEUR A COUTE, DANS SON JOURNAL.

(harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build, 2026-09-17)

CE QU'IL COMPTE. `.autoport/logs/auto_build_apk.txt` melange deux choses : la sortie brute des
outils (ninja, gradle, le bake) et les lignes que `say()` ecrit, SEULES a porter un horodatage
`HH:MM:SS ` en tete de ligne. Ces dernieres sont les seules paroles du constructeur ; l'ecart
entre deux d'entre elles est un SILENCE, et un silence qui couvre un commit livrable est
exactement le defaut de cet item.

Un changement d'heure d'ete au milieu du journal
decalerait d'une heure les ticks anterieurs ; le journal courant n'en contient aucun.

POURQUOI LE SILENCE SE LIT A L'ENVERS. Le journal ne porte pas de DATE, seulement une heure.
On ancre donc la DERNIERE ligne sur le mtime du fichier et on remonte : chaque fois que l'heure
AUGMENTE en remontant, on a franchi minuit. Ancrer au debut aurait demande de deviner le jour
du premier tick d'un fichier de 30 Mo qui couvre plusieurs semaines.

POURQUOI « UN COMMIT LIVRABLE NON BATI » SE PROUVE PAR L'INTERIEUR DE LA FENETRE. Un commit
non-WIP cree STRICTEMENT PENDANT le silence ne peut pas avoir ete bati pendant ce silence :
batir ecrit « build declenche » puis « APK + BUILD-INFO prets », deux lignes horodatees, donc
deux paroles — et il n'y en a aucune, c'est la definition du silence. Aucune reconstitution
d'etat n'est necessaire, le fait se lit dans le journal lui-meme.

LES TICKS MUETS SONT UNE BORNE INFERIEURE, PAS UNE ESTIMATION COMPLAISANTE. La cadence n'est pas
supposee (`sleep 240`) : on la MESURE, en prenant le 90e centile des ecarts normaux du journal
(ceux sous 600 s). Diviser le silence par la cadence la plus LONGUE observee donne le plus PETIT
nombre de tours possible. Le vrai chiffre est plus grand.

Usage : builder_silence_cost.py [chemin-du-journal]  -> des lignes cle=valeur sur stdout
"""
import os
import re
import subprocess
import sys
import time

TICK = re.compile(rb"^(\d{2}):(\d{2}):(\d{2}) ")
# Le MEME litteral que `head_is_wip` dans auto_build_apk.sh. Deux copies divergeraient en
# silence ; celle-ci est relue depuis le script et comparee (cf. `cost_wip_motif_identique`).
WIP = re.compile(r"WIP checkpoint|checkpoint automatique|^\[[^]]*\] *WIP |validateur .CHOU|PAS une r.ussite",
                 re.IGNORECASE)
JOUR = 86400


def ticks(chemin):
    """[(epoch, texte)] — les seules lignes que `say()` a ecrites, en temps absolu."""
    try:
        mtime = int(os.stat(chemin).st_mtime)
    except OSError:
        return []
    brut = []
    with open(chemin, "rb") as fh:
        for ligne in fh:
            m = TICK.match(ligne)
            if m:
                sec = int(m.group(1)) * 3600 + int(m.group(2)) * 60 + int(m.group(3))
                brut.append((sec, ligne[9:].decode("utf-8", "replace").rstrip()))
    if not brut:
        return []
    # MINUIT **LOCAL**, PAS MINUIT UTC. `say()` ecrit `date +%H:%M:%S`, donc une heure LOCALE ;
    # ancrer sur `mtime // 86400` (minuit UTC) decale tout de l'offset du fuseau — deux heures en
    # CEST — et fait basculer d'un jour entier tout ce qui tombe pres de minuit. Mesure : le
    # silence du 16/09 17:40 ressortait date du 15/09 19:40.
    lt = time.localtime(mtime)
    jour = mtime - (lt.tm_hour * 3600 + lt.tm_min * 60 + lt.tm_sec)
    if brut[-1][0] > mtime - jour:
        jour -= JOUR
    out = []
    precedent = None
    for sec, txt in reversed(brut):
        if precedent is not None and sec > precedent:
            jour -= JOUR
        precedent = sec
        out.append((jour + sec, txt))
    out.reverse()
    return out


def commits_livrables():
    """[(epoch, sha, sujet)] des commits NON-WIP, tous ceux que git connait sur cette branche."""
    try:
        brut = subprocess.run(["git", "log", "--format=%ct%x09%h%x09%s"],
                              capture_output=True, text=True, timeout=120).stdout
    except (OSError, subprocess.SubprocessError):
        return []
    out = []
    for l in brut.splitlines():
        p = l.split("\t", 2)
        if len(p) != 3:
            continue
        if WIP.search(p[2]):
            continue
        try:
            out.append((int(p[0]), p[1], p[2]))
        except ValueError:
            pass
    out.sort()
    return out


def centile(vals, q):
    if not vals:
        return -1
    v = sorted(vals)
    return v[min(len(v) - 1, int(q * (len(v) - 1)))]


def main():
    ap = os.path.join(os.getcwd(), ".autoport")
    journal = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ap, "logs", "auto_build_apk.txt")
    T = ticks(journal)
    C = commits_livrables()

    # La cadence, MESUREE : 90e centile des ecarts normaux (< 600 s). Le plus long tour normal.
    ecarts = [T[i + 1][0] - T[i][0] for i in range(len(T) - 1)]
    normaux = [e for e in ecarts if 0 < e < 600]
    periode = centile(normaux, 0.90)

    pire = {"s": 0, "t0": 0, "t1": 0, "commits": [], "avant": "-", "apres": "-"}
    dernier = dict(pire)
    silences = 0
    muets = 0
    redemarrages = 0
    for i in range(len(T) - 1):
        t0, t1 = T[i][0], T[i + 1][0]
        d = t1 - t0
        if d < 600:                       # un tour normal n'est pas un silence
            continue
        # UN DEMON MORT N'EST PAS UN TICK MUET. Si la parole qui rouvre le silence est
        # « auto-builder demarré », le constructeur ne TOURNAIT pas : c'est une panne de
        # supervision, un autre defaut. On ne l'impute pas a cet item (feedback : une porte qui
        # IMPUTE doit ancrer sur l'essai et NOMMER sa cause). Le compte des exclus est publie.
        if T[i + 1][1].startswith("auto-builder"):
            redemarrages += 1
            continue
        dedans = [c for c in C if t0 < c[0] < t1]
        if not dedans:
            continue                      # rien de livrable n'attendait : pas le defaut de cet item
        silences += 1
        if periode > 0:
            muets += max(0, d // periode - 1)
        courant = {"s": d, "t0": t0, "t1": t1, "commits": dedans,
                   "avant": T[i][1][:70], "apres": T[i + 1][1][:70]}
        dernier = courant                 # le journal est chronologique : le dernier gagne
        if d > pire["s"]:
            pire = courant

    p_muets = (pire["s"] // periode - 1) if periode > 0 and pire["s"] else 0
    # Le litteral WIP est-il TOUJOURS celui du script juge ? Une divergence rendrait « livrable »
    # des checkpoints, donc gonflerait le cout. On le verifie au lieu de l'esperer.
    try:
        src = open(os.path.join(ap, "auto_build_apk.sh"), encoding="utf-8", errors="replace").read()
        meme = 1 if WIP.pattern in src else 0
    except OSError:
        meme = -1

    out = {
        "cost_log": journal,
        "cost_log_bytes": os.path.getsize(journal) if os.path.exists(journal) else -1,
        "cost_ticks_total": len(T),
        "cost_tick_period_s": periode,
        "cost_silences_with_pending_commit": silences,
        "cost_silences_excluded_daemon_restart": redemarrages,
        "cost_max_silence_s": pire["s"],
        "cost_max_silence_from": pire["t0"],
        "cost_max_silence_to": pire["t1"],
        "cost_max_silence_last_word": pire["avant"].replace(" ", "_") or "-",
        "cost_max_silence_next_word": pire["apres"].replace(" ", "_") or "-",
        "cost_max_silence_pending_commits": len(pire["commits"]),
        "cost_max_silence_commit_list": ",".join(c[1] for c in pire["commits"][:12]) or "-",
        "cost_max_silence_mute_ticks": max(0, p_muets),
        "cost_mute_ticks_lower_bound": muets,
        # LE PLUS RECENT, celui que la cause connue de l'item nomme (16/09 17:41 -> 17/09 00:40).
        "cost_last_silence_s": dernier["s"],
        "cost_last_silence_from": dernier["t0"],
        "cost_last_silence_to": dernier["t1"],
        "cost_last_silence_pending_commits": len(dernier["commits"]),
        "cost_last_silence_commit_list": ",".join(c[1] for c in dernier["commits"][:12]) or "-",
        "cost_last_silence_mute_ticks": (dernier["s"] // periode - 1) if periode > 0 and dernier["s"] else 0,
        "cost_deliverable_commits_seen": len(C),
        "cost_wip_motif_identique": meme,
    }
    for k, v in out.items():
        print("%s=%s" % (k, v))


if __name__ == "__main__":
    main()
