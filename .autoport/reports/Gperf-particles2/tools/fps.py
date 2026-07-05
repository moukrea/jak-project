#!/usr/bin/env python3
"""Median fps / render_ms / scale over a HH:MM:SS logcat window (from the
dyn-rs avg-fps + A35-RENDER lines). Reused from the round4 mfps parser."""
import re, statistics as st, sys

log, s, e = sys.argv[1], sys.argv[2], sys.argv[3]
L = open(log, errors="replace").read().splitlines()


def t(l):
    m = re.match(r"\d\d-\d\d (\d\d:\d\d:\d\d)", l)
    return m.group(1) if m else None


fps, rm, idle, sc = [], [], [], []
for ln in L:
    if not (s <= (t(ln) or "") <= e):
        continue
    m = re.search(r"avg-fps=([\d.]+) scale=(\d+)%", ln)
    if m and "dyn-rs] state" in ln:
        fps.append(float(m.group(1)))
        sc.append(int(m.group(2)))
    m = re.search(r"render_ms=([\d.]+)", ln)
    if m and "A35-RENDER" in ln:
        rm.append(float(m.group(1)))


def md(x):
    return round(st.median(x), 2) if x else None


print(f"  FPS median={md(fps)} (min {round(min(fps),1) if fps else 0}, n={len(fps)}) "
      f"scale={sorted(set(sc))} render_ms={md(rm)}")
