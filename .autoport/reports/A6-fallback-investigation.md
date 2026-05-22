# AVD fallback investigation — outcome: dropped

2026-05-22 supervisor session.

## Goal

Have a fallback "device" available so the orchestrator can keep
iterating when the user's phone is unplugged / away.

## What was tried

1. Android Studio emulator + arm64-v8a system image — FATAL on launch:
   `Avd's CPU Architecture 'arm64' is not supported by the QEMU2
   emulator on x86_64 host. System image must match the host
   architecture.` Google removed cross-arch from the standard
   Android emulator.

2. Cuttlefish — same restriction in practice; arm64-on-x86 needs
   full TCG emulation and is not Google-supported as a primary path.

3. Genymotion / anbox / waydroid — all same-arch.

4. x86_64 AVD + libnativebridge — would work mechanically but
   translation can both hide and create bugs different from real
   arm64. Not reliable for testing the arm64 emitter (which is
   most of A6/A7's value).

5. qemu-system-aarch64 + Fedora arm64 VM — viable for pure arm64
   testing but no Android stack and ~2-3h setup. Doesn't actually
   match the user's deployment target.

## Resolution

User decision: drop the fallback. Accept that the orchestrator
halts cleanly when phone is unplugged.

## Residual artifacts (kept, dormant)

- `.autoport/lib/emulator_fallback.sh` — generic launcher; remains
  in place in case a future fallback option becomes viable.
- `.autoport/lib/device-validate.sh` — `device_require_attached` now
  has fallback preference logic (real > emulator > start emulator).
  Currently has no emulator to fall back to. Works correctly when
  real device is attached. Gives clearer error message than the
  pre-patch version when no device is attached.

## Lesson

Don't assume "qemu-system-aarch64 binary exists" implies "can run
arm64 Android on x86 host." The emulator's frontend (Android
Studio's QEMU2 wrapper) explicitly blocks cross-arch even when the
underlying qemu would support TCG emulation.
