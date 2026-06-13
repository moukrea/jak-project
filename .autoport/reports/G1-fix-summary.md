# G1 — arm64 `go`/`enter-state` control transfer made oracle-correct (title recovered)

**Phase:** G1-arm64-go-enterstate-oracle-correct
**Goal (hard floor):** the title screen must boot crash-free and fly again after F1f
regressed it into `sig=11 fault=0x7effffffec` (control-transfer-to-garbage in the
arm64 `enter-state`/`go` path). **Stretch:** keep the new-game cinematic. **Method
(mandated):** diff the compiled `enter-state` / `.jr` / return path against the
working x86 oracle, find why a return address restores to garbage on the title
path, and make the arm64 RA/SP contract MATCH x86 — not guess from the device.

**Verdict:** FLOOR MET. The title regressor is reverted; the arm64 `enter-state`
`.jr` transfer is now **byte-identical to the verified-stable baseline e1f35fc0c**
and **semantically identical to the x86 oracle**. The cinematic stretch is the
documented residual (it required the very change that corrupts the title — see
§7). Collision/visible-Jak stays G2.

---

## 1. The regression (what F1f did and what broke)

F1f added a compiler change (`goalc/compiler/CodeGenerator.cpp`, commit
`19bb8e50a`: "pop the pushed RA into X30 at enter-state's `.jr`") plus kernel-asm
groundwork (`game/kernel/asm_funcs_arm64.s`, `game/kernel/jak1/klink.cpp`,
`game/mips2c/mips2c_table_jak1_arm64.cpp`, committed in `5b70c8d59`). The compiler
change made the pushed-RA→X30 scan (`mark_push_jr_pop_ra_arm64`) run for NORMAL
defuns, not just asm-funcs — so `enter-state` (a normal `defun` at
`goal_src/jak1/kernel/gstate.gc:372`) started emitting a pop-RA at its `.jr`.

That fixed the new-game cinematic's process-death RETURN path but **regressed the
title** on the real device:

```
GK-DIAG sig=11 fault=0x7effffffec pc=0x75b286f2e4 lr=0x75b286f2c0
```

`fault=0x7effffffec` is a near-top-of-EE-range address = a control transfer to a
garbage address = a corrupted/misaligned return-address contract on SOME
`enter-state` path. Because `go`/`enter-state` is the engine's universal state
mechanism (title attract, cinematics, AND gameplay all route through it), a fix
that is right for the cinematic RETURN path is wrong for the title's
suspend-forever attract states.

---

## 2. Oracle disasm diff — `enter-state` `.push RA; .jr func` (x86 vs arm64)

Method: dumped `enter-state` per-function with goalc's own disassembler
(`Compiler::codegen_and_disassemble_object_file`) for both backends after loading
the kernel deps (gcommon → gkernel → gstring → dgo-h) then `gstate.gc`:
- x86 oracle: `build-x86/goalc/goalc` → `/tmp/gstate_x86.asm`
- arm64 G1 (reverted, fresh from HEAD): `build-arm64/goalc/goalc` → `/tmp/gstate_arm64_G1fresh.asm`
- arm64 F1f (broken, for contrast): `/tmp/gstate_arm64_G1.asm`

### x86 (ground truth) — `gstate.gc:370-372`
```
[0x1035C]  push r9      ; .push return-from-thread-dead trampoline (rsp -= 8)
[0x1035E]  jmp  r8      ; .jr func — transfer to state code; trampoline RA sits on [rsp]
```
`jmp` does NOT touch `rsp`. The pushed trampoline word stays resident at `[rsp]`
for the entire lifetime of the state code. x86 has no link register — the return
address lives ONLY on the stack. The state `code` consumes the pushed word via its
own `ret` *iff it returns*; suspend-looping attract states never return, so the
word is simply never popped and the stack (already reset to main-thread stack-top
at 0x1034E) is never unwound.

### arm64 — G1 reverted (what we ship; matches x86)
```
[0x10518]  str x9, [sp, #-0x10]!   ; .push trampoline (SP -= 16)
[0x1051C]  br  x8                  ; .jr func — X30 left STALE (no pop-RA)
```
`br x8` does NOT touch SP — SP stays exactly 16 lower, trampoline word resident,
X30 stale (register-RA contract untouched on this direct-`(go)` path). This is the
faithful translation of x86's `push; jmp`.

### arm64 — F1f broken (the regressor) — `/tmp/gstate_arm64_G1.asm:697-699`
```
[0x10518]  str x9, [sp, #-0x10]!   ; .push trampoline (SP -= 16)
[0x1051C]  ldr x30, [sp], #0x10    ; F1f pop-RA: X30 = RA, SP += 16   <-- the bug
[0x10520]  br  x8                  ; .jr func
```
The inserted `ldr x30,[sp],#0x10` (encoding `0xF84107FE`, emitted by
`IR_JumpReg::do_codegen_arm64`'s `m_arm64_pop_ra` branch at `goalc/compiler/IR.cpp:2452`,
armed by `mark_push_jr_pop_ra_arm64` at `CodeGenerator.cpp:462`) re-raises SP by 16
BEFORE the `br`, consuming the trampoline word early.

