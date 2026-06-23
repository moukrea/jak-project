# Gcrash-mouche — design notes (working)

## Root cause (static, high confidence)
Buzzer scout-fly pickup (`collectables.gc:1273-1274`, the `pickup` state of `buzzer`):
```
(let ((v1-18 (manipy-spawn (-> self root trans) #f *buzzer-sg* #f :to *entity-pool*)))
  (send-event (ppointer->process v1-18) 'become-hud-object (ppointer->process (-> *hud-parts* buzzers))))
```
Path: manipy-spawn → `become-hud-object` event → `convert-to-hud-object` (hud-classes.gc:1510)
sets `(-> draw dma-add-func) = dma-add-process-drawable-hud` + `(go hud-collecting)` →
`draw-bones-hud` (bones.gc:1408) **forces `use-mercneric=1`** → `draw-bones-generic-merc`.
The ENTIRE generic-merc family is **NOOP-bound on arm64** (not in `kSet`,
mips2c_table_jak1_arm64.cpp:392-524): `mercneric-convert`, `generic-merc-execute-asm`,
`generic-merc-init-asm`, all `generic-*` effect builders return 0. `draw-bones-hud` stores
`(set! (-> gp-0 base) (draw-bones-generic-merc ...))` → DMA `base` cursor collapses → crash.
Orbs don't crash: different (real) sprite HUD path. `draw-bones-merc` (non-generic Merc2) IS real.

## Repro (device, no goalc listener — Android has "no listener", android_runtime_full.cpp:209)
Native hook `mouche_maybe_fire()` (kmachine.cpp), gated by `debug.opengoal.mouche.fx` /
`OG_MOUCHE_FX`, fired as `*listener-function*` (kernel runs once via reset-and-call w/ live pp,
then auto-clears, gkernel.gc:1325). Replicates the form in C++:
- get-process (dead-pool method **14**) → activate (process-tree method **9**) →
  run-function-in-process(manipy-init, trans, #f, *buzzer-sg*, #f).
- become-hud-object: direct `convert-to-hud-object(manipy, hud)` w/ pp=manipy (== event handler).
  Safe: enter-state takes `(!= current-process pp)` branch → set-to-run + returns, no longjmp.
- CRITICAL: needs `*hud-parts* buzzers` non-#f (else convert-to-hud-object no-ops → world-merc,
  not the crash). Auto-spawned by init-target→activate-hud during the F1 warp; force activate-hud(*target*) if absent.

Offsets: target root(control)@+108, trans@+12 (proven by F1-WARP). hud-parts buzzers@+16.
event-message-block avoided entirely (direct convert call). x86 oracle (gmouche_x86.sh): NO crash.

## Fix candidates (decide AFTER device forensics)
- A (low risk): make the HUD/generic-merc noop SAFE — don't collapse the DMA base to 0 (passthrough),
  HUD fly icon won't render but no crash. Acceptable degradation (curated renderer subset).
- B (high risk): enable generic-merc family on arm64 (kSet + CMake TUs + #f-guard audit). Avoid unless needed.
- C: content-canary repair-and-resume if forensics show a code/data stomp (extend android_gfx.cpp).

Locks: ANDROID_SERIAL=eae4df44; no goalc/emitter/IGenX86_64; .autoport/gold read-only; goal_src 1-to-1.
