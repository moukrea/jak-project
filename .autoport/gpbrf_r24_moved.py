#!/usr/bin/env python3
"""gpbrf_r24_moved.py — ROUND 24: the EFFECT metric for displacement coverage.

The round-22/23 number counted a pixel as displaced when the program that drew it COULD displace
it. That is a CAPABILITY, and it read 99.22% while the owner was looking at flat geometry. This
tool answers the question the owner actually asked, with the denominator he himself gave
("la geometrie ou c'est sense etre le cas, car utilise une texture qui a les maps"):

    among the pixels whose material HAS a height map, what fraction actually CHANGES
    when the displacement is switched off at the same vantage, in the same boot, in the
    same frame — above a drift floor MEASURED from an OFF/OFF pair?

Inputs (all captured by .autoport/gpbrf_r24_cells.sh at one vantage in one boot):
  --off1/--on/--off2  the bracketed triple; the two OFFs give the floor, ON-vs-OFF gives the effect
  --mask              u_pbr_debug 32 — white iff the material has a height map (the DENOMINATOR)
  --prog              u_pbr_debug 30 — program tag, to attribute dead pixels to a renderer
  --diag              u_pbr_debug 33 — R tess displacement cm/10, G POM offset world cm/10, B dist/40
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


def load(p):
    return np.asarray(Image.open(p).convert("RGB"), dtype=np.float32)


def de(a, b):
    """Per-pixel mean absolute channel difference, 0..255."""
    return np.abs(a - b).mean(axis=2)


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
    ap.add_argument("--tol", type=float, default=48.0)
    ap.add_argument("--floor-pct", type=float, default=99.0)
    ap.add_argument("--floor-min", type=float, default=6.0)
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
    # (b) is what keeps the sky, the ocean, the sprites and the HUD out of the denominator: those
    # programs never got a tag branch, so in the tag capture they draw their ordinary colour and
    # land in UNCLASSIFIED. Without (b) a bright sky would enter the denominator as "maps-bearing"
    # and then, correctly, never move — inventing a dead zone out of nothing. Everything excluded
    # by (b) is counted and printed below, so the exclusion can never hide anything either.
    lab = classify(pg, a.tol)
    world_lab = np.zeros(lab.shape, dtype=bool)
    for i, (_n, _rgb, is_world) in enumerate(TAGS):
        if is_world:
            world_lab |= lab == i
    mklum = mk.mean(axis=2)
    maps_raw = mklum > 160.0            # solidly white
    maps = maps_raw & world_lab
    amb = (mklum > 40.0) & ~maps_raw    # blended/alpha edges: reported, never counted

    # ---- the MEASURED drift floor -------------------------------------------------------------
    floor = de(off1, off2)
    fsel = floor[maps] if maps.any() else floor.ravel()
    thr = max(a.floor_min, float(np.percentile(fsel, a.floor_pct)))

    # ---- the EFFECT: a pixel moved only if it differs from BOTH OFF captures -------------------
    d1, d2 = de(on, off1), de(on, off2)
    dmin = np.minimum(d1, d2)
    moved = dmin > thr

    dead = maps & ~moved

    tessc = dg[:, :, 0] * (10.0 / 255.0)   # cm of tessellation displacement applied here
    pomc = dg[:, :, 1] * (10.0 / 255.0)    # cm of world POM offset here
    dist = dg[:, :, 2] * (40.0 / 255.0)    # metres from the camera

    nmaps = int(maps.sum())
    nmoved = int((maps & moved).sum())
    print(f"=== ROUND 24 EFFECT METRIC — vantage {a.label}, tier {a.tier} ===")
    print(f"frame {w}x{h} = {npx} px")
    print(f"DRIFT FLOOR (|off1-off2|, the two OFF cells that BRACKET the ON cell):")
    print(f"    mean {floor.mean():.3f}/255   p50 {np.percentile(fsel,50):.3f}   "
          f"p{a.floor_pct:g} {np.percentile(fsel,a.floor_pct):.3f}   max {floor.max():.3f}")
    print(f"    -> threshold used: {thr:.3f}/255 (max of floor p{a.floor_pct:g} and {a.floor_min:g})")
    nraw = int(maps_raw.sum())
    print(f"MAPS-BEARING DENOMINATOR (u_pbr_debug 32 AND a world program tag): {nmaps} px = "
          f"{pct(nmaps,npx):.2f}% of the frame")
    print(f"    mask-white pixels dropped for having no world program tag (sky/ocean/sprite/HUD/"
          f"blended): {nraw-nmaps} px = {pct(nraw-nmaps,npx):.2f}% of the frame")
    print(f"    blend-ambiguous mask pixels (grey, never counted either way): {int(amb.sum())} px "
          f"= {pct(int(amb.sum()),npx):.2f}% of the frame")
    print(f"MOVED: {nmoved}/{nmaps} = {pct(nmoved,nmaps):.2f}% of maps-bearing pixels actually moved")
    print(f"    mean |ON-OFF| over maps-bearing pixels: {dmin[maps].mean():.3f}/255 "
          f"= {dmin[maps].mean()/max(thr,1e-6):.2f}x the floor")

    # ---- per program -------------------------------------------------------------------------
    print()
    print(f"{'program':<13}{'drawn px':>10}{'% frame':>9}{'maps px':>10}{'moved':>10}{'% moved':>9}"
          f"{'dead':>9}{'tessCm':>8}{'pomCm':>8}{'dist m':>8}")
    rows = []
    world_px = world_maps = world_moved = 0
    actor_px = actor_maps = 0
    for i, (name, _rgb, is_world) in enumerate(TAGS):
        m = lab == i
        n = int(m.sum())
        if n == 0:
            continue
        mm = m & maps
        nm = int(mm.sum())
        nv = int((mm & moved).sum())
        nd = int((mm & ~moved).sum())
        tc = float(tessc[mm].mean()) if nm else 0.0
        pc = float(pomc[mm].mean()) if nm else 0.0
        dm = float(dist[mm].mean()) if nm else 0.0
        print(f"{name:<13}{n:>10}{pct(n,npx):>8.2f}%{nm:>10}{nv:>10}{pct(nv,nm):>8.2f}%{nd:>9}"
              f"{tc:>8.3f}{pc:>8.3f}{dm:>8.1f}")
        rows.append(dict(program=name, drawn=n, maps=nm, moved=nv, dead=nd,
                         moved_pct=pct(nv, nm), tess_cm=tc, pom_cm=pc, dist_m=dm))
        if is_world:
            world_px += n
            world_maps += nm
            world_moved += nv
        else:
            actor_px += n
            actor_maps += nm
    nun = int((lab == -1).sum())
    print(f"{'UNCLASSIFIED':<13}{nun:>10}{pct(nun,npx):>8.2f}%")
    print(f"{'WORLD':<13}{world_px:>10}{pct(world_px,npx):>8.2f}%{world_maps:>10}{world_moved:>10}"
          f"{pct(world_moved,world_maps):>8.2f}%")
    print(f"{'ACTORS':<13}{actor_px:>10}{pct(actor_px,npx):>8.2f}%{actor_maps:>10}")

    # ---- DEAD ZONES: localise and explain ----------------------------------------------------
    ndead = int(dead.sum())
    print()
    print(f"DEAD ZONES: {ndead} maps-bearing px did NOT move ({pct(ndead,nmaps):.2f}% of the denominator)")
    if ndead:
        TESS_MIN, POM_MIN = 0.05, 0.05  # cm — below this the tier applied nothing measurable
        cls = {
            "tess acted (>=0.05 cm) but image identical": dead & (tessc >= TESS_MIN),
            "POM acted (>=0.05 cm) but image identical": dead & (tessc < TESS_MIN) & (pomc >= POM_MIN),
            "NEITHER tier acted — amplitude 0 here": dead & (tessc < TESS_MIN) & (pomc < POM_MIN),
        }
        for k, m in cls.items():
            n = int(m.sum())
            if not n:
                continue
            print(f"  - {k}: {n} px = {pct(n,nmaps):.2f}% of denominator, "
                  f"mean dist {dist[m].mean():.1f} m, "
                  f"programs " + ", ".join(
                      f"{TAGS[i][0]}:{pct(int((m&(lab==i)).sum()),n):.0f}%"
                      for i in range(len(TAGS)) if (m & (lab == i)).any()))
        # distance profile of the pixels no tier touched
        m0 = cls["NEITHER tier acted — amplitude 0 here"]
        if m0.any():
            d0 = dist[m0]
            print(f"    distance profile of the untouched pixels: p10 {np.percentile(d0,10):.1f} m  "
                  f"p50 {np.percentile(d0,50):.1f} m  p90 {np.percentile(d0,90):.1f} m  "
                  f"| beyond the 30 m tesc gate: {pct(int((d0>30).sum()),d0.size):.1f}%")
        # spatial localisation: worst tiles of a 16x9 grid
        GX, GY = 16, 9
        print("    worst screen tiles (col,row of a 16x9 grid; only tiles >=40% dead shown):")
        tiles = []
        for gy in range(GY):
            for gx in range(GX):
                ys, ye = gy * h // GY, (gy + 1) * h // GY
                xs, xe = gx * w // GX, (gx + 1) * w // GX
                sm = maps[ys:ye, xs:xe]
                sd = dead[ys:ye, xs:xe]
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
                                  float(pomc[ys:ye, xs:xe][sd].mean())))
        for f, gx, gy, n, dom, dm, tc, pc in sorted(tiles, reverse=True)[:12]:
            print(f"      tile({gx:2d},{gy}) {f:5.1f}% dead  {n:6d} px  prog={dom:<12} "
                  f"dist={dm:5.1f} m  tessCm={tc:.3f}  pomCm={pc:.3f}")
        if not tiles:
            print("      (none — the dead pixels are scattered, no localised dead zone)")

    out = dict(label=a.label, tier=a.tier, w=w, h=h, threshold=thr,
               floor_mean=float(floor.mean()), floor_p=float(np.percentile(fsel, a.floor_pct)),
               maps_px=nmaps, moved_px=nmoved, moved_pct=pct(nmoved, nmaps),
               dead_px=ndead, world_px=world_px, world_maps=world_maps,
               world_moved=world_moved, world_moved_pct=pct(world_moved, world_maps),
               programs=rows)
    print()
    print(f"HEADLINE[{a.label}/{a.tier}]: {pct(nmoved,nmaps):.2f}% of maps-bearing pixels actually moved "
          f"({nmoved}/{nmaps}), floor {thr:.2f}/255")
    if a.json:
        with open(a.json, "w") as f:
            json.dump(out, f, indent=1)


if __name__ == "__main__":
    main()
