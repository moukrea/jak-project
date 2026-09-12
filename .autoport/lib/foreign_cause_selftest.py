#!/usr/bin/env python3
"""lib/foreign_cause_selftest.py — LE BANC de `harness-attempt-not-burned-by-foreign-cause`.

CE QU'IL FAIT. Il fait tourner la VRAIE `close_gate`, le VRAI `git_commit_paths` et la VRAIE
comptabilite d'essais de l'orchestrateur sur des DEPOTS GIT JETABLES, face aux trois causes
exterieures du signalement du 12/09. Rien n'est simule du cote juge : c'est le code qui
tournera en production qui decide, et on lit ce que git et le registre ont ECRIT.

LES CAUSES REPRODUITES, avec de VRAIS objets git — jamais un drapeau :
  * l'arbre sale HERITE : des fichiers moteur modifies AVANT l'essai, toujours sales a la
    porte. Le perimetre d'un worker lui interdit de les commiter ou de les defaire.
  * le chemin DURABLEMENT non committable : un fichier suivi, modifie, puis `chmod 000`.
    `git add` sort en 128 (« open(): Permission non accordee »), `git commit -- <chemin>`
    aussi, et le chemin reste sale. C'est la saleté permanente qui rebloque chaque item.
  * le territoire moteur : un fichier sale sous `common/` — le seul dossier que GATE 0
    comptait et que GATE 1 ignorait.

LES BRAS, et pourquoi deux codes :
  terr_*    un fichier sale sous `common/` SEUL. Le VIEUX code rend `fail` CLOSE-GATE/code
            (son GATE 1 ne voit pas `common/`), le NEUF non. Meme depot, meme item, meme
            entree : la divergence des deux listes est LA cause, pas le bras.
  requal_*  l'arbre sale herite. Le VIEUX rend `fail` — un essai COMPTE, empreinte, et une
            consigne qui ordonne au worker de nettoyer l'arbre d'un autre. Le NEUF rend
            `foreign`, et `requalify_foreign_attempt` REMET `retries` comme avant.
  quar_*    le chemin impossible, presente DEUX FOIS de suite. Le VIEUX le represente et le
            refait echouer (le correctif du 12/09 ne le PERD plus, il ne le RESOUT pas) ; le
            NEUF le met de cote, date, et ne le presente plus.
  lock_*    l'etat nomme « preuve impossible » : le script est LANCE, son fichier est relu.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ de
proof.txt ; `lib/census/harness-attempt-not-burned-by-foreign-cause.sh` fait la somme.
"""
from __future__ import annotations

import ast
import importlib.util
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent
MARKER = "requalify_foreign_attempt"
ITEM_ID = "zzz-banc-foreign-cause"

HERITE = [                      # sales AVANT l'essai : le chantier d'un AUTRE item
    "game/graphics/opengl_renderer/Loader.cpp",
    "common/util/FileUtil.cpp",
    "android/app/src/main/cpp/native.cpp",
]
COMMUN = "common/util/Territoire.cpp"       # le dossier que GATE 1 ignorait
PROPRE = "game/graphics/Propre.cpp"
POISON = "game/graphics/Poison.cpp"         # chmod 000 : refuse par add ET par commit
AUTRE = "game/graphics/Autre.cpp"


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ")[:400]))


def git(repo: Path, *args, check=False):
    r = subprocess.run(["git", *args], cwd=repo, capture_output=True, text=True, timeout=120)
    if check and r.returncode != 0:
        raise RuntimeError("git %s -> %s : %s" % (args[0], r.returncode, r.stderr))
    return r


def write(repo: Path, rel: str, body: str):
    f = repo / rel
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_text(body, encoding="utf-8")


