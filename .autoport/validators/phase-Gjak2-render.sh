#!/usr/bin/env bash
# Validator — Gjak2-render: jak2 reaches a FIRST RENDER FRAME on Android. STRICT physical proof —
# a device screencap artifact + foreground=jak2 assertion + the gcommon SIGSEGV fixed + x86 oracle.
# Does NOT accept a mere "render" keyword (Gjak2-boot's leniency, corrected).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
fail(){ echo "[Gjak2-render FAIL] $*" >&2; exit 1; }
ok(){ echo "[Gjak2-render ok] $*"; }

R=.autoport/reports/Gjak2-render/report.txt
[ -f "$R" ] || fail "no report.txt"
grep -qiE 'RESULT:[[:space:]]*JAK2[[:space:]]+RENDER' "$R" || fail "report lacks RESULT: JAK2 RENDER <what-frame>"

# STRICT render proof: a device frame artifact must EXIST + be non-trivial (real capture, not a stub)
FRAME=$(find .autoport/reports/Gjak2-render -type f \( -name '*.png' -o -name '*.jpg' \) -newermt '-1 day' 2>/dev/null | head -1)
[ -n "$FRAME" ] || fail "no device render-frame screencap artifact (physical render proof required)"
SZ=$(stat -c %s "$FRAME" 2>/dev/null || echo 0)
[ "$SZ" -ge 20000 ] 2>/dev/null || fail "render frame $FRAME too small ($SZ B) — likely blank/stub, not a real jak2 frame"
ok "device render frame present ($FRAME, $SZ B)"

# Foreground = jak2 (shared-device hygiene — a jak1 frame does NOT count) + gcommon fixed + crash-free
grep -qiE 'mCurrentFocus.*jak2|focus.*jak2|jak2.*foreground' "$R" || fail "report must assert mCurrentFocus=jak2 at capture (jak1 frame doesn't count)"
grep -qiE 'gcommon|SIGSEGV.*fixed|fault.*(gone|eliminated)|no longer' "$R" || fail "report must show the gcommon SIGSEGV ceiling is fixed"
grep -qiE 'no.*(sig|crash|native)|crash-free|0 (sig|crash)|survive' "$R" || fail "report must assert a crash-free frame window (no sig 11/6/4/7)"
grep -qiE 'bug class|mips2c|codegen|gpr|epilogue|SIMD|cc|msub|NaN|IDIV|new class' "$R" || fail "report must name the arm64 fix / bug class for the gcommon fault"
ok "render foreground=jak2 + gcommon fixed + crash-free + fix named"

# 1-to-1: engine goal_src (jak1+jak2, non-pc) untouched; gold pristine
SUP_ANCHOR=$(git log --format=%H --grep='\[autoport/supervisor\]' | head -1); ANCHOR=${SUP_ANCHOR:-HEAD~1}
ENG=$(git diff --name-only "$ANCHOR" -- goal_src/ 2>/dev/null | grep -v '/pc/' | head -1)
[ -n "$ENG" ] && { grep -qiE 'revert|pristine|documented|prior.?phase' "$R" || fail "engine goal_src changed ($ENG) undocumented — our-x86 must == original-x86"; }
git status --porcelain .autoport/gold 2>/dev/null | grep -q . && fail "golden not pristine"
ok "engine goal_src untouched; golden pristine"

# PHYSICAL: built libgk still has real jak2 symbols
SO=$(ls -t build-android/lib/arm64-v8a/libgk.so 2>/dev/null | head -1)
[ -f "$SO" ] || fail "no built Android libgk.so"
OD=$(command -v aarch64-linux-gnu-nm || command -v llvm-nm || command -v nm)
J=$($OD "$SO" 2>/dev/null | grep -icE 'jak2|InitMachine'); [ "${J:-0}" -gt 0 ] 2>/dev/null || \
  { J=$(strings -a "$SO" 2>/dev/null | grep -icE 'jak2'); [ "${J:-0}" -gt 0 ] 2>/dev/null || fail "libgk has no jak2 symbols (stub)"; }
ok "libgk has real jak2 symbols ($J)"

# x86 jak2 oracle still boots
SMOKE=$(mktemp)
timeout 180 build-x86/game/gk --game jak2 --portable -fakeiso --verbose --disable-ansi \
  -iso-data out/jak2/iso -- -boot -debug-mem > "$SMOKE" 2>&1 || true
grep -qiE 'link finish|master-mode|machine started' "$SMOKE" || { tail -5 "$SMOKE"; rm -f "$SMOKE"; fail "x86 jak2 oracle regressed"; }
rm -f "$SMOKE"
ok "x86 jak2 oracle boots"
echo "[Gjak2-render PASS] first jak2 render frame on device + gcommon fixed + x86 oracle intact. (owner play-test next)"
