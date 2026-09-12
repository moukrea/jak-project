#!/usr/bin/env python3
"""lib/naming_authority_selftest.py — LE BANC DE `harness-naming-authority-completion`.

CE QU'IL MESURE, DANS L'ORDRE DES TERMES DU LIVRABLE. Chaque axe joue DEUX CODES quand c'est
possible : celui du disque et celui d'AVANT ce chantier, ancre par MARQUEUR et jamais par `HEAD:`
(un temoin lu a `HEAD:` s'accuse lui-meme des le commit). Le commit retenu est publie.

  1. UN SEUL NOMMEUR        recensement des sites qui FABRIQUENT un nom de fichier de course,
                            aiguille construite PAR l'autorite, avec deux controles negatifs.
  2. LE BRAS D'ABLATION     par bras et par LECTEUR, le nom ecrit et le nom lu. L'egalite est le
                            verdict ; le bras d'AVANT montre le lecteur aveugle a l'ablation.
  3. LES TEMOINS            ceux qu'on a CONVERTIS en mesure de comportement, avec leur controle
                            negatif, et ceux qui restent LITTERAUX, avec leur raison ecrite.
  4. LA PROPRETE D'ARBRE    plus un seul recensement ne l'affirme ; et ce qui la fait respecter
                            — GATE 0 et GATE 1 — est NOMME, sinon le retrait serait un retrait.
  5. LA PURGE               deux purges lancees ensemble sur le MEME fichier, meme instrument
                            des deux cotes : le verrou partage ou la collision.
  6. LE BLOC RENDU          borne, et il DIT combien il n'affiche pas ; les plus anciens d'abord.
  7. L'ORIGINE DU VERDICT   le refus de promotion nomme d'ou vient le verdict qu'il cite.
  8. LA CITATION            un croisillon dans une chaine ne coupe plus la ligne.
  9. LE SCEAU               la paire de la course precedente est ARCHIVEE avant d'etre detruite,
                            et les deux noms neufs s'apparient par la regle du globber existant.

RIEN N'EST SIMULE DU COTE PRODUCTEUR : le vrai `proof_impossible.sh`, le vrai `impossible.py`,
le vrai `backlog.py`, le vrai bloc de `proof_run.sh` leve TEL QUEL entre ses marqueurs.
"""
from __future__ import annotations

import ast
import hashlib
import importlib.util
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent
sys.path.insert(0, str(AP / "lib"))
import impossible as I                                   # noqa: E402  — L'AUTORITE DE NOMMAGE

RAISON = "verrou-de-deploiement"
DETAIL = "le constructeur tient le verrou"
BUSY = "deploy-in-progress pid=4242 vivant"
MARQUEUR_LITTERAL = "NOM-LITTERAL-ATTENDU:"

# Les marqueurs qui ancrent chaque bras d'AVANT. Un marqueur est une chaine que ce chantier a
# INTRODUITE : le premier commit, en remontant, ou elle est absente est l'etat d'avant.
M_PURGE = "PURGE/verrou-partage"
M_BLOC = "TEXTE/bloc-borne"
M_ORIGINE = "VERDICT/origine-dite"
M_CITATION = "decommente()"
M_PAIRE = "PAIRE-PRECEDENTE/debut"
M_PURETE = "LA PROPRETE DE L'ARBRE N'EST PLUS AFFIRMEE ICI"
M_LECTEUR = "impossible_name_read"

# Les dossiers qui ne sont pas du code du harnais : produits, archives, brouillons.
HORS = {"logs", "reports", "archive", "backups", "tmp", "scratch", "dist", "gold", "codex",
        "__pycache__", "refset", "refset-candidates", "refset-origine-pure", "refset-unify",
        "cgo-cache", "demos", "assets", "report_blocks", "prompts", "plans", "design",
        "milestones", "ops", "oracle", "rigwork", "gsf", "owner-ok", "hooks"}


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ")[:400]))


def charger(chemin: Path, nom: str):
    spec = importlib.util.spec_from_file_location(nom, chemin)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[nom] = mod
    spec.loader.exec_module(mod)
    return mod


def before_blob(rel: str, marker: str) -> tuple[str, str]:
    """Le premier commit, en remontant, dont `rel` ne porte PAS `marker`."""
    try:
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "150",
                               "--", rel], capture_output=True, text=True,
                              timeout=120).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return "", ""
    for commit in hist:
        try:
            blob = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (commit, rel)],
                                  capture_output=True, text=True, timeout=120).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if blob and marker not in blob:
            return commit, blob
    return "", ""


