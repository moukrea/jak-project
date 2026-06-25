[(method debug-print game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x10
  [0x1000C] mov rbx, rdi
  [0x1000F] mov rbp, rsi
  [0x10012] mov r9d, [r15+rbx*1-0x04]
  [0x10017] mov r9d, [r15+r9*1+0x1C]
  [0x1001C] mov rdi, rbx
  [0x1001F] add r9, r15
  [0x10022] call r9
  [0x10025] mov r9, r14
  [0x10028] mov r8, r14
  [0x1002B] cmp rbp, r9
  [0x1002E] jnz 0x0000000000010039
  [0x10034] lea r8, [r14+0x08]
  [0x10039] mov r9, r8
  [0x1003C] mov r8, r14
  [0x1003F] cmp r9, r8
  [0x10042] jnz 0x0000000000010064
  [0x10048] lea r9, [r14+0xAFECAFE]
  [0x10050] mov r8, r14
  [0x10053] cmp rbp, r9
  [0x10056] jnz 0x0000000000010061
  [0x1005C] lea r8, [r14+0x08]
  [0x10061] mov r9, r8
  [0x10064] mov r8, r14
  [0x10067] cmp r9, r8
  [0x1006A] jz 0x0000000000010123
  [0x10070] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10078] lea rdi, [r14+0x08]
  [0x1007D] lea rsi, [0x0000000000010084]
  [0x10084] sub rsi, r15
  [0x10087] add r9, r15
  [0x1008A] call r9
  [0x1008D] xor r12, r12
  [0x10090] jmp 0x000000000001010C
  [0x10095] mov rsi, r12
  [0x10098] mov r9d, [r15+rbx*1-0x04]
  [0x1009D] mov r9d, [r15+r9*1+0x3C]
  [0x100A2] mov rdi, rbx
  [0x100A5] add r9, r15
  [0x100A8] call r9
  [0x100AB] mov r9, r14
  [0x100AE] cmp rax, r9
  [0x100B1] jz 0x0000000000010100
  [0x100B7] mov r11d, [r15+r14*1+0xBADBEEF]
  [0x100BF] lea r10, [r14+0x08]
  [0x100C4] lea r9, [0x00000000000100CB]
  [0x100CB] sub r9, r15
  [0x100CE] mov [rsp], r9
  [0x100D6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100DE] mov rdi, r12
  [0x100E1] add r9, r15
  [0x100E4] call r9
  [0x100E7] mov rdi, r10
  [0x100EA] mov rsi, [rsp]
  [0x100F2] mov rdx, rax
  [0x100F5] add r11, r15
  [0x100F8] call r11
  [0x100FB] jmp 0x0000000000010103
  [0x10100] mov rax, r14
  [0x10103] mov r9d, 0x01
  [0x10109] add r12, r9
  [0x1010C] mov r9d, 0x74
  [0x10112] cmp r12, r9
  [0x10115] jl 0x0000000000010095
  [0x1011B] mov r9, r14
  [0x1011E] jmp 0x0000000000010126
  [0x10123] mov r9, r14
  [0x10126] mov r9, r14
  [0x10129] mov r8, r14
  [0x1012C] cmp rbp, r9
  [0x1012F] jnz 0x000000000001013A
  [0x10135] lea r8, [r14+0x08]
  [0x1013A] mov r9, r8
  [0x1013D] mov r8, r14
  [0x10140] cmp r9, r8
  [0x10143] jnz 0x0000000000010165
  [0x10149] lea r9, [r14+0xAFECAFE]
  [0x10151] mov r8, r14
  [0x10154] cmp rbp, r9
  [0x10157] jnz 0x0000000000010162
  [0x1015D] lea r8, [r14+0x08]
  [0x10162] mov r9, r8
  [0x10165] mov r8, r14
  [0x10168] cmp r9, r8
  [0x1016B] jz 0x00000000000101E9
  [0x10171] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10179] lea rdi, [r14+0x08]
  [0x1017E] lea rsi, [0x0000000000010185]
  [0x10185] sub rsi, r15
  [0x10188] add r9, r15
  [0x1018B] call r9
  [0x1018E] mov ebp, [r15+rbx*1+0x60]
  [0x10193] xor r12, r12
  [0x10196] jmp 0x00000000000101D4
  [0x1019B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101A3] lea rdi, [r14+0x08]
  [0x101A8] lea rsi, [0x00000000000101AF]
  [0x101AF] sub rsi, r15
  [0x101B2] mov rdx, r12
  [0x101B5] shl rdx, 0x04
  [0x101B9] mov r8d, 0x0C
  [0x101BF] add r8, rbp
  [0x101C2] add rdx, r8
  [0x101C5] add r9, r15
  [0x101C8] call r9
  [0x101CB] mov r9d, 0x01
  [0x101D1] add r12, r9
  [0x101D4] movsxd r9, dword ptr [r15+rbp*1]
  [0x101D8] cmp r12, r9
  [0x101DB] jl 0x000000000001019B
  [0x101E1] mov r9, r14
  [0x101E4] jmp 0x00000000000101EC
  [0x101E9] mov r9, r14
  [0x101EC] mov rax, rbx
  [0x101EF] add rsp, 0x10
  [0x101F3] pop r12
  [0x101F5] pop r11
  [0x101F7] pop r10
  [0x101F9] pop rbp
  [0x101FA] pop rbx
  [0x101FB] ret


[(method print continue-point)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000C] lea rdi, [r14+0x08]
  [0x10011] lea rsi, [0x0000000000010018]
  [0x10018] sub rsi, r15
  [0x1001B] mov edx, [r15+rbx*1-0x04]
  [0x10020] mov ecx, [r15+rbx*1]
  [0x10024] mov r8, rbx
  [0x10027] add r9, r15
  [0x1002A] call r9
  [0x1002D] mov rax, rbx
  [0x10030] pop rbx
  [0x10031] ret