---

## 3. Root cause of `fault=0x7effffffec`

For a state `code` that **suspends forever** (the title's attract states), x86
keeps the pushed trampoline word at `[rsp]` and never moves rsp. F1f's arm64 pops
it and raises SP by 16, so the state code begins executing on a stack **16 bytes
higher than the x86 contract**, with the trampoline word already gone. The
suspend snapshot (thread-suspend/thread-resume in `gkernel.gc`) is captured and
later restored at that shifted SP; a subsequent kernel dispatch reads a slot that
is now off by one quadword and finds a NULL/garbage function pointer →
`BLR Xn` to GOAL-null (EE base) → SIGSEGV.

`fault=0x7effffffec` itself is a **secondary** fault: the primary SIGSEGV's pc is
near the EE base, and `gk_sigsegv_diag` (game/linux-arm64) + its A37-PCWIN window
then read memory around that pc (`[pc&~15]-32 ..`), and THAT read faults near the
top of the EE range — which is the `0x7effffffec` reported. Either way the trigger
is the +16 SP / consumed-trampoline divergence from x86 on the suspend path.

(Caveat, stated honestly: the exact null-slot dispatch address `~0x18eed8` and the
"`0x7effffffec` == diag's own bad read" attribution come from the F1f-25 log +
CodeGenerator.cpp:585-607 narrative; the opcode-level diff in §2 is fully verified
from real disassembly, the secondary-fault attribution is corroborated but not
re-proven instruction-by-instruction in G1.)

---

## 4. Why the revert is oracle-CORRECT (equivalence argument)

Removing the pop-RA leaves arm64's `br x8` with a stale X30 and SP 16-low — exactly
x86's `jmp r8` (which also loads no RA register; x86's RA is the stack word only).
For suspend-looping states NEITHER side ever consumes the pushed trampoline, so the
stale X30 / un-popped `[rsp]` word is harmless and **semantically identical** to
x86. Verified from source: `git show e1f35fc0c:goalc/compiler/CodeGenerator.cpp`
has NO `mark_push_jr_pop_ra_arm64` call in `do_goal_function_arm64`; the scan lives
only in the asm-func path (`reset-and-call` @ gkernel.gc:535, `set-to-run-bootstrap`
@ gkernel.gc:1858), whose A34 contract is unchanged. The current HEAD working tree
is byte-identical to e1f35fc0c at the `enter-state` `.jr`.

This is the key oracle point: the title regression was NOT a missing arm64 feature
— it was an OVER-application of the push-RA→pop-RA rewrite to a path where x86
deliberately leaves the RA on the stack. The correct arm64 contract for
`enter-state`'s direct-`(go)` transfer is "leave it on the stack, like x86", which
is exactly what e1f35fc0c (and now HEAD) does.

---

## 5. Bisect matrix (blast-radius analysis)

