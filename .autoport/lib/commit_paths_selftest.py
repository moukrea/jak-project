#!/usr/bin/env python3
"""lib/commit_paths_selftest.py — LE BANC de `harness-commit-paths-all-or-nothing`.

CE QU'IL FAIT. Il fait tourner le VRAI `git_commit_paths` et la VRAIE `close_gate` de
l'orchestrateur sur des DEPOTS GIT JETABLES, face a un lot qui contient le chemin
impossible du 12/09 — REPRODUIT par un `git rm` reel, jamais simule par un drapeau.
Rien n'est simule du cote juge : c'est le code qui tournera en production qui decide,
et on lit ce que git a ECRIT (`git log`, `git show --name-only`, `git status`).

LE DEFAUT REPRODUIT. `git rm f` retire f de l'arbre ET indexe sa suppression : f n'existe
alors ni dans l'arbre ni dans l'index. Un `git add -- f` (meme avec -A) sort en FATAL
« le chemin 'f' ne correspond a aucun fichier ». L'ancien `git_commit_paths` faisait UN
SEUL `git add` pour les 64 chemins sales : le fatal emportait les 63 autres.

LES BRAS, et pourquoi :

  vieux_lot   orchestrator.py au dernier commit SANS le marqueur `COMMIT_PATHS_STATS`,
              lot AVEC le chemin impossible. TEMOIN D'AVANT : zero fichier commite, HEAD
              immobile, les 8 chemins toujours sales. Ancre par MARQUEUR et jamais a
              `HEAD:` — une fois ce chantier commite, HEAD porte le correctif et le temoin
              s'accuserait lui-meme des le deuxieme essai.
  neuf_lot    orchestrator.py sur le disque, MEME depot, MEME lot. Les 8 changements
              commites, 6 chemins indexes, 2 refus NOMMES avec la raison de git.
  vieux_ok /  les deux codes sur un lot SANS chemin impossible. CONTROLE POSITIF : la
  neuf_ok     difference entre les deux premiers bras vient du chemin impossible, pas du
              bras. Sans lui, un correctif qui casserait le cas normal passerait la porte.
  vieux_vide/ un lot ou RIEN n'est indexe (un chemin propre). Le garde-fou d'avant,
  neuf_vide   `git diff --cached --pathspec-from-file`, N'EXISTE PAS dans git (sortie 129,
              usage) : il ne valait donc JAMAIS 0 et le commit vide partait quand meme
              jusqu'a git. Le neuf le DIT et le compte.
  porte_*     GATE 0 : la porte de fermeture refuse de conclure quand l'arbre reste sale
              sur des chemins moteur herites. Trois vantages — le neuf avec heritage
              (doit REFUSER), le neuf SANS heritage mais avec l'arbre sale du travail de
              l'item (ne doit PAS refuser : sinon faux rouge systematique), et le vieux
              avec heritage (ne connait pas la porte).

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun champ
de proof.txt ; `lib/census/harness-commit-paths-all-or-nothing.sh` fait la somme.
"""
from __future__ import annotations

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
MARKER = "COMMIT_PATHS_STATS"
ITEM_ID = "zzz-banc-commit-paths"

# Les chemins du scenario. Trois modifies, trois neufs, deux SUPPRIMES-INDEXES (les
# impossibles). Les noms sont ceux de l'incident : c'est PbrTestPattern.cpp qui a fait
# sortir git en fatal le 12/09 a 02:26.
TRACKED = [
    "game/graphics/opengl_renderer/Loader.cpp",
    "common/util/FileUtil.cpp",
    "android/app/src/main/cpp/native.cpp",
]
IMPOSSIBLE = [
    "game/graphics/opengl_renderer/loader/PbrTestPattern.cpp",
    "game/graphics/shaders/pbr_fused.glsl",
]
UNTRACKED = [
    "goal_src/jak1/pc/banc-neuf.gc",
    "game/graphics/BancNeuf.cpp",
    "common/banc_neuf.h",
]
CLEAN = "game/graphics/Propre.cpp"


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


