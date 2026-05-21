#!/usr/bin/env python3
"""
Trace-diff harness — the core anti-cheat for the autoport.

Compares a target trace (typically `adb logcat -v threadtime` from a
device) against the desktop oracle trace, asserting the target is a
subsequence of the oracle up to a specified milestone. Designed so
that printing log strings doesn't suffice — the validator needs the
*ordered set* of normalized events to match.

Usage:

    trace_diff.py \
        --oracle .autoport/oracle/jak1-desktop-trace.txt \
        --target /tmp/android-run.log \
        --milestone 'engine: state=title' \
        --max-divergence-events 20

Exits 0 on match (target's events are a subsequence of oracle's up to
milestone), 1 on divergence (with a diff summary printed to stderr).
"""

from __future__ import annotations

import argparse
import re
import sys
from collections import deque
from dataclasses import dataclass
from pathlib import Path

# ---- Normalizers ----------------------------------------------------
#
# Rewrite a raw log line to a stable canonical event string that is
# platform-agnostic where possible. Lines that don't survive
# normalization (uninteresting platform spam) get dropped (None
# returned).

ANSI_RE = re.compile(r'\x1b\[[0-9;]*[mGKH]')
LOGCAT_HEADER_RE = re.compile(
    r'^\d{2}-\d{2}\s+\d{2}:\d{2}:\d{2}\.\d+\s+\d+\s+\d+\s+[VDIWEAF]\s+([^:]+):\s*'
)
DESKTOP_LG_RE = re.compile(
    r'^\[[\d:.\- ]+\]\s+\[(\w+)\]\s+(?:\[[\w:_-]+\]\s+)?'
)
HEX_RE = re.compile(r'0x[0-9a-fA-F]{4,}')
ADDR_RE = re.compile(r'\b[0-9a-fA-F]{8,}\b')
INT_RE = re.compile(r'\b\d{4,}\b')
PATH_BASENAME_RE = re.compile(r'/[^\s:()]+/')
THREADID_RE = re.compile(r'tid\s*=?\s*\d+', re.IGNORECASE)
DURATION_RE = re.compile(r'\b\d+(?:\.\d+)?\s*(?:ms|us|ns|s|sec|min)\b', re.IGNORECASE)

# Tag that an Android logcat line MUST have to be considered an opengoal-gk
# emission. Anything else is noise (system services, MIUI spam, etc.).
ANDROID_INTERESTING_TAGS = (
    'opengoal-gk', 'opengoal-gk-kernel', 'opengoal-loader',
    'libgk', 'opengoal-overlord', 'opengoal-iop', 'opengoal-listener',
)

# Tag indicators on the desktop side: lg::log macros emit lines like
# `[GAME] message` or `[KERNEL] message` after the timestamp. We accept
# any tag.
DESKTOP_INTERESTING_PREFIXES = (
    'kernel', 'gkernel', 'game', 'gfx', 'iop', 'overlord',
    'listener', 'engine', 'goal_main', 'kheap', 'cgo',
    'init', 'shader', 'render', 'state',
)

# Substrings that mean "this is GOAL-emitted, keep it" — these are
# the canonical milestones / runtime signals we care about across both
# platforms.
CANONICAL_KEYWORDS = (
    'engine:', 'gkernel:', 'goal_main', 'KERNEL.CGO', 'GAME.CGO',
    'ENGINE.CGO', 'kheap_alloc', 'InitMachine', 'KernelCheckAndDispatch',
    'symbol:', 'set_state', 'set!', 'Listener', 'Overlord', 'IOP:',
    'shader:', 'frame ', 'GfxDispatcher',
)


def strip_platform_frame(line: str) -> tuple[str, str] | None:
    """Return (tag, body) if the line is worth analyzing, else None.

    Tag is the platform-emitter tag (e.g. 'opengoal-gk' on Android,
    or 'KERNEL' on desktop). Body is everything after the tag.
    """
    line = ANSI_RE.sub('', line)
    line = line.rstrip()
    if not line:
        return None

    # Android logcat format: 05-20 08:03:48.910  2970 11112 I tagname: body
    m = LOGCAT_HEADER_RE.match(line)
    if m:
        tag = m.group(1).strip().lower()
        body = line[m.end():]
        if not any(t in tag for t in ANDROID_INTERESTING_TAGS):
            # Drop non-gk Android logcat noise unless body has a canonical kw.
            if not any(k in body for k in CANONICAL_KEYWORDS):
                return None
        return (tag, body)

    # Desktop lg format: [HH:MM:SS.mmm] [tag] body
    m = DESKTOP_LG_RE.match(line)
    if m:
        tag = m.group(1).strip().lower()
        body = line[m.end():]
        if not any(p in tag for p in DESKTOP_INTERESTING_PREFIXES):
            if not any(k in body for k in CANONICAL_KEYWORDS):
                return None
        return (tag, body)

    # Last resort: if a raw line carries a canonical keyword, keep it.
    if any(k in line for k in CANONICAL_KEYWORDS):
        return ('?', line)
    return None


def canonicalize_body(body: str) -> str:
    """Strip platform/run-specific noise so the same event from two
    runs collapses to the same string."""
    s = body
    s = HEX_RE.sub('0xH', s)
    s = ADDR_RE.sub('A', s)
    s = INT_RE.sub('N', s)
    s = PATH_BASENAME_RE.sub('/.../', s)
    s = THREADID_RE.sub('tid=T', s)
    s = DURATION_RE.sub('D', s)
    s = re.sub(r'\s+', ' ', s).strip()
    return s


