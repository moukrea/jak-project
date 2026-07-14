#!/usr/bin/env python3
# Grecharged-grass-overhang4: OBJECTIVE banding detector (owner addendum 2026-07-14 00:25 —
# eyeballs are not evidence; a metric must say bands present/absent).
#
# Method: over the droop-region crop, keep only green (grass) pixels, high-pass the luminance
# (kills the slow shading gradient), then compute the 2D AUTOCORRELATION via the power spectrum.
# Periodic stripes = a repeated parallel structure -> the autocorrelation has a strong LOCAL peak
# at lag = the stripe period along the stripe-normal direction. A single edge/silhouette (the lip
# line) or unstructured blade clutter has NO repeated peak -> low score. The score is
#     BANDING = max over directions/lags of a LOCAL autocorr maximum (normalized by ac[0]),
# reported with the peak's direction (stripe-normal, deg, 0 = +x/right, 90 = +y/down) and
# period (px). Calibration: owner_bands_ref_01..11 = positive sample (must fire); an OFF capture
# at the same vantage = the noise floor (must sit low). After the fix ON must read ~ the floor.
#
# Usage: goverhang4_banding.py [--crop X0,Y0,X1,Y1] [--dbg DIR] img1.png [img2.png ...]
import argparse, os, sys
import numpy as np
from PIL import Image

# Calibrated on owner_bands_ref_01..11 (positive sample, 2026-07-14): the diagonal-band
# signature is a stable autocorr peak at period 48-54 px. BAND@WIN tracks exactly that
# frequency band so ON-vs-OFF deltas at the same vantage/crop can't be confused by other
# periodic content (the game's ground textures TILE — absolute cross-vantage values are
# meaningless; only same-vantage same-crop deltas count).
PERIOD_WIN = (40, 62)

def box_blur(a, r):
    # 3-pass box blur ~ gaussian; separable, edge-padded
    for _ in range(3):
        k = 2 * r + 1
        c = np.cumsum(np.pad(a, ((r + 1, r), (0, 0)), mode='edge'), axis=0)
        a = (c[k:, :] - c[:-k, :]) / k
        c = np.cumsum(np.pad(a, ((0, 0), (r + 1, r)), mode='edge'), axis=1)
        a = (c[:, k:] - c[:, :-k]) / k
    return a