def base_repo(root: Path, tracked: list[str]) -> Path:
    """Un depot jetable a DEUX commits : `HEAD~1` resout, donc l'ancre du superviseur ne
    retombe pas sur une revision inconnue et le bras ne mesure pas cet accident-la."""
    repo = root
    repo.mkdir(parents=True, exist_ok=True)
    git(repo, "init", "-q", ".", check=True)
    git(repo, "config", "user.email", "banc@autoport", check=True)
    git(repo, "config", "user.name", "banc", check=True)
    git(repo, "config", "commit.gpgsign", "false", check=True)
    for rel in tracked:
        write(repo, rel, "// origine\n")
    git(repo, "add", "-A", check=True)
    git(repo, "commit", "-q", "-m", "origine", check=True)
    write(repo, "LISEZMOI.md", "second commit, hors territoire moteur\n")
    git(repo, "add", "-A", check=True)
    git(repo, "commit", "-q", "-m", "second", check=True)
    return repo


def load(src: Path, name: str, repo: Path, journal: list):
    """L'orchestrateur, charge depuis `src`, branche sur le depot jetable.

    Le `.autoport` du banc vit HORS du depot jetable : dedans, le registre de mise de cote
    serait lui-meme un fichier sale que `worker_paths()` presenterait au tour suivant, et
    les deux bras ne recevraient plus le meme lot. En production il est nomme dans
    `_HARNESS_STATE_FILES`, donc jamais presente."""
    sys.path.insert(0, str(AP))
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    mod.REPO_ROOT = repo
    ap_banc = repo.parent / (".autoport-banc-" + repo.name)   # HORS du depot
    ap_banc.mkdir(parents=True, exist_ok=True)
    mod.AUTOPORT_DIR = ap_banc
    if hasattr(mod, "OWNER_OK_DIR"):
        mod.OWNER_OK_DIR = ap_banc / "owner-ok"
    mod.log = lambda msg, *a, **k: journal.append(str(msg))
    mod._reread_item = lambda iid, fallback: fallback
    return mod


def status_of(repo: Path, path: str | None = None) -> list[str]:
    args = ["status", "--porcelain=v1", "-uall"]
    if path:
        args += ["--", path]
    return [x[3:] for x in git(repo, *args).stdout.splitlines()]


# ======================================================= 1. LE TERRITOIRE, UNE SEULE LISTE ==
def arm_territoire(tag: str, src: Path, root: Path) -> None:
    """Un fichier sale sous `common/` SEUL. GATE 1 le compte, ou ne le compte pas."""
    repo = base_repo(root / ("repo-" + tag), [COMMUN, PROPRE])
    write(repo, COMMUN, "// origine\n// modifie par l'essai\n")
    journal: list = []
    mod = load(src, "orch_t_" + tag, repo, journal)
    item = {"id": ITEM_ID, "no_code": False, "device": False, "owner_test": True,
            "feature": "banc du territoire"}

    sales = status_of(repo)
    kv("%s_tree_dirty" % tag, len(sales))
    kv("%s_dirty_list" % tag, ",".join(sorted(sales)) or "-")
    try:
        status, reason = mod.close_gate(item, [])
    except TypeError:
        status, reason = mod.close_gate(item)
    kv("%s_status" % tag, status)
    kv("%s_is_gate1" % tag, 1 if "CLOSE-GATE/code" in reason else 0)
    kv("%s_reason" % tag, " ".join(reason.split())[:200] or "-")
    terr = getattr(mod, "GATE_TERRITORY", None)
    kv("%s_has_recorder" % tag, 1 if isinstance(terr, dict) else 0)
    g0 = ",".join((terr or {}).get("gate0") or []) or "-"
    g1 = ",".join((terr or {}).get("gate1") or []) or "-"
    kv("%s_gate0_list" % tag, g0)
    kv("%s_gate1_list" % tag, g1)
    kv("%s_identical" % tag, 1 if (g0 != "-" and g0 == g1) else 0)


