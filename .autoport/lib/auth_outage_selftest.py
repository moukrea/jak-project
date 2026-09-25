#!/usr/bin/env python3
"""lib/auth_outage_selftest.py — LE BANC DE LA PANNE D'AUTHENTIFICATION
(harness-api-auth-outage-pauses-not-blocks, 25/09).

La VRAIE boucle `main()` d'orchestrator.py, sur un depot jetable (git init), un backlog jetable
(le faux `lib/backlog.py` de reference des tests, INTERFACES §5) et un faux `claude` qui rejoue
les evenements RELEVES le 25/09 sur les journaux reels : `api_retry` 401, message synthetique
« Failed to authenticate. API Error: 401 OAuth access token has been revoked. », `result` en
`api_error_status: 401`. Aucun appel reseau, aucun fichier du vrai depot n'est ecrit.

LA CASCADE (trois items ouverts A, B, C, `max_retries: 1`, validateur factice qui ECHOUE) :
  lancement 1  A travaille (un outil) puis 401 EN PLEIN TRAVAIL — lighting-local-lights essai 2
  lancement 2  401 A LA PORTE, zero travail — les 24 autres du 25/09
  lancements suivants  le worker travaille et sort : un VRAI echec, juge par le validateur.
  L'API simulee (la sonde) rend 401, 401, puis 200 : l'alerte est posee a 0 s pour que le banc
  voie qu'elle ne part qu'UNE fois sur deux sondes refusees.

DEUX BRAS
  neuf   le code courant : attendu 0 item bloque pour l'authentification, 0 essai 401 compte,
         2 pauses, 2 reprises, 1 alerte ; et les trois VRAIS echecs restent comptes (controle
         NEGATIF) — sinon la couche aurait simplement cesse de compter.
  vieux  le dernier orchestrator.py SANS le marqueur : il DOIT bloquer ou compter sur les 401,
         sinon le banc est aveugle.
Plus `neuf_404` : un 404 (modele inexistant) reste une erreur de CONFIGURATION, bloquee.
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import textwrap
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent
MARKER = "PANNE-D-AUTH/"
AUTH_RE = re.compile(r"(?i)\b40[13]\b|authentif")

SID = "banc-auth"
EV_INIT = {"type": "system", "subtype": "init", "session_id": SID, "model": "banc"}
EV_TOOL = {"type": "assistant", "message": {
    "usage": {"input_tokens": 12, "output_tokens": 34},
    "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "true"}}]}}
EV_RETRY = {"type": "system", "subtype": "api_retry", "attempt": 1, "max_retries": 10,
            "retry_delay_ms": 578, "error_status": 401, "error": "authentication_failed",
            "session_id": SID}
TXT_401 = "Failed to authenticate. API Error: 401 OAuth access token has been revoked."
EV_SYNTH = {"type": "assistant", "message": {"model": "<synthetic>", "role": "assistant",
            "content": [{"type": "text", "text": TXT_401}],
            "usage": {"input_tokens": 0, "output_tokens": 0}},
            "session_id": SID, "error": "authentication_failed"}
EV_RES_401 = {"type": "result", "subtype": "success", "is_error": True,
              "terminal_reason": "api_error", "api_error_status": 401, "result": TXT_401,
              "num_turns": 1, "duration_ms": 10, "usage": {}, "session_id": SID}
EV_RES_404 = dict(EV_RES_401, api_error_status=404,
                  result="API Error: 404 model: claude-banc-inexistant not_found_error")
EV_RES_OK = {"type": "result", "subtype": "success", "is_error": False, "num_turns": 1,
             "duration_ms": 10, "usage": {}, "session_id": SID}


def kv(key, value):
    print("%s=%s" % (key, str(value).replace("\n", " ").replace(" ", "_")[:220]))


def _fake_claude(sandbox: Path, script: list[str]) -> Path:
    """Le faux `claude -p` : le Neme lancement joue `script[N-1]` (le dernier ensuite)."""
    counter = sandbox / "launches.txt"
    bodies = {
        "mid401": [EV_INIT, EV_TOOL, EV_RETRY, EV_SYNTH, EV_RES_401],
        "door401": [EV_INIT, EV_RETRY, EV_SYNTH, EV_RES_401],
        "door404": [EV_INIT, EV_RES_404],
        "works": [EV_INIT, EV_TOOL, EV_RES_OK],
    }
    lines = ["#!/usr/bin/env bash", "cat >/dev/null",
             'n=$(( $(cat "%s" 2>/dev/null || echo 0) + 1 )); echo $n > "%s"' % (counter, counter)]
    for i, mode in enumerate(script, 1):
        cond = ('if [ "$n" -eq %d ]; then' % i) if i < len(script) else "if true; then"
        lines.append(cond)
        # Espaces : la lecture `select` + `readline` perd les lignes deja en tampon a la sortie.
        for ev in bodies[mode]:
            lines += ["  echo '%s'" % json.dumps(ev), "  sleep 0.2"]
        lines.append("  exit %d" % (0 if mode == "works" else 1))
        lines.append("fi")
    p = sandbox / "fake_claude.sh"
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")
    p.chmod(0o755)
    return p


def _load(src: Path, name: str):
    sys.path.insert(0, str(AP))
    spec = importlib.util.spec_from_file_location(name, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    return mod


def _sandbox(mod, root: Path, items: list[dict]):
    from rich.console import Console

    ap = root / ".autoport"
    for d in ("logs", "reports", "owner-ok", "validators", "prompts", "lib"):
        (ap / d).mkdir(parents=True, exist_ok=True)
    for args in (["init", "-q", "-b", "main"], ["config", "user.email", "t@t"],
                 ["config", "user.name", "t"]):
        subprocess.run(["git", *args], cwd=root, capture_output=True)
    (root / "seed.txt").write_text("seed\n")
    subprocess.run(["git", "add", "seed.txt"], cwd=root, capture_output=True)
    subprocess.run(["git", "commit", "-qm", "seed"], cwd=root, capture_output=True)

    sys.path.insert(0, str(AP / "tests" / "harness"))
    from test_selection import FAKE_BACKLOG      # noqa: PLC0415 — le faux backlog de reference
    (ap / "lib" / "backlog.py").write_text(textwrap.dedent(FAKE_BACKLOG))
    os.environ["FAKE_BACKLOG_PATH"] = str(ap / "backlog.yaml")
    sys.modules.pop("backlog", None)
    import yaml                                  # noqa: PLC0415
    (ap / "backlog.yaml").write_text(yaml.safe_dump({"version": 1, "items": items},
                                                    allow_unicode=True))
    for it in items:
        (ap / it["prompt"]).write_text("Fais la chose.\n")
    calls = ap / "validator-calls.txt"
    (ap / "validators" / "generic.sh").write_text(
        "#!/usr/bin/env bash\n"
        'printf "%s\\n" "${AUTOPORT_PHASE_ID:-?}" >> "' + str(calls) + '"\n'
        'echo "[$AUTOPORT_PHASE_ID FAIL] pas prouve (banc)"\nexit 1\n')
    (ap / "validators" / "generic.sh").chmod(0o755)
    creds = ap / "creds.json"
    creds.write_text("{}")
    profil = root / "model-profiles.json"
    profil.write_text(Path(mod._PROFILE_PATH).read_text())

    mod.console = Console(width=4000, no_color=True, force_terminal=False, highlight=False)
    for name, value in {
            "REPO_ROOT": root, "AUTOPORT_DIR": ap, "STATE_PATH": ap / "state.json",
            "BACKLOG_PATH": ap / "backlog.yaml", "BACKLOG_LIB": ap / "lib" / "backlog.py",
            "LOG_ROOT": ap / "logs", "REPORTS_DIR": ap / "reports",
            "OWNER_OK_DIR": ap / "owner-ok", "SCOPE_STAMP": ap / ".scope_stamp",
            "_PROFILE_PATH": profil, "GENERIC_VALIDATOR": ap / "validators" / "generic.sh",
            "SHIELD_GUARD": ap / "shield_guard.sh", "CREDENTIALS_PATH": creds,
            "PACING_NOW": ap / "logs" / "pacing-now.json",
            "AUTH_PAUSE_NOW": ap / "logs" / "auth-pause.json",
            "AUTH_JOURNAL": ap / "logs" / "auth-outage.jsonl",
            "HALT": False, "READ_POLL_SEC": 0.2, "AUTH_PROBE_EVERY_S": 0,
            "AUTH_ALERT_AFTER_S": 0}.items():
        setattr(mod, name, value)
    mod.build_instructions = lambda item, seq: "banc\n"
    mod.nap = lambda seconds: None
    mod.sleep_until = lambda epoch, label: None
    mod.acquire_single_instance_lock = lambda: object()   # jamais le verrou du VRAI depot
    mod.git_push = lambda: None
    return ap, calls


def _auth_blocked(ap: Path, items: list[dict]) -> tuple[list[str], dict]:
    """Items BLOQUES pour une cause d'authentification : raison qui la nomme, ou dernier essai
    termine par un refus d'authentification (le 401 compte puis « max_retries »)."""
    sys.path.insert(0, str(AP))
    from lib import auth_outage                  # noqa: PLC0415
    import yaml                                  # noqa: PLC0415
    data = yaml.safe_load((ap / "backlog.yaml").read_text())
    final = {it["id"]: it for it in data.get("items", [])}
    out = []
    for it in items:
        cur = final.get(it["id"], {})
        if cur.get("status") != "blocked":
            continue
        logs = sorted((ap / "logs" / it["id"]).glob("attempt-*.jsonl"))
        last_auth = bool(logs) and bool(auth_outage.refusal_in_file(logs[-1]))
        if AUTH_RE.search(str(cur.get("block_reason") or "")) or last_auth:
            out.append(it["id"])
    return out, final


