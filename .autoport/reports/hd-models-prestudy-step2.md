# Grecharged-hd-models — Step 2: jak2 HD model extraction + skinless staging

Executes step 1 of phase Grecharged-hd-models ahead of time, per
`.autoport/reports/hd-models-prestudy.md`. Device-less, decompiler + GLB
post-processing only. No game source, build-android, android, gold, or
validators touched.

## TL;DR

All four jak1-look highres jak2 models extracted to per-actor GLB, converted to
SKINLESS drop-in replacements (weight-borrow path), renamed for jak1 merc
replacement, and staged under `recharged_assets/hd_models/`. Textures embedded.
GAP 1 (jak1 player skeleton) resolved: **`eichar-lod0-jg` = 83 joints**, so the
Jak replacement GLB is **`eichar-lod0-mg.glb`** (NOT "hero" — the prestudy's
guessed target name was wrong).

## Per-character result

| jak1 target GLB (staged) | jak1 merc / joints | jak2 donor | donor joints | tris | textures | GLB size |
|---|---|---|---|---|---|---|
| `eichar-lod0-mg.glb` (Jak) | `eichar-lod0-mg` / **83** | `jak-highres-lod0-mg` | 63 | 10 886 | 24 | 1.94 MB |
| `sidekick-lod0-mg.glb` (Daxter) | `sidekick-lod0-mg` / 49 | `daxter-highres-lod0-mg` | 62 | 9 510 | 17 | 2.13 MB |
| `geologist-lod0-mg.glb` (Samos) | `geologist-lod0-mg` / 78 | `samos-highres-lod0-mg` | 80 | 10 434 | 27 | 2.68 MB |
| `assistant-lod0-mg.glb` (Keira) | `assistant-lod0-mg` / 96 | `keira-highres-lod0-mg` | 95 | 10 808 | 28 | 2.61 MB |

Donor joint counts (63/62/80/95) match the prestudy's dumps exactly. All jak1
joint counts (eichar 83, sidekick 49, geologist 78, assistant 96) re-verified
against a fresh full-object jak1 joint dump.

## GAP 1 resolved — jak1 player skeleton

- The jak1 player character skeleton-group is `*jchar-sg*`, defined in
  `goal_src/jak1/engine/target/target-util.gc:12`: jgeo `eichar-lod0-jg`,
  merc `eichar-lod0-mg`, shadow `eichar-shadow-mg`.
- Fresh dump (`dump_joint_geo_info` + `dump_art_group_info` on ALL jak1 objects,
  incl. GAME.CGO): **`eichar-lod0-jg` = 83 joints**, art group `eichar-ag`.
- `jak-white-lod0-jg` (83) is the finalboss white-Jak variant (in `copy-gos`
  alongside robotboss/finalbosscam in `game.gp`), NOT the everyday player. The
  prestudy's "83 = hint" was numerically right but for the wrong art group;
  `eichar` is the real player and is coincidentally also 83.
- The regenerated jak1 dumps were restored to their committed state after
  reading (no diff to `decompiler/config/jak1/`).

## Extraction method

The decompiler cannot export a single actor to GLB directly; the actor merc mesh
is emitted inside a level's foreground GLB. Two jak2 cutscene DGOs, both already
registered as levels in `inputs.jsonc`, cover all four characters:

- **LJAKDAX.DGO** → `jak-highres-lod0.glb`, `daxter-highres-lod0.glb`
- **LINTCSTB.DGO** → `samos-highres-lod0.glb`, `keira-highres-lod0.glb`

Command (restrict `dgo_names` via `--config-override` so only these two levels
enter the DB; all other `levels_to_extract` entries then skip cleanly — this
avoids the bsp-header ASSERT that fires when `allowed_objects` starves an
unrelated level like ATE.DGO):

```
./build/decompiler/decompiler decompiler/config/jak2/jak2_config.jsonc iso_data/ <out> \
  --config-override '{
    "rip_levels": true, "levels_extract": true,
    "extract_collision": false, "save_texture_pngs": false, "dump_objs": false,
    "process_tpages": false, "process_game_text": false,
    "process_game_count": false, "process_part_group_table": false,
    "dgo_names": ["CGO/KERNEL.CGO","CGO/GAME.CGO","DGO/LJAKDAX.DGO","DGO/LINTCSTB.DGO"]
  }'
```

