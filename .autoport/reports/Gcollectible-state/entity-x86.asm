[entity-task-complete-off]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rdi*1+0x14]
  [0x10005] movzx r8, byte ptr [r15+r9*1+0x3B]
  [0x1000B] mov ecx, 0x01
  [0x10010] cmp r8, rcx
  [0x10013] jz 0x000000000001007C
  [0x10019] movzx r8, byte ptr [r15+r9*1+0x3B]
  [0x1001F] shl r8, 0x04
  [0x10023] mov ecx, 0x0C
  [0x10028] mov edx, [r15+r14*1+0xBADBEEF]
  [0x10030] mov edx, [r15+rdx*1+0x64]
  [0x10035] add rcx, rdx
  [0x10038] add r8, rcx
  [0x1003B] movzx r8, word ptr [r15+r8*1+0x08]
  [0x10041] mov ecx, 0x100
  [0x10046] not rcx
  [0x10049] and r8, rcx
  [0x1004C] movzx r9, byte ptr [r15+r9*1+0x3B]
  [0x10052] shl r9, 0x04
  [0x10056] mov ecx, 0x0C
  [0x1005B] mov edx, [r15+r14*1+0xBADBEEF]
  [0x10063] mov edx, [r15+rdx*1+0x64]
  [0x10068] add rcx, rdx
  [0x1006B] add r9, rcx
  [0x1006E] mov [r15+r9*1+0x08], r8w
  [0x10074] mov r9, r8
  [0x10077] jmp 0x000000000001007F
  [0x1007C] mov r9, r14
  [0x1007F] xor r9, r9
  [0x10082] ret


[entity-task-complete-on]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rdi*1+0x14]
  [0x10005] movzx r8, byte ptr [r15+r9*1+0x3B]
  [0x1000B] xor rcx, rcx
  [0x1000E] cmp r8, rcx
  [0x10011] jz 0x0000000000010077
  [0x10017] movzx r8, byte ptr [r15+r9*1+0x3B]
  [0x1001D] shl r8, 0x04
  [0x10021] mov ecx, 0x0C
  [0x10026] mov edx, [r15+r14*1+0xBADBEEF]
  [0x1002E] mov edx, [r15+rdx*1+0x64]
  [0x10033] add rcx, rdx
  [0x10036] add r8, rcx
  [0x10039] movzx r8, word ptr [r15+r8*1+0x08]
  [0x1003F] mov ecx, 0x100
  [0x10044] or r8, rcx
  [0x10047] movzx r9, byte ptr [r15+r9*1+0x3B]
  [0x1004D] shl r9, 0x04
  [0x10051] mov ecx, 0x0C
  [0x10056] mov edx, [r15+r14*1+0xBADBEEF]
  [0x1005E] mov edx, [r15+rdx*1+0x64]
  [0x10063] add rcx, rdx
  [0x10066] add r9, rcx
  [0x10069] mov [r15+r9*1+0x08], r8w
  [0x1006F] mov r9, r8
  [0x10072] jmp 0x000000000001007A
  [0x10077] mov r9, r14
  [0x1007A] xor r9, r9
  [0x1007D] ret


[(method actors-update level-group)]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] push rbx
  [0x1000B] push rbp
  [0x1000C] push r10
  [0x1000E] push r11
  [0x10010] push r12
  [0x10012] sub rsp, 0xA8
  [0x10019] mov rbx, rdi
  [0x1001C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10024] mov r8, r14
  [0x10027] cmp r9, r8
  [0x1002A] jz 0x00000000000101AB
  [0x10030] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10038] lea r8, [r14+0xAFECAFE]
  [0x10040] mov rcx, r14
  [0x10043] cmp r9, r8
  [0x10046] jnz 0x0000000000010051
  [0x1004C] lea rcx, [r14+0x08]
  [0x10051] mov r9, rcx
  [0x10054] mov r8, r14
  [0x10057] cmp r9, r8
  [0x1005A] jz 0x000000000001008E
  [0x10060] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10068] mov r9d, [r15+r9*1+0x50]
  [0x1006D] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10075] mov r8d, [r15+r8*1+0x30]
  [0x1007A] mov rcx, r14
  [0x1007D] cmp r9, r8
  [0x10080] jnz 0x000000000001008B
  [0x10086] lea rcx, [r14+0x08]
  [0x1008B] mov r9, rcx
  [0x1008E] mov r8, r14
  [0x10091] cmp r9, r8
  [0x10094] jz 0x00000000000100BC
  [0x1009A] mov edi, [r15+r14*1+0xBADBEEF]
  [0x100A2] mov esi, 0x01
  [0x100A7] mov r9d, [r15+rdi*1-0x04]
  [0x100AC] mov r9d, [r15+r9*1+0x58]
  [0x100B1] add r9, r15
  [0x100B4] call r9
  [0x100B7] jmp 0x00000000000100BF
  [0x100BC] mov rbp, r14
  [0x100BF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100C7] xor r8, r8
  [0x100CA] cmp r9, r8
  [0x100CD] jz 0x00000000000100F5
  [0x100D3] mov edi, [r15+r14*1+0xBADBEEF]
  [0x100DB] mov esi, 0x0A
  [0x100E0] mov r9d, [r15+rdi*1-0x04]
  [0x100E5] mov r9d, [r15+r9*1+0x50]
  [0x100EA] add r9, r15
  [0x100ED] call r9
  [0x100F0] jmp 0x00000000000100F8
  [0x100F5] mov rbp, r14
  [0x100F8] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10100] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10108] movss xmm7, dword ptr [0x0000000000010110]
  [0x10110] movss xmm6, dword ptr [0x0000000000010118]
  [0x10118] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10120] movsxd r8, dword ptr [r15+r8*1+0x230]
  [0x10128] shl r8, 0x05
  [0x1012C] mov ecx, 0x234
  [0x10131] mov edx, [r15+r14*1+0xBADBEEF]
  [0x10139] add rcx, rdx
  [0x1013C] add r8, rcx
  [0x1013F] mov r8d, [r15+r8*1+0x10]
  [0x10144] mov r8, [r15+r8*1+0x34]
  [0x10149] cvtsi2ss xmm5, r8d
  [0x1014E] movss xmm4, dword ptr [0x0000000000010156]
  [0x10156] movss xmm3, dword ptr [0x000000000001015E]
  [0x1015E] movd edi, xmm7
  [0x10162] movsxd rdi, edi
  [0x10165] movd esi, xmm6
  [0x10169] movsxd rsi, esi
  [0x1016C] movd edx, xmm5
  [0x10170] movsxd rdx, edx
  [0x10173] movd ecx, xmm4
  [0x10177] movsxd rcx, ecx
  [0x1017A] movd r8d, xmm3
  [0x1017F] movsxd r8, r8d
  [0x10182] add r9, r15
  [0x10185] call r9
  [0x10188] movd xmm7, eax
  [0x1018C] cvttss2si esi, xmm7
  [0x10190] movsxd rsi, esi
  [0x10193] mov r9d, [r15+rbp*1-0x04]
  [0x10198] mov r9d, [r15+r9*1+0x50]
  [0x1019D] mov rdi, rbp
  [0x101A0] add r9, r15
  [0x101A3] call r9
  [0x101A6] jmp 0x00000000000101AE
  [0x101AB] mov rbp, r14
  [0x101AE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101B6] add r9, r15
  [0x101B9] call r9
  [0x101BC] mov r9, r14
  [0x101BF] cmp rax, r9
  [0x101C2] jnz 0x0000000000010365
  [0x101C8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101D0] movsxd r9, dword ptr [r15+r9*1+0x230]
  [0x101D8] shl r9, 0x05
  [0x101DC] mov r8d, 0x234
  [0x101E2] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x101EA] add r8, rcx
  [0x101ED] add r9, r8
  [0x101F0] mov r9d, [r15+r9*1+0x10]
  [0x101F5] mov rbp, [r15+r9*1+0x34]
  [0x101FA] movss xmm7, dword ptr [0x0000000000010202]
  [0x10202] movss xmm6, dword ptr [0x000000000001020A]
  [0x1020A] movss xmm5, dword ptr [0x0000000000010212]
  [0x10212] mov r9d, 0x1B58
  [0x10218] sub r9, rbp
  [0x1021B] cvtsi2ss xmm4, r9d
  [0x10220] mulss xmm5, xmm4
  [0x10224] addss xmm6, xmm5
  [0x10228] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10230] movss xmm5, dword ptr [r15+r9*1+0x04]
  [0x10237] minss xmm6, xmm5
  [0x1023B] maxss xmm7, xmm6
  [0x1023F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10247] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1024F] movss xmm6, dword ptr [r15+r8*1]
  [0x10255] movss xmm5, dword ptr [0x000000000001025D]
  [0x1025D] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10265] movss xmm4, dword ptr [r15+r8*1+0x388]
  [0x1026F] mulss xmm5, xmm4
  [0x10273] movd edi, xmm6
  [0x10277] movsxd rdi, edi
  [0x1027A] movd esi, xmm7
  [0x1027E] movsxd rsi, esi
  [0x10281] movd edx, xmm5
  [0x10285] movsxd rdx, edx
  [0x10288] add r9, r15
  [0x1028B] call r9
  [0x1028E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10296] mov [r15+r9*1], eax
  [0x1029A] mov r12d, [r15+r14*1+0xBADBEEF]
  [0x102A2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102AA] movsxd r11, dword ptr [r15+r9*1+0x08]
  [0x102AF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102B7] movss xmm7, dword ptr [0x00000000000102BF]
  [0x102BF] movss xmm6, dword ptr [0x00000000000102C7]
  [0x102C7] cvtsi2ss xmm5, ebp
  [0x102CB] movss xmm4, dword ptr [0x00000000000102D3]
  [0x102D3] movss xmm3, dword ptr [0x00000000000102DB]
  [0x102DB] movd edi, xmm7
  [0x102DF] movsxd rdi, edi
  [0x102E2] movd esi, xmm6
  [0x102E6] movsxd rsi, esi
  [0x102E9] movd edx, xmm5
  [0x102ED] movsxd rdx, edx
  [0x102F0] movd ecx, xmm4
  [0x102F4] movsxd rcx, ecx
  [0x102F7] movd r8d, xmm3
  [0x102FC] movsxd r8, r8d
  [0x102FF] add r9, r15
  [0x10302] call r9
  [0x10305] movd xmm7, eax
  [0x10309] cvttss2si esi, xmm7
  [0x1030D] movsxd rsi, esi
  [0x10310] mov edx, 0x0A
  [0x10315] mov rdi, r11
  [0x10318] add r12, r15
  [0x1031B] call r12
  [0x1031E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10326] mov [r15+r9*1+0x08], eax
  [0x1032B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10333] add r9, r15
  [0x10336] call r9
  [0x10339] mov r9, r14
  [0x1033C] cmp rax, r9
  [0x1033F] jz 0x000000000001035D
  [0x10345] mov r9d, 0x3E8
  [0x1034B] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10353] mov [r15+r8*1+0x08], r9d
  [0x10358] jmp 0x0000000000010360
  [0x1035D] mov r9, r14
  [0x10360] jmp 0x0000000000010368
  [0x10365] mov r9, r14
  [0x10368] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10370] mov r8, r14
  [0x10373] cmp r9, r8
  [0x10376] jz 0x0000000000011047
  [0x1037C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10384] add r9, r15
  [0x10387] call r9
  [0x1038A] xor r12, r12
  [0x1038D] mov rbp, rax
  [0x10390] xor r11, r11
  [0x10393] jmp 0x0000000000011032
  [0x10398] mov r10d, 0xA30
  [0x1039E] imul r10d, r11d
  [0x103A2] movsxd r10, r10d
  [0x103A5] mov r9d, 0x60
  [0x103AB] add r9, rbx
  [0x103AE] add r10, r9
  [0x103B1] mov r9d, [r15+r10*1+0x10]
  [0x103B6] lea r8, [r14+0xAFECAFE]
  [0x103BE] cmp r9, r8
  [0x103C1] jnz 0x0000000000011026
  [0x103C7] mov r9d, [r15+r10*1+0x174]
  [0x103CF] lea r8, [r14+0xAFECAFE]
  [0x103D7] cmp r9, r8
  [0x103DA] jnz 0x0000000000010574
  [0x103E0] mov r10d, [r15+r10*1+0x118]
  [0x103E8] movsxd r8, dword ptr [r15+r10*1]
  [0x103EC] mov r9, r8
  [0x103EF] mov [rsp+0x50], r9
  [0x103F7] xor r8, r8
  [0x103FA] mov r9, r8
  [0x103FD] mov [rsp+0x60], r9
  [0x10405] jmp 0x0000000000010553
  [0x1040A] mov r9, [rsp+0x60]
  [0x10412] mov r8, r9
  [0x10415] shl r8, 0x06
  [0x10419] mov r9d, 0x0C
  [0x1041F] add r9, r10
  [0x10422] add r8, r9
  [0x10425] movzx r9, word ptr [r15+r8*1+0x38]
  [0x1042B] mov ecx, 0x80
  [0x10430] and r9, rcx
  [0x10433] xor rcx, rcx
  [0x10436] cmp r9, rcx
  [0x10439] jz 0x00000000000104D2
  [0x1043F] mov r9d, [r15+r8*1+0x0C]
  [0x10444] mov rcx, r14
  [0x10447] cmp r9, rcx
  [0x1044A] jnz 0x0000000000010475
  [0x10450] movzx r9, word ptr [r15+r8*1+0x38]
  [0x10456] mov ecx, 0x05
  [0x1045B] and r9, rcx
  [0x1045E] xor rcx, rcx
  [0x10461] mov rdx, r14
  [0x10464] cmp r9, rcx
  [0x10467] jz 0x0000000000010472
  [0x1046D] lea rdx, [r14+0x08]
  [0x10472] mov r9, rdx
  [0x10475] mov rcx, r14
  [0x10478] cmp r9, rcx
  [0x1047B] jnz 0x00000000000104CA
  [0x10481] mov edi, [r15+r8*1+0x08]
  [0x10486] mov r9d, [r15+rdi*1-0x04]
  [0x1048B] mov r9d, [r15+r9*1+0x68]
  [0x10490] add r9, r15
  [0x10493] call r9
  [0x10496] mov r9d, 0x01
  [0x1049C] add r12, r9
  [0x1049F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104A7] movsxd r9, dword ptr [r15+r9*1+0x08]
  [0x104AC] cmp r12, r9
  [0x104AF] jl 0x00000000000104C2
  [0x104B5] mov rax, r14
  [0x104B8] jmp 0x000000000001104D
  [0x104BD] jmp 0x00000000000104C5
  [0x104C2] mov r9, r14
  [0x104C5] jmp 0x00000000000104CD
  [0x104CA] mov r9, r14
  [0x104CD] jmp 0x0000000000010534
  [0x104D2] mov r9d, [r15+r8*1+0x0C]
  [0x104D7] mov rcx, r14
  [0x104DA] cmp r9, rcx
  [0x104DD] jz 0x0000000000010508
  [0x104E3] movzx r9, word ptr [r15+r8*1+0x38]
  [0x104E9] mov ecx, 0x08
  [0x104EE] and r9, rcx
  [0x104F1] xor rcx, rcx
  [0x104F4] mov rdx, r14
  [0x104F7] cmp r9, rcx
  [0x104FA] jnz 0x0000000000010505
  [0x10500] lea rdx, [r14+0x08]
  [0x10505] mov r9, rdx
  [0x10508] mov rcx, r14
  [0x1050B] cmp r9, rcx
  [0x1050E] jz 0x000000000001052E
  [0x10514] mov edi, [r15+r8*1+0x08]
  [0x10519] mov r9d, [r15+rdi*1-0x04]
  [0x1051E] mov r9d, [r15+r9*1+0x6C]
  [0x10523] add r9, r15
  [0x10526] call r9
  [0x10529] jmp 0x0000000000010531
  [0x1052E] mov rax, r14
  [0x10531] mov r9, rax
  [0x10534] mov r9, [rsp+0x60]
  [0x1053C] mov r8, r9
  [0x1053F] mov r9d, 0x01
  [0x10545] add r8, r9
  [0x10548] mov r9, r8
  [0x1054B] mov [rsp+0x60], r9
  [0x10553] mov r9, [rsp+0x50]
  [0x1055B] mov r8, [rsp+0x60]
  [0x10563] cmp r8, r9
  [0x10566] jl 0x000000000001040A
  [0x1056C] mov r9, r14
  [0x1056F] jmp 0x0000000000011021
  [0x10574] mov r9d, [r15+r10*1+0x174]
  [0x1057C] lea r8, [r14+0xAFECAFE]
  [0x10584] cmp r9, r8
  [0x10587] jnz 0x00000000000107DF
  [0x1058D] mov r8d, [r15+r10*1+0x118]
  [0x10595] mov r9, r8
  [0x10598] mov [rsp+0x30], r9
  [0x105A0] mov r9, [rsp+0x30]
  [0x105A8] movsxd r8, dword ptr [r15+r9*1]
  [0x105AC] mov r9, r8
  [0x105AF] mov [rsp+0x40], r9
  [0x105B7] xor r8, r8
  [0x105BA] mov r9, r8
  [0x105BD] mov [rsp+0x48], r9
  [0x105C5] jmp 0x00000000000107BE
  [0x105CA] mov r9, [rsp+0x48]
  [0x105D2] mov r8, r9
  [0x105D5] shl r8, 0x06
  [0x105D9] mov ecx, 0x0C
  [0x105DE] mov r9, [rsp+0x30]
  [0x105E6] add rcx, r9
  [0x105E9] add r8, rcx
  [0x105EC] mov r9, r8
  [0x105EF] mov [rsp+0x78], r9
  [0x105F7] mov r9, [rsp+0x78]
  [0x105FF] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10605] mov r9d, 0x80
  [0x1060B] and r8, r9
  [0x1060E] xor r9, r9
  [0x10611] mov rcx, r14
  [0x10614] cmp r8, r9
  [0x10617] jz 0x0000000000010622
  [0x1061D] lea rcx, [r14+0x08]
  [0x10622] mov r9, rcx
  [0x10625] mov r8, r14
  [0x10628] cmp r9, r8
  [0x1062B] jz 0x0000000000010654
  [0x10631] mov r9, [rsp+0x78]
  [0x10639] movsxd rsi, dword ptr [r15+r9*1+0x14]
  [0x1063E] mov r9d, [r15+r10*1-0x04]
  [0x10643] mov r9d, [r15+r9*1+0x38]
  [0x10648] mov rdi, r10
  [0x1064B] add r9, r15
  [0x1064E] call r9
  [0x10651] mov r9, rax
  [0x10654] mov r8, r14
  [0x10657] cmp r9, r8
  [0x1065A] jz 0x00000000000106EF
  [0x10660] mov r9, [rsp+0x78]
  [0x10668] mov r8d, [r15+r9*1+0x0C]
  [0x1066D] mov r9, r8
  [0x10670] mov r8, r14
  [0x10673] cmp r9, r8
  [0x10676] jnz 0x00000000000106AA
  [0x1067C] mov r9, [rsp+0x78]
  [0x10684] movzx r8, word ptr [r15+r9*1+0x38]
  [0x1068A] mov r9d, 0x05
  [0x10690] and r8, r9
  [0x10693] xor r9, r9
  [0x10696] mov rcx, r14
  [0x10699] cmp r8, r9
  [0x1069C] jz 0x00000000000106A7
  [0x106A2] lea rcx, [r14+0x08]
  [0x106A7] mov r9, rcx
  [0x106AA] mov r8, r14
  [0x106AD] cmp r9, r8
  [0x106B0] jnz 0x00000000000106E7
  [0x106B6] mov r9, [rsp+0x78]
  [0x106BE] mov edi, [r15+r9*1+0x08]
  [0x106C3] mov r9d, [r15+rdi*1-0x04]
  [0x106C8] mov r9d, [r15+r9*1+0x68]
  [0x106CD] add r9, r15
  [0x106D0] call r9
  [0x106D3] mov r9, r12
  [0x106D6] mov r8d, 0x01
  [0x106DC] add r9, r8
  [0x106DF] mov r12, r9
  [0x106E2] jmp 0x00000000000106EA
  [0x106E7] mov r9, r14
  [0x106EA] jmp 0x0000000000010779
  [0x106EF] mov r9, [rsp+0x78]
  [0x106F7] mov r8d, [r15+r9*1+0x0C]
  [0x106FC] mov r9, r8
  [0x106FF] mov r8, r14
  [0x10702] cmp r9, r8
  [0x10705] jz 0x0000000000010739
  [0x1070B] mov r9, [rsp+0x78]
  [0x10713] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10719] mov r9d, 0x08
  [0x1071F] and r8, r9
  [0x10722] xor r9, r9
  [0x10725] mov rcx, r14
  [0x10728] cmp r8, r9
  [0x1072B] jnz 0x0000000000010736
  [0x10731] lea rcx, [r14+0x08]
  [0x10736] mov r9, rcx
  [0x10739] mov r8, r14
  [0x1073C] cmp r9, r8
  [0x1073F] jz 0x0000000000010776
  [0x10745] mov r9, [rsp+0x78]
  [0x1074D] mov edi, [r15+r9*1+0x08]
  [0x10752] mov r9d, [r15+rdi*1-0x04]
  [0x10757] mov r9d, [r15+r9*1+0x6C]
  [0x1075C] add r9, r15
  [0x1075F] call r9
  [0x10762] mov r9, r12
  [0x10765] mov r8d, 0x01
  [0x1076B] add r9, r8
  [0x1076E] mov r12, r9
  [0x10771] jmp 0x0000000000010779
  [0x10776] mov r9, r14
  [0x10779] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10781] movsxd r9, dword ptr [r15+r9*1+0x08]
  [0x10786] cmp r12, r9
  [0x10789] jl 0x000000000001079C
  [0x1078F] mov rax, r14
  [0x10792] jmp 0x000000000001104D
  [0x10797] jmp 0x000000000001079F
  [0x1079C] mov r9, r14
  [0x1079F] mov r9, [rsp+0x48]
  [0x107A7] mov r8, r9
  [0x107AA] mov r9d, 0x01
  [0x107B0] add r8, r9
  [0x107B3] mov r9, r8
  [0x107B6] mov [rsp+0x48], r9
  [0x107BE] mov r9, [rsp+0x40]
  [0x107C6] mov r8, [rsp+0x48]
  [0x107CE] cmp r8, r9
  [0x107D1] jl 0x00000000000105CA
  [0x107D7] mov r9, r14
  [0x107DA] jmp 0x0000000000011021
  [0x107DF] mov r9d, [r15+r10*1+0x174]
  [0x107E7] lea r8, [r14+0xAFECAFE]
  [0x107EF] cmp r9, r8
  [0x107F2] jnz 0x0000000000010983
  [0x107F8] mov r10d, [r15+r10*1+0x118]
  [0x10800] movsxd r8, dword ptr [r15+r10*1]
  [0x10804] mov r9, r8
  [0x10807] mov [rsp+0x68], r9
  [0x1080F] xor r8, r8
  [0x10812] mov r9, r8
  [0x10815] mov [rsp+0x70], r9
  [0x1081D] jmp 0x0000000000010962
  [0x10822] mov r9, [rsp+0x70]
  [0x1082A] mov r8, r9
  [0x1082D] shl r8, 0x06
  [0x10831] mov r9d, 0x0C
  [0x10837] add r9, r10
  [0x1083A] add r8, r9
  [0x1083D] lea r9, [r14+0x08]
  [0x10842] mov rcx, r14
  [0x10845] cmp r9, rcx
  [0x10848] jz 0x00000000000108E1
  [0x1084E] mov r9d, [r15+r8*1+0x0C]
  [0x10853] mov rcx, r14
  [0x10856] cmp r9, rcx
  [0x10859] jnz 0x0000000000010884
  [0x1085F] movzx r9, word ptr [r15+r8*1+0x38]
  [0x10865] mov ecx, 0x05
  [0x1086A] and r9, rcx
  [0x1086D] xor rcx, rcx
  [0x10870] mov rdx, r14
  [0x10873] cmp r9, rcx
  [0x10876] jz 0x0000000000010881
  [0x1087C] lea rdx, [r14+0x08]
  [0x10881] mov r9, rdx
  [0x10884] mov rcx, r14
  [0x10887] cmp r9, rcx
  [0x1088A] jnz 0x00000000000108D9
  [0x10890] mov edi, [r15+r8*1+0x08]
  [0x10895] mov r9d, [r15+rdi*1-0x04]
  [0x1089A] mov r9d, [r15+r9*1+0x68]
  [0x1089F] add r9, r15
  [0x108A2] call r9
  [0x108A5] mov r9d, 0x01
  [0x108AB] add r12, r9
  [0x108AE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x108B6] movsxd r9, dword ptr [r15+r9*1+0x08]
  [0x108BB] cmp r12, r9
  [0x108BE] jl 0x00000000000108D1
  [0x108C4] mov rax, r14
  [0x108C7] jmp 0x000000000001104D
  [0x108CC] jmp 0x00000000000108D4
  [0x108D1] mov r9, r14
  [0x108D4] jmp 0x00000000000108DC
  [0x108D9] mov r9, r14
  [0x108DC] jmp 0x0000000000010943
  [0x108E1] mov r9d, [r15+r8*1+0x0C]
  [0x108E6] mov rcx, r14
  [0x108E9] cmp r9, rcx
  [0x108EC] jz 0x0000000000010917
  [0x108F2] movzx r9, word ptr [r15+r8*1+0x38]
  [0x108F8] mov ecx, 0x08
  [0x108FD] and r9, rcx
  [0x10900] xor rcx, rcx
  [0x10903] mov rdx, r14
  [0x10906] cmp r9, rcx
  [0x10909] jnz 0x0000000000010914
  [0x1090F] lea rdx, [r14+0x08]
  [0x10914] mov r9, rdx
  [0x10917] mov rcx, r14
  [0x1091A] cmp r9, rcx
  [0x1091D] jz 0x000000000001093D
  [0x10923] mov edi, [r15+r8*1+0x08]
  [0x10928] mov r9d, [r15+rdi*1-0x04]
  [0x1092D] mov r9d, [r15+r9*1+0x6C]
  [0x10932] add r9, r15
  [0x10935] call r9
  [0x10938] jmp 0x0000000000010940
  [0x1093D] mov rax, r14
  [0x10940] mov r9, rax
  [0x10943] mov r9, [rsp+0x70]
  [0x1094B] mov r8, r9
  [0x1094E] mov r9d, 0x01
  [0x10954] add r8, r9
  [0x10957] mov r9, r8
  [0x1095A] mov [rsp+0x70], r9
  [0x10962] mov r9, [rsp+0x68]
  [0x1096A] mov r8, [rsp+0x70]
  [0x10972] cmp r8, r9
  [0x10975] jl 0x0000000000010822
  [0x1097B] mov r9, r14
  [0x1097E] jmp 0x0000000000011021
  [0x10983] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1098B] mov r8, r14
  [0x1098E] cmp r9, r8
  [0x10991] jnz 0x0000000000010BDF
  [0x10997] mov r10d, [r15+r10*1+0x118]
  [0x1099F] movsxd r8, dword ptr [r15+r10*1]
  [0x109A3] mov r9, r8
  [0x109A6] mov [rsp+0x28], r9
  [0x109AE] xor r8, r8
  [0x109B1] mov r9, r8
  [0x109B4] mov [rsp+0x38], r9
  [0x109BC] jmp 0x0000000000010BBE
  [0x109C1] mov r9, [rsp+0x38]
  [0x109C9] mov r8, r9
  [0x109CC] shl r8, 0x06
  [0x109D0] mov r9d, 0x0C
  [0x109D6] add r9, r10
  [0x109D9] add r8, r9
  [0x109DC] mov r9, r8
  [0x109DF] mov [rsp+0x58], r9
  [0x109E7] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x109EF] mov edi, 0x20
  [0x109F4] mov r9, [rsp+0x58]
  [0x109FC] add rdi, r9
  [0x109FF] mov rsi, rbp
  [0x10A02] add r8, r15
  [0x10A05] call r8
  [0x10A08] movd xmm7, eax
  [0x10A0C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10A14] movss xmm6, dword ptr [r15+r9*1+0x04]
  [0x10A1B] mov r9, r14
  [0x10A1E] ucomiss xmm7, xmm6
  [0x10A21] jnb 0x0000000000010A2C
  [0x10A27] lea r9, [r14+0x08]
  [0x10A2C] mov r8, r14
  [0x10A2F] cmp r9, r8
  [0x10A32] jz 0x0000000000010A66
  [0x10A38] mov r9, [rsp+0x58]
  [0x10A40] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10A46] mov r9d, 0x600
  [0x10A4C] and r8, r9
  [0x10A4F] xor r9, r9
  [0x10A52] mov rcx, r14
  [0x10A55] cmp r8, r9
  [0x10A58] jnz 0x0000000000010A63
  [0x10A5E] lea rcx, [r14+0x08]
  [0x10A63] mov r9, rcx
  [0x10A66] mov r8, r14
  [0x10A69] cmp r9, r8
  [0x10A6C] jz 0x0000000000010B21
  [0x10A72] mov r9, [rsp+0x58]
  [0x10A7A] mov r8d, [r15+r9*1+0x0C]
  [0x10A7F] mov r9, r8
  [0x10A82] mov r8, r14
  [0x10A85] cmp r9, r8
  [0x10A88] jnz 0x0000000000010ABC
  [0x10A8E] mov r9, [rsp+0x58]
  [0x10A96] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10A9C] mov r9d, 0x05
  [0x10AA2] and r8, r9
  [0x10AA5] xor r9, r9
  [0x10AA8] mov rcx, r14
  [0x10AAB] cmp r8, r9
  [0x10AAE] jz 0x0000000000010AB9
  [0x10AB4] lea rcx, [r14+0x08]
  [0x10AB9] mov r9, rcx
  [0x10ABC] mov r8, r14
  [0x10ABF] cmp r9, r8
  [0x10AC2] jnz 0x0000000000010B19
  [0x10AC8] mov r9, [rsp+0x58]
  [0x10AD0] mov edi, [r15+r9*1+0x08]
  [0x10AD5] mov r9d, [r15+rdi*1-0x04]
  [0x10ADA] mov r9d, [r15+r9*1+0x68]
  [0x10ADF] add r9, r15
  [0x10AE2] call r9
  [0x10AE5] mov r9d, 0x01
  [0x10AEB] add r12, r9
  [0x10AEE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10AF6] movsxd r9, dword ptr [r15+r9*1+0x08]
  [0x10AFB] cmp r12, r9
  [0x10AFE] jl 0x0000000000010B11
  [0x10B04] mov rax, r14
  [0x10B07] jmp 0x000000000001104D
  [0x10B0C] jmp 0x0000000000010B14
  [0x10B11] mov r9, r14
  [0x10B14] jmp 0x0000000000010B1C
  [0x10B19] mov r9, r14
  [0x10B1C] jmp 0x0000000000010B9F
  [0x10B21] mov r9, [rsp+0x58]
  [0x10B29] mov r8d, [r15+r9*1+0x0C]
  [0x10B2E] mov r9, r8
  [0x10B31] mov r8, r14
  [0x10B34] cmp r9, r8
  [0x10B37] jz 0x0000000000010B6B
  [0x10B3D] mov r9, [rsp+0x58]
  [0x10B45] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10B4B] mov r9d, 0x08
  [0x10B51] and r8, r9
  [0x10B54] xor r9, r9
  [0x10B57] mov rcx, r14
  [0x10B5A] cmp r8, r9
  [0x10B5D] jnz 0x0000000000010B68
  [0x10B63] lea rcx, [r14+0x08]
  [0x10B68] mov r9, rcx
  [0x10B6B] mov r8, r14
  [0x10B6E] cmp r9, r8
  [0x10B71] jz 0x0000000000010B99
  [0x10B77] mov r9, [rsp+0x58]
  [0x10B7F] mov edi, [r15+r9*1+0x08]
  [0x10B84] mov r9d, [r15+rdi*1-0x04]
  [0x10B89] mov r9d, [r15+r9*1+0x6C]
  [0x10B8E] add r9, r15
  [0x10B91] call r9
  [0x10B94] jmp 0x0000000000010B9C
  [0x10B99] mov rax, r14
  [0x10B9C] mov r9, rax
  [0x10B9F] mov r9, [rsp+0x38]
  [0x10BA7] mov r8, r9
  [0x10BAA] mov r9d, 0x01
  [0x10BB0] add r8, r9
  [0x10BB3] mov r9, r8
  [0x10BB6] mov [rsp+0x38], r9
  [0x10BBE] mov r9, [rsp+0x28]
  [0x10BC6] mov r8, [rsp+0x38]
  [0x10BCE] cmp r8, r9
  [0x10BD1] jl 0x00000000000109C1
  [0x10BD7] mov r9, r14
  [0x10BDA] jmp 0x0000000000011021
  [0x10BDF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10BE7] mov r8, r14
  [0x10BEA] cmp r9, r8
  [0x10BED] jz 0x000000000001101E
  [0x10BF3] mov r9d, [r15+r10*1+0x194]
  [0x10BFB] mov r8, r14
  [0x10BFE] cmp r9, r8
  [0x10C01] jz 0x0000000000010C0F
  [0x10C07] mov r9d, [r15+r10*1+0x188]
  [0x10C0F] mov r8, r14
  [0x10C12] cmp r9, r8
  [0x10C15] jnz 0x0000000000011016
  [0x10C1B] mov r8d, [r15+r10*1+0x118]
  [0x10C23] mov r9, r8
  [0x10C26] mov [rsp], r9
  [0x10C2E] mov r9, [rsp]
  [0x10C36] movsxd r8, dword ptr [r15+r9*1]
  [0x10C3A] mov r9, r8
  [0x10C3D] mov [rsp+0x08], r9
  [0x10C45] mov r8, r14
  [0x10C48] mov r9, r8
  [0x10C4B] mov [rsp+0x10], r9
  [0x10C53] xor r8, r8
  [0x10C56] mov r9, r8
  [0x10C59] mov [rsp+0x18], r9
  [0x10C61] jmp 0x0000000000010FF5
  [0x10C66] mov r9, [rsp+0x18]
  [0x10C6E] mov r8, r9
  [0x10C71] shl r8, 0x06
  [0x10C75] mov ecx, 0x0C
  [0x10C7A] mov r9, [rsp]
  [0x10C82] add rcx, r9
  [0x10C85] add r8, rcx
  [0x10C88] mov r9, r8
  [0x10C8B] mov [rsp+0x20], r9
  [0x10C93] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C9B] mov r8, r14
  [0x10C9E] cmp r9, r8
  [0x10CA1] jz 0x0000000000010CD3
  [0x10CA7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10CAF] mov r9d, [r15+r9*1+0x13C]
  [0x10CB7] mov r8, r14
  [0x10CBA] mov rcx, r14
  [0x10CBD] cmp r9, r8
  [0x10CC0] jnz 0x0000000000010CCB
  [0x10CC6] lea rcx, [r14+0x08]
  [0x10CCB] mov r9, rcx
  [0x10CCE] jmp 0x0000000000010CD6
  [0x10CD3] mov r9, r14
  [0x10CD6] mov r8, r14
  [0x10CD9] cmp r9, r8
  [0x10CDC] jnz 0x0000000000010D05
  [0x10CE2] mov r9, [rsp+0x20]
  [0x10CEA] movsxd rsi, dword ptr [r15+r9*1+0x14]
  [0x10CEF] mov r9d, [r15+r10*1-0x04]
  [0x10CF4] mov r9d, [r15+r9*1+0x38]
  [0x10CF9] mov rdi, r10
  [0x10CFC] add r9, r15
  [0x10CFF] call r9
  [0x10D02] mov r9, rax
  [0x10D05] mov r8, r14
  [0x10D08] cmp r9, r8
  [0x10D0B] jz 0x0000000000010D3F
  [0x10D11] mov r9, [rsp+0x20]
  [0x10D19] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10D1F] mov r9d, 0x600
  [0x10D25] and r8, r9
  [0x10D28] xor r9, r9
  [0x10D2B] mov rcx, r14
  [0x10D2E] cmp r8, r9
  [0x10D31] jnz 0x0000000000010D3C
  [0x10D37] lea rcx, [r14+0x08]
  [0x10D3C] mov r9, rcx
  [0x10D3F] mov r8, r14
  [0x10D42] cmp r9, r8
  [0x10D45] jz 0x0000000000010F26
  [0x10D4B] mov r9, [rsp+0x20]
  [0x10D53] mov r8d, [r15+r9*1+0x0C]
  [0x10D58] mov r9, r14
  [0x10D5B] cmp r8, r9
  [0x10D5E] jnz 0x0000000000010DA9
  [0x10D64] mov r9, [rsp+0x20]
  [0x10D6C] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10D72] mov r9d, 0x05
  [0x10D78] and r8, r9
  [0x10D7B] xor r9, r9
  [0x10D7E] mov rcx, r14
  [0x10D81] cmp r8, r9
  [0x10D84] jz 0x0000000000010D8F
  [0x10D8A] lea rcx, [r14+0x08]
  [0x10D8F] mov r8, rcx
  [0x10D92] mov r9, r14
  [0x10D95] cmp r8, r9
  [0x10D98] jnz 0x0000000000010DA9
  [0x10D9E] mov r9, [rsp+0x10]
  [0x10DA6] mov r8, r9
  [0x10DA9] mov r9, r14
  [0x10DAC] cmp r8, r9
  [0x10DAF] jnz 0x0000000000010F1E
  [0x10DB5] mov r9, [rsp+0x20]
  [0x10DBD] mov edi, [r15+r9*1+0x08]
  [0x10DC2] mov r9d, [r15+rdi*1-0x04]
  [0x10DC7] mov r9d, [r15+r9*1+0x68]
  [0x10DCC] add r9, r15
  [0x10DCF] call r9
  [0x10DD2] mov r9d, 0x01
  [0x10DD8] add r12, r9
  [0x10DDB] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10DE3] mov r9d, [r15+rdi*1-0x04]
  [0x10DE8] mov r9d, [r15+r9*1+0x74]
  [0x10DED] add r9, r15
  [0x10DF0] call r9
  [0x10DF3] cvtsi2ss xmm8, eax
  [0x10DF8] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10E00] mov r9d, [r15+rdi*1-0x04]
  [0x10E05] mov r9d, [r15+r9*1+0x60]
  [0x10E0A] add r9, r15
  [0x10E0D] call r9
  [0x10E10] cvtsi2ss xmm7, eax
  [0x10E14] movss xmm6, dword ptr [0x0000000000010E1C]
  [0x10E1C] ucomiss xmm6, xmm7
  [0x10E1F] jz 0x0000000000010E2F
  [0x10E25] divss xmm8, xmm7
  [0x10E2A] jmp 0x0000000000010E5B
  [0x10E2F] mov r9d, 0x7F7FFFFF
  [0x10E35] mov r8d, 0x80000000
  [0x10E3B] movd ecx, xmm8
  [0x10E40] movsxd rcx, ecx
  [0x10E43] and rcx, r8
  [0x10E46] xor r9, rcx
  [0x10E49] movd ecx, xmm7
  [0x10E4D] movsxd rcx, ecx
  [0x10E50] and rcx, r8
  [0x10E53] xor r9, rcx
  [0x10E56] movd xmm8, r9d
  [0x10E5B] movss xmm7, dword ptr [0x0000000000010E63]
  [0x10E63] ucomiss xmm8, xmm7
  [0x10E67] jnb 0x0000000000010F16
  [0x10E6D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10E75] mov [rsp+0x80], r9
  [0x10E7D] xor r9, r9
  [0x10E80] mov [rsp+0x88], r9
  [0x10E88] lea r9, [0x0000000000010E8F]
  [0x10E8F] sub r9, r15
  [0x10E92] mov [rsp+0x90], r9
  [0x10E9A] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10EA2] mov r9d, [r15+rdi*1-0x04]
  [0x10EA7] mov r9d, [r15+r9*1+0x74]
  [0x10EAC] add r9, r15
  [0x10EAF] call r9
  [0x10EB2] mov [rsp+0x98], rax
  [0x10EBA] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10EC2] mov r9d, [r15+rdi*1-0x04]
  [0x10EC7] mov r9d, [r15+r9*1+0x60]
  [0x10ECC] add r9, r15
  [0x10ECF] call r9
  [0x10ED2] mov rdi, [rsp+0x88]
  [0x10EDA] mov rsi, [rsp+0x90]
  [0x10EE2] mov rdx, [rsp+0x98]
  [0x10EEA] mov rcx, rax
  [0x10EED] mov r9, [rsp+0x80]
  [0x10EF5] mov r8, r9
  [0x10EF8] add r8, r15
  [0x10EFB] call r8
  [0x10EFE] lea r8, [r14+0x08]
  [0x10F03] mov r9, r8
  [0x10F06] mov [rsp+0x10], r9
  [0x10F0E] mov r9, r8
  [0x10F11] jmp 0x0000000000010F19
  [0x10F16] mov r9, r14
  [0x10F19] jmp 0x0000000000010F21
  [0x10F1E] mov r9, r14
  [0x10F21] jmp 0x0000000000010FB0
  [0x10F26] mov r9, [rsp+0x20]
  [0x10F2E] mov r8d, [r15+r9*1+0x0C]
  [0x10F33] mov r9, r8
  [0x10F36] mov r8, r14
  [0x10F39] cmp r9, r8
  [0x10F3C] jz 0x0000000000010F70
  [0x10F42] mov r9, [rsp+0x20]
  [0x10F4A] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10F50] mov r9d, 0x08
  [0x10F56] and r8, r9
  [0x10F59] xor r9, r9
  [0x10F5C] mov rcx, r14
  [0x10F5F] cmp r8, r9
  [0x10F62] jnz 0x0000000000010F6D
  [0x10F68] lea rcx, [r14+0x08]
  [0x10F6D] mov r9, rcx
  [0x10F70] mov r8, r14
  [0x10F73] cmp r9, r8
  [0x10F76] jz 0x0000000000010FAD
  [0x10F7C] mov r9, [rsp+0x20]
  [0x10F84] mov edi, [r15+r9*1+0x08]
  [0x10F89] mov r9d, [r15+rdi*1-0x04]
  [0x10F8E] mov r9d, [r15+r9*1+0x6C]
  [0x10F93] add r9, r15
  [0x10F96] call r9
  [0x10F99] mov r9, r12
  [0x10F9C] mov r8d, 0x01
  [0x10FA2] add r9, r8
  [0x10FA5] mov r12, r9
  [0x10FA8] jmp 0x0000000000010FB0
  [0x10FAD] mov r9, r14
  [0x10FB0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10FB8] movsxd r9, dword ptr [r15+r9*1+0x08]
  [0x10FBD] cmp r12, r9
  [0x10FC0] jl 0x0000000000010FD3
  [0x10FC6] mov rax, r14
  [0x10FC9] jmp 0x000000000001104D
  [0x10FCE] jmp 0x0000000000010FD6
  [0x10FD3] mov r9, r14
  [0x10FD6] mov r9, [rsp+0x18]
  [0x10FDE] mov r8, r9
  [0x10FE1] mov r9d, 0x01
  [0x10FE7] add r8, r9
  [0x10FEA] mov r9, r8
  [0x10FED] mov [rsp+0x18], r9
  [0x10FF5] mov r9, [rsp+0x08]
  [0x10FFD] mov r8, [rsp+0x18]
  [0x11005] cmp r8, r9
  [0x11008] jl 0x0000000000010C66
  [0x1100E] mov r9, r14
  [0x11011] jmp 0x0000000000011019
  [0x11016] mov r9, r14
  [0x11019] jmp 0x0000000000011021
  [0x1101E] mov r9, r14
  [0x11021] jmp 0x0000000000011029
  [0x11026] mov r9, r14
  [0x11029] mov r9d, 0x01
  [0x1102F] add r11, r9
  [0x11032] movsxd r9, dword ptr [r15+rbx*1]
  [0x11036] cmp r11, r9
  [0x11039] jl 0x0000000000010398
  [0x1103F] mov r9, r14
  [0x11042] jmp 0x000000000001104A
  [0x11047] mov r9, r14
  [0x1104A] xor rax, rax
  [0x1104D] add rsp, 0xA8
  [0x11054] pop r12
  [0x11056] pop r11
  [0x11058] pop r10
  [0x1105A] pop rbp
  [0x1105B] pop rbx
  [0x1105C] movdqa xmm8, [rsp]
  [0x11062] add rsp, 0x18
  [0x11066] ret


