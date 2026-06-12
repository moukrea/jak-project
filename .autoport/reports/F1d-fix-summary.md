# F1d — input reaches the GOAL cpad: START → menus → NEW GAME → intro cinematic → Geyser Rock → Jak moves

## 1. The gap (as inherited from F1c)

F1c's honest residual: `adb input tap` and `adb input keyevent 108` were both
DELIVERED to the app (MIUIInput ACTION_DOWN/UP on the MainActivity channel)
but neither ever reached `(cpad-pressed? 0 start)` in GOAL. Coordinates were
already correct (1080×2400 physical vs 2298×1036 overlay bounds, +102,0
cutout); the gap was deeper than coordinates.

## 2. Root cause of the input gap

Traced in `android/`: the on-screen TouchOverlayView is a plain Android view
that synthesizes presses ONLY from real `onTouchEvent` motion streams, and the
SDL virtual-gamepad path the desktop port relies on is not in the loop at all
on the headless-injection side:

- `adb input tap` injects window events that reach the Activity's input
  channel, but the overlay's hit-zones translate them into JNI pad calls only
  for events it actually receives as touches on ITS window region — injected
  taps landed on the SDL surface view, not the overlay child, and died there.
- `adb input keyevent 108` (KEYCODE_BUTTON_START) reaches SDL's Java side,
  but the headless runtime never opened an SDL game-controller device, so no
  SDL_CONTROLLERBUTTON event is ever produced — and the GOAL runtime's
  `CPadGetData` on Android read a stub that no producer fed.

So BOTH delivery mechanisms worked at the Android layer and died before the
PS2 cpad image. The fix had to provide a real producer for the cpad state.

## 3. The fix mechanism (committed in 4554ca260, bisected innocent in F1e)

Chosen path = mandate option (b): a debug cpad-injection hook in the Android
runtime that sets the SAME button/stick state the overlay sets — a legitimate
test boundary (injects a real INPUT; GOAL logic genuinely reacts; nothing
downstream is faked):

- `android/android_input_audio.{cpp,h}` — a PS2-layout cpad mirror
  (`button0` bitmask + 4 analog axes, 0..255 with 127 neutral) fed by three
  OR-composed producers: overlay JNI, real Bluetooth pad (SDL events), and the
  headless file injector. `start_inject_watcher()` polls
  `files/cpad_inject` every 25 ms (bounded 512-byte reads, atomics only);
  tokens: `start x circle square triangle select l1 r1 l2 r2 l3 r3 up down
  left right lx= ly= rx= ry=`. `get_cpad_state()` is the single consumer read.
- `android/android_runtime_compat.cpp` — `CPadGetData` stamps the mirror into
  the GOAL `cpad-info` exactly like the desktop `scePadRead` path (button0
  pressed=1, sticks 0..255). One-shot `F1D-CPAD-START` log when GOAL reads a
  START press — the provable "press crossed the boundary" marker.
- `android/gk_android_main.cpp` — HOME → app files dir before `goal_main`
  (the save path previously resolved to a read-only CWD: uncaught
  `ghc::filesystem_error` → SIGABRT right after the title advanced); arms the
  inject watcher; F1D target-pos / PLAY-MODE telemetry (~4 Hz) reading the
  REAL GOAL symbols `*target*` (→ `process-drawable.root.trans`) and
  `*master-mode*` via the symbol table — real memory reads, not synthesized.

## 4. Why the flow previously stalled in the menus (this attempt's first find)

F1e run7 forensics: after START → `*master-mode*` = `progress`, X selected
NEW GAME, and the flow parked FOREVER on the "SELECT FILE TO SAVE TO" screen —
`A40-DPROC` showed `*master-mode*=progress` through f=8400 (run end). Cause:
the prior harness pressed X blindly on the save-slot list (slot 1 holds the
owner's GEYSER ROCK save; selecting it opens the slot-detail/overwrite view,
which the blind X presses never exited). Fix in the run harness: navigate
DOWN ×4 to CONTINUE WITHOUT SAVING (verified highlighted in
`F1d-device-run7-07-continue-sel.png`) and confirm with X — also preserves the
owner's save.

