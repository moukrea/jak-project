#!/usr/bin/env bash
# zone_sweep_qemu.sh — device-independent arm64 zone-crash sweep under qemu-aarch64.
# Loads + relocates (links) every level DGO with the headless linux-arm64 gk under
# qemu, one DGO per invocation (isolated fresh sweep heap). Reports per-DGO:
#   OK            — all objects linked + relocated clean (no arm64 codegen/link crash)
#   LINK-RC=N     — clean direct-loader reject (e.g. oversized object), NOT a crash
#   CRASH sig=N   — a real signal during link (arm64 codegen / relocation defect)
# Link-only by default (no top-level execute): the execute path runs the tpage
# texture-upload forms which crash uniformly in this NO-GL headless build for
# EVERY level (proven on known-good VI1) — a build artifact, not a per-level bug.
# Real gameplay + render crash classes are device-only.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
GK="build-arm64-linux/game/linux-arm64/gk"
QEMU="qemu-aarch64 -L /usr/aarch64-linux-gnu"
OUT=".autoport/reports/Gzone-sweep"
mkdir -p "$OUT"
DGOS="${1:-VI1.DGO VI2.DGO VI3.DGO BEA.DGO JUN.DGO MIS.DGO TRA.DGO FIC.DGO OGR.DGO ROL.DGO SUN.DGO SWA.DGO LAV.DGO CIT.DGO DAR.DGO FIN.DGO INT.DGO JUB.DGO MAI.DGO ROB.DGO SNO.DGO SUB.DGO DEM.DGO TSZ.DGO}"
TABLE="$OUT/zone-sweep-table.txt"
: > "$TABLE"
echo "=== Gzone-sweep (qemu-arm64, link-only) $(date -Iseconds) ===" | tee -a "$TABLE"
echo "gk built-sha: $(git rev-parse --short HEAD)  gk: $GK" | tee -a "$TABLE"
printf "%-10s | %-8s | %s\n" "DGO" "RESULT" "detail" | tee -a "$TABLE"
printf -- "-----------+----------+------------------------------------------\n" | tee -a "$TABLE"
for DGO in $DGOS; do
  LOG="$OUT/sweep-$DGO.log"
  OG_ZONE_SWEEP_DGOS="$DGO" timeout 400 $QEMU "$GK" > "$LOG" 2>&1
  EX=$?
  if grep -aqE "SWEEP $DGO OK" "$LOG"; then
    NS=$(grep -aoE "SWEEP $DGO OK \(NumSymbols=[0-9]+\)" "$LOG" | grep -oE "[0-9]+" | tail -1)
    printf "%-10s | %-8s | all objects linked+relocated, NumSymbols=%s\n" "$DGO" "OK" "$NS" | tee -a "$TABLE"
  elif grep -aqE "GK-DIAG sig=|uncaught target signal" "$LOG"; then
    SIG=$(grep -aoE "GK-DIAG sig=[0-9]+|uncaught target signal [0-9]+" "$LOG" | head -1)
    LASTLINK=$(grep -aE "link finish:" "$LOG" | tail -1 | sed -E 's/.*link finish: //')
    printf "%-10s | %-8s | %s ; last-link=%s\n" "$DGO" "CRASH" "$SIG" "$LASTLINK" | tee -a "$TABLE"
  elif grep -aqE "SWEEP $DGO LINK-RC=" "$LOG"; then
    RC=$(grep -aoE "SWEEP $DGO LINK-RC=-?[0-9]+" "$LOG" | head -1)
    OBJ=$(grep -aoE "exceeds buffer" "$LOG" | head -1)
    printf "%-10s | %-8s | %s (clean reject: %s)\n" "$DGO" "RC" "$RC" "${OBJ:-loader-rc}" | tee -a "$TABLE"
  elif grep -aqE "SWEEP $DGO MISSING" "$LOG"; then
    printf "%-10s | %-8s | DGO not present in out/jak1-arm64/iso\n" "$DGO" "MISSING" | tee -a "$TABLE"
  else
    printf "%-10s | %-8s | exit=%d, no SWEEP marker (see %s)\n" "$DGO" "UNKNOWN" "$EX" "$LOG" | tee -a "$TABLE"
  fi
done
echo "=== sweep complete $(date -Iseconds) ===" | tee -a "$TABLE"
