[top-level]
[1m[38;2;255;000;000m- [0x10000] [0mlea r9, [0x0000000000010007]
  [0x10007] sub r9, r15
  [0x1000A] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10012] lea r9, [0x0000000000010019]
  [0x10019] sub r9, r15
  [0x1001C] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10024] lea r9, [0x000000000001002B]
  [0x1002B] sub r9, r15
  [0x1002E] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10036] lea r9, [0x000000000001003D]
  [0x1003D] sub r9, r15
  [0x10040] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10048] lea r9, [0x000000000001004F]
  [0x1004F] sub r9, r15
  [0x10052] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1005A] lea r9, [0x0000000000010061]
  [0x10061] sub r9, r15
  [0x10064] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1006C] lea r9, [0x0000000000010073]
  [0x10073] sub r9, r15
  [0x10076] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1007E] lea r9, [0x0000000000010085]
  [0x10085] sub r9, r15
  [0x10088] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10090] lea r9, [0x0000000000010097]
  [0x10097] sub r9, r15
  [0x1009A] mov [r15+r14*1+0xBADBEEF], r9d
  [0x100A2] lea r9, [0x00000000000100A9]
  [0x100A9] sub r9, r15
  [0x100AC] mov [r15+r14*1+0xBADBEEF], r9d
  [0x100B4] lea r9, [0x00000000000100BB]
  [0x100BB] sub r9, r15
  [0x100BE] mov [r15+r14*1+0xBADBEEF], r9d
  [0x100C6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100CE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D6] lea r9, [0x00000000000100DD]
  [0x100DD] sub r9, r15
  [0x100E0] mov [r15+r14*1+0xBADBEEF], r9d
  [0x100E8] lea r9, [0x00000000000100EF]
  [0x100EF] sub r9, r15
  [0x100F2] mov [r15+r14*1+0xBADBEEF], r9d
  [0x100FA] lea rax, [0x0000000000010101]
  [0x10101] sub rax, r15
  [0x10104] mov [r15+r14*1+0xBADBEEF], eax
  [0x1010C] ret


[target-effect-exit]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+r13*1+0x78]
  [0x10005] mov r9d, [r15+r9*1+0x24]
  [0x1000A] xor r8, r8
  [0x1000D] mov [r15+r9*1+0x10], r8d
  [0x10012] xor r9, r9
  [0x10015] ret


[target-state-hook-exit]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+r14*1+0xBADBEEF]
  [0x10008] mov [r15+r13*1+0xC4], r9d
  [0x10010] ret


[target-exit]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10009] mov r8d, [r15+r13*1+0x6C]
  [0x1000E] mov [r15+r8*1+0x290], r9d
  [0x10016] xor r9, r9
  [0x10019] movq xmm7, r9
  [0x1001E] mov r9d, [r15+r13*1+0x6C]
  [0x10023] vmovaps [r15+r9*1+0x24C], xmm7
  [0x1002D] xor r9, r9
  [0x10030] movq xmm7, r9
  [0x10035] mov r9d, [r15+r13*1+0x6C]
  [0x1003A] vmovaps [r15+r9*1+0x25C], xmm7
  [0x10044] xor r9, r9
  [0x10047] movq xmm7, r9
  [0x1004C] mov r9d, [r15+r13*1+0x6C]
  [0x10051] vmovaps [r15+r9*1+0x26C], xmm7
  [0x1005B] xor r9, r9
  [0x1005E] movq xmm7, r9
  [0x10063] mov r9d, [r15+r13*1+0x6C]
  [0x10068] vmovaps [r15+r9*1+0x22C], xmm7
  [0x10072] movss xmm7, dword ptr [0x000000000001007A]
  [0x1007A] mov r9d, [r15+r13*1+0x6C]
  [0x1007F] movss [r15+r9*1+0x494], xmm7
  [0x10089] movss xmm7, dword ptr [0x0000000000010091]
  [0x10091] mov r9d, [r15+r13*1+0x6C]
  [0x10096] movss [r15+r9*1+0x6BC], xmm7
  [0x100A0] mov r9d, [r15+r13*1+0xA0]
  [0x100A8] mov r8d, 0x1C038C
  [0x100AE] not r8
  [0x100B1] and r9, r8
  [0x100B4] mov [r15+r13*1+0xA0], r9d
  [0x100BC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100C4] lea rdi, [r14+0xAFECAFE]
  [0x100CC] mov rsi, r14
  [0x100CF] add r9, r15
  [0x100D2] call r9
  [0x100D5] mov r9d, [r15+r13*1+0x98]
  [0x100DD] mov r9d, [r15+r9*1]
  [0x100E1] mov r8d, 0x10
  [0x100E7] or r9, r8
  [0x100EA] mov r8d, [r15+r13*1+0x98]
  [0x100F2] mov [r15+r8*1], r9d
  [0x100F6] mov r9d, [r15+r13*1+0x98]
  [0x100FE] mov r9d, [r15+r9*1]
  [0x10102] mov r8d, 0x10000
  [0x10108] not r8
  [0x1010B] and r9, r8
  [0x1010E] mov r8d, [r15+r13*1+0x98]
  [0x10116] mov [r15+r8*1], r9d
  [0x1011A] movss xmm7, dword ptr [0x0000000000010122]
  [0x10122] mov r9d, [r15+r13*1+0x98]
  [0x1012A] movss [r15+r9*1+0x114], xmm7
  [0x10134] movss xmm7, dword ptr [0x000000000001013C]
  [0x1013C] mov r9d, [r15+r13*1+0xB8]
  [0x10144] movss [r15+r9*1+0x74], xmm7
  [0x1014B] movss xmm7, dword ptr [0x0000000000010153]
  [0x10153] mov r9d, [r15+r13*1+0x6C]
  [0x10158] movss [r15+r9*1+0x734], xmm7
  [0x10162] mov r9d, [r15+r13*1+0x74]
  [0x10167] movzx r9, byte ptr [r15+r9*1]
  [0x1016C] mov r8d, 0x02
  [0x10172] not r8
  [0x10175] and r9, r8
  [0x10178] mov r8d, [r15+r13*1+0x74]
  [0x1017D] mov [r15+r8*1], r9b
  [0x10181] mov r9d, [r15+r13*1+0x78]
  [0x10186] movzx r9, word ptr [r15+r9*1]
  [0x1018B] mov r8d, 0x20
  [0x10191] not r8
  [0x10194] and r9, r8
  [0x10197] mov r8d, [r15+r13*1+0x78]
  [0x1019C] mov [r15+r8*1], r9w
  [0x101A1] mov r9d, [r15+r13*1+0x6C]
  [0x101A6] mov r9, [r15+r9*1+0x10C]
  [0x101AE] mov r8d, 0x4000
  [0x101B4] not r8
  [0x101B7] and r9, r8
  [0x101BA] mov r8d, [r15+r13*1+0x6C]
  [0x101BF] mov [r15+r8*1+0x10C], r9
  [0x101C7] xor r9, r9
  [0x101CA] pop rbx
  [0x101CB] ret


[target-walk-event-handler]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r11
  [0x10004] push r12
  [0x10006] push rbx
  [0x10007] mov rbx, rdi
  [0x1000A] mov rbp, rsi
  [0x1000D] mov r12, rdx
  [0x10010] mov r11, rcx
  [0x10013] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1001B] mov rdi, rbx
  [0x1001E] mov rsi, rbp
  [0x10021] mov rdx, r12
  [0x10024] mov rcx, r11
  [0x10027] add r9, r15
  [0x1002A] call r9
  [0x1002D] mov r9, r14
  [0x10030] cmp rax, r9
  [0x10033] jz 0x000000000001003E
  [0x10039] jmp 0x0000000000010058
  [0x1003E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10046] mov rdi, rbx
  [0x10049] mov rsi, rbp
  [0x1004C] mov rdx, r12
  [0x1004F] mov rcx, r11
  [0x10052] add r9, r15
  [0x10055] call r9
  [0x10058] pop rbx
  [0x10059] pop r12
  [0x1005B] pop r11
  [0x1005D] pop rbp
  [0x1005E] pop rbx
  [0x1005F] ret


[target-jump-event-handler]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r11
  [0x10004] push r12
  [0x10006] push rbx
  [0x10007] mov rbx, rdi
  [0x1000A] mov rbp, rsi
  [0x1000D] mov r12, rdx
  [0x10010] mov r11, rcx
  [0x10013] lea r9, [r14+0xAFECAFE]
  [0x1001B] mov r8, r14
  [0x1001E] cmp r12, r9
  [0x10021] jnz 0x000000000001002C
  [0x10027] lea r8, [r14+0x08]
  [0x1002C] mov r9, r8
  [0x1002F] mov r8, r14
  [0x10032] cmp r9, r8
  [0x10035] jz 0x00000000000100C0
  [0x1003B] mov r9d, 0x1C
  [0x10041] mov r8d, [r15+r13*1+0x6C]
  [0x10046] mov r8d, [r15+r8*1+0x1B0]
  [0x1004E] add r9, r8
  [0x10051] mov r8d, 0x3C
  [0x10057] mov ecx, [r15+r13*1+0x6C]
  [0x1005C] add r8, rcx
  [0x1005F] movss xmm7, dword ptr [0x0000000000010067]
  [0x10067] movss xmm6, dword ptr [r15+r9*1]
  [0x1006D] movss xmm5, dword ptr [r15+r8*1]
  [0x10073] mulss xmm6, xmm5
  [0x10077] addss xmm7, xmm6
  [0x1007B] movss xmm6, dword ptr [r15+r9*1+0x04]
  [0x10082] movss xmm5, dword ptr [r15+r8*1+0x04]
  [0x10089] mulss xmm6, xmm5
  [0x1008D] addss xmm7, xmm6
  [0x10091] movss xmm6, dword ptr [r15+r9*1+0x08]
  [0x10098] movss xmm5, dword ptr [r15+r8*1+0x08]
  [0x1009F] mulss xmm6, xmm5
  [0x100A3] addss xmm7, xmm6
  [0x100A7] movss xmm6, dword ptr [0x00000000000100AF]
  [0x100AF] mov r9, r14
  [0x100B2] ucomiss xmm6, xmm7
  [0x100B5] jnb 0x00000000000100C0
  [0x100BB] lea r9, [r14+0x08]
  [0x100C0] mov r8, r14
  [0x100C3] cmp r9, r8
  [0x100C6] jz 0x00000000000100D9
  [0x100CC] mov rax, r14
  [0x100CF] jmp 0x0000000000010121
  [0x100D4] jmp 0x00000000000100DC
  [0x100D9] mov r9, r14
  [0x100DC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100E4] mov rdi, rbx
  [0x100E7] mov rsi, rbp
  [0x100EA] mov rdx, r12
  [0x100ED] mov rcx, r11
  [0x100F0] add r9, r15
  [0x100F3] call r9
  [0x100F6] mov r9, r14
  [0x100F9] cmp rax, r9
  [0x100FC] jz 0x0000000000010107
  [0x10102] jmp 0x0000000000010121
  [0x10107] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1010F] mov rdi, rbx
  [0x10112] mov rsi, rbp
  [0x10115] mov rdx, r12
  [0x10118] mov rcx, r11
  [0x1011B] add r9, r15
  [0x1011E] call r9
  [0x10121] pop rbx
  [0x10122] pop r12
  [0x10124] pop r11
  [0x10126] pop rbp
  [0x10127] pop rbx
  [0x10128] ret


[target-bonk-event-handler]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] push rbx
  [0x1000B] push rbp
  [0x1000C] push r11
  [0x1000E] push r12
  [0x10010] sub rsp, 0x80
  [0x10017] mov r12, rdi
  [0x1001A] mov rbp, rdx
  [0x1001D] mov rbx, rcx
  [0x10020] mov r11, rsp
  [0x10023] sub r11, r15
  [0x10026] lea r9, [r14+0xAFECAFE]
  [0x1002E] mov r8, r14
  [0x10031] cmp rbp, r9
  [0x10034] jnz 0x000000000001003F
  [0x1003A] lea r8, [r14+0x08]
  [0x1003F] mov r9, r8
  [0x10042] mov r8, r14
  [0x10045] cmp r9, r8
  [0x10048] jz 0x00000000000101E5
  [0x1004E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10056] mov r9d, [r15+r9*1+0x40]
  [0x1005B] mov rdi, [r15+rbx*1+0x10]
  [0x10060] mov esi, [r15+r13*1+0x6C]
  [0x10065] mov edx, 0x06
  [0x1006A] add r9, r15
  [0x1006D] call r9
  [0x10070] mov r9, rax
  [0x10073] mov r8, r14
  [0x10076] cmp r9, r8
  [0x10079] jz 0x00000000000101E5
  [0x1007F] movss xmm7, dword ptr [0x0000000000010087]
  [0x10087] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1008F] movss xmm6, dword ptr [r15+r9*1+0x394]
  [0x10099] mulss xmm7, xmm6
  [0x1009D] mov r9d, 0x1C
  [0x100A3] mov r8d, [r15+r13*1+0x6C]
  [0x100A8] mov r8d, [r15+r8*1+0x1B0]
  [0x100B0] add r9, r8
  [0x100B3] lea r8, [rsp+0x10]
  [0x100B8] sub r8, r15
  [0x100BB] mov ecx, 0x3C
  [0x100C0] mov edx, [r15+r13*1+0x6C]
  [0x100C5] add rcx, rdx
  [0x100C8] mov edx, 0x21C
  [0x100CD] mov esi, [r15+r13*1+0x6C]
  [0x100D2] add rdx, rsi
  [0x100D5] vmovaps xmm5, [r15+rcx*1]
  [0x100DB] vmovaps xmm4, [r15+rdx*1]
  [0x100E1] vmovaps xmm6, [0x00000000000100E9]
  [0x100E9] vsubps xmm5, xmm5, xmm4
  [0x100ED] vblendps xmm5, xmm5, xmm6, 0x08
  [0x100F3] vmovaps [r15+r8*1], xmm5
  [0x100F9] movss xmm6, dword ptr [0x0000000000010101]
  [0x10101] movss xmm5, dword ptr [r15+r9*1]
  [0x10107] movss xmm4, dword ptr [r15+r8*1]
  [0x1010D] mulss xmm5, xmm4
  [0x10111] addss xmm6, xmm5
  [0x10115] movss xmm5, dword ptr [r15+r9*1+0x04]
  [0x1011C] movss xmm4, dword ptr [r15+r8*1+0x04]
  [0x10123] mulss xmm5, xmm4
  [0x10127] addss xmm6, xmm5
  [0x1012B] movss xmm5, dword ptr [r15+r9*1+0x08]
  [0x10132] movss xmm4, dword ptr [r15+r8*1+0x08]
  [0x10139] mulss xmm5, xmm4
  [0x1013D] addss xmm6, xmm5
  [0x10141] mov r9, r14
  [0x10144] ucomiss xmm7, xmm6
  [0x10147] jnb 0x0000000000010152
  [0x1014D] lea r9, [r14+0x08]
  [0x10152] mov r8, r14
  [0x10155] cmp r9, r8
  [0x10158] jz 0x00000000000101E5
  [0x1015E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10166] mov r8d, 0x0C
  [0x1016C] mov ecx, [r15+r13*1+0x6C]
  [0x10171] mov ecx, [r15+rcx*1+0x644]
  [0x10179] add r8, rcx
  [0x1017C] mov ecx, 0x61C
  [0x10181] mov edx, [r15+r13*1+0x6C]
  [0x10186] add rcx, rdx
  [0x10189] mov rdi, r11
  [0x1018C] vmovaps xmm6, [r15+r8*1]
  [0x10192] vmovaps xmm5, [r15+rcx*1]
  [0x10198] vmovaps xmm7, [0x00000000000101A0]
  [0x101A0] vsubps xmm6, xmm6, xmm5
  [0x101A4] vblendps xmm6, xmm6, xmm7, 0x08
  [0x101AA] vmovaps [r15+rdi*1], xmm6
  [0x101B0] movss xmm7, dword ptr [0x00000000000101B8]
  [0x101B8] movd esi, xmm7
  [0x101BC] movsxd rsi, esi
  [0x101BF] add r9, r15
  [0x101C2] call r9
  [0x101C5] movss xmm7, dword ptr [0x00000000000101CD]
  [0x101CD] movss xmm6, dword ptr [r15+r11*1+0x04]
  [0x101D4] mov r9, r14
  [0x101D7] ucomiss xmm7, xmm6
  [0x101DA] jnb 0x00000000000101E5
  [0x101E0] lea r9, [r14+0x08]
  [0x101E5] mov r8, r14
  [0x101E8] cmp r9, r8
  [0x101EB] jz 0x00000000000104B0
  [0x101F1] movss xmm7, dword ptr [0x00000000000101F9]
  [0x101F9] movss xmm6, dword ptr [r15+r11*1+0x04]
  [0x10200] ucomiss xmm7, xmm6
  [0x10203] jnb 0x00000000000102E6
  [0x10209] lea rsi, [rsp+0x20]
  [0x1020E] sub rsi, r15
  [0x10211] mov [r15+rsi*1+0x04], r13d
  [0x10216] mov r9d, 0x02
  [0x1021C] mov [r15+rsi*1+0x08], r9d
  [0x10221] lea r9, [r14+0xAFECAFE]
  [0x10229] mov [r15+rsi*1+0x0C], r9d
  [0x1022E] mov r9, [r15+rbx*1+0x10]
  [0x10233] mov [r15+rsi*1+0x10], r9
  [0x10238] mov r9d, [r15+r13*1+0x6C]
  [0x1023D] movss xmm7, dword ptr [r15+r9*1+0x19C]
  [0x10247] mov r9d, 0x3C
  [0x1024D] mov r8d, [r15+r13*1+0x6C]
  [0x10252] add r9, r8
  [0x10255] mov r8d, 0x1C
  [0x1025B] mov ecx, [r15+r13*1+0x6C]
  [0x10260] mov ecx, [r15+rcx*1+0x1B0]
  [0x10268] add r8, rcx
  [0x1026B] movss xmm6, dword ptr [0x0000000000010273]
  [0x10273] movss xmm5, dword ptr [r15+r9*1]
  [0x10279] movss xmm4, dword ptr [r15+r8*1]
  [0x1027F] mulss xmm5, xmm4
  [0x10283] addss xmm6, xmm5
  [0x10287] movss xmm5, dword ptr [r15+r9*1+0x04]
  [0x1028E] movss xmm4, dword ptr [r15+r8*1+0x04]
  [0x10295] mulss xmm5, xmm4
  [0x10299] addss xmm6, xmm5
  [0x1029D] movss xmm5, dword ptr [r15+r9*1+0x08]
  [0x102A4] movss xmm4, dword ptr [r15+r8*1+0x08]
  [0x102AB] mulss xmm5, xmm4
  [0x102AF] addss xmm6, xmm5
  [0x102B3] movss xmm5, dword ptr [0x00000000000102BB]
  [0x102BB] subss xmm5, xmm6
  [0x102BF] maxss xmm7, xmm5
  [0x102C3] movd r9d, xmm7
  [0x102C8] movsxd r9, r9d
  [0x102CB] mov [r15+rsi*1+0x18], r9
  [0x102D0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102D8] mov rdi, r12
  [0x102DB] add r9, r15
  [0x102DE] call r9
  [0x102E1] jmp 0x00000000000102E9
  [0x102E6] mov rax, r14
  [0x102E9] mov r9d, 0x1C
  [0x102EF] mov r8d, [r15+r13*1+0x6C]
  [0x102F4] mov r8d, [r15+r8*1+0x1B0]
  [0x102FC] add r9, r8
  [0x102FF] lea r8, [rsp+0x70]
  [0x10304] sub r8, r15
  [0x10307] mov ecx, 0x91C
  [0x1030C] mov edx, [r15+r13*1+0x6C]
  [0x10311] add rcx, rdx
  [0x10314] mov edx, 0x0C
  [0x10319] mov esi, [r15+r13*1+0x6C]
  [0x1031E] add rdx, rsi
  [0x10321] vmovaps xmm6, [r15+rcx*1]
  [0x10327] vmovaps xmm5, [r15+rdx*1]
  [0x1032D] vmovaps xmm7, [0x0000000000010335]
  [0x10335] vsubps xmm6, xmm6, xmm5
  [0x10339] vblendps xmm6, xmm6, xmm7, 0x08
  [0x1033F] vmovaps [r15+r8*1], xmm6
  [0x10345] movss xmm7, dword ptr [0x000000000001034D]
  [0x1034D] movss xmm6, dword ptr [r15+r9*1]
  [0x10353] movss xmm5, dword ptr [r15+r8*1]
  [0x10359] mulss xmm6, xmm5
  [0x1035D] addss xmm7, xmm6
  [0x10361] movss xmm6, dword ptr [r15+r9*1+0x04]
  [0x10368] movss xmm5, dword ptr [r15+r8*1+0x04]
  [0x1036F] mulss xmm6, xmm5
  [0x10373] addss xmm7, xmm6
  [0x10377] movss xmm6, dword ptr [r15+r9*1+0x08]
  [0x1037E] movss xmm5, dword ptr [r15+r8*1+0x08]
  [0x10385] mulss xmm6, xmm5
  [0x10389] addss xmm7, xmm6
  [0x1038D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10395] movss xmm6, dword ptr [r15+r9*1+0x90]
  [0x1039F] ucomiss xmm6, xmm7
  [0x103A2] jnb 0x00000000000104A5
  [0x103A8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103B0] lea rsi, [r14+0xAFECAFE]
  [0x103B8] mov rdx, [r15+rbx*1+0x10]
  [0x103BD] mov r8d, [r15+r13*1+0x6C]
  [0x103C2] mov rcx, [r15+r8*1+0x954]
  [0x103CA] mov r8d, [r15+r13*1+0x6C]
  [0x103CF] mov r8, [r15+r8*1+0x95C]
  [0x103D7] mov rdi, r12
  [0x103DA] add r9, r15
  [0x103DD] call r9
  [0x103E0] mov r9, r14
  [0x103E3] cmp rax, r9
  [0x103E6] jz 0x0000000000010411
  [0x103EC] mov r9d, [r15+r13*1+0xA0]
  [0x103F4] mov r8d, 0x8008
  [0x103FA] and r9, r8
  [0x103FD] xor r8, r8
  [0x10400] mov rax, r14
  [0x10403] cmp r9, r8
  [0x10406] jnz 0x0000000000010411
  [0x1040C] lea rax, [r14+0x08]
  [0x10411] mov r9, r14
  [0x10414] cmp rax, r9
  [0x10417] jz 0x000000000001049D
  [0x1041D] mov r9d, [r15+r13*1+0x6C]
  [0x10422] vmovaps xmm7, [r15+r9*1+0x0C]
  [0x10429] mov r9d, [r15+r13*1+0x6C]
  [0x1042E] vmovaps [r15+r9*1+0x4BC], xmm7
  [0x10438] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10440] mov edi, 0x1E
  [0x10445] mov rsi, r13
  [0x10448] add r9, r15
  [0x1044B] call r9
  [0x1044E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10456] mov [r15+r13*1+0x48], r9d
  [0x1045B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10463] movss xmm7, dword ptr [r15+r9*1+0x04]
  [0x1046A] movd edi, xmm7
  [0x1046E] movsxd rdi, edi
  [0x10471] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10479] movss xmm7, dword ptr [r15+r9*1+0x08]
  [0x10480] movd esi, xmm7
  [0x10484] movsxd rsi, esi
  [0x10487] mov rdx, r14
  [0x1048A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10492] add r9, r15
  [0x10495] call r9
  [0x10498] jmp 0x00000000000104A0
  [0x1049D] mov rax, r14
  [0x104A0] jmp 0x00000000000104A8
  [0x104A5] mov rax, r14
  [0x104A8] mov rax, r14
  [0x104AB] jmp 0x0000000000010584
  [0x104B0] lea r9, [r14+0xAFECAFE]
  [0x104B8] cmp rbp, r9
  [0x104BB] jnz 0x0000000000010581
  [0x104C1] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x104C9] mov r9, 0x6E6F6C2D706D756A
  [0x104D3] movq xmm7, r9
  [0x104D8] mov r9d, 0x67
  [0x104DE] movq xmm8, r9
  [0x104E3] vpunpcklqdq xmm8, xmm7, xmm8
  [0x104E8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104F0] add r9, r15
  [0x104F3] call r9
  [0x104F6] movss xmm7, dword ptr [0x00000000000104FE]
  [0x104FE] movss xmm6, dword ptr [0x0000000000010506]
  [0x10506] divss xmm7, xmm6
  [0x1050A] movss xmm6, dword ptr [0x0000000000010512]
  [0x10512] mulss xmm7, xmm6
  [0x10516] cvttss2si esi, xmm7
  [0x1051A] movsxd rsi, esi
  [0x1051D] movss xmm7, dword ptr [0x0000000000010525]
  [0x10525] xor r9, r9
  [0x10528] cvtsi2ss xmm6, r9d
  [0x1052D] mulss xmm7, xmm6
  [0x10531] cvttss2si edx, xmm7
  [0x10535] movsxd rdx, edx
  [0x10538] xor rcx, rcx
  [0x1053B] mov r8d, 0x01
  [0x10541] lea r9, [r14+0x08]
  [0x10546] vmovaps xmm1, xmm8
  [0x1054A] mov rdi, rax
  [0x1054D] add rbp, r15
  [0x10550] call rbp
  [0x10552] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1055A] mov [r15+r13*1+0x48], r9d
  [0x1055F] mov rdi, [r15+rbx*1+0x10]
  [0x10564] mov rsi, [r15+rbx*1+0x18]
  [0x10569] mov rdx, [r15+rbx*1+0x20]
  [0x1056E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10576] add r9, r15
  [0x10579] call r9
  [0x1057C] jmp 0x0000000000010584
  [0x10581] mov rax, r14
  [0x10584] add rsp, 0x80
  [0x1058B] pop r12
  [0x1058D] pop r11
  [0x1058F] pop rbp
  [0x10590] pop rbx
  [0x10591] movdqa xmm8, [rsp]
  [0x10597] add rsp, 0x18
  [0x1059B] ret


