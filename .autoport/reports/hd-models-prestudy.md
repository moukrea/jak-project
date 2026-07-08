# Grecharged-hd-models — Read-only Prestudy

De-risking "swap jak1's low-poly Jak/Daxter/Samos/Keira for jak2 intro-era detailed
(`*-highres`) models." All findings are STATIC (config dumps + decompiler/goal_src
source). No decompiler run was needed — the checked-in joint-node/art-group dumps
already answer the joint-count + naming questions.

## TL;DR per-character verdict

| jak1 target (merc name) | jak1 joints | jak2 donor (`-highres`) | jak2 joints | Verdict |
|---|---|---|---|---|
| Jak player (`jakc`/hero, low-poly) | UNKNOWN-static (not in level dumps) | `jak-highres-lod0-mg` | **63** | needs-remap / infeasible-static-unknown |
| Daxter = `sidekick-lod0-mg` | **49** | `daxter-highres-lod0-mg` | **62** | needs-remap (mismatch 49≠62) |
| Samos = `geologist-lod0-mg` | **78** | `samos-highres`=80 / `youngsamos-highres`=58 | 80 / 58 | needs-remap |
| Keira = `assistant-lod0-mg` | **96** | `keira-highres-lod0-mg` | **95** | needs-remap (near, but ≠) |

No character is a **direct** drop-in, because the OpenGOAL merc-replacement import
does NOT remap joints by name — it uses the GLB joint index RAW as a bone index into
the TARGET model's bone array (see Import Path). Equal joint COUNT is necessary but
not sufficient; the joint ORDER/hierarchy must also match, which is not guaranteed
across games. None of the counts even match, so all four need an explicit rig-remap
step in Blender (rename+reorder the highres skin to the jak1 skeleton) OR the
weight-borrow fallback (see below).

## Extraction recipe (dump jak2 highres models to GLB)

The decompiler does NOT export individual actors to GLB directly. Two supported paths:

1. **Level rip (whole-DGO .glb, includes actors):** set in
   `decompiler/config/jak2/jak2_config.jsonc`:
   - `"rip_levels": true` (line 127) → writes `decompiler_out/jak2/levels/*.glb`
   - restrict work with `"allowed_objects": [...]` (line 10) to the intro/cutscene
     DGO that loads `jak-highres-ag`/`daxter-highres-ag` to keep it fast + <2GB.
   Command: `./build/decompiler/decompiler decompiler/config/jak2/jak2_config.jsonc <jak2-iso-extract> decompiler_out/`
   (This exports the actor merc mesh inside the level GLB; you then isolate the actor
   mesh in Blender.)

2. **Round-trip via merc_replacement (preferred for isolating one actor):** the same
   codepath that IMPORTS also defines the model name space. The cleanest per-actor GLB
   comes from the community jak2 asset-rip flow, but statically the donor merc names to
   target are exactly: `jak-highres-lod0-mg`, `daxter-highres-lod0-mg`,
   `youngsamos-highres-lod0-mg` (or `samos-highres-lod0-mg`), `keira-highres-lod0-mg`.

To also emit the joint skeleton mapping for verification, set (already have dumps
checked in, but to regenerate): `"dump_joint_geo_info": true` + `"dump_art_group_info": true`
with `"allowed_objects": []` (ALL objects) → writes
`decompiler/config/jak2/ntsc_v1/joint-node-info.min.json` and `art-group-info.min.json`.

## jak1 target model names (what the replacement must be keyed to)

Drop `<mercname>.glb` into `custom_assets/jak1/merc_replacements/` where `<mercname>`
matches the jak1 merc model name EXACTLY (stem, no extension):
- Daxter: **`sidekick-lod0-mg`**  (`sidekick-ag`, jg=`sidekick-lod0-jg`, 49 joints)
- Samos:  **`geologist-lod0-mg`** (`geologist-ag`, jg=`geologist-lod0-jg`, 78 joints)
- Keira:  **`assistant-lod0-mg`** (`assistant-ag`, jg=`assistant-lod0-jg`, 96 joints;
           note Keira has per-level variants: assistant-firecanyon/lavatube/village2/3 = 94–96)
