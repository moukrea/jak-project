$ objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/x86-after.o

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/x86-after.o:     file format elf64-x86-64


Disassembly of section .text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv:

0000000000000000 <Mips2C::jak1::geco_spart_dump_armed()>:
   0:	48 83 ec 18          	sub    $0x18,%rsp
   4:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # b <Mips2C::jak1::geco_spart_dump_armed()+0xb>	7: R_X86_64_PC32	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay-0x4
   b:	48 83 f8 fe          	cmp    $0xfffffffffffffffe,%rax
   f:	74 4f                	je     60 <Mips2C::jak1::geco_spart_dump_armed()+0x60>
  11:	48 85 c0             	test   %rax,%rax
  14:	7f 0a                	jg     20 <Mips2C::jak1::geco_spart_dump_armed()+0x20>
  16:	0f 94 c0             	sete   %al
  19:	48 83 c4 18          	add    $0x18,%rsp
  1d:	c3                   	ret
  1e:	66 90                	xchg   %ax,%ax
  20:	31 ff                	xor    %edi,%edi
  22:	e8 00 00 00 00       	call   27 <Mips2C::jak1::geco_spart_dump_armed()+0x27>	23: R_X86_64_PLT32	time-0x4
  27:	48 89 c2             	mov    %rax,%rdx
  2a:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 31 <Mips2C::jak1::geco_spart_dump_armed()+0x31>	2d: R_X86_64_PC32	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay-0x4
  31:	48 39 c2             	cmp    %rax,%rdx
  34:	7d 12                	jge    48 <Mips2C::jak1::geco_spart_dump_armed()+0x48>
  36:	48 85 c0             	test   %rax,%rax
  39:	0f 94 c0             	sete   %al
  3c:	48 83 c4 18          	add    $0x18,%rsp
  40:	c3                   	ret
  41:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  48:	48 c7 05 00 00 00 00 00 00 00 00 	movq   $0x0,0x0(%rip)        # 53 <Mips2C::jak1::geco_spart_dump_armed()+0x53>	4b: R_X86_64_PC32	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay-0x8
  53:	b8 01 00 00 00       	mov    $0x1,%eax
  58:	48 83 c4 18          	add    $0x18,%rsp
  5c:	c3                   	ret
  5d:	0f 1f 00             	nopl   (%rax)
  60:	48 c7 05 00 00 00 00 ff ff ff ff 	movq   $0xffffffffffffffff,0x0(%rip)        # 6b <Mips2C::jak1::geco_spart_dump_armed()+0x6b>	63: R_X86_64_PC32	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay-0x8
  6b:	bf 00 00 00 00       	mov    $0x0,%edi	6c: R_X86_64_32	.rodata._ZN6Mips2C4jak1L21geco_spart_dump_armedEv.str1.1
  70:	e8 00 00 00 00       	call   75 <Mips2C::jak1::geco_spart_dump_armed()+0x75>	71: R_X86_64_PLT32	getenv-0x4
  75:	48 85 c0             	test   %rax,%rax
  78:	74 05                	je     7f <Mips2C::jak1::geco_spart_dump_armed()+0x7f>
  7a:	80 38 00             	cmpb   $0x0,(%rax)
  7d:	75 11                	jne    90 <Mips2C::jak1::geco_spart_dump_armed()+0x90>
  7f:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 86 <Mips2C::jak1::geco_spart_dump_armed()+0x86>	82: R_X86_64_PC32	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay-0x4
  86:	eb 89                	jmp    11 <Mips2C::jak1::geco_spart_dump_armed()+0x11>
  88:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  90:	31 f6                	xor    %esi,%esi
  92:	ba 0a 00 00 00       	mov    $0xa,%edx
  97:	48 89 c7             	mov    %rax,%rdi
  9a:	e8 00 00 00 00       	call   9f <Mips2C::jak1::geco_spart_dump_armed()+0x9f>	9b: R_X86_64_PLT32	__isoc23_strtol-0x4
  9f:	48 83 f8 01          	cmp    $0x1,%rax
  a3:	74 a3                	je     48 <Mips2C::jak1::geco_spart_dump_armed()+0x48>
  a5:	7e d8                	jle    7f <Mips2C::jak1::geco_spart_dump_armed()+0x7f>
  a7:	31 ff                	xor    %edi,%edi
  a9:	48 89 44 24 08       	mov    %rax,0x8(%rsp)
  ae:	e8 00 00 00 00       	call   b3 <Mips2C::jak1::geco_spart_dump_armed()+0xb3>	af: R_X86_64_PLT32	time-0x4
  b3:	48 03 44 24 08       	add    0x8(%rsp),%rax
  b8:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # bf <Mips2C::jak1::geco_spart_dump_armed()+0xbf>	bb: R_X86_64_PC32	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay-0x4
  bf:	e9 4d ff ff ff       	jmp    11 <Mips2C::jak1::geco_spart_dump_armed()+0x11>

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
       0:	55                   	push   %rbp
       1:	48 89 e5             	mov    %rsp,%rbp
       4:	41 57                	push   %r15
       6:	41 56                	push   %r14
       8:	41 55                	push   %r13
       a:	41 54                	push   %r12
       c:	53                   	push   %rbx
       d:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
      11:	48 81 ec 80 01 00 00 	sub    $0x180,%rsp
      18:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
      1f:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
      26:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 2d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d>	29: R_X86_64_PC32	g_ee_main_mem-0x4
      2d:	48 2d a0 00 00 00    	sub    $0xa0,%rax
      33:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
      3a:	89 c0                	mov    %eax,%eax
      3c:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
      40:	48 8b 8f e0 01 00 00 	mov    0x1e0(%rdi),%rcx
      47:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      4d:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 54 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x54>	50: R_X86_64_PC32	g_ee_main_mem-0x4
      54:	48 89 4c 02 08       	mov    %rcx,0x8(%rdx,%rax,1)
      59:	48 8b 87 90 01 00 00 	mov    0x190(%rdi),%rax
      60:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 67 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x67>	63: R_X86_64_PC32	g_ee_main_mem-0x4
      67:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
      6f:	48 89 87 e0 01 00 00 	mov    %rax,0x1e0(%rdi)
      76:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      7c:	83 c0 30             	add    $0x30,%eax
      7f:	83 e0 f0             	and    $0xfffffff0,%eax
      82:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      88:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      8e:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
      96:	83 c0 40             	add    $0x40,%eax
      99:	83 e0 f0             	and    $0xfffffff0,%eax
      9c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      a2:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      a8:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
      b0:	83 c0 50             	add    $0x50,%eax
      b3:	83 e0 f0             	and    $0xfffffff0,%eax
      b6:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      bc:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      c2:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
      ca:	83 c0 60             	add    $0x60,%eax
      cd:	83 e0 f0             	and    $0xfffffff0,%eax
      d0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      d6:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      dc:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
      e4:	83 c0 70             	add    $0x70,%eax
      e7:	83 e0 f0             	and    $0xfffffff0,%eax
      ea:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      f0:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      f6:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
      fe:	83 e8 80             	sub    $0xffffff80,%eax
     101:	83 e0 f0             	and    $0xfffffff0,%eax
     104:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     10a:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     110:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
     118:	05 90 00 00 00       	add    $0x90,%eax
     11d:	83 e0 f0             	and    $0xfffffff0,%eax
     120:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     126:	48 8b 47 40          	mov    0x40(%rdi),%rax
     12a:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
     12e:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
     135:	48 8b 47 50          	mov    0x50(%rdi),%rax
     139:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
     140:	48 8b 47 60          	mov    0x60(%rdi),%rax
     144:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
     14b:	48 8b 47 70          	mov    0x70(%rdi),%rax
     14f:	48 89 87 00 01 00 00 	mov    %rax,0x100(%rdi)
     156:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
     15d:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
     164:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
     16b:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
     172:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
     179:	48 83 c0 10          	add    $0x10,%rax
     17d:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
     184:	83 e0 f0             	and    $0xfffffff0,%eax
     187:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     18d:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 194 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x194>	190: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
     194:	48 63 10             	movslq (%rax),%rdx
     197:	48 89 57 30          	mov    %rdx,0x30(%rdi)
     19b:	f6 c2 0f             	test   $0xf,%dl
     19e:	0f 85 dc 11 00 00    	jne    1380 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     1a4:	89 d0                	mov    %edx,%eax
     1a6:	8b 9f d0 01 00 00    	mov    0x1d0(%rdi),%ebx
     1ac:	49 89 fe             	mov    %rdi,%r14
     1af:	49 8b 4c 01 08       	mov    0x8(%r9,%rax,1),%rcx
     1b4:	49 8b 14 01          	mov    (%r9,%rax,1),%rdx
     1b8:	48 89 8f 88 03 00 00 	mov    %rcx,0x388(%rdi)
     1bf:	0f b6 c2             	movzbl %dl,%eax
     1c2:	48 89 97 80 03 00 00 	mov    %rdx,0x380(%rdi)
     1c9:	48 89 ca             	mov    %rcx,%rdx
     1cc:	48 89 4f 38          	mov    %rcx,0x38(%rdi)
     1d0:	8d 4b 20             	lea    0x20(%rbx),%ecx
     1d3:	83 e1 f0             	and    $0xfffffff0,%ecx
     1d6:	48 89 47 30          	mov    %rax,0x30(%rdi)
     1da:	49 89 04 09          	mov    %rax,(%r9,%rcx,1)
     1de:	49 89 54 09 08       	mov    %rdx,0x8(%r9,%rcx,1)
     1e3:	48 8b 87 50 01 00 00 	mov    0x150(%rdi),%rax
     1ea:	e9 b3 00 00 00       	jmp    2a2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2a2>
     1ef:	90                   	nop
     1f0:	49 63 08             	movslq (%r8),%rcx
     1f3:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
     1fb:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     1ff:	85 c9                	test   %ecx,%ecx
     201:	0f 84 60 01 00 00    	je     367 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     207:	8b 07                	mov    (%rdi),%eax
     209:	89 c2                	mov    %eax,%edx
     20b:	83 e0 bf             	and    $0xffffffbf,%eax
     20e:	83 e2 40             	and    $0x40,%edx
     211:	48 63 c8             	movslq %eax,%rcx
     214:	89 d3                	mov    %edx,%ebx
     216:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     21a:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     21e:	89 07                	mov    %eax,(%rdi)
     220:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 227 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x227>	223: R_X86_64_PC32	g_ee_main_mem-0x4
     227:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     22e:	85 d2                	test   %edx,%edx
     230:	74 2e                	je     260 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     232:	89 c0                	mov    %eax,%eax
     234:	49 63 54 01 7c       	movslq 0x7c(%r9,%rax,1),%rdx
     239:	48 89 d0             	mov    %rdx,%rax
     23c:	49 89 56 30          	mov    %rdx,0x30(%r14)
     240:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
     247:	41 89 44 11 2c       	mov    %eax,0x2c(%r9,%rdx,1)
     24c:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     253:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 25a <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x25a>	256: R_X86_64_PC32	g_ee_main_mem-0x4
     25a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
     260:	49 8b 9e 30 01 00 00 	mov    0x130(%r14),%rbx
     267:	48 05 90 00 00 00    	add    $0x90,%rax
     26d:	49 83 86 40 01 00 00 30 	addq   $0x30,0x140(%r14)
     275:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
     27c:	48 8d 53 ff          	lea    -0x1(%rbx),%rdx
     280:	49 8b 9e 00 01 00 00 	mov    0x100(%r14),%rbx
     287:	49 89 96 30 01 00 00 	mov    %rdx,0x130(%r14)
     28e:	48 8d 4b 01          	lea    0x1(%rbx),%rcx
     292:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
     299:	48 85 d2             	test   %rdx,%rdx
     29c:	0f 84 be 0f 00 00    	je     1260 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1260>
     2a2:	89 c1                	mov    %eax,%ecx
     2a4:	49 8b b6 70 01 00 00 	mov    0x170(%r14),%rsi
     2ab:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
     2b3:	49 89 56 30          	mov    %rdx,0x30(%r14)
     2b7:	48 39 d6             	cmp    %rdx,%rsi
     2ba:	74 a4                	je     260 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     2bc:	49 8d 7c 09 68       	lea    0x68(%r9,%rcx,1),%rdi
     2c1:	4d 8d 44 09 64       	lea    0x64(%r9,%rcx,1),%r8
     2c6:	48 63 17             	movslq (%rdi),%rdx
     2c9:	49 3b b6 20 01 00 00 	cmp    0x120(%r14),%rsi
     2d0:	0f 84 fa 0b 00 00    	je     ed0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xed0>
     2d6:	81 e2 00 20 00 00    	and    $0x2000,%edx
     2dc:	89 d3                	mov    %edx,%ebx
     2de:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     2e2:	0f 84 08 ff ff ff    	je     1f0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1f0>
     2e8:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
     2ef:	49 63 30             	movslq (%r8),%rsi
     2f2:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
     2fa:	8d 53 20             	lea    0x20(%rbx),%edx
     2fd:	49 89 76 30          	mov    %rsi,0x30(%r14)
     301:	83 e2 f0             	and    $0xfffffff0,%edx
     304:	4d 8b 14 11          	mov    (%r9,%rdx,1),%r10
     308:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
     30d:	4d 89 56 40          	mov    %r10,0x40(%r14)
     311:	49 89 56 48          	mov    %rdx,0x48(%r14)
     315:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
     319:	0f 84 49 01 00 00    	je     468 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x468>
     31f:	48 89 f1             	mov    %rsi,%rcx
     322:	c5 f9 6e fa          	vmovd  %edx,%xmm7
     326:	4c 29 d1             	sub    %r10,%rcx
     329:	49 89 d2             	mov    %rdx,%r10
     32c:	48 89 cf             	mov    %rcx,%rdi
     32f:	49 c1 fa 20          	sar    $0x20,%r10
     333:	c5 f9 6e d9          	vmovd  %ecx,%xmm3
     337:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     33b:	48 c1 ff 20          	sar    $0x20,%rdi
     33f:	c4 c3 41 22 ca 01    	vpinsrd $0x1,%r10d,%xmm7,%xmm1
     345:	c4 e3 61 22 c7 01    	vpinsrd $0x1,%edi,%xmm3,%xmm0
     34b:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
     34f:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
     353:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
     358:	c4 c1 79 7f 46 30    	vmovdqa %xmm0,0x30(%r14)
     35e:	48 85 f6             	test   %rsi,%rsi
     361:	0f 85 e9 00 00 00    	jne    450 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x450>
     367:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 36e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x36e>	36a: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
     36e:	49 8b 8e 40 01 00 00 	mov    0x140(%r14),%rcx
     375:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
     37a:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
     383:	49 63 b6 f0 01 00 00 	movslq 0x1f0(%r14),%rsi
     38a:	c4 c1 7a 7e be a0 00 00 00 	vmovq  0xa0(%r14),%xmm7
     393:	48 63 12             	movslq (%rdx),%rdx
     396:	49 89 46 60          	mov    %rax,0x60(%r14)
     39a:	c4 c3 c1 22 96 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm7,%xmm2
     3a4:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
     3aa:	c4 c1 7a 7e 9e 80 00 00 00 	vmovq  0x80(%r14),%xmm3
     3b3:	49 89 96 90 01 00 00 	mov    %rdx,0x190(%r14)
     3ba:	48 89 d7             	mov    %rdx,%rdi
     3bd:	49 8b 96 00 01 00 00 	mov    0x100(%r14),%rdx
     3c4:	c4 c3 e1 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm3,%xmm1
     3ce:	49 89 4e 70          	mov    %rcx,0x70(%r14)
     3d2:	c4 e3 f9 22 c2 01    	vpinsrq $0x1,%rdx,%xmm0,%xmm0
     3d8:	49 89 56 50          	mov    %rdx,0x50(%r14)
     3dc:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     3e2:	c4 e3 d9 22 d1 01    	vpinsrq $0x1,%rcx,%xmm4,%xmm2
     3e8:	49 89 76 20          	mov    %rsi,0x20(%r14)
     3ec:	c5 fd 7f 8c 24 60 01 00 00 	vmovdqa %ymm1,0x160(%rsp)
     3f5:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
     3fb:	c5 fd 7f 84 24 40 01 00 00 	vmovdqa %ymm0,0x140(%rsp)
     404:	85 ff                	test   %edi,%edi
     406:	0f 84 30 0f 00 00    	je     133c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     40c:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     413:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     41a:	89 ff                	mov    %edi,%edi
     41c:	31 d2                	xor    %edx,%edx
     41e:	4c 01 cf             	add    %r9,%rdi
     421:	48 8d b4 24 40 01 00 00 	lea    0x140(%rsp),%rsi
     429:	c5 f8 77             	vzeroupper
     42c:	e8 00 00 00 00       	call   431 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x431>	42d: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     431:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 438 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x438>	434: R_X86_64_PC32	g_ee_main_mem-0x4
     438:	49 89 46 20          	mov    %rax,0x20(%r14)
     43c:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     443:	e9 18 fe ff ff       	jmp    260 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     448:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
     450:	c4 c1 79 7e 00       	vmovd  %xmm0,(%r8)
     455:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
     45c:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 463 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x463>	45f: R_X86_64_PC32	g_ee_main_mem-0x4
     463:	48 8d 7c 02 68       	lea    0x68(%rdx,%rax,1),%rdi
     468:	8b 07                	mov    (%rdi),%eax
     46a:	89 c2                	mov    %eax,%edx
     46c:	83 e0 bf             	and    $0xffffffbf,%eax
     46f:	83 e2 40             	and    $0x40,%edx
     472:	48 63 c8             	movslq %eax,%rcx
     475:	89 d3                	mov    %edx,%ebx
     477:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     47b:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     47f:	89 07                	mov    %eax,(%rdi)
     481:	85 d2                	test   %edx,%edx
     483:	74 25                	je     4aa <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x4aa>
     485:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
     48c:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 493 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x493>	48f: R_X86_64_PC32	g_ee_main_mem-0x4
     493:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
     498:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     49c:	48 89 ca             	mov    %rcx,%rdx
     49f:	41 8b 8e 40 01 00 00 	mov    0x140(%r14),%ecx
     4a6:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
     4aa:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 4b1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x4b1>	4ad: R_X86_64_PC32	g_ee_main_mem-0x4
     4b1:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
     4b8:	49 63 44 11 70       	movslq 0x70(%r9,%rdx,1),%rax
     4bd:	48 89 c1             	mov    %rax,%rcx
     4c0:	49 89 86 90 01 00 00 	mov    %rax,0x190(%r14)
     4c7:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     4ce:	85 c9                	test   %ecx,%ecx
     4d0:	0f 84 f6 01 00 00    	je     6cc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6cc>
     4d6:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
     4df:	48 83 e8 60          	sub    $0x60,%rax
     4e3:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     4ea:	83 e0 f0             	and    $0xfffffff0,%eax
     4ed:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     4f3:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     4fa:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
     503:	83 c0 10             	add    $0x10,%eax
     506:	83 e0 f0             	and    $0xfffffff0,%eax
     509:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     50f:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     516:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
     51f:	83 c0 20             	add    $0x20,%eax
     522:	83 e0 f0             	and    $0xfffffff0,%eax
     525:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     52b:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     532:	c4 c1 79 6f 86 00 01 00 00 	vmovdqa 0x100(%r14),%xmm0
     53b:	83 c0 30             	add    $0x30,%eax
     53e:	83 e0 f0             	and    $0xfffffff0,%eax
     541:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     547:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     54e:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
     557:	83 c0 40             	add    $0x40,%eax
     55a:	83 e0 f0             	and    $0xfffffff0,%eax
     55d:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     563:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
     56a:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
     573:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
     57a:	49 89 46 40          	mov    %rax,0x40(%r14)
     57e:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     585:	49 89 46 50          	mov    %rax,0x50(%r14)
     589:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     590:	49 89 46 60          	mov    %rax,0x60(%r14)
     594:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     59b:	83 c0 50             	add    $0x50,%eax
     59e:	83 e0 f0             	and    $0xfffffff0,%eax
     5a1:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     5a7:	c4 c1 7a 7e 76 60    	vmovq  0x60(%r14),%xmm6
     5ad:	c4 c1 7a 7e ae a0 00 00 00 	vmovq  0xa0(%r14),%xmm5
     5b6:	c4 c3 d1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm5,%xmm1
     5c0:	c4 c3 c9 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm6,%xmm2
     5c7:	c4 c1 7a 7e ae 80 00 00 00 	vmovq  0x80(%r14),%xmm5
     5d0:	c4 c1 7a 7e 7e 40    	vmovq  0x40(%r14),%xmm7
     5d6:	c4 c3 d1 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm5,%xmm0
     5e0:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     5e6:	c4 c3 c1 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm7,%xmm1
     5ed:	c5 fd 7f 44 24 60    	vmovdqa %ymm0,0x60(%rsp)
     5f3:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     5f9:	c5 fd 7f 4c 24 40    	vmovdqa %ymm1,0x40(%rsp)
     5ff:	85 ff                	test   %edi,%edi
     601:	0f 84 35 0d 00 00    	je     133c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     607:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     60e:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     615:	4c 01 cf             	add    %r9,%rdi
     618:	31 d2                	xor    %edx,%edx
     61a:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
     61f:	c5 f8 77             	vzeroupper
     622:	e8 00 00 00 00       	call   627 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x627>	623: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     627:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 62e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x62e>	62a: R_X86_64_PC32	g_ee_main_mem-0x4
     62e:	49 89 46 20          	mov    %rax,0x20(%r14)
     632:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     639:	48 89 c2             	mov    %rax,%rdx
     63c:	8d 48 10             	lea    0x10(%rax),%ecx
     63f:	83 e2 f0             	and    $0xfffffff0,%edx
     642:	83 e1 f0             	and    $0xfffffff0,%ecx
     645:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
     64b:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
     654:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
     658:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
     65d:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
     664:	8d 48 20             	lea    0x20(%rax),%ecx
     667:	83 e1 f0             	and    $0xfffffff0,%ecx
     66a:	49 89 96 50 01 00 00 	mov    %rdx,0x150(%r14)
     671:	89 d2                	mov    %edx,%edx
     673:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     679:	8d 48 30             	lea    0x30(%rax),%ecx
     67c:	83 e1 f0             	and    $0xfffffff0,%ecx
     67f:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
     688:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     68e:	8d 48 40             	lea    0x40(%rax),%ecx
     691:	83 e1 f0             	and    $0xfffffff0,%ecx
     694:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
     69d:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     6a3:	8d 48 50             	lea    0x50(%rax),%ecx
     6a6:	48 83 c0 60          	add    $0x60,%rax
     6aa:	83 e1 f0             	and    $0xfffffff0,%ecx
     6ad:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
     6b6:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     6bc:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     6c3:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
     6cc:	49 63 74 11 78       	movslq 0x78(%r9,%rdx,1),%rsi
     6d1:	83 c0 20             	add    $0x20,%eax
     6d4:	83 e0 f0             	and    $0xfffffff0,%eax
     6d7:	49 89 76 50          	mov    %rsi,0x50(%r14)
     6db:	48 89 f1             	mov    %rsi,%rcx
     6de:	49 8d 74 11 74       	lea    0x74(%r9,%rdx,1),%rsi
     6e3:	48 63 16             	movslq (%rsi),%rdx
     6e6:	49 89 56 30          	mov    %rdx,0x30(%r14)
     6ea:	49 8b 3c 01          	mov    (%r9,%rax,1),%rdi
     6ee:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
     6f3:	49 89 7e 40          	mov    %rdi,0x40(%r14)
     6f7:	49 89 46 48          	mov    %rax,0x48(%r14)
     6fb:	85 c9                	test   %ecx,%ecx
     6fd:	74 0f                	je     70e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x70e>
     6ff:	48 29 fa             	sub    %rdi,%rdx
     702:	49 89 56 30          	mov    %rdx,0x30(%r14)
     706:	89 16                	mov    %edx,(%rsi)
     708:	0f 88 32 09 00 00    	js     1040 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1040>
     70e:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
     715:	f6 c2 0f             	test   $0xf,%dl
     718:	0f 85 a0 0c 00 00    	jne    13be <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13be>
     71e:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 725 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x725>	721: R_X86_64_PC32	g_ee_main_mem-0x4
     725:	41 8b b6 50 01 00 00 	mov    0x150(%r14),%esi
     72c:	4c 8b 4c 10 18       	mov    0x18(%rax,%rdx,1),%r9
     731:	48 8b 5c 10 10       	mov    0x10(%rax,%rdx,1),%rbx
     736:	c5 fa 7e 1c 10       	vmovq  (%rax,%rdx,1),%xmm3
     73b:	48 8b 4c 10 08       	mov    0x8(%rax,%rdx,1),%rcx
     740:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
     745:	4c 89 4c 24 28       	mov    %r9,0x28(%rsp)
     74a:	40 f6 c6 0f          	test   $0xf,%sil
     74e:	0f 85 4b 0c 00 00    	jne    139f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x139f>
     754:	c5 78 10 44 10 20    	vmovups 0x20(%rax,%rdx,1),%xmm8
     75a:	4d 8b 96 88 03 00 00 	mov    0x388(%r14),%r10
     761:	c4 e3 e1 22 d9 01    	vpinsrq $0x1,%rcx,%xmm3,%xmm3
     767:	48 8b 54 30 10       	mov    0x10(%rax,%rsi,1),%rdx
     76c:	c5 fa 6f 44 30 40    	vmovdqu 0x40(%rax,%rsi,1),%xmm0
     772:	c4 41 79 6e ca       	vmovd  %r10d,%xmm9
     777:	48 8b 4c 30 18       	mov    0x18(%rax,%rsi,1),%rcx
     77c:	c5 7a 7e 54 30 30    	vmovq  0x30(%rax,%rsi,1),%xmm10
     782:	c4 e1 f9 6e ca       	vmovq  %rdx,%xmm1
     787:	c5 f9 6f e0          	vmovdqa %xmm0,%xmm4
     78b:	c5 f9 6f e8          	vmovdqa %xmm0,%xmm5
     78f:	c4 c1 30 c6 d1 00    	vshufps $0x0,%xmm9,%xmm9,%xmm2
     795:	c5 f0 c6 c9 55       	vshufps $0x55,%xmm1,%xmm1,%xmm1
     79a:	c5 79 6f f1          	vmovdqa %xmm1,%xmm14
     79e:	c4 c1 7a 12 c9       	vmovsldup %xmm9,%xmm1
     7a3:	48 89 cf             	mov    %rcx,%rdi
     7a6:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
     7ab:	c5 f9 6f f4          	vmovdqa %xmm4,%xmm6
     7af:	c5 f9 6e e2          	vmovd  %edx,%xmm4
     7b3:	c5 79 6e d9          	vmovd  %ecx,%xmm11
     7b7:	c5 e8 59 d0          	vmulps %xmm0,%xmm2,%xmm2
     7bb:	c5 f8 14 c6          	vunpcklps %xmm6,%xmm0,%xmm0
     7bf:	4c 8b 7c 30 38       	mov    0x38(%rax,%rsi,1),%r15
     7c4:	48 8b 5c 30 20       	mov    0x20(%rax,%rsi,1),%rbx
     7c9:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     7cd:	4c 8b 5c 30 28       	mov    0x28(%rax,%rsi,1),%r11
     7d2:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
     7d9:	48 ba 00 00 00 00 ff ff ff ff 	movabs $0xffffffff00000000,%rdx
     7e3:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     7e7:	48 21 d7             	and    %rdx,%rdi
     7ea:	c4 c3 a9 22 ff 01    	vpinsrq $0x1,%r15,%xmm10,%xmm7
     7f0:	c5 f8 59 c1          	vmulps %xmm1,%xmm0,%xmm0
     7f4:	c4 c1 58 14 ce       	vunpcklps %xmm14,%xmm4,%xmm1
     7f9:	48 89 74 24 38       	mov    %rsi,0x38(%rsp)
     7fe:	89 f6                	mov    %esi,%esi
     800:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     804:	48 89 74 24 30       	mov    %rsi,0x30(%rsp)
     809:	48 63 74 30 60       	movslq 0x60(%rax,%rsi,1),%rsi
     80e:	49 89 f0             	mov    %rsi,%r8
     811:	41 89 b6 00 02 00 00 	mov    %esi,0x200(%r14)
     818:	49 89 76 30          	mov    %rsi,0x30(%r14)
     81c:	49 8b b6 80 03 00 00 	mov    0x380(%r14),%rsi
     823:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     827:	c5 f8 58 c1          	vaddps %xmm1,%xmm0,%xmm0
     82b:	c5 e8 15 ca          	vunpckhps %xmm2,%xmm2,%xmm1
     82f:	c4 c1 72 58 cb       	vaddss %xmm11,%xmm1,%xmm1
     834:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
     839:	c4 62 79 35 f9       	vpmovzxdq %xmm1,%xmm15
     83e:	c4 61 f9 7e fa       	vmovq  %xmm15,%rdx
     843:	c5 79 d6 7c 24 18    	vmovq  %xmm15,0x18(%rsp)
     849:	48 09 d7             	or     %rdx,%rdi
     84c:	49 89 fd             	mov    %rdi,%r13
     84f:	45 85 c0             	test   %r8d,%r8d
     852:	0f 85 30 07 00 00    	jne    f88 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf88>
     858:	c5 7a 16 c8          	vmovshdup %xmm0,%xmm9
     85c:	c5 f8 28 e8          	vmovaps %xmm0,%xmm5
     860:	48 89 df             	mov    %rbx,%rdi
     863:	48 c1 e9 20          	shr    $0x20,%rcx
     867:	c4 c1 50 14 e9       	vunpcklps %xmm9,%xmm5,%xmm5
     86c:	c4 e1 f9 6e f6       	vmovq  %rsi,%xmm6
     871:	48 c1 ef 20          	shr    $0x20,%rdi
     875:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
     879:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
     87e:	c5 f9 6f c6          	vmovdqa %xmm6,%xmm0
     882:	c5 79 6e ef          	vmovd  %edi,%xmm13
     886:	4c 89 df             	mov    %r11,%rdi
     889:	c5 f0 14 cc          	vunpcklps %xmm4,%xmm1,%xmm1
     88d:	49 c1 e9 20          	shr    $0x20,%r9
     891:	48 c1 ef 20          	shr    $0x20,%rdi
     895:	c5 d0 16 e9          	vmovlhps %xmm1,%xmm5,%xmm5
     899:	c4 c1 79 6e e3       	vmovd  %r11d,%xmm4
     89e:	c5 f9 6e cb          	vmovd  %ebx,%xmm1
     8a2:	c5 79 6e ff          	vmovd  %edi,%xmm15
     8a6:	c4 c1 70 14 cd       	vunpcklps %xmm13,%xmm1,%xmm1
     8ab:	c5 f8 c6 c0 00       	vshufps $0x0,%xmm0,%xmm0,%xmm0
     8b0:	c4 e3 7d 18 c0 01    	vinsertf128 $0x1,%xmm0,%ymm0,%ymm0
     8b6:	c4 c1 58 14 e7       	vunpcklps %xmm15,%xmm4,%xmm4
     8bb:	c5 c8 c6 f6 00       	vshufps $0x0,%xmm6,%xmm6,%xmm6
     8c0:	48 8b 7c 24 28       	mov    0x28(%rsp),%rdi
     8c5:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
     8ca:	c5 f0 16 cc          	vmovlhps %xmm4,%xmm1,%xmm1
     8ce:	c4 e3 55 18 c9 01    	vinsertf128 $0x1,%xmm1,%ymm5,%ymm1
     8d4:	4d 89 a6 30 03 00 00 	mov    %r12,0x330(%r14)
     8db:	c5 c8 59 ff          	vmulps %xmm7,%xmm6,%xmm7
     8df:	89 fa                	mov    %edi,%edx
     8e1:	49 89 b6 10 03 00 00 	mov    %rsi,0x310(%r14)
     8e8:	c5 fc 59 c1          	vmulps %ymm1,%ymm0,%ymm0
     8ec:	4d 89 ae 38 03 00 00 	mov    %r13,0x338(%r14)
     8f3:	c5 c8 59 f5          	vmulps %xmm5,%xmm6,%xmm6
     8f7:	49 89 9e 40 03 00 00 	mov    %rbx,0x340(%r14)
     8fe:	4d 89 9e 48 03 00 00 	mov    %r11,0x348(%r14)
     905:	4d 89 be 58 03 00 00 	mov    %r15,0x358(%r14)
     90c:	c4 41 79 d6 96 50 03 00 00 	vmovq  %xmm10,0x350(%r14)
     915:	c5 38 58 c7          	vaddps %xmm7,%xmm8,%xmm8
     919:	c4 c1 78 29 96 60 03 00 00 	vmovaps %xmm2,0x360(%r14)
     922:	c4 e3 7d 19 c1 01    	vextractf128 $0x1,%ymm0,%xmm1
     928:	c5 c8 58 f3          	vaddps %xmm3,%xmm6,%xmm6
     92c:	c4 c1 79 6e d9       	vmovd  %r9d,%xmm3
     931:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
     936:	c5 f2 58 db          	vaddss %xmm3,%xmm1,%xmm3
     93a:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
     93e:	c4 c1 70 5f c8       	vmaxps %xmm8,%xmm1,%xmm1
     943:	c4 c1 79 7f b6 00 03 00 00 	vmovdqa %xmm6,0x300(%r14)
     94c:	c5 f9 7e d9          	vmovd  %xmm3,%ecx
     950:	c4 c1 79 7f 8e 20 03 00 00 	vmovdqa %xmm1,0x320(%r14)
     959:	48 c1 e1 20          	shl    $0x20,%rcx
     95d:	48 09 ca             	or     %rcx,%rdx
     960:	49 89 96 18 03 00 00 	mov    %rdx,0x318(%r14)
     967:	45 85 c0             	test   %r8d,%r8d
     96a:	74 29                	je     995 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x995>
     96c:	c5 fa 10 74 24 14    	vmovss 0x14(%rsp),%xmm6
     972:	c5 fa 10 5c 24 08    	vmovss 0x8(%rsp),%xmm3
     978:	c4 e3 49 21 54 24 10 10 	vinsertps $0x10,0x10(%rsp),%xmm6,%xmm2
     980:	c4 e3 61 21 4c 24 0c 10 	vinsertps $0x10,0xc(%rsp),%xmm3,%xmm1
     988:	c5 f0 16 ca          	vmovlhps %xmm2,%xmm1,%xmm1
     98c:	c4 c1 78 29 8e 70 03 00 00 	vmovaps %xmm1,0x370(%r14)
     995:	c4 c1 7c 11 86 90 03 00 00 	vmovups %ymm0,0x390(%r14)
     99e:	c4 c1 78 29 be b0 03 00 00 	vmovaps %xmm7,0x3b0(%r14)
     9a7:	f6 44 24 38 0f       	testb  $0xf,0x38(%rsp)
     9ac:	0f 85 ac 09 00 00    	jne    135e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     9b2:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
     9b7:	c5 f8 11 6c 18 10    	vmovups %xmm5,0x10(%rax,%rbx,1)
     9bd:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     9c4:	f6 c2 0f             	test   $0xf,%dl
     9c7:	0f 85 91 09 00 00    	jne    135e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     9cd:	c4 c1 79 6f 86 00 03 00 00 	vmovdqa 0x300(%r14),%xmm0
     9d6:	89 d2                	mov    %edx,%edx
     9d8:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
     9dd:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     9e4:	f6 c2 0f             	test   $0xf,%dl
     9e7:	0f 85 71 09 00 00    	jne    135e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     9ed:	c4 c1 79 6f 86 10 03 00 00 	vmovdqa 0x310(%r14),%xmm0
     9f6:	89 d2                	mov    %edx,%edx
     9f8:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
     9fe:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     a05:	f6 c2 0f             	test   $0xf,%dl
     a08:	0f 85 50 09 00 00    	jne    135e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     a0e:	c4 c1 79 6f 86 20 03 00 00 	vmovdqa 0x320(%r14),%xmm0
     a17:	89 d2                	mov    %edx,%edx
     a19:	c5 fa 10 2d 00 00 00 00 	vmovss 0x0(%rip),%xmm5        # a21 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa21>	a1d: R_X86_64_PC32	.LC11-0x4
     a21:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
     a27:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     a2e:	49 8b 8e 10 01 00 00 	mov    0x110(%r14),%rcx
     a35:	49 89 56 40          	mov    %rdx,0x40(%r14)
     a39:	89 d2                	mov    %edx,%edx
     a3b:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     a3f:	8b 74 10 10          	mov    0x10(%rax,%rdx,1),%esi
     a43:	89 c9                	mov    %ecx,%ecx
     a45:	41 89 b6 00 02 00 00 	mov    %esi,0x200(%r14)
     a4c:	8b 7c 10 14          	mov    0x14(%rax,%rdx,1),%edi
     a50:	41 89 be 04 02 00 00 	mov    %edi,0x204(%r14)
     a57:	8b 54 10 18          	mov    0x18(%rax,%rdx,1),%edx
     a5b:	41 89 96 0c 02 00 00 	mov    %edx,0x20c(%r14)
     a62:	89 34 08             	mov    %esi,(%rax,%rcx,1)
     a65:	41 8b 8e 04 02 00 00 	mov    0x204(%r14),%ecx
     a6c:	41 8b 46 30          	mov    0x30(%r14),%eax
     a70:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # a77 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa77>	a73: R_X86_64_PC32	g_ee_main_mem-0x4
     a77:	89 4c 02 04          	mov    %ecx,0x4(%rdx,%rax,1)
     a7b:	41 8b 8e 0c 02 00 00 	mov    0x20c(%r14),%ecx
     a82:	41 8b 46 30          	mov    0x30(%r14),%eax
     a86:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # a8d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa8d>	a89: R_X86_64_PC32	g_ee_main_mem-0x4
     a8d:	89 4c 02 08          	mov    %ecx,0x8(%rdx,%rax,1)
     a91:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # a98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa98>	a94: R_X86_64_PC32	g_ee_main_mem-0x4
     a98:	c4 c1 7a 10 86 0c 02 00 00 	vmovss 0x20c(%r14),%xmm0
     aa1:	41 8b 46 30          	mov    0x30(%r14),%eax
     aa5:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
     aa9:	c4 c1 7a 11 86 0c 02 00 00 	vmovss %xmm0,0x20c(%r14)
     ab2:	c5 d2 5c c8          	vsubss %xmm0,%xmm5,%xmm1
     ab6:	c4 c1 7a 10 86 04 02 00 00 	vmovss 0x204(%r14),%xmm0
     abf:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
     ac3:	c5 f2 5c c0          	vsubss %xmm0,%xmm1,%xmm0
     ac7:	c5 f8 14 c9          	vunpcklps %xmm1,%xmm0,%xmm1
     acb:	c4 c1 78 13 8e 04 02 00 00 	vmovlps %xmm1,0x204(%r14)
     ad4:	c4 c1 7a 10 8e 00 02 00 00 	vmovss 0x200(%r14),%xmm1
     add:	c5 f2 59 c9          	vmulss %xmm1,%xmm1,%xmm1
     ae1:	c5 fa 5c c1          	vsubss %xmm1,%xmm0,%xmm0
     ae5:	c5 f8 54 05 00 00 00 00 	vandps 0x0(%rip),%xmm0,%xmm0        # aed <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xaed>	ae9: R_X86_64_PC32	.LC14-0x4
     aed:	c5 fa 51 c0          	vsqrtss %xmm0,%xmm0,%xmm0
     af1:	c4 c1 7a 11 86 00 02 00 00 	vmovss %xmm0,0x200(%r14)
     afa:	c5 fa 11 44 02 0c    	vmovss %xmm0,0xc(%rdx,%rax,1)
     b00:	49 63 86 00 02 00 00 	movslq 0x200(%r14),%rax
     b07:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # b0e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb0e>	b0a: R_X86_64_PC32	g_ee_main_mem-0x4
     b0e:	49 89 46 40          	mov    %rax,0x40(%r14)
     b12:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # b19 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb19>	b15: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
     b19:	48 63 10             	movslq (%rax),%rdx
     b1c:	89 d0                	mov    %edx,%eax
     b1e:	49 89 56 30          	mov    %rdx,0x30(%r14)
     b22:	41 8b 04 01          	mov    (%r9,%rax,1),%eax
     b26:	41 89 86 00 02 00 00 	mov    %eax,0x200(%r14)
     b2d:	0f b6 c0             	movzbl %al,%eax
     b30:	48 83 e8 0a          	sub    $0xa,%rax
     b34:	49 89 46 30          	mov    %rax,0x30(%r14)
     b38:	0f 88 c8 00 00 00    	js     c06 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc06>
     b3e:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     b45:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # b4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb4c>	b48: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
     b4c:	c4 c1 7a 7e 96 10 01 00 00 	vmovq  0x110(%r14),%xmm2
     b55:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
     b5c:	c4 c1 7a 7e b6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm6
     b65:	48 83 c0 50          	add    $0x50,%rax
     b69:	48 63 09             	movslq (%rcx),%rcx
     b6c:	c4 e1 f9 6e e8       	vmovq  %rax,%xmm5
     b71:	c4 c3 d1 22 46 70 01 	vpinsrq $0x1,0x70(%r14),%xmm5,%xmm0
     b78:	c5 e9 6c ca          	vpunpcklqdq %xmm2,%xmm2,%xmm1
     b7c:	c4 c1 7a 7e be 80 00 00 00 	vmovq  0x80(%r14),%xmm7
     b85:	c4 c3 c9 22 9e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm6,%xmm3
     b8f:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
     b96:	48 89 cf             	mov    %rcx,%rdi
     b99:	c4 e3 75 18 c8 01    	vinsertf128 $0x1,%xmm0,%ymm1,%ymm1
     b9f:	49 89 46 60          	mov    %rax,0x60(%r14)
     ba3:	c4 c3 c1 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm7,%xmm0
     bad:	49 89 56 20          	mov    %rdx,0x20(%r14)
     bb1:	c4 e3 7d 18 c3 01    	vinsertf128 $0x1,%xmm3,%ymm0,%ymm0
     bb7:	c4 c1 79 d6 56 40    	vmovq  %xmm2,0x40(%r14)
     bbd:	c4 c1 79 d6 56 50    	vmovq  %xmm2,0x50(%r14)
     bc3:	c5 fd 7f 8c 24 c0 00 00 00 	vmovdqa %ymm1,0xc0(%rsp)
     bcc:	c5 fd 7f 84 24 e0 00 00 00 	vmovdqa %ymm0,0xe0(%rsp)
     bd5:	85 c9                	test   %ecx,%ecx
     bd7:	0f 84 5f 07 00 00    	je     133c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     bdd:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     be4:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     beb:	89 ff                	mov    %edi,%edi
     bed:	31 d2                	xor    %edx,%edx
     bef:	4c 01 cf             	add    %r9,%rdi
     bf2:	48 8d b4 24 c0 00 00 00 	lea    0xc0(%rsp),%rsi
     bfa:	c5 f8 77             	vzeroupper
     bfd:	e8 00 00 00 00       	call   c02 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc02>	bfe: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     c02:	49 89 46 20          	mov    %rax,0x20(%r14)
     c06:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # c0d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc0d>	c09: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
     c0d:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
     c14:	c4 c1 7a 7e be a0 00 00 00 	vmovq  0xa0(%r14),%xmm7
     c1d:	c4 c1 7a 7e ae 80 00 00 00 	vmovq  0x80(%r14),%xmm5
     c26:	c4 c3 c1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm7,%xmm1
     c30:	48 63 00             	movslq (%rax),%rax
     c33:	49 89 56 20          	mov    %rdx,0x20(%r14)
     c37:	c4 c3 d1 22 96 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm5,%xmm2
     c41:	c4 c1 7a 7e 86 10 01 00 00 	vmovq  0x110(%r14),%xmm0
     c4a:	49 89 86 90 01 00 00 	mov    %rax,0x190(%r14)
     c51:	48 89 c7             	mov    %rax,%rdi
     c54:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     c5b:	c4 e3 6d 18 d1 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm2
     c61:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
     c67:	48 83 c0 50          	add    $0x50,%rax
     c6b:	c4 c1 79 d6 46 50    	vmovq  %xmm0,0x50(%r14)
     c71:	c5 f9 6c c0          	vpunpcklqdq %xmm0,%xmm0,%xmm0
     c75:	c4 e1 f9 6e f0       	vmovq  %rax,%xmm6
     c7a:	c4 c3 c9 22 4e 70 01 	vpinsrq $0x1,0x70(%r14),%xmm6,%xmm1
     c81:	49 89 46 60          	mov    %rax,0x60(%r14)
     c85:	c5 fd 7f 94 24 20 01 00 00 	vmovdqa %ymm2,0x120(%rsp)
     c8e:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     c94:	c5 fd 7f 84 24 00 01 00 00 	vmovdqa %ymm0,0x100(%rsp)
     c9d:	85 ff                	test   %edi,%edi
     c9f:	0f 84 97 06 00 00    	je     133c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     ca5:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # cac <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcac>	ca8: R_X86_64_PC32	g_ee_main_mem-0x4
     cac:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     cb3:	89 ff                	mov    %edi,%edi
     cb5:	31 d2                	xor    %edx,%edx
     cb7:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     cbe:	48 8d b4 24 00 01 00 00 	lea    0x100(%rsp),%rsi
     cc6:	4c 01 cf             	add    %r9,%rdi
     cc9:	c5 f8 77             	vzeroupper
     ccc:	e8 00 00 00 00       	call   cd1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcd1>	ccd: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     cd1:	49 8b 96 10 01 00 00 	mov    0x110(%r14),%rdx
     cd8:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
     cdc:	49 89 46 20          	mov    %rax,0x20(%r14)
     ce0:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # ce7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xce7>	ce3: R_X86_64_PC32	g_ee_main_mem-0x4
     ce7:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     cee:	89 d1                	mov    %edx,%ecx
     cf0:	49 89 56 30          	mov    %rdx,0x30(%r14)
     cf4:	49 89 46 40          	mov    %rax,0x40(%r14)
     cf8:	c4 c1 79 6e 44 09 0c 	vmovd  0xc(%r9,%rcx,1),%xmm0
     cff:	41 c7 86 04 02 00 00 00 00 00 00 	movl   $0x0,0x204(%r14)
     d0a:	c4 c1 79 7e 86 00 02 00 00 	vmovd  %xmm0,0x200(%r14)
     d13:	c5 f8 2f c8          	vcomiss %xmm0,%xmm1
     d17:	0f 87 c3 01 00 00    	ja     ee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     d1d:	a8 0f                	test   $0xf,%al
     d1f:	0f 85 5b 06 00 00    	jne    1380 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     d25:	89 c0                	mov    %eax,%eax
     d27:	83 e2 0f             	and    $0xf,%edx
     d2a:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
     d2f:	48 8b 07             	mov    (%rdi),%rax
     d32:	48 8b 77 08          	mov    0x8(%rdi),%rsi
     d36:	49 89 86 90 02 00 00 	mov    %rax,0x290(%r14)
     d3d:	49 89 b6 98 02 00 00 	mov    %rsi,0x298(%r14)
     d44:	0f 85 36 06 00 00    	jne    1380 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     d4a:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
     d4e:	49 8b 44 09 08       	mov    0x8(%r9,%rcx,1),%rax
     d53:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
     d57:	48 c1 ee 20          	shr    $0x20,%rsi
     d5b:	49 89 96 a0 02 00 00 	mov    %rdx,0x2a0(%r14)
     d62:	c5 f9 6e c2          	vmovd  %edx,%xmm0
     d66:	48 c1 ea 20          	shr    $0x20,%rdx
     d6a:	c5 f9 6e fa          	vmovd  %edx,%xmm7
     d6e:	49 89 86 a8 02 00 00 	mov    %rax,0x2a8(%r14)
     d75:	c5 f8 14 c7          	vunpcklps %xmm7,%xmm0,%xmm0
     d79:	c5 f9 6e fe          	vmovd  %esi,%xmm7
     d7d:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     d81:	c5 f8 58 c2          	vaddps %xmm2,%xmm0,%xmm0
     d85:	c5 f9 6e d0          	vmovd  %eax,%xmm2
     d89:	c5 ea 58 c9          	vaddss %xmm1,%xmm2,%xmm1
     d8d:	c4 c1 78 13 86 90 02 00 00 	vmovlps %xmm0,0x290(%r14)
     d96:	c4 c1 7a 11 8e 98 02 00 00 	vmovss %xmm1,0x298(%r14)
     d9f:	c5 f0 14 cf          	vunpcklps %xmm7,%xmm1,%xmm1
     da3:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
     da7:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
     dab:	49 8b 86 90 02 00 00 	mov    0x290(%r14),%rax
     db2:	49 8b 96 98 02 00 00 	mov    0x298(%r14),%rdx
     db9:	c4 c1 78 28 86 20 03 00 00 	vmovaps 0x320(%r14),%xmm0
     dc2:	49 89 46 40          	mov    %rax,0x40(%r14)
     dc6:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     dcd:	49 89 56 48          	mov    %rdx,0x48(%r14)
     dd1:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     dd7:	89 c2                	mov    %eax,%edx
     dd9:	49 63 4c 11 68       	movslq 0x68(%r9,%rdx,1),%rcx
     dde:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     de2:	48 89 ca             	mov    %rcx,%rdx
     de5:	83 e1 04             	and    $0x4,%ecx
     de8:	89 cb                	mov    %ecx,%ebx
     dea:	49 89 5e 50          	mov    %rbx,0x50(%r14)
     dee:	f6 c2 02             	test   $0x2,%dl
     df1:	74 33                	je     e26 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe26>
     df3:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
     df8:	41 c7 46 60 00 00 00 00 	movl   $0x0,0x60(%r14)
     e00:	c4 c3 79 16 46 64 02 	vpextrd $0x2,%xmm0,0x64(%r14)
     e07:	c4 c3 79 16 46 6c 03 	vpextrd $0x3,%xmm0,0x6c(%r14)
     e0e:	41 c7 46 68 00 00 00 00 	movl   $0x0,0x68(%r14)
     e16:	48 85 f6             	test   %rsi,%rsi
     e19:	75 0b                	jne    e26 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe26>
     e1b:	49 83 7e 60 00       	cmpq   $0x0,0x60(%r14)
     e20:	0f 84 41 f5 ff ff    	je     367 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     e26:	83 e2 01             	and    $0x1,%edx
     e29:	89 d3                	mov    %edx,%ebx
     e2b:	49 89 5e 40          	mov    %rbx,0x40(%r14)
     e2f:	85 c9                	test   %ecx,%ecx
     e31:	74 29                	je     e5c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe5c>
     e33:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
     e3b:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     e42:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
     e49:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     e51:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
     e56:	0f 8e 0b f5 ff ff    	jle    367 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     e5c:	85 d2                	test   %edx,%edx
     e5e:	0f 84 fc f3 ff ff    	je     260 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     e64:	c4 c1 78 28 86 00 03 00 00 	vmovaps 0x300(%r14),%xmm0
     e6d:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     e73:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     e7a:	c4 c1 78 28 86 10 03 00 00 	vmovaps 0x310(%r14),%xmm0
     e83:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     e8b:	49 8b 56 30          	mov    0x30(%r14),%rdx
     e8f:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     e95:	48 85 d2             	test   %rdx,%rdx
     e98:	0f 88 c9 f4 ff ff    	js     367 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     e9e:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
     ea6:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     ead:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
     eb4:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     ebc:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
     ec1:	0f 88 a0 f4 ff ff    	js     367 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     ec7:	e9 94 f3 ff ff       	jmp    260 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     ecc:	0f 1f 40 00          	nopl   0x0(%rax)
     ed0:	49 89 56 30          	mov    %rdx,0x30(%r14)
     ed4:	e9 0f f4 ff ff       	jmp    2e8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2e8>
     ed9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
     ee0:	a8 0f                	test   $0xf,%al
     ee2:	0f 85 98 04 00 00    	jne    1380 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     ee8:	89 c0                	mov    %eax,%eax
     eea:	83 e2 0f             	and    $0xf,%edx
     eed:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
     ef2:	48 8b 07             	mov    (%rdi),%rax
     ef5:	48 8b 77 08          	mov    0x8(%rdi),%rsi
     ef9:	49 89 86 90 02 00 00 	mov    %rax,0x290(%r14)
     f00:	49 89 b6 98 02 00 00 	mov    %rsi,0x298(%r14)
     f07:	0f 85 73 04 00 00    	jne    1380 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     f0d:	49 8b 04 09          	mov    (%r9,%rcx,1),%rax
     f11:	49 8b 54 09 08       	mov    0x8(%r9,%rcx,1),%rdx
     f16:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
     f1a:	48 c1 ee 20          	shr    $0x20,%rsi
     f1e:	c5 f9 6e ee          	vmovd  %esi,%xmm5
     f22:	49 89 86 a0 02 00 00 	mov    %rax,0x2a0(%r14)
     f29:	c5 f9 6e d0          	vmovd  %eax,%xmm2
     f2d:	48 c1 e8 20          	shr    $0x20,%rax
     f31:	c5 f9 6e d8          	vmovd  %eax,%xmm3
     f35:	49 89 96 a8 02 00 00 	mov    %rdx,0x2a8(%r14)
     f3c:	c5 e8 14 d3          	vunpcklps %xmm3,%xmm2,%xmm2
     f40:	c5 fa 7e d2          	vmovq  %xmm2,%xmm2
     f44:	c5 f8 5c c2          	vsubps %xmm2,%xmm0,%xmm0
     f48:	c5 f9 6e d2          	vmovd  %edx,%xmm2
     f4c:	c5 f2 5c ca          	vsubss %xmm2,%xmm1,%xmm1
     f50:	c4 c1 78 13 86 90 02 00 00 	vmovlps %xmm0,0x290(%r14)
     f59:	c4 c1 7a 11 8e 98 02 00 00 	vmovss %xmm1,0x298(%r14)
     f62:	c5 f0 14 cd          	vunpcklps %xmm5,%xmm1,%xmm1
     f66:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
     f6a:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
     f6e:	49 8b 86 90 02 00 00 	mov    0x290(%r14),%rax
     f75:	49 8b 96 98 02 00 00 	mov    0x298(%r14),%rdx
     f7c:	e9 38 fe ff ff       	jmp    db9 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb9>
     f81:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
     f88:	49 8b 7e 30          	mov    0x30(%r14),%rdi
     f8c:	49 c1 ea 20          	shr    $0x20,%r10
     f90:	49 8b 56 38          	mov    0x38(%r14),%rdx
     f94:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     f98:	c5 b2 59 ed          	vmulss %xmm5,%xmm9,%xmm5
     f9c:	c4 41 79 6e da       	vmovd  %r10d,%xmm11
     fa1:	49 ba 00 00 00 00 ff ff ff ff 	movabs $0xffffffff00000000,%r10
     fab:	c5 32 59 ce          	vmulss %xmm6,%xmm9,%xmm9
     faf:	c5 79 6e e7          	vmovd  %edi,%xmm12
     fb3:	48 c1 ef 20          	shr    $0x20,%rdi
     fb7:	c4 41 1a 59 fb       	vmulss %xmm11,%xmm12,%xmm15
     fbc:	c5 d2 58 ec          	vaddss %xmm4,%xmm5,%xmm5
     fc0:	c4 41 32 58 ce       	vaddss %xmm14,%xmm9,%xmm9
     fc5:	c5 7a 11 7c 24 08    	vmovss %xmm15,0x8(%rsp)
     fcb:	c5 79 6e ff          	vmovd  %edi,%xmm15
     fcf:	c4 41 22 59 ef       	vmulss %xmm15,%xmm11,%xmm13
     fd4:	c5 7a 10 3d 00 00 00 00 	vmovss 0x0(%rip),%xmm15        # fdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xfdc>	fd8: R_X86_64_PC32	.LC11-0x4
     fdc:	c4 41 02 5c e4       	vsubss %xmm12,%xmm15,%xmm12
     fe1:	c4 41 1a 59 e3       	vmulss %xmm11,%xmm12,%xmm12
     fe6:	c5 7a 11 6c 24 0c    	vmovss %xmm13,0xc(%rsp)
     fec:	c5 79 6e ea          	vmovd  %edx,%xmm13
     ff0:	4c 89 ea             	mov    %r13,%rdx
     ff3:	c4 41 22 59 ed       	vmulss %xmm13,%xmm11,%xmm13
     ff8:	4c 21 d2             	and    %r10,%rdx
     ffb:	c4 41 02 5c e4       	vsubss %xmm12,%xmm15,%xmm12
    1000:	c5 7a 11 6c 24 14    	vmovss %xmm13,0x14(%rsp)
    1006:	c4 c1 72 59 cc       	vmulss %xmm12,%xmm1,%xmm1
    100b:	c4 c1 7a 12 f4       	vmovsldup %xmm12,%xmm6
    1010:	c5 7a 11 64 24 10    	vmovss %xmm12,0x10(%rsp)
    1016:	c4 c1 52 59 ec       	vmulss %xmm12,%xmm5,%xmm5
    101b:	c4 41 32 59 cc       	vmulss %xmm12,%xmm9,%xmm9
    1020:	c5 fa 7e f6          	vmovq  %xmm6,%xmm6
    1024:	c5 c8 59 c0          	vmulps %xmm0,%xmm6,%xmm0
    1028:	c5 f9 7e cf          	vmovd  %xmm1,%edi
    102c:	48 09 fa             	or     %rdi,%rdx
    102f:	49 89 d5             	mov    %rdx,%r13
    1032:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
    1037:	e9 24 f8 ff ff       	jmp    860 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x860>
    103c:	0f 1f 40 00          	nopl   0x0(%rax)
    1040:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    1047:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 104e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x104e>	104a: R_X86_64_PC32	g_ee_main_mem-0x4
    104e:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
    1057:	48 83 e8 60          	sub    $0x60,%rax
    105b:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    1062:	83 e0 f0             	and    $0xfffffff0,%eax
    1065:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    106b:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    1072:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
    107b:	83 c0 10             	add    $0x10,%eax
    107e:	83 e0 f0             	and    $0xfffffff0,%eax
    1081:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1087:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    108e:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
    1097:	83 c0 20             	add    $0x20,%eax
    109a:	83 e0 f0             	and    $0xfffffff0,%eax
    109d:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    10a3:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    10aa:	c4 c1 79 6f 86 00 01 00 00 	vmovdqa 0x100(%r14),%xmm0
    10b3:	83 c0 30             	add    $0x30,%eax
    10b6:	83 e0 f0             	and    $0xfffffff0,%eax
    10b9:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    10bf:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    10c6:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
    10cf:	83 c0 40             	add    $0x40,%eax
    10d2:	83 e0 f0             	and    $0xfffffff0,%eax
    10d5:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    10db:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    10e2:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
    10eb:	83 c0 50             	add    $0x50,%eax
    10ee:	83 e0 f0             	and    $0xfffffff0,%eax
    10f1:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    10f7:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    10fe:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
    1107:	c4 c1 7a 7e 96 50 01 00 00 	vmovq  0x150(%r14),%xmm2
    1110:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1117 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1117>	1113: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
    1117:	c4 c1 7a 7e b6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm6
    1120:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
    1126:	c4 c1 79 d6 56 60    	vmovq  %xmm2,0x60(%r14)
    112c:	c4 e3 e9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm2,%xmm2
    1132:	49 89 56 70          	mov    %rdx,0x70(%r14)
    1136:	48 63 08             	movslq (%rax),%rcx
    1139:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
    1140:	48 89 c8             	mov    %rcx,%rax
    1143:	49 63 8e f0 01 00 00 	movslq 0x1f0(%r14),%rcx
    114a:	49 89 4e 20          	mov    %rcx,0x20(%r14)
    114e:	c4 c3 c9 22 9e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm6,%xmm3
    1158:	c4 c1 7a 7e be 80 00 00 00 	vmovq  0x80(%r14),%xmm7
    1161:	c4 c3 f9 22 46 50 01 	vpinsrq $0x1,0x50(%r14),%xmm0,%xmm0
    1168:	c4 c3 c1 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm7,%xmm1
    1172:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
    1178:	c5 fd 7f 84 24 80 00 00 00 	vmovdqa %ymm0,0x80(%rsp)
    1181:	c4 e3 75 18 cb 01    	vinsertf128 $0x1,%xmm3,%ymm1,%ymm1
    1187:	c5 fd 7f 8c 24 a0 00 00 00 	vmovdqa %ymm1,0xa0(%rsp)
    1190:	85 c0                	test   %eax,%eax
    1192:	0f 84 a4 01 00 00    	je     133c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
    1198:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    119f:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    11a6:	89 c0                	mov    %eax,%eax
    11a8:	31 d2                	xor    %edx,%edx
    11aa:	48 8d b4 24 80 00 00 00 	lea    0x80(%rsp),%rsi
    11b2:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
    11b6:	c5 f8 77             	vzeroupper
    11b9:	e8 00 00 00 00       	call   11be <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x11be>	11ba: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    11be:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 11c5 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x11c5>	11c1: R_X86_64_PC32	g_ee_main_mem-0x4
    11c5:	49 89 46 20          	mov    %rax,0x20(%r14)
    11c9:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    11d0:	48 89 c1             	mov    %rax,%rcx
    11d3:	83 e1 f0             	and    $0xfffffff0,%ecx
    11d6:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    11db:	8d 48 10             	lea    0x10(%rax),%ecx
    11de:	83 e1 f0             	and    $0xfffffff0,%ecx
    11e1:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    11ea:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    11ef:	8d 48 20             	lea    0x20(%rax),%ecx
    11f2:	83 e1 f0             	and    $0xfffffff0,%ecx
    11f5:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    11fe:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    1203:	8d 48 30             	lea    0x30(%rax),%ecx
    1206:	83 e1 f0             	and    $0xfffffff0,%ecx
    1209:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    1212:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    1217:	8d 48 40             	lea    0x40(%rax),%ecx
    121a:	83 e1 f0             	and    $0xfffffff0,%ecx
    121d:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
    1226:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    122b:	8d 48 50             	lea    0x50(%rax),%ecx
    122e:	48 83 c0 60          	add    $0x60,%rax
    1232:	83 e1 f0             	and    $0xfffffff0,%ecx
    1235:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    123e:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    1243:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    124a:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    1253:	e9 b6 f4 ff ff       	jmp    70e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x70e>
    1258:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
    1260:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    1267:	49 89 4e 20          	mov    %rcx,0x20(%r14)
    126b:	89 c2                	mov    %eax,%edx
    126d:	49 8b 34 11          	mov    (%r9,%rdx,1),%rsi
    1271:	49 89 b6 f0 01 00 00 	mov    %rsi,0x1f0(%r14)
    1278:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
    127d:	49 89 96 e0 01 00 00 	mov    %rdx,0x1e0(%r14)
    1284:	8d 90 90 00 00 00    	lea    0x90(%rax),%edx
    128a:	83 e2 f0             	and    $0xfffffff0,%edx
    128d:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    1293:	8d 90 80 00 00 00    	lea    0x80(%rax),%edx
    1299:	83 e2 f0             	and    $0xfffffff0,%edx
    129c:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    12a5:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    12ab:	8d 50 70             	lea    0x70(%rax),%edx
    12ae:	83 e2 f0             	and    $0xfffffff0,%edx
    12b1:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    12ba:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    12c0:	8d 50 60             	lea    0x60(%rax),%edx
    12c3:	83 e2 f0             	and    $0xfffffff0,%edx
    12c6:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    12cf:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    12d5:	8d 50 50             	lea    0x50(%rax),%edx
    12d8:	83 e2 f0             	and    $0xfffffff0,%edx
    12db:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    12e4:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    12ea:	8d 50 40             	lea    0x40(%rax),%edx
    12ed:	83 e2 f0             	and    $0xfffffff0,%edx
    12f0:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    12f9:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    12ff:	8d 50 30             	lea    0x30(%rax),%edx
    1302:	48 05 a0 00 00 00    	add    $0xa0,%rax
    1308:	83 e2 f0             	and    $0xfffffff0,%edx
    130b:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    1314:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    131a:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    1321:	48 89 c8             	mov    %rcx,%rax
    1324:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
    132d:	48 8d 65 d8          	lea    -0x28(%rbp),%rsp
    1331:	5b                   	pop    %rbx
    1332:	41 5c                	pop    %r12
    1334:	41 5d                	pop    %r13
    1336:	41 5e                	pop    %r14
    1338:	41 5f                	pop    %r15
    133a:	5d                   	pop    %rbp
    133b:	c3                   	ret
    133c:	41 b8 00 00 00 00    	mov    $0x0,%r8d	133e: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    1342:	b9 00 00 00 00       	mov    $0x0,%ecx	1343: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0xa8
    1347:	ba 90 01 00 00       	mov    $0x190,%edx
    134c:	be 00 00 00 00       	mov    $0x0,%esi	134d: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x38
    1351:	bf 00 00 00 00       	mov    $0x0,%edi	1352: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1+0x1
    1356:	c5 f8 77             	vzeroupper
    1359:	e8 00 00 00 00       	call   135e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>	135a: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    135e:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1360: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    1364:	b9 00 00 00 00       	mov    $0x0,%ecx	1365: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x1d8
    1369:	ba c0 01 00 00       	mov    $0x1c0,%edx
    136e:	be 00 00 00 00       	mov    $0x0,%esi	136f: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x38
    1373:	bf 00 00 00 00       	mov    $0x0,%edi	1374: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x210
    1378:	c5 f8 77             	vzeroupper
    137b:	e8 00 00 00 00       	call   1380 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>	137c: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    1380:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1382: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    1386:	b9 00 00 00 00       	mov    $0x0,%ecx	1387: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8
    138b:	ba 58 01 00 00       	mov    $0x158,%edx
    1390:	be 00 00 00 00       	mov    $0x0,%esi	1391: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x38
    1395:	bf 00 00 00 00       	mov    $0x0,%edi	1396: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x78
    139a:	e8 00 00 00 00       	call   139f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x139f>	139b: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    139f:	41 b8 00 00 00 00    	mov    $0x0,%r8d	13a1: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    13a5:	b9 00 00 00 00       	mov    $0x0,%ecx	13a6: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0xd8
    13aa:	ba 00 01 00 00       	mov    $0x100,%edx
    13af:	be 00 00 00 00       	mov    $0x0,%esi	13b0: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x110
    13b4:	bf 00 00 00 00       	mov    $0x0,%edi	13b5: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x1a8
    13b9:	e8 00 00 00 00       	call   13be <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13be>	13ba: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    13be:	41 b8 00 00 00 00    	mov    $0x0,%r8d	13c0: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    13c4:	b9 00 00 00 00       	mov    $0x0,%ecx	13c5: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0xd8
    13c9:	ba fa 00 00 00       	mov    $0xfa,%edx
    13ce:	be 00 00 00 00       	mov    $0x0,%esi	13cf: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x110
    13d3:	bf 00 00 00 00       	mov    $0x0,%edi	13d4: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x178
    13d8:	e8 00 00 00 00       	call   13dd <.LC24+0x13cd>	13d9: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::execute(void*)>:
       0:	4c 8d 54 24 08       	lea    0x8(%rsp),%r10
       5:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
       9:	41 ff 72 f8          	push   -0x8(%r10)
       d:	55                   	push   %rbp
       e:	48 89 e5             	mov    %rsp,%rbp
      11:	41 57                	push   %r15
      13:	41 56                	push   %r14
      15:	41 55                	push   %r13
      17:	41 54                	push   %r12
      19:	41 52                	push   %r10
      1b:	53                   	push   %rbx
      1c:	48 81 ec 40 01 00 00 	sub    $0x140,%rsp
      23:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
      2a:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
      31:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 38 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x38>	34: R_X86_64_PC32	g_ee_main_mem-0x4
      38:	48 83 c0 80          	add    $0xffffffffffffff80,%rax
      3c:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
      43:	89 c0                	mov    %eax,%eax
      45:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
      49:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      4f:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 56 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x56>	52: R_X86_64_PC32	g_ee_main_mem-0x4
      56:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
      5e:	83 c0 10             	add    $0x10,%eax
      61:	83 e0 f0             	and    $0xfffffff0,%eax
      64:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      6a:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      70:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
      78:	83 c0 20             	add    $0x20,%eax
      7b:	83 e0 f0             	and    $0xfffffff0,%eax
      7e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      84:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      8a:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
      92:	83 c0 30             	add    $0x30,%eax
      95:	83 e0 f0             	and    $0xfffffff0,%eax
      98:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      9e:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      a4:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
      ac:	83 c0 40             	add    $0x40,%eax
      af:	83 e0 f0             	and    $0xfffffff0,%eax
      b2:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      b8:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      be:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
      c6:	83 c0 50             	add    $0x50,%eax
      c9:	83 e0 f0             	and    $0xfffffff0,%eax
      cc:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      d2:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      d8:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
      e0:	83 c0 60             	add    $0x60,%eax
      e3:	83 e0 f0             	and    $0xfffffff0,%eax
      e6:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
      ec:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
      f2:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
      fa:	83 c0 70             	add    $0x70,%eax
      fd:	83 e0 f0             	and    $0xfffffff0,%eax
     100:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     106:	48 8b 47 40          	mov    0x40(%rdi),%rax
     10a:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
     111:	48 8b 47 50          	mov    0x50(%rdi),%rax
     115:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
     11c:	48 8b 47 60          	mov    0x60(%rdi),%rax
     120:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
     127:	48 8b 47 70          	mov    0x70(%rdi),%rax
     12b:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
     132:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
     139:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
     140:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
     147:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
     14e:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 155 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x155>	151: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
     155:	48 63 10             	movslq (%rax),%rdx
     158:	48 89 57 30          	mov    %rdx,0x30(%rdi)
     15c:	f6 c2 0f             	test   $0xf,%dl
     15f:	0f 85 7a 16 00 00    	jne    17df <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
     165:	89 d0                	mov    %edx,%eax
     167:	49 89 fe             	mov    %rdi,%r14
     16a:	49 8b 14 01          	mov    (%r9,%rax,1),%rdx
     16e:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
     173:	48 89 97 10 03 00 00 	mov    %rdx,0x310(%rdi)
     17a:	48 89 57 30          	mov    %rdx,0x30(%rdi)
     17e:	81 e2 ff 00 00 00    	and    $0xff,%edx
     184:	48 89 87 18 03 00 00 	mov    %rax,0x318(%rdi)
     18b:	48 89 47 38          	mov    %rax,0x38(%rdi)
     18f:	48 89 97 00 01 00 00 	mov    %rdx,0x100(%rdi)
     196:	e9 ba 00 00 00       	jmp    255 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x255>
     19b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
     1a0:	48 63 09             	movslq (%rcx),%rcx
     1a3:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
     1ab:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     1af:	85 c9                	test   %ecx,%ecx
     1b1:	0f 84 91 0e 00 00    	je     1048 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1048>
     1b7:	8b 06                	mov    (%rsi),%eax
     1b9:	89 c1                	mov    %eax,%ecx
     1bb:	83 e0 bf             	and    $0xffffffbf,%eax
     1be:	83 e1 40             	and    $0x40,%ecx
     1c1:	48 63 d0             	movslq %eax,%rdx
     1c4:	89 cb                	mov    %ecx,%ebx
     1c6:	49 89 56 40          	mov    %rdx,0x40(%r14)
     1ca:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     1ce:	89 06                	mov    %eax,(%rsi)
     1d0:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     1d7:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1de <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1de>	1da: R_X86_64_PC32	g_ee_main_mem-0x4
     1de:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     1e5:	85 c9                	test   %ecx,%ecx
     1e7:	74 27                	je     210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
     1e9:	89 c0                	mov    %eax,%eax
     1eb:	89 d2                	mov    %edx,%edx
     1ed:	49 63 4c 01 7c       	movslq 0x7c(%r9,%rax,1),%rcx
     1f2:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     1f6:	41 89 4c 11 2c       	mov    %ecx,0x2c(%r9,%rdx,1)
     1fb:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     202:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     209:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>	20c: R_X86_64_PC32	g_ee_main_mem-0x4
     210:	48 05 90 00 00 00    	add    $0x90,%rax
     216:	49 8b 9e 30 01 00 00 	mov    0x130(%r14),%rbx
     21d:	48 83 c2 30          	add    $0x30,%rdx
     221:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
     228:	49 8b 86 10 01 00 00 	mov    0x110(%r14),%rax
     22f:	48 8d 4b ff          	lea    -0x1(%rbx),%rcx
     233:	49 89 96 40 01 00 00 	mov    %rdx,0x140(%r14)
     23a:	48 83 c0 01          	add    $0x1,%rax
     23e:	49 89 8e 30 01 00 00 	mov    %rcx,0x130(%r14)
     245:	49 89 86 10 01 00 00 	mov    %rax,0x110(%r14)
     24c:	48 85 c9             	test   %rcx,%rcx
     24f:	0f 84 cb 0e 00 00    	je     1120 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1120>
     255:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     25c:	49 8b be 70 01 00 00 	mov    0x170(%r14),%rdi
     263:	89 c1                	mov    %eax,%ecx
     265:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
     26d:	49 89 56 30          	mov    %rdx,0x30(%r14)
     271:	48 39 d7             	cmp    %rdx,%rdi
     274:	0f 84 be 0d 00 00    	je     1038 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1038>
     27a:	49 8d 74 09 68       	lea    0x68(%r9,%rcx,1),%rsi
     27f:	49 8d 4c 09 64       	lea    0x64(%r9,%rcx,1),%rcx
     284:	48 63 16             	movslq (%rsi),%rdx
     287:	49 3b be 20 01 00 00 	cmp    0x120(%r14),%rdi
     28e:	0f 84 c4 0d 00 00    	je     1058 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1058>
     294:	81 e2 00 20 00 00    	and    $0x2000,%edx
     29a:	89 d3                	mov    %edx,%ebx
     29c:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     2a0:	0f 84 fa fe ff ff    	je     1a0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1a0>
     2a6:	48 63 11             	movslq (%rcx),%rdx
     2a9:	48 89 d7             	mov    %rdx,%rdi
     2ac:	49 2b be 00 01 00 00 	sub    0x100(%r14),%rdi
     2b3:	49 89 56 30          	mov    %rdx,0x30(%r14)
     2b7:	49 89 7e 40          	mov    %rdi,0x40(%r14)
     2bb:	48 83 fa ff          	cmp    $0xffffffffffffffff,%rdx
     2bf:	74 51                	je     312 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x312>
     2c1:	48 89 fe             	mov    %rdi,%rsi
     2c4:	c4 c1 79 6e 6e 48    	vmovd  0x48(%r14),%xmm5
     2ca:	c4 c3 51 22 4e 4c 01 	vpinsrd $0x1,0x4c(%r14),%xmm5,%xmm1
     2d1:	c5 f9 6e ef          	vmovd  %edi,%xmm5
     2d5:	48 c1 fe 20          	sar    $0x20,%rsi
     2d9:	c4 e3 51 22 c6 01    	vpinsrd $0x1,%esi,%xmm5,%xmm0
     2df:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
     2e3:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
     2e7:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
     2ec:	c4 c1 79 7f 46 30    	vmovdqa %xmm0,0x30(%r14)
     2f2:	48 85 d2             	test   %rdx,%rdx
     2f5:	0f 84 4d 0d 00 00    	je     1048 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1048>
     2fb:	c5 f9 7e 01          	vmovd  %xmm0,(%rcx)
     2ff:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
     306:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 30d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x30d>	309: R_X86_64_PC32	g_ee_main_mem-0x4
     30d:	48 8d 74 02 68       	lea    0x68(%rdx,%rax,1),%rsi
     312:	8b 06                	mov    (%rsi),%eax
     314:	89 c2                	mov    %eax,%edx
     316:	83 e0 bf             	and    $0xffffffbf,%eax
     319:	83 e2 40             	and    $0x40,%edx
     31c:	48 63 c8             	movslq %eax,%rcx
     31f:	89 d3                	mov    %edx,%ebx
     321:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     325:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     329:	89 06                	mov    %eax,(%rsi)
     32b:	85 d2                	test   %edx,%edx
     32d:	74 25                	je     354 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x354>
     32f:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
     336:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 33d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x33d>	339: R_X86_64_PC32	g_ee_main_mem-0x4
     33d:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
     342:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     346:	48 89 ca             	mov    %rcx,%rdx
     349:	41 8b 8e 40 01 00 00 	mov    0x140(%r14),%ecx
     350:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
     354:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 35b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x35b>	357: R_X86_64_PC32	g_ee_main_mem-0x4
     35b:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
     362:	49 63 4c 01 70       	movslq 0x70(%r9,%rax,1),%rcx
     367:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
     36e:	85 c9                	test   %ecx,%ecx
     370:	0f 84 fa 01 00 00    	je     570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     376:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
     37f:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     386:	48 83 e8 50          	sub    $0x50,%rax
     38a:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     391:	83 e0 f0             	and    $0xfffffff0,%eax
     394:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     39a:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     3a1:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
     3aa:	83 c0 10             	add    $0x10,%eax
     3ad:	83 e0 f0             	and    $0xfffffff0,%eax
     3b0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     3b6:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     3bd:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
     3c6:	83 c0 20             	add    $0x20,%eax
     3c9:	83 e0 f0             	and    $0xfffffff0,%eax
     3cc:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     3d2:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     3d9:	c4 c1 79 6f 86 10 01 00 00 	vmovdqa 0x110(%r14),%xmm0
     3e2:	83 c0 30             	add    $0x30,%eax
     3e5:	83 e0 f0             	and    $0xfffffff0,%eax
     3e8:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     3ee:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
     3f5:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
     3fe:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
     405:	49 89 46 40          	mov    %rax,0x40(%r14)
     409:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     410:	49 89 46 50          	mov    %rax,0x50(%r14)
     414:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     41b:	49 89 46 60          	mov    %rax,0x60(%r14)
     41f:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     426:	83 c0 40             	add    $0x40,%eax
     429:	83 e0 f0             	and    $0xfffffff0,%eax
     42c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     432:	c4 c1 7a 7e 6e 60    	vmovq  0x60(%r14),%xmm5
     438:	c4 c1 7a 7e a6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm4
     441:	c4 c3 d9 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm4,%xmm1
     44b:	c4 c3 d1 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm5,%xmm2
     452:	c4 c1 7a 7e a6 80 00 00 00 	vmovq  0x80(%r14),%xmm4
     45b:	c4 c3 d9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm4,%xmm0
     465:	c4 c1 7a 7e 66 40    	vmovq  0x40(%r14),%xmm4
     46b:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     471:	c4 c3 d9 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm4,%xmm1
     478:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     47e:	c5 fd 7f 8d d0 fe ff ff 	vmovdqa %ymm1,-0x130(%rbp)
     486:	c5 fd 7f 85 f0 fe ff ff 	vmovdqa %ymm0,-0x110(%rbp)
     48e:	85 ff                	test   %edi,%edi
     490:	0f 84 8a 13 00 00    	je     1820 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
     496:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     49d:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     4a4:	4c 01 cf             	add    %r9,%rdi
     4a7:	31 d2                	xor    %edx,%edx
     4a9:	48 8d b5 d0 fe ff ff 	lea    -0x130(%rbp),%rsi
     4b0:	c5 f8 77             	vzeroupper
     4b3:	e8 00 00 00 00       	call   4b8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4b8>	4b4: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     4b8:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 4bf <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4bf>	4bb: R_X86_64_PC32	g_ee_main_mem-0x4
     4bf:	49 89 46 20          	mov    %rax,0x20(%r14)
     4c3:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     4ca:	48 89 c1             	mov    %rax,%rcx
     4cd:	83 e1 f0             	and    $0xfffffff0,%ecx
     4d0:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     4d5:	8d 48 10             	lea    0x10(%rax),%ecx
     4d8:	83 e1 f0             	and    $0xfffffff0,%ecx
     4db:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
     4e4:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     4e9:	8d 48 20             	lea    0x20(%rax),%ecx
     4ec:	83 e1 f0             	and    $0xfffffff0,%ecx
     4ef:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
     4f8:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     4fd:	8d 48 30             	lea    0x30(%rax),%ecx
     500:	83 e1 f0             	and    $0xfffffff0,%ecx
     503:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
     50c:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     511:	8d 48 40             	lea    0x40(%rax),%ecx
     514:	48 83 c0 50          	add    $0x50,%rax
     518:	83 e1 f0             	and    $0xfffffff0,%ecx
     51b:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
     524:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     529:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     530:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
     539:	e8 00 00 00 00       	call   53e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x53e>	53a: R_X86_64_PC32	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv-0x4
     53e:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
     545:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 54c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x54c>	548: R_X86_64_PC32	g_ee_main_mem-0x4
     54c:	84 c0                	test   %al,%al
     54e:	89 f0                	mov    %esi,%eax
     550:	74 1e                	je     570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     552:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 558 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x558>	554: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count-0x4
     558:	81 fa 3f 1f 00 00    	cmp    $0x1f3f,%edx
     55e:	0f 8e dc 10 00 00    	jle    1640 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1640>
     564:	90                   	nop
     565:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
     570:	49 63 4c 01 78       	movslq 0x78(%r9,%rax,1),%rcx
     575:	49 89 4e 50          	mov    %rcx,0x50(%r14)
     579:	48 89 ca             	mov    %rcx,%rdx
     57c:	49 8d 4c 01 74       	lea    0x74(%r9,%rax,1),%rcx
     581:	48 63 01             	movslq (%rcx),%rax
     584:	49 89 46 30          	mov    %rax,0x30(%r14)
     588:	49 2b 86 00 01 00 00 	sub    0x100(%r14),%rax
     58f:	49 89 46 40          	mov    %rax,0x40(%r14)
     593:	85 d2                	test   %edx,%edx
     595:	74 13                	je     5aa <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
     597:	48 8d 50 ff          	lea    -0x1(%rax),%rdx
     59b:	49 89 56 30          	mov    %rdx,0x30(%r14)
     59f:	89 01                	mov    %eax,(%rcx)
     5a1:	48 85 d2             	test   %rdx,%rdx
     5a4:	0f 88 46 0c 00 00    	js     11f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x11f0>
     5aa:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     5b1:	f6 c2 0f             	test   $0xf,%dl
     5b4:	0f 85 25 12 00 00    	jne    17df <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
     5ba:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 5c1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5c1>	5bd: R_X86_64_PC32	g_ee_main_mem-0x4
     5c1:	89 d2                	mov    %edx,%edx
     5c3:	4d 8b 96 50 01 00 00 	mov    0x150(%r14),%r10
     5ca:	c5 7a 7e 04 10       	vmovq  (%rax,%rdx,1),%xmm8
     5cf:	48 8b 4c 10 08       	mov    0x8(%rax,%rdx,1),%rcx
     5d4:	c4 41 79 d6 86 90 02 00 00 	vmovq  %xmm8,0x290(%r14)
     5dd:	49 89 8e 98 02 00 00 	mov    %rcx,0x298(%r14)
     5e4:	48 8b 74 10 10       	mov    0x10(%rax,%rdx,1),%rsi
     5e9:	4c 8b 44 10 18       	mov    0x18(%rax,%rdx,1),%r8
     5ee:	49 89 b6 a0 02 00 00 	mov    %rsi,0x2a0(%r14)
     5f5:	4d 89 86 a8 02 00 00 	mov    %r8,0x2a8(%r14)
     5fc:	48 8b 74 10 20       	mov    0x20(%rax,%rdx,1),%rsi
     601:	48 8b 7c 10 28       	mov    0x28(%rax,%rdx,1),%rdi
     606:	49 89 b6 b0 02 00 00 	mov    %rsi,0x2b0(%r14)
     60d:	49 89 be b8 02 00 00 	mov    %rdi,0x2b8(%r14)
     614:	41 f6 c2 0f          	test   $0xf,%r10b
     618:	0f 85 c1 11 00 00    	jne    17df <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
     61e:	45 89 d2             	mov    %r10d,%r10d
     621:	c4 63 b9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm8,%xmm8
     627:	c4 c1 7a 10 b6 18 03 00 00 	vmovss 0x318(%r14),%xmm6
     630:	c4 41 7a 10 a6 1c 03 00 00 	vmovss 0x31c(%r14),%xmm12
     639:	4e 8d 64 10 10       	lea    0x10(%rax,%r10,1),%r12
     63e:	49 8b 0c 24          	mov    (%r12),%rcx
     642:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
     647:	c5 c8 c6 d6 00       	vshufps $0x0,%xmm6,%xmm6,%xmm2
     64c:	49 89 8e c0 02 00 00 	mov    %rcx,0x2c0(%r14)
     653:	49 89 d5             	mov    %rdx,%r13
     656:	49 89 96 c8 02 00 00 	mov    %rdx,0x2c8(%r14)
     65d:	4e 8b 4c 10 20       	mov    0x20(%rax,%r10,1),%r9
     662:	49 c1 ed 20          	shr    $0x20,%r13
     666:	4a 8b 5c 10 28       	mov    0x28(%rax,%r10,1),%rbx
     66b:	4d 89 8e d0 02 00 00 	mov    %r9,0x2d0(%r14)
     672:	49 89 9e d8 02 00 00 	mov    %rbx,0x2d8(%r14)
     679:	4e 8b 5c 10 38       	mov    0x38(%rax,%r10,1),%r11
     67e:	c4 a1 7a 7e 4c 10 30 	vmovq  0x30(%rax,%r10,1),%xmm1
     685:	4d 89 9e e8 02 00 00 	mov    %r11,0x2e8(%r14)
     68c:	c4 c1 f9 6e eb       	vmovq  %r11,%xmm5
     691:	45 89 df             	mov    %r11d,%r15d
     694:	c4 c1 79 d6 8e e0 02 00 00 	vmovq  %xmm1,0x2e0(%r14)
     69d:	c4 c3 f1 22 e3 01    	vpinsrq $0x1,%r11,%xmm1,%xmm4
     6a3:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
     6a8:	c4 a1 7a 6f 7c 10 40 	vmovdqu 0x40(%rax,%r10,1),%xmm7
     6af:	c4 c1 7a 7e 8e 14 03 00 00 	vmovq  0x314(%r14),%xmm1
     6b8:	c5 79 6f fd          	vmovdqa %xmm5,%xmm15
     6bc:	c5 e8 59 d7          	vmulps %xmm7,%xmm2,%xmm2
     6c0:	c5 f9 6f ef          	vmovdqa %xmm7,%xmm5
     6c4:	c5 f9 6f df          	vmovdqa %xmm7,%xmm3
     6c8:	c4 c1 7a 7f be f0 02 00 00 	vmovdqu %xmm7,0x2f0(%r14)
     6d1:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
     6d6:	c5 7a 12 d9          	vmovsldup %xmm1,%xmm11
     6da:	c5 79 6f ed          	vmovdqa %xmm5,%xmm13
     6de:	c5 70 c6 f1 00       	vshufps $0x0,%xmm1,%xmm1,%xmm14
     6e3:	c5 f0 c6 e9 00       	vshufps $0x0,%xmm1,%xmm1,%xmm5
     6e8:	c5 fa 16 c9          	vmovshdup %xmm1,%xmm1
     6ec:	c4 41 60 14 cd       	vunpcklps %xmm13,%xmm3,%xmm9
     6f1:	c5 f9 6e f9          	vmovd  %ecx,%xmm7
     6f5:	c4 41 7a 7e c9       	vmovq  %xmm9,%xmm9
     6fa:	48 c1 e9 20          	shr    $0x20,%rcx
     6fe:	4e 63 54 10 60       	movslq 0x60(%rax,%r10,1),%r10
     703:	c4 43 0d 18 f6 01    	vinsertf128 $0x1,%xmm14,%ymm14,%ymm14
     709:	c5 79 6e d1          	vmovd  %ecx,%xmm10
     70d:	c4 c1 78 29 96 f0 02 00 00 	vmovaps %xmm2,0x2f0(%r14)
     716:	c5 e8 15 d2          	vunpckhps %xmm2,%xmm2,%xmm2
     71a:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     71e:	45 89 96 00 02 00 00 	mov    %r10d,0x200(%r14)
     725:	c4 c1 70 59 c9       	vmulps %xmm9,%xmm1,%xmm1
     72a:	c4 41 40 14 ca       	vunpcklps %xmm10,%xmm7,%xmm9
     72f:	4d 89 56 30          	mov    %r10,0x30(%r14)
     733:	c4 41 7a 7e c9       	vmovq  %xmm9,%xmm9
     738:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     73c:	c4 c1 70 58 c9       	vaddps %xmm9,%xmm1,%xmm1
     741:	c5 79 6e ca          	vmovd  %edx,%xmm9
     745:	c4 c1 6a 58 d1       	vaddss %xmm9,%xmm2,%xmm2
     74a:	c4 c1 78 13 8e c0 02 00 00 	vmovlps %xmm1,0x2c0(%r14)
     753:	c4 c1 7a 11 96 c8 02 00 00 	vmovss %xmm2,0x2c8(%r14)
     75c:	45 85 d2             	test   %r10d,%r10d
     75f:	0f 85 03 09 00 00    	jne    1068 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1068>
     765:	c5 fa 16 f1          	vmovshdup %xmm1,%xmm6
     769:	c5 f8 28 d9          	vmovaps %xmm1,%xmm3
     76d:	c4 c1 79 6e fd       	vmovd  %r13d,%xmm7
     772:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     776:	c4 c1 79 6e c9       	vmovd  %r9d,%xmm1
     77b:	49 c1 e9 20          	shr    $0x20,%r9
     77f:	c5 d0 59 e4          	vmulps %xmm4,%xmm5,%xmm4
     783:	c5 e8 14 d7          	vunpcklps %xmm7,%xmm2,%xmm2
     787:	c4 41 7a 7e db       	vmovq  %xmm11,%xmm11
     78c:	c5 e0 16 d2          	vmovlhps %xmm2,%xmm3,%xmm2
     790:	c5 e8 59 ed          	vmulps %xmm5,%xmm2,%xmm5
     794:	c5 f9 6e db          	vmovd  %ebx,%xmm3
     798:	48 c1 eb 20          	shr    $0x20,%rbx
     79c:	c5 f9 6e f3          	vmovd  %ebx,%xmm6
     7a0:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     7a4:	c4 c1 79 6e f1       	vmovd  %r9d,%xmm6
     7a9:	c5 f0 14 ce          	vunpcklps %xmm6,%xmm1,%xmm1
     7ad:	c4 c1 79 6e f7       	vmovd  %r15d,%xmm6
     7b2:	c5 f0 16 cb          	vmovlhps %xmm3,%xmm1,%xmm1
     7b6:	c4 e3 6d 18 c9 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm1
     7bc:	c4 c1 48 14 c7       	vunpcklps %xmm15,%xmm6,%xmm0
     7c1:	c4 c1 79 6e d8       	vmovd  %r8d,%xmm3
     7c6:	c4 c1 74 59 ce       	vmulps %ymm14,%ymm1,%ymm1
     7cb:	c4 c1 50 58 e8       	vaddps %xmm8,%xmm5,%xmm5
     7d0:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     7d4:	49 c1 e8 20          	shr    $0x20,%r8
     7d8:	c4 c1 78 59 c3       	vmulps %xmm11,%xmm0,%xmm0
     7dd:	c4 c1 79 6e f8       	vmovd  %r8d,%xmm7
     7e2:	c4 c1 78 29 a6 40 03 00 00 	vmovaps %xmm4,0x340(%r14)
     7eb:	c4 c1 78 29 ae 90 02 00 00 	vmovaps %xmm5,0x290(%r14)
     7f4:	c4 c1 7c 11 8e 20 03 00 00 	vmovups %ymm1,0x320(%r14)
     7fd:	c4 e3 7d 19 c9 01    	vextractf128 $0x1,%ymm1,%xmm1
     803:	c5 f0 15 e9          	vunpckhps %xmm1,%xmm1,%xmm5
     807:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     80b:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
     810:	c5 f2 58 cf          	vaddss %xmm7,%xmm1,%xmm1
     814:	c5 d2 58 eb          	vaddss %xmm3,%xmm5,%xmm5
     818:	c5 f9 6e df          	vmovd  %edi,%xmm3
     81c:	48 c1 ef 20          	shr    $0x20,%rdi
     820:	c5 f9 6e f7          	vmovd  %edi,%xmm6
     824:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     828:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
     82c:	c5 d0 14 c9          	vunpcklps %xmm1,%xmm5,%xmm1
     830:	c5 f8 58 c3          	vaddps %xmm3,%xmm0,%xmm0
     834:	c5 f9 6e de          	vmovd  %esi,%xmm3
     838:	48 c1 ee 20          	shr    $0x20,%rsi
     83c:	c5 da 58 f3          	vaddss %xmm3,%xmm4,%xmm6
     840:	c5 f9 6e fe          	vmovd  %esi,%xmm7
     844:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
     849:	c5 e0 57 db          	vxorps %xmm3,%xmm3,%xmm3
     84d:	c5 da 58 e7          	vaddss %xmm7,%xmm4,%xmm4
     851:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
     855:	c5 78 28 c0          	vmovaps %xmm0,%xmm8
     859:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     85d:	c5 ca c2 ff 05       	vcmpnltss %xmm7,%xmm6,%xmm7
     862:	c4 e3 61 4a de 70    	vblendvps %xmm7,%xmm6,%xmm3,%xmm3
     868:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
     86c:	c5 c8 57 f6          	vxorps %xmm6,%xmm6,%xmm6
     870:	c5 da c2 ff 05       	vcmpnltss %xmm7,%xmm4,%xmm7
     875:	c4 e3 49 4a f4 70    	vblendvps %xmm7,%xmm4,%xmm6,%xmm6
     87b:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     87f:	c5 f0 16 cb          	vmovlhps %xmm3,%xmm1,%xmm1
     883:	c4 c1 78 11 8e a8 02 00 00 	vmovups %xmm1,0x2a8(%r14)
     88c:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
     890:	c5 f8 c2 c1 01       	vcmpltps %xmm1,%xmm0,%xmm0
     895:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
     899:	c4 63 39 4a c1 00    	vblendvps %xmm0,%xmm1,%xmm8,%xmm8
     89f:	c4 41 78 13 86 b8 02 00 00 	vmovlps %xmm8,0x2b8(%r14)
     8a8:	c4 c1 78 11 14 24    	vmovups %xmm2,(%r12)
     8ae:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     8b5:	f6 c2 0f             	test   $0xf,%dl
     8b8:	0f 85 40 0f 00 00    	jne    17fe <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
     8be:	c4 c1 79 6f 86 90 02 00 00 	vmovdqa 0x290(%r14),%xmm0
     8c7:	89 d2                	mov    %edx,%edx
     8c9:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
     8ce:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     8d5:	f6 c2 0f             	test   $0xf,%dl
     8d8:	0f 85 20 0f 00 00    	jne    17fe <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
     8de:	c4 c1 79 6f 86 a0 02 00 00 	vmovdqa 0x2a0(%r14),%xmm0
     8e7:	89 d2                	mov    %edx,%edx
     8e9:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
     8ef:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     8f6:	f6 c2 0f             	test   $0xf,%dl
     8f9:	0f 85 ff 0e 00 00    	jne    17fe <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
     8ff:	c4 c1 79 6f 86 b0 02 00 00 	vmovdqa 0x2b0(%r14),%xmm0
     908:	89 d2                	mov    %edx,%edx
     90a:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
     910:	c5 f8 77             	vzeroupper
     913:	e8 00 00 00 00       	call   918 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x918>	914: R_X86_64_PC32	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv-0x4
     918:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
     91f:	84 c0                	test   %al,%al
     921:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 928 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x928>	924: R_X86_64_PC32	g_ee_main_mem-0x4
     928:	0f 84 b2 00 00 00    	je     9e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
     92e:	8b 0d 00 00 00 00    	mov    0x0(%rip),%ecx        # 934 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x934>	930: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count_1-0x4
     934:	81 f9 3f 1f 00 00    	cmp    $0x1f3f,%ecx
     93a:	0f 8f a0 00 00 00    	jg     9e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
     940:	48 8b 7c 10 20       	mov    0x20(%rax,%rdx,1),%rdi
     945:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
     94c:	4c 8b 44 10 28       	mov    0x28(%rax,%rdx,1),%r8
     951:	41 89 f2             	mov    %esi,%r10d
     954:	c5 79 6e c7          	vmovd  %edi,%xmm8
     958:	c5 78 2f 05 00 00 00 00 	vcomiss 0x0(%rip),%xmm8        # 960 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x960>	95c: R_X86_64_PC32	.LC21-0x4
     960:	4e 8b 4c 10 30       	mov    0x30(%rax,%r10,1),%r9
     965:	c4 c1 79 6e d0       	vmovd  %r8d,%xmm2
     96a:	4e 8b 54 10 38       	mov    0x38(%rax,%r10,1),%r10
     96f:	c4 c1 79 6e e1       	vmovd  %r9d,%xmm4
     974:	0f 87 a6 0b 00 00    	ja     1520 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1520>
     97a:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
     97e:	c5 f8 2e d0          	vucomiss %xmm0,%xmm2
     982:	7a 3c                	jp     9c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
     984:	75 3a                	jne    9c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
     986:	c4 e1 f9 6e f7       	vmovq  %rdi,%xmm6
     98b:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
     990:	c5 f8 2f 35 00 00 00 00 	vcomiss 0x0(%rip),%xmm6        # 998 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x998>	994: R_X86_64_PC32	.LC22-0x4
     998:	c5 f9 6f ce          	vmovdqa %xmm6,%xmm1
     99c:	72 22                	jb     9c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
     99e:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # 9a6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9a6>	9a2: R_X86_64_PC32	.LC23-0x4
     9a6:	c4 c1 78 2f c0       	vcomiss %xmm8,%xmm0
     9ab:	0f 83 9f 0b 00 00    	jae    1550 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1550>
     9b1:	0f 1f 40 00          	nopl   0x0(%rax)
     9b5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
     9c0:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # 9c8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c8>	9c4: R_X86_64_PC32	.LC24-0x4
     9c8:	c5 f8 2f c4          	vcomiss %xmm4,%xmm0
     9cc:	0f 87 3a 0d 00 00    	ja     170c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x170c>
     9d2:	0f 1f 00             	nopl   (%rax)
     9d5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
     9e0:	48 8d 54 10 18       	lea    0x18(%rax,%rdx,1),%rdx
     9e5:	c5 d8 57 e4          	vxorps %xmm4,%xmm4,%xmm4
     9e9:	c5 fa 2c 02          	vcvttss2si (%rdx),%eax
     9ed:	48 0f bf c8          	movswq %ax,%rcx
     9f1:	98                   	cwtl
     9f2:	c5 da 2a c0          	vcvtsi2ss %eax,%xmm4,%xmm0
     9f6:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     9fa:	c4 c1 7a 11 86 00 02 00 00 	vmovss %xmm0,0x200(%r14)
     a03:	c5 fa 11 02          	vmovss %xmm0,(%rdx)
     a07:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     a0e:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # a15 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa15>	a11: R_X86_64_PC32	g_ee_main_mem-0x4
     a15:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # a1c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa1c>	a18: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0xc
     a1c:	89 c2                	mov    %eax,%edx
     a1e:	49 8d 7c 11 68       	lea    0x68(%r9,%rdx,1),%rdi
     a23:	8b 17                	mov    (%rdi),%edx
     a25:	81 e2 80 00 00 00    	and    $0x80,%edx
     a2b:	89 d3                	mov    %edx,%ebx
     a2d:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     a31:	48 63 09             	movslq (%rcx),%rcx
     a34:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
     a3b:	0f 84 ff 03 00 00    	je     e40 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe40>
     a41:	e8 00 00 00 00       	call   a46 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa46>	a42: R_X86_64_PC32	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv-0x4
     a46:	89 c3                	mov    %eax,%ebx
     a48:	84 c0                	test   %al,%al
     a4a:	0f 84 d1 01 00 00    	je     c21 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>
     a50:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # a56 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa56>	a52: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count_2-0x4
     a56:	81 fa 9f 86 01 00    	cmp    $0x1869f,%edx
     a5c:	0f 8f d6 0b 00 00    	jg     1638 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1638>
     a62:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # a69 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa69>	a65: R_X86_64_PC32	g_ee_main_mem-0x4
     a69:	41 8b 8e 50 01 00 00 	mov    0x150(%r14),%ecx
     a70:	83 c2 01             	add    $0x1,%edx
     a73:	41 8b be 40 01 00 00 	mov    0x140(%r14),%edi
     a7a:	89 15 00 00 00 00    	mov    %edx,0x0(%rip)        # a80 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa80>	a7c: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count_2-0x4
     a80:	44 8b 64 08 6c       	mov    0x6c(%rax,%rcx,1),%r12d
     a85:	89 8d 9c fe ff ff    	mov    %ecx,-0x164(%rbp)
     a8b:	c5 f9 6e 4c 08 08    	vmovd  0x8(%rax,%rcx,1),%xmm1
     a91:	c5 79 6e 44 08 0c    	vmovd  0xc(%rax,%rcx,1),%xmm8
     a97:	45 8d 5c 24 ef       	lea    -0x11(%r12),%r11d
     a9c:	4c 8b 44 08 10       	mov    0x10(%rax,%rcx,1),%r8
     aa1:	4c 8b 54 08 18       	mov    0x18(%rax,%rcx,1),%r10
     aa6:	4c 8b 4c 08 50       	mov    0x50(%rax,%rcx,1),%r9
     aab:	48 8b 54 08 58       	mov    0x58(%rax,%rcx,1),%rdx
     ab0:	4c 8b 6c 38 08       	mov    0x8(%rax,%rdi,1),%r13
     ab5:	48 8b 0c 38          	mov    (%rax,%rdi,1),%rcx
     ab9:	48 8b 74 38 20       	mov    0x20(%rax,%rdi,1),%rsi
     abe:	48 8b 7c 38 28       	mov    0x28(%rax,%rdi,1),%rdi
     ac3:	41 81 fb e2 ff ff 07 	cmp    $0x7ffffe2,%r11d
     aca:	0f 86 cb 0c 00 00    	jbe    179b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x179b>
     ad0:	c4 41 31 57 c9       	vxorpd %xmm9,%xmm9,%xmm9
     ad5:	c5 79 29 ca          	vmovapd %xmm9,%xmm2
     ad9:	c4 41 79 28 d1       	vmovapd %xmm9,%xmm10
     ade:	4c 8b 1d 00 00 00 00 	mov    0x0(%rip),%r11        # ae5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xae5>	ae1: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
     ae5:	c5 d0 57 ed          	vxorps %xmm5,%xmm5,%xmm5
     ae9:	45 8b 1b             	mov    (%r11),%r11d
     aec:	45 8d 7b ef          	lea    -0x11(%r11),%r15d
     af0:	41 81 ff e6 ff ff 07 	cmp    $0x7ffffe6,%r15d
     af7:	77 07                	ja     b00 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb00>
     af9:	c4 a1 7a 10 6c 18 04 	vmovss 0x4(%rax,%r11,1),%xmm5
     b00:	48 83 ec 60          	sub    $0x60,%rsp
     b04:	c4 c1 79 6e f1       	vmovd  %r9d,%xmm6
     b09:	c4 e1 f9 6e c7       	vmovq  %rdi,%xmm0
     b0e:	c4 41 3a 5a c0       	vcvtss2sd %xmm8,%xmm8,%xmm8
     b13:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
     b18:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     b1c:	c5 fb 11 44 24 58    	vmovsd %xmm0,0x58(%rsp)
     b22:	c5 f9 6e c7          	vmovd  %edi,%xmm0
     b26:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     b2a:	c5 fb 11 44 24 50    	vmovsd %xmm0,0x50(%rsp)
     b30:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
     b35:	c4 c1 f9 6e e1       	vmovq  %r9,%xmm4
     b3a:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
     b3f:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     b43:	c4 41 79 6e d8       	vmovd  %r8d,%xmm11
     b48:	c5 ca 5a f6          	vcvtss2sd %xmm6,%xmm6,%xmm6
     b4c:	c5 fb 11 44 24 48    	vmovsd %xmm0,0x48(%rsp)
     b52:	c5 f9 6e c6          	vmovd  %esi,%xmm0
     b56:	c4 c1 f9 6e d8       	vmovq  %r8,%xmm3
     b5b:	8b b5 9c fe ff ff    	mov    -0x164(%rbp),%esi
     b61:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     b65:	c5 fb 11 44 24 40    	vmovsd %xmm0,0x40(%rsp)
     b6b:	c4 c1 79 6e c5       	vmovd  %r13d,%xmm0
     b70:	bf 00 00 00 00       	mov    $0x0,%edi	b71: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d7executeEPv.str1.8+0x130
     b75:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     b79:	c5 fb 11 44 24 38    	vmovsd %xmm0,0x38(%rsp)
     b7f:	c5 d2 5a ed          	vcvtss2sd %xmm5,%xmm5,%xmm5
     b83:	c4 e1 f9 6e c1       	vmovq  %rcx,%xmm0
     b88:	c5 fb 11 54 24 18    	vmovsd %xmm2,0x18(%rsp)
     b8e:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
     b93:	c4 e1 f9 6e d2       	vmovq  %rdx,%xmm2
     b98:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     b9c:	c5 fb 11 44 24 30    	vmovsd %xmm0,0x30(%rsp)
     ba2:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
     ba6:	c5 e8 c6 d2 55       	vshufps $0x55,%xmm2,%xmm2,%xmm2
     bab:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
     bb0:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     bb4:	c5 fb 11 44 24 28    	vmovsd %xmm0,0x28(%rsp)
     bba:	c5 ea 5a c2          	vcvtss2sd %xmm2,%xmm2,%xmm0
     bbe:	c5 f9 6f fc          	vmovdqa %xmm4,%xmm7
     bc2:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
     bc8:	c5 f9 6e c2          	vmovd  %edx,%xmm0
     bcc:	c4 c1 79 6e e2       	vmovd  %r10d,%xmm4
     bd1:	44 89 e2             	mov    %r12d,%edx
     bd4:	c5 7b 11 54 24 20    	vmovsd %xmm10,0x20(%rsp)
     bda:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     bde:	b8 08 00 00 00       	mov    $0x8,%eax
     be3:	c5 e0 c6 db 55       	vshufps $0x55,%xmm3,%xmm3,%xmm3
     be8:	c5 c2 5a ff          	vcvtss2sd %xmm7,%xmm7,%xmm7
     bec:	c5 da 5a e4          	vcvtss2sd %xmm4,%xmm4,%xmm4
     bf0:	c5 e2 5a db          	vcvtss2sd %xmm3,%xmm3,%xmm3
     bf4:	c4 c1 22 5a d3       	vcvtss2sd %xmm11,%xmm11,%xmm2
     bf9:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
     bfe:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
     c02:	c5 f2 5a c9          	vcvtss2sd %xmm1,%xmm1,%xmm1
     c06:	c5 7b 11 4c 24 10    	vmovsd %xmm9,0x10(%rsp)
     c0c:	e8 00 00 00 00       	call   c11 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc11>	c0d: R_X86_64_PLT32	printf-0x4
     c11:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # c18 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc18>	c14: R_X86_64_PC32	stdout-0x4
     c18:	48 83 c4 60          	add    $0x60,%rsp
     c1c:	e8 00 00 00 00       	call   c21 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>	c1d: R_X86_64_PLT32	fflush-0x4
     c21:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     c28:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # c2f <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc2f>	c2b: R_X86_64_PC32	g_ee_main_mem-0x4
     c2f:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
     c38:	48 83 e8 60          	sub    $0x60,%rax
     c3c:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     c43:	83 e0 f0             	and    $0xfffffff0,%eax
     c46:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     c4c:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     c53:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
     c5c:	83 c0 10             	add    $0x10,%eax
     c5f:	83 e0 f0             	and    $0xfffffff0,%eax
     c62:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     c68:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     c6f:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
     c78:	83 c0 20             	add    $0x20,%eax
     c7b:	83 e0 f0             	and    $0xfffffff0,%eax
     c7e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     c84:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     c8b:	c4 c1 79 6f 86 10 01 00 00 	vmovdqa 0x110(%r14),%xmm0
     c94:	83 c0 30             	add    $0x30,%eax
     c97:	83 e0 f0             	and    $0xfffffff0,%eax
     c9a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     ca0:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     ca7:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
     cb0:	83 c0 40             	add    $0x40,%eax
     cb3:	83 e0 f0             	and    $0xfffffff0,%eax
     cb6:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     cbc:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
     cc3:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
     ccc:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
     cd3:	49 89 46 40          	mov    %rax,0x40(%r14)
     cd7:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     cde:	49 89 46 50          	mov    %rax,0x50(%r14)
     ce2:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     ce9:	49 89 46 60          	mov    %rax,0x60(%r14)
     ced:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     cf4:	83 c0 50             	add    $0x50,%eax
     cf7:	83 e0 f0             	and    $0xfffffff0,%eax
     cfa:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     d00:	c4 c1 7a 7e 66 60    	vmovq  0x60(%r14),%xmm4
     d06:	c4 c1 7a 7e ae a0 00 00 00 	vmovq  0xa0(%r14),%xmm5
     d0f:	c4 c1 7a 7e 96 80 00 00 00 	vmovq  0x80(%r14),%xmm2
     d18:	c4 c3 d1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm5,%xmm1
     d22:	c4 c3 e9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm2,%xmm0
     d2c:	c4 c3 d9 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm4,%xmm2
     d33:	c4 c1 7a 7e 6e 40    	vmovq  0x40(%r14),%xmm5
     d39:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     d3f:	c4 c3 d1 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm5,%xmm1
     d46:	c5 fd 7f 85 70 ff ff ff 	vmovdqa %ymm0,-0x90(%rbp)
     d4e:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     d54:	c5 fd 7f 8d 50 ff ff ff 	vmovdqa %ymm1,-0xb0(%rbp)
     d5c:	85 ff                	test   %edi,%edi
     d5e:	0f 84 bc 0a 00 00    	je     1820 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
     d64:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     d6b:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     d72:	4c 01 cf             	add    %r9,%rdi
     d75:	31 d2                	xor    %edx,%edx
     d77:	48 8d b5 50 ff ff ff 	lea    -0xb0(%rbp),%rsi
     d7e:	c5 f8 77             	vzeroupper
     d81:	e8 00 00 00 00       	call   d86 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd86>	d82: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     d86:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
     d8d:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # d94 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd94>	d90: R_X86_64_PC32	g_ee_main_mem-0x4
     d94:	49 89 46 20          	mov    %rax,0x20(%r14)
     d98:	48 89 d0             	mov    %rdx,%rax
     d9b:	8d 4a 10             	lea    0x10(%rdx),%ecx
     d9e:	83 e0 f0             	and    $0xfffffff0,%eax
     da1:	83 e1 f0             	and    $0xfffffff0,%ecx
     da4:	c4 c1 7a 6f 04 01    	vmovdqu (%r9,%rax,1),%xmm0
     daa:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
     db3:	49 8b 04 09          	mov    (%r9,%rcx,1),%rax
     db7:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
     dbc:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
     dc3:	8d 4a 20             	lea    0x20(%rdx),%ecx
     dc6:	83 e1 f0             	and    $0xfffffff0,%ecx
     dc9:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
     dd0:	49 8b 34 09          	mov    (%r9,%rcx,1),%rsi
     dd4:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
     dd9:	49 89 8e 48 01 00 00 	mov    %rcx,0x148(%r14)
     de0:	8d 4a 30             	lea    0x30(%rdx),%ecx
     de3:	83 e1 f0             	and    $0xfffffff0,%ecx
     de6:	49 89 b6 40 01 00 00 	mov    %rsi,0x140(%r14)
     ded:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     df3:	8d 4a 40             	lea    0x40(%rdx),%ecx
     df6:	83 e1 f0             	and    $0xfffffff0,%ecx
     df9:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
     e02:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     e08:	8d 4a 50             	lea    0x50(%rdx),%ecx
     e0b:	48 83 c2 60          	add    $0x60,%rdx
     e0f:	83 e1 f0             	and    $0xfffffff0,%ecx
     e12:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
     e1b:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     e21:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
     e28:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
     e31:	84 db                	test   %bl,%bl
     e33:	0f 85 4f 08 00 00    	jne    1688 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1688>
     e39:	89 c2                	mov    %eax,%edx
     e3b:	49 8d 7c 11 68       	lea    0x68(%r9,%rdx,1),%rdi
     e40:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     e47:	8d 4a 20             	lea    0x20(%rdx),%ecx
     e4a:	83 e1 f0             	and    $0xfffffff0,%ecx
     e4d:	4d 8b 04 09          	mov    (%r9,%rcx,1),%r8
     e51:	49 8b 74 09 08       	mov    0x8(%r9,%rcx,1),%rsi
     e56:	4d 89 46 30          	mov    %r8,0x30(%r14)
     e5a:	49 89 76 38          	mov    %rsi,0x38(%r14)
     e5e:	48 63 3f             	movslq (%rdi),%rdi
     e61:	49 89 7e 40          	mov    %rdi,0x40(%r14)
     e65:	48 89 f9             	mov    %rdi,%rcx
     e68:	83 e7 04             	and    $0x4,%edi
     e6b:	89 fb                	mov    %edi,%ebx
     e6d:	49 89 5e 50          	mov    %rbx,0x50(%r14)
     e71:	f6 c1 02             	test   $0x2,%cl
     e74:	74 3e                	je     eb4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xeb4>
     e76:	49 89 f2             	mov    %rsi,%r10
     e79:	41 c7 86 c0 00 00 00 00 00 00 00 	movl   $0x0,0xc0(%r14)
     e84:	49 c1 ea 20          	shr    $0x20,%r10
     e88:	41 89 b6 c4 00 00 00 	mov    %esi,0xc4(%r14)
     e8f:	41 c7 86 c8 00 00 00 00 00 00 00 	movl   $0x0,0xc8(%r14)
     e9a:	45 89 96 cc 00 00 00 	mov    %r10d,0xcc(%r14)
     ea1:	4d 85 c0             	test   %r8,%r8
     ea4:	75 0e                	jne    eb4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xeb4>
     ea6:	49 83 be c0 00 00 00 00 	cmpq   $0x0,0xc0(%r14)
     eae:	0f 84 ac 00 00 00    	je     f60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
     eb4:	83 e1 01             	and    $0x1,%ecx
     eb7:	89 cb                	mov    %ecx,%ebx
     eb9:	49 89 5e 40          	mov    %rbx,0x40(%r14)
     ebd:	85 ff                	test   %edi,%edi
     ebf:	74 35                	je     ef6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xef6>
     ec1:	49 c7 86 c8 00 00 00 00 00 00 00 	movq   $0x0,0xc8(%r14)
     ecc:	48 89 f7             	mov    %rsi,%rdi
     ecf:	48 c1 ef 20          	shr    $0x20,%rdi
     ed3:	41 89 b6 c8 00 00 00 	mov    %esi,0xc8(%r14)
     eda:	41 c7 86 c0 00 00 00 00 00 00 00 	movl   $0x0,0xc0(%r14)
     ee5:	41 89 be c4 00 00 00 	mov    %edi,0xc4(%r14)
     eec:	49 83 be c0 00 00 00 00 	cmpq   $0x0,0xc0(%r14)
     ef4:	7e 6a                	jle    f60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
     ef6:	85 c9                	test   %ecx,%ecx
     ef8:	0f 84 12 f3 ff ff    	je     210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
     efe:	c4 c1 78 28 86 90 02 00 00 	vmovaps 0x290(%r14),%xmm0
     f07:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     f0d:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     f14:	c4 c1 78 28 86 a0 02 00 00 	vmovaps 0x2a0(%r14),%xmm0
     f1d:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     f25:	49 8b 4e 30          	mov    0x30(%r14),%rcx
     f29:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     f2f:	48 85 c9             	test   %rcx,%rcx
     f32:	78 2c                	js     f60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
     f34:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
     f3c:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     f43:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
     f4a:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     f52:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
     f57:	0f 89 b3 f2 ff ff    	jns    210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
     f5d:	0f 1f 00             	nopl   (%rax)
     f60:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # f67 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf67>	f63: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x4
     f67:	49 63 b6 f0 01 00 00 	movslq 0x1f0(%r14),%rsi
     f6e:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
     f77:	c4 c1 7a 7e a6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm4
     f80:	c4 c3 d9 22 96 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm4,%xmm2
     f8a:	48 63 09             	movslq (%rcx),%rcx
     f8d:	49 89 46 60          	mov    %rax,0x60(%r14)
     f91:	c4 c1 7a 7e a6 80 00 00 00 	vmovq  0x80(%r14),%xmm4
     f9a:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
     fa0:	c4 c3 d9 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm4,%xmm1
     faa:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
     faf:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
     fb6:	48 89 cf             	mov    %rcx,%rdi
     fb9:	49 8b 8e 10 01 00 00 	mov    0x110(%r14),%rcx
     fc0:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     fc6:	c4 e3 d9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm4,%xmm2
     fcc:	49 89 56 70          	mov    %rdx,0x70(%r14)
     fd0:	c4 e3 f9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm0,%xmm0
     fd6:	49 89 4e 50          	mov    %rcx,0x50(%r14)
     fda:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
     fe0:	49 89 76 20          	mov    %rsi,0x20(%r14)
     fe4:	c5 fd 7f 45 90       	vmovdqa %ymm0,-0x70(%rbp)
     fe9:	c5 fd 7f 4d b0       	vmovdqa %ymm1,-0x50(%rbp)
     fee:	85 ff                	test   %edi,%edi
     ff0:	0f 84 2a 08 00 00    	je     1820 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
     ff6:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     ffd:	89 ff                	mov    %edi,%edi
     fff:	31 d2                	xor    %edx,%edx
    1001:	48 8d 75 90          	lea    -0x70(%rbp),%rsi
    1005:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    100c:	4c 01 cf             	add    %r9,%rdi
    100f:	c5 f8 77             	vzeroupper
    1012:	e8 00 00 00 00       	call   1017 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1017>	1013: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    1017:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    101e:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1025 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1025>	1021: R_X86_64_PC32	g_ee_main_mem-0x4
    1025:	49 89 46 20          	mov    %rax,0x20(%r14)
    1029:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    1030:	e9 db f1 ff ff       	jmp    210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    1035:	0f 1f 00             	nopl   (%rax)
    1038:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    103f:	e9 cc f1 ff ff       	jmp    210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    1044:	0f 1f 40 00          	nopl   0x0(%rax)
    1048:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    104f:	e9 0c ff ff ff       	jmp    f60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
    1054:	0f 1f 40 00          	nopl   0x0(%rax)
    1058:	49 89 56 30          	mov    %rdx,0x30(%r14)
    105c:	e9 45 f2 ff ff       	jmp    2a6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2a6>
    1061:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    1068:	c4 41 79 6e d2       	vmovd  %r10d,%xmm10
    106d:	4c 89 d2             	mov    %r10,%rdx
    1070:	4d 8b 5e 38          	mov    0x38(%r14),%r11
    1074:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
    1078:	c5 7a 10 0d 00 00 00 00 	vmovss 0x0(%rip),%xmm9        # 1080 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1080>	107c: R_X86_64_PC32	.LC11-0x4
    1080:	c5 ca 59 db          	vmulss %xmm3,%xmm6,%xmm3
    1084:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # 108c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x108c>	1088: R_X86_64_PC32	.LC11-0x4
    108c:	48 c1 ea 20          	shr    $0x20,%rdx
    1090:	c4 c1 4a 59 f5       	vmulss %xmm13,%xmm6,%xmm6
    1095:	c4 41 32 5c ca       	vsubss %xmm10,%xmm9,%xmm9
    109a:	c4 41 1a 59 d2       	vmulss %xmm10,%xmm12,%xmm10
    109f:	c4 41 32 59 cc       	vmulss %xmm12,%xmm9,%xmm9
    10a4:	c5 e2 58 df          	vaddss %xmm7,%xmm3,%xmm3
    10a8:	c5 f9 6e f9          	vmovd  %ecx,%xmm7
    10ac:	c5 ca 58 f7          	vaddss %xmm7,%xmm6,%xmm6
    10b0:	c4 41 7a 5c c9       	vsubss %xmm9,%xmm0,%xmm9
    10b5:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    10b9:	c5 9a 59 c0          	vmulss %xmm0,%xmm12,%xmm0
    10bd:	c4 c1 6a 59 d1       	vmulss %xmm9,%xmm2,%xmm2
    10c2:	c4 c1 7a 12 f9       	vmovsldup %xmm9,%xmm7
    10c7:	c4 c1 62 59 d9       	vmulss %xmm9,%xmm3,%xmm3
    10cc:	c4 c1 4a 59 f1       	vmulss %xmm9,%xmm6,%xmm6
    10d1:	c5 f9 7e c2          	vmovd  %xmm0,%edx
    10d5:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
    10da:	c5 1a 59 e0          	vmulss %xmm0,%xmm12,%xmm12
    10de:	c5 fa 7e ff          	vmovq  %xmm7,%xmm7
    10e2:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    10e6:	c5 c0 59 c9          	vmulps %xmm1,%xmm7,%xmm1
    10ea:	c5 28 14 d0          	vunpcklps %xmm0,%xmm10,%xmm10
    10ee:	c4 c1 7a 11 96 c8 02 00 00 	vmovss %xmm2,0x2c8(%r14)
    10f7:	c4 41 18 14 e1       	vunpcklps %xmm9,%xmm12,%xmm12
    10fc:	c4 c1 78 13 8e c0 02 00 00 	vmovlps %xmm1,0x2c0(%r14)
    1105:	c4 41 28 16 d4       	vmovlhps %xmm12,%xmm10,%xmm10
    110a:	c4 41 78 29 96 00 03 00 00 	vmovaps %xmm10,0x300(%r14)
    1113:	e9 55 f6 ff ff       	jmp    76d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x76d>
    1118:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
    1120:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
    1127:	49 89 46 20          	mov    %rax,0x20(%r14)
    112b:	89 d1                	mov    %edx,%ecx
    112d:	49 8b 0c 09          	mov    (%r9,%rcx,1),%rcx
    1131:	49 89 8e f0 01 00 00 	mov    %rcx,0x1f0(%r14)
    1138:	8d 4a 70             	lea    0x70(%rdx),%ecx
    113b:	83 e1 f0             	and    $0xfffffff0,%ecx
    113e:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1144:	8d 4a 60             	lea    0x60(%rdx),%ecx
    1147:	83 e1 f0             	and    $0xfffffff0,%ecx
    114a:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    1153:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1159:	8d 4a 50             	lea    0x50(%rdx),%ecx
    115c:	83 e1 f0             	and    $0xfffffff0,%ecx
    115f:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    1168:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    116e:	8d 4a 40             	lea    0x40(%rdx),%ecx
    1171:	83 e1 f0             	and    $0xfffffff0,%ecx
    1174:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    117d:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1183:	8d 4a 30             	lea    0x30(%rdx),%ecx
    1186:	83 e1 f0             	and    $0xfffffff0,%ecx
    1189:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    1192:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1198:	8d 4a 20             	lea    0x20(%rdx),%ecx
    119b:	83 e1 f0             	and    $0xfffffff0,%ecx
    119e:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    11a7:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    11ad:	8d 4a 10             	lea    0x10(%rdx),%ecx
    11b0:	48 83 ea 80          	sub    $0xffffffffffffff80,%rdx
    11b4:	83 e1 f0             	and    $0xfffffff0,%ecx
    11b7:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    11c0:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    11c6:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    11cd:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
    11d6:	48 8d 65 d0          	lea    -0x30(%rbp),%rsp
    11da:	5b                   	pop    %rbx
    11db:	41 5a                	pop    %r10
    11dd:	41 5c                	pop    %r12
    11df:	41 5d                	pop    %r13
    11e1:	41 5e                	pop    %r14
    11e3:	41 5f                	pop    %r15
    11e5:	5d                   	pop    %rbp
    11e6:	49 8d 62 f8          	lea    -0x8(%r10),%rsp
    11ea:	c3                   	ret
    11eb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    11f0:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
    11f9:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    1200:	48 8d 50 a0          	lea    -0x60(%rax),%rdx
    1204:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 120b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x120b>	1207: R_X86_64_PC32	g_ee_main_mem-0x4
    120b:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    1212:	83 e2 f0             	and    $0xfffffff0,%edx
    1215:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    121a:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    1221:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
    122a:	8d 53 10             	lea    0x10(%rbx),%edx
    122d:	83 e2 f0             	and    $0xfffffff0,%edx
    1230:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    1235:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    123c:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
    1245:	8d 53 20             	lea    0x20(%rbx),%edx
    1248:	83 e2 f0             	and    $0xfffffff0,%edx
    124b:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    1250:	49 8b be 10 01 00 00 	mov    0x110(%r14),%rdi
    1257:	49 8b b6 18 01 00 00 	mov    0x118(%r14),%rsi
    125e:	48 89 bd b0 fe ff ff 	mov    %rdi,-0x150(%rbp)
    1265:	41 8b be d0 01 00 00 	mov    0x1d0(%r14),%edi
    126c:	48 8b 9d b0 fe ff ff 	mov    -0x150(%rbp),%rbx
    1273:	48 89 b5 b8 fe ff ff 	mov    %rsi,-0x148(%rbp)
    127a:	8d 57 30             	lea    0x30(%rdi),%edx
    127d:	83 e2 f0             	and    $0xfffffff0,%edx
    1280:	48 89 9d b0 fe ff ff 	mov    %rbx,-0x150(%rbp)
    1287:	48 89 1c 10          	mov    %rbx,(%rax,%rdx,1)
    128b:	48 89 74 10 08       	mov    %rsi,0x8(%rax,%rdx,1)
    1290:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    1297:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
    12a0:	8d 53 40             	lea    0x40(%rbx),%edx
    12a3:	83 e2 f0             	and    $0xfffffff0,%edx
    12a6:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    12ab:	49 8b be 20 01 00 00 	mov    0x120(%r14),%rdi
    12b2:	49 8b b6 28 01 00 00 	mov    0x128(%r14),%rsi
    12b9:	48 89 bd a0 fe ff ff 	mov    %rdi,-0x160(%rbp)
    12c0:	41 8b be d0 01 00 00 	mov    0x1d0(%r14),%edi
    12c7:	48 8b 9d a0 fe ff ff 	mov    -0x160(%rbp),%rbx
    12ce:	48 89 b5 a8 fe ff ff 	mov    %rsi,-0x158(%rbp)
    12d5:	8d 57 50             	lea    0x50(%rdi),%edx
    12d8:	83 e2 f0             	and    $0xfffffff0,%edx
    12db:	48 89 9d a0 fe ff ff 	mov    %rbx,-0x160(%rbp)
    12e2:	48 89 1c 10          	mov    %rbx,(%rax,%rdx,1)
    12e6:	48 89 74 10 08       	mov    %rsi,0x8(%rax,%rdx,1)
    12eb:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
    12f2:	49 89 46 40          	mov    %rax,0x40(%r14)
    12f6:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
    12fd:	49 89 46 70          	mov    %rax,0x70(%r14)
    1301:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    1308:	49 89 46 60          	mov    %rax,0x60(%r14)
    130c:	e8 00 00 00 00       	call   1311 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1311>	130d: R_X86_64_PC32	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv-0x4
    1311:	89 c3                	mov    %eax,%ebx
    1313:	84 c0                	test   %al,%al
    1315:	74 13                	je     132a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x132a>
    1317:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 131d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x131d>	1319: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count_0-0x4
    131d:	3d 3f 1f 00 00       	cmp    $0x1f3f,%eax
    1322:	0f 8e f1 03 00 00    	jle    1719 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1719>
    1328:	31 db                	xor    %ebx,%ebx
    132a:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1331 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1331>	132d: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x14
    1331:	48 63 10             	movslq (%rax),%rdx
    1334:	49 89 96 90 01 00 00 	mov    %rdx,0x190(%r14)
    133b:	48 89 d0             	mov    %rdx,%rax
    133e:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
    1345:	49 89 56 20          	mov    %rdx,0x20(%r14)
    1349:	49 8b 56 40          	mov    0x40(%r14),%rdx
    134d:	48 89 95 10 ff ff ff 	mov    %rdx,-0xf0(%rbp)
    1354:	49 8b 56 50          	mov    0x50(%r14),%rdx
    1358:	48 89 95 18 ff ff ff 	mov    %rdx,-0xe8(%rbp)
    135f:	49 8b 56 60          	mov    0x60(%r14),%rdx
    1363:	48 89 95 20 ff ff ff 	mov    %rdx,-0xe0(%rbp)
    136a:	49 8b 56 70          	mov    0x70(%r14),%rdx
    136e:	48 89 95 28 ff ff ff 	mov    %rdx,-0xd8(%rbp)
    1375:	49 8b 96 80 00 00 00 	mov    0x80(%r14),%rdx
    137c:	48 89 95 30 ff ff ff 	mov    %rdx,-0xd0(%rbp)
    1383:	49 8b 96 90 00 00 00 	mov    0x90(%r14),%rdx
    138a:	48 89 95 38 ff ff ff 	mov    %rdx,-0xc8(%rbp)
    1391:	49 8b 96 a0 00 00 00 	mov    0xa0(%r14),%rdx
    1398:	48 89 95 40 ff ff ff 	mov    %rdx,-0xc0(%rbp)
    139f:	49 8b 96 b0 00 00 00 	mov    0xb0(%r14),%rdx
    13a6:	48 89 95 48 ff ff ff 	mov    %rdx,-0xb8(%rbp)
    13ad:	85 c0                	test   %eax,%eax
    13af:	0f 84 6e 04 00 00    	je     1823 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1823>
    13b5:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 13bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13bc>	13b8: R_X86_64_PC32	g_ee_main_mem-0x4
    13bc:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    13c3:	89 c0                	mov    %eax,%eax
    13c5:	48 8d b5 10 ff ff ff 	lea    -0xf0(%rbp),%rsi
    13cc:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    13d3:	31 d2                	xor    %edx,%edx
    13d5:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
    13d9:	e8 00 00 00 00       	call   13de <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13de>	13da: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    13de:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
    13e5:	49 89 46 20          	mov    %rax,0x20(%r14)
    13e9:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 13f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13f0>	13ec: R_X86_64_PC32	g_ee_main_mem-0x4
    13f0:	48 89 d1             	mov    %rdx,%rcx
    13f3:	83 e1 f0             	and    $0xfffffff0,%ecx
    13f6:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    13fb:	8d 4a 10             	lea    0x10(%rdx),%ecx
    13fe:	83 e1 f0             	and    $0xfffffff0,%ecx
    1401:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    140a:	48 8b 3c 08          	mov    (%rax,%rcx,1),%rdi
    140e:	48 8b 4c 08 08       	mov    0x8(%rax,%rcx,1),%rcx
    1413:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
    141a:	8d 4a 20             	lea    0x20(%rdx),%ecx
    141d:	83 e1 f0             	and    $0xfffffff0,%ecx
    1420:	49 89 be 50 01 00 00 	mov    %rdi,0x150(%r14)
    1427:	48 8b 34 08          	mov    (%rax,%rcx,1),%rsi
    142b:	48 8b 4c 08 08       	mov    0x8(%rax,%rcx,1),%rcx
    1430:	49 89 8e 48 01 00 00 	mov    %rcx,0x148(%r14)
    1437:	8d 4a 30             	lea    0x30(%rdx),%ecx
    143a:	83 e1 f0             	and    $0xfffffff0,%ecx
    143d:	49 89 b6 40 01 00 00 	mov    %rsi,0x140(%r14)
    1444:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    1449:	8d 4a 40             	lea    0x40(%rdx),%ecx
    144c:	83 e1 f0             	and    $0xfffffff0,%ecx
    144f:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    1458:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    145d:	8d 4a 50             	lea    0x50(%rdx),%ecx
    1460:	48 83 c2 60          	add    $0x60,%rdx
    1464:	83 e1 f0             	and    $0xfffffff0,%ecx
    1467:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    1470:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    1475:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    147c:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    1485:	84 db                	test   %bl,%bl
    1487:	0f 84 1d f1 ff ff    	je     5aa <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
    148d:	89 f9                	mov    %edi,%ecx
    148f:	89 ff                	mov    %edi,%edi
    1491:	c4 41 01 57 ff       	vxorpd %xmm15,%xmm15,%xmm15
    1496:	89 f6                	mov    %esi,%esi
    1498:	48 8b 54 38 10       	mov    0x10(%rax,%rdi,1),%rdx
    149d:	48 83 ec 10          	sub    $0x10,%rsp
    14a1:	c5 82 5a 04 30       	vcvtss2sd (%rax,%rsi,1),%xmm15,%xmm0
    14a6:	c5 79 28 c0          	vmovapd %xmm0,%xmm8
    14aa:	c5 82 5a 7c 38 10    	vcvtss2sd 0x10(%rax,%rdi,1),%xmm15,%xmm7
    14b0:	c5 82 5a 44 38 18    	vcvtss2sd 0x18(%rax,%rdi,1),%xmm15,%xmm0
    14b6:	c5 82 5a 74 30 2c    	vcvtss2sd 0x2c(%rax,%rsi,1),%xmm15,%xmm6
    14bc:	c5 82 5a 6c 30 28    	vcvtss2sd 0x28(%rax,%rsi,1),%xmm15,%xmm5
    14c2:	48 c1 ea 20          	shr    $0x20,%rdx
    14c6:	c5 82 5a 64 30 24    	vcvtss2sd 0x24(%rax,%rsi,1),%xmm15,%xmm4
    14cc:	c5 82 5a 5c 30 20    	vcvtss2sd 0x20(%rax,%rsi,1),%xmm15,%xmm3
    14d2:	c5 82 5a 54 30 08    	vcvtss2sd 0x8(%rax,%rsi,1),%xmm15,%xmm2
    14d8:	c5 82 5a 4c 30 04    	vcvtss2sd 0x4(%rax,%rsi,1),%xmm15,%xmm1
    14de:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
    14e4:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    14e8:	89 ce                	mov    %ecx,%esi
    14ea:	bf 00 00 00 00       	mov    $0x0,%edi	14eb: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d7executeEPv.str1.8+0x78
    14ef:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    14f3:	b8 08 00 00 00       	mov    $0x8,%eax
    14f8:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
    14fd:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
    1501:	e8 00 00 00 00       	call   1506 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1506>	1502: R_X86_64_PLT32	printf-0x4
    1506:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 150d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x150d>	1509: R_X86_64_PC32	stdout-0x4
    150d:	59                   	pop    %rcx
    150e:	5e                   	pop    %rsi
    150f:	e8 00 00 00 00       	call   1514 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1514>	1510: R_X86_64_PLT32	fflush-0x4
    1514:	e9 91 f0 ff ff       	jmp    5aa <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
    1519:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    1520:	c4 e1 f9 6e f7       	vmovq  %rdi,%xmm6
    1525:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
    152a:	c5 f8 2f 35 00 00 00 00 	vcomiss 0x0(%rip),%xmm6        # 1532 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1532>	152e: R_X86_64_PC32	.LC21-0x4
    1532:	c5 f9 6f ce          	vmovdqa %xmm6,%xmm1
    1536:	0f 86 84 f4 ff ff    	jbe    9c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    153c:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    1540:	c5 f8 2e d0          	vucomiss %xmm0,%xmm2
    1544:	0f 8a 76 f4 ff ff    	jp     9c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    154a:	0f 85 70 f4 ff ff    	jne    9c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    1550:	4c 8b 5c 10 10       	mov    0x10(%rax,%rdx,1),%r11
    1555:	83 c1 01             	add    $0x1,%ecx
    1558:	48 83 ec 30          	sub    $0x30,%rsp
    155c:	c5 d1 57 ed          	vxorpd %xmm5,%xmm5,%xmm5
    1560:	48 8b 7c 10 08       	mov    0x8(%rax,%rdx,1),%rdi
    1565:	89 0d 00 00 00 00    	mov    %ecx,0x0(%rip)        # 156b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x156b>	1567: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count_1-0x4
    156b:	c5 d2 5a 44 10 1c    	vcvtss2sd 0x1c(%rax,%rdx,1),%xmm5,%xmm0
    1571:	c4 c1 f9 6e f2       	vmovq  %r10,%xmm6
    1576:	48 8b 0c 10          	mov    (%rax,%rdx,1),%rcx
    157a:	49 c1 e9 20          	shr    $0x20,%r9
    157e:	49 c1 e8 20          	shr    $0x20,%r8
    1582:	c5 fb 11 44 24 20    	vmovsd %xmm0,0x20(%rsp)
    1588:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
    158d:	c4 c1 79 6e d8       	vmovd  %r8d,%xmm3
    1592:	c4 41 3a 5a c0       	vcvtss2sd %xmm8,%xmm8,%xmm8
    1597:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
    159c:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    15a0:	c5 f9 6f fe          	vmovdqa %xmm6,%xmm7
    15a4:	c5 fb 11 44 24 18    	vmovsd %xmm0,0x18(%rsp)
    15aa:	c4 e1 f9 6e e9       	vmovq  %rcx,%xmm5
    15af:	c5 f9 6e c7          	vmovd  %edi,%xmm0
    15b3:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
    15b8:	c4 c1 79 6e f2       	vmovd  %r10d,%xmm6
    15bd:	bf 00 00 00 00       	mov    $0x0,%edi	15be: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d7executeEPv.str1.8+0xc8
    15c2:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    15c6:	c5 c2 5a ff          	vcvtss2sd %xmm7,%xmm7,%xmm7
    15ca:	c5 ca 5a f6          	vcvtss2sd %xmm6,%xmm6,%xmm6
    15ce:	c5 da 5a e4          	vcvtss2sd %xmm4,%xmm4,%xmm4
    15d2:	c5 fb 11 44 24 10    	vmovsd %xmm0,0x10(%rsp)
    15d8:	c5 d2 5a c5          	vcvtss2sd %xmm5,%xmm5,%xmm0
    15dc:	c4 c1 79 6e e9       	vmovd  %r9d,%xmm5
    15e1:	c5 e2 5a db          	vcvtss2sd %xmm3,%xmm3,%xmm3
    15e5:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
    15eb:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
    15ef:	c5 d2 5a ed          	vcvtss2sd %xmm5,%xmm5,%xmm5
    15f3:	c5 ea 5a d2          	vcvtss2sd %xmm2,%xmm2,%xmm2
    15f7:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    15fb:	b8 08 00 00 00       	mov    $0x8,%eax
    1600:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
    1605:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
    1609:	c5 f2 5a c9          	vcvtss2sd %xmm1,%xmm1,%xmm1
    160d:	e8 00 00 00 00       	call   1612 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1612>	160e: R_X86_64_PLT32	printf-0x4
    1612:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 1619 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1619>	1615: R_X86_64_PC32	stdout-0x4
    1619:	48 83 c4 30          	add    $0x30,%rsp
    161d:	e8 00 00 00 00       	call   1622 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1622>	161e: R_X86_64_PLT32	fflush-0x4
    1622:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1629 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1629>	1625: R_X86_64_PC32	g_ee_main_mem-0x4
    1629:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
    1630:	e9 ab f3 ff ff       	jmp    9e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
    1635:	0f 1f 00             	nopl   (%rax)
    1638:	31 db                	xor    %ebx,%ebx
    163a:	e9 e2 f5 ff ff       	jmp    c21 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>
    163f:	90                   	nop
    1640:	83 c2 01             	add    $0x1,%edx
    1643:	41 8b 4c 01 74       	mov    0x74(%r9,%rax,1),%ecx
    1648:	45 8b 44 01 78       	mov    0x78(%r9,%rax,1),%r8d
    164d:	bf 00 00 00 00       	mov    $0x0,%edi	164e: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d7executeEPv.str1.8
    1652:	89 15 00 00 00 00    	mov    %edx,0x0(%rip)        # 1658 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1658>	1654: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count-0x4
    1658:	41 8b 54 01 70       	mov    0x70(%r9,%rax,1),%edx
    165d:	31 c0                	xor    %eax,%eax
    165f:	e8 00 00 00 00       	call   1664 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1664>	1660: R_X86_64_PLT32	printf-0x4
    1664:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 166b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x166b>	1667: R_X86_64_PC32	stdout-0x4
    166b:	e8 00 00 00 00       	call   1670 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1670>	166c: R_X86_64_PLT32	fflush-0x4
    1670:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
    1677:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 167e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x167e>	167a: R_X86_64_PC32	g_ee_main_mem-0x4
    167e:	e9 ed ee ff ff       	jmp    570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
    1683:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    1688:	c4 41 09 57 f6       	vxorpd %xmm14,%xmm14,%xmm14
    168d:	48 83 ec 10          	sub    $0x10,%rsp
    1691:	89 c2                	mov    %eax,%edx
    1693:	89 f6                	mov    %esi,%esi
    1695:	89 c0                	mov    %eax,%eax
    1697:	c4 c1 0a 5a 7c 31 04 	vcvtss2sd 0x4(%r9,%rsi,1),%xmm14,%xmm7
    169e:	c4 c1 0a 5a 34 31    	vcvtss2sd (%r9,%rsi,1),%xmm14,%xmm6
    16a4:	c4 41 0a 5a 44 31 08 	vcvtss2sd 0x8(%r9,%rsi,1),%xmm14,%xmm8
    16ab:	c4 c1 0a 5a 6c 01 5c 	vcvtss2sd 0x5c(%r9,%rax,1),%xmm14,%xmm5
    16b2:	c4 c1 0a 5a 64 01 58 	vcvtss2sd 0x58(%r9,%rax,1),%xmm14,%xmm4
    16b9:	89 d6                	mov    %edx,%esi
    16bb:	c4 c1 0a 5a 5c 01 54 	vcvtss2sd 0x54(%r9,%rax,1),%xmm14,%xmm3
    16c2:	c4 c1 0a 5a 54 01 50 	vcvtss2sd 0x50(%r9,%rax,1),%xmm14,%xmm2
    16c9:	c4 c1 0a 5a 4c 01 08 	vcvtss2sd 0x8(%r9,%rax,1),%xmm14,%xmm1
    16d0:	bf 00 00 00 00       	mov    $0x0,%edi	16d1: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d7executeEPv.str1.8+0x1b0
    16d5:	c4 c1 0a 5a 44 01 0c 	vcvtss2sd 0xc(%r9,%rax,1),%xmm14,%xmm0
    16dc:	c5 7b 11 04 24       	vmovsd %xmm8,(%rsp)
    16e1:	b8 08 00 00 00       	mov    $0x8,%eax
    16e6:	e8 00 00 00 00       	call   16eb <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16eb>	16e7: R_X86_64_PLT32	printf-0x4
    16eb:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 16f2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16f2>	16ee: R_X86_64_PC32	stdout-0x4
    16f2:	58                   	pop    %rax
    16f3:	5a                   	pop    %rdx
    16f4:	e8 00 00 00 00       	call   16f9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16f9>	16f5: R_X86_64_PLT32	fflush-0x4
    16f9:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    1700:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1707 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1707>	1703: R_X86_64_PC32	g_ee_main_mem-0x4
    1707:	e9 2d f7 ff ff       	jmp    e39 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe39>
    170c:	48 c1 ef 20          	shr    $0x20,%rdi
    1710:	c5 f9 6e cf          	vmovd  %edi,%xmm1
    1714:	e9 37 fe ff ff       	jmp    1550 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1550>
    1719:	83 c0 01             	add    $0x1,%eax
    171c:	41 8b 8e 50 01 00 00 	mov    0x150(%r14),%ecx
    1723:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
    172a:	c5 d9 57 e4          	vxorpd %xmm4,%xmm4,%xmm4
    172e:	89 05 00 00 00 00    	mov    %eax,0x0(%rip)        # 1734 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1734>	1730: R_X86_64_PC32	.bss._ZZN6Mips2C4jak119sp_process_block_2d7executeEPvE7s_count_0-0x4
    1734:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 173b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x173b>	1737: R_X86_64_PC32	g_ee_main_mem-0x4
    173b:	c5 f9 28 fc          	vmovapd %xmm4,%xmm7
    173f:	8b 74 08 70          	mov    0x70(%rax,%rcx,1),%esi
    1743:	8b 7c 08 78          	mov    0x78(%rax,%rcx,1),%edi
    1747:	c5 da 5a 04 10       	vcvtss2sd (%rax,%rdx,1),%xmm4,%xmm0
    174c:	c5 da 5a 74 10 2c    	vcvtss2sd 0x2c(%rax,%rdx,1),%xmm4,%xmm6
    1752:	c5 da 5a 6c 10 28    	vcvtss2sd 0x28(%rax,%rdx,1),%xmm4,%xmm5
    1758:	c5 c2 5a 5c 10 20    	vcvtss2sd 0x20(%rax,%rdx,1),%xmm7,%xmm3
    175e:	c5 da 5a 64 10 24    	vcvtss2sd 0x24(%rax,%rdx,1),%xmm4,%xmm4
    1764:	c5 c2 5a 54 10 08    	vcvtss2sd 0x8(%rax,%rdx,1),%xmm7,%xmm2
    176a:	c5 c2 5a 4c 10 04    	vcvtss2sd 0x4(%rax,%rdx,1),%xmm7,%xmm1
    1770:	89 f2                	mov    %esi,%edx
    1772:	89 f9                	mov    %edi,%ecx
    1774:	41 8b b6 50 01 00 00 	mov    0x150(%r14),%esi
    177b:	bf 00 00 00 00       	mov    $0x0,%edi	177c: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d7executeEPv.str1.8+0x28
    1780:	b8 07 00 00 00       	mov    $0x7,%eax
    1785:	e8 00 00 00 00       	call   178a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x178a>	1786: R_X86_64_PLT32	printf-0x4
    178a:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 1791 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1791>	178d: R_X86_64_PC32	stdout-0x4
    1791:	e8 00 00 00 00       	call   1796 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1796>	1792: R_X86_64_PLT32	fflush-0x4
    1796:	e9 8f fb ff ff       	jmp    132a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x132a>
    179b:	45 89 e3             	mov    %r12d,%r11d
    179e:	c5 e9 57 d2          	vxorpd %xmm2,%xmm2,%xmm2
    17a2:	49 01 c3             	add    %rax,%r11
    17a5:	4d 8b 3b             	mov    (%r11),%r15
    17a8:	45 8b 5b 08          	mov    0x8(%r11),%r11d
    17ac:	44 89 9d cc fe ff ff 	mov    %r11d,-0x134(%rbp)
    17b3:	4c 89 bd c4 fe ff ff 	mov    %r15,-0x13c(%rbp)
    17ba:	c5 ea 5a a5 cc fe ff ff 	vcvtss2sd -0x134(%rbp),%xmm2,%xmm4
    17c2:	c5 79 28 d4          	vmovapd %xmm4,%xmm10
    17c6:	c5 f9 28 e2          	vmovapd %xmm2,%xmm4
    17ca:	c5 5a 5a 8d c4 fe ff ff 	vcvtss2sd -0x13c(%rbp),%xmm4,%xmm9
    17d2:	c5 ea 5a 95 c8 fe ff ff 	vcvtss2sd -0x138(%rbp),%xmm2,%xmm2
    17da:	e9 ff f2 ff ff       	jmp    ade <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xade>
    17df:	41 b8 00 00 00 00    	mov    $0x0,%r8d	17e1: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    17e5:	b9 00 00 00 00       	mov    $0x0,%ecx	17e6: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8
    17ea:	ba 58 01 00 00       	mov    $0x158,%edx
    17ef:	be 00 00 00 00       	mov    $0x0,%esi	17f0: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x38
    17f4:	bf 00 00 00 00       	mov    $0x0,%edi	17f5: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x78
    17f9:	e8 00 00 00 00       	call   17fe <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>	17fa: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    17fe:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1800: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    1804:	b9 00 00 00 00       	mov    $0x0,%ecx	1805: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x1d8
    1809:	ba c0 01 00 00       	mov    $0x1c0,%edx
    180e:	be 00 00 00 00       	mov    $0x0,%esi	180f: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x38
    1813:	bf 00 00 00 00       	mov    $0x0,%edi	1814: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x210
    1818:	c5 f8 77             	vzeroupper
    181b:	e8 00 00 00 00       	call   1820 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>	181c: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    1820:	c5 f8 77             	vzeroupper
    1823:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1825: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1
    1829:	b9 00 00 00 00       	mov    $0x0,%ecx	182a: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0xa8
    182e:	ba 90 01 00 00       	mov    $0x190,%edx
    1833:	be 00 00 00 00       	mov    $0x0,%esi	1834: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.8+0x38
    1838:	bf 00 00 00 00       	mov    $0x0,%edi	1839: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d7executeEPv.str1.1+0x1
    183d:	e8 00 00 00 00       	call   1842 <.LC24+0x1832>	183e: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4