[(method copy-perms-to-level! game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r11
  [0x10004] push r12
  [0x10006] push rbx
  [0x10007] mov rbx, rdi
  [0x1000A] mov r9d, [r15+rsi*1+0x2C]
  [0x1000F] mov r9d, [r15+r9*1+0x78]
  [0x10014] mov ebp, [r15+r9*1+0x118]
  [0x1001C] xor r12, r12
  [0x1001F] jmp 0x00000000000100AE
  [0x10024] mov r9, r12
  [0x10027] shl r9, 0x06
  [0x1002B] mov r11d, 0x30
  [0x10031] mov r8d, 0x0C
  [0x10037] add r8, rbp
  [0x1003A] add r9, r8
  [0x1003D] mov r9d, [r15+r9*1+0x08]
  [0x10042] mov r9d, [r15+r9*1+0x14]
  [0x10047] add r11, r9
  [0x1004A] mov esi, [r15+r11*1+0x0C]
  [0x1004F] mov r9d, [r15+rbx*1-0x04]
  [0x10054] mov r9d, [r15+r9*1+0x40]
  [0x10059] mov rdi, rbx
  [0x1005C] add r9, r15
  [0x1005F] call r9
  [0x10062] mov r9, r14
  [0x10065] cmp rax, r9
  [0x10068] jz 0x00000000000100A2
  [0x1006E] vmovaps xmm7, [r15+rax*1]
  [0x10074] vmovaps [r15+r11*1], xmm7
  [0x1007A] lea rsi, [r14+0xAFECAFE]
  [0x10082] mov edx, 0x26F
  [0x10087] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1008F] mov r9d, [r15+r9*1+0x34]
  [0x10094] mov rdi, r11
  [0x10097] add r9, r15
  [0x1009A] call r9
  [0x1009D] jmp 0x00000000000100A5
  [0x100A2] mov rax, r14
  [0x100A5] mov r9d, 0x01
  [0x100AB] add r12, r9
  [0x100AE] movsxd r9, dword ptr [r15+rbp*1]
  [0x100B2] cmp r12, r9
  [0x100B5] jl 0x0000000000010024
  [0x100BB] mov r9, r14
  [0x100BE] pop rbx
  [0x100BF] pop r12
  [0x100C1] pop r11
  [0x100C3] pop rbp
  [0x100C4] pop rbx
  [0x100C5] ret


[(method copy-perms-from-level! game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] mov rbx, rdi
  [0x1000B] mov ebp, [r15+rbx*1+0x60]
  [0x10010] mov r9d, [r15+rsi*1+0x2C]
  [0x10015] mov r9d, [r15+r9*1+0x78]
  [0x1001A] mov r12d, [r15+r9*1+0x118]
  [0x10022] xor r11, r11
  [0x10025] jmp 0x00000000000100F8
  [0x1002A] mov r9, r11
  [0x1002D] shl r9, 0x06
  [0x10031] mov r10d, 0x30
  [0x10037] mov r8d, 0x0C
  [0x1003D] add r8, r12
  [0x10040] add r9, r8
  [0x10043] mov r9d, [r15+r9*1+0x08]
  [0x10048] mov r9d, [r15+r9*1+0x14]
  [0x1004D] add r10, r9
  [0x10050] movzx r9, byte ptr [r15+r10*1+0x0B]
  [0x10056] xor r8, r8
  [0x10059] cmp r9, r8
  [0x1005C] jz 0x00000000000100EC
  [0x10062] mov esi, [r15+r10*1+0x0C]
  [0x10067] mov r9d, [r15+rbx*1-0x04]
  [0x1006C] mov r9d, [r15+r9*1+0x40]
  [0x10071] mov rdi, rbx
  [0x10074] add r9, r15
  [0x10077] call r9
  [0x1007A] mov r9, r14
  [0x1007D] cmp rax, r9
  [0x10080] jz 0x000000000001009C
  [0x10086] vmovaps xmm7, [r15+r10*1]
  [0x1008C] vmovaps [r15+rax*1], xmm7
  [0x10092] movq r9, xmm7
  [0x10097] jmp 0x00000000000100E7
  [0x1009C] movsxd r9, dword ptr [r15+rbp*1]
  [0x100A0] movsxd r8, dword ptr [r15+rbp*1+0x04]
  [0x100A5] cmp r9, r8
  [0x100A8] jnl 0x00000000000100E4
  [0x100AE] vmovaps xmm7, [r15+r10*1]
  [0x100B4] movsxd r9, dword ptr [r15+rbp*1]
  [0x100B8] shl r9, 0x04
  [0x100BC] mov r8d, 0x0C
  [0x100C2] add r8, rbp
  [0x100C5] add r9, r8
  [0x100C8] vmovaps [r15+r9*1], xmm7
  [0x100CE] movsxd r9, dword ptr [r15+rbp*1]
  [0x100D2] mov r8d, 0x01
  [0x100D8] add r9, r8
  [0x100DB] mov [r15+rbp*1], r9d
  [0x100DF] jmp 0x00000000000100E7
  [0x100E4] mov r9, r14
  [0x100E7] jmp 0x00000000000100EF
  [0x100EC] mov r9, r14
  [0x100EF] mov r9d, 0x01
  [0x100F5] add r11, r9
  [0x100F8] movsxd r9, dword ptr [r12+r15*1]
  [0x100FC] cmp r11, r9
  [0x100FF] jl 0x000000000001002A
  [0x10105] mov r9, r14
  [0x10108] pop r12
  [0x1010A] pop r11
  [0x1010C] pop r10
  [0x1010E] pop rbp
  [0x1010F] pop rbx
  [0x10110] ret


[(method get-health-percent-lost game-info)]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] movss xmm8, dword ptr [0x0000000000010013]
  [0x10013] mov rsi, r14
  [0x10016] mov r9d, [r15+rdi*1-0x04]
  [0x1001B] mov r9d, [r15+r9*1+0x7C]
  [0x10020] add r9, r15
  [0x10023] call r9
  [0x10026] cvtsi2ss xmm7, eax
  [0x1002A] mulss xmm8, xmm7
  [0x1002F] movd eax, xmm8
  [0x10034] movsxd rax, eax
  [0x10037] movdqa xmm8, [rsp]
  [0x1003D] add rsp, 0x18
  [0x10041] ret


[(method lookup-entity-perm-by-aid game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rdi*1+0x60]
  [0x10005] movsxd r8, dword ptr [r15+r9*1]
  [0x10009] jmp 0x0000000000010056
  [0x1000E] mov ecx, 0x01
  [0x10013] sub r8, rcx
  [0x10016] mov rcx, r8
  [0x10019] shl rcx, 0x04
  [0x1001D] mov edx, 0x0C
  [0x10022] add rdx, r9
  [0x10025] add rcx, rdx
  [0x10028] mov ecx, [r15+rcx*1+0x0C]
  [0x1002D] cmp rsi, rcx
  [0x10030] jnz 0x0000000000010053
  [0x10036] mov rax, r8
  [0x10039] shl rax, 0x04
  [0x1003D] mov r8d, 0x0C
  [0x10043] add r8, r9
  [0x10046] add rax, r8
  [0x10049] jmp 0x0000000000010068
  [0x1004E] jmp 0x0000000000010056
  [0x10053] mov rcx, r14
  [0x10056] xor rcx, rcx
  [0x10059] cmp r8, rcx
  [0x1005C] jnz 0x000000000001000E
  [0x10062] mov r9, r14
  [0x10065] mov rax, r14
  [0x10068] ret


[(method pickup-collectable! fact-info-target)]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x28
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] movdqa [rsp+0x10], xmm9
  [0x10011] push rbx
  [0x10012] push rbp
  [0x10013] push r10
  [0x10015] push r11
  [0x10017] push r12
  [0x10019] sub rsp, 0x58
  [0x1001D] mov r11, rdi
  [0x10020] mov rbx, rsi
  [0x10023] mov rbp, rdx
  [0x10026] mov r12, rcx
  [0x10029] mov r9, rbx
  [0x1002C] mov r8d, 0x04
  [0x10032] cmp r9, r8
  [0x10035] jnz 0x000000000001052E
  [0x1003B] movd xmm7, ebp
  [0x1003F] movss xmm6, dword ptr [0x0000000000010047]
  [0x10047] ucomiss xmm7, xmm6
  [0x1004A] jb 0x0000000000010357
  [0x10050] movss xmm7, dword ptr [0x0000000000010058]
  [0x10058] movd xmm6, ebp
  [0x1005C] ucomiss xmm7, xmm6
  [0x1005F] jnb 0x0000000000010280
  [0x10065] mov r9, r12
  [0x10068] mov r8, r9
  [0x1006B] shl r8, 0x20
  [0x1006F] shr r8, 0x20
  [0x10073] mov rcx, r14
  [0x10076] cmp r8, rcx
  [0x10079] jz 0x00000000000100B0
  [0x1007F] mov r8, r9
  [0x10082] shl r8, 0x20
  [0x10086] shr r8, 0x20
  [0x1008A] mov r8d, [r15+r8*1]
  [0x1008E] sar r9, 0x20
  [0x10092] movsxd rcx, dword ptr [r15+r8*1+0x24]
  [0x10097] cmp r9, rcx
  [0x1009A] jnz 0x00000000000100A5
  [0x100A0] jmp 0x00000000000100A8
  [0x100A5] mov r8, r14
  [0x100A8] mov r9, r8
  [0x100AB] jmp 0x00000000000100B3
  [0x100B0] mov r9, r14
  [0x100B3] mov r8, [r15+r11*1+0x5C]
  [0x100B8] mov rcx, r8
  [0x100BB] shl rcx, 0x20
  [0x100BF] shr rcx, 0x20
  [0x100C3] mov rdx, r14
  [0x100C6] cmp rcx, rdx
  [0x100C9] jz 0x0000000000010100
  [0x100CF] mov rcx, r8
  [0x100D2] shl rcx, 0x20
  [0x100D6] shr rcx, 0x20
  [0x100DA] mov ecx, [r15+rcx*1]
  [0x100DE] sar r8, 0x20
  [0x100E2] movsxd rdx, dword ptr [r15+rcx*1+0x24]
  [0x100E7] cmp r8, rdx
  [0x100EA] jnz 0x00000000000100F5
  [0x100F0] jmp 0x00000000000100F8
  [0x100F5] mov rcx, r14
  [0x100F8] mov r8, rcx
  [0x100FB] jmp 0x0000000000010103
  [0x10100] mov r8, r14
  [0x10103] mov rcx, r14
  [0x10106] cmp r9, r8
  [0x10109] jz 0x0000000000010114
  [0x1010F] lea rcx, [r14+0x08]
  [0x10114] mov r9, rcx
  [0x10117] mov r8, r14
  [0x1011A] cmp r9, r8
  [0x1011D] jnz 0x0000000000010155
  [0x10123] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1012B] mov r9, [r15+r9*1+0x30C]
  [0x10133] mov r8, [r15+r11*1+0x64]
  [0x10138] sub r9, r8
  [0x1013B] mov r8d, 0x96
  [0x10141] mov rcx, r14
  [0x10144] cmp r9, r8
  [0x10147] jl 0x0000000000010152
  [0x1014D] lea rcx, [r14+0x08]
  [0x10152] mov r9, rcx
  [0x10155] mov r8, r14
  [0x10158] cmp r9, r8
  [0x1015B] jz 0x00000000000101FC
  [0x10161] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10169] mov r9, 0x656572672D746567
  [0x10173] movq xmm7, r9
  [0x10178] mov r9, 0x6F63652D6E
  [0x10182] movq xmm8, r9
  [0x10187] vpunpcklqdq xmm8, xmm7, xmm8
  [0x1018C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10194] add r9, r15
  [0x10197] call r9
  [0x1019A] movss xmm7, dword ptr [0x00000000000101A2]
  [0x101A2] movss xmm6, dword ptr [0x00000000000101AA]
  [0x101AA] divss xmm7, xmm6
  [0x101AE] movss xmm6, dword ptr [0x00000000000101B6]
  [0x101B6] mulss xmm7, xmm6
  [0x101BA] cvttss2si esi, xmm7
  [0x101BE] movsxd rsi, esi
  [0x101C1] movss xmm7, dword ptr [0x00000000000101C9]
  [0x101C9] xor r9, r9
  [0x101CC] cvtsi2ss xmm6, r9d
  [0x101D1] mulss xmm7, xmm6
  [0x101D5] cvttss2si edx, xmm7
  [0x101D9] movsxd rdx, edx
  [0x101DC] xor rcx, rcx
  [0x101DF] mov r8d, 0x01
  [0x101E5] lea r9, [r14+0x08]
  [0x101EA] vmovaps xmm1, xmm8
  [0x101EE] mov rdi, rax
  [0x101F1] add r10, r15
  [0x101F4] call r10
  [0x101F7] jmp 0x00000000000101FF
  [0x101FC] mov rax, r14
  [0x101FF] mov r9, r12
  [0x10202] mov r8, r9
  [0x10205] shl r8, 0x20
  [0x10209] shr r8, 0x20
  [0x1020D] mov rcx, r14
  [0x10210] cmp r8, rcx
  [0x10213] jz 0x000000000001024A
  [0x10219] mov r8, r9
  [0x1021C] shl r8, 0x20
  [0x10220] shr r8, 0x20
  [0x10224] mov r8d, [r15+r8*1]
  [0x10228] sar r9, 0x20
  [0x1022C] movsxd rcx, dword ptr [r15+r8*1+0x24]
  [0x10231] cmp r9, rcx
  [0x10234] jnz 0x000000000001023F
  [0x1023A] jmp 0x0000000000010242
  [0x1023F] mov r8, r14
  [0x10242] mov r9, r8
  [0x10245] jmp 0x000000000001024D
  [0x1024A] mov r9, r14
  [0x1024D] mov r8, r14
  [0x10250] cmp r9, r8
  [0x10253] jz 0x0000000000010278
  [0x10259] mov [r15+r11*1+0x5C], r12
  [0x1025E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10266] mov r9, [r15+r9*1+0x30C]
  [0x1026E] mov [r15+r11*1+0x64], r9
  [0x10273] jmp 0x000000000001027B
  [0x10278] mov r9, r14
  [0x1027B] jmp 0x0000000000010283
  [0x10280] mov r9, r14
  [0x10283] movss xmm7, dword ptr [r15+r11*1+0x3C]
  [0x1028A] movss xmm6, dword ptr [r15+r11*1+0x40]
  [0x10291] ucomiss xmm7, xmm6
  [0x10294] jnz 0x0000000000010308
  [0x1029A] mov esi, 0x07
  [0x1029F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102A7] movss xmm7, dword ptr [r15+r9*1+0x2C]
  [0x102AE] mov r9d, [r15+r11*1]
  [0x102B2] mov r8, r14
  [0x102B5] cmp r9, r8
  [0x102B8] jz 0x00000000000102C8
  [0x102BE] mov r9d, [r15+r9*1+0x14]
  [0x102C3] jmp 0x00000000000102CB
  [0x102C8] mov r9, r14
  [0x102CB] mov r8d, [r15+r9*1]
  [0x102CF] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x102D4] xor rcx, rcx
  [0x102D7] shl r9, 0x20
  [0x102DB] shr r9, 0x20
  [0x102DF] or rcx, r9
  [0x102E2] shl r8, 0x20
  [0x102E6] or rcx, r8
  [0x102E9] mov r9d, [r15+r11*1-0x04]
  [0x102EE] mov r9d, [r15+r9*1+0x3C]
  [0x102F3] mov rdi, r11
  [0x102F6] movd edx, xmm7
  [0x102FA] movsxd rdx, edx
  [0x102FD] add r9, r15
  [0x10300] call r9
  [0x10303] jmp 0x000000000001030B
  [0x10308] mov rax, r14
  [0x1030B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10313] mov r9, [r15+r9*1+0x30C]
  [0x1031B] mov [r15+r11*1+0x54], r9
  [0x10320] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10328] movss xmm7, dword ptr [r15+r11*1+0x3C]
  [0x1032F] movss xmm6, dword ptr [r15+r11*1+0x40]
  [0x10336] movd edi, xmm7
  [0x1033A] movsxd rdi, edi
  [0x1033D] movd esi, xmm6
  [0x10341] movsxd rsi, esi
  [0x10344] mov rdx, rbp
  [0x10347] add r9, r15
  [0x1034A] call r9
  [0x1034D] mov [r15+r11*1+0x3C], eax
  [0x10352] jmp 0x000000000001044E
  [0x10357] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1035F] movss xmm7, dword ptr [r15+r11*1+0x3C]
  [0x10366] movss xmm6, dword ptr [0x000000000001036E]
  [0x1036E] movss xmm5, dword ptr [0x0000000000010376]
  [0x10376] movd xmm4, ebp
  [0x1037A] subss xmm5, xmm4
  [0x1037E] movd edi, xmm7
  [0x10382] movsxd rdi, edi
  [0x10385] movd esi, xmm6
  [0x10389] movsxd rsi, esi
  [0x1038C] movd edx, xmm5
  [0x10390] movsxd rdx, edx
  [0x10393] add r9, r15
  [0x10396] call r9
  [0x10399] mov [r15+r11*1+0x3C], eax
  [0x1039E] movd xmm7, ebp
  [0x103A2] movss xmm6, dword ptr [0x00000000000103AA]
  [0x103AA] ucomiss xmm7, xmm6
  [0x103AD] jb 0x00000000000103E2
  [0x103B3] mov esi, 0x07
  [0x103B8] movss xmm7, dword ptr [0x00000000000103C0]
  [0x103C0] mov r9d, [r15+r11*1-0x04]
  [0x103C5] mov r9d, [r15+r9*1+0x3C]
  [0x103CA] mov rdi, r11
  [0x103CD] movd edx, xmm7
  [0x103D1] movsxd rdx, edx
  [0x103D4] mov rcx, r12
  [0x103D7] add r9, r15
  [0x103DA] call r9
  [0x103DD] jmp 0x00000000000103E5
  [0x103E2] mov rax, r14
  [0x103E5] movss xmm7, dword ptr [r15+r11*1+0x3C]
  [0x103EC] movss xmm6, dword ptr [0x00000000000103F4]
  [0x103F4] ucomiss xmm7, xmm6
  [0x103F7] jnz 0x000000000001044B
  [0x103FD] mov r9d, [r15+r11*1]
  [0x10401] mov edi, [r15+r9*1+0xB4]
  [0x10409] lea rsi, [r14+0xAFECAFE]
  [0x10411] movss xmm7, dword ptr [0x0000000000010419]
  [0x10419] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10421] movss xmm6, dword ptr [r15+r9*1+0x08]
  [0x10428] subss xmm7, xmm6
  [0x1042C] mov r9d, [r15+rdi*1-0x04]
  [0x10431] mov r9d, [r15+r9*1+0x38]
  [0x10436] movd edx, xmm7
  [0x1043A] movsxd rdx, edx
  [0x1043D] mov rcx, r12
  [0x10440] add r9, r15
  [0x10443] call r9
  [0x10446] jmp 0x000000000001044E
  [0x1044B] mov rax, r14
  [0x1044E] mov r9d, [r15+r11*1]
  [0x10452] mov r9d, [r15+r9*1+0x6C]
  [0x10457] mov r9d, [r15+r9*1+0x9C]
  [0x1045F] mov r9d, [r15+r9*1+0x24]
  [0x10464] mov r8d, 0x200
  [0x1046A] and r9, r8
  [0x1046D] xor r8, r8
  [0x10470] mov rcx, r14
  [0x10473] cmp r9, r8
  [0x10476] jz 0x0000000000010481
  [0x1047C] lea rcx, [r14+0x08]
  [0x10481] mov r9, rcx
  [0x10484] mov r8, r14
  [0x10487] cmp r9, r8
  [0x1048A] jz 0x00000000000104FC
  [0x10490] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10498] mov r8, r12
  [0x1049B] mov rcx, r8
  [0x1049E] shl rcx, 0x20
  [0x104A2] shr rcx, 0x20
  [0x104A6] mov rdx, r14
  [0x104A9] cmp rcx, rdx
  [0x104AC] jz 0x00000000000104E3
  [0x104B2] mov rcx, r8
  [0x104B5] shl rcx, 0x20
  [0x104B9] shr rcx, 0x20
  [0x104BD] mov ecx, [r15+rcx*1]
  [0x104C1] sar r8, 0x20
  [0x104C5] movsxd rdx, dword ptr [r15+rcx*1+0x24]
  [0x104CA] cmp r8, rdx
  [0x104CD] jnz 0x00000000000104D8
  [0x104D3] jmp 0x00000000000104DB
  [0x104D8] mov rcx, r14
  [0x104DB] mov r8, rcx
  [0x104DE] jmp 0x00000000000104E6
  [0x104E3] mov r8, r14
  [0x104E6] mov edi, [r15+r8*1-0x04]
  [0x104EB] mov esi, [r15+r14*1+0xBADBEEF]
  [0x104F3] add r9, r15
  [0x104F6] call r9
  [0x104F9] mov r9, rax
  [0x104FC] nop
  [0x104FD] mov r8, r14
  [0x10500] cmp r9, r8
  [0x10503] jz 0x0000000000010518
  [0x10509] lea r9, [r14-0x0A]
  [0x1050E] jmp 0x00000000000109AD
  [0x10513] jmp 0x000000000001051B
  [0x10518] mov r9, r14
  [0x1051B] movss xmm7, dword ptr [r15+r11*1+0x3C]
  [0x10522] movd eax, xmm7
  [0x10526] movsxd rax, eax
  [0x10529] jmp 0x00000000000112BF
  [0x1052E] mov r8d, 0x07
  [0x10534] cmp r9, r8
  [0x10537] jnz 0x00000000000106A7
  [0x1053D] movd xmm7, ebp
  [0x10541] movss xmm6, dword ptr [0x0000000000010549]
  [0x10549] ucomiss xmm7, xmm6
  [0x1054C] jb 0x0000000000010691
  [0x10552] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1055A] mov r9, [r15+r9*1+0x30C]
  [0x10562] mov [r15+r11*1+0x84], r9
  [0x1056A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10572] movss xmm7, dword ptr [r15+r11*1+0x4C]
  [0x10579] movss xmm6, dword ptr [r15+r11*1+0x50]
  [0x10580] movd edi, xmm7
  [0x10584] movsxd rdi, edi
  [0x10587] movd esi, xmm6
  [0x1058B] movsxd rsi, esi
  [0x1058E] mov rdx, rbp
  [0x10591] add r9, r15
  [0x10594] call r9
  [0x10597] mov [r15+r11*1+0x4C], eax
  [0x1059C] movss xmm7, dword ptr [r15+r11*1+0x4C]
  [0x105A3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105AB] movss xmm6, dword ptr [r15+r9*1+0x2C]
  [0x105B2] mov r9, r14
  [0x105B5] ucomiss xmm7, xmm6
  [0x105B8] jb 0x00000000000105C3
  [0x105BE] lea r9, [r14+0x08]
  [0x105C3] mov r8, r14
  [0x105C6] cmp r9, r8
  [0x105C9] jz 0x00000000000105EE
  [0x105CF] movss xmm7, dword ptr [r15+r11*1+0x3C]
  [0x105D6] movss xmm6, dword ptr [r15+r11*1+0x40]
  [0x105DD] mov r9, r14
  [0x105E0] ucomiss xmm7, xmm6
  [0x105E3] jnb 0x00000000000105EE
  [0x105E9] lea r9, [r14+0x08]
  [0x105EE] mov r8, r14
  [0x105F1] cmp r9, r8
  [0x105F4] jz 0x0000000000010689
  [0x105FA] movss xmm7, dword ptr [r15+r11*1+0x4C]
  [0x10601] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10609] movss xmm6, dword ptr [r15+r9*1+0x2C]
  [0x10610] subss xmm7, xmm6
  [0x10614] movss [r15+r11*1+0x4C], xmm7
  [0x1061B] mov esi, 0x04
  [0x10620] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10628] movss xmm7, dword ptr [r15+r9*1+0x30]
  [0x1062F] mov r9d, [r15+r11*1]
  [0x10633] mov r8, r14
  [0x10636] cmp r9, r8
  [0x10639] jz 0x0000000000010649
  [0x1063F] mov r9d, [r15+r9*1+0x14]
  [0x10644] jmp 0x000000000001064C
  [0x10649] mov r9, r14
  [0x1064C] mov r8d, [r15+r9*1]
  [0x10650] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x10655] xor rcx, rcx
  [0x10658] shl r9, 0x20
  [0x1065C] shr r9, 0x20
  [0x10660] or rcx, r9
  [0x10663] shl r8, 0x20
  [0x10667] or rcx, r8
  [0x1066A] mov r9d, [r15+r11*1-0x04]
  [0x1066F] mov r9d, [r15+r9*1+0x3C]
  [0x10674] mov rdi, r11
  [0x10677] movd edx, xmm7
  [0x1067B] movsxd rdx, edx
  [0x1067E] add r9, r15
  [0x10681] call r9
  [0x10684] jmp 0x000000000001068C
  [0x10689] mov rax, r14
  [0x1068C] jmp 0x0000000000010694
  [0x10691] mov rax, r14
  [0x10694] movss xmm7, dword ptr [r15+r11*1+0x4C]
  [0x1069B] movd eax, xmm7
  [0x1069F] movsxd rax, eax
  [0x106A2] jmp 0x00000000000112BF
  [0x106A7] mov r8d, 0x05
  [0x106AD] cmp r9, r8
  [0x106B0] jnz 0x00000000000107E5
  [0x106B6] movss xmm7, dword ptr [0x00000000000106BE]
  [0x106BE] movd xmm6, ebp
  [0x106C2] ucomiss xmm7, xmm6
  [0x106C5] jnb 0x00000000000107B3
  [0x106CB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x106D3] add r9, r15
  [0x106D6] call r9
  [0x106D9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x106E1] mov r9, [r15+r9*1+0x30C]
  [0x106E9] mov r8, [r15+r11*1+0x6C]
  [0x106EE] sub r9, r8
  [0x106F1] mov r8d, 0x0F
  [0x106F7] cmp r9, r8
  [0x106FA] jl 0x0000000000010796
  [0x10700] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x10708] mov r9, 0x69702D79656E6F6D
  [0x10712] movq xmm7, r9
  [0x10717] mov r9d, 0x70756B63
  [0x1071D] movq xmm8, r9
  [0x10722] vpunpcklqdq xmm8, xmm7, xmm8
  [0x10727] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1072F] add r9, r15
  [0x10732] call r9
  [0x10735] movss xmm7, dword ptr [0x000000000001073D]
  [0x1073D] movss xmm6, dword ptr [0x0000000000010745]
  [0x10745] divss xmm7, xmm6
  [0x10749] movss xmm6, dword ptr [0x0000000000010751]
  [0x10751] mulss xmm7, xmm6
  [0x10755] cvttss2si esi, xmm7
  [0x10759] movsxd rsi, esi
  [0x1075C] movss xmm7, dword ptr [0x0000000000010764]
  [0x10764] xor r9, r9
  [0x10767] cvtsi2ss xmm6, r9d
  [0x1076C] mulss xmm7, xmm6
  [0x10770] cvttss2si edx, xmm7
  [0x10774] movsxd rdx, edx
  [0x10777] xor rcx, rcx
  [0x1077A] mov r8d, 0x01
  [0x10780] lea r9, [r14+0x08]
  [0x10785] vmovaps xmm1, xmm8
  [0x10789] mov rdi, rax
  [0x1078C] add rbx, r15
  [0x1078F] call rbx
  [0x10791] jmp 0x0000000000010799
  [0x10796] mov rax, r14
  [0x10799] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x107A1] mov r9, [r15+r9*1+0x30C]
  [0x107A9] mov [r15+r11*1+0x6C], r9
  [0x107AE] jmp 0x00000000000107B6
  [0x107B3] mov r9, r14
  [0x107B6] mov r9d, [r15+r11*1]
  [0x107BA] mov edi, [r15+r9*1+0xB4]
  [0x107C2] lea rsi, [r14+0xAFECAFE]
  [0x107CA] mov r9d, [r15+rdi*1-0x04]
  [0x107CF] mov r9d, [r15+r9*1+0x38]
  [0x107D4] mov rdx, rbp
  [0x107D7] mov rcx, r12
  [0x107DA] add r9, r15
  [0x107DD] call r9
  [0x107E0] jmp 0x00000000000112BF
  [0x107E5] mov r8d, 0x06
  [0x107EB] cmp r9, r8
  [0x107EE] jnz 0x00000000000108A7
  [0x107F4] movd xmm7, ebp
  [0x107F8] cvttss2si ebx, xmm7
  [0x107FC] movsxd rbx, ebx
  [0x107FF] mov r9d, [r15+r11*1]
  [0x10803] mov edi, [r15+r9*1+0xB4]
  [0x1080B] mov rsi, rbx
  [0x1080E] mov r9d, [r15+rdi*1-0x04]
  [0x10813] mov r9d, [r15+r9*1+0x3C]
  [0x10818] add r9, r15
  [0x1081B] call r9
  [0x1081E] mov r9, r14
  [0x10821] cmp rax, r9
  [0x10824] jnz 0x0000000000010841
  [0x1082A] mov r9d, 0x01
  [0x10830] mov rax, r14
  [0x10833] cmp r9, rbx
  [0x10836] jb 0x0000000000010841
  [0x1083C] lea rax, [r14+0x08]
  [0x10841] mov r9, r14
  [0x10844] cmp rax, r9
  [0x10847] jnz 0x0000000000010875
  [0x1084D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10855] add r9, r15
  [0x10858] call r9
  [0x1085B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10863] mov r9, [r15+r9*1+0x30C]
  [0x1086B] mov [r15+r11*1+0x7C], r9
  [0x10870] jmp 0x0000000000010878
  [0x10875] mov r9, r14
  [0x10878] mov r9d, [r15+r11*1]
  [0x1087C] mov edi, [r15+r9*1+0xB4]
  [0x10884] lea rsi, [r14+0xAFECAFE]
  [0x1088C] mov r9d, [r15+rdi*1-0x04]
  [0x10891] mov r9d, [r15+r9*1+0x38]
  [0x10896] mov rdx, rbp
  [0x10899] mov rcx, r12
  [0x1089C] add r9, r15
  [0x1089F] call r9
  [0x108A2] jmp 0x00000000000112BF
  [0x108A7] mov r8d, 0x08
  [0x108AD] cmp r9, r8
  [0x108B0] jnz 0x000000000001093B
  [0x108B6] mov r9d, [r15+r11*1]
  [0x108BA] mov edi, [r15+r9*1+0xB4]
  [0x108C2] lea rsi, [r14+0xAFECAFE]
  [0x108CA] mov r9d, [r15+rdi*1-0x04]
  [0x108CF] mov r9d, [r15+r9*1+0x38]
  [0x108D4] mov rdx, rbp
  [0x108D7] mov rcx, r12
  [0x108DA] add r9, r15
  [0x108DD] call r9
  [0x108E0] movd xmm8, eax
  [0x108E5] movss xmm7, dword ptr [r15+r11*1+0x44]
  [0x108EC] ucomiss xmm8, xmm7
  [0x108F0] jz 0x000000000001091E
  [0x108F6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x108FE] add r9, r15
  [0x10901] call r9
  [0x10904] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1090C] mov r9, [r15+r9*1+0x30C]
  [0x10914] mov [r15+r11*1+0x74], r9
  [0x10919] jmp 0x0000000000010921
  [0x1091E] mov r9, r14
  [0x10921] movss [r15+r11*1+0x44], xmm8
  [0x10928] movss xmm7, dword ptr [r15+r11*1+0x44]
  [0x1092F] movd eax, xmm7
  [0x10933] movsxd rax, eax
  [0x10936] jmp 0x00000000000112BF
  [0x1093B] mov r8d, 0x02
  [0x10941] mov rcx, r14
  [0x10944] cmp r9, r8
  [0x10947] jnz 0x0000000000010952
  [0x1094D] lea rcx, [r14+0x08]
  [0x10952] mov r8, rcx
  [0x10955] mov rcx, r14
  [0x10958] cmp r8, rcx
  [0x1095B] jnz 0x00000000000109A1
  [0x10961] mov r8d, 0x03
  [0x10967] mov rcx, r14
  [0x1096A] cmp r9, r8
  [0x1096D] jnz 0x0000000000010978
  [0x10973] lea rcx, [r14+0x08]
  [0x10978] mov r8, rcx
  [0x1097B] mov rcx, r14
  [0x1097E] cmp r8, rcx
  [0x10981] jnz 0x00000000000109A1
  [0x10987] mov r8d, 0x01
  [0x1098D] mov rcx, r14
  [0x10990] cmp r9, r8
  [0x10993] jnz 0x000000000001099E
  [0x10999] lea rcx, [r14+0x08]
  [0x1099E] mov r8, rcx
  [0x109A1] mov r9, r14
  [0x109A4] cmp r8, r9
  [0x109A7] jz 0x00000000000112A0
  [0x109AD] movd xmm7, ebp
  [0x109B1] movss xmm6, dword ptr [0x00000000000109B9]
  [0x109B9] ucomiss xmm7, xmm6
  [0x109BC] jnz 0x00000000000109FC
  [0x109C2] movsxd r9, dword ptr [r15+r11*1+0x24]
  [0x109C7] cmp r9, rbx
  [0x109CA] jnz 0x00000000000109E3
  [0x109D0] movss xmm7, dword ptr [r15+r11*1+0x28]
  [0x109D7] movd eax, xmm7
  [0x109DB] movsxd rax, eax
  [0x109DE] jmp 0x00000000000109F2
  [0x109E3] movss xmm7, dword ptr [0x00000000000109EB]
  [0x109EB] movd eax, xmm7
  [0x109EF] movsxd rax, eax
  [0x109F2] jmp 0x00000000000112BF
  [0x109F7] jmp 0x00000000000109FF
  [0x109FC] mov r9, r14
  [0x109FF] movsxd r9, dword ptr [r15+r11*1+0x24]
  [0x10A04] cmp r9, rbx
  [0x10A07] jz 0x0000000000010A29
  [0x10A0D] movss xmm7, dword ptr [0x0000000000010A15]
  [0x10A15] movss [r15+r11*1+0x28], xmm7
  [0x10A1C] xor r9, r9
  [0x10A1F] mov [r15+r11*1+0x34], r9
  [0x10A24] jmp 0x0000000000010A2C
  [0x10A29] mov r9, r14
  [0x10A2C] mov [r15+r11*1+0x24], ebx
  [0x10A31] movss xmm8, dword ptr [r15+r11*1+0x28]
  [0x10A38] movss xmm7, dword ptr [0x0000000000010A40]
  [0x10A40] movss [r15+r11*1+0x28], xmm7
  [0x10A47] movss xmm7, dword ptr [0x0000000000010A4F]
  [0x10A4F] mov r9, r14
  [0x10A52] ucomiss xmm8, xmm7
  [0x10A56] jnz 0x0000000000010A61
  [0x10A5C] lea r9, [r14+0x08]
  [0x10A61] mov r8, r14
  [0x10A64] cmp r9, r8
  [0x10A67] jz 0x0000000000010A8D
  [0x10A6D] movss xmm7, dword ptr [0x0000000000010A75]
  [0x10A75] movss xmm6, dword ptr [r15+r11*1+0x28]
  [0x10A7C] mov r9, r14
  [0x10A7F] ucomiss xmm7, xmm6
  [0x10A82] jnb 0x0000000000010A8D
  [0x10A88] lea r9, [r14+0x08]
  [0x10A8D] mov r8, r14
  [0x10A90] cmp r9, r8
  [0x10A93] jz 0x0000000000010AE5
  [0x10A99] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10AA1] mov r9, [r15+r9*1+0x314]
  [0x10AA9] mov [r15+r11*1+0x2C], r9
  [0x10AAE] mov rsi, rsp
  [0x10AB1] sub rsi, r15
  [0x10AB4] mov [r15+rsi*1+0x04], r13d
  [0x10AB9] xor r9, r9
  [0x10ABC] mov [r15+rsi*1+0x08], r9d
  [0x10AC1] lea r9, [r14+0xAFECAFE]
  [0x10AC9] mov [r15+rsi*1+0x0C], r9d
  [0x10ACE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10AD6] mov edi, [r15+r11*1]
  [0x10ADA] add r9, r15
  [0x10ADD] call r9
  [0x10AE0] jmp 0x0000000000010AE8
  [0x10AE5] mov rax, r14
  [0x10AE8] mov r9, [r15+r11*1+0x34]
  [0x10AED] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10AF5] mov r8, [r15+r8*1+0x0C]
  [0x10AFA] movd xmm7, ebp
  [0x10AFE] cvttss2si ecx, xmm7
  [0x10B02] movsxd rcx, ecx
  [0x10B05] imul r8d, ecx
  [0x10B09] movsxd r8, r8d
  [0x10B0C] add r9, r8
  [0x10B0F] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10B17] mov r8, [r15+r8*1+0x14]
  [0x10B1C] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x10B24] mov rcx, [r15+rcx*1+0x314]
  [0x10B2C] mov rdx, [r15+r11*1+0x2C]
  [0x10B31] sub rcx, rdx
  [0x10B34] add r8, rcx
  [0x10B37] cmp r9, r8
  [0x10B3A] jle 0x0000000000010B45
  [0x10B40] jmp 0x0000000000010B48
  [0x10B45] mov r8, r9
  [0x10B48] mov [r15+r11*1+0x34], r8
  [0x10B4D] mov r9, [r15+r11*1+0x34]
  [0x10B52] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10B5A] mov r8, [r15+r8*1+0x314]
  [0x10B62] mov rcx, [r15+r11*1+0x2C]
  [0x10B67] sub r8, rcx
  [0x10B6A] sub r9, r8
  [0x10B6D] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10B75] mov r8, [r15+r8*1+0x14]
  [0x10B7A] cmp r9, r8
  [0x10B7D] jl 0x0000000000010B9F
  [0x10B83] movss xmm7, dword ptr [0x0000000000010B8B]
  [0x10B8B] movss [r15+r11*1+0x28], xmm7
  [0x10B92] movd r9d, xmm7
  [0x10B97] movsxd r9, r9d
  [0x10B9A] jmp 0x0000000000010BA2
  [0x10B9F] mov r9, r14
  [0x10BA2] mov r9, r12
  [0x10BA5] mov r8, r9
  [0x10BA8] shl r8, 0x20
  [0x10BAC] shr r8, 0x20
  [0x10BB0] mov rcx, r14
  [0x10BB3] cmp r8, rcx
  [0x10BB6] jz 0x0000000000010BED
  [0x10BBC] mov r8, r9
  [0x10BBF] shl r8, 0x20
  [0x10BC3] shr r8, 0x20
  [0x10BC7] mov r8d, [r15+r8*1]
  [0x10BCB] sar r9, 0x20
  [0x10BCF] movsxd rcx, dword ptr [r15+r8*1+0x24]
  [0x10BD4] cmp r9, rcx
  [0x10BD7] jnz 0x0000000000010BE2
  [0x10BDD] jmp 0x0000000000010BE5
  [0x10BE2] mov r8, r14
  [0x10BE5] mov r9, r8
  [0x10BE8] jmp 0x0000000000010BF0
  [0x10BED] mov r9, r14
  [0x10BF0] mov r8, [r15+r11*1+0x5C]
  [0x10BF5] mov rcx, r8
  [0x10BF8] shl rcx, 0x20
  [0x10BFC] shr rcx, 0x20
  [0x10C00] mov rdx, r14
  [0x10C03] cmp rcx, rdx
  [0x10C06] jz 0x0000000000010C3D
  [0x10C0C] mov rcx, r8
  [0x10C0F] shl rcx, 0x20
  [0x10C13] shr rcx, 0x20
  [0x10C17] mov ecx, [r15+rcx*1]
  [0x10C1B] sar r8, 0x20
  [0x10C1F] movsxd rdx, dword ptr [r15+rcx*1+0x24]
  [0x10C24] cmp r8, rdx
  [0x10C27] jnz 0x0000000000010C32
  [0x10C2D] jmp 0x0000000000010C35
  [0x10C32] mov rcx, r14
  [0x10C35] mov r8, rcx
  [0x10C38] jmp 0x0000000000010C40
  [0x10C3D] mov r8, r14
  [0x10C40] mov rcx, r14
  [0x10C43] cmp r9, r8
  [0x10C46] jnz 0x0000000000010C51
  [0x10C4C] lea rcx, [r14+0x08]
  [0x10C51] mov r9, rcx
  [0x10C54] mov r8, r14
  [0x10C57] cmp r9, r8
  [0x10C5A] jz 0x0000000000010C92
  [0x10C60] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C68] mov r9, [r15+r9*1+0x30C]
  [0x10C70] mov r8, [r15+r11*1+0x64]
  [0x10C75] sub r9, r8
  [0x10C78] mov r8d, 0x96
  [0x10C7E] mov rcx, r14
  [0x10C81] cmp r9, r8
  [0x10C84] jnl 0x0000000000010C8F
  [0x10C8A] lea rcx, [r14+0x08]
  [0x10C8F] mov r9, rcx
  [0x10C92] mov r8, r14
  [0x10C95] cmp r9, r8
  [0x10C98] jnz 0x0000000000010F97
  [0x10C9E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10CA6] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10CAE] mov edi, [r15+r8*1+0x04]
  [0x10CB3] mov esi, 0x01
  [0x10CB8] mov edx, 0x7F
  [0x10CBD] mov ecx, 0x3C
  [0x10CC2] add r9, r15
  [0x10CC5] call r9
  [0x10CC8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10CD0] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10CD8] mov edi, [r15+r8*1+0x04]
  [0x10CDD] xor rsi, rsi
  [0x10CE0] mov edx, 0x11
  [0x10CE5] mov ecx, 0x3C
  [0x10CEA] add r9, r15
  [0x10CED] call r9
  [0x10CF0] mov r9, rbx
  [0x10CF3] mov r8d, 0x03
  [0x10CF9] cmp r9, r8
  [0x10CFC] jnz 0x0000000000010D98
  [0x10D02] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10D0A] mov r9, 0x65756C622D746567
  [0x10D14] movq xmm7, r9
  [0x10D19] mov r9d, 0x6F63652D
  [0x10D1F] movq xmm9, r9
  [0x10D24] vpunpcklqdq xmm9, xmm7, xmm9
  [0x10D29] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10D31] add r9, r15
  [0x10D34] call r9
  [0x10D37] movss xmm7, dword ptr [0x0000000000010D3F]
  [0x10D3F] movss xmm6, dword ptr [0x0000000000010D47]
  [0x10D47] divss xmm7, xmm6
  [0x10D4B] movss xmm6, dword ptr [0x0000000000010D53]
  [0x10D53] mulss xmm7, xmm6
  [0x10D57] cvttss2si esi, xmm7
  [0x10D5B] movsxd rsi, esi
  [0x10D5E] movss xmm7, dword ptr [0x0000000000010D66]
  [0x10D66] xor r9, r9
  [0x10D69] cvtsi2ss xmm6, r9d
  [0x10D6E] mulss xmm7, xmm6
  [0x10D72] cvttss2si edx, xmm7
  [0x10D76] movsxd rdx, edx
  [0x10D79] xor rcx, rcx
  [0x10D7C] mov r8d, 0x01
  [0x10D82] lea r9, [r14+0x08]
  [0x10D87] vmovaps xmm1, xmm9
  [0x10D8B] mov rdi, rax
  [0x10D8E] add rbp, r15
  [0x10D91] call rbp
  [0x10D93] jmp 0x0000000000010F92
  [0x10D98] mov r8d, 0x04
  [0x10D9E] cmp r9, r8
  [0x10DA1] jnz 0x0000000000010E41
  [0x10DA7] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10DAF] mov r9, 0x656572672D746567
  [0x10DB9] movq xmm7, r9
  [0x10DBE] mov r9, 0x6F63652D6E
  [0x10DC8] movq xmm9, r9
  [0x10DCD] vpunpcklqdq xmm9, xmm7, xmm9
  [0x10DD2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10DDA] add r9, r15
  [0x10DDD] call r9
  [0x10DE0] movss xmm7, dword ptr [0x0000000000010DE8]
  [0x10DE8] movss xmm6, dword ptr [0x0000000000010DF0]
  [0x10DF0] divss xmm7, xmm6
  [0x10DF4] movss xmm6, dword ptr [0x0000000000010DFC]
  [0x10DFC] mulss xmm7, xmm6
  [0x10E00] cvttss2si esi, xmm7
  [0x10E04] movsxd rsi, esi
  [0x10E07] movss xmm7, dword ptr [0x0000000000010E0F]
  [0x10E0F] xor r9, r9
  [0x10E12] cvtsi2ss xmm6, r9d
  [0x10E17] mulss xmm7, xmm6
  [0x10E1B] cvttss2si edx, xmm7
  [0x10E1F] movsxd rdx, edx
  [0x10E22] xor rcx, rcx
  [0x10E25] mov r8d, 0x01
  [0x10E2B] lea r9, [r14+0x08]
  [0x10E30] vmovaps xmm1, xmm9
  [0x10E34] mov rdi, rax
  [0x10E37] add rbp, r15
  [0x10E3A] call rbp
  [0x10E3C] jmp 0x0000000000010F92
  [0x10E41] mov r8d, 0x01
  [0x10E47] cmp r9, r8
  [0x10E4A] jnz 0x0000000000010EEA
  [0x10E50] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10E58] mov r9, 0x6C6C65792D746567
  [0x10E62] movq xmm7, r9
  [0x10E67] mov r9, 0x6F63652D776F
  [0x10E71] movq xmm9, r9
  [0x10E76] vpunpcklqdq xmm9, xmm7, xmm9
  [0x10E7B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10E83] add r9, r15
  [0x10E86] call r9
  [0x10E89] movss xmm7, dword ptr [0x0000000000010E91]
  [0x10E91] movss xmm6, dword ptr [0x0000000000010E99]
  [0x10E99] divss xmm7, xmm6
  [0x10E9D] movss xmm6, dword ptr [0x0000000000010EA5]
  [0x10EA5] mulss xmm7, xmm6
  [0x10EA9] cvttss2si esi, xmm7
  [0x10EAD] movsxd rsi, esi
  [0x10EB0] movss xmm7, dword ptr [0x0000000000010EB8]
  [0x10EB8] xor r9, r9
  [0x10EBB] cvtsi2ss xmm6, r9d
  [0x10EC0] mulss xmm7, xmm6
  [0x10EC4] cvttss2si edx, xmm7
  [0x10EC8] movsxd rdx, edx
  [0x10ECB] xor rcx, rcx
  [0x10ECE] mov r8d, 0x01
  [0x10ED4] lea r9, [r14+0x08]
  [0x10ED9] vmovaps xmm1, xmm9
  [0x10EDD] mov rdi, rax
  [0x10EE0] add rbp, r15
  [0x10EE3] call rbp
  [0x10EE5] jmp 0x0000000000010F92
  [0x10EEA] mov r8d, 0x02
  [0x10EF0] cmp r9, r8
  [0x10EF3] jnz 0x0000000000010F8F
  [0x10EF9] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10F01] mov r9, 0x2D6465722D746567
  [0x10F0B] movq xmm7, r9
  [0x10F10] mov r9d, 0x6F6365
  [0x10F16] movq xmm9, r9
  [0x10F1B] vpunpcklqdq xmm9, xmm7, xmm9
  [0x10F20] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10F28] add r9, r15
  [0x10F2B] call r9
  [0x10F2E] movss xmm7, dword ptr [0x0000000000010F36]
  [0x10F36] movss xmm6, dword ptr [0x0000000000010F3E]
  [0x10F3E] divss xmm7, xmm6
  [0x10F42] movss xmm6, dword ptr [0x0000000000010F4A]
  [0x10F4A] mulss xmm7, xmm6
  [0x10F4E] cvttss2si esi, xmm7
  [0x10F52] movsxd rsi, esi
  [0x10F55] movss xmm7, dword ptr [0x0000000000010F5D]
  [0x10F5D] xor r9, r9
  [0x10F60] cvtsi2ss xmm6, r9d
  [0x10F65] mulss xmm7, xmm6
  [0x10F69] cvttss2si edx, xmm7
  [0x10F6D] movsxd rdx, edx
  [0x10F70] xor rcx, rcx
  [0x10F73] mov r8d, 0x01
  [0x10F79] lea r9, [r14+0x08]
  [0x10F7E] vmovaps xmm1, xmm9
  [0x10F82] mov rdi, rax
  [0x10F85] add rbp, r15
  [0x10F88] call rbp
  [0x10F8A] jmp 0x0000000000010F92
  [0x10F8F] mov rax, r14
  [0x10F92] jmp 0x0000000000010F9A
  [0x10F97] mov rax, r14
  [0x10F9A] mov [r15+r11*1+0x5C], r12
  [0x10F9F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10FA7] mov r9, [r15+r9*1+0x30C]
  [0x10FAF] mov [r15+r11*1+0x64], r9
  [0x10FB4] mov r9d, 0x03
  [0x10FBA] cmp rbx, r9
  [0x10FBD] jnz 0x000000000001128A
  [0x10FC3] movss xmm7, dword ptr [0x0000000000010FCB]
  [0x10FCB] ucomiss xmm8, xmm7
  [0x10FCF] jnz 0x0000000000011282
  [0x10FD5] mov ebx, [r15+r11*1]
  [0x10FD9] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10FE1] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10FE9] mov edx, 0x4000
  [0x10FEE] mov r9d, [r15+rdi*1-0x04]
  [0x10FF3] mov r9d, [r15+r9*1+0x48]
  [0x10FF8] add r9, r15
  [0x10FFB] call r9
  [0x10FFE] mov rbp, rax
  [0x11001] mov r9, r14
  [0x11004] cmp rbp, r9
  [0x11007] jz 0x000000000001107F
  [0x1100D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11015] mov r9d, [r15+r9*1+0x34]
  [0x1101A] lea rdx, [r14+0xAFECAFE]
  [0x11022] mov ecx, 0x70004000
  [0x11027] mov rdi, rbp
  [0x1102A] mov rsi, rbx
  [0x1102D] add r9, r15
  [0x11030] call r9
  [0x11033] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1103B] mov esi, [r15+r14*1+0xBADBEEF]
  [0x11043] mov edx, 0x0C
  [0x11048] mov r8d, [r15+rbx*1+0x6C]
  [0x1104D] add rdx, r8
  [0x11050] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x11058] movss xmm7, dword ptr [r15+r8*1+0x3C]
  [0x1105F] mov r8d, 0x12C
  [0x11065] mov rdi, rbp
  [0x11068] movd ecx, xmm7
  [0x1106C] movsxd rcx, ecx
  [0x1106F] add r9, r15
  [0x11072] call r9
  [0x11075] mov ebp, [r15+rbp*1+0x14]
  [0x1107A] jmp 0x0000000000011082
  [0x1107F] mov rbp, r14
  [0x11082] mov rsi, rsp
  [0x11085] sub rsi, r15
  [0x11088] mov [r15+rsi*1+0x04], r13d
  [0x1108D] mov r9d, 0x01
  [0x11093] mov [r15+rsi*1+0x08], r9d
  [0x11098] lea r9, [r14+0xAFECAFE]
  [0x110A0] mov [r15+rsi*1+0x0C], r9d
  [0x110A5] mov r9, rbx
  [0x110A8] mov [r15+rsi*1+0x10], r9
  [0x110AD] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x110B5] mov r8, rbp
  [0x110B8] mov rcx, r14
  [0x110BB] cmp r8, rcx
  [0x110BE] jz 0x00000000000110D2
  [0x110C4] mov r8d, [r15+r8*1]
  [0x110C8] mov edi, [r15+r8*1+0x18]
  [0x110CD] jmp 0x00000000000110D5
  [0x110D2] mov rdi, r14
  [0x110D5] add r9, r15
  [0x110D8] call r9
  [0x110DB] mov rsi, rsp
  [0x110DE] sub rsi, r15
  [0x110E1] mov [r15+rsi*1+0x04], r13d
  [0x110E6] mov r9d, 0x01
  [0x110EC] mov [r15+rsi*1+0x08], r9d
  [0x110F1] lea r9, [r14+0xAFECAFE]
  [0x110F9] mov [r15+rsi*1+0x0C], r9d
  [0x110FE] lea r9, [r14+0xAFECAFE]
  [0x11106] mov [r15+rsi*1+0x10], r9
  [0x1110B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11113] mov r8, rbp
  [0x11116] mov rcx, r14
  [0x11119] cmp r8, rcx
  [0x1111C] jz 0x0000000000011130
  [0x11122] mov r8d, [r15+r8*1]
  [0x11126] mov edi, [r15+r8*1+0x18]
  [0x1112B] jmp 0x0000000000011133
  [0x11130] mov rdi, r14
  [0x11133] add r9, r15
  [0x11136] call r9
  [0x11139] mov rsi, rsp
  [0x1113C] sub rsi, r15
  [0x1113F] mov [r15+rsi*1+0x04], r13d
  [0x11144] mov r9d, 0x01
  [0x1114A] mov [r15+rsi*1+0x08], r9d
  [0x1114F] lea r9, [r14+0xAFECAFE]
  [0x11157] mov [r15+rsi*1+0x0C], r9d
  [0x1115C] lea r9, [0x0000000000011163]
  [0x11163] sub r9, r15
  [0x11166] mov [r15+rsi*1+0x10], r9
  [0x1116B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11173] mov r8, rbp
  [0x11176] mov rcx, r14
  [0x11179] cmp r8, rcx
  [0x1117C] jz 0x0000000000011190
  [0x11182] mov r8d, [r15+r8*1]
  [0x11186] mov edi, [r15+r8*1+0x18]
  [0x1118B] jmp 0x0000000000011193
  [0x11190] mov rdi, r14
  [0x11193] add r9, r15
  [0x11196] call r9
  [0x11199] mov rsi, rsp
  [0x1119C] sub rsi, r15
  [0x1119F] mov [r15+rsi*1+0x04], r13d
  [0x111A4] mov r9d, 0x01
  [0x111AA] mov [r15+rsi*1+0x08], r9d
  [0x111AF] lea r9, [r14+0xAFECAFE]
  [0x111B7] mov [r15+rsi*1+0x0C], r9d
  [0x111BC] lea r9, [0x00000000000111C3]
  [0x111C3] sub r9, r15
  [0x111C6] mov [r15+rsi*1+0x10], r9
  [0x111CB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x111D3] mov r8, r14
  [0x111D6] cmp rbp, r8
  [0x111D9] jz 0x00000000000111ED
  [0x111DF] mov r8d, [r15+rbp*1]
  [0x111E3] mov edi, [r15+r8*1+0x18]
  [0x111E8] jmp 0x00000000000111F0
  [0x111ED] mov rdi, r14
  [0x111F0] add r9, r15
  [0x111F3] call r9
  [0x111F6] mov edi, [r15+r14*1+0xBADBEEF]
  [0x111FE] mov esi, [r15+r14*1+0xBADBEEF]
  [0x11206] mov edx, 0x4000
  [0x1120B] mov r9d, [r15+rdi*1-0x04]
  [0x11210] mov r9d, [r15+r9*1+0x48]
  [0x11215] add r9, r15
  [0x11218] call r9
  [0x1121B] mov rbp, rax
  [0x1121E] mov r9, r14
  [0x11221] cmp rbp, r9
  [0x11224] jz 0x000000000001127A
  [0x1122A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11232] mov r9d, [r15+r9*1+0x34]
  [0x11237] lea rdx, [r14+0xAFECAFE]
  [0x1123F] mov ecx, 0x70004000
  [0x11244] mov rdi, rbp
  [0x11247] mov rsi, rbx
  [0x1124A] add r9, r15
  [0x1124D] call r9
  [0x11250] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11258] mov edi, [r15+rbp*1+0x28]
  [0x1125D] lea rsi, [0x0000000000011264]
  [0x11264] sub rsi, r15
  [0x11267] mov rdx, rbx
  [0x1126A] add r9, r15
  [0x1126D] call r9
  [0x11270] mov r9d, [r15+rbp*1+0x14]
  [0x11275] jmp 0x000000000001127D
  [0x1127A] mov r9, r14
  [0x1127D] jmp 0x0000000000011285
  [0x11282] mov r9, r14
  [0x11285] jmp 0x000000000001128D
  [0x1128A] mov r9, r14
  [0x1128D] movss xmm7, dword ptr [r15+r11*1+0x28]
  [0x11294] movd eax, xmm7
  [0x11298] movsxd rax, eax
  [0x1129B] jmp 0x00000000000112BF
  [0x112A0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x112A8] mov r9d, [r15+r9*1+0x3C]
  [0x112AD] mov rdi, r11
  [0x112B0] mov rsi, rbx
  [0x112B3] mov rdx, rbp
  [0x112B6] mov rcx, r12
  [0x112B9] add r9, r15
  [0x112BC] call r9
  [0x112BF] add rsp, 0x58
  [0x112C3] pop r12
  [0x112C5] pop r11
  [0x112C7] pop r10
  [0x112C9] pop rbp
  [0x112CA] pop rbx
  [0x112CB] movdqa xmm9, [rsp+0x10]
  [0x112D2] movdqa xmm8, [rsp]
  [0x112D8] add rsp, 0x28
  [0x112DC] ret