[(method run-logic? process-drawable)]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] push rbx
  [0x1000B] push rbp
  [0x1000C] push r12
  [0x1000E] push rbx
  [0x1000F] mov rbx, rdi
  [0x10012] mov r9d, [r15+rbx*1+0x04]
  [0x10017] mov r8d, 0x20
  [0x1001D] and r9, r8
  [0x10020] xor r8, r8
  [0x10023] mov rax, r14
  [0x10026] cmp r9, r8
  [0x10029] jnz 0x0000000000010034
  [0x1002F] lea rax, [r14+0x08]
  [0x10034] mov r9, r14
  [0x10037] cmp rax, r9
  [0x1003A] jnz 0x0000000000010155
  [0x10040] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10048] movss xmm8, dword ptr [r15+r9*1]
  [0x1004E] mov r9d, [r15+rbx*1+0x6C]
  [0x10053] movss xmm7, dword ptr [r15+r9*1]
  [0x10059] addss xmm8, xmm7
  [0x1005E] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x10066] mov r12d, 0x0C
  [0x1006C] mov r9d, [r15+rbx*1+0x6C]
  [0x10071] add r12, r9
  [0x10074] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1007C] add r9, r15
  [0x1007F] call r9
  [0x10082] mov rdi, r12
  [0x10085] mov rsi, rax
  [0x10088] add rbp, r15
  [0x1008B] call rbp
  [0x1008D] movd xmm7, eax
  [0x10091] mov rax, r14
  [0x10094] ucomiss xmm8, xmm7
  [0x10098] jb 0x00000000000100A3
  [0x1009E] lea rax, [r14+0x08]
  [0x100A3] mov r9, r14
  [0x100A6] cmp rax, r9
  [0x100A9] jnz 0x0000000000010155
  [0x100AF] mov r9d, [r15+rbx*1+0x78]
  [0x100B4] xor r8, r8
  [0x100B7] mov rax, r14
  [0x100BA] cmp r9, r8
  [0x100BD] jz 0x00000000000100C8
  [0x100C3] lea rax, [r14+0x08]
  [0x100C8] mov r9, r14
  [0x100CB] cmp rax, r9
  [0x100CE] jz 0x00000000000100FD
  [0x100D4] mov r9d, [r15+rbx*1+0x78]
  [0x100D9] mov r9d, [r15+r9*1+0x0C]
  [0x100DE] mov r8d, 0x2C
  [0x100E4] mov ecx, [r15+rbx*1+0x78]
  [0x100E9] add r8, rcx
  [0x100EC] mov rax, r14
  [0x100EF] cmp r9, r8
  [0x100F2] jz 0x00000000000100FD
  [0x100F8] lea rax, [r14+0x08]
  [0x100FD] mov r9, r14
  [0x10100] cmp rax, r9
  [0x10103] jnz 0x0000000000010155
  [0x10109] mov r9d, [r15+rbx*1+0x74]
  [0x1010E] xor r8, r8
  [0x10111] mov rax, r14
  [0x10114] cmp r9, r8
  [0x10117] jz 0x0000000000010122
  [0x1011D] lea rax, [r14+0x08]
  [0x10122] mov r9, r14
  [0x10125] cmp rax, r9
  [0x10128] jz 0x0000000000010155
  [0x1012E] mov r9d, [r15+rbx*1+0x74]
  [0x10133] movzx r9, byte ptr [r15+r9*1]
  [0x10138] mov r8d, 0x10
  [0x1013E] and r9, r8
  [0x10141] xor r8, r8
  [0x10144] mov rax, r14
  [0x10147] cmp r9, r8
  [0x1014A] jz 0x0000000000010155
  [0x10150] lea rax, [r14+0x08]
  [0x10155] pop rbx
  [0x10156] pop r12
  [0x10158] pop rbp
  [0x10159] pop rbx
  [0x1015A] movdqa xmm8, [rsp]
  [0x10160] add rsp, 0x18
  [0x10164] ret


[reset-cameras]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1000C] mov r9d, [r15+rdi*1-0x04]
  [0x10011] mov r9d, [r15+r9*1+0x58]
  [0x10016] add r9, r15
  [0x10019] call r9
  [0x1001C] xor rbx, rbx
  [0x1001F] jmp 0x00000000000100D2
  [0x10024] mov r9d, 0xA30
  [0x1002A] imul r9d, ebx
  [0x1002E] movsxd r9, r9d
  [0x10031] mov r8d, 0x60
  [0x10037] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x1003F] add r8, rcx
  [0x10042] add r9, r8
  [0x10045] mov r8d, [r15+r9*1+0x10]
  [0x1004A] lea rcx, [r14+0xAFECAFE]
  [0x10052] cmp r8, rcx
  [0x10055] jnz 0x00000000000100C6
  [0x1005B] mov r9d, [r15+r9*1+0x2C]
  [0x10060] mov ebp, [r15+r9*1+0x70]
  [0x10065] xor r9, r9
  [0x10068] cmp rbp, r9
  [0x1006B] jz 0x00000000000100BE
  [0x10071] xor r12, r12
  [0x10074] jmp 0x00000000000100A9
  [0x10079] mov r9d, 0x0C
  [0x1007F] mov r8, r12
  [0x10082] shl r8, 0x02
  [0x10086] add r8, r9
  [0x10089] add r8, rbp
  [0x1008C] mov edi, [r15+r8*1]
  [0x10090] mov r9d, [r15+rdi*1-0x04]
  [0x10095] mov r9d, [r15+r9*1+0x68]
  [0x1009A] add r9, r15
  [0x1009D] call r9
  [0x100A0] mov r9d, 0x01
  [0x100A6] add r12, r9
  [0x100A9] movsxd r9, dword ptr [r15+rbp*1]
  [0x100AD] cmp r12, r9
  [0x100B0] jl 0x0000000000010079
  [0x100B6] mov r9, r14
  [0x100B9] jmp 0x00000000000100C1
  [0x100BE] mov r9, r14
  [0x100C1] jmp 0x00000000000100C9
  [0x100C6] mov r9, r14
  [0x100C9] mov r9d, 0x01
  [0x100CF] add rbx, r9
  [0x100D2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100DA] movsxd r9, dword ptr [r15+r9*1]
  [0x100DE] cmp rbx, r9
  [0x100E1] jl 0x0000000000010024
  [0x100E7] mov r9, r14
  [0x100EA] xor r9, r9
  [0x100ED] pop r12
  [0x100EF] pop rbp
  [0x100F0] pop rbx
  [0x100F1] ret


[reset-actors]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x10
  [0x1000C] mov rbx, rdi
  [0x1000F] mov r9, r14
  [0x10012] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1001A] mov r9, rbx
  [0x1001D] lea r8, [r14+0xAFECAFE]
  [0x10025] mov rcx, r14
  [0x10028] cmp r9, r8
  [0x1002B] jnz 0x0000000000010036
  [0x10031] lea rcx, [r14+0x08]
  [0x10036] mov r8, rcx
  [0x10039] mov rcx, r14
  [0x1003C] cmp r8, rcx
  [0x1003F] jnz 0x0000000000010061
  [0x10045] lea r8, [r14+0xAFECAFE]
  [0x1004D] mov rcx, r14
  [0x10050] cmp r9, r8
  [0x10053] jnz 0x000000000001005E
  [0x10059] lea rcx, [r14+0x08]
  [0x1005E] mov r8, rcx
  [0x10061] mov rcx, r14
  [0x10064] cmp r8, rcx
  [0x10067] jz 0x0000000000010077
  [0x1006D] mov ebp, 0x26F
  [0x10072] jmp 0x00000000000100B2
  [0x10077] lea r8, [r14+0xAFECAFE]
  [0x1007F] cmp r9, r8
  [0x10082] jnz 0x0000000000010092
  [0x10088] mov ebp, 0x26F
  [0x1008D] jmp 0x00000000000100B2
  [0x10092] lea r8, [r14+0xAFECAFE]
  [0x1009A] cmp r9, r8
  [0x1009D] jnz 0x00000000000100AD
  [0x100A3] mov ebp, 0x77F
  [0x100A8] jmp 0x00000000000100B2
  [0x100AD] mov ebp, 0x67F
  [0x100B2] mov r12d, [r15+r14*1+0xBADBEEF]
  [0x100BA] xor r11, r11
  [0x100BD] jmp 0x00000000000101E2
  [0x100C2] mov r9d, 0xA30
  [0x100C8] imul r9d, r11d
  [0x100CC] movsxd r9, r9d
  [0x100CF] mov r8d, 0x60
  [0x100D5] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x100DD] add r8, rcx
  [0x100E0] add r9, r8
  [0x100E3] mov r8d, [r15+r9*1+0x10]
  [0x100E8] lea rcx, [r14+0xAFECAFE]
  [0x100F0] cmp r8, rcx
  [0x100F3] jnz 0x00000000000101D6
  [0x100F9] mov r9d, [r15+r9*1+0x2C]
  [0x100FE] mov r9d, [r15+r9*1+0x78]
  [0x10103] mov r10d, [r15+r9*1+0x118]
  [0x1010B] xor r8, r8
  [0x1010E] mov r9, r8
  [0x10111] mov [rsp], r9
  [0x10119] jmp 0x00000000000101B9
  [0x1011E] mov r9, [rsp]
  [0x10126] mov r8, r9
  [0x10129] shl r8, 0x06
  [0x1012D] mov r9d, 0x0C
  [0x10133] add r9, r10
  [0x10136] add r8, r9
  [0x10139] mov r8d, [r15+r8*1+0x08]
  [0x1013E] mov r9, r8
  [0x10141] mov [rsp+0x08], r9
  [0x10149] mov r9, [rsp+0x08]
  [0x10151] mov r8d, [r15+r9*1-0x04]
  [0x10156] mov r8d, [r15+r8*1+0x6C]
  [0x1015B] mov r9, [rsp+0x08]
  [0x10163] mov rdi, r9
  [0x10166] add r8, r15
  [0x10169] call r8
  [0x1016C] mov edi, 0x30
  [0x10171] mov r9, [rsp+0x08]
  [0x10179] mov r8d, [r15+r9*1+0x14]
  [0x1017E] add rdi, r8
  [0x10181] mov rdx, rbp
  [0x10184] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1018C] mov r9d, [r15+r9*1+0x34]
  [0x10191] mov rsi, rbx
  [0x10194] add r9, r15
  [0x10197] call r9
  [0x1019A] mov r9, [rsp]
  [0x101A2] mov r8, r9
  [0x101A5] mov r9d, 0x01
  [0x101AB] add r8, r9
  [0x101AE] mov r9, r8
  [0x101B1] mov [rsp], r9
  [0x101B9] movsxd r8, dword ptr [r15+r10*1]
  [0x101BD] mov r9, [rsp]
  [0x101C5] cmp r9, r8
  [0x101C8] jl 0x000000000001011E
  [0x101CE] mov r9, r14
  [0x101D1] jmp 0x00000000000101D9
  [0x101D6] mov r9, r14
  [0x101D9] mov r9d, 0x01
  [0x101DF] add r11, r9
  [0x101E2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101EA] movsxd r9, dword ptr [r15+r9*1]
  [0x101EE] cmp r11, r9
  [0x101F1] jl 0x00000000000100C2
  [0x101F7] mov r9, r14
  [0x101FA] mov r11d, [r12+r15*1+0x64]
  [0x101FF] xor r10, r10
  [0x10202] jmp 0x000000000001023C
  [0x10207] mov rdi, r10
  [0x1020A] shl rdi, 0x04
  [0x1020E] mov r9d, 0x0C
  [0x10214] add r9, r11
  [0x10217] add rdi, r9
  [0x1021A] mov rdx, rbp
  [0x1021D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10225] mov r9d, [r15+r9*1+0x34]
  [0x1022A] mov rsi, rbx
  [0x1022D] add r9, r15
  [0x10230] call r9
  [0x10233] mov r9d, 0x01
  [0x10239] add r10, r9
  [0x1023C] movsxd r9, dword ptr [r15+r11*1]
  [0x10240] cmp r10, r9
  [0x10243] jl 0x0000000000010207
  [0x10249] mov r9, r14
  [0x1024C] movzx r9, word ptr [r15+r11*1+0x24]
  [0x10252] mov r8d, 0x100
  [0x10258] or r9, r8
  [0x1025B] mov [r15+r11*1+0x24], r9w
  [0x10261] mov r12d, [r12+r15*1+0x60]
  [0x10266] xor r11, r11
  [0x10269] jmp 0x00000000000102A3
  [0x1026E] mov rdi, r11
  [0x10271] shl rdi, 0x04
  [0x10275] mov r9d, 0x0C
  [0x1027B] add r9, r12
  [0x1027E] add rdi, r9
  [0x10281] mov rdx, rbp
  [0x10284] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1028C] mov r9d, [r15+r9*1+0x34]
  [0x10291] mov rsi, rbx
  [0x10294] add r9, r15
  [0x10297] call r9
  [0x1029A] mov r9d, 0x01
  [0x102A0] add r11, r9
  [0x102A3] movsxd r9, dword ptr [r12+r15*1]
  [0x102A7] cmp r11, r9
  [0x102AA] jl 0x000000000001026E
  [0x102B0] mov r9, r14
  [0x102B3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102BB] mov edi, [r15+r14*1+0xBADBEEF]
  [0x102C3] lea rsi, [0x00000000000102CA]
  [0x102CA] sub rsi, r15
  [0x102CD] mov edx, [r15+r14*1+0xBADBEEF]
  [0x102D5] add r9, r15
  [0x102D8] call r9
  [0x102DB] lea r9, [r14+0xAFECAFE]
  [0x102E3] cmp rbx, r9
  [0x102E6] jnz 0x0000000000010302
  [0x102EC] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102F4] mov rdi, rbx
  [0x102F7] add r9, r15
  [0x102FA] call r9
  [0x102FD] jmp 0x0000000000010305
  [0x10302] mov rbx, r14
  [0x10305] mov r9d, 0x3E8
  [0x1030B] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10313] mov [r15+r8*1+0x08], r9d
  [0x10318] xor r9, r9
  [0x1031B] add rsp, 0x10
  [0x1031F] pop r12
  [0x10321] pop r11
  [0x10323] pop r10
  [0x10325] pop rbp
  [0x10326] pop rbx
  [0x10327] ret


[anon-function-1]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov r9d, [r15+rdi*1-0x04]
  [0x10006] mov r9d, [r15+r9*1+0x38]
  [0x1000B] add r9, r15
  [0x1000E] call r9
  [0x10011] pop rbx
  [0x10012] ret


[(method update-perm! entity-perm)]
[1m[38;2;255;000;000m- [0x10000] [0mlea r9, [r14+0xAFECAFE]
  [0x10008] cmp rsi, r9
  [0x1000B] jnz 0x0000000000010028
  [0x10011] movzx r9, word ptr [r15+rdi*1+0x08]
  [0x10017] not rdx
  [0x1001A] and r9, rdx
  [0x1001D] mov [r15+rdi*1+0x08], r9w
  [0x10023] jmp 0x00000000000100BE
  [0x10028] movzx r9, byte ptr [r15+rdi*1+0x0B]
  [0x1002E] xor r8, r8
  [0x10031] cmp r9, r8
  [0x10034] jz 0x0000000000010081
  [0x1003A] movzx r9, word ptr [r15+rdi*1+0x08]
  [0x10040] movzx r8, word ptr [r15+rdi*1+0x08]
  [0x10046] mov ecx, 0x10
  [0x1004B] and r8, rcx
  [0x1004E] xor rcx, rcx
  [0x10051] cmp r8, rcx
  [0x10054] jz 0x0000000000010065
  [0x1005A] mov r8d, 0x20C
  [0x10060] jmp 0x0000000000010068
  [0x10065] xor r8, r8
  [0x10068] mov ecx, 0x203
  [0x1006D] or r8, rcx
  [0x10070] not r8
  [0x10073] and r9, r8
  [0x10076] mov [r15+rdi*1+0x08], r9w
  [0x1007C] jmp 0x00000000000100BE
  [0x10081] movzx r9, word ptr [r15+rdi*1+0x08]
  [0x10087] movzx r8, word ptr [r15+rdi*1+0x08]
  [0x1008D] mov ecx, 0x10
  [0x10092] and r8, rcx
  [0x10095] xor rcx, rcx
  [0x10098] cmp r8, rcx
  [0x1009B] jz 0x00000000000100AC
  [0x100A1] mov r8d, 0x20C
  [0x100A7] jmp 0x00000000000100AF
  [0x100AC] xor r8, r8
  [0x100AF] or rdx, r8
  [0x100B2] not rdx
  [0x100B5] and r9, rdx
  [0x100B8] mov [r15+rdi*1+0x08], r9w
  [0x100BE] movzx r9, word ptr [r15+rdi*1+0x08]
  [0x100C4] mov r8d, 0x20
  [0x100CA] and r9, r8
  [0x100CD] xor r8, r8
  [0x100D0] cmp r9, r8
  [0x100D3] jnz 0x00000000000100E8
  [0x100D9] xor r9, r9
  [0x100DC] mov [r15+rdi*1], r9
  [0x100E0] xor r9, r9
  [0x100E3] jmp 0x00000000000100EB
  [0x100E8] mov r9, r14
  [0x100EB] mov rax, rdi
  [0x100EE] ret


[entity-deactivate-handler]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rsi*1+0x14]
  [0x10005] mov r9d, [r15+r9*1+0x0C]
  [0x1000A] cmp rdi, r9
  [0x1000D] jnz 0x0000000000010047
  [0x10013] mov r9d, [r15+rsi*1+0x14]
  [0x10018] movzx r9, word ptr [r15+r9*1+0x38]
  [0x1001E] mov r8d, 0x0A
  [0x10024] not r8
  [0x10027] and r9, r8
  [0x1002A] mov r8d, [r15+rsi*1+0x14]
  [0x1002F] mov [r15+r8*1+0x38], r9w
  [0x10035] mov r9, r14
  [0x10038] mov r8d, [r15+rsi*1+0x14]
  [0x1003D] mov [r15+r8*1+0x0C], r9d
  [0x10042] jmp 0x000000000001004A
  [0x10047] mov r9, r14
  [0x1004A] ret


[(method deactivate-entities bsp-header)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x10
  [0x1000C] mov rbx, rdi
  [0x1000F] mov ebp, [r15+rbx*1+0x6C]
  [0x10014] xor r9, r9
  [0x10017] cmp rbp, r9
  [0x1001A] jz 0x000000000001008E
  [0x10020] xor r12, r12
  [0x10023] jmp 0x0000000000010077
  [0x10028] mov r9, r12
  [0x1002B] shl r9, 0x05
  [0x1002F] mov r8d, 0x20
  [0x10035] add r8, rbp
  [0x10038] add r9, r8
  [0x1003B] mov r11d, [r15+r9*1+0x04]
  [0x10040] mov r9d, [r15+r11*1-0x04]
  [0x10045] mov r9d, [r15+r9*1+0x6C]
  [0x1004A] mov rdi, r11
  [0x1004D] add r9, r15
  [0x10050] call r9
  [0x10053] mov esi, [r15+r14*1+0xBADBEEF]
  [0x1005B] mov r9d, [r15+r11*1-0x04]
  [0x10060] mov r9d, [r15+r9*1+0x74]
  [0x10065] mov rdi, r11
  [0x10068] add r9, r15
  [0x1006B] call r9
  [0x1006E] mov r9d, 0x01
  [0x10074] add r12, r9
  [0x10077] movsx r9, word ptr [r15+rbp*1+0x02]
  [0x1007D] cmp r12, r9
  [0x10080] jl 0x0000000000010028
  [0x10086] mov r9, r14
  [0x10089] jmp 0x0000000000010091
  [0x1008E] mov r9, r14
  [0x10091] mov ebp, [r15+rbx*1+0x70]
  [0x10096] xor r9, r9
  [0x10099] cmp rbp, r9
  [0x1009C] jz 0x00000000000100EF
  [0x100A2] xor r12, r12
  [0x100A5] jmp 0x00000000000100DA
  [0x100AA] mov r9d, 0x0C
  [0x100B0] mov r8, r12
  [0x100B3] shl r8, 0x02
  [0x100B7] add r8, r9
  [0x100BA] add r8, rbp
  [0x100BD] mov edi, [r15+r8*1]
  [0x100C1] mov r9d, [r15+rdi*1-0x04]
  [0x100C6] mov r9d, [r15+r9*1+0x6C]
  [0x100CB] add r9, r15
  [0x100CE] call r9
  [0x100D1] mov r9d, 0x01
  [0x100D7] add r12, r9
  [0x100DA] movsxd r9, dword ptr [r15+rbp*1]
  [0x100DE] cmp r12, r9
  [0x100E1] jl 0x00000000000100AA
  [0x100E7] mov r9, r14
  [0x100EA] jmp 0x00000000000100F2
  [0x100EF] mov r9, r14
  [0x100F2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100FA] mov ebp, [r15+r9*1+0x10]
  [0x100FF] mov r9d, [r15+rbx*1+0x78]
  [0x10104] mov r12d, [r15+r9*1+0x1C]
  [0x10109] mov r9d, [r15+rbx*1+0x78]
  [0x1010E] mov r11d, [r15+r9*1+0x28]
  [0x10113] jmp 0x00000000000104A8
  [0x10118] mov r9, rbp
  [0x1011B] mov r8, r14
  [0x1011E] cmp r9, r8
  [0x10121] jz 0x0000000000010135
  [0x10127] mov r9d, [r15+r9*1]
  [0x1012B] mov r10d, [r15+r9*1+0x18]
  [0x10130] jmp 0x0000000000010138
  [0x10135] mov r10, r14
  [0x10138] mov r9d, [r15+rbp*1]
  [0x1013C] mov ebp, [r15+r9*1+0x0C]
  [0x10141] mov r9, r10
  [0x10144] mov r9d, [r15+r9*1+0x30]
  [0x10149] mov r8, r14
  [0x1014C] cmp r9, r8
  [0x1014F] jz 0x00000000000101B5
  [0x10155] mov r9, r10
  [0x10158] mov r9d, [r15+r9*1+0x30]
  [0x1015D] mov r9d, [r15+r9*1+0x14]
  [0x10162] mov r9d, [r15+r9*1+0x10]
  [0x10167] mov r8d, [r15+rbx*1+0x78]
  [0x1016C] cmp r9, r8
  [0x1016F] jnz 0x00000000000101AD
  [0x10175] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1017D] lea rdi, [r14+0x08]
  [0x10182] lea rsi, [0x0000000000010189]
  [0x10189] sub rsi, r15
  [0x1018C] mov rdx, r10
  [0x1018F] add r9, r15
  [0x10192] call r9
  [0x10195] mov r9d, [r15+r10*1-0x04]
  [0x1019A] mov r9d, [r15+r9*1+0x38]
  [0x1019F] mov rdi, r10
  [0x101A2] add r9, r15
  [0x101A5] call r9
  [0x101A8] jmp 0x00000000000101B0
  [0x101AD] mov r10, r14
  [0x101B0] jmp 0x00000000000104A8
  [0x101B5] mov r9d, [r15+r10*1-0x04]
  [0x101BA] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x101C2] cmp r9, r8
  [0x101C5] jnz 0x0000000000010270
  [0x101CB] mov r9, r10
  [0x101CE] mov r8d, [r15+r9*1+0x70]
  [0x101D3] xor rcx, rcx
  [0x101D6] mov rdx, r14
  [0x101D9] cmp r8, rcx
  [0x101DC] jz 0x00000000000101E7
  [0x101E2] lea rdx, [r14+0x08]
  [0x101E7] mov r8, rdx
  [0x101EA] mov rcx, r14
  [0x101ED] cmp r8, rcx
  [0x101F0] jz 0x0000000000010244
  [0x101F6] mov r8d, [r15+r9*1+0x70]
  [0x101FB] mov r8d, [r15+r8*1+0x0C]
  [0x10200] mov rcx, r12
  [0x10203] mov rdx, r14
  [0x10206] cmp r8, rcx
  [0x10209] jl 0x0000000000010214
  [0x1020F] lea rdx, [r14+0x08]
  [0x10214] mov r8, rdx
  [0x10217] mov rcx, r14
  [0x1021A] cmp r8, rcx
  [0x1021D] jz 0x0000000000010244
  [0x10223] mov r9d, [r15+r9*1+0x70]
  [0x10228] mov r9d, [r15+r9*1+0x0C]
  [0x1022D] mov r8, r11
  [0x10230] mov rcx, r14
  [0x10233] cmp r9, r8
  [0x10236] jnl 0x0000000000010241
  [0x1023C] lea rcx, [r14+0x08]
  [0x10241] mov r8, rcx
  [0x10244] mov r9, r14
  [0x10247] cmp r8, r9
  [0x1024A] jz 0x0000000000010268
  [0x10250] mov r9d, [r15+r10*1-0x04]
  [0x10255] mov r9d, [r15+r9*1+0x38]
  [0x1025A] mov rdi, r10
  [0x1025D] add r9, r15
  [0x10260] call r9
  [0x10263] jmp 0x000000000001026B
  [0x10268] mov r10, r14
  [0x1026B] jmp 0x00000000000104A8
  [0x10270] mov r9, r10
  [0x10273] mov [rsp], r9
  [0x1027B] xor r8, r8
  [0x1027E] mov rcx, r14
  [0x10281] mov r9, [rsp]
  [0x10289] cmp r9, r8
  [0x1028C] jz 0x0000000000010297
  [0x10292] lea rcx, [r14+0x08]
  [0x10297] mov r9, rcx
  [0x1029A] mov r8, r14
  [0x1029D] cmp r9, r8
  [0x102A0] jz 0x00000000000102CC
  [0x102A6] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x102AE] mov r9, [rsp]
  [0x102B6] mov edi, [r15+r9*1-0x04]
  [0x102BB] mov esi, [r15+r14*1+0xBADBEEF]
  [0x102C3] add r8, r15
  [0x102C6] call r8
  [0x102C9] mov r9, rax
  [0x102CC] mov r8, r14
  [0x102CF] cmp r9, r8
  [0x102D2] jz 0x00000000000102E8
  [0x102D8] mov r9, [rsp]
  [0x102E0] mov r8, r9
  [0x102E3] jmp 0x00000000000102EB
  [0x102E8] mov r8, r14
  [0x102EB] mov r9, r14
  [0x102EE] cmp r8, r9
  [0x102F1] jz 0x00000000000104A5
  [0x102F7] mov r9, r8
  [0x102FA] mov r9d, [r15+r9*1+0x94]
  [0x10302] xor rcx, rcx
  [0x10305] mov rdx, r14
  [0x10308] cmp r9, rcx
  [0x1030B] jz 0x0000000000010316
  [0x10311] lea rdx, [r14+0x08]
  [0x10316] mov r9, rdx
  [0x10319] mov rcx, r14
  [0x1031C] cmp r9, rcx
  [0x1031F] jz 0x000000000001037F
  [0x10325] mov r9, r8
  [0x10328] mov r9d, [r15+r9*1+0x94]
  [0x10330] mov r9d, [r15+r9*1+0x0C]
  [0x10335] mov rcx, r12
  [0x10338] mov rdx, r14
  [0x1033B] cmp r9, rcx
  [0x1033E] jl 0x0000000000010349
  [0x10344] lea rdx, [r14+0x08]
  [0x10349] mov r9, rdx
  [0x1034C] mov rcx, r14
  [0x1034F] cmp r9, rcx
  [0x10352] jz 0x000000000001037F
  [0x10358] mov r9, r8
  [0x1035B] mov r9d, [r15+r9*1+0x94]
  [0x10363] mov r9d, [r15+r9*1+0x0C]
  [0x10368] mov rcx, r11
  [0x1036B] mov rdx, r14
  [0x1036E] cmp r9, rcx
  [0x10371] jnl 0x000000000001037C
  [0x10377] lea rdx, [r14+0x08]
  [0x1037C] mov r9, rdx
  [0x1037F] mov rcx, r14
  [0x10382] cmp r9, rcx
  [0x10385] jz 0x00000000000103D0
  [0x1038B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10393] lea rdi, [r14+0x08]
  [0x10398] lea rsi, [0x000000000001039F]
  [0x1039F] sub rsi, r15
  [0x103A2] mov r8d, [r15+r8*1+0x94]
  [0x103AA] mov edx, [r15+r8*1+0x0C]
  [0x103AF] mov rcx, r10
  [0x103B2] add r9, r15
  [0x103B5] call r9
  [0x103B8] mov r9d, [r15+r10*1-0x04]
  [0x103BD] mov r9d, [r15+r9*1+0x38]
  [0x103C2] mov rdi, r10
  [0x103C5] add r9, r15
  [0x103C8] call r9
  [0x103CB] jmp 0x00000000000104A0
  [0x103D0] mov r9, r8
  [0x103D3] mov r9d, [r15+r9*1+0x74]
  [0x103D8] xor rcx, rcx
  [0x103DB] mov rdx, r14
  [0x103DE] cmp r9, rcx
  [0x103E1] jz 0x00000000000103EC
  [0x103E7] lea rdx, [r14+0x08]
  [0x103EC] mov r9, rdx
  [0x103EF] mov rcx, r14
  [0x103F2] cmp r9, rcx
  [0x103F5] jz 0x000000000001044F
  [0x103FB] mov r9, r8
  [0x103FE] mov r9d, [r15+r9*1+0x74]
  [0x10403] mov r9d, [r15+r9*1+0x04]
  [0x10408] mov rcx, r12
  [0x1040B] mov rdx, r14
  [0x1040E] cmp r9, rcx
  [0x10411] jl 0x000000000001041C
  [0x10417] lea rdx, [r14+0x08]
  [0x1041C] mov r9, rdx
  [0x1041F] mov rcx, r14
  [0x10422] cmp r9, rcx
  [0x10425] jz 0x000000000001044F
  [0x1042B] mov r9, r8
  [0x1042E] mov r9d, [r15+r9*1+0x74]
  [0x10433] mov r9d, [r15+r9*1+0x04]
  [0x10438] mov rcx, r11
  [0x1043B] mov rdx, r14
  [0x1043E] cmp r9, rcx
  [0x10441] jnl 0x000000000001044C
  [0x10447] lea rdx, [r14+0x08]
  [0x1044C] mov r9, rdx
  [0x1044F] mov rcx, r14
  [0x10452] cmp r9, rcx
  [0x10455] jz 0x000000000001049D
  [0x1045B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10463] lea rdi, [r14+0x08]
  [0x10468] lea rsi, [0x000000000001046F]
  [0x1046F] sub rsi, r15
  [0x10472] mov r8d, [r15+r8*1+0x74]
  [0x10477] mov edx, [r15+r8*1+0x04]
  [0x1047C] mov rcx, r10
  [0x1047F] add r9, r15
  [0x10482] call r9
  [0x10485] mov r9d, [r15+r10*1-0x04]
  [0x1048A] mov r9d, [r15+r9*1+0x38]
  [0x1048F] mov rdi, r10
  [0x10492] add r9, r15
  [0x10495] call r9
  [0x10498] jmp 0x00000000000104A0
  [0x1049D] mov r10, r14
  [0x104A0] jmp 0x00000000000104A8
  [0x104A5] mov r10, r14
  [0x104A8] mov r9, r14
  [0x104AB] cmp rbp, r9
  [0x104AE] jnz 0x0000000000010118
  [0x104B4] mov r9, r14
  [0x104B7] add rsp, 0x10
  [0x104BB] pop r12
  [0x104BD] pop r11
  [0x104BF] pop r10
  [0x104C1] pop rbp
  [0x104C2] pop rbx
  [0x104C3] ret


