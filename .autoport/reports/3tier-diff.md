# 3-Tier jak1 intro/title/menu comparison — pristine vs our fork (PC) vs our fork (Android)

Read-only capture + analysis. No source/renderer/compiler was modified. The only
mutable file touched was the engine-generated runtime config
`build-x86/game/OpenGOAL/jak1/settings/pc-settings.gc` (language/resolution, exactly
as the reference build did); it was restored to its original fork state afterwards.

Captured 2026-06-14.

## Tiers

| Tier | Build | Resolution | English? | Frames |
|------|-------|-----------|----------|--------|
| 1 (pristine) | clean upstream v0.3.3, separate clone | 2400x1080 (internal-res REPL screenshot) | yes | `.autoport/gold/TRUE-original-v033/*.png` |
| 2 (our PC) | our fork x86 `build-x86/game/gk` | **1920x1080** (see note) | yes | `.autoport/reports/3tier/our-pc-*.png` |
| 3 (Android) | our fork on Redmi Note 9 Pro (eae4df44, arm64) | 2400x1080 native landscape | yes (already) | `.autoport/reports/3tier/android-*.png` |

### Capture status
- **Tier 2 (our PC): RENDERS — does not crash, not black.** gk boots fully (KERNEL.CGO links,
  kernel v2.0, GL loop streaming tfrag/textures), reaches the in-engine title attract, audio
  narration (KEIRA) plays. Captured via the engine's own REPL screenshot path
  (`(lt)` over goalc nREPL, then `(pc-screen-shot)`), driven through a pty because goalc's
  replxx line-editor will not submit piped stdin. **Window/X11:** had to set
  `XAUTHORITY=/run/user/1000/.mutter-Xwaylandauth.RKSTQ3` + `DISPLAY=:0 SDL_VIDEODRIVER=x11`.
- **Tier 3 (Android): RENDERS.** App boots to the title flythrough + PRESS-START, START opens the
  main menu. `mCurrentFocus=org.opengoal.gk.jak1` verified on every frame. Captured via
  `adb exec-out screencap`. The fork ships device diagnostic logging (`GINTRO-CHAINWALK ...`).

### Resolution note (Tier 2)
The fork's `screen-shot-settings` GOAL type is **only forward-declared**
(`(declare-type screen-shot-settings structure)` in `kernel-defs.gc`) — it has **no full
`deftype` with named `width`/`height` fields**. So `(new 'static 'screen-shot-settings :width 2400 ...)`
fails to compile ("Type screen-shot-settings is not fully defined"), and the internal-res
2400-wide capture path the pristine clone used is **unavailable in our fork without a source edit**.
`(pc-screen-shot)` therefore falls back to the default 1920x1080 framebuffer. The monitor also
caps the *window* at 1920 wide ("2400x1080 is not a supported resolution → defaulting to 1920x1080"),
exactly as the reference README documented. 1920x1080 16:9 is fully sufficient for the visual
defect analysis below; only exact-pixel diffing against the 2400-wide pristine frames is precluded.

### Objective near-black-pixel metric (proxy for missing/black geometry)
| Frame | near-black % | note |
|-------|-------------|------|
| Tier1 pristine attract | **0.0%** | clean |
| Tier1 pristine menu | 0.4% | clean (orange-tint menu) |
| Tier2 our-PC attract | **2.9%** | black geometry holes |
| Tier2 our-PC title-wait | **3.3%** | black geometry holes |
| Tier3 android title-wait | 5.3% | incl. touch overlay + black geometry |
| Tier3 android title-wide | 4.9% | " |
| Tier3 android menu | 1.3% | black blocks over OPTIONS |

---

## Beat 1 — Title attract / flythrough

