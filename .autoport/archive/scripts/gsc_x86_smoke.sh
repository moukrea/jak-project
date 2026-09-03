#!/usr/bin/env bash
# gsc_x86_smoke.sh — NON-REGRESSION BUREAU x86. Le bureau n'a PAS d'ASTC, donc le
# niveau pre-cuit doit y etre INERTE et le chemin PNG rigoureusement inchange.
# On verifie aussi que la liberation des sommets ne casse rien.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/logs/gsc/x86-smoke; mkdir -p "$OUT"
export DISPLAY=:0
# Garde a crochets (PREFLIGHT SELF-KILL) : sans elle le motif matche sa PROPRE
# ligne de commande, et le script se tue lui-meme (sortie 144).
pkill -f '[b]uild/game/gk' 2>/dev/null; sleep 1
timeout 90 ./build/game/gk --game jak1 -boot -fakeiso -debug > "$OUT/gk.log" 2>&1 &
GK=$!
sleep 75
kill -INT $GK 2>/dev/null; sleep 3; kill $GK 2>/dev/null
wait $GK 2>/dev/null
echo "=== A54-VERTFREE ==="; grep -a "A54-VERTFREE" "$OUT/gk.log" | head
echo "=== A50-LEVRAM ==="; grep -a "A50-LEVRAM" "$OUT/gk.log" | head -6
echo "=== A55-RSS ==="; grep -a "A55-RSS" "$OUT/gk.log" | head -20
echo "=== niveau pre-cuit (doit etre INERTE sur x86) ==="; grep -ac "BAKED" "$OUT/gk.log"
echo "=== chemin PNG (doit etre PRESENT) ==="; grep -ac "custom texture replacement" "$OUT/gk.log"
echo "=== gpu caps ==="; grep -a "gpu caps" "$OUT/gk.log" | head -2
echo "=== stage texture (pire) ==="; grep -aoE 'stage [a-z]+ took [0-9.]+ ms' "$OUT/gk.log" | sort -t' ' -k4 -rn | head -4
echo "=== erreurs fatales ==="; grep -acE "Segmentation|SIGSEGV|ASSERTION|abort" "$OUT/gk.log"
