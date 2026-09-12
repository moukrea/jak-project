#!/usr/bin/env python3
"""lib/single_namer_selftest.py — LE BANC de `harness-impossible-single-namer`.

CE QU'IL MESURE, dans l'ordre des QUATRE points du livrable :

  1. NOMS     l'ECRIVAIN (`lib/proof_impossible.sh`) et le LECTEUR (`lib/impossible.py`)
              derivent le nom du MEME endroit, sur LES DEUX BRAS — livre et ablation. Le nom
              ECRIT n'est pas recopie ici : on lance le vrai script dans un dossier jetable et
              on regarde le fichier qu'il a POSE. La garde est exercee dans les deux sens :
              autorite presente -> il ecrit ; autorite injoignable -> il n'ecrit RIEN.
  2. JUGE     la sortie de `validators/generic.sh` ne commence plus par un diagnostic que la
              porte va contredire. Mesure sur un etat SEME, le VRAI juge lance, et le juge
              d'AVANT ce chantier lance sur LE MEME semis. Le nombre de constats doit etre
              IDENTIQUE des deux cotes : nommer la cause n'assouplit rien.
  3. JOURNAL  le journal des purges a UN seul ecrivain et une BORNE. Le compteur de sites
              d'ecriture est verifie par un CONTROLE NEGATIF (un faux ecrivain seme doit le
              faire monter a 2), la borne par le bras d'AVANT qui, lui, grandit sans fin.
  4. TEXTE    un etat debout sur un item `validated` — ou sur un id qui n'est plus au backlog
              du tout — figure dans le texte RENDU. Bras d'AVANT : le backlog.py d'avant ce
              chantier, ancre par MARQUEUR et jamais par `HEAD:`, sur le MEME semis.

LES ETATS SONT TOUJOURS SEMES PAR LE VRAI PRODUCTEUR. Rien n'est fabrique a la main du cote
ecrivain : un banc qui ecrirait lui-meme le fichier mesurerait sa propre recopie.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; `lib/census/harness-impossible-single-namer.sh` fait la somme.
"""
from __future__ import annotations

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

# Les marqueurs qui datent CE chantier, un par fichier touche. Le temoin d'AVANT remonte au
# premier commit ou le marqueur est ABSENT : lu a `HEAD:`, il s'accuserait lui-meme des le
# commit, et le bras d'avant deviendrait une copie du bras d'apres.
MARKER_WRITER = "NOMMAGE/ecrivain-derive"      # lib/proof_impossible.sh
MARKER_VALIDATOR = "NOMMAGE/premiere-ligne"    # validators/generic.sh
MARKER_BACKLOG = "NOMMAGE/tous-les-items"      # lib/backlog.py
MARKER_JOURNAL = "JOURNAL/un-seul-ecrivain"    # lib/impossible.py
MARKER_RUN = "ETAT NOMME NON ECRIT"            # lib/proof_run.sh

SEED_IMP = "zzz-banc-namer-impossible"         # l'item SEME dont la preuve etait impossible
SEED_ORD = "zzz-banc-namer-ordinaire"          # l'item SEME dont l'echec est ORDINAIRE
ITEM_CUR = "zzz-banc-namer-en-cours"
ITEM_VAL = "zzz-banc-namer-valide"
ITEM_GHOST = "zzz-banc-namer-fantome"
FEATURE_CUR = "Le banc du nommeur, item en cours"
FEATURE_VAL = "Le banc du nommeur, item deja valide"
RAISON = "verrou-de-deploiement"
DETAIL = "deploy-in-progress tenu depuis 23880s (borne 1800s) par le constructeur"
BUSY = "constructeur-arm64"


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
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "200",
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


def premiere(texte: str) -> str:
    return next((l for l in (texte or "").splitlines() if l.strip()), "")


def constats(texte: str) -> int:
    """Le nombre de constats que le juge a accumules, lu dans SA ligne de cloture."""
    m = re.search(r"\] (\d+) constat\(s\)", texte or "")
    return int(m.group(1)) if m else -1


# =============================================================== 1. LES NOMS, PAR BRAS ======
def faux_depot(root: Path) -> Path:
    d = root / "faux-depot"
    (d / ".autoport").mkdir(parents=True, exist_ok=True)
    (d / ".autoport" / ".deploy-in-progress").write_text(
        "banc pid=%d\n" % os.getpid(), encoding="utf-8")
    if not (d / ".git").exists():
        subprocess.run(["git", "init", "-q", "."], cwd=d, capture_output=True, timeout=60)
    return d


