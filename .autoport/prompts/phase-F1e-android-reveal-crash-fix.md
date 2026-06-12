# Phase F1e — kill the title-reveal crash (sig=11 fault=0x28), keep the input bridge

## Where we are (read this first — it changes your strategy)

- **F1c VERIFIED stable**: the title flies (bug class #13 modulo/MSUB fix, commit `ca47ddc32`). The supervisor's own boot ran 54+ seconds through the attract loop with no crash.
- **F1d attempt-1 made a REAL breakthrough**: injected START + X navigated title → menu → save-game screens (foreground-verified: `F1d-focus-run1/2.txt` frames 01–03 show `org.opengoal.gk.jak1`). The input→cpad bridge WORKS.
- **BUT the F1d build CRASHES at the logo→island reveal**: `GK-DIAG sig=11 fault=0x28 pc=0x7610d56414 lr=0x7610d93594`, ~4–7s after `set-master-mode 'game`, reproducible **3/3 runs** (see `.autoport/reports/F1d-routed-logcat-run3.log` lines ≈5920, 13463, 22664 — use `grep -a`). The app dies to the launcher; every F1d frame after 03 is `com.miui.home`. The owner confirmed live: "ça crash quand ça fait pop le logo... que le noir éclate pour révéler l'île."
- **F1d landed ZERO commits.** Its work sits UNCOMMITTED in the working tree right now:
  - `android/android_input_audio.cpp` (+244) / `.h` (+26) — the input bridge (on_pad_button, process_sdl_event, injection path)
  - `android/android_runtime_compat.cpp` (+48/−13) — touches `CPadOpen` / `CPadGetData`
  - `android/gk_android_main.cpp` (+90) — incl. a +55 block near `a36_tree_scan_per_frame` and +35 in `gk_sdl_main`
  - `.autoport/f1d_run.sh` (untracked)
  One or more of these likely introduced the reveal crash (F1c-era HEAD was stable). The ALTERNATIVE hypothesis: the crash is latent in HEAD's merc/envmap path and only triggers now that the title progresses differently. **Do not assume — bisect.**
- F1d attempts 2/3 were 0-turn quota no-ops; the supervisor reset F1d, and it re-runs AFTER this phase on your stable build. Your job is the crash + preserving the bridge, not the full Geyser flow.

## Mandate (in order)

1. **Triage the uncommitted diff** (`git diff android/`). Understand each hunk: input-bridge vs render/boot-path. Then **bisect by build matrix** on device: (a) clean HEAD build — does the reveal crash reproduce? (b) HEAD + input bridge files only; (c) full tree. Find the minimal diff that introduces the crash, or prove it's latent in HEAD.
2. **Symbolize the crash.** Get the libgk.so load base from the crash-time GK-DIAG context / maps in the logcat, then `addr2line -Cfe` (or llvm-symbolizer) against the MATCHING unstripped libgk.so for `pc=0x7610d56414` and `lr=0x7610d93594`. `fault=0x28` = reading a member at offset 0x28 of a NULL object pointer — name the object and why it's null at the reveal. The fix-summary MUST name function + line for both pc and lr.
3. **Fix at the mechanism.** Forbidden dodges: swallowing the fault, skipping the reveal, disabling merc/envmap/any renderer wholesale, null-checking-and-silently-skipping the draw every frame (the island must still RENDER after the reveal). A null-check is only acceptable if the summary explains why null is a legitimate transient state and shows the island rendering afterwards.
4. **Preserve the input bridge.** If it's not the crash source, keep it in the tree and COMMIT it as its own commit (it is F1d attempt-1's real deliverable). If it IS the source, fix it rather than discarding it. Commit in honest, separated pieces.
5. **Verify**: 3 consecutive device boots each surviving ≥60s past `set-master-mode 'game` — zero `sig=11`, focus stays `org.opengoal.gk.jak1` at EVERY bracket, the reveal completes (island visible in a frame), and the camera still flies (F1c regression check). If any CGO changed, regen + sync ALL 28 CGO/DGOs to APK assets (the B1 script only stashes 3).
6. **`F1e-fix-summary.md`** (≥80 lines): symbolized crash site (pc+lr), bisect matrix result, root-cause mechanism, the fix, the 3-boot evidence timeline, frames labeled by VERIFIED content.

## Rules / Anti-cheat (hard)

Locks: `goalc/emitter/IGenX86_64.{cpp,h}`, `goal_src/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/supervisor.sh`, `.autoport/orchestrator.py`, `.claude/agents/**`, other phase prompts. x86 boots to `link finish: logo`; qemu ≥ 675; preserve ALL prior fixes (esp. F1c modulo/MSUB — regression re-freezes the camera). `export ANDROID_SERIAL=eae4df44` only; keyguard check; reversible app disables (xiaoji ×2, sshxmobile, ghplus) with guaranteed RE-ENABLE; pgrep leftover run scripts before each device run. The supervisor re-captures independently and judges frames by pixels.

## Validator (`phase-F1e-android-reveal-crash-fix.sh`) — STRICT

PASS requires a real **`F1e-fix-summary.md`** (≥80 lines, MUST reference the symbolized `pc=0x7610d56414` / `fault=0x28` site by name) PLUS the newest `F1e-routed-logcat-*.log` showing `set-master-mode ... game`, frame ≥ 300, tris > 0, and **ZERO** `sig=11` / `exited due to signal 11` lines, PLUS the newest `F1e-focus-*.txt` ending on `org.opengoal.gk.jak1`. Plus standard gates: no forbidden edits; x86 smoke; qemu ≥ 675; gk_log_pipe; nm renderer syms; ≥ 1 `F1e-device-*.png`. Whether the island reveal actually renders is judged by the supervisor's own eyes.

## Max settings

`max_turns: 2000`, `max_retries: 3`.

## Strategic note

Thirteen bug classes down and the input bridge already works — this phase is a classic native-crash forensics loop (fp-walk, symbolize, bisect; see the A34 method). The crash fires at a fixed pc with a fixed fault offset: it is deterministic and will name itself under addr2line. Kill it without killing the island, commit the bridge, and F1d's START→Geyser run happens on solid ground.
