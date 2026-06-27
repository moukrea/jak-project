---
name: project_gcollision_systemic_state
description: Gcollision-systemic PASS — arm64 float→int saturation was the pervasive collision root, fixed in goalc codegen (not just mips2c)
metadata:
  type: project
---

Gcollision-systemic PASS 2026-06-27 (commits ad177bc0f fix + 078b946f5 evidence).

**Root (systemic):** arm64 goalc emitted a bare `FCVTZS` for GOAL float→int
(`IGenARM64 float_to_int32` scalar + `ftoi_vf` vector), which saturates NaN→0 /
+ovf+Inf→INT_MAX, where the x86 oracle `cvttss2si`/`cvttps2dq` maps all
out-of-range/NaN → INT_MIN (0x80000000). Collision quantizes coords via **58
vector `.ftoi.vf`** sites in the GAME+ENGINE CGOs (collide-cache 51 / mesh 4 /
edge-grab 3; scalar is ~0 in collision). Degenerate/overflow geometry → wrong
grid cell on arm64 → clip-through/eject/invisible-wall/under-map/stuck. The prior
per-site fix [[project_gledge_glitch... ]] patched the SAME class in ONE mips2c op
(vftoi0); this fixed the GOAL-layer (goalc) half — the actual pervasive cause.

**Fix (arm64-only, x86 byte-identical):** in `IR_FloatToInt`/`IR_VFMath2Asm`
do_codegen_arm64, FCVTZS then override only the +ovf/+Inf/NaN lanes to INT_MIN.
New encoders csel / movi_4s_lsl24 / fcmgt_4s / **bif_16b (base 0x6EE01C00 — NOT
the BIT 0x6EA01C00; size bits 23:22=11)**. Scratch: X16/X17 (free GPR), V0–V2
(free NEON; GOAL floats are V16–V31). No regalloc change → x86 unperturbed.
Needs a full consistent CGO rebuild (`.autoport/build_arm64_full_consistent.sh`)
since the fix is in the boot CGOs; deploy via the slim-APK + push-28-CGOs path.

**Method that worked (reusable):** unit sweep x86-vs-arm64 conv (38285/75000→0) +
on-device exec of the EXACT emitter words (seq_validate, 0 mismatch) + disasm via
`build-arm64/goalc/goalc ... (asm-file FILE :color :disassemble OUT)` (needs
`(make-group "iso")` first) + state-anchored in-game capture with a temp gated
C++ `colldump_tick` libgk hook reading *target* control trans/transv. BEFORE
device exploded on wall contact (tv.y saturated at **-163839.97 = -40·4096**, the
fixed-point/conversion fingerprint; 579-frame freeze); AFTER == x86.

GOTCHA: arm64 goalc `(make-group "iso")` overwrites out/jak1/iso (the x86 oracle)
with arm64 CGOs — restore x86 after (the build script does). Verify NEON/cond
encodings against the NDK assembler before shipping (I nearly shipped BIT-for-BIF).
