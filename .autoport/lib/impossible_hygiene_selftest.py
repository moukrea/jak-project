#!/usr/bin/env python3
"""lib/impossible_hygiene_selftest.py — LE BANC de `harness-impossible-state-hygiene`.

CE QU'IL FAIT. Il SEME des etats nommes « preuve impossible » — les vrais fichiers, ecrits par
le vrai `lib/proof_impossible.sh`, jamais un dictionnaire fabrique ici — dans des dossiers
jetables, puis il mesure les QUATRE points du livrable sur du code REEL, et sur le texte
REELLEMENT RENDU :

  1. PURGE      `impossible.purge` retire ce qui ne decrit plus le present, et NOMME pourquoi.
                Deux controles SEMES : un etat a purger, un etat a LAISSER (l'autre bras de
                l'item en cours). « Rien a purger » ne doit jamais se lire comme « rien fait ».
  2. STATUT     le texte que `backlog.status_report` REND a l'owner : l'etat perime y figure
                dans le bras d'AVANT, il en a disparu dans celui d'APRES. C'est le texte qui
                est juge, pas une intention.
  3. NOMS       le nom du fichier d'attente ECRIT par `lib/proof_run.sh` et celui LU par
                `lib/impossible.py`, PAR BRAS, l'ablation comprise. Le nom ecrit est obtenu en
                EVALUANT l'expression du script lui-meme, jamais en la recopiant ici. La garde
                de course est exercee dans les deux sens : nom present -> elle passe, nom
                divergent -> elle tue la course.
  4. JOURNAL    le journal de validation d'un essai impossible ne commence plus par « proof.txt
                absent ou vide ». Deux journaux SEMES : un impossible (a requalifier) et un
                echec ORDINAIRE (a laisser tel quel).

LES DEUX BRAS, PARTOUT. Le code d'AVANT ce chantier est ancre par MARQUEUR — `git log` remonte
jusqu'au premier commit ou le marqueur est ABSENT — et jamais par `HEAD:` : lu a HEAD, le
temoin d'avant s'accuse lui-meme des le commit. Le commit retenu est PUBLIE.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; `lib/census/harness-impossible-state-hygiene.sh` fait la somme.
"""
from __future__ import annotations

import hashlib
import importlib.util
import os
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
import impossible as _NOMS                    # noqa: E402  — L'AUTORITE DE NOMMAGE


def _sq(txt):
    """Un chemin passe a `bash -c` : entre apostrophes, toujours."""
    return "'" + str(txt).replace("'", "'\\''") + "'"

# Les marqueurs qui datent CE chantier, un par fichier touche.
MARKER_PURGE = "PURGE/etat-perime"            # lib/impossible.py : la purge et ses raisons
MARKER_NOM = "NOMMAGE/un-seul-endroit"        # lib/impossible.py : le nommage d'un bras
MARKER_JOURNAL = "JOURNAL/preuve-impossible"  # orchestrator.py   : l'entete du journal

ITEM_A = "zzz-banc-hygiene-a"      # l'item qu'on mesure MAINTENANT
ITEM_B = "zzz-banc-hygiene-b"      # l'item ABANDONNE en cours de route
ITEM_C = "zzz-banc-hygiene-c"      # l'item dont une course ULTERIEURE a abouti
FEATURE_A = "Le banc d'hygiene, item en cours"
FEATURE_B = "Le banc d'hygiene, item abandonne"
RAISON = "build-en-cours"
DETAIL = "un build ecrit encore apres 1800s (borne 1800s) : processus [n]inja en cours"
BUSY = "deploy-in-progress tenu par le constructeur"


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ")[:400]))


def charger(src: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


def before_blob(rel: str, marker: str) -> tuple[str, str]:
    """Le premier commit, en remontant, dont `rel` ne porte PAS `marker`."""
    try:
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "120",
                               "--", rel], capture_output=True, text=True,
                              timeout=60).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return "", ""
    for commit in hist:
        try:
            blob = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (commit, rel)],
                                  capture_output=True, text=True, timeout=60).stdout
        except (OSError, subprocess.SubprocessError):
            continue
        if blob and marker not in blob:
            return commit, blob
    return "", ""


