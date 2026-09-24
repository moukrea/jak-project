#!/usr/bin/env python3
"""lib/pacing_selftest.py — LE BANC DU FREIN D'USAGE (harness-copes-with-usage-pacing, 24/09).

Le VRAI `run_attempt` d'orchestrator.py, sur un etat jetable, avec un faux worker qui lance un
FAUX crochet de rythme : un processus dont la ligne de commande porte `pacing-hook --provider
claude`, exactement comme celui de l'owner, et qui dort. Aucun fichier de resetdeck n'est lu ni
touche : le vrai crochet n'entre pas dans ce banc.

LE TEMPS EST MIS A L'ECHELLE : 1 s de banc = 15 min reelles. Les gardes sont posees a leur
valeur reelle divisee d'autant (NO_PROGRESS_SEC 45 min -> 3 s, STALL_HARD_SEC 30 min -> 2 s),
et le faux crochet « dort 60 min » -> 4 s. Les deux codes voient les MEMES bornes.

CINQ BRAS
  neuf_frein   (CONTROLE POSITIF) crochet de 60 min puis resultat : l'essai n'est PAS tue, et
               le temps freine est publie (journal d'essai + ligne de statut PENDANT la pause).
  vieux_frein  le meme worker sous le code d'AVANT (dernier orchestrator.py sans le marqueur) :
               il DOIT etre tue — sinon le banc est aveugle.
  neuf_fige    (CONTROLE NEGATIF) worker fige SANS crochet : toujours tue par la garde.
  neuf_mort    le worker meurt PENDANT la pause (crochet encore vivant) : ni compte, ni
               empreinte, pas de validateur.
  vieux_mort   le meme sous le code d'avant : il DOIT etre compte — sinon le banc est aveugle.
  neuf_reprise crochet de 60 min puis worker fige : la garde REPREND et le tue.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
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
MARKER = "FREIN-D-USAGE/"
ITEM_ID = "zzz-banc-frein-d-usage"
SCALE_S_PER_MIN = 1.0 / 15.0          # 1 s de banc = 15 min reelles
HOOK_MIN = 60
NO_PROGRESS_MIN, STALL_HARD_MIN = 45, 30

EV_INIT = {"type": "system", "subtype": "init", "session_id": "banc-frein", "model": "banc"}
EV_TOOL = {"type": "assistant", "message": {
    "usage": {"input_tokens": 12, "output_tokens": 34},
    "content": [{"type": "tool_use", "id": "t1", "name": "Bash",
                 "input": {"command": "true"}}]}}
EV_RESULT = {"type": "result", "is_error": False, "num_turns": 2, "duration_ms": 1234,
             "total_cost_usd": 0.01, "usage": {"input_tokens": 1, "output_tokens": 2}}


def kv(key, value):
    print("%s=%s" % (key, value))


def _fake_worker(sandbox: Path, mode: str) -> Path:
    """Le faux `claude -p`. Le crochet est un processus FILS, comme celui de l'owner."""
    hook_s = HOOK_MIN * SCALE_S_PER_MIN
    probe = sandbox / "status-during-pause.txt"
    hook = ("python3 -c 'import sys,time; time.sleep(float(sys.argv[1]))' %s "
            "pacing-hook --provider claude") % "%s"
    status_probe = ("(sleep %.2f; python3 -c 'import sys; sys.path.insert(0, sys.argv[1]); "
                    "from lib import backlog; print(backlog.pacing_line(sys.argv[2]))' "
                    "%s %s > %s 2>&1) &" % (hook_s * 0.7, AP, sandbox / "logs" / "pacing-now.json",
                                            probe))
    # Les evenements sont ESPACES : la boucle de lecture de l'orchestrateur (`select` sur le fd
    # puis `readline` bufferise) perd les lignes deja en tampon quand le processus sort, et
    # le bras d'avant se classait une fois sur trois « sorti sans rien faire » (FINDINGS).
    lines = ["#!/usr/bin/env bash", "cat >/dev/null",
             "echo '%s'" % json.dumps(EV_INIT), "sleep 0.3",
             "echo '%s'" % json.dumps(EV_TOOL), "sleep 0.3"]
    if mode == "frein":
        lines += [status_probe, hook % ("%.2f" % hook_s), "echo '%s'" % json.dumps(EV_RESULT),
                  "exit 0"]
    elif mode == "fige":
        lines += ["sleep %.2f" % (hook_s * 2), "echo '%s'" % json.dumps(EV_RESULT), "exit 0"]
    elif mode == "mort":
        lines += ["%s &" % (hook % ("%.2f" % hook_s)), "sleep 0.8", "exit 1"]
    elif mode == "reprise":
        lines += [hook % ("%.2f" % hook_s), "sleep %.2f" % (hook_s * 2),
                  "echo '%s'" % json.dumps(EV_RESULT), "exit 0"]
    p = sandbox / ("fake_worker_%s.sh" % mode)
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return p


