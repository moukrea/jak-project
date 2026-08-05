#!/usr/bin/env bash
# Grecharged-hd-models4 — DEFECT CYCLE 4 validator (owner verdict 2026-08-05 ~08:15 on the
# menu+cycle-3 build). VICTORIES LOCKED (zero regression): Jak clothing-clip gone, Daxter perfect,
# Samos beard fixed, donor-iris eyes, NPCs stable in cutscenes, faces alive x4.
# New cycle-4 bar (2 items): (1) VISIBLE natural blink on all four HD faces — the cycle-3
# blink-black fix (lid-blit skip on HD slots) over-corrected and killed the visible blink; fix =
# donor lid texture blit or donor blink blend-targets driven by the driver's lid channel; must NOT
# re-introduce black eyes. (2) Keira's straps clip through the FRONT of her torso — strap-chain
# k->e mapping fix. All cycle-1/2/3 gates CARRIED (append-only, integrity, per-actor coverage,
# class lines re-stated against the CURRENT bake, FACE-FINGER-GATE physical check, device proof).
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
# phase-NEW marker: this must be the CYCLE-4 report, not a refresh of cycle 3's
grep -qE 'DEFECT-CYCLE-4' "$R" || fail "no DEFECT-CYCLE-4 marker — cycle-3 report re-submitted?"

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

# ---- CYCLE-4 item 1 — VISIBLE blink on all four HD faces (owner 08:15) -----------------------
grep -qiE '^CYCLE4-BLINK.*root.?cause' "$R" \
  || fail "CYCLE4-BLINK: no root-cause line (why the cycle-3 fix killed the visible blink)"
grep -qiE '^CYCLE4-BLINK.*(donor|lid|eyelid|blend.?target).*(mechanism|implement|port|blit|driv)' "$R" \
  || fail "CYCLE4-BLINK: no mechanism line (donor lid blit or blend-target drive)"
for c in jak dax keira samos; do
  grep -qiE "^CYCLE4-BLINK.*${c}.*PASS" "$R" \
    || fail "CYCLE4-BLINK: no visible-blink PASS line for ${c}"
done
# proof = renderer-side state/counter evidence (lid value excursion / target weight over time),
# NEVER captures (owner rule 2026-08-04 'pour toujours')
grep -qiE '^CYCLE4-BLINK-PROOF.*(state|dump|counter|log|value|weight|amplitude|excursion|channel)' "$R" \
  || fail "CYCLE4-BLINK-PROOF: no renderer-side/state-dump proof line"
grep -qiE '^CYCLE4-BLINK.*(no|zero|not)[^.]*black' "$R" \
  || fail "CYCLE4-BLINK: no statement that blink does NOT re-introduce black eyes (CYCLE3-KEIRA acquis)"

# ---- CYCLE-4 item 2 — Keira straps must not clip through the front of her torso --------------
grep -qiE '^CYCLE4-KEIRA-STRAP.*(root.?cause|joint|chain|map)' "$R" \
  || fail "CYCLE4-KEIRA-STRAP: no root-cause/mapping line"
grep -qiE '^CYCLE4-KEIRA-STRAP.*(fix|remap|follow|resolve).*PASS' "$R" \
  || fail "CYCLE4-KEIRA-STRAP: no fix PASS line"
# widened scope (owner ~10:35, M5 accepted): the strap fix must cover BOTH keira looks
grep -qiE '^CYCLE4-KEIRA-STRAP.*keira3' "$R" \
  || fail "CYCLE4-KEIRA-STRAP: no keira3-hd (second look) coverage line (owner 10:35 widening)"

# ---- CYCLE-4 item 3 (owner ~10:35) — Jak 3 MASQUE BAISSE as 5th JAK LOOK option --------------
# physical-artifact checks first (objdump/nm-class evidence beats report greps)
grep -qE 'jakm-hd' goal_src/jak1/pc/jak-hd.gc \
  || fail "CYCLE4-MASKED: jakm-hd absent from the jak-hd.gc registry"
grep -qE '17b6' goal_src/jak1/pc/progress-pc.gc \
  || fail "CYCLE4-MASKED: no #x17b6 5th JAK LOOK carousel option in progress-pc.gc"
grep -qE 'jakm-hd-ag\.go' scripts/package_hd_assets.sh \
  || fail "CYCLE4-MASKED: jakm-hd-ag.go not in the external pack list"
grep -qE 'jakm-hd-ag\.go' game/graphics/opengl_renderer/loader/Loader.cpp \
  || fail "CYCLE4-MASKED: jakm-hd-ag.go not in the Loader ag staging list"
