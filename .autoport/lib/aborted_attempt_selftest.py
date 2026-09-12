#!/usr/bin/env python3
"""lib/aborted_attempt_selftest.py — LE BANC A QUATRE BRAS de `harness-aborted-attempt-not-counted`.

CE QU'IL FAIT. Il fait tourner le VRAI `run_attempt` de l'orchestrateur sur un etat
JETABLE (logs, state.json et validateur dans un dossier temporaire), face a une fausse
CLI qui rejoue un flux d'evenements enregistre. Rien n'est simule du cote juge : c'est
le code qui tournera en production qui decide, et on lit ce qu'il a ECRIT.

LES QUATRE BRAS, et pourquoi quatre :

  vieux   orchestrator.py au dernier commit SANS le marqueur `BG_ABORT_RE`, flux AVEC
          la ligne du lanceur. C'est le TEMOIN D'AVANT : il doit COMPTER l'essai et
          LANCER le validateur. Sans lui, un zero ne dirait pas si le piege a ete
          desarme ou s'il n'a jamais existe. Ancre par MARQUEUR et jamais a `HEAD:` :
          une fois ce chantier commite, `HEAD` porte le correctif et le temoin
          s'accuserait lui-meme des le deuxieme essai.

  neuf    orchestrator.py sur le disque, MEME FLUX. Il doit RECONNAITRE l'abandon, ne
          PAS toucher `retries`, ne PAS empreinter, et ne PAS lancer le validateur.

  temoin  orchestrator.py sur le disque, flux SANS la ligne du lanceur. Controle
          positif : un essai ordinaire est toujours compte et toujours juge. Sans ce
          bras, une reconnaissance qui abandonnerait TOUS les essais passerait la
          porte — un vert par INACTION.

  borne   orchestrator.py sur le disque, le MEME flux abandonne joue CINQ fois sur un
          seul etat. Un essai aborte ne coute rien au budget : sans garde-fou, un
          worker qui laisse toujours des taches de fond ferait tourner son item sans
          fin. Attendu : aborted, aborted, aborted, fail, aborted.

LA BORNE EST POSEE A UNE VALEUR IMPROBABLE (1234000 ms) dans l'environnement des bras :
le journal doit citer la borne EN VIGUEUR, pas une constante recopiee. Si le message
sortait une valeur en dur, le temoin de journal tomberait.

Sortie : des lignes `cle=valeur` sur stdout. Ce script ne juge rien et n'ecrit aucun
champ de proof.txt ; `lib/census/harness-aborted-attempt-not-counted.sh` fait la somme.

Usage : python3 lib/aborted_attempt_selftest.py            (banc complet)
        python3 lib/aborted_attempt_selftest.py --arm <nom> --src F --stream F --sandbox D --out F
"""
from __future__ import annotations

import argparse
import importlib.util
import json
import os
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve()
AP = HERE.parent.parent
REPO = AP.parent
MARKER = "BG_ABORT_RE"
CEILING_MS = "1234000"          # improbable expres : le journal doit citer CELLE-CI
ITEM_ID = "zzz-banc-aborted-attempt"

ABORT_LINE = ("Background tasks still running after 600s; terminating. "
              "Set CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 to wait indefinitely.")

# Un flux minimal mais REALISTE : une session, un outil (pour que `did_work` soit vrai),
# un `result`. La seule difference entre les deux flux est la ligne nue du lanceur.
BASE_EVENTS = [
    {"type": "system", "subtype": "init", "session_id": "banc-0000", "model": "banc"},
    {"type": "assistant", "message": {
        "usage": {"input_tokens": 12, "output_tokens": 34, "cache_read_input_tokens": 5},
        "content": [{"type": "tool_use", "id": "t1", "name": "Bash",
                     "input": {"command": "cmake --build build --target gk -j"}}]}},
    {"type": "result", "is_error": False, "num_turns": 2, "duration_ms": 1234,
     "total_cost_usd": 0.01, "usage": {"input_tokens": 1, "output_tokens": 2}},
]


def kv(key, value):
    print("%s=%s" % (key, value))