| | Tier 1 (pristine) | Tier 2 (our PC) | Tier 3 (Android) |
|--|------------------|-----------------|------------------|
| frame | `01-attract-flythrough.png` | `our-pc-01-attract-flythrough.png`, `our-pc-03b-title-wait-dusk.png` | `android-01-attract-flythrough.png`, `android-03b-title-wide-village.png` |
| scene | Full textured Sandover Village, Jak centered on path, foliage, water, dusk/lavender sky. | Same camera & scene, recognizable (Jak, village, water, foliage). **BUT large BLACK wedges/holes** where huts/rocks/structures should be — center-left black triangle, right-edge black blocks, several huts rendered solid black / see-through. Sky is bright blue daytime early, shifts toward dusk as time-of-day advances. | Scene renders **with textures, no black holes** (thatched huts, stone, foliage, water, sky all present). Big "JAK AND DAXTER" logo + "PRESS START" overlaid; sometimes a level name ("SENTINEL BEACH"). |
| watermark | clean `v0.3.3` top-left + small bind-debug text | **garbled longer yellow/tan string** top-left (the fork's `Compiled Version: 48803d14f` build hash overflowing the watermark slot) | logo overlay instead; no stray corner watermark |

**Divergences & classification**
- **Missing/black village geometry (huts, rocks, structures rendered black/see-through)** — **O→P (our edits broke it)**. Present on our PC build, ABSENT on pristine. This is the owner's "missing geometry / rocks / structures / see-through" issue, and it is reproduced on x86, so it is a fork-edit bug, not ARM/GLES-specific. Curiously it is *worse on PC than on Android here* (Android's title scene shows full geometry), suggesting the PC and Android paths diverge in how they handle the attract draw chain.
- **Garbled top-left watermark text** — **O→P**. Cosmetic; the fork prints a long build hash where pristine prints `v0.3.3`. Maps to owner's "stray text / level-names" but is the version watermark, not a level name.
- **Sky / time-of-day** — minor. Pristine sampled at dusk; our PC starts daytime-blue then advances to dusk. Both tiers cycle time-of-day; not a clear defect.
- **Title logo present (Android) vs absent (pristine v0.3.3 attract)** — pristine v0.3.3 attract shows NO "JAK AND DAXTER" logo, only village + subtitle. Our fork (both PC behavior and Android) shows the classic title logo. This is a fork/version behavioral difference, not corruption.

## Beat 2 — Title-wait / PRESS START

| | Tier 1 (pristine) | Tier 2 (our PC) | Tier 3 (Android) |
|--|------------------|-----------------|------------------|
| frame | `03-title-wait-english-subtitle.png` | `our-pc-03-title-wait.png` | `android-03-title-wait.png`, `android-04-levelname-sentinel-beach.png` |
| indicator | English subtitle "KEIRA: WE NEED POWER CELLS TO FUEL THE HEAT SHIELD…" over village; small top-left bind-debug text. NO logo, NO "PRESS START". | Same corrupted village as beat 1; **no visible "PRESS START" text and no KEIRA subtitle rendered** in the captured frames (text either not in the captured sub-state or culled). | Clean **"PRESS START"** text + **"JAK AND DAXTER: The Precursor Legacy"** logo render correctly; level name **"SENTINEL BEACH"** shown on one flythrough frame. |

**Divergences & classification**
- **"PRESS START" / KEIRA subtitle not visible on our PC** vs clean subtitle on pristine and clean "PRESS START" on Android — **O→P (likely)**. Could be a missed sub-state in the PC capture, but combined with the geometry corruption it points to the PC attract being in a degraded path. Android renders the title-screen UI text cleanly, so the *text/UI layer itself* is fine on the fork — the PC issue is the underlying 3D draw.
- **Level-name overlay "SENTINEL BEACH" (Android)** — maps to owner's "stray level-names". This appears to be the title-attract cycling through level vista names with each scene; whether it is intended polish or stray needs an owner call, but it renders correctly (not corrupted). Behavioral, not a render defect.

## Beat 3 — Main menu

| | Tier 1 (pristine) | Tier 2 (our PC) | Tier 3 (Android) |
|--|------------------|-----------------|------------------|
| frame | `05-main-menu.png` | *(not captured — see below)* | `android-05-main-menu.png` |
| menu text | NEW GAME / LOAD GAME / OPTIONS / SECRETS / QUIT GAME / BACK — clean English | n/a | **Same 6 items, clean English, readable** (green/yellow) |
| background | Village under an **intentional orange/sepia menu tint**; **round green orb/gauge bottom-right** (eco/cell widget, intended); Jak centered | n/a | **Heavily corrupted:** blocky red/orange field (a corrupted version of the orange tint), a **giant misplaced green sphere in the center-bottom** (a corrupted/oversized version of the bottom-right green orb), **black rectangular blocks** over "OPTIONS" and to its right (missing geometry), small black square mid-right |

