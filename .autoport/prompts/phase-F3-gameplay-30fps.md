# Phase F3-gameplay-30fps — 30 FPS sustained on the Redmi Note 9 Pro for 60s of gameplay

## Status

**Placeholder.** The supervisor has not yet authored this phase. When
the orchestrator reaches it, the supervisor (a separate Claude Code
session at .autoport/SUPERVISOR_PROMPT.md) must write the real prompt
and validator before any orchestrator's claude session runs.

## Bucket

F — Stretch gameplay (REDESIGN.md §8).

## Goal

30 FPS sustained on the Redmi Note 9 Pro for 60s of gameplay

## Reality check (to be authored)

The validator at `.autoport/validators/phase-F3-gameplay-30fps.sh` is currently a
placeholder that exits 1. The supervisor will replace it with a
trace-diff against `.autoport/oracle/` at the appropriate boot
milestone, plus any per-bucket reality checks (symbol-table diff,
function-body-size sanity, qemu execute parity, screencap phash, GOAL
VM listener probe — see SUPERVISOR_PROMPT.md "Reality check toolkit").