def analyze(path, crop, dbg_dir=None, min_lag=10, max_lag=90, blur_r=10):
    im = Image.open(path).convert('RGB')
    if crop:
        im = im.crop(crop)
    rgb = np.asarray(im, dtype=np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mask = (g > r + 8) & (g > b + 16) & (g > 45)
    mask_frac = float(mask.mean())
    L = 0.299 * r + 0.587 * g + 0.114 * b
    m = mask.astype(np.float32)
    # masked local mean -> high-pass restricted to grass pixels
    mb = box_blur(m, blur_r)
    lb = box_blur(L * m, blur_r)
    local_mean = lb / np.maximum(mb, 1e-3)
    hp = (L - local_mean) * m
    # soften the mask border (apodize) so the mask edge itself doesn't correlate
    hp = hp * np.clip(mb * 1.5, 0.0, 1.0)
    hp -= hp.mean()
    # TILE-AVERAGED autocorrelation (Welch): a GLOBAL stripe pattern keeps the same period/angle
    # in every tile so it survives the average; a random clump correlation (small mask, one lucky
    # pair) averages out. This is what makes the score comparable between ON and OFF captures.
    H, W = hp.shape
    TY, TX = 2, 4
    th, tw = H // TY, W // TX
    lags = np.arange(4, max_lag + 6)
    angles = list(range(0, 180, 2))
    acc = np.zeros((len(angles), len(lags)), dtype=np.float64)
    n_tiles = 0
    for ty in range(TY):
        for tx in range(TX):
            tile = hp[ty * th:(ty + 1) * th, tx * tw:(tx + 1) * tw]
            tm = m[ty * th:(ty + 1) * th, tx * tw:(tx + 1) * tw]
            if tm.mean() < 0.12:
                continue  # not enough grass in this tile to say anything
            F = np.fft.rfft2(tile, s=(2 * th, 2 * tw))
            ac = np.fft.irfft2(np.abs(F) ** 2, s=(2 * th, 2 * tw))
            ac0 = ac[0, 0]
            if ac0 <= 1e-6:
                continue
            n_tiles += 1
            for ai, adeg in enumerate(angles):
                arad = np.deg2rad(adeg)
                dx, dy = np.cos(arad), np.sin(arad)
                xs, ys = lags * dx, lags * dy
                x0, y0 = np.floor(xs).astype(int), np.floor(ys).astype(int)
                fx, fy = xs - x0, ys - y0
                x0m, y0m = x0 % (2 * tw), y0 % (2 * th)
                x1m, y1m = (x0 + 1) % (2 * tw), (y0 + 1) % (2 * th)
                v = (ac[y0m, x0m] * (1 - fx) * (1 - fy) + ac[y0m, x1m] * fx * (1 - fy) +
                     ac[y1m, x0m] * (1 - fx) * fy + ac[y1m, x1m] * fx * fy) / ac0
                acc[ai] += v
    if n_tiles == 0:
        return dict(banding=0.0, angle=0.0, period=0.0, mask_frac=mask_frac, tiles=0)
    acc /= n_tiles
    # find the best LOCAL max on the tile-averaged curves (a repeat, not the central lobe)
    best = (0.0, 0.0, 0.0)
    bandp = (0.0, 0.0, 0.0)  # best peak restricted to the calibrated period window (the refs' band)
    for ai, adeg in enumerate(angles):
        v = acc[ai]
        first_done = False
        for i in range(3, len(lags) - 3):
            if lags[i] < min_lag:
                continue
            if v[i] >= v[i - 3:i + 4].max() and v[i] > 0.0:
                # peak PROMINENCE vs the valley before it (rejects monotone shoulders)
                valley = v[max(0, i - 12):i].min()
                prom = v[i] - valley
                if not first_done and prom > best[0]:
                    best = (float(prom), float(adeg), float(lags[i]))
                first_done = True
                if PERIOD_WIN[0] <= lags[i] <= PERIOD_WIN[1] and prom > bandp[0]:
                    bandp = (float(prom), float(adeg), float(lags[i]))
    if dbg_dir:
        os.makedirs(dbg_dir, exist_ok=True)
        base = os.path.splitext(os.path.basename(path))[0]
        hv = hp - hp.min()
        hv = (255 * hv / max(hv.max(), 1e-6)).astype(np.uint8)
        Image.fromarray(hv).save(os.path.join(dbg_dir, base + '_hp.png'))
    return dict(banding=best[0], angle=best[1], period=best[2], mask_frac=mask_frac,
                tiles=n_tiles, band=bandp[0], band_angle=bandp[1], band_period=bandp[2])

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--crop', default=None, help='X0,Y0,X1,Y1')
    ap.add_argument('--dbg', default=None)
    ap.add_argument('images', nargs='+')
    a = ap.parse_args()
    crop = tuple(int(x) for x in a.crop.split(',')) if a.crop else None
    scores = []
    for p in a.images:
        r = analyze(p, crop, a.dbg)
        scores.append(r['banding'])
        print(f"{os.path.basename(p)}: BANDING={r['banding']:.4f} ANGLE={r['angle']:.0f}deg "
              f"PERIOD={r['period']:.0f}px BAND@WIN={r.get('band', 0):.4f} "
              f"(a={r.get('band_angle', 0):.0f} p={r.get('band_period', 0):.0f}) "
              f"MASK_FRAC={r['mask_frac']:.3f} TILES={r.get('tiles', 0)}")
    if len(scores) > 1:
        print(f"SUMMARY: n={len(scores)} mean={np.mean(scores):.4f} "
              f"median={np.median(scores):.4f} min={min(scores):.4f} max={max(scores):.4f}")

if __name__ == '__main__':
    main()
