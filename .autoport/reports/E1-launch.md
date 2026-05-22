# Phase E1 — UX (landscape + Bluetooth gamepad) launch report

_Generated: 2026-05-22T03:46:33+02:00_

## Determination

**pass**

## Marker observations (from logcat)

```
05-22 03:46:16.384 20822 20822 I opengoal-gk: MainActivity onCreate done; mLayout=true mLayout.children=1
05-22 03:46:16.487 20822 20902 I opengoal-gk: SDL_Init: gamepad subsystem OK
05-22 03:46:16.487 20822 20902 I opengoal-gk: SDL_GAMEPAD: opened 'OpenGOAL touch overlay' id=1 (present at init)
05-22 03:46:16.738 20822 20902 I opengoal-gk: goal_main: calling InitMachine()
05-22 03:46:16.738 20822 20902 I opengoal-gk-full: InitMachine: entered (top-level wrapper)
05-22 03:46:16.738 20822 20902 I opengoal-gk-full: InitMachine: kglobalheap base=0x13fd20 end=0x3eb82e0 size=64456128 (61.47 MB)
05-22 03:46:16.780 20822 20902 I opengoal-gk-full: InitMachine: kglobalheap initialized, used=0
05-22 03:46:16.780 20822 20902 I opengoal-gk-full: InitMachine: kdebugheap base=0x5000000 end=0x7ff0000 size=50266112 (47.94 MB)
05-22 03:46:16.812 20822 20902 I opengoal-gk-full: InitMachine: init_output()
05-22 03:46:16.812 20822 20902 I opengoal-gk-full: InitMachine: print/output buffers reset
05-22 03:46:16.812 20822 20902 I opengoal-gk-full: InitMachine: InitListenerConnect / InitCheckListener
05-22 03:46:16.812 20822 20902 I opengoal-gk-full: InitMachine: MasterUseKernel=1 MasterDebug=1
05-22 03:46:16.812 20822 20902 I opengoal-gk-full: InitMachine: spawning IOP worker thread
05-22 03:46:16.813 20822 20902 I opengoal-gk-full: InitMachine: Deci2Server registered (port=8112, no listener)
05-22 03:46:16.813 20822 20902 I opengoal-gk-full: InitMachine: g_android_skip_goal_call=1 — A5 closed the imm12-overflow NOP gap, but the goalc-arm64 off-register bug in load_goal_gpr/store_goal_gpr still drops the EE base from GOAL pointer derefs (see A5-shim-audit.md)
05-22 03:46:16.813 20822 20902 I opengoal-gk-full: InitMachine: delegating to jak1::InitMachine
05-22 03:46:16.835 20822 20902 D opengoal-gk: link finish: gcommon
05-22 03:46:16.836 20822 20902 D opengoal-gk: link finish: gstring-h
05-22 03:46:16.836 20822 20902 D opengoal-gk: link finish: gkernel-h
05-22 03:46:16.837 20822 20902 D opengoal-gk: link finish: gkernel
05-22 03:46:16.837 20822 20902 D opengoal-gk: link finish: pskernel
05-22 03:46:16.838 20822 20902 D opengoal-gk: link finish: gstring
05-22 03:46:16.838 20822 20902 D opengoal-gk: link finish: dgo-h
05-22 03:46:16.838 20822 20902 D opengoal-gk: link finish: gstate
05-22 03:46:16.838 20822 20902 I opengoal-gk: pre_kernel_version_hook: set *kernel-version*=0x100000 (major=2 minor=0) — gkernel top-level was skip-flagged
05-22 03:46:16.842 20822 20902 D opengoal-gk: link finish: types-h
05-22 03:46:16.843 20822 20902 D opengoal-gk: link finish: vu1-macros
05-22 03:46:16.844 20822 20902 D opengoal-gk: link finish: math
05-22 03:46:16.848 20822 20902 D opengoal-gk: link finish: vector-h
05-22 03:46:16.849 20822 20902 D opengoal-gk: link finish: gravity-h
05-22 03:46:16.850 20822 20902 D opengoal-gk: link finish: bounding-box-h
05-22 03:46:16.851 20822 20902 D opengoal-gk: link finish: matrix-h
05-22 03:46:16.852 20822 20902 D opengoal-gk: link finish: quaternion-h
05-22 03:46:16.853 20822 20902 D opengoal-gk: link finish: euler-h
05-22 03:46:16.853 20822 20902 D opengoal-gk: link finish: transform-h
05-22 03:46:16.853 20822 20902 D opengoal-gk: link finish: geometry-h
05-22 03:46:16.860 20822 20902 D opengoal-gk: link finish: trigonometry-h
05-22 03:46:16.860 20822 20902 D opengoal-gk: link finish: transformq-h
05-22 03:46:16.861 20822 20902 D opengoal-gk: link finish: bounding-box
05-22 03:46:16.861 20822 20902 D opengoal-gk: link finish: matrix
05-22 03:46:16.862 20822 20902 D opengoal-gk: link finish: transform
05-22 03:46:16.862 20822 20902 D opengoal-gk: link finish: quaternion
05-22 03:46:16.864 20822 20902 D opengoal-gk: link finish: euler
05-22 03:46:16.864 20822 20902 D opengoal-gk: link finish: geometry
05-22 03:46:16.865 20822 20902 D opengoal-gk: link finish: trigonometry
05-22 03:46:16.866 20822 20902 D opengoal-gk: link finish: gsound-h
05-22 03:46:16.867 20822 20902 D opengoal-gk: link finish: timer-h
05-22 03:46:16.867 20822 20902 D opengoal-gk: link finish: timer
05-22 03:46:16.868 20822 20902 D opengoal-gk: link finish: vif-h
05-22 03:46:16.868 20822 20902 D opengoal-gk: link finish: dma-h
05-22 03:46:16.868 20822 20902 D opengoal-gk: link finish: video-h
05-22 03:46:16.868 20822 20902 D opengoal-gk: link finish: vu1-user-h
05-22 03:46:16.869 20822 20902 D opengoal-gk: link finish: dma
05-22 03:46:16.869 20822 20902 D opengoal-gk: link finish: dma-buffer
05-22 03:46:16.869 20822 20902 D opengoal-gk: link finish: dma-bucket
05-22 03:46:16.870 20822 20902 D opengoal-gk: link finish: dma-disasm
05-22 03:46:16.870 20822 20902 D opengoal-gk: link finish: pc-cheats
05-22 03:46:16.870 20822 20902 D opengoal-gk: link finish: pckernel-h
05-22 03:46:16.871 20822 20902 D opengoal-gk: link finish: pckernel-impl
05-22 03:46:16.871 20822 20902 D opengoal-gk: link finish: pc-debug-common
05-22 03:46:16.871 20822 20902 D opengoal-gk: link finish: pc-debug-methods
05-22 03:46:16.871 20822 20902 D opengoal-gk: link finish: pad
05-22 03:46:16.872 20822 20902 D opengoal-gk: link finish: gs
05-22 03:46:16.872 20822 20902 D opengoal-gk: link finish: display-h
05-22 03:46:16.872 20822 20902 D opengoal-gk: link finish: vector
05-22 03:46:16.873 20822 20902 D opengoal-gk: link finish: file-io
05-22 03:46:16.873 20822 20902 D opengoal-gk: link finish: loader-h
05-22 03:46:16.873 20822 20902 D opengoal-gk: link finish: texture-h
05-22 03:46:16.873 20822 20902 D opengoal-gk: link finish: level-h
05-22 03:46:16.874 20822 20902 D opengoal-gk: link finish: math-camera-h
05-22 03:46:16.874 20822 20902 D opengoal-gk: link finish: math-camera
05-22 03:46:16.874 20822 20902 D opengoal-gk: link finish: font-h
05-22 03:46:16.874 20822 20902 D opengoal-gk: link finish: decomp-h
05-22 03:46:16.874 20822 20902 D opengoal-gk: link finish: display
05-22 03:46:16.875 20822 20902 D opengoal-gk: link finish: connect
05-22 03:46:16.875 20822 20902 D opengoal-gk: link finish: text-h
05-22 03:46:16.875 20822 20902 D opengoal-gk: link finish: settings-h
05-22 03:46:16.875 20822 20902 D opengoal-gk: link finish: knuth-rand
05-22 03:46:16.875 20822 20902 D opengoal-gk: link finish: capture
05-22 03:46:16.876 20822 20902 D opengoal-gk: link finish: memory-usage-h
(no matching markers)
```

## Next blocker (if any)

None — E1 markers all observed. Validator should pass.
