# Phase Gcine-audit — OBJECTIVELY find what's still wrong with the new-game cinematic (no owner eye). Diagnostic only: produce a ranked, evidence-backed divergence map vs the x86 original. NO fix, NO grind.

## Why (owner, 2026-06-17)
The new-game intro cinematic no longer crashes (Gcine-crash3) and the pose-blink is fixed (Gcine-pose). The owner earlier reported residual cinematic-quality issues — camera issues, cadence, transitions between camera plans, and "water is garbage / weird green-glow lighting on the destination island" — but those were seen BEFORE the recent fixes and may have changed. The owner's directive: **"check yourself for issues, there must be a proper way to do that without me."** So: detect the remaining issues OBJECTIVELY by diffing the device cinematic against the x86 original, not by eyeballing. This is the same oracle-diff discipline as [[feedback_objective_frame_comparison]] / the Pcompare gate.

This phase ONLY measures + ranks. It does NOT fix anything (fixes come as separate single-defect phases driven by this map).

## The reference
The cinematic is deterministic GOAL script — it runs the SAME on x86 and arm64 (same scene-player, same camera keyframes, same timing), so x86 is the ground truth. x86 build: `build-x86/game/gk` (new game plays fully). Clean original source: `/home/emeric/code/jak-original-v033` (READ-ONLY). Device: arm64 `eae4df44`, running fresh HEAD (the pose+crash fixes). adb `/home/emeric/Android/platform-tools/adb`.

## Mandate — two objective tracks
1. **DATA diff (primary — deterministic, grind-free).** Instrument per-frame logging of the cinematic's *camera + scene-player* state on BOTH backends and diff them:
   - active camera / scene-player stage / current cinematic frame counter (catches CADENCE + TRANSITION-between-camera-plans bugs: when does each cut happen, in what order).
   - the math-camera transform each frame (camera position + orientation + fov/zoom; or the full camera matrix) (catches CAMERA bugs: wrong position/angle/jitter).
   - key per-frame render-bucket counts if cheap (catches gross rendering divergence).
   Run the cinematic on x86 (drive new-game; the cinematic plays headlessly) → capture log A. Run on the device via cpad_inject (verify `mCurrentFocus=org.opengoal.gk.jak1` first) → capture log B. Align by cinematic frame counter (NOT wall-clock) and diff. Each significant divergence = a concrete, located issue.
2. **PIXEL diff at matched BEATS (for rendering/lighting: water, green-glow).** Use `.autoport/lib/frame_compare.py` vs the x86 oracle at a FEW deterministic cinematic still/slow beats (e.g. a held-camera moment on the destination island). BOUNDED: a handful of beats, single PNGs, NO video/screenrecord, NO disk grind ([[feedback_objective_frame_comparison]] — grind filled the disk before; [[feedback_moving_beat_matched_phase]] for matched-phase technique). Emit the diff images + diff_frac per beat.

## Deliverable
`.autoport/reports/Gcine-audit/divergences.md` — a RANKED list of objectively-detected divergences. For each: WHAT (camera transform / cut-timing/cadence / transition order / water pixels / lighting green-glow), WHERE (cinematic frame or beat), MAGNITUDE (the metric: camera-delta, timing-delta in frames, diff_frac), and EVIDENCE (artifact paths). If a category objectively MATCHES the oracle within tolerance, say so explicitly (that category is already fine). Plus a short "method" section (what was logged, how aligned, tolerances) and a recommended fix order. Keep the raw capture logs (x86 + arm64) as artifacts.

## Rules / locks
ANDROID_SERIAL=eae4df44 only. No `goalc/emitter/IGenX86_64.*`. No code FIXES (diagnostic only — instrumentation/logging is fine but don't change cinematic behavior). No standalone boot-CGO push. Oracle repo + `.autoport/gold/` READ-ONLY. NO screenshot/video grind (bounded still-beats only). Don't touch the parked menu. Anti-fiction: every divergence MUST cite an artifact that actually exists ([[feedback_a38_report_fiction]]).

## Validator (`phase-Gcine-audit.sh`)
PASS requires: `.autoport/reports/Gcine-audit/divergences.md` (≥50 lines) with a method section + a RANKED divergence list (or explicit per-category "matches oracle" determinations) + a recommended fix order; REAL capture artifacts present and non-trivial — both an x86 capture log AND an arm64 capture log (and any cited diff images) must exist with non-zero size; the divergence entries must cite frame/beat + a metric; x86 still `link finish: logo`; no large `.mp4` (anti-grind); disk ok. (No device fix / no deploy_verify — this is a diagnostic/tooling phase.)

## Max settings
`max_turns: 1500`, `max_retries: 3`.

## Strategic note
The camera/cadence/transition issues are best caught by the DATA diff (deterministic, no pixels, no grind) — lean on that. The water/green-glow needs the bounded pixel diff. The output is an objective issue map the supervisor turns into single-defect fix phases — so be concrete and evidence-backed, not vague. If everything objectively matches the oracle, that is a valid (and great) result: say so with evidence.
