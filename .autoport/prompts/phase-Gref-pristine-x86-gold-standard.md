# Phase Gref — build the PRISTINE upstream x86 gold standard + the 3-tier comparison harness

## Why this phase exists (the owner's methodology principle)

We **modified the compiler** (`goalc`) to add arm64 support. Therefore *our own* x86 build is NOT a trustworthy reference — our compiler modifications could have introduced errors into BOTH our x86 and our Android output, and a 2-way "our-x86 vs our-Android" diff would not catch them. We need a **gold standard**: a build from *pristine, unmodified upstream* code. The comparison chain becomes:

**Original (pristine upstream x86) → Our x86 → Our Android**

- **Tier A — Original vs Our-x86:** catches bugs our compiler mods introduced into x86 itself (these are the most insidious — they live in BOTH our x86 and Android, invisible to a 2-way diff). Our 46 goalc commits on top of the merge-base are *supposed* to be arm64-gated; this tier PROVES it (or finds the leaks).
- **Tier B — Our-x86 vs Our-Android:** the legitimate arm64 porting surface (codegen stand-ins, runtime).

This phase builds the gold reference ONCE and leaves a reusable comparison harness that every later chronological fix phase uses.

## Hard facts

- `upstream` remote = `https://github.com/open-goal/jak-project.git`, fetched. **Merge-base (pristine pre-fork commit) = `704972dd6`** — this is the exact pristine version of our starting point; build IT for an apples-to-apples gold reference (no upstream drift).
- Our current x86 build: `build-x86/game/gk` (exists). Our x86 CGOs/DGOs: `out/jak1/iso/*.CGO` / `.DGO` (or wherever the build emits them — locate them).
- The autoport validators have long claimed "x86 CGOs byte-identical to A2 baseline" — but A2 is *our own* early build, not pristine upstream. THIS phase replaces that circular check with a real one.

## Mandate (in order)

1. **Build the pristine gold standard.** Create a git worktree at `704972dd6` (e.g. `../jak-gold` or `.autoport/gold/src` — do NOT disturb our working tree or HEAD). Build it for x86 with the same toolchain/config our build uses (Release, jak1). Run its `goalc` to produce the pristine CGOs/DGOs and a pristine `gk`. Stash the pristine artifacts under `.autoport/gold/` (binary, CGOs, DGOs).
2. **Tier A diff (the key deliverable):** byte-compare pristine CGOs/DGOs vs our-x86 CGOs/DGOs. Produce `.autoport/gold/tierA-cgo-diff.md`: for each object, identical or divergent; for divergent ones, the first differing offset + a disassembly snippet of the divergence. **Verdict line:** "Our x86 codegen is pristine-identical" OR "N objects diverge — our compiler mods leaked into x86: <list>" (the latter are goalc bugs to fix before trusting any oracle diff).
3. **Capture the pristine boot SEQUENCE reference.** Run the pristine `gk` (jak1) and capture the full boot/intro/title state sequence to `.autoport/gold/pristine-boot-sequence.log` — the chronological "perfect" reference: the SCEE "presents" state, the Naughty Dog / Daxter logo intro states, the title attract, the main-menu state, and the new-game → intro-cinematic transition (state names, `enter-state` calls, level/DGO links, the process/actor list during attract). This is the ground truth for the chronological fix phases (what states SHOULD run, in what order, with what actors — so we can tell "title over-spawns interactables" or "SCEE/ND states skipped" by diffing Android against THIS).
4. **Comparison harness:** write `.autoport/gold/compare-3tier.sh` — given an object name or a boot-log, it reports Tier-A (gold vs our-x86) and Tier-B (our-x86 vs our-android) divergences. Document usage in the summary so later phases invoke it.
5. **`Gref-summary.md`** (≥80 lines): the build provenance (commit, config), the Tier-A verdict (pristine-identical or the leak list), the captured pristine sequence (annotated: which states/actors appear in SCEE→ND→title→menu→cinematic), and how later phases use the harness.

## Rules / Anti-cheat (hard)

This phase builds a REFERENCE; it must NOT modify our engine/compiler. Locks: `goalc/**`, `game/**`, `goal_src/**`, `android/**`, `.autoport/lib/**`, `.autoport/validators/**`, `.autoport/orchestrator.py`, `.autoport/supervisor.sh`, other phase prompts. You MAY create files under `.autoport/gold/` and a worktree outside the repo. The gold build MUST be genuinely from `704972dd6` pristine (no cherry-picking our arm64 changes into it — that would defeat the purpose). x86 smoke (our build) still boots to `link finish: logo`. Do NOT touch the device or the running orchestrator state.

## Validator (`phase-Gref-pristine-x86-gold-standard.sh`)

PASS requires: a real **`Gref-summary.md`** (≥80 lines) with a Tier-A verdict; a pristine `gk` ELF under `.autoport/gold/` distinct from our build (different mtime/provenance, real ELF, non-trivial size); `.autoport/gold/tierA-cgo-diff.md` present listing per-object identical/divergent with a verdict line; `.autoport/gold/pristine-boot-sequence.log` present and non-trivial (contains intro/title state markers); `.autoport/gold/compare-3tier.sh` present and executable; no forbidden edits to goalc/game/goal_src/android; our x86 smoke still reaches `link finish: logo`.

## Max settings

`max_turns: 1200`, `max_retries: 3`.

## Strategic note

This is the measuring stick. With a pristine reference, every later chronological fix (SCEE intro, ND/Daxter logo, title flyover, menu overlay, cinematic) becomes a precise diff — "the pristine build runs state X with actors Y here; ours doesn't" — instead of device guesswork. Build it once, build it honestly from `704972dd6`, and report whether our compiler mods are x86-clean.
