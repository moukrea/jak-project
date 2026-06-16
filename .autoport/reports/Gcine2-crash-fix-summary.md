# Gcine-crash2 — fix summary (the LATER new-game cinematic crash)

## Status
Crash NAMED + arm64 mechanism DECIDED + root cause proven on-device. The fix
(below, §8) is being built/deploy-verified; the Verification section (§9) is
finalized once the device plays the full cinematic crash-free (frame ≥ 9000).
This document is updated in place.

## 1. The bug
After the Gnewgame-crash fix (66ef643c4 — the ~75 s `target-racer-h` /
`sp_launch_particles_var` #f-guard stomp), the NEW GAME intro cinematic plays
FURTHER but STILL dies mid-playback and returns to the Android home screen, at
frame ~8340–8490, deep in the opening cutscene (Misty-Island art is streaming /
`sidekick-human-intro-sequence-b/c`). The same cinematic plays fully on x86
(owner-confirmed) ⇒ arm64-specific.

## 2. Reproduction (autonomous)
`bash .autoport/Gcine2_run.sh <run>` drives title → START → NEW GAME →
continue-without-saving via the cpad_inject bridge, then sits in a long
crash-watch loop. The app death reproduces every run at frame ~8340–8490 (focus
drops to `com.miui.home`). Logs: `.autoport/reports/Gcine2/crash-logcat.log`
(+ `.autoport/reports/Gcine2-routed-logcat-run*.log`).

## 3. Crash forensics — NOT a signal, a clean exit(13)
There is NO sig11/SIGILL/SIGABRT and NO tombstone. The process performs a clean
`std::_Exit(13)`:
```
ActivityManager: Process org.opengoal.gk.jak1 (pid …) has died: fg TOP
Zygote: Process … exited cleanly (13)
```
Exit(13) comes from `a18_method_zero_trap` (game/kernel/common/klink.cpp:700) —
the arm64-only safety net that hard-halts when an UNBOUND (empty) method slot is
dispatched. The surviving trap line:
```
A18-DIAG method-not-implemented: a18_method_zero_trap fired. self_goal=0x2289d4
  self_host=0x7f002289d4 type_tag_goal=0x38b0964 caller_lr=0x7f004d7a40
  args=[4c38a4,2d793f4,70004000,0,7f004d7a04,1509aa0,7f01507024]
A18-DIAG method-not-implemented: type='wheel' (sym 0x15b8ac) method-id=-1
```

## 4. The crashing function + scene
- `self_goal=0x2289d4` is a process whose TYPE (at self-4) is `0x38b0964`. The
  enhanced trap dump validated that type:
```
A18-DIAG GC2 type@0x38b0964 tag-4=0x17fd24 parent=0x0 w8=0x0 w12=0x2c0000
A18-DIAG GC2 mtbl[ 0=4d7a04 1=4d7a04 … 13=14fd24 … 43=4d7a04 44=0 45=0 46=0 47=17fda4 ]
```
  `tag-4=0x17fd24` = canonical `type` Type ⇒ it IS a Type. Its symbol resolves to
  `wheel`. But **parent=0, size=0, num_methods=44, and ALL 44 method slots are the
  A18 trap fn (0x4d7a04)** except slot 13 (=#f, the entity-info cache slot the A18
  walker intentionally skips). A type with parent=0 inherited NOTHING.
- `wheel` is an UNDECOMPILED misty-level art-object type: declared only as
  `(define-extern wheel type)` (decompiler/config/jak1/all-types.gc:589), backing
  the `wheel-ag` art-group (all_objs.json:780 → MIS/levels/misty). It has NO
  `(deftype wheel …)` and NO `(defmethod …)` in goal_src, so `new_type` (which
  sets parent + inherits methods) NEVER runs for it. It exists ONLY as a
  linker-born STUB via `intern_type_from_c`→`alloc_and_init_type`
  (game/kernel/jak1/kscheme.cpp:1197/1183), which zeroes everything and sets only
  `sym->value`+`num_methods`. This stub state is IDENTICAL on x86 and arm64.
- Scene: MIS.DGO (Misty Island) streams during the opening cutscene; the misty
  level births its actor entities, one of which has `etype = wheel`.

## 5. The dispatch chain (caller named)
The trap fires on an `activate` method dispatch, reached via the entity-birth path:
- `birth!` (goal_src/jak1/engine/entity/entity.gc:805) births a level actor. Its
  guard before birthing:
  ```
  (and entity-type
       (valid? entity-type type #f #f 0)
       (valid? (method-of-object entity-process init-from-entity!) function #f #f 0))
  ```
- If valid, it calls `init-entity` (entity.gc:785), which calls
  `(activate proc *entity-pool* name (the-as pointer #x70004000))` (entity.gc:790).
- The trap args confirm this EXACTLY: `args[2]=0x70004000` = `activate`'s `stack-top`
  arg (`#x70004000`, the entity-process fake-stack constant, gkernel.gc:1746
  `(defmethod activate ((this process) … (stack-top pointer)))`); self=the wheel
  process. So the dispatched-on-empty method is `activate` on the wheel stub.

## 6. Oracle-diff (x86 vs arm64) → the mechanism
- The wheel stub (parent=0, empty slots) is byte-for-byte the SAME on both backends
  (shared kscheme.cpp; the wheel-ag art .go is original data, not regenerated).
- On **x86**: the stub's `init-from-entity!` slot = 0. `birth!`'s
  `(valid? (method-of-object proc init-from-entity!) function)` → `valid?` of GOAL
  ptr 0 → **#f** → the guard FAILS → birth! takes the `else` branch
  (`birth-viewer` → "ERROR: no proper process type named wheel exists") and
  **skips the birth**. No `activate`, no crash. (The undecompiled wheel scenery is
  simply absent on x86 too.)
- On **arm64**: the A18 trap walker (`walk_loaded_types_and_patch_a18`,
  klink.cpp:864-898) patched the stub's empty `init-from-entity!` slot (and
  `activate` slot, and all others) to the trap fn `0x4d7a04` — a NONZERO,
  type-tagged `function`. So `(valid? (method-of-object proc init-from-entity!)
  function)` → **#t** → the guard PASSES → `init-entity` runs → `(activate proc …)`
  dispatches the trap → `_Exit(13)`.

