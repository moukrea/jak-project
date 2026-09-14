#!/usr/bin/env python3
"""Chiffre ce que le defaut a coute : les fermetures refusees pour des rouges HERITES.

POURQUOI CE SCRIPT EXISTE. La porte de fermeture refusait un essai des que la suite du
harnais etait rouge, sans regarder si ces rouges existaient DEJA a la base de l'essai.
Reparer cette garde sans chiffrer son cout laisserait la reparation invendable : on dirait
« c'est mieux » sans pouvoir montrer un seul essai perdu. Ce script fournit le nombre.

CE QU'IL MESURE. Il lit les journaux archives `.autoport/logs/*/validator-*.txt`, y trouve
les blocs de refus de la porte de suite, et pour chacun REJOUE les tests incrimines a deux
revisions : la base de l'essai et sa tete. Un refus est `herite` si tous ses rouges etaient
deja rouges A LA BASE — l'essai n'y etait pour rien. Le rejeu est celui de `suite_gate`, la
meme fonction que la porte livree appelle : un second rejeu ecrit ici divergerait en silence.

Il ne repare rien et ne juge rien. Il ecrit des lignes `cle=valeur` sur stdout, sans espace
dans les valeurs, et sort 0 meme sans rien trouver : c'est le recensement qui rougit.

MESURE DE REFERENCE. Essai 2 de `hdr-shadow-range`, refus du 13/09 a 21:57. Tete de l'essai
`897c2a9875`. Base de l'essai `75cd922ae4` : les deux tests y sont ROUGES. Base retenue par
la porte d'alors `80c792057003` : ils y sont VERTS. La porte jugeait donc sur une autre base
que celle que l'essai avait trouvee, et a impute a cet essai deux rouges qu'il heritait.

Usage : python3 .autoport/lib/inherited_red_cost.py [<item-id>]
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import time

# -------------------------------------------------------------------- publication ---
# proof.txt JETTE toute valeur qui porte un espace : une seule porte de sortie, pour que
# rien ne puisse etre publie sans passer par elle.
_BLANCS = re.compile(r"\s+")


def val(x) -> str:
    """Rend une valeur publiable : espaces colles, vide -> `-`."""
    s = _BLANCS.sub("_", str(x).strip())
    return s if s else "-"


_LIGNES: list[str] = []


def pub(cle: str, valeur) -> None:
    _LIGNES.append("%s=%s" % (cle, val(valeur)))


def vider() -> None:
    for ligne in _LIGNES:
        print(ligne)
    sys.stdout.flush()


# ------------------------------------------------------------------------- le depot ---
def git(root: str, *args: str, timeout: int = 120) -> str:
    try:
        r = subprocess.run(["git", "-C", root, *args],
                           capture_output=True, text=True, timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout if r.returncode == 0 else ""


def racine() -> str:
    depart = os.path.dirname(os.path.abspath(__file__))
    try:
        r = subprocess.run(["git", "-C", depart, "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, timeout=60)
        if r.returncode == 0 and r.stdout.strip():
            return r.stdout.strip()
    except (OSError, subprocess.SubprocessError):
        pass
    # repli : deux crans au-dessus de .autoport/lib
    return os.path.dirname(os.path.dirname(depart))


def court(sha: str) -> str:
    sha = (sha or "").strip()
    return sha[:12] if sha else "-"


# ------------------------------------------------------------------- les refus lus ---
MARQUEUR = "CLOSE-GATE/suite: la suite du harnais refuse cette fermeture."
LIGNES_BLOC = 6
RE_ITEM = re.compile(r"--item\s+([A-Za-z0-9_-]+)")
RE_NODE = re.compile(r"[^\s,]+\.py::[A-Za-z0-9_]+")
RE_BASE = re.compile(r"\bbase\s+([0-9a-f]{7,40})\b")


def lire_refus(root: str) -> tuple[list[dict], int]:
    """Rend (refus, nombre de fichiers LUS). Le denominateur n'est jamais sous-entendu."""
    base_logs = os.path.join(root, ".autoport", "logs")
    refus: list[dict] = []
    lus = 0
    fichiers: list[str] = []
    for dossier, _, noms in os.walk(base_logs):
        for nom in noms:
            if nom.startswith("validator-") and nom.endswith(".txt"):
                fichiers.append(os.path.join(dossier, nom))
    for chemin in sorted(fichiers):
        try:
            with open(chemin, encoding="utf-8", errors="replace") as f:
                lignes = f.read().splitlines()
        except OSError:
            continue
        lus += 1
        for i, ligne in enumerate(lignes):
            if MARQUEUR not in ligne:
                continue
            bloc = "\n".join(lignes[i + 1:i + 1 + LIGNES_BLOC])
            m_item = RE_ITEM.search(bloc)
            item = m_item.group(1) if m_item else os.path.basename(os.path.dirname(chemin))
            noeuds = sorted(set(RE_NODE.findall(bloc)))
            m_base = RE_BASE.search(bloc)
            try:
                mtime = os.path.getmtime(chemin)
            except OSError:
                mtime = 0.0
            refus.append({
                "fichier": os.path.relpath(chemin, root),
                "item": item,
                "nodes": noeuds,
                "gate_base": m_base.group(1) if m_base else "",
                "mtime": mtime,
            })
    return refus, lus


