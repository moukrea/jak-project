# Grecharged-grass-overhang6 — device captures (Redmi eae4df44, org.opengoal.gk.jak1)

Harness: `.autoport/goverhang6_capture.sh` (adapted from proven goverhang5_capture.sh).
Per-run focus verified DURING recording; census grepped with `grep -a`. Frames fps=2.
All 5 runs booted first-try (no retries). Feature toggle: `recharged-grass-overhang?`.
SCANPROOF also flips `recharged-grass-precomputed?` (restored to #t afterward).

Expected census: lean_tagged=65842 lean_twins=65842 (band 0.90m) z2_strip=32354 z3_fall=92928

| Run | Warp pos | overhang | precomputed | frames | census seen |
|-----|----------|----------|-------------|--------|-------------|
| 1 terr_on   | -1310.2 52.8 989.0 | #t | #t | 20 | MATCH (z2=32354) |
| 2 terr_off  | -1310.2 52.8 989.0 | #f | #t | 20 | MATCH (z2=32354) |
| 3 edge_on   | -1324.5 52.2 973.9 | #t | #t | 24 | MATCH (z2=32354) |
| 4 edge_off  | -1324.5 52.2 973.9 | #f | #t | 24 | MATCH (z2=32354) |
| 5 scanproof | -1310.2 52.8 989.0 | #t | #f (LIVE) | 20 | z2=32355 (live +1) |

## Census lines seen (verbatim, grep -a)
Runs 1-4 (identical): 
  GOVERHANG6 zones: lean_tagged=65842 lean_twins=65842 (band 0.90m) z2_strip=32354 z3_fall=92928 (layers=2) comb_repl=452 curl_blades=2048 curl_tilt0=1871 plane_capped=7953 plane_dropped=1108
Run 5 scanproof:
  GOVERHANG6 zones: lean_tagged=65842 lean_twins=65842 (band 0.90m) z2_strip=32355 z3_fall=92928 (layers=2) comb_repl=452 curl_blades=2048 curl_tilt0=1871 plane_capped=7953 plane_dropped=1108
  PLACE-TIME mode=live total=12667ms ... instances=807958
  GOVERHANG5 rim-drape: 1989 true-rim edge segments collected (drape roots)

## Focus proof (mCurrentFocus during each recording, verbatim)
1 terr_on:   mCurrentFocus=Window{e2cbd0f u0 org.opengoal.gk.jak1/org.opengoal.gk.MainActivity}
2 terr_off:  mCurrentFocus=Window{5f1605  u0 org.opengoal.gk.jak1/org.opengoal.gk.MainActivity}
3 edge_on:   mCurrentFocus=Window{103f69d u0 org.opengoal.gk.jak1/org.opengoal.gk.MainActivity}
4 edge_off:  mCurrentFocus=Window{eb20dfd u0 org.opengoal.gk.jak1/org.opengoal.gk.MainActivity}
5 scanproof: mCurrentFocus=Window{82a13a7 u0 org.opengoal.gk.jak1/org.opengoal.gk.MainActivity}

## End-state hygiene (owner defaults)
warp / warp.pos props cleared (empty); cpad_inject=neutral; app force-stopped.
EXT + INT pc-settings: recharged-grass-overhang? #t, recharged-grass-precomputed? #t.