[anon-function-3]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] sub rsp, 0x50
  [0x10008] mov rbx, rdi
  [0x1000B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10013] mov rbp, [r15+r9*1+0x30C]
  [0x1001B] mov rsi, rsp
  [0x1001E] sub rsi, r15
  [0x10021] mov [r15+rsi*1+0x04], r13d
  [0x10026] mov r9d, 0x01
  [0x1002C] mov [r15+rsi*1+0x08], r9d
  [0x10031] lea r9, [r14+0xAFECAFE]
  [0x10039] mov [r15+rsi*1+0x0C], r9d
  [0x1003E] lea r9, [r14+0xAFECAFE]
  [0x10046] mov [r15+rsi*1+0x10], r9
  [0x1004B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10053] mov rdi, rbx
  [0x10056] add r9, r15
  [0x10059] call r9
  [0x1005C] mov r9, rsp
  [0x1005F] sub r9, r15
  [0x10062] mov r8, r13
  [0x10065] mov r8d, [r15+r8*1+0x2C]
  [0x1006A] mov ecx, [r15+r8*1+0x1C]
  [0x1006F] sub rcx, r9
  [0x10072] mov r9, r13
  [0x10075] mov r9d, [r15+r9*1+0x2C]
  [0x1007A] movsxd r8, dword ptr [r15+r9*1+0x20]
  [0x1007F] cmp rcx, r8
  [0x10082] jle 0x00000000000100AB
  [0x10088] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10090] xor rdi, rdi
  [0x10093] lea rsi, [0x000000000001009A]
  [0x1009A] sub rsi, r15
  [0x1009D] mov rdx, r13
  [0x100A0] add r9, r15
  [0x100A3] call r9
  [0x100A6] jmp 0x00000000000100AE
  [0x100AB] mov rax, r14
  [0x100AE] mov r9, r13
  [0x100B1] mov r9d, [r15+r9*1+0x2C]
  [0x100B6] mov r13, r9
  [0x100B9] mov r9, r13
  [0x100BC] mov r9d, [r15+r9*1+0x0C]
  [0x100C1] xor rdi, rdi
  [0x100C4] add r9, r15
  [0x100C7] call r9
  [0x100CA] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D2] mov r9, [r15+r9*1+0x30C]
  [0x100DA] sub r9, rbp
  [0x100DD] mov r8d, 0xB4
  [0x100E3] cmp r9, r8
  [0x100E6] jl 0x000000000001001B
  [0x100EC] add rsp, 0x50
  [0x100F0] pop r12
  [0x100F2] pop rbp
  [0x100F3] pop rbx
  [0x100F4] ret


[anon-function-2]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, 0x800E
  [0x10006] mov r8d, [r15+r13*1+0x6C]
  [0x1000B] mov r8d, [r15+r8*1+0x9C]
  [0x10013] mov [r15+r8*1+0x3C], r9
  [0x10018] ret


[(method get-death-count game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9, r14
  [0x10003] cmp rsi, r9
  [0x10006] jz 0x0000000000010057
  [0x1000C] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10014] mov r9, r14
  [0x10017] cmp rsi, r9
  [0x1001A] jz 0x0000000000010057
  [0x10020] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10028] movsxd r9, dword ptr [r15+r9*1]
  [0x1002C] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10034] mov r8d, [r15+r8*1+0x1D8]
  [0x1003C] mov r8d, [r15+r8*1+0x34]
  [0x10041] movsxd r8, dword ptr [r15+r8*1+0x0C]
  [0x10046] mov rsi, r14
  [0x10049] cmp r9, r8
  [0x1004C] jl 0x0000000000010057
  [0x10052] lea rsi, [r14+0x08]
  [0x10057] mov r9, r14
  [0x1005A] cmp rsi, r9
  [0x1005D] jz 0x00000000000100B9
  [0x10063] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1006B] mov r9d, [r15+r9*1+0x1D8]
  [0x10073] mov r9d, [r15+r9*1+0x34]
  [0x10078] movsxd r9, dword ptr [r15+r9*1+0x0C]
  [0x1007D] mov r8, 0xFFFFFFFFFFFFFFFF
  [0x10084] add r9, r8
  [0x10087] mov r8d, 0x0C
  [0x1008D] shl r9, 0x02
  [0x10091] add r9, r8
  [0x10094] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1009C] add r9, r8
  [0x1009F] movsxd r9, dword ptr [r15+r9*1]
  [0x100A3] mov r8d, 0x38
  [0x100A9] add r8, rdi
  [0x100AC] add r9, r8
  [0x100AF] movzx rax, byte ptr [r15+r9*1]
  [0x100B4] jmp 0x00000000000100C1
  [0x100B9] movsxd rax, dword ptr [r15+rdi*1+0xA0]
  [0x100C1] xor r9, r9
  [0x100C4] mov r9d, 0x04
  [0x100CA] mov r8d, 0x05
  [0x100D0] cdq
  [0x100D1] idiv r8d
  [0x100D4] movsxd rax, eax
  [0x100D7] cmp r9, rax
  [0x100DA] jle 0x00000000000100E5
  [0x100E0] jmp 0x00000000000100E8
  [0x100E5] mov rax, r9
  [0x100E8] ret


[anon-function-1]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x58
  [0x10004] mov rsi, rsp
  [0x10007] sub rsi, r15
  [0x1000A] mov [r15+rsi*1+0x04], r13d
  [0x1000F] mov r9d, 0x02
  [0x10015] mov [r15+rsi*1+0x08], r9d
  [0x1001A] lea r9, [r14+0xAFECAFE]
  [0x10022] mov [r15+rsi*1+0x0C], r9d
  [0x10027] lea r9, [r14+0xAFECAFE]
  [0x1002F] mov [r15+rsi*1+0x10], r9
  [0x10034] mov r9d, 0x03
  [0x1003A] mov [r15+rsi*1+0x18], r9
  [0x1003F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10047] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1004F] add r9, r15
  [0x10052] call r9
  [0x10055] add rsp, 0x58
  [0x10059] ret


