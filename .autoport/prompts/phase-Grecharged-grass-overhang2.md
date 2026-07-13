## WORK ECONOMY (manager/worker delegation)
MANAGER: plan, decide, VERIFY subagent claims yourself. Delegate to autoport-researcher (code/shader
scans), autoport-implementer (edits to spec), autoport-tester (device runs, captures). Parallelize.

# Phase Grecharged-grass-overhang2 — ROUND 2: owner HONOR play-test FAILED round 1

## Owner verdict (2026-07-13 19:45, verbatim — HIS eye is the gate)
"Alors ça recouvre pas la texture d'overhang (ça passe au travers et on a toujours la texture
d'overhang visible au lieu qu'elle soit recouverte) puis ça descend beaucoup trop bas et en plus
c'est pas progressif entre l'herbe droite et l'herbe d'overhang"

THREE defects, all must be fixed:
1. **The original overhang ALPHA texture (grass-fringe) is still visible** — droop blades pass through
   it instead of COVERING/REPLACING it. The design intent (phase 1 spec) was: near = 3D droop REPLACES
   the alpha texture; far = alpha texture only. So NEAR the lip, the game's fringe texture must be
   suppressed/faded out (find where the fringe/overhang alpha quads are drawn — tfrag/TIE alpha pass —
   and gate them by the same near-distance used for droop, crossfaded), not drawn under/through the
   droop blades.
2. **Droop descends much too low** — shorten the droop drop distance substantially (blades should drape
   the lip like a fringe, not curtains hanging low). Make the drop length a tunable (code var + debug
   prop), pick a default that reads like the original texture's visual length.
3. **No progressive transition** between upright grass on the walkable top and drooping blades at the
   lip — blend must be gradual: blades near the rim edge should lean progressively outward/downward as
   a function of rim distance (reuse the u16 quantized rim distance already in the bake/runtime),
   not a binary upright-vs-droop switch.

## Constraints (unchanged from round 1)
Edge stack LOCKED (FLOORBELOW/FLOORGAP/global rim hash untouched); walkable-top placement unchanged;
toggle in Grass Settings; OFF == stock INCLUDING the fringe texture (suppression only when droop ON and
near); precomputed mode must keep working (re-bake if the bake schema changes + bundle re-hash);
device eae4df44 only; force-stop after every device window; deploy_verify + deploy_verify_assets before
any claim; A/B frames same-vantage ON/OFF + close-up of the lip; x86 untouched.

## Verify
Same-vantage captures proving: (a) no double texture (fringe hidden under droop near), (b) droop length
visually matched to original fringe length, (c) progressive lean gradient approaching the lip visible in
a close-up sweep. OFF == stock byte-path. Report to .autoport/reports/Grecharged-grass-overhang2/report.txt
with RESULT: line. AWAITING OWNER PLAY-TEST at the end (his three complaints are the acceptance list).

## DEVICE HYGIENE: ALWAYS force-stop org.opengoal.gk.jak1 when a device window ends.
