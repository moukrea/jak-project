#!/usr/bin/env python3
"""
Boot-link bind-order diff (Phase B2).

Consumes two OG_KLINK_TRACE streams produced by the Phase B1 kernel
instrumentation (game/kernel/jak1/klink.cpp + game/kernel/common/klink.cpp):

  * an x86 ORACLE log  — desktop boot that completes (reaches `link finish: logo`)
  * an ARM64 TARGET log — qemu/device boot that dies around "slot 22"

Each stream carries single-line key=value events:

  KLINKTRACE type   name=<s> num_methods=<n> addr=0x<host>
  KLINKTRACE sym    name=<s> addr=0x<host> val=0x<v>
  KLINKTRACE method type=<s> slot=<M> state=bound|empty fn=0x<addr>
  KLINKTRACE finish obj=<name> seq=<N>

The tool builds, per log, a per-(type, slot) method-bind timeline keyed by the
monotonic `finish seq`, then reports the methods the ARM64 target reaches while
still unbound but which the x86 oracle does bind — i.e. the "type loaded after
the A18 hook" dispatch-before-bind failures that the signal-time trap could not
name. It specifically surfaces the slot-22 class behind the ARM64 boot ceiling.

ARM64 nuance: the A18 method-zero trap patches empty slots to a trap function
(see common/klink.cpp). A slot bound to the trap is NOT a real bind, so the trap
function pointer (parsed from the `A18-DIAG ... GOAL fn ptr 0x...` line) is
excluded when deciding whether the target really bound a method.

Usage:
    boot_link_tracer.py --oracle /tmp/x86-klink.log --target /tmp/arm64-klink.log
        [--milestone 'link finish: logo'] [--max-report 20] [--slot 22]

Exit code: 0 if it ran and produced a report (divergences found or not),
2 on input error.
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# Reuse the canonical normalizers rather than re-deriving the regexes
# (Phase B2 must not duplicate trace_diff.py's stripping rules).
sys.path.insert(0, str(Path(__file__).resolve().parent))
from trace_diff import ANSI_RE  # noqa: E402  (ANSI escape stripper)

# KLINKTRACE event: "KLINKTRACE <kind> k1=v1 k2=v2 ...". The kind is one of
# type|sym|method|finish; the rest is whitespace-separated key=value tokens
# (GOAL symbol / object names contain no whitespace).
KLINK_RE = re.compile(r'KLINKTRACE\s+(\w+)\s+(.*\S)')
# The A18 trap's GOAL function pointer, announced once on the target.
TRAP_FN_RE = re.compile(r'GOAL fn ptr (0x[0-9a-fA-F]+)')


def _to_int(v: str | None) -> int | None:
    if v is None:
        return None
    try:
        return int(v, 16) if v.lower().startswith('0x') else int(v)
    except ValueError:
        return None


def _kv(rest: str) -> dict[str, str]:
    out: dict[str, str] = {}
    for tok in rest.split():
        if '=' in tok:
            k, v = tok.split('=', 1)
            out[k] = v
    return out


@dataclass
class SlotTimeline:
    """Bind history of one (type, slot) within a single log."""
    first_empty_seq: int | None = None
    last_empty_seq: int | None = None
    real_bound_seq: int | None = None   # first seq bound to a real (non-trap) fn
    trap_bound_seq: int | None = None   # first seq bound to the A18 trap fn

    def saw_empty(self) -> bool:
        return self.last_empty_seq is not None

    def really_bound(self) -> bool:
        return self.real_bound_seq is not None


@dataclass
class LogModel:
    path: Path
    trap_fn: int | None = None
    num_methods: dict[str, int] = field(default_factory=dict)
    slots: dict[tuple[str, int], SlotTimeline] = field(default_factory=dict)
    finish_count: int = 0
    last_finish_seq: int = 0
    last_finish_obj: str | None = None
    milestone_seq: int | None = None
    method_lines: int = 0

    def tl(self, key: tuple[str, int]) -> SlotTimeline:
        t = self.slots.get(key)
        if t is None:
            t = SlotTimeline()
            self.slots[key] = t
        return t


def parse_log(path: Path, milestone: str) -> LogModel:
    model = LogModel(path=path)
    cur_seq = 0
    with path.open(encoding='utf-8', errors='replace') as fh:
        for raw in fh:
            line = ANSI_RE.sub('', raw)

            # Trap fn pointer (target only) — needed to discount trap "binds".
            if model.trap_fn is None and 'GOAL fn ptr' in line:
                m = TRAP_FN_RE.search(line)
                if m:
                    model.trap_fn = _to_int(m.group(1))

            # Milestone (reuses the `link finish:` keyword convention).
            if model.milestone_seq is None and milestone and milestone in line:
                model.milestone_seq = cur_seq

            idx = line.find('KLINKTRACE ')
            if idx < 0:
                continue
            m = KLINK_RE.search(line, idx)
            if not m:
                continue
            kind, rest = m.group(1), m.group(2)
            kv = _kv(rest)

            if kind == 'finish':
                seq = _to_int(kv.get('seq'))
                if seq is not None:
                    cur_seq = seq
                    model.finish_count += 1
                    if seq >= model.last_finish_seq:
                        model.last_finish_seq = seq
                        model.last_finish_obj = kv.get('obj')
            elif kind == 'type':
                n = _to_int(kv.get('num_methods'))
                if n is not None:
                    model.num_methods[kv.get('name', '?')] = n
            elif kind == 'method':
                model.method_lines += 1
                tname = kv.get('type')
                slot = _to_int(kv.get('slot'))
                state = kv.get('state')
                fn = _to_int(kv.get('fn'))
                if tname is None or slot is None:
                    continue
                tl = model.tl((tname, slot))
                if state == 'empty':
                    if tl.first_empty_seq is None:
                        tl.first_empty_seq = cur_seq
                    tl.last_empty_seq = cur_seq
                elif state == 'bound':
                    is_trap = (model.trap_fn is not None and fn == model.trap_fn)
                    if is_trap:
                        if tl.trap_bound_seq is None:
                            tl.trap_bound_seq = cur_seq
                    else:
                        if tl.real_bound_seq is None:
                            tl.real_bound_seq = cur_seq
            # 'sym' events are parsed for completeness but not needed here.
    return model


@dataclass
class Divergence:
    type_name: str
    slot: int
    oracle_bound_seq: int
    target_empty_seq: int        # last seq arm64 saw it empty
    target_trapped: bool         # arm64 patched it to the A18 trap
    num_methods: int | None


def diff(oracle: LogModel, target: LogModel) -> list[Divergence]:
    """Methods the target reaches unbound but the oracle really binds.

    A divergence is a (type, slot) that:
      * the oracle really binds (a real method exists for it), AND
      * the target saw empty and NEVER really bound (still empty, or only
        patched to the A18 trap) — so dispatching it on the target fails.
    """
    out: list[Divergence] = []
    for key, t_tl in target.slots.items():
        if not t_tl.saw_empty():
            continue
        if t_tl.really_bound():
            continue  # target genuinely bound it — no divergence
        o_tl = oracle.slots.get(key)
        if o_tl is None or not o_tl.really_bound():
            continue  # oracle doesn't bind it either — not a forward-ref bug
        tname, slot = key
        out.append(Divergence(
            type_name=tname,
            slot=slot,
            oracle_bound_seq=o_tl.real_bound_seq,   # type: ignore[arg-type]
            target_empty_seq=t_tl.last_empty_seq,    # type: ignore[arg-type]
            target_trapped=t_tl.trap_bound_seq is not None,
            num_methods=oracle.num_methods.get(tname),
        ))
    # Order: slot-22 first (the known boot-ceiling class), then by how close the
    # target got before reaching it (latest arm64 seq = nearest the crash), then
    # by the oracle's bind seq, then name — deterministic.
    out.sort(key=lambda d: (d.slot != 22, -d.target_empty_seq, d.oracle_bound_seq,
                            d.type_name))
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--oracle', type=Path, required=True,
                    help='x86 KLINKTRACE log (boot completes)')
    ap.add_argument('--target', type=Path, required=True,
                    help='ARM64 KLINKTRACE log (boot dies ~slot 22)')
    ap.add_argument('--milestone', type=str, default='link finish: logo',
                    help='oracle completion marker (default: "link finish: logo")')
    ap.add_argument('--max-report', type=int, default=20,
                    help='max divergences to list (default 20)')
    ap.add_argument('--slot', type=int, default=None,
                    help='restrict the report to a single method slot')
    args = ap.parse_args()

    for p in (args.oracle, args.target):
        if not p.exists():
            print(f'ERROR: log not found: {p}', file=sys.stderr)
            return 2

    oracle = parse_log(args.oracle, args.milestone)
    target = parse_log(args.target, args.milestone)

    if oracle.method_lines == 0 or target.method_lines == 0:
        print('ERROR: no KLINKTRACE method events parsed — was the log produced '
              'with OG_KLINK_TRACE=1 by a B1-instrumented build?', file=sys.stderr)
        print(f'  oracle method lines: {oracle.method_lines}', file=sys.stderr)
        print(f'  target method lines: {target.method_lines}', file=sys.stderr)
        return 2

    divs = diff(oracle, target)
    if args.slot is not None:
        divs = [d for d in divs if d.slot == args.slot]

    # ---- Report ----
    print('== boot-link bind-order diff ==')
    print(f'oracle: {oracle.path}')
    print(f'  finishes={oracle.finish_count} last="{oracle.last_finish_obj}"@{oracle.last_finish_seq}'
          f'  milestone "{args.milestone}" '
          + (f'reached@seq{oracle.milestone_seq}' if oracle.milestone_seq is not None
             else 'NOT reached'))
    print(f'target: {target.path}')
    print(f'  finishes={target.finish_count} DIED after "{target.last_finish_obj}"@seq'
          f'{target.last_finish_seq}'
          + (f'  (A18 trap fn=0x{target.trap_fn:x})' if target.trap_fn else ''))
    print()

    if not divs:
        print('No dispatch-before-bind divergence found: every method the target '
              'reached unbound is also unbound in the oracle.')
        return 0

    head = divs[0]
    print('FIRST divergence that explains the dispatch failure:')
    print(f'  type={head.type_name} slot={head.slot}'
          + (f' (of {head.num_methods} methods)' if head.num_methods else ''))
    print(f'    x86 oracle bound this method at finish seq {head.oracle_bound_seq};')
    print(f'    ARM64 reached it still EMPTY at finish seq {head.target_empty_seq}'
          f' (never bound{" — only A18-trap-patched" if head.target_trapped else ""}),')
    print(f'    and ARM64 boot died after "{target.last_finish_obj}" @ seq '
          f'{target.last_finish_seq}.')
    print('    => this is an engine type whose method was dispatched before its '
          'defmethod bound it on ARM64 ("type loaded after the A18 hook").')
    print()

    slot22 = [d for d in divs if d.slot == 22]
    if slot22 and args.slot is None:
        print(f'slot-22 dispatch-before-bind suspects ({len(slot22)}):')
        for d in slot22[:args.max_report]:
            print(f'  - {d.type_name}: oracle bound@seq{d.oracle_bound_seq}, '
                  f'arm64 empty@seq{d.target_empty_seq}'
                  + ('(trapped)' if d.target_trapped else ''))
        print()

    print('NOTE: the broad list below also includes methods the oracle binds at a '
          'seq the target never reached (it died at seq '
          f'{target.last_finish_seq}); those are not necessarily live dispatches. '
          'The slot-22 cluster whose arm64_empty seq is nearest the death seq are '
          'the live dispatch-before-bind suspects.')
    print(f'all dispatch-before-bind divergences ({len(divs)} total, '
          f'showing up to {args.max_report}):')
    for d in divs[:args.max_report]:
        print(f'  type={d.type_name} slot={d.slot}  oracle_bound@seq{d.oracle_bound_seq}  '
              f'arm64_empty@seq{d.target_empty_seq}'
              + ('  [trapped]' if d.target_trapped else ''))
    if len(divs) > args.max_report:
        print(f'  ... and {len(divs) - args.max_report} more')
    return 0


if __name__ == '__main__':
    sys.exit(main())
