.text
.global mips2c_x12_oracle
mips2c_x12_oracle:
  stp x12, x30, [sp, #-16]!
  ldr x16, exec_literal
  ldr x12, stack_literal
  ldr x17, helper_literal
  blr x17
  ldp x12, x30, [sp], #16
  ret
  .word 0
exec_literal:
  .quad 0
stack_literal:
  .quad 0
helper_literal:
  .quad 0