# ------------------------------------------------------- la tete et la base de l'essai ---
def journal(root: str) -> list:
    chemin = os.path.join(root, ".autoport", ".last_suite_gate.json")
    try:
        with open(chemin, encoding="utf-8") as f:
            d = json.load(f)
    except Exception:                                                  # noqa: BLE001
        return []
    return (d.get("runs") or []) if isinstance(d, dict) else []


def tete_par_mtime(commits: list[tuple[str, int]], mtime: float) -> str:
    """Le commit le plus RECENT dont la date de commit est <= l'instant du refus."""
    if mtime <= 0:
        return ""
    for sha, ct in commits:
        if ct <= mtime:
            return sha
    return ""


def tete_par_journal(runs: list, item: str, noeuds: list[str]) -> str:
    """Le journal prime : il porte la tete que la porte a REELLEMENT jugee."""
    cible = set(noeuds)
    for entree in runs:
        if not isinstance(entree, dict):
            continue
        if entree.get("verdict") != "refuse":
            continue
        if (entree.get("item") or "") != item:
            continue
        if set(entree.get("unwaived") or []) != cible:
            continue
        tete = (entree.get("head") or "").strip()
        if tete:
            return tete
    return ""


def base_de_l_essai(root: str, item: str, tete: str) -> str:
    """Le dernier etat que l'essai a TROUVE : on remonte tant que les commits sont a lui."""
    if not tete:
        return ""
    marque = "[autoport/%s]" % item
    sortie = git(root, "log", "--format=%H%x09%s", "-n", "80", tete)
    for ligne in sortie.splitlines():
        sha, _, sujet = ligne.partition("\t")
        if item and sujet.startswith(marque):
            continue
        return sha.strip()
    return ""


# ------------------------------------------------------------------------ le verdict ---
def verdict_du_refus(res: dict, base: str, tete: str, noeuds: list[str], ran: int) -> str:
    if not ran or not noeuds:
        return "indecidable"
    a_base = res.get(base) or {}
    a_tete = res.get(tete) or {}
    lus = []
    for n in noeuds:
        vb = a_base.get(n, "unknown")
        vt = a_tete.get(n, "unknown")
        if vb in ("unknown", "absent") or vt in ("unknown", "absent"):
            return "indecidable"
        lus.append(vb == "failed")
    if all(lus):
        return "herite"
    if any(lus):
        return "mixte"
    return "neuf"


def rendu(res: dict, ref: str, noeuds: list[str]) -> str:
    par_ref = res.get(ref) or {}
    if not noeuds:
        return "-"
    return ",".join("%s:%s" % (n, par_ref.get(n, "unknown")) for n in noeuds)