@dataclass
class Event:
    raw: str
    tag: str
    body: str
    canonical: str
    line_no: int

    def __repr__(self) -> str:
        return f'L{self.line_no} [{self.tag}] {self.canonical[:80]}'


def parse_trace(path: Path) -> list[Event]:
    """Read a trace file, normalize, and return only the interesting
    events. Order is preserved."""
    events: list[Event] = []
    with path.open(encoding='utf-8', errors='replace') as fh:
        for n, raw in enumerate(fh, start=1):
            parsed = strip_platform_frame(raw)
            if parsed is None:
                continue
            tag, body = parsed
            ev = Event(raw=raw.rstrip(), tag=tag, body=body,
                       canonical=canonicalize_body(body), line_no=n)
            events.append(ev)
    return events


def subsequence_match(oracle: list[Event], target: list[Event],
                      milestone: str,
                      max_extra_target_events: int) -> tuple[bool, str]:
    """Check that `target` is a subsequence of `oracle`, allowing up to
    `max_extra_target_events` Android-only events to be skipped.

    Stops scanning the oracle once its event matches `milestone`. The
    target must reach this milestone too (otherwise the device boot
    failed to advance far enough).

    Returns (passed, diagnostic).
    """
    # Trim oracle to start of run + up to milestone (inclusive).
    oracle_milestone_idx = next(
        (i for i, ev in enumerate(oracle) if milestone in ev.canonical),
        None
    )
    if oracle_milestone_idx is None:
        return False, (
            f"milestone '{milestone}' not found in oracle trace; "
            f"oracle has {len(oracle)} events.\n"
            f"Last 5 oracle canonicals:\n  " +
            '\n  '.join(repr(e) for e in oracle[-5:])
        )
    oracle = oracle[:oracle_milestone_idx + 1]

    target_milestone_idx = next(
        (i for i, ev in enumerate(target) if milestone in ev.canonical),
        None
    )
    if target_milestone_idx is None:
        return False, (
            f"milestone '{milestone}' NOT reached in target trace; "
            f"target has {len(target)} events total.\n"
            f"Last 10 target canonicals:\n  " +
            '\n  '.join(repr(e) for e in target[-10:])
        )
    target = target[:target_milestone_idx + 1]

    # Two-pointer subsequence check with bounded skip budget.
    i_oracle = 0
    i_target = 0
    extras = 0
    diagnostics: list[str] = []
    while i_target < len(target):
        if i_oracle >= len(oracle):
            # Target has events past the oracle's milestone — they're
            # platform-specific or interleaved. Allowed up to budget.
            extras += 1
            if extras > max_extra_target_events:
                diagnostics.append(
                    f"target trace has {extras} events past oracle's "
                    f"milestone (budget {max_extra_target_events}); "
                    f"first extra: {target[i_target]!r}"
                )
                return False, '\n'.join(diagnostics)
            i_target += 1
            continue

        if target[i_target].canonical == oracle[i_oracle].canonical:
            # Match — advance both.
            i_oracle += 1
            i_target += 1
        else:
            # Look ahead in oracle for a future match of target's
            # current event (within a small window).
            HORIZON = 50
            ahead = None
            for j in range(i_oracle + 1, min(i_oracle + 1 + HORIZON, len(oracle))):
                if oracle[j].canonical == target[i_target].canonical:
                    ahead = j; break
            if ahead is not None:
                # Oracle has extra events we'll just skip past.
                i_oracle = ahead + 1
                i_target += 1
                continue
            # No match within horizon — target event is platform-specific
            # noise we tolerate.
            extras += 1
            if extras > max_extra_target_events:
                diagnostics.append(
                    f"target trace diverged: {extras} events not in oracle.\n"
                    f"  target[{i_target}]: {target[i_target]!r}\n"
                    f"  oracle window @ {i_oracle}: "
                    + ', '.join(
                        repr(e) for e in oracle[i_oracle:i_oracle + 3]
                    )
                )
                return False, '\n'.join(diagnostics)
            i_target += 1

    return True, (
        f"PASS: target reached milestone '{milestone}' "
        f"with {extras} platform-only events tolerated "
        f"(budget {max_extra_target_events}); "
        f"oracle scanned {i_oracle}/{len(oracle)} events."
    )


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--oracle', type=Path, required=True,
                    help='Path to oracle trace (desktop verbose log)')
    ap.add_argument('--target', type=Path, required=True,
                    help='Path to target trace (Android logcat capture)')
    ap.add_argument('--milestone', type=str, required=True,
                    help='Canonical event substring that target must reach')
    ap.add_argument('--max-divergence-events', type=int, default=20,
                    help='Tolerance for target-only events not in oracle')
    ap.add_argument('--verbose', action='store_true',
                    help='Print parsed event counts before matching')
    args = ap.parse_args()

    if not args.oracle.exists():
        print(f"ERROR: oracle not found at {args.oracle}", file=sys.stderr)
        return 2
    if not args.target.exists():
        print(f"ERROR: target not found at {args.target}", file=sys.stderr)
        return 2

    oracle = parse_trace(args.oracle)
    target = parse_trace(args.target)
    if args.verbose:
        print(f"oracle: {len(oracle)} interesting events parsed", file=sys.stderr)
        print(f"target: {len(target)} interesting events parsed", file=sys.stderr)

    if not oracle:
        print("ERROR: no interesting events in oracle — normalizer broken?",
              file=sys.stderr)
        return 2

    passed, msg = subsequence_match(
        oracle, target, args.milestone, args.max_divergence_events
    )
    print(msg, file=sys.stderr)
    return 0 if passed else 1


if __name__ == '__main__':
    sys.exit(main())
