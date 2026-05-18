# .autoport — autonomous Android port orchestration

This directory contains the supervised loop that drives the OpenGOAL → Android port using Claude Code (Opus 4.7 at max thinking effort).

## Files

```
orchestrator.py       Main supervisor. Runs forever. Manages phases, rate
                      limits, retries, git commits, notifications.
milestones.yaml       Phase plan. Edit max_turns / max_retries here.
settings.json         Claude Code hooks config (symlinked from .claude/).
state.json            Runtime state. Gitignored. Edit by hand to unblock.

hooks/
  session-start.sh    Injects current phase context into Claude.
  pre-tool.sh         Aborts tool calls if rate limit critical.
  stop.sh             Runs validator; refuses to let Claude stop until it
                      passes. THIS IS THE RALPH LOOP.
  session-end.sh      Snapshots git state for post-mortem.

lib/
  check_limits.sh     Manual rate-limit probe (run any time).
  notify.sh           ntfy.sh / Slack notification dispatcher.

prompts/
  phase-NN-*.md       One prompt per milestone. Read carefully before
                      tuning — they encode the work plan.

validators/
  phase-NN-*.sh       One validator per milestone. Ground-truth oracle.
                      Must exit 0 for the phase to be considered done.

logs/
  orchestrator.log    Top-level orchestrator output (tee'd from tmux).
  <phase-id>/
    attempt-NN.jsonl  Per-attempt stream of Claude Code events.
    validator-NN.txt  Per-attempt validator output.
  session-end.log     Per-session git snapshots.
```

## Hardcoded design choices

The orchestrator was deliberately built with these non-negotiables (search for "Hardcoded" in orchestrator.py):

- **Model:** `claude-opus-4-7` for every phase. No Sonnet fallback. If the weekly quota is exhausted, the orchestrator waits for the actual reset timestamp returned by the API — it does NOT downgrade to Sonnet.
- **Thinking effort:** `max`, via `CLAUDE_EFFORT=max` env var + the `ultrathink` keyword prepended to every prompt.
- **Permissions:** `--dangerously-skip-permissions`. No allowlist. Claude can use any tool freely. The safety net is per-phase git commits: anything destructive is one `git revert` away.
- **Reset timing:** the orchestrator uses the exact `resets_at` ISO timestamp from the API. There is no hardcoded weekly boundary (no assumption of Monday or any other day).
- **Execution:** foreground via `./launch.sh`, tee'd to log. No tmux dependency. Detach with nohup/tmux/screen if you want.

## State management

`state.json` is the source of truth between orchestrator restarts:

```json
{
  "current_phase_idx": 4,
  "retries": {"04-controlflow": 7},
  "fingerprints": {"04-controlflow": ["a1b2c3...", "a1b2c3...", "d4e5f6..."]},
  "completed": ["00-harness", "01-scaffold", "02-intarith", "03-memops"],
  "blocked": [],
  "stuck_reasons": {},
  "started_at": "2026-05-18T...",
  "last_update": "2026-05-18T..."
}
```

The orchestrator records:
- `retries` — attempt count per phase
- `fingerprints` — one hash per failed attempt, used by stuck-detection
- `completed` — phases that passed their validator
- `blocked` — phases that gave up (either max_retries OR stuck)
- `stuck_reasons` — human-readable explanation when a phase was marked stuck

## Stuck detection

The orchestrator hashes every validator failure into a 12-character fingerprint that ignores noise (timestamps, paths, addresses) but captures the failure mode. If the same fingerprint appears **3 attempts in a row**, the agent isn't learning from feedback — the orchestrator halts honestly rather than burning through your weekly quota.

When stuck:
- Loud red panel printed in the terminal with the recurring error lines
- ntfy notification sent with the last 5 error lines
- Phase added to `blocked`, reason saved to `stuck_reasons[phase_id]`
- Orchestrator exits

What stuck means in practice:
- Compiler errors at the same line, same message, 3 attempts running
- Same test failing the same way 3 attempts running
- Validator dying with the same exception 3 attempts running

What is NOT stuck (and will keep iterating):
- Attempt 1 fails at compile, attempt 2 compiles but fails linking, attempt 3 links but tests fail — these are 3 different fingerprints, real progress
- Same kind of error but at a different line/file — different fingerprint
- Test getting closer to passing (different output → different fingerprint)

Stuck-detection threshold is tunable: `STUCK_REPEAT_THRESHOLD` at the top of orchestrator.py.

## Unblocking a stuck or exhausted phase

