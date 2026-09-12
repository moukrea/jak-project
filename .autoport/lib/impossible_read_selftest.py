#!/usr/bin/env python3
"""lib/impossible_read_selftest.py — LE BANC de `harness-proof-impossible-must-be-read`.

CE QU'IL FAIT. Il SEME un etat nomme « preuve impossible » — le vrai fichier, ecrit par le
vrai `lib/proof_impossible.sh`, jamais un dictionnaire fabrique ici — dans des dossiers
jetables, puis il fait tourner LES DEUX LECTEURS reels dessus :

  * `orchestrator.close_gate`   la porte de fermeture, celle qui rendait « pas de preuve » ;
  * `backlog.status_report`     `autoport status` ET le digest de l'owner (auto_push_builds.sh
                                appelle `autoport status --changed` ; c'est la meme fonction).

DEUX AXES, parce qu'une seule direction ne prouve rien :

  AXE A — L'ETAT. Meme code, meme dossier, SANS puis AVEC l'etat seme. Aucun des deux lecteurs
  ne doit rien voir avant, les deux doivent le voir apres. C'est le controle de non-vacuite :
  un lecteur qui parlerait tout le temps ne mesurerait rien.

  AXE B — LE CODE. MEME etat seme, code d'AVANT ce chantier contre code du disque. Le code
  d'avant est ancre par MARQUEUR (`git log` remonte jusqu'au premier commit ou le marqueur est
  absent) et jamais par `HEAD:` — lu a HEAD, le temoin d'avant s'accuse lui-meme des le commit.
  Le commit retenu est PUBLIE.

TROIS CONTROLES DE PLUS, qui disent que la porte ne devient pas bavarde :
  * un etat PERIME — une course ulterieure a ecrit proof.txt — n'est plus debout ;
  * un etat d'un essai PRECEDENT (anterieur a `since`) ne requalifie pas l'essai en cours ;
  * la comptabilite : trois requalifications d'affilee, la quatrieme BLOQUE, et `retries`
    revient a sa valeur d'avant dans les quatre cas.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; `lib/census/harness-proof-impossible-must-be-read.sh` fait la somme.
"""
from __future__ import annotations

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

# Les marqueurs qui datent CE chantier dans chacun des deux lecteurs.
MARKER_ORCH = "CLOSE-GATE/preuve-impossible"
MARKER_BL = "## Preuve impossible"

ITEM_ID = "zzz-banc-impossible"
FEATURE = "Le banc de la preuve impossible"
RAISON = "build-en-cours"
DETAIL = "un build ecrit encore apres 1800s (borne 1800s) : processus [n]inja en cours"
BUSY = "deploy-in-progress tenu par le constructeur"


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ")[:400]))


# ===================================================================== semer un etat vrai ===
def semer(reports: Path, item_id: str, suffix: str = "", lock_pid: str = "",
          age_s: int = 0) -> Path:
    """Ecrit l'etat nomme AVEC LE VRAI SCRIPT. Rien n'est simule du cote producteur.

    `lock_pid` : le pid ecrit dans un faux `.deploy-in-progress`. On y met le NOTRE, qui
    repond forcement a `kill -0` : c'est ce qui rend « verrou VIVANT, tenu depuis » mesurable
    sans attendre six heures.
    """
    d = reports / item_id
    d.mkdir(parents=True, exist_ok=True)
    faux_root = d / "faux-depot"
    (faux_root / ".autoport").mkdir(parents=True, exist_ok=True)
    if lock_pid:
        (faux_root / ".autoport" / ".deploy-in-progress").write_text(
            "banc pid=%s\n" % lock_pid, encoding="utf-8")
    # Le script lit le verrou du depot git courant : on le lance DANS le faux depot.
    subprocess.run(["git", "init", "-q", "."], cwd=faux_root, capture_output=True, timeout=60)
    subprocess.run(
        ["bash", str(AP / "lib" / "proof_impossible.sh"), str(d), item_id, suffix,
         RAISON, DETAIL, "1800", "1800", BUSY],
        cwd=faux_root, capture_output=True, text=True, timeout=120)
    f = d / ("proof%s-impossible.txt" % suffix)
    if age_s and f.exists():
        t = time.time() - age_s
        os.utime(f, (t, t))
    return f


