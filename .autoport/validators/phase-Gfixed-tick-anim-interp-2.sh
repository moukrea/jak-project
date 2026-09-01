#!/usr/bin/env bash
# PORTE CORRIGEE le 2026-09-01. La precedente EXIGEAIT une mesure > 60 img/s et refusait
# le rapport sans elle — « c'est la que le jitter se voit ». C'etait FAUX : l'owner joue
# vers 20 img/s et c'est la qu'il souffre. Elle a donc valide un chantier qui ne traitait
# pas son cas, en releguant les mesures basses en « hors verdict ».
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gfixed-tick-anim-interp-2/report.txt
[ -f "$R" ] || { echo "[Gfta2 FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gfta2 FAIL] "+m,file=sys.stderr); sys.exit(1)
j=[kv(l) for l in re.findall(r'^ANIMJIT .*$',t,re.M)]
bas=[d for d in j if float(d.get('fps',999))<=30]
haut=[d for d in j if float(d.get('fps',0))>60]
if not bas: F("aucune mesure a 30 img/s ou moins : c'est LA que l'owner voit le defaut (« dans les 20 FPS »)")
if not haut: F("aucune mesure au-dessus de 60 img/s : « faut que ça marche dans les deux sens »")
for lot,nom in ((bas,'basse cadence'),(haut,'haute cadence')):
    for f in {d['fps'] for d in lot}:
        on=[d for d in lot if d['fps']==f and d.get('arme')=='1']
        off=[d for d in lot if d['fps']==f and d.get('arme')=='0']
        if not on or not off: F(f"a {f} img/s il manque la mesure armee ou desarmee — sans les deux on ne compare rien")
        if float(on[0]['ecart_max']) >= float(off[0]['ecart_max']):
            F(f"{nom}, {f} img/s : ecart max {on[0]['ecart_max']} arme contre {off[0]['ecart_max']} desarme — pas d'amelioration")
b=[kv(l) for l in re.findall(r'^ANIM60 .*$',t,re.M)]
if not b or b[0].get('identique_au_bit')!='1': F("a 60 img/s le comportement doit rester identique au bit")
print("[Gfta2 ok] jitter reduit AUX DEUX BOUTS (<=30 et >60), 60 fps inchange au bit")
PY
