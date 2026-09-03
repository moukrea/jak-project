#!/usr/bin/env python3
"""Grecharged-hd-eye-scale — grade one run from the [eyescale] counter heartbeats in a gk log or a
routed logcat.

Heartbeat (EyeRenderer.cpp, one line per eye slot per sprite, cumulative, never reset — so the LAST
one of a slot/kind is that slot's whole-run summary):

  [eyescale] slot=N kind=iris|pupil draws=D covered=C changed=X
             raw_min=..     raw_max=..       <- jak1's own channel over EVERY draw
             cov_raw_min=.. cov_raw_max=..   <- the same channel over the HD-COVERED draws only
             cov_out_min=.. cov_out_max=..   <- what the HD eye actually got, same frames
             rest=..        restshare=..     <- mode of the byte-exact histogram = authored rest
             anchor=..                       <- the rest the curve is anchored on

`raw` is what the ORIGINAL model applies: the eye DMA is emitted by the stock driver process from
*eye-control-array* (merc-eye-anim), the HD companion never touches eyes, and the measurement is
taken before any rewrite.  cov_raw_* vs cov_out_* is therefore a stock-vs-HD comparison on
identical frames.

usage: hdeye_parse.py <log> <tag> [--stock]
  default : an HD run — requires coverage, HD <= stock, and the anchor to match the
            authored rest the scene actually shows
  --armed : an HD run whose per-slot rests were pushed below the resting value from DATA — the
            positive control: the rewrite MUST fire and MUST shrink
  --stock : a genuinely stock run — requires ZERO coverage and zero rewriting
"""
import re
import sys

SENTINEL = 1e8
EPS = 1e-4
NUM = r'(-?\d+\.?\d*(?:e[+-]?\d+)?)'
PAT = re.compile(
    r'\[eyescale\] slot=(\d+) kind=(\w+) draws=(\d+) covered=(\d+) changed=(\d+) '
    r'raw_min=' + NUM + r' raw_max=' + NUM +
    r' cov_raw_min=' + NUM + r' cov_raw_max=' + NUM +
    r' cov_out_min=' + NUM + r' cov_out_max=' + NUM +
    r' rest=' + NUM + r' restshare=' + NUM + r' anchor=' + NUM)


def val(x):
    """The cov_* fields carry the +-1e9 'never touched' sentinel when covered == 0."""
    f = float(x)
    return None if abs(f) > SENTINEL else f


def last_per_slot_kind(path):
    out = {}
    with open(path, 'rb') as f:
        txt = f.read().decode('utf-8', 'replace')
    for m in PAT.finditer(txt):
        g = m.groups()
        out[(int(g[0]), g[1])] = dict(
            draws=int(g[2]), covered=int(g[3]), changed=int(g[4]),
            raw_min=val(g[5]), raw_max=val(g[6]),
            cov_raw_min=val(g[7]), cov_raw_max=val(g[8]),
            cov_out_min=val(g[9]), cov_out_max=val(g[10]),
            rest=float(g[11]), restshare=float(g[12]), anchor=float(g[13]))
    return out


