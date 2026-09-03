#!/usr/bin/env bash
# Validator — Ghalo: the ND-logo + title halo (village1/sun-glow leak) must be GONE,
# judged OBJECTIVELY by the trustworthy detector vs the v0.3.3 original — not the eye.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Ghalo FAIL] $*" >&2; bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true; exit 1; }
ok(){ echo "[Ghalo ok] $*"; }

# 1. fix-summary + real code change
S=.autoport/reports/Ghalo-fix-summary.md
[ -f "$S" ] && [ "$(wc -l < "$S")" -ge 60 ] || fail "Ghalo-fix-summary.md missing or <60 lines (where the village/sun leaks onto ND-logo/title, why prior gating is ineffective now, the fix)"
git status --porcelain 2>/dev/null | grep -qE 'goal_src/|game/' || git diff --name-only HEAD~3..HEAD 2>/dev/null | grep -qE '^goal_src/|^game/' || fail "no real code change under goal_src/** or game/**"

# 2. deploy landing guard — device provably runs fresh HEAD
bash .autoport/lib/deploy_verify.sh eae4df44 || fail "deploy not verified — device not running fresh HEAD libgk/build"

# 3. OBJECTIVE halo gate: run the trustworthy detector, require the leak GONE
bash .autoport/lib/verify_device_graphics.sh >/dev/null 2>&1 || true   # exits nonzero on other static MISMATCH (menu) — we only gate the halo here
R=.autoport/reports/graphics-verify/report.json
[ -f "$R" ] || fail "detector produced no report.json"
python3 - "$R" <<'PY' || exit 1
import json,sys
b={x['beat']:x for x in json.load(open(sys.argv[1])).get('beats',[])}
logo=b.get('intro-logo',{}) or {}; title=b.get('title-pressstart',{}) or {}
hl=logo.get('halo_excess_frac'); ht=title.get('halo_excess_frac')
bad=[]
if hl is None or hl>=0.01: bad.append(f"ND-logo halo still present (halo_excess_frac={hl}, must be <0.01)")
if ht is None or ht>=0.02: bad.append(f"title halo still present (halo_excess_frac={ht}, must be <0.02)")
if bad: print("[Ghalo FAIL] "+"; ".join(bad)); sys.exit(1)
print(f"halo gone — ND-logo={hl} title={ht}")
PY

# 4. no-crash regression (broadened sig set)
L=$(ls -t .autoport/reports/graphics-verify/routed-logcat.log 2>/dev/null | head -1)
if [ -n "$L" ]; then
  CR=$(grep -acE 'GK-DIAG sig=(4|6|11)|Fatal signal|signal (11|6|4) \(SIG' "$L" 2>/dev/null || true)
  [ "${CR:-0}" -eq 0 ] || fail "crash regression: $CR sig in run"
  FM=$(grep -aoE 'frame=[0-9]+' "$L" | grep -oE '[0-9]+' | sort -n | tail -1); FM=${FM:-0}
  [ "$FM" -ge 10500 ] || fail "did not reach frame 10500 (regressed gameplay reach: frame=$FM)"
fi
ok "halo gone, no crash, gameplay reach intact"

bash .autoport/restore_knowngood_device.sh >/dev/null 2>&1 || true
echo "[Ghalo PASS] ND-logo + title halo (village/sun leak) OBJECTIVELY gone vs the v0.3.3 original (intro-logo halo<0.01, title<0.02), no crash, reaches in-game. Known-good restored."
exit 0