def lancer_ecrivain(script: Path, depot: Path, dest: Path, suffix: str,
                    sans_python: bool = False):
    """Lance l'ecrivain — celui du disque ou celui d'AVANT — et rend (rc, fichiers poses)."""
    dest.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    if sans_python:
        # L'AUTORITE INJOIGNABLE, sans toucher une ligne du script : un `python3` en TETE de
        # PATH qui refuse. Vider PATH emporterait `sed`, `date`, `bash` : on mesurerait une
        # machine cassee, pas un nommeur prive de son autorite.
        faux = dest.parent / "path-sans-python"
        faux.mkdir(parents=True, exist_ok=True)
        stub = faux / "python3"
        stub.write_text("#!/bin/sh\necho 'banc: autorite injoignable' >&2\nexit 127\n",
                        encoding="utf-8")
        stub.chmod(0o755)
        env["PATH"] = "%s:%s" % (faux, env.get("PATH", ""))
    r = subprocess.run(["bash", str(script), str(dest), "banc", suffix, RAISON, DETAIL,
                        "23880", "1800", BUSY],
                       cwd=depot, capture_output=True, text=True, timeout=120, env=env)
    poses = sorted(p.name for p in dest.iterdir() if p.is_file())
    return r.returncode, poses


def axe_noms(root: Path, I, blob_avant: str) -> None:
    depot = faux_depot(root)
    ecrivain = AP / "lib" / "proof_impossible.sh"

    for suf, arm in (("", "livre"), ("-off", "ablation")):
        rc, poses = lancer_ecrivain(ecrivain, depot, root / ("nom-apres-" + (arm)), suf)
        ecrit = poses[0] if len(poses) == 1 else ("-" if not poses else "+".join(poses))
        lu = I.arm_name("impossible", suf)
        kv("nm_%s_rc" % arm, rc)
        kv("nm_%s_fichiers" % arm, len(poses))
        kv("nm_%s_ecrit" % arm, ecrit)
        kv("nm_%s_lu" % arm, lu)
        kv("nm_%s_egal" % arm, 1 if (len(poses) == 1 and ecrit == lu) else 0)
        # L'ETAT LUI-MEME N'A PAS BOUGE : les douze cles y sont, lues par l'AUTORITE.
        corps = ""
        p = root / ("nom-apres-" + arm) / lu
        if p.exists():
            corps = p.read_text(encoding="utf-8", errors="replace")
        d = I.parse(corps)
        kv("nm_%s_cles" % arm, sum(1 for k in I.KEYS if k in d))
        kv("nm_%s_raison" % arm, d.get("proof_impossible_reason") or "-")
        # ... ET LE LECTEUR LE RETROUVE. Le nom ecrit ne vaut que s'il se relit.
        faux_reports = root / ("relu-" + arm)
        (faux_reports / "banc").mkdir(parents=True, exist_ok=True)
        if p.exists():
            shutil.copyfile(p, faux_reports / "banc" / p.name)
        st = I.read(str(faux_reports), "banc")
        kv("nm_%s_relu" % arm, 1 if st else 0)
        kv("nm_%s_relu_bras" % arm, (st or {}).get("arm", "-"))

    # LA GARDE, DANS LES DEUX SENS. Autorite injoignable : le script d'APRES refuse et ne pose
    # RIEN ; celui d'AVANT pose quand meme un fichier qu'il a nomme tout seul. C'est la
    # difference de COMPORTEMENT, pas une difference de texte.
    rc, poses = lancer_ecrivain(ecrivain, depot, root / "garde-apres", "-off",
                                sans_python=True)
    kv("nm_garde_apres_rc", rc)
    kv("nm_garde_apres_fichiers", len(poses))
    if blob_avant:
        vieux = root / "ecrivain-avant.sh"
        vieux.write_text(blob_avant, encoding="utf-8")
        rc, poses = lancer_ecrivain(vieux, depot, root / "garde-avant", "-off",
                                    sans_python=True)
        kv("nm_garde_avant_rc", rc)
        kv("nm_garde_avant_fichiers", len(poses))
        kv("nm_garde_avant_pose", poses[0] if len(poses) == 1 else "-")
        rc, poses = lancer_ecrivain(vieux, depot, root / "nom-avant", "-off")
        kv("nm_avant_rc", rc)
        kv("nm_avant_ecrit", poses[0] if len(poses) == 1 else "-")
        kv("nm_avant_demande_autorite", 1 if "impossible.py" in blob_avant else 0)
        # LES CLES ECRITES N'ONT PAS CHANGE : seul l'ORIGINE du nom a change, jamais l'etat.
        kv("nm_avant_cles_texte",
           sum(1 for k in I.KEYS if ("%s=" % k) in blob_avant))
    else:
        kv("nm_garde_avant_rc", -1)
        kv("nm_garde_avant_fichiers", -1)
        kv("nm_avant_demande_autorite", -1)

    src = ecrivain.read_text(encoding="utf-8")
    kv("nm_apres_demande_autorite", src.count('impossible.py" name impossible'))
    kv("nm_apres_cles_texte", sum(1 for k in I.KEYS if ("%s=" % k) in src))
    # PLUS UN SEUL NOM D'ETAT FABRIQUE PAR L'ECRIVAIN. Le litteral cherche est CONSTRUIT par
    # l'autorite : un auditeur qui cite le nom qu'il traque se compte lui-meme.
    motif = I.KINDS["impossible"]
    kv("nm_ecrivain_litteral", src.count('proof$SUF%s' % motif))
    # Les AUTRES sites du depot qui citent encore un nom d'etat en dur : publies, listes, JAMAIS
    # comptes dans le verdict — ils sont hors du perimetre de cet item, et ils partent en
    # signalement. Un chantier qui les corrigerait casserait le temoin epingle d'un autre item.
    autres = []
    for p in sorted(list((AP / "lib").rglob("*.py")) + list((AP / "lib").rglob("*.sh"))
                    + list((AP / "validators").glob("*.sh"))):
        if p.name in ("impossible.py", "proof_impossible.sh", HERE.name):
            continue
        txt = p.read_text(encoding="utf-8", errors="replace")
        n = txt.count(motif)
        if n:
            autres.append("%s:%d" % (p.relative_to(AP), n))
    kv("nm_autres_litteraux", len(autres))
    kv("nm_autres_litteraux_liste", ",".join(autres) or "-")


