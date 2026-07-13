## WORK ECONOMY (manager/worker delegation)
MANAGER: plan, decide, VERIFY subagent claims yourself. Delegate bulk work; never delegate understanding.

# Phase Grecharged-grass-overhang4 — ROUND 4. Rounds 2 AND 3 failed the owner's HONOR eye. THINK, then fix.

## Owner verdict on round 3 (2026-07-14 00:15, verbatim — HIS eye is the gate)
"Par contre le grass overhang c'est loupé encore, ça clip totalement au travers du mesh là où ça fait la
transition de sol vers l'overhang au lieu de recouvrir, aucune notion de transition de l'herbe droite
vers l'herbe overhang (ou plutôt transition trop brutale et complètement ratée), le rendu fait des
bandes en diagonales chelou sur l'overhang... C'est complètement loupé !"

THREE defects:
1. **Clip-through at the floor→overhang transition**: blades pass THROUGH the curved mesh instead of
   covering it. Suspect: combed transition blades lean along a direction that crosses their host tri /
   the neighbor tri plane (comb math is not surface-constrained). Fix direction: comb along the tri's
   own down-slope TANGENT (projected gravity), offset the blade root slightly along the tri normal, and
   clamp the tip against leaving the host tri's half-space. Verify geometrically in the bake (report
   per-blade tip-vs-plane violations count -> must be ~0), not just visually.
2. **Transition still brutal/absent**: per-TRI classification (bit4) makes whole triangles flip
   behavior -> visible seams. The blend weight must be PER-BLADE and CONTINUOUS: derive from the
   blade's own rim distance + local interpolated slope (barycentric-interpolated vertex normals, not
   the face normal), so two adjacent blades never jump states. No threshold may be visible as a line.
3. **Weird DIAGONAL BANDS on the overhang**: new artifact, seen on the owner's HONOR (Adreno 8 Elite),
   NOT obvious on the Redmi captures. Two suspects to INVESTIGATE FIRST (do not guess):
   a. Deterministic hash/placement rows on long skinny fringe tris (barycentric patterns aligning
      into diagonals) — check by visualizing placement density on the bake data (offline render or
      debug color mode).
   b. PRECISION: mediump float paths in grass.vert comb/droop math behaving differently on newer
      Adreno — audit precision qualifiers, force highp on all position/weight math in the droop/comb
      branches (cheap, do it regardless).
   If the band pattern is invisible on Redmi, say so honestly and ship the highp+jitter hardening +
   per-blade continuous weights, then request an owner HONOR screenshot at gate for confirmation.

## Method requirements
- Design delta note committed BEFORE code (what changes vs round 3 and why it kills each defect).
- Geometric self-checks in the bake (tip-plane violation counter, seam detector: max neighboring-blade
  weight delta at tri borders) reported as NUMBERS in the report.
- Device evidence: close-range VIDEO sweep (screenrecord) orbiting a transition zone, extracted frames;
  same-vantage OFF pair; the round-2/3 wall wide shot must stay clean (no regression).
- Edge stack LOCKED; OFF == stock; precomputed bake re-hash + deploy_verify + assets; force-stop always.
- Owner gate: his 3 defects above are the acceptance list; ask him for an HONOR screenshot if the
  diagonal bands cannot be reproduced on the Redmi.

## Report: .autoport/reports/Grecharged-grass-overhang4/report.txt with RESULT: line + honest residuals.
Max: max_turns 3000, max_retries 6.

## OWNER ADDENDUM (2026-07-14 00:25, verbatim)
"T'auras pas le screenshot car je peux pas te le passer au travers de ce terminal. Tu dis que c'est
absent de tes captures, mais n'oublie pas que pour tout ce qui est visuel t'es complètement bidon, donc
en même temps pas étonnant que tu vois pas les loupés... Et que ce soit moi qui valide le visuel !"

=> RETRACT the "not visible on Redmi" assumption — supervisor/worker eyeballs are NOT evidence of
absence. The diagonal bands may well be IN the Redmi frames unseen. Consequences (MANDATORY):
- Build an OBJECTIVE banding detector and run it on device captures of the overhang zones: oriented-
  gradient / autocorrelation analysis over the droop pixel region (e.g. FFT peak or Hough-line energy
  at non-axis angles vs an OFF baseline at the same vantage). Report the metric ON vs OFF as NUMBERS;
  the OFF baseline defines the noise floor. Same discipline for the clip-through (geometric counters)
  and the seam (neighbor-weight delta metric).
- Never claim a visual defect absent from an eyeball read again — either a metric says it, or it is
  "unmeasured". The owner is the only visual validator.