**Could not capture Tier-2 (our PC) menu.** Reaching the menu requires START during `target-title-wait`
(`title-obs.gc:686` → `(activate-progress *dproc* (progress-screen title))`). Driving that from the
REPL needs game-source globals (`*dproc*`, `*cpad-list*`, `*target*`, `*progress-process*`) — but
**none of the game-source symbols resolve in the connected goalc session** ("looked up as a global
variable, but it does not exist"), because the listener REPL did not compile the full project, and
`(mi)`-loading it was deliberately avoided (it would rewrite CGOs — out of scope for READ-ONLY
analysis and flagged risky in project memory). Synthetic controller injection failed for the same
reason (`*cpad-list*` unresolved). No `xdotool`/keyboard-focus path on this rootless Xwayland host.
**This is itself a finding:** the fork's title→menu beat is not reachable via the same REPL recipe
the pristine clone used, because the fork's REPL/type surface differs.

**Divergences & classification (Android vs pristine)**
- **Garbled menu background — blocky red/orange + giant central green sphere + black blocks** — **P→A (ARM/GLES-specific) corruption of intentional elements.** Side-by-side with the pristine menu shows these are NOT stray new elements: the pristine menu legitimately has (a) a full-frame orange/sepia tint and (b) a round green orb bottom-right. On Android, (a) degrades into blocky red/orange banding and (b) the green orb is mis-sized/mis-placed into a large central sphere, plus genuine black/missing-geometry blocks appear over the menu items. This is the owner's "garbled menu textures/icons" issue. We could not confirm whether our PC build also corrupts the menu (not reachable), so a definitive O→P vs P→A split for the menu corruption is **open** — but the elevated black-block geometry loss is the same class seen on the PC attract (O→P geometry corruption), so the menu likely suffers BOTH an O→P geometry component and a P→A tint/orb component.
- **Menu text** — clean and correct on both pristine and Android (English, all 6 items). No text defect.

---

## Answers to the brief's key questions

1. **Did our edits break x86 rendering too?** **YES.** Our fork's x86 PC build renders the
   attract/title scene with substantial **black/missing geometry** (huts, rocks, structures
   black or see-through; ~3% near-black vs 0% pristine) that the pristine v0.3.3 build does not
   have. So a meaningful chunk of the breakage is **O→P (our compiler/renderer edits)**, not
   purely ARM/GLES. The x86 build is *not* fully broken (it boots, streams, renders a recognizable
   scene with correct UI text), but it is clearly corrupted relative to pristine.

2. **Is our PC build as broken as Android?** **Different breakage profiles.**
   - On the **attract/title 3D scene**, the **PC build looks WORSE** (large black geometry holes)
     while **Android's title scene renders cleaner** (full textured huts/water/sky). This is
     surprising and suggests the attract draw-chain handling diverges between the two backends.
   - On the **main menu**, **Android is visibly corrupted** (blocky red/orange tint, giant
     central green sphere, black blocks); the PC menu could not be captured, so a direct menu
     comparison is unavailable.

3. **Owner issue list mapping**
   - *Garbled menu textures/icons* → Android beat-3: blocky red/orange + central green sphere +
     black blocks. **P→A corruption of intentional orange-tint + green-orb elements**, plus an
     O→P black-geometry component.
   - *Missing geometry (rocks/structures, see-through)* → **O→P**, reproduced on PC (black holes
     in the attract village); also present on Android.
   - *Water (animation/sunlight)* → water is *present* and textured on both PC and Android title
     scenes (no obvious missing-water in these beats); detailed animation/sunlight diff would
     need motion capture, not single frames. **Inconclusive from stills.**
   - *Camera trajectory* → PC attract camera framing closely matches pristine (Jak centered on
     the path); no gross camera defect in these beats. Android attract is a moving flythrough
     (expected). **No clear camera defect at title.**
   - *Title logo / black background* → logo renders correctly on Android; the "black" is the
     missing-geometry holes (O→P), not a black title background.
   - *Stray level-names* → Android shows "SENTINEL BEACH" during the attract flythrough; renders
     correctly (behavioral, likely the attract vista-name cycle). The PC garbled top-left string
     is the build-hash watermark, not a level name.

## Frame index
- Pristine: `.autoport/gold/TRUE-original-v033/{01-attract-flythrough,03-title-wait-english-subtitle,05-main-menu}.png`
- Our PC: `.autoport/reports/3tier/{our-pc-01-attract-flythrough,our-pc-03-title-wait,our-pc-03b-title-wait-dusk}.png`
- Android: `.autoport/reports/3tier/{android-01-attract-flythrough,android-03-title-wait,android-03b-title-wide-village,android-04-levelname-sentinel-beach,android-05-main-menu}.png`
