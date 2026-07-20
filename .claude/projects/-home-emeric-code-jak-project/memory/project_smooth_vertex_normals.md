---
name: project_smooth_vertex_normals
description: Smooth per-vertex normal reconstruction for the static world (directional-ambient root-cause fix) — DONE + proven at normal level, but render-subtle on dense meshes; shadowed-wall form needs directional GI/SSDO next.
metadata:
  type: project
---

Phase Grecharged-directional-ambient, DEFINITIVE mandate (smooth normals). SHIPPED + [Gda PASS] +
device-proven 2026-07-20 (commit 3f3ee2de2), owner eye-gate pending.

ROOT CAUSE (confirmed in code): static tfrag (tfrag3.vert) has NO per-vertex normal (pos/uv/tod only)
→ realtime shaders synthesized a FLAT per-face `cross(dFdx,dFdy)` normal → faceted/flat on curves.
TIE **already** ships real authored normals (PackedTieVertices nx/ny/nz → unpack_tie_normal → the
2-10-10-10 `nor` field, world-space) and Tie3.cpp **already binds nor at VAO location 3** — but
etie_base/tie_wind BASE shaders threw it away for the flat dFdx. Actors (merc2.vert normal_in) already
smooth (Gouraud) — never flat. Shrub has no normal field (ShrubGpuVertex full, loc3=tod) → left flat.

THE FIX (9 files): `reconstruct_tfrag_smooth_normals()` in TFrag3Data.cpp `TfragTree::unpack()` —
area-weighted face-normal accumulation, welded by exact packed pos (cluster<<48|xoff<<32|yoff<<16|zoff),
strip-parity aware, packed via `pack_to_gl_normal` (unit×511) into `nor`; runs at level-load (loader
thread), inert unless read. TFragment.cpp binds loc-3 nor on the tfrag VAO. tfrag3/etie_base/tie_wind
{vert,frag}: `v_normal` varying; rt path uses the interpolated SMOOTH normal for sun N.L + hemisphere/
SH/IBL, **aligned to the per-face geometric sign** (`dot(Ns,gN)<0?-Ns:Ns`) so reconstruction global
winding is IRRELEVANT and the `Nsl2<=0.2` fallback == old flat behaviour (worst case = stock).
background_common.cpp: `debug.opengoal.rt.flatnormal` / `u_rt_flat_normal` = same-build A/B toggle.
OFF==stock byte-identical (all rt-gated). Build = libgk-only (`cmake --build build-android --target
gen_android_shaders` then `gk`, gradle assembleJak1Debug) — NO GOAL/CGO rebuild (no goal_src touched).
Shaders embedded in libgk via shaders_android_blob.h (preprocess.py).

**HONEST KEY FINDING (the important part):** the normals ARE now smooth on curves — debug-2 world-normal
viz (RTL_DEBUG_MODE=2, renders N*0.5+0.5) A/B is DRAMATIC (continuous gradient vs flat facets; distinct-
normals 1.26x on the hut-wall ROI). BUT the shaded RENDER smooth-vs-flat is **SUBTLE** (still_smooth_h8 ≈
still_flat_h8; wall grad 0.0034 vs 0.0035). Causes: (a) Jak meshes are moderately DENSE so per-face
normals already approximate the surface; (b) ALBEDO texture dominates luminance variance; (c) hemisphere
reads only N.y (~const on a vertical wall); (d) synthetic sky ambient (hemi/SH/IBL) is azimuthally near-
uniform → CANNOT sculpt a shadowed horizontally-curved wall. So the owner's "flat in shadow" is a **GI
problem, not a normal problem**. Smooth normals = correct + necessary FOUNDATION, not the whole answer.
**NEXT STEP for shadowed-wall form = DIRECTIONAL indirect: SSDO/SSGI** (supervisor already flagged it),
now that smooth normals exist to drive it. Smooth normals DO visibly help: raking/low-sun N.L across a
curve + vertically-curving surfaces (domes/terrain, N.y varies).

Reusable: `.autoport/gda_deploy2.sh` (install+deploy_verify+8-stage A/B) + `gda_capture.sh` (RTL_FLATNORMAL,
RTL_AMBIENTMODEL props). Supersedes the hemisphere-only story in [[project_directional_ambient]]. See
[[project_realtime_lighting_sunonly]] for the sun path this shades.