def faux_depot(root: Path, nom="faux-depot") -> Path:
    """Un depot jetable qui porte un verrou de deploiement VIVANT : `proof_impossible.sh` lit le
    verrou du depot courant, et un pid qui repond rend « tenu depuis » mesurable."""
    d = root / nom
    (d / ".autoport").mkdir(parents=True, exist_ok=True)
    (d / ".autoport" / ".deploy-in-progress").write_text(
        "banc pid=%d\n" % os.getpid(), encoding="utf-8")
    if not (d / ".git").exists():
        subprocess.run(["git", "init", "-q", "."], cwd=d, capture_output=True, timeout=60)
    return d


def semer(depot: Path, dossier: Path, item_id: str, suffix: str = "") -> Path:
    """Ecrit l'etat nomme AVEC LE VRAI SCRIPT, et rend le chemin que L'AUTORITE lui donne."""
    dossier.mkdir(parents=True, exist_ok=True)
    subprocess.run(["bash", str(AP / "lib" / "proof_impossible.sh"), str(dossier), item_id,
                    suffix, RAISON, DETAIL, "23880", "1800", BUSY],
                   cwd=depot, capture_output=True, text=True, timeout=120)
    return dossier / I.arm_name("impossible", suffix)


# ===================================================== 1. UN SEUL NOMMEUR ====================
def fichiers_du_harnais():
    """Le CODE du harnais : `.py` et `.sh`, hors produits, archives et brouillons."""
    out = []
    for p in sorted(AP.rglob("*")):
        if p.suffix not in (".py", ".sh") or not p.is_file():
            continue
        rel = p.relative_to(AP)
        if any(part in HORS for part in rel.parts):
            continue
        if ".bak" in p.name:
            continue
        out.append(p)
    return out


def aiguilles():
    """LES NOMS QUE L'AUTORITE PRODUIT, plus les deux GABARITS par lesquels on les fabrique.

    L'aiguille n'est jamais ecrite ici : elle est DEMANDEE. Un genre de plus dans `KINDS`
    entre dans le recensement sans qu'une ligne de ce banc ne bouge."""
    mots = set()
    for kind, ext in I.KINDS.items():
        for suf in I.SUFFIXES:
            mots.add(I.arm_name(kind, suf))
        mots.add("proof$SUF%s" % ext)         # le gabarit bash
        mots.add("proof%%s%s" % ext)          # le gabarit python
    return sorted(mots, key=len, reverse=True)


def decommente(chemin) -> list:
    """LES LIGNES DE CODE d'un fichier, commentaires retires par LE MEME decommenteur que la
    derivation des sources du verdict. En ecrire un deuxieme ici serait refaire, dans ce banc,
    exactement la faute que ce chantier corrige."""
    r = subprocess.run(["bash", str(AP / "lib" / "verdict_sources.sh"), "-", "decomment",
                        str(chemin)], capture_output=True, text=True, timeout=120)
    return (r.stdout or "").splitlines()