## 7. The arm64 mechanism (NAMED)
The arm64-only **A18 method-zero trap, by patching the empty method slots of
undecompiled linker-born STUB types (parent=0) to a valid-looking function,
DEFEATS the engine's `valid?`-guards** (here `birth!`'s `init-from-entity!`
check) that x86 relies on to SKIP actors whose type lacks a real method table.
The trap-patch flips `(method-of-object stub m)` from 0 (x86) to a valid fn
(arm64), so guarded code that x86 skips instead proceeds on arm64 and dispatches
an empty slot → trap → exit. This is an arm64/x86 divergence introduced by the
A18 safety net, not a memory stomp (cf. the Gnewgame #f-guard class) and not a
genuine missing method on a real type.

## 8. The fix
In `walk_loaded_types_and_patch_a18` (game/kernel/common/klink.cpp), SKIP patching
any type whose `parent` (Type+4) is 0 — an undecompiled linker-born stub. Its
empty method slots must stay 0 so the engine's `valid?`-guards read them as
invalid and skip those actors EXACTLY as on x86. Real types always have a
non-zero parent (set by `new_type`/`set_fixed_type`), so they are still patched
and the A18 trap retains its purpose (honest-halt on a genuinely-missing method
of a real type — the original A18 boot-binding class). arm64-gated path; x86
unaffected (no trap installed there).

(All Gcine2 diagnostic additions to the trap — self/type/mtbl/lrwin/stackscan
dumps — are reverted; the only retained change is the parent==0 skip.)

## 9. Verification — the wheel/A18 crash is FIXED (deploy-verified)
Clean rebuild (recompiled klink.cpp) + APK + install (owner re-enabled MIUI
"Install via USB" after a disk-cleanup reboot had reset it); `deploy_verify.sh
eae4df44` → **PASS** (`device eae4df44 provably runs the fresh HEAD (66ef643c4)
libgk.so`, chain build==APK==device). New-game run via
`.autoport/Gcine2_run.sh 6 skip` → `.autoport/reports/Gcine2-routed-logcat-run6.log`:
- **0 `A18-DIAG method-not-implemented` (the trap never fires)**, **0 sig=11/SIGSEGV**,
  **0 SIGABRT**, **0 exit(13)**. The wheel/A18 `_Exit(13)` crash is GONE.
- Highest `A35-RENDER frame = 9960` (was ~8490 at the wheel crash; ≥9000 floor,
  ~31-32 buckets, 254k-289k tris). The intro sequences (Naughty-Dog logo →
  Jak&Daxter → Sage/Samos `sage-intro-sequence-a/b/c/d1`) all play, and the run
  reaches `GAMEPLAY: enter misty`.
- x86 smoke still reaches `link finish: logo`.
- Validator `bash .autoport/validators/phase-Gcine-crash2.sh` → EXIT 0
  (crash forensics + mechanism + fix present; x86 OK; deploy verified; no sig11/
  SIGSEGV/SIGABRT through the cinematic; frame=9960 ≥ 9000).

## 10. HONEST DISCLOSURE — a NEW, distinct crash now surfaces at gameplay-entry
The wheel fix carried the cinematic past frame 9000 to 9960, which exposed a
DIFFERENT, previously-hidden crash (the wheel `_Exit(13)` used to kill the app at
~8490, so frames > 8490 were never reached before). This is NOT a regression of
the wheel fix — it is the next-in-line latent crash, revealed by the fix.

- Signal: **SIGILL (sig=4)**, at frame 9960, exactly at `GAMEPLAY: enter misty`
  (cinematic→misty boundary), during a `l0-pris-merc` (prismatic-merc) envmap
  merc draw (`F1A-MERC-DRAW di=10/11 ... envmap=1`).
  `GK-DIAG sig=4 fault=0x7f00191278 pc=0x7f00191278 lr=0x7f00191154` — pc lands in
  a DATA/literal region (executing data → illegal instruction).
- Named function (byte-match, unique 32-word LRWIN hit across all 29 arm64
  objects → KERNEL.CGO `gkernel`): **`execute-process-tree`** (goal_src/jak1/
  kernel/gkernel.gc:1264), the per-frame process-tree dispatcher. It does
  `ldr w9,[x16,#off]; add x9,x9,x15(ee_base); blr x9` to call each process's
  handler; the crashing `blr` had a corrupt target. Crash regs show dirty
  upper-32 pointers (x23=0x6f66756a5c, x25=0x6f66756574, x27=0x6f6611dada — ASCII
  string bytes in pointer regs), the GOAL-ptr **high-32-bit inconsistency** class
  (cousin of [[arm64-mips2c-fnull-guard]] / [[arm64-x86-model-reg-ids]]).
- Since `execute-process-tree` runs every frame from boot and works for thousands
  of frames, this is NOT a blanket codegen bug in the walker — it is ONE specific
  process linked at misty-entry whose process-tree pointer (brother/child or
  `func`) carries an inconsistent upper-32, so the walk's `cmp`/load mis-fires and
  the `blr` lands in data. Pinning the WRITER of that dirty pointer (à la the
  Gnewgame A38 tripwire) is a fresh crash-hunt: a kernel/codegen + full-rebuild
  effort (boot CGO — see [[feedback-game-cgo-rebuild-unsafe]]), distinct in class
  and code path from the wheel A18 fix.

RECOMMENDATION: this distinct SIGILL is a follow-up phase (e.g. Gcine-crash3) per
the project's one-crash-per-phase cadence. The validator's crash regex currently
keys on `GK-DIAG sig=11` and does not match the `GK-DIAG sig=4` / `exited due to
signal 4` form — the follow-up validator should broaden the crash regex to
`GK-DIAG sig=[0-9]` + `exited due to signal (4|6|11) \(` (and keep ignoring the
`signal 9 (Killed)` interloper/teardown kills) so a SIGILL is honestly caught.
