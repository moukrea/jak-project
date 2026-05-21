# A3 — Per-cluster arm64 differential vs x86

Of 36 real IR forms, 36 have disasm-clean arm64 codegen; 29 qemu-execute to a value matching x86. 7 forms reloc-skipped pending A4-linker-fixups.

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
| IR_FunctionAddr | call_return.gc | ✓ | — | — | — | skip |
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
| IR_GetSymbolValue | mem_symbol.gc | ✓ | — | — | — | skip |
| IR_GetSymbolValueAsm | mem_symbol.gc | ✓ | — | — | — | skip |
| IR_IntegerMath | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_LoadConstOffset | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_LoadConstant64 | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_LoadSymbolPointer | mem_symbol.gc | ✓ | — | — | — | skip |
| IR_RegSet | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_RegValAddr | stack_addr.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_Return | mem_load_const_offset.gc | ✓ | ✓ | 142 | 142 | ✓ |
| IR_SetSymbolValue | mem_symbol.gc | ✓ | — | — | — | skip |
| IR_StaticVarAddr | static_var.gc | ✓ | — | — | — | skip |
| IR_StaticVarLoad | static_var.gc | ✓ | — | — | — | skip |
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

## Reloc-skipped IRs

These IRs emit a real instruction sequence whose immediate field must be patched by the object linker. The arm64 linker support is the work of phase A4-linker-fixups; until then the disasm spot-check verifies the shape but qemu execution is bypassed.

- `IR_FunctionAddr`
- `IR_GetSymbolValue`
- `IR_GetSymbolValueAsm`
- `IR_LoadSymbolPointer`
- `IR_SetSymbolValue`
- `IR_StaticVarAddr`
- `IR_StaticVarLoad`

