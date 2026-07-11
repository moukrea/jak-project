# Phase Grecharged-grass-object-clip — grass must not poke through ground-resting objects (jak1)

## DEPENDS ON: grass edges clean first (Grecharged-grass-poc round#15+ owner-OK). Owner called this "un détail" vs the edge.

## Owner report (2026-07-11, verbatim)
"On a encore des trucs où l'herbe (sur le sol) passe à travers, genre le bouton du gate de l'ile,
l'herbe passe au travers malgré le fait que le bouton est sur le sol, ça faut éviter, et idem pour
peut-être d'autres éléments de décors ou autre posés sur le sol (attention au fait que ça doit s'arrêter
où clip l'objet avec le sol, même si le modèle est beaucoup plus gros en-dessous du sol par exemple)...
bon ça c'est un détail."

## Root-cause hypothesis (verify first)
Round#13's per-instance object-cull only uses NON-grass-TIE object-point buckets as occluders. The
island warp-gate BUTTON (and likely other ground-resting decor) is a GAME-OBJECT / actor
(process-drawable / prototype / instance), NOT a static TIE -> it is absent from the occluder set ->
grass is not culled under it -> blades poke through. CONFIRM by dumping which occluder set the gate
button belongs to on device before fixing.

## Fix
Extend the grass object-cull occluder set to include NON-TIE ground-resting objects (game objects /
actors / prototypes / decor that sit on grass ground). A blade is culled if a real occluder surface is
within the existing contact radius.

## CRITICAL nuance (owner) — cull by the GROUND-CONTACT footprint, NOT the full mesh/bbox
Objects can extend FAR BELOW the ground (buried base, much larger under-surface model). The cull must
key on WHERE THE OBJECT CLIPS THE GROUND (its footprint at/just above the ground surface), NOT its full
mesh or bounding volume — else a small surface object with a huge buried mesh would cull a giant bald
patch. Round#13 already uses a CONTACT BAND [0.05..1.00 m ABOVE ground] which correctly ignores
under-ground geometry; keep/tune that principle for the new occluders (sample only near-ground-surface
points; ignore anything well below the local ground height).

## Scope / toggle
This is CORRECTNESS within grass-ON (no separate toggle; grass OFF == stock already). Do not regress the
open-field DROPPED=0 density or the clean edges.

## Verify (device eae4df44) — supervisor eyeballs
At the island gate BUTTON: grass no longer pokes through it (close-up before/after). Pick 1-2 other
ground-resting decor objects and confirm the same. Confirm NO giant bald patch around objects with buried
bases (the footprint-not-volume nuance). Open-field grass + clean edges NOT regressed. deploy_verify PASS.
Force-stop after tests.

## Report (.autoport/reports/Grecharged-grass-object-clip/report.txt) RESULT: GRASS OBJECT-CLIP <verdict>
which occluder set the gate button was missing from, the extension, the ground-contact-footprint handling
(no giant bald patch on buried-base objects), device before/after at the gate button + 1-2 other objects.
## Locks: ANDROID_SERIAL=eae4df44 only; engine goal_src untouched (renderer/pc layer); gold READ-ONLY.
## Max: max_turns 2400, max_retries 5. device: true, owner_verify: true.
