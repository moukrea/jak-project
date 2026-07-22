# Phase Grecharged-naming — product renaming: "Jak and Daxter: Recharged Collection"

Small, surgical branding phase. No rendering changes.

## OWNER DIRECTIVE (2026-07-22)
The project is renamed. New official naming:
- The COLLECTION (launcher / overall product): **"Jak and Daxter: Recharged Collection"**
  (was "Jak and Daxter: The Recharged Jak-pot").
- Jak 1 (The Precursor Legacy): **"Jak and Daxter: Recharged"** (a nod to "Crash Bandicoot 3: Warped").
- Jak II: **"Jak II: Recharged"**.
- Jak 3: **"Jak 3: Recharged"**.

## WHAT TO DO
1. Find EVERY user-facing occurrence of the old naming ("The Recharged Jak-pot", "Recharged Jak-pot",
   "Jak-pot", and any per-game old titles) and replace with the new names: android strings.xml (app label,
   launcher collection UI), AndroidManifest labels, the Glauncher-collection UI strings, README/docs,
   window titles (desktop gk), about/credits strings, packaging names shown to the user
   (jak-builds release naming can follow later — note it).
2. Per-game titles: the launcher and any title-screen/menu place that names the game must use the per-game
   names above. Do NOT touch save-file compatibility identifiers, package ids (org.opengoal.gk.jak1) or
   internal symbols — USER-FACING strings only (renaming package ids would break installs/saves; explicitly
   out of scope).
3. Update `.autoport/menu-tree.md` if any menu string changes (standing rule).
4. OFF==nothing to toggle here; just ensure builds still compile + boot (mechanical bar) on device.

## EXIT (owner protocol)
Mechanical bar: compiles, installs, boots, the new names visibly present (launcher label + collection UI),
zero package-id changes (grep-proof). RESULT: PASS + "READY FOR OWNER VISUAL CHECK" + where to look.
