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

# ============================================================
# Configuration
# ============================================================

# Model + effort come from the ACTIVE profile in .autoport/model-profiles.json
# (single source of truth — flip "active" there to switch the whole setup, then
# run .autoport/apply-model-profile.sh + relaunch). Hardcoded fallback below is
# used only if the JSON is missing/unreadable.
_PROFILE_PATH = Path(__file__).resolve().parent / "model-profiles.json"


def _load_model_profile() -> dict:
    fallback = {
        "manager_model": "claude-opus-5", "manager_effort": "high",
        "worker_model": "claude-opus-5",
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


def check_stuck(state: dict, item_id: str, current_fp: str) -> tuple[bool, str]:
    """Stuck = the same fingerprint STUCK_REPEAT_THRESHOLD times in a row."""
    history = state.get("fingerprints", {}).get(item_id, [])
    if len(history) < STUCK_REPEAT_THRESHOLD:
        return False, ""

    recent = history[-STUCK_REPEAT_THRESHOLD:]
    if all(fp == current_fp for fp in recent):
        return True, (
            f"Même empreinte d'échec '{current_fp}' {STUCK_REPEAT_THRESHOLD} essais "
            f"de suite : le worker n'apprend plus du validateur. On arrête cet item "
            f"au lieu de brûler du quota dessus."
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
              "rate_interrupts", "last_update")


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
    importlib.reload(_bk)
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


def fatal_config_reason(path: Path) -> str:
    """A model/auth/request error that will repeat forever, not a rate limit."""
    for ev in _iter_events(path):
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
    ".autoport/.scope_stamp",
    ".autoport/.directives_issued",
    ".autoport/.last_apk_build_sha",
    ".autoport/.last_owner_notify.json",
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


def git_commit_paths(item_id: str, message: str, paths: list[str]) -> bool:
    """Commit ONLY `paths`. Returns True if a commit was created."""
    if not paths:
        return False
    spec = "\0".join(paths)
    add = subprocess.run(["git", "add", "--pathspec-from-file=-", "--pathspec-file-nul"],
                         cwd=REPO_ROOT, input=spec, capture_output=True, text=True)
    if add.returncode != 0:
        log(f"git add a échoué : {add.stderr.strip()[:300]}", "yellow")
        return False
    staged = subprocess.run(["git", "diff", "--cached", "--quiet",
                             "--pathspec-from-file=-", "--pathspec-file-nul"],
                            cwd=REPO_ROOT, input=spec, capture_output=True, text=True)
    if staged.returncode == 0:
        return False                       # nothing of ours actually changed
    r = subprocess.run(["git", "commit", "-m", f"[autoport/{item_id}] {message}",
                        "--pathspec-from-file=-", "--pathspec-file-nul"],
                       cwd=REPO_ROOT, input=spec, capture_output=True, text=True)
    if r.returncode != 0:
        log(f"git commit a échoué : {(r.stderr or r.stdout).strip()[:300]}", "yellow")
        return False
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
            fresh = []
            for ln in stat_out.splitlines():
                bits = ln.split(None, 1)
                if len(bits) == 2 and bits[0].strip().isdigit() and int(bits[0]) >= t0:
                    fresh.append(bits[1].strip())
            focused = any(pkg in l for l in sh("shell", "dumpsys", "window").stdout.splitlines()
                          if "mCurrentFocus" in l)
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


def close_gate(item: dict) -> tuple[str, str]:
    """Run after generic.sh exits 0. Returns (status, reason):
      ("pass", "")            -> all gates clear; the item is validated
      ("fail", reason)        -> a FIXABLE gate failed; retry + feed reason back
      ("awaiting-owner", "")  -> gates clear, the owner still has to look
    """
    iid = item["id"]
    item = _reread_item(iid, item)

    # GATE 1 — real translation-layer code change (anti-stub false-green).
    # An item was once marked done with ZERO code. Require a real change since
    # the supervisor anchor, unless the item declares `no_code: true`.
    if not item.get("no_code", False):
        anchor = _supervisor_anchor(iid)
        paths = ["game/", "android/", "goalc/", "goal_src/"]
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
                    "Si cet item ne livre légitimement aucun code, mets `no_code: true` "
                    "sur lui dans backlog.yaml.")

    # GATE 2 — device runs the fresh, CONSISTENT build (anti stale/mixed-build).
    # The validator can pass while the phone still runs an old libgk, or a MIXED
    # build (fresh CGOs + stale libgk) — exactly the 2026-06-30 flicker incident.
    if item.get("device", False):
        serial = item.get("device_serial") or os.environ.get("ANDROID_SERIAL", "eae4df44")
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
            acq_serial = item.get("device_serial") or os.environ.get("ANDROID_SERIAL", "eae4df44")
        for script in sorted(acquis_dir.glob("*.sh")):
            try:
                r = subprocess.run(["bash", str(script), acq_serial], cwd=REPO_ROOT,
                                   capture_output=True, text=True, timeout=600)
            except subprocess.TimeoutExpired:
                return ("fail", f"CLOSE-GATE/acquis: {script.name} n'a pas répondu en 600 s")
            if r.returncode != 0:
                tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-4:])
                return ("fail",
                        f"CLOSE-GATE/acquis: {script.name} — un ACQUIS VALIDÉ PAR L'OWNER "
                        "n'est plus tenu (ou plus prouvable) sur ce build. L'item ne se ferme "
                        "pas tant qu'il n'est pas rétabli.\n" + tail)
            console.print(f"[green]close-gate acquis: {script.name} ok[/green]")

    # GATE 4 — l'oeil de l'owner est la porte FINALE. Un item passe donc en
    # `to-test`, jamais directement en `validated` : seul `owner_ok` le ferme.
    if item.get("owner_verify", True) and not owner_said_yes(item):
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
        lines.append(f"- critère machine : `{gate.get('key')} {gate.get('op')} "
                     f"{gate.get('value')}` lu dans `.autoport/reports/{item['id']}/proof.txt`")
    if item.get("device"):
        lines.append(f"- preuve exigée SUR APPAREIL "
                     f"{item.get('device_serial') or 'eae4df44'} (jamais la SHIELD)")
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
    return (
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
        "- C++ change => rebuild, but INCREMENTAL: `cmake --build <dir> --target gk`.\n"
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
        "## HANDOFF (obligatoire si tu n'aboutis pas)\n"
        f"Avant de t'arrêter sans avoir fait passer la porte, écris "
        f"`.autoport/reports/<id>/handoff.md`, {HANDOFF_MAX_LINES} lignes MAXIMUM,\n"
        "en trois sections : ce qui est ÉTABLI (mesuré, pas supposé), ce qui a été\n"
        "TENTÉ et pourquoi ça a échoué, ce qui RESTE à faire. C'est le seul contexte\n"
        "que l'essai suivant recevra.\n\n"
    )


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
        importlib.reload(_dv)
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
        importlib.reload(_pf)
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
      stuck           same failure 3x -> blocked
      blocked         max_retries, missing input, fatal config
      interrupted     signal / scope change / duplicate worker: NOT counted
      no-start        refused at the door, zero work: NOT counted
      infra           529 storm: NOT counted
    """
    kind: str
    reason: str = ""
    key_lines: list[str] = field(default_factory=list)
    resume_at: int | None = None
    stderr_tail: list[str] = field(default_factory=list)


def run_attempt(item: dict, state: dict) -> Outcome:
    global _CURRENT_CHILD
    iid = item["id"]
    log_dir = LOG_ROOT / iid
    log_dir.mkdir(parents=True, exist_ok=True)
    seq = next_attempt_seq(state, iid)
    attempt_log = log_dir / f"attempt-{seq:03d}.jsonl"
    validator_log = log_dir / f"validator-{seq:03d}.txt"
    started_at = time.time()

    prompt_path = AUTOPORT_DIR / item.get("prompt", "")
    if not item.get("prompt") or not prompt_path.exists():
        return Outcome("blocked", f"prompt absent : {prompt_path}")
    if not GENERIC_VALIDATOR.exists():
        return Outcome("blocked", f"validateur absent : {GENERIC_VALIDATOR}")

    effort = item.get("effort", EFFORT)
    instructions = build_instructions(item, seq)

    console.print(Panel.fit(
        f"[bold cyan]{iid}[/bold cyan] · essai {seq} · "
        f"{item.get('feature', '')[:70]}\n"
        f"modèle={MODEL} · effort={effort} · sous-agents={SUBAGENT_MODEL}",
        border_style="cyan"))

    env = os.environ.copy()
    env["CLAUDE_EFFORT"] = effort
    env["CLAUDE_CODE_SUBAGENT_MODEL"] = SUBAGENT_MODEL
    env["AUTOPORT_PHASE_ID"] = iid                       # = l'id d'item
    env["AUTOPORT_PHASE_VALIDATOR"] = str(GENERIC_VALIDATOR)

    # 2026-08-17 : le prompt passe par STDIN, plus jamais en argv. Un argument
    # unique est plafonne a MAX_ARG_STRLEN (~128 Ko) sur Linux ; le contrat a
    # depasse cette taille et l'exec mourait en OSError E2BIG AVANT tout travail.
    cmd = [
        "claude", "-p",
        "--model", MODEL,
        "--effort", effort,
        "--max-turns", str(min(item.get("max_turns", 300), 300)),
        "--output-format", "stream-json",
        "--verbose",
        "--dangerously-skip-permissions",
    ]

    pstate = PrettyState(t0=time.monotonic())
    stderr_tail: list[str] = []
    abort_reason = ""       # "" | scope | no-progress | post-result | hard-silence
    rc = -1

    with attempt_log.open("x") as f:
        f.write(json.dumps({
            "event": "attempt_start", "item_id": iid, "attempt": seq,
            "model": MODEL, "effort": effort, "subagent_model": SUBAGENT_MODEL,
            "cmd": cmd, "started_at": datetime.now(timezone.utc).isoformat(),
        }) + "\n")
        f.flush()

        proc = subprocess.Popen(cmd, cwd=REPO_ROOT, env=env,
                                stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, bufsize=1, text=True,
                                start_new_session=True)
        try:
            proc.stdin.write(instructions)
        finally:
            proc.stdin.close()          # EOF, sans quoi claude attend indefiniment
        _CURRENT_CHILD = proc

        last_event_at = time.monotonic()
        last_progress_at = time.monotonic()
        last_progress_fp = _progress_fingerprint(iid)
        scope_seen = _scope_changed(None)

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

                if not ready:
                    idle = time.monotonic() - last_event_at
                    if proc.poll() is not None:
                        break
                    # claude said `result` but won't exit (TaskCreate re-engagements
                    # keep the process open in -p mode). Force the issue.
                    if pstate.result_seen and idle >= STALL_POST_RESULT_SEC:
                        log(f"· claude a émis result sans sortir ({idle:.0f}s) — "
                            f"fermeture forcée", "yellow")
                        _kill("post-result")
                        break
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
                        log(f"· aucune sortie de claude depuis {idle:.0f}s — on tue", "red")
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
                    stderr_tail.append(line)
                    del stderr_tail[:-40]
                    console.print(f"[magenta]claude:[/magenta] [dim]{_truncate(line, 300)}[/dim]")
                    continue

                pretty_print_event(ev, pstate)
        except KeyboardInterrupt:
            _kill("signal")
            raise
        finally:
            try:
                rc = proc.wait(timeout=None if not abort_reason else 30)
            except subprocess.TimeoutExpired:
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
            "tool_calls": pstate.tool_calls,
            "tokens_in": pstate.tokens_in, "tokens_out": pstate.tokens_out,
            "cache_read": pstate.cache_read,
        }) + "\n")

    touched = worker_paths()          # ce que l'essai a laissé dans l'arbre
    did_work = (pstate.tokens_in + pstate.tokens_out) > 0 or pstate.tool_calls > 0

    def _checkpoint(label: str) -> bool:
        """Save the work. ALWAYS — an attempt we cancel is still work done.

        The path list is recomputed here rather than reused: the validator and
        the close-gate run between the worker's exit and this commit."""
        try:
            paths = worker_paths()
            if git_commit_paths(iid, label, paths):
                log(f"  checkpoint commité ({len(paths)} chemin(s))", "green")
                return True
        except Exception as e:  # noqa: BLE001 — never let checkpointing crash the loop
            log(f"checkpoint impossible : {e}", "yellow")
        return False

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

    fatal = fatal_config_reason(attempt_log) if (rc != 0 and not did_work) else ""
    if fatal:
        return Outcome("blocked", fatal, stderr_tail=stderr_tail)

    if rc != 0 and not abort_reason and (not did_work or pstate.rate_rejected):
        # Refused by the API: either at the door (zero tokens, zero tool calls)
        # or mid-work with an explicit `rejected`. Either way it is a quota
        # event, not a failure of the worker, and the API told us WHEN the
        # window reopens — we sleep until then instead of guessing five minutes.
        reset = pstate.rate_reset_at or rate_reset_from_log(attempt_log)
        why = ("l'API nous a refusés en cours de session"
               if did_work else f"claude est sorti en {rc} sans rien faire")
        _checkpoint(f"essai {seq} — session refusée par l'API (non compté)")
        return Outcome("no-start", why, resume_at=reset, stderr_tail=stderr_tail)

    if rc != 0 and not abort_reason:
        # An Anthropic outage, counted from structured API errors only, and only
        # when WE did not kill the child (our own SIGTERM is exit 143).
        n529 = count_api_529(attempt_log)
        if n529 >= API_529_STORM_THRESHOLD:
            _checkpoint(f"essai {seq} — tempête 529 de l'API (non compté)")
            return Outcome("infra", f"tempête 529 ({n529} erreurs d'API)",
                           resume_at=int(time.time()) + API_529_SLEEP)

    # ---- COUNTED OUTCOMES ------------------------------------------------
    log(f"Claude Code est sorti en {rc}. Validateur…", "dim")
    with validator_log.open("w") as f:
        v = subprocess.run(["bash", str(GENERIC_VALIDATOR)], cwd=REPO_ROOT,
                           env={**os.environ, "AUTOPORT_PHASE_ID": iid},
                           stdout=f, stderr=subprocess.STDOUT)

    state["retries"][iid] = int(state["retries"].get(iid, 0)) + 1
    attempt_count = state["retries"][iid]
    save_state(state)

    gate_reason = ""
    if v.returncode == 0:
        gate_status, gate_reason = close_gate(item)
        if gate_status in ("pass", "awaiting-owner"):
            if _checkpoint(item.get("feature", iid)
                           + ("" if gate_status == "pass"
                              else " (porte passée — EN ATTENTE DU TEST DE L'OWNER)")):
                git_push()
            return Outcome(gate_status)
        with validator_log.open("a") as f:
            f.write("\n\n" + gate_reason + "\n")
        log(gate_reason, "yellow")

    failure_text = validator_log.read_text(errors="replace")
    fp, key_lines = fingerprint_validator_output(failure_text)
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
    if shutil.which("claude") is None:
        return ("`claude` n'est pas dans le PATH : aucun worker ne peut démarrer.\n"
                "  → installe la CLI Claude Code, ou corrige le PATH du service.")
    if not CREDENTIALS_PATH.exists():
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
    global QUIET
    parser = argparse.ArgumentParser(description="Autoport orchestrator")
    parser.add_argument("--quiet", action="store_true",
                        help="Supprime le rendu des événements (le stderr de claude "
                             "reste imprimé : c'est la seule trace d'un non-démarrage)")
    args = parser.parse_args(argv)
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

    while not HALT:
        bk = load_backlog()
        promote_owner_validated(bk)

        item = bk.next_open()
        if item is None:
            log("Rien d'ouvert dans le backlog : tout est validé, à tester ou bloqué. "
                "`./.autoport/autoport status` dit quoi.", "bold green")
            break

        iid = item["id"]
        started = time.time()
        bk.set_status(iid, "in-progress")
        try:
            out = run_attempt(item, state)
        except StateConflict as e:
            bk.set_status(iid, "open")
            console.print(Panel.fit(f"[bold red]{e}[/bold red]", border_style="red"))
            return 1

        if out.kind == "pass":
            bk.set_status(iid, "validated")
            log(f"✓ {iid} validé en {format_duration(time.time() - started)} "
                f"({state['retries'].get(iid, 1)} essai(s)).", "bold green")
            no_start_streak = 0

        elif out.kind == "awaiting-owner":
            bk.set_status(iid, "to-test")
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
                log("Ce que claude a dit :", "yellow")
                for ln in out.stderr_tail[-10:]:
                    log(f"  {ln}", "dim")
            no_start_streak = 0

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
                log(f"    claude: {ln}", "dim")
            if no_start_streak >= MAX_NO_START_ITERATIONS:
                console.print(Panel.fit(
                    f"[bold red]{MAX_NO_START_ITERATIONS} sessions de suite refusées au "
                    f"démarrage[/bold red]\n\nOn s'arrête au lieu de boucler : la boucle "
                    f"précédente a tourné 230 fois en 19,7 h sans que personne puisse dire "
                    f"pourquoi.\nDernières lignes de claude :\n"
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