1. Read `logs/<phase-id>/validator-NN.txt` to understand the failure.
2. Read `state.json` to see if it was "stuck" (`stuck_reasons[<phase-id>]`) or "max_retries exhausted".
3. Fix the underlying issue, then either:
   - **Reset for retry:** remove the phase id from `blocked`, clear `retries[<phase-id>]` to 0, clear `fingerprints[<phase-id>]` to `[]`, restart orchestrator. It'll re-run from scratch with a clean slate.
   - **Mark as done manually:** if you did the work yourself, add the phase id to `completed`, increment `current_phase_idx`, restart.

Stuck-detection false positives can happen if the validator itself is broken (always fails the same way regardless of code). Fix the validator, then reset and retry.

## Tuning

- **More aggressive retries on a flaky phase:** bump `max_retries` in milestones.yaml.
- **Cheaper phases:** lower `max_turns` (especially for phase 11 which doesn't need 250).
- **Tighter rate-limit margin:** edit the constants at the top of orchestrator.py (`SESSION_PAUSE_PCT`, `WEEKLY_PAUSE_PCT`, `RESET_BUFFER_SECONDS`).

## Telemetry

The orchestrator emits structured events to `logs/<phase>/attempt-NN.jsonl`. You can post-process these with `jq` to compute per-phase token usage, time-to-pass, retry distributions, etc.

## Notification taxonomy

The orchestrator sends notifications at different priority levels so your phone doesn't beep for routine progress:

| Event | Level | ntfy priority | Sound on phone |
|---|---|---|---|
| Phase starting | info | 2 (min) | Silent — just appears |
| Heartbeat every 3rd retry | info | 2 (min) | Silent |
| Rate-limit session pause | info | 2 (min) | Silent |
| Resume after pause | info | 2 (min) | Silent |
| Phase complete | ok | 3 (default) | Soft notification |
| Weekly rate-limit pause | warn | 4 (high) | Vibrate |
| STUCK or BLOCKED | alert | 5 (urgent) | Wakes phone |
| All phases done | celebrate | 5 (urgent) | Celebration |

Typical run notification volume: roughly 4–10 per phase, distributed over hours. You'll see "▶ phase X starting", maybe 1–2 "still iterating" heartbeats, "✓ phase X done in 2h15m (4 attempts)". Once or twice a day you might see a session-limit pause and resume pair. The only sounds that should actively interrupt you are weekly limits, stuck/blocked alerts, and the final celebration.

To customize: edit `.autoport/lib/notify.sh` (`PRIORITY=` and `TAGS=` lines per level).

## Failure modes we've thought about

| Failure | Behavior |
|---|---|
| Rate limit hit mid-phase | PreToolUse hook aborts cleanly; orchestrator catches early stop, waits for reset, re-runs attempt |
| Same failure 3 attempts in a row | Stuck-detection halts honestly with the recurring error lines. Saves your quota. |
| Validator passes but is wrong (false positive) | Caught when a later phase that depends on this fails. The retry loop will discover the issue. Strengthen the earlier validator and re-run. |
| Claude stops claiming success when validator fails | Stop hook blocks the stop; Claude must keep working. |
| Stop hook infinite loops | Claude Code sets `stop_hook_active=true` on re-entry; our stop hook detects this and allows the stop. |
| OAuth token expires | Probe fails silently; orchestrator proceeds optimistically. Next claude invocation will fail with auth error; orchestrator logs and exits. Manual refresh required. |
| Network down to api.anthropic.com | Probe fails; orchestrator proceeds optimistically (will be rate-limited by Claude Code naturally) |
| qemu-aarch64-static not installed | Phase 00 validator fails immediately with clear error |
| Disk full | Various failures; orchestrator log will show ENOSPC |
| Broken validator (false stuck) | Stuck-detection halts; user fixes validator, clears fingerprints, restarts |

## Manual controls

```bash
# Pause without losing state (in the terminal running launch.sh)
Ctrl+C            # graceful (finishes current attempt)
Ctrl+C Ctrl+C     # hard kill

# Resume (just re-run)
./launch.sh

# Check status from another terminal
jq . .autoport/state.json
.autoport/lib/check_limits.sh
tail -f .autoport/logs/orchestrator.log

# Inspect a stuck phase
ls .autoport/logs/<phase-id>/
cat .autoport/logs/<phase-id>/validator-01.txt

# If you started with nohup, find and kill the orchestrator
pgrep -af orchestrator.py
kill <PID>        # graceful
kill -9 <PID>     # hard
```
