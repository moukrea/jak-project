#!/usr/bin/env bash
# Gcutscene-npc-flicker — deuxieme passe x86 : le binaire porte le correctif ET le controle
# positif. Un seul processus, donc UN verrou vivant du debut a la fin (DIRECTIVES 2026-08-14 07:10 :
# le PID d'un shell d'appel d'outil serait mort dans la seconde).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gcutscene-npc-flicker; mkdir -p "$OUT"
R="$OUT/cycle2.txt"; : > "$R"
say(){ echo "$*" | tee -a "$R"; }
export DISPLAY="${DISPLAY:-:0}" XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.2UGBV3}"

LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  H=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$H" ] && kill -0 "$H" 2>/dev/null; then say "FAIL: livraison en cours (pid=$H)"; exit 1; fi
fi
printf 'npcf_cycle2 pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
export NPCF_LOCK_HELD=1
say "verrou de livraison pose (pid=$$) pour toute la passe"

say "== 1. reconstruction du moteur x86 =="
if ! cmake --build build --target gk -j"$(nproc)" > "$OUT/x86_build3.log" 2>&1; then
  say "FAIL: build gk"; tail -30 "$OUT/x86_build3.log" | tee -a "$R"; exit 1
fi
say "   gk OK"

say "== 2. CONTROLE POSITIF : on injecte une disparition, le compteur DOIT monter =="
SKIP_BUILD=0 WATCH=150 LEGS="hd0" SCENES="intro-start" \
  OG_NPCF_INJECT="sage-lod0:120:12" bash .autoport/npcf_x86_campagne.sh >> "$R" 2>&1
for f in "$OUT"/gk-hd0-intro-start.log; do
  [ -f "$f" ] && mv -f "$f" "$OUT/gk-inject-intro-start.log"
done
say "   -> $(grep -ac 'NPCFLICK-EV' "$OUT/gk-inject-intro-start.log" 2>/dev/null) evenement(s), $(grep -ac 'NPCF-INJECT arme' "$OUT/gk-inject-intro-start.log" 2>/dev/null) ligne(s) d'armement"

say "== 3. APRES CORRECTIF : les 4 cinematiques, modeles HD actifs =="
SKIP_BUILD=1 WATCH=150 LEGS="hd1" SCENES="intro-start village1-intro village1-warp village1-demo-convo" \
  bash .autoport/npcf_x86_campagne.sh >> "$R" 2>&1
for s in intro-start village1-intro village1-warp village1-demo-convo; do
  [ -f "$OUT/gk-hd1-$s.log" ] && cp -f "$OUT/gk-hd1-$s.log" "$OUT/fix-hd1-$s.log"
done
say "== fin — $(date -Is) =="
