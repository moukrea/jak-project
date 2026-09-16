#!/usr/bin/env python3
"""
OpenGOAL → Android autonomous orchestrator.

WHAT IT DOES, in one sentence: it takes the next open item of
`.autoport/backlog.yaml`, runs ONE worker session on it, then judges the result
ITSELF with `validators/generic.sh` — never on the worker's word.

Hardcoded design choices (per project owner's preference):
- Model/effort come from the ACTIVE profile in model-profiles.json (single
  source of truth). Active profile 2026-09-03: "fable51-high" —
  * MANAGER (the item session): the profile's `manager_model` @ `manager_effort`.
    Plans, decides, judges, synthesizes, reviews.
  * WORKERS (subagents via CLAUDE_CODE_SUBAGENT_MODEL): the profile's
    `worker_model`, per-agent effort in `.claude/agents/*.md` frontmatter.
  Flip `active` in model-profiles.json, run apply-model-profile.sh, relaunch.
- Thinking: the 'ultrathink' keyword in prompts keeps planning depth at the
  manager level whatever the effort setting.

Lifecycle of one turn of the loop:
1. Promote every `to-test` item whose `owner_ok` is filled → `validated`.
2. `backlog.next_open()` picks the work. No cursor, no index, no milestones.yaml.
3. The item goes `in-progress`; one `claude -p` session runs with the item's
   prompt, the directives block, the preflight findings and the previous
   attempt's `handoff.md`.
4. After it exits, the orchestrator runs `validators/generic.sh` as ground
   truth, then the close-gate (real code change, fresh device build, acquis,
   owner's word).
5. Outcome: `validated` / `to-test` / back to `open` for a retry / `blocked`.

WHAT DOES **NOT** COUNT AS AN ATTEMPT (2026-09-03): a session cut by a signal,
by the scope watchdog, or refused at the door before doing any work. 373 of 597
worker sessions lasted under three minutes because a Ctrl-C burned a retry,
ran the validator on an untouched tree and appended a fingerprint. Those three
paths now commit the work and return WITHOUT touching `retries` or
`fingerprints`.

NI UNE CAUSE EXTERIEURE (2026-09-12) : quand l'arbre porte, AVANT l'essai et ENCORE a
la porte, le chantier non commite d'un AUTRE item, GATE 0 rend `foreign` et non `fail`.
Le perimetre d'un worker lui INTERDIT de commiter ou de defaire l'arbre d'un autre :
lui debiter un essai, c'est le punir d'un ordre qu'on lui interdit d'executer. `retries`
est remis comme avant, les chemins sont nommes, et le compte part dans `foreign_cause`.
Au-dela de MAX_FOREIGN_IN_A_ROW d'affilee l'item est BLOQUE pour le superviseur — on ne
compte toujours aucun essai, mais on ne boucle pas non plus.
"""

from __future__ import annotations

import argparse
import hashlib
import importlib
import json
import os
import re
import select
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from rich.console import Console
from rich.panel import Panel

from lib import cli_backend, backend_control
from lib import freshness
from lib import impossible as impossible_state
from lib import gate_verdict
from lib import safe_reload
from lib import suite_gate

BACKEND = "claude"

# ============================================================
# Configuration
# ============================================================

# Model + effort come from the ACTIVE profile in .autoport/model-profiles.json
# (single source of truth — flip "active" there to switch the whole setup, then
# run .autoport/apply-model-profile.sh + relaunch). Hardcoded fallback below is
# used only if the JSON is missing/unreadable.
_PROFILE_PATH = Path(__file__).resolve().parent / "model-profiles.json"



def _pick_device() -> str:
    """Le serial de l'appareil branche, decide a l'execution (lib/pick_device.sh).

    L'owner, 2026-09-06 : bloquer parce que SON telephone occupe le port au lieu du Redmi est
    absurde — le Honor est plus rapide, donc meilleur pour mesurer. On ne code plus aucun
    numero de serie en dur ; s'il n'y a rien de branche on rend une chaine vide et l'appelant
    echoue proprement, au lieu de prouver sur un appareil absent.
    """
    try:
        import subprocess
        out = subprocess.run(["bash", str(Path(__file__).resolve().parent / "lib" / "pick_device.sh")],
                             capture_output=True, text=True, timeout=40)
        return out.stdout.strip()
    except Exception:
        return ""

def _load_model_profile() -> dict:
    fallback = {
        "manager_model": "claude-fable-5-1[1m]", "manager_effort": "high",
        "worker_model": "claude-fable-5-1[1m]",
        "worker_efforts": {"autoport-researcher": "high",
                           "autoport-implementer": "medium",
                           "autoport-tester": "medium"},
    }
    try:
        cfg = json.loads(_PROFILE_PATH.read_text())
        prof = cfg["profiles"][cfg["active"]]
        for k in ("manager_model", "manager_effort", "worker_model", "worker_efforts"):
            if k not in prof:
                raise KeyError(k)
        prof["_active_name"] = cfg["active"]
        return prof
    except Exception as e:  # noqa: BLE001
        fallback["_active_name"] = f"FALLBACK ({e})"
        return fallback


_PROFILE = _load_model_profile()
MODEL = _PROFILE["manager_model"]           # MANAGER model (the item session)
EFFORT = _PROFILE["manager_effort"]         # manager default
SUBAGENT_MODEL = _PROFILE["worker_model"]   # subagent model (CLAUDE_CODE_SUBAGENT_MODEL)
WORKER_EFFORTS = _PROFILE["worker_efforts"] # per-agent effort (also in .claude/agents/*.md)
PROFILE_NAME = _PROFILE["_active_name"]

# Full YOLO mode: --dangerously-skip-permissions bypasses ALL permission
# prompts. Safety net: per-attempt git checkpoints make damage revertable.

# Live verbosity: how often to emit the periodic progress tick line
LIVE_TICK_INTERVAL = 15.0  # seconds

# Stall detection for the read loop. Claude Code in -p mode sometimes keeps
# the process open after emitting `result` (terminal_reason=completed) when
# background TaskCreate tasks generated notifications; the orchestrator was
# then blocked on EOF that never arrived. We force-close in those cases.
STALL_POST_RESULT_SEC = 45.0   # idle gap after a result event before we force-close
STALL_HARD_SEC = 1800.0        # absolute max idle, regardless of session state
EXIT_WAIT_SEC = 30.0          # EOF must not bypass all progress watchdogs
READ_POLL_SEC = 5.0            # select timeout slice (drives ticks + stall checks)

# Stuck detection: how many identical validator-failure fingerprints in a
# row before we conclude the agent has stopped learning. A "different failure"
# still counts as progress; what we guard against is the exact same error.
STUCK_REPEAT_THRESHOLD = 3

# A session refused at the door (zero tokens, zero tool calls) is INFRA, not a
# failed attempt — but it must not loop forever either. On 2026-08-31 it looped
# 230 times over 19.7 h on a five-minute fixed sleep, and the cause could not be
# recovered afterwards because the attempt log was overwritten every iteration
# and claude's stderr was dropped. Both are fixed; this is the hard stop.
MAX_NO_START_ITERATIONS = 6
NO_START_FALLBACK_SLEEP = 300      # only when the API returned no reset time
NO_START_MAX_SLEEP = 6 * 3600      # never sleep longer than this on one refusal

# An Anthropic 529 storm is an infra outage: it must not consume a retry. It is
# counted ONLY from structured API error events (see count_api_529): counting
# the string "529" anywhere in the stream turned every one of our own SIGTERM
# kills (exit 143) into a fake "infra outage", and this file's own source
# contains the literal, so a worker reading the harness pre-loaded the counter.
API_529_STORM_THRESHOLD = 3
API_529_SLEEP = 600

# ============================================================
# A LAUNCHER ABORT IS NOT A FAILED ATTEMPT (2026-09-12)
# ============================================================
# `claude -p` emits its `result`, then keeps waiting for the background tasks the
# worker started (a build, a device run) because their notifications can re-engage
# the model. Past a ceiling it KILLS them and exits 0, printing one bare line:
#
#     Background tasks still running after 600s; terminating. Set
#     CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS=0 to wait indefinitely.
#
# The worker concluded NOTHING, yet the half-laid tree went to the validator, which
# reported an incoherent state (engine source newer than the proof, binary sha not
# the one on disk, an x86 proof on a device item) and the attempt was COUNTED.
# Census of the attempt logs, 2026-09-12: FOUR attempts destroyed this way —
# Grecharged-mesh-browser 6, refset-replay-stable 2, lighting-hdr 7 and
# lighting-legacy-purge 8, the last of which exhausted the budget of an item the
# owner had put at priority 17.
#
# READ ON A BARE LINE ONLY. That literal lives in this file, in backlog.yaml, in the
# item prompt and in the workers' own tool calls — all of which travel as JSON
# events. Scanning the whole stream would let any worker that merely MENTIONS the
# string abort its own attempt, which is how counting "529" anywhere once turned 58
# of our own SIGTERMs into fake Anthropic outages. Measured on the real logs: the
# four killed attempts carry it as a bare stdout line (bare=1, json=0), while
# `gl-uniforms-dead-seven` attempt 2 and `harness-aborted-attempt-not-counted`
# attempt 1 only quote it (bare=0, json>=1).
BG_ABORT_RE = re.compile(r"Background tasks still running after\s+(\d+)\s*s\s*;\s*terminating")

# The ceiling IN FORCE, in milliseconds. `launch.sh` exports it, but an orchestrator
# started any other way would silently fall back to the CLI's 600 s — so we post it
# on the child's environment ourselves and name it in the journal. Raising it only
# pushes the boundary back; the recognition above is what stops burning attempts.
_BG_CEILING_ENV = os.environ.get("CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS", "").strip()
BG_WAIT_CEILING_MS = int(_BG_CEILING_ENV) if _BG_CEILING_ENV.isdigit() else 45 * 60 * 1000
BG_CEILING_SOURCE = "le lanceur" if _BG_CEILING_ENV.isdigit() else "l'orchestrateur (défaut)"

# An aborted attempt costs nothing to the retry budget — but a worker that ALWAYS
# leaves background tasks behind would then loop forever on the same item. Past this
# many aborts in a row, the attempt IS counted, and the journal says why.
MAX_ABORTED_IN_A_ROW = 3

# The worker's progress is judged on ARTIFACTS, not output.
NO_PROGRESS_SEC = 45 * 60

# A handoff is a short note, not a report.
HANDOFF_MAX_LINES = 30

# ============================================================
# Stuck detection — fingerprint validator failures so we can tell
# when the agent is making no progress vs. learning between attempts.
# ============================================================

_NOISE_PATTERNS = [
    # ISO timestamps
    (re.compile(r'\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}\S*'), '<TIME>'),
    # Absolute paths — keep the basename, drop the dirs
    (re.compile(r'/(?:[^\s:()/]+/)+'), '/.../'),
    # Hex addresses (Linux process addresses, allocator output, etc.)
    (re.compile(r'0x[0-9a-fA-F]+'), '0x<HEX>'),
    # Wall-clock durations
    (re.compile(r'\b\d+\.\d+\s*(?:s|ms|sec|min)\b'), '<DUR>'),
    # PIDs
    (re.compile(r'\bpid\s+\d+\b', re.IGNORECASE), 'pid <PID>'),
    # Very large integers (often pointers, line offsets, etc.)
    (re.compile(r'\b\d{6,}\b'), '<BIGNUM>'),
    # Trailing whitespace
    (re.compile(r'\s+$'), ''),
]

_ERROR_KEYWORDS = re.compile(
    r'\b(error|Error|ERROR|FAIL|Failed|FAILED|panic|undefined|'
    r'cannot|missing|expected|assert(?:ion)?|fatal|abort|segfault|'
    r'SIGSEGV|stack overflow|undefined reference)\b'
)


def fingerprint_validator_output(output: str) -> tuple[str, list[str]]:
    """
    Reduce validator output to a stable failure signature.

    Returns (sha1_short, key_lines) where sha1_short is the same across attempts
    that fail the same way and different when the failure mode changes.
    """
    sig_lines: list[str] = []
    for line in output.splitlines():
        if _ERROR_KEYWORDS.search(line):
            normalized = line
            for pat, repl in _NOISE_PATTERNS:
                normalized = pat.sub(repl, normalized)
            sig_lines.append(normalized)

    # Fallback: if no error-keyword lines, hash the tail of the output
    if not sig_lines:
        tail = [ln for ln in output.splitlines() if ln.strip()][-10:]
        for line in tail:
            normalized = line
            for pat, repl in _NOISE_PATTERNS:
                normalized = pat.sub(repl, normalized)
            sig_lines.append(normalized)

    key_lines = sig_lines[-15:]
    fp = hashlib.sha1('\n'.join(key_lines).encode('utf-8', errors='replace')).hexdigest()[:12]
    return fp, key_lines


def implementation_fingerprint(root: Path) -> str:
    """Identify source contents, independently of commits, reports and build timestamps."""
    listed = subprocess.run(
        ["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard",
         "--", "game", "common", "goal_src", "goalc", "android", ".autoport"],
        cwd=root, capture_output=True, timeout=30)
    if listed.returncode:
        return ""
    digest = hashlib.sha256()
    suffixes = {".cpp", ".h", ".hpp", ".c", ".gc", ".vert", ".frag", ".glsl",
                ".comp", ".py", ".sh", ".java", ".kt"}
    for raw in sorted(set(listed.stdout.split(b"\0")) - {b""}):
        rel = Path(os.fsdecode(raw))
        if rel.suffix not in suffixes:
            continue
        if rel.parts[0] == ".autoport" and any(
                part in {"reports", "logs", "archive", "tests", "tmp"} for part in rel.parts):
            continue
        digest.update(raw + b"\0")
        try:
            with (root / rel).open("rb") as source:
                digest.update(b"present\0")
                while chunk := source.read(1024 * 1024):
                    digest.update(chunk)
        except FileNotFoundError:
            digest.update(b"deleted\0")
        digest.update(b"\0")
    return digest.hexdigest()


def fingerprint_failure(output: str, root: Path) -> tuple[str, list[str]]:
    failure, lines = fingerprint_validator_output(output)
    implementation = implementation_fingerprint(root)
    if implementation:
        failure = hashlib.sha1(f"{failure}:{implementation}".encode()).hexdigest()[:12]
    return failure, lines


def check_stuck(state: dict, item_id: str, current_fp: str) -> tuple[bool, str]:
    """Stuck = the same fingerprint STUCK_REPEAT_THRESHOLD times in a row."""
    history = state.get("fingerprints", {}).get(item_id, [])
    if len(history) < STUCK_REPEAT_THRESHOLD:
        return False, ""

    recent = history[-STUCK_REPEAT_THRESHOLD:]
    if all(fp == current_fp for fp in recent):
        return True, (
            f"Même échec et même empreinte de sources '{current_fp}' "
            f"{STUCK_REPEAT_THRESHOLD} essais de suite : reprise à arbitrer par le "
            f"superviseur à partir du handoff et du validateur."
        )
    return False, ""


# ============================================================
# Paths
# ============================================================

REPO_ROOT = Path(__file__).resolve().parent.parent
AUTOPORT_DIR = REPO_ROOT / ".autoport"
STATE_PATH = AUTOPORT_DIR / "state.json"
BACKLOG_PATH = AUTOPORT_DIR / "backlog.yaml"
BACKLOG_LIB = AUTOPORT_DIR / "lib" / "backlog.py"
GENERIC_VALIDATOR = AUTOPORT_DIR / "validators" / "generic.sh"
LOG_ROOT = AUTOPORT_DIR / "logs"
REPORTS_DIR = AUTOPORT_DIR / "reports"
OWNER_OK_DIR = AUTOPORT_DIR / "owner-ok"
SHIELD_GUARD = AUTOPORT_DIR / "shield_guard.sh"
CREDENTIALS_PATH = Path.home() / ".claude" / ".credentials.json"

console = Console()
HALT = False
QUIET = False  # set from argparse; suppresses live event rendering

# Set inside run_attempt while a claude subprocess is alive. The signal handler
# forwards SIGTERM to its process group so Ctrl-C kills Claude promptly.
_CURRENT_CHILD: subprocess.Popen | None = None


def _sig(_signum, _frame):
    global HALT
    console.print("\n[yellow]⚠ Signal reçu — l'essai en cours est ANNULÉ (ni compté, "
                  "ni empreinté). Le travail déjà fait est commité.[/yellow]")
    HALT = True
    child = _CURRENT_CHILD
    if child is not None and child.poll() is None:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass


signal.signal(signal.SIGINT, _sig)
signal.signal(signal.SIGTERM, _sig)


def log(message: str, style: str = "") -> None:
    """One console line. There is no notification channel any more: the ntfy/Slack
    push was dropped by the owner on 2026-06-13 and `notify()` had been printing
    to this same console ever since, behind a level argument nobody read."""
    console.print(f"[{style}]{message}[/{style}]" if style else message)


def format_duration(seconds: float) -> str:
    """Human-readable duration like '3d 4h', '2h 15m', '45m', '12s'."""
    s = int(seconds)
    if s < 60:
        return f"{s}s"
    m, s = divmod(s, 60)
    if m < 60:
        return f"{m}m"
    h, m = divmod(m, 60)
    if h < 24:
        return f"{h}h {m}m" if m else f"{h}h"
    d, h = divmod(h, 24)
    return f"{d}d {h}h" if h else f"{d}d"


# ============================================================
# State — atomic, versioned, and only five keys
# ============================================================
#
# state.json holds MECHANICS ONLY. Every status lives in backlog.yaml.
#
# The version guard exists because of an observed LOST UPDATE (2026-09-03
# 02:13): an orchestrator that had received a signal kept running its validator
# until 02:15 while a NEW orchestrator started at 02:13:18 and rewrote
# state.json at 02:13:19. The first run's result was never recorded. The flock
# did not prevent the overlap, so the write itself now refuses to clobber a file
# that moved under it.

STATE_KEYS = ("version", "retries", "fingerprints", "attempt_seq",
              "rate_interrupts", "aborted", "commit_paths", "foreign_cause",
              "proof_impossible", "proof_writer", "last_update")


class StateConflict(Exception):
    """state.json changed under us: another orchestrator is alive."""


def load_state() -> dict:
    raw: dict = {}
    if STATE_PATH.exists():
        try:
            raw = json.loads(STATE_PATH.read_text())
        except (OSError, ValueError) as e:
            raise SystemExit(f"state.json illisible ({e}). Répare-le ou supprime-le "
                             f"(il ne contient que des compteurs, aucun statut).")
    # The statuses (`completed`, `parked`, `blocked`, `validator_passed`) moved to
    # backlog.yaml. The first write here would drop them for good, and
    # tools/migrate_backlog.py reads them — so keep one copy, once, before any
    # write can happen.
    legacy = [k for k in raw if k not in STATE_KEYS]
    if legacy:
        backup = STATE_PATH.with_name(STATE_PATH.name + ".legacy")
        if not backup.exists():
            backup.write_text(json.dumps(raw, indent=2))
            log(f"· ancien state.json ({len(legacy)} clés de statut) sauvegardé dans "
                f"{backup.name} avant de passer au format à cinq compteurs.", "yellow")

    return {
        "version": int(raw.get("version", 0) or 0),
        "retries": dict(raw.get("retries") or {}),
        "fingerprints": dict(raw.get("fingerprints") or {}),
        "attempt_seq": dict(raw.get("attempt_seq") or {}),
        "rate_interrupts": dict(raw.get("rate_interrupts") or {}),
        # Attempts the LAUNCHER killed: counted apart from `retries`, on purpose.
        "aborted": dict(raw.get("aborted") or {}),
        # Comptabilité de l'indexation git : indexés / refusés / commits vides évités,
        # séparément. Un seul booléen ne dit pas si UN chemin a fait tomber les 63 autres.
        "commit_paths": dict(raw.get("commit_paths") or {}),
        # Les essais qu'une cause EXTERIEURE a l'item a requalifies : comptes a part de
        # `retries`, sur le meme principe que `aborted`. Un essai classe ici n'a jamais
        # brule le budget de l'item.
        "foreign_cause": dict(raw.get("foreign_cause") or {}),
        # Les essais dont la preuve etait IMPOSSIBLE : etats LUS par la porte (`read`) et
        # verdicts REQUALIFIES (`total`), comptes a part de `retries` comme `aborted` et
        # `foreign_cause`. Une machine qui ne peut pas mesurer ne debite jamais le budget.
        "proof_impossible": dict(raw.get("proof_impossible") or {}),
        # Les essais dont le JUGE a du attendre la fin de la course qui ecrivait leur preuve.
        # Un compteur qu'on n'ecrit nulle part ne vaut rien : celui-ci est ECRIT ici, releve
        # par le recensement de `harness-proof-file-has-no-writer-lock`, et il nomme le pid.
        "proof_writer": dict(raw.get("proof_writer") or {}),
        "last_update": raw.get("last_update", ""),
    }


def save_state(state: dict) -> None:
    """Atomic write, refused if the on-disk version moved under us."""
    on_disk = 0
    if STATE_PATH.exists():
        try:
            on_disk = int(json.loads(STATE_PATH.read_text()).get("version", 0) or 0)
        except (OSError, ValueError):
            on_disk = state["version"]      # unreadable: don't wedge on it
    if on_disk != state["version"]:
        raise StateConflict(
            f"state.json est en version {on_disk}, nous tenons la {state['version']} : "
            f"un autre orchestrateur écrit dans ce dépôt. Écriture REFUSÉE (c'est la "
            f"mise à jour perdue du 2026-09-03 02:13). Arrête l'autre instance."
        )
    new = {k: state.get(k) for k in STATE_KEYS}
    new["version"] = state["version"] + 1
    new["last_update"] = datetime.now(timezone.utc).isoformat()
    tmp = STATE_PATH.with_name(STATE_PATH.name + f".tmp.{os.getpid()}")
    tmp.write_text(json.dumps(new, indent=2))
    os.replace(tmp, STATE_PATH)
    state["version"] = new["version"]
    state["last_update"] = new["last_update"]


