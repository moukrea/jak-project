import re, statistics as st
LOG="/home/emeric/code/jak-project/.autoport/reports/Gperf-particles/round4/ab-logcat.txt"
WINDOWS=[("A","12:41:54","12:43:24"),("C","12:43:44","12:45:14"),
         ("B","12:45:37","12:47:07"),("A2","12:47:26","12:48:21")]
def ts(l):
    m=re.match(r'\d\d-\d\d (\d\d:\d\d:\d\d)',l); return m.group(1) if m else None
def inw(t,s,e): return t is not None and s<=t<=e
lines=open(LOG,encoding='utf-8',errors='replace').read().splitlines()
def med(x): return round(st.median(x),2) if x else None
def mn(x): return round(min(x),2) if x else None
def mx(x): return round(max(x),2) if x else None
res={}
for name,s,e in WINDOWS:
    fps=[];scales=[];r_ms=[];b_ms=[]
    sp={k:[] for k in['2d_ms','2d_it','launch_ms','adgif_ms','sbuckets','quads','glbuild','glflush','idle','pace']}
    spr_ms=[];spr_dr=[]
    for ln in lines:
        t=ts(ln)
        if not inw(t,s,e): continue
        if 'dyn-rs] state' in ln:
            m=re.search(r'avg-fps=([\d.]+) scale=(\d+)%',ln)
            if m: fps.append(float(m.group(1)));scales.append(int(m.group(2)))
        if 'A35-SPART' in ln and 'sprite buckets=' in ln:
            def g(p):
                mm=re.search(p,ln);return float(mm.group(1)) if mm else None
            if (re.search(r'sprite buckets=(\d+)',ln)):
                sp['2d_ms'].append(g(r'2d=([\d.]+)ms'))
                mit=re.search(r'2d=[\d.]+ms/\d+c/(\d+)it',ln);sp['2d_it'].append(int(mit.group(1)) if mit else 0)
                sp['launch_ms'].append(g(r'launch=([\d.]+)ms'))
                sp['adgif_ms'].append(g(r'adgif=([\d.]+)ms'))
                sp['sbuckets'].append(int(re.search(r'sprite buckets=(\d+)',ln).group(1)))
                sp['quads'].append(int(re.search(r'quads=(\d+)',ln).group(1)))
                sp['glbuild'].append(g(r'glbuild=([\d.]+)ms'))
                sp['glflush'].append(g(r'glflush=([\d.]+)ms'))
                sp['idle'].append(g(r'goal idle=([\d.]+)'))
                sp['pace'].append(g(r'pace=([\d.]+)'))
        if 'A35-RENDER frame=' in ln:
            m=re.search(r'render_ms=([\d.]+) buckets_ms=([\d.]+)',ln)
            if m: r_ms.append(float(m.group(1)));b_ms.append(float(m.group(2)))
        body=re.sub(r'^.*GK_STDERR *: ','',ln)
        m=re.match(r'\s*([\d.]+)ms (\d+)dr \d+tri \[66\] sprite\s*$',body)
        if m: spr_ms.append(float(m.group(1)));spr_dr.append(int(m.group(2)))
    res[name]=dict(fps=fps,scales=scales,r_ms=r_ms,b_ms=b_ms,sp=sp,spr_ms=spr_ms,spr_dr=spr_dr)
    print("="*64)
    print(f"WINDOW {name} [{s}-{e}]")
    print(f"  dyn-rs avg-fps  median={med(fps)} min={mn(fps)} max={mx(fps)} (n={len(fps)})")
    print(f"  distinct scales: {sorted(set(scales))}")
    print(f"  A35-RENDER render_ms median={med(r_ms)}  buckets_ms median={med(b_ms)} (n={len(r_ms)})")
    print(f"  A35-SPART (n={len(sp['sbuckets'])}): 2d_ms={med(sp['2d_ms'])} 2d_it={med(sp['2d_it'])} launch_ms={med(sp['launch_ms'])} adgif_ms={med(sp['adgif_ms'])}")
    print(f"            sbuckets={med(sp['sbuckets'])} quads={med(sp['quads'])} glbuild={med(sp['glbuild'])} glflush={med(sp['glflush'])} idle={med(sp['idle'])} pace={med(sp['pace'])}")
    print(f"  sprite[66] bucket ms median={med(spr_ms)} draws median={med(spr_dr)} (n={len(spr_ms)})")
A=med(res['A']['fps']);B=med(res['B']['fps']);C=med(res['C']['fps']);A2=med(res['A2']['fps'])
print("\n"+"#"*64)
print(f"HEADLINE  A(all-old)={A}  C(round3)={C}  B(all-fix)={B}  A2(revert)={A2}")
if A and B:
    need=max(A*1.20,A+5.0)
    print(f"  A->B delta = +{round(B-A,2)}fps (+{round((B-A)/A*100,1)}%)")
    print(f"  gate need >= {round(need,2)} (max(+20%,+5fps));  B={B} -> {'PASS' if B+1e-9>=need else 'FAIL'}")
if C and B: print(f"  round-4 marginal (C->B) = +{round(B-C,2)}fps")
