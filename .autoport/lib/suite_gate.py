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
  5. UN ROUGE NE DE L'ESSAI REFUSE ; UN ROUGE HERITE EST SIGNALE, PAS IMPUTE
     (harness-close-gate-separates-inherited-reds, 2026-09-14). Mesure : l'essai 2 de
     `hdr-shadow-range` est mort le 13/09 a 21:57 sur deux rouges de `test_backlog.py` nes de
     `1c197e3620` ([autoport/supervisor], 20:51), UNE HEURE avant son premier commit. Deux
     fautes cumulees, toutes deux corrigees ici :
       - LA BASE ETAIT CELLE DE L'ITEM, PAS CELLE DE L'ESSAI. `base_ref()` remonte au parent du
         PREMIER commit de l'item, tous essais confondus : pour hdr-shadow-range c'etait
         `80c792057003` du 12/09 a 20:34, VINGT-QUATRE HEURES avant. Tout ce que le monde avait
         commite entre-temps etait impute a l'item. La base des ROUGES est desormais celle de
         L'ESSAI (`red_base_ref`), derivee de l'instant de depart que porte deja
         `AUTOPORT_ATTEMPT_ID`. Celle du REGISTRE reste celle de l'item : une dispense qu'un
         item s'est ecrite au premier essai ne doit pas le couvrir au troisieme.
       - RIEN N'ETAIT MESURE. `unwaived_new` se lisait dans le journal des courses
         precedentes — la trace de l'item lui-meme. On MESURE : un arbre de travail jetable a
         la base, un a `HEAD`, et le meme nodeid rejoue dans les deux. ROUGE A LA BASE ET A
         `HEAD` = HERITE, et l'herite ne refuse pas. Tout le reste — vert a la base, absent,
         indecidable, arbre jetable impossible — est NEUF et refuse : le sens de l'erreur est
         choisi, un doute ne relache jamais la porte.
     Verifie sur l'archive : rejoues a la base de l'ESSAI, les deux rouges du 13/09 sont ROUGES
     (donc herites) ; a la base de l'ITEM ils sont VERTS. C'est tout l'ecart.

CE QU'IL NE FAIT PAS. Il ne desactive aucun test, il n'ecrit jamais dans le registre, et il
n'ecrit aucun champ de `proof.txt`. Son journal (`.autoport/.last_suite_gate.json`, deja
gitignore par `.autoport/.last_*`) ne dispense RIEN et ne classe plus rien : depuis le 14/09
il ne sert qu'a dire ce que la course precedente avait vu (`journal_*`). Un item refuse ne
ferme pas a son deuxieme essai en s'appuyant sur la trace du premier — c'est une mesure a la
base de l'essai qui le decide, et son propre premier essai n'est pas dans cette base.
"""
from __future__ import annotations

import json
import os
import re
import shutil
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


_TRIE = re.compile(r"->\s*(item:[A-Za-z0-9_-]+|ecarte:\S)")


def _trie(findings: str, nodeid: str) -> bool:
    """Ce nodeid est-il SIGNALE — cite sur une ligne de FINDINGS.txt qui porte son tri ?

    La ligne doit citer le nodeid ENTIER. Un nom de test seul se retrouve dans dix fichiers ;
    `lib/findings_gate.sh` lit la meme convention de tri, et il n'y en a qu'une.
    """
    if not findings or not nodeid:
        return False
    return any(nodeid in ligne and _TRIE.search(ligne)
               for ligne in findings.splitlines())


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


def _own_commits(root: str, item_id: str) -> list[tuple[str, int]]:
    """Les commits de l'item, du plus RECENT au plus ancien, avec leur date de commit."""
    if not item_id:
        return []
    motif = r"\[autoport/%s\]" % re.escape(item_id)
    out = []
    for ligne in _git(root, "log", "--format=%H %ct", "--grep", motif).splitlines():
        p = ligne.split()
        if len(p) == 2 and p[1].isdigit():
            out.append((p[0], int(p[1])))
    return out


def attempt_start(since: float = 0.0) -> tuple[float, str]:
    """L'instant ou CET essai a commence, et d'ou on le tient.

    L'orchestrateur le passe (`close_gate(..., since=started_at)`) ; hors de lui il est dans
    `AUTOPORT_ATTEMPT_ID`, que l'orchestrateur fabrique en `<id>@<seq>#<epoch>` et pose dans
    l'environnement du worker. Un seul producteur, deja epingle par le validateur — pas une
    deuxieme horloge a tenir.
    """
    if since and since > 0:
        return float(since), "arg"
    jeton = os.environ.get("AUTOPORT_ATTEMPT_ID") or ""
    if "#" in jeton:
        queue = jeton.rsplit("#", 1)[1]
        if queue.isdigit():
            return float(queue), "env"
    return 0.0, "-"


