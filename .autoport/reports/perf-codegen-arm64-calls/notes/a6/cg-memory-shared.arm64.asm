[top-level]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp
  [0x10008] adrp x0, #0x10000                                mov-fa igpr-0, function-test-cg-memory-shared
  [0x1000C] add x0, x0, #0
  [0x10010] sub x0, x0, x15

cg-memory-shared.gc:2
-> (defun test-cg-memory-shared ()
  [0x10014] adrp x16, #0x10000                               mov 'test-cg-memory-shared, igpr-0
  [0x10018] str w0, [x16]

cg-memory-shared.gc:1
-> ; Two consecutive nonzero field loads; expected 142.
  [0x1001C] mov x0, x0                                       ret igpr-1 igpr-0
  [0x10020] ldp x29, x30, [sp], #0x10
  [0x10024] ret


[test-cg-memory-shared]
  [0x10000] stp x29, x30, [sp, #-0x10]!
  [0x10004] mov x29, sp

cg-memory-shared.gc:3
->   (let ((buf (the (pointer int32) #x40000000)))
  [0x10008] movz x9, #0                                      mov-ic igpr-1, 1073741824
  [0x1000C] movk x9, #0x4000, lsl #16
  [0x10010] mov x9, x9                                       mov igpr-2, igpr-1

cg-memory-shared.gc:3
->   (let ((buf (the (pointer int32) #x40000000)))
  [0x10014] mov x9, x9                                       mov igpr-3, igpr-2

cg-memory-shared.gc:4
->     (set! (-> buf 1) 100)
  [0x10018] movz x8, #0x64                                   mov-ic igpr-4, 100
  [0x1001C] add x16, x9, x15                                 move [igpr-3 + 4], igpr-4
  [0x10020] str w8, [x16, #4] ;; misaligned with debug data

cg-memory-shared.gc:5
->     (set! (-> buf 2) 42)
  [0x10024] movz x8, #0x2a                                   mov-ic igpr-5, 42
  [0x10028] add x16, x9, x15                                 move [igpr-3 + 8], igpr-5
  [0x1002C] str w8, [x16, #8] ;; misaligned with debug data

cg-memory-shared.gc:6
->     (+ (-> buf 1) (-> buf 2))))
  [0x10030] ldrsw x0, [x16, #4]                              mov igpr-7, [igpr-3 + 4]
  [0x10034] mov x0, x0                                       mov igpr-6, igpr-7
  [0x10038] add x16, x9, x15                                 mov igpr-8, [igpr-3 + 8]
  [0x1003C] ldrsw x9, [x16, #8] ;; misaligned with debug data
  [0x10040] add x0, x0, x9                                   addi igpr-6, igpr-8

cg-memory-shared.gc:2
-> (defun test-cg-memory-shared ()
  [0x10044] mov x0, x0                                       ret igpr-0 igpr-6
  [0x10048] ldp x29, x30, [sp], #0x10
  [0x1004C] ret