def vieillir(f: Path, age_s: int) -> None:
    t = time.time() - age_s
    os.utime(f, (t, t))


# ============================================================ le code d'AVANT, par MARQUEUR =
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


def charger(src: Path, name: str):
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    return mod


# ============================================================== 1. LA PORTE DE FERMETURE ====
ITEM = {"id": ITEM_ID, "feature": FEATURE, "no_code": True, "device": False,
        "owner_test": False, "owner_verify": False}


def charger_orchestrateur(src: Path, name: str, ap_banc: Path, journal: list):
    sys.path.insert(0, str(AP))
    mod = charger(src, name)
    ap_banc.mkdir(parents=True, exist_ok=True)
    mod.AUTOPORT_DIR = ap_banc
    mod.REPO_ROOT = ap_banc
    if hasattr(mod, "OWNER_OK_DIR"):
        mod.OWNER_OK_DIR = ap_banc / "owner-ok"
    mod.log = lambda msg, *a, **k: journal.append(str(msg))
    mod._reread_item = lambda iid, fallback: fallback
    return mod


def appeler_porte(mod, since=0.0):
    """La VRAIE close_gate, appelee comme la production l'appelle."""
    try:
        return mod.close_gate(ITEM, (), validator_ok=False, since=since)
    except TypeError:
        # Le code d'AVANT : sa signature n'a ni `validator_ok` ni `since`. C'est le fait
        # mesure — cette porte ne pouvait meme pas etre appelee sur un essai refuse.
        return mod.close_gate(ITEM, ())


def bras_porte(tag: str, src: Path, root: Path, seme: bool) -> None:
    journal: list = []
    ap_banc = root / ("ap-" + tag)
    reports = ap_banc / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    f = semer(reports, ITEM_ID, lock_pid=str(os.getpid())) if seme else None
    if f is not None:
        vieillir(f, 23880)                       # 6 h 38, la duree du 12/09
    mod = charger_orchestrateur(src, "orch_" + tag, ap_banc, journal)
    import inspect
    try:
        params = list(inspect.signature(mod.close_gate).parameters)
    except (TypeError, ValueError):
        params = []
    kv("%s_sig_validator_ok" % tag, 1 if "validator_ok" in params else 0)
    kv("%s_sig_since" % tag, 1 if "since" in params else 0)
    kv("%s_has_requalify" % tag, 1 if hasattr(mod, "requalify_impossible_attempt") else 0)
    kv("%s_has_counts" % tag, 1 if hasattr(mod, "impossible_read_counts") else 0)
    kv("%s_seeded" % tag, 1 if f is not None and f.exists() else 0)
    kv("%s_seeded_keys" % tag,
       len([x for x in (f.read_text(encoding="utf-8").splitlines() if f else []) if "=" in x]))
    try:
        status, reason = appeler_porte(mod, since=time.time() - 30000)
    except Exception as exc:                                       # noqa: BLE001
        kv("%s_ran" % tag, 0)
        kv("%s_error" % tag, "%s: %s" % (type(exc).__name__, exc))
        return
    kv("%s_ran" % tag, 1)
    kv("%s_status" % tag, status)
    kv("%s_is_impossible" % tag, 1 if status == "impossible" else 0)
    kv("%s_names_reason" % tag, 1 if RAISON in reason else 0)
    kv("%s_names_age" % tag, 1 if "6 h 38" in reason else 0)
    kv("%s_names_lock" % tag, 1 if ("pid %d" % os.getpid()) in reason else 0)
    kv("%s_names_arm" % tag, 1 if "livre" in reason else 0)
    kv("%s_reason_len" % tag, len(reason))
    kv("%s_reason" % tag, reason)


