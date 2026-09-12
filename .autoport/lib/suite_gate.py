#!/usr/bin/env python3
"""lib/suite_gate.py — LA SUITE DU HARNAIS, LUE PAR LA PORTE DE FERMETURE.

MARQUEUR : CLOSE-GATE/suite

POURQUOI CE FICHIER EXISTE. Mesure du 2026-09-12 : a 06:16 la suite du harnais etait a 556
verts, pour la premiere fois depuis le 6 septembre. A 15:45, QUARANTE-QUATRE tests de
`tests/harness/test_hdr_batches.py` etaient rouges. `dead-published-keys-round-2` avait renomme
trois cles en `_const` et mis a jour le LECTEUR sans les tests qui les citent ; son essai a ete
accepte, sa porte etait verte, et personne n'a rien vu — parce que `grep -n pytest
orchestrator.py validators/` ne rendait RIEN. Aucune porte ne lancait la suite. Le vert obtenu
le matin ne protegeait donc de rien des l'apres-midi.

CE FICHIER EST LE SEUL PRODUCTEUR DU VERDICT DE LA SUITE. La porte de fermeture
(`orchestrator.close_gate`) l'appelle, le recensement de l'item l'appelle, le banc l'appelle.
Trois lecteurs, UN calcul : deux regles ecrites a deux endroits divergent en silence.

CE QU'IL JUGE, ET AVEC QUELLE POLARITE :

  1. LA SUITE TOURNE ET SON RESULTAT EST LU. Le code de retour de pytest ne suffit pas — 2, 3,
     4 et 5 veulent dire « usage / collecte impossible / rien collecte », et se liraient comme
     « aucun test n'a rate ». On lit le junit : le verdict PAR TEST, jamais un compte.
  2. UN ROUGE QU'AUCUNE DISPENSE ECRITE NE COUVRE REFUSE LA FERMETURE, et il est NOMME. C'est
     la seule chose qui empeche le vert du matin de se perimer l'apres-midi.
  3. UN ITEM NE PEUT PAS SE DONNER DU VERT EN INSCRIVANT SON PROPRE ECHEC AU REGISTRE. Les
     entrees que l'item COURANT a ajoutees a `ECHECS-ATTENDUS.yaml` — mesurees contre le
     registre tel qu'il etait AVANT son premier commit — sont retirees du jeu des dispenses
     pour SA fermeture, comptees, et doivent etre NOMMEES dans son rapport.
  4. LE COUT EST BORNE ET DIT. La suite prend 90 a 190 s ; le budget retenu et la duree
     MESUREE sont publies a chaque fermeture. Un depassement est DIT, jamais avale. Au-dela du
     plafond dur la course est tuee et la fermeture refusee : une suite qui pend n'est pas une
     suite qui passe.

CE QU'IL NE FAIT PAS. Il ne desactive aucun test, il n'ecrit jamais dans le registre, et il
n'ecrit aucun champ de `proof.txt`. Son journal (`.autoport/.last_suite_gate.json`, deja
gitignore par `.autoport/.last_*`) ne sert QU'A publier « ce rouge est-il neuf » : il n'accorde
aucune dispense, sinon un item refuse fermerait a son deuxieme essai en s'appuyant sur la trace
du premier.
"""
from __future__ import annotations

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET

SUITE_REL = "tests/harness"
REGISTRY_REL = "tests/harness/ECHECS-ATTENDUS.yaml"
JOURNAL_NAME = ".last_suite_gate.json"
JOURNAL_KEEP = 24

# Le budget retenu : la suite prend 90 a 190 s (mesure du 12/09). Le depassement est DIT, il ne
# refuse rien — ce n'est pas la faute de l'item qui ferme. Le PLAFOND DUR, lui, refuse : une
# suite qui ne rend pas la main n'a rien prouve.
BUDGET_S = int(os.environ.get("AUTOPORT_SUITE_BUDGET_S") or 240)
TIMEOUT_S = int(os.environ.get("AUTOPORT_SUITE_TIMEOUT_S") or 900)


