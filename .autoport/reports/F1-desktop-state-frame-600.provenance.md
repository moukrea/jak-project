# F1 desktop oracle — provenance

Desktop x86 reference for the F1 (Geyser Rock) game-state match.

- Captured by `.autoport/f1_x86_dump.sh`: boots `build-x86/game/gk`, connects
  `goalc` over the GOAL listener, `(lt)` + `(build-game)`, then warps to the
  NEW-GAME continue **"game-start"** (level `'training` = Geyser Rock) via
  `(start 'play (get-continue-by-name *game-info* "game-start"))`, and polls
  `(-> *target* control trans)` once/sec while the body settles.
- Settled position (42 identical samples, raw in `F1-desktop-state-raw.txt`):
  - `target_trans = x=-5393129.0  y=28317.4628  z=4362849.5`
  - `current-continue name = "training-start"`
- The comparable oracle is `F1-desktop-state-frame-600.json` (position-only, so the
  validator's recursive key-walk compares exactly the device-reproducible state).
  `_provenance`/`continue` were moved here so the comparator does not demand the
  device dump replicate prose/string keys it cannot produce from the C++ probe.
- The device dump (`F1-state-frame-600.json`) reads the **same GOAL field**
  `(-> *target* control trans)` via a property-armed C++ probe in `Merc2.cpp`
  (env `OG_F1_CENSUS` / prop `debug.opengoal.f1.census`), cross-validated on x86 to
  agree with this listener oracle bit-for-bit before trusting it on device.
