# A4 — Arm64 link-time fix-ups, per-IR-form differential

Of 36 real IR forms, 36 have disasm-clean arm64 codegen and 36 qemu-execute to a value matching x86 — including the 7 IRs A3 reloc-skipped, now wired through the arm64-aware ObjectGenerator fix-up paths.

## Per-cluster results

### asm

| IR | test | disasm | qemu | x86 | arm64 | match |
|---|---|---|---|---|---|---|
| IR_AsmAdd | asm_ops.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_AsmPop | asm_ops.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_AsmPush | asm_ops.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_AsmRet | asm_ops.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_AsmSub | asm_ops.gc | ✓ | ✓ | 142 | 142 | ✓ |

### call

| IR | test | disasm | qemu | x86 | arm64 | match |
|---|---|---|---|---|---|---|
| IR_FunctionAddr | a4_func_addr.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_FunctionCall | call_return.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_JumpReg | call_return.gc | ✓ | ✓ | 142 | 142 | ✓ |

### control

| IR | test | disasm | qemu | x86 | arm64 | match |
|---|---|---|---|---|---|---|
| IR_ConditionalBranch | control_flow.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_GotoLabel | control_flow.gc | ✓ | ✓ | 142 | 142 | ✓ |

### float

| IR | test | disasm | qemu | x86 | arm64 | match |
|---|---|---|---|---|---|---|
| IR_FloatMath | float_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_FloatToInt | float_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_IntToFloat | float_math.gc | ✓ | ✓ | 142 | 142 | ✓ |

### int128

| IR | test | disasm | qemu | x86 | arm64 | match |
|---|---|---|---|---|---|---|
| IR_Int128Math2Asm | int128_math.gc | ✓ | ✓ | 110 | 110 | ✓ |
| IR_Int128Math3Asm | int128_math.gc | ✓ | ✓ | 110 | 110 | ✓ |

### mem

| IR | test | disasm | qemu | x86 | arm64 | match |
|---|---|---|---|---|---|---|
| IR_GetStackAddr | stack_addr.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_GetSymbolValue | a4_sym_svg.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_GetSymbolValueAsm | a4_sym_svg.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_IntegerMath | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_LoadConstOffset | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_LoadConstant64 | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_LoadSymbolPointer | a4_sym_ptr.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_RegSet | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_RegValAddr | stack_addr.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_Return | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_SetSymbolValue | a4_sym_svg.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_StaticVarAddr | a4_static_addr.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_StaticVarLoad | a4_static_load.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_StoreConstOffset | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |

### vf

| IR | test | disasm | qemu | x86 | arm64 | match |
|---|---|---|---|---|---|---|
| IR_BlendVF | vf_lane_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_RegSetAsm | vf_lane_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_SplatVF | vf_lane_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_SqrtVF | vf_lane_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_SwizzleVF | vf_lane_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_VFMath2Asm | vf_lane_math.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_VFMath3Asm | vf_lane_math.gc | ✓ | ✓ | 142 | 142 | ✓ |

## Runtime-link simulation

The harness pins main_code at virtual address 0x40400000 (via `--section-start=.text._main`) and the synthetic symbol table at 0x40500000 on both backends, so the arm64 patcher (a4_arm64_patcher.py) and the x86 patcher produce byte-identical effects on the function-pointer / symbol-pointer / static-pointer / static-load fix-up sites.

