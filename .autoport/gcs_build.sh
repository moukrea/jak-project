#!/usr/bin/env bash
# Gcutscene-skip-all — compilation GOAL x86 sous VERROU DE LIVRAISON.
# Le verrou porte le PID de CE script, qui vit tant que la compilation dure : un verrou pose
# depuis un shell d'appel d'outil nommerait un mort (cf. registre).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Gcutscene-skip-all; mkdir -p "$OUT"
LOG="$OUT/build.log"
LOCK=.autoport/.deploy-in-progress
if [ -f "$LOCK" ]; then
  P=$(sed -n 's/.*pid=\([0-9]*\).*/\1/p' "$LOCK" | head -1)
  if [ -n "$P" ] && kill -0 "$P" 2>/dev/null; then
    echo "VERROU TENU par pid=$P — abandon"; exit 2
  fi
fi
printf 'gcs_build pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
: > "$LOG"
stdbuf -oL -eL timeout 1200 build-x86/goalc/goalc --game jak1 --proj-path . --disable-ansi \
  --cmd '(build-game)' >> "$LOG" 2>&1
echo "GOALC-EXIT=$?" >> "$LOG"
if grep -q "Successfully built all" "$LOG"; then echo "BUILD OK"; else echo "BUILD KO"; tail -40 "$LOG"; fi