[(method reset! fact-info-target)]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9, r14
  [0x10003] mov r8, r14
  [0x10006] cmp rsi, r9
  [0x10009] jnz 0x0000000000010014
  [0x1000F] lea r8, [r14+0x08]
  [0x10014] mov r9, r8
  [0x10017] mov r8, r14
  [0x1001A] cmp r9, r8
  [0x1001D] jnz 0x000000000001003F
  [0x10023] lea r9, [r14+0xAFECAFE]
  [0x1002B] mov r8, r14
  [0x1002E] cmp rsi, r9
  [0x10031] jnz 0x000000000001003C
  [0x10037] lea r8, [r14+0x08]
  [0x1003C] mov r9, r8
  [0x1003F] mov r8, r14
  [0x10042] cmp r9, r8
  [0x10045] jz 0x000000000001007C
  [0x1004B] xor r9, r9
  [0x1004E] mov [r15+rdi*1+0x34], r9
  [0x10053] movss xmm7, dword ptr [0x000000000001005B]
  [0x1005B] movss [r15+rdi*1+0x28], xmm7
  [0x10062] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1006A] mov r9, [r15+r9*1+0x314]
  [0x10072] mov [r15+rdi*1+0x2C], r9
  [0x10077] jmp 0x000000000001007F
  [0x1007C] mov r9, r14
  [0x1007F] mov r9, r14
  [0x10082] mov r8, r14
  [0x10085] cmp rsi, r9
  [0x10088] jnz 0x0000000000010093
  [0x1008E] lea r8, [r14+0x08]
  [0x10093] mov r9, r8
  [0x10096] mov r8, r14
  [0x10099] cmp r9, r8
  [0x1009C] jnz 0x00000000000100BE
  [0x100A2] lea r9, [r14+0xAFECAFE]
  [0x100AA] mov r8, r14
  [0x100AD] cmp rsi, r9
  [0x100B0] jnz 0x00000000000100BB
  [0x100B6] lea r8, [r14+0x08]
  [0x100BB] mov r9, r8
  [0x100BE] mov r8, r14
  [0x100C1] cmp r9, r8
  [0x100C4] jz 0x00000000000100FF
  [0x100CA] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D2] movss xmm7, dword ptr [r15+r9*1+0x24]
  [0x100D9] movss [r15+rdi*1+0x40], xmm7
  [0x100E0] movss xmm7, dword ptr [r15+rdi*1+0x40]
  [0x100E7] movss [r15+rdi*1+0x3C], xmm7
  [0x100EE] mov r9, 0xFFFFFFFFFFFF8AD0
  [0x100F5] mov [r15+rdi*1+0x54], r9
  [0x100FA] jmp 0x0000000000010102
  [0x100FF] mov r9, r14
  [0x10102] mov r9, r14
  [0x10105] mov r8, r14
  [0x10108] cmp rsi, r9
  [0x1010B] jnz 0x0000000000010116
  [0x10111] lea r8, [r14+0x08]
  [0x10116] mov r9, r8
  [0x10119] mov r8, r14
  [0x1011C] cmp r9, r8
  [0x1011F] jnz 0x0000000000010141
  [0x10125] lea r9, [r14+0xAFECAFE]
  [0x1012D] mov r8, r14
  [0x10130] cmp rsi, r9
  [0x10133] jnz 0x000000000001013E
  [0x10139] lea r8, [r14+0x08]
  [0x1013E] mov r9, r8
  [0x10141] mov r8, r14
  [0x10144] cmp r9, r8
  [0x10147] jz 0x000000000001017F
  [0x1014D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10155] movss xmm7, dword ptr [r15+r9*1+0x34]
  [0x1015C] movss [r15+rdi*1+0x48], xmm7
  [0x10163] movss xmm7, dword ptr [0x000000000001016B]
  [0x1016B] movss [r15+rdi*1+0x44], xmm7
  [0x10172] movd r9d, xmm7
  [0x10177] movsxd r9, r9d
  [0x1017A] jmp 0x0000000000010182
  [0x1017F] mov r9, r14
  [0x10182] mov r9, r14
  [0x10185] mov r8, r14
  [0x10188] cmp rsi, r9
  [0x1018B] jnz 0x0000000000010196
  [0x10191] lea r8, [r14+0x08]
  [0x10196] mov r9, r8
  [0x10199] mov r8, r14
  [0x1019C] cmp r9, r8
  [0x1019F] jnz 0x00000000000101C1
  [0x101A5] lea r9, [r14+0xAFECAFE]
  [0x101AD] mov r8, r14
  [0x101B0] cmp rsi, r9
  [0x101B3] jnz 0x00000000000101BE
  [0x101B9] lea r8, [r14+0x08]
  [0x101BE] mov r9, r8
  [0x101C1] mov r8, r14
  [0x101C4] cmp r9, r8
  [0x101C7] jz 0x00000000000101FF
  [0x101CD] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101D5] movss xmm7, dword ptr [r15+r9*1+0x2C]
  [0x101DC] movss [r15+rdi*1+0x50], xmm7
  [0x101E3] movss xmm7, dword ptr [0x00000000000101EB]
  [0x101EB] movss [r15+rdi*1+0x4C], xmm7
  [0x101F2] movd r9d, xmm7
  [0x101F7] movsxd r9, r9d
  [0x101FA] jmp 0x0000000000010202
  [0x101FF] mov r9, r14
  [0x10202] ret


[top-level]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10009] mov esi, 0x09
  [0x1000E] lea rdx, [0x0000000000010015]
  [0x10015] sub rdx, r15
  [0x10018] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10020] add r9, r15
  [0x10023] call r9
  [0x10026] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1002E] mov esi, 0x0A
  [0x10033] lea rdx, [0x000000000001003A]
  [0x1003A] sub rdx, r15
  [0x1003D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10045] add r9, r15
  [0x10048] call r9
  [0x1004B] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10053] mov esi, 0x0B
  [0x10058] lea rdx, [0x000000000001005F]
  [0x1005F] sub rdx, r15
  [0x10062] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1006A] add r9, r15
  [0x1006D] call r9
  [0x10070] lea r9, [0x0000000000010077]
  [0x10077] sub r9, r15
  [0x1007A] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10082] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1008A] mov esi, 0x11
  [0x1008F] lea rdx, [0x0000000000010096]
  [0x10096] sub rdx, r15
  [0x10099] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100A1] add r9, r15
  [0x100A4] call r9
  [0x100A7] mov edi, [r15+r14*1+0xBADBEEF]
  [0x100AF] mov esi, 0x12
  [0x100B4] lea rdx, [0x00000000000100BB]
  [0x100BB] sub rdx, r15
  [0x100BE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100C6] add r9, r15
  [0x100C9] call r9
  [0x100CC] mov edi, [r15+r14*1+0xBADBEEF]
  [0x100D4] mov esi, 0x13
  [0x100D9] lea rdx, [0x00000000000100E0]
  [0x100E0] sub rdx, r15
  [0x100E3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100EB] add r9, r15
  [0x100EE] call r9
  [0x100F1] mov edi, [r15+r14*1+0xBADBEEF]
  [0x100F9] mov esi, 0x0D
  [0x100FE] lea rdx, [0x0000000000010105]
  [0x10105] sub rdx, r15
  [0x10108] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10110] add r9, r15
  [0x10113] call r9
  [0x10116] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1011E] mov esi, 0x09
  [0x10123] lea rdx, [0x000000000001012A]
  [0x1012A] sub rdx, r15
  [0x1012D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10135] add r9, r15
  [0x10138] call r9
  [0x1013B] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10143] mov esi, 0x0A
  [0x10148] lea rdx, [0x000000000001014F]
  [0x1014F] sub rdx, r15
  [0x10152] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1015A] add r9, r15
  [0x1015D] call r9
  [0x10160] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10168] mov esi, 0x17
  [0x1016D] lea rdx, [0x0000000000010174]
  [0x10174] sub rdx, r15
  [0x10177] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1017F] add r9, r15
  [0x10182] call r9
  [0x10185] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1018D] mov esi, 0x14
  [0x10192] lea rdx, [0x0000000000010199]
  [0x10199] sub rdx, r15
  [0x1019C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101A4] add r9, r15
  [0x101A7] call r9
  [0x101AA] mov edi, [r15+r14*1+0xBADBEEF]
  [0x101B2] mov esi, 0x15
  [0x101B7] lea rdx, [0x00000000000101BE]
  [0x101BE] sub rdx, r15
  [0x101C1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101C9] add r9, r15
  [0x101CC] call r9
  [0x101CF] mov edi, [r15+r14*1+0xBADBEEF]
  [0x101D7] mov esi, 0x16
  [0x101DC] lea rdx, [0x00000000000101E3]
  [0x101E3] sub rdx, r15
  [0x101E6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101EE] add r9, r15
  [0x101F1] call r9
  [0x101F4] mov edi, [r15+r14*1+0xBADBEEF]
  [0x101FC] mov esi, 0x1A
  [0x10201] lea rdx, [0x0000000000010208]
  [0x10208] sub rdx, r15
  [0x1020B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10213] add r9, r15
  [0x10216] call r9
  [0x10219] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10221] mov esi, 0x0A
  [0x10226] lea rdx, [0x000000000001022D]
  [0x1022D] sub rdx, r15
  [0x10230] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10238] add r9, r15
  [0x1023B] call r9
  [0x1023E] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10246] mov esi, 0x0B
  [0x1024B] lea rdx, [0x0000000000010252]
  [0x10252] sub rdx, r15
  [0x10255] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1025D] add r9, r15
  [0x10260] call r9
  [0x10263] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1026B] mov esi, 0x0C
  [0x10270] lea rdx, [0x0000000000010277]
  [0x10277] sub rdx, r15
  [0x1027A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10282] add r9, r15
  [0x10285] call r9
  [0x10288] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10290] mov esi, 0x0E
  [0x10295] lea rdx, [0x000000000001029C]
  [0x1029C] sub rdx, r15
  [0x1029F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102A7] add r9, r15
  [0x102AA] call r9
  [0x102AD] mov edi, [r15+r14*1+0xBADBEEF]
  [0x102B5] mov esi, 0x0F
  [0x102BA] lea rdx, [0x00000000000102C1]
  [0x102C1] sub rdx, r15
  [0x102C4] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102CC] add r9, r15
  [0x102CF] call r9
  [0x102D2] mov edi, [r15+r14*1+0xBADBEEF]
  [0x102DA] mov esi, 0x02
  [0x102DF] lea rdx, [0x00000000000102E6]
  [0x102E6] sub rdx, r15
  [0x102E9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102F1] add r9, r15
  [0x102F4] call r9
  [0x102F7] mov edi, [r15+r14*1+0xBADBEEF]
  [0x102FF] mov esi, 0x09
  [0x10304] lea rdx, [0x000000000001030B]
  [0x1030B] sub rdx, r15
  [0x1030E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10316] add r9, r15
  [0x10319] call r9
  [0x1031C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10324] mov r8, r14
  [0x10327] cmp r9, r8
  [0x1032A] jz 0x0000000000010347
  [0x10330] lea r9, [0x0000000000010337]
  [0x10337] sub r9, r15
  [0x1033A] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10342] jmp 0x0000000000010357
  [0x10347] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1034F] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10357] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1035F] mov r8, r14
  [0x10362] cmp r9, r8
  [0x10365] jz 0x0000000000010382
  [0x1036B] lea r9, [0x0000000000010372]
  [0x10372] sub r9, r15
  [0x10375] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1037D] jmp 0x0000000000010392
  [0x10382] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1038A] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10392] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1039A] mov esi, 0x10
  [0x1039F] lea rdx, [0x00000000000103A6]
  [0x103A6] sub rdx, r15
  [0x103A9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103B1] add r9, r15
  [0x103B4] call r9
  [0x103B7] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x103BF] mov r9d, [r15+rbx*1+0x60]
  [0x103C4] xor r8, r8
  [0x103C7] cmp r9, r8
  [0x103CA] jnz 0x0000000000010411
  [0x103D0] lea rdi, [r14+0xAFECAFE]
  [0x103D8] mov esi, [r15+r14*1+0xBADBEEF]
  [0x103E0] mov edx, 0x1000
  [0x103E5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103ED] mov r9d, [r15+r9*1+0x10]
  [0x103F2] add r9, r15
  [0x103F5] call r9
  [0x103F8] mov [r15+rbx*1+0x60], eax
  [0x103FD] xor r9, r9
  [0x10400] mov r8d, [r15+rbx*1+0x60]
  [0x10405] mov [r15+r8*1], r9d
  [0x10409] xor r9, r9
  [0x1040C] jmp 0x0000000000010414
  [0x10411] mov r9, r14
  [0x10414] mov r9d, [r15+rbx*1+0x64]
  [0x10419] xor r8, r8
  [0x1041C] cmp r9, r8
  [0x1041F] jnz 0x00000000000104A7
  [0x10425] lea rdi, [r14+0xAFECAFE]
  [0x1042D] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10435] mov edx, 0x74
  [0x1043A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10442] mov r9d, [r15+r9*1+0x10]
  [0x10447] add r9, r15
  [0x1044A] call r9
  [0x1044D] mov [r15+rbx*1+0x64], eax
  [0x10452] xor r9, r9
  [0x10455] jmp 0x000000000001047D
  [0x1045A] mov r8, r9
  [0x1045D] mov rcx, r9
  [0x10460] shl rcx, 0x04
  [0x10464] mov edx, 0x0C
  [0x10469] add rdx, rax
  [0x1046C] add rcx, rdx
  [0x1046F] mov [r15+rcx*1+0x0B], r8b
  [0x10474] mov r8d, 0x01
  [0x1047A] add r9, r8
  [0x1047D] movsxd r8, dword ptr [r15+rax*1]
  [0x10481] cmp r9, r8
  [0x10484] jl 0x000000000001045A
  [0x1048A] mov r9, r14
  [0x1048D] movzx r9, word ptr [r15+rax*1+0x24]
  [0x10493] mov r8d, 0x100
  [0x10499] or r9, r8
  [0x1049C] mov [r15+rax*1+0x24], r9w
  [0x104A2] jmp 0x00000000000104AA
  [0x104A7] mov r9, r14
  [0x104AA] mov r9d, [r15+rbx*1+0x6C]
  [0x104AF] xor r8, r8
  [0x104B2] cmp r9, r8
  [0x104B5] jnz 0x00000000000104ED
  [0x104BB] lea rdi, [r14+0xAFECAFE]
  [0x104C3] mov esi, [r15+r14*1+0xBADBEEF]
  [0x104CB] mov edx, 0xFFF
  [0x104D0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104D8] mov r9d, [r15+r9*1+0x10]
  [0x104DD] add r9, r15
  [0x104E0] call r9
  [0x104E3] mov [r15+rbx*1+0x6C], eax
  [0x104E8] jmp 0x00000000000104F0
  [0x104ED] mov rax, r14
  [0x104F0] mov r9d, [r15+rbx*1+0x134]
  [0x104F8] xor r8, r8
  [0x104FB] cmp r9, r8
  [0x104FE] jnz 0x000000000001054B
  [0x10504] lea rdi, [r14+0xAFECAFE]
  [0x1050C] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10514] mov edx, 0x40
  [0x10519] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10521] mov r9d, [r15+r9*1+0x10]
  [0x10526] add r9, r15
  [0x10529] call r9
  [0x1052C] mov [r15+rbx*1+0x134], eax
  [0x10534] xor r9, r9
  [0x10537] mov r8d, [r15+rbx*1+0x134]
  [0x1053F] mov [r15+r8*1], r9d
  [0x10543] xor r9, r9
  [0x10546] jmp 0x000000000001054E
  [0x1054B] mov r9, r14
  [0x1054E] mov r9, [r15+rbx*1+0xFC]
  [0x10556] xor r8, r8
  [0x10559] cmp r9, r8
  [0x1055C] jnz 0x0000000000010572
  [0x10562] mov r9, r14
  [0x10565] mov [r15+rbx*1+0xFC], r9
  [0x1056D] jmp 0x0000000000010575
  [0x10572] mov r9, r14
  [0x10575] mov r9d, [r15+rbx*1+0x68]
  [0x1057A] mov r8, r14
  [0x1057D] cmp r9, r8
  [0x10580] jnz 0x00000000000105A6
  [0x10586] mov esi, [r15+r14*1+0xBADBEEF]
  [0x1058E] mov r9d, [r15+rbx*1-0x04]
  [0x10593] mov r9d, [r15+r9*1+0x5C]
  [0x10598] mov rdi, rbx
  [0x1059B] add r9, r15
  [0x1059E] call r9
  [0x105A1] jmp 0x00000000000105A9
  [0x105A6] mov rax, r14
  [0x105A9] mov r9, r14
  [0x105AC] mov [r15+rbx*1+0x108], r9d
  [0x105B4] mov r9, r14
  [0x105B7] mov [r15+rbx*1+0x10C], r9
  [0x105BF] mov r9d, 0x01
  [0x105C5] mov [r15+rbx*1+0x114], r9d
  [0x105CD] xor r9, r9
  [0x105D0] mov [r15+rbx*1+0x118], r9d
  [0x105D8] mov r9, 0xFFFFFFFFFFFFFFFF
  [0x105DF] mov [r15+rbx*1+0x11C], r9d
  [0x105E7] mov r9, r14
  [0x105EA] mov [r15+rbx*1+0x124], r9
  [0x105F2] mov r9, r14
  [0x105F5] mov [r15+rbx*1+0x12C], r9
  [0x105FD] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10605] mov esi, 0x1B
  [0x1060A] lea rdx, [0x0000000000010611]
  [0x10611] sub rdx, r15
  [0x10614] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1061C] add r9, r15
  [0x1061F] call r9
  [0x10622] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1062A] mov esi, 0x1C
  [0x1062F] lea rdx, [0x0000000000010636]
  [0x10636] sub rdx, r15
  [0x10639] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10641] add r9, r15
  [0x10644] call r9
  [0x10647] mov rax, rbx
  [0x1064A] pop rbx
  [0x1064B] ret


