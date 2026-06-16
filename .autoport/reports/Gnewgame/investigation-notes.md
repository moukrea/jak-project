# Gnewgame-crash — investigation notes (scratch; source for the final fix-summary)

## Settled facts (verified)
- Repro: NEW GAME via cpad_inject harness (.autoport/f1d_run.sh, FLOW=newgame).
  Intro cutscene plays ~75s (ndi-intro -> logo-intro -> sage-intro-sequence),
  then SIGSEGV.
- Crash (forensics, on current HEAD build): `GK-DIAG sig=11 fault=0x7f3eb851fa
  pc=0x75b31dcc1c lr=0x75b31dcc04`. pc = `jak1::new_type+0x80` (libgk.so+0x3b4c1c).
  Faulting instr `79401d0b ldrh w11,[x8,#0xe]` = `Ptr<Type>(parent)->num_methods`
  at game/kernel/jak1/kscheme.cpp:1362.
- `parent = 0x3eb851ec` (x20). Ptr<Type>(parent)=ee_base+parent=0x7f3eb851ec;
  +0xe=0x7f3eb851fa = fault. ee_base = g_ee_main_mem = 0x7f00000000 (mmap, 128MB).
  parent is far outside the 128MB heap => GARBAGE supplied by the GOAL caller.
- Old F1d hypothesis ("(go process-drawable-art-error) returns then break! ->
  UDF#0xBEEF SIGILL") is FALSIFIED for this build. No SIGILL/UDF; clean SIGSEGV.
- Crash site = top-level of object `target-racer-h` (goal_src/jak1/levels/
  racer_common/target-racer-h.gc). klink.cpp:622 prints "link finish: target-racer-h"
  BEFORE running the top-level at klink.cpp:724-730 (call_goal_on_stack). So the
  crashing deftype is INSIDE target-racer-h.gc.
- target-racer-h.gc top-level: `(deftype racer-info (basic))` line 27 then
  `(deftype racer-bank (basic))` line 116 — both parent = `basic`. First deftype
  (racer-info) is the crasher (interning at kscheme.cpp:1341 succeeds with arg0,
  so arg0 ok; crash is the parent deref at :1362).
- target-racer-h is bundled in MIS.DGO (Misty-Island intro) -> only the new-game
  flow links it; boot/title (frame 2522 reached) never do.
- x86 oracle: build-x86/game/gk reaches `link finish: logo` (validator check 4
  passes). x86 plays the new-game cinematic (owner-confirmed) => x86 links
  target-racer-h with the correct `basic` parent.
- s7 = GOAL offset 0x14fd24 (symbol table ~1.36MB into heap). Cited OOB writer
  (~0x519cxx, ~5.3MB) is FAR from the symbol table -> does not explain a basic-slot
  stomp.

## Call path
GOAL `(deftype X (parent))` -> top-level calls `type`'s `new` method =
C `new_type(symbol, parent, flags)` (bound kscheme.cpp:2083). args: arg0=new
type's name symbol (GOAL ptr), arg1=parent type (GOAL ptr/value), arg2=flags.
GOAL->C via make_function_from_c_arm64 (kscheme.cpp:631; arg1 shuffle x6->x1 at
:712 — verified correct).

## arm64 codegen of the `basic` load (unlinked .o disasm, target-racer-h top-level)
racer-info deftype call (offsets in the carved top-level blob):
```
20: adrp x7 ; 24: add x7        ; arg0 = LoadSymbolPointer(racer-info) -> GOAL ptr (Rd=X7)
28: adrp x16; 2c: add x16       ; basic slot address materialise (Rd=X16)
30: ldr  w6,[x16]               ; w6 = *(basic slot) = parent value
34: mov x2,#0x238 ; 38: movk x2,#9,lsl32   ; arg2 flags = 0x900000238 (n_methods=9)
... x9 = type.new_method ; 50-58: call_r64 spills (x3,x5,x10,x11,x12,x23) ;
5c: blr x9                      ; -> new_type
```
Nothing clobbers x6 between :30 and :5c. So parent = value loaded from the
ADRP/ADD-materialised `basic` slot address. arg0 (racer-info, same LoadSymbolPointer
family) worked.

## arm64 symbol-access codegen (goalc)
- IR_GetSymbolValue (symbol VALUE) arm64 (IR.cpp:636): `LDR/LDRSW Wd,[Xst,#imm12]`
  st-relative (Xst=x14). imm12 = symbol_offset>>2 (fits if offset<=16380).
- IR_LoadSymbolPointer (symbol ADDRESS) arm64 (IR.cpp:532-556): `ADRP Xd; ADD Xd`
  registered with link_instruction_symbol_ptr. The `basic` parent here uses
  LoadSymbolPointer(into temp X16) + `ldr w6,[x16]` deref (NOT GetSymbolValue).
- IR_SetSymbolValue arm64 (IR.cpp:586): `STR Wsrc,[Xst,#imm12]`.

## Runtime reloc patcher (klink_arm64_patch_pc_rel, game/kernel/common/klink.cpp:245)
Called from symlink_v3/ptr_link/typelink (jak1/klink.cpp). For an ADRP/ADD pair:
- If Rd != X16 AND not followed by `SUB Xd,Xd,X15`: rewrite ADRP->`MOVZ Xd,#lo16`,
  ADD->`MOVK Xd,#hi16,lsl16` so Xd = symbol's 32-bit GOAL OFFSET (a GOAL pointer).
  (This is the sym-PTR path; gives a GOAL offset consumed by Ptr<T> in C.)
- If Rd == X16 (A5 "sym-MEM reserves X16"): host-address path — ADRP page-delta +
  ADD lo12 => Xd = host address; range-checks page_delta to +-2^20 pages (+-4GB),
  prints "klink-arm64: ADRP page-delta ... out of range" + returns kAborted if out.
- LDR/STR [x14,#imm12]: st-relative; FAR symbols (offset> imm12 range) patched to NOP.
- Crash log shows ZERO "klink-arm64" abort/out-of-range messages this boot.

## Open question -> on-device probe (in flight)
Two hypotheses for `parent`=0x3eb851ec:
  (A) STOMP: `basic`'s value slot was runtime-overwritten. Tension: game ran ~75s
      using basic-derived dispatch; cited OOB region (0x519cxx) is nowhere near the
      symtab (0x14fd24). Would require a late, precise single-slot write.
  (B) RELOC/LOAD: the ADRP/ADD that materialises `basic`'s slot address (Rd=X16
      host path, OR the MOVZ/MOVK offset path) reads/produces a wrong address.
      Tension: arg0 (racer-info) used the same family and worked; no klink aborts.
Probe added to new_type (kscheme.cpp): on `parent >= EE_MAIN_MEM_SIZE`, prints the
type name, parent, and the INDEPENDENT C-side value+slot of `basic`/`type`/`structure`.
  - C-side basic.val == 0x3eb851ec  => (A) stomp confirmed -> hunt the writer.
  - C-side basic.val == small/correct => (B) reloc/load -> the GOAL-materialised
    address differs from the real slot -> codegen/linker fix (regen affected DGOs).
