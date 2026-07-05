#!/usr/bin/env python3
"""Synthesize a deterministic pad_replay .inputs clip for the Gperf-particles2
moving-gameplay capture: Jak walks in bursts while the camera pans continuously,
so the whole TOD scene (trees/terrain/NPCs) sweeps through view AND Jak's merc
model stays on screen — exercising tie/tfrag/shrub AND merc-mod every frame.

Uses the pad path (CPadGetData tap), so it does NOT contend for the kernel
ListenerFunction trampoline that debug.opengoal.tod.fast needs — the fast clock
and the motion run together cleanly.

Format (game/system/pad_replay.cpp): 64-byte little-endian Header
  magic[8]="OGPADRP1", version u32=2, record_size u32=6, seed u32=0x0AD12345,
  reserved0 u32=0, anchor_frame i64=0, fingerprint[32]=0
then N x 6-byte PadRecord {button0 u16, leftx u8, lefty u8, rightx u8, righty u8},
neutral axis = 127, no buttons (button0=0) so nothing jumps/attacks.

record[i] is applied at the i-th gameplay logic frame after Jak spawns (anchor).
"""
import argparse, struct

NEUTRAL = 127


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    # Long + PERIODIC so it NEVER exhausts and there is motion at ANY offset — robust
    # whether pad_replay indexes from Jak-spawn (anchored) or from boot (legacy). 12000
    # logic frames ~= 3.3 min, longer than any boot + capture.
    ap.add_argument("--frames", type=int, default=12000)
    ap.add_argument("--pan", type=int, default=48,
                    help="camera-orbit magnitude added to rightx (0..127)")
    ap.add_argument("--walk", type=int, default=70,
                    help="forward magnitude subtracted from lefty during bursts")
    args = ap.parse_args()

    recs = bytearray()
    for i in range(args.frames):
        button0 = 0
        leftx = NEUTRAL
        lefty = NEUTRAL
        rightx = NEUTRAL
        righty = NEUTRAL

        # Camera orbit: pan one way then reverse every 600 frames (~10s), so the
        # camera continuously sweeps the whole scene back and forth (all trees/
        # terrain/NPCs pass through view). Continuous -> smooth motion, never a
        # pop false-fire. Periodic -> motion regardless of replay start offset.
        rightx = NEUTRAL + (args.pan if (i // 600) % 2 == 0 else -args.pan)

        # Forward walk in short bursts: ~1s walk every ~5s. Jak takes a few steps
        # (satisfies "Jak moving") without wandering far. Camera-relative, so with
        # the orbit he drifts gently around the spawn area.
        if (i % 300) < 60:
            lefty = NEUTRAL - args.walk

        recs += struct.pack("<HBBBB", button0, leftx, lefty, rightx, righty)

    header = struct.pack("<8sIIIIq32s",
                         b"OGPADRP1", 2, 6, 0x0AD12345, 0, 0, b"\x00" * 32)
    assert len(header) == 64, len(header)
    with open(args.out, "wb") as f:
        f.write(header)
        f.write(recs)
    print(f"wrote {args.out}: {args.frames} frames, {64 + len(recs)} bytes "
          f"(pan={args.pan} walk={args.walk})")


if __name__ == "__main__":
    main()