def controles_porte(root: Path) -> None:
    """La porte NEUVE ne doit pas devenir bavarde : trois etats qui ne sont PAS debout."""
    journal: list = []
    ap_banc = root / "ap-controles"
    reports = ap_banc / "reports"
    reports.mkdir(parents=True, exist_ok=True)
    mod = charger_orchestrateur(AP / "orchestrator.py", "orch_ctrl", ap_banc, journal)

    # a. AUCUN etat : la porte ne parle pas d'impossibilite.
    st, _ = mod.close_gate(ITEM, (), validator_ok=False, since=0.0)
    kv("ctrl_vide_status", st)
    kv("ctrl_vide_is_impossible", 1 if st == "impossible" else 0)

    # b. ETAT PERIME : une course ULTERIEURE a ecrit proof.txt. Il n'est plus debout.
    f = semer(reports, ITEM_ID, lock_pid=str(os.getpid()))
    vieillir(f, 600)
    (reports / ITEM_ID / "proof.txt").write_text("source=x86\nframes=13504\n", encoding="utf-8")
    st, _ = mod.close_gate(ITEM, (), validator_ok=False, since=0.0)
    kv("ctrl_perime_status", st)
    kv("ctrl_perime_is_impossible", 1 if st == "impossible" else 0)
    (reports / ITEM_ID / "proof.txt").unlink()

    # b'. le MEME etat, proof.txt retire : il redevient debout. Sans ce tour, (b) pourrait
    # etre vert parce que le semis a echoue.
    st, _ = mod.close_gate(ITEM, (), validator_ok=False, since=0.0)
    kv("ctrl_perime_temoin_status", st)
    kv("ctrl_perime_temoin_is_impossible", 1 if st == "impossible" else 0)

    # c. ETAT D'UN ESSAI PRECEDENT : anterieur a `since`, il ne requalifie pas celui-ci.
    vieillir(f, 7200)
    st, _ = mod.close_gate(ITEM, (), validator_ok=False, since=time.time() - 60)
    kv("ctrl_ancien_status", st)
    kv("ctrl_ancien_is_impossible", 1 if st == "impossible" else 0)

    # d. le validateur PASSE et rien n'est debout : la porte suit son cours normal.
    f.unlink()
    st, _ = mod.close_gate(ITEM, (), validator_ok=True, since=0.0)
    kv("ctrl_valide_status", st)


# =============================================== 2. LA COMPTABILITE DES ESSAIS REQUALIFIES ==
def comptabilite(root: Path) -> None:
    journal: list = []
    ap_banc = root / "ap-compta"
    mod = charger_orchestrateur(AP / "orchestrator.py", "orch_compta", ap_banc, journal)
    mod.save_state = lambda st: None
    st_fake = {"reports": None}
    etat = {"retries": {ITEM_ID: 4}}
    vu = {"reason": RAISON, "arm": "livre", "since_s": 23880, "lock_pid": str(os.getpid()),
          "lock_held_s": 23940, "detail": DETAIL}
    verdicts, retries = [], []
    for _ in range(4):
        etat["retries"][ITEM_ID] = 4
        v, dit = mod.requalify_impossible_attempt(etat, ITEM_ID, vu)
        verdicts.append(v)
        retries.append(etat["retries"][ITEM_ID])
        dernier = dit
    kv("compta_verdicts", ",".join(verdicts))
    kv("compta_retries", ",".join(str(x) for x in retries))
    kv("compta_ceiling", getattr(mod, "MAX_IMPOSSIBLE_IN_A_ROW", -1))
    rec = etat["proof_impossible"][ITEM_ID]
    kv("compta_total", rec["total"])
    kv("compta_read", rec["read"])
    kv("compta_streak", rec["streak"])
    kv("compta_since_set", 1 if rec["since"] else 0)
    kv("compta_reason", rec["reason"])
    lus, req = mod.impossible_read_counts(etat)
    kv("compta_counts_read", lus)
    kv("compta_counts_requalified", req)
    kv("compta_dit_names_age", 1 if "6 h 38" in dernier else 0)
    kv("compta_dit_names_lock", 1 if ("pid %d" % os.getpid()) in dernier else 0)
    kv("compta_dit", dernier)
    mod._impossible_reset(etat, ITEM_ID)
    kv("compta_after_reset_streak", etat["proof_impossible"][ITEM_ID]["streak"])
    kv("compta_after_reset_total", etat["proof_impossible"][ITEM_ID]["total"])
    kv("compta_state_key", 1 if "proof_impossible" in getattr(mod, "STATE_KEYS", ()) else 0)
    del st_fake


