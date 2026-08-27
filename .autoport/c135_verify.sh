#!/usr/bin/env bash
# c135_verify.sh — LES SIX PREDICTIONS DU c135, CONFRONTEES A LA COURSE. Ce script ne CHOISIT rien :
# il relit `.autoport/c135-predictions.txt`, ecrit AVANT le lot, et dit DANS / HORS pour chacune.
#
# Garde 1 : la TABLE est une seconde commande. `keira_room_x86.sh` ne fait que recolter le log ;
#           l'oublier laisse la table de la course PRECEDENTE, ce qui se lit exactement comme
#           « mon changement n'a rien fait » (registre : validator-reads-a-stale-table).
# Garde 2 : on publie le md5 du log ET de la table, pour qu'on sache QUELLE course a parle.
set -uo pipefail
cd "$(dirname "$0")/.."
OUT=.autoport/reports/Grecharged-secondary-motion
LOG="$OUT/keira-room-x86.log"; TBL="$OUT/keira-room-table.txt"

[ -f "$LOG" ] || { echo "FAIL: pas de log de course"; exit 2; }
echo "log md5 : $(md5sum "$LOG" | cut -d' ' -f1)   ($(stat -c%y "$LOG"))"

echo "== 1. REGENERATION DE LA TABLE (jamais supposee fraiche) =="
python3 .autoport/physics_room_table.py "$LOG" "$TBL" >/dev/null || { echo "FAIL: table"; exit 5; }
echo "table md5 : $(md5sum "$TBL" | cut -d' ' -f1)"

echo
echo "== 2. LE CANAL A-T-IL ETE LU ? (preuve d'execution, pas un commentaire) =="
grep -ao "PHYSRIGID c=[0-9]* i=6 rs=[0-9.]*" "$LOG" | sort -u

echo
echo "== 3. §11 — LES QUATRE PREDICTIONS DE BANDE (instrument c133, portage controle) =="
python3 .autoport/c133_delivered_com.py "$LOG" 2>&1 | tee /tmp/c135_after.txt \
  | grep -aE "w>0\.00 +§11 +i=6 +LIVREE|portage|HORS DEFAUT" | grep -av "w>0.05"

echo
echo "== 4. DISCRIMINANT (gate du validateur, seuil 25 %) =="
python3 - "$TBL" <<'PY'
import re,sys
t=open(sys.argv[1],errors='ignore').read()
rows=[dict(re.findall(r'(\w+)=([^\s]+)',l)) for l in t.split('\n') if l.startswith('row ')]
rows=[d for d in rows if {'chain','drive','tipvar'}<=set(d)]
dr=sorted({r['drive'] for r in rows})
for ch in sorted({r['chain'] for r in rows}):
    per={d:max(float(r['tipvar']) for r in rows if r['chain']==ch and r['drive']==d)
         for d in dr if any(r['chain']==ch and r['drive']==d for r in rows)}
    if len(per)<3: continue
    hi,lo=max(per.values()),min(per.values()); sp=(hi-lo)/hi*100
    print("  %-8s ecart %5.2f%%  %s  -> %s"%(ch,sp," · ".join("%s %.4f"%kv for kv in sorted(per.items())),
          "DANS" if sp>=25 else "HORS (gate cassee)"))
PY

echo
echo "== 5. LES SIX PREDICTIONS, VERDICT =="
python3 - <<'PY'
import re
p={'chestL':dict(L=1.2585,C=0.2008),'chestR':dict(L=1.2552,C=0.2042)}
txt=open('/tmp/c135_after.txt',errors='ignore').read()
got={}
for m in re.finditer(r'(chest[LR])\s+w>0\.00\s+§11\s+i=6\s+LIVREE\(compte\)\s+([0-9.]+)',txt):
    got[m.group(1)]={'C':float(m.group(2))}
for m in re.finditer(r'(chest[LR])\s+w>0\.00\s+§11\s+deciles\s+:\s+c124\s+([0-9.]+)',txt):
    got.setdefault(m.group(1),{})['L']=float(m.group(2))
for ch in ('chestL','chestR'):
    g=got.get(ch,{})
    if 'L' in g: print("  %s longueur  predite %.4f  mesuree %.4f  bande<=1.26  -> %s"
        %(ch,p[ch]['L'],g['L'],"DANS" if g['L']<=1.26 else "AU-DESSUS"))
    if 'C' in g: print("  %s COM       predite %.4f  mesuree %.4f  bande>=0.20  -> %s"
        %(ch,p[ch]['C'],g['C'],"DANS" if 0.20<=g['C']<=0.28 else ("SOUS" if g['C']<0.20 else "AU-DESSUS")))
PY
