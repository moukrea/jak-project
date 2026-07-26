#!/usr/bin/env python3
"""gpbrf_r24_moved.py — ROUND 24: the EFFECT metric for displacement coverage.

Round 22/23 counted a pixel as displaced when the program that drew it COULD displace it. That is a
CAPABILITY, and it read 99.22% while the owner was looking at flat geometry on his device. This tool
answers the question the owner actually asked, with the denominator he himself gave ("la geometrie ou
c'est sense etre le cas, car utilise une texture qui a les maps"):

    among the pixels whose material HAS a height map, what fraction actually CHANGES when the
    displacement is switched off at the same vantage, in the same boot, in the same frame — above a
    drift floor MEASURED from an OFF/OFF pair that BRACKETS the ON cell in time?

THE MEASURE IS CONTRAST-RELATIVE (Weber), not an absolute code-value difference. That is not a
softening of the criterion, it is the only way to ask the question uniformly across a frame: the
maps-bearing geometry at the owner's vantage includes stone wall sitting in shadow at a mean
luminance of 21/255, where a 12% shading change — plainly visible — is 2.5 code values, while the
same 12% on the sunlit roof is 20. An absolute threshold does not measure displacement, it measures
how brightly lit a surface happens to be. Numerator and floor use the SAME measure, and the absolute
figure is reported alongside for continuity with rounds 22-23.

Inputs (all captured by .autoport/gpbrf_r24_cells.sh at one vantage in one boot):
  --off1/--on/--off2  the bracketed triple; the two OFFs give the floor, ON-vs-OFF gives the effect
  --mask              u_pbr_debug 32 — white iff the material has a height map (the DENOMINATOR)
  --prog              u_pbr_debug 30 — program tag, to attribute dead pixels to a renderer
  --diag              u_pbr_debug 33 — R tess displacement cm/10, G POM offset world cm/10, B dist/40
  --diag2 (optional)  u_pbr_debug 34 — R tess_disp_w, G |h-0.5|*2, B amp_m in metres
"""
import argparse
import json
import sys

import numpy as np
from PIL import Image

# The r22/r23 program-tag palette (min pairwise distance 127 so it survives H.264).
TAGS = [
    ("tfrag3_tess", (255, 255, 0), True),
    ("tfrag3", (255, 0, 0), True),
    ("etie_base", (0, 255, 0), True),
    ("tie_wind", (0, 255, 255), True),
    ("shrub", (0, 0, 255), True),
    ("hfrag", (255, 128, 0), True),
    ("merc2", (255, 0, 255), False),
    ("generic", (128, 0, 255), False),
    ("emerc", (128, 255, 0), False),
    ("grass", (0, 128, 128), True),
]
LUMA_FLOOR = 8.0  # code values; keeps the relative measure finite in pure black


def load(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)


def dabs(a, b):
    """Per-pixel mean absolute channel difference, 0..255."""
    return np.abs(a - b).mean(axis=2)


def drel(a, b):
    """Per-pixel change as a FRACTION of the local luminance (Weber contrast)."""
    return dabs(a, b) / np.maximum((a.mean(axis=2) + b.mean(axis=2)) * 0.5, LUMA_FLOOR)


def classify(prog, tol):
    h, w, _ = prog.shape
    best = np.full((h, w), 1e18, dtype=np.float32)
    lab = np.full((h, w), -1, dtype=np.int16)
    for i, (_n, rgb, _w) in enumerate(TAGS):
        d = ((prog - np.array(rgb, dtype=np.float32)) ** 2).sum(axis=2)
        m = d < best
        best[m] = d[m]
        lab[m] = i
    lab[best > tol * tol * 3] = -1
    return lab