# ============================================================ 2. LA SORTIE DU JUGE ==========
def lancer_juge(script: Path, item_id: str) -> tuple[int, str]:
    env = dict(os.environ, AUTOPORT_PHASE_ID=item_id)
    r = subprocess.run(["bash", str(script)], cwd=str(REPO), capture_output=True,
                       text=True, timeout=600, env=env)
    return r.returncode, (r.stdout or "") + (r.stderr or "")


def axe_juge(root: Path, I, O, blob_avant: str) -> None:
    """Le semis vit dans les VRAIS reports : le juge y va tout seul, il ne se laisse pas
    rediriger. Il en repart au `finally` de `main`."""
    reports = AP / "reports"
    depot = faux_depot(root)
    dimp = reports / SEED_IMP
    dord = reports / SEED_ORD
    for d in (dimp, dord):
        shutil.rmtree(d, ignore_errors=True)
        d.mkdir(parents=True, exist_ok=True)
    # L'ETAT SEME par le vrai producteur, et AUCUN proof.txt a cote : c'est exactement ce que
    # le juge voit quand la machine n'etait pas mesurable.
    subprocess.run(["bash", str(AP / "lib" / "proof_impossible.sh"), str(dimp), SEED_IMP, "",
                    RAISON, DETAIL, "23880", "1800", BUSY],
                   cwd=depot, capture_output=True, text=True, timeout=120)
    seme = dimp / I.arm_name("impossible", "")
    if seme.exists():
        t = time.time() - 23880                    # 6 h 38, l'ordre de grandeur du 12/09
        os.utime(seme, (t, t))
    kv("vl_semis_etat", 1 if seme.exists() else 0)
    kv("vl_semis_lu", 1 if I.read(str(reports), SEED_IMP) else 0)
    # LE CONTROLE A LAISSER : un echec ORDINAIRE. proof.txt est la, aucun etat nomme a cote.
    # Sa date est ancienne : le juge doit trouver sa premiere source « plus recente » tout de
    # suite, sinon il parcourt tout l'arbre moteur pour rien.
    # Le nom de la preuve sort de l'autorite, comme l'etat seme juste au-dessus : un controle
    # ecrit sous un nom que le juge n'ouvre pas rendrait « absent » et se lirait comme un succes.
    pf = dord / I.arm_name("proof", "")
    pf.write_text("source=x86\nframes=12\ncrash=0\nbinary=build/game/gk\n", encoding="utf-8")
    os.utime(pf, (1_000_000_000, 1_000_000_000))

    rc, txt = lancer_juge(AP / "validators" / "generic.sh", SEED_IMP)
    l1 = premiere(txt)
    kv("vl_apres_ran", 1)
    kv("vl_apres_rc", rc)
    kv("vl_apres_l1", l1[:300])
    kv("vl_apres_l1_dit_impossible", 1 if "PREUVE IMPOSSIBLE" in l1 else 0)
    kv("vl_apres_l1_dit_absent", 1 if "absent ou vide" in l1 else 0)
    kv("vl_apres_l1_nomme_cause", 1 if RAISON in l1 else 0)
    kv("vl_apres_l1_nomme_age", 1 if "6 h 38" in l1 else 0)
    # NOM-LITTERAL-ATTENDU: message-du-juge-pas-un-chemin
    kv("vl_apres_corps_intact", 1 if "proof.txt absent ou vide" in txt else 0)
    kv("vl_apres_constats", constats(txt))
    kv("vl_apres_contredit", 1 if O.journal_contredit(txt) else 0)

    rc, txt = lancer_juge(AP / "validators" / "generic.sh", SEED_ORD)
    l1o = premiere(txt)
    kv("vl_ordinaire_rc", rc)
    kv("vl_ordinaire_l1", l1o[:300])
    kv("vl_ordinaire_l1_dit_impossible", 1 if "PREUVE IMPOSSIBLE" in l1o else 0)
    kv("vl_ordinaire_contredit", 1 if O.journal_contredit(txt) else 0)

    if blob_avant:
        vieux = root / "juge-avant.sh"
        vieux.write_text(blob_avant, encoding="utf-8")
        rc, txt = lancer_juge(vieux, SEED_IMP)
        l1a = premiere(txt)
        kv("vl_avant_ran", 1)
        kv("vl_avant_rc", rc)
        kv("vl_avant_l1", l1a[:300])
        kv("vl_avant_l1_dit_impossible", 1 if "PREUVE IMPOSSIBLE" in l1a else 0)
        kv("vl_avant_l1_dit_absent", 1 if "absent ou vide" in l1a else 0)
        kv("vl_avant_constats", constats(txt))
        kv("vl_avant_contredit", 1 if O.journal_contredit(txt) else 0)
    else:
        kv("vl_avant_ran", 0)


