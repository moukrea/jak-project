#!/usr/bin/env python3
"""
OpenGOAL → Android autonomous orchestrator.

Hardcoded design choices (per project owner's preference):
- Model: claude-opus-4-7 for EVERY phase. No Sonnet fallback ever.
- Thinking effort: max (via CLAUDE_EFFORT env + 'ultrathink' keyword in prompts)
- Rate-limit waits use the EXACT reset epoch returned by the API.
  No "next Monday" assumption. The API tells us when the window resets;
  we sleep until that timestamp + a small buffer.

Lifecycle:
1. Load milestones.yaml, load state.json
2. For each unfinished phase:
   a. Poll rate-limit API. If above threshold, sleep until reset_at + buffer.
   b. Launch `claude -p` with the phase prompt, Opus 4.7, max effort.
   c. Stop-hook inside Claude Code re-runs the validator after every turn
      and blocks completion until it passes (or turn cap is hit).
   d. After claude exits, re-run validator post-hoc as ground truth.
   e. On pass: git commit, optional push, notify, advance.
   f. On fail: increment retry, feed validator output back into the next attempt.
   g. After max_retries: mark blocked, notify, halt.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import signal
import subprocess
import sys
import time
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
import yaml
from rich.console import Console
from rich.panel import Panel

# ============================================================
# Configuration — hardcoded per owner preference.
# ============================================================

MODEL = "claude-opus-4-7"
EFFORT = "max"

# Full YOLO mode: --dangerously-skip-permissions bypasses ALL permission
# prompts. No per-tool allowlist — Claude can use any tool freely.
# Safety net: per-phase git commits make any damage trivially revertable.

# Rate-limit thresholds (0-100 percent)
SESSION_PAUSE_PCT = 90.0   # 5h window: pause at this %
WEEKLY_PAUSE_PCT = 95.0    # weekly: pause at this %
RESET_BUFFER_SECONDS = 90  # wait this long after the API-reported reset
POLL_INTERVAL_SECONDS = 300  # how often to re-check while sleeping (5 min)

# Stuck detection: how many identical validator-failure fingerprints in a
# row before we conclude the agent has stopped learning and is just burning
# tokens. Set to 3 = halt when the same failure recurs three attempts in a
# row. Note: a "different failure" still counts as progress, even if both
# fail — what we're guarding against is the exact-same error repeating.
STUCK_REPEAT_THRESHOLD = 3

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

    Returns (sha1_short, key_lines) where:
      - sha1_short is a 12-char hash that's the same across attempts that
        fail the same way, and different when the failure mode changes
      - key_lines is the actual normalized text we hashed, for human display

    Strategy: keep only lines mentioning errors/failures, normalize away
    timestamps/paths/addresses/durations, then hash the tail.
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

    # Keep the last 15 — most-recent errors are the most diagnostic.
    key_lines = sig_lines[-15:]
    fp = hashlib.sha1('\n'.join(key_lines).encode('utf-8', errors='replace')).hexdigest()[:12]
    return fp, key_lines


def check_stuck(state: dict, phase_id: str, current_fp: str) -> tuple[bool, str]:
    """
    Returns (is_stuck, human_reason).

    Stuck = the same fingerprint has now occurred STUCK_REPEAT_THRESHOLD
    times in a row across recorded attempts for this phase.
    """
    history = state.get("fingerprints", {}).get(phase_id, [])
    if len(history) < STUCK_REPEAT_THRESHOLD:
        return False, ""

    recent = history[-STUCK_REPEAT_THRESHOLD:]
    if all(fp == current_fp for fp in recent):
        return True, (
            f"Same failure fingerprint '{current_fp}' has recurred "
            f"{STUCK_REPEAT_THRESHOLD} attempts in a row. The agent is no longer "
            f"learning from validator feedback — halting to preserve token quota."
        )
    return False, ""


# ============================================================
# Paths
# ============================================================

REPO_ROOT = Path(__file__).resolve().parent.parent
AUTOPORT_DIR = REPO_ROOT / ".autoport"
STATE_PATH = AUTOPORT_DIR / "state.json"
MILESTONES_PATH = AUTOPORT_DIR / "milestones.yaml"
LOG_ROOT = AUTOPORT_DIR / "logs"
NOTIFY_SCRIPT = AUTOPORT_DIR / "lib" / "notify.sh"
CREDENTIALS_PATH = Path.home() / ".claude" / ".credentials.json"

console = Console()
HALT = False


def _sig(_sig, _frame):
    global HALT
    console.print("\n[yellow]⚠ Received signal — finishing current step then halting.[/yellow]")
    HALT = True


signal.signal(signal.SIGINT, _sig)
signal.signal(signal.SIGTERM, _sig)


# ============================================================
# State persistence
# ============================================================

def load_state() -> dict:
    if STATE_PATH.exists():
        return json.loads(STATE_PATH.read_text())
    return {
        "current_phase_idx": 0,
        "retries": {},
        "fingerprints": {},
        "stuck_reasons": {},
        "completed": [],
        "blocked": [],
        "started_at": datetime.now(timezone.utc).isoformat(),
    }


def save_state(state: dict) -> None:
    state["last_update"] = datetime.now(timezone.utc).isoformat()
    STATE_PATH.write_text(json.dumps(state, indent=2))


def load_milestones() -> dict:
    return yaml.safe_load(MILESTONES_PATH.read_text())


# ============================================================
# Rate-limit awareness — uses ACTUAL reset_at from API.
# No hardcoded weekly boundaries.
# ============================================================

@dataclass
class RateStatus:
    session_pct: float
    session_reset: int  # unix epoch
    weekly_pct: float
    weekly_reset: int   # unix epoch
    raw: dict

    def session_reset_iso(self) -> str:
        return datetime.fromtimestamp(self.session_reset, tz=timezone.utc).isoformat()

    def weekly_reset_iso(self) -> str:
        return datetime.fromtimestamp(self.weekly_reset, tz=timezone.utc).isoformat()


def get_oauth_token() -> str | None:
    if not CREDENTIALS_PATH.exists():
        return None
    try:
        return json.loads(CREDENTIALS_PATH.read_text()) \
            .get("claudeAiOauth", {}).get("accessToken")
    except Exception:
        return None


def fetch_rate_status() -> RateStatus | None:
    """Returns None if we can't reach the API; caller proceeds cautiously."""
    token = get_oauth_token()
    if not token:
        return None
    try:
        r = requests.get(
            "https://api.anthropic.com/api/oauth/usage",
            headers={
                "Authorization": f"Bearer {token}",
                "anthropic-beta": "oauth-2025-04-20",
            },
            timeout=15,
        )
        r.raise_for_status()
        data = r.json()
        return RateStatus(
            session_pct=float(data["five_hour"]["utilization"]),
            session_reset=int(
                datetime.fromisoformat(
                    data["five_hour"]["resets_at"].replace("Z", "+00:00")
                ).timestamp()
            ),
            weekly_pct=float(data["seven_day"]["utilization"]),
            weekly_reset=int(
                datetime.fromisoformat(
                    data["seven_day"]["resets_at"].replace("Z", "+00:00")
                ).timestamp()
            ),
            raw=data,
        )
    except Exception as e:
        console.print(f"[yellow]Rate-limit probe failed: {e}[/yellow]")
        return None