def red_base(root: str, item_id: str, since: float = 0.0) -> tuple[str, str, float, str]:
    """La revision d'avant CET ESSAI : (ref, genre, instant retenu, d'ou vient l'instant).

    JAMAIS la base de l'ITEM. Un item qui a deja commite hier porterait une base d'hier, et
    tout ce que le monde a commite depuis lui serait impute : c'est exactement ce qui a tue
    l'essai 2 de `hdr-shadow-range` le 13/09.

    Trois derivations, de la plus sure a la plus conservatrice :
      `attempt`   on connait l'instant de depart : parent du PREMIER commit de l'item pose
                  APRES lui.
      `head`      on le connait, et l'item n'a rien commite depuis : `HEAD`. Son travail est
                  alors dans l'arbre de travail, que l'arbre jetable ne porte pas — un rouge
                  qu'il vient de fabriquer se lira donc NEUF, ce qui est le sens voulu.
      `walkback`  on ne le connait pas : on remonte `HEAD` tant que les commits sont de CET
                  item, et on s'arrete au premier qui ne l'est pas. Une serie d'essais que
                  rien n'a separes se lit alors comme un seul : la base est plus VIEILLE que
                  la verite, donc plus de rouges se lisent NEUFS. Le doute ne relache pas.
    """
    t0, d_ou = attempt_start(since)
    if t0 > 0:
        posterieurs = [sha for sha, ct in _own_commits(root, item_id) if ct >= int(t0) - 1]
        if posterieurs:
            parents = _git(root, "rev-parse", "%s^" % posterieurs[-1]).split()
            return (parents[0] if parents else posterieurs[-1]), "attempt", t0, d_ou
        return "HEAD", "head", t0, d_ou
    marque = "[autoport/%s]" % item_id
    for ligne in _git(root, "log", "--format=%H%x09%s", "-n", "80").splitlines():
        sha, _, sujet = ligne.partition("\t")
        if item_id and sujet.startswith(marque):
            continue
        return sha, "walkback", 0.0, d_ou
    return "HEAD", "head", 0.0, d_ou


# ======================================== le rouge est-il DEJA LA ? on le REJOUE, on ne le devine pas =
MAX_PROBE_NODES = int(os.environ.get("AUTOPORT_SUITE_PROBE_MAX") or 40)


