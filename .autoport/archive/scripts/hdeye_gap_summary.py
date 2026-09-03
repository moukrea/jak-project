#!/usr/bin/env python3
"""Grecharged-hd-eye-scale — summarise ONE gk log (or routed logcat) from the per-frame [eyegap]
trace, per model.

WHY A PER-FRAME PARSER AND NOT THE HEARTBEAT.  Merc2's [eyegap] heartbeat only prints every 600
blerc calls, so a model that is rendered for a few hundred frames (jak1's own Daxter at
village1-hut: 577 frames on the 2026-08-10 leg) produces ZERO heartbeat lines and reads as "not
measured".  That is how a real stock reference went missing from the previous round.  The
per-frame trace (OG_EYEGAP_TRACE=1) is emitted on every single call, so it can summarise a short
appearance exactly as well as a long one.

THE THREE QUESTIONS, ANSWERED FOR EACH PUBLISHED NUMBER (SPEC section 7):

  gap  — NATURE: a DISTANCE, and specifically a sustained collapse of one; the owner's symptom is
                 "the two eyes TOUCH", which is a distance reaching zero, not an agitation.
         FRAME:  between the LEFT and the RIGHT eye vertex cloud OF THE SAME MODEL, in that model's
                 own object space.  Both clouds ride the same head, so every motion of the head,
                 the body or the camera cancels: what is left is the two eyes' motion towards each
                 other and nothing else.
         READING WITH THE DEFECT ABSENT: bind_gap, the distance with zero blerc displacement.
                 Reported per model, so `close` (= 1 - gap/bind_gap) is 0 when nothing moves.

  grow — NATURE: a fractional radius change, i.e. a SIZE change — the "globuleux" symptom itself.
         FRAME:  fitted about EACH eye's OWN centroid, where sum(r_i) = 0, so a rigid translation
                 of the eyeball drops out of the fit and only its dilation survives.
         READING WITH THE DEFECT ABSENT: exactly 0.0 (no blerc displacement, no growth).

`raw_*` is the field jak1 + the donor produce, before the fix; the unprefixed columns are what the
GPU is actually handed.  On a stock model the two are equal BY CONSTRUCTION (the clamp only ever
looks at models whose name carries -hd), which is what makes the stock column a reference and not
a second treatment.

usage: hdeye_gap_summary.py <log> [<log> ...]
"""
import re
import sys

GEOM = re.compile(
    r'\[eyegap\] geom model=(\S+) hd=(\d+) eyes=(\S+) flex=(\S+) '
    r'span=([\d.]+) bind_gap=([\d.]+) ok=(\d+)')
FRAME = re.compile(
    r'\[eyegap-f\] n=(\d+) model=(\S+) raw_gap=([\d.-]+) gap=([\d.-]+) '
    r'raw_grow=([\d.eE+-]+) grow=([\d.eE+-]+) k=([\d.eE+-]+)')


def summarise(path):
    geom, st = {}, {}
    with open(path, errors='ignore') as fh:
        for line in fh:
            m = GEOM.search(line)
            if m:
                geom[m.group(1)] = dict(hd=int(m.group(2)), eyes=m.group(3), flex=m.group(4),
                                        span=float(m.group(5)), bind_gap=float(m.group(6)),
                                        ok=int(m.group(7)))
                continue
            m = FRAME.search(line)
            if not m:
                continue
            name = m.group(2)
            raw_gap, gap = float(m.group(3)), float(m.group(4))
            raw_grow, grow, k = float(m.group(5)), float(m.group(6)), float(m.group(7))
            s = st.setdefault(name, dict(frames=0, damped=0, raw_gap_min=1e30, gap_min=1e30,
                                         raw_grow_max=-1e30, grow_max=-1e30, k_min=1.0))
            s['frames'] += 1
            s['damped'] += 1 if k < 0.9999 else 0
            s['raw_gap_min'] = min(s['raw_gap_min'], raw_gap)
            s['gap_min'] = min(s['gap_min'], gap)
            s['raw_grow_max'] = max(s['raw_grow_max'], raw_grow)
            s['grow_max'] = max(s['grow_max'], grow)
            s['k_min'] = min(s['k_min'], k)
    return geom, st


def main():
    for path in sys.argv[1:]:
        geom, st = summarise(path)
        print(f'--- {path}')
        if not st:
            print('    NO per-frame [eyegap-f] line in this log '
                  '(was OG_EYEGAP_TRACE=1 set, and was a model with an eye PAIR rendered?)')
        for name in sorted(st):
            s = st[name]
            g = geom.get(name, {})
            bind = g.get('bind_gap', 0.0)
            hd = g.get('hd', -1)
            rc = (1.0 - s['raw_gap_min'] / bind) if bind > 0 else float('nan')
            oc = (1.0 - s['gap_min'] / bind) if bind > 0 else float('nan')
            print(f'    model={name} hd={hd} frames={s["frames"]} damped={s["damped"]} '
                  f'k_min={s["k_min"]:.4f} span={g.get("span", 0):.2f} bind_gap={bind:.2f}')
            print(f'        gap   : raw_min={s["raw_gap_min"]:.2f} -> min={s["gap_min"]:.2f}   '
                  f'closed raw={rc * 100:.2f}% -> {oc * 100:.2f}%')
            print(f'        grow  : raw_top={s["raw_grow_max"]:.4f} -> top={s["grow_max"]:.4f}')
        for name in sorted(geom):
            if name not in st:
                g = geom[name]
                print(f'    model={name} hd={g["hd"]} SEEN AT BIND ONLY (no traced blerc frame): '
                      f'span={g["span"]:.2f} bind_gap={g["bind_gap"]:.2f} ok={g["ok"]} '
                      f'eyes={g["eyes"]} flex={g["flex"]}')


if __name__ == '__main__':
    main()