[target-dangerous-event-handler]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r11
  [0x10004] push r12
  [0x10006] push rbx
  [0x10007] mov rbx, rdi
  [0x1000A] mov rbp, rsi
  [0x1000D] mov r12, rdx
  [0x10010] mov r11, rcx
  [0x10013] mov r9, r12
  [0x10016] lea r8, [r14+0xAFECAFE]
  [0x1001E] cmp r9, r8
  [0x10021] jnz 0x00000000000100B6
  [0x10027] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1002F] mov r9d, [r15+r9*1+0x40]
  [0x10034] mov rdi, [r15+r11*1+0x10]
  [0x10039] mov esi, [r15+r13*1+0x6C]
  [0x1003E] mov edx, 0xE0
  [0x10043] add r9, r15
  [0x10046] call r9
  [0x10049] mov r9, r14
  [0x1004C] cmp rax, r9
  [0x1004F] jz 0x0000000000010097
  [0x10055] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1005D] mov r8d, [r15+r13*1+0x6C]
  [0x10062] mov esi, [r15+r8*1+0x94C]
  [0x1006A] mov rdx, [r15+r11*1+0x10]
  [0x1006F] mov r8d, [r15+r13*1+0x6C]
  [0x10074] mov rcx, [r15+r8*1+0x954]
  [0x1007C] mov r8d, [r15+r13*1+0x6C]
  [0x10081] mov r8, [r15+r8*1+0x95C]
  [0x10089] mov rdi, rbx
  [0x1008C] add r9, r15
  [0x1008F] call r9
  [0x10092] jmp 0x00000000000100B1
  [0x10097] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1009F] mov rdi, rbx
  [0x100A2] mov rsi, rbp
  [0x100A5] mov rdx, r12
  [0x100A8] mov rcx, r11
  [0x100AB] add r9, r15
  [0x100AE] call r9
  [0x100B1] jmp 0x0000000000010173
  [0x100B6] lea r8, [r14+0xAFECAFE]
  [0x100BE] mov rcx, r14
  [0x100C1] cmp r9, r8
  [0x100C4] jnz 0x00000000000100CF
  [0x100CA] lea rcx, [r14+0x08]
  [0x100CF] mov r8, rcx
  [0x100D2] mov rcx, r14
  [0x100D5] cmp r8, rcx
  [0x100D8] jnz 0x0000000000010122
  [0x100DE] lea r8, [r14+0xAFECAFE]
  [0x100E6] mov rcx, r14
  [0x100E9] cmp r9, r8
  [0x100EC] jnz 0x00000000000100F7
  [0x100F2] lea rcx, [r14+0x08]
  [0x100F7] mov r8, rcx
  [0x100FA] mov rcx, r14
  [0x100FD] cmp r8, rcx
  [0x10100] jnz 0x0000000000010122
  [0x10106] lea r8, [r14+0xAFECAFE]
  [0x1010E] mov rcx, r14
  [0x10111] cmp r9, r8
  [0x10114] jnz 0x000000000001011F
  [0x1011A] lea rcx, [r14+0x08]
  [0x1011F] mov r8, rcx
  [0x10122] mov r9, r14
  [0x10125] cmp r8, r9
  [0x10128] jz 0x0000000000010159
  [0x1012E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10136] mov rsi, [r15+r11*1+0x18]
  [0x1013B] mov rcx, [r15+r11*1+0x10]
  [0x10140] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10148] mov rdi, r12
  [0x1014B] mov rdx, rbx
  [0x1014E] add r9, r15
  [0x10151] call r9
  [0x10154] jmp 0x0000000000010173
  [0x10159] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10161] mov rdi, rbx
  [0x10164] mov rsi, rbp
  [0x10167] mov rdx, r12
  [0x1016A] mov rcx, r11
  [0x1016D] add r9, r15
  [0x10170] call r9
  [0x10173] pop rbx
  [0x10174] pop r12
  [0x10176] pop r11
  [0x10178] pop rbp
  [0x10179] pop rbx
  [0x1017A] ret


[target-apply-tongue]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x38
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] movdqa [rsp+0x10], xmm9
  [0x10011] movdqa [rsp+0x20], xmm10
  [0x10018] push rbx
  [0x10019] push rbp
  [0x1001A] sub rsp, 0x10
  [0x1001E] mov r9d, [r15+r13*1+0xA0]
  [0x10026] mov r8d, 0x08
  [0x1002C] and r9, r8
  [0x1002F] xor r8, r8
  [0x10032] cmp r9, r8
  [0x10035] jnz 0x000000000001021E
  [0x1003B] mov r9d, [r15+r13*1+0xA0]
  [0x10043] mov r8d, 0x7000
  [0x10049] or r9, r8
  [0x1004C] mov [r15+r13*1+0xA0], r9d
  [0x10054] mov rbx, rsp
  [0x10057] sub rbx, r15
  [0x1005A] mov r9d, 0x0C
  [0x10060] mov r8d, [r15+r13*1+0x6C]
  [0x10065] add r9, r8
  [0x10068] vmovaps xmm6, [r15+rdi*1]
  [0x1006E] vmovaps xmm5, [r15+r9*1]
  [0x10074] vmovaps xmm7, [0x000000000001007C]
  [0x1007C] vsubps xmm6, xmm6, xmm5
  [0x10080] vblendps xmm6, xmm6, xmm7, 0x08
  [0x10086] vmovaps [r15+rbx*1], xmm6
  [0x1008C] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10094] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1009C] movss xmm9, dword ptr [r15+r9*1+0x240]
  [0x100A6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100AE] movss xmm10, dword ptr [r15+r9*1+0x244]
  [0x100B8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100C0] mov rdi, rbx
  [0x100C3] add r9, r15
  [0x100C6] call r9
  [0x100C9] movss xmm7, dword ptr [0x00000000000100D1]
  [0x100D1] movss xmm6, dword ptr [0x00000000000100D9]
  [0x100D9] movd edi, xmm9
  [0x100DE] movsxd rdi, edi
  [0x100E1] movd esi, xmm10
  [0x100E6] movsxd rsi, esi
  [0x100E9] mov rdx, rax
  [0x100EC] movd ecx, xmm7
  [0x100F0] movsxd rcx, ecx
  [0x100F3] movd r8d, xmm6
  [0x100F8] movsxd r8, r8d
  [0x100FB] add rbp, r15
  [0x100FE] call rbp
  [0x10100] mov r9d, [r15+r13*1+0x6C]
  [0x10105] mov [r15+r9*1+0x494], eax
  [0x1010D] mov r9d, [r15+r13*1+0x6C]
  [0x10112] movsxd r9, dword ptr [r15+r9*1+0x498]
  [0x1011A] xor r8, r8
  [0x1011D] cmp r9, r8
  [0x10120] jnz 0x0000000000010156
  [0x10126] mov r9d, 0x47C
  [0x1012C] mov r8d, [r15+r13*1+0x6C]
  [0x10131] add r9, r8
  [0x10134] mov r8, r9
  [0x10137] vxorps xmm8, xmm8, xmm8
  [0x1013C] vmovaps [r15+r8*1], xmm8
  [0x10142] movss xmm7, dword ptr [0x000000000001014A]
  [0x1014A] movss [r15+r9*1+0x0C], xmm7
  [0x10151] jmp 0x0000000000010159
  [0x10156] mov r9, r14
  [0x10159] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10161] mov edx, 0x13C
  [0x10166] mov r8d, [r15+r13*1+0x6C]
  [0x1016B] add rdx, r8
  [0x1016E] mov rdi, rbx
  [0x10171] mov rsi, rbx
  [0x10174] add r9, r15
  [0x10177] call r9
  [0x1017A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10182] movss xmm7, dword ptr [0x000000000001018A]
  [0x1018A] mov rdi, rbx
  [0x1018D] movd esi, xmm7
  [0x10191] movsxd rsi, esi
  [0x10194] add r9, r15
  [0x10197] call r9
  [0x1019A] mov r9d, 0x47C
  [0x101A0] mov r8d, [r15+r13*1+0x6C]
  [0x101A5] add r9, r8
  [0x101A8] mov r8d, 0x47C
  [0x101AE] mov ecx, [r15+r13*1+0x6C]
  [0x101B3] add r8, rcx
  [0x101B6] vmovaps xmm6, [r15+r8*1]
  [0x101BC] vmovaps xmm5, [r15+rbx*1]
  [0x101C2] vmovaps xmm7, [0x00000000000101CA]
  [0x101CA] vaddps xmm6, xmm6, xmm5
  [0x101CE] vblendps xmm6, xmm6, xmm7, 0x08
  [0x101D4] vmovaps [r15+r9*1], xmm6
  [0x101DA] movss xmm7, dword ptr [0x00000000000101E2]
  [0x101E2] mov r9d, [r15+r13*1+0x6C]
  [0x101E7] movss [r15+r9*1+0x48C], xmm7
  [0x101F1] mov r9d, [r15+r13*1+0x6C]
  [0x101F6] movsxd r9, dword ptr [r15+r9*1+0x498]
  [0x101FE] mov r8d, 0x01
  [0x10204] add r9, r8
  [0x10207] mov r8d, [r15+r13*1+0x6C]
  [0x1020C] mov [r15+r8*1+0x498], r9d
  [0x10214] lea rax, [r14+0x08]
  [0x10219] jmp 0x0000000000010221
  [0x1021E] mov rax, r14
  [0x10221] add rsp, 0x10
  [0x10225] pop rbp
  [0x10226] pop rbx
  [0x10227] movdqa xmm10, [rsp+0x20]
  [0x1022E] movdqa xmm9, [rsp+0x10]
  [0x10235] movdqa xmm8, [rsp]
  [0x1023B] add rsp, 0x38
  [0x1023F] ret


