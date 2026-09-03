#!/usr/bin/env bash
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
R=.autoport/reports/Gfont-regression/report.txt
[ -f "$R" ] || { echo "[Gfr FAIL] pas de report.txt" >&2; exit 1; }
python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read(); kv=lambda l: dict(re.findall(r'(\w+)=([^\s]+)',l))
def F(m): print("[Gfr FAIL] "+m,file=sys.stderr); sys.exit(1)
b=[kv(l) for l in re.findall(r'^FONTBISECT .*$',t,re.M)]
if len(b)<2: F("FONTBISECT sur >= 2 builds exige : dire OU la police casse, pas deviner")
if not re.search(r'^FONTCAUSE .*nommee=\S+',t,re.M): F("FONTCAUSE absent : la cause doit etre nommee")
# PREUVE PROGRAMMATIQUE OBLIGATOIRE (owner 2026-09-02) : l'atlas LIE et la table CONSULTEE
# doivent etre publies depuis le moteur, pas deduits d'une image.
if not re.search(r'^FONTBIND .*atlas=\S+.*table=\S+',t,re.M):
    F("FONTBIND absent : publier depuis le MOTEUR quel atlas est lie et quelle table de glyphes est consultee — une capture d'ecran n'est pas une preuve")
ok=[kv(l) for l in re.findall(r'^FONTOK .*$',t,re.M)]
if not ok: F("FONTOK absent")
d=ok[0]
if int(d.get('chaines',0))<20: F(f"{d.get('chaines')} chaines verifiees, il en faut >= 20")
if int(d.get('glyphes_atlas_origine',1))!=0: F(f"{d['glyphes_atlas_origine']} glyphe(s) viennent encore de l'atlas d'origine")
if not re.search(r'^FONTGUARD .*echoue_si=\S+',t,re.M):
    F("FONTGUARD absent : la police est un ACQUIS VALIDE par l'owner, il faut une garde qui la verifie a CHAQUE cycle")
print("[Gfr ok] regression localisee, cause nommee, zero glyphe d'origine sur >=20 chaines, garde posee")
PY
