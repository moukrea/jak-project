# Phase C3-linux-arm64-title — Reach title under qemu-aarch64; trace-diff matches oracle through title milestone

## Status

**Placeholder.** The supervisor has not yet authored this phase. When
the orchestrator reaches it, the supervisor (a separate Claude Code
session at .autoport/SUPERVISOR_PROMPT.md) must write the real prompt
and validator before any orchestrator's claude session runs.

## Bucket

C — Linux-arm64 first (REDESIGN.md §8).

## Goal

Reach title under qemu-aarch64; trace-diff matches oracle through title milestone

## Reality check (to be authored)

The validator at `.autoport/validators/phase-C3-linux-arm64-title.sh` is currently a
placeholder that exits 1. The supervisor will replace it with a
trace-diff against `.autoport/oracle/` at the appropriate boot
milestone, plus any per-bucket reality checks (symbol-table diff,
function-body-size sanity, qemu execute parity, screencap phash, GOAL
VM listener probe — see SUPERVISOR_PROMPT.md "Reality check toolkit").