def make_repo(root: Path, *, impossible: bool) -> Path:
    """Un depot jetable dans l'etat EXACT ou l'incident a eu lieu."""
    repo = root
    repo.mkdir(parents=True, exist_ok=True)
    git(repo, "init", "-q", ".", check=True)
    git(repo, "config", "user.email", "banc@autoport", check=True)
    git(repo, "config", "user.name", "banc", check=True)
    git(repo, "config", "commit.gpgsign", "false", check=True)
    for rel in TRACKED + IMPOSSIBLE + [CLEAN]:
        write(repo, rel, "// origine\n")
    git(repo, "add", "-A", check=True)
    git(repo, "commit", "-q", "-m", "origine", check=True)
    for rel in TRACKED:                       # ' M'
        write(repo, rel, "// origine\n// modifie par l'essai\n")
    for rel in UNTRACKED:                     # '??'
        write(repo, rel, "// neuf\n")
    if impossible:
        for rel in IMPOSSIBLE:                # 'D ' : ni dans l'arbre, ni dans l'index
            git(repo, "rm", "-q", "--", rel, check=True)
    return repo


def load(src: Path, name: str, repo: Path, journal: list):
    """L'orchestrateur, charge depuis `src`, branche sur le depot jetable."""
    sys.path.insert(0, str(AP))
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[name] = mod
    spec.loader.exec_module(mod)
    mod.REPO_ROOT = repo
    mod.AUTOPORT_DIR = repo / ".autoport-banc"     # pas d'acquis/, pas d'owner-ok/
    mod.log = lambda msg, *a, **k: journal.append(str(msg))
    mod._reread_item = lambda iid, fallback: fallback
    return mod


def state_of(repo: Path) -> dict:
    head = git(repo, "log", "--format=%H").stdout.split()
    files = []
    if head:
        files = [x for x in git(repo, "show", "--name-only", "--format=", "HEAD")
                 .stdout.splitlines() if x.strip()]
    dirty = [x[3:] for x in git(repo, "status", "--porcelain=v1", "-uall").stdout.splitlines()]
    return {"commits": len(head), "files": sorted(files), "dirty": sorted(dirty)}


# ============================================================ un bras de commit ==========
def arm_commit(tag: str, src: Path, root: Path, *, impossible: bool, vide: bool) -> None:
    repo = make_repo(root / ("repo-" + tag), impossible=impossible)
    journal: list = []
    mod = load(src, "orch_" + tag, repo, journal)

    before = state_of(repo)
    if vide:
        paths = [CLEAN]                       # suivi, PROPRE : rien a indexer sous lui
    else:
        paths = mod.worker_paths()
    kv("%s_paths" % tag, len(paths))
    kv("%s_before_commits" % tag, before["commits"])

    ret = mod.git_commit_paths(ITEM_ID, "banc", paths)
    after = state_of(repo)
    jt = "\n".join(journal)

    kv("%s_ran" % tag, 1)
    kv("%s_returned" % tag, 1 if ret else 0)
    kv("%s_head_moved" % tag, after["commits"] - before["commits"])
    kv("%s_committed" % tag, len(after["files"]) if after["commits"] > before["commits"] else 0)
    kv("%s_committed_list" % tag,
       ",".join(after["files"]) if after["commits"] > before["commits"] else "-")
    kv("%s_dirty_after" % tag, len(after["dirty"]))
    stats = getattr(mod, "COMMIT_PATHS_STATS", None)
    kv("%s_stats" % tag, 1 if stats is not None else 0)
    for key in ("indexed", "refused", "rescued", "empty_avoided", "commits", "batches"):
        kv("%s_%s" % (tag, key), (stats or {}).get(key, -1))
    refused_paths = [r[0] for r in (stats or {}).get("last_refused", [])]
    kv("%s_refused_list" % tag, ",".join(refused_paths) or "-")
    # LE JOURNAL, tel qu'il est sorti. Un refus doit y etre DIT, chemin et raison.
    kv("%s_journal_lines" % tag, len(journal))
    kv("%s_journal_names_path" % tag,
       1 if all(Path(p).name in jt for p in (IMPOSSIBLE if impossible else [])) else 0)
    kv("%s_journal_says_empty" % tag, 1 if "COMMIT VIDE" in jt else 0)
    kv("%s_journal_says_perpath" % tag, 1 if "CHEMIN PAR CHEMIN" in jt else 0)
    kv("%s_journal_says_commit_failed" % tag, 1 if "git commit a" in jt else 0)
    # LA RAISON DE GIT, pas une phrase a nous : on refait echouer le meme `git add` et on
    # verifie que ce que git a dit se retrouve MOT POUR MOT dans le journal.
    if impossible:
        r = git(repo, "add", "--", IMPOSSIBLE[0])
        reason = " ".join(((r.stderr or r.stdout) or "").split())
        kv("%s_git_reason_len" % tag, len(reason))
        kv("%s_journal_quotes_git" % tag, 1 if reason and reason[:120] in " ".join(jt.split()) else 0)
    (root / ("journal-" + tag + ".txt")).write_text(jt, encoding="utf-8")


