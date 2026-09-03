#!/usr/bin/env python3
"""hdeye_anim_scan.py — Grecharged-hd-eye-scale: measure jak1's CARTOON EYE-SIZE channel OFFLINE,
over every animation in the game, and apply the shipped HD curve to it.

Why offline. The channel only MOVES in spooled cutscene animations: the gameplay art-groups are
almost all max-frame=0, i.e. one constant eye pose per animation. A runtime sample would therefore
report a flat channel and prove nothing. The authored data is the ground truth, and it is on disk.

Where it lives. `art-joint-anim` (art-h.gc:110-124) holds `eye-anim-data` -> `merc-eye-anim-block`
(merc-h.gc:190-192): `max-frame int16 @0`, then `(max-frame+1)*2` inlined `merc-eye-anim-frame`
(merc-h.gc:179-187, 8 bytes: pupil-trans-x, pupil-trans-y, blink, pad, iris-scale, pupil-scale,
lid-scale, pad) — two per animation frame, left eye then right (eye.gc:927-930). convert-eye-data
(eye.gc:886-903) ZERO-extends those bytes and vitof12s them, so the dequantised value is byte/64.

Object layout is taken from decompiler/ObjectFile/ObjectFileDB.cpp get_art_info (art-group at
segment base, name@+8, length@+12, element pointers at +32+4i; element P has eye-anim-data@P+0 and
name@P+4), not guessed. Every hit is cross-checked: the element name must decode as printable ascii
and the block must fit inside the segment.

STOCK column = the value jak1 applies. HD column = hd_eye_scale_curve() from EyeRenderer.cpp, i.e.
    out = rest + gainup * (raw - rest)   if raw > rest,   else raw
with that character's own authored rest — the same numbers the runtime uses, read from the same
[eyescale] block of recharged_assets/physics_chains.txt.

usage: hdeye_anim_scan.py [--params <physics_chains.txt>] [--top N]
"""
import argparse
import collections
import glob
import os
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# jak1 driver model prefix -> (character, eye_id pair). The eye_id is the slot every HD look for
# that character is remapped onto (tools/hd_merc_swap remap_eye_ids, --eye-from <driver>).
DRIVERS = [
    ('sidekick-human', 'Daxter(human)', None),   # longest prefixes first
    ('green-sagecage', 'Samos', 4),
    ('sage-bluehut', 'Samos', 4),
    ('assistant', 'Keira', 6),
    ('jak-white', 'Jak(white)', None),
    ('sidekick', 'Daxter', 2),
    ('eichar', 'Jak', 0),
    ('sage', 'Samos', 4),
]


def art_scan(d, B, SZ):
    """Yield (element_name, max_frame, iris[], pupil[], lid[]) for one linked art-group segment."""
    def u32(o):
        return struct.unpack_from('<I', d, B + o)[0]

    if B + 36 > len(d) or u32(0) != 0xFFFFFFFF:
        return None

    def gstr(p):
        n = u32(p)
        if n > 128 or B + p + 4 + n > len(d):
            raise ValueError
        return d[B + p + 4:B + p + 4 + n].split(b'\0')[0].decode('ascii', 'replace')

    try:
        agname, length = gstr(u32(8)), u32(12)
    except Exception:
        return None
    if not (0 < length < 4000):
        return None
    out = []
    for i in range(length):
        if B + 32 + 4 * i + 4 > len(d):
            break
        p = u32(32 + 4 * i)
        if p == 0 or p >= SZ or p & 3:
            continue
        try:
            name = gstr(u32(p + 4))
        except Exception:
            continue
        if not name or not name.isprintable():
            continue
        q = u32(p + 0)
        if q == 0 or q >= SZ or q & 3:
            continue
        mx = struct.unpack_from('<h', d, B + q)[0]
        if mx < 0 or q + 8 + 16 * (mx + 1) > SZ:
            continue
        iris, pupil, lid = [], [], []
        for k in range(2 * (mx + 1)):
            b = d[B + q + 8 + 8 * k:B + q + 8 + 8 * k + 8]
            if len(b) < 8:
                break
            iris.append(b[4])
            pupil.append(b[5])
            lid.append(b[6])
        if len(iris) == 2 * (mx + 1):
            out.append((name, mx, iris, pupil, lid))
    return agname, out


