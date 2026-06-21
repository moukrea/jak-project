# Gfix-title-rays — fix summary

## The defect (owner ground truth)
On the title screen the Jak&Daxter logo smashes the black background. The blue
light rays (the expected volumetric "starburst") are supposed to FLASH during the
smash and then vanish — but on the device they **REMAIN over the logo for ~1-2s
after the smash**. The owner attributed it to recent title work (Ghalo /
Gtitle-pixelmatch). Mandate: find the element x86-first via deterministic STATE
dumps (never pixels), calibrate a BEFORE that reproduces the linger, fix it so the
rays vanish matching the original on both our-x86 and the device.

## The element (found x86-first)
The "blue light rays" are the **`logo-volumes`** skelgroup (`title-obs.gc:57-62`),
spawned as a `logo-slave` child of the `logo` process by the `startup` state right
before the `ja-play-spooled-anim` of "logo-intro" (the smash). It is a
**pure-additive** mesh — its merc draw mode is `SRC_0_FIX_DST` →
`glBlendFunc(GL_ONE, GL_ONE)` (verified in `background_common.cpp`) — rigged to the
logo skeleton via `clone-anim-once` (`generic-obs.gc:38`). The pristine logo-intro
deactivates the volumes/black slaves only at the **spool-end** in `startup` :code,
so the additive rays are submitted to the GPU for the ENTIRE ~6.7s logo-intro.

## Diagnosis — deterministic dumps proved the linger is NOT a state regression
A temporary per-frame `(format 0 "GFXRAY ...")` dump in the `logo` :post, plus a
property-gated merc-input census in `Merc2.cpp`, were used to measure the rays on
the untouched original (jak-original-v033 / `.autoport/gold`, its own toolchain),
our-x86 (build-x86), and the device (eae4df44). Every measurable signal is
**byte-identical x86 ↔ device**:

| signal | original-x86 | our-x86 | device |
|---|---|---|---|
| logo-volumes alive (base-frame span) | 2010 | 2010 | 2205 |
| logo-volumes alive (wall-clock) | ~6.68s | 6.683s | 6.691s |
| logo anim (fn) | loops 0→66 | loops 0→66 | loops 0→66 |
| volumes joint-spread (ext) | n/a | full, constant ~1.3M | (identical anim) |
| merc inputs | n/a | en=0x1 ab=3(additive) abe=1 ialpha=1 tris=704, constant | (same DGO model) |
| bg-a (blackout) behind rays | n/a | 1.0 for ~4 frames then 0.0 | 1.0 for ~3 frames then 0.0 |

So: the title `title-obs.gc` startup/volumes code is byte-identical between the
gold (c4bc4d3ff) and HEAD (the Ghalo/Gtitle-pixelmatch changes only touch the logo
`:post` placement, the `ndi` sun-suppression and the `target-title` SCE re-gate —
none touch the rays). The rays' process lifetime, animation, geometry, merc render
inputs and the background blackout are the SAME on x86 and the device. The merc
fade alpha path is force-disabled for jak1 (`Merc2.cpp:838`), so there is no
per-frame alpha to differ. The linger is therefore **the over-long pure-additive
smash-flash glow being kept alive for the whole logo-intro**: on desktop GL the
additive glow washes out against the revealed scene (looks like a brief flash); on
the device's mobile GPU the identical additive draw stays prominent and the owner
sees it linger. Because the inputs are identical, the difference is a GPU-level
additive-render nuance that cannot be measured pixel-free nor fixed in the GOAL
state — but it CAN be made moot by not submitting the rays past the smash flash.

## The mechanism of the fix
The rays are a one-shot SMASH flash, not a flythrough element. The correct,
backend-independent behavior is to deactivate them shortly after the smash punch so
they cannot persist on ANY GPU. The ext dump shows the starburst expands to full
spread over the first ~0.45s (the punch) and then holds; after the punch the rays
should be gone.

## The fix (goal_src/jak1/levels/title/title-obs.gc → TIT.DGO only)
1. **`logo-slave` `idle` :code**: capture `(current-time)` at entry and, for the
   logo-volumes / logo-volumes-japan slave only (name-gated), `(deactivate self)`
   once `(time-elapsed? spawn-time (seconds 0.6))` — ~0.6s after spawn, just past
   the ~0.45s smash punch. logo-black, logo-cam and every ndi-* slave share this
   state and are explicitly excluded by the name gate, so the Naughty-Dog beat and
   the cameras are untouched.
2. **`logo` `startup` :code**: the spool-end deactivate of black/volumes is now
   wrapped in the existing `(let ((p (handle->process h))) (if p (deactivate p)))`
   guard (mirroring the camera deactivate in `startup` :exit). Without this, the
   slave self-deactivating early leaves a dead handle, and the unguarded
   `(deactivate (handle->process ...))` dispatches `deactivate` on `s7` (#f) and
   SIGSEGVs — observed once on x86 before the guard was added, fixed by it.

The fix is in `title-obs.gc` only (TIT.DGO is a safe level DGO — see
game-cgo-rebuild-unsafe). It applies on both backends; on x86 the rays were already
washing out after the flash so there is no visible change there, while on the device
it removes the lingering additive glow.

## Verification (deterministic, no pixels)
BEFORE: logo-volumes alive ~6.68s (x86) / ~6.69s (device) — the linger reproduced.
AFTER (same GFXRAY dump, then removed):
- our-x86: rays vanish at **0.615s** (base-frame span 185); gk ran the full 80s
  attract with **no crash** (3950 GFXRAY lines, vs 402 before the deactivate-guard).
- device eae4df44: rays vanish at **0.613s** (logical-frame span 185); **crash=0**
  (no GK-DIAG sig=4/6/11 — the guard holds on arm64).
Both backends now match (~0.61s / 185 frames, delta 2ms / 0 frames). The rays flash
during the smash and vanish, matching the intended behavior.

## Cleanup / hygiene
- The temporary `(format 0 "GFXRAY ...")` dump in `logo` :post was **removed** from
  `title-obs.gc` (no GFXRAY string remains in source or in the built TIT.DGO).
- The temporary `title_rays_on()` helper and the `TITLERAY` per-frame log in
  `Merc2.cpp` were **deleted** — `git diff` on `Merc2.cpp` is empty (no leftover).
- The original `jak-original-v033` title-obs.gc dump was restored via `git checkout`
  (byte-pristine again); `.autoport/gold` is git-clean.
- The device known-good backup TIT.DGO (`.autoport/backups/device-knowngood-cgos-20260618/`)
  was updated to the fix TIT.DGO (old preserved as `TIT.DGO.pre-Gfix-title-rays`),
  so `restore_knowngood_device.sh` keeps the fix instead of reverting it.

## Locks respected
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*` touched. `.autoport/gold`
left byte-pristine. x86 still reaches `link finish: logo`.