# ===================================================================== semer un etat vrai ===
def faux_depot(root: Path) -> Path:
    """Un depot jetable qui porte un verrou de deploiement VIVANT : `proof_impossible.sh` lit
    le verrou du depot courant, et un pid qui repond rend « tenu depuis » mesurable."""
    d = root / "faux-depot"
    (d / ".autoport").mkdir(parents=True, exist_ok=True)
    (d / ".autoport" / ".deploy-in-progress").write_text(
        "banc pid=%d\n" % os.getpid(), encoding="utf-8")
    if not (d / ".git").exists():
        subprocess.run(["git", "init", "-q", "."], cwd=d, capture_output=True, timeout=60)
    return d


def semer(depot: Path, reports: Path, item_id: str, suffix: str = "",
          age_s: int = 0) -> Path:
    """Ecrit l'etat nomme AVEC LE VRAI SCRIPT. Rien n'est simule du cote producteur."""
    d = reports / item_id
    d.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["bash", str(AP / "lib" / "proof_impossible.sh"), str(d), item_id, suffix,
         RAISON, DETAIL, "1800", "1800", BUSY],
        cwd=depot, capture_output=True, text=True, timeout=120)
    # LE NOM VIENT DE L'AUTORITE, PAS D'UN `%s` RECOPIE : ce banc fabriquait le sien, et il
    # aurait fallu le corriger le jour ou l'extension change — trois bancs de plus a reparer.
    f = d / _NOMS.arm_name("impossible", suffix)
    if age_s and f.exists():
        t = time.time() - age_s
        os.utime(f, (t, t))
    return f


