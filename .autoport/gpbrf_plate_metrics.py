#!/usr/bin/env python3
"""gpbrf_plate_metrics.py — measure the owner's own acceptance criterion on a relief A/B pair.

The owner's words: "the relief-0 vs relief-2.5 pair must differ only in SURFACE DETAIL, not in
flat brightness patches". That is exactly a frequency split of the difference image:

  PLATE metric  = low-frequency |dLuma| / Luma between the relief-0 and relief-2.5 frames
                  (32x32 blocks). Hard dark/light patches ARE low-frequency energy. -> must be ~0.
  RELIEF metric = high-frequency (8px residual) std ratio relief2.5 / relief0.
                  Surface detail IS high-frequency energy. -> must be clearly > 1.

Usage: gpbrf_plate_metrics.py <dir-with-legacy_r0.png legacy_r25.png fixed_r0.png fixed_r25.png>
"""
import sys
import os
import numpy as np
from PIL import Image


def luma(p):
    a = np.asarray(Image.open(p).convert('RGB'), dtype=np.float32)
    return a[..., 0] * 0.299 + a[..., 1] * 0.587 + a[..., 2] * 0.114


def box(x, k):
    h, w = x.shape
    h2, w2 = h // k * k, w // k * k
    return x[:h2, :w2].reshape(h2 // k, k, w2 // k, k).mean(axis=(1, 3))


def hf(x, k=8):
    h2, w2 = x.shape[0] // k * k, x.shape[1] // k * k
    return (x[:h2, :w2] - np.kron(box(x, k), np.ones((k, k)))).std()


def pair(p0, p25, label):
    a, b = luma(p0), luma(p25)
    if a.shape != b.shape:
        print(f"{label:14s} SHAPE MISMATCH {a.shape} vs {b.shape}")
        return None
    A, B = box(a, 32), box(b, 32)
    m = A > 8  # ignore letterbox / black
    rel = np.abs(B - A) / np.maximum(A, 1e-3)
    r = dict(lf_mean=rel[m].mean() * 100,
             lf_p95=np.percentile(rel[m], 95) * 100,
             lf_p99=np.percentile(rel[m], 99) * 100,
             hf_ratio=hf(b) / max(hf(a), 1e-6),
             luma0=a.mean(), luma25=b.mean())
    print(f"{label:14s} PLATE(low-freq |dL|/L): mean {r['lf_mean']:6.2f}%  p95 {r['lf_p95']:6.2f}%  "
          f"p99 {r['lf_p99']:6.2f}%   |   RELIEF(high-freq std ratio): {r['hf_ratio']:5.3f}   "
          f"|  mean luma {r['luma0']:6.2f} -> {r['luma25']:6.2f}")
    return r


d = sys.argv[1] if len(sys.argv) > 1 else '.'
print("=== relief 0 -> relief 2.5, same boot, same vantage, same frame budget ===")
print("    PLATE  must go DOWN (flat brightness patches = the defect)")
print("    RELIEF must go UP   (surface detail = what the owner wants)")
print()
res = {}
for lbl, p0, p25 in (("LEGACY", "legacy_r0.png", "legacy_r25.png"),
                     ("FIXED", "fixed_r0.png", "fixed_r25.png")):
    f0, f25 = os.path.join(d, p0), os.path.join(d, p25)
    if os.path.exists(f0) and os.path.exists(f25):
        res[lbl] = pair(f0, f25, lbl)
    else:
        print(f"{lbl:14s} MISSING ({p0} / {p25})")

# Owner's Honor reference pair, if it is still archived next door.
ref = os.path.join(os.path.dirname(d.rstrip('/')), 'relief_ab')
if os.path.exists(os.path.join(ref, 'R0.png')):
    print()
    pair(os.path.join(ref, 'R0.png'), os.path.join(ref, 'R25.png'), "HONOR(owner)")

if 'LEGACY' in res and 'FIXED' in res and res['LEGACY'] and res['FIXED']:
    L, F = res['LEGACY'], res['FIXED']
    print()
    print(f"VERDICT: plate low-freq mean {L['lf_mean']:.2f}% -> {F['lf_mean']:.2f}% "
          f"({L['lf_mean'] / max(F['lf_mean'], 1e-6):.1f}x reduction), "
          f"p95 {L['lf_p95']:.2f}% -> {F['lf_p95']:.2f}%; "
          f"relief high-freq ratio {L['hf_ratio']:.3f} -> {F['hf_ratio']:.3f}")
    ok = F['lf_mean'] < L['lf_mean'] and F['hf_ratio'] >= L['hf_ratio'] - 0.02
    print("GATE: " + ("PASS — less flat-brightness change, no loss of surface detail"
                      if ok else "FAIL — the fix did not reduce the plate metric"))
