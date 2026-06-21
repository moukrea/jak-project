# Phase F1 — Geyser Rock gameplay launch report

_Generated: 2026-06-21T05:40:36+02:00_

## Determination

**fail** — reached title link but never gameplay state (dispatcher status unclear from log)

## Artefacts

- boot log:    `.autoport/reports/F1-boot.log` (8964 lines)
- screencap:   `.autoport/reports/F1-screencap-frame-600.png` (2488423 bytes)
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
  link finish: logo                             16
  android_renderer_run: entered                 1
  android_renderer: sustained swap              34
  KernelCheckAndDispatch: skip-flag armed       0
  KernelCheckAndDispatch: jak1 dispatcher returned 0
  Displaying level                              3
  load 'geyser-rock                             0
  engine: state=in-game                         0
  jak1::InitMachine ABORT                       0
  F DEBUG signal                                0
```

## Notes

