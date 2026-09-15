[top-level]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] adrp x0, #0x10000                                mov-fa igpr-0, function-test-cg-memory-branch
  [0x1000C] add x0, x0, #0
  [0x10010] sub x0, x0, x15

cg-memory-branch.gc:2
-> (defun test-cg-memory-branch ()
  [0x10014] adrp x16, #0x10000                               mov 'test-cg-memory-branch, igpr-0
  [0x10018] str w0, [x16]

cg-memory-branch.gc:1
-> ; Both incoming paths to a join, with distinct address bases; expected 168.
  [0x1001C] mov x0, x0                                       ret igpr-1 igpr-0
  [0x10020] ldp x29, x30, [sp], #0x10
  [0x10024] ret


[test-cg-memory-branch]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp

cg-memory-branch.gc:3
->   (let ((p (the (pointer int32) #x40000000))
  [0x10008] movz x9, #0                                      mov-ic igpr-1, 1073741824
  [0x1000C] movk x9, #0x4000, lsl #16
  [0x10010] mov x9, x9                                       mov igpr-2, igpr-1

cg-memory-branch.gc:4
->         (q (the (pointer int32) #x40000040))
  [0x10014] movz x8, #0x40                                   mov-ic igpr-3, 1073741888
  [0x10018] movk x8, #0x4000, lsl #16
  [0x1001C] mov x8, x8                                       mov igpr-4, igpr-3

cg-memory-branch.gc:3
->   (let ((p (the (pointer int32) #x40000000))
  [0x10020] movz x0, #0                                      mov-ic igpr-5, 0
  [0x10024] movz x1, #0                                      mov-ic igpr-6, 0
  [0x10028] mov x9, x9                                       mov igpr-7, igpr-2
  [0x1002C] mov x8, x8                                       mov igpr-8, igpr-4
  [0x10030] mov x0, x0                                       mov igpr-9, igpr-5
  [0x10034] mov x1, x1                                       mov igpr-10, igpr-6

cg-memory-branch.gc:7
->     (set! (-> p 1) 100)
  [0x10038] movz x2, #0x64                                   mov-ic igpr-11, 100
  [0x1003C] add x16, x9, x15                                 move [igpr-7 + 4], igpr-11
  [0x10040] str w2, [x16, #4] ;; misaligned with debug data

cg-memory-branch.gc:8
->     (set! (-> p 2) 42)
  [0x10044] movz x2, #0x2a                                   mov-ic igpr-12, 42
  [0x10048] add x16, x9, x15                                 move [igpr-7 + 8], igpr-12
  [0x1004C] str w2, [x16, #8] ;; misaligned with debug data

cg-memory-branch.gc:9
->     (set! (-> q 1) 0)
  [0x10050] movz x2, #0                                      mov-ic igpr-13, 0
  [0x10054] add x16, x8, x15                                 move [igpr-8 + 4], igpr-13
  [0x10058] str w2, [x16, #4] ;; misaligned with debug data

cg-memory-branch.gc:10
->     (set! (-> q 2) 7)
  [0x1005C] movz x2, #0x7                                    mov-ic igpr-14, 7
  [0x10060] add x16, x8, x15                                 move [igpr-8 + 8], igpr-14
  [0x10064] str w2, [x16, #8] ;; misaligned with debug data

cg-memory-branch.gc:11
->     (while (< i 2)
  [0x10068] b #0x100dc                                       goto label-41

cg-memory-branch.gc:12
->       (if (zero? (-> q 1))
  [0x1006C] add x16, x8, x15                                 mov igpr-18, [igpr-8 + 4]
  [0x10070] ldrsw x2, [x16, #4] ;; misaligned with debug data
  [0x10074] movz x6, #0                                      mov-ic igpr-19, 0
  [0x10078] cmp x2, x6                                       j(igpr-18 != igpr-19) label-27
  [0x1007C] b.ne #0x10094

cg-memory-branch.gc:13
->         (set! (-> p 1) (-> p 2)))
  [0x10080] add x16, x9, x15                                 mov igpr-20, [igpr-7 + 8]
  [0x10084] ldrsw x2, [x16, #8] ;; misaligned with debug data
  [0x10088] str w2, [x16, #4]                                move [igpr-7 + 4], igpr-20

cg-memory-branch.gc:12
->       (if (zero? (-> q 1))
  [0x1008C] mov x2, x2                                       mov igpr-17, igpr-20
  [0x10090] b #0x1009c                                       goto label-28
  [0x10094] mov x2, x14                                      mov-symptr igpr-17, '#f
  [0x10098] sub x2, x2, x15 ;; misaligned with debug data

cg-memory-branch.gc:14
->       (set! total (+ total (+ (-> p 1) (-> p 2))))
  [0x1009C] mov x0, x0                                       mov igpr-21, igpr-9

cg-memory-branch.gc:14
->       (set! total (+ total (+ (-> p 1) (-> p 2))))
  [0x100A0] add x16, x9, x15                                 mov igpr-23, [igpr-7 + 4]
  [0x100A4] ldrsw x2, [x16, #4] ;; misaligned with debug data
  [0x100A8] mov x2, x2                                       mov igpr-22, igpr-23
  [0x100AC] add x16, x9, x15                                 mov igpr-24, [igpr-7 + 8]
  [0x100B0] ldrsw x6, [x16, #8] ;; misaligned with debug data
  [0x100B4] add x2, x2, x6                                   addi igpr-22, igpr-24

cg-memory-branch.gc:14
->       (set! total (+ total (+ (-> p 1) (-> p 2))))
  [0x100B8] add x0, x0, x2                                   addi igpr-21, igpr-22

cg-memory-branch.gc:14
->       (set! total (+ total (+ (-> p 1) (-> p 2))))
  [0x100BC] mov x0, x0                                       mov igpr-9, igpr-21

cg-memory-branch.gc:15
->       (set! (-> q 1) 1)
  [0x100C0] movz x2, #0x1                                    mov-ic igpr-25, 1
  [0x100C4] add x16, x8, x15                                 move [igpr-8 + 4], igpr-25
  [0x100C8] str w2, [x16, #4] ;; misaligned with debug data

cg-memory-branch.gc:16
->       (set! i (+ i 1)))
  [0x100CC] mov x1, x1                                       mov igpr-26, igpr-10
  [0x100D0] movz x2, #0x1                                    mov-ic igpr-27, 1
  [0x100D4] add x1, x1, x2                                   addi igpr-26, igpr-27

cg-memory-branch.gc:16
->       (set! i (+ i 1)))
  [0x100D8] mov x1, x1                                       mov igpr-10, igpr-26

cg-memory-branch.gc:11
->     (while (< i 2)
  [0x100DC] movz x2, #0x2                                    mov-ic igpr-28, 2

cg-memory-branch.gc:11
->     (while (< i 2)
  [0x100E0] cmp x1, x2                                       j(igpr-10 < igpr-28) label-20
  [0x100E4] b.lt #0x1006c
  [0x100E8] mov x9, x14                                      mov-symptr igpr-29, '#f
  [0x100EC] sub x9, x9, x15 ;; misaligned with debug data

cg-memory-branch.gc:2
-> (defun test-cg-memory-branch ()
  [0x100F0] mov x0, x0                                       ret igpr-0 igpr-9
  [0x100F4] ldp x29, x30, [sp], #0x10
  [0x100F8] ret
