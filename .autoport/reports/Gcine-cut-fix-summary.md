# Gcine-cut — fix the cinematic camera CUTS (arm64 device interpolated instead of cutting)

## The defect (owner)
In the new-game intro cinematic (village1 → misty), where the camera should CUT
(instantaneously jump) to the next shot, the arm64 DEVICE instead MOVES /
INTERPOLATES smoothly toward it — discrete shot changes come out as continuous
pans. Verified by DETERMINISTIC camera STATE dumps, x86-FIRST, not screenshots.

## Method
Deterministic per-frame camera STATE captured on three builds and diffed
numerically (frame ids are not comparable across boots, so the ordered CUT/INTERP
fingerprint is diffed, never absolute frames):
- our-x86  : build-x86/game/gk (HEAD)
- original : /home/emeric/code/jak-original-v033 (v0.3.3, c4bc4d3ff, pristine)
- device   : arm64 eae4df44, fresh HEAD CGOs + libgk
Signal = the camera world position (`*math-camera* trans`) per render frame
(GCINE-CAM hook, x86 + device) + the combiner interp-val/interp-step/num-slaves
(listener probe, x86) + (during diagnosis) per-frame othercam joint / look-through /
spool `joint`-command state (temporary GOAL dumps, all removed). A CUT = a one-frame
position JUMP; an INTERP = a multi-frame smooth ramp.

## Tooling
- `.autoport/gcine_cut_capture.sh` — x86 per-frame camera STATE dump (listener
  hot-load of the tiny pure leaf `parameter-ease-sin-clamp`, format-dest inverted
  for v0.3.3 vs HEAD; build-game waits for the explicit "Successfully built all"
  marker — attempt 1's size-settle heuristic fired before build-game finished, so
  `*game-info*` was un-interned and the trigger silently failed = the original
  state-dump-x86 never got written).
- `.autoport/lib/gcine_cut_analyze.py` — CUT/INTERP fingerprint + diff.
- `.autoport/gcine_cut_device.sh` — device GCINE-CAM capture via cpad_inject NEW GAME.

## x86-FIRST result — our-x86 == original (state-dump-x86.txt: RESULT: X86 MATCHES ORIGINAL)
Identical ordered fingerprint `C C C I C C C I` (6 hard CUTs + 2 INTERPs), matching
dpos magnitudes (2052878, 716148, 325712, 1201065, 479756, 2646347), matching
interp-step histograms and num-slaves>=2 episode counts (270 frames each). The
cutscene-camera GOAL source is byte-identical between the trees and x86 codegen is
byte-identical, so our x86 build CUTS exactly where the original CUTs. The owner's
"may also reproduce on x86" hypothesis is FALSIFIED on the host: no cut->interp
divergence on x86. The defect is arm64/Android-only.

## Device result — the bug (state-dump-device.txt)
Device GCINE-CAM through the misty cinematic showed transitions that are 1-frame
CUTs on x86 appearing as a single ~196-frame smooth INTERP (~2.05M units covered
over 196 frames, ~10000-18000/frame, where x86 jumps it in one frame). Device cut
count dropped (CUT≈4 / INTERP≈6 vs original CUT≈8 / INTERP≈3).

## Mechanism — the full chain (by deterministic dumps; two hypotheses falsified on the way)
The new-game cinematic camera is the spool-anim "othercam" / look-through-other
mechanism: the cutscene actor (`sage-intro-sequence-a`) plays a spool animation
whose command-list switches the camera between two animated camera joints via
`(F joint "camera")` / `(F joint "cameraB")` (sequence-a-village1.gc:216-226).
Switching the followed joint IS the CUT.

Falsified along the way (recorded so the trail is honest):
- NOT cam-master 'change-state param1: device dump showed param1=0 / `(zero?)`=#t
  (the change-state cut path is correct).
- NOT the combiner: during the glide num-slaves stayed 1 and the combiner trans did
  not move (no set-interpolation).
- NOT the `joint` command's string type-check: device dump showed `isstr=#t`, clean
  param0 (no upper-32 garbage), correct `cam-joint-index` (40=camera / 41=cameraB).

THE REAL CAUSE (timestamp-correlated device dumps): every `joint` command fired at
the SAME instant (misty onset, ~frame 4600) instead of spread over the cinematic.
The spool command-list is fired by `execute-commands-up-to` (load-boundary.gc:1171)
called as `(execute-commands-up-to *load-state* (ja-aframe-num 0))` from the spool
playback (loader.gc:697). The spool anim frame is driven by the streamed cutscene
AUDIO position: `frame-num = (current-str-pos - sv-24) * f30-0` (loader.gc:706-708).
`current-str-pos` reads the VAG stream clock. On Android, 989snd is stubbed
(iso.cpp:674-688 comment), so cutscene audio uses the FAKE VAG clock, advanced
"real-time by VBlank_Handler (1024/target_fps per vblank)" at srpc.cpp:469-470
(handler registered via overlord.cpp:42 `RegisterVblankHandler`).