def _docstrings(arbre):
    """Les noeuds de PROSE : docstring de module, de classe, de fonction. Une prose qui cite un
    nom de fichier ne fabrique rien — elle en PARLE. Les compter serait accuser les
    commentaires, et c'est exactement la faute que `lib/verdict_sources.sh` a deja corrigee
    pour les sources du verdict."""
    ids = set()
    for n in ast.walk(arbre):
        if not isinstance(n, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            continue
        corps = getattr(n, "body", None) or []
        if (corps and isinstance(corps[0], ast.Expr)
                and isinstance(corps[0].value, ast.Constant)
                and isinstance(corps[0].value.value, str)):
            ids.add(id(corps[0].value))
    return ids


def _sites_python(p, mots, brut):
    """Les CHAINES d'un `.py` qui portent un nom fabrique, docstrings exclues. Lu dans l'AST :
    un grep ne sait pas distinguer une prose d'un litteral, et ce banc jugerait des commentaires."""
    try:
        arbre = ast.parse("\n".join(brut))
    except SyntaxError:
        return []
    proses = _docstrings(arbre)
    vus = []
    for n in ast.walk(arbre):
        if not isinstance(n, ast.Constant) or not isinstance(n.value, str):
            continue
        if id(n) in proses:
            continue
        if any(m in n.value for m in mots):
            vus.append((getattr(n, "lineno", 0), getattr(n, "end_lineno", 0) or
                        getattr(n, "lineno", 0)))
    return sorted(set(vus))


def sites_de_fabrication(fichiers, mots, racine=None):
    """(sites sans marqueur, sites marques, lignes lues) — un nom fabrique, une ligne."""
    racine = racine or AP
    nus, marques = [], []
    lignes_lues = 0
    for p in fichiers:
        if p.name in ("impossible.py", HERE.name):
            continue                      # l'autorite, et ce banc qui cite les aiguilles
        try:
            brut = p.read_text(encoding="utf-8", errors="replace").splitlines()
        except OSError:
            continue
        if p.suffix == ".py":
            lignes = _sites_python(p, mots, brut)
            lignes_lues += len(brut)
        else:
            code = decommente(p)
            lignes_lues += len(code)
            lignes = [(i + 1, i + 1) for i, l in enumerate(code) if any(m in l for m in mots)]
        # LE MARQUEUR SE CHERCHE SUR TOUT LE NOEUD, pas sur sa premiere ligne : une chaine
        # ecrite en concatenation implicite commence des lignes avant le nom qu'elle porte, et
        # un marqueur pose a cote du nom serait alors invisible.
        for ln, fin in lignes:
            entour = brut[max(0, ln - 2):max(fin, ln)]
            cible = marques if any(MARQUEUR_LITTERAL in x for x in entour) else nus
            try:
                nom = p.relative_to(racine)
            except ValueError:
                nom = p.name
            cible.append("%s:%d" % (nom, ln))
    return nus, marques, lignes_lues


def axe_nommeur(root: Path) -> None:
    mots = aiguilles()
    fichiers = fichiers_du_harnais()
    nus, marques, lignes = sites_de_fabrication(fichiers, mots)
    kv("nm_aiguilles", len(mots))
    kv("nm_population", len(fichiers))
    kv("nm_lignes_lues", lignes)
    kv("nm_sites", len(nus))
    kv("nm_sites_liste", ",".join(nus[:24]) or "-")
    kv("nm_marques", len(marques))
    kv("nm_marques_liste", ",".join(marques[:24]) or "-")
    # LES RAISONS ECRITES A COTE DE CHAQUE MARQUEUR. Un marqueur sans raison serait un
    # laissez-passer ; on compte ceux qui n'en portent pas.
    raisons, sans_raison = set(), 0
    for p in fichiers:
        try:
            txt = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        if p.name == HERE.name:
            continue                       # ce banc DEFINIT le marqueur ; il ne le porte pas
        for m in re.finditer(re.escape(MARQUEUR_LITTERAL) + r"\s*([a-z0-9-]*)", txt):
            if m.group(1):
                raisons.add(m.group(1))
            else:
                sans_raison += 1
    kv("nm_raisons", len(raisons))
    kv("nm_raisons_liste", ",".join(sorted(raisons)) or "-")
    kv("nm_marques_sans_raison", sans_raison)

    # LE CONTROLE NEGATIF, DANS LES DEUX SENS : un fichier qui fabrique un nom DOIT etre vu ;
    # le meme fichier, marque, ne doit PAS l'etre. Sans ces deux jambes, `nm_sites=0` se lirait
    # aussi bien « plus un seul nommeur » que « le compteur ne regarde rien ».
    bac = root / "ctrl-nommeur"
    bac.mkdir(parents=True, exist_ok=True)
    nom = I.arm_name("impossible", "-off")
    (bac / "triche.py").write_text('f = d / "%s"\n' % nom, encoding="utf-8")
    (bac / "marque.py").write_text(
        'f = d / "%s"  # %s controle-negatif\n' % (nom, MARQUEUR_LITTERAL), encoding="utf-8")
    c_nus, c_marques, _ = sites_de_fabrication([bac / "triche.py"], mots, racine=bac)
    kv("nm_ctrl_sans_marqueur", len(c_nus))
    c_nus2, c_marques2, _ = sites_de_fabrication([bac / "marque.py"], mots, racine=bac)
    kv("nm_ctrl_avec_marqueur", len(c_nus2))
    kv("nm_ctrl_marque_vue", len(c_marques2))


# ============================================ 2. LE BRAS D'ABLATION, PAR LECTEUR =============
def axe_bras(root: Path) -> None:
    depot = faux_depot(root, "bras-depot")
    reports = root / "bras" / "reports"
    item = "zzz-banc-naming"
    ok = 1
    for suf, arm in (("", "livre"), ("-off", "ablation")):
        d = reports / item
        for f in list(d.glob("*")) if d.exists() else []:
            f.unlink()
        ecrit = semer(depot, d, item, suf)
        attendu = I.arm_name("impossible", suf)
        kv("br_%s_ecrit" % arm, ecrit.name)
        kv("br_%s_pose" % arm, 1 if ecrit.exists() else 0)

        # LECTEUR 1 — l'autorite elle-meme.
        st = I.read(str(reports), item)
        lu_autorite = os.path.basename((st or {}).get("file") or "-")
        kv("br_%s_lu_autorite" % arm, lu_autorite)

        # LECTEUR 2 — la premiere ligne du juge (`impossible.py why`, appelee par generic.sh).
        r = subprocess.run([sys.executable, str(AP / "lib" / "impossible.py"), "why",
                            "--reports", str(reports), "--item", item],
                           capture_output=True, text=True, timeout=120)
        vu = ""
        m = re.search(r"etat (\S+) ecrit le", r.stdout or "")
        if m:
            vu = os.path.basename(m.group(1))
        kv("br_%s_lu_juge" % arm, vu or "-")

        # LECTEUR 3 — le recensement de `harness-attempt-not-burned-by-foreign-cause`, celui qui
        # lisait un nom CODE EN DUR et ne voyait donc que le bras livre.
        env = dict(os.environ, AUTOPORT_CENSUS_DIR=str(d),
                   AUTOPORT_CENSUS_ARMED="1" if not suf else "0")
        c = subprocess.run(["bash", str(AP / "lib" / "census" /
                                        "harness-attempt-not-burned-by-foreign-cause.sh")],
                           capture_output=True, text=True, timeout=900, env=env)
        def cle(k, sortie=c):
            v = [l for l in (sortie.stdout or "").splitlines() if l.startswith(k + "=")]
            return v[-1].split("=", 1)[1] if v else ""
        # LE RECENSEMENT REPUBLIE SES BRUTS SOUS UN PREFIXE A LUI (`fcd_live_`) : c'est cette
        # cle-la qui arrive dans proof.txt, donc c'est elle qu'on lit.
        kv("br_%s_lu_recensement" % arm, cle("fcd_live_impossible_name_read") or "-")
        kv("br_%s_vu_recensement" % arm, cle("proof_impossible_this_run") or "-")

        # LECTEUR 4 — le texte rendu a l'owner passe par `read_all`, le meme lecteur.
        tous = I.read_all(str(reports))
        kv("br_%s_lu_texte" % arm,
           os.path.basename((tous.get(item) or {}).get("file") or "-"))

        lus = [lu_autorite, vu or "-",
               cle("fcd_live_impossible_name_read") or "-",
               os.path.basename((tous.get(item) or {}).get("file") or "-")]
        kv("br_%s_lecteurs_egaux" % arm,
           1 if all(x == attendu for x in lus) and ecrit.name == attendu else 0)
        kv("br_%s_lecteurs" % arm, len(lus))
        if not (all(x == attendu for x in lus) and ecrit.name == attendu):
            ok = 0
    kv("br_tous_bras_egaux", ok)

    # LE BRAS D'AVANT : le MEME recensement, a son commit d'avant, sur le MEME semis d'ablation.
    # Il cherche un nom code en dur : il ne voit rien, et c'est le defaut, mesure.
    rel = ".autoport/lib/census/harness-attempt-not-burned-by-foreign-cause.sh"
    commit, blob = before_blob(rel, M_LECTEUR)
    kv("br_avant_commit", commit[:12] or "-")
    kv("br_avant_marqueur_absent", 1 if (blob and M_LECTEUR not in blob) else 0)
    if blob:
        vieux = root / "recensement-avant.sh"
        vieux.write_text(blob, encoding="utf-8")
        d = reports / item
        for f in list(d.glob("*")):
            f.unlink()
        semer(depot, d, item, "-off")
        env = dict(os.environ, AUTOPORT_CENSUS_DIR=str(d), AUTOPORT_CENSUS_ARMED="0")
        c = subprocess.run(["bash", str(vieux)], capture_output=True, text=True,
                           timeout=900, env=env)
        v = [l for l in (c.stdout or "").splitlines()
             if l.startswith("proof_impossible_this_run=")]
        kv("br_avant_vu_ablation", v[-1].split("=", 1)[1] if v else "-")
    else:
        kv("br_avant_vu_ablation", "-")


# ======================================= 3. TEMOINS CONVERTIS / RESTES LITTERAUX =============
def axe_temoins(root: Path) -> None:
    """Les DEUX temoins convertis sont rejoues ICI, et on leur montre un faux script."""
    fc = charger(AP / "lib" / "foreign_cause_selftest.py", "fc_naming")
    # Le temoin converti, tel qu'il rend aujourd'hui.
    ok_wait = 1
    for suf in I.SUFFIXES:
        vu = os.path.basename(fc._eval_sous_autorite(
            'printf "%s" "$D/$AP_NAME_wait"', suf))
        if vu != I.arm_name("wait", suf):
            ok_wait = 0
    kv("tm_converti_vrai", ok_wait)
    # LE CONTROLE NEGATIF : la MEME mesure sur une expression qui RE-FABRIQUE le nom en dur.
    # Sur le bras livre elle tombe juste par hasard ; sur l'ablation elle se trahit.
    dur = 1
    for suf in I.SUFFIXES:
        vu = os.path.basename(fc._eval_sous_autorite('printf "%s" "$D/proof-wait.txt"', suf))
        if vu != I.arm_name("wait", suf):
            dur = 0
    kv("tm_converti_controle_nom_en_dur", dur)
    kv("tm_convertis", 2)
    kv("tm_convertis_liste",
       "foreign_cause_selftest.pr_writes_wait_file,foreign_cause_selftest.pr_clears_impossible")


# ================================================ 4. LA PROPRETE D'ARBRE N'EST PLUS AFFIRMEE =
CLES_PURETE = ("src_engine_dirty", "src_detection_intacte", "src_untouched_")


def affirmations_purete(texte: str) -> int:
    """Les lignes qui AFFIRMENT la proprete de l'arbre : une cle de proprete ET un `faute`."""
    n = 0
    for ligne in (texte or "").splitlines():
        t = ligne.strip()
        if t.startswith("#"):
            continue
        if "faute" in t and any(k in t for k in CLES_PURETE):
            n += 1
    return n


def axe_purete() -> None:
    recensements = sorted((AP / "lib" / "census").glob("*.sh"))
    apres = 0
    for p in recensements:
        apres += affirmations_purete(p.read_text(encoding="utf-8", errors="replace"))
    kv("pu_apres_affirmations", apres)
    kv("pu_recensements_lus", len(recensements))
    avant, ancres = 0, 0
    details = []
    for p in recensements:
        rel = ".autoport/" + str(p.relative_to(AP))
        commit, blob = before_blob(rel, M_PURETE)
        if not blob:
            continue
        ancres += 1
        n = affirmations_purete(blob)
        avant += n
        if n:
            details.append("%s:%d@%s" % (p.name, n, commit[:8]))
    kv("pu_avant_affirmations", avant)
    kv("pu_avant_ancres", ancres)
    kv("pu_avant_details", ",".join(details) or "-")
    kv("pu_retirees", max(0, avant - apres))
    # CE QUI FAIT RESPECTER LE PERIMETRE MAINTENANT QUE L'INSTRUMENT NE L'AFFIRME PLUS. Retirer
    # une affirmation sans nommer ce qui la remplace serait un retrait, pas une correction.
    orch = (AP / "orchestrator.py").read_text(encoding="utf-8", errors="replace")
    kv("pu_gate0_arbre_sale", orch.count("engine_dirty_paths()"))
    gv = (AP / "lib" / "gate_verdict.py").read_text(encoding="utf-8", errors="replace")
    kv("pu_gate1_lit_le_champ", gv.count("SCOPE_FIELD"))
    kv("pu_gate1_appelee", orch.count("scope_decision("))


# =================================================== 5. LA PURGE, DEUX PROCESSUS ============
_PURGEUR = """
import sys, time, json, os
sys.path.insert(0, %r)
import importlib.util
spec = importlib.util.spec_from_file_location("imp_purge", sys.argv[1])
M = importlib.util.module_from_spec(spec); spec.loader.exec_module(M)
# LE MEME INSTRUMENT DES DEUX COTES : on ELARGIT la fenetre de course en retardant le retrait.
# Sans ca, une collision reste possible mais pas certaine, et le bras d'AVANT rendrait parfois
# zero defaut — un banc qui depend du hasard ne mesure rien.
_vrai = os.remove
def lent(p):
    time.sleep(0.004)
    return _vrai(p)
M.os.remove = lent
r = M.purge(sys.argv[2], current_item="zzz-absent", since=0.0, who="proc-" + sys.argv[3])
print(json.dumps({"purged": len(r["purged"]),
                  "echecs": sum(1 for x in r["standing"] if x["reason"] == "echec-de-purge")}))
"""


def axe_purge(root: Path, chemins: dict) -> None:
    depot = faux_depot(root, "purge-depot")
    for tag, module in chemins.items():
        if module is None or not Path(module).exists():
            kv("pg_%s_ran" % tag, 0)
            continue
        reports = root / ("purge-" + tag) / "reports"
        n = 60
        for i in range(n):
            semer(depot, reports / ("zzz-purge-%03d" % i), "zzz-purge-%03d" % i, "")
        poses = len(I.scan(str(reports)))
        procs = [subprocess.Popen(
            [sys.executable, "-c", _PURGEUR % str(AP / "lib"), str(module), str(reports),
             str(k)], stdout=subprocess.PIPE, text=True) for k in range(4)]
        purges, echecs = 0, 0
        for pr in procs:
            out, _ = pr.communicate(timeout=600)
            for ligne in (out or "").splitlines():
                try:
                    d = __import__("json").loads(ligne)
                except ValueError:
                    continue
                purges += d["purged"]
                echecs += d["echecs"]
        st = I.journal_stats(str(reports))
        kv("pg_%s_ran" % tag, 1)
        kv("pg_%s_semes" % tag, poses)
        kv("pg_%s_purges_cumules" % tag, purges)
        kv("pg_%s_echecs" % tag, echecs)
        kv("pg_%s_restants" % tag, len(I.scan(str(reports))))
        kv("pg_%s_journal_lignes" % tag, st["lines"])
        kv("pg_%s_journal_malformees" % tag, st["malformed"])


# ================================================== 6. LE BLOC RENDU, BORNE =================
def axe_bloc(root: Path, chemins: dict) -> None:
    depot = faux_depot(root, "bloc-depot")
    reports = root / "bloc" / "reports"
    n = 20
    for i in range(n):
        iid = "zzz-bloc-%02d" % i
        f = semer(depot, reports / iid, iid, "")
        t = time.time() - (3600 * (n - i))        # le plus ANCIEN est le premier seme
        os.utime(f, (t, t))
    for tag, module in chemins.items():
        if module is None or not Path(module).exists():
            kv("bl_%s_ran" % tag, 0)
            continue
        B = charger(Path(module), "bl_" + tag)
        # LE BACKLOG REEL, pour que les items du semis se lisent « hors backlog » comme en vrai ;
        # les etats, eux, viennent du bac a sable.
        bk = B.load(str(AP / "backlog.yaml"))
        bk._reports_dir = lambda r=str(reports): r
        etats = B._impossible.read_all(str(reports))
        texte, digest = bk.bloc_impossible(etats)
        lignes = [l for l in texte.splitlines() if l.startswith("- zzz-bloc")]
        kv("bl_%s_ran" % tag, 1)
        kv("bl_%s_etats" % tag, len(etats))
        kv("bl_%s_detailles" % tag, len(lignes))
        kv("bl_%s_len" % tag, len(texte))
        kv("bl_%s_dit_caches" % tag,
           1 if re.search(r"\+ \d+ etat\(s\)", texte) else 0)
        kv("bl_%s_digest_dit_caches" % tag,
           1 if re.search(r"\+ \d+ etat\(s\)", digest) else 0)
        # UNIQUEMENT QUAND IL Y A UNE QUEUE A LIRE : sans borne il n'y a pas de « non
        # detailles », et `split` rendrait le digest entier — on mesurerait un artefact.
        kv("bl_%s_digest_nomme_les_caches" % tag,
           (1 if "zzz-bloc" in digest.split("non detailles")[-1] else 0)
           if "non detailles" in digest else -1)
        kv("bl_%s_premier" % tag, lignes[0][2:] if lignes else "-")
        compte = getattr(bk, "bloc_impossible_counts", None)
        kv("bl_%s_compte_publie" % tag,
           (compte(etats)["caches"] if compte else -1))


# ============================================ 7. L'ORIGINE DU VERDICT DE PROMOTION ===========
_BACKLOG_MIN = """version: 1
items:
- id: sans-journal
  status: to-test
  owner_test: false
  priority: 1
  feature: un item dont la porte n'a pas tenu
  deliverable: 'rien'
  gate: {key: k, op: '==', value: 0}
"""


def axe_origine(root: Path, chemins: dict) -> None:
    for tag, module in chemins.items():
        if module is None or not Path(module).exists():
            kv("or_%s_ran" % tag, 0)
            continue
        d = root / ("origine-" + tag) / ".autoport"
        (d / "logs").mkdir(parents=True, exist_ok=True)
        (d / "reports").mkdir(parents=True, exist_ok=True)
        chemin = d / "backlog.yaml"
        chemin.write_text(_BACKLOG_MIN, encoding="utf-8")
        B = charger(Path(module), "or_" + tag)
        bk = B.load(str(chemin))
        try:
            bk.machine_proved_to_validated()
        except Exception as exc:                            # noqa: BLE001
            kv("or_%s_erreur" % tag, repr(exc)[:120])
        refus = list(getattr(bk, "machine_promotion_refused", []))
        kv("or_%s_ran" % tag, 1)
        kv("or_%s_refus" % tag, len(refus))
        kv("or_%s_champs" % tag, len(refus[0]) if refus else -1)
        kv("or_%s_origine" % tag, refus[0][3] if (refus and len(refus[0]) >= 4) else "-")
    # L'ORCHESTRATEUR IMPRIME-T-IL CE QU'IL RECOIT. Un quadruplet qu'on deballe en trois
    # explose ; un quadruplet qu'on deballe en quatre sans imprimer l'origine la tait.
    orch = (AP / "orchestrator.py").read_text(encoding="utf-8", errors="replace")
    m = re.search(r"for iid, verdict, journal(.*?)in getattr\(bk, \"machine_promotion_refused\"",
                  orch)
    kv("or_orch_deballe", (m.group(1).strip().strip(",").strip() or "-") if m else "-")
    kv("or_orch_imprime_origine", orch.count("verdict lu depuis {origine}"))


# ================================================ 8. LA CITATION AVEC CROISILLON ============
_VIEUX_SED = ["sed", "-e", "s/^[[:space:]]*#.*$//", "-e", "s/[[:space:]]#.*$//"]
_CITE = re.compile(r"(lib|validators|acquis|tests)/[A-Za-z0-9_./-]+\.(sh|py)")


def axe_citation(root: Path) -> None:
    fichiers = fichiers_du_harnais()
    differents, perdues, total, lignes_dif = 0, 0, 0, 0
    exemples = []
    for p in fichiers:
        neuf_l = decommente(p)
        vieux_l = subprocess.run(_VIEUX_SED + [str(p)], capture_output=True, text=True,
                                 timeout=120).stdout.splitlines()
        neuf, vieux = "\n".join(neuf_l), "\n".join(vieux_l)
        total += 1
        n_dif = sum(1 for x, y in zip(neuf_l, vieux_l) if x != y)
        n_dif += abs(len(neuf_l) - len(vieux_l))
        lignes_dif += n_dif
        if n_dif:
            differents += 1
        a = set(m.group(0) for m in _CITE.finditer(vieux))
        b = set(m.group(0) for m in _CITE.finditer(neuf))
        manquantes = b - a
        if manquantes:
            perdues += len(manquantes)
            if len(exemples) < 8:
                exemples.append("%s:%s" % (p.name, "/".join(sorted(manquantes))[:60]))
    kv("ci_fichiers", total)
    kv("ci_decoupage_different", differents)
    kv("ci_lignes_differentes", lignes_dif)
    kv("ci_citations_recuperees", perdues)
    kv("ci_exemples", ",".join(exemples) or "-")
    # LE CONTROLE NEGATIF : une ligne fabriquee ou l'ANCIENNE regle perd une citation.
    bac = root / "ctrl-citation"
    bac.mkdir(parents=True, exist_ok=True)
    f = bac / "cite.sh"
    f.write_text('grep -q "motif #t dans lib/zzz-controle.sh" "$1"\n', encoding="utf-8")
    vieux = subprocess.run(_VIEUX_SED + [str(f)], capture_output=True, text=True,
                           timeout=60).stdout
    neuf = "\n".join(decommente(f))
    kv("ci_ctrl_vieux_perd", 0 if "lib/zzz-controle.sh" in vieux else 1)
    kv("ci_ctrl_neuf_garde", 1 if "lib/zzz-controle.sh" in neuf else 0)
    # ET LA LISTE EPINGLEE DE CET ITEM N'A PAS BOUGE : le sens de l'erreur est d'AJOUTER, jamais
    # de retirer. On le constate, on ne le decrete pas.
    ident = subprocess.run(["bash", str(AP / "lib" / "verdict_sources.sh"),
                            "harness-naming-authority-completion", "count"],
                           capture_output=True, text=True, timeout=300).stdout.strip()
    kv("ci_sources_epinglees", ident or "-1")


# ==================================================== 9. LE SCEAU ET LA PAIRE PRECEDENTE ====
def bloc_paire() -> str:
    """Le bloc d'archivage de `proof_run.sh`, LEVE TEL QUEL entre ses deux marqueurs."""
    src = (AP / "lib" / "proof_run.sh").read_text(encoding="utf-8", errors="replace")
    debut = src.find(M_PAIRE)
    fin = src.find("PAIRE-PRECEDENTE/fin")
    if debut < 0 or fin < 0:
        return ""
    return src[src.find("\n", debut) + 1:src.rfind("\n", debut, fin)]


def axe_sceau(root: Path) -> None:
    bloc = bloc_paire()
    kv("sc_bloc_leve", 1 if bloc else 0)
    if not bloc:
        return
    for suf, arm in (("", "livre"), ("-off", "ablation")):
        for cas, complet in (("complet", True), ("incomplet", False)):
            d = root / ("sceau-%s-%s" % (arm, cas))
            d.mkdir(parents=True, exist_ok=True)
            pf = d / I.arm_name("proof", suf)
            sf = d / I.arm_name("seal", suf)
            pv = d / I.arm_name("prev_proof", suf)
            sv = d / I.arm_name("prev_seal", suf)
            pv.write_text("vieille-paire\n", encoding="utf-8")
            sv.write_text("vieux-sceau\n", encoding="utf-8")
            if complet:
                pf.write_text("frames=42\ncrash=0\n", encoding="utf-8")
            sf.write_text("seal_sha=abc\nexit_sha=abc\n", encoding="utf-8")
            script = ('set -u\nlog(){ :; }\n'
                      'eval "$(python3 %s names %s)"\n'
                      'D=%s; OUTFILE="$D/$AP_NAME_proof"; SEALFILE="$D/$AP_NAME_seal"\n%s'
                      % (_sq(AP / "lib" / "impossible.py"), _sq(suf), _sq(d), bloc))
            r = subprocess.run(["bash", "-c", script], capture_output=True, text=True,
                               timeout=120)
            tag = "sc_%s_%s" % (arm, cas)
            kv(tag + "_rc", r.returncode)
            kv(tag + "_prev_proof", 1 if pv.exists() else 0)
            kv(tag + "_prev_seal", 1 if sv.exists() else 0)
            kv(tag + "_prev_contenu",
               1 if (pv.exists() and pv.read_text(encoding="utf-8") == "frames=42\ncrash=0\n")
               else 0)
            kv(tag + "_courant_parti", 0 if pf.exists() else 1)
    # LES DEUX NOMS NEUFS S'APPARIENT PAR LA REGLE DU GLOBBER EXISTANT (`${sf%.seal}.txt`).
    # Sans ca, la paire archivee serait invisible a celui-la meme qui la cherche.
    for suf, arm in (("", "livre"), ("-off", "ablation")):
        s_ = I.arm_name("prev_seal", suf)
        kv("sc_%s_appariable" % arm,
           1 if (s_.endswith(".seal")
                 and s_[:-len(".seal")] + ".txt" == I.arm_name("prev_proof", suf)) else 0)


def _sq(txt):
    return "'" + str(txt).replace("'", "'\\''") + "'"


# ===================================================================================== main =
def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="naming-banc-"))
    try:
        ancres = {
            "purge": (".autoport/lib/impossible.py", M_PURGE),
            "bloc": (".autoport/lib/backlog.py", M_BLOC),
            "origine": (".autoport/lib/backlog.py", M_ORIGINE),
            "citation": (".autoport/lib/verdict_sources.sh", M_CITATION),
            "paire": (".autoport/lib/proof_run.sh", M_PAIRE),
        }
        blobs = {}
        for nom, (rel, marker) in ancres.items():
            commit, blob = before_blob(rel, marker)
            kv("before_%s_commit" % nom, commit[:12] or "-")
            kv("before_%s_marqueur_absent" % nom, 1 if (blob and marker not in blob) else 0)
            if blob:
                f = root / ("avant-%s%s" % (nom, Path(rel).suffix))
                f.write_text(blob, encoding="utf-8")
                blobs[nom] = f
            else:
                blobs[nom] = None
        for nom, (rel, marker) in ancres.items():
            vivant = (REPO / rel).read_text(encoding="utf-8", errors="replace")
            kv("marqueur_%s_vivant" % nom, 1 if marker in vivant else 0)

        axe_nommeur(root)
        axe_bras(root)
        axe_temoins(root)
        axe_purete()
        axe_purge(root, {"apres": AP / "lib" / "impossible.py", "avant": blobs["purge"]})
        axe_bloc(root, {"apres": AP / "lib" / "backlog.py", "avant": blobs["bloc"]})
        axe_origine(root, {"apres": AP / "lib" / "backlog.py", "avant": blobs["origine"]})
        axe_citation(root)
        axe_sceau(root)

        for rel in ("lib/impossible.py", "lib/proof_run.sh", "lib/backlog.py",
                    "lib/verdict_sources.sh", "validators/generic.sh", "lib/gate_verdict.py",
                    "lib/foreign_cause_selftest.py", "lib/naming_authority_selftest.py"):
            try:
                h = hashlib.sha256((AP / rel).read_bytes()).hexdigest()[:16]
            except OSError:
                h = "-"
            kv("sha_" + rel.replace("/", "_").replace(".", "_"), h)
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