## 5. NEW blocker found and fixed: missing fr3 level archives (run4)

run4 (F1d-routed-logcat-run4.log): the new-game confirm genuinely fired —
`[OVERLORD] FS_Close MIS DGO`, `NOTICE: loaded misty-vis, 6910880 bytes`,
`link finish: misty-vis` — the intro cinematic plays over Misty Island and the
engine streamed its DGO from the seeded iso_data. Then, 6 s after the confirm:

```
Assertion failed: 'false'
  Message: Exception File /data/user/0/org.opengoal.gk.jak1/files/out/jak1/fr3/misty.fr3
           cannot be opened: does not exist. encountered in loader_thread
  Source: game/graphics/opengl_renderer/loader/Loader.cpp:251
  Function: void Loader::loader_thread()
```

SIGABRT on the Loader thread → `Force finishing activity` → launcher. Root
cause: the slim-APK first-run extraction (`.extracted_fr3_v1`) seeds only the
4 title-era archives (GAME, intro, title, village1); every other level's
PC-renderer archive was absent, so ANY level transition off the title set was
a guaranteed abort. Fix (asset, no code): seeded all 20 missing
`out/jak1/fr3/*.fr3` to the device via the established run-as channel,
size-verified (misty 12324141, training 7628334, beach 11565918, …, 205 MB
total, 15 GB free). This unblocks every future gameplay phase, not just this
flow.

## 5b. SECOND blocker found and MITIGATED: Adreno first-merc-draw-after-load fault (run5)

With the fr3s seeded, run5 got further: confirm fired, misty-vis linked,
misty.fr3 streamed, `Blackout loads done: misty is loaded` — then the F1e
crash signature EXACTLY (sig=11 fault=0x28 pc=0x7610d56414 =
libGLESv2_adreno+0x13a414) at the FIRST merc draw referencing the freshly
loaded level (`F1A-MERC-DRAW di=0/18 lev-bucket=l0-pris-merc tex=0x23c`,
load_id=2). Decisive forensics from the F1e instrumentation at the fatal draw:
`F1E-MERC-TEX branch=1 name=1702 is=1 size=627 bind=1702 fbo=50 status=0x8cd5
err=0x0 load_id=2 fsl=0` — texture ALIVE per glIsTexture, FBO complete, zero
GL errors, no F1E-DELTEX/DELBUF/EVICT events in the whole run. The F1e
texture/FBO validation set ran at this exact draw and did not reach the
object the driver nulls on.

Unified fault family across F1a/F1e/now: the first merc draw that consumes a
level's freshly-uploaded GL objects (title reveal = village1 reload;
cinematic start = misty first load) faults in the driver's draw-state walk.
Fix iterations (all `__ANDROID__` only, evidence-driven):

1. (REVERTED) one-time glFinish per load_id INSIDE the merc flush loop —
   run6 crashed at the boot reveal that the same build without it survived;
   a mid-frame pipeline drain between flushes makes the driver fault MORE
   likely. Reverted.
2. glFinish at Loader::update load completion (`F1D-LOADSYNC lev=… glFinish
   at load completion`) — GL thread, during blackout, no flush in flight.
   run7 reproduced the misty crash 8 ms AFTER this glFinish: command-drain
   alone does not materialize the faulting object. Kept (harmless, correct
   place for a sync) but not sufficient.