# ================================================================== 3. LE JOURNAL ===========
# UN SITE D'ECRITURE = une variable qui recoit le chemin du journal, puis un `open` en ajout
# ou en ecriture SUR CETTE VARIABLE. Lu ainsi, un lecteur (`open(path)` sans mode) ne compte
# pas, et le verrou — un AUTRE fichier — non plus. Le compteur est verifie par un controle
# negatif : un faux ecrivain seme doit le faire monter.
_ASSIGN = re.compile(r"^\s*(\w+)\s*=\s*.*purge_journal_path\(", re.M)
_LITT = re.compile(r"^\s*(\w+)\s*=\s*.*impossible-purges\.log", re.M)


def sites_ecriture(fichiers) -> list:
    out = []
    for p in fichiers:
        try:
            txt = Path(p).read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        noms = set(_ASSIGN.findall(txt)) | set(_LITT.findall(txt))
        n = 0
        for nom in sorted(noms):
            n += len(re.findall(r"open\(\s*%s\s*,\s*[\"'][aw]" % re.escape(nom), txt))
            n += len(re.findall(r">>?\s*\"?\$\{?%s\b" % re.escape(nom), txt))
        n += len(re.findall(r"open\(\s*purge_journal_path\([^)]*\)\s*,\s*[\"'][aw]", txt))
        if n:
            out.append("%s:%d" % (Path(p).name, n))
    return out


def fichiers_du_harnais() -> list:
    hors = {"logs", "reports", "archive", "backups", "tmp", "scratch", "dist", "gold",
            "codex", "__pycache__", "refset", "refset-candidates", "refset-origine-pure",
            "refset-unify", "cgo-cache", "demos", "assets", "report_blocks"}
    out = []
    for p in sorted(AP.rglob("*")):
        if p.suffix not in (".py", ".sh") or not p.is_file():
            continue
        if any(part in hors for part in p.relative_to(AP).parts):
            continue
        out.append(p)
    return out


