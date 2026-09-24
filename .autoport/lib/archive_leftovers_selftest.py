#!/usr/bin/env python3
"""lib/archive_leftovers_selftest.py — LE BANC de `harness-archive-and-status-write-leftovers`.

CE QU'IL MESURE : les restes de la coupure par archivage et des ecritures de statut, chacun sur le
VRAI code (orchestrateur, synchro Linear, backlog, crochet pre-tool), dans un dossier JETABLE. Aucun
registre reel n'est ecrit (ni backlog.yaml, ni linear_map.json, ni state.json, ni registre de
commentaires) : tout vit dans un tempdir.

  c1  course lancee hors du groupe du worker (setsid, comme gk) : orpheline apres la coupure ?
  c3  ecritures dans reports/<id>/ APRES la sauvegarde du travail coupe (membre du groupe qui ignore
      SIGTERM, fenetre de detection), + le crochet pre-tool qui laisse partir un outil d'un item archive
  c4  le travail coupe est-il NOMME dans les notes de l'item (essai, « coupé », commit) ?
  c2  un message du superviseur sur le ticket d'un item archive ressort-il le ticket des archives ?
  c5  deux adoptions concurrentes d'un ticket de l'owner : id en double, ticket adopte deux fois ?
  c6  poser un champ en ramenant le statut tenu en memoire (idiome `set_status(i, it["status"], ...)`)

LES BRAS : `neuf` = fichiers du disque ; `vieux` = pour chaque fichier, le blob du dernier commit qui ne
porte PAS le marqueur `ARCHIVE-LEFTOVERS/` (ancre par MARQUEUR, jamais `HEAD:`). Le vieux doit ROUGIR.
Controles negatifs : essai sain (temoin), course d'un AUTRE essai (ciblage), crochet sur item vivant,
ticket archive faute de place (doit ressortir), adoption simple.

Sortie : `cle=valeur`, rien d'autre sur stdout.
Usage : python3 lib/archive_leftovers_selftest.py
        python3 lib/archive_leftovers_selftest.py --case C --arm A --src D --work D   (interne)
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent
MARKER = "ARCHIVE-LEFTOVERS/"
ITEM = "zzz-banc-archive-leftovers"
FILES = {  # nom publie -> chemin relatif a .autoport
    "orchestrator": "orchestrator.py",
    "backlog": "lib/backlog.py",
    "linear_sync": "linear_sync.py",
    "pre_tool": "hooks/pre-tool.sh",
}


def kv(k, v):
    print("%s=%s" % (k, str(v).replace("\n", " ")), flush=True)


def git(*a):
    return subprocess.run(["git", "-C", str(REPO), *a], capture_output=True, text=True)


def before_commit(rel: str) -> str:
    for sha in git("log", "--format=%H", "-n", "400", "--", rel).stdout.split():
        blob = git("show", "%s:%s" % (sha, rel)).stdout
        if blob and MARKER not in blob:
            return sha
    return ""


def put_backlog(path: Path, items):
    import yaml
    path.write_text(yaml.safe_dump({"version": 1, "items": items}, allow_unicode=True, sort_keys=False),
                    encoding="utf-8")


def base_item(status):
    return {"id": ITEM, "status": status, "feature": "banc d'essai du harnais", "priority": 1,
            "prompt": "prompts/banc.md", "max_retries": 6, "owner_test": False, "no_code": True,
            "gate": {"key": "banc", "op": "==", "value": 0}}


def proc_stat(pid):
    try:
        raw = Path("/proc/%d/stat" % pid).read_text()
    except OSError:
        return None
    rest = raw[raw.rfind(")") + 2:].split()
    return rest[19], rest[0]          # starttime, etat


def alive(pid, start):
    st = proc_stat(pid)
    return bool(st) and st[0] == start and st[1] != "Z"


# ------------------------------------------------------------------ c1 + c3 + c4 (+ temoin)
def case_attempt(arm: str, src: Path, sb: Path, temoin: bool) -> int:
    for d in ("logs", "reports", "prompts", "validators", "lib", "banc"):
        (sb / d).mkdir(parents=True, exist_ok=True)
    notes_dir = sb / "reports" / ITEM / "notes"
    notes_dir.mkdir(parents=True, exist_ok=True)
    (sb / "prompts" / "banc.md").write_text("consigne du banc\n", encoding="utf-8")
    for sib in (AP / "lib").glob("*.py"):
        if sib.name != "backlog.py":
            (sb / "lib" / sib.name).symlink_to(sib)
    (sb / "lib" / "backlog.py").write_text((src / "lib" / "backlog.py").read_text(), encoding="utf-8")
    rec = {k: sb / ("%s.txt" % k) for k in ("commits", "validator", "archived_at")}
    bl_path = sb / "backlog.yaml"
    sys.path.insert(0, str(sb / "lib"))
    sys.path.insert(1, str(AP))
    import backlog as BK                                  # celui du bras
    put_backlog(bl_path, [base_item("in-progress")])

    # L'ARCHIVEUR : la VRAIE apply_owner_archive du disque, dans un processus a part
    archiver = sb / "archiver.py"
    archiver.write_text(
        "import sys, time, datetime\n"
        "sys.path.insert(0, %r)\n"
        "import linear_sync as LS\n"
        "from lib import backlog as B\n"
        "t = time.time_ns()\n"
        "LS.apply_owner_archive(B.load(%r), %r, {'identifier': 'BANC-1'}, {'createdAt': datetime.datetime.now("
        "datetime.timezone.utc).isoformat()})\n"
        "open(%r, 'a').write('%%d\\n' %% t)\n" % (str(AP), str(bl_path), ITEM, str(rec["archived_at"])),
        encoding="utf-8")
    from aborted_attempt_selftest import BASE_EVENTS
    ev = [json.dumps(e) for e in BASE_EVENTS]
    head, tail = sb / "stream-head.jsonl", sb / "stream-tail.jsonl"
    head.write_text("\n".join(ev[:-1]) + "\n", encoding="utf-8")
    tail.write_text(ev[-1] + "\n", encoding="utf-8")
    gkpid = sb / "GKPID"
    fake = sb / "fake_cli.sh"
    if temoin:
        body = "cat >/dev/null ; cat %s\nsleep 1\ncat %s\nexit 0\n" % (head, tail)
    else:
        body = ("cat >/dev/null ; cat %s\n"
                "setsid bash -c 'echo \"$$ $(cut -d\" \" -f22 /proc/$$/stat)\" > %s; exec sleep 60' "
                "</dev/null >/dev/null 2>&1 &\n"
                "bash -c 'trap \"\" TERM; for i in $(seq 1 40); do date +%%s%%N > %s/w-$i.txt; sleep 0.25; done' "
                "</dev/null >/dev/null 2>&1 &\n"
                "sleep 0.3 ; python3 \"%s\" >/dev/null 2>&1 ; sleep 6 ; cat %s ; exit 0\n"
                % (head, gkpid, notes_dir, archiver, tail))
    fake.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
    (sb / "validators" / "generic.sh").write_text(
        '#!/usr/bin/env bash\ndate +%%s%%N >> "%s"\necho "[banc] validateur factice"\nexit 1\n'
        % rec["validator"], encoding="utf-8")

    spec = importlib.util.spec_from_file_location("orch_leftovers_" + arm, src / "orchestrator.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    mod.AUTOPORT_DIR = sb
    mod.LOG_ROOT = sb / "logs"
    mod.REPORTS_DIR = sb / "reports"
    mod.STATE_PATH = sb / "state.json"
    mod.GENERIC_VALIDATOR = sb / "validators" / "generic.sh"
    mod.BACKLOG_PATH = bl_path
    mod.SCOPE_STAMP = sb / ".scope_stamp"
    mod.REPO_ROOT = REPO
    mod.READ_POLL_SEC = 5.0                               # la valeur de production

    def _commit(item_id, message, paths):
        with rec["commits"].open("a") as fh:
            fh.write("%d\t%s\n" % (time.time_ns(), item_id))
        return item_id == getattr(mod, "ARCHIVE_CUT_LABEL", "\0")

    from rich.console import Console
    mod.console = Console(width=4000, no_color=True, force_terminal=False, highlight=False,
                          file=open(sb / "console.txt", "w"))
    mod.git_commit_paths = _commit
    mod.git_push = lambda: None
    mod.worker_paths = lambda: ["banc/travail-du-worker.txt"]
    mod.dirty_paths = lambda: []
    mod._progress_fingerprint = lambda item_id: "banc"
    mod.build_instructions = lambda item, seq: "banc d'essai\n"
    mod.judge_measure = lambda *a, **k: None
    mod.close_gate = lambda item, *a, **k: ("fail", "porte factice du banc")
    mod.implementation_fingerprint = lambda root: "banc"
    mod.cli_backend.worker_command = lambda *a, **k: ["bash", str(fake)]
    if hasattr(mod, "_head_sha"):
        mod._head_sha = lambda: "banc5ha000"

    foreign = None
    if arm == "neuf" and not temoin:   # controle de CIBLAGE : la course d'un AUTRE essai survit
        # (sleep direct en session neuve : `setsid` lance d'un chef de session FORKE, le pid serait le parent mort)
        p = subprocess.Popen(["sleep", "60"], env={**os.environ,
                             "AUTOPORT_ATTEMPT_ID": "autre-essai@1#1"}, start_new_session=True,
                             stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        time.sleep(0.2)
        st = proc_stat(p.pid)
        foreign = (p.pid, st[0] if st else "")
        kv("c1_neuf_foreign_pid", p.pid)

    item = {"id": ITEM, "prompt": "prompts/banc.md", "max_retries": 6, "max_turns": 10,
            "feature": "banc d'essai du harnais", "no_code": True,
            "gate": {"key": "banc", "op": "==", "value": 0}}
    state = mod.load_state()
    r0 = int(state.get("retries", {}).get(ITEM, 0) or 0)
    real_stdout = sys.stdout
    sys.stdout = sys.stderr                               # rien d'autre que des kv sur stdout
    try:
        out = mod.run_attempt(item, state)
    finally:
        sys.stdout = real_stdout
    t_ret = time.time_ns()
    notes = (BK.load(bl_path).get(ITEM) or {}).get("notes") or ""

    if temoin:
        st = mod.load_state()
        vcalls = len([ln for ln in rec["validator"].read_text().splitlines() if ln.strip()]) \
            if rec["validator"].exists() else 0
        kv("temoin_outcome", out.kind)
        kv("temoin_validator_calls", vcalls)
        kv("temoin_retries_delta", int(st.get("retries", {}).get(ITEM, 0) or 0) - r0)
        kv("temoin_note_cut", int("coupé" in notes))
        return 0

    time.sleep(8)
    P = "%s_" % arm
    # c1 : la course lancee par setsid
    gk_alive = 0
    try:
        pid_s, start = gkpid.read_text().split()[:2]
        gk_pid = int(pid_s)
        gk_alive = int(alive(gk_pid, start))
    except (OSError, ValueError):
        gk_pid, start = 0, ""
        kv("c1_" + P + "gkpid_missing", 1)
    kv("c1_" + P + "gk_alive", gk_alive)
    kv("c1_" + P + "gk_pid", gk_pid or "-")
    kv("c1_" + P + "defect", gk_alive)
    if gk_pid and alive(gk_pid, start):
        try:
            os.kill(gk_pid, signal.SIGKILL)
        except OSError:
            pass
    if foreign:
        kv("c1_neuf_foreign_alive", int(alive(*foreign)))
        try:
            os.kill(foreign[0], signal.SIGKILL)
        except OSError:
            pass

    # c3 : ecritures apres la sauvegarde
    commits = [ln.split("\t") for ln in rec["commits"].read_text().splitlines()] if rec["commits"].exists() else []
    cut = getattr(mod, "ARCHIVE_CUT_LABEL", "\0")
    t_save = next((int(c[0]) for c in commits if len(c) > 1 and c[1] == cut), None)
    kv("c3_" + P + "save_found", int(t_save is not None))
    t_save = t_save or t_ret
    t_arch = min((int(x) for x in rec["archived_at"].read_text().split()), default=None) \
        if rec["archived_at"].exists() else None
    kv("c3_" + P + "archived", int(t_arch is not None))
    files = [p for p in (sb / "reports" / ITEM).rglob("*") if p.is_file()]
    after_save = sum(1 for p in files if p.stat().st_mtime_ns > t_save)
    after_arch = sum(1 for p in files if t_arch is not None and p.stat().st_mtime_ns > t_arch)
    kv("c3_" + P + "writes_after_save", after_save)
    kv("c3_" + P + "writes_after_archive", after_arch)
    kv("c3_" + P + "detect_s", "%.2f" % ((t_ret - t_arch) / 1e9) if t_arch else "-")
    hook_leaks, live_refusals = hook_calls(src, sb)
    kv("c3_" + P + "hook_leaks", hook_leaks)
    kv("c3_" + P + "hook_live_refusals", live_refusals)
    kv("c3_" + P + "defect", after_save + hook_leaks)

    # c4 : le travail coupe est nomme
    kv("c4_" + P + "outcome", out.kind)
    kv("c4_" + P + "seq", out.seq)
    ok = ("essai %s" % out.seq) in notes and "coupé" in notes and "banc5ha000" in notes
    last = (notes.strip().splitlines() or ["-"])[-1]
    kv("c4_" + P + "note", "_".join(last.split())[:200] or "-")
    kv("c4_" + P + "defect", 0 if ok else 1)
    return 0


def hook_calls(src: Path, sb: Path):
    """(appels NON refuses sur item archive, appels refuses sur item vivant) du pre-tool.sh DU BRAS."""
    hook = src / "hooks" / "pre-tool.sh"
    hb = sb / "hook-backlog.yaml"
    tmpd = sb / "hook-tmp"
    tmpd.mkdir(exist_ok=True)
    sids = ["banc-leftovers-%d-w" % os.getpid(), "banc-leftovers-%d-b" % os.getpid()]
    calls = [{"tool_name": "Write", "tool_input": {"file_path": "/x/.autoport/reports/%s/notes/a.txt" % ITEM},
              "session_id": sids[0]},
             {"tool_name": "Bash", "tool_input": {"command": "echo hi"}, "session_id": sids[1]}]
    env = {**os.environ, "AUTOPORT_PHASE_ID": ITEM, "AUTOPORT_BACKLOG": str(hb),
           "CLAUDE_PROJECT_DIR": str(REPO), "TMPDIR": str(tmpd)}
    res = {}
    for status in ("archived", "in-progress"):
        put_backlog(hb, [base_item(status)])
        rcs = [subprocess.run(["bash", str(hook)], input=json.dumps(c), env=env, capture_output=True,
                              text=True, timeout=60).returncode for c in calls]
        res[status] = rcs
    # l'etat par session du crochet (compteur de lectures) : seulement NOS sessions
    for d in (tmpd, Path(os.environ.get("TMPDIR", "/tmp")), Path("/tmp")):
        for s in sids:
            f = d / ("autoport-lecture-" + s)
            if f.exists():
                f.unlink()
    return (sum(1 for rc in res["archived"] if rc != 2), sum(1 for rc in res["in-progress"] if rc != 0))


# ------------------------------------------------------------------ import de linear_sync DU BRAS
def load_ls(src: Path, work: Path):
    os.environ.pop("AUTOPORT_PHASE_ID", None)            # le superviseur, pas un essai
    sys.path.insert(0, str(src / ".autoport"))
    import linear_sync as LS
    for name in ("HOME",):
        if hasattr(LS, name):
            setattr(LS, name, work)
    if hasattr(LS, "MAP_PATH"):
        LS.MAP_PATH = work / "linear_map.json"
    if hasattr(LS, "SHADOW_PATH"):
        LS.SHADOW_PATH = work / ".linear_map.shadow.json"
    if hasattr(LS, "OCAP"):
        LS.OCAP.record = lambda *a, **k: None
    LS.with_room = lambda L, fn, what: fn()
    return LS


class FakeL:
    def __init__(self, archived):
        self.archived, self.unarchived, self.comments = archived, 0, 0
        self.mode = "app"

    def q(self, query, **v):
        if "issueUnarchive" in query:
            self.unarchived += 1
            self.archived = False
            return {"issueUnarchive": {"success": True}}
        if "commentCreate" in query:
            if self.archived:
                raise RuntimeError("Entity not found: Issue")
            self.comments += 1
            return {"commentCreate": {"success": True, "comment": {"id": "c1"}}}
        if "team(id" in query:
            return {"team": {"issues": {"pageInfo": {"hasNextPage": False, "endCursor": None}, "nodes": [{
                "id": "ISS-NEW", "identifier": "JAK-900", "title": "Mon ticket", "description": "d",
                "createdAt": "2026-09-24T00:00:00Z", "creator": {"id": "owner", "app": False},
                "state": {"name": "Todo", "type": "unstarted"}}]}}}
        raise RuntimeError("requete inattendue du banc : %s" % query[:80])


def case2(arm, src, work):
    LS = load_ls(src, work)
    B = LS.B
    bl = work / "backlog.yaml"
    real = sys.stdout
    for label, status, rec in (
            ("", "archived", {"issue_id": "ISS-1", "identifier": "BANC-1",
                              "owner_archived_at": "2026-09-24T00:00:00Z"}),
            ("live_", "in-progress", {"issue_id": "ISS-1", "identifier": "BANC-1",
                                      "harness_archived_at": "2026-09-24T00:00:00Z"})):
        put_backlog(bl, [base_item(status)])
        LS._CTX["mp"] = {ITEM: rec}
        LS._CTX["bl"] = B.load(bl)
        L = FakeL(archived=True)
        sys.stdout = sys.stderr
        try:
            LS.post_comment(L, "ISS-1", "bonjour")
        finally:
            sys.stdout = real
        if label:
            kv("c2_%s_live_revived" % arm, L.unarchived)
            kv("c2_%s_live_posted" % arm, L.comments)
        else:
            kv("c2_%s_posted" % arm, L.comments)
            kv("c2_%s_defect" % arm, L.unarchived)
    return 0


def case5(arm, src, work):
    import yaml
    LS = load_ls(src, work)
    B = LS.B
    LS._say = lambda *a, **k: None
    LS.swap_labels = lambda *a, **k: None
    LS.save_map = lambda *a, **k: None
    LS.classify_unmapped = lambda iss, bl, mp: ("owner", None)
    other = {"id": "zzz-autre", "status": "open", "feature": "autre", "priority": 5, "prompt": "prompts/banc.md"}
    real = sys.stdout

    def disk_items(p):
        return yaml.safe_load(p.read_text())["items"]

    def adopt(p, bl):
        sys.stdout = sys.stderr
        try:
            return LS.adopt_owner_issues(FakeL(False), bl, {}, "T", "todo", False)
        finally:
            sys.stdout = real

    p = work / "backlog.yaml"
    put_backlog(p, [other])
    stale = B.load(p)
    with B._Lock(str(p)):                                 # un AUTRE ecrivain, entre la lecture et l'adoption
        fresh = B._read(str(p))
        fresh["items"].append({"id": "owner-mon-ticket", "status": "open", "feature": "autre ticket",
                               "priority": 999})
        B._atomic_write(str(p), B._dump(fresh))
    adopt(p, stale)
    stale2 = B.load(p)
    adopt(p, stale2)
    items = disk_items(p)
    ids = [it["id"] for it in items]
    dup = sum(ids.count(i) - 1 for i in set(ids))
    carrying = sum(1 for it in items if it.get("feature") == "Mon ticket")
    kv("c5_%s_dup_ids" % arm, dup)
    kv("c5_%s_carrying" % arm, carrying)
    kv("c5_%s_ids" % arm, "|".join(i for i in ids if i.startswith("owner-")) or "-")
    kv("c5_%s_defect" % arm, dup + max(0, carrying - 1))
    if arm == "neuf":
        q = work / "neg-backlog.yaml"
        put_backlog(q, [other])
        adopt(q, B.load(q))
        new = [it for it in disk_items(q) if it["id"] != "zzz-autre"]
        kv("c5_neuf_neg_new", len(new))
        kv("c5_neuf_neg_id", "|".join(it["id"] for it in new) or "-")
    return 0


# ------------------------------------------------------------------ c6
def case6(arm, src, work):
    sys.path.insert(0, str(src / "lib"))
    import backlog as B
    p = work / "backlog.yaml"
    put_backlog(p, [base_item("in-progress")])
    bk = B.load(p)
    mem = bk.get(ITEM)["status"]
    B.load(p).set_status(ITEM, "to-test")                 # l'autre ecrivain
    try:
        if hasattr(bk, "set_field"):
            bk.set_field(ITEM, "proof_props", ["a=1"])
        else:
            bk.set_status(ITEM, mem, proof_props=["a=1"])  # l'idiome d'avant
        kv("c6_%s_write_err" % arm, "-")
    except Exception as e:  # noqa: BLE001
        kv("c6_%s_write_err" % arm, "_".join(("%s:%s" % (type(e).__name__, e)).split())[:160])
    it = B.load(p).get(ITEM) or {}
    kv("c6_%s_disk_status" % arm, it.get("status"))
    dyn = int(it.get("status") != "to-test") + int(it.get("proof_props") != ["a=1"])
    kv("c6_%s_dynamic" % arm, dyn)
    if arm == "neuf":
        try:
            bk.set_field(ITEM, "status", "open")
            refused = 0
        except B.BacklogError:
            refused = 1
        kv("c6_neuf_refuses_status", refused)
        seed = work / "seed.py"
        seed.write_text('b.set_status(i, it["status"], x=1)\n')
        kv("c6_static_seed", len(static_callers([seed])))
        named = static_callers(static_files())
        kv("c6_static_callers", len(named))
        kv("c6_static_named", ",".join(named) or "-")
        kv("c6_neuf_defect", dyn + len(named))
    else:
        kv("c6_vieux_defect", dyn)
    return 0


def static_files():
    out = []
    for p in AP.rglob("*.py"):
        rel = p.relative_to(AP).parts
        if rel[0] in ("archive", "tmp", "logs"):
            continue
        if rel[0] == "reports" and "notes" not in rel[1:-1]:
            continue
        out.append(p)
    return out


def _status_read(n):
    if isinstance(n, ast.Subscript):
        s = n.slice
        s = getattr(s, "value", s) if not isinstance(s, ast.Constant) else s
        return isinstance(s, ast.Constant) and s.value == "status"
    if isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "get" and n.args:
        return isinstance(n.args[0], ast.Constant) and n.args[0].value == "status"
    return False


def static_callers(files):
    named = []
    for f in files:
        try:
            tree = ast.parse(f.read_text(encoding="utf-8", errors="replace"))
        except (SyntaxError, ValueError, OSError):
            continue
        for n in ast.walk(tree):
            if not (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute) and n.func.attr == "set_status"):
                continue
            arg = n.args[1] if len(n.args) > 1 else next((k.value for k in n.keywords if k.arg == "status"), None)
            if arg is not None and _status_read(arg):
                try:
                    rel = f.relative_to(AP)
                except ValueError:
                    rel = f.name
                named.append("%s:%d" % (rel, n.lineno))
    return named


# ------------------------------------------------------------------ l'orchestre
def build_src(d: Path, blobs: dict):
    (d / "lib").mkdir(parents=True)
    (d / "hooks").mkdir()
    (d / ".autoport").mkdir()
    for side in ("model-profiles.json", "settings.json"):   # lus par l'orchestrateur a cote de lui
        if (AP / side).exists():
            (d / side).symlink_to(AP / side)
    (d / "orchestrator.py").write_text(blobs["orchestrator"])
    (d / "lib" / "backlog.py").write_text(blobs["backlog"])
    for sib in (AP / "lib").glob("*.py"):
        if sib.name != "backlog.py":
            (d / "lib" / sib.name).symlink_to(sib)
    (d / "hooks" / "pre-tool.sh").write_text(blobs["pre_tool"])
    for sib in (AP / "hooks").iterdir():
        if sib.suffix == ".py":
            (d / "hooks" / sib.name).symlink_to(sib)
    # linear_sync DU BRAS dans un `.autoport` jetable : AP = parent/.autoport ; aucun registre lie
    la = d / ".autoport"
    (la / "linear_sync.py").write_text(blobs["linear_sync"])
    (la / "lib").symlink_to(AP / "lib")
    for sib in AP.glob("*.py"):
        if sib.name != "linear_sync.py":
            (la / sib.name).symlink_to(sib)


def full() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="banc-leftovers-"))
    shas = {n: before_commit(".autoport/" + rel) for n, rel in FILES.items()}
    for n, s in shas.items():
        kv("before_commit_" + n, s[:10] or "-")
    srcs = {}
    for arm in ("vieux", "neuf"):
        blobs = {}
        for n, rel in FILES.items():
            if arm == "neuf":
                blobs[n] = (AP / rel).read_text()
            else:
                blobs[n] = git("show", "%s:.autoport/%s" % (shas[n], rel)).stdout if shas[n] else ""
        srcs[arm] = tmp / ("src-" + arm)
        build_src(srcs[arm], blobs)
    runs = [("c134", "vieux"), ("c134", "neuf"), ("temoin", "neuf"), ("c2", "vieux"), ("c2", "neuf"),
            ("c5", "vieux"), ("c5", "neuf"), ("c6", "vieux"), ("c6", "neuf")]
    for case, arm in runs:
        work = tmp / ("%s-%s" % (case, arm))
        work.mkdir()
        try:
            r = subprocess.run([sys.executable, str(HERE), "--case", case, "--arm", arm,
                                "--src", str(srcs[arm]), "--work", str(work)],
                               capture_output=True, text=True, timeout=300, cwd=str(work))
            rc, so, se = r.returncode, r.stdout, r.stderr
        except subprocess.TimeoutExpired as e:
            rc, so, se = 124, (e.stdout or b"").decode(errors="replace") if isinstance(e.stdout, bytes) else (e.stdout or ""), ""
        for ln in so.splitlines():
            k = ln.split("=", 1)[0]
            if "=" in ln and k.replace("_", "").isalnum():
                print(ln, flush=True)
        kv("%s_%s_rc" % (case, arm), rc)
        if rc:
            ef = tmp / ("%s-%s.err" % (case, arm))
            ef.write_text(so[-4000:] + "\n---\n" + se[-8000:])
            kv("%s_%s_err" % (case, arm), ef)
    kv("sandbox", tmp)
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--case")
    ap.add_argument("--arm")
    ap.add_argument("--src")
    ap.add_argument("--work")
    a = ap.parse_args()
    if a.case:
        src, work = Path(a.src), Path(a.work)
        if a.case == "c134":
            sys.exit(case_attempt(a.arm, src, work, temoin=False))
        if a.case == "temoin":
            sys.exit(case_attempt(a.arm, src, work, temoin=True))
        sys.exit({"c2": case2, "c5": case5, "c6": case6}[a.case](a.arm, src, work))
    sys.exit(full())