def next_attempt_seq(state: dict, item_id: str) -> int:
    """A monotonic, never-reused attempt number.

    The number USED to be `retries + 1`. The OPEN-DEFECTS exemption reset
    `retries` to 0, so the next attempt was numbered 1 again and reopened
    `attempt-01.jsonl` in "w" mode: on Grecharged-secondary-motion, 117
    fingerprints had left 18 attempt logs on disk. This counter never goes
    backwards, and it skips any number whose log file somehow already exists."""
    seqs = state.setdefault("attempt_seq", {})
    n = int(seqs.get(item_id, 0) or 0)
    while True:
        n += 1
        if not (LOG_ROOT / item_id / f"attempt-{n:03d}.jsonl").exists():
            break
    seqs[item_id] = n
    save_state(state)
    return n


# ============================================================
# Backlog — the only source of work (lib/backlog.py, chantier D)
# ============================================================

def load_backlog():
    """Fresh read every turn: the operator edits backlog.yaml while we run.

    On passe BACKLOG_PATH EXPLICITEMENT. `backlog.load()` sans argument retombe sur
    le chemin par defaut, c'est-a-dire le VRAI fichier — y compris quand un test
    croit travailler dans un bac a sable. Mesure du 2026-09-03 : un test de la
    reclamation a rouvert `hd-skin-origin-stretch` dans le backlog de production
    pendant qu'un worker vivant le tenait, ce qui aurait pu mettre deux workers sur
    le meme arbre. Le fixture promettait l'isolation, cette ligne la lui rendait fausse.
    """
    lib = str(AUTOPORT_DIR / "lib")
    if lib not in sys.path:
        sys.path.insert(0, lib)
    import backlog as _bk
    # RECHARGEMENT/filet — un `lib/backlog.py` a moitie ecrit TUAIT la boucle ici meme
    # (12/09 15:33, dix minutes d'arret). Le filet garde le module deja charge, nomme le
    # fichier et la ligne, et le tour continue sur du code VIEUX — en le DISANT.
    safe_reload.reload(_bk, "orchestrator:backlog", log)
    return _bk.load(BACKLOG_PATH)


def backlog_missing_reason() -> str:
    """'' when we can start, otherwise the reason AND what to do about it."""
    if not BACKLOG_LIB.exists():
        return (f"{BACKLOG_LIB} est absent. L'orchestrateur ne sait plus choisir le "
                f"travail sans lui : il ne lit plus milestones.yaml ni de curseur.\n"
                f"  → livre lib/backlog.py (chantier D), puis relance.")
    if not BACKLOG_PATH.exists():
        return (f"{BACKLOG_PATH} est absent : il n'y a aucun backlog à traiter.\n"
                f"  → crée-le avec `python3 .autoport/tools/migrate_backlog.py`, "
                f"vérifie-le avec `./.autoport/autoport lint`, puis relance.")
    return ""


def _reread_item(item_id: str, fallback: dict) -> dict:
    """The item as it is ON DISK right now.

    A close-gate decision must never be taken on the copy loaded when the
    attempt started: an operator who fixes `device_serial` or sets `no_code`
    mid-attempt (which is exactly what this gate's own message tells them to do)
    would otherwise be refused until a relaunch."""
    try:
        got = load_backlog().get(item_id)
        return got if got else fallback
    except Exception:  # noqa: BLE001 — fail-safe: keep the in-memory item
        return fallback


# ============================================================
# Live verbosity — smart-compact stream-json renderer
# ============================================================

@dataclass
class PrettyState:
    """Per-attempt live-rendering state. The printer never raises."""
    t0: float                                # attempt start (monotonic)
    session_id: str = ""
    tool_calls: int = 0
    tokens_in: int = 0
    tokens_out: int = 0
    cache_read: int = 0
    cache_creation: int = 0
    last_tick_at: float = 0.0
    tool_use_names: dict[str, str] = field(default_factory=dict)  # id -> name
    init_printed: bool = False
    dirty_since_tick: bool = False           # gate periodic tick on activity
    cli_failed: bool = False
    cli_error: str = ""
    result_seen: bool = False                # at least one result/* event arrived
    # The ONE piece of quota behaviour we keep (owner policy): when the API
    # REFUSES us, it tells us when the window resets. We sleep until then
    # instead of guessing five minutes.
    rate_rejected: bool = False
    rate_reset_at: int | None = None


def _short_id(s: str, n: int = 7) -> str:
    return s[:n] if isinstance(s, str) else ""


def _truncate(s: str, n: int) -> str:
    if not isinstance(s, str):
        s = str(s)
    s = s.replace("\n", " ").replace("\r", " ").strip()
    return s if len(s) <= n else s[: n - 1] + "…"


def _human_tokens(n: int) -> str:
    if n < 1000:
        return f"{n}"
    if n < 1_000_000:
        return f"{n / 1000:.1f}k"
    return f"{n / 1_000_000:.2f}M"


def _primary_arg(tool_name: str, tool_input: dict) -> str:
    """Best single string to identify what the tool is doing."""
    if not isinstance(tool_input, dict):
        return ""
    if tool_name == "Bash":
        return str(tool_input.get("command", ""))
    for key in ("file_path", "path", "pattern", "query", "url", "command",
                "subject", "description", "old_string"):
        if key in tool_input and tool_input[key]:
            return str(tool_input[key])
    for v in tool_input.values():
        if v:
            return str(v)
    return ""


def _accumulate_usage(state: PrettyState, usage: dict) -> None:
    if not isinstance(usage, dict):
        return
    state.tokens_in += int(usage.get("input_tokens", 0) or 0)
    state.tokens_out += int(usage.get("output_tokens", 0) or 0)
    state.cache_read += int(usage.get("cache_read_input_tokens", 0) or 0)
    state.cache_creation += int(usage.get("cache_creation_input_tokens", 0) or 0)


def _maybe_emit_tick(state: PrettyState) -> None:
    if QUIET:
        return
    now = time.monotonic()
    if not state.dirty_since_tick:
        return
    if (now - state.last_tick_at) < LIVE_TICK_INTERVAL:
        return
    state.last_tick_at = now
    state.dirty_since_tick = False
    mins, secs = divmod(int(now - state.t0), 60)
    tokens = state.tokens_in + state.tokens_out
    console.print(f"[dim][{mins}m{secs:02d}s · {state.tool_calls} calls · "
                  f"{_human_tokens(tokens)} tok][/dim]")


def pretty_print_event(ev: dict, state: PrettyState) -> None:
    """Render one stream-json event compactly. Never raises."""
    try:
        if BACKEND == "codex":
            line = cli_backend.update_codex(ev, state)
            if line and (not QUIET or cli_backend.codex_error(ev)):
                console.print(line, markup=False)
            return
        t = ev.get("type")

        if t == "system":
            sub = ev.get("subtype", "")
            if sub == "init" and not state.init_printed:
                state.init_printed = True
                state.session_id = ev.get("session_id", "")
                if not QUIET:
                    console.print(f"[cyan]▶ claude session {_short_id(state.session_id)} · "
                                  f"model={ev.get('model', '?')}[/cyan]")
            elif sub == "api_retry":
                if not QUIET:
                    n = ev.get("attempt"); mx = ev.get("max_retries")
                    delay = ev.get("retry_delay_ms", 0) or 0
                    console.print(f"[yellow]· api_retry {n}/{mx} (delay {delay/1000:.1f}s, "
                                  f"status={ev.get('error_status')}, {ev.get('error', '?')})[/yellow]")
            return

        if t == "rate_limit_event":
            info = ev.get("rate_limit_info", {}) or {}
            status = str(info.get("status", ""))
            if status in ("rejected", "blocked", "exceeded"):
                state.rate_rejected = True
                reset = info.get("resetsAt")
                if isinstance(reset, (int, float)) and reset > 0:
                    state.rate_reset_at = int(reset)
                console.print(f"[red]⚠ l'API nous a REFUSÉS ({status})"
                              + (f", fenêtre réouverte à "
                                 f"{datetime.fromtimestamp(state.rate_reset_at, tz=timezone.utc).isoformat()}"
                                 if state.rate_reset_at else "")
                              + "[/red]")
            elif status not in ("allowed", "") and not QUIET:
                console.print(f"[dim]· rate_limit_event: {status} (avertissement seul — "
                              f"on continue, politique owner 2026-06-12)[/dim]")
            return

        if t == "assistant":
            msg = ev.get("message", {}) or {}
            usage = msg.get("usage")
            if usage:
                _accumulate_usage(state, usage)
            for c in msg.get("content", []) or []:
                ctype = c.get("type")
                if ctype == "tool_use":
                    state.tool_calls += 1
                    state.dirty_since_tick = True
                    name = c.get("name", "?")
                    state.tool_use_names[c.get("id", "")] = name
                    if not QUIET:
                        arg = _truncate(_primary_arg(name, c.get("input", {})), 100)
                        console.print(f"[bold]🔧 {name}[/bold] [dim]{arg}[/dim]")
                elif ctype == "text":
                    text = (c.get("text") or "").strip()
                    if text and not QUIET:
                        first = re.split(r'(?<=[.!?])\s', text, maxsplit=1)[0]
                        console.print(f"[dim]{_truncate(first, 120)}[/dim]")
            return

        if t == "user":
            msg = ev.get("message", {}) or {}
            for c in msg.get("content", []) or []:
                if c.get("type") != "tool_result":
                    continue
                if not (QUIET or not c.get("is_error")):
                    content = c.get("content", "")
                    if isinstance(content, list):
                        parts = [b.get("text", "") for b in content
                                 if isinstance(b, dict) and b.get("type") == "text"]
                        content = "".join(parts) if parts else str(content)
                    console.print(f"   [red]↳ ERROR:[/red] [dim]{_truncate(str(content), 100)}[/dim]")
            return

        if t == "result":
            state.result_seen = True
            _accumulate_usage(state, ev.get("usage", {}) or {})
            if not QUIET:
                dur_ms = ev.get("duration_ms", 0)
                cost = ev.get("total_cost_usd", 0) or 0
                head = "[red]✗ result[/red]" if ev.get("is_error") else "[green]✓ result[/green]"
                console.print(
                    f"{head} [dim]turns={ev.get('num_turns', 0)} · {dur_ms/1000:.1f}s · "
                    f"in {_human_tokens(state.tokens_in)} out {_human_tokens(state.tokens_out)} "
                    f"cache_r {_human_tokens(state.cache_read)} · ${cost:.3f}[/dim]")
            return

    except Exception as e:  # noqa: BLE001 — the printer must NEVER kill the loop
        if not QUIET:
            console.print(f"[dim]· print-err {type(e).__name__}[/dim]")
    finally:
        _maybe_emit_tick(state)


# ============================================================
# Forensics — read the attempt JSONL as EVENTS, never as text
# ============================================================

def _iter_events(path: Path):
    try:
        with path.open(errors="replace") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                try:
                    ev = json.loads(line)
                except ValueError:
                    continue
                if isinstance(ev, dict):
                    yield ev
    except OSError:
        return


def _api_error_statuses(ev: Any, out: list[int] | None = None) -> list[int]:
    """Every `api_error_status` found anywhere in an event, as ints."""
    if out is None:
        out = []
    if isinstance(ev, dict):
        for k, v in ev.items():
            if k == "api_error_status" and isinstance(v, (int, str)) and str(v).isdigit():
                out.append(int(v))
            else:
                _api_error_statuses(v, out)
    elif isinstance(ev, list):
        for v in ev:
            _api_error_statuses(v, out)
    return out


def count_api_529(path: Path) -> int:
    """Structured 529s only.

    The old heuristic counted `overloaded` and `\\b529\\b` ANYWHERE in the
    attempt stream — tool outputs included. This file itself contained six such
    literals, so a worker that read the harness source pre-loaded the counter;
    and any non-zero exit with three hits became an "infra outage", which is how
    58 of our OWN watchdog kills (exit 143) were logged as Anthropic outages,
    skipping the validator and the WIP commit."""
    n = 0
    for ev in _iter_events(path):
        if ev.get("type") == "system" and ev.get("subtype") == "api_retry":
            st = ev.get("error_status")
            if str(st) == "529":
                n += 1
                continue
        n += sum(1 for s in _api_error_statuses(ev) if s == 529)
    return n


def launcher_abort_seconds(line: str) -> int | None:
    """How long the CLI waited before killing the worker's background tasks, or None.

    `line` must be a BARE CLI line — one that failed to parse as JSON. The literal is
    quoted all over the harness and the workers' own tool calls, and every one of
    those copies reaches us inside a JSON event; a scan of the whole stream would let
    a worker abort its own attempt by talking about aborts. The `{` guard makes the
    rule hold even if a caller forgets it."""
    if line.lstrip().startswith("{"):
        return None
    m = BG_ABORT_RE.search(line)
    return int(m.group(1)) if m else None


def launcher_abort_from_log(path: Path) -> int | None:
    """Same reading over a finished attempt log: bare lines only, first one wins."""
    try:
        with path.open(errors="replace") as fh:
            for raw in fh:
                line = raw.rstrip("\n")
                if not line.strip():
                    continue
                try:
                    json.loads(line)
                except ValueError:
                    waited = launcher_abort_seconds(line)
                    if waited is not None:
                        return waited
    except OSError:
        return None
    return None


def _aborted_record(state: dict, item_id: str) -> dict:
    """Per-item abort accounting: `total` ever, `streak` since the last COUNTED attempt.

    Tolerates the plain int an older state.json may carry."""
    book = state.setdefault("aborted", {})
    rec = book.get(item_id)
    if isinstance(rec, int):
        rec = {"total": rec, "streak": rec}
    elif not isinstance(rec, dict):
        rec = {"total": 0, "streak": 0}
    rec = {"total": int(rec.get("total", 0) or 0), "streak": int(rec.get("streak", 0) or 0)}
    book[item_id] = rec
    return rec


# ============================================================
# L'ESSAI QU'UNE CAUSE EXTÉRIEURE A GÂCHÉ — CLASSÉ À PART, JAMAIS COMPTÉ
# ============================================================
# Signalement du 2026-09-12 : GATE 0 rendait `fail` quand l'arbre portait le travail non
# commité d'un AUTRE item. L'essai était COMPTÉ, empreinté, et la consigne renvoyée au worker
# lui demandait de nettoyer un arbre que son périmètre lui INTERDIT de toucher. Un item
# pouvait brûler ses cinq essais sur une saleté qu'il n'avait pas le droit de nettoyer.
#
# Combien de fois d'AFFILÉE avant d'appeler le superviseur. Sans plafond, un arbre que
# personne ne nettoie ferait tourner l'item sans fin — la boucle de 230 itérations du
# 2026-08-31, sous un autre nom. Au-delà on ne compte pas davantage d'essais : on BLOQUE.
MAX_FOREIGN_IN_A_ROW = 3


def _foreign_record(state: dict, item_id: str) -> dict:
    """`total` depuis toujours, `streak` depuis le dernier essai COMPTÉ, `since` la date."""
    book = state.setdefault("foreign_cause", {})
    rec = book.get(item_id)
    if not isinstance(rec, dict):
        rec = {}
    rec = {"total": int(rec.get("total", 0) or 0),
           "streak": int(rec.get("streak", 0) or 0),
           "since": rec.get("since", ""),
           "last": rec.get("last", ""),
           "paths": list(rec.get("paths") or [])}
    book[item_id] = rec
    return rec


def requalify_foreign_attempt(state: dict, item_id: str,
                              paths: list[str]) -> tuple[str, str]:
    """L'essai n'a pas échoué : il a mesuré l'arbre d'un AUTRE item. On le CLASSE À PART.

    Rend `("requalifie"|"bloque", ce qu'il faut dire)`. Dans les DEUX cas `retries` est remis
    comme avant l'essai : un essai n'a jamais à brûler pour une saleté que le périmètre de
    l'item lui interdit de nettoyer. Au-delà de MAX_FOREIGN_IN_A_ROW d'affilée on n'en compte
    pas davantage non plus — on BLOQUE l'item et on nomme le superviseur, seul habilité à
    commiter ou défaire l'arbre d'un autre."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    rec = _foreign_record(state, item_id)
    rec["total"] += 1
    rec["streak"] += 1
    rec["last"] = now
    rec["since"] = rec["since"] or now
    rec["paths"] = sorted(paths)[:32]
    avant = int(state.setdefault("retries", {}).get(item_id, 0) or 0)
    state["retries"][item_id] = max(0, avant - 1)
    montre = ", ".join(sorted(paths)[:8]) + (" …" if len(paths) > 8 else "")
    dit = (f"essai CLASSÉ À PART, NON COMPTÉ : {len(paths)} fichier(s) moteur sales hérités "
           f"d'un autre item — {montre}. retries {avant} → {state['retries'][item_id]}. "
           f"{rec['streak']}e d'affilée sur cet item, {rec['total']} en tout, "
           f"depuis {rec['since']}.")
    if rec["streak"] > MAX_FOREIGN_IN_A_ROW:
        return ("bloque",
                dit + f" Au-delà de {MAX_FOREIGN_IN_A_ROW} d'affilée on n'essaie plus : "
                      f"l'item est BLOQUÉ, le superviseur doit commiter ou défaire ces "
                      f"chemins. Aucun essai n'a été débité pour autant.")
    return ("requalifie", dit)


def _foreign_reset(state: dict, item_id: str) -> None:
    """Un essai JUGÉ remet la série de requalifications à zéro."""
    rec = _foreign_record(state, item_id)
    if rec["streak"]:
        rec["streak"] = 0
        save_state(state)


# ============================================================
# L'ESSAI DONT LA PREUVE ÉTAIT IMPOSSIBLE — LU, NOMMÉ, JAMAIS COMPTÉ
# ============================================================
# Signalement du 2026-09-12 (reports/harness-attempt-not-burned-by-foreign-cause/FINDINGS.txt,
# ligne 4). `lib/proof_run.sh` ÉCRIT depuis ce jour-là un état nommé quand aucune preuve
# n'était possible — binaire absent, appareil absent, verrou de déploiement tenu au-delà de la
# borne. Personne ne le LISAIT : le validateur rendait « proof.txt absent ou vide », l'essai
# était compté, empreinté, et la consigne renvoyée au worker lui demandait de produire une
# preuve que la machine lui interdisait de produire. Le constructeur a tenu le verrou 6 h 38 :
# rien, nulle part, ne l'a dit.
#
# ICI la porte de fermeture LIT cet état AVANT tout le reste, et rend `impossible` : ni `fail`
# — l'essai n'a pas échoué —, ni `pass` — rien n'a été mesuré. Comme pour une cause extérieure,
# `retries` est remis comme avant, et un plafond empêche la boucle sans fin.
MAX_IMPOSSIBLE_IN_A_ROW = 3


def _impossible_record(state: dict, item_id: str) -> dict:
    """`total` depuis toujours, `streak` depuis le dernier essai COMPTÉ, `since` la date."""
    book = state.setdefault("proof_impossible", {})
    rec = book.get(item_id)
    if not isinstance(rec, dict):
        rec = {}
    rec = {"total": int(rec.get("total", 0) or 0),
           "streak": int(rec.get("streak", 0) or 0),
           "since": rec.get("since", ""),
           "last": rec.get("last", ""),
           "reason": rec.get("reason", ""),
           "read": int(rec.get("read", 0) or 0)}
    book[item_id] = rec
    return rec


def requalify_impossible_attempt(state: dict, item_id: str,
                                 st: dict) -> tuple[str, str]:
    """La preuve était IMPOSSIBLE : l'essai est CLASSÉ À PART, jamais débité.

    Rend `("requalifie"|"bloque", ce qu'il faut dire)`. Dans les DEUX cas `retries` revient
    comme avant l'essai. Au-delà de MAX_IMPOSSIBLE_IN_A_ROW d'affilée on n'essaie plus non
    plus : l'item est BLOQUÉ et la cause est nommée au superviseur — une machine qui ne peut
    pas mesurer ne se débloque pas en réessayant."""
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    rec = _impossible_record(state, item_id)
    rec["total"] += 1
    rec["streak"] += 1
    rec["read"] += 1
    rec["last"] = now
    rec["since"] = rec["since"] or now
    rec["reason"] = st.get("reason", "inconnue")
    avant = int(state.setdefault("retries", {}).get(item_id, 0) or 0)
    state["retries"][item_id] = max(0, avant - 1)
    verrou = ""
    if int(st.get("lock_held_s", -1)) >= 0:
        verrou = (f" Verrou de déploiement pid {st.get('lock_pid')}, VIVANT, tenu depuis "
                  f"{impossible_state.human(st['lock_held_s'])}.")
    elif str(st.get("lock_pid", "-")) not in ("-", ""):
        verrou = f" Verrou pid {st.get('lock_pid')} : ne répond plus."
    dit = (f"essai CLASSÉ À PART, NON COMPTÉ : la preuve était IMPOSSIBLE "
           f"({impossible_state.cause(st)}), bras {st.get('arm')}, depuis "
           f"{impossible_state.human(st.get('since_s', -1))}.{verrou} "
           f"retries {avant} → {state['retries'][item_id]}. "
           f"{rec['streak']}e d'affilée sur cet item, {rec['total']} en tout, "
           f"depuis {rec['since']}.")
    if rec["streak"] > MAX_IMPOSSIBLE_IN_A_ROW:
        return ("bloque",
                dit + f" Au-delà de {MAX_IMPOSSIBLE_IN_A_ROW} d'affilée on n'essaie plus : "
                      f"l'item est BLOQUÉ tant que la machine ne peut pas mesurer. Aucun "
                      f"essai n'a été débité pour autant.")
    return ("requalifie", dit)


# JOURNAL/preuve-impossible — LE JOURNAL DE VALIDATION NE COMMENCE PLUS PAR UN DIAGNOSTIC QUE
# LA PORTE VA CONTREDIRE. `validators/generic.sh` écrit « proof.txt absent ou vide » en
# PREMIER quand la preuve était impossible : c'est la seule chose qu'il puisse voir, et
# DIRECTIVES 5 interdit d'y toucher. Le verdict qui requalifie — « aucune preuve n'était
# possible » — était apposé PLUS BAS dans le même fichier. Qui lit de haut en bas lisait donc
# d'abord le mauvais diagnostic, et repartait chercher un défaut de worker là où il n'y avait
# qu'une machine indisponible.
#
# Ici l'orchestrateur RÉÉCRIT le journal de cet essai : la cause nommée d'abord, le texte du
# validateur ensuite, tel quel et sans en retirer un octet. Le journal d'un essai ORDINAIRE
# n'est jamais touché.
ENTETE_IMPOSSIBLE = "PREUVE IMPOSSIBLE"
# NOM-LITTERAL-ATTENDU: message-du-juge-pas-un-chemin
CONTREDIT = "proof.txt absent ou vide"


def journal_contredit(texte: str) -> bool:
    """La première ligne accuse-t-elle une absence que le reste du journal requalifie."""
    premiere = next((l for l in (texte or "").splitlines() if l.strip()), "")
    return CONTREDIT in premiere and ENTETE_IMPOSSIBLE not in premiere


def ecrire_journal_impossible(validator_log: Path, st: dict, gate_reason: str,
                              dit: str) -> int:
    """Réécrit le journal de l'essai : la cause d'abord. Rend 1 si la première ligne du
    validateur contredisait le verdict — c'est ce compte-là qu'on publie."""
    try:
        corps = validator_log.read_text(errors="replace")
    except OSError:
        corps = ""
    contredisait = 1 if journal_contredit(corps) else 0
    entete = (f"{ENTETE_IMPOSSIBLE} : aucune mesure n'était possible pour cet essai — "
              f"{impossible_state.cause(st or {})}. Bras {(st or {}).get('arm', '?')}, "
              f"impossible depuis "
              f"{impossible_state.human((st or {}).get('since_s', -1))}. Ce que le validateur "
              f"écrit plus bas décrit l'ABSENCE de preuve, pas un défaut du travail : l'essai "
              f"n'est pas compté.")
    try:
        validator_log.write_text(entete + "\n\n" + corps.rstrip("\n")
                                 + "\n\n" + gate_reason + "\n\n" + dit + "\n",
                                 encoding="utf-8")
    except OSError:
        pass
    return contredisait


# ============================================================
# L'ECRIVAIN DE LA PREUVE, ATTENDU AVANT DE JUGER
# ============================================================
PROOF_WRITER_WAIT_MAX = int(os.environ.get("AUTOPORT_JUDGE_WAIT_MAX", "1200"))


def proof_writer_alive(item_id: str, reports_dir: str | None = None) -> tuple[int, str]:
    """Le pid de la course qui ECRIT la preuve de cet item, et l'instant ou elle a pris le
    verrou. (0, "") quand personne n'ecrit.

    Le nom du verrou vient de l'AUTORITE (`lib/impossible.py`), comme celui de la preuve : un
    nom fabrique ici serait le deuxieme nommeur, et il divergerait en silence.

    `reports_dir` n'existe que pour le banc (`lib/inflight_selftest.py`), qui doit poser ses
    faux verrous ailleurs que dans les rapports de production. La production ne le passe
    jamais : elle lit le dossier que ce fichier nomme."""
    racine = reports_dir or str(AUTOPORT_DIR / "reports")
    for suffix in impossible_state.SUFFIXES:
        path = Path(impossible_state.arm_path(racine, item_id, "writer", suffix))
        try:
            champs = impossible_state.parse(path.read_text(errors="replace"))
        except OSError:
            continue
        pid = champs.get("pid", "")
        if pid.isdigit() and impossible_state.pid_alive(int(pid)):
            return int(pid), champs.get("at", "-")
    return 0, ""


def wait_for_proof_writer(item_id: str, ceiling: int = PROOF_WRITER_WAIT_MAX) -> tuple[int, int]:
    """Attendre, borne, que plus aucune course n'ecrive la preuve de cet item.

    Rend (secondes attendues, pid rencontre). Un zero en deuxieme position veut dire que
    personne n'ecrivait : le juge est passe apres la chaine, comme il doit."""
    pid, _ = proof_writer_alive(item_id)
    if not pid:
        return 0, 0
    debut = time.monotonic()
    while time.monotonic() - debut < ceiling:
        vivant, _ = proof_writer_alive(item_id)
        if not vivant:
            break
        time.sleep(2)
    return int(time.monotonic() - debut), pid