# ======================================================= 3. `autoport status` ET LE DIGEST ==
YAML = """version: 1
items:
- id: %s
  status: in-progress
  priority: 1
  feature: %s
  gate:
    key: impossible_read_defects
    op: ==
    value: 0
""" % (ITEM_ID, FEATURE)


def charger_backlog(tag: str, src: Path, maison: Path, blob: str | None):
    """Le lecteur de statut, branche sur un backlog.yaml jetable.

    Le code d'AVANT est ecrit dans `maison/lib/` : son `AP` en decoule, donc son memo de
    digest et ses rapports sont ceux du banc. `lib/impossible.py` est copie A COTE dans LES
    DEUX bras — la difference mesuree doit etre le LECTEUR, jamais la presence du module.
    """
    maison.mkdir(parents=True, exist_ok=True)
    (maison / "lib").mkdir(parents=True, exist_ok=True)
    (maison / "reports").mkdir(parents=True, exist_ok=True)
    (maison / "backlog.yaml").write_text(YAML, encoding="utf-8")
    shutil.copyfile(AP / "lib" / "impossible.py", maison / "lib" / "impossible.py")
    if blob is None:
        mod = charger(src, "bl_" + tag)
        mod.DIGEST_MEMO = str(maison / ".last_status_digest")   # JAMAIS celui de l'owner
    else:
        cible = maison / "lib" / "backlog.py"
        cible.write_text(blob, encoding="utf-8")
        mod = charger(cible, "bl_" + tag)
    return mod