def sleep_until(epoch: int, label: str) -> None:
    """Sleep until the given UTC epoch. Wakes early if HALT is signaled."""
    while not HALT:
        remaining = epoch - int(time.time())
        if remaining <= 0:
            return
        mins = remaining // 60
        hrs = mins // 60
        when = datetime.fromtimestamp(epoch, tz=timezone.utc)
        console.print(
            f"[dim]Sleeping {hrs}h{mins % 60:02d}m until {label} reset "
            f"({when.isoformat()})[/dim]"
        )
        # Sleep in chunks so we can react to signals and re-probe periodically
        chunk = min(remaining, POLL_INTERVAL_SECONDS)
        time.sleep(chunk)


def wait_for_quota() -> bool:
    """
    Block until safe to launch the next phase.
    Returns False if HALT was signaled.
    Notifies on pause and resume so the user knows what's happening.
    """
    slept = False
    while not HALT:
        status = fetch_rate_status()
        if status is None:
            console.print("[yellow]No rate data — proceeding optimistically.[/yellow]")
            if slept:
                notify("▶ resumed after pause", level="info")
            return True

        console.print(
            f"[dim]Rate check: session={status.session_pct:.1f}%  "
            f"weekly={status.weekly_pct:.1f}%[/dim]"
        )

        # Weekly first — bigger window, more catastrophic if missed
        if status.weekly_pct >= WEEKLY_PAUSE_PCT:
            wait_secs = max(0, status.weekly_reset - int(time.time()))
            notify(
                f"⏸ WEEKLY limit at {status.weekly_pct:.1f}%. "
                f"Pausing until {status.weekly_reset_iso()} "
                f"({format_duration(wait_secs)})",
                level="warn",
            )
            sleep_until(status.weekly_reset + RESET_BUFFER_SECONDS, "weekly")
            slept = True
            continue

        if status.session_pct >= SESSION_PAUSE_PCT:
            wait_secs = max(0, status.session_reset - int(time.time()))
            console.print(
                f"[yellow]Session at {status.session_pct:.1f}% — "
                f"pausing until {status.session_reset_iso()}[/yellow]"
            )
            notify(
                f"⏸ session limit {status.session_pct:.1f}%. "
                f"Resume in {format_duration(wait_secs)} (~{status.session_reset_iso()[11:16]} UTC)",
                level="info",
            )
            sleep_until(status.session_reset + RESET_BUFFER_SECONDS, "session")
            slept = True
            continue

        if slept:
            notify("▶ resumed after rate-limit pause", level="info")
        return True

    return False


