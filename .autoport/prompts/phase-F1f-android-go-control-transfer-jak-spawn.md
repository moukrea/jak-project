# Phase F1f — fix the GOAL control-transfer/spool walls: cinematic completes → Jak SPAWNS and MOVES

## Where we are (read F1d-fix-summary.md §5-§9 first — it is honest and precise)

F1d delivered: injected input drives the FULL menu flow (title→menu→savefile→
continue / new game confirm genuinely fires: `Discarding level village1`,
`Adding level intro`, `Displaying level misty [display]`, STR spool streams);
fr3 assets blocker fixed; Adreno vertex-BO first-draw-after-load fault
mitigated (map + load-completion glFinish — NOT eliminated, see run12); F1e's
reveal crash stays dead. **But Jak NEVER spawned**: post-confirm the app dies
~15s in, target-pos telemetry ends `(nan nan nan)`. Both legitimate roads end
at deterministic, NAMED crashes (F1d-fix-summary §7a/§7b):

- **§7a NEW GAME road — spool joint-anim linking + a `go` that RETURNS.**
  Seconds into `sidekick-human-intro-sequence-b`: chronic `could not find a
  master slot to link/unlink for #<art-joint-anim …>` (present even for the
  title's own `logo-intro-2` spool — the subsystem is broadly unhealthy on
  Android), then a joint channel's `frame-group` fails the `art-joint-anim`
  type check in `evaluate-joint-control` (goal_src .../process-drawable.gc:620)
  and `(go process-drawable-art-error "joint-anim")` **RETURNS — it must never
  return**. A `go` is a non-local state transfer; on arm64 it falls through.
  This is the catch/throw/control-transfer bug family (A26/A27 era) resurfacing
  in the state-machine path. TWO bugs: (1) master-slot spool linking broken,
  (2) the compiled `go` control transfer returns instead of transferring.
- **§7b LOAD GAME road — restore dies in a corrupt control transfer (2/2).**
  Same family, second site.

## Mandate (in order)

1. **Root-cause the `go`-returns bug at the mechanism.** `goal_src/**` is
   LOCKED — the .gc code is correct (it works on x86/PS2); the defect is in
   how arm64 compiles/executes the non-local transfer (goalc arm64 codegen,
   the throw/catch-frame machinery, kscheme/klink runtime, or the stack/RA
   contract for state transitions — see A26/A27 reports for the catch-frame
   chain infrastructure). Oracle-compare the compiled `go` path x86 vs arm64
   (the A-phase method: disasm diff, break-trap, chain dump). Fix so a `go`
   GENUINELY transfers control. This likely also fixes §7b — verify both roads.
2. **Fix or root-cause the master-slot spool linking** (`could not find a
   master slot to link/unlink`). It fires even on the title's own spool, so it
   reproduces in seconds without menu navigation — use that repro. Determine
   whether it shares a root cause with bug 1 (a `go`/transfer fallout) or is
   independent (e.g. a search/compare codegen defect); fix what is provably
   broken, name what is not.
3. **Drive the flow**: injected START → new game confirm → intro cinematic
   (blackout then misty spool — let it play or skip via the game's own input
   path; NO state-machine bypass) → training/Geyser loads → **target (Jak)
   spawns with a REAL position (never `nan`)** → inject stick/D-pad movement →
   **target-pos CHANGES across many frames**, correlated with the injected
   events in the same logcat timeline. The LOAD GAME road (GEYSER ROCK save)
   is an equally valid path to a spawned Jak — pursue both, ship whichever
   genuinely works, document the other.
4. **Captures** at each transition with `mCurrentFocus` brackets; label frames
   by VERIFIED content only (F1d's run11 "spawn/move" frames were the MIUI
   launcher — never again). Reversible app disables, guaranteed RE-ENABLE.
5. **`F1f-fix-summary.md`** (≥80 lines): the `go` mechanism root cause +
   oracle evidence, the spool-linking verdict, both-roads outcome, the
   spawn+movement evidence timeline (target-pos values quoted), residuals.

## Owner live repro (2026-06-13, supervisor-added)

The owner reproduced the post-confirm death with PHYSICAL input: NEW GAME →
save-slot picker → slot 1 (occupied) → overwrite prompt (default NO) →
select YES → **instant crash**. This proves the §7a wall is input-method-
independent (NOT an injection artifact) and gives a second repro variant:
occupied-slot + overwrite-YES (perceived instant) vs fresh-slot confirm
(~15s with blackout). Compare both paths' logcat tails — if the overwrite
path dies faster/differently, that divergence is diagnostic.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`,
`.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`,
`.claude/agents/**`, other phase prompts. x86 boots to `link finish: logo`;
qemu ≥ 675; x86 CGOs byte-identical; if any CGO changes, regen + sync ALL 28
to APK assets. Preserve ALL prior fixes (F1c modulo/MSUB, F1e Adreno sync,
F1d bridge + fr3 + vertex-BO). NO faked telemetry: a hardcoded/synthetic
target-pos is a cheat; the validator requires MANY DISTINCT non-nan positions
and the supervisor cross-checks frames by pixels. `export ANDROID_SERIAL=eae4df44`
only; keyguard check; pgrep leftover run scripts before device runs.

## Validator (`phase-F1f-android-go-control-transfer-jak-spawn.sh`) — STRICT, hardened

The F1d validator was satisfied by BOOT-TIME attract telemetry (master-mode
'game + a static target at f=15). This one is not satisfiable that way. PASS
requires: real **`F1f-fix-summary.md`** (≥80 lines, must reference the `go` /
control-transfer mechanism AND `master slot`/`evaluate-joint-control`) PLUS
newest `F1f-routed-logcat-*.log` with ZERO `sig=11`, **≥ 10 DISTINCT non-nan
`F1D target-pos` values**, a **non-nan LAST target-pos**, frame ≥ 300,
tris > 0, PLUS newest `F1f-focus-*.txt` ending on `org.opengoal.gk.jak1`.
Plus standard gates (locks, anti-cheat, x86 smoke, qemu ≥ 675, gk_log_pipe,
nm renderer syms, ≥1 `F1f-device-*.png`). Whether a frame shows Jak IN a level
is judged by the supervisor's own eyes.

## Max settings

`max_turns: 2000`, `max_retries: 3`.

## Strategic note

Fourteen bug classes down. The menu works, the cinematic streams, the build is
stable — the last wall between here and a playable Jak is a `go` that falls
through on arm64. That is a compiled-control-transfer defect with a
seconds-fast repro (the title's own spool errors) and a full A26/A27 forensic
toolkit already in the tree. Make `go` transfer, watch the cinematic hand off
to the level, and put Jak's feet on Geyser Rock.
