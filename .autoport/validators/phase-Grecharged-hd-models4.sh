#!/usr/bin/env bash
# Grecharged-hd-models4 — HD MODELS M2 validator: PRINCIPAL cast replacements
# (Daxter = jak3 cinematic NO-pants, Keira = jak2 first-cutscene, Samos = jak3
# cinematic) via the M1 anim-retarget pipeline, PLUS the M1 carry-over fix:
# Merc2 stock-draw suppression must be PER-ACTOR (pid-keyed coverage — the ND
# logo's eichar actor must never be suppressed without a companion covering it).
#
# Co-designed with the implementation (2026-08-04): log tags below are the ones
# the phase emits ([HD-COMP] spawn lines, [hd-render] submit/suppress lines).
# Grep discipline: every required keyword set lives on ONE report line.
#
# PROOF DEVICE: Redmi eae4df44 preferred, owner's Honor AREE026206000788
# fallback (same policy as M1). NO other serial accepted.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Ghdmodels4 FAIL] $*" >&2; exit 1; }
R=.autoport/reports/Grecharged-hd-models4/report.txt
[ -f "$R" ] || fail "no report"

# Phase-NEW marker (anti-stale, anti-recycled-M1-report).
grep -qE 'PHASE-MARKER: Grecharged-hd-models4' "$R" || fail "phase marker missing"

# RESULT line specific to THIS mandate.
grep -qiE 'RESULT:.*HD M2 PRINCIPAL CAST' "$R" || fail "no RESULT: HD M2 PRINCIPAL CAST"

# ---- per-character device proof (routed logcat quotes) -----------------------
# Companion spawn with driver identity + full HD skeleton, per character.
grep -qE '\[HD-COMP\] spawned drv=sidekick-lod0 .*jgeo-joints=[1-9][0-9]*' "$R" || fail "Daxter companion spawn line (drv=sidekick-lod0) missing"
grep -qE '\[HD-COMP\] spawned drv=assistant-lod0 .*jgeo-joints=[1-9][0-9]*' "$R" || fail "Keira companion spawn line (drv=assistant-lod0) missing"
grep -qE '\[HD-COMP\] spawned drv=sage-lod0 .*jgeo-joints=[1-9][0-9]*' "$R" || fail "Samos companion spawn line (drv=sage-lod0) missing"
# Appended merc geometry loaded by the Loader, per character.
grep -qE 'merc-load .*dax-hd-lod0'   "$R" || fail "dax-hd-lod0 merc-load line missing"
grep -qE 'merc-load .*keira-hd-lod0' "$R" || fail "keira-hd-lod0 merc-load line missing"
grep -qE 'merc-load .*samos-hd-lod0' "$R" || fail "samos-hd-lod0 merc-load line missing"
# Merc2 submission with the model FOUND, per character.
grep -qE "\[hd-render\] SUBMITTED name='dax-hd-lod0' found=1"   "$R" || fail "dax-hd SUBMITTED found=1 missing"
grep -qE "\[hd-render\] SUBMITTED name='keira-hd-lod0' found=1" "$R" || fail "keira-hd SUBMITTED found=1 missing"
grep -qE "\[hd-render\] SUBMITTED name='samos-hd-lod0' found=1" "$R" || fail "samos-hd SUBMITTED found=1 missing"

# ---- per-actor coverage (the M1 carry-over: ND-logo invisible Jak) -----------
# Suppression must be pid-keyed: a quoted suppress line naming the covered pid.
grep -qE "\[hd-render\] suppress pid=[0-9]+ name='[a-z-]+-lod0'" "$R" || fail "pid-keyed suppress line missing"
# ND-logo statement: Jak VISIBLE at the logo (HD-covered or stock, never blank).
grep -qiE 'LOGO:.*visible' "$R" || fail "LOGO: ... visible statement missing"
# Physical source check: the old global name-TTL suppression must be GONE and
# pid coverage present in the renderer.
grep -q 's_jakhd_suppress_ttl' game/graphics/opengl_renderer/foreground/Merc2.cpp && fail "global name-TTL suppression still in Merc2.cpp"
grep -qE 'covered|coverage' game/graphics/opengl_renderer/foreground/Merc2.cpp || fail "per-actor coverage absent from Merc2.cpp"
# Physical source check: the companion table drives the three new characters.
grep -q 'sidekick-lod0'  goal_src/jak1/pc/jak-hd.gc || fail "sidekick driver absent from companion table"
grep -q 'assistant-lod0' goal_src/jak1/pc/jak-hd.gc || fail "assistant driver absent from companion table"
grep -q 'sage-lod0'      goal_src/jak1/pc/jak-hd.gc || fail "sage driver absent from companion table"

# ---- objective anim-follow (code-level, not eyeball) -------------------------
grep -qiE 'bone.*(follow|track|delta)' "$R" || fail "objective bone-follow evidence missing"
grep -qiE 'unmapped.*(rest|bind|root)' "$R" || fail "unmapped-joints statement missing"

# ---- round-2 carnage guards (append-only bake, both target fr3s) -------------
grep -qiE 'append.?only' "$R" || fail "append-only bake statement missing"
grep -qiE 'GAME\.fr3.*integrity.*(pass|identical)|integrity.*(pass|identical).*GAME\.fr3' "$R" || fail "GAME.fr3 integrity gate missing"
grep -qiE 'village1\.fr3.*integrity.*(pass|identical)|integrity.*(pass|identical).*village1\.fr3' "$R" || fail "village1.fr3 integrity gate missing"

# ---- toggle semantics + recall discipline ------------------------------------
grep -qiE 'off.*(stock|identical|byte)|stock.*off' "$R" || fail "OFF==stock statement missing"
grep -qiE 'enhanced.*(off after|left off|restored|force-stop)' "$R" || fail "enhanced restore/force-stop discipline missing"

# ---- device evidence ---------------------------------------------------------
grep -qiE 'mCurrentFocus.*jak1|focus.*jak1' "$R" || fail "device jak1 foreground evidence missing"
FRAMES=$(find .autoport/reports/Grecharged-hd-models4 -type f \( -name '*.png' -o -name '*.jpg' -o -name '*.mp4' \) 2>/dev/null | wc -l)
[ "$FRAMES" -ge 3 ] || fail "need capture evidence (>=3 images/videos, found $FRAMES)"

DEVLIST=$(adb devices 2>/dev/null)
DEV=""
if [[ "$DEVLIST" == *$'\n'"eae4df44"* ]]; then DEV=eae4df44
elif [[ "$DEVLIST" == *$'\n'"AREE026206000788"* ]]; then DEV=AREE026206000788
fi
[ -n "$DEV" ] || fail "no configured proof device connected (eae4df44 / AREE026206000788)"
bash .autoport/lib/deploy_verify.sh "$DEV" jak1 >/dev/null 2>&1 || fail "deploy_verify FAIL ($DEV)"

GOLD=$(git status --porcelain .autoport/gold 2>/dev/null)
[ -z "$GOLD" ] || fail "gold not pristine"
echo "[Ghdmodels4 PASS]"