# ============================================================
# LA COURSE QUE LE WORKER A LAISSEE EN VOL (2026-09-16)
# ============================================================
# Le 16/09, trois essais ont ete detruits en cinquante minutes — ao-prepass-tie-alpha 14 et 15,
# perf-mips2c-neon 10. Le worker lance `proof_run.sh <id> <bras>` en arriere-plan, arme un
# moniteur sur son PID, et TERMINE SON TOUR : « En vol — j'attends la notification ». En mode
# `-p` cette notification n'arrive jamais. La CLI se tait, `STALL_POST_RESULT_SEC` expire, et
# `_kill('post-result')` envoie SIGTERM au GROUPE de processus du worker : la course part avec
# lui. Le juge lit alors « proof.txt absent ou vide » et l'essai est COMPTE. L'essai 14 avait
# pourtant trouve la cause de treize essais aveugles ; ce travail a ete perdu deux fois.
#
# `wait_for_proof_writer` n'y pouvait rien : il tourne APRES la boucle, quand la course est
# deja morte — ou avant qu'elle ait pris son verrou.
#
# CE QUI CHANGE : avant de fermer, on REGARDE si une course de preuve de CET item ecrit
# encore. Si oui, aucun signal n'est envoye ; on attend sa fin, bornee par le `proof_timeout`
# de l'item plus une marge, et on juge APRES. On ne relance jamais rien : attendre n'est pas
# produire, et une course qu'on n'a pas vue n'est pas une course qu'on invente.
INFLIGHT_GRACE_SEC = 120.0     # la marge du contrat, par-dessus le proof_timeout de l'item
INFLIGHT_DEFAULT_TIMEOUT = {0: 120.0, 1: 180.0}   # ce que proof_run.sh prend faute d'item


def inflight_ceiling_s(item: dict) -> float:
    """La borne de l'attente : le `proof_timeout` de l'item + la marge. Jamais l'infini.

    Sans `proof_timeout`, on reprend le defaut que `lib/proof_run.sh` s'applique a lui-meme
    (120 s en x86, 180 s sur appareil) : une borne inventee ici divergerait de la sienne."""
    brut = item.get("proof_timeout")
    try:
        secondes = float(brut)
    except (TypeError, ValueError):
        secondes = INFLIGHT_DEFAULT_TIMEOUT[1 if item.get("device") else 0]
    return secondes + INFLIGHT_GRACE_SEC


def proof_run_processes(item_id: str) -> list[int]:
    """Les PID des courses `proof_run.sh <item_id>` vivantes, le notre exclu.

    ON COMPARE LES ARGUMENTS UN PAR UN, JAMAIS UN MOTIF SUR LA LIGNE ENTIERE. Un `pkill -f`
    sans crochet se matche lui-meme ; et la ligne de commande d'un worker qui CITE le nom du
    script — ce qu'il fait des qu'il le lance — serait prise pour une course. Un argument
    dont le nom de fichier est `proof_run.sh`, ET un argument EGAL a l'id de l'item : c'est
    la course de CET item, ou rien. Un item voisin en vol ne retient pas ce juge-ci."""
    trouves: list[int] = []
    moi = os.getpid()
    try:
        entrees = list(os.scandir("/proc"))
    except OSError:
        return trouves
    for entree in entrees:
        if not entree.name.isdigit():
            continue
        pid = int(entree.name)
        if pid == moi:
            continue
        try:
            brut = (Path(entree.path) / "cmdline").read_bytes()
        except OSError:          # le processus est mort entre le scandir et la lecture
            continue
        args = [a.decode("utf-8", "replace") for a in brut.split(b"\0") if a]
        if item_id not in args:
            continue
        if not any(a.rsplit("/", 1)[-1] == "proof_run.sh" for a in args):
            continue
        trouves.append(pid)
    return sorted(trouves)


def inflight_proof_run(item_id: str, reports_dir: str | None = None) -> tuple[int, str]:
    """(pid, par quoi elle a ete vue) de la course de preuve VIVANTE de cet item.

    DEUX TEMOINS, PARCE QU'UN SEUL EST AVEUGLE LA MOITIE DU TEMPS. Le verrou d'ecriture n'est
    pris qu'apres le prologue de `proof_run.sh` : une course de trois secondes n'a encore rien
    ecrit. Le processus, lui, existe des le premier instant, mais il disparait avant que le
    verrou soit relache si la course meurt. On regarde les deux, et on DIT lequel a parle."""
    pid, _ = proof_writer_alive(item_id, reports_dir)
    if pid:
        return pid, "verrou"
    vivants = proof_run_processes(item_id)
    if vivants:
        return vivants[0], "processus"
    return 0, ""


def post_result_verdict(item_id: str, carnet: dict, idle: float) -> bool:
    """Vrai = NE PAS fermer maintenant : une course de preuve de cet item ecrit toujours.

    Aucun signal n'est envoye depuis ici. Cette fonction ne fait que dire « attends encore »,
    et elle tient le carnet que le journal de l'essai publiera : le PID vu, par quel temoin,
    combien de temps on a attendu, et si c'est la borne qui a tranche ou la course qui a fini.
    Faux la premiere fois qu'aucune course ne vit : la fermeture d'avant reprend, intacte."""
    maintenant = time.monotonic()
    pid, vu_par = inflight_proof_run(item_id, carnet.get("reports_dir"))
    if pid:
        if not carnet.get("pid"):
            carnet["pid"] = pid
            carnet["how"] = vu_par
            carnet["since"] = maintenant
            carnet["deadline"] = maintenant + float(carnet.get("ceiling_s") or 0.0)
            carnet["idle_at_hold_s"] = round(idle, 1)
            log(f"· résultat émis, mais une course de preuve de {item_id} ÉCRIT encore "
                f"(pid={pid}, vue par le {vu_par}) — AUCUN signal : on attend sa fin, "
                f"borne {float(carnet.get('ceiling_s') or 0.0):.0f}s", "cyan")
        carnet["waited_s"] = round(maintenant - carnet["since"], 1)
        carnet["holds"] = int(carnet.get("holds", 0)) + 1
        if maintenant < carnet["deadline"]:
            return True
        carnet["expired"] = 1
        log(f"· la course de preuve (pid={carnet['pid']}) dépasse la borne "
            f"{float(carnet.get('ceiling_s') or 0.0):.0f}s — on ferme, et le juge tranchera "
            f"sur ce qu'elle aura écrit", "yellow")
        return False
    if carnet.get("pid") and not carnet.get("ended"):
        carnet["waited_s"] = round(maintenant - carnet["since"], 1)
        carnet["ended"] = 1
        log(f"· la course de preuve (pid={carnet['pid']}) est terminée après "
            f"{carnet['waited_s']:.0f}s — fermeture, et jugement APRÈS elle", "green")
    return False


def _impossible_reset(state: dict, item_id: str) -> None:
    """Un essai JUGÉ remet la série à zéro — le compte `total` et `read`, jamais."""
    rec = _impossible_record(state, item_id)
    if rec["streak"]:
        rec["streak"] = 0
        save_state(state)


def impossible_read_counts(state: dict) -> tuple[int, int]:
    """(états LUS par la porte, verdicts REQUALIFIÉS) — ce que le livrable demande de publier."""
    book = state.get("proof_impossible") or {}
    lus = sum(int((v or {}).get("read", 0) or 0) for v in book.values() if isinstance(v, dict))
    req = sum(int((v or {}).get("total", 0) or 0) for v in book.values() if isinstance(v, dict))
    return (lus, req)


def fatal_config_reason(path: Path) -> str:
    """A model/auth/request error that will repeat forever, not a rate limit."""
    for ev in _iter_events(path):
        error = cli_backend.codex_error(ev)
        if error and cli_backend.error_kind(error) == "config":
            return error
        for st in _api_error_statuses(ev):
            if st in (401, 403, 404):
                return (f"erreur API {st} (modèle / authentification / requête). "
                        f"Vérifie le modèle « {MODEL} » et les identifiants.")
    try:
        if "may not exist or you may not have access" in path.read_text(errors="replace"):
            return (f"le modèle « {MODEL} » n'existe pas ou n'est pas accessible "
                    f"(404) — corrige model-profiles.json.")
    except OSError:
        pass
    return ""


def rate_reset_from_log(path: Path) -> int | None:
    """The reset epoch the API itself returned on a refusal."""
    best = None
    for ev in _iter_events(path):
        if ev.get("type") != "rate_limit_event":
            continue
        info = ev.get("rate_limit_info", {}) or {}
        if str(info.get("status", "")) not in ("rejected", "blocked", "exceeded"):
            continue
        reset = info.get("resetsAt")
        if isinstance(reset, (int, float)) and reset > 0:
            best = max(best or 0, int(reset))
    return best


def nap(seconds: float) -> None:
    """Sleep in one-second slices so a Ctrl-C is felt now, not in five minutes.

    PEP 475 makes `time.sleep` RESUME after a signal handler returns, so a plain
    `time.sleep(300)` swallowed the operator's interrupt for the rest of it."""
    end = time.monotonic() + seconds
    while not HALT and time.monotonic() < end:
        time.sleep(min(1.0, end - time.monotonic()))


def sleep_until(epoch: int, label: str) -> None:
    """Sleep until a UTC epoch, waking early on HALT."""
    while not HALT:
        remaining = epoch - int(time.time())
        if remaining <= 0:
            return
        when = datetime.fromtimestamp(epoch, tz=timezone.utc)
        log(f"En attente de {label} : {format_duration(remaining)} "
            f"(jusqu'à {when.isoformat()})", "dim")
        nap(min(remaining, 60))


# ============================================================
# Git checkpointing — the worker's paths, never the whole tree
# ============================================================
#
# `git add -A` swallowed everything the SUPERVISOR wrote while a worker ran
# (journal, directives, milestones) into the worker's own commit, which made the
# supervisor's trace invisible in the history. The orchestrator now stages
# exactly the paths the tree shows as dirty, minus the harness's own state.

_HARNESS_STATE_FILES = {
    ".autoport/state.json",
    ".autoport/backlog.yaml",
    ".autoport/milestones.yaml",
    ".autoport/.orchestrator.lock",
    ".autoport/.supervisor-watch.lock",
    ".autoport/.scope_stamp",
    ".autoport/.directives_issued",
    ".autoport/.last_apk_build_sha",
    ".autoport/.last_owner_notify.json",
    ".autoport/.commit_quarantine.json",
    ".autoport/DIRECTIVES.md",
}

_HARNESS_STATE_PREFIXES = (
    ".autoport/logs/",
    ".autoport/archive/",
    ".autoport/plans/",
    ".autoport/prompts/",
    ".autoport/owner-ok/",
    ".autoport/.phase-claim.",
)


def _is_harness_state(path: str) -> bool:
    return (path in _HARNESS_STATE_FILES
            or path.startswith(_HARNESS_STATE_PREFIXES))


def dirty_paths() -> list[str]:
    """Every path git reports as changed, renames counted on both sides.

    `-uall` is not optional: the default collapses an untracked directory to
    `dir/`, and staging `.autoport/` would put state.json, the logs and
    DIRECTIVES.md straight back into the worker's commit — the exact thing this
    function exists to prevent."""
    try:
        r = subprocess.run(["git", "status", "--porcelain=v1", "-z", "-uall"],
                           cwd=REPO_ROOT, capture_output=True, text=True, timeout=120)
    except Exception:  # noqa: BLE001
        return []
    fields = r.stdout.split("\0")
    out: list[str] = []
    i = 0
    while i < len(fields):
        entry = fields[i]
        i += 1
        if len(entry) < 4:
            continue
        xy, path = entry[:2], entry[3:]
        if "R" in xy or "C" in xy:          # rename/copy: source is the NEXT field
            if i < len(fields) and fields[i]:
                out.append(fields[i])
            i += 1
        out.append(path)
    return out


def worker_paths() -> list[str]:
    """The dirty paths a worker's checkpoint may carry."""
    return sorted({p for p in dirty_paths() if p and not _is_harness_state(p)})


# ============================================================
# LE TERRITOIRE MOTEUR — UNE SEULE DÉFINITION, LUE PAR LES DEUX PORTES
# ============================================================
# Les chemins du MOTEUR. Un fichier sale sous l'un d'eux est du code qui part dans un
# binaire ; sale et non commité, c'est un binaire que personne ne peut rejouer depuis HEAD.
#
# 2026-09-12 — IL Y EN AVAIT DEUX. GATE 0 lisait cette constante (cinq dossiers, `common/`
# compris) ; GATE 1 en codait une AUTRE en dur dans son corps, sans `common/`. Un fichier de
# `common/` était donc du travail réel pour une porte et rien du tout pour l'autre, et la
# divergence grossissait au prochain dossier ajouté. Une seule liste désormais — et chaque
# porte ENREGISTRE celle qu'elle a effectivement employée dans `GATE_TERRITORY` : une
# constante partagée ne prouve rien tant qu'on n'a pas mesuré que la porte la LIT.
_ENGINE_PREFIXES = ("game/", "common/", "android/", "goal_src/", "goalc/")

# Ce que chaque porte a REELLEMENT lu, rempli au moment de la lecture. Une liste vide se lit
# « cette porte n'a pas encore tourné », jamais « elle lit la bonne ».
GATE_TERRITORY: dict = {"gate0": [], "gate1": [], "source": "_ENGINE_PREFIXES"}


def engine_prefixes(gate: str = "") -> tuple[str, ...]:
    """LA liste du territoire moteur. `gate` consigne QUI l'a lue."""
    if gate:
        GATE_TERRITORY[gate] = list(_ENGINE_PREFIXES)
    return _ENGINE_PREFIXES


def engine_dirty_paths() -> list[str]:
    """Les chemins sales qui portent du code moteur, tels que git les rapporte."""
    return sorted({p for p in dirty_paths() if p and p.startswith(engine_prefixes("gate0"))})


def foreign_dirty_engine_paths(baseline) -> list[str]:
    """Ce qui était sale AVANT l'essai et l'est ENCORE à la porte : le travail d'un AUTRE.

    La causalité est dans le `baseline` : un chemin que l'essai a trouvé sale en arrivant,
    il ne l'a pas produit. S'il est toujours sale au moment de conclure, l'essai a mesuré
    un binaire bâti par-dessus le chantier non commité de quelqu'un d'autre — le 2026-09-12,
    l'APK publié à 03:05 portait 6390 suppressions qu'aucun commit ne décrivait."""
    # LA PORTE DÉCLARE SON TERRITOIRE MÊME QUAND ELLE N'A RIEN À REFUSER. Sans cette ligne,
    # un arbre propre — le cas courant — laissait `GATE_TERRITORY["gate0"]` vide, et la
    # comparaison des deux listes ne comparait rien.
    engine_prefixes("gate0")
    if not baseline:
        return []
    return sorted(set(engine_dirty_paths()) & set(baseline))


# COMPTABILITÉ DE L'INDEXATION. Publiée terme par terme, jamais réduite à un booléen :
# « le commit a échoué » ne dit pas si UN chemin a fait tomber les 63 autres.
COMMIT_PATHS_STATS: dict = {
    "batches": 0,          # appels avec au moins un chemin
    "indexed": 0,          # chemins que `git add` a ACCEPTÉS
    "refused": 0,          # chemins que `git add` a REFUSÉS, nommés dans le journal
    "rescued": 0,          # chemins indexés APRÈS qu'un refus ait fait tomber le lot entier
    "empty_avoided": 0,    # commits vides évités, DITS dans le journal
    "commits": 0,
    "quarantined": 0,      # chemins MIS DE COTE parce que durablement non committables
    "quarantined_skipped": 0,  # presentations evitees grace a la mise de cote
    "last_refused": [],    # [[chemin, raison rendue par git]] du dernier appel
}


# ============================================================
# LA MISE DE CÔTÉ — un chemin durablement non committable est SIGNALÉ UNE FOIS
# ============================================================
# Signalement du 2026-09-12 : le correctif « un chemin refusé n'emporte plus les autres » ne
# PERD plus le lot, mais il ne RÉSOUT pas le chemin fautif. Un chemin que `git add` refuse ET
# que `git commit` ne sait pas davantage prendre reste sale INDÉFINIMENT : il est re-présenté
# et re-refusé à chaque essai, et il rallume GATE 0 sur tous les items qui suivent. Une saleté
# permanente qui reboucle est pire que la perte qu'elle remplace.
#
# La mise de côté est DATÉE et publiée : elle ne fait pas disparaître le chemin, elle arrête
# de le représenter et le NOMME à chaque passage. Le superviseur tranche ; aucun worker n'a le
# droit de nettoyer l'arbre d'un autre item.
def quarantine_path() -> Path:
    """Lu par une fonction, jamais figé à l'import : un banc déplace `AUTOPORT_DIR`."""
    return AUTOPORT_DIR / ".commit_quarantine.json"


def load_quarantine() -> dict:
    try:
        raw = json.loads(quarantine_path().read_text())
    except (OSError, ValueError):
        return {}
    return {k: v for k, v in raw.items() if isinstance(v, dict)} if isinstance(raw, dict) else {}


def save_quarantine(book: dict) -> None:
    f = quarantine_path()
    try:
        f.parent.mkdir(parents=True, exist_ok=True)
        tmp = f.with_name(f.name + f".tmp.{os.getpid()}")
        tmp.write_text(json.dumps(book, indent=2, sort_keys=True))
        os.replace(tmp, f)
    except OSError as e:  # noqa: BLE001 — un registre qu'on ne peut pas écrire se DIT
        log(f"mise de côté NON enregistrée ({e}) : le chemin sera re-présenté", "yellow")