def bras_statut(tag: str, maison: Path, blob: str | None) -> None:
    mod = charger_backlog(tag, AP / "lib" / "backlog.py", maison, blob)
    reports = maison / "reports"
    yml = maison / "backlog.yaml"

    def rendu():
        return mod.load(yml).status_report()

    def digest():
        return mod.load(yml).status_report(changed_only=True)

    # --- AXE A, temps 1 : AUCUN etat. Les deux lectures doivent etre muettes sur le sujet.
    avant = rendu()
    kv("%s_avant_has_section" % tag, 1 if MARKER_BL in avant else 0)
    kv("%s_avant_len" % tag, len(avant))
    digest()                                     # amorce le memo : le 1er appel sort toujours

    # --- AXE A, temps 2 : l'etat SEME, age de 6 h 38, verrou VIVANT.
    f = semer(reports, ITEM_ID, lock_pid=str(os.getpid()))
    vieillir(f, 23880)
    apres = rendu()
    kv("%s_ran" % tag, 1)
    kv("%s_has_section" % tag, 1 if MARKER_BL in apres else 0)
    kv("%s_names_feature" % tag, 1 if FEATURE in apres else 0)
    kv("%s_names_reason" % tag, 1 if RAISON in apres else 0)
    # L'AGE, dans un texte RELU EN BOUCLE : un palier qui ne bouge pas a la seconde, et
    # l'INSTANT exact ou l'etat a ete ecrit, immuable. La duree au format « 6 h 38 » est
    # publiee par la porte, qui n'est ecrite qu'une fois par essai.
    kv("%s_names_bucket" % tag, 1 if "plus de 2 h" in apres else 0)
    kv("%s_names_at" % tag, 1 if "etat ecrit le 20" in apres else 0)
    kv("%s_names_lock" % tag, 1 if ("pid %d" % os.getpid()) in apres else 0)
    kv("%s_says_alive" % tag, 1 if "VIVANT" in apres else 0)
    kv("%s_len" % tag, len(apres))
    # ANTI-BRUIT, MESURE : soixante secondes de plus dans le MEME palier ne changent pas UN
    # octet. `watch.py` reveille le superviseur des que ce texte bouge — une duree a la
    # seconde aurait remplace le silence du 12/09 par un cri permanent.
    vieillir(f, 23940)
    kv("%s_stable_60s" % tag, 1 if rendu() == apres else 0)
    # ... mais un CHANGEMENT DE PALIER, lui, se voit.
    vieillir(f, 120)
    kv("%s_change_palier" % tag, 1 if rendu() != apres else 0)
    vieillir(f, 23880)
    # LE TEMOIN LE PLUS NU : le MEME texte, avec et sans l'etat. Le lecteur d'AVANT rend
    # exactement le meme nombre d'octets — pour lui, l'impossibilite n'existe pas.
    kv("%s_len_delta" % tag, len(apres) - len(avant))
    bloc = ""
    if MARKER_BL in apres:
        bloc = apres[apres.index(MARKER_BL):].split("\n\n")[0]
    kv("%s_text" % tag, bloc.replace("\n", " | "))

    # --- LE DIGEST DE L'OWNER : `autoport status --changed`, la fonction que auto_push_builds
    # appelle. Il doit se REVEILLER a l'apparition, se TAIRE ensuite, se reveiller quand
    # l'impossibilite CHANGE DE PALIER, et se taire pour une seconde de plus.
    d1 = digest()
    kv("%s_digest_apparition" % tag, 1 if MARKER_BL in d1 else 0)
    d2 = digest()
    kv("%s_digest_stable" % tag, 1 if d2 == "" else 0)
    vieillir(f, 120)                              # 6 h 38 -> 2 min : palier franchi
    d3 = digest()
    kv("%s_digest_palier" % tag, 1 if d3 != "" else 0)
    vieillir(f, 150)                              # 2 min -> 2 min 30 : MEME palier
    d4 = digest()
    kv("%s_digest_meme_palier_muet" % tag, 1 if d4 == "" else 0)

    # --- AXE A, temps 3 : l'etat retire, la section disparait.
    f.unlink()
    fin = rendu()
    kv("%s_apres_retrait_has_section" % tag, 1 if MARKER_BL in fin else 0)