# ============================================================ un bras =========
def _patch(mod, sandbox: Path, calls: Path, labels: Path):
    """Le meme detournement pour tous les bras : etat jetable, git muet, validateur bidon."""
    from rich.console import Console

    mod.console = Console(width=4000, no_color=True, force_terminal=False, highlight=False)
    mod.AUTOPORT_DIR = sandbox
    mod.LOG_ROOT = sandbox / "logs"
    mod.REPORTS_DIR = sandbox / "reports"
    mod.STATE_PATH = sandbox / "state.json"
    mod.GENERIC_VALIDATOR = sandbox / "validators" / "generic.sh"
    mod.BACKLOG_PATH = sandbox / "backlog.yaml"
    mod.REPO_ROOT = REPO                      # cwd du faux CLI ; git est neutralise

    def _commit(item_id, message, paths):
        with labels.open("a", encoding="utf-8") as fh:
            fh.write(message + "\n")
        return False                          # False => pas de git_push

    mod.git_commit_paths = _commit
    mod.git_push = lambda: None
    mod.worker_paths = lambda: []
    mod.dirty_paths = lambda: []
    mod.close_gate = lambda item: ("fail", "porte factice du banc")
    mod._scope_changed = lambda seen=None: ""
    mod._progress_fingerprint = lambda item_id: "banc"
    mod.build_instructions = lambda item, seq: "banc d'essai\n"
    mod.write_minimal_handoff = lambda *a, **k: None
    mod.implementation_fingerprint = lambda root: "banc"   # sinon on re-hashe tout le depot
    del calls                                  # compte par le stub bash, pas ici


def run_arm(arm: str, src: Path, stream: Path, sandbox: Path, out: Path,
            repeat: int = 1) -> int:
    sandbox.mkdir(parents=True, exist_ok=True)
    (sandbox / "logs").mkdir(exist_ok=True)
    (sandbox / "reports").mkdir(exist_ok=True)
    (sandbox / "prompts").mkdir(exist_ok=True)
    (sandbox / "validators").mkdir(exist_ok=True)
    (sandbox / "prompts" / "banc.md").write_text("consigne du banc\n", encoding="utf-8")
    calls = sandbox / "validator-calls.txt"
    labels = sandbox / "checkpoints.txt"
    (sandbox / "validators" / "generic.sh").write_text(
        "#!/usr/bin/env bash\n"
        'printf "%s\\n" "${AUTOPORT_PHASE_ID:-?}" >> "' + str(calls) + '"\n'
        'echo "[banc] validateur factice"\n'
        "exit 1\n", encoding="utf-8")
    fake_cli = sandbox / "fake_cli.sh"
    fake_cli.write_text("#!/usr/bin/env bash\ncat >/dev/null\ncat \"$1\"\nexit 0\n",
                        encoding="utf-8")

    sys.path.insert(0, str(AP))               # `from lib import cli_backend`
    spec = importlib.util.spec_from_file_location("orch_arm_" + arm, src)
    mod = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = mod
    spec.loader.exec_module(mod)
    _patch(mod, sandbox, calls, labels)
    mod.cli_backend.worker_command = lambda *a, **k: ["bash", str(fake_cli), str(stream)]

    item = {"id": ITEM_ID, "prompt": "prompts/banc.md", "max_retries": 6,
            "max_turns": 10, "feature": "banc d'essai du harnais", "no_code": True}
    state = mod.load_state()
    before = {
        "retries": int(state.get("retries", {}).get(ITEM_ID, 0) or 0),
        "fingerprints": len(state.get("fingerprints", {}).get(ITEM_ID, []) or []),
    }
    # `repeat` > 1 : le MEME etat traverse plusieurs essais, comme la boucle principale.
    # C'est ainsi qu'on eprouve la borne d'abandons D'AFFILEE.
    kinds = []
    for _ in range(max(1, repeat)):
        outcome = mod.run_attempt(item, state)
        kinds.append(outcome.kind)
    after_state = mod.load_state()
    seq = int(after_state.get("attempt_seq", {}).get(ITEM_ID, 0) or 0)
    log_path = sandbox / "logs" / ITEM_ID / ("attempt-%03d.jsonl" % seq)

    aborted_event = {}
    end_event = {}
    for raw in log_path.read_text(errors="replace").splitlines() if log_path.exists() else []:
        try:
            ev = json.loads(raw)
        except ValueError:
            continue
        if ev.get("event") == "attempt_aborted":
            aborted_event = ev
        elif ev.get("event") == "attempt_end":
            end_event = ev

    rec = after_state.get("aborted", {}).get(ITEM_ID) or {}
    if isinstance(rec, int):
        rec = {"total": rec, "streak": rec}
    result = {
        "arm": arm,
        "ran": 1,
        "outcome": outcome.kind,
        "kinds": ",".join(kinds),
        "runs": len(kinds),
        "reason": outcome.reason,
        "retries_delta": int(after_state.get("retries", {}).get(ITEM_ID, 0) or 0) - before["retries"],
        "fingerprints_delta": len(after_state.get("fingerprints", {}).get(ITEM_ID, []) or []) - before["fingerprints"],
        "validator_calls": len(calls.read_text().split()) if calls.exists() else 0,
        "checkpoints": len(labels.read_text().splitlines()) if labels.exists() else 0,
        "log_abort_event": 1 if aborted_event else 0,
        "log_waited_s": aborted_event.get("waited_s", -1),
        "log_ceiling_ms": aborted_event.get("ceiling_ms", -1),
        "end_launcher_abort_s": end_event.get("launcher_abort_s", -1),
        "aborted_total": int(rec.get("total", 0) or 0),
        "aborted_streak": int(rec.get("streak", 0) or 0),
    }
    out.write_text(json.dumps(result), encoding="utf-8")
    return 0


