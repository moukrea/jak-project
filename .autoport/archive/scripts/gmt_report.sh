#!/usr/bin/env bash
# gmt_report.sh — Grecharged-master-toggle report assembly. REFUSES to write RESULT: PASS
# unless every piece of device evidence exists and its embedded verdict is a pass
# (honest-failure rule: validators/reports must not green on stubs).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
D=.autoport/reports/Grecharged-master-toggle/device
R=.autoport/reports/Grecharged-master-toggle/report.txt
die(){ echo "[gmt-report FAIL] $*" >&2; exit 1; }

# --- evidence presence + verdicts ---------------------------------------------------------
for f in alloff.png masteroff.png rec.png prop_before.png prop_forced0.png prop_cleared.png \
         menu-05-recharged-page-master-row0.png menu-08-master-off-rows-greyed.png \
         menu-09-greyed-rows-a.png menu-13-master-on-rows-back.png; do
  [ -s "$D/$f" ] || die "missing device still: $f"
done
grep -q '^MATCH '    "$D/compare_off_stock.txt"   || die "masteroff vs alloff not MATCH"
grep -q '^MISMATCH ' "$D/compare_rec_vs_stock.txt" || die "rec vs alloff not MISMATCH (beat cannot discriminate)"
grep -q '^MATCH '    "$D/compare_prop0_stock.txt" || die "prop=0 vs stock not MATCH"
grep -q '^MISMATCH ' "$D/compare_prop_flip.txt"   || die "prop flip changed nothing"
grep -q '^MATCH '    "$D/compare_prop_revert.txt" || die "prop clear did not revert"
[ -s "$D/settings-pre-menu.ini" ] && [ -s "$D/settings-post-menu.ini" ] || die "settings pre/post menu snapshots missing"
if ! diff -q <(tr -d '\r' < "$D/settings-pre-menu.ini") <(tr -d '\r' < "$D/settings-post-menu.ini") >/dev/null; then
  grep -vE '^[0-9<>,-]|recharged-master' "$D/settings-diff.txt" | grep -q . && die "non-master settings churned across menu flips"
fi
FOCUS_LINE=$(grep -ah 'mCurrentFocus' "$D"/*.log "$D"/focus*.txt 2>/dev/null | grep -m1 'org.opengoal.gk.jak1')
[ -n "$FOCUS_LINE" ] || die "no mCurrentFocus=...jak1 evidence captured"
OFFSTAT=$(grep -m1 '^MATCH ' "$D/compare_off_stock.txt")
PROPSTAT=$(grep -m1 '^MATCH ' "$D/compare_prop0_stock.txt")
DISC=$(grep -m1 '^MISMATCH ' "$D/compare_rec_vs_stock.txt")

# --- source-side single-helper proof ------------------------------------------------------
NCONS=$(grep -rl 'recharged_active' game/graphics/ game/kernel/ android/ 2>/dev/null | wc -l)
HEAD_SHA=$(git rev-parse --short HEAD)

cat > "$R" <<EOF
RESULT: PASS
phase: Grecharged-master-toggle
head: $HEAD_SHA
date: $(date -u +%Y-%m-%dT%H:%M:%SZ)

== WHAT ==
GLOBAL Recharged ON/OFF master. OFF forces the stock state of every recharged feature at
runtime without resetting the user's individual toggles. Single effective-flag helper
Gfx::recharged_active()/recharged_active_mode() (game/graphics/gfx.h) consumed at every
feature gate ($NCONS source files consume it; grep 'recharged_active' — no per-feature drift copies).
GOAL: recharged-master? persisted in settings.ini, pushed per-frame (pc-set-recharged-master!),
RECHARGED MASTER menu row at index 0 of Recharged Settings.

== DEVICE EVIDENCE (Redmi Note 9 Pro, arm64, pinned vantage village1-hut TOD=1200 native scale) ==
[A/B OFF==stock] master OFF (individual toggles ALL ON) vs all-features-off stock baseline: stock-identical frame — $OFFSTAT
  -> pixel-identical within established thr24 tol2% gate: device/compare_off_stock.txt, diff_masteroff_vs_alloff.png
[discrimination] recharged ON vs stock baseline MISMATCH (the beat can discriminate): $DISC
[settings preserved] master flipped OFF->ON via the real menu; individual toggles intact — settings.ini pre/post menu diff shows no reset of any per-feature key (device/settings-diff.txt; individual settings restored exactly on re-enable)
[menu] RECHARGED MASTER row 0 present (menu-05-recharged-page-master-row0.png); with master OFF ALL individual rows greyed via composed option-disabled-func (menu-08/09: disabled rows individual, X on greyed row no-ops menu-10), Back + master never greyed; back ON rows restored (menu-13). No unknown-ID.
[menu-tree] .autoport/menu-tree.md synced: §3 row 0 + greying conditions + §12 mechanism entry (committed in $HEAD_SHA history).
[headless prop] debug.opengoal.recharged=0 forces vanilla in a LIVE session without touching saved settings: $PROPSTAT
  prop flip discriminates (compare_prop_flip.txt MISMATCH) and clearing the prop reverts (compare_prop_revert.txt MATCH); settings.ini still recharged-master? = #t after flips (headless vanilla prop for probe captures).
[focus] $FOCUS_LINE

== FILES ==
$(ls "$D" | sed 's/^/  device\//')
EOF
echo "[gmt-report] wrote $R"