3. THE effective piece (Merc2.cpp flush path): a read-only
   `glMapBufferRange`+unmap of the level's VERTEX buffer (GL_ARRAY_BUFFER)
   next to F1a's existing index-buffer map — the ONE draw-state object no
   prior defuse ever touched (F1a maps the index BO; F1e validates
   textures/FBO). Mapping forces the driver to materialize the BO's internal
   storage object. run9: the previously 2/2-fatal misty first draw EXECUTED
   and the cinematic ran ~8 s (until the unrelated §7a break). run12 shows
   the family is still probabilistic at blackout-exit — call this a strong
   mitigation, not a cure; skips nothing, swallows nothing.

## 6. What injected input PROVABLY drives (runs 4-12, every run, foreground-verified)

| step | evidence (every run unless noted) |
|---|---|
| title attract (logo + PRESS START, camera flying) | `*-01-title.png`, boot-era `F1D target-pos … master-mode=game` (village1 parked target) |
| injected START → progress menu | `F1D-CPAD-START: START reached the cpad mirror` + `GOAL CPadGetData stamped START into cpad-info button0=0x0008 … (cpad-pressed? 0 start) fired` (2 one-shots, all 9 runs); `*-02-menu.png` = NEW GAME/LOAD GAME/OPTIONS/SECRETS/QUIT/BACK |
| injected DOWN/UP → cursor moves | run4/6/7: `03-menu-down1/2.png` (LOAD GAME, then OPTIONS highlighted), `05-menu-newgame.png` (back on NEW GAME) |
| injected X on NEW GAME → save-file screen | `06-savefile.png` ("SELECT FILE TO SAVE TO", slot 1 = owner's GEYSER ROCK save) |
| injected DOWN×4 → CONTINUE WITHOUT SAVING highlighted | `07-continue-sel.png` (run7: app foreground, verified highlight) |
| injected X → NEW GAME STARTS | `*master-mode*` leaves progress; `Discarding level village1`; `kill #<level active village1>`; `Adding level intro`; `begin load intro-vis [int.DGO]`; SIHISB STR spool chunks stream; **`Displaying level misty [display]`** (runs 9 & 12) — the state machine genuinely left the title |
| loadgame variant (runs 10/11): DOWN→LOAD GAME→X→slot 1 | `run10-06-loadgame-sel.png`, `run10-07-savelist.png` ("SELECT SAVE FILE TO LOAD", GEYSER ROCK selected); X starts the restore |

Every frame named above was opened and content-verified before naming. The
cinematic itself runs under blackout until its assets settle, so the visible
post-confirm frames (`run12-05..08-post-confirm-*.png`, app foreground) show
the blackout + overlay — the logcat carries the cinematic's existence
(misty display + intro DGO + STR spool traffic).

## 7. NOT achieved — and the exact, named walls (the honest core)

**Jak did NOT spawn this attempt. No movement evidence exists.** Both
legitimate roads to the training level end at deterministic crashes that are
each their own phase:

### 7a. NEW GAME road: spool joint-anim linking is broken on Android

run9 (and reproduced run12): seconds into the intro spool
(`sidekick-human-intro-sequence-b`), chronic
`could not find a master slot to link/unlink for #<art-joint-anim …>` errors
(present even for the title's own `logo-intro-2` spool — the subsystem is
broadly unhealthy on Android), then a joint channel's `frame-group` fails the
`art-joint-anim` type check in `evaluate-joint-control`
(`goal_src/jak1/engine/common-obs/process-drawable.gc:620`):
`(go process-drawable-art-error "joint-anim")` RETURNS (it must never),
falls into `(format 0 "dummy-19 bad~%")` + `(break!)` → the A26 divide-by-zero
trap (`UDF #0xBEEF`, decoded from the A37-PCWIN window:
`MOVZ X9,#0; CBNZ X9,+8; .word 0x0000beef` at pc=0x7f01e47a98) → SIGILL.
The break trap WORKED as designed; the bugs are (1) the master-slot spool
linking and (2) a `go` that returns instead of transferring.

### 7b. LOAD GAME road: restore dies in a corrupt control transfer (2/2)

runs 10 & 11, identical: X on the GEYSER ROCK save slot → pc-settings write →
~0.3-0.6 s → `sig=11 fault=0x0 pc=0x0 lr=0x0` with **x29(fp)=0 AND x30(lr)=0**
— a frame record restored as ZEROS then RET → pc=0. A34 process dump names the
victim: a process in state `done` (state-name-sym resolves "done") with a
GARBAGE next-state pointer (its name field decodes as an instruction,
0xa9bf7bfd = STP) — the auto-save/restore state machine's exit transition.
Both crashes fired inside the same ~300 ms window where the title's
`logo-loop` STR finished linking (`link finish: logo-loop` immediately
precedes both) — a plausible race partner. This is the A23/A37
corrupt-LDP-then-RET control-transfer family (same lineage as the parked
1-in-6 link-time boot flake), now with a DETERMINISTIC 2/2 repro:
`FLOW=loadgame bash .autoport/f1d_run.sh N skip`. That repro is gold for the
follow-up phase.

Common thread of 7a+7b: GOAL non-local control transfer (go / state
transition / deactivate-running-process) corrupts or no-ops on arm64 in
specific contexts. The phase's INPUT mandate is done; this control-transfer
family is the next wall and needs a dedicated phase with the runs 9-12
forensics as its starting dossier.

## 8. Verdict numbers (newest log = F1d-routed-logcat-run12.log)

- `F1D-CPAD-START` one-shots: 2 (mirror + GOAL CPadGetData read)
- `Displaying level misty [display]`: 1 (21:50:48, post-confirm)
- frame counter max: 3426 (≥300); tris max: 102796 (>0)
- `F1D target-pos` telemetry lines: 658 (real `*target*`/`*master-mode*`
  symbol reads)
- focus brackets: org.opengoal.gk.jak1 through `08-post-confirm-12s`
  (the crash then drops to launcher — recorded as-is in F1d-focus-run12.txt)
- crash inventory tonight: run4 misty.fr3 SIGABRT (FIXED — fr3 seeding);
  run5 Adreno 0x28 misty first draw (MITIGATED — vertex-BO map, see §5b);
  run6 Adreno 0x28 at boot reveal (mid-frame glFinish made it worse —
  REVERTED); run8 link-time boot-flake (pre-existing, parked); run9 dummy-19
  break (§7a); run10/11 pc=0 restore crash (§7b); run12 Adreno 0x28 at
  blackout-exit (the driver fault family remains probabilistic — §5b is an
  improvement, not a cure).

## 9. Honest residuals

- **Jak has not spawned on Android yet.** Blockers named in §7a/§7b with
  deterministic repros; both belong to a GOAL control-transfer/spool phase.
- The Adreno first-draw-after-load driver fault is mitigated (vertex-BO map
  + load-completion glFinish), not eliminated (run12).
- Pre-title boot intro missing; water/ocean + pause-menu backdrop wrong
  (parked, owner-known). Audio unported (F2a) — cinematic would be silent.
- The ~1-in-6 link-time boot-flake family (F1e §6) is untouched (cost run8).

## 10. Artifacts

- Logs: `F1d-routed-logcat-run{4..12}.log` + `F1d-focus-run{4..12}.txt`
  (run4 fr3-abort; run5/6/12 Adreno; run9 dummy-19; run10/11 restore crash)
- Frames: `F1d-device-run{4..12}-*.png` — menu navigation series (verified
  labels), run10 savelist series, run12 post-confirm blackout series
- Code this attempt: Merc2.cpp vertex-BO map defuse; Loader.cpp
  load-completion glFinish; `.autoport/f1d_run.sh` cinematic window + spawn
  detection + movement-delta verdict + FLOW=loadgame variant
- Device state: all 24 jak1 fr3 archives seeded (size-verified, run-as)
- Input bridge: commit 4554ca260 (F1e-era, bisected innocent), exercised
  end-to-end in all 9 runs tonight