def replay(root: str, refs: list[str], nodes: list[str],
           timeout_s: int = 600) -> tuple[dict, dict]:
    """Rejoue `nodes` a chaque revision de `refs`, dans UN arbre de travail jetable.

    Rend `({ref: {nodeid: verdict}}, info)`. Verdicts : `failed`, `passed`, `skipped`,
    `absent` (le fichier du test n'existe pas a cette revision), `unknown` (pytest n'a rien
    rendu de lisible pour ce nodeid).

    UN SEUL ARBRE, recycle par `checkout` : la copie complete coute 3 s et 765 Mo sur cet
    arbre, un `checkout` entre deux revisions voisines coute 0,9 s. Deux arbres simultanes
    tiendraient mal dans un `/tmp` en memoire.

    LES DEUX BRAS SE MESURENT AU MEME ENDROIT. Comparer « la suite complete dans l'arbre
    livre » a « un nodeid seul dans un arbre jetable » comparerait deux instruments : un test
    qui lit un fichier GITIGNORE rend un verdict different hors de l'arbre livre — mesure du
    13/09, 7 rouges en detache contre 5 dans l'arbre livre au MEME commit. On rejoue donc AUSSI
    a `HEAD`, dans le meme arbre jetable, et c'est `base` CONTRE `head` qui decide.
    """
    info = {"ran": 0, "seconds": 0.0, "error": "-", "worktree": "-", "capped": 0}
    res = {ref: {} for ref in refs}
    if not refs or not nodes:
        return res, info
    if len(nodes) > MAX_PROBE_NODES:
        info["capped"] = len(nodes) - MAX_PROBE_NODES
        nodes = nodes[:MAX_PROBE_NODES]
    t0 = time.time()
    tmpd = tempfile.mkdtemp(prefix="suite-replay-")
    wt = os.path.join(tmpd, "wt")
    try:
        r = subprocess.run(["git", "-C", root, "worktree", "add", "--detach", wt, refs[0]],
                           capture_output=True, text=True, timeout=timeout_s)
        if r.returncode != 0:
            info["error"] = (r.stderr or "worktree-add-echec").strip().splitlines()[-1][:160]
            return res, info
        info["worktree"] = wt
        for ref in refs:
            c = subprocess.run(["git", "-C", wt, "checkout", "--detach", "--force", ref],
                               capture_output=True, text=True, timeout=timeout_s)
            if c.returncode != 0:
                for n in nodes:
                    res[ref][n] = "unknown"
                info["error"] = (c.stderr or "checkout-echec").strip().splitlines()[-1][:160]
                continue
            a_jouer = []
            for n in nodes:
                fichier = n.split("::", 1)[0]
                if os.path.exists(os.path.join(wt, fichier)):
                    a_jouer.append(n)
                else:
                    res[ref][n] = "absent"
            if not a_jouer:
                continue
            xml = os.path.join(tmpd, "replay.xml")
            try:
                subprocess.run([sys.executable, "-m", "pytest", "-q", "-p", "no:cacheprovider",
                                "--junitxml=" + xml, *a_jouer],
                               cwd=wt, capture_output=True, text=True, timeout=timeout_s)
            except (OSError, subprocess.SubprocessError) as exc:       # noqa: BLE001
                info["error"] = ("%s" % exc)[:160]
            lu = read_junit(xml) or {}
            try:
                os.remove(xml)
            except OSError:
                pass
            for n in a_jouer:
                v = (lu.get(n) or ("unknown", ""))[0]
                res[ref][n] = {"failure": "failed", "error": "failed"}.get(v, v)
        info["ran"] = 1
    except (OSError, subprocess.SubprocessError) as exc:               # noqa: BLE001
        info["error"] = ("%s" % exc)[:160]
    finally:
        subprocess.run(["git", "-C", root, "worktree", "remove", "--force", wt],
                       capture_output=True, text=True, timeout=120)
        subprocess.run(["git", "-C", root, "worktree", "prune"],
                       capture_output=True, text=True, timeout=120)
        shutil.rmtree(tmpd, ignore_errors=True)
        info["seconds"] = round(time.time() - t0, 1)
    return res, info


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
          timeout_s: int | None = None, record: bool = True, since: float = 0.0) -> dict:
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
        "unwaived_new": -1, "unwaived_new_list": [],
        "unwaived_known": -1, "unwaived_known_list": [],
        "red_base_ref": "-", "red_base_kind": "-", "red_base_since": 0,
        "red_base_since_from": "-",
        "replay_ran": 0, "replay_seconds": 0.0, "replay_error": "-", "replay_capped": 0,
        "replay_base": [], "replay_head": [],
        "inherited_named": -1, "inherited_unnamed": [],
        "inherited_filed": -1, "inherited_unfiled": [], "findings_read": 0,
        "journal_unseen": -1, "journal_unseen_list": [],
        "previous_at": "-", "previous_runs": len(read_journal(autoport)),
        "verdict": "refuse", "reason": "", "refused_for": [],
    }
    if not os.path.isdir(suite_abs):
        d["refused_for"] = ["suite-absente"]
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
    # LES SIGNALEMENTS DE L'ESSAI. Meme convention que `lib/findings_gate.sh` : une ligne triee
    # porte `-> item:<id>` ou `-> ecarte:<raison>`. On la lit, on ne l'ecrit jamais.
    findings = ""
    chemin_find = os.path.join(autoport, "reports", item_id, "FINDINGS.txt") if item_id else ""
    if chemin_find and os.path.exists(chemin_find):
        try:
            with open(chemin_find, encoding="utf-8", errors="replace") as f:
                findings = f.read()
            d["findings_read"] = 1
        except OSError:
            findings = ""
    d["self_added_unnamed"] = [n for n in propres if n not in rapport]
    d["self_added_named"] = len(propres) - len(d["self_added_unnamed"])

    # ------------------------------------------------------------------ 3. LE JUGEMENT ------
    # CHAQUE DEFAUT PORTE SON NOM. La phrase est pour l'humain ; le slug est pour qui compte.
    # Sans lui, « la porte a refuse » ne distingue pas « ce build a casse la suite » de « tu
    # n'as pas signale un rouge qui n'est pas de toi » — et un recensement qui veut compter les
    # refus IMPUTES devrait deviner. Le journal le garde, la publication aussi.
    defauts: list[str] = []
    genres: list[str] = []

    def faute(genre: str, texte: str) -> None:
        genres.append(genre)
        defauts.append(texte)

    if tue:
        faute("plafond", "la suite n'a pas rendu la main en %d s (plafond dur) : elle a ete tuee, "
                       "et une suite tuee n'a rien prouve" % plafond)
    if resultats is None:
        faute("junit", "le junit de la suite est illisible ou absent (pytest rc=%d) : le code "
                       "de retour seul ne distingue pas « un test a rate » de « la collecte a "
                       "echoue »" % rc)
    if rc not in (0, 1) and not tue:
        faute("rc", "pytest est sorti en %d — usage, collecte impossible ou aucun test "
                       "collecte ; ce n'est pas « aucun test n'a rate »" % rc)
    if registre is None:
        faute("registre", "le registre des echecs assumes (%s) est illisible : sans lui aucun "
                       "rouge ne peut etre dispense, et un registre casse ne dispense pas tout"
                       % registre_rel)

    if resultats is not None:
        rouges = sorted(k for k, (v, _m) in resultats.items() if v in ("failure", "error"))
        d["collected"] = len(resultats)
        d["failed"] = len(rouges)
        d["failed_list"] = rouges
        if not resultats:
            faute("collecte-vide", "la suite n'a COLLECTE aucun test : une suite qui ne collecte rien "
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
            # CE QUE LA COURSE PRECEDENTE AVAIT VU : publie, et RIEN DE PLUS. Ce journal est la
            # trace de l'item lui-meme ; il ne classe rien et ne dispense rien.
            precedent = read_journal(autoport)
            connus, quand = set(), "-"
            for r in reversed(precedent):
                if r.get("unwaived") is not None:
                    connus = set(r.get("unwaived") or [])
                    quand = str(r.get("at") or "-")
                    break
            d["previous_at"] = quand
            d["journal_unseen_list"] = [n for n in non_couverts if n not in connus]
            d["journal_unseen"] = len(d["journal_unseen_list"])

            # ================== HERITE OU NEUF : ON LE MESURE A LA BASE DE L'ESSAI ==========
            # Le meme nodeid rejoue dans UN arbre jetable, a la base de l'essai puis a `HEAD`.
            # ROUGE AUX DEUX = HERITE : l'essai ne l'a pas fabrique, il ne le paie pas. Tout le
            # reste est NEUF et refuse — vert a la base, absent, indecidable, arbre impossible.
            # Le sens de l'erreur est choisi : un doute ne relache jamais la porte.
            rbase, rkind, rsince, rfrom = red_base(root, item_id, since)
            d["red_base_kind"] = rkind
            d["red_base_since"] = int(rsince)
            d["red_base_since_from"] = rfrom
            tete = (_git(root, "rev-parse", "HEAD").split() or ["HEAD"])[0]
            d["red_base_ref"] = (rbase[:12] if re.fullmatch(r"[0-9a-f]{40}", rbase) else rbase)
            herites, neufs = [], list(non_couverts)
            if non_couverts:
                refs = [rbase] if rbase == tete else [rbase, tete]
                vus, info = replay(root, refs, non_couverts)
                d["replay_ran"] = info["ran"]
                d["replay_seconds"] = info["seconds"]
                d["replay_error"] = info["error"]
                d["replay_capped"] = info["capped"]
                vbase = vus.get(rbase, {})
                vtete = vus.get(tete, vbase)
                d["replay_base"] = ["%s:%s" % (n, vbase.get(n, "unknown"))
                                    for n in non_couverts]
                d["replay_head"] = ["%s:%s" % (n, vtete.get(n, "unknown"))
                                    for n in non_couverts]
                if info["ran"]:
                    herites = [n for n in non_couverts
                               if vbase.get(n) == "failed" and vtete.get(n) == "failed"]
                    neufs = [n for n in non_couverts if n not in herites]
            d["unwaived_known"] = len(herites)
            d["unwaived_known_list"] = herites
            d["unwaived_new"] = len(neufs)
            d["unwaived_new_list"] = neufs

            if neufs:
                faute(
                    "neufs",
                    "%d test(s) de la suite du harnais sont ROUGES, aucune dispense ecrite ne "
                    "les couvre, et ils etaient VERTS a la base de CET essai (%s, %s) : c'est "
                    "ce travail-ci qui les rend rouges — %s. Repare le test ou inscris-le dans "
                    "%s avec sa raison, sa signature et le nom de qui doit trancher."
                    % (len(neufs), d["red_base_ref"], rkind, ",".join(neufs[:8]), registre_rel))
            # L'HERITE NE MEURT PAS EN SILENCE. Il ne refuse pas la fermeture — mais il ne
            # disparait pas non plus : il est NOMME dans le rapport et TRIE dans FINDINGS.txt,
            # faute de quoi l'essai suivant le retrouvera intact et paiera l'enquete a son tour.
            if herites:
                d["inherited_unnamed"] = [n for n in herites if n not in rapport]
                d["inherited_named"] = len(herites) - len(d["inherited_unnamed"])
                d["inherited_unfiled"] = [n for n in herites if not _trie(findings, n)]
                d["inherited_filed"] = len(herites) - len(d["inherited_unfiled"])
                manquants = sorted(set(d["inherited_unnamed"]) | set(d["inherited_unfiled"]))
                if manquants:
                    faute(
                        "signalement",
                        "%d rouge(s) HERITE(S) ne sont pas passes en signalement : %s. Ils ne "
                        "sont PAS de cet essai — ils sont deja rouges a sa base (%s) et la "
                        "porte ne les lui impute pas — mais un rouge herite que personne "
                        "n'ecrit est retrouve intact par l'essai suivant, qui repaie "
                        "l'enquete. Nomme chacun dans ton rapport ET dans "
                        "reports/%s/FINDINGS.txt avec '-> item:<id>' ou '-> ecarte:<raison>'."
                        % (len(manquants), ",".join(manquants[:8]), d["red_base_ref"],
                           item_id or "<id>"))
    if d["self_added"] > 0 and d["unwaived_new"] and d["unwaived_new"] > 0:
        faute(
            "dispense-propre",
            "%d entree(s) du registre ont ete ajoutees par CET item (%s, base %s) : elles ne "
            "dispensent pas SES propres rouges. Un item ne se donne pas du vert en inscrivant "
            "son echec au registre." % (d["self_added"], ",".join(propres[:6]), d["base_ref"]))
    if d["self_added"] > 0 and d["self_added_unnamed"]:
        faute(
            "dispense-non-nommee",
            "%d entree(s) ajoutees au registre ne sont NOMMEES nulle part dans le rapport de "
            "l'item (%s) : une dispense que personne ne lit est une regression silencieuse."
            % (len(d["self_added_unnamed"]), ",".join(d["self_added_unnamed"][:6])))

    d["verdict"] = "pass" if not defauts else "refuse"
    d["reason"] = " | ".join(defauts)
    d["refused_for"] = genres

    if record:
        _append_journal(autoport, {
            "at": time.strftime("%Y-%m-%dT%H:%M:%S"), "item": item_id,
            "head": (_git(root, "rev-parse", "--short", "HEAD").strip() or "-"),
            "collected": d["collected"], "failed": d["failed"],
            "unwaived": d["unwaived_list"], "duration_s": d["duration_s"],
            "verdict": d["verdict"], "red_base": d["red_base_ref"],
            "red_base_kind": d["red_base_kind"],
            "inherited": d["unwaived_known_list"], "introduced": d["unwaived_new_list"],
            "refused_for": d["refused_for"],
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
             "unwaived_new_list", "unwaived_known", "unwaived_known_list",
             "red_base_ref", "red_base_kind", "red_base_since", "red_base_since_from",
             "replay_ran", "replay_seconds", "replay_error", "replay_capped",
             "replay_base", "replay_head",
             "inherited_named", "inherited_unnamed", "inherited_filed", "inherited_unfiled",
             "findings_read", "journal_unseen", "journal_unseen_list",
             "previous_at", "previous_runs", "verdict", "refused_for", "suite_dir")
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
    ap.add_argument("--since", type=float, default=0.0,
                    help="instant de depart de l'essai (epoch) ; sinon AUTOPORT_ATTEMPT_ID")
    a = ap.parse_args(argv)
    ici = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    autoport = a.autoport or ici
    root = a.root or os.path.dirname(autoport)
    d = judge(root, autoport, a.item, budget_s=a.budget, timeout_s=a.timeout,
              record=not a.no_record, since=a.since)
    for ligne in publish(d, a.prefix):
        print(ligne)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
