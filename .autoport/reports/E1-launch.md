# Phase E1 — UX (landscape + Bluetooth gamepad) launch report

_Generated: 2026-05-22T03:32:42+02:00_

## Determination

**pass**

## Marker observations (from logcat)

```
05-22 03:32:26.631 14678 14678 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=1
05-22 03:32:26.720 14678 14949 I opengoal-gk: SDL_Init: gamepad subsystem OK
05-22 03:32:26.720 14678 14949 I opengoal-gk: SDL_GAMEPAD: opened 'OpenGOAL touch overlay' id=1 (present at init)
05-22 03:32:26.928 14678 14949 I opengoal-gk: goal_main: calling InitMachine()
05-22 03:32:26.928 14678 14949 I opengoal-gk-full: InitMachine: entered (top-level wrapper)
05-22 03:32:26.928 14678 14949 I opengoal-gk-full: InitMachine: kglobalheap base=0x13fd20 end=0x3eb82e0 size=64456128 (61.47 MB)
05-22 03:32:26.963 14678 14949 I opengoal-gk-full: InitMachine: kglobalheap initialized, used=0
05-22 03:32:26.963 14678 14949 I opengoal-gk-full: InitMachine: kdebugheap base=0x5000000 end=0x7ff0000 size=50266112 (47.94 MB)
05-22 03:32:26.990 14678 14949 I opengoal-gk-full: InitMachine: init_output()
05-22 03:32:26.991 14678 14949 I opengoal-gk-full: InitMachine: print/output buffers reset
05-22 03:32:26.991 14678 14949 I opengoal-gk-full: InitMachine: InitListenerConnect / InitCheckListener
05-22 03:32:26.991 14678 14949 I opengoal-gk-full: InitMachine: MasterUseKernel=1 MasterDebug=1
05-22 03:32:26.991 14678 14949 I opengoal-gk-full: InitMachine: spawning IOP worker thread
05-22 03:32:26.991 14678 14949 I opengoal-gk-full: InitMachine: Deci2Server registered (port=8112, no listener)
05-22 03:32:26.991 14678 14949 I opengoal-gk-full: InitMachine: g_android_skip_goal_call=1 — A5 closed the imm12-overflow NOP gap, but the goalc-arm64 off-register bug in load_goal_gpr/store_goal_gpr still drops the EE base from GOAL pointer derefs (see A5-shim-audit.md)
05-22 03:32:26.991 14678 14949 I opengoal-gk-full: InitMachine: delegating to jak1::InitMachine
05-22 03:32:27.012 14678 14949 D opengoal-gk: link finish: gcommon
05-22 03:32:27.012 14678 14949 D opengoal-gk: link finish: gstring-h
05-22 03:32:27.012 14678 14949 D opengoal-gk: link finish: gkernel-h
05-22 03:32:27.013 14678 14949 D opengoal-gk: link finish: gkernel
05-22 03:32:27.013 14678 14949 D opengoal-gk: link finish: pskernel
05-22 03:32:27.013 14678 14949 D opengoal-gk: link finish: gstring
05-22 03:32:27.013 14678 14949 D opengoal-gk: link finish: dgo-h
05-22 03:32:27.013 14678 14949 D opengoal-gk: link finish: gstate
05-22 03:32:27.013 14678 14949 I opengoal-gk: pre_kernel_version_hook: set *kernel-version*=0x100000 (major=2 minor=0) — gkernel top-level was skip-flagged
05-22 03:32:27.016 14678 14949 D opengoal-gk: link finish: types-h
05-22 03:32:27.016 14678 14949 D opengoal-gk: link finish: vu1-macros
05-22 03:32:27.016 14678 14949 D opengoal-gk: link finish: math
05-22 03:32:27.016 14678 14949 D opengoal-gk: link finish: vector-h
05-22 03:32:27.017 14678 14949 D opengoal-gk: link finish: gravity-h
05-22 03:32:27.017 14678 14949 D opengoal-gk: link finish: bounding-box-h
05-22 03:32:27.017 14678 14949 D opengoal-gk: link finish: matrix-h
05-22 03:32:27.017 14678 14949 D opengoal-gk: link finish: quaternion-h
05-22 03:32:27.017 14678 14949 D opengoal-gk: link finish: euler-h
05-22 03:32:27.018 14678 14949 D opengoal-gk: link finish: transform-h
05-22 03:32:27.018 14678 14949 D opengoal-gk: link finish: geometry-h
05-22 03:32:27.018 14678 14949 D opengoal-gk: link finish: trigonometry-h
05-22 03:32:27.018 14678 14949 D opengoal-gk: link finish: transformq-h
05-22 03:32:27.018 14678 14949 D opengoal-gk: link finish: bounding-box
05-22 03:32:27.018 14678 14949 D opengoal-gk: link finish: matrix
05-22 03:32:27.019 14678 14949 D opengoal-gk: link finish: transform
05-22 03:32:27.019 14678 14949 D opengoal-gk: link finish: quaternion
05-22 03:32:27.019 14678 14949 D opengoal-gk: link finish: euler
05-22 03:32:27.019 14678 14949 D opengoal-gk: link finish: geometry
05-22 03:32:27.019 14678 14949 D opengoal-gk: link finish: trigonometry
05-22 03:32:27.020 14678 14949 D opengoal-gk: link finish: gsound-h
05-22 03:32:27.020 14678 14949 D opengoal-gk: link finish: timer-h
05-22 03:32:27.020 14678 14949 D opengoal-gk: link finish: timer
05-22 03:32:27.020 14678 14949 D opengoal-gk: link finish: vif-h
05-22 03:32:27.020 14678 14949 D opengoal-gk: link finish: dma-h
05-22 03:32:27.021 14678 14949 D opengoal-gk: link finish: video-h
05-22 03:32:27.021 14678 14949 D opengoal-gk: link finish: vu1-user-h
05-22 03:32:27.021 14678 14949 D opengoal-gk: link finish: dma
05-22 03:32:27.021 14678 14949 D opengoal-gk: link finish: dma-buffer
05-22 03:32:27.021 14678 14949 D opengoal-gk: link finish: dma-bucket
05-22 03:32:27.021 14678 14949 D opengoal-gk: link finish: dma-disasm
05-22 03:32:27.022 14678 14949 D opengoal-gk: link finish: pc-cheats
05-22 03:32:27.022 14678 14949 D opengoal-gk: link finish: pckernel-h
05-22 03:32:27.022 14678 14949 D opengoal-gk: link finish: pckernel-impl
05-22 03:32:27.022 14678 14949 D opengoal-gk: link finish: pc-debug-common
05-22 03:32:27.023 14678 14949 D opengoal-gk: link finish: pc-debug-methods
05-22 03:32:27.023 14678 14949 D opengoal-gk: link finish: pad
05-22 03:32:27.023 14678 14949 D opengoal-gk: link finish: gs
05-22 03:32:27.023 14678 14949 D opengoal-gk: link finish: display-h
05-22 03:32:27.023 14678 14949 D opengoal-gk: link finish: vector
05-22 03:32:27.024 14678 14949 D opengoal-gk: link finish: file-io
05-22 03:32:27.024 14678 14949 D opengoal-gk: link finish: loader-h
05-22 03:32:27.024 14678 14949 D opengoal-gk: link finish: texture-h
05-22 03:32:27.024 14678 14949 D opengoal-gk: link finish: level-h
05-22 03:32:27.024 14678 14949 D opengoal-gk: link finish: math-camera-h
05-22 03:32:27.024 14678 14949 D opengoal-gk: link finish: math-camera
05-22 03:32:27.025 14678 14949 D opengoal-gk: link finish: font-h
05-22 03:32:27.025 14678 14949 D opengoal-gk: link finish: decomp-h
05-22 03:32:27.025 14678 14949 D opengoal-gk: link finish: display
05-22 03:32:27.025 14678 14949 D opengoal-gk: link finish: connect
05-22 03:32:27.025 14678 14949 D opengoal-gk: link finish: text-h
05-22 03:32:27.026 14678 14949 D opengoal-gk: link finish: settings-h
05-22 03:32:27.026 14678 14949 D opengoal-gk: link finish: knuth-rand
05-22 03:32:27.026 14678 14949 D opengoal-gk: link finish: capture
05-22 03:32:27.026 14678 14949 D opengoal-gk: link finish: memory-usage-h
(no matching markers)
```

## Next blocker (if any)

None — E1 markers all observed. Validator should pass.
