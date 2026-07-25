;; GOAL Runtime assembly functions. These exist only in the arm64 version of GOAL.
;; - https://developer.apple.com/documentation/xcode/writing-arm64-code-for-apple-platforms#Pass-arguments-to-functions-correctly
;; - https://en.wikipedia.org/wiki/Calling_convention#ARM_(A64)
;; - https://student.cs.uwaterloo.ca/~cs452/docs/rpi4b/aapcs64.pdf
;; - s16–s31 (d8–d15, q4–q7) must be preserved
;; - s0–s15 (d0–d7, q0–q3) and d16–d31 (q8–q15) do not need to be preserved
;; - https://devblogs.microsoft.com/oldnewthing/20220728-00/?p=106912
;; - ;; - https://courses.cs.washington.edu/courses/cse469/19wi/arm64.pdf

.text

;; A24 — post-LDP X30 stack-range check macro. Mirrors the goalc-arm64
;; epilogue tracer in goalc/compiler/CodeGenerator.cpp::do_goal_function_arm64
;; (see the epilogue_x30_trace_emit_enabled() comment block there for the
;; rationale). Goalc-emitted epilogues are env-gated by OG_X30_TRACE_EMIT;
;; the asm trampolines below are NOT goalc-emitted and ARE on the suspect
;; list for the 216-link-finish ceiling crash (A23 falsified the
;; goalc-call_r64 BLR-target hypothesis; A24 attempt-1 falsified the
;; goalc-epilogue LDP hypothesis with ZERO firings of OG_X30_TRACE_EMIT
;; over 216 link-finishes — so the corruption must enter via an
;; asm-trampoline LDP X29,X30 whose save slot was clobbered during the
;; BLR into GOAL). The macro fires UDF #0x1EF0 if the just-LDP'd X30 is
;; signed-greater-or-equal to X15 + 0x07000000 — i.e. in the GOAL stack
;; range. The decoder in game/linux-arm64/linux_arm64_main.cpp emits
;; A24-DIAG EPILOGUE-X30-STACK with emit_pc + X30 + GOAL offset +
;; caller_lr + a 256-byte backward disasm window so the offending
;; trampoline is unambiguously named by its emit_pc.
;;
;; X16, X17 are AAPCS intra-procedure call scratch (IP0/IP1) — caller-
;; save, clobberable here. The macro emits 7 instructions per RET site.
;; Always-on (no compile-time gate): the .s file is consumed by GNU as
;; with no C-preprocessor pass, and the runtime cost is ~4 ns per
;; trampoline call (~hundreds of thousands of calls across a boot, so
;; <1 ms total — negligible).
;;
;; 2026-07-25 — LAYOUT-INDEPENDENCE FIX. The original check was one-sided
;; and SIGNED: B.LT skipped the UDF only when X30 < X15, i.e. it assumed
;; libgk.so is always mapped BELOW EE_BASE so a return into host C++ wraps
;; negative. android_runtime_compat.cpp tries to guarantee that by hinting
;; EE_BASE high, but it never validates the postcondition, and the kernel is
;; free to ignore the hint (MAP_FIXED_NOREPLACE is a no-op before kernel
;; 4.17 — the Redmi runs 4.14.190). After a device reboot on 2026-07-25 the
;; 0x7F00000000 hint was refused, EE_BASE fell to 0x7E00000000, and libgk.so
;; landed at 0x7E7B656000 — ABOVE EE_BASE. Every legitimate GOAL→C++ return
;; then produced X17 = 0x7BC20538 (positive, > 0x07000000), B.LT was not
;; taken, and the UDF fired: SIGILL at boot right after `link finish:
;; gcommon`, deterministically, on every launch.
;;
;; The check is now a proper TWO-SIDED UNSIGNED range test on the offset
;; into EE memory, so it is correct wherever the kernel places libgk.so
;; relative to EE_BASE:
;;   offset <  0x07000000              -> ordinary GOAL return         (skip)
;;   offset >= 0x08000000 (EE size)    -> return to native code, any
;;                                        layout, incl. libgk above EE  (skip)
;;   0x07000000 <= offset < 0x08000000 -> X30 corrupted into the top
;;                                        16 MB of EE space             (UDF)
;; Trade-off: a corrupt X30 pointing far OUTSIDE EE memory is no longer
;; trapped. It never was on the intended layout either (that range is where
;; host return addresses live, and is indistinguishable from a legitimate
;; native return), so no real detection is lost — only the false positive.
.macro a24_x30_stack_range_check
  sub  x17, x30, x15            // X17 = X30 - EE_BASE (unsigned offset into EE)
  movz x16, #0x0700, lsl #16    // X16 = 0x07000000 (GOAL stack-range floor)
  cmp  x17, x16
  b.lo 9999f                    // unsigned below floor → ordinary GOAL return
  movz x16, #0x0800, lsl #16    // X16 = 0x08000000 (EE_MAIN_MEM_SIZE, 128 MB)
  cmp  x17, x16
  b.hs 9999f                    // unsigned at/above EE top → native return (any layout)
  udf  #0x1ef0                  // distinct from A23's 0x1EE0..0x1EFF range