[target-send-attack]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x190
  [0x1000F] mov rbp, rdx
  [0x10012] mov r9, rsp
  [0x10015] sub r9, r15
  [0x10018] mov [r15+r9*1+0x04], r13d
  [0x1001D] mov edx, 0x04
  [0x10022] mov [r15+r9*1+0x08], edx
  [0x10027] lea rdx, [r14+0xAFECAFE]
  [0x1002F] mov [r15+r9*1+0x0C], edx
  [0x10034] mov rdx, rbp
  [0x10037] mov [r15+r9*1+0x10], rdx
  [0x1003C] mov [r15+r9*1+0x18], rsi
  [0x10041] mov [r15+r9*1+0x20], rcx
  [0x10046] mov [r15+r9*1+0x28], r8
  [0x1004B] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10053] mov rsi, r9
  [0x10056] add r8, r15
  [0x10059] call r8
  [0x1005C] mov rbx, rax
  [0x1005F] mov r9, rbx
  [0x10062] mov r8, r14
  [0x10065] cmp r9, r8
  [0x10068] jz 0x000000000001008A
  [0x1006E] lea r9, [r14+0xAFECAFE]
  [0x10076] mov r8, r14
  [0x10079] cmp rbx, r9
  [0x1007C] jz 0x0000000000010087
  [0x10082] lea r8, [r14+0x08]
  [0x10087] mov r9, r8
  [0x1008A] mov r8, r14
  [0x1008D] cmp r9, r8
  [0x10090] jz 0x0000000000010D28
  [0x10096] mov r9d, [r15+r13*1+0x6C]
  [0x1009B] mov r9d, [r15+r9*1+0x94C]
  [0x100A3] lea r8, [r14+0xAFECAFE]
  [0x100AB] mov rcx, r14
  [0x100AE] cmp r9, r8
  [0x100B1] jnz 0x00000000000100BC
  [0x100B7] lea rcx, [r14+0x08]
  [0x100BC] mov r8, rcx
  [0x100BF] mov rcx, r14
  [0x100C2] cmp r8, rcx
  [0x100C5] jnz 0x00000000000100E7
  [0x100CB] lea r8, [r14+0xAFECAFE]
  [0x100D3] mov rcx, r14
  [0x100D6] cmp r9, r8
  [0x100D9] jnz 0x00000000000100E4
  [0x100DF] lea rcx, [r14+0x08]
  [0x100E4] mov r8, rcx
  [0x100E7] mov rcx, r14
  [0x100EA] cmp r8, rcx
  [0x100ED] jz 0x000000000001031A
  [0x100F3] mov esi, [r15+r13*1+0x6C]
  [0x100F8] mov edx, 0x40
  [0x100FD] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10105] mov r9d, [r15+r9*1+0x40]
  [0x1010A] mov rdi, rbp
  [0x1010D] add r9, r15
  [0x10110] call r9
  [0x10113] mov r11, rax
  [0x10116] mov r9, r14
  [0x10119] cmp r11, r9
  [0x1011C] jz 0x0000000000010259
  [0x10122] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1012A] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10132] mov edx, 0x4000
  [0x10137] mov r9d, [r15+rdi*1-0x04]
  [0x1013C] mov r9d, [r15+r9*1+0x48]
  [0x10141] add r9, r15
  [0x10144] call r9
  [0x10147] mov r12, rax
  [0x1014A] mov r9, r14
  [0x1014D] cmp r12, r9
  [0x10150] jz 0x0000000000010251
  [0x10156] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1015E] mov r9d, [r15+r9*1+0x34]
  [0x10163] lea rdx, [r14+0xAFECAFE]
  [0x1016B] mov ecx, 0x70004000
  [0x10170] mov rdi, r12
  [0x10173] mov rsi, r13
  [0x10176] add r9, r15
  [0x10179] call r9
  [0x1017C] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10184] mov r9, r8
  [0x10187] mov [rsp+0xE0], r9
  [0x1018F] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10197] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1019F] mov r9d, [r15+r8*1+0x1C]
  [0x101A4] mov [rsp+0xF8], r9
  [0x101AC] mov r9, 0xFFFFFFFFFFFFFFFF
  [0x101B3] mov [rsp+0xF0], r9
  [0x101BB] mov r8, r14
  [0x101BE] mov r9, r8
  [0x101C1] mov [rsp+0x118], r9
  [0x101C9] mov r8, r14
  [0x101CC] mov r9, r8
  [0x101CF] mov [rsp+0x158], r9
  [0x101D7] mov r8, r14
  [0x101DA] mov r9, r8
  [0x101DD] mov [rsp+0x180], r9
  [0x101E5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101ED] lea rdi, [rsp+0x50]
  [0x101F2] sub rdi, r15
  [0x101F5] mov edx, [r15+r13*1+0x6C]
  [0x101FA] mov rsi, r11
  [0x101FD] mov rcx, rbp
  [0x10200] add r9, r15
  [0x10203] call r9
  [0x10206] mov rdi, r12
  [0x10209] mov rsi, r10
  [0x1020C] mov rdx, [rsp+0xF8]
  [0x10214] mov rcx, [rsp+0xF0]
  [0x1021C] mov r8, [rsp+0x118]
  [0x10224] mov r9, [rsp+0x158]
  [0x1022C] mov r10, [rsp+0x180]
  [0x10234] mov r11, rax
  [0x10237] mov rax, [rsp+0xE0]
  [0x1023F] mov rbp, rax
  [0x10242] add rbp, r15
  [0x10245] call rbp
  [0x10247] mov r9d, [r12+r15*1+0x14]
  [0x1024C] jmp 0x0000000000010254
  [0x10251] mov r9, r14
  [0x10254] jmp 0x0000000000010292
  [0x10259] mov r9d, [r15+r13*1+0x78]
  [0x1025E] mov edi, [r15+r9*1+0x24]
  [0x10263] lea rsi, [r14+0xAFECAFE]
  [0x1026B] movss xmm7, dword ptr [0x0000000000010273]
  [0x10273] mov ecx, 0x4A
  [0x10278] mov r9d, [r15+rdi*1-0x04]
  [0x1027D] mov r9d, [r15+r9*1+0x38]
  [0x10282] movd edx, xmm7
  [0x10286] movsxd rdx, edx
  [0x10289] add r9, r15
  [0x1028C] call r9
  [0x1028F] mov r9, rax
  [0x10292] mov r9d, [r15+r13*1+0x78]
  [0x10297] mov edi, [r15+r9*1+0x24]
  [0x1029C] mov r9d, [r15+r13*1+0x6C]
  [0x102A1] mov esi, [r15+r9*1+0x94C]
  [0x102A9] movss xmm7, dword ptr [0x00000000000102B1]
  [0x102B1] mov ecx, 0x4A
  [0x102B6] mov r8, r14
  [0x102B9] mov r9, 0x7469682D6E697073
  [0x102C3] movq xmm6, r9
  [0x102C8] xor r9, r9
  [0x102CB] movq xmm1, r9
  [0x102D0] vpunpcklqdq xmm1, xmm6, xmm1
  [0x102D4] mov r9d, [r15+rdi*1-0x04]
  [0x102D9] mov r9d, [r15+r9*1+0x40]
  [0x102DE] movd edx, xmm7
  [0x102E2] movsxd rdx, edx
  [0x102E5] add r9, r15
  [0x102E8] call r9
  [0x102EB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102F3] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x102FB] mov edi, [r15+r8*1+0x04]
  [0x10300] mov esi, 0x01
  [0x10305] mov edx, 0x7F
  [0x1030A] mov ecx, 0x3C
  [0x1030F] add r9, r15
  [0x10312] call r9
  [0x10315] jmp 0x0000000000010D23
  [0x1031A] lea r8, [r14+0xAFECAFE]
  [0x10322] cmp r9, r8
  [0x10325] jnz 0x00000000000106C1
  [0x1032B] mov esi, [r15+r13*1+0x6C]
  [0x10330] mov edx, 0x40
  [0x10335] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1033D] mov r9d, [r15+r9*1+0x40]
  [0x10342] mov rdi, rbp
  [0x10345] add r9, r15
  [0x10348] call r9
  [0x1034B] mov r12, rax
  [0x1034E] mov r9, r14
  [0x10351] cmp r12, r9
  [0x10354] jz 0x00000000000104AF
  [0x1035A] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10362] mov esi, [r15+r14*1+0xBADBEEF]
  [0x1036A] mov edx, 0x4000
  [0x1036F] mov r9d, [r15+rdi*1-0x04]
  [0x10374] mov r9d, [r15+r9*1+0x48]
  [0x10379] add r9, r15
  [0x1037C] call r9
  [0x1037F] mov r9, rax
  [0x10382] mov [rsp+0xB0], r9
  [0x1038A] mov r8, r14
  [0x1038D] mov r9, [rsp+0xB0]
  [0x10395] cmp r9, r8
  [0x10398] jz 0x00000000000104A7
  [0x1039E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103A6] mov r8d, [r15+r9*1+0x34]
  [0x103AB] lea rdx, [r14+0xAFECAFE]
  [0x103B3] mov ecx, 0x70004000
  [0x103B8] mov r9, [rsp+0xB0]
  [0x103C0] mov rdi, r9
  [0x103C3] mov rsi, r13
  [0x103C6] add r8, r15
  [0x103C9] call r8
  [0x103CC] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x103D4] mov r9, r8
  [0x103D7] mov [rsp+0xC8], r9
  [0x103DF] mov r11d, [r15+r14*1+0xBADBEEF]
  [0x103E7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103EF] mov r10d, [r15+r9*1+0x20]
  [0x103F4] mov r9, 0xFFFFFFFFFFFFFFFF
  [0x103FB] mov [rsp+0x100], r9
  [0x10403] mov r8, r14
  [0x10406] mov r9, r8
  [0x10409] mov [rsp+0x130], r9
  [0x10411] mov r8, r14
  [0x10414] mov r9, r8
  [0x10417] mov [rsp+0x160], r9
  [0x1041F] mov r8, r14
  [0x10422] mov r9, r8
  [0x10425] mov [rsp+0x170], r9
  [0x1042D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10435] lea rdi, [rsp+0x60]
  [0x1043A] sub rdi, r15
  [0x1043D] mov edx, [r15+r13*1+0x6C]
  [0x10442] mov rsi, r12
  [0x10445] mov rcx, rbp
  [0x10448] add r9, r15
  [0x1044B] call r9
  [0x1044E] mov r9, [rsp+0xB0]
  [0x10456] mov rdi, r9
  [0x10459] mov rsi, r11
  [0x1045C] mov rdx, r10
  [0x1045F] mov rcx, [rsp+0x100]
  [0x10467] mov r8, [rsp+0x130]
  [0x1046F] mov r9, [rsp+0x160]
  [0x10477] mov r10, [rsp+0x170]
  [0x1047F] mov r11, rax
  [0x10482] mov rax, [rsp+0xC8]
  [0x1048A] mov rbp, rax
  [0x1048D] add rbp, r15
  [0x10490] call rbp
  [0x10492] mov r9, [rsp+0xB0]
  [0x1049A] mov r8d, [r15+r9*1+0x14]
  [0x1049F] mov r9, r8
  [0x104A2] jmp 0x00000000000104AA
  [0x104A7] mov r9, r14
  [0x104AA] jmp 0x0000000000010636
  [0x104AF] mov esi, [r15+r13*1+0x6C]
  [0x104B4] mov edx, 0x20
  [0x104B9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104C1] mov r9d, [r15+r9*1+0x40]
  [0x104C6] mov rdi, rbp
  [0x104C9] add r9, r15
  [0x104CC] call r9
  [0x104CF] mov r12, rax
  [0x104D2] mov r9, r14
  [0x104D5] cmp rax, r9
  [0x104D8] jz 0x0000000000010633
  [0x104DE] mov edi, [r15+r14*1+0xBADBEEF]
  [0x104E6] mov esi, [r15+r14*1+0xBADBEEF]
  [0x104EE] mov edx, 0x4000
  [0x104F3] mov r9d, [r15+rdi*1-0x04]
  [0x104F8] mov r9d, [r15+r9*1+0x48]
  [0x104FD] add r9, r15
  [0x10500] call r9
  [0x10503] mov r9, rax
  [0x10506] mov [rsp+0xA0], r9
  [0x1050E] mov r8, r14
  [0x10511] mov r9, [rsp+0xA0]
  [0x10519] cmp r9, r8
  [0x1051C] jz 0x000000000001062B
  [0x10522] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1052A] mov r8d, [r15+r9*1+0x34]
  [0x1052F] lea rdx, [r14+0xAFECAFE]
  [0x10537] mov ecx, 0x70004000
  [0x1053C] mov r9, [rsp+0xA0]
  [0x10544] mov rdi, r9
  [0x10547] mov rsi, r13
  [0x1054A] add r8, r15
  [0x1054D] call r8
  [0x10550] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10558] mov r9, r8
  [0x1055B] mov [rsp+0xC0], r9
  [0x10563] mov r11d, [r15+r14*1+0xBADBEEF]
  [0x1056B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10573] mov r10d, [r15+r9*1+0x20]
  [0x10578] mov r9, 0xFFFFFFFFFFFFFFFF
  [0x1057F] mov [rsp+0x108], r9
  [0x10587] mov r8, r14
  [0x1058A] mov r9, r8
  [0x1058D] mov [rsp+0x120], r9
  [0x10595] mov r8, r14
  [0x10598] mov r9, r8
  [0x1059B] mov [rsp+0x150], r9
  [0x105A3] mov r8, r14
  [0x105A6] mov r9, r8
  [0x105A9] mov [rsp+0x178], r9
  [0x105B1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105B9] lea rdi, [rsp+0x70]
  [0x105BE] sub rdi, r15
  [0x105C1] mov edx, [r15+r13*1+0x6C]
  [0x105C6] mov rsi, r12
  [0x105C9] mov rcx, rbp
  [0x105CC] add r9, r15
  [0x105CF] call r9
  [0x105D2] mov r9, [rsp+0xA0]
  [0x105DA] mov rdi, r9
  [0x105DD] mov rsi, r11
  [0x105E0] mov rdx, r10
  [0x105E3] mov rcx, [rsp+0x108]
  [0x105EB] mov r8, [rsp+0x120]
  [0x105F3] mov r9, [rsp+0x150]
  [0x105FB] mov r10, [rsp+0x178]
  [0x10603] mov r11, rax
  [0x10606] mov rax, [rsp+0xC0]
  [0x1060E] mov rbp, rax
  [0x10611] add rbp, r15
  [0x10614] call rbp
  [0x10616] mov r9, [rsp+0xA0]
  [0x1061E] mov r8d, [r15+r9*1+0x14]
  [0x10623] mov r9, r8
  [0x10626] jmp 0x000000000001062E
  [0x1062B] mov r9, r14
  [0x1062E] jmp 0x0000000000010636
  [0x10633] mov r9, r14
  [0x10636] mov r9d, [r15+r13*1+0x78]
  [0x1063B] mov edi, [r15+r9*1+0x24]
  [0x10640] mov r9d, [r15+r13*1+0x6C]
  [0x10645] mov esi, [r15+r9*1+0x94C]
  [0x1064D] movss xmm7, dword ptr [0x0000000000010655]
  [0x10655] mov ecx, 0x17
  [0x1065A] mov r8, r14
  [0x1065D] mov r9, 0x69682D68636E7570
  [0x10667] movq xmm6, r9
  [0x1066C] mov r9d, 0x74
  [0x10672] movq xmm1, r9
  [0x10677] vpunpcklqdq xmm1, xmm6, xmm1
  [0x1067B] mov r9d, [r15+rdi*1-0x04]
  [0x10680] mov r9d, [r15+r9*1+0x40]
  [0x10685] movd edx, xmm7
  [0x10689] movsxd rdx, edx
  [0x1068C] add r9, r15
  [0x1068F] call r9
  [0x10692] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1069A] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x106A2] mov edi, [r15+r8*1+0x04]
  [0x106A7] mov esi, 0x01
  [0x106AC] mov edx, 0xB2
  [0x106B1] mov ecx, 0x1E
  [0x106B6] add r9, r15
  [0x106B9] call r9
  [0x106BC] jmp 0x0000000000010D23
  [0x106C1] lea r8, [r14+0xAFECAFE]
  [0x106C9] cmp r9, r8
  [0x106CC] jnz 0x000000000001075D
  [0x106D2] mov r9d, [r15+r13*1+0x78]
  [0x106D7] mov edi, [r15+r9*1+0x24]
  [0x106DC] mov r9d, [r15+r13*1+0x6C]
  [0x106E1] mov esi, [r15+r9*1+0x94C]
  [0x106E9] movss xmm7, dword ptr [0x00000000000106F1]
  [0x106F1] mov ecx, 0x4A
  [0x106F6] mov r8, r14
  [0x106F9] mov r9, 0x69682D68636E7570
  [0x10703] movq xmm6, r9
  [0x10708] mov r9d, 0x74
  [0x1070E] movq xmm1, r9
  [0x10713] vpunpcklqdq xmm1, xmm6, xmm1
  [0x10717] mov r9d, [r15+rdi*1-0x04]
  [0x1071C] mov r9d, [r15+r9*1+0x40]
  [0x10721] movd edx, xmm7
  [0x10725] movsxd rdx, edx
  [0x10728] add r9, r15
  [0x1072B] call r9
  [0x1072E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10736] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1073E] mov edi, [r15+r8*1+0x04]
  [0x10743] mov esi, 0x01
  [0x10748] mov edx, 0x7F
  [0x1074D] mov ecx, 0x1E
  [0x10752] add r9, r15
  [0x10755] call r9
  [0x10758] jmp 0x0000000000010D23
  [0x1075D] lea r8, [r14+0xAFECAFE]
  [0x10765] cmp r9, r8
  [0x10768] jnz 0x0000000000010B40
  [0x1076E] mov esi, [r15+r13*1+0x6C]
  [0x10773] mov edx, 0x40
  [0x10778] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10780] mov r9d, [r15+r9*1+0x40]
  [0x10785] mov rdi, rbp
  [0x10788] add r9, r15
  [0x1078B] call r9
  [0x1078E] mov r12, rax
  [0x10791] mov r9, r14
  [0x10794] cmp r12, r9
  [0x10797] jz 0x00000000000108F5
  [0x1079D] mov edi, [r15+r14*1+0xBADBEEF]
  [0x107A5] mov esi, [r15+r14*1+0xBADBEEF]
  [0x107AD] mov edx, 0x4000
  [0x107B2] mov r9d, [r15+rdi*1-0x04]
  [0x107B7] mov r9d, [r15+r9*1+0x48]
  [0x107BC] add r9, r15
  [0x107BF] call r9
  [0x107C2] mov r9, rax
  [0x107C5] mov [rsp+0xA8], r9
  [0x107CD] mov r8, r14
  [0x107D0] mov r9, [rsp+0xA8]
  [0x107D8] cmp r9, r8
  [0x107DB] jz 0x00000000000108ED
  [0x107E1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x107E9] mov r8d, [r15+r9*1+0x34]
  [0x107EE] lea rdx, [r14+0xAFECAFE]
  [0x107F6] mov ecx, 0x70004000
  [0x107FB] mov r9, [rsp+0xA8]
  [0x10803] mov rdi, r9
  [0x10806] mov rsi, r13
  [0x10809] add r8, r15
  [0x1080C] call r8
  [0x1080F] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10817] mov r9, r8
  [0x1081A] mov [rsp+0xD0], r9
  [0x10822] mov r11d, [r15+r14*1+0xBADBEEF]
  [0x1082A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10832] mov r10d, [r15+r9*1+0x20]
  [0x10837] mov r9, 0xFFFFFFFFFFFFFFFF
  [0x1083E] mov [rsp+0xE8], r9
  [0x10846] mov r8, r14
  [0x10849] mov r9, r8
  [0x1084C] mov [rsp+0x138], r9
  [0x10854] mov r8, r14
  [0x10857] mov r9, r8
  [0x1085A] mov [rsp+0x140], r9
  [0x10862] mov r8, r14
  [0x10865] mov r9, r8
  [0x10868] mov [rsp+0x168], r9
  [0x10870] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10878] lea rdi, [rsp+0x80]
  [0x10880] sub rdi, r15
  [0x10883] mov edx, [r15+r13*1+0x6C]
  [0x10888] mov rsi, r12
  [0x1088B] mov rcx, rbp
  [0x1088E] add r9, r15
  [0x10891] call r9
  [0x10894] mov r9, [rsp+0xA8]
  [0x1089C] mov rdi, r9
  [0x1089F] mov rsi, r11
  [0x108A2] mov rdx, r10
  [0x108A5] mov rcx, [rsp+0xE8]
  [0x108AD] mov r8, [rsp+0x138]
  [0x108B5] mov r9, [rsp+0x140]
  [0x108BD] mov r10, [rsp+0x168]
  [0x108C5] mov r11, rax
  [0x108C8] mov rax, [rsp+0xD0]
  [0x108D0] mov rbp, rax
  [0x108D3] add rbp, r15
  [0x108D6] call rbp
  [0x108D8] mov r9, [rsp+0xA8]
  [0x108E0] mov r8d, [r15+r9*1+0x14]
  [0x108E5] mov r9, r8
  [0x108E8] jmp 0x00000000000108F0
  [0x108ED] mov r9, r14
  [0x108F0] jmp 0x0000000000010A7F
  [0x108F5] mov esi, [r15+r13*1+0x6C]
  [0x108FA] mov edx, 0x20
  [0x108FF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10907] mov r9d, [r15+r9*1+0x40]
  [0x1090C] mov rdi, rbp
  [0x1090F] add r9, r15
  [0x10912] call r9
  [0x10915] mov r12, rax
  [0x10918] mov r9, r14
  [0x1091B] cmp rax, r9
  [0x1091E] jz 0x0000000000010A7C
  [0x10924] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1092C] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10934] mov edx, 0x4000
  [0x10939] mov r9d, [r15+rdi*1-0x04]
  [0x1093E] mov r9d, [r15+r9*1+0x48]
  [0x10943] add r9, r15
  [0x10946] call r9
  [0x10949] mov r9, rax
  [0x1094C] mov [rsp+0xB8], r9
  [0x10954] mov r8, r14
  [0x10957] mov r9, [rsp+0xB8]
  [0x1095F] cmp r9, r8
  [0x10962] jz 0x0000000000010A74
  [0x10968] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10970] mov r8d, [r15+r9*1+0x34]
  [0x10975] lea rdx, [r14+0xAFECAFE]
  [0x1097D] mov ecx, 0x70004000
  [0x10982] mov r9, [rsp+0xB8]
  [0x1098A] mov rdi, r9
  [0x1098D] mov rsi, r13
  [0x10990] add r8, r15
  [0x10993] call r8
  [0x10996] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1099E] mov r9, r8
  [0x109A1] mov [rsp+0xD8], r9
  [0x109A9] mov r11d, [r15+r14*1+0xBADBEEF]
  [0x109B1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x109B9] mov r10d, [r15+r9*1+0x20]
  [0x109BE] mov r9, 0xFFFFFFFFFFFFFFFF
  [0x109C5] mov [rsp+0x110], r9
  [0x109CD] mov r8, r14
  [0x109D0] mov r9, r8
  [0x109D3] mov [rsp+0x128], r9
  [0x109DB] mov r8, r14
  [0x109DE] mov r9, r8
  [0x109E1] mov [rsp+0x148], r9
  [0x109E9] mov r8, r14
  [0x109EC] mov r9, r8
  [0x109EF] mov [rsp+0x188], r9
  [0x109F7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x109FF] lea rdi, [rsp+0x90]
  [0x10A07] sub rdi, r15
  [0x10A0A] mov edx, [r15+r13*1+0x6C]
  [0x10A0F] mov rsi, r12
  [0x10A12] mov rcx, rbp
  [0x10A15] add r9, r15
  [0x10A18] call r9
  [0x10A1B] mov r9, [rsp+0xB8]
  [0x10A23] mov rdi, r9
  [0x10A26] mov rsi, r11
  [0x10A29] mov rdx, r10
  [0x10A2C] mov rcx, [rsp+0x110]
  [0x10A34] mov r8, [rsp+0x128]
  [0x10A3C] mov r9, [rsp+0x148]
  [0x10A44] mov r10, [rsp+0x188]
  [0x10A4C] mov r11, rax
  [0x10A4F] mov rax, [rsp+0xD8]
  [0x10A57] mov rbp, rax
  [0x10A5A] add rbp, r15
  [0x10A5D] call rbp
  [0x10A5F] mov r9, [rsp+0xB8]
  [0x10A67] mov r8d, [r15+r9*1+0x14]
  [0x10A6C] mov r9, r8
  [0x10A6F] jmp 0x0000000000010A77
  [0x10A74] mov r9, r14
  [0x10A77] jmp 0x0000000000010A7F
  [0x10A7C] mov r9, r14
  [0x10A7F] mov r9d, [r15+r13*1+0x78]
  [0x10A84] mov edi, [r15+r9*1+0x24]
  [0x10A89] lea rsi, [r14+0xAFECAFE]
  [0x10A91] movss xmm7, dword ptr [0x0000000000010A99]
  [0x10A99] mov ecx, 0x17
  [0x10A9E] mov r9d, [r15+rdi*1-0x04]
  [0x10AA3] mov r9d, [r15+r9*1+0x38]
  [0x10AA8] movd edx, xmm7
  [0x10AAC] movsxd rdx, edx
  [0x10AAF] add r9, r15
  [0x10AB2] call r9
  [0x10AB5] mov r9d, [r15+r13*1+0x78]
  [0x10ABA] mov edi, [r15+r9*1+0x24]
  [0x10ABF] mov r9d, [r15+r13*1+0x6C]
  [0x10AC4] mov esi, [r15+r9*1+0x94C]
  [0x10ACC] movss xmm7, dword ptr [0x0000000000010AD4]
  [0x10AD4] mov ecx, 0x17
  [0x10AD9] mov r8, r14
  [0x10ADC] mov r9, 0x7475637265707075
  [0x10AE6] movq xmm6, r9
  [0x10AEB] mov r9d, 0x7469682D
  [0x10AF1] movq xmm1, r9
  [0x10AF6] vpunpcklqdq xmm1, xmm6, xmm1
  [0x10AFA] mov r9d, [r15+rdi*1-0x04]
  [0x10AFF] mov r9d, [r15+r9*1+0x40]
  [0x10B04] movd edx, xmm7
  [0x10B08] movsxd rdx, edx
  [0x10B0B] add r9, r15
  [0x10B0E] call r9
  [0x10B11] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10B19] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10B21] mov edi, [r15+r8*1+0x04]
  [0x10B26] mov esi, 0x01
  [0x10B2B] mov edx, 0xB2
  [0x10B30] mov ecx, 0x1E
  [0x10B35] add r9, r15
  [0x10B38] call r9
  [0x10B3B] jmp 0x0000000000010D23
  [0x10B40] lea r8, [r14+0xAFECAFE]
  [0x10B48] mov rcx, r14
  [0x10B4B] cmp r9, r8
  [0x10B4E] jnz 0x0000000000010B59
  [0x10B54] lea rcx, [r14+0x08]
  [0x10B59] mov r8, rcx
  [0x10B5C] mov rcx, r14
  [0x10B5F] cmp r8, rcx
  [0x10B62] jnz 0x0000000000010B84
  [0x10B68] lea r8, [r14+0xAFECAFE]
  [0x10B70] mov rcx, r14
  [0x10B73] cmp r9, r8
  [0x10B76] jnz 0x0000000000010B81
  [0x10B7C] lea rcx, [r14+0x08]
  [0x10B81] mov r8, rcx
  [0x10B84] mov rcx, r14
  [0x10B87] cmp r8, rcx
  [0x10B8A] jz 0x0000000000010C84
  [0x10B90] mov r9d, [r15+r13*1+0x78]
  [0x10B95] mov edi, [r15+r9*1+0x24]
  [0x10B9A] lea rsi, [r14+0xAFECAFE]
  [0x10BA2] movss xmm7, dword ptr [0x0000000000010BAA]
  [0x10BAA] mov ecx, 0x17
  [0x10BAF] mov r9d, [r15+rdi*1-0x04]
  [0x10BB4] mov r9d, [r15+r9*1+0x38]
  [0x10BB9] movd edx, xmm7
  [0x10BBD] movsxd rdx, edx
  [0x10BC0] add r9, r15
  [0x10BC3] call r9
  [0x10BC6] mov r9d, [r15+r13*1+0x78]
  [0x10BCB] mov edi, [r15+r9*1+0x24]
  [0x10BD0] lea rsi, [r14+0xAFECAFE]
  [0x10BD8] movss xmm7, dword ptr [0x0000000000010BE0]
  [0x10BE0] mov ecx, 0x11
  [0x10BE5] mov r9d, [r15+rdi*1-0x04]
  [0x10BEA] mov r9d, [r15+r9*1+0x38]
  [0x10BEF] movd edx, xmm7
  [0x10BF3] movsxd rdx, edx
  [0x10BF6] add r9, r15
  [0x10BF9] call r9
  [0x10BFC] mov r9d, [r15+r13*1+0x78]
  [0x10C01] mov edi, [r15+r9*1+0x24]
  [0x10C06] mov r9d, [r15+r13*1+0x6C]
  [0x10C0B] mov esi, [r15+r9*1+0x94C]
  [0x10C13] movss xmm7, dword ptr [0x0000000000010C1B]
  [0x10C1B] mov ecx, 0x17
  [0x10C20] mov r8, r14
  [0x10C23] mov r9, 0x7469682D706F6C66
  [0x10C2D] movq xmm6, r9
  [0x10C32] xor r9, r9
  [0x10C35] movq xmm1, r9
  [0x10C3A] vpunpcklqdq xmm1, xmm6, xmm1
  [0x10C3E] mov r9d, [r15+rdi*1-0x04]
  [0x10C43] mov r9d, [r15+r9*1+0x40]
  [0x10C48] movd edx, xmm7
  [0x10C4C] movsxd rdx, edx
  [0x10C4F] add r9, r15
  [0x10C52] call r9
  [0x10C55] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C5D] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10C65] mov edi, [r15+r8*1+0x04]
  [0x10C6A] mov esi, 0x01
  [0x10C6F] mov edx, 0xB2
  [0x10C74] mov ecx, 0x1E
  [0x10C79] add r9, r15
  [0x10C7C] call r9
  [0x10C7F] jmp 0x0000000000010D23
  [0x10C84] lea r8, [r14+0xAFECAFE]
  [0x10C8C] cmp r9, r8
  [0x10C8F] jnz 0x0000000000010D20
  [0x10C95] mov r9d, [r15+r13*1+0x78]
  [0x10C9A] mov edi, [r15+r9*1+0x24]
  [0x10C9F] mov r9d, [r15+r13*1+0x6C]
  [0x10CA4] mov esi, [r15+r9*1+0x94C]
  [0x10CAC] movss xmm7, dword ptr [0x0000000000010CB4]
  [0x10CB4] mov ecx, 0x17
  [0x10CB9] mov r8, r14
  [0x10CBC] mov r9, 0x69682D68636E7570
  [0x10CC6] movq xmm6, r9
  [0x10CCB] mov r9d, 0x74
  [0x10CD1] movq xmm1, r9
  [0x10CD6] vpunpcklqdq xmm1, xmm6, xmm1
  [0x10CDA] mov r9d, [r15+rdi*1-0x04]
  [0x10CDF] mov r9d, [r15+r9*1+0x40]
  [0x10CE4] movd edx, xmm7
  [0x10CE8] movsxd rdx, edx
  [0x10CEB] add r9, r15
  [0x10CEE] call r9
  [0x10CF1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10CF9] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10D01] mov edi, [r15+r8*1+0x04]
  [0x10D06] mov esi, 0x01
  [0x10D0B] mov edx, 0xFF
  [0x10D10] mov ecx, 0x3C
  [0x10D15] add r9, r15
  [0x10D18] call r9
  [0x10D1B] jmp 0x0000000000010D23
  [0x10D20] mov rbp, r14
  [0x10D23] jmp 0x0000000000010D2B
  [0x10D28] mov rbp, r14
  [0x10D2B] mov rax, rbx
  [0x10D2E] add rsp, 0x190
  [0x10D35] pop r12
  [0x10D37] pop r11
  [0x10D39] pop r10
  [0x10D3B] pop rbp
  [0x10D3C] pop rbx
  [0x10D3D] ret


