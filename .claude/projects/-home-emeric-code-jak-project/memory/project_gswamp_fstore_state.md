---
name: gswamp-fstore-state
description: arm64 mips2c ExecutionContext gpr s7 must be seeded with the GOAL OFFSET (x14-x15), not raw host x14 — else jalr double-EE-base torns x14 and corrupts #f stores (swamp crash). FIXED.
metadata:
  type: project
---

PASS 2026-07-05 (48096f890). Rock Village→Swamp crash-to-home (owner Snapdragon) =
null/garbage dispatch at process-drawable.gc:636 `(if (-> gp-0 effect) (effect-control-method-9 ...))`:
joint-control.effect held garbage instead of #f.

ROOT (NOT codegen — goalc byte-correct on both backends): `_mips2c_call_arm64`
(game/kernel/asm_funcs_arm64.s) seeded ExecutionContext **gpr s7 (+368) with RAW x14**,
which on arm64 = the HOST address of the symbol table (`add x14, st, off` in the
_call_goal*_arm64 trampolines). x86 `_mips2c_call_systemv` seeds r14 = the GOAL OFFSET.
Every mips2c body that calls back into GOAL via `ExecutionContext::jalr`
(mips2c_private.h:382) forwards gpr s7 as the `st` arg to `_call_goal8_asm_arm64`, which
reconstructs `x14 = st + off` (`add x14,x4,x5`). Host-valued st ⇒ EE base added TWICE ⇒
torn x14 in the GOAL callee ⇒ every `(set! (-> obj field) #f)` (emitted `mov x9,x14; sub
x9,x9,x15`) stores garbage. Named class: **arm64 "double-EE-base" torn register on the
mips2c→GOAL callback path** (same class as Gmatch's g_dblee_repairs, different site).

FIX: store `x14 - x15` (GOAL offset) into gpr s7, x86-identical. **pp (gpr s6, +352)
left RAW x13** — `_call_goal8` passes pp through with `mov x13,x3` (no +off), so pp
round-trips correctly on both backends; only st is reconstructed with +off, so only st
must be a GOAL offset.

REUSABLE LESSON: the mips2c ExecutionContext gprs are consumed as GOAL/EE OFFSETS by the
shared C++ (gpr_addr = du32 + g_ee_main_mem, load_symbol_addr = sym-g_ee_main_mem). Any
arm64 trampoline seeding a context gpr from a live HOST-valued GOAL register (x14=st is
host; x13=pp/x15=off usage varies) must convert host→offset UNLESS the consuming path is
a pure pass-through. Suspect this class for future jak2/jak3 mips2c-callback `#f`/pointer
corruption.

PROOF (device-independent — owner device was offline): `.autoport/gsf/` qemu-aarch64 A/B
drives the REAL trampolines: FIX→gpr s7=GOAL offset, jalr callee sees #f=K (correct);
pre-fix BUG→gpr s7=host, #f=garbage (reproduces crash); test proven SENSITIVE. objdump:
libgk.so carries cb0f01cb `sub x11,x14,x15` / f900bbeb `str x11,[sp,#368]`. x86 parity:
28 CGO/DGO byte-identical (goalc untouched) + boots `link finish: logo`. Band-aid
`g_grv_nullfg_heals` (android/gk_android_main.cpp) RETAINED as belt-and-suspenders +
diagnostic (expected 0). Owner final swamp walk (0 crash + counter==0) deferred.

Builds on [[gcine-cut-deferred]] (prior double-EE-base blerc RETURN cursor) and
[[feedback-arm64-mips2c-fnull-guard]] (host-vs-offset gpr compare class). Prereq fix
history: the fd28435b6 _arg_call/_stack_call/_mips2c x13/x14/x15 SAVES protect x14 across
the C++ body — orthogonal; this fixes the SEED value written into the context.
