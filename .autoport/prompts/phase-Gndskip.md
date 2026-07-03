# Phase Gndskip — START at the Naughty Dog logo must skip TO the Jak and Daxter logo, not to black

## Why (owner 2026-07-03, v3 playtest)
Pressing START during the Naughty Dog logo sequence does not skip: the screen just goes BLACK while
the sequence's audio keeps playing in the background, until the Jak and Daxter logo eventually
appears at its normal time. Expected: skipping should jump the whole ND sequence and land directly
at the Jak and Daxter logo appearance.

## Mandate
1. REPRODUCE on eae4df44: boot, press START (cpad inject) during the ND logo, screenrecord — show
   the black gap until the J&D logo. Measure the gap.
2. ORACLE: same input on the pristine x86 golden. Does x86 skip instantly to the J&D logo, or does
   it black-out the same way? If x86 skips correctly → Android divergence (find where the skip path
   diverges: intro/ndi process kill vs sequence clock, arm64 side). If x86 has the same black gap →
   upstream behavior; the owner wants it IMPROVED anyway — implement the skip in the pc layer
   (pc/ goal_src or runtime glue): on skip, advance to the J&D-logo beat (kill the ndi spool/
   process and jump the sequence clock), do not just blank the display. Mind the Gndlogo/Ghalo
   lessons (done?-gated village display, sun-fade suppression — do not regress them; TIT.DGO is
   safe to rebuild+push, boot CGOs are NOT).
3. Verify: START during ND → J&D logo appears within ~1s, audio consistent (no orphan ND audio),
   no black hole; not pressing START still plays the full sequence; title screen intact
   (attract/logo placement/halo unregressed — screencap vs golden). x86 link finish: logo.

## Report (`.autoport/reports/Gndskip/report.txt`) with `RESULT: ND SKIP LANDS ON JAK LOGO`
the measured before-gap, the oracle verdict, the skip path + fix (file:line), the after timing,
no-skip path intact, title unregressed, x86 ok.

## Locks: ANDROID_SERIAL=eae4df44 only; no goalc/emitter/IGenX86_64.*; engine goal_src untouched (pc/ ok, TIT.DGO rebuildable); .autoport/gold READ-ONLY.
## Max: max_turns 2000, max_retries 5. device: true, owner_verify: true.