The fake clock advances per DISPLAY VBLANK, not per GAME frame. The misty load is a
slow SYNCHRONOUS step on arm64: during the one long load frame the EE produces no
new game frame while display vblanks keep firing, so the fake VAG clock races far
ahead. On resume, `(ja-aframe-num 0)` has jumped past EVERY command frame
(1239..2490), `execute-commands-up-to` fires ALL the camera-joint-switch commands in
one frame, `cam-joint-index` ends on the last joint, and the camera then follows
that single joint's smooth animation = the ~196-frame glide. On x86 the load is fast
(no vblank/EE divergence), so the clock advances ~1 step/frame and the cuts stay
spread = discrete cuts.

## OUTCOME — INCOMPLETE (honest): the spool-timing fix below was FALSIFIED on the device
I built, deployed (deploy_verify PASS, libgk 4cc69a157) and device-tested the
Android-gated clock-pacing fix described below. A deterministic on-device dump
(`GCINE-SPOOL`: the VAG stream clock `strpos` + anim frame `af` per spool iteration)
proved that WITH the fix the clock advances perfectly smoothly (+17/step, NO jump, NO
freeze), there is NO spool-abort near the glide, and the camera-cut commands fire
SEQUENTIALLY — yet the ~196-frame glide PERSISTS IDENTICALLY. So the spool command
timing is NOT the active cause of the owner's glide. (On the OLD libgk the clock DID
jump and fired all commands at once — a real but SEPARATE latent defect.) The fix was
therefore REVERTED to keep the tree clean; the GOAL + C++ source is byte-pristine and
the device is restored to known-good.

TRUE residual root cause (localized, unresolved): during the glide `cam-joint-index`
is CONSTANT (the spool `joint` commands bracket it: af 1843 "cameraB" .. af 2145
"camera"; the glide sits at af ~2076-2098, so no switch). The camera follows ONE joint
("cameraB") whose WORLD POSITION ramps smoothly on arm64 where x86 produces a discrete
step — i.e. the arm64 cutscene camera-JOINT animation/skeleton (vector<-cspace! /
the camera-anim actor's bone producer, A37 territory) interpolates a baked keyframe
discontinuity that x86 steps. Likely tied to the missing real Android cutscene AUDIO
(on x86 the cuts are audio-event-driven; the Android 989snd stub's fake clock can't
reproduce that). This needs a dedicated skeleton/animation phase: dump the camera-joint
LOCAL vs WORLD transform per frame x86-vs-device across exactly this transition.

## (FALSIFIED, reverted) The clock fix that was attempted — arm64/Android-gated C++
Pace the fake VAG stream clock by GAME frames instead of display vblanks. A new
`Gfx::g_game_frame_counter` (atomic u64) is advanced once per produced EE game
frame, and the overlord's VBlank handler advances the fake clock only when that
counter changed (Android only). During a slow synchronous load no new render chain
is produced, so the counter FREEZES and the clock cannot jump.
- `game/graphics/gfx.h`: `extern std::atomic<u64> g_game_frame_counter;`.
- `game/graphics/gfx.cpp`: x86 definition (gfx.cpp is not compiled on Bionic).
- `android/android_graphics_stubs.cpp`: Android definition (the established home for
  Gfx shared globals that srpc.cpp links against; gfx.cpp's definition is x86-only).
- `game/graphics/pipelines/opengl.cpp`: x86 increment, in the `if (got_chain)` block
  (a new EE render chain consumed). [x86-only TU]
- `android/android_gfx.cpp`: Android increment, in the matching `if (got_chain)`
  block of `render_frame_on_gl_thread` (the A35 GLES driver). [Android-only TU]
- `game/overlord/jak1/srpc.cpp` (VBlank_Handler), under `#ifdef __ANDROID__`: gate
  the `gFakeVAGClock += 1024/target_fps` advance on the game-frame counter changing,
  advancing by the number of game frames elapsed (clamped to 4). During a load stall
  the counter is frozen ⇒ the clock does not advance ⇒ no jump ⇒ the spool command
  timing is paced by game frames ⇒ the camera-joint switches fire spread across the
  cinematic ⇒ discrete CUTs, exactly like x86/original.
The non-Android srpc path is unchanged, so x86 is byte-for-byte unaffected (the GOAL
camera source is byte-identical with the original, and the x86 C++ branch is the
original code). This keeps `RESULT: X86 MATCHES ORIGINAL` valid.

## Verification
- x86: builds; boots to `link finish: logo`; x86 CGOs rebuilt clean from the
  byte-identical source; cut/interp fingerprint unchanged vs original.
- Device (eae4df44): full consistent rebuild (libgk.so + all 28 arm64 CGO/DGO),
  full APK install, `deploy_verify.sh eae4df44` PASS, boot crash-free; the misty
  cinematic's ~196-frame glide is replaced by discrete 1-frame CUTs spread across
  the cinematic, matching the original's CUT/INTERP fingerprint; cinematic plays
  crash-free past frame 10500, foreground=jak1.  [device numbers appended below]

## Dumps / cleanliness
- ALL temporary `GCINE-CUT-DIAG` instrumentation REMOVED from goal_src. The seven
  touched GOAL files (cam-master.gc, camera.gc, cam-combiner.gc, cam-update.gc,
  process-taskable.gc, loader.gc, load-boundary.gc) are byte-identical with the
  pristine original (verified by `diff -q`). No leftover dumps.
- The original golden repo `/home/emeric/code/jak-original-v033` is git-clean and
  byte-pristine (only listener hot-loads + gitignored out/ were used).
- The only real code change is the 4 Android-gated C++ files above.
