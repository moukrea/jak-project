#!/usr/bin/env python3
"""Gfixed-tick-interpolation — demo de manette MINIMALE : ouvrir le menu de pause.

But unique : faire tourner `init-game-options` (engine/ui/progress/progress.gc:371), qui
n'est atteint QU'A LA CREATION du processus progress — donc quand le menu s'ouvre, jamais
au demarrage. C'est la seule facon d'obtenir la TRACE D'EXECUTION du cablage de la ligne
FIXED TIMESTEP (`[FIXEDTICK-MENU] row wired: idx=N len=M`) au lieu d'affirmer qu'elle est
bien posee — une ligne de menu non cablee est un interrupteur qui ne fait RIEN, et c'est
exactement le faux vert que ce lot doit eviter.

Meme format que gft_gen_jump_inputs.py (pad_replay.cpp). START = bit 3 (ButtonIndex,
game/system/hid/input_bindings.h:29).
"""
import argparse, struct

NEUTRAL = 127
START = 1 << 3

ap = argparse.ArgumentParser()
ap.add_argument("out")
ap.add_argument("--settle", type=int, default=180)
ap.add_argument("--press", type=int, default=8)
ap.add_argument("--hold", type=int, default=400)
a = ap.parse_args()

hdr = struct.pack("<8sIIIIq32s", b"OGPADRP1", 2, 6, 0x0AD12345, 0, 0, b"\0" * 32)
assert len(hdr) == 64
recs = bytearray()
for _ in range(a.settle):
    recs += struct.pack("<HBBBB", 0, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL)
for _ in range(a.press):
    recs += struct.pack("<HBBBB", START, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL)
for _ in range(a.hold):
    recs += struct.pack("<HBBBB", 0, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL)
open(a.out, "wb").write(hdr + bytes(recs))
n = len(recs) // 6
print(f"{a.out}: {n} frames (settle {a.settle}, START {a.press}, hold {a.hold}) dernier tick {n-1}")