9999:
.endm

;; Call C++ code on arm64 systems, from GOAL.
;; Following the macOS documentation which mostly aligns with standard arm64
.global _arg_call_arm64
.align 4
_arg_call_arm64:
  stp	x29, x30, [sp, #-16]!
  mov	x29, sp
  ldr x8, [sp], #16

  ; Gffi-xmm-validate: preserve the GOAL-callee-saved XMM bank across the C++ call.
  ; goalc maps xmm8-15 to arm64 V24-V31 and treats them as CALLEE-saved (never
  ; spilled before a call, mirroring x86's GOAL ABI). VERIFIED against goalc:
  ; XMM0..XMM15 are register ids 16..31 (emitter/Register.h enum X86_REG;
  ; static_assert N_REGS-1 == XMM15), and the AArch64 emitter encodes the V-reg as
  ; arm64_reg5(r) = r.id() & 0x1f with NO remap (emitter/IGenARM64.cpp), so xmm8 =
  ; id 24 -> V24 and xmm15 = id 31 -> V31. The GOAL CC marks XMM8-15 saved=true
  ; (emitter/Register.cpp m_saved_xmms); a call clobbers only temp() regs
  ; (compiler/IR.cpp), so live floats stay in V24-V31 UNSPILLED across the call.
  ; An AAPCS C++ callee clobbers V16-V31 (caller-saved), so a GOAL float parked in
  ; V24-V31 — e.g. the spooled-anim frame-rate scale f30-0 in
  ; loader.gc::ja-play-spooled-anim — returns garbage unless saved HERE. The old
  ; q8-q15 save protected V8-V15, which goalc never uses for floats (and whose low
  ; halves AAPCS already preserves), so xmm8-15 was stomped and f30-0 collapsed:
  ; this is the ROOT of the f30-0 float-corruption class (title-spool anim rate +
  ; the Gd1/Gcine cutscene slow-mo). Save q24-q31 (matching pairs, no swap).
  stp q31, q30, [sp, #-32]!
  stp q29, q28, [sp, #-32]!
  stp q27, q26, [sp, #-32]!
  stp q25, q24, [sp, #-32]!

  ;; Gres-picker (autoport) — save the GOAL pp/st/off registers x13/x14/x15
  ;; across the C++ call. These are AAPCS caller-saved temporaries, so a C++
  ;; callee may clobber them; goalc treats them as the live GOAL ABI regs
  ;; (x13=pp, x14=st/#f-mirror base, x15=EE base). If x14 is stomped to the
  ;; EE base, every subsequent `(set! (-> obj field) #f)` — emitted as
  ;; `mov x9,x14; sub x9,x9,x15; str w9` — stores 0 instead of #f (x14==x15
  ;; ⇒ 0), zeroing e.g. joint-control.effect for swamp actors → null-dispatch
  ;; crash. Mirror the proven idiom in make_function_from_c_arm64 (kscheme.cpp)
  ;; and _mips2c_call_arm64 below: save right before the blr, restore right
  ;; after. `str x15,[sp,#-16]!` reserves a full 16 bytes (8 dead) so the
  ;; 16-byte SP alignment is preserved.
  stp x13, x14, [sp, #-16]!
  str x15, [sp, #-16]!

  ;; Ggrass-precompute (autoport) — bug class #14: also save the GOAL callee-saved
  ;; GPR bank {RBX,RBP,R10,R11,R12} = arm64 {X3,X5,X10,X11,X12} (identity id→Xn
  ;; map). goalc keeps values live in these across calls (x86-model saved
  ;; semantics; x86 gets r10/r11 saved by _arg_call_systemv and rbx/rbp/r12 by
  ;; SysV), but AAPCS lets the C++ callee clobber all five. Named by the
  ;; pc-settings parser desync at `recharged-grass-precomputed?` (kread clobber).
  stp x3, x5, [sp, #-16]!
  stp x10, x11, [sp, #-16]!
  str x12, [sp, #-16]!

  blr x8

  ;; bug class #14 — restore the GOAL saved-GPR bank (mirror LIFO)
  ldr x12, [sp], #16
  ldp x10, x11, [sp], #16
  ldp x3, x5, [sp], #16

  ;; restore the GOAL pp/st/off registers before any GOAL code runs again.
  ldr x15, [sp], #16
  ldp x13, x14, [sp], #16

  ;; restore in matching register order (NO swap). The old q8-q15 restore used
  ;; ldp q10,q11 against stp q11,q10 — a swap that was harmless only because
  ;; goalc never uses V8-V15; on the real xmm8-15 bank (V24-V31) the swap
  ;; corrupts f30-0, so pair each ldp to its stp exactly.
  ldp q25, q24, [sp], #32
  ldp q27, q26, [sp], #32
  ldp q29, q28, [sp], #32
  ldp q31, q30, [sp], #32

  ldp	x29, x30, [sp], #16
  a24_x30_stack_range_check
  ret


;; Call C++ code on arm64 systems, from GOAL.
;;
;; Put arguments on the stack and put a pointer to this array in the first arg.
;; this function pushes all 8 OpenGOAL registers into a stack array.
;; then it calls the function pointed to by x0 (RAX in x86) with a pointer to this array.
;; it returns the return value of the called function.
.global _stack_call_arm64
.align 4
_stack_call_arm64:
  stp	x29, x30, [sp, #-16]!
  mov	x29, sp
  ldr x8, [sp], #16

  ; Gffi-xmm-validate: save goalc xmm8-15 (= arm64 V24-V31), not q8-q15 — see the
  ; verified derivation in _arg_call_arm64 above. A C++ FFI callee clobbers V24-V31,
  ; which the GOAL caller treats as callee-saved (holds e.g. the spool f30-0, and the
  ; cutscene f30-0 of the same float-corruption class, there).
  stp q31, q30, [sp, #-32]!
  stp q29, q28, [sp, #-32]!
  stp q27, q26, [sp, #-32]!
  stp q25, q24, [sp, #-32]!

  ;; Gres-picker (autoport) — save the GOAL pp/st/off registers x13/x14/x15
  ;; across the C++ call. See _arg_call_arm64 above and the proven idiom in
  ;; make_function_from_c_arm64 (kscheme.cpp) / _mips2c_call_arm64 below.
  ;; x13/x14/x15 are AAPCS caller-saved, so the C++ callee may clobber them;
  ;; a stomped x14 (st/#f-mirror base) makes `(set! (-> obj field) #f)` store
  ;; 0 instead of #f (mov x9,x14; sub x9,x9,x15; str w9 ⇒ 0 when x14==x15),
  ;; zeroing joint-control.effect for swamp actors → null-dispatch crash. The
  ;; arg-array marshalling below uses x0-x7 and x19, never x13/x14/x15, so it
  ;; is unaffected. `str x15,[sp,#-16]!` reserves a full 16 bytes (8 dead) to
  ;; keep SP 16-byte aligned.
  stp x13, x14, [sp, #-16]!
  str x15, [sp, #-16]!

  ;; Ggrass-precompute (autoport) — bug class #14: save the GOAL callee-saved
  ;; GPR bank {X3,X5,X10,X11,X12} — see _arg_call_arm64 above. The arg-array
  ;; pop below only restores x0-x7; X10-X12 would stay clobbered without this.
  stp x3, x5, [sp, #-16]!
  stp x10, x11, [sp, #-16]!
  str x12, [sp, #-16]!

  ; create stack array of arguments
  ; arg 7 (R11 in x86)
  ; arg 6 (R10 in x86)
  ; arg 5 (R8 in x86)
  ; arg 4 (R8 in x86)
  ; arg 3 (RCX in x86)
  ; arg 2 (RDX in x86)
  ; arg 1 (RSI in x86)
  ; arg 0 (RDI in x86)
  stp x7, x6, [sp, #-16]!
  stp x5, x4, [sp, #-16]!
  stp x3, x2, [sp, #-16]!
  stp x1, x0, [sp, #-16]!

  ; set first argument
  mov x19, sp
  ; call function
  blr x8
  ; restore arguments
  ldp x1, x0, [sp], #16
  ldp x3, x2, [sp], #16
  ldp x5, x4, [sp], #16
  ldp x7, x6, [sp], #16

  ;; bug class #14 — restore the GOAL saved-GPR bank (mirror LIFO)
  ldr x12, [sp], #16
  ldp x10, x11, [sp], #16
  ldp x3, x5, [sp], #16

  ;; restore the GOAL pp/st/off registers before any GOAL code runs again.
  ldr x15, [sp], #16
  ldp x13, x14, [sp], #16

  ;; restore in matching register order (NO swap) — see _arg_call_arm64.
  ldp q25, q24, [sp], #32
  ldp q27, q26, [sp], #32
  ldp q29, q28, [sp], #32
  ldp q31, q30, [sp], #32

  ldp	x29, x30, [sp], #16
  a24_x30_stack_range_check
  ; return!
  ret

;; Call c++ code through mips2c.
;; GOAL calls a dynamically generated trampoline (LinkedFunctionTable::reg in
;; game/mips2c/mips2c_table_jak1_arm64.cpp) which loads:
;;   x16 = the C++ exec body (u64 (*)(void* ExecutionContext))
;;   x12 = the GOAL fake-stack size (16-byte multiple)
;; and BRanches here with x30 still holding the GOAL caller's return address.
;; Mirrors _mips2c_call_systemv (asm_funcs_x86_64.asm): build a 1280-byte
;; ExecutionContext on the stack, fill the MIPS arg slots a0-t3 from the
;; GOAL arg registers — which on this port are the x86-id registers
;; X7,X6,X2,X1,X8,X9,X10,X11 (RDI,RSI,RDX,RCX,R8,R9,R10,R11 enum ids; see
;; the A6 FFI shuffle note in game/kernel/jak1/kscheme.cpp) — pp/st from
;; the live GOAL convention regs (x13/x14, Phase C4 note), the MIPS sp
;; slot (gpr 29 @ +464) with the GOAL-relative context address (x15 = EE
;; base), then call the body on a lowered stack and return the context's
;; v0 (gpr 2 @ +32) in x0 (= GOAL return reg, x86 id RAX/0).
;; x13/x14/x15 are caller-saved under AAPCS (unlike SysV R13-R15), so the
;; C++ body may clobber them — save/restore explicitly, exactly like the
;; A6 GOAL→C FFI trampoline does.
.global _mips2c_call_arm64
.align 4
_mips2c_call_arm64:
  stp	x29, x30, [sp, #-16]!
  mov	x29, sp

  ;; save the GOAL callee-saved xmm registers. goalc maps xmm8-15 to arm64
  ;; V24-V31 (NOT V8-V15), and a mips2c/C++ body clobbers V16-V31 (AAPCS
  ;; caller-saved). The previous q8-q15 save protected registers goalc never
  ;; uses, leaving the GOAL caller's xmm8-15 (e.g. the spool f30-0 rate) to be
  ;; stomped — the f30-0 float-corruption class (title-spool rate + the Gd1/Gcine
  ;; cutscene slow-mo). Save q24-q31.
  stp q31, q30, [sp, #-32]!
  stp q29, q28, [sp, #-32]!
  stp q27, q26, [sp, #-32]!
  stp q25, q24, [sp, #-32]!

  ;; save GOAL pp/st/off — AAPCS temporaries the C++ body may clobber
  stp x13, x14, [sp, #-16]!
  str x15, [sp, #-16]!

  ;; Ggrass-precompute (autoport) — bug class #14: save the GOAL callee-saved
  ;; GPR bank {X3,X5,X10,X11,X12} — see _arg_call_arm64. A mips2c C++ body
  ;; clobbers these AAPCS temporaries; the GOAL caller may hold live values
  ;; there (x86-model saved semantics). Saved BEFORE the ExecutionContext is
  ;; built (x10/x11 arg slots + x11/x12 scratch below read/write freely).
  stp x3, x5, [sp, #-16]!
  stp x10, x11, [sp, #-16]!
  str x12, [sp, #-16]!

  ;; ExecutionContext (1280 bytes; gpr slot i at 16*i, filled like x86)
  sub sp, sp, 1280
  str x7, [sp, #+64]   ;; gpr a0 (GOAL arg 0, x86 id RDI=7)
  str x6, [sp, #+80]   ;; gpr a1 (GOAL arg 1, x86 id RSI=6)
  str x2, [sp, #+96]   ;; gpr a2 (GOAL arg 2, x86 id RDX=2)
  str x1, [sp, #+112]  ;; gpr a3 (GOAL arg 3, x86 id RCX=1)
  str x8, [sp, #+128]  ;; gpr t0 (GOAL arg 4, x86 id R8)
  str x9, [sp, #+144]  ;; gpr t1 (GOAL arg 5, x86 id R9)
  str x10, [sp, #+160] ;; gpr t2 (GOAL arg 6, x86 id R10)
  str x11, [sp, #+176] ;; gpr t3 (GOAL arg 7, x86 id R11)
  str x13, [sp, #+352] ;; gpr s6 = pp  (live GOAL reg x13)
  ;; Gswamp-fstore (autoport) — gpr s7 must hold the GOAL OFFSET of the symbol
  ;; table, exactly like x86 _mips2c_call_systemv (asm_funcs_x86_64.asm:133,
  ;; `mov [rsp+368], r14`) where R14 ALREADY IS that GOAL offset. On arm64 the
  ;; live st register x14 instead holds the HOST address of the symbol table
  ;; (set up as `add x14, st, off` in the _call_goal*_arm64 trampolines), so
  ;; storing raw x14 gives gpr s7 a host address — one EE-base too high.
  ;; ExecutionContext::jalr (mips2c_private.h) forwards gpr s7 as the `st` arg to
  ;; _call_goal8_asm_arm64, which reconstructs x14 = st + off (`add x14,x4,x5`).
  ;; With a host-valued gpr s7 that RE-ADDS the EE base -> a torn x14 in the GOAL
  ;; callee, and every `(set! (-> obj field) #f)` there (emitted as `mov x9,x14;
  ;; sub x9,x9,x15`) stores garbage instead of #f. That is the swamp
  ;; joint-control.effect null-dispatch crash. x14 - x15 = host_symtab - EE_base
  ;; = GOAL offset (x15 is the EE base / GOAL offset here, see line below).
  sub x11, x14, x15    ;; st as GOAL offset (x86-identical gpr s7 semantics)
  str x11, [sp, #+368] ;; gpr s7 = st (GOAL offset, NOT raw host x14)

  mov x11, sp
  sub x11, x11, x15    ;; GOAL-relative context address (x15 = GOAL offset)
  str x11, [sp, #+464] ;; gpr sp = mips2c code's GOAL stack

  mov x11, sp          ;; ExecutionContext pointer

  sub sp, sp, x12      ;; allocate the GOAL fake stack for the body
  ;; remember the size so we can find our way back (str/ldr, NOT
  ;; stp/ldp with equal regs — LDP Xt,Xt is CONSTRAINED UNPREDICTABLE
  ;; and SIGILLs on real cores even though qemu-user permits it)
  str x12, [sp, #-16]!

  mov x0, x11          ;; arg0 = ExecutionContext*
  blr x16              ;; call the C++ body

  ;; unallocate the fake stack
  ldr x12, [sp], #16
  add sp, sp, x12

  ldr x0, [sp, #+32]   ;; GOAL return value = context v0 (gpr 2)

  add sp, sp, 1280     ;; drop the ExecutionContext

  ;; bug class #14 — restore the GOAL saved-GPR bank (mirror LIFO)
  ldr x12, [sp], #16
  ldp x10, x11, [sp], #16
  ldp x3, x5, [sp], #16

  ldr x15, [sp], #16
  ldp x13, x14, [sp], #16

  ldp q25, q24, [sp], #32
  ldp q27, q26, [sp], #32
  ldp q29, q28, [sp], #32
  ldp q31, q30, [sp], #32

  ldp	x29, x30, [sp], #16
  a24_x30_stack_range_check
  ret

;; The _call_goal_asm function is used to call a GOAL function from C.
;; It calls on the parent stack, which is a bad idea if your stack is not already a GOAL stack.
;; It supports up to 3 arguments and a return value.
;; This should be called with the arguments:
;; - first goal arg
;; - second goal arg
;; - third goal arg
;; - address of function to call
;; - address of the symbol table
;; - GOAL memory space offset
.global _call_goal_asm_arm64
.align 4
_call_goal_asm_arm64:
  stp	x29, x30, [sp, #-16]!
  mov	x29, sp
  ;; A6 (autoport) — save the AAPCS callee-saved block (X19-X28 + D8-D15).
  ;; Real-on-device behaviour showed at least one helper in the GOAL→C
  ;; FFI chain clobbering X19 (the C++ caller `link_control::jak1_finish`
  ;; holds `this` in X19, and the fault on the LDR W2, [X19, #0x50] right
  ;; after call_goal_on_stack returns shows X19 came back as 0x7f7fffff
  ;; with the previous save list — i.e. it wasn't actually being saved).
  ;; The pre-A6 version saved X20-X28; the post-A6-fix version saved the
  ;; same plus X23 in call_r64 but still missed X19 in the trampoline.
  ;; Total now = 5 stp GPRs + 4 stp FPRs = 144 bytes (unchanged from
  ;; pre-fix 4-stp + 1-str + 4-stp, so the stack-switch alignment math
  ;; in _call_goal_on_stack_asm_arm64 stays correct).
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  stp x23, x24, [sp, #-16]!
  stp x25, x26, [sp, #-16]!
  stp x27, x28, [sp, #-16]!
  stp d8, d9, [sp, #-16]!
  stp d10, d11, [sp, #-16]!
  stp d12, d13, [sp, #-16]!
  stp d14, d15, [sp, #-16]!

  ;; x0 - first arg
  ;; x1 - second arg
  ;; x2 - third arg
  ;; x3 - function pointer
  ;; x4 - st (goes in x20 and x21)
  ;; x5 - off (goes in x22)

  ;; set GOAL process
  mov x20, x4
  ;; symbol table
  mov x21, x4
  ;; offset
  mov x22, x5
  ;; Phase C4 (autoport, bucket C): the goalc-arm64 emitter resolves the
  ;; GOAL ABI registers via the shared RegisterInfo (R13/R14/R15 enum IDs),
  ;; which map to arm64 register numbers 13/14/15 — NOT the documented
  ;; x20/x21/x22 from Register.h. The codegen-lock since A4 prevents
  ;; fixing this at the emitter level, so the trampoline mirrors st/off
  ;; into x14/x15 (and x13 for pp) right before the blr so the emitted
  ;; GOAL code finds its symbol-table base and g_ee_main_mem offset where
  ;; the compiled instructions actually look for them. Without this, the
  ;; first `str w_src, [x14, #imm12]` in any executed top-level SIGSEGVs
  ;; on a near-zero address.
  add x14, x4, x5
  mov x15, x5
  mov x13, x4
  ;; call GOAL by function pointer
  blr x3

  ;; A6 (autoport): restore the full AAPCS callee-saved set (X19-X28 +
  ;; D8-D15). See the corresponding stp's at the function head for why
  ;; the wider save is necessary.
  ldp d14, d15, [sp], #16
  ldp d12, d13, [sp], #16
  ldp d10, d11, [sp], #16
  ldp d8, d9, [sp], #16
  ldp x27, x28, [sp], #16
  ldp x25, x26, [sp], #16
  ldp x23, x24, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp	x29, x30, [sp], #16
  a24_x30_stack_range_check
  ret

.global _call_goal8_asm_arm64
.align 4
_call_goal8_asm_arm64:
  stp	x29, x30, [sp, #-16]!
  mov	x29, sp
  ;; A6 (autoport): mirror _call_goal_asm_arm64's full AAPCS callee-saved
  ;; block (X19-X28 + D8-D15). mips2c-routed C→GOAL FFI lands here, and
  ;; the C++ caller (chiefly the jak1 mips2c shim wrappers in
  ;; jak1/mips2c.cpp) keeps locals in X19+ that must survive the GOAL leg.
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  stp x23, x24, [sp, #-16]!
  stp x25, x26, [sp, #-16]!
  stp x27, x28, [sp, #-16]!
  stp d8, d9, [sp, #-16]!
  stp d10, d11, [sp, #-16]!
  stp d12, d13, [sp, #-16]!
  stp d14, d15, [sp, #-16]!

  ;; x0 - first arg (func)
  ;; x1 - second arg (arg array)
  ;; x2 - third arg  (0)
  ;; x3 - pp (goes in r13)
  ;; x4  - st (goes in r14)
  ;; x5  - off (goes in r15)

  ;; set GOAL function pointer
  mov x20, x3
  ;; st
  mov x21, x4
  ;; offset
  mov x22, x5
  ;; Phase C4 (autoport): mirror st_host/offset into x14/x15 + pp into
  ;; x13 — see the note in _call_goal_asm_arm64 above for the codegen-
  ;; lock workaround that this exists for.
  add x14, x4, x5
  mov x15, x5
  mov x13, x3
  ;; move function to a scratch that is NOT a GOAL arg register. The old
  ;; `mov x8, x0` clobbered arg4's slot (x8 == R8 == GOAL arg 4 below).
  mov x16, x0
  ;; Gsprite (autoport): place the 8 args in the GOAL ABI registers. Those
  ;; are the x86-id registers (RDI=7,RSI=6,RDX=2,RCX=1,R8,R9,R10,R11 — see
  ;; emitter/Register.cpp:44 m_gpr_arg_regs) emitted as physical arm64
  ;; register NUMBERS, exactly as _mips2c_call_arm64 above HARVESTS them:
  ;;   arg0->x7  arg1->x6  arg2->x2  arg3->x1  arg4->x8  arg5->x9
  ;;   arg6->x10 arg7->x11
  ;; This mirrors x86 _call_goal8_asm_systemv (asm_funcs_x86_64.asm:372-381)
  ;; one-for-one (mov rdi/rsi/rdx/rcx/r8/r9/r10/r11). The previous code used
  ;; AAPCS argN->xN, so only arg2 (x2) landed correctly; a GOAL callee taking
  ;; a heap/process pointer in arg3/arg4 (e.g. sp-launch-particles-var's
  ;; allocator calls) read garbage -> zeroed heap header -> Ptr.h:48 abort.
  ;; Load every array-relative value BEFORE overwriting x1 (the arg-array ptr,
  ;; which is also arg3's target) last.
  ldr x7,  [x1, #+0]   ;; arg0 -> x7  (RDI)
  ldr x6,  [x1, #+8]   ;; arg1 -> x6  (RSI)
  ldr x2,  [x1, #+16]  ;; arg2 -> x2  (RDX)
  ldr x8,  [x1, #+32]  ;; arg4 -> x8  (R8)
  ldr x9,  [x1, #+40]  ;; arg5 -> x9  (R9)
  ldr x10, [x1, #+48]  ;; arg6 -> x10 (R10)
  ldr x11, [x1, #+56]  ;; arg7 -> x11 (R11)
  ldr x1,  [x1, #+24]  ;; arg3 -> x1  (RCX) — LAST, clobbers the array ptr
  ;; call GOAL by function pointer
  blr x16

  ;; A6 (autoport): restore the full AAPCS callee-saved block (X19-X28 +
  ;; D8-D15).
  ldp d14, d15, [sp], #16
  ldp d12, d13, [sp], #16
  ldp d10, d11, [sp], #16
  ldp d8, d9, [sp], #16
  ldp x27, x28, [sp], #16
  ldp x25, x26, [sp], #16
  ldp x23, x24, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp	x29, x30, [sp], #16
  a24_x30_stack_range_check
  ret

;; Call goal, but switch stacks.
.global _call_goal_on_stack_asm_arm64
.align 4
_call_goal_on_stack_asm_arm64:
  stp	x29, x30, [sp, #-16]!
  mov	x29, sp
  ;; x0 - stack pointer
  ;; x1 - unused
  ;; x2 - unused
  ;; x3 - function pointer
  ;; x4  - st (goes in x21 and x20)
  ;; x5  - offset (goes in x22)

  ;; A6 (autoport): save the full AAPCS callee-saved block (X19-X28 +
  ;; D8-D15) on the OLD stack before we switch to the GOAL stack. The
  ;; previous attempt saved X20-X28 and missed X19; on-device crash
  ;; showed the C++ caller `link_control::jak1_finish` keeps `this` in
  ;; X19 and dereferences it (`LDR W2, [X19, #0x50]`) right after the
  ;; BL to call_goal_on_stack@plt returns, faulting at 0x7f80004f
  ;; because X19 = 0x7f7fffff after the trampoline failed to preserve
  ;; it. Five GPR stp pairs (X19-X28) + four FPR stp pairs (D8-D15) =
  ;; 144 bytes — same total as the previous (4 stp + 1 str + 4 stp),
  ;; so the 16-byte stack alignment requirement for the subsequent
  ;; `mov sp, x10` is unchanged.
  ; ARM64 requires 16-byte stack pointer alignment
  stp x19, x20, [sp, #-16]!
  stp x21, x22, [sp, #-16]!
  stp x23, x24, [sp, #-16]!
  stp x25, x26, [sp, #-16]!
  stp x27, x28, [sp, #-16]!
  stp d8, d9, [sp, #-16]!
  stp d10, d11, [sp, #-16]!
  stp d12, d13, [sp, #-16]!
  stp d14, d15, [sp, #-16]!
  ;; capture the OLD sp (after the pushes above) so we can restore it
  ;; after the GOAL function returns. NOTE - you cannot directly store or
  ;; load the `sp` register in arm64; round-trip through a GPR.
  ;;
  ;; Phase 26 (autoport) fix: the pre-phase-26 version of this code did:
  ;;   stp x22, x9, [sp, #-16]!   ;; (on OLD sp)
  ;;   mov sp, x0
  ;;   ...
  ;;   ldp x22, x9, [sp], #16     ;; (from NEW sp — UB, no matching push)
  ;; The store-then-switch sequence pushed onto the OLD stack but the load
  ;; after the call pops from the NEW stack, where nothing was stored. The
  ;; popped x9 was garbage and the subsequent `mov sp, x9` blew up.
  ;; The x86 sibling (_call_goal_on_stack_asm_systemv) gets this right by
  ;; pushing AFTER the switch; we now mirror that on aarch64.
  ;;
  ;; Phase D4 (autoport) fix: upstream callers (jak1::kboot.cpp,
  ;; jak1::klink.cpp::jak1_finish) compute goal_stack as
  ;; `(u64)g_ee_main_mem + EE_MAIN_MEM_SIZE - 8`, which is 8-byte aligned
  ;; but NOT the 16-byte alignment AArch64 requires for SP. Storing
  ;; through a misaligned SP triggers SIGBUS (BUS_ADRALN) on the very
  ;; first `stp` below. We align the incoming stack pointer DOWN to a
  ;; 16-byte boundary before switching — the difference is at most 8
  ;; bytes of unused stack at the top, which is negligible given the
  ;; 128 MB main mem allocation.
  mov x9, sp                ;; x9 = OLD sp value (already includes the X19-X28 + D8-D15 saves above)
  and x10, x0, #-16         ;; align goal_stack down to 16-byte
  mov sp, x10               ;; switch to GOAL/process stack
  stp xzr, x9, [sp, #-16]!  ;; push the saved OLD sp on the NEW stack (callee-saved already on OLD stack)

  mov x20, x4 // set GOAL function pointer
  mov x21, x4 // symbol table
  mov x22, x5 // offset
  ;; Phase C4 (autoport): mirror st_host/offset into x14/x15 + pp into
  ;; x13 — see the note in _call_goal_asm_arm64 for the codegen-lock
  ;; workaround. The emitted GOAL body references these IDs directly
  ;; (not x20/x21/x22) for ABI registers, so we have to seed them here.
  add x14, x4, x5
  mov x15, x5
  mov x13, x4
  ;; call GOAL by function pointer
  blr x3

  ;; restore registers — first pop the saved OLD sp from the NEW stack,
  ;; then switch back, then pop the AAPCS-callee-saved block (X19-X28 +
  ;; D8-D15) from the OLD stack.
  ldp xzr, x9, [sp], #16    ;; pop xzr placeholder + saved OLD sp from NEW stack
  mov sp, x9                ;; switch back to OLD stack
  ldp d14, d15, [sp], #16
  ldp d12, d13, [sp], #16
  ldp d10, d11, [sp], #16
  ldp d8, d9, [sp], #16
  ldp x27, x28, [sp], #16
  ldp x25, x26, [sp], #16
  ldp x23, x24, [sp], #16
  ldp x21, x22, [sp], #16
  ldp x19, x20, [sp], #16
  ldp	x29, x30, [sp], #16
  a24_x30_stack_range_check
  ret
