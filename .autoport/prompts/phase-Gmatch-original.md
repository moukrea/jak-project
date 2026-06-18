# Phase Gmatch-original — make the device match the UNTOUCHED v0.3.3 original (objective harness, zero human eyeballing)

## The point
The owner judges "is it good?" by comparing the phone to the **untouched upstream original** (OpenGOAL v0.3.3, `/home/emeric/code/jak-original-v033`, commit `c4bc4d3ff`) — NOT our modified build. An objective harness now does this automatically. Your job: get the device to match the original on the gated signals, with NO human looking.

## X86-FIRST PRINCIPLE (owner directive — do this before ANY Android deploy)
A divergence has TWO possible causes: (a) OUR code differs from the original even on x86 (a bug in our port that has nothing to do with arm64), or (b) our x86 matches the original but the arm64/Adreno device diverges (a real arm64/GLES bug). **Catch (a) on the HOST first — it is free, fast, and never needs the phone.** For EACH divergence (halo, menu black-rects, new-game crash, etc.):
1. Build/run OUR x86 (`build-x86/game/gk`, our current code) AND the untouched original (`/home/emeric/code/jak-original-v033/.../gk`), capture the same beat from BOTH on the host, and `frame_compare.py` them.
2. If **our-x86 already differs from the original** → it's an x86-level bug in OUR code. FIX IT ON THE HOST (edit + rebuild x86 + re-compare), iterating with NO device involved, until our-x86 matches the original.
3. ONLY when our-x86 matches the original but the DEVICE still diverges do you build/deploy to arm64 — that residual is the genuine arm64/Adreno delta.
EXTEND the harness to do this automatically: add an x86 capture+compare stage so `report.json` tags each beat as `x86_matches_original` (our-code OK) vs `arm64_only_divergence`. This makes the loop spend device cycles only on real arm64 bugs. (Note: the halo's `#ifdef __ANDROID__` Adreno fix means the halo is likely arm64-only — our x86 won't show it — but VERIFY, don't assume; the menu black-rects and the new-game crash may well reproduce on x86 = our-code bugs.)

## The objective gate (this IS your ground truth — run it, read it, don't guess)
- `bash .autoport/lib/verify_device_graphics.sh` → writes `.autoport/reports/graphics-verify/report.json`: per-beat (intro-logo, title-pressstart, main-menu, newgame-cinematic, ingame-firstframe) {reached, diff_frac vs the v0.3.3 oracle, halo_excess_frac, MATCH/MISMATCH} + crash_signatures.
- Oracle refs from the v0.3.3 original: `.autoport/gold/oracle-beats/*.png` (capture more via `.autoport/lib/capture_oracle_beats.sh` if you need newgame/ingame oracle frames — its TODO: the original's DECI2 listener doesn't bind on this host + START is remapped; solve that to capture the cinematic/in-game oracle beats).
- The validator `.autoport/validators/phase-Gmatch-original.sh` PASSES when: **crash_signatures==0 AND ingame-firstframe reached AND no halo at intro-logo (halo_excess_frac<0.01)**. (The moving intro/title PIXEL diffs are phase-confounded — NOT gated yet; if you want them as gates, add matched-phase capture per the "Moving-beat matched-phase" memory.)

## Current objective verdict (baseline — the build on the device now = f1c CGOs + a 93f639155 libgk)
- **NEW GAME CRASHES: `sig=11` SIGSEGV while linking the intro cutscene** (`link finish: logo-intro-2`, `fishermans-boat-ride-to-misty`, ~frame 2089) → never reaches cinematic/in-game. THIS is the #1 blocker for "playable".
- **Halo present at intro-logo** (halo_excess_frac=0.050) — a bright blob the original doesn't have.
- Menu opens, layout matches the original; residual = black-rectangle artifacts behind the text.

## Hard constraints you must work within
- The device can ONLY boot **f1c CGOs** (every rebuilt CGO set crashes at frame 180 — that's the separate Gspark-enterstate phase). So **all your fixes ship via `libgk.so`** (the device runs f1c CGOs + your libgk). Do NOT try to ship rebuilt boot CGOs here.
- The current device libgk is **93f639155** — it PRE-DATES the cutscene-crash fixes **`6a8035ae4` (Gnewgame) and `3deef6bf3` (Gcine-crash3)**. The new-game `sig=11` is almost certainly fixed by those. **First experiment: build a CLEAN libgk from a commit that HAS them (e.g. HEAD/`67ad5176d` or `3deef6bf3`), deploy it (APK reinstall) with f1c CGOs, and re-run the harness — does newgame-cinematic/ingame-firstframe now reach?**
- The halo: `93f639155` is the documented title-halo fix and it IS in the libgk, but the harness still sees a blob at intro-logo. Investigate whether (a) the ND-logo blob is a SEPARATE glow source from the title one, or (b) it's the original's "sun" off-screen-on-4:3 leaking into the device's 2.222 framing (compare the v0.3.3 oracle intro-logo frame). Fix the real one; the gate is the objective metric, not your eyes.

## Build/deploy mechanics (build-android is freshly clean now)
- libgk for the device = gradle's RelWithDebInfo build of `build-android` (shared dir; gradle only reconfigures if CMakeCache absent). To deploy a libgk: checkout the commit's `game/ android/ common/`, `cd android && ./gradlew :app:assembleJak1Debug`, then `pm install -r -d -t -i com.android.vending` the APK (MIUI: `appops set com.android.shell REQUEST_INSTALL_PACKAGES allow`). Keep f1c CGOs in `files/iso_data/jak1/` (don't wipe `.extracted_v1`).
- Device serial `eae4df44` ONLY. After any failing run, `bash .autoport/restore_knowngood_device.sh` (the validator also does this). Never leave the phone bricked.

## Done = the validator passes (objective)
crash_signatures==0, reaches in-game, no halo at intro-logo — judged by `verify_device_graphics.sh` vs the v0.3.3 original, no human in the loop. Bonus: drive the menu black-rect artifact + (once oracle beats exist) the cinematic/in-game pixel-match to MATCH too.
