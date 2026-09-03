#!/usr/bin/env bash
# keira_a3_redeliver.sh — attempt-3 CLOSE-GATE fix for Grecharged-secondary-motion.
#
# WHY THIS EXISTS (diagnosed 2026-08-11 13:0x, all numbers measured, none assumed):
#
# The phase validator exits 0. What failed is the close gate:
#   DEPLOY-VERIFY FAIL: custom pack STALE on device:
#     stamp 'c442c1ec37f96' != built version 'c211dc0833ced'
#
# Root cause, in order of causation:
#   1. The arm64 GOAL set on the phone was staged at 12:43:28. Commit f7a027b839
#      (13:00:48) then changed the PHYSICS ENGINE ITSELF —
#      goal_src/jak1/pc/jak-hd-physics.gc (+45 lines) and phys-room.gc (+17). Measured:
#      both files are mtime 12:55, i.e. NEWER than out/jak1-arm64-full/iso/GAME.CGO.
#      So the phone runs an OLDER engine than HEAD. deploy_verify cannot see this (it
#      checks the libgk sha chain and the pack stamps, not GOAL freshness) — the
#      custom-pack stamp is what tripped, but the CGO staleness is the deeper half.
#   2. The custom pack was rebuilt at 12:45:41 and the APK reassembled at 12:46:26,
#      AFTER the 12:41 install. Nothing installed that APK, so the device stamp stayed
#      on the pack it had actually unpacked. The gate is right and the build is stale.
#   3. That 12:45 pack is not merely older, it is CORRUPT. Measured member-by-member
#      against disk: 66 members byte-identical, exactly ONE mismatch —
#      recharged_assets/physics_chains.txt, zip=15437 bytes vs src=15410. The diff is
#      one line:
#        zip: chain goggles ... radii=196,150,150,150,150,150,150,150,79
#        src: chain goggles ... radii=196,150
#      The goggles chain has TWO joints (gogglesBase r=196, gogglesMid r=79 — the
#      generator's own comment line above it). The 9-entry list is the residue of the
#      non-idempotent apply_owner_tuning.py, which appended ",150" (4 bytes) on every
#      packaging run: 196,150,150,150,79 at 93bb21e4cb -> 196,150,150,150,150,150,79 at
#      1bb28bc0f2 -> fixed to 196,150 at f7a027b839. That is the "donnee qui grossit a
#      chaque empaquetage". The SCRIPT is fixed (verified here: 3 consecutive runs leave
#      the file byte-identical, md5 02690bf81bfa), but the CORRUPTED PACK was never
#      rebuilt, so the phone still eats the corrupt radii.
#
# So this is not a re-run of a flaky gate: shipping the existing APK would hand the
# owner a pack whose goggles radii disagree with HEAD, which is precisely the
# "paire depareillee" the contract forbids and precisely the process incident that
# already made him test an APK without his own corrections.
#
# BUILD TIER (owner standing order: cheapest path that PROVES the change):
#   * libgk.so:      NO REBUILD. Measured: zero C++/shader files newer than the
#                    11:19 libgk.so. An NDK rebuild here would be pure waste.
#   * arm64 GOAL:    REBUILD (tier "GOAL only"). This is the one thing that is
#                    genuinely stale, and it is the physics engine itself.
#   * packs + APK:   rebuild + gradle repack + install. Unavoidable: the data changed.
#
# Never `rm -rf` on code, never kill by pattern. Every step hard-fails with what to re-run.
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"

ADB="${ADB:-$HOME/Android/platform-tools/adb}"
S="${S:-eae4df44}"
GAME=jak1
OUT=.autoport/reports/Grecharged-secondary-motion
mkdir -p "$OUT"
LOG="$OUT/a3_redeliver.log"; : > "$LOG"
say(){ echo "[a3] $*" | tee -a "$LOG"; }
die(){ echo "[a3 FAIL] $*" | tee -a "$LOG"; exit 1; }

CUS_MAN="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.manifest.properties"
APK_PATH="android/app/build/outputs/apk/${GAME}/debug/app-${GAME}-debug.apk"

