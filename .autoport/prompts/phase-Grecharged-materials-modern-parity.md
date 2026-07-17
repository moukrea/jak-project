# Phase Grecharged-materials-modern-parity — modern-engine material parity (BACKLOG, re-scope at start)

## Owner intent (2026-07-17)
"Faut que ce soit raccord avec ce que font de mieux les game engines modernes pour qu'on puisse s'en
rapprocher niveau matériaux — p't'être une évolution quand on aura nail le PBR générique que t'as l'air de
mettre en place, donc dans le backlog."

## Precondition
Do NOT start until Grecharged-pbr-materials is owner-validated: robust tfrag/tie tangents, each PBR channel
(normal/roughness/metal/AO) VISIBLY contributes, realtime mood-sun proven (moving highlight). This phase is
the EVOLUTION on top of that generic base.

## Scope (to be re-scoped with the owner when reached — this is a backlog placeholder)
Bring fork materials toward the modern-engine bar, flag-gated (--pbr family), per-material opt-in, OFF==stock:
- Height / DISPLACEMENT — parallax-occlusion mapping (the owner explicitly wants depth, not just normals).
- SUBSURFACE SCATTERING — "scattering color" for skin/foliage/wax surfaces.
- ORM packing (occlusion+roughness+metal in one RGB) to bound memory/APK size.
- Clearcoat / anisotropy where it matters; energy-conserving multi-light; image-based ambient / light-probe
  IBL so ambient reacts to the environment, not a flat term.
- Tone/exposure calibration so PBR surfaces sit coherently next to legacy-baked neighbours across all moods.
- A reference A/B vs a modern-engine screenshot of the same material to judge "raccord".

## Delivery philosophy (inherit the pillar + PBR lessons)
Real device proof on the Redmi via the P3 custom_assets external path; per-channel debug viz; realtime clip;
OFF==stock byte-identity; honest partial beats a flat photo. Owner's eye is the final gate.

## Budget
max_turns 3500, max_retries 6. device: true, owner_verify: true. Re-scope the concrete deliverable with the
owner at phase start (owner: "je re-scope au démarrage").