# ============================================================ le banc ========
def before_commit(marker: str) -> tuple[str, str]:
    """Le dernier commit de orchestrator.py qui ne porte PAS le marqueur, et son contenu."""
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


def bench() -> int:
    import shutil
    import tempfile

    root = Path(tempfile.mkdtemp(prefix="abt-banc-"))
    try:
        stream_abort = root / "stream-abort.jsonl"
        stream_clean = root / "stream-clean.jsonl"
        body = "".join(json.dumps(e) + "\n" for e in BASE_EVENTS)
        stream_clean.write_text(body, encoding="utf-8")
        stream_abort.write_text(body + ABORT_LINE + "\n", encoding="utf-8")

        commit, blob = before_commit(MARKER)
        kv("before_commit", commit[:12] or "-")
        kv("before_marker_absent", 1 if (blob and MARKER not in blob) else 0)
        old_src = root / "old_orchestrator.py"
        if blob:
            old_src.write_text(blob, encoding="utf-8")
            # le profil se lit a cote du fichier : meme configuration pour les deux bras
            try:
                shutil.copyfile(AP / "model-profiles.json", root / "model-profiles.json")
            except OSError:
                pass

        # Le 4e bras : le MEME flux abandonne, joue assez de fois pour depasser la borne
        # `MAX_ABORTED_IN_A_ROW`. Sans lui, un item dont le worker laisse toujours des
        # taches de fond tournerait sans fin — l'essai doit finir par etre COMPTE.
        arms = [("vieux", old_src if blob else None, stream_abort, 1),
                ("neuf", AP / "orchestrator.py", stream_abort, 1),
                ("temoin", AP / "orchestrator.py", stream_clean, 1),
                ("borne", AP / "orchestrator.py", stream_abort, 5)]
        env = dict(os.environ)
        env["CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS"] = CEILING_MS
        env["COLUMNS"] = "4000"
        env.pop("AUTOPORT_PHASE_ID", None)
        kv("ceiling_ms_posee", CEILING_MS)

        for name, src, stream, repeat in arms:
            if src is None or not Path(src).exists():
                kv("%s_ran" % name, 0)
                continue
            sandbox = root / ("sb-" + name)
            out = root / ("out-" + name + ".json")
            proc = subprocess.run(
                [sys.executable, str(HERE), "--arm", name, "--src", str(src),
                 "--stream", str(stream), "--sandbox", str(sandbox), "--out", str(out),
                 "--repeat", str(repeat)],
                cwd=str(REPO), env=env, capture_output=True, text=True, timeout=900)
            journal = proc.stdout + proc.stderr
            (root / ("journal-" + name + ".txt")).write_text(journal, encoding="utf-8")
            if not out.exists():
                kv("%s_ran" % name, 0)
                kv("%s_rc" % name, proc.returncode)
                for line in journal.strip().splitlines()[-6:]:
                    kv("%s_stderr" % name, line.replace("=", ":")[:160])
                continue
            data = json.loads(out.read_text())
            for key, value in data.items():
                if key == "arm":
                    continue
                kv("%s_%s" % (name, key), str(value).replace("\n", " ")[:200])
            # LE JOURNAL, lu tel qu'il est sorti sur la console de l'orchestrateur.
            kv("%s_journal_duration" % name, 1 if "600 s" in journal else 0)
            kv("%s_journal_ceiling" % name,
               1 if ("CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=" + CEILING_MS) in journal else 0)
            kv("%s_journal_not_counted" % name, 1 if "NON COMPTÉ" in journal else 0)
            kv("%s_journal_no_validator" % name, 1 if "VALIDATEUR NON LANCÉ" in journal else 0)
            kv("%s_journal_lines" % name, len(journal.splitlines()))
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--arm")
    ap.add_argument("--src")
    ap.add_argument("--stream")
    ap.add_argument("--sandbox")
    ap.add_argument("--out")
    ap.add_argument("--repeat", type=int, default=1)
    args = ap.parse_args(argv)
    if args.arm:
        return run_arm(args.arm, Path(args.src), Path(args.stream),
                       Path(args.sandbox), Path(args.out), args.repeat)
    return bench()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