# ============================================================
# Notifications
# ============================================================

def notify(message: str, level: str = "info") -> None:
    """Send a notification at the given level. See notify.sh for level meanings."""
    icon = {
        "info": "[dim]→[/dim]",
        "ok": "[green]✓[/green]",
        "warn": "[yellow]⚠[/yellow]",
        "alert": "[red]🛑[/red]",
        "celebrate": "[bold green]🎉[/bold green]",
    }.get(level, "→")
    console.print(f"{icon} [cyan]notify({level}):[/cyan] {message}")
    if NOTIFY_SCRIPT.exists():
        subprocess.run(
            ["bash", str(NOTIFY_SCRIPT), level, message],
            check=False,
        )


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
# Git checkpointing
# ============================================================

def git_commit(phase_id: str, message: str) -> bool:
    subprocess.run(["git", "add", "-A"], cwd=REPO_ROOT, check=True)
    diff = subprocess.run(
        ["git", "diff", "--cached", "--quiet"], cwd=REPO_ROOT
    )
    if diff.returncode == 0:
        return False  # nothing to commit
    subprocess.run(
        ["git", "commit", "-m", f"[autoport/{phase_id}] {message}"],
        cwd=REPO_ROOT, check=True,
    )
    return True


def git_push() -> None:
    subprocess.run(
        ["git", "push", "-u", "origin", "HEAD"],
        cwd=REPO_ROOT, check=False,
    )


# ============================================================
# Phase execution
# ============================================================