Disassembly of section .text.unlikely._ZN6Mips2C4jak119sp_process_block_3d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::link() [clone .cold]>:
   0:	48 8b 3c 24          	mov    (%rsp),%rdi
   4:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
   9:	48 39 c7             	cmp    %rax,%rdi
   c:	75 0b                	jne    19 <Mips2C::jak1::sp_process_block_3d::link() [clone .cold]+0x19>
   e:	c5 f8 77             	vzeroupper
  11:	48 89 df             	mov    %rbx,%rdi
  14:	e8 00 00 00 00       	call   19 <Mips2C::jak1::sp_process_block_3d::link() [clone .cold]+0x19>	15: R_X86_64_PLT32	_Unwind_Resume-0x4
  19:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
  1e:	48 8d 70 01          	lea    0x1(%rax),%rsi
  22:	c5 f8 77             	vzeroupper
  25:	e8 00 00 00 00       	call   2a <Mips2C::jak1::sp_process_block_3d::link() [clone .cold]+0x2a>	26: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
  2a:	eb e5                	jmp    11 <Mips2C::jak1::sp_process_block_3d::link() [clone .cold]+0x11>

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::link()>:
   0:	53                   	push   %rbx
   1:	bf 00 00 00 00       	mov    $0x0,%edi	2: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d4linkEv.str1.1
   6:	48 83 ec 20          	sub    $0x20,%rsp
   a:	e8 00 00 00 00       	call   f <Mips2C::jak1::sp_process_block_3d::link()+0xf>	b: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
   f:	bf 00 00 00 00       	mov    $0x0,%edi	10: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d4linkEv.str1.1+0x10
  14:	89 c2                	mov    %eax,%edx
  16:	89 c0                	mov    %eax,%eax
  18:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 1f <Mips2C::jak1::sp_process_block_3d::link()+0x1f>	1b: R_X86_64_PC32	g_ee_main_mem-0x4
  1f:	85 d2                	test   %edx,%edx
  21:	ba 00 00 00 00       	mov    $0x0,%edx
  26:	48 0f 44 c2          	cmove  %rdx,%rax
  2a:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 31 <Mips2C::jak1::sp_process_block_3d::link()+0x31>	2d: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
  31:	e8 00 00 00 00       	call   36 <Mips2C::jak1::sp_process_block_3d::link()+0x36>	32: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
  36:	bf 00 00 00 00       	mov    $0x0,%edi	37: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d4linkEv.str1.1+0x1d
  3b:	89 c2                	mov    %eax,%edx
  3d:	89 c0                	mov    %eax,%eax
  3f:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 46 <Mips2C::jak1::sp_process_block_3d::link()+0x46>	42: R_X86_64_PC32	g_ee_main_mem-0x4
  46:	85 d2                	test   %edx,%edx
  48:	ba 00 00 00 00       	mov    $0x0,%edx
  4d:	48 0f 44 c2          	cmove  %rdx,%rax
  51:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 58 <Mips2C::jak1::sp_process_block_3d::link()+0x58>	54: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
  58:	e8 00 00 00 00       	call   5d <Mips2C::jak1::sp_process_block_3d::link()+0x5d>	59: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
  5d:	bf 00 00 00 00       	mov    $0x0,%edi	5e: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d4linkEv.str1.1+0x2e
  62:	89 c2                	mov    %eax,%edx
  64:	89 c0                	mov    %eax,%eax
  66:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 6d <Mips2C::jak1::sp_process_block_3d::link()+0x6d>	69: R_X86_64_PC32	g_ee_main_mem-0x4
  6d:	85 d2                	test   %edx,%edx
  6f:	ba 00 00 00 00       	mov    $0x0,%edx
  74:	48 0f 44 c2          	cmove  %rdx,%rax
  78:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 7f <Mips2C::jak1::sp_process_block_3d::link()+0x7f>	7b: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
  7f:	e8 00 00 00 00       	call   84 <Mips2C::jak1::sp_process_block_3d::link()+0x84>	80: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
  84:	bf 14 00 00 00       	mov    $0x14,%edi
  89:	89 c2                	mov    %eax,%edx
  8b:	89 c0                	mov    %eax,%eax
  8d:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 94 <Mips2C::jak1::sp_process_block_3d::link()+0x94>	90: R_X86_64_PC32	g_ee_main_mem-0x4
  94:	85 d2                	test   %edx,%edx
  96:	ba 00 00 00 00       	mov    $0x0,%edx
  9b:	48 0f 44 c2          	cmove  %rdx,%rax
  9f:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # a6 <Mips2C::jak1::sp_process_block_3d::link()+0xa6>	a2: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
  a6:	e8 00 00 00 00       	call   ab <Mips2C::jak1::sp_process_block_3d::link()+0xab>	a7: R_X86_64_PLT32	operator new(unsigned long)-0x4
  ab:	c5 f9 6f 05 00 00 00 00 	vmovdqa 0x0(%rip),%xmm0        # b3 <Mips2C::jak1::sp_process_block_3d::link()+0xb3>	af: R_X86_64_PC32	.LC32-0x4
  b3:	48 89 e6             	mov    %rsp,%rsi
  b6:	b9 00 01 00 00       	mov    $0x100,%ecx
  bb:	c6 40 13 00          	movb   $0x0,0x13(%rax)
  bf:	ba 00 00 00 00       	mov    $0x0,%edx	c0: R_X86_64_32	Mips2C::jak1::sp_process_block_3d::execute(void*)
  c4:	bf 00 00 00 00       	mov    $0x0,%edi	c5: R_X86_64_32	Mips2C::gLinkedFunctionTable
  c9:	c5 fa 7f 00          	vmovdqu %xmm0,(%rax)
  cd:	c7 40 0f 6b 2d 33 64 	movl   $0x64332d6b,0xf(%rax)
  d4:	48 89 04 24          	mov    %rax,(%rsp)
  d8:	48 c7 44 24 10 13 00 00 00 	movq   $0x13,0x10(%rsp)
  e1:	48 c7 44 24 08 13 00 00 00 	movq   $0x13,0x8(%rsp)
  ea:	e8 00 00 00 00       	call   ef <Mips2C::jak1::sp_process_block_3d::link()+0xef>	eb: R_X86_64_PLT32	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)-0x4
  ef:	48 8b 3c 24          	mov    (%rsp),%rdi
  f3:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
  f8:	48 39 c7             	cmp    %rax,%rdi
  fb:	74 0e                	je     10b <Mips2C::jak1::sp_process_block_3d::link()+0x10b>
  fd:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 102:	48 8d 70 01          	lea    0x1(%rax),%rsi
 106:	e8 00 00 00 00       	call   10b <Mips2C::jak1::sp_process_block_3d::link()+0x10b>	107: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
 10b:	48 83 c4 20          	add    $0x20,%rsp
 10f:	5b                   	pop    %rbx
 110:	c3                   	ret
 111:	48 89 c3             	mov    %rax,%rbx
 114:	e9 00 00 00 00       	jmp    119 <.LC24+0x109>	115: R_X86_64_PC32	.text.unlikely._ZN6Mips2C4jak119sp_process_block_3d4linkEv-0x4