# ================================================================ 4. LES TEMOINS DE SOURCE ==
def temoins_source() -> None:
    """Ce que le CODE dit de lui-meme, lu dans l'AST et non par un grep de commentaire."""
    import ast as _ast
    src = (AP / "orchestrator.py").read_text(encoding="utf-8")
    tree = _ast.parse(src)
    fn = next((n for n in _ast.walk(tree)
               if isinstance(n, _ast.FunctionDef) and n.name == "run_attempt"), None)
    appels, sous_condition = 0, 0
    if fn is not None:
        # La PORTE DE FERMETURE doit etre appelee HORS du `if v.returncode == 0`. C'est le
        # changement de structure : sans lui, GATE -1 ne voit jamais un essai refuse.
        interdits = set()
        for n in _ast.walk(fn):
            if isinstance(n, _ast.If) and "returncode" in _ast.dump(n.test):
                for c in n.body:
                    for d in _ast.walk(c):
                        interdits.add(id(d))
        for n in _ast.walk(fn):
            if (isinstance(n, _ast.Call) and isinstance(n.func, _ast.Name)
                    and n.func.id == "close_gate"):
                appels += 1
                if id(n) in interdits:
                    sous_condition += 1
    kv("src_close_gate_calls", appels)
    kv("src_close_gate_under_rc", sous_condition)
    kv("src_outcome_impossible",
       1 if 'Outcome("impossible"' in src else 0)
    kv("src_main_branch",
       1 if 'out.kind == "impossible"' in src else 0)
    # UN SEUL LECTEUR. Ni la porte ni le statut ne fabriquent le nom du fichier : ils passent
    # par lib/impossible.py, sinon il y aurait deux definitions de « preuve impossible ».
    bl = (AP / "lib" / "backlog.py").read_text(encoding="utf-8")
    kv("src_orch_builds_filename", src.count("-impossible.txt"))
    kv("src_bl_builds_filename", bl.count("-impossible.txt"))
    kv("src_orch_uses_reader", src.count("impossible_state."))
    kv("src_bl_uses_reader", bl.count("_impossible."))
    # HORS PERIMETRE : la detection ne bouge pas, le jeu non plus.
    for rel in ("lib/proof_run.sh", "lib/proof_impossible.sh"):
        r = subprocess.run(["git", "-C", str(REPO), "diff", "--quiet", "HEAD", "--",
                            ".autoport/" + rel], capture_output=True, timeout=60)
        kv("src_untouched_" + rel.replace("/", "_").replace(".", "_"),
           1 if r.returncode == 0 else 0)
    r = subprocess.run(["git", "-C", str(REPO), "status", "--porcelain", "--",
                        "game/", "common/", "android/", "goal_src/", "goalc/"],
                       capture_output=True, text=True, timeout=120)
    sales = [x[3:] for x in r.stdout.splitlines() if x.strip()]
    kv("src_engine_dirty", len(sales))
    kv("src_engine_dirty_list", ",".join(sales[:12]) or "-")


# ===================================================================================== main =
def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="imp-banc-"))
    try:
        c_orch, b_orch = before_blob(".autoport/orchestrator.py", MARKER_ORCH)
        c_bl, b_bl = before_blob(".autoport/lib/backlog.py", MARKER_BL)
        kv("before_orch_commit", c_orch[:12] or "-")
        kv("before_orch_marker_absent", 1 if (b_orch and MARKER_ORCH not in b_orch) else 0)
        kv("before_bl_commit", c_bl[:12] or "-")
        kv("before_bl_marker_absent", 1 if (b_bl and MARKER_BL not in b_bl) else 0)
        kv("marker_orch_live", 1 if MARKER_ORCH in (AP / "orchestrator.py").read_text(
            encoding="utf-8") else 0)
        kv("marker_bl_live", 1 if MARKER_BL in (AP / "lib" / "backlog.py").read_text(
            encoding="utf-8") else 0)

        vieux_orch = None
        if b_orch:
            vieux_orch = root / "vieux_orchestrator.py"
            vieux_orch.write_text(b_orch, encoding="utf-8")
            try:
                shutil.copyfile(AP / "model-profiles.json", root / "model-profiles.json")
            except OSError:
                pass

        # AXE B sur la porte : meme etat seme, deux codes.
        bras_porte("gate_neuf", AP / "orchestrator.py", root, seme=True)
        if vieux_orch is not None:
            bras_porte("gate_vieux", vieux_orch, root, seme=True)
        # AXE A sur la porte : code neuf, etat absent.
        bras_porte("gate_neuf_vide", AP / "orchestrator.py", root, seme=False)

        controles_porte(root)
        comptabilite(root)
        temoins_source()

        bras_statut("stat_neuf", root / "maison-neuf", None)
        if b_bl:
            bras_statut("stat_vieux", root / "maison-vieux", b_bl)

        # LES OCTETS JUGES. Un chemin n'est pas une provenance.
        for rel in ("orchestrator.py", "lib/backlog.py", "lib/impossible.py",
                    "lib/proof_impossible.sh", "lib/impossible_read_selftest.py"):
            import hashlib
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