| CodeGenerator pop-RA on enter-state | kernel-asm/mips2c collide-enable | Title boots+flies | Cinematic plays | Source |
|---|---|---|---|---|
| present (F1f) | present (F1f) | **NO — sig=11 0x7effffffec** | yes (Daxter animates, Jak spawns) | F1f run19/run25 |
| reverted | reverted (= e1f35fc0c) | **YES (3×149s clean @ e1f35fc0c; G1 device run below)** | no (RETURN path unfixed) | **G1 (shipped)** |
| reverted | present | title-risk (collide-enable + over-spawn; "Press CIRCLE to use" during attract, obs #6-8) — G2-scope, no floor benefit | no | attempt-1 intermediate (not shipped) |
| present | reverted | pop-RA still corrupts title | n/a | not viable |

Conclusions:
- The **CodeGenerator pop-RA on `enter-state` is the title regressor** — necessary
  and sufficient to break the title; reverting it is necessary to recover it.
- The kernel-asm/mips2c change is **G2 collision groundwork** (it enables the
  collide subsystem + an EE-scratch-stack mips2c trampoline + a klink null-data
  guard). With the pop-RA gone the cinematic doesn't play anyway, so keeping it
  buys no floor/stretch benefit and adds title-stability risk (newly-enabled
  collide bodies + the over-spawn observation). It is reverted here and preserved
  in git (`5b70c8d59`) for G2 to cherry-pick.

---

## 6. The fix — exact change set

**Reverted to e1f35fc0c (recovers the verified-stable title mechanism):**
- `game/kernel/asm_funcs_arm64.s` — removes the additive `_mips2c_call_arm64_eestack`
  trampoline + `g_mips2c_ee_sp_cursor` (G2 collide groundwork).
- `game/kernel/jak1/klink.cpp` — removes the `m_entry.offset > 4` load-game guard (G2).
- `game/mips2c/mips2c_table_jak1_arm64.cpp` — removes the collide-subsystem enable +
  eestack routing (G2).

**Kept (already e1f35fc0c-equivalent or mandated-preserve):**
- `goalc/compiler/CodeGenerator.cpp` — kept G1 attempt-1's refactor: the
  `mark_push_jr_pop_ra_arm64` scan is extracted into a named function but is called
  **only** from `do_asm_function_arm64` (line ~897), NOT from
  `do_goal_function_arm64`. Behaviorally identical to e1f35fc0c (enter-state gets no
  pop-RA; asm-funcs keep the A34 contract). The added comment block documents the
  whole rationale.
- `game/graphics/opengl_renderer/foreground/Merc2.cpp` — KEPT the Adreno
  first-merc-draw-after-load `fault=0x28` workaround (`glBindBufferBase(GL_UNIFORM_BUFFER,
  0, m_bones_buffer)`). Mandate rule 5 says preserve the F1e Adreno fix; it is
  validation-only (binds a live buffer to UBO point 0; rendering unchanged) and
  cannot corrupt a control transfer.
- `game/graphics/opengl_renderer/loader/Loader.cpp` — F1d-only (fr3 assets); no F1f hunk.

All prior fixes preserved: F1c modulo/MSUB (bug #13), F1e Adreno sync, F1d input
bridge — none touched.

---

## 7. Residual (the stretch, documented for the follow-up)

The new-game cinematic needs `enter-state`'s process-death RETURN path to run the
pushed `return-from-thread-dead` trampoline. F1f did that with a COMPILE-TIME
pop-RA marking — but whether an `enter-state` will RETURN (process death) or
SUSPEND forever (attract) is a RUNTIME property of the state `code`, not statically
known. So a compile-time pop-RA cannot distinguish the two: marking it fixes the
RETURN path and breaks the SUSPEND path (the title), and not marking it does the
reverse. The oracle-correct cinematic fix therefore does NOT live in the compiler —
it belongs in the kernel's process-death/thread-dead trampoline path (matching how
x86's `ret` consumes the stack word only on the paths that actually return). That
is deferred to G2 (collision/visible-Jak) alongside the rest of the gameplay
mechanism, where it can be done runtime-correct rather than compile-time-guessed.

---

## 8. Rebuild discipline

- arm64 goalc (`build-arm64/goalc/goalc`, fresh from HEAD) regenerated ALL 28
  arm64 CGO/DGOs (`(make-group "iso" :force #t)`) into `out/jak1/iso/`, synced to
  the APK assets dir `android/app/src/jak1/assets/iso_data/jak1/` (all 28, not just 3).
- x86 CGOs restored into `out/jak1/iso/` via `build/goalc/goalc` (x86) so the x86
  desktop smoke stays green; the 3 x86 CGO hashes byte-match `.autoport/reports/A2-baseline-x86-cgo-hashes.txt`.
- 3 arm64 CGOs stashed to `out/jak1-arm64/iso/` for the qemu gate.
- `libgk.so` rebuilt (arm64) with the reverted kernel files; APK repackaged + full-installed on `eae4df44`.

---

## 9. Device evidence (title stable) — VALIDATOR FLOOR

Captured on device `eae4df44` (Redmi Note 9 Pro, arm64) from the freshly-installed
APK (1.26 GB, all-28 arm64 assets). Source:
`.autoport/reports/G1-routed-logcat-run1.log` (22519 lines, 150s title watch),
`G1-focus-run1.txt`, `G1-device-run1-*.png`.

- **sig=11 / signal 11 count: 0** (floor: 0) — FLOOR MET. (Also 0 `Fatal signal 11`,
  0 `exited due to signal 11`.) The `0x7effffffec` control-transfer crash is GONE.
- **max `A35-RENDER frame=`: 11220** (floor: >=300) — FLOOR MET. Monotonic climb
  (720 → 1680 → … → 9720 → 11220) across the full watch = sustained, not a stall.
- **max `tris=`: 102796** (floor: >0) — FLOOR MET. The 3D title is really drawing.
- **`set-master-mode` count: 1** (floor: >=1) — FLOOR MET (boot reached play-master).
- **final focus: `org.opengoal.gk.jak1/org.opengoal.gk.MainActivity`** (floor:
  org.opengoal.gk.jak1) — FLOOR MET; all 13 caps held this focus.
- **screencaps: 13** (`G1-device-run1-wait-t15.png` … `wait-t150.png`, `menu-open`,
  `menu-back`, `title-after` = 2.33 MB). `wait-t90.png` / `title-after.png` show the
  textured 3D flying title — "JAK AND DAXTER — The Precursor Legacy / PRESS START"
  over the village sky flythrough.
- `enter-state` transition count during the title-only watch: 0 (attract suspends,
  as intended) — i.e. the title runs the exact suspend-forever path that F1f's
  pop-RA was corrupting, and it now flies crash-free for 11220 frames.

**Build integrity:** x86 desktop-smoke CGOs in `out/jak1/iso/` byte-match the A2
baseline (KERNEL `19c2e108…`, ENGINE `3145d31d…`, GAME `2a4b6c4f…`); arm64 assets
(KERNEL `63d7707c…` ≠ x86, proof of arm64) shipped in the APK; 3 arm64 CGOs stashed
to `out/jak1-arm64/iso/` for the qemu gate.

**Conclusion:** the hard floor is met — a stable, crash-free, sustained flying title
on an oracle-grounded `enter-state`/`go` fix that matches the x86 RA/SP contract.