[target-standard-event-handler]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9, rdx
  [0x10007] lea r8, [r14+0xAFECAFE]
  [0x1000F] mov rdi, r14
  [0x10012] cmp r9, r8
  [0x10015] jnz 0x0000000000010020
  [0x1001B] lea rdi, [r14+0x08]
  [0x10020] mov r8, rdi
  [0x10023] mov rdi, r14
  [0x10026] cmp r8, rdi
  [0x10029] jnz 0x0000000000010073
  [0x1002F] lea r8, [r14+0xAFECAFE]
  [0x10037] mov rdi, r14
  [0x1003A] cmp r9, r8
  [0x1003D] jnz 0x0000000000010048
  [0x10043] lea rdi, [r14+0x08]
  [0x10048] mov r8, rdi
  [0x1004B] mov rdi, r14
  [0x1004E] cmp r8, rdi
  [0x10051] jnz 0x0000000000010073
  [0x10057] lea r8, [r14+0xAFECAFE]
  [0x1005F] mov rdi, r14
  [0x10062] cmp r9, r8
  [0x10065] jnz 0x0000000000010070
  [0x1006B] lea rdi, [r14+0x08]
  [0x10070] mov r8, rdi
  [0x10073] mov rdi, r14
  [0x10076] cmp r8, rdi
  [0x10079] jz 0x00000000000100AA
  [0x1007F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10087] mov rsi, [r15+rcx*1+0x18]
  [0x1008C] mov rcx, [r15+rcx*1+0x10]
  [0x10091] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10099] mov rdi, rdx
  [0x1009C] mov rdx, rbx
  [0x1009F] add r9, r15
  [0x100A2] call r9
  [0x100A5] jmp 0x0000000000010CDD
  [0x100AA] lea r8, [r14+0xAFECAFE]
  [0x100B2] cmp r9, r8
  [0x100B5] jnz 0x00000000000101AA
  [0x100BB] mov r9d, [r15+r13*1+0x48]
  [0x100C0] mov r9d, [r15+r9*1]
  [0x100C4] lea r8, [r14+0xAFECAFE]
  [0x100CC] cmp r9, r8
  [0x100CF] jz 0x00000000000101A2
  [0x100D5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100DD] mov edi, 0x14C
  [0x100E2] add rdi, r13
  [0x100E5] mov rsi, [r15+rcx*1+0x18]
  [0x100EA] mov edx, 0x68
  [0x100EF] add r9, r15
  [0x100F2] call r9
  [0x100F5] mov r9d, [r15+r13*1+0x18C]
  [0x100FD] mov r8d, 0x08
  [0x10103] and r9, r8
  [0x10106] xor r8, r8
  [0x10109] cmp r9, r8
  [0x1010C] jnz 0x000000000001016F
  [0x10112] mov r9, r14
  [0x10115] cmp rbx, r9
  [0x10118] jz 0x0000000000010128
  [0x1011E] mov r9d, [r15+rbx*1+0x14]
  [0x10123] jmp 0x000000000001012B
  [0x10128] mov r9, r14
  [0x1012B] mov r8d, [r15+r9*1]
  [0x1012F] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x10134] xor rcx, rcx
  [0x10137] shl r9, 0x20
  [0x1013B] shr r9, 0x20
  [0x1013F] or rcx, r9
  [0x10142] shl r8, 0x20
  [0x10146] or rcx, r8
  [0x10149] mov [r15+r13*1+0x17C], rcx
  [0x10151] mov r9d, [r15+r13*1+0x18C]
  [0x10159] mov r8d, 0x08
  [0x1015F] or r9, r8
  [0x10162] mov [r15+r13*1+0x18C], r9d
  [0x1016A] jmp 0x0000000000010172
  [0x1016F] mov r9, r14
  [0x10172] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1017A] mov [r15+r13*1+0x48], r9d
  [0x1017F] lea rdi, [r14+0xAFECAFE]
  [0x10187] mov esi, 0x14C
  [0x1018C] add rsi, r13
  [0x1018F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10197] add r9, r15
  [0x1019A] call r9
  [0x1019D] jmp 0x00000000000101A5
  [0x101A2] mov rax, r14
  [0x101A5] jmp 0x0000000000010CDD
  [0x101AA] lea r8, [r14+0xAFECAFE]
  [0x101B2] cmp r9, r8
  [0x101B5] jnz 0x00000000000101E8
  [0x101BB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101C3] mov edi, 0x96C
  [0x101C8] mov r8d, [r15+r13*1+0x6C]
  [0x101CD] add rdi, r8
  [0x101D0] mov edx, 0x48
  [0x101D5] mov rsi, rcx
  [0x101D8] add r9, r15
  [0x101DB] call r9
  [0x101DE] lea rax, [r14+0x08]
  [0x101E3] jmp 0x0000000000010CDD
  [0x101E8] lea r8, [r14+0xAFECAFE]
  [0x101F0] cmp r9, r8
  [0x101F3] jnz 0x00000000000102BE
  [0x101F9] mov r9d, [r15+r13*1+0x48]
  [0x101FE] mov r9d, [r15+r9*1]
  [0x10202] lea r8, [r14+0xAFECAFE]
  [0x1020A] mov rdx, r14
  [0x1020D] cmp r9, r8
  [0x10210] jnz 0x000000000001021B
  [0x10216] lea rdx, [r14+0x08]
  [0x1021B] mov r9, rdx
  [0x1021E] mov r8, r14
  [0x10221] cmp r9, r8
  [0x10224] jnz 0x0000000000010280
  [0x1022A] mov r9d, [r15+r13*1+0x48]
  [0x1022F] mov r9d, [r15+r9*1]
  [0x10233] lea r8, [r14+0xAFECAFE]
  [0x1023B] mov rdx, r14
  [0x1023E] cmp r9, r8
  [0x10241] jnz 0x000000000001024C
  [0x10247] lea rdx, [r14+0x08]
  [0x1024C] mov r9, rdx
  [0x1024F] mov r8, r14
  [0x10252] cmp r9, r8
  [0x10255] jnz 0x0000000000010280
  [0x1025B] mov r9d, [r15+r13*1+0x48]
  [0x10260] mov r9d, [r15+r9*1]
  [0x10264] lea r8, [r14+0xAFECAFE]
  [0x1026C] mov rdx, r14
  [0x1026F] cmp r9, r8
  [0x10272] jnz 0x000000000001027D
  [0x10278] lea rdx, [r14+0x08]
  [0x1027D] mov r9, rdx
  [0x10280] mov r8, r14
  [0x10283] cmp r9, r8
  [0x10286] jz 0x00000000000102B6
  [0x1028C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10294] mov [r15+r13*1+0x48], r9d
  [0x10299] mov rdi, [r15+rcx*1+0x10]
  [0x1029E] mov rsi, [r15+rcx*1+0x18]
  [0x102A3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102AB] add r9, r15
  [0x102AE] call r9
  [0x102B1] jmp 0x00000000000102B9
  [0x102B6] mov rax, r14
  [0x102B9] jmp 0x0000000000010CDD
  [0x102BE] lea r8, [r14+0xAFECAFE]
  [0x102C6] cmp r9, r8
  [0x102C9] jnz 0x0000000000010453
  [0x102CF] mov r9d, [r15+r13*1+0x6C]
  [0x102D4] mov r9d, [r15+r9*1+0x290]
  [0x102DC] mov r9d, [r15+r9*1+0x90]
  [0x102E4] mov r8d, 0x800
  [0x102EA] and r9, r8
  [0x102ED] xor r8, r8
  [0x102F0] mov rcx, r14
  [0x102F3] cmp r9, r8
  [0x102F6] jz 0x0000000000010301
  [0x102FC] lea rcx, [r14+0x08]
  [0x10301] mov r9, rcx
  [0x10304] mov r8, r14
  [0x10307] cmp r9, r8
  [0x1030A] jz 0x000000000001033D
  [0x10310] mov r9d, [r15+r13*1+0x6C]
  [0x10315] mov r9, [r15+r9*1+0x10C]
  [0x1031D] mov r8d, 0x01
  [0x10323] and r9, r8
  [0x10326] xor r8, r8
  [0x10329] mov rcx, r14
  [0x1032C] cmp r9, r8
  [0x1032F] jnz 0x000000000001033A
  [0x10335] lea rcx, [r14+0x08]
  [0x1033A] mov r9, rcx
  [0x1033D] mov r8, r14
  [0x10340] cmp r9, r8
  [0x10343] jnz 0x000000000001041F
  [0x10349] mov r9d, [r15+r13*1+0x98]
  [0x10351] mov r9d, [r15+r9*1]
  [0x10355] mov r8d, 0x200
  [0x1035B] and r9, r8
  [0x1035E] xor r8, r8
  [0x10361] mov rcx, r14
  [0x10364] cmp r9, r8
  [0x10367] jz 0x0000000000010372
  [0x1036D] lea rcx, [r14+0x08]
  [0x10372] mov r9, rcx
  [0x10375] mov r8, r14
  [0x10378] cmp r9, r8
  [0x1037B] jnz 0x000000000001041F
  [0x10381] mov r9d, [r15+r13*1+0xA0]
  [0x10389] mov r8d, 0x830E
  [0x1038F] and r9, r8
  [0x10392] xor r8, r8
  [0x10395] mov rcx, r14
  [0x10398] cmp r9, r8
  [0x1039B] jz 0x00000000000103A6
  [0x103A1] lea rcx, [r14+0x08]
  [0x103A6] mov r9, rcx
  [0x103A9] mov r8, r14
  [0x103AC] cmp r9, r8
  [0x103AF] jnz 0x000000000001041F
  [0x103B5] mov r9d, [r15+r13*1+0x6C]
  [0x103BA] mov r9d, [r15+r9*1+0x9C]
  [0x103C2] mov r9d, [r15+r9*1+0x24]
  [0x103C7] mov r8d, 0x7380
  [0x103CD] and r9, r8
  [0x103D0] xor r8, r8
  [0x103D3] mov rcx, r14
  [0x103D6] cmp r9, r8
  [0x103D9] jz 0x00000000000103E4
  [0x103DF] lea rcx, [r14+0x08]
  [0x103E4] mov r9, rcx
  [0x103E7] mov r8, r14
  [0x103EA] cmp r9, r8
  [0x103ED] jnz 0x000000000001041F
  [0x103F3] mov r9, [r15+r13*1+0x234]
  [0x103FB] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10403] mov r8, [r15+r8*1+0x30C]
  [0x1040B] mov rcx, r14
  [0x1040E] cmp r9, r8
  [0x10411] jl 0x000000000001041C
  [0x10417] lea rcx, [r14+0x08]
  [0x1041C] mov r9, rcx
  [0x1041F] mov r8, r14
  [0x10422] cmp r9, r8
  [0x10425] jnz 0x000000000001044B
  [0x1042B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10433] mov [r15+r13*1+0x48], r9d
  [0x10438] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10440] add r9, r15
  [0x10443] call r9
  [0x10446] jmp 0x000000000001044E
  [0x1044B] mov rax, r14
  [0x1044E] jmp 0x0000000000010CDD
  [0x10453] lea r8, [r14+0xAFECAFE]
  [0x1045B] cmp r9, r8
  [0x1045E] jnz 0x0000000000010912
  [0x10464] mov r9, [r15+rcx*1+0x10]
  [0x10469] lea r8, [r14+0xAFECAFE]
  [0x10471] cmp r9, r8
  [0x10474] jnz 0x000000000001049A
  [0x1047A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10482] mov [r15+r13*1+0x48], r9d
  [0x10487] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1048F] add r9, r15
  [0x10492] call r9
  [0x10495] jmp 0x000000000001090D
  [0x1049A] lea r8, [r14+0xAFECAFE]
  [0x104A2] cmp r9, r8
  [0x104A5] jnz 0x00000000000104CB
  [0x104AB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104B3] mov [r15+r13*1+0x48], r9d
  [0x104B8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104C0] add r9, r15
  [0x104C3] call r9
  [0x104C6] jmp 0x000000000001090D
  [0x104CB] lea r8, [r14+0xAFECAFE]
  [0x104D3] cmp r9, r8
  [0x104D6] jnz 0x00000000000104FC
  [0x104DC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104E4] mov [r15+r13*1+0x48], r9d
  [0x104E9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104F1] add r9, r15
  [0x104F4] call r9
  [0x104F7] jmp 0x000000000001090D
  [0x104FC] lea r8, [r14+0xAFECAFE]
  [0x10504] cmp r9, r8
  [0x10507] jnz 0x0000000000010530
  [0x1050D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10515] mov [r15+r13*1+0x48], r9d
  [0x1051A] mov rdi, r14
  [0x1051D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10525] add r9, r15
  [0x10528] call r9
  [0x1052B] jmp 0x000000000001090D
  [0x10530] lea r8, [r14+0xAFECAFE]
  [0x10538] cmp r9, r8
  [0x1053B] jnz 0x000000000001059D
  [0x10541] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10549] mov [r15+r13*1+0x48], r9d
  [0x1054E] mov r9, [r15+rcx*1+0x18]
  [0x10553] mov r8, r14
  [0x10556] cmp r9, r8
  [0x10559] jz 0x0000000000010569
  [0x1055F] mov r9d, [r15+r9*1+0x14]
  [0x10564] jmp 0x000000000001056C
  [0x10569] mov r9, r14
  [0x1056C] mov r8d, [r15+r9*1]
  [0x10570] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x10575] xor rdi, rdi
  [0x10578] shl r9, 0x20
  [0x1057C] shr r9, 0x20
  [0x10580] or rdi, r9
  [0x10583] shl r8, 0x20
  [0x10587] or rdi, r8
  [0x1058A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10592] add r9, r15
  [0x10595] call r9
  [0x10598] jmp 0x000000000001090D
  [0x1059D] lea r8, [r14+0xAFECAFE]
  [0x105A5] cmp r9, r8
  [0x105A8] jnz 0x000000000001060A
  [0x105AE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105B6] mov [r15+r13*1+0x48], r9d
  [0x105BB] mov r9, [r15+rcx*1+0x18]
  [0x105C0] mov r8, r14
  [0x105C3] cmp r9, r8
  [0x105C6] jz 0x00000000000105D6
  [0x105CC] mov r9d, [r15+r9*1+0x14]
  [0x105D1] jmp 0x00000000000105D9
  [0x105D6] mov r9, r14
  [0x105D9] mov r8d, [r15+r9*1]
  [0x105DD] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x105E2] xor rdi, rdi
  [0x105E5] shl r9, 0x20
  [0x105E9] shr r9, 0x20
  [0x105ED] or rdi, r9
  [0x105F0] shl r8, 0x20
  [0x105F4] or rdi, r8
  [0x105F7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105FF] add r9, r15
  [0x10602] call r9
  [0x10605] jmp 0x000000000001090D
  [0x1060A] lea r8, [r14+0xAFECAFE]
  [0x10612] cmp r9, r8
  [0x10615] jnz 0x0000000000010677
  [0x1061B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10623] mov [r15+r13*1+0x48], r9d
  [0x10628] mov r9, [r15+rcx*1+0x18]
  [0x1062D] mov r8, r14
  [0x10630] cmp r9, r8
  [0x10633] jz 0x0000000000010643
  [0x10639] mov r9d, [r15+r9*1+0x14]
  [0x1063E] jmp 0x0000000000010646
  [0x10643] mov r9, r14
  [0x10646] mov r8d, [r15+r9*1]
  [0x1064A] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x1064F] xor rdi, rdi
  [0x10652] shl r9, 0x20
  [0x10656] shr r9, 0x20
  [0x1065A] or rdi, r9
  [0x1065D] shl r8, 0x20
  [0x10661] or rdi, r8
  [0x10664] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1066C] add r9, r15
  [0x1066F] call r9
  [0x10672] jmp 0x000000000001090D
  [0x10677] lea r8, [r14+0xAFECAFE]
  [0x1067F] cmp r9, r8
  [0x10682] jnz 0x000000000001075D
  [0x10688] mov r9d, [r15+r13*1+0x6C]
  [0x1068D] mov r9, [r15+r9*1+0x10C]
  [0x10695] mov r8d, 0x01
  [0x1069B] and r9, r8
  [0x1069E] xor r8, r8
  [0x106A1] mov rdx, r14
  [0x106A4] cmp r9, r8
  [0x106A7] jz 0x00000000000106B2
  [0x106AD] lea rdx, [r14+0x08]
  [0x106B2] mov r9, rdx
  [0x106B5] mov r8, r14
  [0x106B8] cmp r9, r8
  [0x106BB] jz 0x00000000000106ED
  [0x106C1] mov r9d, [r15+r13*1+0x98]
  [0x106C9] mov r9d, [r15+r9*1]
  [0x106CD] mov r8d, 0x200
  [0x106D3] and r9, r8
  [0x106D6] xor r8, r8
  [0x106D9] mov rdx, r14
  [0x106DC] cmp r9, r8
  [0x106DF] jnz 0x00000000000106EA
  [0x106E5] lea rdx, [r14+0x08]
  [0x106EA] mov r9, rdx
  [0x106ED] mov r8, r14
  [0x106F0] cmp r9, r8
  [0x106F3] jz 0x0000000000010755
  [0x106F9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10701] mov [r15+r13*1+0x48], r9d
  [0x10706] mov r9, [r15+rcx*1+0x18]
  [0x1070B] mov r8, r14
  [0x1070E] cmp r9, r8
  [0x10711] jz 0x0000000000010721
  [0x10717] mov r9d, [r15+r9*1+0x14]
  [0x1071C] jmp 0x0000000000010724
  [0x10721] mov r9, r14
  [0x10724] mov r8d, [r15+r9*1]
  [0x10728] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x1072D] xor rdi, rdi
  [0x10730] shl r9, 0x20
  [0x10734] shr r9, 0x20
  [0x10738] or rdi, r9
  [0x1073B] shl r8, 0x20
  [0x1073F] or rdi, r8
  [0x10742] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1074A] add r9, r15
  [0x1074D] call r9
  [0x10750] jmp 0x0000000000010758
  [0x10755] mov rax, r14
  [0x10758] jmp 0x000000000001090D
  [0x1075D] lea r8, [r14+0xAFECAFE]
  [0x10765] cmp r9, r8
  [0x10768] jnz 0x00000000000107F4
  [0x1076E] mov r9d, [r15+r13*1+0x6C]
  [0x10773] mov r9, [r15+r9*1+0x10C]
  [0x1077B] mov r8d, 0x01
  [0x10781] and r9, r8
  [0x10784] xor r8, r8
  [0x10787] cmp r9, r8
  [0x1078A] jz 0x00000000000107EC
  [0x10790] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10798] mov [r15+r13*1+0x48], r9d
  [0x1079D] mov r9, [r15+rcx*1+0x18]
  [0x107A2] mov r8, r14
  [0x107A5] cmp r9, r8
  [0x107A8] jz 0x00000000000107B8
  [0x107AE] mov r9d, [r15+r9*1+0x14]
  [0x107B3] jmp 0x00000000000107BB
  [0x107B8] mov r9, r14
  [0x107BB] mov r8d, [r15+r9*1]
  [0x107BF] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x107C4] xor rdi, rdi
  [0x107C7] shl r9, 0x20
  [0x107CB] shr r9, 0x20
  [0x107CF] or rdi, r9
  [0x107D2] shl r8, 0x20
  [0x107D6] or rdi, r8
  [0x107D9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x107E1] add r9, r15
  [0x107E4] call r9
  [0x107E7] jmp 0x00000000000107EF
  [0x107EC] mov rax, r14
  [0x107EF] jmp 0x000000000001090D
  [0x107F4] lea r8, [r14+0xAFECAFE]
  [0x107FC] cmp r9, r8
  [0x107FF] jnz 0x0000000000010861
  [0x10805] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1080D] mov [r15+r13*1+0x48], r9d
  [0x10812] mov r9, [r15+rcx*1+0x18]
  [0x10817] mov r8, r14
  [0x1081A] cmp r9, r8
  [0x1081D] jz 0x000000000001082D
  [0x10823] mov r9d, [r15+r9*1+0x14]
  [0x10828] jmp 0x0000000000010830
  [0x1082D] mov r9, r14
  [0x10830] mov r8d, [r15+r9*1]
  [0x10834] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x10839] xor rdi, rdi
  [0x1083C] shl r9, 0x20
  [0x10840] shr r9, 0x20
  [0x10844] or rdi, r9
  [0x10847] shl r8, 0x20
  [0x1084B] or rdi, r8
  [0x1084E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10856] add r9, r15
  [0x10859] call r9
  [0x1085C] jmp 0x000000000001090D
  [0x10861] lea r8, [r14+0xAFECAFE]
  [0x10869] cmp r9, r8
  [0x1086C] jnz 0x000000000001090A
  [0x10872] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1087A] mov [r15+r13*1+0x48], r9d
  [0x1087F] mov r9, [r15+rcx*1+0x18]
  [0x10884] mov r8, r14
  [0x10887] cmp r9, r8
  [0x1088A] jz 0x000000000001089A
  [0x10890] mov r9d, [r15+r9*1+0x14]
  [0x10895] jmp 0x000000000001089D
  [0x1089A] mov r9, r14
  [0x1089D] mov r8d, [r15+r9*1]
  [0x108A1] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x108A6] xor rdi, rdi
  [0x108A9] shl r9, 0x20
  [0x108AD] shr r9, 0x20
  [0x108B1] or rdi, r9
  [0x108B4] shl r8, 0x20
  [0x108B8] or rdi, r8
  [0x108BB] mov r9, [r15+rcx*1+0x20]
  [0x108C0] mov r8, r14
  [0x108C3] cmp r9, r8
  [0x108C6] jz 0x00000000000108D6
  [0x108CC] mov r9d, [r15+r9*1+0x14]
  [0x108D1] jmp 0x00000000000108D9
  [0x108D6] mov r9, r14
  [0x108D9] mov r8d, [r15+r9*1]
  [0x108DD] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x108E2] xor rsi, rsi
  [0x108E5] shl r9, 0x20
  [0x108E9] shr r9, 0x20
  [0x108ED] or rsi, r9
  [0x108F0] shl r8, 0x20
  [0x108F4] or rsi, r8
  [0x108F7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x108FF] add r9, r15
  [0x10902] call r9
  [0x10905] jmp 0x000000000001090D
  [0x1090A] mov rax, r14
  [0x1090D] jmp 0x0000000000010CDD
  [0x10912] lea r8, [r14+0xAFECAFE]
  [0x1091A] cmp r9, r8
  [0x1091D] jnz 0x0000000000010948
  [0x10923] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1092B] mov [r15+r13*1+0x48], r9d
  [0x10930] mov rdi, [r15+rcx*1+0x10]
  [0x10935] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1093D] add r9, r15
  [0x10940] call r9
  [0x10943] jmp 0x0000000000010CDD
  [0x10948] lea r8, [r14+0xAFECAFE]
  [0x10950] cmp r9, r8
  [0x10953] jnz 0x00000000000109B5
  [0x10959] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10961] mov [r15+r13*1+0x48], r9d
  [0x10966] mov r9, [r15+rcx*1+0x10]
  [0x1096B] mov r8, r14
  [0x1096E] cmp r9, r8
  [0x10971] jz 0x0000000000010981
  [0x10977] mov r9d, [r15+r9*1+0x14]
  [0x1097C] jmp 0x0000000000010984
  [0x10981] mov r9, r14
  [0x10984] mov r8d, [r15+r9*1]
  [0x10988] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x1098D] xor rdi, rdi
  [0x10990] shl r9, 0x20
  [0x10994] shr r9, 0x20
  [0x10998] or rdi, r9
  [0x1099B] shl r8, 0x20
  [0x1099F] or rdi, r8
  [0x109A2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x109AA] add r9, r15
  [0x109AD] call r9
  [0x109B0] jmp 0x0000000000010CDD
  [0x109B5] lea r8, [r14+0xAFECAFE]
  [0x109BD] cmp r9, r8
  [0x109C0] jnz 0x00000000000109E6
  [0x109C6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x109CE] mov [r15+r13*1+0x48], r9d
  [0x109D3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x109DB] add r9, r15
  [0x109DE] call r9
  [0x109E1] jmp 0x0000000000010CDD
  [0x109E6] lea r8, [r14+0xAFECAFE]
  [0x109EE] cmp r9, r8
  [0x109F1] jnz 0x0000000000010A82
  [0x109F7] mov r9d, [r15+r13*1+0x6C]
  [0x109FC] mov r9d, [r15+r9*1+0x9C]
  [0x10A04] mov r9d, [r15+r9*1+0x24]
  [0x10A09] mov r8d, 0x100
  [0x10A0F] and r9, r8
  [0x10A12] xor r8, r8
  [0x10A15] cmp r9, r8
  [0x10A18] jnz 0x0000000000010A7A
  [0x10A1E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10A26] mov [r15+r13*1+0x48], r9d
  [0x10A2B] mov r9, [r15+rcx*1+0x10]
  [0x10A30] mov r8, r14
  [0x10A33] cmp r9, r8
  [0x10A36] jz 0x0000000000010A46
  [0x10A3C] mov r9d, [r15+r9*1+0x14]
  [0x10A41] jmp 0x0000000000010A49
  [0x10A46] mov r9, r14
  [0x10A49] mov r8d, [r15+r9*1]
  [0x10A4D] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x10A52] xor rdi, rdi
  [0x10A55] shl r9, 0x20
  [0x10A59] shr r9, 0x20
  [0x10A5D] or rdi, r9
  [0x10A60] shl r8, 0x20
  [0x10A64] or rdi, r8
  [0x10A67] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10A6F] add r9, r15
  [0x10A72] call r9
  [0x10A75] jmp 0x0000000000010A7D
  [0x10A7A] mov rax, r14
  [0x10A7D] jmp 0x0000000000010CDD
  [0x10A82] lea r8, [r14+0xAFECAFE]
  [0x10A8A] cmp r9, r8
  [0x10A8D] jnz 0x0000000000010B9A
  [0x10A93] mov r9d, [r15+r13*1+0x6C]
  [0x10A98] mov r9d, [r15+r9*1+0x290]
  [0x10AA0] mov r9d, [r15+r9*1+0x8C]
  [0x10AA8] lea r8, [r14+0xAFECAFE]
  [0x10AB0] mov rcx, r14
  [0x10AB3] cmp r9, r8
  [0x10AB6] jnz 0x0000000000010AC1
  [0x10ABC] lea rcx, [r14+0x08]
  [0x10AC1] mov r9, rcx
  [0x10AC4] mov r8, r14
  [0x10AC7] cmp r9, r8
  [0x10ACA] jnz 0x0000000000010B66
  [0x10AD0] mov r9d, [r15+r13*1+0x6C]
  [0x10AD5] mov r9d, [r15+r9*1+0x290]
  [0x10ADD] mov r9d, [r15+r9*1+0x8C]
  [0x10AE5] lea r8, [r14+0xAFECAFE]
  [0x10AED] mov rcx, r14
  [0x10AF0] cmp r9, r8
  [0x10AF3] jnz 0x0000000000010AFE
  [0x10AF9] lea rcx, [r14+0x08]
  [0x10AFE] mov r9, rcx
  [0x10B01] mov r8, r14
  [0x10B04] cmp r9, r8
  [0x10B07] jnz 0x0000000000010B66
  [0x10B0D] mov r9d, [r15+r13*1+0x48]
  [0x10B12] mov r9d, [r15+r9*1]
  [0x10B16] lea r8, [r14+0xAFECAFE]
  [0x10B1E] mov rcx, r14
  [0x10B21] cmp r9, r8
  [0x10B24] jnz 0x0000000000010B2F
  [0x10B2A] lea rcx, [r14+0x08]
  [0x10B2F] mov r9, rcx
  [0x10B32] mov r8, r14
  [0x10B35] cmp r9, r8
  [0x10B38] jnz 0x0000000000010B66
  [0x10B3E] mov r9d, [r15+r13*1+0xA0]
  [0x10B46] mov r8d, 0x08
  [0x10B4C] and r9, r8
  [0x10B4F] xor r8, r8
  [0x10B52] mov rcx, r14
  [0x10B55] cmp r9, r8
  [0x10B58] jz 0x0000000000010B63
  [0x10B5E] lea rcx, [r14+0x08]
  [0x10B63] mov r9, rcx
  [0x10B66] mov r8, r14
  [0x10B69] cmp r9, r8
  [0x10B6C] jnz 0x0000000000010B92
  [0x10B72] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10B7A] mov [r15+r13*1+0x48], r9d
  [0x10B7F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10B87] add r9, r15
  [0x10B8A] call r9
  [0x10B8D] jmp 0x0000000000010B95
  [0x10B92] mov rax, r14
  [0x10B95] jmp 0x0000000000010CDD
  [0x10B9A] lea r8, [r14+0xAFECAFE]
  [0x10BA2] cmp r9, r8
  [0x10BA5] jnz 0x0000000000010CA3
  [0x10BAB] mov r9d, [r15+r13*1+0x6C]
  [0x10BB0] mov r9d, [r15+r9*1+0x290]
  [0x10BB8] mov r9d, [r15+r9*1+0x8C]
  [0x10BC0] lea r8, [r14+0xAFECAFE]
  [0x10BC8] mov rcx, r14
  [0x10BCB] cmp r9, r8
  [0x10BCE] jz 0x0000000000010BD9
  [0x10BD4] lea rcx, [r14+0x08]
  [0x10BD9] mov r9, rcx
  [0x10BDC] mov r8, r14
  [0x10BDF] cmp r9, r8
  [0x10BE2] jz 0x0000000000010C6F
  [0x10BE8] mov r9d, [r15+r13*1+0x48]
  [0x10BED] mov r9d, [r15+r9*1]
  [0x10BF1] lea r8, [r14+0xAFECAFE]
  [0x10BF9] mov rcx, r14
  [0x10BFC] cmp r9, r8
  [0x10BFF] jnz 0x0000000000010C0A
  [0x10C05] lea rcx, [r14+0x08]
  [0x10C0A] mov r9, rcx
  [0x10C0D] mov r8, r14
  [0x10C10] cmp r9, r8
  [0x10C13] jnz 0x0000000000010C6F
  [0x10C19] mov r9d, [r15+r13*1+0x48]
  [0x10C1E] mov r9d, [r15+r9*1]
  [0x10C22] lea r8, [r14+0xAFECAFE]
  [0x10C2A] mov rcx, r14
  [0x10C2D] cmp r9, r8
  [0x10C30] jnz 0x0000000000010C3B
  [0x10C36] lea rcx, [r14+0x08]
  [0x10C3B] mov r9, rcx
  [0x10C3E] mov r8, r14
  [0x10C41] cmp r9, r8
  [0x10C44] jnz 0x0000000000010C6F
  [0x10C4A] mov r9d, [r15+r13*1+0x48]
  [0x10C4F] mov r9d, [r15+r9*1]
  [0x10C53] lea r8, [r14+0xAFECAFE]
  [0x10C5B] mov rcx, r14
  [0x10C5E] cmp r9, r8
  [0x10C61] jnz 0x0000000000010C6C
  [0x10C67] lea rcx, [r14+0x08]
  [0x10C6C] mov r9, rcx
  [0x10C6F] mov r8, r14
  [0x10C72] cmp r9, r8
  [0x10C75] jz 0x0000000000010C9B
  [0x10C7B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C83] mov [r15+r13*1+0x48], r9d
  [0x10C88] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C90] add r9, r15
  [0x10C93] call r9
  [0x10C96] jmp 0x0000000000010C9E
  [0x10C9B] mov rax, r14
  [0x10C9E] jmp 0x0000000000010CDD
  [0x10CA3] lea r8, [r14+0xAFECAFE]
  [0x10CAB] cmp r9, r8
  [0x10CAE] jnz 0x0000000000010CCC
  [0x10CB4] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10CBC] mov rdi, [r15+rcx*1+0x10]
  [0x10CC1] add r9, r15
  [0x10CC4] call r9
  [0x10CC7] jmp 0x0000000000010CDD
  [0x10CCC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10CD4] mov rdi, rbx
  [0x10CD7] add r9, r15
  [0x10CDA] call r9
  [0x10CDD] pop rbx
  [0x10CDE] ret


