#!/usr/bin/env python3
"""Gfixed-tick-interpolation — demo de manette : COURSE puis SAUT, repetee.

Ce que la phase demande de prouver : « la meme sequence d'entrees, rejouee, doit
produire les MEMES trajectoires a 25, 60, 90 et 120 fps ». Il faut donc une sequence
qui contienne un saut FRANC, dont la hauteur et la longueur se lisent sans ambiguite
dans la position de Jak.

Format lu par game/system/pad_replay.cpp (:35-45, :56-64) :
  en-tete 64 o : magic "OGPADRP1", version u32, record_size u32, seed u32, reserved u32,
                 anchor_frame i64, fingerprint[32]
  puis N x 6 o : button0 u16, leftx u8, lefty u8, rightx u8, righty u8  (127 = repos)
button0 est ACTIF-HAUT ; CROIX = bit 14 (ButtonIndex, pad_replay.h).

L'index 0 est la premiere frame de LOGIQUE apres l'apparition de Jak (l'ancre), donc le
demarrage et le chargement — de duree variable — sont absorbes et n'entrent pas dans la
comparaison entre framerates.

DECOUPAGE, publie ici pour que l'analyse n'ait pas a le deviner :
  [0, settle)                      repos : Jak retombe au sol, la camera se pose
  puis, REPETE `jumps` fois :
    [+0, +accel)                   stick a fond vers l'avant : montee en vitesse
    [+accel, +accel+press)         CROIX maintenue, stick toujours a fond
    [+accel+press, +cycle)         stick a fond, croix relachee : arc + retombee
"""

import argparse
import struct

NEUTRAL = 127
FORWARD = 0          # lefty 0 == avant
CROSS = 1 << 14


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--settle", type=int, default=300)
    ap.add_argument("--accel", type=int, default=110)
    ap.add_argument("--press", type=int, default=6)
    ap.add_argument("--cycle", type=int, default=260)
    ap.add_argument("--jumps", type=int, default=3)
    ap.add_argument("--nostick", action="store_true",
                    help="saut DEBOUT : stick au repos. La direction de course de Jak est "
                         "relative a la CAMERA ; des que le stick pousse, une difference "
                         "de 0,01 deg sur la pose de camera entre en boucle et s'amplifie. "
                         "Sans stick, la trajectoire est purement verticale et ne depend "
                         "plus que de l'integrateur — c'est le test STRICT du pas de temps.")
    a = ap.parse_args()

    hdr = struct.pack("<8sIIIIq32s", b"OGPADRP1", 2, 6, 0x0AD12345, 0, 0, b"\0" * 32)
    assert len(hdr) == 64, len(hdr)

    recs = bytearray()
    windows = []
    for _ in range(a.settle):
        recs += struct.pack("<HBBBB", 0, NEUTRAL, NEUTRAL, NEUTRAL, NEUTRAL)
    fwd = NEUTRAL if a.nostick else FORWARD
    t = a.settle
    for _ in range(a.jumps):
        for _ in range(a.accel):
            recs += struct.pack("<HBBBB", 0, NEUTRAL, fwd, NEUTRAL, NEUTRAL)
        t0 = t + a.accel                      # tick ou la croix passe a 1
        for _ in range(a.press):
            recs += struct.pack("<HBBBB", CROSS, NEUTRAL, fwd, NEUTRAL, NEUTRAL)
        for _ in range(a.cycle - a.accel - a.press):
            recs += struct.pack("<HBBBB", 0, NEUTRAL, fwd, NEUTRAL, NEUTRAL)
        windows.append((t0, t + a.cycle))
        t += a.cycle

    with open(a.out, "wb") as f:
        f.write(hdr)
        f.write(recs)
    print("GFTDEMO out=%s ticks=%d sauts=%d fenetres=%s"
          % (a.out, t, a.jumps, ";".join("%d-%d" % w for w in windows)))


if __name__ == "__main__":
    main()
