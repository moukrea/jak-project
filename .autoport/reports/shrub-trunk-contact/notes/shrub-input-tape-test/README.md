# Offline input-tape test

This links the actual `game/system/shrub_proof_inputs.cpp` against minimal proof/pad stubs.
It does not execute a game, renderer or device and is not a campaign proof.

Compile:

```
c++ -std=c++17 -I .autoport/reports/shrub-trunk-contact/notes/shrub-input-tape-test/stubs -I . .autoport/reports/shrub-trunk-contact/notes/shrub-input-tape-test/main.cpp game/system/shrub_proof_inputs.cpp -o .autoport/reports/shrub-trunk-contact/notes/shrub-input-tape-test/tape-test
```

Run with `AUTOPORT_SHRUB_INPUT_MODE=record|replay` and
`AUTOPORT_SHRUB_INPUT_PATH=/absolute/path/to/tape`. The executable argument selects
`record`, `replay`, `missing`, `preanchor-mismatch`, `bad-duplicate`, `corrupt`,
`vector-record`, or `vector-read`.

Observed results on 2026-09-15:

- record: exit 0; replay: exit 0; replay requests explicit source keys in reversed order.
- missing: SIGABRT; preanchor-mismatch: SIGABRT.
- bad-duplicate: SIGABRT (record reused a source key with different bytes).
- corrupt: SIGABRT (last tape byte removed before loading).
- vector-record: exit 0; vector-read: SIGABRT (count 1048577 exceeds allocation bound).

Each failing log includes `shrub_input_tape_errors=1` before termination.
The good run reuses one explicit key twice, changes logical frame 0 to 60, and
asserts actual restored values (11,21,22,55).

Limits: source-key events are independent of render call ordering. Ordinary
clock/contact events still preserve per-channel render ordinals and the complete
pre-anchor history. A different pre-anchor call count is rejected at the anchor;
no accumulator reset or reference-derived spring/contact output is injected.
This test establishes file/API behavior only, not cross-binary pre-anchor
alignment or camera/contact/wind equality.