[(method birth! entity-actor)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] mov rbx, rdi
  [0x10007] mov ebp, [r15+rbx*1+0x34]
  [0x1000C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10014] mov rdi, rbp
  [0x10017] add r9, r15
  [0x1001A] call r9
  [0x1001D] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10025] mov r9, r14
  [0x10028] cmp rax, r9
  [0x1002B] jz 0x000000000001003B
  [0x10031] movsxd rdx, dword ptr [r15+rax*1+0x10]
  [0x10036] jmp 0x0000000000010040
  [0x1003B] mov edx, 0x4000
  [0x10040] mov r9d, [r15+rdi*1-0x04]
  [0x10045] mov r9d, [r15+r9*1+0x48]
  [0x1004A] mov rsi, rbp
  [0x1004D] add r9, r15
  [0x10050] call r9
  [0x10053] mov r12, rax
  [0x10056] mov r9, r14
  [0x10059] cmp r12, r9
  [0x1005C] jnz 0x0000000000010082
  [0x10062] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1006A] xor rdi, rdi
  [0x1006D] lea rsi, [0x0000000000010074]
  [0x10074] sub rsi, r15
  [0x10077] add r9, r15
  [0x1007A] call r9
  [0x1007D] jmp 0x0000000000010183
  [0x10082] mov [r12+r15*1-0x04], ebp
  [0x10087] mov r9, rbp
  [0x1008A] mov r8, r14
  [0x1008D] cmp r9, r8
  [0x10090] jz 0x00000000000100F3
  [0x10096] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1009E] mov esi, [r15+r14*1+0xBADBEEF]
  [0x100A6] mov rdx, r14
  [0x100A9] mov rcx, r14
  [0x100AC] xor r8, r8
  [0x100AF] mov rdi, rbp
  [0x100B2] add r9, r15
  [0x100B5] call r9
  [0x100B8] mov r9, rax
  [0x100BB] mov r8, r14
  [0x100BE] cmp r9, r8
  [0x100C1] jz 0x00000000000100F3
  [0x100C7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100CF] mov r8d, [r12+r15*1-0x04]
  [0x100D4] mov edi, [r15+r8*1+0x3C]
  [0x100D9] mov esi, [r15+r14*1+0xBADBEEF]
  [0x100E1] mov rdx, r14
  [0x100E4] mov rcx, r14
  [0x100E7] xor r8, r8
  [0x100EA] add r9, r15
  [0x100ED] call r9
  [0x100F0] mov r9, rax
  [0x100F3] mov r8, r14
  [0x100F6] cmp r9, r8
  [0x100F9] jz 0x000000000001011B
  [0x100FF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10107] mov rdi, r12
  [0x1010A] mov rsi, rbx
  [0x1010D] add r9, r15
  [0x10110] call r9
  [0x10113] mov rax, rbp
  [0x10116] jmp 0x0000000000010183
  [0x1011B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10123] mov rdi, r12
  [0x10126] mov rsi, rbx
  [0x10129] add r9, r15
  [0x1012C] call r9
  [0x1012F] mov r9, r14
  [0x10132] cmp rax, r9
  [0x10135] jnz 0x0000000000010180
  [0x1013B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10143] xor rdi, rdi
  [0x10146] lea rsi, [0x000000000001014D]
  [0x1014D] sub rsi, r15
  [0x10150] mov rdx, rbp
  [0x10153] mov rcx, rbx
  [0x10156] add r9, r15
  [0x10159] call r9
  [0x1015C] mov r9d, [r15+rbx*1+0x14]
  [0x10161] movzx rax, word ptr [r15+r9*1+0x38]
  [0x10167] mov r9d, 0x01
  [0x1016D] or rax, r9
  [0x10170] mov r9d, [r15+rbx*1+0x14]
  [0x10175] mov [r15+r9*1+0x38], ax
  [0x1017B] jmp 0x0000000000010183
  [0x10180] mov rax, r14
  [0x10183] mov rax, rbx
  [0x10186] pop r12
  [0x10188] pop rbp
  [0x10189] pop rbx
  [0x1018A] ret


[init-entity]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] mov rbx, rdi
  [0x1000B] mov rbp, rsi
  [0x1000E] mov r12d, [r15+r14*1+0xBADBEEF]
  [0x10016] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1001E] mov eax, [r15+r9*1+0x38]
  [0x10023] lea rsi, [r14+0xAFECAFE]
  [0x1002B] lea rdx, [r14+0xAFECAFE]
  [0x10033] movss xmm7, dword ptr [0x000000000001003B]
  [0x1003B] mov r8, r14
  [0x1003E] mov r9, r14
  [0x10041] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10049] mov rdi, rbp
  [0x1004C] movd ecx, xmm7
  [0x10050] movsxd rcx, ecx
  [0x10053] mov r11, rax
  [0x10056] add r11, r15
  [0x10059] call r11
  [0x1005C] mov ecx, 0x70004000
  [0x10061] mov r9d, [r15+rbx*1-0x04]
  [0x10066] mov r9d, [r15+r9*1+0x34]
  [0x1006B] mov rdi, rbx
  [0x1006E] mov rsi, r12
  [0x10071] mov rdx, rax
  [0x10074] add r9, r15
  [0x10077] call r9
  [0x1007A] mov [r15+rbx*1+0x30], ebp
  [0x1007F] mov r9d, [r15+rbp*1+0x14]
  [0x10084] mov [r15+r9*1+0x0C], ebx
  [0x10089] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10091] mov r8d, [r15+rbx*1-0x04]
  [0x10096] mov esi, [r15+r8*1+0x3C]
  [0x1009B] mov rdi, rbx
  [0x1009E] mov rdx, rbx
  [0x100A1] mov rcx, rbp
  [0x100A4] add r9, r15
  [0x100A7] call r9
  [0x100AA] pop r12
  [0x100AC] pop r11
  [0x100AE] pop r10
  [0x100B0] pop rbp
  [0x100B1] pop rbx
  [0x100B2] ret


[(method birth? entity-links)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] movzx r9, word ptr [r15+rdi*1+0x38]
  [0x10007] mov r8d, 0x05
  [0x1000D] and r9, r8
  [0x10010] xor r8, r8
  [0x10013] mov rax, r14
  [0x10016] cmp r9, r8
  [0x10019] jnz 0x0000000000010024
  [0x1001F] lea rax, [r14+0x08]
  [0x10024] mov r9, r14
  [0x10027] cmp rax, r9
  [0x1002A] jz 0x000000000001006E
  [0x10030] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10038] mov r8d, 0x20
  [0x1003E] add r8, rdi
  [0x10041] mov rdi, r8
  [0x10044] add r9, r15
  [0x10047] call r9
  [0x1004A] movd xmm7, eax
  [0x1004E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10056] movss xmm6, dword ptr [r15+r9*1+0x04]
  [0x1005D] mov rax, r14
  [0x10060] ucomiss xmm7, xmm6
  [0x10063] jnb 0x000000000001006E
  [0x10069] lea rax, [r14+0x08]
  [0x1006E] pop rbx
  [0x1006F] ret


[(method kill! entity-camera)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1000C] mov r9d, [r15+rdi*1-0x04]
  [0x10011] mov r9d, [r15+r9*1+0x5C]
  [0x10016] mov rsi, rbx
  [0x10019] add r9, r15
  [0x1001C] call r9
  [0x1001F] mov rax, rbx
  [0x10022] pop rbx
  [0x10023] ret


[(method birth! entity-camera)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push rbx
  [0x10003] mov rbx, rdi
  [0x10006] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1000E] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10016] mov edx, [r15+r14*1+0xBADBEEF]
  [0x1001E] mov r8, r14
  [0x10021] mov r9, r14
  [0x10024] mov ecx, [r15+rdi*1-0x04]
  [0x10029] mov eax, [r15+rcx*1+0x4C]
  [0x1002E] mov rcx, rbx
  [0x10031] mov rbp, rax
  [0x10034] add rbp, r15
  [0x10037] call rbp
  [0x10039] mov rax, rbx
  [0x1003C] pop rbx
  [0x1003D] pop rbp
  [0x1003E] pop rbx
  [0x1003F] ret


[process-drawable-from-entity!]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9d, [r15+rbx*1+0x04]
  [0x10009] mov r8d, 0x20
  [0x1000F] or r9, r8
  [0x10012] mov [r15+rbx*1+0x04], r9d
  [0x10017] mov r9d, [r15+rsi*1+0x14]
  [0x1001C] vmovaps xmm7, [r15+r9*1+0x20]
  [0x10023] mov r9d, [r15+rbx*1+0x6C]
  [0x10028] vmovaps [r15+r9*1+0x0C], xmm7
  [0x1002F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10037] mov edi, 0x1C
  [0x1003C] mov r8d, [r15+rbx*1+0x6C]
  [0x10041] add rdi, r8
  [0x10044] mov r8d, 0x3C
  [0x1004A] add r8, rsi
  [0x1004D] mov rsi, r8
  [0x10050] add r9, r15
  [0x10053] call r9
  [0x10056] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1005E] mov edi, 0x2C
  [0x10063] mov r8d, [r15+rbx*1+0x6C]
  [0x10068] add rdi, r8
  [0x1006B] add r9, r15
  [0x1006E] call r9
  [0x10071] pop rbx
  [0x10072] ret


[expand-vis-box-with-point]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] mov rbx, rsi
  [0x10007] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000F] mov eax, [r15+r9*1+0x34]
  [0x10014] lea rsi, [r14+0xAFECAFE]
  [0x1001C] lea rdx, [r14+0xAFECAFE]
  [0x10024] movss xmm7, dword ptr [0x000000000001002C]
  [0x1002C] mov r8, r14
  [0x1002F] mov r9, r14
  [0x10032] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x1003A] movd ecx, xmm7
  [0x1003E] movsxd rcx, ecx
  [0x10041] mov rbp, rax
  [0x10044] add rbp, r15
  [0x10047] call rbp
  [0x10049] mov r9, r14
  [0x1004C] cmp rax, r9
  [0x1004F] jz 0x00000000000100FE
  [0x10055] mov r9, rax
  [0x10058] mov r8d, 0x10
  [0x1005E] add r8, rax
  [0x10061] movss xmm7, dword ptr [r15+r9*1]
  [0x10067] movss xmm6, dword ptr [r15+rbx*1]
  [0x1006D] minss xmm7, xmm6
  [0x10071] movss [r15+r9*1], xmm7
  [0x10077] movss xmm7, dword ptr [r15+r9*1+0x04]
  [0x1007E] movss xmm6, dword ptr [r15+rbx*1+0x04]
  [0x10085] minss xmm7, xmm6
  [0x10089] movss [r15+r9*1+0x04], xmm7
  [0x10090] movss xmm7, dword ptr [r15+r9*1+0x08]
  [0x10097] movss xmm6, dword ptr [r15+rbx*1+0x08]
  [0x1009E] minss xmm7, xmm6
  [0x100A2] movss [r15+r9*1+0x08], xmm7
  [0x100A9] movss xmm7, dword ptr [r15+r8*1]
  [0x100AF] movss xmm6, dword ptr [r15+rbx*1]
  [0x100B5] maxss xmm7, xmm6
  [0x100B9] movss [r15+r8*1], xmm7
  [0x100BF] movss xmm7, dword ptr [r15+r8*1+0x04]
  [0x100C6] movss xmm6, dword ptr [r15+rbx*1+0x04]
  [0x100CD] maxss xmm7, xmm6
  [0x100D1] movss [r15+r8*1+0x04], xmm7
  [0x100D8] movss xmm7, dword ptr [r15+r8*1+0x08]
  [0x100DF] movss xmm6, dword ptr [r15+rbx*1+0x08]
  [0x100E6] maxss xmm7, xmm6
  [0x100EA] movss [r15+r8*1+0x08], xmm7
  [0x100F1] movd r9d, xmm7
  [0x100F6] movsxd r9, r9d
  [0x100F9] jmp 0x0000000000010101
  [0x100FE] mov r9, r14
  [0x10101] xor r9, r9
  [0x10104] pop r10
  [0x10106] pop rbp
  [0x10107] pop rbx
  [0x10108] ret


[top-level]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] lea r9, [r14+0x08]
  [0x10006] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1000E] lea r9, [r14+0x08]
  [0x10013] mov [r15+r14*1+0xBADBEEF], r9d
  [0x1001B] lea r9, [r14+0x08]
  [0x10020] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10028] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10030] mov esi, 0x08
  [0x10035] lea rdx, [0x000000000001003C]
  [0x1003C] sub rdx, r15
  [0x1003F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10047] add r9, r15
  [0x1004A] call r9
  [0x1004D] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10055] mov esi, 0x08
  [0x1005A] lea rdx, [0x0000000000010061]
  [0x10061] sub rdx, r15
  [0x10064] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1006C] add r9, r15
  [0x1006F] call r9
  [0x10072] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1007A] mov esi, 0x02
  [0x1007F] lea rdx, [0x0000000000010086]
  [0x10086] sub rdx, r15
  [0x10089] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10091] add r9, r15
  [0x10094] call r9
  [0x10097] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1009F] mov esi, 0x02
  [0x100A4] lea rdx, [0x00000000000100AB]
  [0x100AB] sub rdx, r15
  [0x100AE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100B6] add r9, r15
  [0x100B9] call r9
  [0x100BC] mov edi, [r15+r14*1+0xBADBEEF]
  [0x100C4] mov esi, 0x16
  [0x100C9] lea rdx, [0x00000000000100D0]
  [0x100D0] sub rdx, r15
  [0x100D3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100DB] add r9, r15
  [0x100DE] call r9
  [0x100E1] mov edi, [r15+r14*1+0xBADBEEF]
  [0x100E9] mov esi, 0x17
  [0x100EE] lea rdx, [0x00000000000100F5]
  [0x100F5] sub rdx, r15
  [0x100F8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10100] add r9, r15
  [0x10103] call r9
  [0x10106] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1010E] mov esi, 0x02
  [0x10113] lea rdx, [0x000000000001011A]
  [0x1011A] sub rdx, r15
  [0x1011D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10125] add r9, r15
  [0x10128] call r9
  [0x1012B] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10133] mov esi, 0x1A
  [0x10138] lea rdx, [0x000000000001013F]
  [0x1013F] sub rdx, r15
  [0x10142] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1014A] add r9, r15
  [0x1014D] call r9
  [0x10150] lea r9, [0x0000000000010157]
  [0x10157] sub r9, r15
  [0x1015A] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10162] lea r9, [0x0000000000010169]
  [0x10169] sub r9, r15
  [0x1016C] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10174] lea r9, [0x000000000001017B]
  [0x1017B] sub r9, r15
  [0x1017E] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10186] lea r9, [0x000000000001018D]
  [0x1018D] sub r9, r15
  [0x10190] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10198] lea r9, [0x000000000001019F]
  [0x1019F] sub r9, r15
  [0x101A2] mov [r15+r14*1+0xBADBEEF], r9d
  [0x101AA] lea r9, [0x00000000000101B1]
  [0x101B1] sub r9, r15
  [0x101B4] mov [r15+r14*1+0xBADBEEF], r9d
  [0x101BC] lea r9, [0x00000000000101C3]
  [0x101C3] sub r9, r15
  [0x101C6] mov [r15+r14*1+0xBADBEEF], r9d
  [0x101CE] lea r9, [0x00000000000101D5]
  [0x101D5] sub r9, r15
  [0x101D8] mov [r15+r14*1+0xBADBEEF], r9d
  [0x101E0] mov edi, [r15+r14*1+0xBADBEEF]
  [0x101E8] mov esi, 0x03
  [0x101ED] lea rdx, [0x00000000000101F4]
  [0x101F4] sub rdx, r15
  [0x101F7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101FF] add r9, r15
  [0x10202] call r9
  [0x10205] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1020D] mov esi, 0x03
  [0x10212] lea rdx, [0x0000000000010219]
  [0x10219] sub rdx, r15
  [0x1021C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10224] add r9, r15
  [0x10227] call r9
  [0x1022A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10232] mov r8, r14
  [0x10235] cmp r9, r8
  [0x10238] jz 0x0000000000010255
  [0x1023E] lea r9, [0x0000000000010245]
  [0x10245] sub r9, r15
  [0x10248] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10250] jmp 0x0000000000010265
  [0x10255] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1025D] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10265] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1026D] mov esi, 0x02
  [0x10272] lea rdx, [0x0000000000010279]
  [0x10279] sub rdx, r15
  [0x1027C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10284] add r9, r15
  [0x10287] call r9
  [0x1028A] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10292] mov esi, 0x1D
  [0x10297] lea rdx, [0x000000000001029E]
  [0x1029E] sub rdx, r15
  [0x102A1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102A9] add r9, r15
  [0x102AC] call r9
  [0x102AF] mov edi, [r15+r14*1+0xBADBEEF]
  [0x102B7] mov esi, 0x0D
  [0x102BC] lea rdx, [0x00000000000102C3]
  [0x102C3] sub rdx, r15
  [0x102C6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102CE] add r9, r15
  [0x102D1] call r9
  [0x102D4] mov edi, [r15+r14*1+0xBADBEEF]
  [0x102DC] mov esi, 0x18
  [0x102E1] lea rdx, [0x00000000000102E8]
  [0x102E8] sub rdx, r15
  [0x102EB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102F3] add r9, r15
  [0x102F6] call r9
  [0x102F9] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10301] mov esi, 0x19
  [0x10306] lea rdx, [0x000000000001030D]
  [0x1030D] sub rdx, r15
  [0x10310] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10318] add r9, r15
  [0x1031B] call r9
  [0x1031E] lea r9, [0x0000000000010325]
  [0x10325] sub r9, r15
  [0x10328] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10330] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10338] mov esi, 0x16
  [0x1033D] lea rdx, [0x0000000000010344]
  [0x10344] sub rdx, r15
  [0x10347] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1034F] add r9, r15
  [0x10352] call r9
  [0x10355] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1035D] mov esi, 0x17
  [0x10362] lea rdx, [0x0000000000010369]
  [0x10369] sub rdx, r15
  [0x1036C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10374] add r9, r15
  [0x10377] call r9
  [0x1037A] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10382] mov esi, 0x18
  [0x10387] lea rdx, [0x000000000001038E]
  [0x1038E] sub rdx, r15
  [0x10391] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10399] add r9, r15
  [0x1039C] call r9
  [0x1039F] lea r9, [0x00000000000103A6]
  [0x103A6] sub r9, r15
  [0x103A9] mov [r15+r14*1+0xBADBEEF], r9d
  [0x103B1] mov edi, [r15+r14*1+0xBADBEEF]
  [0x103B9] mov esi, 0x0E
  [0x103BE] lea rdx, [0x00000000000103C5]
  [0x103C5] sub rdx, r15
  [0x103C8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103D0] add r9, r15
  [0x103D3] call r9
  [0x103D6] mov edi, [r15+r14*1+0xBADBEEF]
  [0x103DE] mov esi, 0x16
  [0x103E3] lea rdx, [0x00000000000103EA]
  [0x103EA] sub rdx, r15
  [0x103ED] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103F5] add r9, r15
  [0x103F8] call r9
  [0x103FB] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10403] mov esi, 0x17
  [0x10408] lea rdx, [0x000000000001040F]
  [0x1040F] sub rdx, r15
  [0x10412] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1041A] add r9, r15
  [0x1041D] call r9
  [0x10420] lea r9, [0x0000000000010427]
  [0x10427] sub r9, r15
  [0x1042A] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10432] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1043A] mov esi, 0x16
  [0x1043F] lea rdx, [0x0000000000010446]
  [0x10446] sub rdx, r15
  [0x10449] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10451] add r9, r15
  [0x10454] call r9
  [0x10457] lea r9, [0x000000000001045E]
  [0x1045E] sub r9, r15
  [0x10461] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10469] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10471] mov esi, 0x17
  [0x10476] lea rdx, [0x000000000001047D]
  [0x1047D] sub rdx, r15
  [0x10480] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10488] add r9, r15
  [0x1048B] call r9
  [0x1048E] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10496] mov esi, 0x12
  [0x1049B] lea rdx, [0x00000000000104A2]
  [0x104A2] sub rdx, r15
  [0x104A5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104AD] add r9, r15
  [0x104B0] call r9
  [0x104B3] mov edi, [r15+r14*1+0xBADBEEF]
  [0x104BB] mov esi, 0x13
  [0x104C0] lea rdx, [0x00000000000104C7]
  [0x104C7] sub rdx, r15
  [0x104CA] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104D2] add r9, r15
  [0x104D5] call r9
  [0x104D8] lea r9, [0x00000000000104DF]
  [0x104DF] sub r9, r15
  [0x104E2] mov [r15+r14*1+0xBADBEEF], r9d
  [0x104EA] mov edi, [r15+r14*1+0xBADBEEF]
  [0x104F2] mov esi, 0x09
  [0x104F7] lea rdx, [0x00000000000104FE]
  [0x104FE] sub rdx, r15
  [0x10501] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10509] add r9, r15
  [0x1050C] call r9
  [0x1050F] lea r9, [0x0000000000010516]
  [0x10516] sub r9, r15
  [0x10519] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10521] lea r9, [0x0000000000010528]
  [0x10528] sub r9, r15
  [0x1052B] mov [r15+r14*1+0xBADBEEF], r9d
  [0x10533] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1053B] mov esi, 0x0C
  [0x10540] lea rdx, [0x0000000000010547]
  [0x10547] sub rdx, r15
  [0x1054A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10552] add r9, r15
  [0x10555] call r9
  [0x10558] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10560] mov esi, 0x09
  [0x10565] lea rdx, [0x000000000001056C]
  [0x1056C] sub rdx, r15
  [0x1056F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10577] add r9, r15
  [0x1057A] call r9
  [0x1057D] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10585] mov esi, 0x0F
  [0x1058A] lea rdx, [0x0000000000010591]
  [0x10591] sub rdx, r15
  [0x10594] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1059C] add r9, r15
  [0x1059F] call r9
  [0x105A2] lea r9, [0x00000000000105A9]
  [0x105A9] sub r9, r15
  [0x105AC] mov [r15+r14*1+0xBADBEEF], r9d
  [0x105B4] lea r9, [0x00000000000105BB]
  [0x105BB] sub r9, r15
  [0x105BE] mov [r15+r14*1+0xBADBEEF], r9d
  [0x105C6] lea r9, [0x00000000000105CD]
  [0x105CD] sub r9, r15
  [0x105D0] mov [r15+r14*1+0xBADBEEF], r9d
  [0x105D8] mov edi, [r15+r14*1+0xBADBEEF]
  [0x105E0] mov esi, 0x1E
  [0x105E5] lea rdx, [0x00000000000105EC]
  [0x105EC] sub rdx, r15
  [0x105EF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x105F7] add r9, r15
  [0x105FA] call r9
  [0x105FD] lea rax, [0x0000000000010604]
  [0x10604] sub rax, r15
  [0x10607] mov [r15+r14*1+0xBADBEEF], eax
  [0x1060F] pop rbx
  [0x10610] ret