# ================================================ 2. L'ARBRE HERITE NE BRULE PLUS UN ESSAI ==
def arm_requal(tag: str, src: Path, root: Path, *, herite: bool) -> None:
    repo = base_repo(root / ("repo-" + tag), HERITE + [PROPRE])
    for rel in HERITE:
        write(repo, rel, "// origine\n// le chantier d'un AUTRE item\n")
    journal: list = []
    mod = load(src, "orch_r_" + tag, repo, journal)
    item = {"id": ITEM_ID, "no_code": True, "device": False, "owner_test": True,
            "feature": "banc de la requalification"}

    # La ligne de base est mesuree PAR LE BANC : les deux bras recoivent la MEME entree,
    # y compris celui qui n'a pas le helper.
    tree = sorted(p for p in status_of(repo)
                  if p.startswith(("game/", "common/", "android/", "goal_src/", "goalc/")))
    baseline = tree if herite else []
    kv("%s_tree_dirty" % tag, len(tree))
    kv("%s_baseline" % tag, len(baseline))
    try:
        status, reason = mod.close_gate(item, baseline)
    except TypeError:
        status, reason = mod.close_gate(item)
    kv("%s_status" % tag, status)
    kv("%s_is_gate0" % tag, 1 if "CLOSE-GATE/arbre-sale" in reason else 0)
    kv("%s_names_paths" % tag, 1 if all(Path(p).name in reason for p in HERITE) else 0)
    kv("%s_reason" % tag, " ".join(reason.split())[:200] or "-")

    # LA COMPTABILITE, pilotee sur un `state` jetable : c'est elle qui decide si l'essai
    # est debite. Une porte qui rend `foreign` sans qu'on defasse le compte ne sert a rien.
    fn = getattr(mod, "requalify_foreign_attempt", None)
    kv("%s_has_requal" % tag, 1 if callable(fn) else 0)
    if not callable(fn):
        return
    state = {"retries": {}, "foreign_cause": {}}
    verdicts, comptes = [], []
    plafond = int(getattr(mod, "MAX_FOREIGN_IN_A_ROW", 0) or 0)
    for _ in range(plafond + 2):
        state["retries"][ITEM_ID] = int(state["retries"].get(ITEM_ID, 0)) + 1   # l'essai
        v, _dit = fn(state, ITEM_ID, list(tree))                                # la porte
        verdicts.append(v)
        comptes.append(int(state["retries"][ITEM_ID]))
    kv("%s_ceiling" % tag, plafond)
    kv("%s_verdicts" % tag, ",".join(verdicts))
    kv("%s_retries_after" % tag, ",".join(str(c) for c in comptes))
    kv("%s_retries_max" % tag, max(comptes) if comptes else -1)
    rec = state["foreign_cause"].get(ITEM_ID) or {}
    kv("%s_total" % tag, rec.get("total", -1))
    kv("%s_streak" % tag, rec.get("streak", -1))
    kv("%s_since" % tag, rec.get("since", "-") or "-")
    kv("%s_rec_paths" % tag, len(rec.get("paths") or []))
    reset = getattr(mod, "_foreign_reset", None)
    if callable(reset):
        state["version"] = 0
        mod.save_state = lambda *_a, **_k: None
        reset(state, ITEM_ID)
        kv("%s_streak_after_reset" % tag, state["foreign_cause"][ITEM_ID]["streak"])
    else:
        kv("%s_streak_after_reset" % tag, -1)


