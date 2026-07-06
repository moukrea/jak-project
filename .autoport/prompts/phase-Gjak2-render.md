## WORK ECONOMY (manager/worker delegation)
You are the MANAGER (claude-opus-4-8[1m], effort=xhigh): plan, decide, judge, VERIFY subagent claims
yourself. Delegate to autoport-researcher (read-only scans/oracle/forensics), autoport-implementer
(mechanical edits to your exact spec), autoport-tester (builds/device runs/screencaps). Parallelize.

# Phase Gjak2-render — get JAK 2 to its FIRST rendered frame on Android arm64

## Where we are (Gjak2-boot done — infra only)
jak2 now BUILDS for Android arm64 and BOOTS through game-select -> jak2::InitMachine -> IOP/overlord
init (libgk carries 498 real jak2 symbols). CEILING: it **SIGSEGVs in gcommon's linked GOAL code on a
jak2-specific NEW arm64 codegen path** BEFORE any render — no jak2 frame is drawn yet (device falls
back to jak1). This phase breaks that ceiling and reaches the FIRST jak2 render frame, mirroring jak1's
A1..A42 kernel-boot -> first-render arc — but with the whole jak1 bug-class catalog + Android-adaptation
knowledge as a HEAD START (do not rediscover).

## Mandate — two blockers, in order
1. **Fix the gcommon SIGSEGV** (the immediate boot ceiling). It is a NEW jak2 codegen path jak1 never
   hit. Use the jak1 forensics loop (fp-walk + 24-word lr windows + byte matcher, [[A34 crash forensics
   loop]]) to NAME the faulting instruction + function, then map it to a KNOWN bug class first
   (mips2c gpr-s7/x14 double-EE-base, FFI SIMD bank, 128-bit cc, LDP/RET epilogue, modulo msub, NaN
   compare, asm-func stack-RA, mips2c #f-guard 32-bit gpr, IDIV X8/R8 hazard, …). Fix in the
   TRANSLATION LAYER ONLY (arm64 codegen / mips2c / runtime glue). If it is genuinely new, catalog it
   as a new class. NEVER touch engine goal_src — our-x86 jak2 MUST == original-x86 jak2.
2. **Reach a first jak2 render frame.** Past gcommon, wire whatever the jak2 render path needs that
   jak1's curated Android subset doesn't cover: jak2 renderer-subset TUs (game/CMakeLists.txt), bucket
   registrations, GLES primitive-restart / format gates, jak2 mips2c allowlist entries for the DMA/
   sparticle builders (un-noop the jak2 ones or the chain is empty). First frame can be the jak2 boot/
   title/first-loaded-level — a real jak2 image on screen, not a cleared buffer, not jak1.

## Verify (device eae4df44) — STRICT, physical render proof (no keyword-matching)
- Device boots jak2 to a RENDER FRAME: capture a screencap that shows actual jak2 content; assert
  mCurrentFocus = the jak2 package/activity at capture time (shared-device hygiene — a jak1 or other
  frame does NOT count); the app pid survives with NO native sig 11/6/4/7 across a sustained window
  (>= ~30 s / hundreds of frames past the old gcommon ceiling).
- The gcommon SIGSEGV is GONE (fault site no longer reached; name the fix + bug class).
- x86 jak2 oracle still boots to its milestone (no engine goal_src diff; our-x86 == original-x86).
- Full CONSISTENT arm64 build; deploy_verify PASS (build==APK==device libgk) for the jak2 build.

## Report (`.autoport/reports/Gjak2-render/report.txt`) `RESULT: JAK2 RENDER <what-frame>`
the gcommon fix (file:line + bug class), the renderer-subset/mips2c-allowlist wiring, the device
render evidence (screencap path + mCurrentFocus=jak2 + crash-free frame window), x86 jak2 oracle intact.
If render is only partial (some buckets), say so honestly and label what's deferred.

## Locks: ANDROID_SERIAL=eae4df44 only; arm64 codegen only (no x86 goalc/emitter/IGenX86_64 semantic
change); engine goal_src (jak1+jak2, non-pc) UNTOUCHED; .autoport/gold READ-ONLY; full CONSISTENT
builds only; grep -a on routed logcat; verify mCurrentFocus=jak2 before trusting ANY frame.
## Max: max_turns 3000, max_retries 6. device: true, owner_verify: true.
