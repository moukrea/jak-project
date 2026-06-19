#!/usr/bin/env bash
# Validator — Gvistruth: prove the new visual-quality gate is TRUSTWORTHY.
# A detector is only trustworthy if it (a) FAILS on the defects the owner sees
# and (b) does NOT false-FAIL a clean render. This validator enforces both with
# an INDEPENDENT re-check (frame_compare.py on saved frames), so a lenient or
# fabricated gate cannot pass. See memory [[gate-visual-quality-not-liveness]].
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
FC=.autoport/lib/frame_compare.py
ORA=.autoport/gold/oracle-beats
KB=.autoport/reports/graphics-verify/known-bad
fail(){ echo "[Gvistruth FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Gvistruth ok] $*"; }

# 1. hardened harness markers: static-beat gating wired in + crash regex broadened + halo detector
H=.autoport/lib/verify_device_graphics.sh
grep -qE 'sig=\(4\|6\|11\)|sig=\[?4.*6.*11|GK-DIAG sig=\(' "$H" || fail "crash counter still sig=11-only (must match sig=(4|6|11))"
grep -qiE 'halo' "$H" || fail "no halo detector in harness"
# static beats must influence the overall verdict (not be ungated 'phase-confounded')
grep -qiE 'static|intro-logo.*MISMATCH|gate.*(menu|title|logo)|diff_frac.*(fail|gate)' "$H" || fail "static-beat oracle-diff is not wired into the gate verdict"

# 2. ANTI-FALSE-GREEN: the gate must FLAG the owner's defects. Independently re-verify
#    with frame_compare.py that the saved known-bad frames REALLY diverge from oracle.
for b in main-menu; do
  [ -f "$KB/$b.png" ] || fail "missing known-bad capture $KB/$b.png (must save the current defective build's frames as calibration baseline)"
  [ -f "$ORA/$b.png" ] || fail "missing oracle $ORA/$b.png"
  D=$(python3 "$FC" "$ORA/$b.png" "$KB/$b.png" --threshold 24 2>/dev/null | grep -oE 'frac=[0-9.]+' | head -1 | cut -d= -f2)
  D=${D:-0}
  python3 -c "import sys;sys.exit(0 if float('$D')>0.15 else 1)" || fail "known-bad $b diff_frac=$D is NOT high — the gate is not catching the garble the owner sees (expected >0.15)"
  ok "known-bad $b genuinely diverges from oracle (diff_frac=$D) — gate catches it"
done

# 3. NO FALSE-FAIL: oracle-vs-oracle must read clean.
for b in main-menu title-pressstart intro-logo; do
  [ -f "$ORA/$b.png" ] || continue
  S=$(python3 "$FC" "$ORA/$b.png" "$ORA/$b.png" --threshold 24 2>/dev/null | grep -oE 'frac=[0-9.]+' | head -1 | cut -d= -f2); S=${S:-1}
  python3 -c "import sys;sys.exit(0 if float('$S')<0.02 else 1)" || fail "oracle-vs-oracle $b diff_frac=$S not ~0 — detector false-FAILs a clean render"
done
ok "oracle-vs-oracle clean on all static beats — no false-FAIL"

# 4. the gate's own known-bad report must record the FAIL verdict (menu MISMATCH + a halo somewhere)
KBR=$KB/report.json
[ -f "$KBR" ] || fail "no $KBR (run the hardened gate on the CURRENT build and save the FAIL report)"
python3 - "$KBR" <<'PY' || exit 1
import json,sys
r=json.load(open(sys.argv[1])); beats={b['beat']:b for b in r.get('beats',[])}
menu=beats.get('main-menu',{}) or {}
logo=beats.get('intro-logo',{}) or {}; title=beats.get('title-pressstart',{}) or {}
bad=[]
if (menu.get('verdict') or '').upper()!='MISMATCH': bad.append("gate did NOT flag main-menu garble")
halo_logo=(logo.get('halo_excess_frac') or 0); halo_title=(title.get('halo_excess_frac') or 0)
if not (halo_logo>0.01 or halo_title>0.01): bad.append("gate did NOT flag the ND-logo/title halo the owner sees")
if bad: print("[Gvistruth FAIL] "+"; ".join(bad)); sys.exit(1)
print("known-bad report correctly flags menu garble + logo/title halo")
PY

# 5. cinematic + in-game now measurable (oracle frames present) OR explicitly documented impossible
for b in newgame-cinematic ingame-firstframe; do
  [ -f "$ORA/$b.png" ] || grep -qiE "$b.*(cannot|impossible|unmeasur)" .autoport/reports/Gvistruth-fix-summary.md 2>/dev/null \
    || fail "no oracle frame for $b and no documented impossibility — it must be MEASURED, not silently NO_ORACLE"
done
ok "cinematic/in-game beats measurable or documented"

# 6. fix-summary + a real code change
S=.autoport/reports/Gvistruth-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "Gvistruth-fix-summary.md missing or <60 lines (document metrics, thresholds, calibration evidence, why old halo read 0.0)"
git diff --name-only HEAD~3..HEAD 2>/dev/null | grep -qE '^\.autoport/lib/|^game/' || git status --porcelain | grep -qE '\.autoport/lib/|game/' || fail "no real code change under .autoport/lib/** or game/**"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Gvistruth PASS] visual gate is trustworthy: FAILS on the owner's defects (menu garble + logo/title halo), PASSES clean oracle-vs-oracle, cinematic/in-game measurable, standing gate wired. Known-good restored."
exit 0
