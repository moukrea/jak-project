#!/usr/bin/env python3
"""lib/owner_archive_selftest.py — LE BANC de `harness-owner-archive-of-running-item-is-safe`.

CE QU'IL FAIT. Il fait tourner le VRAI `run_attempt` de l'orchestrateur sur un etat JETABLE (backlog,
state.json, journaux, validateur dans un dossier temporaire) face a une fausse CLI, et l'item est
ARCHIVE en plein essai par la VRAIE `linear_sync.apply_owner_archive` — la fonction qui applique
l'archivage de l'owner en production. Puis il pose le statut que la boucle `main` DU BRAS ecrit pour
l'issue rendue (lu dans le code du bras par l'AST, jamais recopie ici), et il compte ce qui a ete
ECRIT apres l'archivage.

UN EFFET DE BORD = une ecriture au nom de l'item posterieure a l'archivage :
  commit      `git_commit_paths` appele avec l'id de l'item (le travail sauve sous ARCHIVE_CUT_LABEL
              n'est PAS au nom de l'item : il est compte a part, `saved_work`)
  validateur  le validateur lance apres l'archivage (un verdict)
  juge        `judge_measure` lance apres l'archivage (une mesure de verdict)
  retries     l'essai compte dans le budget
  empreinte   une empreinte d'echec ajoutee
  handoff     `reports/<id>/handoff.md` ecrit apres l'archivage
  statut      le statut final n'est plus `archived` (l'archivage de l'owner defait)

LES BRAS :
  vieux   orchestrator.py + lib/backlog.py au dernier commit SANS le marqueur `ARCHIVE-OWNER/`,
          archive pendant le worker. Temoin d'AVANT : il doit ROUGIR, sinon un zero ne dirait pas si
          le piege est desarme ou s'il n'a jamais existe. Ancre par MARQUEUR, jamais `HEAD:`.
  neuf    code du disque, archive pendant le worker : l'essai doit etre COUPE (pas attendu).
  juge    code du disque, archive PENDANT le validateur (le validateur factice archive puis sort).
  porte   code du disque, archive PENDANT la porte de fermeture : `retries` deja compte, a rendre.
  temoin  code du disque, AUCUN archivage : l'essai doit etre juge et compte comme avant
          (controle negatif : une detection qui couperait tout serait un vert par INACTION).
  seme    code du disque, detection NEUTRALISEE (`_archived_on_disk` -> False), archive pendant le
          worker : controle POSITIF, doit rougir et NOMMER ses effets.

Sortie : `cle=valeur`. Ce banc ne juge rien et n'ecrit aucun champ de proof.txt.
Usage : python3 lib/owner_archive_selftest.py
        python3 lib/owner_archive_selftest.py --arm <nom> --src D --sandbox D   (interne)
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent
MARKER = "ARCHIVE-OWNER/"
ITEM_ID = "zzz-banc-owner-archive"
WORKER_SLEEP_S = 6          # ce que le faux worker « travaille » APRES l'archivage
ARMS = {  # nom -> (source, etape d'archivage, detection neutralisee)
    "vieux": ("vieux", "worker", False),
    "neuf": ("neuf", "worker", False),
    "juge": ("neuf", "validateur", False),
    "porte": ("neuf", "porte", False),
    "temoin": ("neuf", "", False),
    "seme": ("neuf", "worker", True),
}
CHANNELS = ("commit", "validateur", "juge", "retries", "empreinte", "handoff", "statut")

sys.path.insert(0, str(AP / "lib"))
from aborted_attempt_selftest import BASE_EVENTS  # noqa: E402  le meme flux realiste


def kv(k, v):
    print("%s=%s" % (k, v), flush=True)


def git(*a):
    return subprocess.run(["git", "-C", str(REPO), *a], capture_output=True, text=True)


def before_commit(rel: str) -> str:
    """Le dernier commit dont `rel` ne porte PAS le marqueur (le code d'avant ce chantier)."""
    for sha in git("log", "--format=%H", "-n", "400", "--", rel).stdout.split():
        blob = git("show", "%s:%s" % (sha, rel)).stdout
        if blob and MARKER not in blob:
            return sha
    return ""


# ------------------------------------------------------------- la boucle main DU BRAS, lue par l'AST
def main_write_for(src: str, kind: str):
    """(appel, statut) que la boucle `main` du bras ecrit pour `out.kind == kind`, ou None si la
    branche n'ecrit aucun statut. Lu dans le code du bras : une recopie ici mesurerait la recopie."""
    tree = ast.parse(src)
    fn = next(n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name == "main")

    def kinds_of(test):
        if not (isinstance(test, ast.Compare) and isinstance(test.left, ast.Attribute)
                and test.left.attr == "kind"):
            return None
        c = test.comparators[0]
        if isinstance(c, ast.Constant):
            return {c.value}
        if isinstance(c, (ast.Tuple, ast.List)):
            return {e.value for e in c.elts if isinstance(e, ast.Constant)}
        return None

    def first_write(body):
        for node in body:
            for sub in ast.walk(node):
                if not isinstance(sub, ast.Call):
                    continue
                f = sub.func
                name = f.attr if isinstance(f, ast.Attribute) else getattr(f, "id", "")
                pos = {"set_status": 1, "_write_status": 2, "pronounce_gate": 2}.get(name)
                if pos is not None and len(sub.args) > pos and isinstance(sub.args[pos], ast.Constant):
                    return name, sub.args[pos].value
        return None

    for node in ast.walk(fn):
        if isinstance(node, ast.If) and kinds_of(node.test):
            cur = node
            while isinstance(cur, ast.If) and kinds_of(cur.test) is not None:
                if kind in kinds_of(cur.test):
                    return first_write(cur.body)
                if len(cur.orelse) == 1 and isinstance(cur.orelse[0], ast.If):
                    cur = cur.orelse[0]
                else:
                    return first_write(cur.orelse)     # le `else:  # fail`
            break
    return None


# ------------------------------------------------------------------------------------ un bras
def run_arm(arm: str, src_dir: Path, sandbox: Path) -> int:
    _, stage, neutralise = ARMS[arm]
    for d in ("logs", "reports", "prompts", "validators", "lib"):
        (sandbox / d).mkdir(parents=True, exist_ok=True)
    (sandbox / "prompts" / "banc.md").write_text("consigne du banc\n", encoding="utf-8")
    # le backlog.py DU BRAS, entoure des modules freres du disque (il en charge par chemin relatif)
    for sib in (AP / "lib").glob("*.py"):
        if sib.name != "backlog.py" and not (sandbox / "lib" / sib.name).exists():
            (sandbox / "lib" / sib.name).symlink_to(sib)
    (sandbox / "lib" / "backlog.py").write_text((src_dir / "backlog.py").read_text(), encoding="utf-8")
    rec = {k: sandbox / ("%s.txt" % k) for k in ("commits", "validator", "judge", "archived_at")}
    bl_path = sandbox / "backlog.yaml"

    # le backlog du bras en tete : c'est LUI que l'orchestrateur du bras relira
    sys.path.insert(0, str(sandbox / "lib"))
    sys.path.insert(1, str(AP))
    import yaml
    import backlog as BK                               # celui du bras
    bl_path.write_text(yaml.safe_dump({"version": 1, "items": [{
        "id": ITEM_ID, "feature": "banc d'essai du harnais", "status": "in-progress", "priority": 1,
        "prompt": "prompts/banc.md", "max_retries": 6, "owner_test": False, "no_code": True,
        "gate": {"key": "banc", "op": "==", "value": 0}}]}, allow_unicode=True), encoding="utf-8")

    # L'ARCHIVEUR : la VRAIE apply_owner_archive, dans un processus a part (comme la synchro)
    archiver = sandbox / "archiver.py"
    archiver.write_text(
        "import sys, time, datetime\n"
        "sys.path.insert(0, %r)\n"
        "import linear_sync as LS\n"
        "from lib import backlog as B\n"
        "t = time.time_ns()\n"
        "rec = {'identifier': 'BANC-1'}\n"
        "LS.apply_owner_archive(B.load(%r), %r, rec, {'createdAt': datetime.datetime.now("
        "datetime.timezone.utc).isoformat()})\n"
        "open(%r, 'a').write('%%d\\n' %% t)\n" % (str(AP), str(bl_path), ITEM_ID, str(rec["archived_at"])),
        encoding="utf-8")
    arch_cmd = 'python3 "%s" >/dev/null 2>&1' % archiver

    ev = [json.dumps(e) for e in BASE_EVENTS]
    head, tail = sandbox / "stream-head.jsonl", sandbox / "stream-tail.jsonl"
    head.write_text("\n".join(ev[:-1]) + "\n", encoding="utf-8")
    tail.write_text(ev[-1] + "\n", encoding="utf-8")
    fake_cli = sandbox / "fake_cli.sh"
    fake_cli.write_text("#!/usr/bin/env bash\ncat >/dev/null\ncat %s\n%s\nsleep %d\ncat %s\nexit 0\n"
                        % (head, arch_cmd if stage == "worker" else ":", WORKER_SLEEP_S, tail),
                        encoding="utf-8")
    (sandbox / "validators" / "generic.sh").write_text(
        "#!/usr/bin/env bash\n"
        'date +%%s%%N >> "%s"\n%s\necho "[banc] validateur factice"\nexit 1\n'
        % (rec["validator"], arch_cmd if stage == "validateur" else ":"), encoding="utf-8")

    spec = importlib.util.spec_from_file_location("orch_banc_" + arm, src_dir / "orchestrator.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    mod.AUTOPORT_DIR = sandbox
    mod.LOG_ROOT = sandbox / "logs"
    mod.REPORTS_DIR = sandbox / "reports"
    mod.STATE_PATH = sandbox / "state.json"
    mod.GENERIC_VALIDATOR = sandbox / "validators" / "generic.sh"
    mod.BACKLOG_PATH = bl_path
    mod.SCOPE_STAMP = sandbox / ".scope_stamp"
    mod.REPO_ROOT = REPO                               # cwd du faux CLI ; git est neutralise
    mod.READ_POLL_SEC = 0.5

    def _commit(item_id, message, paths):
        with rec["commits"].open("a") as fh:
            fh.write("%d\t%s\t%s\n" % (time.time_ns(), item_id, message.replace("\n", " ")))
        return False

    def _judge(item, iid, token, judge, journal=None):
        with rec["judge"].open("a") as fh:
            fh.write("%d\n" % time.time_ns())

    def _gate(item, *a, **k):
        if stage == "porte":
            subprocess.run(["bash", "-c", arch_cmd])
        return ("fail", "porte factice du banc")

    from rich.console import Console
    mod.console = Console(width=4000, no_color=True, force_terminal=False, highlight=False)
    mod.git_commit_paths = _commit
    mod.git_push = lambda: None
    # l'arbre REEL porte le travail d'autres chantiers : le banc en donne un faux, a lui
    mod.worker_paths = lambda: ["banc/travail-du-worker.txt"]
    mod.dirty_paths = lambda: []
    mod._progress_fingerprint = lambda item_id: "banc"
    mod.build_instructions = lambda item, seq: "banc d'essai\n"
    mod.judge_measure = _judge
    mod.close_gate = _gate
    mod.implementation_fingerprint = lambda root: "banc"
    mod.cli_backend.worker_command = lambda *a, **k: ["bash", str(fake_cli)]
    if neutralise:
        mod._archived_on_disk = lambda _iid: False     # LE DEFAUT SEME : l'orchestrateur ne voit rien

    item = {"id": ITEM_ID, "prompt": "prompts/banc.md", "max_retries": 6, "max_turns": 10,
            "feature": "banc d'essai du harnais", "no_code": True,
            "gate": {"key": "banc", "op": "==", "value": 0}}
    state = mod.load_state()
    r0 = int(state.get("retries", {}).get(ITEM_ID, 0) or 0)
    f0 = len(state.get("fingerprints", {}).get(ITEM_ID, []) or [])
    t0 = time.monotonic()
    out = mod.run_attempt(item, state)
    elapsed = time.monotonic() - t0

    # la boucle `main` DU BRAS pose son statut pour cette issue
    bk = BK.load(bl_path)
    write = main_write_for((src_dir / "orchestrator.py").read_text(encoding="utf-8"), out.kind)
    write_rc = "aucun"
    if write:
        callee, status = write
        extra = {"block_reason": out.reason or "banc"} if status == "blocked" else {}
        try:
            if callee == "_write_status":
                write_rc = "ecrit" if mod._write_status(bk, ITEM_ID, status, **extra) else "refuse"
            elif callee == "pronounce_gate":
                mod.pronounce_gate(bk, ITEM_ID, status, "porte-tenue", out.seq, out.journal)
                write_rc = "ecrit"
            else:
                bk.set_status(ITEM_ID, status, **extra)
                write_rc = "ecrit"
        except BK.BacklogError as e:
            write_rc = "refuse:%s" % type(e).__name__

    st = mod.load_state()
    lines = lambda p: [ln.split("\t") for ln in p.read_text().splitlines() if ln.strip()] if p.exists() else []
    t_arch = min((int(x[0]) for x in lines(rec["archived_at"])), default=None)
    after = (lambda t: t_arch is not None and int(t) > t_arch)
    commits = lines(rec["commits"])
    eff = {c: 0 for c in CHANNELS}
    final = (BK.load(bl_path).get(ITEM_ID) or {}).get("status")
    if t_arch is not None:
        eff["commit"] = sum(1 for c in commits if after(c[0]) and c[1] == ITEM_ID)
        eff["validateur"] = sum(1 for c in lines(rec["validator"]) if after(c[0]))
        eff["juge"] = sum(1 for c in lines(rec["judge"]) if after(c[0]))
        eff["retries"] = max(0, int(st.get("retries", {}).get(ITEM_ID, 0) or 0) - r0)
        eff["empreinte"] = max(0, len(st.get("fingerprints", {}).get(ITEM_ID, []) or []) - f0)
        ho = sandbox / "reports" / ITEM_ID / "handoff.md"
        eff["handoff"] = int(ho.exists() and ho.stat().st_mtime_ns > t_arch)
        eff["statut"] = int(final != "archived")
    end = {}
    logf = sandbox / "logs" / ITEM_ID / ("attempt-%03d.jsonl" % int(out.seq or st.get("attempt_seq", {}).get(ITEM_ID, 0) or 0))
    for p in sorted((sandbox / "logs" / ITEM_ID).glob("attempt-*.jsonl")):
        logf = p
    for raw in (logf.read_text(errors="replace").splitlines() if logf.exists() else []):
        try:
            e = json.loads(raw)
        except ValueError:
            continue
        if isinstance(e, dict) and e.get("event") == "attempt_end":
            end = e
    kv("arm", arm)
    kv("stage", stage or "aucun")
    kv("archived", int(t_arch is not None))
    kv("outcome", out.kind)
    kv("reason", " ".join((out.reason or "-").split())[:200])
    kv("elapsed_s", "%.1f" % elapsed)
    kv("abort_reason", end.get("abort_reason") or "-")
    kv("main_write", "%s:%s" % write if write else "aucun")
    kv("main_write_rc", write_rc)
    kv("final_status", final)
    kv("validator_calls", len(lines(rec["validator"])))
    kv("retries_delta", int(st.get("retries", {}).get(ITEM_ID, 0) or 0) - r0)
    kv("saved_work", sum(1 for c in commits if c[1] == getattr(mod, "ARCHIVE_CUT_LABEL", "\0")))
    kv("commit_labels", "|".join(c[1] for c in commits) or "-")
    for c in CHANNELS:
        kv("eff_" + c, eff[c])
    kv("side_effects", sum(eff.values()))
    kv("side_effects_named", ",".join("%s:%d" % (c, eff[c]) for c in CHANNELS if eff[c]) or "-")
    return 0


# ---------------------------------------------------------------- les gardes des ecrivains du worker
def guards(tmp: Path):
    """Le commentaire Linear et le commit d'un ESSAI sur un item archive : refuses. Controle negatif :
    item vivant, et hors essai (superviseur), rien n'est refuse."""
    import yaml
    sys.path.insert(0, str(AP))
    bl_path = tmp / "guard-backlog.yaml"

    def put(status):
        bl_path.write_text(yaml.safe_dump({"version": 1, "items": [{
            "id": ITEM_ID, "feature": "banc", "status": status, "priority": 1,
            "prompt": "prompts/banc.md"}]}), encoding="utf-8")
    worker, superviseur = {"AUTOPORT_PHASE_ID": ITEM_ID}, {}
    from lib import backlog as B
    try:
        import linear_sync as LS
        cref = getattr(LS, "worker_comment_refused", None)
    except Exception:  # noqa: BLE001
        cref = None
    import archived_commit_guard as G
    res = {}
    for status in ("archived", "in-progress"):
        put(status)
        for who, env in (("worker", worker), ("superviseur", superviseur)):
            res["comment_%s_%s" % (status, who)] = int(bool(cref and cref(B.load(bl_path), ITEM_ID, env)))
            res["commit_%s_%s" % (status, who)] = int(bool(G.refused("[autoport/%s] x" % ITEM_ID, bl_path, env)))
    # LE VRAI CHEMIN DE PRODUCTION : git appelle le hook du depot
    hook = AP / "hooks" / "git" / "commit-msg"
    repo = tmp / "guard-repo"
    subprocess.run(["git", "init", "-q", str(repo)], check=True)
    rcs = {}
    for status in ("archived", "in-progress"):
        put(status)
        (repo / "f.txt").write_text(status)
        subprocess.run(["git", "-C", str(repo), "add", "f.txt"], check=True)
        env = {**os.environ, "AUTOPORT_PHASE_ID": ITEM_ID, "AUTOPORT_BACKLOG": str(bl_path),
               "GIT_AUTHOR_NAME": "banc", "GIT_AUTHOR_EMAIL": "banc@local",
               "GIT_COMMITTER_NAME": "banc", "GIT_COMMITTER_EMAIL": "banc@local"}
        hooks_only = tmp / "hooks-only"
        hooks_only.mkdir(exist_ok=True)
        dst = hooks_only / "commit-msg"
        if not dst.exists():
            dst.symlink_to(hook)
        r = subprocess.run(["git", "-C", str(repo), "-c", "core.hooksPath=%s" % hooks_only,
                            "commit", "-q", "-m", "[autoport/%s] banc" % ITEM_ID], env=env,
                           capture_output=True, text=True)
        rcs[status] = r.returncode
    installed = (REPO / ".git" / "hooks" / "commit-msg")
    res["hook_git_refused_archived"] = int(rcs.get("archived", 0) != 0)
    res["hook_git_refused_live"] = int(rcs.get("in-progress", 0) != 0)
    res["hook_installed"] = int(installed.exists() and installed.resolve() == hook.resolve())
    return res


# ------------------------------------------------------------------------------------ l'orchestre
def full() -> int:
    tmp = Path(tempfile.mkdtemp(prefix="banc-archive-"))
    shas = {rel: before_commit(".autoport/" + rel) for rel in ("orchestrator.py", "lib/backlog.py")}
    kv("before_commit_orchestrator", shas["orchestrator.py"][:10] or "-")
    kv("before_commit_backlog", shas["lib/backlog.py"][:10] or "-")
    srcs = {"neuf": tmp / "src-neuf", "vieux": tmp / "src-vieux"}
    for d in srcs.values():
        d.mkdir()
        # ce que l'orchestrateur lit a cote de lui-meme (profil de modele, reglages)
        for side in ("model-profiles.json", "settings.json"):
            if (AP / side).exists():
                (d / side).symlink_to(AP / side)
    (srcs["neuf"] / "orchestrator.py").write_text((AP / "orchestrator.py").read_text())
    (srcs["neuf"] / "backlog.py").write_text((AP / "lib" / "backlog.py").read_text())
    for rel, name in (("orchestrator.py", "orchestrator.py"), ("lib/backlog.py", "backlog.py")):
        blob = git("show", "%s:.autoport/%s" % (shas[rel], rel)).stdout if shas[rel] else ""
        (srcs["vieux"] / name).write_text(blob)
    for arm, (src, _, _) in ARMS.items():
        r = subprocess.run([sys.executable, str(HERE), "--arm", arm, "--src", str(srcs[src]),
                            "--sandbox", str(tmp / ("arm-" + arm))],
                           capture_output=True, text=True, timeout=300)
        got = 0
        for ln in r.stdout.splitlines():
            if "=" in ln and not ln.startswith(" ") and ln.split("=", 1)[0].replace("_", "").isalnum():
                k, v = ln.split("=", 1)
                if k in ("arm",):
                    continue
                print("%s_%s=%s" % (arm, k, v))
                got += 1
        kv("%s_rc" % arm, r.returncode)
        kv("%s_keys" % arm, got)
        if r.returncode:
            (tmp / ("arm-%s.err" % arm)).write_text(r.stdout[-4000:] + r.stderr[-4000:])
            kv("%s_err" % arm, str(tmp / ("arm-%s.err" % arm)))
    for k, v in guards(tmp).items():
        kv("guard_" + k, v)
    kv("sandbox", tmp)
    return 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm")
    ap.add_argument("--src")
    ap.add_argument("--sandbox")
    a = ap.parse_args()
    if a.arm:
        sys.exit(run_arm(a.arm, Path(a.src), Path(a.sandbox)))
    sys.exit(full())