# ======================================================================= 1. LA PURGE ========
def axe_purge(root: Path, I_neuf, I_vieux) -> None:
    """Quatre etats semes, un seul doit rester : celui de l'AUTRE bras de l'item en cours."""
    depot = faux_depot(root)
    for tag, mod in (("apres", I_neuf), ("avant", I_vieux)):
        if mod is None:
            kv("pg_%s_ran" % tag, 0)
            continue
        reports = root / ("reports-pg-" + tag)
        reports.mkdir(parents=True, exist_ok=True)
        fa = semer(depot, reports, ITEM_A, "", age_s=1200)          # a purger : essai precedent
        fa_off = semer(depot, reports, ITEM_A, "-off", age_s=30)    # A LAISSER : l'autre bras
        fb = semer(depot, reports, ITEM_B, "", age_s=23880)         # a purger : item abandonne
        fc = semer(depot, reports, ITEM_C, "", age_s=600)           # a purger : course aboutie
        # Le nom de la preuve sort de l'AUTORITE : semee sous un autre nom, elle ne rendrait
        # aucun etat perime et la purge n'aurait rien a purger — un banc vert par inaction.
        (reports / ITEM_C / _NOMS.arm_name("proof", "")).write_text(
            "source=x86\nframes=13504\n", encoding="utf-8")
        avant_n = len(mod.scan(str(reports))) if hasattr(mod, "scan") else -1
        kv("pg_%s_seeded" % tag, sum(1 for f in (fa, fa_off, fb, fc) if f.exists()))
        kv("pg_%s_scan_avant" % tag, avant_n)
        kv("pg_%s_purge_fn" % tag, 1 if hasattr(mod, "purge") else 0)
        if not hasattr(mod, "purge"):
            # LE BRAS D'AVANT : il n'a pas de purge. Les quatre etats restent sur le disque,
            # et c'est exactement le defaut mesure.
            kv("pg_%s_ran" % tag, 1)
            kv("pg_%s_purged" % tag, 0)
            kv("pg_%s_standing" % tag, sum(1 for f in (fa, fa_off, fb, fc) if f.exists()))
            kv("pg_%s_fichiers_restants" % tag,
               sum(1 for f in (fa, fa_off, fb, fc) if f.exists()))
            kv("pg_%s_reasons" % tag, "-")
            kv("pg_%s_journal_lines" % tag, 0)
            continue
        r = mod.purge(str(reports), current_item=ITEM_A, current_suffix="",
                      since=time.time() - 60)
        kv("pg_%s_ran" % tag, 1)
        kv("pg_%s_purged" % tag, len(r["purged"]))
        kv("pg_%s_standing" % tag, len(r["standing"]))
        kv("pg_%s_reasons" % tag, ",".join(sorted(x["reason"] for x in r["purged"])) or "-")
        kv("pg_%s_standing_list" % tag,
           ",".join("%s%s" % (x["item"], x["suffix"]) for x in r["standing"]) or "-")
        # LE DISQUE, pas le dictionnaire rendu : ce qui reste, et ce qui est parti.
        kv("pg_%s_reste_autre_bras" % tag, 1 if fa_off.exists() else 0)
        kv("pg_%s_parti_meme_bras" % tag, 0 if fa.exists() else 1)
        kv("pg_%s_parti_item_abandonne" % tag, 0 if fb.exists() else 1)
        kv("pg_%s_parti_course_aboutie" % tag, 0 if fc.exists() else 1)
        kv("pg_%s_fichiers_restants" % tag,
           sum(1 for f in (fa, fa_off, fb, fc) if f.exists()))
        # LE JOURNAL DES PURGES : ce qu'on efface se raconte, sinon l'information disparait
        # une deuxieme fois.
        jn, par = mod.purge_counts(str(reports))
        kv("pg_%s_journal_lines" % tag, jn)
        kv("pg_%s_journal_reasons" % tag,
           ",".join("%s:%d" % (k, v) for k, v in sorted(par.items())) or "-")
        kv("pg_%s_journal_path" % tag,
           os.path.relpath(mod.purge_journal_path(str(reports)), root))
        # LE COMPTE D'ETATS DEBOUT, mesure a part : un zero ici se lit « rien en cours », et
        # le denominateur (`scan`) dit que quelque chose a bien ete regarde.
        kv("pg_%s_standing_apres" % tag, len(mod.standing(str(reports))))
        kv("pg_%s_scan_apres" % tag, len(mod.scan(str(reports))))
        # UNE DEUXIEME PURGE NE DOIT RIEN TROUVER : l'operation est idempotente.
        r2 = mod.purge(str(reports), current_item=ITEM_A, current_suffix="",
                       since=time.time() - 60)
        kv("pg_%s_purge2" % tag, len(r2["purged"]))
        # ... et SANS item courant, la purge ne retire que le PERIME : elle ne vide pas le
        # disque sous pretexte qu'on l'appelle.
        r3 = mod.purge(str(reports), current_item=None, current_suffix=None, since=0.0)
        kv("pg_%s_purge_sans_item" % tag, len(r3["purged"]))
        kv("pg_%s_reste_apres_purge_nue" % tag, 1 if fa_off.exists() else 0)


# ===================================================== 2. LE TEXTE RENDU A L'OWNER ==========
YAML = """version: 1
items:
- id: %s
  status: in-progress
  priority: 2
  feature: %s
  gate:
    key: impossible_hygiene_defects
    op: ==
    value: 0
- id: %s
  status: open
  priority: 1
  feature: %s
  gate:
    key: impossible_hygiene_defects
    op: ==
    value: 0
""" % (ITEM_A, FEATURE_A, ITEM_B, FEATURE_B)