[ -f recharged_assets/hd_anim/jakm-hd-ag.go ] \
  || fail "CYCLE4-MASKED: recharged_assets/hd_anim/jakm-hd-ag.go missing"
grep -qiE '^CYCLE4-MASKED.*(target|blerc).*(bake|baked)' "$R" \
  || fail "CYCLE4-MASKED: no goggle-target bake mechanism/evidence line"
grep -qiE '^CYCLE4-MASKED.*jakm-hd.*(append|integr|draws|proven)' "$R" \
  || fail "CYCLE4-MASKED: no jakm-hd append/integrity line"
grep -qiE '^CYCLE4-MASKED.*(SUBMITTED|submit)' "$R" \
  || fail "CYCLE4-MASKED: no device submit-counter proof line"
grep -qiE '^CYCLE4-MASKED.*(face|blerc|lipsync).*(live|animat|preserved|PASS)' "$R" \
  || fail "CYCLE4-MASKED: no faces-still-live line (owner DoD: every look complete from day one)"

# ---- NO-REGRESSION on the owner's 08:15 locked victories -------------------------------------
grep -qiE '^NO-REGRESS.*(pupil|iris).*donor.*(PASS|intact|proven)' "$R" \
  || fail "no NO-REGRESS donor-iris/pupils line (owner 08:15 acquis: eyes = HD versions)"

# ---- backport definition-of-done: LOUD-FAIL k->e generator (owner ~11:30, carried) -----------
grep -qE 'FACE-FINGER-GATE' scripts/shell/retarget_fill_table.py \
  || fail "retarget_fill_table.py has no FACE-FINGER-GATE enforcement (loud-fail DoD)"
grep -qiE '^FACE-FINGER-GATE.*(jak|dax|keira|samos).*PASS' "$R" \
  || fail "no FACE-FINGER-GATE PASS line (tables must be regenerated under the gate)"

# ==== DEFECT CYCLE 5 (owner verdict 2026-08-05 ~14:00 + carry 11:05) ==========================
# Locked by owner at 14:00: blinks are GOOD ("super !") — zero regression tolerated (blink gates
# above are carried unchanged). New bar:
# (1) jakm-hd BUG: the two Jak-3 looks render IDENTICAL — the baked target 15 moves only
#     lens/gogglemetal/brownstrap ~0.10-0.12 and never the face scarf; diagnose bytes+amplitude,
#     ship a look whose FACE IS ACTUALLY UNCOVERED (mask down around the neck), visibly distinct.
# (2) Keira strap residual per-anim clip — coordinate with the physics-chain phase (collision) for
#     BOTH keira looks; honest statement of behavior at every physics level incl. OFF.
# (3) CARRY owner 11:05: EXHAUSTIVE inventory of Jak CINEMATIC looks across jak2+jak3 dumps
#     (prison/experiments J2, all J3 variants; cutscene highres ONLY) + integration of ALL distinct
#     ones into the JAK LOOK carousel, each complete from day one (DoD).
grep -qE 'DEFECT-CYCLE-5' "$R" || fail "no DEFECT-CYCLE-5 marker — cycle-4 report re-submitted?"

# ---- CYCLE-5 item 1 — jakm-hd visibly distinct (bare face, mask at neck) ---------------------
grep -qiE '^CYCLE5-JAKM.*root.?cause' "$R" \
  || fail "CYCLE5-JAKM: no root-cause line (why the two looks rendered identical)"
grep -qiE '^CYCLE5-JAKM.*(byte|vert|diff|amplitude|bake)' "$R" \
  || fail "CYCLE5-JAKM: no byte/amplitude diagnosis line on the SHIPPED fr3"
grep -qiE '^CYCLE5-JAKM.*(scarf|mask|neck|bare.?face|visage)' "$R" \
  || fail "CYCLE5-JAKM: no line addressing the FACE-UNCOVERED requirement (owner 11:00 quiproquo)"
grep -qiE '^CYCLE5-JAKM.*(distinct|differ).*(PASS|proven)' "$R" \
  || fail "CYCLE5-JAKM: no quantitative distinctness PASS line (jak3-hd vs jakm-hd)"
grep -qiE '^CYCLE5-JAKM.*(SUBMITTED|submit)' "$R" \
  || fail "CYCLE5-JAKM: no device submit-counter proof line"

# ---- CYCLE-5 item 2 — Keira straps x physics chains (both looks, all physics levels) ---------
grep -qiE '^CYCLE5-KEIRA-STRAP.*(physic|chain|collision)' "$R" \
  || fail "CYCLE5-KEIRA-STRAP: no physics-chain coordination line"
