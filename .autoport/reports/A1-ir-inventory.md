# Phase A1 — AArch64 emitter IR inventory

Of 41 IR forms used by jak1, 6 have real arm64 codegen; 35 are stubs blocked for A2.

Totals across all declared IR classes (42): 6 real, 35 stub, 1 missing.

## Top blockers (A2 work list, descending by jak1 usage)

| Rank | IR form | arm64 status | x86 emits in jak1 (`(mi)`) |
|---:|---|---|---:|
| 1 | `IR_LoadConstOffset` | stub | 135,869 |
| 2 | `IR_GetSymbolValue` | stub | 90,705 |
| 3 | `IR_LoadSymbolPointer` | stub | 83,652 |
| 4 | `IR_StoreConstOffset` | stub | 60,259 |
| 5 | `IR_FunctionCall` | stub | 59,734 |
| 6 | `IR_Null` | stub | 46,463 |
| 7 | `IR_StaticVarLoad` | stub | 29,790 |
| 8 | `IR_StaticVarAddr` | stub | 23,602 |
| 9 | `IR_FloatMath` | stub | 16,238 |
| 10 | `IR_ValueReset` | stub | 11,582 |
| 11 | `IR_FunctionAddr` | stub | 9,455 |
| 12 | `IR_SetSymbolValue` | stub | 6,021 |
| 13 | `IR_IntToFloat` | stub | 4,045 |
| 14 | `IR_GetStackAddr` | stub | 3,680 |
| 15 | `IR_VFMath3Asm` | stub | 3,184 |
| 16 | `IR_BlendVF` | stub | 1,897 |
| 17 | `IR_FloatToInt` | stub | 1,843 |
| 18 | `IR_SplatVF` | stub | 1,132 |
| 19 | `IR_Int128Math3Asm` | stub | 996 |
| 20 | `IR_Nop` | stub | 703 |
| 21 | `IR_RegSetAsm` | stub | 482 |
| 22 | `IR_Int128Math2Asm` | stub | 240 |
| 23 | `IR_SwizzleVF` | stub | 188 |
| 24 | `IR_VFMath2Asm` | stub | 130 |
| 25 | `IR_RegValAddr` | stub | 85 |
| 26 | `IR_AsmFNop` | stub | 48 |
| 27 | `IR_AsmFWait` | stub | 34 |
| 28 | `IR_AsmAdd` | stub | 23 |
| 29 | `IR_AsmPop` | stub | 21 |
| 30 | `IR_AsmPush` | stub | 21 |
| 31 | `IR_SqrtVF` | stub | 20 |
| 32 | `IR_AsmRet` | stub | 8 |
| 33 | `IR_AsmSub` | stub | 6 |
| 34 | `IR_JumpReg` | stub | 4 |
| 35 | `IR_GetSymbolValueAsm` | stub | 3 |

## Full inventory (descending by jak1 usage)

| IR form | arm64 status | x86 emits in jak1 |
|---|---|---:|
| `IR_RegSet` | real | 493,080 |
| `IR_LoadConstOffset` | stub | 135,869 |
| `IR_GetSymbolValue` | stub | 90,705 |
| `IR_LoadConstant64` | real | 85,970 |
| `IR_LoadSymbolPointer` | stub | 83,652 |
| `IR_IntegerMath` | real | 62,587 |
| `IR_StoreConstOffset` | stub | 60,259 |
| `IR_FunctionCall` | stub | 59,734 |
| `IR_Null` | stub | 46,463 |
| `IR_ConditionalBranch` | real | 42,101 |
| `IR_GotoLabel` | real | 29,862 |
| `IR_StaticVarLoad` | stub | 29,790 |
| `IR_StaticVarAddr` | stub | 23,602 |
| `IR_FloatMath` | stub | 16,238 |
| `IR_ValueReset` | stub | 11,582 |
| `IR_FunctionAddr` | stub | 9,455 |
| `IR_Return` | real | 7,782 |
| `IR_SetSymbolValue` | stub | 6,021 |
| `IR_IntToFloat` | stub | 4,045 |
| `IR_GetStackAddr` | stub | 3,680 |
| `IR_VFMath3Asm` | stub | 3,184 |
| `IR_BlendVF` | stub | 1,897 |
| `IR_FloatToInt` | stub | 1,843 |
| `IR_SplatVF` | stub | 1,132 |
| `IR_Int128Math3Asm` | stub | 996 |
| `IR_Nop` | stub | 703 |
| `IR_RegSetAsm` | stub | 482 |
| `IR_Int128Math2Asm` | stub | 240 |
| `IR_SwizzleVF` | stub | 188 |
| `IR_VFMath2Asm` | stub | 130 |
| `IR_RegValAddr` | stub | 85 |
| `IR_AsmFNop` | stub | 48 |
| `IR_AsmFWait` | stub | 34 |
| `IR_AsmAdd` | stub | 23 |
| `IR_AsmPop` | stub | 21 |
| `IR_AsmPush` | stub | 21 |
| `IR_SqrtVF` | stub | 20 |
| `IR_AsmRet` | stub | 8 |
| `IR_AsmSub` | stub | 6 |
| `IR_JumpReg` | stub | 4 |
| `IR_GetSymbolValueAsm` | stub | 3 |
| `IR_Asm` | missing | 0 |

## How to regenerate

```
build/goalc/goalc --user-auto --game jak1 --disable-ansi \
    --ir-emit-stats /tmp/A1-jak1-x86-stats.json -c "(mi)"
python3 .autoport/lib/build_a1_inventory.py \
    goalc/compiler/IR.h goalc/compiler/IR.cpp \
    /tmp/A1-jak1-x86-stats.json \
    .autoport/reports/A1-ir-inventory.json \
    .autoport/reports/A1-ir-inventory.md
```