def axe_statut(tag: str, root: Path, maison: Path, mod_impossible_src: Path,
               purge_dispo: bool) -> None:
    """Le MEME lecteur de statut, le MEME semis : seul le module de purge change.

    Le rendu est fait par `lib/backlog.py` du disque dans les DEUX bras — la difference
    mesuree est la PURGE, jamais le renderer.
    """
    maison.mkdir(parents=True, exist_ok=True)
    (maison / "lib").mkdir(parents=True, exist_ok=True)
    reports = maison / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    (maison / "backlog.yaml").write_text(YAML, encoding="utf-8")
    shutil.copyfile(mod_impossible_src, maison / "lib" / "impossible.py")
    shutil.copyfile(AP / "lib" / "backlog.py", maison / "lib" / "backlog.py")
    bl = charger(maison / "lib" / "backlog.py", "bl_hyg_" + tag)
    bl.DIGEST_MEMO = str(maison / ".last_status_digest")       # JAMAIS celui de l'owner
    mod = charger(maison / "lib" / "impossible.py", "imp_hyg_" + tag)

    depot = faux_depot(root)
    f_b = semer(depot, reports, ITEM_B, "", age_s=23880)   # l'item ABANDONNE, 6 h 38
    f_a = semer(depot, reports, ITEM_A, "")               # l'item EN COURS, a l'instant

    avant = bl.load(maison / "backlog.yaml").status_report()
    kv("%s_avant_has_section" % tag, 1 if "## Preuve impossible" in avant else 0)
    kv("%s_avant_names_abandonne" % tag, 1 if FEATURE_B in avant else 0)
    kv("%s_avant_names_en_cours" % tag, 1 if FEATURE_A in avant else 0)
    kv("%s_avant_len" % tag, len(avant))

    kv("%s_purge_fn" % tag, 1 if hasattr(mod, "purge") else 0)
    purges = 0
    if purge_dispo and hasattr(mod, "purge"):
        r = mod.purge(str(reports), current_item=ITEM_A, current_suffix=None,
                      since=time.time() - 300)
        purges = len(r["purged"])
    kv("%s_purges" % tag, purges)

    apres = bl.load(maison / "backlog.yaml").status_report()
    kv("%s_ran" % tag, 1)
    kv("%s_apres_has_section" % tag, 1 if "## Preuve impossible" in apres else 0)
    kv("%s_apres_names_abandonne" % tag, 1 if FEATURE_B in apres else 0)
    kv("%s_apres_names_en_cours" % tag, 1 if FEATURE_A in apres else 0)
    kv("%s_apres_len" % tag, len(apres))
    kv("%s_delta_len" % tag, len(apres) - len(avant))
    kv("%s_fichier_abandonne_reste" % tag, 1 if f_b.exists() else 0)
    kv("%s_fichier_en_cours_reste" % tag, 1 if f_a.exists() else 0)
    bloc = ""
    if "## Preuve impossible" in apres:
        bloc = apres[apres.index("## Preuve impossible"):].split("\n\n")[0]
    kv("%s_texte_apres" % tag, bloc.replace("\n", " | ")[:300] or "-")
    bloc = ""
    if "## Preuve impossible" in avant:
        bloc = avant[avant.index("## Preuve impossible"):].split("\n\n")[0]
    kv("%s_texte_avant" % tag, bloc.replace("\n", " | ")[:300] or "-")


# ============================================================== 3. LES NOMS, PAR BRAS =======
GARDE_DEBUT = "WAITNAME=$(python3"
GARDE_FIN = "log \"attente de ce bras publiee"


def nom_ecrit_par_le_script(suffix: str) -> str:
    """Le nom que `lib/proof_run.sh` ECRIT, obtenu en EVALUANT sa propre expression.

    On ne recopie pas le nom ici : on prend la ligne de redirection du script, on en garde la
    cible, et on la fait evaluer par bash avec `D` et `SUF` poses. Un banc qui reecrirait le
    nom mesurerait sa propre recopie.

    L'ENVIRONNEMENT DE L'EVALUATION EST CELUI DU SCRIPT (12/09). `proof_run.sh` ne fabrique
    plus aucun nom : il `eval`-ue au prologue ce que `lib/impossible.py names` lui rend. Poser
    seulement `D` et `SUF` laissait donc `$AP_NAME_wait` vide, et ce banc aurait accuse le
    script d'ecrire un fichier sans nom. On rejoue le MEME prologue, par le MEME appel.
    ET LA MESURE RESTE FALSIFIABLE : si le script re-fabriquait `proof-wait.txt` en dur, le
    bras d'ablation rendrait `proof-wait.txt` la ou l'autorite dit `proof-off-wait.txt`, et
    `nm_ablation_egal` tomberait a 0.
    """
    src = (AP / "lib" / "proof_run.sh").read_text(encoding="utf-8")
    cible = ""
    for line in src.splitlines():
        t = line.strip()
        if t.startswith("} >") and "wait" in t:
            cible = t.split(">", 1)[1].strip()
            break
    if not cible:
        return ""
    prologue = 'eval "$(python3 %s names \'%s\')"; ' % (
        _sq(str(AP / "lib" / "impossible.py")), suffix)
    r = subprocess.run(["bash", "-c",
                        '%sD=.; SUF="%s"; printf "%%s" %s' % (prologue, suffix, cible)],
                       capture_output=True, text=True, timeout=60)
    return os.path.basename(r.stdout.strip())


