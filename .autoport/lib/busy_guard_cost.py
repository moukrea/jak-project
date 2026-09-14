#!/usr/bin/env python3
"""lib/busy_guard_cost.py — CE QUE L'ANCIENNE GARDE A COUTE, COMPTE DANS LES JOURNAUX ARCHIVES.

(harness-busy-guard-matches-gradle-daemon, 2026-09-14)

CE QU'IL COMPTE. Les sorties rc=3 de `lib/proof_run.sh` dont la cause NOMMEE etait Gradle :

    [proof_run <item>] PREUVE IMPOSSIBLE (build-en-cours) : un build ecrit encore apres
    <N>s (borne <M>s) : processus [g]radle en cours

POURQUOI CETTE LIGNE SUFFIT A DIRE « LA SEULE CAUSE ETAIT LE DEMON ». `busy_reason` rend la
PREMIERE cause trouvee, dans cet ordre : verrou de deploiement vivant, puis ninja/goalc/cc1plus
par leur NOM de processus, puis Gradle. Une ligne qui nomme Gradle dit donc, par construction,
qu'aucun compilateur ne tournait et qu'aucun verrou ne repondait. Reste l'APK : `waited == borne`
dit que la condition a tenu SANS INTERRUPTION pendant toute la borne (1800 s par defaut) — aucun
build d'APK de ce depot ne dure trente minutes, et l'`idleTimeout=10800000` du demon (trois
heures, ecrit dans son propre journal) explique exactement cette duree. Les deux termes sont
publies SEPAREMENT (`cost_at_cap` / `cost_below_cap`) : qui veut contester n'a pas a me croire.

L'UNITE EST L'ESSAI BRULE, pas l'occurrence. Un meme refus est recopie plusieurs fois dans un
transcript (le worker relit son journal) : compter les occurrences compterait les relectures.
On compte donc les couples (item, essai) DISTINCTS qui portent au moins un de ces refus, et on
publie aussi le brut.

LE SCANNER S'EXCLUT LUI-MEME. Le transcript de CET item contient forcement ces chaines — je
suis en train de les ecrire. Les chemins qui portent l'identifiant de l'item sont ecartes, et
leur nombre est PUBLIE : un exclu muet serait un chiffre choisi.

Usage : busy_guard_cost.py <item-id-a-exclure>   -> des lignes cle=valeur sur stdout
"""
import os
import re
import sys

ANCRE = b"PREUVE IMPOSSIBLE (build-en-cours)"
MOTIF = re.compile(
    r"\[proof_run ([A-Za-z0-9._-]+)\] PREUVE IMPOSSIBLE \(build-en-cours\) : "
    r"un build ecrit encore apres (\d+)s \(borne (\d+)s\) : processus \[g\]radle en cours")
ANCRE_ATT = b"attente : processus [g]radle en cours"
MOTIF_ATT = re.compile(r"\[proof_run ([A-Za-z0-9._-]+)\] attente : processus \[g\]radle en cours")


def essai(chemin, racine):
    """(item, essai) deduits du CHEMIN. `logs/<item>/attempt-NNN.jsonl` -> (item, NNN)."""
    rel = os.path.relpath(chemin, racine)
    parts = rel.split(os.sep)
    if len(parts) >= 3 and parts[0] == "logs" and parts[2].startswith("attempt-"):
        return parts[1], parts[2].split(".", 1)[0]
    if len(parts) >= 2 and parts[0] == "reports":
        return parts[1], "journal:" + parts[-1]
    return rel, "-"


def fichiers(ap):
    for d in sorted(os.listdir(os.path.join(ap, "logs"))):
        sd = os.path.join(ap, "logs", d)
        if not os.path.isdir(sd):
            continue
        for f in sorted(os.listdir(sd)):
            if f.startswith("attempt-") and f.endswith(".jsonl"):
                yield os.path.join(sd, f)
    for dirpath, _dirnames, filenames in os.walk(os.path.join(ap, "reports")):
        for f in filenames:
            if f.startswith("proof-run") and f.endswith(".log"):
                yield os.path.join(dirpath, f)


def main():
    exclu = sys.argv[1] if len(sys.argv) > 1 else ""
    ap = os.path.join(os.getcwd(), ".autoport")
    lus = ecartes = octets = 0
    occ = occ_att = 0
    brules, items, attentes = set(), set(), set()
    au_plafond = sous_plafond = 0
    for chemin in fichiers(ap):
        if exclu and exclu in chemin:
            ecartes += 1
            continue
        try:
            brut = open(chemin, "rb").read()
        except OSError:
            continue
        lus += 1
        octets += len(brut)
        if ANCRE not in brut and ANCRE_ATT not in brut:
            continue
        # Le JSONL echappe les sauts de ligne : on les rend pour retrouver les lignes du log.
        texte = brut.decode("utf-8", "replace").replace("\\n", "\n")
        for m in MOTIF.finditer(texte):
            item, attendu, borne = m.group(1), int(m.group(2)), int(m.group(3))
            occ += 1
            if attendu >= borne:
                au_plafond += 1
            else:
                sous_plafond += 1
            it, es = essai(chemin, ap)
            brules.add((item, it, es))
            items.add(item)
        for m in MOTIF_ATT.finditer(texte):
            occ_att += 1
            it, es = essai(chemin, ap)
            attentes.add((m.group(1), it, es))

    out = {
        "cost_files_scanned": lus,
        "cost_files_self_excluded": ecartes,
        "cost_mbytes_scanned": octets // (1024 * 1024),
        "cost_occurrences": occ,
        "cost_attempts_burned": len(brules),
        "cost_items": len(items),
        "cost_at_cap": au_plafond,
        "cost_below_cap": sous_plafond,
        "cost_wait_occurrences": occ_att,
        "cost_wait_attempts": len(attentes),
        "cost_items_list": ",".join(sorted(items)) or "-",
        "cost_attempts_list": ",".join(sorted("%s/%s" % (a, b) for _i, a, b in brules)) or "-",
        "cost_wait_items_list": ",".join(sorted({i for i, _a, _b in attentes})) or "-",
    }
    for k, v in out.items():
        print("%s=%s" % (k, v))


if __name__ == "__main__":
    main()