def _patch(mod, sandbox: Path, calls: Path):
    from rich.console import Console

    mod.console = Console(width=4000, no_color=True, force_terminal=False, highlight=False)
    mod.AUTOPORT_DIR = sandbox
    mod.LOG_ROOT = sandbox / "logs"
    mod.REPORTS_DIR = sandbox / "reports"
    mod.STATE_PATH = sandbox / "state.json"
    mod.GENERIC_VALIDATOR = sandbox / "validators" / "generic.sh"
    mod.BACKLOG_PATH = sandbox / "backlog.yaml"
    mod.PACING_NOW = sandbox / "logs" / "pacing-now.json"
    mod.REPO_ROOT = REPO
    # Les bornes, mises a l'echelle, IDENTIQUES pour les deux codes.
    mod.NO_PROGRESS_SEC = NO_PROGRESS_MIN * SCALE_S_PER_MIN
    mod.STALL_HARD_SEC = STALL_HARD_MIN * SCALE_S_PER_MIN
    mod.READ_POLL_SEC = 0.2
    mod.EXIT_WAIT_SEC = 5.0
    mod.PACING_PUBLISH_AFTER_S = 1.0 * SCALE_S_PER_MIN * 15   # 15 min reelles -> 1 s
    mod.git_commit_paths = lambda *a, **k: False
    mod.git_push = lambda: None
    mod.worker_paths = lambda: []
    mod.dirty_paths = lambda: []
    mod.engine_dirty_paths = lambda: []
    mod.close_gate = lambda *a, **k: ("fail", "porte factice du banc")
    mod._scope_changed = lambda seen=None: ""
    mod._archived_on_disk = lambda *a, **k: False
    mod._progress_fingerprint = lambda item_id: "banc"     # rien ne bouge : la garde doit juger
    mod.build_instructions = lambda item, seq: "banc d'essai\n"
    mod.write_minimal_handoff = lambda *a, **k: None
    mod.implementation_fingerprint = lambda root: "banc"
    mod.wait_for_proof_writer = lambda *a, **k: (0, 0)
    mod.proof_freshness = lambda *a, **k: {"trigger": ""}
    mod.judge_measure = lambda *a, **k: None
    if hasattr(mod, "impossible_state"):
        mod.impossible_state.purge = lambda *a, **k: {"purged": [], "standing": []}
    del calls