def _still_refused(path: str) -> bool:
    """Le chemin est-il TOUJOURS sale ET toujours refusé, après la tentative de commit ?

    Les deux conditions, jamais une seule : la suppression déjà indexée du 12/09 est refusée
    par `git add` mais `git commit -- <chemin>` sait la prendre — elle n'est pas durable et
    ne doit surtout pas être mise de côté."""
    st = subprocess.run(["git", "status", "--porcelain=v1", "-uall", "--", path],
                        cwd=REPO_ROOT, capture_output=True, text=True)
    if st.returncode != 0 or not st.stdout.strip():
        return False
    return not _git_add_one(path, dry=True)[0]


def _git_add_one(path: str, dry: bool = False) -> tuple[bool, str]:
    """Indexe UN chemin. Rend (ok, la raison que git a donnée) — jamais une exception.

    `dry=True` SONDE sans toucher à l'index (`git add -n`) : même code de retour, même
    message de git, index intact. C'est ce qu'il faut pour REMESURER un refus après coup —
    une mesure qui indexe au passage laisserait un chemin en attente dans l'index du worker
    suivant."""
    r = subprocess.run(["git", "add"] + (["-n"] if dry else []) + ["--", path],
                       cwd=REPO_ROOT, capture_output=True, text=True)
    if r.returncode == 0:
        return True, ""
    why = " ".join(((r.stderr or r.stdout) or "").split())[:200]
    return False, why or f"git add a rendu {r.returncode} sans un mot"


def _staged_under(paths: list[str]) -> bool:
    """Y a-t-il quelque chose d'indexé sous ces chemins ?

    `git diff --cached --pathspec-from-file` N'EXISTE PAS (git 2.53 sort en 129, usage) :
    l'ancien garde-fou rendait donc TOUJOURS 129, ne valait jamais 0, et le commit vide
    partait quand même jusqu'à git pour échouer là-bas, sans que rien ne le dise. Les
    pathspecs en argv, elles, sont acceptées et TOLÉRANTES : un chemin inconnu n'y fait
    pas d'erreur."""
    r = subprocess.run(["git", "diff", "--cached", "--name-only", "-z", "--", *paths],
                       cwd=REPO_ROOT, capture_output=True, text=True)
    if r.returncode != 0:
        return True                        # inconnu : on laisse git trancher au commit
    return bool(r.stdout.replace("\0", "").strip())


def _mettre_de_cote(refused: list, book: dict) -> None:
    """Après la tentative de commit : les refus qui SURVIVENT sont mis de côté, une fois.

    Un refus qui a disparu (la suppression déjà indexée que `git commit` a prise) n'est PAS
    durable et ne doit rien déclencher : on remesure au lieu de croire le premier refus."""
    neufs = []
    for one, reason in refused:
        if one in book or not _still_refused(one):
            continue
        book[one] = {"since": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                     "reason": reason[:200], "item": "", "refusals": 1}
        neufs.append(one)
    if not neufs:
        return
    COMMIT_PATHS_STATS["quarantined"] += len(neufs)
    save_quarantine(book)
    for one in neufs:
        log(f"  chemin MIS DE CÔTÉ (signalé une fois, plus jamais re-présenté) : {one} — "
            f"{book[one]['reason']}. Le superviseur tranche ; ce registre est "
            f"{quarantine_path()}.", "yellow")


def git_commit_paths(item_id: str, message: str, paths: list[str]) -> bool:
    """Commit ONLY `paths`. Returns True if a commit was created.

    UN CHEMIN QUI REFUSE DE S'INDEXER N'EMPORTE PLUS LES AUTRES. Le 2026-09-12 à 02:26,
    à la fermeture de `lighting-legacy-purge`, un seul `git add` portait les 64 chemins
    sales ; l'un d'eux — `PbrTestPattern.cpp`, dont la suppression était DÉJÀ INDEXÉE,
    donc absent de l'arbre COMME de l'index — a fait sortir git en fatal, et AUCUN des 64
    n'a été commité. 357 insertions et 6390 suppressions ont survécu dans l'arbre sans
    qu'aucun commit les décrive, et l'APK publié à 03:05 en portait le code.

    Le lot rapide reste tenté d'abord (un seul `git add` pour 64 chemins). S'il tombe, on
    reprend CHEMIN PAR CHEMIN : chaque refus est nommé avec la raison de git, et les autres
    passent. Le commit garde d'abord la liste ENTIÈRE — `git commit -- <chemin>` sait
    committer une suppression déjà indexée que `git add` refuse — et n'est retenté sans les
    chemins fautifs que s'il tombe à son tour."""
    if not paths:
        return False
    stats = COMMIT_PATHS_STATS
    stats["batches"] += 1
    stats["last_refused"] = []

    # LES CHEMINS DÉJÀ MIS DE CÔTÉ NE SONT PLUS PRÉSENTÉS — mais ils sont NOMMÉS, avec leur
    # date. Les représenter, c'est refaire échouer le même `git add` à chaque essai de chaque
    # item, indéfiniment.
    book = load_quarantine()
    mis_de_cote = [x for x in paths if x in book]
    paths = [x for x in paths if x not in book]
    if mis_de_cote:
        stats["quarantined_skipped"] += len(mis_de_cote)
        for one in mis_de_cote:
            log(f"  chemin MIS DE CÔTÉ le {book[one].get('since', '?')}, NON re-présenté : "
                f"{one} — {book[one].get('reason', 'raison non enregistrée')}", "yellow")
    if not paths:
        log(f"RIEN À PRÉSENTER pour {item_id} : les {len(mis_de_cote)} chemin(s) du lot sont "
            f"tous mis de côté. Le superviseur doit les commiter ou les défaire.", "yellow")
        return False

    spec = "\0".join(paths)
    add = subprocess.run(["git", "add", "--pathspec-from-file=-", "--pathspec-file-nul"],
                         cwd=REPO_ROOT, input=spec, capture_output=True, text=True)
    indexed: list[str] = list(paths)
    refused: list[list[str]] = []
    if add.returncode != 0:
        why = " ".join(((add.stderr or add.stdout) or "").split())[:200]
        log(f"git add du lot a échoué ({why}) — REPRISE CHEMIN PAR CHEMIN sur "
            f"{len(paths)} chemin(s) : un chemin fautif n'emporte plus les autres", "yellow")
        indexed = []
        for one in paths:
            ok, reason = _git_add_one(one)
            if ok:
                indexed.append(one)
            else:
                refused.append([one, reason])
                log(f"  chemin REFUSÉ par git add : {one} — {reason}", "yellow")
        stats["rescued"] += len(indexed)
    stats["indexed"] += len(indexed)
    stats["refused"] += len(refused)
    stats["last_refused"] = refused

    if not _staged_under(paths):
        # DIT, jamais silencieux : un essai qui se ferme sur un commit vide laisse croire
        # que son travail est enregistré.
        stats["empty_avoided"] += 1
        log(f"COMMIT VIDE ÉVITÉ pour {item_id} : {len(paths)} chemin(s) présentés, "
            f"{len(indexed)} indexé(s), {len(refused)} refusé(s), RIEN d'indexé sous eux.",
            "yellow")
        for one, reason in refused:
            log(f"  chemin refusé et NON COMMITÉ : {one} — {reason}", "yellow")
        # ICI AUSSI : c'est le cas où le lot ne contient QUE des chemins impossibles. Sans
        # cette ligne ils seraient re-présentés à chaque essai, pour toujours.
        _mettre_de_cote(refused, book)
        return False

    def _commit(plist: list[str]):
        if not plist:
            return None
        return subprocess.run(["git", "commit", "-m", f"[autoport/{item_id}] {message}",
                               "--pathspec-from-file=-", "--pathspec-file-nul"],
                              cwd=REPO_ROOT, input="\0".join(plist),
                              capture_output=True, text=True)

    r = _commit(paths)
    if (r is None or r.returncode != 0) and refused:
        why = " ".join((((r.stderr or r.stdout) if r else "") or "").split())[:200]
        log(f"git commit a refusé le lot entier ({why}) — nouvelle tentative SANS les "
            f"{len(refused)} chemin(s) refusé(s)", "yellow")
        r = _commit(indexed)
    _mettre_de_cote(refused, book)
    if r is None or r.returncode != 0:
        why = " ".join((((r.stderr or r.stdout) if r else "") or "").split())[:300]
        log(f"git commit a échoué : {why}", "yellow")
        for one, reason in refused:
            log(f"  chemin refusé et NON COMMITÉ : {one} — {reason}", "yellow")
        return False
    stats["commits"] += 1
    log(f"  commit {item_id} : {len(indexed)} chemin(s) indexé(s), "
        f"{len(refused)} refusé(s)", "yellow" if refused else "green")
    return True


def git_push() -> None:
    subprocess.run(["git", "push", "-u", "origin", "HEAD"], cwd=REPO_ROOT, check=False)


# ============================================================
# Close-gate — defense-in-depth against false-greens
# ============================================================
#
# Owner mandate (2026-06-30): per-item validators kept FALSE-GREENING (marking
# work "done" that wasn't) — collision/jungle/flicker all slipped a lax check and
# only the owner's eye caught them. This central gate runs AFTER the validator
# exits 0 and re-checks the false-green patterns we actually hit:
#   1. validator passes on ZERO code change (a stub / no-op item),
#   2. validator passes while the DEVICE runs a stale/mixed build,
#   3. validator passes but an ACQUIS the owner already validated is broken,
#   4. validator passes but the OWNER hasn't looked at it yet.

def _supervisor_anchor(item_id: str | None = None) -> str:
    """The 'no new game fix' anchor the gate uses to prove real work.
    Item-aware: mid-run [autoport/supervisor] journal commits must NOT advance
    the anchor past the item's own fix commits — Gcrash-blueeco 2026-07-02:
    the anchor postdated the real fix commits and GATE 1 false-negatived a
    device-proven fix. Falls back to HEAD~1."""
    def _log(*extra: str) -> list[str]:
        r = subprocess.run(["git", "log", "--format=%H", *extra],
                           cwd=REPO_ROOT, capture_output=True, text=True)
        return [l for l in r.stdout.splitlines() if l.strip()]

    if item_id:
        item_commits = _log("--grep", rf"\[autoport/{re.escape(item_id)}\]")
        if item_commits:
            pre = _log("--grep", r"\[autoport/supervisor\]", f"{item_commits[-1]}^")
            if pre:
                return pre[0]
    lines = _log("--grep", r"\[autoport/supervisor\]")
    return lines[0] if lines else "HEAD~1"


def _device_boot_check(serial: str, pkg: str = "org.opengoal.gk.jak1") -> tuple[bool, str]:
    """After deploy_verify (libgk sha chain) passes, prove the app actually BOOTS to
    in-game/render — deploy_verify does NOT catch a non-booting build (e.g. the
    'Setup failed: bundle/jak1_assets.zip' asset-unpack failure the owner hit
    2026-06-30, where the .so was fresh but the app never started). Tolerates the
    flaky first-launch (monkey/am start sometimes doesn't take) via 3 attempts.
    Fail-OPEN on adb infra errors (don't wedge the loop; the owner is the backstop).

    Launch goes through the RESOLVED launcher activity, never MainActivity directly:
    MainActivity BYPASSES LoaderActivity, the sole writer of the pack stamps, so a
    direct launch unpacks nothing and mis-reports any item that moves the packs.

    Two evidence routes:
      A. LOG route (primary) — logcat shows master-mode=game / A35-RENDER.
      B. ARTIFACT route — for phones that DROP third-party app log lines. The owner's
         Honor BKQ-N49 emits ZERO app lines (even LoaderActivity's own Log.i);
         `logcat --pid=<pid>` yields nothing but the encrypted (HKS) banner, so route
         A can NEVER confirm a boot there. Route B instead demands evidence the app
         itself produced: the process alive (and un-restarted) across the whole
         window — the pre-fix build died at t~3s on every single run — plus no
         files/gk_crash.txt (the app's own async-signal-safe crash channel writes it
         on any fatal signal), plus a native-written diagnostic under files/ refreshed
         at/after launch (proves GOAL/renderer code ran, not just a splash), plus the
         app in foreground. Route B is entered ONLY when the app emitted no log lines
         at all, so a phone that CAN surface app logs still fails when markers are
         absent. NOTE: `adb exec-out run-as ls` exits 0 even for a MISSING file, so
         every file test here reads OUTPUT, never the exit code."""
    adb = os.environ.get("ADB") or "/home/emeric/Android/platform-tools/adb"

    def sh(*args, t=40):
        return subprocess.run([adb, "-s", serial, *args], cwd=REPO_ROOT,
                              capture_output=True, text=True, timeout=t)
    try:
        sh("shell", "svc", "power", "stayon", "true")
        for p in ("debug.opengoal.f1.warp", "debug.opengoal.level.warp",
                  "debug.opengoal.render.scale", "debug.opengoal.gspeed.off",
                  "debug.opengoal.gspeed.measure"):
            sh("shell", "setprop", p, '""')
        comp = f"{pkg}/org.opengoal.gk.MainActivity"
        for ln in sh("shell", "cmd", "package", "resolve-activity",
                     "--brief", pkg).stdout.splitlines():
            if ln.strip().startswith(f"{pkg}/"):
                comp = ln.strip()
        for _ in range(3):
            sh("shell", "am", "force-stop", pkg)
            sh("exec-out", "run-as", pkg, "rm", "-f", "files/gk_crash.txt")
            t0 = int((sh("shell", "date", "+%s").stdout.strip() or "0").split()[0] or 0)
            sh("shell", "logcat", "-c")
            sh("shell", "am", "start", "-n", comp)
            first_pid = ""
            for _ in range(12):  # up to ~48s per attempt
                time.sleep(4)
                lc = sh("shell", "logcat", "-d", "-t", "500").stdout
                if "Setup failed" in lc or "jak1_assets" in lc:
                    return (False, "CLOSE-GATE/boot: app shows 'Setup failed' (asset "
                            "bundle/unpack) — the deployed build does NOT boot. Re-stage "
                            "the game assets / fix the bundle before this item can close.")
                pid = sh("shell", "pidof", pkg).stdout.strip()
                if pid and not first_pid:
                    first_pid = pid
                if pid and ("master-mode=game" in lc or "A35-RENDER frame=" in lc):
                    return (True, "")

            # ---- route B: the phone drops app logs, so ask the APP for evidence ----
            pid = sh("shell", "pidof", pkg).stdout.strip()
            if not pid or not first_pid or pid != first_pid or not t0:
                continue  # died, restarted, or no device clock -> fail closed
            applog = [l for l in sh("shell", "logcat", "-d", "--pid=" + pid).stdout.splitlines()
                      if l.strip() and not l.lstrip().startswith("---------")]
            if applog:
                continue  # this phone DOES surface app logs -> absent markers is real
            stat_out = sh("exec-out", "run-as", pkg, "sh", "-c",
                          'stat -c "%Y %n" files/*.txt 2>/dev/null').stdout
            if "gk_crash.txt" in stat_out:
                continue  # the app's own crash channel fired -> it crashed
            # L'EGALITE N'EST PLUS UNE FRAICHEUR (harness-subsecond-freshness-is-blind,
            # 2026-09-12). Cette selection etait un `int(bits[0]) >= t0` : les DEUX cotes sont a
            # la seconde entiere — `stat -c "%Y %n"` de toybox n'a pas de sous-seconde, et
            # `date +%s` non plus — donc un artefact ecrit par la course PRECEDENTE, jusqu'a
            # 0,9 s AVANT `t0`, porte le meme entier que lui et passait pour « produit pendant ».
            # Le `force-stop`, le `rm -f files/gk_crash.txt` et le `date` tiennent tres largement
            # dans une seconde. La porte de fermeture pouvait donc se declarer « prouvee par les
            # artefacts de l'app » sur un fichier de la course d'avant, EN VERT.
            # La resolution reste symetrique (seconde des deux cotes, c'est tout ce que
            # l'appareil sait rendre) ; c'est donc l'ambiguite qui est traitee, et elle l'est du
            # cote FERME : `douteux` n'est pas une preuve, et il est NOMME au lieu d'etre tu.
            fresh, douteux = freshness.classer_artefacts(stat_out, t0)
            focused = any(pkg in l for l in sh("shell", "dumpsys", "window").stdout.splitlines()
                          if "mCurrentFocus" in l)
            if douteux and not fresh:
                console.print(f"[yellow]close-gate boot-check: artefacts {douteux} au MEME "
                              f"horodatage entier que t0={t0} ({freshness.RESOLUTION_APPAREIL} "
                              f"des deux cotes) — DOUTEUX, pas frais : ils peuvent venir de la "
                              f"course precedente. Cette tentative ne les compte pas.[/yellow]")
            if fresh and focused:
                console.print(f"[green]close-gate boot-check: log-silent device — proved by "
                              f"app artifacts {fresh} (pid {pid} stable, no gk_crash.txt)[/green]")
                return (True, "")
        return (False, "CLOSE-GATE/boot: app did NOT reach in-game/render after 3 launch "
                "attempts (pid dead or no render frames) — the deployed build does not boot "
                "on device (deploy_verify passed the .so but the app is broken).")
    except Exception as e:  # noqa: BLE001 — never wedge the loop on a boot-check infra error
        console.print(f"[yellow]close-gate boot-check infra error (fail-open): {e}[/yellow]")
        return (True, "")


def owner_said_yes(item: dict) -> bool:
    """The owner's word, from the backlog field or the legacy token file.

    The token file is still read because nine items carried an `owner-ok/<id>`
    token that the old loop could never act on: the "parked" shortcut ran BEFORE
    the token check, so an item the owner had already approved was re-parked on
    sight, forever."""
    if item.get("owner_ok"):
        return True
    return (OWNER_OK_DIR / str(item.get("id", ""))).exists()


