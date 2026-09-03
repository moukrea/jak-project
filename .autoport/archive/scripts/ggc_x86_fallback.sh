#!/usr/bin/env bash
# ggc_x86_fallback.sh — Ggrass-crash : FAIRE DIRE AU MOTEUR POURQUOI IL BASCULE EN PLACEMENT DIRECT.
#
# Le prompt de phase pose comme acquis que « le pre-calcul n'arrive JAMAIS sur l'appareil » et que
# le placement est donc « EN DIRECT systematique ». C'est REFUTE par l'artefact : l'APK contient
# `fr3/training.grassbake` (2 024 808 o) et `fr3/beach.grassbake` (1 418 098 o), et le `.fr3`
# correspondant n'est PAS remplace par le pack HD. Sur x86 comme sur l'appareil, le bake est donc
# VALIDE et le mode est `precomputed` — il n'y a aucun repli, et « aucun repli » ne se prouve pas en
# ne montrant rien.
#
# Cette course fait donc l'inverse : elle DECLENCHE le repli exprès, par un geste de joueur (monter
# le curseur de densite au-dessus de la densite a laquelle le bake a ete cuit), pour que la ligne
# `PRECOMPUTED unavailable (<raison>) -> LIVE fallback` sorte avec sa RAISON NOMMEE. On mesure ainsi
# les DEUX etats du meme binaire : le mode normal (precomputed) et le repli, avec sa cause.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK="build-x86/game/gk"; GOALC="build-x86/goalc/goalc"; ISO="out/jak1/iso"
OUT=".autoport/reports/Ggrass-crash"; mkdir -p "$OUT"
SETTINGS="build-x86/game/OpenGOAL/jak1/settings/settings.ini"
TAG="${1:-fallback}"; DHI="${2:-400}"
export DISPLAY="${DISPLAY:-:0}" SDL_VIDEODRIVER=x11
export XAUTHORITY="${XAUTHORITY:-/run/user/1000/.mutter-Xwaylandauth.2UGBV3}"
LOG="$OUT/$TAG.log"; GCLOG="$OUT/$TAG-goalc.log"; : > "$LOG"; : > "$GCLOG"
KSZ=$(stat -c %s "$ISO/KERNEL.CGO" 2>/dev/null || echo 0)
echo "PROVENANCE kernel_cgo_octets=$KSZ (92176=x86) gk_md5=$(md5sum $GK | cut -c1-12) date=$(date -Is)"
[ "$KSZ" = 92176 ] || { echo "FAIL: out/jak1/iso n'est PAS x86 — course refusee"; exit 1; }
sed -i "s/^version = .*/version = #x1000B00000000/;s/^recharged-grass? = .*/recharged-grass? = #t/;s/^recharged-grass-precomputed? = .*/recharged-grass-precomputed? = #t/;s/^recharged-grass-density = .*/recharged-grass-density = 150.0000/" "$SETTINGS"

stdbuf -oL -eL "$GK" --game jak1 --portable -fakeiso --verbose --disable-ansi \
    -iso-data "$ISO" -- -boot -debug-mem > "$LOG" 2>&1 &
sleep 2
GKPID=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true)
[ -n "$GKPID" ] || { echo "FAIL: gk n'a pas demarre"; exit 1; }
FIFO="$(mktemp -u)"; mkfifo "$FIFO"
cleanup(){ exec 3>&- 2>/dev/null || true; [ -n "${GCPID:-}" ] && kill "$GCPID" 2>/dev/null; P=$(pgrep -n -f "game/gk --game jak1 --portable -fakeiso" || true); [ -n "$P" ] && kill "$P" 2>/dev/null; rm -f "$FIFO"; }
trap cleanup EXIT
for i in $(seq 1 240); do [ -d "/proc/$GKPID" ] || break; grep -qa "BOOTLINE etape=titre-affiche" "$LOG" && break; sleep 1; done
sleep 3
timeout 1800 "$GOALC" --game jak1 --proj-path . --iso-path "$ISO" < "$FIFO" > "$GCLOG" 2>&1 & GCPID=$!
exec 3>"$FIFO"
# `(lt)` SEUL NE SUFFIT PAS : goalc n'a aucun symbole du jeu avant `(build-game)`, et
# `(format ...)` repond alors « No method or function named format for type int » — la course
# s'arreterait sur un « listener non connecte » alors que le listener EST connecte.
echo '(lt)' >&3
echo '(build-game)' >&3
for i in $(seq 1 420); do sleep 1; grep -qiE "Successfully built all|Build Successful" "$GCLOG" 2>/dev/null && break; done
sleep 3
live=0
for att in 1 2 3; do
  echo "(format 0 \"REPL-LIVE~%\")" >&3
  for i in $(seq 1 15); do sleep 1; grep -qa "REPL-LIVE" "$LOG" && { live=1; break; }; done
  [ "$live" = 1 ] && break
  echo '(lt)' >&3; sleep 5
done
[ "$live" = 1 ] || { echo "FAIL: listener goalc non connecte"; exit 1; }
echo '(initialize! *game-info* (quote game) (the-as game-save #f) "game-start")' >&3
for i in $(seq 1 120); do sleep 1; [ "$(grep -ac 'PLACE-TIME' "$LOG" | head -1)" -ge 1 ] && break; done
echo "== etat NORMAL (curseur a 150) =="; grep -a 'PLACE-TIME' "$LOG" | tail -1 | cut -c1-200
echo "== on monte le curseur de densite a $DHI (au-dessus de la densite du bake) =="
echo "(set! (-> *pc-settings* recharged-grass-density) $DHI.0)" >&3
for i in $(seq 1 120); do sleep 1; [ "$(grep -ac 'PLACE-TIME' "$LOG" | head -1)" -ge 2 ] && break; done
sleep 3
echo "== RAISON DU REPLI, telle qu'elle sort =="; grep -a 'PRECOMPUTED unavailable' "$LOG" | tail -2
echo "== etat APRES =="; grep -a 'PLACE-TIME' "$LOG" | tail -1 | cut -c1-200
echo "== le jeu vit-il encore ? =="; [ -d "/proc/$GKPID" ] && echo "VIVANT" || echo "MORT"