Output: `decompiler_out/jak2/levels/{ljakdax,lintcstb}/*-lod0.glb` (gitignored;
removed after conversion). Each is a clean single-mesh, single-skin, TRIANGLES
GLB with embedded data-URI PNG textures.

## Skinless conversion method (weight-borrow path)

Per the prestudy's recommended low-risk path and the importer code
(`merc_replacement.cpp` / `gltf_util.cpp`): a GLB with NO skin and no
`enable_custom_weights` node-extra takes the `find_closest` branch, re-skinning
the highres mesh onto the jak1 rig by spatial proximity. So the conversion
strips the skin/joints and relies on the importer to reweight.

Conversion (pygltflib + numpy, `/tmp/convert2.py`), per model:
1. Decode all buffers — the ripped GLB uses ~191 separate data-URI buffers (one
   per accessor), so each accessor is read from *its own* buffer, not the GLB
   binary chunk.
2. Remove the `skin`, detach skeleton child nodes, drop the `JOINTS_0` /
   `WEIGHTS_0` primitive attributes, empty `skins`, reduce the scene to the
   single mesh node.
3. **Add a `NORMAL` attribute** (area-weighted smooth vertex normals from all
   primitives; degenerate/unreferenced verts get a (0,1,0) fallback so every
   normal is unit-length). This is REQUIRED: the merc importer calls
   `gltf_vertices(..., get_normals=true)` and then dereferences `in.normals.at(i)`
   in `merc_convert_replacement`; the raw ripped merc GLB carries NO normals, so
   a direct re-import would throw. Generating normals closes that gap.
4. Keep materials + textures as embedded data-URI PNGs.

Verified per file: `skins=0`, no residual `JOINTS_0`/`WEIGHTS_0`, `NORMAL`
present and unit-length on all referenced verts, TRIANGLES mode, materials →
textures → images all resolvable and embedded.

Import-path sanity check (static): `find_single_skin` returns nullopt on a
skinless GLB (no crash); `has_custom_weights` stays false; the no-JOINTS_0
branch fills dummy joint data; `merc_convert_replacement` runs `find_closest`.
The staged GLBs are import-ready for the weight-borrow flow.

## Staging location

`recharged_assets/hd_models/` (staging only — NOT yet copied into
`custom_assets/jak1/merc_replacements/`). Total 9 MB.

## Blockers / follow-ups (not blocking staging)

1. **Weight-borrow fidelity.** Proximity reskin will produce artifacts on parts
   far from any jak1 vertex (fingers, hair, Daxter's mole/tail, Samos' staff).
   Escalate to a name-based rig remap (custom skin + `enable_custom_weights`,
   joints reordered to the jak1 target order) only if artifacts are bad. Joint
   counts differ on every character (63/62/80/95 donor vs 83/49/78/96 target),
   so a custom-skin path is non-trivial and needs a Blender remap.
2. **Eye / mod (breakable) draws.** Jak + Daxter jak1 models have eye-draw and
   mod-draw effects the highres GLB won't carry. Per the prestudy, set
   `copy_eye_draws=1` (and `copy_mod_draws=1` where relevant) as node `extras`
   on the GLB, or eyes vanish / breakable-mesh logic breaks. These extras are
   NOT set on the current staged GLBs and should be added when the model is
   promoted into `custom_assets`.
3. **Android/arm64 vertex+bone budget.** A highres model is far more
   vertices/bones than jak1 low-poly. This whole path is desktop/x86 decompiler
   + asset build; the on-device arm64 merc path (max_bones, blend-shape) has not
   been stressed with a model this size and must be verified on-device at
   integration time.
4. **Generated normals are synthetic.** The originals ship without per-vertex
   normals (the merc renderer computes lighting differently); the smooth normals
   added here are geometry-derived. Fine for the weight-borrow import, but if
   lighting looks off, revisit.

## Disk

Net new committed disk: 9 MB (four staged GLBs + this report). Bulky decompiler
intermediates (`decompiler_out/jak2/levels`, ~584 MB) are gitignored and were
removed post-conversion. Pre-existing `decompiler_out/jak2/raw_obj` etc. (from an
earlier run, 15:08 timestamps) left untouched.