def run_phase(phase: dict, state: dict) -> str:
    """Returns 'pass', 'fail', or 'blocked'."""
    pid = phase["id"]
    log_dir = LOG_ROOT / pid
    log_dir.mkdir(parents=True, exist_ok=True)
    attempt = state["retries"].get(pid, 0) + 1
    attempt_log = log_dir / f"attempt-{attempt:02d}.jsonl"
    validator_log = log_dir / f"validator-{attempt:02d}.txt"

    prompt_path = AUTOPORT_DIR / phase["prompt"]
    validator = AUTOPORT_DIR / phase["validator"]

    if not prompt_path.exists():
        console.print(f"[red]Missing prompt: {prompt_path}[/red]")
        return "blocked"
    if not validator.exists():
        console.print(f"[red]Missing validator: {validator}[/red]")
        return "blocked"

    # Assemble prompt. "ultrathink" keyword reinforces max thinking even if
    # CLAUDE_EFFORT env isn't honored by current build.
    instructions = "ultrathink\n\n" + prompt_path.read_text()
    if attempt > 1:
        prev_validator = log_dir / f"validator-{attempt - 1:02d}.txt"
        if prev_validator.exists():
            tail = prev_validator.read_text()[-4000:]
            instructions += (
                f"\n\n## Previous attempt {attempt - 1} failed. Validator output (last 4KB):\n"
                f"\n```\n{tail}\n```\n\n"
                "Diagnose root cause and fix. Do not declare success until "
                f"`bash {phase['validator']}` exits 0."
            )

    console.print(Panel.fit(
        f"[bold cyan]Phase {pid}[/bold cyan] · attempt {attempt}/"
        f"{phase.get('max_retries', 3)} · model={MODEL} · effort={EFFORT}",
        border_style="cyan",
    ))

    env = os.environ.copy()
    env["CLAUDE_EFFORT"] = EFFORT
    env["AUTOPORT_PHASE_ID"] = pid
    env["AUTOPORT_PHASE_VALIDATOR"] = str(validator)

    cmd = [
        "claude",
        "-p", instructions,
        "--model", MODEL,
        "--max-turns", str(phase.get("max_turns", 150)),
        "--output-format", "stream-json",
        "--verbose",
        "--dangerously-skip-permissions",
    ]

    with attempt_log.open("w") as f:
        f.write(json.dumps({
            "event": "phase_start",
            "phase_id": pid,
            "attempt": attempt,
            "model": MODEL,
            "effort": EFFORT,
            "cmd": cmd,
            "started_at": datetime.now(timezone.utc).isoformat(),
        }) + "\n")
        f.flush()
        proc = subprocess.run(
            cmd, cwd=REPO_ROOT, stdout=f, stderr=subprocess.STDOUT, env=env
        )
        f.write(json.dumps({
            "event": "phase_end",
            "exit_code": proc.returncode,
            "ended_at": datetime.now(timezone.utc).isoformat(),
        }) + "\n")

    console.print(f"[dim]Claude Code exited {proc.returncode}. Running validator...[/dim]")

    # Ground-truth validator pass: this is what decides pass/fail, not Claude's word.
    with validator_log.open("w") as f:
        v = subprocess.run(
            ["bash", str(validator)],
            cwd=REPO_ROOT, stdout=f, stderr=subprocess.STDOUT,
        )

    state["retries"][pid] = attempt
    save_state(state)

    if v.returncode == 0:
        return "pass", "", []

    # Validator failed. Fingerprint the failure and check for stuck loops.
    failure_text = validator_log.read_text(errors='replace')
    fp, key_lines = fingerprint_validator_output(failure_text)

    state.setdefault("fingerprints", {}).setdefault(pid, []).append(fp)
    save_state(state)

    stuck, stuck_reason = check_stuck(state, pid, fp)
    if stuck:
        return "stuck", stuck_reason, key_lines

    if attempt >= phase.get("max_retries", 10):
        return "blocked", f"max_retries ({phase.get('max_retries', 10)}) exhausted", key_lines

    return "fail", "", key_lines


# ============================================================
# Main loop
# ============================================================