def close_gate(item: dict, pre_dirty_engine=(), validator_ok: bool = True,
               since: float = 0.0) -> tuple[str, str]:
    """La porte de fermeture. Returns (status, reason):
      ("pass", "")            -> all gates clear; the item is validated
      ("fail", reason)        -> a FIXABLE gate failed; retry + feed reason back
      ("foreign", reason)     -> CAUSE EXTÉRIEURE : rien de jugeable, l'essai ne compte pas
      ("impossible", reason)  -> AUCUNE PREUVE N'ÉTAIT POSSIBLE : nommée, datée, non comptée
      ("awaiting-owner", "")  -> gates clear, the owner still has to look

    `pre_dirty_engine` : les chemins moteur que l'essai a trouvés SALES en arrivant.
    `validator_ok`     : ce que `generic.sh` a rendu. Elle est appelée dans les DEUX cas —
                         GATE -1 doit voir un essai que le validateur a refusé, puisque c'est
                         précisément là que « preuve impossible » se lisait « pas de preuve ».
    `since`            : l'instant où l'essai a commencé. GATE -1 n'accepte qu'un état écrit
                         APRÈS : l'impossibilité d'un essai précédent ne requalifie pas celui-ci.
    """
    iid = item["id"]
    item = _reread_item(iid, item)

    # GATE -1 — UNE PREUVE IMPOSSIBLE SE LIT « IMPOSSIBLE », JAMAIS « PAS DE PREUVE ».
    # `lib/proof_run.sh` écrit un état nommé à chacune de ses sorties 3 ; jusqu'au 12/09
    # personne ne le lisait. Le validateur disait « proof.txt absent ou vide » et l'essai
    # brûlait pour une machine indisponible. On lit l'état, on NOMME la cause, et on publie
    # DEPUIS QUAND — une impossibilité de 30 s et une de six heures ne se lisent pas pareil.
    _imp = impossible_state.read(str(AUTOPORT_DIR / "reports"), iid, since=since)
    if _imp is not None:
        _verrou = ""
        if _imp["lock_held_s"] >= 0:
            _verrou = (f" Le verrou de déploiement (pid {_imp['lock_pid']}) RÉPOND ENCORE et "
                       f"est tenu depuis {impossible_state.human(_imp['lock_held_s'])}.")
        elif _imp["lock_pid"] not in ("-", ""):
            _verrou = f" Le verrou pid {_imp['lock_pid']} ne répond plus."
        return ("impossible",
                f"CLOSE-GATE/preuve-impossible: aucune preuve n'était possible pour cet essai "
                f"— {impossible_state.cause(_imp)}. Bras {_imp['arm']}, état {_imp['file']} "
                f"écrit le {_imp['at']}, impossible depuis "
                f"{impossible_state.human(_imp['since_s'])}.{_verrou} "
                f"Ce n'est pas « pas de preuve » : la machine n'a rien pu mesurer. L'essai "
                f"n'est pas compté ; c'est la CAUSE qu'il faut lever, pas la preuve qu'il "
                f"faut réécrire.")

    # Le validateur a refusé et rien n'était impossible : son verdict tient tel quel, les
    # portes suivantes n'ont rien à juger.
    if not validator_ok:
        return ("fail", "")

    # GATE 0 — L'ARBRE NE PORTE PAS LE TRAVAIL NON COMMITÉ D'UN AUTRE ITEM.
    # 2026-09-12 : un `git add` fatal a laissé 64 fichiers d'un item BLOQUÉ dans l'arbre ;
    # les essais suivants ont bâti, mesuré et publié un binaire que ce code habitait et
    # qu'aucun commit ne décrit. Une porte verte posée là-dessus juge un binaire que
    # personne ne peut reproduire depuis HEAD. On refuse de conclure, on NOMME les chemins.
    foreign = foreign_dirty_engine_paths(pre_dirty_engine)
    # UN CHEMIN DÉJÀ MIS DE CÔTÉ NE REBLOQUE PLUS — il est NOMMÉ à chaque passage, jamais
    # tu. Sans cette exception, une saleté permanente rallumerait cette porte sur tous les
    # items qui suivent, pour toujours : pire que la perte qu'elle remplace.
    _book = load_quarantine()
    _ecarte = [x for x in foreign if x in _book]
    foreign = [x for x in foreign if x not in _book]
    if _ecarte:
        log(f"· arbre : {len(_ecarte)} chemin(s) MIS DE CÔTÉ, durablement non committables, "
            f"nommés et non bloquants — "
            + ", ".join(f"{x} (depuis {_book[x].get('since', '?')})" for x in _ecarte[:8]),
            "yellow")
    if foreign:
        montre = ", ".join(foreign[:12]) + (" …" if len(foreign) > 12 else "")
        # `foreign`, JAMAIS `fail` : l'essai n'a pas échoué, il n'avait rien de reproductible
        # à juger. Le périmètre d'un worker lui interdit de commiter ou de défaire l'arbre
        # d'un autre item — le compter, c'est lui débiter un essai pour un ordre qu'on lui
        # interdit d'exécuter (signalement du 2026-09-12).
        return ("foreign",
                f"CLOSE-GATE/arbre-sale: {len(foreign)} fichier(s) moteur sont sales depuis "
                f"AVANT cet essai et le sont encore — ils appartiennent à un autre item et "
                f"aucun commit ne les décrit. Le binaire mesuré n'est pas reproductible "
                f"depuis HEAD. Chemins : {montre}. Le superviseur doit les commiter ou les "
                f"défaire ; cet essai ne doit ni se les approprier ni les effacer.")

    # GATE 1 — real translation-layer code change (anti-stub false-green).
    # An item was once marked done with ZERO code. Require a real change since
    # the supervisor anchor, unless the item declares `no_code: true`.
    #
    # GATE1/perimetre-sans-code — ELLE NE BRULE PLUS UN ESSAI POUR UN DRAPEAU ABSENT.
    # Un item dont le perimetre INTERDIT `game/ android/ goalc/ goal_src/` echouait ici
    # FORCEMENT tant que personne n'avait pose `no_code: true` a la main, et rien ne le
    # disait au LANCEMENT : seulement ici, une fois l'essai depense. Mesure du 2026-09-12,
    # essai 1 de `harness-proof-props-pin` : porte machine TENUE, refusee pour ce seul
    # drapeau. La question a une reponse LISIBLE dans le perimetre de l'item ; c'est
    # `gate_verdict.code_free_item` qui la lit, ici comme au lancement, au meme endroit.
    _sans_code, _pourquoi_sans_code = gate_verdict.code_free_item(item)
    if _sans_code and not item.get("no_code", False):
        log(f"· GATE 1 : le perimetre de {iid} interdit le code du jeu ({_pourquoi_sans_code}) "
            f"— aucun code de portage n'est exige. Le drapeau `no_code` manquait ; il n'est "
            f"plus une condition de fermeture.", "dim")
    if not _sans_code:
        anchor = _supervisor_anchor(iid)
        # LA MÊME liste que GATE 0, lue au même endroit et consignée. Elle codait
        # `["game/","android/","goalc/","goal_src/"]` en dur — `common/` manquait.
        paths = list(engine_prefixes("gate1"))
        committed = subprocess.run(["git", "diff", "--name-only", anchor, "--", *paths],
                                   cwd=REPO_ROOT, capture_output=True, text=True).stdout.splitlines()
        dirty = subprocess.run(["git", "status", "--porcelain", "--", *paths],
                               cwd=REPO_ROOT, capture_output=True, text=True).stdout.splitlines()
        # x86 emitter is LOCKED (our-x86 must == original-x86) — a change there
        # is not a legitimate port fix, so it doesn't count toward "real work".
        real = [f for f in (committed + dirty) if f.strip() and "IGenX86_64" not in f]
        if not real:
            return ("fail",
                    "CLOSE-GATE/code: le validateur sort 0 mais AUCUN code de portage n'a "
                    "changé depuis l'ancre superviseur — faux vert refusé. Un vrai correctif "
                    "touche game/ android/ goalc/ goal_src/ (jamais l'émetteur x86 verrouillé). "
                    "Si cet item ne livre légitimement aucun code, renseigne `code_scope: none` "
                    "(ou `code_scope: harness`) sur lui dans backlog.yaml.")

    # GATE 2 — device runs the fresh, CONSISTENT build (anti stale/mixed-build).
    # The validator can pass while the phone still runs an old libgk, or a MIXED
    # build (fresh CGOs + stale libgk) — exactly the 2026-06-30 flicker incident.
    if item.get("device", False):
        serial = item.get("device_serial") or os.environ.get("ANDROID_SERIAL") or _pick_device()
        # Game-aware deploy gate: a jak2/jak3 item must verify against ITS package +
        # APK, not the jak1 default (2026-07-09 Gjak2-polish stuck here twice).
        game = item.get("game") or ("jak2" if "jak2" in iid.lower()
                                    else "jak3" if "jak3" in iid.lower() else "jak1")
        dv = AUTOPORT_DIR / "lib" / "deploy_verify.sh"
        if dv.exists():
            r = subprocess.run(["bash", str(dv), serial, game],
                               cwd=REPO_ROOT, capture_output=True, text=True)
            if r.returncode != 0:
                tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-4:])
                return ("fail",
                        "CLOSE-GATE/deploy: deploy_verify a ÉCHOUÉ — rien ne prouve que "
                        "l'appareil tourne le build de HEAD (CGO/libgk périmés ou mélangés). "
                        "Rebâtis un ensemble COHÉRENT et redéploie.\n" + tail)
        pkg = item.get("device_pkg") or f"org.opengoal.gk.{game}"
        booted, why = _device_boot_check(serial, pkg)
        if not booted:
            return ("fail", why)

    # GATE 3 — ACQUIS VALIDES PAR L'OWNER (Gfont-regression, 2026-09-02). La police
    # Urbanist, fermee par sa parole le 2026-08-30, a ete cassee et AUCUNE garde ne
    # l'a vu : chaque item ne verifie que son propre perimetre, et un acquis n'est le
    # perimetre de personne. Chaque script de .autoport/acquis/ verifie un acquis
    # owner et tourne a CHAQUE fermeture. Fail-CLOSED : un acquis qu'on ne peut pas
    # prouver est un acquis qu'on ne tient pas.
    acquis_dir = AUTOPORT_DIR / "acquis"
    if acquis_dir.is_dir():
        acq_serial = ""
        if item.get("device", False):
            acq_serial = item.get("device_serial") or os.environ.get("ANDROID_SERIAL") or _pick_device()
        # 2026-09-11 — ROTATION. Mesure du 11/09 : les sept gardes se partagent trois courses du
        # jeu (220 s de budget) et la fermeture tourne 2 a 2,7 fois par chantier — ~15 min de
        # rituel par chantier, 4,7 h sur les 46 fermetures enregistrees. Owner : « un test random
        # quand ca boucle a la place pourquoi pas ».
        # LA GARANTIE QUI VA AVEC : le balayage COMPLET tombe des que le chantier va etre
        # presente a l'owner — c'est le build qu'il testera — et au plus tard toutes les trois
        # fermetures. Une fermeture intermediaire, qui ne lui livre rien, n'en fait qu'une, a
        # tour de role. Une garde qui echoue bloque toujours : fail-CLOSED inchange.
        _scripts = [x for x in sorted(acquis_dir.glob("*.sh")) if x.name != "_lib.sh"]
        _rot = AUTOPORT_DIR / ".acquis_rotation"
        _idx, _depuis = 0, 99
        try:
            _idx, _depuis = (int(x) for x in _rot.read_text().split()[:2])
        except Exception:  # noqa: BLE001 — pas de compteur = balayage complet
            pass
        _complet = bool(item.get("owner_test", True)) or _depuis >= 3 or not _scripts
        if _complet:
            _choisis, _depuis_neuf, _idx_neuf = _scripts, 0, _idx
        else:
            _choisis = [_scripts[_idx % len(_scripts)]]
            _depuis_neuf, _idx_neuf = _depuis + 1, _idx + 1
        log(f"· acquis : {'balayage complet' if _complet else 'rotation'} "
            f"({len(_choisis)}/{len(_scripts)} garde(s))", "dim")
        try:
            # Comme pytest et ses rejeux, les acquis creent leurs temporaires hors /tmp.
            # Verifier le stockage AVANT d'avancer la rotation : une garde qui n'a pas
            # pu demarrer ne doit pas etre sautee a la fermeture suivante.
            with suite_gate.suite_temporary("suite-acquis-") as acq_tmp:
                acq_env = dict(os.environ, TMPDIR=acq_tmp, TMP=acq_tmp, TEMP=acq_tmp)
                try:
                    _rot.write_text(f"{_idx_neuf} {_depuis_neuf}\n")
                except Exception:  # noqa: BLE001
                    pass
                for script in _choisis:
                    try:
                        r = subprocess.run(["bash", str(script), acq_serial], cwd=REPO_ROOT,
                                           env=acq_env, capture_output=True, text=True, timeout=600)
                    except subprocess.TimeoutExpired:
                        return ("fail", f"CLOSE-GATE/acquis: {script.name} n'a pas répondu en 600 s")
                    if r.returncode != 0:
                        tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-4:])
                        return ("fail",
                                f"CLOSE-GATE/acquis: {script.name} — un ACQUIS VALIDÉ PAR L'OWNER "
                                "n'est plus tenu (ou plus prouvable) sur ce build. L'item ne se ferme "
                                "pas tant qu'il n'est pas rétabli.\n" + tail)
                    console.print(f"[green]close-gate acquis: {script.name} ok[/green]")
        except suite_gate.SuiteTemporaryUnavailable as exc:
            return ("fail", f"CLOSE-GATE/acquis-temporaire-indisponible: {exc}")

    # 2026-09-11 — SIGNALEMENTS DU WORKER. Ce qu'il a vu de casse sans le corriger doit devenir
    # un chantier ou etre ecarte devant l'owner, jamais dormir dans un rapport ferme. Voir
    # lib/findings_gate.sh : alerte par defaut, bloquant avec `.autoport/.findings_gate_strict`.
    _fg = AUTOPORT_DIR / "lib" / "findings_gate.sh"
    if _fg.exists():
        try:
            _r = subprocess.run(["bash", str(_fg), iid], cwd=REPO_ROOT,
                                capture_output=True, text=True, timeout=120)
            _msg = (_r.stdout + _r.stderr).strip()
            if _r.returncode != 0:
                return ("fail", "CLOSE-GATE/signalements : des trouvailles du worker n'ont "
                                "aucune suite.\n" + _msg)
            if _msg:
                console.print(f"[yellow]close-gate signalements: {_msg}[/yellow]"
                              if "absent" in _msg or "NON TRIE" in _msg
                              else f"[green]close-gate signalements: {_msg.strip()}[/green]")
        except subprocess.TimeoutExpired:
            return ("fail", "CLOSE-GATE/signalements : findings_gate.sh n'a pas repondu en 120 s")

    # GATE SUITE — LA SUITE DU HARNAIS EST LUE ICI, ET NULLE PART AILLEURS.
    # MARQUEUR : CLOSE-GATE/suite
    #
    # Mesure du 2026-09-12 : 556 verts a 06:16, QUARANTE-QUATRE rouges a 15:45. L'item qui les
    # avait cassees (`dead-published-keys-round-2`, trois cles renommees en `_const`, lecteur
    # mis a jour, tests non) a ete ACCEPTE, porte verte, et personne n'a rien vu — parce que
    # `grep -n pytest orchestrator.py validators/` ne rendait RIEN. Aucune porte ne lancait la
    # suite : le vert du matin ne protegeait de rien des l'apres-midi, et le chantier qui
    # l'avait obtenu perdait son acquis en quelques heures.
    #
    # LE COUT EST DIT, JAMAIS AVALE. La suite prend 90 a 190 s (80 s mesurees le 12/09 sur 560
    # tests). Le budget retenu et la duree MESUREE sont journalises a chaque fermeture ; un
    # depassement est annonce en clair et ne refuse rien — ce n'est pas la faute de l'item qui
    # ferme. Le plafond dur, lui, refuse : une suite tuee n'a rien prouve.
    #
    # LE CALCUL N'EST PAS ICI. `lib/suite_gate.py` est le seul producteur du verdict ; cette
    # porte, le recensement de l'item et le banc l'appellent tous les trois. Deux regles
    # ecrites a deux endroits divergent en silence.
    # `since` EST LA BASE DES ROUGES (harness-close-gate-separates-inherited-reds, 14/09). Sans
    # lui, le juge remonte au premier commit de l'ITEM — pour `hdr-shadow-range` le 13/09,
    # vingt-quatre heures en arriere : tout ce que le monde avait commite depuis lui etait
    # impute a l'essai, et l'essai 2 est mort sur deux rouges du superviseur.
    _sg = suite_gate.judge(REPO_ROOT, AUTOPORT_DIR, iid, since=since)
    log(f"· suite : {_sg['collected']} test(s) collecte(s), {_sg['failed']} rouge(s), "
        f"{_sg['unwaived']} sans dispense, {_sg['duration_s']}s "
        f"(budget {_sg['budget_s']}s) — registre {_sg['registry_sha']} "
        f"({_sg['registry_entries']} entree(s), dont {_sg['self_added']} de cet item)",
        "dim" if _sg["verdict"] == "pass" else "yellow")
    if _sg["unwaived"] and _sg["unwaived"] > 0:
        log(f"· suite : {_sg['unwaived_known']} rouge(s) HERITE(S) — deja rouges a la base de "
            f"cet essai ({_sg['red_base_ref']}, {_sg['red_base_kind']}), ils ne lui sont PAS "
            f"imputes — et {_sg['unwaived_new']} NEUF(S) [{','.join(_sg['unwaived_new_list'][:4]) or '-'}]. "
            f"Rejeu {_sg['replay_seconds']}s (ran={_sg['replay_ran']}, err={_sg['replay_error']})",
            "yellow")
    if _sg["over_budget"]:
        log(f"· suite : {_sg['duration_s']}s DEPASSENT le budget de {_sg['budget_s']}s. "
            f"Ce n'est pas un refus, c'est un cout qui derive et qu'on refuse d'avaler.",
            "yellow")
    if _sg["verdict"] != "pass":
        return ("fail",
                "CLOSE-GATE/suite: la suite du harnais refuse cette fermeture.\n"
                + _sg["reason"]
                + f"\n(suite : {_sg['collected']} collecte(s), {_sg['failed']} rouge(s), dont "
                  f"{_sg['unwaived_known']} HERITE(S) non imputes ; registre "
                  f"{_sg['registry_sha']} ; base du registre {_sg['base_ref']} ; base des "
                  f"rouges {_sg['red_base_ref']} ({_sg['red_base_kind']}) ; {_sg['duration_s']}s "
                  f"+ {_sg['replay_seconds']}s de rejeu ; reproduis avec : python3 "
                  f"{AUTOPORT_DIR.name}/lib/suite_gate.py judge --item {iid} --since {int(since)})")

    # GATE 4 — l'oeil de l'owner est la porte FINALE. Un item passe donc en
    # `to-test`, jamais directement en `validated` : seul `owner_ok` le ferme.
    #
    # SAUF `owner_test: false` : sa preuve est machine (empreinte, reproductibilite, instrument
    # qui ne change aucun pixel) et l'owner n'a RIEN a regarder. L'attendre gele tout ce qui en
    # depend — le 2026-09-06, lighting-census a bloque les onze chantiers d'eclairage suivants
    # parce qu'il ne pouvait par construction jamais recevoir son feu vert.
    if item.get("owner_test", True) and item.get("owner_verify", True) and not owner_said_yes(item):
        return ("awaiting-owner", "")

    return ("pass", "")


# ============================================================
# Attempt execution
# ============================================================

SCOPE_STAMP = AUTOPORT_DIR / ".scope_stamp"   # bumped by the supervisor on a scope change


def _scope_changed(seen: str | None) -> str | None:
    """A scope change must kill the running attempt IMMEDIATELY.

    The owner lost hours twice because an attempt kept grinding the OLD scope
    after he narrowed it. Touching .autoport/.scope_stamp aborts on the next
    tick instead of waiting for the 45-minute progress watchdog. Since
    2026-09-03 that abort does NOT burn an attempt: we cut the work, so we pay
    for it."""
    try:
        return f"{SCOPE_STAMP.stat().st_mtime_ns}"
    except OSError:
        return seen


def _progress_fingerprint(item_id: str) -> str:
    """Cheap snapshot of what THIS attempt has actually produced.

    Deliberately artifact-based: an attempt that prints constantly while the
    tree stays frozen is not making progress.

    Two corrections (2026-09-03). The APK and `.autoport/tmp/` are REWRITTEN BY
    THE BUILD DAEMON on its own schedule, so an idle worker looked alive purely
    because a build finished next to it — the watchdog was measuring the wrong
    process. And a worker that reads and analyses for 45 minutes without
    touching the tree was killed 13 times, so its notes and its handoff now
    count as progress: thinking that leaves a written trace IS progress."""
    try:
        tree = subprocess.run(["git", "status", "--porcelain=v1"], cwd=REPO_ROOT,
                              capture_output=True, text=True, timeout=30).stdout
    except Exception:  # noqa: BLE001
        tree = ""
    stamps = []
    rep = REPORTS_DIR / item_id
    for pat in ("report.txt", "proof*.txt", "handoff.md", "notes/**/*", "device/*"):
        for d in rep.glob(pat):
            try:
                st = d.stat()
                stamps.append(f"{d}:{st.st_mtime_ns}:{st.st_size}")
            except OSError:
                pass
    return hashlib.sha1(("".join(sorted(stamps)) + tree).encode()).hexdigest()


def handoff_path(item_id: str) -> Path:
    return REPORTS_DIR / item_id / "handoff.md"


def read_handoff(item_id: str) -> str:
    """The previous attempt's handoff, capped at HANDOFF_MAX_LINES."""
    p = handoff_path(item_id)
    try:
        lines = p.read_text(errors="replace").splitlines()
    except OSError:
        return ""
    text = "\n".join(lines[:HANDOFF_MAX_LINES])
    if len(lines) > HANDOFF_MAX_LINES:
        text += f"\n… (tronqué : {len(lines)} lignes, plafond {HANDOFF_MAX_LINES})"
    return text.strip()


def write_minimal_handoff(item_id: str, seq: int, validator_log: Path,
                          touched: list[str], gate_reason: str) -> None:
    """What the NEXT attempt gets when this one left no note.

    A retry used to receive the item prompt plus 4 KB of validator tail and
    nothing else — no idea what the previous attempt had established, tried or
    ruled out. That is the "re-discovers everything" loop. The worker is asked
    to write this file itself; when it doesn't, the orchestrator writes the
    little it can prove from the forensic log."""
    p = handoff_path(item_id)
    p.parent.mkdir(parents=True, exist_ok=True)
    try:
        vlines = [l for l in validator_log.read_text(errors="replace").splitlines() if l.strip()]
    except OSError:
        vlines = []
    body = [
        f"# Handoff — {item_id} (essai {seq}, {datetime.now():%Y-%m-%d %H:%M})",
        "",
        "_Écrit par l'orchestrateur : cet essai n'a laissé aucune note. Ce qui suit est",
        "tout ce que la machine peut prouver, pas un compte rendu._",
        "",
        "## Dernier échec du validateur",
        "```",
        *vlines[-10:],
        "```",
    ]
    if gate_reason:
        body += ["", "## Porte de fermeture", gate_reason.splitlines()[0][:200]]
    if touched:
        body += ["", "## Fichiers touchés par cet essai"]
        body += [f"- {f}" for f in touched[:8]]
        if len(touched) > 8:
            body.append(f"- … et {len(touched) - 8} autres")
    body += ["", "## Ce qui reste", "- inconnu : à rétablir en lisant le diff ci-dessus."]
    p.write_text("\n".join(body[:HANDOFF_MAX_LINES]) + "\n")


def _item_header(item: dict, seq: int) -> str:
    """The item, in the worker's own prompt.

    The owner's words used to live only in a YAML field the prompt never
    carried; they reached the worker, if at all, through a session banner that
    resolved the wrong item half the time. They travel with the instructions
    now."""
    gate = item.get("gate") or {}
    lines = [
        "## CET ESSAI",
        "",
        f"- item : `{item['id']}` — essai {seq} (plafond {item.get('max_retries', 6)})",
        f"- ce que l'OWNER doit voir marcher : {item.get('feature', '(non renseigné)')}",
    ]
    if gate:
        # LE NOM DE LA PREUVE VIENT DE L'AUTORITE, jusque dans la consigne du worker : lui
        # donner un nom que plus personne n'ecrit, c'est l'envoyer chercher au mauvais endroit.
        _pf = impossible_state.arm_name("proof", "")
        lines.append(f"- critère machine : `{gate.get('key')} {gate.get('op')} "
                     f"{gate.get('value')}` lu dans `.autoport/reports/{item['id']}/{_pf}`")
    if item.get("device"):
        lines.append("- preuve exigée SUR APPAREIL USB : le worker est autorisé à lancer "
                     "`lib/proof_run.sh <id> device` ; `lib/pick_device.sh` choisit "
                     "l'appareil USB disponible au moment du test. SHIELD et adresses réseau interdites.")
        if item.get('device_serial'):
            lines.append(f"- appareil demandé par l'item : {item['device_serial']}")
        lines.append("- Si aucun appareil USB n'est disponible, signaler cette indisponibilité "
                     "factuelle ; ce n'est pas une interdiction de tester. Ne pas réutiliser "
                     "une ancienne preuve comme résultat de cet essai.")
    else:
        lines.append("- preuve sur x86 (`lib/proof_run.sh <id> x86`)")
    lines.append("- le validateur `.autoport/validators/generic.sh` est lancé par "
                 "l'orchestrateur, pas par toi : ta parole ne ferme rien.")
    fb = item.get("owner_feedback") or []
    if fb:
        lines += ["", "### Ce que l'owner a dit, mot pour mot"]
        for entry in fb[-4:]:
            if isinstance(entry, dict):
                lines.append(f"- {entry.get('date', '?')} : « {entry.get('text', '')} »")
    lines += ["", "---", ""]
    return "\n".join(lines)


