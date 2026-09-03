#!/usr/bin/env python3
"""c44_verdict.py — score les 8 predictions A1-A8 de C44E1 (md5 37b02f3b1a90ce5830dccb49588b27fa).

REPERE ET NATURE DES GRANDEURS, declares ici parce que le contrat l'exige (SPEC-keira-physique 7) :
  * `a0` / `a1` / `ang`  : ANGLE PROPRE d'un maillon, en degres, mesure RELATIVEMENT A SON PARENT
    (direction courante depuis l'attache SIMULEE vs direction du MODELE depuis l'attache ANIMEE,
    `phys-cap-ang!` :1274). Ce n'est PAS un deplacement monde. Nature = une FORME (un angle),
    publiee par (chaine, maillon, pilotage) et jamais agregee en un scalaire par chaine.
  * `ecart entre pilotages` : (max - min) / max sur les SIX colonnes de pilotage, a maillon fixe.
    Nature = une DISCRIMINATION. Ligne de base quand le defaut est absent : un systeme dont la
    reponse suit sa cause rend ici l'ordre de grandeur de l'ecart d'ENTREE (38.9x, cf. C44E1B).
  * `meshpen` / `tipvar` / `ROOM-STRETCH` / COM : repris tels quels du tableau, qui declare les
    siens ; ce script ne les recalcule pas, il les LIT.
"""
import re,sys,collections,math

def grads(path):
    S=collections.defaultdict(dict); F=collections.defaultdict(dict)
    for line in open(path,errors='ignore'):
        m=re.match(r'PHYSGRADS c=(\d+) a=(\d+) d=(\d+) l=(\d+) a0=([-\d.]+) a1=([-\d.]+)',line)
        if m:
            c,a,d,l=map(int,m.groups()[:4]); S[(c,l)][(a,d)]=(float(m.group(5)),float(m.group(6)))
        m=re.match(r'PHYSGRAD c=(\d+) a=(\d+) d=(\d+) l=(\d+) amp=([-\d.]+) ang=([-\d.]+)',line)
        if m:
            c,a,d,l=map(int,m.groups()[:4]); F[(c,l)][(a,d)]=float(m.group(6))
    return S,F

def percol(F,c,l):
    return [max(v for k,v in F[(c,l)].items() if k[1]==d) for d in range(6)]

def spread(xs):
    hi,lo=max(xs),min(xs)
    return (hi-lo)/hi*100.0 if hi>0 else 0.0

def stim(path):
    out={}
    for line in open(path,errors='ignore'):
        m=re.match(r'PHYSSTIM dr=(\d+) mag=([-\d.]+)',line)
        if m: out[int(m.group(1))]=float(m.group(2))
    return out

def resp(path):
    out={}
    for line in open(path,errors='ignore'):
        m=re.match(r'PHYSRESP c=(\d+) lvl=(\d+) exc=([-\d.]+) amp=([-\d.]+) jump=([-\d.]+)',line)
        if m: out[(int(m.group(1)),int(m.group(2)))]=(float(m.group(3)),float(m.group(4)))
    return out

def table_get(path):
    """Lit les grandeurs du TABLEAU derive (il declare les siennes ; on ne les recalcule pas)."""
    g={'stretch':None,'worst':{},'drives':{}}
    for line in open(path,errors='ignore'):
        m=re.search(r'ROOM-STRETCH: max=([\d.]+)',line)
        if m: g['stretch']=float(m.group(1))
        m=re.match(r'worst chain=(\S+)\s+tipvar=([\d.]+).*?rootdev=([\d.]+)\s+meshpen=([\d.]+)',line)
        if m: g['worst'][m.group(1)]={'tipvar':float(m.group(2)),'rootdev':float(m.group(3)),'meshpen':float(m.group(4))}
        m=re.match(r'drive=(\S+)\s+windows=\d+\s+tipvar_max=([\d.]+).*?meshpen_max=([\d.]+)',line)
        if m: g['drives'][m.group(1)]={'tipvar':float(m.group(2)),'meshpen':float(m.group(3))}
    return g

if __name__=='__main__':
    ref,abl=sys.argv[1],sys.argv[2]
    tref,tabl=(sys.argv[3],sys.argv[4]) if len(sys.argv)>4 else (None,None)
    names={0:'chestL',1:'chestR'}
    Sr,Fr=grads(ref); Sa,Fa=grads(abl)
    print("STIMULUS COMMANDE (PHYSSTIM, u/frame^2) — l'ENTREE, pas une sortie")
    sr,sa=stim(ref),stim(abl)
    print(f"  reference {sr}\n  ablation  {sa}   IDENTIQUE={sr==sa}")
    print()
    print("=== A1 / A2 — DISCRIMINATION DE L'ANGLE LIVRE (`ang`), ecart sur les 6 pilotages ===")
    for c in (0,1):
        for l in (0,1):
            r=percol(Fr,c,l); a=percol(Fa,c,l)
            print(f"  {names[c]} l={l}")
            print(f"     REF  "+"  ".join(f"{x:8.3f}" for x in r)+f"   ecart {spread(r):6.2f} %  max {max(r):8.3f}")
            print(f"     ABL  "+"  ".join(f"{x:8.3f}" for x in a)+f"   ecart {spread(a):6.2f} %  max {max(a):8.3f}")
    print()
    print("=== la DEMANDE (etage 0) doit etre quasi inchangee : l'ablation est EN AVAL ===")
    for c in (0,1):
        for l in (0,1):
            r=[max(v[0] for k,v in Sr[(c,l)].items() if k[1]==d) for d in range(6)]
            a=[max(v[0] for k,v in Sa[(c,l)].items() if k[1]==d) for d in range(6)]
            print(f"  {names[c]} l={l}  REF a0 "+" ".join(f"{x:7.2f}" for x in r))
            print(f"  {names[c]} l={l}  ABL a0 "+" ".join(f"{x:7.2f}" for x in a))
    print()
    print("=== A8 — LE STIMULUS RECU : PHYSRESP (exc, amp) par (chaine, niveau) ===")
    rr,ra=resp(ref),resp(abl)
    same=sum(1 for k in rr if k in ra and abs(rr[k][0]-ra[k][0])<1e-6)
    print(f"  colonnes `exc` identiques : {same}/{len(rr)}")
    for k in sorted(rr):
        print(f"   c={k[0]} lvl={k[1]}  exc {rr[k][0]:8.3f} -> {ra.get(k,(0,0))[0]:8.3f}   amp {rr[k][1]:9.3f} -> {ra.get(k,(0,0))[1]:9.3f}")
    if tref and tabl:
        print()
        print("=== A4 / A5 / A7 — LUS DANS LE TABLEAU DERIVE ===")
        gr,ga=table_get(tref),table_get(tabl)
        print(f"  ROOM-STRETCH max   REF {gr['stretch']}   ABL {ga['stretch']}")
        for ch in sorted(set(list(gr['worst'])+list(ga['worst']))):
            R=gr['worst'].get(ch,{}); A=ga['worst'].get(ch,{})
            for f in ('tipvar','meshpen','rootdev'):
                r,a=R.get(f),A.get(f)
                d=f"{(a-r)/r*100:+7.1f} %" if (r and a) else "   n/a"
                print(f"  {ch:8s} {f:8s} REF {r}  ABL {a}   {d}")
        for dn in sorted(set(list(gr['drives'])+list(ga['drives']))):
            R=gr['drives'].get(dn,{}); A=ga['drives'].get(dn,{})
            print(f"  drive={dn:10s} tipvar {R.get('tipvar')} -> {A.get('tipvar')}   meshpen {R.get('meshpen')} -> {A.get('meshpen')}")