# ============================================== 3. LE CHEMIN IMPOSSIBLE, MIS DE COTE UNE FOIS
def arm_quarantaine(tag: str, src: Path, root: Path) -> None:
    repo = base_repo(root / ("repo-" + tag), [POISON, PROPRE, AUTRE])
    write(repo, POISON, "// origine\n// modifie\n")
    write(repo, PROPRE, "// origine\n// modifie\n")
    os.chmod(repo / POISON, 0o000)             # git add ET git commit sortent en 128
    journal: list = []
    mod = load(src, "orch_q_" + tag, repo, journal)
    try:
        # LE POISON EST-IL VRAIMENT IMPOSSIBLE ? Mesure, pas decor : sans ca, un bras vert
        # ne dirait que « git a tout accepte ».
        r = git(repo, "add", "--", POISON)
        kv("%s_poison_add_rc" % tag, r.returncode)
        r2 = git(repo, "commit", "-m", "x", "--", POISON)
        kv("%s_poison_commit_rc" % tag, r2.returncode)
        kv("%s_poison_still_dirty" % tag, 1 if status_of(repo, POISON) else 0)

        # --- PREMIERE PRESENTATION -------------------------------------------------
        paths1 = mod.worker_paths()
        kv("%s_paths1" % tag, len(paths1))
        ok1 = mod.git_commit_paths(ITEM_ID, "banc 1", paths1)
        st = getattr(mod, "COMMIT_PATHS_STATS", {}) or {}
        kv("%s_ok1" % tag, 1 if ok1 else 0)
        kv("%s_refused1" % tag, st.get("refused", -1))
        kv("%s_quarantined1" % tag, st.get("quarantined", -1))
        kv("%s_skipped1" % tag, st.get("quarantined_skipped", -1))

        book = {}
        qf = mod.quarantine_path() if hasattr(mod, "quarantine_path") else None
        if qf is not None and Path(qf).exists():
            book = json.loads(Path(qf).read_text())
        kv("%s_book1" % tag, len(book))
        kv("%s_book1_has_poison" % tag, 1 if POISON in book else 0)
        kv("%s_book1_since" % tag, (book.get(POISON) or {}).get("since", "-") or "-")
        kv("%s_book1_reason_len" % tag, len((book.get(POISON) or {}).get("reason", "")))

        # --- DEUXIEME PRESENTATION : un AUTRE fichier devient sale ------------------
        write(repo, AUTRE, "// origine\n// modifie au deuxieme essai\n")
        before = st.get("refused", 0)
        paths2 = mod.worker_paths()
        kv("%s_paths2" % tag, len(paths2))
        kv("%s_paths2_has_poison" % tag, 1 if POISON in paths2 else 0)
        ok2 = mod.git_commit_paths(ITEM_ID, "banc 2", paths2)
        st = getattr(mod, "COMMIT_PATHS_STATS", {}) or {}
        kv("%s_ok2" % tag, 1 if ok2 else 0)
        kv("%s_refused2_delta" % tag, st.get("refused", -1) - before)
        kv("%s_skipped2" % tag, st.get("quarantined_skipped", -1))
        kv("%s_autre_committed" % tag, 0 if status_of(repo, AUTRE) else 1)
        jt = " ".join(" ".join(journal).split())
        kv("%s_journal_names_poison" % tag, 1 if Path(POISON).name in jt else 0)
        kv("%s_journal_says_aside" % tag, 1 if "MIS DE CÔTÉ" in jt else 0)
        kv("%s_journal_lines" % tag, len(journal))
        (root / ("journal-" + tag + ".txt")).write_text("\n".join(journal), encoding="utf-8")
    finally:
        try:
            os.chmod(repo / POISON, 0o644)
        except OSError:
            pass