def axe_noms(root: Path, I_neuf) -> None:
    for suf, arm in (("", "livre"), ("-off", "ablation")):
        ecrit = nom_ecrit_par_le_script(suf)
        lu = I_neuf.arm_name("wait", suf)
        kv("nm_%s_ecrit" % arm, ecrit or "-")
        kv("nm_%s_lu" % arm, lu or "-")
        kv("nm_%s_egal" % arm, 1 if (ecrit and ecrit == lu) else 0)
        kv("nm_%s_etat_lu" % arm, os.path.basename(I_neuf.state_path("r", "i", suf)))

    # LA GARDE DE COURSE, EXERCEE DANS LES DEUX SENS. On extrait le texte REEL de la garde de
    # `lib/proof_run.sh` — jamais une reecriture — et on le joue sur un dossier ou le fichier
    # porte le bon nom, puis sur un dossier ou il porte un autre nom.
    src = (AP / "lib" / "proof_run.sh").read_text(encoding="utf-8").splitlines()
    d0 = next((i for i, l in enumerate(src) if l.startswith(GARDE_DEBUT)), -1)
    d1 = next((i for i, l in enumerate(src) if GARDE_FIN in l), -1)
    kv("nm_garde_trouvee", 1 if 0 <= d0 <= d1 else 0)
    if not (0 <= d0 <= d1):
        return
    garde = "\n".join(src[d0:d1 + 1])
    kv("nm_garde_lignes", d1 - d0 + 1)
    # Le cas « divergent » n'est pas invente : c'est EXACTEMENT le defaut du 12/09 — le bras
    # d'ablation ecrit son attente pendant que le fichier porte le nom du bras LIVRE.
    for cas, nom in (("bon", I_neuf.arm_name("wait", "-off")),
                     ("divergent", I_neuf.arm_name("wait", ""))):
        d = root / ("garde-" + cas)
        d.mkdir(parents=True, exist_ok=True)
        (d / nom).write_text("proof_wait_s=0\n", encoding="utf-8")
        # LE PROLOGUE DU SCRIPT FAIT PARTIE DE SON ENVIRONNEMENT. `proof_run.sh` ne fabrique
        # plus aucun nom : il `eval`-ue au prologue ce que l'autorite lui rend, et la garde
        # compare ce qu'elle a recu a ce que l'autorite redonne. Rejouer la garde sans ce
        # prologue laisse `$AP_NAME_wait` non lie, et `set -u` tue le bac a sable avant que la
        # garde n'ait rien juge : on mesurerait un banc casse, pas une garde.
        script = ('set -uo pipefail\nAP=%s\nD=%s\nSUF=-off\nID=banc\n'
                  'eval "$(python3 "$AP/lib/impossible.py" names "$SUF")"\n'
                  'log(){ :; }\ndie3(){ printf "DIE3 %%s\\n" "$1" >&2; exit 9; }\n%s\n'
                  'exit 0\n' % (str(AP), str(d), garde))
        r = subprocess.run(["bash", "-c", script], capture_output=True, text=True, timeout=120)
        kv("nm_garde_%s_rc" % cas, r.returncode)
        kv("nm_garde_%s_die3" % cas, 1 if "DIE3" in r.stderr else 0)

    # PLUS AUCUN NOM D'ATTENTE CODE EN DUR CHEZ LES LECTEURS. On compte les LITTERAUX cites
    # dans du code (entre quotes), jamais les mentions en prose d'un commentaire.
    # LE MOTIF CHERCHE EST CONSTRUIT PAR L'AUTORITE, jamais ecrit ici : un auditeur qui cite
    # le litteral qu'il traque se compte lui-meme.
    nom_dur = I_neuf.arm_name("wait", "")
    durs = []
    for p in sorted(list((AP / "lib" / "census").glob("*.sh")) + list((AP / "lib").glob("*.py"))):
        if p.name == "impossible.py":
            continue
        txt = p.read_text(encoding="utf-8", errors="replace")
        n = txt.count("'%s'" % nom_dur) + txt.count('"%s"' % nom_dur)
        if n:
            durs.append("%s:%d" % (p.name, n))
    kv("nm_lecteurs_en_dur", len(durs))
    kv("nm_lecteurs_en_dur_liste", ",".join(durs) or "-")


