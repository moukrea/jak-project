import re, statistics as st
LOG="/home/emeric/code/jak-project/.autoport/reports/Gperf-particles/ab2/ab2-logcat.txt"

# window boundaries (device-local HH:MM:SS on 07-04)
WINDOWS=[
 ("A",  "02:03:52","02:05:22"),
 ("C",  "02:05:53","02:07:40"),
 ("B",  "02:08:06","02:09:42"),
 ("A2", "02:10:51+","x"),  # A2 special: fill below
]
# A2 window: start 02:10:xx after 12s wait; markers say A2_START then 45s. Use 02:10:00-02:10:51.
WINDOWS=[
 ("A",  "02:03:52","02:05:22"),
 ("C",  "02:05:53","02:07:40"),
 ("B",  "02:08:06","02:09:42"),
 ("A2", "02:10:06","02:10:51"),
]
def ts(line):
    m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)', line)
    return m.group(1) if m else None
def inwin(t,s,e): return t is not None and s<=t<=e

lines=open(LOG,encoding='utf-8',errors='replace').read().splitlines()

def med(x): return round(st.median(x),2) if x else None
def mn(x): return round(min(x),2) if x else None
def mx(x): return round(max(x),2) if x else None

for name,s,e in WINDOWS:
    print("="*70)
    print(f"WINDOW {name}  [{s} - {e}]")
    fps=[]; scales=[]; scalepairs=[]
    # SPART fields (only full-data frames: sprite buckets>0)
    spart={k:[] for k in ['3d_ms','2d_ms','2d_it','launch_ms','adgif_ms','sbuckets','quads','directflush','glbuild','glflush','idle','pace','n','tie_i','tie_ts','tie_cu','tie_ix']}
    render_ms=[]; buckets_ms=[]; pcrtc_ms=[]
    perfdumps=[]
    curperf=None
    for ln in lines:
        t=ts(ln)
        if not inwin(t,s,e): 
            # still may need to close a perf dump started in-window
            if curperf is not None and not inwin(t,s,e):
                pass
            continue
        if 'dyn-rs] state' in ln:
            m=re.search(r'avg-fps=([\d.]+) scale=(\d+)%',ln)
            if m:
                fps.append(float(m.group(1))); sc=int(m.group(2)); scales.append(sc)
                scalepairs.append((float(m.group(1)),sc))
        if 'A35-SPART' in ln and 'sprite buckets=' in ln:
            m=re.search(r'sprite buckets=(\d+)',ln)
            if m and int(m.group(1))>0:
                def g(pat,default=None):
                    mm=re.search(pat,ln); return float(mm.group(1)) if mm else default
                spart['3d_ms'].append(g(r'3d=([\d.]+)ms'))
                spart['2d_ms'].append(g(r'2d=([\d.]+)ms'))
                mit=re.search(r'2d=[\d.]+ms/\d+c/(\d+)it',ln); spart['2d_it'].append(int(mit.group(1)) if mit else 0)
                spart['launch_ms'].append(g(r'launch=([\d.]+)ms'))
                spart['adgif_ms'].append(g(r'adgif=([\d.]+)ms'))
                spart['sbuckets'].append(int(m.group(1)))
                spart['quads'].append(int(re.search(r'quads=(\d+)',ln).group(1)))
                spart['directflush'].append(int(re.search(r'directflush=(\d+)',ln).group(1)))
                spart['glbuild'].append(g(r'glbuild=([\d.]+)ms'))
                spart['glflush'].append(g(r'glflush=([\d.]+)ms'))
                spart['idle'].append(g(r'goal idle=([\d.]+)'))
                spart['pace'].append(g(r'pace=([\d.]+)'))
                spart['n'].append(int(re.search(r' n=(\d+)',ln).group(1)))
                spart['tie_i'].append(g(r'tie i=([\d.]+)'))
                spart['tie_ts'].append(g(r'ts=([\d.]+)'))
                spart['tie_cu'].append(g(r'cu=([\d.]+)'))
                spart['tie_ix'].append(g(r'ix=([\d.]+)'))
        if 'A35-RENDER frame=' in ln:
            m=re.search(r'render_ms=([\d.]+) buckets_ms=([\d.]+) pcrtc_ms=([\d.]+)',ln)
            if m:
                render_ms.append(float(m.group(1))); buckets_ms.append(float(m.group(2))); pcrtc_ms.append(float(m.group(3)))
    # scale report
    dscales=sorted(set(scales))
    print(f"  dyn-rs avg-fps: median={med(fps)} min={mn(fps)} max={mx(fps)}  (n={len(fps)})")
    print(f"  dyn-rs distinct scales: {dscales}")
    if dscales and (max(dscales)>40):
        print(f"  !!! SCALE ROSE ABOVE 40 -- fps/scale pairs over time:")
        for p in scalepairs: print("     ",p)
    print(f"  A35-RENDER render_ms: median={med(render_ms)} min={mn(render_ms)} max={mx(render_ms)}  (n={len(render_ms)})")
    print(f"  A35-RENDER buckets_ms median={med(buckets_ms)}  pcrtc_ms median={med(pcrtc_ms)}")
    print(f"  A35-SPART (full-data frames n={len(spart['sbuckets'])}):")
    for k in ['2d_ms','2d_it','launch_ms','adgif_ms','sbuckets','quads','directflush','glbuild','glflush','idle','pace','n','tie_i','tie_ts','tie_cu','tie_ix']:
        print(f"      {k:12s} median={med(spart[k])} min={mn(spart[k])} max={mx(spart[k])}")

# 2 A35-PERF dumps per window
print("\n"+"#"*70)
print("A35-PERF dumps (2 per window, root + sprite bucket line)")
def perf_dumps_in(s,e,maxn=2):
    out=[]; cur=[]; capturing=False; curt=None
    for ln in lines:
        t=ts(ln)
        if 'A35-PERF frame=' in ln:
            if cur and curt and inwin(curt,s,e):
                out.append(cur)
                if len(out)>=maxn: return out
            cur=[ln]; curt=t; capturing=True
        elif capturing and 'A35-' in ln and 'A35-PERF' not in ln:
            if cur and curt and inwin(curt,s,e): out.append(cur)
            if len(out)>=maxn: return out
            capturing=False; cur=[]
        elif capturing:
            cur.append(ln)
    if cur and curt and inwin(curt,s,e) and len(out)<maxn: out.append(cur)
    return out

for name,s,e in WINDOWS:
    print(f"\n--- WINDOW {name} A35-PERF ---")
    dumps=perf_dumps_in(s,e,2)
    for d in dumps:
        for ln in d:
            txt=re.sub(r'.*A35-PERF ','',ln); txt=re.sub(r'.*GK_STDERR\( *\d+\): ','',txt)
            # keep frame line, root, and any sprite bucket
            keep = ('frame=' in ln) or ('root' in ln) or ('sprite' in ln.lower()) or ('sprite-glow' in ln) or ('buckets\n' in ln)
        # print frame + root + sprite bucket lines
        for ln in d:
            body=re.sub(r'^.*GK_STDERR\( *\d+\): ','',ln)
            if 'frame=' in body or body.strip().endswith('root') or 'sprite' in body.lower() or body.strip().endswith('buckets'):
                print("   ",body)