def main() -> int:
    if not MILESTONES_PATH.exists():
        console.print(f"[red]Missing {MILESTONES_PATH}[/red]")
        return 1
    if not CREDENTIALS_PATH.exists():
        console.print(
            f"[red]No Claude Code credentials at {CREDENTIALS_PATH}.\n"
            "Run 'claude' interactively once to complete OAuth.[/red]"
        )
        return 1

    plan = load_milestones()
    phases = plan["phases"]
    state = load_state()

    console.print(Panel.fit(
        f"[bold green]Autoport orchestrator starting[/bold green]\n"
        f"Repo: {REPO_ROOT}\n"
        f"Model: {MODEL} · Effort: {EFFORT}\n"
        f"Resuming at phase index {state['current_phase_idx']} / {len(phases)}\n"
        f"Completed: {len(state['completed'])} · "
        f"Blocked: {len(state['blocked'])}",
        border_style="green",
    ))

    while state["current_phase_idx"] < len(phases) and not HALT:
        phase = phases[state["current_phase_idx"]]
        pid = phase["id"]

        if pid in state["completed"]:
            state["current_phase_idx"] += 1
            save_state(state)
            continue

        if pid in state["blocked"]:
            console.print(
                f"[red]Phase {pid} is BLOCKED. Edit state.json to unblock "
                "(remove from 'blocked', clear 'retries' and 'fingerprints' for "
                "this phase).[/red]"
            )
            notify(
                f"Resumed but phase {pid} is still BLOCKED. Manual fix needed.",
                level="alert",
            )
            return 0

        if not wait_for_quota():
            return 0

        # Record phase start time (only on first attempt for this phase)
        if pid not in state["retries"]:
            state.setdefault("phase_started_at", {})[pid] = time.time()
            save_state(state)
            notify(
                f"▶ phase {pid} starting ({phase['name']})",
                level="info",
            )

        result, reason, key_lines = run_phase(phase, state)

        if result == "pass":
            elapsed = time.time() - state.get("phase_started_at", {}).get(pid, time.time())
            attempts = state["retries"].get(pid, 1)
            console.print(f"[bold green]✓ Phase {pid} validator passed[/bold green]")
            state["completed"].append(pid)
            state["current_phase_idx"] += 1
            save_state(state)
            if git_commit(pid, phase["name"]):
                console.print(f"[green]  committed[/green]")
                if plan.get("global", {}).get("git", {}).get("push_after_each_phase", True):
                    git_push()
                    console.print(f"[green]  pushed[/green]")
            # Rich completion notification
            remaining = len(phases) - state["current_phase_idx"]
            notify(
                f"✓ phase {pid} done in {format_duration(elapsed)} "
                f"({attempts} attempt{'s' if attempts != 1 else ''}). "
                f"{remaining} phase{'s' if remaining != 1 else ''} remaining.",
                level="ok",
            )

        elif result == "stuck":
            console.print(Panel.fit(
                f"[bold red]🛑 STUCK at phase {pid}[/bold red]\n\n"
                f"{reason}\n\n"
                f"[yellow]Recurring failure signature:[/yellow]\n"
                + "\n".join(f"  {ln}" for ln in key_lines[-10:]),
                border_style="red",
                title="HONEST STOP",
            ))
            state.setdefault("stuck_reasons", {})[pid] = reason
            state["blocked"].append(pid)
            save_state(state)
            short_lines = "\n".join(key_lines[-5:]) if key_lines else "(no error lines extracted)"
            notify(
                f"🛑 STUCK at {pid}: same failure 3x in a row. "
                f"Halting to save quota.\n\nRecurring error:\n{short_lines}",
                level="alert",
            )
            return 0

        elif result == "blocked":
            console.print(Panel.fit(
                f"[bold red]✗ Phase {pid} BLOCKED[/bold red]\n\n"
                f"{reason}\n\n"
                f"[yellow]Last failure lines:[/yellow]\n"
                + "\n".join(f"  {ln}" for ln in key_lines[-10:]),
                border_style="red",
            ))
            state["blocked"].append(pid)
            save_state(state)
            short_lines = "\n".join(key_lines[-5:]) if key_lines else ""
            notify(
                f"✗ BLOCKED at {pid}: {reason}.\n\nLast errors:\n{short_lines}",
                level="alert",
            )
            return 0

        else:  # fail, will retry
            attempt = state["retries"][pid]
            max_r = phase.get("max_retries", 10)
            fp_hist = state.get("fingerprints", {}).get(pid, [])
            unique_fps = len(set(fp_hist))
            console.print(
                f"[yellow]Phase {pid} attempt {attempt}/{max_r} failed. "
                f"Distinct failure modes so far: {unique_fps}. Retrying...[/yellow]"
            )
            # Heartbeat every 3rd attempt so user knows we're still working
            if attempt > 0 and attempt % 3 == 0:
                notify(
                    f"phase {pid}: attempt {attempt}/{max_r}, "
                    f"{unique_fps} distinct failure modes (still iterating)",
                    level="info",
                )
            time.sleep(30)

    if state["current_phase_idx"] >= len(phases):
        console.print("[bold green]🎉 All phases complete![/bold green]")
        total_elapsed = time.time() - datetime.fromisoformat(
            state.get("started_at", datetime.now(timezone.utc).isoformat())
        ).timestamp()
        notify(
            f"🎉 All {len(phases)} phases complete! Total time: {format_duration(total_elapsed)}",
            level="celebrate",
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
