---
name: project_hd_models_state
description: Grecharged-hd-models LANDED 4/4 — jak2 HD Jak/Daxter/Samos/Keira into jak1 via conditional ENHANCED MODELS toggle; the gotchas that made it work
metadata:
  type: project
---

Grecharged-hd-models PASS 2026-07-14 (commit 6fdfb4b9a): jak2's detailed highres
Jak/Daxter/Samos/Keira (jak1-look) replace jak1 low-poly, driven by jak1 anims.
**4/4 land** on x86 + device (eae4df44); GAP 2 (arm64 highres merc stress) CLEAN
(90s soak, 0 fatal sigs). Daxter has one cosmetic weight-borrow tail-drape.

Non-obvious facts (the ones that cost time):
- **merc match name = `<name>-lod0`, NOT `-mg`.** The merc-replacement importer matches the
  GLB stem against the merc-CTRL name (eichar-lod0 / sidekick-lod0 / geologist-lod0 /
  assistant-lod0). The prestudy's `*-lod0-mg.glb` names silently NO-OP'd. Staged GLBs in
  `recharged_assets/hd_models/` are renamed to the correct `-lod0` stems.
- **Weight-borrow path** (no cross-game joint remap): export skinless GLB (strip skin +
  JOINTS_0/WEIGHTS_0, ADD smooth normals — importer derefs normals or throws) → importer
  re-skins to the jak1 rig via find_closest (merc_replacement.cpp). HD models carry own eyes
  → NO copy_eye_draws needed.
- **FR3 map:** Jak+Daxter → GAME.fr3 (common, loaded at boot); Keira → village1.fr3; Samos →
  village2.fr3. Conditional bake `scripts/shell/build_enhanced_models.sh` (gated on
  iso_data/jak2 DGOs) writes `out/jak1/fr3/enhanced/*.fr3` and RESTORES stock byte-identical.
- **Toggle plumbing:** pc-settings `recharged-enhanced-models?` (default #f) → gfx.h flag;
  `Loader.cpp hd_fr3_path` prefers fr3/enhanced/<name>.fr3 when ON+present else stock
  (OFF==stock). Menu row in `*recharged-options-pc*`, hidden via live-length when
  `pc-enhanced-models-available?` (fr3/enhanced/GAME.fr3 present) = 0. See [[project_goptions_reorder_menu_tooling]].
- **SEED must be in the SHARED `Loader::load_common`, not OpenGLRenderer ctor.** Common GAME.fr3
  loads at renderer construction BEFORE GOAL's per-frame push; Android uses a SEPARATE
  `AndroidOpenGLRenderer` class. Seeding in desktop OpenGLRenderer left the flagship swap dormant
  on device (GAP B). Relaunch applies Jak/Daxter (common); villages apply on level reload.
- **Stale arm64 CGO trap (GAP A):** goal_src menu edits need a fresh arm64 CGO/DGO set —
  `.autoport/build_arm64_full_consistent.sh` — or the device runs old GOAL with no row/push.
  See [[feedback_stale_asset_dgos]]. Device reads enhanced FR3 from EXTERNAL root
  fr3/enhanced/; launch via `.LoaderActivity` (re-extracts), NOT `.MainActivity`.
