[top-level]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] adrp x9, #0x10000
  [0x1000C] add x9, x9, #0
  [0x10010] sub x9, x9, x15
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] str w9, [x16]
  [0x10020] adrp x9, #0x10000
  [0x10024] add x9, x9, #0
  [0x10028] sub x9, x9, x15
  [0x1002C] adrp x16, #0x10000
  [0x10030] add x16, x16, #0
  [0x10034] str w9, [x16]
  [0x10038] adrp x9, #0x10000
  [0x1003C] add x9, x9, #0
  [0x10040] sub x9, x9, x15
  [0x10044] adrp x16, #0x10000
  [0x10048] add x16, x16, #0
  [0x1004C] str w9, [x16]
  [0x10050] adrp x9, #0x10000
  [0x10054] add x9, x9, #0
  [0x10058] sub x9, x9, x15
  [0x1005C] adrp x16, #0x10000
  [0x10060] add x16, x16, #0
  [0x10064] str w9, [x16]
  [0x10068] adrp x9, #0x10000
  [0x1006C] add x9, x9, #0
  [0x10070] sub x9, x9, x15
  [0x10074] adrp x16, #0x10000
  [0x10078] add x16, x16, #0
  [0x1007C] str w9, [x16]
  [0x10080] adrp x9, #0x10000
  [0x10084] add x9, x9, #0
  [0x10088] sub x9, x9, x15
  [0x1008C] adrp x16, #0x10000
  [0x10090] add x16, x16, #0
  [0x10094] str w9, [x16]
  [0x10098] adrp x9, #0x10000
  [0x1009C] add x9, x9, #0
  [0x100A0] sub x9, x9, x15
  [0x100A4] adrp x16, #0x10000
  [0x100A8] add x16, x16, #0
  [0x100AC] str w9, [x16]
  [0x100B0] adrp x9, #0x10000
  [0x100B4] add x9, x9, #0
  [0x100B8] sub x9, x9, x15
  [0x100BC] adrp x16, #0x10000
  [0x100C0] add x16, x16, #0
  [0x100C4] str w9, [x16]
  [0x100C8] adrp x9, #0x10000
  [0x100CC] add x9, x9, #0
  [0x100D0] sub x9, x9, x15
  [0x100D4] adrp x16, #0x10000
  [0x100D8] add x16, x16, #0
  [0x100DC] str w9, [x16]
  [0x100E0] adrp x9, #0x10000
  [0x100E4] add x9, x9, #0
  [0x100E8] sub x9, x9, x15
  [0x100EC] adrp x16, #0x10000
  [0x100F0] add x16, x16, #0
  [0x100F4] str w9, [x16]
  [0x100F8] adrp x9, #0x10000
  [0x100FC] add x9, x9, #0
  [0x10100] sub x9, x9, x15
  [0x10104] adrp x16, #0x10000
  [0x10108] add x16, x16, #0
  [0x1010C] str w9, [x16]
  [0x10110] adrp x16, #0x10000
  [0x10114] add x16, x16, #0
  [0x10118] ldr w9, [x16]
  [0x1011C] adrp x16, #0x10000
  [0x10120] add x16, x16, #0
  [0x10124] ldr w9, [x16]
  [0x10128] adrp x9, #0x10000
  [0x1012C] add x9, x9, #0
  [0x10130] sub x9, x9, x15
  [0x10134] adrp x16, #0x10000
  [0x10138] add x16, x16, #0
  [0x1013C] str w9, [x16]
  [0x10140] adrp x9, #0x10000
  [0x10144] add x9, x9, #0
  [0x10148] sub x9, x9, x15
  [0x1014C] adrp x16, #0x10000
  [0x10150] add x16, x16, #0
  [0x10154] str w9, [x16]
  [0x10158] adrp x0, #0x10000
  [0x1015C] add x0, x0, #0
  [0x10160] sub x0, x0, x15
  [0x10164] adrp x16, #0x10000
  [0x10168] add x16, x16, #0
  [0x1016C] str w0, [x16]
  [0x10170] mov x0, x0
  [0x10174] ldp x29, x30, [sp], #0x10
  [0x10178] ret


