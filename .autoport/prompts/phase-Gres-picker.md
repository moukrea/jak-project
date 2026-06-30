# Phase Gres-picker — "Game Resolution" picker: NATIVE + standard ladder per aspect ratio

## Why (owner 2026-06-30)
The game does NOT run at native resolution (internal 3D is pinned low). The owner wants the in-game
"Game Resolution" option to offer, for the current aspect ratio: a "NATIVE" entry (the device's real
screen resolution) + the standard resolution ladder, down to the minimum (640 wide if width-
constrained, else 480 tall). Works on BOTH x86 and Android. A WIP exists (commit 9a1e64c84,
goal_src/jak1/pc/progress-pc.gc + pckernel-common.gc) — finish + verify it.

## Mandate (pc/ + C++ runtime; engine goal_src untouched → gold oracle clean)
Scout map (see [[project_graphics_options_backlog]]): list built by `build-resolution-options`
(progress-pc.gc:1217) from C++ `pc-get-num-resolutions`/`pc-get-resolution`
(game/system/hid/display_manager.cpp:187), filtered to window aspect ratio. Native size already
available: `DisplayManager::get_screen_width/height` (display_manager.cpp:173) — expose via a
`pc-get-native-resolution` symbol if not reachable.
1. "NATIVE" entry at the top = real screen resolution (get_screen_width/height).
2. Build the standard ladder for the CURRENT aspect ratio (VGA 640x480 4:3 … FHD 1920x1080 16:9 …
   4K 3840x2160; plus 16:10/5:4/21:9/17:9 entries) filtered to the selected aspect and clamped:
   floor = 640w (width-constrained) or 480h (height-constrained), ceiling = native. Per-aspect compute.
3. Apply via the existing path (set-window-size!/pc-set-game-resolution, progress-pc.gc:2582).
4. INTERACTION with the RENDER SCALE % option (b7d7afcd7): on this single-FBO engine both feed
   game_res. "Game Resolution" sets the BASE game_res; RENDER SCALE % multiplies it in update-to-os.
   No double/conflicting application — document the order.

## Honest expectation
On this device (Adreno 618, draw-call bound) higher res = sharper but LOWER fps (native ~10fps). That
is fine — the option lets the user CHOOSE the sharpness/fps tradeoff. Do NOT chase native-60.

## Verify (both builds, actual screen)
Device: Game Resolution shows NATIVE + the ladder for the current aspect; selecting higher res
visibly sharpens (fps drops, expected); NATIVE renders at panel res; switching aspect re-filters the
list; setting persists. x86 builds + boots. Full CONSISTENT build, deploy_verify PASS. Screencaps.

## Report (`.autoport/reports/Gres-picker/report.txt`) with `RESULT: RESOLUTION PICKER NATIVE + LADDER`
the menu list (NATIVE + ladder entries), per-aspect filtering, persistence, a low-vs-native sharpness
comparison (screencaps), the render-scale interaction order, x86 link finish: logo.

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; pc/ only goal_src; .autoport/gold READ-ONLY.
## Max: max_turns 1800, max_retries 5. device: true, owner_verify: true.

## OWNER REFINEMENT (2026-06-30) — NATIVE must ADAPT to the selected aspect ratio
Owner play-test: otherwise perfect, but the "NATIVE" entry must NOT be the raw panel size when the
chosen aspect ratio differs from the panel aspect. NATIVE = the LARGEST resolution at the CURRENTLY
SELECTED aspect ratio that fits within the physical panel:
  - if chosen aspect is WIDER than the panel aspect → fit to panel WIDTH, compute height;
  - if chosen aspect is NARROWER/taller than the panel → fit to panel HEIGHT, compute width.
Example (owner's): panel 1080 tall (~2.22:1), choose 4:3 → 4:3 is narrower than panel → height-
constrained → NATIVE = 1440 x 1080 (1080*4/3). Choose 16:9 → 1920 x 1080. Choose the panel's own
aspect → the real panel size. The NATIVE entry's resolution must recompute when the aspect changes.
Keep everything else (the ladder, persistence, render-scale coexistence) as-is.
