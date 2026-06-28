#!/usr/bin/env python3
# Ginput-replay-liverecord analyzer: parse a recorded pad_demo (.inputs v2) and
# report non-neutral capture + byte-match vs the KNOWN injected held state.
import struct, sys, os

BITS = {'select':0,'l3':1,'r3':2,'start':3,'up':4,'right':5,'down':6,'left':7,
        'l2':8,'r2':9,'l1':10,'r1':11,'triangle':12,'circle':13,'x':14,'cross':14,'square':15}

def expected_from_inject(inject):
    b0 = 0; lx=ly=rx=ry=127
    for tok in inject.split():
        for k,dstname in (('lx=','lx'),('ly=','ly'),('rx=','rx'),('ry=','ry')):
            if tok.startswith(k):
                v=max(0,min(255,int(tok[len(k):])))
                if dstname=='lx': lx=v
                elif dstname=='ly': ly=v
                elif dstname=='rx': rx=v
                else: ry=v
                break
        else:
            if tok in BITS: b0 |= (1<<BITS[tok])
    return (b0,lx,ly,rx,ry)

def main():
    path=sys.argv[1]; inject=sys.argv[2] if len(sys.argv)>2 else ''
    data=open(path,'rb').read()
    if len(data)<64:
        print(f"RESULT: demo too short ({len(data)} bytes)"); sys.exit(2)
    ver,recsz,seed,_=struct.unpack('<IIII',data[8:24]); anchor=struct.unpack('<q',data[24:32])[0]
    body=data[64:]; n=len(body)//6
    exp=expected_from_inject(inject)
    exp_rec=struct.pack('<HBBBB',*exp)
    nn=0; match=0; first_nn=-1
    seen=set()
    for i in range(n):
        r=body[i*6:i*6+6]
        b0,lx,ly,rx,ry=struct.unpack('<HBBBB',r)
        neutral=(b0==0 and lx==127 and ly==127 and rx==127 and ry==127)
        if not neutral:
            nn+=1
            if first_nn<0: first_nn=i
        if r==exp_rec: match+=1
        seen.add(r)
    print(f"demo: {os.path.basename(path)} v{ver} anchor={anchor} frames={n}")
    print(f"injected string: '{inject}'")
    print(f"expected injected record: button0=0x{exp[0]:04x} lx={exp[1]} ly={exp[2]} rx={exp[3]} ry={exp[4]}  bytes={exp_rec.hex()}")
    print(f"INPUT CAPTURED: {nn}/{n} non-neutral  ({100*nn/max(n,1):.1f}%)  first_nn={first_nn}")
    print(f"byte-match injected: {match}/{n} records == injected value  ({100*match/max(n,1):.1f}%)")
    print(f"distinct records seen: {len(seen)}")
    # Verdict for convenience (the validator reads report.txt, not this).
    if n>=30 and nn>=n/2 and match>=n/2:
        print("VERDICT: CAPTURED — live record captured the injected input (byte-matches)")
    elif nn==0:
        print("VERDICT: ALL-NEUTRAL — bug reproduced (injected input NOT captured)")
    else:
        print(f"VERDICT: PARTIAL — nn={nn}/{n} match={match}/{n}")

if __name__=='__main__':
    main()
