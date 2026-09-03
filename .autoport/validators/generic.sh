#!/usr/bin/env bash
# generic.sh — LE seul validateur. Il juge `reports/<id>/proof.txt` ecrit par la MACHINE
# (lib/proof_run.sh), jamais `report.txt` ecrit par le worker. Il ACCUMULE ses constats : une
# porte qui sort a la premiere erreur masque les suivantes. Aucune citation d'owner ici.
set -uo pipefail; cd "$(git rev-parse --show-toplevel)" || exit 1
P="${AUTOPORT_PHASE_ID:?AUTOPORT_PHASE_ID manquant}"; D=".autoport/reports/$P"; PF="$D/proof.txt"; N=0
bad(){ echo "[$P FAIL] $*" >&2; N=$((N+1)); }; kv(){ sed -n "s/^$1=//p" "$PF" 2>/dev/null | tail -1; }
eval "$(python3 - "$P" <<'PY'
import sys, yaml
sys.path.insert(0, '.autoport/lib')
try: it = __import__('backlog').load().get(sys.argv[1]) or {}
except Exception: it = next((c for c in ((yaml.safe_load(open('.autoport/backlog.yaml', encoding='utf-8')) or {}).get('items') or []) if c.get('id') == sys.argv[1]), {})
g = it.get('gate') or {}
q = lambda s: "'" + str(s).replace("'", "'\\''") + "'"
print("GK=%s GO=%s GV=%s DEV=%d FMIN=%s" % (q(g.get('key', '')), q(g.get('op', '')), q(g.get('value', '')), 1 if it.get('device') else 0, q(it.get('frames_min', 300))))
PY
)"
if [ ! -s "$PF" ]; then
  bad "proof.txt absent ou vide. Produis-le : .autoport/lib/proof_run.sh $P $([ "${DEV:-0}" = 1 ] && echo device || echo x86)"
else
  src=$(kv source); bin=build/game/gk; [ "$src" = device ] && bin=build-android/lib/arm64-v8a/libgk.so
  neuf=$(find game common android goal_src -type f \( -name '*.cpp' -o -name '*.h' -o -name '*.gc' -o -name '*.vert' -o -name '*.frag' \) -newer "$PF" -print -quit 2>/dev/null)
  [ -z "$neuf" ] || bad "source moteur editee APRES la preuve ($neuf) : la preuve ne decrit pas ce binaire"
  [ "$(kv sha)" = "$(sha256sum "$bin" 2>/dev/null | cut -c1-16)" ] || bad "sha=$(kv sha) n'est pas celui de $bin sur le disque"
  [ "$(kv binary)" = "$bin" ] || bad "binary=$(kv binary) ne correspond pas a source=$src"
  [ "$(kv crash)" = 0 ] || bad "crash=$(kv crash)"
  f=$(kv frames); [ "${f:-0}" -ge "$FMIN" ] 2>/dev/null || bad "frames=${f:-absent} sous le seuil $FMIN : rien n'a ete dessine assez longtemps"
  [ "$DEV" = 0 ] || [ "$src" = device ] || bad "l'item exige l'appareil, la preuve est en source=$src"
  dm=$(kv device_lib_md5); case "${dm:-vide}" in vide|absent-*) ;; *) [ "$dm" = "$(kv local_lib_md5)" ] || bad "le libgk.so de l'appareil ($dm) n'est pas celui du build ($(kv local_lib_md5))" ;; esac
  grep -qE "^FEATURE $P armed=1 hits=[1-9][0-9]*$" "$PF" || bad "ligne 'FEATURE $P armed=1 hits=>0' absente : rien ne prouve que la feature a tire"
  if [ -n "$GK" ]; then v=$(kv "$GK")
    if [ -z "$v" ]; then bad "le proof ne porte pas '$GK=' : le moteur doit emettre cette grandeur"
    else awk -v a="$v" -v b="$GV" -v o="$GO" 'BEGIN{n=(a+0==a&&b+0==b);r=(o=="=="?(n?a+0==b+0:a==b):o=="!="?(n?a+0!=b+0:a!=b):o=="<"?a+0<b+0:o=="<="?a+0<=b+0:o==">"?a+0>b+0:o==">="?a+0>=b+0:0);exit r?0:1}' \
           || bad "$GK=$v viole le critere $GK $GO $GV"; fi
  fi
  OFF="$D/proof-off.txt"
  [ ! -s "$OFF" ] || grep -qE "^FEATURE $P armed=0 hits=0$" "$OFF" || bad "ablation : proof-off.txt ne montre pas 'armed=0 hits=0' — la feature tire encore desarmee"
fi
[ "$N" = 0 ] || { echo "[$P FAIL] $N constat(s) ci-dessus, aucun n'a ete masque par un autre." >&2; exit 1; }
echo "[$P ok] source=$(kv source) sha=$(kv sha) frames=$(kv frames) crash=0${GK:+ ; $GK $GO $GV tenu}"