[(method print-volume-sizes level-group)]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] movdqa [rsp], xmm8
  [0x1000A] push rbx
  [0x1000B] push rbp
  [0x1000C] push r10
  [0x1000E] push r11
  [0x10010] push r12
  [0x10012] sub rsp, 0x58
  [0x10016] mov [rsp+0x48], rdi
  [0x1001E] xor rbp, rbp
  [0x10021] jmp 0x000000000001047B
  [0x10026] mov r9d, 0xA30
  [0x1002C] imul r9d, ebp
  [0x10030] movsxd r9, r9d
  [0x10033] mov r8d, 0x60
  [0x10039] mov rcx, [rsp+0x48]
  [0x10041] add r8, rcx
  [0x10044] add r9, r8
  [0x10047] mov r8d, [r15+r9*1+0x10]
  [0x1004C] lea rcx, [r14+0xAFECAFE]
  [0x10054] cmp r8, rcx
  [0x10057] jnz 0x000000000001046F
  [0x1005D] mov r9d, [r15+r9*1+0x2C]
  [0x10062] mov r9d, [r15+r9*1+0x78]
  [0x10067] mov r12d, [r15+r9*1+0x118]
  [0x1006F] xor r8, r8
  [0x10072] mov r9, r8
  [0x10075] mov [rsp], r9
  [0x1007D] jmp 0x0000000000010452
  [0x10082] mov r9, [rsp]
  [0x1008A] mov r8, r9
  [0x1008D] shl r8, 0x06
  [0x10091] mov r9d, 0x0C
  [0x10097] add r9, r12
  [0x1009A] add r8, r9
  [0x1009D] mov r11d, [r15+r8*1+0x08]
  [0x100A2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100AA] mov eax, [r15+r9*1+0x34]
  [0x100AF] lea rsi, [r14+0xAFECAFE]
  [0x100B7] lea rdx, [r14+0xAFECAFE]
  [0x100BF] movss xmm7, dword ptr [0x00000000000100C7]
  [0x100C7] mov r8, r14
  [0x100CA] mov r9, r14
  [0x100CD] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x100D5] mov rdi, r11
  [0x100D8] movd ecx, xmm7
  [0x100DC] movsxd rcx, ecx
  [0x100DF] mov [rsp+0x40], rax
  [0x100E7] mov rbx, [rsp+0x40]
  [0x100EF] add rbx, r15
  [0x100F2] call rbx
  [0x100F4] mov [rsp+0x40], rbx
  [0x100FC] mov r9, rax
  [0x100FF] mov [rsp+0x20], r9
  [0x10107] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1010F] mov eax, [r15+r9*1+0x40]
  [0x10114] lea rsi, [r14+0xAFECAFE]
  [0x1011C] lea rdx, [r14+0xAFECAFE]
  [0x10124] movss xmm7, dword ptr [0x000000000001012C]
  [0x1012C] movss xmm6, dword ptr [0x0000000000010134]
  [0x10134] mov r9, r14
  [0x10137] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x1013F] mov rdi, r11
  [0x10142] movd ecx, xmm7
  [0x10146] movsxd rcx, ecx
  [0x10149] movd r8d, xmm6
  [0x1014E] movsxd r8, r8d
  [0x10151] mov rbx, rax
  [0x10154] add rbx, r15
  [0x10157] call rbx
  [0x10159] movd xmm8, eax
  [0x1015E] mov r8d, 0x20
  [0x10164] mov r9d, [r15+r11*1+0x14]
  [0x10169] add r8, r9
  [0x1016C] mov r9, r8
  [0x1016F] mov [rsp+0x08], r9
  [0x10177] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1017F] mov edi, [r15+r11*1-0x04]
  [0x10184] mov esi, [r15+r14*1+0xBADBEEF]
  [0x1018C] add r9, r15
  [0x1018F] call r9
  [0x10192] mov r9, r14
  [0x10195] cmp rax, r9
  [0x10198] jz 0x00000000000101AB
  [0x1019E] mov r9, r11
  [0x101A1] mov r10d, [r15+r9*1+0x34]
  [0x101A6] jmp 0x00000000000101AE
  [0x101AB] mov r10, r14
  [0x101AE] mov r9, [rsp+0x20]
  [0x101B6] mov r8, r9
  [0x101B9] mov ecx, 0x10
  [0x101BE] mov r9, [rsp+0x20]
  [0x101C6] mov rdx, r9
  [0x101C9] add rcx, rdx
  [0x101CC] mov r9, r8
  [0x101CF] mov [rsp+0x18], r9
  [0x101D7] mov r9, rcx
  [0x101DA] mov [rsp+0x10], r9
  [0x101E2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101EA] mov esi, [r15+r14*1+0xBADBEEF]
  [0x101F2] mov rdi, r10
  [0x101F5] add r9, r15
  [0x101F8] call r9
  [0x101FB] mov r9, r14
  [0x101FE] cmp rax, r9
  [0x10201] jnz 0x000000000001026A
  [0x10207] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1020F] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10217] mov rdi, r10
  [0x1021A] add r9, r15
  [0x1021D] call r9
  [0x10220] mov r9, r14
  [0x10223] cmp rax, r9
  [0x10226] jnz 0x000000000001026A
  [0x1022C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10234] mov esi, [r15+r14*1+0xBADBEEF]
  [0x1023C] mov rdi, r10
  [0x1023F] add r9, r15
  [0x10242] call r9
  [0x10245] mov r9, r14
  [0x10248] cmp rax, r9
  [0x1024B] jnz 0x000000000001026A
  [0x10251] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10259] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10261] mov rdi, r10
  [0x10264] add r9, r15
  [0x10267] call r9
  [0x1026A] mov r9, r14
  [0x1026D] cmp rax, r9
  [0x10270] jnz 0x0000000000010430
  [0x10276] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1027E] mov [rsp+0x28], r9
  [0x10286] lea r9, [r14+0x08]
  [0x1028B] mov [rsp+0x30], r9
  [0x10293] lea r9, [0x000000000001029A]
  [0x1029A] sub r9, r15
  [0x1029D] mov [rsp+0x38], r9
  [0x102A5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x102AD] mov eax, [r15+r9*1+0x38]
  [0x102B2] lea rsi, [r14+0xAFECAFE]
  [0x102BA] lea rdx, [r14+0xAFECAFE]
  [0x102C2] movss xmm7, dword ptr [0x00000000000102CA]
  [0x102CA] mov r8, r14
  [0x102CD] mov r9, r14
  [0x102D0] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x102D8] mov rdi, r11
  [0x102DB] movd ecx, xmm7
  [0x102DF] movsxd rcx, ecx
  [0x102E2] mov rbx, rax
  [0x102E5] add rbx, r15
  [0x102E8] call rbx
  [0x102EA] mov rdi, [rsp+0x30]
  [0x102F2] mov rsi, [rsp+0x38]
  [0x102FA] mov rdx, rax
  [0x102FD] movd ecx, xmm8
  [0x10302] movsxd rcx, ecx
  [0x10305] mov r9, [rsp+0x28]
  [0x1030D] mov r8, r9
  [0x10310] add r8, r15
  [0x10313] call r8
  [0x10316] mov eax, [r15+r14*1+0xBADBEEF]
  [0x1031E] lea rdi, [r14+0x08]
  [0x10323] lea rsi, [0x000000000001032A]
  [0x1032A] sub rsi, r15
  [0x1032D] mov r9, [rsp+0x18]
  [0x10335] movss xmm7, dword ptr [r15+r9*1]
  [0x1033B] mov r9, [rsp+0x08]
  [0x10343] movss xmm6, dword ptr [r15+r9*1]
  [0x10349] subss xmm7, xmm6
  [0x1034D] mov r9, [rsp+0x18]
  [0x10355] movss xmm6, dword ptr [r15+r9*1+0x04]
  [0x1035C] mov r9, [rsp+0x08]
  [0x10364] movss xmm5, dword ptr [r15+r9*1+0x04]
  [0x1036B] subss xmm6, xmm5
  [0x1036F] mov r9, [rsp+0x18]
  [0x10377] movss xmm5, dword ptr [r15+r9*1+0x08]
  [0x1037E] mov r9, [rsp+0x08]
  [0x10386] movss xmm4, dword ptr [r15+r9*1+0x08]
  [0x1038D] subss xmm5, xmm4
  [0x10391] mov r9, [rsp+0x10]
  [0x10399] movss xmm4, dword ptr [r15+r9*1]
  [0x1039F] mov r9, [rsp+0x08]
  [0x103A7] movss xmm3, dword ptr [r15+r9*1]
  [0x103AD] subss xmm4, xmm3
  [0x103B1] mov r9, [rsp+0x10]
  [0x103B9] movss xmm3, dword ptr [r15+r9*1+0x04]
  [0x103C0] mov r9, [rsp+0x08]
  [0x103C8] movss xmm2, dword ptr [r15+r9*1+0x04]
  [0x103CF] subss xmm3, xmm2
  [0x103D3] mov r9, [rsp+0x10]
  [0x103DB] movss xmm2, dword ptr [r15+r9*1+0x08]
  [0x103E2] mov r9, [rsp+0x08]
  [0x103EA] movss xmm1, dword ptr [r15+r9*1+0x08]
  [0x103F1] subss xmm2, xmm1
  [0x103F5] movd edx, xmm7
  [0x103F9] movsxd rdx, edx
  [0x103FC] movd ecx, xmm6
  [0x10400] movsxd rcx, ecx
  [0x10403] movd r8d, xmm5
  [0x10408] movsxd r8, r8d
  [0x1040B] movd r9d, xmm4
  [0x10410] movsxd r9, r9d
  [0x10413] movd r10d, xmm3
  [0x10418] movsxd r10, r10d
  [0x1041B] movd r11d, xmm2
  [0x10420] movsxd r11, r11d
  [0x10423] mov rbx, rax
  [0x10426] add rbx, r15
  [0x10429] call rbx
  [0x1042B] jmp 0x0000000000010433
  [0x10430] mov rax, r14
  [0x10433] mov r9, [rsp]
  [0x1043B] mov r8, r9
  [0x1043E] mov r9d, 0x01
  [0x10444] add r8, r9
  [0x10447] mov r9, r8
  [0x1044A] mov [rsp], r9
  [0x10452] movsxd r8, dword ptr [r12+r15*1]
  [0x10456] mov r9, [rsp]
  [0x1045E] cmp r9, r8
  [0x10461] jl 0x0000000000010082
  [0x10467] mov r9, r14
  [0x1046A] jmp 0x0000000000010472
  [0x1046F] mov r9, r14
  [0x10472] mov r9d, 0x01
  [0x10478] add rbp, r9
  [0x1047B] mov r9, [rsp+0x48]
  [0x10483] movsxd r8, dword ptr [r15+r9*1]
  [0x10487] cmp rbp, r8
  [0x1048A] jl 0x0000000000010026
  [0x10490] mov r9, r14
  [0x10493] add rsp, 0x58
  [0x10497] pop r12
  [0x10499] pop r11
  [0x1049B] pop r10
  [0x1049D] pop rbp
  [0x1049E] pop rbx
  [0x1049F] movdqa xmm8, [rsp]
  [0x104A5] add rsp, 0x18
  [0x104A9] ret


[(method update-vis-volumes-from-nav-mesh level-group)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x40
  [0x1000C] mov [rsp+0x30], rdi
  [0x10014] xor rbp, rbp
  [0x10017] jmp 0x0000000000010334
  [0x1001C] mov r9d, 0xA30
  [0x10022] imul r9d, ebp
  [0x10026] movsxd r9, r9d
  [0x10029] mov r8d, 0x60
  [0x1002F] mov rcx, [rsp+0x30]
  [0x10037] add r8, rcx
  [0x1003A] add r9, r8
  [0x1003D] mov r8d, [r15+r9*1+0x10]
  [0x10042] lea rcx, [r14+0xAFECAFE]
  [0x1004A] cmp r8, rcx
  [0x1004D] jnz 0x0000000000010328
  [0x10053] mov r9d, [r15+r9*1+0x2C]
  [0x10058] mov r9d, [r15+r9*1+0x78]
  [0x1005D] mov r12d, [r15+r9*1+0x118]
  [0x10065] xor r11, r11
  [0x10068] jmp 0x0000000000010313
  [0x1006D] mov r9, r11
  [0x10070] shl r9, 0x06
  [0x10074] mov r8d, 0x0C
  [0x1007A] add r8, r12
  [0x1007D] add r9, r8
  [0x10080] mov r8d, [r15+r9*1+0x08]
  [0x10085] mov r9, r8
  [0x10088] mov [rsp+0x18], r9
  [0x10090] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10098] mov eax, [r15+r9*1+0x34]
  [0x1009D] lea rsi, [r14+0xAFECAFE]
  [0x100A5] lea rdx, [r14+0xAFECAFE]
  [0x100AD] movss xmm7, dword ptr [0x00000000000100B5]
  [0x100B5] mov r8, r14
  [0x100B8] mov r9, r14
  [0x100BB] mov [rsp+0x20], r9
  [0x100C3] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x100CB] mov r9, [rsp+0x18]
  [0x100D3] mov rdi, r9
  [0x100D6] movd ecx, xmm7
  [0x100DA] movsxd rcx, ecx
  [0x100DD] mov r9, [rsp+0x20]
  [0x100E5] mov [rsp+0x28], rax
  [0x100ED] mov rbx, [rsp+0x28]
  [0x100F5] add rbx, r15
  [0x100F8] call rbx
  [0x100FA] mov [rsp+0x28], rbx
  [0x10102] mov r8, rax
  [0x10105] mov r9, r8
  [0x10108] mov [rsp], r9
  [0x10110] mov r10d, 0x10
  [0x10116] add r10, rax
  [0x10119] mov r8d, 0x20
  [0x1011F] mov r9, [rsp+0x18]
  [0x10127] mov ecx, [r15+r9*1+0x14]
  [0x1012C] add r8, rcx
  [0x1012F] mov r9, r8
  [0x10132] mov [rsp+0x08], r9
  [0x1013A] mov r8, [rsp+0x18]
  [0x10142] mov r9, r8
  [0x10145] mov [rsp+0x10], r9
  [0x1014D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10155] lea rsi, [r14+0xAFECAFE]
  [0x1015D] xor rdx, rdx
  [0x10160] mov rdi, [rsp+0x18]
  [0x10168] add r9, r15
  [0x1016B] call r9
  [0x1016E] mov r9, r14
  [0x10171] cmp rax, r9
  [0x10174] jz 0x0000000000010198
  [0x1017A] mov r9, rax
  [0x1017D] mov [rsp+0x10], r9
  [0x10185] mov r9, [rsp+0x10]
  [0x1018D] mov r8, r9
  [0x10190] mov r9, r8
  [0x10193] jmp 0x000000000001019B
  [0x10198] mov r9, r14
  [0x1019B] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x101A3] mov r9, [rsp+0x10]
  [0x101AB] mov edi, [r15+r9*1-0x04]
  [0x101B0] mov esi, [r15+r14*1+0xBADBEEF]
  [0x101B8] add r8, r15
  [0x101BB] call r8
  [0x101BE] mov r9, r14
  [0x101C1] cmp rax, r9
  [0x101C4] jz 0x00000000000101EE
  [0x101CA] mov r9, [rsp+0x10]
  [0x101D2] mov r8, r9
  [0x101D5] mov r9d, [r15+r8*1+0x30]
  [0x101DA] xor r8, r8
  [0x101DD] mov rax, r14
  [0x101E0] cmp r9, r8
  [0x101E3] jz 0x00000000000101EE
  [0x101E9] lea rax, [r14+0x08]
  [0x101EE] mov r9, r14
  [0x101F1] cmp rax, r9
  [0x101F4] jz 0x000000000001022D
  [0x101FA] mov r9, [rsp+0x10]
  [0x10202] mov r8, r9
  [0x10205] mov edi, [r15+r8*1+0x30]
  [0x1020A] mov r9d, [r15+rdi*1-0x04]
  [0x1020F] mov r8d, [r15+r9*1+0x5C]
  [0x10214] mov r9, [rsp]
  [0x1021C] mov rsi, r9
  [0x1021F] mov rdx, r10
  [0x10222] add r8, r15
  [0x10225] call r8
  [0x10228] jmp 0x0000000000010262
  [0x1022D] mov r9, [rsp+0x08]
  [0x10235] vmovaps xmm7, [r15+r9*1]
  [0x1023B] mov r9, [rsp]
  [0x10243] vmovaps [r15+r9*1], xmm7
  [0x10249] mov r9, [rsp+0x08]
  [0x10251] vmovaps xmm7, [r15+r9*1]
  [0x10257] vmovaps [r15+r10*1], xmm7
  [0x1025D] movq r9, xmm7
  [0x10262] movss xmm7, dword ptr [0x000000000001026A]
  [0x1026A] movss xmm6, dword ptr [0x0000000000010272]
  [0x10272] mov r9, [rsp]
  [0x1027A] movss xmm5, dword ptr [r15+r9*1]
  [0x10280] addss xmm5, xmm7
  [0x10284] mov r9, [rsp]
  [0x1028C] movss [r15+r9*1], xmm5
  [0x10292] mov r9, [rsp]
  [0x1029A] movss xmm5, dword ptr [r15+r9*1+0x04]
  [0x102A1] addss xmm5, xmm7
  [0x102A5] mov r9, [rsp]
  [0x102AD] movss [r15+r9*1+0x04], xmm5
  [0x102B4] mov r9, [rsp]
  [0x102BC] movss xmm5, dword ptr [r15+r9*1+0x08]
  [0x102C3] addss xmm5, xmm7
  [0x102C7] mov r9, [rsp]
  [0x102CF] movss [r15+r9*1+0x08], xmm5
  [0x102D6] movss xmm7, dword ptr [r15+r10*1]
  [0x102DC] addss xmm7, xmm6
  [0x102E0] movss [r15+r10*1], xmm7
  [0x102E6] movss xmm7, dword ptr [r15+r10*1+0x04]
  [0x102ED] addss xmm7, xmm6
  [0x102F1] movss [r15+r10*1+0x04], xmm7
  [0x102F8] movss xmm7, dword ptr [r15+r10*1+0x08]
  [0x102FF] addss xmm7, xmm6
  [0x10303] movss [r15+r10*1+0x08], xmm7
  [0x1030A] mov r9d, 0x01
  [0x10310] add r11, r9
  [0x10313] movsxd r9, dword ptr [r12+r15*1]
  [0x10317] cmp r11, r9
  [0x1031A] jl 0x000000000001006D
  [0x10320] mov r9, r14
  [0x10323] jmp 0x000000000001032B
  [0x10328] mov r9, r14
  [0x1032B] mov r9d, 0x01
  [0x10331] add rbp, r9
  [0x10334] mov r9, [rsp+0x30]
  [0x1033C] movsxd r8, dword ptr [r15+r9*1]
  [0x10340] cmp rbp, r8
  [0x10343] jl 0x000000000001001C
  [0x10349] mov r9, r14
  [0x1034C] add rsp, 0x40
  [0x10350] pop r12
  [0x10352] pop r11
  [0x10354] pop r10
  [0x10356] pop rbp
  [0x10357] pop rbx
  [0x10358] ret


[(method update-vis-volumes level-group)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x60
  [0x1000C] mov [rsp+0x50], rdi
  [0x10014] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1001C] xor rdi, rdi
  [0x1001F] lea rsi, [0x0000000000010026]
  [0x10026] sub rsi, r15
  [0x10029] add r9, r15
  [0x1002C] call r9
  [0x1002F] xor r11, r11
  [0x10032] jmp 0x000000000001036B
  [0x10037] mov r9d, 0xA30
  [0x1003D] imul r9d, r11d
  [0x10041] movsxd r9, r9d
  [0x10044] mov r8d, 0x60
  [0x1004A] mov rcx, [rsp+0x50]
  [0x10052] add r8, rcx
  [0x10055] add r9, r8
  [0x10058] mov r8d, [r15+r9*1+0x10]
  [0x1005D] lea rcx, [r14+0xAFECAFE]
  [0x10065] cmp r8, rcx
  [0x10068] jnz 0x000000000001035F
  [0x1006E] mov r9d, [r15+r9*1+0x2C]
  [0x10073] mov r9d, [r15+r9*1+0x78]
  [0x10078] mov r8d, [r15+r9*1+0x118]
  [0x10080] mov r9, r8
  [0x10083] mov [rsp], r9
  [0x1008B] xor r8, r8
  [0x1008E] mov r9, r8
  [0x10091] mov [rsp+0x08], r9
  [0x10099] jmp 0x000000000001033A
  [0x1009E] mov r9, [rsp+0x08]
  [0x100A6] mov r8, r9
  [0x100A9] shl r8, 0x06
  [0x100AD] mov ecx, 0x0C
  [0x100B2] mov r9, [rsp]
  [0x100BA] add rcx, r9
  [0x100BD] add r8, rcx
  [0x100C0] mov r8d, [r15+r8*1+0x08]
  [0x100C5] mov r9, r8
  [0x100C8] mov [rsp+0x20], r9
  [0x100D0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D8] mov eax, [r15+r9*1+0x34]
  [0x100DD] lea rsi, [r14+0xAFECAFE]
  [0x100E5] lea rdx, [r14+0xAFECAFE]
  [0x100ED] movss xmm7, dword ptr [0x00000000000100F5]
  [0x100F5] mov r8, r14
  [0x100F8] mov r9, r14
  [0x100FB] mov [rsp+0x40], r9
  [0x10103] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x1010B] mov r9, [rsp+0x20]
  [0x10113] mov rdi, r9
  [0x10116] movd ecx, xmm7
  [0x1011A] movsxd rcx, ecx
  [0x1011D] mov r9, [rsp+0x40]
  [0x10125] mov [rsp+0x48], rax
  [0x1012D] mov r12, [rsp+0x48]
  [0x10135] add r12, r15
  [0x10138] call r12
  [0x1013B] mov [rsp+0x48], r12
  [0x10143] mov r10, rax
  [0x10146] mov r8d, 0x10
  [0x1014C] add r8, rax
  [0x1014F] mov r9, r8
  [0x10152] mov [rsp+0x10], r9
  [0x1015A] mov r9, [rsp+0x20]
  [0x10162] mov r8d, [r15+r9*1+0x14]
  [0x10167] mov r8d, [r15+r8*1+0x0C]
  [0x1016C] mov r9, r8
  [0x1016F] mov [rsp+0x30], r9
  [0x10177] xor r8, r8
  [0x1017A] mov rcx, r14
  [0x1017D] mov r9, [rsp+0x30]
  [0x10185] cmp r9, r8
  [0x10188] jz 0x0000000000010193
  [0x1018E] lea rcx, [r14+0x08]
  [0x10193] mov r9, rcx
  [0x10196] mov r8, r14
  [0x10199] cmp r9, r8
  [0x1019C] jz 0x00000000000101C8
  [0x101A2] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x101AA] mov r9, [rsp+0x30]
  [0x101B2] mov edi, [r15+r9*1-0x04]
  [0x101B7] mov esi, [r15+r14*1+0xBADBEEF]
  [0x101BF] add r8, r15
  [0x101C2] call r8
  [0x101C5] mov r9, rax
  [0x101C8] mov r8, r14
  [0x101CB] cmp r9, r8
  [0x101CE] jz 0x00000000000101E4
  [0x101D4] mov rbp, rbx
  [0x101D7] mov rbp, [rsp+0x30]
  [0x101DF] jmp 0x00000000000101E7
  [0x101E4] mov rbx, r14
  [0x101E7] mov r9, r14
  [0x101EA] cmp rbp, r9
  [0x101ED] jz 0x0000000000010318
  [0x101F3] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x101FB] mov rdi, rbp
  [0x101FE] mov rsi, r10
  [0x10201] mov r9, [rsp+0x10]
  [0x10209] mov rdx, r9
  [0x1020C] add r8, r15
  [0x1020F] call r8
  [0x10212] mov r8d, [r15+rbp*1+0x10]
  [0x10217] mov r9, r8
  [0x1021A] mov [rsp+0x18], r9
  [0x10222] jmp 0x00000000000102FC
  [0x10227] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1022F] mov r9, [rsp+0x18]
  [0x10237] mov ecx, [r15+r9*1]
  [0x1023B] mov r9, r8
  [0x1023E] mov [rsp+0x28], r9
  [0x10246] mov r9, rcx
  [0x10249] mov [rsp+0x38], r9
  [0x10251] xor r8, r8
  [0x10254] mov rcx, r14
  [0x10257] mov r9, [rsp+0x38]
  [0x1025F] cmp r9, r8
  [0x10262] jz 0x000000000001026D
  [0x10268] lea rcx, [r14+0x08]
  [0x1026D] mov r9, rcx
  [0x10270] mov r8, r14
  [0x10273] cmp r9, r8
  [0x10276] jz 0x00000000000102A2
  [0x1027C] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10284] mov r9, [rsp+0x38]
  [0x1028C] mov edi, [r15+r9*1-0x04]
  [0x10291] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10299] add r8, r15
  [0x1029C] call r8
  [0x1029F] mov r9, rax
  [0x102A2] mov r8, r14
  [0x102A5] cmp r9, r8
  [0x102A8] jz 0x00000000000102BE
  [0x102AE] mov r9, [rsp+0x38]
  [0x102B6] mov rdi, r9
  [0x102B9] jmp 0x00000000000102C1
  [0x102BE] mov rdi, r14
  [0x102C1] mov rsi, r10
  [0x102C4] mov r9, [rsp+0x10]
  [0x102CC] mov rdx, r9
  [0x102CF] mov r9, [rsp+0x28]
  [0x102D7] mov r8, r9
  [0x102DA] add r8, r15
  [0x102DD] call r8
  [0x102E0] mov r9, [rsp+0x18]
  [0x102E8] mov r8d, [r15+r9*1]
  [0x102EC] mov r8d, [r15+r8*1+0x0C]
  [0x102F1] mov r9, r8
  [0x102F4] mov [rsp+0x18], r9
  [0x102FC] mov r8, r14
  [0x102FF] mov r9, [rsp+0x18]
  [0x10307] cmp r9, r8
  [0x1030A] jnz 0x0000000000010227
  [0x10310] mov r9, r14
  [0x10313] jmp 0x000000000001031B
  [0x10318] mov r9, r14
  [0x1031B] mov r9, [rsp+0x08]
  [0x10323] mov r8, r9
  [0x10326] mov r9d, 0x01
  [0x1032C] add r8, r9
  [0x1032F] mov r9, r8
  [0x10332] mov [rsp+0x08], r9
  [0x1033A] mov r9, [rsp]
  [0x10342] movsxd r8, dword ptr [r15+r9*1]
  [0x10346] mov r9, [rsp+0x08]
  [0x1034E] cmp r9, r8
  [0x10351] jl 0x000000000001009E
  [0x10357] mov r9, r14
  [0x1035A] jmp 0x0000000000010362
  [0x1035F] mov r9, r14
  [0x10362] mov r9d, 0x01
  [0x10368] add r11, r9
  [0x1036B] mov r9, [rsp+0x50]
  [0x10373] movsxd r8, dword ptr [r15+r9*1]
  [0x10377] cmp r11, r8
  [0x1037A] jl 0x0000000000010037
  [0x10380] mov r9, r14
  [0x10383] add rsp, 0x60
  [0x10387] pop r12
  [0x10389] pop r11
  [0x1038B] pop r10
  [0x1038D] pop rbp
  [0x1038E] pop rbx
  [0x1038F] ret


[(method birth bsp-header)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] mov rbx, rdi
  [0x1000B] mov r9d, [r15+rbx*1+0x6C]
  [0x10010] xor r8, r8
  [0x10013] cmp r9, r8
  [0x10016] jz 0x000000000001002C
  [0x1001C] mov r9d, [r15+rbx*1+0x6C]
  [0x10021] movsx rcx, word ptr [r15+r9*1+0x02]
  [0x10027] jmp 0x000000000001002F
  [0x1002C] xor rcx, rcx
  [0x1002F] mov r9d, [r15+rbx*1+0x78]
  [0x10034] mov r9d, [r15+r9*1+0x118]
  [0x1003C] mov r8, r14
  [0x1003F] cmp r9, r8
  [0x10042] jnz 0x0000000000010080
  [0x10048] lea rdi, [r14+0xAFECAFE]
  [0x10050] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10058] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10060] mov r9d, [r15+r9*1+0x10]
  [0x10065] mov rdx, rcx
  [0x10068] add r9, r15
  [0x1006B] call r9
  [0x1006E] mov r9d, [r15+rbx*1+0x78]
  [0x10073] mov [r15+r9*1+0x118], eax
  [0x1007B] jmp 0x00000000000100D5
  [0x10080] mov r9d, [r15+rbx*1+0x78]
  [0x10085] mov r9d, [r15+r9*1+0x118]
  [0x1008D] movsxd r9, dword ptr [r15+r9*1+0x04]
  [0x10092] cmp r9, rcx
  [0x10095] jnl 0x00000000000100D2
  [0x1009B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100A3] xor rdi, rdi
  [0x100A6] lea rsi, [0x00000000000100AD]
  [0x100AD] sub rsi, r15
  [0x100B0] mov edx, [r15+rbx*1+0x78]
  [0x100B5] mov r8d, [r15+rbx*1+0x78]
  [0x100BA] mov r8d, [r15+r8*1+0x118]
  [0x100C2] movsxd r8, dword ptr [r15+r8*1+0x04]
  [0x100C7] add r9, r15
  [0x100CA] call r9
  [0x100CD] jmp 0x00000000000100D5
  [0x100D2] mov rax, r14
  [0x100D5] xor r9, r9
  [0x100D8] mov r8d, [r15+rbx*1+0x78]
  [0x100DD] mov r8d, [r15+r8*1+0x118]
  [0x100E5] mov [r15+r8*1], r9d
  [0x100E9] mov r9d, [r15+rbx*1+0x6C]
  [0x100EE] xor r8, r8
  [0x100F1] cmp r9, r8
  [0x100F4] jz 0x0000000000010182
  [0x100FA] xor rbp, rbp
  [0x100FD] jmp 0x0000000000010166
  [0x10102] mov r9, rbp
  [0x10105] shl r9, 0x02
  [0x10109] mov r8d, [r15+rbx*1+0xA8]
  [0x10111] add r9, r8
  [0x10114] mov r9d, [r15+r9*1]
  [0x10118] mov r8d, 0xFFFF
  [0x1011E] and r9, r8
  [0x10121] shl r9, 0x05
  [0x10125] mov r8d, 0x20
  [0x1012B] mov ecx, [r15+rbx*1+0x6C]
  [0x10130] add r8, rcx
  [0x10133] add r9, r8
  [0x10136] mov edi, [r15+r9*1+0x04]
  [0x1013B] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10143] mov edx, [r15+rbx*1+0x78]
  [0x10148] mov ecx, [r15+rdi*1+0x2C]
  [0x1014D] mov r9d, [r15+rdi*1-0x04]
  [0x10152] mov r9d, [r15+r9*1+0x70]
  [0x10157] add r9, r15
  [0x1015A] call r9
  [0x1015D] mov r9d, 0x01
  [0x10163] add rbp, r9
  [0x10166] mov r9d, [r15+rbx*1+0x6C]
  [0x1016B] movsx r9, word ptr [r15+r9*1+0x02]
  [0x10171] cmp rbp, r9
  [0x10174] jl 0x0000000000010102
  [0x1017A] mov r9, r14
  [0x1017D] jmp 0x0000000000010185
  [0x10182] mov r9, r14
  [0x10185] mov r9d, [r15+rbx*1+0x98]
  [0x1018D] xor r8, r8
  [0x10190] cmp r9, r8
  [0x10193] jz 0x00000000000101AC
  [0x10199] mov r9d, [r15+rbx*1+0x98]
  [0x101A1] movsx rcx, word ptr [r15+r9*1+0x02]
  [0x101A7] jmp 0x00000000000101AF
  [0x101AC] xor rcx, rcx
  [0x101AF] mov r9d, [r15+rbx*1+0x78]
  [0x101B4] mov r9d, [r15+r9*1+0x11C]
  [0x101BC] mov r8, r14
  [0x101BF] cmp r9, r8
  [0x101C2] jnz 0x0000000000010200
  [0x101C8] lea rdi, [r14+0xAFECAFE]
  [0x101D0] mov esi, [r15+r14*1+0xBADBEEF]
  [0x101D8] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x101E0] mov r9d, [r15+r9*1+0x10]
  [0x101E5] mov rdx, rcx
  [0x101E8] add r9, r15
  [0x101EB] call r9
  [0x101EE] mov r9d, [r15+rbx*1+0x78]
  [0x101F3] mov [r15+r9*1+0x11C], eax
  [0x101FB] jmp 0x0000000000010255
  [0x10200] mov r9d, [r15+rbx*1+0x78]
  [0x10205] mov r9d, [r15+r9*1+0x11C]
  [0x1020D] movsxd r9, dword ptr [r15+r9*1+0x04]
  [0x10212] cmp r9, rcx
  [0x10215] jnl 0x0000000000010252
  [0x1021B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10223] xor rdi, rdi
  [0x10226] lea rsi, [0x000000000001022D]
  [0x1022D] sub rsi, r15
  [0x10230] mov edx, [r15+rbx*1+0x78]
  [0x10235] mov r8d, [r15+rbx*1+0x78]
  [0x1023A] mov r8d, [r15+r8*1+0x11C]
  [0x10242] movsxd r8, dword ptr [r15+r8*1+0x04]
  [0x10247] add r9, r15
  [0x1024A] call r9
  [0x1024D] jmp 0x0000000000010255
  [0x10252] mov rax, r14
  [0x10255] xor r9, r9
  [0x10258] mov r8d, [r15+rbx*1+0x78]
  [0x1025D] mov r8d, [r15+r8*1+0x11C]
  [0x10265] mov [r15+r8*1], r9d
  [0x10269] mov r9d, [r15+rbx*1+0x78]
  [0x1026E] mov ebp, [r15+r9*1+0x11C]
  [0x10276] mov r12d, [r15+rbx*1+0x98]
  [0x1027E] xor r9, r9
  [0x10281] cmp r12, r9
  [0x10284] jz 0x0000000000010307
  [0x1028A] xor r11, r11
  [0x1028D] jmp 0x00000000000102F0
  [0x10292] mov r9, r11
  [0x10295] shl r9, 0x05
  [0x10299] mov r8d, 0x20
  [0x1029F] add r8, r12
  [0x102A2] add r9, r8
  [0x102A5] mov edi, [r15+r9*1+0x04]
  [0x102AA] movsxd r9, dword ptr [r15+rbp*1]
  [0x102AE] shl r9, 0x04
  [0x102B2] mov r8d, 0x0C
  [0x102B8] add r8, rbp
  [0x102BB] add r9, r8
  [0x102BE] mov [r15+rdi*1+0x14], r9d
  [0x102C3] mov r9d, [r15+rdi*1-0x04]
  [0x102C8] mov r9d, [r15+r9*1+0x80]
  [0x102D0] add r9, r15
  [0x102D3] call r9
  [0x102D6] movsxd r9, dword ptr [r15+rbp*1]
  [0x102DA] mov r8d, 0x01
  [0x102E0] add r9, r8
  [0x102E3] mov [r15+rbp*1], r9d
  [0x102E7] mov r9d, 0x01
  [0x102ED] add r11, r9
  [0x102F0] movsx r9, word ptr [r12+r15*1+0x02]
  [0x102F6] cmp r11, r9
  [0x102F9] jl 0x0000000000010292
  [0x102FF] mov r9, r14
  [0x10302] jmp 0x000000000001030A
  [0x10307] mov r9, r14
  [0x1030A] mov ebx, [r15+rbx*1+0x70]
  [0x1030F] xor r9, r9
  [0x10312] cmp rbx, r9
  [0x10315] jz 0x0000000000010368
  [0x1031B] xor rbp, rbp
  [0x1031E] jmp 0x0000000000010353
  [0x10323] mov r9d, 0x0C
  [0x10329] mov r8, rbp
  [0x1032C] shl r8, 0x02
  [0x10330] add r8, r9
  [0x10333] add r8, rbx
  [0x10336] mov edi, [r15+r8*1]
  [0x1033A] mov r9d, [r15+rdi*1-0x04]
  [0x1033F] mov r9d, [r15+r9*1+0x68]
  [0x10344] add r9, r15
  [0x10347] call r9
  [0x1034A] mov r9d, 0x01
  [0x10350] add rbp, r9
  [0x10353] movsxd r9, dword ptr [r15+rbx*1]
  [0x10357] cmp rbp, r9
  [0x1035A] jl 0x0000000000010323
  [0x10360] mov r9, r14
  [0x10363] jmp 0x000000000001036B
  [0x10368] mov r9, r14
  [0x1036B] pop r12
  [0x1036D] pop r11
  [0x1036F] pop r10
  [0x10371] pop rbp
  [0x10372] pop rbx
  [0x10373] ret


