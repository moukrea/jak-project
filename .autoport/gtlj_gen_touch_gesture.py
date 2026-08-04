#!/usr/bin/env python3
"""Gtouch-longjump-regression: generate the owner's 3-finger long-jump gesture
as a touch_replay.txt script for TouchReplayPlayer (normalized coords).

Owner repro: run forward (left thumb holds the virtual stick), hold R1/R2
(the l1r1 pill), press X. Expected: target-wheel -> target-wheel-flip.
Observed by owner: target-duck-walk + plain target-jump.

Zone centres derive from TouchOverlayView.layoutControls() proportions at
2400x1080 (floors don't bind there):
  stick centre (0.155, 0.68); knob full deflection = 0.62*0.165h = 0.1023h
  l1r1 pill centre (0.9125, 0.1075)
  south/X centre (0.86, 0.8085)

Usage: gtlj_gen_touch_gesture.py OUT [reps] [variant]
  variant: owner  = stick full fwd, R1 held, X 160ms after R1 (default)
           half   = stick at ~55% deflection
           tapx   = R1 tap released before X
           latex  = X 400ms after R1
"""
import sys

STICK = (0.155, 0.68)
FWD_FULL = (0.155, 0.68 - 0.1023)
FWD_HALF = (0.155, 0.68 - 0.055)
L1R1 = (0.9125, 0.1075)
SOUTH = (0.86, 0.8085)


def rep(out, t0, variant, backward=False):
    fwd = FWD_HALF if variant == "half" else FWD_FULL
    if backward:
        # alternate run direction so Jak shuttles over the same runway stretch
        # instead of drifting off the geyser ledge rep after rep
        fwd = (fwd[0], STICK[1] + (STICK[1] - fwd[1]))
    e = out.append
    e((t0 + 0, "down", 0, *STICK))
    e((t0 + 50, "move", 0, STICK[0], (STICK[1] + fwd[1]) / 2))
    e((t0 + 100, "move", 0, *fwd))
    # hold with micro-jitter (real thumbs are never still)
    t = t0 + 200
    j = 0.002
    k = 0
    while t < t0 + 2400:
        e((t, "move", 0, fwd[0] + (j if k % 2 else -j), fwd[1]))
        k += 1
        t += 100
    r1_t = t0 + 1400
    e((r1_t, "down", 1, *L1R1))
    if variant == "tapx":
        e((r1_t + 120, "up", 1))
        e((r1_t + 200, "down", 2, *SOUTH))
        e((r1_t + 380, "up", 2))
    else:
        x_dt = 400 if variant == "latex" else 160
        e((r1_t + x_dt, "down", 2, *SOUTH))
        e((r1_t + x_dt + 200, "up", 2))
        e((r1_t + 900, "up", 1))
    e((t0 + 2500, "up", 0))


def main():
    outp = sys.argv[1]
    reps = int(sys.argv[2]) if len(sys.argv) > 2 else 5
    variant = sys.argv[3] if len(sys.argv) > 3 else "owner"
    evs = []
    for i in range(reps):
        rep(evs, i * 4200, variant, backward=(i % 2 == 1))
    evs.sort(key=lambda x: x[0])
    with open(outp, "w") as f:
        f.write(f"# gtlj gesture variant={variant} reps={reps}\n")
        for ev in evs:
            if ev[1] == "up":
                f.write(f"{ev[0]} up {ev[2]}\n")
            else:
                f.write(f"{ev[0]} {ev[1]} {ev[2]} {ev[3]:.4f} {ev[4]:.4f}\n")
    print(f"wrote {outp}: {len(evs)} events, {reps} reps, variant={variant}, "
          f"span {evs[-1][0]}ms")


if __name__ == "__main__":
    main()
