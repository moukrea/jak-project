[(method debug-print game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x12, x6
  [0x10014] add x16, x5, x15
  [0x10018] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1001C] add x16, x9, x15
  [0x10020] ldr w9, [x16, #0x1c] ;; misaligned with debug data
  [0x10024] mov x9, x9
  [0x10028] mov x7, x5
  [0x1002C] add x9, x9, x15
  [0x10030] stp x3, x5, [sp, #-0x10]!
  [0x10034] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10038] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1003C] blr x9 ;; misaligned with debug data
  [0x10040] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10044] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10048] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1004C] mov x0, x0
  [0x10050] mov x9, x14
  [0x10054] sub x9, x9, x15 ;; misaligned with debug data
  [0x10058] mov x8, x14
  [0x1005C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10060] cmp x12, x9
  [0x10064] b.ne #0x10074
  [0x10068] add x8, x14, #8
  [0x1006C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10070] mov x8, x8
  [0x10074] mov x9, x8
  [0x10078] mov x8, x14
  [0x1007C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10080] cmp x9, x8
  [0x10084] b.ne #0x100b0
  [0x10088] adrp x9, #0x10000
  [0x1008C] add x9, x9, #0
  [0x10090] mov x8, x14
  [0x10094] sub x8, x8, x15 ;; misaligned with debug data
  [0x10098] cmp x12, x9
  [0x1009C] b.ne #0x100ac
  [0x100A0] add x8, x14, #8
  [0x100A4] sub x8, x8, x15 ;; misaligned with debug data
  [0x100A8] mov x8, x8
  [0x100AC] mov x9, x8
  [0x100B0] mov x8, x14
  [0x100B4] sub x8, x8, x15 ;; misaligned with debug data
  [0x100B8] cmp x9, x8
  [0x100BC] b.eq #0x10244
  [0x100C0] adrp x16, #0x10000
  [0x100C4] add x16, x16, #0
  [0x100C8] ldr w9, [x16]
  [0x100CC] add x7, x14, #8
  [0x100D0] sub x7, x7, x15 ;; misaligned with debug data
  [0x100D4] adrp x6, #0x11000
  [0x100D8] add x6, x6, #0xd4
  [0x100DC] sub x6, x6, x15
  [0x100E0] mov x9, x9
  [0x100E4] mov x7, x7
  [0x100E8] mov x6, x6
  [0x100EC] add x9, x9, x15
  [0x100F0] stp x3, x5, [sp, #-0x10]!
  [0x100F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100FC] blr x9 ;; misaligned with debug data
  [0x10100] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10104] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10108] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1010C] mov x0, x0
  [0x10110] movz x3, #0
  [0x10114] mov x3, x3
  [0x10118] b #0x10228
  [0x1011C] mov x6, x3
  [0x10120] add x16, x5, x15
  [0x10124] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10128] add x16, x9, x15
  [0x1012C] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10130] mov x9, x9
  [0x10134] mov x7, x5
  [0x10138] mov x6, x6
  [0x1013C] add x9, x9, x15
  [0x10140] stp x3, x5, [sp, #-0x10]!
  [0x10144] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10148] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1014C] blr x9 ;; misaligned with debug data
  [0x10150] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10154] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10158] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1015C] mov x0, x0
  [0x10160] mov x9, x14
  [0x10164] sub x9, x9, x15 ;; misaligned with debug data
  [0x10168] cmp x0, x9
  [0x1016C] b.eq #0x10210
  [0x10170] adrp x16, #0x10000
  [0x10174] add x16, x16, #0
  [0x10178] ldr w11, [x16]
  [0x1017C] add x10, x14, #8
  [0x10180] sub x10, x10, x15 ;; misaligned with debug data
  [0x10184] adrp x9, #0x11000
  [0x10188] add x9, x9, #0xf4
  [0x1018C] sub x9, x9, x15
  [0x10190] str x9, [sp]
  [0x10194] adrp x16, #0x10000
  [0x10198] add x16, x16, #0
  [0x1019C] ldr w9, [x16]
  [0x101A0] mov x7, x3
  [0x101A4] mov x9, x9
  [0x101A8] mov x7, x7
  [0x101AC] add x9, x9, x15
  [0x101B0] stp x3, x5, [sp, #-0x10]!
  [0x101B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101BC] blr x9 ;; misaligned with debug data
  [0x101C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101CC] mov x0, x0
  [0x101D0] mov x11, x11
  [0x101D4] mov x7, x10
  [0x101D8] ldr x6, [sp]
  [0x101DC] mov x6, x6
  [0x101E0] mov x2, x0
  [0x101E4] add x11, x11, x15
  [0x101E8] stp x3, x5, [sp, #-0x10]!
  [0x101EC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101F0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101F4] blr x11 ;; misaligned with debug data
  [0x101F8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101FC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10200] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10204] mov x0, x0
  [0x10208] mov x0, x0
  [0x1020C] b #0x10218
  [0x10210] mov x0, x14
  [0x10214] sub x0, x0, x15 ;; misaligned with debug data
  [0x10218] mov x3, x3
  [0x1021C] movz x9, #0x1
  [0x10220] add x3, x3, x9
  [0x10224] mov x3, x3
  [0x10228] movz x9, #0x74
  [0x1022C] cmp x3, x9
  [0x10230] b.lt #0x1011c
  [0x10234] mov x9, x14
  [0x10238] sub x9, x9, x15 ;; misaligned with debug data
  [0x1023C] mov x9, x9
  [0x10240] b #0x1024c
  [0x10244] mov x9, x14
  [0x10248] sub x9, x9, x15 ;; misaligned with debug data
  [0x1024C] mov x9, x14
  [0x10250] sub x9, x9, x15 ;; misaligned with debug data
  [0x10254] mov x8, x14
  [0x10258] sub x8, x8, x15 ;; misaligned with debug data
  [0x1025C] cmp x12, x9
  [0x10260] b.ne #0x10270
  [0x10264] add x8, x14, #8
  [0x10268] sub x8, x8, x15 ;; misaligned with debug data
  [0x1026C] mov x8, x8
  [0x10270] mov x9, x8
  [0x10274] mov x8, x14
  [0x10278] sub x8, x8, x15 ;; misaligned with debug data
  [0x1027C] cmp x9, x8
  [0x10280] b.ne #0x102ac
  [0x10284] adrp x9, #0x10000
  [0x10288] add x9, x9, #0
  [0x1028C] mov x8, x14
  [0x10290] sub x8, x8, x15 ;; misaligned with debug data
  [0x10294] cmp x12, x9
  [0x10298] b.ne #0x102a8
  [0x1029C] add x8, x14, #8
  [0x102A0] sub x8, x8, x15 ;; misaligned with debug data
  [0x102A4] mov x8, x8
  [0x102A8] mov x9, x8
  [0x102AC] mov x8, x14
  [0x102B0] sub x8, x8, x15 ;; misaligned with debug data
  [0x102B4] cmp x9, x8
  [0x102B8] b.eq #0x103c0
  [0x102BC] adrp x16, #0x10000
  [0x102C0] add x16, x16, #0
  [0x102C4] ldr w9, [x16]
  [0x102C8] add x7, x14, #8
  [0x102CC] sub x7, x7, x15 ;; misaligned with debug data
  [0x102D0] adrp x6, #0x11000
  [0x102D4] add x6, x6, #0x114
  [0x102D8] sub x6, x6, x15
  [0x102DC] mov x9, x9
  [0x102E0] mov x7, x7
  [0x102E4] mov x6, x6
  [0x102E8] add x9, x9, x15
  [0x102EC] stp x3, x5, [sp, #-0x10]!
  [0x102F0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102F4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102F8] blr x9 ;; misaligned with debug data
  [0x102FC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10300] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10304] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10308] mov x0, x0
  [0x1030C] add x16, x5, x15
  [0x10310] ldr w3, [x16, #0x60] ;; misaligned with debug data
  [0x10314] mov x12, x3
  [0x10318] movz x3, #0
  [0x1031C] mov x3, x3
  [0x10320] b #0x103a0
  [0x10324] adrp x16, #0x10000
  [0x10328] add x16, x16, #0
  [0x1032C] ldr w9, [x16]
  [0x10330] add x7, x14, #8
  [0x10334] sub x7, x7, x15 ;; misaligned with debug data
  [0x10338] adrp x6, #0x11000
  [0x1033C] add x6, x6, #0x134
  [0x10340] sub x6, x6, x15
  [0x10344] mov x2, x3
  [0x10348] lsl x2, x2, #4
  [0x1034C] mov x2, x2
  [0x10350] movz x8, #0xc
  [0x10354] add x8, x8, x12
  [0x10358] add x2, x2, x8
  [0x1035C] mov x9, x9
  [0x10360] mov x7, x7
  [0x10364] mov x6, x6
  [0x10368] mov x2, x2
  [0x1036C] add x9, x9, x15
  [0x10370] stp x3, x5, [sp, #-0x10]!
  [0x10374] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10378] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1037C] blr x9 ;; misaligned with debug data
  [0x10380] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10384] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10388] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1038C] mov x0, x0
  [0x10390] mov x3, x3
  [0x10394] movz x9, #0x1
  [0x10398] add x3, x3, x9
  [0x1039C] mov x3, x3
  [0x103A0] add x16, x12, x15
  [0x103A4] ldrsw x9, [x16] ;; misaligned with debug data
  [0x103A8] cmp x3, x9
  [0x103AC] b.lt #0x10324
  [0x103B0] mov x9, x14
  [0x103B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x103B8] mov x9, x9
  [0x103BC] b #0x103c8
  [0x103C0] mov x9, x14
  [0x103C4] sub x9, x9, x15 ;; misaligned with debug data
  [0x103C8] mov x0, x5
  [0x103CC] add sp, sp, #0x10
  [0x103D0] ldp x29, x30, [sp], #0x10
  [0x103D4] ret


[(method print continue-point)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] add x7, x14, #8
  [0x10020] sub x7, x7, x15 ;; misaligned with debug data
  [0x10024] adrp x6, #0x11000
  [0x10028] add x6, x6, #0xa4
  [0x1002C] sub x6, x6, x15
  [0x10030] add x16, x3, x15
  [0x10034] ldur w2, [x16, #-4] ;; misaligned with debug data
  [0x10038] add x16, x3, x15
  [0x1003C] ldr w1, [x16] ;; misaligned with debug data
  [0x10040] mov x9, x9
  [0x10044] mov x7, x7
  [0x10048] mov x6, x6
  [0x1004C] mov x2, x2
  [0x10050] mov x1, x1
  [0x10054] mov x8, x3
  [0x10058] add x9, x9, x15
  [0x1005C] stp x3, x5, [sp, #-0x10]!
  [0x10060] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10064] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10068] blr x9 ;; misaligned with debug data
  [0x1006C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10070] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10074] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10078] mov x0, x0
  [0x1007C] mov x0, x3
  [0x10080] add sp, sp, #0x10
  [0x10084] ldp x29, x30, [sp], #0x10
  [0x10088] ret


[(method copy-perms-to-level! game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x6, x6
  [0x10014] add x16, x6, x15
  [0x10018] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x1001C] add x16, x9, x15
  [0x10020] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10024] add x16, x9, x15
  [0x10028] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x1002C] mov x12, x3
  [0x10030] movz x3, #0
  [0x10034] mov x11, x3
  [0x10038] b #0x10154
  [0x1003C] mov x9, x11
  [0x10040] lsl x9, x9, #6
  [0x10044] movz x3, #0x30
  [0x10048] mov x9, x9
  [0x1004C] movz x8, #0xc
  [0x10050] add x8, x8, x12
  [0x10054] add x9, x9, x8
  [0x10058] add x16, x9, x15
  [0x1005C] ldr w9, [x16, #8] ;; misaligned with debug data
  [0x10060] add x16, x9, x15
  [0x10064] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10068] add x3, x3, x9
  [0x1006C] mov x3, x3
  [0x10070] add x16, x3, x15
  [0x10074] ldr w6, [x16, #0xc] ;; misaligned with debug data
  [0x10078] add x16, x5, x15
  [0x1007C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10080] add x16, x9, x15
  [0x10084] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10088] mov x9, x9
  [0x1008C] mov x7, x5
  [0x10090] mov x6, x6
  [0x10094] add x9, x9, x15
  [0x10098] stp x3, x5, [sp, #-0x10]!
  [0x1009C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A4] blr x9 ;; misaligned with debug data
  [0x100A8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100AC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100B0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100B4] mov x0, x0
  [0x100B8] mov x0, x0
  [0x100BC] mov x9, x14
  [0x100C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x100C4] cmp x0, x9
  [0x100C8] b.eq #0x1013c
  [0x100CC] add x16, x0, x15
  [0x100D0] ldr q23, [x16] ;; misaligned with debug data
  [0x100D4] mov v23.16b, v23.16b
  [0x100D8] add x16, x3, x15
  [0x100DC] str q23, [x16] ;; misaligned with debug data
  [0x100E0] adrp x6, #0x10000
  [0x100E4] add x6, x6, #0
  [0x100E8] movz x2, #0x26f
  [0x100EC] adrp x16, #0x10000
  [0x100F0] add x16, x16, #0
  [0x100F4] ldr w9, [x16]
  [0x100F8] add x16, x9, x15
  [0x100FC] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10100] mov x9, x9
  [0x10104] mov x7, x3
  [0x10108] mov x6, x6
  [0x1010C] mov x2, x2
  [0x10110] add x9, x9, x15
  [0x10114] stp x3, x5, [sp, #-0x10]!
  [0x10118] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1011C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10120] blr x9 ;; misaligned with debug data
  [0x10124] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10128] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1012C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10130] mov x0, x0
  [0x10134] mov x0, x0
  [0x10138] b #0x10144
  [0x1013C] mov x0, x14
  [0x10140] sub x0, x0, x15 ;; misaligned with debug data
  [0x10144] mov x3, x11
  [0x10148] movz x9, #0x1
  [0x1014C] add x3, x3, x9
  [0x10150] mov x11, x3
  [0x10154] add x16, x12, x15
  [0x10158] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1015C] cmp x11, x9
  [0x10160] b.lt #0x1003c
  [0x10164] mov x9, x14
  [0x10168] sub x9, x9, x15 ;; misaligned with debug data
  [0x1016C] add sp, sp, #0x10
  [0x10170] ldp x29, x30, [sp], #0x10
  [0x10174] ret


[(method copy-perms-from-level! game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x12, x7
  [0x10010] mov x6, x6
  [0x10014] add x16, x12, x15
  [0x10018] ldr w3, [x16, #0x60] ;; misaligned with debug data
  [0x1001C] add x16, x6, x15
  [0x10020] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10024] add x16, x9, x15
  [0x10028] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x1002C] add x16, x9, x15
  [0x10030] ldr w5, [x16, #0x118] ;; misaligned with debug data
  [0x10034] mov x11, x3
  [0x10038] mov x5, x5
  [0x1003C] movz x3, #0
  [0x10040] mov x10, x3
  [0x10044] b #0x101a0
  [0x10048] mov x9, x10
  [0x1004C] lsl x9, x9, #6
  [0x10050] movz x3, #0x30
  [0x10054] mov x9, x9
  [0x10058] movz x8, #0xc
  [0x1005C] add x8, x8, x5
  [0x10060] add x9, x9, x8
  [0x10064] add x16, x9, x15
  [0x10068] ldr w9, [x16, #8] ;; misaligned with debug data
  [0x1006C] add x16, x9, x15
  [0x10070] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10074] add x3, x3, x9
  [0x10078] mov x3, x3
  [0x1007C] add x16, x3, x15
  [0x10080] ldrb w9, [x16, #0xb] ;; misaligned with debug data
  [0x10084] movz x8, #0
  [0x10088] cmp x9, x8
  [0x1008C] b.eq #0x10188
  [0x10090] add x16, x3, x15
  [0x10094] ldr w6, [x16, #0xc] ;; misaligned with debug data
  [0x10098] add x16, x12, x15
  [0x1009C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100A0] add x16, x9, x15
  [0x100A4] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x100A8] mov x9, x9
  [0x100AC] mov x7, x12
  [0x100B0] mov x6, x6
  [0x100B4] add x9, x9, x15
  [0x100B8] stp x3, x5, [sp, #-0x10]!
  [0x100BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C4] blr x9 ;; misaligned with debug data
  [0x100C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] mov x0, x0
  [0x100D8] mov x0, x0
  [0x100DC] mov x9, x14
  [0x100E0] sub x9, x9, x15 ;; misaligned with debug data
  [0x100E4] cmp x0, x9
  [0x100E8] b.eq #0x10108
  [0x100EC] add x16, x3, x15
  [0x100F0] ldr q23, [x16] ;; misaligned with debug data
  [0x100F4] mov v23.16b, v23.16b
  [0x100F8] add x16, x0, x15
  [0x100FC] str q23, [x16] ;; misaligned with debug data
  [0x10100] fmov x9, d23
  [0x10104] b #0x10180
  [0x10108] add x16, x11, x15
  [0x1010C] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10110] add x16, x11, x15
  [0x10114] ldrsw x8, [x16, #4] ;; misaligned with debug data
  [0x10118] cmp x9, x8
  [0x1011C] b.ge #0x10178
  [0x10120] add x16, x3, x15
  [0x10124] ldr q23, [x16] ;; misaligned with debug data
  [0x10128] add x16, x11, x15
  [0x1012C] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10130] mov x9, x9
  [0x10134] lsl x9, x9, #4
  [0x10138] mov v23.16b, v23.16b
  [0x1013C] mov x9, x9
  [0x10140] movz x8, #0xc
  [0x10144] add x8, x8, x11
  [0x10148] add x9, x9, x8
  [0x1014C] add x16, x9, x15
  [0x10150] str q23, [x16] ;; misaligned with debug data
  [0x10154] add x16, x11, x15
  [0x10158] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1015C] mov x9, x9
  [0x10160] movz x8, #0x1
  [0x10164] add x9, x9, x8
  [0x10168] add x16, x11, x15
  [0x1016C] str w9, [x16] ;; misaligned with debug data
  [0x10170] mov x9, x9
  [0x10174] b #0x10180
  [0x10178] mov x9, x14
  [0x1017C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10180] mov x9, x9
  [0x10184] b #0x10190
  [0x10188] mov x9, x14
  [0x1018C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10190] mov x3, x10
  [0x10194] movz x9, #0x1
  [0x10198] add x3, x3, x9
  [0x1019C] mov x10, x3
  [0x101A0] add x16, x5, x15
  [0x101A4] ldrsw x9, [x16] ;; misaligned with debug data
  [0x101A8] cmp x10, x9
  [0x101AC] b.lt #0x10048
  [0x101B0] mov x9, x14
  [0x101B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101B8] add sp, sp, #0x10
  [0x101BC] ldp x29, x30, [sp], #0x10
  [0x101C0] ret


[(method get-health-percent-lost game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0x10
  [0x10010] mov x7, x7
  [0x10014] mov x6, x6
  [0x10018] adrp x16, #0x11000
  [0x1001C] ldr s24, [x16, #0x150]
  [0x10020] mov v24.16b, v24.16b
  [0x10024] mov x6, x14
  [0x10028] sub x6, x6, x15 ;; misaligned with debug data
  [0x1002C] add x16, x7, x15
  [0x10030] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10034] add x16, x9, x15
  [0x10038] ldr w9, [x16, #0x7c] ;; misaligned with debug data
  [0x1003C] mov x9, x9
  [0x10040] mov x7, x7
  [0x10044] mov x6, x6
  [0x10048] add x9, x9, x15
  [0x1004C] stp x3, x5, [sp, #-0x10]!
  [0x10050] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10054] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10058] blr x9 ;; misaligned with debug data
  [0x1005C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10060] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10064] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10068] mov x0, x0
  [0x1006C] scvtf s23, w0
  [0x10070] fmul s24, s24, s23
  [0x10074] fmov w0, s24
  [0x10078] sxtw x0, w0
  [0x1007C] mov x0, x0
  [0x10080] add sp, sp, #0x10
  [0x10084] ldr q24, [sp], #0x10
  [0x10088] ldp x29, x30, [sp], #0x10
  [0x1008C] ret


[(method lookup-entity-perm-by-aid game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] add x16, x7, x15
  [0x10014] ldr w9, [x16, #0x60] ;; misaligned with debug data
  [0x10018] mov x9, x9
  [0x1001C] add x16, x9, x15
  [0x10020] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10024] mov x8, x8
  [0x10028] b #0x10090
  [0x1002C] mov x8, x8
  [0x10030] movz x1, #0x1
  [0x10034] sub x8, x8, x1
  [0x10038] mov x8, x8
  [0x1003C] mov x1, x8
  [0x10040] lsl x1, x1, #4
  [0x10044] mov x1, x1
  [0x10048] movz x2, #0xc
  [0x1004C] add x2, x2, x9
  [0x10050] add x1, x1, x2
  [0x10054] add x16, x1, x15
  [0x10058] ldr w1, [x16, #0xc] ;; misaligned with debug data
  [0x1005C] cmp x6, x1
  [0x10060] b.ne #0x10088
  [0x10064] mov x0, x8
  [0x10068] lsl x0, x0, #4
  [0x1006C] mov x0, x0
  [0x10070] movz x8, #0xc
  [0x10074] add x8, x8, x9
  [0x10078] add x0, x0, x8
  [0x1007C] mov x0, x0
  [0x10080] b #0x100b4
  [0x10084] b #0x10090
  [0x10088] mov x1, x14
  [0x1008C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10090] movz x1, #0
  [0x10094] cmp x8, x1
  [0x10098] b.ne #0x1002c
  [0x1009C] mov x9, x14
  [0x100A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x100A4] mov x0, x14
  [0x100A8] sub x0, x0, x15 ;; misaligned with debug data
  [0x100AC] mov x0, x0
  [0x100B0] mov x0, x0
  [0x100B4] ldp x29, x30, [sp], #0x10
  [0x100B8] ret


[(method pickup-collectable! fact-info-target)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] str q25, [sp, #-0x10]!
  [0x10010] sub sp, sp, #0x50
  [0x10014] mov x11, x7
  [0x10018] mov x3, x6
  [0x1001C] mov x5, x2
  [0x10020] mov x12, x1
  [0x10024] mov x9, x3
  [0x10028] movz x8, #0x4
  [0x1002C] cmp x9, x8
  [0x10030] b.ne #0x10850
  [0x10034] fmov s23, w5
  [0x10038] adrp x16, #0x12000
  [0x1003C] ldr s22, [x16, #0xfa4]
  [0x10040] fcmp s23, s22
  [0x10044] b.mi #0x10540
  [0x10048] adrp x16, #0x12000
  [0x1004C] ldr s23, [x16, #0xfa8]
  [0x10050] fmov s22, w5
  [0x10054] fcmp s23, s22
  [0x10058] b.ge #0x103b8
  [0x1005C] mov x9, x12
  [0x10060] mov x9, x9
  [0x10064] mov x8, x9
  [0x10068] lsl x8, x8, #0x20
  [0x1006C] lsr x8, x8, #0x20
  [0x10070] mov x1, x14
  [0x10074] sub x1, x1, x15 ;; misaligned with debug data
  [0x10078] cmp x8, x1
  [0x1007C] b.eq #0x100c8
  [0x10080] mov x8, x9
  [0x10084] lsl x8, x8, #0x20
  [0x10088] lsr x8, x8, #0x20
  [0x1008C] add x16, x8, x15
  [0x10090] ldr w8, [x16] ;; misaligned with debug data
  [0x10094] mov x8, x8
  [0x10098] mov x9, x9
  [0x1009C] asr x9, x9, #0x20
  [0x100A0] add x16, x8, x15
  [0x100A4] ldrsw x1, [x16, #0x24] ;; misaligned with debug data
  [0x100A8] cmp x9, x1
  [0x100AC] b.ne #0x100b8
  [0x100B0] mov x8, x8
  [0x100B4] b #0x100c0
  [0x100B8] mov x8, x14
  [0x100BC] sub x8, x8, x15 ;; misaligned with debug data
  [0x100C0] mov x9, x8
  [0x100C4] b #0x100d0
  [0x100C8] mov x9, x14
  [0x100CC] sub x9, x9, x15 ;; misaligned with debug data
  [0x100D0] add x16, x11, x15
  [0x100D4] ldur x8, [x16, #0x5c] ;; misaligned with debug data
  [0x100D8] mov x8, x8
  [0x100DC] mov x8, x8
  [0x100E0] mov x1, x8
  [0x100E4] lsl x1, x1, #0x20
  [0x100E8] lsr x1, x1, #0x20
  [0x100EC] mov x2, x14
  [0x100F0] sub x2, x2, x15 ;; misaligned with debug data
  [0x100F4] cmp x1, x2
  [0x100F8] b.eq #0x10144
  [0x100FC] mov x1, x8
  [0x10100] lsl x1, x1, #0x20
  [0x10104] lsr x1, x1, #0x20
  [0x10108] add x16, x1, x15
  [0x1010C] ldr w1, [x16] ;; misaligned with debug data
  [0x10110] mov x1, x1
  [0x10114] mov x8, x8
  [0x10118] asr x8, x8, #0x20
  [0x1011C] add x16, x1, x15
  [0x10120] ldrsw x2, [x16, #0x24] ;; misaligned with debug data
  [0x10124] cmp x8, x2
  [0x10128] b.ne #0x10134
  [0x1012C] mov x1, x1
  [0x10130] b #0x1013c
  [0x10134] mov x1, x14
  [0x10138] sub x1, x1, x15 ;; misaligned with debug data
  [0x1013C] mov x8, x1
  [0x10140] b #0x1014c
  [0x10144] mov x8, x14
  [0x10148] sub x8, x8, x15 ;; misaligned with debug data
  [0x1014C] mov x1, x14
  [0x10150] sub x1, x1, x15 ;; misaligned with debug data
  [0x10154] cmp x9, x8
  [0x10158] b.eq #0x10168
  [0x1015C] add x1, x14, #8
  [0x10160] sub x1, x1, x15 ;; misaligned with debug data
  [0x10164] mov x1, x1
  [0x10168] mov x9, x1
  [0x1016C] mov x8, x14
  [0x10170] sub x8, x8, x15 ;; misaligned with debug data
  [0x10174] cmp x9, x8
  [0x10178] b.ne #0x101c8
  [0x1017C] adrp x16, #0x10000
  [0x10180] add x16, x16, #0
  [0x10184] ldr w9, [x16]
  [0x10188] add x16, x9, x15
  [0x1018C] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10190] ldr x9, [x16] ;; misaligned with debug data
  [0x10194] mov x9, x9
  [0x10198] add x16, x11, x15
  [0x1019C] ldur x8, [x16, #0x64] ;; misaligned with debug data
  [0x101A0] sub x9, x9, x8
  [0x101A4] movz x8, #0x96
  [0x101A8] mov x1, x14
  [0x101AC] sub x1, x1, x15 ;; misaligned with debug data
  [0x101B0] cmp x9, x8
  [0x101B4] b.lt #0x101c4
  [0x101B8] add x1, x14, #8
  [0x101BC] sub x1, x1, x15 ;; misaligned with debug data
  [0x101C0] mov x1, x1
  [0x101C4] mov x9, x1
  [0x101C8] mov x8, x14
  [0x101CC] sub x8, x8, x15 ;; misaligned with debug data
  [0x101D0] cmp x9, x8
  [0x101D4] b.eq #0x102ec
  [0x101D8] adrp x16, #0x10000
  [0x101DC] add x16, x16, #0
  [0x101E0] ldr w10, [x16]
  [0x101E4] movz x9, #0x6567
  [0x101E8] movk x9, #0x2d74, lsl #16
  [0x101EC] movk x9, #0x7267, lsl #32
  [0x101F0] movk x9, #0x6565, lsl #48
  [0x101F4] fmov d23, x9
  [0x101F8] movz x9, #0x2d6e
  [0x101FC] movk x9, #0x6365, lsl #16
  [0x10200] movk x9, #0x6f, lsl #32
  [0x10204] fmov d24, x9
  [0x10208] zip1 v24.2d, v23.2d, v24.2d
  [0x1020C] adrp x16, #0x10000
  [0x10210] add x16, x16, #0
  [0x10214] ldr w9, [x16]
  [0x10218] mov x9, x9
  [0x1021C] add x9, x9, x15
  [0x10220] stp x3, x5, [sp, #-0x10]!
  [0x10224] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10228] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1022C] blr x9 ;; misaligned with debug data
  [0x10230] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10234] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10238] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1023C] mov x0, x0
  [0x10240] adrp x16, #0x12000
  [0x10244] ldr s23, [x16, #0xfac]
  [0x10248] adrp x16, #0x12000
  [0x1024C] ldr s22, [x16, #0xfb0]
  [0x10250] mov v23.16b, v23.16b
  [0x10254] fdiv s23, s23, s22
  [0x10258] mov v23.16b, v23.16b
  [0x1025C] adrp x16, #0x12000
  [0x10260] ldr s22, [x16, #0xfb4]
  [0x10264] fmul s23, s23, s22
  [0x10268] fcvtzs w6, s23
  [0x1026C] sxtw x6, w6
  [0x10270] adrp x16, #0x12000
  [0x10274] ldr s23, [x16, #0xfb8]
  [0x10278] mov v23.16b, v23.16b
  [0x1027C] movz x9, #0
  [0x10280] scvtf s22, w9
  [0x10284] fmul s23, s23, s22
  [0x10288] fcvtzs w2, s23
  [0x1028C] sxtw x2, w2
  [0x10290] movz x1, #0
  [0x10294] movz x8, #0x1
  [0x10298] add x9, x14, #8
  [0x1029C] sub x9, x9, x15 ;; misaligned with debug data
  [0x102A0] mov x10, x10
  [0x102A4] mov v17.16b, v24.16b
  [0x102A8] mov x7, x0
  [0x102AC] mov x6, x6
  [0x102B0] mov x2, x2
  [0x102B4] mov x1, x1
  [0x102B8] mov x8, x8
  [0x102BC] mov x9, x9
  [0x102C0] add x10, x10, x15
  [0x102C4] stp x3, x5, [sp, #-0x10]!
  [0x102C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102D0] blr x10 ;; misaligned with debug data
  [0x102D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102E0] mov x0, x0
  [0x102E4] mov x0, x0
  [0x102E8] b #0x102f4
  [0x102EC] mov x0, x14
  [0x102F0] sub x0, x0, x15 ;; misaligned with debug data
  [0x102F4] mov x9, x12
  [0x102F8] mov x9, x9
  [0x102FC] mov x8, x9
  [0x10300] lsl x8, x8, #0x20
  [0x10304] lsr x8, x8, #0x20
  [0x10308] mov x1, x14
  [0x1030C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10310] cmp x8, x1
  [0x10314] b.eq #0x10360
  [0x10318] mov x8, x9
  [0x1031C] lsl x8, x8, #0x20
  [0x10320] lsr x8, x8, #0x20
  [0x10324] add x16, x8, x15
  [0x10328] ldr w8, [x16] ;; misaligned with debug data
  [0x1032C] mov x8, x8
  [0x10330] mov x9, x9
  [0x10334] asr x9, x9, #0x20
  [0x10338] add x16, x8, x15
  [0x1033C] ldrsw x1, [x16, #0x24] ;; misaligned with debug data
  [0x10340] cmp x9, x1
  [0x10344] b.ne #0x10350
  [0x10348] mov x8, x8
  [0x1034C] b #0x10358
  [0x10350] mov x8, x14
  [0x10354] sub x8, x8, x15 ;; misaligned with debug data
  [0x10358] mov x9, x8
  [0x1035C] b #0x10368
  [0x10360] mov x9, x14
  [0x10364] sub x9, x9, x15 ;; misaligned with debug data
  [0x10368] mov x8, x14
  [0x1036C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10370] cmp x9, x8
  [0x10374] b.eq #0x103a8
  [0x10378] add x16, x11, x15
  [0x1037C] stur x12, [x16, #0x5c] ;; misaligned with debug data
  [0x10380] adrp x16, #0x10000
  [0x10384] add x16, x16, #0
  [0x10388] ldr w9, [x16]
  [0x1038C] add x16, x9, x15
  [0x10390] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10394] ldr x9, [x16] ;; misaligned with debug data
  [0x10398] add x16, x11, x15
  [0x1039C] stur x9, [x16, #0x64] ;; misaligned with debug data
  [0x103A0] mov x9, x9
  [0x103A4] b #0x103b0
  [0x103A8] mov x9, x14
  [0x103AC] sub x9, x9, x15 ;; misaligned with debug data
  [0x103B0] mov x9, x9
  [0x103B4] b #0x103c0
  [0x103B8] mov x9, x14
  [0x103BC] sub x9, x9, x15 ;; misaligned with debug data
  [0x103C0] add x16, x11, x15
  [0x103C4] ldr s23, [x16, #0x3c] ;; misaligned with debug data
  [0x103C8] add x16, x11, x15
  [0x103CC] ldr s22, [x16, #0x40] ;; misaligned with debug data
  [0x103D0] fcmp s23, s22
  [0x103D4] b.ne #0x104b0
  [0x103D8] movz x6, #0x7
  [0x103DC] adrp x16, #0x10000
  [0x103E0] add x16, x16, #0
  [0x103E4] ldr w9, [x16]
  [0x103E8] add x16, x9, x15
  [0x103EC] ldr s23, [x16, #0x2c] ;; misaligned with debug data
  [0x103F0] add x16, x11, x15
  [0x103F4] ldr w9, [x16] ;; misaligned with debug data
  [0x103F8] mov x9, x9
  [0x103FC] mov x8, x14
  [0x10400] sub x8, x8, x15 ;; misaligned with debug data
  [0x10404] cmp x9, x8
  [0x10408] b.eq #0x1041c
  [0x1040C] add x16, x9, x15
  [0x10410] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10414] mov x9, x9
  [0x10418] b #0x10424
  [0x1041C] mov x9, x14
  [0x10420] sub x9, x9, x15 ;; misaligned with debug data
  [0x10424] mov x9, x9
  [0x10428] mov x9, x9
  [0x1042C] add x16, x9, x15
  [0x10430] ldr w8, [x16] ;; misaligned with debug data
  [0x10434] add x16, x8, x15
  [0x10438] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x1043C] movz x1, #0
  [0x10440] mov x9, x9
  [0x10444] lsl x9, x9, #0x20
  [0x10448] lsr x9, x9, #0x20
  [0x1044C] orr x1, x1, x9
  [0x10450] mov x8, x8
  [0x10454] lsl x8, x8, #0x20
  [0x10458] orr x1, x1, x8
  [0x1045C] add x16, x11, x15
  [0x10460] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10464] add x16, x9, x15
  [0x10468] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x1046C] mov x9, x9
  [0x10470] mov x7, x11
  [0x10474] mov x6, x6
  [0x10478] fmov w2, s23
  [0x1047C] sxtw x2, w2
  [0x10480] mov x1, x1
  [0x10484] add x9, x9, x15
  [0x10488] stp x3, x5, [sp, #-0x10]!
  [0x1048C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10490] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10494] blr x9 ;; misaligned with debug data
  [0x10498] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1049C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104A4] mov x0, x0
  [0x104A8] mov x0, x0
  [0x104AC] b #0x104b8
  [0x104B0] mov x0, x14
  [0x104B4] sub x0, x0, x15 ;; misaligned with debug data
  [0x104B8] adrp x16, #0x10000
  [0x104BC] add x16, x16, #0
  [0x104C0] ldr w9, [x16]
  [0x104C4] add x16, x9, x15
  [0x104C8] add x16, x16, #0x30c ;; misaligned with debug data
  [0x104CC] ldr x9, [x16] ;; misaligned with debug data
  [0x104D0] add x16, x11, x15
  [0x104D4] stur x9, [x16, #0x54] ;; misaligned with debug data
  [0x104D8] adrp x16, #0x10000
  [0x104DC] add x16, x16, #0
  [0x104E0] ldr w9, [x16]
  [0x104E4] add x16, x11, x15
  [0x104E8] ldr s23, [x16, #0x3c] ;; misaligned with debug data
  [0x104EC] add x16, x11, x15
  [0x104F0] ldr s22, [x16, #0x40] ;; misaligned with debug data
  [0x104F4] mov x9, x9
  [0x104F8] fmov w7, s23
  [0x104FC] sxtw x7, w7
  [0x10500] fmov w6, s22
  [0x10504] sxtw x6, w6
  [0x10508] mov x2, x5
  [0x1050C] add x9, x9, x15
  [0x10510] stp x3, x5, [sp, #-0x10]!
  [0x10514] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10518] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1051C] blr x9 ;; misaligned with debug data
  [0x10520] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10524] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10528] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1052C] mov x0, x0
  [0x10530] add x16, x11, x15
  [0x10534] str w0, [x16, #0x3c] ;; misaligned with debug data
  [0x10538] mov x0, x0
  [0x1053C] b #0x106e4
  [0x10540] adrp x16, #0x10000
  [0x10544] add x16, x16, #0
  [0x10548] ldr w9, [x16]
  [0x1054C] add x16, x11, x15
  [0x10550] ldr s23, [x16, #0x3c] ;; misaligned with debug data
  [0x10554] adrp x16, #0x12000
  [0x10558] ldr s22, [x16, #0xfbc]
  [0x1055C] adrp x16, #0x12000
  [0x10560] ldr s21, [x16, #0xfc0]
  [0x10564] fmov s20, w5
  [0x10568] fsub s21, s21, s20
  [0x1056C] mov x9, x9
  [0x10570] fmov w7, s23
  [0x10574] sxtw x7, w7
  [0x10578] fmov w6, s22
  [0x1057C] sxtw x6, w6
  [0x10580] fmov w2, s21
  [0x10584] sxtw x2, w2
  [0x10588] add x9, x9, x15
  [0x1058C] stp x3, x5, [sp, #-0x10]!
  [0x10590] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10594] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10598] blr x9 ;; misaligned with debug data
  [0x1059C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x105A0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x105A4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x105A8] mov x0, x0
  [0x105AC] add x16, x11, x15
  [0x105B0] str w0, [x16, #0x3c] ;; misaligned with debug data
  [0x105B4] fmov s23, w5
  [0x105B8] adrp x16, #0x12000
  [0x105BC] ldr s22, [x16, #0xfc4]
  [0x105C0] fcmp s23, s22
  [0x105C4] b.mi #0x10628
  [0x105C8] movz x6, #0x7
  [0x105CC] adrp x16, #0x12000
  [0x105D0] ldr s23, [x16, #0xfc8]
  [0x105D4] add x16, x11, x15
  [0x105D8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x105DC] add x16, x9, x15
  [0x105E0] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x105E4] mov x9, x9
  [0x105E8] mov x7, x11
  [0x105EC] mov x6, x6
  [0x105F0] fmov w2, s23
  [0x105F4] sxtw x2, w2
  [0x105F8] mov x1, x12
  [0x105FC] add x9, x9, x15
  [0x10600] stp x3, x5, [sp, #-0x10]!
  [0x10604] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10608] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1060C] blr x9 ;; misaligned with debug data
  [0x10610] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10614] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10618] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1061C] mov x0, x0
  [0x10620] mov x0, x0
  [0x10624] b #0x10630
  [0x10628] mov x0, x14
  [0x1062C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10630] add x16, x11, x15
  [0x10634] ldr s23, [x16, #0x3c] ;; misaligned with debug data
  [0x10638] adrp x16, #0x12000
  [0x1063C] ldr s22, [x16, #0xfcc]
  [0x10640] fcmp s23, s22
  [0x10644] b.ne #0x106d8
  [0x10648] add x16, x11, x15
  [0x1064C] ldr w9, [x16] ;; misaligned with debug data
  [0x10650] mov x9, x9
  [0x10654] add x16, x9, x15
  [0x10658] ldr w7, [x16, #0xb4] ;; misaligned with debug data
  [0x1065C] adrp x6, #0x10000
  [0x10660] add x6, x6, #0
  [0x10664] adrp x16, #0x12000
  [0x10668] ldr s23, [x16, #0xfd0]
  [0x1066C] adrp x16, #0x10000
  [0x10670] add x16, x16, #0
  [0x10674] ldr w9, [x16]
  [0x10678] add x16, x9, x15
  [0x1067C] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x10680] fsub s23, s23, s22
  [0x10684] add x16, x7, x15
  [0x10688] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1068C] add x16, x9, x15
  [0x10690] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10694] mov x9, x9
  [0x10698] mov x7, x7
  [0x1069C] mov x6, x6
  [0x106A0] fmov w2, s23
  [0x106A4] sxtw x2, w2
  [0x106A8] mov x1, x12
  [0x106AC] add x9, x9, x15
  [0x106B0] stp x3, x5, [sp, #-0x10]!
  [0x106B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106BC] blr x9 ;; misaligned with debug data
  [0x106C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x106CC] mov x0, x0
  [0x106D0] mov x0, x0
  [0x106D4] b #0x106e0
  [0x106D8] mov x0, x14
  [0x106DC] sub x0, x0, x15 ;; misaligned with debug data
  [0x106E0] mov x0, x0
  [0x106E4] add x16, x11, x15
  [0x106E8] ldr w9, [x16] ;; misaligned with debug data
  [0x106EC] add x16, x9, x15
  [0x106F0] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x106F4] mov x9, x9
  [0x106F8] add x16, x9, x15
  [0x106FC] ldr w9, [x16, #0x9c] ;; misaligned with debug data
  [0x10700] add x16, x9, x15
  [0x10704] ldr w9, [x16, #0x24] ;; misaligned with debug data
  [0x10708] movz x8, #0x200
  [0x1070C] mov x9, x9
  [0x10710] and x9, x9, x8
  [0x10714] movz x8, #0
  [0x10718] mov x1, x14
  [0x1071C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10720] cmp x9, x8
  [0x10724] b.eq #0x10734
  [0x10728] add x1, x14, #8
  [0x1072C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10730] mov x1, x1
  [0x10734] mov x9, x1
  [0x10738] mov x8, x14
  [0x1073C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10740] cmp x9, x8
  [0x10744] b.eq #0x10810
  [0x10748] adrp x16, #0x10000
  [0x1074C] add x16, x16, #0
  [0x10750] ldr w9, [x16]
  [0x10754] mov x8, x12
  [0x10758] mov x8, x8
  [0x1075C] mov x1, x8
  [0x10760] lsl x1, x1, #0x20
  [0x10764] lsr x1, x1, #0x20
  [0x10768] mov x2, x14
  [0x1076C] sub x2, x2, x15 ;; misaligned with debug data
  [0x10770] cmp x1, x2
  [0x10774] b.eq #0x107c0
  [0x10778] mov x1, x8
  [0x1077C] lsl x1, x1, #0x20
  [0x10780] lsr x1, x1, #0x20
  [0x10784] add x16, x1, x15
  [0x10788] ldr w1, [x16] ;; misaligned with debug data
  [0x1078C] mov x1, x1
  [0x10790] mov x8, x8
  [0x10794] asr x8, x8, #0x20
  [0x10798] add x16, x1, x15
  [0x1079C] ldrsw x2, [x16, #0x24] ;; misaligned with debug data
  [0x107A0] cmp x8, x2
  [0x107A4] b.ne #0x107b0
  [0x107A8] mov x1, x1
  [0x107AC] b #0x107b8
  [0x107B0] mov x1, x14
  [0x107B4] sub x1, x1, x15 ;; misaligned with debug data
  [0x107B8] mov x8, x1
  [0x107BC] b #0x107c8
  [0x107C0] mov x8, x14
  [0x107C4] sub x8, x8, x15 ;; misaligned with debug data
  [0x107C8] add x16, x8, x15
  [0x107CC] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x107D0] adrp x16, #0x10000
  [0x107D4] add x16, x16, #0
  [0x107D8] ldr w6, [x16]
  [0x107DC] mov x9, x9
  [0x107E0] mov x7, x7
  [0x107E4] mov x6, x6
  [0x107E8] add x9, x9, x15
  [0x107EC] stp x3, x5, [sp, #-0x10]!
  [0x107F0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x107F4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x107F8] blr x9 ;; misaligned with debug data
  [0x107FC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10800] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10804] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10808] mov x0, x0
  [0x1080C] mov x9, x0
  [0x10810] mov x9, x9
  [0x10814] mov x8, x14
  [0x10818] sub x8, x8, x15 ;; misaligned with debug data
  [0x1081C] cmp x9, x8
  [0x10820] b.eq #0x10834
  [0x10824] sub x9, x14, #0xa
  [0x10828] sub x9, x9, x15 ;; misaligned with debug data
  [0x1082C] b #0x1101c
  [0x10830] b #0x1083c
  [0x10834] mov x9, x14
  [0x10838] sub x9, x9, x15 ;; misaligned with debug data
  [0x1083C] add x16, x11, x15
  [0x10840] ldr s23, [x16, #0x3c] ;; misaligned with debug data
  [0x10844] fmov w0, s23
  [0x10848] sxtw x0, w0
  [0x1084C] b #0x1207c
  [0x10850] movz x8, #0x7
  [0x10854] cmp x9, x8
  [0x10858] b.ne #0x10aac
  [0x1085C] fmov s23, w5
  [0x10860] adrp x16, #0x12000
  [0x10864] ldr s22, [x16, #0xfd4]
  [0x10868] fcmp s23, s22
  [0x1086C] b.mi #0x10a90
  [0x10870] adrp x16, #0x10000
  [0x10874] add x16, x16, #0
  [0x10878] ldr w9, [x16]
  [0x1087C] add x16, x9, x15
  [0x10880] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10884] ldr x9, [x16] ;; misaligned with debug data
  [0x10888] add x16, x11, x15
  [0x1088C] stur x9, [x16, #0x84] ;; misaligned with debug data
  [0x10890] adrp x16, #0x10000
  [0x10894] add x16, x16, #0
  [0x10898] ldr w9, [x16]
  [0x1089C] add x16, x11, x15
  [0x108A0] ldr s23, [x16, #0x4c] ;; misaligned with debug data
  [0x108A4] add x16, x11, x15
  [0x108A8] ldr s22, [x16, #0x50] ;; misaligned with debug data
  [0x108AC] mov x9, x9
  [0x108B0] fmov w7, s23
  [0x108B4] sxtw x7, w7
  [0x108B8] fmov w6, s22
  [0x108BC] sxtw x6, w6
  [0x108C0] mov x2, x5
  [0x108C4] add x9, x9, x15
  [0x108C8] stp x3, x5, [sp, #-0x10]!
  [0x108CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108D4] blr x9 ;; misaligned with debug data
  [0x108D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108E4] mov x0, x0
  [0x108E8] add x16, x11, x15
  [0x108EC] str w0, [x16, #0x4c] ;; misaligned with debug data
  [0x108F0] add x16, x11, x15
  [0x108F4] ldr s23, [x16, #0x4c] ;; misaligned with debug data
  [0x108F8] adrp x16, #0x10000
  [0x108FC] add x16, x16, #0
  [0x10900] ldr w9, [x16]
  [0x10904] add x16, x9, x15
  [0x10908] ldr s22, [x16, #0x2c] ;; misaligned with debug data
  [0x1090C] mov x9, x14
  [0x10910] sub x9, x9, x15 ;; misaligned with debug data
  [0x10914] fcmp s23, s22
  [0x10918] b.mi #0x10928
  [0x1091C] add x9, x14, #8
  [0x10920] sub x9, x9, x15 ;; misaligned with debug data
  [0x10924] mov x9, x9
  [0x10928] mov x9, x9
  [0x1092C] mov x8, x14
  [0x10930] sub x8, x8, x15 ;; misaligned with debug data
  [0x10934] cmp x9, x8
  [0x10938] b.eq #0x1096c
  [0x1093C] add x16, x11, x15
  [0x10940] ldr s23, [x16, #0x3c] ;; misaligned with debug data
  [0x10944] add x16, x11, x15
  [0x10948] ldr s22, [x16, #0x40] ;; misaligned with debug data
  [0x1094C] mov x9, x14
  [0x10950] sub x9, x9, x15 ;; misaligned with debug data
  [0x10954] fcmp s23, s22
  [0x10958] b.ge #0x10968
  [0x1095C] add x9, x14, #8
  [0x10960] sub x9, x9, x15 ;; misaligned with debug data
  [0x10964] mov x9, x9
  [0x10968] mov x9, x9
  [0x1096C] mov x8, x14
  [0x10970] sub x8, x8, x15 ;; misaligned with debug data
  [0x10974] cmp x9, x8
  [0x10978] b.eq #0x10a80
  [0x1097C] add x16, x11, x15
  [0x10980] ldr s23, [x16, #0x4c] ;; misaligned with debug data
  [0x10984] mov v23.16b, v23.16b
  [0x10988] adrp x16, #0x10000
  [0x1098C] add x16, x16, #0
  [0x10990] ldr w9, [x16]
  [0x10994] add x16, x9, x15
  [0x10998] ldr s22, [x16, #0x2c] ;; misaligned with debug data
  [0x1099C] fsub s23, s23, s22
  [0x109A0] add x16, x11, x15
  [0x109A4] str s23, [x16, #0x4c] ;; misaligned with debug data
  [0x109A8] movz x6, #0x4
  [0x109AC] adrp x16, #0x10000
  [0x109B0] add x16, x16, #0
  [0x109B4] ldr w9, [x16]
  [0x109B8] add x16, x9, x15
  [0x109BC] ldr s23, [x16, #0x30] ;; misaligned with debug data
  [0x109C0] add x16, x11, x15
  [0x109C4] ldr w9, [x16] ;; misaligned with debug data
  [0x109C8] mov x9, x9
  [0x109CC] mov x8, x14
  [0x109D0] sub x8, x8, x15 ;; misaligned with debug data
  [0x109D4] cmp x9, x8
  [0x109D8] b.eq #0x109ec
  [0x109DC] add x16, x9, x15
  [0x109E0] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x109E4] mov x9, x9
  [0x109E8] b #0x109f4
  [0x109EC] mov x9, x14
  [0x109F0] sub x9, x9, x15 ;; misaligned with debug data
  [0x109F4] mov x9, x9
  [0x109F8] mov x9, x9
  [0x109FC] add x16, x9, x15
  [0x10A00] ldr w8, [x16] ;; misaligned with debug data
  [0x10A04] add x16, x8, x15
  [0x10A08] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10A0C] movz x1, #0
  [0x10A10] mov x9, x9
  [0x10A14] lsl x9, x9, #0x20
  [0x10A18] lsr x9, x9, #0x20
  [0x10A1C] orr x1, x1, x9
  [0x10A20] mov x8, x8
  [0x10A24] lsl x8, x8, #0x20
  [0x10A28] orr x1, x1, x8
  [0x10A2C] add x16, x11, x15
  [0x10A30] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10A34] add x16, x9, x15
  [0x10A38] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10A3C] mov x9, x9
  [0x10A40] mov x7, x11
  [0x10A44] mov x6, x6
  [0x10A48] fmov w2, s23
  [0x10A4C] sxtw x2, w2
  [0x10A50] mov x1, x1
  [0x10A54] add x9, x9, x15
  [0x10A58] stp x3, x5, [sp, #-0x10]!
  [0x10A5C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A60] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A64] blr x9 ;; misaligned with debug data
  [0x10A68] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A6C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A70] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A74] mov x0, x0
  [0x10A78] mov x0, x0
  [0x10A7C] b #0x10a88
  [0x10A80] mov x0, x14
  [0x10A84] sub x0, x0, x15 ;; misaligned with debug data
  [0x10A88] mov x0, x0
  [0x10A8C] b #0x10a98
  [0x10A90] mov x0, x14
  [0x10A94] sub x0, x0, x15 ;; misaligned with debug data
  [0x10A98] add x16, x11, x15
  [0x10A9C] ldr s23, [x16, #0x4c] ;; misaligned with debug data
  [0x10AA0] fmov w0, s23
  [0x10AA4] sxtw x0, w0
  [0x10AA8] b #0x1207c
  [0x10AAC] movz x8, #0x5
  [0x10AB0] cmp x9, x8
  [0x10AB4] b.ne #0x10ce8
  [0x10AB8] adrp x16, #0x12000
  [0x10ABC] ldr s23, [x16, #0xfd8]
  [0x10AC0] fmov s22, w5
  [0x10AC4] fcmp s23, s22
  [0x10AC8] b.ge #0x10c74
  [0x10ACC] adrp x16, #0x10000
  [0x10AD0] add x16, x16, #0
  [0x10AD4] ldr w9, [x16]
  [0x10AD8] mov x9, x9
  [0x10ADC] add x9, x9, x15
  [0x10AE0] stp x3, x5, [sp, #-0x10]!
  [0x10AE4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AE8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AEC] blr x9 ;; misaligned with debug data
  [0x10AF0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10AF4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10AF8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AFC] mov x3, x3
  [0x10B00] adrp x16, #0x10000
  [0x10B04] add x16, x16, #0
  [0x10B08] ldr w9, [x16]
  [0x10B0C] add x16, x9, x15
  [0x10B10] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10B14] ldr x9, [x16] ;; misaligned with debug data
  [0x10B18] mov x9, x9
  [0x10B1C] add x16, x11, x15
  [0x10B20] ldur x8, [x16, #0x6c] ;; misaligned with debug data
  [0x10B24] sub x9, x9, x8
  [0x10B28] movz x8, #0xf
  [0x10B2C] cmp x9, x8
  [0x10B30] b.lt #0x10c44
  [0x10B34] adrp x16, #0x10000
  [0x10B38] add x16, x16, #0
  [0x10B3C] ldr w3, [x16]
  [0x10B40] movz x9, #0x6f6d
  [0x10B44] movk x9, #0x656e, lsl #16
  [0x10B48] movk x9, #0x2d79, lsl #32
  [0x10B4C] movk x9, #0x6970, lsl #48
  [0x10B50] fmov d23, x9
  [0x10B54] movz x9, #0x6b63
  [0x10B58] movk x9, #0x7075, lsl #16
  [0x10B5C] fmov d24, x9
  [0x10B60] zip1 v24.2d, v23.2d, v24.2d
  [0x10B64] adrp x16, #0x10000
  [0x10B68] add x16, x16, #0
  [0x10B6C] ldr w9, [x16]
  [0x10B70] mov x9, x9
  [0x10B74] add x9, x9, x15
  [0x10B78] stp x3, x5, [sp, #-0x10]!
  [0x10B7C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B80] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B84] blr x9 ;; misaligned with debug data
  [0x10B88] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B8C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10B90] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10B94] mov x0, x0
  [0x10B98] adrp x16, #0x12000
  [0x10B9C] ldr s23, [x16, #0xfdc]
  [0x10BA0] adrp x16, #0x12000
  [0x10BA4] ldr s22, [x16, #0xfe0]
  [0x10BA8] mov v23.16b, v23.16b
  [0x10BAC] fdiv s23, s23, s22
  [0x10BB0] mov v23.16b, v23.16b
  [0x10BB4] adrp x16, #0x12000
  [0x10BB8] ldr s22, [x16, #0xfe4]
  [0x10BBC] fmul s23, s23, s22
  [0x10BC0] fcvtzs w6, s23
  [0x10BC4] sxtw x6, w6
  [0x10BC8] adrp x16, #0x12000
  [0x10BCC] ldr s23, [x16, #0xfe8]
  [0x10BD0] mov v23.16b, v23.16b
  [0x10BD4] movz x9, #0
  [0x10BD8] scvtf s22, w9
  [0x10BDC] fmul s23, s23, s22
  [0x10BE0] fcvtzs w2, s23
  [0x10BE4] sxtw x2, w2
  [0x10BE8] movz x1, #0
  [0x10BEC] movz x8, #0x1
  [0x10BF0] add x9, x14, #8
  [0x10BF4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BF8] mov x3, x3
  [0x10BFC] mov v17.16b, v24.16b
  [0x10C00] mov x7, x0
  [0x10C04] mov x6, x6
  [0x10C08] mov x2, x2
  [0x10C0C] mov x1, x1
  [0x10C10] mov x8, x8
  [0x10C14] mov x9, x9
  [0x10C18] add x3, x3, x15
  [0x10C1C] stp x3, x5, [sp, #-0x10]!
  [0x10C20] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C24] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C28] blr x3 ;; misaligned with debug data
  [0x10C2C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C30] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C34] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C38] mov x0, x0
  [0x10C3C] mov x0, x0
  [0x10C40] b #0x10c4c
  [0x10C44] mov x0, x14
  [0x10C48] sub x0, x0, x15 ;; misaligned with debug data
  [0x10C4C] adrp x16, #0x10000
  [0x10C50] add x16, x16, #0
  [0x10C54] ldr w9, [x16]
  [0x10C58] add x16, x9, x15
  [0x10C5C] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10C60] ldr x9, [x16] ;; misaligned with debug data
  [0x10C64] add x16, x11, x15
  [0x10C68] stur x9, [x16, #0x6c] ;; misaligned with debug data
  [0x10C6C] mov x9, x9
  [0x10C70] b #0x10c7c
  [0x10C74] mov x9, x14
  [0x10C78] sub x9, x9, x15 ;; misaligned with debug data
  [0x10C7C] add x16, x11, x15
  [0x10C80] ldr w9, [x16] ;; misaligned with debug data
  [0x10C84] mov x9, x9
  [0x10C88] add x16, x9, x15
  [0x10C8C] ldr w7, [x16, #0xb4] ;; misaligned with debug data
  [0x10C90] adrp x6, #0x10000
  [0x10C94] add x6, x6, #0
  [0x10C98] add x16, x7, x15
  [0x10C9C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10CA0] add x16, x9, x15
  [0x10CA4] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10CA8] mov x9, x9
  [0x10CAC] mov x7, x7
  [0x10CB0] mov x6, x6
  [0x10CB4] mov x2, x5
  [0x10CB8] mov x1, x12
  [0x10CBC] add x9, x9, x15
  [0x10CC0] stp x3, x5, [sp, #-0x10]!
  [0x10CC4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CC8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CCC] blr x9 ;; misaligned with debug data
  [0x10CD0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10CD4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10CD8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10CDC] mov x0, x0
  [0x10CE0] mov x0, x0
  [0x10CE4] b #0x1207c
  [0x10CE8] movz x8, #0x6
  [0x10CEC] cmp x9, x8
  [0x10CF0] b.ne #0x10e7c
  [0x10CF4] fmov s23, w5
  [0x10CF8] fcvtzs w3, s23
  [0x10CFC] sxtw x3, w3
  [0x10D00] mov x3, x3
  [0x10D04] add x16, x11, x15
  [0x10D08] ldr w9, [x16] ;; misaligned with debug data
  [0x10D0C] mov x9, x9
  [0x10D10] add x16, x9, x15
  [0x10D14] ldr w7, [x16, #0xb4] ;; misaligned with debug data
  [0x10D18] mov x6, x3
  [0x10D1C] add x16, x7, x15
  [0x10D20] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10D24] add x16, x9, x15
  [0x10D28] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10D2C] mov x9, x9
  [0x10D30] mov x7, x7
  [0x10D34] mov x6, x6
  [0x10D38] add x9, x9, x15
  [0x10D3C] stp x3, x5, [sp, #-0x10]!
  [0x10D40] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D44] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D48] blr x9 ;; misaligned with debug data
  [0x10D4C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D50] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D54] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D58] mov x0, x0
  [0x10D5C] mov x0, x0
  [0x10D60] mov x9, x14
  [0x10D64] sub x9, x9, x15 ;; misaligned with debug data
  [0x10D68] cmp x0, x9
  [0x10D6C] b.ne #0x10d9c
  [0x10D70] movz x9, #0x1
  [0x10D74] mov x9, x9
  [0x10D78] mov x3, x3
  [0x10D7C] mov x0, x14
  [0x10D80] sub x0, x0, x15 ;; misaligned with debug data
  [0x10D84] cmp x9, x3
  [0x10D88] b.lo #0x10d98
  [0x10D8C] add x0, x14, #8
  [0x10D90] sub x0, x0, x15 ;; misaligned with debug data
  [0x10D94] mov x0, x0
  [0x10D98] mov x0, x0
  [0x10D9C] mov x9, x14
  [0x10DA0] sub x9, x9, x15 ;; misaligned with debug data
  [0x10DA4] cmp x0, x9
  [0x10DA8] b.ne #0x10e08
  [0x10DAC] adrp x16, #0x10000
  [0x10DB0] add x16, x16, #0
  [0x10DB4] ldr w9, [x16]
  [0x10DB8] mov x9, x9
  [0x10DBC] add x9, x9, x15
  [0x10DC0] stp x3, x5, [sp, #-0x10]!
  [0x10DC4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DC8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DCC] blr x9 ;; misaligned with debug data
  [0x10DD0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10DD4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10DD8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10DDC] mov x3, x3
  [0x10DE0] adrp x16, #0x10000
  [0x10DE4] add x16, x16, #0
  [0x10DE8] ldr w9, [x16]
  [0x10DEC] add x16, x9, x15
  [0x10DF0] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10DF4] ldr x9, [x16] ;; misaligned with debug data
  [0x10DF8] add x16, x11, x15
  [0x10DFC] stur x9, [x16, #0x7c] ;; misaligned with debug data
  [0x10E00] mov x9, x9
  [0x10E04] b #0x10e10
  [0x10E08] mov x9, x14
  [0x10E0C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10E10] add x16, x11, x15
  [0x10E14] ldr w9, [x16] ;; misaligned with debug data
  [0x10E18] mov x9, x9
  [0x10E1C] add x16, x9, x15
  [0x10E20] ldr w7, [x16, #0xb4] ;; misaligned with debug data
  [0x10E24] adrp x6, #0x10000
  [0x10E28] add x6, x6, #0
  [0x10E2C] add x16, x7, x15
  [0x10E30] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10E34] add x16, x9, x15
  [0x10E38] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10E3C] mov x9, x9
  [0x10E40] mov x7, x7
  [0x10E44] mov x6, x6
  [0x10E48] mov x2, x5
  [0x10E4C] mov x1, x12
  [0x10E50] add x9, x9, x15
  [0x10E54] stp x3, x5, [sp, #-0x10]!
  [0x10E58] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E5C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E60] blr x9 ;; misaligned with debug data
  [0x10E64] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10E68] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10E6C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10E70] mov x0, x0
  [0x10E74] mov x0, x0
  [0x10E78] b #0x1207c
  [0x10E7C] movz x8, #0x8
  [0x10E80] cmp x9, x8
  [0x10E84] b.ne #0x10f80
  [0x10E88] add x16, x11, x15
  [0x10E8C] ldr w9, [x16] ;; misaligned with debug data
  [0x10E90] mov x9, x9
  [0x10E94] add x16, x9, x15
  [0x10E98] ldr w7, [x16, #0xb4] ;; misaligned with debug data
  [0x10E9C] adrp x6, #0x10000
  [0x10EA0] add x6, x6, #0
  [0x10EA4] add x16, x7, x15
  [0x10EA8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10EAC] add x16, x9, x15
  [0x10EB0] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10EB4] mov x9, x9
  [0x10EB8] mov x7, x7
  [0x10EBC] mov x6, x6
  [0x10EC0] mov x2, x5
  [0x10EC4] mov x1, x12
  [0x10EC8] add x9, x9, x15
  [0x10ECC] stp x3, x5, [sp, #-0x10]!
  [0x10ED0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10ED4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10ED8] blr x9 ;; misaligned with debug data
  [0x10EDC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10EE0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10EE4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10EE8] mov x0, x0
  [0x10EEC] fmov s24, w0
  [0x10EF0] add x16, x11, x15
  [0x10EF4] ldr s23, [x16, #0x44] ;; misaligned with debug data
  [0x10EF8] fcmp s24, s23
  [0x10EFC] b.eq #0x10f5c
  [0x10F00] adrp x16, #0x10000
  [0x10F04] add x16, x16, #0
  [0x10F08] ldr w9, [x16]
  [0x10F0C] mov x9, x9
  [0x10F10] add x9, x9, x15
  [0x10F14] stp x3, x5, [sp, #-0x10]!
  [0x10F18] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F1C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F20] blr x9 ;; misaligned with debug data
  [0x10F24] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10F28] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10F2C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10F30] mov x3, x3
  [0x10F34] adrp x16, #0x10000
  [0x10F38] add x16, x16, #0
  [0x10F3C] ldr w9, [x16]
  [0x10F40] add x16, x9, x15
  [0x10F44] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10F48] ldr x9, [x16] ;; misaligned with debug data
  [0x10F4C] add x16, x11, x15
  [0x10F50] stur x9, [x16, #0x74] ;; misaligned with debug data
  [0x10F54] mov x9, x9
  [0x10F58] b #0x10f64
  [0x10F5C] mov x9, x14
  [0x10F60] sub x9, x9, x15 ;; misaligned with debug data
  [0x10F64] add x16, x11, x15
  [0x10F68] str s24, [x16, #0x44] ;; misaligned with debug data
  [0x10F6C] add x16, x11, x15
  [0x10F70] ldr s23, [x16, #0x44] ;; misaligned with debug data
  [0x10F74] fmov w0, s23
  [0x10F78] sxtw x0, w0
  [0x10F7C] b #0x1207c
  [0x10F80] movz x8, #0x2
  [0x10F84] mov x1, x14
  [0x10F88] sub x1, x1, x15 ;; misaligned with debug data
  [0x10F8C] cmp x9, x8
  [0x10F90] b.ne #0x10fa0
  [0x10F94] add x1, x14, #8
  [0x10F98] sub x1, x1, x15 ;; misaligned with debug data
  [0x10F9C] mov x1, x1
  [0x10FA0] mov x8, x1
  [0x10FA4] mov x1, x14
  [0x10FA8] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FAC] cmp x8, x1
  [0x10FB0] b.ne #0x1100c
  [0x10FB4] movz x8, #0x3
  [0x10FB8] mov x1, x14
  [0x10FBC] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FC0] cmp x9, x8
  [0x10FC4] b.ne #0x10fd4
  [0x10FC8] add x1, x14, #8
  [0x10FCC] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FD0] mov x1, x1
  [0x10FD4] mov x8, x1
  [0x10FD8] mov x1, x14
  [0x10FDC] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FE0] cmp x8, x1
  [0x10FE4] b.ne #0x1100c
  [0x10FE8] movz x8, #0x1
  [0x10FEC] mov x1, x14
  [0x10FF0] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FF4] cmp x9, x8
  [0x10FF8] b.ne #0x11008
  [0x10FFC] add x1, x14, #8
  [0x11000] sub x1, x1, x15 ;; misaligned with debug data
  [0x11004] mov x1, x1
  [0x11008] mov x8, x1
  [0x1100C] mov x9, x14
  [0x11010] sub x9, x9, x15 ;; misaligned with debug data
  [0x11014] cmp x8, x9
  [0x11018] b.eq #0x1202c
  [0x1101C] fmov s23, w5
  [0x11020] adrp x16, #0x12000
  [0x11024] ldr s22, [x16, #0xfec]
  [0x11028] fcmp s23, s22
  [0x1102C] b.ne #0x11070
  [0x11030] add x16, x11, x15
  [0x11034] ldrsw x9, [x16, #0x24] ;; misaligned with debug data
  [0x11038] cmp x9, x3
  [0x1103C] b.ne #0x11054
  [0x11040] add x16, x11, x15
  [0x11044] ldr s23, [x16, #0x28] ;; misaligned with debug data
  [0x11048] fmov w0, s23
  [0x1104C] sxtw x0, w0
  [0x11050] b #0x11064
  [0x11054] adrp x16, #0x12000
  [0x11058] ldr s23, [x16, #0xff0]
  [0x1105C] fmov w0, s23
  [0x11060] sxtw x0, w0
  [0x11064] mov x0, x0
  [0x11068] b #0x12080
  [0x1106C] b #0x11078
  [0x11070] mov x9, x14
  [0x11074] sub x9, x9, x15 ;; misaligned with debug data
  [0x11078] add x16, x11, x15
  [0x1107C] ldrsw x9, [x16, #0x24] ;; misaligned with debug data
  [0x11080] cmp x9, x3
  [0x11084] b.eq #0x110ac
  [0x11088] adrp x16, #0x12000
  [0x1108C] ldr s23, [x16, #0xff4]
  [0x11090] add x16, x11, x15
  [0x11094] str s23, [x16, #0x28] ;; misaligned with debug data
  [0x11098] movz x9, #0
  [0x1109C] add x16, x11, x15
  [0x110A0] stur x9, [x16, #0x34] ;; misaligned with debug data
  [0x110A4] mov x9, x9
  [0x110A8] b #0x110b4
  [0x110AC] mov x9, x14
  [0x110B0] sub x9, x9, x15 ;; misaligned with debug data
  [0x110B4] add x16, x11, x15
  [0x110B8] str w3, [x16, #0x24] ;; misaligned with debug data
  [0x110BC] add x16, x11, x15
  [0x110C0] ldr s24, [x16, #0x28] ;; misaligned with debug data
  [0x110C4] mov v24.16b, v24.16b
  [0x110C8] adrp x16, #0x12000
  [0x110CC] ldr s23, [x16, #0xff8]
  [0x110D0] add x16, x11, x15
  [0x110D4] str s23, [x16, #0x28] ;; misaligned with debug data
  [0x110D8] adrp x16, #0x12000
  [0x110DC] ldr s23, [x16, #0xffc]
  [0x110E0] mov x9, x14
  [0x110E4] sub x9, x9, x15 ;; misaligned with debug data
  [0x110E8] fcmp s24, s23
  [0x110EC] b.ne #0x110fc
  [0x110F0] add x9, x14, #8
  [0x110F4] sub x9, x9, x15 ;; misaligned with debug data
  [0x110F8] mov x9, x9
  [0x110FC] mov x9, x9
  [0x11100] mov x8, x14
  [0x11104] sub x8, x8, x15 ;; misaligned with debug data
  [0x11108] cmp x9, x8
  [0x1110C] b.eq #0x11140
  [0x11110] adrp x16, #0x13000
  [0x11114] ldr s23, [x16]
  [0x11118] add x16, x11, x15
  [0x1111C] ldr s22, [x16, #0x28] ;; misaligned with debug data
  [0x11120] mov x9, x14
  [0x11124] sub x9, x9, x15 ;; misaligned with debug data
  [0x11128] fcmp s23, s22
  [0x1112C] b.ge #0x1113c
  [0x11130] add x9, x14, #8
  [0x11134] sub x9, x9, x15 ;; misaligned with debug data
  [0x11138] mov x9, x9
  [0x1113C] mov x9, x9
  [0x11140] mov x8, x14
  [0x11144] sub x8, x8, x15 ;; misaligned with debug data
  [0x11148] cmp x9, x8
  [0x1114C] b.eq #0x111ec
  [0x11150] adrp x16, #0x11000
  [0x11154] add x16, x16, #0
  [0x11158] ldr w9, [x16]
  [0x1115C] add x16, x9, x15
  [0x11160] add x16, x16, #0x314 ;; misaligned with debug data
  [0x11164] ldr x9, [x16] ;; misaligned with debug data
  [0x11168] add x16, x11, x15
  [0x1116C] stur x9, [x16, #0x2c] ;; misaligned with debug data
  [0x11170] mov x6, sp
  [0x11174] sub x6, x6, x15
  [0x11178] mov x6, x6
  [0x1117C] add x16, x6, x15
  [0x11180] str w13, [x16, #4] ;; misaligned with debug data
  [0x11184] movz x9, #0
  [0x11188] add x16, x6, x15
  [0x1118C] str w9, [x16, #8] ;; misaligned with debug data
  [0x11190] adrp x9, #0x11000
  [0x11194] add x9, x9, #0
  [0x11198] add x16, x6, x15
  [0x1119C] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x111A0] adrp x16, #0x11000
  [0x111A4] add x16, x16, #0
  [0x111A8] ldr w9, [x16]
  [0x111AC] add x16, x11, x15
  [0x111B0] ldr w7, [x16] ;; misaligned with debug data
  [0x111B4] mov x9, x9
  [0x111B8] mov x7, x7
  [0x111BC] mov x6, x6
  [0x111C0] add x9, x9, x15
  [0x111C4] stp x3, x5, [sp, #-0x10]!
  [0x111C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x111CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x111D0] blr x9 ;; misaligned with debug data
  [0x111D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x111D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x111DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x111E0] mov x0, x0
  [0x111E4] mov x0, x0
  [0x111E8] b #0x111f4
  [0x111EC] mov x0, x14
  [0x111F0] sub x0, x0, x15 ;; misaligned with debug data
  [0x111F4] add x16, x11, x15
  [0x111F8] ldur x9, [x16, #0x34] ;; misaligned with debug data
  [0x111FC] mov x9, x9
  [0x11200] adrp x16, #0x11000
  [0x11204] add x16, x16, #0
  [0x11208] ldr w8, [x16]
  [0x1120C] add x16, x8, x15
  [0x11210] ldur x8, [x16, #0xc] ;; misaligned with debug data
  [0x11214] mov x8, x8
  [0x11218] mov x8, x8
  [0x1121C] fmov s23, w5
  [0x11220] fcvtzs w1, s23
  [0x11224] sxtw x1, w1
  [0x11228] mul x8, x8, x1
  [0x1122C] add x9, x9, x8
  [0x11230] mov x9, x9
  [0x11234] adrp x16, #0x11000
  [0x11238] add x16, x16, #0
  [0x1123C] ldr w8, [x16]
  [0x11240] add x16, x8, x15
  [0x11244] ldur x8, [x16, #0x14] ;; misaligned with debug data
  [0x11248] mov x8, x8
  [0x1124C] adrp x16, #0x11000
  [0x11250] add x16, x16, #0
  [0x11254] ldr w1, [x16]
  [0x11258] add x16, x1, x15
  [0x1125C] add x16, x16, #0x314 ;; misaligned with debug data
  [0x11260] ldr x1, [x16] ;; misaligned with debug data
  [0x11264] mov x1, x1
  [0x11268] add x16, x11, x15
  [0x1126C] ldur x2, [x16, #0x2c] ;; misaligned with debug data
  [0x11270] sub x1, x1, x2
  [0x11274] add x8, x8, x1
  [0x11278] mov x8, x8
  [0x1127C] mov x9, x9
  [0x11280] mov x8, x8
  [0x11284] cmp x9, x8
  [0x11288] b.le #0x11294
  [0x1128C] mov x8, x8
  [0x11290] b #0x11298
  [0x11294] mov x8, x9
  [0x11298] mov x8, x8
  [0x1129C] add x16, x11, x15
  [0x112A0] stur x8, [x16, #0x34] ;; misaligned with debug data
  [0x112A4] add x16, x11, x15
  [0x112A8] ldur x9, [x16, #0x34] ;; misaligned with debug data
  [0x112AC] mov x9, x9
  [0x112B0] adrp x16, #0x11000
  [0x112B4] add x16, x16, #0
  [0x112B8] ldr w8, [x16]
  [0x112BC] add x16, x8, x15
  [0x112C0] add x16, x16, #0x314 ;; misaligned with debug data
  [0x112C4] ldr x8, [x16] ;; misaligned with debug data
  [0x112C8] mov x8, x8
  [0x112CC] add x16, x11, x15
  [0x112D0] ldur x1, [x16, #0x2c] ;; misaligned with debug data
  [0x112D4] sub x8, x8, x1
  [0x112D8] mov x8, x8
  [0x112DC] sub x9, x9, x8
  [0x112E0] mov x9, x9
  [0x112E4] adrp x16, #0x11000
  [0x112E8] add x16, x16, #0
  [0x112EC] ldr w8, [x16]
  [0x112F0] add x16, x8, x15
  [0x112F4] ldur x8, [x16, #0x14] ;; misaligned with debug data
  [0x112F8] mov x8, x8
  [0x112FC] cmp x9, x8
  [0x11300] b.lt #0x11320
  [0x11304] adrp x16, #0x13000
  [0x11308] ldr s23, [x16, #4]
  [0x1130C] add x16, x11, x15
  [0x11310] str s23, [x16, #0x28] ;; misaligned with debug data
  [0x11314] fmov w9, s23
  [0x11318] sxtw x9, w9
  [0x1131C] b #0x11328
  [0x11320] mov x9, x14
  [0x11324] sub x9, x9, x15 ;; misaligned with debug data
  [0x11328] mov x9, x12
  [0x1132C] mov x9, x9
  [0x11330] mov x8, x9
  [0x11334] lsl x8, x8, #0x20
  [0x11338] lsr x8, x8, #0x20
  [0x1133C] mov x1, x14
  [0x11340] sub x1, x1, x15 ;; misaligned with debug data
  [0x11344] cmp x8, x1
  [0x11348] b.eq #0x11394
  [0x1134C] mov x8, x9
  [0x11350] lsl x8, x8, #0x20
  [0x11354] lsr x8, x8, #0x20
  [0x11358] add x16, x8, x15
  [0x1135C] ldr w8, [x16] ;; misaligned with debug data
  [0x11360] mov x8, x8
  [0x11364] mov x9, x9
  [0x11368] asr x9, x9, #0x20
  [0x1136C] add x16, x8, x15
  [0x11370] ldrsw x1, [x16, #0x24] ;; misaligned with debug data
  [0x11374] cmp x9, x1
  [0x11378] b.ne #0x11384
  [0x1137C] mov x8, x8
  [0x11380] b #0x1138c
  [0x11384] mov x8, x14
  [0x11388] sub x8, x8, x15 ;; misaligned with debug data
  [0x1138C] mov x9, x8
  [0x11390] b #0x1139c
  [0x11394] mov x9, x14
  [0x11398] sub x9, x9, x15 ;; misaligned with debug data
  [0x1139C] add x16, x11, x15
  [0x113A0] ldur x8, [x16, #0x5c] ;; misaligned with debug data
  [0x113A4] mov x8, x8
  [0x113A8] mov x8, x8
  [0x113AC] mov x1, x8
  [0x113B0] lsl x1, x1, #0x20
  [0x113B4] lsr x1, x1, #0x20
  [0x113B8] mov x2, x14
  [0x113BC] sub x2, x2, x15 ;; misaligned with debug data
  [0x113C0] cmp x1, x2
  [0x113C4] b.eq #0x11410
  [0x113C8] mov x1, x8
  [0x113CC] lsl x1, x1, #0x20
  [0x113D0] lsr x1, x1, #0x20
  [0x113D4] add x16, x1, x15
  [0x113D8] ldr w1, [x16] ;; misaligned with debug data
  [0x113DC] mov x1, x1
  [0x113E0] mov x8, x8
  [0x113E4] asr x8, x8, #0x20
  [0x113E8] add x16, x1, x15
  [0x113EC] ldrsw x2, [x16, #0x24] ;; misaligned with debug data
  [0x113F0] cmp x8, x2
  [0x113F4] b.ne #0x11400
  [0x113F8] mov x1, x1
  [0x113FC] b #0x11408
  [0x11400] mov x1, x14
  [0x11404] sub x1, x1, x15 ;; misaligned with debug data
  [0x11408] mov x8, x1
  [0x1140C] b #0x11418
  [0x11410] mov x8, x14
  [0x11414] sub x8, x8, x15 ;; misaligned with debug data
  [0x11418] mov x1, x14
  [0x1141C] sub x1, x1, x15 ;; misaligned with debug data
  [0x11420] cmp x9, x8
  [0x11424] b.ne #0x11434
  [0x11428] add x1, x14, #8
  [0x1142C] sub x1, x1, x15 ;; misaligned with debug data
  [0x11430] mov x1, x1
  [0x11434] mov x9, x1
  [0x11438] mov x8, x14
  [0x1143C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11440] cmp x9, x8
  [0x11444] b.eq #0x11494
  [0x11448] adrp x16, #0x11000
  [0x1144C] add x16, x16, #0
  [0x11450] ldr w9, [x16]
  [0x11454] add x16, x9, x15
  [0x11458] add x16, x16, #0x30c ;; misaligned with debug data
  [0x1145C] ldr x9, [x16] ;; misaligned with debug data
  [0x11460] mov x9, x9
  [0x11464] add x16, x11, x15
  [0x11468] ldur x8, [x16, #0x64] ;; misaligned with debug data
  [0x1146C] sub x9, x9, x8
  [0x11470] movz x8, #0x96
  [0x11474] mov x1, x14
  [0x11478] sub x1, x1, x15 ;; misaligned with debug data
  [0x1147C] cmp x9, x8
  [0x11480] b.ge #0x11490
  [0x11484] add x1, x14, #8
  [0x11488] sub x1, x1, x15 ;; misaligned with debug data
  [0x1148C] mov x1, x1
  [0x11490] mov x9, x1
  [0x11494] mov x8, x14
  [0x11498] sub x8, x8, x15 ;; misaligned with debug data
  [0x1149C] cmp x9, x8
  [0x114A0] b.ne #0x119f8
  [0x114A4] adrp x16, #0x11000
  [0x114A8] add x16, x16, #0
  [0x114AC] ldr w9, [x16]
  [0x114B0] adrp x16, #0x11000
  [0x114B4] add x16, x16, #0
  [0x114B8] ldr w8, [x16]
  [0x114BC] add x16, x8, x15
  [0x114C0] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x114C4] movz x6, #0x1
  [0x114C8] movz x2, #0x7f
  [0x114CC] movz x1, #0x3c
  [0x114D0] mov x9, x9
  [0x114D4] mov x7, x7
  [0x114D8] mov x6, x6
  [0x114DC] mov x2, x2
  [0x114E0] mov x1, x1
  [0x114E4] add x9, x9, x15
  [0x114E8] stp x3, x5, [sp, #-0x10]!
  [0x114EC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x114F0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x114F4] blr x9 ;; misaligned with debug data
  [0x114F8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x114FC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11500] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11504] mov x5, x5
  [0x11508] adrp x16, #0x11000
  [0x1150C] add x16, x16, #0
  [0x11510] ldr w9, [x16]
  [0x11514] adrp x16, #0x11000
  [0x11518] add x16, x16, #0
  [0x1151C] ldr w8, [x16]
  [0x11520] add x16, x8, x15
  [0x11524] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x11528] movz x6, #0
  [0x1152C] movz x2, #0x11
  [0x11530] movz x1, #0x3c
  [0x11534] mov x9, x9
  [0x11538] mov x7, x7
  [0x1153C] mov x6, x6
  [0x11540] mov x2, x2
  [0x11544] mov x1, x1
  [0x11548] add x9, x9, x15
  [0x1154C] stp x3, x5, [sp, #-0x10]!
  [0x11550] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11554] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11558] blr x9 ;; misaligned with debug data
  [0x1155C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11560] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11564] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11568] mov x5, x5
  [0x1156C] mov x9, x3
  [0x11570] movz x8, #0x3
  [0x11574] cmp x9, x8
  [0x11578] b.ne #0x1168c
  [0x1157C] adrp x16, #0x11000
  [0x11580] add x16, x16, #0
  [0x11584] ldr w5, [x16]
  [0x11588] movz x9, #0x6567
  [0x1158C] movk x9, #0x2d74, lsl #16
  [0x11590] movk x9, #0x6c62, lsl #32
  [0x11594] movk x9, #0x6575, lsl #48
  [0x11598] fmov d23, x9
  [0x1159C] movz x9, #0x652d
  [0x115A0] movk x9, #0x6f63, lsl #16
  [0x115A4] fmov d25, x9
  [0x115A8] zip1 v25.2d, v23.2d, v25.2d
  [0x115AC] adrp x16, #0x11000
  [0x115B0] add x16, x16, #0
  [0x115B4] ldr w9, [x16]
  [0x115B8] mov x9, x9
  [0x115BC] add x9, x9, x15
  [0x115C0] stp x3, x5, [sp, #-0x10]!
  [0x115C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x115C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x115CC] blr x9 ;; misaligned with debug data
  [0x115D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x115D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x115D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x115DC] mov x0, x0
  [0x115E0] adrp x16, #0x13000
  [0x115E4] ldr s23, [x16, #8]
  [0x115E8] adrp x16, #0x13000
  [0x115EC] ldr s22, [x16, #0xc]
  [0x115F0] mov v23.16b, v23.16b
  [0x115F4] fdiv s23, s23, s22
  [0x115F8] mov v23.16b, v23.16b
  [0x115FC] adrp x16, #0x13000
  [0x11600] ldr s22, [x16, #0x10]
  [0x11604] fmul s23, s23, s22
  [0x11608] fcvtzs w6, s23
  [0x1160C] sxtw x6, w6
  [0x11610] adrp x16, #0x13000
  [0x11614] ldr s23, [x16, #0x14]
  [0x11618] mov v23.16b, v23.16b
  [0x1161C] movz x9, #0
  [0x11620] scvtf s22, w9
  [0x11624] fmul s23, s23, s22
  [0x11628] fcvtzs w2, s23
  [0x1162C] sxtw x2, w2
  [0x11630] movz x1, #0
  [0x11634] movz x8, #0x1
  [0x11638] add x9, x14, #8
  [0x1163C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11640] mov x5, x5
  [0x11644] mov v17.16b, v25.16b
  [0x11648] mov x7, x0
  [0x1164C] mov x6, x6
  [0x11650] mov x2, x2
  [0x11654] mov x1, x1
  [0x11658] mov x8, x8
  [0x1165C] mov x9, x9
  [0x11660] add x5, x5, x15
  [0x11664] stp x3, x5, [sp, #-0x10]!
  [0x11668] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1166C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11670] blr x5 ;; misaligned with debug data
  [0x11674] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11678] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1167C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11680] mov x0, x0
  [0x11684] mov x0, x0
  [0x11688] b #0x119f0
  [0x1168C] movz x8, #0x4
  [0x11690] cmp x9, x8
  [0x11694] b.ne #0x117ac
  [0x11698] adrp x16, #0x11000
  [0x1169C] add x16, x16, #0
  [0x116A0] ldr w5, [x16]
  [0x116A4] movz x9, #0x6567
  [0x116A8] movk x9, #0x2d74, lsl #16
  [0x116AC] movk x9, #0x7267, lsl #32
  [0x116B0] movk x9, #0x6565, lsl #48
  [0x116B4] fmov d23, x9
  [0x116B8] movz x9, #0x2d6e
  [0x116BC] movk x9, #0x6365, lsl #16
  [0x116C0] movk x9, #0x6f, lsl #32
  [0x116C4] fmov d25, x9
  [0x116C8] zip1 v25.2d, v23.2d, v25.2d
  [0x116CC] adrp x16, #0x11000
  [0x116D0] add x16, x16, #0
  [0x116D4] ldr w9, [x16]
  [0x116D8] mov x9, x9
  [0x116DC] add x9, x9, x15
  [0x116E0] stp x3, x5, [sp, #-0x10]!
  [0x116E4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x116E8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x116EC] blr x9 ;; misaligned with debug data
  [0x116F0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x116F4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x116F8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x116FC] mov x0, x0
  [0x11700] adrp x16, #0x13000
  [0x11704] ldr s23, [x16, #0x18]
  [0x11708] adrp x16, #0x13000
  [0x1170C] ldr s22, [x16, #0x1c]
  [0x11710] mov v23.16b, v23.16b
  [0x11714] fdiv s23, s23, s22
  [0x11718] mov v23.16b, v23.16b
  [0x1171C] adrp x16, #0x13000
  [0x11720] ldr s22, [x16, #0x20]
  [0x11724] fmul s23, s23, s22
  [0x11728] fcvtzs w6, s23
  [0x1172C] sxtw x6, w6
  [0x11730] adrp x16, #0x13000
  [0x11734] ldr s23, [x16, #0x24]
  [0x11738] mov v23.16b, v23.16b
  [0x1173C] movz x9, #0
  [0x11740] scvtf s22, w9
  [0x11744] fmul s23, s23, s22
  [0x11748] fcvtzs w2, s23
  [0x1174C] sxtw x2, w2
  [0x11750] movz x1, #0
  [0x11754] movz x8, #0x1
  [0x11758] add x9, x14, #8
  [0x1175C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11760] mov x5, x5
  [0x11764] mov v17.16b, v25.16b
  [0x11768] mov x7, x0
  [0x1176C] mov x6, x6
  [0x11770] mov x2, x2
  [0x11774] mov x1, x1
  [0x11778] mov x8, x8
  [0x1177C] mov x9, x9
  [0x11780] add x5, x5, x15
  [0x11784] stp x3, x5, [sp, #-0x10]!
  [0x11788] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1178C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11790] blr x5 ;; misaligned with debug data
  [0x11794] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11798] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1179C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x117A0] mov x0, x0
  [0x117A4] mov x0, x0
  [0x117A8] b #0x119f0
  [0x117AC] movz x8, #0x1
  [0x117B0] cmp x9, x8
  [0x117B4] b.ne #0x118cc
  [0x117B8] adrp x16, #0x11000
  [0x117BC] add x16, x16, #0
  [0x117C0] ldr w5, [x16]
  [0x117C4] movz x9, #0x6567
  [0x117C8] movk x9, #0x2d74, lsl #16
  [0x117CC] movk x9, #0x6579, lsl #32
  [0x117D0] movk x9, #0x6c6c, lsl #48
  [0x117D4] fmov d23, x9
  [0x117D8] movz x9, #0x776f
  [0x117DC] movk x9, #0x652d, lsl #16
  [0x117E0] movk x9, #0x6f63, lsl #32
  [0x117E4] fmov d25, x9
  [0x117E8] zip1 v25.2d, v23.2d, v25.2d
  [0x117EC] adrp x16, #0x11000
  [0x117F0] add x16, x16, #0
  [0x117F4] ldr w9, [x16]
  [0x117F8] mov x9, x9
  [0x117FC] add x9, x9, x15
  [0x11800] stp x3, x5, [sp, #-0x10]!
  [0x11804] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11808] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1180C] blr x9 ;; misaligned with debug data
  [0x11810] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11814] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11818] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1181C] mov x0, x0
  [0x11820] adrp x16, #0x13000
  [0x11824] ldr s23, [x16, #0x28]
  [0x11828] adrp x16, #0x13000
  [0x1182C] ldr s22, [x16, #0x2c]
  [0x11830] mov v23.16b, v23.16b
  [0x11834] fdiv s23, s23, s22
  [0x11838] mov v23.16b, v23.16b
  [0x1183C] adrp x16, #0x13000
  [0x11840] ldr s22, [x16, #0x30]
  [0x11844] fmul s23, s23, s22
  [0x11848] fcvtzs w6, s23
  [0x1184C] sxtw x6, w6
  [0x11850] adrp x16, #0x13000
  [0x11854] ldr s23, [x16, #0x34]
  [0x11858] mov v23.16b, v23.16b
  [0x1185C] movz x9, #0
  [0x11860] scvtf s22, w9
  [0x11864] fmul s23, s23, s22
  [0x11868] fcvtzs w2, s23
  [0x1186C] sxtw x2, w2
  [0x11870] movz x1, #0
  [0x11874] movz x8, #0x1
  [0x11878] add x9, x14, #8
  [0x1187C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11880] mov x5, x5
  [0x11884] mov v17.16b, v25.16b
  [0x11888] mov x7, x0
  [0x1188C] mov x6, x6
  [0x11890] mov x2, x2
  [0x11894] mov x1, x1
  [0x11898] mov x8, x8
  [0x1189C] mov x9, x9
  [0x118A0] add x5, x5, x15
  [0x118A4] stp x3, x5, [sp, #-0x10]!
  [0x118A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x118AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x118B0] blr x5 ;; misaligned with debug data
  [0x118B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x118B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x118BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x118C0] mov x0, x0
  [0x118C4] mov x0, x0
  [0x118C8] b #0x119f0
  [0x118CC] movz x8, #0x2
  [0x118D0] cmp x9, x8
  [0x118D4] b.ne #0x119e8
  [0x118D8] adrp x16, #0x11000
  [0x118DC] add x16, x16, #0
  [0x118E0] ldr w5, [x16]
  [0x118E4] movz x9, #0x6567
  [0x118E8] movk x9, #0x2d74, lsl #16
  [0x118EC] movk x9, #0x6572, lsl #32
  [0x118F0] movk x9, #0x2d64, lsl #48
  [0x118F4] fmov d23, x9
  [0x118F8] movz x9, #0x6365
  [0x118FC] movk x9, #0x6f, lsl #16
  [0x11900] fmov d25, x9
  [0x11904] zip1 v25.2d, v23.2d, v25.2d
  [0x11908] adrp x16, #0x11000
  [0x1190C] add x16, x16, #0
  [0x11910] ldr w9, [x16]
  [0x11914] mov x9, x9
  [0x11918] add x9, x9, x15
  [0x1191C] stp x3, x5, [sp, #-0x10]!
  [0x11920] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11924] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11928] blr x9 ;; misaligned with debug data
  [0x1192C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11930] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11934] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11938] mov x0, x0
  [0x1193C] adrp x16, #0x13000
  [0x11940] ldr s23, [x16, #0x38]
  [0x11944] adrp x16, #0x13000
  [0x11948] ldr s22, [x16, #0x3c]
  [0x1194C] mov v23.16b, v23.16b
  [0x11950] fdiv s23, s23, s22
  [0x11954] mov v23.16b, v23.16b
  [0x11958] adrp x16, #0x13000
  [0x1195C] ldr s22, [x16, #0x40]
  [0x11960] fmul s23, s23, s22
  [0x11964] fcvtzs w6, s23
  [0x11968] sxtw x6, w6
  [0x1196C] adrp x16, #0x13000
  [0x11970] ldr s23, [x16, #0x44]
  [0x11974] mov v23.16b, v23.16b
  [0x11978] movz x9, #0
  [0x1197C] scvtf s22, w9
  [0x11980] fmul s23, s23, s22
  [0x11984] fcvtzs w2, s23
  [0x11988] sxtw x2, w2
  [0x1198C] movz x1, #0
  [0x11990] movz x8, #0x1
  [0x11994] add x9, x14, #8
  [0x11998] sub x9, x9, x15 ;; misaligned with debug data
  [0x1199C] mov x5, x5
  [0x119A0] mov v17.16b, v25.16b
  [0x119A4] mov x7, x0
  [0x119A8] mov x6, x6
  [0x119AC] mov x2, x2
  [0x119B0] mov x1, x1
  [0x119B4] mov x8, x8
  [0x119B8] mov x9, x9
  [0x119BC] add x5, x5, x15
  [0x119C0] stp x3, x5, [sp, #-0x10]!
  [0x119C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x119C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x119CC] blr x5 ;; misaligned with debug data
  [0x119D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x119D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x119D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x119DC] mov x0, x0
  [0x119E0] mov x0, x0
  [0x119E4] b #0x119f0
  [0x119E8] mov x0, x14
  [0x119EC] sub x0, x0, x15 ;; misaligned with debug data
  [0x119F0] mov x0, x0
  [0x119F4] b #0x11a00
  [0x119F8] mov x0, x14
  [0x119FC] sub x0, x0, x15 ;; misaligned with debug data
  [0x11A00] add x16, x11, x15
  [0x11A04] stur x12, [x16, #0x5c] ;; misaligned with debug data
  [0x11A08] adrp x16, #0x11000
  [0x11A0C] add x16, x16, #0
  [0x11A10] ldr w9, [x16]
  [0x11A14] add x16, x9, x15
  [0x11A18] add x16, x16, #0x30c ;; misaligned with debug data
  [0x11A1C] ldr x9, [x16] ;; misaligned with debug data
  [0x11A20] add x16, x11, x15
  [0x11A24] stur x9, [x16, #0x64] ;; misaligned with debug data
  [0x11A28] movz x9, #0x3
  [0x11A2C] cmp x3, x9
  [0x11A30] b.ne #0x12010
  [0x11A34] adrp x16, #0x13000
  [0x11A38] ldr s23, [x16, #0x48]
  [0x11A3C] fcmp s24, s23
  [0x11A40] b.ne #0x12000
  [0x11A44] add x16, x11, x15
  [0x11A48] ldr w3, [x16] ;; misaligned with debug data
  [0x11A4C] mov x5, x3
  [0x11A50] adrp x16, #0x11000
  [0x11A54] add x16, x16, #0
  [0x11A58] ldr w7, [x16]
  [0x11A5C] adrp x16, #0x11000
  [0x11A60] add x16, x16, #0
  [0x11A64] ldr w6, [x16]
  [0x11A68] movz x2, #0x4000
  [0x11A6C] add x16, x7, x15
  [0x11A70] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11A74] add x16, x9, x15
  [0x11A78] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x11A7C] mov x9, x9
  [0x11A80] mov x7, x7
  [0x11A84] mov x6, x6
  [0x11A88] mov x2, x2
  [0x11A8C] add x9, x9, x15
  [0x11A90] stp x3, x5, [sp, #-0x10]!
  [0x11A94] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11A98] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11A9C] blr x9 ;; misaligned with debug data
  [0x11AA0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11AA4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11AA8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11AAC] mov x0, x0
  [0x11AB0] mov x3, x0
  [0x11AB4] mov x3, x3
  [0x11AB8] mov x9, x14
  [0x11ABC] sub x9, x9, x15 ;; misaligned with debug data
  [0x11AC0] cmp x3, x9
  [0x11AC4] b.eq #0x11bc0
  [0x11AC8] adrp x16, #0x11000
  [0x11ACC] add x16, x16, #0
  [0x11AD0] ldr w9, [x16]
  [0x11AD4] add x16, x9, x15
  [0x11AD8] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x11ADC] adrp x2, #0x11000
  [0x11AE0] add x2, x2, #0
  [0x11AE4] movz x1, #0x4000
  [0x11AE8] movk x1, #0x7000, lsl #16
  [0x11AEC] mov x1, x1
  [0x11AF0] mov x9, x9
  [0x11AF4] mov x7, x3
  [0x11AF8] mov x6, x5
  [0x11AFC] mov x2, x2
  [0x11B00] mov x1, x1
  [0x11B04] add x9, x9, x15
  [0x11B08] stp x3, x5, [sp, #-0x10]!
  [0x11B0C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11B10] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11B14] blr x9 ;; misaligned with debug data
  [0x11B18] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11B1C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11B20] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11B24] mov x0, x0
  [0x11B28] adrp x16, #0x11000
  [0x11B2C] add x16, x16, #0
  [0x11B30] ldr w9, [x16]
  [0x11B34] mov x9, x9
  [0x11B38] adrp x16, #0x11000
  [0x11B3C] add x16, x16, #0
  [0x11B40] ldr w6, [x16]
  [0x11B44] movz x2, #0xc
  [0x11B48] add x16, x5, x15
  [0x11B4C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x11B50] add x2, x2, x8
  [0x11B54] adrp x16, #0x11000
  [0x11B58] add x16, x16, #0
  [0x11B5C] ldr w8, [x16]
  [0x11B60] add x16, x8, x15
  [0x11B64] ldr s23, [x16, #0x3c] ;; misaligned with debug data
  [0x11B68] movz x8, #0x12c
  [0x11B6C] mov x9, x9
  [0x11B70] mov x7, x3
  [0x11B74] mov x6, x6
  [0x11B78] mov x2, x2
  [0x11B7C] fmov w1, s23
  [0x11B80] sxtw x1, w1
  [0x11B84] mov x8, x8
  [0x11B88] add x9, x9, x15
  [0x11B8C] stp x3, x5, [sp, #-0x10]!
  [0x11B90] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11B94] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11B98] blr x9 ;; misaligned with debug data
  [0x11B9C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11BA0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11BA4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11BA8] mov x0, x0
  [0x11BAC] add x16, x3, x15
  [0x11BB0] ldr w3, [x16, #0x14] ;; misaligned with debug data
  [0x11BB4] mov x3, x3
  [0x11BB8] mov x3, x3
  [0x11BBC] b #0x11bc8
  [0x11BC0] mov x3, x14
  [0x11BC4] sub x3, x3, x15 ;; misaligned with debug data
  [0x11BC8] mov x3, x3
  [0x11BCC] mov x6, sp
  [0x11BD0] sub x6, x6, x15
  [0x11BD4] mov x6, x6
  [0x11BD8] add x16, x6, x15
  [0x11BDC] str w13, [x16, #4] ;; misaligned with debug data
  [0x11BE0] movz x9, #0x1
  [0x11BE4] add x16, x6, x15
  [0x11BE8] str w9, [x16, #8] ;; misaligned with debug data
  [0x11BEC] adrp x9, #0x11000
  [0x11BF0] add x9, x9, #0
  [0x11BF4] add x16, x6, x15
  [0x11BF8] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x11BFC] mov x9, x5
  [0x11C00] add x16, x6, x15
  [0x11C04] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x11C08] adrp x16, #0x11000
  [0x11C0C] add x16, x16, #0
  [0x11C10] ldr w9, [x16]
  [0x11C14] mov x8, x3
  [0x11C18] mov x1, x14
  [0x11C1C] sub x1, x1, x15 ;; misaligned with debug data
  [0x11C20] cmp x8, x1
  [0x11C24] b.eq #0x11c40
  [0x11C28] add x16, x8, x15
  [0x11C2C] ldr w8, [x16] ;; misaligned with debug data
  [0x11C30] add x16, x8, x15
  [0x11C34] ldr w7, [x16, #0x18] ;; misaligned with debug data
  [0x11C38] mov x7, x7
  [0x11C3C] b #0x11c48
  [0x11C40] mov x7, x14
  [0x11C44] sub x7, x7, x15 ;; misaligned with debug data
  [0x11C48] mov x7, x7
  [0x11C4C] mov x9, x9
  [0x11C50] mov x7, x7
  [0x11C54] mov x6, x6
  [0x11C58] add x9, x9, x15
  [0x11C5C] stp x3, x5, [sp, #-0x10]!
  [0x11C60] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11C64] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11C68] blr x9 ;; misaligned with debug data
  [0x11C6C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11C70] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11C74] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11C78] mov x0, x0
  [0x11C7C] mov x6, sp
  [0x11C80] sub x6, x6, x15
  [0x11C84] mov x6, x6
  [0x11C88] add x16, x6, x15
  [0x11C8C] str w13, [x16, #4] ;; misaligned with debug data
  [0x11C90] movz x9, #0x1
  [0x11C94] add x16, x6, x15
  [0x11C98] str w9, [x16, #8] ;; misaligned with debug data
  [0x11C9C] adrp x9, #0x11000
  [0x11CA0] add x9, x9, #0
  [0x11CA4] add x16, x6, x15
  [0x11CA8] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x11CAC] adrp x9, #0x11000
  [0x11CB0] add x9, x9, #0
  [0x11CB4] mov x9, x9
  [0x11CB8] add x16, x6, x15
  [0x11CBC] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x11CC0] adrp x16, #0x11000
  [0x11CC4] add x16, x16, #0
  [0x11CC8] ldr w9, [x16]
  [0x11CCC] mov x8, x3
  [0x11CD0] mov x1, x14
  [0x11CD4] sub x1, x1, x15 ;; misaligned with debug data
  [0x11CD8] cmp x8, x1
  [0x11CDC] b.eq #0x11cf8
  [0x11CE0] add x16, x8, x15
  [0x11CE4] ldr w8, [x16] ;; misaligned with debug data
  [0x11CE8] add x16, x8, x15
  [0x11CEC] ldr w7, [x16, #0x18] ;; misaligned with debug data
  [0x11CF0] mov x7, x7
  [0x11CF4] b #0x11d00
  [0x11CF8] mov x7, x14
  [0x11CFC] sub x7, x7, x15 ;; misaligned with debug data
  [0x11D00] mov x7, x7
  [0x11D04] mov x9, x9
  [0x11D08] mov x7, x7
  [0x11D0C] mov x6, x6
  [0x11D10] add x9, x9, x15
  [0x11D14] stp x3, x5, [sp, #-0x10]!
  [0x11D18] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11D1C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11D20] blr x9 ;; misaligned with debug data
  [0x11D24] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11D28] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11D2C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11D30] mov x0, x0
  [0x11D34] mov x6, sp
  [0x11D38] sub x6, x6, x15
  [0x11D3C] mov x6, x6
  [0x11D40] add x16, x6, x15
  [0x11D44] str w13, [x16, #4] ;; misaligned with debug data
  [0x11D48] movz x9, #0x1
  [0x11D4C] add x16, x6, x15
  [0x11D50] str w9, [x16, #8] ;; misaligned with debug data
  [0x11D54] adrp x9, #0x11000
  [0x11D58] add x9, x9, #0
  [0x11D5C] add x16, x6, x15
  [0x11D60] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x11D64] adrp x9, #0xf000
  [0x11D68] add x9, x9, #0xd84
  [0x11D6C] sub x9, x9, x15
  [0x11D70] mov x9, x9
  [0x11D74] add x16, x6, x15
  [0x11D78] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x11D7C] adrp x16, #0x11000
  [0x11D80] add x16, x16, #0
  [0x11D84] ldr w9, [x16]
  [0x11D88] mov x8, x3
  [0x11D8C] mov x1, x14
  [0x11D90] sub x1, x1, x15 ;; misaligned with debug data
  [0x11D94] cmp x8, x1
  [0x11D98] b.eq #0x11db4
  [0x11D9C] add x16, x8, x15
  [0x11DA0] ldr w8, [x16] ;; misaligned with debug data
  [0x11DA4] add x16, x8, x15
  [0x11DA8] ldr w7, [x16, #0x18] ;; misaligned with debug data
  [0x11DAC] mov x7, x7
  [0x11DB0] b #0x11dbc
  [0x11DB4] mov x7, x14
  [0x11DB8] sub x7, x7, x15 ;; misaligned with debug data
  [0x11DBC] mov x7, x7
  [0x11DC0] mov x9, x9
  [0x11DC4] mov x7, x7
  [0x11DC8] mov x6, x6
  [0x11DCC] add x9, x9, x15
  [0x11DD0] stp x3, x5, [sp, #-0x10]!
  [0x11DD4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11DD8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11DDC] blr x9 ;; misaligned with debug data
  [0x11DE0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11DE4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11DE8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11DEC] mov x0, x0
  [0x11DF0] mov x6, sp
  [0x11DF4] sub x6, x6, x15
  [0x11DF8] mov x6, x6
  [0x11DFC] add x16, x6, x15
  [0x11E00] str w13, [x16, #4] ;; misaligned with debug data
  [0x11E04] movz x9, #0x1
  [0x11E08] add x16, x6, x15
  [0x11E0C] str w9, [x16, #8] ;; misaligned with debug data
  [0x11E10] adrp x9, #0x11000
  [0x11E14] add x9, x9, #0
  [0x11E18] add x16, x6, x15
  [0x11E1C] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x11E20] adrp x9, #0xf000
  [0x11E24] add x9, x9, #0xe44
  [0x11E28] sub x9, x9, x15
  [0x11E2C] mov x9, x9
  [0x11E30] add x16, x6, x15
  [0x11E34] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x11E38] adrp x16, #0x11000
  [0x11E3C] add x16, x16, #0
  [0x11E40] ldr w9, [x16]
  [0x11E44] mov x3, x3
  [0x11E48] mov x8, x14
  [0x11E4C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11E50] cmp x3, x8
  [0x11E54] b.eq #0x11e70
  [0x11E58] add x16, x3, x15
  [0x11E5C] ldr w8, [x16] ;; misaligned with debug data
  [0x11E60] add x16, x8, x15
  [0x11E64] ldr w7, [x16, #0x18] ;; misaligned with debug data
  [0x11E68] mov x7, x7
  [0x11E6C] b #0x11e78
  [0x11E70] mov x7, x14
  [0x11E74] sub x7, x7, x15 ;; misaligned with debug data
  [0x11E78] mov x7, x7
  [0x11E7C] mov x9, x9
  [0x11E80] mov x7, x7
  [0x11E84] mov x6, x6
  [0x11E88] add x9, x9, x15
  [0x11E8C] stp x3, x5, [sp, #-0x10]!
  [0x11E90] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11E94] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11E98] blr x9 ;; misaligned with debug data
  [0x11E9C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11EA0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11EA4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11EA8] mov x0, x0
  [0x11EAC] adrp x16, #0x11000
  [0x11EB0] add x16, x16, #0
  [0x11EB4] ldr w7, [x16]
  [0x11EB8] adrp x16, #0x11000
  [0x11EBC] add x16, x16, #0
  [0x11EC0] ldr w6, [x16]
  [0x11EC4] movz x2, #0x4000
  [0x11EC8] add x16, x7, x15
  [0x11ECC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11ED0] add x16, x9, x15
  [0x11ED4] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x11ED8] mov x9, x9
  [0x11EDC] mov x7, x7
  [0x11EE0] mov x6, x6
  [0x11EE4] mov x2, x2
  [0x11EE8] add x9, x9, x15
  [0x11EEC] stp x3, x5, [sp, #-0x10]!
  [0x11EF0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11EF4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11EF8] blr x9 ;; misaligned with debug data
  [0x11EFC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11F00] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11F04] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11F08] mov x0, x0
  [0x11F0C] mov x3, x0
  [0x11F10] mov x3, x3
  [0x11F14] mov x9, x14
  [0x11F18] sub x9, x9, x15 ;; misaligned with debug data
  [0x11F1C] cmp x3, x9
  [0x11F20] b.eq #0x11ff0
  [0x11F24] adrp x16, #0x11000
  [0x11F28] add x16, x16, #0
  [0x11F2C] ldr w9, [x16]
  [0x11F30] add x16, x9, x15
  [0x11F34] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x11F38] adrp x2, #0x11000
  [0x11F3C] add x2, x2, #0
  [0x11F40] movz x1, #0x4000
  [0x11F44] movk x1, #0x7000, lsl #16
  [0x11F48] mov x1, x1
  [0x11F4C] mov x9, x9
  [0x11F50] mov x7, x3
  [0x11F54] mov x6, x5
  [0x11F58] mov x2, x2
  [0x11F5C] mov x1, x1
  [0x11F60] add x9, x9, x15
  [0x11F64] stp x3, x5, [sp, #-0x10]!
  [0x11F68] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11F6C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11F70] blr x9 ;; misaligned with debug data
  [0x11F74] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11F78] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11F7C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11F80] mov x0, x0
  [0x11F84] adrp x16, #0x11000
  [0x11F88] add x16, x16, #0
  [0x11F8C] ldr w9, [x16]
  [0x11F90] mov x9, x9
  [0x11F94] add x16, x3, x15
  [0x11F98] ldr w7, [x16, #0x28] ;; misaligned with debug data
  [0x11F9C] adrp x6, #0xe000
  [0x11FA0] add x6, x6, #0xe84
  [0x11FA4] sub x6, x6, x15
  [0x11FA8] mov x9, x9
  [0x11FAC] mov x7, x7
  [0x11FB0] mov x6, x6
  [0x11FB4] mov x2, x5
  [0x11FB8] add x9, x9, x15
  [0x11FBC] stp x3, x5, [sp, #-0x10]!
  [0x11FC0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11FC4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11FC8] blr x9 ;; misaligned with debug data
  [0x11FCC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11FD0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11FD4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11FD8] mov x0, x0
  [0x11FDC] add x16, x3, x15
  [0x11FE0] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x11FE4] mov x9, x9
  [0x11FE8] mov x9, x9
  [0x11FEC] b #0x11ff8
  [0x11FF0] mov x9, x14
  [0x11FF4] sub x9, x9, x15 ;; misaligned with debug data
  [0x11FF8] mov x9, x9
  [0x11FFC] b #0x12008
  [0x12000] mov x9, x14
  [0x12004] sub x9, x9, x15 ;; misaligned with debug data
  [0x12008] mov x9, x9
  [0x1200C] b #0x12018
  [0x12010] mov x9, x14
  [0x12014] sub x9, x9, x15 ;; misaligned with debug data
  [0x12018] add x16, x11, x15
  [0x1201C] ldr s23, [x16, #0x28] ;; misaligned with debug data
  [0x12020] fmov w0, s23
  [0x12024] sxtw x0, w0
  [0x12028] b #0x1207c
  [0x1202C] adrp x16, #0x12000
  [0x12030] add x16, x16, #0
  [0x12034] ldr w9, [x16]
  [0x12038] add x16, x9, x15
  [0x1203C] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x12040] mov x9, x9
  [0x12044] mov x7, x11
  [0x12048] mov x6, x3
  [0x1204C] mov x2, x5
  [0x12050] mov x1, x12
  [0x12054] add x9, x9, x15
  [0x12058] stp x3, x5, [sp, #-0x10]!
  [0x1205C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x12060] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x12064] blr x9 ;; misaligned with debug data
  [0x12068] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1206C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x12070] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x12074] mov x0, x0
  [0x12078] mov x0, x0
  [0x1207C] mov x0, x0
  [0x12080] add sp, sp, #0x50
  [0x12084] ldr q25, [sp], #0x10
  [0x12088] ldr q24, [sp], #0x10
  [0x1208C] ldp x29, x30, [sp], #0x10
  [0x12090] ret


[anon-function-3]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x50
  [0x1000C] mov x5, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] add x16, x9, x15
  [0x10020] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10024] ldr x3, [x16] ;; misaligned with debug data
  [0x10028] mov x12, x3
  [0x1002C] mov x6, sp
  [0x10030] sub x6, x6, x15
  [0x10034] mov x6, x6
  [0x10038] add x16, x6, x15
  [0x1003C] str w13, [x16, #4] ;; misaligned with debug data
  [0x10040] movz x9, #0x1
  [0x10044] add x16, x6, x15
  [0x10048] str w9, [x16, #8] ;; misaligned with debug data
  [0x1004C] adrp x9, #0x10000
  [0x10050] add x9, x9, #0
  [0x10054] add x16, x6, x15
  [0x10058] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x1005C] adrp x9, #0x10000
  [0x10060] add x9, x9, #0
  [0x10064] mov x9, x9
  [0x10068] add x16, x6, x15
  [0x1006C] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x10070] adrp x16, #0x10000
  [0x10074] add x16, x16, #0
  [0x10078] ldr w9, [x16]
  [0x1007C] mov x9, x9
  [0x10080] mov x7, x5
  [0x10084] mov x6, x6
  [0x10088] add x9, x9, x15
  [0x1008C] stp x3, x5, [sp, #-0x10]!
  [0x10090] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10094] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10098] blr x9 ;; misaligned with debug data
  [0x1009C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100A0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100A4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100A8] mov x0, x0
  [0x100AC] mov x9, sp
  [0x100B0] sub x9, x9, x15
  [0x100B4] mov x9, x9
  [0x100B8] mov x8, x13
  [0x100BC] add x16, x8, x15
  [0x100C0] ldr w8, [x16, #0x2c] ;; misaligned with debug data
  [0x100C4] add x16, x8, x15
  [0x100C8] ldr w1, [x16, #0x1c] ;; misaligned with debug data
  [0x100CC] mov x1, x1
  [0x100D0] mov x1, x1
  [0x100D4] mov x1, x1
  [0x100D8] mov x9, x9
  [0x100DC] sub x1, x1, x9
  [0x100E0] mov x1, x1
  [0x100E4] mov x9, x13
  [0x100E8] add x16, x9, x15
  [0x100EC] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x100F0] add x16, x9, x15
  [0x100F4] ldrsw x8, [x16, #0x20] ;; misaligned with debug data
  [0x100F8] mov x8, x8
  [0x100FC] cmp x1, x8
  [0x10100] b.le #0x10164
  [0x10104] adrp x16, #0x10000
  [0x10108] add x16, x16, #0
  [0x1010C] ldr w9, [x16]
  [0x10110] movz x7, #0
  [0x10114] adrp x6, #0x14000
  [0x10118] add x6, x6, #0x54
  [0x1011C] sub x6, x6, x15
  [0x10120] mov x9, x9
  [0x10124] mov x7, x7
  [0x10128] mov x6, x6
  [0x1012C] mov x2, x13
  [0x10130] mov x1, x1
  [0x10134] mov x8, x8
  [0x10138] add x9, x9, x15
  [0x1013C] stp x3, x5, [sp, #-0x10]!
  [0x10140] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10144] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10148] blr x9 ;; misaligned with debug data
  [0x1014C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10150] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10154] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10158] mov x0, x0
  [0x1015C] mov x0, x0
  [0x10160] b #0x1016c
  [0x10164] mov x0, x14
  [0x10168] sub x0, x0, x15 ;; misaligned with debug data
  [0x1016C] mov x9, x13
  [0x10170] add x16, x9, x15
  [0x10174] ldr w3, [x16, #0x2c] ;; misaligned with debug data
  [0x10178] mov x13, x3
  [0x1017C] mov x9, x13
  [0x10180] add x16, x9, x15
  [0x10184] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10188] movz x7, #0
  [0x1018C] mov x7, x7
  [0x10190] mov x9, x9
  [0x10194] mov x7, x7
  [0x10198] add x9, x9, x15
  [0x1019C] stp x3, x5, [sp, #-0x10]!
  [0x101A0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A8] blr x9 ;; misaligned with debug data
  [0x101AC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101B0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101B4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101B8] mov x3, x3
  [0x101BC] adrp x16, #0x10000
  [0x101C0] add x16, x16, #0
  [0x101C4] ldr w9, [x16]
  [0x101C8] add x16, x9, x15
  [0x101CC] add x16, x16, #0x30c ;; misaligned with debug data
  [0x101D0] ldr x9, [x16] ;; misaligned with debug data
  [0x101D4] mov x9, x9
  [0x101D8] sub x9, x9, x12
  [0x101DC] movz x8, #0xb4
  [0x101E0] cmp x9, x8
  [0x101E4] b.lt #0x1002c
  [0x101E8] add sp, sp, #0x50
  [0x101EC] ldp x29, x30, [sp], #0x10
  [0x101F0] ret


[anon-function-2]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] movz x9, #0x800e
  [0x1000C] add x16, x13, x15
  [0x10010] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10014] mov x8, x8
  [0x10018] add x16, x8, x15
  [0x1001C] ldr w8, [x16, #0x9c] ;; misaligned with debug data
  [0x10020] add x16, x8, x15
  [0x10024] stur x9, [x16, #0x3c] ;; misaligned with debug data
  [0x10028] ldp x29, x30, [sp], #0x10
  [0x1002C] ret


[(method get-death-count game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x6, x6
  [0x10014] mov x9, x14
  [0x10018] sub x9, x9, x15 ;; misaligned with debug data
  [0x1001C] cmp x6, x9
  [0x10020] b.eq #0x1009c
  [0x10024] adrp x16, #0x10000
  [0x10028] add x16, x16, #0
  [0x1002C] ldr w6, [x16]
  [0x10030] mov x6, x6
  [0x10034] mov x9, x14
  [0x10038] sub x9, x9, x15 ;; misaligned with debug data
  [0x1003C] cmp x6, x9
  [0x10040] b.eq #0x1009c
  [0x10044] adrp x16, #0x10000
  [0x10048] add x16, x16, #0
  [0x1004C] ldr w9, [x16]
  [0x10050] add x16, x9, x15
  [0x10054] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10058] adrp x16, #0x10000
  [0x1005C] add x16, x16, #0
  [0x10060] ldr w8, [x16]
  [0x10064] add x16, x8, x15
  [0x10068] ldr w8, [x16, #0x1d8] ;; misaligned with debug data
  [0x1006C] add x16, x8, x15
  [0x10070] ldr w8, [x16, #0x34] ;; misaligned with debug data
  [0x10074] add x16, x8, x15
  [0x10078] ldrsw x8, [x16, #0xc] ;; misaligned with debug data
  [0x1007C] mov x6, x14
  [0x10080] sub x6, x6, x15 ;; misaligned with debug data
  [0x10084] cmp x9, x8
  [0x10088] b.lt #0x10098
  [0x1008C] add x6, x14, #8
  [0x10090] sub x6, x6, x15 ;; misaligned with debug data
  [0x10094] mov x6, x6
  [0x10098] mov x6, x6
  [0x1009C] mov x9, x14
  [0x100A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x100A4] cmp x6, x9
  [0x100A8] b.eq #0x1013c
  [0x100AC] adrp x16, #0x10000
  [0x100B0] add x16, x16, #0
  [0x100B4] ldr w9, [x16]
  [0x100B8] add x16, x9, x15
  [0x100BC] ldr w9, [x16, #0x1d8] ;; misaligned with debug data
  [0x100C0] add x16, x9, x15
  [0x100C4] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x100C8] add x16, x9, x15
  [0x100CC] ldrsw x9, [x16, #0xc] ;; misaligned with debug data
  [0x100D0] mov x9, x9
  [0x100D4] movz x8, #0xffff
  [0x100D8] movk x8, #0xffff, lsl #16
  [0x100DC] movk x8, #0xffff, lsl #32
  [0x100E0] movk x8, #0xffff, lsl #48
  [0x100E4] add x9, x9, x8
  [0x100E8] movz x8, #0xc
  [0x100EC] mov x9, x9
  [0x100F0] lsl x9, x9, #2
  [0x100F4] add x9, x9, x8
  [0x100F8] mov x9, x9
  [0x100FC] adrp x16, #0x10000
  [0x10100] add x16, x16, #0
  [0x10104] ldr w8, [x16]
  [0x10108] add x9, x9, x8
  [0x1010C] add x16, x9, x15
  [0x10110] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10114] mov x9, x9
  [0x10118] mov x9, x9
  [0x1011C] movz x8, #0x38
  [0x10120] add x8, x8, x7
  [0x10124] add x9, x9, x8
  [0x10128] add x16, x9, x15
  [0x1012C] ldrb w0, [x16] ;; misaligned with debug data
  [0x10130] mov x0, x0
  [0x10134] mov x0, x0
  [0x10138] b #0x10148
  [0x1013C] add x16, x7, x15
  [0x10140] ldrsw x0, [x16, #0xa0] ;; misaligned with debug data
  [0x10144] mov x0, x0
  [0x10148] mov x0, x0
  [0x1014C] movz x9, #0
  [0x10150] movz x9, #0x4
  [0x10154] mov x0, x0
  [0x10158] movz x8, #0x5
  [0x1015C] cbnz x8, #0x10164
  [0x10160] .word 0x0000beef
  [0x10164] mov x16, x8
  [0x10168] sub sp, sp, #0x10
  [0x1016C] str x8, [sp]
  [0x10170] mov x8, x0
  [0x10174] sdiv x8, x8, x16
  [0x10178] mov x0, x8
  [0x1017C] ldr x8, [sp]
  [0x10180] add sp, sp, #0x10
  [0x10184] mov x0, x0
  [0x10188] mov x9, x9
  [0x1018C] mov x0, x0
  [0x10190] cmp x9, x0
  [0x10194] b.le #0x101a0
  [0x10198] mov x0, x0
  [0x1019C] b #0x101a4
  [0x101A0] mov x0, x9
  [0x101A4] mov x0, x0
  [0x101A8] ldp x29, x30, [sp], #0x10
  [0x101AC] ret


[anon-function-1]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x50
  [0x1000C] mov x6, sp
  [0x10010] sub x6, x6, x15
  [0x10014] mov x6, x6
  [0x10018] add x16, x6, x15
  [0x1001C] str w13, [x16, #4] ;; misaligned with debug data
  [0x10020] movz x9, #0x2
  [0x10024] add x16, x6, x15
  [0x10028] str w9, [x16, #8] ;; misaligned with debug data
  [0x1002C] adrp x9, #0x10000
  [0x10030] add x9, x9, #0
  [0x10034] add x16, x6, x15
  [0x10038] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x1003C] adrp x9, #0x10000
  [0x10040] add x9, x9, #0
  [0x10044] mov x9, x9
  [0x10048] add x16, x6, x15
  [0x1004C] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x10050] movz x9, #0x3
  [0x10054] mov x9, x9
  [0x10058] add x16, x6, x15
  [0x1005C] str x9, [x16, #0x18] ;; misaligned with debug data
  [0x10060] adrp x16, #0x10000
  [0x10064] add x16, x16, #0
  [0x10068] ldr w9, [x16]
  [0x1006C] adrp x16, #0x10000
  [0x10070] add x16, x16, #0
  [0x10074] ldr w7, [x16]
  [0x10078] mov x9, x9
  [0x1007C] mov x7, x7
  [0x10080] mov x6, x6
  [0x10084] add x9, x9, x15
  [0x10088] stp x3, x5, [sp, #-0x10]!
  [0x1008C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10090] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10094] blr x9 ;; misaligned with debug data
  [0x10098] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1009C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100A4] mov x0, x0
  [0x100A8] mov x0, x0
  [0x100AC] add sp, sp, #0x50
  [0x100B0] ldp x29, x30, [sp], #0x10
  [0x100B4] ret


[(method reset! fact-info-target)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x9, x14
  [0x10014] sub x9, x9, x15 ;; misaligned with debug data
  [0x10018] mov x8, x14
  [0x1001C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10020] cmp x6, x9
  [0x10024] b.ne #0x10034
  [0x10028] add x8, x14, #8
  [0x1002C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10030] mov x8, x8
  [0x10034] mov x9, x8
  [0x10038] mov x8, x14
  [0x1003C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10040] cmp x9, x8
  [0x10044] b.ne #0x10070
  [0x10048] adrp x9, #0x10000
  [0x1004C] add x9, x9, #0
  [0x10050] mov x8, x14
  [0x10054] sub x8, x8, x15 ;; misaligned with debug data
  [0x10058] cmp x6, x9
  [0x1005C] b.ne #0x1006c
  [0x10060] add x8, x14, #8
  [0x10064] sub x8, x8, x15 ;; misaligned with debug data
  [0x10068] mov x8, x8
  [0x1006C] mov x9, x8
  [0x10070] mov x8, x14
  [0x10074] sub x8, x8, x15 ;; misaligned with debug data
  [0x10078] cmp x9, x8
  [0x1007C] b.eq #0x100c4
  [0x10080] movz x9, #0
  [0x10084] add x16, x7, x15
  [0x10088] stur x9, [x16, #0x34] ;; misaligned with debug data
  [0x1008C] adrp x16, #0x13000
  [0x10090] ldr s23, [x16, #0xf98]
  [0x10094] add x16, x7, x15
  [0x10098] str s23, [x16, #0x28] ;; misaligned with debug data
  [0x1009C] adrp x16, #0x10000
  [0x100A0] add x16, x16, #0
  [0x100A4] ldr w9, [x16]
  [0x100A8] add x16, x9, x15
  [0x100AC] add x16, x16, #0x314 ;; misaligned with debug data
  [0x100B0] ldr x9, [x16] ;; misaligned with debug data
  [0x100B4] add x16, x7, x15
  [0x100B8] stur x9, [x16, #0x2c] ;; misaligned with debug data
  [0x100BC] mov x9, x9
  [0x100C0] b #0x100cc
  [0x100C4] mov x9, x14
  [0x100C8] sub x9, x9, x15 ;; misaligned with debug data
  [0x100CC] mov x9, x14
  [0x100D0] sub x9, x9, x15 ;; misaligned with debug data
  [0x100D4] mov x8, x14
  [0x100D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100DC] cmp x6, x9
  [0x100E0] b.ne #0x100f0
  [0x100E4] add x8, x14, #8
  [0x100E8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100EC] mov x8, x8
  [0x100F0] mov x9, x8
  [0x100F4] mov x8, x14
  [0x100F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100FC] cmp x9, x8
  [0x10100] b.ne #0x1012c
  [0x10104] adrp x9, #0x10000
  [0x10108] add x9, x9, #0
  [0x1010C] mov x8, x14
  [0x10110] sub x8, x8, x15 ;; misaligned with debug data
  [0x10114] cmp x6, x9
  [0x10118] b.ne #0x10128
  [0x1011C] add x8, x14, #8
  [0x10120] sub x8, x8, x15 ;; misaligned with debug data
  [0x10124] mov x8, x8
  [0x10128] mov x9, x8
  [0x1012C] mov x8, x14
  [0x10130] sub x8, x8, x15 ;; misaligned with debug data
  [0x10134] cmp x9, x8
  [0x10138] b.eq #0x10188
  [0x1013C] adrp x16, #0x10000
  [0x10140] add x16, x16, #0
  [0x10144] ldr w9, [x16]
  [0x10148] add x16, x9, x15
  [0x1014C] ldr s23, [x16, #0x24] ;; misaligned with debug data
  [0x10150] add x16, x7, x15
  [0x10154] str s23, [x16, #0x40] ;; misaligned with debug data
  [0x10158] add x16, x7, x15
  [0x1015C] ldr s23, [x16, #0x40] ;; misaligned with debug data
  [0x10160] add x16, x7, x15
  [0x10164] str s23, [x16, #0x3c] ;; misaligned with debug data
  [0x10168] movz x9, #0x8ad0
  [0x1016C] movk x9, #0xffff, lsl #16
  [0x10170] movk x9, #0xffff, lsl #32
  [0x10174] movk x9, #0xffff, lsl #48
  [0x10178] add x16, x7, x15
  [0x1017C] stur x9, [x16, #0x54] ;; misaligned with debug data
  [0x10180] mov x9, x9
  [0x10184] b #0x10190
  [0x10188] mov x9, x14
  [0x1018C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10190] mov x9, x14
  [0x10194] sub x9, x9, x15 ;; misaligned with debug data
  [0x10198] mov x8, x14
  [0x1019C] sub x8, x8, x15 ;; misaligned with debug data
  [0x101A0] cmp x6, x9
  [0x101A4] b.ne #0x101b4
  [0x101A8] add x8, x14, #8
  [0x101AC] sub x8, x8, x15 ;; misaligned with debug data
  [0x101B0] mov x8, x8
  [0x101B4] mov x9, x8
  [0x101B8] mov x8, x14
  [0x101BC] sub x8, x8, x15 ;; misaligned with debug data
  [0x101C0] cmp x9, x8
  [0x101C4] b.ne #0x101f0
  [0x101C8] adrp x9, #0x10000
  [0x101CC] add x9, x9, #0
  [0x101D0] mov x8, x14
  [0x101D4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101D8] cmp x6, x9
  [0x101DC] b.ne #0x101ec
  [0x101E0] add x8, x14, #8
  [0x101E4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101E8] mov x8, x8
  [0x101EC] mov x9, x8
  [0x101F0] mov x8, x14
  [0x101F4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101F8] cmp x9, x8
  [0x101FC] b.eq #0x10238
  [0x10200] adrp x16, #0x10000
  [0x10204] add x16, x16, #0
  [0x10208] ldr w9, [x16]
  [0x1020C] add x16, x9, x15
  [0x10210] ldr s23, [x16, #0x34] ;; misaligned with debug data
  [0x10214] add x16, x7, x15
  [0x10218] str s23, [x16, #0x48] ;; misaligned with debug data
  [0x1021C] adrp x16, #0x13000
  [0x10220] ldr s23, [x16, #0xf9c]
  [0x10224] add x16, x7, x15
  [0x10228] str s23, [x16, #0x44] ;; misaligned with debug data
  [0x1022C] fmov w9, s23
  [0x10230] sxtw x9, w9
  [0x10234] b #0x10240
  [0x10238] mov x9, x14
  [0x1023C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10240] mov x9, x14
  [0x10244] sub x9, x9, x15 ;; misaligned with debug data
  [0x10248] mov x8, x14
  [0x1024C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10250] cmp x6, x9
  [0x10254] b.ne #0x10264
  [0x10258] add x8, x14, #8
  [0x1025C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10260] mov x8, x8
  [0x10264] mov x9, x8
  [0x10268] mov x8, x14
  [0x1026C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10270] cmp x9, x8
  [0x10274] b.ne #0x102a0
  [0x10278] adrp x9, #0x10000
  [0x1027C] add x9, x9, #0
  [0x10280] mov x8, x14
  [0x10284] sub x8, x8, x15 ;; misaligned with debug data
  [0x10288] cmp x6, x9
  [0x1028C] b.ne #0x1029c
  [0x10290] add x8, x14, #8
  [0x10294] sub x8, x8, x15 ;; misaligned with debug data
  [0x10298] mov x8, x8
  [0x1029C] mov x9, x8
  [0x102A0] mov x8, x14
  [0x102A4] sub x8, x8, x15 ;; misaligned with debug data
  [0x102A8] cmp x9, x8
  [0x102AC] b.eq #0x102e8
  [0x102B0] adrp x16, #0x10000
  [0x102B4] add x16, x16, #0
  [0x102B8] ldr w9, [x16]
  [0x102BC] add x16, x9, x15
  [0x102C0] ldr s23, [x16, #0x2c] ;; misaligned with debug data
  [0x102C4] add x16, x7, x15
  [0x102C8] str s23, [x16, #0x50] ;; misaligned with debug data
  [0x102CC] adrp x16, #0x13000
  [0x102D0] ldr s23, [x16, #0xfa0]
  [0x102D4] add x16, x7, x15
  [0x102D8] str s23, [x16, #0x4c] ;; misaligned with debug data
  [0x102DC] fmov w9, s23
  [0x102E0] sxtw x9, w9
  [0x102E4] b #0x102f0
  [0x102E8] mov x9, x14
  [0x102EC] sub x9, x9, x15 ;; misaligned with debug data
  [0x102F0] ldp x29, x30, [sp], #0x10
  [0x102F4] ret


[top-level]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] adrp x16, #0x10000
  [0x10010] add x16, x16, #0
  [0x10014] ldr w7, [x16]
  [0x10018] movz x6, #0x9
  [0x1001C] adrp x2, #0x10000
  [0x10020] add x2, x2, #0
  [0x10024] sub x2, x2, x15
  [0x10028] adrp x16, #0x10000
  [0x1002C] add x16, x16, #0
  [0x10030] ldr w9, [x16]
  [0x10034] mov x9, x9
  [0x10038] mov x7, x7
  [0x1003C] mov x6, x6
  [0x10040] mov x2, x2
  [0x10044] add x9, x9, x15
  [0x10048] stp x3, x5, [sp, #-0x10]!
  [0x1004C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10050] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10054] blr x9 ;; misaligned with debug data
  [0x10058] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1005C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10060] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10064] mov x3, x3
  [0x10068] adrp x16, #0x10000
  [0x1006C] add x16, x16, #0
  [0x10070] ldr w7, [x16]
  [0x10074] movz x6, #0xa
  [0x10078] adrp x2, #0x10000
  [0x1007C] add x2, x2, #0
  [0x10080] sub x2, x2, x15
  [0x10084] adrp x16, #0x10000
  [0x10088] add x16, x16, #0
  [0x1008C] ldr w9, [x16]
  [0x10090] mov x9, x9
  [0x10094] mov x7, x7
  [0x10098] mov x6, x6
  [0x1009C] mov x2, x2
  [0x100A0] add x9, x9, x15
  [0x100A4] stp x3, x5, [sp, #-0x10]!
  [0x100A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100B0] blr x9 ;; misaligned with debug data
  [0x100B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100C0] mov x3, x3
  [0x100C4] adrp x16, #0x10000
  [0x100C8] add x16, x16, #0
  [0x100CC] ldr w7, [x16]
  [0x100D0] movz x6, #0xb
  [0x100D4] adrp x2, #0x10000
  [0x100D8] add x2, x2, #0
  [0x100DC] sub x2, x2, x15
  [0x100E0] adrp x16, #0x10000
  [0x100E4] add x16, x16, #0
  [0x100E8] ldr w9, [x16]
  [0x100EC] mov x9, x9
  [0x100F0] mov x7, x7
  [0x100F4] mov x6, x6
  [0x100F8] mov x2, x2
  [0x100FC] add x9, x9, x15
  [0x10100] stp x3, x5, [sp, #-0x10]!
  [0x10104] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10108] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1010C] blr x9 ;; misaligned with debug data
  [0x10110] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10114] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10118] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1011C] mov x3, x3
  [0x10120] adrp x9, #0x10000
  [0x10124] add x9, x9, #0
  [0x10128] sub x9, x9, x15
  [0x1012C] adrp x16, #0x10000
  [0x10130] add x16, x16, #0
  [0x10134] str w9, [x16]
  [0x10138] adrp x16, #0x10000
  [0x1013C] add x16, x16, #0
  [0x10140] ldr w7, [x16]
  [0x10144] movz x6, #0x11
  [0x10148] adrp x2, #0x10000
  [0x1014C] add x2, x2, #0
  [0x10150] sub x2, x2, x15
  [0x10154] adrp x16, #0x10000
  [0x10158] add x16, x16, #0
  [0x1015C] ldr w9, [x16]
  [0x10160] mov x9, x9
  [0x10164] mov x7, x7
  [0x10168] mov x6, x6
  [0x1016C] mov x2, x2
  [0x10170] add x9, x9, x15
  [0x10174] stp x3, x5, [sp, #-0x10]!
  [0x10178] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1017C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10180] blr x9 ;; misaligned with debug data
  [0x10184] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10188] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1018C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10190] mov x3, x3
  [0x10194] adrp x16, #0x10000
  [0x10198] add x16, x16, #0
  [0x1019C] ldr w7, [x16]
  [0x101A0] movz x6, #0x12
  [0x101A4] adrp x2, #0x10000
  [0x101A8] add x2, x2, #0
  [0x101AC] sub x2, x2, x15
  [0x101B0] adrp x16, #0x10000
  [0x101B4] add x16, x16, #0
  [0x101B8] ldr w9, [x16]
  [0x101BC] mov x9, x9
  [0x101C0] mov x7, x7
  [0x101C4] mov x6, x6
  [0x101C8] mov x2, x2
  [0x101CC] add x9, x9, x15
  [0x101D0] stp x3, x5, [sp, #-0x10]!
  [0x101D4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101D8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101DC] blr x9 ;; misaligned with debug data
  [0x101E0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101E4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101E8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101EC] mov x3, x3
  [0x101F0] adrp x16, #0x10000
  [0x101F4] add x16, x16, #0
  [0x101F8] ldr w7, [x16]
  [0x101FC] movz x6, #0x13
  [0x10200] adrp x2, #0x10000
  [0x10204] add x2, x2, #0
  [0x10208] sub x2, x2, x15
  [0x1020C] adrp x16, #0x10000
  [0x10210] add x16, x16, #0
  [0x10214] ldr w9, [x16]
  [0x10218] mov x9, x9
  [0x1021C] mov x7, x7
  [0x10220] mov x6, x6
  [0x10224] mov x2, x2
  [0x10228] add x9, x9, x15
  [0x1022C] stp x3, x5, [sp, #-0x10]!
  [0x10230] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10234] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10238] blr x9 ;; misaligned with debug data
  [0x1023C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10240] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10244] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10248] mov x3, x3
  [0x1024C] adrp x16, #0x10000
  [0x10250] add x16, x16, #0
  [0x10254] ldr w7, [x16]
  [0x10258] movz x6, #0xd
  [0x1025C] adrp x2, #0x10000
  [0x10260] add x2, x2, #0
  [0x10264] sub x2, x2, x15
  [0x10268] adrp x16, #0x10000
  [0x1026C] add x16, x16, #0
  [0x10270] ldr w9, [x16]
  [0x10274] mov x9, x9
  [0x10278] mov x7, x7
  [0x1027C] mov x6, x6
  [0x10280] mov x2, x2
  [0x10284] add x9, x9, x15
  [0x10288] stp x3, x5, [sp, #-0x10]!
  [0x1028C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10290] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10294] blr x9 ;; misaligned with debug data
  [0x10298] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1029C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102A4] mov x3, x3
  [0x102A8] adrp x16, #0x10000
  [0x102AC] add x16, x16, #0
  [0x102B0] ldr w7, [x16]
  [0x102B4] movz x6, #0x9
  [0x102B8] adrp x2, #0x10000
  [0x102BC] add x2, x2, #0
  [0x102C0] sub x2, x2, x15
  [0x102C4] adrp x16, #0x10000
  [0x102C8] add x16, x16, #0
  [0x102CC] ldr w9, [x16]
  [0x102D0] mov x9, x9
  [0x102D4] mov x7, x7
  [0x102D8] mov x6, x6
  [0x102DC] mov x2, x2
  [0x102E0] add x9, x9, x15
  [0x102E4] stp x3, x5, [sp, #-0x10]!
  [0x102E8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102EC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102F0] blr x9 ;; misaligned with debug data
  [0x102F4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102F8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102FC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10300] mov x3, x3
  [0x10304] adrp x16, #0x10000
  [0x10308] add x16, x16, #0
  [0x1030C] ldr w7, [x16]
  [0x10310] movz x6, #0xa
  [0x10314] adrp x2, #0x10000
  [0x10318] add x2, x2, #0
  [0x1031C] sub x2, x2, x15
  [0x10320] adrp x16, #0x10000
  [0x10324] add x16, x16, #0
  [0x10328] ldr w9, [x16]
  [0x1032C] mov x9, x9
  [0x10330] mov x7, x7
  [0x10334] mov x6, x6
  [0x10338] mov x2, x2
  [0x1033C] add x9, x9, x15
  [0x10340] stp x3, x5, [sp, #-0x10]!
  [0x10344] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10348] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1034C] blr x9 ;; misaligned with debug data
  [0x10350] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10354] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10358] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1035C] mov x3, x3
  [0x10360] adrp x16, #0x10000
  [0x10364] add x16, x16, #0
  [0x10368] ldr w7, [x16]
  [0x1036C] movz x6, #0x17
  [0x10370] adrp x2, #0x10000
  [0x10374] add x2, x2, #0
  [0x10378] sub x2, x2, x15
  [0x1037C] adrp x16, #0x10000
  [0x10380] add x16, x16, #0
  [0x10384] ldr w9, [x16]
  [0x10388] mov x9, x9
  [0x1038C] mov x7, x7
  [0x10390] mov x6, x6
  [0x10394] mov x2, x2
  [0x10398] add x9, x9, x15
  [0x1039C] stp x3, x5, [sp, #-0x10]!
  [0x103A0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103A4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103A8] blr x9 ;; misaligned with debug data
  [0x103AC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103B0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103B4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103B8] mov x3, x3
  [0x103BC] adrp x16, #0x10000
  [0x103C0] add x16, x16, #0
  [0x103C4] ldr w7, [x16]
  [0x103C8] movz x6, #0x14
  [0x103CC] adrp x2, #0x10000
  [0x103D0] add x2, x2, #0
  [0x103D4] sub x2, x2, x15
  [0x103D8] adrp x16, #0x10000
  [0x103DC] add x16, x16, #0
  [0x103E0] ldr w9, [x16]
  [0x103E4] mov x9, x9
  [0x103E8] mov x7, x7
  [0x103EC] mov x6, x6
  [0x103F0] mov x2, x2
  [0x103F4] add x9, x9, x15
  [0x103F8] stp x3, x5, [sp, #-0x10]!
  [0x103FC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10400] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10404] blr x9 ;; misaligned with debug data
  [0x10408] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1040C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10410] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10414] mov x3, x3
  [0x10418] adrp x16, #0x10000
  [0x1041C] add x16, x16, #0
  [0x10420] ldr w7, [x16]
  [0x10424] movz x6, #0x15
  [0x10428] adrp x2, #0x10000
  [0x1042C] add x2, x2, #0
  [0x10430] sub x2, x2, x15
  [0x10434] adrp x16, #0x10000
  [0x10438] add x16, x16, #0
  [0x1043C] ldr w9, [x16]
  [0x10440] mov x9, x9
  [0x10444] mov x7, x7
  [0x10448] mov x6, x6
  [0x1044C] mov x2, x2
  [0x10450] add x9, x9, x15
  [0x10454] stp x3, x5, [sp, #-0x10]!
  [0x10458] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1045C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10460] blr x9 ;; misaligned with debug data
  [0x10464] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10468] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1046C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10470] mov x3, x3
  [0x10474] adrp x16, #0x10000
  [0x10478] add x16, x16, #0
  [0x1047C] ldr w7, [x16]
  [0x10480] movz x6, #0x16
  [0x10484] adrp x2, #0x10000
  [0x10488] add x2, x2, #0
  [0x1048C] sub x2, x2, x15
  [0x10490] adrp x16, #0x10000
  [0x10494] add x16, x16, #0
  [0x10498] ldr w9, [x16]
  [0x1049C] mov x9, x9
  [0x104A0] mov x7, x7
  [0x104A4] mov x6, x6
  [0x104A8] mov x2, x2
  [0x104AC] add x9, x9, x15
  [0x104B0] stp x3, x5, [sp, #-0x10]!
  [0x104B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104BC] blr x9 ;; misaligned with debug data
  [0x104C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104CC] mov x3, x3
  [0x104D0] adrp x16, #0x10000
  [0x104D4] add x16, x16, #0
  [0x104D8] ldr w7, [x16]
  [0x104DC] movz x6, #0x1a
  [0x104E0] adrp x2, #0x10000
  [0x104E4] add x2, x2, #0
  [0x104E8] sub x2, x2, x15
  [0x104EC] adrp x16, #0x10000
  [0x104F0] add x16, x16, #0
  [0x104F4] ldr w9, [x16]
  [0x104F8] mov x9, x9
  [0x104FC] mov x7, x7
  [0x10500] mov x6, x6
  [0x10504] mov x2, x2
  [0x10508] add x9, x9, x15
  [0x1050C] stp x3, x5, [sp, #-0x10]!
  [0x10510] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10514] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10518] blr x9 ;; misaligned with debug data
  [0x1051C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10520] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10524] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10528] mov x3, x3
  [0x1052C] adrp x16, #0x10000
  [0x10530] add x16, x16, #0
  [0x10534] ldr w7, [x16]
  [0x10538] movz x6, #0xa
  [0x1053C] adrp x2, #0x10000
  [0x10540] add x2, x2, #0
  [0x10544] sub x2, x2, x15
  [0x10548] adrp x16, #0x10000
  [0x1054C] add x16, x16, #0
  [0x10550] ldr w9, [x16]
  [0x10554] mov x9, x9
  [0x10558] mov x7, x7
  [0x1055C] mov x6, x6
  [0x10560] mov x2, x2
  [0x10564] add x9, x9, x15
  [0x10568] stp x3, x5, [sp, #-0x10]!
  [0x1056C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10570] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10574] blr x9 ;; misaligned with debug data
  [0x10578] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1057C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10580] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10584] mov x3, x3
  [0x10588] adrp x16, #0x10000
  [0x1058C] add x16, x16, #0
  [0x10590] ldr w7, [x16]
  [0x10594] movz x6, #0xb
  [0x10598] adrp x2, #0x10000
  [0x1059C] add x2, x2, #0
  [0x105A0] sub x2, x2, x15
  [0x105A4] adrp x16, #0x10000
  [0x105A8] add x16, x16, #0
  [0x105AC] ldr w9, [x16]
  [0x105B0] mov x9, x9
  [0x105B4] mov x7, x7
  [0x105B8] mov x6, x6
  [0x105BC] mov x2, x2
  [0x105C0] add x9, x9, x15
  [0x105C4] stp x3, x5, [sp, #-0x10]!
  [0x105C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x105CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x105D0] blr x9 ;; misaligned with debug data
  [0x105D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x105D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x105DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x105E0] mov x3, x3
  [0x105E4] adrp x16, #0x10000
  [0x105E8] add x16, x16, #0
  [0x105EC] ldr w7, [x16]
  [0x105F0] movz x6, #0xc
  [0x105F4] adrp x2, #0x10000
  [0x105F8] add x2, x2, #0
  [0x105FC] sub x2, x2, x15
  [0x10600] adrp x16, #0x10000
  [0x10604] add x16, x16, #0
  [0x10608] ldr w9, [x16]
  [0x1060C] mov x9, x9
  [0x10610] mov x7, x7
  [0x10614] mov x6, x6
  [0x10618] mov x2, x2
  [0x1061C] add x9, x9, x15
  [0x10620] stp x3, x5, [sp, #-0x10]!
  [0x10624] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10628] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1062C] blr x9 ;; misaligned with debug data
  [0x10630] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10634] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10638] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1063C] mov x3, x3
  [0x10640] adrp x16, #0x10000
  [0x10644] add x16, x16, #0
  [0x10648] ldr w7, [x16]
  [0x1064C] movz x6, #0xe
  [0x10650] adrp x2, #0x10000
  [0x10654] add x2, x2, #0
  [0x10658] sub x2, x2, x15
  [0x1065C] adrp x16, #0x10000
  [0x10660] add x16, x16, #0
  [0x10664] ldr w9, [x16]
  [0x10668] mov x9, x9
  [0x1066C] mov x7, x7
  [0x10670] mov x6, x6
  [0x10674] mov x2, x2
  [0x10678] add x9, x9, x15
  [0x1067C] stp x3, x5, [sp, #-0x10]!
  [0x10680] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10684] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10688] blr x9 ;; misaligned with debug data
  [0x1068C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10690] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10694] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10698] mov x3, x3
  [0x1069C] adrp x16, #0x10000
  [0x106A0] add x16, x16, #0
  [0x106A4] ldr w7, [x16]
  [0x106A8] movz x6, #0xf
  [0x106AC] adrp x2, #0x10000
  [0x106B0] add x2, x2, #0
  [0x106B4] sub x2, x2, x15
  [0x106B8] adrp x16, #0x10000
  [0x106BC] add x16, x16, #0
  [0x106C0] ldr w9, [x16]
  [0x106C4] mov x9, x9
  [0x106C8] mov x7, x7
  [0x106CC] mov x6, x6
  [0x106D0] mov x2, x2
  [0x106D4] add x9, x9, x15
  [0x106D8] stp x3, x5, [sp, #-0x10]!
  [0x106DC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106E0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106E4] blr x9 ;; misaligned with debug data
  [0x106E8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106EC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106F0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x106F4] mov x3, x3
  [0x106F8] adrp x16, #0x10000
  [0x106FC] add x16, x16, #0
  [0x10700] ldr w7, [x16]
  [0x10704] movz x6, #0x2
  [0x10708] adrp x2, #0x10000
  [0x1070C] add x2, x2, #0
  [0x10710] sub x2, x2, x15
  [0x10714] adrp x16, #0x10000
  [0x10718] add x16, x16, #0
  [0x1071C] ldr w9, [x16]
  [0x10720] mov x9, x9
  [0x10724] mov x7, x7
  [0x10728] mov x6, x6
  [0x1072C] mov x2, x2
  [0x10730] add x9, x9, x15
  [0x10734] stp x3, x5, [sp, #-0x10]!
  [0x10738] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1073C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10740] blr x9 ;; misaligned with debug data
  [0x10744] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10748] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1074C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10750] mov x3, x3
  [0x10754] adrp x16, #0x10000
  [0x10758] add x16, x16, #0
  [0x1075C] ldr w7, [x16]
  [0x10760] movz x6, #0x9
  [0x10764] adrp x2, #0x10000
  [0x10768] add x2, x2, #0
  [0x1076C] sub x2, x2, x15
  [0x10770] adrp x16, #0x10000
  [0x10774] add x16, x16, #0
  [0x10778] ldr w9, [x16]
  [0x1077C] mov x9, x9
  [0x10780] mov x7, x7
  [0x10784] mov x6, x6
  [0x10788] mov x2, x2
  [0x1078C] add x9, x9, x15
  [0x10790] stp x3, x5, [sp, #-0x10]!
  [0x10794] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10798] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1079C] blr x9 ;; misaligned with debug data
  [0x107A0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x107A4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x107A8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x107AC] mov x3, x3
  [0x107B0] adrp x16, #0x10000
  [0x107B4] add x16, x16, #0
  [0x107B8] ldr w9, [x16]
  [0x107BC] mov x8, x14
  [0x107C0] sub x8, x8, x15 ;; misaligned with debug data
  [0x107C4] cmp x9, x8
  [0x107C8] b.eq #0x107ec
  [0x107CC] adrp x9, #0x10000
  [0x107D0] add x9, x9, #0
  [0x107D4] sub x9, x9, x15
  [0x107D8] adrp x16, #0x10000
  [0x107DC] add x16, x16, #0
  [0x107E0] str w9, [x16]
  [0x107E4] mov x9, x9
  [0x107E8] b #0x10808
  [0x107EC] adrp x16, #0x10000
  [0x107F0] add x16, x16, #0
  [0x107F4] ldr w9, [x16]
  [0x107F8] adrp x16, #0x10000
  [0x107FC] add x16, x16, #0
  [0x10800] str w9, [x16]
  [0x10804] mov x9, x9
  [0x10808] adrp x16, #0x10000
  [0x1080C] add x16, x16, #0
  [0x10810] ldr w9, [x16]
  [0x10814] mov x8, x14
  [0x10818] sub x8, x8, x15 ;; misaligned with debug data
  [0x1081C] cmp x9, x8
  [0x10820] b.eq #0x10844
  [0x10824] adrp x9, #0x10000
  [0x10828] add x9, x9, #0
  [0x1082C] sub x9, x9, x15
  [0x10830] adrp x16, #0x10000
  [0x10834] add x16, x16, #0
  [0x10838] str w9, [x16]
  [0x1083C] mov x9, x9
  [0x10840] b #0x10860
  [0x10844] adrp x16, #0x10000
  [0x10848] add x16, x16, #0
  [0x1084C] ldr w9, [x16]
  [0x10850] adrp x16, #0x10000
  [0x10854] add x16, x16, #0
  [0x10858] str w9, [x16]
  [0x1085C] mov x9, x9
  [0x10860] adrp x16, #0x10000
  [0x10864] add x16, x16, #0
  [0x10868] ldr w7, [x16]
  [0x1086C] movz x6, #0x10
  [0x10870] adrp x2, #0x10000
  [0x10874] add x2, x2, #0
  [0x10878] sub x2, x2, x15
  [0x1087C] adrp x16, #0x10000
  [0x10880] add x16, x16, #0
  [0x10884] ldr w9, [x16]
  [0x10888] mov x9, x9
  [0x1088C] mov x7, x7
  [0x10890] mov x6, x6
  [0x10894] mov x2, x2
  [0x10898] add x9, x9, x15
  [0x1089C] stp x3, x5, [sp, #-0x10]!
  [0x108A0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108A4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108A8] blr x9 ;; misaligned with debug data
  [0x108AC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108B0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108B4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108B8] mov x3, x3
  [0x108BC] adrp x16, #0x10000
  [0x108C0] add x16, x16, #0
  [0x108C4] ldr w3, [x16]
  [0x108C8] mov x3, x3
  [0x108CC] add x16, x3, x15
  [0x108D0] ldr w9, [x16, #0x60] ;; misaligned with debug data
  [0x108D4] movz x8, #0
  [0x108D8] cmp x9, x8
  [0x108DC] b.ne #0x10968
  [0x108E0] adrp x7, #0x10000
  [0x108E4] add x7, x7, #0
  [0x108E8] adrp x16, #0x10000
  [0x108EC] add x16, x16, #0
  [0x108F0] ldr w6, [x16]
  [0x108F4] movz x2, #0x1000
  [0x108F8] adrp x16, #0x10000
  [0x108FC] add x16, x16, #0
  [0x10900] ldr w9, [x16]
  [0x10904] add x16, x9, x15
  [0x10908] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x1090C] mov x9, x9
  [0x10910] mov x7, x7
  [0x10914] mov x6, x6
  [0x10918] mov x2, x2
  [0x1091C] add x9, x9, x15
  [0x10920] stp x3, x5, [sp, #-0x10]!
  [0x10924] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10928] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1092C] blr x9 ;; misaligned with debug data
  [0x10930] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10934] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10938] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1093C] mov x0, x0
  [0x10940] add x16, x3, x15
  [0x10944] str w0, [x16, #0x60] ;; misaligned with debug data
  [0x10948] movz x9, #0
  [0x1094C] add x16, x3, x15
  [0x10950] ldr w8, [x16, #0x60] ;; misaligned with debug data
  [0x10954] add x16, x8, x15
  [0x10958] str w9, [x16] ;; misaligned with debug data
  [0x1095C] movz x9, #0
  [0x10960] mov x9, x9
  [0x10964] b #0x10970
  [0x10968] mov x9, x14
  [0x1096C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10970] add x16, x3, x15
  [0x10974] ldr w9, [x16, #0x64] ;; misaligned with debug data
  [0x10978] movz x8, #0
  [0x1097C] cmp x9, x8
  [0x10980] b.ne #0x10a6c
  [0x10984] adrp x7, #0x10000
  [0x10988] add x7, x7, #0
  [0x1098C] adrp x16, #0x10000
  [0x10990] add x16, x16, #0
  [0x10994] ldr w6, [x16]
  [0x10998] movz x2, #0x74
  [0x1099C] adrp x16, #0x10000
  [0x109A0] add x16, x16, #0
  [0x109A4] ldr w9, [x16]
  [0x109A8] add x16, x9, x15
  [0x109AC] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x109B0] mov x9, x9
  [0x109B4] mov x7, x7
  [0x109B8] mov x6, x6
  [0x109BC] mov x2, x2
  [0x109C0] add x9, x9, x15
  [0x109C4] stp x3, x5, [sp, #-0x10]!
  [0x109C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x109CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109D0] blr x9 ;; misaligned with debug data
  [0x109D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x109E0] mov x0, x0
  [0x109E4] mov x0, x0
  [0x109E8] add x16, x3, x15
  [0x109EC] str w0, [x16, #0x64] ;; misaligned with debug data
  [0x109F0] movz x9, #0
  [0x109F4] mov x9, x9
  [0x109F8] b #0x10a30
  [0x109FC] mov x8, x9
  [0x10A00] mov x1, x9
  [0x10A04] lsl x1, x1, #4
  [0x10A08] mov x1, x1
  [0x10A0C] movz x2, #0xc
  [0x10A10] add x2, x2, x0
  [0x10A14] add x1, x1, x2
  [0x10A18] add x16, x1, x15
  [0x10A1C] strb w8, [x16, #0xb] ;; misaligned with debug data
  [0x10A20] mov x9, x9
  [0x10A24] movz x8, #0x1
  [0x10A28] add x9, x9, x8
  [0x10A2C] mov x9, x9
  [0x10A30] add x16, x0, x15
  [0x10A34] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10A38] cmp x9, x8
  [0x10A3C] b.lt #0x109fc
  [0x10A40] mov x9, x14
  [0x10A44] sub x9, x9, x15 ;; misaligned with debug data
  [0x10A48] add x16, x0, x15
  [0x10A4C] ldrh w9, [x16, #0x24] ;; misaligned with debug data
  [0x10A50] mov x9, x9
  [0x10A54] movz x8, #0x100
  [0x10A58] orr x9, x9, x8
  [0x10A5C] add x16, x0, x15
  [0x10A60] strh w9, [x16, #0x24] ;; misaligned with debug data
  [0x10A64] mov x9, x9
  [0x10A68] b #0x10a74
  [0x10A6C] mov x9, x14
  [0x10A70] sub x9, x9, x15 ;; misaligned with debug data
  [0x10A74] add x16, x3, x15
  [0x10A78] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10A7C] movz x8, #0
  [0x10A80] cmp x9, x8
  [0x10A84] b.ne #0x10af8
  [0x10A88] adrp x7, #0x10000
  [0x10A8C] add x7, x7, #0
  [0x10A90] adrp x16, #0x10000
  [0x10A94] add x16, x16, #0
  [0x10A98] ldr w6, [x16]
  [0x10A9C] movz x2, #0xfff
  [0x10AA0] adrp x16, #0x10000
  [0x10AA4] add x16, x16, #0
  [0x10AA8] ldr w9, [x16]
  [0x10AAC] add x16, x9, x15
  [0x10AB0] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10AB4] mov x9, x9
  [0x10AB8] mov x7, x7
  [0x10ABC] mov x6, x6
  [0x10AC0] mov x2, x2
  [0x10AC4] add x9, x9, x15
  [0x10AC8] stp x3, x5, [sp, #-0x10]!
  [0x10ACC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AD0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AD4] blr x9 ;; misaligned with debug data
  [0x10AD8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10ADC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10AE0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AE4] mov x0, x0
  [0x10AE8] add x16, x3, x15
  [0x10AEC] str w0, [x16, #0x6c] ;; misaligned with debug data
  [0x10AF0] mov x0, x0
  [0x10AF4] b #0x10b00
  [0x10AF8] mov x0, x14
  [0x10AFC] sub x0, x0, x15 ;; misaligned with debug data
  [0x10B00] add x16, x3, x15
  [0x10B04] ldr w9, [x16, #0x134] ;; misaligned with debug data
  [0x10B08] movz x8, #0
  [0x10B0C] cmp x9, x8
  [0x10B10] b.ne #0x10b9c
  [0x10B14] adrp x7, #0x10000
  [0x10B18] add x7, x7, #0
  [0x10B1C] adrp x16, #0x10000
  [0x10B20] add x16, x16, #0
  [0x10B24] ldr w6, [x16]
  [0x10B28] movz x2, #0x40
  [0x10B2C] adrp x16, #0x10000
  [0x10B30] add x16, x16, #0
  [0x10B34] ldr w9, [x16]
  [0x10B38] add x16, x9, x15
  [0x10B3C] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10B40] mov x9, x9
  [0x10B44] mov x7, x7
  [0x10B48] mov x6, x6
  [0x10B4C] mov x2, x2
  [0x10B50] add x9, x9, x15
  [0x10B54] stp x3, x5, [sp, #-0x10]!
  [0x10B58] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B5C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B60] blr x9 ;; misaligned with debug data
  [0x10B64] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B68] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10B6C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10B70] mov x0, x0
  [0x10B74] add x16, x3, x15
  [0x10B78] str w0, [x16, #0x134] ;; misaligned with debug data
  [0x10B7C] movz x9, #0
  [0x10B80] add x16, x3, x15
  [0x10B84] ldr w8, [x16, #0x134] ;; misaligned with debug data
  [0x10B88] add x16, x8, x15
  [0x10B8C] str w9, [x16] ;; misaligned with debug data
  [0x10B90] movz x9, #0
  [0x10B94] mov x9, x9
  [0x10B98] b #0x10ba4
  [0x10B9C] mov x9, x14
  [0x10BA0] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BA4] add x16, x3, x15
  [0x10BA8] ldur x9, [x16, #0xfc] ;; misaligned with debug data
  [0x10BAC] movz x8, #0
  [0x10BB0] cmp x9, x8
  [0x10BB4] b.ne #0x10bd4
  [0x10BB8] mov x9, x14
  [0x10BBC] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BC0] mov x9, x9
  [0x10BC4] add x16, x3, x15
  [0x10BC8] stur x9, [x16, #0xfc] ;; misaligned with debug data
  [0x10BCC] mov x9, x9
  [0x10BD0] b #0x10bdc
  [0x10BD4] mov x9, x14
  [0x10BD8] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BDC] add x16, x3, x15
  [0x10BE0] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x10BE4] mov x8, x14
  [0x10BE8] sub x8, x8, x15 ;; misaligned with debug data
  [0x10BEC] cmp x9, x8
  [0x10BF0] b.ne #0x10c48
  [0x10BF4] adrp x16, #0x10000
  [0x10BF8] add x16, x16, #0
  [0x10BFC] ldr w6, [x16]
  [0x10C00] add x16, x3, x15
  [0x10C04] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10C08] add x16, x9, x15
  [0x10C0C] ldr w9, [x16, #0x5c] ;; misaligned with debug data
  [0x10C10] mov x9, x9
  [0x10C14] mov x7, x3
  [0x10C18] mov x6, x6
  [0x10C1C] add x9, x9, x15
  [0x10C20] stp x3, x5, [sp, #-0x10]!
  [0x10C24] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C28] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C2C] blr x9 ;; misaligned with debug data
  [0x10C30] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C34] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C38] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C3C] mov x0, x0
  [0x10C40] mov x0, x0
  [0x10C44] b #0x10c50
  [0x10C48] mov x0, x14
  [0x10C4C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10C50] mov x9, x14
  [0x10C54] sub x9, x9, x15 ;; misaligned with debug data
  [0x10C58] add x16, x3, x15
  [0x10C5C] str w9, [x16, #0x108] ;; misaligned with debug data
  [0x10C60] mov x9, x14
  [0x10C64] sub x9, x9, x15 ;; misaligned with debug data
  [0x10C68] mov x9, x9
  [0x10C6C] add x16, x3, x15
  [0x10C70] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10C74] str x9, [x16] ;; misaligned with debug data
  [0x10C78] movz x9, #0x1
  [0x10C7C] add x16, x3, x15
  [0x10C80] str w9, [x16, #0x114] ;; misaligned with debug data
  [0x10C84] movz x9, #0
  [0x10C88] add x16, x3, x15
  [0x10C8C] str w9, [x16, #0x118] ;; misaligned with debug data
  [0x10C90] movz x9, #0xffff
  [0x10C94] movk x9, #0xffff, lsl #16
  [0x10C98] movk x9, #0xffff, lsl #32
  [0x10C9C] movk x9, #0xffff, lsl #48
  [0x10CA0] add x16, x3, x15
  [0x10CA4] str w9, [x16, #0x11c] ;; misaligned with debug data
  [0x10CA8] mov x9, x14
  [0x10CAC] sub x9, x9, x15 ;; misaligned with debug data
  [0x10CB0] mov x9, x9
  [0x10CB4] add x16, x3, x15
  [0x10CB8] add x16, x16, #0x124 ;; misaligned with debug data
  [0x10CBC] str x9, [x16] ;; misaligned with debug data
  [0x10CC0] mov x9, x14
  [0x10CC4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10CC8] mov x9, x9
  [0x10CCC] add x16, x3, x15
  [0x10CD0] add x16, x16, #0x12c ;; misaligned with debug data
  [0x10CD4] str x9, [x16] ;; misaligned with debug data
  [0x10CD8] adrp x16, #0x10000
  [0x10CDC] add x16, x16, #0
  [0x10CE0] ldr w7, [x16]
  [0x10CE4] movz x6, #0x1b
  [0x10CE8] adrp x2, #0x10000
  [0x10CEC] add x2, x2, #0
  [0x10CF0] sub x2, x2, x15
  [0x10CF4] adrp x16, #0x10000
  [0x10CF8] add x16, x16, #0
  [0x10CFC] ldr w9, [x16]
  [0x10D00] mov x9, x9
  [0x10D04] mov x7, x7
  [0x10D08] mov x6, x6
  [0x10D0C] mov x2, x2
  [0x10D10] add x9, x9, x15
  [0x10D14] stp x3, x5, [sp, #-0x10]!
  [0x10D18] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D1C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D20] blr x9 ;; misaligned with debug data
  [0x10D24] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D28] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D2C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D30] mov x3, x3
  [0x10D34] adrp x16, #0x10000
  [0x10D38] add x16, x16, #0
  [0x10D3C] ldr w7, [x16]
  [0x10D40] movz x6, #0x1c
  [0x10D44] adrp x2, #0x10000
  [0x10D48] add x2, x2, #0
  [0x10D4C] sub x2, x2, x15
  [0x10D50] adrp x16, #0x10000
  [0x10D54] add x16, x16, #0
  [0x10D58] ldr w9, [x16]
  [0x10D5C] mov x9, x9
  [0x10D60] mov x7, x7
  [0x10D64] mov x6, x6
  [0x10D68] mov x2, x2
  [0x10D6C] add x9, x9, x15
  [0x10D70] stp x3, x5, [sp, #-0x10]!
  [0x10D74] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D78] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D7C] blr x9 ;; misaligned with debug data
  [0x10D80] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D84] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D88] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D8C] mov x3, x3
  [0x10D90] mov x0, x3
  [0x10D94] add sp, sp, #0x10
  [0x10D98] ldp x29, x30, [sp], #0x10
  [0x10D9C] ret


[(method seen-text? game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] add x16, x7, x15
  [0x10018] ldr w7, [x16, #0x6c] ;; misaligned with debug data
  [0x1001C] mov x6, x6
  [0x10020] add x16, x7, x15
  [0x10024] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10028] add x16, x9, x15
  [0x1002C] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10030] mov x9, x9
  [0x10034] mov x7, x7
  [0x10038] mov x6, x6
  [0x1003C] add x9, x9, x15
  [0x10040] stp x3, x5, [sp, #-0x10]!
  [0x10044] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10048] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1004C] blr x9 ;; misaligned with debug data
  [0x10050] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10054] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10058] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1005C] mov x0, x0
  [0x10060] mov x0, x0
  [0x10064] add sp, sp, #0x10
  [0x10068] ldp x29, x30, [sp], #0x10
  [0x1006C] ret


[(method buzzer-count game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] ldr w9, [x16]
  [0x10020] mov x9, x9
  [0x10024] mov x7, x6
  [0x10028] add x9, x9, x15
  [0x1002C] stp x3, x5, [sp, #-0x10]!
  [0x10030] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10034] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10038] blr x9 ;; misaligned with debug data
  [0x1003C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10040] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10044] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10048] mov x0, x0
  [0x1004C] movz x6, #0
  [0x10050] add x16, x0, x15
  [0x10054] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10058] add x16, x9, x15
  [0x1005C] ldr w9, [x16, #0x50] ;; misaligned with debug data
  [0x10060] mov x9, x9
  [0x10064] mov x7, x0
  [0x10068] mov x6, x6
  [0x1006C] add x9, x9, x15
  [0x10070] stp x3, x5, [sp, #-0x10]!
  [0x10074] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10078] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1007C] blr x9 ;; misaligned with debug data
  [0x10080] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10084] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10088] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1008C] mov x0, x0
  [0x10090] movz x9, #0
  [0x10094] mov x0, x0
  [0x10098] mov x9, x9
  [0x1009C] adrp x16, #0x10000
  [0x100A0] add x16, x16, #0
  [0x100A4] ldr w8, [x16]
  [0x100A8] add x16, x8, x15
  [0x100AC] ldr s23, [x16, #0x34] ;; misaligned with debug data
  [0x100B0] fcvtzs w8, s23
  [0x100B4] sxtw x8, w8
  [0x100B8] mov x8, x8
  [0x100BC] b #0x10148
  [0x100C0] mov x8, x8
  [0x100C4] movz x1, #0x1
  [0x100C8] sub x8, x8, x1
  [0x100CC] mov x8, x8
  [0x100D0] movz x1, #0x1
  [0x100D4] mov x2, x1
  [0x100D8] mov x6, x8
  [0x100DC] movz x1, #0
  [0x100E0] cmp x6, x1
  [0x100E4] b.le #0x100fc
  [0x100E8] mov x2, x2
  [0x100EC] mov x1, x6
  [0x100F0] lsl x2, x2, x1
  [0x100F4] mov x1, x2
  [0x100F8] b #0x10114
  [0x100FC] movz x1, #0
  [0x10100] sub x1, x1, x6
  [0x10104] mov x2, x2
  [0x10108] mov x1, x1
  [0x1010C] asr x2, x2, x1
  [0x10110] mov x1, x2
  [0x10114] mov x2, x0
  [0x10118] and x2, x2, x1
  [0x1011C] movz x1, #0
  [0x10120] cmp x2, x1
  [0x10124] b.eq #0x10140
  [0x10128] mov x1, x9
  [0x1012C] movz x9, #0x1
  [0x10130] add x1, x1, x9
  [0x10134] mov x9, x1
  [0x10138] mov x1, x1
  [0x1013C] b #0x10148
  [0x10140] mov x1, x14
  [0x10144] sub x1, x1, x15 ;; misaligned with debug data
  [0x10148] movz x1, #0
  [0x1014C] cmp x8, x1
  [0x10150] b.ne #0x100c0
  [0x10154] mov x8, x14
  [0x10158] sub x8, x8, x15 ;; misaligned with debug data
  [0x1015C] mov x0, x9
  [0x10160] add sp, sp, #0x10
  [0x10164] ldp x29, x30, [sp], #0x10
  [0x10168] ret


[(method got-buzzer? game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] mov x3, x2
  [0x10018] adrp x16, #0x10000
  [0x1001C] add x16, x16, #0
  [0x10020] ldr w9, [x16]
  [0x10024] mov x9, x9
  [0x10028] mov x7, x6
  [0x1002C] add x9, x9, x15
  [0x10030] stp x3, x5, [sp, #-0x10]!
  [0x10034] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10038] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1003C] blr x9 ;; misaligned with debug data
  [0x10040] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10044] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10048] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1004C] mov x0, x0
  [0x10050] movz x6, #0
  [0x10054] add x16, x0, x15
  [0x10058] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1005C] add x16, x9, x15
  [0x10060] ldr w9, [x16, #0x50] ;; misaligned with debug data
  [0x10064] mov x9, x9
  [0x10068] mov x7, x0
  [0x1006C] mov x6, x6
  [0x10070] add x9, x9, x15
  [0x10074] stp x3, x5, [sp, #-0x10]!
  [0x10078] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1007C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10080] blr x9 ;; misaligned with debug data
  [0x10084] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10088] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1008C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10090] mov x0, x0
  [0x10094] movz x9, #0x1
  [0x10098] mov x9, x9
  [0x1009C] mov x3, x3
  [0x100A0] movz x8, #0
  [0x100A4] cmp x3, x8
  [0x100A8] b.le #0x100c0
  [0x100AC] mov x9, x9
  [0x100B0] mov x1, x3
  [0x100B4] lsl x9, x9, x1
  [0x100B8] mov x9, x9
  [0x100BC] b #0x100d8
  [0x100C0] movz x1, #0
  [0x100C4] sub x1, x1, x3
  [0x100C8] mov x9, x9
  [0x100CC] mov x1, x1
  [0x100D0] asr x9, x9, x1
  [0x100D4] mov x9, x9
  [0x100D8] mov x0, x0
  [0x100DC] and x0, x0, x9
  [0x100E0] movz x9, #0
  [0x100E4] mov x8, x14
  [0x100E8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100EC] cmp x0, x9
  [0x100F0] b.eq #0x10100
  [0x100F4] add x8, x14, #8
  [0x100F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100FC] mov x8, x8
  [0x10100] mov x0, x8
  [0x10104] add sp, sp, #0x10
  [0x10108] ldp x29, x30, [sp], #0x10
  [0x1010C] ret


[(method adjust game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0x10
  [0x10010] mov x5, x7
  [0x10014] mov x6, x6
  [0x10018] mov x12, x2
  [0x1001C] mov x3, x1
  [0x10020] mov x6, x6
  [0x10024] adrp x9, #0x10000
  [0x10028] add x9, x9, #0
  [0x1002C] cmp x6, x9
  [0x10030] b.ne #0x1013c
  [0x10034] fmov s23, w12
  [0x10038] adrp x16, #0x14000
  [0x1003C] ldr s22, [x16, #0xf60]
  [0x10040] fcmp s23, s22
  [0x10044] b.mi #0x100b0
  [0x10048] adrp x16, #0x10000
  [0x1004C] add x16, x16, #0
  [0x10050] ldr w9, [x16]
  [0x10054] add x16, x5, x15
  [0x10058] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x1005C] add x16, x5, x15
  [0x10060] ldr s22, [x16, #0xc] ;; misaligned with debug data
  [0x10064] mov x9, x9
  [0x10068] fmov w7, s23
  [0x1006C] sxtw x7, w7
  [0x10070] fmov w6, s22
  [0x10074] sxtw x6, w6
  [0x10078] mov x2, x12
  [0x1007C] add x9, x9, x15
  [0x10080] stp x3, x5, [sp, #-0x10]!
  [0x10084] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10088] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1008C] blr x9 ;; misaligned with debug data
  [0x10090] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10094] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10098] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1009C] mov x0, x0
  [0x100A0] add x16, x5, x15
  [0x100A4] str w0, [x16, #8] ;; misaligned with debug data
  [0x100A8] mov x0, x0
  [0x100AC] b #0x10128
  [0x100B0] adrp x16, #0x10000
  [0x100B4] add x16, x16, #0
  [0x100B8] ldr w9, [x16]
  [0x100BC] add x16, x5, x15
  [0x100C0] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x100C4] adrp x16, #0x14000
  [0x100C8] ldr s22, [x16, #0xf64]
  [0x100CC] adrp x16, #0x14000
  [0x100D0] ldr s21, [x16, #0xf68]
  [0x100D4] fmov s20, w12
  [0x100D8] fsub s21, s21, s20
  [0x100DC] mov x9, x9
  [0x100E0] fmov w7, s23
  [0x100E4] sxtw x7, w7
  [0x100E8] fmov w6, s22
  [0x100EC] sxtw x6, w6
  [0x100F0] fmov w2, s21
  [0x100F4] sxtw x2, w2
  [0x100F8] add x9, x9, x15
  [0x100FC] stp x3, x5, [sp, #-0x10]!
  [0x10100] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10104] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10108] blr x9 ;; misaligned with debug data
  [0x1010C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10110] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10114] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10118] mov x0, x0
  [0x1011C] add x16, x5, x15
  [0x10120] str w0, [x16, #8] ;; misaligned with debug data
  [0x10124] mov x0, x0
  [0x10128] add x16, x5, x15
  [0x1012C] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x10130] fmov w0, s23
  [0x10134] sxtw x0, w0
  [0x10138] b #0x10b0c
  [0x1013C] adrp x9, #0x10000
  [0x10140] add x9, x9, #0
  [0x10144] cmp x6, x9
  [0x10148] b.ne #0x10540
  [0x1014C] adrp x16, #0x14000
  [0x10150] ldr s23, [x16, #0xf6c]
  [0x10154] fmov s22, w12
  [0x10158] mov x9, x14
  [0x1015C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10160] fcmp s23, s22
  [0x10164] b.ge #0x10174
  [0x10168] add x9, x14, #8
  [0x1016C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10170] mov x9, x9
  [0x10174] mov x9, x9
  [0x10178] mov x8, x14
  [0x1017C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10180] cmp x9, x8
  [0x10184] b.eq #0x101d0
  [0x10188] add x16, x5, x15
  [0x1018C] ldr s23, [x16, #0x10] ;; misaligned with debug data
  [0x10190] mov v23.16b, v23.16b
  [0x10194] fmov s22, w12
  [0x10198] fadd s23, s23, s22
  [0x1019C] adrp x16, #0x10000
  [0x101A0] add x16, x16, #0
  [0x101A4] ldr w9, [x16]
  [0x101A8] add x16, x9, x15
  [0x101AC] ldr s22, [x16, #0xc] ;; misaligned with debug data
  [0x101B0] mov x9, x14
  [0x101B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101B8] fcmp s23, s22
  [0x101BC] b.ne #0x101cc
  [0x101C0] add x9, x14, #8
  [0x101C4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101C8] mov x9, x9
  [0x101CC] mov x9, x9
  [0x101D0] mov x8, x14
  [0x101D4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101D8] cmp x9, x8
  [0x101DC] b.eq #0x1025c
  [0x101E0] adrp x16, #0x10000
  [0x101E4] add x16, x16, #0
  [0x101E8] ldr w9, [x16]
  [0x101EC] movz x7, #0x233
  [0x101F0] adrp x6, #0x14000
  [0x101F4] add x6, x6, #0xf74
  [0x101F8] sub x6, x6, x15
  [0x101FC] mov x2, x14
  [0x10200] sub x2, x2, x15 ;; misaligned with debug data
  [0x10204] mov x2, x2
  [0x10208] adrp x16, #0x10000
  [0x1020C] add x16, x16, #0
  [0x10210] ldr w1, [x16]
  [0x10214] movz x8, #0
  [0x10218] mov x9, x9
  [0x1021C] mov x7, x7
  [0x10220] mov x6, x6
  [0x10224] mov x2, x2
  [0x10228] mov x1, x1
  [0x1022C] mov x8, x8
  [0x10230] add x9, x9, x15
  [0x10234] stp x3, x5, [sp, #-0x10]!
  [0x10238] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1023C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10240] blr x9 ;; misaligned with debug data
  [0x10244] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10248] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1024C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10250] mov x11, x11
  [0x10254] mov x11, x11
  [0x10258] b #0x10264
  [0x1025C] mov x11, x14
  [0x10260] sub x11, x11, x15 ;; misaligned with debug data
  [0x10264] adrp x16, #0x14000
  [0x10268] ldr s23, [x16, #0xf84]
  [0x1026C] fmov s22, w12
  [0x10270] fcmp s23, s22
  [0x10274] b.ge #0x10510
  [0x10278] mov x3, x3
  [0x1027C] mov x3, x3
  [0x10280] mov x9, x3
  [0x10284] lsl x9, x9, #0x20
  [0x10288] lsr x9, x9, #0x20
  [0x1028C] mov x8, x14
  [0x10290] sub x8, x8, x15 ;; misaligned with debug data
  [0x10294] cmp x9, x8
  [0x10298] b.eq #0x102e4
  [0x1029C] mov x9, x3
  [0x102A0] lsl x9, x9, #0x20
  [0x102A4] lsr x9, x9, #0x20
  [0x102A8] add x16, x9, x15
  [0x102AC] ldr w9, [x16] ;; misaligned with debug data
  [0x102B0] mov x9, x9
  [0x102B4] mov x3, x3
  [0x102B8] asr x3, x3, #0x20
  [0x102BC] add x16, x9, x15
  [0x102C0] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x102C4] cmp x3, x8
  [0x102C8] b.ne #0x102d4
  [0x102CC] mov x9, x9
  [0x102D0] b #0x102dc
  [0x102D4] mov x9, x14
  [0x102D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x102DC] mov x9, x9
  [0x102E0] b #0x102ec
  [0x102E4] mov x9, x14
  [0x102E8] sub x9, x9, x15 ;; misaligned with debug data
  [0x102EC] mov x9, x9
  [0x102F0] mov x8, x9
  [0x102F4] mov x1, x14
  [0x102F8] sub x1, x1, x15 ;; misaligned with debug data
  [0x102FC] cmp x8, x1
  [0x10300] b.eq #0x10310
  [0x10304] add x16, x9, x15
  [0x10308] ldr w8, [x16, #0x30] ;; misaligned with debug data
  [0x1030C] mov x8, x8
  [0x10310] mov x1, x14
  [0x10314] sub x1, x1, x15 ;; misaligned with debug data
  [0x10318] cmp x8, x1
  [0x1031C] b.eq #0x10500
  [0x10320] adrp x16, #0x10000
  [0x10324] add x16, x16, #0
  [0x10328] ldr w8, [x16]
  [0x1032C] add x16, x8, x15
  [0x10330] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10334] add x16, x9, x15
  [0x10338] ldr w1, [x16, #0x30] ;; misaligned with debug data
  [0x1033C] add x16, x1, x15
  [0x10340] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10344] add x16, x1, x15
  [0x10348] ldr w1, [x16, #0x10] ;; misaligned with debug data
  [0x1034C] add x16, x1, x15
  [0x10350] ldr w1, [x16, #0x34] ;; misaligned with debug data
  [0x10354] add x16, x1, x15
  [0x10358] ldrsw x1, [x16, #0xc] ;; misaligned with debug data
  [0x1035C] cmp x8, x1
  [0x10360] b.lt #0x104f0
  [0x10364] add x16, x9, x15
  [0x10368] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x1036C] add x16, x9, x15
  [0x10370] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10374] add x16, x9, x15
  [0x10378] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x1037C] add x16, x9, x15
  [0x10380] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10384] add x16, x9, x15
  [0x10388] ldrsw x9, [x16, #0xc] ;; misaligned with debug data
  [0x1038C] mov x9, x9
  [0x10390] movz x8, #0xffff
  [0x10394] movk x8, #0xffff, lsl #16
  [0x10398] movk x8, #0xffff, lsl #32
  [0x1039C] movk x8, #0xffff, lsl #48
  [0x103A0] add x9, x9, x8
  [0x103A4] movz x8, #0xc
  [0x103A8] mov x9, x9
  [0x103AC] lsl x9, x9, #2
  [0x103B0] add x9, x9, x8
  [0x103B4] mov x9, x9
  [0x103B8] adrp x16, #0x10000
  [0x103BC] add x16, x16, #0
  [0x103C0] ldr w8, [x16]
  [0x103C4] add x9, x9, x8
  [0x103C8] add x16, x9, x15
  [0x103CC] ldrsw x3, [x16] ;; misaligned with debug data
  [0x103D0] mov x3, x3
  [0x103D4] mov x9, x3
  [0x103D8] mov x9, x9
  [0x103DC] movz x8, #0x18
  [0x103E0] add x8, x8, x5
  [0x103E4] add x9, x9, x8
  [0x103E8] add x16, x9, x15
  [0x103EC] ldrb w9, [x16] ;; misaligned with debug data
  [0x103F0] mov x9, x9
  [0x103F4] fmov s23, w12
  [0x103F8] fcvtzs w8, s23
  [0x103FC] sxtw x8, w8
  [0x10400] add x9, x9, x8
  [0x10404] mov x8, x3
  [0x10408] mov x8, x8
  [0x1040C] movz x1, #0x18
  [0x10410] add x1, x1, x5
  [0x10414] add x8, x8, x1
  [0x10418] add x16, x8, x15
  [0x1041C] strb w9, [x16] ;; misaligned with debug data
  [0x10420] add x16, x5, x15
  [0x10424] ldr s23, [x16, #0x14] ;; misaligned with debug data
  [0x10428] mov v23.16b, v23.16b
  [0x1042C] fmov s22, w12
  [0x10430] fadd s23, s23, s22
  [0x10434] add x16, x5, x15
  [0x10438] str s23, [x16, #0x14] ;; misaligned with debug data
  [0x1043C] mov x11, x3
  [0x10440] adrp x16, #0x10000
  [0x10444] add x16, x16, #0
  [0x10448] ldr w9, [x16]
  [0x1044C] mov x9, x9
  [0x10450] mov x7, x3
  [0x10454] add x9, x9, x15
  [0x10458] stp x3, x5, [sp, #-0x10]!
  [0x1045C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10460] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10464] blr x9 ;; misaligned with debug data
  [0x10468] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1046C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10470] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10474] mov x0, x0
  [0x10478] mov x11, x11
  [0x1047C] movz x9, #0x18
  [0x10480] add x9, x9, x5
  [0x10484] add x11, x11, x9
  [0x10488] add x16, x11, x15
  [0x1048C] ldrb w9, [x16] ;; misaligned with debug data
  [0x10490] add x16, x0, x15
  [0x10494] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10498] cmp x9, x8
  [0x1049C] b.ne #0x104e0
  [0x104A0] adrp x16, #0x10000
  [0x104A4] add x16, x16, #0
  [0x104A8] ldr w9, [x16]
  [0x104AC] mov x9, x9
  [0x104B0] mov x7, x3
  [0x104B4] add x9, x9, x15
  [0x104B8] stp x3, x5, [sp, #-0x10]!
  [0x104BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104C4] blr x9 ;; misaligned with debug data
  [0x104C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104D4] mov x0, x0
  [0x104D8] mov x0, x0
  [0x104DC] b #0x104e8
  [0x104E0] mov x0, x14
  [0x104E4] sub x0, x0, x15 ;; misaligned with debug data
  [0x104E8] mov x0, x0
  [0x104EC] b #0x104f8
  [0x104F0] mov x0, x14
  [0x104F4] sub x0, x0, x15 ;; misaligned with debug data
  [0x104F8] mov x0, x0
  [0x104FC] b #0x10508
  [0x10500] mov x0, x14
  [0x10504] sub x0, x0, x15 ;; misaligned with debug data
  [0x10508] mov x0, x0
  [0x1050C] b #0x10518
  [0x10510] mov x0, x14
  [0x10514] sub x0, x0, x15 ;; misaligned with debug data
  [0x10518] add x16, x5, x15
  [0x1051C] ldr s23, [x16, #0x10] ;; misaligned with debug data
  [0x10520] mov v23.16b, v23.16b
  [0x10524] fmov s22, w12
  [0x10528] fadd s23, s23, s22
  [0x1052C] add x16, x5, x15
  [0x10530] str s23, [x16, #0x10] ;; misaligned with debug data
  [0x10534] fmov w0, s23
  [0x10538] sxtw x0, w0
  [0x1053C] b #0x10b0c
  [0x10540] adrp x9, #0x10000
  [0x10544] add x9, x9, #0
  [0x10548] cmp x6, x9
  [0x1054C] b.ne #0x10780
  [0x10550] fmov s23, w12
  [0x10554] fcvtzs w3, s23
  [0x10558] sxtw x3, w3
  [0x1055C] mov x3, x3
  [0x10560] mov x6, x3
  [0x10564] add x16, x5, x15
  [0x10568] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1056C] add x16, x9, x15
  [0x10570] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10574] mov x9, x9
  [0x10578] mov x7, x5
  [0x1057C] mov x6, x6
  [0x10580] add x9, x9, x15
  [0x10584] stp x3, x5, [sp, #-0x10]!
  [0x10588] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1058C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10590] blr x9 ;; misaligned with debug data
  [0x10594] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10598] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1059C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x105A0] mov x0, x0
  [0x105A4] mov x0, x0
  [0x105A8] mov x9, x14
  [0x105AC] sub x9, x9, x15 ;; misaligned with debug data
  [0x105B0] cmp x0, x9
  [0x105B4] b.ne #0x105e4
  [0x105B8] movz x9, #0x1
  [0x105BC] mov x9, x9
  [0x105C0] mov x8, x3
  [0x105C4] mov x0, x14
  [0x105C8] sub x0, x0, x15 ;; misaligned with debug data
  [0x105CC] cmp x9, x8
  [0x105D0] b.lo #0x105e0
  [0x105D4] add x0, x14, #8
  [0x105D8] sub x0, x0, x15 ;; misaligned with debug data
  [0x105DC] mov x0, x0
  [0x105E0] mov x0, x0
  [0x105E4] mov x9, x14
  [0x105E8] sub x9, x9, x15 ;; misaligned with debug data
  [0x105EC] cmp x0, x9
  [0x105F0] b.ne #0x10764
  [0x105F4] movz x9, #0
  [0x105F8] add x16, x5, x15
  [0x105FC] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10600] adrp x16, #0x10000
  [0x10604] add x16, x16, #0
  [0x10608] ldr w9, [x16]
  [0x1060C] add x16, x9, x15
  [0x10610] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10614] ldr x9, [x16] ;; misaligned with debug data
  [0x10618] add x16, x5, x15
  [0x1061C] stur x9, [x16, #0xc4] ;; misaligned with debug data
  [0x10620] adrp x16, #0x10000
  [0x10624] add x16, x16, #0
  [0x10628] ldr w9, [x16]
  [0x1062C] add x16, x9, x15
  [0x10630] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10634] ldr x9, [x16] ;; misaligned with debug data
  [0x10638] movz x8, #0xc
  [0x1063C] mov x1, x3
  [0x10640] lsl x1, x1, #3
  [0x10644] add x1, x1, x8
  [0x10648] mov x1, x1
  [0x1064C] add x16, x5, x15
  [0x10650] ldr w8, [x16, #0xcc] ;; misaligned with debug data
  [0x10654] add x1, x1, x8
  [0x10658] add x16, x1, x15
  [0x1065C] str x9, [x16] ;; misaligned with debug data
  [0x10660] add x16, x5, x15
  [0x10664] ldr s23, [x16, #0x5c] ;; misaligned with debug data
  [0x10668] mov v23.16b, v23.16b
  [0x1066C] adrp x16, #0x13000
  [0x10670] ldr s22, [x16, #0xf88]
  [0x10674] fadd s23, s23, s22
  [0x10678] add x16, x5, x15
  [0x1067C] str s23, [x16, #0x5c] ;; misaligned with debug data
  [0x10680] mov x9, x3
  [0x10684] lsl x9, x9, #4
  [0x10688] mov x9, x9
  [0x1068C] movz x8, #0xc
  [0x10690] add x16, x5, x15
  [0x10694] ldr w1, [x16, #0x64] ;; misaligned with debug data
  [0x10698] add x8, x8, x1
  [0x1069C] add x9, x9, x8
  [0x106A0] add x16, x9, x15
  [0x106A4] ldrh w9, [x16, #8] ;; misaligned with debug data
  [0x106A8] mov x9, x9
  [0x106AC] movz x8, #0x100
  [0x106B0] orr x9, x9, x8
  [0x106B4] mov x8, x3
  [0x106B8] lsl x8, x8, #4
  [0x106BC] mov x8, x8
  [0x106C0] movz x1, #0xc
  [0x106C4] add x16, x5, x15
  [0x106C8] ldr w2, [x16, #0x64] ;; misaligned with debug data
  [0x106CC] add x1, x1, x2
  [0x106D0] add x8, x8, x1
  [0x106D4] add x16, x8, x15
  [0x106D8] strh w9, [x16, #8] ;; misaligned with debug data
  [0x106DC] adrp x16, #0x10000
  [0x106E0] add x16, x16, #0
  [0x106E4] ldr w9, [x16]
  [0x106E8] mov x7, x3
  [0x106EC] mov x9, x9
  [0x106F0] mov x7, x7
  [0x106F4] add x9, x9, x15
  [0x106F8] stp x3, x5, [sp, #-0x10]!
  [0x106FC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10700] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10704] blr x9 ;; misaligned with debug data
  [0x10708] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1070C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10710] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10714] mov x0, x0
  [0x10718] adrp x16, #0x10000
  [0x1071C] add x16, x16, #0
  [0x10720] ldr w9, [x16]
  [0x10724] mov x3, x3
  [0x10728] movz x6, #0x7
  [0x1072C] mov x9, x9
  [0x10730] mov x7, x3
  [0x10734] mov x6, x6
  [0x10738] add x9, x9, x15
  [0x1073C] stp x3, x5, [sp, #-0x10]!
  [0x10740] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10744] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10748] blr x9 ;; misaligned with debug data
  [0x1074C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10750] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10754] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10758] mov x0, x0
  [0x1075C] mov x0, x0
  [0x10760] b #0x1076c
  [0x10764] mov x0, x14
  [0x10768] sub x0, x0, x15 ;; misaligned with debug data
  [0x1076C] add x16, x5, x15
  [0x10770] ldr s23, [x16, #0x5c] ;; misaligned with debug data
  [0x10774] fmov w0, s23
  [0x10778] sxtw x0, w0
  [0x1077C] b #0x10b0c
  [0x10780] adrp x9, #0x10000
  [0x10784] add x9, x9, #0
  [0x10788] cmp x6, x9
  [0x1078C] b.ne #0x10b04
  [0x10790] fmov s23, w12
  [0x10794] fcvtzs w7, s23
  [0x10798] sxtw x7, w7
  [0x1079C] movz x9, #0xffff
  [0x107A0] mov x7, x7
  [0x107A4] and x7, x7, x9
  [0x107A8] fmov s23, w12
  [0x107AC] fcvtzs w3, s23
  [0x107B0] sxtw x3, w3
  [0x107B4] mov x3, x3
  [0x107B8] asr x3, x3, #0x10
  [0x107BC] adrp x16, #0x13000
  [0x107C0] ldr s24, [x16, #0xf8c]
  [0x107C4] mov x7, x7
  [0x107C8] mov x11, x3
  [0x107CC] mov v24.16b, v24.16b
  [0x107D0] mov x9, x7
  [0x107D4] movz x8, #0
  [0x107D8] cmp x9, x8
  [0x107DC] b.ls #0x10af0
  [0x107E0] adrp x16, #0x10000
  [0x107E4] add x16, x16, #0
  [0x107E8] ldr w9, [x16]
  [0x107EC] mov x7, x7
  [0x107F0] mov x9, x9
  [0x107F4] mov x7, x7
  [0x107F8] add x9, x9, x15
  [0x107FC] stp x3, x5, [sp, #-0x10]!
  [0x10800] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10804] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10808] blr x9 ;; misaligned with debug data
  [0x1080C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10810] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10814] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10818] mov x0, x0
  [0x1081C] mov x12, x0
  [0x10820] movz x6, #0
  [0x10824] add x16, x12, x15
  [0x10828] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1082C] add x16, x9, x15
  [0x10830] ldr w9, [x16, #0x50] ;; misaligned with debug data
  [0x10834] mov x9, x9
  [0x10838] mov x7, x12
  [0x1083C] mov x6, x6
  [0x10840] add x9, x9, x15
  [0x10844] stp x3, x5, [sp, #-0x10]!
  [0x10848] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1084C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10850] blr x9 ;; misaligned with debug data
  [0x10854] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10858] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1085C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10860] mov x0, x0
  [0x10864] mov x3, x0
  [0x10868] movz x9, #0
  [0x1086C] mov x8, x14
  [0x10870] sub x8, x8, x15 ;; misaligned with debug data
  [0x10874] cmp x11, x9
  [0x10878] b.lt #0x10888
  [0x1087C] add x8, x14, #8
  [0x10880] sub x8, x8, x15 ;; misaligned with debug data
  [0x10884] mov x8, x8
  [0x10888] mov x9, x8
  [0x1088C] mov x8, x14
  [0x10890] sub x8, x8, x15 ;; misaligned with debug data
  [0x10894] cmp x9, x8
  [0x10898] b.eq #0x108d8
  [0x1089C] adrp x16, #0x10000
  [0x108A0] add x16, x16, #0
  [0x108A4] ldr w9, [x16]
  [0x108A8] add x16, x9, x15
  [0x108AC] ldr s23, [x16, #0x34] ;; misaligned with debug data
  [0x108B0] fcvtzs w9, s23
  [0x108B4] sxtw x9, w9
  [0x108B8] mov x8, x14
  [0x108BC] sub x8, x8, x15 ;; misaligned with debug data
  [0x108C0] cmp x11, x9
  [0x108C4] b.ge #0x108d4
  [0x108C8] add x8, x14, #8
  [0x108CC] sub x8, x8, x15 ;; misaligned with debug data
  [0x108D0] mov x8, x8
  [0x108D4] mov x9, x8
  [0x108D8] mov x8, x14
  [0x108DC] sub x8, x8, x15 ;; misaligned with debug data
  [0x108E0] cmp x9, x8
  [0x108E4] b.eq #0x10a18
  [0x108E8] movz x9, #0x1
  [0x108EC] mov x9, x9
  [0x108F0] mov x8, x11
  [0x108F4] movz x1, #0
  [0x108F8] cmp x8, x1
  [0x108FC] b.le #0x10914
  [0x10900] mov x9, x9
  [0x10904] mov x1, x8
  [0x10908] lsl x9, x9, x1
  [0x1090C] mov x9, x9
  [0x10910] b #0x1092c
  [0x10914] movz x1, #0
  [0x10918] sub x1, x1, x8
  [0x1091C] mov x9, x9
  [0x10920] mov x1, x1
  [0x10924] asr x9, x9, x1
  [0x10928] mov x9, x9
  [0x1092C] mov x8, x3
  [0x10930] and x8, x8, x9
  [0x10934] movz x9, #0
  [0x10938] cmp x8, x9
  [0x1093C] b.ne #0x1096c
  [0x10940] add x16, x5, x15
  [0x10944] ldr s23, [x16, #0x58] ;; misaligned with debug data
  [0x10948] mov v23.16b, v23.16b
  [0x1094C] adrp x16, #0x13000
  [0x10950] ldr s22, [x16, #0xf90]
  [0x10954] fadd s23, s23, s22
  [0x10958] add x16, x5, x15
  [0x1095C] str s23, [x16, #0x58] ;; misaligned with debug data
  [0x10960] fmov w9, s23
  [0x10964] sxtw x9, w9
  [0x10968] b #0x10974
  [0x1096C] mov x9, x14
  [0x10970] sub x9, x9, x15 ;; misaligned with debug data
  [0x10974] add x16, x12, x15
  [0x10978] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1097C] add x16, x9, x15
  [0x10980] ldr w9, [x16, #0x54] ;; misaligned with debug data
  [0x10984] mov x9, x9
  [0x10988] mov x3, x3
  [0x1098C] movz x8, #0x1
  [0x10990] mov x8, x8
  [0x10994] mov x11, x11
  [0x10998] movz x1, #0
  [0x1099C] cmp x11, x1
  [0x109A0] b.le #0x109b8
  [0x109A4] mov x8, x8
  [0x109A8] mov x1, x11
  [0x109AC] lsl x8, x8, x1
  [0x109B0] mov x8, x8
  [0x109B4] b #0x109d0
  [0x109B8] movz x1, #0
  [0x109BC] sub x1, x1, x11
  [0x109C0] mov x8, x8
  [0x109C4] mov x1, x1
  [0x109C8] asr x8, x8, x1
  [0x109CC] mov x8, x8
  [0x109D0] orr x3, x3, x8
  [0x109D4] mov x3, x3
  [0x109D8] movz x2, #0
  [0x109DC] mov x9, x9
  [0x109E0] mov x7, x12
  [0x109E4] mov x6, x3
  [0x109E8] mov x2, x2
  [0x109EC] add x9, x9, x15
  [0x109F0] stp x3, x5, [sp, #-0x10]!
  [0x109F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x109F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109FC] blr x9 ;; misaligned with debug data
  [0x10A00] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A04] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A08] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A0C] mov x0, x0
  [0x10A10] mov x0, x0
  [0x10A14] b #0x10a20
  [0x10A18] mov x0, x14
  [0x10A1C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10A20] adrp x16, #0x10000
  [0x10A24] add x16, x16, #0
  [0x10A28] ldr w9, [x16]
  [0x10A2C] add x16, x9, x15
  [0x10A30] ldr s23, [x16, #0x34] ;; misaligned with debug data
  [0x10A34] fcvtzs w9, s23
  [0x10A38] sxtw x9, w9
  [0x10A3C] mov x9, x9
  [0x10A40] b #0x10ad4
  [0x10A44] mov x9, x9
  [0x10A48] movz x8, #0x1
  [0x10A4C] sub x9, x9, x8
  [0x10A50] mov x9, x9
  [0x10A54] movz x8, #0x1
  [0x10A58] mov x8, x8
  [0x10A5C] mov x2, x9
  [0x10A60] movz x1, #0
  [0x10A64] cmp x2, x1
  [0x10A68] b.le #0x10a80
  [0x10A6C] mov x8, x8
  [0x10A70] mov x1, x2
  [0x10A74] lsl x8, x8, x1
  [0x10A78] mov x8, x8
  [0x10A7C] b #0x10a98
  [0x10A80] movz x1, #0
  [0x10A84] sub x1, x1, x2
  [0x10A88] mov x8, x8
  [0x10A8C] mov x1, x1
  [0x10A90] asr x8, x8, x1
  [0x10A94] mov x8, x8
  [0x10A98] mov x1, x3
  [0x10A9C] and x1, x1, x8
  [0x10AA0] movz x8, #0
  [0x10AA4] cmp x1, x8
  [0x10AA8] b.eq #0x10acc
  [0x10AAC] adrp x16, #0x13000
  [0x10AB0] ldr s23, [x16, #0xf94]
  [0x10AB4] mov v23.16b, v23.16b
  [0x10AB8] fadd s23, s23, s24
  [0x10ABC] mov v24.16b, v23.16b
  [0x10AC0] fmov w8, s23
  [0x10AC4] sxtw x8, w8
  [0x10AC8] b #0x10ad4
  [0x10ACC] mov x8, x14
  [0x10AD0] sub x8, x8, x15 ;; misaligned with debug data
  [0x10AD4] movz x8, #0
  [0x10AD8] cmp x9, x8
  [0x10ADC] b.ne #0x10a44
  [0x10AE0] mov x9, x14
  [0x10AE4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10AE8] mov x9, x9
  [0x10AEC] b #0x10af8
  [0x10AF0] mov x9, x14
  [0x10AF4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10AF8] fmov w0, s24
  [0x10AFC] sxtw x0, w0
  [0x10B00] b #0x10b0c
  [0x10B04] mov x0, x14
  [0x10B08] sub x0, x0, x15 ;; misaligned with debug data
  [0x10B0C] mov x0, x0
  [0x10B10] add sp, sp, #0x10
  [0x10B14] ldr q24, [sp], #0x10
  [0x10B18] ldp x29, x30, [sp], #0x10
  [0x10B1C] ret


[(method initialize! game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x70
  [0x1000C] mov x5, x7
  [0x10010] mov x11, x6
  [0x10014] mov x12, x2
  [0x10018] mov x10, x1
  [0x1001C] mov x9, x11
  [0x10020] adrp x8, #0x10000
  [0x10024] add x8, x8, #0
  [0x10028] cmp x9, x8
  [0x1002C] b.ne #0x1029c
  [0x10030] add x16, x5, x15
  [0x10034] ldrsw x9, [x16, #0x98] ;; misaligned with debug data
  [0x10038] mov x9, x9
  [0x1003C] movz x8, #0x1
  [0x10040] add x9, x9, x8
  [0x10044] add x16, x5, x15
  [0x10048] str w9, [x16, #0x98] ;; misaligned with debug data
  [0x1004C] add x16, x5, x15
  [0x10050] ldrsw x9, [x16, #0x9c] ;; misaligned with debug data
  [0x10054] mov x9, x9
  [0x10058] movz x8, #0x1
  [0x1005C] add x9, x9, x8
  [0x10060] add x16, x5, x15
  [0x10064] str w9, [x16, #0x9c] ;; misaligned with debug data
  [0x10068] add x16, x5, x15
  [0x1006C] ldrsw x9, [x16, #0xa0] ;; misaligned with debug data
  [0x10070] mov x9, x9
  [0x10074] movz x8, #0x1
  [0x10078] add x9, x9, x8
  [0x1007C] add x16, x5, x15
  [0x10080] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10084] adrp x16, #0x10000
  [0x10088] add x16, x16, #0
  [0x1008C] ldr w9, [x16]
  [0x10090] mov x8, x14
  [0x10094] sub x8, x8, x15 ;; misaligned with debug data
  [0x10098] cmp x9, x8
  [0x1009C] b.eq #0x10224
  [0x100A0] adrp x16, #0x10000
  [0x100A4] add x16, x16, #0
  [0x100A8] ldr w9, [x16]
  [0x100AC] add x16, x9, x15
  [0x100B0] ldr w9, [x16, #0x1d8] ;; misaligned with debug data
  [0x100B4] add x16, x9, x15
  [0x100B8] ldr w3, [x16, #0x34] ;; misaligned with debug data
  [0x100BC] mov x3, x3
  [0x100C0] adrp x16, #0x10000
  [0x100C4] add x16, x16, #0
  [0x100C8] ldr w9, [x16]
  [0x100CC] add x16, x9, x15
  [0x100D0] ldrsw x9, [x16] ;; misaligned with debug data
  [0x100D4] add x16, x3, x15
  [0x100D8] ldrsw x8, [x16, #0xc] ;; misaligned with debug data
  [0x100DC] cmp x9, x8
  [0x100E0] b.lt #0x10210
  [0x100E4] adrp x16, #0x10000
  [0x100E8] add x16, x16, #0
  [0x100EC] ldr w9, [x16]
  [0x100F0] add x16, x3, x15
  [0x100F4] ldrsw x8, [x16, #0xc] ;; misaligned with debug data
  [0x100F8] mov x8, x8
  [0x100FC] movz x1, #0xffff
  [0x10100] movk x1, #0xffff, lsl #16
  [0x10104] movk x1, #0xffff, lsl #32
  [0x10108] movk x1, #0xffff, lsl #48
  [0x1010C] add x8, x8, x1
  [0x10110] movz x1, #0xc
  [0x10114] mov x8, x8
  [0x10118] lsl x8, x8, #2
  [0x1011C] add x8, x8, x1
  [0x10120] mov x8, x8
  [0x10124] adrp x16, #0x10000
  [0x10128] add x16, x16, #0
  [0x1012C] ldr w1, [x16]
  [0x10130] add x8, x8, x1
  [0x10134] add x16, x8, x15
  [0x10138] ldrsw x8, [x16] ;; misaligned with debug data
  [0x1013C] mov x8, x8
  [0x10140] mov x8, x8
  [0x10144] movz x1, #0x38
  [0x10148] add x1, x1, x5
  [0x1014C] add x8, x8, x1
  [0x10150] add x16, x8, x15
  [0x10154] ldrb w7, [x16] ;; misaligned with debug data
  [0x10158] mov x7, x7
  [0x1015C] movz x6, #0xff
  [0x10160] movz x2, #0x1
  [0x10164] mov x9, x9
  [0x10168] mov x7, x7
  [0x1016C] mov x6, x6
  [0x10170] mov x2, x2
  [0x10174] add x9, x9, x15
  [0x10178] stp x3, x5, [sp, #-0x10]!
  [0x1017C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10180] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10184] blr x9 ;; misaligned with debug data
  [0x10188] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1018C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10190] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10194] mov x0, x0
  [0x10198] mov x0, x0
  [0x1019C] mov x9, x0
  [0x101A0] add x16, x3, x15
  [0x101A4] ldrsw x8, [x16, #0xc] ;; misaligned with debug data
  [0x101A8] mov x8, x8
  [0x101AC] movz x1, #0xffff
  [0x101B0] movk x1, #0xffff, lsl #16
  [0x101B4] movk x1, #0xffff, lsl #32
  [0x101B8] movk x1, #0xffff, lsl #48
  [0x101BC] add x8, x8, x1
  [0x101C0] movz x1, #0xc
  [0x101C4] mov x8, x8
  [0x101C8] lsl x8, x8, #2
  [0x101CC] add x8, x8, x1
  [0x101D0] mov x8, x8
  [0x101D4] adrp x16, #0x10000
  [0x101D8] add x16, x16, #0
  [0x101DC] ldr w1, [x16]
  [0x101E0] add x8, x8, x1
  [0x101E4] add x16, x8, x15
  [0x101E8] ldrsw x8, [x16] ;; misaligned with debug data
  [0x101EC] mov x8, x8
  [0x101F0] mov x8, x8
  [0x101F4] movz x1, #0x38
  [0x101F8] add x1, x1, x5
  [0x101FC] add x8, x8, x1
  [0x10200] add x16, x8, x15
  [0x10204] strb w9, [x16] ;; misaligned with debug data
  [0x10208] mov x9, x0
  [0x1020C] b #0x10218
  [0x10210] mov x9, x14
  [0x10214] sub x9, x9, x15 ;; misaligned with debug data
  [0x10218] mov x0, x9
  [0x1021C] mov x9, x9
  [0x10220] b #0x1022c
  [0x10224] mov x9, x14
  [0x10228] sub x9, x9, x15 ;; misaligned with debug data
  [0x1022C] add x16, x5, x15
  [0x10230] ldr w9, [x16] ;; misaligned with debug data
  [0x10234] mov x9, x9
  [0x10238] adrp x8, #0x10000
  [0x1023C] add x8, x8, #0
  [0x10240] cmp x9, x8
  [0x10244] b.ne #0x1028c
  [0x10248] adrp x16, #0x15000
  [0x1024C] ldr s23, [x16, #0xe9c]
  [0x10250] add x16, x5, x15
  [0x10254] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x10258] fcmp s23, s22
  [0x1025C] b.ge #0x10274
  [0x10260] adrp x9, #0x10000
  [0x10264] add x9, x9, #0
  [0x10268] mov x11, x9
  [0x1026C] mov x9, x9
  [0x10270] b #0x10284
  [0x10274] adrp x9, #0x10000
  [0x10278] add x9, x9, #0
  [0x1027C] mov x11, x9
  [0x10280] mov x9, x9
  [0x10284] mov x9, x9
  [0x10288] b #0x10294
  [0x1028C] mov x5, x5
  [0x10290] b #0x10ea8
  [0x10294] mov x9, x9
  [0x10298] b #0x102a4
  [0x1029C] mov x9, x14
  [0x102A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x102A4] adrp x16, #0x10000
  [0x102A8] add x16, x16, #0
  [0x102AC] ldr w9, [x16]
  [0x102B0] sub x7, x14, #0xa
  [0x102B4] sub x7, x7, x15 ;; misaligned with debug data
  [0x102B8] sub x6, x14, #0xa
  [0x102BC] sub x6, x6, x15 ;; misaligned with debug data
  [0x102C0] adrp x2, #0x10000
  [0x102C4] add x2, x2, #0
  [0x102C8] mov x9, x9
  [0x102CC] mov x7, x7
  [0x102D0] mov x6, x6
  [0x102D4] mov x2, x2
  [0x102D8] add x9, x9, x15
  [0x102DC] stp x3, x5, [sp, #-0x10]!
  [0x102E0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102E4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102E8] blr x9 ;; misaligned with debug data
  [0x102EC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102F0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102F4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102F8] mov x3, x3
  [0x102FC] mov x9, x11
  [0x10300] adrp x8, #0x10000
  [0x10304] add x8, x8, #0
  [0x10308] cmp x9, x8
  [0x1030C] b.ne #0x10728
  [0x10310] adrp x16, #0x10000
  [0x10314] add x16, x16, #0
  [0x10318] ldr w9, [x16]
  [0x1031C] mov x9, x9
  [0x10320] add x9, x9, x15
  [0x10324] stp x3, x5, [sp, #-0x10]!
  [0x10328] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1032C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10330] blr x9 ;; misaligned with debug data
  [0x10334] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10338] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1033C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10340] mov x3, x3
  [0x10344] mov x9, x14
  [0x10348] sub x9, x9, x15 ;; misaligned with debug data
  [0x1034C] cmp x10, x9
  [0x10350] b.eq #0x1035c
  [0x10354] mov x10, x10
  [0x10358] b #0x103cc
  [0x1035C] adrp x16, #0x10000
  [0x10360] add x16, x16, #0
  [0x10364] ldr w9, [x16]
  [0x10368] adrp x8, #0x10000
  [0x1036C] add x8, x8, #0
  [0x10370] cmp x9, x8
  [0x10374] b.eq #0x1038c
  [0x10378] adrp x10, #0x15000
  [0x1037C] add x10, x10, #0xea4
  [0x10380] sub x10, x10, x15
  [0x10384] mov x10, x10
  [0x10388] b #0x103cc
  [0x1038C] adrp x16, #0x10000
  [0x10390] add x16, x16, #0
  [0x10394] ldr w9, [x16]
  [0x10398] mov x8, x14
  [0x1039C] sub x8, x8, x15 ;; misaligned with debug data
  [0x103A0] cmp x9, x8
  [0x103A4] b.eq #0x103bc
  [0x103A8] adrp x10, #0x15000
  [0x103AC] add x10, x10, #0xec4
  [0x103B0] sub x10, x10, x15
  [0x103B4] mov x10, x10
  [0x103B8] b #0x103cc
  [0x103BC] adrp x10, #0x15000
  [0x103C0] add x10, x10, #0xee4
  [0x103C4] sub x10, x10, x15
  [0x103C8] mov x10, x10
  [0x103CC] add x16, x5, x15
  [0x103D0] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x103D4] add x16, x9, x15
  [0x103D8] ldr w9, [x16, #0x5c] ;; misaligned with debug data
  [0x103DC] mov x9, x9
  [0x103E0] mov x7, x5
  [0x103E4] mov x6, x10
  [0x103E8] add x9, x9, x15
  [0x103EC] stp x3, x5, [sp, #-0x10]!
  [0x103F0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103F4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103F8] blr x9 ;; misaligned with debug data
  [0x103FC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10400] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10404] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10408] mov x0, x0
  [0x1040C] movz x9, #0
  [0x10410] add x16, x5, x15
  [0x10414] str w9, [x16, #0x13c] ;; misaligned with debug data
  [0x10418] mov x9, x14
  [0x1041C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10420] adrp x16, #0x10000
  [0x10424] add x16, x16, #0
  [0x10428] ldr w8, [x16]
  [0x1042C] add x16, x8, x15
  [0x10430] str w9, [x16, #0x1fc] ;; misaligned with debug data
  [0x10434] adrp x16, #0x14000
  [0x10438] ldr s23, [x16, #0xef4]
  [0x1043C] add x16, x5, x15
  [0x10440] str s23, [x16, #0x10] ;; misaligned with debug data
  [0x10444] adrp x16, #0x14000
  [0x10448] ldr s23, [x16, #0xef8]
  [0x1044C] add x16, x5, x15
  [0x10450] str s23, [x16, #0x5c] ;; misaligned with debug data
  [0x10454] adrp x16, #0x14000
  [0x10458] ldr s23, [x16, #0xefc]
  [0x1045C] add x16, x5, x15
  [0x10460] str s23, [x16, #0x14] ;; misaligned with debug data
  [0x10464] adrp x16, #0x14000
  [0x10468] ldr s23, [x16, #0xf00]
  [0x1046C] add x16, x5, x15
  [0x10470] str s23, [x16, #0x58] ;; misaligned with debug data
  [0x10474] movz x9, #0
  [0x10478] add x16, x5, x15
  [0x1047C] ldr w8, [x16, #0x60] ;; misaligned with debug data
  [0x10480] add x16, x8, x15
  [0x10484] str w9, [x16] ;; misaligned with debug data
  [0x10488] add x16, x5, x15
  [0x1048C] ldr w7, [x16, #0x6c] ;; misaligned with debug data
  [0x10490] add x16, x7, x15
  [0x10494] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10498] add x16, x9, x15
  [0x1049C] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x104A0] mov x9, x9
  [0x104A4] mov x7, x7
  [0x104A8] add x9, x9, x15
  [0x104AC] stp x3, x5, [sp, #-0x10]!
  [0x104B0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104B4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104B8] blr x9 ;; misaligned with debug data
  [0x104BC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104C0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104C4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104C8] mov x0, x0
  [0x104CC] adrp x16, #0x10000
  [0x104D0] add x16, x16, #0
  [0x104D4] ldr w9, [x16]
  [0x104D8] movz x7, #0xa
  [0x104DC] mov x9, x9
  [0x104E0] mov x7, x7
  [0x104E4] add x9, x9, x15
  [0x104E8] stp x3, x5, [sp, #-0x10]!
  [0x104EC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104F0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104F4] blr x9 ;; misaligned with debug data
  [0x104F8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104FC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10500] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10504] mov x0, x0
  [0x10508] add x16, x5, x15
  [0x1050C] str w0, [x16, #0x104] ;; misaligned with debug data
  [0x10510] movz x9, #0
  [0x10514] add x16, x5, x15
  [0x10518] str w9, [x16, #0x98] ;; misaligned with debug data
  [0x1051C] movz x9, #0
  [0x10520] add x16, x5, x15
  [0x10524] str w9, [x16, #0x9c] ;; misaligned with debug data
  [0x10528] movz x9, #0
  [0x1052C] add x16, x5, x15
  [0x10530] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10534] movz x9, #0
  [0x10538] add x16, x5, x15
  [0x1053C] ldr w8, [x16, #0x134] ;; misaligned with debug data
  [0x10540] add x16, x8, x15
  [0x10544] str w9, [x16] ;; misaligned with debug data
  [0x10548] adrp x16, #0x10000
  [0x1054C] add x16, x16, #0
  [0x10550] ldr w9, [x16]
  [0x10554] add x16, x9, x15
  [0x10558] add x16, x16, #0x30c ;; misaligned with debug data
  [0x1055C] ldr x9, [x16] ;; misaligned with debug data
  [0x10560] add x16, x5, x15
  [0x10564] stur x9, [x16, #0xa4] ;; misaligned with debug data
  [0x10568] adrp x16, #0x10000
  [0x1056C] add x16, x16, #0
  [0x10570] ldr w9, [x16]
  [0x10574] add x16, x9, x15
  [0x10578] add x16, x16, #0x30c ;; misaligned with debug data
  [0x1057C] ldr x9, [x16] ;; misaligned with debug data
  [0x10580] add x16, x5, x15
  [0x10584] stur x9, [x16, #0xc4] ;; misaligned with debug data
  [0x10588] adrp x16, #0x10000
  [0x1058C] add x16, x16, #0
  [0x10590] ldr w9, [x16]
  [0x10594] add x16, x9, x15
  [0x10598] add x16, x16, #0x30c ;; misaligned with debug data
  [0x1059C] ldr x9, [x16] ;; misaligned with debug data
  [0x105A0] add x16, x5, x15
  [0x105A4] stur x9, [x16, #0xac] ;; misaligned with debug data
  [0x105A8] adrp x16, #0x10000
  [0x105AC] add x16, x16, #0
  [0x105B0] ldr w9, [x16]
  [0x105B4] add x16, x9, x15
  [0x105B8] add x16, x16, #0x30c ;; misaligned with debug data
  [0x105BC] ldr x9, [x16] ;; misaligned with debug data
  [0x105C0] add x16, x5, x15
  [0x105C4] stur x9, [x16, #0xb4] ;; misaligned with debug data
  [0x105C8] adrp x16, #0x10000
  [0x105CC] add x16, x16, #0
  [0x105D0] ldr w9, [x16]
  [0x105D4] add x16, x9, x15
  [0x105D8] add x16, x16, #0x30c ;; misaligned with debug data
  [0x105DC] ldr x9, [x16] ;; misaligned with debug data
  [0x105E0] add x16, x5, x15
  [0x105E4] stur x9, [x16, #0xbc] ;; misaligned with debug data
  [0x105E8] movz x9, #0
  [0x105EC] mov x9, x9
  [0x105F0] b #0x10618
  [0x105F4] movz x8, #0
  [0x105F8] add x16, x5, x15
  [0x105FC] ldr w1, [x16, #0xcc] ;; misaligned with debug data
  [0x10600] add x16, x1, x15
  [0x10604] stur x8, [x16, #0xc] ;; misaligned with debug data
  [0x10608] mov x9, x9
  [0x1060C] movz x8, #0x1
  [0x10610] add x9, x9, x8
  [0x10614] mov x9, x9
  [0x10618] movz x8, #0x74
  [0x1061C] cmp x9, x8
  [0x10620] b.lt #0x105f4
  [0x10624] mov x9, x14
  [0x10628] sub x9, x9, x15 ;; misaligned with debug data
  [0x1062C] movz x9, #0
  [0x10630] mov x9, x9
  [0x10634] b #0x1070c
  [0x10638] movz x8, #0
  [0x1063C] mov x8, x8
  [0x10640] mov x1, x9
  [0x10644] mov x1, x1
  [0x10648] movz x2, #0x18
  [0x1064C] add x2, x2, x5
  [0x10650] add x1, x1, x2
  [0x10654] add x16, x1, x15
  [0x10658] strb w8, [x16] ;; misaligned with debug data
  [0x1065C] movz x8, #0
  [0x10660] mov x8, x8
  [0x10664] mov x1, x9
  [0x10668] mov x1, x1
  [0x1066C] movz x2, #0x38
  [0x10670] add x2, x2, x5
  [0x10674] add x1, x1, x2
  [0x10678] add x16, x1, x15
  [0x1067C] strb w8, [x16] ;; misaligned with debug data
  [0x10680] movz x8, #0
  [0x10684] movz x1, #0xc
  [0x10688] mov x2, x9
  [0x1068C] lsl x2, x2, #3
  [0x10690] add x2, x2, x1
  [0x10694] mov x2, x2
  [0x10698] add x16, x5, x15
  [0x1069C] ldr w1, [x16, #0xd0] ;; misaligned with debug data
  [0x106A0] add x2, x2, x1
  [0x106A4] add x16, x2, x15
  [0x106A8] str x8, [x16] ;; misaligned with debug data
  [0x106AC] movz x8, #0
  [0x106B0] movz x1, #0xc
  [0x106B4] mov x2, x9
  [0x106B8] lsl x2, x2, #3
  [0x106BC] add x2, x2, x1
  [0x106C0] mov x2, x2
  [0x106C4] add x16, x5, x15
  [0x106C8] ldr w1, [x16, #0xd4] ;; misaligned with debug data
  [0x106CC] add x2, x2, x1
  [0x106D0] add x16, x2, x15
  [0x106D4] str x8, [x16] ;; misaligned with debug data
  [0x106D8] movz x8, #0
  [0x106DC] mov x8, x8
  [0x106E0] mov x1, x9
  [0x106E4] mov x1, x1
  [0x106E8] movz x2, #0x70
  [0x106EC] add x2, x2, x5
  [0x106F0] add x1, x1, x2
  [0x106F4] add x16, x1, x15
  [0x106F8] strb w8, [x16] ;; misaligned with debug data
  [0x106FC] mov x9, x9
  [0x10700] movz x8, #0x1
  [0x10704] add x9, x9, x8
  [0x10708] mov x9, x9
  [0x1070C] movz x8, #0x20
  [0x10710] cmp x9, x8
  [0x10714] b.lt #0x10638
  [0x10718] mov x9, x14
  [0x1071C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10720] mov x9, x9
  [0x10724] b #0x10730
  [0x10728] mov x9, x14
  [0x1072C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10730] mov x9, x11
  [0x10734] adrp x8, #0x10000
  [0x10738] add x8, x8, #0
  [0x1073C] mov x1, x14
  [0x10740] sub x1, x1, x15 ;; misaligned with debug data
  [0x10744] cmp x9, x8
  [0x10748] b.ne #0x10758
  [0x1074C] add x1, x14, #8
  [0x10750] sub x1, x1, x15 ;; misaligned with debug data
  [0x10754] mov x1, x1
  [0x10758] mov x8, x1
  [0x1075C] mov x1, x14
  [0x10760] sub x1, x1, x15 ;; misaligned with debug data
  [0x10764] cmp x8, x1
  [0x10768] b.ne #0x10794
  [0x1076C] adrp x8, #0x10000
  [0x10770] add x8, x8, #0
  [0x10774] mov x1, x14
  [0x10778] sub x1, x1, x15 ;; misaligned with debug data
  [0x1077C] cmp x9, x8
  [0x10780] b.ne #0x10790
  [0x10784] add x1, x14, #8
  [0x10788] sub x1, x1, x15 ;; misaligned with debug data
  [0x1078C] mov x1, x1
  [0x10790] mov x8, x1
  [0x10794] mov x9, x14
  [0x10798] sub x9, x9, x15 ;; misaligned with debug data
  [0x1079C] cmp x8, x9
  [0x107A0] b.eq #0x1083c
  [0x107A4] add x16, x5, x15
  [0x107A8] ldr w9, [x16] ;; misaligned with debug data
  [0x107AC] mov x9, x9
  [0x107B0] adrp x8, #0x10000
  [0x107B4] add x8, x8, #0
  [0x107B8] cmp x9, x8
  [0x107BC] b.ne #0x107f0
  [0x107C0] mov x9, x14
  [0x107C4] sub x9, x9, x15 ;; misaligned with debug data
  [0x107C8] adrp x16, #0x10000
  [0x107CC] add x16, x16, #0
  [0x107D0] str w9, [x16]
  [0x107D4] mov x9, x14
  [0x107D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x107DC] adrp x16, #0x10000
  [0x107E0] add x16, x16, #0
  [0x107E4] str w9, [x16]
  [0x107E8] mov x9, x9
  [0x107EC] b #0x107f8
  [0x107F0] mov x9, x14
  [0x107F4] sub x9, x9, x15 ;; misaligned with debug data
  [0x107F8] adrp x16, #0x10000
  [0x107FC] add x16, x16, #0
  [0x10800] ldr w9, [x16]
  [0x10804] add x16, x9, x15
  [0x10808] ldr s23, [x16] ;; misaligned with debug data
  [0x1080C] add x16, x5, x15
  [0x10810] str s23, [x16, #0xc] ;; misaligned with debug data
  [0x10814] adrp x16, #0x10000
  [0x10818] add x16, x16, #0
  [0x1081C] ldr w9, [x16]
  [0x10820] add x16, x9, x15
  [0x10824] ldr s23, [x16, #4] ;; misaligned with debug data
  [0x10828] add x16, x5, x15
  [0x1082C] str s23, [x16, #8] ;; misaligned with debug data
  [0x10830] fmov w9, s23
  [0x10834] sxtw x9, w9
  [0x10838] b #0x10844
  [0x1083C] mov x9, x14
  [0x10840] sub x9, x9, x15 ;; misaligned with debug data
  [0x10844] add x16, x5, x15
  [0x10848] ldr w9, [x16] ;; misaligned with debug data
  [0x1084C] mov x9, x9
  [0x10850] adrp x8, #0x10000
  [0x10854] add x8, x8, #0
  [0x10858] cmp x9, x8
  [0x1085C] b.ne #0x10900
  [0x10860] adrp x16, #0x10000
  [0x10864] add x16, x16, #0
  [0x10868] ldr w9, [x16]
  [0x1086C] mov x9, x9
  [0x10870] mov x7, x11
  [0x10874] add x9, x9, x15
  [0x10878] stp x3, x5, [sp, #-0x10]!
  [0x1087C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10880] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10884] blr x9 ;; misaligned with debug data
  [0x10888] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1088C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10890] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10894] mov x3, x3
  [0x10898] mov x9, x14
  [0x1089C] sub x9, x9, x15 ;; misaligned with debug data
  [0x108A0] cmp x12, x9
  [0x108A4] b.eq #0x108f0
  [0x108A8] add x16, x5, x15
  [0x108AC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x108B0] add x16, x9, x15
  [0x108B4] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x108B8] mov x9, x9
  [0x108BC] mov x7, x5
  [0x108C0] mov x6, x12
  [0x108C4] add x9, x9, x15
  [0x108C8] stp x3, x5, [sp, #-0x10]!
  [0x108CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108D4] blr x9 ;; misaligned with debug data
  [0x108D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108E4] mov x0, x0
  [0x108E8] mov x0, x0
  [0x108EC] b #0x108f8
  [0x108F0] mov x0, x14
  [0x108F4] sub x0, x0, x15 ;; misaligned with debug data
  [0x108F8] mov x0, x0
  [0x108FC] b #0x10ea8
  [0x10900] adrp x8, #0x10000
  [0x10904] add x8, x8, #0
  [0x10908] cmp x9, x8
  [0x1090C] b.ne #0x10ea0
  [0x10910] adrp x16, #0x10000
  [0x10914] add x16, x16, #0
  [0x10918] ldr w9, [x16]
  [0x1091C] mov x8, x14
  [0x10920] sub x8, x8, x15 ;; misaligned with debug data
  [0x10924] cmp x9, x8
  [0x10928] b.eq #0x10a8c
  [0x1092C] adrp x16, #0x10000
  [0x10930] add x16, x16, #0
  [0x10934] ldr w7, [x16]
  [0x10938] adrp x16, #0x10000
  [0x1093C] add x16, x16, #0
  [0x10940] ldr w6, [x16]
  [0x10944] adrp x2, #0x10000
  [0x10948] add x2, x2, #0
  [0x1094C] mov x1, x14
  [0x10950] sub x1, x1, x15 ;; misaligned with debug data
  [0x10954] adrp x16, #0x14000
  [0x10958] ldr s23, [x16, #0xf04]
  [0x1095C] movz x9, #0
  [0x10960] add x16, x7, x15
  [0x10964] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x10968] add x16, x8, x15
  [0x1096C] ldr w8, [x16, #0x38] ;; misaligned with debug data
  [0x10970] mov x0, x8
  [0x10974] mov x7, x7
  [0x10978] mov x6, x6
  [0x1097C] mov x2, x2
  [0x10980] mov x1, x1
  [0x10984] fmov w8, s23
  [0x10988] sxtw x8, w8
  [0x1098C] mov x9, x9
  [0x10990] add x0, x0, x15
  [0x10994] stp x3, x5, [sp, #-0x10]!
  [0x10998] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1099C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109A0] blr x0 ;; misaligned with debug data
  [0x109A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x109B0] mov x3, x3
  [0x109B4] adrp x16, #0x10000
  [0x109B8] add x16, x16, #0
  [0x109BC] ldr w7, [x16]
  [0x109C0] adrp x16, #0x10000
  [0x109C4] add x16, x16, #0
  [0x109C8] ldr w6, [x16]
  [0x109CC] adrp x2, #0x10000
  [0x109D0] add x2, x2, #0
  [0x109D4] mov x1, x14
  [0x109D8] sub x1, x1, x15 ;; misaligned with debug data
  [0x109DC] adrp x16, #0x14000
  [0x109E0] ldr s23, [x16, #0xf08]
  [0x109E4] movz x9, #0
  [0x109E8] add x16, x7, x15
  [0x109EC] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x109F0] add x16, x8, x15
  [0x109F4] ldr w8, [x16, #0x38] ;; misaligned with debug data
  [0x109F8] mov x0, x8
  [0x109FC] mov x7, x7
  [0x10A00] mov x6, x6
  [0x10A04] mov x2, x2
  [0x10A08] mov x1, x1
  [0x10A0C] fmov w8, s23
  [0x10A10] sxtw x8, w8
  [0x10A14] mov x9, x9
  [0x10A18] add x0, x0, x15
  [0x10A1C] stp x3, x5, [sp, #-0x10]!
  [0x10A20] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A24] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A28] blr x0 ;; misaligned with debug data
  [0x10A2C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A30] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A34] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A38] mov x3, x3
  [0x10A3C] adrp x16, #0x10000
  [0x10A40] add x16, x16, #0
  [0x10A44] ldr w7, [x16]
  [0x10A48] add x16, x7, x15
  [0x10A4C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10A50] add x16, x9, x15
  [0x10A54] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10A58] mov x9, x9
  [0x10A5C] mov x7, x7
  [0x10A60] add x9, x9, x15
  [0x10A64] stp x3, x5, [sp, #-0x10]!
  [0x10A68] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A6C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A70] blr x9 ;; misaligned with debug data
  [0x10A74] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A78] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A7C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A80] mov x0, x0
  [0x10A84] mov x0, x0
  [0x10A88] b #0x10a94
  [0x10A8C] mov x0, x14
  [0x10A90] sub x0, x0, x15 ;; misaligned with debug data
  [0x10A94] mov x6, sp
  [0x10A98] sub x6, x6, x15
  [0x10A9C] mov x6, x6
  [0x10AA0] add x16, x6, x15
  [0x10AA4] str w13, [x16, #4] ;; misaligned with debug data
  [0x10AA8] movz x9, #0
  [0x10AAC] add x16, x6, x15
  [0x10AB0] str w9, [x16, #8] ;; misaligned with debug data
  [0x10AB4] adrp x9, #0x10000
  [0x10AB8] add x9, x9, #0
  [0x10ABC] add x16, x6, x15
  [0x10AC0] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x10AC4] adrp x16, #0x10000
  [0x10AC8] add x16, x16, #0
  [0x10ACC] ldr w9, [x16]
  [0x10AD0] adrp x16, #0x10000
  [0x10AD4] add x16, x16, #0
  [0x10AD8] ldr w8, [x16]
  [0x10ADC] add x16, x8, x15
  [0x10AE0] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10AE4] ldr x8, [x16] ;; misaligned with debug data
  [0x10AE8] mov x8, x8
  [0x10AEC] mov x8, x8
  [0x10AF0] mov x1, x8
  [0x10AF4] lsl x1, x1, #0x20
  [0x10AF8] lsr x1, x1, #0x20
  [0x10AFC] mov x2, x14
  [0x10B00] sub x2, x2, x15 ;; misaligned with debug data
  [0x10B04] cmp x1, x2
  [0x10B08] b.eq #0x10b54
  [0x10B0C] mov x1, x8
  [0x10B10] lsl x1, x1, #0x20
  [0x10B14] lsr x1, x1, #0x20
  [0x10B18] add x16, x1, x15
  [0x10B1C] ldr w7, [x16] ;; misaligned with debug data
  [0x10B20] mov x7, x7
  [0x10B24] mov x8, x8
  [0x10B28] asr x8, x8, #0x20
  [0x10B2C] add x16, x7, x15
  [0x10B30] ldrsw x1, [x16, #0x24] ;; misaligned with debug data
  [0x10B34] cmp x8, x1
  [0x10B38] b.ne #0x10b44
  [0x10B3C] mov x7, x7
  [0x10B40] b #0x10b4c
  [0x10B44] mov x7, x14
  [0x10B48] sub x7, x7, x15 ;; misaligned with debug data
  [0x10B4C] mov x7, x7
  [0x10B50] b #0x10b5c
  [0x10B54] mov x7, x14
  [0x10B58] sub x7, x7, x15 ;; misaligned with debug data
  [0x10B5C] mov x9, x9
  [0x10B60] mov x7, x7
  [0x10B64] mov x6, x6
  [0x10B68] add x9, x9, x15
  [0x10B6C] stp x3, x5, [sp, #-0x10]!
  [0x10B70] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B74] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B78] blr x9 ;; misaligned with debug data
  [0x10B7C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B80] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10B84] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10B88] mov x0, x0
  [0x10B8C] mov x9, x14
  [0x10B90] sub x9, x9, x15 ;; misaligned with debug data
  [0x10B94] adrp x16, #0x10000
  [0x10B98] add x16, x16, #0
  [0x10B9C] ldr w8, [x16]
  [0x10BA0] add x16, x8, x15
  [0x10BA4] str w9, [x16, #0x10] ;; misaligned with debug data
  [0x10BA8] mov x9, x14
  [0x10BAC] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BB0] adrp x16, #0x10000
  [0x10BB4] add x16, x16, #0
  [0x10BB8] ldr w8, [x16]
  [0x10BBC] add x16, x8, x15
  [0x10BC0] str w9, [x16, #0x1ac] ;; misaligned with debug data
  [0x10BC4] mov x9, x14
  [0x10BC8] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BCC] adrp x16, #0x10000
  [0x10BD0] add x16, x16, #0
  [0x10BD4] str w9, [x16]
  [0x10BD8] adrp x16, #0x10000
  [0x10BDC] add x16, x16, #0
  [0x10BE0] ldr w9, [x16]
  [0x10BE4] movz x7, #0x1e
  [0x10BE8] mov x9, x9
  [0x10BEC] mov x7, x7
  [0x10BF0] add x9, x9, x15
  [0x10BF4] stp x3, x5, [sp, #-0x10]!
  [0x10BF8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10BFC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C00] blr x9 ;; misaligned with debug data
  [0x10C04] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C08] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C0C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C10] mov x3, x3
  [0x10C14] mov x6, sp
  [0x10C18] sub x6, x6, x15
  [0x10C1C] mov x6, x6
  [0x10C20] add x16, x6, x15
  [0x10C24] str w13, [x16, #4] ;; misaligned with debug data
  [0x10C28] movz x9, #0
  [0x10C2C] add x16, x6, x15
  [0x10C30] str w9, [x16, #8] ;; misaligned with debug data
  [0x10C34] adrp x9, #0x10000
  [0x10C38] add x9, x9, #0
  [0x10C3C] add x16, x6, x15
  [0x10C40] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x10C44] adrp x16, #0x10000
  [0x10C48] add x16, x16, #0
  [0x10C4C] ldr w9, [x16]
  [0x10C50] adrp x16, #0x10000
  [0x10C54] add x16, x16, #0
  [0x10C58] ldr w7, [x16]
  [0x10C5C] mov x9, x9
  [0x10C60] mov x7, x7
  [0x10C64] mov x6, x6
  [0x10C68] add x9, x9, x15
  [0x10C6C] stp x3, x5, [sp, #-0x10]!
  [0x10C70] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C74] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C78] blr x9 ;; misaligned with debug data
  [0x10C7C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C80] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C84] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C88] mov x0, x0
  [0x10C8C] adrp x16, #0x10000
  [0x10C90] add x16, x16, #0
  [0x10C94] ldr w7, [x16]
  [0x10C98] adrp x16, #0x10000
  [0x10C9C] add x16, x16, #0
  [0x10CA0] ldr w6, [x16]
  [0x10CA4] movz x2, #0x4000
  [0x10CA8] add x16, x7, x15
  [0x10CAC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10CB0] add x16, x9, x15
  [0x10CB4] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x10CB8] mov x9, x9
  [0x10CBC] mov x7, x7
  [0x10CC0] mov x6, x6
  [0x10CC4] mov x2, x2
  [0x10CC8] add x9, x9, x15
  [0x10CCC] stp x3, x5, [sp, #-0x10]!
  [0x10CD0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CD4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CD8] blr x9 ;; misaligned with debug data
  [0x10CDC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10CE0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10CE4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10CE8] mov x0, x0
  [0x10CEC] mov x3, x0
  [0x10CF0] mov x10, x3
  [0x10CF4] mov x9, x14
  [0x10CF8] sub x9, x9, x15 ;; misaligned with debug data
  [0x10CFC] cmp x10, x9
  [0x10D00] b.eq #0x10e50
  [0x10D04] adrp x16, #0x10000
  [0x10D08] add x16, x16, #0
  [0x10D0C] ldr w9, [x16]
  [0x10D10] add x16, x9, x15
  [0x10D14] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10D18] adrp x16, #0x10000
  [0x10D1C] add x16, x16, #0
  [0x10D20] ldr w6, [x16]
  [0x10D24] adrp x2, #0x10000
  [0x10D28] add x2, x2, #0
  [0x10D2C] movz x1, #0x4000
  [0x10D30] movk x1, #0x7000, lsl #16
  [0x10D34] mov x1, x1
  [0x10D38] mov x9, x9
  [0x10D3C] mov x7, x10
  [0x10D40] mov x6, x6
  [0x10D44] mov x2, x2
  [0x10D48] mov x1, x1
  [0x10D4C] add x9, x9, x15
  [0x10D50] stp x3, x5, [sp, #-0x10]!
  [0x10D54] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D58] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D5C] blr x9 ;; misaligned with debug data
  [0x10D60] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D64] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D68] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D6C] mov x0, x0
  [0x10D70] adrp x16, #0x10000
  [0x10D74] add x16, x16, #0
  [0x10D78] ldr w3, [x16]
  [0x10D7C] mov x3, x3
  [0x10D80] str x3, [sp, #0x50]
  [0x10D84] add x16, x10, x15
  [0x10D88] ldr w9, [x16, #0x28] ;; misaligned with debug data
  [0x10D8C] str x9, [sp, #0x58]
  [0x10D90] adrp x3, #0xf000
  [0x10D94] add x3, x3, #0x924
  [0x10D98] sub x3, x3, x15
  [0x10D9C] add x16, x5, x15
  [0x10DA0] ldr w9, [x16] ;; misaligned with debug data
  [0x10DA4] str x9, [sp, #0x60]
  [0x10DA8] add x16, x5, x15
  [0x10DAC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10DB0] add x16, x9, x15
  [0x10DB4] ldr w9, [x16, #0x54] ;; misaligned with debug data
  [0x10DB8] mov x9, x9
  [0x10DBC] mov x7, x5
  [0x10DC0] add x9, x9, x15
  [0x10DC4] stp x3, x5, [sp, #-0x10]!
  [0x10DC8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DCC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DD0] blr x9 ;; misaligned with debug data
  [0x10DD4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10DD8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10DDC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10DE0] mov x0, x0
  [0x10DE4] ldr x9, [sp, #0x50]
  [0x10DE8] mov x8, x9
  [0x10DEC] str x8, [sp, #0x68]
  [0x10DF0] ldr x7, [sp, #0x58]
  [0x10DF4] mov x7, x7
  [0x10DF8] mov x6, x3
  [0x10DFC] ldr x2, [sp, #0x60]
  [0x10E00] mov x2, x2
  [0x10E04] mov x1, x11
  [0x10E08] mov x8, x0
  [0x10E0C] mov x9, x12
  [0x10E10] ldr x3, [sp, #0x68]
  [0x10E14] add x3, x3, x15
  [0x10E18] stp x3, x5, [sp, #-0x10]!
  [0x10E1C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E20] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E24] blr x3 ;; misaligned with debug data
  [0x10E28] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10E2C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10E30] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10E34] str x3, [sp, #0x68]
  [0x10E38] mov x0, x0
  [0x10E3C] add x16, x10, x15
  [0x10E40] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10E44] mov x9, x9
  [0x10E48] mov x9, x9
  [0x10E4C] b #0x10e58
  [0x10E50] mov x9, x14
  [0x10E54] sub x9, x9, x15 ;; misaligned with debug data
  [0x10E58] adrp x16, #0x10000
  [0x10E5C] add x16, x16, #0
  [0x10E60] ldr w9, [x16]
  [0x10E64] adrp x7, #0x10000
  [0x10E68] add x7, x7, #0
  [0x10E6C] mov x9, x9
  [0x10E70] mov x7, x7
  [0x10E74] add x9, x9, x15
  [0x10E78] stp x3, x5, [sp, #-0x10]!
  [0x10E7C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E80] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E84] blr x9 ;; misaligned with debug data
  [0x10E88] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10E8C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10E90] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10E94] mov x3, x3
  [0x10E98] mov x0, x3
  [0x10E9C] b #0x10ea8
  [0x10EA0] mov x0, x14
  [0x10EA4] sub x0, x0, x15 ;; misaligned with debug data
  [0x10EA8] mov x0, x5
  [0x10EAC] add sp, sp, #0x70
  [0x10EB0] ldp x29, x30, [sp], #0x10
  [0x10EB4] ret


[game-task->string]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x7, x7
  [0x10010] movz x9, #0x74
  [0x10014] cmp x7, x9
  [0x10018] b.ne #0x10030
  [0x1001C] adrp x0, #0x11000
  [0x10020] add x0, x0, #0x4c4
  [0x10024] sub x0, x0, x15
  [0x10028] mov x0, x0
  [0x1002C] b #0x10ec0
  [0x10030] movz x9, #0x73
  [0x10034] cmp x7, x9
  [0x10038] b.ne #0x10050
  [0x1003C] adrp x0, #0x11000
  [0x10040] add x0, x0, #0x4d4
  [0x10044] sub x0, x0, x15
  [0x10048] mov x0, x0
  [0x1004C] b #0x10ec0
  [0x10050] movz x9, #0x72
  [0x10054] cmp x7, x9
  [0x10058] b.ne #0x10070
  [0x1005C] adrp x0, #0x11000
  [0x10060] add x0, x0, #0x4f4
  [0x10064] sub x0, x0, x15
  [0x10068] mov x0, x0
  [0x1006C] b #0x10ec0
  [0x10070] movz x9, #0x71
  [0x10074] cmp x7, x9
  [0x10078] b.ne #0x10090
  [0x1007C] adrp x0, #0x11000
  [0x10080] add x0, x0, #0x514
  [0x10084] sub x0, x0, x15
  [0x10088] mov x0, x0
  [0x1008C] b #0x10ec0
  [0x10090] movz x9, #0x70
  [0x10094] cmp x7, x9
  [0x10098] b.ne #0x100b0
  [0x1009C] adrp x0, #0x11000
  [0x100A0] add x0, x0, #0x534
  [0x100A4] sub x0, x0, x15
  [0x100A8] mov x0, x0
  [0x100AC] b #0x10ec0
  [0x100B0] movz x9, #0x6f
  [0x100B4] cmp x7, x9
  [0x100B8] b.ne #0x100d0
  [0x100BC] adrp x0, #0x11000
  [0x100C0] add x0, x0, #0x554
  [0x100C4] sub x0, x0, x15
  [0x100C8] mov x0, x0
  [0x100CC] b #0x10ec0
  [0x100D0] movz x9, #0x6e
  [0x100D4] cmp x7, x9
  [0x100D8] b.ne #0x100f0
  [0x100DC] adrp x0, #0x11000
  [0x100E0] add x0, x0, #0x574
  [0x100E4] sub x0, x0, x15
  [0x100E8] mov x0, x0
  [0x100EC] b #0x10ec0
  [0x100F0] movz x9, #0x6d
  [0x100F4] cmp x7, x9
  [0x100F8] b.ne #0x10110
  [0x100FC] adrp x0, #0x11000
  [0x10100] add x0, x0, #0x594
  [0x10104] sub x0, x0, x15
  [0x10108] mov x0, x0
  [0x1010C] b #0x10ec0
  [0x10110] movz x9, #0x6c
  [0x10114] cmp x7, x9
  [0x10118] b.ne #0x10130
  [0x1011C] adrp x0, #0x11000
  [0x10120] add x0, x0, #0x5a4
  [0x10124] sub x0, x0, x15
  [0x10128] mov x0, x0
  [0x1012C] b #0x10ec0
  [0x10130] movz x9, #0x6b
  [0x10134] cmp x7, x9
  [0x10138] b.ne #0x10150
  [0x1013C] adrp x0, #0x11000
  [0x10140] add x0, x0, #0x5c4
  [0x10144] sub x0, x0, x15
  [0x10148] mov x0, x0
  [0x1014C] b #0x10ec0
  [0x10150] movz x9, #0x6a
  [0x10154] cmp x7, x9
  [0x10158] b.ne #0x10170
  [0x1015C] adrp x0, #0x11000
  [0x10160] add x0, x0, #0x5e4
  [0x10164] sub x0, x0, x15
  [0x10168] mov x0, x0
  [0x1016C] b #0x10ec0
  [0x10170] movz x9, #0x69
  [0x10174] cmp x7, x9
  [0x10178] b.ne #0x10190
  [0x1017C] adrp x0, #0x11000
  [0x10180] add x0, x0, #0x604
  [0x10184] sub x0, x0, x15
  [0x10188] mov x0, x0
  [0x1018C] b #0x10ec0
  [0x10190] movz x9, #0x68
  [0x10194] cmp x7, x9
  [0x10198] b.ne #0x101b0
  [0x1019C] adrp x0, #0x11000
  [0x101A0] add x0, x0, #0x624
  [0x101A4] sub x0, x0, x15
  [0x101A8] mov x0, x0
  [0x101AC] b #0x10ec0
  [0x101B0] movz x9, #0x67
  [0x101B4] cmp x7, x9
  [0x101B8] b.ne #0x101d0
  [0x101BC] adrp x0, #0x11000
  [0x101C0] add x0, x0, #0x644
  [0x101C4] sub x0, x0, x15
  [0x101C8] mov x0, x0
  [0x101CC] b #0x10ec0
  [0x101D0] movz x9, #0x66
  [0x101D4] cmp x7, x9
  [0x101D8] b.ne #0x101f0
  [0x101DC] adrp x0, #0x11000
  [0x101E0] add x0, x0, #0x664
  [0x101E4] sub x0, x0, x15
  [0x101E8] mov x0, x0
  [0x101EC] b #0x10ec0
  [0x101F0] movz x9, #0x65
  [0x101F4] cmp x7, x9
  [0x101F8] b.ne #0x10210
  [0x101FC] adrp x0, #0x11000
  [0x10200] add x0, x0, #0x684
  [0x10204] sub x0, x0, x15
  [0x10208] mov x0, x0
  [0x1020C] b #0x10ec0
  [0x10210] movz x9, #0x64
  [0x10214] cmp x7, x9
  [0x10218] b.ne #0x10230
  [0x1021C] adrp x0, #0x11000
  [0x10220] add x0, x0, #0x6a4
  [0x10224] sub x0, x0, x15
  [0x10228] mov x0, x0
  [0x1022C] b #0x10ec0
  [0x10230] movz x9, #0x63
  [0x10234] cmp x7, x9
  [0x10238] b.ne #0x10250
  [0x1023C] adrp x0, #0x11000
  [0x10240] add x0, x0, #0x6c4
  [0x10244] sub x0, x0, x15
  [0x10248] mov x0, x0
  [0x1024C] b #0x10ec0
  [0x10250] movz x9, #0x62
  [0x10254] cmp x7, x9
  [0x10258] b.ne #0x10270
  [0x1025C] adrp x0, #0x11000
  [0x10260] add x0, x0, #0x6e4
  [0x10264] sub x0, x0, x15
  [0x10268] mov x0, x0
  [0x1026C] b #0x10ec0
  [0x10270] movz x9, #0x61
  [0x10274] cmp x7, x9
  [0x10278] b.ne #0x10290
  [0x1027C] adrp x0, #0x11000
  [0x10280] add x0, x0, #0x704
  [0x10284] sub x0, x0, x15
  [0x10288] mov x0, x0
  [0x1028C] b #0x10ec0
  [0x10290] movz x9, #0x60
  [0x10294] cmp x7, x9
  [0x10298] b.ne #0x102b0
  [0x1029C] adrp x0, #0x11000
  [0x102A0] add x0, x0, #0x724
  [0x102A4] sub x0, x0, x15
  [0x102A8] mov x0, x0
  [0x102AC] b #0x10ec0
  [0x102B0] movz x9, #0x5f
  [0x102B4] cmp x7, x9
  [0x102B8] b.ne #0x102d0
  [0x102BC] adrp x0, #0x11000
  [0x102C0] add x0, x0, #0x744
  [0x102C4] sub x0, x0, x15
  [0x102C8] mov x0, x0
  [0x102CC] b #0x10ec0
  [0x102D0] movz x9, #0x5e
  [0x102D4] cmp x7, x9
  [0x102D8] b.ne #0x102f0
  [0x102DC] adrp x0, #0x11000
  [0x102E0] add x0, x0, #0x764
  [0x102E4] sub x0, x0, x15
  [0x102E8] mov x0, x0
  [0x102EC] b #0x10ec0
  [0x102F0] movz x9, #0x5d
  [0x102F4] cmp x7, x9
  [0x102F8] b.ne #0x10310
  [0x102FC] adrp x0, #0x11000
  [0x10300] add x0, x0, #0x784
  [0x10304] sub x0, x0, x15
  [0x10308] mov x0, x0
  [0x1030C] b #0x10ec0
  [0x10310] movz x9, #0x5c
  [0x10314] cmp x7, x9
  [0x10318] b.ne #0x10330
  [0x1031C] adrp x0, #0x11000
  [0x10320] add x0, x0, #0x7a4
  [0x10324] sub x0, x0, x15
  [0x10328] mov x0, x0
  [0x1032C] b #0x10ec0
  [0x10330] movz x9, #0x5b
  [0x10334] cmp x7, x9
  [0x10338] b.ne #0x10350
  [0x1033C] adrp x0, #0x11000
  [0x10340] add x0, x0, #0x7c4
  [0x10344] sub x0, x0, x15
  [0x10348] mov x0, x0
  [0x1034C] b #0x10ec0
  [0x10350] movz x9, #0x5a
  [0x10354] cmp x7, x9
  [0x10358] b.ne #0x10370
  [0x1035C] adrp x0, #0x11000
  [0x10360] add x0, x0, #0x7e4
  [0x10364] sub x0, x0, x15
  [0x10368] mov x0, x0
  [0x1036C] b #0x10ec0
  [0x10370] movz x9, #0x59
  [0x10374] cmp x7, x9
  [0x10378] b.ne #0x10390
  [0x1037C] adrp x0, #0x11000
  [0x10380] add x0, x0, #0x804
  [0x10384] sub x0, x0, x15
  [0x10388] mov x0, x0
  [0x1038C] b #0x10ec0
  [0x10390] movz x9, #0x58
  [0x10394] cmp x7, x9
  [0x10398] b.ne #0x103b0
  [0x1039C] adrp x0, #0x11000
  [0x103A0] add x0, x0, #0x824
  [0x103A4] sub x0, x0, x15
  [0x103A8] mov x0, x0
  [0x103AC] b #0x10ec0
  [0x103B0] movz x9, #0x57
  [0x103B4] cmp x7, x9
  [0x103B8] b.ne #0x103d0
  [0x103BC] adrp x0, #0x11000
  [0x103C0] add x0, x0, #0x844
  [0x103C4] sub x0, x0, x15
  [0x103C8] mov x0, x0
  [0x103CC] b #0x10ec0
  [0x103D0] movz x9, #0x56
  [0x103D4] cmp x7, x9
  [0x103D8] b.ne #0x103f0
  [0x103DC] adrp x0, #0x11000
  [0x103E0] add x0, x0, #0x864
  [0x103E4] sub x0, x0, x15
  [0x103E8] mov x0, x0
  [0x103EC] b #0x10ec0
  [0x103F0] movz x9, #0x55
  [0x103F4] cmp x7, x9
  [0x103F8] b.ne #0x10410
  [0x103FC] adrp x0, #0x11000
  [0x10400] add x0, x0, #0x884
  [0x10404] sub x0, x0, x15
  [0x10408] mov x0, x0
  [0x1040C] b #0x10ec0
  [0x10410] movz x9, #0x54
  [0x10414] cmp x7, x9
  [0x10418] b.ne #0x10430
  [0x1041C] adrp x0, #0x11000
  [0x10420] add x0, x0, #0x8a4
  [0x10424] sub x0, x0, x15
  [0x10428] mov x0, x0
  [0x1042C] b #0x10ec0
  [0x10430] movz x9, #0x53
  [0x10434] cmp x7, x9
  [0x10438] b.ne #0x10450
  [0x1043C] adrp x0, #0x11000
  [0x10440] add x0, x0, #0x8c4
  [0x10444] sub x0, x0, x15
  [0x10448] mov x0, x0
  [0x1044C] b #0x10ec0
  [0x10450] movz x9, #0x52
  [0x10454] cmp x7, x9
  [0x10458] b.ne #0x10470
  [0x1045C] adrp x0, #0x11000
  [0x10460] add x0, x0, #0x8e4
  [0x10464] sub x0, x0, x15
  [0x10468] mov x0, x0
  [0x1046C] b #0x10ec0
  [0x10470] movz x9, #0x51
  [0x10474] cmp x7, x9
  [0x10478] b.ne #0x10490
  [0x1047C] adrp x0, #0x11000
  [0x10480] add x0, x0, #0x904
  [0x10484] sub x0, x0, x15
  [0x10488] mov x0, x0
  [0x1048C] b #0x10ec0
  [0x10490] movz x9, #0x50
  [0x10494] cmp x7, x9
  [0x10498] b.ne #0x104b0
  [0x1049C] adrp x0, #0x11000
  [0x104A0] add x0, x0, #0x924
  [0x104A4] sub x0, x0, x15
  [0x104A8] mov x0, x0
  [0x104AC] b #0x10ec0
  [0x104B0] movz x9, #0x4f
  [0x104B4] cmp x7, x9
  [0x104B8] b.ne #0x104d0
  [0x104BC] adrp x0, #0x11000
  [0x104C0] add x0, x0, #0x944
  [0x104C4] sub x0, x0, x15
  [0x104C8] mov x0, x0
  [0x104CC] b #0x10ec0
  [0x104D0] movz x9, #0x4e
  [0x104D4] cmp x7, x9
  [0x104D8] b.ne #0x104f0
  [0x104DC] adrp x0, #0x11000
  [0x104E0] add x0, x0, #0x964
  [0x104E4] sub x0, x0, x15
  [0x104E8] mov x0, x0
  [0x104EC] b #0x10ec0
  [0x104F0] movz x9, #0x4d
  [0x104F4] cmp x7, x9
  [0x104F8] b.ne #0x10510
  [0x104FC] adrp x0, #0x11000
  [0x10500] add x0, x0, #0x984
  [0x10504] sub x0, x0, x15
  [0x10508] mov x0, x0
  [0x1050C] b #0x10ec0
  [0x10510] movz x9, #0x4c
  [0x10514] cmp x7, x9
  [0x10518] b.ne #0x10530
  [0x1051C] adrp x0, #0x11000
  [0x10520] add x0, x0, #0x9a4
  [0x10524] sub x0, x0, x15
  [0x10528] mov x0, x0
  [0x1052C] b #0x10ec0
  [0x10530] movz x9, #0x4b
  [0x10534] cmp x7, x9
  [0x10538] b.ne #0x10550
  [0x1053C] adrp x0, #0x11000
  [0x10540] add x0, x0, #0x9c4
  [0x10544] sub x0, x0, x15
  [0x10548] mov x0, x0
  [0x1054C] b #0x10ec0
  [0x10550] movz x9, #0x4a
  [0x10554] cmp x7, x9
  [0x10558] b.ne #0x10570
  [0x1055C] adrp x0, #0x11000
  [0x10560] add x0, x0, #0x9e4
  [0x10564] sub x0, x0, x15
  [0x10568] mov x0, x0
  [0x1056C] b #0x10ec0
  [0x10570] movz x9, #0x49
  [0x10574] cmp x7, x9
  [0x10578] b.ne #0x10590
  [0x1057C] adrp x0, #0x11000
  [0x10580] add x0, x0, #0xa04
  [0x10584] sub x0, x0, x15
  [0x10588] mov x0, x0
  [0x1058C] b #0x10ec0
  [0x10590] movz x9, #0x48
  [0x10594] cmp x7, x9
  [0x10598] b.ne #0x105b0
  [0x1059C] adrp x0, #0x11000
  [0x105A0] add x0, x0, #0xa24
  [0x105A4] sub x0, x0, x15
  [0x105A8] mov x0, x0
  [0x105AC] b #0x10ec0
  [0x105B0] movz x9, #0x47
  [0x105B4] cmp x7, x9
  [0x105B8] b.ne #0x105d0
  [0x105BC] adrp x0, #0x11000
  [0x105C0] add x0, x0, #0xa44
  [0x105C4] sub x0, x0, x15
  [0x105C8] mov x0, x0
  [0x105CC] b #0x10ec0
  [0x105D0] movz x9, #0x46
  [0x105D4] cmp x7, x9
  [0x105D8] b.ne #0x105f0
  [0x105DC] adrp x0, #0x11000
  [0x105E0] add x0, x0, #0xa64
  [0x105E4] sub x0, x0, x15
  [0x105E8] mov x0, x0
  [0x105EC] b #0x10ec0
  [0x105F0] movz x9, #0x45
  [0x105F4] cmp x7, x9
  [0x105F8] b.ne #0x10610
  [0x105FC] adrp x0, #0x11000
  [0x10600] add x0, x0, #0xa84
  [0x10604] sub x0, x0, x15
  [0x10608] mov x0, x0
  [0x1060C] b #0x10ec0
  [0x10610] movz x9, #0x44
  [0x10614] cmp x7, x9
  [0x10618] b.ne #0x10630
  [0x1061C] adrp x0, #0x11000
  [0x10620] add x0, x0, #0xaa4
  [0x10624] sub x0, x0, x15
  [0x10628] mov x0, x0
  [0x1062C] b #0x10ec0
  [0x10630] movz x9, #0x43
  [0x10634] cmp x7, x9
  [0x10638] b.ne #0x10650
  [0x1063C] adrp x0, #0x11000
  [0x10640] add x0, x0, #0xac4
  [0x10644] sub x0, x0, x15
  [0x10648] mov x0, x0
  [0x1064C] b #0x10ec0
  [0x10650] movz x9, #0x42
  [0x10654] cmp x7, x9
  [0x10658] b.ne #0x10670
  [0x1065C] adrp x0, #0x11000
  [0x10660] add x0, x0, #0xae4
  [0x10664] sub x0, x0, x15
  [0x10668] mov x0, x0
  [0x1066C] b #0x10ec0
  [0x10670] movz x9, #0x41
  [0x10674] cmp x7, x9
  [0x10678] b.ne #0x10690
  [0x1067C] adrp x0, #0x11000
  [0x10680] add x0, x0, #0xb04
  [0x10684] sub x0, x0, x15
  [0x10688] mov x0, x0
  [0x1068C] b #0x10ec0
  [0x10690] movz x9, #0x40
  [0x10694] cmp x7, x9
  [0x10698] b.ne #0x106b0
  [0x1069C] adrp x0, #0x11000
  [0x106A0] add x0, x0, #0xb24
  [0x106A4] sub x0, x0, x15
  [0x106A8] mov x0, x0
  [0x106AC] b #0x10ec0
  [0x106B0] movz x9, #0x3f
  [0x106B4] cmp x7, x9
  [0x106B8] b.ne #0x106d0
  [0x106BC] adrp x0, #0x11000
  [0x106C0] add x0, x0, #0xb44
  [0x106C4] sub x0, x0, x15
  [0x106C8] mov x0, x0
  [0x106CC] b #0x10ec0
  [0x106D0] movz x9, #0x3e
  [0x106D4] cmp x7, x9
  [0x106D8] b.ne #0x106f0
  [0x106DC] adrp x0, #0x11000
  [0x106E0] add x0, x0, #0xb64
  [0x106E4] sub x0, x0, x15
  [0x106E8] mov x0, x0
  [0x106EC] b #0x10ec0
  [0x106F0] movz x9, #0x3d
  [0x106F4] cmp x7, x9
  [0x106F8] b.ne #0x10710
  [0x106FC] adrp x0, #0x11000
  [0x10700] add x0, x0, #0xb84
  [0x10704] sub x0, x0, x15
  [0x10708] mov x0, x0
  [0x1070C] b #0x10ec0
  [0x10710] movz x9, #0x3c
  [0x10714] cmp x7, x9
  [0x10718] b.ne #0x10730
  [0x1071C] adrp x0, #0x11000
  [0x10720] add x0, x0, #0xba4
  [0x10724] sub x0, x0, x15
  [0x10728] mov x0, x0
  [0x1072C] b #0x10ec0
  [0x10730] movz x9, #0x3b
  [0x10734] cmp x7, x9
  [0x10738] b.ne #0x10750
  [0x1073C] adrp x0, #0x11000
  [0x10740] add x0, x0, #0xbc4
  [0x10744] sub x0, x0, x15
  [0x10748] mov x0, x0
  [0x1074C] b #0x10ec0
  [0x10750] movz x9, #0x3a
  [0x10754] cmp x7, x9
  [0x10758] b.ne #0x10770
  [0x1075C] adrp x0, #0x11000
  [0x10760] add x0, x0, #0xbe4
  [0x10764] sub x0, x0, x15
  [0x10768] mov x0, x0
  [0x1076C] b #0x10ec0
  [0x10770] movz x9, #0x39
  [0x10774] cmp x7, x9
  [0x10778] b.ne #0x10790
  [0x1077C] adrp x0, #0x11000
  [0x10780] add x0, x0, #0xc04
  [0x10784] sub x0, x0, x15
  [0x10788] mov x0, x0
  [0x1078C] b #0x10ec0
  [0x10790] movz x9, #0x38
  [0x10794] cmp x7, x9
  [0x10798] b.ne #0x107b0
  [0x1079C] adrp x0, #0x11000
  [0x107A0] add x0, x0, #0xc24
  [0x107A4] sub x0, x0, x15
  [0x107A8] mov x0, x0
  [0x107AC] b #0x10ec0
  [0x107B0] movz x9, #0x37
  [0x107B4] cmp x7, x9
  [0x107B8] b.ne #0x107d0
  [0x107BC] adrp x0, #0x11000
  [0x107C0] add x0, x0, #0xc44
  [0x107C4] sub x0, x0, x15
  [0x107C8] mov x0, x0
  [0x107CC] b #0x10ec0
  [0x107D0] movz x9, #0x36
  [0x107D4] cmp x7, x9
  [0x107D8] b.ne #0x107f0
  [0x107DC] adrp x0, #0x11000
  [0x107E0] add x0, x0, #0xc64
  [0x107E4] sub x0, x0, x15
  [0x107E8] mov x0, x0
  [0x107EC] b #0x10ec0
  [0x107F0] movz x9, #0x35
  [0x107F4] cmp x7, x9
  [0x107F8] b.ne #0x10810
  [0x107FC] adrp x0, #0x11000
  [0x10800] add x0, x0, #0xc84
  [0x10804] sub x0, x0, x15
  [0x10808] mov x0, x0
  [0x1080C] b #0x10ec0
  [0x10810] movz x9, #0x34
  [0x10814] cmp x7, x9
  [0x10818] b.ne #0x10830
  [0x1081C] adrp x0, #0x11000
  [0x10820] add x0, x0, #0xca4
  [0x10824] sub x0, x0, x15
  [0x10828] mov x0, x0
  [0x1082C] b #0x10ec0
  [0x10830] movz x9, #0x33
  [0x10834] cmp x7, x9
  [0x10838] b.ne #0x10850
  [0x1083C] adrp x0, #0x11000
  [0x10840] add x0, x0, #0xcc4
  [0x10844] sub x0, x0, x15
  [0x10848] mov x0, x0
  [0x1084C] b #0x10ec0
  [0x10850] movz x9, #0x32
  [0x10854] cmp x7, x9
  [0x10858] b.ne #0x10870
  [0x1085C] adrp x0, #0x11000
  [0x10860] add x0, x0, #0xce4
  [0x10864] sub x0, x0, x15
  [0x10868] mov x0, x0
  [0x1086C] b #0x10ec0
  [0x10870] movz x9, #0x31
  [0x10874] cmp x7, x9
  [0x10878] b.ne #0x10890
  [0x1087C] adrp x0, #0x11000
  [0x10880] add x0, x0, #0xd04
  [0x10884] sub x0, x0, x15
  [0x10888] mov x0, x0
  [0x1088C] b #0x10ec0
  [0x10890] movz x9, #0x30
  [0x10894] cmp x7, x9
  [0x10898] b.ne #0x108b0
  [0x1089C] adrp x0, #0x11000
  [0x108A0] add x0, x0, #0xd24
  [0x108A4] sub x0, x0, x15
  [0x108A8] mov x0, x0
  [0x108AC] b #0x10ec0
  [0x108B0] movz x9, #0x2f
  [0x108B4] cmp x7, x9
  [0x108B8] b.ne #0x108d0
  [0x108BC] adrp x0, #0x11000
  [0x108C0] add x0, x0, #0xd44
  [0x108C4] sub x0, x0, x15
  [0x108C8] mov x0, x0
  [0x108CC] b #0x10ec0
  [0x108D0] movz x9, #0x2e
  [0x108D4] cmp x7, x9
  [0x108D8] b.ne #0x108f0
  [0x108DC] adrp x0, #0x11000
  [0x108E0] add x0, x0, #0xd64
  [0x108E4] sub x0, x0, x15
  [0x108E8] mov x0, x0
  [0x108EC] b #0x10ec0
  [0x108F0] movz x9, #0x2d
  [0x108F4] cmp x7, x9
  [0x108F8] b.ne #0x10910
  [0x108FC] adrp x0, #0x11000
  [0x10900] add x0, x0, #0xd84
  [0x10904] sub x0, x0, x15
  [0x10908] mov x0, x0
  [0x1090C] b #0x10ec0
  [0x10910] movz x9, #0x2c
  [0x10914] cmp x7, x9
  [0x10918] b.ne #0x10930
  [0x1091C] adrp x0, #0x11000
  [0x10920] add x0, x0, #0xda4
  [0x10924] sub x0, x0, x15
  [0x10928] mov x0, x0
  [0x1092C] b #0x10ec0
  [0x10930] movz x9, #0x2b
  [0x10934] cmp x7, x9
  [0x10938] b.ne #0x10950
  [0x1093C] adrp x0, #0x11000
  [0x10940] add x0, x0, #0xdc4
  [0x10944] sub x0, x0, x15
  [0x10948] mov x0, x0
  [0x1094C] b #0x10ec0
  [0x10950] movz x9, #0x2a
  [0x10954] cmp x7, x9
  [0x10958] b.ne #0x10970
  [0x1095C] adrp x0, #0x11000
  [0x10960] add x0, x0, #0xde4
  [0x10964] sub x0, x0, x15
  [0x10968] mov x0, x0
  [0x1096C] b #0x10ec0
  [0x10970] movz x9, #0x29
  [0x10974] cmp x7, x9
  [0x10978] b.ne #0x10990
  [0x1097C] adrp x0, #0x11000
  [0x10980] add x0, x0, #0xe04
  [0x10984] sub x0, x0, x15
  [0x10988] mov x0, x0
  [0x1098C] b #0x10ec0
  [0x10990] movz x9, #0x28
  [0x10994] cmp x7, x9
  [0x10998] b.ne #0x109b0
  [0x1099C] adrp x0, #0x11000
  [0x109A0] add x0, x0, #0xe24
  [0x109A4] sub x0, x0, x15
  [0x109A8] mov x0, x0
  [0x109AC] b #0x10ec0
  [0x109B0] movz x9, #0x27
  [0x109B4] cmp x7, x9
  [0x109B8] b.ne #0x109d0
  [0x109BC] adrp x0, #0x11000
  [0x109C0] add x0, x0, #0xe44
  [0x109C4] sub x0, x0, x15
  [0x109C8] mov x0, x0
  [0x109CC] b #0x10ec0
  [0x109D0] movz x9, #0x26
  [0x109D4] cmp x7, x9
  [0x109D8] b.ne #0x109f0
  [0x109DC] adrp x0, #0x11000
  [0x109E0] add x0, x0, #0xe64
  [0x109E4] sub x0, x0, x15
  [0x109E8] mov x0, x0
  [0x109EC] b #0x10ec0
  [0x109F0] movz x9, #0x25
  [0x109F4] cmp x7, x9
  [0x109F8] b.ne #0x10a10
  [0x109FC] adrp x0, #0x11000
  [0x10A00] add x0, x0, #0xe84
  [0x10A04] sub x0, x0, x15
  [0x10A08] mov x0, x0
  [0x10A0C] b #0x10ec0
  [0x10A10] movz x9, #0x24
  [0x10A14] cmp x7, x9
  [0x10A18] b.ne #0x10a30
  [0x10A1C] adrp x0, #0x11000
  [0x10A20] add x0, x0, #0xea4
  [0x10A24] sub x0, x0, x15
  [0x10A28] mov x0, x0
  [0x10A2C] b #0x10ec0
  [0x10A30] movz x9, #0x23
  [0x10A34] cmp x7, x9
  [0x10A38] b.ne #0x10a50
  [0x10A3C] adrp x0, #0x11000
  [0x10A40] add x0, x0, #0xec4
  [0x10A44] sub x0, x0, x15
  [0x10A48] mov x0, x0
  [0x10A4C] b #0x10ec0
  [0x10A50] movz x9, #0x22
  [0x10A54] cmp x7, x9
  [0x10A58] b.ne #0x10a70
  [0x10A5C] adrp x0, #0x11000
  [0x10A60] add x0, x0, #0xee4
  [0x10A64] sub x0, x0, x15
  [0x10A68] mov x0, x0
  [0x10A6C] b #0x10ec0
  [0x10A70] movz x9, #0x21
  [0x10A74] cmp x7, x9
  [0x10A78] b.ne #0x10a90
  [0x10A7C] adrp x0, #0x11000
  [0x10A80] add x0, x0, #0xf04
  [0x10A84] sub x0, x0, x15
  [0x10A88] mov x0, x0
  [0x10A8C] b #0x10ec0
  [0x10A90] movz x9, #0x20
  [0x10A94] cmp x7, x9
  [0x10A98] b.ne #0x10ab0
  [0x10A9C] adrp x0, #0x11000
  [0x10AA0] add x0, x0, #0xf24
  [0x10AA4] sub x0, x0, x15
  [0x10AA8] mov x0, x0
  [0x10AAC] b #0x10ec0
  [0x10AB0] movz x9, #0x1f
  [0x10AB4] cmp x7, x9
  [0x10AB8] b.ne #0x10ad0
  [0x10ABC] adrp x0, #0x11000
  [0x10AC0] add x0, x0, #0xf54
  [0x10AC4] sub x0, x0, x15
  [0x10AC8] mov x0, x0
  [0x10ACC] b #0x10ec0
  [0x10AD0] movz x9, #0x1e
  [0x10AD4] cmp x7, x9
  [0x10AD8] b.ne #0x10af0
  [0x10ADC] adrp x0, #0x11000
  [0x10AE0] add x0, x0, #0xf74
  [0x10AE4] sub x0, x0, x15
  [0x10AE8] mov x0, x0
  [0x10AEC] b #0x10ec0
  [0x10AF0] movz x9, #0x1d
  [0x10AF4] cmp x7, x9
  [0x10AF8] b.ne #0x10b10
  [0x10AFC] adrp x0, #0x11000
  [0x10B00] add x0, x0, #0xf94
  [0x10B04] sub x0, x0, x15
  [0x10B08] mov x0, x0
  [0x10B0C] b #0x10ec0
  [0x10B10] movz x9, #0x1c
  [0x10B14] cmp x7, x9
  [0x10B18] b.ne #0x10b30
  [0x10B1C] adrp x0, #0x11000
  [0x10B20] add x0, x0, #0xfb4
  [0x10B24] sub x0, x0, x15
  [0x10B28] mov x0, x0
  [0x10B2C] b #0x10ec0
  [0x10B30] movz x9, #0x1b
  [0x10B34] cmp x7, x9
  [0x10B38] b.ne #0x10b50
  [0x10B3C] adrp x0, #0x11000
  [0x10B40] add x0, x0, #0xfd4
  [0x10B44] sub x0, x0, x15
  [0x10B48] mov x0, x0
  [0x10B4C] b #0x10ec0
  [0x10B50] movz x9, #0x1a
  [0x10B54] cmp x7, x9
  [0x10B58] b.ne #0x10b70
  [0x10B5C] adrp x0, #0x11000
  [0x10B60] add x0, x0, #0xff4
  [0x10B64] sub x0, x0, x15
  [0x10B68] mov x0, x0
  [0x10B6C] b #0x10ec0
  [0x10B70] movz x9, #0x19
  [0x10B74] cmp x7, x9
  [0x10B78] b.ne #0x10b90
  [0x10B7C] adrp x0, #0x11000
  [0x10B80] add x0, x0, #0x14
  [0x10B84] sub x0, x0, x15
  [0x10B88] mov x0, x0
  [0x10B8C] b #0x10ec0
  [0x10B90] movz x9, #0x18
  [0x10B94] cmp x7, x9
  [0x10B98] b.ne #0x10bb0
  [0x10B9C] adrp x0, #0x11000
  [0x10BA0] add x0, x0, #0x34
  [0x10BA4] sub x0, x0, x15
  [0x10BA8] mov x0, x0
  [0x10BAC] b #0x10ec0
  [0x10BB0] movz x9, #0x17
  [0x10BB4] cmp x7, x9
  [0x10BB8] b.ne #0x10bd0
  [0x10BBC] adrp x0, #0x11000
  [0x10BC0] add x0, x0, #0x54
  [0x10BC4] sub x0, x0, x15
  [0x10BC8] mov x0, x0
  [0x10BCC] b #0x10ec0
  [0x10BD0] movz x9, #0x16
  [0x10BD4] cmp x7, x9
  [0x10BD8] b.ne #0x10bf0
  [0x10BDC] adrp x0, #0x11000
  [0x10BE0] add x0, x0, #0x74
  [0x10BE4] sub x0, x0, x15
  [0x10BE8] mov x0, x0
  [0x10BEC] b #0x10ec0
  [0x10BF0] movz x9, #0x15
  [0x10BF4] cmp x7, x9
  [0x10BF8] b.ne #0x10c10
  [0x10BFC] adrp x0, #0x11000
  [0x10C00] add x0, x0, #0x94
  [0x10C04] sub x0, x0, x15
  [0x10C08] mov x0, x0
  [0x10C0C] b #0x10ec0
  [0x10C10] movz x9, #0x14
  [0x10C14] cmp x7, x9
  [0x10C18] b.ne #0x10c30
  [0x10C1C] adrp x0, #0x11000
  [0x10C20] add x0, x0, #0xb4
  [0x10C24] sub x0, x0, x15
  [0x10C28] mov x0, x0
  [0x10C2C] b #0x10ec0
  [0x10C30] movz x9, #0x13
  [0x10C34] cmp x7, x9
  [0x10C38] b.ne #0x10c50
  [0x10C3C] adrp x0, #0x11000
  [0x10C40] add x0, x0, #0xd4
  [0x10C44] sub x0, x0, x15
  [0x10C48] mov x0, x0
  [0x10C4C] b #0x10ec0
  [0x10C50] movz x9, #0x12
  [0x10C54] cmp x7, x9
  [0x10C58] b.ne #0x10c70
  [0x10C5C] adrp x0, #0x11000
  [0x10C60] add x0, x0, #0xf4
  [0x10C64] sub x0, x0, x15
  [0x10C68] mov x0, x0
  [0x10C6C] b #0x10ec0
  [0x10C70] movz x9, #0x11
  [0x10C74] cmp x7, x9
  [0x10C78] b.ne #0x10c90
  [0x10C7C] adrp x0, #0x11000
  [0x10C80] add x0, x0, #0x114
  [0x10C84] sub x0, x0, x15
  [0x10C88] mov x0, x0
  [0x10C8C] b #0x10ec0
  [0x10C90] movz x9, #0x10
  [0x10C94] cmp x7, x9
  [0x10C98] b.ne #0x10cb0
  [0x10C9C] adrp x0, #0x11000
  [0x10CA0] add x0, x0, #0x134
  [0x10CA4] sub x0, x0, x15
  [0x10CA8] mov x0, x0
  [0x10CAC] b #0x10ec0
  [0x10CB0] movz x9, #0xf
  [0x10CB4] cmp x7, x9
  [0x10CB8] b.ne #0x10cd0
  [0x10CBC] adrp x0, #0x11000
  [0x10CC0] add x0, x0, #0x154
  [0x10CC4] sub x0, x0, x15
  [0x10CC8] mov x0, x0
  [0x10CCC] b #0x10ec0
  [0x10CD0] movz x9, #0xe
  [0x10CD4] cmp x7, x9
  [0x10CD8] b.ne #0x10cf0
  [0x10CDC] adrp x0, #0x11000
  [0x10CE0] add x0, x0, #0x174
  [0x10CE4] sub x0, x0, x15
  [0x10CE8] mov x0, x0
  [0x10CEC] b #0x10ec0
  [0x10CF0] movz x9, #0xd
  [0x10CF4] cmp x7, x9
  [0x10CF8] b.ne #0x10d10
  [0x10CFC] adrp x0, #0x11000
  [0x10D00] add x0, x0, #0x194
  [0x10D04] sub x0, x0, x15
  [0x10D08] mov x0, x0
  [0x10D0C] b #0x10ec0
  [0x10D10] movz x9, #0xc
  [0x10D14] cmp x7, x9
  [0x10D18] b.ne #0x10d30
  [0x10D1C] adrp x0, #0x11000
  [0x10D20] add x0, x0, #0x1b4
  [0x10D24] sub x0, x0, x15
  [0x10D28] mov x0, x0
  [0x10D2C] b #0x10ec0
  [0x10D30] movz x9, #0xb
  [0x10D34] cmp x7, x9
  [0x10D38] b.ne #0x10d50
  [0x10D3C] adrp x0, #0x11000
  [0x10D40] add x0, x0, #0x1d4
  [0x10D44] sub x0, x0, x15
  [0x10D48] mov x0, x0
  [0x10D4C] b #0x10ec0
  [0x10D50] movz x9, #0xa
  [0x10D54] cmp x7, x9
  [0x10D58] b.ne #0x10d70
  [0x10D5C] adrp x0, #0x11000
  [0x10D60] add x0, x0, #0x1f4
  [0x10D64] sub x0, x0, x15
  [0x10D68] mov x0, x0
  [0x10D6C] b #0x10ec0
  [0x10D70] movz x9, #0x9
  [0x10D74] cmp x7, x9
  [0x10D78] b.ne #0x10d90
  [0x10D7C] adrp x0, #0x11000
  [0x10D80] add x0, x0, #0x214
  [0x10D84] sub x0, x0, x15
  [0x10D88] mov x0, x0
  [0x10D8C] b #0x10ec0
  [0x10D90] movz x9, #0x8
  [0x10D94] cmp x7, x9
  [0x10D98] b.ne #0x10db0
  [0x10D9C] adrp x0, #0x11000
  [0x10DA0] add x0, x0, #0x234
  [0x10DA4] sub x0, x0, x15
  [0x10DA8] mov x0, x0
  [0x10DAC] b #0x10ec0
  [0x10DB0] movz x9, #0x7
  [0x10DB4] cmp x7, x9
  [0x10DB8] b.ne #0x10dd0
  [0x10DBC] adrp x0, #0x11000
  [0x10DC0] add x0, x0, #0x254
  [0x10DC4] sub x0, x0, x15
  [0x10DC8] mov x0, x0
  [0x10DCC] b #0x10ec0
  [0x10DD0] movz x9, #0x6
  [0x10DD4] cmp x7, x9
  [0x10DD8] b.ne #0x10df0
  [0x10DDC] adrp x0, #0x11000
  [0x10DE0] add x0, x0, #0x274
  [0x10DE4] sub x0, x0, x15
  [0x10DE8] mov x0, x0
  [0x10DEC] b #0x10ec0
  [0x10DF0] movz x9, #0x5
  [0x10DF4] cmp x7, x9
  [0x10DF8] b.ne #0x10e10
  [0x10DFC] adrp x0, #0x11000
  [0x10E00] add x0, x0, #0x294
  [0x10E04] sub x0, x0, x15
  [0x10E08] mov x0, x0
  [0x10E0C] b #0x10ec0
  [0x10E10] movz x9, #0x4
  [0x10E14] cmp x7, x9
  [0x10E18] b.ne #0x10e30
  [0x10E1C] adrp x0, #0x11000
  [0x10E20] add x0, x0, #0x2b4
  [0x10E24] sub x0, x0, x15
  [0x10E28] mov x0, x0
  [0x10E2C] b #0x10ec0
  [0x10E30] movz x9, #0x3
  [0x10E34] cmp x7, x9
  [0x10E38] b.ne #0x10e50
  [0x10E3C] adrp x0, #0x11000
  [0x10E40] add x0, x0, #0x2d4
  [0x10E44] sub x0, x0, x15
  [0x10E48] mov x0, x0
  [0x10E4C] b #0x10ec0
  [0x10E50] movz x9, #0x2
  [0x10E54] cmp x7, x9
  [0x10E58] b.ne #0x10e70
  [0x10E5C] adrp x0, #0x11000
  [0x10E60] add x0, x0, #0x2f4
  [0x10E64] sub x0, x0, x15
  [0x10E68] mov x0, x0
  [0x10E6C] b #0x10ec0
  [0x10E70] movz x9, #0x1
  [0x10E74] cmp x7, x9
  [0x10E78] b.ne #0x10e90
  [0x10E7C] adrp x0, #0x11000
  [0x10E80] add x0, x0, #0x314
  [0x10E84] sub x0, x0, x15
  [0x10E88] mov x0, x0
  [0x10E8C] b #0x10ec0
  [0x10E90] movz x9, #0
  [0x10E94] cmp x7, x9
  [0x10E98] b.ne #0x10eb0
  [0x10E9C] adrp x0, #0x11000
  [0x10EA0] add x0, x0, #0x334
  [0x10EA4] sub x0, x0, x15
  [0x10EA8] mov x0, x0
  [0x10EAC] b #0x10ec0
  [0x10EB0] adrp x0, #0x11000
  [0x10EB4] add x0, x0, #0x344
  [0x10EB8] sub x0, x0, x15
  [0x10EBC] mov x0, x0
  [0x10EC0] mov x0, x0
  [0x10EC4] ldp x29, x30, [sp], #0x10
  [0x10EC8] ret


[(method get-entity-task-perm game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x6, x6
  [0x10014] lsl x6, x6, #4
  [0x10018] mov x6, x6
  [0x1001C] movz x9, #0xc
  [0x10020] add x16, x7, x15
  [0x10024] ldr w8, [x16, #0x64] ;; misaligned with debug data
  [0x10028] add x9, x9, x8
  [0x1002C] add x6, x6, x9
  [0x10030] mov x0, x6
  [0x10034] ldp x29, x30, [sp], #0x10
  [0x10038] ret


[(method set-continue! game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x6, x6
  [0x10014] add x16, x5, x15
  [0x10018] ldr w3, [x16, #0x68] ;; misaligned with debug data
  [0x1001C] mov x12, x3
  [0x10020] sub x9, x14, #0xa
  [0x10024] sub x9, x9, x15 ;; misaligned with debug data
  [0x10028] cmp x6, x9
  [0x1002C] b.ne #0x10044
  [0x10030] mov x9, x14
  [0x10034] sub x9, x9, x15 ;; misaligned with debug data
  [0x10038] mov x6, x9
  [0x1003C] mov x9, x9
  [0x10040] b #0x1004c
  [0x10044] mov x9, x14
  [0x10048] sub x9, x9, x15 ;; misaligned with debug data
  [0x1004C] add x16, x6, x15
  [0x10050] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10054] mov x9, x9
  [0x10058] adrp x16, #0x10000
  [0x1005C] add x16, x16, #0
  [0x10060] ldr w8, [x16]
  [0x10064] cmp x9, x8
  [0x10068] b.ne #0x100e4
  [0x1006C] mov x6, x6
  [0x10070] add x16, x5, x15
  [0x10074] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10078] add x16, x9, x15
  [0x1007C] ldr w9, [x16, #0x58] ;; misaligned with debug data
  [0x10080] mov x9, x9
  [0x10084] mov x7, x5
  [0x10088] mov x6, x6
  [0x1008C] add x9, x9, x15
  [0x10090] stp x3, x5, [sp, #-0x10]!
  [0x10094] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10098] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1009C] blr x9 ;; misaligned with debug data
  [0x100A0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100A4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100A8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100AC] mov x0, x0
  [0x100B0] mov x0, x0
  [0x100B4] mov x9, x14
  [0x100B8] sub x9, x9, x15 ;; misaligned with debug data
  [0x100BC] cmp x0, x9
  [0x100C0] b.eq #0x100d4
  [0x100C4] add x16, x5, x15
  [0x100C8] str w0, [x16, #0x68] ;; misaligned with debug data
  [0x100CC] mov x0, x0
  [0x100D0] b #0x100dc
  [0x100D4] mov x0, x14
  [0x100D8] sub x0, x0, x15 ;; misaligned with debug data
  [0x100DC] mov x0, x0
  [0x100E0] b #0x10254
  [0x100E4] adrp x16, #0x10000
  [0x100E8] add x16, x16, #0
  [0x100EC] ldr w8, [x16]
  [0x100F0] cmp x9, x8
  [0x100F4] b.ne #0x1010c
  [0x100F8] mov x6, x6
  [0x100FC] add x16, x5, x15
  [0x10100] str w6, [x16, #0x68] ;; misaligned with debug data
  [0x10104] mov x0, x6
  [0x10108] b #0x10254
  [0x1010C] adrp x16, #0x10000
  [0x10110] add x16, x16, #0
  [0x10114] ldr w3, [x16]
  [0x10118] mov x3, x3
  [0x1011C] adrp x16, #0x10000
  [0x10120] add x16, x16, #0
  [0x10124] ldr w9, [x16]
  [0x10128] movz x7, #0xc
  [0x1012C] add x7, x7, x3
  [0x10130] adrp x16, #0x15000
  [0x10134] ldr s23, [x16, #0xe94]
  [0x10138] adrp x16, #0x15000
  [0x1013C] ldr s22, [x16, #0xe98]
  [0x10140] mov x9, x9
  [0x10144] mov x7, x7
  [0x10148] fmov w6, s23
  [0x1014C] sxtw x6, w6
  [0x10150] fmov w2, s22
  [0x10154] sxtw x2, w2
  [0x10158] add x9, x9, x15
  [0x1015C] stp x3, x5, [sp, #-0x10]!
  [0x10160] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10164] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10168] blr x9 ;; misaligned with debug data
  [0x1016C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10170] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10174] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10178] mov x0, x0
  [0x1017C] adrp x16, #0x10000
  [0x10180] add x16, x16, #0
  [0x10184] ldr w9, [x16]
  [0x10188] movz x7, #0x1c
  [0x1018C] add x7, x7, x3
  [0x10190] mov x9, x9
  [0x10194] mov x7, x7
  [0x10198] add x9, x9, x15
  [0x1019C] stp x3, x5, [sp, #-0x10]!
  [0x101A0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A8] blr x9 ;; misaligned with debug data
  [0x101AC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101B0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101B4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101B8] mov x0, x0
  [0x101BC] adrp x16, #0x10000
  [0x101C0] add x16, x16, #0
  [0x101C4] ldr w9, [x16]
  [0x101C8] add x16, x9, x15
  [0x101CC] ldr w9, [x16, #0x20] ;; misaligned with debug data
  [0x101D0] add x16, x3, x15
  [0x101D4] str w9, [x16, #0x64] ;; misaligned with debug data
  [0x101D8] adrp x16, #0x10000
  [0x101DC] add x16, x16, #0
  [0x101E0] ldr w9, [x16]
  [0x101E4] add x16, x9, x15
  [0x101E8] ldr w9, [x16] ;; misaligned with debug data
  [0x101EC] add x16, x3, x15
  [0x101F0] str w9, [x16, #0x68] ;; misaligned with debug data
  [0x101F4] adrp x16, #0x10000
  [0x101F8] add x16, x16, #0
  [0x101FC] ldr w9, [x16]
  [0x10200] add x16, x9, x15
  [0x10204] ldr w9, [x16, #4] ;; misaligned with debug data
  [0x10208] add x16, x3, x15
  [0x1020C] str w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10210] adrp x16, #0x10000
  [0x10214] add x16, x16, #0
  [0x10218] ldr w9, [x16]
  [0x1021C] add x16, x9, x15
  [0x10220] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10224] add x16, x3, x15
  [0x10228] str w9, [x16, #0x70] ;; misaligned with debug data
  [0x1022C] adrp x16, #0x10000
  [0x10230] add x16, x16, #0
  [0x10234] ldr w9, [x16]
  [0x10238] add x16, x9, x15
  [0x1023C] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10240] add x16, x3, x15
  [0x10244] str w9, [x16, #0x74] ;; misaligned with debug data
  [0x10248] add x16, x5, x15
  [0x1024C] str w3, [x16, #0x68] ;; misaligned with debug data
  [0x10250] mov x0, x3
  [0x10254] add x16, x5, x15
  [0x10258] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x1025C] cmp x12, x9
  [0x10260] b.eq #0x10298
  [0x10264] movz x9, #0
  [0x10268] add x16, x5, x15
  [0x1026C] str w9, [x16, #0x9c] ;; misaligned with debug data
  [0x10270] adrp x16, #0x10000
  [0x10274] add x16, x16, #0
  [0x10278] ldr w9, [x16]
  [0x1027C] add x16, x9, x15
  [0x10280] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10284] ldr x9, [x16] ;; misaligned with debug data
  [0x10288] add x16, x5, x15
  [0x1028C] stur x9, [x16, #0xac] ;; misaligned with debug data
  [0x10290] mov x9, x9
  [0x10294] b #0x102a0
  [0x10298] mov x9, x14
  [0x1029C] sub x9, x9, x15 ;; misaligned with debug data
  [0x102A0] add x16, x5, x15
  [0x102A4] ldr w0, [x16, #0x68] ;; misaligned with debug data
  [0x102A8] mov x0, x0
  [0x102AC] add sp, sp, #0x10
  [0x102B0] ldp x29, x30, [sp], #0x10
  [0x102B4] ret


[(method mark-text-as-seen game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] mov x9, x6
  [0x10018] movz x8, #0xfff
  [0x1001C] mov x8, x8
  [0x10020] mov x1, x14
  [0x10024] sub x1, x1, x15 ;; misaligned with debug data
  [0x10028] cmp x9, x8
  [0x1002C] b.hs #0x1003c
  [0x10030] add x1, x14, #8
  [0x10034] sub x1, x1, x15 ;; misaligned with debug data
  [0x10038] mov x1, x1
  [0x1003C] mov x9, x1
  [0x10040] mov x8, x14
  [0x10044] sub x8, x8, x15 ;; misaligned with debug data
  [0x10048] cmp x9, x8
  [0x1004C] b.eq #0x10078
  [0x10050] mov x9, x6
  [0x10054] movz x8, #0
  [0x10058] mov x1, x14
  [0x1005C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10060] cmp x9, x8
  [0x10064] b.ls #0x10074
  [0x10068] add x1, x14, #8
  [0x1006C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10070] mov x1, x1
  [0x10074] mov x9, x1
  [0x10078] mov x8, x14
  [0x1007C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10080] cmp x9, x8
  [0x10084] b.eq #0x100dc
  [0x10088] add x16, x7, x15
  [0x1008C] ldr w7, [x16, #0x6c] ;; misaligned with debug data
  [0x10090] mov x6, x6
  [0x10094] add x16, x7, x15
  [0x10098] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1009C] add x16, x9, x15
  [0x100A0] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x100A4] mov x9, x9
  [0x100A8] mov x7, x7
  [0x100AC] mov x6, x6
  [0x100B0] add x9, x9, x15
  [0x100B4] stp x3, x5, [sp, #-0x10]!
  [0x100B8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100BC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C0] blr x9 ;; misaligned with debug data
  [0x100C4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100C8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100CC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100D0] mov x0, x0
  [0x100D4] mov x0, x0
  [0x100D8] b #0x100e4
  [0x100DC] mov x0, x14
  [0x100E0] sub x0, x0, x15 ;; misaligned with debug data
  [0x100E4] add sp, sp, #0x10
  [0x100E8] ldp x29, x30, [sp], #0x10
  [0x100EC] ret


[(method get-continue-by-name game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x5, x6
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] ldr w3, [x16]
  [0x10020] mov x12, x3
  [0x10024] b #0x100fc
  [0x10028] add x16, x12, x15
  [0x1002C] ldursw x9, [x16, #-2] ;; misaligned with debug data
  [0x10030] mov x9, x9
  [0x10034] add x16, x9, x15
  [0x10038] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1003C] mov x9, x9
  [0x10040] add x16, x9, x15
  [0x10044] ldr w3, [x16, #0x34] ;; misaligned with debug data
  [0x10048] mov x11, x3
  [0x1004C] b #0x100d8
  [0x10050] add x16, x11, x15
  [0x10054] ldursw x3, [x16, #-2] ;; misaligned with debug data
  [0x10058] mov x3, x3
  [0x1005C] adrp x16, #0x10000
  [0x10060] add x16, x16, #0
  [0x10064] ldr w9, [x16]
  [0x10068] mov x8, x3
  [0x1006C] add x16, x8, x15
  [0x10070] ldr w6, [x16] ;; misaligned with debug data
  [0x10074] mov x9, x9
  [0x10078] mov x7, x5
  [0x1007C] mov x6, x6
  [0x10080] add x9, x9, x15
  [0x10084] stp x3, x5, [sp, #-0x10]!
  [0x10088] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1008C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10090] blr x9 ;; misaligned with debug data
  [0x10094] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10098] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1009C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100A0] mov x0, x0
  [0x100A4] mov x9, x14
  [0x100A8] sub x9, x9, x15 ;; misaligned with debug data
  [0x100AC] cmp x0, x9
  [0x100B0] b.eq #0x100c4
  [0x100B4] mov x3, x3
  [0x100B8] mov x0, x3
  [0x100BC] b #0x10124
  [0x100C0] b #0x100cc
  [0x100C4] mov x9, x14
  [0x100C8] sub x9, x9, x15 ;; misaligned with debug data
  [0x100CC] add x16, x11, x15
  [0x100D0] ldursw x3, [x16, #2] ;; misaligned with debug data
  [0x100D4] mov x11, x3
  [0x100D8] sub x9, x14, #0xa
  [0x100DC] sub x9, x9, x15 ;; misaligned with debug data
  [0x100E0] cmp x11, x9
  [0x100E4] b.ne #0x10050
  [0x100E8] mov x9, x14
  [0x100EC] sub x9, x9, x15 ;; misaligned with debug data
  [0x100F0] add x16, x12, x15
  [0x100F4] ldursw x3, [x16, #2] ;; misaligned with debug data
  [0x100F8] mov x12, x3
  [0x100FC] sub x9, x14, #0xa
  [0x10100] sub x9, x9, x15 ;; misaligned with debug data
  [0x10104] cmp x12, x9
  [0x10108] b.ne #0x10028
  [0x1010C] mov x9, x14
  [0x10110] sub x9, x9, x15 ;; misaligned with debug data
  [0x10114] mov x0, x14
  [0x10118] sub x0, x0, x15 ;; misaligned with debug data
  [0x1011C] mov x0, x0
  [0x10120] mov x0, x0
  [0x10124] add sp, sp, #0x10
  [0x10128] ldp x29, x30, [sp], #0x10
  [0x1012C] ret


[trsq->continue-point]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w7, [x16]
  [0x1001C] add x16, x7, x15
  [0x10020] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10024] add x16, x9, x15
  [0x10028] ldr w9, [x16, #0x54] ;; misaligned with debug data
  [0x1002C] mov x9, x9
  [0x10030] mov x7, x7
  [0x10034] add x9, x9, x15
  [0x10038] stp x3, x5, [sp, #-0x10]!
  [0x1003C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10040] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10044] blr x9 ;; misaligned with debug data
  [0x10048] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1004C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10050] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10054] mov x0, x0
  [0x10058] mov x0, x0
  [0x1005C] adrp x16, #0x10000
  [0x10060] add x16, x16, #0
  [0x10064] ldr w9, [x16]
  [0x10068] add x7, x14, #8
  [0x1006C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10070] adrp x6, #0x11000
  [0x10074] add x6, x6, #0x364
  [0x10078] sub x6, x6, x15
  [0x1007C] movz x8, #0
  [0x10080] movk x8, #0x2, lsl #16
  [0x10084] mov x8, x8
  [0x10088] add x16, x0, x15
  [0x1008C] ldr w1, [x16] ;; misaligned with debug data
  [0x10090] mov x1, x1
  [0x10094] add x8, x8, x1
  [0x10098] mov x8, x8
  [0x1009C] add x16, x8, x15
  [0x100A0] ldr w2, [x16] ;; misaligned with debug data
  [0x100A4] mov x9, x9
  [0x100A8] mov x7, x7
  [0x100AC] mov x6, x6
  [0x100B0] mov x2, x2
  [0x100B4] add x9, x9, x15
  [0x100B8] stp x3, x5, [sp, #-0x10]!
  [0x100BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C4] blr x9 ;; misaligned with debug data
  [0x100C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] mov x0, x0
  [0x100D8] adrp x16, #0x10000
  [0x100DC] add x16, x16, #0
  [0x100E0] ldr w9, [x16]
  [0x100E4] add x7, x14, #8
  [0x100E8] sub x7, x7, x15 ;; misaligned with debug data
  [0x100EC] adrp x6, #0x11000
  [0x100F0] add x6, x6, #0x394
  [0x100F4] sub x6, x6, x15
  [0x100F8] add x16, x3, x15
  [0x100FC] ldr s23, [x16, #0xc] ;; misaligned with debug data
  [0x10100] add x16, x3, x15
  [0x10104] ldr s22, [x16, #0x10] ;; misaligned with debug data
  [0x10108] add x16, x3, x15
  [0x1010C] ldr s21, [x16, #0x14] ;; misaligned with debug data
  [0x10110] mov x9, x9
  [0x10114] mov x7, x7
  [0x10118] mov x6, x6
  [0x1011C] fmov w2, s23
  [0x10120] sxtw x2, w2
  [0x10124] fmov w1, s22
  [0x10128] sxtw x1, w1
  [0x1012C] fmov w8, s21
  [0x10130] sxtw x8, w8
  [0x10134] add x9, x9, x15
  [0x10138] stp x3, x5, [sp, #-0x10]!
  [0x1013C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10140] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10144] blr x9 ;; misaligned with debug data
  [0x10148] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1014C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10150] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10154] mov x0, x0
  [0x10158] adrp x16, #0x10000
  [0x1015C] add x16, x16, #0
  [0x10160] ldr w9, [x16]
  [0x10164] add x7, x14, #8
  [0x10168] sub x7, x7, x15 ;; misaligned with debug data
  [0x1016C] adrp x6, #0x11000
  [0x10170] add x6, x6, #0x3d4
  [0x10174] sub x6, x6, x15
  [0x10178] add x16, x3, x15
  [0x1017C] ldr s23, [x16, #0x1c] ;; misaligned with debug data
  [0x10180] add x16, x3, x15
  [0x10184] ldr s22, [x16, #0x20] ;; misaligned with debug data
  [0x10188] add x16, x3, x15
  [0x1018C] ldr s21, [x16, #0x24] ;; misaligned with debug data
  [0x10190] add x16, x3, x15
  [0x10194] ldr s20, [x16, #0x28] ;; misaligned with debug data
  [0x10198] mov x3, x9
  [0x1019C] mov x7, x7
  [0x101A0] mov x6, x6
  [0x101A4] fmov w2, s23
  [0x101A8] sxtw x2, w2
  [0x101AC] fmov w1, s22
  [0x101B0] sxtw x1, w1
  [0x101B4] fmov w8, s21
  [0x101B8] sxtw x8, w8
  [0x101BC] fmov w9, s20
  [0x101C0] sxtw x9, w9
  [0x101C4] add x3, x3, x15
  [0x101C8] stp x3, x5, [sp, #-0x10]!
  [0x101CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101D4] blr x3 ;; misaligned with debug data
  [0x101D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101E4] mov x0, x0
  [0x101E8] adrp x16, #0x10000
  [0x101EC] add x16, x16, #0
  [0x101F0] ldr w3, [x16]
  [0x101F4] mov x3, x3
  [0x101F8] adrp x16, #0x10000
  [0x101FC] add x16, x16, #0
  [0x10200] ldr w9, [x16]
  [0x10204] add x7, x14, #8
  [0x10208] sub x7, x7, x15 ;; misaligned with debug data
  [0x1020C] adrp x6, #0x11000
  [0x10210] add x6, x6, #0x3f4
  [0x10214] sub x6, x6, x15
  [0x10218] add x16, x3, x15
  [0x1021C] ldr s23, [x16, #0x34c] ;; misaligned with debug data
  [0x10220] add x16, x3, x15
  [0x10224] ldr s22, [x16, #0x350] ;; misaligned with debug data
  [0x10228] add x16, x3, x15
  [0x1022C] ldr s21, [x16, #0x354] ;; misaligned with debug data
  [0x10230] add x16, x3, x15
  [0x10234] ldr s20, [x16, #0x1ac] ;; misaligned with debug data
  [0x10238] add x16, x3, x15
  [0x1023C] ldr s19, [x16, #0x1b0] ;; misaligned with debug data
  [0x10240] add x16, x3, x15
  [0x10244] ldr s18, [x16, #0x1b4] ;; misaligned with debug data
  [0x10248] mov x5, x9
  [0x1024C] mov x7, x7
  [0x10250] mov x6, x6
  [0x10254] fmov w2, s23
  [0x10258] sxtw x2, w2
  [0x1025C] fmov w1, s22
  [0x10260] sxtw x1, w1
  [0x10264] fmov w8, s21
  [0x10268] sxtw x8, w8
  [0x1026C] fmov w9, s20
  [0x10270] sxtw x9, w9
  [0x10274] fmov w10, s19
  [0x10278] sxtw x10, w10
  [0x1027C] fmov w11, s18
  [0x10280] sxtw x11, w11
  [0x10284] add x5, x5, x15
  [0x10288] stp x3, x5, [sp, #-0x10]!
  [0x1028C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10290] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10294] blr x5 ;; misaligned with debug data
  [0x10298] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1029C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102A4] mov x0, x0
  [0x102A8] adrp x16, #0x10000
  [0x102AC] add x16, x16, #0
  [0x102B0] ldr w9, [x16]
  [0x102B4] add x7, x14, #8
  [0x102B8] sub x7, x7, x15 ;; misaligned with debug data
  [0x102BC] adrp x6, #0x11000
  [0x102C0] add x6, x6, #0x434
  [0x102C4] sub x6, x6, x15
  [0x102C8] add x16, x3, x15
  [0x102CC] ldr s23, [x16, #0x1bc] ;; misaligned with debug data
  [0x102D0] add x16, x3, x15
  [0x102D4] ldr s22, [x16, #0x1c0] ;; misaligned with debug data
  [0x102D8] add x16, x3, x15
  [0x102DC] ldr s21, [x16, #0x1c4] ;; misaligned with debug data
  [0x102E0] add x16, x3, x15
  [0x102E4] ldr s20, [x16, #0x1cc] ;; misaligned with debug data
  [0x102E8] add x16, x3, x15
  [0x102EC] ldr s19, [x16, #0x1d0] ;; misaligned with debug data
  [0x102F0] add x16, x3, x15
  [0x102F4] ldr s18, [x16, #0x1d4] ;; misaligned with debug data
  [0x102F8] mov x3, x9
  [0x102FC] mov x7, x7
  [0x10300] mov x6, x6
  [0x10304] fmov w2, s23
  [0x10308] sxtw x2, w2
  [0x1030C] fmov w1, s22
  [0x10310] sxtw x1, w1
  [0x10314] fmov w8, s21
  [0x10318] sxtw x8, w8
  [0x1031C] fmov w9, s20
  [0x10320] sxtw x9, w9
  [0x10324] fmov w10, s19
  [0x10328] sxtw x10, w10
  [0x1032C] fmov w11, s18
  [0x10330] sxtw x11, w11
  [0x10334] add x3, x3, x15
  [0x10338] stp x3, x5, [sp, #-0x10]!
  [0x1033C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10340] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10344] blr x3 ;; misaligned with debug data
  [0x10348] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1034C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10350] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10354] mov x0, x0
  [0x10358] adrp x16, #0x10000
  [0x1035C] add x16, x16, #0
  [0x10360] ldr w0, [x16]
  [0x10364] add x7, x14, #8
  [0x10368] sub x7, x7, x15 ;; misaligned with debug data
  [0x1036C] adrp x6, #0x11000
  [0x10370] add x6, x6, #0x454
  [0x10374] sub x6, x6, x15
  [0x10378] adrp x16, #0x10000
  [0x1037C] add x16, x16, #0
  [0x10380] ldr w9, [x16]
  [0x10384] add x16, x9, x15
  [0x10388] ldr w2, [x16, #0x20] ;; misaligned with debug data
  [0x1038C] adrp x16, #0x10000
  [0x10390] add x16, x16, #0
  [0x10394] ldr w9, [x16]
  [0x10398] add x16, x9, x15
  [0x1039C] ldr w1, [x16] ;; misaligned with debug data
  [0x103A0] adrp x16, #0x10000
  [0x103A4] add x16, x16, #0
  [0x103A8] ldr w9, [x16]
  [0x103AC] add x16, x9, x15
  [0x103B0] ldr w8, [x16, #4] ;; misaligned with debug data
  [0x103B4] adrp x16, #0x10000
  [0x103B8] add x16, x16, #0
  [0x103BC] ldr w9, [x16]
  [0x103C0] add x16, x9, x15
  [0x103C4] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x103C8] adrp x16, #0x10000
  [0x103CC] add x16, x16, #0
  [0x103D0] ldr w3, [x16]
  [0x103D4] add x16, x3, x15
  [0x103D8] ldr w10, [x16, #0x14] ;; misaligned with debug data
  [0x103DC] mov x3, x0
  [0x103E0] mov x7, x7
  [0x103E4] mov x6, x6
  [0x103E8] mov x2, x2
  [0x103EC] mov x1, x1
  [0x103F0] mov x8, x8
  [0x103F4] mov x9, x9
  [0x103F8] mov x10, x10
  [0x103FC] add x3, x3, x15
  [0x10400] stp x3, x5, [sp, #-0x10]!
  [0x10404] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10408] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1040C] blr x3 ;; misaligned with debug data
  [0x10410] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10414] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10418] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1041C] mov x0, x0
  [0x10420] adrp x16, #0x10000
  [0x10424] add x16, x16, #0
  [0x10428] ldr w9, [x16]
  [0x1042C] add x7, x14, #8
  [0x10430] sub x7, x7, x15 ;; misaligned with debug data
  [0x10434] adrp x6, #0x11000
  [0x10438] add x6, x6, #0x494
  [0x1043C] sub x6, x6, x15
  [0x10440] mov x9, x9
  [0x10444] mov x7, x7
  [0x10448] mov x6, x6
  [0x1044C] add x9, x9, x15
  [0x10450] stp x3, x5, [sp, #-0x10]!
  [0x10454] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10458] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1045C] blr x9 ;; misaligned with debug data
  [0x10460] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10464] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10468] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1046C] mov x0, x0
  [0x10470] movz x9, #0
  [0x10474] add sp, sp, #0x10
  [0x10478] ldp x29, x30, [sp], #0x10
  [0x1047C] ret


[(method clear-text-seen! game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] add x16, x7, x15
  [0x10018] ldr w7, [x16, #0x6c] ;; misaligned with debug data
  [0x1001C] mov x6, x6
  [0x10020] add x16, x7, x15
  [0x10024] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10028] add x16, x9, x15
  [0x1002C] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10030] mov x9, x9
  [0x10034] mov x7, x7
  [0x10038] mov x6, x6
  [0x1003C] add x9, x9, x15
  [0x10040] stp x3, x5, [sp, #-0x10]!
  [0x10044] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10048] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1004C] blr x9 ;; misaligned with debug data
  [0x10050] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10054] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10058] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1005C] mov x0, x0
  [0x10060] add sp, sp, #0x10
  [0x10064] ldp x29, x30, [sp], #0x10
  [0x10068] ret


[anon-function-0]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x11, x6
  [0x10014] mov x12, x2
  [0x10018] mov x3, x1
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] ldr w9, [x16]
  [0x10028] mov x9, x9
  [0x1002C] mov x7, x5
  [0x10030] add x9, x9, x15
  [0x10034] stp x3, x5, [sp, #-0x10]!
  [0x10038] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1003C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10040] blr x9 ;; misaligned with debug data
  [0x10044] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10048] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1004C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10050] mov x0, x0
  [0x10054] adrp x16, #0x10000
  [0x10058] add x16, x16, #0
  [0x1005C] ldr w9, [x16]
  [0x10060] mov x9, x9
  [0x10064] mov x7, x11
  [0x10068] add x9, x9, x15
  [0x1006C] stp x3, x5, [sp, #-0x10]!
  [0x10070] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10074] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10078] blr x9 ;; misaligned with debug data
  [0x1007C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10080] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10084] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10088] mov x11, x11
  [0x1008C] adrp x16, #0x10000
  [0x10090] add x16, x16, #0
  [0x10094] ldr w7, [x16]
  [0x10098] add x16, x7, x15
  [0x1009C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100A0] add x16, x9, x15
  [0x100A4] ldr w9, [x16, #0x5c] ;; misaligned with debug data
  [0x100A8] mov x9, x9
  [0x100AC] mov x7, x7
  [0x100B0] mov x6, x12
  [0x100B4] add x9, x9, x15
  [0x100B8] stp x3, x5, [sp, #-0x10]!
  [0x100BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C4] blr x9 ;; misaligned with debug data
  [0x100C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] mov x0, x0
  [0x100D8] mov x9, x14
  [0x100DC] sub x9, x9, x15 ;; misaligned with debug data
  [0x100E0] cmp x3, x9
  [0x100E4] b.eq #0x10188
  [0x100E8] adrp x16, #0x10000
  [0x100EC] add x16, x16, #0
  [0x100F0] ldr w7, [x16]
  [0x100F4] add x16, x7, x15
  [0x100F8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100FC] add x16, x9, x15
  [0x10100] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x10104] mov x9, x9
  [0x10108] mov x7, x7
  [0x1010C] mov x6, x3
  [0x10110] add x9, x9, x15
  [0x10114] stp x3, x5, [sp, #-0x10]!
  [0x10118] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1011C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10120] blr x9 ;; misaligned with debug data
  [0x10124] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10128] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1012C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10130] mov x0, x0
  [0x10134] adrp x16, #0x10000
  [0x10138] add x16, x16, #0
  [0x1013C] ldr w7, [x16]
  [0x10140] add x16, x7, x15
  [0x10144] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10148] add x16, x9, x15
  [0x1014C] ldr w9, [x16, #0x54] ;; misaligned with debug data
  [0x10150] mov x9, x9
  [0x10154] mov x7, x7
  [0x10158] add x9, x9, x15
  [0x1015C] stp x3, x5, [sp, #-0x10]!
  [0x10160] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10164] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10168] blr x9 ;; misaligned with debug data
  [0x1016C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10170] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10174] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10178] mov x0, x0
  [0x1017C] mov x12, x0
  [0x10180] mov x0, x0
  [0x10184] b #0x10190
  [0x10188] mov x0, x14
  [0x1018C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10190] mov x9, sp
  [0x10194] sub x9, x9, x15
  [0x10198] mov x9, x9
  [0x1019C] mov x8, x13
  [0x101A0] add x16, x8, x15
  [0x101A4] ldr w8, [x16, #0x2c] ;; misaligned with debug data
  [0x101A8] add x16, x8, x15
  [0x101AC] ldr w1, [x16, #0x1c] ;; misaligned with debug data
  [0x101B0] mov x1, x1
  [0x101B4] mov x1, x1
  [0x101B8] mov x1, x1
  [0x101BC] mov x9, x9
  [0x101C0] sub x1, x1, x9
  [0x101C4] mov x1, x1
  [0x101C8] mov x9, x13
  [0x101CC] add x16, x9, x15
  [0x101D0] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x101D4] add x16, x9, x15
  [0x101D8] ldrsw x8, [x16, #0x20] ;; misaligned with debug data
  [0x101DC] mov x8, x8
  [0x101E0] cmp x1, x8
  [0x101E4] b.le #0x10248
  [0x101E8] adrp x16, #0x10000
  [0x101EC] add x16, x16, #0
  [0x101F0] ldr w9, [x16]
  [0x101F4] movz x7, #0
  [0x101F8] adrp x6, #0x15000
  [0x101FC] add x6, x6, #0xf14
  [0x10200] sub x6, x6, x15
  [0x10204] mov x9, x9
  [0x10208] mov x7, x7
  [0x1020C] mov x6, x6
  [0x10210] mov x2, x13
  [0x10214] mov x1, x1
  [0x10218] mov x8, x8
  [0x1021C] add x9, x9, x15
  [0x10220] stp x3, x5, [sp, #-0x10]!
  [0x10224] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10228] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1022C] blr x9 ;; misaligned with debug data
  [0x10230] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10234] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10238] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1023C] mov x0, x0
  [0x10240] mov x0, x0
  [0x10244] b #0x10250
  [0x10248] mov x0, x14
  [0x1024C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10250] mov x9, x13
  [0x10254] add x16, x9, x15
  [0x10258] ldr w3, [x16, #0x2c] ;; misaligned with debug data
  [0x1025C] mov x13, x3
  [0x10260] mov x9, x13
  [0x10264] add x16, x9, x15
  [0x10268] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x1026C] movz x7, #0
  [0x10270] mov x7, x7
  [0x10274] mov x9, x9
  [0x10278] mov x7, x7
  [0x1027C] add x9, x9, x15
  [0x10280] stp x3, x5, [sp, #-0x10]!
  [0x10284] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10288] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1028C] blr x9 ;; misaligned with debug data
  [0x10290] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10294] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10298] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1029C] mov x3, x3
  [0x102A0] adrp x16, #0x10000
  [0x102A4] add x16, x16, #0
  [0x102A8] ldr w9, [x16]
  [0x102AC] mov x9, x9
  [0x102B0] mov x7, x5
  [0x102B4] mov x6, x12
  [0x102B8] add x9, x9, x15
  [0x102BC] stp x3, x5, [sp, #-0x10]!
  [0x102C0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C8] blr x9 ;; misaligned with debug data
  [0x102CC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102D0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102D4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102D8] mov x0, x0
  [0x102DC] add sp, sp, #0x10
  [0x102E0] ldp x29, x30, [sp], #0x10
  [0x102E4] ret


[(method get-or-create-continue! game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] add x16, x7, x15
  [0x10014] ldr w9, [x16] ;; misaligned with debug data
  [0x10018] adrp x8, #0x10000
  [0x1001C] add x8, x8, #0
  [0x10020] mov x1, x14
  [0x10024] sub x1, x1, x15 ;; misaligned with debug data
  [0x10028] cmp x9, x8
  [0x1002C] b.ne #0x1003c
  [0x10030] add x1, x14, #8
  [0x10034] sub x1, x1, x15 ;; misaligned with debug data
  [0x10038] mov x1, x1
  [0x1003C] mov x9, x1
  [0x10040] mov x8, x14
  [0x10044] sub x8, x8, x15 ;; misaligned with debug data
  [0x10048] cmp x9, x8
  [0x1004C] b.eq #0x1005c
  [0x10050] add x16, x7, x15
  [0x10054] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x10058] mov x9, x9
  [0x1005C] mov x8, x14
  [0x10060] sub x8, x8, x15 ;; misaligned with debug data
  [0x10064] cmp x9, x8
  [0x10068] b.eq #0x1007c
  [0x1006C] add x16, x7, x15
  [0x10070] ldr w0, [x16, #0x68] ;; misaligned with debug data
  [0x10074] mov x0, x0
  [0x10078] b #0x101bc
  [0x1007C] adrp x16, #0x10000
  [0x10080] add x16, x16, #0
  [0x10084] ldr w3, [x16]
  [0x10088] mov x3, x3
  [0x1008C] adrp x16, #0x10000
  [0x10090] add x16, x16, #0
  [0x10094] ldr w9, [x16]
  [0x10098] movz x7, #0xc
  [0x1009C] add x7, x7, x3
  [0x100A0] adrp x16, #0x15000
  [0x100A4] ldr s23, [x16, #0xe8c]
  [0x100A8] adrp x16, #0x15000
  [0x100AC] ldr s22, [x16, #0xe90]
  [0x100B0] mov x9, x9
  [0x100B4] mov x7, x7
  [0x100B8] fmov w6, s23
  [0x100BC] sxtw x6, w6
  [0x100C0] fmov w2, s22
  [0x100C4] sxtw x2, w2
  [0x100C8] add x9, x9, x15
  [0x100CC] stp x3, x5, [sp, #-0x10]!
  [0x100D0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D8] blr x9 ;; misaligned with debug data
  [0x100DC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100E0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100E4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100E8] mov x0, x0
  [0x100EC] adrp x16, #0x10000
  [0x100F0] add x16, x16, #0
  [0x100F4] ldr w9, [x16]
  [0x100F8] movz x7, #0x1c
  [0x100FC] add x7, x7, x3
  [0x10100] mov x9, x9
  [0x10104] mov x7, x7
  [0x10108] add x9, x9, x15
  [0x1010C] stp x3, x5, [sp, #-0x10]!
  [0x10110] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10114] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10118] blr x9 ;; misaligned with debug data
  [0x1011C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10120] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10124] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10128] mov x0, x0
  [0x1012C] adrp x16, #0x10000
  [0x10130] add x16, x16, #0
  [0x10134] ldr w9, [x16]
  [0x10138] add x16, x9, x15
  [0x1013C] ldr w9, [x16, #0x20] ;; misaligned with debug data
  [0x10140] add x16, x3, x15
  [0x10144] str w9, [x16, #0x64] ;; misaligned with debug data
  [0x10148] adrp x16, #0x10000
  [0x1014C] add x16, x16, #0
  [0x10150] ldr w9, [x16]
  [0x10154] add x16, x9, x15
  [0x10158] ldr w9, [x16] ;; misaligned with debug data
  [0x1015C] add x16, x3, x15
  [0x10160] str w9, [x16, #0x68] ;; misaligned with debug data
  [0x10164] adrp x16, #0x10000
  [0x10168] add x16, x16, #0
  [0x1016C] ldr w9, [x16]
  [0x10170] add x16, x9, x15
  [0x10174] ldr w9, [x16, #4] ;; misaligned with debug data
  [0x10178] add x16, x3, x15
  [0x1017C] str w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10180] adrp x16, #0x10000
  [0x10184] add x16, x16, #0
  [0x10188] ldr w9, [x16]
  [0x1018C] add x16, x9, x15
  [0x10190] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10194] add x16, x3, x15
  [0x10198] str w9, [x16, #0x70] ;; misaligned with debug data
  [0x1019C] adrp x16, #0x10000
  [0x101A0] add x16, x16, #0
  [0x101A4] ldr w9, [x16]
  [0x101A8] add x16, x9, x15
  [0x101AC] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x101B0] add x16, x3, x15
  [0x101B4] str w9, [x16, #0x74] ;; misaligned with debug data
  [0x101B8] mov x0, x3
  [0x101BC] mov x0, x0
  [0x101C0] add sp, sp, #0x10
  [0x101C4] ldp x29, x30, [sp], #0x10
  [0x101C8] ret


[(method task-complete? game-info)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x6, x6
  [0x10014] lsl x6, x6, #4
  [0x10018] mov x6, x6
  [0x1001C] movz x9, #0xc
  [0x10020] add x16, x7, x15
  [0x10024] ldr w8, [x16, #0x64] ;; misaligned with debug data
  [0x10028] add x9, x9, x8
  [0x1002C] add x6, x6, x9
  [0x10030] add x16, x6, x15
  [0x10034] ldrh w9, [x16, #8] ;; misaligned with debug data
  [0x10038] movz x8, #0x100
  [0x1003C] mov x9, x9
  [0x10040] and x9, x9, x8
  [0x10044] movz x8, #0
  [0x10048] mov x0, x14
  [0x1004C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10050] cmp x9, x8
  [0x10054] b.eq #0x10064
  [0x10058] add x0, x14, #8
  [0x1005C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10060] mov x0, x0
  [0x10064] mov x0, x0
  [0x10068] ldp x29, x30, [sp], #0x10
  [0x1006C] ret


[(method debug-draw! continue-point)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] add x7, x14, #8
  [0x10020] sub x7, x7, x15 ;; misaligned with debug data
  [0x10024] movz x6, #0x44
  [0x10028] movz x2, #0xc
  [0x1002C] add x2, x2, x3
  [0x10030] movz x1, #0xff
  [0x10034] movk x1, #0x8000, lsl #16
  [0x10038] mov x9, x9
  [0x1003C] mov x7, x7
  [0x10040] mov x6, x6
  [0x10044] mov x2, x2
  [0x10048] mov x1, x1
  [0x1004C] add x9, x9, x15
  [0x10050] stp x3, x5, [sp, #-0x10]!
  [0x10054] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10058] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1005C] blr x9 ;; misaligned with debug data
  [0x10060] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10064] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10068] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1006C] mov x0, x0
  [0x10070] adrp x16, #0x10000
  [0x10074] add x16, x16, #0
  [0x10078] ldr w0, [x16]
  [0x1007C] add x7, x14, #8
  [0x10080] sub x7, x7, x15 ;; misaligned with debug data
  [0x10084] movz x6, #0x44
  [0x10088] add x16, x3, x15
  [0x1008C] ldr w2, [x16] ;; misaligned with debug data
  [0x10090] movz x1, #0xc
  [0x10094] add x1, x1, x3
  [0x10098] movz x8, #0x1
  [0x1009C] adrp x9, #0x11000
  [0x100A0] add x9, x9, #0xc0
  [0x100A4] sub x9, x9, x15
  [0x100A8] mov x5, x0
  [0x100AC] mov x7, x7
  [0x100B0] mov x6, x6
  [0x100B4] mov x2, x2
  [0x100B8] mov x1, x1
  [0x100BC] mov x8, x8
  [0x100C0] mov x9, x9
  [0x100C4] add x5, x5, x15
  [0x100C8] stp x3, x5, [sp, #-0x10]!
  [0x100CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D4] blr x5 ;; misaligned with debug data
  [0x100D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100E4] mov x0, x0
  [0x100E8] adrp x16, #0x10000
  [0x100EC] add x16, x16, #0
  [0x100F0] ldr w9, [x16]
  [0x100F4] mov x7, sp
  [0x100F8] sub x7, x7, x15
  [0x100FC] mov x7, x7
  [0x10100] movz x8, #0
  [0x10104] mov x8, x8
  [0x10108] fmov d23, x8
  [0x1010C] add x16, x7, x15
  [0x10110] str q23, [x16] ;; misaligned with debug data
  [0x10114] movz x6, #0x1c
  [0x10118] add x6, x6, x3
  [0x1011C] mov x9, x9
  [0x10120] mov x7, x7
  [0x10124] mov x6, x6
  [0x10128] add x9, x9, x15
  [0x1012C] stp x3, x5, [sp, #-0x10]!
  [0x10130] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10134] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10138] blr x9 ;; misaligned with debug data
  [0x1013C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10140] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10144] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10148] mov x0, x0
  [0x1014C] mov x0, x0
  [0x10150] adrp x16, #0x10000
  [0x10154] add x16, x16, #0
  [0x10158] ldr w8, [x16]
  [0x1015C] add x7, x14, #8
  [0x10160] sub x7, x7, x15 ;; misaligned with debug data
  [0x10164] movz x6, #0x44
  [0x10168] movz x2, #0xc
  [0x1016C] add x2, x2, x3
  [0x10170] adrp x16, #0x11000
  [0x10174] ldr s23, [x16, #0xc4]
  [0x10178] movz x9, #0x80ff
  [0x1017C] movk x9, #0x8000, lsl #16
  [0x10180] mov x3, x8
  [0x10184] mov x7, x7
  [0x10188] mov x6, x6
  [0x1018C] mov x2, x2
  [0x10190] mov x1, x0
  [0x10194] fmov w8, s23
  [0x10198] sxtw x8, w8
  [0x1019C] mov x9, x9
  [0x101A0] add x3, x3, x15
  [0x101A4] stp x3, x5, [sp, #-0x10]!
  [0x101A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101B0] blr x3 ;; misaligned with debug data
  [0x101B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101C0] mov x0, x0
  [0x101C4] add sp, sp, #0x10
  [0x101C8] ldp x29, x30, [sp], #0x10
  [0x101CC] ret


[(method point-past-plane? border-plane)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] mov x9, sp
  [0x10018] sub x9, x9, x15
  [0x1001C] movz x8, #0xc
  [0x10020] add x8, x8, x7
  [0x10024] mov x9, x9
  [0x10028] mov x6, x6
  [0x1002C] mov x8, x8
  [0x10030] add x16, x6, x15
  [0x10034] ldr q22, [x16] ;; misaligned with debug data
  [0x10038] add x16, x8, x15
  [0x1003C] ldr q21, [x16] ;; misaligned with debug data
  [0x10040] adrp x16, #0x15000
  [0x10044] ldr q23, [x16, #0xde0]
  [0x10048] fsub v22.4s, v22.4s, v21.4s
  [0x1004C] ins v22.s[3], v23.s[3]
  [0x10050] add x16, x9, x15
  [0x10054] str q22, [x16] ;; misaligned with debug data
  [0x10058] movz x8, #0x1c
  [0x1005C] add x8, x8, x7
  [0x10060] mov x9, x9
  [0x10064] mov x8, x8
  [0x10068] adrp x16, #0x15000
  [0x1006C] ldr s23, [x16, #0xdf0]
  [0x10070] mov v23.16b, v23.16b
  [0x10074] mov v23.16b, v23.16b
  [0x10078] add x16, x9, x15
  [0x1007C] ldr s22, [x16] ;; misaligned with debug data
  [0x10080] mov v22.16b, v22.16b
  [0x10084] add x16, x8, x15
  [0x10088] ldr s21, [x16] ;; misaligned with debug data
  [0x1008C] fmul s22, s22, s21
  [0x10090] fadd s23, s23, s22
  [0x10094] mov v23.16b, v23.16b
  [0x10098] mov v23.16b, v23.16b
  [0x1009C] add x16, x9, x15
  [0x100A0] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x100A4] mov v22.16b, v22.16b
  [0x100A8] add x16, x8, x15
  [0x100AC] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x100B0] fmul s22, s22, s21
  [0x100B4] fadd s23, s23, s22
  [0x100B8] mov v23.16b, v23.16b
  [0x100BC] mov v23.16b, v23.16b
  [0x100C0] add x16, x9, x15
  [0x100C4] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x100C8] mov v22.16b, v22.16b
  [0x100CC] add x16, x8, x15
  [0x100D0] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x100D4] fmul s22, s22, s21
  [0x100D8] fadd s23, s23, s22
  [0x100DC] mov v23.16b, v23.16b
  [0x100E0] adrp x16, #0x15000
  [0x100E4] ldr s22, [x16, #0xdf4]
  [0x100E8] mov x0, x14
  [0x100EC] sub x0, x0, x15 ;; misaligned with debug data
  [0x100F0] fcmp s23, s22
  [0x100F4] b.mi #0x10104
  [0x100F8] add x0, x14, #8
  [0x100FC] sub x0, x0, x15 ;; misaligned with debug data
  [0x10100] mov x0, x0
  [0x10104] mov x0, x0
  [0x10108] add sp, sp, #0x10
  [0x1010C] ldp x29, x30, [sp], #0x10
  [0x10110] ret


[(method debug-draw! border-plane)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] add x16, x5, x15
  [0x10014] ldr w9, [x16, #4] ;; misaligned with debug data
  [0x10018] mov x9, x9
  [0x1001C] adrp x8, #0x10000
  [0x10020] add x8, x8, #0
  [0x10024] cmp x9, x8
  [0x10028] b.ne #0x1003c
  [0x1002C] movz x3, #0xff00
  [0x10030] movk x3, #0x8000, lsl #16
  [0x10034] mov x3, x3
  [0x10038] b #0x10048
  [0x1003C] movz x3, #0xff
  [0x10040] movk x3, #0x8000, lsl #16
  [0x10044] mov x3, x3
  [0x10048] mov x3, x3
  [0x1004C] adrp x16, #0x10000
  [0x10050] add x16, x16, #0
  [0x10054] ldr w9, [x16]
  [0x10058] add x7, x14, #8
  [0x1005C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10060] movz x6, #0x44
  [0x10064] movz x2, #0xc
  [0x10068] add x2, x2, x5
  [0x1006C] adrp x16, #0x15000
  [0x10070] ldr s23, [x16, #0xdd4]
  [0x10074] movz x8, #0
  [0x10078] movk x8, #0x2, lsl #16
  [0x1007C] mov x8, x8
  [0x10080] add x16, x5, x15
  [0x10084] ldr w1, [x16] ;; misaligned with debug data
  [0x10088] mov x1, x1
  [0x1008C] add x8, x8, x1
  [0x10090] mov x8, x8
  [0x10094] add x16, x8, x15
  [0x10098] ldr w8, [x16] ;; misaligned with debug data
  [0x1009C] mov x12, x9
  [0x100A0] mov x7, x7
  [0x100A4] mov x6, x6
  [0x100A8] mov x2, x2
  [0x100AC] fmov w1, s23
  [0x100B0] sxtw x1, w1
  [0x100B4] mov x8, x8
  [0x100B8] mov x9, x3
  [0x100BC] add x12, x12, x15
  [0x100C0] stp x3, x5, [sp, #-0x10]!
  [0x100C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100CC] blr x12 ;; misaligned with debug data
  [0x100D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] mov x0, x0
  [0x100E0] adrp x16, #0x10000
  [0x100E4] add x16, x16, #0
  [0x100E8] ldr w9, [x16]
  [0x100EC] add x7, x14, #8
  [0x100F0] sub x7, x7, x15 ;; misaligned with debug data
  [0x100F4] movz x6, #0x44
  [0x100F8] movz x2, #0xc
  [0x100FC] add x2, x2, x5
  [0x10100] movz x1, #0x1c
  [0x10104] add x1, x1, x5
  [0x10108] adrp x16, #0x15000
  [0x1010C] ldr s23, [x16, #0xdd8]
  [0x10110] mov x5, x9
  [0x10114] mov x7, x7
  [0x10118] mov x6, x6
  [0x1011C] mov x2, x2
  [0x10120] mov x1, x1
  [0x10124] fmov w8, s23
  [0x10128] sxtw x8, w8
  [0x1012C] mov x9, x3
  [0x10130] add x5, x5, x15
  [0x10134] stp x3, x5, [sp, #-0x10]!
  [0x10138] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1013C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10140] blr x5 ;; misaligned with debug data
  [0x10144] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10148] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1014C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10150] mov x0, x0
  [0x10154] add sp, sp, #0x10
  [0x10158] ldp x29, x30, [sp], #0x10
  [0x1015C] ret