def _delegation_preamble(effort: str) -> str:
    we = WORKER_EFFORTS
    text = (
        "## WORK ECONOMY (mandatory — manager/worker delegation)\n"
        f"You are the MANAGER ({MODEL}, effort={effort}): plan, decide, judge,\n"
        "synthesize, review. Delegate bulk execution to subagents via the Task\n"
        f"tool — they run on {SUBAGENT_MODEL} (CLAUDE_CODE_SUBAGENT_MODEL):\n"
        f"- `autoport-researcher` (effort {we.get('autoport-researcher', 'high')}): "
        "code/disassembly/log/oracle scans, symbol hunts, large-file analysis. Read-only.\n"
        f"- `autoport-implementer` (effort {we.get('autoport-implementer', 'medium')}): "
        "mechanical code edits to YOUR exact spec (files, lines, precise semantics).\n"
        f"- `autoport-tester` (effort {we.get('autoport-tester', 'medium')}): "
        "builds, qemu runs, device runs, log harvesting, screencaps.\n"
        "Keep main-thread tool calls for decisions, small precise edits, and\n"
        "VERIFYING subagent claims (read their diffs/logs yourself — trust but\n"
        "verify). Never delegate understanding: subagent prompts must contain\n"
        "exact file paths, line numbers, commands, and expected outputs.\n"
        "Parallelize independent subagent runs in one message.\n"
        "MANDATORY: every subagent prompt STARTS with the active scope and the\n"
        "`DIRECTIVES <version>` line from the block above. If the scope changes\n"
        "mid-attempt, RELAUNCH them — never let one finish on the abandoned scope.\n\n"
        "## BUILD & DELIVERY EFFICIENCY (owner standing order 2026-08-06)\n"
        "The owner: 'c'est pas possible sur une journee d'avoir quasi la moitie du\n"
        "temps gaspillee en builds'. ALWAYS pick the CHEAPEST path that proves the\n"
        "change:\n"
        "- DATA-only change (params/config read at runtime) => NO build. Push the\n"
        "  file to the device / edit in place, relaunch.\n"
        "- GOAL-only change => make-group iso + gradle repack. NO NDK/libgk rebuild.\n"
        "- C++ change => rebuild, but INCREMENTAL, and through the DOOR of the tree:\n"
        "    desktop  `.autoport/lib/build_x86.sh --target gk`\n"
        "    arm64    `cmake --build build-android --target gk -j`\n"
        "  The desktop door runs the SAME ninja, but it repairs `build/.ninja_deps`\n"
        "  first and EXITS 4 on a binary older than its inputs. A bare cmake build of\n"
        "  the desktop tree is REFUSED by hooks/pre-tool.sh since 2026-09-12: it\n"
        "  returned 0 on three passes that left `build/game/gk` UNLINKED, and\n"
        "  recompiled 335 targets every time (444 s -> 0,4 s once repaired).\n"
        "  NEVER re-run `cmake -B <dir>` unless a build OPTION changed: it\n"
        "  invalidates the whole tree (1300+ objects, incl. unrelated jak2 mips2c).\n"
        "- Batch changes: land ALL edits of a cycle before building, never per edit.\n\n"
        "## PROOF ECONOMY (owner standing order 2026-08-06)\n"
        "Prove ONLY what would break SILENTLY, with the CHEAPEST instrument that\n"
        "already exists:\n"
        "- MUST prove: no crash, no regression of a locked-in acquis, the feature is\n"
        "  actually ACTIVE (a counter/log showing the code path ran), deploy freshness.\n"
        "- MUST NOT build: elaborate new proof harnesses, multi-leg device campaigns,\n"
        "  or any visual-measurement campaign (permanently banned).\n"
        "- QUALITY/aesthetics are judged by the OWNER, never by you: ship the build\n"
        "  and let him look. Your report lists what HE must test.\n"
        "Budget guide: proof runs are MINUTES, not hours.\n\n"
        "## EPINGLER LE REGIME DE TA COURSE (harness-proof-props-pin, 2026-09-12)\n"
        "Un reglage de course se pose dans L'ITEM DU BACKLOG, jamais a la main avant\n"
        "la course :\n"
        "  proof_props:  - debug.opengoal.hdr.out=2   # course appareil (setprop)\n"
        "  proof_env:    - OG_RECHARGED=1             # course x86 (environnement)\n"
        "`lib/proof_run.sh` lance `lib/device_teardown.sh` AVANT l'amorcage, et il efface\n"
        "TOUTES les `debug.opengoal.*` posees sur l'appareil. Un `adb shell setprop` tape\n"
        "depuis l'hote meurt donc entre ta pose et la course : tu mesures l'AUTRE regime\n"
        "sans rien voir. Seul `proof_props` survit — il voyage dans une variable du script\n"
        "et se repose APRES le teardown.\n"
        "Ta preuve te le dit maintenant, relis-la avant d'accuser le code :\n"
        "  teardown_props_found / teardown_props_list  ce qui etait pose a l'arrivee, nomme\n"
        "  proof_props_file / _extracted / _effective  fichier -> extrait -> ce que rend l'appareil\n"
        "  proof_prop_obs_<cle>                        la valeur RELUE apres l'amorcage\n"
        "Un item `owner_test: false` n'est jamais parque pour l'owner : sa preuve est\n"
        "machine, il se ferme tout seul.\n\n"
        "## HANDOFF (obligatoire si tu n'aboutis pas)\n"
        f"Avant de t'arrêter sans avoir fait passer la porte, écris "
        f"`.autoport/reports/<id>/handoff.md`, {HANDOFF_MAX_LINES} lignes MAXIMUM,\n"
        "en trois sections : ce qui est ÉTABLI (mesuré, pas supposé), ce qui a été\n"
        "TENTÉ et pourquoi ça a échoué, ce qui RESTE à faire. C'est le seul contexte\n"
        "que l'essai suivant recevra.\n\n"
    )
    if BACKEND == "codex":
        start = text.index("## BUILD & DELIVERY")
        text = (
            "## DÉLÉGATION CODEX\n"
            "Tu es le manager. Délègue les sous-tâches indépendantes aux outils natifs "
            "Codex spawn_agent / wait_agent / send_message, puis vérifie leurs résultats. "
            "Ne lance jamais claude, ni une autre CLI pour les sous-tâches.\n"
            f"Modèle des sous-agents : {SUBAGENT_MODEL or 'hérité de la CLI'}. "
            f"Trois rôles : researcher = lecture seule ({we.get('autoport-researcher', 'high')}), "
            f"implementer = spec exacte ({we.get('autoport-implementer', 'medium')}), "
            f"tester = builds et mesures ({we.get('autoport-tester', 'medium')}). "
            "Lis .autoport/codex/roles.md. Passe explicitement le rôle et son effort au spawn. "
            "Chaque prompt commence par le périmètre et DIRECTIVES <version>. "
            "Ne délègue pas la compréhension ; donne fichiers, questions et critères précis. "
            "Attends tous les agents avant de terminer. Relance-les si le périmètre change.\n\n"
        ) + text[start:]
    return text



def build_instructions(item: dict, seq: int) -> str:
    """ultrathink + directives + preflight + work economy + the item + handoff."""
    iid = item["id"]
    effort = item.get("effort", EFFORT)

    # DIRECTIVE TRANSMISSION (owner 2026-08-11: "t'arrives pas a faire descendre a
    # tes agents les changements et ca gaspille des heures"). The contract is
    # INLINED, not referenced by path: a path the worker may or may not open is
    # not a channel.
    dblock = ""
    try:
        lib = str(AUTOPORT_DIR / "lib")
        if lib not in sys.path:
            sys.path.insert(0, lib)
        import directives as _dv
        safe_reload.reload(_dv, "orchestrator:directives", log)   # RECHARGEMENT/filet
        dblock = _dv.block(iid)
        log(f"· directives {_dv.version(iid)} inlinées dans le prompt "
            f"({len(dblock)} caractères)", "dim")
    except Exception as e:  # noqa: BLE001 — never let transmission break the run
        log(f"· bloc directives indisponible : {e}", "yellow")

    # PREFLIGHT (owner 2026-08-11: "le but etant d'avoir un cercle vertueux, pas un
    # frein"). At most 5 findings reach the prompt; the rest are printed here.
    pblock = ""
    try:
        import preflight as _pf
        safe_reload.reload(_pf, "orchestrator:preflight", log)    # RECHARGEMENT/filet
        pblock = _pf.prompt_block(iid)
        injected, overflow, sup = _pf.prompt_findings(iid)
        if injected:
            log(f"· preflight : {len(injected)} constat(s) injecté(s) dans le prompt", "dim")
        if overflow:
            log(f"· preflight : {len(overflow)} constat(s) AU-DELÀ du plafond de "
                f"{_pf.MAX_PROMPT_FINDINGS} — non injectés, les voici :", "yellow")
            for sev, code, msg in overflow:
                log(f"    [{sev} {code}] {msg}", "yellow")
        for sev, code, msg in sup:
            log(f"· preflight/SUPERVISEUR [{code}] {msg}", "yellow")
    except Exception as e:  # noqa: BLE001
        log(f"· preflight indisponible : {e}", "yellow")

    prompt_path = AUTOPORT_DIR / item["prompt"]
    text = ("ultrathink\n\n" + dblock + pblock + _delegation_preamble(effort)
            + _item_header(item, seq) + prompt_path.read_text())

    handoff = read_handoff(iid)
    if handoff:
        text += (f"\n\n## CE QUE L'ESSAI PRÉCÉDENT A LAISSÉ (`reports/{iid}/handoff.md`)\n\n"
                 f"{handoff}\n\n"
                 "Reprends À PARTIR DE LÀ. Ne refais pas ce qui y est déjà établi.\n")
    return text


@dataclass
class Outcome:
    """What one attempt produced.

    kind:
      pass            gates clear, the owner does not need to look
      awaiting-owner  gates clear, the owner has to look  -> to-test
      fail            counted, fingerprinted, retried
      foreign         l'arbre portait le chantier d'un AUTRE item: NOT counted
      stuck           same failure 3x -> blocked
      blocked         max_retries, missing input, fatal config
      aborted         the launcher killed the worker's background tasks: NOT counted
      interrupted     signal / scope change / duplicate worker: NOT counted
      no-start        refused at the door, zero work: NOT counted
      infra           529 storm: NOT counted
    """
    kind: str
    reason: str = ""
    key_lines: list[str] = field(default_factory=list)
    resume_at: int | None = None
    stderr_tail: list[str] = field(default_factory=list)
    # VERDICT/dans-l-item : ce que la porte doit pouvoir ECRIRE dans l'item quand elle prononce.
    # Le numero d'essai et le nom du journal sont calcules dans `run_attempt` et mouraient avec
    # elle ; la boucle en avait besoin et ne pouvait pas les reconstruire.
    seq: int = 0
    journal: str = "-"