# ============================================================ la course, et ce qu'elle rend ==
def _run_pytest(root: str, suite_rel: str, xml: str, timeout_s: int) -> tuple[int, float, int]:
    """Rend (code de retour, duree en secondes, tue-par-le-plafond)."""
    t0 = time.time()
    try:
        r = subprocess.run(
            [sys.executable, "-m", "pytest", suite_rel, "-q", "-p", "no:cacheprovider",
             "--junitxml=" + xml],
            cwd=root, capture_output=True, text=True, timeout=timeout_s)
        return r.returncode, time.time() - t0, 0
    except subprocess.TimeoutExpired:
        return -1, time.time() - t0, 1
    except (OSError, ValueError):
        return -2, time.time() - t0, 0


def read_junit(chemin: str) -> dict | None:
    """nodeid -> (verdict, message). Un fichier absent ou tronque rend None : INCONNU.

    La derivation du nodeid est celle de `lib/census/harness-test-suite-is-not-a-signal.sh`,
    au caractere pres : le registre est lu par les deux, et deux orthographes du meme test
    feraient passer une dispense pour perimee d'un cote et absente de l'autre.
    """
    try:
        racine = ET.parse(chemin).getroot()
    except Exception:                                                  # noqa: BLE001
        return None
    suite = racine if racine.tag == "testsuite" else racine.find("testsuite")
    if suite is None:
        return None
    res = {}
    for tc in suite.iter("testcase"):
        parts = (tc.get("classname") or "").split(".")
        fichier = ("." + "/".join(parts[1:]) + ".py") if parts and parts[0] == "" \
                  else "/".join(parts) + ".py"
        nodeid = "%s::%s" % (fichier, tc.get("name"))
        verdict, message = "passed", ""
        for enfant in tc:
            if enfant.tag in ("failure", "error"):
                verdict = enfant.tag
                message = (enfant.get("message") or "") + "\n" + (enfant.text or "")
            elif enfant.tag == "skipped":
                verdict = "skipped"
        res[nodeid] = (verdict, message)
    return res


# ==================================================================== le registre, et sa base =
def parse_registry(texte: str | None) -> dict | None:
    """`nodeid -> entree`. None = illisible, et l'illisible est un DEFAUT, jamais un vide."""
    if texte is None:
        return None
    try:
        import yaml
        doc = yaml.safe_load(texte) or {}
    except Exception:                                                  # noqa: BLE001
        return None
    if not isinstance(doc, dict):
        return None
    out = {}
    for e in (doc.get("attendus") or []):
        if isinstance(e, dict) and e.get("nodeid"):
            out[str(e["nodeid"])] = e
    return out


def _git(root: str, *args: str, timeout: int = 60) -> str:
    try:
        r = subprocess.run(["git", "-C", root, *args], capture_output=True, text=True,
                           timeout=timeout)
    except (OSError, subprocess.SubprocessError):
        return ""
    return r.stdout if r.returncode == 0 else ""


def base_ref(root: str, item_id: str) -> str:
    """La revision d'AVANT l'item courant.

    Le PARENT de son PREMIER commit s'il en a — c'est l'etat du registre qu'il a TROUVE — et
    `HEAD` sinon, pour qu'une entree posee dans l'arbre de travail et pas encore commitee
    compte quand meme comme la sienne. Jamais `HEAD` quand l'item a deja commite : lu la, le
    temoin d'avant porterait deja l'ajout et s'innocenterait lui-meme.
    """
    if not item_id:
        return "HEAD"
    motif = r"\[autoport/%s\]" % re.escape(item_id)
    commits = [x for x in _git(root, "log", "--format=%H", "--grep", motif).split() if x]
    if commits:
        parents = _git(root, "rev-parse", "%s^" % commits[-1]).split()
        if parents:
            return parents[0]
        return commits[-1]          # commit racine : son propre etat est la base
    return "HEAD"


def registry_at(root: str, ref: str, rel: str) -> str | None:
    try:
        r = subprocess.run(["git", "-C", root, "show", "%s:%s" % (ref, rel)],
                           capture_output=True, text=True, timeout=60)
    except (OSError, subprocess.SubprocessError):
        return None
    return r.stdout if r.returncode == 0 else None


# ============================================================================== le journal ===
def _journal_path(autoport: str) -> str:
    return os.path.join(autoport, JOURNAL_NAME)