# ==================================================================== 4. LE JOURNAL =========
VALIDATEUR_IMPOSSIBLE = (
    # NOM-LITTERAL-ATTENDU: message-du-juge-pas-un-chemin
    "[{iid} FAIL] proof.txt absent ou vide. Produis-le : "
    ".autoport/lib/proof_run.sh {iid} x86\n"
    "[{iid} FAIL] 1 constat(s) ci-dessus, aucun n'a ete masque par un autre.\n")
VALIDATEUR_ORDINAIRE = (
    "[{iid} FAIL] frames=12 sous le seuil 300 : rien n'a ete dessine assez longtemps\n"
    "[{iid} FAIL] 1 constat(s) ci-dessus, aucun n'a ete masque par un autre.\n")


def premiere_ligne(p: Path) -> str:
    try:
        return next((l for l in p.read_text(errors="replace").splitlines() if l.strip()), "")
    except OSError:
        return ""


def axe_journal(root: Path, O_neuf, blob_vieux: str) -> None:
    """Deux journaux SEMES : l'impossible (a requalifier) et l'echec ORDINAIRE (a laisser)."""
    st = {"reason": RAISON, "detail": DETAIL, "arm": "livre", "since_s": 23880,
          "lock_pid": str(os.getpid()), "lock_held_s": 23940}
    raison_porte = ("CLOSE-GATE/preuve-impossible: aucune preuve n'etait possible pour cet "
                    "essai — %s (%s)." % (RAISON, DETAIL))
    dit = "essai CLASSE A PART, NON COMPTE : la preuve etait IMPOSSIBLE."

    # --- LE BRAS D'APRES : le vrai code du disque.
    d = root / "journal-apres"
    d.mkdir(parents=True, exist_ok=True)
    j_imp = d / "validator-001.txt"
    j_ord = d / "validator-002.txt"
    j_imp.write_text(VALIDATEUR_IMPOSSIBLE.format(iid=ITEM_A), encoding="utf-8")
    j_ord.write_text(VALIDATEUR_ORDINAIRE.format(iid=ITEM_A), encoding="utf-8")
    ord_avant = j_ord.read_bytes()
    kv("jl_apres_fn", 1 if hasattr(O_neuf, "ecrire_journal_impossible") else 0)
    kv("jl_apres_detecteur", 1 if hasattr(O_neuf, "journal_contredit") else 0)
    if hasattr(O_neuf, "ecrire_journal_impossible"):
        kv("jl_apres_contredisait",
           O_neuf.ecrire_journal_impossible(j_imp, st, raison_porte, dit))
        texte = j_imp.read_text(encoding="utf-8")
        l1 = premiere_ligne(j_imp)
        kv("jl_apres_ran", 1)
        kv("jl_apres_l1_dit_impossible", 1 if "PREUVE IMPOSSIBLE" in l1 else 0)
        kv("jl_apres_l1_dit_absent", 1 if "absent ou vide" in l1 else 0)
        kv("jl_apres_l1_nomme_cause", 1 if RAISON in l1 else 0)
        kv("jl_apres_l1_nomme_age", 1 if "6 h 38" in l1 else 0)
        kv("jl_apres_l1", l1[:300])
        # LE TEXTE DU VALIDATEUR EST INTACT : on ne masque pas son constat, on cesse de le
        # laisser en tete. Le verdict de la porte et la requalification y sont aussi.
        kv("jl_apres_corps_intact",
           # NOM-LITTERAL-ATTENDU: message-du-juge-pas-un-chemin
           1 if "proof.txt absent ou vide" in texte else 0)
        kv("jl_apres_porte_presente", 1 if raison_porte[:40] in texte else 0)
        kv("jl_apres_dit_present", 1 if dit[:30] in texte else 0)
        kv("jl_apres_contredit_maintenant",
           1 if O_neuf.journal_contredit(texte) else 0)
        # LE CONTROLE A LAISSER : un echec ORDINAIRE n'est ni accuse, ni touche.
        kv("jl_apres_ordinaire_accuse",
           1 if O_neuf.journal_contredit(j_ord.read_text(encoding="utf-8")) else 0)
        kv("jl_apres_ordinaire_intact", 1 if j_ord.read_bytes() == ord_avant else 0)
    else:
        kv("jl_apres_ran", 0)

    # --- LE BRAS D'AVANT : son code AJOUTAIT a la fin. On verifie que le site d'ajout existe
    # dans le blob d'avant (sinon le temoin est une invention), puis on refait ce geste.
    site = 'f.write("\\n\\n" + gate_reason + "\\n\\n" + dit + "\\n")'
    kv("jl_avant_site_append", 1 if (blob_vieux and site in blob_vieux) else 0)
    kv("jl_avant_fn", 1 if (blob_vieux and "ecrire_journal_impossible" in blob_vieux) else 0)
    d = root / "journal-avant"
    d.mkdir(parents=True, exist_ok=True)
    j = d / "validator-001.txt"
    j.write_text(VALIDATEUR_IMPOSSIBLE.format(iid=ITEM_A), encoding="utf-8")
    with j.open("a", encoding="utf-8") as fh:
        fh.write("\n\n" + raison_porte + "\n\n" + dit + "\n")
    l1 = premiere_ligne(j)
    kv("jl_avant_ran", 1)
    kv("jl_avant_l1_dit_impossible", 1 if "PREUVE IMPOSSIBLE" in l1 else 0)
    kv("jl_avant_l1_dit_absent", 1 if "absent ou vide" in l1 else 0)
    kv("jl_avant_l1", l1[:300])
    if hasattr(O_neuf, "journal_contredit"):
        kv("jl_avant_contredit", 1 if O_neuf.journal_contredit(j.read_text()) else 0)

    # --- LES JOURNAUX DE CE DEPOT, MAINTENANT : le compte de ceux dont les deux lignes se
    # contredisaient. Publie, jamais compte dans le verdict : c'est de l'HISTOIRE, et un
    # chantier ne peut pas reecrire les journaux d'hier.
    vus = contredits = 0
    for p in sorted((AP / "logs").glob("*/validator-*.txt")):
        try:
            txt = p.read_text(errors="replace")
        except OSError:
            continue
        vus += 1
        l1 = next((l for l in txt.splitlines() if l.strip()), "")
        if "absent ou vide" in l1 and "PREUVE IMPOSSIBLE" not in l1 and (
                "preuve était IMPOSSIBLE" in txt or "preuve-impossible" in txt):
            contredits += 1
    kv("jl_depot_journaux", vus)
    kv("jl_depot_contredits", contredits)


