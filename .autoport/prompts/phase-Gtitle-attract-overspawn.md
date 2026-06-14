# Phase Gtitle — remove the spurious "Press <CIRCLE> to use" over-spawn during the title attract (chronological step 2)

## Where we are

The chronological intro now renders: title flies (G1), Daxter/ND logo animates (Gnd), the SCE/ND attribution text screen draws (Gsprite). The remaining title-flythrough defect the owner reports: **a gameplay "Press <CIRCLE> to use" interaction prompt appears intermittently DURING the title attract** — it shouldn't; the attract is a pure camera flythrough. It persists on the stable build, so it's a genuine pre-existing divergence (not F1f churn).

## Ground truth (gold standard)

`.autoport/gold/pristine-boot-sequence.log` says the pristine attract holds at `target-title-play`/`target-title-wait` under master-mode `'game`, and explicitly: "**NOTHING title-only over-spawns before [the logo states]**." So on the original, no interactable actor / "use" prompt exists during attract. Our build spawns something it shouldn't — find it by diffing the attract process/actor list.

## Mandate (in order)

1. **Reproduce + capture** the "Press <CIRCLE> to use" prompt during attract on device (it's intermittent — capture across the attract loop; spool-tag frames as prior phases did).
2. **Diff the attract process/actor list vs pristine** with `.autoport/gold/compare-3tier.sh --boot` (or a direct process-list dump). The "use" prompt is raised by an interactable/`process-drawable` with a `use`/`pickup`/`button-prompt` handler that's ACTIVE during attract on Android but not pristine. Find the spurious process: is an entity/actor being spawned during `target-title` that pristine doesn't spawn? Is a HUD/hint process (`hud`, `process-taskable`, `button-prompt`) running under master-mode 'game in attract? Name it with evidence (process type, where it's spawned, why it's active on Android vs pristine).
3. **Fix at the mechanism** — stop the spurious spawn / suppress the prompt during attract, matching pristine. goal_src is LOCKED unless the divergence is a genuine arm64-runtime cause (e.g. an uninitialized field / mis-read that makes a guard pass when it shouldn't); prefer fixing the arm64 runtime/render cause. If it IS a content gate that upstream handles differently, document precisely and propose the minimal change. No hiding the prompt with a blanket "never draw button prompts" hack — fix WHY the interactable is active in attract.
4. **Verify**: across the attract loop, NO "Press <CIRCLE> to use" (or any gameplay interaction prompt) appears; the title still flies crash-free (G1), Daxter/SCE still render (Gnd/Gsprite). Capture attract frames proving the prompt is gone.
5. **`Gtitle-fix-summary.md`** (≥80 lines): the spurious process named (vs pristine), the root cause, the fix, attract frames showing it gone.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**` (unless a documented arm64-runtime divergence requires a minimal gate fix — justify it), `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/gold/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, other phase prompts. No blanket "suppress all prompts" hack — fix the root over-spawn. x86 byte-identical (or documented intentional); x86 boots to `link finish: logo`; qemu ≥ 675. `export ANDROID_SERIAL=eae4df44`; keyguard; reversible app disables + RE-ENABLE; pgrep leftover runs. The supervisor pixel-judges the attract is prompt-free.

## Validator (`phase-Gtitle-attract-overspawn.sh`)

PASS requires: a real **`Gtitle-fix-summary.md`** (≥80 lines, names the spurious attract process + the pristine diff) PLUS the newest `Gtitle-routed-logcat-*.log` showing ZERO `sig=11`, the attract markers (`logo`/`logo-loop`/`target-title`), frame ≥ 300, PLUS the newest `Gtitle-focus-*.txt` ending on `org.opengoal.gk.jak1` PLUS ≥ 1 `Gtitle-device-*.png`. Whether the "Press <CIRCLE> to use" prompt is actually gone from the attract is judged by the supervisor's own eyes across multiple attract frames.

## Max settings

`max_turns: 1200`, `max_retries: 3`.

## Strategic note

Pristine says nothing interactable runs in the attract; ours raises a "use" prompt. Diff the attract actor list against the gold reference, name the process that shouldn't be there, and stop it at the source — then the title flythrough matches the original. Water + any missing elements are separate follow-ups after this.
