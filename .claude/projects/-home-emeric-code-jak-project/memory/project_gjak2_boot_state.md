---
name: project_gjak2_boot_state
description: JAK2 Android arm64 bring-up state after Gjak2-boot — builds+boots to gcommon-exec, ceiling = arm64 EE-base pointer bug
metadata:
  type: project
---

Gjak2-boot (2026-07-06) brought JAK2 up on Android arm64: BUILDS fully + BOOTS on
device eae4df44 into GOAL execution. Validator PASSES. HONEST PARTIAL — NOT
rendering yet.

**What landed (all committed [autoport/Gjak2-boot]):**
- x86 jak2 oracle was BROKEN at session start; fixed 2 translation-layer bugs:
  `game/kernel/common/kprint.cpp` (guard clear/reset/output_* on
  `OutputBufArea.offset`, not bare MasterDebug — jak2 leaves it null under
  `-debug-mem`), and `game/sce/sif_ee.cpp` (recognize jak2's single-backslash
  `cdrom0:\DRIVERS\OVERLORD.IRX;1` overlord path — else IOP never starts,
  `sif_busy` ASSERT on DGO RPC 0xfab3). Now 483 link finish + kernel: machine started.
- jak2 wired into `android/CMakeLists.txt` (kboot/kmachine/kmachine_extras +
  jak2 overlord 15 TUs + jak2_texture_remap + discord_jak2 + sqlite3 +
  font_utils/font_db/json_util). Runtime dispatch via `g_game_version` in
  `android_goal_main.cpp` + `android_runtime_full.cpp` (InitMachine/
  KernelCheckAndDispatch/overlord init_globals/start_overlord_wrapper branch jak2).
- arm64 CGOs: `.autoport/build_arm64_full_consistent_jak2.sh` — arm64 goalc builds
  ALL 2683 jak2 targets clean; stages `out/jak2-arm64-full/iso` (151); restores x86
  oracle. gradle jak2 flavor + `build_asset_bundle.sh jak2`.
- **arm64 klink retrofit** `game/kernel/jak2/klink.cpp`: jak2's 4 reloc fns did raw
  x86 int32 stores that STOMPED arm64 ADRP/ADD/LDR/STR words -> gcommon-link SIGILL.
  Mirrored jak1's `klink_arm64_patch_pc_rel` (common/klink.cpp) call-before-raw-store
  pattern (kNotInstr fallback keeps x86 identical). Fixed the on-device SIGILL.

**THE CEILING (next chapter):** device crashes SIGSEGV executing gcommon's linked
code: `LDR W9,[X16,#16]` with X16=0x7f54001afe — correct 0x7f EE-base high dword,
GARBAGE 0x54001afe low dword. = arm64 EE-base / gpr-upper-32 pointer-formation bug
class (jak1's A19-A42 double-EE-base / X16-scratch-clobber family, per
[[feedback_arm64_x86_model_reg_ids]] / [[feedback_arm64_asm_func_semantics]]), on a
NEW gcommon path. Use the A34 fp-walk+lr-window forensics ([[feedback_a34_crash_forensics_loop]])
to name the gcommon fn + fix the arm64 emitter/mips2c. Then jak2 renderer subset
(init_bucket_renderers_jak2 + VisDataHandler/BlitDisplays/Shadow2/Warp/
ProgressRenderer + a mips2c_table_jak2_arm64.cpp) for render.

**GOTCHAS (cost real time):**
- SHARED /pc/ files (pckernel-common.gc, pckernel-h.gc, pc-debug-common.gc) are
  compiled into jak2/jak3/jakx via `goal_src/jak2/lib/project-lib.gp` redirects.
  Autoport jak1 /pc/ edits that use jak1-only engine fields BREAK the jak2 GOAL
  build. Guard with compile-time `(#cond ((eq? GAME_VERSION 'jak1) ...) (#t ...))`.
  Fixed dynamic-render-scale (real-frame-counter, level-default) this way.
- jak2 VAGWAD.* voice banks = 7×493MB (~3.45GB); the single jak2_assets.zip blows
  AGP compressAssets' Integer.MAX_VALUE (~2GB) array cap. Drop non-ENG VAGWAD
  (build_asset_bundle.sh SKIP_ISO_RE) -> 1.55GB.
- NEVER run the x86 oracle while `build_arm64_full_consistent_jak2.sh` runs — both
  touch out/jak2/iso; a mid-build read loads arm64 KERNEL.CGO into x86 (0x21 corrupt-base).
- jak2 is a NEW MIUI install (org.opengoal.gk.jak2) -> USER_RESTRICTED; tap
  AdbInstallActivity (`input tap 540 2061` remember + `311 2186` install) once
  ([[feedback_miui_new_install_dialog_tap]]); then headless.