# ================================================================ LES TEMOINS DE SOURCE =====
def temoins_source() -> None:
    orch = (AP / "orchestrator.py").read_text(encoding="utf-8")
    imp = (AP / "lib" / "impossible.py").read_text(encoding="utf-8")
    pr = (AP / "lib" / "proof_run.sh").read_text(encoding="utf-8")
    kv("src_marker_purge", 1 if MARKER_PURGE in imp else 0)
    kv("src_marker_nom", 1 if MARKER_NOM in imp else 0)
    kv("src_marker_journal", 1 if MARKER_JOURNAL in orch else 0)
    kv("src_purete_arbre_retiree", 1)   # le compte de tests de proprete retires de CE banc
    # LA PURGE EST APPELEE AU POINT DE PRODUCTION : l'orchestrateur au changement d'item, et
    # le producteur de preuve au debut de chaque course.
    kv("src_orch_appelle_purge", orch.count("impossible_state.purge("))
    kv("src_proof_run_appelle_purge", pr.count('impossible.py" purge'))
    kv("src_proof_run_derive_nom", pr.count('impossible.py" name wait'))
    kv("src_orch_ecrit_journal", orch.count("ecrire_journal_impossible("))
    # LE TEST DE PROPRETE D'ARBRE EST RETIRE (signalement 5 du 12/09). `src_detection_intacte`
    # affirmait `git diff --quiet HEAD -- lib/proof_impossible.sh` : un recensement rougissait
    # donc pour TOUT chantier qui touche ce fichier, pour une raison qui n'etait pas la sienne.
    # La proprete de l'arbre et le perimetre sont le travail des PORTES de l'orchestrateur
    # (GATE 0 et GATE 1, qui lisent `code_scope`), pas d'un instrument de mesure.
    r = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--",
                        "game/", "common/", "android/", "goal_src/", "goalc/"],
                       capture_output=True, text=True, timeout=120)
    sales = [x[3:] for x in r.stdout.splitlines() if x.strip()]
    kv("src_engine_dirty", len(sales))
    kv("src_engine_dirty_list", ",".join(sales[:12]) or "-")


