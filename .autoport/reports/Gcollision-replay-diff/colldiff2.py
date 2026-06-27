#!/usr/bin/env python3
# Gcollision-replay-diff: tolerance-aware x86-vs-arm64 collision-trace comparator.
# Separates inherent x86(SSE)/arm64(NEON) FP last-ULP noise from a GROSS collision
# divergence (the real arm64 bug: wrong push-out / saturated velocity / frozen pos /
# flipped normal / wrong control state). Reports, per field, the first frame it
# diverges beyond a NOISE tolerance and beyond a GROSS threshold, plus the earliest
# gross divergence overall and trajectory context.
import sys, struct, math

FIELDS = [
    (0,   16, "trans",             "vec"),   # position, GOAL units (4096 = 1m)
    (16,  16, "quat",              "vec"),   # orientation
    (32,  16, "transv",            "vec"),   # velocity
    (48,  16, "rotv",              "vec"),   # angular velocity
    (64,   8, "status",            "u64"),   # collision/control flags (exact)
    (72,  16, "local-normal",      "vec"),
    (88,  16, "surface-normal",    "vec"),
    (104, 16, "poly-normal",       "vec"),
    (120, 16, "ground-poly-normal","vec"),
    (136, 16, "ground-touch-point","vec"),
    (152,  4, "ground-impact-vel", "f32"),
    (156,  4, "surface-angle",     "f32"),
    (160,  4, "poly-angle",        "f32"),
    (164,  4, "touch-angle",       "f32"),
    (168,  4, "coverage",          "f32"),
]
# per-field-kind tolerances
NOISE = {"pos": 8.0, "vel": 8.0, "norm": 1e-3, "ang": 1e-2}   # below = FP noise
GROSS = {"pos": 2048.0, "vel": 512.0, "norm": 0.1, "ang": 1.0} # above = real bug
def kindof(name):
    if name in ("trans","ground-touch-point"): return "pos"
    if name in ("transv","rotv"): return "vel"
    if "normal" in name: return "norm"
    if name=="ground-impact-vel": return "vel"
    return "ang"

def load(path):
    out={}
    for ln in open(path,"r",errors="replace"):
        if not ln.startswith("ci frame="): continue
        sp=ln.split()
        try:
            fr=int(sp[1].split("=")[1]); b=bytes(int(x,16) for x in sp[2:])
        except Exception: continue
        if len(b)>=172: out[fr]=b
    return out

def vecf(b,off): return struct.unpack("<4f",b[off:off+16])
def f32(b,off): return struct.unpack("<f",b[off:off+4])[0]
def maxabsdiff(a,b,off,length):
    if length>=16: return max(abs(x-y) for x,y in zip(vecf(a,off),vecf(b,off)))
    return abs(f32(a,off)-f32(b,off))

def fmt(b,off,length,kind):
    if kind=="vec": return "["+", ".join(f"{x:.5g}" for x in vecf(b,off))+"]"
    if kind=="f32": return f"{f32(b,off):.6g}"
    if kind=="u64": return "0x"+b[off:off+length][::-1].hex()
    return b[off:off+length].hex()

def main():
    x=load(sys.argv[1]); a=load(sys.argv[2])
    common=sorted(set(x)&set(a))
    print(f"x86 frames={len(x)}  arm frames={len(a)}  common={len(common)}")
    if not common: print("NO COMMON FRAMES"); sys.exit(1)
    print(f"common range {common[0]}..{common[-1]}\n")
    # bit-exact first divergence (reference)
    bitfirst=None; nbit=0
    for fr in common:
        if x[fr]==a[fr]: nbit+=1
        else: bitfirst=fr; break
    print(f"[bit-exact] first byte divergence: {'frame '+str(bitfirst) if bitfirst is not None else 'NONE (identical)'} ({nbit} frames bit-identical)")
    # per-field first noise-exceed and first gross-exceed
    print("\n[per-field] first frame exceeding NOISE / GROSS tolerance:")
    earliest_gross=(None,None)
    for off,length,name,kind in FIELDS:
        k=kindof(name); fn=None; fg=None; maxd=0.0
        for fr in common:
            if kind=="u64":
                d = 0.0 if x[fr][off:off+8]==a[fr][off:off+8] else 1e9
            else:
                d = maxabsdiff(x[fr],a[fr],off,length)
            maxd=max(maxd,d)
            if kind=="u64":
                if d>0 and fn is None: fn=fr
                if d>0 and fg is None: fg=fr
            else:
                if d>NOISE[k] and fn is None: fn=fr
                if d>GROSS[k] and fg is None: fg=fr
        gmark=""
        if fg is not None:
            if earliest_gross[0] is None or fg<earliest_gross[0]: earliest_gross=(fg,name)
            gmark=f"  GROSS@{fg}"
        print(f"  {name:20s} kind={k:4s} maxΔ={maxd:.4g}  noise>{NOISE.get(k,'-')}@{fn}{gmark}")
    print()
    if earliest_gross[0] is None:
        print("RESULT: NO GROSS DIVERGENCE — arm64 collision matches x86 within FP noise over all common frames")
        return
    gf,gname=earliest_gross
    print(f"RESULT: FIRST GROSS DIVERGENCE at logic frame {gf} in field '{gname}'")
    off,length,_,kind=[F for F in FIELDS if F[2]==gname][0]
    print(f"  x86={fmt(x[gf],off,length,kind)}")
    print(f"  arm={fmt(a[gf],off,length,kind)}")
    show=[f for f in common if gf-4<=f<=gf+4]
    print(f"\n  context '{gname}' frames {show[0]}..{show[-1]}:")
    for fr in show:
        mark=" <-- FIRST GROSS" if fr==gf else ""
        print(f"    f{fr}: x86={fmt(x[fr],off,length,kind)}  arm={fmt(a[fr],off,length,kind)}{mark}")
    # also show all fields at the gross frame
    print(f"\n  ALL fields at frame {gf}:")
    for off,length,name,kind in FIELDS:
        d = (0.0 if x[gf][off:off+8]==a[gf][off:off+8] else 1e9) if kind=="u64" else maxabsdiff(x[gf],a[gf],off,length)
        print(f"    {name:20s} Δ={d:.4g}  x86={fmt(x[gf],off,length,kind)}  arm={fmt(a[gf],off,length,kind)}")

if __name__=="__main__": main()