[get-intersect-point]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push rbx
  [0x10003] mov rbx, rdi
  [0x10006] mov rbp, rsi
  [0x10009] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10011] mov r9d, [r15+r9*1+0x40]
  [0x10016] mov rdi, rbp
  [0x10019] mov rsi, rdx
  [0x1001C] mov rdx, rcx
  [0x1001F] add r9, r15
  [0x10022] call r9
  [0x10025] mov r9, r14
  [0x10028] cmp rax, r9
  [0x1002B] jz 0x0000000000010048
  [0x10031] vmovaps xmm7, [r15+rax*1+0x30]
  [0x10038] vmovaps [r15+rbx*1], xmm7
  [0x1003E] movq r9, xmm7
  [0x10043] jmp 0x0000000000010064
  [0x10048] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10050] mov r9d, [r15+r9*1+0x3C]
  [0x10055] mov rdi, rbp
  [0x10058] mov rsi, rbx
  [0x1005B] add r9, r15
  [0x1005E] call r9
  [0x10061] mov r9, rax
  [0x10064] mov rax, rbx
  [0x10067] pop rbx
  [0x10068] pop rbp
  [0x10069] pop rbx
  [0x1006A] ret


[target-attacked]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] push rbx
  [0x1000B] push rbp
  [0x1000C] push r10
  [0x1000E] push r11
  [0x10010] push r12
  [0x10012] push rbx
  [0x10013] mov rbx, rdi
  [0x10016] mov r12, rdx
  [0x10019] mov r11, rcx
  [0x1001C] mov rbp, r8
  [0x1001F] mov r9d, [r15+r13*1+0xA0]
  [0x10027] mov r8d, 0x08
  [0x1002D] and r9, r8
  [0x10030] xor r8, r8
  [0x10033] cmp r9, r8
  [0x10036] jnz 0x0000000000010755
  [0x1003C] mov r9d, [r15+r13*1+0xA0]
  [0x10044] mov r8d, 0x70
  [0x1004A] and r9, r8
  [0x1004D] xor r8, r8
  [0x10050] mov rcx, r14
  [0x10053] cmp r9, r8
  [0x10056] jz 0x0000000000010061
  [0x1005C] lea rcx, [r14+0x08]
  [0x10061] mov r9, rcx
  [0x10064] mov r8, r14
  [0x10067] cmp r9, r8
  [0x1006A] jnz 0x000000000001015D
  [0x10070] mov r9d, [r15+rsi*1+0x40]
  [0x10075] mov r8d, 0x20
  [0x1007B] and r9, r8
  [0x1007E] xor r8, r8
  [0x10081] mov rcx, r14
  [0x10084] cmp r9, r8
  [0x10087] jz 0x0000000000010092
  [0x1008D] lea rcx, [r14+0x08]
  [0x10092] mov r9, rcx
  [0x10095] mov r8, r14
  [0x10098] cmp r9, r8
  [0x1009B] jz 0x000000000001015D
  [0x100A1] mov r9d, [r15+rsi*1+0x44]
  [0x100A6] lea r8, [r14+0xAFECAFE]
  [0x100AE] mov rcx, r14
  [0x100B1] cmp r9, r8
  [0x100B4] jnz 0x00000000000100BF
  [0x100BA] lea rcx, [r14+0x08]
  [0x100BF] mov r9, rcx
  [0x100C2] mov r8, r14
  [0x100C5] cmp r9, r8
  [0x100C8] jz 0x000000000001015D
  [0x100CE] mov r9d, [r15+r13*1+0x8C]
  [0x100D6] movsxd r9, dword ptr [r15+r9*1+0x24]
  [0x100DB] mov r8d, 0x02
  [0x100E1] mov rcx, r14
  [0x100E4] cmp r9, r8
  [0x100E7] jnz 0x00000000000100F2
  [0x100ED] lea rcx, [r14+0x08]
  [0x100F2] mov r9, rcx
  [0x100F5] mov r8, r14
  [0x100F8] cmp r9, r8
  [0x100FB] jz 0x0000000000010129
  [0x10101] mov r9d, [r15+r13*1+0x8C]
  [0x10109] movss xmm7, dword ptr [r15+r9*1+0x28]
  [0x10110] movss xmm6, dword ptr [0x0000000000010118]
  [0x10118] mov r9, r14
  [0x1011B] ucomiss xmm7, xmm6
  [0x1011E] jb 0x0000000000010129
  [0x10124] lea r9, [r14+0x08]
  [0x10129] mov r8, r14
  [0x1012C] cmp r9, r8
  [0x1012F] jz 0x000000000001015D
  [0x10135] mov r9d, 0x100002
  [0x1013B] mov r8d, [r15+r13*1+0xA0]
  [0x10143] and r9, r8
  [0x10146] xor r8, r8
  [0x10149] mov rcx, r14
  [0x1014C] cmp r9, r8
  [0x1014F] jz 0x000000000001015A
  [0x10155] lea rcx, [r14+0x08]
  [0x1015A] mov r9, rcx
  [0x1015D] mov r8, r14
  [0x10160] cmp r9, r8
  [0x10163] jz 0x00000000000101B3
  [0x10169] mov r9, rbx
  [0x1016C] lea r8, [r14+0xAFECAFE]
  [0x10174] cmp r9, r8
  [0x10177] jnz 0x0000000000010182
  [0x1017D] jmp 0x00000000000101AB
  [0x10182] lea r8, [r14+0xAFECAFE]
  [0x1018A] cmp r9, r8
  [0x1018D] jnz 0x00000000000101A3
  [0x10193] lea rax, [r14+0xAFECAFE]
  [0x1019B] mov rbx, rax
  [0x1019E] jmp 0x00000000000101AB
  [0x101A3] mov rax, r14
  [0x101A6] jmp 0x0000000000010758
  [0x101AB] mov r9, rax
  [0x101AE] jmp 0x0000000000010219
  [0x101B3] mov r9, rbx
  [0x101B6] lea r8, [r14+0xAFECAFE]
  [0x101BE] mov rcx, r14
  [0x101C1] cmp r9, r8
  [0x101C4] jnz 0x00000000000101CF
  [0x101CA] lea rcx, [r14+0x08]
  [0x101CF] mov r8, rcx
  [0x101D2] mov rcx, r14
  [0x101D5] cmp r8, rcx
  [0x101D8] jnz 0x00000000000101FA
  [0x101DE] lea r8, [r14+0xAFECAFE]
  [0x101E6] mov rcx, r14
  [0x101E9] cmp r9, r8
  [0x101EC] jnz 0x00000000000101F7
  [0x101F2] lea rcx, [r14+0x08]
  [0x101F7] mov r8, rcx
  [0x101FA] mov r9, r14
  [0x101FD] cmp r8, r9
  [0x10200] jz 0x0000000000010216
  [0x10206] lea r9, [r14+0xAFECAFE]
  [0x1020E] mov rbx, r9
  [0x10211] jmp 0x0000000000010219
  [0x10216] mov r9, r14
  [0x10219] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10221] mov edi, 0x14C
  [0x10226] add rdi, r13
  [0x10229] mov edx, 0x68
  [0x1022E] add r9, r15
  [0x10231] call r9
  [0x10234] mov r9, r14
  [0x10237] cmp r11, r9
  [0x1023A] jz 0x00000000000102B5
  [0x10240] mov esi, [r15+r13*1+0x6C]
  [0x10245] mov rdx, 0xFFFFFFFFFFFFFFFF
  [0x1024C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10254] mov r9d, [r15+r9*1+0x40]
  [0x10259] mov rdi, r11
  [0x1025C] add r9, r15
  [0x1025F] call r9
  [0x10262] mov r9, r14
  [0x10265] cmp rax, r9
  [0x10268] jz 0x00000000000102AD
  [0x1026E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10276] mov edi, 0x16C
  [0x1027B] add rdi, r13
  [0x1027E] mov edx, [r15+r13*1+0x6C]
  [0x10283] mov rsi, rax
  [0x10286] mov rcx, r11
  [0x10289] add r9, r15
  [0x1028C] call r9
  [0x1028F] mov r9d, [r15+r13*1+0x18C]
  [0x10297] mov r8d, 0x04
  [0x1029D] or r9, r8
  [0x102A0] mov [r15+r13*1+0x18C], r9d
  [0x102A8] jmp 0x00000000000102B0
  [0x102AD] mov r9, r14
  [0x102B0] jmp 0x00000000000102B8
  [0x102B5] mov r9, r14
  [0x102B8] mov r9d, [r15+r13*1+0x34]
  [0x102BD] mov [r15+r13*1+0x1B0], r9d
  [0x102C5] mov r9d, [r15+r13*1+0x18C]
  [0x102CD] mov r8d, 0x2000
  [0x102D3] or r9, r8
  [0x102D6] mov [r15+r13*1+0x18C], r9d
  [0x102DE] mov r9d, [r15+r13*1+0x18C]
  [0x102E6] mov r8d, 0x08
  [0x102EC] and r9, r8
  [0x102EF] xor r8, r8
  [0x102F2] cmp r9, r8
  [0x102F5] jnz 0x0000000000010358
  [0x102FB] mov r9, r14
  [0x102FE] cmp r12, r9
  [0x10301] jz 0x0000000000010311
  [0x10307] mov r9d, [r12+r15*1+0x14]
  [0x1030C] jmp 0x0000000000010314
  [0x10311] mov r9, r14
  [0x10314] mov r8d, [r15+r9*1]
  [0x10318] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x1031D] xor rcx, rcx
  [0x10320] shl r9, 0x20
  [0x10324] shr r9, 0x20
  [0x10328] or rcx, r9
  [0x1032B] shl r8, 0x20
  [0x1032F] or rcx, r8
  [0x10332] mov [r15+r13*1+0x17C], rcx
  [0x1033A] mov r9d, [r15+r13*1+0x18C]
  [0x10342] mov r8d, 0x08
  [0x10348] or r9, r8
  [0x1034B] mov [r15+r13*1+0x18C], r9d
  [0x10353] jmp 0x000000000001035B
  [0x10358] mov r9, r14
  [0x1035B] mov r9d, [r15+r13*1+0x18C]
  [0x10363] mov r8d, 0x20
  [0x10369] and r9, r8
  [0x1036C] xor r8, r8
  [0x1036F] mov rcx, r14
  [0x10372] cmp r9, r8
  [0x10375] jz 0x0000000000010380
  [0x1037B] lea rcx, [r14+0x08]
  [0x10380] mov r9, rcx
  [0x10383] mov r8, r14
  [0x10386] cmp r9, r8
  [0x10389] jz 0x0000000000010432
  [0x1038F] mov r9d, [r15+r13*1+0x190]
  [0x10397] lea r8, [r14+0xAFECAFE]
  [0x1039F] mov rcx, r14
  [0x103A2] cmp r9, r8
  [0x103A5] jnz 0x00000000000103B0
  [0x103AB] lea rcx, [r14+0x08]
  [0x103B0] mov r9, rcx
  [0x103B3] mov r8, r14
  [0x103B6] cmp r9, r8
  [0x103B9] jz 0x0000000000010432
  [0x103BF] mov r9d, [r15+r13*1+0xB4]
  [0x103C7] mov r9d, [r15+r9*1]
  [0x103CB] lea r8, [r14+0xAFECAFE]
  [0x103D3] mov rcx, r14
  [0x103D6] cmp r9, r8
  [0x103D9] jnz 0x00000000000103E4
  [0x103DF] lea rcx, [r14+0x08]
  [0x103E4] mov r9, rcx
  [0x103E7] mov r8, r14
  [0x103EA] cmp r9, r8
  [0x103ED] jz 0x000000000001041B
  [0x103F3] movss xmm7, dword ptr [0x00000000000103FB]
  [0x103FB] mov r9d, [r15+r13*1+0x8C]
  [0x10403] movss xmm6, dword ptr [r15+r9*1+0x3C]
  [0x1040A] mov r9, r14
  [0x1040D] ucomiss xmm7, xmm6
  [0x10410] jb 0x000000000001041B
  [0x10416] lea r9, [r14+0x08]
  [0x1041B] mov r8, r14
  [0x1041E] mov rcx, r14
  [0x10421] cmp r9, r8
  [0x10424] jnz 0x000000000001042F
  [0x1042A] lea rcx, [r14+0x08]
  [0x1042F] mov r9, rcx
  [0x10432] mov r8, r14
  [0x10435] cmp r9, r8
  [0x10438] jz 0x0000000000010668
  [0x1043E] mov edi, [r15+r13*1+0x8C]
  [0x10446] mov esi, 0x04
  [0x1044B] movss xmm7, dword ptr [0x0000000000010453]
  [0x10453] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1045B] movss xmm6, dword ptr [r15+r9*1+0x28]
  [0x10462] subss xmm7, xmm6
  [0x10466] mov rcx, r14
  [0x10469] mov r9d, [r15+rdi*1-0x04]
  [0x1046E] mov r9d, [r15+r9*1+0x3C]
  [0x10473] movd edx, xmm7
  [0x10477] movsxd rdx, edx
  [0x1047A] add r9, r15
  [0x1047D] call r9
  [0x10480] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10488] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10490] mov edx, 0x4000
  [0x10495] mov r9d, [r15+rdi*1-0x04]
  [0x1049A] mov r9d, [r15+r9*1+0x48]
  [0x1049F] add r9, r15
  [0x104A2] call r9
  [0x104A5] mov rbx, rax
  [0x104A8] mov r9, r14
  [0x104AB] cmp rbx, r9
  [0x104AE] jz 0x000000000001055F
  [0x104B4] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104BC] mov r9d, [r15+r9*1+0x34]
  [0x104C1] lea rdx, [r14+0xAFECAFE]
  [0x104C9] mov ecx, 0x70004000
  [0x104CE] mov rdi, rbx
  [0x104D1] mov rsi, r13
  [0x104D4] add r9, r15
  [0x104D7] call r9
  [0x104DA] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104E2] mov rax, r9
  [0x104E5] mov esi, [r15+r14*1+0xBADBEEF]
  [0x104ED] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104F5] mov edx, [r15+r9*1+0x10]
  [0x104FA] mov rcx, 0xFFFFFFFFFFFFFFFF
  [0x10501] mov r8, r14
  [0x10504] mov r9, r14
  [0x10507] mov r10, r14
  [0x1050A] mov edi, [r15+r13*1+0x18C]
  [0x10512] mov ebp, 0x04
  [0x10517] and rdi, rbp
  [0x1051A] xor rbp, rbp
  [0x1051D] cmp rdi, rbp
  [0x10520] jz 0x0000000000010534
  [0x10526] mov r11d, 0x16C
  [0x1052C] add r11, r13
  [0x1052F] jmp 0x000000000001054A
  [0x10534] mov r11d, 0x0C
  [0x1053A] mov edi, [r15+r13*1+0x6C]
  [0x1053F] mov edi, [r15+rdi*1+0x9C]
  [0x10547] add r11, rdi
  [0x1054A] mov rdi, rbx
  [0x1054D] mov rbp, rax
  [0x10550] add rbp, r15
  [0x10553] call rbp
  [0x10555] mov r9d, [r15+rbx*1+0x14]
  [0x1055A] jmp 0x0000000000010562
  [0x1055F] mov r9, r14
  [0x10562] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1056A] mov r8d, [r15+r13*1+0x18C]
  [0x10572] mov ecx, 0x10
  [0x10577] and r8, rcx
  [0x1057A] xor rcx, rcx
  [0x1057D] cmp r8, rcx
  [0x10580] jz 0x0000000000010593
  [0x10586] mov rdi, [r15+r13*1+0x184]
  [0x1058E] jmp 0x00000000000105A3
  [0x10593] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1059B] mov rdi, [r15+r8*1+0xC4]
  [0x105A3] mov rsi, r13
  [0x105A6] add r9, r15
  [0x105A9] call r9
  [0x105AC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105B4] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x105BC] mov edi, [r15+r8*1+0x04]
  [0x105C1] xor rsi, rsi
  [0x105C4] mov edx, 0xFF
  [0x105C9] mov ecx, 0x96
  [0x105CE] add r9, r15
  [0x105D1] call r9
  [0x105D4] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x105DC] mov r9d, 0x666F6F
  [0x105E2] movq xmm7, r9
  [0x105E7] xor r9, r9
  [0x105EA] movq xmm8, r9
  [0x105EF] vpunpcklqdq xmm8, xmm7, xmm8
  [0x105F4] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105FC] add r9, r15
  [0x105FF] call r9
  [0x10602] movss xmm7, dword ptr [0x000000000001060A]
  [0x1060A] movss xmm6, dword ptr [0x0000000000010612]
  [0x10612] divss xmm7, xmm6
  [0x10616] movss xmm6, dword ptr [0x000000000001061E]
  [0x1061E] mulss xmm7, xmm6
  [0x10622] cvttss2si esi, xmm7
  [0x10626] movsxd rsi, esi
  [0x10629] movss xmm7, dword ptr [0x0000000000010631]
  [0x10631] xor r9, r9
  [0x10634] cvtsi2ss xmm6, r9d
  [0x10639] mulss xmm7, xmm6
  [0x1063D] cvttss2si edx, xmm7
  [0x10641] movsxd rdx, edx
  [0x10644] xor rcx, rcx
  [0x10647] mov r8d, 0x01
  [0x1064D] lea r9, [r14+0x08]
  [0x10652] vmovaps xmm1, xmm8
  [0x10656] mov rdi, rax
  [0x10659] add rbx, r15
  [0x1065C] call rbx
  [0x1065E] lea rax, [r14+0x08]
  [0x10663] jmp 0x0000000000010750
  [0x10668] mov r9d, [r15+r13*1+0xA0]
  [0x10670] mov r8d, 0x08
  [0x10676] or r9, r8
  [0x10679] mov [r15+r13*1+0xA0], r9d
  [0x10681] mov r9d, [r15+r13*1+0xB4]
  [0x10689] mov r9d, [r15+r9*1]
  [0x1068D] lea r8, [r14+0xAFECAFE]
  [0x10695] mov rcx, r14
  [0x10698] cmp r9, r8
  [0x1069B] jnz 0x00000000000106A6
  [0x106A1] lea rcx, [r14+0x08]
  [0x106A6] mov r9, rcx
  [0x106A9] mov r8, r14
  [0x106AC] cmp r9, r8
  [0x106AF] jz 0x0000000000010705
  [0x106B5] movss xmm7, dword ptr [0x00000000000106BD]
  [0x106BD] mov r9d, [r15+r13*1+0x8C]
  [0x106C5] movss xmm6, dword ptr [r15+r9*1+0x3C]
  [0x106CC] mov r9, r14
  [0x106CF] ucomiss xmm7, xmm6
  [0x106D2] jb 0x00000000000106DD
  [0x106D8] lea r9, [r14+0x08]
  [0x106DD] mov r8, r14
  [0x106E0] cmp r9, r8
  [0x106E3] jz 0x0000000000010705
  [0x106E9] lea r9, [r14+0xAFECAFE]
  [0x106F1] mov r8, r14
  [0x106F4] cmp rbx, r9
  [0x106F7] jnz 0x0000000000010702
  [0x106FD] lea r8, [r14+0x08]
  [0x10702] mov r9, r8
  [0x10705] mov r8, r14
  [0x10708] cmp r9, r8
  [0x1070B] jz 0x000000000001072F
  [0x10711] mov r9d, [r15+r13*1+0xA0]
  [0x10719] mov r8d, 0x8000
  [0x1071F] or r9, r8
  [0x10722] mov [r15+r13*1+0xA0], r9d
  [0x1072A] jmp 0x0000000000010732
  [0x1072F] mov r9, r14
  [0x10732] mov [r15+r13*1+0x48], ebp
  [0x10737] mov esi, 0x14C
  [0x1073C] add rsi, r13
  [0x1073F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10747] mov rdi, rbx
  [0x1074A] add r9, r15
  [0x1074D] call r9
  [0x10750] jmp 0x0000000000010758
  [0x10755] mov rax, r14
  [0x10758] pop rbx
  [0x10759] pop r12
  [0x1075B] pop r11
  [0x1075D] pop r10
  [0x1075F] pop rbp
  [0x10760] pop rbx
  [0x10761] movdqa xmm8, [rsp]
  [0x10767] add rsp, 0x18
  [0x1076B] ret