# ================================================ 4. L'ETAT NOMME « PREUVE IMPOSSIBLE » =====
def arm_etat_nomme(root: Path) -> None:
    d = root / "etat"
    d.mkdir(parents=True, exist_ok=True)
    script = AP / "lib" / "proof_impossible.sh"
    kv("lock_script", 1 if script.exists() else 0)
    if not script.exists():
        return
    r = subprocess.run(["bash", str(script), str(d), ITEM_ID, "", "build-en-cours",
                        "un build ecrit encore", "1800", "1800",
                        "deploy-in-progress pid=4242 vivant"],
                       capture_output=True, text=True, timeout=120)
    kv("lock_script_rc", r.returncode)
    f = d / "proof-impossible.txt"
    kv("lock_file", 1 if f.exists() else 0)
    if not f.exists():
        return
    got = {}
    for line in f.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            k, v = line.split("=", 1)
            got[k] = v
    attendus = ("proof_impossible", "proof_impossible_id", "proof_impossible_reason",
                "proof_impossible_detail", "proof_impossible_wait_s",
                "proof_impossible_wait_max_s", "proof_impossible_busy_why",
                "proof_impossible_lock_pid", "proof_impossible_lock_alive",
                "proof_impossible_lock_age_s", "proof_impossible_at",
                "proof_impossible_exit")
    kv("lock_keys", sum(1 for k in attendus if k in got))
    kv("lock_keys_attendus", len(attendus))
    kv("lock_wait_echoed", 1 if got.get("proof_impossible_wait_s") == "1800" else 0)
    kv("lock_reason_echoed", 1 if got.get("proof_impossible_reason") == "build-en-cours" else 0)
    kv("lock_exit_named", 1 if got.get("proof_impossible_exit") == "3" else 0)
    # AUCUN champ de la machine : une preuve impossible ne devient pas une preuve.
    kv("lock_no_machine_field",
       0 if {"sha", "frames", "crash", "source", "binary"} & set(got) else 1)


# ======================================================== la lecture statique de proof_run ==
def arm_proof_run() -> None:
    src = AP / "lib" / "proof_run.sh"
    kv("pr_file", 1 if src.exists() else 0)
    if not src.exists():
        return
    lignes = src.read_text(encoding="utf-8", errors="replace").splitlines()
    fin_prologue = die_debut = die_fin = -1
    for i, l in enumerate(lignes):
        if "FIN-DU-PROLOGUE-SANS-DOSSIER" in l and fin_prologue < 0:
            fin_prologue = i
        if l.startswith("die3()") and die_debut < 0:
            die_debut = i
        if die_debut >= 0 and die_fin < 0 and i > die_debut and l.startswith("}"):
            die_fin = i
    kv("pr_prologue_marker", 1 if fin_prologue >= 0 else 0)
    kv("pr_die3_defined", 1 if die_debut >= 0 else 0)
    nues = [i + 1 for i, l in enumerate(lignes)
            if "exit 3" in l and i > fin_prologue >= 0
            and not (die_debut <= i <= die_fin)]
    kv("pr_bare_exit3_after_prologue", len(nues))
    kv("pr_bare_exit3_lines", ",".join(str(x) for x in nues) or "-")
    kv("pr_die3_calls", sum(1 for l in lignes if "die3 " in l and not l.startswith("die3()")))
    kv("pr_publishes_wait", sum(1 for l in lignes if 'extra "proof_wait_s=' in l))
    kv("pr_writes_wait_file", sum(1 for l in lignes if 'proof$SUF-wait.txt' in l))
    kv("pr_clears_impossible",
       sum(1 for l in lignes if 'rm -f "$OUTFILE" "$D/proof$SUF-impossible.txt"' in l))


