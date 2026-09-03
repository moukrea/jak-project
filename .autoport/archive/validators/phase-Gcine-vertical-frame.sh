#!/usr/bin/env bash
# Validator — Gcine-vertical-frame. Portes NUMERIQUES : une relecture de code ne peut pas les ouvrir.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gcvf FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gcvf ok] $*"; }
R=.autoport/reports/Gcine-vertical-frame/report.txt
[ -f "$R" ] || fail "pas de report.txt"
grep -qE '^RESULT:[[:space:]]*CINE VERTICAL FRAME MEASURED[[:space:]]*$' "$R" \
  || fail "RESULT: CINE VERTICAL FRAME MEASURED absent (comparaison a la CLE ENTIERE, pas un prefixe)"

N=$(grep -cE '^CINELIVE ' "$R"); [ "$N" -ge 8 ] || fail "seulement $N lignes CINELIVE, il en faut >= 8 PENDANT la vraie cinematique"
grep -qE '^CINELIVE .*scene=[^ ]*(sage|hut|teleport)' "$R" || fail "aucune CINELIVE sur la cinematique NOMMEE par l'owner (Hutte du Sage Vert / teleporteur)"
[ "$(grep -cE '^CINECTL ' "$R")" -ge 1 ] || fail "controle negatif CINECTL absent — sans lui la trace ne discrimine rien"
grep -qE '^CINEBRANCH taken=(usevis|realmovie|else)$' "$R" || fail "CINEBRANCH doit NOMMER la branche reellement executee"

python3 - "$R" <<'PY' || exit 1
import re,sys
t=open(sys.argv[1]).read()
def kv(line):
    return dict(re.findall(r'(\w+)=([^\s]+)',line))
live=[kv(l) for l in re.findall(r'^CINELIVE .*$',t,re.M)]
ctl =[kv(l) for l in re.findall(r'^CINECTL .*$',t,re.M)]
sig=lambda d:(d.get('usevis'),d.get('realmovie'),d.get('x'),d.get('y'))
if all(sig(c) in {sig(l) for l in live} for c in ctl):
    print("[Gcvf FAIL] le controle negatif est IDENTIQUE a la trace de cinematique : l'instrument ne mesure rien",file=sys.stderr); sys.exit(1)
fit=[kv(l) for l in re.findall(r'^CINEFIT .*$',t,re.M)]
if len(fit)<4:
    print(f"[Gcvf FAIL] {len(fit)} lignes CINEFIT, il en faut >= 4 formats",file=sys.stderr); sys.exit(1)
for f in fit:
    ah,sh=float(f['authorh']),float(f['screenh'])
    if sh<=0 or abs(ah-sh)/sh>0.005:
        print(f"[Gcvf FAIL] asp={f['asp']} : hauteur d'auteur {ah} != hauteur d'ecran {sh} — le cadre vertical ne remplit PAS la hauteur",file=sys.stderr); sys.exit(1)
    if int(f['offscreen'])!=0:
        print(f"[Gcvf FAIL] asp={f['asp']} : {f['offscreen']} pixels d'auteur HORS ECRAN — c'est exactement le defaut signale 5 fois",file=sys.stderr); sys.exit(1)
wide=sorted(((float(k['asp']),int(k['objets'])) for k in (kv(l) for l in re.findall(r'^CINEWIDE .*$',t,re.M))))
if len(wide)<4:
    print(f"[Gcvf FAIL] {len(wide)} lignes CINEWIDE, il en faut >= 4",file=sys.stderr); sys.exit(1)
if any(b<=a for (_,a),(_,b) in zip(wide,wide[1:])):
    print(f"[Gcvf FAIL] le champ ne s'ELARGIT pas avec le format : {wide} — un zoom, pas un elargissement",file=sys.stderr); sys.exit(1)
b={m.group(1):int(m.group(2)) for m in re.finditer(r'^CINEBARS vis=(\d) bytes=(\d+)',t,re.M)}
if b.get('0')!=0:
    print(f"[Gcvf FAIL] mode natif : letterbox emet {b.get('0')} octets, il doit en emettre 0",file=sys.stderr); sys.exit(1)
if not b.get('1',0)>0:
    print("[Gcvf FAIL] controle POSITIF absent (vis=1 doit emettre des octets) — un zero sans controle qui tire ne prouve rien",file=sys.stderr); sys.exit(1)
print("[Gcvf ok] trace vivante, controle negatif distinct, cadre plein a 4+ formats, champ elargi, barres nulles avec controle positif")
PY
# --- Porte ajoutee 2026-08-30 : l'observable de l'owner, mesure a 25,0 % de perte ---
grep -qE '^CINEVLOSS ' "$R" || fail "CINEVLOSS absent : il faut publier la pente verticale en cinematique ET en jeu, au MEME format (c'est la ligne qui porte le defaut, mesuree a 25,0 % de perte le 30/08)"
python3 - "$R" <<'PZ' || exit 1
import re,sys
t=open(sys.argv[1]).read()
rows=[dict(re.findall(r'(\w+)=([^\s]+)',l)) for l in re.findall(r'^CINEVLOSS .*$',t,re.M)]
if len(rows)<4:
    print(f"[Gcvf FAIL] {len(rows)} lignes CINEVLOSS, il en faut >= 4 formats",file=sys.stderr); sys.exit(1)
for r in rows:
    vc,vj=float(r['v_cine']),float(r['v_jeu'])
    perte=(1-vc/vj)*100
    if perte>0.5:
        print(f"[Gcvf FAIL] format {r.get('asp')} : {perte:.1f} %% de champ VERTICAL perdu a l'entree en cinematique (mesure d'origine : 25,0 %%). C'est le defaut que l'owner signale depuis 5 fois.",file=sys.stderr); sys.exit(1)
print("[Gcvf ok] aucune perte de champ vertical a l'entree en cinematique, sur %d formats"%len(rows))
PZ
ok "toutes les portes numeriques passees"