[update-actor-vis-box]
[1m[38;2;255;000;000m- [0x10000] [0msub rsp, 0x18
  [0x10004] mov r9, rdi
  [0x10007] mov r8, r14
  [0x1000A] cmp r9, r8
  [0x1000D] jz 0x000000000001002F
  [0x10013] mov r9d, [r15+rdi*1+0x74]
  [0x10018] xor r8, r8
  [0x1001B] mov rcx, r14
  [0x1001E] cmp r9, r8
  [0x10021] jz 0x000000000001002C
  [0x10027] lea rcx, [r14+0x08]
  [0x1002C] mov r9, rcx
  [0x1002F] mov r8, r14
  [0x10032] cmp r9, r8
  [0x10035] jz 0x0000000000010144
  [0x1003B] mov r9, rsp
  [0x1003E] sub r9, r15
  [0x10041] mov r8d, 0x6C
  [0x10047] mov ecx, [r15+rdi*1+0x74]
  [0x1004C] add r8, rcx
  [0x1004F] mov ecx, 0x7C
  [0x10054] mov eax, [r15+rdi*1+0x74]
  [0x10059] add rcx, rax
  [0x1005C] vmovaps xmm6, [r15+r8*1]
  [0x10062] vmovaps xmm5, [r15+rcx*1]
  [0x10068] vmovaps xmm7, [0x0000000000010070]
  [0x10070] vaddps xmm6, xmm6, xmm5
  [0x10074] vblendps xmm6, xmm6, xmm7, 0x08
  [0x1007A] vmovaps [r15+r9*1], xmm6
  [0x10080] mov r8d, [r15+rdi*1+0x74]
  [0x10085] movss xmm7, dword ptr [r15+r8*1+0x88]
  [0x1008F] movss xmm6, dword ptr [r15+rsi*1]
  [0x10095] movss xmm5, dword ptr [r15+r9*1]
  [0x1009B] subss xmm5, xmm7
  [0x1009F] minss xmm6, xmm5
  [0x100A3] movss [r15+rsi*1], xmm6
  [0x100A9] movss xmm6, dword ptr [r15+rsi*1+0x04]
  [0x100B0] movss xmm5, dword ptr [r15+r9*1+0x04]
  [0x100B7] subss xmm5, xmm7
  [0x100BB] minss xmm6, xmm5
  [0x100BF] movss [r15+rsi*1+0x04], xmm6
  [0x100C6] movss xmm6, dword ptr [r15+rsi*1+0x08]
  [0x100CD] movss xmm5, dword ptr [r15+r9*1+0x08]
  [0x100D4] subss xmm5, xmm7
  [0x100D8] minss xmm6, xmm5
  [0x100DC] movss [r15+rsi*1+0x08], xmm6
  [0x100E3] movss xmm6, dword ptr [r15+rdx*1]
  [0x100E9] movss xmm5, dword ptr [r15+r9*1]
  [0x100EF] addss xmm5, xmm7
  [0x100F3] maxss xmm6, xmm5
  [0x100F7] movss [r15+rdx*1], xmm6
  [0x100FD] movss xmm6, dword ptr [r15+rdx*1+0x04]
  [0x10104] movss xmm5, dword ptr [r15+r9*1+0x04]
  [0x1010B] addss xmm5, xmm7
  [0x1010F] maxss xmm6, xmm5
  [0x10113] movss [r15+rdx*1+0x04], xmm6
  [0x1011A] movss xmm6, dword ptr [r15+rdx*1+0x08]
  [0x10121] movss xmm5, dword ptr [r15+r9*1+0x08]
  [0x10128] addss xmm5, xmm7
  [0x1012C] maxss xmm6, xmm5
  [0x10130] movss [r15+rdx*1+0x08], xmm6
  [0x10137] movd r9d, xmm6
  [0x1013C] movsxd r9, r9d
  [0x1013F] jmp 0x0000000000010147
  [0x10144] mov r9, r14
  [0x10147] xor r9, r9
  [0x1014A] add rsp, 0x18
  [0x1014E] ret


[(method remove-from-level! entity)]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rdi*1+0x14]
  [0x10005] mov r8d, [r15+r9*1+0x04]
  [0x1000A] cmp r8, r9
  [0x1000D] jnz 0x0000000000010020
  [0x10013] mov r9, r14
  [0x10016] mov [r15+rsi*1+0x0C], r9d
  [0x1001B] jmp 0x000000000001005A
  [0x10020] mov r8d, [r15+r9*1]
  [0x10024] mov ecx, [r15+r9*1+0x04]
  [0x10029] mov [r15+rcx*1], r8d
  [0x1002D] mov r8d, [r15+r9*1+0x04]
  [0x10032] mov ecx, [r15+r9*1]
  [0x10036] mov [r15+rcx*1+0x04], r8d
  [0x1003B] mov r8d, [r15+rsi*1+0x0C]
  [0x10040] cmp r8, r9
  [0x10043] jnz 0x0000000000010057
  [0x10049] mov r9d, [r15+r9*1]
  [0x1004D] mov [r15+rsi*1+0x0C], r9d
  [0x10052] jmp 0x000000000001005A
  [0x10057] mov r9, r14
  [0x1005A] mov rax, rdi
  [0x1005D] ret


[(method debug-print-entities level-group)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x10
  [0x1000C] mov rbx, rdi
  [0x1000F] mov rbp, rsi
  [0x10012] mov r12, rdx
  [0x10015] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1001D] lea rdi, [r14+0x08]
  [0x10022] lea rsi, [0x0000000000010029]
  [0x10029] sub rsi, r15
  [0x1002C] xor rdx, rdx
  [0x1002F] xor rcx, rcx
  [0x10032] xor r8, r8
  [0x10035] add r9, r15
  [0x10038] call r9
  [0x1003B] xor r11, r11
  [0x1003E] jmp 0x00000000000101FE
  [0x10043] mov r10d, 0xA30
  [0x10049] imul r10d, r11d
  [0x1004D] movsxd r10, r10d
  [0x10050] mov r9d, 0x60
  [0x10056] add r9, rbx
  [0x10059] add r10, r9
  [0x1005C] mov r9d, [r15+r10*1+0x10]
  [0x10061] lea r8, [r14+0xAFECAFE]
  [0x10069] cmp r9, r8
  [0x1006C] jnz 0x00000000000101F2
  [0x10072] mov r9, rbp
  [0x10075] lea r8, [r14+0xAFECAFE]
  [0x1007D] cmp r9, r8
  [0x10080] jnz 0x0000000000010155
  [0x10086] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1008E] lea rdi, [r14+0x08]
  [0x10093] lea rsi, [0x000000000001009A]
  [0x1009A] sub rsi, r15
  [0x1009D] mov edx, [r15+r10*1]
  [0x100A1] add r9, r15
  [0x100A4] call r9
  [0x100A7] xor r8, r8
  [0x100AA] mov r9, r8
  [0x100AD] mov [rsp], r9
  [0x100B5] jmp 0x000000000001012E
  [0x100BA] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x100C2] lea rdi, [r14+0x08]
  [0x100C7] lea rsi, [0x00000000000100CE]
  [0x100CE] sub rsi, r15
  [0x100D1] mov ecx, 0x0C
  [0x100D6] mov r9, [rsp]
  [0x100DE] mov rdx, r9
  [0x100E1] shl rdx, 0x02
  [0x100E5] add rdx, rcx
  [0x100E8] mov r9d, [r15+r10*1+0x30]
  [0x100ED] mov r9d, [r15+r9*1+0x08]
  [0x100F2] add rdx, r9
  [0x100F5] mov r9d, [r15+rdx*1]
  [0x100F9] mov ecx, [r15+r9*1+0x04]
  [0x100FE] mov r9, [rsp]
  [0x10106] mov rdx, r9
  [0x10109] add r8, r15
  [0x1010C] call r8
  [0x1010F] mov r9, [rsp]
  [0x10117] mov r8, r9
  [0x1011A] mov r9d, 0x01
  [0x10120] add r8, r9
  [0x10123] mov r9, r8
  [0x10126] mov [rsp], r9
  [0x1012E] mov r9d, [r15+r10*1+0x30]
  [0x10133] mov r9d, [r15+r9*1+0x08]
  [0x10138] movsxd r8, dword ptr [r15+r9*1]
  [0x1013C] mov r9, [rsp]
  [0x10144] cmp r9, r8
  [0x10147] jl 0x00000000000100BA
  [0x1014D] mov r9, r14
  [0x10150] jmp 0x00000000000101ED
  [0x10155] mov r9d, [r15+r10*1+0x2C]
  [0x1015A] mov r9d, [r15+r9*1+0x78]
  [0x1015F] mov r10d, [r15+r9*1+0x118]
  [0x10167] xor r8, r8
  [0x1016A] mov r9, r8
  [0x1016D] mov [rsp+0x08], r9
  [0x10175] jmp 0x00000000000101D5
  [0x1017A] mov r9, [rsp+0x08]
  [0x10182] mov r8, r9
  [0x10185] shl r8, 0x06
  [0x10189] mov r9d, 0x0C
  [0x1018F] add r9, r10
  [0x10192] add r8, r9
  [0x10195] mov edi, [r15+r8*1+0x08]
  [0x1019A] mov r9d, [r15+rdi*1-0x04]
  [0x1019F] mov r9d, [r15+r9*1+0x84]
  [0x101A7] mov rsi, rbp
  [0x101AA] mov rdx, r12
  [0x101AD] mov r8, r9
  [0x101B0] add r8, r15
  [0x101B3] call r8
  [0x101B6] mov r9, [rsp+0x08]
  [0x101BE] mov r8, r9
  [0x101C1] mov r9d, 0x01
  [0x101C7] add r8, r9
  [0x101CA] mov r9, r8
  [0x101CD] mov [rsp+0x08], r9
  [0x101D5] movsxd r8, dword ptr [r15+r10*1]
  [0x101D9] mov r9, [rsp+0x08]
  [0x101E1] cmp r9, r8
  [0x101E4] jl 0x000000000001017A
  [0x101EA] mov r9, r14
  [0x101ED] jmp 0x00000000000101F5
  [0x101F2] mov r9, r14
  [0x101F5] mov r9d, 0x01
  [0x101FB] add r11, r9
  [0x101FE] movsxd r9, dword ptr [r15+rbx*1]
  [0x10202] cmp r11, r9
  [0x10205] jl 0x0000000000010043
  [0x1020B] mov r9, r14
  [0x1020E] add rsp, 0x10
  [0x10212] pop r12
  [0x10214] pop r11
  [0x10216] pop r10
  [0x10218] pop rbp
  [0x10219] pop rbx
  [0x1021A] ret


[(method print process)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] mov rbx, rdi
  [0x10007] mov eax, [r15+r14*1+0xBADBEEF]
  [0x1000F] lea rdi, [r14+0x08]
  [0x10014] lea rsi, [0x000000000001001B]
  [0x1001B] sub rsi, r15
  [0x1001E] mov edx, [r15+rbx*1-0x04]
  [0x10023] mov ecx, [r15+rbx*1]
  [0x10027] mov r8d, [r15+rbx*1+0x20]
  [0x1002C] mov r9d, [r15+rbx*1+0x34]
  [0x10031] mov rbp, r14
  [0x10034] cmp r9, rbp
  [0x10037] jz 0x000000000001004B
  [0x1003D] mov r9d, [r15+rbx*1+0x34]
  [0x10042] mov r9d, [r15+r9*1]
  [0x10046] jmp 0x000000000001004E
  [0x1004B] mov r9, r14
  [0x1004E] mov rbp, rax
  [0x10051] add rbp, r15
  [0x10054] call rbp
  [0x10056] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1005E] lea rsi, [r14+0x08]
  [0x10063] mov rdi, rbx
  [0x10066] add r9, r15
  [0x10069] call r9
  [0x1006C] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10074] lea rdi, [r14+0x08]
  [0x10079] lea rsi, [0x0000000000010080]
  [0x10080] sub rsi, r15
  [0x10083] mov r9d, [r15+rbx*1+0x2C]
  [0x10088] mov edx, [r15+r9*1+0x1C]
  [0x1008D] mov r9d, [r15+rbx*1+0x2C]
  [0x10092] mov r9d, [r15+r9*1+0x18]
  [0x10097] sub rdx, r9
  [0x1009A] mov r9d, [r15+rbx*1+0x28]
  [0x1009F] movsxd rcx, dword ptr [r15+r9*1+0x20]
  [0x100A4] movsxd r8, dword ptr [r15+rbx*1+0x44]
  [0x100A9] mov r9d, [r15+rbx*1+0x50]
  [0x100AE] mov ebp, [r15+rbx*1+0x54]
  [0x100B3] sub r9, rbp
  [0x100B6] sub r8, r9
  [0x100B9] movsxd r9, dword ptr [r15+rbx*1+0x44]
  [0x100BE] mov r10, rbx
  [0x100C1] mov rbp, rax
  [0x100C4] add rbp, r15
  [0x100C7] call rbp
  [0x100C9] mov rax, rbx
  [0x100CC] pop r10
  [0x100CE] pop rbp
  [0x100CF] pop rbx
  [0x100D0] ret


