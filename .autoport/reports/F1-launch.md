# Phase F1 — Geyser Rock gameplay launch report

_Generated: 2026-05-22T05:15:48+02:00_

## Determination

**blocked** — dispatcher in passive sleep loop; goalc-arm64 off-register bug — see F1-blocker-analysis.md

## Artefacts

- boot log:    `.autoport/reports/F1-boot.log` (3898 lines)
- screencap:   `.autoport/reports/F1-screencap-frame-600.png` (66542 bytes)
- state dump:  NOT PRODUCED — JNI hook depends on dispatcher (see F1-blocker-analysis.md)

## Marker scoreboard

Counts from `.autoport/reports/F1-boot.log`:

```
  MainActivity onCreate done                    1
  InitIOP OK                                    1
  Initialized GOAL heap                         1
  link finish: gcommon                          1
  link finish: gkernel                          2
  link finish: gstate                           1
  link finish: logo                             4
  android_renderer_run: entered                 1
  android_renderer: sustained swap              42
  KernelCheckAndDispatch: skip-flag armed       1
  KernelCheckAndDispatch: jak1 dispatcher returned 0
  Displaying level                              0
  load 'geyser-rock                             0
  engine: state=in-game                         0
  jak1::InitMachine ABORT                       0
  F DEBUG signal                                0
```

## Notes

The runtime skip-flag dodge introduced in D4 and retained at A5 is
still armed. The dispatcher reaches `KernelCheckAndDispatch` then
sleeps without forwarding to `jak1::KernelCheckAndDispatch`. This is
the documented consequence of the off-register goalc-arm64 emitter
bug — see `.autoport/reports/F1-blocker-analysis.md` and
`.autoport/reports/A5-shim-audit.md`.

Path forward: an A6-emitter-off-register phase that fixes
`load_goal_gpr` / `store_goal_gpr` / `load_goal_xmm32` /
`load_goal_xmm128` / `store_goal_xmm32` / `store_goal_vf` in
`goalc/emitter/IGenARM64.cpp` to emit `ADD X16, Xbase, X15; LDR/STR
Wt, [X16, #imm12]` instead of dropping the off register.