[target-shoved]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] mov rbp, rcx
  [0x10007] lea rbx, [0x000000000001000E]
  [0x1000E] sub rbx, r15
  [0x10011] mov r9, r14
  [0x10014] cmp rdx, r9
  [0x10017] jz 0x0000000000010027
  [0x1001D] mov r9d, [r15+rdx*1+0x14]
  [0x10022] jmp 0x000000000001002A
  [0x10027] mov r9, r14
  [0x1002A] mov r8d, [r15+r9*1]
  [0x1002E] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x10033] xor rcx, rcx
  [0x10036] shl r9, 0x20
  [0x1003A] shr r9, 0x20
  [0x1003E] or rcx, r9
  [0x10041] shl r8, 0x20
  [0x10045] or rcx, r8
  [0x10048] mov [r15+rbx*1+0x30], rcx
  [0x1004D] mov [r15+rbx*1+0x48], edi
  [0x10052] mov [r15+rbx*1+0x4C], esi
  [0x10057] mov r9d, [r15+r13*1+0x6C]
  [0x1005C] mov r9, [r15+r9*1+0x10C]
  [0x10064] mov r8d, [r15+r13*1+0x6C]
  [0x10069] mov r8, [r15+r8*1+0x114]
  [0x10071] or r9, r8
  [0x10074] mov r8d, 0x01
  [0x1007A] and r9, r8
  [0x1007D] xor r8, r8
  [0x10080] cmp r9, r8
  [0x10083] jnz 0x0000000000010096
  [0x10089] lea r9, [r14+0xAFECAFE]
  [0x10091] jmp 0x000000000001009E
  [0x10096] lea r9, [r14+0xAFECAFE]
  [0x1009E] mov [r15+rbx*1+0x5C], r9d
  [0x100A3] mov r9d, 0x8C8
  [0x100A9] mov [r15+rbx*1+0x40], r9d
  [0x100AE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100B6] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x100BE] mov edi, [r15+r8*1+0x04]
  [0x100C3] mov esi, 0x01
  [0x100C8] mov edx, 0xFF
  [0x100CD] mov ecx, 0x1E
  [0x100D2] add r9, r15
  [0x100D5] call r9
  [0x100D8] mov [r15+r13*1+0x48], ebp
  [0x100DD] lea rdi, [r14+0xAFECAFE]
  [0x100E5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100ED] mov rsi, rbx
  [0x100F0] add r9, r15
  [0x100F3] call r9
  [0x100F6] pop r12
  [0x100F8] pop rbp
  [0x100F9] pop rbx
  [0x100FA] ret