def run_arm(arm: str, src: Path, mode: str, sandbox: Path, out: Path) -> int:
    for d in ("logs", "reports", "prompts", "validators"):
        (sandbox / d).mkdir(parents=True, exist_ok=True)
    (sandbox / "prompts" / "banc.md").write_text("consigne du banc\n", encoding="utf-8")
    calls = sandbox / "validator-calls.txt"
    (sandbox / "validators" / "generic.sh").write_text(
        "#!/usr/bin/env bash\n"
        'printf "%s\\n" "${AUTOPORT_PHASE_ID:-?}" >> "' + str(calls) + '"\n'
        'echo "[banc] validateur factice"\nexit 1\n', encoding="utf-8")
    worker = _fake_worker(sandbox, mode)

    sys.path.insert(0, str(AP))
    spec = importlib.util.spec_from_file_location("orch_arm_" + arm, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    _patch(mod, sandbox, calls)
    mod.cli_backend.worker_command = lambda *a, **k: ["bash", str(worker)]

    item = {"id": ITEM_ID, "prompt": "prompts/banc.md", "max_retries": 6, "max_turns": 10,
            "feature": "banc du frein d'usage", "no_code": True}
    state = mod.load_state()
    t0 = time.monotonic()
    outcome = mod.run_attempt(item, state)
    wall = time.monotonic() - t0
    after = mod.load_state()
    seq = int(after.get("attempt_seq", {}).get(ITEM_ID, 0) or 0)
    end = {}
    log_path = sandbox / "logs" / ITEM_ID / ("attempt-%03d.jsonl" % seq)
    for raw in (log_path.read_text(errors="replace").splitlines() if log_path.exists() else []):
        try:
            ev = json.loads(raw)
        except ValueError:
            continue
        if ev.get("event") == "attempt_end":
            end = ev
    pacing_rec = end.get("pacing") or {}
    probe = sandbox / "status-during-pause.txt"
    # APRES l'essai : le fichier publie doit etre parti, ou du moins ne plus etre CRU.
    sys.path.insert(0, str(AP))
    from lib import backlog as _bk                         # noqa: PLC0415
    status_after = _bk.pacing_line(str(sandbox / "logs" / "pacing-now.json"))
    result = {
        "ran": 1, "outcome": outcome.kind, "reason": outcome.reason[:160],
        "abort_reason": end.get("abort_reason", "?") or "-",
        "abort_paced": int(bool(end.get("abort_paced"))),
        "killed": 1 if (end.get("abort_reason") or "") in (
            "no-progress", "hard-silence", "post-result", "exit-stall", "tool-budget") else 0,
        "retries_delta": int(after.get("retries", {}).get(ITEM_ID, 0) or 0),
        "fingerprints_delta": len(after.get("fingerprints", {}).get(ITEM_ID, []) or []),
        "validator_calls": len(calls.read_text().split()) if calls.exists() else 0,
        "paced_total_s": pacing_rec.get("total_s", -1),
        "paced_total_min": (round(float(pacing_rec["total_s"]) / SCALE_S_PER_MIN, 1)
                            if "total_s" in pacing_rec else -1),
        "paced_episodes": pacing_rec.get("episodes", -1),
        "paced_active_at_end": int(bool(pacing_rec.get("active_at_end"))),
        "state_paced_void": int((after.get("paced", {}).get(ITEM_ID) or {}).get("void", 0) or 0),
        "status_during_pause": (probe.read_text().strip().replace("=", ":")[:120]
                                if probe.exists() else "-") or "-",
        "status_after": status_after.replace("=", ":")[:80] or "-",
        "wall_s": round(wall, 1),
    }
    out.write_text(json.dumps(result), encoding="utf-8")
    return 0


def before_commit(marker: str) -> tuple[str, str]:
    """Le dernier commit de orchestrator.py qui ne porte PAS le marqueur (jamais `HEAD:`)."""
    rel = ".autoport/orchestrator.py"
    try:
        hist = subprocess.run(["git", "-C", str(REPO), "log", "--format=%H", "-n", "80",
                               "--", rel], capture_output=True, text=True,
                              timeout=60).stdout.split()
    except (OSError, subprocess.SubprocessError):
        return "", ""
    for commit in hist:
        blob = subprocess.run(["git", "-C", str(REPO), "show", "%s:%s" % (commit, rel)],
                              capture_output=True, text=True, timeout=60).stdout
        if blob and marker not in blob:
            return commit, blob
    return "", ""


def bench() -> int:
    root = Path(tempfile.mkdtemp(prefix="pacing-banc-"))
    try:
        cur = AP / "orchestrator.py"
        kv("bench_marker_in_current", 1 if MARKER in cur.read_text() else 0)
        commit, blob = before_commit(MARKER)
        kv("bench_before_commit", commit[:12] or "-")
        old = None
        if blob:
            old = root / "old_orchestrator.py"
            old.write_text(blob, encoding="utf-8")
            try:
                shutil.copyfile(AP / "model-profiles.json", root / "model-profiles.json")
            except OSError:
                pass
        kv("bench_scale", "1s=15min")
        kv("bench_guard_no_progress_s", NO_PROGRESS_MIN * SCALE_S_PER_MIN)
        kv("bench_guard_hard_silence_s", STALL_HARD_MIN * SCALE_S_PER_MIN)
        kv("bench_hook_min", HOOK_MIN)
        arms = [("neuf_frein", cur, "frein"), ("vieux_frein", old, "frein"),
                ("neuf_fige", cur, "fige"), ("neuf_mort", cur, "mort"),
                ("vieux_mort", old, "mort"), ("neuf_reprise", cur, "reprise")]
        env = dict(os.environ, COLUMNS="4000")
        env.pop("AUTOPORT_PHASE_ID", None)
        env.pop("AUTOPORT_ATTEMPT_ID", None)
        for name, src, mode in arms:
            if src is None or not Path(src).exists():
                kv("%s_ran" % name, 0)
                continue
            sandbox, out = root / ("sb-" + name), root / ("out-" + name + ".json")
            proc = subprocess.run([sys.executable, str(HERE), "--arm", name, "--src", str(src),
                                   "--mode", mode, "--sandbox", str(sandbox), "--out", str(out)],
                                  cwd=str(REPO), env=env, capture_output=True, text=True,
                                  timeout=300)
            journal = proc.stdout + proc.stderr
            if not out.exists():
                kv("%s_ran" % name, 0)
                kv("%s_rc" % name, proc.returncode)
                for line in journal.strip().splitlines()[-4:]:
                    kv("%s_stderr" % name, line.replace("=", ":")[:160])
                continue
            for key, value in json.loads(out.read_text()).items():
                kv("%s_%s" % (name, key), str(value).replace("\n", " ").replace(" ", "_")[:200])
            kv("%s_journal_says_paused" % name, 1 if "EN PAUSE : frein d'usage" in journal else 0)
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm")
    ap.add_argument("--src")
    ap.add_argument("--mode")
    ap.add_argument("--sandbox")
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    if a.arm:
        return run_arm(a.arm, Path(a.src), a.mode, Path(a.sandbox), Path(a.out))
    return bench()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
