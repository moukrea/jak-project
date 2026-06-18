# Phase Gspark-enterstate — fix the frame-180 `enter-state` null-enter SIGILL that blocks ALL current-source CGO ships

## Why this phase exists (it gates everything)
The device has been frozen on **2026-06-11 ("f1c") boot CGOs** because rebuilding the boot CGOs from CURRENT `goal_src` deterministically crashes ~3 s into boot ("title frame ~180", the Naughty Dog logo intro). Until this is fixed, **no GOAL-level change can ship to the device** — not the cutscene fix (next phase), not title fixes, nothing. f1c boots fine; current source does not. So a `goal_src` change since June 11 introduced this.

## The bug — already root-caused to the SYMPTOM (do NOT re-derive this)
- Crash = `sig=4` SIGILL: a `blr` to a null function pointer (target computes to `ee_base+0 = 0x7f00000000`).
- Byte-symbolized to **`enter-state` at `goal_src/jak1/kernel/gstate.gc:338-339`**: `(let ((enter-func (-> new-state enter))) (if enter-func (...call enter-func...)))`. `new-state = (-> pp state) = pp.next-state`. The state's **`enter` slot is a raw `0`** (a null GOAL offset, NOT `#f`). GOAL's `(if enter-func ...)` only treats `#f` (s7) as false, so a raw `0` passes the guard and gets BLR'd → SIGILL.
- Registers are IDENTICAL every run (deterministic): `x0=0 x3=0 x4=0x178bc4 x13=0x1e4294 x16=0x15738c`, `s7(#f)=0x14fd24`. Forensics saved: `.autoport/reports/Gspark-deploy/fresh-crash-logcat.txt` (sig=4 + full reg dump + fp-walk).
- `enter-state`'s own codegen is BYTE-IDENTICAL f1c-vs-current (it is the VICTIM). The `sig=11` in the log is a benign secondary fault inside the crash dumper (`gk_sigsegv_diag`) — ignore it.

## FOUR fixes already tried and FALSIFIED — do NOT repeat them
1. Fully-consistent fresh 28-file build → identical crash (it's a real regression, not packaging).
2. `gpr_addr` hardening of all 19 sparticle `#f`-guards → identical crash.
3. Un-noop'ing `sp-process-block-3d` in `mips2c_table_jak1_arm64.cpp` → identical crash.
4. Guarding the null call inside `enter-state` with `(nonzero? ...)` and with `(zero? (logand ... #xffffffff))` → STILL crashed and the diagnostic `format` never even fired. **Lesson: the function-pointer value in GOAL is held inconsistently on arm64 (host `ee_base+offset` vs raw 32-bit offset), so a GOAL-level null test of `enter-func` is unreliable.** The `A40-SPWIN` sparticle dump that pointed everyone at sparticle is a RED HERRING (A40 just watches that window).

## YOUR job — find WHY the `enter` slot is null, then fix the real cause
The slot is null because the **`go`/state for the ndi/logo intro produced a state whose `enter` was never set (0), OR `new-state` itself points at the wrong/zero object** on arm64 (x86/f1c set it correctly). This is almost certainly the recurring **arm64 GOAL-pointer / `go-hook` / state-construction codegen class** (cf. the F1f / G1 / G2 `enter-state` history; `go-hook` calls `enter-state` and sets `(-> proc next-state)`).
Concrete attack plan (pick the cheapest decisive one first):
- **Identify the exact state.** Instrument RELIABLY — NOT in GOAL (representation is ambiguous). Either: (a) add a C++ check at the mips2c/kernel call boundary that reads the raw 32-bit field, or (b) read `(-> new-state name)`/`type` via a robust low-32 mask and dump it, or (c) use the existing A38 infra. Name which `defstate` (in `title-obs.gc` ndi/logo path, or `static-screen.gc`) is being entered at frame ~180 with a 0 enter.
- **Oracle-diff** that state object's construction (the `defstate` define-state-hook output / the `go-hook`) x86 vs arm64 — is `enter` written correctly into the state object on x86 but 0 on arm64? Check `define-state-hook` / `set-and-go` / the state allocation.
- OR **git-bisect** `goal_src` between f1c (the set in `.autoport/backups/device-knowngood-cgos-20260618/`, build of 2026-06-11) and HEAD over the intro/state/go files to name the introducing commit.
- Then FIX at the real mechanism (likely a goalc/IGenARM64 codegen fix for state/function-pointer field stores, or a `go-hook`/`define-state-hook` arm64 issue). A GOAL-level null-guard in `enter-state` is a LAST-RESORT mask, not the fix — and it must be done in a representation-robust way if used.

## Device-safety — MANDATORY (the device is currently WORKING; keep it that way)
- After ANY failing on-device test, IMMEDIATELY run `bash .autoport/restore_knowngood_device.sh` (restores the verified-good f1c 28-file set to `files/iso_data/jak1/`). Never leave the phone crashing.
- Build a consistent current-source arm64 set with `bash .autoport/build_arm64_full_consistent.sh` (stages all 28 to `out/jak1-arm64-full/iso/`, restores the x86 oracle).
- Deploy CGO-only changes by `run-as cp` into `files/iso_data/jak1/` (push all 28 as a consistent set, sha256-verify). Do NOT wipe the `.extracted_v1` sentinel (that forces a 1.4 GB re-extraction). libgk.so changes DO need an APK reinstall (`pm install -r -d -t -i com.android.vending`, with `appops set com.android.shell REQUEST_INSTALL_PACKAGES allow` for MIUI).
- Device serial `eae4df44`, pkg `org.opengoal.gk.jak1`. Verify `mCurrentFocus=...jak1` before trusting any frame (shared device). Use `grep -a` on routed logcat.

## Done = (validator is ground truth)
A FRESH, fully-consistent CURRENT-source 28-file CGO set, deployed to the device, **boots past frame 180 to the title screen** — app FOREGROUND at end-of-run (`mCurrentFocus` = jak1), **frame reached >= 600**, **zero `GK-DIAG sig=4`** in the run — AND the fix is a real code change (not a stub, not a mask claimed as a root fix). The validator force-restores the known-good set afterward so the device is always left usable. Owner eye-confirms the title still renders.
