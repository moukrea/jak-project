#!/usr/bin/env python3
"""Synthesize the x86 LOCOMOTION DRIVE for the secondary-motion legs.

The device leg drives Jak with `setprop debug.opengoal.cpad_inject` (android_input_audio.cpp).
That path does not exist on desktop — `cpad_inject` is an Android-only TU — so the x86 leg uses
the only working desktop route: a hand-synthesized pad_replay v2 `.inputs` file armed with
`OG_PAD_REPLAY_REPLAY`. Same intent as the device's box path: HELD stick, so the RUN animation
actually plays and the chains' own anchors are driven, rather than a transform that slides.

Format (game/system/pad_replay.cpp, unchanged): 64B header `<8sIIIIq32s` magic "OGPADRP1",
version 2, record_size 6; then dense per-logic-frame `<HBBBB` = u16 button0 (ACTIVE-HIGH,
ButtonIndex bits L1=10 R1=11 CROSS=14) + leftx/lefty/rightx/righty, neutral 127, 0 = up/left.
The replay index anchors at *target* spawn, so HEAD covers the warp/blackout.
"""
import struct
import sys

R1 = 1 << 11
X = 1 << 14

frames = []


def hold(n, button0=0, lx=127, ly=127, rx=127, ry=127):
    frames.extend([(button0, lx, ly, rx, ry)] * n)


def box_leg(lx, ly, run=720):
    """One side of the device leg's box path: 12 s of HELD stick at 60 Hz, then a short settle.

    The settle is not padding — it is the only stretch in the whole drive where the actor is
    still while the chains are not, which is what `idledrift` and the settle time are read on.
    """
    hold(run, 0, lx, ly)
    hold(90)


def jump(lx, ly):
    """A jump while running. Landing is the biggest single anchor acceleration a chain sees, and
    it is where the owner looks first ('en courant les cheveux de Jak ne bougent pas')."""
    hold(120, 0, lx, ly)
    hold(10, X, lx, ly)
    hold(70, 0, lx, ly)


def spin():
    """Camera-relative direction changes with the stick held: the turn is what drives a chain
    whose anchor is a thigh or a collar rather than the head."""
    for lx, ly in ((127, 0), (0, 0), (0, 127), (0, 255), (127, 255), (255, 255), (255, 127), (255, 0)):
        hold(45, 0, lx, ly)


HEAD = int(sys.argv[2]) if len(sys.argv) > 2 else 900   # ~15 s: warp delay + spawn blackout
hold(HEAD)
box_leg(127, 0)      # forward
box_leg(0, 127)      # left
box_leg(127, 255)    # back
box_leg(255, 127)    # right
jump(127, 0)
spin()
jump(0, 127)
hold(600)            # tail: a long undriven stretch — the calm ceilings live here

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/physics_drive.inputs"
with open(out, "wb") as f:
    f.write(struct.pack("<8sIIIIq32s", b"OGPADRP1", 2, 6, 0x1234, 0, 0, b"\x00" * 32))
    for b0, lx, ly, rx, ry in frames:
        f.write(struct.pack("<HBBBB", b0, lx, ly, rx, ry))
print("%s: %d frames (%.1fs) — 4x12s held-stick box path, 2 jumps, an 8-way turn, %ds tail"
      % (out, len(frames), len(frames) / 60.0, 600 // 60))