# --- PREFLIGHT: NOBODY ELSE MAY BE BUILDING -------------------------------------
# Attempt 3, first run, died here and it is worth naming precisely. `.autoport/
# auto_build_apk.sh` is the supervisor's continuous-APK watcher: it rebuilds a
# consistent arm64 set + APK whenever a watched source changes, so the owner always has
# something to test. It fired at 13:14:29 ("sources changées → build arm64 cohérent")
# straight into out/jak1/iso WHILE this script's own build_arm64_full_consistent.sh was
# using the same tree. Two `(make-group "iso" :force #t)` passes on one output dir is the
# concurrent-build race, and the result was caught downstream by build_cgo_pack.sh:
#   [cgo-pack] FATAL: staged KERNEL.CGO == x86 oracle (would SIGILL on the arm64 device)
# i.e. the "arm64" set that got staged held x86 bytes. That guard did its job — it refused
# to ship a set that would SIGILL on the phone — but the cycle was already lost.
#
# The watcher itself is not at fault: its own interlock skips while cmake/ninja/cc1plus/
# java/goalc/gk run, and none of those run during an `adb install` + LoaderActivity boot,
# which is precisely the window this script sits in for several minutes. So the interlock
# has to exist on THIS side too. Match on the process NAME (ps -eo comm), never on a
# pattern over the full args: an args grep matches this very script and would self-block.
preflight_exclusive(){
  local busy
  busy=$(ps -eo comm --no-headers | awk '$1=="goalc"||$1=="cmake"||$1=="ninja"||$1=="cc1plus"{print $1}' | sort -u | tr '\n' ' ')
  [ -z "$busy" ] || die "another build is running ($busy) — refusing to start a second one on the same output tree. That race is what corrupted the staged arm64 set at 13:14 (staged KERNEL.CGO came out x86). Wait for it, or stop it by EXACT PID (never by pattern), then re-run."
  # The watcher must be stopped for the whole cycle, install+boot included.
  local w
  w=$(pgrep -f '[a]uto_build_apk\.sh' | tr '\n' ' ')
  [ -z "$w" ] || die "auto_build_apk.sh is alive (PID(s): $w). It will fire mid-install and rebuild GAME.CGO under us. Stop it by EXACT PID, run this script, then restart it."
  say "preflight OK: no compiler running, no APK watcher armed"
}
preflight_exclusive

# The other half of the interlock. preflight_exclusive only stops US from starting on top of
# THEM; nothing stopped THEM from starting on top of US, and "us" includes several minutes of
# `adb install` + LoaderActivity boot during which no compiler is running and the watcher's own
# check therefore sees an idle machine. This file is what auto_build_apk.sh now honours (with a
# 60-min staleness bound, so a dead worker cannot wedge the owner's APK publishing for ever).
# trap on EXIT: the lock must not survive a die(), a Ctrl-C or a crash.
LOCK=.autoport/.deploy-in-progress
printf 'keira_a3_redeliver.sh pid=%s started=%s\n' "$$" "$(date -Is)" > "$LOCK"
trap 'rm -f "$LOCK"' EXIT
say "deploy lock posed ($LOCK) — the APK watcher will stand off for this whole cycle"

say "=== STEP 0 — record the stale state we are correcting (evidence, not assumption) ==="
say "pre: custom manifest version = $(grep -E '^version=' "$CUS_MAN" | cut -d= -f2)"
say "pre: device custom stamp     = $($ADB -s "$S" exec-out run-as org.opengoal.gk.${GAME} \
      cat files/.custom_pack_stamp_${GAME} 2>/dev/null | tr -d '\r\n')"
say "pre: packed physics_chains   = $(unzip -p android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.zip \
      recharged_assets/physics_chains.txt 2>/dev/null | wc -c) bytes"
say "pre: tree   physics_chains   = $(wc -c < recharged_assets/physics_chains.txt) bytes"

# ---------------------------------------------------------------------------------
say "=== STEP 1 — consistent arm64 GOAL set from CURRENT goal_src (engine is stale) ==="
# Two full passes (arm64 build + x86 oracle restore). Several minutes. This is the
# step that puts f7a027b839's engine changes onto the phone at all.
bash .autoport/build_arm64_full_consistent.sh 2>&1 | tee -a "$LOG" | tail -6
grep -q "DONE — consistent arm64 set ready" "$LOG" \
  || die "arm64 consistent build did not finish (see $LOG)"

# The engine files must now be OLDER than the staged CGO, or the set is still stale.
for f in goal_src/jak1/pc/jak-hd-physics.gc goal_src/jak1/pc/phys-room.gc; do
  if [ "$f" -nt "out/${GAME}-arm64-full/iso/GAME.CGO" ]; then
    die "STILL STALE: $f is newer than the staged GAME.CGO — the arm64 build did not pick it up"
  fi
done
say "arm64 set staged and NEWER than both engine sources (staleness closed)"