[target-effect-exit]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] add x16, x13, x15
  [0x1000C] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10010] add x16, x9, x15
  [0x10014] ldr w9, [x16, #0x24] ;; misaligned with debug data
  [0x10018] mov x9, x9
  [0x1001C] movz x8, #0
  [0x10020] add x16, x9, x15
  [0x10024] str w8, [x16, #0x10] ;; misaligned with debug data
  [0x10028] movz x9, #0
  [0x1002C] ldp x29, x30, [sp], #0x10
  [0x10030] ret


[target-state-hook-exit]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] adrp x16, #0x10000
  [0x1000C] add x16, x16, #0
  [0x10010] ldr w9, [x16]
  [0x10014] mov x9, x9
  [0x10018] add x16, x13, x15
  [0x1001C] str w9, [x16, #0xc4] ;; misaligned with debug data
  [0x10020] ldp x29, x30, [sp], #0x10
  [0x10024] ret


[target-exit]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] adrp x16, #0x10000
  [0x10010] add x16, x16, #0
  [0x10014] ldr w9, [x16]
  [0x10018] add x16, x13, x15
  [0x1001C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10020] add x16, x8, x15
  [0x10024] str w9, [x16, #0x290] ;; misaligned with debug data
  [0x10028] movz x9, #0
  [0x1002C] mov x9, x9
  [0x10030] fmov d23, x9
  [0x10034] add x16, x13, x15
  [0x10038] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1003C] add x16, x9, x15
  [0x10040] add x16, x16, #0x24c ;; misaligned with debug data
  [0x10044] str q23, [x16] ;; misaligned with debug data
  [0x10048] movz x9, #0
  [0x1004C] mov x9, x9
  [0x10050] fmov d23, x9
  [0x10054] add x16, x13, x15
  [0x10058] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1005C] add x16, x9, x15
  [0x10060] add x16, x16, #0x25c ;; misaligned with debug data
  [0x10064] str q23, [x16] ;; misaligned with debug data
  [0x10068] movz x9, #0
  [0x1006C] mov x9, x9
  [0x10070] fmov d23, x9
  [0x10074] add x16, x13, x15
  [0x10078] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1007C] add x16, x9, x15
  [0x10080] add x16, x16, #0x26c ;; misaligned with debug data
  [0x10084] str q23, [x16] ;; misaligned with debug data
  [0x10088] movz x9, #0
  [0x1008C] mov x9, x9
  [0x10090] fmov d23, x9
  [0x10094] add x16, x13, x15
  [0x10098] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1009C] add x16, x9, x15
  [0x100A0] add x16, x16, #0x22c ;; misaligned with debug data
  [0x100A4] str q23, [x16] ;; misaligned with debug data
  [0x100A8] adrp x16, #0x11000
  [0x100AC] ldr s23, [x16, #0x4c]
  [0x100B0] add x16, x13, x15
  [0x100B4] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x100B8] add x16, x9, x15
  [0x100BC] str s23, [x16, #0x494] ;; misaligned with debug data
  [0x100C0] adrp x16, #0x11000
  [0x100C4] ldr s23, [x16, #0x50]
  [0x100C8] add x16, x13, x15
  [0x100CC] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x100D0] add x16, x9, x15
  [0x100D4] str s23, [x16, #0x6bc] ;; misaligned with debug data
  [0x100D8] add x16, x13, x15
  [0x100DC] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x100E0] movz x8, #0x38c
  [0x100E4] movk x8, #0x1c, lsl #16
  [0x100E8] mov x8, x8
  [0x100EC] mvn x8, x8
  [0x100F0] mov x9, x9
  [0x100F4] and x9, x9, x8
  [0x100F8] add x16, x13, x15
  [0x100FC] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10100] adrp x16, #0x10000
  [0x10104] add x16, x16, #0
  [0x10108] ldr w9, [x16]
  [0x1010C] adrp x7, #0x10000
  [0x10110] add x7, x7, #0
  [0x10114] mov x6, x14
  [0x10118] sub x6, x6, x15 ;; misaligned with debug data
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
  [0x1014C] add x16, x13, x15
  [0x10150] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x10154] add x16, x9, x15
  [0x10158] ldr w9, [x16] ;; misaligned with debug data
  [0x1015C] mov x9, x9
  [0x10160] movz x8, #0x10
  [0x10164] orr x9, x9, x8
  [0x10168] add x16, x13, x15
  [0x1016C] ldr w8, [x16, #0x98] ;; misaligned with debug data
  [0x10170] add x16, x8, x15
  [0x10174] str w9, [x16] ;; misaligned with debug data
  [0x10178] add x16, x13, x15
  [0x1017C] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x10180] add x16, x9, x15
  [0x10184] ldr w9, [x16] ;; misaligned with debug data
  [0x10188] movz x8, #0
  [0x1018C] movk x8, #0x1, lsl #16
  [0x10190] mov x8, x8
  [0x10194] mvn x8, x8
  [0x10198] mov x9, x9
  [0x1019C] and x9, x9, x8
  [0x101A0] add x16, x13, x15
  [0x101A4] ldr w8, [x16, #0x98] ;; misaligned with debug data
  [0x101A8] add x16, x8, x15
  [0x101AC] str w9, [x16] ;; misaligned with debug data
  [0x101B0] adrp x16, #0x11000
  [0x101B4] ldr s23, [x16, #0x54]
  [0x101B8] add x16, x13, x15
  [0x101BC] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x101C0] add x16, x9, x15
  [0x101C4] str s23, [x16, #0x114] ;; misaligned with debug data
  [0x101C8] adrp x16, #0x11000
  [0x101CC] ldr s23, [x16, #0x58]
  [0x101D0] add x16, x13, x15
  [0x101D4] ldr w9, [x16, #0xb8] ;; misaligned with debug data
  [0x101D8] add x16, x9, x15
  [0x101DC] str s23, [x16, #0x74] ;; misaligned with debug data
  [0x101E0] adrp x16, #0x11000
  [0x101E4] ldr s23, [x16, #0x5c]
  [0x101E8] add x16, x13, x15
  [0x101EC] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x101F0] add x16, x9, x15
  [0x101F4] str s23, [x16, #0x734] ;; misaligned with debug data
  [0x101F8] add x16, x13, x15
  [0x101FC] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x10200] add x16, x9, x15
  [0x10204] ldrb w9, [x16] ;; misaligned with debug data
  [0x10208] movz x8, #0x2
  [0x1020C] mov x8, x8
  [0x10210] mvn x8, x8
  [0x10214] mov x9, x9
  [0x10218] and x9, x9, x8
  [0x1021C] add x16, x13, x15
  [0x10220] ldr w8, [x16, #0x74] ;; misaligned with debug data
  [0x10224] add x16, x8, x15
  [0x10228] strb w9, [x16] ;; misaligned with debug data
  [0x1022C] add x16, x13, x15
  [0x10230] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10234] add x16, x9, x15
  [0x10238] ldrh w9, [x16] ;; misaligned with debug data
  [0x1023C] movz x8, #0x20
  [0x10240] mov x8, x8
  [0x10244] mvn x8, x8
  [0x10248] mov x9, x9
  [0x1024C] and x9, x9, x8
  [0x10250] add x16, x13, x15
  [0x10254] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x10258] add x16, x8, x15
  [0x1025C] strh w9, [x16] ;; misaligned with debug data
  [0x10260] add x16, x13, x15
  [0x10264] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10268] add x16, x9, x15
  [0x1026C] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10270] ldr x9, [x16] ;; misaligned with debug data
  [0x10274] movz x8, #0x4000
  [0x10278] mov x8, x8
  [0x1027C] mvn x8, x8
  [0x10280] mov x9, x9
  [0x10284] and x9, x9, x8
  [0x10288] add x16, x13, x15
  [0x1028C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10290] add x16, x8, x15
  [0x10294] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10298] str x9, [x16] ;; misaligned with debug data
  [0x1029C] movz x9, #0
  [0x102A0] add sp, sp, #0x10
  [0x102A4] ldp x29, x30, [sp], #0x10
  [0x102A8] ret


[target-walk-event-handler]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] mov x5, x6
  [0x10014] mov x12, x2
  [0x10018] mov x11, x1
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] ldr w9, [x16]
  [0x10028] mov x9, x9
  [0x1002C] mov x7, x3
  [0x10030] mov x6, x5
  [0x10034] mov x2, x12
  [0x10038] mov x1, x11
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
  [0x10064] mov x9, x14
  [0x10068] sub x9, x9, x15 ;; misaligned with debug data
  [0x1006C] cmp x0, x9
  [0x10070] b.eq #0x1007c
  [0x10074] mov x0, x0
  [0x10078] b #0x100c4
  [0x1007C] adrp x16, #0x10000
  [0x10080] add x16, x16, #0
  [0x10084] ldr w9, [x16]
  [0x10088] mov x9, x9
  [0x1008C] mov x7, x3
  [0x10090] mov x6, x5
  [0x10094] mov x2, x12
  [0x10098] mov x1, x11
  [0x1009C] add x9, x9, x15
  [0x100A0] stp x3, x5, [sp, #-0x10]!
  [0x100A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100AC] blr x9 ;; misaligned with debug data
  [0x100B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100BC] mov x0, x0
  [0x100C0] mov x0, x0
  [0x100C4] mov x0, x0
  [0x100C8] add sp, sp, #0x10
  [0x100CC] ldp x29, x30, [sp], #0x10
  [0x100D0] ret


[target-jump-event-handler]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] mov x5, x6
  [0x10014] mov x12, x2
  [0x10018] mov x11, x1
  [0x1001C] adrp x9, #0x10000
  [0x10020] add x9, x9, #0
  [0x10024] mov x8, x14
  [0x10028] sub x8, x8, x15 ;; misaligned with debug data
  [0x1002C] cmp x12, x9
  [0x10030] b.ne #0x10040
  [0x10034] add x8, x14, #8
  [0x10038] sub x8, x8, x15 ;; misaligned with debug data
  [0x1003C] mov x8, x8
  [0x10040] mov x9, x8
  [0x10044] mov x8, x14
  [0x10048] sub x8, x8, x15 ;; misaligned with debug data
  [0x1004C] cmp x9, x8
  [0x10050] b.eq #0x10124
  [0x10054] movz x9, #0x1c
  [0x10058] add x16, x13, x15
  [0x1005C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10060] add x16, x8, x15
  [0x10064] ldr w8, [x16, #0x1b0] ;; misaligned with debug data
  [0x10068] add x9, x9, x8
  [0x1006C] movz x8, #0x3c
  [0x10070] add x16, x13, x15
  [0x10074] ldr w1, [x16, #0x6c] ;; misaligned with debug data
  [0x10078] add x8, x8, x1
  [0x1007C] mov x9, x9
  [0x10080] mov x8, x8
  [0x10084] adrp x16, #0x11000
  [0x10088] ldr s23, [x16, #0x48]
  [0x1008C] mov v23.16b, v23.16b
  [0x10090] mov v23.16b, v23.16b
  [0x10094] add x16, x9, x15
  [0x10098] ldr s22, [x16] ;; misaligned with debug data
  [0x1009C] mov v22.16b, v22.16b
  [0x100A0] add x16, x8, x15
  [0x100A4] ldr s21, [x16] ;; misaligned with debug data
  [0x100A8] fmul s22, s22, s21
  [0x100AC] fadd s23, s23, s22
  [0x100B0] mov v23.16b, v23.16b
  [0x100B4] mov v23.16b, v23.16b
  [0x100B8] add x16, x9, x15
  [0x100BC] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x100C0] mov v22.16b, v22.16b
  [0x100C4] add x16, x8, x15
  [0x100C8] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x100CC] fmul s22, s22, s21
  [0x100D0] fadd s23, s23, s22
  [0x100D4] mov v23.16b, v23.16b
  [0x100D8] mov v23.16b, v23.16b
  [0x100DC] add x16, x9, x15
  [0x100E0] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x100E4] mov v22.16b, v22.16b
  [0x100E8] add x16, x8, x15
  [0x100EC] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x100F0] fmul s22, s22, s21
  [0x100F4] fadd s23, s23, s22
  [0x100F8] mov v23.16b, v23.16b
  [0x100FC] adrp x16, #0x11000
  [0x10100] ldr s22, [x16, #0x44]
  [0x10104] mov x9, x14
  [0x10108] sub x9, x9, x15 ;; misaligned with debug data
  [0x1010C] fcmp s22, s23
  [0x10110] b.ge #0x10120
  [0x10114] add x9, x14, #8
  [0x10118] sub x9, x9, x15 ;; misaligned with debug data
  [0x1011C] mov x9, x9
  [0x10120] mov x9, x9
  [0x10124] mov x8, x14
  [0x10128] sub x8, x8, x15 ;; misaligned with debug data
  [0x1012C] cmp x9, x8
  [0x10130] b.eq #0x10148
  [0x10134] mov x0, x14
  [0x10138] sub x0, x0, x15 ;; misaligned with debug data
  [0x1013C] mov x0, x0
  [0x10140] b #0x101fc
  [0x10144] b #0x10150
  [0x10148] mov x9, x14
  [0x1014C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10150] adrp x16, #0x10000
  [0x10154] add x16, x16, #0
  [0x10158] ldr w9, [x16]
  [0x1015C] mov x9, x9
  [0x10160] mov x7, x3
  [0x10164] mov x6, x5
  [0x10168] mov x2, x12
  [0x1016C] mov x1, x11
  [0x10170] add x9, x9, x15
  [0x10174] stp x3, x5, [sp, #-0x10]!
  [0x10178] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1017C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10180] blr x9 ;; misaligned with debug data
  [0x10184] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10188] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1018C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10190] mov x0, x0
  [0x10194] mov x0, x0
  [0x10198] mov x9, x14
  [0x1019C] sub x9, x9, x15 ;; misaligned with debug data
  [0x101A0] cmp x0, x9
  [0x101A4] b.eq #0x101b0
  [0x101A8] mov x0, x0
  [0x101AC] b #0x101f8
  [0x101B0] adrp x16, #0x10000
  [0x101B4] add x16, x16, #0
  [0x101B8] ldr w9, [x16]
  [0x101BC] mov x9, x9
  [0x101C0] mov x7, x3
  [0x101C4] mov x6, x5
  [0x101C8] mov x2, x12
  [0x101CC] mov x1, x11
  [0x101D0] add x9, x9, x15
  [0x101D4] stp x3, x5, [sp, #-0x10]!
  [0x101D8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101DC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101E0] blr x9 ;; misaligned with debug data
  [0x101E4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101E8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101EC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101F0] mov x0, x0
  [0x101F4] mov x0, x0
  [0x101F8] mov x0, x0
  [0x101FC] add sp, sp, #0x10
  [0x10200] ldp x29, x30, [sp], #0x10
  [0x10204] ret


[target-bonk-event-handler]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0x80
  [0x10010] mov x11, x7
  [0x10014] mov x6, x6
  [0x10018] mov x12, x2
  [0x1001C] mov x5, x1
  [0x10020] mov x3, sp
  [0x10024] sub x3, x3, x15
  [0x10028] mov x3, x3
  [0x1002C] adrp x9, #0x10000
  [0x10030] add x9, x9, #0
  [0x10034] mov x8, x14
  [0x10038] sub x8, x8, x15 ;; misaligned with debug data
  [0x1003C] cmp x12, x9
  [0x10040] b.ne #0x10050
  [0x10044] add x8, x14, #8
  [0x10048] sub x8, x8, x15 ;; misaligned with debug data
  [0x1004C] mov x8, x8
  [0x10050] mov x9, x8
  [0x10054] mov x8, x14
  [0x10058] sub x8, x8, x15 ;; misaligned with debug data
  [0x1005C] cmp x9, x8
  [0x10060] b.eq #0x102fc
  [0x10064] adrp x16, #0x10000
  [0x10068] add x16, x16, #0
  [0x1006C] ldr w9, [x16]
  [0x10070] add x16, x9, x15
  [0x10074] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10078] add x16, x5, x15
  [0x1007C] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x10080] mov x7, x7
  [0x10084] add x16, x13, x15
  [0x10088] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x1008C] movz x2, #0x6
  [0x10090] mov x2, x2
  [0x10094] mov x9, x9
  [0x10098] mov x7, x7
  [0x1009C] mov x6, x6
  [0x100A0] mov x2, x2
  [0x100A4] add x9, x9, x15
  [0x100A8] stp x3, x5, [sp, #-0x10]!
  [0x100AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100B4] blr x9 ;; misaligned with debug data
  [0x100B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100C4] mov x0, x0
  [0x100C8] mov x9, x0
  [0x100CC] mov x8, x14
  [0x100D0] sub x8, x8, x15 ;; misaligned with debug data
  [0x100D4] cmp x9, x8
  [0x100D8] b.eq #0x102fc
  [0x100DC] adrp x16, #0x10000
  [0x100E0] ldr s23, [x16, #0xfc4]
  [0x100E4] mov v23.16b, v23.16b
  [0x100E8] adrp x16, #0x10000
  [0x100EC] add x16, x16, #0
  [0x100F0] ldr w9, [x16]
  [0x100F4] add x16, x9, x15
  [0x100F8] ldr s22, [x16, #0x394] ;; misaligned with debug data
  [0x100FC] fmul s23, s23, s22
  [0x10100] movz x9, #0x1c
  [0x10104] add x16, x13, x15
  [0x10108] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x1010C] add x16, x8, x15
  [0x10110] ldr w8, [x16, #0x1b0] ;; misaligned with debug data
  [0x10114] add x9, x9, x8
  [0x10118] add x8, sp, #0x10
  [0x1011C] sub x8, x8, x15
  [0x10120] movz x1, #0x3c
  [0x10124] add x16, x13, x15
  [0x10128] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x1012C] add x1, x1, x2
  [0x10130] movz x2, #0x21c
  [0x10134] add x16, x13, x15
  [0x10138] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x1013C] add x2, x2, x6
  [0x10140] mov x8, x8
  [0x10144] mov x1, x1
  [0x10148] mov x2, x2
  [0x1014C] add x16, x1, x15
  [0x10150] ldr q21, [x16] ;; misaligned with debug data
  [0x10154] add x16, x2, x15
  [0x10158] ldr q20, [x16] ;; misaligned with debug data
  [0x1015C] adrp x16, #0x10000
  [0x10160] ldr q22, [x16, #0xfd0]
  [0x10164] fsub v21.4s, v21.4s, v20.4s
  [0x10168] ins v21.s[3], v22.s[3]
  [0x1016C] add x16, x8, x15
  [0x10170] str q21, [x16] ;; misaligned with debug data
  [0x10174] mov x9, x9
  [0x10178] mov x8, x8
  [0x1017C] adrp x16, #0x10000
  [0x10180] ldr s22, [x16, #0xfe0]
  [0x10184] mov v22.16b, v22.16b
  [0x10188] mov v22.16b, v22.16b
  [0x1018C] add x16, x9, x15
  [0x10190] ldr s21, [x16] ;; misaligned with debug data
  [0x10194] mov v21.16b, v21.16b
  [0x10198] add x16, x8, x15
  [0x1019C] ldr s20, [x16] ;; misaligned with debug data
  [0x101A0] fmul s21, s21, s20
  [0x101A4] fadd s22, s22, s21
  [0x101A8] mov v22.16b, v22.16b
  [0x101AC] mov v22.16b, v22.16b
  [0x101B0] add x16, x9, x15
  [0x101B4] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x101B8] mov v21.16b, v21.16b
  [0x101BC] add x16, x8, x15
  [0x101C0] ldr s20, [x16, #4] ;; misaligned with debug data
  [0x101C4] fmul s21, s21, s20
  [0x101C8] fadd s22, s22, s21
  [0x101CC] mov v22.16b, v22.16b
  [0x101D0] mov v22.16b, v22.16b
  [0x101D4] add x16, x9, x15
  [0x101D8] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x101DC] mov v21.16b, v21.16b
  [0x101E0] add x16, x8, x15
  [0x101E4] ldr s20, [x16, #8] ;; misaligned with debug data
  [0x101E8] fmul s21, s21, s20
  [0x101EC] fadd s22, s22, s21
  [0x101F0] mov v22.16b, v22.16b
  [0x101F4] mov x9, x14
  [0x101F8] sub x9, x9, x15 ;; misaligned with debug data
  [0x101FC] fcmp s23, s22
  [0x10200] b.ge #0x10210
  [0x10204] add x9, x14, #8
  [0x10208] sub x9, x9, x15 ;; misaligned with debug data
  [0x1020C] mov x9, x9
  [0x10210] mov x9, x9
  [0x10214] mov x8, x14
  [0x10218] sub x8, x8, x15 ;; misaligned with debug data
  [0x1021C] cmp x9, x8
  [0x10220] b.eq #0x102fc
  [0x10224] adrp x16, #0x10000
  [0x10228] add x16, x16, #0
  [0x1022C] ldr w9, [x16]
  [0x10230] movz x8, #0xc
  [0x10234] add x16, x13, x15
  [0x10238] ldr w1, [x16, #0x6c] ;; misaligned with debug data
  [0x1023C] add x16, x1, x15
  [0x10240] ldr w1, [x16, #0x644] ;; misaligned with debug data
  [0x10244] add x8, x8, x1
  [0x10248] movz x1, #0x61c
  [0x1024C] add x16, x13, x15
  [0x10250] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x10254] add x1, x1, x2
  [0x10258] mov x7, x3
  [0x1025C] mov x8, x8
  [0x10260] mov x1, x1
  [0x10264] add x16, x8, x15
  [0x10268] ldr q22, [x16] ;; misaligned with debug data
  [0x1026C] add x16, x1, x15
  [0x10270] ldr q21, [x16] ;; misaligned with debug data
  [0x10274] adrp x16, #0x10000
  [0x10278] ldr q23, [x16, #0xff0]
  [0x1027C] fsub v22.4s, v22.4s, v21.4s
  [0x10280] ins v22.s[3], v23.s[3]
  [0x10284] add x16, x7, x15
  [0x10288] str q22, [x16] ;; misaligned with debug data
  [0x1028C] adrp x16, #0x11000
  [0x10290] ldr s23, [x16]
  [0x10294] mov v23.16b, v23.16b
  [0x10298] mov x9, x9
  [0x1029C] mov x7, x7
  [0x102A0] fmov w6, s23
  [0x102A4] sxtw x6, w6
  [0x102A8] add x9, x9, x15
  [0x102AC] stp x3, x5, [sp, #-0x10]!
  [0x102B0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102B4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102B8] blr x9 ;; misaligned with debug data
  [0x102BC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102C0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102C4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102C8] mov x0, x0
  [0x102CC] adrp x16, #0x11000
  [0x102D0] ldr s23, [x16, #4]
  [0x102D4] add x16, x3, x15
  [0x102D8] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x102DC] mov x9, x14
  [0x102E0] sub x9, x9, x15 ;; misaligned with debug data
  [0x102E4] fcmp s23, s22
  [0x102E8] b.ge #0x102f8
  [0x102EC] add x9, x14, #8
  [0x102F0] sub x9, x9, x15 ;; misaligned with debug data
  [0x102F4] mov x9, x9
  [0x102F8] mov x9, x9
  [0x102FC] mov x8, x14
  [0x10300] sub x8, x8, x15 ;; misaligned with debug data
  [0x10304] cmp x9, x8
  [0x10308] b.eq #0x107bc
  [0x1030C] adrp x16, #0x11000
  [0x10310] ldr s23, [x16, #8]
  [0x10314] add x16, x3, x15
  [0x10318] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x1031C] fcmp s23, s22
  [0x10320] b.ge #0x1048c
  [0x10324] add x6, sp, #0x20
  [0x10328] sub x6, x6, x15
  [0x1032C] mov x6, x6
  [0x10330] add x16, x6, x15
  [0x10334] str w13, [x16, #4] ;; misaligned with debug data
  [0x10338] movz x9, #0x2
  [0x1033C] add x16, x6, x15
  [0x10340] str w9, [x16, #8] ;; misaligned with debug data
  [0x10344] adrp x9, #0x10000
  [0x10348] add x9, x9, #0
  [0x1034C] add x16, x6, x15
  [0x10350] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x10354] add x16, x5, x15
  [0x10358] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x1035C] mov x9, x9
  [0x10360] add x16, x6, x15
  [0x10364] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x10368] add x16, x13, x15
  [0x1036C] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10370] add x16, x9, x15
  [0x10374] ldr s23, [x16, #0x19c] ;; misaligned with debug data
  [0x10378] mov v23.16b, v23.16b
  [0x1037C] movz x9, #0x3c
  [0x10380] add x16, x13, x15
  [0x10384] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10388] add x9, x9, x8
  [0x1038C] movz x8, #0x1c
  [0x10390] add x16, x13, x15
  [0x10394] ldr w1, [x16, #0x6c] ;; misaligned with debug data
  [0x10398] add x16, x1, x15
  [0x1039C] ldr w1, [x16, #0x1b0] ;; misaligned with debug data
  [0x103A0] add x8, x8, x1
  [0x103A4] mov x9, x9
  [0x103A8] mov x8, x8
  [0x103AC] adrp x16, #0x11000
  [0x103B0] ldr s22, [x16, #0xc]
  [0x103B4] mov v22.16b, v22.16b
  [0x103B8] mov v22.16b, v22.16b
  [0x103BC] add x16, x9, x15
  [0x103C0] ldr s21, [x16] ;; misaligned with debug data
  [0x103C4] mov v21.16b, v21.16b
  [0x103C8] add x16, x8, x15
  [0x103CC] ldr s20, [x16] ;; misaligned with debug data
  [0x103D0] fmul s21, s21, s20
  [0x103D4] fadd s22, s22, s21
  [0x103D8] mov v22.16b, v22.16b
  [0x103DC] mov v22.16b, v22.16b
  [0x103E0] add x16, x9, x15
  [0x103E4] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x103E8] mov v21.16b, v21.16b
  [0x103EC] add x16, x8, x15
  [0x103F0] ldr s20, [x16, #4] ;; misaligned with debug data
  [0x103F4] fmul s21, s21, s20
  [0x103F8] fadd s22, s22, s21
  [0x103FC] mov v22.16b, v22.16b
  [0x10400] mov v22.16b, v22.16b
  [0x10404] add x16, x9, x15
  [0x10408] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x1040C] mov v21.16b, v21.16b
  [0x10410] add x16, x8, x15
  [0x10414] ldr s20, [x16, #8] ;; misaligned with debug data
  [0x10418] fmul s21, s21, s20
  [0x1041C] fadd s22, s22, s21
  [0x10420] mov v22.16b, v22.16b
  [0x10424] adrp x16, #0x11000
  [0x10428] ldr s21, [x16, #0x10]
  [0x1042C] fsub s21, s21, s22
  [0x10430] fmax s23, s23, s21
  [0x10434] mov v23.16b, v23.16b
  [0x10438] fmov w9, s23
  [0x1043C] sxtw x9, w9
  [0x10440] add x16, x6, x15
  [0x10444] str x9, [x16, #0x18] ;; misaligned with debug data
  [0x10448] adrp x16, #0x10000
  [0x1044C] add x16, x16, #0
  [0x10450] ldr w9, [x16]
  [0x10454] mov x9, x9
  [0x10458] mov x7, x11
  [0x1045C] mov x6, x6
  [0x10460] add x9, x9, x15
  [0x10464] stp x3, x5, [sp, #-0x10]!
  [0x10468] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1046C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10470] blr x9 ;; misaligned with debug data
  [0x10474] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10478] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1047C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10480] mov x0, x0
  [0x10484] mov x0, x0
  [0x10488] b #0x10494
  [0x1048C] mov x0, x14
  [0x10490] sub x0, x0, x15 ;; misaligned with debug data
  [0x10494] movz x9, #0x1c
  [0x10498] add x16, x13, x15
  [0x1049C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x104A0] add x16, x8, x15
  [0x104A4] ldr w8, [x16, #0x1b0] ;; misaligned with debug data
  [0x104A8] add x9, x9, x8
  [0x104AC] add x8, sp, #0x70
  [0x104B0] sub x8, x8, x15
  [0x104B4] movz x1, #0x91c
  [0x104B8] add x16, x13, x15
  [0x104BC] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x104C0] add x1, x1, x2
  [0x104C4] movz x2, #0xc
  [0x104C8] add x16, x13, x15
  [0x104CC] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x104D0] add x2, x2, x6
  [0x104D4] mov x8, x8
  [0x104D8] mov x1, x1
  [0x104DC] mov x2, x2
  [0x104E0] add x16, x1, x15
  [0x104E4] ldr q22, [x16] ;; misaligned with debug data
  [0x104E8] add x16, x2, x15
  [0x104EC] ldr q21, [x16] ;; misaligned with debug data
  [0x104F0] adrp x16, #0x11000
  [0x104F4] ldr q23, [x16, #0x20]
  [0x104F8] fsub v22.4s, v22.4s, v21.4s
  [0x104FC] ins v22.s[3], v23.s[3]
  [0x10500] add x16, x8, x15
  [0x10504] str q22, [x16] ;; misaligned with debug data
  [0x10508] mov x9, x9
  [0x1050C] mov x8, x8
  [0x10510] adrp x16, #0x11000
  [0x10514] ldr s23, [x16, #0x30]
  [0x10518] mov v23.16b, v23.16b
  [0x1051C] mov v23.16b, v23.16b
  [0x10520] add x16, x9, x15
  [0x10524] ldr s22, [x16] ;; misaligned with debug data
  [0x10528] mov v22.16b, v22.16b
  [0x1052C] add x16, x8, x15
  [0x10530] ldr s21, [x16] ;; misaligned with debug data
  [0x10534] fmul s22, s22, s21
  [0x10538] fadd s23, s23, s22
  [0x1053C] mov v23.16b, v23.16b
  [0x10540] mov v23.16b, v23.16b
  [0x10544] add x16, x9, x15
  [0x10548] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x1054C] mov v22.16b, v22.16b
  [0x10550] add x16, x8, x15
  [0x10554] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x10558] fmul s22, s22, s21
  [0x1055C] fadd s23, s23, s22
  [0x10560] mov v23.16b, v23.16b
  [0x10564] mov v23.16b, v23.16b
  [0x10568] add x16, x9, x15
  [0x1056C] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x10570] mov v22.16b, v22.16b
  [0x10574] add x16, x8, x15
  [0x10578] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x1057C] fmul s22, s22, s21
  [0x10580] fadd s23, s23, s22
  [0x10584] mov v23.16b, v23.16b
  [0x10588] mov v23.16b, v23.16b
  [0x1058C] adrp x16, #0x10000
  [0x10590] add x16, x16, #0
  [0x10594] ldr w9, [x16]
  [0x10598] add x16, x9, x15
  [0x1059C] ldr s22, [x16, #0x90] ;; misaligned with debug data
  [0x105A0] fcmp s22, s23
  [0x105A4] b.ge #0x107a4
  [0x105A8] adrp x16, #0x10000
  [0x105AC] add x16, x16, #0
  [0x105B0] ldr w9, [x16]
  [0x105B4] adrp x6, #0x10000
  [0x105B8] add x6, x6, #0
  [0x105BC] mov x6, x6
  [0x105C0] add x16, x5, x15
  [0x105C4] ldr x2, [x16, #0x10] ;; misaligned with debug data
  [0x105C8] mov x2, x2
  [0x105CC] add x16, x13, x15
  [0x105D0] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x105D4] add x16, x8, x15
  [0x105D8] add x16, x16, #0x954 ;; misaligned with debug data
  [0x105DC] ldr x1, [x16] ;; misaligned with debug data
  [0x105E0] add x16, x13, x15
  [0x105E4] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x105E8] add x16, x8, x15
  [0x105EC] add x16, x16, #0x95c ;; misaligned with debug data
  [0x105F0] ldr x8, [x16] ;; misaligned with debug data
  [0x105F4] mov x9, x9
  [0x105F8] mov x7, x11
  [0x105FC] mov x6, x6
  [0x10600] mov x2, x2
  [0x10604] mov x1, x1
  [0x10608] mov x8, x8
  [0x1060C] add x9, x9, x15
  [0x10610] stp x3, x5, [sp, #-0x10]!
  [0x10614] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10618] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1061C] blr x9 ;; misaligned with debug data
  [0x10620] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10624] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10628] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1062C] mov x0, x0
  [0x10630] mov x0, x0
  [0x10634] mov x9, x14
  [0x10638] sub x9, x9, x15 ;; misaligned with debug data
  [0x1063C] cmp x0, x9
  [0x10640] b.eq #0x1067c
  [0x10644] add x16, x13, x15
  [0x10648] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x1064C] movz x8, #0x8008
  [0x10650] mov x9, x9
  [0x10654] and x9, x9, x8
  [0x10658] movz x8, #0
  [0x1065C] mov x0, x14
  [0x10660] sub x0, x0, x15 ;; misaligned with debug data
  [0x10664] cmp x9, x8
  [0x10668] b.ne #0x10678
  [0x1066C] add x0, x14, #8
  [0x10670] sub x0, x0, x15 ;; misaligned with debug data
  [0x10674] mov x0, x0
  [0x10678] mov x0, x0
  [0x1067C] mov x9, x14
  [0x10680] sub x9, x9, x15 ;; misaligned with debug data
  [0x10684] cmp x0, x9
  [0x10688] b.eq #0x10794
  [0x1068C] add x16, x13, x15
  [0x10690] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10694] add x16, x9, x15
  [0x10698] ldur q23, [x16, #0xc] ;; misaligned with debug data
  [0x1069C] mov v23.16b, v23.16b
  [0x106A0] add x16, x13, x15
  [0x106A4] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x106A8] add x16, x9, x15
  [0x106AC] add x16, x16, #0x4bc ;; misaligned with debug data
  [0x106B0] str q23, [x16] ;; misaligned with debug data
  [0x106B4] adrp x16, #0x10000
  [0x106B8] add x16, x16, #0
  [0x106BC] ldr w9, [x16]
  [0x106C0] movz x7, #0x1e
  [0x106C4] mov x9, x9
  [0x106C8] mov x7, x7
  [0x106CC] mov x6, x13
  [0x106D0] add x9, x9, x15
  [0x106D4] stp x3, x5, [sp, #-0x10]!
  [0x106D8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106DC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106E0] blr x9 ;; misaligned with debug data
  [0x106E4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106E8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106EC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x106F0] mov x3, x3
  [0x106F4] adrp x16, #0x10000
  [0x106F8] add x16, x16, #0
  [0x106FC] ldr w9, [x16]
  [0x10700] add x16, x13, x15
  [0x10704] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10708] adrp x16, #0x10000
  [0x1070C] add x16, x16, #0
  [0x10710] ldr w9, [x16]
  [0x10714] add x16, x9, x15
  [0x10718] ldr s23, [x16, #4] ;; misaligned with debug data
  [0x1071C] fmov w7, s23
  [0x10720] sxtw x7, w7
  [0x10724] adrp x16, #0x10000
  [0x10728] add x16, x16, #0
  [0x1072C] ldr w9, [x16]
  [0x10730] add x16, x9, x15
  [0x10734] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x10738] fmov w6, s23
  [0x1073C] sxtw x6, w6
  [0x10740] mov x2, x14
  [0x10744] sub x2, x2, x15 ;; misaligned with debug data
  [0x10748] mov x2, x2
  [0x1074C] adrp x16, #0x10000
  [0x10750] add x16, x16, #0
  [0x10754] ldr w9, [x16]
  [0x10758] mov x9, x9
  [0x1075C] mov x7, x7
  [0x10760] mov x6, x6
  [0x10764] mov x2, x2
  [0x10768] add x9, x9, x15
  [0x1076C] stp x3, x5, [sp, #-0x10]!
  [0x10770] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10774] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10778] blr x9 ;; misaligned with debug data
  [0x1077C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10780] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10784] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10788] mov x0, x0
  [0x1078C] mov x0, x0
  [0x10790] b #0x1079c
  [0x10794] mov x0, x14
  [0x10798] sub x0, x0, x15 ;; misaligned with debug data
  [0x1079C] mov x0, x0
  [0x107A0] b #0x107ac
  [0x107A4] mov x0, x14
  [0x107A8] sub x0, x0, x15 ;; misaligned with debug data
  [0x107AC] mov x0, x14
  [0x107B0] sub x0, x0, x15 ;; misaligned with debug data
  [0x107B4] mov x0, x0
  [0x107B8] b #0x10958
  [0x107BC] adrp x9, #0x10000
  [0x107C0] add x9, x9, #0
  [0x107C4] cmp x12, x9
  [0x107C8] b.ne #0x10950
  [0x107CC] adrp x16, #0x10000
  [0x107D0] add x16, x16, #0
  [0x107D4] ldr w3, [x16]
  [0x107D8] movz x9, #0x756a
  [0x107DC] movk x9, #0x706d, lsl #16
  [0x107E0] movk x9, #0x6c2d, lsl #32
  [0x107E4] movk x9, #0x6e6f, lsl #48
  [0x107E8] fmov d23, x9
  [0x107EC] movz x9, #0x67
  [0x107F0] fmov d24, x9
  [0x107F4] zip1 v24.2d, v23.2d, v24.2d
  [0x107F8] adrp x16, #0x10000
  [0x107FC] add x16, x16, #0
  [0x10800] ldr w9, [x16]
  [0x10804] mov x9, x9
  [0x10808] add x9, x9, x15
  [0x1080C] stp x3, x5, [sp, #-0x10]!
  [0x10810] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10814] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10818] blr x9 ;; misaligned with debug data
  [0x1081C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10820] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10824] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10828] mov x0, x0
  [0x1082C] adrp x16, #0x11000
  [0x10830] ldr s23, [x16, #0x34]
  [0x10834] adrp x16, #0x11000
  [0x10838] ldr s22, [x16, #0x38]
  [0x1083C] mov v23.16b, v23.16b
  [0x10840] fdiv s23, s23, s22
  [0x10844] mov v23.16b, v23.16b
  [0x10848] adrp x16, #0x11000
  [0x1084C] ldr s22, [x16, #0x3c]
  [0x10850] fmul s23, s23, s22
  [0x10854] fcvtzs w6, s23
  [0x10858] sxtw x6, w6
  [0x1085C] adrp x16, #0x11000
  [0x10860] ldr s23, [x16, #0x40]
  [0x10864] mov v23.16b, v23.16b
  [0x10868] movz x9, #0
  [0x1086C] scvtf s22, w9
  [0x10870] fmul s23, s23, s22
  [0x10874] fcvtzs w2, s23
  [0x10878] sxtw x2, w2
  [0x1087C] movz x1, #0
  [0x10880] movz x8, #0x1
  [0x10884] add x9, x14, #8
  [0x10888] sub x9, x9, x15 ;; misaligned with debug data
  [0x1088C] mov x3, x3
  [0x10890] mov v17.16b, v24.16b
  [0x10894] mov x7, x0
  [0x10898] mov x6, x6
  [0x1089C] mov x2, x2
  [0x108A0] mov x1, x1
  [0x108A4] mov x8, x8
  [0x108A8] mov x9, x9
  [0x108AC] add x3, x3, x15
  [0x108B0] stp x3, x5, [sp, #-0x10]!
  [0x108B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108BC] blr x3 ;; misaligned with debug data
  [0x108C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108CC] mov x0, x0
  [0x108D0] adrp x16, #0x10000
  [0x108D4] add x16, x16, #0
  [0x108D8] ldr w9, [x16]
  [0x108DC] add x16, x13, x15
  [0x108E0] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x108E4] add x16, x5, x15
  [0x108E8] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x108EC] mov x7, x7
  [0x108F0] add x16, x5, x15
  [0x108F4] ldr x6, [x16, #0x18] ;; misaligned with debug data
  [0x108F8] mov x6, x6
  [0x108FC] add x16, x5, x15
  [0x10900] ldr x2, [x16, #0x20] ;; misaligned with debug data
  [0x10904] mov x2, x2
  [0x10908] adrp x16, #0x10000
  [0x1090C] add x16, x16, #0
  [0x10910] ldr w9, [x16]
  [0x10914] mov x9, x9
  [0x10918] mov x7, x7
  [0x1091C] mov x6, x6
  [0x10920] mov x2, x2
  [0x10924] add x9, x9, x15
  [0x10928] stp x3, x5, [sp, #-0x10]!
  [0x1092C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10930] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10934] blr x9 ;; misaligned with debug data
  [0x10938] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1093C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10940] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10944] mov x0, x0
  [0x10948] mov x0, x0
  [0x1094C] b #0x10958
  [0x10950] mov x0, x14
  [0x10954] sub x0, x0, x15 ;; misaligned with debug data
  [0x10958] mov x0, x0
  [0x1095C] add sp, sp, #0x80
  [0x10960] ldr q24, [sp], #0x10
  [0x10964] ldp x29, x30, [sp], #0x10
  [0x10968] ret


[target-dangerous-event-handler]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] mov x5, x6
  [0x10014] mov x12, x2
  [0x10018] mov x11, x1
  [0x1001C] mov x9, x12
  [0x10020] adrp x8, #0x10000
  [0x10024] add x8, x8, #0
  [0x10028] cmp x9, x8
  [0x1002C] b.ne #0x1018c
  [0x10030] adrp x16, #0x10000
  [0x10034] add x16, x16, #0
  [0x10038] ldr w9, [x16]
  [0x1003C] add x16, x9, x15
  [0x10040] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10044] add x16, x11, x15
  [0x10048] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x1004C] mov x7, x7
  [0x10050] add x16, x13, x15
  [0x10054] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x10058] movz x2, #0xe0
  [0x1005C] mov x2, x2
  [0x10060] mov x9, x9
  [0x10064] mov x7, x7
  [0x10068] mov x6, x6
  [0x1006C] mov x2, x2
  [0x10070] add x9, x9, x15
  [0x10074] stp x3, x5, [sp, #-0x10]!
  [0x10078] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1007C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10080] blr x9 ;; misaligned with debug data
  [0x10084] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10088] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1008C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10090] mov x0, x0
  [0x10094] mov x9, x14
  [0x10098] sub x9, x9, x15 ;; misaligned with debug data
  [0x1009C] cmp x0, x9
  [0x100A0] b.eq #0x1013c
  [0x100A4] adrp x16, #0x10000
  [0x100A8] add x16, x16, #0
  [0x100AC] ldr w9, [x16]
  [0x100B0] add x16, x13, x15
  [0x100B4] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x100B8] add x16, x8, x15
  [0x100BC] ldr w6, [x16, #0x94c] ;; misaligned with debug data
  [0x100C0] mov x6, x6
  [0x100C4] add x16, x11, x15
  [0x100C8] ldr x2, [x16, #0x10] ;; misaligned with debug data
  [0x100CC] mov x2, x2
  [0x100D0] add x16, x13, x15
  [0x100D4] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x100D8] add x16, x8, x15
  [0x100DC] add x16, x16, #0x954 ;; misaligned with debug data
  [0x100E0] ldr x1, [x16] ;; misaligned with debug data
  [0x100E4] add x16, x13, x15
  [0x100E8] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x100EC] add x16, x8, x15
  [0x100F0] add x16, x16, #0x95c ;; misaligned with debug data
  [0x100F4] ldr x8, [x16] ;; misaligned with debug data
  [0x100F8] mov x9, x9
  [0x100FC] mov x7, x3
  [0x10100] mov x6, x6
  [0x10104] mov x2, x2
  [0x10108] mov x1, x1
  [0x1010C] mov x8, x8
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
  [0x10138] b #0x10184
  [0x1013C] adrp x16, #0x10000
  [0x10140] add x16, x16, #0
  [0x10144] ldr w9, [x16]
  [0x10148] mov x9, x9
  [0x1014C] mov x7, x3
  [0x10150] mov x6, x5
  [0x10154] mov x2, x12
  [0x10158] mov x1, x11
  [0x1015C] add x9, x9, x15
  [0x10160] stp x3, x5, [sp, #-0x10]!
  [0x10164] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10168] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1016C] blr x9 ;; misaligned with debug data
  [0x10170] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10174] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10178] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1017C] mov x0, x0
  [0x10180] mov x0, x0
  [0x10184] mov x0, x0
  [0x10188] b #0x102f0
  [0x1018C] adrp x8, #0x10000
  [0x10190] add x8, x8, #0
  [0x10194] mov x1, x14
  [0x10198] sub x1, x1, x15 ;; misaligned with debug data
  [0x1019C] cmp x9, x8
  [0x101A0] b.ne #0x101b0
  [0x101A4] add x1, x14, #8
  [0x101A8] sub x1, x1, x15 ;; misaligned with debug data
  [0x101AC] mov x1, x1
  [0x101B0] mov x8, x1
  [0x101B4] mov x1, x14
  [0x101B8] sub x1, x1, x15 ;; misaligned with debug data
  [0x101BC] cmp x8, x1
  [0x101C0] b.ne #0x10224
  [0x101C4] adrp x8, #0x10000
  [0x101C8] add x8, x8, #0
  [0x101CC] mov x1, x14
  [0x101D0] sub x1, x1, x15 ;; misaligned with debug data
  [0x101D4] cmp x9, x8
  [0x101D8] b.ne #0x101e8
  [0x101DC] add x1, x14, #8
  [0x101E0] sub x1, x1, x15 ;; misaligned with debug data
  [0x101E4] mov x1, x1
  [0x101E8] mov x8, x1
  [0x101EC] mov x1, x14
  [0x101F0] sub x1, x1, x15 ;; misaligned with debug data
  [0x101F4] cmp x8, x1
  [0x101F8] b.ne #0x10224
  [0x101FC] adrp x8, #0x10000
  [0x10200] add x8, x8, #0
  [0x10204] mov x1, x14
  [0x10208] sub x1, x1, x15 ;; misaligned with debug data
  [0x1020C] cmp x9, x8
  [0x10210] b.ne #0x10220
  [0x10214] add x1, x14, #8
  [0x10218] sub x1, x1, x15 ;; misaligned with debug data
  [0x1021C] mov x1, x1
  [0x10220] mov x8, x1
  [0x10224] mov x9, x14
  [0x10228] sub x9, x9, x15 ;; misaligned with debug data
  [0x1022C] cmp x8, x9
  [0x10230] b.eq #0x102a8
  [0x10234] adrp x16, #0x10000
  [0x10238] add x16, x16, #0
  [0x1023C] ldr w9, [x16]
  [0x10240] add x16, x11, x15
  [0x10244] ldr x6, [x16, #0x18] ;; misaligned with debug data
  [0x10248] mov x6, x6
  [0x1024C] add x16, x11, x15
  [0x10250] ldr x1, [x16, #0x10] ;; misaligned with debug data
  [0x10254] mov x1, x1
  [0x10258] adrp x16, #0x10000
  [0x1025C] add x16, x16, #0
  [0x10260] ldr w8, [x16]
  [0x10264] mov x9, x9
  [0x10268] mov x7, x12
  [0x1026C] mov x6, x6
  [0x10270] mov x2, x3
  [0x10274] mov x1, x1
  [0x10278] mov x8, x8
  [0x1027C] add x9, x9, x15
  [0x10280] stp x3, x5, [sp, #-0x10]!
  [0x10284] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10288] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1028C] blr x9 ;; misaligned with debug data
  [0x10290] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10294] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10298] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1029C] mov x0, x0
  [0x102A0] mov x0, x0
  [0x102A4] b #0x102f0
  [0x102A8] adrp x16, #0x10000
  [0x102AC] add x16, x16, #0
  [0x102B0] ldr w9, [x16]
  [0x102B4] mov x9, x9
  [0x102B8] mov x7, x3
  [0x102BC] mov x6, x5
  [0x102C0] mov x2, x12
  [0x102C4] mov x1, x11
  [0x102C8] add x9, x9, x15
  [0x102CC] stp x3, x5, [sp, #-0x10]!
  [0x102D0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102D4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102D8] blr x9 ;; misaligned with debug data
  [0x102DC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102E0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102E4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102E8] mov x0, x0
  [0x102EC] mov x0, x0
  [0x102F0] mov x0, x0
  [0x102F4] add sp, sp, #0x10
  [0x102F8] ldp x29, x30, [sp], #0x10
  [0x102FC] ret


[target-apply-tongue]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] str q25, [sp, #-0x10]!
  [0x10010] str q26, [sp, #-0x10]!
  [0x10014] sub sp, sp, #0x10
  [0x10018] mov x7, x7
  [0x1001C] add x16, x13, x15
  [0x10020] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10024] movz x8, #0x8
  [0x10028] mov x9, x9
  [0x1002C] and x9, x9, x8
  [0x10030] movz x8, #0
  [0x10034] cmp x9, x8
  [0x10038] b.ne #0x1032c
  [0x1003C] add x16, x13, x15
  [0x10040] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10044] mov x9, x9
  [0x10048] movz x8, #0x7000
  [0x1004C] orr x9, x9, x8
  [0x10050] add x16, x13, x15
  [0x10054] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10058] mov x3, sp
  [0x1005C] sub x3, x3, x15
  [0x10060] movz x9, #0xc
  [0x10064] add x16, x13, x15
  [0x10068] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x1006C] add x9, x9, x8
  [0x10070] mov x3, x3
  [0x10074] mov x7, x7
  [0x10078] mov x9, x9
  [0x1007C] add x16, x7, x15
  [0x10080] ldr q22, [x16] ;; misaligned with debug data
  [0x10084] add x16, x9, x15
  [0x10088] ldr q21, [x16] ;; misaligned with debug data
  [0x1008C] adrp x16, #0x12000
  [0x10090] ldr q23, [x16, #0xf90]
  [0x10094] fsub v22.4s, v22.4s, v21.4s
  [0x10098] ins v22.s[3], v23.s[3]
  [0x1009C] add x16, x3, x15
  [0x100A0] str q22, [x16] ;; misaligned with debug data
  [0x100A4] mov x3, x3
  [0x100A8] adrp x16, #0x10000
  [0x100AC] add x16, x16, #0
  [0x100B0] ldr w5, [x16]
  [0x100B4] adrp x16, #0x10000
  [0x100B8] add x16, x16, #0
  [0x100BC] ldr w9, [x16]
  [0x100C0] add x16, x9, x15
  [0x100C4] ldr s25, [x16, #0x240] ;; misaligned with debug data
  [0x100C8] adrp x16, #0x10000
  [0x100CC] add x16, x16, #0
  [0x100D0] ldr w9, [x16]
  [0x100D4] add x16, x9, x15
  [0x100D8] ldr s26, [x16, #0x244] ;; misaligned with debug data
  [0x100DC] adrp x16, #0x10000
  [0x100E0] add x16, x16, #0
  [0x100E4] ldr w9, [x16]
  [0x100E8] mov x9, x9
  [0x100EC] mov x7, x3
  [0x100F0] add x9, x9, x15
  [0x100F4] stp x3, x5, [sp, #-0x10]!
  [0x100F8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100FC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10100] blr x9 ;; misaligned with debug data
  [0x10104] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10108] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1010C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10110] mov x0, x0
  [0x10114] adrp x16, #0x12000
  [0x10118] ldr s23, [x16, #0xfa0]
  [0x1011C] mov v23.16b, v23.16b
  [0x10120] adrp x16, #0x12000
  [0x10124] ldr s22, [x16, #0xfa4]
  [0x10128] mov v22.16b, v22.16b
  [0x1012C] mov x5, x5
  [0x10130] fmov w7, s25
  [0x10134] sxtw x7, w7
  [0x10138] fmov w6, s26
  [0x1013C] sxtw x6, w6
  [0x10140] mov x2, x0
  [0x10144] fmov w1, s23
  [0x10148] sxtw x1, w1
  [0x1014C] fmov w8, s22
  [0x10150] sxtw x8, w8
  [0x10154] add x5, x5, x15
  [0x10158] stp x3, x5, [sp, #-0x10]!
  [0x1015C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10160] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10164] blr x5 ;; misaligned with debug data
  [0x10168] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1016C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10170] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10174] mov x0, x0
  [0x10178] add x16, x13, x15
  [0x1017C] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10180] add x16, x9, x15
  [0x10184] str w0, [x16, #0x494] ;; misaligned with debug data
  [0x10188] add x16, x13, x15
  [0x1018C] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10190] add x16, x9, x15
  [0x10194] ldrsw x9, [x16, #0x498] ;; misaligned with debug data
  [0x10198] movz x8, #0
  [0x1019C] cmp x9, x8
  [0x101A0] b.ne #0x101e0
  [0x101A4] movz x9, #0x47c
  [0x101A8] add x16, x13, x15
  [0x101AC] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x101B0] add x9, x9, x8
  [0x101B4] mov x9, x9
  [0x101B8] mov x8, x9
  [0x101BC] eor v24.16b, v24.16b, v24.16b
  [0x101C0] add x16, x8, x15
  [0x101C4] str q24, [x16] ;; misaligned with debug data
  [0x101C8] adrp x16, #0x12000
  [0x101CC] ldr s23, [x16, #0xfa8]
  [0x101D0] add x16, x9, x15
  [0x101D4] str s23, [x16, #0xc] ;; misaligned with debug data
  [0x101D8] mov x9, x9
  [0x101DC] b #0x101e8
  [0x101E0] mov x9, x14
  [0x101E4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101E8] adrp x16, #0x10000
  [0x101EC] add x16, x16, #0
  [0x101F0] ldr w9, [x16]
  [0x101F4] movz x2, #0x13c
  [0x101F8] add x16, x13, x15
  [0x101FC] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10200] add x2, x2, x8
  [0x10204] mov x9, x9
  [0x10208] mov x7, x3
  [0x1020C] mov x6, x3
  [0x10210] mov x2, x2
  [0x10214] add x9, x9, x15
  [0x10218] stp x3, x5, [sp, #-0x10]!
  [0x1021C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10220] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10224] blr x9 ;; misaligned with debug data
  [0x10228] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1022C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10230] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10234] mov x0, x0
  [0x10238] adrp x16, #0x10000
  [0x1023C] add x16, x16, #0
  [0x10240] ldr w9, [x16]
  [0x10244] adrp x16, #0x12000
  [0x10248] ldr s23, [x16, #0xfac]
  [0x1024C] mov v23.16b, v23.16b
  [0x10250] mov x9, x9
  [0x10254] mov x7, x3
  [0x10258] fmov w6, s23
  [0x1025C] sxtw x6, w6
  [0x10260] add x9, x9, x15
  [0x10264] stp x3, x5, [sp, #-0x10]!
  [0x10268] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1026C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10270] blr x9 ;; misaligned with debug data
  [0x10274] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10278] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1027C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10280] mov x0, x0
  [0x10284] movz x9, #0x47c
  [0x10288] add x16, x13, x15
  [0x1028C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10290] add x9, x9, x8
  [0x10294] movz x8, #0x47c
  [0x10298] add x16, x13, x15
  [0x1029C] ldr w1, [x16, #0x6c] ;; misaligned with debug data
  [0x102A0] add x8, x8, x1
  [0x102A4] mov x9, x9
  [0x102A8] mov x8, x8
  [0x102AC] mov x3, x3
  [0x102B0] add x16, x8, x15
  [0x102B4] ldr q22, [x16] ;; misaligned with debug data
  [0x102B8] add x16, x3, x15
  [0x102BC] ldr q21, [x16] ;; misaligned with debug data
  [0x102C0] adrp x16, #0x12000
  [0x102C4] ldr q23, [x16, #0xfb0]
  [0x102C8] fadd v22.4s, v22.4s, v21.4s
  [0x102CC] ins v22.s[3], v23.s[3]
  [0x102D0] add x16, x9, x15
  [0x102D4] str q22, [x16] ;; misaligned with debug data
  [0x102D8] adrp x16, #0x12000
  [0x102DC] ldr s23, [x16, #0xfc0]
  [0x102E0] add x16, x13, x15
  [0x102E4] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x102E8] add x16, x9, x15
  [0x102EC] str s23, [x16, #0x48c] ;; misaligned with debug data
  [0x102F0] add x16, x13, x15
  [0x102F4] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x102F8] add x16, x9, x15
  [0x102FC] ldrsw x9, [x16, #0x498] ;; misaligned with debug data
  [0x10300] mov x9, x9
  [0x10304] movz x8, #0x1
  [0x10308] add x9, x9, x8
  [0x1030C] add x16, x13, x15
  [0x10310] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10314] add x16, x8, x15
  [0x10318] str w9, [x16, #0x498] ;; misaligned with debug data
  [0x1031C] add x0, x14, #8
  [0x10320] sub x0, x0, x15 ;; misaligned with debug data
  [0x10324] mov x0, x0
  [0x10328] b #0x10334
  [0x1032C] mov x0, x14
  [0x10330] sub x0, x0, x15 ;; misaligned with debug data
  [0x10334] mov x0, x0
  [0x10338] add sp, sp, #0x10
  [0x1033C] ldr q26, [sp], #0x10
  [0x10340] ldr q25, [sp], #0x10
  [0x10344] ldr q24, [sp], #0x10
  [0x10348] ldp x29, x30, [sp], #0x10
  [0x1034C] ret


[target-send-attack]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x190
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] mov x12, x2
  [0x10018] mov x1, x1
  [0x1001C] mov x8, x8
  [0x10020] mov x9, sp
  [0x10024] sub x9, x9, x15
  [0x10028] mov x9, x9
  [0x1002C] add x16, x9, x15
  [0x10030] str w13, [x16, #4] ;; misaligned with debug data
  [0x10034] movz x2, #0x4
  [0x10038] add x16, x9, x15
  [0x1003C] str w2, [x16, #8] ;; misaligned with debug data
  [0x10040] adrp x2, #0x10000
  [0x10044] add x2, x2, #0
  [0x10048] add x16, x9, x15
  [0x1004C] str w2, [x16, #0xc] ;; misaligned with debug data
  [0x10050] mov x2, x12
  [0x10054] add x16, x9, x15
  [0x10058] str x2, [x16, #0x10] ;; misaligned with debug data
  [0x1005C] add x16, x9, x15
  [0x10060] str x6, [x16, #0x18] ;; misaligned with debug data
  [0x10064] mov x1, x1
  [0x10068] add x16, x9, x15
  [0x1006C] str x1, [x16, #0x20] ;; misaligned with debug data
  [0x10070] mov x8, x8
  [0x10074] add x16, x9, x15
  [0x10078] str x8, [x16, #0x28] ;; misaligned with debug data
  [0x1007C] adrp x16, #0x10000
  [0x10080] add x16, x16, #0
  [0x10084] ldr w8, [x16]
  [0x10088] mov x8, x8
  [0x1008C] mov x7, x7
  [0x10090] mov x6, x9
  [0x10094] add x8, x8, x15
  [0x10098] stp x3, x5, [sp, #-0x10]!
  [0x1009C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A4] blr x8 ;; misaligned with debug data
  [0x100A8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100AC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100B0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100B4] mov x0, x0
  [0x100B8] mov x5, x0
  [0x100BC] mov x9, x5
  [0x100C0] mov x8, x14
  [0x100C4] sub x8, x8, x15 ;; misaligned with debug data
  [0x100C8] cmp x9, x8
  [0x100CC] b.eq #0x100f8
  [0x100D0] adrp x9, #0x10000
  [0x100D4] add x9, x9, #0
  [0x100D8] mov x8, x14
  [0x100DC] sub x8, x8, x15 ;; misaligned with debug data
  [0x100E0] cmp x5, x9
  [0x100E4] b.eq #0x100f4
  [0x100E8] add x8, x14, #8
  [0x100EC] sub x8, x8, x15 ;; misaligned with debug data
  [0x100F0] mov x8, x8
  [0x100F4] mov x9, x8
  [0x100F8] mov x8, x14
  [0x100FC] sub x8, x8, x15 ;; misaligned with debug data
  [0x10100] cmp x9, x8
  [0x10104] b.eq #0x11800
  [0x10108] add x16, x13, x15
  [0x1010C] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10110] add x16, x9, x15
  [0x10114] ldr w9, [x16, #0x94c] ;; misaligned with debug data
  [0x10118] mov x9, x9
  [0x1011C] adrp x8, #0x10000
  [0x10120] add x8, x8, #0
  [0x10124] mov x1, x14
  [0x10128] sub x1, x1, x15 ;; misaligned with debug data
  [0x1012C] cmp x9, x8
  [0x10130] b.ne #0x10140
  [0x10134] add x1, x14, #8
  [0x10138] sub x1, x1, x15 ;; misaligned with debug data
  [0x1013C] mov x1, x1
  [0x10140] mov x8, x1
  [0x10144] mov x1, x14
  [0x10148] sub x1, x1, x15 ;; misaligned with debug data
  [0x1014C] cmp x8, x1
  [0x10150] b.ne #0x1017c
  [0x10154] adrp x8, #0x10000
  [0x10158] add x8, x8, #0
  [0x1015C] mov x1, x14
  [0x10160] sub x1, x1, x15 ;; misaligned with debug data
  [0x10164] cmp x9, x8
  [0x10168] b.ne #0x10178
  [0x1016C] add x1, x14, #8
  [0x10170] sub x1, x1, x15 ;; misaligned with debug data
  [0x10174] mov x1, x1
  [0x10178] mov x8, x1
  [0x1017C] mov x1, x14
  [0x10180] sub x1, x1, x15 ;; misaligned with debug data
  [0x10184] cmp x8, x1
  [0x10188] b.eq #0x105c0
  [0x1018C] add x16, x13, x15
  [0x10190] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x10194] movz x2, #0x40
  [0x10198] mov x2, x2
  [0x1019C] adrp x16, #0x10000
  [0x101A0] add x16, x16, #0
  [0x101A4] ldr w9, [x16]
  [0x101A8] add x16, x9, x15
  [0x101AC] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x101B0] mov x9, x9
  [0x101B4] mov x7, x12
  [0x101B8] mov x6, x6
  [0x101BC] mov x2, x2
  [0x101C0] add x9, x9, x15
  [0x101C4] stp x3, x5, [sp, #-0x10]!
  [0x101C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101D0] blr x9 ;; misaligned with debug data
  [0x101D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101E0] mov x0, x0
  [0x101E4] mov x11, x0
  [0x101E8] mov x9, x14
  [0x101EC] sub x9, x9, x15 ;; misaligned with debug data
  [0x101F0] cmp x11, x9
  [0x101F4] b.eq #0x10430
  [0x101F8] adrp x16, #0x10000
  [0x101FC] add x16, x16, #0
  [0x10200] ldr w7, [x16]
  [0x10204] adrp x16, #0x10000
  [0x10208] add x16, x16, #0
  [0x1020C] ldr w6, [x16]
  [0x10210] movz x2, #0x4000
  [0x10214] add x16, x7, x15
  [0x10218] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1021C] add x16, x9, x15
  [0x10220] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x10224] mov x9, x9
  [0x10228] mov x7, x7
  [0x1022C] mov x6, x6
  [0x10230] mov x2, x2
  [0x10234] add x9, x9, x15
  [0x10238] stp x3, x5, [sp, #-0x10]!
  [0x1023C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10240] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10244] blr x9 ;; misaligned with debug data
  [0x10248] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1024C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10250] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10254] mov x0, x0
  [0x10258] mov x3, x0
  [0x1025C] mov x3, x3
  [0x10260] str x3, [sp, #0xa0]
  [0x10264] mov x8, x14
  [0x10268] sub x8, x8, x15 ;; misaligned with debug data
  [0x1026C] ldr x9, [sp, #0xa0]
  [0x10270] cmp x9, x8
  [0x10274] b.eq #0x10420
  [0x10278] adrp x16, #0x10000
  [0x1027C] add x16, x16, #0
  [0x10280] ldr w9, [x16]
  [0x10284] add x16, x9, x15
  [0x10288] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x1028C] adrp x2, #0x10000
  [0x10290] add x2, x2, #0
  [0x10294] movz x1, #0x4000
  [0x10298] movk x1, #0x7000, lsl #16
  [0x1029C] mov x1, x1
  [0x102A0] mov x8, x9
  [0x102A4] ldr x9, [sp, #0xa0]
  [0x102A8] mov x7, x9
  [0x102AC] mov x6, x13
  [0x102B0] mov x2, x2
  [0x102B4] mov x1, x1
  [0x102B8] add x8, x8, x15
  [0x102BC] stp x3, x5, [sp, #-0x10]!
  [0x102C0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C8] blr x8 ;; misaligned with debug data
  [0x102CC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102D0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102D4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102D8] mov x0, x0
  [0x102DC] adrp x16, #0x10000
  [0x102E0] add x16, x16, #0
  [0x102E4] ldr w3, [x16]
  [0x102E8] mov x3, x3
  [0x102EC] str x3, [sp, #0x128]
  [0x102F0] adrp x16, #0x10000
  [0x102F4] add x16, x16, #0
  [0x102F8] ldr w10, [x16]
  [0x102FC] adrp x16, #0x10000
  [0x10300] add x16, x16, #0
  [0x10304] ldr w8, [x16]
  [0x10308] add x16, x8, x15
  [0x1030C] ldr w9, [x16, #0x1c] ;; misaligned with debug data
  [0x10310] str x9, [sp, #0x120]
  [0x10314] movz x9, #0xffff
  [0x10318] movk x9, #0xffff, lsl #16
  [0x1031C] movk x9, #0xffff, lsl #32
  [0x10320] movk x9, #0xffff, lsl #48
  [0x10324] str x9, [sp, #0x118]
  [0x10328] mov x3, x14
  [0x1032C] sub x3, x3, x15 ;; misaligned with debug data
  [0x10330] mov x3, x3
  [0x10334] str x3, [sp, #0x148]
  [0x10338] mov x3, x14
  [0x1033C] sub x3, x3, x15 ;; misaligned with debug data
  [0x10340] mov x3, x3
  [0x10344] str x3, [sp, #0x180]
  [0x10348] mov x3, x14
  [0x1034C] sub x3, x3, x15 ;; misaligned with debug data
  [0x10350] mov x3, x3
  [0x10354] adrp x16, #0x10000
  [0x10358] add x16, x16, #0
  [0x1035C] ldr w9, [x16]
  [0x10360] add x7, sp, #0x50
  [0x10364] sub x7, x7, x15
  [0x10368] add x16, x13, x15
  [0x1036C] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x10370] mov x9, x9
  [0x10374] mov x7, x7
  [0x10378] mov x6, x11
  [0x1037C] mov x2, x2
  [0x10380] mov x1, x12
  [0x10384] add x9, x9, x15
  [0x10388] stp x3, x5, [sp, #-0x10]!
  [0x1038C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10390] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10394] blr x9 ;; misaligned with debug data
  [0x10398] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1039C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103A4] mov x0, x0
  [0x103A8] ldr x9, [sp, #0x128]
  [0x103AC] mov x12, x9
  [0x103B0] ldr x9, [sp, #0xa0]
  [0x103B4] mov x7, x9
  [0x103B8] mov x6, x10
  [0x103BC] ldr x2, [sp, #0x120]
  [0x103C0] mov x2, x2
  [0x103C4] ldr x1, [sp, #0x118]
  [0x103C8] mov x1, x1
  [0x103CC] ldr x8, [sp, #0x148]
  [0x103D0] mov x8, x8
  [0x103D4] ldr x9, [sp, #0x180]
  [0x103D8] mov x9, x9
  [0x103DC] mov x10, x3
  [0x103E0] mov x11, x0
  [0x103E4] add x12, x12, x15
  [0x103E8] stp x3, x5, [sp, #-0x10]!
  [0x103EC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103F0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103F4] blr x12 ;; misaligned with debug data
  [0x103F8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103FC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10400] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10404] mov x0, x0
  [0x10408] ldr x9, [sp, #0xa0]
  [0x1040C] add x16, x9, x15
  [0x10410] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10414] mov x8, x8
  [0x10418] mov x9, x8
  [0x1041C] b #0x10428
  [0x10420] mov x9, x14
  [0x10424] sub x9, x9, x15 ;; misaligned with debug data
  [0x10428] mov x9, x9
  [0x1042C] b #0x104a8
  [0x10430] add x16, x13, x15
  [0x10434] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10438] add x16, x9, x15
  [0x1043C] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x10440] adrp x6, #0x10000
  [0x10444] add x6, x6, #0
  [0x10448] adrp x16, #0x14000
  [0x1044C] ldr s23, [x16, #0xf68]
  [0x10450] mov v23.16b, v23.16b
  [0x10454] movz x1, #0x4a
  [0x10458] add x16, x7, x15
  [0x1045C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10460] add x16, x9, x15
  [0x10464] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10468] mov x9, x9
  [0x1046C] mov x7, x7
  [0x10470] mov x6, x6
  [0x10474] fmov w2, s23
  [0x10478] sxtw x2, w2
  [0x1047C] mov x1, x1
  [0x10480] add x9, x9, x15
  [0x10484] stp x3, x5, [sp, #-0x10]!
  [0x10488] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1048C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10490] blr x9 ;; misaligned with debug data
  [0x10494] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10498] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1049C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104A0] mov x0, x0
  [0x104A4] mov x9, x0
  [0x104A8] add x16, x13, x15
  [0x104AC] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x104B0] add x16, x9, x15
  [0x104B4] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x104B8] add x16, x13, x15
  [0x104BC] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x104C0] add x16, x9, x15
  [0x104C4] ldr w6, [x16, #0x94c] ;; misaligned with debug data
  [0x104C8] adrp x16, #0x14000
  [0x104CC] ldr s23, [x16, #0xf6c]
  [0x104D0] mov v23.16b, v23.16b
  [0x104D4] movz x1, #0x4a
  [0x104D8] mov x8, x14
  [0x104DC] sub x8, x8, x15 ;; misaligned with debug data
  [0x104E0] movz x9, #0x7073
  [0x104E4] movk x9, #0x6e69, lsl #16
  [0x104E8] movk x9, #0x682d, lsl #32
  [0x104EC] movk x9, #0x7469, lsl #48
  [0x104F0] fmov d22, x9
  [0x104F4] movz x9, #0
  [0x104F8] fmov d17, x9
  [0x104FC] zip1 v17.2d, v22.2d, v17.2d
  [0x10500] add x16, x7, x15
  [0x10504] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10508] add x16, x9, x15
  [0x1050C] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10510] mov x9, x9
  [0x10514] mov x7, x7
  [0x10518] mov x6, x6
  [0x1051C] fmov w2, s23
  [0x10520] sxtw x2, w2
  [0x10524] mov x1, x1
  [0x10528] mov x8, x8
  [0x1052C] mov v17.16b, v17.16b
  [0x10530] add x9, x9, x15
  [0x10534] stp x3, x5, [sp, #-0x10]!
  [0x10538] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1053C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10540] blr x9 ;; misaligned with debug data
  [0x10544] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10548] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1054C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10550] mov x0, x0
  [0x10554] adrp x16, #0x10000
  [0x10558] add x16, x16, #0
  [0x1055C] ldr w9, [x16]
  [0x10560] adrp x16, #0x10000
  [0x10564] add x16, x16, #0
  [0x10568] ldr w8, [x16]
  [0x1056C] add x16, x8, x15
  [0x10570] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x10574] movz x6, #0x1
  [0x10578] movz x2, #0x7f
  [0x1057C] movz x1, #0x3c
  [0x10580] mov x9, x9
  [0x10584] mov x7, x7
  [0x10588] mov x6, x6
  [0x1058C] mov x2, x2
  [0x10590] mov x1, x1
  [0x10594] add x9, x9, x15
  [0x10598] stp x3, x5, [sp, #-0x10]!
  [0x1059C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x105A0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x105A4] blr x9 ;; misaligned with debug data
  [0x105A8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x105AC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x105B0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x105B4] mov x3, x3
  [0x105B8] mov x3, x3
  [0x105BC] b #0x117f8
  [0x105C0] adrp x8, #0x10000
  [0x105C4] add x8, x8, #0
  [0x105C8] cmp x9, x8
  [0x105CC] b.ne #0x10c3c
  [0x105D0] add x16, x13, x15
  [0x105D4] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x105D8] movz x2, #0x40
  [0x105DC] mov x2, x2
  [0x105E0] adrp x16, #0x10000
  [0x105E4] add x16, x16, #0
  [0x105E8] ldr w9, [x16]
  [0x105EC] add x16, x9, x15
  [0x105F0] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x105F4] mov x9, x9
  [0x105F8] mov x7, x12
  [0x105FC] mov x6, x6
  [0x10600] mov x2, x2
  [0x10604] add x9, x9, x15
  [0x10608] stp x3, x5, [sp, #-0x10]!
  [0x1060C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10610] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10614] blr x9 ;; misaligned with debug data
  [0x10618] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1061C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10620] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10624] mov x0, x0
  [0x10628] mov x11, x0
  [0x1062C] mov x9, x14
  [0x10630] sub x9, x9, x15 ;; misaligned with debug data
  [0x10634] cmp x11, x9
  [0x10638] b.eq #0x10874
  [0x1063C] adrp x16, #0x10000
  [0x10640] add x16, x16, #0
  [0x10644] ldr w7, [x16]
  [0x10648] adrp x16, #0x10000
  [0x1064C] add x16, x16, #0
  [0x10650] ldr w6, [x16]
  [0x10654] movz x2, #0x4000
  [0x10658] add x16, x7, x15
  [0x1065C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10660] add x16, x9, x15
  [0x10664] ldr w9, [x16, #0x48] ;; misaligned with debug data
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
  [0x10698] mov x0, x0
  [0x1069C] mov x3, x0
  [0x106A0] mov x3, x3
  [0x106A4] str x3, [sp, #0xb0]
  [0x106A8] mov x8, x14
  [0x106AC] sub x8, x8, x15 ;; misaligned with debug data
  [0x106B0] ldr x9, [sp, #0xb0]
  [0x106B4] cmp x9, x8
  [0x106B8] b.eq #0x10864
  [0x106BC] adrp x16, #0x10000
  [0x106C0] add x16, x16, #0
  [0x106C4] ldr w9, [x16]
  [0x106C8] add x16, x9, x15
  [0x106CC] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x106D0] adrp x2, #0x10000
  [0x106D4] add x2, x2, #0
  [0x106D8] movz x1, #0x4000
  [0x106DC] movk x1, #0x7000, lsl #16
  [0x106E0] mov x1, x1
  [0x106E4] mov x8, x9
  [0x106E8] ldr x9, [sp, #0xb0]
  [0x106EC] mov x7, x9
  [0x106F0] mov x6, x13
  [0x106F4] mov x2, x2
  [0x106F8] mov x1, x1
  [0x106FC] add x8, x8, x15
  [0x10700] stp x3, x5, [sp, #-0x10]!
  [0x10704] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10708] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1070C] blr x8 ;; misaligned with debug data
  [0x10710] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10714] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10718] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1071C] mov x0, x0
  [0x10720] adrp x16, #0x10000
  [0x10724] add x16, x16, #0
  [0x10728] ldr w3, [x16]
  [0x1072C] mov x3, x3
  [0x10730] str x3, [sp, #0xd8]
  [0x10734] adrp x16, #0x10000
  [0x10738] add x16, x16, #0
  [0x1073C] ldr w10, [x16]
  [0x10740] adrp x16, #0x10000
  [0x10744] add x16, x16, #0
  [0x10748] ldr w8, [x16]
  [0x1074C] add x16, x8, x15
  [0x10750] ldr w9, [x16, #0x20] ;; misaligned with debug data
  [0x10754] str x9, [sp, #0xe0]
  [0x10758] movz x9, #0xffff
  [0x1075C] movk x9, #0xffff, lsl #16
  [0x10760] movk x9, #0xffff, lsl #32
  [0x10764] movk x9, #0xffff, lsl #48
  [0x10768] str x9, [sp, #0xe8]
  [0x1076C] mov x3, x14
  [0x10770] sub x3, x3, x15 ;; misaligned with debug data
  [0x10774] mov x3, x3
  [0x10778] str x3, [sp, #0x150]
  [0x1077C] mov x3, x14
  [0x10780] sub x3, x3, x15 ;; misaligned with debug data
  [0x10784] mov x3, x3
  [0x10788] str x3, [sp, #0x188]
  [0x1078C] mov x3, x14
  [0x10790] sub x3, x3, x15 ;; misaligned with debug data
  [0x10794] mov x3, x3
  [0x10798] adrp x16, #0x10000
  [0x1079C] add x16, x16, #0
  [0x107A0] ldr w9, [x16]
  [0x107A4] add x7, sp, #0x60
  [0x107A8] sub x7, x7, x15
  [0x107AC] add x16, x13, x15
  [0x107B0] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x107B4] mov x9, x9
  [0x107B8] mov x7, x7
  [0x107BC] mov x6, x11
  [0x107C0] mov x2, x2
  [0x107C4] mov x1, x12
  [0x107C8] add x9, x9, x15
  [0x107CC] stp x3, x5, [sp, #-0x10]!
  [0x107D0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x107D4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x107D8] blr x9 ;; misaligned with debug data
  [0x107DC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x107E0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x107E4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x107E8] mov x0, x0
  [0x107EC] ldr x9, [sp, #0xd8]
  [0x107F0] mov x12, x9
  [0x107F4] ldr x9, [sp, #0xb0]
  [0x107F8] mov x7, x9
  [0x107FC] mov x6, x10
  [0x10800] ldr x2, [sp, #0xe0]
  [0x10804] mov x2, x2
  [0x10808] ldr x1, [sp, #0xe8]
  [0x1080C] mov x1, x1
  [0x10810] ldr x8, [sp, #0x150]
  [0x10814] mov x8, x8
  [0x10818] ldr x9, [sp, #0x188]
  [0x1081C] mov x9, x9
  [0x10820] mov x10, x3
  [0x10824] mov x11, x0
  [0x10828] add x12, x12, x15
  [0x1082C] stp x3, x5, [sp, #-0x10]!
  [0x10830] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10834] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10838] blr x12 ;; misaligned with debug data
  [0x1083C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10840] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10844] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10848] mov x0, x0
  [0x1084C] ldr x9, [sp, #0xb0]
  [0x10850] add x16, x9, x15
  [0x10854] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10858] mov x8, x8
  [0x1085C] mov x9, x8
  [0x10860] b #0x1086c
  [0x10864] mov x9, x14
  [0x10868] sub x9, x9, x15 ;; misaligned with debug data
  [0x1086C] mov x9, x9
  [0x10870] b #0x10b24
  [0x10874] add x16, x13, x15
  [0x10878] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x1087C] movz x2, #0x20
  [0x10880] mov x2, x2
  [0x10884] adrp x16, #0x10000
  [0x10888] add x16, x16, #0
  [0x1088C] ldr w9, [x16]
  [0x10890] add x16, x9, x15
  [0x10894] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10898] mov x9, x9
  [0x1089C] mov x7, x12
  [0x108A0] mov x6, x6
  [0x108A4] mov x2, x2
  [0x108A8] add x9, x9, x15
  [0x108AC] stp x3, x5, [sp, #-0x10]!
  [0x108B0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108B4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108B8] blr x9 ;; misaligned with debug data
  [0x108BC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108C0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108C4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108C8] mov x0, x0
  [0x108CC] mov x0, x0
  [0x108D0] mov x11, x0
  [0x108D4] mov x9, x14
  [0x108D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x108DC] cmp x0, x9
  [0x108E0] b.eq #0x10b1c
  [0x108E4] adrp x16, #0x10000
  [0x108E8] add x16, x16, #0
  [0x108EC] ldr w7, [x16]
  [0x108F0] adrp x16, #0x10000
  [0x108F4] add x16, x16, #0
  [0x108F8] ldr w6, [x16]
  [0x108FC] movz x2, #0x4000
  [0x10900] add x16, x7, x15
  [0x10904] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10908] add x16, x9, x15
  [0x1090C] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x10910] mov x9, x9
  [0x10914] mov x7, x7
  [0x10918] mov x6, x6
  [0x1091C] mov x2, x2
  [0x10920] add x9, x9, x15
  [0x10924] stp x3, x5, [sp, #-0x10]!
  [0x10928] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1092C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10930] blr x9 ;; misaligned with debug data
  [0x10934] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10938] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1093C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10940] mov x0, x0
  [0x10944] mov x3, x0
  [0x10948] mov x3, x3
  [0x1094C] str x3, [sp, #0xa8]
  [0x10950] mov x8, x14
  [0x10954] sub x8, x8, x15 ;; misaligned with debug data
  [0x10958] ldr x9, [sp, #0xa8]
  [0x1095C] cmp x9, x8
  [0x10960] b.eq #0x10b0c
  [0x10964] adrp x16, #0x10000
  [0x10968] add x16, x16, #0
  [0x1096C] ldr w9, [x16]
  [0x10970] add x16, x9, x15
  [0x10974] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10978] adrp x2, #0x10000
  [0x1097C] add x2, x2, #0
  [0x10980] movz x1, #0x4000
  [0x10984] movk x1, #0x7000, lsl #16
  [0x10988] mov x1, x1
  [0x1098C] mov x8, x9
  [0x10990] ldr x9, [sp, #0xa8]
  [0x10994] mov x7, x9
  [0x10998] mov x6, x13
  [0x1099C] mov x2, x2
  [0x109A0] mov x1, x1
  [0x109A4] add x8, x8, x15
  [0x109A8] stp x3, x5, [sp, #-0x10]!
  [0x109AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x109B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109B4] blr x8 ;; misaligned with debug data
  [0x109B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x109C4] mov x0, x0
  [0x109C8] adrp x16, #0x10000
  [0x109CC] add x16, x16, #0
  [0x109D0] ldr w3, [x16]
  [0x109D4] mov x3, x3
  [0x109D8] str x3, [sp, #0xc8]
  [0x109DC] adrp x16, #0x10000
  [0x109E0] add x16, x16, #0
  [0x109E4] ldr w10, [x16]
  [0x109E8] adrp x16, #0x10000
  [0x109EC] add x16, x16, #0
  [0x109F0] ldr w8, [x16]
  [0x109F4] add x16, x8, x15
  [0x109F8] ldr w9, [x16, #0x20] ;; misaligned with debug data
  [0x109FC] str x9, [sp, #0xf8]
  [0x10A00] movz x9, #0xffff
  [0x10A04] movk x9, #0xffff, lsl #16
  [0x10A08] movk x9, #0xffff, lsl #32
  [0x10A0C] movk x9, #0xffff, lsl #48
  [0x10A10] str x9, [sp, #0xf0]
  [0x10A14] mov x3, x14
  [0x10A18] sub x3, x3, x15 ;; misaligned with debug data
  [0x10A1C] mov x3, x3
  [0x10A20] str x3, [sp, #0x158]
  [0x10A24] mov x3, x14
  [0x10A28] sub x3, x3, x15 ;; misaligned with debug data
  [0x10A2C] mov x3, x3
  [0x10A30] str x3, [sp, #0x178]
  [0x10A34] mov x3, x14
  [0x10A38] sub x3, x3, x15 ;; misaligned with debug data
  [0x10A3C] mov x3, x3
  [0x10A40] adrp x16, #0x10000
  [0x10A44] add x16, x16, #0
  [0x10A48] ldr w9, [x16]
  [0x10A4C] add x7, sp, #0x70
  [0x10A50] sub x7, x7, x15
  [0x10A54] add x16, x13, x15
  [0x10A58] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x10A5C] mov x9, x9
  [0x10A60] mov x7, x7
  [0x10A64] mov x6, x11
  [0x10A68] mov x2, x2
  [0x10A6C] mov x1, x12
  [0x10A70] add x9, x9, x15
  [0x10A74] stp x3, x5, [sp, #-0x10]!
  [0x10A78] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A7C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A80] blr x9 ;; misaligned with debug data
  [0x10A84] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A88] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A8C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A90] mov x0, x0
  [0x10A94] ldr x9, [sp, #0xc8]
  [0x10A98] mov x12, x9
  [0x10A9C] ldr x9, [sp, #0xa8]
  [0x10AA0] mov x7, x9
  [0x10AA4] mov x6, x10
  [0x10AA8] ldr x2, [sp, #0xf8]
  [0x10AAC] mov x2, x2
  [0x10AB0] ldr x1, [sp, #0xf0]
  [0x10AB4] mov x1, x1
  [0x10AB8] ldr x8, [sp, #0x158]
  [0x10ABC] mov x8, x8
  [0x10AC0] ldr x9, [sp, #0x178]
  [0x10AC4] mov x9, x9
  [0x10AC8] mov x10, x3
  [0x10ACC] mov x11, x0
  [0x10AD0] add x12, x12, x15
  [0x10AD4] stp x3, x5, [sp, #-0x10]!
  [0x10AD8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10ADC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AE0] blr x12 ;; misaligned with debug data
  [0x10AE4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10AE8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10AEC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AF0] mov x0, x0
  [0x10AF4] ldr x9, [sp, #0xa8]
  [0x10AF8] add x16, x9, x15
  [0x10AFC] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10B00] mov x8, x8
  [0x10B04] mov x9, x8
  [0x10B08] b #0x10b14
  [0x10B0C] mov x9, x14
  [0x10B10] sub x9, x9, x15 ;; misaligned with debug data
  [0x10B14] mov x9, x9
  [0x10B18] b #0x10b24
  [0x10B1C] mov x9, x14
  [0x10B20] sub x9, x9, x15 ;; misaligned with debug data
  [0x10B24] add x16, x13, x15
  [0x10B28] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10B2C] add x16, x9, x15
  [0x10B30] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x10B34] add x16, x13, x15
  [0x10B38] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10B3C] add x16, x9, x15
  [0x10B40] ldr w6, [x16, #0x94c] ;; misaligned with debug data
  [0x10B44] adrp x16, #0x13000
  [0x10B48] ldr s23, [x16, #0xf70]
  [0x10B4C] mov v23.16b, v23.16b
  [0x10B50] movz x1, #0x17
  [0x10B54] mov x8, x14
  [0x10B58] sub x8, x8, x15 ;; misaligned with debug data
  [0x10B5C] movz x9, #0x7570
  [0x10B60] movk x9, #0x636e, lsl #16
  [0x10B64] movk x9, #0x2d68, lsl #32
  [0x10B68] movk x9, #0x6968, lsl #48
  [0x10B6C] fmov d22, x9
  [0x10B70] movz x9, #0x74
  [0x10B74] fmov d17, x9
  [0x10B78] zip1 v17.2d, v22.2d, v17.2d
  [0x10B7C] add x16, x7, x15
  [0x10B80] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10B84] add x16, x9, x15
  [0x10B88] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10B8C] mov x9, x9
  [0x10B90] mov x7, x7
  [0x10B94] mov x6, x6
  [0x10B98] fmov w2, s23
  [0x10B9C] sxtw x2, w2
  [0x10BA0] mov x1, x1
  [0x10BA4] mov x8, x8
  [0x10BA8] mov v17.16b, v17.16b
  [0x10BAC] add x9, x9, x15
  [0x10BB0] stp x3, x5, [sp, #-0x10]!
  [0x10BB4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10BB8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10BBC] blr x9 ;; misaligned with debug data
  [0x10BC0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10BC4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10BC8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10BCC] mov x0, x0
  [0x10BD0] adrp x16, #0x10000
  [0x10BD4] add x16, x16, #0
  [0x10BD8] ldr w9, [x16]
  [0x10BDC] adrp x16, #0x10000
  [0x10BE0] add x16, x16, #0
  [0x10BE4] ldr w8, [x16]
  [0x10BE8] add x16, x8, x15
  [0x10BEC] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x10BF0] movz x6, #0x1
  [0x10BF4] movz x2, #0xb2
  [0x10BF8] movz x1, #0x1e
  [0x10BFC] mov x9, x9
  [0x10C00] mov x7, x7
  [0x10C04] mov x6, x6
  [0x10C08] mov x2, x2
  [0x10C0C] mov x1, x1
  [0x10C10] add x9, x9, x15
  [0x10C14] stp x3, x5, [sp, #-0x10]!
  [0x10C18] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C1C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C20] blr x9 ;; misaligned with debug data
  [0x10C24] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C28] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C2C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C30] mov x3, x3
  [0x10C34] mov x3, x3
  [0x10C38] b #0x117f8
  [0x10C3C] adrp x8, #0x10000
  [0x10C40] add x8, x8, #0
  [0x10C44] cmp x9, x8
  [0x10C48] b.ne #0x10d64
  [0x10C4C] add x16, x13, x15
  [0x10C50] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10C54] add x16, x9, x15
  [0x10C58] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x10C5C] add x16, x13, x15
  [0x10C60] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10C64] add x16, x9, x15
  [0x10C68] ldr w6, [x16, #0x94c] ;; misaligned with debug data
  [0x10C6C] adrp x16, #0x13000
  [0x10C70] ldr s23, [x16, #0xf74]
  [0x10C74] mov v23.16b, v23.16b
  [0x10C78] movz x1, #0x4a
  [0x10C7C] mov x8, x14
  [0x10C80] sub x8, x8, x15 ;; misaligned with debug data
  [0x10C84] movz x9, #0x7570
  [0x10C88] movk x9, #0x636e, lsl #16
  [0x10C8C] movk x9, #0x2d68, lsl #32
  [0x10C90] movk x9, #0x6968, lsl #48
  [0x10C94] fmov d22, x9
  [0x10C98] movz x9, #0x74
  [0x10C9C] fmov d17, x9
  [0x10CA0] zip1 v17.2d, v22.2d, v17.2d
  [0x10CA4] add x16, x7, x15
  [0x10CA8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10CAC] add x16, x9, x15
  [0x10CB0] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10CB4] mov x9, x9
  [0x10CB8] mov x7, x7
  [0x10CBC] mov x6, x6
  [0x10CC0] fmov w2, s23
  [0x10CC4] sxtw x2, w2
  [0x10CC8] mov x1, x1
  [0x10CCC] mov x8, x8
  [0x10CD0] mov v17.16b, v17.16b
  [0x10CD4] add x9, x9, x15
  [0x10CD8] stp x3, x5, [sp, #-0x10]!
  [0x10CDC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CE0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CE4] blr x9 ;; misaligned with debug data
  [0x10CE8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10CEC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10CF0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10CF4] mov x0, x0
  [0x10CF8] adrp x16, #0x10000
  [0x10CFC] add x16, x16, #0
  [0x10D00] ldr w9, [x16]
  [0x10D04] adrp x16, #0x10000
  [0x10D08] add x16, x16, #0
  [0x10D0C] ldr w8, [x16]
  [0x10D10] add x16, x8, x15
  [0x10D14] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x10D18] movz x6, #0x1
  [0x10D1C] movz x2, #0x7f
  [0x10D20] movz x1, #0x1e
  [0x10D24] mov x9, x9
  [0x10D28] mov x7, x7
  [0x10D2C] mov x6, x6
  [0x10D30] mov x2, x2
  [0x10D34] mov x1, x1
  [0x10D38] add x9, x9, x15
  [0x10D3C] stp x3, x5, [sp, #-0x10]!
  [0x10D40] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D44] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D48] blr x9 ;; misaligned with debug data
  [0x10D4C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D50] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D54] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D58] mov x3, x3
  [0x10D5C] mov x3, x3
  [0x10D60] b #0x117f8
  [0x10D64] adrp x8, #0x10000
  [0x10D68] add x8, x8, #0
  [0x10D6C] cmp x9, x8
  [0x10D70] b.ne #0x11458
  [0x10D74] add x16, x13, x15
  [0x10D78] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x10D7C] movz x2, #0x40
  [0x10D80] mov x2, x2
  [0x10D84] adrp x16, #0x10000
  [0x10D88] add x16, x16, #0
  [0x10D8C] ldr w9, [x16]
  [0x10D90] add x16, x9, x15
  [0x10D94] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10D98] mov x9, x9
  [0x10D9C] mov x7, x12
  [0x10DA0] mov x6, x6
  [0x10DA4] mov x2, x2
  [0x10DA8] add x9, x9, x15
  [0x10DAC] stp x3, x5, [sp, #-0x10]!
  [0x10DB0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DB4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DB8] blr x9 ;; misaligned with debug data
  [0x10DBC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10DC0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10DC4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10DC8] mov x0, x0
  [0x10DCC] mov x11, x0
  [0x10DD0] mov x9, x14
  [0x10DD4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10DD8] cmp x11, x9
  [0x10DDC] b.eq #0x11018
  [0x10DE0] adrp x16, #0x10000
  [0x10DE4] add x16, x16, #0
  [0x10DE8] ldr w7, [x16]
  [0x10DEC] adrp x16, #0x10000
  [0x10DF0] add x16, x16, #0
  [0x10DF4] ldr w6, [x16]
  [0x10DF8] movz x2, #0x4000
  [0x10DFC] add x16, x7, x15
  [0x10E00] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10E04] add x16, x9, x15
  [0x10E08] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x10E0C] mov x9, x9
  [0x10E10] mov x7, x7
  [0x10E14] mov x6, x6
  [0x10E18] mov x2, x2
  [0x10E1C] add x9, x9, x15
  [0x10E20] stp x3, x5, [sp, #-0x10]!
  [0x10E24] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E28] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E2C] blr x9 ;; misaligned with debug data
  [0x10E30] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10E34] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10E38] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10E3C] mov x0, x0
  [0x10E40] mov x3, x0
  [0x10E44] mov x3, x3
  [0x10E48] str x3, [sp, #0xc0]
  [0x10E4C] mov x8, x14
  [0x10E50] sub x8, x8, x15 ;; misaligned with debug data
  [0x10E54] ldr x9, [sp, #0xc0]
  [0x10E58] cmp x9, x8
  [0x10E5C] b.eq #0x11008
  [0x10E60] adrp x16, #0x10000
  [0x10E64] add x16, x16, #0
  [0x10E68] ldr w9, [x16]
  [0x10E6C] add x16, x9, x15
  [0x10E70] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10E74] adrp x2, #0x10000
  [0x10E78] add x2, x2, #0
  [0x10E7C] movz x1, #0x4000
  [0x10E80] movk x1, #0x7000, lsl #16
  [0x10E84] mov x1, x1
  [0x10E88] mov x8, x9
  [0x10E8C] ldr x9, [sp, #0xc0]
  [0x10E90] mov x7, x9
  [0x10E94] mov x6, x13
  [0x10E98] mov x2, x2
  [0x10E9C] mov x1, x1
  [0x10EA0] add x8, x8, x15
  [0x10EA4] stp x3, x5, [sp, #-0x10]!
  [0x10EA8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10EAC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10EB0] blr x8 ;; misaligned with debug data
  [0x10EB4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10EB8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10EBC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10EC0] mov x0, x0
  [0x10EC4] adrp x16, #0x10000
  [0x10EC8] add x16, x16, #0
  [0x10ECC] ldr w3, [x16]
  [0x10ED0] mov x3, x3
  [0x10ED4] str x3, [sp, #0xd0]
  [0x10ED8] adrp x16, #0x10000
  [0x10EDC] add x16, x16, #0
  [0x10EE0] ldr w10, [x16]
  [0x10EE4] adrp x16, #0x10000
  [0x10EE8] add x16, x16, #0
  [0x10EEC] ldr w8, [x16]
  [0x10EF0] add x16, x8, x15
  [0x10EF4] ldr w9, [x16, #0x20] ;; misaligned with debug data
  [0x10EF8] str x9, [sp, #0x100]
  [0x10EFC] movz x9, #0xffff
  [0x10F00] movk x9, #0xffff, lsl #16
  [0x10F04] movk x9, #0xffff, lsl #32
  [0x10F08] movk x9, #0xffff, lsl #48
  [0x10F0C] str x9, [sp, #0x108]
  [0x10F10] mov x3, x14
  [0x10F14] sub x3, x3, x15 ;; misaligned with debug data
  [0x10F18] mov x3, x3
  [0x10F1C] str x3, [sp, #0x140]
  [0x10F20] mov x3, x14
  [0x10F24] sub x3, x3, x15 ;; misaligned with debug data
  [0x10F28] mov x3, x3
  [0x10F2C] str x3, [sp, #0x168]
  [0x10F30] mov x3, x14
  [0x10F34] sub x3, x3, x15 ;; misaligned with debug data
  [0x10F38] mov x3, x3
  [0x10F3C] adrp x16, #0x10000
  [0x10F40] add x16, x16, #0
  [0x10F44] ldr w9, [x16]
  [0x10F48] add x7, sp, #0x80
  [0x10F4C] sub x7, x7, x15
  [0x10F50] add x16, x13, x15
  [0x10F54] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x10F58] mov x9, x9
  [0x10F5C] mov x7, x7
  [0x10F60] mov x6, x11
  [0x10F64] mov x2, x2
  [0x10F68] mov x1, x12
  [0x10F6C] add x9, x9, x15
  [0x10F70] stp x3, x5, [sp, #-0x10]!
  [0x10F74] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F78] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F7C] blr x9 ;; misaligned with debug data
  [0x10F80] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10F84] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10F88] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10F8C] mov x0, x0
  [0x10F90] ldr x9, [sp, #0xd0]
  [0x10F94] mov x12, x9
  [0x10F98] ldr x9, [sp, #0xc0]
  [0x10F9C] mov x7, x9
  [0x10FA0] mov x6, x10
  [0x10FA4] ldr x2, [sp, #0x100]
  [0x10FA8] mov x2, x2
  [0x10FAC] ldr x1, [sp, #0x108]
  [0x10FB0] mov x1, x1
  [0x10FB4] ldr x8, [sp, #0x140]
  [0x10FB8] mov x8, x8
  [0x10FBC] ldr x9, [sp, #0x168]
  [0x10FC0] mov x9, x9
  [0x10FC4] mov x10, x3
  [0x10FC8] mov x11, x0
  [0x10FCC] add x12, x12, x15
  [0x10FD0] stp x3, x5, [sp, #-0x10]!
  [0x10FD4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10FD8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10FDC] blr x12 ;; misaligned with debug data
  [0x10FE0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10FE4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10FE8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10FEC] mov x0, x0
  [0x10FF0] ldr x9, [sp, #0xc0]
  [0x10FF4] add x16, x9, x15
  [0x10FF8] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10FFC] mov x8, x8
  [0x11000] mov x9, x8
  [0x11004] b #0x11010
  [0x11008] mov x9, x14
  [0x1100C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11010] mov x9, x9
  [0x11014] b #0x112c8
  [0x11018] add x16, x13, x15
  [0x1101C] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x11020] movz x2, #0x20
  [0x11024] mov x2, x2
  [0x11028] adrp x16, #0x11000
  [0x1102C] add x16, x16, #0
  [0x11030] ldr w9, [x16]
  [0x11034] add x16, x9, x15
  [0x11038] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x1103C] mov x9, x9
  [0x11040] mov x7, x12
  [0x11044] mov x6, x6
  [0x11048] mov x2, x2
  [0x1104C] add x9, x9, x15
  [0x11050] stp x3, x5, [sp, #-0x10]!
  [0x11054] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11058] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1105C] blr x9 ;; misaligned with debug data
  [0x11060] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11064] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11068] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1106C] mov x0, x0
  [0x11070] mov x0, x0
  [0x11074] mov x11, x0
  [0x11078] mov x9, x14
  [0x1107C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11080] cmp x0, x9
  [0x11084] b.eq #0x112c0
  [0x11088] adrp x16, #0x11000
  [0x1108C] add x16, x16, #0
  [0x11090] ldr w7, [x16]
  [0x11094] adrp x16, #0x11000
  [0x11098] add x16, x16, #0
  [0x1109C] ldr w6, [x16]
  [0x110A0] movz x2, #0x4000
  [0x110A4] add x16, x7, x15
  [0x110A8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x110AC] add x16, x9, x15
  [0x110B0] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x110B4] mov x9, x9
  [0x110B8] mov x7, x7
  [0x110BC] mov x6, x6
  [0x110C0] mov x2, x2
  [0x110C4] add x9, x9, x15
  [0x110C8] stp x3, x5, [sp, #-0x10]!
  [0x110CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x110D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x110D4] blr x9 ;; misaligned with debug data
  [0x110D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x110DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x110E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x110E4] mov x0, x0
  [0x110E8] mov x3, x0
  [0x110EC] mov x3, x3
  [0x110F0] str x3, [sp, #0xb8]
  [0x110F4] mov x8, x14
  [0x110F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x110FC] ldr x9, [sp, #0xb8]
  [0x11100] cmp x9, x8
  [0x11104] b.eq #0x112b0
  [0x11108] adrp x16, #0x11000
  [0x1110C] add x16, x16, #0
  [0x11110] ldr w9, [x16]
  [0x11114] add x16, x9, x15
  [0x11118] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x1111C] adrp x2, #0x11000
  [0x11120] add x2, x2, #0
  [0x11124] movz x1, #0x4000
  [0x11128] movk x1, #0x7000, lsl #16
  [0x1112C] mov x1, x1
  [0x11130] mov x8, x9
  [0x11134] ldr x9, [sp, #0xb8]
  [0x11138] mov x7, x9
  [0x1113C] mov x6, x13
  [0x11140] mov x2, x2
  [0x11144] mov x1, x1
  [0x11148] add x8, x8, x15
  [0x1114C] stp x3, x5, [sp, #-0x10]!
  [0x11150] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11154] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11158] blr x8 ;; misaligned with debug data
  [0x1115C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11160] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11164] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11168] mov x0, x0
  [0x1116C] adrp x16, #0x11000
  [0x11170] add x16, x16, #0
  [0x11174] ldr w3, [x16]
  [0x11178] mov x3, x3
  [0x1117C] str x3, [sp, #0x110]
  [0x11180] adrp x16, #0x11000
  [0x11184] add x16, x16, #0
  [0x11188] ldr w10, [x16]
  [0x1118C] adrp x16, #0x11000
  [0x11190] add x16, x16, #0
  [0x11194] ldr w8, [x16]
  [0x11198] add x16, x8, x15
  [0x1119C] ldr w9, [x16, #0x20] ;; misaligned with debug data
  [0x111A0] str x9, [sp, #0x130]
  [0x111A4] movz x9, #0xffff
  [0x111A8] movk x9, #0xffff, lsl #16
  [0x111AC] movk x9, #0xffff, lsl #32
  [0x111B0] movk x9, #0xffff, lsl #48
  [0x111B4] str x9, [sp, #0x138]
  [0x111B8] mov x3, x14
  [0x111BC] sub x3, x3, x15 ;; misaligned with debug data
  [0x111C0] mov x3, x3
  [0x111C4] str x3, [sp, #0x160]
  [0x111C8] mov x3, x14
  [0x111CC] sub x3, x3, x15 ;; misaligned with debug data
  [0x111D0] mov x3, x3
  [0x111D4] str x3, [sp, #0x170]
  [0x111D8] mov x3, x14
  [0x111DC] sub x3, x3, x15 ;; misaligned with debug data
  [0x111E0] mov x3, x3
  [0x111E4] adrp x16, #0x11000
  [0x111E8] add x16, x16, #0
  [0x111EC] ldr w9, [x16]
  [0x111F0] add x7, sp, #0x90
  [0x111F4] sub x7, x7, x15
  [0x111F8] add x16, x13, x15
  [0x111FC] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x11200] mov x9, x9
  [0x11204] mov x7, x7
  [0x11208] mov x6, x11
  [0x1120C] mov x2, x2
  [0x11210] mov x1, x12
  [0x11214] add x9, x9, x15
  [0x11218] stp x3, x5, [sp, #-0x10]!
  [0x1121C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11220] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11224] blr x9 ;; misaligned with debug data
  [0x11228] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1122C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11230] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11234] mov x0, x0
  [0x11238] ldr x9, [sp, #0x110]
  [0x1123C] mov x12, x9
  [0x11240] ldr x9, [sp, #0xb8]
  [0x11244] mov x7, x9
  [0x11248] mov x6, x10
  [0x1124C] ldr x2, [sp, #0x130]
  [0x11250] mov x2, x2
  [0x11254] ldr x1, [sp, #0x138]
  [0x11258] mov x1, x1
  [0x1125C] ldr x8, [sp, #0x160]
  [0x11260] mov x8, x8
  [0x11264] ldr x9, [sp, #0x170]
  [0x11268] mov x9, x9
  [0x1126C] mov x10, x3
  [0x11270] mov x11, x0
  [0x11274] add x12, x12, x15
  [0x11278] stp x3, x5, [sp, #-0x10]!
  [0x1127C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11280] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11284] blr x12 ;; misaligned with debug data
  [0x11288] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1128C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11290] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11294] mov x0, x0
  [0x11298] ldr x9, [sp, #0xb8]
  [0x1129C] add x16, x9, x15
  [0x112A0] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x112A4] mov x8, x8
  [0x112A8] mov x9, x8
  [0x112AC] b #0x112b8
  [0x112B0] mov x9, x14
  [0x112B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x112B8] mov x9, x9
  [0x112BC] b #0x112c8
  [0x112C0] mov x9, x14
  [0x112C4] sub x9, x9, x15 ;; misaligned with debug data
  [0x112C8] add x16, x13, x15
  [0x112CC] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x112D0] add x16, x9, x15
  [0x112D4] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x112D8] adrp x6, #0x11000
  [0x112DC] add x6, x6, #0
  [0x112E0] adrp x16, #0x14000
  [0x112E4] ldr s23, [x16, #0xf78]
  [0x112E8] mov v23.16b, v23.16b
  [0x112EC] movz x1, #0x17
  [0x112F0] add x16, x7, x15
  [0x112F4] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x112F8] add x16, x9, x15
  [0x112FC] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x11300] mov x9, x9
  [0x11304] mov x7, x7
  [0x11308] mov x6, x6
  [0x1130C] fmov w2, s23
  [0x11310] sxtw x2, w2
  [0x11314] mov x1, x1
  [0x11318] add x9, x9, x15
  [0x1131C] stp x3, x5, [sp, #-0x10]!
  [0x11320] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11324] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11328] blr x9 ;; misaligned with debug data
  [0x1132C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11330] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11334] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11338] mov x0, x0
  [0x1133C] add x16, x13, x15
  [0x11340] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x11344] add x16, x9, x15
  [0x11348] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x1134C] add x16, x13, x15
  [0x11350] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x11354] add x16, x9, x15
  [0x11358] ldr w6, [x16, #0x94c] ;; misaligned with debug data
  [0x1135C] adrp x16, #0x14000
  [0x11360] ldr s23, [x16, #0xf7c]
  [0x11364] mov v23.16b, v23.16b
  [0x11368] movz x1, #0x17
  [0x1136C] mov x8, x14
  [0x11370] sub x8, x8, x15 ;; misaligned with debug data
  [0x11374] movz x9, #0x7075
  [0x11378] movk x9, #0x6570, lsl #16
  [0x1137C] movk x9, #0x6372, lsl #32
  [0x11380] movk x9, #0x7475, lsl #48
  [0x11384] fmov d22, x9
  [0x11388] movz x9, #0x682d
  [0x1138C] movk x9, #0x7469, lsl #16
  [0x11390] fmov d17, x9
  [0x11394] zip1 v17.2d, v22.2d, v17.2d
  [0x11398] add x16, x7, x15
  [0x1139C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x113A0] add x16, x9, x15
  [0x113A4] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x113A8] mov x9, x9
  [0x113AC] mov x7, x7
  [0x113B0] mov x6, x6
  [0x113B4] fmov w2, s23
  [0x113B8] sxtw x2, w2
  [0x113BC] mov x1, x1
  [0x113C0] mov x8, x8
  [0x113C4] mov v17.16b, v17.16b
  [0x113C8] add x9, x9, x15
  [0x113CC] stp x3, x5, [sp, #-0x10]!
  [0x113D0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x113D4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x113D8] blr x9 ;; misaligned with debug data
  [0x113DC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x113E0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x113E4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x113E8] mov x0, x0
  [0x113EC] adrp x16, #0x11000
  [0x113F0] add x16, x16, #0
  [0x113F4] ldr w9, [x16]
  [0x113F8] adrp x16, #0x11000
  [0x113FC] add x16, x16, #0
  [0x11400] ldr w8, [x16]
  [0x11404] add x16, x8, x15
  [0x11408] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x1140C] movz x6, #0x1
  [0x11410] movz x2, #0xb2
  [0x11414] movz x1, #0x1e
  [0x11418] mov x9, x9
  [0x1141C] mov x7, x7
  [0x11420] mov x6, x6
  [0x11424] mov x2, x2
  [0x11428] mov x1, x1
  [0x1142C] add x9, x9, x15
  [0x11430] stp x3, x5, [sp, #-0x10]!
  [0x11434] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11438] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1143C] blr x9 ;; misaligned with debug data
  [0x11440] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11444] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11448] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1144C] mov x3, x3
  [0x11450] mov x3, x3
  [0x11454] b #0x117f8
  [0x11458] adrp x8, #0x11000
  [0x1145C] add x8, x8, #0
  [0x11460] mov x1, x14
  [0x11464] sub x1, x1, x15 ;; misaligned with debug data
  [0x11468] cmp x9, x8
  [0x1146C] b.ne #0x1147c
  [0x11470] add x1, x14, #8
  [0x11474] sub x1, x1, x15 ;; misaligned with debug data
  [0x11478] mov x1, x1
  [0x1147C] mov x8, x1
  [0x11480] mov x1, x14
  [0x11484] sub x1, x1, x15 ;; misaligned with debug data
  [0x11488] cmp x8, x1
  [0x1148C] b.ne #0x114b8
  [0x11490] adrp x8, #0x11000
  [0x11494] add x8, x8, #0
  [0x11498] mov x1, x14
  [0x1149C] sub x1, x1, x15 ;; misaligned with debug data
  [0x114A0] cmp x9, x8
  [0x114A4] b.ne #0x114b4
  [0x114A8] add x1, x14, #8
  [0x114AC] sub x1, x1, x15 ;; misaligned with debug data
  [0x114B0] mov x1, x1
  [0x114B4] mov x8, x1
  [0x114B8] mov x1, x14
  [0x114BC] sub x1, x1, x15 ;; misaligned with debug data
  [0x114C0] cmp x8, x1
  [0x114C4] b.eq #0x116c8
  [0x114C8] add x16, x13, x15
  [0x114CC] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x114D0] add x16, x9, x15
  [0x114D4] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x114D8] adrp x6, #0x11000
  [0x114DC] add x6, x6, #0
  [0x114E0] adrp x16, #0x14000
  [0x114E4] ldr s23, [x16, #0xf80]
  [0x114E8] mov v23.16b, v23.16b
  [0x114EC] movz x1, #0x17
  [0x114F0] add x16, x7, x15
  [0x114F4] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x114F8] add x16, x9, x15
  [0x114FC] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x11500] mov x9, x9
  [0x11504] mov x7, x7
  [0x11508] mov x6, x6
  [0x1150C] fmov w2, s23
  [0x11510] sxtw x2, w2
  [0x11514] mov x1, x1
  [0x11518] add x9, x9, x15
  [0x1151C] stp x3, x5, [sp, #-0x10]!
  [0x11520] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11524] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11528] blr x9 ;; misaligned with debug data
  [0x1152C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11530] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11534] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11538] mov x0, x0
  [0x1153C] add x16, x13, x15
  [0x11540] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x11544] add x16, x9, x15
  [0x11548] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x1154C] adrp x6, #0x11000
  [0x11550] add x6, x6, #0
  [0x11554] adrp x16, #0x14000
  [0x11558] ldr s23, [x16, #0xf84]
  [0x1155C] mov v23.16b, v23.16b
  [0x11560] movz x1, #0x11
  [0x11564] add x16, x7, x15
  [0x11568] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1156C] add x16, x9, x15
  [0x11570] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x11574] mov x9, x9
  [0x11578] mov x7, x7
  [0x1157C] mov x6, x6
  [0x11580] fmov w2, s23
  [0x11584] sxtw x2, w2
  [0x11588] mov x1, x1
  [0x1158C] add x9, x9, x15
  [0x11590] stp x3, x5, [sp, #-0x10]!
  [0x11594] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11598] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1159C] blr x9 ;; misaligned with debug data
  [0x115A0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x115A4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x115A8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x115AC] mov x0, x0
  [0x115B0] add x16, x13, x15
  [0x115B4] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x115B8] add x16, x9, x15
  [0x115BC] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x115C0] add x16, x13, x15
  [0x115C4] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x115C8] add x16, x9, x15
  [0x115CC] ldr w6, [x16, #0x94c] ;; misaligned with debug data
  [0x115D0] adrp x16, #0x14000
  [0x115D4] ldr s23, [x16, #0xf88]
  [0x115D8] mov v23.16b, v23.16b
  [0x115DC] movz x1, #0x17
  [0x115E0] mov x8, x14
  [0x115E4] sub x8, x8, x15 ;; misaligned with debug data
  [0x115E8] movz x9, #0x6c66
  [0x115EC] movk x9, #0x706f, lsl #16
  [0x115F0] movk x9, #0x682d, lsl #32
  [0x115F4] movk x9, #0x7469, lsl #48
  [0x115F8] fmov d22, x9
  [0x115FC] movz x9, #0
  [0x11600] fmov d17, x9
  [0x11604] zip1 v17.2d, v22.2d, v17.2d
  [0x11608] add x16, x7, x15
  [0x1160C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11610] add x16, x9, x15
  [0x11614] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x11618] mov x9, x9
  [0x1161C] mov x7, x7
  [0x11620] mov x6, x6
  [0x11624] fmov w2, s23
  [0x11628] sxtw x2, w2
  [0x1162C] mov x1, x1
  [0x11630] mov x8, x8
  [0x11634] mov v17.16b, v17.16b
  [0x11638] add x9, x9, x15
  [0x1163C] stp x3, x5, [sp, #-0x10]!
  [0x11640] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11644] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11648] blr x9 ;; misaligned with debug data
  [0x1164C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11650] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11654] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11658] mov x0, x0
  [0x1165C] adrp x16, #0x11000
  [0x11660] add x16, x16, #0
  [0x11664] ldr w9, [x16]
  [0x11668] adrp x16, #0x11000
  [0x1166C] add x16, x16, #0
  [0x11670] ldr w8, [x16]
  [0x11674] add x16, x8, x15
  [0x11678] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x1167C] movz x6, #0x1
  [0x11680] movz x2, #0xb2
  [0x11684] movz x1, #0x1e
  [0x11688] mov x9, x9
  [0x1168C] mov x7, x7
  [0x11690] mov x6, x6
  [0x11694] mov x2, x2
  [0x11698] mov x1, x1
  [0x1169C] add x9, x9, x15
  [0x116A0] stp x3, x5, [sp, #-0x10]!
  [0x116A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x116A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x116AC] blr x9 ;; misaligned with debug data
  [0x116B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x116B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x116B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x116BC] mov x3, x3
  [0x116C0] mov x3, x3
  [0x116C4] b #0x117f8
  [0x116C8] adrp x8, #0x11000
  [0x116CC] add x8, x8, #0
  [0x116D0] cmp x9, x8
  [0x116D4] b.ne #0x117f0
  [0x116D8] add x16, x13, x15
  [0x116DC] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x116E0] add x16, x9, x15
  [0x116E4] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x116E8] add x16, x13, x15
  [0x116EC] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x116F0] add x16, x9, x15
  [0x116F4] ldr w6, [x16, #0x94c] ;; misaligned with debug data
  [0x116F8] adrp x16, #0x13000
  [0x116FC] ldr s23, [x16, #0xf8c]
  [0x11700] mov v23.16b, v23.16b
  [0x11704] movz x1, #0x17
  [0x11708] mov x8, x14
  [0x1170C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11710] movz x9, #0x7570
  [0x11714] movk x9, #0x636e, lsl #16
  [0x11718] movk x9, #0x2d68, lsl #32
  [0x1171C] movk x9, #0x6968, lsl #48
  [0x11720] fmov d22, x9
  [0x11724] movz x9, #0x74
  [0x11728] fmov d17, x9
  [0x1172C] zip1 v17.2d, v22.2d, v17.2d
  [0x11730] add x16, x7, x15
  [0x11734] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11738] add x16, x9, x15
  [0x1173C] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x11740] mov x9, x9
  [0x11744] mov x7, x7
  [0x11748] mov x6, x6
  [0x1174C] fmov w2, s23
  [0x11750] sxtw x2, w2
  [0x11754] mov x1, x1
  [0x11758] mov x8, x8
  [0x1175C] mov v17.16b, v17.16b
  [0x11760] add x9, x9, x15
  [0x11764] stp x3, x5, [sp, #-0x10]!
  [0x11768] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1176C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11770] blr x9 ;; misaligned with debug data
  [0x11774] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11778] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1177C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11780] mov x0, x0
  [0x11784] adrp x16, #0x11000
  [0x11788] add x16, x16, #0
  [0x1178C] ldr w9, [x16]
  [0x11790] adrp x16, #0x11000
  [0x11794] add x16, x16, #0
  [0x11798] ldr w8, [x16]
  [0x1179C] add x16, x8, x15
  [0x117A0] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x117A4] movz x6, #0x1
  [0x117A8] movz x2, #0xff
  [0x117AC] movz x1, #0x3c
  [0x117B0] mov x9, x9
  [0x117B4] mov x7, x7
  [0x117B8] mov x6, x6
  [0x117BC] mov x2, x2
  [0x117C0] mov x1, x1
  [0x117C4] add x9, x9, x15
  [0x117C8] stp x3, x5, [sp, #-0x10]!
  [0x117CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x117D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x117D4] blr x9 ;; misaligned with debug data
  [0x117D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x117DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x117E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x117E4] mov x3, x3
  [0x117E8] mov x3, x3
  [0x117EC] b #0x117f8
  [0x117F0] mov x3, x14
  [0x117F4] sub x3, x3, x15 ;; misaligned with debug data
  [0x117F8] mov x3, x3
  [0x117FC] b #0x11808
  [0x11800] mov x3, x14
  [0x11804] sub x3, x3, x15 ;; misaligned with debug data
  [0x11808] mov x5, x5
  [0x1180C] mov x0, x5
  [0x11810] add sp, sp, #0x190
  [0x11814] ldp x29, x30, [sp], #0x10
  [0x11818] ret


[target-standard-event-handler]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] mov x6, x6
  [0x10014] mov x2, x2
  [0x10018] mov x1, x1
  [0x1001C] mov x9, x2
  [0x10020] adrp x8, #0x10000
  [0x10024] add x8, x8, #0
  [0x10028] mov x7, x14
  [0x1002C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10030] cmp x9, x8
  [0x10034] b.ne #0x10044
  [0x10038] add x7, x14, #8
  [0x1003C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10040] mov x7, x7
  [0x10044] mov x8, x7
  [0x10048] mov x7, x14
  [0x1004C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10050] cmp x8, x7
  [0x10054] b.ne #0x100b8
  [0x10058] adrp x8, #0x10000
  [0x1005C] add x8, x8, #0
  [0x10060] mov x7, x14
  [0x10064] sub x7, x7, x15 ;; misaligned with debug data
  [0x10068] cmp x9, x8
  [0x1006C] b.ne #0x1007c
  [0x10070] add x7, x14, #8
  [0x10074] sub x7, x7, x15 ;; misaligned with debug data
  [0x10078] mov x7, x7
  [0x1007C] mov x8, x7
  [0x10080] mov x7, x14
  [0x10084] sub x7, x7, x15 ;; misaligned with debug data
  [0x10088] cmp x8, x7
  [0x1008C] b.ne #0x100b8
  [0x10090] adrp x8, #0x10000
  [0x10094] add x8, x8, #0
  [0x10098] mov x7, x14
  [0x1009C] sub x7, x7, x15 ;; misaligned with debug data
  [0x100A0] cmp x9, x8
  [0x100A4] b.ne #0x100b4
  [0x100A8] add x7, x14, #8
  [0x100AC] sub x7, x7, x15 ;; misaligned with debug data
  [0x100B0] mov x7, x7
  [0x100B4] mov x8, x7
  [0x100B8] mov x7, x14
  [0x100BC] sub x7, x7, x15 ;; misaligned with debug data
  [0x100C0] cmp x8, x7
  [0x100C4] b.eq #0x1013c
  [0x100C8] adrp x16, #0x10000
  [0x100CC] add x16, x16, #0
  [0x100D0] ldr w9, [x16]
  [0x100D4] add x16, x1, x15
  [0x100D8] ldr x6, [x16, #0x18] ;; misaligned with debug data
  [0x100DC] mov x6, x6
  [0x100E0] add x16, x1, x15
  [0x100E4] ldr x1, [x16, #0x10] ;; misaligned with debug data
  [0x100E8] mov x1, x1
  [0x100EC] adrp x16, #0x10000
  [0x100F0] add x16, x16, #0
  [0x100F4] ldr w8, [x16]
  [0x100F8] mov x9, x9
  [0x100FC] mov x7, x2
  [0x10100] mov x6, x6
  [0x10104] mov x2, x3
  [0x10108] mov x1, x1
  [0x1010C] mov x8, x8
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
  [0x10138] b #0x116cc
  [0x1013C] adrp x8, #0x10000
  [0x10140] add x8, x8, #0
  [0x10144] cmp x9, x8
  [0x10148] b.ne #0x102fc
  [0x1014C] add x16, x13, x15
  [0x10150] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x10154] add x16, x9, x15
  [0x10158] ldr w9, [x16] ;; misaligned with debug data
  [0x1015C] adrp x8, #0x10000
  [0x10160] add x8, x8, #0
  [0x10164] cmp x9, x8
  [0x10168] b.eq #0x102ec
  [0x1016C] adrp x16, #0x10000
  [0x10170] add x16, x16, #0
  [0x10174] ldr w9, [x16]
  [0x10178] movz x7, #0x14c
  [0x1017C] add x7, x7, x13
  [0x10180] mov x7, x7
  [0x10184] add x16, x1, x15
  [0x10188] ldr x6, [x16, #0x18] ;; misaligned with debug data
  [0x1018C] mov x6, x6
  [0x10190] movz x2, #0x68
  [0x10194] mov x9, x9
  [0x10198] mov x7, x7
  [0x1019C] mov x6, x6
  [0x101A0] mov x2, x2
  [0x101A4] add x9, x9, x15
  [0x101A8] stp x3, x5, [sp, #-0x10]!
  [0x101AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101B4] blr x9 ;; misaligned with debug data
  [0x101B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101C4] mov x0, x0
  [0x101C8] add x16, x13, x15
  [0x101CC] ldr w9, [x16, #0x18c] ;; misaligned with debug data
  [0x101D0] movz x8, #0x8
  [0x101D4] mov x9, x9
  [0x101D8] and x9, x9, x8
  [0x101DC] movz x8, #0
  [0x101E0] cmp x9, x8
  [0x101E4] b.ne #0x1027c
  [0x101E8] mov x3, x3
  [0x101EC] mov x9, x14
  [0x101F0] sub x9, x9, x15 ;; misaligned with debug data
  [0x101F4] cmp x3, x9
  [0x101F8] b.eq #0x1020c
  [0x101FC] add x16, x3, x15
  [0x10200] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10204] mov x9, x9
  [0x10208] b #0x10214
  [0x1020C] mov x9, x14
  [0x10210] sub x9, x9, x15 ;; misaligned with debug data
  [0x10214] mov x9, x9
  [0x10218] mov x9, x9
  [0x1021C] add x16, x9, x15
  [0x10220] ldr w8, [x16] ;; misaligned with debug data
  [0x10224] add x16, x8, x15
  [0x10228] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x1022C] movz x1, #0
  [0x10230] mov x9, x9
  [0x10234] lsl x9, x9, #0x20
  [0x10238] lsr x9, x9, #0x20
  [0x1023C] orr x1, x1, x9
  [0x10240] mov x8, x8
  [0x10244] lsl x8, x8, #0x20
  [0x10248] orr x1, x1, x8
  [0x1024C] add x16, x13, x15
  [0x10250] add x16, x16, #0x17c ;; misaligned with debug data
  [0x10254] str x1, [x16] ;; misaligned with debug data
  [0x10258] add x16, x13, x15
  [0x1025C] ldr w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10260] mov x9, x9
  [0x10264] movz x8, #0x8
  [0x10268] orr x9, x9, x8
  [0x1026C] add x16, x13, x15
  [0x10270] str w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10274] mov x9, x9
  [0x10278] b #0x10284
  [0x1027C] mov x9, x14
  [0x10280] sub x9, x9, x15 ;; misaligned with debug data
  [0x10284] adrp x16, #0x10000
  [0x10288] add x16, x16, #0
  [0x1028C] ldr w9, [x16]
  [0x10290] add x16, x13, x15
  [0x10294] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10298] adrp x7, #0x10000
  [0x1029C] add x7, x7, #0
  [0x102A0] movz x6, #0x14c
  [0x102A4] add x6, x6, x13
  [0x102A8] adrp x16, #0x10000
  [0x102AC] add x16, x16, #0
  [0x102B0] ldr w9, [x16]
  [0x102B4] mov x9, x9
  [0x102B8] mov x7, x7
  [0x102BC] mov x6, x6
  [0x102C0] add x9, x9, x15
  [0x102C4] stp x3, x5, [sp, #-0x10]!
  [0x102C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102D0] blr x9 ;; misaligned with debug data
  [0x102D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102E0] mov x0, x0
  [0x102E4] mov x0, x0
  [0x102E8] b #0x102f4
  [0x102EC] mov x0, x14
  [0x102F0] sub x0, x0, x15 ;; misaligned with debug data
  [0x102F4] mov x0, x0
  [0x102F8] b #0x116cc
  [0x102FC] adrp x8, #0x10000
  [0x10300] add x8, x8, #0
  [0x10304] cmp x9, x8
  [0x10308] b.ne #0x10374
  [0x1030C] adrp x16, #0x10000
  [0x10310] add x16, x16, #0
  [0x10314] ldr w9, [x16]
  [0x10318] movz x7, #0x96c
  [0x1031C] add x16, x13, x15
  [0x10320] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10324] add x7, x7, x8
  [0x10328] mov x1, x1
  [0x1032C] movz x2, #0x48
  [0x10330] mov x9, x9
  [0x10334] mov x7, x7
  [0x10338] mov x6, x1
  [0x1033C] mov x2, x2
  [0x10340] add x9, x9, x15
  [0x10344] stp x3, x5, [sp, #-0x10]!
  [0x10348] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1034C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10350] blr x9 ;; misaligned with debug data
  [0x10354] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10358] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1035C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10360] mov x0, x0
  [0x10364] add x0, x14, #8
  [0x10368] sub x0, x0, x15 ;; misaligned with debug data
  [0x1036C] mov x0, x0
  [0x10370] b #0x116cc
  [0x10374] adrp x8, #0x10000
  [0x10378] add x8, x8, #0
  [0x1037C] cmp x9, x8
  [0x10380] b.ne #0x104d8
  [0x10384] add x16, x13, x15
  [0x10388] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x1038C] add x16, x9, x15
  [0x10390] ldr w9, [x16] ;; misaligned with debug data
  [0x10394] adrp x8, #0x10000
  [0x10398] add x8, x8, #0
  [0x1039C] mov x2, x14
  [0x103A0] sub x2, x2, x15 ;; misaligned with debug data
  [0x103A4] cmp x9, x8
  [0x103A8] b.ne #0x103b8
  [0x103AC] add x2, x14, #8
  [0x103B0] sub x2, x2, x15 ;; misaligned with debug data
  [0x103B4] mov x2, x2
  [0x103B8] mov x9, x2
  [0x103BC] mov x8, x14
  [0x103C0] sub x8, x8, x15 ;; misaligned with debug data
  [0x103C4] cmp x9, x8
  [0x103C8] b.ne #0x1044c
  [0x103CC] add x16, x13, x15
  [0x103D0] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x103D4] add x16, x9, x15
  [0x103D8] ldr w9, [x16] ;; misaligned with debug data
  [0x103DC] adrp x8, #0x10000
  [0x103E0] add x8, x8, #0
  [0x103E4] mov x2, x14
  [0x103E8] sub x2, x2, x15 ;; misaligned with debug data
  [0x103EC] cmp x9, x8
  [0x103F0] b.ne #0x10400
  [0x103F4] add x2, x14, #8
  [0x103F8] sub x2, x2, x15 ;; misaligned with debug data
  [0x103FC] mov x2, x2
  [0x10400] mov x9, x2
  [0x10404] mov x8, x14
  [0x10408] sub x8, x8, x15 ;; misaligned with debug data
  [0x1040C] cmp x9, x8
  [0x10410] b.ne #0x1044c
  [0x10414] add x16, x13, x15
  [0x10418] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x1041C] add x16, x9, x15
  [0x10420] ldr w9, [x16] ;; misaligned with debug data
  [0x10424] adrp x8, #0x10000
  [0x10428] add x8, x8, #0
  [0x1042C] mov x2, x14
  [0x10430] sub x2, x2, x15 ;; misaligned with debug data
  [0x10434] cmp x9, x8
  [0x10438] b.ne #0x10448
  [0x1043C] add x2, x14, #8
  [0x10440] sub x2, x2, x15 ;; misaligned with debug data
  [0x10444] mov x2, x2
  [0x10448] mov x9, x2
  [0x1044C] mov x8, x14
  [0x10450] sub x8, x8, x15 ;; misaligned with debug data
  [0x10454] cmp x9, x8
  [0x10458] b.eq #0x104c8
  [0x1045C] adrp x16, #0x10000
  [0x10460] add x16, x16, #0
  [0x10464] ldr w9, [x16]
  [0x10468] add x16, x13, x15
  [0x1046C] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10470] add x16, x1, x15
  [0x10474] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x10478] add x16, x1, x15
  [0x1047C] ldr x6, [x16, #0x18] ;; misaligned with debug data
  [0x10480] mov x6, x6
  [0x10484] adrp x16, #0x10000
  [0x10488] add x16, x16, #0
  [0x1048C] ldr w9, [x16]
  [0x10490] mov x9, x9
  [0x10494] mov x7, x7
  [0x10498] mov x6, x6
  [0x1049C] add x9, x9, x15
  [0x104A0] stp x3, x5, [sp, #-0x10]!
  [0x104A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104AC] blr x9 ;; misaligned with debug data
  [0x104B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104BC] mov x0, x0
  [0x104C0] mov x0, x0
  [0x104C4] b #0x104d0
  [0x104C8] mov x0, x14
  [0x104CC] sub x0, x0, x15 ;; misaligned with debug data
  [0x104D0] mov x0, x0
  [0x104D4] b #0x116cc
  [0x104D8] adrp x8, #0x10000
  [0x104DC] add x8, x8, #0
  [0x104E0] cmp x9, x8
  [0x104E4] b.ne #0x10740
  [0x104E8] add x16, x13, x15
  [0x104EC] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x104F0] add x16, x9, x15
  [0x104F4] ldr w9, [x16, #0x290] ;; misaligned with debug data
  [0x104F8] add x16, x9, x15
  [0x104FC] ldr w9, [x16, #0x90] ;; misaligned with debug data
  [0x10500] movz x8, #0x800
  [0x10504] mov x9, x9
  [0x10508] and x9, x9, x8
  [0x1050C] movz x8, #0
  [0x10510] mov x1, x14
  [0x10514] sub x1, x1, x15 ;; misaligned with debug data
  [0x10518] cmp x9, x8
  [0x1051C] b.eq #0x1052c
  [0x10520] add x1, x14, #8
  [0x10524] sub x1, x1, x15 ;; misaligned with debug data
  [0x10528] mov x1, x1
  [0x1052C] mov x9, x1
  [0x10530] mov x8, x14
  [0x10534] sub x8, x8, x15 ;; misaligned with debug data
  [0x10538] cmp x9, x8
  [0x1053C] b.eq #0x10584
  [0x10540] add x16, x13, x15
  [0x10544] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10548] add x16, x9, x15
  [0x1054C] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10550] ldr x9, [x16] ;; misaligned with debug data
  [0x10554] movz x8, #0x1
  [0x10558] mov x9, x9
  [0x1055C] and x9, x9, x8
  [0x10560] movz x8, #0
  [0x10564] mov x1, x14
  [0x10568] sub x1, x1, x15 ;; misaligned with debug data
  [0x1056C] cmp x9, x8
  [0x10570] b.ne #0x10580
  [0x10574] add x1, x14, #8
  [0x10578] sub x1, x1, x15 ;; misaligned with debug data
  [0x1057C] mov x1, x1
  [0x10580] mov x9, x1
  [0x10584] mov x9, x9
  [0x10588] mov x8, x14
  [0x1058C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10590] cmp x9, x8
  [0x10594] b.ne #0x106d0
  [0x10598] add x16, x13, x15
  [0x1059C] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x105A0] add x16, x9, x15
  [0x105A4] ldr w9, [x16] ;; misaligned with debug data
  [0x105A8] movz x8, #0x200
  [0x105AC] mov x9, x9
  [0x105B0] and x9, x9, x8
  [0x105B4] movz x8, #0
  [0x105B8] mov x1, x14
  [0x105BC] sub x1, x1, x15 ;; misaligned with debug data
  [0x105C0] cmp x9, x8
  [0x105C4] b.eq #0x105d4
  [0x105C8] add x1, x14, #8
  [0x105CC] sub x1, x1, x15 ;; misaligned with debug data
  [0x105D0] mov x1, x1
  [0x105D4] mov x9, x1
  [0x105D8] mov x8, x14
  [0x105DC] sub x8, x8, x15 ;; misaligned with debug data
  [0x105E0] cmp x9, x8
  [0x105E4] b.ne #0x106cc
  [0x105E8] add x16, x13, x15
  [0x105EC] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x105F0] movz x8, #0x830e
  [0x105F4] mov x9, x9
  [0x105F8] and x9, x9, x8
  [0x105FC] movz x8, #0
  [0x10600] mov x1, x14
  [0x10604] sub x1, x1, x15 ;; misaligned with debug data
  [0x10608] cmp x9, x8
  [0x1060C] b.eq #0x1061c
  [0x10610] add x1, x14, #8
  [0x10614] sub x1, x1, x15 ;; misaligned with debug data
  [0x10618] mov x1, x1
  [0x1061C] mov x9, x1
  [0x10620] mov x8, x14
  [0x10624] sub x8, x8, x15 ;; misaligned with debug data
  [0x10628] cmp x9, x8
  [0x1062C] b.ne #0x106cc
  [0x10630] add x16, x13, x15
  [0x10634] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10638] add x16, x9, x15
  [0x1063C] ldr w9, [x16, #0x9c] ;; misaligned with debug data
  [0x10640] add x16, x9, x15
  [0x10644] ldr w9, [x16, #0x24] ;; misaligned with debug data
  [0x10648] movz x8, #0x7380
  [0x1064C] mov x9, x9
  [0x10650] and x9, x9, x8
  [0x10654] movz x8, #0
  [0x10658] mov x1, x14
  [0x1065C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10660] cmp x9, x8
  [0x10664] b.eq #0x10674
  [0x10668] add x1, x14, #8
  [0x1066C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10670] mov x1, x1
  [0x10674] mov x9, x1
  [0x10678] mov x8, x14
  [0x1067C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10680] cmp x9, x8
  [0x10684] b.ne #0x106cc
  [0x10688] add x16, x13, x15
  [0x1068C] add x16, x16, #0x234 ;; misaligned with debug data
  [0x10690] ldr x9, [x16] ;; misaligned with debug data
  [0x10694] adrp x16, #0x10000
  [0x10698] add x16, x16, #0
  [0x1069C] ldr w8, [x16]
  [0x106A0] add x16, x8, x15
  [0x106A4] add x16, x16, #0x30c ;; misaligned with debug data
  [0x106A8] ldr x8, [x16] ;; misaligned with debug data
  [0x106AC] mov x1, x14
  [0x106B0] sub x1, x1, x15 ;; misaligned with debug data
  [0x106B4] cmp x9, x8
  [0x106B8] b.lt #0x106c8
  [0x106BC] add x1, x14, #8
  [0x106C0] sub x1, x1, x15 ;; misaligned with debug data
  [0x106C4] mov x1, x1
  [0x106C8] mov x9, x1
  [0x106CC] mov x9, x9
  [0x106D0] mov x8, x14
  [0x106D4] sub x8, x8, x15 ;; misaligned with debug data
  [0x106D8] cmp x9, x8
  [0x106DC] b.ne #0x10730
  [0x106E0] adrp x16, #0x10000
  [0x106E4] add x16, x16, #0
  [0x106E8] ldr w9, [x16]
  [0x106EC] add x16, x13, x15
  [0x106F0] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x106F4] adrp x16, #0x10000
  [0x106F8] add x16, x16, #0
  [0x106FC] ldr w9, [x16]
  [0x10700] mov x9, x9
  [0x10704] add x9, x9, x15
  [0x10708] stp x3, x5, [sp, #-0x10]!
  [0x1070C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10710] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10714] blr x9 ;; misaligned with debug data
  [0x10718] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1071C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10720] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10724] mov x0, x0
  [0x10728] mov x0, x0
  [0x1072C] b #0x10738
  [0x10730] mov x0, x14
  [0x10734] sub x0, x0, x15 ;; misaligned with debug data
  [0x10738] mov x0, x0
  [0x1073C] b #0x116cc
  [0x10740] adrp x8, #0x10000
  [0x10744] add x8, x8, #0
  [0x10748] cmp x9, x8
  [0x1074C] b.ne #0x1102c
  [0x10750] add x16, x1, x15
  [0x10754] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x10758] mov x9, x9
  [0x1075C] adrp x8, #0x10000
  [0x10760] add x8, x8, #0
  [0x10764] cmp x9, x8
  [0x10768] b.ne #0x107bc
  [0x1076C] adrp x16, #0x10000
  [0x10770] add x16, x16, #0
  [0x10774] ldr w9, [x16]
  [0x10778] add x16, x13, x15
  [0x1077C] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10780] adrp x16, #0x10000
  [0x10784] add x16, x16, #0
  [0x10788] ldr w9, [x16]
  [0x1078C] mov x9, x9
  [0x10790] add x9, x9, x15
  [0x10794] stp x3, x5, [sp, #-0x10]!
  [0x10798] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1079C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x107A0] blr x9 ;; misaligned with debug data
  [0x107A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x107A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x107AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x107B0] mov x0, x0
  [0x107B4] mov x0, x0
  [0x107B8] b #0x11024
  [0x107BC] adrp x8, #0x10000
  [0x107C0] add x8, x8, #0
  [0x107C4] cmp x9, x8
  [0x107C8] b.ne #0x1081c
  [0x107CC] adrp x16, #0x10000
  [0x107D0] add x16, x16, #0
  [0x107D4] ldr w9, [x16]
  [0x107D8] add x16, x13, x15
  [0x107DC] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x107E0] adrp x16, #0x10000
  [0x107E4] add x16, x16, #0
  [0x107E8] ldr w9, [x16]
  [0x107EC] mov x9, x9
  [0x107F0] add x9, x9, x15
  [0x107F4] stp x3, x5, [sp, #-0x10]!
  [0x107F8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x107FC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10800] blr x9 ;; misaligned with debug data
  [0x10804] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10808] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1080C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10810] mov x0, x0
  [0x10814] mov x0, x0
  [0x10818] b #0x11024
  [0x1081C] adrp x8, #0x10000
  [0x10820] add x8, x8, #0
  [0x10824] cmp x9, x8
  [0x10828] b.ne #0x1087c
  [0x1082C] adrp x16, #0x10000
  [0x10830] add x16, x16, #0
  [0x10834] ldr w9, [x16]
  [0x10838] add x16, x13, x15
  [0x1083C] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10840] adrp x16, #0x10000
  [0x10844] add x16, x16, #0
  [0x10848] ldr w9, [x16]
  [0x1084C] mov x9, x9
  [0x10850] add x9, x9, x15
  [0x10854] stp x3, x5, [sp, #-0x10]!
  [0x10858] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1085C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10860] blr x9 ;; misaligned with debug data
  [0x10864] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10868] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1086C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10870] mov x0, x0
  [0x10874] mov x0, x0
  [0x10878] b #0x11024
  [0x1087C] adrp x8, #0x10000
  [0x10880] add x8, x8, #0
  [0x10884] cmp x9, x8
  [0x10888] b.ne #0x108e8
  [0x1088C] adrp x16, #0x10000
  [0x10890] add x16, x16, #0
  [0x10894] ldr w9, [x16]
  [0x10898] add x16, x13, x15
  [0x1089C] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x108A0] mov x7, x14
  [0x108A4] sub x7, x7, x15 ;; misaligned with debug data
  [0x108A8] adrp x16, #0x10000
  [0x108AC] add x16, x16, #0
  [0x108B0] ldr w9, [x16]
  [0x108B4] mov x9, x9
  [0x108B8] mov x7, x7
  [0x108BC] add x9, x9, x15
  [0x108C0] stp x3, x5, [sp, #-0x10]!
  [0x108C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108CC] blr x9 ;; misaligned with debug data
  [0x108D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108DC] mov x0, x0
  [0x108E0] mov x0, x0
  [0x108E4] b #0x11024
  [0x108E8] adrp x8, #0x10000
  [0x108EC] add x8, x8, #0
  [0x108F0] cmp x9, x8
  [0x108F4] b.ne #0x109bc
  [0x108F8] adrp x16, #0x10000
  [0x108FC] add x16, x16, #0
  [0x10900] ldr w9, [x16]
  [0x10904] add x16, x13, x15
  [0x10908] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x1090C] add x16, x1, x15
  [0x10910] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10914] mov x9, x9
  [0x10918] mov x9, x9
  [0x1091C] mov x8, x14
  [0x10920] sub x8, x8, x15 ;; misaligned with debug data
  [0x10924] cmp x9, x8
  [0x10928] b.eq #0x1093c
  [0x1092C] add x16, x9, x15
  [0x10930] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10934] mov x9, x9
  [0x10938] b #0x10944
  [0x1093C] mov x9, x14
  [0x10940] sub x9, x9, x15 ;; misaligned with debug data
  [0x10944] mov x9, x9
  [0x10948] mov x9, x9
  [0x1094C] add x16, x9, x15
  [0x10950] ldr w8, [x16] ;; misaligned with debug data
  [0x10954] add x16, x8, x15
  [0x10958] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x1095C] movz x7, #0
  [0x10960] mov x9, x9
  [0x10964] lsl x9, x9, #0x20
  [0x10968] lsr x9, x9, #0x20
  [0x1096C] orr x7, x7, x9
  [0x10970] mov x8, x8
  [0x10974] lsl x8, x8, #0x20
  [0x10978] orr x7, x7, x8
  [0x1097C] adrp x16, #0x10000
  [0x10980] add x16, x16, #0
  [0x10984] ldr w9, [x16]
  [0x10988] mov x9, x9
  [0x1098C] mov x7, x7
  [0x10990] add x9, x9, x15
  [0x10994] stp x3, x5, [sp, #-0x10]!
  [0x10998] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1099C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109A0] blr x9 ;; misaligned with debug data
  [0x109A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x109B0] mov x0, x0
  [0x109B4] mov x0, x0
  [0x109B8] b #0x11024
  [0x109BC] adrp x8, #0x10000
  [0x109C0] add x8, x8, #0
  [0x109C4] cmp x9, x8
  [0x109C8] b.ne #0x10a90
  [0x109CC] adrp x16, #0x10000
  [0x109D0] add x16, x16, #0
  [0x109D4] ldr w9, [x16]
  [0x109D8] add x16, x13, x15
  [0x109DC] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x109E0] add x16, x1, x15
  [0x109E4] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x109E8] mov x9, x9
  [0x109EC] mov x9, x9
  [0x109F0] mov x8, x14
  [0x109F4] sub x8, x8, x15 ;; misaligned with debug data
  [0x109F8] cmp x9, x8
  [0x109FC] b.eq #0x10a10
  [0x10A00] add x16, x9, x15
  [0x10A04] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10A08] mov x9, x9
  [0x10A0C] b #0x10a18
  [0x10A10] mov x9, x14
  [0x10A14] sub x9, x9, x15 ;; misaligned with debug data
  [0x10A18] mov x9, x9
  [0x10A1C] mov x9, x9
  [0x10A20] add x16, x9, x15
  [0x10A24] ldr w8, [x16] ;; misaligned with debug data
  [0x10A28] add x16, x8, x15
  [0x10A2C] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10A30] movz x7, #0
  [0x10A34] mov x9, x9
  [0x10A38] lsl x9, x9, #0x20
  [0x10A3C] lsr x9, x9, #0x20
  [0x10A40] orr x7, x7, x9
  [0x10A44] mov x8, x8
  [0x10A48] lsl x8, x8, #0x20
  [0x10A4C] orr x7, x7, x8
  [0x10A50] adrp x16, #0x10000
  [0x10A54] add x16, x16, #0
  [0x10A58] ldr w9, [x16]
  [0x10A5C] mov x9, x9
  [0x10A60] mov x7, x7
  [0x10A64] add x9, x9, x15
  [0x10A68] stp x3, x5, [sp, #-0x10]!
  [0x10A6C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A70] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A74] blr x9 ;; misaligned with debug data
  [0x10A78] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A7C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A80] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A84] mov x0, x0
  [0x10A88] mov x0, x0
  [0x10A8C] b #0x11024
  [0x10A90] adrp x8, #0x10000
  [0x10A94] add x8, x8, #0
  [0x10A98] cmp x9, x8
  [0x10A9C] b.ne #0x10b64
  [0x10AA0] adrp x16, #0x10000
  [0x10AA4] add x16, x16, #0
  [0x10AA8] ldr w9, [x16]
  [0x10AAC] add x16, x13, x15
  [0x10AB0] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10AB4] add x16, x1, x15
  [0x10AB8] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10ABC] mov x9, x9
  [0x10AC0] mov x9, x9
  [0x10AC4] mov x8, x14
  [0x10AC8] sub x8, x8, x15 ;; misaligned with debug data
  [0x10ACC] cmp x9, x8
  [0x10AD0] b.eq #0x10ae4
  [0x10AD4] add x16, x9, x15
  [0x10AD8] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10ADC] mov x9, x9
  [0x10AE0] b #0x10aec
  [0x10AE4] mov x9, x14
  [0x10AE8] sub x9, x9, x15 ;; misaligned with debug data
  [0x10AEC] mov x9, x9
  [0x10AF0] mov x9, x9
  [0x10AF4] add x16, x9, x15
  [0x10AF8] ldr w8, [x16] ;; misaligned with debug data
  [0x10AFC] add x16, x8, x15
  [0x10B00] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10B04] movz x7, #0
  [0x10B08] mov x9, x9
  [0x10B0C] lsl x9, x9, #0x20
  [0x10B10] lsr x9, x9, #0x20
  [0x10B14] orr x7, x7, x9
  [0x10B18] mov x8, x8
  [0x10B1C] lsl x8, x8, #0x20
  [0x10B20] orr x7, x7, x8
  [0x10B24] adrp x16, #0x10000
  [0x10B28] add x16, x16, #0
  [0x10B2C] ldr w9, [x16]
  [0x10B30] mov x9, x9
  [0x10B34] mov x7, x7
  [0x10B38] add x9, x9, x15
  [0x10B3C] stp x3, x5, [sp, #-0x10]!
  [0x10B40] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B44] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B48] blr x9 ;; misaligned with debug data
  [0x10B4C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B50] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10B54] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10B58] mov x0, x0
  [0x10B5C] mov x0, x0
  [0x10B60] b #0x11024
  [0x10B64] adrp x8, #0x10000
  [0x10B68] add x8, x8, #0
  [0x10B6C] cmp x9, x8
  [0x10B70] b.ne #0x10cec
  [0x10B74] add x16, x13, x15
  [0x10B78] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10B7C] add x16, x9, x15
  [0x10B80] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10B84] ldr x9, [x16] ;; misaligned with debug data
  [0x10B88] movz x8, #0x1
  [0x10B8C] mov x9, x9
  [0x10B90] and x9, x9, x8
  [0x10B94] movz x8, #0
  [0x10B98] mov x2, x14
  [0x10B9C] sub x2, x2, x15 ;; misaligned with debug data
  [0x10BA0] cmp x9, x8
  [0x10BA4] b.eq #0x10bb4
  [0x10BA8] add x2, x14, #8
  [0x10BAC] sub x2, x2, x15 ;; misaligned with debug data
  [0x10BB0] mov x2, x2
  [0x10BB4] mov x9, x2
  [0x10BB8] mov x8, x14
  [0x10BBC] sub x8, x8, x15 ;; misaligned with debug data
  [0x10BC0] cmp x9, x8
  [0x10BC4] b.eq #0x10c08
  [0x10BC8] add x16, x13, x15
  [0x10BCC] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x10BD0] add x16, x9, x15
  [0x10BD4] ldr w9, [x16] ;; misaligned with debug data
  [0x10BD8] movz x8, #0x200
  [0x10BDC] mov x9, x9
  [0x10BE0] and x9, x9, x8
  [0x10BE4] movz x8, #0
  [0x10BE8] mov x2, x14
  [0x10BEC] sub x2, x2, x15 ;; misaligned with debug data
  [0x10BF0] cmp x9, x8
  [0x10BF4] b.ne #0x10c04
  [0x10BF8] add x2, x14, #8
  [0x10BFC] sub x2, x2, x15 ;; misaligned with debug data
  [0x10C00] mov x2, x2
  [0x10C04] mov x9, x2
  [0x10C08] mov x8, x14
  [0x10C0C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10C10] cmp x9, x8
  [0x10C14] b.eq #0x10cdc
  [0x10C18] adrp x16, #0x10000
  [0x10C1C] add x16, x16, #0
  [0x10C20] ldr w9, [x16]
  [0x10C24] add x16, x13, x15
  [0x10C28] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10C2C] add x16, x1, x15
  [0x10C30] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10C34] mov x9, x9
  [0x10C38] mov x9, x9
  [0x10C3C] mov x8, x14
  [0x10C40] sub x8, x8, x15 ;; misaligned with debug data
  [0x10C44] cmp x9, x8
  [0x10C48] b.eq #0x10c5c
  [0x10C4C] add x16, x9, x15
  [0x10C50] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10C54] mov x9, x9
  [0x10C58] b #0x10c64
  [0x10C5C] mov x9, x14
  [0x10C60] sub x9, x9, x15 ;; misaligned with debug data
  [0x10C64] mov x9, x9
  [0x10C68] mov x9, x9
  [0x10C6C] add x16, x9, x15
  [0x10C70] ldr w8, [x16] ;; misaligned with debug data
  [0x10C74] add x16, x8, x15
  [0x10C78] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10C7C] movz x7, #0
  [0x10C80] mov x9, x9
  [0x10C84] lsl x9, x9, #0x20
  [0x10C88] lsr x9, x9, #0x20
  [0x10C8C] orr x7, x7, x9
  [0x10C90] mov x8, x8
  [0x10C94] lsl x8, x8, #0x20
  [0x10C98] orr x7, x7, x8
  [0x10C9C] adrp x16, #0x10000
  [0x10CA0] add x16, x16, #0
  [0x10CA4] ldr w9, [x16]
  [0x10CA8] mov x9, x9
  [0x10CAC] mov x7, x7
  [0x10CB0] add x9, x9, x15
  [0x10CB4] stp x3, x5, [sp, #-0x10]!
  [0x10CB8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CBC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CC0] blr x9 ;; misaligned with debug data
  [0x10CC4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10CC8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10CCC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10CD0] mov x0, x0
  [0x10CD4] mov x0, x0
  [0x10CD8] b #0x10ce4
  [0x10CDC] mov x0, x14
  [0x10CE0] sub x0, x0, x15 ;; misaligned with debug data
  [0x10CE4] mov x0, x0
  [0x10CE8] b #0x11024
  [0x10CEC] adrp x8, #0x10000
  [0x10CF0] add x8, x8, #0
  [0x10CF4] cmp x9, x8
  [0x10CF8] b.ne #0x10dfc
  [0x10CFC] add x16, x13, x15
  [0x10D00] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10D04] add x16, x9, x15
  [0x10D08] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10D0C] ldr x9, [x16] ;; misaligned with debug data
  [0x10D10] movz x8, #0x1
  [0x10D14] mov x9, x9
  [0x10D18] and x9, x9, x8
  [0x10D1C] movz x8, #0
  [0x10D20] cmp x9, x8
  [0x10D24] b.eq #0x10dec
  [0x10D28] adrp x16, #0x10000
  [0x10D2C] add x16, x16, #0
  [0x10D30] ldr w9, [x16]
  [0x10D34] add x16, x13, x15
  [0x10D38] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10D3C] add x16, x1, x15
  [0x10D40] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10D44] mov x9, x9
  [0x10D48] mov x9, x9
  [0x10D4C] mov x8, x14
  [0x10D50] sub x8, x8, x15 ;; misaligned with debug data
  [0x10D54] cmp x9, x8
  [0x10D58] b.eq #0x10d6c
  [0x10D5C] add x16, x9, x15
  [0x10D60] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10D64] mov x9, x9
  [0x10D68] b #0x10d74
  [0x10D6C] mov x9, x14
  [0x10D70] sub x9, x9, x15 ;; misaligned with debug data
  [0x10D74] mov x9, x9
  [0x10D78] mov x9, x9
  [0x10D7C] add x16, x9, x15
  [0x10D80] ldr w8, [x16] ;; misaligned with debug data
  [0x10D84] add x16, x8, x15
  [0x10D88] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10D8C] movz x7, #0
  [0x10D90] mov x9, x9
  [0x10D94] lsl x9, x9, #0x20
  [0x10D98] lsr x9, x9, #0x20
  [0x10D9C] orr x7, x7, x9
  [0x10DA0] mov x8, x8
  [0x10DA4] lsl x8, x8, #0x20
  [0x10DA8] orr x7, x7, x8
  [0x10DAC] adrp x16, #0x10000
  [0x10DB0] add x16, x16, #0
  [0x10DB4] ldr w9, [x16]
  [0x10DB8] mov x9, x9
  [0x10DBC] mov x7, x7
  [0x10DC0] add x9, x9, x15
  [0x10DC4] stp x3, x5, [sp, #-0x10]!
  [0x10DC8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DCC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DD0] blr x9 ;; misaligned with debug data
  [0x10DD4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10DD8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10DDC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10DE0] mov x0, x0
  [0x10DE4] mov x0, x0
  [0x10DE8] b #0x10df4
  [0x10DEC] mov x0, x14
  [0x10DF0] sub x0, x0, x15 ;; misaligned with debug data
  [0x10DF4] mov x0, x0
  [0x10DF8] b #0x11024
  [0x10DFC] adrp x8, #0x10000
  [0x10E00] add x8, x8, #0
  [0x10E04] cmp x9, x8
  [0x10E08] b.ne #0x10ed0
  [0x10E0C] adrp x16, #0x10000
  [0x10E10] add x16, x16, #0
  [0x10E14] ldr w9, [x16]
  [0x10E18] add x16, x13, x15
  [0x10E1C] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10E20] add x16, x1, x15
  [0x10E24] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10E28] mov x9, x9
  [0x10E2C] mov x9, x9
  [0x10E30] mov x8, x14
  [0x10E34] sub x8, x8, x15 ;; misaligned with debug data
  [0x10E38] cmp x9, x8
  [0x10E3C] b.eq #0x10e50
  [0x10E40] add x16, x9, x15
  [0x10E44] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10E48] mov x9, x9
  [0x10E4C] b #0x10e58
  [0x10E50] mov x9, x14
  [0x10E54] sub x9, x9, x15 ;; misaligned with debug data
  [0x10E58] mov x9, x9
  [0x10E5C] mov x9, x9
  [0x10E60] add x16, x9, x15
  [0x10E64] ldr w8, [x16] ;; misaligned with debug data
  [0x10E68] add x16, x8, x15
  [0x10E6C] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10E70] movz x7, #0
  [0x10E74] mov x9, x9
  [0x10E78] lsl x9, x9, #0x20
  [0x10E7C] lsr x9, x9, #0x20
  [0x10E80] orr x7, x7, x9
  [0x10E84] mov x8, x8
  [0x10E88] lsl x8, x8, #0x20
  [0x10E8C] orr x7, x7, x8
  [0x10E90] adrp x16, #0x10000
  [0x10E94] add x16, x16, #0
  [0x10E98] ldr w9, [x16]
  [0x10E9C] mov x9, x9
  [0x10EA0] mov x7, x7
  [0x10EA4] add x9, x9, x15
  [0x10EA8] stp x3, x5, [sp, #-0x10]!
  [0x10EAC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10EB0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10EB4] blr x9 ;; misaligned with debug data
  [0x10EB8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10EBC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10EC0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10EC4] mov x0, x0
  [0x10EC8] mov x0, x0
  [0x10ECC] b #0x11024
  [0x10ED0] adrp x8, #0x10000
  [0x10ED4] add x8, x8, #0
  [0x10ED8] cmp x9, x8
  [0x10EDC] b.ne #0x1101c
  [0x10EE0] adrp x16, #0x10000
  [0x10EE4] add x16, x16, #0
  [0x10EE8] ldr w9, [x16]
  [0x10EEC] add x16, x13, x15
  [0x10EF0] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x10EF4] add x16, x1, x15
  [0x10EF8] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10EFC] mov x9, x9
  [0x10F00] mov x9, x9
  [0x10F04] mov x8, x14
  [0x10F08] sub x8, x8, x15 ;; misaligned with debug data
  [0x10F0C] cmp x9, x8
  [0x10F10] b.eq #0x10f24
  [0x10F14] add x16, x9, x15
  [0x10F18] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10F1C] mov x9, x9
  [0x10F20] b #0x10f2c
  [0x10F24] mov x9, x14
  [0x10F28] sub x9, x9, x15 ;; misaligned with debug data
  [0x10F2C] mov x9, x9
  [0x10F30] mov x9, x9
  [0x10F34] add x16, x9, x15
  [0x10F38] ldr w8, [x16] ;; misaligned with debug data
  [0x10F3C] add x16, x8, x15
  [0x10F40] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10F44] movz x7, #0
  [0x10F48] mov x9, x9
  [0x10F4C] lsl x9, x9, #0x20
  [0x10F50] lsr x9, x9, #0x20
  [0x10F54] orr x7, x7, x9
  [0x10F58] mov x8, x8
  [0x10F5C] lsl x8, x8, #0x20
  [0x10F60] orr x7, x7, x8
  [0x10F64] mov x7, x7
  [0x10F68] add x16, x1, x15
  [0x10F6C] ldr x9, [x16, #0x20] ;; misaligned with debug data
  [0x10F70] mov x9, x9
  [0x10F74] mov x9, x9
  [0x10F78] mov x8, x14
  [0x10F7C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10F80] cmp x9, x8
  [0x10F84] b.eq #0x10f98
  [0x10F88] add x16, x9, x15
  [0x10F8C] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10F90] mov x9, x9
  [0x10F94] b #0x10fa0
  [0x10F98] mov x9, x14
  [0x10F9C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10FA0] mov x9, x9
  [0x10FA4] mov x9, x9
  [0x10FA8] add x16, x9, x15
  [0x10FAC] ldr w8, [x16] ;; misaligned with debug data
  [0x10FB0] add x16, x8, x15
  [0x10FB4] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10FB8] movz x6, #0
  [0x10FBC] mov x9, x9
  [0x10FC0] lsl x9, x9, #0x20
  [0x10FC4] lsr x9, x9, #0x20
  [0x10FC8] orr x6, x6, x9
  [0x10FCC] mov x8, x8
  [0x10FD0] lsl x8, x8, #0x20
  [0x10FD4] orr x6, x6, x8
  [0x10FD8] adrp x16, #0x10000
  [0x10FDC] add x16, x16, #0
  [0x10FE0] ldr w9, [x16]
  [0x10FE4] mov x9, x9
  [0x10FE8] mov x7, x7
  [0x10FEC] mov x6, x6
  [0x10FF0] add x9, x9, x15
  [0x10FF4] stp x3, x5, [sp, #-0x10]!
  [0x10FF8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10FFC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11000] blr x9 ;; misaligned with debug data
  [0x11004] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11008] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1100C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11010] mov x0, x0
  [0x11014] mov x0, x0
  [0x11018] b #0x11024
  [0x1101C] mov x0, x14
  [0x11020] sub x0, x0, x15 ;; misaligned with debug data
  [0x11024] mov x0, x0
  [0x11028] b #0x116cc
  [0x1102C] adrp x8, #0x11000
  [0x11030] add x8, x8, #0
  [0x11034] cmp x9, x8
  [0x11038] b.ne #0x110a4
  [0x1103C] adrp x16, #0x11000
  [0x11040] add x16, x16, #0
  [0x11044] ldr w9, [x16]
  [0x11048] add x16, x13, x15
  [0x1104C] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x11050] add x16, x1, x15
  [0x11054] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x11058] mov x7, x7
  [0x1105C] mov x6, x6
  [0x11060] adrp x16, #0x11000
  [0x11064] add x16, x16, #0
  [0x11068] ldr w9, [x16]
  [0x1106C] mov x9, x9
  [0x11070] mov x7, x7
  [0x11074] mov x6, x6
  [0x11078] add x9, x9, x15
  [0x1107C] stp x3, x5, [sp, #-0x10]!
  [0x11080] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11084] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11088] blr x9 ;; misaligned with debug data
  [0x1108C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11090] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11094] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11098] mov x0, x0
  [0x1109C] mov x0, x0
  [0x110A0] b #0x116cc
  [0x110A4] adrp x8, #0x11000
  [0x110A8] add x8, x8, #0
  [0x110AC] cmp x9, x8
  [0x110B0] b.ne #0x11178
  [0x110B4] adrp x16, #0x11000
  [0x110B8] add x16, x16, #0
  [0x110BC] ldr w9, [x16]
  [0x110C0] add x16, x13, x15
  [0x110C4] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x110C8] add x16, x1, x15
  [0x110CC] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x110D0] mov x9, x9
  [0x110D4] mov x9, x9
  [0x110D8] mov x8, x14
  [0x110DC] sub x8, x8, x15 ;; misaligned with debug data
  [0x110E0] cmp x9, x8
  [0x110E4] b.eq #0x110f8
  [0x110E8] add x16, x9, x15
  [0x110EC] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x110F0] mov x9, x9
  [0x110F4] b #0x11100
  [0x110F8] mov x9, x14
  [0x110FC] sub x9, x9, x15 ;; misaligned with debug data
  [0x11100] mov x9, x9
  [0x11104] mov x9, x9
  [0x11108] add x16, x9, x15
  [0x1110C] ldr w8, [x16] ;; misaligned with debug data
  [0x11110] add x16, x8, x15
  [0x11114] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x11118] movz x7, #0
  [0x1111C] mov x9, x9
  [0x11120] lsl x9, x9, #0x20
  [0x11124] lsr x9, x9, #0x20
  [0x11128] orr x7, x7, x9
  [0x1112C] mov x8, x8
  [0x11130] lsl x8, x8, #0x20
  [0x11134] orr x7, x7, x8
  [0x11138] adrp x16, #0x11000
  [0x1113C] add x16, x16, #0
  [0x11140] ldr w9, [x16]
  [0x11144] mov x9, x9
  [0x11148] mov x7, x7
  [0x1114C] add x9, x9, x15
  [0x11150] stp x3, x5, [sp, #-0x10]!
  [0x11154] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11158] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1115C] blr x9 ;; misaligned with debug data
  [0x11160] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11164] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11168] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1116C] mov x0, x0
  [0x11170] mov x0, x0
  [0x11174] b #0x116cc
  [0x11178] adrp x8, #0x11000
  [0x1117C] add x8, x8, #0
  [0x11180] cmp x9, x8
  [0x11184] b.ne #0x111d8
  [0x11188] adrp x16, #0x11000
  [0x1118C] add x16, x16, #0
  [0x11190] ldr w9, [x16]
  [0x11194] add x16, x13, x15
  [0x11198] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x1119C] adrp x16, #0x11000
  [0x111A0] add x16, x16, #0
  [0x111A4] ldr w9, [x16]
  [0x111A8] mov x9, x9
  [0x111AC] add x9, x9, x15
  [0x111B0] stp x3, x5, [sp, #-0x10]!
  [0x111B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x111B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x111BC] blr x9 ;; misaligned with debug data
  [0x111C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x111C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x111C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x111CC] mov x0, x0
  [0x111D0] mov x0, x0
  [0x111D4] b #0x116cc
  [0x111D8] adrp x8, #0x11000
  [0x111DC] add x8, x8, #0
  [0x111E0] cmp x9, x8
  [0x111E4] b.ne #0x112ec
  [0x111E8] add x16, x13, x15
  [0x111EC] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x111F0] add x16, x9, x15
  [0x111F4] ldr w9, [x16, #0x9c] ;; misaligned with debug data
  [0x111F8] add x16, x9, x15
  [0x111FC] ldr w9, [x16, #0x24] ;; misaligned with debug data
  [0x11200] movz x8, #0x100
  [0x11204] mov x9, x9
  [0x11208] and x9, x9, x8
  [0x1120C] movz x8, #0
  [0x11210] cmp x9, x8
  [0x11214] b.ne #0x112dc
  [0x11218] adrp x16, #0x11000
  [0x1121C] add x16, x16, #0
  [0x11220] ldr w9, [x16]
  [0x11224] add x16, x13, x15
  [0x11228] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x1122C] add x16, x1, x15
  [0x11230] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x11234] mov x9, x9
  [0x11238] mov x9, x9
  [0x1123C] mov x8, x14
  [0x11240] sub x8, x8, x15 ;; misaligned with debug data
  [0x11244] cmp x9, x8
  [0x11248] b.eq #0x1125c
  [0x1124C] add x16, x9, x15
  [0x11250] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x11254] mov x9, x9
  [0x11258] b #0x11264
  [0x1125C] mov x9, x14
  [0x11260] sub x9, x9, x15 ;; misaligned with debug data
  [0x11264] mov x9, x9
  [0x11268] mov x9, x9
  [0x1126C] add x16, x9, x15
  [0x11270] ldr w8, [x16] ;; misaligned with debug data
  [0x11274] add x16, x8, x15
  [0x11278] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x1127C] movz x7, #0
  [0x11280] mov x9, x9
  [0x11284] lsl x9, x9, #0x20
  [0x11288] lsr x9, x9, #0x20
  [0x1128C] orr x7, x7, x9
  [0x11290] mov x8, x8
  [0x11294] lsl x8, x8, #0x20
  [0x11298] orr x7, x7, x8
  [0x1129C] adrp x16, #0x11000
  [0x112A0] add x16, x16, #0
  [0x112A4] ldr w9, [x16]
  [0x112A8] mov x9, x9
  [0x112AC] mov x7, x7
  [0x112B0] add x9, x9, x15
  [0x112B4] stp x3, x5, [sp, #-0x10]!
  [0x112B8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x112BC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x112C0] blr x9 ;; misaligned with debug data
  [0x112C4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x112C8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x112CC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x112D0] mov x0, x0
  [0x112D4] mov x0, x0
  [0x112D8] b #0x112e4
  [0x112DC] mov x0, x14
  [0x112E0] sub x0, x0, x15 ;; misaligned with debug data
  [0x112E4] mov x0, x0
  [0x112E8] b #0x116cc
  [0x112EC] adrp x8, #0x11000
  [0x112F0] add x8, x8, #0
  [0x112F4] cmp x9, x8
  [0x112F8] b.ne #0x1148c
  [0x112FC] add x16, x13, x15
  [0x11300] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x11304] add x16, x9, x15
  [0x11308] ldr w9, [x16, #0x290] ;; misaligned with debug data
  [0x1130C] add x16, x9, x15
  [0x11310] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x11314] adrp x8, #0x11000
  [0x11318] add x8, x8, #0
  [0x1131C] mov x1, x14
  [0x11320] sub x1, x1, x15 ;; misaligned with debug data
  [0x11324] cmp x9, x8
  [0x11328] b.ne #0x11338
  [0x1132C] add x1, x14, #8
  [0x11330] sub x1, x1, x15 ;; misaligned with debug data
  [0x11334] mov x1, x1
  [0x11338] mov x9, x1
  [0x1133C] mov x8, x14
  [0x11340] sub x8, x8, x15 ;; misaligned with debug data
  [0x11344] cmp x9, x8
  [0x11348] b.ne #0x1141c
  [0x1134C] add x16, x13, x15
  [0x11350] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x11354] add x16, x9, x15
  [0x11358] ldr w9, [x16, #0x290] ;; misaligned with debug data
  [0x1135C] add x16, x9, x15
  [0x11360] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x11364] adrp x8, #0x11000
  [0x11368] add x8, x8, #0
  [0x1136C] mov x1, x14
  [0x11370] sub x1, x1, x15 ;; misaligned with debug data
  [0x11374] cmp x9, x8
  [0x11378] b.ne #0x11388
  [0x1137C] add x1, x14, #8
  [0x11380] sub x1, x1, x15 ;; misaligned with debug data
  [0x11384] mov x1, x1
  [0x11388] mov x9, x1
  [0x1138C] mov x8, x14
  [0x11390] sub x8, x8, x15 ;; misaligned with debug data
  [0x11394] cmp x9, x8
  [0x11398] b.ne #0x1141c
  [0x1139C] add x16, x13, x15
  [0x113A0] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x113A4] add x16, x9, x15
  [0x113A8] ldr w9, [x16] ;; misaligned with debug data
  [0x113AC] adrp x8, #0x11000
  [0x113B0] add x8, x8, #0
  [0x113B4] mov x1, x14
  [0x113B8] sub x1, x1, x15 ;; misaligned with debug data
  [0x113BC] cmp x9, x8
  [0x113C0] b.ne #0x113d0
  [0x113C4] add x1, x14, #8
  [0x113C8] sub x1, x1, x15 ;; misaligned with debug data
  [0x113CC] mov x1, x1
  [0x113D0] mov x9, x1
  [0x113D4] mov x8, x14
  [0x113D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x113DC] cmp x9, x8
  [0x113E0] b.ne #0x1141c
  [0x113E4] add x16, x13, x15
  [0x113E8] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x113EC] movz x8, #0x8
  [0x113F0] mov x9, x9
  [0x113F4] and x9, x9, x8
  [0x113F8] movz x8, #0
  [0x113FC] mov x1, x14
  [0x11400] sub x1, x1, x15 ;; misaligned with debug data
  [0x11404] cmp x9, x8
  [0x11408] b.eq #0x11418
  [0x1140C] add x1, x14, #8
  [0x11410] sub x1, x1, x15 ;; misaligned with debug data
  [0x11414] mov x1, x1
  [0x11418] mov x9, x1
  [0x1141C] mov x8, x14
  [0x11420] sub x8, x8, x15 ;; misaligned with debug data
  [0x11424] cmp x9, x8
  [0x11428] b.ne #0x1147c
  [0x1142C] adrp x16, #0x11000
  [0x11430] add x16, x16, #0
  [0x11434] ldr w9, [x16]
  [0x11438] add x16, x13, x15
  [0x1143C] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x11440] adrp x16, #0x11000
  [0x11444] add x16, x16, #0
  [0x11448] ldr w9, [x16]
  [0x1144C] mov x9, x9
  [0x11450] add x9, x9, x15
  [0x11454] stp x3, x5, [sp, #-0x10]!
  [0x11458] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1145C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11460] blr x9 ;; misaligned with debug data
  [0x11464] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11468] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1146C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11470] mov x0, x0
  [0x11474] mov x0, x0
  [0x11478] b #0x11484
  [0x1147C] mov x0, x14
  [0x11480] sub x0, x0, x15 ;; misaligned with debug data
  [0x11484] mov x0, x0
  [0x11488] b #0x116cc
  [0x1148C] adrp x8, #0x11000
  [0x11490] add x8, x8, #0
  [0x11494] cmp x9, x8
  [0x11498] b.ne #0x11628
  [0x1149C] add x16, x13, x15
  [0x114A0] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x114A4] add x16, x9, x15
  [0x114A8] ldr w9, [x16, #0x290] ;; misaligned with debug data
  [0x114AC] add x16, x9, x15
  [0x114B0] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x114B4] adrp x8, #0x11000
  [0x114B8] add x8, x8, #0
  [0x114BC] mov x1, x14
  [0x114C0] sub x1, x1, x15 ;; misaligned with debug data
  [0x114C4] cmp x9, x8
  [0x114C8] b.eq #0x114d8
  [0x114CC] add x1, x14, #8
  [0x114D0] sub x1, x1, x15 ;; misaligned with debug data
  [0x114D4] mov x1, x1
  [0x114D8] mov x9, x1
  [0x114DC] mov x8, x14
  [0x114E0] sub x8, x8, x15 ;; misaligned with debug data
  [0x114E4] cmp x9, x8
  [0x114E8] b.eq #0x115b8
  [0x114EC] add x16, x13, x15
  [0x114F0] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x114F4] add x16, x9, x15
  [0x114F8] ldr w9, [x16] ;; misaligned with debug data
  [0x114FC] adrp x8, #0x11000
  [0x11500] add x8, x8, #0
  [0x11504] mov x1, x14
  [0x11508] sub x1, x1, x15 ;; misaligned with debug data
  [0x1150C] cmp x9, x8
  [0x11510] b.ne #0x11520
  [0x11514] add x1, x14, #8
  [0x11518] sub x1, x1, x15 ;; misaligned with debug data
  [0x1151C] mov x1, x1
  [0x11520] mov x9, x1
  [0x11524] mov x8, x14
  [0x11528] sub x8, x8, x15 ;; misaligned with debug data
  [0x1152C] cmp x9, x8
  [0x11530] b.ne #0x115b4
  [0x11534] add x16, x13, x15
  [0x11538] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x1153C] add x16, x9, x15
  [0x11540] ldr w9, [x16] ;; misaligned with debug data
  [0x11544] adrp x8, #0x11000
  [0x11548] add x8, x8, #0
  [0x1154C] mov x1, x14
  [0x11550] sub x1, x1, x15 ;; misaligned with debug data
  [0x11554] cmp x9, x8
  [0x11558] b.ne #0x11568
  [0x1155C] add x1, x14, #8
  [0x11560] sub x1, x1, x15 ;; misaligned with debug data
  [0x11564] mov x1, x1
  [0x11568] mov x9, x1
  [0x1156C] mov x8, x14
  [0x11570] sub x8, x8, x15 ;; misaligned with debug data
  [0x11574] cmp x9, x8
  [0x11578] b.ne #0x115b4
  [0x1157C] add x16, x13, x15
  [0x11580] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x11584] add x16, x9, x15
  [0x11588] ldr w9, [x16] ;; misaligned with debug data
  [0x1158C] adrp x8, #0x11000
  [0x11590] add x8, x8, #0
  [0x11594] mov x1, x14
  [0x11598] sub x1, x1, x15 ;; misaligned with debug data
  [0x1159C] cmp x9, x8
  [0x115A0] b.ne #0x115b0
  [0x115A4] add x1, x14, #8
  [0x115A8] sub x1, x1, x15 ;; misaligned with debug data
  [0x115AC] mov x1, x1
  [0x115B0] mov x9, x1
  [0x115B4] mov x9, x9
  [0x115B8] mov x8, x14
  [0x115BC] sub x8, x8, x15 ;; misaligned with debug data
  [0x115C0] cmp x9, x8
  [0x115C4] b.eq #0x11618
  [0x115C8] adrp x16, #0x11000
  [0x115CC] add x16, x16, #0
  [0x115D0] ldr w9, [x16]
  [0x115D4] add x16, x13, x15
  [0x115D8] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x115DC] adrp x16, #0x11000
  [0x115E0] add x16, x16, #0
  [0x115E4] ldr w9, [x16]
  [0x115E8] mov x9, x9
  [0x115EC] add x9, x9, x15
  [0x115F0] stp x3, x5, [sp, #-0x10]!
  [0x115F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x115F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x115FC] blr x9 ;; misaligned with debug data
  [0x11600] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11604] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11608] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1160C] mov x0, x0
  [0x11610] mov x0, x0
  [0x11614] b #0x11620
  [0x11618] mov x0, x14
  [0x1161C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11620] mov x0, x0
  [0x11624] b #0x116cc
  [0x11628] adrp x8, #0x11000
  [0x1162C] add x8, x8, #0
  [0x11630] cmp x9, x8
  [0x11634] b.ne #0x11684
  [0x11638] adrp x16, #0x11000
  [0x1163C] add x16, x16, #0
  [0x11640] ldr w9, [x16]
  [0x11644] add x16, x1, x15
  [0x11648] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x1164C] mov x7, x7
  [0x11650] mov x9, x9
  [0x11654] mov x7, x7
  [0x11658] add x9, x9, x15
  [0x1165C] stp x3, x5, [sp, #-0x10]!
  [0x11660] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11664] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11668] blr x9 ;; misaligned with debug data
  [0x1166C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11670] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11674] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11678] mov x0, x0
  [0x1167C] mov x0, x0
  [0x11680] b #0x116cc
  [0x11684] adrp x16, #0x11000
  [0x11688] add x16, x16, #0
  [0x1168C] ldr w9, [x16]
  [0x11690] mov x9, x9
  [0x11694] mov x7, x3
  [0x11698] mov x6, x6
  [0x1169C] mov x2, x2
  [0x116A0] mov x1, x1
  [0x116A4] add x9, x9, x15
  [0x116A8] stp x3, x5, [sp, #-0x10]!
  [0x116AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x116B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x116B4] blr x9 ;; misaligned with debug data
  [0x116B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x116BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x116C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x116C4] mov x0, x0
  [0x116C8] mov x0, x0
  [0x116CC] mov x0, x0
  [0x116D0] add sp, sp, #0x10
  [0x116D4] ldp x29, x30, [sp], #0x10
  [0x116D8] ret


[get-intersect-point]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] mov x5, x6
  [0x10014] mov x2, x2
  [0x10018] mov x1, x1
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] ldr w9, [x16]
  [0x10028] add x16, x9, x15
  [0x1002C] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10030] mov x9, x9
  [0x10034] mov x7, x5
  [0x10038] mov x6, x2
  [0x1003C] mov x2, x1
  [0x10040] add x9, x9, x15
  [0x10044] stp x3, x5, [sp, #-0x10]!
  [0x10048] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1004C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10050] blr x9 ;; misaligned with debug data
  [0x10054] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10058] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1005C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10060] mov x0, x0
  [0x10064] mov x0, x0
  [0x10068] mov x9, x14
  [0x1006C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10070] cmp x0, x9
  [0x10074] b.eq #0x10094
  [0x10078] add x16, x0, x15
  [0x1007C] ldr q23, [x16, #0x30] ;; misaligned with debug data
  [0x10080] mov v23.16b, v23.16b
  [0x10084] add x16, x3, x15
  [0x10088] str q23, [x16] ;; misaligned with debug data
  [0x1008C] fmov x9, d23
  [0x10090] b #0x100dc
  [0x10094] adrp x16, #0x10000
  [0x10098] add x16, x16, #0
  [0x1009C] ldr w9, [x16]
  [0x100A0] add x16, x9, x15
  [0x100A4] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x100A8] mov x9, x9
  [0x100AC] mov x7, x5
  [0x100B0] mov x6, x3
  [0x100B4] add x9, x9, x15
  [0x100B8] stp x3, x5, [sp, #-0x10]!
  [0x100BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C4] blr x9 ;; misaligned with debug data
  [0x100C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] mov x0, x0
  [0x100D8] mov x9, x0
  [0x100DC] mov x0, x3
  [0x100E0] add sp, sp, #0x10
  [0x100E4] ldp x29, x30, [sp], #0x10
  [0x100E8] ret


[target-attacked]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0x10
  [0x10010] mov x3, x7
  [0x10014] mov x6, x6
  [0x10018] mov x12, x2
  [0x1001C] mov x11, x1
  [0x10020] mov x5, x8
  [0x10024] add x16, x13, x15
  [0x10028] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x1002C] movz x8, #0x8
  [0x10030] mov x9, x9
  [0x10034] and x9, x9, x8
  [0x10038] movz x8, #0
  [0x1003C] cmp x9, x8
  [0x10040] b.ne #0x10c40
  [0x10044] add x16, x13, x15
  [0x10048] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x1004C] movz x8, #0x70
  [0x10050] mov x9, x9
  [0x10054] and x9, x9, x8
  [0x10058] movz x8, #0
  [0x1005C] mov x1, x14
  [0x10060] sub x1, x1, x15 ;; misaligned with debug data
  [0x10064] cmp x9, x8
  [0x10068] b.eq #0x10078
  [0x1006C] add x1, x14, #8
  [0x10070] sub x1, x1, x15 ;; misaligned with debug data
  [0x10074] mov x1, x1
  [0x10078] mov x9, x1
  [0x1007C] mov x8, x14
  [0x10080] sub x8, x8, x15 ;; misaligned with debug data
  [0x10084] cmp x9, x8
  [0x10088] b.ne #0x101e8
  [0x1008C] add x16, x6, x15
  [0x10090] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10094] movz x8, #0x20
  [0x10098] mov x9, x9
  [0x1009C] and x9, x9, x8
  [0x100A0] movz x8, #0
  [0x100A4] mov x1, x14
  [0x100A8] sub x1, x1, x15 ;; misaligned with debug data
  [0x100AC] cmp x9, x8
  [0x100B0] b.eq #0x100c0
  [0x100B4] add x1, x14, #8
  [0x100B8] sub x1, x1, x15 ;; misaligned with debug data
  [0x100BC] mov x1, x1
  [0x100C0] mov x9, x1
  [0x100C4] mov x8, x14
  [0x100C8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100CC] cmp x9, x8
  [0x100D0] b.eq #0x101e4
  [0x100D4] add x16, x6, x15
  [0x100D8] ldr w9, [x16, #0x44] ;; misaligned with debug data
  [0x100DC] adrp x8, #0x10000
  [0x100E0] add x8, x8, #0
  [0x100E4] mov x1, x14
  [0x100E8] sub x1, x1, x15 ;; misaligned with debug data
  [0x100EC] cmp x9, x8
  [0x100F0] b.ne #0x10100
  [0x100F4] add x1, x14, #8
  [0x100F8] sub x1, x1, x15 ;; misaligned with debug data
  [0x100FC] mov x1, x1
  [0x10100] mov x9, x1
  [0x10104] mov x8, x14
  [0x10108] sub x8, x8, x15 ;; misaligned with debug data
  [0x1010C] cmp x9, x8
  [0x10110] b.eq #0x101e4
  [0x10114] add x16, x13, x15
  [0x10118] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x1011C] add x16, x9, x15
  [0x10120] ldrsw x9, [x16, #0x24] ;; misaligned with debug data
  [0x10124] movz x8, #0x2
  [0x10128] mov x1, x14
  [0x1012C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10130] cmp x9, x8
  [0x10134] b.ne #0x10144
  [0x10138] add x1, x14, #8
  [0x1013C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10140] mov x1, x1
  [0x10144] mov x9, x1
  [0x10148] mov x8, x14
  [0x1014C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10150] cmp x9, x8
  [0x10154] b.eq #0x10190
  [0x10158] add x16, x13, x15
  [0x1015C] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x10160] add x16, x9, x15
  [0x10164] ldr s23, [x16, #0x28] ;; misaligned with debug data
  [0x10168] adrp x16, #0x15000
  [0x1016C] ldr s22, [x16, #0xf48]
  [0x10170] mov x9, x14
  [0x10174] sub x9, x9, x15 ;; misaligned with debug data
  [0x10178] fcmp s23, s22
  [0x1017C] b.mi #0x1018c
  [0x10180] add x9, x14, #8
  [0x10184] sub x9, x9, x15 ;; misaligned with debug data
  [0x10188] mov x9, x9
  [0x1018C] mov x9, x9
  [0x10190] mov x9, x9
  [0x10194] mov x8, x14
  [0x10198] sub x8, x8, x15 ;; misaligned with debug data
  [0x1019C] cmp x9, x8
  [0x101A0] b.eq #0x101e0
  [0x101A4] movz x9, #0x2
  [0x101A8] movk x9, #0x10, lsl #16
  [0x101AC] add x16, x13, x15
  [0x101B0] ldr w8, [x16, #0xa0] ;; misaligned with debug data
  [0x101B4] mov x9, x9
  [0x101B8] and x9, x9, x8
  [0x101BC] movz x8, #0
  [0x101C0] mov x1, x14
  [0x101C4] sub x1, x1, x15 ;; misaligned with debug data
  [0x101C8] cmp x9, x8
  [0x101CC] b.eq #0x101dc
  [0x101D0] add x1, x14, #8
  [0x101D4] sub x1, x1, x15 ;; misaligned with debug data
  [0x101D8] mov x1, x1
  [0x101DC] mov x9, x1
  [0x101E0] mov x9, x9
  [0x101E4] mov x9, x9
  [0x101E8] mov x8, x14
  [0x101EC] sub x8, x8, x15 ;; misaligned with debug data
  [0x101F0] cmp x9, x8
  [0x101F4] b.eq #0x1024c
  [0x101F8] mov x9, x3
  [0x101FC] adrp x8, #0x10000
  [0x10200] add x8, x8, #0
  [0x10204] cmp x9, x8
  [0x10208] b.ne #0x10210
  [0x1020C] b #0x10244
  [0x10210] adrp x8, #0x10000
  [0x10214] add x8, x8, #0
  [0x10218] cmp x9, x8
  [0x1021C] b.ne #0x10234
  [0x10220] adrp x0, #0x10000
  [0x10224] add x0, x0, #0
  [0x10228] mov x3, x0
  [0x1022C] mov x0, x0
  [0x10230] b #0x10244
  [0x10234] mov x0, x14
  [0x10238] sub x0, x0, x15 ;; misaligned with debug data
  [0x1023C] mov x0, x0
  [0x10240] b #0x10c4c
  [0x10244] mov x9, x0
  [0x10248] b #0x102e0
  [0x1024C] mov x9, x3
  [0x10250] adrp x8, #0x10000
  [0x10254] add x8, x8, #0
  [0x10258] mov x1, x14
  [0x1025C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10260] cmp x9, x8
  [0x10264] b.ne #0x10274
  [0x10268] add x1, x14, #8
  [0x1026C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10270] mov x1, x1
  [0x10274] mov x8, x1
  [0x10278] mov x1, x14
  [0x1027C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10280] cmp x8, x1
  [0x10284] b.ne #0x102b0
  [0x10288] adrp x8, #0x10000
  [0x1028C] add x8, x8, #0
  [0x10290] mov x1, x14
  [0x10294] sub x1, x1, x15 ;; misaligned with debug data
  [0x10298] cmp x9, x8
  [0x1029C] b.ne #0x102ac
  [0x102A0] add x1, x14, #8
  [0x102A4] sub x1, x1, x15 ;; misaligned with debug data
  [0x102A8] mov x1, x1
  [0x102AC] mov x8, x1
  [0x102B0] mov x9, x14
  [0x102B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x102B8] cmp x8, x9
  [0x102BC] b.eq #0x102d4
  [0x102C0] adrp x9, #0x10000
  [0x102C4] add x9, x9, #0
  [0x102C8] mov x3, x9
  [0x102CC] mov x9, x9
  [0x102D0] b #0x102dc
  [0x102D4] mov x9, x14
  [0x102D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x102DC] mov x9, x9
  [0x102E0] adrp x16, #0x10000
  [0x102E4] add x16, x16, #0
  [0x102E8] ldr w9, [x16]
  [0x102EC] movz x7, #0x14c
  [0x102F0] add x7, x7, x13
  [0x102F4] mov x7, x7
  [0x102F8] mov x6, x6
  [0x102FC] movz x2, #0x68
  [0x10300] mov x9, x9
  [0x10304] mov x7, x7
  [0x10308] mov x6, x6
  [0x1030C] mov x2, x2
  [0x10310] add x9, x9, x15
  [0x10314] stp x3, x5, [sp, #-0x10]!
  [0x10318] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1031C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10320] blr x9 ;; misaligned with debug data
  [0x10324] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10328] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1032C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10330] mov x0, x0
  [0x10334] mov x9, x14
  [0x10338] sub x9, x9, x15 ;; misaligned with debug data
  [0x1033C] cmp x11, x9
  [0x10340] b.eq #0x10444
  [0x10344] add x16, x13, x15
  [0x10348] ldr w6, [x16, #0x6c] ;; misaligned with debug data
  [0x1034C] movz x2, #0xffff
  [0x10350] movk x2, #0xffff, lsl #16
  [0x10354] movk x2, #0xffff, lsl #32
  [0x10358] movk x2, #0xffff, lsl #48
  [0x1035C] mov x2, x2
  [0x10360] adrp x16, #0x10000
  [0x10364] add x16, x16, #0
  [0x10368] ldr w9, [x16]
  [0x1036C] add x16, x9, x15
  [0x10370] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x10374] mov x9, x9
  [0x10378] mov x7, x11
  [0x1037C] mov x6, x6
  [0x10380] mov x2, x2
  [0x10384] add x9, x9, x15
  [0x10388] stp x3, x5, [sp, #-0x10]!
  [0x1038C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10390] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10394] blr x9 ;; misaligned with debug data
  [0x10398] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1039C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103A4] mov x0, x0
  [0x103A8] mov x0, x0
  [0x103AC] mov x9, x14
  [0x103B0] sub x9, x9, x15 ;; misaligned with debug data
  [0x103B4] cmp x0, x9
  [0x103B8] b.eq #0x10434
  [0x103BC] adrp x16, #0x10000
  [0x103C0] add x16, x16, #0
  [0x103C4] ldr w9, [x16]
  [0x103C8] movz x7, #0x16c
  [0x103CC] add x7, x7, x13
  [0x103D0] add x16, x13, x15
  [0x103D4] ldr w2, [x16, #0x6c] ;; misaligned with debug data
  [0x103D8] mov x9, x9
  [0x103DC] mov x7, x7
  [0x103E0] mov x6, x0
  [0x103E4] mov x2, x2
  [0x103E8] mov x1, x11
  [0x103EC] add x9, x9, x15
  [0x103F0] stp x3, x5, [sp, #-0x10]!
  [0x103F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103FC] blr x9 ;; misaligned with debug data
  [0x10400] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10404] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10408] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1040C] mov x0, x0
  [0x10410] add x16, x13, x15
  [0x10414] ldr w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10418] mov x9, x9
  [0x1041C] movz x8, #0x4
  [0x10420] orr x9, x9, x8
  [0x10424] add x16, x13, x15
  [0x10428] str w9, [x16, #0x18c] ;; misaligned with debug data
  [0x1042C] mov x9, x9
  [0x10430] b #0x1043c
  [0x10434] mov x9, x14
  [0x10438] sub x9, x9, x15 ;; misaligned with debug data
  [0x1043C] mov x9, x9
  [0x10440] b #0x1044c
  [0x10444] mov x9, x14
  [0x10448] sub x9, x9, x15 ;; misaligned with debug data
  [0x1044C] add x16, x13, x15
  [0x10450] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10454] add x16, x13, x15
  [0x10458] str w9, [x16, #0x1b0] ;; misaligned with debug data
  [0x1045C] add x16, x13, x15
  [0x10460] ldr w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10464] mov x9, x9
  [0x10468] movz x8, #0x2000
  [0x1046C] orr x9, x9, x8
  [0x10470] add x16, x13, x15
  [0x10474] str w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10478] add x16, x13, x15
  [0x1047C] ldr w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10480] movz x8, #0x8
  [0x10484] mov x9, x9
  [0x10488] and x9, x9, x8
  [0x1048C] movz x8, #0
  [0x10490] cmp x9, x8
  [0x10494] b.ne #0x1052c
  [0x10498] mov x12, x12
  [0x1049C] mov x9, x14
  [0x104A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x104A4] cmp x12, x9
  [0x104A8] b.eq #0x104bc
  [0x104AC] add x16, x12, x15
  [0x104B0] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x104B4] mov x9, x9
  [0x104B8] b #0x104c4
  [0x104BC] mov x9, x14
  [0x104C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x104C4] mov x9, x9
  [0x104C8] mov x9, x9
  [0x104CC] add x16, x9, x15
  [0x104D0] ldr w8, [x16] ;; misaligned with debug data
  [0x104D4] add x16, x8, x15
  [0x104D8] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x104DC] movz x1, #0
  [0x104E0] mov x9, x9
  [0x104E4] lsl x9, x9, #0x20
  [0x104E8] lsr x9, x9, #0x20
  [0x104EC] orr x1, x1, x9
  [0x104F0] mov x8, x8
  [0x104F4] lsl x8, x8, #0x20
  [0x104F8] orr x1, x1, x8
  [0x104FC] add x16, x13, x15
  [0x10500] add x16, x16, #0x17c ;; misaligned with debug data
  [0x10504] str x1, [x16] ;; misaligned with debug data
  [0x10508] add x16, x13, x15
  [0x1050C] ldr w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10510] mov x9, x9
  [0x10514] movz x8, #0x8
  [0x10518] orr x9, x9, x8
  [0x1051C] add x16, x13, x15
  [0x10520] str w9, [x16, #0x18c] ;; misaligned with debug data
  [0x10524] mov x9, x9
  [0x10528] b #0x10534
  [0x1052C] mov x9, x14
  [0x10530] sub x9, x9, x15 ;; misaligned with debug data
  [0x10534] add x16, x13, x15
  [0x10538] ldr w9, [x16, #0x18c] ;; misaligned with debug data
  [0x1053C] movz x8, #0x20
  [0x10540] mov x9, x9
  [0x10544] and x9, x9, x8
  [0x10548] movz x8, #0
  [0x1054C] mov x1, x14
  [0x10550] sub x1, x1, x15 ;; misaligned with debug data
  [0x10554] cmp x9, x8
  [0x10558] b.eq #0x10568
  [0x1055C] add x1, x14, #8
  [0x10560] sub x1, x1, x15 ;; misaligned with debug data
  [0x10564] mov x1, x1
  [0x10568] mov x9, x1
  [0x1056C] mov x8, x14
  [0x10570] sub x8, x8, x15 ;; misaligned with debug data
  [0x10574] cmp x9, x8
  [0x10578] b.eq #0x10668
  [0x1057C] add x16, x13, x15
  [0x10580] ldr w9, [x16, #0x190] ;; misaligned with debug data
  [0x10584] adrp x8, #0x10000
  [0x10588] add x8, x8, #0
  [0x1058C] mov x1, x14
  [0x10590] sub x1, x1, x15 ;; misaligned with debug data
  [0x10594] cmp x9, x8
  [0x10598] b.ne #0x105a8
  [0x1059C] add x1, x14, #8
  [0x105A0] sub x1, x1, x15 ;; misaligned with debug data
  [0x105A4] mov x1, x1
  [0x105A8] mov x9, x1
  [0x105AC] mov x8, x14
  [0x105B0] sub x8, x8, x15 ;; misaligned with debug data
  [0x105B4] cmp x9, x8
  [0x105B8] b.eq #0x10664
  [0x105BC] add x16, x13, x15
  [0x105C0] ldr w9, [x16, #0xb4] ;; misaligned with debug data
  [0x105C4] add x16, x9, x15
  [0x105C8] ldr w9, [x16] ;; misaligned with debug data
  [0x105CC] adrp x8, #0x10000
  [0x105D0] add x8, x8, #0
  [0x105D4] mov x1, x14
  [0x105D8] sub x1, x1, x15 ;; misaligned with debug data
  [0x105DC] cmp x9, x8
  [0x105E0] b.ne #0x105f0
  [0x105E4] add x1, x14, #8
  [0x105E8] sub x1, x1, x15 ;; misaligned with debug data
  [0x105EC] mov x1, x1
  [0x105F0] mov x9, x1
  [0x105F4] mov x8, x14
  [0x105F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x105FC] cmp x9, x8
  [0x10600] b.eq #0x1063c
  [0x10604] adrp x16, #0x14000
  [0x10608] ldr s23, [x16, #0xf4c]
  [0x1060C] add x16, x13, x15
  [0x10610] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x10614] add x16, x9, x15
  [0x10618] ldr s22, [x16, #0x3c] ;; misaligned with debug data
  [0x1061C] mov x9, x14
  [0x10620] sub x9, x9, x15 ;; misaligned with debug data
  [0x10624] fcmp s23, s22
  [0x10628] b.mi #0x10638
  [0x1062C] add x9, x14, #8
  [0x10630] sub x9, x9, x15 ;; misaligned with debug data
  [0x10634] mov x9, x9
  [0x10638] mov x9, x9
  [0x1063C] mov x8, x14
  [0x10640] sub x8, x8, x15 ;; misaligned with debug data
  [0x10644] mov x1, x14
  [0x10648] sub x1, x1, x15 ;; misaligned with debug data
  [0x1064C] cmp x9, x8
  [0x10650] b.ne #0x10660
  [0x10654] add x1, x14, #8
  [0x10658] sub x1, x1, x15 ;; misaligned with debug data
  [0x1065C] mov x1, x1
  [0x10660] mov x9, x1
  [0x10664] mov x9, x9
  [0x10668] mov x8, x14
  [0x1066C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10670] cmp x9, x8
  [0x10674] b.eq #0x10ad4
  [0x10678] add x16, x13, x15
  [0x1067C] ldr w7, [x16, #0x8c] ;; misaligned with debug data
  [0x10680] movz x6, #0x4
  [0x10684] adrp x16, #0x14000
  [0x10688] ldr s23, [x16, #0xf50]
  [0x1068C] adrp x16, #0x10000
  [0x10690] add x16, x16, #0
  [0x10694] ldr w9, [x16]
  [0x10698] add x16, x9, x15
  [0x1069C] ldr s22, [x16, #0x28] ;; misaligned with debug data
  [0x106A0] fsub s23, s23, s22
  [0x106A4] mov x1, x14
  [0x106A8] sub x1, x1, x15 ;; misaligned with debug data
  [0x106AC] mov x1, x1
  [0x106B0] add x16, x7, x15
  [0x106B4] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x106B8] add x16, x9, x15
  [0x106BC] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x106C0] mov x9, x9
  [0x106C4] mov x7, x7
  [0x106C8] mov x6, x6
  [0x106CC] fmov w2, s23
  [0x106D0] sxtw x2, w2
  [0x106D4] mov x1, x1
  [0x106D8] add x9, x9, x15
  [0x106DC] stp x3, x5, [sp, #-0x10]!
  [0x106E0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106E4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106E8] blr x9 ;; misaligned with debug data
  [0x106EC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106F0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106F4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x106F8] mov x0, x0
  [0x106FC] adrp x16, #0x10000
  [0x10700] add x16, x16, #0
  [0x10704] ldr w7, [x16]
  [0x10708] adrp x16, #0x10000
  [0x1070C] add x16, x16, #0
  [0x10710] ldr w6, [x16]
  [0x10714] movz x2, #0x4000
  [0x10718] add x16, x7, x15
  [0x1071C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10720] add x16, x9, x15
  [0x10724] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x10728] mov x9, x9
  [0x1072C] mov x7, x7
  [0x10730] mov x6, x6
  [0x10734] mov x2, x2
  [0x10738] add x9, x9, x15
  [0x1073C] stp x3, x5, [sp, #-0x10]!
  [0x10740] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10744] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10748] blr x9 ;; misaligned with debug data
  [0x1074C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10750] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10754] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10758] mov x0, x0
  [0x1075C] mov x3, x0
  [0x10760] mov x3, x3
  [0x10764] mov x9, x14
  [0x10768] sub x9, x9, x15 ;; misaligned with debug data
  [0x1076C] cmp x3, x9
  [0x10770] b.eq #0x108d4
  [0x10774] adrp x16, #0x10000
  [0x10778] add x16, x16, #0
  [0x1077C] ldr w9, [x16]
  [0x10780] add x16, x9, x15
  [0x10784] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10788] adrp x2, #0x10000
  [0x1078C] add x2, x2, #0
  [0x10790] movz x1, #0x4000
  [0x10794] movk x1, #0x7000, lsl #16
  [0x10798] mov x1, x1
  [0x1079C] mov x9, x9
  [0x107A0] mov x7, x3
  [0x107A4] mov x6, x13
  [0x107A8] mov x2, x2
  [0x107AC] mov x1, x1
  [0x107B0] add x9, x9, x15
  [0x107B4] stp x3, x5, [sp, #-0x10]!
  [0x107B8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x107BC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x107C0] blr x9 ;; misaligned with debug data
  [0x107C4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x107C8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x107CC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x107D0] mov x0, x0
  [0x107D4] adrp x16, #0x10000
  [0x107D8] add x16, x16, #0
  [0x107DC] ldr w9, [x16]
  [0x107E0] mov x7, x9
  [0x107E4] adrp x16, #0x10000
  [0x107E8] add x16, x16, #0
  [0x107EC] ldr w6, [x16]
  [0x107F0] adrp x16, #0x10000
  [0x107F4] add x16, x16, #0
  [0x107F8] ldr w9, [x16]
  [0x107FC] add x16, x9, x15
  [0x10800] ldr w2, [x16, #0x10] ;; misaligned with debug data
  [0x10804] movz x1, #0xffff
  [0x10808] movk x1, #0xffff, lsl #16
  [0x1080C] movk x1, #0xffff, lsl #32
  [0x10810] movk x1, #0xffff, lsl #48
  [0x10814] mov x8, x14
  [0x10818] sub x8, x8, x15 ;; misaligned with debug data
  [0x1081C] mov x9, x14
  [0x10820] sub x9, x9, x15 ;; misaligned with debug data
  [0x10824] mov x10, x14
  [0x10828] sub x10, x10, x15 ;; misaligned with debug data
  [0x1082C] add x16, x13, x15
  [0x10830] ldr w0, [x16, #0x18c] ;; misaligned with debug data
  [0x10834] movz x5, #0x4
  [0x10838] mov x0, x0
  [0x1083C] and x0, x0, x5
  [0x10840] movz x5, #0
  [0x10844] cmp x0, x5
  [0x10848] b.eq #0x1085c
  [0x1084C] movz x11, #0x16c
  [0x10850] add x11, x11, x13
  [0x10854] mov x11, x11
  [0x10858] b #0x10878
  [0x1085C] movz x11, #0xc
  [0x10860] add x16, x13, x15
  [0x10864] ldr w0, [x16, #0x6c] ;; misaligned with debug data
  [0x10868] add x16, x0, x15
  [0x1086C] ldr w0, [x16, #0x9c] ;; misaligned with debug data
  [0x10870] add x11, x11, x0
  [0x10874] mov x11, x11
  [0x10878] mov x5, x7
  [0x1087C] mov x7, x3
  [0x10880] mov x6, x6
  [0x10884] mov x2, x2
  [0x10888] mov x1, x1
  [0x1088C] mov x8, x8
  [0x10890] mov x9, x9
  [0x10894] mov x10, x10
  [0x10898] mov x11, x11
  [0x1089C] add x5, x5, x15
  [0x108A0] stp x3, x5, [sp, #-0x10]!
  [0x108A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108AC] blr x5 ;; misaligned with debug data
  [0x108B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108BC] mov x0, x0
  [0x108C0] add x16, x3, x15
  [0x108C4] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x108C8] mov x9, x9
  [0x108CC] mov x9, x9
  [0x108D0] b #0x108dc
  [0x108D4] mov x9, x14
  [0x108D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x108DC] adrp x16, #0x10000
  [0x108E0] add x16, x16, #0
  [0x108E4] ldr w9, [x16]
  [0x108E8] add x16, x13, x15
  [0x108EC] ldr w8, [x16, #0x18c] ;; misaligned with debug data
  [0x108F0] movz x1, #0x10
  [0x108F4] mov x8, x8
  [0x108F8] and x8, x8, x1
  [0x108FC] movz x1, #0
  [0x10900] cmp x8, x1
  [0x10904] b.eq #0x1091c
  [0x10908] add x16, x13, x15
  [0x1090C] add x16, x16, #0x184 ;; misaligned with debug data
  [0x10910] ldr x7, [x16] ;; misaligned with debug data
  [0x10914] mov x7, x7
  [0x10918] b #0x10934
  [0x1091C] adrp x16, #0x10000
  [0x10920] add x16, x16, #0
  [0x10924] ldr w8, [x16]
  [0x10928] add x16, x8, x15
  [0x1092C] ldur x7, [x16, #0xc4] ;; misaligned with debug data
  [0x10930] mov x7, x7
  [0x10934] mov x9, x9
  [0x10938] mov x7, x7
  [0x1093C] mov x6, x13
  [0x10940] add x9, x9, x15
  [0x10944] stp x3, x5, [sp, #-0x10]!
  [0x10948] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1094C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10950] blr x9 ;; misaligned with debug data
  [0x10954] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10958] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1095C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10960] mov x3, x3
  [0x10964] adrp x16, #0x10000
  [0x10968] add x16, x16, #0
  [0x1096C] ldr w9, [x16]
  [0x10970] adrp x16, #0x10000
  [0x10974] add x16, x16, #0
  [0x10978] ldr w8, [x16]
  [0x1097C] add x16, x8, x15
  [0x10980] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x10984] movz x6, #0
  [0x10988] movz x2, #0xff
  [0x1098C] movz x1, #0x96
  [0x10990] mov x9, x9
  [0x10994] mov x7, x7
  [0x10998] mov x6, x6
  [0x1099C] mov x2, x2
  [0x109A0] mov x1, x1
  [0x109A4] add x9, x9, x15
  [0x109A8] stp x3, x5, [sp, #-0x10]!
  [0x109AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x109B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109B4] blr x9 ;; misaligned with debug data
  [0x109B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x109C4] mov x3, x3
  [0x109C8] adrp x16, #0x10000
  [0x109CC] add x16, x16, #0
  [0x109D0] ldr w3, [x16]
  [0x109D4] movz x9, #0x6f6f
  [0x109D8] movk x9, #0x66, lsl #16
  [0x109DC] fmov d23, x9
  [0x109E0] movz x9, #0
  [0x109E4] fmov d24, x9
  [0x109E8] zip1 v24.2d, v23.2d, v24.2d
  [0x109EC] adrp x16, #0x10000
  [0x109F0] add x16, x16, #0
  [0x109F4] ldr w9, [x16]
  [0x109F8] mov x9, x9
  [0x109FC] add x9, x9, x15
  [0x10A00] stp x3, x5, [sp, #-0x10]!
  [0x10A04] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A08] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A0C] blr x9 ;; misaligned with debug data
  [0x10A10] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A14] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A18] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A1C] mov x0, x0
  [0x10A20] adrp x16, #0x14000
  [0x10A24] ldr s23, [x16, #0xf54]
  [0x10A28] adrp x16, #0x14000
  [0x10A2C] ldr s22, [x16, #0xf58]
  [0x10A30] mov v23.16b, v23.16b
  [0x10A34] fdiv s23, s23, s22
  [0x10A38] mov v23.16b, v23.16b
  [0x10A3C] adrp x16, #0x14000
  [0x10A40] ldr s22, [x16, #0xf5c]
  [0x10A44] fmul s23, s23, s22
  [0x10A48] fcvtzs w6, s23
  [0x10A4C] sxtw x6, w6
  [0x10A50] adrp x16, #0x14000
  [0x10A54] ldr s23, [x16, #0xf60]
  [0x10A58] mov v23.16b, v23.16b
  [0x10A5C] movz x9, #0
  [0x10A60] scvtf s22, w9
  [0x10A64] fmul s23, s23, s22
  [0x10A68] fcvtzs w2, s23
  [0x10A6C] sxtw x2, w2
  [0x10A70] movz x1, #0
  [0x10A74] movz x8, #0x1
  [0x10A78] add x9, x14, #8
  [0x10A7C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10A80] mov x3, x3
  [0x10A84] mov v17.16b, v24.16b
  [0x10A88] mov x7, x0
  [0x10A8C] mov x6, x6
  [0x10A90] mov x2, x2
  [0x10A94] mov x1, x1
  [0x10A98] mov x8, x8
  [0x10A9C] mov x9, x9
  [0x10AA0] add x3, x3, x15
  [0x10AA4] stp x3, x5, [sp, #-0x10]!
  [0x10AA8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AAC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AB0] blr x3 ;; misaligned with debug data
  [0x10AB4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10AB8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10ABC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AC0] mov x0, x0
  [0x10AC4] add x0, x14, #8
  [0x10AC8] sub x0, x0, x15 ;; misaligned with debug data
  [0x10ACC] mov x0, x0
  [0x10AD0] b #0x10c38
  [0x10AD4] add x16, x13, x15
  [0x10AD8] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10ADC] mov x9, x9
  [0x10AE0] movz x8, #0x8
  [0x10AE4] orr x9, x9, x8
  [0x10AE8] add x16, x13, x15
  [0x10AEC] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10AF0] add x16, x13, x15
  [0x10AF4] ldr w9, [x16, #0xb4] ;; misaligned with debug data
  [0x10AF8] add x16, x9, x15
  [0x10AFC] ldr w9, [x16] ;; misaligned with debug data
  [0x10B00] adrp x8, #0x10000
  [0x10B04] add x8, x8, #0
  [0x10B08] mov x1, x14
  [0x10B0C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10B10] cmp x9, x8
  [0x10B14] b.ne #0x10b24
  [0x10B18] add x1, x14, #8
  [0x10B1C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10B20] mov x1, x1
  [0x10B24] mov x9, x1
  [0x10B28] mov x8, x14
  [0x10B2C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10B30] cmp x9, x8
  [0x10B34] b.eq #0x10bac
  [0x10B38] adrp x16, #0x14000
  [0x10B3C] ldr s23, [x16, #0xf64]
  [0x10B40] add x16, x13, x15
  [0x10B44] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x10B48] add x16, x9, x15
  [0x10B4C] ldr s22, [x16, #0x3c] ;; misaligned with debug data
  [0x10B50] mov x9, x14
  [0x10B54] sub x9, x9, x15 ;; misaligned with debug data
  [0x10B58] fcmp s23, s22
  [0x10B5C] b.mi #0x10b6c
  [0x10B60] add x9, x14, #8
  [0x10B64] sub x9, x9, x15 ;; misaligned with debug data
  [0x10B68] mov x9, x9
  [0x10B6C] mov x9, x9
  [0x10B70] mov x8, x14
  [0x10B74] sub x8, x8, x15 ;; misaligned with debug data
  [0x10B78] cmp x9, x8
  [0x10B7C] b.eq #0x10ba8
  [0x10B80] adrp x9, #0x10000
  [0x10B84] add x9, x9, #0
  [0x10B88] mov x8, x14
  [0x10B8C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10B90] cmp x3, x9
  [0x10B94] b.ne #0x10ba4
  [0x10B98] add x8, x14, #8
  [0x10B9C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10BA0] mov x8, x8
  [0x10BA4] mov x9, x8
  [0x10BA8] mov x9, x9
  [0x10BAC] mov x8, x14
  [0x10BB0] sub x8, x8, x15 ;; misaligned with debug data
  [0x10BB4] cmp x9, x8
  [0x10BB8] b.eq #0x10be0
  [0x10BBC] add x16, x13, x15
  [0x10BC0] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10BC4] mov x9, x9
  [0x10BC8] movz x8, #0x8000
  [0x10BCC] orr x9, x9, x8
  [0x10BD0] add x16, x13, x15
  [0x10BD4] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10BD8] mov x9, x9
  [0x10BDC] b #0x10be8
  [0x10BE0] mov x9, x14
  [0x10BE4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BE8] add x16, x13, x15
  [0x10BEC] str w5, [x16, #0x48] ;; misaligned with debug data
  [0x10BF0] movz x6, #0x14c
  [0x10BF4] add x6, x6, x13
  [0x10BF8] adrp x16, #0x10000
  [0x10BFC] add x16, x16, #0
  [0x10C00] ldr w9, [x16]
  [0x10C04] mov x9, x9
  [0x10C08] mov x7, x3
  [0x10C0C] mov x6, x6
  [0x10C10] add x9, x9, x15
  [0x10C14] stp x3, x5, [sp, #-0x10]!
  [0x10C18] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C1C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C20] blr x9 ;; misaligned with debug data
  [0x10C24] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C28] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C2C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C30] mov x0, x0
  [0x10C34] mov x0, x0
  [0x10C38] mov x0, x0
  [0x10C3C] b #0x10c48
  [0x10C40] mov x0, x14
  [0x10C44] sub x0, x0, x15 ;; misaligned with debug data
  [0x10C48] mov x0, x0
  [0x10C4C] add sp, sp, #0x10
  [0x10C50] ldr q24, [sp], #0x10
  [0x10C54] ldp x29, x30, [sp], #0x10
  [0x10C58] ret


[target-shoved]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] mov x2, x2
  [0x10018] mov x5, x1
  [0x1001C] adrp x3, #0x15000
  [0x10020] add x3, x3, #0xee0
  [0x10024] sub x3, x3, x15
  [0x10028] mov x3, x3
  [0x1002C] mov x2, x2
  [0x10030] mov x9, x14
  [0x10034] sub x9, x9, x15 ;; misaligned with debug data
  [0x10038] cmp x2, x9
  [0x1003C] b.eq #0x10050
  [0x10040] add x16, x2, x15
  [0x10044] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10048] mov x9, x9
  [0x1004C] b #0x10058
  [0x10050] mov x9, x14
  [0x10054] sub x9, x9, x15 ;; misaligned with debug data
  [0x10058] mov x9, x9
  [0x1005C] mov x9, x9
  [0x10060] add x16, x9, x15
  [0x10064] ldr w8, [x16] ;; misaligned with debug data
  [0x10068] add x16, x8, x15
  [0x1006C] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10070] movz x1, #0
  [0x10074] mov x9, x9
  [0x10078] lsl x9, x9, #0x20
  [0x1007C] lsr x9, x9, #0x20
  [0x10080] orr x1, x1, x9
  [0x10084] mov x8, x8
  [0x10088] lsl x8, x8, #0x20
  [0x1008C] orr x1, x1, x8
  [0x10090] add x16, x3, x15
  [0x10094] str x1, [x16, #0x30] ;; misaligned with debug data
  [0x10098] add x16, x3, x15
  [0x1009C] str w7, [x16, #0x48] ;; misaligned with debug data
  [0x100A0] add x16, x3, x15
  [0x100A4] str w6, [x16, #0x4c] ;; misaligned with debug data
  [0x100A8] add x16, x13, x15
  [0x100AC] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x100B0] add x16, x9, x15
  [0x100B4] add x16, x16, #0x10c ;; misaligned with debug data
  [0x100B8] ldr x9, [x16] ;; misaligned with debug data
  [0x100BC] mov x9, x9
  [0x100C0] add x16, x13, x15
  [0x100C4] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x100C8] add x16, x8, x15
  [0x100CC] add x16, x16, #0x114 ;; misaligned with debug data
  [0x100D0] ldr x8, [x16] ;; misaligned with debug data
  [0x100D4] orr x9, x9, x8
  [0x100D8] movz x8, #0x1
  [0x100DC] mov x9, x9
  [0x100E0] and x9, x9, x8
  [0x100E4] movz x8, #0
  [0x100E8] cmp x9, x8
  [0x100EC] b.ne #0x10100
  [0x100F0] adrp x9, #0x10000
  [0x100F4] add x9, x9, #0
  [0x100F8] mov x9, x9
  [0x100FC] b #0x1010c
  [0x10100] adrp x9, #0x10000
  [0x10104] add x9, x9, #0
  [0x10108] mov x9, x9
  [0x1010C] add x16, x3, x15
  [0x10110] str w9, [x16, #0x5c] ;; misaligned with debug data
  [0x10114] movz x9, #0x8c8
  [0x10118] add x16, x3, x15
  [0x1011C] str w9, [x16, #0x40] ;; misaligned with debug data
  [0x10120] adrp x16, #0x10000
  [0x10124] add x16, x16, #0
  [0x10128] ldr w9, [x16]
  [0x1012C] adrp x16, #0x10000
  [0x10130] add x16, x16, #0
  [0x10134] ldr w8, [x16]
  [0x10138] add x16, x8, x15
  [0x1013C] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x10140] movz x6, #0x1
  [0x10144] movz x2, #0xff
  [0x10148] movz x1, #0x1e
  [0x1014C] mov x9, x9
  [0x10150] mov x7, x7
  [0x10154] mov x6, x6
  [0x10158] mov x2, x2
  [0x1015C] mov x1, x1
  [0x10160] add x9, x9, x15
  [0x10164] stp x3, x5, [sp, #-0x10]!
  [0x10168] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1016C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10170] blr x9 ;; misaligned with debug data
  [0x10174] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10178] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1017C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10180] mov x12, x12
  [0x10184] add x16, x13, x15
  [0x10188] str w5, [x16, #0x48] ;; misaligned with debug data
  [0x1018C] adrp x7, #0x10000
  [0x10190] add x7, x7, #0
  [0x10194] adrp x16, #0x10000
  [0x10198] add x16, x16, #0
  [0x1019C] ldr w9, [x16]
  [0x101A0] mov x9, x9
  [0x101A4] mov x7, x7
  [0x101A8] mov x6, x3
  [0x101AC] add x9, x9, x15
  [0x101B0] stp x3, x5, [sp, #-0x10]!
  [0x101B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101BC] blr x9 ;; misaligned with debug data
  [0x101C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101CC] mov x0, x0
  [0x101D0] mov x0, x0
  [0x101D4] add sp, sp, #0x10
  [0x101D8] ldp x29, x30, [sp], #0x10
  [0x101DC] ret


[target-generic-event-handler]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0x50
  [0x10010] mov x12, x7
  [0x10014] mov x6, x6
  [0x10018] mov x2, x2
  [0x1001C] mov x5, x1
  [0x10020] mov x9, x2
  [0x10024] adrp x8, #0x10000
  [0x10028] add x8, x8, #0
  [0x1002C] cmp x9, x8
  [0x10030] b.ne #0x101e0
  [0x10034] add x16, x13, x15
  [0x10038] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x1003C] movz x8, #0x8000
  [0x10040] mov x9, x9
  [0x10044] and x9, x9, x8
  [0x10048] movz x8, #0
  [0x1004C] cmp x9, x8
  [0x10050] b.ne #0x101d0
  [0x10054] add x16, x5, x15
  [0x10058] ldr x3, [x16, #0x10] ;; misaligned with debug data
  [0x1005C] add x16, x5, x15
  [0x10060] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10064] mov x9, x9
  [0x10068] mov x5, x3
  [0x1006C] fmov s24, w9
  [0x10070] add x16, x13, x15
  [0x10074] ldr w7, [x16, #0x8c] ;; misaligned with debug data
  [0x10078] mov x6, x5
  [0x1007C] adrp x16, #0x16000
  [0x10080] ldr s23, [x16, #0xea8]
  [0x10084] mov v23.16b, v23.16b
  [0x10088] mov x1, x14
  [0x1008C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10090] mov x1, x1
  [0x10094] add x16, x7, x15
  [0x10098] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1009C] add x16, x9, x15
  [0x100A0] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x100A4] mov x9, x9
  [0x100A8] mov x7, x7
  [0x100AC] mov x6, x6
  [0x100B0] fmov w2, s23
  [0x100B4] sxtw x2, w2
  [0x100B8] mov x1, x1
  [0x100BC] add x9, x9, x15
  [0x100C0] stp x3, x5, [sp, #-0x10]!
  [0x100C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100CC] blr x9 ;; misaligned with debug data
  [0x100D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] mov x3, x0
  [0x100E0] add x16, x13, x15
  [0x100E4] ldr w7, [x16, #0x8c] ;; misaligned with debug data
  [0x100E8] mov x5, x5
  [0x100EC] mov x12, x12
  [0x100F0] mov x9, x14
  [0x100F4] sub x9, x9, x15 ;; misaligned with debug data
  [0x100F8] cmp x12, x9
  [0x100FC] b.eq #0x10110
  [0x10100] add x16, x12, x15
  [0x10104] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10108] mov x9, x9
  [0x1010C] b #0x10118
  [0x10110] mov x9, x14
  [0x10114] sub x9, x9, x15 ;; misaligned with debug data
  [0x10118] mov x9, x9
  [0x1011C] mov x9, x9
  [0x10120] add x16, x9, x15
  [0x10124] ldr w8, [x16] ;; misaligned with debug data
  [0x10128] add x16, x8, x15
  [0x1012C] ldrsw x8, [x16, #0x24] ;; misaligned with debug data
  [0x10130] movz x1, #0
  [0x10134] mov x9, x9
  [0x10138] lsl x9, x9, #0x20
  [0x1013C] lsr x9, x9, #0x20
  [0x10140] orr x1, x1, x9
  [0x10144] mov x8, x8
  [0x10148] lsl x8, x8, #0x20
  [0x1014C] orr x1, x1, x8
  [0x10150] add x16, x7, x15
  [0x10154] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10158] add x16, x9, x15
  [0x1015C] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10160] mov x9, x9
  [0x10164] mov x7, x7
  [0x10168] mov x6, x5
  [0x1016C] fmov w2, s24
  [0x10170] sxtw x2, w2
  [0x10174] mov x1, x1
  [0x10178] add x9, x9, x15
  [0x1017C] stp x3, x5, [sp, #-0x10]!
  [0x10180] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10184] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10188] blr x9 ;; misaligned with debug data
  [0x1018C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10190] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10194] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10198] mov x0, x0
  [0x1019C] fmov s23, w3
  [0x101A0] fmov s22, w0
  [0x101A4] fcmp s23, s22
  [0x101A8] b.eq #0x101bc
  [0x101AC] add x0, x14, #8
  [0x101B0] sub x0, x0, x15 ;; misaligned with debug data
  [0x101B4] mov x0, x0
  [0x101B8] b #0x101c8
  [0x101BC] adrp x0, #0x10000
  [0x101C0] add x0, x0, #0
  [0x101C4] mov x0, x0
  [0x101C8] mov x0, x0
  [0x101CC] b #0x101d8
  [0x101D0] mov x0, x14
  [0x101D4] sub x0, x0, x15 ;; misaligned with debug data
  [0x101D8] mov x0, x0
  [0x101DC] b #0x11a5c
  [0x101E0] adrp x8, #0x10000
  [0x101E4] add x8, x8, #0
  [0x101E8] cmp x9, x8
  [0x101EC] b.ne #0x1024c
  [0x101F0] add x16, x13, x15
  [0x101F4] ldr w7, [x16, #0x8c] ;; misaligned with debug data
  [0x101F8] add x16, x5, x15
  [0x101FC] ldr x6, [x16, #0x10] ;; misaligned with debug data
  [0x10200] mov x6, x6
  [0x10204] add x16, x7, x15
  [0x10208] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1020C] add x16, x9, x15
  [0x10210] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10214] mov x9, x9
  [0x10218] mov x7, x7
  [0x1021C] mov x6, x6
  [0x10220] add x9, x9, x15
  [0x10224] stp x3, x5, [sp, #-0x10]!
  [0x10228] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1022C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10230] blr x9 ;; misaligned with debug data
  [0x10234] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10238] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1023C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10240] mov x3, x3
  [0x10244] mov x0, x3
  [0x10248] b #0x11a5c
  [0x1024C] adrp x8, #0x10000
  [0x10250] add x8, x8, #0
  [0x10254] cmp x9, x8
  [0x10258] b.ne #0x10370
  [0x1025C] add x16, x13, x15
  [0x10260] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10264] add x16, x9, x15
  [0x10268] ldr w9, [x16, #0x72c] ;; misaligned with debug data
  [0x1026C] mov x8, x14
  [0x10270] sub x8, x8, x15 ;; misaligned with debug data
  [0x10274] cmp x9, x8
  [0x10278] b.eq #0x102e4
  [0x1027C] adrp x16, #0x10000
  [0x10280] add x16, x16, #0
  [0x10284] ldr w9, [x16]
  [0x10288] add x16, x13, x15
  [0x1028C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10290] add x16, x8, x15
  [0x10294] ldr w7, [x16, #0x72c] ;; misaligned with debug data
  [0x10298] add x16, x13, x15
  [0x1029C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x102A0] add x16, x8, x15
  [0x102A4] ldr s23, [x16, #0x730] ;; misaligned with debug data
  [0x102A8] mov x9, x9
  [0x102AC] mov x7, x7
  [0x102B0] fmov w6, s23
  [0x102B4] sxtw x6, w6
  [0x102B8] add x9, x9, x15
  [0x102BC] stp x3, x5, [sp, #-0x10]!
  [0x102C0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C8] blr x9 ;; misaligned with debug data
  [0x102CC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102D0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102D4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102D8] mov x0, x0
  [0x102DC] mov x0, x0
  [0x102E0] b #0x10368
  [0x102E4] add x16, x13, x15
  [0x102E8] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x102EC] add x16, x9, x15
  [0x102F0] ldr w9, [x16, #0x94c] ;; misaligned with debug data
  [0x102F4] mov x8, x14
  [0x102F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x102FC] cmp x9, x8
  [0x10300] b.eq #0x10360
  [0x10304] adrp x16, #0x10000
  [0x10308] add x16, x16, #0
  [0x1030C] ldr w9, [x16]
  [0x10310] add x16, x13, x15
  [0x10314] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10318] add x16, x8, x15
  [0x1031C] ldr w7, [x16, #0x94c] ;; misaligned with debug data
  [0x10320] mov x6, x14
  [0x10324] sub x6, x6, x15 ;; misaligned with debug data
  [0x10328] mov x9, x9
  [0x1032C] mov x7, x7
  [0x10330] mov x6, x6
  [0x10334] add x9, x9, x15
  [0x10338] stp x3, x5, [sp, #-0x10]!
  [0x1033C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10340] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10344] blr x9 ;; misaligned with debug data
  [0x10348] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1034C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10350] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10354] mov x0, x0
  [0x10358] mov x0, x0
  [0x1035C] b #0x10368
  [0x10360] mov x0, x14
  [0x10364] sub x0, x0, x15 ;; misaligned with debug data
  [0x10368] mov x0, x0
  [0x1036C] b #0x11a5c
  [0x10370] adrp x8, #0x10000
  [0x10374] add x8, x8, #0
  [0x10378] cmp x9, x8
  [0x1037C] b.ne #0x10390
  [0x10380] mov x0, x14
  [0x10384] sub x0, x0, x15 ;; misaligned with debug data
  [0x10388] mov x0, x0
  [0x1038C] b #0x11a5c
  [0x10390] adrp x8, #0x10000
  [0x10394] add x8, x8, #0
  [0x10398] cmp x9, x8
  [0x1039C] b.ne #0x10778
  [0x103A0] adrp x16, #0x10000
  [0x103A4] add x16, x16, #0
  [0x103A8] ldr w7, [x16]
  [0x103AC] add x16, x5, x15
  [0x103B0] ldr x6, [x16, #0x10] ;; misaligned with debug data
  [0x103B4] mov x6, x6
  [0x103B8] add x16, x7, x15
  [0x103BC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x103C0] add x16, x9, x15
  [0x103C4] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x103C8] mov x9, x9
  [0x103CC] mov x7, x7
  [0x103D0] mov x6, x6
  [0x103D4] add x9, x9, x15
  [0x103D8] stp x3, x5, [sp, #-0x10]!
  [0x103DC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103E0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103E4] blr x9 ;; misaligned with debug data
  [0x103E8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103EC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103F0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103F4] mov x0, x0
  [0x103F8] mov x0, x0
  [0x103FC] mov x9, x14
  [0x10400] sub x9, x9, x15 ;; misaligned with debug data
  [0x10404] cmp x0, x9
  [0x10408] b.eq #0x10768
  [0x1040C] add x16, x0, x15
  [0x10410] ldr w3, [x16, #0x34] ;; misaligned with debug data
  [0x10414] mov x3, x3
  [0x10418] add x16, x3, x15
  [0x1041C] ldrsw x9, [x16, #0x58] ;; misaligned with debug data
  [0x10420] mov x9, x9
  [0x10424] movz x8, #0
  [0x10428] cmp x9, x8
  [0x1042C] b.ne #0x10454
  [0x10430] adrp x16, #0x16000
  [0x10434] ldr s23, [x16, #0xeac]
  [0x10438] add x16, x13, x15
  [0x1043C] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x10440] add x16, x9, x15
  [0x10444] str s23, [x16, #0x44] ;; misaligned with debug data
  [0x10448] fmov w9, s23
  [0x1044C] sxtw x9, w9
  [0x10450] b #0x104e8
  [0x10454] add x16, x13, x15
  [0x10458] ldr w7, [x16, #0x8c] ;; misaligned with debug data
  [0x1045C] movz x6, #0x8
  [0x10460] movz x8, #0
  [0x10464] movk x8, #0xffff, lsl #16
  [0x10468] movk x8, #0xffff, lsl #32
  [0x1046C] movk x8, #0xffff, lsl #48
  [0x10470] mov x8, x8
  [0x10474] orr x8, x8, x9
  [0x10478] scvtf s23, w8
  [0x1047C] mov x1, x14
  [0x10480] sub x1, x1, x15 ;; misaligned with debug data
  [0x10484] mov x1, x1
  [0x10488] add x16, x7, x15
  [0x1048C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10490] add x16, x9, x15
  [0x10494] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10498] mov x9, x9
  [0x1049C] mov x7, x7
  [0x104A0] mov x6, x6
  [0x104A4] fmov w2, s23
  [0x104A8] sxtw x2, w2
  [0x104AC] mov x1, x1
  [0x104B0] add x9, x9, x15
  [0x104B4] stp x3, x5, [sp, #-0x10]!
  [0x104B8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104BC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104C0] blr x9 ;; misaligned with debug data
  [0x104C4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104C8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104CC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104D0] mov x0, x0
  [0x104D4] add x16, x13, x15
  [0x104D8] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x104DC] add x16, x9, x15
  [0x104E0] str w0, [x16, #0x44] ;; misaligned with debug data
  [0x104E4] mov x9, x0
  [0x104E8] add x16, x3, x15
  [0x104EC] ldrsw x9, [x16, #0xc] ;; misaligned with debug data
  [0x104F0] movz x8, #0xc
  [0x104F4] mov x9, x9
  [0x104F8] lsl x9, x9, #3
  [0x104FC] add x9, x9, x8
  [0x10500] mov x9, x9
  [0x10504] adrp x16, #0x10000
  [0x10508] add x16, x16, #0
  [0x1050C] ldr w8, [x16]
  [0x10510] add x16, x8, x15
  [0x10514] ldr w8, [x16, #0xd0] ;; misaligned with debug data
  [0x10518] add x9, x9, x8
  [0x1051C] add x16, x9, x15
  [0x10520] ldr x9, [x16] ;; misaligned with debug data
  [0x10524] movz x8, #0
  [0x10528] mov x1, x14
  [0x1052C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10530] cmp x9, x8
  [0x10534] b.ne #0x10544
  [0x10538] add x1, x14, #8
  [0x1053C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10540] mov x1, x1
  [0x10544] mov x9, x1
  [0x10548] mov x8, x14
  [0x1054C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10550] cmp x9, x8
  [0x10554] b.eq #0x10594
  [0x10558] adrp x16, #0x10000
  [0x1055C] add x16, x16, #0
  [0x10560] ldr w9, [x16]
  [0x10564] add x16, x9, x15
  [0x10568] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1056C] add x16, x3, x15
  [0x10570] ldrsw x8, [x16, #0xc] ;; misaligned with debug data
  [0x10574] mov x1, x14
  [0x10578] sub x1, x1, x15 ;; misaligned with debug data
  [0x1057C] cmp x9, x8
  [0x10580] b.lt #0x10590
  [0x10584] add x1, x14, #8
  [0x10588] sub x1, x1, x15 ;; misaligned with debug data
  [0x1058C] mov x1, x1
  [0x10590] mov x9, x1
  [0x10594] mov x8, x14
  [0x10598] sub x8, x8, x15 ;; misaligned with debug data
  [0x1059C] cmp x9, x8
  [0x105A0] b.eq #0x10644
  [0x105A4] adrp x16, #0x10000
  [0x105A8] add x16, x16, #0
  [0x105AC] ldr w9, [x16]
  [0x105B0] add x16, x9, x15
  [0x105B4] add x16, x16, #0x30c ;; misaligned with debug data
  [0x105B8] ldr x9, [x16] ;; misaligned with debug data
  [0x105BC] add x16, x3, x15
  [0x105C0] ldrsw x8, [x16, #0xc] ;; misaligned with debug data
  [0x105C4] mov x8, x8
  [0x105C8] movz x1, #0xffff
  [0x105CC] movk x1, #0xffff, lsl #16
  [0x105D0] movk x1, #0xffff, lsl #32
  [0x105D4] movk x1, #0xffff, lsl #48
  [0x105D8] add x8, x8, x1
  [0x105DC] movz x1, #0xc
  [0x105E0] mov x8, x8
  [0x105E4] lsl x8, x8, #2
  [0x105E8] add x8, x8, x1
  [0x105EC] mov x8, x8
  [0x105F0] adrp x16, #0x10000
  [0x105F4] add x16, x16, #0
  [0x105F8] ldr w1, [x16]
  [0x105FC] add x8, x8, x1
  [0x10600] add x16, x8, x15
  [0x10604] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10608] movz x1, #0xc
  [0x1060C] mov x8, x8
  [0x10610] lsl x8, x8, #3
  [0x10614] add x8, x8, x1
  [0x10618] mov x8, x8
  [0x1061C] adrp x16, #0x10000
  [0x10620] add x16, x16, #0
  [0x10624] ldr w1, [x16]
  [0x10628] add x16, x1, x15
  [0x1062C] ldr w1, [x16, #0xd0] ;; misaligned with debug data
  [0x10630] add x8, x8, x1
  [0x10634] add x16, x8, x15
  [0x10638] str x9, [x16] ;; misaligned with debug data
  [0x1063C] mov x9, x9
  [0x10640] b #0x1064c
  [0x10644] mov x9, x14
  [0x10648] sub x9, x9, x15 ;; misaligned with debug data
  [0x1064C] mov x6, sp
  [0x10650] sub x6, x6, x15
  [0x10654] mov x6, x6
  [0x10658] add x16, x6, x15
  [0x1065C] str w13, [x16, #4] ;; misaligned with debug data
  [0x10660] movz x9, #0
  [0x10664] add x16, x6, x15
  [0x10668] str w9, [x16, #8] ;; misaligned with debug data
  [0x1066C] adrp x9, #0x10000
  [0x10670] add x9, x9, #0
  [0x10674] add x16, x6, x15
  [0x10678] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x1067C] adrp x16, #0x10000
  [0x10680] add x16, x16, #0
  [0x10684] ldr w9, [x16]
  [0x10688] adrp x16, #0x10000
  [0x1068C] add x16, x16, #0
  [0x10690] ldr w8, [x16]
  [0x10694] add x16, x8, x15
  [0x10698] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x1069C] mov x8, x8
  [0x106A0] mov x1, x14
  [0x106A4] sub x1, x1, x15 ;; misaligned with debug data
  [0x106A8] cmp x8, x1
  [0x106AC] b.eq #0x106c8
  [0x106B0] add x16, x8, x15
  [0x106B4] ldr w8, [x16] ;; misaligned with debug data
  [0x106B8] add x16, x8, x15
  [0x106BC] ldr w7, [x16, #0x18] ;; misaligned with debug data
  [0x106C0] mov x7, x7
  [0x106C4] b #0x106d0
  [0x106C8] mov x7, x14
  [0x106CC] sub x7, x7, x15 ;; misaligned with debug data
  [0x106D0] mov x7, x7
  [0x106D4] mov x9, x9
  [0x106D8] mov x7, x7
  [0x106DC] mov x6, x6
  [0x106E0] add x9, x9, x15
  [0x106E4] stp x3, x5, [sp, #-0x10]!
  [0x106E8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106EC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106F0] blr x9 ;; misaligned with debug data
  [0x106F4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106F8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106FC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10700] mov x0, x0
  [0x10704] adrp x16, #0x10000
  [0x10708] add x16, x16, #0
  [0x1070C] ldr w9, [x16]
  [0x10710] add x7, x14, #8
  [0x10714] sub x7, x7, x15 ;; misaligned with debug data
  [0x10718] adrp x6, #0x16000
  [0x1071C] add x6, x6, #0xeb4
  [0x10720] sub x6, x6, x15
  [0x10724] add x16, x5, x15
  [0x10728] ldr x2, [x16, #0x10] ;; misaligned with debug data
  [0x1072C] mov x9, x9
  [0x10730] mov x7, x7
  [0x10734] mov x6, x6
  [0x10738] mov x2, x2
  [0x1073C] add x9, x9, x15
  [0x10740] stp x3, x5, [sp, #-0x10]!
  [0x10744] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10748] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1074C] blr x9 ;; misaligned with debug data
  [0x10750] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10754] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10758] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1075C] mov x0, x0
  [0x10760] mov x0, x0
  [0x10764] b #0x10770
  [0x10768] mov x0, x14
  [0x1076C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10770] mov x0, x0
  [0x10774] b #0x11a5c
  [0x10778] adrp x8, #0x10000
  [0x1077C] add x8, x8, #0
  [0x10780] cmp x9, x8
  [0x10784] b.ne #0x107d0
  [0x10788] add x16, x13, x15
  [0x1078C] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10790] add x16, x9, x15
  [0x10794] add x16, x16, #0x95c ;; misaligned with debug data
  [0x10798] ldr x0, [x16] ;; misaligned with debug data
  [0x1079C] mov x0, x0
  [0x107A0] add x16, x5, x15
  [0x107A4] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x107A8] add x0, x0, x9
  [0x107AC] mov x0, x0
  [0x107B0] mov x9, x0
  [0x107B4] add x16, x13, x15
  [0x107B8] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x107BC] add x16, x8, x15
  [0x107C0] add x16, x16, #0x95c ;; misaligned with debug data
  [0x107C4] str x9, [x16] ;; misaligned with debug data
  [0x107C8] mov x0, x0
  [0x107CC] b #0x11a5c
  [0x107D0] adrp x8, #0x10000
  [0x107D4] add x8, x8, #0
  [0x107D8] cmp x9, x8
  [0x107DC] b.ne #0x10840
  [0x107E0] adrp x16, #0x10000
  [0x107E4] add x16, x16, #0
  [0x107E8] ldr w9, [x16]
  [0x107EC] add x16, x13, x15
  [0x107F0] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x107F4] add x16, x5, x15
  [0x107F8] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x107FC] mov x7, x7
  [0x10800] adrp x16, #0x10000
  [0x10804] add x16, x16, #0
  [0x10808] ldr w9, [x16]
  [0x1080C] mov x9, x9
  [0x10810] mov x7, x7
  [0x10814] add x9, x9, x15
  [0x10818] stp x3, x5, [sp, #-0x10]!
  [0x1081C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10820] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10824] blr x9 ;; misaligned with debug data
  [0x10828] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1082C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10830] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10834] mov x0, x0
  [0x10838] mov x0, x0
  [0x1083C] b #0x11a5c
  [0x10840] adrp x8, #0x10000
  [0x10844] add x8, x8, #0
  [0x10848] cmp x9, x8
  [0x1084C] b.ne #0x109e0
  [0x10850] add x16, x5, x15
  [0x10854] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x10858] mov x9, x9
  [0x1085C] adrp x8, #0x10000
  [0x10860] add x8, x8, #0
  [0x10864] cmp x9, x8
  [0x10868] b.ne #0x108f4
  [0x1086C] add x16, x13, x15
  [0x10870] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x10874] add x16, x9, x15
  [0x10878] ldrsw x9, [x16, #0x24] ;; misaligned with debug data
  [0x1087C] add x16, x5, x15
  [0x10880] ldr x8, [x16, #0x18] ;; misaligned with debug data
  [0x10884] mov x0, x14
  [0x10888] sub x0, x0, x15 ;; misaligned with debug data
  [0x1088C] cmp x9, x8
  [0x10890] b.ne #0x108a0
  [0x10894] add x0, x14, #8
  [0x10898] sub x0, x0, x15 ;; misaligned with debug data
  [0x1089C] mov x0, x0
  [0x108A0] mov x0, x0
  [0x108A4] mov x9, x14
  [0x108A8] sub x9, x9, x15 ;; misaligned with debug data
  [0x108AC] cmp x0, x9
  [0x108B0] b.eq #0x108ec
  [0x108B4] adrp x16, #0x16000
  [0x108B8] ldr s23, [x16, #0xed0]
  [0x108BC] add x16, x13, x15
  [0x108C0] ldr w9, [x16, #0x8c] ;; misaligned with debug data
  [0x108C4] add x16, x9, x15
  [0x108C8] ldr s22, [x16, #0x28] ;; misaligned with debug data
  [0x108CC] mov x0, x14
  [0x108D0] sub x0, x0, x15 ;; misaligned with debug data
  [0x108D4] fcmp s23, s22
  [0x108D8] b.ge #0x108e8
  [0x108DC] add x0, x14, #8
  [0x108E0] sub x0, x0, x15 ;; misaligned with debug data
  [0x108E4] mov x0, x0
  [0x108E8] mov x0, x0
  [0x108EC] mov x0, x0
  [0x108F0] b #0x109d8
  [0x108F4] adrp x8, #0x10000
  [0x108F8] add x8, x8, #0
  [0x108FC] cmp x9, x8
  [0x10900] b.ne #0x10984
  [0x10904] add x16, x13, x15
  [0x10908] ldr w7, [x16, #0x8c] ;; misaligned with debug data
  [0x1090C] add x16, x5, x15
  [0x10910] ldr x6, [x16, #0x18] ;; misaligned with debug data
  [0x10914] mov x6, x6
  [0x10918] adrp x16, #0x16000
  [0x1091C] ldr s23, [x16, #0xed4]
  [0x10920] mov v23.16b, v23.16b
  [0x10924] mov x1, x14
  [0x10928] sub x1, x1, x15 ;; misaligned with debug data
  [0x1092C] mov x1, x1
  [0x10930] add x16, x7, x15
  [0x10934] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10938] add x16, x9, x15
  [0x1093C] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10940] mov x9, x9
  [0x10944] mov x7, x7
  [0x10948] mov x6, x6
  [0x1094C] fmov w2, s23
  [0x10950] sxtw x2, w2
  [0x10954] mov x1, x1
  [0x10958] add x9, x9, x15
  [0x1095C] stp x3, x5, [sp, #-0x10]!
  [0x10960] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10964] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10968] blr x9 ;; misaligned with debug data
  [0x1096C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10970] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10974] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10978] mov x0, x0
  [0x1097C] mov x0, x0
  [0x10980] b #0x109d8
  [0x10984] adrp x8, #0x10000
  [0x10988] add x8, x8, #0
  [0x1098C] cmp x9, x8
  [0x10990] b.ne #0x109d0
  [0x10994] adrp x16, #0x10000
  [0x10998] add x16, x16, #0
  [0x1099C] ldr w9, [x16]
  [0x109A0] mov x9, x9
  [0x109A4] add x9, x9, x15
  [0x109A8] stp x3, x5, [sp, #-0x10]!
  [0x109AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x109B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109B4] blr x9 ;; misaligned with debug data
  [0x109B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x109C4] mov x0, x0
  [0x109C8] mov x0, x0
  [0x109CC] b #0x109d8
  [0x109D0] mov x0, x14
  [0x109D4] sub x0, x0, x15 ;; misaligned with debug data
  [0x109D8] mov x0, x0
  [0x109DC] b #0x11a5c
  [0x109E0] adrp x8, #0x10000
  [0x109E4] add x8, x8, #0
  [0x109E8] cmp x9, x8
  [0x109EC] b.ne #0x10cbc
  [0x109F0] add x16, x5, x15
  [0x109F4] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x109F8] mov x9, x9
  [0x109FC] adrp x8, #0x10000
  [0x10A00] add x8, x8, #0
  [0x10A04] cmp x9, x8
  [0x10A08] b.ne #0x10ab8
  [0x10A0C] add x16, x13, x15
  [0x10A10] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10A14] add x16, x9, x15
  [0x10A18] ldur q23, [x16, #0xc] ;; misaligned with debug data
  [0x10A1C] mov v23.16b, v23.16b
  [0x10A20] add x16, x13, x15
  [0x10A24] add x16, x16, #0x1bc ;; misaligned with debug data
  [0x10A28] str q23, [x16] ;; misaligned with debug data
  [0x10A2C] add x16, x13, x15
  [0x10A30] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10A34] mov x9, x9
  [0x10A38] movz x8, #0
  [0x10A3C] movk x8, #0x2, lsl #16
  [0x10A40] orr x9, x9, x8
  [0x10A44] add x16, x13, x15
  [0x10A48] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10A4C] adrp x16, #0x10000
  [0x10A50] add x16, x16, #0
  [0x10A54] ldr w9, [x16]
  [0x10A58] add x16, x5, x15
  [0x10A5C] ldr x7, [x16, #0x18] ;; misaligned with debug data
  [0x10A60] mov x7, x7
  [0x10A64] movz x6, #0xc
  [0x10A68] add x16, x13, x15
  [0x10A6C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10A70] add x6, x6, x8
  [0x10A74] mov x6, x6
  [0x10A78] movz x2, #0x30
  [0x10A7C] mov x9, x9
  [0x10A80] mov x7, x7
  [0x10A84] mov x6, x6
  [0x10A88] mov x2, x2
  [0x10A8C] add x9, x9, x15
  [0x10A90] stp x3, x5, [sp, #-0x10]!
  [0x10A94] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A98] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A9C] blr x9 ;; misaligned with debug data
  [0x10AA0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10AA4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10AA8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AAC] mov x0, x0
  [0x10AB0] mov x0, x0
  [0x10AB4] b #0x10cb4
  [0x10AB8] adrp x8, #0x10000
  [0x10ABC] add x8, x8, #0
  [0x10AC0] cmp x9, x8
  [0x10AC4] b.ne #0x10c64
  [0x10AC8] add x16, x13, x15
  [0x10ACC] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10AD0] movz x8, #0
  [0x10AD4] movk x8, #0x2, lsl #16
  [0x10AD8] mov x8, x8
  [0x10ADC] mvn x8, x8
  [0x10AE0] mov x9, x9
  [0x10AE4] and x9, x9, x8
  [0x10AE8] add x16, x13, x15
  [0x10AEC] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10AF0] add x16, x5, x15
  [0x10AF4] ldr x3, [x16, #0x18] ;; misaligned with debug data
  [0x10AF8] mov x3, x3
  [0x10AFC] add x16, x13, x15
  [0x10B00] ldr w7, [x16, #0x6c] ;; misaligned with debug data
  [0x10B04] mov x6, x3
  [0x10B08] movz x9, #0
  [0x10B0C] add x6, x6, x9
  [0x10B10] mov x6, x6
  [0x10B14] add x16, x7, x15
  [0x10B18] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10B1C] add x16, x9, x15
  [0x10B20] ldr w9, [x16, #0x88] ;; misaligned with debug data
  [0x10B24] mov x9, x9
  [0x10B28] mov x7, x7
  [0x10B2C] mov x6, x6
  [0x10B30] add x9, x9, x15
  [0x10B34] stp x3, x5, [sp, #-0x10]!
  [0x10B38] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B3C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B40] blr x9 ;; misaligned with debug data
  [0x10B44] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B48] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10B4C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10B50] mov x5, x5
  [0x10B54] adrp x16, #0x10000
  [0x10B58] add x16, x16, #0
  [0x10B5C] ldr w9, [x16]
  [0x10B60] movz x7, #0x1c
  [0x10B64] add x16, x13, x15
  [0x10B68] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10B6C] add x7, x7, x8
  [0x10B70] mov x3, x3
  [0x10B74] movz x8, #0x10
  [0x10B78] add x3, x3, x8
  [0x10B7C] mov x3, x3
  [0x10B80] mov x9, x9
  [0x10B84] mov x7, x7
  [0x10B88] mov x6, x3
  [0x10B8C] add x9, x9, x15
  [0x10B90] stp x3, x5, [sp, #-0x10]!
  [0x10B94] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B98] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B9C] blr x9 ;; misaligned with debug data
  [0x10BA0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10BA4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10BA8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10BAC] mov x0, x0
  [0x10BB0] add x16, x13, x15
  [0x10BB4] ldr w7, [x16, #0x6c] ;; misaligned with debug data
  [0x10BB8] add x16, x7, x15
  [0x10BBC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10BC0] add x16, x9, x15
  [0x10BC4] ldr w9, [x16, #0x64] ;; misaligned with debug data
  [0x10BC8] mov x9, x9
  [0x10BCC] mov x7, x7
  [0x10BD0] add x9, x9, x15
  [0x10BD4] stp x3, x5, [sp, #-0x10]!
  [0x10BD8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10BDC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10BE0] blr x9 ;; misaligned with debug data
  [0x10BE4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10BE8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10BEC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10BF0] mov x0, x0
  [0x10BF4] add x16, x13, x15
  [0x10BF8] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10BFC] add x16, x9, x15
  [0x10C00] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10C04] ldr x9, [x16] ;; misaligned with debug data
  [0x10C08] mov x9, x9
  [0x10C0C] movz x8, #0x7
  [0x10C10] orr x9, x9, x8
  [0x10C14] add x16, x13, x15
  [0x10C18] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10C1C] add x16, x8, x15
  [0x10C20] add x16, x16, #0x10c ;; misaligned with debug data
  [0x10C24] str x9, [x16] ;; misaligned with debug data
  [0x10C28] adrp x16, #0x10000
  [0x10C2C] add x16, x16, #0
  [0x10C30] ldr w9, [x16]
  [0x10C34] add x16, x9, x15
  [0x10C38] add x16, x16, #0x30c ;; misaligned with debug data
  [0x10C3C] ldr x0, [x16] ;; misaligned with debug data
  [0x10C40] mov x0, x0
  [0x10C44] mov x9, x0
  [0x10C48] add x16, x13, x15
  [0x10C4C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10C50] add x16, x8, x15
  [0x10C54] add x16, x16, #0x504 ;; misaligned with debug data
  [0x10C58] str x9, [x16] ;; misaligned with debug data
  [0x10C5C] mov x0, x0
  [0x10C60] b #0x10cb4
  [0x10C64] adrp x8, #0x10000
  [0x10C68] add x8, x8, #0
  [0x10C6C] cmp x9, x8
  [0x10C70] b.ne #0x10cac
  [0x10C74] add x16, x13, x15
  [0x10C78] ldr w0, [x16, #0xa0] ;; misaligned with debug data
  [0x10C7C] movz x9, #0
  [0x10C80] movk x9, #0x2, lsl #16
  [0x10C84] mov x9, x9
  [0x10C88] mvn x9, x9
  [0x10C8C] mov x0, x0
  [0x10C90] and x0, x0, x9
  [0x10C94] mov x0, x0
  [0x10C98] mov x9, x0
  [0x10C9C] add x16, x13, x15
  [0x10CA0] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10CA4] mov x0, x0
  [0x10CA8] b #0x10cb4
  [0x10CAC] mov x0, x14
  [0x10CB0] sub x0, x0, x15 ;; misaligned with debug data
  [0x10CB4] mov x0, x0
  [0x10CB8] b #0x11a5c
  [0x10CBC] adrp x8, #0x10000
  [0x10CC0] add x8, x8, #0
  [0x10CC4] cmp x9, x8
  [0x10CC8] b.ne #0x10d18
  [0x10CCC] adrp x16, #0x10000
  [0x10CD0] add x16, x16, #0
  [0x10CD4] ldr w9, [x16]
  [0x10CD8] add x16, x5, x15
  [0x10CDC] ldr x7, [x16, #0x10] ;; misaligned with debug data
  [0x10CE0] mov x7, x7
  [0x10CE4] mov x9, x9
  [0x10CE8] mov x7, x7
  [0x10CEC] add x9, x9, x15
  [0x10CF0] stp x3, x5, [sp, #-0x10]!
  [0x10CF4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CF8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10CFC] blr x9 ;; misaligned with debug data
  [0x10D00] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D04] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D08] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D0C] mov x3, x3
  [0x10D10] mov x0, x3
  [0x10D14] b #0x11a5c
  [0x10D18] adrp x8, #0x10000
  [0x10D1C] add x8, x8, #0
  [0x10D20] cmp x9, x8
  [0x10D24] b.ne #0x10e68
  [0x10D28] add x16, x13, x15
  [0x10D2C] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10D30] add x16, x9, x15
  [0x10D34] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x10D38] add x16, x5, x15
  [0x10D3C] ldr x6, [x16, #0x10] ;; misaligned with debug data
  [0x10D40] mov x6, x6
  [0x10D44] add x16, x5, x15
  [0x10D48] ldr x2, [x16, #0x18] ;; misaligned with debug data
  [0x10D4C] mov x2, x2
  [0x10D50] movz x1, #0xffff
  [0x10D54] movk x1, #0xffff, lsl #16
  [0x10D58] movk x1, #0xffff, lsl #32
  [0x10D5C] movk x1, #0xffff, lsl #48
  [0x10D60] add x16, x7, x15
  [0x10D64] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10D68] add x16, x9, x15
  [0x10D6C] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10D70] mov x9, x9
  [0x10D74] mov x7, x7
  [0x10D78] mov x6, x6
  [0x10D7C] mov x2, x2
  [0x10D80] mov x1, x1
  [0x10D84] add x9, x9, x15
  [0x10D88] stp x3, x5, [sp, #-0x10]!
  [0x10D8C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D90] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D94] blr x9 ;; misaligned with debug data
  [0x10D98] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D9C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10DA0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10DA4] mov x0, x0
  [0x10DA8] add x16, x13, x15
  [0x10DAC] ldr w9, [x16, #0xcc] ;; misaligned with debug data
  [0x10DB0] mov x8, x14
  [0x10DB4] sub x8, x8, x15 ;; misaligned with debug data
  [0x10DB8] cmp x9, x8
  [0x10DBC] b.eq #0x10e58
  [0x10DC0] add x16, x13, x15
  [0x10DC4] ldr w9, [x16, #0xcc] ;; misaligned with debug data
  [0x10DC8] add x16, x9, x15
  [0x10DCC] ldr w9, [x16] ;; misaligned with debug data
  [0x10DD0] add x16, x9, x15
  [0x10DD4] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10DD8] add x16, x9, x15
  [0x10DDC] ldr w7, [x16, #0x24] ;; misaligned with debug data
  [0x10DE0] add x16, x5, x15
  [0x10DE4] ldr x6, [x16, #0x10] ;; misaligned with debug data
  [0x10DE8] mov x6, x6
  [0x10DEC] add x16, x5, x15
  [0x10DF0] ldr x2, [x16, #0x18] ;; misaligned with debug data
  [0x10DF4] mov x2, x2
  [0x10DF8] movz x1, #0xffff
  [0x10DFC] movk x1, #0xffff, lsl #16
  [0x10E00] movk x1, #0xffff, lsl #32
  [0x10E04] movk x1, #0xffff, lsl #48
  [0x10E08] add x16, x7, x15
  [0x10E0C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10E10] add x16, x9, x15
  [0x10E14] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10E18] mov x9, x9
  [0x10E1C] mov x7, x7
  [0x10E20] mov x6, x6
  [0x10E24] mov x2, x2
  [0x10E28] mov x1, x1
  [0x10E2C] add x9, x9, x15
  [0x10E30] stp x3, x5, [sp, #-0x10]!
  [0x10E34] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E38] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E3C] blr x9 ;; misaligned with debug data
  [0x10E40] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10E44] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10E48] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10E4C] mov x0, x0
  [0x10E50] mov x0, x0
  [0x10E54] b #0x10e60
  [0x10E58] mov x0, x14
  [0x10E5C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10E60] mov x0, x0
  [0x10E64] b #0x11a5c
  [0x10E68] adrp x8, #0x10000
  [0x10E6C] add x8, x8, #0
  [0x10E70] cmp x9, x8
  [0x10E74] b.ne #0x10f94
  [0x10E78] add x16, x5, x15
  [0x10E7C] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x10E80] mov x9, x9
  [0x10E84] add x16, x13, x15
  [0x10E88] ldr w8, [x16, #0xb8] ;; misaligned with debug data
  [0x10E8C] add x16, x8, x15
  [0x10E90] str w9, [x16, #0x74] ;; misaligned with debug data
  [0x10E94] add x16, x5, x15
  [0x10E98] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10E9C] mov x8, x14
  [0x10EA0] sub x8, x8, x15 ;; misaligned with debug data
  [0x10EA4] cmp x9, x8
  [0x10EA8] b.eq #0x10f58
  [0x10EAC] add x16, x13, x15
  [0x10EB0] ldr w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10EB4] mov x9, x9
  [0x10EB8] movz x8, #0
  [0x10EBC] movk x8, #0x4, lsl #16
  [0x10EC0] orr x9, x9, x8
  [0x10EC4] add x16, x13, x15
  [0x10EC8] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10ECC] add x16, x5, x15
  [0x10ED0] ldr x9, [x16, #0x18] ;; misaligned with debug data
  [0x10ED4] mov x9, x9
  [0x10ED8] add x16, x9, x15
  [0x10EDC] ldr q23, [x16] ;; misaligned with debug data
  [0x10EE0] mov v23.16b, v23.16b
  [0x10EE4] add x16, x13, x15
  [0x10EE8] add x16, x16, #0x21c ;; misaligned with debug data
  [0x10EEC] str q23, [x16] ;; misaligned with debug data
  [0x10EF0] add x16, x13, x15
  [0x10EF4] ldr w7, [x16, #0xb8] ;; misaligned with debug data
  [0x10EF8] movz x6, #0x21c
  [0x10EFC] add x6, x6, x13
  [0x10F00] adrp x2, #0x10000
  [0x10F04] add x2, x2, #0
  [0x10F08] add x16, x7, x15
  [0x10F0C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10F10] add x16, x9, x15
  [0x10F14] ldr w9, [x16, #0x3c] ;; misaligned with debug data
  [0x10F18] mov x9, x9
  [0x10F1C] mov x7, x7
  [0x10F20] mov x6, x6
  [0x10F24] mov x2, x2
  [0x10F28] mov x1, x12
  [0x10F2C] add x9, x9, x15
  [0x10F30] stp x3, x5, [sp, #-0x10]!
  [0x10F34] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F38] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F3C] blr x9 ;; misaligned with debug data
  [0x10F40] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10F44] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10F48] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10F4C] mov x3, x3
  [0x10F50] mov x0, x3
  [0x10F54] b #0x10f8c
  [0x10F58] add x16, x13, x15
  [0x10F5C] ldr w0, [x16, #0xa0] ;; misaligned with debug data
  [0x10F60] movz x9, #0
  [0x10F64] movk x9, #0x4, lsl #16
  [0x10F68] mov x9, x9
  [0x10F6C] mvn x9, x9
  [0x10F70] mov x0, x0
  [0x10F74] and x0, x0, x9
  [0x10F78] mov x0, x0
  [0x10F7C] mov x9, x0
  [0x10F80] add x16, x13, x15
  [0x10F84] str w9, [x16, #0xa0] ;; misaligned with debug data
  [0x10F88] mov x0, x0
  [0x10F8C] mov x0, x0
  [0x10F90] b #0x11a5c
  [0x10F94] adrp x8, #0x10000
  [0x10F98] add x8, x8, #0
  [0x10F9C] cmp x9, x8
  [0x10FA0] b.ne #0x11234
  [0x10FA4] add x16, x5, x15
  [0x10FA8] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x10FAC] mov x9, x9
  [0x10FB0] mov x8, x14
  [0x10FB4] sub x8, x8, x15 ;; misaligned with debug data
  [0x10FB8] cmp x9, x8
  [0x10FBC] b.eq #0x10ff0
  [0x10FC0] add x16, x13, x15
  [0x10FC4] ldr w9, [x16, #0xcc] ;; misaligned with debug data
  [0x10FC8] mov x8, x14
  [0x10FCC] sub x8, x8, x15 ;; misaligned with debug data
  [0x10FD0] mov x1, x14
  [0x10FD4] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FD8] cmp x9, x8
  [0x10FDC] b.ne #0x10fec
  [0x10FE0] add x1, x14, #8
  [0x10FE4] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FE8] mov x1, x1
  [0x10FEC] mov x9, x1
  [0x10FF0] mov x8, x14
  [0x10FF4] sub x8, x8, x15 ;; misaligned with debug data
  [0x10FF8] cmp x9, x8
  [0x10FFC] b.eq #0x11158
  [0x11000] adrp x16, #0x11000
  [0x11004] add x16, x16, #0
  [0x11008] ldr w7, [x16]
  [0x1100C] adrp x16, #0x11000
  [0x11010] add x16, x16, #0
  [0x11014] ldr w6, [x16]
  [0x11018] movz x2, #0x4000
  [0x1101C] add x16, x7, x15
  [0x11020] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11024] add x16, x9, x15
  [0x11028] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x1102C] mov x9, x9
  [0x11030] mov x7, x7
  [0x11034] mov x6, x6
  [0x11038] mov x2, x2
  [0x1103C] add x9, x9, x15
  [0x11040] stp x3, x5, [sp, #-0x10]!
  [0x11044] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11048] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1104C] blr x9 ;; misaligned with debug data
  [0x11050] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11054] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11058] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1105C] mov x0, x0
  [0x11060] mov x3, x0
  [0x11064] mov x9, x14
  [0x11068] sub x9, x9, x15 ;; misaligned with debug data
  [0x1106C] cmp x3, x9
  [0x11070] b.eq #0x11138
  [0x11074] adrp x16, #0x11000
  [0x11078] add x16, x16, #0
  [0x1107C] ldr w9, [x16]
  [0x11080] add x16, x9, x15
  [0x11084] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x11088] mov x9, x9
  [0x1108C] mov x7, x3
  [0x11090] adrp x2, #0x11000
  [0x11094] add x2, x2, #0
  [0x11098] movz x1, #0x4000
  [0x1109C] movk x1, #0x7000, lsl #16
  [0x110A0] mov x1, x1
  [0x110A4] mov x9, x9
  [0x110A8] mov x7, x7
  [0x110AC] mov x6, x13
  [0x110B0] mov x2, x2
  [0x110B4] mov x1, x1
  [0x110B8] add x9, x9, x15
  [0x110BC] stp x3, x5, [sp, #-0x10]!
  [0x110C0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x110C4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x110C8] blr x9 ;; misaligned with debug data
  [0x110CC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x110D0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x110D4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x110D8] mov x0, x0
  [0x110DC] adrp x16, #0x11000
  [0x110E0] add x16, x16, #0
  [0x110E4] ldr w9, [x16]
  [0x110E8] mov x9, x9
  [0x110EC] adrp x16, #0x11000
  [0x110F0] add x16, x16, #0
  [0x110F4] ldr w6, [x16]
  [0x110F8] mov x9, x9
  [0x110FC] mov x7, x3
  [0x11100] mov x6, x6
  [0x11104] add x9, x9, x15
  [0x11108] stp x3, x5, [sp, #-0x10]!
  [0x1110C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11110] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11114] blr x9 ;; misaligned with debug data
  [0x11118] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1111C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11120] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11124] mov x0, x0
  [0x11128] add x16, x3, x15
  [0x1112C] ldr w0, [x16, #0x14] ;; misaligned with debug data
  [0x11130] mov x0, x0
  [0x11134] b #0x11140
  [0x11138] mov x0, x14
  [0x1113C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11140] mov x0, x0
  [0x11144] mov x9, x0
  [0x11148] add x16, x13, x15
  [0x1114C] str w9, [x16, #0xcc] ;; misaligned with debug data
  [0x11150] mov x0, x0
  [0x11154] b #0x1122c
  [0x11158] add x16, x5, x15
  [0x1115C] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x11160] mov x8, x14
  [0x11164] sub x8, x8, x15 ;; misaligned with debug data
  [0x11168] mov x1, x14
  [0x1116C] sub x1, x1, x15 ;; misaligned with debug data
  [0x11170] cmp x9, x8
  [0x11174] b.ne #0x11184
  [0x11178] add x1, x14, #8
  [0x1117C] sub x1, x1, x15 ;; misaligned with debug data
  [0x11180] mov x1, x1
  [0x11184] mov x9, x1
  [0x11188] mov x8, x14
  [0x1118C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11190] cmp x9, x8
  [0x11194] b.eq #0x111a4
  [0x11198] add x16, x13, x15
  [0x1119C] ldr w9, [x16, #0xcc] ;; misaligned with debug data
  [0x111A0] mov x9, x9
  [0x111A4] mov x8, x14
  [0x111A8] sub x8, x8, x15 ;; misaligned with debug data
  [0x111AC] cmp x9, x8
  [0x111B0] b.eq #0x11224
  [0x111B4] add x16, x13, x15
  [0x111B8] ldr w9, [x16, #0xcc] ;; misaligned with debug data
  [0x111BC] add x16, x9, x15
  [0x111C0] ldr w7, [x16] ;; misaligned with debug data
  [0x111C4] add x16, x7, x15
  [0x111C8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x111CC] add x16, x9, x15
  [0x111D0] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x111D4] mov x9, x9
  [0x111D8] mov x7, x7
  [0x111DC] add x9, x9, x15
  [0x111E0] stp x3, x5, [sp, #-0x10]!
  [0x111E4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x111E8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x111EC] blr x9 ;; misaligned with debug data
  [0x111F0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x111F4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x111F8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x111FC] mov x3, x3
  [0x11200] mov x9, x14
  [0x11204] sub x9, x9, x15 ;; misaligned with debug data
  [0x11208] mov x9, x9
  [0x1120C] add x16, x13, x15
  [0x11210] str w9, [x16, #0xcc] ;; misaligned with debug data
  [0x11214] mov x0, x14
  [0x11218] sub x0, x0, x15 ;; misaligned with debug data
  [0x1121C] mov x0, x0
  [0x11220] b #0x1122c
  [0x11224] mov x0, x14
  [0x11228] sub x0, x0, x15 ;; misaligned with debug data
  [0x1122C] mov x0, x0
  [0x11230] b #0x11a5c
  [0x11234] adrp x8, #0x11000
  [0x11238] add x8, x8, #0
  [0x1123C] cmp x9, x8
  [0x11240] b.ne #0x113e0
  [0x11244] add x16, x5, x15
  [0x11248] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x1124C] mov x8, x14
  [0x11250] sub x8, x8, x15 ;; misaligned with debug data
  [0x11254] cmp x9, x8
  [0x11258] b.eq #0x11290
  [0x1125C] add x16, x13, x15
  [0x11260] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x11264] add x16, x9, x15
  [0x11268] ldrh w9, [x16] ;; misaligned with debug data
  [0x1126C] mov x9, x9
  [0x11270] movz x8, #0x8
  [0x11274] orr x9, x9, x8
  [0x11278] add x16, x13, x15
  [0x1127C] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x11280] add x16, x8, x15
  [0x11284] strh w9, [x16] ;; misaligned with debug data
  [0x11288] mov x9, x9
  [0x1128C] b #0x112c8
  [0x11290] add x16, x13, x15
  [0x11294] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x11298] add x16, x9, x15
  [0x1129C] ldrh w9, [x16] ;; misaligned with debug data
  [0x112A0] movz x8, #0x8
  [0x112A4] mov x8, x8
  [0x112A8] mvn x8, x8
  [0x112AC] mov x9, x9
  [0x112B0] and x9, x9, x8
  [0x112B4] add x16, x13, x15
  [0x112B8] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x112BC] add x16, x8, x15
  [0x112C0] strh w9, [x16] ;; misaligned with debug data
  [0x112C4] mov x9, x9
  [0x112C8] mov x9, sp
  [0x112CC] sub x9, x9, x15
  [0x112D0] mov x9, x9
  [0x112D4] add x16, x9, x15
  [0x112D8] str w12, [x16, #4] ;; misaligned with debug data
  [0x112DC] add x16, x9, x15
  [0x112E0] str w6, [x16, #8] ;; misaligned with debug data
  [0x112E4] add x16, x9, x15
  [0x112E8] str w2, [x16, #0xc] ;; misaligned with debug data
  [0x112EC] add x16, x5, x15
  [0x112F0] ldr x8, [x16, #0x10] ;; misaligned with debug data
  [0x112F4] add x16, x9, x15
  [0x112F8] str x8, [x16, #0x10] ;; misaligned with debug data
  [0x112FC] add x16, x5, x15
  [0x11300] ldr x8, [x16, #0x18] ;; misaligned with debug data
  [0x11304] add x16, x9, x15
  [0x11308] str x8, [x16, #0x18] ;; misaligned with debug data
  [0x1130C] add x16, x5, x15
  [0x11310] ldr x8, [x16, #0x20] ;; misaligned with debug data
  [0x11314] add x16, x9, x15
  [0x11318] str x8, [x16, #0x20] ;; misaligned with debug data
  [0x1131C] add x16, x5, x15
  [0x11320] ldr x8, [x16, #0x28] ;; misaligned with debug data
  [0x11324] add x16, x9, x15
  [0x11328] str x8, [x16, #0x28] ;; misaligned with debug data
  [0x1132C] add x16, x5, x15
  [0x11330] ldr x8, [x16, #0x30] ;; misaligned with debug data
  [0x11334] add x16, x9, x15
  [0x11338] str x8, [x16, #0x30] ;; misaligned with debug data
  [0x1133C] add x16, x5, x15
  [0x11340] ldr x8, [x16, #0x38] ;; misaligned with debug data
  [0x11344] add x16, x9, x15
  [0x11348] str x8, [x16, #0x38] ;; misaligned with debug data
  [0x1134C] add x16, x5, x15
  [0x11350] ldr x8, [x16, #0x40] ;; misaligned with debug data
  [0x11354] add x16, x9, x15
  [0x11358] str x8, [x16, #0x40] ;; misaligned with debug data
  [0x1135C] adrp x16, #0x11000
  [0x11360] add x16, x16, #0
  [0x11364] ldr w8, [x16]
  [0x11368] add x16, x13, x15
  [0x1136C] ldr w1, [x16, #0xcc] ;; misaligned with debug data
  [0x11370] mov x1, x1
  [0x11374] mov x2, x14
  [0x11378] sub x2, x2, x15 ;; misaligned with debug data
  [0x1137C] cmp x1, x2
  [0x11380] b.eq #0x1139c
  [0x11384] add x16, x1, x15
  [0x11388] ldr w1, [x16] ;; misaligned with debug data
  [0x1138C] add x16, x1, x15
  [0x11390] ldr w7, [x16, #0x18] ;; misaligned with debug data
  [0x11394] mov x7, x7
  [0x11398] b #0x113a4
  [0x1139C] mov x7, x14
  [0x113A0] sub x7, x7, x15 ;; misaligned with debug data
  [0x113A4] mov x7, x7
  [0x113A8] mov x8, x8
  [0x113AC] mov x7, x7
  [0x113B0] mov x6, x9
  [0x113B4] add x8, x8, x15
  [0x113B8] stp x3, x5, [sp, #-0x10]!
  [0x113BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x113C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x113C4] blr x8 ;; misaligned with debug data
  [0x113C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x113CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x113D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x113D4] mov x0, x0
  [0x113D8] mov x0, x0
  [0x113DC] b #0x11a5c
  [0x113E0] adrp x8, #0x11000
  [0x113E4] add x8, x8, #0
  [0x113E8] cmp x9, x8
  [0x113EC] b.ne #0x1148c
  [0x113F0] add x16, x5, x15
  [0x113F4] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x113F8] mov x8, x14
  [0x113FC] sub x8, x8, x15 ;; misaligned with debug data
  [0x11400] cmp x9, x8
  [0x11404] b.eq #0x1144c
  [0x11408] add x16, x13, x15
  [0x1140C] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x11410] add x16, x9, x15
  [0x11414] ldr w9, [x16, #0x5c] ;; misaligned with debug data
  [0x11418] mov x9, x9
  [0x1141C] add x16, x9, x15
  [0x11420] ldrsw x8, [x16, #0x18] ;; misaligned with debug data
  [0x11424] movz x1, #0x20
  [0x11428] mov x1, x1
  [0x1142C] mvn x1, x1
  [0x11430] mov x8, x8
  [0x11434] and x8, x8, x1
  [0x11438] add x16, x9, x15
  [0x1143C] str w8, [x16, #0x18] ;; misaligned with debug data
  [0x11440] movz x0, #0
  [0x11444] mov x0, x0
  [0x11448] b #0x11484
  [0x1144C] add x16, x13, x15
  [0x11450] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x11454] add x16, x9, x15
  [0x11458] ldr w9, [x16, #0x5c] ;; misaligned with debug data
  [0x1145C] mov x9, x9
  [0x11460] add x16, x9, x15
  [0x11464] ldrsw x8, [x16, #0x18] ;; misaligned with debug data
  [0x11468] mov x8, x8
  [0x1146C] movz x1, #0x20
  [0x11470] orr x8, x8, x1
  [0x11474] add x16, x9, x15
  [0x11478] str w8, [x16, #0x18] ;; misaligned with debug data
  [0x1147C] movz x0, #0
  [0x11480] mov x0, x0
  [0x11484] mov x0, x0
  [0x11488] b #0x11a5c
  [0x1148C] adrp x8, #0x11000
  [0x11490] add x8, x8, #0
  [0x11494] cmp x9, x8
  [0x11498] b.ne #0x115c0
  [0x1149C] adrp x16, #0x11000
  [0x114A0] add x16, x16, #0
  [0x114A4] ldr w9, [x16]
  [0x114A8] movz x7, #0x1ec
  [0x114AC] add x16, x13, x15
  [0x114B0] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x114B4] add x7, x7, x8
  [0x114B8] movz x6, #0x1ec
  [0x114BC] add x16, x13, x15
  [0x114C0] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x114C4] add x6, x6, x8
  [0x114C8] add x16, x5, x15
  [0x114CC] ldr x2, [x16, #0x10] ;; misaligned with debug data
  [0x114D0] mov x2, x2
  [0x114D4] mov x9, x9
  [0x114D8] mov x7, x7
  [0x114DC] mov x6, x6
  [0x114E0] mov x2, x2
  [0x114E4] add x9, x9, x15
  [0x114E8] stp x3, x5, [sp, #-0x10]!
  [0x114EC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x114F0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x114F4] blr x9 ;; misaligned with debug data
  [0x114F8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x114FC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11500] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11504] mov x0, x0
  [0x11508] add x16, x13, x15
  [0x1150C] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x11510] add x16, x9, x15
  [0x11514] ldr w9, [x16, #0x298] ;; misaligned with debug data
  [0x11518] add x16, x9, x15
  [0x1151C] ldrsw x9, [x16, #0x20] ;; misaligned with debug data
  [0x11520] mov x9, x9
  [0x11524] lsl x9, x9, #2
  [0x11528] mov x9, x9
  [0x1152C] movz x8, #0x4
  [0x11530] adrp x16, #0x11000
  [0x11534] add x16, x16, #0
  [0x11538] ldr w1, [x16]
  [0x1153C] add x8, x8, x1
  [0x11540] add x9, x9, x8
  [0x11544] add x16, x9, x15
  [0x11548] ldr w9, [x16] ;; misaligned with debug data
  [0x1154C] add x16, x9, x15
  [0x11550] ldr s23, [x16, #0x48] ;; misaligned with debug data
  [0x11554] adrp x16, #0x16000
  [0x11558] ldr s22, [x16, #0xed8]
  [0x1155C] fcmp s23, s22
  [0x11560] b.ne #0x115b0
  [0x11564] add x16, x13, x15
  [0x11568] ldr w7, [x16, #0x6c] ;; misaligned with debug data
  [0x1156C] add x16, x7, x15
  [0x11570] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11574] add x16, x9, x15
  [0x11578] ldr w9, [x16, #0x64] ;; misaligned with debug data
  [0x1157C] mov x9, x9
  [0x11580] mov x7, x7
  [0x11584] add x9, x9, x15
  [0x11588] stp x3, x5, [sp, #-0x10]!
  [0x1158C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11590] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11594] blr x9 ;; misaligned with debug data
  [0x11598] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1159C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x115A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x115A4] mov x0, x0
  [0x115A8] mov x0, x0
  [0x115AC] b #0x115b8
  [0x115B0] mov x0, x14
  [0x115B4] sub x0, x0, x15 ;; misaligned with debug data
  [0x115B8] mov x0, x0
  [0x115BC] b #0x11a5c
  [0x115C0] adrp x8, #0x11000
  [0x115C4] add x8, x8, #0
  [0x115C8] cmp x9, x8
  [0x115CC] b.ne #0x11658
  [0x115D0] mov x6, sp
  [0x115D4] sub x6, x6, x15
  [0x115D8] mov x6, x6
  [0x115DC] add x16, x6, x15
  [0x115E0] str w13, [x16, #4] ;; misaligned with debug data
  [0x115E4] movz x9, #0x1
  [0x115E8] add x16, x6, x15
  [0x115EC] str w9, [x16, #8] ;; misaligned with debug data
  [0x115F0] adrp x9, #0x11000
  [0x115F4] add x9, x9, #0
  [0x115F8] add x16, x6, x15
  [0x115FC] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x11600] add x16, x5, x15
  [0x11604] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x11608] mov x9, x9
  [0x1160C] add x16, x6, x15
  [0x11610] str x9, [x16, #0x10] ;; misaligned with debug data
  [0x11614] adrp x16, #0x11000
  [0x11618] add x16, x16, #0
  [0x1161C] ldr w9, [x16]
  [0x11620] mov x9, x9
  [0x11624] mov x7, x12
  [0x11628] mov x6, x6
  [0x1162C] add x9, x9, x15
  [0x11630] stp x3, x5, [sp, #-0x10]!
  [0x11634] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11638] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1163C] blr x9 ;; misaligned with debug data
  [0x11640] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11644] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11648] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1164C] mov x0, x0
  [0x11650] mov x0, x0
  [0x11654] b #0x11a5c
  [0x11658] adrp x8, #0x11000
  [0x1165C] add x8, x8, #0
  [0x11660] cmp x9, x8
  [0x11664] b.ne #0x1168c
  [0x11668] adrp x16, #0x16000
  [0x1166C] ldr s23, [x16, #0xedc]
  [0x11670] add x16, x13, x15
  [0x11674] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x11678] add x16, x9, x15
  [0x1167C] str s23, [x16, #0x100] ;; misaligned with debug data
  [0x11680] fmov w0, s23
  [0x11684] sxtw x0, w0
  [0x11688] b #0x11a5c
  [0x1168C] adrp x8, #0x11000
  [0x11690] add x8, x8, #0
  [0x11694] cmp x9, x8
  [0x11698] b.ne #0x116d4
  [0x1169C] add x16, x13, x15
  [0x116A0] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x116A4] add x16, x9, x15
  [0x116A8] ldur q23, [x16, #0xc] ;; misaligned with debug data
  [0x116AC] mov v23.16b, v23.16b
  [0x116B0] add x16, x13, x15
  [0x116B4] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x116B8] add x16, x9, x15
  [0x116BC] add x16, x16, #0x4bc ;; misaligned with debug data
  [0x116C0] str q23, [x16] ;; misaligned with debug data
  [0x116C4] mov x0, x14
  [0x116C8] sub x0, x0, x15 ;; misaligned with debug data
  [0x116CC] mov x0, x0
  [0x116D0] b #0x11a5c
  [0x116D4] adrp x8, #0x11000
  [0x116D8] add x8, x8, #0
  [0x116DC] cmp x9, x8
  [0x116E0] b.ne #0x11880
  [0x116E4] add x16, x5, x15
  [0x116E8] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x116EC] mov x8, x14
  [0x116F0] sub x8, x8, x15 ;; misaligned with debug data
  [0x116F4] cmp x9, x8
  [0x116F8] b.eq #0x11738
  [0x116FC] add x16, x13, x15
  [0x11700] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x11704] add x16, x9, x15
  [0x11708] ldrb w9, [x16] ;; misaligned with debug data
  [0x1170C] movz x8, #0x20
  [0x11710] mov x8, x8
  [0x11714] mvn x8, x8
  [0x11718] mov x9, x9
  [0x1171C] and x9, x9, x8
  [0x11720] add x16, x13, x15
  [0x11724] ldr w8, [x16, #0x74] ;; misaligned with debug data
  [0x11728] add x16, x8, x15
  [0x1172C] strb w9, [x16] ;; misaligned with debug data
  [0x11730] mov x9, x9
  [0x11734] b #0x11768
  [0x11738] add x16, x13, x15
  [0x1173C] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x11740] add x16, x9, x15
  [0x11744] ldrb w9, [x16] ;; misaligned with debug data
  [0x11748] mov x9, x9
  [0x1174C] movz x8, #0x20
  [0x11750] orr x9, x9, x8
  [0x11754] add x16, x13, x15
  [0x11758] ldr w8, [x16, #0x74] ;; misaligned with debug data
  [0x1175C] add x16, x8, x15
  [0x11760] strb w9, [x16] ;; misaligned with debug data
  [0x11764] mov x9, x9
  [0x11768] mov x9, sp
  [0x1176C] sub x9, x9, x15
  [0x11770] mov x9, x9
  [0x11774] add x16, x9, x15
  [0x11778] str w12, [x16, #4] ;; misaligned with debug data
  [0x1177C] add x16, x9, x15
  [0x11780] str w6, [x16, #8] ;; misaligned with debug data
  [0x11784] add x16, x9, x15
  [0x11788] str w2, [x16, #0xc] ;; misaligned with debug data
  [0x1178C] add x16, x5, x15
  [0x11790] ldr x8, [x16, #0x10] ;; misaligned with debug data
  [0x11794] add x16, x9, x15
  [0x11798] str x8, [x16, #0x10] ;; misaligned with debug data
  [0x1179C] add x16, x5, x15
  [0x117A0] ldr x8, [x16, #0x18] ;; misaligned with debug data
  [0x117A4] add x16, x9, x15
  [0x117A8] str x8, [x16, #0x18] ;; misaligned with debug data
  [0x117AC] add x16, x5, x15
  [0x117B0] ldr x8, [x16, #0x20] ;; misaligned with debug data
  [0x117B4] add x16, x9, x15
  [0x117B8] str x8, [x16, #0x20] ;; misaligned with debug data
  [0x117BC] add x16, x5, x15
  [0x117C0] ldr x8, [x16, #0x28] ;; misaligned with debug data
  [0x117C4] add x16, x9, x15
  [0x117C8] str x8, [x16, #0x28] ;; misaligned with debug data
  [0x117CC] add x16, x5, x15
  [0x117D0] ldr x8, [x16, #0x30] ;; misaligned with debug data
  [0x117D4] add x16, x9, x15
  [0x117D8] str x8, [x16, #0x30] ;; misaligned with debug data
  [0x117DC] add x16, x5, x15
  [0x117E0] ldr x8, [x16, #0x38] ;; misaligned with debug data
  [0x117E4] add x16, x9, x15
  [0x117E8] str x8, [x16, #0x38] ;; misaligned with debug data
  [0x117EC] add x16, x5, x15
  [0x117F0] ldr x8, [x16, #0x40] ;; misaligned with debug data
  [0x117F4] add x16, x9, x15
  [0x117F8] str x8, [x16, #0x40] ;; misaligned with debug data
  [0x117FC] adrp x16, #0x11000
  [0x11800] add x16, x16, #0
  [0x11804] ldr w8, [x16]
  [0x11808] add x16, x13, x15
  [0x1180C] ldr w1, [x16, #0xd0] ;; misaligned with debug data
  [0x11810] mov x1, x1
  [0x11814] mov x2, x14
  [0x11818] sub x2, x2, x15 ;; misaligned with debug data
  [0x1181C] cmp x1, x2
  [0x11820] b.eq #0x1183c
  [0x11824] add x16, x1, x15
  [0x11828] ldr w1, [x16] ;; misaligned with debug data
  [0x1182C] add x16, x1, x15
  [0x11830] ldr w7, [x16, #0x18] ;; misaligned with debug data
  [0x11834] mov x7, x7
  [0x11838] b #0x11844
  [0x1183C] mov x7, x14
  [0x11840] sub x7, x7, x15 ;; misaligned with debug data
  [0x11844] mov x7, x7
  [0x11848] mov x8, x8
  [0x1184C] mov x7, x7
  [0x11850] mov x6, x9
  [0x11854] add x8, x8, x15
  [0x11858] stp x3, x5, [sp, #-0x10]!
  [0x1185C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11860] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11864] blr x8 ;; misaligned with debug data
  [0x11868] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1186C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11870] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11874] mov x0, x0
  [0x11878] mov x0, x0
  [0x1187C] b #0x11a5c
  [0x11880] adrp x8, #0x11000
  [0x11884] add x8, x8, #0
  [0x11888] cmp x9, x8
  [0x1188C] b.ne #0x118d8
  [0x11890] adrp x16, #0x11000
  [0x11894] add x16, x16, #0
  [0x11898] ldr w9, [x16]
  [0x1189C] add x16, x9, x15
  [0x118A0] add x16, x16, #0x30c ;; misaligned with debug data
  [0x118A4] ldr x0, [x16] ;; misaligned with debug data
  [0x118A8] mov x0, x0
  [0x118AC] add x16, x5, x15
  [0x118B0] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x118B4] mov x9, x9
  [0x118B8] add x0, x0, x9
  [0x118BC] mov x0, x0
  [0x118C0] mov x9, x0
  [0x118C4] add x16, x13, x15
  [0x118C8] add x16, x16, #0x234 ;; misaligned with debug data
  [0x118CC] str x9, [x16] ;; misaligned with debug data
  [0x118D0] mov x0, x0
  [0x118D4] b #0x11a5c
  [0x118D8] adrp x8, #0x11000
  [0x118DC] add x8, x8, #0
  [0x118E0] cmp x9, x8
  [0x118E4] b.ne #0x119c4
  [0x118E8] adrp x16, #0x11000
  [0x118EC] add x16, x16, #0
  [0x118F0] ldr w9, [x16]
  [0x118F4] add x16, x9, x15
  [0x118F8] add x16, x16, #0x30c ;; misaligned with debug data
  [0x118FC] ldr x9, [x16] ;; misaligned with debug data
  [0x11900] mov x9, x9
  [0x11904] add x16, x5, x15
  [0x11908] ldr x8, [x16, #0x10] ;; misaligned with debug data
  [0x1190C] mov x8, x8
  [0x11910] add x9, x9, x8
  [0x11914] add x16, x13, x15
  [0x11918] add x16, x16, #0x23c ;; misaligned with debug data
  [0x1191C] str x9, [x16] ;; misaligned with debug data
  [0x11920] add x16, x13, x15
  [0x11924] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x11928] add x16, x9, x15
  [0x1192C] ldr w9, [x16] ;; misaligned with debug data
  [0x11930] adrp x8, #0x11000
  [0x11934] add x8, x8, #0
  [0x11938] cmp x9, x8
  [0x1193C] b.ne #0x119b4
  [0x11940] mov x6, sp
  [0x11944] sub x6, x6, x15
  [0x11948] mov x6, x6
  [0x1194C] add x16, x6, x15
  [0x11950] str w13, [x16, #4] ;; misaligned with debug data
  [0x11954] movz x9, #0
  [0x11958] add x16, x6, x15
  [0x1195C] str w9, [x16, #8] ;; misaligned with debug data
  [0x11960] adrp x9, #0x11000
  [0x11964] add x9, x9, #0
  [0x11968] add x16, x6, x15
  [0x1196C] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x11970] adrp x16, #0x11000
  [0x11974] add x16, x16, #0
  [0x11978] ldr w9, [x16]
  [0x1197C] mov x9, x9
  [0x11980] mov x7, x13
  [0x11984] mov x6, x6
  [0x11988] add x9, x9, x15
  [0x1198C] stp x3, x5, [sp, #-0x10]!
  [0x11990] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11994] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11998] blr x9 ;; misaligned with debug data
  [0x1199C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x119A0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x119A4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x119A8] mov x0, x0
  [0x119AC] mov x0, x0
  [0x119B0] b #0x119bc
  [0x119B4] mov x0, x14
  [0x119B8] sub x0, x0, x15 ;; misaligned with debug data
  [0x119BC] mov x0, x0
  [0x119C0] b #0x11a5c
  [0x119C4] adrp x8, #0x11000
  [0x119C8] add x8, x8, #0
  [0x119CC] cmp x9, x8
  [0x119D0] b.ne #0x11a54
  [0x119D4] add x16, x5, x15
  [0x119D8] ldr x9, [x16, #0x10] ;; misaligned with debug data
  [0x119DC] mov x9, x9
  [0x119E0] add x16, x13, x15
  [0x119E4] str w9, [x16, #0x48] ;; misaligned with debug data
  [0x119E8] add x16, x5, x15
  [0x119EC] ldr x7, [x16, #0x18] ;; misaligned with debug data
  [0x119F0] add x16, x5, x15
  [0x119F4] ldr x6, [x16, #0x20] ;; misaligned with debug data
  [0x119F8] add x16, x5, x15
  [0x119FC] ldr x2, [x16, #0x28] ;; misaligned with debug data
  [0x11A00] add x16, x5, x15
  [0x11A04] ldr x1, [x16, #0x30] ;; misaligned with debug data
  [0x11A08] adrp x16, #0x11000
  [0x11A0C] add x16, x16, #0
  [0x11A10] ldr w9, [x16]
  [0x11A14] mov x9, x9
  [0x11A18] mov x7, x7
  [0x11A1C] mov x6, x6
  [0x11A20] mov x2, x2
  [0x11A24] mov x1, x1
  [0x11A28] add x9, x9, x15
  [0x11A2C] stp x3, x5, [sp, #-0x10]!
  [0x11A30] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11A34] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11A38] blr x9 ;; misaligned with debug data
  [0x11A3C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11A40] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11A44] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11A48] mov x0, x0
  [0x11A4C] mov x0, x0
  [0x11A50] b #0x11a5c
  [0x11A54] mov x0, x14
  [0x11A58] sub x0, x0, x15 ;; misaligned with debug data
  [0x11A5C] mov x0, x0
  [0x11A60] add sp, sp, #0x50
  [0x11A64] ldr q24, [sp], #0x10
  [0x11A68] ldp x29, x30, [sp], #0x10
  [0x11A6C] ret