def read_journal(autoport: str) -> list:
    try:
        with open(_journal_path(autoport), encoding="utf-8") as f:
            d = json.load(f)
    except Exception:                                                  # noqa: BLE001
        return []
    return d.get("runs") or [] if isinstance(d, dict) else []


def _append_journal(autoport: str, entree: dict) -> None:
    """UN SEUL ECRIVAIN : ce module. Ecriture atomique — un journal a moitie ecrit se relit
    `[]`, et un item lirait alors « aucun rouge connu » sur une machine qui en a."""
    runs = read_journal(autoport)
    runs.append(entree)
    runs = runs[-JOURNAL_KEEP:]
    chemin = _journal_path(autoport)
    try:
        os.makedirs(autoport, exist_ok=True)
        fd, tmp = tempfile.mkstemp(dir=autoport, prefix=".suite-gate-", suffix=".tmp")
        with os.fdopen(fd, "w", encoding="utf-8") as f:
            json.dump({"runs": runs}, f, ensure_ascii=False)
        os.replace(tmp, chemin)
    except OSError:
        pass


# ================================================================================ le verdict =
def judge(repo_root, autoport_dir, item_id: str = "", *, budget_s: int | None = None,
          timeout_s: int | None = None, record: bool = True) -> dict:
    """Lance la suite, la juge, et rend un dictionnaire de grandeurs PUBLIABLES.

    `verdict` vaut `pass` ou `refuse` ; `reason` porte, en francais, ce que la porte dira.
    """
    root = str(repo_root)
    autoport = str(autoport_dir)
    budget = BUDGET_S if budget_s is None else int(budget_s)
    plafond = TIMEOUT_S if timeout_s is None else int(timeout_s)

    suite_abs = os.path.join(autoport, SUITE_REL)
    suite_rel = os.path.relpath(suite_abs, root)
    registre_rel = os.path.relpath(os.path.join(autoport, REGISTRY_REL), root)

    d = {
        "suite_dir": suite_rel, "budget_s": budget, "timeout_s": plafond,
        "ran": 0, "rc": -9, "duration_s": 0.0, "timed_out": 0, "over_budget": 0,
        "collected": -1, "failed": -1, "failed_list": [],
        "registry_read": 0, "registry_sha": "-", "registry_entries": -1,
        "base_ref": "-", "self_added": -1, "self_added_list": [],
        "self_added_named": -1, "self_added_unnamed": [], "report_read": 0,
        "waived_effective": -1, "stale_waivers": -1,
        "unwaived": -1, "unwaived_list": [],
        "unwaived_new": -1, "unwaived_new_list": [], "unwaived_known": -1,
        "previous_at": "-", "previous_runs": len(read_journal(autoport)),
        "verdict": "refuse", "reason": "",
    }
    if not os.path.isdir(suite_abs):
        d["reason"] = ("la suite du harnais est INTROUVABLE (%s) : rien n'a ete mesure, et "
                       "une porte qui ne trouve pas son filet ne le remplace pas par un vert."
                       % suite_rel)
        return d

    # ------------------------------------------------------------------ 1. LA COURSE --------
    tmpd = tempfile.mkdtemp(prefix="suite-gate-")
    xml = os.path.join(tmpd, "junit.xml")
    rc, duree, tue = _run_pytest(root, suite_rel, xml, plafond)
    resultats = read_junit(xml)
    try:
        os.remove(xml)
        os.rmdir(tmpd)
    except OSError:
        pass
    d["ran"] = 1
    d["rc"] = rc
    d["duration_s"] = round(duree, 1)
    d["timed_out"] = tue
    d["over_budget"] = 1 if duree > budget else 0

    # ------------------------------------------------------------------ 2. LE REGISTRE ------
    reg_txt = None
    reg_abs = os.path.join(autoport, REGISTRY_REL)
    try:
        with open(reg_abs, "rb") as f:
            brut = f.read()
        reg_txt = brut.decode("utf-8", "replace")
        import hashlib
        d["registry_sha"] = hashlib.sha256(brut).hexdigest()[:16]
    except OSError:
        brut = b""
    registre = parse_registry(reg_txt)
    d["registry_read"] = 1 if registre is not None else 0
    d["registry_entries"] = len(registre) if registre is not None else -1

    # LES DISPENSES QUE L'ITEM COURANT S'EST ECRITES. Elles sont comptees, nommees, et RETIREES
    # du jeu : c'est le seul geste par lequel un item pourrait se donner du vert tout seul.
    ref = base_ref(root, item_id)
    d["base_ref"] = (ref[:12] if re.fullmatch(r"[0-9a-f]{40}", ref) else ref)
    base_reg = parse_registry(registry_at(root, ref, registre_rel))
    if registre is None:
        propres = []
    elif base_reg is None:
        # Pas de base lisible : TOUT est impute a l'item courant. Le sens de l'erreur est
        # choisi — une base inconnue ne doit pas offrir une dispense gratuite.
        propres = sorted(registre)
    else:
        propres = sorted(set(registre) - set(base_reg))
    d["self_added"] = len(propres)
    d["self_added_list"] = propres

    rapport = ""
    chemin_rapport = os.path.join(autoport, "reports", item_id, "report.txt") if item_id else ""
    if chemin_rapport and os.path.exists(chemin_rapport):
        try:
            with open(chemin_rapport, encoding="utf-8", errors="replace") as f:
                rapport = f.read()
            d["report_read"] = 1
        except OSError:
            rapport = ""
    d["self_added_unnamed"] = [n for n in propres if n not in rapport]
    d["self_added_named"] = len(propres) - len(d["self_added_unnamed"])

    # ------------------------------------------------------------------ 3. LE JUGEMENT ------
    defauts = []
    if tue:
        defauts.append("la suite n'a pas rendu la main en %d s (plafond dur) : elle a ete tuee, "
                       "et une suite tuee n'a rien prouve" % plafond)
    if resultats is None:
        defauts.append("le junit de la suite est illisible ou absent (pytest rc=%d) : le code "
                       "de retour seul ne distingue pas « un test a rate » de « la collecte a "
                       "echoue »" % rc)
    if rc not in (0, 1) and not tue:
        defauts.append("pytest est sorti en %d — usage, collecte impossible ou aucun test "
                       "collecte ; ce n'est pas « aucun test n'a rate »" % rc)
    if registre is None:
        defauts.append("le registre des echecs assumes (%s) est illisible : sans lui aucun "
                       "rouge ne peut etre dispense, et un registre casse ne dispense pas tout"
                       % registre_rel)

    if resultats is not None:
        rouges = sorted(k for k, (v, _m) in resultats.items() if v in ("failure", "error"))
        d["collected"] = len(resultats)
        d["failed"] = len(rouges)
        d["failed_list"] = rouges
        if not resultats:
            defauts.append("la suite n'a COLLECTE aucun test : une suite qui ne collecte rien "
                           "ne rate rien, et son vert ne protege personne")
        if registre is not None:
            # UNE DISPENSE NE COUVRE QUE SA PROPRE SIGNATURE : un autre defaut ne passe pas
            # dessous. Et jamais une dispense que l'item courant vient d'ecrire.
            couvre = set()
            for n in rouges:
                e = registre.get(n)
                if e is None or n in propres:
                    continue
                sig = e.get("signature") or "(?!)"
                msg = (resultats.get(n) or ("", ""))[1] or ""
                try:
                    if re.search(sig, msg):
                        couvre.add(n)
                except re.error:
                    pass
            d["waived_effective"] = len(couvre)
            d["stale_waivers"] = len([n for n in registre
                                      if n not in propres and n not in rouges])
            non_couverts = [n for n in rouges if n not in couvre]
            d["unwaived"] = len(non_couverts)
            d["unwaived_list"] = non_couverts
            # NEUF OU DEJA LA : publie, jamais dispensateur. Le journal dit qui a casse quoi ;
            # il ne ferme aucune porte, sinon un item refuse fermerait au deuxieme essai en
            # s'appuyant sur la trace que son premier essai vient d'ecrire.
            precedent = read_journal(autoport)
            connus, quand = set(), "-"
            for r in reversed(precedent):
                if r.get("unwaived") is not None:
                    connus = set(r.get("unwaived") or [])
                    quand = str(r.get("at") or "-")
                    break
            d["previous_at"] = quand
            d["unwaived_new_list"] = [n for n in non_couverts if n not in connus]
            d["unwaived_new"] = len(d["unwaived_new_list"])
            d["unwaived_known"] = len(non_couverts) - d["unwaived_new"]
            if non_couverts:
                defauts.append(
                    "%d test(s) de la suite du harnais sont ROUGES et aucune dispense ecrite "
                    "ne les couvre : %s. La suite etait VERTE et ce build la rend rouge — "
                    "repare le test ou inscris-le dans %s avec sa raison, sa signature et le "
                    "nom de qui doit trancher."
                    % (len(non_couverts), ",".join(non_couverts[:8]), registre_rel))
    if d["self_added"] > 0 and d["unwaived"] and d["unwaived"] > 0:
        defauts.append(
            "%d entree(s) du registre ont ete ajoutees par CET item (%s, base %s) : elles ne "
            "dispensent pas SES propres rouges. Un item ne se donne pas du vert en inscrivant "
            "son echec au registre." % (d["self_added"], ",".join(propres[:6]), d["base_ref"]))
    if d["self_added"] > 0 and d["self_added_unnamed"]:
        defauts.append(
            "%d entree(s) ajoutees au registre ne sont NOMMEES nulle part dans le rapport de "
            "l'item (%s) : une dispense que personne ne lit est une regression silencieuse."
            % (len(d["self_added_unnamed"]), ",".join(d["self_added_unnamed"][:6])))

    d["verdict"] = "pass" if not defauts else "refuse"
    d["reason"] = " | ".join(defauts)

    if record:
        _append_journal(autoport, {
            "at": time.strftime("%Y-%m-%dT%H:%M:%S"), "item": item_id,
            "head": (_git(root, "rev-parse", "--short", "HEAD").strip() or "-"),
            "collected": d["collected"], "failed": d["failed"],
            "unwaived": d["unwaived_list"], "duration_s": d["duration_s"],
            "verdict": d["verdict"],
        })
    return d


