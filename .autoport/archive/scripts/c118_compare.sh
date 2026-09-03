#!/usr/bin/env bash
# cycle 118 — CONTROLES DE LA BORNE DE SPEC 21 SUR LA VALEUR LIVREE.
#   $1 = la course a comparer (defaut : la course courante)
# Gauche = c117-BASE (etat livre du cycle 117, AVANT toute edition) ; droite = $1.
set -uo pipefail
cd "$(dirname "$0")/.."
D=.autoport/reports/Grecharged-secondary-motion
A=$D/keira-room-x86.c117-BASE.log
B=${1:-$D/keira-room-x86.log}
echo "=== A = $A"
echo "=== B = $B"
echo
echo "================ (P5) IDENTITE AU BIT SUR TOUTES LES LIGNES PHYS*"
na=$(grep -ac "^PHYS" "$A"); nb=$(grep -ac "^PHYS" "$B")
nd=$(diff <(grep -a "^PHYS" "$A") <(grep -a "^PHYS" "$B") | grep -c "^[<>]")
echo "  A: $na lignes PHYS*   B: $nb lignes PHYS*   lignes differentes: $nd"
echo "  (les lignes PHYSE21 sont NEUVES dans B : elles comptent dans nd et ne sont pas un ecart)"
ndx=$(diff <(grep -a "^PHYS" "$A" | grep -av "^PHYSE21 ") <(grep -a "^PHYS" "$B" | grep -av "^PHYSE21 ") | grep -c "^[<>]")
echo "  hors PHYSE21 : $ndx lignes differentes"
echo
echo "================ (P3) LA BORNE A-T-ELLE MORDU"
grep -a "^PHYSE21 " "$B" || echo "  (aucune ligne PHYSE21)"
echo "  --- pour comparaison, la borne de §22 sur le meme etat :"
grep -a "^PHYSE22 " "$B" || true
echo
echo "================ (P1/P2/P4/P6) LA GRANDEUR DE §21 ET L'APEX"
python3 .autoport/c118_s21.py "$A" "$B"
echo
echo "================ (P7) CE QUE LES GATES LISENT"
TA=$D/keira-room-table.c118-BASE.txt
TB=$D/keira-room-table.txt
for pat in '^ROOM-IDLE:' '^ROOM-POSCONTROL' '^ROOM-AUTHORED' '^ROOM-ANIMS:' \
           '^ROOM-SKINPEN-VERDICT:' '^ROOM-SKINPEN-REST:' '^ROOM-SKINPEN-COUT:' '^ROOM-APEX:' ; do
  echo "---- $pat"
  diff <(grep -E "$pat" "$TA" 2>/dev/null) <(grep -E "$pat" "$TB" 2>/dev/null) \
    && echo "    identique" || true
done
echo "---- DISCRIMINANT (tipvar par pilotage, la gate exige >= 25 %)"
python3 - "$TA" "$TB" <<'PY'
import re,sys
def spread(p):
    t=open(p,errors='ignore').read(); rows=[]
    for ln in t.split('\n'):
        if ln.startswith('row '):
            d=dict(re.findall(r'(\w+)=([^\s]+)',ln))
            if {'chain','drive','tipvar'}<=set(d): rows.append(d)
    out={}
    dr=sorted({r['drive'] for r in rows})
    for ch in sorted({r['chain'] for r in rows}):
        per={d:max([float(r['tipvar']) for r in rows if r['chain']==ch and r['drive']==d] or [0]) for d in dr}
        per={k:v for k,v in per.items() if v>0}
        if len(per)>=3:
            hi,lo=max(per.values()),min(per.values()); out[ch]=(100*(hi-lo)/hi,per)
    return out
a,b=spread(sys.argv[1]),spread(sys.argv[2])
for ch in sorted(set(a)|set(b)):
    sa=a.get(ch,(float('nan'),{}))[0]; sb=b.get(ch,(float('nan'),{}))[0]
    print("  %-8s ecart %.1f %% -> %.1f %%   %s"%(ch,sa,sb,
        " · ".join("%s %.4f->%.4f"%(d,a[ch][1].get(d,0),b[ch][1].get(d,0)) for d in sorted(b.get(ch,(0,{}))[1]))))
PY