[(method seen-text? game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov edi, [r15+rdi*1+0x6C]
  [0x10006] mov r9d, [r15+rdi*1-0x04]
  [0x1000B] mov r9d, [r15+r9*1+0x34]
  [0x10010] add r9, r15
  [0x10013] call r9
  [0x10016] pop rbx
  [0x10017] ret


[(method buzzer-count game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10009] mov rdi, rsi
  [0x1000C] add r9, r15
  [0x1000F] call r9
  [0x10012] xor rsi, rsi
  [0x10015] mov r9d, [r15+rax*1-0x04]
  [0x1001A] mov r9d, [r15+r9*1+0x50]
  [0x1001F] mov rdi, rax
  [0x10022] add r9, r15
  [0x10025] call r9
  [0x10028] xor r9, r9
  [0x1002B] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10033] movss xmm7, dword ptr [r15+r8*1+0x34]
  [0x1003A] cvttss2si r8d, xmm7
  [0x1003F] movsxd r8, r8d
  [0x10042] jmp 0x00000000000100A9
  [0x10047] mov ecx, 0x01
  [0x1004C] sub r8, rcx
  [0x1004F] mov ecx, 0x01
  [0x10054] mov rdx, rcx
  [0x10057] mov rsi, r8
  [0x1005A] xor rcx, rcx
  [0x1005D] cmp rsi, rcx
  [0x10060] jle 0x0000000000010074
  [0x10066] mov rcx, rsi
  [0x10069] shl rdx, cl
  [0x1006C] mov rcx, rdx
  [0x1006F] jmp 0x0000000000010080
  [0x10074] xor rcx, rcx
  [0x10077] sub rcx, rsi
  [0x1007A] sar rdx, cl
  [0x1007D] mov rcx, rdx
  [0x10080] mov rdx, rax
  [0x10083] and rdx, rcx
  [0x10086] xor rcx, rcx
  [0x10089] cmp rdx, rcx
  [0x1008C] jz 0x00000000000100A6
  [0x10092] mov rcx, r9
  [0x10095] mov r9d, 0x01
  [0x1009B] add rcx, r9
  [0x1009E] mov r9, rcx
  [0x100A1] jmp 0x00000000000100A9
  [0x100A6] mov rcx, r14
  [0x100A9] xor rcx, rcx
  [0x100AC] cmp r8, rcx
  [0x100AF] jnz 0x0000000000010047
  [0x100B5] mov r8, r14
  [0x100B8] mov rax, r9
  [0x100BB] pop rbx
  [0x100BC] ret


[(method got-buzzer? game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdx
  [0x10004] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000C] mov rdi, rsi
  [0x1000F] add r9, r15
  [0x10012] call r9
  [0x10015] xor rsi, rsi
  [0x10018] mov r9d, [r15+rax*1-0x04]
  [0x1001D] mov r9d, [r15+r9*1+0x50]
  [0x10022] mov rdi, rax
  [0x10025] add r9, r15
  [0x10028] call r9
  [0x1002B] mov r9d, 0x01
  [0x10031] xor r8, r8
  [0x10034] cmp rbx, r8
  [0x10037] jle 0x0000000000010048
  [0x1003D] mov rcx, rbx
  [0x10040] shl r9, cl
  [0x10043] jmp 0x0000000000010051
  [0x10048] xor rcx, rcx
  [0x1004B] sub rcx, rbx
  [0x1004E] sar r9, cl
  [0x10051] and rax, r9
  [0x10054] xor r9, r9
  [0x10057] mov r8, r14
  [0x1005A] cmp rax, r9
  [0x1005D] jz 0x0000000000010068
  [0x10063] lea r8, [r14+0x08]
  [0x10068] mov rax, r8
  [0x1006B] pop rbx
  [0x1006C] ret


[(method adjust game-info)]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] push rbx
  [0x1000B] push rbp
  [0x1000C] push r11
  [0x1000E] push r12
  [0x10010] mov rbx, rdi
  [0x10013] mov rbp, rdx
  [0x10016] mov r12, rcx
  [0x10019] lea r9, [r14+0xAFECAFE]
  [0x10021] cmp rsi, r9
  [0x10024] jnz 0x00000000000100D0
  [0x1002A] movd xmm7, ebp
  [0x1002E] movss xmm6, dword ptr [0x0000000000010036]
  [0x10036] ucomiss xmm7, xmm6
  [0x10039] jb 0x0000000000010076
  [0x1003F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10047] movss xmm7, dword ptr [r15+rbx*1+0x08]
  [0x1004E] movss xmm6, dword ptr [r15+rbx*1+0x0C]
  [0x10055] movd edi, xmm7
  [0x10059] movsxd rdi, edi
  [0x1005C] movd esi, xmm6
  [0x10060] movsxd rsi, esi
  [0x10063] mov rdx, rbp
  [0x10066] add r9, r15
  [0x10069] call r9
  [0x1006C] mov [r15+rbx*1+0x08], eax
  [0x10071] jmp 0x00000000000100BD
  [0x10076] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1007E] movss xmm7, dword ptr [r15+rbx*1+0x08]
  [0x10085] movss xmm6, dword ptr [0x000000000001008D]
  [0x1008D] movss xmm5, dword ptr [0x0000000000010095]
  [0x10095] movd xmm4, ebp
  [0x10099] subss xmm5, xmm4
  [0x1009D] movd edi, xmm7
  [0x100A1] movsxd rdi, edi
  [0x100A4] movd esi, xmm6
  [0x100A8] movsxd rsi, esi
  [0x100AB] movd edx, xmm5
  [0x100AF] movsxd rdx, edx
  [0x100B2] add r9, r15
  [0x100B5] call r9
  [0x100B8] mov [r15+rbx*1+0x08], eax
  [0x100BD] movss xmm7, dword ptr [r15+rbx*1+0x08]
  [0x100C4] movd eax, xmm7
  [0x100C8] movsxd rax, eax
  [0x100CB] jmp 0x00000000000106B1
  [0x100D0] lea r9, [r14+0xAFECAFE]
  [0x100D8] cmp rsi, r9
  [0x100DB] jnz 0x0000000000010332
  [0x100E1] movss xmm7, dword ptr [0x00000000000100E9]
  [0x100E9] movd xmm6, ebp
  [0x100ED] mov r9, r14
  [0x100F0] ucomiss xmm7, xmm6
  [0x100F3] jnb 0x00000000000100FE
  [0x100F9] lea r9, [r14+0x08]
  [0x100FE] mov r8, r14
  [0x10101] cmp r9, r8
  [0x10104] jz 0x0000000000010139
  [0x1010A] movss xmm7, dword ptr [r15+rbx*1+0x10]
  [0x10111] movd xmm6, ebp
  [0x10115] addss xmm7, xmm6
  [0x10119] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10121] movss xmm6, dword ptr [r15+r9*1+0x0C]
  [0x10128] mov r9, r14
  [0x1012B] ucomiss xmm7, xmm6
  [0x1012E] jnz 0x0000000000010139
  [0x10134] lea r9, [r14+0x08]
  [0x10139] mov r8, r14
  [0x1013C] cmp r9, r8
  [0x1013F] jz 0x0000000000010175
  [0x10145] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1014D] mov edi, 0x233
  [0x10152] lea rsi, [0x0000000000010159]
  [0x10159] sub rsi, r15
  [0x1015C] mov rdx, r14
  [0x1015F] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x10167] xor r8, r8
  [0x1016A] add r9, r15
  [0x1016D] call r9
  [0x10170] jmp 0x0000000000010178
  [0x10175] mov r11, r14
  [0x10178] movss xmm7, dword ptr [0x0000000000010180]
  [0x10180] movd xmm6, ebp
  [0x10184] ucomiss xmm7, xmm6
  [0x10187] jnb 0x000000000001030D
  [0x1018D] mov r9, r12
  [0x10190] shl r9, 0x20
  [0x10194] shr r9, 0x20
  [0x10198] mov r8, r14
  [0x1019B] cmp r9, r8
  [0x1019E] jz 0x00000000000101D2
  [0x101A4] mov r9, r12
  [0x101A7] shl r9, 0x20
  [0x101AB] shr r9, 0x20
  [0x101AF] mov r9d, [r15+r9*1]
  [0x101B3] sar r12, 0x20
  [0x101B7] movsxd r8, dword ptr [r15+r9*1+0x24]
  [0x101BC] cmp r12, r8
  [0x101BF] jnz 0x00000000000101CA
  [0x101C5] jmp 0x00000000000101CD
  [0x101CA] mov r9, r14
  [0x101CD] jmp 0x00000000000101D5
  [0x101D2] mov r9, r14
  [0x101D5] mov r8, r9
  [0x101D8] mov rcx, r14
  [0x101DB] cmp r8, rcx
  [0x101DE] jz 0x00000000000101E9
  [0x101E4] mov r8d, [r15+r9*1+0x30]
  [0x101E9] mov rcx, r14
  [0x101EC] cmp r8, rcx
  [0x101EF] jz 0x0000000000010305
  [0x101F5] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x101FD] movsxd r8, dword ptr [r15+r8*1]
  [0x10201] mov ecx, [r15+r9*1+0x30]
  [0x10206] mov ecx, [r15+rcx*1+0x14]
  [0x1020B] mov ecx, [r15+rcx*1+0x10]
  [0x10210] mov ecx, [r15+rcx*1+0x34]
  [0x10215] movsxd rcx, dword ptr [r15+rcx*1+0x0C]
  [0x1021A] cmp r8, rcx
  [0x1021D] jl 0x00000000000102FD
  [0x10223] mov r9d, [r15+r9*1+0x30]
  [0x10228] mov r9d, [r15+r9*1+0x14]
  [0x1022D] mov r9d, [r15+r9*1+0x10]
  [0x10232] mov r9d, [r15+r9*1+0x34]
  [0x10237] movsxd r9, dword ptr [r15+r9*1+0x0C]
  [0x1023C] mov r8, 0xFFFFFFFFFFFFFFFF
  [0x10243] add r9, r8
  [0x10246] mov r8d, 0x0C
  [0x1024C] shl r9, 0x02
  [0x10250] add r9, r8
  [0x10253] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1025B] add r9, r8
  [0x1025E] movsxd r12, dword ptr [r15+r9*1]
  [0x10262] mov r9, r12
  [0x10265] mov r8d, 0x18
  [0x1026B] add r8, rbx
  [0x1026E] add r9, r8
  [0x10271] movzx r9, byte ptr [r15+r9*1]
  [0x10276] movd xmm7, ebp
  [0x1027A] cvttss2si r8d, xmm7
  [0x1027F] movsxd r8, r8d
  [0x10282] add r9, r8
  [0x10285] mov r8, r12
  [0x10288] mov ecx, 0x18
  [0x1028D] add rcx, rbx
  [0x10290] add r8, rcx
  [0x10293] mov [r15+r8*1], r9b
  [0x10297] movss xmm7, dword ptr [r15+rbx*1+0x14]
  [0x1029E] movd xmm6, ebp
  [0x102A2] addss xmm7, xmm6
  [0x102A6] movss [r15+rbx*1+0x14], xmm7
  [0x102AD] mov r11, r12
  [0x102B0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102B8] mov rdi, r12
  [0x102BB] add r9, r15
  [0x102BE] call r9
  [0x102C1] mov r9d, 0x18
  [0x102C7] add r9, rbx
  [0x102CA] add r11, r9
  [0x102CD] movzx r9, byte ptr [r15+r11*1]
  [0x102D2] movsxd r8, dword ptr [r15+rax*1]
  [0x102D6] cmp r9, r8
  [0x102D9] jnz 0x00000000000102F5
  [0x102DF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102E7] mov rdi, r12
  [0x102EA] add r9, r15
  [0x102ED] call r9
  [0x102F0] jmp 0x00000000000102F8
  [0x102F5] mov rax, r14
  [0x102F8] jmp 0x0000000000010300
  [0x102FD] mov rax, r14
  [0x10300] jmp 0x0000000000010308
  [0x10305] mov rax, r14
  [0x10308] jmp 0x0000000000010310
  [0x1030D] mov rax, r14
  [0x10310] movss xmm7, dword ptr [r15+rbx*1+0x10]
  [0x10317] movd xmm6, ebp
  [0x1031B] addss xmm7, xmm6
  [0x1031F] movss [r15+rbx*1+0x10], xmm7
  [0x10326] movd eax, xmm7
  [0x1032A] movsxd rax, eax
  [0x1032D] jmp 0x00000000000106B1
  [0x10332] lea r9, [r14+0xAFECAFE]
  [0x1033A] cmp rsi, r9
  [0x1033D] jnz 0x0000000000010488
  [0x10343] movd xmm7, ebp
  [0x10347] cvttss2si ebp, xmm7
  [0x1034B] movsxd rbp, ebp
  [0x1034E] mov rsi, rbp
  [0x10351] mov r9d, [r15+rbx*1-0x04]
  [0x10356] mov r9d, [r15+r9*1+0x3C]
  [0x1035B] mov rdi, rbx
  [0x1035E] add r9, r15
  [0x10361] call r9
  [0x10364] mov r9, r14
  [0x10367] cmp rax, r9
  [0x1036A] jnz 0x000000000001038A
  [0x10370] mov r9d, 0x01
  [0x10376] mov r8, rbp
  [0x10379] mov rax, r14
  [0x1037C] cmp r9, r8
  [0x1037F] jb 0x000000000001038A
  [0x10385] lea rax, [r14+0x08]
  [0x1038A] mov r9, r14
  [0x1038D] cmp rax, r9
  [0x10390] jnz 0x0000000000010472
  [0x10396] xor r9, r9
  [0x10399] mov [r15+rbx*1+0xA0], r9d
  [0x103A1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103A9] mov r9, [r15+r9*1+0x30C]
  [0x103B1] mov [r15+rbx*1+0xC4], r9
  [0x103B9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103C1] mov r9, [r15+r9*1+0x30C]
  [0x103C9] mov r8d, 0x0C
  [0x103CF] mov rcx, rbp
  [0x103D2] shl rcx, 0x03
  [0x103D6] add rcx, r8
  [0x103D9] mov r8d, [r15+rbx*1+0xCC]
  [0x103E1] add rcx, r8
  [0x103E4] mov [r15+rcx*1], r9
  [0x103E8] movss xmm7, dword ptr [r15+rbx*1+0x5C]
  [0x103EF] movss xmm6, dword ptr [0x00000000000103F7]
  [0x103F7] addss xmm7, xmm6
  [0x103FB] movss [r15+rbx*1+0x5C], xmm7
  [0x10402] mov r9, rbp
  [0x10405] shl r9, 0x04
  [0x10409] mov r8d, 0x0C
  [0x1040F] mov ecx, [r15+rbx*1+0x64]
  [0x10414] add r8, rcx
  [0x10417] add r9, r8
  [0x1041A] movzx r9, word ptr [r15+r9*1+0x08]
  [0x10420] mov r8d, 0x100
  [0x10426] or r9, r8
  [0x10429] mov r8, rbp
  [0x1042C] shl r8, 0x04
  [0x10430] mov ecx, 0x0C
  [0x10435] mov edx, [r15+rbx*1+0x64]
  [0x1043A] add rcx, rdx
  [0x1043D] add r8, rcx
  [0x10440] mov [r15+r8*1+0x08], r9w
  [0x10446] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1044E] mov rdi, rbp
  [0x10451] add r9, r15
  [0x10454] call r9
  [0x10457] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1045F] mov esi, 0x07
  [0x10464] mov rdi, rbp
  [0x10467] add r9, r15
  [0x1046A] call r9
  [0x1046D] jmp 0x0000000000010475
  [0x10472] mov rax, r14
  [0x10475] movss xmm7, dword ptr [r15+rbx*1+0x5C]
  [0x1047C] movd eax, xmm7
  [0x10480] movsxd rax, eax
  [0x10483] jmp 0x00000000000106B1
  [0x10488] lea r9, [r14+0xAFECAFE]
  [0x10490] cmp rsi, r9
  [0x10493] jnz 0x00000000000106AE
  [0x10499] movd xmm7, ebp
  [0x1049D] cvttss2si edi, xmm7
  [0x104A1] movsxd rdi, edi
  [0x104A4] mov r9d, 0xFFFF
  [0x104AA] and rdi, r9
  [0x104AD] movd xmm7, ebp
  [0x104B1] cvttss2si r11d, xmm7
  [0x104B6] movsxd r11, r11d
  [0x104B9] sar r11, 0x10
  [0x104BD] movss xmm8, dword ptr [0x00000000000104C6]
  [0x104C6] mov r9, rdi
  [0x104C9] xor r8, r8
  [0x104CC] cmp r9, r8
  [0x104CF] jbe 0x000000000001069E
  [0x104D5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104DD] add r9, r15
  [0x104E0] call r9
  [0x104E3] mov r12, rax
  [0x104E6] xor rsi, rsi
  [0x104E9] mov r9d, [r12+r15*1-0x04]
  [0x104EE] mov r9d, [r15+r9*1+0x50]
  [0x104F3] mov rdi, r12
  [0x104F6] add r9, r15
  [0x104F9] call r9
  [0x104FC] mov rbp, rax
  [0x104FF] xor r9, r9
  [0x10502] mov r8, r14
  [0x10505] cmp r11, r9
  [0x10508] jl 0x0000000000010513
  [0x1050E] lea r8, [r14+0x08]
  [0x10513] mov r9, r8
  [0x10516] mov r8, r14
  [0x10519] cmp r9, r8
  [0x1051C] jz 0x000000000001054D
  [0x10522] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1052A] movss xmm7, dword ptr [r15+r9*1+0x34]
  [0x10531] cvttss2si r9d, xmm7
  [0x10536] movsxd r9, r9d
  [0x10539] mov r8, r14
  [0x1053C] cmp r11, r9
  [0x1053F] jnl 0x000000000001054A
  [0x10545] lea r8, [r14+0x08]
  [0x1054A] mov r9, r8
  [0x1054D] mov r8, r14
  [0x10550] cmp r9, r8
  [0x10553] jz 0x0000000000010605
  [0x10559] mov r9d, 0x01
  [0x1055F] mov r8, r11
  [0x10562] xor rcx, rcx
  [0x10565] cmp r8, rcx
  [0x10568] jle 0x0000000000010579
  [0x1056E] mov rcx, r8
  [0x10571] shl r9, cl
  [0x10574] jmp 0x0000000000010582
  [0x10579] xor rcx, rcx
  [0x1057C] sub rcx, r8
  [0x1057F] sar r9, cl
  [0x10582] mov r8, rbp
  [0x10585] and r8, r9
  [0x10588] xor r9, r9
  [0x1058B] cmp r8, r9
  [0x1058E] jnz 0x00000000000105BB
  [0x10594] movss xmm7, dword ptr [r15+rbx*1+0x58]
  [0x1059B] movss xmm6, dword ptr [0x00000000000105A3]
  [0x105A3] addss xmm7, xmm6
  [0x105A7] movss [r15+rbx*1+0x58], xmm7
  [0x105AE] movd r9d, xmm7
  [0x105B3] movsxd r9, r9d
  [0x105B6] jmp 0x00000000000105BE
  [0x105BB] mov r9, r14
  [0x105BE] mov r9d, [r12+r15*1-0x04]
  [0x105C3] mov r9d, [r15+r9*1+0x54]
  [0x105C8] mov r8d, 0x01
  [0x105CE] xor rcx, rcx
  [0x105D1] cmp r11, rcx
  [0x105D4] jle 0x00000000000105E5
  [0x105DA] mov rcx, r11
  [0x105DD] shl r8, cl
  [0x105E0] jmp 0x00000000000105EE
  [0x105E5] xor rcx, rcx
  [0x105E8] sub rcx, r11
  [0x105EB] sar r8, cl
  [0x105EE] or rbp, r8
  [0x105F1] xor rdx, rdx
  [0x105F4] mov rdi, r12
  [0x105F7] mov rsi, rbp
  [0x105FA] add r9, r15
  [0x105FD] call r9
  [0x10600] jmp 0x0000000000010608
  [0x10605] mov rax, r14
  [0x10608] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10610] movss xmm7, dword ptr [r15+r9*1+0x34]
  [0x10617] cvttss2si r9d, xmm7
  [0x1061C] movsxd r9, r9d
  [0x1061F] jmp 0x000000000001068A
  [0x10624] mov r8d, 0x01
  [0x1062A] sub r9, r8
  [0x1062D] mov r8d, 0x01
  [0x10633] mov rdx, r9
  [0x10636] xor rcx, rcx
  [0x10639] cmp rdx, rcx
  [0x1063C] jle 0x000000000001064D
  [0x10642] mov rcx, rdx
  [0x10645] shl r8, cl
  [0x10648] jmp 0x0000000000010656
  [0x1064D] xor rcx, rcx
  [0x10650] sub rcx, rdx
  [0x10653] sar r8, cl
  [0x10656] mov rcx, rbp
  [0x10659] and rcx, r8
  [0x1065C] xor r8, r8
  [0x1065F] cmp rcx, r8
  [0x10662] jz 0x0000000000010687
  [0x10668] movss xmm7, dword ptr [0x0000000000010670]
  [0x10670] addss xmm7, xmm8
  [0x10675] movss xmm8, xmm7
  [0x1067A] movd r8d, xmm7
  [0x1067F] movsxd r8, r8d
  [0x10682] jmp 0x000000000001068A
  [0x10687] mov r8, r14
  [0x1068A] xor r8, r8
  [0x1068D] cmp r9, r8
  [0x10690] jnz 0x0000000000010624
  [0x10696] mov r9, r14
  [0x10699] jmp 0x00000000000106A1
  [0x1069E] mov r9, r14
  [0x106A1] movd eax, xmm8
  [0x106A6] movsxd rax, eax
  [0x106A9] jmp 0x00000000000106B1
  [0x106AE] mov rax, r14
  [0x106B1] pop r12
  [0x106B3] pop r11
  [0x106B5] pop rbp
  [0x106B6] pop rbx
  [0x106B7] movdqa xmm8, [rsp]
  [0x106BD] add rsp, 0x18
  [0x106C1] ret