- Jak player: art-group is `jakc`/hero, loaded from a COMMON/hero DGO not present in
  the level-scoped joint dumps → joint count UNKNOWN from static dumps here. MUST be
  resolved by the phase: enable `dump_joint_geo_info` on ALL objects OR read the hero
  art file. (jak1 `jak-white-lod0-jg` = 83 is a cutscene-white variant, likely the
  player skeleton's sibling; treat 83 as a hint, not confirmed player count.)

jak2 donor art-groups (intro/"pre-timeskip jak1-look" = the `-highres` cinematic set),
from `decompiler/config/jak2/ntsc_v1/art-group-info.min.json`:
`jak-highres-ag`, `daxter-highres-ag`, `samos-highres-ag`, `youngsamos-highres-ag`,
`keira-highres-ag` (also kid-highres, plus darkjak/baron/etc.).
Joint counts from `decompiler/config/jak2/ntsc_v1/joint-node-info.min.json`:
jak-highres=63, daxter-highres=62, samos-highres=80, youngsamos-highres=58,
keira-highres=95, kid-highres=64.

## Import path (how a GLB becomes a merc model on-device)

Files: `decompiler/level_extractor/merc_replacement.cpp` (+ `.h`),
`decompiler/level_extractor/extract_merc.cpp` (`replace_model` @1621,
`add_custom_model_to_level` @1656), `decompiler/level_extractor/extract_level.cpp`
(@119 discovers `custom_assets/<game>/merc_replacements/*.glb`),
`common/util/gltf_util.cpp` (joint/weight extraction).

Two modes:
- **replace_model** (our case): fires only if `model.max_bones < 100`
  (extract_merc.cpp:1622). Loads the GLB, then `merc_convert_replacement`
  (merc_replacement.cpp:283). If the GLB has NO custom skin/weights, it calls
  `find_closest(old_verts,...)` (line 261/295) to COPY each new vertex's joint indices
  + weights from the nearest OLD jak1 vertex — i.e. the highres mesh is re-skinned to
  the jak1 rig by spatial proximity, no name remap. If the GLB HAS a skin
  (`enable_custom_weights` extra + JOINTS_0/WEIGHTS_0), it uses the GLB's own joint
  indices RAW (`ret.joints[dst] = joints[src] + 2`, gltf_util.cpp:164), indexing the
  jak1 target's bone array directly → REQUIRES matching joint order.
- Per-node GLB `extras` flags matter: `set_invisible`, `enable_custom_weights`,
  `copy_eye_draws`, `copy_mod_draws` (merc_replacement.cpp:30-41). Jak/Daxter have
  eyes + mod (breakable) draws — set `copy_eye_draws=1` to preserve jak1 eye rendering
  since the highres GLB won't carry jak1's eye-draw effect.

Format expected: **binary glTF (.glb)**, TRIANGLES only
(ASSERT `prim.mode == TINYGLTF_MODE_TRIANGLES`), one skin per actor
(`find_single_skin` dies on multiple skins), attributes POSITION/NORMAL/COLOR_0
optional/TEXCOORD + optional JOINTS_0/WEIGHTS_0. Example scaffolds live at
`custom_assets/jak1/models/custom_levels/test-actor.glb` and
`custom_assets/jak1/levels/test-zone/test-zone2.glb`.

## Recommended low-risk path

Use the **weight-borrow fallback** (GLB WITHOUT a custom skin): export each jak2
highres mesh, strip its skin, drop it in as `sidekick-lod0-mg.glb` etc. The importer
re-skins it to the jak1 rig via `find_closest`. This sidesteps the joint-order problem
entirely and animates on jak1's existing skeleton — at the cost of proximity-mapping
artifacts on parts far from any jak1 vertex (fingers, hair, mole). Only escalate to a
full name-based rig remap (custom skin + `enable_custom_weights`) if artifacts are bad.

## Open risks (biggest first)

1. **No name-based joint remap in the pipeline.** Any custom-skin GLB must have its
   skin joints reordered to match the jak1 target's exact bone index order, which is
   NOT statically known for the player. The safe fallback (weight-borrow) trades
   fidelity for animation correctness.
2. **jak1 player (`jakc`) joint count/skeleton UNKNOWN from the checked-in dumps** —
   must be resolved first (dump_joint_geo_info on all objects, or read hero art file).
   Everything about the flagship Jak swap hinges on this.
3. **Joint-count mismatch on every character** (49≠62, 78≠80/58, 96≠95) ⇒ zero
   direct fits; each needs a Blender remap or the borrow fallback.
4. **Eye/mod draws**: Jak+Daxter need `copy_eye_draws`/`copy_mod_draws` extras or eyes
   vanish / breakable-mesh (mod) logic breaks.
5. **This whole path is DESKTOP/x86 decompiler + asset build.** The Android port ships
   a curated renderer subset; the merc-replacement produces standard FR3/merc data so
   it *should* ride the existing arm64 merc path, but that must be verified on-device —
   a highres model is far more vertices/bones than jak1 low-poly and may hit arm64
   merc/bone limits (max_bones, blend-shape) the port hasn't stressed.