[(method debug-draw-actors level-group)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x110
  [0x1000F] mov [rsp+0x108], rdi
  [0x10017] mov rbp, rsi
  [0x1001A] mov r9, rbp
  [0x1001D] mov r8, r14
  [0x10020] cmp r9, r8
  [0x10023] jz 0x0000000000010094
  [0x10029] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10031] lea r8, [r14+0xAFECAFE]
  [0x10039] mov rcx, r14
  [0x1003C] cmp r9, r8
  [0x1003F] jnz 0x000000000001004A
  [0x10045] lea rcx, [r14+0x08]
  [0x1004A] mov r9, rcx
  [0x1004D] mov r8, r14
  [0x10050] cmp r9, r8
  [0x10053] jnz 0x000000000001007D
  [0x10059] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10061] lea r8, [r14+0xAFECAFE]
  [0x10069] mov rcx, r14
  [0x1006C] cmp r9, r8
  [0x1006F] jnz 0x000000000001007A
  [0x10075] lea rcx, [r14+0x08]
  [0x1007A] mov r9, rcx
  [0x1007D] mov r8, r14
  [0x10080] mov rcx, r14
  [0x10083] cmp r9, r8
  [0x10086] jnz 0x0000000000010091
  [0x1008C] lea rcx, [r14+0x08]
  [0x10091] mov r9, rcx
  [0x10094] mov r8, r14
  [0x10097] cmp r9, r8
  [0x1009A] jz 0x000000000001079A
  [0x100A0] xor r12, r12
  [0x100A3] jmp 0x000000000001077D
  [0x100A8] mov r9d, 0xA30
  [0x100AE] imul r9d, r12d
  [0x100B2] movsxd r9, r9d
  [0x100B5] mov r8d, 0x60
  [0x100BB] mov rcx, [rsp+0x108]
  [0x100C3] add r8, rcx
  [0x100C6] add r9, r8
  [0x100C9] mov r8d, [r15+r9*1+0x10]
  [0x100CE] lea rcx, [r14+0xAFECAFE]
  [0x100D6] cmp r8, rcx
  [0x100D9] jnz 0x0000000000010771
  [0x100DF] mov r9d, [r15+r9*1+0x2C]
  [0x100E4] mov r9d, [r15+r9*1+0x78]
  [0x100E9] mov r11d, [r15+r9*1+0x118]
  [0x100F1] xor r8, r8
  [0x100F4] mov r9, r8
  [0x100F7] mov [rsp+0x20], r9
  [0x100FF] jmp 0x0000000000010754
  [0x10104] mov r9, [rsp+0x20]
  [0x1010C] mov r8, r9
  [0x1010F] shl r8, 0x06
  [0x10113] mov r9d, 0x0C
  [0x10119] add r9, r11
  [0x1011C] add r8, r9
  [0x1011F] mov r8d, [r15+r8*1+0x08]
  [0x10124] mov r9, r8
  [0x10127] mov [rsp+0x30], r9
  [0x1012F] mov r8d, 0x20
  [0x10135] mov r9, [rsp+0x30]
  [0x1013D] mov ecx, [r15+r9*1+0x14]
  [0x10142] add r8, rcx
  [0x10145] mov r9, r8
  [0x10148] mov [rsp+0x28], r9
  [0x10150] lea r9, [r14+0xAFECAFE]
  [0x10158] mov r8, r14
  [0x1015B] cmp rbp, r9
  [0x1015E] jnz 0x0000000000010169
  [0x10164] lea r8, [r14+0x08]
  [0x10169] mov r9, r8
  [0x1016C] mov r8, r14
  [0x1016F] cmp r9, r8
  [0x10172] jz 0x00000000000101C6
  [0x10178] mov r9, [rsp+0x30]
  [0x10180] mov r8d, [r15+r9*1+0x14]
  [0x10185] mov r9d, [r15+r8*1+0x0C]
  [0x1018A] mov r8, r14
  [0x1018D] cmp r9, r8
  [0x10190] jz 0x00000000000101C6
  [0x10196] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1019E] mov r9, [rsp+0x30]
  [0x101A6] mov ecx, [r15+r9*1+0x14]
  [0x101AB] mov r9d, [r15+rcx*1+0x0C]
  [0x101B0] mov edi, [r15+r9*1-0x04]
  [0x101B5] mov esi, [r15+r14*1+0xBADBEEF]
  [0x101BD] add r8, r15
  [0x101C0] call r8
  [0x101C3] mov r9, rax
  [0x101C6] mov r8, r14
  [0x101C9] cmp r9, r8
  [0x101CC] jz 0x00000000000105A3
  [0x101D2] mov r9, [rsp+0x30]
  [0x101DA] mov r8d, [r15+r9*1+0x14]
  [0x101DF] mov r9d, [r15+r8*1+0x0C]
  [0x101E4] mov r8, r9
  [0x101E7] mov r9, r8
  [0x101EA] mov [rsp+0x48], r9
  [0x101F2] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x101FA] lea rdi, [r14+0x08]
  [0x101FF] mov esi, 0x44
  [0x10204] mov edx, 0x0C
  [0x10209] mov r9, [rsp+0x48]
  [0x10211] mov ecx, [r15+r9*1+0x6C]
  [0x10216] add rdx, rcx
  [0x10219] mov ecx, 0x8080FF80
  [0x1021E] add r8, r15
  [0x10221] call r8
  [0x10224] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1022C] mov [rsp+0x88], r9
  [0x10234] lea r9, [r14+0x08]
  [0x10239] mov [rsp+0xA0], r9
  [0x10241] mov r9d, 0x44
  [0x10247] mov [rsp+0x98], r9
  [0x1024F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10257] mov eax, [r15+r9*1+0x38]
  [0x1025C] lea rsi, [r14+0xAFECAFE]
  [0x10264] lea rdx, [r14+0xAFECAFE]
  [0x1026C] movss xmm7, dword ptr [0x0000000000010274]
  [0x10274] mov r8, r14
  [0x10277] mov r9, r14
  [0x1027A] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10282] mov rdi, [rsp+0x30]
  [0x1028A] movd ecx, xmm7
  [0x1028E] movsxd rcx, ecx
  [0x10291] mov [rsp+0x100], rax
  [0x10299] mov rbx, [rsp+0x100]
  [0x102A1] add rbx, r15
  [0x102A4] call rbx
  [0x102A6] mov [rsp+0x100], rbx
  [0x102AE] mov ecx, 0x0C
  [0x102B3] mov r9, [rsp+0x48]
  [0x102BB] mov r8d, [r15+r9*1+0x6C]
  [0x102C0] add rcx, r8
  [0x102C3] mov r8d, 0x01
  [0x102C9] lea r9, [0x00000000000102D0]
  [0x102D0] sub r9, r15
  [0x102D3] mov rdi, [rsp+0xA0]
  [0x102DB] mov rsi, [rsp+0x98]
  [0x102E3] mov rdx, rax
  [0x102E6] mov rax, [rsp+0x88]
  [0x102EE] mov rbx, rax
  [0x102F1] add rbx, r15
  [0x102F4] call rbx
  [0x102F6] mov eax, [r15+r14*1+0xBADBEEF]
  [0x102FE] lea rdi, [r14+0x08]
  [0x10303] mov esi, 0x44
  [0x10308] mov r8d, 0x20000
  [0x1030E] mov r9, [rsp+0x48]
  [0x10316] mov ecx, [r15+r9*1+0x34]
  [0x1031B] mov r9d, [r15+rcx*1]
  [0x1031F] add r8, r9
  [0x10322] mov edx, [r15+r8*1]
  [0x10326] mov ecx, 0x0C
  [0x1032B] mov r9, [rsp+0x48]
  [0x10333] mov r8d, [r15+r9*1+0x6C]
  [0x10338] add rcx, r8
  [0x1033B] mov r8d, 0x01
  [0x10341] lea r9, [0x0000000000010348]
  [0x10348] sub r9, r15
  [0x1034B] mov rbx, rax
  [0x1034E] add rbx, r15
  [0x10351] call rbx
  [0x10353] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1035B] mov eax, [r15+r9*1+0x34]
  [0x10360] mov r9, [rsp+0x48]
  [0x10368] mov edi, [r15+r9*1+0x30]
  [0x1036D] lea rsi, [r14+0xAFECAFE]
  [0x10375] lea rdx, [r14+0xAFECAFE]
  [0x1037D] movss xmm7, dword ptr [0x0000000000010385]
  [0x10385] mov r8, r14
  [0x10388] mov r9, r14
  [0x1038B] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10393] movd ecx, xmm7
  [0x10397] movsxd rcx, ecx
  [0x1039A] mov rbx, rax
  [0x1039D] add rbx, r15
  [0x103A0] call rbx
  [0x103A2] mov r9, rax
  [0x103A5] mov [rsp+0xA8], r9
  [0x103AD] mov r8, r14
  [0x103B0] mov r9, [rsp+0xA8]
  [0x103B8] cmp r9, r8
  [0x103BB] jz 0x00000000000104BF
  [0x103C1] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x103C9] lea r8, [r14+0x08]
  [0x103CE] mov ecx, 0x44
  [0x103D3] mov r9, r8
  [0x103D6] mov [rsp+0x90], r9
  [0x103DE] mov r9, rcx
  [0x103E1] mov [rsp+0xB0], r9
  [0x103E9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x103F1] mov [rsp+0xD0], r9
  [0x103F9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10401] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10409] add r9, r15
  [0x1040C] call r9
  [0x1040F] mov [rsp+0xF8], rax
  [0x10417] lea r9, [0x000000000001041E]
  [0x1041E] sub r9, r15
  [0x10421] mov [rsp+0xF0], r9
  [0x10429] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10431] mov r9, [rsp+0xA8]
  [0x10439] movsxd rdi, dword ptr [r15+r9*1]
  [0x1043D] add r8, r15
  [0x10440] call r8
  [0x10443] mov r9, [rsp+0xA8]
  [0x1044B] movsxd rcx, dword ptr [r15+r9*1+0x04]
  [0x10450] mov rdi, [rsp+0xF8]
  [0x10458] mov rsi, [rsp+0xF0]
  [0x10460] mov rdx, rax
  [0x10463] mov r9, [rsp+0xD0]
  [0x1046B] mov r8, r9
  [0x1046E] add r8, r15
  [0x10471] call r8
  [0x10474] mov r9, [rsp+0xB0]
  [0x1047C] mov rsi, r9
  [0x1047F] mov edx, [r15+r14*1+0xBADBEEF]
  [0x10487] mov ecx, 0x0C
  [0x1048C] mov r9, [rsp+0x48]
  [0x10494] mov r8d, [r15+r9*1+0x6C]
  [0x10499] add rcx, r8
  [0x1049C] mov r8d, 0x01
  [0x104A2] lea r9, [0x00000000000104A9]
  [0x104A9] sub r9, r15
  [0x104AC] mov rdi, [rsp+0x90]
  [0x104B4] add r10, r15
  [0x104B7] call r10
  [0x104BA] jmp 0x00000000000104C2
  [0x104BF] mov rax, r14
  [0x104C2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x104CA] mov eax, [r15+r9*1+0x38]
  [0x104CF] mov r9, [rsp+0x48]
  [0x104D7] mov edi, [r15+r9*1+0x30]
  [0x104DC] lea rsi, [r14+0xAFECAFE]
  [0x104E4] lea rdx, [r14+0xAFECAFE]
  [0x104EC] movss xmm7, dword ptr [0x00000000000104F4]
  [0x104F4] mov r8, r14
  [0x104F7] mov r9, r14
  [0x104FA] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10502] movd ecx, xmm7
  [0x10506] movsxd rcx, ecx
  [0x10509] mov rbx, rax
  [0x1050C] add rbx, r15
  [0x1050F] call rbx
  [0x10511] mov r9, rax
  [0x10514] mov r8, r14
  [0x10517] cmp r9, r8
  [0x1051A] jz 0x0000000000010541
  [0x10520] mov r9d, [r15+rax*1-0x04]
  [0x10525] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1052D] mov rcx, r14
  [0x10530] cmp r9, r8
  [0x10533] jnz 0x000000000001053E
  [0x10539] lea rcx, [r14+0x08]
  [0x1053E] mov r9, rcx
  [0x10541] mov r8, r14
  [0x10544] cmp r9, r8
  [0x10547] jz 0x000000000001059B
  [0x1054D] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x10555] lea rdi, [r14+0x08]
  [0x1055A] mov esi, 0x44
  [0x1055F] mov r9d, 0x20000
  [0x10565] add r9, rax
  [0x10568] mov edx, [r15+r9*1]
  [0x1056C] mov ecx, 0x0C
  [0x10571] mov r9, [rsp+0x48]
  [0x10579] mov r8d, [r15+r9*1+0x6C]
  [0x1057E] add rcx, r8
  [0x10581] mov r8d, 0x01
  [0x10587] lea r9, [0x000000000001058E]
  [0x1058E] sub r9, r15
  [0x10591] add rbx, r15
  [0x10594] call rbx
  [0x10596] jmp 0x000000000001059E
  [0x1059B] mov rax, r14
  [0x1059E] jmp 0x0000000000010735
  [0x105A3] lea r9, [r14+0xAFECAFE]
  [0x105AB] mov r8, r14
  [0x105AE] cmp rbp, r9
  [0x105B1] jnz 0x00000000000105BC
  [0x105B7] lea r8, [r14+0x08]
  [0x105BC] mov r9, r8
  [0x105BF] mov r8, r14
  [0x105C2] cmp r9, r8
  [0x105C5] jnz 0x00000000000105DD
  [0x105CB] mov r9, [rsp+0x30]
  [0x105D3] mov r8d, [r15+r9*1+0x14]
  [0x105D8] mov r9d, [r15+r8*1+0x0C]
  [0x105DD] mov r8, r14
  [0x105E0] cmp r9, r8
  [0x105E3] jz 0x0000000000010732
  [0x105E9] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x105F1] lea rdi, [r14+0x08]
  [0x105F6] mov esi, 0x44
  [0x105FB] mov r9, [rsp+0x30]
  [0x10603] mov ecx, [r15+r9*1+0x14]
  [0x10608] mov r9d, [r15+rcx*1+0x0C]
  [0x1060D] mov rcx, r14
  [0x10610] cmp r9, rcx
  [0x10613] jz 0x0000000000010623
  [0x10619] mov ecx, 0x8080FF80
  [0x1061E] jmp 0x0000000000010628
  [0x10623] mov ecx, 0x800000FF
  [0x10628] mov r9, [rsp+0x28]
  [0x10630] mov rdx, r9
  [0x10633] add r8, r15
  [0x10636] call r8
  [0x10639] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10641] lea rcx, [r14+0x08]
  [0x10646] mov edx, 0x44
  [0x1064B] mov r9, r8
  [0x1064E] mov [rsp+0x58], r9
  [0x10656] mov r9, rcx
  [0x10659] mov [rsp+0x68], r9
  [0x10661] mov r9, rdx
  [0x10664] mov [rsp+0x70], r9
  [0x1066C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10674] mov eax, [r15+r9*1+0x38]
  [0x10679] lea rsi, [r14+0xAFECAFE]
  [0x10681] lea rdx, [r14+0xAFECAFE]
  [0x10689] movss xmm7, dword ptr [0x0000000000010691]
  [0x10691] mov r8, r14
  [0x10694] mov r9, r14
  [0x10697] mov rbx, r9
  [0x1069A] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x106A2] mov r9, [rsp+0x30]
  [0x106AA] mov rdi, r9
  [0x106AD] movd ecx, xmm7
  [0x106B1] movsxd rcx, ecx
  [0x106B4] mov r9, rbx
  [0x106B7] mov rbx, rax
  [0x106BA] add rbx, r15
  [0x106BD] call rbx
  [0x106BF] mov r9, [rsp+0x30]
  [0x106C7] mov r8d, [r15+r9*1+0x14]
  [0x106CC] movzx r9, word ptr [r15+r8*1+0x38]
  [0x106D2] mov r8d, 0x03
  [0x106D8] and r9, r8
  [0x106DB] xor r8, r8
  [0x106DE] cmp r9, r8
  [0x106E1] jz 0x00000000000106F2
  [0x106E7] mov r8d, 0x01
  [0x106ED] jmp 0x00000000000106F8
  [0x106F2] mov r8d, 0x05
  [0x106F8] lea r9, [0x00000000000106FF]
  [0x106FF] sub r9, r15
  [0x10702] mov rdi, [rsp+0x68]
  [0x1070A] mov rsi, [rsp+0x70]
  [0x10712] mov rdx, rax
  [0x10715] mov rcx, [rsp+0x28]
  [0x1071D] mov rax, [rsp+0x58]
  [0x10725] mov rbx, rax
  [0x10728] add rbx, r15
  [0x1072B] call rbx
  [0x1072D] jmp 0x0000000000010735
  [0x10732] mov rax, r14
  [0x10735] mov r9, [rsp+0x20]
  [0x1073D] mov r8, r9
  [0x10740] mov r9d, 0x01
  [0x10746] add r8, r9
  [0x10749] mov r9, r8
  [0x1074C] mov [rsp+0x20], r9
  [0x10754] movsxd r8, dword ptr [r15+r11*1]
  [0x10758] mov r9, [rsp+0x20]
  [0x10760] cmp r9, r8
  [0x10763] jl 0x0000000000010104
  [0x10769] mov r9, r14
  [0x1076C] jmp 0x0000000000010774
  [0x10771] mov r9, r14
  [0x10774] mov r9d, 0x01
  [0x1077A] add r12, r9
  [0x1077D] mov r9, [rsp+0x108]
  [0x10785] movsxd r8, dword ptr [r15+r9*1]
  [0x10789] cmp r12, r8
  [0x1078C] jl 0x00000000000100A8
  [0x10792] mov r9, r14
  [0x10795] jmp 0x000000000001079D
  [0x1079A] mov r9, r14
  [0x1079D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x107A5] mov r8, r14
  [0x107A8] cmp r9, r8
  [0x107AB] jz 0x00000000000107E4
  [0x107B1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x107B9] mov r8, r14
  [0x107BC] cmp r9, r8
  [0x107BF] jnz 0x00000000000107CD
  [0x107C5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x107CD] mov r8, r14
  [0x107D0] mov rcx, r14
  [0x107D3] cmp r9, r8
  [0x107D6] jnz 0x00000000000107E1
  [0x107DC] lea rcx, [r14+0x08]
  [0x107E1] mov r9, rcx
  [0x107E4] mov r8, r14
  [0x107E7] cmp r9, r8
  [0x107EA] jz 0x0000000000010BF3
  [0x107F0] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x107F8] xor r12, r12
  [0x107FB] jmp 0x0000000000010BD6
  [0x10800] mov r11d, 0xA30
  [0x10806] imul r11d, r12d
  [0x1080A] movsxd r11, r11d
  [0x1080D] mov r8d, 0x60
  [0x10813] mov r9, [rsp+0x108]
  [0x1081B] add r8, r9
  [0x1081E] add r11, r8
  [0x10821] mov r9d, [r15+r11*1+0x10]
  [0x10826] lea r8, [r14+0xAFECAFE]
  [0x1082E] cmp r9, r8
  [0x10831] jnz 0x0000000000010BCA
  [0x10837] mov r9d, [r15+r11*1+0x2C]
  [0x1083C] mov r9d, [r15+r9*1+0x78]
  [0x10841] mov r8d, [r15+r9*1+0x118]
  [0x10849] mov r9, r8
  [0x1084C] mov [rsp+0x38], r9
  [0x10854] xor r8, r8
  [0x10857] mov r9, r8
  [0x1085A] mov [rsp+0x40], r9
  [0x10862] jmp 0x0000000000010BA5
  [0x10867] mov r9, [rsp+0x40]
  [0x1086F] mov r8, r9
  [0x10872] shl r8, 0x06
  [0x10876] mov ecx, 0x0C
  [0x1087B] mov r9, [rsp+0x38]
  [0x10883] add rcx, r9
  [0x10886] add r8, rcx
  [0x10889] mov r8d, [r15+r8*1+0x08]
  [0x1088E] mov r9, r8
  [0x10891] mov [rsp+0x50], r9
  [0x10899] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x108A1] mov eax, [r15+r9*1+0x34]
  [0x108A6] lea rsi, [r14+0xAFECAFE]
  [0x108AE] lea rdx, [r14+0xAFECAFE]
  [0x108B6] movss xmm7, dword ptr [0x00000000000108BE]
  [0x108BE] mov r8, r14
  [0x108C1] mov r9, r14
  [0x108C4] mov rbx, r9
  [0x108C7] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x108CF] mov r9, [rsp+0x50]
  [0x108D7] mov rdi, r9
  [0x108DA] movd ecx, xmm7
  [0x108DE] movsxd rcx, ecx
  [0x108E1] mov r9, rbx
  [0x108E4] mov rbx, rax
  [0x108E7] add rbx, r15
  [0x108EA] call rbx
  [0x108EC] mov r9, [rsp+0x50]
  [0x108F4] mov r8d, [r15+r9*1+0x14]
  [0x108F9] movsxd rsi, dword ptr [r15+r8*1+0x14]
  [0x108FE] mov r9, rax
  [0x10901] mov r8, r14
  [0x10904] cmp r9, r8
  [0x10907] jz 0x000000000001094E
  [0x1090D] lea r9, [r14+0x08]
  [0x10912] mov r8, r14
  [0x10915] cmp rbp, r9
  [0x10918] jnz 0x0000000000010923
  [0x1091E] lea r8, [r14+0x08]
  [0x10923] mov r9, r8
  [0x10926] mov r8, r14
  [0x10929] cmp r9, r8
  [0x1092C] jnz 0x000000000001094E
  [0x10932] lea r9, [r14+0xAFECAFE]
  [0x1093A] mov r8, r14
  [0x1093D] cmp rbp, r9
  [0x10940] jnz 0x000000000001094B
  [0x10946] lea r8, [r14+0x08]
  [0x1094B] mov r9, r8
  [0x1094E] mov r8, r14
  [0x10951] cmp r9, r8
  [0x10954] jz 0x0000000000010A05
  [0x1095A] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10962] lea r8, [r14+0x08]
  [0x10967] mov ecx, 0x44
  [0x1096C] mov rdx, rax
  [0x1096F] xor r9, r9
  [0x10972] add rdx, r9
  [0x10975] mov r9d, 0x10
  [0x1097B] add rax, r9
  [0x1097E] mov r9, r8
  [0x10981] mov [rsp+0xC0], r9
  [0x10989] mov r9, rcx
  [0x1098C] mov [rsp+0xE8], r9
  [0x10994] mov r9, rdx
  [0x10997] mov [rsp+0xD8], r9
  [0x1099F] mov r9, rax
  [0x109A2] mov [rsp+0xE0], r9
  [0x109AA] mov r9d, [r15+r11*1-0x04]
  [0x109AF] mov r9d, [r15+r9*1+0x38]
  [0x109B4] mov rdi, r11
  [0x109B7] add r9, r15
  [0x109BA] call r9
  [0x109BD] mov r9, r14
  [0x109C0] cmp rax, r9
  [0x109C3] jz 0x00000000000109D4
  [0x109C9] mov r8d, 0x80808000
  [0x109CF] jmp 0x00000000000109DA
  [0x109D4] mov r8d, 0x80800080
  [0x109DA] mov rdi, [rsp+0xC0]
  [0x109E2] mov rsi, [rsp+0xE8]
  [0x109EA] mov rdx, [rsp+0xD8]
  [0x109F2] mov rcx, [rsp+0xE0]
  [0x109FA] add r10, r15
  [0x109FD] call r10
  [0x10A00] jmp 0x0000000000010A08
  [0x10A05] mov rax, r14
  [0x10A08] lea r9, [r14+0x08]
  [0x10A0D] mov r8, r14
  [0x10A10] cmp rbp, r9
  [0x10A13] jnz 0x0000000000010A1E
  [0x10A19] lea r8, [r14+0x08]
  [0x10A1E] mov r9, r8
  [0x10A21] mov r8, r14
  [0x10A24] cmp r9, r8
  [0x10A27] jnz 0x0000000000010A49
  [0x10A2D] lea r9, [r14+0xAFECAFE]
  [0x10A35] mov r8, r14
  [0x10A38] cmp rbp, r9
  [0x10A3B] jnz 0x0000000000010A46
  [0x10A41] lea r8, [r14+0x08]
  [0x10A46] mov r9, r8
  [0x10A49] mov r8, r14
  [0x10A4C] cmp r9, r8
  [0x10A4F] jz 0x0000000000010B83
  [0x10A55] mov r9, [rsp+0x50]
  [0x10A5D] mov r8d, [r15+r9*1+0x14]
  [0x10A62] mov r10d, [r15+r8*1+0x0C]
  [0x10A67] mov r9, r14
  [0x10A6A] cmp r10, r9
  [0x10A6D] jz 0x0000000000010B7B
  [0x10A73] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10A7B] mov edi, [r15+r10*1-0x04]
  [0x10A80] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10A88] add r9, r15
  [0x10A8B] call r9
  [0x10A8E] mov r9, r14
  [0x10A91] cmp rax, r9
  [0x10A94] jz 0x0000000000010AB6
  [0x10A9A] mov r9, r10
  [0x10A9D] mov r9d, [r15+r9*1+0x74]
  [0x10AA2] xor r8, r8
  [0x10AA5] mov rax, r14
  [0x10AA8] cmp r9, r8
  [0x10AAB] jz 0x0000000000010AB6
  [0x10AB1] lea rax, [r14+0x08]
  [0x10AB6] mov r9, r14
  [0x10AB9] cmp rax, r9
  [0x10ABC] jz 0x0000000000010B73
  [0x10AC2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10ACA] lea rdi, [r14+0x08]
  [0x10ACF] mov esi, 0x44
  [0x10AD4] mov edx, 0x0C
  [0x10AD9] mov r8, r10
  [0x10ADC] mov r8d, [r15+r8*1+0x6C]
  [0x10AE1] add rdx, r8
  [0x10AE4] mov ecx, 0x80FFFFFF
  [0x10AE9] add r9, r15
  [0x10AEC] call r9
  [0x10AEF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10AF7] lea rdi, [r14+0x08]
  [0x10AFC] mov esi, 0x43
  [0x10B01] mov rdx, rsp
  [0x10B04] sub rdx, r15
  [0x10B07] mov r8d, 0x6C
  [0x10B0D] mov rcx, r10
  [0x10B10] mov ecx, [r15+rcx*1+0x74]
  [0x10B15] add r8, rcx
  [0x10B18] mov ecx, 0x7C
  [0x10B1D] mov rax, r10
  [0x10B20] mov eax, [r15+rax*1+0x74]
  [0x10B25] add rcx, rax
  [0x10B28] vmovaps xmm6, [r15+r8*1]
  [0x10B2E] vmovaps xmm5, [r15+rcx*1]
  [0x10B34] vmovaps xmm7, [0x0000000000010B3C]
  [0x10B3C] vaddps xmm6, xmm6, xmm5
  [0x10B40] vblendps xmm6, xmm6, xmm7, 0x08
  [0x10B46] vmovaps [r15+rdx*1], xmm6
  [0x10B4C] mov r8d, [r15+r10*1+0x74]
  [0x10B51] movss xmm7, dword ptr [r15+r8*1+0x88]
  [0x10B5B] mov r8d, 0x80000080
  [0x10B61] movd ecx, xmm7
  [0x10B65] movsxd rcx, ecx
  [0x10B68] add r9, r15
  [0x10B6B] call r9
  [0x10B6E] jmp 0x0000000000010B76
  [0x10B73] mov rax, r14
  [0x10B76] jmp 0x0000000000010B7E
  [0x10B7B] mov rax, r14
  [0x10B7E] jmp 0x0000000000010B86
  [0x10B83] mov rax, r14
  [0x10B86] mov r9, [rsp+0x40]
  [0x10B8E] mov r8, r9
  [0x10B91] mov r9d, 0x01
  [0x10B97] add r8, r9
  [0x10B9A] mov r9, r8
  [0x10B9D] mov [rsp+0x40], r9
  [0x10BA5] mov r9, [rsp+0x38]
  [0x10BAD] movsxd r8, dword ptr [r15+r9*1]
  [0x10BB1] mov r9, [rsp+0x40]
  [0x10BB9] cmp r9, r8
  [0x10BBC] jl 0x0000000000010867
  [0x10BC2] mov r9, r14
  [0x10BC5] jmp 0x0000000000010BCD
  [0x10BCA] mov r9, r14
  [0x10BCD] mov r9d, 0x01
  [0x10BD3] add r12, r9
  [0x10BD6] mov r9, [rsp+0x108]
  [0x10BDE] movsxd r8, dword ptr [r15+r9*1]
  [0x10BE2] cmp r12, r8
  [0x10BE5] jl 0x0000000000010800
  [0x10BEB] mov r9, r14
  [0x10BEE] jmp 0x0000000000010BF6
  [0x10BF3] mov r9, r14
  [0x10BF6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10BFE] mov r8, r14
  [0x10C01] cmp r9, r8
  [0x10C04] jz 0x0000000000010C32
  [0x10C0A] mov r9, [rsp+0x108]
  [0x10C12] mov r8d, [r15+r9*1-0x04]
  [0x10C17] mov r8d, [r15+r8*1+0x68]
  [0x10C1C] mov r9, [rsp+0x108]
  [0x10C24] mov rdi, r9
  [0x10C27] add r8, r15
  [0x10C2A] call r8
  [0x10C2D] jmp 0x0000000000010C35
  [0x10C32] mov rbp, r14
  [0x10C35] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C3D] mov r8, r14
  [0x10C40] cmp r9, r8
  [0x10C43] jnz 0x0000000000010C51
  [0x10C49] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C51] mov r8, r14
  [0x10C54] cmp r9, r8
  [0x10C57] jz 0x00000000000111B7
  [0x10C5D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C65] mov r8, r14
  [0x10C68] cmp r9, r8
  [0x10C6B] jz 0x0000000000010C7F
  [0x10C71] mov r9d, [r15+r9*1]
  [0x10C75] mov ebp, [r15+r9*1+0x18]
  [0x10C7A] jmp 0x0000000000010C82
  [0x10C7F] mov rbp, r14
  [0x10C82] mov r9, r14
  [0x10C85] cmp rbp, r9
  [0x10C88] jnz 0x0000000000010CB4
  [0x10C8E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10C96] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10C9E] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10CA6] add r9, r15
  [0x10CA9] call r9
  [0x10CAC] mov rbp, rax
  [0x10CAF] jmp 0x0000000000010CB7
  [0x10CB4] mov rax, r14
  [0x10CB7] mov r9, rbp
  [0x10CBA] mov r8, r14
  [0x10CBD] cmp r9, r8
  [0x10CC0] jz 0x0000000000010CE4
  [0x10CC6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10CCE] mov edi, [r15+rbp*1-0x04]
  [0x10CD3] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10CDB] add r9, r15
  [0x10CDE] call r9
  [0x10CE1] mov r9, rax
  [0x10CE4] mov r8, r14
  [0x10CE7] cmp r9, r8
  [0x10CEA] jz 0x0000000000010F5D
  [0x10CF0] mov r9, rbp
  [0x10CF3] mov r11d, [r15+r9*1+0x30]
  [0x10CF8] mov r12d, 0x0C
  [0x10CFE] mov r9, rbp
  [0x10D01] mov r9d, [r15+r9*1+0x6C]
  [0x10D06] add r12, r9
  [0x10D09] mov r9, r14
  [0x10D0C] cmp r11, r9
  [0x10D0F] jz 0x0000000000010E71
  [0x10D15] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10D1D] lea rdi, [r14+0x08]
  [0x10D22] mov esi, 0x44
  [0x10D27] mov r8d, [r15+r11*1+0x14]
  [0x10D2C] mov r8d, [r15+r8*1+0x0C]
  [0x10D31] mov rcx, r14
  [0x10D34] cmp r8, rcx
  [0x10D37] jz 0x0000000000010D47
  [0x10D3D] mov ecx, 0x8080FF80
  [0x10D42] jmp 0x0000000000010D4C
  [0x10D47] mov ecx, 0x800000FF
  [0x10D4C] mov rdx, r12
  [0x10D4F] add r9, r15
  [0x10D52] call r9
  [0x10D55] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10D5D] mov [rsp+0x60], r9
  [0x10D65] lea r9, [r14+0x08]
  [0x10D6A] mov [rsp+0x80], r9
  [0x10D72] mov r9d, 0x44
  [0x10D78] mov [rsp+0x78], r9
  [0x10D80] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10D88] mov eax, [r15+r9*1+0x38]
  [0x10D8D] lea rsi, [r14+0xAFECAFE]
  [0x10D95] lea rdx, [r14+0xAFECAFE]
  [0x10D9D] movss xmm7, dword ptr [0x0000000000010DA5]
  [0x10DA5] mov r8, r14
  [0x10DA8] mov r9, r14
  [0x10DAB] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10DB3] mov rdi, r11
  [0x10DB6] movd ecx, xmm7
  [0x10DBA] movsxd rcx, ecx
  [0x10DBD] mov rbx, rax
  [0x10DC0] add rbx, r15
  [0x10DC3] call rbx
  [0x10DC5] mov r9d, [r15+r11*1+0x14]
  [0x10DCA] movzx r9, word ptr [r15+r9*1+0x38]
  [0x10DD0] mov r8d, 0x03
  [0x10DD6] and r9, r8
  [0x10DD9] xor r8, r8
  [0x10DDC] cmp r9, r8
  [0x10DDF] jz 0x0000000000010DF0
  [0x10DE5] mov r8d, 0x01
  [0x10DEB] jmp 0x0000000000010DF6
  [0x10DF0] mov r8d, 0x01
  [0x10DF6] lea r9, [0x0000000000010DFD]
  [0x10DFD] sub r9, r15
  [0x10E00] mov rdi, [rsp+0x80]
  [0x10E08] mov rsi, [rsp+0x78]
  [0x10E10] mov rdx, rax
  [0x10E13] mov rcx, r12
  [0x10E16] mov rax, [rsp+0x60]
  [0x10E1E] mov rbx, rax
  [0x10E21] add rbx, r15
  [0x10E24] call rbx
  [0x10E26] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10E2E] lea rdi, [r14+0x08]
  [0x10E33] mov esi, 0x44
  [0x10E38] mov r9d, 0x20000
  [0x10E3E] mov r8, rbp
  [0x10E41] mov r8d, [r15+r8*1+0x34]
  [0x10E46] mov r8d, [r15+r8*1]
  [0x10E4A] add r9, r8
  [0x10E4D] mov edx, [r15+r9*1]
  [0x10E51] mov r8d, 0x01
  [0x10E57] lea r9, [0x0000000000010E5E]
  [0x10E5E] sub r9, r15
  [0x10E61] mov rcx, r12
  [0x10E64] mov rbx, rax
  [0x10E67] add rbx, r15
  [0x10E6A] call rbx
  [0x10E6C] jmp 0x0000000000010E74
  [0x10E71] mov rax, r14
  [0x10E74] mov r9, rbp
  [0x10E77] mov r9d, [r15+r9*1+0x78]
  [0x10E7C] xor r8, r8
  [0x10E7F] cmp r9, r8
  [0x10E82] jz 0x0000000000010EAD
  [0x10E88] mov r9, rbp
  [0x10E8B] mov edi, [r15+r9*1+0x78]
  [0x10E90] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10E98] mov r9d, [r15+rdi*1-0x04]
  [0x10E9D] mov r9d, [r15+r9*1+0x38]
  [0x10EA2] add r9, r15
  [0x10EA5] call r9
  [0x10EA8] jmp 0x0000000000010EB0
  [0x10EAD] mov rax, r14
  [0x10EB0] mov r9, rbp
  [0x10EB3] mov r9d, [r15+r9*1+0x7C]
  [0x10EB8] xor r8, r8
  [0x10EBB] cmp r9, r8
  [0x10EBE] jz 0x0000000000010EE1
  [0x10EC4] mov r9, rbp
  [0x10EC7] mov edi, [r15+r9*1+0x7C]
  [0x10ECC] mov r9d, [r15+rdi*1-0x04]
  [0x10ED1] mov r9d, [r15+r9*1+0x34]
  [0x10ED6] add r9, r15
  [0x10ED9] call r9
  [0x10EDC] jmp 0x0000000000010EE4
  [0x10EE1] mov r12, r14
  [0x10EE4] mov r9, rbp
  [0x10EE7] mov r9d, [r15+r9*1+0x84]
  [0x10EEF] xor r8, r8
  [0x10EF2] cmp r9, r8
  [0x10EF5] jz 0x0000000000010F1B
  [0x10EFB] mov r9, rbp
  [0x10EFE] mov edi, [r15+r9*1+0x84]
  [0x10F06] mov r9d, [r15+rdi*1-0x04]
  [0x10F0B] mov r9d, [r15+r9*1+0x34]
  [0x10F10] add r9, r15
  [0x10F13] call r9
  [0x10F16] jmp 0x0000000000010F1E
  [0x10F1B] mov r12, r14
  [0x10F1E] mov r9, rbp
  [0x10F21] mov r9d, [r15+r9*1+0x88]
  [0x10F29] xor r8, r8
  [0x10F2C] cmp r9, r8
  [0x10F2F] jz 0x0000000000010F55
  [0x10F35] mov r9, rbp
  [0x10F38] mov edi, [r15+r9*1+0x88]
  [0x10F40] mov r9d, [r15+rdi*1-0x04]
  [0x10F45] mov r9d, [r15+r9*1+0x34]
  [0x10F4A] add r9, r15
  [0x10F4D] call r9
  [0x10F50] jmp 0x0000000000010F58
  [0x10F55] mov rax, r14
  [0x10F58] jmp 0x0000000000010F60
  [0x10F5D] mov rax, r14
  [0x10F60] mov r9, rbp
  [0x10F63] mov r8, r14
  [0x10F66] cmp r9, r8
  [0x10F69] jz 0x0000000000010FCF
  [0x10F6F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10F77] mov r8, rbp
  [0x10F7A] mov edi, [r15+r8*1-0x04]
  [0x10F7F] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10F87] add r9, r15
  [0x10F8A] call r9
  [0x10F8D] mov r9, rax
  [0x10F90] mov r8, r14
  [0x10F93] cmp r9, r8
  [0x10F96] jz 0x0000000000010FCF
  [0x10F9C] mov r9, rbp
  [0x10F9F] mov r9d, [r15+r9*1+0x74]
  [0x10FA4] xor r8, r8
  [0x10FA7] mov rcx, r14
  [0x10FAA] cmp r9, r8
  [0x10FAD] jz 0x0000000000010FB8
  [0x10FB3] lea rcx, [r14+0x08]
  [0x10FB8] mov r9, rcx
  [0x10FBB] mov r8, r14
  [0x10FBE] cmp r9, r8
  [0x10FC1] jz 0x0000000000010FCF
  [0x10FC7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10FCF] mov r8, r14
  [0x10FD2] cmp r9, r8
  [0x10FD5] jz 0x0000000000011061
  [0x10FDB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10FE3] lea rdi, [r14+0x08]
  [0x10FE8] mov esi, 0x43
  [0x10FED] lea rdx, [rsp+0x10]
  [0x10FF2] sub rdx, r15
  [0x10FF5] mov r8d, 0x6C
  [0x10FFB] mov rcx, rbp
  [0x10FFE] mov ecx, [r15+rcx*1+0x74]
  [0x11003] add r8, rcx
  [0x11006] mov ecx, 0x7C
  [0x1100B] mov rax, rbp
  [0x1100E] mov eax, [r15+rax*1+0x74]
  [0x11013] add rcx, rax
  [0x11016] vmovaps xmm6, [r15+r8*1]
  [0x1101C] vmovaps xmm5, [r15+rcx*1]
  [0x11022] vmovaps xmm7, [0x000000000001102A]
  [0x1102A] vaddps xmm6, xmm6, xmm5
  [0x1102E] vblendps xmm6, xmm6, xmm7, 0x08
  [0x11034] vmovaps [r15+rdx*1], xmm6
  [0x1103A] mov r8d, [r15+rbp*1+0x74]
  [0x1103F] movss xmm7, dword ptr [r15+r8*1+0x88]
  [0x11049] mov r8d, 0x80000080
  [0x1104F] movd ecx, xmm7
  [0x11053] movsxd rcx, ecx
  [0x11056] add r9, r15
  [0x11059] call r9
  [0x1105C] jmp 0x0000000000011064
  [0x11061] mov rax, r14
  [0x11064] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1106C] mov r8, r14
  [0x1106F] cmp r9, r8
  [0x11072] jz 0x0000000000011080
  [0x11078] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11080] mov r8, r14
  [0x11083] cmp r9, r8
  [0x11086] jz 0x00000000000111AF
  [0x1108C] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11094] mov edi, [r15+r14*1+0xBADBEEF]
  [0x1109C] add r9, r15
  [0x1109F] call r9
  [0x110A2] mov rbp, rax
  [0x110A5] mov r9, r14
  [0x110A8] cmp rbp, r9
  [0x110AB] jz 0x00000000000111A7
  [0x110B1] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x110B9] mov eax, [r15+r9*1+0x34]
  [0x110BE] lea rsi, [r14+0xAFECAFE]
  [0x110C6] lea rdx, [r14+0xAFECAFE]
  [0x110CE] movss xmm7, dword ptr [0x00000000000110D6]
  [0x110D6] mov r8, r14
  [0x110D9] mov r9, r14
  [0x110DC] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x110E4] mov rdi, rbp
  [0x110E7] movd ecx, xmm7
  [0x110EB] movsxd rcx, ecx
  [0x110EE] mov rbx, rax
  [0x110F1] add rbx, r15
  [0x110F4] call rbx
  [0x110F6] mov r9d, [r15+rbp*1+0x14]
  [0x110FB] movsxd rsi, dword ptr [r15+r9*1+0x14]
  [0x11100] mov r9, r14
  [0x11103] cmp rax, r9
  [0x11106] jz 0x000000000001119F
  [0x1110C] mov r12d, [r15+r14*1+0xBADBEEF]
  [0x11114] lea r11, [r14+0x08]
  [0x11119] mov r10d, 0x44
  [0x1111F] mov r8, rax
  [0x11122] xor r9, r9
  [0x11125] add r8, r9
  [0x11128] mov r9, r8
  [0x1112B] mov [rsp+0xB8], r9
  [0x11133] mov r9d, 0x10
  [0x11139] add rax, r9
  [0x1113C] mov r9, rax
  [0x1113F] mov [rsp+0xC8], r9
  [0x11147] mov r9d, [r15+rbp*1+0x14]
  [0x1114C] mov edi, [r15+r9*1+0x10]
  [0x11151] mov r9d, [r15+rdi*1-0x04]
  [0x11156] mov r9d, [r15+r9*1+0x38]
  [0x1115B] add r9, r15
  [0x1115E] call r9
  [0x11161] mov r9, r14
  [0x11164] cmp rax, r9
  [0x11167] jz 0x0000000000011178
  [0x1116D] mov r8d, 0x80808000
  [0x11173] jmp 0x000000000001117E
  [0x11178] mov r8d, 0x80800080
  [0x1117E] mov rdi, r11
  [0x11181] mov rsi, r10
  [0x11184] mov rdx, [rsp+0xB8]
  [0x1118C] mov rcx, [rsp+0xC8]
  [0x11194] add r12, r15
  [0x11197] call r12
  [0x1119A] jmp 0x00000000000111A2
  [0x1119F] mov rax, r14
  [0x111A2] jmp 0x00000000000111AA
  [0x111A7] mov rax, r14
  [0x111AA] jmp 0x00000000000111B2
  [0x111AF] mov rax, r14
  [0x111B2] jmp 0x00000000000111BA
  [0x111B7] mov rax, r14
  [0x111BA] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x111C2] mov r8, r14
  [0x111C5] cmp r9, r8
  [0x111C8] jnz 0x00000000000111EA
  [0x111CE] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x111D6] mov r8, r14
  [0x111D9] cmp r9, r8
  [0x111DC] jnz 0x00000000000111EA
  [0x111E2] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x111EA] mov r8, r14
  [0x111ED] cmp r9, r8
  [0x111F0] jz 0x0000000000011229
  [0x111F6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x111FE] mov r8, r14
  [0x11201] cmp r9, r8
  [0x11204] jnz 0x0000000000011212
  [0x1120A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11212] mov r8, r14
  [0x11215] mov rcx, r14
  [0x11218] cmp r9, r8
  [0x1121B] jnz 0x0000000000011226
  [0x11221] lea rcx, [r14+0x08]
  [0x11226] mov r9, rcx
  [0x11229] mov r8, r14
  [0x1122C] cmp r9, r8
  [0x1122F] jz 0x0000000000011262
  [0x11235] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1123D] mov edi, [r15+r14*1+0xBADBEEF]
  [0x11245] lea rsi, [0x000000000001124C]
  [0x1124C] sub rsi, r15
  [0x1124F] mov edx, [r15+r14*1+0xBADBEEF]
  [0x11257] add r9, r15
  [0x1125A] call r9
  [0x1125D] jmp 0x0000000000011265
  [0x11262] mov rax, r14
  [0x11265] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1126D] mov r8, r14
  [0x11270] cmp r9, r8
  [0x11273] jz 0x0000000000011394
  [0x11279] xor rbp, rbp
  [0x1127C] jmp 0x0000000000011377
  [0x11281] mov r12d, 0xA30
  [0x11287] imul r12d, ebp
  [0x1128B] movsxd r12, r12d
  [0x1128E] mov r8d, 0x60
  [0x11294] mov r9, [rsp+0x108]
  [0x1129C] add r8, r9
  [0x1129F] add r12, r8
  [0x112A2] mov r9d, [r12+r15*1+0x10]
  [0x112A7] lea r8, [r14+0xAFECAFE]
  [0x112AF] cmp r9, r8
  [0x112B2] jnz 0x000000000001136B
  [0x112B8] mov r9d, [r12+r15*1+0x2C]
  [0x112BD] mov r9d, [r15+r9*1+0x90]
  [0x112C5] xor r8, r8
  [0x112C8] cmp r9, r8
  [0x112CB] jz 0x0000000000011363
  [0x112D1] mov r9d, [r12+r15*1+0x2C]
  [0x112D6] mov r11d, [r15+r9*1+0x90]
  [0x112DE] movsxd r10, dword ptr [r15+r11*1]
  [0x112E2] jmp 0x000000000001134F
  [0x112E7] mov r9d, 0x01
  [0x112ED] sub r10, r9
  [0x112F0] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x112F8] lea rdi, [r14+0x08]
  [0x112FD] mov esi, 0x43
  [0x11302] mov rdx, r10
  [0x11305] shl rdx, 0x05
  [0x11309] mov r8d, 0x0C
  [0x1130F] add r8, r11
  [0x11312] add rdx, r8
  [0x11315] mov ecx, 0x1C
  [0x1131A] add rcx, r11
  [0x1131D] mov r8, r10
  [0x11320] shl r8, 0x05
  [0x11324] add rcx, r8
  [0x11327] movsxd r8, dword ptr [r12+r15*1+0x0C]
  [0x1132C] xor rax, rax
  [0x1132F] cmp r8, rax
  [0x11332] jnz 0x0000000000011343
  [0x11338] mov r8d, 0x80808000
  [0x1133E] jmp 0x0000000000011349
  [0x11343] mov r8d, 0x808080FF
  [0x11349] add r9, r15
  [0x1134C] call r9
  [0x1134F] xor r9, r9
  [0x11352] cmp r10, r9
  [0x11355] jnz 0x00000000000112E7
  [0x1135B] mov r9, r14
  [0x1135E] jmp 0x0000000000011366
  [0x11363] mov r9, r14
  [0x11366] jmp 0x000000000001136E
  [0x1136B] mov r9, r14
  [0x1136E] mov r9d, 0x01
  [0x11374] add rbp, r9
  [0x11377] mov r9, [rsp+0x108]
  [0x1137F] movsxd r8, dword ptr [r15+r9*1]
  [0x11383] cmp rbp, r8
  [0x11386] jl 0x0000000000011281
  [0x1138C] mov r9, r14
  [0x1138F] jmp 0x0000000000011397
  [0x11394] mov r9, r14
  [0x11397] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1139F] mov r8, r14
  [0x113A2] cmp r9, r8
  [0x113A5] jnz 0x000000000001143F
  [0x113AB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x113B3] mov r8, r14
  [0x113B6] cmp r9, r8
  [0x113B9] jnz 0x000000000001143F
  [0x113BF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x113C7] mov r8, r14
  [0x113CA] cmp r9, r8
  [0x113CD] jnz 0x000000000001143F
  [0x113D3] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x113DB] mov r8, r14
  [0x113DE] cmp r9, r8
  [0x113E1] jnz 0x000000000001143F
  [0x113E7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x113EF] mov r8, r14
  [0x113F2] cmp r9, r8
  [0x113F5] jnz 0x000000000001143F
  [0x113FB] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11403] mov r8, r14
  [0x11406] cmp r9, r8
  [0x11409] jnz 0x000000000001143F
  [0x1140F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x11417] mov r8, r14
  [0x1141A] cmp r9, r8
  [0x1141D] jnz 0x000000000001143F
  [0x11423] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1142B] mov r8, r14
  [0x1142E] cmp r9, r8
  [0x11431] jnz 0x000000000001143F
  [0x11437] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1143F] mov r8, r14
  [0x11442] cmp r9, r8
  [0x11445] jz 0x0000000000011526
  [0x1144B] xor rbp, rbp
  [0x1144E] jmp 0x0000000000011509
  [0x11453] mov r9d, 0xA30
  [0x11459] imul r9d, ebp
  [0x1145D] movsxd r9, r9d
  [0x11460] mov r8, r9
  [0x11463] mov ecx, 0x60
  [0x11468] mov r9, [rsp+0x108]
  [0x11470] add rcx, r9
  [0x11473] add r8, rcx
  [0x11476] mov r9d, [r15+r8*1+0x10]
  [0x1147B] lea rcx, [r14+0xAFECAFE]
  [0x11483] cmp r9, rcx
  [0x11486] jnz 0x00000000000114FD
  [0x1148C] mov r9d, [r15+r8*1+0x2C]
  [0x11491] mov r12d, [r15+r9*1+0x98]
  [0x11499] xor r9, r9
  [0x1149C] cmp r12, r9
  [0x1149F] jz 0x00000000000114F5
  [0x114A5] xor r11, r11
  [0x114A8] jmp 0x00000000000114DE
  [0x114AD] mov r9, r11
  [0x114B0] shl r9, 0x05
  [0x114B4] mov r8d, 0x20
  [0x114BA] add r8, r12
  [0x114BD] add r9, r8
  [0x114C0] mov edi, [r15+r9*1+0x04]
  [0x114C5] mov r9d, [r15+rdi*1-0x04]
  [0x114CA] mov r9d, [r15+r9*1+0x7C]
  [0x114CF] add r9, r15
  [0x114D2] call r9
  [0x114D5] mov r9d, 0x01
  [0x114DB] add r11, r9
  [0x114DE] movsx r9, word ptr [r12+r15*1+0x02]
  [0x114E4] cmp r11, r9
  [0x114E7] jl 0x00000000000114AD
  [0x114ED] mov r9, r14
  [0x114F0] jmp 0x00000000000114F8
  [0x114F5] mov r9, r14
  [0x114F8] jmp 0x0000000000011500
  [0x114FD] mov r9, r14
  [0x11500] mov r9d, 0x01
  [0x11506] add rbp, r9
  [0x11509] mov r9, [rsp+0x108]
  [0x11511] movsxd r8, dword ptr [r15+r9*1]
  [0x11515] cmp rbp, r8
  [0x11518] jl 0x0000000000011453
  [0x1151E] mov r9, r14
  [0x11521] jmp 0x0000000000011529
  [0x11526] mov r9, r14
  [0x11529] add rsp, 0x110
  [0x11530] pop r12
  [0x11532] pop r11
  [0x11534] pop r10
  [0x11536] pop rbp
  [0x11537] pop rbx
  [0x11538] ret


[(method inspect entity-actor)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000C] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10014] mov esi, 0x03
  [0x10019] add r9, r15
  [0x1001C] call r9
  [0x1001F] mov rdi, rbx
  [0x10022] mov r9, rax
  [0x10025] add r9, r15
  [0x10028] call r9
  [0x1002B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10033] lea rdi, [r14+0x08]
  [0x10038] lea rsi, [0x000000000001003F]
  [0x1003F] sub rsi, r15
  [0x10042] mov edx, [r15+rbx*1+0x30]
  [0x10047] add r9, r15
  [0x1004A] call r9
  [0x1004D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10055] lea rdi, [r14+0x08]
  [0x1005A] lea rsi, [0x0000000000010061]
  [0x10061] sub rsi, r15
  [0x10064] mov edx, [r15+rbx*1+0x34]
  [0x10069] add r9, r15
  [0x1006C] call r9
  [0x1006F] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10077] lea rdi, [r14+0x08]
  [0x1007C] lea rsi, [0x0000000000010083]
  [0x10083] sub rsi, r15
  [0x10086] movzx rdx, byte ptr [r15+rbx*1+0x38]
  [0x1008C] add r9, r15
  [0x1008F] call r9
  [0x10092] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1009A] lea rdi, [r14+0x08]
  [0x1009F] lea rsi, [0x00000000000100A6]
  [0x100A6] sub rsi, r15
  [0x100A9] movsx rdx, word ptr [r15+rbx*1+0x3A]
  [0x100AF] add r9, r15
  [0x100B2] call r9
  [0x100B5] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100BD] lea rdi, [r14+0x08]
  [0x100C2] lea rsi, [0x00000000000100C9]
  [0x100C9] sub rsi, r15
  [0x100CC] mov edx, 0x3C
  [0x100D1] add rdx, rbx
  [0x100D4] add r9, r15
  [0x100D7] call r9
  [0x100DA] mov rax, rbx
  [0x100DD] pop rbx
  [0x100DE] ret


[anon-function-0]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push rbx
  [0x10003] mov rbx, rdi
  [0x10006] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000E] mov edi, [r15+rbx*1-0x04]
  [0x10013] mov esi, [r15+r14*1+0xBADBEEF]
  [0x1001B] add r9, r15
  [0x1001E] call r9
  [0x10021] mov r9, r14
  [0x10024] cmp rax, r9
  [0x10027] jz 0x00000000000100C8
  [0x1002D] mov r9d, [r15+rbx*1+0x7C]
  [0x10032] xor r8, r8
  [0x10035] cmp r9, r8
  [0x10038] jz 0x0000000000010058
  [0x1003E] mov edi, [r15+rbx*1+0x7C]
  [0x10043] mov r9d, [r15+rdi*1-0x04]
  [0x10048] mov r9d, [r15+r9*1+0x34]
  [0x1004D] add r9, r15
  [0x10050] call r9
  [0x10053] jmp 0x000000000001005B
  [0x10058] mov rbp, r14
  [0x1005B] mov r9d, [r15+rbx*1+0x84]
  [0x10063] xor r8, r8
  [0x10066] cmp r9, r8
  [0x10069] jz 0x000000000001008C
  [0x1006F] mov edi, [r15+rbx*1+0x84]
  [0x10077] mov r9d, [r15+rdi*1-0x04]
  [0x1007C] mov r9d, [r15+r9*1+0x34]
  [0x10081] add r9, r15
  [0x10084] call r9
  [0x10087] jmp 0x000000000001008F
  [0x1008C] mov rbp, r14
  [0x1008F] mov r9d, [r15+rbx*1+0x88]
  [0x10097] xor r8, r8
  [0x1009A] cmp r9, r8
  [0x1009D] jz 0x00000000000100C0
  [0x100A3] mov edi, [r15+rbx*1+0x88]
  [0x100AB] mov r9d, [r15+rdi*1-0x04]
  [0x100B0] mov r9d, [r15+r9*1+0x34]
  [0x100B5] add r9, r15
  [0x100B8] call r9
  [0x100BB] jmp 0x00000000000100C3
  [0x100C0] mov rax, r14
  [0x100C3] jmp 0x00000000000100CB
  [0x100C8] mov rax, r14
  [0x100CB] pop rbx
  [0x100CC] pop rbp
  [0x100CD] pop rbx
  [0x100CE] ret