def enregistrements(n, item="zzz-banc", why="changement-d-item"):
    return [{"item": "%s-%d" % (item, i), "arm": "livre", "suffix": "",
             # NOM-LITTERAL-ATTENDU: champ-de-faux-enregistrement-de-journal
             "file": "%s-%d/proof-impossible.txt" % (item, i), "age_s": 120 + i,
             "reason": why, "cause": "verrou-de-deploiement"} for i in range(n)]


def axe_journal(root: Path, I, blob_avant: str) -> None:
    # --- LES SITES D'ECRITURE DU DEPOT, et le controle negatif du compteur.
    vus = sites_ecriture(fichiers_du_harnais())
    kv("jn_sites", sum(int(x.split(":")[1]) for x in vus))
    kv("jn_sites_liste", ",".join(vus) or "-")
    faux = root / "faux-ecrivain"
    faux.mkdir(parents=True, exist_ok=True)
    (faux / "faux_ecrivain.py").write_text(
        "import impossible as I\n"
        "def go(r):\n"
        "    chemin = I.purge_journal_path(r)\n"
        '    with open(chemin, "a", encoding="utf-8") as fh:\n'
        '        fh.write("triche\\n")\n', encoding="utf-8")
    kv("jn_sites_controle_negatif",
       sum(int(x.split(":")[1]) for x in
           sites_ecriture([AP / "lib" / "impossible.py", faux / "faux_ecrivain.py"])))

    # --- LES DEUX VRAIS APPELANTS, SUR UN SEUL JOURNAL. `who=` les nomme, `by=` dit que le
    # code qui a ecrit est unique. C'est la reponse mesurable a « deux ecrivains ».
    # Les deux appelants jouent leur VRAI geste sur des etats SEMES par le vrai producteur :
    # l'orchestrateur purge dans SON processus, la course appelle la CLI, mot pour mot comme
    # `lib/proof_run.sh` l'appelle. Aucun des deux n'ecrit le journal lui-meme.
    reports = root / "jn-appelants" / "reports"
    depot = faux_depot(root)
    ecrivain = AP / "lib" / "proof_impossible.sh"
    def semer_ailleurs(iid):
        (reports / iid).mkdir(parents=True, exist_ok=True)
        subprocess.run(["bash", str(ecrivain), str(reports / iid), iid, "", RAISON, DETAIL,
                        "23880", "1800", BUSY],
                       cwd=depot, capture_output=True, text=True, timeout=120)
    semer_ailleurs("zzz-b")
    r_orch = I.purge(str(reports), current_item="zzz-a", since=0.0, who="orchestrateur")
    semer_ailleurs("zzz-c")
    cli = subprocess.run([sys.executable, str(AP / "lib" / "impossible.py"), "purge",
                          "--reports", str(reports), "--item", "zzz-a", "--arm", "",
                          "--who", "course"],
                         capture_output=True, text=True, timeout=120)
    kv("jn_appelants_purge_orch", len(r_orch["purged"]))
    kv("jn_appelants_purge_cli",
       ((cli.stdout or "").strip().splitlines() or ["-"])[-1])
    st = I.journal_stats(str(reports))
    kv("jn_appelants_lignes", st["lines"])
    kv("jn_appelants_ecrivains", len(st["writers"]))
    kv("jn_appelants_ecrivains_liste", ",".join(st["writers"]) or "-")
    kv("jn_appelants", len(st["callers"]))
    kv("jn_appelants_liste", ",".join(st["callers"]) or "-")
    kv("jn_appelants_malformees", st["malformed"])

    # --- LA CONCURRENCE : six processus, le meme journal, en meme temps. On compte les lignes
    # et on relit chacune avec le motif STRICT du module : une ligne coupee en deux se verrait.
    conc = root / "jn-concurrence" / "reports"
    conc.mkdir(parents=True, exist_ok=True)
    prog = ("import sys; sys.path.insert(0, %r)\n"
            "import impossible as I\n"
            "recs = [{'item': 'z%%s-%%d' %% (sys.argv[2], i), 'arm': 'livre', 'suffix': '',\n"
            # NOM-LITTERAL-ATTENDU: champ-de-faux-enregistrement-de-journal
            "         'file': 'z/proof-impossible.txt', 'age_s': i, 'reason': 'essai-precedent',\n"
            "         'cause': 'verrou'} for i in range(%d)]\n"
            "I.write_journal(sys.argv[1], recs, who='proc-' + sys.argv[2])\n"
            % (str(AP / "lib"), 150))
    procs = [subprocess.Popen([sys.executable, "-c", prog, str(conc), str(i)])
             for i in range(6)]
    for p in procs:
        p.wait(timeout=300)
    st = I.journal_stats(str(conc))
    kv("jn_conc_lignes", st["lines"])
    kv("jn_conc_attendu", 6 * 150)
    kv("jn_conc_malformees", st["malformed"])
    kv("jn_conc_ecrivains", len(st["writers"]))
    kv("jn_conc_appelants", len(st["callers"]))
    kv("jn_conc_verrou", st["lock_available"])

    # --- LA BORNE, LES DEUX BRAS. On ecrit plus que la borne et on regarde le disque.
    PLAFOND = 4 << 20      # ce que ce banc accepte d'ecrire pour ATTEINDRE la borne
    kv("jn_borne_hors_portee", 1 if I.PURGE_JOURNAL_MAX_BYTES > PLAFOND else 0)
    volume = min((I.PURGE_JOURNAL_MAX_BYTES // 120) + 2000, PLAFOND // 120)
    for tag, mod in (("apres", I), ("avant", None)):
        if I.PURGE_JOURNAL_MAX_BYTES > PLAFOND:
            # Une borne qu'on ne peut pas franchir en 4 Mio n'est pas une borne : on ne la
            # declare ni tenue ni rompue, on dit qu'on n'a pas pu la mesurer.
            kv("jn_borne_%s_ran" % tag, 0)
            continue
        if tag == "avant":
            if not blob_avant:
                kv("jn_borne_avant_ran", 0)
                continue
            src = root / "impossible-avant.py"
            src.write_text(blob_avant, encoding="utf-8")
            mod = charger(src, "imp_namer_avant")
        d = root / ("jn-borne-" + tag) / "reports"
        d.mkdir(parents=True, exist_ok=True)
        ecrire = getattr(mod, "write_journal", None) or getattr(mod, "_write_journal", None)
        kv("jn_borne_%s_ran" % tag, 1 if ecrire else 0)
        if not ecrire:
            continue
        reste = volume
        while reste > 0:
            lot = min(500, reste)
            try:
                ecrire(str(d), enregistrements(lot), time.time(), who="banc")
            except TypeError:                      # le bras d'avant ne connait pas `who`
                ecrire(str(d), enregistrements(lot), time.time())
            reste -= lot
        vivant = mod.purge_journal_path(str(d))
        try:
            taille = os.path.getsize(vivant)
        except OSError:
            taille = -1
        kv("jn_borne_%s_octets" % tag, taille)
        kv("jn_borne_%s_borne_declaree" % tag, getattr(mod, "PURGE_JOURNAL_MAX_BYTES", -1))
        kv("jn_borne_%s_borne_jugee" % tag, I.PURGE_JOURNAL_MAX_BYTES)
        kv("jn_borne_%s_sous_borne" % tag,
           1 if 0 <= taille <= I.PURGE_JOURNAL_MAX_BYTES else 0)
        garde = getattr(mod, "PURGE_JOURNAL_KEEP", ".1")
        kv("jn_borne_%s_rotation" % tag, 1 if os.path.exists(vivant + garde) else 0)
        # CE QU'ON GARDE EST ENCORE LISIBLE : une borne qui casse le fichier ne borne rien.
        tot, par = mod.purge_counts(str(d))
        kv("jn_borne_%s_lignes_relues" % tag, tot)

    # --- LE JOURNAL DE CE DEPOT, MAINTENANT. Publie, jamais compte : exiger des purges
    # REELLES serait exiger une panne. Un zero s'y lit « rien a purger ».
    st = I.journal_stats(str(AP / "reports"))
    for cle in ("bytes", "rotated_bytes", "max_bytes", "over_bound", "lines", "legacy",
                "malformed", "lock_available"):
        kv("jn_live_" + cle, st[cle])
    kv("jn_live_ecrivains", len(st["writers"]))
    kv("jn_live_ecrivains_liste", ",".join(st["writers"]) or "-")
    kv("jn_live_appelants_liste", ",".join(st["callers"]) or "-")


# ============================================================ 4. LE TEXTE RENDU =============
YAML = """version: 1
items:
- id: %s
  status: in-progress
  priority: 2
  feature: %s
  gate: {key: single_namer_defects, op: '==', value: 0}
- id: %s
  status: validated
  priority: 1
  feature: %s
  gate: {key: single_namer_defects, op: '==', value: 0}
""" % (ITEM_CUR, FEATURE_CUR, ITEM_VAL, FEATURE_VAL)


def maison(root: Path, tag: str, backlog_src: Path) -> tuple:
    m = root / ("maison-" + tag)
    (m / "lib").mkdir(parents=True, exist_ok=True)
    reports = m / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    (m / "backlog.yaml").write_text(YAML, encoding="utf-8")
    shutil.copyfile(backlog_src, m / "lib" / "backlog.py")
    bl = charger(m / "lib" / "backlog.py", "bl_namer_" + tag)
    bl.DIGEST_MEMO = str(m / ".last_status_digest")     # JAMAIS celui de l'owner
    return m, reports, bl


def axe_texte(root: Path, I, blob_avant: str) -> None:
    depot = faux_depot(root)
    ecrivain = AP / "lib" / "proof_impossible.sh"
    avant_src = None
    if blob_avant:
        avant_src = root / "backlog-avant.py"
        avant_src.write_text(blob_avant, encoding="utf-8")

    for tag, src in (("apres", AP / "lib" / "backlog.py"), ("avant", avant_src)):
        if src is None:
            kv("tx_%s_ran" % tag, 0)
            continue
        m, reports, bl = maison(root, tag, src)
        # LE MEME SEMIS DES DEUX COTES : trois etats, trois populations d'item.
        for iid in (ITEM_CUR, ITEM_VAL, ITEM_GHOST):
            (reports / iid).mkdir(parents=True, exist_ok=True)
            subprocess.run(["bash", str(ecrivain), str(reports / iid), iid, "",
                            RAISON, DETAIL, "23880", "1800", BUSY],
                           cwd=depot, capture_output=True, text=True, timeout=120)
        # Le nom SE DEMANDE, ici aussi : un banc qui citerait le litteral qu'il traque
        # serait le deuxieme nommeur que cet item retire.
        semes = sum(1 for iid in (ITEM_CUR, ITEM_VAL, ITEM_GHOST)
                    if (reports / iid / I.arm_name("impossible", "")).exists())
        texte = bl.load(m / "backlog.yaml").status_report()
        kv("tx_%s_ran" % tag, 1)
        kv("tx_%s_semes" % tag, semes)
        kv("tx_%s_len" % tag, len(texte))
        kv("tx_%s_section" % tag, 1 if "## Preuve impossible" in texte else 0)
        kv("tx_%s_nomme_en_cours" % tag, 1 if FEATURE_CUR in texte else 0)
        kv("tx_%s_nomme_valide" % tag, 1 if FEATURE_VAL in texte else 0)
        kv("tx_%s_nomme_fantome" % tag, 1 if ITEM_GHOST in texte else 0)
        kv("tx_%s_dit_hors_file" % tag, 1 if "hors file" in texte else 0)
        bloc = ""
        if "## Preuve impossible" in texte:
            bloc = texte[texte.index("## Preuve impossible"):].split("\n\n")[0]
        kv("tx_%s_bloc" % tag, bloc.replace("\n", " | ")[:380] or "-")


# ================================================================ LES TEMOINS DE SOURCE =====
def temoins_source(I, blob_imp_avant: str, blob_run_avant: str) -> None:
    ecrivain = (AP / "lib" / "proof_impossible.sh").read_text(encoding="utf-8")
    juge = (AP / "validators" / "generic.sh").read_text(encoding="utf-8")
    bl = (AP / "lib" / "backlog.py").read_text(encoding="utf-8")
    imp = (AP / "lib" / "impossible.py").read_text(encoding="utf-8")
    run = (AP / "lib" / "proof_run.sh").read_text(encoding="utf-8")
    orch = (AP / "orchestrator.py").read_text(encoding="utf-8")
    kv("src_marker_writer", 1 if MARKER_WRITER in ecrivain else 0)
    kv("src_marker_validator", 1 if MARKER_VALIDATOR in juge else 0)
    kv("src_marker_backlog", 1 if MARKER_BACKLOG in bl else 0)
    kv("src_marker_journal", 1 if MARKER_JOURNAL in imp else 0)
    kv("src_marker_run", 1 if MARKER_RUN in run else 0)
    # LE JUGE INTERROGE L'AUTORITE, il ne fabrique aucun nom.
    kv("src_juge_appelle_autorite", juge.count("impossible.py why"))
    kv("src_juge_litteral_etat", juge.count(I.KINDS["impossible"]))
    # LE RAPPORT LIT TOUT LE DISQUE : plus de filtre ACTIONABLE devant les etats.
    kv("src_bl_lit_tout", bl.count("_impossible.read_all(self._reports_dir())"))
    kv("src_bl_un_renderer", bl.count("def bloc_impossible("))
    # LES DEUX APPELANTS NOMMENT LEUR PURGE.
    kv("src_orch_who", orch.count('who="orchestrateur"'))
    kv("src_run_who", run.count("--who course"))
    # HORS PERIMETRE : les MOTIFS de purge ne bougent pas, la DETECTION non plus.
    kv("src_raisons_purge", ",".join(I.PURGE_REASONS))
    m = re.search(r"PURGE_REASONS\s*=\s*\(([^)]*)\)", blob_imp_avant or "")
    kv("src_raisons_purge_avant",
       ",".join(x.strip().strip('"\'') for x in m.group(1).split(",") if x.strip())
       if m else "-")
    raisons = lambda txt: ",".join(sorted(set(  # noqa: E731
        re.findall(r"die3 ([a-z0-9-]+)", txt or ""))))
    kv("src_die3_raisons", raisons(run))
    kv("src_die3_raisons_avant", raisons(blob_run_avant) or "-")
    kv("src_cles_etat", len(I.KEYS))
    r = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--",
                        "game/", "common/", "android/", "goal_src/", "goalc/"],
                       capture_output=True, text=True, timeout=180)
    sales = [x[3:] for x in r.stdout.splitlines() if x.strip()]
    kv("src_engine_dirty", len(sales))
    kv("src_engine_dirty_list", ",".join(sales[:12]) or "-")


