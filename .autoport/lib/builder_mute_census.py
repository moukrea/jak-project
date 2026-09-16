#!/usr/bin/env python3
"""lib/builder_mute_census.py — AUCUN `continue` MUET DANS LA BOUCLE DU CONSTRUCTEUR.

(harness-builder-does-not-mistake-an-idle-gradle-daemon-for-a-build, 2026-09-17)

CE QU'IL LIT. Le corps de la boucle `while true; do ... done` de `.autoport/auto_build_apk.sh`,
et CHAQUE `continue` qui s'y trouve. DEUX GRANDEURS, PAS UNE — et les confondre accuserait un innocent. Un `continue` est MUET si,
en remontant au plus trois lignes utiles avant lui, on ne trouve AUCUN appel de journal (`say`
comme `say_cause`) — ou si un mot-cle qui FERME une branche (`fi`, `else`, `elif`, `done`,
`esac`, `;;`) s'intercale entre les deux, auquel cas la parole etait conditionnelle et le
`continue` ne l'est pas. Il est NON ETRANGLE si sa parole est un `say` nu : le 16/09 onze
sorties parlaient a CHAQUE tour de 240 s — « build IGNORE » est ecrit 118 fois dans le
journal, mesure — ce qui noie les rares lignes qui comptent. La consigne demande les deux : aucune
sortie muette, et au plus une ligne par cause et par 20 min.

POURQUOI UN RECENSEMENT DU FICHIER ET PAS UN COMPTEUR A L'EXECUTION. Un compteur ne voit que les
chemins qu'une course emprunte ; les cinq sorties muettes du 16/09 etaient sur des chemins qu'une
course de preuve ne prend jamais. La perte se rend impossible au POINT DE PRODUCTION : la regle
est une propriete du texte, verifiable sur les 100 % des sorties, y compris celles qu'on n'a pas
vues cette nuit-la.

LE TEMOIN « AVANT » NE S'ACCUSE PAS LUI-MEME (regle du 12/09). On ne lit pas `HEAD:` : on remonte
a la derniere revision ou le marqueur `BUILDER-GUARD-BEGIN` est ABSENT, on y rejoue le MEME
recensement, et on PUBLIE le commit retenu. Un chiffre « avant » nul serait un defaut : il
voudrait dire que l'instrument ne sait pas voir le defaut qu'on vient de corriger.

Usage : builder_mute_census.py   -> des lignes cle=valeur sur stdout
"""
import os
import re
import subprocess
import sys

SRC = ".autoport/auto_build_apk.sh"
MARQUEUR = "BUILDER-GUARD-BEGIN"
FERME = re.compile(r"(^|[\s;])(fi|else|elif|done|esac|;;)($|[\s;])")
CONT = re.compile(r"(^|[\s;{])continue($|[\s;}])")
ETRANGLE = re.compile(r"(^|[^A-Za-z0-9_])say_cause[\s\"]")
NUE = re.compile(r"(^|[^A-Za-z0-9_])say[\s\"]")
RECUL = 3


def corps_de_boucle(src):
    """(debut, fin, lignes) du corps de `while true; do ... done`, 1-indexe sur le fichier."""
    lignes = src.split("\n")
    debut = None
    for i, l in enumerate(lignes):
        if re.match(r"^\s*while\s+true\s*;\s*do\s*$", l):
            debut = i
            break
    if debut is None:
        return None
    prof = 1
    for j in range(debut + 1, len(lignes)):
        nu = lignes[j].split("#", 1)[0]
        if re.search(r"(^|[\s;])(do|then)($|[\s;])", nu) and re.search(r"(^|[\s;])(while|for|until|if)($|[\s;])", nu):
            pass  # `if ...; then` sur une ligne : ferme par `fi`, pas par `done`
        if re.search(r"(^|[\s;])do($|[\s;])", nu) and re.search(r"(^|[\s;])(while|for|until)($|[\s;])", nu):
            prof += 1
        if re.search(r"(^|[\s;])done($|[\s;])", nu):
            prof -= 1
            if prof == 0:
                return debut, j, lignes
    return None


def recense(src):
    """(muets, total, boucles_internes, liste des lignes fautives)."""
    bl = corps_de_boucle(src)
    if bl is None:
        return -1, -1, -1, -1, ["corps-de-boucle-introuvable"], ["-"]
    debut, fin, lignes = bl
    internes = 0
    for j in range(debut + 1, fin):
        nu = lignes[j].split("#", 1)[0]
        if re.search(r"(^|[\s;])do($|[\s;])", nu) and re.search(r"(^|[\s;])(while|for|until)($|[\s;])", nu):
            internes += 1
    muets, nus, total, fautifs, bavards = 0, 0, 0, [], []
    for j in range(debut + 1, fin):
        nu = lignes[j].split("#", 1)[0]
        if not CONT.search(nu):
            continue
        total += 1
        # La parole la plus PROCHE, en remontant au plus RECUL lignes utiles ; une fermeture de
        # branche coupe la recherche (la parole etait conditionnelle, le `continue` ne l'est pas).
        forme = None
        for k in range(j, max(debut, j - RECUL) - 1, -1):
            prec = lignes[k].split("#", 1)[0]
            if k != j and not prec.strip():
                continue
            if ETRANGLE.search(prec):
                forme = "etranglee"
                break
            if NUE.search(prec):
                forme = "nue"
                break
            if k != j and FERME.search(prec):
                break
        if forme is None:
            muets += 1
            fautifs.append(str(j + 1))
        elif forme == "nue":
            nus += 1
            bavards.append(str(j + 1))
    return muets, nus, total, internes, fautifs, bavards


def avant():
    """(sha, source) de la derniere revision SANS le marqueur de la garde neuve."""
    try:
        shas = subprocess.run(["git", "log", "--format=%H", "--", SRC],
                              capture_output=True, text=True, timeout=120).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return "-", None
    for sha in shas:
        try:
            s = subprocess.run(["git", "show", "%s:%s" % (sha, SRC)],
                               capture_output=True, text=True, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if s and MARQUEUR not in s:
            return sha, s
    return "-", None


def main():
    if not os.path.exists(SRC):
        print("mute_census_ran=0")
        return 1
    src = open(SRC, encoding="utf-8", errors="replace").read()
    muets, nus, total, internes, fautifs, bavards = recense(src)
    sha, vieux = avant()
    if vieux is None:
        a_muets, a_nus, a_total = -1, -1, -1
        a_fautifs, a_bavards = ["source-avant-introuvable"], ["-"]
    else:
        a_muets, a_nus, a_total, _ai, a_fautifs, a_bavards = recense(vieux)

    out = {
        "builder_mute_continues": muets,
        "builder_unthrottled_continues": nus,
        "builder_continues_total": total,
        "builder_mute_lines": ",".join(fautifs) or "-",
        "builder_unthrottled_lines": ",".join(bavards) or "-",
        "builder_inner_loops": internes,
        "builder_mute_continues_before": a_muets,
        "builder_unthrottled_continues_before": a_nus,
        "builder_continues_total_before": a_total,
        "builder_mute_lines_before": ",".join(a_fautifs) or "-",
        "builder_unthrottled_lines_before": ",".join(a_bavards) or "-",
        "builder_before_commit": sha[:12],
        "mute_census_ran": 1,
    }
    for k, v in out.items():
        print("%s=%s" % (k, v))
    return 0


if __name__ == "__main__":
    sys.exit(main())