[process-status-bits]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] mov r10, rdi
  [0x1000B] mov rbx, rsi
  [0x1000E] mov rbp, r10
  [0x10011] xor r9, r9
  [0x10014] mov r8, r14
  [0x10017] cmp rbp, r9
  [0x1001A] jz 0x0000000000010025
  [0x10020] lea r8, [r14+0x08]
  [0x10025] mov r9, r8
  [0x10028] mov r8, r14
  [0x1002B] cmp r9, r8
  [0x1002E] jz 0x0000000000010052
  [0x10034] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1003C] mov edi, [r15+rbp*1-0x04]
  [0x10041] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10049] add r9, r15
  [0x1004C] call r9
  [0x1004F] mov r9, rax
  [0x10052] mov r8, r14
  [0x10055] cmp r9, r8
  [0x10058] jz 0x0000000000010063
  [0x1005E] jmp 0x0000000000010066
  [0x10063] mov rbp, r14
  [0x10066] mov r11, rbp
  [0x10069] mov r9, r11
  [0x1006C] mov r8, r14
  [0x1006F] cmp r9, r8
  [0x10072] jz 0x0000000000010094
  [0x10078] mov r9d, [r15+r11*1+0x74]
  [0x1007D] xor r8, r8
  [0x10080] mov rcx, r14
  [0x10083] cmp r9, r8
  [0x10086] jnz 0x0000000000010091
  [0x1008C] lea rcx, [r14+0x08]
  [0x10091] mov r9, rcx
  [0x10094] mov r8, r14
  [0x10097] cmp r9, r8
  [0x1009A] jz 0x00000000000100AB
  [0x100A0] mov r9, r14
  [0x100A3] mov r11, r9
  [0x100A6] jmp 0x00000000000100AE
  [0x100AB] mov r9, r14
  [0x100AE] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x100B6] lea r12, [0x00000000000100BD]
  [0x100BD] sub r12, r15
  [0x100C0] mov r9, r10
  [0x100C3] mov r8, r14
  [0x100C6] cmp r9, r8
  [0x100C9] jz 0x000000000001011C
  [0x100CF] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D7] mov r9d, [r15+r9*1]
  [0x100DB] mov r8d, [r15+r10*1+0x04]
  [0x100E0] and r9, r8
  [0x100E3] xor r8, r8
  [0x100E6] mov rcx, r14
  [0x100E9] cmp r9, r8
  [0x100EC] jnz 0x00000000000100F7
  [0x100F2] lea rcx, [r14+0x08]
  [0x100F7] mov r9, rcx
  [0x100FA] mov r8, r14
  [0x100FD] cmp r9, r8
  [0x10100] jz 0x000000000001011C
  [0x10106] mov r9d, [r15+r10*1-0x04]
  [0x1010B] mov r9d, [r15+r9*1+0x40]
  [0x10110] mov rdi, r10
  [0x10113] add r9, r15
  [0x10116] call r9
  [0x10119] mov r9, rax
  [0x1011C] mov r8, r14
  [0x1011F] cmp r9, r8
  [0x10122] jz 0x0000000000010132
  [0x10128] mov edx, 0x72
  [0x1012D] jmp 0x0000000000010137
  [0x10132] mov edx, 0x20
  [0x10137] mov r9, r11
  [0x1013A] mov r8, r14
  [0x1013D] cmp r9, r8
  [0x10140] jz 0x0000000000010170
  [0x10146] mov r9d, [r15+r11*1+0x74]
  [0x1014B] movzx r9, byte ptr [r15+r9*1]
  [0x10150] mov r8d, 0x08
  [0x10156] and r9, r8
  [0x10159] xor r8, r8
  [0x1015C] mov rcx, r14
  [0x1015F] cmp r9, r8
  [0x10162] jz 0x000000000001016D
  [0x10168] lea rcx, [r14+0x08]
  [0x1016D] mov r9, rcx
  [0x10170] mov r8, r14
  [0x10173] cmp r9, r8
  [0x10176] jz 0x0000000000010186
  [0x1017C] mov ecx, 0x64
  [0x10181] jmp 0x000000000001018B
  [0x10186] mov ecx, 0x20
  [0x1018B] mov r9, r11
  [0x1018E] mov r8, r14
  [0x10191] cmp r9, r8
  [0x10194] jz 0x00000000000101C4
  [0x1019A] mov r9d, [r15+r11*1+0x74]
  [0x1019F] movzx r9, byte ptr [r15+r9*1]
  [0x101A4] mov r8d, 0x08
  [0x101AA] and r9, r8
  [0x101AD] xor r8, r8
  [0x101B0] mov rsi, r14
  [0x101B3] cmp r9, r8
  [0x101B6] jz 0x00000000000101C1
  [0x101BC] lea rsi, [r14+0x08]
  [0x101C1] mov r9, rsi
  [0x101C4] mov r8, r14
  [0x101C7] cmp r9, r8
  [0x101CA] jz 0x0000000000010262
  [0x101D0] mov r9d, [r15+r11*1+0x74]
  [0x101D5] movsx r9, byte ptr [r15+r9*1+0x3A]
  [0x101DB] xor r8, r8
  [0x101DE] cmp r9, r8
  [0x101E1] jnz 0x00000000000101F2
  [0x101E7] mov r8d, 0x30
  [0x101ED] jmp 0x000000000001025D
  [0x101F2] mov r8d, 0x01
  [0x101F8] cmp r9, r8
  [0x101FB] jnz 0x000000000001020C
  [0x10201] mov r8d, 0x31
  [0x10207] jmp 0x000000000001025D
  [0x1020C] mov r8d, 0x02
  [0x10212] cmp r9, r8
  [0x10215] jnz 0x0000000000010226
  [0x1021B] mov r8d, 0x32
  [0x10221] jmp 0x000000000001025D
  [0x10226] mov r8d, 0x03
  [0x1022C] cmp r9, r8
  [0x1022F] jnz 0x0000000000010240
  [0x10235] mov r8d, 0x33
  [0x1023B] jmp 0x000000000001025D
  [0x10240] mov r8d, 0x04
  [0x10246] cmp r9, r8
  [0x10249] jnz 0x000000000001025A
  [0x1024F] mov r8d, 0x34
  [0x10255] jmp 0x000000000001025D
  [0x1025A] mov r8, r14
  [0x1025D] jmp 0x0000000000010268
  [0x10262] mov r8d, 0x20
  [0x10268] mov rdi, rbx
  [0x1026B] mov rsi, r12
  [0x1026E] add rbp, r15
  [0x10271] call rbp
  [0x10273] xor r9, r9
  [0x10276] pop r12
  [0x10278] pop r11
  [0x1027A] pop r10
  [0x1027C] pop rbp
  [0x1027D] pop rbx
  [0x1027E] ret


[(method inspect entity)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000C] mov edi, [r15+r14*1+0xBADBEEF]
  [0x10014] mov esi, 0x03
  [0x10019] add r9, r15
  [0x1001C] call r9
  [0x1001F] mov rdi, rbx
  [0x10022] mov r9, rax
  [0x10025] add r9, r15
  [0x10028] call r9
  [0x1002B] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10033] lea rdi, [r14+0x08]
  [0x10038] lea rsi, [0x000000000001003F]
  [0x1003F] sub rsi, r15
  [0x10042] mov edx, 0x1C
  [0x10047] add rdx, rbx
  [0x1004A] add r9, r15
  [0x1004D] call r9
  [0x10050] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10058] lea rdi, [r14+0x08]
  [0x1005D] lea rsi, [0x0000000000010064]
  [0x10064] sub rsi, r15
  [0x10067] mov edx, [r15+rbx*1+0x2C]
  [0x1006C] add r9, r15
  [0x1006F] call r9
  [0x10072] mov rax, rbx
  [0x10075] pop rbx
  [0x10076] ret


[(method set-or-clear-status! entity-actor)]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rdi*1+0x14]
  [0x10005] mov r8, r14
  [0x10008] cmp rdx, r8
  [0x1000B] jz 0x0000000000010025
  [0x10011] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10017] or r8, rsi
  [0x1001A] mov [r15+r9*1+0x38], r8w
  [0x10020] jmp 0x0000000000010037
  [0x10025] movzx r8, word ptr [r15+r9*1+0x38]
  [0x1002B] not rsi
  [0x1002E] and r8, rsi
  [0x10031] mov [r15+r9*1+0x38], r8w
  [0x10037] movzx r9, word ptr [r15+r9*1+0x38]
  [0x1003D] ret


[entity-birth-no-kill]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov ebx, [r15+rdi*1+0x14]
  [0x10006] movzx r9, word ptr [r15+rbx*1+0x38]
  [0x1000C] mov r8d, 0x08
  [0x10012] or r9, r8
  [0x10015] mov [r15+rbx*1+0x38], r9w
  [0x1001B] mov r9d, [r15+rbx*1+0x0C]
  [0x10020] mov r8, r14
  [0x10023] cmp r9, r8
  [0x10026] jnz 0x0000000000010052
  [0x1002C] movzx r9, word ptr [r15+rbx*1+0x38]
  [0x10032] mov r8d, 0x05
  [0x10038] and r9, r8
  [0x1003B] xor r8, r8
  [0x1003E] mov rcx, r14
  [0x10041] cmp r9, r8
  [0x10044] jz 0x000000000001004F
  [0x1004A] lea rcx, [r14+0x08]
  [0x1004F] mov r9, rcx
  [0x10052] mov r8, r14
  [0x10055] cmp r9, r8
  [0x10058] jnz 0x0000000000010078
  [0x1005E] mov edi, [r15+rbx*1+0x08]
  [0x10063] mov r9d, [r15+rdi*1-0x04]
  [0x10068] mov r9d, [r15+r9*1+0x68]
  [0x1006D] add r9, r15
  [0x10070] call r9
  [0x10073] jmp 0x000000000001007B
  [0x10078] mov rax, r14
  [0x1007B] mov r9d, [r15+rbx*1+0x0C]
  [0x10080] pop rbx
  [0x10081] ret


[entity-remap-names]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push rbx
  [0x10003] mov rbx, rdi
  [0x10006] movsxd rbp, dword ptr [r15+rbx*1-0x02]
  [0x1000B] jmp 0x00000000000100F9
  [0x10010] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10018] movsxd r8, dword ptr [r15+rbp*1+0x02]
  [0x1001D] movsxd r8, dword ptr [r15+r8*1-0x02]
  [0x10022] sar r8, 0x03
  [0x10026] cvtsi2ss xmm7, r8d
  [0x1002B] movsxd r8, dword ptr [r15+rbp*1+0x02]
  [0x10030] movsxd r8, dword ptr [r15+r8*1+0x02]
  [0x10035] movsxd r8, dword ptr [r15+r8*1-0x02]
  [0x1003A] sar r8, 0x03
  [0x1003E] cvtsi2ss xmm6, r8d
  [0x10043] movsxd r8, dword ptr [r15+rbp*1+0x02]
  [0x10048] movsxd r8, dword ptr [r15+r8*1+0x02]
  [0x1004D] movsxd r8, dword ptr [r15+r8*1+0x02]
  [0x10052] movsxd r8, dword ptr [r15+r8*1-0x02]
  [0x10057] sar r8, 0x03
  [0x1005B] cvtsi2ss xmm5, r8d
  [0x10060] movd edi, xmm7
  [0x10064] movsxd rdi, edi
  [0x10067] movd esi, xmm6
  [0x1006B] movsxd rsi, esi
  [0x1006E] movd edx, xmm5
  [0x10072] movsxd rdx, edx
  [0x10075] add r9, r15
  [0x10078] call r9
  [0x1007B] mov r9, r14
  [0x1007E] cmp rax, r9
  [0x10081] jz 0x00000000000100EC
  [0x10087] lea r9, [r14+0xAFECAFE]
  [0x1008F] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10097] mov rcx, 0xCE6E6B2800000000
  [0x100A1] mov rdx, 0x1000000000000
  [0x100AB] shl r9, 0x20
  [0x100AF] shr r9, 0x20
  [0x100B3] or rcx, r9
  [0x100B6] shl r8, 0x20
  [0x100BA] shr r8, 0x20
  [0x100BE] or rdx, r8
  [0x100C1] movq xmm7, rcx
  [0x100C6] movq xmm1, rdx
  [0x100CB] vpunpcklqdq xmm1, xmm7, xmm1
  [0x100CF] movsxd rsi, dword ptr [r15+rbp*1-0x02]
  [0x100D4] mov r9d, [r15+rax*1-0x04]
  [0x100D9] mov r9d, [r15+r9*1+0x54]
  [0x100DE] mov rdi, rax
  [0x100E1] add r9, r15
  [0x100E4] call r9
  [0x100E7] jmp 0x00000000000100EF
  [0x100EC] mov rax, r14
  [0x100EF] movsxd rbx, dword ptr [r15+rbx*1+0x02]
  [0x100F4] movsxd rbp, dword ptr [r15+rbx*1-0x02]
  [0x100F9] lea r9, [r14-0x0A]
  [0x100FE] cmp rbx, r9
  [0x10101] jnz 0x0000000000010010
  [0x10107] mov r9, r14
  [0x1010A] xor r9, r9
  [0x1010D] pop rbx
  [0x1010E] pop rbp
  [0x1010F] pop rbx
  [0x10110] ret


[(method kill! entity-actor)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push rbx
  [0x10003] mov rbx, rdi
  [0x10006] mov r9d, [r15+rbx*1+0x14]
  [0x1000B] mov edi, [r15+r9*1+0x0C]
  [0x10010] mov r9, r14
  [0x10013] cmp rdi, r9
  [0x10016] jz 0x0000000000010031
  [0x1001C] mov r9d, [r15+rdi*1-0x04]
  [0x10021] mov r9d, [r15+r9*1+0x38]
  [0x10026] add r9, r15
  [0x10029] call r9
  [0x1002C] jmp 0x0000000000010042
  [0x10031] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10039] mov rsi, rbx
  [0x1003C] add r9, r15
  [0x1003F] call r9
  [0x10042] mov rax, rbx
  [0x10045] pop rbx
  [0x10046] pop rbp
  [0x10047] pop rbx
  [0x10048] ret


[entity-count]
[1m[38;2;255;000;000m- [0x10000] [0mxor rax, rax
  [0x10003] xor r9, r9
  [0x10006] jmp 0x00000000000100A3
  [0x1000B] mov r8d, 0xA30
  [0x10011] imul r8d, r9d
  [0x10015] movsxd r8, r8d
  [0x10018] mov ecx, 0x60
  [0x1001D] mov edx, [r15+r14*1+0xBADBEEF]
  [0x10025] add rcx, rdx
  [0x10028] add r8, rcx
  [0x1002B] mov ecx, [r15+r8*1+0x10]
  [0x10030] lea rdx, [r14+0xAFECAFE]
  [0x10038] cmp rcx, rdx
  [0x1003B] jnz 0x0000000000010097
  [0x10041] mov r8d, [r15+r8*1+0x2C]
  [0x10046] mov r8d, [r15+r8*1+0x78]
  [0x1004B] mov r8d, [r15+r8*1+0x118]
  [0x10053] xor rcx, rcx
  [0x10056] jmp 0x0000000000010082
  [0x1005B] mov rdx, rcx
  [0x1005E] shl rdx, 0x06
  [0x10062] mov esi, 0x0C
  [0x10067] add rsi, r8
  [0x1006A] add rdx, rsi
  [0x1006D] mov edx, [r15+rdx*1+0x08]
  [0x10072] mov edx, 0x01
  [0x10077] add rax, rdx
  [0x1007A] mov edx, 0x01
  [0x1007F] add rcx, rdx
  [0x10082] movsxd rdx, dword ptr [r15+r8*1]
  [0x10086] cmp rcx, rdx
  [0x10089] jl 0x000000000001005B
  [0x1008F] mov r8, r14
  [0x10092] jmp 0x000000000001009A
  [0x10097] mov r8, r14
  [0x1009A] mov r8d, 0x01
  [0x100A0] add r9, r8
  [0x100A3] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x100AB] movsxd r8, dword ptr [r15+r8*1]
  [0x100AF] cmp r9, r8
  [0x100B2] jl 0x000000000001000B
  [0x100B8] mov r9, r14
  [0x100BB] ret


[entity-process-count]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x10
  [0x1000C] mov rbp, rdi
  [0x1000F] xor rbx, rbx
  [0x10012] xor r12, r12
  [0x10015] jmp 0x0000000000010164
  [0x1001A] mov r11d, 0xA30
  [0x10020] imul r11d, r12d
  [0x10024] movsxd r11, r11d
  [0x10027] mov r9d, 0x60
  [0x1002D] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10035] add r9, r8
  [0x10038] add r11, r9
  [0x1003B] mov r9d, [r15+r11*1+0x10]
  [0x10040] lea r8, [r14+0xAFECAFE]
  [0x10048] cmp r9, r8
  [0x1004B] jnz 0x0000000000010158
  [0x10051] mov r9d, [r15+r11*1+0x2C]
  [0x10056] mov r9d, [r15+r9*1+0x78]
  [0x1005B] mov r10d, [r15+r9*1+0x118]
  [0x10063] xor r8, r8
  [0x10066] mov r9, r8
  [0x10069] mov [rsp], r9
  [0x10071] jmp 0x000000000001013B
  [0x10076] mov r9, [rsp]
  [0x1007E] mov r8, r9
  [0x10081] shl r8, 0x06
  [0x10085] mov r9d, 0x0C
  [0x1008B] add r9, r10
  [0x1008E] add r8, r9
  [0x10091] mov r9d, [r15+r8*1+0x08]
  [0x10096] mov r8, rbp
  [0x10099] lea rcx, [r14+0xAFECAFE]
  [0x100A1] cmp r8, rcx
  [0x100A4] jnz 0x00000000000100EF
  [0x100AA] mov r9d, [r15+r9*1+0x14]
  [0x100AF] movsxd rsi, dword ptr [r15+r9*1+0x14]
  [0x100B4] mov r9d, [r15+r11*1-0x04]
  [0x100B9] mov r9d, [r15+r9*1+0x38]
  [0x100BE] mov rdi, r11
  [0x100C1] add r9, r15
  [0x100C4] call r9
  [0x100C7] mov r9, r14
  [0x100CA] cmp rax, r9
  [0x100CD] jz 0x00000000000100E7
  [0x100D3] mov r9, rbx
  [0x100D6] mov r8d, 0x01
  [0x100DC] add r9, r8
  [0x100DF] mov rbx, r9
  [0x100E2] jmp 0x00000000000100EA
  [0x100E7] mov r9, r14
  [0x100EA] jmp 0x000000000001011C
  [0x100EF] mov r9d, [r15+r9*1+0x14]
  [0x100F4] mov r9d, [r15+r9*1+0x0C]
  [0x100F9] mov r8, r14
  [0x100FC] cmp r9, r8
  [0x100FF] jz 0x0000000000010119
  [0x10105] mov r9, rbx
  [0x10108] mov r8d, 0x01
  [0x1010E] add r9, r8
  [0x10111] mov rbx, r9
  [0x10114] jmp 0x000000000001011C
  [0x10119] mov r9, r14
  [0x1011C] mov r9, [rsp]
  [0x10124] mov r8, r9
  [0x10127] mov r9d, 0x01
  [0x1012D] add r8, r9
  [0x10130] mov r9, r8
  [0x10133] mov [rsp], r9
  [0x1013B] movsxd r8, dword ptr [r15+r10*1]
  [0x1013F] mov r9, [rsp]
  [0x10147] cmp r9, r8
  [0x1014A] jl 0x0000000000010076
  [0x10150] mov r9, r14
  [0x10153] jmp 0x000000000001015B
  [0x10158] mov r9, r14
  [0x1015B] mov r9d, 0x01
  [0x10161] add r12, r9
  [0x10164] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1016C] movsxd r9, dword ptr [r15+r9*1]
  [0x10170] cmp r12, r9
  [0x10173] jl 0x000000000001001A
  [0x10179] mov r9, r14
  [0x1017C] mov rax, rbx
  [0x1017F] add rsp, 0x10
  [0x10183] pop r12
  [0x10185] pop r11
  [0x10187] pop r10
  [0x10189] pop rbp
  [0x1018A] pop rbx
  [0x1018B] ret


[process-by-ename]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10009] add r9, r15
  [0x1000C] call r9
  [0x1000F] mov r9, r14
  [0x10012] cmp rax, r9
  [0x10015] jz 0x000000000001002A
  [0x1001B] mov r9d, [r15+rax*1+0x14]
  [0x10020] mov eax, [r15+r9*1+0x0C]
  [0x10025] jmp 0x000000000001002D
  [0x1002A] mov rax, r14
  [0x1002D] pop rbx
  [0x1002E] ret


[entity-by-meters]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] xor r9, r9
  [0x10007] jmp 0x000000000001015C
  [0x1000C] mov r8d, 0xA30
  [0x10012] imul r8d, r9d
  [0x10016] movsxd r8, r8d
  [0x10019] mov ecx, 0x60
  [0x1001E] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10026] add rcx, rax
  [0x10029] add r8, rcx
  [0x1002C] mov ecx, [r15+r8*1+0x10]
  [0x10031] lea rax, [r14+0xAFECAFE]
  [0x10039] cmp rcx, rax
  [0x1003C] jnz 0x0000000000010150
  [0x10042] mov r8d, [r15+r8*1+0x2C]
  [0x10047] mov r8d, [r15+r8*1+0x6C]
  [0x1004C] xor rcx, rcx
  [0x1004F] cmp r8, rcx
  [0x10052] jz 0x0000000000010148
  [0x10058] xor rcx, rcx
  [0x1005B] jmp 0x0000000000010131
  [0x10060] mov rax, rcx
  [0x10063] shl rax, 0x05
  [0x10067] mov ebx, 0x20
  [0x1006C] add rbx, r8
  [0x1006F] add rax, rbx
  [0x10072] mov eax, [r15+rax*1+0x04]
  [0x10077] mov ebx, 0x20
  [0x1007C] mov ebp, [r15+rax*1+0x14]
  [0x10081] add rbx, rbp
  [0x10084] movss xmm7, dword ptr [r15+rbx*1]
  [0x1008A] cvttss2si ebp, xmm7
  [0x1008E] movsxd rbp, ebp
  [0x10091] cvtsi2ss xmm7, ebp
  [0x10095] movd xmm6, edi
  [0x10099] mov rbp, r14
  [0x1009C] ucomiss xmm7, xmm6
  [0x1009F] jnz 0x00000000000100AA
  [0x100A5] lea rbp, [r14+0x08]
  [0x100AA] mov r12, r14
  [0x100AD] cmp rbp, r12
  [0x100B0] jz 0x0000000000010110
  [0x100B6] movss xmm7, dword ptr [r15+rbx*1+0x04]
  [0x100BD] cvttss2si ebp, xmm7
  [0x100C1] movsxd rbp, ebp
  [0x100C4] cvtsi2ss xmm7, ebp
  [0x100C8] movd xmm6, esi
  [0x100CC] mov rbp, r14
  [0x100CF] ucomiss xmm7, xmm6
  [0x100D2] jnz 0x00000000000100DD
  [0x100D8] lea rbp, [r14+0x08]
  [0x100DD] mov r12, r14
  [0x100E0] cmp rbp, r12
  [0x100E3] jz 0x0000000000010110
  [0x100E9] movss xmm7, dword ptr [r15+rbx*1+0x08]
  [0x100F0] cvttss2si ebx, xmm7
  [0x100F4] movsxd rbx, ebx
  [0x100F7] cvtsi2ss xmm7, ebx
  [0x100FB] movd xmm6, edx
  [0x100FF] mov rbp, r14
  [0x10102] ucomiss xmm7, xmm6
  [0x10105] jnz 0x0000000000010110
  [0x1010B] lea rbp, [r14+0x08]
  [0x10110] mov rbx, r14
  [0x10113] cmp rbp, rbx
  [0x10116] jz 0x0000000000010126
  [0x1011C] jmp 0x0000000000010177
  [0x10121] jmp 0x0000000000010129
  [0x10126] mov rax, r14
  [0x10129] mov eax, 0x01
  [0x1012E] add rcx, rax
  [0x10131] movsx rax, word ptr [r15+r8*1+0x02]
  [0x10137] cmp rcx, rax
  [0x1013A] jl 0x0000000000010060
  [0x10140] mov r8, r14
  [0x10143] jmp 0x000000000001014B
  [0x10148] mov r8, r14
  [0x1014B] jmp 0x0000000000010153
  [0x10150] mov r8, r14
  [0x10153] mov r8d, 0x01
  [0x10159] add r9, r8
  [0x1015C] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10164] movsxd r8, dword ptr [r15+r8*1]
  [0x10168] cmp r9, r8
  [0x1016B] jl 0x000000000001000C
  [0x10171] mov r9, r14
  [0x10174] mov rax, r14
  [0x10177] pop r12
  [0x10179] pop rbp
  [0x1017A] pop rbx
  [0x1017B] ret


[entity-by-type]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] mov rbx, rdi
  [0x1000B] xor rbp, rbp
  [0x1000E] jmp 0x000000000001010D
  [0x10013] mov r9d, 0xA30
  [0x10019] imul r9d, ebp
  [0x1001D] movsxd r9, r9d
  [0x10020] mov r8d, 0x60
  [0x10026] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x1002E] add r8, rcx
  [0x10031] add r9, r8
  [0x10034] mov r8d, [r15+r9*1+0x10]
  [0x10039] lea rcx, [r14+0xAFECAFE]
  [0x10041] cmp r8, rcx
  [0x10044] jnz 0x0000000000010101
  [0x1004A] mov r9d, [r15+r9*1+0x2C]
  [0x1004F] mov r12d, [r15+r9*1+0x6C]
  [0x10054] xor r9, r9
  [0x10057] cmp r12, r9
  [0x1005A] jz 0x00000000000100F9
  [0x10060] xor r11, r11
  [0x10063] jmp 0x00000000000100E2
  [0x10068] mov r9, r11
  [0x1006B] shl r9, 0x05
  [0x1006F] mov r8d, 0x20
  [0x10075] add r8, r12
  [0x10078] add r9, r8
  [0x1007B] mov r10d, [r15+r9*1+0x04]
  [0x10080] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10088] mov edi, [r15+r10*1-0x04]
  [0x1008D] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10095] add r9, r15
  [0x10098] call r9
  [0x1009B] mov r9, r14
  [0x1009E] cmp rax, r9
  [0x100A1] jz 0x00000000000100BD
  [0x100A7] mov r9d, [r15+r10*1+0x34]
  [0x100AC] mov rax, r14
  [0x100AF] cmp r9, rbx
  [0x100B2] jnz 0x00000000000100BD
  [0x100B8] lea rax, [r14+0x08]
  [0x100BD] mov r9, r14
  [0x100C0] cmp rax, r9
  [0x100C3] jz 0x00000000000100D6
  [0x100C9] mov rax, r10
  [0x100CC] jmp 0x0000000000010128
  [0x100D1] jmp 0x00000000000100D9
  [0x100D6] mov r9, r14
  [0x100D9] mov r9d, 0x01
  [0x100DF] add r11, r9
  [0x100E2] movsx r9, word ptr [r12+r15*1+0x02]
  [0x100E8] cmp r11, r9
  [0x100EB] jl 0x0000000000010068
  [0x100F1] mov r9, r14
  [0x100F4] jmp 0x00000000000100FC
  [0x100F9] mov r9, r14
  [0x100FC] jmp 0x0000000000010104
  [0x10101] mov r9, r14
  [0x10104] mov r9d, 0x01
  [0x1010A] add rbp, r9
  [0x1010D] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10115] movsxd r9, dword ptr [r15+r9*1]
  [0x10119] cmp rbp, r9
  [0x1011C] jl 0x0000000000010013
  [0x10122] mov r9, r14
  [0x10125] mov rax, r14
  [0x10128] pop r12
  [0x1012A] pop r11
  [0x1012C] pop r10
  [0x1012E] pop rbp
  [0x1012F] pop rbx
  [0x10130] ret


[process-entity-status!]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rdi*1+0x30]
  [0x10005] mov r8, r14
  [0x10008] cmp r9, r8
  [0x1000B] jz 0x0000000000010034
  [0x10011] mov r9d, [r15+rdi*1+0x30]
  [0x10016] mov r9d, [r15+r9*1+0x14]
  [0x1001B] mov r9d, [r15+r9*1+0x0C]
  [0x10020] mov r8, r14
  [0x10023] cmp rdi, r9
  [0x10026] jnz 0x0000000000010031
  [0x1002C] lea r8, [r14+0x08]
  [0x10031] mov r9, r8
  [0x10034] mov r8, r14
  [0x10037] cmp r9, r8
  [0x1003A] jz 0x0000000000010087
  [0x10040] mov r9d, [r15+rdi*1+0x30]
  [0x10045] mov r9d, [r15+r9*1+0x14]
  [0x1004A] mov r8, r14
  [0x1004D] cmp rdx, r8
  [0x10050] jz 0x000000000001006A
  [0x10056] movzx r8, word ptr [r15+r9*1+0x38]
  [0x1005C] or r8, rsi
  [0x1005F] mov [r15+r9*1+0x38], r8w
  [0x10065] jmp 0x000000000001007C
  [0x1006A] movzx r8, word ptr [r15+r9*1+0x38]
  [0x10070] not rsi
  [0x10073] and r8, rsi
  [0x10076] mov [r15+r9*1+0x38], r8w
  [0x1007C] movzx rax, word ptr [r15+r9*1+0x38]
  [0x10082] jmp 0x000000000001008A
  [0x10087] xor rax, rax
  [0x1008A] ret


[entity-by-aid]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] xor r9, r9
  [0x10004] jmp 0x00000000000100F6
  [0x10009] mov r8d, 0xA30
  [0x1000F] imul r8d, r9d
  [0x10013] movsxd r8, r8d
  [0x10016] mov ecx, 0x60
  [0x1001B] mov edx, [r15+r14*1+0xBADBEEF]
  [0x10023] add rcx, rdx
  [0x10026] add r8, rcx
  [0x10029] mov ecx, [r15+r8*1+0x10]
  [0x1002E] lea rdx, [r14+0xAFECAFE]
  [0x10036] cmp rcx, rdx
  [0x10039] jnz 0x00000000000100EA
  [0x1003F] mov r8d, [r15+r8*1+0x118]
  [0x10047] xor rcx, rcx
  [0x1004A] cmp r8, rcx
  [0x1004D] jz 0x00000000000100E2
  [0x10053] xor rcx, rcx
  [0x10056] movsxd rdx, dword ptr [r15+r8*1]
  [0x1005A] mov rsi, 0xFFFFFFFFFFFFFFFF
  [0x10061] add rdx, rsi
  [0x10064] xor rsi, rsi
  [0x10067] jmp 0x00000000000100D1
  [0x1006C] mov rsi, rcx
  [0x1006F] mov rax, rdx
  [0x10072] sub rax, rcx
  [0x10075] sar rax, 0x01
  [0x10079] add rsi, rax
  [0x1007C] mov rax, rsi
  [0x1007F] shl rax, 0x06
  [0x10083] mov ebx, 0x0C
  [0x10088] add rbx, r8
  [0x1008B] add rax, rbx
  [0x1008E] mov ebx, [r15+rax*1+0x3C]
  [0x10093] cmp rbx, rdi
  [0x10096] jnz 0x00000000000100AB
  [0x1009C] mov eax, [r15+rax*1+0x08]
  [0x100A1] jmp 0x0000000000010111
  [0x100A6] jmp 0x00000000000100D1
  [0x100AB] cmp rbx, rdi
  [0x100AE] jnb 0x00000000000100C4
  [0x100B4] mov ecx, 0x01
  [0x100B9] add rsi, rcx
  [0x100BC] mov rcx, rsi
  [0x100BF] jmp 0x00000000000100D1
  [0x100C4] mov rdx, 0xFFFFFFFFFFFFFFFF
  [0x100CB] add rsi, rdx
  [0x100CE] mov rdx, rsi
  [0x100D1] cmp rdx, rcx
  [0x100D4] jnl 0x000000000001006C
  [0x100DA] mov r8, r14
  [0x100DD] jmp 0x00000000000100E5
  [0x100E2] mov r8, r14
  [0x100E5] jmp 0x00000000000100ED
  [0x100EA] mov r8, r14
  [0x100ED] mov r8d, 0x01
  [0x100F3] add r9, r8
  [0x100F6] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x100FE] movsxd r8, dword ptr [r15+r8*1]
  [0x10102] cmp r9, r8
  [0x10105] jl 0x0000000000010009
  [0x1010B] mov r9, r14
  [0x1010E] mov rax, r14
  [0x10111] pop rbx
  [0x10112] ret


[entity-by-name]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x60
  [0x1000C] mov [rsp+0x50], rdi
  [0x10014] xor rbp, rbp
  [0x10017] jmp 0x00000000000103FA
  [0x1001C] mov r12d, 0xA30
  [0x10022] imul r12d, ebp
  [0x10026] movsxd r12, r12d
  [0x10029] mov r9d, 0x60
  [0x1002F] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x10037] add r9, r8
  [0x1003A] add r12, r9
  [0x1003D] mov r9d, [r12+r15*1+0x10]
  [0x10042] lea r8, [r14+0xAFECAFE]
  [0x1004A] cmp r9, r8
  [0x1004D] jnz 0x00000000000103EE
  [0x10053] mov r9d, [r12+r15*1+0x2C]
  [0x10058] mov r11d, [r15+r9*1+0x6C]
  [0x1005D] xor r9, r9
  [0x10060] cmp r11, r9
  [0x10063] jz 0x00000000000101A7
  [0x10069] xor r8, r8
  [0x1006C] mov r9, r8
  [0x1006F] mov [rsp+0x08], r9
  [0x10077] jmp 0x0000000000010188
  [0x1007C] mov r9, [rsp+0x08]
  [0x10084] mov r8, r9
  [0x10087] shl r8, 0x05
  [0x1008B] mov r9d, 0x20
  [0x10091] add r9, r11
  [0x10094] add r8, r9
  [0x10097] mov r8d, [r15+r8*1+0x04]
  [0x1009C] mov r9, r8
  [0x1009F] mov [rsp+0x18], r9
  [0x100A7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100AF] mov [rsp+0x28], r9
  [0x100B7] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100BF] mov eax, [r15+r9*1+0x38]
  [0x100C4] lea rsi, [r14+0xAFECAFE]
  [0x100CC] lea rdx, [r14+0xAFECAFE]
  [0x100D4] movss xmm7, dword ptr [0x00000000000100DC]
  [0x100DC] mov r8, r14
  [0x100DF] mov r9, r14
  [0x100E2] mov [rsp+0x40], r9
  [0x100EA] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x100F2] mov r9, [rsp+0x18]
  [0x100FA] mov rdi, r9
  [0x100FD] movd ecx, xmm7
  [0x10101] movsxd rcx, ecx
  [0x10104] mov r9, [rsp+0x40]
  [0x1010C] mov [rsp+0x48], rax
  [0x10114] mov rbx, [rsp+0x48]
  [0x1011C] add rbx, r15
  [0x1011F] call rbx
  [0x10121] mov [rsp+0x48], rbx
  [0x10129] mov rdi, rax
  [0x1012C] mov r9, [rsp+0x50]
  [0x10134] mov rsi, r9
  [0x10137] mov r9, [rsp+0x28]
  [0x1013F] mov r8, r9
  [0x10142] add r8, r15
  [0x10145] call r8
  [0x10148] mov r9, r14
  [0x1014B] cmp rax, r9
  [0x1014E] jz 0x0000000000010166
  [0x10154] mov rax, [rsp+0x18]
  [0x1015C] jmp 0x0000000000010415
  [0x10161] jmp 0x0000000000010169
  [0x10166] mov r9, r14
  [0x10169] mov r9, [rsp+0x08]
  [0x10171] mov r8, r9
  [0x10174] mov r9d, 0x01
  [0x1017A] add r8, r9
  [0x1017D] mov r9, r8
  [0x10180] mov [rsp+0x08], r9
  [0x10188] movsx r8, word ptr [r15+r11*1+0x02]
  [0x1018E] mov r9, [rsp+0x08]
  [0x10196] cmp r9, r8
  [0x10199] jl 0x000000000001007C
  [0x1019F] mov r9, r14
  [0x101A2] jmp 0x00000000000101AA
  [0x101A7] mov r9, r14
  [0x101AA] mov r9d, [r12+r15*1+0x2C]
  [0x101AF] mov r11d, [r15+r9*1+0x98]
  [0x101B7] xor r9, r9
  [0x101BA] cmp r11, r9
  [0x101BD] jz 0x00000000000102E2
  [0x101C3] xor r8, r8
  [0x101C6] mov r9, r8
  [0x101C9] mov [rsp], r9
  [0x101D1] jmp 0x00000000000102C3
  [0x101D6] mov r9, [rsp]
  [0x101DE] mov r8, r9
  [0x101E1] shl r8, 0x05
  [0x101E5] mov r9d, 0x20
  [0x101EB] add r9, r11
  [0x101EE] add r8, r9
  [0x101F1] mov r8d, [r15+r8*1+0x04]
  [0x101F6] mov r9, r8
  [0x101F9] mov [rsp+0x10], r9
  [0x10201] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10209] mov [rsp+0x30], r9
  [0x10211] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10219] mov eax, [r15+r9*1+0x38]
  [0x1021E] lea rsi, [r14+0xAFECAFE]
  [0x10226] lea rdx, [r14+0xAFECAFE]
  [0x1022E] movss xmm7, dword ptr [0x0000000000010236]
  [0x10236] mov r8, r14
  [0x10239] mov r9, r14
  [0x1023C] mov rbx, r9
  [0x1023F] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10247] mov r9, [rsp+0x10]
  [0x1024F] mov rdi, r9
  [0x10252] movd ecx, xmm7
  [0x10256] movsxd rcx, ecx
  [0x10259] mov r9, rbx
  [0x1025C] mov rbx, rax
  [0x1025F] add rbx, r15
  [0x10262] call rbx
  [0x10264] mov rdi, rax
  [0x10267] mov r9, [rsp+0x50]
  [0x1026F] mov rsi, r9
  [0x10272] mov r9, [rsp+0x30]
  [0x1027A] mov r8, r9
  [0x1027D] add r8, r15
  [0x10280] call r8
  [0x10283] mov r9, r14
  [0x10286] cmp rax, r9
  [0x10289] jz 0x00000000000102A1
  [0x1028F] mov rax, [rsp+0x10]
  [0x10297] jmp 0x0000000000010415
  [0x1029C] jmp 0x00000000000102A4
  [0x102A1] mov r9, r14
  [0x102A4] mov r9, [rsp]
  [0x102AC] mov r8, r9
  [0x102AF] mov r9d, 0x01
  [0x102B5] add r8, r9
  [0x102B8] mov r9, r8
  [0x102BB] mov [rsp], r9
  [0x102C3] movsx r8, word ptr [r15+r11*1+0x02]
  [0x102C9] mov r9, [rsp]
  [0x102D1] cmp r9, r8
  [0x102D4] jl 0x00000000000101D6
  [0x102DA] mov r9, r14
  [0x102DD] jmp 0x00000000000102E5
  [0x102E2] mov r9, r14
  [0x102E5] mov r9d, [r12+r15*1+0x2C]
  [0x102EA] mov r12d, [r15+r9*1+0x70]
  [0x102EF] xor r9, r9
  [0x102F2] cmp r12, r9
  [0x102F5] jz 0x00000000000103E6
  [0x102FB] xor r11, r11
  [0x102FE] jmp 0x00000000000103D1
  [0x10303] mov r9d, 0x0C
  [0x10309] mov r8, r11
  [0x1030C] shl r8, 0x02
  [0x10310] add r8, r9
  [0x10313] add r8, r12
  [0x10316] mov r8d, [r15+r8*1]
  [0x1031A] mov r9, r8
  [0x1031D] mov [rsp+0x20], r9
  [0x10325] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1032D] mov [rsp+0x38], r9
  [0x10335] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1033D] mov eax, [r15+r9*1+0x38]
  [0x10342] lea rsi, [r14+0xAFECAFE]
  [0x1034A] lea rdx, [r14+0xAFECAFE]
  [0x10352] movss xmm7, dword ptr [0x000000000001035A]
  [0x1035A] mov r8, r14
  [0x1035D] mov r9, r14
  [0x10360] mov rbx, r9
  [0x10363] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x1036B] mov r9, [rsp+0x20]
  [0x10373] mov rdi, r9
  [0x10376] movd ecx, xmm7
  [0x1037A] movsxd rcx, ecx
  [0x1037D] mov r9, rbx
  [0x10380] mov rbx, rax
  [0x10383] add rbx, r15
  [0x10386] call rbx
  [0x10388] mov rdi, rax
  [0x1038B] mov r9, [rsp+0x50]
  [0x10393] mov rsi, r9
  [0x10396] mov r9, [rsp+0x38]
  [0x1039E] mov r8, r9
  [0x103A1] add r8, r15
  [0x103A4] call r8
  [0x103A7] mov r9, r14
  [0x103AA] cmp rax, r9
  [0x103AD] jz 0x00000000000103C5
  [0x103B3] mov rax, [rsp+0x20]
  [0x103BB] jmp 0x0000000000010415
  [0x103C0] jmp 0x00000000000103C8
  [0x103C5] mov r9, r14
  [0x103C8] mov r9d, 0x01
  [0x103CE] add r11, r9
  [0x103D1] movsxd r9, dword ptr [r12+r15*1]
  [0x103D5] cmp r11, r9
  [0x103D8] jl 0x0000000000010303
  [0x103DE] mov r9, r14
  [0x103E1] jmp 0x00000000000103E9
  [0x103E6] mov r9, r14
  [0x103E9] jmp 0x00000000000103F1
  [0x103EE] mov r9, r14
  [0x103F1] mov r9d, 0x01
  [0x103F7] add rbp, r9
  [0x103FA] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10402] movsxd r9, dword ptr [r15+r9*1]
  [0x10406] cmp rbp, r9
  [0x10409] jl 0x000000000001001C
  [0x1040F] mov r9, r14
  [0x10412] mov rax, r14
  [0x10415] add rsp, 0x60
  [0x10419] pop r12
  [0x1041B] pop r11
  [0x1041D] pop r10
  [0x1041F] pop rbp
  [0x10420] pop rbx
  [0x10421] ret


