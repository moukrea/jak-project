#!/usr/bin/env python3
"""Synthesize a pad_replay v2 .inputs demo that performs the LONG JUMP (roll + jump:
run forward, tap R1 -> target-wheel, hold X -> target-wheel-flip) three times, in three
different stick directions (up/down/left) so at least one leg has clean runway wherever
game-start spawns. Used by hd3_x86_longjump_ab.sh for the defect-7 enhanced ON/OFF A/B.

Format facts (game/system/pad_replay.cpp / .h, verified 2026-08-04):
  Header (64B): magic "OGPADRP1", u32 version=2, u32 record_size=6, u32 seed,
                u32 reserved0, i64 anchor_frame, u8 fingerprint[32].
                Replay validates ONLY magic + record_size.
  Records: dense per-logic-frame 6B: u16 button0, u8 leftx, lefty, rightx, righty.
  Index = logic_frame - anchor(latched at *target* spawn). Neutral analog = 127.
  button0 is ACTIVE-HIGH (libpad.cpp:91: button0 |= pressed<<i), bits per
  input_bindings.h ButtonIndex: L2=8 R2=9 L1=10 R1=11 TRIANGLE=12 CIRCLE=13
  CROSS=14 SQUARE=15.
"""
import struct, sys

R1 = 1 << 11
X  = 1 << 14
NEUT = (0, 127, 127, 127, 127)

frames = []
def hold(n, button0=0, lx=127, ly=127, rx=127, ry=127):
    frames.extend([(button0, lx, ly, rx, ry)] * n)

def combo(lx, ly):
    hold(70, 0, lx, ly)              # run to build stick0-speed (can-wheel? needs motion)
    hold(8, R1, lx, ly)              # tap R1 while running -> target-wheel (roll)
    hold(4, 0, lx, ly)               # release gap
    hold(40, X, lx, ly)              # hold X through the roll -> gate at target.gc:1832
                                     # (cpad-pressed? x) fires target-wheel-flip
    hold(110, 0, lx, ly)             # flight + landing, stick held
    hold(60)                         # settle neutral

def owner_combo(lx, ly, gap):
    # OWNER'S EXACT MOVE (morning verdict 2026-08-04): RUNNING FORWARD + R1/R2 + jump,
    # buttons effectively held together ("le saut est annulé"). gap = ticks between the
    # R1 press and X joining (0 = same tick, 3 = near-simultaneous human press).
    hold(70, 0, lx, ly)              # run forward
    if gap:
        hold(gap, R1, lx, ly)        # R1 lands first...
    hold(40, R1 | X, lx, ly)         # ...X joins, BOTH HELD while still running
    hold(110, 0, lx, ly)             # flight + landing
    hold(60)                         # settle

def duck_high_jump():
    # owner's words were "R1/R2 + saut" — also cover the STANDING crouch jump:
    # duck-stance (R1 held, stick neutral) + X -> target-high-jump 'duck (target.gc:758-760)
    hold(30)                         # stand still
    hold(30, R1)                     # hold R1 -> target-duck-stance
    hold(12, R1 | X)                 # X while ducked (stick0-speed == 0) -> high jump
    hold(28, R1)                     # keep duck held through takeoff
    hold(120)                        # flight + landing
    hold(60)                         # settle

HEAD = int(sys.argv[2]) if len(sys.argv) > 2 else 600
hold(HEAD)                           # post-anchor settle (spawn blackout / camera intro; sized by
                                     # the caller to cover goalc probe installation under OG_F1_WARP)
combo(127, 0)                        # leg 1: stick full up
combo(127, 255)                      # leg 2: stick full down
combo(0, 127)                        # leg 3: stick full left
duck_high_jump()                     # leg 4: standing crouch jump
owner_combo(127, 0, 3)               # leg 5: OWNER combo, near-simultaneous R1 then +X, running up
owner_combo(127, 255, 0)             # leg 6: OWNER combo, same-tick R1+X, running down
hold(300)                            # tail

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/hd3_longjump.inputs"
with open(out, "wb") as f:
    f.write(struct.pack("<8sIIIIq32s", b"OGPADRP1", 2, 6, 0x1234, 0, 0, b"\x00" * 32))
    for b0, lx, ly, rx, ry in frames:
        f.write(struct.pack("<HBBBB", b0, lx, ly, rx, ry))
print(f"{out}: {len(frames)} frames ({len(frames)/60:.1f}s), 3 tap long-jump combos + 1 duck high jump + 2 OWNER held-R1+X combos")