# ---------------------------------------------------------------------------------
say "=== STEP 2 — repack CGO + custom packs from that set ==="
# PIPESTATUS[0], not $?: `cmd | tee | tail` reports TAIL's status, so a hard-failing pack
# builder exits 0 here and the run sails on. That is not hypothetical — on the first a3 run
# `[cgo-pack] FATAL: staged KERNEL.CGO == x86 oracle` fired HERE, at step 2, was swallowed,
# and the script went on to spend two more minutes building a 431 MB custom pack before
# gradle re-ran the same task and failed for real. The fatal was in the log the whole time,
# two hundred lines above the error that got reported. Fail where the failure happens.
bash android/build_cgo_pack.sh "$GAME"    2>&1 | tee -a "$LOG" | tail -3
[ "${PIPESTATUS[0]}" -eq 0 ] || die "build_cgo_pack.sh FAILED (see $LOG) — refusing to build an APK around a bad CGO set"
bash android/build_custom_pack.sh "$GAME" 2>&1 | tee -a "$LOG" | tail -4
[ "${PIPESTATUS[0]}" -eq 0 ] || die "build_custom_pack.sh FAILED (see $LOG)"

# The pack must now carry HEAD's chains file byte-for-byte. This is the check whose
# ABSENCE let the corrupt goggles radii ride into two APKs: the pack builder's
# data-freshness guard byte-compares fr3/ members only, never recharged_assets/.
PZ="android/app/src/${GAME}/assets-slim/bundle/${GAME}_custom.zip"
ZM=$(unzip -p "$PZ" recharged_assets/physics_chains.txt | md5sum | cut -d' ' -f1)
SM=$(md5sum recharged_assets/physics_chains.txt | cut -d' ' -f1)
[ "$ZM" = "$SM" ] || die "pack physics_chains.txt md5 $ZM != tree $SM — the pack is STILL not HEAD's data"
say "pack physics_chains.txt == tree ($SM, $(wc -c < recharged_assets/physics_chains.txt) bytes)"
unzip -p "$PZ" recharged_assets/physics_chains.txt | grep -q 'radii=196,150$' \
  || die "packed goggles line does not carry the corrected 2-entry radii"
say "packed goggles radii corrected: $(unzip -p "$PZ" recharged_assets/physics_chains.txt | grep -o 'radii=196,150$')"

NEWVER=$(grep -E '^version=' "$CUS_MAN" | cut -d= -f2)
say "new custom pack version = $NEWVER"

# ---------------------------------------------------------------------------------
say "=== STEP 3 — reassemble the APK ==="
# zipflinger updates an existing archive IN PLACE and leaves the superseded bytes as
# dead space (measured once at 426 MB of gaps in a 1.0 GB APK). Delete first.
rm -f "$APK_PATH"
( cd android && ./gradlew assembleJak1Debug -q ) > "$OUT/a3_gradle.log" 2>&1 \
  || { tail -30 "$OUT/a3_gradle.log"; die "gradle assemble failed (see $OUT/a3_gradle.log)"; }
[ -f "$APK_PATH" ] || die "no APK produced at $APK_PATH"
say "APK: $(stat -c%s "$APK_PATH") bytes, $(date -d @$(stat -c%Y "$APK_PATH") +%H:%M:%S)"

# The APK must embed the pack we just built — not a cached one. Check the bytes, not the mtime.
AV=$(unzip -p "$APK_PATH" "assets/bundle/${GAME}_custom.manifest.properties" | grep -E '^version=' | cut -d= -f2)
[ "$AV" = "$NEWVER" ] || die "APK embeds custom pack '$AV' but the build produced '$NEWVER' — gradle used a cached asset"
say "APK embeds custom pack version $AV (== built)"

# ---------------------------------------------------------------------------------
say "=== STEP 4 — install + LoaderActivity extraction + deploy_verify ==="
# physics_deploy_fresh.sh installs, boots through LoaderActivity (MainActivity bypasses
# pack extraction), byte-proves GAME.CGO + physics_chains.txt landed, refreshes the
# EXTERNAL override (which wins over the APK copy, so a stale one would silently beat a
# fresh install), then runs deploy_verify.
bash .autoport/physics_deploy_fresh.sh 2>&1 | tee -a "$LOG" | tail -20
grep -q "\[deploy PASS\]" "$OUT/deploy_fresh.log" || die "physics_deploy_fresh.sh did not reach [deploy PASS]"

# ---------------------------------------------------------------------------------
say "=== STEP 5 — re-run the close gate's own instrument, unmodified ==="
bash .autoport/lib/deploy_verify.sh "$S" "$GAME" 2>&1 | tee -a "$LOG" | tail -8
say "=== a3 redeliver COMPLETE ==="
