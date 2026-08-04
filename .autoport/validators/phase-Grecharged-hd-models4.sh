#!/usr/bin/env bash
# Grecharged-hd-models4 — DEFECT CYCLE 2 validator (owner verdict 2026-08-04 ~10:5x + corrections
# ~11:05 (class B bar = ALL facial anims) and ~11:30 (backport definition-of-done in the pipeline)).
# Cycle-1 gates (append-only, integrity, per-actor coverage, device proof) REMAIN and the six
# defect classes are ADDED. Line-based greps: every required fact must sit on ONE report line.
set -uo pipefail
fail(){ echo "[Ghdmodels4 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models4/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-hd-models4/report.txt)"

# freshness vs THIS phase's (re)start — the cycle-1 report is stale evidence by definition
PSTART=$(python3 -c "
import json
try:
    s=json.load(open('.autoport/state.json'))
    print(int(s.get('phase_started_at',{}).get('Grecharged-hd-models4',0)))
except Exception:
    print(0)")
if [ "$PSTART" -gt 0 ]; then
  RMT=$(stat -c %Y "$R" 2>/dev/null || echo 0)
  [ "$RMT" -gt "$PSTART" ] || fail "report older than this phase's start — stale evidence"
fi
grep -qiE 'RESULT:' "$R" || fail "no RESULT: line"
# phase-NEW marker: this must be the CYCLE-2 report, not a refresh of cycle 1's
grep -qE 'DEFECT-CYCLE-2' "$R" || fail "no DEFECT-CYCLE-2 marker — cycle-1 report re-submitted?"

# ---- carried cycle-1 gates -------------------------------------------------------------------
for c in dax keira samos; do
  grep -qiE "${c}-hd-lod0.*(append|integr|visible|proven)|SKIP.*${c}" "$R" \
    || fail "no append/skip evidence for ${c}-hd-lod0"
done
grep -qiE 'append.?only' "$R" || fail "append-only statement missing"
grep -qiE 'integrity.*(pass|identical)' "$R" || fail "integrity gate missing"
grep -qiE '(logo|per.?actor|coverage).*(fix|cover|suppress|resolved|proven|implemented)' "$R" \
  || fail "logo/per-actor coverage line missing"

# ---- DEFECT CLASS C — lost geometry (Daxter jaw P1, Jak scalp/hair gap) ----------------------
grep -qiE '^CLASS-C.*dax.*jaw.*(draws|tris).*(parity|restored|complete|match).*PASS' "$R" \
  || fail "CLASS-C: no Daxter-jaw geometry-parity PASS line (draws/tris donor vs appended)"
grep -qiE '^CLASS-C.*jak.*(scalp|hair|head).*(parity|restored|complete|match|root.?cause)' "$R" \
  || fail "CLASS-C: no Jak scalp/hair-gap line"

# ---- DEFECT CLASS A — eyes/glasses functional (eye_id) on ALL appended mercs -----------------
for c in jak keira samos; do
  grep -qiE "^CLASS-A.*${c}.*eye.*PASS" "$R" || fail "CLASS-A: no eye PASS line for ${c}"
done

# ---- DEFECT CLASS D — k->e mapping precision (fingers/beard/clothing) ------------------------
grep -qiE '^CLASS-D.*keira.*finger.*(PASS|root.?cause.*fix)' "$R" || fail "CLASS-D: no Keira fingers line"
grep -qiE '^CLASS-D.*samos.*beard.*(PASS|root.?cause.*fix)' "$R" || fail "CLASS-D: no Samos beard line"
grep -qiE '^CLASS-D.*jak.*(cloth|clip).*' "$R" || fail "CLASS-D: no Jak clothing-clip line"

# ---- DEFECT CLASS E — Daxter fur transparency ------------------------------------------------
grep -qiE '^CLASS-E.*fur.*(alpha|draw.?order|backface|mode).*PASS' "$R" || fail "CLASS-E: no fur PASS line"

# ---- DEFECT CLASS B — facial animation: ALL driver blerc channels (owner ~11:05) -------------
if ! grep -qiE '^CLASS-B.*blerc.*ALL-CHANNELS.*PASS' "$R"; then
  grep -qiE '^CLASS-B.*blerc.*PARTIAL' "$R" \
    || fail "CLASS-B: need blerc ALL-CHANNELS PASS or an honest PARTIAL line"
  grep -qiE '^CLASS-B-EXCEPTION:.*' "$R" \
    || fail "CLASS-B PARTIAL without per-channel CLASS-B-EXCEPTION lines (owner: case-by-case proof)"
fi

# ---- DEFECT CLASS F — Keira sourcing verdict -------------------------------------------------
grep -qiE '^CLASS-F.*keira.*(sandal|boot).*(verdict|confirmed|correct|sourced)' "$R" \
  || fail "CLASS-F: no Keira sandals/boots sourcing verdict line"

# ---- backport definition-of-done: LOUD-FAIL k->e generator (owner ~11:30) --------------------
# physical artifact: the generator itself must carry the face/finger gate, not just the report.
grep -qE 'FACE-FINGER-GATE' scripts/shell/retarget_fill_table.py \
  || fail "retarget_fill_table.py has no FACE-FINGER-GATE enforcement (loud-fail DoD)"
grep -qiE '^FACE-FINGER-GATE.*(jak|dax|keira|samos).*PASS' "$R" \
  || fail "no FACE-FINGER-GATE PASS line (tables must be regenerated under the gate)"

# ---- device proof ----------------------------------------------------------------------------
DEV=""
for s2 in eae4df44 AREE026206000788; do
  if adb devices 2>/dev/null | grep -qE "^${s2}[[:space:]]+device$"; then DEV="$s2"; break; fi
done
[ -n "$DEV" ] || fail "no proof device connected"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"
grep -qiE 'crash|exit-info' "$R" || fail "no crash-free/exit-info evidence line"
# fresh captures only (>= 4: at least one per character), newer than the phase restart
FRAMES=0
while IFS= read -r f; do
  [ "$PSTART" -gt 0 ] && [ "$(stat -c %Y "$f")" -le "$PSTART" ] && continue
  FRAMES=$((FRAMES+1))
done < <(find .autoport/reports/Grecharged-hd-models4 -type f \( -name '*.png' -o -name '*.mp4' \) 2>/dev/null)
[ "$FRAMES" -ge 4 ] || fail "need FRESH capture evidence (>=4 newer than phase restart, found $FRAMES)"
echo "[Ghdmodels4 PASS]"