[(method get-level entity)]
[1m[38;2;255;000;000m- [0x10000] [0mxor r9, r9
  [0x10003] jmp 0x00000000000100AC
  [0x10008] mov eax, 0xA30
  [0x1000D] imul eax, r9d
  [0x10011] movsxd rax, eax
  [0x10014] mov r8d, 0x60
  [0x1001A] mov ecx, [r15+r14*1+0xBADBEEF]
  [0x10022] add r8, rcx
  [0x10025] add rax, r8
  [0x10028] mov r8d, [r15+rax*1+0x10]
  [0x1002D] lea rcx, [r14+0xAFECAFE]
  [0x10035] cmp r8, rcx
  [0x10038] jnz 0x00000000000100A0
  [0x1003E] mov r8, rdi
  [0x10041] mov ecx, [r15+rax*1+0x1C]
  [0x10046] mov rdx, r14
  [0x10049] cmp r8, rcx
  [0x1004C] jl 0x0000000000010057
  [0x10052] lea rdx, [r14+0x08]
  [0x10057] mov r8, rdx
  [0x1005A] mov rcx, r14
  [0x1005D] cmp r8, rcx
  [0x10060] jz 0x0000000000010082
  [0x10066] mov r8, rdi
  [0x10069] mov ecx, [r15+rax*1+0x28]
  [0x1006E] mov rdx, r14
  [0x10071] cmp r8, rcx
  [0x10074] jnl 0x000000000001007F
  [0x1007A] lea rdx, [r14+0x08]
  [0x1007F] mov r8, rdx
  [0x10082] mov rcx, r14
  [0x10085] cmp r8, rcx
  [0x10088] jz 0x0000000000010098
  [0x1008E] jmp 0x00000000000100D4
  [0x10093] jmp 0x000000000001009B
  [0x10098] mov r8, r14
  [0x1009B] jmp 0x00000000000100A3
  [0x100A0] mov r8, r14
  [0x100A3] mov r8d, 0x01
  [0x100A9] add r9, r8
  [0x100AC] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x100B4] movsxd r8, dword ptr [r15+r8*1]
  [0x100B8] cmp r9, r8
  [0x100BB] jl 0x0000000000010008
  [0x100C1] mov r9, r14
  [0x100C4] mov eax, 0x14C0
  [0x100C9] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100D1] add rax, r9
  [0x100D4] ret


[(method kill! entity)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000C] lea rdi, [r14+0x08]
  [0x10011] lea rsi, [0x0000000000010018]
  [0x10018] sub rsi, r15
  [0x1001B] mov rdx, rbx
  [0x1001E] add r9, r15
  [0x10021] call r9
  [0x10024] mov rax, rbx
  [0x10027] pop rbx
  [0x10028] ret


[(method birth! entity)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000C] lea rdi, [r14+0x08]
  [0x10011] lea rsi, [0x0000000000010018]
  [0x10018] sub rsi, r15
  [0x1001B] mov rdx, rbx
  [0x1001E] add r9, r15
  [0x10021] call r9
  [0x10024] mov rax, rbx
  [0x10027] pop rbx
  [0x10028] ret


[(method print entity-perm)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] mov rbx, rdi
  [0x10007] mov eax, [r15+r14*1+0xBADBEEF]
  [0x1000F] lea rdi, [r14+0x08]
  [0x10014] lea rsi, [0x000000000001001B]
  [0x1001B] sub rsi, r15
  [0x1001E] mov edx, [r15+rbx*1+0x0C]
  [0x10023] movzx rcx, byte ptr [r15+rbx*1+0x0B]
  [0x10029] movzx r8, word ptr [r15+rbx*1+0x08]
  [0x1002F] mov r9, [r15+rbx*1]
  [0x10033] mov r10, rbx
  [0x10036] mov rbp, rax
  [0x10039] add rbp, r15
  [0x1003C] call rbp
  [0x1003E] mov rax, rbx
  [0x10041] pop r10
  [0x10043] pop rbp
  [0x10044] pop rbx
  [0x10045] ret


[(method add-to-level! entity)]
[1m[38;2;255;000;000m- [0x10000] [0mmov r9d, [r15+rdx*1+0x118]
  [0x10008] movsxd r9, dword ptr [r15+r9*1]
  [0x1000C] shl r9, 0x06
  [0x10010] mov r8d, 0x0C
  [0x10016] mov eax, [r15+rdx*1+0x118]
  [0x1001E] add r8, rax
  [0x10021] add r9, r8
  [0x10024] mov r8d, [r15+rdx*1+0x118]
  [0x1002C] movsxd r8, dword ptr [r15+r8*1]
  [0x10030] mov eax, 0x01
  [0x10035] add r8, rax
  [0x10038] mov eax, [r15+rdx*1+0x118]
  [0x10040] mov [r15+rax*1], r8d
  [0x10044] mov r8, r14
  [0x10047] mov [r15+r9*1+0x0C], r8d
  [0x1004C] mov [r15+r9*1+0x08], edi
  [0x10051] mov [r15+rdi*1+0x14], r9d
  [0x10056] mov r8d, [r15+rsi*1+0x0C]
  [0x1005B] mov rax, r14
  [0x1005E] cmp r8, rax
  [0x10061] jz 0x000000000001008B
  [0x10067] mov r8d, [r15+rsi*1+0x0C]
  [0x1006C] mov eax, [r15+r8*1+0x04]
  [0x10071] mov [r15+r8*1+0x04], r9d
  [0x10076] mov [r15+r9*1], r8d
  [0x1007A] mov [r15+r9*1+0x04], eax
  [0x1007F] mov [r15+rax*1], r9d
  [0x10083] mov r8, r9
  [0x10086] jmp 0x0000000000010097
  [0x1008B] mov [r15+r9*1], r9d
  [0x1008F] mov [r15+r9*1+0x04], r9d
  [0x10094] mov r8, r9
  [0x10097] mov [r15+rsi*1+0x0C], r9d
  [0x1009C] vmovaps xmm7, [r15+rdi*1+0x1C]
  [0x100A3] vmovaps [r15+r9*1+0x20], xmm7
  [0x100AA] mov r9d, [r15+rdi*1+0x14]
  [0x100AF] mov [r15+r9*1+0x3C], ecx
  [0x100B4] mov r9d, [r15+rdi*1+0x14]
  [0x100B9] mov [r15+r9*1+0x10], edx
  [0x100BE] mov r9d, [r15+rdi*1-0x04]
  [0x100C3] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x100CB] cmp r9, r8
  [0x100CE] jnz 0x0000000000010102
  [0x100D4] mov r9, rdi
  [0x100D7] movzx r9, byte ptr [r15+r9*1+0x38]
  [0x100DD] mov r8, rdi
  [0x100E0] mov r8d, [r15+r8*1+0x14]
  [0x100E5] mov [r15+r8*1+0x3B], r9b
  [0x100EA] mov r9, rdi
  [0x100ED] movsx r9, word ptr [r15+r9*1+0x3A]
  [0x100F3] mov r8d, [r15+rdi*1+0x14]
  [0x100F8] mov [r15+r8*1+0x14], r9d
  [0x100FD] jmp 0x000000000001011F
  [0x10102] xor r9, r9
  [0x10105] mov r8d, [r15+rdi*1+0x14]
  [0x1010A] mov [r15+r8*1+0x3B], r9b
  [0x1010F] xor r9, r9
  [0x10112] mov r8d, [r15+rdi*1+0x14]
  [0x10117] mov [r15+r8*1+0x14], r9d
  [0x1011C] xor r9, r9
  [0x1011F] ret


[(method print entity-links)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] mov rbx, rdi
  [0x10004] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1000C] lea rdi, [r14+0x08]
  [0x10011] lea rsi, [0x0000000000010018]
  [0x10018] sub rsi, r15
  [0x1001B] mov edx, [r15+rbx*1+0x0C]
  [0x10020] mov rcx, rbx
  [0x10023] add r9, r15
  [0x10026] call r9
  [0x10029] mov rax, rbx
  [0x1002C] pop rbx
  [0x1002D] ret


[(method mem-usage drawable-inline-array-actor)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r11
  [0x10004] push r12
  [0x10006] push rbx
  [0x10007] mov rbx, rdi
  [0x1000A] mov rbp, rsi
  [0x1000D] mov r12, rdx
  [0x10010] mov r9d, 0x01
  [0x10016] movsxd r8, dword ptr [r15+rbp*1+0x04]
  [0x1001B] cmp r9, r8
  [0x1001E] jle 0x0000000000010029
  [0x10024] jmp 0x000000000001002C
  [0x10029] mov r9, r8
  [0x1002C] mov [r15+rbp*1+0x04], r9d
  [0x10031] mov r9d, 0x20000
  [0x10037] lea r8, [r14+0xAFECAFE]
  [0x1003F] add r9, r8
  [0x10042] mov r9d, [r15+r9*1]
  [0x10046] mov [r15+rbp*1+0x0C], r9d
  [0x1004B] movsxd r9, dword ptr [r15+rbp*1+0x10]
  [0x10050] mov r8d, 0x01
  [0x10056] add r9, r8
  [0x10059] mov [r15+rbp*1+0x10], r9d
  [0x1005E] mov r9d, 0x20
  [0x10064] movsxd r8, dword ptr [r15+rbp*1+0x14]
  [0x10069] add r8, r9
  [0x1006C] mov [r15+rbp*1+0x14], r8d
  [0x10071] movsxd r8, dword ptr [r15+rbp*1+0x18]
  [0x10076] mov rcx, 0xFFFFFFFFFFFFFFF0
  [0x1007D] mov edx, 0x0F
  [0x10082] add r9, rdx
  [0x10085] and rcx, r9
  [0x10088] add r8, rcx
  [0x1008B] mov [r15+rbp*1+0x18], r8d
  [0x10090] xor r11, r11
  [0x10093] jmp 0x00000000000100CA
  [0x10098] mov rdi, r11
  [0x1009B] shl rdi, 0x05
  [0x1009F] mov r9d, 0x20
  [0x100A5] add r9, rbx
  [0x100A8] add rdi, r9
  [0x100AB] mov r9d, [r15+rdi*1-0x04]
  [0x100B0] mov r9d, [r15+r9*1+0x30]
  [0x100B5] mov rsi, rbp
  [0x100B8] mov rdx, r12
  [0x100BB] add r9, r15
  [0x100BE] call r9
  [0x100C1] mov r9d, 0x01
  [0x100C7] add r11, r9
  [0x100CA] movsx r9, word ptr [r15+rbx*1+0x02]
  [0x100D0] cmp r11, r9
  [0x100D3] jl 0x0000000000010098
  [0x100D9] mov r9, r14
  [0x100DC] xor rax, rax
  [0x100DF] pop rbx
  [0x100E0] pop r12
  [0x100E2] pop r11
  [0x100E4] pop rbp
  [0x100E5] pop rbx
  [0x100E6] ret


[(method debug-print entity-actor)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x20
  [0x1000C] mov [rsp+0x18], rdi
  [0x10014] mov rbp, rsi
  [0x10017] mov r12, rdx
  [0x1001A] mov r9, [rsp+0x18]
  [0x10022] mov r11d, [r15+r9*1+0x34]
  [0x10027] mov r9, r14
  [0x1002A] mov r8, r14
  [0x1002D] cmp r12, r9
  [0x10030] jnz 0x000000000001003B
  [0x10036] lea r8, [r14+0x08]
  [0x1003B] mov r9, r8
  [0x1003E] mov r8, r14
  [0x10041] cmp r9, r8
  [0x10044] jnz 0x00000000000100A1
  [0x1004A] mov r9, r11
  [0x1004D] mov r8, r14
  [0x10050] cmp r9, r8
  [0x10053] jz 0x00000000000100A1
  [0x10059] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10061] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10069] mov rdx, r14
  [0x1006C] mov rcx, r14
  [0x1006F] xor r8, r8
  [0x10072] mov rdi, r11
  [0x10075] add r9, r15
  [0x10078] call r9
  [0x1007B] mov r9, rax
  [0x1007E] mov r8, r14
  [0x10081] cmp r9, r8
  [0x10084] jz 0x00000000000100A1
  [0x1008A] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10092] mov rdi, r11
  [0x10095] mov rsi, r12
  [0x10098] add r9, r15
  [0x1009B] call r9
  [0x1009E] mov r9, rax
  [0x100A1] mov r8, r14
  [0x100A4] cmp r9, r8
  [0x100A7] jz 0x00000000000105B1
  [0x100AD] mov r12d, [r15+r14*1+0xBADBEEF]
  [0x100B5] lea r11, [r14+0x08]
  [0x100BA] lea r9, [0x00000000000100C1]
  [0x100C1] sub r9, r15
  [0x100C4] mov [rsp], r9
  [0x100CC] mov r9, [rsp+0x18]
  [0x100D4] mov r8d, [r15+r9*1+0x14]
  [0x100D9] movsxd r9, dword ptr [r15+r8*1+0x14]
  [0x100DE] mov [rsp+0x08], r9
  [0x100E6] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x100EE] mov eax, [r15+r9*1+0x38]
  [0x100F3] lea rsi, [r14+0xAFECAFE]
  [0x100FB] lea rdx, [r14+0xAFECAFE]
  [0x10103] movss xmm7, dword ptr [0x000000000001010B]
  [0x1010B] mov r8, r14
  [0x1010E] mov r9, r14
  [0x10111] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10119] mov rcx, [rsp+0x18]
  [0x10121] mov rdi, rcx
  [0x10124] movd ecx, xmm7
  [0x10128] movsxd rcx, ecx
  [0x1012B] mov [rsp+0x10], rax
  [0x10133] mov rbx, [rsp+0x10]
  [0x1013B] add rbx, r15
  [0x1013E] call rbx
  [0x10140] mov [rsp+0x10], rbx
  [0x10148] mov rdi, r11
  [0x1014B] mov rsi, [rsp]
  [0x10153] mov rdx, [rsp+0x08]
  [0x1015B] mov r9, [rsp+0x18]
  [0x10163] mov rcx, r9
  [0x10166] mov r8, rax
  [0x10169] add r12, r15
  [0x1016C] call r12
  [0x1016F] mov r9, [rsp+0x18]
  [0x10177] mov r8d, [r15+r9*1+0x14]
  [0x1017C] mov r9d, [r15+r8*1+0x10]
  [0x10181] mov r8d, [r15+r9*1+0x08]
  [0x10186] mov r9, r14
  [0x10189] cmp r8, r9
  [0x1018C] jz 0x0000000000010197
  [0x10192] jmp 0x00000000000101AD
  [0x10197] mov r9, [rsp+0x18]
  [0x1019F] mov r8d, [r15+r9*1+0x14]
  [0x101A4] mov r9d, [r15+r8*1+0x10]
  [0x101A9] mov r8d, [r15+r9*1]
  [0x101AD] mov eax, [r15+r14*1+0xBADBEEF]
  [0x101B5] lea rdi, [r14+0x08]
  [0x101BA] lea rsi, [0x00000000000101C1]
  [0x101C1] sub rsi, r15
  [0x101C4] mov r9, [rsp+0x18]
  [0x101CC] mov ecx, [r15+r9*1+0x14]
  [0x101D1] mov edx, [r15+rcx*1+0x3C]
  [0x101D6] mov r9, [rsp+0x18]
  [0x101DE] mov ecx, [r15+r9*1+0x14]
  [0x101E3] movzx rcx, byte ptr [r15+rcx*1+0x3B]
  [0x101E9] mov r9, [rsp+0x18]
  [0x101F1] mov ebx, [r15+r9*1+0x14]
  [0x101F6] movzx r9, word ptr [r15+rbx*1+0x38]
  [0x101FC] mov rbx, rax
  [0x101FF] add rbx, r15
  [0x10202] call rbx
  [0x10204] lea r9, [r14+0xAFECAFE]
  [0x1020C] cmp rbp, r9
  [0x1020F] jnz 0x000000000001028C
  [0x10215] mov eax, [r15+r14*1+0xBADBEEF]
  [0x1021D] lea rdi, [r14+0x08]
  [0x10222] lea rsi, [0x0000000000010229]
  [0x10229] sub rsi, r15
  [0x1022C] mov r9, [rsp+0x18]
  [0x10234] mov r8d, [r15+r9*1+0x14]
  [0x10239] movss xmm7, dword ptr [r15+r8*1+0x20]
  [0x10240] mov r9, [rsp+0x18]
  [0x10248] mov r8d, [r15+r9*1+0x14]
  [0x1024D] movss xmm6, dword ptr [r15+r8*1+0x24]
  [0x10254] mov r9, [rsp+0x18]
  [0x1025C] mov r8d, [r15+r9*1+0x14]
  [0x10261] movss xmm5, dword ptr [r15+r8*1+0x28]
  [0x10268] movd edx, xmm7
  [0x1026C] movsxd rdx, edx
  [0x1026F] movd ecx, xmm6
  [0x10273] movsxd rcx, ecx
  [0x10276] movd r8d, xmm5
  [0x1027B] movsxd r8, r8d
  [0x1027E] mov r9, rax
  [0x10281] add r9, r15
  [0x10284] call r9
  [0x10287] jmp 0x00000000000102FE
  [0x1028C] mov eax, [r15+r14*1+0xBADBEEF]
  [0x10294] lea rdi, [r14+0x08]
  [0x10299] lea rsi, [0x00000000000102A0]
  [0x102A0] sub rsi, r15
  [0x102A3] mov r9, [rsp+0x18]
  [0x102AB] mov r8d, [r15+r9*1+0x14]
  [0x102B0] movss xmm7, dword ptr [r15+r8*1+0x20]
  [0x102B7] mov r9, [rsp+0x18]
  [0x102BF] mov r8d, [r15+r9*1+0x14]
  [0x102C4] movss xmm6, dword ptr [r15+r8*1+0x24]
  [0x102CB] mov r9, [rsp+0x18]
  [0x102D3] mov r8d, [r15+r9*1+0x14]
  [0x102D8] movss xmm5, dword ptr [r15+r8*1+0x28]
  [0x102DF] movd edx, xmm7
  [0x102E3] movsxd rdx, edx
  [0x102E6] movd ecx, xmm6
  [0x102EA] movsxd rcx, ecx
  [0x102ED] movd r8d, xmm5
  [0x102F2] movsxd r8, r8d
  [0x102F5] mov r9, rax
  [0x102F8] add r9, r15
  [0x102FB] call r9
  [0x102FE] mov r9, [rsp+0x18]
  [0x10306] mov r8d, [r15+r9*1+0x14]
  [0x1030B] mov r12d, [r15+r8*1+0x0C]
  [0x10310] xor r9, r9
  [0x10313] mov r8, r14
  [0x10316] cmp r12, r9
  [0x10319] jz 0x0000000000010324
  [0x1031F] lea r8, [r14+0x08]
  [0x10324] mov r9, r8
  [0x10327] mov r8, r14
  [0x1032A] cmp r9, r8
  [0x1032D] jz 0x0000000000010351
  [0x10333] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1033B] mov edi, [r12+r15*1-0x04]
  [0x10340] mov esi, [r15+r14*1+0xBADBEEF]
  [0x10348] add r9, r15
  [0x1034B] call r9
  [0x1034E] mov r9, rax
  [0x10351] mov r8, r14
  [0x10354] cmp r9, r8
  [0x10357] jz 0x0000000000010362
  [0x1035D] jmp 0x0000000000010365
  [0x10362] mov r12, r14
  [0x10365] mov ebx, [r15+r14*1+0xBADBEEF]
  [0x1036D] lea rdi, [r14+0x08]
  [0x10372] lea rsi, [0x0000000000010379]
  [0x10379] sub rsi, r15
  [0x1037C] mov r9, [rsp+0x18]
  [0x10384] mov r8d, [r15+r9*1+0x14]
  [0x10389] mov r9d, [r15+r8*1+0x0C]
  [0x1038E] mov r8, r14
  [0x10391] cmp r9, r8
  [0x10394] jz 0x00000000000103B1
  [0x1039A] mov r9, [rsp+0x18]
  [0x103A2] mov r8d, [r15+r9*1+0x14]
  [0x103A7] mov edx, [r15+r8*1+0x0C]
  [0x103AC] jmp 0x00000000000103B4
  [0x103B1] xor rdx, rdx
  [0x103B4] mov r9, [rsp+0x18]
  [0x103BC] mov r8d, [r15+r9*1+0x14]
  [0x103C1] mov r9d, [r15+r8*1+0x0C]
  [0x103C6] mov r8, r14
  [0x103C9] cmp r9, r8
  [0x103CC] jz 0x00000000000103ED
  [0x103D2] mov r9, [rsp+0x18]
  [0x103DA] mov r8d, [r15+r9*1+0x14]
  [0x103DF] mov r9d, [r15+r8*1+0x0C]
  [0x103E4] mov ecx, [r15+r9*1]
  [0x103E8] jmp 0x00000000000103F7
  [0x103ED] lea rcx, [0x00000000000103F4]
  [0x103F4] sub rcx, r15
  [0x103F7] mov r9, [rsp+0x18]
  [0x103FF] mov r8d, [r15+r9*1+0x14]
  [0x10404] mov r9d, [r15+r8*1+0x0C]
  [0x10409] mov r8, r14
  [0x1040C] cmp r9, r8
  [0x1040F] jz 0x000000000001042C
  [0x10415] mov r9, [rsp+0x18]
  [0x1041D] mov r8d, [r15+r9*1+0x14]
  [0x10422] mov r9d, [r15+r8*1+0x0C]
  [0x10427] mov r9d, [r15+r9*1+0x34]
  [0x1042C] mov r8, r14
  [0x1042F] cmp r9, r8
  [0x10432] jz 0x0000000000010458
  [0x10438] mov r9, [rsp+0x18]
  [0x10440] mov r8d, [r15+r9*1+0x14]
  [0x10445] mov r9d, [r15+r8*1+0x0C]
  [0x1044A] mov r9d, [r15+r9*1+0x34]
  [0x1044F] mov r8d, [r15+r9*1]
  [0x10453] jmp 0x0000000000010462
  [0x10458] lea r8, [0x000000000001045F]
  [0x1045F] sub r8, r15
  [0x10462] mov r9, [rsp+0x18]
  [0x1046A] mov eax, [r15+r9*1+0x14]
  [0x1046F] mov r9d, [r15+rax*1+0x0C]
  [0x10474] mov rax, r14
  [0x10477] cmp r9, rax
  [0x1047A] jz 0x00000000000104D7
  [0x10480] mov r9, [rsp+0x18]
  [0x10488] mov eax, [r15+r9*1+0x14]
  [0x1048D] mov r9d, [r15+rax*1+0x0C]
  [0x10492] movsxd r9, dword ptr [r15+r9*1+0x44]
  [0x10497] mov rax, [rsp+0x18]
  [0x1049F] mov r11d, [r15+rax*1+0x14]
  [0x104A4] mov eax, [r15+r11*1+0x0C]
  [0x104A9] mov eax, [r15+rax*1+0x50]
  [0x104AE] mov r11, rax
  [0x104B1] mov rax, [rsp+0x18]
  [0x104B9] mov r10d, [r15+rax*1+0x14]
  [0x104BE] mov eax, [r15+r10*1+0x0C]
  [0x104C3] mov eax, [r15+rax*1+0x54]
  [0x104C8] sub r11, rax
  [0x104CB] sub r9, r11
  [0x104CE] shl r9, 0x03
  [0x104D2] jmp 0x00000000000104E1
  [0x104D7] lea r9, [0x00000000000104DE]
  [0x104DE] sub r9, r15
  [0x104E1] mov rax, [rsp+0x18]
  [0x104E9] mov r11d, [r15+rax*1+0x14]
  [0x104EE] mov eax, [r15+r11*1+0x0C]
  [0x104F3] mov r11, r14
  [0x104F6] cmp rax, r11
  [0x104F9] jz 0x000000000001051F
  [0x104FF] mov rax, [rsp+0x18]
  [0x10507] mov r11d, [r15+rax*1+0x14]
  [0x1050C] mov eax, [r15+r11*1+0x0C]
  [0x10511] movsxd r10, dword ptr [r15+rax*1+0x44]
  [0x10516] shl r10, 0x03
  [0x1051A] jmp 0x0000000000010529
  [0x1051F] lea r10, [0x0000000000010526]
  [0x10526] sub r10, r15
  [0x10529] add rbx, r15
  [0x1052C] call rbx
  [0x1052E] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10536] lea rsi, [r14+0x08]
  [0x1053B] mov rdi, r12
  [0x1053E] add r9, r15
  [0x10541] call r9
  [0x10544] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x1054C] lea rdi, [r14+0x08]
  [0x10551] lea rsi, [0x0000000000010558]
  [0x10558] sub rsi, r15
  [0x1055B] add r9, r15
  [0x1055E] call r9
  [0x10561] lea r9, [r14+0xAFECAFE]
  [0x10569] cmp rbp, r9
  [0x1056C] jnz 0x00000000000105A9
  [0x10572] mov r8d, [r15+r14*1+0xBADBEEF]
  [0x1057A] lea rdi, [r14+0x08]
  [0x1057F] lea rsi, [0x0000000000010586]
  [0x10586] sub rsi, r15
  [0x10589] mov edx, 0x30
  [0x1058E] mov r9, [rsp+0x18]
  [0x10596] mov ecx, [r15+r9*1+0x14]
  [0x1059B] add rdx, rcx
  [0x1059E] add r8, r15
  [0x105A1] call r8
  [0x105A4] jmp 0x00000000000105AC
  [0x105A9] mov rax, r14
  [0x105AC] jmp 0x00000000000105B4
  [0x105B1] mov rax, r14
  [0x105B4] add rsp, 0x20
  [0x105B8] pop r12
  [0x105BA] pop r11
  [0x105BC] pop r10
  [0x105BE] pop rbp
  [0x105BF] pop rbx
  [0x105C0] ret


[(method print entity)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r10
  [0x10004] push r11
  [0x10006] push r12
  [0x10008] sub rsp, 0x20
  [0x1000C] mov [rsp+0x10], rdi
  [0x10014] mov ebp, [r15+r14*1+0xBADBEEF]
  [0x1001C] lea r12, [r14+0x08]
  [0x10021] lea r11, [0x0000000000010028]
  [0x10028] sub r11, r15
  [0x1002B] mov r8, [rsp+0x10]
  [0x10033] mov r9d, [r15+r8*1-0x04]
  [0x10038] mov [rsp], r9
  [0x10040] mov r9d, [r15+r14*1+0xBADBEEF]
  [0x10048] mov eax, [r15+r9*1+0x38]
  [0x1004D] lea rsi, [r14+0xAFECAFE]
  [0x10055] lea rdx, [r14+0xAFECAFE]
  [0x1005D] movss xmm7, dword ptr [0x0000000000010065]
  [0x10065] mov r8, r14
  [0x10068] mov r9, r14
  [0x1006B] mov r10d, [r15+r14*1+0xBADBEEF]
  [0x10073] mov rcx, [rsp+0x10]
  [0x1007B] mov rdi, rcx
  [0x1007E] movd ecx, xmm7
  [0x10082] movsxd rcx, ecx
  [0x10085] mov [rsp+0x08], rax
  [0x1008D] mov rbx, [rsp+0x08]
  [0x10095] add rbx, r15
  [0x10098] call rbx
  [0x1009A] mov [rsp+0x08], rbx
  [0x100A2] mov rdi, r12
  [0x100A5] mov rsi, r11
  [0x100A8] mov rdx, [rsp]
  [0x100B0] mov rcx, rax
  [0x100B3] mov r9, [rsp+0x10]
  [0x100BB] mov r8, r9
  [0x100BE] add rbp, r15
  [0x100C1] call rbp
  [0x100C3] mov rax, [rsp+0x10]
  [0x100CB] add rsp, 0x20
  [0x100CF] pop r12
  [0x100D1] pop r11
  [0x100D3] pop r10
  [0x100D5] pop rbp
  [0x100D6] pop rbx
  [0x100D7] ret


[(method mem-usage drawable-actor)]
[1m[38;2;255;000;000m- [0x10000] [0mpush rbx
  [0x10001] push rbp
  [0x10002] push r12
  [0x10004] mov rbp, rdi
  [0x10007] mov rbx, rsi
  [0x1000A] mov r12, rdx
  [0x1000D] mov r9d, 0x2C
  [0x10013] movsxd r8, dword ptr [r15+rbx*1+0x04]
  [0x10018] cmp r9, r8
  [0x1001B] jle 0x0000000000010026
  [0x10021] jmp 0x0000000000010029
  [0x10026] mov r9, r8
  [0x10029] mov [r15+rbx*1+0x04], r9d
  [0x1002E] lea r9, [0x0000000000010035]
  [0x10035] sub r9, r15
  [0x10038] mov [r15+rbx*1+0x2BC], r9d
  [0x10040] movsxd r9, dword ptr [r15+rbx*1+0x2C0]
  [0x10048] mov r8d, 0x01
  [0x1004E] add r9, r8
  [0x10051] mov [r15+rbx*1+0x2C0], r9d
  [0x10059] mov r9d, [r15+rbp*1-0x04]
  [0x1005E] mov r9d, [r15+r9*1+0x24]
  [0x10063] mov rdi, rbp
  [0x10066] add r9, r15
  [0x10069] call r9
  [0x1006C] movsxd r9, dword ptr [r15+rbx*1+0x2C4]
  [0x10074] add r9, rax
  [0x10077] mov [r15+rbx*1+0x2C4], r9d
  [0x1007F] movsxd r9, dword ptr [r15+rbx*1+0x2C8]
  [0x10087] mov r8, 0xFFFFFFFFFFFFFFF0
  [0x1008E] mov ecx, 0x0F
  [0x10093] add rax, rcx
  [0x10096] and r8, rax
  [0x10099] add r9, r8
  [0x1009C] mov [r15+rbx*1+0x2C8], r9d
  [0x100A4] mov edi, [r15+rbp*1+0x04]
  [0x100A9] mov r9d, 0x40
  [0x100AF] or r12, r9
  [0x100B2] mov r9d, [r15+rdi*1-0x04]
  [0x100B7] mov r9d, [r15+r9*1+0x30]
  [0x100BC] mov rsi, rbx
  [0x100BF] mov rdx, r12
  [0x100C2] add r9, r15
  [0x100C5] call r9
  [0x100C8] xor rax, rax
  [0x100CB] pop r12
  [0x100CD] pop rbp
  [0x100CE] pop rbx
  [0x100CF] ret