def _attempts(ap: Path, items: list[dict]) -> dict:
    """Par essai : refus d'authentification ? validateur lance (= essai COMPTE) ?"""
    sys.path.insert(0, str(AP))
    from lib import auth_outage                  # noqa: PLC0415
    auth_counted = genuine_counted = auth_attempts = 0
    for it in items:
        for p in sorted((ap / "logs" / it["id"]).glob("attempt-*.jsonl")):
            seq = p.stem.replace("attempt-", "")
            counted = (p.parent / ("validator-%s.txt" % seq)).exists()
            if auth_outage.refusal_in_file(p):
                auth_attempts += 1
                auth_counted += int(counted)
            else:
                genuine_counted += int(counted)
    return {"auth_attempts": auth_attempts, "auth_counted": auth_counted,
            "genuine_counted": genuine_counted}


def run_cascade(src: Path, sandbox: Path, out: Path) -> int:
    items = [{"id": x, "status": "open", "priority": 10 + i, "feature": "banc " + x,
              "prompt": "prompts/item-%s.md" % x, "max_turns": 5, "max_retries": 1,
              "depends_on": []} for i, x in enumerate(("banc-a", "banc-b", "banc-c"))]
    mod = _load(src, "orch_cascade")
    ap, calls = _sandbox(mod, sandbox, items)
    fake = _fake_claude(sandbox, ["mid401", "door401", "works"])
    mod.cli_backend.worker_command = lambda *a, **k: ["bash", str(fake)]

    sys.path.insert(0, str(AP))
    from lib import auth_outage                  # noqa: PLC0415
    real_backlog = importlib.util.spec_from_file_location("_real_backlog", AP / "lib" / "backlog.py")
    rb = importlib.util.module_from_spec(real_backlog)
    real_backlog.loader.exec_module(rb)
    answers = [False, False, True, True, True, True]
    seen = []

    def fake_probe():
        """L'API simulee : 401, 401, puis 200. Ce que le statut dit PENDANT la pause est releve
        ici, par la fonction que `autoport status` appelle, sur le fichier que la boucle publie."""
        pause = ap / "logs" / "auth-pause.json"
        seen.append({"status": rb.auth_pause_line(str(pause)),
                     "digest": rb.auth_pause_digest(str(pause))})
        ok = answers[min(len(seen) - 1, len(answers) - 1)]
        return ok, ("API simulee : 200" if ok else "API simulee : 401")
    mod.auth_probe = fake_probe

    rc = mod.main([])
    journal = []
    jp = ap / "logs" / "auth-outage.jsonl"
    for raw in (jp.read_text().splitlines() if jp.exists() else []):
        try:
            journal.append(json.loads(raw))
        except ValueError:
            pass
    blocked_auth, final = _auth_blocked(ap, items)
    state = json.loads((ap / "state.json").read_text()) if (ap / "state.json").exists() else {}
    res = {"ran": 1, "rc": rc,
           "launches": int((sandbox / "launches.txt").read_text().strip() or 0)
           if (sandbox / "launches.txt").exists() else 0,
           "items_blocked_by_auth": len(blocked_auth),
           "items_blocked_by_auth_list": ",".join(blocked_auth) or "-",
           "items_blocked_total": sum(1 for v in final.values() if v.get("status") == "blocked"),
           "block_reasons": "|".join("%s:%s" % (k, str(v.get("block_reason") or "-")[:60])
                                     for k, v in sorted(final.items())),
           "retries": ",".join("%s:%s" % (k, v) for k, v in sorted(
               (state.get("retries") or {}).items())) or "-",
           "validator_calls": len(calls.read_text().split()) if calls.exists() else 0,
           "pauses": sum(1 for e in journal if e.get("event") == "pause"),
           "probes": sum(1 for e in journal if e.get("event") == "probe"),
           "alerts": sum(1 for e in journal if e.get("event") == "alert"),
           "resumes": sum(1 for e in journal if e.get("event") == "resume"),
           "status_first_probe": (seen[0]["status"].split("\n")[0][:120] if seen else "-") or "-",
           "status_has_alert_after": int(len(seen) > 1 and "ALERTE" in seen[1]["status"]),
           "digest_before_alert": seen[0]["digest"] or "-" if seen else "-",
           "digest_after_alert": (seen[1]["digest"] or "-") if len(seen) > 1 else "-",
           "status_after_run": rb.auth_pause_line(str(ap / "logs" / "auth-pause.json")) or "-"}
    res.update(_attempts(ap, items))
    out.write_text(json.dumps(res), encoding="utf-8")
    return 0