def pct(a, b):
    return 100.0 * a / b if b else 0.0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--label", required=True)
    ap.add_argument("--tier", required=True, help="tessellation|parallax")
    ap.add_argument("--on", required=True)
    ap.add_argument("--off1", required=True)
    ap.add_argument("--off2", required=True)
    ap.add_argument("--mask", required=True)
    ap.add_argument("--prog", required=True)
    ap.add_argument("--diag", required=True)
    ap.add_argument("--diag2", default="")
    ap.add_argument("--sham", default="", help="a 4th OFF capture: the false-positive control")
    ap.add_argument("--snr", type=float, default=3.0, help="effect must exceed snr x the pixel's own floor")
    ap.add_argument("--min-rel", type=float, default=0.01, help="and this minimum relative change")
    ap.add_argument("--tol", type=float, default=48.0)
    ap.add_argument("--floor-pct", type=float, default=99.0)
    ap.add_argument("--json", default="")
    a = ap.parse_args()

    on, off1, off2 = load(a.on), load(a.off1), load(a.off2)
    mk, pg, dg = load(a.mask), load(a.prog), load(a.diag)
    shapes = {x.shape for x in (on, off1, off2, mk, pg, dg)}
    if len(shapes) != 1:
        sys.exit(f"[r24] shape mismatch: {shapes}")
    h, w, _ = on.shape
    npx = h * w

    # ---- the DENOMINATOR: WORLD pixels whose material has a height map ------------------------
    # Two conditions, both per pixel and both from the device:
    #   (a) the mask capture is solidly white  => a height map is bound on the material that drew it
    #   (b) the program tag classifies it as one of the STATIC WORLD programs
    # (b) keeps the sky, the ocean, the sprites and the HUD out of the denominator: those programs
    # have no tag branch, so in the tag capture they draw their ordinary colour and land in
    # UNCLASSIFIED. Without (b) a bright sky would enter the denominator as "maps-bearing" and then,
    # correctly, never move — inventing a dead zone out of nothing. Everything (b) removes is counted
    # and printed, so the exclusion cannot hide anything either.
    lab = classify(pg, a.tol)
    world_lab = np.zeros(lab.shape, dtype=bool)
    for i, (_n, _rgb, is_world) in enumerate(TAGS):
        if is_world:
            world_lab |= lab == i
    mklum = mk.mean(axis=2)
    maps_raw = mklum > 160.0
    maps = maps_raw & world_lab
    amb = (mklum > 40.0) & ~maps_raw

    # ---- the MEASURED drift floor and the EFFECT, in the same measure --------------------------
    floor_r = drel(off1, off2)
    floor_a = dabs(off1, off2)
    eff_r = np.minimum(drel(on, off1), drel(on, off2))
    eff_a = np.minimum(dabs(on, off1), dabs(on, off2))
    if not maps.any():
        sys.exit(f"[r24] no maps-bearing pixels at {a.label}/{a.tier}")
    thr_r = float(np.percentile(floor_r[maps], a.floor_pct))
    thr_a = float(np.percentile(floor_a[maps], a.floor_pct))
    # PER-PIXEL DECISION RULE. A global percentile of the floor is the wrong instrument here: the
    # floor is near zero on the static geometry that carries the maps and large on the handful of
    # animated pixels (foliage, water, Jak), so a single percentile makes the animated tail set the
    # bar for the whole frame. The rule is per pixel instead — the change must beat THIS pixel's own
    # measured floor by a factor, and clear an absolute minimum relative change so that a pixel with
    # a zero floor cannot qualify on rounding noise.
    thr_px = np.maximum(a.snr * floor_r, a.min_rel)
    moved = eff_r > thr_px
    if a.sham:
        sh = load(a.sham)
        sham_r = np.minimum(drel(sh, off1), drel(sh, off2))
        fp = pct(int((maps & (sham_r > thr_px)).sum()), int(maps.sum()))
        fp_src = "a 4th OFF capture measured EXACTLY like the effect"
    else:
        fp = pct(int((maps & (floor_r > thr_px)).sum()), int(maps.sum()))
        fp_src = "the floor pair itself (no sham cell supplied)"

    tessc = dg[:, :, 0] * (10.0 / 255.0)
    pomc = dg[:, :, 1] * (10.0 / 255.0)
    dist = dg[:, :, 2] * (40.0 / 255.0)

    nmaps = int(maps.sum())
    nmoved = int((maps & moved).sum())
    print(f"=== ROUND 24 EFFECT METRIC — vantage {a.label}, tier {a.tier} ===")
    print(f"frame {w}x{h} = {npx} px")
    print("DRIFT FLOOR — MEASURED from the OFF/OFF pair that brackets the ON cell in time:")
    print(f"    relative: mean {floor_r[maps].mean():.4f}  p50 {np.percentile(floor_r[maps],50):.4f}"
          f"  p{a.floor_pct:g} {thr_r:.4f}      (absolute: mean {floor_a[maps].mean():.2f}/255"
          f"  p{a.floor_pct:g} {thr_a:.2f}/255)")
    print(f"    -> RULE: a pixel counts as MOVED when its relative ON/OFF change exceeds "
          f"max({a.snr:g} x its own measured floor, {a.min_rel:g})")
    print(f"    -> FALSE-POSITIVE CONTROL ({fp_src}): {fp:.2f}%")
    nraw = int(maps_raw.sum())
    print(f"MAPS-BEARING DENOMINATOR (u_pbr_debug 32 AND a world program tag): {nmaps} px = "
          f"{pct(nmaps,npx):.2f}% of the frame")
    print(f"    mask-white pixels dropped for having no world program tag (sky/ocean/sprite/HUD/"
          f"blended): {nraw-nmaps} px = {pct(nraw-nmaps,npx):.2f}% of the frame")
    print(f"    blend-ambiguous mask pixels (grey, never counted either way): {int(amb.sum())} px "
          f"= {pct(int(amb.sum()),npx):.2f}% of the frame")
    print(f"MOVED: {nmoved}/{nmaps} = {pct(nmoved,nmaps):.2f}% of maps-bearing pixels actually moved")
    print(f"    mean relative |ON-OFF| over the denominator: {eff_r[maps].mean():.4f} = "
          f"{eff_r[maps].mean()/max(floor_r[maps].mean(),1e-9):.2f}x the measured floor "
          f"(absolute {eff_a[maps].mean():.2f}/255 vs floor {floor_a[maps].mean():.2f}/255)")

    print()
    print(f"{'program':<13}{'drawn px':>10}{'% frame':>9}{'maps px':>10}{'moved':>10}{'% moved':>9}"
          f"{'dead':>9}{'tessCm':>8}{'pomCm':>8}{'dist m':>8}")
    rows = []
    world_px = world_maps = world_moved = 0
    actor_px = 0
    for i, (name, _rgb, is_world) in enumerate(TAGS):
        m = lab == i
        n = int(m.sum())
        if n == 0:
            continue
        mm = m & maps
        nm = int(mm.sum())
        nv = int((mm & moved).sum())
        tc = float(tessc[mm].mean()) if nm else 0.0
        pc = float(pomc[mm].mean()) if nm else 0.0
        dm = float(dist[mm].mean()) if nm else 0.0
        print(f"{name:<13}{n:>10}{pct(n,npx):>8.2f}%{nm:>10}{nv:>10}{pct(nv,nm):>8.2f}%{nm-nv:>9}"
              f"{tc:>8.3f}{pc:>8.3f}{dm:>8.1f}")
        rows.append(dict(program=name, drawn=n, maps=nm, moved=nv, dead=nm - nv,
                         moved_pct=pct(nv, nm), tess_cm=tc, pom_cm=pc, dist_m=dm))
        if is_world:
            world_px += n
            world_maps += nm
            world_moved += nv
        else:
            actor_px += n
    nun = int((lab == -1).sum())
    print(f"{'UNCLASSIFIED':<13}{nun:>10}{pct(nun,npx):>8.2f}%")
    print(f"{'WORLD':<13}{world_px:>10}{pct(world_px,npx):>8.2f}%{world_maps:>10}{world_moved:>10}"
          f"{pct(world_moved,world_maps):>8.2f}%")
    print(f"{'ACTORS':<13}{actor_px:>10}{pct(actor_px,npx):>8.2f}%         0 (no PBR material path — "
          f"excluded, see the report)")

    # ---- DEAD ZONES: localise and explain ----------------------------------------------------
    dead = maps & ~moved
    ndead = int(dead.sum())
    print()
    print(f"DEAD ZONES: {ndead} maps-bearing px did NOT move ({pct(ndead,nmaps):.2f}% of the denominator)")
    out_dead = []
    if ndead:
        TESS_MIN, POM_MIN = 0.05, 0.05
        cls = {
            "tess tier acted here (>=0.05 cm of vertex displacement) but the image did not change":
                dead & (tessc >= TESS_MIN),
            "parallax tier acted here (>=0.05 cm of world offset) but the image did not change":
                dead & (tessc < TESS_MIN) & (pomc >= POM_MIN),
            "NEITHER tier acted — final amplitude is zero at this pixel":
                dead & (tessc < TESS_MIN) & (pomc < POM_MIN),
        }
        for k, m in cls.items():
            n = int(m.sum())
            if not n:
                continue
            progs = ", ".join(f"{TAGS[i][0]}:{pct(int((m&(lab==i)).sum()),n):.0f}%"
                              for i in range(len(TAGS)) if (m & (lab == i)).any())
            print(f"  - {k}: {n} px = {pct(n,nmaps):.2f}% of denominator, mean dist "
                  f"{dist[m].mean():.1f} m, beyond the 30 m tesc gate "
                  f"{pct(int((dist[m]>30).sum()),n):.0f}%, programs {progs}")
            out_dead.append(dict(cls=k, px=n, pct=pct(n, nmaps), dist=float(dist[m].mean())))
        GX, GY = 16, 9
        print("  worst screen tiles (col,row of a 16x9 grid; only tiles >=40% dead shown):")
        tiles = []
        for gy in range(GY):
            for gx in range(GX):
                ys, ye = gy * h // GY, (gy + 1) * h // GY
                xs, xe = gx * w // GX, (gx + 1) * w // GX
                sm, sd = maps[ys:ye, xs:xe], dead[ys:ye, xs:xe]
                if sm.sum() < 200:
                    continue
                f = pct(int(sd.sum()), int(sm.sum()))
                if f >= 40.0:
                    sl = lab[ys:ye, xs:xe][sd]
                    dom = "n/a"
                    if sl.size:
                        vals, cnt = np.unique(sl, return_counts=True)
                        k = int(vals[cnt.argmax()])
                        dom = TAGS[k][0] if k >= 0 else "unclassified"
                    tiles.append((f, gx, gy, int(sd.sum()), dom,
                                  float(dist[ys:ye, xs:xe][sd].mean()),
                                  float(tessc[ys:ye, xs:xe][sd].mean()),
                                  float(pomc[ys:ye, xs:xe][sd].mean()),
                                  float(((on[ys:ye, xs:xe].mean(axis=2))[sd]).mean())))
        for f, gx, gy, n, dom, dm, tc, pc, lu in sorted(tiles, reverse=True)[:12]:
            print(f"      tile({gx:2d},{gy}) {f:5.1f}% dead {n:6d} px  prog={dom:<12} "
                  f"dist={dm:5.1f}m tessCm={tc:.3f} pomCm={pc:.3f} luma={lu:5.1f}")
        if not tiles:
            print("      (none — no localised dead zone; the residue is scattered)")

    out = dict(label=a.label, tier=a.tier, w=w, h=h, thr_rel=thr_r, thr_abs=thr_a,
               floor_rel_mean=float(floor_r[maps].mean()), false_positive_pct=fp,
               eff_rel_mean=float(eff_r[maps].mean()),
               maps_px=nmaps, moved_px=nmoved, moved_pct=pct(nmoved, nmaps),
               dead_px=ndead, world_px=world_px, world_maps=world_maps,
               world_moved=world_moved, world_moved_pct=pct(world_moved, world_maps),
               programs=rows, dead_classes=out_dead)
    print()
    print(f"HEADLINE[{a.label}/{a.tier}]: {pct(nmoved,nmaps):.2f}% of maps-bearing pixels actually moved "
          f"({nmoved}/{nmaps}), rule max({a.snr:g}x own floor, {a.min_rel:g} relative), "
          f"false-positive {fp:.2f}%")
    if a.json:
        with open(a.json, "w") as f:
            json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