# ===================================================================================== main =
def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="hyg-banc-"))
    try:
        c_imp, b_imp = before_blob(".autoport/lib/impossible.py", MARKER_PURGE)
        c_orch, b_orch = before_blob(".autoport/orchestrator.py", MARKER_JOURNAL)
        kv("before_impossible_commit", c_imp[:12] or "-")
        kv("before_orch_commit", c_orch[:12] or "-")
        kv("before_impossible_marker_absent",
           1 if (b_imp and MARKER_PURGE not in b_imp) else 0)
        kv("before_orch_marker_absent", 1 if (b_orch and MARKER_JOURNAL not in b_orch) else 0)
        kv("marker_impossible_live", 1 if MARKER_PURGE in
           (AP / "lib" / "impossible.py").read_text(encoding="utf-8") else 0)
        kv("marker_orch_live", 1 if MARKER_JOURNAL in
           (AP / "orchestrator.py").read_text(encoding="utf-8") else 0)

        vieux_imp = None
        if b_imp:
            vieux_imp = root / "vieux_impossible.py"
            vieux_imp.write_text(b_imp, encoding="utf-8")

        I_neuf = charger(AP / "lib" / "impossible.py", "imp_neuf")
        I_vieux = charger(vieux_imp, "imp_vieux") if vieux_imp else None
        sys.path.insert(0, str(AP))
        O_neuf = charger(AP / "orchestrator.py", "orch_neuf_hyg")

        axe_purge(root, I_neuf, I_vieux)
        axe_statut("st_apres", root, root / "maison-apres", AP / "lib" / "impossible.py", True)
        if vieux_imp:
            axe_statut("st_avant", root, root / "maison-avant", vieux_imp, False)
        axe_noms(root, I_neuf)
        axe_journal(root, O_neuf, b_orch)
        temoins_source()

        for rel in ("orchestrator.py", "lib/impossible.py", "lib/proof_run.sh",
                    "lib/proof_impossible.sh", "lib/backlog.py",
                    "lib/impossible_hygiene_selftest.py"):
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
