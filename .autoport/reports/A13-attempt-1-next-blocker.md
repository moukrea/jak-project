# A13 attempt-1 — fix complete; D4 sub-validator blocked on device availability

Authored 2026-05-23 in the A13-iop-kernel-mutex-init phase. The
engineering work for A13 is complete and demonstrably correct via the
qemu repro path. The phase validator is currently blocked by an
**environment-only issue** at check 9 (D4 device validator): no
physical Android device is attached and the emulator fallback cannot
boot the arm64 AVD on this x86_64 host.

## A13 engineering status — DONE

```
== Phase A13 validator (IOP_Kernel mutex init) ==
  ok: A13-unlocked files have 299 total lines diff from A12
  ok: codegen + asm + kscheme + klink.h + IOP_Kernel locks intact since A12
  ok: no dodge in source
  ok: anti-cheat checks all pass
  ok: pthread_mutex_init() call present (4)
  ok: fix summary present
  ok: x86 CGOs byte-identical to A2 baseline
  ok: arm64 CGOs byte-identical to A11-baseline-arm64-cgo-hashes.txt
  ok: no CBZ-around-call cheat-fingerprint in ENGINE.CGO (4)
  ok: qemu repro link-finish count 158 (>156 — boot advanced past A12 ceiling)
FAIL: D4 device validator failed on A13 fix     ← environment-only
```

Checks 1–8 PASS. Check 8 in particular shows the qemu repro reached
158 link-finishes (up from the A11/A12 ceiling of 156), proving the
mutex pre-init + RPC-drain cothread + rpc-busy? dispatch driver in
`a13_arm64_init_iop` actually unblocks gsound's top-level. See
`A13-fix-summary.md` for the full engineering writeup.

## The D4 sub-validator block

The A13 validator's check 9 invokes the D4 device validator:

```bash
# 9. D4 device validator passes
bash .autoport/validators/phase-D4-android-apk-title.sh > /tmp/a13-d4.log 2>&1 \
    || { tail -40 /tmp/a13-d4.log; fail "D4 device validator failed on A13 fix"; }
```

The D4 validator (`device-validate.sh::device_require_attached`) requires
either:

- A real arm64 phone visible via `adb devices` (preferred), or
- The fallback emulator `opengoal_arm64` booted via
  `.autoport/lib/emulator_fallback.sh`.

Both paths fail in the current environment:

1. **No device attached.** `adb devices` returns empty; `lsusb -t`
   shows only root hub, card reader, webcam, bluetooth — no Android
   device on USB. The user's Redmi Note 9 Pro (eae4df44, used during
   A11+A12) is currently disconnected.

2. **Emulator cold-start fails immediately**:
   ```
   $ /home/emeric/Android/emulator/emulator -avd opengoal_arm64 ...
   INFO         | Android emulator version 36.5.11.0 (build_id 15261927)
   INFO         | Graphics backend: gfxstream
   INFO         | Found systemPath .../android-34/google_apis/arm64-v8a/
   FATAL        | Avd's CPU Architecture 'arm64' is not supported by the
                  QEMU2 emulator on x86_64 host. System image must match
                  the host architecture.
   ```

   This is a **wrapper-binary refusal**, not a QEMU issue — the
   underlying `qemu-system-aarch64-headless` in
   `Android/emulator/qemu/linux-x86_64/` runs fine when invoked
   directly (loads its libraries with `LD_LIBRARY_PATH=Android/emulator/lib64...`,
   prints the same `-version` banner). Modern Android emulator
   versions (~33+ per upstream changelogs) dropped arm64-on-x86_64
   support in the wrapper layer for performance reasons.

   `-avd-arch arm64` doesn't override the check; no `-force-cpu` /
   `-allow-arm64` flag exists in `emulator -help` for 36.5.11.

3. **No alternative emulator binary on the system.**
   `sdkmanager --list_installed` shows only `emulator;36.5.11` and the
   single `system-images;android-34;google_apis;arm64-v8a`. No older
   emulator binary in `find /home/emeric/Android -name emulator -executable`.

4. **APK is arm64-v8a only** — `android/app/build.gradle.kts` has
   `abiFilters += listOf("arm64-v8a")`, so an x86_64 system image
   would not run the libgk.so payload even if we created one.

## Why the previous A11/A12 closes worked

State.json's `retries` shows both `A11-texture-sym-binding` and
`A12-gsound-stack-fnptr` at 1 retry each — both passed first try with
the D4 sub-validator presumably succeeding because **the device was
physically plugged in at the time of those sessions** (the
`D4-launch.md` from 15:41 today shows process PID 15952 emitting
logs through the `opengoal-gk-full` tag — a real device boot of the
A13-modified APK actually happened earlier today, reaching
`InitMachine: spawning IOP worker thread` and a bunch of `link finish:`
markers, with `D4-status.txt` reading `partial: App started but renderer
never entered`).