[(method initialize! game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x70
  [0x1000C] mov rbx, rdi
  [0x1000F] mov r12, rsi
  [0x10012] mov rbp, rdx
  [0x10015] mov r11, rcx
  [0x10018] mov r9, r12
  [0x1001B] lea r8, [r14+0xAFECAFE]
  [0x10023] cmp r9, r8
  [0x10026] jnz 0x00000000000101B5
  [0x1002C] movsxd r9, dword ptr [r15+rbx*1+0x98]
  [0x10034] mov r8d, 0x01
  [0x1003A] add r9, r8
  [0x1003D] mov [r15+rbx*1+0x98], r9d
  [0x10045] movsxd r9, dword ptr [r15+rbx*1+0x9C]
  [0x1004D] mov r8d, 0x01
  [0x10053] add r9, r8
  [0x10056] mov [r15+rbx*1+0x9C], r9d
  [0x1005E] movsxd r9, dword ptr [r15+rbx*1+0xA0]
  [0x10066] mov r8d, 0x01
  [0x1006C] add r9, r8
  [0x1006F] mov [r15+rbx*1+0xA0], r9d
  [0x10077] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1007F] mov r8, r14
  [0x10082] cmp r9, r8
  [0x10085] jz 0x000000000001015B
  [0x1008B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10093] mov r9d, [r15+r9*1+0x1D8]
  [0x1009B] mov r12d, [r15+r9*1+0x34]
  [0x100A0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100A8] movsxd r9, dword ptr [r15+r9*1]
  [0x100AC] movsxd r8, dword ptr [r12+r15*1+0x0C]
  [0x100B1] cmp r9, r8
  [0x100B4] jl 0x0000000000010150
  [0x100BA] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100C2] movsxd r8, dword ptr [r12+r15*1+0x0C]
  [0x100C7] mov rcx, 0xFFFFFFFFFFFFFFFF
  [0x100CE] add r8, rcx
  [0x100D1] mov ecx, 0x0C
  [0x100D6] shl r8, 0x02
  [0x100DA] add r8, rcx
  [0x100DD] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x100E5] add r8, rcx
  [0x100E8] movsxd r8, dword ptr [r15+r8*1]
  [0x100EC] mov ecx, 0x38
  [0x100F1] add rcx, rbx
  [0x100F4] add r8, rcx
  [0x100F7] movzx rdi, byte ptr [r15+r8*1]
  [0x100FC] mov esi, 0xFF
  [0x10101] mov edx, 0x01
  [0x10106] add r9, r15
  [0x10109] call r9
  [0x1010C] mov r9, rax
  [0x1010F] movsxd r8, dword ptr [r12+r15*1+0x0C]
  [0x10114] mov rcx, 0xFFFFFFFFFFFFFFFF
  [0x1011B] add r8, rcx
  [0x1011E] mov ecx, 0x0C
  [0x10123] shl r8, 0x02
  [0x10127] add r8, rcx
  [0x1012A] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x10132] add r8, rcx
  [0x10135] movsxd r8, dword ptr [r15+r8*1]
  [0x10139] mov ecx, 0x38
  [0x1013E] add rcx, rbx
  [0x10141] add r8, rcx
  [0x10144] mov [r15+r8*1], r9b
  [0x10148] mov r9, rax
  [0x1014B] jmp 0x0000000000010153
  [0x10150] mov r9, r14
  [0x10153] mov rax, r9
  [0x10156] jmp 0x000000000001015E
  [0x1015B] mov r9, r14
  [0x1015E] mov r9d, [r15+rbx*1]
  [0x10162] lea r8, [r14+0xAFECAFE]
  [0x1016A] cmp r9, r8
  [0x1016D] jnz 0x00000000000101AB
  [0x10173] movss xmm7, dword ptr [0x000000000001017B]
  [0x1017B] movss xmm6, dword ptr [r15+rbx*1+0x08]
  [0x10182] ucomiss xmm7, xmm6
  [0x10185] jnb 0x000000000001019B
  [0x1018B] lea r9, [r14+0xAFECAFE]
  [0x10193] mov r12, r9
  [0x10196] jmp 0x00000000000101A6
  [0x1019B] lea r9, [r14+0xAFECAFE]
  [0x101A3] mov r12, r9
  [0x101A6] jmp 0x00000000000101B0
  [0x101AB] jmp 0x0000000000010861
  [0x101B0] jmp 0x00000000000101B8
  [0x101B5] mov r9, r14
  [0x101B8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101C0] lea rdi, [r14-0x0A]
  [0x101C5] lea rsi, [r14-0x0A]
  [0x101CA] lea rdx, [r14+0xAFECAFE]
  [0x101D2] add r9, r15
  [0x101D5] call r9
  [0x101D8] mov r9, r12
  [0x101DB] lea r8, [r14+0xAFECAFE]
  [0x101E3] cmp r9, r8
  [0x101E6] jnz 0x0000000000010492
  [0x101EC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101F4] add r9, r15
  [0x101F7] call r9
  [0x101FA] mov r9, r14
  [0x101FD] cmp r11, r9
  [0x10200] jz 0x000000000001020B
  [0x10206] jmp 0x0000000000010260
  [0x1020B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10213] lea r8, [r14+0xAFECAFE]
  [0x1021B] cmp r9, r8
  [0x1021E] jz 0x0000000000010233
  [0x10224] lea r11, [0x000000000001022B]
  [0x1022B] sub r11, r15
  [0x1022E] jmp 0x0000000000010260
  [0x10233] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1023B] mov r8, r14
  [0x1023E] cmp r9, r8
  [0x10241] jz 0x0000000000010256
  [0x10247] lea r11, [0x000000000001024E]
  [0x1024E] sub r11, r15
  [0x10251] jmp 0x0000000000010260
  [0x10256] lea r11, [0x000000000001025D]
  [0x1025D] sub r11, r15
  [0x10260] mov r9d, [r15+rbx*1-0x04]
  [0x10265] mov r9d, [r15+r9*1+0x5C]
  [0x1026A] mov rdi, rbx
  [0x1026D] mov rsi, r11
  [0x10270] add r9, r15
  [0x10273] call r9
  [0x10276] xor r9, r9
  [0x10279] mov [r15+rbx*1+0x13C], r9d
  [0x10281] mov r9, r14
  [0x10284] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1028C] mov [r15+r8*1+0x1FC], r9d
  [0x10294] movss xmm7, dword ptr [0x000000000001029C]
  [0x1029C] movss [r15+rbx*1+0x10], xmm7
  [0x102A3] movss xmm7, dword ptr [0x00000000000102AB]
  [0x102AB] movss [r15+rbx*1+0x5C], xmm7
  [0x102B2] movss xmm7, dword ptr [0x00000000000102BA]
  [0x102BA] movss [r15+rbx*1+0x14], xmm7
  [0x102C1] movss xmm7, dword ptr [0x00000000000102C9]
  [0x102C9] movss [r15+rbx*1+0x58], xmm7
  [0x102D0] xor r9, r9
  [0x102D3] mov r8d, [r15+rbx*1+0x60]
  [0x102D8] mov [r15+r8*1], r9d
  [0x102DC] mov edi, [r15+rbx*1+0x6C]
  [0x102E1] mov r9d, [r15+rdi*1-0x04]
  [0x102E6] mov r9d, [r15+r9*1+0x40]
  [0x102EB] add r9, r15
  [0x102EE] call r9
  [0x102F1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102F9] mov edi, 0x0A
  [0x102FE] add r9, r15
  [0x10301] call r9
  [0x10304] mov [r15+rbx*1+0x104], eax
  [0x1030C] xor r9, r9
  [0x1030F] mov [r15+rbx*1+0x98], r9d
  [0x10317] xor r9, r9
  [0x1031A] mov [r15+rbx*1+0x9C], r9d
  [0x10322] xor r9, r9
  [0x10325] mov [r15+rbx*1+0xA0], r9d
  [0x1032D] xor r9, r9
  [0x10330] mov r8d, [r15+rbx*1+0x134]
  [0x10338] mov [r15+r8*1], r9d
  [0x1033C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10344] mov r9, [r15+r9*1+0x30C]
  [0x1034C] mov [r15+rbx*1+0xA4], r9
  [0x10354] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1035C] mov r9, [r15+r9*1+0x30C]
  [0x10364] mov [r15+rbx*1+0xC4], r9
  [0x1036C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10374] mov r9, [r15+r9*1+0x30C]
  [0x1037C] mov [r15+rbx*1+0xAC], r9
  [0x10384] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1038C] mov r9, [r15+r9*1+0x30C]
  [0x10394] mov [r15+rbx*1+0xB4], r9
  [0x1039C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103A4] mov r9, [r15+r9*1+0x30C]
  [0x103AC] mov [r15+rbx*1+0xBC], r9
  [0x103B4] xor r9, r9
  [0x103B7] jmp 0x00000000000103D6
  [0x103BC] xor r8, r8
  [0x103BF] mov ecx, [r15+rbx*1+0xCC]
  [0x103C7] mov [r15+rcx*1+0x0C], r8
  [0x103CC] nop
  [0x103CD] mov r8d, 0x01
  [0x103D3] add r9, r8
  [0x103D6] mov r8d, 0x74
  [0x103DC] cmp r9, r8
  [0x103DF] jl 0x00000000000103BC
  [0x103E5] mov r9, r14
  [0x103E8] xor r9, r9
  [0x103EB] jmp 0x000000000001047B
  [0x103F0] xor r8, r8
  [0x103F3] mov rcx, r9
  [0x103F6] mov edx, 0x18
  [0x103FB] add rdx, rbx
  [0x103FE] add rcx, rdx
  [0x10401] mov [r15+rcx*1], r8b
  [0x10405] xor r8, r8
  [0x10408] mov rcx, r9
  [0x1040B] mov edx, 0x38
  [0x10410] add rdx, rbx
  [0x10413] add rcx, rdx
  [0x10416] mov [r15+rcx*1], r8b
  [0x1041A] xor r8, r8
  [0x1041D] mov ecx, 0x0C
  [0x10422] mov rdx, r9
  [0x10425] shl rdx, 0x03
  [0x10429] add rdx, rcx
  [0x1042C] mov ecx, [r15+rbx*1+0xD0]
  [0x10434] add rdx, rcx
  [0x10437] mov [r15+rdx*1], r8
  [0x1043B] xor r8, r8
  [0x1043E] mov ecx, 0x0C
  [0x10443] mov rdx, r9
  [0x10446] shl rdx, 0x03
  [0x1044A] add rdx, rcx
  [0x1044D] mov ecx, [r15+rbx*1+0xD4]
  [0x10455] add rdx, rcx
  [0x10458] mov [r15+rdx*1], r8
  [0x1045C] xor r8, r8
  [0x1045F] mov rcx, r9
  [0x10462] mov edx, 0x70
  [0x10467] add rdx, rbx
  [0x1046A] add rcx, rdx
  [0x1046D] mov [r15+rcx*1], r8b
  [0x10471] nop
  [0x10472] mov r8d, 0x01
  [0x10478] add r9, r8
  [0x1047B] mov r8d, 0x20
  [0x10481] cmp r9, r8
  [0x10484] jl 0x00000000000103F0
  [0x1048A] mov r9, r14
  [0x1048D] jmp 0x0000000000010495
  [0x10492] mov r9, r14
  [0x10495] mov r9, r12
  [0x10498] lea r8, [r14+0xAFECAFE]
  [0x104A0] mov rcx, r14
  [0x104A3] cmp r9, r8
  [0x104A6] jnz 0x00000000000104B1
  [0x104AC] lea rcx, [r14+0x08]
  [0x104B1] mov r8, rcx
  [0x104B4] mov rcx, r14
  [0x104B7] cmp r8, rcx
  [0x104BA] jnz 0x00000000000104DC
  [0x104C0] lea r8, [r14+0xAFECAFE]
  [0x104C8] mov rcx, r14
  [0x104CB] cmp r9, r8
  [0x104CE] jnz 0x00000000000104D9
  [0x104D4] lea rcx, [r14+0x08]
  [0x104D9] mov r8, rcx
  [0x104DC] mov r9, r14
  [0x104DF] cmp r8, r9
  [0x104E2] jz 0x0000000000010553
  [0x104E8] mov r9d, [r15+rbx*1]
  [0x104EC] lea r8, [r14+0xAFECAFE]
  [0x104F4] cmp r9, r8
  [0x104F7] jnz 0x0000000000010518
  [0x104FD] mov r9, r14
  [0x10500] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10508] mov r9, r14
  [0x1050B] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10513] jmp 0x000000000001051B
  [0x10518] mov r9, r14
  [0x1051B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10523] movss xmm7, dword ptr [r15+r9*1]
  [0x10529] movss [r15+rbx*1+0x0C], xmm7
  [0x10530] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10538] movss xmm7, dword ptr [r15+r9*1+0x04]
  [0x1053F] movss [r15+rbx*1+0x08], xmm7
  [0x10546] movd r9d, xmm7
  [0x1054B] movsxd r9, r9d
  [0x1054E] jmp 0x0000000000010556
  [0x10553] mov r9, r14
  [0x10556] mov r9d, [r15+rbx*1]
  [0x1055A] lea r8, [r14+0xAFECAFE]
  [0x10562] cmp r9, r8
  [0x10565] jnz 0x00000000000105AB
  [0x1056B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10573] mov rdi, r12
  [0x10576] add r9, r15
  [0x10579] call r9
  [0x1057C] mov r9, r14
  [0x1057F] cmp rbp, r9
  [0x10582] jz 0x00000000000105A3
  [0x10588] mov r9d, [r15+rbx*1-0x04]
  [0x1058D] mov r9d, [r15+r9*1+0x74]
  [0x10592] mov rdi, rbx
  [0x10595] mov rsi, rbp
  [0x10598] add r9, r15
  [0x1059B] call r9
  [0x1059E] jmp 0x00000000000105A6
  [0x105A3] mov rax, r14
  [0x105A6] jmp 0x0000000000010861
  [0x105AB] lea r8, [r14+0xAFECAFE]
  [0x105B3] cmp r9, r8
  [0x105B6] jnz 0x000000000001085E
  [0x105BC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105C4] mov r8, r14
  [0x105C7] cmp r9, r8
  [0x105CA] jz 0x0000000000010667
  [0x105D0] mov edi, [r15+r14*1+0xBADBEEF]
  [0x105D8] mov esi, [r15+r14*1+0xBADBEEF]
  [0x105E0] lea rdx, [r14+0xAFECAFE]
  [0x105E8] mov rcx, r14
  [0x105EB] movss xmm7, dword ptr [0x00000000000105F3]
  [0x105F3] xor r9, r9
  [0x105F6] mov r8d, [r15+rdi*1-0x04]
  [0x105FB] mov eax, [r15+r8*1+0x38]
  [0x10600] movd r8d, xmm7
  [0x10605] movsxd r8, r8d
  [0x10608] add rax, r15
  [0x1060B] call rax
  [0x1060D] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10615] mov esi, [r15+r14*1+0xBADBEEF]
  [0x1061D] lea rdx, [r14+0xAFECAFE]
  [0x10625] mov rcx, r14
  [0x10628] movss xmm7, dword ptr [0x0000000000010630]
  [0x10630] xor r9, r9
  [0x10633] mov r8d, [r15+rdi*1-0x04]
  [0x10638] mov eax, [r15+r8*1+0x38]
  [0x1063D] movd r8d, xmm7
  [0x10642] movsxd r8, r8d
  [0x10645] add rax, r15
  [0x10648] call rax
  [0x1064A] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10652] mov r9d, [r15+rdi*1-0x04]
  [0x10657] mov r9d, [r15+r9*1+0x40]
  [0x1065C] add r9, r15
  [0x1065F] call r9
  [0x10662] jmp 0x000000000001066A
  [0x10667] mov rax, r14
  [0x1066A] mov rsi, rsp
  [0x1066D] sub rsi, r15
  [0x10670] mov [r15+rsi*1+0x04], r13d
  [0x10675] xor r9, r9
  [0x10678] mov [r15+rsi*1+0x08], r9d
  [0x1067D] lea r9, [r14+0xAFECAFE]
  [0x10685] mov [r15+rsi*1+0x0C], r9d
  [0x1068A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10692] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1069A] mov r8, [r15+r8*1+0x10C]
  [0x106A2] mov rcx, r8
  [0x106A5] shl rcx, 0x20
  [0x106A9] shr rcx, 0x20
  [0x106AD] mov rdx, r14
  [0x106B0] cmp rcx, rdx
  [0x106B3] jz 0x00000000000106E7
  [0x106B9] mov rcx, r8
  [0x106BC] shl rcx, 0x20
  [0x106C0] shr rcx, 0x20
  [0x106C4] mov edi, [r15+rcx*1]
  [0x106C8] sar r8, 0x20
  [0x106CC] movsxd rcx, dword ptr [r15+rdi*1+0x24]
  [0x106D1] cmp r8, rcx
  [0x106D4] jnz 0x00000000000106DF
  [0x106DA] jmp 0x00000000000106E2
  [0x106DF] mov rdi, r14
  [0x106E2] jmp 0x00000000000106EA
  [0x106E7] mov rdi, r14
  [0x106EA] add r9, r15
  [0x106ED] call r9
  [0x106F0] mov r9, r14
  [0x106F3] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x106FB] mov [r15+r8*1+0x10], r9d
  [0x10700] mov r9, r14
  [0x10703] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1070B] mov [r15+r8*1+0x1AC], r9d
  [0x10713] mov r9, r14
  [0x10716] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1071E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10726] mov edi, 0x1E
  [0x1072B] add r9, r15
  [0x1072E] call r9
  [0x10731] mov rsi, rsp
  [0x10734] sub rsi, r15
  [0x10737] mov [r15+rsi*1+0x04], r13d
  [0x1073C] xor r9, r9
  [0x1073F] mov [r15+rsi*1+0x08], r9d
  [0x10744] lea r9, [r14+0xAFECAFE]
  [0x1074C] mov [r15+rsi*1+0x0C], r9d
  [0x10751] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10759] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10761] add r9, r15
  [0x10764] call r9
  [0x10767] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1076F] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10777] mov edx, 0x4000
  [0x1077C] mov r9d, [r15+rdi*1-0x04]
  [0x10781] mov r9d, [r15+r9*1+0x48]
  [0x10786] add r9, r15
  [0x10789] call r9
  [0x1078C] mov r11, rax
  [0x1078F] mov r9, r14
  [0x10792] cmp r11, r9
  [0x10795] jz 0x000000000001083D
  [0x1079B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x107A3] mov r9d, [r15+r9*1+0x34]
  [0x107A8] mov esi, [r15+r14*1+0xBADBEEF]
  [0x107B0] lea rdx, [r14+0xAFECAFE]
  [0x107B8] mov ecx, 0x70004000
  [0x107BD] mov rdi, r11
  [0x107C0] add r9, r15
  [0x107C3] call r9
  [0x107C6] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x107CE] mov r9d, [r15+r11*1+0x28]
  [0x107D3] mov [rsp+0x58], r9
  [0x107DB] lea r9, [0x00000000000107E2]
  [0x107E2] sub r9, r15
  [0x107E5] mov [rsp+0x50], r9
  [0x107ED] mov r9d, [r15+rbx*1]
  [0x107F1] mov [rsp+0x60], r9
  [0x107F9] mov r9d, [r15+rbx*1-0x04]
  [0x107FE] mov r9d, [r15+r9*1+0x54]
  [0x10803] mov rdi, rbx
  [0x10806] add r9, r15
  [0x10809] call r9
  [0x1080C] mov rdi, [rsp+0x58]
  [0x10814] mov rsi, [rsp+0x50]
  [0x1081C] mov rdx, [rsp+0x60]
  [0x10824] mov rcx, r12
  [0x10827] mov r8, rax
  [0x1082A] mov r9, rbp
  [0x1082D] add r10, r15
  [0x10830] call r10
  [0x10833] mov r9d, [r15+r11*1+0x14]
  [0x10838] jmp 0x0000000000010840
  [0x1083D] mov r9, r14
  [0x10840] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10848] lea rdi, [r14+0xAFECAFE]
  [0x10850] add r9, r15
  [0x10853] call r9
  [0x10856] mov rax, rbp
  [0x10859] jmp 0x0000000000010861
  [0x1085E] mov rax, r14
  [0x10861] mov rax, rbx
  [0x10864] add rsp, 0x70
  [0x10868] pop r12
  [0x1086A] pop r11
  [0x1086C] pop r10
  [0x1086E] pop rbp
  [0x1086F] pop rbx
  [0x10870] ret


