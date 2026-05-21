# Phase C2-linux-arm64-symbols — Resolve glibc + dynamic symbol issues so gk dlopens cleanly

## Status

**Placeholder.** The supervisor has not yet authored this phase. When
the orchestrator reaches it, the supervisor (a separate Claude Code
session at .autoport/SUPERVISOR_PROMPT.md) must write the real prompt
and validator before any orchestrator's claude session runs.

## Bucket

C — Linux-arm64 first (REDESIGN.md §8).

## Goal

Resolve glibc + dynamic symbol issues so gk dlopens cleanly

## Reality check (to be authored)

The validator at `.autoport/validators/phase-C2-linux-arm64-symbols.sh` is currently a
placeholder that exits 1. The supervisor will replace it with a
trace-diff against `.autoport/oracle/` at the appropriate boot
milestone, plus any per-bucket reality checks (symbol-table diff,
function-body-size sanity, qemu execute parity, screencap phash, GOAL
VM listener probe — see SUPERVISOR_PROMPT.md "Reality check toolkit").
