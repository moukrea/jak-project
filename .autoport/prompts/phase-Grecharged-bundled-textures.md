# Phase Grecharged-bundled-textures — first-party RECHARGED TEXTURES (owner's PBR set, bundled in the APK)

ultrathink. Manager designs + verifies; delegate mechanical work.

## OWNER DIRECTIVE (2026-07-21)
The owner made a first-party PBR texture set FROM SCRATCH for village1 (7 textures). It is IMPORTED +
COMMITTED at `custom_assets/jak1/recharged_textures/<tpage>/<texname>/` (72 MB, 28 PNGs):
`village1-vis-tfrag/{vil-hut-roof-tile-01, vil1-sages-strawroof-01, vil-beachrock, vil1-jng-leafyground,
vil1-sages-stonewall-01, vil-beach-01, vil-wallplaster}`, each with:
- `<tex>.png` (NO suffix) = a REPLACEMENT of the original texture → shown when the NEW **"RECHARGED
  TEXTURES"** toggle is ON (this menu option does not exist yet — ADD it).
- `<tex>_height/_normal/_roughness.png` = the PBR maps → consumed when the **PBR option** is ON (the
  existing loader suffix convention).

## REQUIREMENTS
1. **BUNDLED, not side-loaded**: these ship IN the APK/binaries (like the probes packaging) — extracted by
   LoaderActivity (there is already a `recharged_assets/` extraction channel ~line 889) so a plain install
   has them. NOT the user custom_assets dir.
2. **NEW "RECHARGED TEXTURES" on/off menu row** (Recharged Settings; label clean, no unknown-ID; persisted;
   greyed appropriately; **update `.autoport/menu-tree.md`** — standing rule). ON => the bundled base
   replacements are used. OFF => stock textures.
3. **PBR maps path**: when PBR materials is ON, the bundled `_height/_normal/_roughness` maps feed the PBR
   pipeline for those textures (same lookup_suffixed convention), regardless of the base-replacement toggle
   (document the chosen interaction: PBR maps should apply whenever PBR is ON; base replacement only when
   Recharged Textures is ON).
4. **PRECEDENCE (owner): user custom_assets > bundled recharged > stock.** A user file with the same name in
   the device custom_assets dir overrides the bundled one (both for base and for PBR maps). Prove it.
5. Respect the master-toggle contract (when the global Recharged master lands: master OFF => stock textures).
6. OFF==stock byte-identical; jak1 focus; device evidence (A/B stock vs recharged-textures ON showing the
   owner's textures on device; PBR maps active under PBR ON).

## GATES
- Source: bundled extraction path wired (LoaderActivity/recharged channel), toggle + FFI + persistence.
- Device: A/B toggle ON/OFF (owner textures visibly land, measured diff on the right tpage surfaces);
  precedence test (a user custom override wins); OFF==stock.
- menu-tree.md updated. Report RESULT: PASS + evidence. owner_verify: the owner judges his own textures.

---
## SUPERVISOR — REPORT DISCIPLINE (attempts 1-2 exited with ZERO report)
Create `.autoport/reports/Grecharged-bundled-textures/report.txt` in your FIRST 10 turns (RESULT: WIP) and
fill it as you go; flip to RESULT: PASS + "READY FOR OWNER VISUAL CHECK" the moment the mechanical bar is
met (build installs, boots, textures land, toggle wired, precedence proven by grep/log — NO capture
batteries). Reserve the last 20% of your budget for finishing the report. An attempt that exits without a
report wastes everyone's time.
