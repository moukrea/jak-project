[entity-task-complete-off]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] add x16, x7, x15
  [0x10010] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10014] mov x9, x9
  [0x10018] add x16, x9, x15
  [0x1001C] ldrb w8, [x16, #0x3b] ;; misaligned with debug data
  [0x10020] movz x1, #0x1
  [0x10024] cmp x8, x1
  [0x10028] b.eq #0x100c0
  [0x1002C] add x16, x9, x15
  [0x10030] ldrb w8, [x16, #0x3b] ;; misaligned with debug data
  [0x10034] mov x8, x8
  [0x10038] lsl x8, x8, #4
  [0x1003C] mov x8, x8
  [0x10040] movz x1, #0xc
  [0x10044] adrp x16, #0x10000
  [0x10048] add x16, x16, #0
  [0x1004C] ldr w2, [x16]
  [0x10050] add x16, x2, x15
  [0x10054] ldr w2, [x16, #0x64] ;; misaligned with debug data
  [0x10058] add x1, x1, x2
  [0x1005C] add x8, x8, x1
  [0x10060] add x16, x8, x15
  [0x10064] ldrh w8, [x16, #8] ;; misaligned with debug data
  [0x10068] movz x1, #0x100
  [0x1006C] mov x1, x1
  [0x10070] mvn x1, x1
  [0x10074] mov x8, x8
  [0x10078] and x8, x8, x1
  [0x1007C] add x16, x9, x15
  [0x10080] ldrb w9, [x16, #0x3b] ;; misaligned with debug data
  [0x10084] mov x9, x9
  [0x10088] lsl x9, x9, #4
  [0x1008C] mov x9, x9
  [0x10090] movz x1, #0xc
  [0x10094] adrp x16, #0x10000
  [0x10098] add x16, x16, #0
  [0x1009C] ldr w2, [x16]
  [0x100A0] add x16, x2, x15
  [0x100A4] ldr w2, [x16, #0x64] ;; misaligned with debug data
  [0x100A8] add x1, x1, x2
  [0x100AC] add x9, x9, x1
  [0x100B0] add x16, x9, x15
  [0x100B4] strh w8, [x16, #8] ;; misaligned with debug data
  [0x100B8] mov x9, x8
  [0x100BC] b #0x100c8
  [0x100C0] mov x9, x14
  [0x100C4] sub x9, x9, x15 ;; misaligned with debug data
  [0x100C8] movz x9, #0
  [0x100CC] ldp x29, x30, [sp], #0x10
  [0x100D0] ret


[entity-task-complete-on]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] add x16, x7, x15
  [0x10010] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10014] mov x9, x9
  [0x10018] add x16, x9, x15
  [0x1001C] ldrb w8, [x16, #0x3b] ;; misaligned with debug data
  [0x10020] movz x1, #0
  [0x10024] cmp x8, x1
  [0x10028] b.eq #0x100b8
  [0x1002C] add x16, x9, x15
  [0x10030] ldrb w8, [x16, #0x3b] ;; misaligned with debug data
  [0x10034] mov x8, x8
  [0x10038] lsl x8, x8, #4
  [0x1003C] mov x8, x8
  [0x10040] movz x1, #0xc
  [0x10044] adrp x16, #0x10000
  [0x10048] add x16, x16, #0
  [0x1004C] ldr w2, [x16]
  [0x10050] add x16, x2, x15
  [0x10054] ldr w2, [x16, #0x64] ;; misaligned with debug data
  [0x10058] add x1, x1, x2
  [0x1005C] add x8, x8, x1
  [0x10060] add x16, x8, x15
  [0x10064] ldrh w8, [x16, #8] ;; misaligned with debug data
  [0x10068] mov x8, x8
  [0x1006C] movz x1, #0x100
  [0x10070] orr x8, x8, x1
  [0x10074] add x16, x9, x15
  [0x10078] ldrb w9, [x16, #0x3b] ;; misaligned with debug data
  [0x1007C] mov x9, x9
  [0x10080] lsl x9, x9, #4
  [0x10084] mov x9, x9
  [0x10088] movz x1, #0xc
  [0x1008C] adrp x16, #0x10000
  [0x10090] add x16, x16, #0
  [0x10094] ldr w2, [x16]
  [0x10098] add x16, x2, x15
  [0x1009C] ldr w2, [x16, #0x64] ;; misaligned with debug data
  [0x100A0] add x1, x1, x2
  [0x100A4] add x9, x9, x1
  [0x100A8] add x16, x9, x15
  [0x100AC] strh w8, [x16, #8] ;; misaligned with debug data
  [0x100B0] mov x9, x8
  [0x100B4] b #0x100c0
  [0x100B8] mov x9, x14
  [0x100BC] sub x9, x9, x15 ;; misaligned with debug data
  [0x100C0] movz x9, #0
  [0x100C4] ldp x29, x30, [sp], #0x10
  [0x100C8] ret


[(method actors-update level-group)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0xa0
  [0x10010] mov x5, x7
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] ldr w9, [x16]
  [0x10020] mov x8, x14
  [0x10024] sub x8, x8, x15 ;; misaligned with debug data
  [0x10028] cmp x9, x8
  [0x1002C] b.eq #0x102cc
  [0x10030] adrp x16, #0x10000
  [0x10034] add x16, x16, #0
  [0x10038] ldr w9, [x16]
  [0x1003C] adrp x8, #0x10000
  [0x10040] add x8, x8, #0
  [0x10044] mov x1, x14
  [0x10048] sub x1, x1, x15 ;; misaligned with debug data
  [0x1004C] cmp x9, x8
  [0x10050] b.ne #0x10060
  [0x10054] add x1, x14, #8
  [0x10058] sub x1, x1, x15 ;; misaligned with debug data
  [0x1005C] mov x1, x1
  [0x10060] mov x9, x1
  [0x10064] mov x8, x14
  [0x10068] sub x8, x8, x15 ;; misaligned with debug data
  [0x1006C] cmp x9, x8
  [0x10070] b.eq #0x100bc
  [0x10074] adrp x16, #0x10000
  [0x10078] add x16, x16, #0
  [0x1007C] ldr w9, [x16]
  [0x10080] add x16, x9, x15
  [0x10084] ldr w9, [x16, #0x50] ;; misaligned with debug data
  [0x10088] adrp x16, #0x10000
  [0x1008C] add x16, x16, #0
  [0x10090] ldr w8, [x16]
  [0x10094] add x16, x8, x15
  [0x10098] ldr w8, [x16, #0x30] ;; misaligned with debug data
  [0x1009C] mov x1, x14
  [0x100A0] sub x1, x1, x15 ;; misaligned with debug data
  [0x100A4] cmp x9, x8
  [0x100A8] b.ne #0x100b8
  [0x100AC] add x1, x14, #8
  [0x100B0] sub x1, x1, x15 ;; misaligned with debug data
  [0x100B4] mov x1, x1
  [0x100B8] mov x9, x1
  [0x100BC] mov x8, x14
  [0x100C0] sub x8, x8, x15 ;; misaligned with debug data
  [0x100C4] cmp x9, x8
  [0x100C8] b.eq #0x10124
  [0x100CC] adrp x16, #0x10000
  [0x100D0] add x16, x16, #0
  [0x100D4] ldr w7, [x16]
  [0x100D8] movz x6, #0x1
  [0x100DC] add x16, x7, x15
  [0x100E0] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100E4] add x16, x9, x15
  [0x100E8] ldr w9, [x16, #0x58] ;; misaligned with debug data
  [0x100EC] mov x9, x9
  [0x100F0] mov x7, x7
  [0x100F4] mov x6, x6
  [0x100F8] add x9, x9, x15
  [0x100FC] stp x3, x5, [sp, #-0x10]!
  [0x10100] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10104] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10108] blr x9 ;; misaligned with debug data
  [0x1010C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10110] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10114] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10118] mov x3, x3
  [0x1011C] mov x3, x3
  [0x10120] b #0x1012c
  [0x10124] mov x3, x14
  [0x10128] sub x3, x3, x15 ;; misaligned with debug data
  [0x1012C] adrp x16, #0x10000
  [0x10130] add x16, x16, #0
  [0x10134] ldr w9, [x16]
  [0x10138] movz x8, #0
  [0x1013C] cmp x9, x8
  [0x10140] b.eq #0x1019c
  [0x10144] adrp x16, #0x10000
  [0x10148] add x16, x16, #0
  [0x1014C] ldr w7, [x16]
  [0x10150] movz x6, #0xa
  [0x10154] add x16, x7, x15
  [0x10158] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1015C] add x16, x9, x15
  [0x10160] ldr w9, [x16, #0x50] ;; misaligned with debug data
  [0x10164] mov x9, x9
  [0x10168] mov x7, x7
  [0x1016C] mov x6, x6
  [0x10170] add x9, x9, x15
  [0x10174] stp x3, x5, [sp, #-0x10]!
  [0x10178] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1017C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10180] blr x9 ;; misaligned with debug data
  [0x10184] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10188] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1018C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10190] mov x3, x3
  [0x10194] mov x3, x3
  [0x10198] b #0x101a4
  [0x1019C] mov x3, x14
  [0x101A0] sub x3, x3, x15 ;; misaligned with debug data
  [0x101A4] adrp x16, #0x10000
  [0x101A8] add x16, x16, #0
  [0x101AC] ldr w3, [x16]
  [0x101B0] adrp x16, #0x10000
  [0x101B4] add x16, x16, #0
  [0x101B8] ldr w9, [x16]
  [0x101BC] adrp x16, #0x13000
  [0x101C0] ldr s23, [x16, #0x27c]
  [0x101C4] adrp x16, #0x13000
  [0x101C8] ldr s22, [x16, #0x280]
  [0x101CC] adrp x16, #0x10000
  [0x101D0] add x16, x16, #0
  [0x101D4] ldr w8, [x16]
  [0x101D8] add x16, x8, x15
  [0x101DC] ldrsw x8, [x16, #0x230] ;; misaligned with debug data
  [0x101E0] mov x8, x8
  [0x101E4] lsl x8, x8, #5
  [0x101E8] mov x8, x8
  [0x101EC] movz x1, #0x234
  [0x101F0] adrp x16, #0x10000
  [0x101F4] add x16, x16, #0
  [0x101F8] ldr w2, [x16]
  [0x101FC] add x1, x1, x2
  [0x10200] add x8, x8, x1
  [0x10204] add x16, x8, x15
  [0x10208] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x1020C] add x16, x8, x15
  [0x10210] ldur x8, [x16, #0x34] ;; misaligned with debug data
  [0x10214] scvtf s21, w8
  [0x10218] adrp x16, #0x13000
  [0x1021C] ldr s20, [x16, #0x284]
  [0x10220] adrp x16, #0x13000
  [0x10224] ldr s19, [x16, #0x288]
  [0x10228] mov x9, x9
  [0x1022C] fmov w7, s23
  [0x10230] sxtw x7, w7
  [0x10234] fmov w6, s22
  [0x10238] sxtw x6, w6
  [0x1023C] fmov w2, s21
  [0x10240] sxtw x2, w2
  [0x10244] fmov w1, s20
  [0x10248] sxtw x1, w1
  [0x1024C] fmov w8, s19
  [0x10250] sxtw x8, w8
  [0x10254] add x9, x9, x15
  [0x10258] stp x3, x5, [sp, #-0x10]!
  [0x1025C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10260] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10264] blr x9 ;; misaligned with debug data
  [0x10268] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1026C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10270] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10274] mov x0, x0
  [0x10278] fmov s23, w0
  [0x1027C] fcvtzs w6, s23
  [0x10280] sxtw x6, w6
  [0x10284] add x16, x3, x15
  [0x10288] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1028C] add x16, x9, x15
  [0x10290] ldr w9, [x16, #0x50] ;; misaligned with debug data
  [0x10294] mov x9, x9
  [0x10298] mov x7, x3
  [0x1029C] mov x6, x6
  [0x102A0] add x9, x9, x15
  [0x102A4] stp x3, x5, [sp, #-0x10]!
  [0x102A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102B0] blr x9 ;; misaligned with debug data
  [0x102B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102C0] mov x3, x3
  [0x102C4] mov x3, x3
  [0x102C8] b #0x102d4
  [0x102CC] mov x3, x14
  [0x102D0] sub x3, x3, x15 ;; misaligned with debug data
  [0x102D4] adrp x16, #0x10000
  [0x102D8] add x16, x16, #0
  [0x102DC] ldr w9, [x16]
  [0x102E0] mov x9, x9
  [0x102E4] add x9, x9, x15
  [0x102E8] stp x3, x5, [sp, #-0x10]!
  [0x102EC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102F0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102F4] blr x9 ;; misaligned with debug data
  [0x102F8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102FC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10300] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10304] mov x0, x0
  [0x10308] mov x9, x14
  [0x1030C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10310] cmp x0, x9
  [0x10314] b.ne #0x105c8
  [0x10318] adrp x16, #0x10000
  [0x1031C] add x16, x16, #0
  [0x10320] ldr w9, [x16]
  [0x10324] add x16, x9, x15
  [0x10328] ldrsw x9, [x16, #0x230] ;; misaligned with debug data
  [0x1032C] mov x9, x9
  [0x10330] lsl x9, x9, #5
  [0x10334] mov x9, x9
  [0x10338] movz x8, #0x234
  [0x1033C] adrp x16, #0x10000
  [0x10340] add x16, x16, #0
  [0x10344] ldr w1, [x16]
  [0x10348] add x8, x8, x1
  [0x1034C] add x9, x9, x8
  [0x10350] add x16, x9, x15
  [0x10354] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10358] add x16, x9, x15
  [0x1035C] ldur x3, [x16, #0x34] ;; misaligned with debug data
  [0x10360] mov x3, x3
  [0x10364] adrp x16, #0x12000
  [0x10368] ldr s23, [x16, #0x28c]
  [0x1036C] mov v23.16b, v23.16b
  [0x10370] adrp x16, #0x12000
  [0x10374] ldr s22, [x16, #0x290]
  [0x10378] mov v22.16b, v22.16b
  [0x1037C] adrp x16, #0x12000
  [0x10380] ldr s21, [x16, #0x294]
  [0x10384] mov v21.16b, v21.16b
  [0x10388] movz x9, #0x1b58
  [0x1038C] mov x9, x9
  [0x10390] sub x9, x9, x3
  [0x10394] scvtf s20, w9
  [0x10398] fmul s21, s21, s20
  [0x1039C] fadd s22, s22, s21
  [0x103A0] mov v22.16b, v22.16b
  [0x103A4] adrp x16, #0x10000
  [0x103A8] add x16, x16, #0
  [0x103AC] ldr w9, [x16]
  [0x103B0] add x16, x9, x15
  [0x103B4] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x103B8] fmin s22, s22, s21
  [0x103BC] fmax s23, s23, s22
  [0x103C0] mov v23.16b, v23.16b
  [0x103C4] adrp x16, #0x10000
  [0x103C8] add x16, x16, #0
  [0x103CC] ldr w9, [x16]
  [0x103D0] adrp x16, #0x10000
  [0x103D4] add x16, x16, #0
  [0x103D8] ldr w8, [x16]
  [0x103DC] add x16, x8, x15
  [0x103E0] ldr s22, [x16] ;; misaligned with debug data
  [0x103E4] adrp x16, #0x12000
  [0x103E8] ldr s21, [x16, #0x298]
  [0x103EC] mov v21.16b, v21.16b
  [0x103F0] adrp x16, #0x10000
  [0x103F4] add x16, x16, #0
  [0x103F8] ldr w8, [x16]
  [0x103FC] add x16, x8, x15
  [0x10400] ldr s20, [x16, #0x388] ;; misaligned with debug data
  [0x10404] fmul s21, s21, s20
  [0x10408] mov x9, x9
  [0x1040C] fmov w7, s22
  [0x10410] sxtw x7, w7
  [0x10414] fmov w6, s23
  [0x10418] sxtw x6, w6
  [0x1041C] fmov w2, s21
  [0x10420] sxtw x2, w2
  [0x10424] add x9, x9, x15
  [0x10428] stp x3, x5, [sp, #-0x10]!
  [0x1042C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10430] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10434] blr x9 ;; misaligned with debug data
  [0x10438] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1043C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10440] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10444] mov x0, x0
  [0x10448] adrp x16, #0x10000
  [0x1044C] add x16, x16, #0
  [0x10450] ldr w9, [x16]
  [0x10454] add x16, x9, x15
  [0x10458] str w0, [x16] ;; misaligned with debug data
  [0x1045C] adrp x16, #0x10000
  [0x10460] add x16, x16, #0
  [0x10464] ldr w12, [x16]
  [0x10468] adrp x16, #0x10000
  [0x1046C] add x16, x16, #0
  [0x10470] ldr w9, [x16]
  [0x10474] add x16, x9, x15
  [0x10478] ldrsw x11, [x16, #8] ;; misaligned with debug data
  [0x1047C] adrp x16, #0x10000
  [0x10480] add x16, x16, #0
  [0x10484] ldr w9, [x16]
  [0x10488] adrp x16, #0x12000
  [0x1048C] ldr s23, [x16, #0x29c]
  [0x10490] adrp x16, #0x12000
  [0x10494] ldr s22, [x16, #0x2a0]
  [0x10498] scvtf s21, w3
  [0x1049C] adrp x16, #0x12000
  [0x104A0] ldr s20, [x16, #0x2a4]
  [0x104A4] adrp x16, #0x12000
  [0x104A8] ldr s19, [x16, #0x2a8]
  [0x104AC] mov x9, x9
  [0x104B0] fmov w7, s23
  [0x104B4] sxtw x7, w7
  [0x104B8] fmov w6, s22
  [0x104BC] sxtw x6, w6
  [0x104C0] fmov w2, s21
  [0x104C4] sxtw x2, w2
  [0x104C8] fmov w1, s20
  [0x104CC] sxtw x1, w1
  [0x104D0] fmov w8, s19
  [0x104D4] sxtw x8, w8
  [0x104D8] add x9, x9, x15
  [0x104DC] stp x3, x5, [sp, #-0x10]!
  [0x104E0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104E4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104E8] blr x9 ;; misaligned with debug data
  [0x104EC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104F0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104F4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104F8] mov x0, x0
  [0x104FC] fmov s23, w0
  [0x10500] fcvtzs w6, s23
  [0x10504] sxtw x6, w6
  [0x10508] movz x2, #0xa
  [0x1050C] mov x12, x12
  [0x10510] mov x7, x11
  [0x10514] mov x6, x6
  [0x10518] mov x2, x2
  [0x1051C] add x12, x12, x15
  [0x10520] stp x3, x5, [sp, #-0x10]!
  [0x10524] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10528] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1052C] blr x12 ;; misaligned with debug data
  [0x10530] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10534] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10538] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1053C] mov x0, x0
  [0x10540] adrp x16, #0x10000
  [0x10544] add x16, x16, #0
  [0x10548] ldr w9, [x16]
  [0x1054C] add x16, x9, x15
  [0x10550] str w0, [x16, #8] ;; misaligned with debug data
  [0x10554] adrp x16, #0x10000
  [0x10558] add x16, x16, #0
  [0x1055C] ldr w9, [x16]
  [0x10560] mov x9, x9
  [0x10564] add x9, x9, x15
  [0x10568] stp x3, x5, [sp, #-0x10]!
  [0x1056C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10570] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10574] blr x9 ;; misaligned with debug data
  [0x10578] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1057C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10580] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10584] mov x0, x0
  [0x10588] mov x9, x14
  [0x1058C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10590] cmp x0, x9
  [0x10594] b.eq #0x105b8
  [0x10598] movz x9, #0x3e8
  [0x1059C] adrp x16, #0x10000
  [0x105A0] add x16, x16, #0
  [0x105A4] ldr w8, [x16]
  [0x105A8] add x16, x8, x15
  [0x105AC] str w9, [x16, #8] ;; misaligned with debug data
  [0x105B0] mov x9, x9
  [0x105B4] b #0x105c0
  [0x105B8] mov x9, x14
  [0x105BC] sub x9, x9, x15 ;; misaligned with debug data
  [0x105C0] mov x9, x9
  [0x105C4] b #0x105d0
  [0x105C8] mov x9, x14
  [0x105CC] sub x9, x9, x15 ;; misaligned with debug data
  [0x105D0] adrp x16, #0x10000
  [0x105D4] add x16, x16, #0
  [0x105D8] ldr w9, [x16]
  [0x105DC] mov x8, x14
  [0x105E0] sub x8, x8, x15 ;; misaligned with debug data
  [0x105E4] cmp x9, x8
  [0x105E8] b.eq #0x118a4
  [0x105EC] adrp x16, #0x10000
  [0x105F0] add x16, x16, #0
  [0x105F4] ldr w9, [x16]
  [0x105F8] mov x9, x9
  [0x105FC] add x9, x9, x15
  [0x10600] stp x3, x5, [sp, #-0x10]!
  [0x10604] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10608] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1060C] blr x9 ;; misaligned with debug data
  [0x10610] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10614] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10618] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1061C] mov x0, x0
  [0x10620] movz x3, #0
  [0x10624] mov x12, x0
  [0x10628] mov x11, x3
  [0x1062C] movz x3, #0
  [0x10630] mov x10, x3
  [0x10634] b #0x11884
  [0x10638] movz x3, #0xa30
  [0x1063C] mul x3, x3, x10
  [0x10640] mov x3, x3
  [0x10644] movz x9, #0x60
  [0x10648] add x9, x9, x5
  [0x1064C] add x3, x3, x9
  [0x10650] mov x3, x3
  [0x10654] str x3, [sp]
  [0x10658] ldr x9, [sp]
  [0x1065C] add x16, x9, x15
  [0x10660] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x10664] adrp x9, #0x10000
  [0x10668] add x9, x9, #0
  [0x1066C] cmp x8, x9
  [0x10670] b.ne #0x1186c
  [0x10674] ldr x9, [sp]
  [0x10678] add x16, x9, x15
  [0x1067C] ldr w8, [x16, #0x174] ;; misaligned with debug data
  [0x10680] adrp x9, #0x10000
  [0x10684] add x9, x9, #0
  [0x10688] cmp x8, x9
  [0x1068C] b.ne #0x1090c
  [0x10690] ldr x9, [sp]
  [0x10694] add x16, x9, x15
  [0x10698] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x1069C] mov x3, x3
  [0x106A0] str x3, [sp, #0x58]
  [0x106A4] ldr x9, [sp, #0x58]
  [0x106A8] add x16, x9, x15
  [0x106AC] ldrsw x3, [x16] ;; misaligned with debug data
  [0x106B0] mov x3, x3
  [0x106B4] str x3, [sp, #0x60]
  [0x106B8] movz x3, #0
  [0x106BC] mov x3, x3
  [0x106C0] str x3, [sp, #0x70]
  [0x106C4] b #0x108ec
  [0x106C8] ldr x9, [sp, #0x70]
  [0x106CC] mov x8, x9
  [0x106D0] lsl x8, x8, #6
  [0x106D4] mov x8, x8
  [0x106D8] movz x1, #0xc
  [0x106DC] ldr x9, [sp, #0x58]
  [0x106E0] add x1, x1, x9
  [0x106E4] add x8, x8, x1
  [0x106E8] mov x8, x8
  [0x106EC] add x16, x8, x15
  [0x106F0] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x106F4] movz x1, #0x80
  [0x106F8] mov x9, x9
  [0x106FC] and x9, x9, x1
  [0x10700] movz x1, #0
  [0x10704] cmp x9, x1
  [0x10708] b.eq #0x10818
  [0x1070C] add x16, x8, x15
  [0x10710] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10714] mov x9, x9
  [0x10718] mov x1, x14
  [0x1071C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10720] cmp x9, x1
  [0x10724] b.ne #0x10760
  [0x10728] add x16, x8, x15
  [0x1072C] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10730] movz x1, #0x5
  [0x10734] mov x9, x9
  [0x10738] and x9, x9, x1
  [0x1073C] movz x1, #0
  [0x10740] mov x2, x14
  [0x10744] sub x2, x2, x15 ;; misaligned with debug data
  [0x10748] cmp x9, x1
  [0x1074C] b.eq #0x1075c
  [0x10750] add x2, x14, #8
  [0x10754] sub x2, x2, x15 ;; misaligned with debug data
  [0x10758] mov x2, x2
  [0x1075C] mov x9, x2
  [0x10760] mov x1, x14
  [0x10764] sub x1, x1, x15 ;; misaligned with debug data
  [0x10768] cmp x9, x1
  [0x1076C] b.ne #0x10808
  [0x10770] add x16, x8, x15
  [0x10774] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x10778] add x16, x7, x15
  [0x1077C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10780] add x16, x9, x15
  [0x10784] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x10788] mov x9, x9
  [0x1078C] mov x7, x7
  [0x10790] add x9, x9, x15
  [0x10794] stp x3, x5, [sp, #-0x10]!
  [0x10798] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1079C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x107A0] blr x9 ;; misaligned with debug data
  [0x107A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x107A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x107AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x107B0] mov x0, x0
  [0x107B4] mov x3, x11
  [0x107B8] movz x9, #0x1
  [0x107BC] add x3, x3, x9
  [0x107C0] mov x11, x3
  [0x107C4] adrp x16, #0x10000
  [0x107C8] add x16, x16, #0
  [0x107CC] ldr w9, [x16]
  [0x107D0] add x16, x9, x15
  [0x107D4] ldrsw x9, [x16, #8] ;; misaligned with debug data
  [0x107D8] cmp x11, x9
  [0x107DC] b.lt #0x107f8
  [0x107E0] mov x0, x14
  [0x107E4] sub x0, x0, x15 ;; misaligned with debug data
  [0x107E8] mov x0, x0
  [0x107EC] mov x0, x0
  [0x107F0] b #0x118b4
  [0x107F4] b #0x10800
  [0x107F8] mov x9, x14
  [0x107FC] sub x9, x9, x15 ;; misaligned with debug data
  [0x10800] mov x9, x9
  [0x10804] b #0x10810
  [0x10808] mov x9, x14
  [0x1080C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10810] mov x9, x9
  [0x10814] b #0x108d4
  [0x10818] add x16, x8, x15
  [0x1081C] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10820] mov x9, x9
  [0x10824] mov x1, x14
  [0x10828] sub x1, x1, x15 ;; misaligned with debug data
  [0x1082C] cmp x9, x1
  [0x10830] b.eq #0x1086c
  [0x10834] add x16, x8, x15
  [0x10838] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1083C] movz x1, #0x8
  [0x10840] mov x9, x9
  [0x10844] and x9, x9, x1
  [0x10848] movz x1, #0
  [0x1084C] mov x2, x14
  [0x10850] sub x2, x2, x15 ;; misaligned with debug data
  [0x10854] cmp x9, x1
  [0x10858] b.ne #0x10868
  [0x1085C] add x2, x14, #8
  [0x10860] sub x2, x2, x15 ;; misaligned with debug data
  [0x10864] mov x2, x2
  [0x10868] mov x9, x2
  [0x1086C] mov x1, x14
  [0x10870] sub x1, x1, x15 ;; misaligned with debug data
  [0x10874] cmp x9, x1
  [0x10878] b.eq #0x108c8
  [0x1087C] add x16, x8, x15
  [0x10880] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x10884] add x16, x7, x15
  [0x10888] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1088C] add x16, x9, x15
  [0x10890] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10894] mov x9, x9
  [0x10898] mov x7, x7
  [0x1089C] add x9, x9, x15
  [0x108A0] stp x3, x5, [sp, #-0x10]!
  [0x108A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108AC] blr x9 ;; misaligned with debug data
  [0x108B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108BC] mov x0, x0
  [0x108C0] mov x0, x0
  [0x108C4] b #0x108d0
  [0x108C8] mov x0, x14
  [0x108CC] sub x0, x0, x15 ;; misaligned with debug data
  [0x108D0] mov x9, x0
  [0x108D4] ldr x3, [sp, #0x70]
  [0x108D8] mov x3, x3
  [0x108DC] movz x9, #0x1
  [0x108E0] add x3, x3, x9
  [0x108E4] mov x3, x3
  [0x108E8] str x3, [sp, #0x70]
  [0x108EC] ldr x9, [sp, #0x60]
  [0x108F0] ldr x8, [sp, #0x70]
  [0x108F4] cmp x8, x9
  [0x108F8] b.lt #0x106c8
  [0x108FC] mov x9, x14
  [0x10900] sub x9, x9, x15 ;; misaligned with debug data
  [0x10904] mov x9, x9
  [0x10908] b #0x11864
  [0x1090C] ldr x9, [sp]
  [0x10910] add x16, x9, x15
  [0x10914] ldr w8, [x16, #0x174] ;; misaligned with debug data
  [0x10918] adrp x9, #0x10000
  [0x1091C] add x9, x9, #0
  [0x10920] cmp x8, x9
  [0x10924] b.ne #0x10c40
  [0x10928] ldr x9, [sp]
  [0x1092C] add x16, x9, x15
  [0x10930] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10934] mov x3, x3
  [0x10938] str x3, [sp, #0x38]
  [0x1093C] ldr x9, [sp, #0x38]
  [0x10940] add x16, x9, x15
  [0x10944] ldrsw x3, [x16] ;; misaligned with debug data
  [0x10948] mov x3, x3
  [0x1094C] str x3, [sp, #0x48]
  [0x10950] movz x3, #0
  [0x10954] mov x3, x3
  [0x10958] str x3, [sp, #0x50]
  [0x1095C] b #0x10c20
  [0x10960] ldr x9, [sp, #0x50]
  [0x10964] mov x3, x9
  [0x10968] lsl x3, x3, #6
  [0x1096C] mov x3, x3
  [0x10970] movz x8, #0xc
  [0x10974] ldr x9, [sp, #0x38]
  [0x10978] add x8, x8, x9
  [0x1097C] add x3, x3, x8
  [0x10980] mov x3, x3
  [0x10984] add x16, x3, x15
  [0x10988] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1098C] movz x8, #0x80
  [0x10990] mov x9, x9
  [0x10994] and x9, x9, x8
  [0x10998] movz x8, #0
  [0x1099C] mov x1, x14
  [0x109A0] sub x1, x1, x15 ;; misaligned with debug data
  [0x109A4] cmp x9, x8
  [0x109A8] b.eq #0x109b8
  [0x109AC] add x1, x14, #8
  [0x109B0] sub x1, x1, x15 ;; misaligned with debug data
  [0x109B4] mov x1, x1
  [0x109B8] mov x9, x1
  [0x109BC] mov x8, x14
  [0x109C0] sub x8, x8, x15 ;; misaligned with debug data
  [0x109C4] cmp x9, x8
  [0x109C8] b.eq #0x10a20
  [0x109CC] add x16, x3, x15
  [0x109D0] ldrsw x6, [x16, #0x14] ;; misaligned with debug data
  [0x109D4] ldr x9, [sp]
  [0x109D8] add x16, x9, x15
  [0x109DC] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x109E0] add x16, x8, x15
  [0x109E4] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x109E8] mov x8, x9
  [0x109EC] ldr x9, [sp]
  [0x109F0] mov x7, x9
  [0x109F4] mov x6, x6
  [0x109F8] add x8, x8, x15
  [0x109FC] stp x3, x5, [sp, #-0x10]!
  [0x10A00] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A04] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A08] blr x8 ;; misaligned with debug data
  [0x10A0C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A10] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A14] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A18] mov x0, x0
  [0x10A1C] mov x9, x0
  [0x10A20] mov x8, x14
  [0x10A24] sub x8, x8, x15 ;; misaligned with debug data
  [0x10A28] cmp x9, x8
  [0x10A2C] b.eq #0x10b00
  [0x10A30] add x16, x3, x15
  [0x10A34] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10A38] mov x9, x9
  [0x10A3C] mov x8, x14
  [0x10A40] sub x8, x8, x15 ;; misaligned with debug data
  [0x10A44] cmp x9, x8
  [0x10A48] b.ne #0x10a84
  [0x10A4C] add x16, x3, x15
  [0x10A50] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10A54] movz x8, #0x5
  [0x10A58] mov x9, x9
  [0x10A5C] and x9, x9, x8
  [0x10A60] movz x8, #0
  [0x10A64] mov x1, x14
  [0x10A68] sub x1, x1, x15 ;; misaligned with debug data
  [0x10A6C] cmp x9, x8
  [0x10A70] b.eq #0x10a80
  [0x10A74] add x1, x14, #8
  [0x10A78] sub x1, x1, x15 ;; misaligned with debug data
  [0x10A7C] mov x1, x1
  [0x10A80] mov x9, x1
  [0x10A84] mov x8, x14
  [0x10A88] sub x8, x8, x15 ;; misaligned with debug data
  [0x10A8C] cmp x9, x8
  [0x10A90] b.ne #0x10af0
  [0x10A94] add x16, x3, x15
  [0x10A98] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x10A9C] add x16, x7, x15
  [0x10AA0] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10AA4] add x16, x9, x15
  [0x10AA8] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x10AAC] mov x9, x9
  [0x10AB0] mov x7, x7
  [0x10AB4] add x9, x9, x15
  [0x10AB8] stp x3, x5, [sp, #-0x10]!
  [0x10ABC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AC0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AC4] blr x9 ;; misaligned with debug data
  [0x10AC8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10ACC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10AD0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AD4] mov x0, x0
  [0x10AD8] mov x9, x11
  [0x10ADC] movz x8, #0x1
  [0x10AE0] add x9, x9, x8
  [0x10AE4] mov x11, x9
  [0x10AE8] mov x9, x9
  [0x10AEC] b #0x10af8
  [0x10AF0] mov x9, x14
  [0x10AF4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10AF8] mov x9, x9
  [0x10AFC] b #0x10bcc
  [0x10B00] add x16, x3, x15
  [0x10B04] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10B08] mov x9, x9
  [0x10B0C] mov x8, x14
  [0x10B10] sub x8, x8, x15 ;; misaligned with debug data
  [0x10B14] cmp x9, x8
  [0x10B18] b.eq #0x10b54
  [0x10B1C] add x16, x3, x15
  [0x10B20] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10B24] movz x8, #0x8
  [0x10B28] mov x9, x9
  [0x10B2C] and x9, x9, x8
  [0x10B30] movz x8, #0
  [0x10B34] mov x1, x14
  [0x10B38] sub x1, x1, x15 ;; misaligned with debug data
  [0x10B3C] cmp x9, x8
  [0x10B40] b.ne #0x10b50
  [0x10B44] add x1, x14, #8
  [0x10B48] sub x1, x1, x15 ;; misaligned with debug data
  [0x10B4C] mov x1, x1
  [0x10B50] mov x9, x1
  [0x10B54] mov x8, x14
  [0x10B58] sub x8, x8, x15 ;; misaligned with debug data
  [0x10B5C] cmp x9, x8
  [0x10B60] b.eq #0x10bc0
  [0x10B64] add x16, x3, x15
  [0x10B68] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x10B6C] add x16, x7, x15
  [0x10B70] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10B74] add x16, x9, x15
  [0x10B78] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10B7C] mov x9, x9
  [0x10B80] mov x7, x7
  [0x10B84] add x9, x9, x15
  [0x10B88] stp x3, x5, [sp, #-0x10]!
  [0x10B8C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B90] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B94] blr x9 ;; misaligned with debug data
  [0x10B98] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B9C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10BA0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10BA4] mov x0, x0
  [0x10BA8] mov x9, x11
  [0x10BAC] movz x8, #0x1
  [0x10BB0] add x9, x9, x8
  [0x10BB4] mov x11, x9
  [0x10BB8] mov x9, x9
  [0x10BBC] b #0x10bc8
  [0x10BC0] mov x9, x14
  [0x10BC4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BC8] mov x9, x9
  [0x10BCC] adrp x16, #0x10000
  [0x10BD0] add x16, x16, #0
  [0x10BD4] ldr w9, [x16]
  [0x10BD8] add x16, x9, x15
  [0x10BDC] ldrsw x9, [x16, #8] ;; misaligned with debug data
  [0x10BE0] cmp x11, x9
  [0x10BE4] b.lt #0x10c00
  [0x10BE8] mov x0, x14
  [0x10BEC] sub x0, x0, x15 ;; misaligned with debug data
  [0x10BF0] mov x0, x0
  [0x10BF4] mov x0, x0
  [0x10BF8] b #0x118b4
  [0x10BFC] b #0x10c08
  [0x10C00] mov x9, x14
  [0x10C04] sub x9, x9, x15 ;; misaligned with debug data
  [0x10C08] ldr x3, [sp, #0x50]
  [0x10C0C] mov x3, x3
  [0x10C10] movz x9, #0x1
  [0x10C14] add x3, x3, x9
  [0x10C18] mov x3, x3
  [0x10C1C] str x3, [sp, #0x50]
  [0x10C20] ldr x9, [sp, #0x48]
  [0x10C24] ldr x8, [sp, #0x50]
  [0x10C28] cmp x8, x9
  [0x10C2C] b.lt #0x10960
  [0x10C30] mov x9, x14
  [0x10C34] sub x9, x9, x15 ;; misaligned with debug data
  [0x10C38] mov x9, x9
  [0x10C3C] b #0x11864
  [0x10C40] ldr x9, [sp]
  [0x10C44] add x16, x9, x15
  [0x10C48] ldr w8, [x16, #0x174] ;; misaligned with debug data
  [0x10C4C] adrp x9, #0x10000
  [0x10C50] add x9, x9, #0
  [0x10C54] cmp x8, x9
  [0x10C58] b.ne #0x10ed0
  [0x10C5C] ldr x9, [sp]
  [0x10C60] add x16, x9, x15
  [0x10C64] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10C68] mov x3, x3
  [0x10C6C] str x3, [sp, #0x68]
  [0x10C70] ldr x9, [sp, #0x68]
  [0x10C74] add x16, x9, x15
  [0x10C78] ldrsw x3, [x16] ;; misaligned with debug data
  [0x10C7C] mov x3, x3
  [0x10C80] str x3, [sp, #0x78]
  [0x10C84] movz x3, #0
  [0x10C88] mov x3, x3
  [0x10C8C] str x3, [sp, #0x80]
  [0x10C90] b #0x10eb0
  [0x10C94] ldr x9, [sp, #0x80]
  [0x10C98] mov x8, x9
  [0x10C9C] lsl x8, x8, #6
  [0x10CA0] mov x8, x8
  [0x10CA4] movz x1, #0xc
  [0x10CA8] ldr x9, [sp, #0x68]
  [0x10CAC] add x1, x1, x9
  [0x10CB0] add x8, x8, x1
  [0x10CB4] mov x8, x8
  [0x10CB8] add x9, x14, #8
  [0x10CBC] sub x9, x9, x15 ;; misaligned with debug data
  [0x10CC0] mov x1, x14
  [0x10CC4] sub x1, x1, x15 ;; misaligned with debug data
  [0x10CC8] cmp x9, x1
  [0x10CCC] b.eq #0x10ddc
  [0x10CD0] add x16, x8, x15
  [0x10CD4] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10CD8] mov x9, x9
  [0x10CDC] mov x1, x14
  [0x10CE0] sub x1, x1, x15 ;; misaligned with debug data
  [0x10CE4] cmp x9, x1
  [0x10CE8] b.ne #0x10d24
  [0x10CEC] add x16, x8, x15
  [0x10CF0] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10CF4] movz x1, #0x5
  [0x10CF8] mov x9, x9
  [0x10CFC] and x9, x9, x1
  [0x10D00] movz x1, #0
  [0x10D04] mov x2, x14
  [0x10D08] sub x2, x2, x15 ;; misaligned with debug data
  [0x10D0C] cmp x9, x1
  [0x10D10] b.eq #0x10d20
  [0x10D14] add x2, x14, #8
  [0x10D18] sub x2, x2, x15 ;; misaligned with debug data
  [0x10D1C] mov x2, x2
  [0x10D20] mov x9, x2
  [0x10D24] mov x1, x14
  [0x10D28] sub x1, x1, x15 ;; misaligned with debug data
  [0x10D2C] cmp x9, x1
  [0x10D30] b.ne #0x10dcc
  [0x10D34] add x16, x8, x15
  [0x10D38] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x10D3C] add x16, x7, x15
  [0x10D40] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10D44] add x16, x9, x15
  [0x10D48] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x10D4C] mov x9, x9
  [0x10D50] mov x7, x7
  [0x10D54] add x9, x9, x15
  [0x10D58] stp x3, x5, [sp, #-0x10]!
  [0x10D5C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D60] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D64] blr x9 ;; misaligned with debug data
  [0x10D68] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D6C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D70] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D74] mov x0, x0
  [0x10D78] mov x3, x11
  [0x10D7C] movz x9, #0x1
  [0x10D80] add x3, x3, x9
  [0x10D84] mov x11, x3
  [0x10D88] adrp x16, #0x10000
  [0x10D8C] add x16, x16, #0
  [0x10D90] ldr w9, [x16]
  [0x10D94] add x16, x9, x15
  [0x10D98] ldrsw x9, [x16, #8] ;; misaligned with debug data
  [0x10D9C] cmp x11, x9
  [0x10DA0] b.lt #0x10dbc
  [0x10DA4] mov x0, x14
  [0x10DA8] sub x0, x0, x15 ;; misaligned with debug data
  [0x10DAC] mov x0, x0
  [0x10DB0] mov x0, x0
  [0x10DB4] b #0x118b4
  [0x10DB8] b #0x10dc4
  [0x10DBC] mov x9, x14
  [0x10DC0] sub x9, x9, x15 ;; misaligned with debug data
  [0x10DC4] mov x9, x9
  [0x10DC8] b #0x10dd4
  [0x10DCC] mov x9, x14
  [0x10DD0] sub x9, x9, x15 ;; misaligned with debug data
  [0x10DD4] mov x9, x9
  [0x10DD8] b #0x10e98
  [0x10DDC] add x16, x8, x15
  [0x10DE0] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10DE4] mov x9, x9
  [0x10DE8] mov x1, x14
  [0x10DEC] sub x1, x1, x15 ;; misaligned with debug data
  [0x10DF0] cmp x9, x1
  [0x10DF4] b.eq #0x10e30
  [0x10DF8] add x16, x8, x15
  [0x10DFC] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10E00] movz x1, #0x8
  [0x10E04] mov x9, x9
  [0x10E08] and x9, x9, x1
  [0x10E0C] movz x1, #0
  [0x10E10] mov x2, x14
  [0x10E14] sub x2, x2, x15 ;; misaligned with debug data
  [0x10E18] cmp x9, x1
  [0x10E1C] b.ne #0x10e2c
  [0x10E20] add x2, x14, #8
  [0x10E24] sub x2, x2, x15 ;; misaligned with debug data
  [0x10E28] mov x2, x2
  [0x10E2C] mov x9, x2
  [0x10E30] mov x1, x14
  [0x10E34] sub x1, x1, x15 ;; misaligned with debug data
  [0x10E38] cmp x9, x1
  [0x10E3C] b.eq #0x10e8c
  [0x10E40] add x16, x8, x15
  [0x10E44] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x10E48] add x16, x7, x15
  [0x10E4C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10E50] add x16, x9, x15
  [0x10E54] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10E58] mov x9, x9
  [0x10E5C] mov x7, x7
  [0x10E60] add x9, x9, x15
  [0x10E64] stp x3, x5, [sp, #-0x10]!
  [0x10E68] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E6C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10E70] blr x9 ;; misaligned with debug data
  [0x10E74] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10E78] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10E7C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10E80] mov x0, x0
  [0x10E84] mov x0, x0
  [0x10E88] b #0x10e94
  [0x10E8C] mov x0, x14
  [0x10E90] sub x0, x0, x15 ;; misaligned with debug data
  [0x10E94] mov x9, x0
  [0x10E98] ldr x3, [sp, #0x80]
  [0x10E9C] mov x3, x3
  [0x10EA0] movz x9, #0x1
  [0x10EA4] add x3, x3, x9
  [0x10EA8] mov x3, x3
  [0x10EAC] str x3, [sp, #0x80]
  [0x10EB0] ldr x9, [sp, #0x78]
  [0x10EB4] ldr x8, [sp, #0x80]
  [0x10EB8] cmp x8, x9
  [0x10EBC] b.lt #0x10c94
  [0x10EC0] mov x9, x14
  [0x10EC4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10EC8] mov x9, x9
  [0x10ECC] b #0x11864
  [0x10ED0] adrp x16, #0x10000
  [0x10ED4] add x16, x16, #0
  [0x10ED8] ldr w9, [x16]
  [0x10EDC] mov x8, x14
  [0x10EE0] sub x8, x8, x15 ;; misaligned with debug data
  [0x10EE4] cmp x9, x8
  [0x10EE8] b.ne #0x1121c
  [0x10EEC] ldr x9, [sp]
  [0x10EF0] add x16, x9, x15
  [0x10EF4] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10EF8] mov x3, x3
  [0x10EFC] str x3, [sp, #0x28]
  [0x10F00] ldr x9, [sp, #0x28]
  [0x10F04] add x16, x9, x15
  [0x10F08] ldrsw x3, [x16] ;; misaligned with debug data
  [0x10F0C] mov x3, x3
  [0x10F10] str x3, [sp, #0x30]
  [0x10F14] movz x3, #0
  [0x10F18] mov x3, x3
  [0x10F1C] str x3, [sp, #0x40]
  [0x10F20] b #0x111fc
  [0x10F24] ldr x9, [sp, #0x40]
  [0x10F28] mov x3, x9
  [0x10F2C] lsl x3, x3, #6
  [0x10F30] mov x3, x3
  [0x10F34] movz x8, #0xc
  [0x10F38] ldr x9, [sp, #0x28]
  [0x10F3C] add x8, x8, x9
  [0x10F40] add x3, x3, x8
  [0x10F44] mov x3, x3
  [0x10F48] adrp x16, #0x10000
  [0x10F4C] add x16, x16, #0
  [0x10F50] ldr w9, [x16]
  [0x10F54] movz x7, #0x20
  [0x10F58] add x7, x7, x3
  [0x10F5C] mov x9, x9
  [0x10F60] mov x7, x7
  [0x10F64] mov x6, x12
  [0x10F68] add x9, x9, x15
  [0x10F6C] stp x3, x5, [sp, #-0x10]!
  [0x10F70] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F74] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F78] blr x9 ;; misaligned with debug data
  [0x10F7C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10F80] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10F84] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10F88] mov x0, x0
  [0x10F8C] fmov s23, w0
  [0x10F90] adrp x16, #0x10000
  [0x10F94] add x16, x16, #0
  [0x10F98] ldr w9, [x16]
  [0x10F9C] add x16, x9, x15
  [0x10FA0] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x10FA4] mov x9, x14
  [0x10FA8] sub x9, x9, x15 ;; misaligned with debug data
  [0x10FAC] fcmp s23, s22
  [0x10FB0] b.ge #0x10fc0
  [0x10FB4] add x9, x14, #8
  [0x10FB8] sub x9, x9, x15 ;; misaligned with debug data
  [0x10FBC] mov x9, x9
  [0x10FC0] mov x9, x9
  [0x10FC4] mov x8, x14
  [0x10FC8] sub x8, x8, x15 ;; misaligned with debug data
  [0x10FCC] cmp x9, x8
  [0x10FD0] b.eq #0x1100c
  [0x10FD4] add x16, x3, x15
  [0x10FD8] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10FDC] movz x8, #0x600
  [0x10FE0] mov x9, x9
  [0x10FE4] and x9, x9, x8
  [0x10FE8] movz x8, #0
  [0x10FEC] mov x1, x14
  [0x10FF0] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FF4] cmp x9, x8
  [0x10FF8] b.ne #0x11008
  [0x10FFC] add x1, x14, #8
  [0x11000] sub x1, x1, x15 ;; misaligned with debug data
  [0x11004] mov x1, x1
  [0x11008] mov x9, x1
  [0x1100C] mov x8, x14
  [0x11010] sub x8, x8, x15 ;; misaligned with debug data
  [0x11014] cmp x9, x8
  [0x11018] b.eq #0x11128
  [0x1101C] add x16, x3, x15
  [0x11020] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x11024] mov x9, x9
  [0x11028] mov x8, x14
  [0x1102C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11030] cmp x9, x8
  [0x11034] b.ne #0x11070
  [0x11038] add x16, x3, x15
  [0x1103C] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x11040] movz x8, #0x5
  [0x11044] mov x9, x9
  [0x11048] and x9, x9, x8
  [0x1104C] movz x8, #0
  [0x11050] mov x1, x14
  [0x11054] sub x1, x1, x15 ;; misaligned with debug data
  [0x11058] cmp x9, x8
  [0x1105C] b.eq #0x1106c
  [0x11060] add x1, x14, #8
  [0x11064] sub x1, x1, x15 ;; misaligned with debug data
  [0x11068] mov x1, x1
  [0x1106C] mov x9, x1
  [0x11070] mov x8, x14
  [0x11074] sub x8, x8, x15 ;; misaligned with debug data
  [0x11078] cmp x9, x8
  [0x1107C] b.ne #0x11118
  [0x11080] add x16, x3, x15
  [0x11084] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x11088] add x16, x7, x15
  [0x1108C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11090] add x16, x9, x15
  [0x11094] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x11098] mov x9, x9
  [0x1109C] mov x7, x7
  [0x110A0] add x9, x9, x15
  [0x110A4] stp x3, x5, [sp, #-0x10]!
  [0x110A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x110AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x110B0] blr x9 ;; misaligned with debug data
  [0x110B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x110B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x110BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x110C0] mov x0, x0
  [0x110C4] mov x3, x11
  [0x110C8] movz x9, #0x1
  [0x110CC] add x3, x3, x9
  [0x110D0] mov x11, x3
  [0x110D4] adrp x16, #0x11000
  [0x110D8] add x16, x16, #0
  [0x110DC] ldr w9, [x16]
  [0x110E0] add x16, x9, x15
  [0x110E4] ldrsw x9, [x16, #8] ;; misaligned with debug data
  [0x110E8] cmp x11, x9
  [0x110EC] b.lt #0x11108
  [0x110F0] mov x0, x14
  [0x110F4] sub x0, x0, x15 ;; misaligned with debug data
  [0x110F8] mov x0, x0
  [0x110FC] mov x0, x0
  [0x11100] b #0x118b4
  [0x11104] b #0x11110
  [0x11108] mov x9, x14
  [0x1110C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11110] mov x9, x9
  [0x11114] b #0x11120
  [0x11118] mov x9, x14
  [0x1111C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11120] mov x9, x9
  [0x11124] b #0x111e4
  [0x11128] add x16, x3, x15
  [0x1112C] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x11130] mov x9, x9
  [0x11134] mov x8, x14
  [0x11138] sub x8, x8, x15 ;; misaligned with debug data
  [0x1113C] cmp x9, x8
  [0x11140] b.eq #0x1117c
  [0x11144] add x16, x3, x15
  [0x11148] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1114C] movz x8, #0x8
  [0x11150] mov x9, x9
  [0x11154] and x9, x9, x8
  [0x11158] movz x8, #0
  [0x1115C] mov x1, x14
  [0x11160] sub x1, x1, x15 ;; misaligned with debug data
  [0x11164] cmp x9, x8
  [0x11168] b.ne #0x11178
  [0x1116C] add x1, x14, #8
  [0x11170] sub x1, x1, x15 ;; misaligned with debug data
  [0x11174] mov x1, x1
  [0x11178] mov x9, x1
  [0x1117C] mov x8, x14
  [0x11180] sub x8, x8, x15 ;; misaligned with debug data
  [0x11184] cmp x9, x8
  [0x11188] b.eq #0x111d8
  [0x1118C] add x16, x3, x15
  [0x11190] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x11194] add x16, x7, x15
  [0x11198] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1119C] add x16, x9, x15
  [0x111A0] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x111A4] mov x9, x9
  [0x111A8] mov x7, x7
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
  [0x111D4] b #0x111e0
  [0x111D8] mov x0, x14
  [0x111DC] sub x0, x0, x15 ;; misaligned with debug data
  [0x111E0] mov x9, x0
  [0x111E4] ldr x3, [sp, #0x40]
  [0x111E8] mov x3, x3
  [0x111EC] movz x9, #0x1
  [0x111F0] add x3, x3, x9
  [0x111F4] mov x3, x3
  [0x111F8] str x3, [sp, #0x40]
  [0x111FC] ldr x9, [sp, #0x30]
  [0x11200] ldr x8, [sp, #0x40]
  [0x11204] cmp x8, x9
  [0x11208] b.lt #0x10f24
  [0x1120C] mov x9, x14
  [0x11210] sub x9, x9, x15 ;; misaligned with debug data
  [0x11214] mov x9, x9
  [0x11218] b #0x11864
  [0x1121C] adrp x16, #0x11000
  [0x11220] add x16, x16, #0
  [0x11224] ldr w9, [x16]
  [0x11228] mov x8, x14
  [0x1122C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11230] cmp x9, x8
  [0x11234] b.eq #0x1185c
  [0x11238] ldr x9, [sp]
  [0x1123C] add x16, x9, x15
  [0x11240] ldr w8, [x16, #0x194] ;; misaligned with debug data
  [0x11244] mov x9, x8
  [0x11248] mov x8, x14
  [0x1124C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11250] cmp x9, x8
  [0x11254] b.eq #0x11268
  [0x11258] ldr x9, [sp]
  [0x1125C] add x16, x9, x15
  [0x11260] ldr w8, [x16, #0x188] ;; misaligned with debug data
  [0x11264] mov x9, x8
  [0x11268] mov x8, x14
  [0x1126C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11270] cmp x9, x8
  [0x11274] b.ne #0x1184c
  [0x11278] ldr x9, [sp]
  [0x1127C] add x16, x9, x15
  [0x11280] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x11284] mov x3, x3
  [0x11288] str x3, [sp, #8]
  [0x1128C] ldr x9, [sp, #8]
  [0x11290] add x16, x9, x15
  [0x11294] ldrsw x3, [x16] ;; misaligned with debug data
  [0x11298] mov x3, x3
  [0x1129C] str x3, [sp, #0x10]
  [0x112A0] mov x3, x14
  [0x112A4] sub x3, x3, x15 ;; misaligned with debug data
  [0x112A8] mov x3, x3
  [0x112AC] str x3, [sp, #0x18]
  [0x112B0] movz x3, #0
  [0x112B4] mov x3, x3
  [0x112B8] str x3, [sp, #0x20]
  [0x112BC] b #0x1182c
  [0x112C0] ldr x9, [sp, #0x20]
  [0x112C4] mov x3, x9
  [0x112C8] lsl x3, x3, #6
  [0x112CC] mov x3, x3
  [0x112D0] movz x8, #0xc
  [0x112D4] ldr x9, [sp, #8]
  [0x112D8] add x8, x8, x9
  [0x112DC] add x3, x3, x8
  [0x112E0] mov x3, x3
  [0x112E4] adrp x16, #0x11000
  [0x112E8] add x16, x16, #0
  [0x112EC] ldr w9, [x16]
  [0x112F0] mov x9, x9
  [0x112F4] mov x8, x14
  [0x112F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x112FC] cmp x9, x8
  [0x11300] b.eq #0x11344
  [0x11304] adrp x16, #0x11000
  [0x11308] add x16, x16, #0
  [0x1130C] ldr w9, [x16]
  [0x11310] add x16, x9, x15
  [0x11314] ldr w9, [x16, #0x13c] ;; misaligned with debug data
  [0x11318] mov x8, x14
  [0x1131C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11320] mov x1, x14
  [0x11324] sub x1, x1, x15 ;; misaligned with debug data
  [0x11328] cmp x9, x8
  [0x1132C] b.ne #0x1133c
  [0x11330] add x1, x14, #8
  [0x11334] sub x1, x1, x15 ;; misaligned with debug data
  [0x11338] mov x1, x1
  [0x1133C] mov x9, x1
  [0x11340] b #0x1134c
  [0x11344] mov x9, x14
  [0x11348] sub x9, x9, x15 ;; misaligned with debug data
  [0x1134C] mov x9, x9
  [0x11350] mov x8, x14
  [0x11354] sub x8, x8, x15 ;; misaligned with debug data
  [0x11358] cmp x9, x8
  [0x1135C] b.ne #0x113b4
  [0x11360] add x16, x3, x15
  [0x11364] ldrsw x6, [x16, #0x14] ;; misaligned with debug data
  [0x11368] ldr x9, [sp]
  [0x1136C] add x16, x9, x15
  [0x11370] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x11374] add x16, x8, x15
  [0x11378] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x1137C] mov x8, x9
  [0x11380] ldr x9, [sp]
  [0x11384] mov x7, x9
  [0x11388] mov x6, x6
  [0x1138C] add x8, x8, x15
  [0x11390] stp x3, x5, [sp, #-0x10]!
  [0x11394] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11398] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1139C] blr x8 ;; misaligned with debug data
  [0x113A0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x113A4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x113A8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x113AC] mov x0, x0
  [0x113B0] mov x9, x0
  [0x113B4] mov x9, x9
  [0x113B8] mov x8, x14
  [0x113BC] sub x8, x8, x15 ;; misaligned with debug data
  [0x113C0] cmp x9, x8
  [0x113C4] b.eq #0x11400
  [0x113C8] add x16, x3, x15
  [0x113CC] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x113D0] movz x8, #0x600
  [0x113D4] mov x9, x9
  [0x113D8] and x9, x9, x8
  [0x113DC] movz x8, #0
  [0x113E0] mov x1, x14
  [0x113E4] sub x1, x1, x15 ;; misaligned with debug data
  [0x113E8] cmp x9, x8
  [0x113EC] b.ne #0x113fc
  [0x113F0] add x1, x14, #8
  [0x113F4] sub x1, x1, x15 ;; misaligned with debug data
  [0x113F8] mov x1, x1
  [0x113FC] mov x9, x1
  [0x11400] mov x8, x14
  [0x11404] sub x8, x8, x15 ;; misaligned with debug data
  [0x11408] cmp x9, x8
  [0x1140C] b.eq #0x1170c
  [0x11410] add x16, x3, x15
  [0x11414] ldr w8, [x16, #0xc] ;; misaligned with debug data
  [0x11418] mov x8, x8
  [0x1141C] mov x9, x14
  [0x11420] sub x9, x9, x15 ;; misaligned with debug data
  [0x11424] cmp x8, x9
  [0x11428] b.ne #0x1147c
  [0x1142C] add x16, x3, x15
  [0x11430] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x11434] movz x8, #0x5
  [0x11438] mov x9, x9
  [0x1143C] and x9, x9, x8
  [0x11440] movz x8, #0
  [0x11444] mov x1, x14
  [0x11448] sub x1, x1, x15 ;; misaligned with debug data
  [0x1144C] cmp x9, x8
  [0x11450] b.eq #0x11460
  [0x11454] add x1, x14, #8
  [0x11458] sub x1, x1, x15 ;; misaligned with debug data
  [0x1145C] mov x1, x1
  [0x11460] mov x8, x1
  [0x11464] mov x9, x14
  [0x11468] sub x9, x9, x15 ;; misaligned with debug data
  [0x1146C] cmp x8, x9
  [0x11470] b.ne #0x1147c
  [0x11474] ldr x9, [sp, #0x18]
  [0x11478] mov x8, x9
  [0x1147C] mov x9, x14
  [0x11480] sub x9, x9, x15 ;; misaligned with debug data
  [0x11484] cmp x8, x9
  [0x11488] b.ne #0x116fc
  [0x1148C] add x16, x3, x15
  [0x11490] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x11494] add x16, x7, x15
  [0x11498] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1149C] add x16, x9, x15
  [0x114A0] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x114A4] mov x9, x9
  [0x114A8] mov x7, x7
  [0x114AC] add x9, x9, x15
  [0x114B0] stp x3, x5, [sp, #-0x10]!
  [0x114B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x114B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x114BC] blr x9 ;; misaligned with debug data
  [0x114C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x114C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x114C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x114CC] mov x0, x0
  [0x114D0] mov x3, x11
  [0x114D4] movz x9, #0x1
  [0x114D8] add x3, x3, x9
  [0x114DC] mov x11, x3
  [0x114E0] adrp x16, #0x11000
  [0x114E4] add x16, x16, #0
  [0x114E8] ldr w7, [x16]
  [0x114EC] add x16, x7, x15
  [0x114F0] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x114F4] add x16, x9, x15
  [0x114F8] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x114FC] mov x9, x9
  [0x11500] mov x7, x7
  [0x11504] add x9, x9, x15
  [0x11508] stp x3, x5, [sp, #-0x10]!
  [0x1150C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11510] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11514] blr x9 ;; misaligned with debug data
  [0x11518] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1151C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11520] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11524] mov x0, x0
  [0x11528] scvtf s24, w0
  [0x1152C] adrp x16, #0x11000
  [0x11530] add x16, x16, #0
  [0x11534] ldr w7, [x16]
  [0x11538] add x16, x7, x15
  [0x1153C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11540] add x16, x9, x15
  [0x11544] ldr w9, [x16, #0x60] ;; misaligned with debug data
  [0x11548] mov x9, x9
  [0x1154C] mov x7, x7
  [0x11550] add x9, x9, x15
  [0x11554] stp x3, x5, [sp, #-0x10]!
  [0x11558] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1155C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11560] blr x9 ;; misaligned with debug data
  [0x11564] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11568] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1156C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11570] mov x0, x0
  [0x11574] scvtf s23, w0
  [0x11578] adrp x16, #0x12000
  [0x1157C] ldr s22, [x16, #0x2ac]
  [0x11580] fcmp s22, s23
  [0x11584] b.eq #0x11594
  [0x11588] mov v24.16b, v24.16b
  [0x1158C] fdiv s24, s24, s23
  [0x11590] b #0x115c8
  [0x11594] movz x9, #0xffff
  [0x11598] movk x9, #0x7f7f, lsl #16
  [0x1159C] movz x8, #0
  [0x115A0] movk x8, #0x8000, lsl #16
  [0x115A4] fmov w1, s24
  [0x115A8] sxtw x1, w1
  [0x115AC] and x1, x1, x8
  [0x115B0] eor x9, x9, x1
  [0x115B4] fmov w1, s23
  [0x115B8] sxtw x1, w1
  [0x115BC] and x1, x1, x8
  [0x115C0] eor x9, x9, x1
  [0x115C4] fmov s24, w9
  [0x115C8] adrp x16, #0x12000
  [0x115CC] ldr s23, [x16, #0x2b0]
  [0x115D0] fcmp s24, s23
  [0x115D4] b.ge #0x116ec
  [0x115D8] adrp x16, #0x11000
  [0x115DC] add x16, x16, #0
  [0x115E0] ldr w3, [x16]
  [0x115E4] movz x9, #0
  [0x115E8] str x9, [sp, #0x88]
  [0x115EC] adrp x9, #0x12000
  [0x115F0] add x9, x9, #0x2c4
  [0x115F4] sub x9, x9, x15
  [0x115F8] str x9, [sp, #0x90]
  [0x115FC] adrp x16, #0x11000
  [0x11600] add x16, x16, #0
  [0x11604] ldr w7, [x16]
  [0x11608] add x16, x7, x15
  [0x1160C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11610] add x16, x9, x15
  [0x11614] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x11618] mov x9, x9
  [0x1161C] mov x7, x7
  [0x11620] add x9, x9, x15
  [0x11624] stp x3, x5, [sp, #-0x10]!
  [0x11628] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1162C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11630] blr x9 ;; misaligned with debug data
  [0x11634] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11638] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1163C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11640] mov x0, x0
  [0x11644] str x0, [sp, #0x98]
  [0x11648] adrp x16, #0x11000
  [0x1164C] add x16, x16, #0
  [0x11650] ldr w7, [x16]
  [0x11654] add x16, x7, x15
  [0x11658] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1165C] add x16, x9, x15
  [0x11660] ldr w9, [x16, #0x60] ;; misaligned with debug data
  [0x11664] mov x9, x9
  [0x11668] mov x7, x7
  [0x1166C] add x9, x9, x15
  [0x11670] stp x3, x5, [sp, #-0x10]!
  [0x11674] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11678] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1167C] blr x9 ;; misaligned with debug data
  [0x11680] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11684] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11688] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1168C] mov x0, x0
  [0x11690] mov x3, x3
  [0x11694] ldr x7, [sp, #0x88]
  [0x11698] mov x7, x7
  [0x1169C] ldr x6, [sp, #0x90]
  [0x116A0] mov x6, x6
  [0x116A4] ldr x2, [sp, #0x98]
  [0x116A8] mov x2, x2
  [0x116AC] mov x1, x0
  [0x116B0] add x3, x3, x15
  [0x116B4] stp x3, x5, [sp, #-0x10]!
  [0x116B8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x116BC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x116C0] blr x3 ;; misaligned with debug data
  [0x116C4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x116C8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x116CC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x116D0] mov x0, x0
  [0x116D4] add x8, x14, #8
  [0x116D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x116DC] mov x9, x8
  [0x116E0] str x9, [sp, #0x18]
  [0x116E4] mov x9, x8
  [0x116E8] b #0x116f4
  [0x116EC] mov x9, x14
  [0x116F0] sub x9, x9, x15 ;; misaligned with debug data
  [0x116F4] mov x9, x9
  [0x116F8] b #0x11704
  [0x116FC] mov x9, x14
  [0x11700] sub x9, x9, x15 ;; misaligned with debug data
  [0x11704] mov x9, x9
  [0x11708] b #0x117d8
  [0x1170C] add x16, x3, x15
  [0x11710] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x11714] mov x9, x9
  [0x11718] mov x8, x14
  [0x1171C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11720] cmp x9, x8
  [0x11724] b.eq #0x11760
  [0x11728] add x16, x3, x15
  [0x1172C] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x11730] movz x8, #0x8
  [0x11734] mov x9, x9
  [0x11738] and x9, x9, x8
  [0x1173C] movz x8, #0
  [0x11740] mov x1, x14
  [0x11744] sub x1, x1, x15 ;; misaligned with debug data
  [0x11748] cmp x9, x8
  [0x1174C] b.ne #0x1175c
  [0x11750] add x1, x14, #8
  [0x11754] sub x1, x1, x15 ;; misaligned with debug data
  [0x11758] mov x1, x1
  [0x1175C] mov x9, x1
  [0x11760] mov x8, x14
  [0x11764] sub x8, x8, x15 ;; misaligned with debug data
  [0x11768] cmp x9, x8
  [0x1176C] b.eq #0x117cc
  [0x11770] add x16, x3, x15
  [0x11774] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x11778] add x16, x7, x15
  [0x1177C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11780] add x16, x9, x15
  [0x11784] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x11788] mov x9, x9
  [0x1178C] mov x7, x7
  [0x11790] add x9, x9, x15
  [0x11794] stp x3, x5, [sp, #-0x10]!
  [0x11798] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1179C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x117A0] blr x9 ;; misaligned with debug data
  [0x117A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x117A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x117AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x117B0] mov x0, x0
  [0x117B4] mov x9, x11
  [0x117B8] movz x8, #0x1
  [0x117BC] add x9, x9, x8
  [0x117C0] mov x11, x9
  [0x117C4] mov x9, x9
  [0x117C8] b #0x117d4
  [0x117CC] mov x9, x14
  [0x117D0] sub x9, x9, x15 ;; misaligned with debug data
  [0x117D4] mov x9, x9
  [0x117D8] adrp x16, #0x11000
  [0x117DC] add x16, x16, #0
  [0x117E0] ldr w9, [x16]
  [0x117E4] add x16, x9, x15
  [0x117E8] ldrsw x9, [x16, #8] ;; misaligned with debug data
  [0x117EC] cmp x11, x9
  [0x117F0] b.lt #0x1180c
  [0x117F4] mov x0, x14
  [0x117F8] sub x0, x0, x15 ;; misaligned with debug data
  [0x117FC] mov x0, x0
  [0x11800] mov x0, x0
  [0x11804] b #0x118b4
  [0x11808] b #0x11814
  [0x1180C] mov x9, x14
  [0x11810] sub x9, x9, x15 ;; misaligned with debug data
  [0x11814] ldr x3, [sp, #0x20]
  [0x11818] mov x3, x3
  [0x1181C] movz x9, #0x1
  [0x11820] add x3, x3, x9
  [0x11824] mov x3, x3
  [0x11828] str x3, [sp, #0x20]
  [0x1182C] ldr x9, [sp, #0x10]
  [0x11830] ldr x8, [sp, #0x20]
  [0x11834] cmp x8, x9
  [0x11838] b.lt #0x112c0
  [0x1183C] mov x9, x14
  [0x11840] sub x9, x9, x15 ;; misaligned with debug data
  [0x11844] mov x9, x9
  [0x11848] b #0x11854
  [0x1184C] mov x9, x14
  [0x11850] sub x9, x9, x15 ;; misaligned with debug data
  [0x11854] mov x9, x9
  [0x11858] b #0x11864
  [0x1185C] mov x9, x14
  [0x11860] sub x9, x9, x15 ;; misaligned with debug data
  [0x11864] mov x9, x9
  [0x11868] b #0x11874
  [0x1186C] mov x9, x14
  [0x11870] sub x9, x9, x15 ;; misaligned with debug data
  [0x11874] mov x3, x10
  [0x11878] movz x9, #0x1
  [0x1187C] add x3, x3, x9
  [0x11880] mov x10, x3
  [0x11884] add x16, x5, x15
  [0x11888] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1188C] cmp x10, x9
  [0x11890] b.lt #0x10638
  [0x11894] mov x9, x14
  [0x11898] sub x9, x9, x15 ;; misaligned with debug data
  [0x1189C] mov x9, x9
  [0x118A0] b #0x118ac
  [0x118A4] mov x9, x14
  [0x118A8] sub x9, x9, x15 ;; misaligned with debug data
  [0x118AC] movz x0, #0
  [0x118B0] mov x0, x0
  [0x118B4] add sp, sp, #0xa0
  [0x118B8] ldr q24, [sp], #0x10
  [0x118BC] ldp x29, x30, [sp], #0x10
  [0x118C0] ret


[(method run-logic? process-drawable)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0x10
  [0x10010] mov x3, x7
  [0x10014] add x16, x3, x15
  [0x10018] ldr w9, [x16, #4] ;; misaligned with debug data
  [0x1001C] movz x8, #0x20
  [0x10020] mov x9, x9
  [0x10024] and x9, x9, x8
  [0x10028] movz x8, #0
  [0x1002C] mov x0, x14
  [0x10030] sub x0, x0, x15 ;; misaligned with debug data
  [0x10034] cmp x9, x8
  [0x10038] b.ne #0x10048
  [0x1003C] add x0, x14, #8
  [0x10040] sub x0, x0, x15 ;; misaligned with debug data
  [0x10044] mov x0, x0
  [0x10048] mov x0, x0
  [0x1004C] mov x9, x14
  [0x10050] sub x9, x9, x15 ;; misaligned with debug data
  [0x10054] cmp x0, x9
  [0x10058] b.ne #0x10254
  [0x1005C] adrp x16, #0x10000
  [0x10060] add x16, x16, #0
  [0x10064] ldr w9, [x16]
  [0x10068] add x16, x9, x15
  [0x1006C] ldr s24, [x16] ;; misaligned with debug data
  [0x10070] mov v24.16b, v24.16b
  [0x10074] add x16, x3, x15
  [0x10078] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1007C] add x16, x9, x15
  [0x10080] ldr s23, [x16] ;; misaligned with debug data
  [0x10084] fadd s24, s24, s23
  [0x10088] adrp x16, #0x10000
  [0x1008C] add x16, x16, #0
  [0x10090] ldr w5, [x16]
  [0x10094] movz x12, #0xc
  [0x10098] add x16, x3, x15
  [0x1009C] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x100A0] add x12, x12, x9
  [0x100A4] adrp x16, #0x10000
  [0x100A8] add x16, x16, #0
  [0x100AC] ldr w9, [x16]
  [0x100B0] mov x9, x9
  [0x100B4] add x9, x9, x15
  [0x100B8] stp x3, x5, [sp, #-0x10]!
  [0x100BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C4] blr x9 ;; misaligned with debug data
  [0x100C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] mov x0, x0
  [0x100D8] mov x5, x5
  [0x100DC] mov x7, x12
  [0x100E0] mov x6, x0
  [0x100E4] add x5, x5, x15
  [0x100E8] stp x3, x5, [sp, #-0x10]!
  [0x100EC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100F0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100F4] blr x5 ;; misaligned with debug data
  [0x100F8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100FC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10100] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10104] mov x0, x0
  [0x10108] fmov s23, w0
  [0x1010C] mov x0, x14
  [0x10110] sub x0, x0, x15 ;; misaligned with debug data
  [0x10114] fcmp s24, s23
  [0x10118] b.mi #0x10128
  [0x1011C] add x0, x14, #8
  [0x10120] sub x0, x0, x15 ;; misaligned with debug data
  [0x10124] mov x0, x0
  [0x10128] mov x0, x0
  [0x1012C] mov x9, x14
  [0x10130] sub x9, x9, x15 ;; misaligned with debug data
  [0x10134] cmp x0, x9
  [0x10138] b.ne #0x10250
  [0x1013C] add x16, x3, x15
  [0x10140] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10144] movz x8, #0
  [0x10148] mov x0, x14
  [0x1014C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10150] cmp x9, x8
  [0x10154] b.eq #0x10164
  [0x10158] add x0, x14, #8
  [0x1015C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10160] mov x0, x0
  [0x10164] mov x0, x0
  [0x10168] mov x9, x14
  [0x1016C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10170] cmp x0, x9
  [0x10174] b.eq #0x101bc
  [0x10178] add x16, x3, x15
  [0x1017C] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10180] add x16, x9, x15
  [0x10184] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10188] mov x9, x9
  [0x1018C] movz x8, #0x2c
  [0x10190] add x16, x3, x15
  [0x10194] ldr w1, [x16, #0x78] ;; misaligned with debug data
  [0x10198] add x8, x8, x1
  [0x1019C] mov x0, x14
  [0x101A0] sub x0, x0, x15 ;; misaligned with debug data
  [0x101A4] cmp x9, x8
  [0x101A8] b.eq #0x101b8
  [0x101AC] add x0, x14, #8
  [0x101B0] sub x0, x0, x15 ;; misaligned with debug data
  [0x101B4] mov x0, x0
  [0x101B8] mov x0, x0
  [0x101BC] mov x0, x0
  [0x101C0] mov x9, x14
  [0x101C4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101C8] cmp x0, x9
  [0x101CC] b.ne #0x10250
  [0x101D0] add x16, x3, x15
  [0x101D4] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x101D8] movz x8, #0
  [0x101DC] mov x0, x14
  [0x101E0] sub x0, x0, x15 ;; misaligned with debug data
  [0x101E4] cmp x9, x8
  [0x101E8] b.eq #0x101f8
  [0x101EC] add x0, x14, #8
  [0x101F0] sub x0, x0, x15 ;; misaligned with debug data
  [0x101F4] mov x0, x0
  [0x101F8] mov x0, x0
  [0x101FC] mov x9, x14
  [0x10200] sub x9, x9, x15 ;; misaligned with debug data
  [0x10204] cmp x0, x9
  [0x10208] b.eq #0x1024c
  [0x1020C] add x16, x3, x15
  [0x10210] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x10214] add x16, x9, x15
  [0x10218] ldrb w9, [x16] ;; misaligned with debug data
  [0x1021C] movz x8, #0x10
  [0x10220] mov x9, x9
  [0x10224] and x9, x9, x8
  [0x10228] movz x8, #0
  [0x1022C] mov x0, x14
  [0x10230] sub x0, x0, x15 ;; misaligned with debug data
  [0x10234] cmp x9, x8
  [0x10238] b.eq #0x10248
  [0x1023C] add x0, x14, #8
  [0x10240] sub x0, x0, x15 ;; misaligned with debug data
  [0x10244] mov x0, x0
  [0x10248] mov x0, x0
  [0x1024C] mov x0, x0
  [0x10250] mov x0, x0
  [0x10254] mov x0, x0
  [0x10258] add sp, sp, #0x10
  [0x1025C] ldr q24, [sp], #0x10
  [0x10260] ldp x29, x30, [sp], #0x10
  [0x10264] ret


[reset-cameras]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] adrp x16, #0x10000
  [0x10010] add x16, x16, #0
  [0x10014] ldr w7, [x16]
  [0x10018] add x16, x7, x15
  [0x1001C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10020] add x16, x9, x15
  [0x10024] ldr w9, [x16, #0x58] ;; misaligned with debug data
  [0x10028] mov x9, x9
  [0x1002C] mov x7, x7
  [0x10030] add x9, x9, x15
  [0x10034] stp x3, x5, [sp, #-0x10]!
  [0x10038] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1003C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10040] blr x9 ;; misaligned with debug data
  [0x10044] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10048] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1004C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10050] mov x0, x0
  [0x10054] movz x3, #0
  [0x10058] mov x5, x3
  [0x1005C] b #0x10180
  [0x10060] movz x9, #0xa30
  [0x10064] mul x9, x9, x5
  [0x10068] mov x9, x9
  [0x1006C] movz x8, #0x60
  [0x10070] adrp x16, #0x10000
  [0x10074] add x16, x16, #0
  [0x10078] ldr w1, [x16]
  [0x1007C] add x8, x8, x1
  [0x10080] add x9, x9, x8
  [0x10084] mov x9, x9
  [0x10088] add x16, x9, x15
  [0x1008C] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x10090] adrp x1, #0x10000
  [0x10094] add x1, x1, #0
  [0x10098] cmp x8, x1
  [0x1009C] b.ne #0x10168
  [0x100A0] add x16, x9, x15
  [0x100A4] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x100A8] add x16, x9, x15
  [0x100AC] ldr w3, [x16, #0x70] ;; misaligned with debug data
  [0x100B0] mov x12, x3
  [0x100B4] movz x9, #0
  [0x100B8] cmp x12, x9
  [0x100BC] b.eq #0x10158
  [0x100C0] movz x3, #0
  [0x100C4] mov x3, x3
  [0x100C8] b #0x10138
  [0x100CC] movz x9, #0xc
  [0x100D0] mov x8, x3
  [0x100D4] lsl x8, x8, #2
  [0x100D8] add x8, x8, x9
  [0x100DC] mov x8, x8
  [0x100E0] add x8, x8, x12
  [0x100E4] add x16, x8, x15
  [0x100E8] ldr w7, [x16] ;; misaligned with debug data
  [0x100EC] add x16, x7, x15
  [0x100F0] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100F4] add x16, x9, x15
  [0x100F8] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x100FC] mov x9, x9
  [0x10100] mov x7, x7
  [0x10104] add x9, x9, x15
  [0x10108] stp x3, x5, [sp, #-0x10]!
  [0x1010C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10110] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10114] blr x9 ;; misaligned with debug data
  [0x10118] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1011C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10120] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10124] mov x0, x0
  [0x10128] mov x3, x3
  [0x1012C] movz x9, #0x1
  [0x10130] add x3, x3, x9
  [0x10134] mov x3, x3
  [0x10138] add x16, x12, x15
  [0x1013C] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10140] cmp x3, x9
  [0x10144] b.lt #0x100cc
  [0x10148] mov x9, x14
  [0x1014C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10150] mov x9, x9
  [0x10154] b #0x10160
  [0x10158] mov x9, x14
  [0x1015C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10160] mov x9, x9
  [0x10164] b #0x10170
  [0x10168] mov x9, x14
  [0x1016C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10170] mov x3, x5
  [0x10174] movz x9, #0x1
  [0x10178] add x3, x3, x9
  [0x1017C] mov x5, x3
  [0x10180] adrp x16, #0x10000
  [0x10184] add x16, x16, #0
  [0x10188] ldr w9, [x16]
  [0x1018C] add x16, x9, x15
  [0x10190] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10194] cmp x5, x9
  [0x10198] b.lt #0x10060
  [0x1019C] mov x9, x14
  [0x101A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x101A4] movz x9, #0
  [0x101A8] add sp, sp, #0x10
  [0x101AC] ldp x29, x30, [sp], #0x10
  [0x101B0] ret


[reset-actors]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x9, x14
  [0x10014] sub x9, x9, x15 ;; misaligned with debug data
  [0x10018] mov x9, x9
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] str w9, [x16]
  [0x10028] mov x9, x5
  [0x1002C] adrp x8, #0x10000
  [0x10030] add x8, x8, #0
  [0x10034] mov x1, x14
  [0x10038] sub x1, x1, x15 ;; misaligned with debug data
  [0x1003C] cmp x9, x8
  [0x10040] b.ne #0x10050
  [0x10044] add x1, x14, #8
  [0x10048] sub x1, x1, x15 ;; misaligned with debug data
  [0x1004C] mov x1, x1
  [0x10050] mov x8, x1
  [0x10054] mov x1, x14
  [0x10058] sub x1, x1, x15 ;; misaligned with debug data
  [0x1005C] cmp x8, x1
  [0x10060] b.ne #0x1008c
  [0x10064] adrp x8, #0x10000
  [0x10068] add x8, x8, #0
  [0x1006C] mov x1, x14
  [0x10070] sub x1, x1, x15 ;; misaligned with debug data
  [0x10074] cmp x9, x8
  [0x10078] b.ne #0x10088
  [0x1007C] add x1, x14, #8
  [0x10080] sub x1, x1, x15 ;; misaligned with debug data
  [0x10084] mov x1, x1
  [0x10088] mov x8, x1
  [0x1008C] mov x1, x14
  [0x10090] sub x1, x1, x15 ;; misaligned with debug data
  [0x10094] cmp x8, x1
  [0x10098] b.eq #0x100a8
  [0x1009C] movz x3, #0x26f
  [0x100A0] mov x3, x3
  [0x100A4] b #0x100e8
  [0x100A8] adrp x8, #0x10000
  [0x100AC] add x8, x8, #0
  [0x100B0] cmp x9, x8
  [0x100B4] b.ne #0x100c4
  [0x100B8] movz x3, #0x26f
  [0x100BC] mov x3, x3
  [0x100C0] b #0x100e8
  [0x100C4] adrp x8, #0x10000
  [0x100C8] add x8, x8, #0
  [0x100CC] cmp x9, x8
  [0x100D0] b.ne #0x100e0
  [0x100D4] movz x3, #0x77f
  [0x100D8] mov x3, x3
  [0x100DC] b #0x100e8
  [0x100E0] movz x3, #0x67f
  [0x100E4] mov x3, x3
  [0x100E8] mov x12, x3
  [0x100EC] adrp x16, #0x10000
  [0x100F0] add x16, x16, #0
  [0x100F4] ldr w3, [x16]
  [0x100F8] mov x11, x3
  [0x100FC] movz x3, #0
  [0x10100] mov x10, x3
  [0x10104] b #0x10294
  [0x10108] movz x9, #0xa30
  [0x1010C] mul x9, x9, x10
  [0x10110] mov x9, x9
  [0x10114] movz x8, #0x60
  [0x10118] adrp x16, #0x10000
  [0x1011C] add x16, x16, #0
  [0x10120] ldr w1, [x16]
  [0x10124] add x8, x8, x1
  [0x10128] add x9, x9, x8
  [0x1012C] mov x9, x9
  [0x10130] add x16, x9, x15
  [0x10134] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x10138] adrp x1, #0x10000
  [0x1013C] add x1, x1, #0
  [0x10140] cmp x8, x1
  [0x10144] b.ne #0x1027c
  [0x10148] add x16, x9, x15
  [0x1014C] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10150] add x16, x9, x15
  [0x10154] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10158] add x16, x9, x15
  [0x1015C] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10160] mov x3, x3
  [0x10164] str x3, [sp]
  [0x10168] movz x3, #0
  [0x1016C] mov x3, x3
  [0x10170] str x3, [sp, #8]
  [0x10174] b #0x10254
  [0x10178] ldr x9, [sp, #8]
  [0x1017C] mov x8, x9
  [0x10180] lsl x8, x8, #6
  [0x10184] mov x8, x8
  [0x10188] movz x1, #0xc
  [0x1018C] ldr x9, [sp]
  [0x10190] add x1, x1, x9
  [0x10194] add x8, x8, x1
  [0x10198] add x16, x8, x15
  [0x1019C] ldr w3, [x16, #8] ;; misaligned with debug data
  [0x101A0] mov x3, x3
  [0x101A4] add x16, x3, x15
  [0x101A8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x101AC] add x16, x9, x15
  [0x101B0] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x101B4] mov x9, x9
  [0x101B8] mov x7, x3
  [0x101BC] add x9, x9, x15
  [0x101C0] stp x3, x5, [sp, #-0x10]!
  [0x101C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101CC] blr x9 ;; misaligned with debug data
  [0x101D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101DC] mov x0, x0
  [0x101E0] movz x7, #0x30
  [0x101E4] add x16, x3, x15
  [0x101E8] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x101EC] add x7, x7, x9
  [0x101F0] mov x2, x12
  [0x101F4] adrp x16, #0x10000
  [0x101F8] add x16, x16, #0
  [0x101FC] ldr w9, [x16]
  [0x10200] add x16, x9, x15
  [0x10204] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10208] mov x9, x9
  [0x1020C] mov x7, x7
  [0x10210] mov x6, x5
  [0x10214] mov x2, x2
  [0x10218] add x9, x9, x15
  [0x1021C] stp x3, x5, [sp, #-0x10]!
  [0x10220] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10224] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10228] blr x9 ;; misaligned with debug data
  [0x1022C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10230] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10234] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10238] mov x0, x0
  [0x1023C] ldr x3, [sp, #8]
  [0x10240] mov x3, x3
  [0x10244] movz x9, #0x1
  [0x10248] add x3, x3, x9
  [0x1024C] mov x3, x3
  [0x10250] str x3, [sp, #8]
  [0x10254] ldr x9, [sp]
  [0x10258] add x16, x9, x15
  [0x1025C] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10260] ldr x9, [sp, #8]
  [0x10264] cmp x9, x8
  [0x10268] b.lt #0x10178
  [0x1026C] mov x9, x14
  [0x10270] sub x9, x9, x15 ;; misaligned with debug data
  [0x10274] mov x9, x9
  [0x10278] b #0x10284
  [0x1027C] mov x9, x14
  [0x10280] sub x9, x9, x15 ;; misaligned with debug data
  [0x10284] mov x3, x10
  [0x10288] movz x9, #0x1
  [0x1028C] add x3, x3, x9
  [0x10290] mov x10, x3
  [0x10294] adrp x16, #0x10000
  [0x10298] add x16, x16, #0
  [0x1029C] ldr w9, [x16]
  [0x102A0] add x16, x9, x15
  [0x102A4] ldrsw x9, [x16] ;; misaligned with debug data
  [0x102A8] cmp x10, x9
  [0x102AC] b.lt #0x10108
  [0x102B0] mov x9, x14
  [0x102B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x102B8] add x16, x11, x15
  [0x102BC] ldr w3, [x16, #0x64] ;; misaligned with debug data
  [0x102C0] mov x10, x3
  [0x102C4] movz x3, #0
  [0x102C8] mov x3, x3
  [0x102CC] b #0x10344
  [0x102D0] mov x7, x3
  [0x102D4] lsl x7, x7, #4
  [0x102D8] mov x7, x7
  [0x102DC] movz x9, #0xc
  [0x102E0] add x9, x9, x10
  [0x102E4] add x7, x7, x9
  [0x102E8] mov x2, x12
  [0x102EC] adrp x16, #0x10000
  [0x102F0] add x16, x16, #0
  [0x102F4] ldr w9, [x16]
  [0x102F8] add x16, x9, x15
  [0x102FC] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10300] mov x9, x9
  [0x10304] mov x7, x7
  [0x10308] mov x6, x5
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
  [0x10334] mov x3, x3
  [0x10338] movz x9, #0x1
  [0x1033C] add x3, x3, x9
  [0x10340] mov x3, x3
  [0x10344] add x16, x10, x15
  [0x10348] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1034C] cmp x3, x9
  [0x10350] b.lt #0x102d0
  [0x10354] mov x9, x14
  [0x10358] sub x9, x9, x15 ;; misaligned with debug data
  [0x1035C] add x16, x10, x15
  [0x10360] ldrh w9, [x16, #0x24] ;; misaligned with debug data
  [0x10364] mov x9, x9
  [0x10368] movz x8, #0x100
  [0x1036C] orr x9, x9, x8
  [0x10370] add x16, x10, x15
  [0x10374] strh w9, [x16, #0x24] ;; misaligned with debug data
  [0x10378] add x16, x11, x15
  [0x1037C] ldr w3, [x16, #0x60] ;; misaligned with debug data
  [0x10380] mov x11, x3
  [0x10384] movz x3, #0
  [0x10388] mov x3, x3
  [0x1038C] b #0x10404
  [0x10390] mov x7, x3
  [0x10394] lsl x7, x7, #4
  [0x10398] mov x7, x7
  [0x1039C] movz x9, #0xc
  [0x103A0] add x9, x9, x11
  [0x103A4] add x7, x7, x9
  [0x103A8] mov x2, x12
  [0x103AC] adrp x16, #0x10000
  [0x103B0] add x16, x16, #0
  [0x103B4] ldr w9, [x16]
  [0x103B8] add x16, x9, x15
  [0x103BC] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x103C0] mov x9, x9
  [0x103C4] mov x7, x7
  [0x103C8] mov x6, x5
  [0x103CC] mov x2, x2
  [0x103D0] add x9, x9, x15
  [0x103D4] stp x3, x5, [sp, #-0x10]!
  [0x103D8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103DC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103E0] blr x9 ;; misaligned with debug data
  [0x103E4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103E8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103EC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103F0] mov x0, x0
  [0x103F4] mov x3, x3
  [0x103F8] movz x9, #0x1
  [0x103FC] add x3, x3, x9
  [0x10400] mov x3, x3
  [0x10404] add x16, x11, x15
  [0x10408] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1040C] cmp x3, x9
  [0x10410] b.lt #0x10390
  [0x10414] mov x9, x14
  [0x10418] sub x9, x9, x15 ;; misaligned with debug data
  [0x1041C] adrp x16, #0x10000
  [0x10420] add x16, x16, #0
  [0x10424] ldr w9, [x16]
  [0x10428] adrp x16, #0x10000
  [0x1042C] add x16, x16, #0
  [0x10430] ldr w7, [x16]
  [0x10434] adrp x6, #0x10000
  [0x10438] add x6, x6, #0x234
  [0x1043C] sub x6, x6, x15
  [0x10440] adrp x16, #0x10000
  [0x10444] add x16, x16, #0
  [0x10448] ldr w2, [x16]
  [0x1044C] mov x9, x9
  [0x10450] mov x7, x7
  [0x10454] mov x6, x6
  [0x10458] mov x2, x2
  [0x1045C] add x9, x9, x15
  [0x10460] stp x3, x5, [sp, #-0x10]!
  [0x10464] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10468] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1046C] blr x9 ;; misaligned with debug data
  [0x10470] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10474] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10478] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1047C] mov x0, x0
  [0x10480] adrp x9, #0x10000
  [0x10484] add x9, x9, #0
  [0x10488] cmp x5, x9
  [0x1048C] b.ne #0x104d0
  [0x10490] adrp x16, #0x10000
  [0x10494] add x16, x16, #0
  [0x10498] ldr w9, [x16]
  [0x1049C] mov x9, x9
  [0x104A0] mov x7, x5
  [0x104A4] add x9, x9, x15
  [0x104A8] stp x3, x5, [sp, #-0x10]!
  [0x104AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104B4] blr x9 ;; misaligned with debug data
  [0x104B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104C4] mov x3, x3
  [0x104C8] mov x3, x3
  [0x104CC] b #0x104d8
  [0x104D0] mov x3, x14
  [0x104D4] sub x3, x3, x15 ;; misaligned with debug data
  [0x104D8] movz x9, #0x3e8
  [0x104DC] adrp x16, #0x10000
  [0x104E0] add x16, x16, #0
  [0x104E4] ldr w8, [x16]
  [0x104E8] add x16, x8, x15
  [0x104EC] str w9, [x16, #8] ;; misaligned with debug data
  [0x104F0] movz x9, #0
  [0x104F4] add sp, sp, #0x10
  [0x104F8] ldp x29, x30, [sp], #0x10
  [0x104FC] ret


[anon-function-1]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] add x16, x7, x15
  [0x10014] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10018] add x16, x9, x15
  [0x1001C] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10020] mov x9, x9
  [0x10024] mov x7, x7
  [0x10028] add x9, x9, x15
  [0x1002C] stp x3, x5, [sp, #-0x10]!
  [0x10030] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10034] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10038] blr x9 ;; misaligned with debug data
  [0x1003C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10040] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10044] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10048] mov x3, x3
  [0x1004C] add sp, sp, #0x10
  [0x10050] ldp x29, x30, [sp], #0x10
  [0x10054] ret


[(method update-perm! entity-perm)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x2, x2
  [0x10014] adrp x9, #0x10000
  [0x10018] add x9, x9, #0
  [0x1001C] cmp x6, x9
  [0x10020] b.ne #0x1004c
  [0x10024] add x16, x7, x15
  [0x10028] ldrh w9, [x16, #8] ;; misaligned with debug data
  [0x1002C] mov x2, x2
  [0x10030] mvn x2, x2
  [0x10034] mov x9, x9
  [0x10038] and x9, x9, x2
  [0x1003C] add x16, x7, x15
  [0x10040] strh w9, [x16, #8] ;; misaligned with debug data
  [0x10044] mov x9, x9
  [0x10048] b #0x10128
  [0x1004C] add x16, x7, x15
  [0x10050] ldrb w9, [x16, #0xb] ;; misaligned with debug data
  [0x10054] movz x8, #0
  [0x10058] cmp x9, x8
  [0x1005C] b.eq #0x100c8
  [0x10060] add x16, x7, x15
  [0x10064] ldrh w9, [x16, #8] ;; misaligned with debug data
  [0x10068] add x16, x7, x15
  [0x1006C] ldrh w8, [x16, #8] ;; misaligned with debug data
  [0x10070] movz x1, #0x10
  [0x10074] mov x8, x8
  [0x10078] and x8, x8, x1
  [0x1007C] movz x1, #0
  [0x10080] cmp x8, x1
  [0x10084] b.eq #0x10094
  [0x10088] movz x8, #0x20c
  [0x1008C] mov x8, x8
  [0x10090] b #0x1009c
  [0x10094] movz x8, #0
  [0x10098] mov x8, x8
  [0x1009C] mov x8, x8
  [0x100A0] movz x1, #0x203
  [0x100A4] orr x8, x8, x1
  [0x100A8] mov x8, x8
  [0x100AC] mvn x8, x8
  [0x100B0] mov x9, x9
  [0x100B4] and x9, x9, x8
  [0x100B8] add x16, x7, x15
  [0x100BC] strh w9, [x16, #8] ;; misaligned with debug data
  [0x100C0] mov x9, x9
  [0x100C4] b #0x10128
  [0x100C8] add x16, x7, x15
  [0x100CC] ldrh w9, [x16, #8] ;; misaligned with debug data
  [0x100D0] mov x2, x2
  [0x100D4] add x16, x7, x15
  [0x100D8] ldrh w8, [x16, #8] ;; misaligned with debug data
  [0x100DC] movz x1, #0x10
  [0x100E0] mov x8, x8
  [0x100E4] and x8, x8, x1
  [0x100E8] movz x1, #0
  [0x100EC] cmp x8, x1
  [0x100F0] b.eq #0x10100
  [0x100F4] movz x8, #0x20c
  [0x100F8] mov x8, x8
  [0x100FC] b #0x10108
  [0x10100] movz x8, #0
  [0x10104] mov x8, x8
  [0x10108] orr x2, x2, x8
  [0x1010C] mov x2, x2
  [0x10110] mvn x2, x2
  [0x10114] mov x9, x9
  [0x10118] and x9, x9, x2
  [0x1011C] add x16, x7, x15
  [0x10120] strh w9, [x16, #8] ;; misaligned with debug data
  [0x10124] mov x9, x9
  [0x10128] add x16, x7, x15
  [0x1012C] ldrh w9, [x16, #8] ;; misaligned with debug data
  [0x10130] movz x8, #0x20
  [0x10134] mov x9, x9
  [0x10138] and x9, x9, x8
  [0x1013C] movz x8, #0
  [0x10140] cmp x9, x8
  [0x10144] b.ne #0x10164
  [0x10148] movz x9, #0
  [0x1014C] mov x9, x9
  [0x10150] add x16, x7, x15
  [0x10154] str x9, [x16] ;; misaligned with debug data
  [0x10158] movz x9, #0
  [0x1015C] mov x9, x9
  [0x10160] b #0x1016c
  [0x10164] mov x9, x14
  [0x10168] sub x9, x9, x15 ;; misaligned with debug data
  [0x1016C] mov x0, x7
  [0x10170] ldp x29, x30, [sp], #0x10
  [0x10174] ret


[entity-deactivate-handler]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] add x16, x6, x15
  [0x10014] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10018] add x16, x9, x15
  [0x1001C] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10020] cmp x7, x9
  [0x10024] b.ne #0x1007c
  [0x10028] add x16, x6, x15
  [0x1002C] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10030] add x16, x9, x15
  [0x10034] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10038] movz x8, #0xa
  [0x1003C] mov x8, x8
  [0x10040] mvn x8, x8
  [0x10044] mov x9, x9
  [0x10048] and x9, x9, x8
  [0x1004C] add x16, x6, x15
  [0x10050] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10054] add x16, x8, x15
  [0x10058] strh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1005C] mov x9, x14
  [0x10060] sub x9, x9, x15 ;; misaligned with debug data
  [0x10064] add x16, x6, x15
  [0x10068] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x1006C] add x16, x8, x15
  [0x10070] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x10074] mov x9, x9
  [0x10078] b #0x10084
  [0x1007C] mov x9, x14
  [0x10080] sub x9, x9, x15 ;; misaligned with debug data
  [0x10084] ldp x29, x30, [sp], #0x10
  [0x10088] ret


[(method deactivate-entities bsp-header)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x11, x7
  [0x10010] add x16, x11, x15
  [0x10014] ldr w3, [x16, #0x6c] ;; misaligned with debug data
  [0x10018] mov x5, x3
  [0x1001C] movz x9, #0
  [0x10020] cmp x5, x9
  [0x10024] b.eq #0x10110
  [0x10028] movz x3, #0
  [0x1002C] mov x12, x3
  [0x10030] b #0x100f0
  [0x10034] mov x9, x12
  [0x10038] lsl x9, x9, #5
  [0x1003C] mov x9, x9
  [0x10040] movz x8, #0x20
  [0x10044] add x8, x8, x5
  [0x10048] add x9, x9, x8
  [0x1004C] add x16, x9, x15
  [0x10050] ldr w3, [x16, #4] ;; misaligned with debug data
  [0x10054] mov x3, x3
  [0x10058] add x16, x3, x15
  [0x1005C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10060] add x16, x9, x15
  [0x10064] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10068] mov x9, x9
  [0x1006C] mov x7, x3
  [0x10070] add x9, x9, x15
  [0x10074] stp x3, x5, [sp, #-0x10]!
  [0x10078] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1007C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10080] blr x9 ;; misaligned with debug data
  [0x10084] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10088] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1008C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10090] mov x0, x0
  [0x10094] adrp x16, #0x10000
  [0x10098] add x16, x16, #0
  [0x1009C] ldr w6, [x16]
  [0x100A0] add x16, x3, x15
  [0x100A4] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100A8] add x16, x9, x15
  [0x100AC] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x100B0] mov x9, x9
  [0x100B4] mov x7, x3
  [0x100B8] mov x6, x6
  [0x100BC] add x9, x9, x15
  [0x100C0] stp x3, x5, [sp, #-0x10]!
  [0x100C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100CC] blr x9 ;; misaligned with debug data
  [0x100D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] mov x0, x0
  [0x100E0] mov x3, x12
  [0x100E4] movz x9, #0x1
  [0x100E8] add x3, x3, x9
  [0x100EC] mov x12, x3
  [0x100F0] add x16, x5, x15
  [0x100F4] ldrsh x9, [x16, #2] ;; misaligned with debug data
  [0x100F8] cmp x12, x9
  [0x100FC] b.lt #0x10034
  [0x10100] mov x9, x14
  [0x10104] sub x9, x9, x15 ;; misaligned with debug data
  [0x10108] mov x9, x9
  [0x1010C] b #0x10118
  [0x10110] mov x9, x14
  [0x10114] sub x9, x9, x15 ;; misaligned with debug data
  [0x10118] add x16, x11, x15
  [0x1011C] ldr w3, [x16, #0x70] ;; misaligned with debug data
  [0x10120] mov x5, x3
  [0x10124] movz x9, #0
  [0x10128] cmp x5, x9
  [0x1012C] b.eq #0x101c8
  [0x10130] movz x3, #0
  [0x10134] mov x3, x3
  [0x10138] b #0x101a8
  [0x1013C] movz x9, #0xc
  [0x10140] mov x8, x3
  [0x10144] lsl x8, x8, #2
  [0x10148] add x8, x8, x9
  [0x1014C] mov x8, x8
  [0x10150] add x8, x8, x5
  [0x10154] add x16, x8, x15
  [0x10158] ldr w7, [x16] ;; misaligned with debug data
  [0x1015C] add x16, x7, x15
  [0x10160] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10164] add x16, x9, x15
  [0x10168] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1016C] mov x9, x9
  [0x10170] mov x7, x7
  [0x10174] add x9, x9, x15
  [0x10178] stp x3, x5, [sp, #-0x10]!
  [0x1017C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10180] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10184] blr x9 ;; misaligned with debug data
  [0x10188] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1018C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10190] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10194] mov x0, x0
  [0x10198] mov x3, x3
  [0x1019C] movz x9, #0x1
  [0x101A0] add x3, x3, x9
  [0x101A4] mov x3, x3
  [0x101A8] add x16, x5, x15
  [0x101AC] ldrsw x9, [x16] ;; misaligned with debug data
  [0x101B0] cmp x3, x9
  [0x101B4] b.lt #0x1013c
  [0x101B8] mov x9, x14
  [0x101BC] sub x9, x9, x15 ;; misaligned with debug data
  [0x101C0] mov x9, x9
  [0x101C4] b #0x101d0
  [0x101C8] mov x9, x14
  [0x101CC] sub x9, x9, x15 ;; misaligned with debug data
  [0x101D0] adrp x16, #0x10000
  [0x101D4] add x16, x16, #0
  [0x101D8] ldr w9, [x16]
  [0x101DC] add x16, x9, x15
  [0x101E0] ldr w3, [x16, #0x10] ;; misaligned with debug data
  [0x101E4] add x16, x11, x15
  [0x101E8] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x101EC] add x16, x9, x15
  [0x101F0] ldr w5, [x16, #0x1c] ;; misaligned with debug data
  [0x101F4] add x16, x11, x15
  [0x101F8] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x101FC] add x16, x9, x15
  [0x10200] ldr w12, [x16, #0x28] ;; misaligned with debug data
  [0x10204] mov x10, x3
  [0x10208] mov x5, x5
  [0x1020C] mov x12, x12
  [0x10210] b #0x108d0
  [0x10214] mov x9, x10
  [0x10218] mov x8, x14
  [0x1021C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10220] cmp x9, x8
  [0x10224] b.eq #0x10240
  [0x10228] add x16, x9, x15
  [0x1022C] ldr w9, [x16] ;; misaligned with debug data
  [0x10230] add x16, x9, x15
  [0x10234] ldr w3, [x16, #0x18] ;; misaligned with debug data
  [0x10238] mov x3, x3
  [0x1023C] b #0x10248
  [0x10240] mov x3, x14
  [0x10244] sub x3, x3, x15 ;; misaligned with debug data
  [0x10248] mov x3, x3
  [0x1024C] mov x3, x3
  [0x10250] str x3, [sp]
  [0x10254] add x16, x10, x15
  [0x10258] ldr w9, [x16] ;; misaligned with debug data
  [0x1025C] add x16, x9, x15
  [0x10260] ldr w3, [x16, #0xc] ;; misaligned with debug data
  [0x10264] mov x10, x3
  [0x10268] ldr x9, [sp]
  [0x1026C] mov x8, x9
  [0x10270] add x16, x8, x15
  [0x10274] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x10278] mov x8, x14
  [0x1027C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10280] cmp x9, x8
  [0x10284] b.eq #0x1036c
  [0x10288] ldr x9, [sp]
  [0x1028C] mov x8, x9
  [0x10290] add x16, x8, x15
  [0x10294] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x10298] add x16, x9, x15
  [0x1029C] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x102A0] add x16, x9, x15
  [0x102A4] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x102A8] add x16, x11, x15
  [0x102AC] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x102B0] cmp x9, x8
  [0x102B4] b.ne #0x1035c
  [0x102B8] adrp x16, #0x10000
  [0x102BC] add x16, x16, #0
  [0x102C0] ldr w9, [x16]
  [0x102C4] add x7, x14, #8
  [0x102C8] sub x7, x7, x15 ;; misaligned with debug data
  [0x102CC] adrp x6, #0x14000
  [0x102D0] add x6, x6, #0x1a4
  [0x102D4] sub x6, x6, x15
  [0x102D8] mov x8, x9
  [0x102DC] mov x7, x7
  [0x102E0] mov x6, x6
  [0x102E4] ldr x9, [sp]
  [0x102E8] mov x2, x9
  [0x102EC] add x8, x8, x15
  [0x102F0] stp x3, x5, [sp, #-0x10]!
  [0x102F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102FC] blr x8 ;; misaligned with debug data
  [0x10300] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10304] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10308] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1030C] mov x0, x0
  [0x10310] ldr x9, [sp]
  [0x10314] add x16, x9, x15
  [0x10318] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x1031C] add x16, x8, x15
  [0x10320] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10324] mov x9, x9
  [0x10328] ldr x7, [sp]
  [0x1032C] mov x7, x7
  [0x10330] add x9, x9, x15
  [0x10334] stp x3, x5, [sp, #-0x10]!
  [0x10338] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1033C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10340] blr x9 ;; misaligned with debug data
  [0x10344] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10348] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1034C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10350] mov x3, x3
  [0x10354] mov x3, x3
  [0x10358] b #0x10364
  [0x1035C] mov x3, x14
  [0x10360] sub x3, x3, x15 ;; misaligned with debug data
  [0x10364] mov x3, x3
  [0x10368] b #0x108d0
  [0x1036C] ldr x9, [sp]
  [0x10370] add x16, x9, x15
  [0x10374] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x10378] adrp x16, #0x10000
  [0x1037C] add x16, x16, #0
  [0x10380] ldr w9, [x16]
  [0x10384] cmp x8, x9
  [0x10388] b.ne #0x104c0
  [0x1038C] ldr x9, [sp]
  [0x10390] mov x8, x9
  [0x10394] mov x8, x8
  [0x10398] add x16, x8, x15
  [0x1039C] ldr w9, [x16, #0x70] ;; misaligned with debug data
  [0x103A0] movz x1, #0
  [0x103A4] mov x2, x14
  [0x103A8] sub x2, x2, x15 ;; misaligned with debug data
  [0x103AC] cmp x9, x1
  [0x103B0] b.eq #0x103c0
  [0x103B4] add x2, x14, #8
  [0x103B8] sub x2, x2, x15 ;; misaligned with debug data
  [0x103BC] mov x2, x2
  [0x103C0] mov x9, x2
  [0x103C4] mov x1, x14
  [0x103C8] sub x1, x1, x15 ;; misaligned with debug data
  [0x103CC] cmp x9, x1
  [0x103D0] b.eq #0x10454
  [0x103D4] add x16, x8, x15
  [0x103D8] ldr w9, [x16, #0x70] ;; misaligned with debug data
  [0x103DC] add x16, x9, x15
  [0x103E0] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x103E4] mov x9, x9
  [0x103E8] mov x1, x5
  [0x103EC] mov x2, x14
  [0x103F0] sub x2, x2, x15 ;; misaligned with debug data
  [0x103F4] cmp x9, x1
  [0x103F8] b.lt #0x10408
  [0x103FC] add x2, x14, #8
  [0x10400] sub x2, x2, x15 ;; misaligned with debug data
  [0x10404] mov x2, x2
  [0x10408] mov x9, x2
  [0x1040C] mov x1, x14
  [0x10410] sub x1, x1, x15 ;; misaligned with debug data
  [0x10414] cmp x9, x1
  [0x10418] b.eq #0x10454
  [0x1041C] add x16, x8, x15
  [0x10420] ldr w9, [x16, #0x70] ;; misaligned with debug data
  [0x10424] add x16, x9, x15
  [0x10428] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x1042C] mov x9, x9
  [0x10430] mov x8, x12
  [0x10434] mov x1, x14
  [0x10438] sub x1, x1, x15 ;; misaligned with debug data
  [0x1043C] cmp x9, x8
  [0x10440] b.ge #0x10450
  [0x10444] add x1, x14, #8
  [0x10448] sub x1, x1, x15 ;; misaligned with debug data
  [0x1044C] mov x1, x1
  [0x10450] mov x9, x1
  [0x10454] mov x8, x14
  [0x10458] sub x8, x8, x15 ;; misaligned with debug data
  [0x1045C] cmp x9, x8
  [0x10460] b.eq #0x104b0
  [0x10464] ldr x9, [sp]
  [0x10468] add x16, x9, x15
  [0x1046C] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x10470] add x16, x8, x15
  [0x10474] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10478] mov x9, x9
  [0x1047C] ldr x7, [sp]
  [0x10480] mov x7, x7
  [0x10484] add x9, x9, x15
  [0x10488] stp x3, x5, [sp, #-0x10]!
  [0x1048C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10490] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10494] blr x9 ;; misaligned with debug data
  [0x10498] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1049C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104A4] mov x3, x3
  [0x104A8] mov x3, x3
  [0x104AC] b #0x104b8
  [0x104B0] mov x3, x14
  [0x104B4] sub x3, x3, x15 ;; misaligned with debug data
  [0x104B8] mov x3, x3
  [0x104BC] b #0x108d0
  [0x104C0] ldr x9, [sp]
  [0x104C4] mov x3, x9
  [0x104C8] movz x9, #0
  [0x104CC] mov x8, x14
  [0x104D0] sub x8, x8, x15 ;; misaligned with debug data
  [0x104D4] cmp x3, x9
  [0x104D8] b.eq #0x104e8
  [0x104DC] add x8, x14, #8
  [0x104E0] sub x8, x8, x15 ;; misaligned with debug data
  [0x104E4] mov x8, x8
  [0x104E8] mov x9, x8
  [0x104EC] mov x8, x14
  [0x104F0] sub x8, x8, x15 ;; misaligned with debug data
  [0x104F4] cmp x9, x8
  [0x104F8] b.eq #0x10550
  [0x104FC] adrp x16, #0x10000
  [0x10500] add x16, x16, #0
  [0x10504] ldr w9, [x16]
  [0x10508] add x16, x3, x15
  [0x1050C] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x10510] adrp x16, #0x10000
  [0x10514] add x16, x16, #0
  [0x10518] ldr w6, [x16]
  [0x1051C] mov x9, x9
  [0x10520] mov x7, x7
  [0x10524] mov x6, x6
  [0x10528] add x9, x9, x15
  [0x1052C] stp x3, x5, [sp, #-0x10]!
  [0x10530] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10534] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10538] blr x9 ;; misaligned with debug data
  [0x1053C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10540] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10544] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10548] mov x0, x0
  [0x1054C] mov x9, x0
  [0x10550] mov x8, x14
  [0x10554] sub x8, x8, x15 ;; misaligned with debug data
  [0x10558] cmp x9, x8
  [0x1055C] b.eq #0x10568
  [0x10560] mov x3, x3
  [0x10564] b #0x10570
  [0x10568] mov x3, x14
  [0x1056C] sub x3, x3, x15 ;; misaligned with debug data
  [0x10570] mov x3, x3
  [0x10574] mov x9, x14
  [0x10578] sub x9, x9, x15 ;; misaligned with debug data
  [0x1057C] cmp x3, x9
  [0x10580] b.eq #0x108c4
  [0x10584] mov x9, x3
  [0x10588] add x16, x9, x15
  [0x1058C] ldr w9, [x16, #0x94] ;; misaligned with debug data
  [0x10590] movz x8, #0
  [0x10594] mov x1, x14
  [0x10598] sub x1, x1, x15 ;; misaligned with debug data
  [0x1059C] cmp x9, x8
  [0x105A0] b.eq #0x105b0
  [0x105A4] add x1, x14, #8
  [0x105A8] sub x1, x1, x15 ;; misaligned with debug data
  [0x105AC] mov x1, x1
  [0x105B0] mov x9, x1
  [0x105B4] mov x8, x14
  [0x105B8] sub x8, x8, x15 ;; misaligned with debug data
  [0x105BC] cmp x9, x8
  [0x105C0] b.eq #0x1064c
  [0x105C4] mov x9, x3
  [0x105C8] add x16, x9, x15
  [0x105CC] ldr w9, [x16, #0x94] ;; misaligned with debug data
  [0x105D0] add x16, x9, x15
  [0x105D4] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x105D8] mov x9, x9
  [0x105DC] mov x8, x5
  [0x105E0] mov x1, x14
  [0x105E4] sub x1, x1, x15 ;; misaligned with debug data
  [0x105E8] cmp x9, x8
  [0x105EC] b.lt #0x105fc
  [0x105F0] add x1, x14, #8
  [0x105F4] sub x1, x1, x15 ;; misaligned with debug data
  [0x105F8] mov x1, x1
  [0x105FC] mov x9, x1
  [0x10600] mov x8, x14
  [0x10604] sub x8, x8, x15 ;; misaligned with debug data
  [0x10608] cmp x9, x8
  [0x1060C] b.eq #0x1064c
  [0x10610] mov x9, x3
  [0x10614] add x16, x9, x15
  [0x10618] ldr w9, [x16, #0x94] ;; misaligned with debug data
  [0x1061C] add x16, x9, x15
  [0x10620] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10624] mov x9, x9
  [0x10628] mov x8, x12
  [0x1062C] mov x1, x14
  [0x10630] sub x1, x1, x15 ;; misaligned with debug data
  [0x10634] cmp x9, x8
  [0x10638] b.ge #0x10648
  [0x1063C] add x1, x14, #8
  [0x10640] sub x1, x1, x15 ;; misaligned with debug data
  [0x10644] mov x1, x1
  [0x10648] mov x9, x1
  [0x1064C] mov x8, x14
  [0x10650] sub x8, x8, x15 ;; misaligned with debug data
  [0x10654] cmp x9, x8
  [0x10658] b.eq #0x1071c
  [0x1065C] adrp x16, #0x10000
  [0x10660] add x16, x16, #0
  [0x10664] ldr w9, [x16]
  [0x10668] add x7, x14, #8
  [0x1066C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10670] adrp x6, #0x14000
  [0x10674] add x6, x6, #0x1e4
  [0x10678] sub x6, x6, x15
  [0x1067C] mov x3, x3
  [0x10680] add x16, x3, x15
  [0x10684] ldr w8, [x16, #0x94] ;; misaligned with debug data
  [0x10688] mov x8, x8
  [0x1068C] add x16, x8, x15
  [0x10690] ldr w2, [x16, #0xc] ;; misaligned with debug data
  [0x10694] mov x8, x9
  [0x10698] mov x7, x7
  [0x1069C] mov x6, x6
  [0x106A0] mov x2, x2
  [0x106A4] ldr x9, [sp]
  [0x106A8] mov x1, x9
  [0x106AC] add x8, x8, x15
  [0x106B0] stp x3, x5, [sp, #-0x10]!
  [0x106B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106BC] blr x8 ;; misaligned with debug data
  [0x106C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x106CC] mov x0, x0
  [0x106D0] ldr x9, [sp]
  [0x106D4] add x16, x9, x15
  [0x106D8] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x106DC] add x16, x8, x15
  [0x106E0] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x106E4] mov x9, x9
  [0x106E8] ldr x7, [sp]
  [0x106EC] mov x7, x7
  [0x106F0] add x9, x9, x15
  [0x106F4] stp x3, x5, [sp, #-0x10]!
  [0x106F8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106FC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10700] blr x9 ;; misaligned with debug data
  [0x10704] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10708] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1070C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10710] mov x3, x3
  [0x10714] mov x3, x3
  [0x10718] b #0x108bc
  [0x1071C] mov x9, x3
  [0x10720] add x16, x9, x15
  [0x10724] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x10728] movz x8, #0
  [0x1072C] mov x1, x14
  [0x10730] sub x1, x1, x15 ;; misaligned with debug data
  [0x10734] cmp x9, x8
  [0x10738] b.eq #0x10748
  [0x1073C] add x1, x14, #8
  [0x10740] sub x1, x1, x15 ;; misaligned with debug data
  [0x10744] mov x1, x1
  [0x10748] mov x9, x1
  [0x1074C] mov x8, x14
  [0x10750] sub x8, x8, x15 ;; misaligned with debug data
  [0x10754] cmp x9, x8
  [0x10758] b.eq #0x107e4
  [0x1075C] mov x9, x3
  [0x10760] add x16, x9, x15
  [0x10764] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x10768] add x16, x9, x15
  [0x1076C] ldr w9, [x16, #4] ;; misaligned with debug data
  [0x10770] mov x9, x9
  [0x10774] mov x8, x5
  [0x10778] mov x1, x14
  [0x1077C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10780] cmp x9, x8
  [0x10784] b.lt #0x10794
  [0x10788] add x1, x14, #8
  [0x1078C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10790] mov x1, x1
  [0x10794] mov x9, x1
  [0x10798] mov x8, x14
  [0x1079C] sub x8, x8, x15 ;; misaligned with debug data
  [0x107A0] cmp x9, x8
  [0x107A4] b.eq #0x107e4
  [0x107A8] mov x9, x3
  [0x107AC] add x16, x9, x15
  [0x107B0] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x107B4] add x16, x9, x15
  [0x107B8] ldr w9, [x16, #4] ;; misaligned with debug data
  [0x107BC] mov x9, x9
  [0x107C0] mov x8, x12
  [0x107C4] mov x1, x14
  [0x107C8] sub x1, x1, x15 ;; misaligned with debug data
  [0x107CC] cmp x9, x8
  [0x107D0] b.ge #0x107e0
  [0x107D4] add x1, x14, #8
  [0x107D8] sub x1, x1, x15 ;; misaligned with debug data
  [0x107DC] mov x1, x1
  [0x107E0] mov x9, x1
  [0x107E4] mov x8, x14
  [0x107E8] sub x8, x8, x15 ;; misaligned with debug data
  [0x107EC] cmp x9, x8
  [0x107F0] b.eq #0x108b4
  [0x107F4] adrp x16, #0x10000
  [0x107F8] add x16, x16, #0
  [0x107FC] ldr w9, [x16]
  [0x10800] add x7, x14, #8
  [0x10804] sub x7, x7, x15 ;; misaligned with debug data
  [0x10808] adrp x6, #0x14000
  [0x1080C] add x6, x6, #0x234
  [0x10810] sub x6, x6, x15
  [0x10814] mov x3, x3
  [0x10818] add x16, x3, x15
  [0x1081C] ldr w8, [x16, #0x74] ;; misaligned with debug data
  [0x10820] mov x8, x8
  [0x10824] add x16, x8, x15
  [0x10828] ldr w2, [x16, #4] ;; misaligned with debug data
  [0x1082C] mov x8, x9
  [0x10830] mov x7, x7
  [0x10834] mov x6, x6
  [0x10838] mov x2, x2
  [0x1083C] ldr x9, [sp]
  [0x10840] mov x1, x9
  [0x10844] add x8, x8, x15
  [0x10848] stp x3, x5, [sp, #-0x10]!
  [0x1084C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10850] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10854] blr x8 ;; misaligned with debug data
  [0x10858] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1085C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10860] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10864] mov x0, x0
  [0x10868] ldr x9, [sp]
  [0x1086C] add x16, x9, x15
  [0x10870] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x10874] add x16, x8, x15
  [0x10878] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x1087C] mov x9, x9
  [0x10880] ldr x7, [sp]
  [0x10884] mov x7, x7
  [0x10888] add x9, x9, x15
  [0x1088C] stp x3, x5, [sp, #-0x10]!
  [0x10890] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10894] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10898] blr x9 ;; misaligned with debug data
  [0x1089C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108A0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108A4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108A8] mov x3, x3
  [0x108AC] mov x3, x3
  [0x108B0] b #0x108bc
  [0x108B4] mov x3, x14
  [0x108B8] sub x3, x3, x15 ;; misaligned with debug data
  [0x108BC] mov x3, x3
  [0x108C0] b #0x108cc
  [0x108C4] mov x3, x14
  [0x108C8] sub x3, x3, x15 ;; misaligned with debug data
  [0x108CC] mov x3, x3
  [0x108D0] mov x9, x14
  [0x108D4] sub x9, x9, x15 ;; misaligned with debug data
  [0x108D8] cmp x10, x9
  [0x108DC] b.ne #0x10214
  [0x108E0] mov x9, x14
  [0x108E4] sub x9, x9, x15 ;; misaligned with debug data
  [0x108E8] add sp, sp, #0x10
  [0x108EC] ldp x29, x30, [sp], #0x10
  [0x108F0] ret


[(method birth! entity-actor)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] add x16, x5, x15
  [0x10014] ldr w3, [x16, #0x34] ;; misaligned with debug data
  [0x10018] mov x3, x3
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] ldr w9, [x16]
  [0x10028] mov x9, x9
  [0x1002C] mov x7, x3
  [0x10030] add x9, x9, x15
  [0x10034] stp x3, x5, [sp, #-0x10]!
  [0x10038] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1003C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10040] blr x9 ;; misaligned with debug data
  [0x10044] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10048] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1004C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10050] mov x0, x0
  [0x10054] mov x0, x0
  [0x10058] adrp x16, #0x10000
  [0x1005C] add x16, x16, #0
  [0x10060] ldr w7, [x16]
  [0x10064] mov x9, x14
  [0x10068] sub x9, x9, x15 ;; misaligned with debug data
  [0x1006C] cmp x0, x9
  [0x10070] b.eq #0x10084
  [0x10074] add x16, x0, x15
  [0x10078] ldrsw x2, [x16, #0x10] ;; misaligned with debug data
  [0x1007C] mov x2, x2
  [0x10080] b #0x1008c
  [0x10084] movz x2, #0x4000
  [0x10088] mov x2, x2
  [0x1008C] add x16, x7, x15
  [0x10090] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10094] add x16, x9, x15
  [0x10098] ldr w9, [x16, #0x48] ;; misaligned with debug data
  [0x1009C] mov x9, x9
  [0x100A0] mov x7, x7
  [0x100A4] mov x6, x3
  [0x100A8] mov x2, x2
  [0x100AC] add x9, x9, x15
  [0x100B0] stp x3, x5, [sp, #-0x10]!
  [0x100B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100BC] blr x9 ;; misaligned with debug data
  [0x100C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100CC] mov x0, x0
  [0x100D0] mov x12, x0
  [0x100D4] mov x9, x14
  [0x100D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x100DC] cmp x12, x9
  [0x100E0] b.ne #0x10138
  [0x100E4] adrp x16, #0x10000
  [0x100E8] add x16, x16, #0
  [0x100EC] ldr w9, [x16]
  [0x100F0] movz x7, #0
  [0x100F4] adrp x6, #0x15000
  [0x100F8] add x6, x6, #0x44
  [0x100FC] sub x6, x6, x15
  [0x10100] mov x9, x9
  [0x10104] mov x7, x7
  [0x10108] mov x6, x6
  [0x1010C] add x9, x9, x15
  [0x10110] stp x3, x5, [sp, #-0x10]!
  [0x10114] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10118] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1011C] blr x9 ;; misaligned with debug data
  [0x10120] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10124] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10128] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1012C] mov x0, x0
  [0x10130] mov x0, x0
  [0x10134] b #0x10380
  [0x10138] add x16, x12, x15
  [0x1013C] stur w3, [x16, #-4] ;; misaligned with debug data
  [0x10140] mov x9, x3
  [0x10144] mov x8, x14
  [0x10148] sub x8, x8, x15 ;; misaligned with debug data
  [0x1014C] cmp x9, x8
  [0x10150] b.eq #0x1024c
  [0x10154] adrp x16, #0x10000
  [0x10158] add x16, x16, #0
  [0x1015C] ldr w9, [x16]
  [0x10160] adrp x16, #0x10000
  [0x10164] add x16, x16, #0
  [0x10168] ldr w6, [x16]
  [0x1016C] mov x2, x14
  [0x10170] sub x2, x2, x15 ;; misaligned with debug data
  [0x10174] mov x1, x14
  [0x10178] sub x1, x1, x15 ;; misaligned with debug data
  [0x1017C] movz x8, #0
  [0x10180] mov x9, x9
  [0x10184] mov x7, x3
  [0x10188] mov x6, x6
  [0x1018C] mov x2, x2
  [0x10190] mov x1, x1
  [0x10194] mov x8, x8
  [0x10198] add x9, x9, x15
  [0x1019C] stp x3, x5, [sp, #-0x10]!
  [0x101A0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A8] blr x9 ;; misaligned with debug data
  [0x101AC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101B0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101B4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101B8] mov x0, x0
  [0x101BC] mov x9, x0
  [0x101C0] mov x8, x14
  [0x101C4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101C8] cmp x9, x8
  [0x101CC] b.eq #0x1024c
  [0x101D0] adrp x16, #0x10000
  [0x101D4] add x16, x16, #0
  [0x101D8] ldr w9, [x16]
  [0x101DC] add x16, x12, x15
  [0x101E0] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x101E4] add x16, x8, x15
  [0x101E8] ldr w7, [x16, #0x3c] ;; misaligned with debug data
  [0x101EC] adrp x16, #0x10000
  [0x101F0] add x16, x16, #0
  [0x101F4] ldr w6, [x16]
  [0x101F8] mov x2, x14
  [0x101FC] sub x2, x2, x15 ;; misaligned with debug data
  [0x10200] mov x1, x14
  [0x10204] sub x1, x1, x15 ;; misaligned with debug data
  [0x10208] movz x8, #0
  [0x1020C] mov x9, x9
  [0x10210] mov x7, x7
  [0x10214] mov x6, x6
  [0x10218] mov x2, x2
  [0x1021C] mov x1, x1
  [0x10220] mov x8, x8
  [0x10224] add x9, x9, x15
  [0x10228] stp x3, x5, [sp, #-0x10]!
  [0x1022C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10230] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10234] blr x9 ;; misaligned with debug data
  [0x10238] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1023C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10240] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10244] mov x0, x0
  [0x10248] mov x9, x0
  [0x1024C] mov x8, x14
  [0x10250] sub x8, x8, x15 ;; misaligned with debug data
  [0x10254] cmp x9, x8
  [0x10258] b.eq #0x102a0
  [0x1025C] adrp x16, #0x10000
  [0x10260] add x16, x16, #0
  [0x10264] ldr w9, [x16]
  [0x10268] mov x9, x9
  [0x1026C] mov x7, x12
  [0x10270] mov x6, x5
  [0x10274] add x9, x9, x15
  [0x10278] stp x3, x5, [sp, #-0x10]!
  [0x1027C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10280] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10284] blr x9 ;; misaligned with debug data
  [0x10288] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1028C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10290] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10294] mov x3, x3
  [0x10298] mov x0, x3
  [0x1029C] b #0x10380
  [0x102A0] adrp x16, #0x10000
  [0x102A4] add x16, x16, #0
  [0x102A8] ldr w9, [x16]
  [0x102AC] mov x9, x9
  [0x102B0] mov x7, x12
  [0x102B4] mov x6, x5
  [0x102B8] add x9, x9, x15
  [0x102BC] stp x3, x5, [sp, #-0x10]!
  [0x102C0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102C8] blr x9 ;; misaligned with debug data
  [0x102CC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102D0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102D4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102D8] mov x0, x0
  [0x102DC] mov x9, x14
  [0x102E0] sub x9, x9, x15 ;; misaligned with debug data
  [0x102E4] cmp x0, x9
  [0x102E8] b.ne #0x10374
  [0x102EC] adrp x16, #0x10000
  [0x102F0] add x16, x16, #0
  [0x102F4] ldr w9, [x16]
  [0x102F8] movz x7, #0
  [0x102FC] adrp x6, #0x15000
  [0x10300] add x6, x6, #0x84
  [0x10304] sub x6, x6, x15
  [0x10308] mov x9, x9
  [0x1030C] mov x7, x7
  [0x10310] mov x6, x6
  [0x10314] mov x2, x3
  [0x10318] mov x1, x5
  [0x1031C] add x9, x9, x15
  [0x10320] stp x3, x5, [sp, #-0x10]!
  [0x10324] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10328] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1032C] blr x9 ;; misaligned with debug data
  [0x10330] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10334] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10338] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1033C] mov x0, x0
  [0x10340] add x16, x5, x15
  [0x10344] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10348] add x16, x9, x15
  [0x1034C] ldrh w0, [x16, #0x38] ;; misaligned with debug data
  [0x10350] mov x0, x0
  [0x10354] movz x9, #0x1
  [0x10358] orr x0, x0, x9
  [0x1035C] add x16, x5, x15
  [0x10360] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10364] add x16, x9, x15
  [0x10368] strh w0, [x16, #0x38] ;; misaligned with debug data
  [0x1036C] mov x0, x0
  [0x10370] b #0x1037c
  [0x10374] mov x0, x14
  [0x10378] sub x0, x0, x15 ;; misaligned with debug data
  [0x1037C] mov x0, x0
  [0x10380] mov x0, x5
  [0x10384] add sp, sp, #0x10
  [0x10388] ldp x29, x30, [sp], #0x10
  [0x1038C] ret


[init-entity]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] mov x5, x6
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] ldr w12, [x16]
  [0x10020] adrp x16, #0x10000
  [0x10024] add x16, x16, #0
  [0x10028] ldr w9, [x16]
  [0x1002C] add x16, x9, x15
  [0x10030] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x10034] adrp x6, #0x10000
  [0x10038] add x6, x6, #0
  [0x1003C] adrp x2, #0x10000
  [0x10040] add x2, x2, #0
  [0x10044] adrp x16, #0x15000
  [0x10048] ldr s23, [x16, #0x34]
  [0x1004C] mov x8, x14
  [0x10050] sub x8, x8, x15 ;; misaligned with debug data
  [0x10054] mov x8, x8
  [0x10058] mov x9, x14
  [0x1005C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10060] mov x9, x9
  [0x10064] adrp x16, #0x10000
  [0x10068] add x16, x16, #0
  [0x1006C] ldr w10, [x16]
  [0x10070] mov x11, x1
  [0x10074] mov x7, x5
  [0x10078] mov x6, x6
  [0x1007C] mov x2, x2
  [0x10080] fmov w1, s23
  [0x10084] sxtw x1, w1
  [0x10088] mov x8, x8
  [0x1008C] mov x9, x9
  [0x10090] mov x10, x10
  [0x10094] add x11, x11, x15
  [0x10098] stp x3, x5, [sp, #-0x10]!
  [0x1009C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A4] blr x11 ;; misaligned with debug data
  [0x100A8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100AC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100B0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100B4] mov x0, x0
  [0x100B8] mov x0, x0
  [0x100BC] movz x1, #0x4000
  [0x100C0] movk x1, #0x7000, lsl #16
  [0x100C4] mov x1, x1
  [0x100C8] add x16, x3, x15
  [0x100CC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100D0] add x16, x9, x15
  [0x100D4] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x100D8] mov x9, x9
  [0x100DC] mov x7, x3
  [0x100E0] mov x6, x12
  [0x100E4] mov x2, x0
  [0x100E8] mov x1, x1
  [0x100EC] add x9, x9, x15
  [0x100F0] stp x3, x5, [sp, #-0x10]!
  [0x100F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100FC] blr x9 ;; misaligned with debug data
  [0x10100] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10104] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10108] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1010C] mov x0, x0
  [0x10110] add x16, x3, x15
  [0x10114] str w5, [x16, #0x30] ;; misaligned with debug data
  [0x10118] add x16, x5, x15
  [0x1011C] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10120] add x16, x9, x15
  [0x10124] str w3, [x16, #0xc] ;; misaligned with debug data
  [0x10128] adrp x16, #0x10000
  [0x1012C] add x16, x16, #0
  [0x10130] ldr w9, [x16]
  [0x10134] mov x9, x9
  [0x10138] add x16, x3, x15
  [0x1013C] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x10140] add x16, x8, x15
  [0x10144] ldr w6, [x16, #0x3c] ;; misaligned with debug data
  [0x10148] mov x9, x9
  [0x1014C] mov x7, x3
  [0x10150] mov x6, x6
  [0x10154] mov x2, x3
  [0x10158] mov x1, x5
  [0x1015C] add x9, x9, x15
  [0x10160] stp x3, x5, [sp, #-0x10]!
  [0x10164] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10168] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1016C] blr x9 ;; misaligned with debug data
  [0x10170] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10174] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10178] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1017C] mov x0, x0
  [0x10180] add sp, sp, #0x10
  [0x10184] ldp x29, x30, [sp], #0x10
  [0x10188] ret


[(method birth? entity-links)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] add x16, x7, x15
  [0x10018] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1001C] movz x8, #0x5
  [0x10020] mov x9, x9
  [0x10024] and x9, x9, x8
  [0x10028] movz x8, #0
  [0x1002C] mov x0, x14
  [0x10030] sub x0, x0, x15 ;; misaligned with debug data
  [0x10034] cmp x9, x8
  [0x10038] b.ne #0x10048
  [0x1003C] add x0, x14, #8
  [0x10040] sub x0, x0, x15 ;; misaligned with debug data
  [0x10044] mov x0, x0
  [0x10048] mov x0, x0
  [0x1004C] mov x9, x14
  [0x10050] sub x9, x9, x15 ;; misaligned with debug data
  [0x10054] cmp x0, x9
  [0x10058] b.eq #0x100d8
  [0x1005C] adrp x16, #0x10000
  [0x10060] add x16, x16, #0
  [0x10064] ldr w9, [x16]
  [0x10068] movz x8, #0x20
  [0x1006C] add x8, x8, x7
  [0x10070] mov x9, x9
  [0x10074] mov x7, x8
  [0x10078] mov x6, x6
  [0x1007C] add x9, x9, x15
  [0x10080] stp x3, x5, [sp, #-0x10]!
  [0x10084] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10088] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1008C] blr x9 ;; misaligned with debug data
  [0x10090] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10094] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10098] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1009C] mov x0, x0
  [0x100A0] fmov s23, w0
  [0x100A4] adrp x16, #0x10000
  [0x100A8] add x16, x16, #0
  [0x100AC] ldr w9, [x16]
  [0x100B0] add x16, x9, x15
  [0x100B4] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x100B8] mov x0, x14
  [0x100BC] sub x0, x0, x15 ;; misaligned with debug data
  [0x100C0] fcmp s23, s22
  [0x100C4] b.ge #0x100d4
  [0x100C8] add x0, x14, #8
  [0x100CC] sub x0, x0, x15 ;; misaligned with debug data
  [0x100D0] mov x0, x0
  [0x100D4] mov x0, x0
  [0x100D8] mov x0, x0
  [0x100DC] add sp, sp, #0x10
  [0x100E0] ldp x29, x30, [sp], #0x10
  [0x100E4] ret


[(method kill! entity-camera)]
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
  [0x10028] ldr w9, [x16, #0x5c] ;; misaligned with debug data
  [0x1002C] mov x9, x9
  [0x10030] mov x7, x7
  [0x10034] mov x6, x3
  [0x10038] add x9, x9, x15
  [0x1003C] stp x3, x5, [sp, #-0x10]!
  [0x10040] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10044] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10048] blr x9 ;; misaligned with debug data
  [0x1004C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10050] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10054] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10058] mov x0, x0
  [0x1005C] mov x0, x3
  [0x10060] add sp, sp, #0x10
  [0x10064] ldp x29, x30, [sp], #0x10
  [0x10068] ret


[(method birth! entity-camera)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w7, [x16]
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] ldr w6, [x16]
  [0x10028] adrp x16, #0x10000
  [0x1002C] add x16, x16, #0
  [0x10030] ldr w2, [x16]
  [0x10034] mov x8, x14
  [0x10038] sub x8, x8, x15 ;; misaligned with debug data
  [0x1003C] mov x9, x14
  [0x10040] sub x9, x9, x15 ;; misaligned with debug data
  [0x10044] add x16, x7, x15
  [0x10048] ldur w1, [x16, #-4] ;; misaligned with debug data
  [0x1004C] add x16, x1, x15
  [0x10050] ldr w1, [x16, #0x4c] ;; misaligned with debug data
  [0x10054] mov x5, x1
  [0x10058] mov x7, x7
  [0x1005C] mov x6, x6
  [0x10060] mov x2, x2
  [0x10064] mov x1, x3
  [0x10068] mov x8, x8
  [0x1006C] mov x9, x9
  [0x10070] add x5, x5, x15
  [0x10074] stp x3, x5, [sp, #-0x10]!
  [0x10078] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1007C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10080] blr x5 ;; misaligned with debug data
  [0x10084] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10088] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1008C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10090] mov x0, x0
  [0x10094] mov x0, x3
  [0x10098] add sp, sp, #0x10
  [0x1009C] ldp x29, x30, [sp], #0x10
  [0x100A0] ret


[process-drawable-from-entity!]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] mov x6, x6
  [0x10014] add x16, x3, x15
  [0x10018] ldr w9, [x16, #4] ;; misaligned with debug data
  [0x1001C] mov x9, x9
  [0x10020] movz x8, #0x20
  [0x10024] orr x9, x9, x8
  [0x10028] add x16, x3, x15
  [0x1002C] str w9, [x16, #4] ;; misaligned with debug data
  [0x10030] add x16, x6, x15
  [0x10034] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10038] add x16, x9, x15
  [0x1003C] ldr q23, [x16, #0x20] ;; misaligned with debug data
  [0x10040] mov v23.16b, v23.16b
  [0x10044] add x16, x3, x15
  [0x10048] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1004C] add x16, x9, x15
  [0x10050] stur q23, [x16, #0xc] ;; misaligned with debug data
  [0x10054] adrp x16, #0x10000
  [0x10058] add x16, x16, #0
  [0x1005C] ldr w9, [x16]
  [0x10060] movz x7, #0x1c
  [0x10064] add x16, x3, x15
  [0x10068] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x1006C] add x7, x7, x8
  [0x10070] movz x8, #0x3c
  [0x10074] add x8, x8, x6
  [0x10078] mov x9, x9
  [0x1007C] mov x7, x7
  [0x10080] mov x6, x8
  [0x10084] add x9, x9, x15
  [0x10088] stp x3, x5, [sp, #-0x10]!
  [0x1008C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10090] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10094] blr x9 ;; misaligned with debug data
  [0x10098] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1009C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100A0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100A4] mov x0, x0
  [0x100A8] adrp x16, #0x10000
  [0x100AC] add x16, x16, #0
  [0x100B0] ldr w9, [x16]
  [0x100B4] movz x7, #0x2c
  [0x100B8] add x16, x3, x15
  [0x100BC] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x100C0] add x7, x7, x8
  [0x100C4] mov x9, x9
  [0x100C8] mov x7, x7
  [0x100CC] add x9, x9, x15
  [0x100D0] stp x3, x5, [sp, #-0x10]!
  [0x100D4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100DC] blr x9 ;; misaligned with debug data
  [0x100E0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100E4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100E8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100EC] mov x0, x0
  [0x100F0] add sp, sp, #0x10
  [0x100F4] ldp x29, x30, [sp], #0x10
  [0x100F8] ret


[expand-vis-box-with-point]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x3, x6
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] ldr w9, [x16]
  [0x10020] add x16, x9, x15
  [0x10024] ldr w1, [x16, #0x34] ;; misaligned with debug data
  [0x10028] adrp x6, #0x10000
  [0x1002C] add x6, x6, #0
  [0x10030] adrp x2, #0x10000
  [0x10034] add x2, x2, #0
  [0x10038] adrp x16, #0x16000
  [0x1003C] ldr s23, [x16, #0xf78]
  [0x10040] mov x8, x14
  [0x10044] sub x8, x8, x15 ;; misaligned with debug data
  [0x10048] mov x8, x8
  [0x1004C] mov x9, x14
  [0x10050] sub x9, x9, x15 ;; misaligned with debug data
  [0x10054] mov x9, x9
  [0x10058] adrp x16, #0x10000
  [0x1005C] add x16, x16, #0
  [0x10060] ldr w10, [x16]
  [0x10064] mov x5, x1
  [0x10068] mov x7, x7
  [0x1006C] mov x6, x6
  [0x10070] mov x2, x2
  [0x10074] fmov w1, s23
  [0x10078] sxtw x1, w1
  [0x1007C] mov x8, x8
  [0x10080] mov x9, x9
  [0x10084] mov x10, x10
  [0x10088] add x5, x5, x15
  [0x1008C] stp x3, x5, [sp, #-0x10]!
  [0x10090] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10094] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10098] blr x5 ;; misaligned with debug data
  [0x1009C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100A0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100A4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100A8] mov x0, x0
  [0x100AC] mov x0, x0
  [0x100B0] mov x0, x0
  [0x100B4] mov x9, x14
  [0x100B8] sub x9, x9, x15 ;; misaligned with debug data
  [0x100BC] cmp x0, x9
  [0x100C0] b.eq #0x101a4
  [0x100C4] mov x9, x0
  [0x100C8] movz x8, #0x10
  [0x100CC] add x8, x8, x0
  [0x100D0] mov x9, x9
  [0x100D4] mov x8, x8
  [0x100D8] add x16, x9, x15
  [0x100DC] ldr s23, [x16] ;; misaligned with debug data
  [0x100E0] mov v23.16b, v23.16b
  [0x100E4] add x16, x3, x15
  [0x100E8] ldr s22, [x16] ;; misaligned with debug data
  [0x100EC] fmin s23, s23, s22
  [0x100F0] add x16, x9, x15
  [0x100F4] str s23, [x16] ;; misaligned with debug data
  [0x100F8] add x16, x9, x15
  [0x100FC] ldr s23, [x16, #4] ;; misaligned with debug data
  [0x10100] mov v23.16b, v23.16b
  [0x10104] add x16, x3, x15
  [0x10108] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x1010C] fmin s23, s23, s22
  [0x10110] add x16, x9, x15
  [0x10114] str s23, [x16, #4] ;; misaligned with debug data
  [0x10118] add x16, x9, x15
  [0x1011C] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x10120] mov v23.16b, v23.16b
  [0x10124] add x16, x3, x15
  [0x10128] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x1012C] fmin s23, s23, s22
  [0x10130] add x16, x9, x15
  [0x10134] str s23, [x16, #8] ;; misaligned with debug data
  [0x10138] add x16, x8, x15
  [0x1013C] ldr s23, [x16] ;; misaligned with debug data
  [0x10140] mov v23.16b, v23.16b
  [0x10144] add x16, x3, x15
  [0x10148] ldr s22, [x16] ;; misaligned with debug data
  [0x1014C] fmax s23, s23, s22
  [0x10150] add x16, x8, x15
  [0x10154] str s23, [x16] ;; misaligned with debug data
  [0x10158] add x16, x8, x15
  [0x1015C] ldr s23, [x16, #4] ;; misaligned with debug data
  [0x10160] mov v23.16b, v23.16b
  [0x10164] add x16, x3, x15
  [0x10168] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x1016C] fmax s23, s23, s22
  [0x10170] add x16, x8, x15
  [0x10174] str s23, [x16, #4] ;; misaligned with debug data
  [0x10178] add x16, x8, x15
  [0x1017C] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x10180] mov v23.16b, v23.16b
  [0x10184] add x16, x3, x15
  [0x10188] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x1018C] fmax s23, s23, s22
  [0x10190] add x16, x8, x15
  [0x10194] str s23, [x16, #8] ;; misaligned with debug data
  [0x10198] fmov w9, s23
  [0x1019C] sxtw x9, w9
  [0x101A0] b #0x101ac
  [0x101A4] mov x9, x14
  [0x101A8] sub x9, x9, x15 ;; misaligned with debug data
  [0x101AC] movz x9, #0
  [0x101B0] add sp, sp, #0x10
  [0x101B4] ldp x29, x30, [sp], #0x10
  [0x101B8] ret


[top-level]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] add x9, x14, #8
  [0x10010] sub x9, x9, x15 ;; misaligned with debug data
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] str w9, [x16]
  [0x10020] add x9, x14, #8
  [0x10024] sub x9, x9, x15 ;; misaligned with debug data
  [0x10028] adrp x16, #0x10000
  [0x1002C] add x16, x16, #0
  [0x10030] str w9, [x16]
  [0x10034] add x9, x14, #8
  [0x10038] sub x9, x9, x15 ;; misaligned with debug data
  [0x1003C] adrp x16, #0x10000
  [0x10040] add x16, x16, #0
  [0x10044] str w9, [x16]
  [0x10048] adrp x16, #0x10000
  [0x1004C] add x16, x16, #0
  [0x10050] ldr w7, [x16]
  [0x10054] movz x6, #0x8
  [0x10058] adrp x2, #0x10000
  [0x1005C] add x2, x2, #0
  [0x10060] sub x2, x2, x15
  [0x10064] adrp x16, #0x10000
  [0x10068] add x16, x16, #0
  [0x1006C] ldr w9, [x16]
  [0x10070] mov x9, x9
  [0x10074] mov x7, x7
  [0x10078] mov x6, x6
  [0x1007C] mov x2, x2
  [0x10080] add x9, x9, x15
  [0x10084] stp x3, x5, [sp, #-0x10]!
  [0x10088] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1008C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10090] blr x9 ;; misaligned with debug data
  [0x10094] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10098] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1009C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100A0] mov x3, x3
  [0x100A4] adrp x16, #0x10000
  [0x100A8] add x16, x16, #0
  [0x100AC] ldr w7, [x16]
  [0x100B0] movz x6, #0x8
  [0x100B4] adrp x2, #0x10000
  [0x100B8] add x2, x2, #0
  [0x100BC] sub x2, x2, x15
  [0x100C0] adrp x16, #0x10000
  [0x100C4] add x16, x16, #0
  [0x100C8] ldr w9, [x16]
  [0x100CC] mov x9, x9
  [0x100D0] mov x7, x7
  [0x100D4] mov x6, x6
  [0x100D8] mov x2, x2
  [0x100DC] add x9, x9, x15
  [0x100E0] stp x3, x5, [sp, #-0x10]!
  [0x100E4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100E8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100EC] blr x9 ;; misaligned with debug data
  [0x100F0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100F4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100F8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100FC] mov x3, x3
  [0x10100] adrp x16, #0x10000
  [0x10104] add x16, x16, #0
  [0x10108] ldr w7, [x16]
  [0x1010C] movz x6, #0x2
  [0x10110] adrp x2, #0x10000
  [0x10114] add x2, x2, #0
  [0x10118] sub x2, x2, x15
  [0x1011C] adrp x16, #0x10000
  [0x10120] add x16, x16, #0
  [0x10124] ldr w9, [x16]
  [0x10128] mov x9, x9
  [0x1012C] mov x7, x7
  [0x10130] mov x6, x6
  [0x10134] mov x2, x2
  [0x10138] add x9, x9, x15
  [0x1013C] stp x3, x5, [sp, #-0x10]!
  [0x10140] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10144] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10148] blr x9 ;; misaligned with debug data
  [0x1014C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10150] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10154] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10158] mov x3, x3
  [0x1015C] adrp x16, #0x10000
  [0x10160] add x16, x16, #0
  [0x10164] ldr w7, [x16]
  [0x10168] movz x6, #0x2
  [0x1016C] adrp x2, #0x10000
  [0x10170] add x2, x2, #0
  [0x10174] sub x2, x2, x15
  [0x10178] adrp x16, #0x10000
  [0x1017C] add x16, x16, #0
  [0x10180] ldr w9, [x16]
  [0x10184] mov x9, x9
  [0x10188] mov x7, x7
  [0x1018C] mov x6, x6
  [0x10190] mov x2, x2
  [0x10194] add x9, x9, x15
  [0x10198] stp x3, x5, [sp, #-0x10]!
  [0x1019C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A4] blr x9 ;; misaligned with debug data
  [0x101A8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101AC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101B0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101B4] mov x3, x3
  [0x101B8] adrp x16, #0x10000
  [0x101BC] add x16, x16, #0
  [0x101C0] ldr w7, [x16]
  [0x101C4] movz x6, #0x16
  [0x101C8] adrp x2, #0x10000
  [0x101CC] add x2, x2, #0
  [0x101D0] sub x2, x2, x15
  [0x101D4] adrp x16, #0x10000
  [0x101D8] add x16, x16, #0
  [0x101DC] ldr w9, [x16]
  [0x101E0] mov x9, x9
  [0x101E4] mov x7, x7
  [0x101E8] mov x6, x6
  [0x101EC] mov x2, x2
  [0x101F0] add x9, x9, x15
  [0x101F4] stp x3, x5, [sp, #-0x10]!
  [0x101F8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101FC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10200] blr x9 ;; misaligned with debug data
  [0x10204] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10208] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1020C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10210] mov x3, x3
  [0x10214] adrp x16, #0x10000
  [0x10218] add x16, x16, #0
  [0x1021C] ldr w7, [x16]
  [0x10220] movz x6, #0x17
  [0x10224] adrp x2, #0x10000
  [0x10228] add x2, x2, #0
  [0x1022C] sub x2, x2, x15
  [0x10230] adrp x16, #0x10000
  [0x10234] add x16, x16, #0
  [0x10238] ldr w9, [x16]
  [0x1023C] mov x9, x9
  [0x10240] mov x7, x7
  [0x10244] mov x6, x6
  [0x10248] mov x2, x2
  [0x1024C] add x9, x9, x15
  [0x10250] stp x3, x5, [sp, #-0x10]!
  [0x10254] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10258] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1025C] blr x9 ;; misaligned with debug data
  [0x10260] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10264] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10268] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1026C] mov x3, x3
  [0x10270] adrp x16, #0x10000
  [0x10274] add x16, x16, #0
  [0x10278] ldr w7, [x16]
  [0x1027C] movz x6, #0x2
  [0x10280] adrp x2, #0x10000
  [0x10284] add x2, x2, #0
  [0x10288] sub x2, x2, x15
  [0x1028C] adrp x16, #0x10000
  [0x10290] add x16, x16, #0
  [0x10294] ldr w9, [x16]
  [0x10298] mov x9, x9
  [0x1029C] mov x7, x7
  [0x102A0] mov x6, x6
  [0x102A4] mov x2, x2
  [0x102A8] add x9, x9, x15
  [0x102AC] stp x3, x5, [sp, #-0x10]!
  [0x102B0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102B4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102B8] blr x9 ;; misaligned with debug data
  [0x102BC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102C0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102C4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102C8] mov x3, x3
  [0x102CC] adrp x16, #0x10000
  [0x102D0] add x16, x16, #0
  [0x102D4] ldr w7, [x16]
  [0x102D8] movz x6, #0x1a
  [0x102DC] adrp x2, #0x10000
  [0x102E0] add x2, x2, #0
  [0x102E4] sub x2, x2, x15
  [0x102E8] adrp x16, #0x10000
  [0x102EC] add x16, x16, #0
  [0x102F0] ldr w9, [x16]
  [0x102F4] mov x9, x9
  [0x102F8] mov x7, x7
  [0x102FC] mov x6, x6
  [0x10300] mov x2, x2
  [0x10304] add x9, x9, x15
  [0x10308] stp x3, x5, [sp, #-0x10]!
  [0x1030C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10310] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10314] blr x9 ;; misaligned with debug data
  [0x10318] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1031C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10320] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10324] mov x3, x3
  [0x10328] adrp x9, #0x10000
  [0x1032C] add x9, x9, #0
  [0x10330] sub x9, x9, x15
  [0x10334] adrp x16, #0x10000
  [0x10338] add x16, x16, #0
  [0x1033C] str w9, [x16]
  [0x10340] adrp x9, #0x10000
  [0x10344] add x9, x9, #0
  [0x10348] sub x9, x9, x15
  [0x1034C] adrp x16, #0x10000
  [0x10350] add x16, x16, #0
  [0x10354] str w9, [x16]
  [0x10358] adrp x9, #0x10000
  [0x1035C] add x9, x9, #0
  [0x10360] sub x9, x9, x15
  [0x10364] adrp x16, #0x10000
  [0x10368] add x16, x16, #0
  [0x1036C] str w9, [x16]
  [0x10370] adrp x9, #0x10000
  [0x10374] add x9, x9, #0
  [0x10378] sub x9, x9, x15
  [0x1037C] adrp x16, #0x10000
  [0x10380] add x16, x16, #0
  [0x10384] str w9, [x16]
  [0x10388] adrp x9, #0x10000
  [0x1038C] add x9, x9, #0
  [0x10390] sub x9, x9, x15
  [0x10394] adrp x16, #0x10000
  [0x10398] add x16, x16, #0
  [0x1039C] str w9, [x16]
  [0x103A0] adrp x9, #0x10000
  [0x103A4] add x9, x9, #0
  [0x103A8] sub x9, x9, x15
  [0x103AC] adrp x16, #0x10000
  [0x103B0] add x16, x16, #0
  [0x103B4] str w9, [x16]
  [0x103B8] adrp x9, #0x10000
  [0x103BC] add x9, x9, #0
  [0x103C0] sub x9, x9, x15
  [0x103C4] adrp x16, #0x10000
  [0x103C8] add x16, x16, #0
  [0x103CC] str w9, [x16]
  [0x103D0] adrp x9, #0x10000
  [0x103D4] add x9, x9, #0
  [0x103D8] sub x9, x9, x15
  [0x103DC] adrp x16, #0x10000
  [0x103E0] add x16, x16, #0
  [0x103E4] str w9, [x16]
  [0x103E8] adrp x16, #0x10000
  [0x103EC] add x16, x16, #0
  [0x103F0] ldr w7, [x16]
  [0x103F4] movz x6, #0x3
  [0x103F8] adrp x2, #0x10000
  [0x103FC] add x2, x2, #0
  [0x10400] sub x2, x2, x15
  [0x10404] adrp x16, #0x10000
  [0x10408] add x16, x16, #0
  [0x1040C] ldr w9, [x16]
  [0x10410] mov x9, x9
  [0x10414] mov x7, x7
  [0x10418] mov x6, x6
  [0x1041C] mov x2, x2
  [0x10420] add x9, x9, x15
  [0x10424] stp x3, x5, [sp, #-0x10]!
  [0x10428] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1042C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10430] blr x9 ;; misaligned with debug data
  [0x10434] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10438] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1043C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10440] mov x3, x3
  [0x10444] adrp x16, #0x10000
  [0x10448] add x16, x16, #0
  [0x1044C] ldr w7, [x16]
  [0x10450] movz x6, #0x3
  [0x10454] adrp x2, #0x10000
  [0x10458] add x2, x2, #0
  [0x1045C] sub x2, x2, x15
  [0x10460] adrp x16, #0x10000
  [0x10464] add x16, x16, #0
  [0x10468] ldr w9, [x16]
  [0x1046C] mov x9, x9
  [0x10470] mov x7, x7
  [0x10474] mov x6, x6
  [0x10478] mov x2, x2
  [0x1047C] add x9, x9, x15
  [0x10480] stp x3, x5, [sp, #-0x10]!
  [0x10484] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10488] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1048C] blr x9 ;; misaligned with debug data
  [0x10490] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10494] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10498] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1049C] mov x3, x3
  [0x104A0] adrp x16, #0x10000
  [0x104A4] add x16, x16, #0
  [0x104A8] ldr w9, [x16]
  [0x104AC] mov x8, x14
  [0x104B0] sub x8, x8, x15 ;; misaligned with debug data
  [0x104B4] cmp x9, x8
  [0x104B8] b.eq #0x104dc
  [0x104BC] adrp x9, #0x10000
  [0x104C0] add x9, x9, #0
  [0x104C4] sub x9, x9, x15
  [0x104C8] adrp x16, #0x10000
  [0x104CC] add x16, x16, #0
  [0x104D0] str w9, [x16]
  [0x104D4] mov x9, x9
  [0x104D8] b #0x104f8
  [0x104DC] adrp x16, #0x10000
  [0x104E0] add x16, x16, #0
  [0x104E4] ldr w9, [x16]
  [0x104E8] adrp x16, #0x10000
  [0x104EC] add x16, x16, #0
  [0x104F0] str w9, [x16]
  [0x104F4] mov x9, x9
  [0x104F8] adrp x16, #0x10000
  [0x104FC] add x16, x16, #0
  [0x10500] ldr w7, [x16]
  [0x10504] movz x6, #0x2
  [0x10508] adrp x2, #0x10000
  [0x1050C] add x2, x2, #0
  [0x10510] sub x2, x2, x15
  [0x10514] adrp x16, #0x10000
  [0x10518] add x16, x16, #0
  [0x1051C] ldr w9, [x16]
  [0x10520] mov x9, x9
  [0x10524] mov x7, x7
  [0x10528] mov x6, x6
  [0x1052C] mov x2, x2
  [0x10530] add x9, x9, x15
  [0x10534] stp x3, x5, [sp, #-0x10]!
  [0x10538] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1053C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10540] blr x9 ;; misaligned with debug data
  [0x10544] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10548] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1054C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10550] mov x3, x3
  [0x10554] adrp x16, #0x10000
  [0x10558] add x16, x16, #0
  [0x1055C] ldr w7, [x16]
  [0x10560] movz x6, #0x1d
  [0x10564] adrp x2, #0x10000
  [0x10568] add x2, x2, #0
  [0x1056C] sub x2, x2, x15
  [0x10570] adrp x16, #0x10000
  [0x10574] add x16, x16, #0
  [0x10578] ldr w9, [x16]
  [0x1057C] mov x9, x9
  [0x10580] mov x7, x7
  [0x10584] mov x6, x6
  [0x10588] mov x2, x2
  [0x1058C] add x9, x9, x15
  [0x10590] stp x3, x5, [sp, #-0x10]!
  [0x10594] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10598] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1059C] blr x9 ;; misaligned with debug data
  [0x105A0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x105A4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x105A8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x105AC] mov x3, x3
  [0x105B0] adrp x16, #0x10000
  [0x105B4] add x16, x16, #0
  [0x105B8] ldr w7, [x16]
  [0x105BC] movz x6, #0xd
  [0x105C0] adrp x2, #0x10000
  [0x105C4] add x2, x2, #0
  [0x105C8] sub x2, x2, x15
  [0x105CC] adrp x16, #0x10000
  [0x105D0] add x16, x16, #0
  [0x105D4] ldr w9, [x16]
  [0x105D8] mov x9, x9
  [0x105DC] mov x7, x7
  [0x105E0] mov x6, x6
  [0x105E4] mov x2, x2
  [0x105E8] add x9, x9, x15
  [0x105EC] stp x3, x5, [sp, #-0x10]!
  [0x105F0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x105F4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x105F8] blr x9 ;; misaligned with debug data
  [0x105FC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10600] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10604] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10608] mov x3, x3
  [0x1060C] adrp x16, #0x10000
  [0x10610] add x16, x16, #0
  [0x10614] ldr w7, [x16]
  [0x10618] movz x6, #0x18
  [0x1061C] adrp x2, #0x10000
  [0x10620] add x2, x2, #0
  [0x10624] sub x2, x2, x15
  [0x10628] adrp x16, #0x10000
  [0x1062C] add x16, x16, #0
  [0x10630] ldr w9, [x16]
  [0x10634] mov x9, x9
  [0x10638] mov x7, x7
  [0x1063C] mov x6, x6
  [0x10640] mov x2, x2
  [0x10644] add x9, x9, x15
  [0x10648] stp x3, x5, [sp, #-0x10]!
  [0x1064C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10650] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10654] blr x9 ;; misaligned with debug data
  [0x10658] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1065C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10660] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10664] mov x3, x3
  [0x10668] adrp x16, #0x10000
  [0x1066C] add x16, x16, #0
  [0x10670] ldr w7, [x16]
  [0x10674] movz x6, #0x19
  [0x10678] adrp x2, #0x10000
  [0x1067C] add x2, x2, #0
  [0x10680] sub x2, x2, x15
  [0x10684] adrp x16, #0x10000
  [0x10688] add x16, x16, #0
  [0x1068C] ldr w9, [x16]
  [0x10690] mov x9, x9
  [0x10694] mov x7, x7
  [0x10698] mov x6, x6
  [0x1069C] mov x2, x2
  [0x106A0] add x9, x9, x15
  [0x106A4] stp x3, x5, [sp, #-0x10]!
  [0x106A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106B0] blr x9 ;; misaligned with debug data
  [0x106B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x106C0] mov x3, x3
  [0x106C4] adrp x9, #0x10000
  [0x106C8] add x9, x9, #0
  [0x106CC] sub x9, x9, x15
  [0x106D0] adrp x16, #0x10000
  [0x106D4] add x16, x16, #0
  [0x106D8] str w9, [x16]
  [0x106DC] adrp x16, #0x10000
  [0x106E0] add x16, x16, #0
  [0x106E4] ldr w7, [x16]
  [0x106E8] movz x6, #0x16
  [0x106EC] adrp x2, #0x10000
  [0x106F0] add x2, x2, #0
  [0x106F4] sub x2, x2, x15
  [0x106F8] adrp x16, #0x10000
  [0x106FC] add x16, x16, #0
  [0x10700] ldr w9, [x16]
  [0x10704] mov x9, x9
  [0x10708] mov x7, x7
  [0x1070C] mov x6, x6
  [0x10710] mov x2, x2
  [0x10714] add x9, x9, x15
  [0x10718] stp x3, x5, [sp, #-0x10]!
  [0x1071C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10720] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10724] blr x9 ;; misaligned with debug data
  [0x10728] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1072C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10730] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10734] mov x3, x3
  [0x10738] adrp x16, #0x10000
  [0x1073C] add x16, x16, #0
  [0x10740] ldr w7, [x16]
  [0x10744] movz x6, #0x17
  [0x10748] adrp x2, #0x10000
  [0x1074C] add x2, x2, #0
  [0x10750] sub x2, x2, x15
  [0x10754] adrp x16, #0x10000
  [0x10758] add x16, x16, #0
  [0x1075C] ldr w9, [x16]
  [0x10760] mov x9, x9
  [0x10764] mov x7, x7
  [0x10768] mov x6, x6
  [0x1076C] mov x2, x2
  [0x10770] add x9, x9, x15
  [0x10774] stp x3, x5, [sp, #-0x10]!
  [0x10778] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1077C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10780] blr x9 ;; misaligned with debug data
  [0x10784] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10788] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1078C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10790] mov x3, x3
  [0x10794] adrp x16, #0x10000
  [0x10798] add x16, x16, #0
  [0x1079C] ldr w7, [x16]
  [0x107A0] movz x6, #0x18
  [0x107A4] adrp x2, #0x10000
  [0x107A8] add x2, x2, #0
  [0x107AC] sub x2, x2, x15
  [0x107B0] adrp x16, #0x10000
  [0x107B4] add x16, x16, #0
  [0x107B8] ldr w9, [x16]
  [0x107BC] mov x9, x9
  [0x107C0] mov x7, x7
  [0x107C4] mov x6, x6
  [0x107C8] mov x2, x2
  [0x107CC] add x9, x9, x15
  [0x107D0] stp x3, x5, [sp, #-0x10]!
  [0x107D4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x107D8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x107DC] blr x9 ;; misaligned with debug data
  [0x107E0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x107E4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x107E8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x107EC] mov x3, x3
  [0x107F0] adrp x9, #0x10000
  [0x107F4] add x9, x9, #0
  [0x107F8] sub x9, x9, x15
  [0x107FC] adrp x16, #0x10000
  [0x10800] add x16, x16, #0
  [0x10804] str w9, [x16]
  [0x10808] adrp x16, #0x10000
  [0x1080C] add x16, x16, #0
  [0x10810] ldr w7, [x16]
  [0x10814] movz x6, #0xe
  [0x10818] adrp x2, #0x10000
  [0x1081C] add x2, x2, #0
  [0x10820] sub x2, x2, x15
  [0x10824] adrp x16, #0x10000
  [0x10828] add x16, x16, #0
  [0x1082C] ldr w9, [x16]
  [0x10830] mov x9, x9
  [0x10834] mov x7, x7
  [0x10838] mov x6, x6
  [0x1083C] mov x2, x2
  [0x10840] add x9, x9, x15
  [0x10844] stp x3, x5, [sp, #-0x10]!
  [0x10848] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1084C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10850] blr x9 ;; misaligned with debug data
  [0x10854] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10858] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1085C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10860] mov x3, x3
  [0x10864] adrp x16, #0x10000
  [0x10868] add x16, x16, #0
  [0x1086C] ldr w7, [x16]
  [0x10870] movz x6, #0x16
  [0x10874] adrp x2, #0x10000
  [0x10878] add x2, x2, #0
  [0x1087C] sub x2, x2, x15
  [0x10880] adrp x16, #0x10000
  [0x10884] add x16, x16, #0
  [0x10888] ldr w9, [x16]
  [0x1088C] mov x9, x9
  [0x10890] mov x7, x7
  [0x10894] mov x6, x6
  [0x10898] mov x2, x2
  [0x1089C] add x9, x9, x15
  [0x108A0] stp x3, x5, [sp, #-0x10]!
  [0x108A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108AC] blr x9 ;; misaligned with debug data
  [0x108B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108BC] mov x3, x3
  [0x108C0] adrp x16, #0x10000
  [0x108C4] add x16, x16, #0
  [0x108C8] ldr w7, [x16]
  [0x108CC] movz x6, #0x17
  [0x108D0] adrp x2, #0x10000
  [0x108D4] add x2, x2, #0
  [0x108D8] sub x2, x2, x15
  [0x108DC] adrp x16, #0x10000
  [0x108E0] add x16, x16, #0
  [0x108E4] ldr w9, [x16]
  [0x108E8] mov x9, x9
  [0x108EC] mov x7, x7
  [0x108F0] mov x6, x6
  [0x108F4] mov x2, x2
  [0x108F8] add x9, x9, x15
  [0x108FC] stp x3, x5, [sp, #-0x10]!
  [0x10900] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10904] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10908] blr x9 ;; misaligned with debug data
  [0x1090C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10910] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10914] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10918] mov x3, x3
  [0x1091C] adrp x9, #0x10000
  [0x10920] add x9, x9, #0
  [0x10924] sub x9, x9, x15
  [0x10928] adrp x16, #0x10000
  [0x1092C] add x16, x16, #0
  [0x10930] str w9, [x16]
  [0x10934] adrp x16, #0x10000
  [0x10938] add x16, x16, #0
  [0x1093C] ldr w7, [x16]
  [0x10940] movz x6, #0x16
  [0x10944] adrp x2, #0x10000
  [0x10948] add x2, x2, #0
  [0x1094C] sub x2, x2, x15
  [0x10950] adrp x16, #0x10000
  [0x10954] add x16, x16, #0
  [0x10958] ldr w9, [x16]
  [0x1095C] mov x9, x9
  [0x10960] mov x7, x7
  [0x10964] mov x6, x6
  [0x10968] mov x2, x2
  [0x1096C] add x9, x9, x15
  [0x10970] stp x3, x5, [sp, #-0x10]!
  [0x10974] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10978] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1097C] blr x9 ;; misaligned with debug data
  [0x10980] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10984] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10988] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1098C] mov x3, x3
  [0x10990] adrp x9, #0x10000
  [0x10994] add x9, x9, #0
  [0x10998] sub x9, x9, x15
  [0x1099C] adrp x16, #0x10000
  [0x109A0] add x16, x16, #0
  [0x109A4] str w9, [x16]
  [0x109A8] adrp x16, #0x10000
  [0x109AC] add x16, x16, #0
  [0x109B0] ldr w7, [x16]
  [0x109B4] movz x6, #0x17
  [0x109B8] adrp x2, #0x10000
  [0x109BC] add x2, x2, #0
  [0x109C0] sub x2, x2, x15
  [0x109C4] adrp x16, #0x10000
  [0x109C8] add x16, x16, #0
  [0x109CC] ldr w9, [x16]
  [0x109D0] mov x9, x9
  [0x109D4] mov x7, x7
  [0x109D8] mov x6, x6
  [0x109DC] mov x2, x2
  [0x109E0] add x9, x9, x15
  [0x109E4] stp x3, x5, [sp, #-0x10]!
  [0x109E8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x109EC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109F0] blr x9 ;; misaligned with debug data
  [0x109F4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109F8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109FC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A00] mov x3, x3
  [0x10A04] adrp x16, #0x10000
  [0x10A08] add x16, x16, #0
  [0x10A0C] ldr w7, [x16]
  [0x10A10] movz x6, #0x12
  [0x10A14] adrp x2, #0x10000
  [0x10A18] add x2, x2, #0
  [0x10A1C] sub x2, x2, x15
  [0x10A20] adrp x16, #0x10000
  [0x10A24] add x16, x16, #0
  [0x10A28] ldr w9, [x16]
  [0x10A2C] mov x9, x9
  [0x10A30] mov x7, x7
  [0x10A34] mov x6, x6
  [0x10A38] mov x2, x2
  [0x10A3C] add x9, x9, x15
  [0x10A40] stp x3, x5, [sp, #-0x10]!
  [0x10A44] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A48] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10A4C] blr x9 ;; misaligned with debug data
  [0x10A50] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10A54] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10A58] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10A5C] mov x3, x3
  [0x10A60] adrp x16, #0x10000
  [0x10A64] add x16, x16, #0
  [0x10A68] ldr w7, [x16]
  [0x10A6C] movz x6, #0x13
  [0x10A70] adrp x2, #0x10000
  [0x10A74] add x2, x2, #0
  [0x10A78] sub x2, x2, x15
  [0x10A7C] adrp x16, #0x10000
  [0x10A80] add x16, x16, #0
  [0x10A84] ldr w9, [x16]
  [0x10A88] mov x9, x9
  [0x10A8C] mov x7, x7
  [0x10A90] mov x6, x6
  [0x10A94] mov x2, x2
  [0x10A98] add x9, x9, x15
  [0x10A9C] stp x3, x5, [sp, #-0x10]!
  [0x10AA0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AA4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AA8] blr x9 ;; misaligned with debug data
  [0x10AAC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10AB0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10AB4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AB8] mov x3, x3
  [0x10ABC] adrp x9, #0x10000
  [0x10AC0] add x9, x9, #0
  [0x10AC4] sub x9, x9, x15
  [0x10AC8] adrp x16, #0x10000
  [0x10ACC] add x16, x16, #0
  [0x10AD0] str w9, [x16]
  [0x10AD4] adrp x16, #0x10000
  [0x10AD8] add x16, x16, #0
  [0x10ADC] ldr w7, [x16]
  [0x10AE0] movz x6, #0x9
  [0x10AE4] adrp x2, #0x10000
  [0x10AE8] add x2, x2, #0
  [0x10AEC] sub x2, x2, x15
  [0x10AF0] adrp x16, #0x10000
  [0x10AF4] add x16, x16, #0
  [0x10AF8] ldr w9, [x16]
  [0x10AFC] mov x9, x9
  [0x10B00] mov x7, x7
  [0x10B04] mov x6, x6
  [0x10B08] mov x2, x2
  [0x10B0C] add x9, x9, x15
  [0x10B10] stp x3, x5, [sp, #-0x10]!
  [0x10B14] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B18] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B1C] blr x9 ;; misaligned with debug data
  [0x10B20] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B24] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10B28] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10B2C] mov x3, x3
  [0x10B30] adrp x9, #0x10000
  [0x10B34] add x9, x9, #0
  [0x10B38] sub x9, x9, x15
  [0x10B3C] adrp x16, #0x10000
  [0x10B40] add x16, x16, #0
  [0x10B44] str w9, [x16]
  [0x10B48] adrp x9, #0x10000
  [0x10B4C] add x9, x9, #0
  [0x10B50] sub x9, x9, x15
  [0x10B54] adrp x16, #0x10000
  [0x10B58] add x16, x16, #0
  [0x10B5C] str w9, [x16]
  [0x10B60] adrp x16, #0x10000
  [0x10B64] add x16, x16, #0
  [0x10B68] ldr w7, [x16]
  [0x10B6C] movz x6, #0xc
  [0x10B70] adrp x2, #0x10000
  [0x10B74] add x2, x2, #0
  [0x10B78] sub x2, x2, x15
  [0x10B7C] adrp x16, #0x10000
  [0x10B80] add x16, x16, #0
  [0x10B84] ldr w9, [x16]
  [0x10B88] mov x9, x9
  [0x10B8C] mov x7, x7
  [0x10B90] mov x6, x6
  [0x10B94] mov x2, x2
  [0x10B98] add x9, x9, x15
  [0x10B9C] stp x3, x5, [sp, #-0x10]!
  [0x10BA0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10BA4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10BA8] blr x9 ;; misaligned with debug data
  [0x10BAC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10BB0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10BB4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10BB8] mov x3, x3
  [0x10BBC] adrp x16, #0x10000
  [0x10BC0] add x16, x16, #0
  [0x10BC4] ldr w7, [x16]
  [0x10BC8] movz x6, #0x9
  [0x10BCC] adrp x2, #0x10000
  [0x10BD0] add x2, x2, #0
  [0x10BD4] sub x2, x2, x15
  [0x10BD8] adrp x16, #0x10000
  [0x10BDC] add x16, x16, #0
  [0x10BE0] ldr w9, [x16]
  [0x10BE4] mov x9, x9
  [0x10BE8] mov x7, x7
  [0x10BEC] mov x6, x6
  [0x10BF0] mov x2, x2
  [0x10BF4] add x9, x9, x15
  [0x10BF8] stp x3, x5, [sp, #-0x10]!
  [0x10BFC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C00] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C04] blr x9 ;; misaligned with debug data
  [0x10C08] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C0C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C10] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C14] mov x3, x3
  [0x10C18] adrp x16, #0x10000
  [0x10C1C] add x16, x16, #0
  [0x10C20] ldr w7, [x16]
  [0x10C24] movz x6, #0xf
  [0x10C28] adrp x2, #0x10000
  [0x10C2C] add x2, x2, #0
  [0x10C30] sub x2, x2, x15
  [0x10C34] adrp x16, #0x10000
  [0x10C38] add x16, x16, #0
  [0x10C3C] ldr w9, [x16]
  [0x10C40] mov x9, x9
  [0x10C44] mov x7, x7
  [0x10C48] mov x6, x6
  [0x10C4C] mov x2, x2
  [0x10C50] add x9, x9, x15
  [0x10C54] stp x3, x5, [sp, #-0x10]!
  [0x10C58] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C5C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10C60] blr x9 ;; misaligned with debug data
  [0x10C64] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10C68] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10C6C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10C70] mov x3, x3
  [0x10C74] adrp x9, #0x10000
  [0x10C78] add x9, x9, #0
  [0x10C7C] sub x9, x9, x15
  [0x10C80] adrp x16, #0x10000
  [0x10C84] add x16, x16, #0
  [0x10C88] str w9, [x16]
  [0x10C8C] adrp x9, #0x10000
  [0x10C90] add x9, x9, #0
  [0x10C94] sub x9, x9, x15
  [0x10C98] adrp x16, #0x10000
  [0x10C9C] add x16, x16, #0
  [0x10CA0] str w9, [x16]
  [0x10CA4] adrp x9, #0x10000
  [0x10CA8] add x9, x9, #0
  [0x10CAC] sub x9, x9, x15
  [0x10CB0] adrp x16, #0x10000
  [0x10CB4] add x16, x16, #0
  [0x10CB8] str w9, [x16]
  [0x10CBC] adrp x16, #0x10000
  [0x10CC0] add x16, x16, #0
  [0x10CC4] ldr w7, [x16]
  [0x10CC8] movz x6, #0x1e
  [0x10CCC] adrp x2, #0x10000
  [0x10CD0] add x2, x2, #0
  [0x10CD4] sub x2, x2, x15
  [0x10CD8] adrp x16, #0x10000
  [0x10CDC] add x16, x16, #0
  [0x10CE0] ldr w9, [x16]
  [0x10CE4] mov x9, x9
  [0x10CE8] mov x7, x7
  [0x10CEC] mov x6, x6
  [0x10CF0] mov x2, x2
  [0x10CF4] add x9, x9, x15
  [0x10CF8] stp x3, x5, [sp, #-0x10]!
  [0x10CFC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D00] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10D04] blr x9 ;; misaligned with debug data
  [0x10D08] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10D0C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10D10] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10D14] mov x3, x3
  [0x10D18] adrp x0, #0x10000
  [0x10D1C] add x0, x0, #0
  [0x10D20] sub x0, x0, x15
  [0x10D24] adrp x16, #0x10000
  [0x10D28] add x16, x16, #0
  [0x10D2C] str w0, [x16]
  [0x10D30] mov x0, x0
  [0x10D34] add sp, sp, #0x10
  [0x10D38] ldp x29, x30, [sp], #0x10
  [0x10D3C] ret


[(method print-volume-sizes level-group)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] str q24, [sp, #-0x10]!
  [0x1000C] sub sp, sp, #0x50
  [0x10010] mov x12, x7
  [0x10014] movz x3, #0
  [0x10018] mov x3, x3
  [0x1001C] str x3, [sp]
  [0x10020] b #0x106ec
  [0x10024] movz x8, #0xa30
  [0x10028] ldr x9, [sp]
  [0x1002C] mul x8, x8, x9
  [0x10030] mov x8, x8
  [0x10034] movz x9, #0x60
  [0x10038] add x9, x9, x12
  [0x1003C] add x8, x8, x9
  [0x10040] mov x8, x8
  [0x10044] add x16, x8, x15
  [0x10048] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x1004C] adrp x1, #0x10000
  [0x10050] add x1, x1, #0
  [0x10054] cmp x9, x1
  [0x10058] b.ne #0x106cc
  [0x1005C] add x16, x8, x15
  [0x10060] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10064] add x16, x9, x15
  [0x10068] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x1006C] add x16, x9, x15
  [0x10070] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10074] mov x3, x3
  [0x10078] str x3, [sp, #8]
  [0x1007C] movz x3, #0
  [0x10080] mov x3, x3
  [0x10084] str x3, [sp, #0x10]
  [0x10088] b #0x106a4
  [0x1008C] ldr x9, [sp, #0x10]
  [0x10090] mov x8, x9
  [0x10094] lsl x8, x8, #6
  [0x10098] mov x8, x8
  [0x1009C] movz x1, #0xc
  [0x100A0] ldr x9, [sp, #8]
  [0x100A4] add x1, x1, x9
  [0x100A8] add x8, x8, x1
  [0x100AC] add x16, x8, x15
  [0x100B0] ldr w3, [x16, #8] ;; misaligned with debug data
  [0x100B4] mov x11, x3
  [0x100B8] adrp x16, #0x10000
  [0x100BC] add x16, x16, #0
  [0x100C0] ldr w9, [x16]
  [0x100C4] add x16, x9, x15
  [0x100C8] ldr w1, [x16, #0x34] ;; misaligned with debug data
  [0x100CC] adrp x6, #0x10000
  [0x100D0] add x6, x6, #0
  [0x100D4] adrp x2, #0x10000
  [0x100D8] add x2, x2, #0
  [0x100DC] adrp x16, #0x17000
  [0x100E0] ldr s23, [x16, #0xef8]
  [0x100E4] mov x8, x14
  [0x100E8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100EC] mov x8, x8
  [0x100F0] mov x9, x14
  [0x100F4] sub x9, x9, x15 ;; misaligned with debug data
  [0x100F8] mov x9, x9
  [0x100FC] adrp x16, #0x10000
  [0x10100] add x16, x16, #0
  [0x10104] ldr w10, [x16]
  [0x10108] mov x3, x1
  [0x1010C] mov x7, x11
  [0x10110] mov x6, x6
  [0x10114] mov x2, x2
  [0x10118] fmov w1, s23
  [0x1011C] sxtw x1, w1
  [0x10120] mov x8, x8
  [0x10124] mov x9, x9
  [0x10128] mov x10, x10
  [0x1012C] add x3, x3, x15
  [0x10130] stp x3, x5, [sp, #-0x10]!
  [0x10134] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10138] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1013C] blr x3 ;; misaligned with debug data
  [0x10140] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10144] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10148] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1014C] mov x0, x0
  [0x10150] mov x0, x0
  [0x10154] mov x3, x0
  [0x10158] mov x3, x3
  [0x1015C] str x3, [sp, #0x20]
  [0x10160] adrp x16, #0x10000
  [0x10164] add x16, x16, #0
  [0x10168] ldr w9, [x16]
  [0x1016C] add x16, x9, x15
  [0x10170] ldr w8, [x16, #0x40] ;; misaligned with debug data
  [0x10174] adrp x6, #0x10000
  [0x10178] add x6, x6, #0
  [0x1017C] adrp x2, #0x10000
  [0x10180] add x2, x2, #0
  [0x10184] adrp x16, #0x17000
  [0x10188] ldr s23, [x16, #0xefc]
  [0x1018C] adrp x16, #0x17000
  [0x10190] ldr s22, [x16, #0xf00]
  [0x10194] mov x9, x14
  [0x10198] sub x9, x9, x15 ;; misaligned with debug data
  [0x1019C] mov x9, x9
  [0x101A0] adrp x16, #0x10000
  [0x101A4] add x16, x16, #0
  [0x101A8] ldr w10, [x16]
  [0x101AC] mov x3, x8
  [0x101B0] mov x7, x11
  [0x101B4] mov x6, x6
  [0x101B8] mov x2, x2
  [0x101BC] fmov w1, s23
  [0x101C0] sxtw x1, w1
  [0x101C4] fmov w8, s22
  [0x101C8] sxtw x8, w8
  [0x101CC] mov x9, x9
  [0x101D0] mov x10, x10
  [0x101D4] add x3, x3, x15
  [0x101D8] stp x3, x5, [sp, #-0x10]!
  [0x101DC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101E0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101E4] blr x3 ;; misaligned with debug data
  [0x101E8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101EC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101F0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101F4] mov x0, x0
  [0x101F8] fmov s24, w0
  [0x101FC] movz x3, #0x20
  [0x10200] add x16, x11, x15
  [0x10204] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10208] add x3, x3, x9
  [0x1020C] mov x3, x3
  [0x10210] str x3, [sp, #0x18]
  [0x10214] adrp x16, #0x10000
  [0x10218] add x16, x16, #0
  [0x1021C] ldr w9, [x16]
  [0x10220] add x16, x11, x15
  [0x10224] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x10228] adrp x16, #0x10000
  [0x1022C] add x16, x16, #0
  [0x10230] ldr w6, [x16]
  [0x10234] mov x9, x9
  [0x10238] mov x7, x7
  [0x1023C] mov x6, x6
  [0x10240] add x9, x9, x15
  [0x10244] stp x3, x5, [sp, #-0x10]!
  [0x10248] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1024C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10250] blr x9 ;; misaligned with debug data
  [0x10254] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10258] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1025C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10260] mov x0, x0
  [0x10264] mov x9, x14
  [0x10268] sub x9, x9, x15 ;; misaligned with debug data
  [0x1026C] cmp x0, x9
  [0x10270] b.eq #0x1028c
  [0x10274] mov x9, x11
  [0x10278] add x16, x9, x15
  [0x1027C] ldr w3, [x16, #0x34] ;; misaligned with debug data
  [0x10280] mov x10, x3
  [0x10284] mov x3, x10
  [0x10288] b #0x1029c
  [0x1028C] mov x3, x14
  [0x10290] sub x3, x3, x15 ;; misaligned with debug data
  [0x10294] mov x3, x3
  [0x10298] mov x3, x3
  [0x1029C] mov x10, x3
  [0x102A0] ldr x9, [sp, #0x20]
  [0x102A4] mov x3, x9
  [0x102A8] mov x3, x3
  [0x102AC] movz x5, #0x10
  [0x102B0] ldr x9, [sp, #0x20]
  [0x102B4] mov x8, x9
  [0x102B8] add x5, x5, x8
  [0x102BC] mov x3, x3
  [0x102C0] mov x5, x5
  [0x102C4] adrp x16, #0x10000
  [0x102C8] add x16, x16, #0
  [0x102CC] ldr w9, [x16]
  [0x102D0] adrp x16, #0x10000
  [0x102D4] add x16, x16, #0
  [0x102D8] ldr w6, [x16]
  [0x102DC] mov x9, x9
  [0x102E0] mov x7, x10
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
  [0x1030C] mov x0, x0
  [0x10310] mov x9, x14
  [0x10314] sub x9, x9, x15 ;; misaligned with debug data
  [0x10318] cmp x0, x9
  [0x1031C] b.ne #0x10428
  [0x10320] adrp x16, #0x10000
  [0x10324] add x16, x16, #0
  [0x10328] ldr w9, [x16]
  [0x1032C] adrp x16, #0x10000
  [0x10330] add x16, x16, #0
  [0x10334] ldr w6, [x16]
  [0x10338] mov x9, x9
  [0x1033C] mov x7, x10
  [0x10340] mov x6, x6
  [0x10344] add x9, x9, x15
  [0x10348] stp x3, x5, [sp, #-0x10]!
  [0x1034C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10350] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10354] blr x9 ;; misaligned with debug data
  [0x10358] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1035C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10360] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10364] mov x0, x0
  [0x10368] mov x0, x0
  [0x1036C] mov x9, x14
  [0x10370] sub x9, x9, x15 ;; misaligned with debug data
  [0x10374] cmp x0, x9
  [0x10378] b.ne #0x10424
  [0x1037C] adrp x16, #0x10000
  [0x10380] add x16, x16, #0
  [0x10384] ldr w9, [x16]
  [0x10388] adrp x16, #0x10000
  [0x1038C] add x16, x16, #0
  [0x10390] ldr w6, [x16]
  [0x10394] mov x9, x9
  [0x10398] mov x7, x10
  [0x1039C] mov x6, x6
  [0x103A0] add x9, x9, x15
  [0x103A4] stp x3, x5, [sp, #-0x10]!
  [0x103A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103B0] blr x9 ;; misaligned with debug data
  [0x103B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103C0] mov x0, x0
  [0x103C4] mov x0, x0
  [0x103C8] mov x9, x14
  [0x103CC] sub x9, x9, x15 ;; misaligned with debug data
  [0x103D0] cmp x0, x9
  [0x103D4] b.ne #0x10424
  [0x103D8] adrp x16, #0x10000
  [0x103DC] add x16, x16, #0
  [0x103E0] ldr w9, [x16]
  [0x103E4] adrp x16, #0x10000
  [0x103E8] add x16, x16, #0
  [0x103EC] ldr w6, [x16]
  [0x103F0] mov x9, x9
  [0x103F4] mov x7, x10
  [0x103F8] mov x6, x6
  [0x103FC] add x9, x9, x15
  [0x10400] stp x3, x5, [sp, #-0x10]!
  [0x10404] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10408] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1040C] blr x9 ;; misaligned with debug data
  [0x10410] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10414] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10418] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1041C] mov x0, x0
  [0x10420] mov x0, x0
  [0x10424] mov x0, x0
  [0x10428] mov x9, x14
  [0x1042C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10430] cmp x0, x9
  [0x10434] b.ne #0x10684
  [0x10438] adrp x16, #0x10000
  [0x1043C] add x16, x16, #0
  [0x10440] ldr w9, [x16]
  [0x10444] str x9, [sp, #0x28]
  [0x10448] add x9, x14, #8
  [0x1044C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10450] str x9, [sp, #0x30]
  [0x10454] adrp x9, #0x17000
  [0x10458] add x9, x9, #0xf14
  [0x1045C] sub x9, x9, x15
  [0x10460] str x9, [sp, #0x38]
  [0x10464] adrp x16, #0x10000
  [0x10468] add x16, x16, #0
  [0x1046C] ldr w9, [x16]
  [0x10470] add x16, x9, x15
  [0x10474] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x10478] adrp x6, #0x10000
  [0x1047C] add x6, x6, #0
  [0x10480] adrp x2, #0x10000
  [0x10484] add x2, x2, #0
  [0x10488] adrp x16, #0x17000
  [0x1048C] ldr s23, [x16, #0xf30]
  [0x10490] mov x8, x14
  [0x10494] sub x8, x8, x15 ;; misaligned with debug data
  [0x10498] mov x8, x8
  [0x1049C] mov x9, x14
  [0x104A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x104A4] mov x9, x9
  [0x104A8] adrp x16, #0x10000
  [0x104AC] add x16, x16, #0
  [0x104B0] ldr w10, [x16]
  [0x104B4] mov x1, x1
  [0x104B8] str x1, [sp, #0x40]
  [0x104BC] mov x7, x11
  [0x104C0] mov x6, x6
  [0x104C4] mov x2, x2
  [0x104C8] fmov w1, s23
  [0x104CC] sxtw x1, w1
  [0x104D0] mov x8, x8
  [0x104D4] mov x9, x9
  [0x104D8] mov x10, x10
  [0x104DC] ldr x11, [sp, #0x40]
  [0x104E0] add x11, x11, x15
  [0x104E4] stp x3, x5, [sp, #-0x10]!
  [0x104E8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104EC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104F0] blr x11 ;; misaligned with debug data
  [0x104F4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104F8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104FC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10500] str x11, [sp, #0x40]
  [0x10504] mov x0, x0
  [0x10508] mov x0, x0
  [0x1050C] ldr x9, [sp, #0x28]
  [0x10510] mov x8, x9
  [0x10514] ldr x7, [sp, #0x30]
  [0x10518] mov x7, x7
  [0x1051C] ldr x6, [sp, #0x38]
  [0x10520] mov x6, x6
  [0x10524] mov x2, x0
  [0x10528] fmov w1, s24
  [0x1052C] sxtw x1, w1
  [0x10530] add x8, x8, x15
  [0x10534] stp x3, x5, [sp, #-0x10]!
  [0x10538] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1053C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10540] blr x8 ;; misaligned with debug data
  [0x10544] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10548] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1054C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10550] mov x0, x0
  [0x10554] adrp x16, #0x10000
  [0x10558] add x16, x16, #0
  [0x1055C] ldr w8, [x16]
  [0x10560] add x7, x14, #8
  [0x10564] sub x7, x7, x15 ;; misaligned with debug data
  [0x10568] adrp x6, #0x17000
  [0x1056C] add x6, x6, #0xf44
  [0x10570] sub x6, x6, x15
  [0x10574] add x16, x3, x15
  [0x10578] ldr s23, [x16] ;; misaligned with debug data
  [0x1057C] mov v23.16b, v23.16b
  [0x10580] ldr x9, [sp, #0x18]
  [0x10584] add x16, x9, x15
  [0x10588] ldr s22, [x16] ;; misaligned with debug data
  [0x1058C] fsub s23, s23, s22
  [0x10590] add x16, x3, x15
  [0x10594] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x10598] mov v22.16b, v22.16b
  [0x1059C] ldr x9, [sp, #0x18]
  [0x105A0] add x16, x9, x15
  [0x105A4] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x105A8] fsub s22, s22, s21
  [0x105AC] add x16, x3, x15
  [0x105B0] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x105B4] mov v21.16b, v21.16b
  [0x105B8] ldr x9, [sp, #0x18]
  [0x105BC] add x16, x9, x15
  [0x105C0] ldr s20, [x16, #8] ;; misaligned with debug data
  [0x105C4] fsub s21, s21, s20
  [0x105C8] add x16, x5, x15
  [0x105CC] ldr s20, [x16] ;; misaligned with debug data
  [0x105D0] mov v20.16b, v20.16b
  [0x105D4] ldr x9, [sp, #0x18]
  [0x105D8] add x16, x9, x15
  [0x105DC] ldr s19, [x16] ;; misaligned with debug data
  [0x105E0] fsub s20, s20, s19
  [0x105E4] add x16, x5, x15
  [0x105E8] ldr s19, [x16, #4] ;; misaligned with debug data
  [0x105EC] mov v19.16b, v19.16b
  [0x105F0] ldr x9, [sp, #0x18]
  [0x105F4] add x16, x9, x15
  [0x105F8] ldr s18, [x16, #4] ;; misaligned with debug data
  [0x105FC] fsub s19, s19, s18
  [0x10600] add x16, x5, x15
  [0x10604] ldr s18, [x16, #8] ;; misaligned with debug data
  [0x10608] mov v18.16b, v18.16b
  [0x1060C] ldr x9, [sp, #0x18]
  [0x10610] add x16, x9, x15
  [0x10614] ldr s17, [x16, #8] ;; misaligned with debug data
  [0x10618] fsub s18, s18, s17
  [0x1061C] mov x3, x8
  [0x10620] mov x7, x7
  [0x10624] mov x6, x6
  [0x10628] fmov w2, s23
  [0x1062C] sxtw x2, w2
  [0x10630] fmov w1, s22
  [0x10634] sxtw x1, w1
  [0x10638] fmov w8, s21
  [0x1063C] sxtw x8, w8
  [0x10640] fmov w9, s20
  [0x10644] sxtw x9, w9
  [0x10648] fmov w10, s19
  [0x1064C] sxtw x10, w10
  [0x10650] fmov w11, s18
  [0x10654] sxtw x11, w11
  [0x10658] add x3, x3, x15
  [0x1065C] stp x3, x5, [sp, #-0x10]!
  [0x10660] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10664] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10668] blr x3 ;; misaligned with debug data
  [0x1066C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10670] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10674] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10678] mov x0, x0
  [0x1067C] mov x0, x0
  [0x10680] b #0x1068c
  [0x10684] mov x0, x14
  [0x10688] sub x0, x0, x15 ;; misaligned with debug data
  [0x1068C] ldr x3, [sp, #0x10]
  [0x10690] mov x3, x3
  [0x10694] movz x9, #0x1
  [0x10698] add x3, x3, x9
  [0x1069C] mov x3, x3
  [0x106A0] str x3, [sp, #0x10]
  [0x106A4] ldr x9, [sp, #8]
  [0x106A8] add x16, x9, x15
  [0x106AC] ldrsw x8, [x16] ;; misaligned with debug data
  [0x106B0] ldr x9, [sp, #0x10]
  [0x106B4] cmp x9, x8
  [0x106B8] b.lt #0x1008c
  [0x106BC] mov x9, x14
  [0x106C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x106C4] mov x9, x9
  [0x106C8] b #0x106d4
  [0x106CC] mov x9, x14
  [0x106D0] sub x9, x9, x15 ;; misaligned with debug data
  [0x106D4] ldr x3, [sp]
  [0x106D8] mov x3, x3
  [0x106DC] movz x9, #0x1
  [0x106E0] add x3, x3, x9
  [0x106E4] mov x3, x3
  [0x106E8] str x3, [sp]
  [0x106EC] add x16, x12, x15
  [0x106F0] ldrsw x8, [x16] ;; misaligned with debug data
  [0x106F4] ldr x9, [sp]
  [0x106F8] cmp x9, x8
  [0x106FC] b.lt #0x10024
  [0x10700] mov x9, x14
  [0x10704] sub x9, x9, x15 ;; misaligned with debug data
  [0x10708] add sp, sp, #0x50
  [0x1070C] ldr q24, [sp], #0x10
  [0x10710] ldp x29, x30, [sp], #0x10
  [0x10714] ret


[(method update-vis-volumes-from-nav-mesh level-group)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x30
  [0x1000C] mov x5, x7
  [0x10010] movz x3, #0
  [0x10014] mov x12, x3
  [0x10018] b #0x1046c
  [0x1001C] movz x9, #0xa30
  [0x10020] mul x9, x9, x12
  [0x10024] mov x9, x9
  [0x10028] movz x8, #0x60
  [0x1002C] add x8, x8, x5
  [0x10030] add x9, x9, x8
  [0x10034] mov x9, x9
  [0x10038] add x16, x9, x15
  [0x1003C] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x10040] adrp x1, #0x10000
  [0x10044] add x1, x1, #0
  [0x10048] cmp x8, x1
  [0x1004C] b.ne #0x10454
  [0x10050] add x16, x9, x15
  [0x10054] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10058] add x16, x9, x15
  [0x1005C] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10060] add x16, x9, x15
  [0x10064] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10068] mov x11, x3
  [0x1006C] movz x3, #0
  [0x10070] mov x3, x3
  [0x10074] str x3, [sp]
  [0x10078] b #0x10430
  [0x1007C] ldr x9, [sp]
  [0x10080] mov x8, x9
  [0x10084] lsl x8, x8, #6
  [0x10088] mov x8, x8
  [0x1008C] movz x9, #0xc
  [0x10090] add x9, x9, x11
  [0x10094] add x8, x8, x9
  [0x10098] add x16, x8, x15
  [0x1009C] ldr w3, [x16, #8] ;; misaligned with debug data
  [0x100A0] mov x3, x3
  [0x100A4] str x3, [sp, #0x20]
  [0x100A8] adrp x16, #0x10000
  [0x100AC] add x16, x16, #0
  [0x100B0] ldr w9, [x16]
  [0x100B4] add x16, x9, x15
  [0x100B8] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x100BC] adrp x6, #0x10000
  [0x100C0] add x6, x6, #0
  [0x100C4] adrp x2, #0x10000
  [0x100C8] add x2, x2, #0
  [0x100CC] adrp x16, #0x17000
  [0x100D0] ldr s23, [x16, #0xeec]
  [0x100D4] mov x8, x14
  [0x100D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100DC] mov x8, x8
  [0x100E0] mov x1, x14
  [0x100E4] sub x1, x1, x15 ;; misaligned with debug data
  [0x100E8] mov x0, x1
  [0x100EC] adrp x16, #0x10000
  [0x100F0] add x16, x16, #0
  [0x100F4] ldr w10, [x16]
  [0x100F8] mov x3, x9
  [0x100FC] ldr x9, [sp, #0x20]
  [0x10100] mov x7, x9
  [0x10104] mov x6, x6
  [0x10108] mov x2, x2
  [0x1010C] fmov w1, s23
  [0x10110] sxtw x1, w1
  [0x10114] mov x8, x8
  [0x10118] mov x9, x0
  [0x1011C] mov x10, x10
  [0x10120] add x3, x3, x15
  [0x10124] stp x3, x5, [sp, #-0x10]!
  [0x10128] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1012C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10130] blr x3 ;; misaligned with debug data
  [0x10134] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10138] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1013C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10140] mov x0, x0
  [0x10144] mov x0, x0
  [0x10148] mov x0, x0
  [0x1014C] mov x3, x0
  [0x10150] mov x3, x3
  [0x10154] str x3, [sp, #8]
  [0x10158] movz x3, #0x10
  [0x1015C] add x3, x3, x0
  [0x10160] mov x10, x3
  [0x10164] movz x3, #0x20
  [0x10168] ldr x9, [sp, #0x20]
  [0x1016C] add x16, x9, x15
  [0x10170] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10174] add x3, x3, x8
  [0x10178] mov x3, x3
  [0x1017C] str x3, [sp, #0x10]
  [0x10180] ldr x8, [sp, #0x20]
  [0x10184] mov x9, x8
  [0x10188] str x9, [sp, #0x18]
  [0x1018C] adrp x16, #0x10000
  [0x10190] add x16, x16, #0
  [0x10194] ldr w9, [x16]
  [0x10198] adrp x6, #0x10000
  [0x1019C] add x6, x6, #0
  [0x101A0] movz x2, #0
  [0x101A4] mov x9, x9
  [0x101A8] ldr x7, [sp, #0x20]
  [0x101AC] mov x7, x7
  [0x101B0] mov x6, x6
  [0x101B4] mov x2, x2
  [0x101B8] add x9, x9, x15
  [0x101BC] stp x3, x5, [sp, #-0x10]!
  [0x101C0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101C4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101C8] blr x9 ;; misaligned with debug data
  [0x101CC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101D0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101D4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101D8] mov x0, x0
  [0x101DC] mov x3, x0
  [0x101E0] mov x9, x14
  [0x101E4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101E8] cmp x3, x9
  [0x101EC] b.eq #0x1020c
  [0x101F0] mov x3, x3
  [0x101F4] str x3, [sp, #0x18]
  [0x101F8] ldr x9, [sp, #0x18]
  [0x101FC] mov x8, x9
  [0x10200] mov x8, x8
  [0x10204] mov x9, x8
  [0x10208] b #0x10214
  [0x1020C] mov x9, x14
  [0x10210] sub x9, x9, x15 ;; misaligned with debug data
  [0x10214] adrp x16, #0x10000
  [0x10218] add x16, x16, #0
  [0x1021C] ldr w8, [x16]
  [0x10220] ldr x9, [sp, #0x18]
  [0x10224] add x16, x9, x15
  [0x10228] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x1022C] adrp x16, #0x10000
  [0x10230] add x16, x16, #0
  [0x10234] ldr w6, [x16]
  [0x10238] mov x8, x8
  [0x1023C] mov x7, x7
  [0x10240] mov x6, x6
  [0x10244] add x8, x8, x15
  [0x10248] stp x3, x5, [sp, #-0x10]!
  [0x1024C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10250] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10254] blr x8 ;; misaligned with debug data
  [0x10258] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1025C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10260] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10264] mov x0, x0
  [0x10268] mov x0, x0
  [0x1026C] mov x9, x14
  [0x10270] sub x9, x9, x15 ;; misaligned with debug data
  [0x10274] cmp x0, x9
  [0x10278] b.eq #0x102b0
  [0x1027C] ldr x9, [sp, #0x18]
  [0x10280] mov x8, x9
  [0x10284] add x16, x8, x15
  [0x10288] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x1028C] movz x8, #0
  [0x10290] mov x0, x14
  [0x10294] sub x0, x0, x15 ;; misaligned with debug data
  [0x10298] cmp x9, x8
  [0x1029C] b.eq #0x102ac
  [0x102A0] add x0, x14, #8
  [0x102A4] sub x0, x0, x15 ;; misaligned with debug data
  [0x102A8] mov x0, x0
  [0x102AC] mov x0, x0
  [0x102B0] mov x9, x14
  [0x102B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x102B8] cmp x0, x9
  [0x102BC] b.eq #0x10320
  [0x102C0] ldr x9, [sp, #0x18]
  [0x102C4] mov x8, x9
  [0x102C8] add x16, x8, x15
  [0x102CC] ldr w7, [x16, #0x30] ;; misaligned with debug data
  [0x102D0] add x16, x7, x15
  [0x102D4] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x102D8] add x16, x9, x15
  [0x102DC] ldr w9, [x16, #0x5c] ;; misaligned with debug data
  [0x102E0] mov x8, x9
  [0x102E4] mov x7, x7
  [0x102E8] ldr x9, [sp, #8]
  [0x102EC] mov x6, x9
  [0x102F0] mov x2, x10
  [0x102F4] add x8, x8, x15
  [0x102F8] stp x3, x5, [sp, #-0x10]!
  [0x102FC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10300] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10304] blr x8 ;; misaligned with debug data
  [0x10308] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1030C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10310] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10314] mov x3, x3
  [0x10318] mov x3, x3
  [0x1031C] b #0x10358
  [0x10320] ldr x9, [sp, #0x10]
  [0x10324] add x16, x9, x15
  [0x10328] ldr q23, [x16] ;; misaligned with debug data
  [0x1032C] mov v23.16b, v23.16b
  [0x10330] ldr x9, [sp, #8]
  [0x10334] add x16, x9, x15
  [0x10338] str q23, [x16] ;; misaligned with debug data
  [0x1033C] ldr x9, [sp, #0x10]
  [0x10340] add x16, x9, x15
  [0x10344] ldr q23, [x16] ;; misaligned with debug data
  [0x10348] mov v23.16b, v23.16b
  [0x1034C] add x16, x10, x15
  [0x10350] str q23, [x16] ;; misaligned with debug data
  [0x10354] fmov x3, d23
  [0x10358] adrp x16, #0x17000
  [0x1035C] ldr s23, [x16, #0xef0]
  [0x10360] adrp x16, #0x17000
  [0x10364] ldr s22, [x16, #0xef4]
  [0x10368] mov v23.16b, v23.16b
  [0x1036C] mov v22.16b, v22.16b
  [0x10370] ldr x9, [sp, #8]
  [0x10374] add x16, x9, x15
  [0x10378] ldr s21, [x16] ;; misaligned with debug data
  [0x1037C] mov v21.16b, v21.16b
  [0x10380] fadd s21, s21, s23
  [0x10384] ldr x9, [sp, #8]
  [0x10388] add x16, x9, x15
  [0x1038C] str s21, [x16] ;; misaligned with debug data
  [0x10390] ldr x9, [sp, #8]
  [0x10394] add x16, x9, x15
  [0x10398] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x1039C] mov v21.16b, v21.16b
  [0x103A0] fadd s21, s21, s23
  [0x103A4] ldr x9, [sp, #8]
  [0x103A8] add x16, x9, x15
  [0x103AC] str s21, [x16, #4] ;; misaligned with debug data
  [0x103B0] ldr x9, [sp, #8]
  [0x103B4] add x16, x9, x15
  [0x103B8] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x103BC] mov v21.16b, v21.16b
  [0x103C0] fadd s21, s21, s23
  [0x103C4] ldr x9, [sp, #8]
  [0x103C8] add x16, x9, x15
  [0x103CC] str s21, [x16, #8] ;; misaligned with debug data
  [0x103D0] add x16, x10, x15
  [0x103D4] ldr s23, [x16] ;; misaligned with debug data
  [0x103D8] mov v23.16b, v23.16b
  [0x103DC] fadd s23, s23, s22
  [0x103E0] add x16, x10, x15
  [0x103E4] str s23, [x16] ;; misaligned with debug data
  [0x103E8] add x16, x10, x15
  [0x103EC] ldr s23, [x16, #4] ;; misaligned with debug data
  [0x103F0] mov v23.16b, v23.16b
  [0x103F4] fadd s23, s23, s22
  [0x103F8] add x16, x10, x15
  [0x103FC] str s23, [x16, #4] ;; misaligned with debug data
  [0x10400] add x16, x10, x15
  [0x10404] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x10408] mov v23.16b, v23.16b
  [0x1040C] fadd s23, s23, s22
  [0x10410] add x16, x10, x15
  [0x10414] str s23, [x16, #8] ;; misaligned with debug data
  [0x10418] ldr x3, [sp]
  [0x1041C] mov x3, x3
  [0x10420] movz x9, #0x1
  [0x10424] add x3, x3, x9
  [0x10428] mov x3, x3
  [0x1042C] str x3, [sp]
  [0x10430] add x16, x11, x15
  [0x10434] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10438] ldr x9, [sp]
  [0x1043C] cmp x9, x8
  [0x10440] b.lt #0x1007c
  [0x10444] mov x9, x14
  [0x10448] sub x9, x9, x15 ;; misaligned with debug data
  [0x1044C] mov x9, x9
  [0x10450] b #0x1045c
  [0x10454] mov x9, x14
  [0x10458] sub x9, x9, x15 ;; misaligned with debug data
  [0x1045C] mov x3, x12
  [0x10460] movz x9, #0x1
  [0x10464] add x3, x3, x9
  [0x10468] mov x12, x3
  [0x1046C] add x16, x5, x15
  [0x10470] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10474] cmp x12, x9
  [0x10478] b.lt #0x1001c
  [0x1047C] mov x9, x14
  [0x10480] sub x9, x9, x15 ;; misaligned with debug data
  [0x10484] add sp, sp, #0x30
  [0x10488] ldp x29, x30, [sp], #0x10
  [0x1048C] ret


[(method update-vis-volumes level-group)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x30
  [0x1000C] mov x7, x7
  [0x10010] str x7, [sp]
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] ldr w9, [x16]
  [0x10020] movz x7, #0
  [0x10024] adrp x6, #0x17000
  [0x10028] add x6, x6, #0xea4
  [0x1002C] sub x6, x6, x15
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
  [0x10060] movz x3, #0
  [0x10064] mov x3, x3
  [0x10068] str x3, [sp, #8]
  [0x1006C] b #0x104a4
  [0x10070] movz x8, #0xa30
  [0x10074] ldr x9, [sp, #8]
  [0x10078] mul x8, x8, x9
  [0x1007C] mov x8, x8
  [0x10080] movz x1, #0x60
  [0x10084] ldr x9, [sp]
  [0x10088] add x1, x1, x9
  [0x1008C] add x8, x8, x1
  [0x10090] mov x8, x8
  [0x10094] add x16, x8, x15
  [0x10098] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x1009C] adrp x1, #0x10000
  [0x100A0] add x1, x1, #0
  [0x100A4] cmp x9, x1
  [0x100A8] b.ne #0x10484
  [0x100AC] add x16, x8, x15
  [0x100B0] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x100B4] add x16, x9, x15
  [0x100B8] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x100BC] add x16, x9, x15
  [0x100C0] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x100C4] mov x3, x3
  [0x100C8] str x3, [sp, #0x10]
  [0x100CC] movz x3, #0
  [0x100D0] mov x3, x3
  [0x100D4] str x3, [sp, #0x18]
  [0x100D8] b #0x1045c
  [0x100DC] ldr x9, [sp, #0x18]
  [0x100E0] mov x8, x9
  [0x100E4] lsl x8, x8, #6
  [0x100E8] mov x8, x8
  [0x100EC] movz x1, #0xc
  [0x100F0] ldr x9, [sp, #0x10]
  [0x100F4] add x1, x1, x9
  [0x100F8] add x8, x8, x1
  [0x100FC] add x16, x8, x15
  [0x10100] ldr w3, [x16, #8] ;; misaligned with debug data
  [0x10104] mov x5, x3
  [0x10108] adrp x16, #0x10000
  [0x1010C] add x16, x16, #0
  [0x10110] ldr w9, [x16]
  [0x10114] add x16, x9, x15
  [0x10118] ldr w1, [x16, #0x34] ;; misaligned with debug data
  [0x1011C] adrp x6, #0x10000
  [0x10120] add x6, x6, #0
  [0x10124] adrp x2, #0x10000
  [0x10128] add x2, x2, #0
  [0x1012C] adrp x16, #0x17000
  [0x10130] ldr s23, [x16, #0xee8]
  [0x10134] mov x8, x14
  [0x10138] sub x8, x8, x15 ;; misaligned with debug data
  [0x1013C] mov x8, x8
  [0x10140] mov x9, x14
  [0x10144] sub x9, x9, x15 ;; misaligned with debug data
  [0x10148] mov x9, x9
  [0x1014C] adrp x16, #0x10000
  [0x10150] add x16, x16, #0
  [0x10154] ldr w10, [x16]
  [0x10158] mov x3, x1
  [0x1015C] mov x7, x5
  [0x10160] mov x6, x6
  [0x10164] mov x2, x2
  [0x10168] fmov w1, s23
  [0x1016C] sxtw x1, w1
  [0x10170] mov x8, x8
  [0x10174] mov x9, x9
  [0x10178] mov x10, x10
  [0x1017C] add x3, x3, x15
  [0x10180] stp x3, x5, [sp, #-0x10]!
  [0x10184] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10188] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1018C] blr x3 ;; misaligned with debug data
  [0x10190] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10194] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10198] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1019C] mov x0, x0
  [0x101A0] mov x0, x0
  [0x101A4] mov x0, x0
  [0x101A8] mov x3, x0
  [0x101AC] mov x10, x3
  [0x101B0] movz x3, #0x10
  [0x101B4] add x3, x3, x0
  [0x101B8] mov x3, x3
  [0x101BC] str x3, [sp, #0x20]
  [0x101C0] add x16, x5, x15
  [0x101C4] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x101C8] add x16, x9, x15
  [0x101CC] ldr w3, [x16, #0xc] ;; misaligned with debug data
  [0x101D0] mov x5, x3
  [0x101D4] movz x9, #0
  [0x101D8] mov x8, x14
  [0x101DC] sub x8, x8, x15 ;; misaligned with debug data
  [0x101E0] cmp x5, x9
  [0x101E4] b.eq #0x101f4
  [0x101E8] add x8, x14, #8
  [0x101EC] sub x8, x8, x15 ;; misaligned with debug data
  [0x101F0] mov x8, x8
  [0x101F4] mov x9, x8
  [0x101F8] mov x8, x14
  [0x101FC] sub x8, x8, x15 ;; misaligned with debug data
  [0x10200] cmp x9, x8
  [0x10204] b.eq #0x1025c
  [0x10208] adrp x16, #0x10000
  [0x1020C] add x16, x16, #0
  [0x10210] ldr w9, [x16]
  [0x10214] add x16, x5, x15
  [0x10218] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x1021C] adrp x16, #0x10000
  [0x10220] add x16, x16, #0
  [0x10224] ldr w6, [x16]
  [0x10228] mov x9, x9
  [0x1022C] mov x7, x7
  [0x10230] mov x6, x6
  [0x10234] add x9, x9, x15
  [0x10238] stp x3, x5, [sp, #-0x10]!
  [0x1023C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10240] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10244] blr x9 ;; misaligned with debug data
  [0x10248] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1024C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10250] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10254] mov x0, x0
  [0x10258] mov x9, x0
  [0x1025C] mov x8, x14
  [0x10260] sub x8, x8, x15 ;; misaligned with debug data
  [0x10264] cmp x9, x8
  [0x10268] b.eq #0x10280
  [0x1026C] mov x3, x12
  [0x10270] mov x11, x3
  [0x10274] mov x11, x5
  [0x10278] mov x3, x12
  [0x1027C] b #0x10288
  [0x10280] mov x3, x14
  [0x10284] sub x3, x3, x15 ;; misaligned with debug data
  [0x10288] mov x12, x3
  [0x1028C] mov x9, x14
  [0x10290] sub x9, x9, x15 ;; misaligned with debug data
  [0x10294] cmp x11, x9
  [0x10298] b.eq #0x1043c
  [0x1029C] adrp x16, #0x10000
  [0x102A0] add x16, x16, #0
  [0x102A4] ldr w9, [x16]
  [0x102A8] mov x7, x11
  [0x102AC] mov x8, x9
  [0x102B0] mov x7, x7
  [0x102B4] mov x6, x10
  [0x102B8] ldr x9, [sp, #0x20]
  [0x102BC] mov x2, x9
  [0x102C0] add x8, x8, x15
  [0x102C4] stp x3, x5, [sp, #-0x10]!
  [0x102C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102D0] blr x8 ;; misaligned with debug data
  [0x102D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102E0] mov x3, x3
  [0x102E4] add x16, x11, x15
  [0x102E8] ldr w3, [x16, #0x10] ;; misaligned with debug data
  [0x102EC] mov x3, x3
  [0x102F0] str x3, [sp, #0x28]
  [0x102F4] b #0x10418
  [0x102F8] adrp x16, #0x10000
  [0x102FC] add x16, x16, #0
  [0x10300] ldr w3, [x16]
  [0x10304] ldr x9, [sp, #0x28]
  [0x10308] add x16, x9, x15
  [0x1030C] ldr w5, [x16] ;; misaligned with debug data
  [0x10310] mov x3, x3
  [0x10314] mov x5, x5
  [0x10318] movz x9, #0
  [0x1031C] mov x8, x14
  [0x10320] sub x8, x8, x15 ;; misaligned with debug data
  [0x10324] cmp x5, x9
  [0x10328] b.eq #0x10338
  [0x1032C] add x8, x14, #8
  [0x10330] sub x8, x8, x15 ;; misaligned with debug data
  [0x10334] mov x8, x8
  [0x10338] mov x9, x8
  [0x1033C] mov x8, x14
  [0x10340] sub x8, x8, x15 ;; misaligned with debug data
  [0x10344] cmp x9, x8
  [0x10348] b.eq #0x103a0
  [0x1034C] adrp x16, #0x10000
  [0x10350] add x16, x16, #0
  [0x10354] ldr w9, [x16]
  [0x10358] add x16, x5, x15
  [0x1035C] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x10360] adrp x16, #0x10000
  [0x10364] add x16, x16, #0
  [0x10368] ldr w6, [x16]
  [0x1036C] mov x9, x9
  [0x10370] mov x7, x7
  [0x10374] mov x6, x6
  [0x10378] add x9, x9, x15
  [0x1037C] stp x3, x5, [sp, #-0x10]!
  [0x10380] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10384] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10388] blr x9 ;; misaligned with debug data
  [0x1038C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10390] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10394] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10398] mov x0, x0
  [0x1039C] mov x9, x0
  [0x103A0] mov x8, x14
  [0x103A4] sub x8, x8, x15 ;; misaligned with debug data
  [0x103A8] cmp x9, x8
  [0x103AC] b.eq #0x103b8
  [0x103B0] mov x5, x5
  [0x103B4] b #0x103c0
  [0x103B8] mov x5, x14
  [0x103BC] sub x5, x5, x15 ;; misaligned with debug data
  [0x103C0] mov x5, x5
  [0x103C4] mov x8, x3
  [0x103C8] mov x7, x5
  [0x103CC] mov x6, x10
  [0x103D0] ldr x9, [sp, #0x20]
  [0x103D4] mov x2, x9
  [0x103D8] add x8, x8, x15
  [0x103DC] stp x3, x5, [sp, #-0x10]!
  [0x103E0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103E4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103E8] blr x8 ;; misaligned with debug data
  [0x103EC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103F0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103F4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103F8] mov x3, x3
  [0x103FC] ldr x9, [sp, #0x28]
  [0x10400] add x16, x9, x15
  [0x10404] ldr w8, [x16] ;; misaligned with debug data
  [0x10408] add x16, x8, x15
  [0x1040C] ldr w3, [x16, #0xc] ;; misaligned with debug data
  [0x10410] mov x3, x3
  [0x10414] str x3, [sp, #0x28]
  [0x10418] mov x8, x14
  [0x1041C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10420] ldr x9, [sp, #0x28]
  [0x10424] cmp x9, x8
  [0x10428] b.ne #0x102f8
  [0x1042C] mov x9, x14
  [0x10430] sub x9, x9, x15 ;; misaligned with debug data
  [0x10434] mov x9, x9
  [0x10438] b #0x10444
  [0x1043C] mov x9, x14
  [0x10440] sub x9, x9, x15 ;; misaligned with debug data
  [0x10444] ldr x3, [sp, #0x18]
  [0x10448] mov x3, x3
  [0x1044C] movz x9, #0x1
  [0x10450] add x3, x3, x9
  [0x10454] mov x3, x3
  [0x10458] str x3, [sp, #0x18]
  [0x1045C] ldr x9, [sp, #0x10]
  [0x10460] add x16, x9, x15
  [0x10464] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10468] ldr x9, [sp, #0x18]
  [0x1046C] cmp x9, x8
  [0x10470] b.lt #0x100dc
  [0x10474] mov x9, x14
  [0x10478] sub x9, x9, x15 ;; misaligned with debug data
  [0x1047C] mov x9, x9
  [0x10480] b #0x1048c
  [0x10484] mov x9, x14
  [0x10488] sub x9, x9, x15 ;; misaligned with debug data
  [0x1048C] ldr x3, [sp, #8]
  [0x10490] mov x3, x3
  [0x10494] movz x9, #0x1
  [0x10498] add x3, x3, x9
  [0x1049C] mov x3, x3
  [0x104A0] str x3, [sp, #8]
  [0x104A4] ldr x9, [sp]
  [0x104A8] add x16, x9, x15
  [0x104AC] ldrsw x8, [x16] ;; misaligned with debug data
  [0x104B0] ldr x9, [sp, #8]
  [0x104B4] cmp x9, x8
  [0x104B8] b.lt #0x10070
  [0x104BC] mov x9, x14
  [0x104C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x104C4] add sp, sp, #0x30
  [0x104C8] ldp x29, x30, [sp], #0x10
  [0x104CC] ret


[(method birth bsp-header)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x12, x7
  [0x10010] add x16, x12, x15
  [0x10014] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x10018] movz x8, #0
  [0x1001C] cmp x9, x8
  [0x10020] b.eq #0x1003c
  [0x10024] add x16, x12, x15
  [0x10028] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1002C] add x16, x9, x15
  [0x10030] ldrsh x1, [x16, #2] ;; misaligned with debug data
  [0x10034] mov x1, x1
  [0x10038] b #0x10044
  [0x1003C] movz x1, #0
  [0x10040] mov x1, x1
  [0x10044] mov x1, x1
  [0x10048] add x16, x12, x15
  [0x1004C] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10050] add x16, x9, x15
  [0x10054] ldr w9, [x16, #0x118] ;; misaligned with debug data
  [0x10058] mov x8, x14
  [0x1005C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10060] cmp x9, x8
  [0x10064] b.ne #0x100dc
  [0x10068] adrp x7, #0x10000
  [0x1006C] add x7, x7, #0
  [0x10070] adrp x16, #0x10000
  [0x10074] add x16, x16, #0
  [0x10078] ldr w6, [x16]
  [0x1007C] adrp x16, #0x10000
  [0x10080] add x16, x16, #0
  [0x10084] ldr w9, [x16]
  [0x10088] add x16, x9, x15
  [0x1008C] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10090] mov x9, x9
  [0x10094] mov x7, x7
  [0x10098] mov x6, x6
  [0x1009C] mov x2, x1
  [0x100A0] add x9, x9, x15
  [0x100A4] stp x3, x5, [sp, #-0x10]!
  [0x100A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100B0] blr x9 ;; misaligned with debug data
  [0x100B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100C0] mov x0, x0
  [0x100C4] add x16, x12, x15
  [0x100C8] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x100CC] add x16, x9, x15
  [0x100D0] str w0, [x16, #0x118] ;; misaligned with debug data
  [0x100D4] mov x0, x0
  [0x100D8] b #0x10184
  [0x100DC] add x16, x12, x15
  [0x100E0] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x100E4] add x16, x9, x15
  [0x100E8] ldr w9, [x16, #0x118] ;; misaligned with debug data
  [0x100EC] add x16, x9, x15
  [0x100F0] ldrsw x9, [x16, #4] ;; misaligned with debug data
  [0x100F4] cmp x9, x1
  [0x100F8] b.ge #0x1017c
  [0x100FC] adrp x16, #0x10000
  [0x10100] add x16, x16, #0
  [0x10104] ldr w9, [x16]
  [0x10108] movz x7, #0
  [0x1010C] adrp x6, #0x14000
  [0x10110] add x6, x6, #0xe4
  [0x10114] sub x6, x6, x15
  [0x10118] add x16, x12, x15
  [0x1011C] ldr w2, [x16, #0x78] ;; misaligned with debug data
  [0x10120] add x16, x12, x15
  [0x10124] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x10128] add x16, x8, x15
  [0x1012C] ldr w8, [x16, #0x118] ;; misaligned with debug data
  [0x10130] add x16, x8, x15
  [0x10134] ldrsw x8, [x16, #4] ;; misaligned with debug data
  [0x10138] mov x9, x9
  [0x1013C] mov x7, x7
  [0x10140] mov x6, x6
  [0x10144] mov x2, x2
  [0x10148] mov x1, x1
  [0x1014C] mov x8, x8
  [0x10150] add x9, x9, x15
  [0x10154] stp x3, x5, [sp, #-0x10]!
  [0x10158] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1015C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10160] blr x9 ;; misaligned with debug data
  [0x10164] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10168] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1016C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10170] mov x0, x0
  [0x10174] mov x0, x0
  [0x10178] b #0x10184
  [0x1017C] mov x0, x14
  [0x10180] sub x0, x0, x15 ;; misaligned with debug data
  [0x10184] movz x9, #0
  [0x10188] add x16, x12, x15
  [0x1018C] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x10190] add x16, x8, x15
  [0x10194] ldr w8, [x16, #0x118] ;; misaligned with debug data
  [0x10198] add x16, x8, x15
  [0x1019C] str w9, [x16] ;; misaligned with debug data
  [0x101A0] add x16, x12, x15
  [0x101A4] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x101A8] movz x8, #0
  [0x101AC] cmp x9, x8
  [0x101B0] b.eq #0x102bc
  [0x101B4] movz x3, #0
  [0x101B8] mov x3, x3
  [0x101BC] b #0x10294
  [0x101C0] mov x9, x3
  [0x101C4] lsl x9, x9, #2
  [0x101C8] mov x9, x9
  [0x101CC] add x16, x12, x15
  [0x101D0] ldr w8, [x16, #0xa8] ;; misaligned with debug data
  [0x101D4] add x9, x9, x8
  [0x101D8] add x16, x9, x15
  [0x101DC] ldr w9, [x16] ;; misaligned with debug data
  [0x101E0] mov x9, x9
  [0x101E4] movz x8, #0xffff
  [0x101E8] mov x9, x9
  [0x101EC] and x9, x9, x8
  [0x101F0] mov x9, x9
  [0x101F4] lsl x9, x9, #5
  [0x101F8] mov x9, x9
  [0x101FC] movz x8, #0x20
  [0x10200] add x16, x12, x15
  [0x10204] ldr w1, [x16, #0x6c] ;; misaligned with debug data
  [0x10208] add x8, x8, x1
  [0x1020C] add x9, x9, x8
  [0x10210] add x16, x9, x15
  [0x10214] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x10218] mov x7, x7
  [0x1021C] adrp x16, #0x10000
  [0x10220] add x16, x16, #0
  [0x10224] ldr w6, [x16]
  [0x10228] add x16, x12, x15
  [0x1022C] ldr w2, [x16, #0x78] ;; misaligned with debug data
  [0x10230] add x16, x7, x15
  [0x10234] ldr w1, [x16, #0x2c] ;; misaligned with debug data
  [0x10238] mov x1, x1
  [0x1023C] add x16, x7, x15
  [0x10240] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10244] add x16, x9, x15
  [0x10248] ldr w9, [x16, #0x70] ;; misaligned with debug data
  [0x1024C] mov x9, x9
  [0x10250] mov x7, x7
  [0x10254] mov x6, x6
  [0x10258] mov x2, x2
  [0x1025C] mov x1, x1
  [0x10260] add x9, x9, x15
  [0x10264] stp x3, x5, [sp, #-0x10]!
  [0x10268] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1026C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10270] blr x9 ;; misaligned with debug data
  [0x10274] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10278] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1027C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10280] mov x5, x5
  [0x10284] mov x3, x3
  [0x10288] movz x9, #0x1
  [0x1028C] add x3, x3, x9
  [0x10290] mov x3, x3
  [0x10294] add x16, x12, x15
  [0x10298] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x1029C] add x16, x9, x15
  [0x102A0] ldrsh x9, [x16, #2] ;; misaligned with debug data
  [0x102A4] cmp x3, x9
  [0x102A8] b.lt #0x101c0
  [0x102AC] mov x9, x14
  [0x102B0] sub x9, x9, x15 ;; misaligned with debug data
  [0x102B4] mov x9, x9
  [0x102B8] b #0x102c4
  [0x102BC] mov x9, x14
  [0x102C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x102C4] add x16, x12, x15
  [0x102C8] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x102CC] movz x8, #0
  [0x102D0] cmp x9, x8
  [0x102D4] b.eq #0x102f0
  [0x102D8] add x16, x12, x15
  [0x102DC] ldr w9, [x16, #0x98] ;; misaligned with debug data
  [0x102E0] add x16, x9, x15
  [0x102E4] ldrsh x1, [x16, #2] ;; misaligned with debug data
  [0x102E8] mov x1, x1
  [0x102EC] b #0x102f8
  [0x102F0] movz x1, #0
  [0x102F4] mov x1, x1
  [0x102F8] mov x1, x1
  [0x102FC] add x16, x12, x15
  [0x10300] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10304] add x16, x9, x15
  [0x10308] ldr w9, [x16, #0x11c] ;; misaligned with debug data
  [0x1030C] mov x8, x14
  [0x10310] sub x8, x8, x15 ;; misaligned with debug data
  [0x10314] cmp x9, x8
  [0x10318] b.ne #0x10390
  [0x1031C] adrp x7, #0x10000
  [0x10320] add x7, x7, #0
  [0x10324] adrp x16, #0x10000
  [0x10328] add x16, x16, #0
  [0x1032C] ldr w6, [x16]
  [0x10330] adrp x16, #0x10000
  [0x10334] add x16, x16, #0
  [0x10338] ldr w9, [x16]
  [0x1033C] add x16, x9, x15
  [0x10340] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10344] mov x9, x9
  [0x10348] mov x7, x7
  [0x1034C] mov x6, x6
  [0x10350] mov x2, x1
  [0x10354] add x9, x9, x15
  [0x10358] stp x3, x5, [sp, #-0x10]!
  [0x1035C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10360] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10364] blr x9 ;; misaligned with debug data
  [0x10368] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1036C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10370] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10374] mov x0, x0
  [0x10378] add x16, x12, x15
  [0x1037C] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10380] add x16, x9, x15
  [0x10384] str w0, [x16, #0x11c] ;; misaligned with debug data
  [0x10388] mov x0, x0
  [0x1038C] b #0x10438
  [0x10390] add x16, x12, x15
  [0x10394] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10398] add x16, x9, x15
  [0x1039C] ldr w9, [x16, #0x11c] ;; misaligned with debug data
  [0x103A0] add x16, x9, x15
  [0x103A4] ldrsw x9, [x16, #4] ;; misaligned with debug data
  [0x103A8] cmp x9, x1
  [0x103AC] b.ge #0x10430
  [0x103B0] adrp x16, #0x10000
  [0x103B4] add x16, x16, #0
  [0x103B8] ldr w9, [x16]
  [0x103BC] movz x7, #0
  [0x103C0] adrp x6, #0x14000
  [0x103C4] add x6, x6, #0x144
  [0x103C8] sub x6, x6, x15
  [0x103CC] add x16, x12, x15
  [0x103D0] ldr w2, [x16, #0x78] ;; misaligned with debug data
  [0x103D4] add x16, x12, x15
  [0x103D8] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x103DC] add x16, x8, x15
  [0x103E0] ldr w8, [x16, #0x11c] ;; misaligned with debug data
  [0x103E4] add x16, x8, x15
  [0x103E8] ldrsw x8, [x16, #4] ;; misaligned with debug data
  [0x103EC] mov x9, x9
  [0x103F0] mov x7, x7
  [0x103F4] mov x6, x6
  [0x103F8] mov x2, x2
  [0x103FC] mov x1, x1
  [0x10400] mov x8, x8
  [0x10404] add x9, x9, x15
  [0x10408] stp x3, x5, [sp, #-0x10]!
  [0x1040C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10410] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10414] blr x9 ;; misaligned with debug data
  [0x10418] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1041C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10420] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10424] mov x0, x0
  [0x10428] mov x0, x0
  [0x1042C] b #0x10438
  [0x10430] mov x0, x14
  [0x10434] sub x0, x0, x15 ;; misaligned with debug data
  [0x10438] movz x9, #0
  [0x1043C] add x16, x12, x15
  [0x10440] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x10444] add x16, x8, x15
  [0x10448] ldr w8, [x16, #0x11c] ;; misaligned with debug data
  [0x1044C] add x16, x8, x15
  [0x10450] str w9, [x16] ;; misaligned with debug data
  [0x10454] add x16, x12, x15
  [0x10458] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x1045C] add x16, x9, x15
  [0x10460] ldr w3, [x16, #0x11c] ;; misaligned with debug data
  [0x10464] add x16, x12, x15
  [0x10468] ldr w5, [x16, #0x98] ;; misaligned with debug data
  [0x1046C] mov x11, x3
  [0x10470] mov x5, x5
  [0x10474] movz x9, #0
  [0x10478] cmp x5, x9
  [0x1047C] b.eq #0x10560
  [0x10480] movz x3, #0
  [0x10484] mov x3, x3
  [0x10488] b #0x10540
  [0x1048C] mov x9, x3
  [0x10490] lsl x9, x9, #5
  [0x10494] mov x9, x9
  [0x10498] movz x8, #0x20
  [0x1049C] add x8, x8, x5
  [0x104A0] add x9, x9, x8
  [0x104A4] add x16, x9, x15
  [0x104A8] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x104AC] mov x7, x7
  [0x104B0] add x16, x11, x15
  [0x104B4] ldrsw x9, [x16] ;; misaligned with debug data
  [0x104B8] mov x9, x9
  [0x104BC] lsl x9, x9, #4
  [0x104C0] mov x9, x9
  [0x104C4] movz x8, #0xc
  [0x104C8] add x8, x8, x11
  [0x104CC] add x9, x9, x8
  [0x104D0] add x16, x7, x15
  [0x104D4] str w9, [x16, #0x14] ;; misaligned with debug data
  [0x104D8] add x16, x7, x15
  [0x104DC] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x104E0] add x16, x9, x15
  [0x104E4] ldr w9, [x16, #0x80] ;; misaligned with debug data
  [0x104E8] mov x9, x9
  [0x104EC] mov x7, x7
  [0x104F0] add x9, x9, x15
  [0x104F4] stp x3, x5, [sp, #-0x10]!
  [0x104F8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104FC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10500] blr x9 ;; misaligned with debug data
  [0x10504] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10508] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1050C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10510] mov x10, x10
  [0x10514] add x16, x11, x15
  [0x10518] ldrsw x9, [x16] ;; misaligned with debug data
  [0x1051C] mov x9, x9
  [0x10520] movz x8, #0x1
  [0x10524] add x9, x9, x8
  [0x10528] add x16, x11, x15
  [0x1052C] str w9, [x16] ;; misaligned with debug data
  [0x10530] mov x3, x3
  [0x10534] movz x9, #0x1
  [0x10538] add x3, x3, x9
  [0x1053C] mov x3, x3
  [0x10540] add x16, x5, x15
  [0x10544] ldrsh x9, [x16, #2] ;; misaligned with debug data
  [0x10548] cmp x3, x9
  [0x1054C] b.lt #0x1048c
  [0x10550] mov x9, x14
  [0x10554] sub x9, x9, x15 ;; misaligned with debug data
  [0x10558] mov x9, x9
  [0x1055C] b #0x10568
  [0x10560] mov x9, x14
  [0x10564] sub x9, x9, x15 ;; misaligned with debug data
  [0x10568] add x16, x12, x15
  [0x1056C] ldr w3, [x16, #0x70] ;; misaligned with debug data
  [0x10570] mov x5, x3
  [0x10574] movz x9, #0
  [0x10578] cmp x5, x9
  [0x1057C] b.eq #0x10618
  [0x10580] movz x3, #0
  [0x10584] mov x3, x3
  [0x10588] b #0x105f8
  [0x1058C] movz x9, #0xc
  [0x10590] mov x8, x3
  [0x10594] lsl x8, x8, #2
  [0x10598] add x8, x8, x9
  [0x1059C] mov x8, x8
  [0x105A0] add x8, x8, x5
  [0x105A4] add x16, x8, x15
  [0x105A8] ldr w7, [x16] ;; misaligned with debug data
  [0x105AC] add x16, x7, x15
  [0x105B0] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x105B4] add x16, x9, x15
  [0x105B8] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x105BC] mov x9, x9
  [0x105C0] mov x7, x7
  [0x105C4] add x9, x9, x15
  [0x105C8] stp x3, x5, [sp, #-0x10]!
  [0x105CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x105D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x105D4] blr x9 ;; misaligned with debug data
  [0x105D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x105DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x105E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x105E4] mov x0, x0
  [0x105E8] mov x3, x3
  [0x105EC] movz x9, #0x1
  [0x105F0] add x3, x3, x9
  [0x105F4] mov x3, x3
  [0x105F8] add x16, x5, x15
  [0x105FC] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10600] cmp x3, x9
  [0x10604] b.lt #0x1058c
  [0x10608] mov x9, x14
  [0x1060C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10610] mov x9, x9
  [0x10614] b #0x10620
  [0x10618] mov x9, x14
  [0x1061C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10620] add sp, sp, #0x10
  [0x10624] ldp x29, x30, [sp], #0x10
  [0x10628] ret


[update-actor-vis-box]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] mov x6, x6
  [0x10014] mov x2, x2
  [0x10018] mov x9, x7
  [0x1001C] mov x8, x14
  [0x10020] sub x8, x8, x15 ;; misaligned with debug data
  [0x10024] cmp x9, x8
  [0x10028] b.eq #0x10058
  [0x1002C] add x16, x7, x15
  [0x10030] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x10034] movz x8, #0
  [0x10038] mov x1, x14
  [0x1003C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10040] cmp x9, x8
  [0x10044] b.eq #0x10054
  [0x10048] add x1, x14, #8
  [0x1004C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10050] mov x1, x1
  [0x10054] mov x9, x1
  [0x10058] mov x8, x14
  [0x1005C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10060] cmp x9, x8
  [0x10064] b.eq #0x101d8
  [0x10068] mov x9, sp
  [0x1006C] sub x9, x9, x15
  [0x10070] movz x8, #0x6c
  [0x10074] add x16, x7, x15
  [0x10078] ldr w1, [x16, #0x74] ;; misaligned with debug data
  [0x1007C] add x8, x8, x1
  [0x10080] movz x1, #0x7c
  [0x10084] add x16, x7, x15
  [0x10088] ldr w0, [x16, #0x74] ;; misaligned with debug data
  [0x1008C] add x1, x1, x0
  [0x10090] mov x9, x9
  [0x10094] mov x8, x8
  [0x10098] mov x1, x1
  [0x1009C] add x16, x8, x15
  [0x100A0] ldr q22, [x16] ;; misaligned with debug data
  [0x100A4] add x16, x1, x15
  [0x100A8] ldr q21, [x16] ;; misaligned with debug data
  [0x100AC] adrp x16, #0x18000
  [0x100B0] ldr q23, [x16, #0xe90]
  [0x100B4] fadd v22.4s, v22.4s, v21.4s
  [0x100B8] ins v22.s[3], v23.s[3]
  [0x100BC] add x16, x9, x15
  [0x100C0] str q22, [x16] ;; misaligned with debug data
  [0x100C4] add x16, x7, x15
  [0x100C8] ldr w8, [x16, #0x74] ;; misaligned with debug data
  [0x100CC] add x16, x8, x15
  [0x100D0] ldr s23, [x16, #0x88] ;; misaligned with debug data
  [0x100D4] mov x9, x9
  [0x100D8] mov v23.16b, v23.16b
  [0x100DC] add x16, x6, x15
  [0x100E0] ldr s22, [x16] ;; misaligned with debug data
  [0x100E4] mov v22.16b, v22.16b
  [0x100E8] add x16, x9, x15
  [0x100EC] ldr s21, [x16] ;; misaligned with debug data
  [0x100F0] mov v21.16b, v21.16b
  [0x100F4] fsub s21, s21, s23
  [0x100F8] fmin s22, s22, s21
  [0x100FC] add x16, x6, x15
  [0x10100] str s22, [x16] ;; misaligned with debug data
  [0x10104] add x16, x6, x15
  [0x10108] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x1010C] mov v22.16b, v22.16b
  [0x10110] add x16, x9, x15
  [0x10114] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x10118] mov v21.16b, v21.16b
  [0x1011C] fsub s21, s21, s23
  [0x10120] fmin s22, s22, s21
  [0x10124] add x16, x6, x15
  [0x10128] str s22, [x16, #4] ;; misaligned with debug data
  [0x1012C] add x16, x6, x15
  [0x10130] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x10134] mov v22.16b, v22.16b
  [0x10138] add x16, x9, x15
  [0x1013C] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x10140] mov v21.16b, v21.16b
  [0x10144] fsub s21, s21, s23
  [0x10148] fmin s22, s22, s21
  [0x1014C] add x16, x6, x15
  [0x10150] str s22, [x16, #8] ;; misaligned with debug data
  [0x10154] add x16, x2, x15
  [0x10158] ldr s22, [x16] ;; misaligned with debug data
  [0x1015C] mov v22.16b, v22.16b
  [0x10160] add x16, x9, x15
  [0x10164] ldr s21, [x16] ;; misaligned with debug data
  [0x10168] mov v21.16b, v21.16b
  [0x1016C] fadd s21, s21, s23
  [0x10170] fmax s22, s22, s21
  [0x10174] add x16, x2, x15
  [0x10178] str s22, [x16] ;; misaligned with debug data
  [0x1017C] add x16, x2, x15
  [0x10180] ldr s22, [x16, #4] ;; misaligned with debug data
  [0x10184] mov v22.16b, v22.16b
  [0x10188] add x16, x9, x15
  [0x1018C] ldr s21, [x16, #4] ;; misaligned with debug data
  [0x10190] mov v21.16b, v21.16b
  [0x10194] fadd s21, s21, s23
  [0x10198] fmax s22, s22, s21
  [0x1019C] add x16, x2, x15
  [0x101A0] str s22, [x16, #4] ;; misaligned with debug data
  [0x101A4] add x16, x2, x15
  [0x101A8] ldr s22, [x16, #8] ;; misaligned with debug data
  [0x101AC] mov v22.16b, v22.16b
  [0x101B0] add x16, x9, x15
  [0x101B4] ldr s21, [x16, #8] ;; misaligned with debug data
  [0x101B8] mov v21.16b, v21.16b
  [0x101BC] fadd s21, s21, s23
  [0x101C0] fmax s22, s22, s21
  [0x101C4] add x16, x2, x15
  [0x101C8] str s22, [x16, #8] ;; misaligned with debug data
  [0x101CC] fmov w9, s22
  [0x101D0] sxtw x9, w9
  [0x101D4] b #0x101e0
  [0x101D8] mov x9, x14
  [0x101DC] sub x9, x9, x15 ;; misaligned with debug data
  [0x101E0] movz x9, #0
  [0x101E4] add sp, sp, #0x10
  [0x101E8] ldp x29, x30, [sp], #0x10
  [0x101EC] ret


[(method remove-from-level! entity)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] add x16, x7, x15
  [0x10014] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10018] mov x9, x9
  [0x1001C] add x16, x9, x15
  [0x10020] ldr w8, [x16, #4] ;; misaligned with debug data
  [0x10024] cmp x8, x9
  [0x10028] b.ne #0x10044
  [0x1002C] mov x9, x14
  [0x10030] sub x9, x9, x15 ;; misaligned with debug data
  [0x10034] add x16, x6, x15
  [0x10038] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x1003C] mov x9, x9
  [0x10040] b #0x100a8
  [0x10044] add x16, x9, x15
  [0x10048] ldr w8, [x16] ;; misaligned with debug data
  [0x1004C] add x16, x9, x15
  [0x10050] ldr w1, [x16, #4] ;; misaligned with debug data
  [0x10054] add x16, x1, x15
  [0x10058] str w8, [x16] ;; misaligned with debug data
  [0x1005C] add x16, x9, x15
  [0x10060] ldr w8, [x16, #4] ;; misaligned with debug data
  [0x10064] add x16, x9, x15
  [0x10068] ldr w1, [x16] ;; misaligned with debug data
  [0x1006C] add x16, x1, x15
  [0x10070] str w8, [x16, #4] ;; misaligned with debug data
  [0x10074] add x16, x6, x15
  [0x10078] ldr w8, [x16, #0xc] ;; misaligned with debug data
  [0x1007C] cmp x8, x9
  [0x10080] b.ne #0x1009c
  [0x10084] add x16, x9, x15
  [0x10088] ldr w9, [x16] ;; misaligned with debug data
  [0x1008C] add x16, x6, x15
  [0x10090] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x10094] mov x9, x9
  [0x10098] b #0x100a4
  [0x1009C] mov x9, x14
  [0x100A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x100A4] mov x9, x9
  [0x100A8] mov x0, x7
  [0x100AC] ldp x29, x30, [sp], #0x10
  [0x100B0] ret


[(method debug-print-entities level-group)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x12, x6
  [0x10014] mov x11, x2
  [0x10018] adrp x16, #0x10000
  [0x1001C] add x16, x16, #0
  [0x10020] ldr w9, [x16]
  [0x10024] add x7, x14, #8
  [0x10028] sub x7, x7, x15 ;; misaligned with debug data
  [0x1002C] adrp x6, #0x18000
  [0x10030] add x6, x6, #0xd84
  [0x10034] sub x6, x6, x15
  [0x10038] movz x2, #0
  [0x1003C] movz x1, #0
  [0x10040] movz x8, #0
  [0x10044] mov x9, x9
  [0x10048] mov x7, x7
  [0x1004C] mov x6, x6
  [0x10050] mov x2, x2
  [0x10054] mov x1, x1
  [0x10058] mov x8, x8
  [0x1005C] add x9, x9, x15
  [0x10060] stp x3, x5, [sp, #-0x10]!
  [0x10064] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10068] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1006C] blr x9 ;; misaligned with debug data
  [0x10070] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10074] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10078] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1007C] mov x0, x0
  [0x10080] movz x3, #0
  [0x10084] mov x10, x3
  [0x10088] b #0x1030c
  [0x1008C] movz x3, #0xa30
  [0x10090] mul x3, x3, x10
  [0x10094] mov x3, x3
  [0x10098] movz x9, #0x60
  [0x1009C] add x9, x9, x5
  [0x100A0] add x3, x3, x9
  [0x100A4] mov x3, x3
  [0x100A8] str x3, [sp]
  [0x100AC] ldr x9, [sp]
  [0x100B0] add x16, x9, x15
  [0x100B4] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x100B8] adrp x9, #0x10000
  [0x100BC] add x9, x9, #0
  [0x100C0] cmp x8, x9
  [0x100C4] b.ne #0x102f4
  [0x100C8] mov x9, x12
  [0x100CC] adrp x8, #0x10000
  [0x100D0] add x8, x8, #0
  [0x100D4] cmp x9, x8
  [0x100D8] b.ne #0x10220
  [0x100DC] adrp x16, #0x10000
  [0x100E0] add x16, x16, #0
  [0x100E4] ldr w8, [x16]
  [0x100E8] add x7, x14, #8
  [0x100EC] sub x7, x7, x15 ;; misaligned with debug data
  [0x100F0] adrp x6, #0x18000
  [0x100F4] add x6, x6, #0xe54
  [0x100F8] sub x6, x6, x15
  [0x100FC] ldr x9, [sp]
  [0x10100] add x16, x9, x15
  [0x10104] ldr w2, [x16] ;; misaligned with debug data
  [0x10108] mov x8, x8
  [0x1010C] mov x7, x7
  [0x10110] mov x6, x6
  [0x10114] mov x2, x2
  [0x10118] add x8, x8, x15
  [0x1011C] stp x3, x5, [sp, #-0x10]!
  [0x10120] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10124] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10128] blr x8 ;; misaligned with debug data
  [0x1012C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10130] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10134] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10138] mov x0, x0
  [0x1013C] movz x3, #0
  [0x10140] mov x3, x3
  [0x10144] b #0x101ec
  [0x10148] adrp x16, #0x10000
  [0x1014C] add x16, x16, #0
  [0x10150] ldr w8, [x16]
  [0x10154] add x7, x14, #8
  [0x10158] sub x7, x7, x15 ;; misaligned with debug data
  [0x1015C] adrp x6, #0x18000
  [0x10160] add x6, x6, #0xe74
  [0x10164] sub x6, x6, x15
  [0x10168] movz x9, #0xc
  [0x1016C] mov x1, x3
  [0x10170] lsl x1, x1, #2
  [0x10174] add x1, x1, x9
  [0x10178] mov x1, x1
  [0x1017C] ldr x9, [sp]
  [0x10180] add x16, x9, x15
  [0x10184] ldr w2, [x16, #0x30] ;; misaligned with debug data
  [0x10188] add x16, x2, x15
  [0x1018C] ldr w9, [x16, #8] ;; misaligned with debug data
  [0x10190] add x1, x1, x9
  [0x10194] add x16, x1, x15
  [0x10198] ldr w9, [x16] ;; misaligned with debug data
  [0x1019C] add x16, x9, x15
  [0x101A0] ldr w1, [x16, #4] ;; misaligned with debug data
  [0x101A4] mov x8, x8
  [0x101A8] mov x7, x7
  [0x101AC] mov x6, x6
  [0x101B0] mov x2, x3
  [0x101B4] mov x1, x1
  [0x101B8] add x8, x8, x15
  [0x101BC] stp x3, x5, [sp, #-0x10]!
  [0x101C0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101C4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101C8] blr x8 ;; misaligned with debug data
  [0x101CC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101D0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101D4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101D8] mov x0, x0
  [0x101DC] mov x3, x3
  [0x101E0] movz x9, #0x1
  [0x101E4] add x3, x3, x9
  [0x101E8] mov x3, x3
  [0x101EC] ldr x9, [sp]
  [0x101F0] add x16, x9, x15
  [0x101F4] ldr w8, [x16, #0x30] ;; misaligned with debug data
  [0x101F8] add x16, x8, x15
  [0x101FC] ldr w9, [x16, #8] ;; misaligned with debug data
  [0x10200] add x16, x9, x15
  [0x10204] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10208] cmp x3, x9
  [0x1020C] b.lt #0x10148
  [0x10210] mov x9, x14
  [0x10214] sub x9, x9, x15 ;; misaligned with debug data
  [0x10218] mov x9, x9
  [0x1021C] b #0x102ec
  [0x10220] ldr x9, [sp]
  [0x10224] add x16, x9, x15
  [0x10228] ldr w8, [x16, #0x2c] ;; misaligned with debug data
  [0x1022C] add x16, x8, x15
  [0x10230] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10234] add x16, x9, x15
  [0x10238] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x1023C] mov x3, x3
  [0x10240] str x3, [sp, #8]
  [0x10244] movz x3, #0
  [0x10248] mov x3, x3
  [0x1024C] b #0x102cc
  [0x10250] mov x9, x3
  [0x10254] lsl x9, x9, #6
  [0x10258] mov x8, x9
  [0x1025C] movz x1, #0xc
  [0x10260] ldr x9, [sp, #8]
  [0x10264] add x1, x1, x9
  [0x10268] add x8, x8, x1
  [0x1026C] add x16, x8, x15
  [0x10270] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x10274] mov x7, x7
  [0x10278] add x16, x7, x15
  [0x1027C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10280] add x16, x9, x15
  [0x10284] ldr w9, [x16, #0x84] ;; misaligned with debug data
  [0x10288] mov x8, x9
  [0x1028C] mov x7, x7
  [0x10290] mov x6, x12
  [0x10294] mov x2, x11
  [0x10298] add x8, x8, x15
  [0x1029C] stp x3, x5, [sp, #-0x10]!
  [0x102A0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102A4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102A8] blr x8 ;; misaligned with debug data
  [0x102AC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x102B0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x102B4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x102B8] mov x9, x9
  [0x102BC] mov x3, x3
  [0x102C0] movz x9, #0x1
  [0x102C4] add x3, x3, x9
  [0x102C8] mov x3, x3
  [0x102CC] ldr x9, [sp, #8]
  [0x102D0] add x16, x9, x15
  [0x102D4] ldrsw x8, [x16] ;; misaligned with debug data
  [0x102D8] cmp x3, x8
  [0x102DC] b.lt #0x10250
  [0x102E0] mov x9, x14
  [0x102E4] sub x9, x9, x15 ;; misaligned with debug data
  [0x102E8] mov x9, x9
  [0x102EC] mov x9, x9
  [0x102F0] b #0x102fc
  [0x102F4] mov x9, x14
  [0x102F8] sub x9, x9, x15 ;; misaligned with debug data
  [0x102FC] mov x3, x10
  [0x10300] movz x9, #0x1
  [0x10304] add x3, x3, x9
  [0x10308] mov x10, x3
  [0x1030C] add x16, x5, x15
  [0x10310] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10314] cmp x10, x9
  [0x10318] b.lt #0x1008c
  [0x1031C] mov x9, x14
  [0x10320] sub x9, x9, x15 ;; misaligned with debug data
  [0x10324] add sp, sp, #0x10
  [0x10328] ldp x29, x30, [sp], #0x10
  [0x1032C] ret


[(method print process)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w0, [x16]
  [0x1001C] add x7, x14, #8
  [0x10020] sub x7, x7, x15 ;; misaligned with debug data
  [0x10024] adrp x6, #0x19000
  [0x10028] add x6, x6, #0xbe4
  [0x1002C] sub x6, x6, x15
  [0x10030] add x16, x3, x15
  [0x10034] ldur w2, [x16, #-4] ;; misaligned with debug data
  [0x10038] add x16, x3, x15
  [0x1003C] ldr w1, [x16] ;; misaligned with debug data
  [0x10040] add x16, x3, x15
  [0x10044] ldr w8, [x16, #0x20] ;; misaligned with debug data
  [0x10048] add x16, x3, x15
  [0x1004C] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10050] mov x5, x14
  [0x10054] sub x5, x5, x15 ;; misaligned with debug data
  [0x10058] cmp x9, x5
  [0x1005C] b.eq #0x10078
  [0x10060] add x16, x3, x15
  [0x10064] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10068] add x16, x9, x15
  [0x1006C] ldr w9, [x16] ;; misaligned with debug data
  [0x10070] mov x9, x9
  [0x10074] b #0x10080
  [0x10078] mov x9, x14
  [0x1007C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10080] mov x5, x0
  [0x10084] mov x7, x7
  [0x10088] mov x6, x6
  [0x1008C] mov x2, x2
  [0x10090] mov x1, x1
  [0x10094] mov x8, x8
  [0x10098] mov x9, x9
  [0x1009C] add x5, x5, x15
  [0x100A0] stp x3, x5, [sp, #-0x10]!
  [0x100A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100AC] blr x5 ;; misaligned with debug data
  [0x100B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100BC] mov x0, x0
  [0x100C0] adrp x16, #0x10000
  [0x100C4] add x16, x16, #0
  [0x100C8] ldr w9, [x16]
  [0x100CC] add x6, x14, #8
  [0x100D0] sub x6, x6, x15 ;; misaligned with debug data
  [0x100D4] mov x9, x9
  [0x100D8] mov x7, x3
  [0x100DC] mov x6, x6
  [0x100E0] add x9, x9, x15
  [0x100E4] stp x3, x5, [sp, #-0x10]!
  [0x100E8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100EC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100F0] blr x9 ;; misaligned with debug data
  [0x100F4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100F8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100FC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10100] mov x5, x5
  [0x10104] adrp x16, #0x10000
  [0x10108] add x16, x16, #0
  [0x1010C] ldr w0, [x16]
  [0x10110] add x7, x14, #8
  [0x10114] sub x7, x7, x15 ;; misaligned with debug data
  [0x10118] adrp x6, #0x19000
  [0x1011C] add x6, x6, #0xc14
  [0x10120] sub x6, x6, x15
  [0x10124] add x16, x3, x15
  [0x10128] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x1012C] add x16, x9, x15
  [0x10130] ldr w2, [x16, #0x1c] ;; misaligned with debug data
  [0x10134] mov x2, x2
  [0x10138] mov x2, x2
  [0x1013C] add x16, x3, x15
  [0x10140] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10144] add x16, x9, x15
  [0x10148] ldr w9, [x16, #0x18] ;; misaligned with debug data
  [0x1014C] mov x9, x9
  [0x10150] mov x9, x9
  [0x10154] sub x2, x2, x9
  [0x10158] add x16, x3, x15
  [0x1015C] ldr w9, [x16, #0x28] ;; misaligned with debug data
  [0x10160] add x16, x9, x15
  [0x10164] ldrsw x1, [x16, #0x20] ;; misaligned with debug data
  [0x10168] add x16, x3, x15
  [0x1016C] ldrsw x8, [x16, #0x44] ;; misaligned with debug data
  [0x10170] mov x8, x8
  [0x10174] add x16, x3, x15
  [0x10178] ldr w9, [x16, #0x50] ;; misaligned with debug data
  [0x1017C] mov x9, x9
  [0x10180] mov x9, x9
  [0x10184] add x16, x3, x15
  [0x10188] ldr w5, [x16, #0x54] ;; misaligned with debug data
  [0x1018C] mov x5, x5
  [0x10190] mov x5, x5
  [0x10194] sub x9, x9, x5
  [0x10198] sub x8, x8, x9
  [0x1019C] add x16, x3, x15
  [0x101A0] ldrsw x9, [x16, #0x44] ;; misaligned with debug data
  [0x101A4] mov x5, x0
  [0x101A8] mov x7, x7
  [0x101AC] mov x6, x6
  [0x101B0] mov x2, x2
  [0x101B4] mov x1, x1
  [0x101B8] mov x8, x8
  [0x101BC] mov x9, x9
  [0x101C0] mov x10, x3
  [0x101C4] add x5, x5, x15
  [0x101C8] stp x3, x5, [sp, #-0x10]!
  [0x101CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101D4] blr x5 ;; misaligned with debug data
  [0x101D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101E4] mov x0, x0
  [0x101E8] mov x0, x3
  [0x101EC] add sp, sp, #0x10
  [0x101F0] ldp x29, x30, [sp], #0x10
  [0x101F4] ret


[(method debug-draw-actors level-group)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0xe0
  [0x1000C] mov x7, x7
  [0x10010] str x7, [sp, #0xd8]
  [0x10014] mov x6, x6
  [0x10018] str x6, [sp, #0x20]
  [0x1001C] ldr x9, [sp, #0x20]
  [0x10020] mov x8, x9
  [0x10024] mov x9, x14
  [0x10028] sub x9, x9, x15 ;; misaligned with debug data
  [0x1002C] cmp x8, x9
  [0x10030] b.eq #0x100d4
  [0x10034] adrp x16, #0x10000
  [0x10038] add x16, x16, #0
  [0x1003C] ldr w9, [x16]
  [0x10040] adrp x8, #0x10000
  [0x10044] add x8, x8, #0
  [0x10048] mov x1, x14
  [0x1004C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10050] cmp x9, x8
  [0x10054] b.ne #0x10064
  [0x10058] add x1, x14, #8
  [0x1005C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10060] mov x1, x1
  [0x10064] mov x9, x1
  [0x10068] mov x8, x14
  [0x1006C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10070] cmp x9, x8
  [0x10074] b.ne #0x100ac
  [0x10078] adrp x16, #0x10000
  [0x1007C] add x16, x16, #0
  [0x10080] ldr w9, [x16]
  [0x10084] adrp x8, #0x10000
  [0x10088] add x8, x8, #0
  [0x1008C] mov x1, x14
  [0x10090] sub x1, x1, x15 ;; misaligned with debug data
  [0x10094] cmp x9, x8
  [0x10098] b.ne #0x100a8
  [0x1009C] add x1, x14, #8
  [0x100A0] sub x1, x1, x15 ;; misaligned with debug data
  [0x100A4] mov x1, x1
  [0x100A8] mov x9, x1
  [0x100AC] mov x8, x14
  [0x100B0] sub x8, x8, x15 ;; misaligned with debug data
  [0x100B4] mov x1, x14
  [0x100B8] sub x1, x1, x15 ;; misaligned with debug data
  [0x100BC] cmp x9, x8
  [0x100C0] b.ne #0x100d0
  [0x100C4] add x1, x14, #8
  [0x100C8] sub x1, x1, x15 ;; misaligned with debug data
  [0x100CC] mov x1, x1
  [0x100D0] mov x8, x1
  [0x100D4] mov x9, x14
  [0x100D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x100DC] cmp x8, x9
  [0x100E0] b.eq #0x10be8
  [0x100E4] movz x3, #0
  [0x100E8] mov x3, x3
  [0x100EC] str x3, [sp, #0x28]
  [0x100F0] b #0x10bc0
  [0x100F4] movz x8, #0xa30
  [0x100F8] ldr x9, [sp, #0x28]
  [0x100FC] mul x8, x8, x9
  [0x10100] mov x8, x8
  [0x10104] movz x9, #0x60
  [0x10108] ldr x1, [sp, #0xd8]
  [0x1010C] add x9, x9, x1
  [0x10110] add x8, x8, x9
  [0x10114] mov x8, x8
  [0x10118] add x16, x8, x15
  [0x1011C] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10120] adrp x1, #0x10000
  [0x10124] add x1, x1, #0
  [0x10128] cmp x9, x1
  [0x1012C] b.ne #0x10ba0
  [0x10130] add x16, x8, x15
  [0x10134] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10138] add x16, x9, x15
  [0x1013C] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10140] add x16, x9, x15
  [0x10144] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10148] mov x3, x3
  [0x1014C] str x3, [sp, #0x30]
  [0x10150] movz x3, #0
  [0x10154] mov x3, x3
  [0x10158] str x3, [sp, #0x38]
  [0x1015C] b #0x10b78
  [0x10160] ldr x9, [sp, #0x38]
  [0x10164] mov x8, x9
  [0x10168] lsl x8, x8, #6
  [0x1016C] mov x8, x8
  [0x10170] movz x1, #0xc
  [0x10174] ldr x9, [sp, #0x30]
  [0x10178] add x1, x1, x9
  [0x1017C] add x8, x8, x1
  [0x10180] add x16, x8, x15
  [0x10184] ldr w3, [x16, #8] ;; misaligned with debug data
  [0x10188] mov x3, x3
  [0x1018C] str x3, [sp, #0x40]
  [0x10190] movz x3, #0x20
  [0x10194] ldr x9, [sp, #0x40]
  [0x10198] add x16, x9, x15
  [0x1019C] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x101A0] add x3, x3, x8
  [0x101A4] mov x12, x3
  [0x101A8] adrp x8, #0x10000
  [0x101AC] add x8, x8, #0
  [0x101B0] mov x1, x14
  [0x101B4] sub x1, x1, x15 ;; misaligned with debug data
  [0x101B8] ldr x9, [sp, #0x20]
  [0x101BC] cmp x9, x8
  [0x101C0] b.ne #0x101d0
  [0x101C4] add x1, x14, #8
  [0x101C8] sub x1, x1, x15 ;; misaligned with debug data
  [0x101CC] mov x1, x1
  [0x101D0] mov x9, x1
  [0x101D4] mov x8, x14
  [0x101D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x101DC] cmp x9, x8
  [0x101E0] b.eq #0x10274
  [0x101E4] ldr x9, [sp, #0x40]
  [0x101E8] add x16, x9, x15
  [0x101EC] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x101F0] add x16, x8, x15
  [0x101F4] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x101F8] mov x9, x9
  [0x101FC] mov x8, x14
  [0x10200] sub x8, x8, x15 ;; misaligned with debug data
  [0x10204] cmp x9, x8
  [0x10208] b.eq #0x10274
  [0x1020C] adrp x16, #0x10000
  [0x10210] add x16, x16, #0
  [0x10214] ldr w8, [x16]
  [0x10218] ldr x9, [sp, #0x40]
  [0x1021C] add x16, x9, x15
  [0x10220] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10224] add x16, x1, x15
  [0x10228] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x1022C] add x16, x9, x15
  [0x10230] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x10234] adrp x16, #0x10000
  [0x10238] add x16, x16, #0
  [0x1023C] ldr w6, [x16]
  [0x10240] mov x8, x8
  [0x10244] mov x7, x7
  [0x10248] mov x6, x6
  [0x1024C] add x8, x8, x15
  [0x10250] stp x3, x5, [sp, #-0x10]!
  [0x10254] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10258] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1025C] blr x8 ;; misaligned with debug data
  [0x10260] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10264] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10268] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1026C] mov x0, x0
  [0x10270] mov x9, x0
  [0x10274] mov x8, x14
  [0x10278] sub x8, x8, x15 ;; misaligned with debug data
  [0x1027C] cmp x9, x8
  [0x10280] b.eq #0x10900
  [0x10284] ldr x9, [sp, #0x40]
  [0x10288] add x16, x9, x15
  [0x1028C] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10290] add x16, x8, x15
  [0x10294] ldr w3, [x16, #0xc] ;; misaligned with debug data
  [0x10298] mov x3, x3
  [0x1029C] mov x3, x3
  [0x102A0] str x3, [sp, #0x70]
  [0x102A4] adrp x16, #0x10000
  [0x102A8] add x16, x16, #0
  [0x102AC] ldr w8, [x16]
  [0x102B0] add x7, x14, #8
  [0x102B4] sub x7, x7, x15 ;; misaligned with debug data
  [0x102B8] movz x6, #0x44
  [0x102BC] movz x2, #0xc
  [0x102C0] ldr x9, [sp, #0x70]
  [0x102C4] add x16, x9, x15
  [0x102C8] ldr w1, [x16, #0x6c] ;; misaligned with debug data
  [0x102CC] add x2, x2, x1
  [0x102D0] movz x1, #0xff80
  [0x102D4] movk x1, #0x8080, lsl #16
  [0x102D8] mov x8, x8
  [0x102DC] mov x7, x7
  [0x102E0] mov x6, x6
  [0x102E4] mov x2, x2
  [0x102E8] mov x1, x1
  [0x102EC] add x8, x8, x15
  [0x102F0] stp x3, x5, [sp, #-0x10]!
  [0x102F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x102F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x102FC] blr x8 ;; misaligned with debug data
  [0x10300] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10304] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10308] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1030C] mov x0, x0
  [0x10310] adrp x16, #0x10000
  [0x10314] add x16, x16, #0
  [0x10318] ldr w12, [x16]
  [0x1031C] add x5, x14, #8
  [0x10320] sub x5, x5, x15 ;; misaligned with debug data
  [0x10324] movz x3, #0x44
  [0x10328] adrp x16, #0x10000
  [0x1032C] add x16, x16, #0
  [0x10330] ldr w9, [x16]
  [0x10334] add x16, x9, x15
  [0x10338] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x1033C] adrp x6, #0x10000
  [0x10340] add x6, x6, #0
  [0x10344] adrp x2, #0x10000
  [0x10348] add x2, x2, #0
  [0x1034C] adrp x16, #0x16000
  [0x10350] ldr s23, [x16, #0xf7c]
  [0x10354] mov x8, x14
  [0x10358] sub x8, x8, x15 ;; misaligned with debug data
  [0x1035C] mov x8, x8
  [0x10360] mov x9, x14
  [0x10364] sub x9, x9, x15 ;; misaligned with debug data
  [0x10368] mov x9, x9
  [0x1036C] adrp x16, #0x10000
  [0x10370] add x16, x16, #0
  [0x10374] ldr w10, [x16]
  [0x10378] mov x1, x1
  [0x1037C] str x1, [sp, #0xd0]
  [0x10380] ldr x7, [sp, #0x40]
  [0x10384] mov x7, x7
  [0x10388] mov x6, x6
  [0x1038C] mov x2, x2
  [0x10390] fmov w1, s23
  [0x10394] sxtw x1, w1
  [0x10398] mov x8, x8
  [0x1039C] mov x9, x9
  [0x103A0] mov x10, x10
  [0x103A4] ldr x11, [sp, #0xd0]
  [0x103A8] add x11, x11, x15
  [0x103AC] stp x3, x5, [sp, #-0x10]!
  [0x103B0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103B4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103B8] blr x11 ;; misaligned with debug data
  [0x103BC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103C0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103C4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103C8] str x11, [sp, #0xd0]
  [0x103CC] mov x0, x0
  [0x103D0] mov x0, x0
  [0x103D4] movz x1, #0xc
  [0x103D8] ldr x9, [sp, #0x70]
  [0x103DC] add x16, x9, x15
  [0x103E0] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x103E4] add x1, x1, x8
  [0x103E8] movz x8, #0x1
  [0x103EC] adrp x9, #0x16000
  [0x103F0] add x9, x9, #0xf80
  [0x103F4] sub x9, x9, x15
  [0x103F8] mov x12, x12
  [0x103FC] mov x7, x5
  [0x10400] mov x6, x3
  [0x10404] mov x2, x0
  [0x10408] mov x1, x1
  [0x1040C] mov x8, x8
  [0x10410] mov x9, x9
  [0x10414] add x12, x12, x15
  [0x10418] stp x3, x5, [sp, #-0x10]!
  [0x1041C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10420] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10424] blr x12 ;; misaligned with debug data
  [0x10428] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1042C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10430] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10434] mov x0, x0
  [0x10438] adrp x16, #0x10000
  [0x1043C] add x16, x16, #0
  [0x10440] ldr w0, [x16]
  [0x10444] add x7, x14, #8
  [0x10448] sub x7, x7, x15 ;; misaligned with debug data
  [0x1044C] movz x6, #0x44
  [0x10450] movz x8, #0
  [0x10454] movk x8, #0x2, lsl #16
  [0x10458] mov x8, x8
  [0x1045C] ldr x9, [sp, #0x70]
  [0x10460] add x16, x9, x15
  [0x10464] ldr w1, [x16, #0x34] ;; misaligned with debug data
  [0x10468] add x16, x1, x15
  [0x1046C] ldr w9, [x16] ;; misaligned with debug data
  [0x10470] mov x9, x9
  [0x10474] add x8, x8, x9
  [0x10478] mov x8, x8
  [0x1047C] add x16, x8, x15
  [0x10480] ldr w2, [x16] ;; misaligned with debug data
  [0x10484] movz x1, #0xc
  [0x10488] ldr x9, [sp, #0x70]
  [0x1048C] add x16, x9, x15
  [0x10490] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10494] add x1, x1, x8
  [0x10498] movz x8, #0x1
  [0x1049C] adrp x9, #0x16000
  [0x104A0] add x9, x9, #0xf90
  [0x104A4] sub x9, x9, x15
  [0x104A8] mov x3, x0
  [0x104AC] mov x7, x7
  [0x104B0] mov x6, x6
  [0x104B4] mov x2, x2
  [0x104B8] mov x1, x1
  [0x104BC] mov x8, x8
  [0x104C0] mov x9, x9
  [0x104C4] add x3, x3, x15
  [0x104C8] stp x3, x5, [sp, #-0x10]!
  [0x104CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104D4] blr x3 ;; misaligned with debug data
  [0x104D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104E4] mov x0, x0
  [0x104E8] adrp x16, #0x10000
  [0x104EC] add x16, x16, #0
  [0x104F0] ldr w9, [x16]
  [0x104F4] add x16, x9, x15
  [0x104F8] ldr w1, [x16, #0x34] ;; misaligned with debug data
  [0x104FC] ldr x9, [sp, #0x70]
  [0x10500] add x16, x9, x15
  [0x10504] ldr w7, [x16, #0x30] ;; misaligned with debug data
  [0x10508] adrp x6, #0x10000
  [0x1050C] add x6, x6, #0
  [0x10510] adrp x2, #0x10000
  [0x10514] add x2, x2, #0
  [0x10518] adrp x16, #0x16000
  [0x1051C] ldr s23, [x16, #0xf94]
  [0x10520] mov x8, x14
  [0x10524] sub x8, x8, x15 ;; misaligned with debug data
  [0x10528] mov x8, x8
  [0x1052C] mov x9, x14
  [0x10530] sub x9, x9, x15 ;; misaligned with debug data
  [0x10534] mov x9, x9
  [0x10538] adrp x16, #0x10000
  [0x1053C] add x16, x16, #0
  [0x10540] ldr w10, [x16]
  [0x10544] mov x3, x1
  [0x10548] mov x7, x7
  [0x1054C] mov x6, x6
  [0x10550] mov x2, x2
  [0x10554] fmov w1, s23
  [0x10558] sxtw x1, w1
  [0x1055C] mov x8, x8
  [0x10560] mov x9, x9
  [0x10564] mov x10, x10
  [0x10568] add x3, x3, x15
  [0x1056C] stp x3, x5, [sp, #-0x10]!
  [0x10570] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10574] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10578] blr x3 ;; misaligned with debug data
  [0x1057C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10580] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10584] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10588] mov x0, x0
  [0x1058C] mov x3, x0
  [0x10590] mov x10, x3
  [0x10594] mov x9, x14
  [0x10598] sub x9, x9, x15 ;; misaligned with debug data
  [0x1059C] cmp x10, x9
  [0x105A0] b.eq #0x1073c
  [0x105A4] adrp x16, #0x10000
  [0x105A8] add x16, x16, #0
  [0x105AC] ldr w3, [x16]
  [0x105B0] add x5, x14, #8
  [0x105B4] sub x5, x5, x15 ;; misaligned with debug data
  [0x105B8] movz x12, #0x44
  [0x105BC] mov x3, x3
  [0x105C0] mov x5, x5
  [0x105C4] mov x12, x12
  [0x105C8] adrp x16, #0x10000
  [0x105CC] add x16, x16, #0
  [0x105D0] ldr w9, [x16]
  [0x105D4] str x9, [sp, #0xb8]
  [0x105D8] adrp x16, #0x10000
  [0x105DC] add x16, x16, #0
  [0x105E0] ldr w9, [x16]
  [0x105E4] adrp x16, #0x10000
  [0x105E8] add x16, x16, #0
  [0x105EC] ldr w7, [x16]
  [0x105F0] mov x9, x9
  [0x105F4] mov x7, x7
  [0x105F8] add x9, x9, x15
  [0x105FC] stp x3, x5, [sp, #-0x10]!
  [0x10600] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10604] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10608] blr x9 ;; misaligned with debug data
  [0x1060C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10610] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10614] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10618] mov x0, x0
  [0x1061C] str x0, [sp, #0xc8]
  [0x10620] adrp x9, #0x16000
  [0x10624] add x9, x9, #0xfa4
  [0x10628] sub x9, x9, x15
  [0x1062C] str x9, [sp, #0xc0]
  [0x10630] adrp x16, #0x10000
  [0x10634] add x16, x16, #0
  [0x10638] ldr w9, [x16]
  [0x1063C] add x16, x10, x15
  [0x10640] ldrsw x7, [x16] ;; misaligned with debug data
  [0x10644] mov x7, x7
  [0x10648] mov x9, x9
  [0x1064C] mov x7, x7
  [0x10650] add x9, x9, x15
  [0x10654] stp x3, x5, [sp, #-0x10]!
  [0x10658] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1065C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10660] blr x9 ;; misaligned with debug data
  [0x10664] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10668] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1066C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10670] mov x0, x0
  [0x10674] add x16, x10, x15
  [0x10678] ldrsw x1, [x16, #4] ;; misaligned with debug data
  [0x1067C] ldr x9, [sp, #0xb8]
  [0x10680] mov x8, x9
  [0x10684] ldr x7, [sp, #0xc8]
  [0x10688] mov x7, x7
  [0x1068C] ldr x6, [sp, #0xc0]
  [0x10690] mov x6, x6
  [0x10694] mov x2, x0
  [0x10698] mov x1, x1
  [0x1069C] add x8, x8, x15
  [0x106A0] stp x3, x5, [sp, #-0x10]!
  [0x106A4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x106A8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x106AC] blr x8 ;; misaligned with debug data
  [0x106B0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x106B4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x106B8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x106BC] mov x0, x0
  [0x106C0] mov x12, x12
  [0x106C4] adrp x16, #0x10000
  [0x106C8] add x16, x16, #0
  [0x106CC] ldr w2, [x16]
  [0x106D0] movz x1, #0xc
  [0x106D4] ldr x9, [sp, #0x70]
  [0x106D8] add x16, x9, x15
  [0x106DC] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x106E0] add x1, x1, x8
  [0x106E4] movz x8, #0x1
  [0x106E8] adrp x9, #0x16000
  [0x106EC] add x9, x9, #0xfb0
  [0x106F0] sub x9, x9, x15
  [0x106F4] mov x3, x3
  [0x106F8] mov x7, x5
  [0x106FC] mov x6, x12
  [0x10700] mov x2, x2
  [0x10704] mov x1, x1
  [0x10708] mov x8, x8
  [0x1070C] mov x9, x9
  [0x10710] add x3, x3, x15
  [0x10714] stp x3, x5, [sp, #-0x10]!
  [0x10718] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1071C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10720] blr x3 ;; misaligned with debug data
  [0x10724] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10728] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1072C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10730] mov x0, x0
  [0x10734] mov x0, x0
  [0x10738] b #0x10744
  [0x1073C] mov x0, x14
  [0x10740] sub x0, x0, x15 ;; misaligned with debug data
  [0x10744] adrp x16, #0x10000
  [0x10748] add x16, x16, #0
  [0x1074C] ldr w9, [x16]
  [0x10750] add x16, x9, x15
  [0x10754] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x10758] ldr x9, [sp, #0x70]
  [0x1075C] add x16, x9, x15
  [0x10760] ldr w7, [x16, #0x30] ;; misaligned with debug data
  [0x10764] adrp x6, #0x10000
  [0x10768] add x6, x6, #0
  [0x1076C] adrp x2, #0x10000
  [0x10770] add x2, x2, #0
  [0x10774] adrp x16, #0x16000
  [0x10778] ldr s23, [x16, #0xfb4]
  [0x1077C] mov x8, x14
  [0x10780] sub x8, x8, x15 ;; misaligned with debug data
  [0x10784] mov x8, x8
  [0x10788] mov x9, x14
  [0x1078C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10790] mov x9, x9
  [0x10794] adrp x16, #0x10000
  [0x10798] add x16, x16, #0
  [0x1079C] ldr w10, [x16]
  [0x107A0] mov x3, x1
  [0x107A4] mov x7, x7
  [0x107A8] mov x6, x6
  [0x107AC] mov x2, x2
  [0x107B0] fmov w1, s23
  [0x107B4] sxtw x1, w1
  [0x107B8] mov x8, x8
  [0x107BC] mov x9, x9
  [0x107C0] mov x10, x10
  [0x107C4] add x3, x3, x15
  [0x107C8] stp x3, x5, [sp, #-0x10]!
  [0x107CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x107D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x107D4] blr x3 ;; misaligned with debug data
  [0x107D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x107DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x107E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x107E4] mov x0, x0
  [0x107E8] mov x0, x0
  [0x107EC] mov x0, x0
  [0x107F0] mov x9, x0
  [0x107F4] mov x9, x9
  [0x107F8] mov x8, x14
  [0x107FC] sub x8, x8, x15 ;; misaligned with debug data
  [0x10800] cmp x9, x8
  [0x10804] b.eq #0x1083c
  [0x10808] add x16, x0, x15
  [0x1080C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10810] adrp x16, #0x10000
  [0x10814] add x16, x16, #0
  [0x10818] ldr w8, [x16]
  [0x1081C] mov x1, x14
  [0x10820] sub x1, x1, x15 ;; misaligned with debug data
  [0x10824] cmp x9, x8
  [0x10828] b.ne #0x10838
  [0x1082C] add x1, x14, #8
  [0x10830] sub x1, x1, x15 ;; misaligned with debug data
  [0x10834] mov x1, x1
  [0x10838] mov x9, x1
  [0x1083C] mov x8, x14
  [0x10840] sub x8, x8, x15 ;; misaligned with debug data
  [0x10844] cmp x9, x8
  [0x10848] b.eq #0x108f0
  [0x1084C] adrp x16, #0x10000
  [0x10850] add x16, x16, #0
  [0x10854] ldr w3, [x16]
  [0x10858] add x7, x14, #8
  [0x1085C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10860] movz x6, #0x44
  [0x10864] movz x9, #0
  [0x10868] movk x9, #0x2, lsl #16
  [0x1086C] mov x9, x9
  [0x10870] mov x0, x0
  [0x10874] add x9, x9, x0
  [0x10878] mov x9, x9
  [0x1087C] add x16, x9, x15
  [0x10880] ldr w2, [x16] ;; misaligned with debug data
  [0x10884] movz x1, #0xc
  [0x10888] ldr x9, [sp, #0x70]
  [0x1088C] add x16, x9, x15
  [0x10890] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10894] add x1, x1, x8
  [0x10898] movz x8, #0x1
  [0x1089C] adrp x9, #0x16000
  [0x108A0] add x9, x9, #0xfc0
  [0x108A4] sub x9, x9, x15
  [0x108A8] mov x3, x3
  [0x108AC] mov x7, x7
  [0x108B0] mov x6, x6
  [0x108B4] mov x2, x2
  [0x108B8] mov x1, x1
  [0x108BC] mov x8, x8
  [0x108C0] mov x9, x9
  [0x108C4] add x3, x3, x15
  [0x108C8] stp x3, x5, [sp, #-0x10]!
  [0x108CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108D4] blr x3 ;; misaligned with debug data
  [0x108D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108E4] mov x0, x0
  [0x108E8] mov x0, x0
  [0x108EC] b #0x108f8
  [0x108F0] mov x0, x14
  [0x108F4] sub x0, x0, x15 ;; misaligned with debug data
  [0x108F8] mov x0, x0
  [0x108FC] b #0x10b60
  [0x10900] adrp x8, #0x10000
  [0x10904] add x8, x8, #0
  [0x10908] mov x1, x14
  [0x1090C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10910] ldr x9, [sp, #0x20]
  [0x10914] cmp x9, x8
  [0x10918] b.ne #0x10928
  [0x1091C] add x1, x14, #8
  [0x10920] sub x1, x1, x15 ;; misaligned with debug data
  [0x10924] mov x1, x1
  [0x10928] mov x9, x1
  [0x1092C] mov x8, x14
  [0x10930] sub x8, x8, x15 ;; misaligned with debug data
  [0x10934] cmp x9, x8
  [0x10938] b.ne #0x10954
  [0x1093C] ldr x9, [sp, #0x40]
  [0x10940] add x16, x9, x15
  [0x10944] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10948] add x16, x8, x15
  [0x1094C] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10950] mov x9, x9
  [0x10954] mov x8, x14
  [0x10958] sub x8, x8, x15 ;; misaligned with debug data
  [0x1095C] cmp x9, x8
  [0x10960] b.eq #0x10b58
  [0x10964] adrp x16, #0x10000
  [0x10968] add x16, x16, #0
  [0x1096C] ldr w8, [x16]
  [0x10970] add x7, x14, #8
  [0x10974] sub x7, x7, x15 ;; misaligned with debug data
  [0x10978] movz x6, #0x44
  [0x1097C] ldr x9, [sp, #0x40]
  [0x10980] add x16, x9, x15
  [0x10984] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10988] add x16, x1, x15
  [0x1098C] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10990] mov x1, x14
  [0x10994] sub x1, x1, x15 ;; misaligned with debug data
  [0x10998] cmp x9, x1
  [0x1099C] b.eq #0x109b0
  [0x109A0] movz x1, #0xff80
  [0x109A4] movk x1, #0x8080, lsl #16
  [0x109A8] mov x1, x1
  [0x109AC] b #0x109bc
  [0x109B0] movz x1, #0xff
  [0x109B4] movk x1, #0x8000, lsl #16
  [0x109B8] mov x1, x1
  [0x109BC] mov x8, x8
  [0x109C0] mov x7, x7
  [0x109C4] mov x6, x6
  [0x109C8] mov x2, x12
  [0x109CC] mov x1, x1
  [0x109D0] add x8, x8, x15
  [0x109D4] stp x3, x5, [sp, #-0x10]!
  [0x109D8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x109DC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x109E0] blr x8 ;; misaligned with debug data
  [0x109E4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x109E8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x109EC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x109F0] mov x0, x0
  [0x109F4] adrp x16, #0x10000
  [0x109F8] add x16, x16, #0
  [0x109FC] ldr w3, [x16]
  [0x10A00] add x5, x14, #8
  [0x10A04] sub x5, x5, x15 ;; misaligned with debug data
  [0x10A08] movz x9, #0x44
  [0x10A0C] mov x3, x3
  [0x10A10] str x3, [sp, #0x80]
  [0x10A14] mov x5, x5
  [0x10A18] mov x3, x9
  [0x10A1C] mov x3, x3
  [0x10A20] adrp x16, #0x10000
  [0x10A24] add x16, x16, #0
  [0x10A28] ldr w9, [x16]
  [0x10A2C] add x16, x9, x15
  [0x10A30] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10A34] adrp x6, #0x10000
  [0x10A38] add x6, x6, #0
  [0x10A3C] adrp x2, #0x10000
  [0x10A40] add x2, x2, #0
  [0x10A44] adrp x16, #0x16000
  [0x10A48] ldr s23, [x16, #0xfc4]
  [0x10A4C] mov x8, x14
  [0x10A50] sub x8, x8, x15 ;; misaligned with debug data
  [0x10A54] mov x8, x8
  [0x10A58] mov x1, x14
  [0x10A5C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10A60] mov x0, x1
  [0x10A64] adrp x16, #0x10000
  [0x10A68] add x16, x16, #0
  [0x10A6C] ldr w10, [x16]
  [0x10A70] mov x11, x9
  [0x10A74] ldr x9, [sp, #0x40]
  [0x10A78] mov x7, x9
  [0x10A7C] mov x6, x6
  [0x10A80] mov x2, x2
  [0x10A84] fmov w1, s23
  [0x10A88] sxtw x1, w1
  [0x10A8C] mov x8, x8
  [0x10A90] mov x9, x0
  [0x10A94] mov x10, x10
  [0x10A98] add x11, x11, x15
  [0x10A9C] stp x3, x5, [sp, #-0x10]!
  [0x10AA0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AA4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10AA8] blr x11 ;; misaligned with debug data
  [0x10AAC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10AB0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10AB4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10AB8] mov x0, x0
  [0x10ABC] mov x0, x0
  [0x10AC0] ldr x9, [sp, #0x40]
  [0x10AC4] add x16, x9, x15
  [0x10AC8] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10ACC] add x16, x8, x15
  [0x10AD0] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10AD4] movz x8, #0x3
  [0x10AD8] mov x9, x9
  [0x10ADC] and x9, x9, x8
  [0x10AE0] movz x8, #0
  [0x10AE4] cmp x9, x8
  [0x10AE8] b.eq #0x10af8
  [0x10AEC] movz x8, #0x1
  [0x10AF0] mov x8, x8
  [0x10AF4] b #0x10b00
  [0x10AF8] movz x8, #0x5
  [0x10AFC] mov x8, x8
  [0x10B00] adrp x11, #0x15000
  [0x10B04] add x11, x11, #0xfd0
  [0x10B08] sub x11, x11, x15
  [0x10B0C] ldr x9, [sp, #0x80]
  [0x10B10] mov x10, x9
  [0x10B14] mov x7, x5
  [0x10B18] mov x6, x3
  [0x10B1C] mov x2, x0
  [0x10B20] mov x1, x12
  [0x10B24] mov x8, x8
  [0x10B28] mov x9, x11
  [0x10B2C] add x10, x10, x15
  [0x10B30] stp x3, x5, [sp, #-0x10]!
  [0x10B34] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B38] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10B3C] blr x10 ;; misaligned with debug data
  [0x10B40] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10B44] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10B48] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10B4C] mov x0, x0
  [0x10B50] mov x0, x0
  [0x10B54] b #0x10b60
  [0x10B58] mov x0, x14
  [0x10B5C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10B60] ldr x3, [sp, #0x38]
  [0x10B64] mov x3, x3
  [0x10B68] movz x9, #0x1
  [0x10B6C] add x3, x3, x9
  [0x10B70] mov x3, x3
  [0x10B74] str x3, [sp, #0x38]
  [0x10B78] ldr x9, [sp, #0x30]
  [0x10B7C] add x16, x9, x15
  [0x10B80] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10B84] ldr x9, [sp, #0x38]
  [0x10B88] cmp x9, x8
  [0x10B8C] b.lt #0x10160
  [0x10B90] mov x9, x14
  [0x10B94] sub x9, x9, x15 ;; misaligned with debug data
  [0x10B98] mov x9, x9
  [0x10B9C] b #0x10ba8
  [0x10BA0] mov x9, x14
  [0x10BA4] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BA8] ldr x3, [sp, #0x28]
  [0x10BAC] mov x3, x3
  [0x10BB0] movz x9, #0x1
  [0x10BB4] add x3, x3, x9
  [0x10BB8] mov x3, x3
  [0x10BBC] str x3, [sp, #0x28]
  [0x10BC0] ldr x9, [sp, #0xd8]
  [0x10BC4] add x16, x9, x15
  [0x10BC8] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10BCC] ldr x9, [sp, #0x28]
  [0x10BD0] cmp x9, x8
  [0x10BD4] b.lt #0x100f4
  [0x10BD8] mov x9, x14
  [0x10BDC] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BE0] mov x9, x9
  [0x10BE4] b #0x10bf0
  [0x10BE8] mov x9, x14
  [0x10BEC] sub x9, x9, x15 ;; misaligned with debug data
  [0x10BF0] adrp x16, #0x10000
  [0x10BF4] add x16, x16, #0
  [0x10BF8] ldr w9, [x16]
  [0x10BFC] mov x9, x9
  [0x10C00] mov x8, x14
  [0x10C04] sub x8, x8, x15 ;; misaligned with debug data
  [0x10C08] cmp x9, x8
  [0x10C0C] b.eq #0x10c68
  [0x10C10] adrp x16, #0x10000
  [0x10C14] add x16, x16, #0
  [0x10C18] ldr w9, [x16]
  [0x10C1C] mov x9, x9
  [0x10C20] mov x8, x14
  [0x10C24] sub x8, x8, x15 ;; misaligned with debug data
  [0x10C28] cmp x9, x8
  [0x10C2C] b.ne #0x10c40
  [0x10C30] adrp x16, #0x10000
  [0x10C34] add x16, x16, #0
  [0x10C38] ldr w9, [x16]
  [0x10C3C] mov x9, x9
  [0x10C40] mov x8, x14
  [0x10C44] sub x8, x8, x15 ;; misaligned with debug data
  [0x10C48] mov x1, x14
  [0x10C4C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10C50] cmp x9, x8
  [0x10C54] b.ne #0x10c64
  [0x10C58] add x1, x14, #8
  [0x10C5C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10C60] mov x1, x1
  [0x10C64] mov x9, x1
  [0x10C68] mov x8, x14
  [0x10C6C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10C70] cmp x9, x8
  [0x10C74] b.eq #0x112e8
  [0x10C78] adrp x16, #0x10000
  [0x10C7C] add x16, x16, #0
  [0x10C80] ldr w3, [x16]
  [0x10C84] mov x3, x3
  [0x10C88] str x3, [sp, #0x48]
  [0x10C8C] movz x3, #0
  [0x10C90] mov x3, x3
  [0x10C94] str x3, [sp, #0x50]
  [0x10C98] b #0x112c0
  [0x10C9C] movz x3, #0xa30
  [0x10CA0] ldr x9, [sp, #0x50]
  [0x10CA4] mul x3, x3, x9
  [0x10CA8] mov x3, x3
  [0x10CAC] movz x8, #0x60
  [0x10CB0] ldr x9, [sp, #0xd8]
  [0x10CB4] add x8, x8, x9
  [0x10CB8] add x3, x3, x8
  [0x10CBC] mov x3, x3
  [0x10CC0] str x3, [sp, #0x58]
  [0x10CC4] ldr x9, [sp, #0x58]
  [0x10CC8] add x16, x9, x15
  [0x10CCC] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x10CD0] adrp x9, #0x10000
  [0x10CD4] add x9, x9, #0
  [0x10CD8] cmp x8, x9
  [0x10CDC] b.ne #0x112a0
  [0x10CE0] ldr x9, [sp, #0x58]
  [0x10CE4] add x16, x9, x15
  [0x10CE8] ldr w8, [x16, #0x2c] ;; misaligned with debug data
  [0x10CEC] add x16, x8, x15
  [0x10CF0] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10CF4] add x16, x9, x15
  [0x10CF8] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x10CFC] mov x3, x3
  [0x10D00] str x3, [sp, #0x60]
  [0x10D04] movz x3, #0
  [0x10D08] mov x3, x3
  [0x10D0C] str x3, [sp, #0x68]
  [0x10D10] b #0x11278
  [0x10D14] ldr x9, [sp, #0x68]
  [0x10D18] mov x8, x9
  [0x10D1C] lsl x8, x8, #6
  [0x10D20] mov x8, x8
  [0x10D24] movz x1, #0xc
  [0x10D28] ldr x9, [sp, #0x60]
  [0x10D2C] add x1, x1, x9
  [0x10D30] add x8, x8, x1
  [0x10D34] add x16, x8, x15
  [0x10D38] ldr w3, [x16, #8] ;; misaligned with debug data
  [0x10D3C] mov x3, x3
  [0x10D40] str x3, [sp, #0x78]
  [0x10D44] adrp x16, #0x10000
  [0x10D48] add x16, x16, #0
  [0x10D4C] ldr w9, [x16]
  [0x10D50] add x16, x9, x15
  [0x10D54] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10D58] adrp x6, #0x10000
  [0x10D5C] add x6, x6, #0
  [0x10D60] adrp x2, #0x10000
  [0x10D64] add x2, x2, #0
  [0x10D68] adrp x16, #0x15000
  [0x10D6C] ldr s23, [x16, #0xfd4]
  [0x10D70] mov x8, x14
  [0x10D74] sub x8, x8, x15 ;; misaligned with debug data
  [0x10D78] mov x8, x8
  [0x10D7C] mov x1, x14
  [0x10D80] sub x1, x1, x15 ;; misaligned with debug data
  [0x10D84] mov x0, x1
  [0x10D88] adrp x16, #0x10000
  [0x10D8C] add x16, x16, #0
  [0x10D90] ldr w10, [x16]
  [0x10D94] mov x3, x9
  [0x10D98] ldr x9, [sp, #0x78]
  [0x10D9C] mov x7, x9
  [0x10DA0] mov x6, x6
  [0x10DA4] mov x2, x2
  [0x10DA8] fmov w1, s23
  [0x10DAC] sxtw x1, w1
  [0x10DB0] mov x8, x8
  [0x10DB4] mov x9, x0
  [0x10DB8] mov x10, x10
  [0x10DBC] add x3, x3, x15
  [0x10DC0] stp x3, x5, [sp, #-0x10]!
  [0x10DC4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DC8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10DCC] blr x3 ;; misaligned with debug data
  [0x10DD0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10DD4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10DD8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10DDC] mov x0, x0
  [0x10DE0] mov x0, x0
  [0x10DE4] ldr x9, [sp, #0x78]
  [0x10DE8] add x16, x9, x15
  [0x10DEC] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10DF0] add x16, x8, x15
  [0x10DF4] ldrsw x6, [x16, #0x14] ;; misaligned with debug data
  [0x10DF8] mov x0, x0
  [0x10DFC] mov x6, x6
  [0x10E00] mov x9, x0
  [0x10E04] mov x8, x14
  [0x10E08] sub x8, x8, x15 ;; misaligned with debug data
  [0x10E0C] cmp x9, x8
  [0x10E10] b.eq #0x10e80
  [0x10E14] add x8, x14, #8
  [0x10E18] sub x8, x8, x15 ;; misaligned with debug data
  [0x10E1C] mov x1, x14
  [0x10E20] sub x1, x1, x15 ;; misaligned with debug data
  [0x10E24] ldr x9, [sp, #0x48]
  [0x10E28] cmp x9, x8
  [0x10E2C] b.ne #0x10e3c
  [0x10E30] add x1, x14, #8
  [0x10E34] sub x1, x1, x15 ;; misaligned with debug data
  [0x10E38] mov x1, x1
  [0x10E3C] mov x9, x1
  [0x10E40] mov x8, x14
  [0x10E44] sub x8, x8, x15 ;; misaligned with debug data
  [0x10E48] cmp x9, x8
  [0x10E4C] b.ne #0x10e7c
  [0x10E50] adrp x8, #0x10000
  [0x10E54] add x8, x8, #0
  [0x10E58] mov x1, x14
  [0x10E5C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10E60] ldr x9, [sp, #0x48]
  [0x10E64] cmp x9, x8
  [0x10E68] b.ne #0x10e78
  [0x10E6C] add x1, x14, #8
  [0x10E70] sub x1, x1, x15 ;; misaligned with debug data
  [0x10E74] mov x1, x1
  [0x10E78] mov x9, x1
  [0x10E7C] mov x9, x9
  [0x10E80] mov x8, x14
  [0x10E84] sub x8, x8, x15 ;; misaligned with debug data
  [0x10E88] cmp x9, x8
  [0x10E8C] b.eq #0x10fa0
  [0x10E90] adrp x16, #0x10000
  [0x10E94] add x16, x16, #0
  [0x10E98] ldr w3, [x16]
  [0x10E9C] add x5, x14, #8
  [0x10EA0] sub x5, x5, x15 ;; misaligned with debug data
  [0x10EA4] movz x9, #0x44
  [0x10EA8] mov x8, x0
  [0x10EAC] movz x1, #0
  [0x10EB0] add x8, x8, x1
  [0x10EB4] mov x0, x0
  [0x10EB8] movz x1, #0x10
  [0x10EBC] add x0, x0, x1
  [0x10EC0] mov x10, x3
  [0x10EC4] mov x5, x5
  [0x10EC8] str x5, [sp, #0xb0]
  [0x10ECC] mov x3, x9
  [0x10ED0] mov x5, x8
  [0x10ED4] mov x12, x0
  [0x10ED8] mov x3, x3
  [0x10EDC] mov x5, x5
  [0x10EE0] mov x12, x12
  [0x10EE4] ldr x9, [sp, #0x58]
  [0x10EE8] add x16, x9, x15
  [0x10EEC] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x10EF0] add x16, x8, x15
  [0x10EF4] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10EF8] mov x8, x9
  [0x10EFC] ldr x9, [sp, #0x58]
  [0x10F00] mov x7, x9
  [0x10F04] mov x6, x6
  [0x10F08] add x8, x8, x15
  [0x10F0C] stp x3, x5, [sp, #-0x10]!
  [0x10F10] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F14] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F18] blr x8 ;; misaligned with debug data
  [0x10F1C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10F20] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10F24] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10F28] mov x0, x0
  [0x10F2C] mov x9, x14
  [0x10F30] sub x9, x9, x15 ;; misaligned with debug data
  [0x10F34] cmp x0, x9
  [0x10F38] b.eq #0x10f4c
  [0x10F3C] movz x8, #0x8000
  [0x10F40] movk x8, #0x8080, lsl #16
  [0x10F44] mov x8, x8
  [0x10F48] b #0x10f58
  [0x10F4C] movz x8, #0x80
  [0x10F50] movk x8, #0x8080, lsl #16
  [0x10F54] mov x8, x8
  [0x10F58] mov x10, x10
  [0x10F5C] ldr x7, [sp, #0xb0]
  [0x10F60] mov x7, x7
  [0x10F64] mov x6, x3
  [0x10F68] mov x2, x5
  [0x10F6C] mov x1, x12
  [0x10F70] mov x8, x8
  [0x10F74] add x10, x10, x15
  [0x10F78] stp x3, x5, [sp, #-0x10]!
  [0x10F7C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F80] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10F84] blr x10 ;; misaligned with debug data
  [0x10F88] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10F8C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10F90] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10F94] mov x0, x0
  [0x10F98] mov x0, x0
  [0x10F9C] b #0x10fa8
  [0x10FA0] mov x0, x14
  [0x10FA4] sub x0, x0, x15 ;; misaligned with debug data
  [0x10FA8] add x8, x14, #8
  [0x10FAC] sub x8, x8, x15 ;; misaligned with debug data
  [0x10FB0] mov x1, x14
  [0x10FB4] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FB8] ldr x9, [sp, #0x48]
  [0x10FBC] cmp x9, x8
  [0x10FC0] b.ne #0x10fd0
  [0x10FC4] add x1, x14, #8
  [0x10FC8] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FCC] mov x1, x1
  [0x10FD0] mov x9, x1
  [0x10FD4] mov x8, x14
  [0x10FD8] sub x8, x8, x15 ;; misaligned with debug data
  [0x10FDC] cmp x9, x8
  [0x10FE0] b.ne #0x11010
  [0x10FE4] adrp x8, #0x10000
  [0x10FE8] add x8, x8, #0
  [0x10FEC] mov x1, x14
  [0x10FF0] sub x1, x1, x15 ;; misaligned with debug data
  [0x10FF4] ldr x9, [sp, #0x48]
  [0x10FF8] cmp x9, x8
  [0x10FFC] b.ne #0x1100c
  [0x11000] add x1, x14, #8
  [0x11004] sub x1, x1, x15 ;; misaligned with debug data
  [0x11008] mov x1, x1
  [0x1100C] mov x9, x1
  [0x11010] mov x8, x14
  [0x11014] sub x8, x8, x15 ;; misaligned with debug data
  [0x11018] cmp x9, x8
  [0x1101C] b.eq #0x11258
  [0x11020] ldr x9, [sp, #0x78]
  [0x11024] add x16, x9, x15
  [0x11028] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x1102C] add x16, x8, x15
  [0x11030] ldr w3, [x16, #0xc] ;; misaligned with debug data
  [0x11034] mov x3, x3
  [0x11038] mov x9, x14
  [0x1103C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11040] cmp x3, x9
  [0x11044] b.eq #0x11248
  [0x11048] adrp x16, #0x11000
  [0x1104C] add x16, x16, #0
  [0x11050] ldr w9, [x16]
  [0x11054] add x16, x3, x15
  [0x11058] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x1105C] adrp x16, #0x11000
  [0x11060] add x16, x16, #0
  [0x11064] ldr w6, [x16]
  [0x11068] mov x9, x9
  [0x1106C] mov x7, x7
  [0x11070] mov x6, x6
  [0x11074] add x9, x9, x15
  [0x11078] stp x3, x5, [sp, #-0x10]!
  [0x1107C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11080] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11084] blr x9 ;; misaligned with debug data
  [0x11088] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1108C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11090] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11094] mov x0, x0
  [0x11098] mov x0, x0
  [0x1109C] mov x9, x14
  [0x110A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x110A4] cmp x0, x9
  [0x110A8] b.eq #0x110dc
  [0x110AC] mov x9, x3
  [0x110B0] add x16, x9, x15
  [0x110B4] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x110B8] movz x8, #0
  [0x110BC] mov x0, x14
  [0x110C0] sub x0, x0, x15 ;; misaligned with debug data
  [0x110C4] cmp x9, x8
  [0x110C8] b.eq #0x110d8
  [0x110CC] add x0, x14, #8
  [0x110D0] sub x0, x0, x15 ;; misaligned with debug data
  [0x110D4] mov x0, x0
  [0x110D8] mov x0, x0
  [0x110DC] mov x9, x14
  [0x110E0] sub x9, x9, x15 ;; misaligned with debug data
  [0x110E4] cmp x0, x9
  [0x110E8] b.eq #0x11238
  [0x110EC] adrp x16, #0x11000
  [0x110F0] add x16, x16, #0
  [0x110F4] ldr w9, [x16]
  [0x110F8] add x7, x14, #8
  [0x110FC] sub x7, x7, x15 ;; misaligned with debug data
  [0x11100] movz x6, #0x44
  [0x11104] movz x2, #0xc
  [0x11108] mov x8, x3
  [0x1110C] add x16, x8, x15
  [0x11110] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x11114] add x2, x2, x8
  [0x11118] movz x1, #0xffff
  [0x1111C] movk x1, #0x80ff, lsl #16
  [0x11120] mov x9, x9
  [0x11124] mov x7, x7
  [0x11128] mov x6, x6
  [0x1112C] mov x2, x2
  [0x11130] mov x1, x1
  [0x11134] add x9, x9, x15
  [0x11138] stp x3, x5, [sp, #-0x10]!
  [0x1113C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11140] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11144] blr x9 ;; misaligned with debug data
  [0x11148] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1114C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11150] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11154] mov x0, x0
  [0x11158] adrp x16, #0x11000
  [0x1115C] add x16, x16, #0
  [0x11160] ldr w9, [x16]
  [0x11164] add x7, x14, #8
  [0x11168] sub x7, x7, x15 ;; misaligned with debug data
  [0x1116C] movz x6, #0x43
  [0x11170] mov x2, sp
  [0x11174] sub x2, x2, x15
  [0x11178] movz x8, #0x6c
  [0x1117C] mov x1, x3
  [0x11180] add x16, x1, x15
  [0x11184] ldr w1, [x16, #0x74] ;; misaligned with debug data
  [0x11188] add x8, x8, x1
  [0x1118C] movz x1, #0x7c
  [0x11190] mov x0, x3
  [0x11194] add x16, x0, x15
  [0x11198] ldr w0, [x16, #0x74] ;; misaligned with debug data
  [0x1119C] add x1, x1, x0
  [0x111A0] mov x2, x2
  [0x111A4] mov x8, x8
  [0x111A8] mov x1, x1
  [0x111AC] add x16, x8, x15
  [0x111B0] ldr q22, [x16] ;; misaligned with debug data
  [0x111B4] add x16, x1, x15
  [0x111B8] ldr q21, [x16] ;; misaligned with debug data
  [0x111BC] adrp x16, #0x16000
  [0x111C0] ldr q23, [x16, #0xfe0]
  [0x111C4] fadd v22.4s, v22.4s, v21.4s
  [0x111C8] ins v22.s[3], v23.s[3]
  [0x111CC] add x16, x2, x15
  [0x111D0] str q22, [x16] ;; misaligned with debug data
  [0x111D4] mov x3, x3
  [0x111D8] add x16, x3, x15
  [0x111DC] ldr w8, [x16, #0x74] ;; misaligned with debug data
  [0x111E0] add x16, x8, x15
  [0x111E4] ldr s23, [x16, #0x88] ;; misaligned with debug data
  [0x111E8] movz x8, #0x80
  [0x111EC] movk x8, #0x8000, lsl #16
  [0x111F0] mov x9, x9
  [0x111F4] mov x7, x7
  [0x111F8] mov x6, x6
  [0x111FC] mov x2, x2
  [0x11200] fmov w1, s23
  [0x11204] sxtw x1, w1
  [0x11208] mov x8, x8
  [0x1120C] add x9, x9, x15
  [0x11210] stp x3, x5, [sp, #-0x10]!
  [0x11214] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11218] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1121C] blr x9 ;; misaligned with debug data
  [0x11220] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11224] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11228] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1122C] mov x0, x0
  [0x11230] mov x0, x0
  [0x11234] b #0x11240
  [0x11238] mov x0, x14
  [0x1123C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11240] mov x0, x0
  [0x11244] b #0x11250
  [0x11248] mov x0, x14
  [0x1124C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11250] mov x0, x0
  [0x11254] b #0x11260
  [0x11258] mov x0, x14
  [0x1125C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11260] ldr x3, [sp, #0x68]
  [0x11264] mov x3, x3
  [0x11268] movz x9, #0x1
  [0x1126C] add x3, x3, x9
  [0x11270] mov x3, x3
  [0x11274] str x3, [sp, #0x68]
  [0x11278] ldr x9, [sp, #0x60]
  [0x1127C] add x16, x9, x15
  [0x11280] ldrsw x8, [x16] ;; misaligned with debug data
  [0x11284] ldr x9, [sp, #0x68]
  [0x11288] cmp x9, x8
  [0x1128C] b.lt #0x10d14
  [0x11290] mov x9, x14
  [0x11294] sub x9, x9, x15 ;; misaligned with debug data
  [0x11298] mov x9, x9
  [0x1129C] b #0x112a8
  [0x112A0] mov x9, x14
  [0x112A4] sub x9, x9, x15 ;; misaligned with debug data
  [0x112A8] ldr x3, [sp, #0x50]
  [0x112AC] mov x3, x3
  [0x112B0] movz x9, #0x1
  [0x112B4] add x3, x3, x9
  [0x112B8] mov x3, x3
  [0x112BC] str x3, [sp, #0x50]
  [0x112C0] ldr x9, [sp, #0xd8]
  [0x112C4] add x16, x9, x15
  [0x112C8] ldrsw x8, [x16] ;; misaligned with debug data
  [0x112CC] ldr x9, [sp, #0x50]
  [0x112D0] cmp x9, x8
  [0x112D4] b.lt #0x10c9c
  [0x112D8] mov x9, x14
  [0x112DC] sub x9, x9, x15 ;; misaligned with debug data
  [0x112E0] mov x9, x9
  [0x112E4] b #0x112f0
  [0x112E8] mov x9, x14
  [0x112EC] sub x9, x9, x15 ;; misaligned with debug data
  [0x112F0] adrp x16, #0x11000
  [0x112F4] add x16, x16, #0
  [0x112F8] ldr w9, [x16]
  [0x112FC] mov x8, x14
  [0x11300] sub x8, x8, x15 ;; misaligned with debug data
  [0x11304] cmp x9, x8
  [0x11308] b.eq #0x11358
  [0x1130C] ldr x9, [sp, #0xd8]
  [0x11310] add x16, x9, x15
  [0x11314] ldur w8, [x16, #-4] ;; misaligned with debug data
  [0x11318] add x16, x8, x15
  [0x1131C] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x11320] mov x8, x9
  [0x11324] ldr x9, [sp, #0xd8]
  [0x11328] mov x7, x9
  [0x1132C] add x8, x8, x15
  [0x11330] stp x3, x5, [sp, #-0x10]!
  [0x11334] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11338] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1133C] blr x8 ;; misaligned with debug data
  [0x11340] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11344] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11348] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1134C] mov x3, x3
  [0x11350] mov x3, x3
  [0x11354] b #0x11360
  [0x11358] mov x3, x14
  [0x1135C] sub x3, x3, x15 ;; misaligned with debug data
  [0x11360] adrp x16, #0x11000
  [0x11364] add x16, x16, #0
  [0x11368] ldr w9, [x16]
  [0x1136C] mov x9, x9
  [0x11370] mov x8, x14
  [0x11374] sub x8, x8, x15 ;; misaligned with debug data
  [0x11378] cmp x9, x8
  [0x1137C] b.ne #0x11390
  [0x11380] adrp x16, #0x11000
  [0x11384] add x16, x16, #0
  [0x11388] ldr w9, [x16]
  [0x1138C] mov x9, x9
  [0x11390] mov x8, x14
  [0x11394] sub x8, x8, x15 ;; misaligned with debug data
  [0x11398] cmp x9, x8
  [0x1139C] b.eq #0x11ddc
  [0x113A0] adrp x16, #0x11000
  [0x113A4] add x16, x16, #0
  [0x113A8] ldr w9, [x16]
  [0x113AC] mov x9, x9
  [0x113B0] mov x8, x14
  [0x113B4] sub x8, x8, x15 ;; misaligned with debug data
  [0x113B8] cmp x9, x8
  [0x113BC] b.eq #0x113d8
  [0x113C0] add x16, x9, x15
  [0x113C4] ldr w9, [x16] ;; misaligned with debug data
  [0x113C8] add x16, x9, x15
  [0x113CC] ldr w3, [x16, #0x18] ;; misaligned with debug data
  [0x113D0] mov x3, x3
  [0x113D4] b #0x113e0
  [0x113D8] mov x3, x14
  [0x113DC] sub x3, x3, x15 ;; misaligned with debug data
  [0x113E0] mov x3, x3
  [0x113E4] mov x12, x3
  [0x113E8] mov x9, x14
  [0x113EC] sub x9, x9, x15 ;; misaligned with debug data
  [0x113F0] cmp x12, x9
  [0x113F4] b.ne #0x11458
  [0x113F8] adrp x16, #0x11000
  [0x113FC] add x16, x16, #0
  [0x11400] ldr w9, [x16]
  [0x11404] adrp x16, #0x11000
  [0x11408] add x16, x16, #0
  [0x1140C] ldr w7, [x16]
  [0x11410] adrp x16, #0x11000
  [0x11414] add x16, x16, #0
  [0x11418] ldr w6, [x16]
  [0x1141C] mov x9, x9
  [0x11420] mov x7, x7
  [0x11424] mov x6, x6
  [0x11428] add x9, x9, x15
  [0x1142C] stp x3, x5, [sp, #-0x10]!
  [0x11430] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11434] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11438] blr x9 ;; misaligned with debug data
  [0x1143C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11440] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11444] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11448] mov x0, x0
  [0x1144C] mov x12, x0
  [0x11450] mov x0, x0
  [0x11454] b #0x11460
  [0x11458] mov x0, x14
  [0x1145C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11460] mov x9, x12
  [0x11464] mov x8, x14
  [0x11468] sub x8, x8, x15 ;; misaligned with debug data
  [0x1146C] cmp x9, x8
  [0x11470] b.eq #0x114c8
  [0x11474] adrp x16, #0x11000
  [0x11478] add x16, x16, #0
  [0x1147C] ldr w9, [x16]
  [0x11480] add x16, x12, x15
  [0x11484] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x11488] adrp x16, #0x11000
  [0x1148C] add x16, x16, #0
  [0x11490] ldr w6, [x16]
  [0x11494] mov x9, x9
  [0x11498] mov x7, x7
  [0x1149C] mov x6, x6
  [0x114A0] add x9, x9, x15
  [0x114A4] stp x3, x5, [sp, #-0x10]!
  [0x114A8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x114AC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x114B0] blr x9 ;; misaligned with debug data
  [0x114B4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x114B8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x114BC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x114C0] mov x0, x0
  [0x114C4] mov x9, x0
  [0x114C8] mov x8, x14
  [0x114CC] sub x8, x8, x15 ;; misaligned with debug data
  [0x114D0] cmp x9, x8
  [0x114D4] b.eq #0x11978
  [0x114D8] mov x9, x12
  [0x114DC] add x16, x9, x15
  [0x114E0] ldr w3, [x16, #0x30] ;; misaligned with debug data
  [0x114E4] movz x5, #0xc
  [0x114E8] mov x9, x12
  [0x114EC] add x16, x9, x15
  [0x114F0] ldr w9, [x16, #0x6c] ;; misaligned with debug data
  [0x114F4] add x5, x5, x9
  [0x114F8] mov x3, x3
  [0x114FC] mov x5, x5
  [0x11500] mov x9, x14
  [0x11504] sub x9, x9, x15 ;; misaligned with debug data
  [0x11508] cmp x3, x9
  [0x1150C] b.eq #0x11794
  [0x11510] adrp x16, #0x11000
  [0x11514] add x16, x16, #0
  [0x11518] ldr w9, [x16]
  [0x1151C] add x7, x14, #8
  [0x11520] sub x7, x7, x15 ;; misaligned with debug data
  [0x11524] movz x6, #0x44
  [0x11528] add x16, x3, x15
  [0x1152C] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x11530] add x16, x8, x15
  [0x11534] ldr w8, [x16, #0xc] ;; misaligned with debug data
  [0x11538] mov x1, x14
  [0x1153C] sub x1, x1, x15 ;; misaligned with debug data
  [0x11540] cmp x8, x1
  [0x11544] b.eq #0x11558
  [0x11548] movz x1, #0xff80
  [0x1154C] movk x1, #0x8080, lsl #16
  [0x11550] mov x1, x1
  [0x11554] b #0x11564
  [0x11558] movz x1, #0xff
  [0x1155C] movk x1, #0x8000, lsl #16
  [0x11560] mov x1, x1
  [0x11564] mov x9, x9
  [0x11568] mov x7, x7
  [0x1156C] mov x6, x6
  [0x11570] mov x2, x5
  [0x11574] mov x1, x1
  [0x11578] add x9, x9, x15
  [0x1157C] stp x3, x5, [sp, #-0x10]!
  [0x11580] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11584] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11588] blr x9 ;; misaligned with debug data
  [0x1158C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11590] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11594] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11598] mov x0, x0
  [0x1159C] adrp x16, #0x11000
  [0x115A0] add x16, x16, #0
  [0x115A4] ldr w9, [x16]
  [0x115A8] str x9, [sp, #0x98]
  [0x115AC] add x9, x14, #8
  [0x115B0] sub x9, x9, x15 ;; misaligned with debug data
  [0x115B4] str x9, [sp, #0x90]
  [0x115B8] movz x9, #0x44
  [0x115BC] str x9, [sp, #0x88]
  [0x115C0] adrp x16, #0x11000
  [0x115C4] add x16, x16, #0
  [0x115C8] ldr w9, [x16]
  [0x115CC] add x16, x9, x15
  [0x115D0] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x115D4] adrp x6, #0x11000
  [0x115D8] add x6, x6, #0
  [0x115DC] adrp x2, #0x11000
  [0x115E0] add x2, x2, #0
  [0x115E4] adrp x16, #0x16000
  [0x115E8] ldr s23, [x16, #0xff0]
  [0x115EC] mov x8, x14
  [0x115F0] sub x8, x8, x15 ;; misaligned with debug data
  [0x115F4] mov x8, x8
  [0x115F8] mov x9, x14
  [0x115FC] sub x9, x9, x15 ;; misaligned with debug data
  [0x11600] mov x9, x9
  [0x11604] adrp x16, #0x11000
  [0x11608] add x16, x16, #0
  [0x1160C] ldr w10, [x16]
  [0x11610] mov x11, x1
  [0x11614] mov x7, x3
  [0x11618] mov x6, x6
  [0x1161C] mov x2, x2
  [0x11620] fmov w1, s23
  [0x11624] sxtw x1, w1
  [0x11628] mov x8, x8
  [0x1162C] mov x9, x9
  [0x11630] mov x10, x10
  [0x11634] add x11, x11, x15
  [0x11638] stp x3, x5, [sp, #-0x10]!
  [0x1163C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11640] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11644] blr x11 ;; misaligned with debug data
  [0x11648] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1164C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11650] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11654] mov x0, x0
  [0x11658] mov x0, x0
  [0x1165C] add x16, x3, x15
  [0x11660] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x11664] add x16, x9, x15
  [0x11668] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1166C] movz x8, #0x3
  [0x11670] mov x9, x9
  [0x11674] and x9, x9, x8
  [0x11678] movz x8, #0
  [0x1167C] cmp x9, x8
  [0x11680] b.eq #0x11690
  [0x11684] movz x8, #0x1
  [0x11688] mov x8, x8
  [0x1168C] b #0x11698
  [0x11690] movz x8, #0x1
  [0x11694] mov x8, x8
  [0x11698] adrp x3, #0x17000
  [0x1169C] add x3, x3, #0
  [0x116A0] sub x3, x3, x15
  [0x116A4] ldr x9, [sp, #0x98]
  [0x116A8] mov x11, x9
  [0x116AC] ldr x7, [sp, #0x90]
  [0x116B0] mov x7, x7
  [0x116B4] ldr x6, [sp, #0x88]
  [0x116B8] mov x6, x6
  [0x116BC] mov x2, x0
  [0x116C0] mov x1, x5
  [0x116C4] mov x8, x8
  [0x116C8] mov x9, x3
  [0x116CC] add x11, x11, x15
  [0x116D0] stp x3, x5, [sp, #-0x10]!
  [0x116D4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x116D8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x116DC] blr x11 ;; misaligned with debug data
  [0x116E0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x116E4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x116E8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x116EC] mov x0, x0
  [0x116F0] adrp x16, #0x11000
  [0x116F4] add x16, x16, #0
  [0x116F8] ldr w1, [x16]
  [0x116FC] add x7, x14, #8
  [0x11700] sub x7, x7, x15 ;; misaligned with debug data
  [0x11704] movz x6, #0x44
  [0x11708] movz x9, #0
  [0x1170C] movk x9, #0x2, lsl #16
  [0x11710] mov x9, x9
  [0x11714] mov x8, x12
  [0x11718] add x16, x8, x15
  [0x1171C] ldr w8, [x16, #0x34] ;; misaligned with debug data
  [0x11720] add x16, x8, x15
  [0x11724] ldr w8, [x16] ;; misaligned with debug data
  [0x11728] mov x8, x8
  [0x1172C] add x9, x9, x8
  [0x11730] mov x9, x9
  [0x11734] add x16, x9, x15
  [0x11738] ldr w2, [x16] ;; misaligned with debug data
  [0x1173C] movz x8, #0x1
  [0x11740] adrp x9, #0x17000
  [0x11744] add x9, x9, #0x10
  [0x11748] sub x9, x9, x15
  [0x1174C] mov x3, x1
  [0x11750] mov x7, x7
  [0x11754] mov x6, x6
  [0x11758] mov x2, x2
  [0x1175C] mov x1, x5
  [0x11760] mov x8, x8
  [0x11764] mov x9, x9
  [0x11768] add x3, x3, x15
  [0x1176C] stp x3, x5, [sp, #-0x10]!
  [0x11770] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11774] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11778] blr x3 ;; misaligned with debug data
  [0x1177C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11780] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11784] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11788] mov x0, x0
  [0x1178C] mov x0, x0
  [0x11790] b #0x1179c
  [0x11794] mov x0, x14
  [0x11798] sub x0, x0, x15 ;; misaligned with debug data
  [0x1179C] mov x9, x12
  [0x117A0] add x16, x9, x15
  [0x117A4] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x117A8] movz x8, #0
  [0x117AC] cmp x9, x8
  [0x117B0] b.eq #0x11818
  [0x117B4] mov x9, x12
  [0x117B8] add x16, x9, x15
  [0x117BC] ldr w7, [x16, #0x78] ;; misaligned with debug data
  [0x117C0] adrp x16, #0x11000
  [0x117C4] add x16, x16, #0
  [0x117C8] ldr w6, [x16]
  [0x117CC] mov x6, x6
  [0x117D0] add x16, x7, x15
  [0x117D4] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x117D8] add x16, x9, x15
  [0x117DC] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x117E0] mov x9, x9
  [0x117E4] mov x7, x7
  [0x117E8] mov x6, x6
  [0x117EC] add x9, x9, x15
  [0x117F0] stp x3, x5, [sp, #-0x10]!
  [0x117F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x117F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x117FC] blr x9 ;; misaligned with debug data
  [0x11800] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11804] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11808] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1180C] mov x0, x0
  [0x11810] mov x0, x0
  [0x11814] b #0x11820
  [0x11818] mov x0, x14
  [0x1181C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11820] mov x9, x12
  [0x11824] add x16, x9, x15
  [0x11828] ldr w9, [x16, #0x7c] ;; misaligned with debug data
  [0x1182C] movz x8, #0
  [0x11830] cmp x9, x8
  [0x11834] b.eq #0x11888
  [0x11838] mov x9, x12
  [0x1183C] add x16, x9, x15
  [0x11840] ldr w7, [x16, #0x7c] ;; misaligned with debug data
  [0x11844] add x16, x7, x15
  [0x11848] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1184C] add x16, x9, x15
  [0x11850] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x11854] mov x9, x9
  [0x11858] mov x7, x7
  [0x1185C] add x9, x9, x15
  [0x11860] stp x3, x5, [sp, #-0x10]!
  [0x11864] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11868] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1186C] blr x9 ;; misaligned with debug data
  [0x11870] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11874] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11878] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1187C] mov x3, x3
  [0x11880] mov x3, x3
  [0x11884] b #0x11890
  [0x11888] mov x3, x14
  [0x1188C] sub x3, x3, x15 ;; misaligned with debug data
  [0x11890] mov x9, x12
  [0x11894] add x16, x9, x15
  [0x11898] ldr w9, [x16, #0x84] ;; misaligned with debug data
  [0x1189C] movz x8, #0
  [0x118A0] cmp x9, x8
  [0x118A4] b.eq #0x118f8
  [0x118A8] mov x9, x12
  [0x118AC] add x16, x9, x15
  [0x118B0] ldr w7, [x16, #0x84] ;; misaligned with debug data
  [0x118B4] add x16, x7, x15
  [0x118B8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x118BC] add x16, x9, x15
  [0x118C0] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x118C4] mov x9, x9
  [0x118C8] mov x7, x7
  [0x118CC] add x9, x9, x15
  [0x118D0] stp x3, x5, [sp, #-0x10]!
  [0x118D4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x118D8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x118DC] blr x9 ;; misaligned with debug data
  [0x118E0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x118E4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x118E8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x118EC] mov x3, x3
  [0x118F0] mov x3, x3
  [0x118F4] b #0x11900
  [0x118F8] mov x3, x14
  [0x118FC] sub x3, x3, x15 ;; misaligned with debug data
  [0x11900] mov x9, x12
  [0x11904] add x16, x9, x15
  [0x11908] ldr w9, [x16, #0x88] ;; misaligned with debug data
  [0x1190C] movz x8, #0
  [0x11910] cmp x9, x8
  [0x11914] b.eq #0x11968
  [0x11918] mov x9, x12
  [0x1191C] add x16, x9, x15
  [0x11920] ldr w7, [x16, #0x88] ;; misaligned with debug data
  [0x11924] add x16, x7, x15
  [0x11928] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1192C] add x16, x9, x15
  [0x11930] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x11934] mov x9, x9
  [0x11938] mov x7, x7
  [0x1193C] add x9, x9, x15
  [0x11940] stp x3, x5, [sp, #-0x10]!
  [0x11944] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11948] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1194C] blr x9 ;; misaligned with debug data
  [0x11950] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11954] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11958] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1195C] mov x0, x0
  [0x11960] mov x0, x0
  [0x11964] b #0x11970
  [0x11968] mov x0, x14
  [0x1196C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11970] mov x0, x0
  [0x11974] b #0x11980
  [0x11978] mov x0, x14
  [0x1197C] sub x0, x0, x15 ;; misaligned with debug data
  [0x11980] mov x9, x12
  [0x11984] mov x9, x9
  [0x11988] mov x8, x14
  [0x1198C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11990] cmp x9, x8
  [0x11994] b.eq #0x11a50
  [0x11998] adrp x16, #0x11000
  [0x1199C] add x16, x16, #0
  [0x119A0] ldr w9, [x16]
  [0x119A4] mov x8, x12
  [0x119A8] add x16, x8, x15
  [0x119AC] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x119B0] adrp x16, #0x11000
  [0x119B4] add x16, x16, #0
  [0x119B8] ldr w6, [x16]
  [0x119BC] mov x9, x9
  [0x119C0] mov x7, x7
  [0x119C4] mov x6, x6
  [0x119C8] add x9, x9, x15
  [0x119CC] stp x3, x5, [sp, #-0x10]!
  [0x119D0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x119D4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x119D8] blr x9 ;; misaligned with debug data
  [0x119DC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x119E0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x119E4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x119E8] mov x0, x0
  [0x119EC] mov x9, x0
  [0x119F0] mov x8, x14
  [0x119F4] sub x8, x8, x15 ;; misaligned with debug data
  [0x119F8] cmp x9, x8
  [0x119FC] b.eq #0x11a50
  [0x11A00] mov x9, x12
  [0x11A04] add x16, x9, x15
  [0x11A08] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x11A0C] movz x8, #0
  [0x11A10] mov x1, x14
  [0x11A14] sub x1, x1, x15 ;; misaligned with debug data
  [0x11A18] cmp x9, x8
  [0x11A1C] b.eq #0x11a2c
  [0x11A20] add x1, x14, #8
  [0x11A24] sub x1, x1, x15 ;; misaligned with debug data
  [0x11A28] mov x1, x1
  [0x11A2C] mov x9, x1
  [0x11A30] mov x8, x14
  [0x11A34] sub x8, x8, x15 ;; misaligned with debug data
  [0x11A38] cmp x9, x8
  [0x11A3C] b.eq #0x11a50
  [0x11A40] adrp x16, #0x11000
  [0x11A44] add x16, x16, #0
  [0x11A48] ldr w9, [x16]
  [0x11A4C] mov x9, x9
  [0x11A50] mov x8, x14
  [0x11A54] sub x8, x8, x15 ;; misaligned with debug data
  [0x11A58] cmp x9, x8
  [0x11A5C] b.eq #0x11b40
  [0x11A60] adrp x16, #0x11000
  [0x11A64] add x16, x16, #0
  [0x11A68] ldr w9, [x16]
  [0x11A6C] add x7, x14, #8
  [0x11A70] sub x7, x7, x15 ;; misaligned with debug data
  [0x11A74] movz x6, #0x43
  [0x11A78] add x2, sp, #0x10
  [0x11A7C] sub x2, x2, x15
  [0x11A80] movz x8, #0x6c
  [0x11A84] mov x1, x12
  [0x11A88] add x16, x1, x15
  [0x11A8C] ldr w1, [x16, #0x74] ;; misaligned with debug data
  [0x11A90] add x8, x8, x1
  [0x11A94] movz x1, #0x7c
  [0x11A98] mov x0, x12
  [0x11A9C] add x16, x0, x15
  [0x11AA0] ldr w0, [x16, #0x74] ;; misaligned with debug data
  [0x11AA4] add x1, x1, x0
  [0x11AA8] mov x2, x2
  [0x11AAC] mov x8, x8
  [0x11AB0] mov x1, x1
  [0x11AB4] add x16, x8, x15
  [0x11AB8] ldr q22, [x16] ;; misaligned with debug data
  [0x11ABC] add x16, x1, x15
  [0x11AC0] ldr q21, [x16] ;; misaligned with debug data
  [0x11AC4] adrp x16, #0x16000
  [0x11AC8] ldr q23, [x16, #0x20]
  [0x11ACC] fadd v22.4s, v22.4s, v21.4s
  [0x11AD0] ins v22.s[3], v23.s[3]
  [0x11AD4] add x16, x2, x15
  [0x11AD8] str q22, [x16] ;; misaligned with debug data
  [0x11ADC] mov x12, x12
  [0x11AE0] add x16, x12, x15
  [0x11AE4] ldr w8, [x16, #0x74] ;; misaligned with debug data
  [0x11AE8] add x16, x8, x15
  [0x11AEC] ldr s23, [x16, #0x88] ;; misaligned with debug data
  [0x11AF0] movz x8, #0x80
  [0x11AF4] movk x8, #0x8000, lsl #16
  [0x11AF8] mov x9, x9
  [0x11AFC] mov x7, x7
  [0x11B00] mov x6, x6
  [0x11B04] mov x2, x2
  [0x11B08] fmov w1, s23
  [0x11B0C] sxtw x1, w1
  [0x11B10] mov x8, x8
  [0x11B14] add x9, x9, x15
  [0x11B18] stp x3, x5, [sp, #-0x10]!
  [0x11B1C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11B20] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11B24] blr x9 ;; misaligned with debug data
  [0x11B28] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11B2C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11B30] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11B34] mov x0, x0
  [0x11B38] mov x0, x0
  [0x11B3C] b #0x11b48
  [0x11B40] mov x0, x14
  [0x11B44] sub x0, x0, x15 ;; misaligned with debug data
  [0x11B48] adrp x16, #0x11000
  [0x11B4C] add x16, x16, #0
  [0x11B50] ldr w9, [x16]
  [0x11B54] mov x9, x9
  [0x11B58] mov x8, x14
  [0x11B5C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11B60] cmp x9, x8
  [0x11B64] b.eq #0x11b78
  [0x11B68] adrp x16, #0x11000
  [0x11B6C] add x16, x16, #0
  [0x11B70] ldr w9, [x16]
  [0x11B74] mov x9, x9
  [0x11B78] mov x8, x14
  [0x11B7C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11B80] cmp x9, x8
  [0x11B84] b.eq #0x11dcc
  [0x11B88] adrp x16, #0x11000
  [0x11B8C] add x16, x16, #0
  [0x11B90] ldr w9, [x16]
  [0x11B94] adrp x16, #0x11000
  [0x11B98] add x16, x16, #0
  [0x11B9C] ldr w7, [x16]
  [0x11BA0] mov x9, x9
  [0x11BA4] mov x7, x7
  [0x11BA8] add x9, x9, x15
  [0x11BAC] stp x3, x5, [sp, #-0x10]!
  [0x11BB0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11BB4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11BB8] blr x9 ;; misaligned with debug data
  [0x11BBC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11BC0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11BC4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11BC8] mov x0, x0
  [0x11BCC] mov x5, x0
  [0x11BD0] mov x9, x14
  [0x11BD4] sub x9, x9, x15 ;; misaligned with debug data
  [0x11BD8] cmp x5, x9
  [0x11BDC] b.eq #0x11dbc
  [0x11BE0] adrp x16, #0x11000
  [0x11BE4] add x16, x16, #0
  [0x11BE8] ldr w9, [x16]
  [0x11BEC] add x16, x9, x15
  [0x11BF0] ldr w1, [x16, #0x34] ;; misaligned with debug data
  [0x11BF4] adrp x6, #0x11000
  [0x11BF8] add x6, x6, #0
  [0x11BFC] adrp x2, #0x11000
  [0x11C00] add x2, x2, #0
  [0x11C04] adrp x16, #0x16000
  [0x11C08] ldr s23, [x16, #0x30]
  [0x11C0C] mov x8, x14
  [0x11C10] sub x8, x8, x15 ;; misaligned with debug data
  [0x11C14] mov x8, x8
  [0x11C18] mov x9, x14
  [0x11C1C] sub x9, x9, x15 ;; misaligned with debug data
  [0x11C20] mov x9, x9
  [0x11C24] adrp x16, #0x11000
  [0x11C28] add x16, x16, #0
  [0x11C2C] ldr w10, [x16]
  [0x11C30] mov x3, x1
  [0x11C34] mov x7, x5
  [0x11C38] mov x6, x6
  [0x11C3C] mov x2, x2
  [0x11C40] fmov w1, s23
  [0x11C44] sxtw x1, w1
  [0x11C48] mov x8, x8
  [0x11C4C] mov x9, x9
  [0x11C50] mov x10, x10
  [0x11C54] add x3, x3, x15
  [0x11C58] stp x3, x5, [sp, #-0x10]!
  [0x11C5C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11C60] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11C64] blr x3 ;; misaligned with debug data
  [0x11C68] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11C6C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11C70] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11C74] mov x0, x0
  [0x11C78] mov x0, x0
  [0x11C7C] add x16, x5, x15
  [0x11C80] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x11C84] add x16, x9, x15
  [0x11C88] ldrsw x6, [x16, #0x14] ;; misaligned with debug data
  [0x11C8C] mov x0, x0
  [0x11C90] mov x6, x6
  [0x11C94] mov x9, x14
  [0x11C98] sub x9, x9, x15 ;; misaligned with debug data
  [0x11C9C] cmp x0, x9
  [0x11CA0] b.eq #0x11dac
  [0x11CA4] adrp x16, #0x11000
  [0x11CA8] add x16, x16, #0
  [0x11CAC] ldr w10, [x16]
  [0x11CB0] add x9, x14, #8
  [0x11CB4] sub x9, x9, x15 ;; misaligned with debug data
  [0x11CB8] str x9, [sp, #0xa0]
  [0x11CBC] movz x12, #0x44
  [0x11CC0] mov x3, x0
  [0x11CC4] movz x9, #0
  [0x11CC8] add x3, x3, x9
  [0x11CCC] mov x3, x3
  [0x11CD0] str x3, [sp, #0xa8]
  [0x11CD4] mov x3, x0
  [0x11CD8] movz x9, #0x10
  [0x11CDC] add x3, x3, x9
  [0x11CE0] mov x3, x3
  [0x11CE4] add x16, x5, x15
  [0x11CE8] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x11CEC] add x16, x9, x15
  [0x11CF0] ldr w7, [x16, #0x10] ;; misaligned with debug data
  [0x11CF4] add x16, x7, x15
  [0x11CF8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x11CFC] add x16, x9, x15
  [0x11D00] ldr w9, [x16, #0x38] ;; misaligned with debug data
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
  [0x11D34] mov x9, x14
  [0x11D38] sub x9, x9, x15 ;; misaligned with debug data
  [0x11D3C] cmp x0, x9
  [0x11D40] b.eq #0x11d54
  [0x11D44] movz x8, #0x8000
  [0x11D48] movk x8, #0x8080, lsl #16
  [0x11D4C] mov x8, x8
  [0x11D50] b #0x11d60
  [0x11D54] movz x8, #0x80
  [0x11D58] movk x8, #0x8080, lsl #16
  [0x11D5C] mov x8, x8
  [0x11D60] mov x10, x10
  [0x11D64] ldr x7, [sp, #0xa0]
  [0x11D68] mov x7, x7
  [0x11D6C] mov x6, x12
  [0x11D70] ldr x2, [sp, #0xa8]
  [0x11D74] mov x2, x2
  [0x11D78] mov x1, x3
  [0x11D7C] mov x8, x8
  [0x11D80] add x10, x10, x15
  [0x11D84] stp x3, x5, [sp, #-0x10]!
  [0x11D88] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11D8C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11D90] blr x10 ;; misaligned with debug data
  [0x11D94] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11D98] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11D9C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11DA0] mov x0, x0
  [0x11DA4] mov x0, x0
  [0x11DA8] b #0x11db4
  [0x11DAC] mov x0, x14
  [0x11DB0] sub x0, x0, x15 ;; misaligned with debug data
  [0x11DB4] mov x0, x0
  [0x11DB8] b #0x11dc4
  [0x11DBC] mov x0, x14
  [0x11DC0] sub x0, x0, x15 ;; misaligned with debug data
  [0x11DC4] mov x0, x0
  [0x11DC8] b #0x11dd4
  [0x11DCC] mov x0, x14
  [0x11DD0] sub x0, x0, x15 ;; misaligned with debug data
  [0x11DD4] mov x0, x0
  [0x11DD8] b #0x11de4
  [0x11DDC] mov x0, x14
  [0x11DE0] sub x0, x0, x15 ;; misaligned with debug data
  [0x11DE4] adrp x16, #0x11000
  [0x11DE8] add x16, x16, #0
  [0x11DEC] ldr w9, [x16]
  [0x11DF0] mov x9, x9
  [0x11DF4] mov x8, x14
  [0x11DF8] sub x8, x8, x15 ;; misaligned with debug data
  [0x11DFC] cmp x9, x8
  [0x11E00] b.ne #0x11e34
  [0x11E04] adrp x16, #0x11000
  [0x11E08] add x16, x16, #0
  [0x11E0C] ldr w9, [x16]
  [0x11E10] mov x9, x9
  [0x11E14] mov x8, x14
  [0x11E18] sub x8, x8, x15 ;; misaligned with debug data
  [0x11E1C] cmp x9, x8
  [0x11E20] b.ne #0x11e34
  [0x11E24] adrp x16, #0x11000
  [0x11E28] add x16, x16, #0
  [0x11E2C] ldr w9, [x16]
  [0x11E30] mov x9, x9
  [0x11E34] mov x9, x9
  [0x11E38] mov x8, x14
  [0x11E3C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11E40] cmp x9, x8
  [0x11E44] b.eq #0x11ea0
  [0x11E48] adrp x16, #0x11000
  [0x11E4C] add x16, x16, #0
  [0x11E50] ldr w9, [x16]
  [0x11E54] mov x9, x9
  [0x11E58] mov x8, x14
  [0x11E5C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11E60] cmp x9, x8
  [0x11E64] b.ne #0x11e78
  [0x11E68] adrp x16, #0x11000
  [0x11E6C] add x16, x16, #0
  [0x11E70] ldr w9, [x16]
  [0x11E74] mov x9, x9
  [0x11E78] mov x8, x14
  [0x11E7C] sub x8, x8, x15 ;; misaligned with debug data
  [0x11E80] mov x1, x14
  [0x11E84] sub x1, x1, x15 ;; misaligned with debug data
  [0x11E88] cmp x9, x8
  [0x11E8C] b.ne #0x11e9c
  [0x11E90] add x1, x14, #8
  [0x11E94] sub x1, x1, x15 ;; misaligned with debug data
  [0x11E98] mov x1, x1
  [0x11E9C] mov x9, x1
  [0x11EA0] mov x8, x14
  [0x11EA4] sub x8, x8, x15 ;; misaligned with debug data
  [0x11EA8] cmp x9, x8
  [0x11EAC] b.eq #0x11f1c
  [0x11EB0] adrp x16, #0x11000
  [0x11EB4] add x16, x16, #0
  [0x11EB8] ldr w9, [x16]
  [0x11EBC] adrp x16, #0x11000
  [0x11EC0] add x16, x16, #0
  [0x11EC4] ldr w7, [x16]
  [0x11EC8] adrp x6, #0xf000
  [0x11ECC] add x6, x6, #0x374
  [0x11ED0] sub x6, x6, x15
  [0x11ED4] adrp x16, #0x11000
  [0x11ED8] add x16, x16, #0
  [0x11EDC] ldr w2, [x16]
  [0x11EE0] mov x9, x9
  [0x11EE4] mov x7, x7
  [0x11EE8] mov x6, x6
  [0x11EEC] mov x2, x2
  [0x11EF0] add x9, x9, x15
  [0x11EF4] stp x3, x5, [sp, #-0x10]!
  [0x11EF8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x11EFC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x11F00] blr x9 ;; misaligned with debug data
  [0x11F04] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x11F08] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x11F0C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x11F10] mov x0, x0
  [0x11F14] mov x0, x0
  [0x11F18] b #0x11f24
  [0x11F1C] mov x0, x14
  [0x11F20] sub x0, x0, x15 ;; misaligned with debug data
  [0x11F24] adrp x16, #0x11000
  [0x11F28] add x16, x16, #0
  [0x11F2C] ldr w9, [x16]
  [0x11F30] mov x8, x14
  [0x11F34] sub x8, x8, x15 ;; misaligned with debug data
  [0x11F38] cmp x9, x8
  [0x11F3C] b.eq #0x120fc
  [0x11F40] movz x3, #0
  [0x11F44] mov x5, x3
  [0x11F48] b #0x120d8
  [0x11F4C] movz x3, #0xa30
  [0x11F50] mul x3, x3, x5
  [0x11F54] mov x3, x3
  [0x11F58] movz x8, #0x60
  [0x11F5C] ldr x9, [sp, #0xd8]
  [0x11F60] add x8, x8, x9
  [0x11F64] add x3, x3, x8
  [0x11F68] mov x12, x3
  [0x11F6C] add x16, x12, x15
  [0x11F70] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x11F74] adrp x8, #0x11000
  [0x11F78] add x8, x8, #0
  [0x11F7C] cmp x9, x8
  [0x11F80] b.ne #0x120c0
  [0x11F84] add x16, x12, x15
  [0x11F88] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x11F8C] add x16, x9, x15
  [0x11F90] ldr w9, [x16, #0x90] ;; misaligned with debug data
  [0x11F94] movz x8, #0
  [0x11F98] cmp x9, x8
  [0x11F9C] b.eq #0x120b0
  [0x11FA0] add x16, x12, x15
  [0x11FA4] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x11FA8] add x16, x9, x15
  [0x11FAC] ldr w3, [x16, #0x90] ;; misaligned with debug data
  [0x11FB0] mov x10, x3
  [0x11FB4] add x16, x10, x15
  [0x11FB8] ldrsw x3, [x16] ;; misaligned with debug data
  [0x11FBC] mov x3, x3
  [0x11FC0] b #0x12094
  [0x11FC4] mov x3, x3
  [0x11FC8] movz x9, #0x1
  [0x11FCC] sub x3, x3, x9
  [0x11FD0] mov x3, x3
  [0x11FD4] adrp x16, #0x11000
  [0x11FD8] add x16, x16, #0
  [0x11FDC] ldr w9, [x16]
  [0x11FE0] add x7, x14, #8
  [0x11FE4] sub x7, x7, x15 ;; misaligned with debug data
  [0x11FE8] movz x6, #0x43
  [0x11FEC] mov x2, x3
  [0x11FF0] lsl x2, x2, #5
  [0x11FF4] mov x2, x2
  [0x11FF8] movz x8, #0xc
  [0x11FFC] add x8, x8, x10
  [0x12000] add x2, x2, x8
  [0x12004] mov x2, x2
  [0x12008] movz x1, #0x1c
  [0x1200C] add x1, x1, x10
  [0x12010] mov x1, x1
  [0x12014] mov x1, x1
  [0x12018] mov x8, x3
  [0x1201C] lsl x8, x8, #5
  [0x12020] add x1, x1, x8
  [0x12024] mov x1, x1
  [0x12028] add x16, x12, x15
  [0x1202C] ldrsw x8, [x16, #0xc] ;; misaligned with debug data
  [0x12030] movz x0, #0
  [0x12034] cmp x8, x0
  [0x12038] b.ne #0x1204c
  [0x1203C] movz x8, #0x8000
  [0x12040] movk x8, #0x8080, lsl #16
  [0x12044] mov x8, x8
  [0x12048] b #0x12058
  [0x1204C] movz x8, #0x80ff
  [0x12050] movk x8, #0x8080, lsl #16
  [0x12054] mov x8, x8
  [0x12058] mov x9, x9
  [0x1205C] mov x7, x7
  [0x12060] mov x6, x6
  [0x12064] mov x2, x2
  [0x12068] mov x1, x1
  [0x1206C] mov x8, x8
  [0x12070] add x9, x9, x15
  [0x12074] stp x3, x5, [sp, #-0x10]!
  [0x12078] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1207C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x12080] blr x9 ;; misaligned with debug data
  [0x12084] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x12088] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1208C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x12090] mov x0, x0
  [0x12094] movz x9, #0
  [0x12098] cmp x3, x9
  [0x1209C] b.ne #0x11fc4
  [0x120A0] mov x9, x14
  [0x120A4] sub x9, x9, x15 ;; misaligned with debug data
  [0x120A8] mov x9, x9
  [0x120AC] b #0x120b8
  [0x120B0] mov x9, x14
  [0x120B4] sub x9, x9, x15 ;; misaligned with debug data
  [0x120B8] mov x9, x9
  [0x120BC] b #0x120c8
  [0x120C0] mov x9, x14
  [0x120C4] sub x9, x9, x15 ;; misaligned with debug data
  [0x120C8] mov x3, x5
  [0x120CC] movz x9, #0x1
  [0x120D0] add x3, x3, x9
  [0x120D4] mov x5, x3
  [0x120D8] ldr x9, [sp, #0xd8]
  [0x120DC] add x16, x9, x15
  [0x120E0] ldrsw x8, [x16] ;; misaligned with debug data
  [0x120E4] cmp x5, x8
  [0x120E8] b.lt #0x11f4c
  [0x120EC] mov x9, x14
  [0x120F0] sub x9, x9, x15 ;; misaligned with debug data
  [0x120F4] mov x9, x9
  [0x120F8] b #0x12104
  [0x120FC] mov x9, x14
  [0x12100] sub x9, x9, x15 ;; misaligned with debug data
  [0x12104] adrp x16, #0x12000
  [0x12108] add x16, x16, #0
  [0x1210C] ldr w9, [x16]
  [0x12110] mov x9, x9
  [0x12114] mov x8, x14
  [0x12118] sub x8, x8, x15 ;; misaligned with debug data
  [0x1211C] cmp x9, x8
  [0x12120] b.ne #0x12214
  [0x12124] adrp x16, #0x12000
  [0x12128] add x16, x16, #0
  [0x1212C] ldr w9, [x16]
  [0x12130] mov x9, x9
  [0x12134] mov x8, x14
  [0x12138] sub x8, x8, x15 ;; misaligned with debug data
  [0x1213C] cmp x9, x8
  [0x12140] b.ne #0x12214
  [0x12144] adrp x16, #0x12000
  [0x12148] add x16, x16, #0
  [0x1214C] ldr w9, [x16]
  [0x12150] mov x9, x9
  [0x12154] mov x8, x14
  [0x12158] sub x8, x8, x15 ;; misaligned with debug data
  [0x1215C] cmp x9, x8
  [0x12160] b.ne #0x12214
  [0x12164] adrp x16, #0x12000
  [0x12168] add x16, x16, #0
  [0x1216C] ldr w9, [x16]
  [0x12170] mov x9, x9
  [0x12174] mov x8, x14
  [0x12178] sub x8, x8, x15 ;; misaligned with debug data
  [0x1217C] cmp x9, x8
  [0x12180] b.ne #0x12214
  [0x12184] adrp x16, #0x12000
  [0x12188] add x16, x16, #0
  [0x1218C] ldr w9, [x16]
  [0x12190] mov x9, x9
  [0x12194] mov x8, x14
  [0x12198] sub x8, x8, x15 ;; misaligned with debug data
  [0x1219C] cmp x9, x8
  [0x121A0] b.ne #0x12214
  [0x121A4] adrp x16, #0x12000
  [0x121A8] add x16, x16, #0
  [0x121AC] ldr w9, [x16]
  [0x121B0] mov x9, x9
  [0x121B4] mov x8, x14
  [0x121B8] sub x8, x8, x15 ;; misaligned with debug data
  [0x121BC] cmp x9, x8
  [0x121C0] b.ne #0x12214
  [0x121C4] adrp x16, #0x12000
  [0x121C8] add x16, x16, #0
  [0x121CC] ldr w9, [x16]
  [0x121D0] mov x9, x9
  [0x121D4] mov x8, x14
  [0x121D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x121DC] cmp x9, x8
  [0x121E0] b.ne #0x12214
  [0x121E4] adrp x16, #0x12000
  [0x121E8] add x16, x16, #0
  [0x121EC] ldr w9, [x16]
  [0x121F0] mov x9, x9
  [0x121F4] mov x8, x14
  [0x121F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x121FC] cmp x9, x8
  [0x12200] b.ne #0x12214
  [0x12204] adrp x16, #0x12000
  [0x12208] add x16, x16, #0
  [0x1220C] ldr w9, [x16]
  [0x12210] mov x9, x9
  [0x12214] mov x8, x14
  [0x12218] sub x8, x8, x15 ;; misaligned with debug data
  [0x1221C] cmp x9, x8
  [0x12220] b.eq #0x1236c
  [0x12224] movz x3, #0
  [0x12228] mov x5, x3
  [0x1222C] b #0x12348
  [0x12230] movz x9, #0xa30
  [0x12234] mul x9, x9, x5
  [0x12238] mov x8, x9
  [0x1223C] movz x1, #0x60
  [0x12240] ldr x9, [sp, #0xd8]
  [0x12244] add x1, x1, x9
  [0x12248] add x8, x8, x1
  [0x1224C] mov x8, x8
  [0x12250] add x16, x8, x15
  [0x12254] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x12258] adrp x1, #0x12000
  [0x1225C] add x1, x1, #0
  [0x12260] cmp x9, x1
  [0x12264] b.ne #0x12330
  [0x12268] add x16, x8, x15
  [0x1226C] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x12270] add x16, x9, x15
  [0x12274] ldr w3, [x16, #0x98] ;; misaligned with debug data
  [0x12278] mov x12, x3
  [0x1227C] movz x9, #0
  [0x12280] cmp x12, x9
  [0x12284] b.eq #0x12320
  [0x12288] movz x3, #0
  [0x1228C] mov x3, x3
  [0x12290] b #0x12300
  [0x12294] mov x9, x3
  [0x12298] lsl x9, x9, #5
  [0x1229C] mov x9, x9
  [0x122A0] movz x8, #0x20
  [0x122A4] add x8, x8, x12
  [0x122A8] add x9, x9, x8
  [0x122AC] add x16, x9, x15
  [0x122B0] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x122B4] add x16, x7, x15
  [0x122B8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x122BC] add x16, x9, x15
  [0x122C0] ldr w9, [x16, #0x7c] ;; misaligned with debug data
  [0x122C4] mov x9, x9
  [0x122C8] mov x7, x7
  [0x122CC] add x9, x9, x15
  [0x122D0] stp x3, x5, [sp, #-0x10]!
  [0x122D4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x122D8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x122DC] blr x9 ;; misaligned with debug data
  [0x122E0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x122E4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x122E8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x122EC] mov x10, x10
  [0x122F0] mov x3, x3
  [0x122F4] movz x9, #0x1
  [0x122F8] add x3, x3, x9
  [0x122FC] mov x3, x3
  [0x12300] add x16, x12, x15
  [0x12304] ldrsh x9, [x16, #2] ;; misaligned with debug data
  [0x12308] cmp x3, x9
  [0x1230C] b.lt #0x12294
  [0x12310] mov x9, x14
  [0x12314] sub x9, x9, x15 ;; misaligned with debug data
  [0x12318] mov x9, x9
  [0x1231C] b #0x12328
  [0x12320] mov x9, x14
  [0x12324] sub x9, x9, x15 ;; misaligned with debug data
  [0x12328] mov x9, x9
  [0x1232C] b #0x12338
  [0x12330] mov x9, x14
  [0x12334] sub x9, x9, x15 ;; misaligned with debug data
  [0x12338] mov x3, x5
  [0x1233C] movz x9, #0x1
  [0x12340] add x3, x3, x9
  [0x12344] mov x5, x3
  [0x12348] ldr x9, [sp, #0xd8]
  [0x1234C] add x16, x9, x15
  [0x12350] ldrsw x8, [x16] ;; misaligned with debug data
  [0x12354] cmp x5, x8
  [0x12358] b.lt #0x12230
  [0x1235C] mov x9, x14
  [0x12360] sub x9, x9, x15 ;; misaligned with debug data
  [0x12364] mov x9, x9
  [0x12368] b #0x12374
  [0x1236C] mov x9, x14
  [0x12370] sub x9, x9, x15 ;; misaligned with debug data
  [0x12374] add sp, sp, #0xe0
  [0x12378] ldp x29, x30, [sp], #0x10
  [0x1237C] ret


[(method inspect entity-actor)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] ldr w7, [x16]
  [0x10028] movz x6, #0x3
  [0x1002C] mov x9, x9
  [0x10030] mov x7, x7
  [0x10034] mov x6, x6
  [0x10038] add x9, x9, x15
  [0x1003C] stp x3, x5, [sp, #-0x10]!
  [0x10040] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10044] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10048] blr x9 ;; misaligned with debug data
  [0x1004C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10050] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10054] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10058] mov x0, x0
  [0x1005C] mov x0, x0
  [0x10060] mov x9, x0
  [0x10064] mov x7, x3
  [0x10068] add x9, x9, x15
  [0x1006C] stp x3, x5, [sp, #-0x10]!
  [0x10070] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10074] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10078] blr x9 ;; misaligned with debug data
  [0x1007C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10080] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10084] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10088] mov x0, x0
  [0x1008C] adrp x16, #0x10000
  [0x10090] add x16, x16, #0
  [0x10094] ldr w9, [x16]
  [0x10098] add x7, x14, #8
  [0x1009C] sub x7, x7, x15 ;; misaligned with debug data
  [0x100A0] adrp x6, #0x19000
  [0x100A4] add x6, x6, #0xb34
  [0x100A8] sub x6, x6, x15
  [0x100AC] add x16, x3, x15
  [0x100B0] ldr w2, [x16, #0x30] ;; misaligned with debug data
  [0x100B4] mov x9, x9
  [0x100B8] mov x7, x7
  [0x100BC] mov x6, x6
  [0x100C0] mov x2, x2
  [0x100C4] add x9, x9, x15
  [0x100C8] stp x3, x5, [sp, #-0x10]!
  [0x100CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D4] blr x9 ;; misaligned with debug data
  [0x100D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100E4] mov x0, x0
  [0x100E8] adrp x16, #0x10000
  [0x100EC] add x16, x16, #0
  [0x100F0] ldr w9, [x16]
  [0x100F4] add x7, x14, #8
  [0x100F8] sub x7, x7, x15 ;; misaligned with debug data
  [0x100FC] adrp x6, #0x19000
  [0x10100] add x6, x6, #0xb54
  [0x10104] sub x6, x6, x15
  [0x10108] add x16, x3, x15
  [0x1010C] ldr w2, [x16, #0x34] ;; misaligned with debug data
  [0x10110] mov x9, x9
  [0x10114] mov x7, x7
  [0x10118] mov x6, x6
  [0x1011C] mov x2, x2
  [0x10120] add x9, x9, x15
  [0x10124] stp x3, x5, [sp, #-0x10]!
  [0x10128] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1012C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10130] blr x9 ;; misaligned with debug data
  [0x10134] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10138] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1013C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10140] mov x0, x0
  [0x10144] adrp x16, #0x10000
  [0x10148] add x16, x16, #0
  [0x1014C] ldr w9, [x16]
  [0x10150] add x7, x14, #8
  [0x10154] sub x7, x7, x15 ;; misaligned with debug data
  [0x10158] adrp x6, #0x19000
  [0x1015C] add x6, x6, #0xb74
  [0x10160] sub x6, x6, x15
  [0x10164] add x16, x3, x15
  [0x10168] ldrb w2, [x16, #0x38] ;; misaligned with debug data
  [0x1016C] mov x9, x9
  [0x10170] mov x7, x7
  [0x10174] mov x6, x6
  [0x10178] mov x2, x2
  [0x1017C] add x9, x9, x15
  [0x10180] stp x3, x5, [sp, #-0x10]!
  [0x10184] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10188] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1018C] blr x9 ;; misaligned with debug data
  [0x10190] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10194] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10198] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1019C] mov x0, x0
  [0x101A0] adrp x16, #0x10000
  [0x101A4] add x16, x16, #0
  [0x101A8] ldr w9, [x16]
  [0x101AC] add x7, x14, #8
  [0x101B0] sub x7, x7, x15 ;; misaligned with debug data
  [0x101B4] adrp x6, #0x19000
  [0x101B8] add x6, x6, #0xb94
  [0x101BC] sub x6, x6, x15
  [0x101C0] add x16, x3, x15
  [0x101C4] ldrsh x2, [x16, #0x3a] ;; misaligned with debug data
  [0x101C8] mov x9, x9
  [0x101CC] mov x7, x7
  [0x101D0] mov x6, x6
  [0x101D4] mov x2, x2
  [0x101D8] add x9, x9, x15
  [0x101DC] stp x3, x5, [sp, #-0x10]!
  [0x101E0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101E4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101E8] blr x9 ;; misaligned with debug data
  [0x101EC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101F0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101F4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101F8] mov x0, x0
  [0x101FC] adrp x16, #0x10000
  [0x10200] add x16, x16, #0
  [0x10204] ldr w9, [x16]
  [0x10208] add x7, x14, #8
  [0x1020C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10210] adrp x6, #0x19000
  [0x10214] add x6, x6, #0xbb4
  [0x10218] sub x6, x6, x15
  [0x1021C] movz x2, #0x3c
  [0x10220] add x2, x2, x3
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
  [0x10258] mov x0, x3
  [0x1025C] add sp, sp, #0x10
  [0x10260] ldp x29, x30, [sp], #0x10
  [0x10264] ret


[anon-function-0]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] add x16, x3, x15
  [0x10020] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x10024] adrp x16, #0x10000
  [0x10028] add x16, x16, #0
  [0x1002C] ldr w6, [x16]
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
  [0x10060] mov x9, x14
  [0x10064] sub x9, x9, x15 ;; misaligned with debug data
  [0x10068] cmp x0, x9
  [0x1006C] b.eq #0x101b0
  [0x10070] add x16, x3, x15
  [0x10074] ldr w9, [x16, #0x7c] ;; misaligned with debug data
  [0x10078] movz x8, #0
  [0x1007C] cmp x9, x8
  [0x10080] b.eq #0x100d0
  [0x10084] add x16, x3, x15
  [0x10088] ldr w7, [x16, #0x7c] ;; misaligned with debug data
  [0x1008C] add x16, x7, x15
  [0x10090] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10094] add x16, x9, x15
  [0x10098] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x1009C] mov x9, x9
  [0x100A0] mov x7, x7
  [0x100A4] add x9, x9, x15
  [0x100A8] stp x3, x5, [sp, #-0x10]!
  [0x100AC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100B0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100B4] blr x9 ;; misaligned with debug data
  [0x100B8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100BC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100C0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100C4] mov x5, x5
  [0x100C8] mov x5, x5
  [0x100CC] b #0x100d8
  [0x100D0] mov x5, x14
  [0x100D4] sub x5, x5, x15 ;; misaligned with debug data
  [0x100D8] add x16, x3, x15
  [0x100DC] ldr w9, [x16, #0x84] ;; misaligned with debug data
  [0x100E0] movz x8, #0
  [0x100E4] cmp x9, x8
  [0x100E8] b.eq #0x10138
  [0x100EC] add x16, x3, x15
  [0x100F0] ldr w7, [x16, #0x84] ;; misaligned with debug data
  [0x100F4] add x16, x7, x15
  [0x100F8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100FC] add x16, x9, x15
  [0x10100] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10104] mov x9, x9
  [0x10108] mov x7, x7
  [0x1010C] add x9, x9, x15
  [0x10110] stp x3, x5, [sp, #-0x10]!
  [0x10114] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10118] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1011C] blr x9 ;; misaligned with debug data
  [0x10120] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10124] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10128] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1012C] mov x5, x5
  [0x10130] mov x5, x5
  [0x10134] b #0x10140
  [0x10138] mov x5, x14
  [0x1013C] sub x5, x5, x15 ;; misaligned with debug data
  [0x10140] add x16, x3, x15
  [0x10144] ldr w9, [x16, #0x88] ;; misaligned with debug data
  [0x10148] movz x8, #0
  [0x1014C] cmp x9, x8
  [0x10150] b.eq #0x101a0
  [0x10154] add x16, x3, x15
  [0x10158] ldr w7, [x16, #0x88] ;; misaligned with debug data
  [0x1015C] add x16, x7, x15
  [0x10160] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10164] add x16, x9, x15
  [0x10168] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x1016C] mov x9, x9
  [0x10170] mov x7, x7
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
  [0x1019C] b #0x101a8
  [0x101A0] mov x0, x14
  [0x101A4] sub x0, x0, x15 ;; misaligned with debug data
  [0x101A8] mov x0, x0
  [0x101AC] b #0x101b8
  [0x101B0] mov x0, x14
  [0x101B4] sub x0, x0, x15 ;; misaligned with debug data
  [0x101B8] add sp, sp, #0x10
  [0x101BC] ldp x29, x30, [sp], #0x10
  [0x101C0] ret


[process-status-bits]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x10, x7
  [0x10010] mov x5, x6
  [0x10014] mov x3, x10
  [0x10018] movz x9, #0
  [0x1001C] mov x8, x14
  [0x10020] sub x8, x8, x15 ;; misaligned with debug data
  [0x10024] cmp x3, x9
  [0x10028] b.eq #0x10038
  [0x1002C] add x8, x14, #8
  [0x10030] sub x8, x8, x15 ;; misaligned with debug data
  [0x10034] mov x8, x8
  [0x10038] mov x9, x8
  [0x1003C] mov x8, x14
  [0x10040] sub x8, x8, x15 ;; misaligned with debug data
  [0x10044] cmp x9, x8
  [0x10048] b.eq #0x100a0
  [0x1004C] adrp x16, #0x10000
  [0x10050] add x16, x16, #0
  [0x10054] ldr w9, [x16]
  [0x10058] add x16, x3, x15
  [0x1005C] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x10060] adrp x16, #0x10000
  [0x10064] add x16, x16, #0
  [0x10068] ldr w6, [x16]
  [0x1006C] mov x9, x9
  [0x10070] mov x7, x7
  [0x10074] mov x6, x6
  [0x10078] add x9, x9, x15
  [0x1007C] stp x3, x5, [sp, #-0x10]!
  [0x10080] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10084] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10088] blr x9 ;; misaligned with debug data
  [0x1008C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10090] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10094] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10098] mov x0, x0
  [0x1009C] mov x9, x0
  [0x100A0] mov x8, x14
  [0x100A4] sub x8, x8, x15 ;; misaligned with debug data
  [0x100A8] cmp x9, x8
  [0x100AC] b.eq #0x100bc
  [0x100B0] mov x3, x3
  [0x100B4] mov x3, x3
  [0x100B8] b #0x100c4
  [0x100BC] mov x3, x14
  [0x100C0] sub x3, x3, x15 ;; misaligned with debug data
  [0x100C4] mov x3, x3
  [0x100C8] mov x11, x3
  [0x100CC] mov x9, x11
  [0x100D0] mov x9, x9
  [0x100D4] mov x8, x14
  [0x100D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100DC] cmp x9, x8
  [0x100E0] b.eq #0x10110
  [0x100E4] add x16, x11, x15
  [0x100E8] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x100EC] movz x8, #0
  [0x100F0] mov x1, x14
  [0x100F4] sub x1, x1, x15 ;; misaligned with debug data
  [0x100F8] cmp x9, x8
  [0x100FC] b.ne #0x1010c
  [0x10100] add x1, x14, #8
  [0x10104] sub x1, x1, x15 ;; misaligned with debug data
  [0x10108] mov x1, x1
  [0x1010C] mov x9, x1
  [0x10110] mov x8, x14
  [0x10114] sub x8, x8, x15 ;; misaligned with debug data
  [0x10118] cmp x9, x8
  [0x1011C] b.eq #0x10138
  [0x10120] mov x9, x14
  [0x10124] sub x9, x9, x15 ;; misaligned with debug data
  [0x10128] mov x9, x9
  [0x1012C] mov x11, x9
  [0x10130] mov x9, x9
  [0x10134] b #0x10140
  [0x10138] mov x9, x14
  [0x1013C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10140] adrp x16, #0x10000
  [0x10144] add x16, x16, #0
  [0x10148] ldr w12, [x16]
  [0x1014C] adrp x3, #0x10000
  [0x10150] add x3, x3, #0x404
  [0x10154] sub x3, x3, x15
  [0x10158] mov x9, x10
  [0x1015C] mov x8, x14
  [0x10160] sub x8, x8, x15 ;; misaligned with debug data
  [0x10164] cmp x9, x8
  [0x10168] b.eq #0x10204
  [0x1016C] adrp x16, #0x10000
  [0x10170] add x16, x16, #0
  [0x10174] ldr w9, [x16]
  [0x10178] add x16, x9, x15
  [0x1017C] ldr w9, [x16] ;; misaligned with debug data
  [0x10180] add x16, x10, x15
  [0x10184] ldr w8, [x16, #4] ;; misaligned with debug data
  [0x10188] mov x9, x9
  [0x1018C] and x9, x9, x8
  [0x10190] movz x8, #0
  [0x10194] mov x1, x14
  [0x10198] sub x1, x1, x15 ;; misaligned with debug data
  [0x1019C] cmp x9, x8
  [0x101A0] b.ne #0x101b0
  [0x101A4] add x1, x14, #8
  [0x101A8] sub x1, x1, x15 ;; misaligned with debug data
  [0x101AC] mov x1, x1
  [0x101B0] mov x9, x1
  [0x101B4] mov x8, x14
  [0x101B8] sub x8, x8, x15 ;; misaligned with debug data
  [0x101BC] cmp x9, x8
  [0x101C0] b.eq #0x10204
  [0x101C4] add x16, x10, x15
  [0x101C8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x101CC] add x16, x9, x15
  [0x101D0] ldr w9, [x16, #0x40] ;; misaligned with debug data
  [0x101D4] mov x9, x9
  [0x101D8] mov x7, x10
  [0x101DC] add x9, x9, x15
  [0x101E0] stp x3, x5, [sp, #-0x10]!
  [0x101E4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x101E8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101EC] blr x9 ;; misaligned with debug data
  [0x101F0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101F4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101F8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101FC] mov x0, x0
  [0x10200] mov x9, x0
  [0x10204] mov x8, x14
  [0x10208] sub x8, x8, x15 ;; misaligned with debug data
  [0x1020C] cmp x9, x8
  [0x10210] b.eq #0x10220
  [0x10214] movz x2, #0x72
  [0x10218] mov x2, x2
  [0x1021C] b #0x10228
  [0x10220] movz x2, #0x20
  [0x10224] mov x2, x2
  [0x10228] mov x9, x11
  [0x1022C] mov x8, x14
  [0x10230] sub x8, x8, x15 ;; misaligned with debug data
  [0x10234] cmp x9, x8
  [0x10238] b.eq #0x1027c
  [0x1023C] add x16, x11, x15
  [0x10240] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x10244] add x16, x9, x15
  [0x10248] ldrb w9, [x16] ;; misaligned with debug data
  [0x1024C] movz x8, #0x8
  [0x10250] mov x9, x9
  [0x10254] and x9, x9, x8
  [0x10258] movz x8, #0
  [0x1025C] mov x1, x14
  [0x10260] sub x1, x1, x15 ;; misaligned with debug data
  [0x10264] cmp x9, x8
  [0x10268] b.eq #0x10278
  [0x1026C] add x1, x14, #8
  [0x10270] sub x1, x1, x15 ;; misaligned with debug data
  [0x10274] mov x1, x1
  [0x10278] mov x9, x1
  [0x1027C] mov x8, x14
  [0x10280] sub x8, x8, x15 ;; misaligned with debug data
  [0x10284] cmp x9, x8
  [0x10288] b.eq #0x10298
  [0x1028C] movz x1, #0x64
  [0x10290] mov x1, x1
  [0x10294] b #0x102a0
  [0x10298] movz x1, #0x20
  [0x1029C] mov x1, x1
  [0x102A0] mov x9, x11
  [0x102A4] mov x8, x14
  [0x102A8] sub x8, x8, x15 ;; misaligned with debug data
  [0x102AC] cmp x9, x8
  [0x102B0] b.eq #0x102f4
  [0x102B4] add x16, x11, x15
  [0x102B8] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x102BC] add x16, x9, x15
  [0x102C0] ldrb w9, [x16] ;; misaligned with debug data
  [0x102C4] movz x8, #0x8
  [0x102C8] mov x9, x9
  [0x102CC] and x9, x9, x8
  [0x102D0] movz x8, #0
  [0x102D4] mov x6, x14
  [0x102D8] sub x6, x6, x15 ;; misaligned with debug data
  [0x102DC] cmp x9, x8
  [0x102E0] b.eq #0x102f0
  [0x102E4] add x6, x14, #8
  [0x102E8] sub x6, x6, x15 ;; misaligned with debug data
  [0x102EC] mov x6, x6
  [0x102F0] mov x9, x6
  [0x102F4] mov x8, x14
  [0x102F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x102FC] cmp x9, x8
  [0x10300] b.eq #0x103a0
  [0x10304] add x16, x11, x15
  [0x10308] ldr w9, [x16, #0x74] ;; misaligned with debug data
  [0x1030C] add x16, x9, x15
  [0x10310] ldrsb x9, [x16, #0x3a] ;; misaligned with debug data
  [0x10314] mov x9, x9
  [0x10318] movz x8, #0
  [0x1031C] cmp x9, x8
  [0x10320] b.ne #0x10330
  [0x10324] movz x8, #0x30
  [0x10328] mov x8, x8
  [0x1032C] b #0x10398
  [0x10330] movz x8, #0x1
  [0x10334] cmp x9, x8
  [0x10338] b.ne #0x10348
  [0x1033C] movz x8, #0x31
  [0x10340] mov x8, x8
  [0x10344] b #0x10398
  [0x10348] movz x8, #0x2
  [0x1034C] cmp x9, x8
  [0x10350] b.ne #0x10360
  [0x10354] movz x8, #0x32
  [0x10358] mov x8, x8
  [0x1035C] b #0x10398
  [0x10360] movz x8, #0x3
  [0x10364] cmp x9, x8
  [0x10368] b.ne #0x10378
  [0x1036C] movz x8, #0x33
  [0x10370] mov x8, x8
  [0x10374] b #0x10398
  [0x10378] movz x8, #0x4
  [0x1037C] cmp x9, x8
  [0x10380] b.ne #0x10390
  [0x10384] movz x8, #0x34
  [0x10388] mov x8, x8
  [0x1038C] b #0x10398
  [0x10390] mov x8, x14
  [0x10394] sub x8, x8, x15 ;; misaligned with debug data
  [0x10398] mov x8, x8
  [0x1039C] b #0x103a8
  [0x103A0] movz x8, #0x20
  [0x103A4] mov x8, x8
  [0x103A8] mov x12, x12
  [0x103AC] mov x7, x5
  [0x103B0] mov x6, x3
  [0x103B4] mov x2, x2
  [0x103B8] mov x1, x1
  [0x103BC] mov x8, x8
  [0x103C0] add x12, x12, x15
  [0x103C4] stp x3, x5, [sp, #-0x10]!
  [0x103C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x103CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x103D0] blr x12 ;; misaligned with debug data
  [0x103D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x103D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x103DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x103E0] mov x0, x0
  [0x103E4] movz x9, #0
  [0x103E8] add sp, sp, #0x10
  [0x103EC] ldp x29, x30, [sp], #0x10
  [0x103F0] ret


[(method inspect entity)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] adrp x16, #0x10000
  [0x10020] add x16, x16, #0
  [0x10024] ldr w7, [x16]
  [0x10028] movz x6, #0x3
  [0x1002C] mov x9, x9
  [0x10030] mov x7, x7
  [0x10034] mov x6, x6
  [0x10038] add x9, x9, x15
  [0x1003C] stp x3, x5, [sp, #-0x10]!
  [0x10040] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10044] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10048] blr x9 ;; misaligned with debug data
  [0x1004C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10050] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10054] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10058] mov x0, x0
  [0x1005C] mov x0, x0
  [0x10060] mov x9, x0
  [0x10064] mov x7, x3
  [0x10068] add x9, x9, x15
  [0x1006C] stp x3, x5, [sp, #-0x10]!
  [0x10070] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10074] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10078] blr x9 ;; misaligned with debug data
  [0x1007C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10080] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10084] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10088] mov x0, x0
  [0x1008C] adrp x16, #0x10000
  [0x10090] add x16, x16, #0
  [0x10094] ldr w9, [x16]
  [0x10098] add x7, x14, #8
  [0x1009C] sub x7, x7, x15 ;; misaligned with debug data
  [0x100A0] adrp x6, #0x19000
  [0x100A4] add x6, x6, #0xaf4
  [0x100A8] sub x6, x6, x15
  [0x100AC] movz x2, #0x1c
  [0x100B0] add x2, x2, x3
  [0x100B4] mov x9, x9
  [0x100B8] mov x7, x7
  [0x100BC] mov x6, x6
  [0x100C0] mov x2, x2
  [0x100C4] add x9, x9, x15
  [0x100C8] stp x3, x5, [sp, #-0x10]!
  [0x100CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D4] blr x9 ;; misaligned with debug data
  [0x100D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100E4] mov x0, x0
  [0x100E8] adrp x16, #0x10000
  [0x100EC] add x16, x16, #0
  [0x100F0] ldr w9, [x16]
  [0x100F4] add x7, x14, #8
  [0x100F8] sub x7, x7, x15 ;; misaligned with debug data
  [0x100FC] adrp x6, #0x19000
  [0x10100] add x6, x6, #0xb14
  [0x10104] sub x6, x6, x15
  [0x10108] add x16, x3, x15
  [0x1010C] ldr w2, [x16, #0x2c] ;; misaligned with debug data
  [0x10110] mov x9, x9
  [0x10114] mov x7, x7
  [0x10118] mov x6, x6
  [0x1011C] mov x2, x2
  [0x10120] add x9, x9, x15
  [0x10124] stp x3, x5, [sp, #-0x10]!
  [0x10128] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1012C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10130] blr x9 ;; misaligned with debug data
  [0x10134] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10138] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1013C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10140] mov x0, x0
  [0x10144] mov x0, x3
  [0x10148] add sp, sp, #0x10
  [0x1014C] ldp x29, x30, [sp], #0x10
  [0x10150] ret


[(method set-or-clear-status! entity-actor)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x2, x2
  [0x10014] add x16, x7, x15
  [0x10018] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x1001C] mov x9, x9
  [0x10020] mov x8, x14
  [0x10024] sub x8, x8, x15 ;; misaligned with debug data
  [0x10028] cmp x2, x8
  [0x1002C] b.eq #0x10050
  [0x10030] add x16, x9, x15
  [0x10034] ldrh w8, [x16, #0x38] ;; misaligned with debug data
  [0x10038] mov x8, x8
  [0x1003C] orr x8, x8, x6
  [0x10040] add x16, x9, x15
  [0x10044] strh w8, [x16, #0x38] ;; misaligned with debug data
  [0x10048] mov x8, x8
  [0x1004C] b #0x10074
  [0x10050] add x16, x9, x15
  [0x10054] ldrh w8, [x16, #0x38] ;; misaligned with debug data
  [0x10058] mov x6, x6
  [0x1005C] mvn x6, x6
  [0x10060] mov x8, x8
  [0x10064] and x8, x8, x6
  [0x10068] add x16, x9, x15
  [0x1006C] strh w8, [x16, #0x38] ;; misaligned with debug data
  [0x10070] mov x8, x8
  [0x10074] add x16, x9, x15
  [0x10078] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1007C] ldp x29, x30, [sp], #0x10
  [0x10080] ret


[entity-birth-no-kill]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] add x16, x7, x15
  [0x10014] ldr w3, [x16, #0x14] ;; misaligned with debug data
  [0x10018] mov x3, x3
  [0x1001C] add x16, x3, x15
  [0x10020] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10024] mov x9, x9
  [0x10028] movz x8, #0x8
  [0x1002C] orr x9, x9, x8
  [0x10030] add x16, x3, x15
  [0x10034] strh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10038] add x16, x3, x15
  [0x1003C] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10040] mov x9, x9
  [0x10044] mov x8, x14
  [0x10048] sub x8, x8, x15 ;; misaligned with debug data
  [0x1004C] cmp x9, x8
  [0x10050] b.ne #0x1008c
  [0x10054] add x16, x3, x15
  [0x10058] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x1005C] movz x8, #0x5
  [0x10060] mov x9, x9
  [0x10064] and x9, x9, x8
  [0x10068] movz x8, #0
  [0x1006C] mov x1, x14
  [0x10070] sub x1, x1, x15 ;; misaligned with debug data
  [0x10074] cmp x9, x8
  [0x10078] b.eq #0x10088
  [0x1007C] add x1, x14, #8
  [0x10080] sub x1, x1, x15 ;; misaligned with debug data
  [0x10084] mov x1, x1
  [0x10088] mov x9, x1
  [0x1008C] mov x8, x14
  [0x10090] sub x8, x8, x15 ;; misaligned with debug data
  [0x10094] cmp x9, x8
  [0x10098] b.ne #0x100e8
  [0x1009C] add x16, x3, x15
  [0x100A0] ldr w7, [x16, #8] ;; misaligned with debug data
  [0x100A4] add x16, x7, x15
  [0x100A8] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100AC] add x16, x9, x15
  [0x100B0] ldr w9, [x16, #0x68] ;; misaligned with debug data
  [0x100B4] mov x9, x9
  [0x100B8] mov x7, x7
  [0x100BC] add x9, x9, x15
  [0x100C0] stp x3, x5, [sp, #-0x10]!
  [0x100C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100CC] blr x9 ;; misaligned with debug data
  [0x100D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] mov x0, x0
  [0x100E0] mov x0, x0
  [0x100E4] b #0x100f0
  [0x100E8] mov x0, x14
  [0x100EC] sub x0, x0, x15 ;; misaligned with debug data
  [0x100F0] add x16, x3, x15
  [0x100F4] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x100F8] add sp, sp, #0x10
  [0x100FC] ldp x29, x30, [sp], #0x10
  [0x10100] ret


[entity-remap-names]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] add x16, x5, x15
  [0x10014] ldursw x3, [x16, #-2] ;; misaligned with debug data
  [0x10018] mov x3, x3
  [0x1001C] b #0x101c4
  [0x10020] adrp x16, #0x10000
  [0x10024] add x16, x16, #0
  [0x10028] ldr w9, [x16]
  [0x1002C] add x16, x3, x15
  [0x10030] ldursw x8, [x16, #2] ;; misaligned with debug data
  [0x10034] add x16, x8, x15
  [0x10038] ldursw x8, [x16, #-2] ;; misaligned with debug data
  [0x1003C] mov x8, x8
  [0x10040] mov x8, x8
  [0x10044] asr x8, x8, #3
  [0x10048] scvtf s23, w8
  [0x1004C] add x16, x3, x15
  [0x10050] ldursw x8, [x16, #2] ;; misaligned with debug data
  [0x10054] add x16, x8, x15
  [0x10058] ldursw x8, [x16, #2] ;; misaligned with debug data
  [0x1005C] add x16, x8, x15
  [0x10060] ldursw x8, [x16, #-2] ;; misaligned with debug data
  [0x10064] mov x8, x8
  [0x10068] mov x8, x8
  [0x1006C] asr x8, x8, #3
  [0x10070] scvtf s22, w8
  [0x10074] add x16, x3, x15
  [0x10078] ldursw x8, [x16, #2] ;; misaligned with debug data
  [0x1007C] add x16, x8, x15
  [0x10080] ldursw x8, [x16, #2] ;; misaligned with debug data
  [0x10084] add x16, x8, x15
  [0x10088] ldursw x8, [x16, #2] ;; misaligned with debug data
  [0x1008C] add x16, x8, x15
  [0x10090] ldursw x8, [x16, #-2] ;; misaligned with debug data
  [0x10094] mov x8, x8
  [0x10098] mov x8, x8
  [0x1009C] asr x8, x8, #3
  [0x100A0] scvtf s21, w8
  [0x100A4] mov x9, x9
  [0x100A8] fmov w7, s23
  [0x100AC] sxtw x7, w7
  [0x100B0] fmov w6, s22
  [0x100B4] sxtw x6, w6
  [0x100B8] fmov w2, s21
  [0x100BC] sxtw x2, w2
  [0x100C0] add x9, x9, x15
  [0x100C4] stp x3, x5, [sp, #-0x10]!
  [0x100C8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100CC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D0] blr x9 ;; misaligned with debug data
  [0x100D4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100D8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100E0] mov x0, x0
  [0x100E4] mov x0, x0
  [0x100E8] mov x9, x14
  [0x100EC] sub x9, x9, x15 ;; misaligned with debug data
  [0x100F0] cmp x0, x9
  [0x100F4] b.eq #0x101a4
  [0x100F8] adrp x9, #0x10000
  [0x100FC] add x9, x9, #0
  [0x10100] adrp x16, #0x10000
  [0x10104] add x16, x16, #0
  [0x10108] ldr w8, [x16]
  [0x1010C] movz x1, #0
  [0x10110] movk x1, #0x6b28, lsl #32
  [0x10114] movk x1, #0xce6e, lsl #48
  [0x10118] movz x2, #0
  [0x1011C] movk x2, #0x1, lsl #48
  [0x10120] mov x9, x9
  [0x10124] lsl x9, x9, #0x20
  [0x10128] lsr x9, x9, #0x20
  [0x1012C] orr x1, x1, x9
  [0x10130] mov x8, x8
  [0x10134] lsl x8, x8, #0x20
  [0x10138] lsr x8, x8, #0x20
  [0x1013C] orr x2, x2, x8
  [0x10140] fmov d23, x1
  [0x10144] fmov d17, x2
  [0x10148] zip1 v17.2d, v23.2d, v17.2d
  [0x1014C] add x16, x3, x15
  [0x10150] ldursw x6, [x16, #-2] ;; misaligned with debug data
  [0x10154] mov x6, x6
  [0x10158] add x16, x0, x15
  [0x1015C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10160] add x16, x9, x15
  [0x10164] ldr w9, [x16, #0x54] ;; misaligned with debug data
  [0x10168] mov x9, x9
  [0x1016C] mov x7, x0
  [0x10170] mov v17.16b, v17.16b
  [0x10174] mov x6, x6
  [0x10178] add x9, x9, x15
  [0x1017C] stp x3, x5, [sp, #-0x10]!
  [0x10180] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10184] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10188] blr x9 ;; misaligned with debug data
  [0x1018C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10190] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10194] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10198] mov x0, x0
  [0x1019C] mov x0, x0
  [0x101A0] b #0x101ac
  [0x101A4] mov x0, x14
  [0x101A8] sub x0, x0, x15 ;; misaligned with debug data
  [0x101AC] add x16, x5, x15
  [0x101B0] ldursw x3, [x16, #2] ;; misaligned with debug data
  [0x101B4] mov x5, x3
  [0x101B8] add x16, x5, x15
  [0x101BC] ldursw x3, [x16, #-2] ;; misaligned with debug data
  [0x101C0] mov x3, x3
  [0x101C4] sub x9, x14, #0xa
  [0x101C8] sub x9, x9, x15 ;; misaligned with debug data
  [0x101CC] cmp x5, x9
  [0x101D0] b.ne #0x10020
  [0x101D4] mov x9, x14
  [0x101D8] sub x9, x9, x15 ;; misaligned with debug data
  [0x101DC] movz x9, #0
  [0x101E0] add sp, sp, #0x10
  [0x101E4] ldp x29, x30, [sp], #0x10
  [0x101E8] ret


[(method kill! entity-actor)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] add x16, x3, x15
  [0x10014] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10018] add x16, x9, x15
  [0x1001C] ldr w7, [x16, #0xc] ;; misaligned with debug data
  [0x10020] mov x7, x7
  [0x10024] mov x9, x14
  [0x10028] sub x9, x9, x15 ;; misaligned with debug data
  [0x1002C] cmp x7, x9
  [0x10030] b.eq #0x10078
  [0x10034] add x16, x7, x15
  [0x10038] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1003C] add x16, x9, x15
  [0x10040] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x10044] mov x9, x9
  [0x10048] mov x7, x7
  [0x1004C] add x9, x9, x15
  [0x10050] stp x3, x5, [sp, #-0x10]!
  [0x10054] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10058] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1005C] blr x9 ;; misaligned with debug data
  [0x10060] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10064] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10068] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1006C] mov x5, x5
  [0x10070] mov x5, x5
  [0x10074] b #0x100b8
  [0x10078] adrp x16, #0x10000
  [0x1007C] add x16, x16, #0
  [0x10080] ldr w9, [x16]
  [0x10084] mov x9, x9
  [0x10088] mov x7, x7
  [0x1008C] mov x6, x3
  [0x10090] add x9, x9, x15
  [0x10094] stp x3, x5, [sp, #-0x10]!
  [0x10098] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1009C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A0] blr x9 ;; misaligned with debug data
  [0x100A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100B0] mov x5, x5
  [0x100B4] mov x5, x5
  [0x100B8] mov x0, x3
  [0x100BC] add sp, sp, #0x10
  [0x100C0] ldp x29, x30, [sp], #0x10
  [0x100C4] ret


[entity-count]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] movz x0, #0
  [0x1000C] mov x0, x0
  [0x10010] movz x9, #0
  [0x10014] mov x9, x9
  [0x10018] b #0x100fc
  [0x1001C] movz x8, #0xa30
  [0x10020] mul x8, x8, x9
  [0x10024] mov x8, x8
  [0x10028] movz x1, #0x60
  [0x1002C] adrp x16, #0x10000
  [0x10030] add x16, x16, #0
  [0x10034] ldr w2, [x16]
  [0x10038] add x1, x1, x2
  [0x1003C] add x8, x8, x1
  [0x10040] mov x8, x8
  [0x10044] add x16, x8, x15
  [0x10048] ldr w1, [x16, #0x10] ;; misaligned with debug data
  [0x1004C] adrp x2, #0x10000
  [0x10050] add x2, x2, #0
  [0x10054] cmp x1, x2
  [0x10058] b.ne #0x100e4
  [0x1005C] add x16, x8, x15
  [0x10060] ldr w8, [x16, #0x2c] ;; misaligned with debug data
  [0x10064] add x16, x8, x15
  [0x10068] ldr w8, [x16, #0x78] ;; misaligned with debug data
  [0x1006C] add x16, x8, x15
  [0x10070] ldr w8, [x16, #0x118] ;; misaligned with debug data
  [0x10074] mov x8, x8
  [0x10078] movz x1, #0
  [0x1007C] mov x1, x1
  [0x10080] b #0x100c4
  [0x10084] mov x2, x1
  [0x10088] lsl x2, x2, #6
  [0x1008C] mov x2, x2
  [0x10090] movz x6, #0xc
  [0x10094] add x6, x6, x8
  [0x10098] add x2, x2, x6
  [0x1009C] add x16, x2, x15
  [0x100A0] ldr w2, [x16, #8] ;; misaligned with debug data
  [0x100A4] mov x0, x0
  [0x100A8] movz x2, #0x1
  [0x100AC] add x0, x0, x2
  [0x100B0] mov x0, x0
  [0x100B4] mov x1, x1
  [0x100B8] movz x2, #0x1
  [0x100BC] add x1, x1, x2
  [0x100C0] mov x1, x1
  [0x100C4] add x16, x8, x15
  [0x100C8] ldrsw x2, [x16] ;; misaligned with debug data
  [0x100CC] cmp x1, x2
  [0x100D0] b.lt #0x10084
  [0x100D4] mov x8, x14
  [0x100D8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100DC] mov x8, x8
  [0x100E0] b #0x100ec
  [0x100E4] mov x8, x14
  [0x100E8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100EC] mov x9, x9
  [0x100F0] movz x8, #0x1
  [0x100F4] add x9, x9, x8
  [0x100F8] mov x9, x9
  [0x100FC] adrp x16, #0x10000
  [0x10100] add x16, x16, #0
  [0x10104] ldr w8, [x16]
  [0x10108] add x16, x8, x15
  [0x1010C] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10110] cmp x9, x8
  [0x10114] b.lt #0x1001c
  [0x10118] mov x9, x14
  [0x1011C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10120] mov x0, x0
  [0x10124] ldp x29, x30, [sp], #0x10
  [0x10128] ret


[entity-process-count]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x12, x7
  [0x10010] movz x3, #0
  [0x10014] mov x5, x3
  [0x10018] movz x3, #0
  [0x1001C] mov x11, x3
  [0x10020] b #0x101e4
  [0x10024] movz x3, #0xa30
  [0x10028] mul x3, x3, x11
  [0x1002C] mov x3, x3
  [0x10030] movz x9, #0x60
  [0x10034] adrp x16, #0x10000
  [0x10038] add x16, x16, #0
  [0x1003C] ldr w8, [x16]
  [0x10040] add x9, x9, x8
  [0x10044] add x3, x3, x9
  [0x10048] mov x10, x3
  [0x1004C] add x16, x10, x15
  [0x10050] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10054] adrp x8, #0x10000
  [0x10058] add x8, x8, #0
  [0x1005C] cmp x9, x8
  [0x10060] b.ne #0x101cc
  [0x10064] add x16, x10, x15
  [0x10068] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x1006C] add x16, x9, x15
  [0x10070] ldr w9, [x16, #0x78] ;; misaligned with debug data
  [0x10074] add x16, x9, x15
  [0x10078] ldr w3, [x16, #0x118] ;; misaligned with debug data
  [0x1007C] mov x3, x3
  [0x10080] str x3, [sp]
  [0x10084] movz x3, #0
  [0x10088] mov x3, x3
  [0x1008C] b #0x101a8
  [0x10090] mov x9, x3
  [0x10094] lsl x9, x9, #6
  [0x10098] mov x8, x9
  [0x1009C] movz x1, #0xc
  [0x100A0] ldr x9, [sp]
  [0x100A4] add x1, x1, x9
  [0x100A8] add x8, x8, x1
  [0x100AC] add x16, x8, x15
  [0x100B0] ldr w9, [x16, #8] ;; misaligned with debug data
  [0x100B4] mov x9, x9
  [0x100B8] mov x8, x12
  [0x100BC] adrp x1, #0x10000
  [0x100C0] add x1, x1, #0
  [0x100C4] cmp x8, x1
  [0x100C8] b.ne #0x10154
  [0x100CC] add x16, x9, x15
  [0x100D0] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x100D4] add x16, x9, x15
  [0x100D8] ldrsw x6, [x16, #0x14] ;; misaligned with debug data
  [0x100DC] add x16, x10, x15
  [0x100E0] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x100E4] add x16, x9, x15
  [0x100E8] ldr w9, [x16, #0x38] ;; misaligned with debug data
  [0x100EC] mov x9, x9
  [0x100F0] mov x7, x10
  [0x100F4] mov x6, x6
  [0x100F8] add x9, x9, x15
  [0x100FC] stp x3, x5, [sp, #-0x10]!
  [0x10100] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10104] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10108] blr x9 ;; misaligned with debug data
  [0x1010C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10110] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10114] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10118] mov x0, x0
  [0x1011C] mov x9, x14
  [0x10120] sub x9, x9, x15 ;; misaligned with debug data
  [0x10124] cmp x0, x9
  [0x10128] b.eq #0x10144
  [0x1012C] mov x9, x5
  [0x10130] movz x8, #0x1
  [0x10134] add x9, x9, x8
  [0x10138] mov x5, x9
  [0x1013C] mov x9, x9
  [0x10140] b #0x1014c
  [0x10144] mov x9, x14
  [0x10148] sub x9, x9, x15 ;; misaligned with debug data
  [0x1014C] mov x9, x9
  [0x10150] b #0x10198
  [0x10154] add x16, x9, x15
  [0x10158] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x1015C] add x16, x9, x15
  [0x10160] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10164] mov x8, x14
  [0x10168] sub x8, x8, x15 ;; misaligned with debug data
  [0x1016C] cmp x9, x8
  [0x10170] b.eq #0x1018c
  [0x10174] mov x9, x5
  [0x10178] movz x8, #0x1
  [0x1017C] add x9, x9, x8
  [0x10180] mov x5, x9
  [0x10184] mov x9, x9
  [0x10188] b #0x10194
  [0x1018C] mov x9, x14
  [0x10190] sub x9, x9, x15 ;; misaligned with debug data
  [0x10194] mov x9, x9
  [0x10198] mov x3, x3
  [0x1019C] movz x9, #0x1
  [0x101A0] add x3, x3, x9
  [0x101A4] mov x3, x3
  [0x101A8] ldr x9, [sp]
  [0x101AC] add x16, x9, x15
  [0x101B0] ldrsw x8, [x16] ;; misaligned with debug data
  [0x101B4] cmp x3, x8
  [0x101B8] b.lt #0x10090
  [0x101BC] mov x9, x14
  [0x101C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x101C4] mov x9, x9
  [0x101C8] b #0x101d4
  [0x101CC] mov x9, x14
  [0x101D0] sub x9, x9, x15 ;; misaligned with debug data
  [0x101D4] mov x3, x11
  [0x101D8] movz x9, #0x1
  [0x101DC] add x3, x3, x9
  [0x101E0] mov x11, x3
  [0x101E4] adrp x16, #0x10000
  [0x101E8] add x16, x16, #0
  [0x101EC] ldr w9, [x16]
  [0x101F0] add x16, x9, x15
  [0x101F4] ldrsw x9, [x16] ;; misaligned with debug data
  [0x101F8] cmp x11, x9
  [0x101FC] b.lt #0x10024
  [0x10200] mov x9, x14
  [0x10204] sub x9, x9, x15 ;; misaligned with debug data
  [0x10208] mov x0, x5
  [0x1020C] add sp, sp, #0x10
  [0x10210] ldp x29, x30, [sp], #0x10
  [0x10214] ret


[process-by-ename]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x7, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] mov x9, x9
  [0x10020] mov x7, x7
  [0x10024] add x9, x9, x15
  [0x10028] stp x3, x5, [sp, #-0x10]!
  [0x1002C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10030] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10034] blr x9 ;; misaligned with debug data
  [0x10038] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1003C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10040] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10044] mov x0, x0
  [0x10048] mov x0, x0
  [0x1004C] mov x9, x14
  [0x10050] sub x9, x9, x15 ;; misaligned with debug data
  [0x10054] cmp x0, x9
  [0x10058] b.eq #0x10074
  [0x1005C] add x16, x0, x15
  [0x10060] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10064] add x16, x9, x15
  [0x10068] ldr w0, [x16, #0xc] ;; misaligned with debug data
  [0x1006C] mov x0, x0
  [0x10070] b #0x1007c
  [0x10074] mov x0, x14
  [0x10078] sub x0, x0, x15 ;; misaligned with debug data
  [0x1007C] mov x0, x0
  [0x10080] add sp, sp, #0x10
  [0x10084] ldp x29, x30, [sp], #0x10
  [0x10088] ret


[entity-by-meters]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x2, x2
  [0x10014] movz x9, #0
  [0x10018] mov x9, x9
  [0x1001C] b #0x10208
  [0x10020] movz x8, #0xa30
  [0x10024] mul x8, x8, x9
  [0x10028] mov x8, x8
  [0x1002C] movz x1, #0x60
  [0x10030] adrp x16, #0x10000
  [0x10034] add x16, x16, #0
  [0x10038] ldr w0, [x16]
  [0x1003C] add x1, x1, x0
  [0x10040] add x8, x8, x1
  [0x10044] mov x8, x8
  [0x10048] add x16, x8, x15
  [0x1004C] ldr w1, [x16, #0x10] ;; misaligned with debug data
  [0x10050] adrp x0, #0x10000
  [0x10054] add x0, x0, #0
  [0x10058] cmp x1, x0
  [0x1005C] b.ne #0x101f0
  [0x10060] add x16, x8, x15
  [0x10064] ldr w8, [x16, #0x2c] ;; misaligned with debug data
  [0x10068] add x16, x8, x15
  [0x1006C] ldr w8, [x16, #0x6c] ;; misaligned with debug data
  [0x10070] mov x8, x8
  [0x10074] movz x1, #0
  [0x10078] cmp x8, x1
  [0x1007C] b.eq #0x101e0
  [0x10080] movz x1, #0
  [0x10084] mov x1, x1
  [0x10088] b #0x101c0
  [0x1008C] mov x0, x1
  [0x10090] lsl x0, x0, #5
  [0x10094] mov x0, x0
  [0x10098] movz x3, #0x20
  [0x1009C] add x3, x3, x8
  [0x100A0] add x0, x0, x3
  [0x100A4] add x16, x0, x15
  [0x100A8] ldr w0, [x16, #4] ;; misaligned with debug data
  [0x100AC] mov x0, x0
  [0x100B0] movz x3, #0x20
  [0x100B4] add x16, x0, x15
  [0x100B8] ldr w5, [x16, #0x14] ;; misaligned with debug data
  [0x100BC] add x3, x3, x5
  [0x100C0] mov x3, x3
  [0x100C4] add x16, x3, x15
  [0x100C8] ldr s23, [x16] ;; misaligned with debug data
  [0x100CC] fcvtzs w5, s23
  [0x100D0] sxtw x5, w5
  [0x100D4] scvtf s23, w5
  [0x100D8] fmov s22, w7
  [0x100DC] mov x5, x14
  [0x100E0] sub x5, x5, x15 ;; misaligned with debug data
  [0x100E4] fcmp s23, s22
  [0x100E8] b.ne #0x100f8
  [0x100EC] add x5, x14, #8
  [0x100F0] sub x5, x5, x15 ;; misaligned with debug data
  [0x100F4] mov x5, x5
  [0x100F8] mov x5, x5
  [0x100FC] mov x12, x14
  [0x10100] sub x12, x12, x15 ;; misaligned with debug data
  [0x10104] cmp x5, x12
  [0x10108] b.eq #0x1018c
  [0x1010C] add x16, x3, x15
  [0x10110] ldr s23, [x16, #4] ;; misaligned with debug data
  [0x10114] fcvtzs w5, s23
  [0x10118] sxtw x5, w5
  [0x1011C] scvtf s23, w5
  [0x10120] fmov s22, w6
  [0x10124] mov x5, x14
  [0x10128] sub x5, x5, x15 ;; misaligned with debug data
  [0x1012C] fcmp s23, s22
  [0x10130] b.ne #0x10140
  [0x10134] add x5, x14, #8
  [0x10138] sub x5, x5, x15 ;; misaligned with debug data
  [0x1013C] mov x5, x5
  [0x10140] mov x5, x5
  [0x10144] mov x12, x14
  [0x10148] sub x12, x12, x15 ;; misaligned with debug data
  [0x1014C] cmp x5, x12
  [0x10150] b.eq #0x1018c
  [0x10154] add x16, x3, x15
  [0x10158] ldr s23, [x16, #8] ;; misaligned with debug data
  [0x1015C] fcvtzs w3, s23
  [0x10160] sxtw x3, w3
  [0x10164] scvtf s23, w3
  [0x10168] fmov s22, w2
  [0x1016C] mov x5, x14
  [0x10170] sub x5, x5, x15 ;; misaligned with debug data
  [0x10174] fcmp s23, s22
  [0x10178] b.ne #0x10188
  [0x1017C] add x5, x14, #8
  [0x10180] sub x5, x5, x15 ;; misaligned with debug data
  [0x10184] mov x5, x5
  [0x10188] mov x5, x5
  [0x1018C] mov x3, x14
  [0x10190] sub x3, x3, x15 ;; misaligned with debug data
  [0x10194] cmp x5, x3
  [0x10198] b.eq #0x101a8
  [0x1019C] mov x0, x0
  [0x101A0] b #0x1023c
  [0x101A4] b #0x101b0
  [0x101A8] mov x0, x14
  [0x101AC] sub x0, x0, x15 ;; misaligned with debug data
  [0x101B0] mov x1, x1
  [0x101B4] movz x0, #0x1
  [0x101B8] add x1, x1, x0
  [0x101BC] mov x1, x1
  [0x101C0] add x16, x8, x15
  [0x101C4] ldrsh x0, [x16, #2] ;; misaligned with debug data
  [0x101C8] cmp x1, x0
  [0x101CC] b.lt #0x1008c
  [0x101D0] mov x8, x14
  [0x101D4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101D8] mov x8, x8
  [0x101DC] b #0x101e8
  [0x101E0] mov x8, x14
  [0x101E4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101E8] mov x8, x8
  [0x101EC] b #0x101f8
  [0x101F0] mov x8, x14
  [0x101F4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101F8] mov x9, x9
  [0x101FC] movz x8, #0x1
  [0x10200] add x9, x9, x8
  [0x10204] mov x9, x9
  [0x10208] adrp x16, #0x10000
  [0x1020C] add x16, x16, #0
  [0x10210] ldr w8, [x16]
  [0x10214] add x16, x8, x15
  [0x10218] ldrsw x8, [x16] ;; misaligned with debug data
  [0x1021C] cmp x9, x8
  [0x10220] b.lt #0x10020
  [0x10224] mov x9, x14
  [0x10228] sub x9, x9, x15 ;; misaligned with debug data
  [0x1022C] mov x0, x14
  [0x10230] sub x0, x0, x15 ;; misaligned with debug data
  [0x10234] mov x0, x0
  [0x10238] mov x0, x0
  [0x1023C] ldp x29, x30, [sp], #0x10
  [0x10240] ret


[entity-by-type]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] movz x3, #0
  [0x10014] mov x12, x3
  [0x10018] b #0x101b4
  [0x1001C] movz x9, #0xa30
  [0x10020] mul x9, x9, x12
  [0x10024] mov x9, x9
  [0x10028] movz x8, #0x60
  [0x1002C] adrp x16, #0x10000
  [0x10030] add x16, x16, #0
  [0x10034] ldr w1, [x16]
  [0x10038] add x8, x8, x1
  [0x1003C] add x9, x9, x8
  [0x10040] mov x9, x9
  [0x10044] add x16, x9, x15
  [0x10048] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x1004C] adrp x1, #0x10000
  [0x10050] add x1, x1, #0
  [0x10054] cmp x8, x1
  [0x10058] b.ne #0x1019c
  [0x1005C] add x16, x9, x15
  [0x10060] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10064] add x16, x9, x15
  [0x10068] ldr w3, [x16, #0x6c] ;; misaligned with debug data
  [0x1006C] mov x11, x3
  [0x10070] movz x9, #0
  [0x10074] cmp x11, x9
  [0x10078] b.eq #0x1018c
  [0x1007C] movz x3, #0
  [0x10080] mov x10, x3
  [0x10084] b #0x1016c
  [0x10088] mov x9, x10
  [0x1008C] lsl x9, x9, #5
  [0x10090] mov x9, x9
  [0x10094] movz x8, #0x20
  [0x10098] add x8, x8, x11
  [0x1009C] add x9, x9, x8
  [0x100A0] add x16, x9, x15
  [0x100A4] ldr w3, [x16, #4] ;; misaligned with debug data
  [0x100A8] mov x3, x3
  [0x100AC] adrp x16, #0x10000
  [0x100B0] add x16, x16, #0
  [0x100B4] ldr w9, [x16]
  [0x100B8] add x16, x3, x15
  [0x100BC] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x100C0] adrp x16, #0x10000
  [0x100C4] add x16, x16, #0
  [0x100C8] ldr w6, [x16]
  [0x100CC] mov x9, x9
  [0x100D0] mov x7, x7
  [0x100D4] mov x6, x6
  [0x100D8] add x9, x9, x15
  [0x100DC] stp x3, x5, [sp, #-0x10]!
  [0x100E0] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100E4] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100E8] blr x9 ;; misaligned with debug data
  [0x100EC] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100F0] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100F4] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100F8] mov x0, x0
  [0x100FC] mov x0, x0
  [0x10100] mov x9, x14
  [0x10104] sub x9, x9, x15 ;; misaligned with debug data
  [0x10108] cmp x0, x9
  [0x1010C] b.eq #0x10138
  [0x10110] add x16, x3, x15
  [0x10114] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x10118] mov x0, x14
  [0x1011C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10120] cmp x9, x5
  [0x10124] b.ne #0x10134
  [0x10128] add x0, x14, #8
  [0x1012C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10130] mov x0, x0
  [0x10134] mov x0, x0
  [0x10138] mov x9, x14
  [0x1013C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10140] cmp x0, x9
  [0x10144] b.eq #0x10154
  [0x10148] mov x0, x3
  [0x1014C] b #0x101e8
  [0x10150] b #0x1015c
  [0x10154] mov x9, x14
  [0x10158] sub x9, x9, x15 ;; misaligned with debug data
  [0x1015C] mov x3, x10
  [0x10160] movz x9, #0x1
  [0x10164] add x3, x3, x9
  [0x10168] mov x10, x3
  [0x1016C] add x16, x11, x15
  [0x10170] ldrsh x9, [x16, #2] ;; misaligned with debug data
  [0x10174] cmp x10, x9
  [0x10178] b.lt #0x10088
  [0x1017C] mov x9, x14
  [0x10180] sub x9, x9, x15 ;; misaligned with debug data
  [0x10184] mov x9, x9
  [0x10188] b #0x10194
  [0x1018C] mov x9, x14
  [0x10190] sub x9, x9, x15 ;; misaligned with debug data
  [0x10194] mov x9, x9
  [0x10198] b #0x101a4
  [0x1019C] mov x9, x14
  [0x101A0] sub x9, x9, x15 ;; misaligned with debug data
  [0x101A4] mov x3, x12
  [0x101A8] movz x9, #0x1
  [0x101AC] add x3, x3, x9
  [0x101B0] mov x12, x3
  [0x101B4] adrp x16, #0x10000
  [0x101B8] add x16, x16, #0
  [0x101BC] ldr w9, [x16]
  [0x101C0] add x16, x9, x15
  [0x101C4] ldrsw x9, [x16] ;; misaligned with debug data
  [0x101C8] cmp x12, x9
  [0x101CC] b.lt #0x1001c
  [0x101D0] mov x9, x14
  [0x101D4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101D8] mov x0, x14
  [0x101DC] sub x0, x0, x15 ;; misaligned with debug data
  [0x101E0] mov x0, x0
  [0x101E4] mov x0, x0
  [0x101E8] add sp, sp, #0x10
  [0x101EC] ldp x29, x30, [sp], #0x10
  [0x101F0] ret


[process-entity-status!]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x2, x2
  [0x10014] add x16, x7, x15
  [0x10018] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x1001C] mov x9, x9
  [0x10020] mov x8, x14
  [0x10024] sub x8, x8, x15 ;; misaligned with debug data
  [0x10028] cmp x9, x8
  [0x1002C] b.eq #0x10068
  [0x10030] add x16, x7, x15
  [0x10034] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x10038] add x16, x9, x15
  [0x1003C] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10040] add x16, x9, x15
  [0x10044] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10048] mov x8, x14
  [0x1004C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10050] cmp x7, x9
  [0x10054] b.ne #0x10064
  [0x10058] add x8, x14, #8
  [0x1005C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10060] mov x8, x8
  [0x10064] mov x9, x8
  [0x10068] mov x8, x14
  [0x1006C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10070] cmp x9, x8
  [0x10074] b.eq #0x100f4
  [0x10078] add x16, x7, x15
  [0x1007C] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x10080] add x16, x9, x15
  [0x10084] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10088] mov x9, x9
  [0x1008C] mov x8, x14
  [0x10090] sub x8, x8, x15 ;; misaligned with debug data
  [0x10094] cmp x2, x8
  [0x10098] b.eq #0x100bc
  [0x1009C] add x16, x9, x15
  [0x100A0] ldrh w8, [x16, #0x38] ;; misaligned with debug data
  [0x100A4] mov x8, x8
  [0x100A8] orr x8, x8, x6
  [0x100AC] add x16, x9, x15
  [0x100B0] strh w8, [x16, #0x38] ;; misaligned with debug data
  [0x100B4] mov x8, x8
  [0x100B8] b #0x100e0
  [0x100BC] add x16, x9, x15
  [0x100C0] ldrh w8, [x16, #0x38] ;; misaligned with debug data
  [0x100C4] mov x6, x6
  [0x100C8] mvn x6, x6
  [0x100CC] mov x8, x8
  [0x100D0] and x8, x8, x6
  [0x100D4] add x16, x9, x15
  [0x100D8] strh w8, [x16, #0x38] ;; misaligned with debug data
  [0x100DC] mov x8, x8
  [0x100E0] add x16, x9, x15
  [0x100E4] ldrh w0, [x16, #0x38] ;; misaligned with debug data
  [0x100E8] mov x0, x0
  [0x100EC] mov x0, x0
  [0x100F0] b #0x100fc
  [0x100F4] movz x0, #0
  [0x100F8] mov x0, x0
  [0x100FC] mov x0, x0
  [0x10100] ldp x29, x30, [sp], #0x10
  [0x10104] ret


[entity-by-aid]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] movz x9, #0
  [0x10010] mov x9, x9
  [0x10014] b #0x10188
  [0x10018] movz x8, #0xa30
  [0x1001C] mul x8, x8, x9
  [0x10020] mov x8, x8
  [0x10024] movz x1, #0x60
  [0x10028] adrp x16, #0x10000
  [0x1002C] add x16, x16, #0
  [0x10030] ldr w2, [x16]
  [0x10034] add x1, x1, x2
  [0x10038] add x8, x8, x1
  [0x1003C] mov x8, x8
  [0x10040] add x16, x8, x15
  [0x10044] ldr w1, [x16, #0x10] ;; misaligned with debug data
  [0x10048] adrp x2, #0x10000
  [0x1004C] add x2, x2, #0
  [0x10050] cmp x1, x2
  [0x10054] b.ne #0x10170
  [0x10058] add x16, x8, x15
  [0x1005C] ldr w8, [x16, #0x118] ;; misaligned with debug data
  [0x10060] mov x8, x8
  [0x10064] movz x1, #0
  [0x10068] cmp x8, x1
  [0x1006C] b.eq #0x10160
  [0x10070] movz x1, #0
  [0x10074] add x16, x8, x15
  [0x10078] ldrsw x2, [x16] ;; misaligned with debug data
  [0x1007C] mov x2, x2
  [0x10080] movz x6, #0xffff
  [0x10084] movk x6, #0xffff, lsl #16
  [0x10088] movk x6, #0xffff, lsl #32
  [0x1008C] movk x6, #0xffff, lsl #48
  [0x10090] add x2, x2, x6
  [0x10094] mov x1, x1
  [0x10098] mov x2, x2
  [0x1009C] movz x6, #0
  [0x100A0] b #0x10148
  [0x100A4] mov x6, x1
  [0x100A8] mov x0, x2
  [0x100AC] sub x0, x0, x1
  [0x100B0] mov x0, x0
  [0x100B4] asr x0, x0, #1
  [0x100B8] add x6, x6, x0
  [0x100BC] mov x6, x6
  [0x100C0] mov x0, x6
  [0x100C4] lsl x0, x0, #6
  [0x100C8] mov x0, x0
  [0x100CC] movz x3, #0xc
  [0x100D0] add x3, x3, x8
  [0x100D4] add x0, x0, x3
  [0x100D8] mov x0, x0
  [0x100DC] add x16, x0, x15
  [0x100E0] ldr w3, [x16, #0x3c] ;; misaligned with debug data
  [0x100E4] mov x3, x3
  [0x100E8] cmp x3, x7
  [0x100EC] b.ne #0x10104
  [0x100F0] add x16, x0, x15
  [0x100F4] ldr w0, [x16, #8] ;; misaligned with debug data
  [0x100F8] mov x0, x0
  [0x100FC] b #0x101bc
  [0x10100] b #0x10148
  [0x10104] mov x3, x3
  [0x10108] cmp x3, x7
  [0x1010C] b.hs #0x10128
  [0x10110] mov x6, x6
  [0x10114] movz x1, #0x1
  [0x10118] add x6, x6, x1
  [0x1011C] mov x1, x6
  [0x10120] mov x6, x6
  [0x10124] b #0x10148
  [0x10128] mov x6, x6
  [0x1012C] movz x2, #0xffff
  [0x10130] movk x2, #0xffff, lsl #16
  [0x10134] movk x2, #0xffff, lsl #32
  [0x10138] movk x2, #0xffff, lsl #48
  [0x1013C] add x6, x6, x2
  [0x10140] mov x2, x6
  [0x10144] mov x6, x6
  [0x10148] cmp x2, x1
  [0x1014C] b.ge #0x100a4
  [0x10150] mov x8, x14
  [0x10154] sub x8, x8, x15 ;; misaligned with debug data
  [0x10158] mov x8, x8
  [0x1015C] b #0x10168
  [0x10160] mov x8, x14
  [0x10164] sub x8, x8, x15 ;; misaligned with debug data
  [0x10168] mov x8, x8
  [0x1016C] b #0x10178
  [0x10170] mov x8, x14
  [0x10174] sub x8, x8, x15 ;; misaligned with debug data
  [0x10178] mov x9, x9
  [0x1017C] movz x8, #0x1
  [0x10180] add x9, x9, x8
  [0x10184] mov x9, x9
  [0x10188] adrp x16, #0x10000
  [0x1018C] add x16, x16, #0
  [0x10190] ldr w8, [x16]
  [0x10194] add x16, x8, x15
  [0x10198] ldrsw x8, [x16] ;; misaligned with debug data
  [0x1019C] cmp x9, x8
  [0x101A0] b.lt #0x10018
  [0x101A4] mov x9, x14
  [0x101A8] sub x9, x9, x15 ;; misaligned with debug data
  [0x101AC] mov x0, x14
  [0x101B0] sub x0, x0, x15 ;; misaligned with debug data
  [0x101B4] mov x0, x0
  [0x101B8] mov x0, x0
  [0x101BC] ldp x29, x30, [sp], #0x10
  [0x101C0] ret


[entity-by-name]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x50
  [0x1000C] mov x7, x7
  [0x10010] str x7, [sp, #0x48]
  [0x10014] movz x3, #0
  [0x10018] mov x12, x3
  [0x1001C] b #0x10598
  [0x10020] movz x3, #0xa30
  [0x10024] mul x3, x3, x12
  [0x10028] mov x3, x3
  [0x1002C] movz x9, #0x60
  [0x10030] adrp x16, #0x10000
  [0x10034] add x16, x16, #0
  [0x10038] ldr w8, [x16]
  [0x1003C] add x9, x9, x8
  [0x10040] add x3, x3, x9
  [0x10044] mov x11, x3
  [0x10048] add x16, x11, x15
  [0x1004C] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x10050] adrp x8, #0x10000
  [0x10054] add x8, x8, #0
  [0x10058] cmp x9, x8
  [0x1005C] b.ne #0x10580
  [0x10060] add x16, x11, x15
  [0x10064] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10068] add x16, x9, x15
  [0x1006C] ldr w3, [x16, #0x6c] ;; misaligned with debug data
  [0x10070] mov x3, x3
  [0x10074] str x3, [sp]
  [0x10078] movz x8, #0
  [0x1007C] ldr x9, [sp]
  [0x10080] cmp x9, x8
  [0x10084] b.eq #0x10218
  [0x10088] movz x3, #0
  [0x1008C] mov x3, x3
  [0x10090] str x3, [sp, #0x20]
  [0x10094] b #0x101f0
  [0x10098] ldr x9, [sp, #0x20]
  [0x1009C] mov x8, x9
  [0x100A0] lsl x8, x8, #5
  [0x100A4] mov x8, x8
  [0x100A8] movz x1, #0x20
  [0x100AC] ldr x9, [sp]
  [0x100B0] add x1, x1, x9
  [0x100B4] add x8, x8, x1
  [0x100B8] add x16, x8, x15
  [0x100BC] ldr w3, [x16, #4] ;; misaligned with debug data
  [0x100C0] mov x3, x3
  [0x100C4] adrp x16, #0x10000
  [0x100C8] add x16, x16, #0
  [0x100CC] ldr w9, [x16]
  [0x100D0] str x9, [sp, #0x28]
  [0x100D4] adrp x16, #0x10000
  [0x100D8] add x16, x16, #0
  [0x100DC] ldr w9, [x16]
  [0x100E0] add x16, x9, x15
  [0x100E4] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x100E8] adrp x6, #0x10000
  [0x100EC] add x6, x6, #0
  [0x100F0] adrp x2, #0x10000
  [0x100F4] add x2, x2, #0
  [0x100F8] adrp x16, #0x1a000
  [0x100FC] ldr s23, [x16, #0xae4]
  [0x10100] mov x8, x14
  [0x10104] sub x8, x8, x15 ;; misaligned with debug data
  [0x10108] mov x8, x8
  [0x1010C] mov x9, x14
  [0x10110] sub x9, x9, x15 ;; misaligned with debug data
  [0x10114] mov x9, x9
  [0x10118] adrp x16, #0x10000
  [0x1011C] add x16, x16, #0
  [0x10120] ldr w10, [x16]
  [0x10124] mov x1, x1
  [0x10128] str x1, [sp, #0x40]
  [0x1012C] mov x7, x3
  [0x10130] mov x6, x6
  [0x10134] mov x2, x2
  [0x10138] fmov w1, s23
  [0x1013C] sxtw x1, w1
  [0x10140] mov x8, x8
  [0x10144] mov x9, x9
  [0x10148] mov x10, x10
  [0x1014C] ldr x5, [sp, #0x40]
  [0x10150] add x5, x5, x15
  [0x10154] stp x3, x5, [sp, #-0x10]!
  [0x10158] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1015C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10160] blr x5 ;; misaligned with debug data
  [0x10164] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10168] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1016C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10170] str x5, [sp, #0x40]
  [0x10174] mov x0, x0
  [0x10178] mov x0, x0
  [0x1017C] ldr x9, [sp, #0x28]
  [0x10180] mov x8, x9
  [0x10184] mov x7, x0
  [0x10188] ldr x9, [sp, #0x48]
  [0x1018C] mov x6, x9
  [0x10190] add x8, x8, x15
  [0x10194] stp x3, x5, [sp, #-0x10]!
  [0x10198] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1019C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x101A0] blr x8 ;; misaligned with debug data
  [0x101A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x101A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x101AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x101B0] mov x0, x0
  [0x101B4] mov x9, x14
  [0x101B8] sub x9, x9, x15 ;; misaligned with debug data
  [0x101BC] cmp x0, x9
  [0x101C0] b.eq #0x101d0
  [0x101C4] mov x0, x3
  [0x101C8] b #0x105cc
  [0x101CC] b #0x101d8
  [0x101D0] mov x9, x14
  [0x101D4] sub x9, x9, x15 ;; misaligned with debug data
  [0x101D8] ldr x3, [sp, #0x20]
  [0x101DC] mov x3, x3
  [0x101E0] movz x9, #0x1
  [0x101E4] add x3, x3, x9
  [0x101E8] mov x3, x3
  [0x101EC] str x3, [sp, #0x20]
  [0x101F0] ldr x9, [sp]
  [0x101F4] add x16, x9, x15
  [0x101F8] ldrsh x8, [x16, #2] ;; misaligned with debug data
  [0x101FC] ldr x9, [sp, #0x20]
  [0x10200] cmp x9, x8
  [0x10204] b.lt #0x10098
  [0x10208] mov x9, x14
  [0x1020C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10210] mov x9, x9
  [0x10214] b #0x10220
  [0x10218] mov x9, x14
  [0x1021C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10220] add x16, x11, x15
  [0x10224] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x10228] add x16, x9, x15
  [0x1022C] ldr w3, [x16, #0x98] ;; misaligned with debug data
  [0x10230] mov x3, x3
  [0x10234] str x3, [sp, #8]
  [0x10238] movz x8, #0
  [0x1023C] ldr x9, [sp, #8]
  [0x10240] cmp x9, x8
  [0x10244] b.eq #0x103cc
  [0x10248] movz x3, #0
  [0x1024C] mov x3, x3
  [0x10250] str x3, [sp, #0x10]
  [0x10254] b #0x103a4
  [0x10258] ldr x9, [sp, #0x10]
  [0x1025C] mov x8, x9
  [0x10260] lsl x8, x8, #5
  [0x10264] mov x8, x8
  [0x10268] movz x1, #0x20
  [0x1026C] ldr x9, [sp, #8]
  [0x10270] add x1, x1, x9
  [0x10274] add x8, x8, x1
  [0x10278] add x16, x8, x15
  [0x1027C] ldr w3, [x16, #4] ;; misaligned with debug data
  [0x10280] mov x3, x3
  [0x10284] adrp x16, #0x10000
  [0x10288] add x16, x16, #0
  [0x1028C] ldr w9, [x16]
  [0x10290] str x9, [sp, #0x30]
  [0x10294] adrp x16, #0x10000
  [0x10298] add x16, x16, #0
  [0x1029C] ldr w9, [x16]
  [0x102A0] add x16, x9, x15
  [0x102A4] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x102A8] adrp x6, #0x10000
  [0x102AC] add x6, x6, #0
  [0x102B0] adrp x2, #0x10000
  [0x102B4] add x2, x2, #0
  [0x102B8] adrp x16, #0x1a000
  [0x102BC] ldr s23, [x16, #0xae8]
  [0x102C0] mov x8, x14
  [0x102C4] sub x8, x8, x15 ;; misaligned with debug data
  [0x102C8] mov x8, x8
  [0x102CC] mov x9, x14
  [0x102D0] sub x9, x9, x15 ;; misaligned with debug data
  [0x102D4] mov x9, x9
  [0x102D8] adrp x16, #0x10000
  [0x102DC] add x16, x16, #0
  [0x102E0] ldr w10, [x16]
  [0x102E4] mov x5, x1
  [0x102E8] mov x7, x3
  [0x102EC] mov x6, x6
  [0x102F0] mov x2, x2
  [0x102F4] fmov w1, s23
  [0x102F8] sxtw x1, w1
  [0x102FC] mov x8, x8
  [0x10300] mov x9, x9
  [0x10304] mov x10, x10
  [0x10308] add x5, x5, x15
  [0x1030C] stp x3, x5, [sp, #-0x10]!
  [0x10310] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10314] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10318] blr x5 ;; misaligned with debug data
  [0x1031C] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10320] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10324] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10328] mov x0, x0
  [0x1032C] mov x0, x0
  [0x10330] ldr x9, [sp, #0x30]
  [0x10334] mov x8, x9
  [0x10338] mov x7, x0
  [0x1033C] ldr x9, [sp, #0x48]
  [0x10340] mov x6, x9
  [0x10344] add x8, x8, x15
  [0x10348] stp x3, x5, [sp, #-0x10]!
  [0x1034C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10350] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10354] blr x8 ;; misaligned with debug data
  [0x10358] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1035C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10360] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10364] mov x0, x0
  [0x10368] mov x9, x14
  [0x1036C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10370] cmp x0, x9
  [0x10374] b.eq #0x10384
  [0x10378] mov x0, x3
  [0x1037C] b #0x105cc
  [0x10380] b #0x1038c
  [0x10384] mov x9, x14
  [0x10388] sub x9, x9, x15 ;; misaligned with debug data
  [0x1038C] ldr x3, [sp, #0x10]
  [0x10390] mov x3, x3
  [0x10394] movz x9, #0x1
  [0x10398] add x3, x3, x9
  [0x1039C] mov x3, x3
  [0x103A0] str x3, [sp, #0x10]
  [0x103A4] ldr x9, [sp, #8]
  [0x103A8] add x16, x9, x15
  [0x103AC] ldrsh x8, [x16, #2] ;; misaligned with debug data
  [0x103B0] ldr x9, [sp, #0x10]
  [0x103B4] cmp x9, x8
  [0x103B8] b.lt #0x10258
  [0x103BC] mov x9, x14
  [0x103C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x103C4] mov x9, x9
  [0x103C8] b #0x103d4
  [0x103CC] mov x9, x14
  [0x103D0] sub x9, x9, x15 ;; misaligned with debug data
  [0x103D4] add x16, x11, x15
  [0x103D8] ldr w9, [x16, #0x2c] ;; misaligned with debug data
  [0x103DC] add x16, x9, x15
  [0x103E0] ldr w3, [x16, #0x70] ;; misaligned with debug data
  [0x103E4] mov x11, x3
  [0x103E8] movz x9, #0
  [0x103EC] cmp x11, x9
  [0x103F0] b.eq #0x10570
  [0x103F4] movz x3, #0
  [0x103F8] mov x3, x3
  [0x103FC] str x3, [sp, #0x18]
  [0x10400] b #0x1054c
  [0x10404] movz x8, #0xc
  [0x10408] ldr x9, [sp, #0x18]
  [0x1040C] mov x1, x9
  [0x10410] lsl x1, x1, #2
  [0x10414] add x1, x1, x8
  [0x10418] mov x1, x1
  [0x1041C] add x1, x1, x11
  [0x10420] add x16, x1, x15
  [0x10424] ldr w3, [x16] ;; misaligned with debug data
  [0x10428] mov x3, x3
  [0x1042C] adrp x16, #0x10000
  [0x10430] add x16, x16, #0
  [0x10434] ldr w9, [x16]
  [0x10438] str x9, [sp, #0x38]
  [0x1043C] adrp x16, #0x10000
  [0x10440] add x16, x16, #0
  [0x10444] ldr w9, [x16]
  [0x10448] add x16, x9, x15
  [0x1044C] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x10450] adrp x6, #0x10000
  [0x10454] add x6, x6, #0
  [0x10458] adrp x2, #0x10000
  [0x1045C] add x2, x2, #0
  [0x10460] adrp x16, #0x1a000
  [0x10464] ldr s23, [x16, #0xaec]
  [0x10468] mov x8, x14
  [0x1046C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10470] mov x8, x8
  [0x10474] mov x9, x14
  [0x10478] sub x9, x9, x15 ;; misaligned with debug data
  [0x1047C] mov x9, x9
  [0x10480] adrp x16, #0x10000
  [0x10484] add x16, x16, #0
  [0x10488] ldr w10, [x16]
  [0x1048C] mov x5, x1
  [0x10490] mov x7, x3
  [0x10494] mov x6, x6
  [0x10498] mov x2, x2
  [0x1049C] fmov w1, s23
  [0x104A0] sxtw x1, w1
  [0x104A4] mov x8, x8
  [0x104A8] mov x9, x9
  [0x104AC] mov x10, x10
  [0x104B0] add x5, x5, x15
  [0x104B4] stp x3, x5, [sp, #-0x10]!
  [0x104B8] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104BC] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104C0] blr x5 ;; misaligned with debug data
  [0x104C4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104C8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104CC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104D0] mov x0, x0
  [0x104D4] mov x0, x0
  [0x104D8] ldr x9, [sp, #0x38]
  [0x104DC] mov x8, x9
  [0x104E0] mov x7, x0
  [0x104E4] ldr x9, [sp, #0x48]
  [0x104E8] mov x6, x9
  [0x104EC] add x8, x8, x15
  [0x104F0] stp x3, x5, [sp, #-0x10]!
  [0x104F4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104F8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104FC] blr x8 ;; misaligned with debug data
  [0x10500] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10504] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10508] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1050C] mov x0, x0
  [0x10510] mov x9, x14
  [0x10514] sub x9, x9, x15 ;; misaligned with debug data
  [0x10518] cmp x0, x9
  [0x1051C] b.eq #0x1052c
  [0x10520] mov x0, x3
  [0x10524] b #0x105cc
  [0x10528] b #0x10534
  [0x1052C] mov x9, x14
  [0x10530] sub x9, x9, x15 ;; misaligned with debug data
  [0x10534] ldr x3, [sp, #0x18]
  [0x10538] mov x3, x3
  [0x1053C] movz x9, #0x1
  [0x10540] add x3, x3, x9
  [0x10544] mov x3, x3
  [0x10548] str x3, [sp, #0x18]
  [0x1054C] add x16, x11, x15
  [0x10550] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10554] ldr x9, [sp, #0x18]
  [0x10558] cmp x9, x8
  [0x1055C] b.lt #0x10404
  [0x10560] mov x9, x14
  [0x10564] sub x9, x9, x15 ;; misaligned with debug data
  [0x10568] mov x9, x9
  [0x1056C] b #0x10578
  [0x10570] mov x9, x14
  [0x10574] sub x9, x9, x15 ;; misaligned with debug data
  [0x10578] mov x9, x9
  [0x1057C] b #0x10588
  [0x10580] mov x9, x14
  [0x10584] sub x9, x9, x15 ;; misaligned with debug data
  [0x10588] mov x3, x12
  [0x1058C] movz x9, #0x1
  [0x10590] add x3, x3, x9
  [0x10594] mov x12, x3
  [0x10598] adrp x16, #0x10000
  [0x1059C] add x16, x16, #0
  [0x105A0] ldr w9, [x16]
  [0x105A4] add x16, x9, x15
  [0x105A8] ldrsw x9, [x16] ;; misaligned with debug data
  [0x105AC] cmp x12, x9
  [0x105B0] b.lt #0x10020
  [0x105B4] mov x9, x14
  [0x105B8] sub x9, x9, x15 ;; misaligned with debug data
  [0x105BC] mov x0, x14
  [0x105C0] sub x0, x0, x15 ;; misaligned with debug data
  [0x105C4] mov x0, x0
  [0x105C8] mov x0, x0
  [0x105CC] add sp, sp, #0x50
  [0x105D0] ldp x29, x30, [sp], #0x10
  [0x105D4] ret


[(method get-level entity)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] movz x9, #0
  [0x10010] mov x9, x9
  [0x10014] b #0x1010c
  [0x10018] movz x0, #0xa30
  [0x1001C] mul x0, x0, x9
  [0x10020] mov x0, x0
  [0x10024] movz x8, #0x60
  [0x10028] adrp x16, #0x10000
  [0x1002C] add x16, x16, #0
  [0x10030] ldr w1, [x16]
  [0x10034] add x8, x8, x1
  [0x10038] add x0, x0, x8
  [0x1003C] mov x0, x0
  [0x10040] add x16, x0, x15
  [0x10044] ldr w8, [x16, #0x10] ;; misaligned with debug data
  [0x10048] adrp x1, #0x10000
  [0x1004C] add x1, x1, #0
  [0x10050] cmp x8, x1
  [0x10054] b.ne #0x100f4
  [0x10058] mov x8, x7
  [0x1005C] add x16, x0, x15
  [0x10060] ldr w1, [x16, #0x1c] ;; misaligned with debug data
  [0x10064] mov x1, x1
  [0x10068] mov x2, x14
  [0x1006C] sub x2, x2, x15 ;; misaligned with debug data
  [0x10070] cmp x8, x1
  [0x10074] b.lt #0x10084
  [0x10078] add x2, x14, #8
  [0x1007C] sub x2, x2, x15 ;; misaligned with debug data
  [0x10080] mov x2, x2
  [0x10084] mov x8, x2
  [0x10088] mov x1, x14
  [0x1008C] sub x1, x1, x15 ;; misaligned with debug data
  [0x10090] cmp x8, x1
  [0x10094] b.eq #0x100c8
  [0x10098] mov x8, x7
  [0x1009C] add x16, x0, x15
  [0x100A0] ldr w1, [x16, #0x28] ;; misaligned with debug data
  [0x100A4] mov x1, x1
  [0x100A8] mov x2, x14
  [0x100AC] sub x2, x2, x15 ;; misaligned with debug data
  [0x100B0] cmp x8, x1
  [0x100B4] b.ge #0x100c4
  [0x100B8] add x2, x14, #8
  [0x100BC] sub x2, x2, x15 ;; misaligned with debug data
  [0x100C0] mov x2, x2
  [0x100C4] mov x8, x2
  [0x100C8] mov x1, x14
  [0x100CC] sub x1, x1, x15 ;; misaligned with debug data
  [0x100D0] cmp x8, x1
  [0x100D4] b.eq #0x100e4
  [0x100D8] mov x0, x0
  [0x100DC] b #0x10148
  [0x100E0] b #0x100ec
  [0x100E4] mov x8, x14
  [0x100E8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100EC] mov x8, x8
  [0x100F0] b #0x100fc
  [0x100F4] mov x8, x14
  [0x100F8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100FC] mov x9, x9
  [0x10100] movz x8, #0x1
  [0x10104] add x9, x9, x8
  [0x10108] mov x9, x9
  [0x1010C] adrp x16, #0x10000
  [0x10110] add x16, x16, #0
  [0x10114] ldr w8, [x16]
  [0x10118] add x16, x8, x15
  [0x1011C] ldrsw x8, [x16] ;; misaligned with debug data
  [0x10120] cmp x9, x8
  [0x10124] b.lt #0x10018
  [0x10128] mov x9, x14
  [0x1012C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10130] movz x0, #0x14c0
  [0x10134] adrp x16, #0x10000
  [0x10138] add x16, x16, #0
  [0x1013C] ldr w9, [x16]
  [0x10140] add x0, x0, x9
  [0x10144] mov x0, x0
  [0x10148] ldp x29, x30, [sp], #0x10
  [0x1014C] ret


[(method kill! entity)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] add x7, x14, #8
  [0x10020] sub x7, x7, x15 ;; misaligned with debug data
  [0x10024] adrp x6, #0x1a000
  [0x10028] add x6, x6, #0xaa4
  [0x1002C] sub x6, x6, x15
  [0x10030] mov x9, x9
  [0x10034] mov x7, x7
  [0x10038] mov x6, x6
  [0x1003C] mov x2, x3
  [0x10040] add x9, x9, x15
  [0x10044] stp x3, x5, [sp, #-0x10]!
  [0x10048] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1004C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10050] blr x9 ;; misaligned with debug data
  [0x10054] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10058] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1005C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10060] mov x0, x0
  [0x10064] mov x0, x3
  [0x10068] add sp, sp, #0x10
  [0x1006C] ldp x29, x30, [sp], #0x10
  [0x10070] ret


[(method birth! entity)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] add x7, x14, #8
  [0x10020] sub x7, x7, x15 ;; misaligned with debug data
  [0x10024] adrp x6, #0x1a000
  [0x10028] add x6, x6, #0xa84
  [0x1002C] sub x6, x6, x15
  [0x10030] mov x9, x9
  [0x10034] mov x7, x7
  [0x10038] mov x6, x6
  [0x1003C] mov x2, x3
  [0x10040] add x9, x9, x15
  [0x10044] stp x3, x5, [sp, #-0x10]!
  [0x10048] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1004C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10050] blr x9 ;; misaligned with debug data
  [0x10054] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10058] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1005C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10060] mov x0, x0
  [0x10064] mov x0, x3
  [0x10068] add sp, sp, #0x10
  [0x1006C] ldp x29, x30, [sp], #0x10
  [0x10070] ret


[(method print entity-perm)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w0, [x16]
  [0x1001C] add x7, x14, #8
  [0x10020] sub x7, x7, x15 ;; misaligned with debug data
  [0x10024] adrp x6, #0x1a000
  [0x10028] add x6, x6, #0xa34
  [0x1002C] sub x6, x6, x15
  [0x10030] add x16, x3, x15
  [0x10034] ldr w2, [x16, #0xc] ;; misaligned with debug data
  [0x10038] add x16, x3, x15
  [0x1003C] ldrb w1, [x16, #0xb] ;; misaligned with debug data
  [0x10040] add x16, x3, x15
  [0x10044] ldrh w8, [x16, #8] ;; misaligned with debug data
  [0x10048] add x16, x3, x15
  [0x1004C] ldr x9, [x16] ;; misaligned with debug data
  [0x10050] mov x5, x0
  [0x10054] mov x7, x7
  [0x10058] mov x6, x6
  [0x1005C] mov x2, x2
  [0x10060] mov x1, x1
  [0x10064] mov x8, x8
  [0x10068] mov x9, x9
  [0x1006C] mov x10, x3
  [0x10070] add x5, x5, x15
  [0x10074] stp x3, x5, [sp, #-0x10]!
  [0x10078] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1007C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10080] blr x5 ;; misaligned with debug data
  [0x10084] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10088] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1008C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10090] mov x0, x0
  [0x10094] mov x0, x3
  [0x10098] add sp, sp, #0x10
  [0x1009C] ldp x29, x30, [sp], #0x10
  [0x100A0] ret


[(method add-to-level! entity)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] mov x7, x7
  [0x1000C] mov x6, x6
  [0x10010] mov x2, x2
  [0x10014] mov x1, x1
  [0x10018] add x16, x2, x15
  [0x1001C] ldr w9, [x16, #0x118] ;; misaligned with debug data
  [0x10020] add x16, x9, x15
  [0x10024] ldrsw x9, [x16] ;; misaligned with debug data
  [0x10028] mov x9, x9
  [0x1002C] lsl x9, x9, #6
  [0x10030] mov x9, x9
  [0x10034] movz x8, #0xc
  [0x10038] add x16, x2, x15
  [0x1003C] ldr w0, [x16, #0x118] ;; misaligned with debug data
  [0x10040] add x8, x8, x0
  [0x10044] add x9, x9, x8
  [0x10048] mov x9, x9
  [0x1004C] add x16, x2, x15
  [0x10050] ldr w8, [x16, #0x118] ;; misaligned with debug data
  [0x10054] add x16, x8, x15
  [0x10058] ldrsw x8, [x16] ;; misaligned with debug data
  [0x1005C] mov x8, x8
  [0x10060] movz x0, #0x1
  [0x10064] add x8, x8, x0
  [0x10068] add x16, x2, x15
  [0x1006C] ldr w0, [x16, #0x118] ;; misaligned with debug data
  [0x10070] add x16, x0, x15
  [0x10074] str w8, [x16] ;; misaligned with debug data
  [0x10078] mov x8, x14
  [0x1007C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10080] add x16, x9, x15
  [0x10084] str w8, [x16, #0xc] ;; misaligned with debug data
  [0x10088] add x16, x9, x15
  [0x1008C] str w7, [x16, #8] ;; misaligned with debug data
  [0x10090] add x16, x7, x15
  [0x10094] str w9, [x16, #0x14] ;; misaligned with debug data
  [0x10098] add x16, x6, x15
  [0x1009C] ldr w8, [x16, #0xc] ;; misaligned with debug data
  [0x100A0] mov x0, x14
  [0x100A4] sub x0, x0, x15 ;; misaligned with debug data
  [0x100A8] cmp x8, x0
  [0x100AC] b.eq #0x100f0
  [0x100B0] add x16, x6, x15
  [0x100B4] ldr w8, [x16, #0xc] ;; misaligned with debug data
  [0x100B8] mov x8, x8
  [0x100BC] add x16, x8, x15
  [0x100C0] ldr w0, [x16, #4] ;; misaligned with debug data
  [0x100C4] mov x0, x0
  [0x100C8] add x16, x8, x15
  [0x100CC] str w9, [x16, #4] ;; misaligned with debug data
  [0x100D0] add x16, x9, x15
  [0x100D4] str w8, [x16] ;; misaligned with debug data
  [0x100D8] add x16, x9, x15
  [0x100DC] str w0, [x16, #4] ;; misaligned with debug data
  [0x100E0] add x16, x0, x15
  [0x100E4] str w9, [x16] ;; misaligned with debug data
  [0x100E8] mov x8, x9
  [0x100EC] b #0x10104
  [0x100F0] add x16, x9, x15
  [0x100F4] str w9, [x16] ;; misaligned with debug data
  [0x100F8] add x16, x9, x15
  [0x100FC] str w9, [x16, #4] ;; misaligned with debug data
  [0x10100] mov x8, x9
  [0x10104] add x16, x6, x15
  [0x10108] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x1010C] add x16, x7, x15
  [0x10110] ldur q23, [x16, #0x1c] ;; misaligned with debug data
  [0x10114] mov v23.16b, v23.16b
  [0x10118] add x16, x9, x15
  [0x1011C] str q23, [x16, #0x20] ;; misaligned with debug data
  [0x10120] add x16, x7, x15
  [0x10124] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10128] add x16, x9, x15
  [0x1012C] str w1, [x16, #0x3c] ;; misaligned with debug data
  [0x10130] add x16, x7, x15
  [0x10134] ldr w9, [x16, #0x14] ;; misaligned with debug data
  [0x10138] add x16, x9, x15
  [0x1013C] str w2, [x16, #0x10] ;; misaligned with debug data
  [0x10140] add x16, x7, x15
  [0x10144] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10148] adrp x16, #0x10000
  [0x1014C] add x16, x16, #0
  [0x10150] ldr w8, [x16]
  [0x10154] cmp x9, x8
  [0x10158] b.ne #0x101a4
  [0x1015C] mov x9, x7
  [0x10160] add x16, x9, x15
  [0x10164] ldrb w9, [x16, #0x38] ;; misaligned with debug data
  [0x10168] mov x8, x7
  [0x1016C] add x16, x8, x15
  [0x10170] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10174] add x16, x8, x15
  [0x10178] strb w9, [x16, #0x3b] ;; misaligned with debug data
  [0x1017C] mov x9, x7
  [0x10180] add x16, x9, x15
  [0x10184] ldrsh x9, [x16, #0x3a] ;; misaligned with debug data
  [0x10188] mov x7, x7
  [0x1018C] add x16, x7, x15
  [0x10190] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10194] add x16, x8, x15
  [0x10198] str w9, [x16, #0x14] ;; misaligned with debug data
  [0x1019C] mov x9, x9
  [0x101A0] b #0x101d4
  [0x101A4] movz x9, #0
  [0x101A8] add x16, x7, x15
  [0x101AC] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x101B0] add x16, x8, x15
  [0x101B4] strb w9, [x16, #0x3b] ;; misaligned with debug data
  [0x101B8] movz x9, #0
  [0x101BC] add x16, x7, x15
  [0x101C0] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x101C4] add x16, x8, x15
  [0x101C8] str w9, [x16, #0x14] ;; misaligned with debug data
  [0x101CC] movz x9, #0
  [0x101D0] mov x9, x9
  [0x101D4] ldp x29, x30, [sp], #0x10
  [0x101D8] ret


[(method print entity-links)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x3, x7
  [0x10010] adrp x16, #0x10000
  [0x10014] add x16, x16, #0
  [0x10018] ldr w9, [x16]
  [0x1001C] add x7, x14, #8
  [0x10020] sub x7, x7, x15 ;; misaligned with debug data
  [0x10024] adrp x6, #0x1a000
  [0x10028] add x6, x6, #0xa04
  [0x1002C] sub x6, x6, x15
  [0x10030] add x16, x3, x15
  [0x10034] ldr w2, [x16, #0xc] ;; misaligned with debug data
  [0x10038] mov x9, x9
  [0x1003C] mov x7, x7
  [0x10040] mov x6, x6
  [0x10044] mov x2, x2
  [0x10048] mov x1, x3
  [0x1004C] add x9, x9, x15
  [0x10050] stp x3, x5, [sp, #-0x10]!
  [0x10054] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10058] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1005C] blr x9 ;; misaligned with debug data
  [0x10060] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10064] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10068] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1006C] mov x0, x0
  [0x10070] mov x0, x3
  [0x10074] add sp, sp, #0x10
  [0x10078] ldp x29, x30, [sp], #0x10
  [0x1007C] ret


[(method mem-usage drawable-inline-array-actor)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x12, x6
  [0x10014] mov x11, x2
  [0x10018] movz x9, #0x1
  [0x1001C] add x16, x12, x15
  [0x10020] ldrsw x8, [x16, #4] ;; misaligned with debug data
  [0x10024] mov x9, x9
  [0x10028] mov x8, x8
  [0x1002C] cmp x9, x8
  [0x10030] b.le #0x1003c
  [0x10034] mov x9, x9
  [0x10038] b #0x10040
  [0x1003C] mov x9, x8
  [0x10040] add x16, x12, x15
  [0x10044] str w9, [x16, #4] ;; misaligned with debug data
  [0x10048] movz x9, #0
  [0x1004C] movk x9, #0x2, lsl #16
  [0x10050] mov x9, x9
  [0x10054] adrp x8, #0x10000
  [0x10058] add x8, x8, #0
  [0x1005C] mov x8, x8
  [0x10060] add x9, x9, x8
  [0x10064] mov x9, x9
  [0x10068] add x16, x9, x15
  [0x1006C] ldr w9, [x16] ;; misaligned with debug data
  [0x10070] add x16, x12, x15
  [0x10074] str w9, [x16, #0xc] ;; misaligned with debug data
  [0x10078] add x16, x12, x15
  [0x1007C] ldrsw x9, [x16, #0x10] ;; misaligned with debug data
  [0x10080] mov x9, x9
  [0x10084] movz x8, #0x1
  [0x10088] add x9, x9, x8
  [0x1008C] add x16, x12, x15
  [0x10090] str w9, [x16, #0x10] ;; misaligned with debug data
  [0x10094] movz x9, #0x20
  [0x10098] mov x9, x9
  [0x1009C] add x16, x12, x15
  [0x100A0] ldrsw x8, [x16, #0x14] ;; misaligned with debug data
  [0x100A4] mov x8, x8
  [0x100A8] add x8, x8, x9
  [0x100AC] add x16, x12, x15
  [0x100B0] str w8, [x16, #0x14] ;; misaligned with debug data
  [0x100B4] add x16, x12, x15
  [0x100B8] ldrsw x8, [x16, #0x18] ;; misaligned with debug data
  [0x100BC] mov x8, x8
  [0x100C0] movz x1, #0xfff0
  [0x100C4] movk x1, #0xffff, lsl #16
  [0x100C8] movk x1, #0xffff, lsl #32
  [0x100CC] movk x1, #0xffff, lsl #48
  [0x100D0] mov x9, x9
  [0x100D4] movz x2, #0xf
  [0x100D8] add x9, x9, x2
  [0x100DC] mov x1, x1
  [0x100E0] and x1, x1, x9
  [0x100E4] add x8, x8, x1
  [0x100E8] add x16, x12, x15
  [0x100EC] str w8, [x16, #0x18] ;; misaligned with debug data
  [0x100F0] movz x3, #0
  [0x100F4] mov x3, x3
  [0x100F8] b #0x10168
  [0x100FC] mov x7, x3
  [0x10100] lsl x7, x7, #5
  [0x10104] mov x7, x7
  [0x10108] movz x9, #0x20
  [0x1010C] add x9, x9, x5
  [0x10110] add x7, x7, x9
  [0x10114] add x16, x7, x15
  [0x10118] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x1011C] add x16, x9, x15
  [0x10120] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x10124] mov x9, x9
  [0x10128] mov x7, x7
  [0x1012C] mov x6, x12
  [0x10130] mov x2, x11
  [0x10134] add x9, x9, x15
  [0x10138] stp x3, x5, [sp, #-0x10]!
  [0x1013C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10140] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10144] blr x9 ;; misaligned with debug data
  [0x10148] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1014C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10150] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10154] mov x0, x0
  [0x10158] mov x3, x3
  [0x1015C] movz x9, #0x1
  [0x10160] add x3, x3, x9
  [0x10164] mov x3, x3
  [0x10168] add x16, x5, x15
  [0x1016C] ldrsh x9, [x16, #2] ;; misaligned with debug data
  [0x10170] cmp x3, x9
  [0x10174] b.lt #0x100fc
  [0x10178] mov x9, x14
  [0x1017C] sub x9, x9, x15 ;; misaligned with debug data
  [0x10180] movz x0, #0
  [0x10184] mov x0, x0
  [0x10188] mov x0, x0
  [0x1018C] add sp, sp, #0x10
  [0x10190] ldp x29, x30, [sp], #0x10
  [0x10194] ret


[(method debug-print entity-actor)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x20
  [0x1000C] mov x7, x7
  [0x10010] str x7, [sp, #0x18]
  [0x10014] mov x12, x6
  [0x10018] mov x11, x2
  [0x1001C] ldr x9, [sp, #0x18]
  [0x10020] add x16, x9, x15
  [0x10024] ldr w3, [x16, #0x34] ;; misaligned with debug data
  [0x10028] mov x3, x3
  [0x1002C] mov x9, x14
  [0x10030] sub x9, x9, x15 ;; misaligned with debug data
  [0x10034] mov x8, x14
  [0x10038] sub x8, x8, x15 ;; misaligned with debug data
  [0x1003C] cmp x11, x9
  [0x10040] b.ne #0x10050
  [0x10044] add x8, x14, #8
  [0x10048] sub x8, x8, x15 ;; misaligned with debug data
  [0x1004C] mov x8, x8
  [0x10050] mov x9, x8
  [0x10054] mov x8, x14
  [0x10058] sub x8, x8, x15 ;; misaligned with debug data
  [0x1005C] cmp x9, x8
  [0x10060] b.ne #0x10138
  [0x10064] mov x9, x3
  [0x10068] mov x8, x14
  [0x1006C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10070] cmp x9, x8
  [0x10074] b.eq #0x10134
  [0x10078] adrp x16, #0x10000
  [0x1007C] add x16, x16, #0
  [0x10080] ldr w9, [x16]
  [0x10084] adrp x16, #0x10000
  [0x10088] add x16, x16, #0
  [0x1008C] ldr w6, [x16]
  [0x10090] mov x2, x14
  [0x10094] sub x2, x2, x15 ;; misaligned with debug data
  [0x10098] mov x1, x14
  [0x1009C] sub x1, x1, x15 ;; misaligned with debug data
  [0x100A0] movz x8, #0
  [0x100A4] mov x9, x9
  [0x100A8] mov x7, x3
  [0x100AC] mov x6, x6
  [0x100B0] mov x2, x2
  [0x100B4] mov x1, x1
  [0x100B8] mov x8, x8
  [0x100BC] add x9, x9, x15
  [0x100C0] stp x3, x5, [sp, #-0x10]!
  [0x100C4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100C8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100CC] blr x9 ;; misaligned with debug data
  [0x100D0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100D4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100D8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] mov x0, x0
  [0x100E0] mov x9, x0
  [0x100E4] mov x8, x14
  [0x100E8] sub x8, x8, x15 ;; misaligned with debug data
  [0x100EC] cmp x9, x8
  [0x100F0] b.eq #0x10134
  [0x100F4] adrp x16, #0x10000
  [0x100F8] add x16, x16, #0
  [0x100FC] ldr w9, [x16]
  [0x10100] mov x9, x9
  [0x10104] mov x7, x3
  [0x10108] mov x6, x11
  [0x1010C] add x9, x9, x15
  [0x10110] stp x3, x5, [sp, #-0x10]!
  [0x10114] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10118] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1011C] blr x9 ;; misaligned with debug data
  [0x10120] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10124] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10128] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1012C] mov x0, x0
  [0x10130] mov x9, x0
  [0x10134] mov x9, x9
  [0x10138] mov x8, x14
  [0x1013C] sub x8, x8, x15 ;; misaligned with debug data
  [0x10140] cmp x9, x8
  [0x10144] b.eq #0x10968
  [0x10148] adrp x16, #0x10000
  [0x1014C] add x16, x16, #0
  [0x10150] ldr w3, [x16]
  [0x10154] add x11, x14, #8
  [0x10158] sub x11, x11, x15 ;; misaligned with debug data
  [0x1015C] adrp x9, #0x18000
  [0x10160] add x9, x9, #0xc44
  [0x10164] sub x9, x9, x15
  [0x10168] str x9, [sp]
  [0x1016C] ldr x9, [sp, #0x18]
  [0x10170] add x16, x9, x15
  [0x10174] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10178] add x16, x8, x15
  [0x1017C] ldrsw x9, [x16, #0x14] ;; misaligned with debug data
  [0x10180] str x9, [sp, #8]
  [0x10184] adrp x16, #0x10000
  [0x10188] add x16, x16, #0
  [0x1018C] ldr w9, [x16]
  [0x10190] add x16, x9, x15
  [0x10194] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x10198] adrp x6, #0x10000
  [0x1019C] add x6, x6, #0
  [0x101A0] adrp x2, #0x10000
  [0x101A4] add x2, x2, #0
  [0x101A8] adrp x16, #0x18000
  [0x101AC] ldr s23, [x16, #0xc5c]
  [0x101B0] mov x8, x14
  [0x101B4] sub x8, x8, x15 ;; misaligned with debug data
  [0x101B8] mov x8, x8
  [0x101BC] mov x9, x14
  [0x101C0] sub x9, x9, x15 ;; misaligned with debug data
  [0x101C4] mov x9, x9
  [0x101C8] adrp x16, #0x10000
  [0x101CC] add x16, x16, #0
  [0x101D0] ldr w10, [x16]
  [0x101D4] mov x1, x1
  [0x101D8] str x1, [sp, #0x10]
  [0x101DC] ldr x1, [sp, #0x18]
  [0x101E0] mov x7, x1
  [0x101E4] mov x6, x6
  [0x101E8] mov x2, x2
  [0x101EC] fmov w1, s23
  [0x101F0] sxtw x1, w1
  [0x101F4] mov x8, x8
  [0x101F8] mov x9, x9
  [0x101FC] mov x10, x10
  [0x10200] ldr x5, [sp, #0x10]
  [0x10204] add x5, x5, x15
  [0x10208] stp x3, x5, [sp, #-0x10]!
  [0x1020C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10210] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10214] blr x5 ;; misaligned with debug data
  [0x10218] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1021C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10220] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10224] str x5, [sp, #0x10]
  [0x10228] mov x0, x0
  [0x1022C] mov x0, x0
  [0x10230] mov x3, x3
  [0x10234] mov x7, x11
  [0x10238] ldr x6, [sp]
  [0x1023C] mov x6, x6
  [0x10240] ldr x2, [sp, #8]
  [0x10244] mov x2, x2
  [0x10248] ldr x9, [sp, #0x18]
  [0x1024C] mov x1, x9
  [0x10250] mov x8, x0
  [0x10254] add x3, x3, x15
  [0x10258] stp x3, x5, [sp, #-0x10]!
  [0x1025C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10260] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10264] blr x3 ;; misaligned with debug data
  [0x10268] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1026C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10270] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10274] mov x0, x0
  [0x10278] ldr x9, [sp, #0x18]
  [0x1027C] add x16, x9, x15
  [0x10280] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10284] add x16, x8, x15
  [0x10288] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x1028C] add x16, x9, x15
  [0x10290] ldr w8, [x16, #8] ;; misaligned with debug data
  [0x10294] mov x8, x8
  [0x10298] mov x9, x14
  [0x1029C] sub x9, x9, x15 ;; misaligned with debug data
  [0x102A0] cmp x8, x9
  [0x102A4] b.eq #0x102b0
  [0x102A8] mov x8, x8
  [0x102AC] b #0x102d0
  [0x102B0] ldr x9, [sp, #0x18]
  [0x102B4] add x16, x9, x15
  [0x102B8] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x102BC] add x16, x8, x15
  [0x102C0] ldr w9, [x16, #0x10] ;; misaligned with debug data
  [0x102C4] add x16, x9, x15
  [0x102C8] ldr w8, [x16] ;; misaligned with debug data
  [0x102CC] mov x8, x8
  [0x102D0] mov x8, x8
  [0x102D4] adrp x16, #0x10000
  [0x102D8] add x16, x16, #0
  [0x102DC] ldr w0, [x16]
  [0x102E0] add x7, x14, #8
  [0x102E4] sub x7, x7, x15 ;; misaligned with debug data
  [0x102E8] adrp x6, #0x18000
  [0x102EC] add x6, x6, #0xc64
  [0x102F0] sub x6, x6, x15
  [0x102F4] ldr x9, [sp, #0x18]
  [0x102F8] add x16, x9, x15
  [0x102FC] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10300] add x16, x1, x15
  [0x10304] ldr w2, [x16, #0x3c] ;; misaligned with debug data
  [0x10308] ldr x9, [sp, #0x18]
  [0x1030C] add x16, x9, x15
  [0x10310] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10314] add x16, x1, x15
  [0x10318] ldrb w1, [x16, #0x3b] ;; misaligned with debug data
  [0x1031C] ldr x9, [sp, #0x18]
  [0x10320] add x16, x9, x15
  [0x10324] ldr w3, [x16, #0x14] ;; misaligned with debug data
  [0x10328] add x16, x3, x15
  [0x1032C] ldrh w9, [x16, #0x38] ;; misaligned with debug data
  [0x10330] mov x3, x0
  [0x10334] mov x7, x7
  [0x10338] mov x6, x6
  [0x1033C] mov x2, x2
  [0x10340] mov x1, x1
  [0x10344] mov x8, x8
  [0x10348] mov x9, x9
  [0x1034C] add x3, x3, x15
  [0x10350] stp x3, x5, [sp, #-0x10]!
  [0x10354] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10358] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1035C] blr x3 ;; misaligned with debug data
  [0x10360] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10364] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10368] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1036C] mov x0, x0
  [0x10370] adrp x9, #0x10000
  [0x10374] add x9, x9, #0
  [0x10378] cmp x12, x9
  [0x1037C] b.ne #0x1042c
  [0x10380] adrp x16, #0x10000
  [0x10384] add x16, x16, #0
  [0x10388] ldr w8, [x16]
  [0x1038C] add x7, x14, #8
  [0x10390] sub x7, x7, x15 ;; misaligned with debug data
  [0x10394] adrp x6, #0x18000
  [0x10398] add x6, x6, #0xc84
  [0x1039C] sub x6, x6, x15
  [0x103A0] ldr x9, [sp, #0x18]
  [0x103A4] add x16, x9, x15
  [0x103A8] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x103AC] add x16, x1, x15
  [0x103B0] ldr s23, [x16, #0x20] ;; misaligned with debug data
  [0x103B4] ldr x9, [sp, #0x18]
  [0x103B8] add x16, x9, x15
  [0x103BC] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x103C0] add x16, x1, x15
  [0x103C4] ldr s22, [x16, #0x24] ;; misaligned with debug data
  [0x103C8] ldr x9, [sp, #0x18]
  [0x103CC] add x16, x9, x15
  [0x103D0] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x103D4] add x16, x1, x15
  [0x103D8] ldr s21, [x16, #0x28] ;; misaligned with debug data
  [0x103DC] mov x9, x8
  [0x103E0] mov x7, x7
  [0x103E4] mov x6, x6
  [0x103E8] fmov w2, s23
  [0x103EC] sxtw x2, w2
  [0x103F0] fmov w1, s22
  [0x103F4] sxtw x1, w1
  [0x103F8] fmov w8, s21
  [0x103FC] sxtw x8, w8
  [0x10400] add x9, x9, x15
  [0x10404] stp x3, x5, [sp, #-0x10]!
  [0x10408] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1040C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10410] blr x9 ;; misaligned with debug data
  [0x10414] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10418] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1041C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10420] mov x0, x0
  [0x10424] mov x0, x0
  [0x10428] b #0x104d4
  [0x1042C] adrp x16, #0x10000
  [0x10430] add x16, x16, #0
  [0x10434] ldr w8, [x16]
  [0x10438] add x7, x14, #8
  [0x1043C] sub x7, x7, x15 ;; misaligned with debug data
  [0x10440] adrp x6, #0x18000
  [0x10444] add x6, x6, #0xcb4
  [0x10448] sub x6, x6, x15
  [0x1044C] ldr x9, [sp, #0x18]
  [0x10450] add x16, x9, x15
  [0x10454] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10458] add x16, x1, x15
  [0x1045C] ldr s23, [x16, #0x20] ;; misaligned with debug data
  [0x10460] ldr x9, [sp, #0x18]
  [0x10464] add x16, x9, x15
  [0x10468] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x1046C] add x16, x1, x15
  [0x10470] ldr s22, [x16, #0x24] ;; misaligned with debug data
  [0x10474] ldr x9, [sp, #0x18]
  [0x10478] add x16, x9, x15
  [0x1047C] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10480] add x16, x1, x15
  [0x10484] ldr s21, [x16, #0x28] ;; misaligned with debug data
  [0x10488] mov x9, x8
  [0x1048C] mov x7, x7
  [0x10490] mov x6, x6
  [0x10494] fmov w2, s23
  [0x10498] sxtw x2, w2
  [0x1049C] fmov w1, s22
  [0x104A0] sxtw x1, w1
  [0x104A4] fmov w8, s21
  [0x104A8] sxtw x8, w8
  [0x104AC] add x9, x9, x15
  [0x104B0] stp x3, x5, [sp, #-0x10]!
  [0x104B4] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x104B8] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x104BC] blr x9 ;; misaligned with debug data
  [0x104C0] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x104C4] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x104C8] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x104CC] mov x0, x0
  [0x104D0] mov x0, x0
  [0x104D4] ldr x9, [sp, #0x18]
  [0x104D8] add x16, x9, x15
  [0x104DC] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x104E0] add x16, x8, x15
  [0x104E4] ldr w3, [x16, #0xc] ;; misaligned with debug data
  [0x104E8] mov x3, x3
  [0x104EC] movz x9, #0
  [0x104F0] mov x8, x14
  [0x104F4] sub x8, x8, x15 ;; misaligned with debug data
  [0x104F8] cmp x3, x9
  [0x104FC] b.eq #0x1050c
  [0x10500] add x8, x14, #8
  [0x10504] sub x8, x8, x15 ;; misaligned with debug data
  [0x10508] mov x8, x8
  [0x1050C] mov x9, x8
  [0x10510] mov x8, x14
  [0x10514] sub x8, x8, x15 ;; misaligned with debug data
  [0x10518] cmp x9, x8
  [0x1051C] b.eq #0x10574
  [0x10520] adrp x16, #0x10000
  [0x10524] add x16, x16, #0
  [0x10528] ldr w9, [x16]
  [0x1052C] add x16, x3, x15
  [0x10530] ldur w7, [x16, #-4] ;; misaligned with debug data
  [0x10534] adrp x16, #0x10000
  [0x10538] add x16, x16, #0
  [0x1053C] ldr w6, [x16]
  [0x10540] mov x9, x9
  [0x10544] mov x7, x7
  [0x10548] mov x6, x6
  [0x1054C] add x9, x9, x15
  [0x10550] stp x3, x5, [sp, #-0x10]!
  [0x10554] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10558] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1055C] blr x9 ;; misaligned with debug data
  [0x10560] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10564] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10568] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1056C] mov x0, x0
  [0x10570] mov x9, x0
  [0x10574] mov x8, x14
  [0x10578] sub x8, x8, x15 ;; misaligned with debug data
  [0x1057C] cmp x9, x8
  [0x10580] b.eq #0x1058c
  [0x10584] mov x3, x3
  [0x10588] b #0x10594
  [0x1058C] mov x3, x14
  [0x10590] sub x3, x3, x15 ;; misaligned with debug data
  [0x10594] mov x3, x3
  [0x10598] adrp x16, #0x10000
  [0x1059C] add x16, x16, #0
  [0x105A0] ldr w5, [x16]
  [0x105A4] add x7, x14, #8
  [0x105A8] sub x7, x7, x15 ;; misaligned with debug data
  [0x105AC] adrp x6, #0x18000
  [0x105B0] add x6, x6, #0xce4
  [0x105B4] sub x6, x6, x15
  [0x105B8] ldr x9, [sp, #0x18]
  [0x105BC] add x16, x9, x15
  [0x105C0] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x105C4] add x16, x8, x15
  [0x105C8] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x105CC] mov x8, x14
  [0x105D0] sub x8, x8, x15 ;; misaligned with debug data
  [0x105D4] cmp x9, x8
  [0x105D8] b.eq #0x105f8
  [0x105DC] ldr x9, [sp, #0x18]
  [0x105E0] add x16, x9, x15
  [0x105E4] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x105E8] add x16, x8, x15
  [0x105EC] ldr w2, [x16, #0xc] ;; misaligned with debug data
  [0x105F0] mov x2, x2
  [0x105F4] b #0x10600
  [0x105F8] movz x2, #0
  [0x105FC] mov x2, x2
  [0x10600] ldr x9, [sp, #0x18]
  [0x10604] add x16, x9, x15
  [0x10608] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x1060C] add x16, x8, x15
  [0x10610] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10614] mov x8, x14
  [0x10618] sub x8, x8, x15 ;; misaligned with debug data
  [0x1061C] cmp x9, x8
  [0x10620] b.eq #0x10648
  [0x10624] ldr x9, [sp, #0x18]
  [0x10628] add x16, x9, x15
  [0x1062C] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10630] add x16, x8, x15
  [0x10634] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10638] add x16, x9, x15
  [0x1063C] ldr w1, [x16] ;; misaligned with debug data
  [0x10640] mov x1, x1
  [0x10644] b #0x10658
  [0x10648] adrp x1, #0x18000
  [0x1064C] add x1, x1, #0xd14
  [0x10650] sub x1, x1, x15
  [0x10654] mov x1, x1
  [0x10658] ldr x9, [sp, #0x18]
  [0x1065C] add x16, x9, x15
  [0x10660] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x10664] add x16, x8, x15
  [0x10668] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x1066C] mov x9, x9
  [0x10670] mov x8, x14
  [0x10674] sub x8, x8, x15 ;; misaligned with debug data
  [0x10678] cmp x9, x8
  [0x1067C] b.eq #0x106a0
  [0x10680] ldr x9, [sp, #0x18]
  [0x10684] add x16, x9, x15
  [0x10688] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x1068C] add x16, x8, x15
  [0x10690] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10694] add x16, x9, x15
  [0x10698] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x1069C] mov x9, x9
  [0x106A0] mov x8, x14
  [0x106A4] sub x8, x8, x15 ;; misaligned with debug data
  [0x106A8] cmp x9, x8
  [0x106AC] b.eq #0x106dc
  [0x106B0] ldr x9, [sp, #0x18]
  [0x106B4] add x16, x9, x15
  [0x106B8] ldr w8, [x16, #0x14] ;; misaligned with debug data
  [0x106BC] add x16, x8, x15
  [0x106C0] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x106C4] add x16, x9, x15
  [0x106C8] ldr w9, [x16, #0x34] ;; misaligned with debug data
  [0x106CC] add x16, x9, x15
  [0x106D0] ldr w8, [x16] ;; misaligned with debug data
  [0x106D4] mov x8, x8
  [0x106D8] b #0x106ec
  [0x106DC] adrp x8, #0x18000
  [0x106E0] add x8, x8, #0xd24
  [0x106E4] sub x8, x8, x15
  [0x106E8] mov x8, x8
  [0x106EC] ldr x9, [sp, #0x18]
  [0x106F0] add x16, x9, x15
  [0x106F4] ldr w0, [x16, #0x14] ;; misaligned with debug data
  [0x106F8] add x16, x0, x15
  [0x106FC] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10700] mov x0, x14
  [0x10704] sub x0, x0, x15 ;; misaligned with debug data
  [0x10708] cmp x9, x0
  [0x1070C] b.eq #0x10790
  [0x10710] ldr x9, [sp, #0x18]
  [0x10714] add x16, x9, x15
  [0x10718] ldr w0, [x16, #0x14] ;; misaligned with debug data
  [0x1071C] add x16, x0, x15
  [0x10720] ldr w9, [x16, #0xc] ;; misaligned with debug data
  [0x10724] add x16, x9, x15
  [0x10728] ldrsw x9, [x16, #0x44] ;; misaligned with debug data
  [0x1072C] mov x9, x9
  [0x10730] ldr x0, [sp, #0x18]
  [0x10734] add x16, x0, x15
  [0x10738] ldr w11, [x16, #0x14] ;; misaligned with debug data
  [0x1073C] add x16, x11, x15
  [0x10740] ldr w0, [x16, #0xc] ;; misaligned with debug data
  [0x10744] add x16, x0, x15
  [0x10748] ldr w0, [x16, #0x50] ;; misaligned with debug data
  [0x1074C] mov x0, x0
  [0x10750] mov x11, x0
  [0x10754] ldr x0, [sp, #0x18]
  [0x10758] add x16, x0, x15
  [0x1075C] ldr w10, [x16, #0x14] ;; misaligned with debug data
  [0x10760] add x16, x10, x15
  [0x10764] ldr w0, [x16, #0xc] ;; misaligned with debug data
  [0x10768] add x16, x0, x15
  [0x1076C] ldr w0, [x16, #0x54] ;; misaligned with debug data
  [0x10770] mov x0, x0
  [0x10774] mov x0, x0
  [0x10778] sub x11, x11, x0
  [0x1077C] sub x9, x9, x11
  [0x10780] mov x9, x9
  [0x10784] lsl x9, x9, #3
  [0x10788] mov x9, x9
  [0x1078C] b #0x107a0
  [0x10790] adrp x9, #0x18000
  [0x10794] add x9, x9, #0xd34
  [0x10798] sub x9, x9, x15
  [0x1079C] mov x9, x9
  [0x107A0] ldr x0, [sp, #0x18]
  [0x107A4] add x16, x0, x15
  [0x107A8] ldr w11, [x16, #0x14] ;; misaligned with debug data
  [0x107AC] add x16, x11, x15
  [0x107B0] ldr w0, [x16, #0xc] ;; misaligned with debug data
  [0x107B4] mov x11, x14
  [0x107B8] sub x11, x11, x15 ;; misaligned with debug data
  [0x107BC] cmp x0, x11
  [0x107C0] b.eq #0x107f0
  [0x107C4] ldr x0, [sp, #0x18]
  [0x107C8] add x16, x0, x15
  [0x107CC] ldr w11, [x16, #0x14] ;; misaligned with debug data
  [0x107D0] add x16, x11, x15
  [0x107D4] ldr w0, [x16, #0xc] ;; misaligned with debug data
  [0x107D8] add x16, x0, x15
  [0x107DC] ldrsw x10, [x16, #0x44] ;; misaligned with debug data
  [0x107E0] mov x10, x10
  [0x107E4] lsl x10, x10, #3
  [0x107E8] mov x10, x10
  [0x107EC] b #0x10800
  [0x107F0] adrp x10, #0x18000
  [0x107F4] add x10, x10, #0xd44
  [0x107F8] sub x10, x10, x15
  [0x107FC] mov x10, x10
  [0x10800] mov x5, x5
  [0x10804] mov x7, x7
  [0x10808] mov x6, x6
  [0x1080C] mov x2, x2
  [0x10810] mov x1, x1
  [0x10814] mov x8, x8
  [0x10818] mov x9, x9
  [0x1081C] mov x10, x10
  [0x10820] add x5, x5, x15
  [0x10824] stp x3, x5, [sp, #-0x10]!
  [0x10828] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1082C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10830] blr x5 ;; misaligned with debug data
  [0x10834] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10838] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1083C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10840] mov x0, x0
  [0x10844] adrp x16, #0x10000
  [0x10848] add x16, x16, #0
  [0x1084C] ldr w9, [x16]
  [0x10850] add x6, x14, #8
  [0x10854] sub x6, x6, x15 ;; misaligned with debug data
  [0x10858] mov x9, x9
  [0x1085C] mov x7, x3
  [0x10860] mov x6, x6
  [0x10864] add x9, x9, x15
  [0x10868] stp x3, x5, [sp, #-0x10]!
  [0x1086C] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10870] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10874] blr x9 ;; misaligned with debug data
  [0x10878] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x1087C] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10880] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10884] mov x3, x3
  [0x10888] adrp x16, #0x10000
  [0x1088C] add x16, x16, #0
  [0x10890] ldr w9, [x16]
  [0x10894] add x7, x14, #8
  [0x10898] sub x7, x7, x15 ;; misaligned with debug data
  [0x1089C] adrp x6, #0x18000
  [0x108A0] add x6, x6, #0xd54
  [0x108A4] sub x6, x6, x15
  [0x108A8] mov x9, x9
  [0x108AC] mov x7, x7
  [0x108B0] mov x6, x6
  [0x108B4] add x9, x9, x15
  [0x108B8] stp x3, x5, [sp, #-0x10]!
  [0x108BC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x108C0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x108C4] blr x9 ;; misaligned with debug data
  [0x108C8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x108CC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x108D0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x108D4] mov x0, x0
  [0x108D8] adrp x9, #0x10000
  [0x108DC] add x9, x9, #0
  [0x108E0] cmp x12, x9
  [0x108E4] b.ne #0x10958
  [0x108E8] adrp x16, #0x10000
  [0x108EC] add x16, x16, #0
  [0x108F0] ldr w8, [x16]
  [0x108F4] add x7, x14, #8
  [0x108F8] sub x7, x7, x15 ;; misaligned with debug data
  [0x108FC] adrp x6, #0x18000
  [0x10900] add x6, x6, #0xd64
  [0x10904] sub x6, x6, x15
  [0x10908] movz x2, #0x30
  [0x1090C] ldr x9, [sp, #0x18]
  [0x10910] add x16, x9, x15
  [0x10914] ldr w1, [x16, #0x14] ;; misaligned with debug data
  [0x10918] add x2, x2, x1
  [0x1091C] mov x8, x8
  [0x10920] mov x7, x7
  [0x10924] mov x6, x6
  [0x10928] mov x2, x2
  [0x1092C] add x8, x8, x15
  [0x10930] stp x3, x5, [sp, #-0x10]!
  [0x10934] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x10938] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x1093C] blr x8 ;; misaligned with debug data
  [0x10940] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10944] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x10948] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x1094C] mov x0, x0
  [0x10950] mov x0, x0
  [0x10954] b #0x10960
  [0x10958] mov x0, x14
  [0x1095C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10960] mov x0, x0
  [0x10964] b #0x10970
  [0x10968] mov x0, x14
  [0x1096C] sub x0, x0, x15 ;; misaligned with debug data
  [0x10970] add sp, sp, #0x20
  [0x10974] ldp x29, x30, [sp], #0x10
  [0x10978] ret


[(method print entity)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x20
  [0x1000C] mov x7, x7
  [0x10010] str x7, [sp, #0x10]
  [0x10014] adrp x16, #0x10000
  [0x10018] add x16, x16, #0
  [0x1001C] ldr w5, [x16]
  [0x10020] add x12, x14, #8
  [0x10024] sub x12, x12, x15 ;; misaligned with debug data
  [0x10028] adrp x11, #0x1a000
  [0x1002C] add x11, x11, #0xac4
  [0x10030] sub x11, x11, x15
  [0x10034] ldr x8, [sp, #0x10]
  [0x10038] add x16, x8, x15
  [0x1003C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10040] str x9, [sp]
  [0x10044] adrp x16, #0x10000
  [0x10048] add x16, x16, #0
  [0x1004C] ldr w9, [x16]
  [0x10050] add x16, x9, x15
  [0x10054] ldr w1, [x16, #0x38] ;; misaligned with debug data
  [0x10058] adrp x6, #0x10000
  [0x1005C] add x6, x6, #0
  [0x10060] adrp x2, #0x10000
  [0x10064] add x2, x2, #0
  [0x10068] adrp x16, #0x1a000
  [0x1006C] ldr s23, [x16, #0xae0]
  [0x10070] mov x8, x14
  [0x10074] sub x8, x8, x15 ;; misaligned with debug data
  [0x10078] mov x8, x8
  [0x1007C] mov x9, x14
  [0x10080] sub x9, x9, x15 ;; misaligned with debug data
  [0x10084] mov x9, x9
  [0x10088] adrp x16, #0x10000
  [0x1008C] add x16, x16, #0
  [0x10090] ldr w10, [x16]
  [0x10094] mov x1, x1
  [0x10098] str x1, [sp, #8]
  [0x1009C] ldr x1, [sp, #0x10]
  [0x100A0] mov x7, x1
  [0x100A4] mov x6, x6
  [0x100A8] mov x2, x2
  [0x100AC] fmov w1, s23
  [0x100B0] sxtw x1, w1
  [0x100B4] mov x8, x8
  [0x100B8] mov x9, x9
  [0x100BC] mov x10, x10
  [0x100C0] ldr x3, [sp, #8]
  [0x100C4] add x3, x3, x15
  [0x100C8] stp x3, x5, [sp, #-0x10]!
  [0x100CC] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D0] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100D4] blr x3 ;; misaligned with debug data
  [0x100D8] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100DC] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100E0] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100E4] str x3, [sp, #8]
  [0x100E8] mov x0, x0
  [0x100EC] mov x0, x0
  [0x100F0] mov x5, x5
  [0x100F4] mov x7, x12
  [0x100F8] mov x6, x11
  [0x100FC] ldr x2, [sp]
  [0x10100] mov x2, x2
  [0x10104] mov x1, x0
  [0x10108] ldr x9, [sp, #0x10]
  [0x1010C] mov x8, x9
  [0x10110] add x5, x5, x15
  [0x10114] stp x3, x5, [sp, #-0x10]!
  [0x10118] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1011C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10120] blr x5 ;; misaligned with debug data
  [0x10124] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10128] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1012C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10130] mov x0, x0
  [0x10134] ldr x0, [sp, #0x10]
  [0x10138] mov x0, x0
  [0x1013C] add sp, sp, #0x20
  [0x10140] ldp x29, x30, [sp], #0x10
  [0x10144] ret


[(method mem-usage drawable-actor)]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] sub sp, sp, #0x10
  [0x1000C] mov x5, x7
  [0x10010] mov x3, x6
  [0x10014] mov x12, x2
  [0x10018] movz x9, #0x2c
  [0x1001C] add x16, x3, x15
  [0x10020] ldrsw x8, [x16, #4] ;; misaligned with debug data
  [0x10024] mov x9, x9
  [0x10028] mov x8, x8
  [0x1002C] cmp x9, x8
  [0x10030] b.le #0x1003c
  [0x10034] mov x9, x9
  [0x10038] b #0x10040
  [0x1003C] mov x9, x8
  [0x10040] add x16, x3, x15
  [0x10044] str w9, [x16, #4] ;; misaligned with debug data
  [0x10048] adrp x9, #0x1a000
  [0x1004C] add x9, x9, #0x9f4
  [0x10050] sub x9, x9, x15
  [0x10054] add x16, x3, x15
  [0x10058] str w9, [x16, #0x2bc] ;; misaligned with debug data
  [0x1005C] add x16, x3, x15
  [0x10060] ldrsw x9, [x16, #0x2c0] ;; misaligned with debug data
  [0x10064] mov x9, x9
  [0x10068] movz x8, #0x1
  [0x1006C] add x9, x9, x8
  [0x10070] add x16, x3, x15
  [0x10074] str w9, [x16, #0x2c0] ;; misaligned with debug data
  [0x10078] add x16, x5, x15
  [0x1007C] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10080] add x16, x9, x15
  [0x10084] ldr w9, [x16, #0x24] ;; misaligned with debug data
  [0x10088] mov x9, x9
  [0x1008C] mov x7, x5
  [0x10090] add x9, x9, x15
  [0x10094] stp x3, x5, [sp, #-0x10]!
  [0x10098] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1009C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x100A0] blr x9 ;; misaligned with debug data
  [0x100A4] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x100A8] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x100AC] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x100B0] mov x0, x0
  [0x100B4] mov x0, x0
  [0x100B8] add x16, x3, x15
  [0x100BC] ldrsw x9, [x16, #0x2c4] ;; misaligned with debug data
  [0x100C0] mov x9, x9
  [0x100C4] add x9, x9, x0
  [0x100C8] add x16, x3, x15
  [0x100CC] str w9, [x16, #0x2c4] ;; misaligned with debug data
  [0x100D0] add x16, x3, x15
  [0x100D4] ldrsw x9, [x16, #0x2c8] ;; misaligned with debug data
  [0x100D8] mov x9, x9
  [0x100DC] movz x8, #0xfff0
  [0x100E0] movk x8, #0xffff, lsl #16
  [0x100E4] movk x8, #0xffff, lsl #32
  [0x100E8] movk x8, #0xffff, lsl #48
  [0x100EC] mov x0, x0
  [0x100F0] movz x1, #0xf
  [0x100F4] add x0, x0, x1
  [0x100F8] mov x8, x8
  [0x100FC] and x8, x8, x0
  [0x10100] add x9, x9, x8
  [0x10104] add x16, x3, x15
  [0x10108] str w9, [x16, #0x2c8] ;; misaligned with debug data
  [0x1010C] add x16, x5, x15
  [0x10110] ldr w7, [x16, #4] ;; misaligned with debug data
  [0x10114] mov x12, x12
  [0x10118] movz x9, #0x40
  [0x1011C] orr x12, x12, x9
  [0x10120] add x16, x7, x15
  [0x10124] ldur w9, [x16, #-4] ;; misaligned with debug data
  [0x10128] add x16, x9, x15
  [0x1012C] ldr w9, [x16, #0x30] ;; misaligned with debug data
  [0x10130] mov x9, x9
  [0x10134] mov x7, x7
  [0x10138] mov x6, x3
  [0x1013C] mov x2, x12
  [0x10140] add x9, x9, x15
  [0x10144] stp x3, x5, [sp, #-0x10]!
  [0x10148] stp x10, x11, [sp, #-0x10]! ;; misaligned with debug data
  [0x1014C] stp x12, x23, [sp, #-0x10]! ;; misaligned with debug data
  [0x10150] blr x9 ;; misaligned with debug data
  [0x10154] ldp x12, x23, [sp], #0x10 ;; misaligned with debug data
  [0x10158] ldp x10, x11, [sp], #0x10 ;; misaligned with debug data
  [0x1015C] ldp x3, x5, [sp], #0x10 ;; misaligned with debug data
  [0x10160] mov x0, x0
  [0x10164] movz x0, #0
  [0x10168] mov x0, x0
  [0x1016C] mov x0, x0
  [0x10170] add sp, sp, #0x10
  [0x10174] ldp x29, x30, [sp], #0x10
  [0x10178] ret