# ===================================================================================== main =
def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="namer-banc-"))
    semis = [AP / "reports" / SEED_IMP, AP / "reports" / SEED_ORD]
    try:
        c_w, b_w = before_blob(".autoport/lib/proof_impossible.sh", MARKER_WRITER)
        c_v, b_v = before_blob(".autoport/validators/generic.sh", MARKER_VALIDATOR)
        c_b, b_b = before_blob(".autoport/lib/backlog.py", MARKER_BACKLOG)
        c_j, b_j = before_blob(".autoport/lib/impossible.py", MARKER_JOURNAL)
        c_r, b_r = before_blob(".autoport/lib/proof_run.sh", MARKER_RUN)
        for nom, commit, blob, marker in (("writer", c_w, b_w, MARKER_WRITER),
                                          ("validator", c_v, b_v, MARKER_VALIDATOR),
                                          ("backlog", c_b, b_b, MARKER_BACKLOG),
                                          ("journal", c_j, b_j, MARKER_JOURNAL)):
            kv("before_%s_commit" % nom, commit[:12] or "-")
            kv("before_%s_marker_absent" % nom, 1 if (blob and marker not in blob) else 0)

        sys.path.insert(0, str(AP))
        sys.path.insert(0, str(AP / "lib"))
        I = charger(AP / "lib" / "impossible.py", "imp_namer")
        O = charger(AP / "orchestrator.py", "orch_namer")

        axe_noms(root, I, b_w)
        axe_juge(root, I, O, b_v)
        axe_journal(root, I, b_j)
        axe_texte(root, I, b_b)
        temoins_source(I, b_j, b_r)

        for rel in ("lib/impossible.py", "lib/proof_impossible.sh", "lib/proof_run.sh",
                    "lib/backlog.py", "validators/generic.sh", "orchestrator.py",
                    "lib/single_namer_selftest.py"):
            try:
                h = hashlib.sha256((AP / rel).read_bytes()).hexdigest()[:16]
            except OSError:
                h = "-"
            kv("sha_" + rel.replace("/", "_").replace(".", "_"), h)
        return 0
    finally:
        for d in semis:
            shutil.rmtree(d, ignore_errors=True)
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
