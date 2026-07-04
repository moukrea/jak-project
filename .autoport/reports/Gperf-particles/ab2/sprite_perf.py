import re, statistics as st
LOG="/home/emeric/code/jak-project/.autoport/reports/Gperf-particles/ab2/ab2-logcat.txt"
WINDOWS=[("A","02:03:52","02:05:22"),("C","02:05:53","02:07:40"),("B","02:08:06","02:09:42"),("A2","02:10:06","02:10:51")]
def ts(l):
    m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)',l); return m.group(1) if m else None
lines=open(LOG,errors='replace').read().splitlines()
def med(x): return round(st.median(x),2) if x else None
for name,s,e in WINDOWS:
    sprite_ms=[]; sprite_dr=[]; sprite_tri=[]
    for ln in lines:
        t=ts(ln)
        if t is None or not (s<=t<=e): continue
        body=re.sub(r'^.*GK_STDERR\( *\d+\): ','',ln)
        m=re.match(r'\s*([\d.]+)ms (\d+)dr (\d+)tri \[66\] sprite\s*$',body)
        if m:
            sprite_ms.append(float(m.group(1))); sprite_dr.append(int(m.group(2))); sprite_tri.append(int(m.group(3)))
    print(f"WINDOW {name}: sprite[66] bucket  n={len(sprite_ms)}  ms median={med(sprite_ms)}  draws median={med(sprite_dr)}  tri median={med(sprite_tri)}")
    # show distinct draw counts
    from collections import Counter
    print(f"          draw-count distribution: {dict(Counter(sprite_dr))}")
