## WORK ECONOMY (manager/worker delegation)
MANAGER: plan, decide, VERIFY subagent claims yourself. Delegate bulk work; never delegate understanding.

# Phase Grecharged-grass-overhang3 — ROUND 3. Round 2 = owner verdict "failure totale". THINK FIRST.

## Owner verdict on round 2 (2026-07-13 21:40, verbatim — the acceptance list, HIS eye is the gate)
"Alors ça suit pas du tout le mesh où il y a la texture d'overhang, ça suit même pas le relief du sol
d'où c'est censé faire l'overhang (on a de ton overhang qui sort littéralement de la paroi en dessous
du sol duquel c'est censé pendre) ça me rappelle le début de l'herbe où on n'arrivait pas à faire suivre
la bordure des plateformes (et j'aurais pensé qu'on aurait pu s'appuyer là-dessus un peu, au moins pour
le dégradé herbe -> overhang)... D'ailleurs on voit aucune notion de progression/transition entre
l'herbe et l'overhang ! Et c'est toujours beaucoup trop long, bien plus long que la texture d'overhang
que c'est censé recouvrir (et ça a d'ailleurs l'air d'être une herbe beaucoup plus longue que l'herbe
des plateformes dont c'est censé être issu, c'est pas logique). Bref c'est une failure totale pour moi."

## WHY round 2 failed (structural, not tuning)
Round 2 planted droop on the round#15 "excluded lip tris" set and extruded blades DOWN by a world-space
constant (u_droop_len). That set contains wall/skirt faces below the walkable floor -> blades sprout
from walls under the lip; the drop length ignores the fringe texture's actual extent; and the gradient
was invisible because the droop population is disjoint from the walkable-top population instead of
CONTINUOUS with it. Tuning the same design cannot fix this. Do not retry it.

## MANDATED DESIGN (write + commit a short design note BEFORE any code; then implement)
1. **Placement basis = the fringe-textured tris THEMSELVES.** The game already models where fringe
   hangs: the tris textured "bch-grassfringe" / "bch-leafyground-hang-2x1" (+ per-level variants — build
   the exact list from the fr3, same allowlist discipline as the PoC). Droop blades are placed ON those
   tris (barycentric, like the PoC does on floor tris), oriented ALONG the tri surface (following its
   slope/relief), never on untextured wall faces. That makes the droop follow the mesh + relief BY
   CONSTRUCTION — the exact thing the owner asked.
2. **Blade root at the SHARED edge with the walkable rim** (the fringe tri edge adjacent to a rim
   segment from the GLOBAL rim hash — the edge-saga data the owner explicitly told us to reuse), blades
   combed from that edge downward along the tri plane.
3. **Length from the fringe tri extent, per-tri** — a blade never extends past its host tri (i.e., never
   longer than the texture it covers). No global world-space drop constant.
4. **Blade profile = SAME species as platform grass** — same palette/width/height params as the adjacent
   walkable-top blades (they are "the same grass bending over the edge"), not a separate taller profile.
5. **Continuous gradient**: walkable-top blades within ~0.5m of the rim (u16 rim distance, already in
   the bake) lean progressively outward; the fringe-tri blades continue that arc. One continuous
   population visually. Prove it with a side view close-up sweep.
6. Fringe texture suppression near / crossfade far: keep from round 2 (it worked), but gate it on the
   SAME fringe-tri set as placement so suppression and droop are geometrically coherent.

## Verify (device eae4df44) — captures MUST include round-2's failure modes
(a) WIDE side/below vantage showing a lip + the wall under it: NO blade sprouting from the wall below
    the floor; (b) close-up: droop hugs the fringe mesh relief; (c) length comparison vs the ORIGINAL
    fringe texture at the same spot (toggle OFF/ON pair): same visual extent; (d) side sweep showing the
    continuous upright->lean->droop gradient; (e) blade scale visibly == adjacent platform grass;
    (f) OFF == stock incl. fringe texture. Re-bake if schema changes + bundle re-hash + deploy_verify +
    deploy_verify_assets. Force-stop after every device window. x86 untouched.

## Report: .autoport/reports/Grecharged-grass-overhang3/report.txt, RESULT: line, honest residuals.
AWAITING OWNER PLAY-TEST — his verbatim above is the checklist. Max: max_turns 3000, max_retries 6.
