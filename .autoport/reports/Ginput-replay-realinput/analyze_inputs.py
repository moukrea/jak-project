#!/usr/bin/env python3
# Analyze an OGPADRP1 pad-demo recording: count non-neutral frames.
# Header: 64 bytes. Record: 6 bytes = button0(u16 LE), leftx, lefty, rightx, righty (u8).
# Neutral = button0==0 and all four sticks==127.
import sys, struct

def main(path):
    with open(path, "rb") as f:
        data = f.read()
    if len(data) < 64:
        print(f"FILE TOO SHORT: {len(data)} bytes"); return 1
    magic = data[:8]
    version, rec_size, seed = struct.unpack_from("<III", data, 8)
    anchor = struct.unpack_from("<q", data, 24)[0]
    body = data[64:]
    n = len(body) // 6
    nn = 0
    first_nn = -1
    samples = []
    for i in range(n):
        b0, lx, ly, rx, ry = struct.unpack_from("<HBBBB", body, i*6)
        neutral = (b0 == 0 and lx == 127 and ly == 127 and rx == 127 and ry == 127)
        if not neutral:
            nn += 1
            if first_nn < 0:
                first_nn = i
            if len(samples) < 12:
                samples.append((i, b0, lx, ly, rx, ry))
    print(f"magic={magic!r} version={version} rec_size={rec_size} seed=0x{seed:08x} anchor={anchor}")
    print(f"FRAMES M={n}  NON-NEUTRAL N={nn}  ({(100.0*nn/n if n else 0):.1f}%)  first_nn={first_nn}")
    print(f"REAL INPUT CAPTURED: {nn}/{n}")
    for s in samples:
        print(f"  frame {s[0]}: button0=0x{s[1]:04x} lx={s[2]} ly={s[3]} rx={s[4]} ry={s[5]}")
    return 0

if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