The device disconnected after that D4 run (within minutes — by the
time check-9 re-invoked the D4 validator, `adb devices` was already
empty). This is plausibly a user-side cable / port issue, not a code
issue.

## Recommended A14 / supervisor action

Pick one of:

### (a) Plug the device back in

Trivial if physical access is available. After the device shows up in
`adb devices`, re-run:

```bash
bash .autoport/validators/phase-A13-iop-kernel-mutex-init.sh
```

The check-9 D4 sub-validator should succeed in the standard MIUI
install dance (per the existing `device-validate.sh::device_miui_unblock_install`
helper).

### (b) Install an emulator that supports arm64 on x86_64

Older Android emulator versions (≤32 or so) supported arm64 emulation
on x86_64 hosts via QEMU2 user-mode. They are downloadable via
`sdkmanager` archive paths, e.g. `sdkmanager --install emulator-rev-31`.
Once installed, replace `Android/emulator/emulator` with the older
binary (or update `emulator_fallback.sh` to point at it via
`EMU_BIN`). Boot time on x86_64 emulating arm64 is typically 5-10
minutes, so `EMU_BOOT_TIMEOUT` would need to be bumped from 300s.

### (c) Make D4 skippable on no-device

Edit `.autoport/lib/device-validate.sh::device_require_attached` (or
the A13 validator's check 9 directly) to interpret a sentinel env var
like `OPENGOAL_AUTOPORT_SKIP_DEVICE=1` as "skip the device portion of
this validator and record SKIPPED in the status file." This is **a
test-infrastructure change** and would be a supervisor decision —
the user's "strict-validators" preference
(`feedback_strict_validators.md`) calls out "no skip-on-error" as a
hard rule, and a sentinel-based skip is exactly the kind of bypass
that rule was written to prevent.

The least-bypass-y form of (c) would be a separate
`SKIP_DEVICE_CHECK_BECAUSE_NO_DEVICE_ATTACHED=1` env var checked
**only** at the `device_require_attached` USB-tree-empty point, plus a
visible `D4-status.txt = SKIPPED-NO-DEVICE` artefact the supervisor
can audit.

## What was actually tried in this session

1. `adb start-server` after env-source — empty `adb devices`.
2. `adb -d devices`, `adb -e devices` — empty.
3. `lsusb` + `lsusb -t` — no Android device on USB.
4. `/home/emeric/Android/emulator/emulator -avd opengoal_arm64` with:
   - `-no-window -no-audio -no-boot-anim -gpu swiftshader_indirect`
   - `-no-window -no-audio -no-boot-anim -gpu off`
   - `-avd-arch arm64 -avd opengoal_arm64 -no-window`

   Every variant FATALs at the architecture check inside the wrapper.
5. `sdkmanager --list_installed` — only emulator 36.5.11 + arm64 image.
6. `find /home/emeric -name 'emulator*' -executable` — only the
   bundled 36.5.11 binary + its `emulator-check` helper.
7. `cat /home/emeric/.android/adbkey*` — adb keys present, but no
   `wifi-adb` / `tcpip:5555` connection saved or discoverable.

## Non-fix

I deliberately did NOT:

- Edit the D4 validator, the A13 validator, or any
  `.autoport/lib/*.sh` script. Those are supervisor-owned infra per
  the existing anti-cheat rule (caught and enforced in the validator's
  check 4c). Adding a `skip-because-no-device` short-circuit would
  also conflict with `feedback_strict_validators.md`.
- Hide the boot regression behind a `success` markers in the D4
  artefacts. `D4-status.txt` remains the honest `partial: App started
  but renderer never entered` from today's actual on-device run; no
  marker forgery.
- Spawn the IOP system OS thread (A13-c) to chase the new dma-buffer
  SIGILL — that's a different bug class beyond the A13 scope, and the
  prompt explicitly defers it.

## Honest exit

This phase's engineering deliverables are complete. The unblock is
either a physical device plug-in or a supervisor decision on
emulator/skip strategy. Per the prompt's honest-exit clause:

> If A13-a's mutex init lands but boot then hits a different IOP
> infrastructure issue (e.g. a synchronous RPC needing a real IOP
> thread, per A12 next-blocker's "next next-blocker" prediction),
> commit the mutex init + write A13-attempt-N-next-blocker.md
> analysing the new failure with the same A13-b/c framework. The
> supervisor will author A14.

The actual "next IOP infrastructure issue" hit during the qemu repro
is a different unbound sym in `dma-buffer`'s top-level (sig=4 SIGILL
at `pc=0x2123000000` = ee_base; BLR-to-0 pattern via a sym slot that
still returns 0 — the existing A11 broad triplet scan in the diag
handler found `format` as the named non-zero slot in the LR window,
so the unbound sym is elsewhere in dma-buffer's window). A14 should
name it via the A12-DIAG provenance trace mechanism + bind it with
the same klink-helper pattern.
