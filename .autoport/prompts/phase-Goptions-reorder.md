# Phase Goptions-reorder — reorder the Graphics Options menu + rename PS2 Options + hide Min-Target-FPS when Dynamic off

## Why (owner 2026-07-01, TOP PRIORITY)
The Graphics Options menu order is now a jumble after all the added entries. The owner wants this exact
order and two tweaks. Pure menu/UX (pc/ only) — no renderer behavior change.

## The exact order (goal_src/jak1/pc/progress-pc.gc, the graphics-options arrays — desktop + Android)
1. Aspect Ratio
2. Game Resolution
3. Dynamic Render Scale
4. Render Scale / Min Render Scale   (the same entry that relabels: "RENDER SCALE" when Dynamic OFF,
   "MIN RENDER SCALE" when Dynamic ON — already implemented; just position it here)
5. Min Target FPS   (the "Minimum target framerate" entry) — **HIDE it when Dynamic Render Scale is
   OFF** (only visible/relevant when dynamic is ON); show it when ON.
6. FPS Counter
7. V-Sync
8. MSAA
9. Advanced settings   (RENAME the existing "PS2 Options" entry to "Advanced settings"; same submenu)
(+ BACK stays last, after 9.)
Apply to BOTH the desktop `*graphic-options-pc*` array and the Android-specific array (the batch-1
Android array that hides Display-mode/Display/Frame-rate). Keep those Android hides intact.

## Notes
- The label rename to "Advanced settings" uses the existing name-override mechanism (ALL-CAPS if the
  menu font needs it, like the other added labels). Do NOT change the submenu contents.
- Hiding Min Target FPS when Dynamic is OFF: use the option's `option-disabled-func` / build-time skip
  gated on `(-> *pc-settings* dynamic-render-scale?)` (or however the dynamic toggle field is named).
- goal_src edits in pc/ ONLY; engine goal_src untouched (gold oracle clean).

## Verify (device + owner)
On device eae4df44, the Graphics Options list shows exactly: Aspect Ratio, Game Resolution, Dynamic
Render Scale, Render Scale/Min Render Scale, Min Target FPS (only when Dynamic ON), FPS Counter, V-Sync,
MSAA, Advanced settings, Back. "PS2 Options" no longer appears (now "Advanced settings"). Toggling
Dynamic Render Scale ON/OFF shows/hides Min Target FPS. All entries still work. x86 builds + boots.
Full CONSISTENT build, deploy_verify PASS. Screencap the reordered menu (Dynamic ON and OFF).

## Report (`.autoport/reports/Goptions-reorder/report.txt`) with `RESULT: GRAPHICS OPTIONS REORDERED`
the new order (screencaps ON + OFF), PS2 Options → Advanced settings rename, Min Target FPS hidden when
Dynamic OFF, Android hides intact, x86 link finish: logo.

## Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64.*; engine goal_src untouched; pc/ only goal_src; .autoport/gold READ-ONLY.
## Max: max_turns 1500, max_retries 5. device: true, owner_verify: true.
