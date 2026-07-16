#!/usr/bin/env bash
# ao_attempt5_chain.sh — attempt-5 stage chain after the resume deploy:
#   wait(deploy) -> title gate (15 persisted boots) -> proof battery -> report -> validator
# Each stage gates on the previous one's success marker; first failure aborts the chain
# so no device time is wasted on proofs of a broken stage.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
OUT=.autoport/reports/Grecharged-ambient-occlusion
BDLOG="$OUT/build-deploy-attempt16.log"
mark(){ echo "[chain $(date +%H:%M:%S)] $*"; }

mark "stage 1: wait for deploy resume to finish"
while pgrep -f 'ao_build_deploy_resume\.sh' >/dev/null 2>&1; do sleep 15; done
grep -q '\[ao-build\] DONE' "$BDLOG" || { mark "STAGE-FAIL deploy: no [ao-build] DONE in $BDLOG"; tail -15 "$BDLOG"; exit 1; }
mark "stage 1 OK: deploy DONE (deploy_verify + assets + text PASS)"

mark "stage 2: title gate (15 persisted-combo boots, ~1h)"
bash .autoport/ao_title_gate.sh > "$OUT/chain-title-gate.log" 2>&1
grep -q '\[TITLE-GATE PASS\]' "$OUT/title-gate/gate-log.txt" || { mark "STAGE-FAIL title gate"; tail -25 "$OUT/title-gate/gate-log.txt" 2>/dev/null; exit 2; }
mark "stage 2 OK: TITLE-GATE PASS ($(grep -c 'combo .*: PASS' "$OUT/title-gate/gate-log.txt")/15 combos)"

mark "stage 3: proof battery (menu+safeboot+vantages+strengthgrid+fps, ~2.5h)"
bash .autoport/ao_proof_battery.sh > "$OUT/chain-proof-battery.log" 2>&1
grep -q '\[ao-proof-battery\] DONE' "$OUT/proof-battery-log.txt" || { mark "STAGE-FAIL proof battery"; tail -25 "$OUT/proof-battery-log.txt" 2>/dev/null; exit 3; }
mark "stage 3 OK: proof battery DONE"

mark "stage 4: assemble report from verified artifacts"
bash .autoport/ao_report.sh > "$OUT/chain-report.log" 2>&1 || { mark "STAGE-FAIL report assembler"; tail -25 "$OUT/chain-report.log"; exit 4; }
mark "stage 4 OK: report assembled"

mark "stage 5: phase validator"
bash .autoport/validators/phase-Grecharged-ambient-occlusion.sh || { mark "STAGE-FAIL validator"; exit 5; }
mark "CHAIN COMPLETE: validator PASS"