[game-task->string]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, 0x74
  [0x10006] cmp rdi, r9
  [0x10009] jnz 0x000000000001001E
  [0x1000F] lea rax, [0x0000000000010016]
  [0x10016] sub rax, r15
  [0x10019] jmp 0x0000000000010DBD
  [0x1001E] mov r9d, 0x73
  [0x10024] cmp rdi, r9
  [0x10027] jnz 0x000000000001003C
  [0x1002D] lea rax, [0x0000000000010034]
  [0x10034] sub rax, r15
  [0x10037] jmp 0x0000000000010DBD
  [0x1003C] mov r9d, 0x72
  [0x10042] cmp rdi, r9
  [0x10045] jnz 0x000000000001005A
  [0x1004B] lea rax, [0x0000000000010052]
  [0x10052] sub rax, r15
  [0x10055] jmp 0x0000000000010DBD
  [0x1005A] mov r9d, 0x71
  [0x10060] cmp rdi, r9
  [0x10063] jnz 0x0000000000010078
  [0x10069] lea rax, [0x0000000000010070]
  [0x10070] sub rax, r15
  [0x10073] jmp 0x0000000000010DBD
  [0x10078] mov r9d, 0x70
  [0x1007E] cmp rdi, r9
  [0x10081] jnz 0x0000000000010096
  [0x10087] lea rax, [0x000000000001008E]
  [0x1008E] sub rax, r15
  [0x10091] jmp 0x0000000000010DBD
  [0x10096] mov r9d, 0x6F
  [0x1009C] cmp rdi, r9
  [0x1009F] jnz 0x00000000000100B4
  [0x100A5] lea rax, [0x00000000000100AC]
  [0x100AC] sub rax, r15
  [0x100AF] jmp 0x0000000000010DBD
  [0x100B4] mov r9d, 0x6E
  [0x100BA] cmp rdi, r9
  [0x100BD] jnz 0x00000000000100D2
  [0x100C3] lea rax, [0x00000000000100CA]
  [0x100CA] sub rax, r15
  [0x100CD] jmp 0x0000000000010DBD
  [0x100D2] mov r9d, 0x6D
  [0x100D8] cmp rdi, r9
  [0x100DB] jnz 0x00000000000100F0
  [0x100E1] lea rax, [0x00000000000100E8]
  [0x100E8] sub rax, r15
  [0x100EB] jmp 0x0000000000010DBD
  [0x100F0] mov r9d, 0x6C
  [0x100F6] cmp rdi, r9
  [0x100F9] jnz 0x000000000001010E
  [0x100FF] lea rax, [0x0000000000010106]
  [0x10106] sub rax, r15
  [0x10109] jmp 0x0000000000010DBD
  [0x1010E] mov r9d, 0x6B
  [0x10114] cmp rdi, r9
  [0x10117] jnz 0x000000000001012C
  [0x1011D] lea rax, [0x0000000000010124]
  [0x10124] sub rax, r15
  [0x10127] jmp 0x0000000000010DBD
  [0x1012C] mov r9d, 0x6A
  [0x10132] cmp rdi, r9
  [0x10135] jnz 0x000000000001014A
  [0x1013B] lea rax, [0x0000000000010142]
  [0x10142] sub rax, r15
  [0x10145] jmp 0x0000000000010DBD
  [0x1014A] mov r9d, 0x69
  [0x10150] cmp rdi, r9
  [0x10153] jnz 0x0000000000010168
  [0x10159] lea rax, [0x0000000000010160]
  [0x10160] sub rax, r15
  [0x10163] jmp 0x0000000000010DBD
  [0x10168] mov r9d, 0x68
  [0x1016E] cmp rdi, r9
  [0x10171] jnz 0x0000000000010186
  [0x10177] lea rax, [0x000000000001017E]
  [0x1017E] sub rax, r15
  [0x10181] jmp 0x0000000000010DBD
  [0x10186] mov r9d, 0x67
  [0x1018C] cmp rdi, r9
  [0x1018F] jnz 0x00000000000101A4
  [0x10195] lea rax, [0x000000000001019C]
  [0x1019C] sub rax, r15
  [0x1019F] jmp 0x0000000000010DBD
  [0x101A4] mov r9d, 0x66
  [0x101AA] cmp rdi, r9
  [0x101AD] jnz 0x00000000000101C2
  [0x101B3] lea rax, [0x00000000000101BA]
  [0x101BA] sub rax, r15
  [0x101BD] jmp 0x0000000000010DBD
  [0x101C2] mov r9d, 0x65
  [0x101C8] cmp rdi, r9
  [0x101CB] jnz 0x00000000000101E0
  [0x101D1] lea rax, [0x00000000000101D8]
  [0x101D8] sub rax, r15
  [0x101DB] jmp 0x0000000000010DBD
  [0x101E0] mov r9d, 0x64
  [0x101E6] cmp rdi, r9
  [0x101E9] jnz 0x00000000000101FE
  [0x101EF] lea rax, [0x00000000000101F6]
  [0x101F6] sub rax, r15
  [0x101F9] jmp 0x0000000000010DBD
  [0x101FE] mov r9d, 0x63
  [0x10204] cmp rdi, r9
  [0x10207] jnz 0x000000000001021C
  [0x1020D] lea rax, [0x0000000000010214]
  [0x10214] sub rax, r15
  [0x10217] jmp 0x0000000000010DBD
  [0x1021C] mov r9d, 0x62
  [0x10222] cmp rdi, r9
  [0x10225] jnz 0x000000000001023A
  [0x1022B] lea rax, [0x0000000000010232]
  [0x10232] sub rax, r15
  [0x10235] jmp 0x0000000000010DBD
  [0x1023A] mov r9d, 0x61
  [0x10240] cmp rdi, r9
  [0x10243] jnz 0x0000000000010258
  [0x10249] lea rax, [0x0000000000010250]
  [0x10250] sub rax, r15
  [0x10253] jmp 0x0000000000010DBD
  [0x10258] mov r9d, 0x60
  [0x1025E] cmp rdi, r9
  [0x10261] jnz 0x0000000000010276
  [0x10267] lea rax, [0x000000000001026E]
  [0x1026E] sub rax, r15
  [0x10271] jmp 0x0000000000010DBD
  [0x10276] mov r9d, 0x5F
  [0x1027C] cmp rdi, r9
  [0x1027F] jnz 0x0000000000010294
  [0x10285] lea rax, [0x000000000001028C]
  [0x1028C] sub rax, r15
  [0x1028F] jmp 0x0000000000010DBD
  [0x10294] mov r9d, 0x5E
  [0x1029A] cmp rdi, r9
  [0x1029D] jnz 0x00000000000102B2
  [0x102A3] lea rax, [0x00000000000102AA]
  [0x102AA] sub rax, r15
  [0x102AD] jmp 0x0000000000010DBD
  [0x102B2] mov r9d, 0x5D
  [0x102B8] cmp rdi, r9
  [0x102BB] jnz 0x00000000000102D0
  [0x102C1] lea rax, [0x00000000000102C8]
  [0x102C8] sub rax, r15
  [0x102CB] jmp 0x0000000000010DBD
  [0x102D0] mov r9d, 0x5C
  [0x102D6] cmp rdi, r9
  [0x102D9] jnz 0x00000000000102EE
  [0x102DF] lea rax, [0x00000000000102E6]
  [0x102E6] sub rax, r15
  [0x102E9] jmp 0x0000000000010DBD
  [0x102EE] mov r9d, 0x5B
  [0x102F4] cmp rdi, r9
  [0x102F7] jnz 0x000000000001030C
  [0x102FD] lea rax, [0x0000000000010304]
  [0x10304] sub rax, r15
  [0x10307] jmp 0x0000000000010DBD
  [0x1030C] mov r9d, 0x5A
  [0x10312] cmp rdi, r9
  [0x10315] jnz 0x000000000001032A
  [0x1031B] lea rax, [0x0000000000010322]
  [0x10322] sub rax, r15
  [0x10325] jmp 0x0000000000010DBD
  [0x1032A] mov r9d, 0x59
  [0x10330] cmp rdi, r9
  [0x10333] jnz 0x0000000000010348
  [0x10339] lea rax, [0x0000000000010340]
  [0x10340] sub rax, r15
  [0x10343] jmp 0x0000000000010DBD
  [0x10348] mov r9d, 0x58
  [0x1034E] cmp rdi, r9
  [0x10351] jnz 0x0000000000010366
  [0x10357] lea rax, [0x000000000001035E]
  [0x1035E] sub rax, r15
  [0x10361] jmp 0x0000000000010DBD
  [0x10366] mov r9d, 0x57
  [0x1036C] cmp rdi, r9
  [0x1036F] jnz 0x0000000000010384
  [0x10375] lea rax, [0x000000000001037C]
  [0x1037C] sub rax, r15
  [0x1037F] jmp 0x0000000000010DBD
  [0x10384] mov r9d, 0x56
  [0x1038A] cmp rdi, r9
  [0x1038D] jnz 0x00000000000103A2
  [0x10393] lea rax, [0x000000000001039A]
  [0x1039A] sub rax, r15
  [0x1039D] jmp 0x0000000000010DBD
  [0x103A2] mov r9d, 0x55
  [0x103A8] cmp rdi, r9
  [0x103AB] jnz 0x00000000000103C0
  [0x103B1] lea rax, [0x00000000000103B8]
  [0x103B8] sub rax, r15
  [0x103BB] jmp 0x0000000000010DBD
  [0x103C0] mov r9d, 0x54
  [0x103C6] cmp rdi, r9
  [0x103C9] jnz 0x00000000000103DE
  [0x103CF] lea rax, [0x00000000000103D6]
  [0x103D6] sub rax, r15
  [0x103D9] jmp 0x0000000000010DBD
  [0x103DE] mov r9d, 0x53
  [0x103E4] cmp rdi, r9
  [0x103E7] jnz 0x00000000000103FC
  [0x103ED] lea rax, [0x00000000000103F4]
  [0x103F4] sub rax, r15
  [0x103F7] jmp 0x0000000000010DBD
  [0x103FC] mov r9d, 0x52
  [0x10402] cmp rdi, r9
  [0x10405] jnz 0x000000000001041A
  [0x1040B] lea rax, [0x0000000000010412]
  [0x10412] sub rax, r15
  [0x10415] jmp 0x0000000000010DBD
  [0x1041A] mov r9d, 0x51
  [0x10420] cmp rdi, r9
  [0x10423] jnz 0x0000000000010438
  [0x10429] lea rax, [0x0000000000010430]
  [0x10430] sub rax, r15
  [0x10433] jmp 0x0000000000010DBD
  [0x10438] mov r9d, 0x50
  [0x1043E] cmp rdi, r9
  [0x10441] jnz 0x0000000000010456
  [0x10447] lea rax, [0x000000000001044E]
  [0x1044E] sub rax, r15
  [0x10451] jmp 0x0000000000010DBD
  [0x10456] mov r9d, 0x4F
  [0x1045C] cmp rdi, r9
  [0x1045F] jnz 0x0000000000010474
  [0x10465] lea rax, [0x000000000001046C]
  [0x1046C] sub rax, r15
  [0x1046F] jmp 0x0000000000010DBD
  [0x10474] mov r9d, 0x4E
  [0x1047A] cmp rdi, r9
  [0x1047D] jnz 0x0000000000010492
  [0x10483] lea rax, [0x000000000001048A]
  [0x1048A] sub rax, r15
  [0x1048D] jmp 0x0000000000010DBD
  [0x10492] mov r9d, 0x4D
  [0x10498] cmp rdi, r9
  [0x1049B] jnz 0x00000000000104B0
  [0x104A1] lea rax, [0x00000000000104A8]
  [0x104A8] sub rax, r15
  [0x104AB] jmp 0x0000000000010DBD
  [0x104B0] mov r9d, 0x4C
  [0x104B6] cmp rdi, r9
  [0x104B9] jnz 0x00000000000104CE
  [0x104BF] lea rax, [0x00000000000104C6]
  [0x104C6] sub rax, r15
  [0x104C9] jmp 0x0000000000010DBD
  [0x104CE] mov r9d, 0x4B
  [0x104D4] cmp rdi, r9
  [0x104D7] jnz 0x00000000000104EC
  [0x104DD] lea rax, [0x00000000000104E4]
  [0x104E4] sub rax, r15
  [0x104E7] jmp 0x0000000000010DBD
  [0x104EC] mov r9d, 0x4A
  [0x104F2] cmp rdi, r9
  [0x104F5] jnz 0x000000000001050A
  [0x104FB] lea rax, [0x0000000000010502]
  [0x10502] sub rax, r15
  [0x10505] jmp 0x0000000000010DBD
  [0x1050A] mov r9d, 0x49
  [0x10510] cmp rdi, r9
  [0x10513] jnz 0x0000000000010528
  [0x10519] lea rax, [0x0000000000010520]
  [0x10520] sub rax, r15
  [0x10523] jmp 0x0000000000010DBD
  [0x10528] mov r9d, 0x48
  [0x1052E] cmp rdi, r9
  [0x10531] jnz 0x0000000000010546
  [0x10537] lea rax, [0x000000000001053E]
  [0x1053E] sub rax, r15
  [0x10541] jmp 0x0000000000010DBD
  [0x10546] mov r9d, 0x47
  [0x1054C] cmp rdi, r9
  [0x1054F] jnz 0x0000000000010564
  [0x10555] lea rax, [0x000000000001055C]
  [0x1055C] sub rax, r15
  [0x1055F] jmp 0x0000000000010DBD
  [0x10564] mov r9d, 0x46
  [0x1056A] cmp rdi, r9
  [0x1056D] jnz 0x0000000000010582
  [0x10573] lea rax, [0x000000000001057A]
  [0x1057A] sub rax, r15
  [0x1057D] jmp 0x0000000000010DBD
  [0x10582] mov r9d, 0x45
  [0x10588] cmp rdi, r9
  [0x1058B] jnz 0x00000000000105A0
  [0x10591] lea rax, [0x0000000000010598]
  [0x10598] sub rax, r15
  [0x1059B] jmp 0x0000000000010DBD
  [0x105A0] mov r9d, 0x44
  [0x105A6] cmp rdi, r9
  [0x105A9] jnz 0x00000000000105BE
  [0x105AF] lea rax, [0x00000000000105B6]
  [0x105B6] sub rax, r15
  [0x105B9] jmp 0x0000000000010DBD
  [0x105BE] mov r9d, 0x43
  [0x105C4] cmp rdi, r9
  [0x105C7] jnz 0x00000000000105DC
  [0x105CD] lea rax, [0x00000000000105D4]
  [0x105D4] sub rax, r15
  [0x105D7] jmp 0x0000000000010DBD
  [0x105DC] mov r9d, 0x42
  [0x105E2] cmp rdi, r9
  [0x105E5] jnz 0x00000000000105FA
  [0x105EB] lea rax, [0x00000000000105F2]
  [0x105F2] sub rax, r15
  [0x105F5] jmp 0x0000000000010DBD
  [0x105FA] mov r9d, 0x41
  [0x10600] cmp rdi, r9
  [0x10603] jnz 0x0000000000010618
  [0x10609] lea rax, [0x0000000000010610]
  [0x10610] sub rax, r15
  [0x10613] jmp 0x0000000000010DBD
  [0x10618] mov r9d, 0x40
  [0x1061E] cmp rdi, r9
  [0x10621] jnz 0x0000000000010636
  [0x10627] lea rax, [0x000000000001062E]
  [0x1062E] sub rax, r15
  [0x10631] jmp 0x0000000000010DBD
  [0x10636] mov r9d, 0x3F
  [0x1063C] cmp rdi, r9
  [0x1063F] jnz 0x0000000000010654
  [0x10645] lea rax, [0x000000000001064C]
  [0x1064C] sub rax, r15
  [0x1064F] jmp 0x0000000000010DBD
  [0x10654] mov r9d, 0x3E
  [0x1065A] cmp rdi, r9
  [0x1065D] jnz 0x0000000000010672
  [0x10663] lea rax, [0x000000000001066A]
  [0x1066A] sub rax, r15
  [0x1066D] jmp 0x0000000000010DBD
  [0x10672] mov r9d, 0x3D
  [0x10678] cmp rdi, r9
  [0x1067B] jnz 0x0000000000010690
  [0x10681] lea rax, [0x0000000000010688]
  [0x10688] sub rax, r15
  [0x1068B] jmp 0x0000000000010DBD
  [0x10690] mov r9d, 0x3C
  [0x10696] cmp rdi, r9
  [0x10699] jnz 0x00000000000106AE
  [0x1069F] lea rax, [0x00000000000106A6]
  [0x106A6] sub rax, r15
  [0x106A9] jmp 0x0000000000010DBD
  [0x106AE] mov r9d, 0x3B
  [0x106B4] cmp rdi, r9
  [0x106B7] jnz 0x00000000000106CC
  [0x106BD] lea rax, [0x00000000000106C4]
  [0x106C4] sub rax, r15
  [0x106C7] jmp 0x0000000000010DBD
  [0x106CC] mov r9d, 0x3A
  [0x106D2] cmp rdi, r9
  [0x106D5] jnz 0x00000000000106EA
  [0x106DB] lea rax, [0x00000000000106E2]
  [0x106E2] sub rax, r15
  [0x106E5] jmp 0x0000000000010DBD
  [0x106EA] mov r9d, 0x39
  [0x106F0] cmp rdi, r9
  [0x106F3] jnz 0x0000000000010708
  [0x106F9] lea rax, [0x0000000000010700]
  [0x10700] sub rax, r15
  [0x10703] jmp 0x0000000000010DBD
  [0x10708] mov r9d, 0x38
  [0x1070E] cmp rdi, r9
  [0x10711] jnz 0x0000000000010726
  [0x10717] lea rax, [0x000000000001071E]
  [0x1071E] sub rax, r15
  [0x10721] jmp 0x0000000000010DBD
  [0x10726] mov r9d, 0x37
  [0x1072C] cmp rdi, r9
  [0x1072F] jnz 0x0000000000010744
  [0x10735] lea rax, [0x000000000001073C]
  [0x1073C] sub rax, r15
  [0x1073F] jmp 0x0000000000010DBD
  [0x10744] mov r9d, 0x36
  [0x1074A] cmp rdi, r9
  [0x1074D] jnz 0x0000000000010762
  [0x10753] lea rax, [0x000000000001075A]
  [0x1075A] sub rax, r15
  [0x1075D] jmp 0x0000000000010DBD
  [0x10762] mov r9d, 0x35
  [0x10768] cmp rdi, r9
  [0x1076B] jnz 0x0000000000010780
  [0x10771] lea rax, [0x0000000000010778]
  [0x10778] sub rax, r15
  [0x1077B] jmp 0x0000000000010DBD
  [0x10780] mov r9d, 0x34
  [0x10786] cmp rdi, r9
  [0x10789] jnz 0x000000000001079E
  [0x1078F] lea rax, [0x0000000000010796]
  [0x10796] sub rax, r15
  [0x10799] jmp 0x0000000000010DBD
  [0x1079E] mov r9d, 0x33
  [0x107A4] cmp rdi, r9
  [0x107A7] jnz 0x00000000000107BC
  [0x107AD] lea rax, [0x00000000000107B4]
  [0x107B4] sub rax, r15
  [0x107B7] jmp 0x0000000000010DBD
  [0x107BC] mov r9d, 0x32
  [0x107C2] cmp rdi, r9
  [0x107C5] jnz 0x00000000000107DA
  [0x107CB] lea rax, [0x00000000000107D2]
  [0x107D2] sub rax, r15
  [0x107D5] jmp 0x0000000000010DBD
  [0x107DA] mov r9d, 0x31
  [0x107E0] cmp rdi, r9
  [0x107E3] jnz 0x00000000000107F8
  [0x107E9] lea rax, [0x00000000000107F0]
  [0x107F0] sub rax, r15
  [0x107F3] jmp 0x0000000000010DBD
  [0x107F8] mov r9d, 0x30
  [0x107FE] cmp rdi, r9
  [0x10801] jnz 0x0000000000010816
  [0x10807] lea rax, [0x000000000001080E]
  [0x1080E] sub rax, r15
  [0x10811] jmp 0x0000000000010DBD
  [0x10816] mov r9d, 0x2F
  [0x1081C] cmp rdi, r9
  [0x1081F] jnz 0x0000000000010834
  [0x10825] lea rax, [0x000000000001082C]
  [0x1082C] sub rax, r15
  [0x1082F] jmp 0x0000000000010DBD
  [0x10834] mov r9d, 0x2E
  [0x1083A] cmp rdi, r9
  [0x1083D] jnz 0x0000000000010852
  [0x10843] lea rax, [0x000000000001084A]
  [0x1084A] sub rax, r15
  [0x1084D] jmp 0x0000000000010DBD
  [0x10852] mov r9d, 0x2D
  [0x10858] cmp rdi, r9
  [0x1085B] jnz 0x0000000000010870
  [0x10861] lea rax, [0x0000000000010868]
  [0x10868] sub rax, r15
  [0x1086B] jmp 0x0000000000010DBD
  [0x10870] mov r9d, 0x2C
  [0x10876] cmp rdi, r9
  [0x10879] jnz 0x000000000001088E
  [0x1087F] lea rax, [0x0000000000010886]
  [0x10886] sub rax, r15
  [0x10889] jmp 0x0000000000010DBD
  [0x1088E] mov r9d, 0x2B
  [0x10894] cmp rdi, r9
  [0x10897] jnz 0x00000000000108AC
  [0x1089D] lea rax, [0x00000000000108A4]
  [0x108A4] sub rax, r15
  [0x108A7] jmp 0x0000000000010DBD
  [0x108AC] mov r9d, 0x2A
  [0x108B2] cmp rdi, r9
  [0x108B5] jnz 0x00000000000108CA
  [0x108BB] lea rax, [0x00000000000108C2]
  [0x108C2] sub rax, r15
  [0x108C5] jmp 0x0000000000010DBD
  [0x108CA] mov r9d, 0x29
  [0x108D0] cmp rdi, r9
  [0x108D3] jnz 0x00000000000108E8
  [0x108D9] lea rax, [0x00000000000108E0]
  [0x108E0] sub rax, r15
  [0x108E3] jmp 0x0000000000010DBD
  [0x108E8] mov r9d, 0x28
  [0x108EE] cmp rdi, r9
  [0x108F1] jnz 0x0000000000010906
  [0x108F7] lea rax, [0x00000000000108FE]
  [0x108FE] sub rax, r15
  [0x10901] jmp 0x0000000000010DBD
  [0x10906] mov r9d, 0x27
  [0x1090C] cmp rdi, r9
  [0x1090F] jnz 0x0000000000010924
  [0x10915] lea rax, [0x000000000001091C]
  [0x1091C] sub rax, r15
  [0x1091F] jmp 0x0000000000010DBD
  [0x10924] mov r9d, 0x26
  [0x1092A] cmp rdi, r9
  [0x1092D] jnz 0x0000000000010942
  [0x10933] lea rax, [0x000000000001093A]
  [0x1093A] sub rax, r15
  [0x1093D] jmp 0x0000000000010DBD
  [0x10942] mov r9d, 0x25
  [0x10948] cmp rdi, r9
  [0x1094B] jnz 0x0000000000010960
  [0x10951] lea rax, [0x0000000000010958]
  [0x10958] sub rax, r15
  [0x1095B] jmp 0x0000000000010DBD
  [0x10960] mov r9d, 0x24
  [0x10966] cmp rdi, r9
  [0x10969] jnz 0x000000000001097E
  [0x1096F] lea rax, [0x0000000000010976]
  [0x10976] sub rax, r15
  [0x10979] jmp 0x0000000000010DBD
  [0x1097E] mov r9d, 0x23
  [0x10984] cmp rdi, r9
  [0x10987] jnz 0x000000000001099C
  [0x1098D] lea rax, [0x0000000000010994]
  [0x10994] sub rax, r15
  [0x10997] jmp 0x0000000000010DBD
  [0x1099C] mov r9d, 0x22
  [0x109A2] cmp rdi, r9
  [0x109A5] jnz 0x00000000000109BA
  [0x109AB] lea rax, [0x00000000000109B2]
  [0x109B2] sub rax, r15
  [0x109B5] jmp 0x0000000000010DBD
  [0x109BA] mov r9d, 0x21
  [0x109C0] cmp rdi, r9
  [0x109C3] jnz 0x00000000000109D8
  [0x109C9] lea rax, [0x00000000000109D0]
  [0x109D0] sub rax, r15
  [0x109D3] jmp 0x0000000000010DBD
  [0x109D8] mov r9d, 0x20
  [0x109DE] cmp rdi, r9
  [0x109E1] jnz 0x00000000000109F6
  [0x109E7] lea rax, [0x00000000000109EE]
  [0x109EE] sub rax, r15
  [0x109F1] jmp 0x0000000000010DBD
  [0x109F6] mov r9d, 0x1F
  [0x109FC] cmp rdi, r9
  [0x109FF] jnz 0x0000000000010A14
  [0x10A05] lea rax, [0x0000000000010A0C]
  [0x10A0C] sub rax, r15
  [0x10A0F] jmp 0x0000000000010DBD
  [0x10A14] mov r9d, 0x1E
  [0x10A1A] cmp rdi, r9
  [0x10A1D] jnz 0x0000000000010A32
  [0x10A23] lea rax, [0x0000000000010A2A]
  [0x10A2A] sub rax, r15
  [0x10A2D] jmp 0x0000000000010DBD
  [0x10A32] mov r9d, 0x1D
  [0x10A38] cmp rdi, r9
  [0x10A3B] jnz 0x0000000000010A50
  [0x10A41] lea rax, [0x0000000000010A48]
  [0x10A48] sub rax, r15
  [0x10A4B] jmp 0x0000000000010DBD
  [0x10A50] mov r9d, 0x1C
  [0x10A56] cmp rdi, r9
  [0x10A59] jnz 0x0000000000010A6E
  [0x10A5F] lea rax, [0x0000000000010A66]
  [0x10A66] sub rax, r15
  [0x10A69] jmp 0x0000000000010DBD
  [0x10A6E] mov r9d, 0x1B
  [0x10A74] cmp rdi, r9
  [0x10A77] jnz 0x0000000000010A8C
  [0x10A7D] lea rax, [0x0000000000010A84]
  [0x10A84] sub rax, r15
  [0x10A87] jmp 0x0000000000010DBD
  [0x10A8C] mov r9d, 0x1A
  [0x10A92] cmp rdi, r9
  [0x10A95] jnz 0x0000000000010AAA
  [0x10A9B] lea rax, [0x0000000000010AA2]
  [0x10AA2] sub rax, r15
  [0x10AA5] jmp 0x0000000000010DBD
  [0x10AAA] mov r9d, 0x19
  [0x10AB0] cmp rdi, r9
  [0x10AB3] jnz 0x0000000000010AC8
  [0x10AB9] lea rax, [0x0000000000010AC0]
  [0x10AC0] sub rax, r15
  [0x10AC3] jmp 0x0000000000010DBD
  [0x10AC8] mov r9d, 0x18
  [0x10ACE] cmp rdi, r9
  [0x10AD1] jnz 0x0000000000010AE6
  [0x10AD7] lea rax, [0x0000000000010ADE]
  [0x10ADE] sub rax, r15
  [0x10AE1] jmp 0x0000000000010DBD
  [0x10AE6] mov r9d, 0x17
  [0x10AEC] cmp rdi, r9
  [0x10AEF] jnz 0x0000000000010B04
  [0x10AF5] lea rax, [0x0000000000010AFC]
  [0x10AFC] sub rax, r15
  [0x10AFF] jmp 0x0000000000010DBD
  [0x10B04] mov r9d, 0x16
  [0x10B0A] cmp rdi, r9
  [0x10B0D] jnz 0x0000000000010B22
  [0x10B13] lea rax, [0x0000000000010B1A]
  [0x10B1A] sub rax, r15
  [0x10B1D] jmp 0x0000000000010DBD
  [0x10B22] mov r9d, 0x15
  [0x10B28] cmp rdi, r9
  [0x10B2B] jnz 0x0000000000010B40
  [0x10B31] lea rax, [0x0000000000010B38]
  [0x10B38] sub rax, r15
  [0x10B3B] jmp 0x0000000000010DBD
  [0x10B40] mov r9d, 0x14
  [0x10B46] cmp rdi, r9
  [0x10B49] jnz 0x0000000000010B5E
  [0x10B4F] lea rax, [0x0000000000010B56]
  [0x10B56] sub rax, r15
  [0x10B59] jmp 0x0000000000010DBD
  [0x10B5E] mov r9d, 0x13
  [0x10B64] cmp rdi, r9
  [0x10B67] jnz 0x0000000000010B7C
  [0x10B6D] lea rax, [0x0000000000010B74]
  [0x10B74] sub rax, r15
  [0x10B77] jmp 0x0000000000010DBD
  [0x10B7C] mov r9d, 0x12
  [0x10B82] cmp rdi, r9
  [0x10B85] jnz 0x0000000000010B9A
  [0x10B8B] lea rax, [0x0000000000010B92]
  [0x10B92] sub rax, r15
  [0x10B95] jmp 0x0000000000010DBD
  [0x10B9A] mov r9d, 0x11
  [0x10BA0] cmp rdi, r9
  [0x10BA3] jnz 0x0000000000010BB8
  [0x10BA9] lea rax, [0x0000000000010BB0]
  [0x10BB0] sub rax, r15
  [0x10BB3] jmp 0x0000000000010DBD
  [0x10BB8] mov r9d, 0x10
  [0x10BBE] cmp rdi, r9
  [0x10BC1] jnz 0x0000000000010BD6
  [0x10BC7] lea rax, [0x0000000000010BCE]
  [0x10BCE] sub rax, r15
  [0x10BD1] jmp 0x0000000000010DBD
  [0x10BD6] mov r9d, 0x0F
  [0x10BDC] cmp rdi, r9
  [0x10BDF] jnz 0x0000000000010BF4
  [0x10BE5] lea rax, [0x0000000000010BEC]
  [0x10BEC] sub rax, r15
  [0x10BEF] jmp 0x0000000000010DBD
  [0x10BF4] mov r9d, 0x0E
  [0x10BFA] cmp rdi, r9
  [0x10BFD] jnz 0x0000000000010C12
  [0x10C03] lea rax, [0x0000000000010C0A]
  [0x10C0A] sub rax, r15
  [0x10C0D] jmp 0x0000000000010DBD
  [0x10C12] mov r9d, 0x0D
  [0x10C18] cmp rdi, r9
  [0x10C1B] jnz 0x0000000000010C30
  [0x10C21] lea rax, [0x0000000000010C28]
  [0x10C28] sub rax, r15
  [0x10C2B] jmp 0x0000000000010DBD
  [0x10C30] mov r9d, 0x0C
  [0x10C36] cmp rdi, r9
  [0x10C39] jnz 0x0000000000010C4E
  [0x10C3F] lea rax, [0x0000000000010C46]
  [0x10C46] sub rax, r15
  [0x10C49] jmp 0x0000000000010DBD
  [0x10C4E] mov r9d, 0x0B
  [0x10C54] cmp rdi, r9
  [0x10C57] jnz 0x0000000000010C6C
  [0x10C5D] lea rax, [0x0000000000010C64]
  [0x10C64] sub rax, r15
  [0x10C67] jmp 0x0000000000010DBD
  [0x10C6C] mov r9d, 0x0A
  [0x10C72] cmp rdi, r9
  [0x10C75] jnz 0x0000000000010C8A
  [0x10C7B] lea rax, [0x0000000000010C82]
  [0x10C82] sub rax, r15
  [0x10C85] jmp 0x0000000000010DBD
  [0x10C8A] mov r9d, 0x09
  [0x10C90] cmp rdi, r9
  [0x10C93] jnz 0x0000000000010CA8
  [0x10C99] lea rax, [0x0000000000010CA0]
  [0x10CA0] sub rax, r15
  [0x10CA3] jmp 0x0000000000010DBD
  [0x10CA8] mov r9d, 0x08
  [0x10CAE] cmp rdi, r9
  [0x10CB1] jnz 0x0000000000010CC6
  [0x10CB7] lea rax, [0x0000000000010CBE]
  [0x10CBE] sub rax, r15
  [0x10CC1] jmp 0x0000000000010DBD
  [0x10CC6] mov r9d, 0x07
  [0x10CCC] cmp rdi, r9
  [0x10CCF] jnz 0x0000000000010CE4
  [0x10CD5] lea rax, [0x0000000000010CDC]
  [0x10CDC] sub rax, r15
  [0x10CDF] jmp 0x0000000000010DBD
  [0x10CE4] mov r9d, 0x06
  [0x10CEA] cmp rdi, r9
  [0x10CED] jnz 0x0000000000010D02
  [0x10CF3] lea rax, [0x0000000000010CFA]
  [0x10CFA] sub rax, r15
  [0x10CFD] jmp 0x0000000000010DBD
  [0x10D02] mov r9d, 0x05
  [0x10D08] cmp rdi, r9
  [0x10D0B] jnz 0x0000000000010D20
  [0x10D11] lea rax, [0x0000000000010D18]
  [0x10D18] sub rax, r15
  [0x10D1B] jmp 0x0000000000010DBD
  [0x10D20] mov r9d, 0x04
  [0x10D26] cmp rdi, r9
  [0x10D29] jnz 0x0000000000010D3E
  [0x10D2F] lea rax, [0x0000000000010D36]
  [0x10D36] sub rax, r15
  [0x10D39] jmp 0x0000000000010DBD
  [0x10D3E] mov r9d, 0x03
  [0x10D44] cmp rdi, r9
  [0x10D47] jnz 0x0000000000010D5C
  [0x10D4D] lea rax, [0x0000000000010D54]
  [0x10D54] sub rax, r15
  [0x10D57] jmp 0x0000000000010DBD
  [0x10D5C] mov r9d, 0x02
  [0x10D62] cmp rdi, r9
  [0x10D65] jnz 0x0000000000010D7A
  [0x10D6B] lea rax, [0x0000000000010D72]
  [0x10D72] sub rax, r15
  [0x10D75] jmp 0x0000000000010DBD
  [0x10D7A] mov r9d, 0x01
  [0x10D80] cmp rdi, r9
  [0x10D83] jnz 0x0000000000010D98
  [0x10D89] lea rax, [0x0000000000010D90]
  [0x10D90] sub rax, r15
  [0x10D93] jmp 0x0000000000010DBD
  [0x10D98] xor r9, r9
  [0x10D9B] cmp rdi, r9
  [0x10D9E] jnz 0x0000000000010DB3
  [0x10DA4] lea rax, [0x0000000000010DAB]
  [0x10DAB] sub rax, r15
  [0x10DAE] jmp 0x0000000000010DBD
  [0x10DB3] lea rax, [0x0000000000010DBA]
  [0x10DBA] sub rax, r15
  [0x10DBD] ret