def collect():
    """(character, source, anim, max_frame, iris[], pupil[], lid[]) for the whole corpus."""
    recs = []

    def add(src, name, mx, ir, pu, li):
        for prefix, char, _slot in DRIVERS:
            if name.startswith(prefix + '-'):
                recs.append((char, src, name, mx, ir, pu, li))
                return

    for p in sorted(glob.glob(os.path.join(REPO, 'out/jak1/obj/*-ag.go'))):
        d = open(p, 'rb').read()
        if len(d) < 20:
            continue
        _tt, _ll, ver, sz = struct.unpack_from('<4I', d, 0)
        if ver != 4 or 16 + sz > len(d):
            continue
        r = art_scan(d, 16, sz)
        if r:
            for name, mx, ir, pu, li in r[1]:
                add(os.path.basename(p), name, mx, ir, pu, li)

    for p in sorted(glob.glob(os.path.join(REPO, 'out/jak1/iso/*.STR'))):
        d = open(p, 'rb').read()
        if len(d) < 512:
            continue
        sec = struct.unpack_from('<64I', d, 0)
        siz = struct.unpack_from('<64I', d, 256)
        for c in range(64):
            if sec[c] == 0 or siz[c] == 0:
                continue
            base = sec[c] * 0x800
            if base + 12 > len(d):
                continue
            tt, ln = struct.unpack_from('<2I', d, base)
            ver = struct.unpack_from('<H', d, base + 8)[0]
            if tt != 0xFFFFFFFF or ver != 2:
                continue
            b = base + ln
            sz = min(siz[c] - ln, len(d) - b)
            try:
                r = art_scan(d, b, sz)
            except Exception:
                r = None
            if r:
                for name, mx, ir, pu, li in r[1]:
                    add(f"{os.path.basename(p)}#ch{c}", name, mx, ir, pu, li)
    return recs


def load_params(path):
    """The live [eyescale] block: {'on':bool,'gainup':float, slot -> {'rest_iris','rest_pupil',...}}"""
    prm = {'on': True, 'gainup': 0.45, 'slots': {}}
    if not os.path.exists(path):
        return prm
    in_sec = False
    for raw in open(path, errors='replace'):
        raw = raw.split('#', 1)[0]
        toks = raw.split()
        if not toks:
            continue
        if toks[0].startswith('['):
            in_sec = (toks[0] == '[eyescale]')
            toks = toks[1:]
        if not in_sec:
            continue
        slot = None
        if toks and toks[0] == 'slot' and len(toks) > 1:
            slot = int(float(toks[1]))
            toks = toks[2:]
        for t in toks:
            if '=' not in t:
                continue
            k, v = t.split('=', 1)
            try:
                f = float(v)
            except ValueError:
                continue
            if slot is None:
                if k == 'on':
                    prm['on'] = f != 0.0
                elif k == 'gainup':
                    prm['gainup'] = f
            else:
                prm['slots'].setdefault(slot, {})[k] = f
    return prm


