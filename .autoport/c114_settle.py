import re,sys
from collections import defaultdict
def settle(path):
    S=defaultdict(dict)
    for ln in open(path,errors='ignore'):
        m=re.match(r'PHYSRING(A|B|C)(N|X|Z) c=(\d+) f=(\d+) l=(\d+) ax=(\d+) v=([-0-9.]+)',ln)
        if m:
            k=(m.group(1)+m.group(2),int(m.group(3)),int(m.group(5)),int(m.group(6)))
            S[k][int(m.group(4))]=float(m.group(7))
    out={}
    for k,fv in S.items():
        v=[fv[f] for f in sorted(fv)]
        if len(v)<40: continue
        a0=max(abs(x) for x in v[:5]) or 1e-12
        tl=v[-30:]; mo=sum(tl)/30.0
        sd=(sum((x-mo)**2 for x in tl)/30.0)**0.5
        out[k]=(a0,mo,100.0*abs(mo)/a0,sd)
    return out
runs=[(sys.argv[i],sys.argv[i+1]) for i in range(1,len(sys.argv),2)]
D=[(l,settle(p)) for l,p in runs]
AX={0:'v',1:'ap',2:'lat'}
keys=sorted(set(k for _,d in D for k in d))
print("DECALAGE DE PARCAGE APRES IMPULSION ISOLEE (moyenne des 30 dernieres frames)")
print("NATURE : un DEPLACEMENT residuel, meme unite que la serie. REPERE : celui de PH-AXC.")
print("HORS DEFAUT : 0.0000000 — la chaine se repose sur la pose d'auteur.\n")
hdr="%-4s %-3s %-2s %-3s"%("bloc","ch","l","ax")
for l,_ in D: hdr+=" | %-22s"%l
print(hdr); print("-"*len(hdr))
for k in keys:
    blk,c,l,ax=k
    row="%-4s %-3d %-2d %-3s"%(blk,c,l,AX.get(ax,ax))
    for lab,d in D:
        if k in d:
            a0,mo,pc,sd=d[k]; row+=" | %+0.7f %5.3f%% s%.4f"%(mo,pc,sd)
        else: row+=" | %-22s"%"—"
    print(row)
print()
if len(D)>1:
    ref=D[0][1]
    for lab,d in D[1:]:
        n=sum(1 for k in ref if k in d and abs(d[k][1]-ref[k][1])>1e-9)
        mx=max(((abs(d[k][1]-ref[k][1]),k) for k in ref if k in d), default=(0,None))
        print("%-10s : %d/%d series dont le decalage BOUGE contre %s ; ecart max %.7f sur %s"
              %(lab,n,len(ref),D[0][0],mx[0],mx[1]))