Disassembly of section .text.unlikely._ZN6Mips2C4jak119sp_process_block_2d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]>:
   0:	48 8b 3c 24          	mov    (%rsp),%rdi
   4:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
   9:	48 39 c7             	cmp    %rax,%rdi
   c:	75 0b                	jne    19 <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x19>
   e:	c5 f8 77             	vzeroupper
  11:	48 89 df             	mov    %rbx,%rdi
  14:	e8 00 00 00 00       	call   19 <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x19>	15: R_X86_64_PLT32	_Unwind_Resume-0x4
  19:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
  1e:	48 8d 70 01          	lea    0x1(%rax),%rsi
  22:	c5 f8 77             	vzeroupper
  25:	e8 00 00 00 00       	call   2a <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x2a>	26: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
  2a:	eb e5                	jmp    11 <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x11>

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::link()>:
   0:	53                   	push   %rbx
   1:	bf 00 00 00 00       	mov    $0x0,%edi	2: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d4linkEv.str1.1
   6:	48 83 ec 20          	sub    $0x20,%rsp
   a:	e8 00 00 00 00       	call   f <Mips2C::jak1::sp_process_block_2d::link()+0xf>	b: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
   f:	bf 00 00 00 00       	mov    $0x0,%edi	10: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_3d4linkEv.str1.1+0x1d
  14:	89 c2                	mov    %eax,%edx
  16:	89 c0                	mov    %eax,%eax
  18:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 1f <Mips2C::jak1::sp_process_block_2d::link()+0x1f>	1b: R_X86_64_PC32	g_ee_main_mem-0x4
  1f:	85 d2                	test   %edx,%edx
  21:	ba 00 00 00 00       	mov    $0x0,%edx
  26:	48 0f 44 c2          	cmove  %rdx,%rax
  2a:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 31 <Mips2C::jak1::sp_process_block_2d::link()+0x31>	2d: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
  31:	e8 00 00 00 00       	call   36 <Mips2C::jak1::sp_process_block_2d::link()+0x36>	32: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
  36:	bf 00 00 00 00       	mov    $0x0,%edi	37: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d4linkEv.str1.1
  3b:	89 c2                	mov    %eax,%edx
  3d:	89 c0                	mov    %eax,%eax
  3f:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 46 <Mips2C::jak1::sp_process_block_2d::link()+0x46>	42: R_X86_64_PC32	g_ee_main_mem-0x4
  46:	85 d2                	test   %edx,%edx
  48:	ba 00 00 00 00       	mov    $0x0,%edx
  4d:	48 0f 44 c2          	cmove  %rdx,%rax
  51:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 58 <Mips2C::jak1::sp_process_block_2d::link()+0x58>	54: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x4
  58:	e8 00 00 00 00       	call   5d <Mips2C::jak1::sp_process_block_2d::link()+0x5d>	59: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
  5d:	bf 00 00 00 00       	mov    $0x0,%edi	5e: R_X86_64_32	.rodata._ZN6Mips2C4jak119sp_process_block_2d4linkEv.str1.1+0xb
  62:	89 c2                	mov    %eax,%edx
  64:	89 c0                	mov    %eax,%eax
  66:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 6d <Mips2C::jak1::sp_process_block_2d::link()+0x6d>	69: R_X86_64_PC32	g_ee_main_mem-0x4
  6d:	85 d2                	test   %edx,%edx
  6f:	ba 00 00 00 00       	mov    $0x0,%edx
  74:	48 0f 44 c2          	cmove  %rdx,%rax
  78:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 7f <Mips2C::jak1::sp_process_block_2d::link()+0x7f>	7b: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0xc
  7f:	e8 00 00 00 00       	call   84 <Mips2C::jak1::sp_process_block_2d::link()+0x84>	80: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
  84:	bf 14 00 00 00       	mov    $0x14,%edi
  89:	89 c2                	mov    %eax,%edx
  8b:	89 c0                	mov    %eax,%eax
  8d:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 94 <Mips2C::jak1::sp_process_block_2d::link()+0x94>	90: R_X86_64_PC32	g_ee_main_mem-0x4
  94:	85 d2                	test   %edx,%edx
  96:	ba 00 00 00 00       	mov    $0x0,%edx
  9b:	48 0f 44 c2          	cmove  %rdx,%rax
  9f:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # a6 <Mips2C::jak1::sp_process_block_2d::link()+0xa6>	a2: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x14
  a6:	e8 00 00 00 00       	call   ab <Mips2C::jak1::sp_process_block_2d::link()+0xab>	a7: R_X86_64_PLT32	operator new(unsigned long)-0x4
  ab:	c5 f9 6f 05 00 00 00 00 	vmovdqa 0x0(%rip),%xmm0        # b3 <Mips2C::jak1::sp_process_block_2d::link()+0xb3>	af: R_X86_64_PC32	.LC32-0x4
  b3:	48 89 e6             	mov    %rsp,%rsi
  b6:	b9 00 01 00 00       	mov    $0x100,%ecx
  bb:	c6 40 13 00          	movb   $0x0,0x13(%rax)
  bf:	ba 00 00 00 00       	mov    $0x0,%edx	c0: R_X86_64_32	Mips2C::jak1::sp_process_block_2d::execute(void*)
  c4:	bf 00 00 00 00       	mov    $0x0,%edi	c5: R_X86_64_32	Mips2C::gLinkedFunctionTable
  c9:	c5 fa 7f 00          	vmovdqu %xmm0,(%rax)
  cd:	c7 40 0f 6b 2d 32 64 	movl   $0x64322d6b,0xf(%rax)
  d4:	48 89 04 24          	mov    %rax,(%rsp)
  d8:	48 c7 44 24 10 13 00 00 00 	movq   $0x13,0x10(%rsp)
  e1:	48 c7 44 24 08 13 00 00 00 	movq   $0x13,0x8(%rsp)
  ea:	e8 00 00 00 00       	call   ef <Mips2C::jak1::sp_process_block_2d::link()+0xef>	eb: R_X86_64_PLT32	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)-0x4
  ef:	48 8b 3c 24          	mov    (%rsp),%rdi
  f3:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
  f8:	48 39 c7             	cmp    %rax,%rdi
  fb:	74 0e                	je     10b <Mips2C::jak1::sp_process_block_2d::link()+0x10b>
  fd:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
 102:	48 8d 70 01          	lea    0x1(%rax),%rsi
 106:	e8 00 00 00 00       	call   10b <Mips2C::jak1::sp_process_block_2d::link()+0x10b>	107: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
 10b:	48 83 c4 20          	add    $0x20,%rsp
 10f:	5b                   	pop    %rbx
 110:	c3                   	ret
 111:	48 89 c3             	mov    %rax,%rbx
 114:	e9 00 00 00 00       	jmp    119 <.LC24+0x109>	115: R_X86_64_PC32	.text.unlikely._ZN6Mips2C4jak119sp_process_block_2d4linkEv-0x4

EXIT 0