def curve(raw, rest, gainup):
    """EyeRenderer.cpp hd_eye_scale_curve, verbatim."""
    out = rest + gainup * (raw - rest) if raw > rest else raw
    return 0.0 if out < 0.0 else out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--params', default=os.path.join(REPO, 'recharged_assets/physics_chains.txt'))
    ap.add_argument('--top', type=int, default=6)
    a = ap.parse_args()

    prm = load_params(a.params)
    recs = collect()
    if not recs:
        print("FAIL: no eye-anim-data found — is out/jak1/obj/*-ag.go extracted?")
        return 1

    print(f"corpus: {len(recs)} animations carrying eye-anim-data, from "
          f"{len(set(r[1] for r in recs))} art-group / cutscene sources")
    print(f"params: {a.params}  on={prm['on']} gainup={prm['gainup']}")
    print("")

    order = ['Jak', 'Daxter', 'Samos', 'Keira', 'Jak(white)', 'Daxter(human)']
    slot_of = {c: s for _p, c, s in DRIVERS}
    fails, rows = [], []
    for char in order:
        rs = [r for r in recs if r[0] == char]
        if not rs:
            continue
        slot = slot_of.get(char)
        sp = prm['slots'].get(slot, {}) if slot is not None else {}
        gain = sp.get('gainup', prm['gainup'])
        for kind, idx in (('iris', 4), ('pupil', 5)):
            vals = [v / 64.0 for r in rs for v in r[idx]]
            mode = collections.Counter(vals).most_common(1)[0]
            rest_cfg = sp.get('rest_' + kind)
            anchor = rest_cfg if rest_cfg is not None else mode[0]
            hd = [curve(v, anchor, gain) for v in vals] if prm['on'] and slot is not None else vals
            rows.append((char, slot, kind, min(vals), max(vals), min(hd), max(hd),
                         mode[0], mode[1] / len(vals), anchor, rest_cfg is not None, gain))
            if max(hd) > max(vals) + 1e-6:
                fails.append(f"{char} {kind}: HD max {max(hd):.4f} > stock max {max(vals):.4f}")
            if min(hd) < min(vals) - 1e-6:
                fails.append(f"{char} {kind}: HD min {min(hd):.4f} < stock min {min(vals):.4f}")
            if rest_cfg is not None and abs(rest_cfg - mode[0]) > 1e-4 and slot is not None:
                fails.append(f"{char} {kind}: shipped rest {rest_cfg:.5f} != authored rest "
                             f"{mode[0]:.5f} — the base look would be shifted")
            if max(vals) > anchor + 1e-3 and not max(hd) > anchor + 1e-4:
                fails.append(f"{char} {kind}: the effect was REMOVED, not reduced")

    hdr = (f"{'character':<14}{'slot':>5}{'kind':>7}{'stock min':>11}{'stock max':>11}"
           f"{'HD min':>10}{'HD max':>10}{'rest':>9}{'share':>7}{'anchor':>9}{'gain':>6}  kept")
    print(hdr)
    print('-' * len(hdr))
    for (char, slot, kind, smin, smax, hmin, hmax, mode, share, anchor, shipped, gain) in rows:
        kept = ('n/a' if smax <= anchor + 1e-6
                else f"{100.0*(hmax-anchor)/(smax-anchor):.0f}%")
        print(f"{char:<14}{'-' if slot is None else slot:>5}{kind:>7}{smin:>11.4f}{smax:>11.4f}"
              f"{hmin:>10.4f}{hmax:>10.4f}{mode:>9.4f}{share:>7.2f}"
              f"{anchor:>9.4f}{gain:>6.2f}  {kept}")
    print("")
    print("slot '-' = a jak1 model with no HD look retargeted onto it: never HD-covered, so the HD")
    print("column is jak1's own channel, unmodified.")

    print("")
    print(f"---- the animations where the channel actually MOVES (top {a.top} per character) ----")
    for char in order:
        rs = [r for r in recs if r[0] == char]
        moving = []
        for _c, src, name, mx, ir, pu, _li in rs:
            if mx < 1:
                continue
            fi = [(ir[2 * f] + ir[2 * f + 1]) / 128.0 for f in range(mx + 1)]
            fp = [(pu[2 * f] + pu[2 * f + 1]) / 128.0 for f in range(mx + 1)]
            di, dp = max(fi) - min(fi), max(fp) - min(fp)
            if di > 1e-9 or dp > 1e-9:
                moving.append((max(di, dp), name, src, mx, min(fi), max(fi), min(fp), max(fp)))
        if not moving:
            continue
        moving.sort(reverse=True)
        print(f"  {char}: {len(moving)} animations move the channel")
        for span, name, src, mx, i0, i1, p0, p1 in moving[:a.top]:
            print(f"    {name:<52} {src:<22} frames={mx + 1:<4} "
                  f"iris {i0:.4f}->{i1:.4f}  pupil {p0:.4f}->{p1:.4f}")

    print("")
    if fails:
        print("[hdeye-anim-scan FAIL]")
        for f in fails:
            print("  - " + f)
        return 1
    print("[hdeye-anim-scan PASS] over every animation in the game, the HD-applied eye scale is "
          "<= jak1's on every character, and the effect survives wherever jak1 has one")
    return 0


if __name__ == '__main__':
    sys.exit(main())