def run_attempt(item: dict, state: dict) -> Outcome:
    global _CURRENT_CHILD
    iid = item["id"]
    log_dir = LOG_ROOT / iid
    log_dir.mkdir(parents=True, exist_ok=True)
    seq = next_attempt_seq(state, iid)
    # CE QUE L'ESSAI TROUVE SALE EN ARRIVANT. Il ne l'a pas produit : c'est la ligne de
    # base de GATE 0. Dit tout de suite, au POINT DE PRODUCTION — un arbre hérité sale
    # invalide tout ce que l'essai mesurera ensuite.
    pre_dirty_engine = engine_dirty_paths()
    if pre_dirty_engine:
        log(f"⚠ l'arbre porte DÉJÀ {len(pre_dirty_engine)} fichier(s) moteur sales, non "
            f"commités, hérités d'un autre essai : {', '.join(pre_dirty_engine[:8])}"
            + (" …" if len(pre_dirty_engine) > 8 else ""), "yellow")
    attempt_log = log_dir / f"attempt-{seq:03d}.jsonl"
    validator_log = log_dir / f"validator-{seq:03d}.txt"
    started_at = time.time()

    # PURGE/changement-d-item — L'ÉTAT « PREUVE IMPOSSIBLE » QUI NE DÉCRIT PLUS LE PRÉSENT PART
    # ICI, au moment où la file change d'item. Rien ne le purgeait (signalement du 12/09) :
    # `proof_run.sh` n'efface que le sien, à sa propre relance, sur le MÊME item et le MÊME
    # bras. Un item abandonné en cours de route gardait donc son état pour toujours, et
    # `autoport status` annonçait à l'owner une impossibilité périmée dont l'âge grandissait
    # tout seul. Les états de CET essai, eux, ne sont pas encore écrits : on ne purge que le
    # passé — et l'autre bras de cet item n'est jamais touché.
    try:
        _hyg = impossible_state.purge(str(AUTOPORT_DIR / "reports"),
                                      current_item=iid, since=started_at,
                                      who="orchestrateur")
        for _rec in _hyg["purged"]:
            log(f"· état « preuve impossible » purgé : {_rec['item']}/{_rec['file']} "
                f"({_rec['reason']}, {impossible_state.human(_rec['age_s'])}, "
                f"cause {_rec['cause']})", "dim")
        if _hyg["purged"] or _hyg["standing"]:
            log(f"· hygiène des états impossibles : {len(_hyg['purged'])} purgé(s), "
                f"{len(_hyg['standing'])} encore debout", "dim")
    except Exception as _e:                      # noqa: BLE001
        log(f"· purge des états « preuve impossible » impossible : {_e}", "yellow")

    prompt_path = AUTOPORT_DIR / item.get("prompt", "")
    if not item.get("prompt") or not prompt_path.exists():
        return Outcome("blocked", f"prompt absent : {prompt_path}")

    # 2026-09-11 — CONSIGNE PERIMEE. La fabrication d'un prompt sait raccourcir les citations de
    # l'owner, jamais le livrable — et le livrable gagne un verdict a chaque refus. Au-dela de
    # PROMPT_MAX elle ECHOUE et laisse l'ANCIEN fichier en place : le worker lit alors une version
    # depassee de son cahier des charges, et rien ne le dit. Mesure du 11/09 : quatre chantiers
    # ouverts etaient dans ce cas. On refuse de demarrer plutot que de gacher un essai.
    _bl = None
    try:
        from lib import backlog as _bl          # noqa: PLC0415 — local, comme cli_backend
    except Exception as e:                      # noqa: BLE001
        log(f"· controle de fraicheur de la consigne indisponible : {e}", "yellow")
    if _bl is not None:
        try:
            _etat = _bl.prompt_state(item)
        except Exception as e:                  # noqa: BLE001
            log(f"· fraicheur de la consigne non verifiable : {e}", "yellow")
            _etat = "a-jour"
        if _etat == "perime":
            return Outcome("blocked",
                           f"consigne PERIMEE : {prompt_path.name} est notre fabrication, mais "
                           "l'item a bouge depuis. Refabrique-la avant de relancer — sinon le "
                           "worker travaille sur un cahier des charges depasse.")
        if _etat == "a-la-main":
            # L'owner l'avait vu venir : une consigne ecrite a la main est legitime. On alerte,
            # on ne bloque pas, et surtout on ne l'ecrase pas.
            log(f"· consigne {prompt_path.name} ne vient pas de nos fabrications — ecrite a la "
                "main ? on la respecte telle quelle", "yellow")
    if not GENERIC_VALIDATOR.exists():
        return Outcome("blocked", f"validateur absent : {GENERIC_VALIDATOR}")

    effort = item.get("effort", EFFORT)
    instructions = build_instructions(item, seq)

    console.print(Panel.fit(
        f"[bold cyan]{iid}[/bold cyan] · essai {seq} · "
        f"{item.get('feature', '')[:70]}\n"
        f"CLI={BACKEND} · modèle={MODEL or 'défaut CLI'} · effort={effort} · sous-agents={SUBAGENT_MODEL or 'hérités'}",
        border_style="cyan"))

    env = os.environ.copy()
    env["AUTOPORT_BACKEND"] = BACKEND
    env["CLAUDE_PROJECT_DIR"] = str(REPO_ROOT)
    if BACKEND == "claude":
        env["CLAUDE_EFFORT"] = effort
        env["CLAUDE_CODE_SUBAGENT_MODEL"] = SUBAGENT_MODEL
        # La borne d'attente des taches de fond voyage avec l'essai : un orchestrateur
        # demarre sans launch.sh retombait en silence sur les 600 s de la CLI.
        env["CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS"] = str(BG_WAIT_CEILING_MS)
    else:
        for key in ("CLAUDE_EFFORT", "CLAUDE_CODE_SUBAGENT_MODEL", "CLAUDECODE"):
            env.pop(key, None)
    env["AUTOPORT_PHASE_ID"] = iid                       # = l'id d'item
    env["AUTOPORT_PHASE_VALIDATOR"] = str(GENERIC_VALIDATOR)
    # L'IDENTITE DE CET ESSAI, POSEE UNE FOIS ET LUE DES DEUX COTES
    # (harness-proof-file-has-no-writer-lock, 2026-09-12). `lib/proof_run.sh` la recopie dans
    # `proof_attempt_id=` ; `validators/generic.sh` la relit dans SON environnement et refuse
    # une preuve qui porte celle d'un autre essai. Sans elle, un `proof_run.sh` orphelin d'un
    # essai TUE pouvait ecrire sa preuve par-dessus celle de l'essai suivant, et le juge lisait
    # la course d'AVANT en croyant juger celle d'apres. Aucun espace : `proof.txt` jette toute
    # valeur qui en porte un.
    attempt_token = f"{iid}@{seq}#{int(started_at)}"
    env["AUTOPORT_ATTEMPT_ID"] = attempt_token

    # 2026-08-17 : le prompt passe par STDIN, plus jamais en argv. Un argument
    # unique est plafonne a MAX_ARG_STRLEN (~128 Ko) sur Linux ; le contrat a
    # depasse cette taille et l'exec mourait en OSError E2BIG AVANT tout travail.
    profile = dict(_PROFILE, manager_model=MODEL, worker_model=SUBAGENT_MODEL)
    cmd = cli_backend.worker_command(REPO_ROOT, BACKEND, profile, effort,
                                     item.get("max_turns", 300))

    pstate = PrettyState(t0=time.monotonic())
    stderr_tail: list[str] = []
    abort_reason = ""       # "" | scope | no-progress | post-result | hard-silence
    launcher_abort_sec: int | None = None   # la CLI a tue les taches de fond du worker
    rc = -1

    with attempt_log.open("x") as f:
        f.write(json.dumps({
            "event": "attempt_start", "item_id": iid, "attempt": seq, "backend": BACKEND,
            "model": MODEL, "effort": effort, "subagent_model": SUBAGENT_MODEL,
            "cmd": cmd, "started_at": datetime.now(timezone.utc).isoformat(),
        }) + "\n")
        f.flush()

        try:
            proc = subprocess.Popen(cmd, cwd=REPO_ROOT, env=env,
                                    stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, bufsize=1, text=True,
                                    start_new_session=True)
        except OSError as e:
            f.write(json.dumps({"event": "attempt_end", "launch_error": str(e)}) + "\n")
            return Outcome("no-start", f"CLI {BACKEND} impossible à lancer : {e}", stderr_tail=[str(e)])
        _CURRENT_CHILD = proc
        try:
            proc.stdin.write(instructions)
            proc.stdin.close()          # EOF, sans quoi la CLI attend indefiniment
        except BrokenPipeError:
            # A CLI may reject config before consuming stdin. Still drain its diagnostic.
            try:
                proc.stdin.close()
            except BrokenPipeError:
                pass

        last_event_at = time.monotonic()
        last_progress_at = time.monotonic()
        last_progress_fp = _progress_fingerprint(iid)
        scope_seen = _scope_changed(None)
        # LE CARNET DE LA COURSE LAISSEE EN VOL. Passe par reference a `post_result_verdict`,
        # il finit dans `attempt_end` : l'attente et le PID sont publies, pas racontes.
        inflight = {"ceiling_s": inflight_ceiling_s(item), "pid": 0, "how": "",
                    "waited_s": 0.0, "holds": 0, "expired": 0, "ended": 0}

        def _kill(reason: str) -> None:
            nonlocal abort_reason
            abort_reason = reason
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass

        try:
            stdout_fd = proc.stdout
            while True:
                try:
                    ready, _, _ = select.select([stdout_fd], [], [], READ_POLL_SEC)
                except (OSError, ValueError):
                    break                          # stdout closed underneath us

                # Continuous JSON traffic must not hide a scope cancellation.
                if _scope_changed(scope_seen) != scope_seen:
                    _kill("scope")
                    break
                if BACKEND == "codex" and pstate.tool_calls >= min(item.get("max_turns", 300), 300):
                    _kill("tool-budget")
                    break
                if not ready:
                    idle = time.monotonic() - last_event_at
                    if proc.poll() is not None:
                        break
                    # claude said `result` but won't exit (TaskCreate re-engagements
                    # keep the process open in -p mode). Force the issue — SAUF si le worker a
                    # laisse une course de preuve EN VOL : la tuer detruit la preuve de son
                    # propre essai (trois essais perdus le 16/09).
                    # POST-RESULT/debut
                    # DEUX MARQUEURS, ET C'EST VOULU. Le banc `lib/inflight_selftest.py` leve
                    # CE bloc-ci tel quel pour en faire son bras d'APRES, et le MEME bloc prive
                    # de `EN-VOL/` pour son bras d'AVANT : le bras d'avant n'est pas la couche
                    # desarmee, c'est la couche ABSENTE, aux octets pres de ce qui tournait le
                    # 16/09. Une recopie a la main dans le banc mesurerait la recopie.
                    if pstate.result_seen and idle >= STALL_POST_RESULT_SEC:
                        # EN-VOL/debut
                        if post_result_verdict(iid, inflight, idle):
                            _maybe_emit_tick(pstate)
                            continue
                        # EN-VOL/fin
                        log(f"· {BACKEND} a émis son résultat sans sortir ({idle:.0f}s) — "
                            f"fermeture forcée", "yellow")
                        _kill("post-result")
                        break
                    # POST-RESULT/fin
                    sc = _scope_changed(scope_seen)
                    if sc != scope_seen:
                        log("· PÉRIMÈTRE CHANGÉ — essai annulé immédiatement "
                            "(ni compté, ni empreinté)", "red")
                        _kill("scope")
                        break
                    if time.monotonic() - last_progress_at >= NO_PROGRESS_SEC:
                        fp_now = _progress_fingerprint(iid)
                        if fp_now != last_progress_fp:
                            last_progress_fp = fp_now
                            last_progress_at = time.monotonic()
                        else:
                            mins = (time.monotonic() - last_progress_at) / 60.0
                            log(f"· aucun ARTEFACT modifié depuis {mins:.0f} min "
                                f"(arbre, rapport, notes, handoff) — essai abandonné", "red")
                            _kill("no-progress")
                            break
                    if idle >= STALL_HARD_SEC:
                        log(f"· aucune sortie de {BACKEND} depuis {idle:.0f}s — on tue", "red")
                        _kill("hard-silence")
                        break
                    _maybe_emit_tick(pstate)
                    continue

                raw_line = stdout_fd.readline()
                if not raw_line:
                    break                          # EOF
                last_event_at = time.monotonic()

                f.write(raw_line)                  # forensic log gets every byte
                f.flush()

                line = raw_line.rstrip("\n")
                if not line.strip():
                    continue

                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    # NOT json = claude's own stderr. It is the only account of why
                    # a session refused to start, and `--quiet` used to throw it
                    # away: 230 consecutive no-starts over 19.7 h whose cause could
                    # never be recovered. It is printed whatever the verbosity.
                    if launcher_abort_sec is None:
                        launcher_abort_sec = launcher_abort_seconds(line)
                    stderr_tail.append(line)
                    del stderr_tail[:-40]
                    console.print(f"[magenta]{BACKEND}:[/magenta] [dim]{_truncate(line, 300)}[/dim]")
                    continue

                if not isinstance(ev, dict):
                    continue
                error = cli_backend.codex_error(ev) if BACKEND == "codex" else ""
                if error:
                    stderr_tail.append(error)
                    del stderr_tail[:-40]
                pretty_print_event(ev, pstate)
        except KeyboardInterrupt:
            _kill("signal")
            raise
        finally:
            try:
                rc = proc.wait(timeout=EXIT_WAIT_SEC)
            except subprocess.TimeoutExpired:
                if not abort_reason:
                    abort_reason = "exit-stall"
                    log("· flux CLI fermé mais processus encore vivant — arrêt borné", "red")
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                rc = proc.wait()
            _CURRENT_CHILD = None

        f.write(json.dumps({
            "event": "attempt_end", "exit_code": rc,
            "ended_at": datetime.now(timezone.utc).isoformat(),
            "abort_reason": abort_reason, "halted": HALT,
            "launcher_abort_s": launcher_abort_sec,
            # L'ATTENTE ET LE PID, PUBLIES (2026-09-16). `waited_s` a zero avec `pid` a zero
            # veut dire qu'aucune course n'etait en vol — pas que l'on n'a pas regarde.
            "inflight": {k: inflight.get(k) for k in
                         ("pid", "how", "waited_s", "holds", "ceiling_s", "expired",
                          "ended", "idle_at_hold_s")},
            "tool_calls": pstate.tool_calls,
            "tokens_in": pstate.tokens_in, "tokens_out": pstate.tokens_out,
            "cache_read": pstate.cache_read,
        }) + "\n")
        if launcher_abort_sec is not None:
            # Dit en toutes lettres DANS le journal de l'essai : un essai qui disparait
            # sans un mot est ce qui a coute quatre essais sans que personne le voie.
            f.write(json.dumps({
                "event": "attempt_aborted", "cause": "launcher-bg-tasks",
                "waited_s": launcher_abort_sec,
                "ceiling_ms": BG_WAIT_CEILING_MS,
                "ceiling_source": BG_CEILING_SOURCE,
                "message": (f"le lanceur a termine les taches de fond du worker apres "
                            f"{launcher_abort_sec}s (borne en vigueur "
                            f"{BG_WAIT_CEILING_MS}ms) : essai ABORTE"),
            }) + "\n")

    if BACKEND == "codex" and (pstate.cli_failed or not pstate.result_seen) and rc == 0:
        rc = 1

    touched = worker_paths()          # ce que l'essai a laissé dans l'arbre
    did_work = (pstate.tokens_in + pstate.tokens_out) > 0 or pstate.tool_calls > 0

    def _checkpoint(label: str) -> bool:
        """Save the work. ALWAYS — an attempt we cancel is still work done.

        The path list is recomputed here rather than reused: the validator and
        the close-gate run between the worker's exit and this commit."""
        ok, paths = False, []
        try:
            paths = worker_paths()
            ok = git_commit_paths(iid, label, paths)
        except Exception as e:  # noqa: BLE001 — never let checkpointing crash the loop
            log(f"checkpoint impossible : {e}", "yellow")
        # La comptabilité de l'indexation SURVIT à l'essai : sans elle, « le commit a échoué »
        # resterait une ligne de console que personne ne relit. Écrite À PART : un state.json
        # qu'un autre orchestrateur a bougé ne doit PAS transformer un commit réussi en échec.
        try:
            book = state.setdefault("commit_paths", {})
            for k, v in COMMIT_PATHS_STATS.items():
                if isinstance(v, int):
                    book[k] = int(v)
            book["last_refused"] = list(COMMIT_PATHS_STATS.get("last_refused") or [])
            save_state(state)
        except Exception as e:  # noqa: BLE001
            log(f"comptabilité d'indexation non enregistrée : {e}", "yellow")
        if ok:
            log(f"  checkpoint commité ({len(paths)} chemin(s))", "green")
        return ok

    # ---- VOID OUTCOMES: work saved, nothing counted ----------------------
    # A signal, a scope change or a refusal at the door is OUR interruption, not
    # the worker's failure. Counting them is what made 373 of 597 sessions last
    # under three minutes and blocked items on retries nobody ever used.
    if HALT or abort_reason == "signal":
        _checkpoint(f"essai {seq} interrompu par un signal (non compté)")
        return Outcome("interrupted", "signal reçu")
    if abort_reason == "scope":
        _checkpoint(f"essai {seq} annulé — changement de périmètre (non compté)")
        return Outcome("interrupted", "périmètre changé pendant l'essai")

    # ---- L'ESSAI QUE LE LANCEUR A TUE ------------------------------------
    # Ni un echec du worker, ni un arbre a juger : la CLI a coupe les taches de fond
    # qu'il attendait. On le DIT — duree atteinte et borne en vigueur —, on sauve le
    # travail, et on rend la main SANS toucher `retries`, `fingerprints`, ni le
    # validateur. Le garde-fou est le nombre d'abandons D'AFFILEE : au-dela, l'essai
    # est compte, faute de quoi un worker qui laisse toujours des taches de fond ferait
    # tourner son item sans fin.
    if launcher_abort_sec is not None:
        rec = _aborted_record(state, iid)
        rec["total"] += 1
        rec["streak"] += 1
        save_state(state)
        dit = (f"essai {seq} TUÉ PAR LE LANCEUR : {BACKEND} a attendu "
               f"{launcher_abort_sec} s les tâches de fond du worker, puis les a "
               f"TERMINÉES. Borne en vigueur : "
               f"CLAUDE_CODE_PRINT_BG_WAIT_CEILING_MS={BG_WAIT_CEILING_MS} ms "
               f"({BG_WAIT_CEILING_MS // 1000} s), posée par {BG_CEILING_SOURCE}.")
        if rec["streak"] <= MAX_ABORTED_IN_A_ROW:
            log(f"⏹ {dit} Essai NON COMPTÉ, ni empreinté, VALIDATEUR NON LANCÉ "
                f"(abandons d'affilée : {rec['streak']}/{MAX_ABORTED_IN_A_ROW}, "
                f"{rec['total']} en tout sur cet item). Le travail est commité.", "yellow")
            _checkpoint(f"essai {seq} tué par le lanceur après {launcher_abort_sec}s "
                        f"d'attente des tâches de fond (non compté)")
            return Outcome("aborted",
                           f"tâches de fond terminées par le lanceur après "
                           f"{launcher_abort_sec} s (borne {BG_WAIT_CEILING_MS} ms)")
        log(f"⏹ {dit} C'est le {rec['streak']}e abandon D'AFFILÉE sur cet item : au-delà "
            f"de {MAX_ABORTED_IN_A_ROW}, l'essai EST compté — sinon l'item tourne sans "
            f"fin sans jamais être jugé.", "red")

    fatal = fatal_config_reason(attempt_log) if (rc != 0 and (not did_work or BACKEND == "codex")) else ""
    if fatal:
        if did_work:
            _checkpoint(f"essai {seq} — configuration CLI refusée (non compté)")
        return Outcome("blocked", fatal, stderr_tail=stderr_tail)

    if rc != 0 and not abort_reason and (not did_work or pstate.rate_rejected):
        # Refused by the API: either at the door (zero tokens, zero tool calls)
        # or mid-work with an explicit `rejected`. Either way it is a quota
        # event, not a failure of the worker, and the API told us WHEN the
        # window reopens — we sleep until then instead of guessing five minutes.
        reset = pstate.rate_reset_at or rate_reset_from_log(attempt_log)
        why = ("l'API nous a refusés en cours de session"
               if did_work else f"{BACKEND} est sorti en {rc} sans rien faire")
        _checkpoint(f"essai {seq} — session refusée par l'API (non compté)")
        return Outcome("no-start", why, resume_at=reset, stderr_tail=stderr_tail)

    if (BACKEND == "codex" and rc != 0 and not abort_reason
            and cli_backend.error_kind(pstate.cli_error) == "infra"):
        _checkpoint(f"essai {seq} — API Codex indisponible (non compté)")
        return Outcome("infra", pstate.cli_error,
                       resume_at=int(time.time()) + API_529_SLEEP, stderr_tail=stderr_tail)

    if rc != 0 and not abort_reason:
        # An Anthropic outage, counted from structured API errors only, and only
        # when WE did not kill the child (our own SIGTERM is exit 143).
        n529 = count_api_529(attempt_log)
        if n529 >= API_529_STORM_THRESHOLD:
            _checkpoint(f"essai {seq} — tempête 529 de l'API (non compté)")
            return Outcome("infra", f"tempête 529 ({n529} erreurs d'API)",
                           resume_at=int(time.time()) + API_529_SLEEP)

    # ---- COUNTED OUTCOMES ------------------------------------------------
    # LE JUGE NE PASSE PAS AVANT LA FIN DE LA CHAINE
    # (harness-proof-file-has-no-writer-lock, 2026-09-12). Le 12/09 a 18:12,
    # `build-android-reinvalidates-itself` a ete BLOQUE sur trois refus identiques « proof.txt
    # absent ou vide » : son travail etait commite a 18:04 et 18:06, sa preuve — 34 340 octets,
    # porte tenue — a ete ecrite a 18:21, et le juge etait passe trois fois avant. La garde
    # anti-boucle a lu trois empreintes d'echec identiques et a bloque l'item, ce qui a demande
    # un arbitrage humain pour un travail qui etait fait. Le verrou d'ecriture dit qu'une course
    # ECRIT : on l'attend, borne, et on le DIT. On ne relance rien, on ne tue rien.
    waited_writer, writer_pid = wait_for_proof_writer(iid)
    if writer_pid:
        log(f"· une course ECRIVAIT la preuve de {iid} (pid={writer_pid}) — juge retenu "
            f"{waited_writer} s, le temps qu'elle finisse", "yellow")
        state.setdefault("proof_writer", {})[iid] = {
            "waited_s": waited_writer, "pid": writer_pid,
            "at": datetime.now(timezone.utc).isoformat()}
        save_state(state)
    log(f"{BACKEND} est sorti en {rc}. Validateur…", "dim")
    with validator_log.open("w") as f:
        v = subprocess.run(["bash", str(GENERIC_VALIDATOR)], cwd=REPO_ROOT,
                           env={**os.environ, "AUTOPORT_PHASE_ID": iid,
                                "AUTOPORT_ATTEMPT_ID": attempt_token},
                           stdout=f, stderr=subprocess.STDOUT)

    state["retries"][iid] = int(state["retries"].get(iid, 0)) + 1
    attempt_count = state["retries"][iid]
    _aborted_record(state, iid)["streak"] = 0   # un essai JUGE remet la serie a zero
    save_state(state)

    gate_reason = ""
    # LA PORTE DE FERMETURE EST APPELÉE DANS LES DEUX CAS. GATE -1 — « preuve impossible » —
    # doit voir l'essai que le validateur vient de refuser : c'est là, et nulle part ailleurs,
    # qu'une machine indisponible se lisait « proof.txt absent ou vide ».
    gate_status, gate_reason = close_gate(item, pre_dirty_engine,
                                          validator_ok=(v.returncode == 0),
                                          since=started_at)

    if gate_status == "impossible":
        _imp = impossible_state.read(str(AUTOPORT_DIR / "reports"), iid, since=started_at)
        verdict, dit = requalify_impossible_attempt(state, iid, _imp or {})
        save_state(state)
        _contredit = ecrire_journal_impossible(validator_log, _imp or {}, gate_reason, dit)
        if _contredit:
            log("· journal de validation réécrit : sa première ligne accusait une absence de "
                "preuve que la porte requalifie en preuve IMPOSSIBLE", "dim")
        if verdict == "requalifie":
            log(dit, "yellow")
            _checkpoint(f"essai {seq} classé à part — PREUVE IMPOSSIBLE (non compté)")
            return Outcome("impossible", gate_reason + "\n\n" + dit)
        log(dit, "red")
        _checkpoint(f"essai {seq} classé à part — PREUVE IMPOSSIBLE (non compté ; "
                    f"item BLOQUÉ, la cause doit être levée)")
        return Outcome("blocked", gate_reason + "\n\n" + dit)

    if v.returncode == 0:
        # UNE CAUSE EXTÉRIEURE NE BRÛLE PLUS UN ESSAI. La saleté est celle d'un AUTRE item,
        # que le périmètre de celui-ci lui interdit de commiter ou de défaire. On DÉFAIT le
        # compte, on NOMME les chemins, et l'essai est classé à part — jamais empreinté
        # comme un mode d'échec du worker.
        if gate_status == "foreign":
            etrangers = foreign_dirty_engine_paths(pre_dirty_engine)
            verdict, dit = requalify_foreign_attempt(state, iid, etrangers)
            save_state(state)
            with validator_log.open("a") as f:
                f.write("\n\n" + gate_reason + "\n\n" + dit + "\n")
            if verdict == "requalifie":
                log(dit, "yellow")
                _checkpoint(f"essai {seq} classé à part — arbre sale hérité (non compté)")
                return Outcome("foreign", gate_reason)
            log(dit, "red")
            _checkpoint(f"essai {seq} classé à part — arbre sale hérité (non compté ; "
                        f"item BLOQUÉ, le superviseur doit trancher)")
            return Outcome("blocked", gate_reason + "\n\n" + dit)
        if gate_status in ("pass", "awaiting-owner"):
            _foreign_reset(state, iid)
            _impossible_reset(state, iid)
            if _checkpoint(item.get("feature", iid)
                           + ("" if gate_status == "pass"
                              else " (porte passée — EN ATTENTE DU TEST DE L'OWNER)")):
                git_push()
            return Outcome(gate_status, seq=seq, journal=validator_log.name)
        with validator_log.open("a") as f:
            f.write("\n\n" + gate_reason + "\n")
        log(gate_reason, "yellow")

    # L'essai est COMPTÉ : les séries de requalifications s'arrêtent ici.
    _foreign_reset(state, iid)
    _impossible_reset(state, iid)

    failure_text = validator_log.read_text(errors="replace")
    fp, key_lines = fingerprint_failure(failure_text, REPO_ROOT)
    state.setdefault("fingerprints", {}).setdefault(iid, []).append(fp)
    save_state(state)

    # The handoff is written BEFORE the checkpoint so the next attempt's context
    # is versioned with the work it describes.
    hp = handoff_path(iid)
    if not hp.exists() or hp.stat().st_mtime < started_at:
        write_minimal_handoff(iid, seq, validator_log, touched, gate_reason)
        log("  handoff minimal écrit par l'orchestrateur (le worker n'en a pas laissé)",
            "yellow")

    # AUTO-CHECKPOINT (owner 2026-06-13): version EVERY failed attempt's work so
    # a long iterating item never leaves hours of engine changes un-bisectable.
    _checkpoint(f"WIP essai {seq} (validateur ÉCHOUÉ — versionné pour bisect, "
                f"PAS une réussite)")

    stuck, stuck_reason = check_stuck(state, iid, fp)
    if stuck:
        return Outcome("stuck", stuck_reason, key_lines)
    if attempt_count >= int(item.get("max_retries", 6)):
        return Outcome("blocked",
                       f"max_retries ({item.get('max_retries', 6)}) épuisé", key_lines)
    return Outcome("fail", "", key_lines)


# ============================================================
# Main loop
# ============================================================