def main():
    path, tag = sys.argv[1], sys.argv[2]
    stock_mode = '--stock' in sys.argv[3:]
    armed_mode = '--armed' in sys.argv[3:]
    d = last_per_slot_kind(path)
    fails, notes = [], []
    if not d:
        print(f"[{tag}] no [eyescale] heartbeat found in {path}")
        sys.exit(1)

    for (s, kind) in sorted(d):
        v = d[(s, kind)]
        cr = "n/a" if v['cov_raw_min'] is None else f"[{v['cov_raw_min']:.4f},{v['cov_raw_max']:.4f}]"
        co = "n/a" if v['cov_out_min'] is None else f"[{v['cov_out_min']:.4f},{v['cov_out_max']:.4f}]"
        print(f"[{tag}] slot={s} {kind:<5} draws={v['draws']} covered={v['covered']} "
              f"changed={v['changed']} all_raw[{v['raw_min']:.4f},{v['raw_max']:.4f}] "
              f"stock{cr} HD{co} rest={v['rest']:.5f} restshare={v['restshare']:.3f} "
              f"anchor={v['anchor']:.5f}")

    covered = [k for k in sorted(d) if d[k]['covered'] > 0]

    if stock_mode:
        for k in sorted(d):
            v = d[k]
            if v['covered'] != 0:
                fails.append(f"slot={k[0]} {k[1]}: covered={v['covered']} on a STOCK run")
            if v['changed'] != 0:
                fails.append(f"slot={k[0]} {k[1]}: changed={v['changed']} on a STOCK run")
        print(f"[{tag}] stock run: {len(d)} slot/kind series, coverage on "
              f"{len(covered)} of them (must be 0)")
    else:
        changed = [k for k in covered if d[k]['changed'] > 0]
        print(f"[{tag}] HD-covered series={[f'{s}/{k}' for s, k in covered]}")
        print(f"[{tag}] series where the rewrite actually fired={[f'{s}/{k}' for s, k in changed]}")
        if not covered:
            fails.append("no HD-covered eye slot — the HD models never reached the eye path")
        for k in covered:
            s, kind = k
            v = d[k]
            a = v['anchor']
            # the curve is `out = raw` at and below rest, so out <= raw ALWAYS: HD can never be
            # more exaggerated than jak1, on either end of the range.
            if v['cov_out_max'] > v['cov_raw_max'] + EPS:
                fails.append(f"slot={s} {kind}: HD max {v['cov_out_max']:.4f} exceeds stock max "
                             f"{v['cov_raw_max']:.4f}")
            if v['cov_out_min'] > v['cov_raw_min'] + EPS:
                fails.append(f"slot={s} {kind}: HD min {v['cov_out_min']:.4f} exceeds stock min "
                             f"{v['cov_raw_min']:.4f}")
            if v['cov_raw_max'] > a + 1e-3 and not v['cov_out_max'] > a + EPS:
                fails.append(f"slot={s} {kind}: the effect was REMOVED, not reduced")
            # the anchor MUST be the value the artist actually keyed, or the base look is shifted.
            # Skipped under --armed: the whole point of that leg is an anchor deliberately displaced
            # below the resting value, so a mismatch there is the control, not a defect.
            if armed_mode:
                pass
            elif v['restshare'] >= 0.30 and abs(v['rest'] - a) > 1e-3:
                fails.append(f"slot={s} {kind}: authored rest {v['rest']:.5f} (share "
                             f"{v['restshare']:.2f}) != anchor {a:.5f} — the base look of this "
                             f"character would be shifted")
            elif v['restshare'] < 0.30:
                notes.append(f"slot={s} {kind}: no dominant rest in this scene (share "
                             f"{v['restshare']:.2f}) — anchor not cross-checked here")
        if armed_mode:
            # positive control: the anchors are pushed below the resting value from DATA, so the
            # rewrite must fire and must shrink. A run where nothing fires proves nothing.
            if not changed:
                fails.append("ARMED control: no covered series was rewritten — the runtime path "
                             "is not live (or the armed params never reached the game)")
            for k in changed:
                v = d[k]
                if not v['cov_out_max'] < v['cov_raw_max'] - EPS:
                    fails.append(f"slot={k[0]} {k[1]}: ARMED but HD max {v['cov_out_max']:.4f} is "
                                 f"not below stock max {v['cov_raw_max']:.4f}")
        elif not changed:
            notes.append("no series was rewritten: with the shipped anchors the curve is an EXACT "
                         "identity at rest, and jak1 only moves this channel inside 21 spooled "
                         "cutscene animations (see .autoport/hdeye_anim_scan.py). Run the ARMED "
                         "leg for the positive control.")

    headline = None
    for k in covered:
        v = d[k]
        if v['cov_raw_max'] is not None and v['cov_raw_max'] > v['anchor'] + 1e-3:
            span = v['cov_raw_max'] - v['anchor']
            if headline is None or span > headline[1]:
                headline = (k, span, v)
    if headline:
        (s, kind), _, v = headline
        keep = 100.0 * (v['cov_out_max'] - v['anchor']) / max(1e-9, v['cov_raw_max'] - v['anchor'])
        print(f"[{tag}] HEADLINE slot={s} {kind}: stock max={v['cov_raw_max']:.4f} "
              f"min={v['cov_raw_min']:.4f} | HD max={v['cov_out_max']:.4f} "
              f"min={v['cov_out_min']:.4f} | rest={v['anchor']:.5f} | "
              f"above-rest excursion kept {keep:.1f}%")
    elif not stock_mode:
        print(f"[{tag}] HEADLINE: no above-rest excursion was exercised in this scene (expected "
              f"outside the 21 spooled cutscenes — the exhaustive measurement is the offline scan)")

    for n in notes:
        print(f"[{tag}] NOTE {n}")
    if fails:
        print(f"[{tag} FAIL]")
        for f in fails:
            print("  - " + f)
        sys.exit(1)
    print(f"[{tag} PASS]")
    sys.exit(0)


if __name__ == '__main__':
    main()