def run_404(src: Path, sandbox: Path, out: Path) -> int:
    items = [{"id": "banc-404", "status": "open", "priority": 1, "feature": "banc 404",
              "prompt": "prompts/item-banc-404.md", "max_turns": 5, "max_retries": 3,
              "depends_on": []}]
    mod = _load(src, "orch_404")
    ap, calls = _sandbox(mod, sandbox, items)
    fake = _fake_claude(sandbox, ["door404"])
    mod.cli_backend.worker_command = lambda *a, **k: ["bash", str(fake)]
    state = mod.load_state()
    outcome = mod.run_attempt(dict(items[0]), state)
    out.write_text(json.dumps({"ran": 1, "outcome": outcome.kind,
                               "reason": outcome.reason[:120]}), encoding="utf-8")
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
    root = Path(tempfile.mkdtemp(prefix="auth-banc-"))
    try:
        cur = AP / "orchestrator.py"
        kv("bench_marker_in_current", 1 if MARKER in cur.read_text() else 0)
        commit, blob = before_commit(MARKER)
        kv("bench_before_commit", commit[:12] or "-")
        old = None
        if blob:
            old = root / "old" / "orchestrator.py"
            old.parent.mkdir(parents=True)
            old.write_text(blob, encoding="utf-8")
            shutil.copyfile(AP / "model-profiles.json", old.parent / "model-profiles.json")
        arms = [("neuf", cur, "cascade"), ("vieux", old, "cascade"), ("neuf_404", cur, "404")]
        env = dict(os.environ, COLUMNS="4000")
        for k in ("AUTOPORT_PHASE_ID", "AUTOPORT_ATTEMPT_ID"):
            env.pop(k, None)
        for name, src, mode in arms:
            if src is None or not Path(src).exists():
                kv("%s_ran" % name, 0)
                continue
            sandbox, out = root / ("sb-" + name), root / ("out-" + name + ".json")
            sandbox.mkdir(parents=True)
            proc = subprocess.run([sys.executable, str(HERE), "--mode", mode, "--src", str(src),
                                   "--sandbox", str(sandbox), "--out", str(out)],
                                  cwd=str(sandbox), env=env, capture_output=True, text=True,
                                  timeout=600)
            journal = proc.stdout + proc.stderr
            if not out.exists():
                kv("%s_ran" % name, 0)
                kv("%s_rc" % name, proc.returncode)
                for line in journal.strip().splitlines()[-4:]:
                    kv("%s_stderr" % name, line.replace("=", ":")[:160])
                continue
            for key, value in json.loads(out.read_text()).items():
                kv("%s_%s" % (name, key), value)
            kv("%s_journal_says_paused" % name, 1 if "EN PAUSE : authentification" in journal else 0)
            kv("%s_journal_says_resumed" % name, 1 if "REPRISE :" in journal else 0)
            kv("%s_journal_alert_lines" % name, journal.count("ALERTE SUPERVISEUR"))
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode")
    ap.add_argument("--src")
    ap.add_argument("--sandbox")
    ap.add_argument("--out")
    a = ap.parse_args(argv)
    if a.mode == "cascade":
        return run_cascade(Path(a.src), Path(a.sandbox), Path(a.out))
    if a.mode == "404":
        return run_404(Path(a.src), Path(a.sandbox), Path(a.out))
    return bench()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