# ============================================== le territoire, compte dans la SOURCE ========
def arm_source() -> None:
    """Combien de definitions LITTERALES du territoire moteur restent dans l'orchestrateur.

    Une liste ou un tuple qui contient a la fois 'game/' et 'goal_src/' EST une definition du
    territoire. Il doit y en avoir exactement une. Lu dans l'AST, pas par un grep : un
    commentaire qui cite la liste n'est pas une definition."""
    src = AP / "orchestrator.py"
    try:
        arbre = ast.parse(src.read_text(encoding="utf-8"))
    except (OSError, SyntaxError) as e:                     # noqa: BLE001
        kv("src_parsed", 0)
        kv("src_error", repr(e)[:150])
        return
    kv("src_parsed", 1)
    litteraux = 0
    for node in ast.walk(arbre):
        if isinstance(node, (ast.Tuple, ast.List)):
            vals = [x.value for x in node.elts
                    if isinstance(x, ast.Constant) and isinstance(x.value, str)]
            if "game/" in vals and "goal_src/" in vals:
                litteraux += 1
    kv("src_territory_literals", litteraux)

    # LE CABLAGE. Les deux portes lisent-elles VRAIMENT l'accesseur, et `run_attempt`
    # requalifie-t-il VRAIMENT ? Une garde dont la seule occurrence est son en-tete ne
    # garde rien : on cherche les APPELS, dans les corps nommes.
    corps = {}
    for node in ast.walk(arbre):
        if isinstance(node, ast.FunctionDef):
            corps[node.name] = node
    def appelle(fn: str, nom: str) -> int:
        n = corps.get(fn)
        if n is None:
            return 0
        return int(any(isinstance(c, ast.Call) and getattr(c.func, "id", "") == nom
                       for c in ast.walk(n)))
    def cite(fn: str, texte: str) -> int:
        n = corps.get(fn)
        if n is None:
            return 0
        return int(any(isinstance(c, ast.Constant) and isinstance(c.value, str)
                       and texte in c.value for c in ast.walk(n)))
    kv("src_gate_reads_accessor", appelle("close_gate", "engine_prefixes"))
    kv("src_dirty_reads_accessor", appelle("engine_dirty_paths", "engine_prefixes"))
    kv("src_gate_returns_foreign", cite("close_gate", "foreign"))
    kv("src_gate_reads_quarantine", appelle("close_gate", "load_quarantine"))
    kv("src_attempt_requalifies", appelle("run_attempt", "requalify_foreign_attempt"))
    kv("src_attempt_resets", appelle("run_attempt", "_foreign_reset"))
    kv("src_commit_reads_quarantine", appelle("git_commit_paths", "load_quarantine"))
    kv("src_commit_sets_aside", appelle("git_commit_paths", "_mettre_de_cote"))
    kv("src_loop_handles_foreign", cite("main", "foreign"))


# ============================================================ l'ancre par marqueur ==========
def before_commit(marker: str) -> tuple[str, str]:
    rel = ".autoport/orchestrator.py"
    try:
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "80",
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


def main() -> int:
    root = Path(tempfile.mkdtemp(prefix="fc-banc-"))
    try:
        commit, blob = before_commit(MARKER)
        kv("before_commit", commit[:12] or "-")
        kv("before_marker_absent", 1 if (blob and MARKER not in blob) else 0)
        old = root / "old_orchestrator.py"
        if blob:
            old.write_text(blob, encoding="utf-8")
            try:
                shutil.copyfile(AP / "model-profiles.json", root / "model-profiles.json")
            except OSError:
                pass
        else:
            old = None
        neuf = AP / "orchestrator.py"

        plan = [
            ("terr_neuf", neuf, arm_territoire, {}),
            ("terr_vieux", old, arm_territoire, {}),
            ("requal_neuf", neuf, arm_requal, dict(herite=True)),
            ("requal_vieux", old, arm_requal, dict(herite=True)),
            ("requal_propre", neuf, arm_requal, dict(herite=False)),
            ("quar_neuf", neuf, arm_quarantaine, {}),
            ("quar_vieux", old, arm_quarantaine, {}),
        ]
        for tag, src, fn, kw in plan:
            if src is None or not Path(src).exists():
                kv("%s_status" % tag, "-")
                kv("%s_ran" % tag, 0)
                continue
            try:
                fn(tag, Path(src), root, **kw)
                kv("%s_ran" % tag, 1)
            except Exception as e:                          # noqa: BLE001
                kv("%s_ran" % tag, 0)
                kv("%s_error" % tag, repr(e)[:250])
        for fn in (arm_etat_nomme,):
            try:
                fn(root)
            except Exception as e:                          # noqa: BLE001
                kv("lock_error", repr(e)[:250])
        for fn in (arm_proof_run, arm_source):
            try:
                fn()
            except Exception as e:                          # noqa: BLE001
                kv("%s_error" % fn.__name__, repr(e)[:250])
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