[(method get-entity-task-perm game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mshl rsi, 0x04
  [0x10004] mov r9d, 0x0C
  [0x1000A] mov r8d, [r15+rdi*1+0x64]
  [0x1000F] add r9, r8
  [0x10012] add rsi, r9
  [0x10015] mov rax, rsi
  [0x10018] ret


[(method set-continue! game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] mov rbx, rdi
  [0x10007] mov ebp, [r15+rbx*1+0x68]
  [0x1000C] lea r9, [r14-0x0A]
  [0x10011] cmp rsi, r9
  [0x10014] jnz 0x0000000000010025
  [0x1001A] mov r9, r14
  [0x1001D] mov rsi, r9
  [0x10020] jmp 0x0000000000010028
  [0x10025] mov r9, r14
  [0x10028] mov r9d, [r15+rsi*1-0x04]
  [0x1002D] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10035] cmp r9, r8
  [0x10038] jnz 0x000000000001006F
  [0x1003E] mov r9d, [r15+rbx*1-0x04]
  [0x10043] mov r9d, [r15+r9*1+0x58]
  [0x10048] mov rdi, rbx
  [0x1004B] add r9, r15
  [0x1004E] call r9
  [0x10051] mov r9, r14
  [0x10054] cmp rax, r9
  [0x10057] jz 0x0000000000010067
  [0x1005D] mov [r15+rbx*1+0x68], eax
  [0x10062] jmp 0x000000000001006A
  [0x10067] mov rax, r14
  [0x1006A] jmp 0x0000000000010140
  [0x1006F] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10077] cmp r9, r8
  [0x1007A] jnz 0x000000000001008D
  [0x10080] mov [r15+rbx*1+0x68], esi
  [0x10085] mov rax, rsi
  [0x10088] jmp 0x0000000000010140
  [0x1008D] mov r12d, [r15+r14*1+0xBADBEEF]
  [0x10095] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1009D] mov edi, 0x0C
  [0x100A2] add rdi, r12
  [0x100A5] movss xmm7, dword ptr [0x00000000000100AD]
  [0x100AD] movss xmm6, dword ptr [0x00000000000100B5]
  [0x100B5] movd esi, xmm7
  [0x100B9] movsxd rsi, esi
  [0x100BC] movd edx, xmm6
  [0x100C0] movsxd rdx, edx
  [0x100C3] add r9, r15
  [0x100C6] call r9
  [0x100C9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D1] mov edi, 0x1C
  [0x100D6] add rdi, r12
  [0x100D9] add r9, r15
  [0x100DC] call r9
  [0x100DF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100E7] mov r9d, [r15+r9*1+0x20]
  [0x100EC] mov [r12+r15*1+0x64], r9d
  [0x100F1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100F9] mov r9d, [r15+r9*1]
  [0x100FD] mov [r12+r15*1+0x68], r9d
  [0x10102] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1010A] mov r9d, [r15+r9*1+0x04]
  [0x1010F] mov [r12+r15*1+0x6C], r9d
  [0x10114] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1011C] mov r9d, [r15+r9*1+0x10]
  [0x10121] mov [r12+r15*1+0x70], r9d
  [0x10126] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1012E] mov r9d, [r15+r9*1+0x14]
  [0x10133] mov [r12+r15*1+0x74], r9d
  [0x10138] mov [r15+rbx*1+0x68], r12d
  [0x1013D] mov rax, r12
  [0x10140] mov r9d, [r15+rbx*1+0x68]
  [0x10145] cmp rbp, r9
  [0x10148] jz 0x0000000000010176
  [0x1014E] xor r9, r9
  [0x10151] mov [r15+rbx*1+0x9C], r9d
  [0x10159] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10161] mov r9, [r15+r9*1+0x30C]
  [0x10169] mov [r15+rbx*1+0xAC], r9
  [0x10171] jmp 0x0000000000010179
  [0x10176] mov r9, r14
  [0x10179] mov eax, [r15+rbx*1+0x68]
  [0x1017E] pop r12
  [0x10180] pop rbp
  [0x10181] pop rbx
  [0x10182] ret


[(method mark-text-as-seen game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov r9, rsi
  [0x10004] mov r8d, 0xFFF
  [0x1000A] mov rcx, r14
  [0x1000D] cmp r9, r8
  [0x10010] jnb 0x000000000001001B
  [0x10016] lea rcx, [r14+0x08]
  [0x1001B] mov r9, rcx
  [0x1001E] mov r8, r14
  [0x10021] cmp r9, r8
  [0x10024] jz 0x0000000000010044
  [0x1002A] mov r9, rsi
  [0x1002D] xor r8, r8
  [0x10030] mov rcx, r14
  [0x10033] cmp r9, r8
  [0x10036] jbe 0x0000000000010041
  [0x1003C] lea rcx, [r14+0x08]
  [0x10041] mov r9, rcx
  [0x10044] mov r8, r14
  [0x10047] cmp r9, r8
  [0x1004A] jz 0x000000000001006A
  [0x10050] mov edi, [r15+rdi*1+0x6C]
  [0x10055] mov r9d, [r15+rdi*1-0x04]
  [0x1005A] mov r9d, [r15+r9*1+0x3C]
  [0x1005F] add r9, r15
  [0x10062] call r9
  [0x10065] jmp 0x000000000001006D
  [0x1006A] mov rax, r14
  [0x1006D] pop rbx
  [0x1006E] ret


[(method get-continue-by-name game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r11
  [0x10004] push r12
  [0x10006] push rbx
  [0x10007] mov rbx, rsi
  [0x1000A] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10012] jmp 0x000000000001007E
  [0x10017] movsxd r9, dword ptr [r15+rbp*1-0x02]
  [0x1001C] movsxd r9, dword ptr [r15+r9*1]
  [0x10020] mov r12d, [r15+r9*1+0x34]
  [0x10025] jmp 0x0000000000010068
  [0x1002A] movsxd r11, dword ptr [r12+r15*1-0x02]
  [0x1002F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10037] mov r8, r11
  [0x1003A] mov esi, [r15+r8*1]
  [0x1003E] mov rdi, rbx
  [0x10041] add r9, r15
  [0x10044] call r9
  [0x10047] mov r9, r14
  [0x1004A] cmp rax, r9
  [0x1004D] jz 0x0000000000010060
  [0x10053] mov rax, r11
  [0x10056] jmp 0x0000000000010092
  [0x1005B] jmp 0x0000000000010063
  [0x10060] mov r9, r14
  [0x10063] movsxd r12, dword ptr [r12+r15*1+0x02]
  [0x10068] lea r9, [r14-0x0A]
  [0x1006D] cmp r12, r9
  [0x10070] jnz 0x000000000001002A
  [0x10076] mov r9, r14
  [0x10079] movsxd rbp, dword ptr [r15+rbp*1+0x02]
  [0x1007E] lea r9, [r14-0x0A]
  [0x10083] cmp rbp, r9
  [0x10086] jnz 0x0000000000010017
  [0x1008C] mov r9, r14
  [0x1008F] mov rax, r14
  [0x10092] pop rbx
  [0x10093] pop r12
  [0x10095] pop r11
  [0x10097] pop rbp
  [0x10098] pop rbx
  [0x10099] ret


[trsq->continue-point]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push rbx
  [0x10007] mov rbx, rdi
  [0x1000A] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10012] mov r9d, [r15+rdi*1-0x04]
  [0x10017] mov r9d, [r15+r9*1+0x54]
  [0x1001C] add r9, r15
  [0x1001F] call r9
  [0x10022] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1002A] lea rdi, [r14+0x08]
  [0x1002F] lea rsi, [0x0000000000010036]
  [0x10036] sub rsi, r15
  [0x10039] mov r8d, 0x20000
  [0x1003F] mov ecx, [r15+rax*1]
  [0x10043] add r8, rcx
  [0x10046] mov edx, [r15+r8*1]
  [0x1004A] add r9, r15
  [0x1004D] call r9
  [0x10050] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10058] lea rdi, [r14+0x08]
  [0x1005D] lea rsi, [0x0000000000010064]
  [0x10064] sub rsi, r15
  [0x10067] movss xmm7, dword ptr [r15+rbx*1+0x0C]
  [0x1006E] movss xmm6, dword ptr [r15+rbx*1+0x10]
  [0x10075] movss xmm5, dword ptr [r15+rbx*1+0x14]
  [0x1007C] movd edx, xmm7
  [0x10080] movsxd rdx, edx
  [0x10083] movd ecx, xmm6
  [0x10087] movsxd rcx, ecx
  [0x1008A] movd r8d, xmm5
  [0x1008F] movsxd r8, r8d
  [0x10092] add r9, r15
  [0x10095] call r9
  [0x10098] mov eax, [r15+r14*1+0xBADBEEF]
  [0x100A0] lea rdi, [r14+0x08]
  [0x100A5] lea rsi, [0x00000000000100AC]
  [0x100AC] sub rsi, r15
  [0x100AF] movss xmm7, dword ptr [r15+rbx*1+0x1C]
  [0x100B6] movss xmm6, dword ptr [r15+rbx*1+0x20]
  [0x100BD] movss xmm5, dword ptr [r15+rbx*1+0x24]
  [0x100C4] movss xmm4, dword ptr [r15+rbx*1+0x28]
  [0x100CB] movd edx, xmm7
  [0x100CF] movsxd rdx, edx
  [0x100D2] movd ecx, xmm6
  [0x100D6] movsxd rcx, ecx
  [0x100D9] movd r8d, xmm5
  [0x100DE] movsxd r8, r8d
  [0x100E1] movd r9d, xmm4
  [0x100E6] movsxd r9, r9d
  [0x100E9] mov rbx, rax
  [0x100EC] add rbx, r15
  [0x100EF] call rbx
  [0x100F1] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x100F9] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10101] lea rdi, [r14+0x08]
  [0x10106] lea rsi, [0x000000000001010D]
  [0x1010D] sub rsi, r15
  [0x10110] movss xmm7, dword ptr [r15+rbx*1+0x34C]
  [0x1011A] movss xmm6, dword ptr [r15+rbx*1+0x350]
  [0x10124] movss xmm5, dword ptr [r15+rbx*1+0x354]
  [0x1012E] movss xmm4, dword ptr [r15+rbx*1+0x1AC]
  [0x10138] movss xmm3, dword ptr [r15+rbx*1+0x1B0]
  [0x10142] movss xmm2, dword ptr [r15+rbx*1+0x1B4]
  [0x1014C] movd edx, xmm7
  [0x10150] movsxd rdx, edx
  [0x10153] movd ecx, xmm6
  [0x10157] movsxd rcx, ecx
  [0x1015A] movd r8d, xmm5
  [0x1015F] movsxd r8, r8d
  [0x10162] movd r9d, xmm4
  [0x10167] movsxd r9, r9d
  [0x1016A] movd r10d, xmm3
  [0x1016F] movsxd r10, r10d
  [0x10172] movd r11d, xmm2
  [0x10177] movsxd r11, r11d
  [0x1017A] mov rbp, rax
  [0x1017D] add rbp, r15
  [0x10180] call rbp
  [0x10182] mov eax, [r15+r14*1+0xBADBEEF]
  [0x1018A] lea rdi, [r14+0x08]
  [0x1018F] lea rsi, [0x0000000000010196]
  [0x10196] sub rsi, r15
  [0x10199] movss xmm7, dword ptr [r15+rbx*1+0x1BC]
  [0x101A3] movss xmm6, dword ptr [r15+rbx*1+0x1C0]
  [0x101AD] movss xmm5, dword ptr [r15+rbx*1+0x1C4]
  [0x101B7] movss xmm4, dword ptr [r15+rbx*1+0x1CC]
  [0x101C1] movss xmm3, dword ptr [r15+rbx*1+0x1D0]
  [0x101CB] movss xmm2, dword ptr [r15+rbx*1+0x1D4]
  [0x101D5] movd edx, xmm7
  [0x101D9] movsxd rdx, edx
  [0x101DC] movd ecx, xmm6
  [0x101E0] movsxd rcx, ecx
  [0x101E3] movd r8d, xmm5
  [0x101E8] movsxd r8, r8d
  [0x101EB] movd r9d, xmm4
  [0x101F0] movsxd r9, r9d
  [0x101F3] movd r10d, xmm3
  [0x101F8] movsxd r10, r10d
  [0x101FB] movd r11d, xmm2
  [0x10200] movsxd r11, r11d
  [0x10203] mov rbx, rax
  [0x10206] add rbx, r15
  [0x10209] call rbx
  [0x1020B] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10213] lea rdi, [r14+0x08]
  [0x10218] lea rsi, [0x000000000001021F]
  [0x1021F] sub rsi, r15
  [0x10222] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1022A] mov edx, [r15+r9*1+0x20]
  [0x1022F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10237] mov ecx, [r15+r9*1]
  [0x1023B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10243] mov r8d, [r15+r9*1+0x04]
  [0x10248] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10250] mov r9d, [r15+r9*1+0x10]
  [0x10255] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x1025D] mov r10d, [r15+rbx*1+0x14]
  [0x10262] mov rbx, rax
  [0x10265] add rbx, r15
  [0x10268] call rbx
  [0x1026A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10272] lea rdi, [r14+0x08]
  [0x10277] lea rsi, [0x000000000001027E]
  [0x1027E] sub rsi, r15
  [0x10281] add r9, r15
  [0x10284] call r9
  [0x10287] xor r9, r9
  [0x1028A] pop rbx
  [0x1028B] pop r11
  [0x1028D] pop r10
  [0x1028F] pop rbp
  [0x10290] pop rbx
  [0x10291] ret


[(method clear-text-seen! game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov edi, [r15+rdi*1+0x6C]
  [0x10006] mov r9d, [r15+rdi*1-0x04]
  [0x1000B] mov r9d, [r15+r9*1+0x38]
  [0x10010] add r9, r15
  [0x10013] call r9
  [0x10016] pop rbx
  [0x10017] ret


[anon-function-0]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r11
  [0x10004] push r12
  [0x10006] push rbx
  [0x10007] mov rbx, rdi
  [0x1000A] mov r11, rsi
  [0x1000D] mov rbp, rdx
  [0x10010] mov r12, rcx
  [0x10013] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1001B] mov rdi, rbx
  [0x1001E] add r9, r15
  [0x10021] call r9
  [0x10024] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1002C] mov rdi, r11
  [0x1002F] add r9, r15
  [0x10032] call r9
  [0x10035] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1003D] mov r9d, [r15+rdi*1-0x04]
  [0x10042] mov r9d, [r15+r9*1+0x5C]
  [0x10047] mov rsi, rbp
  [0x1004A] add r9, r15
  [0x1004D] call r9
  [0x10050] mov r9, r14
  [0x10053] cmp r12, r9
  [0x10056] jz 0x0000000000010097
  [0x1005C] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10064] mov r9d, [r15+rdi*1-0x04]
  [0x10069] mov r9d, [r15+r9*1+0x74]
  [0x1006E] mov rsi, r12
  [0x10071] add r9, r15
  [0x10074] call r9
  [0x10077] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1007F] mov r9d, [r15+rdi*1-0x04]
  [0x10084] mov r9d, [r15+r9*1+0x54]
  [0x10089] add r9, r15
  [0x1008C] call r9
  [0x1008F] mov rbp, rax
  [0x10092] jmp 0x000000000001009A
  [0x10097] mov rax, r14
  [0x1009A] mov r9, rsp
  [0x1009D] sub r9, r15
  [0x100A0] mov r8, r13
  [0x100A3] mov r8d, [r15+r8*1+0x2C]
  [0x100A8] mov ecx, [r15+r8*1+0x1C]
  [0x100AD] sub rcx, r9
  [0x100B0] mov r9, r13
  [0x100B3] mov r9d, [r15+r9*1+0x2C]
  [0x100B8] movsxd r8, dword ptr [r15+r9*1+0x20]
  [0x100BD] cmp rcx, r8
  [0x100C0] jle 0x00000000000100E9
  [0x100C6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100CE] xor rdi, rdi
  [0x100D1] lea rsi, [0x00000000000100D8]
  [0x100D8] sub rsi, r15
  [0x100DB] mov rdx, r13
  [0x100DE] add r9, r15
  [0x100E1] call r9
  [0x100E4] jmp 0x00000000000100EC
  [0x100E9] mov rax, r14
  [0x100EC] mov r9, r13
  [0x100EF] mov r9d, [r15+r9*1+0x2C]
  [0x100F4] mov r13, r9
  [0x100F7] mov r9, r13
  [0x100FA] mov r9d, [r15+r9*1+0x0C]
  [0x100FF] xor rdi, rdi
  [0x10102] add r9, r15
  [0x10105] call r9
  [0x10108] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10110] mov rdi, rbx
  [0x10113] mov rsi, rbp
  [0x10116] add r9, r15
  [0x10119] call r9
  [0x1011C] pop rbx
  [0x1011D] pop r12
  [0x1011F] pop r11
  [0x10121] pop rbp
  [0x10122] pop rbx
  [0x10123] ret


[(method get-or-create-continue! game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov r9d, [r15+rdi*1]
  [0x10005] lea r8, [r14+0xAFECAFE]
  [0x1000D] mov rcx, r14
  [0x10010] cmp r9, r8
  [0x10013] jnz 0x000000000001001E
  [0x10019] lea rcx, [r14+0x08]
  [0x1001E] mov r9, rcx
  [0x10021] mov r8, r14
  [0x10024] cmp r9, r8
  [0x10027] jz 0x0000000000010032
  [0x1002D] mov r9d, [r15+rdi*1+0x68]
  [0x10032] mov r8, r14
  [0x10035] cmp r9, r8
  [0x10038] jz 0x0000000000010048
  [0x1003E] mov eax, [r15+rdi*1+0x68]
  [0x10043] jmp 0x00000000000100F6
  [0x10048] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x10050] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10058] mov edi, 0x0C
  [0x1005D] add rdi, rbx
  [0x10060] movss xmm7, dword ptr [0x0000000000010068]
  [0x10068] movss xmm6, dword ptr [0x0000000000010070]
  [0x10070] movd esi, xmm7
  [0x10074] movsxd rsi, esi
  [0x10077] movd edx, xmm6
  [0x1007B] movsxd rdx, edx
  [0x1007E] add r9, r15
  [0x10081] call r9
  [0x10084] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1008C] mov edi, 0x1C
  [0x10091] add rdi, rbx
  [0x10094] add r9, r15
  [0x10097] call r9
  [0x1009A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100A2] mov r9d, [r15+r9*1+0x20]
  [0x100A7] mov [r15+rbx*1+0x64], r9d
  [0x100AC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100B4] mov r9d, [r15+r9*1]
  [0x100B8] mov [r15+rbx*1+0x68], r9d
  [0x100BD] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100C5] mov r9d, [r15+r9*1+0x04]
  [0x100CA] mov [r15+rbx*1+0x6C], r9d
  [0x100CF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D7] mov r9d, [r15+r9*1+0x10]
  [0x100DC] mov [r15+rbx*1+0x70], r9d
  [0x100E1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100E9] mov r9d, [r15+r9*1+0x14]
  [0x100EE] mov [r15+rbx*1+0x74], r9d
  [0x100F3] mov rax, rbx
  [0x100F6] pop rbx
  [0x100F7] ret


[(method task-complete? game-info)]
[1m[38;2;255;000;000m- [0x10000] [0mshl rsi, 0x04
  [0x10004] mov r9d, 0x0C
  [0x1000A] mov r8d, [r15+rdi*1+0x64]
  [0x1000F] add r9, r8
  [0x10012] add rsi, r9
  [0x10015] movzx r9, word ptr [r15+rsi*1+0x08]
  [0x1001B] mov r8d, 0x100
  [0x10021] and r9, r8
  [0x10024] xor r8, r8
  [0x10027] mov rax, r14
  [0x1002A] cmp r9, r8
  [0x1002D] jz 0x0000000000010038
  [0x10033] lea rax, [r14+0x08]
  [0x10038] ret


[(method debug-draw! continue-point)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] sub rsp, 0x18
  [0x10006] mov rbx, rdi
  [0x10009] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10011] lea rdi, [r14+0x08]
  [0x10016] mov esi, 0x44
  [0x1001B] mov edx, 0x0C
  [0x10020] add rdx, rbx
  [0x10023] mov ecx, 0x800000FF
  [0x10028] add r9, r15
  [0x1002B] call r9
  [0x1002E] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10036] lea rdi, [r14+0x08]
  [0x1003B] mov esi, 0x44
  [0x10040] mov edx, [r15+rbx*1]
  [0x10044] mov ecx, 0x0C
  [0x10049] add rcx, rbx
  [0x1004C] mov r8d, 0x01
  [0x10052] lea r9, [0x0000000000010059]
  [0x10059] sub r9, r15
  [0x1005C] mov rbp, rax
  [0x1005F] add rbp, r15
  [0x10062] call rbp
  [0x10064] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1006C] mov rdi, rsp
  [0x1006F] sub rdi, r15
  [0x10072] xor r8, r8
  [0x10075] movq xmm7, r8
  [0x1007A] vmovaps [r15+rdi*1], xmm7
  [0x10080] mov esi, 0x1C
  [0x10085] add rsi, rbx
  [0x10088] add r9, r15
  [0x1008B] call r9
  [0x1008E] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10096] lea rdi, [r14+0x08]
  [0x1009B] mov esi, 0x44
  [0x100A0] mov edx, 0x0C
  [0x100A5] add rdx, rbx
  [0x100A8] movss xmm7, dword ptr [0x00000000000100B0]
  [0x100B0] mov r9d, 0x800080FF
  [0x100B6] mov rcx, rax
  [0x100B9] movd r8d, xmm7
  [0x100BE] movsxd r8, r8d
  [0x100C1] add rbp, r15
  [0x100C4] call rbp
  [0x100C6] add rsp, 0x18
  [0x100CA] pop rbp
  [0x100CB] pop rbx
  [0x100CC] ret


[(method point-past-plane? border-plane)]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] mov r9, rsp
  [0x10007] sub r9, r15
  [0x1000A] mov r8d, 0x0C
  [0x10010] add r8, rdi
  [0x10013] vmovaps xmm6, [r15+rsi*1]
  [0x10019] vmovaps xmm5, [r15+r8*1]
  [0x1001F] vmovaps xmm7, [0x0000000000010027]
  [0x10027] vsubps xmm6, xmm6, xmm5
  [0x1002B] vblendps xmm6, xmm6, xmm7, 0x08
  [0x10031] vmovaps [r15+r9*1], xmm6
  [0x10037] mov r8d, 0x1C
  [0x1003D] add r8, rdi
  [0x10040] movss xmm7, dword ptr [0x0000000000010048]
  [0x10048] movss xmm6, dword ptr [r15+r9*1]
  [0x1004E] movss xmm5, dword ptr [r15+r8*1]
  [0x10054] mulss xmm6, xmm5
  [0x10058] addss xmm7, xmm6
  [0x1005C] movss xmm6, dword ptr [r15+r9*1+0x04]
  [0x10063] movss xmm5, dword ptr [r15+r8*1+0x04]
  [0x1006A] mulss xmm6, xmm5
  [0x1006E] addss xmm7, xmm6
  [0x10072] movss xmm6, dword ptr [r15+r9*1+0x08]
  [0x10079] movss xmm5, dword ptr [r15+r8*1+0x08]
  [0x10080] mulss xmm6, xmm5
  [0x10084] addss xmm7, xmm6
  [0x10088] movss xmm6, dword ptr [0x0000000000010090]
  [0x10090] mov rax, r14
  [0x10093] ucomiss xmm7, xmm6
  [0x10096] jb 0x00000000000100A1
  [0x1009C] lea rax, [r14+0x08]
  [0x100A1] add rsp, 0x18
  [0x100A5] ret


[(method debug-draw! border-plane)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] mov rbx, rdi
  [0x10007] mov r9d, [r15+rbx*1+0x04]
  [0x1000C] lea r8, [r14+0xAFECAFE]
  [0x10014] cmp r9, r8
  [0x10017] jnz 0x0000000000010027
  [0x1001D] mov ebp, 0x8000FF00
  [0x10022] jmp 0x000000000001002C
  [0x10027] mov ebp, 0x800000FF
  [0x1002C] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10034] lea rdi, [r14+0x08]
  [0x10039] mov esi, 0x44
  [0x1003E] mov edx, 0x0C
  [0x10043] add rdx, rbx
  [0x10046] movss xmm7, dword ptr [0x000000000001004E]
  [0x1004E] mov r9d, 0x20000
  [0x10054] mov r8d, [r15+rbx*1]
  [0x10058] add r9, r8
  [0x1005B] mov r8d, [r15+r9*1]
  [0x1005F] movd ecx, xmm7
  [0x10063] movsxd rcx, ecx
  [0x10066] mov r9, rbp
  [0x10069] mov r12, rax
  [0x1006C] add r12, r15
  [0x1006F] call r12
  [0x10072] mov eax, [r15+r14*1+0xBADBEEF]
  [0x1007A] lea rdi, [r14+0x08]
  [0x1007F] mov esi, 0x44
  [0x10084] mov edx, 0x0C
  [0x10089] add rdx, rbx
  [0x1008C] mov ecx, 0x1C
  [0x10091] add rcx, rbx
  [0x10094] movss xmm7, dword ptr [0x000000000001009C]
  [0x1009C] movd r8d, xmm7
  [0x100A1] movsxd r8, r8d
  [0x100A4] mov r9, rbp
  [0x100A7] mov rbx, rax
  [0x100AA] add rbx, r15
  [0x100AD] call rbx
  [0x100AF] pop r12
  [0x100B1] pop rbp
  [0x100B2] pop rbx
  [0x100B3] ret