# ============================================================ un bras de porte ===========
def arm_gate(tag: str, src: Path, root: Path, *, baseline_from_tree: bool) -> None:
    repo = make_repo(root / ("repo-" + tag), impossible=False)
    journal: list = []
    mod = load(src, "orchg_" + tag, repo, journal)
    item = {"id": ITEM_ID, "no_code": True, "device": False, "owner_test": True,
            "feature": "banc de la porte"}

    # La ligne de base est mesuree PAR LE BANC, pas par le module juge : les deux bras
    # recoivent ainsi exactement la MEME entree, y compris celui qui n'a pas le helper.
    tree = sorted(x[3:] for x in git(repo, "status", "--porcelain=v1", "-uall")
                  .stdout.splitlines()
                  if x[3:].startswith(("game/", "common/", "android/", "goal_src/", "goalc/")))
    baseline = tree if baseline_from_tree else []
    kv("%s_tree_dirty" % tag, len(tree))
    kv("%s_baseline" % tag, len(baseline))
    kv("%s_has_helper" % tag, 1 if hasattr(mod, "foreign_dirty_engine_paths") else 0)
    try:
        status, reason = mod.close_gate(item, baseline)
        accepts = 1
    except TypeError:
        status, reason = mod.close_gate(item)      # le code d'AVANT n'a pas d'argument
        accepts = 0
    kv("%s_accepts_baseline" % tag, accepts)
    kv("%s_status" % tag, status)
    kv("%s_is_gate0" % tag, 1 if "CLOSE-GATE/arbre-sale" in reason else 0)
    kv("%s_reason_names_paths" % tag,
       1 if all(Path(p).name in reason for p in TRACKED[:1]) else 0)
    kv("%s_reason" % tag, " ".join(reason.split())[:200] or "-")


# ============================================================ l'ancre par marqueur =======
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
    root = Path(tempfile.mkdtemp(prefix="cp-banc-"))
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
        neuf = AP / "orchestrator.py"

        plan = [
            ("vieux_lot", old, dict(impossible=True, vide=False)),
            ("neuf_lot", neuf, dict(impossible=True, vide=False)),
            ("vieux_ok", old, dict(impossible=False, vide=False)),
            ("neuf_ok", neuf, dict(impossible=False, vide=False)),
            ("vieux_vide", old, dict(impossible=False, vide=True)),
            ("neuf_vide", neuf, dict(impossible=False, vide=True)),
        ]
        for tag, src, kw in plan:
            if src is None or not Path(src).exists():
                kv("%s_ran" % tag, 0)
                continue
            try:
                arm_commit(tag, Path(src), root, **kw)
            except Exception as e:                       # noqa: BLE001
                kv("%s_ran" % tag, 0)
                kv("%s_error" % tag, repr(e)[:200])

        gates = [("porte_neuf_herite", neuf, True),
                 ("porte_neuf_propre", neuf, False),
                 ("porte_vieux_herite", old, True)]
        for tag, src, base in gates:
            if src is None or not Path(src).exists():
                kv("%s_status" % tag, "-")
                continue
            try:
                arm_gate(tag, Path(src), root, baseline_from_tree=base)
            except Exception as e:                       # noqa: BLE001
                kv("%s_status" % tag, "-")
                kv("%s_error" % tag, repr(e)[:200])
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
