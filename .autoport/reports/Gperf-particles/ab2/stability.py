import re
LOG="/home/emeric/code/jak-project/.autoport/reports/Gperf-particles/ab2/ab2-logcat.txt"
PID="5443"
WINDOWS=[("A","02:03:52","02:05:22"),("C","02:05:53","02:07:40"),("B","02:08:06","02:09:42"),("A2","02:10:06","02:10:51")]
def ts(l):
    m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)',l); return m.group(1) if m else None
lines=open(LOG,errors='replace').read().splitlines()
pats={
 'sig4/6/11 (our PID)': re.compile(r'sig(nal)? (4|6|11)\b'),
 'SIGSEGV/SIGILL/SIGABRT': re.compile(r'SIGSEGV|SIGILL|SIGABRT|SIGBUS'),
 'send_chain pending': re.compile(r'send_chain called with pending data'),
 'A37-CHAIN-LOOP': re.compile(r'A37-CHAIN-LOOP'),
 'A42 precopy skip': re.compile(r'A42-CHAIN-PRECOPY skip'),
 'GL error': re.compile(r'GL_?ERROR|glGetError|GL error',re.I),
 'Failed to find texture': re.compile(r'Failed to find texture'),
}
# whole-run tally + per-window
print("=== WHOLE RUN (all lines) ===")
for name,p in pats.items():
    hits=[l for l in lines if p.search(l)]
    # for sig, restrict to our PID
    if 'sig' in name.lower() or 'SIG' in name:
        hits=[l for l in hits if PID in l]
    print(f"  {name:26s}: {len(hits)}")
    for h in hits[:3]:
        print("       >", h[:140])
print()
for name,s,e in WINDOWS:
    print(f"=== WINDOW {name} [{s}-{e}] ===")
    wl=[l for l in lines if (ts(l) and s<=ts(l)<=e)]
    for pn,p in pats.items():
        hits=[l for l in wl if p.search(l)]
        if 'sig' in pn.lower() or 'SIG' in pn:
            hits=[l for l in hits if PID in l]
        if hits: print(f"  {pn}: {len(hits)}")
    print(f"  (window line count={len(wl)})")
