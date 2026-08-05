#!/usr/bin/env python3
"""
OpenGOAL → Android autonomous orchestrator.

Hardcoded design choices (per project owner's preference):
- Model/effort come from the ACTIVE profile in model-profiles.json (single
  source of truth). Current (owner 2026-07-31): profile "opus48-xhigh" —
  * MANAGER (the phase session): claude-opus-4-8[1m] @ effort=xhigh — plans,
    judges, synthesizes, reviews. Per-phase override via `effort:` in
    milestones.yaml.
  * WORKERS (subagents via CLAUDE_CODE_SUBAGENT_MODEL): claude-opus-4-8[1m]
    @ xhigh for research / code generation / testing. Per-agent effort in
    .claude/agents/*.md frontmatter. Owner: "Opus 5 is lame as heck and
    dumber than Opus 4.8" — explicitly opus-4-8, NOT opus-5.
  (History: opus-4-8 max for every phase 2026-06-10→12; opus-4-7 through A32.)
- Thinking: 'ultrathink' keyword in prompts keeps planning depth at the
  manager level despite effort=high.
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

import argparse
import hashlib
import json
import os
import random
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

import requests
import yaml
from rich.console import Console
from rich.panel import Panel

# ============================================================
# Configuration — hardcoded per owner preference.
# ============================================================

# Model + effort come from the ACTIVE profile in .autoport/model-profiles.json
# (single source of truth — flip "active" there to switch the whole setup, then
# run .autoport/apply-model-profile.sh + relaunch). Hardcoded fallback below is
# used only if the JSON is missing/unreadable.
_PROFILE_PATH = Path(__file__).resolve().parent / "model-profiles.json"

def _load_model_profile() -> dict:
    fallback = {
        "manager_model": "claude-opus-4-8[1m]", "manager_effort": "xhigh",
        "worker_model": "claude-opus-4-8[1m]",
        "worker_efforts": {"autoport-researcher": "xhigh",
                           "autoport-implementer": "xhigh",
                           "autoport-tester": "xhigh"},
    }
    try:
        cfg = json.loads(_PROFILE_PATH.read_text())
        prof = cfg["profiles"][cfg["active"]]
        # minimal validation
        for k in ("manager_model", "manager_effort", "worker_model", "worker_efforts"):
            if k not in prof:
                raise KeyError(k)
        prof["_active_name"] = cfg["active"]
        return prof
    except Exception as e:  # noqa: BLE001
        fallback["_active_name"] = f"FALLBACK ({e})"
        return fallback

_PROFILE = _load_model_profile()
MODEL = _PROFILE["manager_model"]           # MANAGER model (orchestrator phase sessions)
EFFORT = _PROFILE["manager_effort"]         # manager default; per-phase `effort:` in milestones.yaml overrides
SUBAGENT_MODEL = _PROFILE["worker_model"]   # WORKER model for Task-tool subagents (CLAUDE_CODE_SUBAGENT_MODEL)
WORKER_EFFORTS = _PROFILE["worker_efforts"] # per-agent effort (also baked into .claude/agents/*.md frontmatter)
PROFILE_NAME = _PROFILE["_active_name"]

# Full YOLO mode: --dangerously-skip-permissions bypasses ALL permission
# prompts. No per-tool allowlist — Claude can use any tool freely.
# Safety net: per-phase git commits make any damage trivially revertable.

# Rate-limit thresholds (0-100 percent)
# OWNER POLICY 2026-06-12: NO pre-emptive stops. Run until the API actually
# rejects; then wait for the reset and resume automatically. Telemetry stays
# (it costs zero model tokens) but has no power to pause or kill.
SESSION_PAUSE_PCT = 100.0  # pre-phase pause ONLY if the API reports the window truly exhausted
WEEKLY_PAUSE_PCT = 999.0   # weekly gate DISABLED by owner 2026-06-11 (was 95.0)
HARD_KILL_PCT = 999.0      # mid-phase pre-emptive kill DISABLED by owner 2026-06-12 (was 98.0) — only a real API rejection stops a session
RESET_BUFFER_SECONDS = 90  # wait this long after the API-reported reset
POLL_INTERVAL_SECONDS = 300  # how often to re-check while sleeping (5 min)

# Hardened rate probe behavior
PROBE_PER_ATTEMPT_TIMEOUT = 8       # HTTP timeout per attempt (sec)
PROBE_DEADLINE_SEC = 30             # total wall-clock budget for a probe
PROBE_RETRY_DELAYS = (2, 4, 8, 16)  # backoff schedule (sec, jitter added)
PROBE_TTL_SEC = 60                  # in-memory cache TTL for successful probes

# Mid-phase probing triggers (inline, from the stream read loop)
PROBE_TOOL_CALLS_TRIGGER = 5  # probe every N tool_use events
PROBE_TIME_TRIGGER = 60.0     # AND at least this many seconds since last probe

# Live verbosity: how often to emit the periodic usage/progress tick line
LIVE_TICK_INTERVAL = 15.0  # seconds

# Stall detection for the read loop. Claude Code in -p mode sometimes keeps
# the process open after emitting `result` (terminal_reason=completed) when
# background TaskCreate tasks generated notifications; the orchestrator was
# then blocked on EOF that never arrived. We force-close in those cases.
STALL_POST_RESULT_SEC = 45.0   # idle gap after a result event before we force-close
STALL_HARD_SEC = 1800.0        # absolute max idle, regardless of session state
READ_POLL_SEC = 5.0            # select timeout slice (drives ticks + stall checks)

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
QUIET = False  # set from argparse; suppresses live event rendering

# Set inside run_phase while a claude subprocess is alive. The signal handler
# forwards SIGTERM to its process group so Ctrl-C kills Claude promptly
# instead of waiting up to 30 minutes for the current attempt to drain.
_CURRENT_CHILD: subprocess.Popen | None = None

# In-memory cache for the rate-limit probe. Keyed only by recency (TTL).
_PROBE_CACHE: tuple[float, "RateStatus"] | None = None


def _sig(_sig, _frame):
    global HALT
    console.print("\n[yellow]⚠ Received signal — finishing current step then halting.[/yellow]")
    HALT = True
    # Forward to the running child so claude exits promptly. We use the
    # process group (start_new_session=True in Popen) to cover claude's own
    # child processes too.
    child = _CURRENT_CHILD
    if child is not None and child.poll() is None:
        try:
            os.killpg(child.pid, signal.SIGTERM)
        except (ProcessLookupError, PermissionError):
            pass


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


_RATE_URL = "https://api.anthropic.com/api/oauth/usage"


def _parse_rate_payload(data: dict) -> RateStatus:
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


def fetch_rate_status(force: bool = False) -> RateStatus | None:
    """Probe /oauth/usage with retries, 429-aware backoff, and a 60s cache.

    Returns None only when the API is truly unreachable inside the deadline
    budget (no caller should treat None as 'all good' — the mid-phase logic
    falls back to a token-based estimate when this is None).
    """
    global _PROBE_CACHE
    now = time.monotonic()
    if not force and _PROBE_CACHE is not None and (now - _PROBE_CACHE[0]) < PROBE_TTL_SEC:
        return _PROBE_CACHE[1]

    token = get_oauth_token()
    if not token:
        return None

    headers = {
        "Authorization": f"Bearer {token}",
        "anthropic-beta": "oauth-2025-04-20",
    }
    deadline = now + PROBE_DEADLINE_SEC

    last_error: str = ""
    for i, base in enumerate(PROBE_RETRY_DELAYS):
        if time.monotonic() >= deadline:
            break
        try:
            r = requests.get(_RATE_URL, headers=headers, timeout=PROBE_PER_ATTEMPT_TIMEOUT)
            if r.status_code == 429:
                ra_hdr = r.headers.get("Retry-After")
                try:
                    wait = float(ra_hdr) if ra_hdr else float(base)
                except ValueError:
                    wait = float(base)
                wait = min(wait, max(0.0, deadline - time.monotonic()))
                if wait <= 0 or i == len(PROBE_RETRY_DELAYS) - 1:
                    last_error = f"429 (Retry-After={ra_hdr or 'n/a'})"
                    break
                console.print(f"[dim]rate probe 429; sleeping {wait:.1f}s before retry[/dim]")
                time.sleep(wait + random.uniform(0, 0.5))
                continue
            r.raise_for_status()
            status = _parse_rate_payload(r.json())
            _PROBE_CACHE = (now, status)
            return status
        except (requests.Timeout, requests.ConnectionError) as e:
            last_error = f"{type(e).__name__}"
            if i == len(PROBE_RETRY_DELAYS) - 1:
                break
            backoff = base + random.uniform(0, base * 0.25)
            if time.monotonic() + backoff > deadline:
                break
            console.print(f"[dim]rate probe {last_error}; retry {i + 1}/{len(PROBE_RETRY_DELAYS)} in {backoff:.1f}s[/dim]")
            time.sleep(backoff)
            continue
        except (ValueError, KeyError) as e:
            last_error = f"bad-payload:{type(e).__name__}"
            break
        except Exception as e:
            last_error = f"{type(e).__name__}: {e}"
            break

    console.print(f"[yellow]Rate-limit probe failed after retries: {last_error or 'budget exhausted'}[/yellow]")
    return None


# ============================================================
# Live verbosity — smart-compact stream-json renderer + inline
# mid-phase rate probing.
# ============================================================

@dataclass
class PrettyState:
    """Per-phase live-rendering and probing state.

    Threaded between every event read off Claude's stdout. The orchestrator
    must never raise out of the read loop on account of this state; the
    printer wraps every render in try/except.
    """
    t0: float                                # phase start (monotonic)
    session_id: str = ""
    tool_calls: int = 0                      # cumulative tool_use events
    tool_calls_since_probe: int = 0
    tokens_in: int = 0                       # cumulative input tokens
    tokens_out: int = 0                      # cumulative output tokens
    cache_read: int = 0                      # cumulative cache-read tokens
    cache_creation: int = 0
    last_tick_at: float = 0.0
    last_probe_at: float = 0.0
    last_session_pct: float | None = None    # last *probed* (authoritative)
    # In-subprocess probes for slope-based extrapolation. Each entry is
    # (probed_pct, total_in_out_tokens_at_probe_time). Single-anchor
    # extrapolation was wildly wrong: it assumes the session started at 0%
    # when this claude subprocess began, but the 5-hour window accumulates
    # across many subprocesses (including the orchestrator's own setup).
    # Slope is meaningful only between two probes inside the SAME
    # subprocess, where token deltas correspond to real session-pct deltas.
    probes: list[tuple[float, int]] = field(default_factory=list)
    probe_failures: int = 0                  # consecutive 429/timeout count; drives backoff
    last_claude_rate_status: str = ""        # from rate_limit_event payloads
    tool_use_names: dict[str, str] = field(default_factory=dict)  # id -> name
    kill_pending: bool = False               # set True when threshold crossed
    init_printed: bool = False
    dirty_since_tick: bool = False           # gate periodic tick on activity
    result_seen: bool = False                # at least one result/* event arrived


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
    # Bash is special-cased so the shell command shows up.
    if tool_name == "Bash":
        return str(tool_input.get("command", ""))
    # Common conventions: file_path / path / pattern / query / url / command
    for key in ("file_path", "path", "pattern", "query", "url", "command",
                "subject", "description", "old_string"):
        if key in tool_input and tool_input[key]:
            return str(tool_input[key])
    # Fallback: first non-empty value
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


def _current_pct(state: PrettyState) -> tuple[float | None, bool]:
    """Return (pct, is_estimated_from_slope). pct is None if we've never seen a probe.

    Rules — designed to avoid the phantom-105% bug:
      - 0 in-subprocess probes: fall back to the (possibly cache-seeded)
        last probed value. Mark as NOT estimated — it's the last actual
        reading we have, not an extrapolation.
      - 1 in-subprocess probe: same as above. We don't have a slope yet,
        so any extrapolation would be inventing one (the prior formula's
        bug was assuming the session started at 0% when this subprocess
        began — wrong, because the 5-hour window accumulates across
        subprocesses including the orchestrator's own setup).
      - 2+ probes: compute the per-token slope between the last two
        probes (real, in-subprocess data points), then extrapolate
        forward from the latest. Marked estimated.
    """
    now_tokens = state.tokens_in + state.tokens_out
    if len(state.probes) >= 2:
        p1_pct, p1_tok = state.probes[-2]
        p2_pct, p2_tok = state.probes[-1]
        if p2_tok > p1_tok and now_tokens > p2_tok:
            slope = (p2_pct - p1_pct) / (p2_tok - p1_tok)
            est = p2_pct + (now_tokens - p2_tok) * slope
            # Never report below the last actual probe (slope can be ≤0 if
            # the session reset between probes; defend against weirdness).
            return (max(est, p2_pct), True)
        # No usable token delta — just report the last probe value.
        return (p2_pct, False)
    if state.last_session_pct is not None:
        return (state.last_session_pct, False)
    return (None, False)


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
    elapsed = now - state.t0
    mins, secs = divmod(int(elapsed), 60)
    pct, estimated = _current_pct(state)
    pct_str = "?" if pct is None else f"{'~' if estimated else ''}{pct:.0f}%"
    tokens = state.tokens_in + state.tokens_out
    console.print(
        f"[dim][{mins}m{secs:02d}s · {state.tool_calls} calls · "
        f"{_human_tokens(tokens)} tok · session {pct_str}][/dim]"
    )


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
                    console.print(
                        f"[cyan]▶ claude session {_short_id(state.session_id)} · "
                        f"model={ev.get('model', '?')}[/cyan]"
                    )
            elif sub == "api_retry":
                if not QUIET:
                    n = ev.get("attempt"); mx = ev.get("max_retries")
                    delay = ev.get("retry_delay_ms", 0)
                    err = ev.get("error", "?")
                    console.print(f"[yellow]· api_retry {n}/{mx} (delay {delay/1000:.1f}s, {err})[/yellow]")
            # task_started, task_notification, hook_started/response: ignore
            return

        if t == "rate_limit_event":
            info = ev.get("rate_limit_info", {}) or {}
            if info.get("rateLimitType") == "five_hour":
                state.last_claude_rate_status = str(info.get("status", ""))
                # OWNER POLICY 2026-06-12: only a REAL rejection stops the
                # session. "allowed_warning" (fires from ~90%) must NOT kill —
                # that wasted two healthy F1e sessions on 2026-06-12.
                if state.last_claude_rate_status in ("rejected", "blocked", "exceeded"):
                    state.kill_pending = True
                    if not QUIET:
                        console.print(
                            f"[red]⚠ claude rate_limit_event: {state.last_claude_rate_status} (real rejection — stopping)[/red]"
                        )
                elif state.last_claude_rate_status not in ("allowed", ""):
                    if not QUIET:
                        console.print(
                            f"[dim]· rate_limit_event: {state.last_claude_rate_status} (warning only — continuing)[/dim]"
                        )
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
                    state.tool_calls_since_probe += 1
                    state.dirty_since_tick = True
                    name = c.get("name", "?")
                    state.tool_use_names[c.get("id", "")] = name
                    if not QUIET:
                        arg = _truncate(_primary_arg(name, c.get("input", {})), 100)
                        console.print(f"[bold]🔧 {name}[/bold] [dim]{arg}[/dim]")
                elif ctype == "text":
                    text = (c.get("text") or "").strip()
                    if text and not QUIET:
                        # First sentence, max 120 chars.
                        first = re.split(r'(?<=[.!?])\s', text, maxsplit=1)[0]
                        console.print(f"[dim]{_truncate(first, 120)}[/dim]")
                # thinking: silent (already costs tokens; no value to display)
            return

        if t == "user":
            msg = ev.get("message", {}) or {}
            for c in msg.get("content", []) or []:
                if c.get("type") != "tool_result":
                    continue
                is_err = bool(c.get("is_error"))
                content = c.get("content", "")
                if isinstance(content, list):
                    parts = []
                    for blk in content:
                        if isinstance(blk, dict) and blk.get("type") == "text":
                            parts.append(blk.get("text", ""))
                    content = "".join(parts) if parts else str(content)
                content = str(content)
                if not QUIET and is_err:
                    head = _truncate(content, 100)
                    console.print(f"   [red]↳ ERROR:[/red] [dim]{head}[/dim]")
                # Successful tool_results are silent — they add no signal
                # beyond what the next assistant turn shows. Byte counts and
                # `ok` markers were pure clutter (per user feedback).
            return

        if t == "result":
            state.result_seen = True
            usage = ev.get("usage", {}) or {}
            _accumulate_usage(state, usage)
            if not QUIET:
                dur_ms = ev.get("duration_ms", 0)
                cost = ev.get("total_cost_usd", 0) or 0
                turns = ev.get("num_turns", 0)
                err = ev.get("is_error")
                head = "[red]✗ result[/red]" if err else "[green]✓ result[/green]"
                console.print(
                    f"{head} [dim]turns={turns} · {dur_ms/1000:.1f}s · "
                    f"in {_human_tokens(state.tokens_in)} out {_human_tokens(state.tokens_out)} "
                    f"cache_r {_human_tokens(state.cache_read)} · ${cost:.3f}[/dim]"
                )
            return

        # Anything else: silent (raw line still goes to JSONL log).
    except Exception as e:
        # Printer must NEVER kill the orchestrator.
        if not QUIET:
            console.print(f"[dim]· print-err {type(e).__name__}[/dim]")
    finally:
        _maybe_emit_tick(state)


def maybe_probe_inline(state: PrettyState) -> None:
    """If trigger conditions are met, probe the rate API and update state.

    On success: append (pct, tokens) to state.probes; with 2+ probes,
    _current_pct() can slope-extrapolate honestly.

    On failure (429, network blip): exponential back-off so we don't burn
    the rate-probe endpoint when it's throttling us. Notably, we DO NOT
    trigger a hard-kill from a single-probe extrapolation — that's the
    bug that caused the phantom 105%. We only kill if the actual probed
    value crosses HARD_KILL_PCT, or if a 2+ probe slope-extrapolation
    crosses it (slope-extrapolation has real data behind it).
    """
    now = time.monotonic()
    if state.tool_calls_since_probe < PROBE_TOOL_CALLS_TRIGGER:
        return
    # Exponential back-off on consecutive failures: 60s → 120s → 240s →
    # 480s, capped at 300s. Doubles on each failure; resets on success.
    min_interval = min(PROBE_TIME_TRIGGER * (2 ** state.probe_failures), 300.0)
    if (now - state.last_probe_at) < min_interval:
        return

    state.last_probe_at = now
    state.tool_calls_since_probe = 0

    st = fetch_rate_status()
    if st is not None:
        state.probe_failures = 0
        prev_pct = state.last_session_pct
        state.last_session_pct = st.session_pct
        # Append to the slope-extrapolation window. Use total in+out
        # tokens at probe time as the x-axis. Cap memory at last 5.
        state.probes.append((st.session_pct, state.tokens_in + state.tokens_out))
        state.probes = state.probes[-5:]

        if not QUIET:
            arrow = ""
            if prev_pct is not None:
                delta = st.session_pct - prev_pct
                arrow = f" ({'+' if delta >= 0 else ''}{delta:.1f})"
            console.print(
                f"[dim]· probed session={st.session_pct:.1f}%{arrow} "
                f"weekly={st.weekly_pct:.1f}%[/dim]"
            )

        # Kill on the *probed* value crossing threshold. Always reliable.
        if st.session_pct >= HARD_KILL_PCT:
            state.kill_pending = True
        return

    # Probe failed.
    state.probe_failures += 1
    if not QUIET:
        next_interval = min(PROBE_TIME_TRIGGER * (2 ** state.probe_failures), 300.0)
        console.print(
            f"[dim]· rate probe failed ({state.probe_failures}x consecutive); "
            f"next attempt in ≥{next_interval:.0f}s[/dim]"
        )

    # Only hard-kill on extrapolation when we have ≥2 in-subprocess probes
    # (a real slope, not a single-anchor invented one). Otherwise the
    # phantom-105% bug returns.
    if len(state.probes) >= 2:
        pct, est = _current_pct(state)
        if pct is not None and est and pct >= HARD_KILL_PCT:
            state.kill_pending = True


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
    # ntfy.sh / Slack push dropped by owner 2026-06-13 — local console line only.
    console.print(f"{icon} [cyan]notify({level}):[/cyan] {message}")


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
# Close-gate — defense-in-depth against false-greens
# ============================================================
#
# Owner mandate (2026-06-30): per-phase validators kept FALSE-GREENING (marking
# work "done" that wasn't) — collision/jungle/flicker all slipped a lax validator
# and only the owner's eye caught them. This central gate runs AFTER a phase's own
# validator exits 0 and re-checks the three false-green patterns we actually hit,
# so NO phase can close on them regardless of how weak its own validator is:
#   1. validator passes on ZERO code change (a stub / no-op phase),
#   2. validator passes while the DEVICE runs a stale/mixed build,
#   3. validator passes but the OWNER's play-test (final gate) hasn't happened.
# Each gate is opt-in/opt-out via milestones.yaml phase fields.

def _supervisor_anchor(pid: str | None = None) -> str:
    """The 'no new game fix' anchor the per-phase validators already use.
    Phase-aware: mid-phase [autoport/supervisor] journal commits (storm bookkeeping,
    profile flips) must NOT advance the anchor past the phase's own fix commits —
    Gcrash-blueeco 2026-07-02: anchor 5cb0642ee postdated the real fix commits
    (c91304925/0943a586d) and GATE 1 false-negatived a device-proven fix. With a
    pid, the anchor is the last supervisor commit BEFORE the phase's first commit;
    without one (or with no phase commits yet), the most recent supervisor commit.
    Falls back to HEAD~1."""
    def _log(*extra: str) -> list[str]:
        r = subprocess.run(["git", "log", "--format=%H", *extra],
                           cwd=REPO_ROOT, capture_output=True, text=True)
        return [l for l in r.stdout.splitlines() if l.strip()]

    if pid:
        phase_commits = _log("--grep", rf"\[autoport/{re.escape(pid)}\]")
        if phase_commits:
            pre = _log("--grep", r"\[autoport/supervisor\]", f"{phase_commits[-1]}^")
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
    Fail-OPEN on adb infra errors (don't wedge the loop; GATE 3 owner is the backstop).

    Launch goes through the RESOLVED launcher activity, never MainActivity directly:
    MainActivity BYPASSES LoaderActivity, the sole writer of the pack stamps, so a
    direct launch unpacks nothing and mis-reports any phase that moves the packs.

    Two evidence routes:
      A. LOG route (primary, unchanged) — logcat shows master-mode=game / A35-RENDER.
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
                            "the game assets / fix the bundle before this phase can close.")
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


def close_gate(phase: dict, validator_log: Path) -> tuple[str, str]:
    """Run after a phase's validator exits 0. Returns (status, reason):
      ("pass", "")            -> all gates clear; the phase may complete
      ("fail", reason)        -> a FIXABLE gate failed; retry + feed reason back
      ("awaiting-owner", "")  -> validator+gates clear, owner play-test pending
    """
    pid = phase["id"]

    # GATE 1 — real translation-layer code change (anti-stub false-green).
    # F1b was marked done with ZERO code. Require a real change since the
    # supervisor anchor in a port/translation dir, unless the phase declares
    # `no_code: true` (pure asset/packaging/investigation phases).
    # Re-read the flag from milestones.yaml on DISK: the in-memory phase dict
    # is loaded once at startup, so a worker that (per this gate's own advice)
    # sets `no_code: true` mid-run would otherwise be refused until a manual
    # orchestrator relaunch (Grecharged-grass-object-clip 2026-07-13: attempt 2
    # declared the flag in-yaml and still burned a retry on the stale dict).
    no_code = phase.get("no_code", False)
    try:
        for p in load_milestones().get("phases", []):
            if p.get("id") == pid:
                no_code = p.get("no_code", no_code)
                break
    except Exception:  # noqa: BLE001 — fail-safe: keep the in-memory value
        pass
    if not no_code:
        anchor = _supervisor_anchor(pid)
        paths = ["game/", "android/", "goalc/", "goal_src/"]
        committed = subprocess.run(
            ["git", "diff", "--name-only", anchor, "--", *paths],
            cwd=REPO_ROOT, capture_output=True, text=True,
        ).stdout.splitlines()
        dirty = subprocess.run(
            ["git", "status", "--porcelain", "--", *paths],
            cwd=REPO_ROOT, capture_output=True, text=True,
        ).stdout.splitlines()
        # x86 emitter is LOCKED (our-x86 must == original-x86) — a change there
        # is not a legitimate port fix, so it doesn't count toward "real work".
        real = [f for f in (committed + dirty)
                if f.strip() and "IGenX86_64" not in f]
        if not real:
            return ("fail",
                    "CLOSE-GATE/code: validator exit 0 but NO translation-layer code "
                    "changed since the supervisor anchor — refusing the false-green. "
                    "A real fix must touch game/ android/ goalc/ goal_src/ (not the "
                    "locked x86 emitter). If this phase legitimately ships no code, "
                    "set `no_code: true` in milestones.yaml.")

    # GATE 2 — device runs the fresh, CONSISTENT build (anti stale/mixed-build).
    # The validator can pass while the phone still runs an old libgk, or a MIXED
    # build (fresh CGOs + stale libgk, or vice-versa — exactly the 2026-06-30
    # flicker incident). deploy_verify proves build==APK==device for libgk;
    # phases that touch CGOs should also assert CGO-consistency in their own
    # validator, but this gate at minimum stops the stale-.so false-green.
    if phase.get("device", False):
        # Re-read device_serial from milestones.yaml on DISK, for the same reason
        # GATE 1 re-reads no_code: the in-memory phase dict is loaded once at
        # startup, so a phase re-pointed at another phone mid-run would keep being
        # verified against the OLD default and could never close. This bit
        # Grecharged-loader-packfix 2026-07-29: the work was on the owner's Honor
        # while the gate kept probing the (unplugged) Redmi and reported the
        # misleading "package not installed" as if it were a stale build.
        serial = phase.get("device_serial")
        try:
            for p in load_milestones().get("phases", []):
                if p.get("id") == pid:
                    serial = p.get("device_serial", serial)
                    break
        except Exception:  # noqa: BLE001 — fail-safe: keep the in-memory value
            pass
        serial = serial or os.environ.get("ANDROID_SERIAL", "eae4df44")
        # Game-aware deploy gate: a jak2/jak3 phase must verify against ITS package +
        # APK, not the jak1 default. Otherwise the fresh SHARED libgk never matches the
        # un-rebuilt jak1 APK -> deploy_verify reports STALE and the gate can NEVER
        # close for a jak2 phase (2026-07-09 Gjak2-polish: attempts 1+2 stuck here).
        game = phase.get("game") or ("jak2" if "jak2" in pid.lower()
                                     else "jak3" if "jak3" in pid.lower() else "jak1")
        dv = AUTOPORT_DIR / "lib" / "deploy_verify.sh"
        if dv.exists():
            r = subprocess.run(["bash", str(dv), serial, game],
                               cwd=REPO_ROOT, capture_output=True, text=True)
            if r.returncode != 0:
                tail = "\n".join((r.stdout + r.stderr).strip().splitlines()[-4:])
                return ("fail",
                        "CLOSE-GATE/deploy: deploy_verify FAILED — the device is NOT "
                        "provably running the fresh HEAD build (stale or mixed "
                        "CGO/libgk). Rebuild a CONSISTENT set (CGOs + libgk together) "
                        "and redeploy before this phase can close.\n" + tail)
        # deploy_verify only proves the libgk sha chain — also prove the app BOOTS
        # (catches 'Setup failed'/non-booting builds deploy_verify can't see).
        pkg = phase.get("device_pkg") or f"org.opengoal.gk.{game}"
        booted, why = _device_boot_check(serial, pkg)
        if not booted:
            return ("fail", why)

    # GATE 3 — owner play-test is the FINAL gate (the owner's eye overrides any
    # synthetic pass; the collision fix false-greened a validator twice before
    # the owner confirmed it). For `owner_verify: true` phases, validator pass is
    # NOT completion: require an owner-OK token the supervisor drops after the
    # owner play-tests (touch .autoport/owner-ok/<pid>).
    if phase.get("owner_verify", False):
        token = AUTOPORT_DIR / "owner-ok" / pid
        if not token.exists():
            return ("awaiting-owner", "")

    return ("pass", "")


# ============================================================
# Phase execution
# ============================================================

def run_phase(phase: dict, state: dict) -> tuple[str, str, list[str]]:
    """Run one phase attempt; return (result, reason, key_lines).

    result is one of: 'pass', 'fail', 'blocked', 'stuck', 'rate-interrupted'.
    'rate-interrupted' means we killed claude because session usage crossed
    HARD_KILL_PCT mid-phase. The caller must wait_for_quota() and retry the
    phase from scratch without incrementing retries or recording a fingerprint.
    """
    global _CURRENT_CHILD
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
        return "blocked", "missing prompt", []
    if not validator.exists():
        console.print(f"[red]Missing validator: {validator}[/red]")
        return "blocked", "missing validator", []

    # Per-phase effort override (milestones.yaml `effort:`), else manager default.
    effort = phase.get("effort", EFFORT)

    # Assemble prompt. "ultrathink" keyword reinforces deep thinking even if
    # CLAUDE_EFFORT env isn't honored by current build. The WORK-ECONOMY
    # preamble enforces the tiered manager/worker architecture (owner
    # 2026-06-12): the fable manager must delegate bulk execution to
    # opus-4-8 subagents instead of burning manager-effort tokens on it.
    _we = WORKER_EFFORTS
    delegation_preamble = (
        "## WORK ECONOMY (mandatory — manager/worker delegation)\n"
        f"You are the MANAGER ({MODEL}, effort={effort}): plan, decide, judge,\n"
        "synthesize, review. Delegate bulk execution to subagents via the Task\n"
        f"tool — they run on {SUBAGENT_MODEL} (CLAUDE_CODE_SUBAGENT_MODEL):\n"
        f"- `autoport-researcher` (effort {_we.get('autoport-researcher','high')}): "
        "code/disassembly/log/oracle scans, symbol hunts, large-file analysis. Read-only.\n"
        f"- `autoport-implementer` (effort {_we.get('autoport-implementer','medium')}): "
        "mechanical code edits to YOUR exact spec (files, lines, precise semantics).\n"
        f"- `autoport-tester` (effort {_we.get('autoport-tester','medium')}): "
        "builds, qemu runs, device runs, log harvesting, screencaps.\n"
        "Keep main-thread tool calls for decisions, small precise edits, and\n"
        "VERIFYING subagent claims (read their diffs/logs yourself — trust but\n"
        "verify). Never delegate understanding: subagent prompts must contain\n"
        "exact file paths, line numbers, commands, and expected outputs.\n"
        "Parallelize independent subagent runs in one message.\n\n"
        "## BUILD & DELIVERY EFFICIENCY (owner standing order 2026-08-06)\n"
        "The owner: 'c'est pas possible sur une journee d'avoir quasi la moitie du\n"
        "temps gaspillee en builds'. ALWAYS pick the CHEAPEST path that proves the\n"
        "change, and actively look for faster ones:\n"
        "- DATA-only change (params/config read at runtime) => NO build. Push the\n"
        "  file to the device / edit in place, relaunch. (e.g. physics_chains.txt\n"
        "  lives at files/custom/jak1/recharged_assets/ on device.)\n"
        "- GOAL-only change => make-group iso + gradle repack. NO NDK/libgk rebuild.\n"
        "- C++ change => rebuild, but INCREMENTAL: `cmake --build <dir> --target gk`.\n"
        "  NEVER re-run `cmake -B <dir>` (reconfigure) unless a build OPTION changed:\n"
        "  it invalidates the whole tree (1300+ objects, incl. unrelated jak2 mips2c).\n"
        "- Start the ANDROID build as soon as the code is final; do not serialize it\n"
        "  behind long x86 runtime tests that could run after/in parallel.\n"
        "- Batch changes: land ALL edits of a cycle before building, never build per edit.\n"
        "- Prefer runtime-tunable DATA over hardcoded constants precisely so future\n"
        "  iterations need no build at all — and make such data overridable from the\n"
        "  EXTERNAL asset pack so the owner re-downloads KB, not a 581MB APK.\n"
        "State in your report which tier you used and why.\n\n"
        "## PROOF ECONOMY (owner standing order 2026-08-06)\n"
        "Owner: efficiency on builds AND on proof collection — but it must still\n"
        "work, no breakage, no false greens. So: prove ONLY what would break\n"
        "SILENTLY, with the CHEAPEST instrument that already exists:\n"
        "- MUST prove (cheap, non-negotiable): no crash, no regression of a\n"
        "  locked-in acquis, the feature is actually ACTIVE (a counter/log showing\n"
        "  the code path ran on device), deploy_verify freshness.\n"
        "- MUST NOT build: elaborate new proof harnesses, multi-leg device\n"
        "  campaigns, or any visual-measurement campaign (permanently banned).\n"
        "  Reuse existing counters/logs; one short device run is enough.\n"
        "- QUALITY/aesthetics are judged by the OWNER, never by you: ship the build\n"
        "  and let him look. Your report lists what HE must test.\n"
        "Budget guide: proof runs are MINUTES, not hours. If proving costs more\n"
        "than the fix, ship with an honest 'not proven: X' line instead of\n"
        "burning the cycle on instrumentation.\n\n"
    )
    instructions = "ultrathink\n\n" + delegation_preamble + prompt_path.read_text()
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
        f"{phase.get('max_retries', 3)} · model={MODEL} · effort={effort} · "
        f"workers={SUBAGENT_MODEL}",
        border_style="cyan",
    ))

    env = os.environ.copy()
    env["CLAUDE_EFFORT"] = effort
    env["CLAUDE_CODE_SUBAGENT_MODEL"] = SUBAGENT_MODEL
    env["AUTOPORT_PHASE_ID"] = pid
    env["AUTOPORT_PHASE_VALIDATOR"] = str(validator)

    # `--effort max` is the CLI flag form of the CLAUDE_EFFORT env var set
    # below. Recent Claude Code builds honor the flag; older ones fall back
    # to the env. We pass both. The 'ultrathink' keyword prepended into
    # `instructions` reinforces max thinking at the prompt level too, which
    # works regardless of build version. See REDESIGN.md §5 on why
    # ultrathink is mandatory for every phase.
    cmd = [
        "claude",
        "-p", instructions,
        "--model", MODEL,
        "--effort", effort,
        "--max-turns", str(phase.get("max_turns", 150)),
        "--output-format", "stream-json",
        "--verbose",
        "--dangerously-skip-permissions",
    ]

    pstate = PrettyState(t0=time.monotonic())
    # Seed last_session_pct from the cache so the first live tick shows a
    # value instead of "?". Do NOT push into pstate.probes — that list is
    # exclusively for in-subprocess data points used to compute a
    # token-vs-pct slope. The cache entry has the right pct but the wrong
    # token reference frame (it predates this subprocess), so feeding it
    # to the slope estimator would resurrect the phantom-105% bug.
    if _PROBE_CACHE is not None:
        cache_age = time.monotonic() - _PROBE_CACHE[0]
        if cache_age < PROBE_TTL_SEC:
            pstate.last_session_pct = _PROBE_CACHE[1].session_pct
            pstate.last_probe_at = _PROBE_CACHE[0]

    rate_interrupted = False
    rc = -1
    with attempt_log.open("w") as f:
        f.write(json.dumps({
            "event": "phase_start",
            "phase_id": pid,
            "attempt": attempt,
            "model": MODEL,
            "effort": effort,
            "subagent_model": SUBAGENT_MODEL,
            "cmd": cmd,
            "started_at": datetime.now(timezone.utc).isoformat(),
        }) + "\n")
        f.flush()

        proc = subprocess.Popen(
            cmd,
            cwd=REPO_ROOT,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            bufsize=1,
            text=True,
            start_new_session=True,
        )
        _CURRENT_CHILD = proc

        stall_forced = False
        last_event_at = time.monotonic()
        try:
            stdout_fd = proc.stdout
            while True:
                # Wait for stdout to be readable, or a 5s tick. The tick lets
                # us check for stalls, emit the periodic usage line, and
                # detect a child that already exited without us blocking
                # forever on a never-arriving EOF.
                try:
                    ready, _, _ = select.select([stdout_fd], [], [], READ_POLL_SEC)
                except (OSError, ValueError):
                    # stdout was closed underneath us.
                    break

                if not ready:
                    idle = time.monotonic() - last_event_at
                    # Process is already gone — close out cleanly.
                    if proc.poll() is not None:
                        break
                    # claude said `result` but won't actually exit (we saw
                    # this with TaskCreate task-notification re-engagements:
                    # claude keeps the process open in -p mode and never
                    # closes its stdout). Force the issue.
                    if pstate.result_seen and idle >= STALL_POST_RESULT_SEC:
                        console.print(
                            f"[yellow]· claude emitted result but hasn't exited "
                            f"({idle:.0f}s idle); forcing close[/yellow]"
                        )
                        stall_forced = True
                        try:
                            os.killpg(proc.pid, signal.SIGTERM)
                        except (ProcessLookupError, PermissionError):
                            pass
                        break
                    # Defensive absolute cap: even without a result, we
                    # should never wait silently forever.
                    if idle >= STALL_HARD_SEC:
                        console.print(
                            f"[red]· no output from claude for {idle:.0f}s; killing[/red]"
                        )
                        stall_forced = True
                        try:
                            os.killpg(proc.pid, signal.SIGTERM)
                        except (ProcessLookupError, PermissionError):
                            pass
                        break
                    # Keep the live tick alive during quiet stretches.
                    _maybe_emit_tick(pstate)
                    continue

                raw_line = stdout_fd.readline()
                if not raw_line:
                    # EOF.
                    break
                last_event_at = time.monotonic()

                # Forensic log gets every byte unchanged.
                f.write(raw_line)
                f.flush()

                line = raw_line.rstrip("\n")
                if not line.strip():
                    continue

                # Parse + render.
                ev: dict | None = None
                try:
                    ev = json.loads(line)
                except json.JSONDecodeError:
                    if not QUIET:
                        console.print(f"[dim]{_truncate(line, 200)}[/dim]")
                    continue

                pretty_print_event(ev, pstate)
                maybe_probe_inline(pstate)

                # Kill at a safe point: just after a tool_result drained.
                # Killing mid-tool-call is what we're explicitly avoiding.
                if pstate.kill_pending and ev.get("type") == "user":
                    pct, est = _current_pct(pstate)
                    pct_str = "?" if pct is None else f"{'~' if est else ''}{pct:.1f}%"
                    console.print(
                        f"[bold red]🛑 session usage at {pct_str} — "
                        f"hard-killing claude to avoid mid-tool-call cutoff[/bold red]"
                    )
                    rate_interrupted = True
                    try:
                        os.killpg(proc.pid, signal.SIGTERM)
                    except (ProcessLookupError, PermissionError):
                        pass
                    break
        except KeyboardInterrupt:
            try:
                os.killpg(proc.pid, signal.SIGTERM)
            except (ProcessLookupError, PermissionError):
                pass
            raise
        finally:
            # Drain any remaining output so the pipe doesn't deadlock at exit.
            if rate_interrupted:
                try:
                    rest = proc.stdout.read()
                    if rest:
                        f.write(rest); f.flush()
                except Exception:
                    pass

            try:
                rc = proc.wait(timeout=15 if rate_interrupted else None)
            except subprocess.TimeoutExpired:
                try:
                    os.killpg(proc.pid, signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                rc = proc.wait()
            _CURRENT_CHILD = None

        f.write(json.dumps({
            "event": "phase_end",
            "exit_code": rc,
            "ended_at": datetime.now(timezone.utc).isoformat(),
            "rate_interrupted": rate_interrupted,
            "stall_forced": stall_forced,
            "tool_calls": pstate.tool_calls,
            "tokens_in": pstate.tokens_in,
            "tokens_out": pstate.tokens_out,
            "cache_read": pstate.cache_read,
        }) + "\n")

    # FATAL CONFIG detection (2026-06-13): a 0-work exit caused by a bad model
    # / auth / request error must NOT be mistaken for a rate limit — that loops
    # forever (fable-5[1m] 404 spun the loop every 5 min). Scan the attempt log
    # for a non-429 API error or the model-unavailable signature and HALT loudly.
    if not rate_interrupted and rc != 0 \
            and (pstate.tokens_in + pstate.tokens_out) == 0 \
            and pstate.tool_calls == 0:
        try:
            tail = attempt_log.read_text(errors="replace")[-6000:]
        except Exception:
            tail = ""
        fatal = (
            "may not exist or you may not have access" in tail
            or '"api_error_status":401' in tail or '"api_error_status":403' in tail
            or '"api_error_status":404' in tail
        )
        if fatal:
            msg = "model/auth/request error (non-rate-limit) — check MODEL / credentials"
            if "may not exist or you may not have access" in tail:
                msg = f"model '{MODEL}' unavailable (API 404) — update MODEL in orchestrator.py"
            notify(f"🛑 phase {pid} HALT: {msg}", level="alert")
            return "blocked", msg, []

    # NO-START detection (owner 2026-06-12): a session that exits having done
    # essentially NOTHING (no tokens, no tool calls) did not fail the phase —
    # it was refused at the door (hard rate limit / "out of extra usage").
    # Treating it as a failed attempt is what falsely blocked F1d (two 0-turn
    # no-ops consumed retries and faked a 3x-identical-failure fingerprint).
    # Back off in place, then re-enter the phase without consuming anything.
    if not rate_interrupted and rc != 0 \
            and (pstate.tokens_in + pstate.tokens_out) == 0 \
            and pstate.tool_calls == 0:
        notify(
            f"⏳ phase {pid}: claude exited {rc} with ZERO work done — "
            "hard rate limit at the door. Backing off 5 min, then retrying "
            f"(attempt {attempt} NOT counted).",
            level="warn",
        )
        time.sleep(300)
        rate_interrupted = True

    if rate_interrupted:
        pct, est = _current_pct(pstate)
        pct_str = "?" if pct is None else f"{'~' if est else ''}{pct:.1f}%"
        state.setdefault("rate_interrupts", {})
        state["rate_interrupts"][pid] = state["rate_interrupts"].get(pid, 0) + 1
        save_state(state)
        notify(
            f"⏸ phase {pid} rate-interrupted at session {pct_str} "
            f"(attempt {attempt} not counted; will retry after reset)",
            level="alert",
        )
        if state["rate_interrupts"][pid] > 3:
            notify(
                f"⚠ phase {pid} has rate-interrupted {state['rate_interrupts'][pid]} times. "
                f"Quota may be structurally too low for this phase.",
                level="warn",
            )
        # Reason carries the percentage so the caller can log it; no key_lines
        # because we never ran the validator.
        return "rate-interrupted", f"session {pct_str}", []

    # API-529-STORM GUARD (2026-07-02): an Anthropic "Overloaded" storm kills the
    # session mid-work (repeated 529s -> long silent retry gaps -> the stall
    # watchdog SIGTERMs -> exit 143 with no report). That is an INFRA outage, not
    # a worker failure — it must not consume a retry or feed the stuck detector
    # (it burned 2x3 attempts on Gcrash-blueeco). Detect: nonzero exit + >=5
    # occurrences of 529/Overloaded in the attempt stream -> sleep out the storm
    # and retry the same attempt number.
    if rc != 0:
        try:
            _atxt = attempt_log.read_text(errors="replace")
            _low = _atxt.lower()
            _n529 = _low.count("overloaded") + len(re.findall(r"\b529\b", _atxt))
        except Exception:
            _n529 = 0
        if _n529 >= 3:
            console.print(
                f"[yellow]API 529-storm detected ({_n529} overload markers, exit {rc}) — "
                f"infra outage, attempt {attempt} NOT counted. Sleeping 10 min before retry.[/yellow]"
            )
            notify(
                f"⏸ phase {pid}: Anthropic API 529-storm killed the session "
                f"({_n529} markers). Waiting it out; attempt not counted.",
                level="warn",
            )
            time.sleep(600)
            return "rate-interrupted", f"api-529-storm x{_n529}", []

    console.print(f"[dim]Claude Code exited {rc}. Running validator...[/dim]")

    # Ground-truth validator pass: this is what decides pass/fail, not Claude's word.
    with validator_log.open("w") as f:
        v = subprocess.run(
            ["bash", str(validator)],
            cwd=REPO_ROOT, stdout=f, stderr=subprocess.STDOUT,
        )

    state["retries"][pid] = attempt
    save_state(state)

    if v.returncode == 0:
        # The phase's own validator passed — but run the central close-gate to
        # catch false-greens a lax validator misses (no-code stub, stale/mixed
        # device build, missing owner play-test). Only "pass" lets it complete.
        gate_status, gate_reason = close_gate(phase, validator_log)
        if gate_status == "pass":
            return "pass", "", []
        if gate_status == "awaiting-owner":
            return "awaiting-owner", "", []
        # Fixable gate failure: append the reason to the validator log and fall
        # through to the normal failure path (checkpoint, fingerprint, retry —
        # the worker sees gate_reason as feedback on the next attempt).
        with validator_log.open("a") as f:
            f.write("\n\n" + gate_reason + "\n")
        console.print(f"[yellow]{gate_reason}[/yellow]")

    # AUTO-CHECKPOINT (owner 2026-06-13): version EVERY failed attempt's work.
    # The orchestrator used to commit ONLY on PASS, so a long failing/iterating
    # phase left hours of engine changes — and any regression it introduced —
    # unversioned and un-bisectable. Commit a labeled WIP now so we can always
    # roll back / diff. (PASS path already commits with the phase name.)
    try:
        git_commit(pid, f"WIP checkpoint — attempt {attempt} (validator FAILED; auto-versioned for rollback/bisect, NOT a pass)")
    except Exception as e:  # noqa: BLE001 — never let checkpointing crash the loop
        console.print(f"[yellow]auto-checkpoint commit failed: {e}[/yellow]")

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

def main(argv: list[str] | None = None) -> int:
    global QUIET
    parser = argparse.ArgumentParser(description="Autoport orchestrator")
    parser.add_argument(
        "--quiet", action="store_true",
        help="Suppress live event rendering (silent mode, like pre-verbose behavior)",
    )
    args = parser.parse_args(argv)
    QUIET = bool(args.quiet)

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
        f"Profile: {PROFILE_NAME} · Manager: {MODEL} @ {EFFORT} · Workers: {SUBAGENT_MODEL}\n"
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

        # Owner-gate resume: if a prior run already validated this owner_verify
        # phase, don't re-run the worker. If the owner has since dropped the OK
        # token, complete + advance; if not, pause again (zero worker burn).
        if phase.get("owner_verify", False) and pid in state.get("validator_passed", []):
            token = AUTOPORT_DIR / "owner-ok" / pid
            if token.exists():
                console.print(f"[bold green]✓ Phase {pid} owner-confirmed[/bold green]")
                state["completed"].append(pid)
                state["current_phase_idx"] += 1
                save_state(state)
                notify(f"✓ phase {pid} owner-confirmed — advancing.", level="ok")
                continue
            console.print(
                f"[yellow]Phase {pid} still awaiting owner play-test "
                f"(touch {AUTOPORT_DIR / 'owner-ok' / pid}).[/yellow]"
            )
            notify(
                f"⏸ phase {pid} still awaiting your play-test. "
                f"Confirm with: touch {AUTOPORT_DIR / 'owner-ok' / pid}",
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

        if result == "rate-interrupted":
            # We deliberately did not consume a retry, did not fingerprint,
            # and did not run the validator. wait_for_quota() at the top of
            # the next iteration will sleep until the session window resets,
            # then we re-enter this phase from scratch.
            console.print(
                f"[yellow]Phase {pid} interrupted by rate-limit guard "
                f"({reason}). Retrying after session reset.[/yellow]"
            )
            continue

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

        elif result == "awaiting-owner":
            # Validator + close-gate passed, but this phase is owner_verify: the
            # owner's eye is the final gate. Commit the work (so it's versioned),
            # record that it validated, and PAUSE — do NOT mark it done. The loop
            # resumes (top-of-loop shortcut) once the owner drops the OK token.
            state.setdefault("validator_passed", [])
            if pid not in state["validator_passed"]:
                state["validator_passed"].append(pid)
            save_state(state)
            if git_commit(pid, phase["name"] + " (validator+gates passed — AWAITING OWNER PLAY-TEST, NOT done)"):
                console.print("[green]  committed (awaiting-owner checkpoint)[/green]")
                if plan.get("global", {}).get("git", {}).get("push_after_each_phase", True):
                    git_push()
            token_path = AUTOPORT_DIR / "owner-ok" / pid
            console.print(Panel.fit(
                f"[bold yellow]⏸ Phase {pid} AWAITING OWNER PLAY-TEST[/bold yellow]\n\n"
                f"Validator + close-gate passed, but {pid} is owner_verify — the "
                f"owner's eye is the final gate.\n\n"
                f"If it's good, confirm and continue:\n  touch {token_path}\n"
                f"then relaunch the orchestrator.",
                border_style="yellow",
                title="HUMAN GATE",
            ))
            notify(
                f"⏸ phase {pid} validator+gates PASSED — awaiting your play-test "
                f"(owner's eye = final gate). If good: touch {token_path}",
                level="alert",
            )
            return 0

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
    sys.exit(main(sys.argv[1:]))