def acquire_single_instance_lock() -> Any:
    """UN SEUL ORCHESTRATEUR PAR DEPOT. Rend le verrou (a garder vivant), ou quitte.

    Mesure du 2026-08-12 07:20 : DEUX orchestrateurs tournaient sur ce depot, et
    chacun a lance son worker sur la MEME phase, a seize secondes d'ecart. Les deux
    workers ont partage le meme arbre, la meme trace, le meme tableau et la meme
    branche ; un worker regenerait les parametres pendant que l'autre mesurait une
    course lancee sur les parametres d'avant — la mesure decrit alors un etat que
    personne n'a choisi. Et un rapport n'a qu'un seul auteur : le dernier qui ecrit.

    L'owner, 2026-08-11 : « t'assurer que ton travail n'est pas systematiquement
    detruit [...] tu peux pas juste dire "ah oups" et laisser reproduire en boucle ! »
    — la regle qu'il en tire est de rendre la perte impossible AU POINT DE
    PRODUCTION. Le point de production est ici : le lanceur de workers.

    `flock` et pas un fichier de PID : le noyau relache le verrou a la mort du
    processus, donc un orchestrateur tue laisse le depot libre sans nettoyage.
    Le fichier de verrou n'est plus suivi par git (un checkout remplacait son
    inode et annulait le verrou en silence)."""
    try:
        import fcntl
    except ImportError:                      # pragma: no cover
        log("· pas de fcntl : verrou d'instance unique indisponible", "yellow")
        return None
    lock_path = AUTOPORT_DIR / ".orchestrator.lock"
    fh = open(lock_path, "a+")
    try:
        fcntl.flock(fh.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except OSError:
        fh.seek(0)
        holder = fh.read().strip() or "inconnu"
        fh.close()
        console.print(
            f"[red]Un orchestrateur tourne deja sur ce depot (PID {holder}).[/red]\n"
            f"[red]Verrou : {lock_path}[/red]\n"
            "Deux orchestrateurs lancent deux workers sur le MEME item : ils partagent\n"
            "l'arbre, la trace, le tableau et le rapport, et le dernier qui ecrit efface\n"
            "l'autre. Arrete l'instance en cours (PID exact, jamais de kill par motif).")
        return "BUSY"
    fh.seek(0)
    fh.truncate()
    fh.write(f"{os.getpid()}\n")
    fh.flush()
    return fh                                # garde le descripteur ouvert = garde le verrou


def promote_owner_validated(bk) -> list[str]:
    """`to-test` + la parole de l'owner = `validated`.

    Neuf items avaient le feu vert de l'owner sur disque et ne se seraient JAMAIS
    fermes : le saut « item parqué » s'executait AVANT la lecture du jeton, donc
    l'item etait re-parqué a vue, indefiniment. La lecture de la parole de l'owner
    passe maintenant en premier, et sur TOUT le backlog, pas sur le seul item du
    curseur."""
    promoted = []
    for item in bk.items:
        if item.get("status") != "to-test":
            continue
        if not owner_said_yes(item):
            continue
        iid = item["id"]
        fields = {}
        if not item.get("owner_ok"):
            token = OWNER_OK_DIR / iid
            fields["owner_ok"] = {
                "date": datetime.fromtimestamp(token.stat().st_mtime).strftime("%Y-%m-%d"),
                "text": f"jeton .autoport/owner-ok/{iid} déposé par le superviseur",
            }
        bk.set_status(iid, "validated", **fields)
        promoted.append(iid)
        log(f"✓ {iid} : l'owner a dit oui — validé.", "bold green")
    return promoted


def free_machine_proved(bk) -> list[str]:
    """UN ITEM `owner_test: false` NE RESTE JAMAIS PARQUÉ POUR L'OWNER.

    La porte de fermeture ne les parque plus depuis le 2026-09-11 (GATE 4). Mais ceux
    parqués AVANT n'avaient plus aucun chemin de sortie : `promote_owner_validated`
    exige la parole de l'owner, et l'item dit lui-même qu'il n'a rien à lui montrer.
    `perf-ocean-idle` a dormi en `to-test` du 10/09 au 12/09 en gelant `perf-stock-60`,
    l'objectif de toute la campagne de cadence — et la seule fonction capable de l'en
    sortir, `backlog.machine_proved_to_validated`, n'avait aucun appelant.

    C'est ici son appelant. Elle écrit par `set_status` : verrou, relecture du disque,
    rename atomique."""
    try:
        freed = bk.machine_proved_to_validated()
    except Exception as e:                                          # noqa: BLE001
        log(f"· rattrapage des items parqués indisponible : {e}", "yellow")
        return []
    for iid in freed:
        log(f"✓ {iid} : preuve machine (owner_test: false) — validé sans l'owner, "
            f"il n'a rien à regarder.", "bold green")
    # CE QUI EST REFUSÉ SE DIT. Un `owner_test: false` que la porte n'a pas tenu ne peut sortir
    # de `to-test` par AUCUN chemin — ni l'owner (il n'a rien à regarder), ni la promotion
    # machine (le verdict est rouge ou absent). Il gèle tout ce qui en dépend : le taire, c'est
    # refabriquer `perf-ocean-idle`, en pire, parce que cette fois rien ne le nommerait.
    # L'ORIGINE DU VERDICT EST DITE (signalement 9 du 12/09). Ce quadruplet rendait trois
    # champs : qui lisait cette ligne ne pouvait pas savoir si le verdict venait du CHAMP de
    # l'item ou du JOURNAL de repli. Une origine tue se lit comme l'origine attendue — et c'est
    # exactement la confusion que `harness-gate-verdict-must-outlive-its-log` a coutee.
    for iid, verdict, journal, origine in getattr(bk, "machine_promotion_refused", []):
        log(f"⚠ {iid} : parqué `to-test` avec `owner_test: false`, mais la porte n'a PAS tenu "
            f"({verdict}, verdict lu depuis {origine}, journal {journal}) — NON promu. Aucun "
            f"chemin ne le sortira de là tant que sa preuve n'aura pas tenu : relance un essai "
            f"ou tranche.", "yellow")
    return freed


def pronounce_gate(bk, item_id: str, status: str, result: str,
                   seq: int = 0, journal: str = "-", **fields) -> dict:
    """VERDICT/dans-l-item — LA PORTE ECRIT CE QU'ELLE A RENDU DANS L'ITEM, PAS AILLEURS.

    Signalement du 12/09 : la porte posait `to-test` et `delivered`, et RIEN D'AUTRE. La seule
    preuve qu'elle avait tenu etait `logs/<id>/validator-NNN.txt`, que `.gitignore` exclut du
    depot. Sur un clone neuf, ou apres une purge de journaux, `machine_proved_to_validated`
    lisait `journal-absent` pour tous les items parques : fail-CLOSED, donc aucun faux vert, mais
    un item PROUVE gelait pour toujours et gelait ses dependants. `perf-ocean-idle` a vecu ca
    deux jours avec un journal ; sans journal, rien ne l'aurait jamais reveille.

    Le backlog est la seule verite du travail ET il est versionne : le verdict s'ecrit LA.
    `gate_verdict.gate_record` en fixe la forme — resultat, date, empreinte des OCTETS de la
    preuve jugee, essai, journal. La racine des rapports est derivee du backlog qu'on ECRIT, pas
    d'une globale : un banc jetable pose son backlog ailleurs et y trouve ses propres preuves.

    LE PRONONCE NE PEUT PAS TUER UNE FERMETURE. Si l'ecriture du champ echoue, on repose le
    statut sans lui : un item ferme sans sa trace se rattrape, un item que la boucle a laisse
    tomber en plein prononce, non.
    """
    try:
        reports = bk._reports_dir()
    except (AttributeError, TypeError):
        reports = str(AUTOPORT_DIR / "reports")
    record = gate_verdict.gate_record(result, reports, item_id, seq, journal)
    try:
        bk.set_status(item_id, status, gate_verdict=record, **fields)
    except Exception as e:                                              # noqa: BLE001
        log(f"⚠ {item_id} : le verdict de la porte n'a pas pu etre ecrit dans l'item ({e}) — "
            f"le statut est pose sans lui, et la promotion machine devra relire le journal.",
            "yellow")
        bk.set_status(item_id, status, **fields)
        return {}
    return record


def launch_item(bk, item: dict) -> dict:
    """LE LANCEMENT D'UN ESSAI : l'item passe `in-progress`, et son périmètre est PRONONCÉ ICI.

    GATE1/perimetre-sans-code — AU POINT DE PRODUCTION, PAS AU POINT DE CONTRÔLE. GATE 1
    refuse un vert obtenu sans une ligne de code moteur ; un item dont le périmètre INTERDIT
    `game/ android/ goalc/ goal_src/` échouait donc forcément à sa PREMIÈRE fermeture tant
    que personne n'avait posé `no_code: true` à la main. Rien ne le disait au lancement :
    l'essai partait, travaillait, tenait sa porte machine, et se faisait refuser sur un
    drapeau absent. Mesure du 2026-09-12 : essai 1 de `harness-proof-props-pin`, un essai
    entier brûlé, et le même coût à chaque nouvel item de harnais.

    Le périmètre le dit en toutes lettres ; `gate_verdict.code_free_item` le lit, et le
    drapeau est POSÉ dans `backlog.yaml` — dans l'écriture `in-progress` qui a lieu de toute
    façon, jamais une seconde. Le prononcé est journalisé : `logs/no-code-at-launch.log`
    garde la trace de ce qui a été LANCÉ, qu'un recensement du backlog d'aujourd'hui ne
    pourrait pas reconstruire.

    Ce que ça ne fait PAS : inventer un périmètre. Un `out_of_scope` muet n'interdit rien, et
    GATE 1 exige le code comme avant.
    """
    iid = item["id"]
    # LE PRONONCÉ NE PEUT PAS TUER UN LANCEMENT. Il est confortable, pas décisif : GATE 1 lit
    # le périmètre par la MÊME autorité, donc un drapeau qu'on n'a pas pu poser ne brûle plus
    # rien. Un backlog réduit — un bouchon de test, une implémentation partielle — n'a ni
    # `path` ni champs libres : il obtient son `in-progress`, et rien d'autre ne casse.
    try:
        logs_root = os.path.join(os.path.dirname(os.path.abspath(bk.path)), "logs")
    except (AttributeError, TypeError):
        logs_root = str(LOG_ROOT)
    sans_code, pourquoi = gate_verdict.code_free_item(item)
    # PERIMETRE/champ-explicite — LA MEME DECISION, ET D'OU ELLE VIENT. `code_free_item` est le
    # raccourci que GATE 1 appelle : il rend la decision, jamais sa provenance. On redemande donc
    # la decision COMPLETE a la meme autorite — un appel pur, sans entree/sortie. Ce n'est pas
    # une redite a factoriser : le compte d'appels de `code_free_item` dans ce fichier est le
    # temoin d'un AUTRE item (`src_gate1_lit_autorite`, harness-close-gate-code-free), et le
    # fondre ici le ferait rougir sans rien corriger.
    provenance = gate_verdict.scope_decision(item)["source"]
    pose = bool(sans_code) and not item.get("no_code", False)
    journal = (gate_verdict.note_launch(logs_root, iid, pose, pourquoi, provenance)
               if sans_code else "")
    if pose:
        log(f"· {iid} : son périmètre interdit le code du jeu ({pourquoi}, source "
            f"{provenance}) — `no_code: true` posé AU LANCEMENT. Sans ça, la porte de "
            f"fermeture aurait refusé cet essai sur ce seul drapeau, porte machine tenue ou "
            f"non.", "yellow")
    if provenance == gate_verdict.SRC_PROSE:
        log(f"· {iid} : son périmètre a été DEVINÉ dans une phrase ({pourquoi}). Le champ "
            f"`code_scope: none` le dirait sans deviner — ce repli est compté.", "dim")
    try:
        bk.set_status(iid, "in-progress", **({"no_code": True} if pose else {}))
    except TypeError:
        bk.set_status(iid, "in-progress")
        pose = False
    if pose:
        # `bk.items` a été remplacé par la relecture du disque : l'objet que `run_attempt` et
        # la porte de fermeture reçoivent est celui-ci, on le met d'accord avec le fichier.
        item["no_code"] = True
    return {"code_free": bool(sans_code), "posed": pose, "reason": pourquoi or "-",
            "source": provenance, "journal": journal or "-", "logs_root": logs_root}


def release_stale_in_progress(bk) -> list[str]:
    """Un item laissé `in-progress` par un orchestrateur tué redevient `open`.

    Un arrêt brutal (SIGKILL, terminal fermé, machine éteinte) ne passe par aucun
    chemin de sortie : l'item reste marqué `in-progress` pour toujours, et
    `next_open()` l'ignore — le harnais ne le reprendrait donc JAMAIS. C'est le
    remplaçant exact des 9 phases « parquées » qui ne fermaient plus dans l'ancien
    modèle, et ça s'est produit dès le premier jour (hd-skin-origin-stretch).

    On ne libère QUE ce que plus personne ne tient : `phase_claim.sh status` sort 0
    tant que le détenteur est vivant (pid + starttime + comm). Libérer un item tenu
    par un worker vivant remettrait deux workers sur le même arbre, ce que l'owner a
    explicitement interdit après que ça se soit produit deux fois.
    """
    freed = []
    for item in bk.items:
        if item.get("status") != "in-progress":
            continue
        iid = item["id"]
        held = subprocess.run(
            ["bash", str(AUTOPORT_DIR / "phase_claim.sh"), "status", iid],
            cwd=REPO_ROOT, capture_output=True, text=True)
        if held.returncode == 0:
            log(f"· {iid} est tenu par un worker VIVANT ({held.stdout.strip()[:60]}) "
                f"— laissé en place", "yellow")
            continue
        bk.set_status(iid, "open")
        freed.append(iid)
    if freed:
        log(f"· items rendus au backlog après un arrêt brutal : {', '.join(freed)}", "yellow")
    return freed


def _startup_refusals() -> str:
    """'' when we may start, otherwise the reason and what to do about it."""
    import shutil
    if BACKEND == "codex":
        if shutil.which("codex") is None:
            return "`codex` absent du PATH : installe la CLI Codex."
        reason = cli_backend.auth_error()
        if reason:
            return reason
    if BACKEND == "claude" and shutil.which("claude") is None:
        return ("`claude` n'est pas dans le PATH : aucun worker ne peut démarrer.\n"
                "  → installe la CLI Claude Code, ou corrige le PATH du service.")
    if BACKEND == "claude" and not CREDENTIALS_PATH.exists():
        return (f"aucun identifiant Claude Code dans {CREDENTIALS_PATH}.\n"
                f"  → lance `claude` une fois en interactif pour finir l'OAuth.")
    reason = backlog_missing_reason()
    if reason:
        return reason
    if not GENERIC_VALIDATOR.exists():
        return (f"{GENERIC_VALIDATOR} est absent : plus aucun item ne peut être jugé.\n"
                f"  → livre validators/generic.sh (chantier C), puis relance.")
    if SHIELD_GUARD.exists():
        # INTERDICTION OWNER 2026-08-30 : « Interdit de toucher a la SHIELD a
        # nouveau. Assures toi que vraiment rien n'y touche. » Le controle
        # tournait dans preflight, ou il violait le contrat du module (adb, pas
        # « sous la seconde ») et ou il a fini par eteindre TOUS les constats.
        # Ici il est ce qu'il doit etre : un REFUS DE DEMARRER, une fois.
        r = subprocess.run(["bash", str(SHIELD_GUARD)], cwd=REPO_ROOT,
                           capture_output=True, text=True)
        if r.returncode != 0:
            return ("la SHIELD est touchée ou ciblée — interdiction de l'owner du "
                    "2026-08-30 :\n" + (r.stderr or r.stdout).strip()[:800])
    return ""


def main(argv: list[str] | None = None) -> int:
    global QUIET, BACKEND, _PROFILE, MODEL, EFFORT, SUBAGENT_MODEL, WORKER_EFFORTS, PROFILE_NAME
    parser = argparse.ArgumentParser(description="Autoport orchestrator")
    parser.add_argument("--quiet", action="store_true",
                        help="Supprime le rendu des événements (le stderr de claude "
                             "reste imprimé : c'est la seule trace d'un non-démarrage)")
    parser.add_argument("--backend", choices=cli_backend.BACKENDS,
                        default=cli_backend.selected(root=REPO_ROOT))
    parser.add_argument("--check", action="store_true",
                        help="Vérifie la CLI et affiche la commande sans lancer de worker")
    args = parser.parse_args(argv)
    BACKEND = cli_backend.selected(args.backend)
    os.environ["AUTOPORT_BACKEND"] = BACKEND
    try:
        _PROFILE = (cli_backend.codex_profile(REPO_ROOT) if BACKEND == "codex"
                    else _load_model_profile())
    except (ValueError, KeyError, OSError) as e:
        parser.error(str(e))
    MODEL, EFFORT = _PROFILE["manager_model"], _PROFILE["manager_effort"]
    SUBAGENT_MODEL, WORKER_EFFORTS = _PROFILE["worker_model"], _PROFILE["worker_efforts"]
    PROFILE_NAME = _PROFILE["_active_name"]
    if args.check:
        import shutil
        error = (cli_backend.auth_error() if BACKEND == "codex" else
                 ("identifiants Claude absents" if not CREDENTIALS_PATH.exists() else ""))
        if not shutil.which(BACKEND):
            error = f"CLI {BACKEND} absente du PATH"
        print(json.dumps({"backend": BACKEND, "profile": PROFILE_NAME, "error": error,
                          "command": cli_backend.worker_command(REPO_ROOT, BACKEND, _PROFILE, EFFORT, 300)},
                         ensure_ascii=False, indent=2))
        return int(bool(error))
    backend_control.require(BACKEND, REPO_ROOT)
    QUIET = bool(args.quiet)

    lock = acquire_single_instance_lock()
    if lock == "BUSY":
        return 1

    refusal = _startup_refusals()
    if refusal:
        console.print(Panel.fit(f"[bold red]Démarrage refusé[/bold red]\n\n{refusal}",
                                border_style="red"))
        return 1

    state = load_state()
    bk = load_backlog()
    release_stale_in_progress(bk)

    console.print(Panel.fit(
        f"[bold green]Orchestrateur autoport[/bold green]\n"
        f"Dépôt : {REPO_ROOT}\n"
        f"Profil : {PROFILE_NAME} · manager {MODEL} @ {EFFORT} · sous-agents {SUBAGENT_MODEL}\n"
        f"Backlog : {len(bk.items)} items",
        border_style="green"))

    no_start_streak = 0

    # Au démarrage seulement : rendre au backlog ce qu'un arrêt brutal a laissé
    # marqué `in-progress` sans détenteur vivant. Sans ça l'item est perdu pour
    # toujours, `next_open()` l'ignorant. Ne jamais faire ça DANS la boucle : notre
    # propre item y est légitimement `in-progress`.
    release_stale_in_progress(load_backlog())

    pause_file = Path(__file__).resolve().parent / "PAUSE"

    while not HALT:
        backend_control.require(BACKEND, REPO_ROOT)
        # Frein de l'owner : `touch .autoport/PAUSE` arrete le harnais APRES l'item en cours,
        # jamais au milieu. Demande le 2026-09-10 (« faut faire en sorte que ca s'arrete une
        # fois l'item en cours termine ») pour changer de telephone sans qu'un item enchaine
        # tout seul. `rm` du fichier + relance pour repartir.
        if pause_file.exists():
            log("⏸ .autoport/PAUSE present : arret demande par l'owner. L'item en cours est "
                "termine, on ne prend pas le suivant. `rm .autoport/PAUSE` puis relancer.",
                "bold yellow")
            break

        bk = load_backlog()
        # RECHARGEMENT/filet — tant qu'un rechargement echoue, le journal le REPETE a chaque
        # tour et compte les tours poursuivis malgre lui. Un harnais qui tourne sur du code
        # vieux et se tait, c'est le gel silencieux que ces rechargements corrigeaient.
        safe_reload.turn_report(log)
        promote_owner_validated(bk)
        free_machine_proved(bk)

        item = bk.next_open()
        if item is None:
            log("Rien d'ouvert dans le backlog : tout est validé, à tester ou bloqué. "
                "`./.autoport/autoport status` dit quoi.", "bold green")
            break

        iid = item["id"]
        started = time.time()
        # Le périmètre de l'item est prononcé ICI, pas à sa fermeture : voir `launch_item`.
        launch_item(bk, item)
        try:
            out = run_attempt(item, state)
        except StateConflict as e:
            bk.set_status(iid, "open")
            console.print(Panel.fit(f"[bold red]{e}[/bold red]", border_style="red"))
            return 1

        if out.kind == "pass":
            pronounce_gate(bk, iid, "validated", gate_verdict.VERDICT_TENUE,
                           out.seq, out.journal)
            log(f"✓ {iid} validé en {format_duration(time.time() - started)} "
                f"({state['retries'].get(iid, 1)} essai(s)).", "bold green")
            no_start_streak = 0

        elif out.kind == "awaiting-owner":
            # `delivered` DOIT etre pose ici : sans lui, _testable_now() range l'item dans
            # « Dette a trier » avec les orphelins de juillet au lieu de « A tester », et
            # l'owner ne voit jamais qu'on vient de lui livrer quelque chose (perf-ocean-idle,
            # 10/09 : livre a 09h55, invisible dans son digest de 10h18).
            pronounce_gate(bk, iid, "to-test", gate_verdict.VERDICT_TENUE,
                           out.seq, out.journal,
                           delivered=datetime.now().date().isoformat())
            console.print(Panel.fit(
                f"[bold yellow]⏸ {iid} — À TESTER PAR L'OWNER[/bold yellow]\n\n"
                f"{item.get('feature', '')}\n\n"
                f"Validateur et portes passés. Seul l'owner ferme :\n"
                f"  ./.autoport/autoport ok {iid} \"sa phrase\"",
                border_style="yellow"))
            no_start_streak = 0

        elif out.kind in ("stuck", "blocked"):
            # lib/backlog.py refuse un `blocked` sans raison : on ne laisse
            # jamais ce refus tuer la boucle au moment précis où un item bloque.
            bk.set_status(iid, "blocked",
                          block_reason=out.reason or "raison non enregistrée")
            console.print(Panel.fit(
                f"[bold red]✗ {iid} BLOQUÉ[/bold red]\n\n{out.reason}\n\n"
                + "\n".join(f"  {ln}" for ln in out.key_lines[-8:]),
                border_style="red"))
            if out.stderr_tail:
                log(f"Ce que {BACKEND} a dit :", "yellow")
                for ln in out.stderr_tail[-10:]:
                    log(f"  {ln}", "dim")
            no_start_streak = 0

        elif out.kind == "foreign":
            # L'arbre portait le travail non commité d'un AUTRE item : l'essai n'a pas
            # échoué, il n'avait rien de reproductible à juger. Ni compté, ni empreinté,
            # et `retries` a été remis comme avant.
            bk.set_status(iid, "open")
            log(f"⏹ {iid} : essai CLASSÉ À PART — cause EXTÉRIEURE à l'item, non compté, "
                f"non empreinté. Le travail est commité.\n{out.reason}", "yellow")
            no_start_streak = 0
            nap(30)

        elif out.kind == "impossible":
            # AUCUNE PREUVE N'ÉTAIT POSSIBLE. Ni « pas de preuve », ni un échec du worker :
            # la machine ne pouvait rien mesurer, la cause est NOMMÉE et DATÉE. `autoport
            # status` et le digest de l'owner la portent aussi — cet item ne se lit plus
            # comme un item qui n'a rien produit.
            bk.set_status(iid, "open")
            log(f"⏹ {iid} : essai CLASSÉ À PART — PREUVE IMPOSSIBLE, non compté, non "
                f"empreinté. Le travail est commité.\n{out.reason}", "yellow")
            no_start_streak = 0
            nap(60)

        elif out.kind == "aborted":
            # Le lanceur a coupe les taches de fond du worker : l'essai n'a pas eu lieu.
            # On rouvre l'item tel quel — ni compte, ni empreinte, ni validateur.
            bk.set_status(iid, "open")
            log(f"⏹ {iid} : essai ABORTÉ — {out.reason}. Ni compté, ni empreinté, "
                f"validateur non lancé. Le travail est commité.", "yellow")
            nap(10)

        elif out.kind == "interrupted":
            bk.set_status(iid, "open")
            log(f"· {iid} : essai annulé ({out.reason}) — ni compté, ni empreinté. "
                f"Le travail est commité.", "yellow")
            if HALT:
                break

        elif out.kind == "no-start":
            bk.set_status(iid, "open")
            no_start_streak += 1
            state["rate_interrupts"][iid] = int(state["rate_interrupts"].get(iid, 0)) + 1
            save_state(state)
            log(f"⏳ {iid} : {out.reason} (non compté, {no_start_streak}/"
                f"{MAX_NO_START_ITERATIONS})", "yellow")
            for ln in out.stderr_tail[-10:]:
                log(f"    {BACKEND}: {ln}", "dim")
            if no_start_streak >= MAX_NO_START_ITERATIONS:
                console.print(Panel.fit(
                    f"[bold red]{MAX_NO_START_ITERATIONS} sessions de suite refusées au "
                    f"démarrage[/bold red]\n\nOn s'arrête au lieu de boucler : la boucle "
                    f"précédente a tourné 230 fois en 19,7 h sans que personne puisse dire "
                    f"pourquoi.\nDernières lignes de {BACKEND} :\n"
                    + "\n".join(f"  {ln}" for ln in out.stderr_tail[-10:]),
                    border_style="red"))
                return 1
            if out.resume_at:
                sleep_until(min(out.resume_at + 90,
                                int(time.time()) + NO_START_MAX_SLEEP),
                            "la réouverture de la fenêtre annoncée par l'API")
            else:
                log(f"L'API n'a annoncé aucune heure de réouverture — repli sur "
                    f"{NO_START_FALLBACK_SLEEP}s.", "dim")
                nap(NO_START_FALLBACK_SLEEP)

        elif out.kind == "infra":
            bk.set_status(iid, "open")
            log(f"⏸ {iid} : {out.reason} — panne d'infra, essai non compté.", "yellow")
            if out.resume_at:
                sleep_until(out.resume_at, "la fin de la tempête d'API")

        else:  # fail
            bk.set_status(iid, "open")
            attempts = state["retries"].get(iid, 0)
            fps = state.get("fingerprints", {}).get(iid, [])
            log(f"{iid} : essai {attempts}/{item.get('max_retries', 6)} échoué. "
                f"{len(set(fps))} mode(s) d'échec distinct(s). On recommence.", "yellow")
            no_start_streak = 0
            nap(30)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