grep -qiE '^CYCLE5-KEIRA-STRAP.*keira3' "$R" \
  || fail "CYCLE5-KEIRA-STRAP: no keira3-hd coverage line"
grep -qiE '^CYCLE5-KEIRA-STRAP.*(OFF|LIGHT|FULL|MAX)' "$R" \
  || fail "CYCLE5-KEIRA-STRAP: no per-physics-level behavior line (incl. PHYSICS OFF fallback)"
grep -qiE '^CYCLE5-KEIRA-STRAP.*PASS' "$R" \
  || fail "CYCLE5-KEIRA-STRAP: no PASS line"

# ---- CYCLE-5 item 3 — exhaustive cinematic-look inventory + integration ----------------------
grep -qiE '^CYCLE5-INVENTORY.*(exhaust|complete|all).*(jak2).*(jak3)|^CYCLE5-INVENTORY.*(exhaust|complete|all).*(jak3).*(jak2)' "$R" \
  || fail "CYCLE5-INVENTORY: no exhaustive-scan statement covering BOTH jak2 and jak3 dumps"
grep -qiE '^CYCLE5-LOOK-.*(prison|experiment)' "$R" \
  || fail "CYCLE5-LOOK: no line for the owner-named Jak II prison/experiments look"
NLOOK=$(grep -cE '^CYCLE5-LOOK-' "$R" || true)
[ "${NLOOK:-0}" -ge 2 ] || fail "CYCLE5-LOOK: fewer than 2 inventory lines ($NLOOK) — not exhaustive"
# every inventoried look line must be resolved: INTEGRATED, DUPLICATE-OF, ALREADY-SHIPPED or EXCEPTION
BAD=$(grep -E '^CYCLE5-LOOK-' "$R" | grep -cviE 'STATUS=(INTEGRATED|DUPLICATE-OF|ALREADY-SHIPPED|EXCEPTION)' || true)
[ "${BAD:-0}" -eq 0 ] || fail "CYCLE5-LOOK: $BAD look line(s) without STATUS=INTEGRATED/DUPLICATE-OF/ALREADY-SHIPPED/EXCEPTION"
# physical-artifact checks for every INTEGRATED look: ag on disk + registry + pack + loader staging
for AG in $(grep -E '^CYCLE5-LOOK-' "$R" | grep -E 'STATUS=INTEGRATED' | grep -oE 'ag=[a-z0-9-]+' | cut -d= -f2 | sort -u); do
  [ -f "recharged_assets/hd_anim/${AG}-ag.go" ] || fail "CYCLE5-LOOK: ${AG}-ag.go missing on disk"
  grep -qE "${AG}" goal_src/jak1/pc/jak-hd.gc || fail "CYCLE5-LOOK: ${AG} absent from jak-hd.gc registry"
  grep -qE "${AG}-ag\.go" scripts/package_hd_assets.sh || fail "CYCLE5-LOOK: ${AG}-ag.go not in external pack list"
  grep -qE "${AG}-ag\.go" game/graphics/opengl_renderer/loader/Loader.cpp || fail "CYCLE5-LOOK: ${AG}-ag.go not in Loader staging"
  grep -qiE "^CYCLE5-LOOK-.*ag=${AG}.*(FACE-FINGER-GATE|gate).*(PASS)" "$R" \
    || fail "CYCLE5-LOOK: ${AG} has no FACE-FINGER-GATE PASS on its own line (DoD: complete from day one)"
  grep -qiE "^CYCLE5-LOOK-.*ag=${AG}.*(append|integr|draws)" "$R" \
    || fail "CYCLE5-LOOK: ${AG} has no append/integrity/draws evidence on its own line"
done
# at least one look must actually be INTEGRATED this cycle (the inventory alone is not the mission)
grep -qE '^CYCLE5-LOOK-.*STATUS=INTEGRATED' "$R" \
  || fail "CYCLE5-LOOK: no look INTEGRATED this cycle (owner: 'il me les FAUT TOUS')"
grep -qiE '^CYCLE5-LOOK.*(SUBMITTED|submit)' "$R" \
  || fail "CYCLE5-LOOK: no device submit-counter proof line for the new looks"

# ---- NO-REGRESSION on the owner's 14:00 locked victory: visible blink ------------------------
grep -qiE '^NO-REGRESS.*blink.*(PASS|intact|proven)' "$R" \
  || fail "no NO-REGRESS blink line (owner 14:00: blinks are good — locked)"

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