[target-generic-event-handler]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] push rbx
  [0x1000B] push rbp
  [0x1000C] push r12
  [0x1000E] sub rsp, 0x58
  [0x10012] mov rbp, rdi
  [0x10015] mov rbx, rcx
  [0x10018] mov r9, rdx
  [0x1001B] lea r8, [r14+0xAFECAFE]
  [0x10023] cmp r9, r8
  [0x10026] jnz 0x0000000000010112
  [0x1002C] mov r9d, [r15+r13*1+0xA0]
  [0x10034] mov r8d, 0x8000
  [0x1003A] and r9, r8
  [0x1003D] xor r8, r8
  [0x10040] cmp r9, r8
  [0x10043] jnz 0x000000000001010A
  [0x10049] mov r12, [r15+rbx*1+0x10]
  [0x1004E] mov r9, [r15+rbx*1+0x18]
  [0x10053] movd xmm8, r9d
  [0x10058] mov edi, [r15+r13*1+0x8C]
  [0x10060] mov rsi, r12
  [0x10063] movss xmm7, dword ptr [0x000000000001006B]
  [0x1006B] mov rcx, r14
  [0x1006E] mov r9d, [r15+rdi*1-0x04]
  [0x10073] mov r9d, [r15+r9*1+0x3C]
  [0x10078] movd edx, xmm7
  [0x1007C] movsxd rdx, edx
  [0x1007F] add r9, r15
  [0x10082] call r9
  [0x10085] mov rbx, rax
  [0x10088] mov edi, [r15+r13*1+0x8C]
  [0x10090] mov r9, r14
  [0x10093] cmp rbp, r9
  [0x10096] jz 0x00000000000100A6
  [0x1009C] mov r9d, [r15+rbp*1+0x14]
  [0x100A1] jmp 0x00000000000100A9
  [0x100A6] mov r9, r14
  [0x100A9] mov r8d, [r15+r9*1]
  [0x100AD] movsxd r8, dword ptr [r15+r8*1+0x24]
  [0x100B2] xor rcx, rcx
  [0x100B5] shl r9, 0x20
  [0x100B9] shr r9, 0x20
  [0x100BD] or rcx, r9
  [0x100C0] shl r8, 0x20
  [0x100C4] or rcx, r8
  [0x100C7] mov r9d, [r15+rdi*1-0x04]
  [0x100CC] mov r9d, [r15+r9*1+0x3C]
  [0x100D1] mov rsi, r12
  [0x100D4] movd edx, xmm8
  [0x100D9] movsxd rdx, edx
  [0x100DC] add r9, r15
  [0x100DF] call r9
  [0x100E2] movd xmm7, ebx
  [0x100E6] movd xmm6, eax
  [0x100EA] ucomiss xmm7, xmm6
  [0x100ED] jz 0x00000000000100FD
  [0x100F3] lea rax, [r14+0x08]
  [0x100F8] jmp 0x0000000000010105
  [0x100FD] lea rax, [r14+0xAFECAFE]
  [0x10105] jmp 0x000000000001010D
  [0x1010A] mov rax, r14
  [0x1010D] jmp 0x0000000000010EB5
  [0x10112] lea r8, [r14+0xAFECAFE]
  [0x1011A] cmp r9, r8
  [0x1011D] jnz 0x0000000000010148
  [0x10123] mov edi, [r15+r13*1+0x8C]
  [0x1012B] mov rsi, [r15+rbx*1+0x10]
  [0x10130] mov r9d, [r15+rdi*1-0x04]
  [0x10135] mov r9d, [r15+r9*1+0x38]
  [0x1013A] add r9, r15
  [0x1013D] call r9
  [0x10140] mov rax, rbx
  [0x10143] jmp 0x0000000000010EB5
  [0x10148] lea r8, [r14+0xAFECAFE]
  [0x10150] cmp r9, r8
  [0x10153] jnz 0x00000000000101EC
  [0x10159] mov r9d, [r15+r13*1+0x6C]
  [0x1015E] mov r9d, [r15+r9*1+0x72C]
  [0x10166] mov r8, r14
  [0x10169] cmp r9, r8
  [0x1016C] jz 0x00000000000101A8
  [0x10172] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1017A] mov r8d, [r15+r13*1+0x6C]
  [0x1017F] mov edi, [r15+r8*1+0x72C]
  [0x10187] mov r8d, [r15+r13*1+0x6C]
  [0x1018C] movss xmm7, dword ptr [r15+r8*1+0x730]
  [0x10196] movd esi, xmm7
  [0x1019A] movsxd rsi, esi
  [0x1019D] add r9, r15
  [0x101A0] call r9
  [0x101A3] jmp 0x00000000000101E7
  [0x101A8] mov r9d, [r15+r13*1+0x6C]
  [0x101AD] mov r9d, [r15+r9*1+0x94C]
  [0x101B5] mov r8, r14
  [0x101B8] cmp r9, r8
  [0x101BB] jz 0x00000000000101E4
  [0x101C1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101C9] mov r8d, [r15+r13*1+0x6C]
  [0x101CE] mov edi, [r15+r8*1+0x94C]
  [0x101D6] mov rsi, r14
  [0x101D9] add r9, r15
  [0x101DC] call r9
  [0x101DF] jmp 0x00000000000101E7
  [0x101E4] mov rax, r14
  [0x101E7] jmp 0x0000000000010EB5
  [0x101EC] lea r8, [r14+0xAFECAFE]
  [0x101F4] cmp r9, r8
  [0x101F7] jnz 0x0000000000010205
  [0x101FD] mov rax, r14
  [0x10200] jmp 0x0000000000010EB5
  [0x10205] lea r8, [r14+0xAFECAFE]
  [0x1020D] cmp r9, r8
  [0x10210] jnz 0x0000000000010428
  [0x10216] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1021E] mov rsi, [r15+rbx*1+0x10]
  [0x10223] mov r9d, [r15+rdi*1-0x04]
  [0x10228] mov r9d, [r15+r9*1+0x34]
  [0x1022D] add r9, r15
  [0x10230] call r9
  [0x10233] mov r9, r14
  [0x10236] cmp rax, r9
  [0x10239] jz 0x0000000000010420
  [0x1023F] mov ebp, [r15+rax*1+0x34]
  [0x10244] movsxd r9, dword ptr [r15+rbp*1+0x58]
  [0x10249] xor r8, r8
  [0x1024C] cmp r9, r8
  [0x1024F] jnz 0x0000000000010279
  [0x10255] movss xmm7, dword ptr [0x000000000001025D]
  [0x1025D] mov r9d, [r15+r13*1+0x8C]
  [0x10265] movss [r15+r9*1+0x44], xmm7
  [0x1026C] movd r9d, xmm7
  [0x10271] movsxd r9, r9d
  [0x10274] jmp 0x00000000000102BF
  [0x10279] mov edi, [r15+r13*1+0x8C]
  [0x10281] mov esi, 0x08
  [0x10286] mov r8, 0xFFFFFFFFFFFF0000
  [0x1028D] or r8, r9
  [0x10290] cvtsi2ss xmm7, r8d
  [0x10295] mov rcx, r14
  [0x10298] mov r9d, [r15+rdi*1-0x04]
  [0x1029D] mov r9d, [r15+r9*1+0x3C]
  [0x102A2] movd edx, xmm7
  [0x102A6] movsxd rdx, edx
  [0x102A9] add r9, r15
  [0x102AC] call r9
  [0x102AF] mov r9d, [r15+r13*1+0x8C]
  [0x102B7] mov [r15+r9*1+0x44], eax
  [0x102BC] mov r9, rax
  [0x102BF] movsxd r9, dword ptr [r15+rbp*1+0x0C]
  [0x102C4] mov r8d, 0x0C
  [0x102CA] shl r9, 0x03
  [0x102CE] add r9, r8
  [0x102D1] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x102D9] mov r8d, [r15+r8*1+0xD0]
  [0x102E1] add r9, r8
  [0x102E4] mov r9, [r15+r9*1]
  [0x102E8] xor r8, r8
  [0x102EB] mov rcx, r14
  [0x102EE] cmp r9, r8
  [0x102F1] jnz 0x00000000000102FC
  [0x102F7] lea rcx, [r14+0x08]
  [0x102FC] mov r9, rcx
  [0x102FF] mov r8, r14
  [0x10302] cmp r9, r8
  [0x10305] jz 0x0000000000010330
  [0x1030B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10313] movsxd r9, dword ptr [r15+r9*1]
  [0x10317] movsxd r8, dword ptr [r15+rbp*1+0x0C]
  [0x1031C] mov rcx, r14
  [0x1031F] cmp r9, r8
  [0x10322] jl 0x000000000001032D
  [0x10328] lea rcx, [r14+0x08]
  [0x1032D] mov r9, rcx
  [0x10330] mov r8, r14
  [0x10333] cmp r9, r8
  [0x10336] jz 0x000000000001039E
  [0x1033C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10344] mov r9, [r15+r9*1+0x30C]
  [0x1034C] movsxd r8, dword ptr [r15+rbp*1+0x0C]
  [0x10351] mov rcx, 0xFFFFFFFFFFFFFFFF
  [0x10358] add r8, rcx
  [0x1035B] mov ecx, 0x0C
  [0x10360] shl r8, 0x02
  [0x10364] add r8, rcx
  [0x10367] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x1036F] add r8, rcx
  [0x10372] movsxd r8, dword ptr [r15+r8*1]
  [0x10376] mov ecx, 0x0C
  [0x1037B] shl r8, 0x03
  [0x1037F] add r8, rcx
  [0x10382] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x1038A] mov ecx, [r15+rcx*1+0xD0]
  [0x10392] add r8, rcx
  [0x10395] mov [r15+r8*1], r9
  [0x10399] jmp 0x00000000000103A1
  [0x1039E] mov r9, r14
  [0x103A1] mov rsi, rsp
  [0x103A4] sub rsi, r15
  [0x103A7] mov [r15+rsi*1+0x04], r13d
  [0x103AC] xor r9, r9
  [0x103AF] mov [r15+rsi*1+0x08], r9d
  [0x103B4] lea r9, [r14+0xAFECAFE]
  [0x103BC] mov [r15+rsi*1+0x0C], r9d
  [0x103C1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103C9] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x103D1] mov r8d, [r15+r8*1+0x10]
  [0x103D6] mov rcx, r14
  [0x103D9] cmp r8, rcx
  [0x103DC] jz 0x00000000000103F0
  [0x103E2] mov r8d, [r15+r8*1]
  [0x103E6] mov edi, [r15+r8*1+0x18]
  [0x103EB] jmp 0x00000000000103F3
  [0x103F0] mov rdi, r14
  [0x103F3] add r9, r15
  [0x103F6] call r9
  [0x103F9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10401] lea rdi, [r14+0x08]
  [0x10406] lea rsi, [0x000000000001040D]
  [0x1040D] sub rsi, r15
  [0x10410] mov rdx, [r15+rbx*1+0x10]
  [0x10415] add r9, r15
  [0x10418] call r9
  [0x1041B] jmp 0x0000000000010423
  [0x10420] mov rax, r14
  [0x10423] jmp 0x0000000000010EB5
  [0x10428] lea r8, [r14+0xAFECAFE]
  [0x10430] cmp r9, r8
  [0x10433] jnz 0x0000000000010463
  [0x10439] mov r9d, [r15+r13*1+0x6C]
  [0x1043E] mov rax, [r15+r9*1+0x95C]
  [0x10446] mov r9, [r15+rbx*1+0x10]
  [0x1044B] add rax, r9
  [0x1044E] mov r9, rax
  [0x10451] mov r8d, [r15+r13*1+0x6C]
  [0x10456] mov [r15+r8*1+0x95C], r9
  [0x1045E] jmp 0x0000000000010EB5
  [0x10463] lea r8, [r14+0xAFECAFE]
  [0x1046B] cmp r9, r8
  [0x1046E] jnz 0x0000000000010499
  [0x10474] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1047C] mov [r15+r13*1+0x48], r9d
  [0x10481] mov rdi, [r15+rbx*1+0x10]
  [0x10486] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1048E] add r9, r15
  [0x10491] call r9
  [0x10494] jmp 0x0000000000010EB5
  [0x10499] lea r8, [r14+0xAFECAFE]
  [0x104A1] cmp r9, r8
  [0x104A4] jnz 0x000000000001058D
  [0x104AA] mov r9, [r15+rbx*1+0x10]
  [0x104AF] lea r8, [r14+0xAFECAFE]
  [0x104B7] cmp r9, r8
  [0x104BA] jnz 0x000000000001051C
  [0x104C0] mov r9d, [r15+r13*1+0x8C]
  [0x104C8] movsxd r9, dword ptr [r15+r9*1+0x24]
  [0x104CD] mov r8, [r15+rbx*1+0x18]
  [0x104D2] mov rax, r14
  [0x104D5] cmp r9, r8
  [0x104D8] jnz 0x00000000000104E3
  [0x104DE] lea rax, [r14+0x08]
  [0x104E3] mov r9, r14
  [0x104E6] cmp rax, r9
  [0x104E9] jz 0x0000000000010517
  [0x104EF] movss xmm7, dword ptr [0x00000000000104F7]
  [0x104F7] mov r9d, [r15+r13*1+0x8C]
  [0x104FF] movss xmm6, dword ptr [r15+r9*1+0x28]
  [0x10506] mov rax, r14
  [0x10509] ucomiss xmm7, xmm6
  [0x1050C] jnb 0x0000000000010517
  [0x10512] lea rax, [r14+0x08]
  [0x10517] jmp 0x0000000000010588
  [0x1051C] lea r8, [r14+0xAFECAFE]
  [0x10524] cmp r9, r8
  [0x10527] jnz 0x0000000000010561
  [0x1052D] mov edi, [r15+r13*1+0x8C]
  [0x10535] mov rsi, [r15+rbx*1+0x18]
  [0x1053A] movss xmm7, dword ptr [0x0000000000010542]
  [0x10542] mov rcx, r14
  [0x10545] mov r9d, [r15+rdi*1-0x04]
  [0x1054A] mov r9d, [r15+r9*1+0x3C]
  [0x1054F] movd edx, xmm7
  [0x10553] movsxd rdx, edx
  [0x10556] add r9, r15
  [0x10559] call r9
  [0x1055C] jmp 0x0000000000010588
  [0x10561] lea r8, [r14+0xAFECAFE]
  [0x10569] cmp r9, r8
  [0x1056C] jnz 0x0000000000010585
  [0x10572] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1057A] add r9, r15
  [0x1057D] call r9
  [0x10580] jmp 0x0000000000010588
  [0x10585] mov rax, r14
  [0x10588] jmp 0x0000000000010EB5
  [0x1058D] lea r8, [r14+0xAFECAFE]
  [0x10595] cmp r9, r8
  [0x10598] jnz 0x0000000000010721
  [0x1059E] mov r9, [r15+rbx*1+0x10]
  [0x105A3] lea r8, [r14+0xAFECAFE]
  [0x105AB] cmp r9, r8
  [0x105AE] jnz 0x000000000001060D
  [0x105B4] mov r9d, [r15+r13*1+0x6C]
  [0x105B9] vmovaps xmm7, [r15+r9*1+0x0C]
  [0x105C0] vmovaps [r15+r13*1+0x1BC], xmm7
  [0x105CA] mov r9d, [r15+r13*1+0xA0]
  [0x105D2] mov r8d, 0x20000
  [0x105D8] or r9, r8
  [0x105DB] mov [r15+r13*1+0xA0], r9d
  [0x105E3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105EB] mov rdi, [r15+rbx*1+0x18]
  [0x105F0] mov esi, 0x0C
  [0x105F5] mov r8d, [r15+r13*1+0x6C]
  [0x105FA] add rsi, r8
  [0x105FD] mov edx, 0x30
  [0x10602] add r9, r15
  [0x10605] call r9
  [0x10608] jmp 0x000000000001071C
  [0x1060D] lea r8, [r14+0xAFECAFE]
  [0x10615] cmp r9, r8
  [0x10618] jnz 0x00000000000106E4
  [0x1061E] mov r9d, [r15+r13*1+0xA0]
  [0x10626] mov r8d, 0x20000
  [0x1062C] not r8
  [0x1062F] and r9, r8
  [0x10632] mov [r15+r13*1+0xA0], r9d
  [0x1063A] mov rbx, [r15+rbx*1+0x18]
  [0x1063F] mov edi, [r15+r13*1+0x6C]
  [0x10644] mov rsi, rbx
  [0x10647] xor r9, r9
  [0x1064A] add rsi, r9
  [0x1064D] mov r9d, [r15+rdi*1-0x04]
  [0x10652] mov r9d, [r15+r9*1+0x88]
  [0x1065A] add r9, r15
  [0x1065D] call r9
  [0x10660] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10668] mov edi, 0x1C
  [0x1066D] mov r8d, [r15+r13*1+0x6C]
  [0x10672] add rdi, r8
  [0x10675] mov r8d, 0x10
  [0x1067B] add rbx, r8
  [0x1067E] mov rsi, rbx
  [0x10681] add r9, r15
  [0x10684] call r9
  [0x10687] mov edi, [r15+r13*1+0x6C]
  [0x1068C] mov r9d, [r15+rdi*1-0x04]
  [0x10691] mov r9d, [r15+r9*1+0x64]
  [0x10696] add r9, r15
  [0x10699] call r9
  [0x1069C] mov r9d, [r15+r13*1+0x6C]
  [0x106A1] mov r9, [r15+r9*1+0x10C]
  [0x106A9] mov r8d, 0x07
  [0x106AF] or r9, r8
  [0x106B2] mov r8d, [r15+r13*1+0x6C]
  [0x106B7] mov [r15+r8*1+0x10C], r9
  [0x106BF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x106C7] mov rax, [r15+r9*1+0x30C]
  [0x106CF] mov r9, rax
  [0x106D2] mov r8d, [r15+r13*1+0x6C]
  [0x106D7] mov [r15+r8*1+0x504], r9
  [0x106DF] jmp 0x000000000001071C
  [0x106E4] lea r8, [r14+0xAFECAFE]
  [0x106EC] cmp r9, r8
  [0x106EF] jnz 0x0000000000010719
  [0x106F5] mov eax, [r15+r13*1+0xA0]
  [0x106FD] mov r9d, 0x20000
  [0x10703] not r9
  [0x10706] and rax, r9
  [0x10709] mov r9, rax
  [0x1070C] mov [r15+r13*1+0xA0], r9d
  [0x10714] jmp 0x000000000001071C
  [0x10719] mov rax, r14
  [0x1071C] jmp 0x0000000000010EB5
  [0x10721] lea r8, [r14+0xAFECAFE]
  [0x10729] cmp r9, r8
  [0x1072C] jnz 0x000000000001074D
  [0x10732] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1073A] mov rdi, [r15+rbx*1+0x10]
  [0x1073F] add r9, r15
  [0x10742] call r9
  [0x10745] mov rax, rbx
  [0x10748] jmp 0x0000000000010EB5
  [0x1074D] lea r8, [r14+0xAFECAFE]
  [0x10755] cmp r9, r8
  [0x10758] jnz 0x00000000000107E1
  [0x1075E] mov r9d, [r15+r13*1+0x78]
  [0x10763] mov edi, [r15+r9*1+0x24]
  [0x10768] mov rsi, [r15+rbx*1+0x10]
  [0x1076D] mov rdx, [r15+rbx*1+0x18]
  [0x10772] mov rcx, 0xFFFFFFFFFFFFFFFF
  [0x10779] mov r9d, [r15+rdi*1-0x04]
  [0x1077E] mov r9d, [r15+r9*1+0x38]
  [0x10783] add r9, r15
  [0x10786] call r9
  [0x10789] mov r9d, [r15+r13*1+0xCC]
  [0x10791] mov r8, r14
  [0x10794] cmp r9, r8
  [0x10797] jz 0x00000000000107D9
  [0x1079D] mov r9d, [r15+r13*1+0xCC]
  [0x107A5] mov r9d, [r15+r9*1]
  [0x107A9] mov r9d, [r15+r9*1+0x78]
  [0x107AE] mov edi, [r15+r9*1+0x24]
  [0x107B3] mov rsi, [r15+rbx*1+0x10]
  [0x107B8] mov rdx, [r15+rbx*1+0x18]
  [0x107BD] mov rcx, 0xFFFFFFFFFFFFFFFF
  [0x107C4] mov r9d, [r15+rdi*1-0x04]
  [0x107C9] mov r9d, [r15+r9*1+0x38]
  [0x107CE] add r9, r15
  [0x107D1] call r9
  [0x107D4] jmp 0x00000000000107DC
  [0x107D9] mov rax, r14
  [0x107DC] jmp 0x0000000000010EB5
  [0x107E1] lea r8, [r14+0xAFECAFE]
  [0x107E9] cmp r9, r8
  [0x107EC] jnz 0x000000000001089A
  [0x107F2] mov r9, [r15+rbx*1+0x10]
  [0x107F7] mov r8d, [r15+r13*1+0xB8]
  [0x107FF] mov [r15+r8*1+0x74], r9d
  [0x10804] mov r9, [r15+rbx*1+0x18]
  [0x10809] mov r8, r14
  [0x1080C] cmp r9, r8
  [0x1080F] jz 0x0000000000010876
  [0x10815] mov r9d, [r15+r13*1+0xA0]
  [0x1081D] mov r8d, 0x40000
  [0x10823] or r9, r8
  [0x10826] mov [r15+r13*1+0xA0], r9d
  [0x1082E] mov r9, [r15+rbx*1+0x18]
  [0x10833] vmovaps xmm7, [r15+r9*1]
  [0x10839] vmovaps [r15+r13*1+0x21C], xmm7
  [0x10843] mov edi, [r15+r13*1+0xB8]
  [0x1084B] mov esi, 0x21C
  [0x10850] add rsi, r13
  [0x10853] lea rdx, [r14+0xAFECAFE]
  [0x1085B] mov r9d, [r15+rdi*1-0x04]
  [0x10860] mov r9d, [r15+r9*1+0x3C]
  [0x10865] mov rcx, rbp
  [0x10868] add r9, r15
  [0x1086B] call r9
  [0x1086E] mov rax, rbx
  [0x10871] jmp 0x0000000000010895
  [0x10876] mov eax, [r15+r13*1+0xA0]
  [0x1087E] mov r9d, 0x40000
  [0x10884] not r9
  [0x10887] and rax, r9
  [0x1088A] mov r9, rax
  [0x1088D] mov [r15+r13*1+0xA0], r9d
  [0x10895] jmp 0x0000000000010EB5
  [0x1089A] lea r8, [r14+0xAFECAFE]
  [0x108A2] cmp r9, r8
  [0x108A5] jnz 0x00000000000109EA
  [0x108AB] mov r9, [r15+rbx*1+0x10]
  [0x108B0] mov r8, r14
  [0x108B3] cmp r9, r8
  [0x108B6] jz 0x00000000000108DB
  [0x108BC] mov r9d, [r15+r13*1+0xCC]
  [0x108C4] mov r8, r14
  [0x108C7] mov rcx, r14
  [0x108CA] cmp r9, r8
  [0x108CD] jnz 0x00000000000108D8
  [0x108D3] lea rcx, [r14+0x08]
  [0x108D8] mov r9, rcx
  [0x108DB] mov r8, r14
  [0x108DE] cmp r9, r8
  [0x108E1] jz 0x0000000000010977
  [0x108E7] mov edi, [r15+r14*1+0xBADBEEF]
  [0x108EF] mov esi, [r15+r14*1+0xBADBEEF]
  [0x108F7] mov edx, 0x4000
  [0x108FC] mov r9d, [r15+rdi*1-0x04]
  [0x10901] mov r9d, [r15+r9*1+0x48]
  [0x10906] add r9, r15
  [0x10909] call r9
  [0x1090C] mov rbx, rax
  [0x1090F] mov r9, r14
  [0x10912] cmp rbx, r9
  [0x10915] jz 0x0000000000010964
  [0x1091B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10923] mov r9d, [r15+r9*1+0x34]
  [0x10928] mov rdi, rbx
  [0x1092B] lea rdx, [r14+0xAFECAFE]
  [0x10933] mov ecx, 0x70004000
  [0x10938] mov rsi, r13
  [0x1093B] add r9, r15
  [0x1093E] call r9
  [0x10941] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10949] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10951] mov rdi, rbx
  [0x10954] add r9, r15
  [0x10957] call r9
  [0x1095A] mov eax, [r15+rbx*1+0x14]
  [0x1095F] jmp 0x0000000000010967
  [0x10964] mov rax, r14
  [0x10967] mov r9, rax
  [0x1096A] mov [r15+r13*1+0xCC], r9d
  [0x10972] jmp 0x00000000000109E5
  [0x10977] mov r9, [r15+rbx*1+0x10]
  [0x1097C] mov r8, r14
  [0x1097F] mov rcx, r14
  [0x10982] cmp r9, r8
  [0x10985] jnz 0x0000000000010990
  [0x1098B] lea rcx, [r14+0x08]
  [0x10990] mov r9, rcx
  [0x10993] mov r8, r14
  [0x10996] cmp r9, r8
  [0x10999] jz 0x00000000000109A7
  [0x1099F] mov r9d, [r15+r13*1+0xCC]
  [0x109A7] mov r8, r14
  [0x109AA] cmp r9, r8
  [0x109AD] jz 0x00000000000109E2
  [0x109B3] mov r9d, [r15+r13*1+0xCC]
  [0x109BB] mov edi, [r15+r9*1]
  [0x109BF] mov r9d, [r15+rdi*1-0x04]
  [0x109C4] mov r9d, [r15+r9*1+0x38]
  [0x109C9] add r9, r15
  [0x109CC] call r9
  [0x109CF] mov r9, r14
  [0x109D2] mov [r15+r13*1+0xCC], r9d
  [0x109DA] mov rax, r14
  [0x109DD] jmp 0x00000000000109E5
  [0x109E2] mov rax, r14
  [0x109E5] jmp 0x0000000000010EB5
  [0x109EA] lea r8, [r14+0xAFECAFE]
  [0x109F2] cmp r9, r8
  [0x109F5] jnz 0x0000000000010AE4
  [0x109FB] mov r9, [r15+rbx*1+0x10]
  [0x10A00] mov r8, r14
  [0x10A03] cmp r9, r8
  [0x10A06] jz 0x0000000000010A2E
  [0x10A0C] mov r9d, [r15+r13*1+0x78]
  [0x10A11] movzx r9, word ptr [r15+r9*1]
  [0x10A16] mov r8d, 0x08
  [0x10A1C] or r9, r8
  [0x10A1F] mov r8d, [r15+r13*1+0x78]
  [0x10A24] mov [r15+r8*1], r9w
  [0x10A29] jmp 0x0000000000010A4E
  [0x10A2E] mov r9d, [r15+r13*1+0x78]
  [0x10A33] movzx r9, word ptr [r15+r9*1]
  [0x10A38] mov r8d, 0x08
  [0x10A3E] not r8
  [0x10A41] and r9, r8
  [0x10A44] mov r8d, [r15+r13*1+0x78]
  [0x10A49] mov [r15+r8*1], r9w
  [0x10A4E] mov r9, rsp
  [0x10A51] sub r9, r15
  [0x10A54] mov [r15+r9*1+0x04], ebp
  [0x10A59] mov [r15+r9*1+0x08], esi
  [0x10A5E] mov [r15+r9*1+0x0C], edx
  [0x10A63] mov r8, [r15+rbx*1+0x10]
  [0x10A68] mov [r15+r9*1+0x10], r8
  [0x10A6D] mov r8, [r15+rbx*1+0x18]
  [0x10A72] mov [r15+r9*1+0x18], r8
  [0x10A77] mov r8, [r15+rbx*1+0x20]
  [0x10A7C] mov [r15+r9*1+0x20], r8
  [0x10A81] mov r8, [r15+rbx*1+0x28]
  [0x10A86] mov [r15+r9*1+0x28], r8
  [0x10A8B] mov r8, [r15+rbx*1+0x30]
  [0x10A90] mov [r15+r9*1+0x30], r8
  [0x10A95] mov r8, [r15+rbx*1+0x38]
  [0x10A9A] mov [r15+r9*1+0x38], r8
  [0x10A9F] mov r8, [r15+rbx*1+0x40]
  [0x10AA4] mov [r15+r9*1+0x40], r8
  [0x10AA9] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10AB1] mov ecx, [r15+r13*1+0xCC]
  [0x10AB9] mov rdx, r14
  [0x10ABC] cmp rcx, rdx
  [0x10ABF] jz 0x0000000000010AD3
  [0x10AC5] mov ecx, [r15+rcx*1]
  [0x10AC9] mov edi, [r15+rcx*1+0x18]
  [0x10ACE] jmp 0x0000000000010AD6
  [0x10AD3] mov rdi, r14
  [0x10AD6] mov rsi, r9
  [0x10AD9] add r8, r15
  [0x10ADC] call r8
  [0x10ADF] jmp 0x0000000000010EB5
  [0x10AE4] lea r8, [r14+0xAFECAFE]
  [0x10AEC] cmp r9, r8
  [0x10AEF] jnz 0x0000000000010B51
  [0x10AF5] mov r9, [r15+rbx*1+0x10]
  [0x10AFA] mov r8, r14
  [0x10AFD] cmp r9, r8
  [0x10B00] jz 0x0000000000010B2D
  [0x10B06] mov r9d, [r15+r13*1+0x74]
  [0x10B0B] mov r9d, [r15+r9*1+0x5C]
  [0x10B10] movsxd r8, dword ptr [r15+r9*1+0x18]
  [0x10B15] mov ecx, 0x20
  [0x10B1A] not rcx
  [0x10B1D] and r8, rcx
  [0x10B20] mov [r15+r9*1+0x18], r8d
  [0x10B25] xor rax, rax
  [0x10B28] jmp 0x0000000000010B4C
  [0x10B2D] mov r9d, [r15+r13*1+0x74]
  [0x10B32] mov r9d, [r15+r9*1+0x5C]
  [0x10B37] movsxd r8, dword ptr [r15+r9*1+0x18]
  [0x10B3C] mov ecx, 0x20
  [0x10B41] or r8, rcx
  [0x10B44] mov [r15+r9*1+0x18], r8d
  [0x10B49] xor rax, rax
  [0x10B4C] jmp 0x0000000000010EB5
  [0x10B51] lea r8, [r14+0xAFECAFE]
  [0x10B59] cmp r9, r8
  [0x10B5C] jnz 0x0000000000010BF7
  [0x10B62] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10B6A] mov edi, 0x1EC
  [0x10B6F] mov r8d, [r15+r13*1+0x6C]
  [0x10B74] add rdi, r8
  [0x10B77] mov esi, 0x1EC
  [0x10B7C] mov r8d, [r15+r13*1+0x6C]
  [0x10B81] add rsi, r8
  [0x10B84] mov rdx, [r15+rbx*1+0x10]
  [0x10B89] add r9, r15
  [0x10B8C] call r9
  [0x10B8F] mov r9d, [r15+r13*1+0x6C]
  [0x10B94] mov r9d, [r15+r9*1+0x298]
  [0x10B9C] movsxd r9, dword ptr [r15+r9*1+0x20]
  [0x10BA1] shl r9, 0x02
  [0x10BA5] mov r8d, 0x04
  [0x10BAB] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x10BB3] add r8, rcx
  [0x10BB6] add r9, r8
  [0x10BB9] mov r9d, [r15+r9*1]
  [0x10BBD] movss xmm7, dword ptr [r15+r9*1+0x48]
  [0x10BC4] movss xmm6, dword ptr [0x0000000000010BCC]
  [0x10BCC] ucomiss xmm7, xmm6
  [0x10BCF] jnz 0x0000000000010BEF
  [0x10BD5] mov edi, [r15+r13*1+0x6C]
  [0x10BDA] mov r9d, [r15+rdi*1-0x04]
  [0x10BDF] mov r9d, [r15+r9*1+0x64]
  [0x10BE4] add r9, r15
  [0x10BE7] call r9
  [0x10BEA] jmp 0x0000000000010BF2
  [0x10BEF] mov rax, r14
  [0x10BF2] jmp 0x0000000000010EB5
  [0x10BF7] lea r8, [r14+0xAFECAFE]
  [0x10BFF] cmp r9, r8
  [0x10C02] jnz 0x0000000000010C4B
  [0x10C08] mov rsi, rsp
  [0x10C0B] sub rsi, r15
  [0x10C0E] mov [r15+rsi*1+0x04], r13d
  [0x10C13] mov r9d, 0x01
  [0x10C19] mov [r15+rsi*1+0x08], r9d
  [0x10C1E] lea r9, [r14+0xAFECAFE]
  [0x10C26] mov [r15+rsi*1+0x0C], r9d
  [0x10C2B] mov r9, [r15+rbx*1+0x10]
  [0x10C30] mov [r15+rsi*1+0x10], r9
  [0x10C35] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C3D] mov rdi, rbp
  [0x10C40] add r9, r15
  [0x10C43] call r9
  [0x10C46] jmp 0x0000000000010EB5
  [0x10C4B] lea r8, [r14+0xAFECAFE]
  [0x10C53] cmp r9, r8
  [0x10C56] jnz 0x0000000000010C82
  [0x10C5C] movss xmm7, dword ptr [0x0000000000010C64]
  [0x10C64] mov r9d, [r15+r13*1+0x98]
  [0x10C6C] movss [r15+r9*1+0x100], xmm7
  [0x10C76] movd eax, xmm7
  [0x10C7A] movsxd rax, eax
  [0x10C7D] jmp 0x0000000000010EB5
  [0x10C82] lea r8, [r14+0xAFECAFE]
  [0x10C8A] cmp r9, r8
  [0x10C8D] jnz 0x0000000000010CB6
  [0x10C93] mov r9d, [r15+r13*1+0x6C]
  [0x10C98] vmovaps xmm7, [r15+r9*1+0x0C]
  [0x10C9F] mov r9d, [r15+r13*1+0x6C]
  [0x10CA4] vmovaps [r15+r9*1+0x4BC], xmm7
  [0x10CAE] mov rax, r14
  [0x10CB1] jmp 0x0000000000010EB5
  [0x10CB6] lea r8, [r14+0xAFECAFE]
  [0x10CBE] cmp r9, r8
  [0x10CC1] jnz 0x0000000000010DAE
  [0x10CC7] mov r9, [r15+rbx*1+0x10]
  [0x10CCC] mov r8, r14
  [0x10CCF] cmp r9, r8
  [0x10CD2] jz 0x0000000000010CFC
  [0x10CD8] mov r9d, [r15+r13*1+0x74]
  [0x10CDD] movzx r9, byte ptr [r15+r9*1]
  [0x10CE2] mov r8d, 0x20
  [0x10CE8] not r8
  [0x10CEB] and r9, r8
  [0x10CEE] mov r8d, [r15+r13*1+0x74]
  [0x10CF3] mov [r15+r8*1], r9b
  [0x10CF7] jmp 0x0000000000010D18
  [0x10CFC] mov r9d, [r15+r13*1+0x74]
  [0x10D01] movzx r9, byte ptr [r15+r9*1]
  [0x10D06] mov r8d, 0x20
  [0x10D0C] or r9, r8
  [0x10D0F] mov r8d, [r15+r13*1+0x74]
  [0x10D14] mov [r15+r8*1], r9b
  [0x10D18] mov r9, rsp
  [0x10D1B] sub r9, r15
  [0x10D1E] mov [r15+r9*1+0x04], ebp
  [0x10D23] mov [r15+r9*1+0x08], esi
  [0x10D28] mov [r15+r9*1+0x0C], edx
  [0x10D2D] mov r8, [r15+rbx*1+0x10]
  [0x10D32] mov [r15+r9*1+0x10], r8
  [0x10D37] mov r8, [r15+rbx*1+0x18]
  [0x10D3C] mov [r15+r9*1+0x18], r8
  [0x10D41] mov r8, [r15+rbx*1+0x20]
  [0x10D46] mov [r15+r9*1+0x20], r8
  [0x10D4B] mov r8, [r15+rbx*1+0x28]
  [0x10D50] mov [r15+r9*1+0x28], r8
  [0x10D55] mov r8, [r15+rbx*1+0x30]
  [0x10D5A] mov [r15+r9*1+0x30], r8
  [0x10D5F] mov r8, [r15+rbx*1+0x38]
  [0x10D64] mov [r15+r9*1+0x38], r8
  [0x10D69] mov r8, [r15+rbx*1+0x40]
  [0x10D6E] mov [r15+r9*1+0x40], r8
  [0x10D73] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10D7B] mov ecx, [r15+r13*1+0xD0]
  [0x10D83] mov rdx, r14
  [0x10D86] cmp rcx, rdx
  [0x10D89] jz 0x0000000000010D9D
  [0x10D8F] mov ecx, [r15+rcx*1]
  [0x10D93] mov edi, [r15+rcx*1+0x18]
  [0x10D98] jmp 0x0000000000010DA0
  [0x10D9D] mov rdi, r14
  [0x10DA0] mov rsi, r9
  [0x10DA3] add r8, r15
  [0x10DA6] call r8
  [0x10DA9] jmp 0x0000000000010EB5
  [0x10DAE] lea r8, [r14+0xAFECAFE]
  [0x10DB6] cmp r9, r8
  [0x10DB9] jnz 0x0000000000010DE7
  [0x10DBF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10DC7] mov rax, [r15+r9*1+0x30C]
  [0x10DCF] mov r9, [r15+rbx*1+0x10]
  [0x10DD4] add rax, r9
  [0x10DD7] mov r9, rax
  [0x10DDA] mov [r15+r13*1+0x234], r9
  [0x10DE2] jmp 0x0000000000010EB5
  [0x10DE7] lea r8, [r14+0xAFECAFE]
  [0x10DEF] cmp r9, r8
  [0x10DF2] jnz 0x0000000000010E70
  [0x10DF8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10E00] mov r9, [r15+r9*1+0x30C]
  [0x10E08] mov r8, [r15+rbx*1+0x10]
  [0x10E0D] add r9, r8
  [0x10E10] mov [r15+r13*1+0x23C], r9
  [0x10E18] mov r9d, [r15+r13*1+0x48]
  [0x10E1D] mov r9d, [r15+r9*1]
  [0x10E21] lea r8, [r14+0xAFECAFE]
  [0x10E29] cmp r9, r8
  [0x10E2C] jnz 0x0000000000010E68
  [0x10E32] mov rsi, rsp
  [0x10E35] sub rsi, r15
  [0x10E38] mov [r15+rsi*1+0x04], r13d
  [0x10E3D] xor r9, r9
  [0x10E40] mov [r15+rsi*1+0x08], r9d
  [0x10E45] lea r9, [r14+0xAFECAFE]
  [0x10E4D] mov [r15+rsi*1+0x0C], r9d
  [0x10E52] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10E5A] mov rdi, r13
  [0x10E5D] add r9, r15
  [0x10E60] call r9
  [0x10E63] jmp 0x0000000000010E6B
  [0x10E68] mov rax, r14
  [0x10E6B] jmp 0x0000000000010EB5
  [0x10E70] lea r8, [r14+0xAFECAFE]
  [0x10E78] cmp r9, r8
  [0x10E7B] jnz 0x0000000000010EB2
  [0x10E81] mov r9, [r15+rbx*1+0x10]
  [0x10E86] mov [r15+r13*1+0x48], r9d
  [0x10E8B] mov rdi, [r15+rbx*1+0x18]
  [0x10E90] mov rsi, [r15+rbx*1+0x20]
  [0x10E95] mov rdx, [r15+rbx*1+0x28]
  [0x10E9A] mov rcx, [r15+rbx*1+0x30]
  [0x10E9F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10EA7] add r9, r15
  [0x10EAA] call r9
  [0x10EAD] jmp 0x0000000000010EB5
  [0x10EB2] mov rax, r14
  [0x10EB5] add rsp, 0x58
  [0x10EB9] pop r12
  [0x10EBB] pop rbp
  [0x10EBC] pop rbx
  [0x10EBD] movdqa xmm8, [rsp]
  [0x10EC3] add rsp, 0x18
  [0x10EC7] ret



