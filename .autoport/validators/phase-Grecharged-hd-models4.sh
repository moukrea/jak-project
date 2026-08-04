#!/usr/bin/env bash
# Grecharged-hd-models4 — DEFECT CYCLE 3 validator (owner verdict 2026-08-04 ~19:00 on the cycle-2
# build). ACQUIS to protect: faces ALIVE x4. New bar: P1 NPC-flicker REGRESSION root-caused+fixed,
# Daxter fur holes + lower face, Jak gap+clip (2-cycle survivors), Samos beard chain, Keira
# blink-black-eyes. Cycle-1/2 gates CARRIED (append-only, integrity, per-actor coverage, six class
# lines re-stated against the CURRENT bake, FACE-FINGER-GATE physical check, device proof).
# Line-based greps: every required fact must sit on ONE report line.
set -uo pipefail
fail(){ echo "[Ghdmodels4 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models4/report.txt
[ -f "$R" ] || fail "no report (reports/Grecharged-hd-models4/report.txt)"

# freshness vs THIS phase's (re)start — the cycle-2 report is stale evidence by definition
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
# phase-NEW marker: this must be the CYCLE-3 report, not a refresh of cycle 2's
grep -qE 'DEFECT-CYCLE-3' "$R" || fail "no DEFECT-CYCLE-3 marker — cycle-2 report re-submitted?"

# ---- carried cycle-1 gates -------------------------------------------------------------------
for c in dax keira samos; do
  grep -qiE "${c}-hd-lod0.*(append|integr|visible|proven)|SKIP.*${c}" "$R" \
    || fail "no append/skip evidence for ${c}-hd-lod0"
done
grep -qiE 'append.?only' "$R" || fail "append-only statement missing"
grep -qiE 'integrity.*(pass|identical)' "$R" || fail "integrity gate missing"
grep -qiE '(logo|per.?actor|coverage).*(fix|cover|suppress|resolved|proven|implemented)' "$R" \
  || fail "logo/per-actor coverage line missing"

# ---- carried cycle-2 class lines (must hold on the CURRENT bake — no silent regression) ------
grep -qiE '^CLASS-C.*dax.*jaw' "$R" || fail "CLASS-C dax jaw line missing (carried)"
for c in jak keira samos; do
  grep -qiE "^CLASS-A.*${c}.*eye.*PASS" "$R" || fail "CLASS-A: no eye PASS line for ${c} (carried)"
done
if ! grep -qiE '^CLASS-B.*blerc.*ALL-CHANNELS.*PASS' "$R"; then
  grep -qiE '^CLASS-B.*blerc.*PARTIAL' "$R" \
    || fail "CLASS-B: need blerc ALL-CHANNELS PASS or an honest PARTIAL line (carried)"
  grep -qiE '^CLASS-B-EXCEPTION:.*' "$R" \
    || fail "CLASS-B PARTIAL without per-channel CLASS-B-EXCEPTION lines (carried)"
fi
grep -qiE '^CLASS-F.*keira.*(sandal|boot).*(verdict|confirmed|correct|sourced)' "$R" \
  || fail "CLASS-F: no Keira sourcing verdict line (carried)"

# ---- NO-REGRESSION on the owner's locked-in acquis: faces alive ------------------------------
grep -qiE '^NO-REGRESS.*(face|blerc).*(alive|animat).*(proof|proven|PASS)' "$R" \
  || fail "no NO-REGRESS faces-alive line (owner acquis 19:00 must be protected)"

# ---- CYCLE-3 P1 — NPC flicker regression (blocks everything) ---------------------------------
grep -qiE '^REGRESSION-FLICKER.*root.?cause' "$R" \
  || fail "REGRESSION-FLICKER: no root-cause line"
grep -qiE '^REGRESSION-FLICKER.*(fix|resolved|repaired).*(PASS|proven)' "$R" \
  || fail "REGRESSION-FLICKER: no fix PASS line"
grep -qiE '^REGRESSION-FLICKER.*(counter|detector|zero|0).*(cutscene|intro|scene)' "$R" \
  || fail "REGRESSION-FLICKER: no counter/detector-based cutscene proof line (metrics not eyeballs)"

# ---- CYCLE-3 Daxter — fur holes + lower face -------------------------------------------------
grep -qiE '^CYCLE3-DAX.*fur.*(hole|transparen|see.?through).*(root.?cause|mode|alpha|backface|shell|cull)' "$R" \
  || fail "CYCLE3-DAX: no fur-holes root-cause line"
grep -qiE '^CYCLE3-DAX.*fur.*PASS' "$R" || fail "CYCLE3-DAX: no fur PASS line"
grep -qiE '^CYCLE3-DAX.*(jaw|lower.?face).*(visible|restored|opaque|PASS)' "$R" \
  || fail "CYCLE3-DAX: no lower-face line"

# ---- CYCLE-3 Jak — 2-cycle survivors, for good -----------------------------------------------
grep -qiE '^CYCLE3-JAK.*(gap|scalp|hair|headband|bandeau).*(root.?cause|closed|fixed).*PASS' "$R" \
  || fail "CYCLE3-JAK: no scalp-gap PASS line"
grep -qiE '^CYCLE3-JAK.*clip.*(root.?cause|fixed|resolved).*PASS' "$R" \
  || fail "CYCLE3-JAK: no clothing-clip PASS line"

# ---- CYCLE-3 Samos — beard chain follows, no rest-pose tip -----------------------------------
grep -qiE '^CYCLE3-SAMOS.*beard.*(tip|chain).*(follow|map|joint).*PASS' "$R" \
  || fail "CYCLE3-SAMOS: no beard-chain PASS line"

# ---- CYCLE-3 Keira — blink must not black the eyes -------------------------------------------
grep -qiE '^CYCLE3-KEIRA.*blink.*(root.?cause|eye|texture|uv|slot).*PASS' "$R" \
  || fail "CYCLE3-KEIRA: no blink PASS line"

# ---- backport definition-of-done: LOUD-FAIL k->e generator (owner ~11:30, carried) -----------
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
# OWNER RULE 2026-08-04 ("pour toujours"): captures are NEVER a validation instrument — illustration
# for the owner only. Visibility/regression evidence must be RENDERER-SIDE COUNTERS / state dumps
# (greppable, reproducible). The NPC-disappearance proof = per-actor merc-submit counters over the
# FULL cutscene showing ZERO long dropout windows (an in-scene actor's submits never fall to 0 for
# >N frames without a legitimate hidden state).
grep -qiE '(submit|draw).{0,80}(counter|per.?frame|per.?actor)|counter.{0,60}(submit|draw)' "$R" \
  || fail "no renderer-side counter evidence (per-actor submit counters required; captures don't count)"
grep -qiE '(0|zero|no) *(dropout|disappear|gap|blackout).{0,30}window|window.{0,30}(=|: ?)(0|zero|none)' "$R" \
  || fail "no zero-disappearance-window statement over the full cutscene (counter-based)"
echo "[Ghdmodels4 PASS]"