# ================================================================================ publication =
def _plat(v) -> str:
    """AUCUN ESPACE : `proof.txt` jette toute valeur qui en porte un — publie pour personne."""
    if isinstance(v, (list, tuple)):
        v = ",".join(str(x) for x in v) or "-"
    s = str(v)
    s = re.sub(r"\s+", "_", s.strip())
    return s or "-"


def publish(d: dict, prefix: str = "suite_") -> list[str]:
    ordre = ("ran", "rc", "collected", "failed", "failed_list", "duration_s", "budget_s",
             "timeout_s", "over_budget", "timed_out", "registry_read", "registry_sha",
             "registry_entries", "base_ref", "self_added", "self_added_list",
             "self_added_named", "self_added_unnamed", "report_read", "waived_effective",
             "stale_waivers", "unwaived", "unwaived_list", "unwaived_new",
             "unwaived_new_list", "unwaived_known", "previous_at", "previous_runs",
             "verdict", "suite_dir")
    out = ["%s%s=%s" % (prefix, k, _plat(d.get(k, "-"))) for k in ordre]
    out.append("%sreason=%s" % (prefix, _plat(d.get("reason") or "-")[:400]))
    return out


def main(argv: list[str]) -> int:
    import argparse
    ap = argparse.ArgumentParser(description="juge la suite du harnais")
    ap.add_argument("action", nargs="?", default="judge", choices=["judge"])
    ap.add_argument("--root", default=None)
    ap.add_argument("--autoport", default=None)
    ap.add_argument("--item", default="")
    ap.add_argument("--prefix", default="suite_")
    ap.add_argument("--budget", type=int, default=None)
    ap.add_argument("--timeout", type=int, default=None)
    ap.add_argument("--no-record", action="store_true")
    a = ap.parse_args(argv)
    ici = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    autoport = a.autoport or ici
    root = a.root or os.path.dirname(autoport)
    d = judge(root, autoport, a.item, budget_s=a.budget, timeout_s=a.timeout,
              record=not a.no_record)
    for ligne in publish(d, a.prefix):
        print(ligne)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
