#!/usr/bin/env bash
# ao_closing_chain.sh — closing-round chain on the attempt17 grazing-gate build (owner
# 2026-07-16 14:25 gate shape): fast worst-case title spot check (replaces the dropped
# 15-combo matrix) -> full proof battery (menu+safeboot+vantages+strengthgrid+fps on the
# NEW build; the 13:11 battery ran on the previous build and its training/grid gates
# FAILED — that is what attempt17 fixes) -> report assembler -> phase validator.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Grecharged-ambient-occlusion
mark(){ echo "[chain $(date +%H:%M:%S)] $*"; }

mark "stage 1: worst-case title spot check (GTAO+High+Stronger, ~4 min)"
bash .autoport/ao_title_spotcheck.sh > "$OUT/chain-spotcheck.log" 2>&1
grep -q '\[TITLE-SPOTCHECK PASS\]' "$OUT/title-gate/spotcheck-log.txt" || { mark "STAGE-FAIL spot check"; tail -25 "$OUT/title-gate/spotcheck-log.txt" 2>/dev/null; exit 1; }
mark "stage 1 OK: TITLE-SPOTCHECK PASS"

mark "stage 2: proof battery on the grazing-gate build (~50 min)"
bash .autoport/ao_proof_battery.sh > "$OUT/chain-proof-battery.log" 2>&1
grep -q '\[ao-proof-battery\] DONE' "$OUT/proof-battery-log.txt" || { mark "STAGE-FAIL proof battery"; tail -25 "$OUT/proof-battery-log.txt" 2>/dev/null; exit 2; }
mark "stage 2 OK: proof battery DONE"

mark "stage 3: assemble report from verified artifacts"
bash .autoport/ao_report.sh > "$OUT/chain-report.log" 2>&1 || { mark "STAGE-FAIL report assembler"; tail -25 "$OUT/chain-report.log"; exit 3; }
mark "stage 3 OK: report assembled"

mark "stage 4: phase validator"
bash .autoport/validators/phase-Grecharged-ambient-occlusion.sh || { mark "STAGE-FAIL validator"; exit 4; }
mark "CHAIN COMPLETE: validator PASS"
