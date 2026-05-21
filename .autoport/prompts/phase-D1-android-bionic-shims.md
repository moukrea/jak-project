# Phase D1-android-bionic-shims — Bionic shims: every glibc symbol gk uses has a real Bionic implementation or wrapper

## Status

**Placeholder.** The supervisor has not yet authored this phase. When
the orchestrator reaches it, the supervisor (a separate Claude Code
session at .autoport/SUPERVISOR_PROMPT.md) must write the real prompt
and validator before any orchestrator's claude session runs.

## Bucket

D — Android port (REDESIGN.md §8).

## Goal

Bionic shims: every glibc symbol gk uses has a real Bionic implementation or wrapper

## Reality check (to be authored)

The validator at `.autoport/validators/phase-D1-android-bionic-shims.sh` is currently a
placeholder that exits 1. The supervisor will replace it with a
trace-diff against `.autoport/oracle/` at the appropriate boot
milestone, plus any per-bucket reality checks (symbol-table diff,
function-body-size sanity, qemu execute parity, screencap phash, GOAL
VM listener probe — see SUPERVISOR_PROMPT.md "Reality check toolkit").
