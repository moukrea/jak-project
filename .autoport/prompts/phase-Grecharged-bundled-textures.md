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

---
## OWNER PLAYTEST (2026-07-22 soir) — TEXTURES LOAD ✅ BUT PRECEDENCE IS BROKEN. Fix = the last item.
Owner on device: "les textures rechargées chargent ! EN REVANCHE si ces mêmes textures (même FILENAME)
existent aussi dans les custom assets de l'utilisateur, elles doivent prendre la PRIORITÉ. J'ai un pack de
textures d'internet en custom qui remplace TOUTES les textures, et malgré tout ce sont les textures
rechargées qui apparaissent. Hormis ça, validé."
THE BUG: the lookup resolves the BUNDLED recharged texture even when a USER file with the same
tpage/filename exists in the device custom_assets dir. Required order, BY FILENAME, at lookup time:
  1. user custom_assets (the customisation channel — always wins)
  2. bundled recharged (our first-party set)
  3. stock
Check the actual lookup path (custom_tex::lookup / the recharged-bundled resolution added this phase) — the
bundled source was probably checked FIRST or the user dir scan misses when the recharged toggle is ON.
PROVE on device with the owner's scenario: a USER custom file with the SAME name as a bundled one (e.g.
vil1-sages-stonewall-01.png) must visibly/log-provably be the one loaded ("custom texture replacements: N
user files" scanner line + which source won per file). Mechanical bar + READY then; the owner re-verifies
with his internet texture pack.