# ---------------------------------------------------------------------------- main ---
def main(argv: list[str]) -> int:
    filtre = argv[1].strip() if len(argv) > 1 and argv[1].strip() else ""
    root = racine()

    pub("cost_ran", 1)

    try:
        sys.path.insert(0, os.path.join(root, ".autoport", "lib"))
        import suite_gate                                              # noqa: PLC0415
    except Exception as exc:                                           # noqa: BLE001
        suite_gate = None
        erreur_import = "import-suite_gate:%s" % exc
    else:
        erreur_import = ""

    refus, lus = lire_refus(root)
    pub("cost_files_scanned", lus)
    pub("cost_refusals", len(refus))

    commits: list[tuple[str, int]] = []
    for ligne in git(root, "log", "--format=%H %ct", "-n", "400").splitlines():
        sha, _, ct = ligne.partition(" ")
        try:
            commits.append((sha.strip(), int(ct.strip())))
        except ValueError:
            continue
    runs = journal(root)

    resolus = 0
    herites = 0
    mixtes = 0
    neufs = 0
    indecidables = 0
    items: set[str] = set()
    noeuds_total = 0
    secondes = 0.0
    erreurs: list[str] = []
    if erreur_import:
        erreurs.append(erreur_import)

    for n, r in enumerate(refus, start=1):
        item = r["item"]
        noeuds = r["nodes"]
        items.add(item)
        noeuds_total += len(noeuds)

        tete = tete_par_journal(runs, item, noeuds)
        source = "journal" if tete else "mtime"
        if not tete:
            tete = tete_par_mtime(commits, r["mtime"])
        tete_pleine = (git(root, "rev-parse", tete).strip() if tete else "")
        if tete_pleine:
            tete = tete_pleine
        base = base_de_l_essai(root, item, tete)

        res: dict = {}
        info = {"ran": 0, "seconds": 0.0, "error": "-"}
        if suite_gate is not None and tete and base and noeuds:
            refs = [base] if base == tete else [base, tete]
            try:
                res, info = suite_gate.replay(root, refs, noeuds)
            except Exception as exc:                                   # noqa: BLE001
                res, info = {}, {"ran": 0, "seconds": 0.0, "error": "replay:%s" % exc}
        elif not erreur_import:
            info["error"] = "tete-ou-base-introuvable"

        ran = int(info.get("ran") or 0)
        secondes += float(info.get("seconds") or 0.0)
        err = str(info.get("error") or "-")
        if err and err != "-":
            erreurs.append("r%d:%s" % (n, err))

        v = verdict_du_refus(res, base, tete, noeuds, ran)
        if ran:
            resolus += 1
        if v == "herite":
            herites += 1
        elif v == "mixte":
            mixtes += 1
        elif v == "neuf":
            neufs += 1
        else:
            indecidables += 1

        quand = "-"
        if r["mtime"] > 0:
            quand = time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(r["mtime"]))
        gate_base = r["gate_base"]
        if base and gate_base:
            meme = 1 if base.startswith(gate_base) or gate_base.startswith(base) else 0
        else:
            meme = -1

        pub("cost_r%d_item" % n, item)
        pub("cost_r%d_file" % n, r["fichier"])
        pub("cost_r%d_at" % n, quand)
        pub("cost_r%d_head" % n, court(tete))
        pub("cost_r%d_head_source" % n, source)
        pub("cost_r%d_base" % n, court(base))
        pub("cost_r%d_gate_base" % n, court(gate_base))
        pub("cost_r%d_base_is_gate_base" % n, meme)
        pub("cost_r%d_nodes" % n, len(noeuds) if noeuds else -1)
        pub("cost_r%d_verdict" % n, v)
        pub("cost_r%d_at_base" % n, rendu(res, base, noeuds) if ran else "-")
        pub("cost_r%d_at_head" % n, rendu(res, tete, noeuds) if ran else "-")

    pub("cost_resolved", resolus)
    pub("cost_all_inherited", herites)
    pub("cost_mixed", mixtes)
    pub("cost_new", neufs)
    pub("cost_undecidable", indecidables)
    pub("cost_items", ",".join(sorted(items)) if items else "-")
    pub("cost_nodes_total", noeuds_total)
    pub("cost_seconds", round(secondes, 1))
    pub("cost_replay_errors", ";".join(erreurs) if erreurs else "-")
    if filtre:
        pub("cost_caller_item", filtre)
    return 0


if __name__ == "__main__":
    code = 0
    try:
        code = main(sys.argv)
    except Exception as exc:                                           # noqa: BLE001
        # INCONNU = DEFAUT : on publie des grandeurs non mesurees, pas des zeros.
        print("cost_ran=0")
        print("cost_files_scanned=-1")
        print("cost_refusals=-1")
        print("cost_resolved=-1")
        print("cost_all_inherited=-1")
        print("cost_mixed=-1")
        print("cost_new=-1")
        print("cost_undecidable=-1")
        print("cost_items=-")
        print("cost_nodes_total=-1")
        print("cost_seconds=-1")
        print("cost_replay_errors=%s" % val("fatal:%s" % exc))
        sys.exit(0)
    vider()
    sys.exit(code)
