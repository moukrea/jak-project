$ objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-after-x86.o

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-after-x86.o:     file format elf64-x86-64


Disassembly of section .text:

0000000000000000 <Mips2C::jak1::geco_spart_dump_armed()>:
       0:	48 83 ec 18          	sub    $0x18,%rsp
       4:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # b <Mips2C::jak1::geco_spart_dump_armed()+0xb>	7: R_X86_64_PC32	.data-0x4
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
      2a:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 31 <Mips2C::jak1::geco_spart_dump_armed()+0x31>	2d: R_X86_64_PC32	.data-0x4
      31:	48 39 c2             	cmp    %rax,%rdx
      34:	7d 12                	jge    48 <Mips2C::jak1::geco_spart_dump_armed()+0x48>
      36:	48 85 c0             	test   %rax,%rax
      39:	0f 94 c0             	sete   %al
      3c:	48 83 c4 18          	add    $0x18,%rsp
      40:	c3                   	ret
      41:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
      48:	48 c7 05 00 00 00 00 00 00 00 00 	movq   $0x0,0x0(%rip)        # 53 <Mips2C::jak1::geco_spart_dump_armed()+0x53>	4b: R_X86_64_PC32	.data-0x8
      53:	b8 01 00 00 00       	mov    $0x1,%eax
      58:	48 83 c4 18          	add    $0x18,%rsp
      5c:	c3                   	ret
      5d:	0f 1f 00             	nopl   (%rax)
      60:	48 c7 05 00 00 00 00 ff ff ff ff 	movq   $0xffffffffffffffff,0x0(%rip)        # 6b <Mips2C::jak1::geco_spart_dump_armed()+0x6b>	63: R_X86_64_PC32	.data-0x8
      6b:	bf 00 00 00 00       	mov    $0x0,%edi	6c: R_X86_64_32	.rodata.str1.1
      70:	e8 00 00 00 00       	call   75 <Mips2C::jak1::geco_spart_dump_armed()+0x75>	71: R_X86_64_PLT32	getenv-0x4
      75:	48 85 c0             	test   %rax,%rax
      78:	74 05                	je     7f <Mips2C::jak1::geco_spart_dump_armed()+0x7f>
      7a:	80 38 00             	cmpb   $0x0,(%rax)
      7d:	75 11                	jne    90 <Mips2C::jak1::geco_spart_dump_armed()+0x90>
      7f:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 86 <Mips2C::jak1::geco_spart_dump_armed()+0x86>	82: R_X86_64_PC32	.data-0x4
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
      b8:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # bf <Mips2C::jak1::geco_spart_dump_armed()+0xbf>	bb: R_X86_64_PC32	.data-0x4
      bf:	e9 4d ff ff ff       	jmp    11 <Mips2C::jak1::geco_spart_dump_armed()+0x11>
      c4:	90                   	nop
      c5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)

00000000000000d0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
      d0:	55                   	push   %rbp
      d1:	48 89 e5             	mov    %rsp,%rbp
      d4:	41 57                	push   %r15
      d6:	41 56                	push   %r14
      d8:	41 55                	push   %r13
      da:	41 54                	push   %r12
      dc:	53                   	push   %rbx
      dd:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
      e1:	48 81 ec 80 01 00 00 	sub    $0x180,%rsp
      e8:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
      ef:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
      f6:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # fd <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d>	f9: R_X86_64_PC32	g_ee_main_mem-0x4
      fd:	48 2d a0 00 00 00    	sub    $0xa0,%rax
     103:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
     10a:	89 c0                	mov    %eax,%eax
     10c:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
     110:	48 8b 8f e0 01 00 00 	mov    0x1e0(%rdi),%rcx
     117:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     11d:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 124 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x54>	120: R_X86_64_PC32	g_ee_main_mem-0x4
     124:	48 89 4c 02 08       	mov    %rcx,0x8(%rdx,%rax,1)
     129:	48 8b 87 90 01 00 00 	mov    0x190(%rdi),%rax
     130:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 137 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x67>	133: R_X86_64_PC32	g_ee_main_mem-0x4
     137:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
     13f:	48 89 87 e0 01 00 00 	mov    %rax,0x1e0(%rdi)
     146:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     14c:	83 c0 30             	add    $0x30,%eax
     14f:	83 e0 f0             	and    $0xfffffff0,%eax
     152:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     158:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     15e:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
     166:	83 c0 40             	add    $0x40,%eax
     169:	83 e0 f0             	and    $0xfffffff0,%eax
     16c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     172:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     178:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
     180:	83 c0 50             	add    $0x50,%eax
     183:	83 e0 f0             	and    $0xfffffff0,%eax
     186:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     18c:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     192:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
     19a:	83 c0 60             	add    $0x60,%eax
     19d:	83 e0 f0             	and    $0xfffffff0,%eax
     1a0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     1a6:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     1ac:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
     1b4:	83 c0 70             	add    $0x70,%eax
     1b7:	83 e0 f0             	and    $0xfffffff0,%eax
     1ba:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     1c0:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     1c6:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
     1ce:	83 e8 80             	sub    $0xffffff80,%eax
     1d1:	83 e0 f0             	and    $0xfffffff0,%eax
     1d4:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     1da:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     1e0:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
     1e8:	05 90 00 00 00       	add    $0x90,%eax
     1ed:	83 e0 f0             	and    $0xfffffff0,%eax
     1f0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     1f6:	48 8b 47 40          	mov    0x40(%rdi),%rax
     1fa:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
     1fe:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
     205:	48 8b 47 50          	mov    0x50(%rdi),%rax
     209:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
     210:	48 8b 47 60          	mov    0x60(%rdi),%rax
     214:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
     21b:	48 8b 47 70          	mov    0x70(%rdi),%rax
     21f:	48 89 87 00 01 00 00 	mov    %rax,0x100(%rdi)
     226:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
     22d:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
     234:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
     23b:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
     242:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
     249:	48 83 c0 10          	add    $0x10,%rax
     24d:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
     254:	83 e0 f0             	and    $0xfffffff0,%eax
     257:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     25d:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 264 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x194>	260: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
     264:	48 63 10             	movslq (%rax),%rdx
     267:	48 89 57 30          	mov    %rdx,0x30(%rdi)
     26b:	f6 c2 0f             	test   $0xf,%dl
     26e:	0f 85 cc 11 00 00    	jne    1440 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1370>
     274:	89 d0                	mov    %edx,%eax
     276:	8b 9f d0 01 00 00    	mov    0x1d0(%rdi),%ebx
     27c:	49 89 fe             	mov    %rdi,%r14
     27f:	49 8b 4c 01 08       	mov    0x8(%r9,%rax,1),%rcx
     284:	49 8b 14 01          	mov    (%r9,%rax,1),%rdx
     288:	48 89 8f 88 03 00 00 	mov    %rcx,0x388(%rdi)
     28f:	0f b6 c2             	movzbl %dl,%eax
     292:	48 89 97 80 03 00 00 	mov    %rdx,0x380(%rdi)
     299:	48 89 ca             	mov    %rcx,%rdx
     29c:	48 89 4f 38          	mov    %rcx,0x38(%rdi)
     2a0:	8d 4b 20             	lea    0x20(%rbx),%ecx
     2a3:	83 e1 f0             	and    $0xfffffff0,%ecx
     2a6:	48 89 47 30          	mov    %rax,0x30(%rdi)
     2aa:	49 89 04 09          	mov    %rax,(%r9,%rcx,1)
     2ae:	49 89 54 09 08       	mov    %rdx,0x8(%r9,%rcx,1)
     2b3:	48 8b 87 50 01 00 00 	mov    0x150(%rdi),%rax
     2ba:	e9 b3 00 00 00       	jmp    372 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2a2>
     2bf:	90                   	nop
     2c0:	49 63 08             	movslq (%r8),%rcx
     2c3:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
     2cb:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     2cf:	85 c9                	test   %ecx,%ecx
     2d1:	0f 84 60 01 00 00    	je     437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     2d7:	8b 07                	mov    (%rdi),%eax
     2d9:	89 c2                	mov    %eax,%edx
     2db:	83 e0 bf             	and    $0xffffffbf,%eax
     2de:	83 e2 40             	and    $0x40,%edx
     2e1:	48 63 c8             	movslq %eax,%rcx
     2e4:	89 d3                	mov    %edx,%ebx
     2e6:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     2ea:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     2ee:	89 07                	mov    %eax,(%rdi)
     2f0:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 2f7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x227>	2f3: R_X86_64_PC32	g_ee_main_mem-0x4
     2f7:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     2fe:	85 d2                	test   %edx,%edx
     300:	74 2e                	je     330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     302:	89 c0                	mov    %eax,%eax
     304:	49 63 54 01 7c       	movslq 0x7c(%r9,%rax,1),%rdx
     309:	48 89 d0             	mov    %rdx,%rax
     30c:	49 89 56 30          	mov    %rdx,0x30(%r14)
     310:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
     317:	41 89 44 11 2c       	mov    %eax,0x2c(%r9,%rdx,1)
     31c:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     323:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 32a <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x25a>	326: R_X86_64_PC32	g_ee_main_mem-0x4
     32a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
     330:	49 8b 9e 30 01 00 00 	mov    0x130(%r14),%rbx
     337:	48 05 90 00 00 00    	add    $0x90,%rax
     33d:	49 83 86 40 01 00 00 30 	addq   $0x30,0x140(%r14)
     345:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
     34c:	48 8d 53 ff          	lea    -0x1(%rbx),%rdx
     350:	49 8b 9e 00 01 00 00 	mov    0x100(%r14),%rbx
     357:	49 89 96 30 01 00 00 	mov    %rdx,0x130(%r14)
     35e:	48 8d 4b 01          	lea    0x1(%rbx),%rcx
     362:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
     369:	48 85 d2             	test   %rdx,%rdx
     36c:	0f 84 ae 0f 00 00    	je     1320 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1250>
     372:	89 c1                	mov    %eax,%ecx
     374:	49 8b b6 70 01 00 00 	mov    0x170(%r14),%rsi
     37b:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
     383:	49 89 56 30          	mov    %rdx,0x30(%r14)
     387:	48 39 d6             	cmp    %rdx,%rsi
     38a:	74 a4                	je     330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     38c:	49 8d 7c 09 68       	lea    0x68(%r9,%rcx,1),%rdi
     391:	4d 8d 44 09 64       	lea    0x64(%r9,%rcx,1),%r8
     396:	48 63 17             	movslq (%rdi),%rdx
     399:	49 3b b6 20 01 00 00 	cmp    0x120(%r14),%rsi
     3a0:	0f 84 e2 0b 00 00    	je     f88 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xeb8>
     3a6:	81 e2 00 20 00 00    	and    $0x2000,%edx
     3ac:	89 d3                	mov    %edx,%ebx
     3ae:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     3b2:	0f 84 08 ff ff ff    	je     2c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1f0>
     3b8:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
     3bf:	49 63 30             	movslq (%r8),%rsi
     3c2:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
     3ca:	8d 53 20             	lea    0x20(%rbx),%edx
     3cd:	49 89 76 30          	mov    %rsi,0x30(%r14)
     3d1:	83 e2 f0             	and    $0xfffffff0,%edx
     3d4:	4d 8b 14 11          	mov    (%r9,%rdx,1),%r10
     3d8:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
     3dd:	4d 89 56 40          	mov    %r10,0x40(%r14)
     3e1:	49 89 56 48          	mov    %rdx,0x48(%r14)
     3e5:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
     3e9:	0f 84 49 01 00 00    	je     538 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x468>
     3ef:	48 89 f1             	mov    %rsi,%rcx
     3f2:	c5 f9 6e e2          	vmovd  %edx,%xmm4
     3f6:	4c 29 d1             	sub    %r10,%rcx
     3f9:	49 89 d2             	mov    %rdx,%r10
     3fc:	48 89 cf             	mov    %rcx,%rdi
     3ff:	49 c1 fa 20          	sar    $0x20,%r10
     403:	c5 f9 6e f1          	vmovd  %ecx,%xmm6
     407:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     40b:	48 c1 ff 20          	sar    $0x20,%rdi
     40f:	c4 c3 59 22 ca 01    	vpinsrd $0x1,%r10d,%xmm4,%xmm1
     415:	c4 e3 49 22 c7 01    	vpinsrd $0x1,%edi,%xmm6,%xmm0
     41b:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
     41f:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
     423:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
     428:	c4 c1 79 7f 46 30    	vmovdqa %xmm0,0x30(%r14)
     42e:	48 85 f6             	test   %rsi,%rsi
     431:	0f 85 e9 00 00 00    	jne    520 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x450>
     437:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 43e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x36e>	43a: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
     43e:	49 8b 8e 40 01 00 00 	mov    0x140(%r14),%rcx
     445:	c4 e1 f9 6e f8       	vmovq  %rax,%xmm7
     44a:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
     453:	49 63 b6 f0 01 00 00 	movslq 0x1f0(%r14),%rsi
     45a:	c4 c1 7a 7e a6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm4
     463:	48 63 12             	movslq (%rdx),%rdx
     466:	49 89 46 60          	mov    %rax,0x60(%r14)
     46a:	c4 c3 d9 22 96 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm4,%xmm2
     474:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
     47a:	c4 c1 7a 7e a6 80 00 00 00 	vmovq  0x80(%r14),%xmm4
     483:	49 89 96 90 01 00 00 	mov    %rdx,0x190(%r14)
     48a:	48 89 d7             	mov    %rdx,%rdi
     48d:	49 8b 96 00 01 00 00 	mov    0x100(%r14),%rdx
     494:	c4 c3 d9 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm4,%xmm1
     49e:	49 89 4e 70          	mov    %rcx,0x70(%r14)
     4a2:	c4 e3 f9 22 c2 01    	vpinsrq $0x1,%rdx,%xmm0,%xmm0
     4a8:	49 89 56 50          	mov    %rdx,0x50(%r14)
     4ac:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     4b2:	c4 e3 c1 22 d1 01    	vpinsrq $0x1,%rcx,%xmm7,%xmm2
     4b8:	49 89 76 20          	mov    %rsi,0x20(%r14)
     4bc:	c5 fd 7f 8c 24 60 01 00 00 	vmovdqa %ymm1,0x160(%rsp)
     4c5:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
     4cb:	c5 fd 7f 84 24 40 01 00 00 	vmovdqa %ymm0,0x140(%rsp)
     4d4:	85 ff                	test   %edi,%edi
     4d6:	0f 84 20 0f 00 00    	je     13fc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x132c>
     4dc:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     4e3:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     4ea:	89 ff                	mov    %edi,%edi
     4ec:	31 d2                	xor    %edx,%edx
     4ee:	4c 01 cf             	add    %r9,%rdi
     4f1:	48 8d b4 24 40 01 00 00 	lea    0x140(%rsp),%rsi
     4f9:	c5 f8 77             	vzeroupper
     4fc:	e8 00 00 00 00       	call   501 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x431>	4fd: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     501:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 508 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x438>	504: R_X86_64_PC32	g_ee_main_mem-0x4
     508:	49 89 46 20          	mov    %rax,0x20(%r14)
     50c:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     513:	e9 18 fe ff ff       	jmp    330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     518:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
     520:	c4 c1 79 7e 00       	vmovd  %xmm0,(%r8)
     525:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
     52c:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 533 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x463>	52f: R_X86_64_PC32	g_ee_main_mem-0x4
     533:	48 8d 7c 02 68       	lea    0x68(%rdx,%rax,1),%rdi
     538:	8b 07                	mov    (%rdi),%eax
     53a:	89 c2                	mov    %eax,%edx
     53c:	83 e0 bf             	and    $0xffffffbf,%eax
     53f:	83 e2 40             	and    $0x40,%edx
     542:	48 63 c8             	movslq %eax,%rcx
     545:	89 d3                	mov    %edx,%ebx
     547:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     54b:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     54f:	89 07                	mov    %eax,(%rdi)
     551:	85 d2                	test   %edx,%edx
     553:	74 25                	je     57a <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x4aa>
     555:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
     55c:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 563 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x493>	55f: R_X86_64_PC32	g_ee_main_mem-0x4
     563:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
     568:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     56c:	48 89 ca             	mov    %rcx,%rdx
     56f:	41 8b 8e 40 01 00 00 	mov    0x140(%r14),%ecx
     576:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
     57a:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 581 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x4b1>	57d: R_X86_64_PC32	g_ee_main_mem-0x4
     581:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
     588:	49 63 44 11 70       	movslq 0x70(%r9,%rdx,1),%rax
     58d:	48 89 c1             	mov    %rax,%rcx
     590:	49 89 86 90 01 00 00 	mov    %rax,0x190(%r14)
     597:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     59e:	85 c9                	test   %ecx,%ecx
     5a0:	0f 84 f6 01 00 00    	je     79c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6cc>
     5a6:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
     5af:	48 83 e8 60          	sub    $0x60,%rax
     5b3:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     5ba:	83 e0 f0             	and    $0xfffffff0,%eax
     5bd:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     5c3:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     5ca:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
     5d3:	83 c0 10             	add    $0x10,%eax
     5d6:	83 e0 f0             	and    $0xfffffff0,%eax
     5d9:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     5df:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     5e6:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
     5ef:	83 c0 20             	add    $0x20,%eax
     5f2:	83 e0 f0             	and    $0xfffffff0,%eax
     5f5:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     5fb:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     602:	c4 c1 79 6f 86 00 01 00 00 	vmovdqa 0x100(%r14),%xmm0
     60b:	83 c0 30             	add    $0x30,%eax
     60e:	83 e0 f0             	and    $0xfffffff0,%eax
     611:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     617:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     61e:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
     627:	83 c0 40             	add    $0x40,%eax
     62a:	83 e0 f0             	and    $0xfffffff0,%eax
     62d:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     633:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
     63a:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
     643:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
     64a:	49 89 46 40          	mov    %rax,0x40(%r14)
     64e:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     655:	49 89 46 50          	mov    %rax,0x50(%r14)
     659:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     660:	49 89 46 60          	mov    %rax,0x60(%r14)
     664:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     66b:	83 c0 50             	add    $0x50,%eax
     66e:	83 e0 f0             	and    $0xfffffff0,%eax
     671:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     677:	c4 c1 7a 7e 5e 60    	vmovq  0x60(%r14),%xmm3
     67d:	c4 c1 7a 7e ae a0 00 00 00 	vmovq  0xa0(%r14),%xmm5
     686:	c4 c1 7a 7e b6 80 00 00 00 	vmovq  0x80(%r14),%xmm6
     68f:	c4 c3 e1 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm3,%xmm2
     696:	c4 c3 d1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm5,%xmm1
     6a0:	c4 c1 7a 7e 66 40    	vmovq  0x40(%r14),%xmm4
     6a6:	c4 c3 c9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm6,%xmm0
     6b0:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     6b6:	c4 c3 d9 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm4,%xmm1
     6bd:	c5 fd 7f 44 24 60    	vmovdqa %ymm0,0x60(%rsp)
     6c3:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     6c9:	c5 fd 7f 4c 24 40    	vmovdqa %ymm1,0x40(%rsp)
     6cf:	85 ff                	test   %edi,%edi
     6d1:	0f 84 25 0d 00 00    	je     13fc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x132c>
     6d7:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     6de:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     6e5:	4c 01 cf             	add    %r9,%rdi
     6e8:	31 d2                	xor    %edx,%edx
     6ea:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
     6ef:	c5 f8 77             	vzeroupper
     6f2:	e8 00 00 00 00       	call   6f7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x627>	6f3: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     6f7:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 6fe <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x62e>	6fa: R_X86_64_PC32	g_ee_main_mem-0x4
     6fe:	49 89 46 20          	mov    %rax,0x20(%r14)
     702:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     709:	48 89 c2             	mov    %rax,%rdx
     70c:	8d 48 10             	lea    0x10(%rax),%ecx
     70f:	83 e2 f0             	and    $0xfffffff0,%edx
     712:	83 e1 f0             	and    $0xfffffff0,%ecx
     715:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
     71b:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
     724:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
     728:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
     72d:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
     734:	8d 48 20             	lea    0x20(%rax),%ecx
     737:	83 e1 f0             	and    $0xfffffff0,%ecx
     73a:	49 89 96 50 01 00 00 	mov    %rdx,0x150(%r14)
     741:	89 d2                	mov    %edx,%edx
     743:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     749:	8d 48 30             	lea    0x30(%rax),%ecx
     74c:	83 e1 f0             	and    $0xfffffff0,%ecx
     74f:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
     758:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     75e:	8d 48 40             	lea    0x40(%rax),%ecx
     761:	83 e1 f0             	and    $0xfffffff0,%ecx
     764:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
     76d:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     773:	8d 48 50             	lea    0x50(%rax),%ecx
     776:	48 83 c0 60          	add    $0x60,%rax
     77a:	83 e1 f0             	and    $0xfffffff0,%ecx
     77d:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
     786:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     78c:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     793:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
     79c:	49 63 74 11 78       	movslq 0x78(%r9,%rdx,1),%rsi
     7a1:	83 c0 20             	add    $0x20,%eax
     7a4:	83 e0 f0             	and    $0xfffffff0,%eax
     7a7:	49 89 76 50          	mov    %rsi,0x50(%r14)
     7ab:	48 89 f1             	mov    %rsi,%rcx
     7ae:	49 8d 74 11 74       	lea    0x74(%r9,%rdx,1),%rsi
     7b3:	48 63 16             	movslq (%rsi),%rdx
     7b6:	49 89 56 30          	mov    %rdx,0x30(%r14)
     7ba:	49 8b 3c 01          	mov    (%r9,%rax,1),%rdi
     7be:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
     7c3:	49 89 7e 40          	mov    %rdi,0x40(%r14)
     7c7:	49 89 46 48          	mov    %rax,0x48(%r14)
     7cb:	85 c9                	test   %ecx,%ecx
     7cd:	74 0f                	je     7de <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x70e>
     7cf:	48 29 fa             	sub    %rdi,%rdx
     7d2:	49 89 56 30          	mov    %rdx,0x30(%r14)
     7d6:	89 16                	mov    %edx,(%rsi)
     7d8:	0f 88 22 09 00 00    	js     1100 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1030>
     7de:	41 8b 8e 40 01 00 00 	mov    0x140(%r14),%ecx
     7e5:	f6 c1 0f             	test   $0xf,%cl
     7e8:	0f 85 90 0c 00 00    	jne    147e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13ae>
     7ee:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 7f5 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x725>	7f1: R_X86_64_PC32	g_ee_main_mem-0x4
     7f5:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
     7fc:	4c 8b 44 08 18       	mov    0x18(%rax,%rcx,1),%r8
     801:	4c 8b 5c 08 10       	mov    0x10(%rax,%rcx,1),%r11
     806:	c5 fa 7e 1c 08       	vmovq  (%rax,%rcx,1),%xmm3
     80b:	48 8b 74 08 08       	mov    0x8(%rax,%rcx,1),%rsi
     810:	4c 89 5c 24 20       	mov    %r11,0x20(%rsp)
     815:	4c 89 44 24 28       	mov    %r8,0x28(%rsp)
     81a:	f6 c2 0f             	test   $0xf,%dl
     81d:	0f 85 3c 0c 00 00    	jne    145f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x138f>
     823:	c4 e3 e1 22 de 01    	vpinsrq $0x1,%rsi,%xmm3,%xmm3
     829:	4d 8b 8e 88 03 00 00 	mov    0x388(%r14),%r9
     830:	c5 fa 6f 6c 10 40    	vmovdqu 0x40(%rax,%rdx,1),%xmm5
     836:	48 8b 74 10 10       	mov    0x10(%rax,%rdx,1),%rsi
     83b:	49 8b be 50 01 00 00 	mov    0x150(%r14),%rdi
     842:	c4 c1 79 6e c1       	vmovd  %r9d,%xmm0
     847:	c5 f9 6f cd          	vmovdqa %xmm5,%xmm1
     84b:	4c 8b 64 10 18       	mov    0x18(%rax,%rdx,1),%r12
     850:	c5 fa 7e 64 10 30    	vmovq  0x30(%rax,%rdx,1),%xmm4
     856:	c5 f8 c6 d0 00       	vshufps $0x0,%xmm0,%xmm0,%xmm2
     85b:	c5 e8 59 d5          	vmulps %xmm5,%xmm2,%xmm2
     85f:	c5 fa 12 c0          	vmovsldup %xmm0,%xmm0
     863:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
     868:	c5 f0 14 cd          	vunpcklps %xmm5,%xmm1,%xmm1
     86c:	41 89 fd             	mov    %edi,%r13d
     86f:	4c 8b 7c 10 38       	mov    0x38(%rax,%rdx,1),%r15
     874:	4c 89 e3             	mov    %r12,%rbx
     877:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     87b:	4c 8b 5c 10 20       	mov    0x20(%rax,%rdx,1),%r11
     880:	4c 8b 54 10 28       	mov    0x28(%rax,%rdx,1),%r10
     885:	48 89 7c 24 38       	mov    %rdi,0x38(%rsp)
     88a:	4a 63 54 28 60       	movslq 0x60(%rax,%r13,1),%rdx
     88f:	c5 78 10 4c 08 20    	vmovups 0x20(%rax,%rcx,1),%xmm9
     895:	c4 43 d9 22 c7 01    	vpinsrq $0x1,%r15,%xmm4,%xmm8
     89b:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     89f:	c5 f0 59 c8          	vmulps %xmm0,%xmm1,%xmm1
     8a3:	c5 f9 6e c6          	vmovd  %esi,%xmm0
     8a7:	48 c1 ee 20          	shr    $0x20,%rsi
     8ab:	49 89 56 30          	mov    %rdx,0x30(%r14)
     8af:	c5 f9 6e f6          	vmovd  %esi,%xmm6
     8b3:	41 89 96 00 02 00 00 	mov    %edx,0x200(%r14)
     8ba:	48 89 d7             	mov    %rdx,%rdi
     8bd:	48 89 de             	mov    %rbx,%rsi
     8c0:	c5 f8 14 c6          	vunpcklps %xmm6,%xmm0,%xmm0
     8c4:	c5 e8 15 f2          	vunpckhps %xmm2,%xmm2,%xmm6
     8c8:	49 8b 96 80 03 00 00 	mov    0x380(%r14),%rdx
     8cf:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     8d3:	48 89 54 24 30       	mov    %rdx,0x30(%rsp)
     8d8:	48 ba 00 00 00 00 ff ff ff ff 	movabs $0xffffffff00000000,%rdx
     8e2:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     8e6:	48 21 d6             	and    %rdx,%rsi
     8e9:	c5 f0 58 c8          	vaddps %xmm0,%xmm1,%xmm1
     8ed:	c4 c1 79 6e c4       	vmovd  %r12d,%xmm0
     8f2:	c5 ca 58 f0          	vaddss %xmm0,%xmm6,%xmm6
     8f6:	c4 e1 f9 7e c9       	vmovq  %xmm1,%rcx
     8fb:	c5 fa 16 c1          	vmovshdup %xmm1,%xmm0
     8ff:	c4 c1 79 7e f4       	vmovd  %xmm6,%r12d
     904:	4c 09 e6             	or     %r12,%rsi
     907:	48 89 f3             	mov    %rsi,%rbx
     90a:	85 ff                	test   %edi,%edi
     90c:	0f 85 2e 07 00 00    	jne    1040 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf70>
     912:	48 89 da             	mov    %rbx,%rdx
     915:	4c 89 de             	mov    %r11,%rsi
     918:	c5 f0 14 c0          	vunpcklps %xmm0,%xmm1,%xmm0
     91c:	c5 fa 7e 7c 24 30    	vmovq  0x30(%rsp),%xmm7
     922:	48 c1 ea 20          	shr    $0x20,%rdx
     926:	48 c1 ee 20          	shr    $0x20,%rsi
     92a:	c4 c1 79 6e cb       	vmovd  %r11d,%xmm1
     92f:	4c 8b 4c 24 28       	mov    0x28(%rsp),%r9
     934:	c5 79 6e da          	vmovd  %edx,%xmm11
     938:	c5 79 6e ee          	vmovd  %esi,%xmm13
     93c:	4c 89 d6             	mov    %r10,%rsi
     93f:	c5 c0 c6 ff 55       	vshufps $0x55,%xmm7,%xmm7,%xmm7
     944:	c4 c1 48 14 f3       	vunpcklps %xmm11,%xmm6,%xmm6
     949:	48 c1 ee 20          	shr    $0x20,%rsi
     94d:	c5 f9 6f ef          	vmovdqa %xmm7,%xmm5
     951:	c4 c1 70 14 cd       	vunpcklps %xmm13,%xmm1,%xmm1
     956:	c5 f8 16 c6          	vmovlhps %xmm6,%xmm0,%xmm0
     95a:	c5 79 6e e6          	vmovd  %esi,%xmm12
     95e:	c4 c1 79 6e f2       	vmovd  %r10d,%xmm6
     963:	c5 d0 c6 ed 00       	vshufps $0x0,%xmm5,%xmm5,%xmm5
     968:	c4 c1 48 14 f4       	vunpcklps %xmm12,%xmm6,%xmm6
     96d:	c5 c0 c6 ff 00       	vshufps $0x0,%xmm7,%xmm7,%xmm7
     972:	c4 e3 55 18 ed 01    	vinsertf128 $0x1,%xmm5,%ymm5,%ymm5
     978:	49 c1 e8 20          	shr    $0x20,%r8
     97c:	c5 f0 16 ce          	vmovlhps %xmm6,%xmm1,%xmm1
     980:	c4 e3 7d 18 c9 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm1
     986:	c4 c1 79 6e f0       	vmovd  %r8d,%xmm6
     98b:	44 89 ca             	mov    %r9d,%edx
     98e:	c4 41 40 59 c0       	vmulps %xmm8,%xmm7,%xmm8
     993:	4c 8b 44 24 20       	mov    0x20(%rsp),%r8
     998:	49 89 8e 30 03 00 00 	mov    %rcx,0x330(%r14)
     99f:	c5 f4 59 cd          	vmulps %ymm5,%ymm1,%ymm1
     9a3:	49 89 9e 38 03 00 00 	mov    %rbx,0x338(%r14)
     9aa:	c5 c0 59 f8          	vmulps %xmm0,%xmm7,%xmm7
     9ae:	4d 89 86 10 03 00 00 	mov    %r8,0x310(%r14)
     9b5:	4d 89 9e 40 03 00 00 	mov    %r11,0x340(%r14)
     9bc:	4d 89 96 48 03 00 00 	mov    %r10,0x348(%r14)
     9c3:	c4 41 30 58 c8       	vaddps %xmm8,%xmm9,%xmm9
     9c8:	4d 89 be 58 03 00 00 	mov    %r15,0x358(%r14)
     9cf:	c4 c1 79 d6 a6 50 03 00 00 	vmovq  %xmm4,0x350(%r14)
     9d8:	c4 c1 78 29 96 60 03 00 00 	vmovaps %xmm2,0x360(%r14)
     9e1:	c5 c0 58 fb          	vaddps %xmm3,%xmm7,%xmm7
     9e5:	c4 e3 7d 19 cb 01    	vextractf128 $0x1,%ymm1,%xmm3
     9eb:	c5 e0 c6 db ff       	vshufps $0xff,%xmm3,%xmm3,%xmm3
     9f0:	c5 e2 58 ee          	vaddss %xmm6,%xmm3,%xmm5
     9f4:	c5 e0 57 db          	vxorps %xmm3,%xmm3,%xmm3
     9f8:	c4 c1 60 5f d9       	vmaxps %xmm9,%xmm3,%xmm3
     9fd:	c4 c1 79 7f be 00 03 00 00 	vmovdqa %xmm7,0x300(%r14)
     a06:	c5 f9 7e ee          	vmovd  %xmm5,%esi
     a0a:	c4 c1 79 7f 9e 20 03 00 00 	vmovdqa %xmm3,0x320(%r14)
     a13:	48 c1 e6 20          	shl    $0x20,%rsi
     a17:	48 09 f2             	or     %rsi,%rdx
     a1a:	49 89 96 18 03 00 00 	mov    %rdx,0x318(%r14)
     a21:	85 ff                	test   %edi,%edi
     a23:	74 29                	je     a4e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x97e>
     a25:	c5 fa 10 5c 24 18    	vmovss 0x18(%rsp),%xmm3
     a2b:	c5 fa 10 64 24 10    	vmovss 0x10(%rsp),%xmm4
     a31:	c4 e3 61 21 5c 24 1c 10 	vinsertps $0x10,0x1c(%rsp),%xmm3,%xmm3
     a39:	c4 e3 59 21 54 24 14 10 	vinsertps $0x10,0x14(%rsp),%xmm4,%xmm2
     a41:	c5 e8 16 d3          	vmovlhps %xmm3,%xmm2,%xmm2
     a45:	c4 c1 78 29 96 70 03 00 00 	vmovaps %xmm2,0x370(%r14)
     a4e:	c4 c1 7c 11 8e 90 03 00 00 	vmovups %ymm1,0x390(%r14)
     a57:	c4 41 78 29 86 b0 03 00 00 	vmovaps %xmm8,0x3b0(%r14)
     a60:	f6 44 24 38 0f       	testb  $0xf,0x38(%rsp)
     a65:	0f 85 b3 09 00 00    	jne    141e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x134e>
     a6b:	c4 a1 78 11 44 28 10 	vmovups %xmm0,0x10(%rax,%r13,1)
     a72:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     a79:	f6 c2 0f             	test   $0xf,%dl
     a7c:	0f 85 9c 09 00 00    	jne    141e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x134e>
     a82:	c4 c1 79 6f 86 00 03 00 00 	vmovdqa 0x300(%r14),%xmm0
     a8b:	89 d2                	mov    %edx,%edx
     a8d:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
     a92:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     a99:	f6 c2 0f             	test   $0xf,%dl
     a9c:	0f 85 7c 09 00 00    	jne    141e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x134e>
     aa2:	c4 c1 79 6f 86 10 03 00 00 	vmovdqa 0x310(%r14),%xmm0
     aab:	89 d2                	mov    %edx,%edx
     aad:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
     ab3:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     aba:	f6 c2 0f             	test   $0xf,%dl
     abd:	0f 85 5b 09 00 00    	jne    141e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x134e>
     ac3:	c4 c1 79 6f 86 20 03 00 00 	vmovdqa 0x320(%r14),%xmm0
     acc:	89 d2                	mov    %edx,%edx
     ace:	c5 fa 10 25 00 00 00 00 	vmovss 0x0(%rip),%xmm4        # ad6 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa06>	ad2: R_X86_64_PC32	.LC11-0x4
     ad6:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
     adc:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     ae3:	49 8b 8e 10 01 00 00 	mov    0x110(%r14),%rcx
     aea:	49 89 56 40          	mov    %rdx,0x40(%r14)
     aee:	89 d2                	mov    %edx,%edx
     af0:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     af4:	8b 74 10 10          	mov    0x10(%rax,%rdx,1),%esi
     af8:	89 c9                	mov    %ecx,%ecx
     afa:	41 89 b6 00 02 00 00 	mov    %esi,0x200(%r14)
     b01:	8b 7c 10 14          	mov    0x14(%rax,%rdx,1),%edi
     b05:	41 89 be 04 02 00 00 	mov    %edi,0x204(%r14)
     b0c:	8b 54 10 18          	mov    0x18(%rax,%rdx,1),%edx
     b10:	41 89 96 0c 02 00 00 	mov    %edx,0x20c(%r14)
     b17:	89 34 08             	mov    %esi,(%rax,%rcx,1)
     b1a:	41 8b 8e 04 02 00 00 	mov    0x204(%r14),%ecx
     b21:	41 8b 46 30          	mov    0x30(%r14),%eax
     b25:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # b2c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa5c>	b28: R_X86_64_PC32	g_ee_main_mem-0x4
     b2c:	89 4c 02 04          	mov    %ecx,0x4(%rdx,%rax,1)
     b30:	41 8b 8e 0c 02 00 00 	mov    0x20c(%r14),%ecx
     b37:	41 8b 46 30          	mov    0x30(%r14),%eax
     b3b:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # b42 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa72>	b3e: R_X86_64_PC32	g_ee_main_mem-0x4
     b42:	89 4c 02 08          	mov    %ecx,0x8(%rdx,%rax,1)
     b46:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # b4d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa7d>	b49: R_X86_64_PC32	g_ee_main_mem-0x4
     b4d:	c4 c1 7a 10 86 0c 02 00 00 	vmovss 0x20c(%r14),%xmm0
     b56:	41 8b 46 30          	mov    0x30(%r14),%eax
     b5a:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
     b5e:	c4 c1 7a 11 86 0c 02 00 00 	vmovss %xmm0,0x20c(%r14)
     b67:	c5 da 5c c8          	vsubss %xmm0,%xmm4,%xmm1
     b6b:	c4 c1 7a 10 86 04 02 00 00 	vmovss 0x204(%r14),%xmm0
     b74:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
     b78:	c5 f2 5c c0          	vsubss %xmm0,%xmm1,%xmm0
     b7c:	c5 f8 14 c9          	vunpcklps %xmm1,%xmm0,%xmm1
     b80:	c4 c1 78 13 8e 04 02 00 00 	vmovlps %xmm1,0x204(%r14)
     b89:	c4 c1 7a 10 8e 00 02 00 00 	vmovss 0x200(%r14),%xmm1
     b92:	c5 f2 59 c9          	vmulss %xmm1,%xmm1,%xmm1
     b96:	c5 fa 5c c1          	vsubss %xmm1,%xmm0,%xmm0
     b9a:	c5 f8 54 05 00 00 00 00 	vandps 0x0(%rip),%xmm0,%xmm0        # ba2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xad2>	b9e: R_X86_64_PC32	.LC14-0x4
     ba2:	c5 fa 51 c0          	vsqrtss %xmm0,%xmm0,%xmm0
     ba6:	c4 c1 7a 11 86 00 02 00 00 	vmovss %xmm0,0x200(%r14)
     baf:	c5 fa 11 44 02 0c    	vmovss %xmm0,0xc(%rdx,%rax,1)
     bb5:	49 63 86 00 02 00 00 	movslq 0x200(%r14),%rax
     bbc:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # bc3 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xaf3>	bbf: R_X86_64_PC32	g_ee_main_mem-0x4
     bc3:	49 89 46 40          	mov    %rax,0x40(%r14)
     bc7:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # bce <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xafe>	bca: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
     bce:	48 63 10             	movslq (%rax),%rdx
     bd1:	89 d0                	mov    %edx,%eax
     bd3:	49 89 56 30          	mov    %rdx,0x30(%r14)
     bd7:	41 8b 04 01          	mov    (%r9,%rax,1),%eax
     bdb:	41 89 86 00 02 00 00 	mov    %eax,0x200(%r14)
     be2:	0f b6 c0             	movzbl %al,%eax
     be5:	48 83 e8 0a          	sub    $0xa,%rax
     be9:	49 89 46 30          	mov    %rax,0x30(%r14)
     bed:	0f 88 c8 00 00 00    	js     cbb <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbeb>
     bf3:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     bfa:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb31>	bfd: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
     c01:	c4 c1 7a 7e 96 10 01 00 00 	vmovq  0x110(%r14),%xmm2
     c0a:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
     c11:	c4 c1 7a 7e ae a0 00 00 00 	vmovq  0xa0(%r14),%xmm5
     c1a:	48 83 c0 50          	add    $0x50,%rax
     c1e:	48 63 09             	movslq (%rcx),%rcx
     c21:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
     c26:	c4 c3 d9 22 46 70 01 	vpinsrq $0x1,0x70(%r14),%xmm4,%xmm0
     c2d:	c5 e9 6c ca          	vpunpcklqdq %xmm2,%xmm2,%xmm1
     c31:	c4 c1 7a 7e b6 80 00 00 00 	vmovq  0x80(%r14),%xmm6
     c3a:	c4 c3 d1 22 9e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm5,%xmm3
     c44:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
     c4b:	48 89 cf             	mov    %rcx,%rdi
     c4e:	c4 e3 75 18 c8 01    	vinsertf128 $0x1,%xmm0,%ymm1,%ymm1
     c54:	49 89 46 60          	mov    %rax,0x60(%r14)
     c58:	c4 c3 c9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm6,%xmm0
     c62:	49 89 56 20          	mov    %rdx,0x20(%r14)
     c66:	c4 e3 7d 18 c3 01    	vinsertf128 $0x1,%xmm3,%ymm0,%ymm0
     c6c:	c4 c1 79 d6 56 40    	vmovq  %xmm2,0x40(%r14)
     c72:	c4 c1 79 d6 56 50    	vmovq  %xmm2,0x50(%r14)
     c78:	c5 fd 7f 8c 24 c0 00 00 00 	vmovdqa %ymm1,0xc0(%rsp)
     c81:	c5 fd 7f 84 24 e0 00 00 00 	vmovdqa %ymm0,0xe0(%rsp)
     c8a:	85 c9                	test   %ecx,%ecx
     c8c:	0f 84 6a 07 00 00    	je     13fc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x132c>
     c92:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     c99:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     ca0:	89 ff                	mov    %edi,%edi
     ca2:	31 d2                	xor    %edx,%edx
     ca4:	4c 01 cf             	add    %r9,%rdi
     ca7:	48 8d b4 24 c0 00 00 00 	lea    0xc0(%rsp),%rsi
     caf:	c5 f8 77             	vzeroupper
     cb2:	e8 00 00 00 00       	call   cb7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbe7>	cb3: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     cb7:	49 89 46 20          	mov    %rax,0x20(%r14)
     cbb:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # cc2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbf2>	cbe: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
     cc2:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
     cc9:	c4 c1 7a 7e be a0 00 00 00 	vmovq  0xa0(%r14),%xmm7
     cd2:	c4 c1 7a 7e 9e 80 00 00 00 	vmovq  0x80(%r14),%xmm3
     cdb:	c4 c3 c1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm7,%xmm1
     ce5:	48 63 00             	movslq (%rax),%rax
     ce8:	49 89 56 20          	mov    %rdx,0x20(%r14)
     cec:	c4 c3 e1 22 96 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm3,%xmm2
     cf6:	c4 c1 7a 7e 86 10 01 00 00 	vmovq  0x110(%r14),%xmm0
     cff:	49 89 86 90 01 00 00 	mov    %rax,0x190(%r14)
     d06:	48 89 c7             	mov    %rax,%rdi
     d09:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     d10:	c4 e3 6d 18 d1 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm2
     d16:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
     d1c:	48 83 c0 50          	add    $0x50,%rax
     d20:	c4 c1 79 d6 46 50    	vmovq  %xmm0,0x50(%r14)
     d26:	c5 f9 6c c0          	vpunpcklqdq %xmm0,%xmm0,%xmm0
     d2a:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
     d2f:	c4 c3 d9 22 4e 70 01 	vpinsrq $0x1,0x70(%r14),%xmm4,%xmm1
     d36:	49 89 46 60          	mov    %rax,0x60(%r14)
     d3a:	c5 fd 7f 94 24 20 01 00 00 	vmovdqa %ymm2,0x120(%rsp)
     d43:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     d49:	c5 fd 7f 84 24 00 01 00 00 	vmovdqa %ymm0,0x100(%rsp)
     d52:	85 ff                	test   %edi,%edi
     d54:	0f 84 a2 06 00 00    	je     13fc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x132c>
     d5a:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # d61 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc91>	d5d: R_X86_64_PC32	g_ee_main_mem-0x4
     d61:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     d68:	89 ff                	mov    %edi,%edi
     d6a:	31 d2                	xor    %edx,%edx
     d6c:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     d73:	48 8d b4 24 00 01 00 00 	lea    0x100(%rsp),%rsi
     d7b:	4c 01 cf             	add    %r9,%rdi
     d7e:	c5 f8 77             	vzeroupper
     d81:	e8 00 00 00 00       	call   d86 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcb6>	d82: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     d86:	49 8b 96 10 01 00 00 	mov    0x110(%r14),%rdx
     d8d:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
     d91:	49 89 46 20          	mov    %rax,0x20(%r14)
     d95:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # d9c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xccc>	d98: R_X86_64_PC32	g_ee_main_mem-0x4
     d9c:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     da3:	89 d1                	mov    %edx,%ecx
     da5:	49 89 56 30          	mov    %rdx,0x30(%r14)
     da9:	49 89 46 40          	mov    %rax,0x40(%r14)
     dad:	c4 c1 79 6e 44 09 0c 	vmovd  0xc(%r9,%rcx,1),%xmm0
     db4:	41 c7 86 04 02 00 00 00 00 00 00 	movl   $0x0,0x204(%r14)
     dbf:	c4 c1 79 7e 86 00 02 00 00 	vmovd  %xmm0,0x200(%r14)
     dc8:	c5 f8 2f c8          	vcomiss %xmm0,%xmm1
     dcc:	0f 87 c6 01 00 00    	ja     f98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xec8>
     dd2:	a8 0f                	test   $0xf,%al
     dd4:	0f 85 66 06 00 00    	jne    1440 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1370>
     dda:	89 c0                	mov    %eax,%eax
     ddc:	83 e2 0f             	and    $0xf,%edx
     ddf:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
     de4:	48 8b 07             	mov    (%rdi),%rax
     de7:	48 8b 77 08          	mov    0x8(%rdi),%rsi
     deb:	49 89 86 90 02 00 00 	mov    %rax,0x290(%r14)
     df2:	49 89 b6 98 02 00 00 	mov    %rsi,0x298(%r14)
     df9:	0f 85 41 06 00 00    	jne    1440 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1370>
     dff:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
     e03:	49 8b 44 09 08       	mov    0x8(%r9,%rcx,1),%rax
     e08:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
     e0c:	48 c1 ee 20          	shr    $0x20,%rsi
     e10:	c5 f9 6e de          	vmovd  %esi,%xmm3
     e14:	49 89 96 a0 02 00 00 	mov    %rdx,0x2a0(%r14)
     e1b:	c5 f9 6e c2          	vmovd  %edx,%xmm0
     e1f:	48 c1 ea 20          	shr    $0x20,%rdx
     e23:	c5 f9 6e ea          	vmovd  %edx,%xmm5
     e27:	49 89 86 a8 02 00 00 	mov    %rax,0x2a8(%r14)
     e2e:	c5 f8 14 c5          	vunpcklps %xmm5,%xmm0,%xmm0
     e32:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     e36:	c5 f8 58 c2          	vaddps %xmm2,%xmm0,%xmm0
     e3a:	c5 f9 6e d0          	vmovd  %eax,%xmm2
     e3e:	c5 ea 58 c9          	vaddss %xmm1,%xmm2,%xmm1
     e42:	c4 c1 78 13 86 90 02 00 00 	vmovlps %xmm0,0x290(%r14)
     e4b:	c4 c1 7a 11 8e 98 02 00 00 	vmovss %xmm1,0x298(%r14)
     e54:	c5 f0 14 cb          	vunpcklps %xmm3,%xmm1,%xmm1
     e58:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
     e5c:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
     e60:	49 8b 86 90 02 00 00 	mov    0x290(%r14),%rax
     e67:	49 8b 96 98 02 00 00 	mov    0x298(%r14),%rdx
     e6e:	c4 c1 78 28 86 20 03 00 00 	vmovaps 0x320(%r14),%xmm0
     e77:	49 89 46 40          	mov    %rax,0x40(%r14)
     e7b:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     e82:	49 89 56 48          	mov    %rdx,0x48(%r14)
     e86:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     e8c:	89 c2                	mov    %eax,%edx
     e8e:	49 63 4c 11 68       	movslq 0x68(%r9,%rdx,1),%rcx
     e93:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     e97:	48 89 ca             	mov    %rcx,%rdx
     e9a:	83 e1 04             	and    $0x4,%ecx
     e9d:	89 cb                	mov    %ecx,%ebx
     e9f:	49 89 5e 50          	mov    %rbx,0x50(%r14)
     ea3:	f6 c2 02             	test   $0x2,%dl
     ea6:	74 33                	je     edb <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe0b>
     ea8:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
     ead:	41 c7 46 60 00 00 00 00 	movl   $0x0,0x60(%r14)
     eb5:	c4 c3 79 16 46 64 02 	vpextrd $0x2,%xmm0,0x64(%r14)
     ebc:	c4 c3 79 16 46 6c 03 	vpextrd $0x3,%xmm0,0x6c(%r14)
     ec3:	41 c7 46 68 00 00 00 00 	movl   $0x0,0x68(%r14)
     ecb:	48 85 f6             	test   %rsi,%rsi
     ece:	75 0b                	jne    edb <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe0b>
     ed0:	49 83 7e 60 00       	cmpq   $0x0,0x60(%r14)
     ed5:	0f 84 5c f5 ff ff    	je     437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     edb:	83 e2 01             	and    $0x1,%edx
     ede:	89 d3                	mov    %edx,%ebx
     ee0:	49 89 5e 40          	mov    %rbx,0x40(%r14)
     ee4:	85 c9                	test   %ecx,%ecx
     ee6:	74 29                	je     f11 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe41>
     ee8:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
     ef0:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     ef7:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
     efe:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     f06:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
     f0b:	0f 8e 26 f5 ff ff    	jle    437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     f11:	85 d2                	test   %edx,%edx
     f13:	0f 84 17 f4 ff ff    	je     330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     f19:	c4 c1 78 28 86 00 03 00 00 	vmovaps 0x300(%r14),%xmm0
     f22:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     f28:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     f2f:	c4 c1 78 28 86 10 03 00 00 	vmovaps 0x310(%r14),%xmm0
     f38:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     f40:	49 8b 56 30          	mov    0x30(%r14),%rdx
     f44:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     f4a:	48 85 d2             	test   %rdx,%rdx
     f4d:	0f 88 e4 f4 ff ff    	js     437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     f53:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
     f5b:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     f62:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
     f69:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     f71:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
     f76:	0f 88 bb f4 ff ff    	js     437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     f7c:	e9 af f3 ff ff       	jmp    330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     f81:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
     f88:	49 89 56 30          	mov    %rdx,0x30(%r14)
     f8c:	e9 27 f4 ff ff       	jmp    3b8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2e8>
     f91:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
     f98:	a8 0f                	test   $0xf,%al
     f9a:	0f 85 a0 04 00 00    	jne    1440 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1370>
     fa0:	89 c0                	mov    %eax,%eax
     fa2:	83 e2 0f             	and    $0xf,%edx
     fa5:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
     faa:	48 8b 07             	mov    (%rdi),%rax
     fad:	48 8b 77 08          	mov    0x8(%rdi),%rsi
     fb1:	49 89 86 90 02 00 00 	mov    %rax,0x290(%r14)
     fb8:	49 89 b6 98 02 00 00 	mov    %rsi,0x298(%r14)
     fbf:	0f 85 7b 04 00 00    	jne    1440 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1370>
     fc5:	49 8b 04 09          	mov    (%r9,%rcx,1),%rax
     fc9:	49 8b 54 09 08       	mov    0x8(%r9,%rcx,1),%rdx
     fce:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
     fd2:	48 c1 ee 20          	shr    $0x20,%rsi
     fd6:	c5 f9 6e fe          	vmovd  %esi,%xmm7
     fda:	49 89 86 a0 02 00 00 	mov    %rax,0x2a0(%r14)
     fe1:	c5 f9 6e d0          	vmovd  %eax,%xmm2
     fe5:	48 c1 e8 20          	shr    $0x20,%rax
     fe9:	c5 f9 6e e8          	vmovd  %eax,%xmm5
     fed:	49 89 96 a8 02 00 00 	mov    %rdx,0x2a8(%r14)
     ff4:	c5 e8 14 d5          	vunpcklps %xmm5,%xmm2,%xmm2
     ff8:	c5 fa 7e d2          	vmovq  %xmm2,%xmm2
     ffc:	c5 f8 5c c2          	vsubps %xmm2,%xmm0,%xmm0
    1000:	c5 f9 6e d2          	vmovd  %edx,%xmm2
    1004:	c5 f2 5c ca          	vsubss %xmm2,%xmm1,%xmm1
    1008:	c4 c1 78 13 86 90 02 00 00 	vmovlps %xmm0,0x290(%r14)
    1011:	c4 c1 7a 11 8e 98 02 00 00 	vmovss %xmm1,0x298(%r14)
    101a:	c5 f0 14 cf          	vunpcklps %xmm7,%xmm1,%xmm1
    101e:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
    1022:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
    1026:	49 8b 86 90 02 00 00 	mov    0x290(%r14),%rax
    102d:	49 8b 96 98 02 00 00 	mov    0x298(%r14),%rdx
    1034:	e9 35 fe ff ff       	jmp    e6e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd9e>
    1039:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    1040:	49 8b 76 30          	mov    0x30(%r14),%rsi
    1044:	4d 8b 66 38          	mov    0x38(%r14),%r12
    1048:	49 c1 e9 20          	shr    $0x20,%r9
    104c:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
    1050:	c4 c1 79 6e c1       	vmovd  %r9d,%xmm0
    1055:	49 89 9e 38 03 00 00 	mov    %rbx,0x338(%r14)
    105c:	c5 f9 6e ee          	vmovd  %esi,%xmm5
    1060:	48 c1 ee 20          	shr    $0x20,%rsi
    1064:	c5 52 59 f0          	vmulss %xmm0,%xmm5,%xmm14
    1068:	c5 f9 6e fe          	vmovd  %esi,%xmm7
    106c:	c5 7a 59 ff          	vmulss %xmm7,%xmm0,%xmm15
    1070:	c4 c1 79 6e fc       	vmovd  %r12d,%xmm7
    1075:	c5 7a 59 df          	vmulss %xmm7,%xmm0,%xmm11
    1079:	c5 fa 10 3d 00 00 00 00 	vmovss 0x0(%rip),%xmm7        # 1081 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xfb1>	107d: R_X86_64_PC32	.LC11-0x4
    1081:	c5 c2 5c ed          	vsubss %xmm5,%xmm7,%xmm5
    1085:	c5 7a 11 74 24 10    	vmovss %xmm14,0x10(%rsp)
    108b:	c5 7a 11 7c 24 14    	vmovss %xmm15,0x14(%rsp)
    1091:	c5 d2 59 e8          	vmulss %xmm0,%xmm5,%xmm5
    1095:	c5 7a 11 5c 24 18    	vmovss %xmm11,0x18(%rsp)
    109b:	c5 c2 5c fd          	vsubss %xmm5,%xmm7,%xmm7
    109f:	c5 7a 12 d7          	vmovsldup %xmm7,%xmm10
    10a3:	c5 a0 14 c7          	vunpcklps %xmm7,%xmm11,%xmm0
    10a7:	c5 fa 11 7c 24 1c    	vmovss %xmm7,0x1c(%rsp)
    10ad:	c5 ca 59 f7          	vmulss %xmm7,%xmm6,%xmm6
    10b1:	c4 41 7a 7e d2       	vmovq  %xmm10,%xmm10
    10b6:	c5 28 59 d1          	vmulps %xmm1,%xmm10,%xmm10
    10ba:	c4 c1 08 14 cf       	vunpcklps %xmm15,%xmm14,%xmm1
    10bf:	c4 c1 7a 11 b6 38 03 00 00 	vmovss %xmm6,0x338(%r14)
    10c8:	c5 f0 16 c0          	vmovlhps %xmm0,%xmm1,%xmm0
    10cc:	49 8b 9e 38 03 00 00 	mov    0x338(%r14),%rbx
    10d3:	c4 c1 78 29 86 70 03 00 00 	vmovaps %xmm0,0x370(%r14)
    10dc:	c4 41 78 13 96 30 03 00 00 	vmovlps %xmm10,0x330(%r14)
    10e5:	c4 c1 7a 16 c2       	vmovshdup %xmm10,%xmm0
    10ea:	c5 78 29 d1          	vmovaps %xmm10,%xmm1
    10ee:	49 8b 8e 30 03 00 00 	mov    0x330(%r14),%rcx
    10f5:	e9 18 f8 ff ff       	jmp    912 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x842>
    10fa:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
    1100:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    1107:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 110e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x103e>	110a: R_X86_64_PC32	g_ee_main_mem-0x4
    110e:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
    1117:	48 83 e8 60          	sub    $0x60,%rax
    111b:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    1122:	83 e0 f0             	and    $0xfffffff0,%eax
    1125:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    112b:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    1132:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
    113b:	83 c0 10             	add    $0x10,%eax
    113e:	83 e0 f0             	and    $0xfffffff0,%eax
    1141:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1147:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    114e:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
    1157:	83 c0 20             	add    $0x20,%eax
    115a:	83 e0 f0             	and    $0xfffffff0,%eax
    115d:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1163:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    116a:	c4 c1 79 6f 86 00 01 00 00 	vmovdqa 0x100(%r14),%xmm0
    1173:	83 c0 30             	add    $0x30,%eax
    1176:	83 e0 f0             	and    $0xfffffff0,%eax
    1179:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    117f:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    1186:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
    118f:	83 c0 40             	add    $0x40,%eax
    1192:	83 e0 f0             	and    $0xfffffff0,%eax
    1195:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    119b:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    11a2:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
    11ab:	83 c0 50             	add    $0x50,%eax
    11ae:	83 e0 f0             	and    $0xfffffff0,%eax
    11b1:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    11b7:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    11be:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
    11c7:	c4 c1 7a 7e 96 50 01 00 00 	vmovq  0x150(%r14),%xmm2
    11d0:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 11d7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1107>	11d3: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
    11d7:	c4 c1 7a 7e b6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm6
    11e0:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
    11e6:	c4 c1 79 d6 56 60    	vmovq  %xmm2,0x60(%r14)
    11ec:	c4 e3 e9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm2,%xmm2
    11f2:	49 89 56 70          	mov    %rdx,0x70(%r14)
    11f6:	48 63 08             	movslq (%rax),%rcx
    11f9:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
    1200:	48 89 c8             	mov    %rcx,%rax
    1203:	49 63 8e f0 01 00 00 	movslq 0x1f0(%r14),%rcx
    120a:	49 89 4e 20          	mov    %rcx,0x20(%r14)
    120e:	c4 c3 c9 22 9e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm6,%xmm3
    1218:	c4 c1 7a 7e ae 80 00 00 00 	vmovq  0x80(%r14),%xmm5
    1221:	c4 c3 f9 22 46 50 01 	vpinsrq $0x1,0x50(%r14),%xmm0,%xmm0
    1228:	c4 c3 d1 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm5,%xmm1
    1232:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
    1238:	c5 fd 7f 84 24 80 00 00 00 	vmovdqa %ymm0,0x80(%rsp)
    1241:	c4 e3 75 18 cb 01    	vinsertf128 $0x1,%xmm3,%ymm1,%ymm1
    1247:	c5 fd 7f 8c 24 a0 00 00 00 	vmovdqa %ymm1,0xa0(%rsp)
    1250:	85 c0                	test   %eax,%eax
    1252:	0f 84 a4 01 00 00    	je     13fc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x132c>
    1258:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    125f:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    1266:	89 c0                	mov    %eax,%eax
    1268:	31 d2                	xor    %edx,%edx
    126a:	48 8d b4 24 80 00 00 00 	lea    0x80(%rsp),%rsi
    1272:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
    1276:	c5 f8 77             	vzeroupper
    1279:	e8 00 00 00 00       	call   127e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x11ae>	127a: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    127e:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 1285 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x11b5>	1281: R_X86_64_PC32	g_ee_main_mem-0x4
    1285:	49 89 46 20          	mov    %rax,0x20(%r14)
    1289:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    1290:	48 89 c1             	mov    %rax,%rcx
    1293:	83 e1 f0             	and    $0xfffffff0,%ecx
    1296:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    129b:	8d 48 10             	lea    0x10(%rax),%ecx
    129e:	83 e1 f0             	and    $0xfffffff0,%ecx
    12a1:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    12aa:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    12af:	8d 48 20             	lea    0x20(%rax),%ecx
    12b2:	83 e1 f0             	and    $0xfffffff0,%ecx
    12b5:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    12be:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    12c3:	8d 48 30             	lea    0x30(%rax),%ecx
    12c6:	83 e1 f0             	and    $0xfffffff0,%ecx
    12c9:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    12d2:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    12d7:	8d 48 40             	lea    0x40(%rax),%ecx
    12da:	83 e1 f0             	and    $0xfffffff0,%ecx
    12dd:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
    12e6:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    12eb:	8d 48 50             	lea    0x50(%rax),%ecx
    12ee:	48 83 c0 60          	add    $0x60,%rax
    12f2:	83 e1 f0             	and    $0xfffffff0,%ecx
    12f5:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    12fe:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    1303:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    130a:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    1313:	e9 c6 f4 ff ff       	jmp    7de <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x70e>
    1318:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
    1320:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    1327:	49 89 4e 20          	mov    %rcx,0x20(%r14)
    132b:	89 c2                	mov    %eax,%edx
    132d:	49 8b 34 11          	mov    (%r9,%rdx,1),%rsi
    1331:	49 89 b6 f0 01 00 00 	mov    %rsi,0x1f0(%r14)
    1338:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
    133d:	49 89 96 e0 01 00 00 	mov    %rdx,0x1e0(%r14)
    1344:	8d 90 90 00 00 00    	lea    0x90(%rax),%edx
    134a:	83 e2 f0             	and    $0xfffffff0,%edx
    134d:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    1353:	8d 90 80 00 00 00    	lea    0x80(%rax),%edx
    1359:	83 e2 f0             	and    $0xfffffff0,%edx
    135c:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    1365:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    136b:	8d 50 70             	lea    0x70(%rax),%edx
    136e:	83 e2 f0             	and    $0xfffffff0,%edx
    1371:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    137a:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    1380:	8d 50 60             	lea    0x60(%rax),%edx
    1383:	83 e2 f0             	and    $0xfffffff0,%edx
    1386:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    138f:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    1395:	8d 50 50             	lea    0x50(%rax),%edx
    1398:	83 e2 f0             	and    $0xfffffff0,%edx
    139b:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    13a4:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    13aa:	8d 50 40             	lea    0x40(%rax),%edx
    13ad:	83 e2 f0             	and    $0xfffffff0,%edx
    13b0:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    13b9:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    13bf:	8d 50 30             	lea    0x30(%rax),%edx
    13c2:	48 05 a0 00 00 00    	add    $0xa0,%rax
    13c8:	83 e2 f0             	and    $0xfffffff0,%edx
    13cb:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    13d4:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    13da:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    13e1:	48 89 c8             	mov    %rcx,%rax
    13e4:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
    13ed:	48 8d 65 d8          	lea    -0x28(%rbp),%rsp
    13f1:	5b                   	pop    %rbx
    13f2:	41 5c                	pop    %r12
    13f4:	41 5d                	pop    %r13
    13f6:	41 5e                	pop    %r14
    13f8:	41 5f                	pop    %r15
    13fa:	5d                   	pop    %rbp
    13fb:	c3                   	ret
    13fc:	41 b8 00 00 00 00    	mov    $0x0,%r8d	13fe: R_X86_64_32	.rodata.str1.1+0xe
    1402:	b9 00 00 00 00       	mov    $0x0,%ecx	1403: R_X86_64_32	.rodata.str1.8+0xa8
    1407:	ba 90 01 00 00       	mov    $0x190,%edx
    140c:	be 00 00 00 00       	mov    $0x0,%esi	140d: R_X86_64_32	.rodata.str1.8+0x38
    1411:	bf 00 00 00 00       	mov    $0x0,%edi	1412: R_X86_64_32	.rodata.str1.1+0xf
    1416:	c5 f8 77             	vzeroupper
    1419:	e8 00 00 00 00       	call   141e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x134e>	141a: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    141e:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1420: R_X86_64_32	.rodata.str1.1+0xe
    1424:	b9 00 00 00 00       	mov    $0x0,%ecx	1425: R_X86_64_32	.rodata.str1.8+0x1d8
    1429:	ba c0 01 00 00       	mov    $0x1c0,%edx
    142e:	be 00 00 00 00       	mov    $0x0,%esi	142f: R_X86_64_32	.rodata.str1.8+0x38
    1433:	bf 00 00 00 00       	mov    $0x0,%edi	1434: R_X86_64_32	.rodata.str1.8+0x210
    1438:	c5 f8 77             	vzeroupper
    143b:	e8 00 00 00 00       	call   1440 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1370>	143c: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    1440:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1442: R_X86_64_32	.rodata.str1.1+0xe
    1446:	b9 00 00 00 00       	mov    $0x0,%ecx	1447: R_X86_64_32	.rodata.str1.8
    144b:	ba 58 01 00 00       	mov    $0x158,%edx
    1450:	be 00 00 00 00       	mov    $0x0,%esi	1451: R_X86_64_32	.rodata.str1.8+0x38
    1455:	bf 00 00 00 00       	mov    $0x0,%edi	1456: R_X86_64_32	.rodata.str1.8+0x78
    145a:	e8 00 00 00 00       	call   145f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x138f>	145b: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    145f:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1461: R_X86_64_32	.rodata.str1.1+0xe
    1465:	b9 00 00 00 00       	mov    $0x0,%ecx	1466: R_X86_64_32	.rodata.str1.8+0xd8
    146a:	ba 00 01 00 00       	mov    $0x100,%edx
    146f:	be 00 00 00 00       	mov    $0x0,%esi	1470: R_X86_64_32	.rodata.str1.8+0x110
    1474:	bf 00 00 00 00       	mov    $0x0,%edi	1475: R_X86_64_32	.rodata.str1.8+0x1a8
    1479:	e8 00 00 00 00       	call   147e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13ae>	147a: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    147e:	41 b8 00 00 00 00    	mov    $0x0,%r8d	1480: R_X86_64_32	.rodata.str1.1+0xe
    1484:	b9 00 00 00 00       	mov    $0x0,%ecx	1485: R_X86_64_32	.rodata.str1.8+0xd8
    1489:	ba fa 00 00 00       	mov    $0xfa,%edx
    148e:	be 00 00 00 00       	mov    $0x0,%esi	148f: R_X86_64_32	.rodata.str1.8+0x110
    1493:	bf 00 00 00 00       	mov    $0x0,%edi	1494: R_X86_64_32	.rodata.str1.8+0x178
    1498:	e8 00 00 00 00       	call   149d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13cd>	1499: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    149d:	0f 1f 00             	nopl   (%rax)

00000000000014a0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>:
    14a0:	4c 8d 54 24 08       	lea    0x8(%rsp),%r10
    14a5:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
    14a9:	41 ff 72 f8          	push   -0x8(%r10)
    14ad:	55                   	push   %rbp
    14ae:	48 89 e5             	mov    %rsp,%rbp
    14b1:	41 57                	push   %r15
    14b3:	41 56                	push   %r14
    14b5:	41 55                	push   %r13
    14b7:	41 54                	push   %r12
    14b9:	41 52                	push   %r10
    14bb:	53                   	push   %rbx
    14bc:	48 81 ec 40 01 00 00 	sub    $0x140,%rsp
    14c3:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
    14ca:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
    14d1:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 14d8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x38>	14d4: R_X86_64_PC32	g_ee_main_mem-0x4
    14d8:	48 83 c0 80          	add    $0xffffffffffffff80,%rax
    14dc:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
    14e3:	89 c0                	mov    %eax,%eax
    14e5:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
    14e9:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    14ef:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 14f6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x56>	14f2: R_X86_64_PC32	g_ee_main_mem-0x4
    14f6:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
    14fe:	83 c0 10             	add    $0x10,%eax
    1501:	83 e0 f0             	and    $0xfffffff0,%eax
    1504:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    150a:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    1510:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
    1518:	83 c0 20             	add    $0x20,%eax
    151b:	83 e0 f0             	and    $0xfffffff0,%eax
    151e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1524:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    152a:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
    1532:	83 c0 30             	add    $0x30,%eax
    1535:	83 e0 f0             	and    $0xfffffff0,%eax
    1538:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    153e:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    1544:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
    154c:	83 c0 40             	add    $0x40,%eax
    154f:	83 e0 f0             	and    $0xfffffff0,%eax
    1552:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1558:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    155e:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
    1566:	83 c0 50             	add    $0x50,%eax
    1569:	83 e0 f0             	and    $0xfffffff0,%eax
    156c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1572:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    1578:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
    1580:	83 c0 60             	add    $0x60,%eax
    1583:	83 e0 f0             	and    $0xfffffff0,%eax
    1586:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    158c:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    1592:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
    159a:	83 c0 70             	add    $0x70,%eax
    159d:	83 e0 f0             	and    $0xfffffff0,%eax
    15a0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    15a6:	48 8b 47 40          	mov    0x40(%rdi),%rax
    15aa:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
    15b1:	48 8b 47 50          	mov    0x50(%rdi),%rax
    15b5:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
    15bc:	48 8b 47 60          	mov    0x60(%rdi),%rax
    15c0:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
    15c7:	48 8b 47 70          	mov    0x70(%rdi),%rax
    15cb:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
    15d2:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
    15d9:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
    15e0:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
    15e7:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
    15ee:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 15f5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x155>	15f1: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
    15f5:	48 63 10             	movslq (%rax),%rdx
    15f8:	48 89 57 30          	mov    %rdx,0x30(%rdi)
    15fc:	f6 c2 0f             	test   $0xf,%dl
    15ff:	0f 85 7a 16 00 00    	jne    2c7f <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
    1605:	89 d0                	mov    %edx,%eax
    1607:	49 89 fe             	mov    %rdi,%r14
    160a:	49 8b 14 01          	mov    (%r9,%rax,1),%rdx
    160e:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
    1613:	48 89 97 10 03 00 00 	mov    %rdx,0x310(%rdi)
    161a:	48 89 57 30          	mov    %rdx,0x30(%rdi)
    161e:	81 e2 ff 00 00 00    	and    $0xff,%edx
    1624:	48 89 87 18 03 00 00 	mov    %rax,0x318(%rdi)
    162b:	48 89 47 38          	mov    %rax,0x38(%rdi)
    162f:	48 89 97 00 01 00 00 	mov    %rdx,0x100(%rdi)
    1636:	e9 ba 00 00 00       	jmp    16f5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x255>
    163b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    1640:	48 63 09             	movslq (%rcx),%rcx
    1643:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
    164b:	49 89 4e 30          	mov    %rcx,0x30(%r14)
    164f:	85 c9                	test   %ecx,%ecx
    1651:	0f 84 91 0e 00 00    	je     24e8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1048>
    1657:	8b 06                	mov    (%rsi),%eax
    1659:	89 c1                	mov    %eax,%ecx
    165b:	83 e0 bf             	and    $0xffffffbf,%eax
    165e:	83 e1 40             	and    $0x40,%ecx
    1661:	48 63 d0             	movslq %eax,%rdx
    1664:	89 cb                	mov    %ecx,%ebx
    1666:	49 89 56 40          	mov    %rdx,0x40(%r14)
    166a:	49 89 5e 30          	mov    %rbx,0x30(%r14)
    166e:	89 06                	mov    %eax,(%rsi)
    1670:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    1677:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 167e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1de>	167a: R_X86_64_PC32	g_ee_main_mem-0x4
    167e:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    1685:	85 c9                	test   %ecx,%ecx
    1687:	74 27                	je     16b0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    1689:	89 c0                	mov    %eax,%eax
    168b:	89 d2                	mov    %edx,%edx
    168d:	49 63 4c 01 7c       	movslq 0x7c(%r9,%rax,1),%rcx
    1692:	49 89 4e 30          	mov    %rcx,0x30(%r14)
    1696:	41 89 4c 11 2c       	mov    %ecx,0x2c(%r9,%rdx,1)
    169b:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    16a2:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    16a9:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 16b0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>	16ac: R_X86_64_PC32	g_ee_main_mem-0x4
    16b0:	48 05 90 00 00 00    	add    $0x90,%rax
    16b6:	49 8b 9e 30 01 00 00 	mov    0x130(%r14),%rbx
    16bd:	48 83 c2 30          	add    $0x30,%rdx
    16c1:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
    16c8:	49 8b 86 10 01 00 00 	mov    0x110(%r14),%rax
    16cf:	48 8d 4b ff          	lea    -0x1(%rbx),%rcx
    16d3:	49 89 96 40 01 00 00 	mov    %rdx,0x140(%r14)
    16da:	48 83 c0 01          	add    $0x1,%rax
    16de:	49 89 8e 30 01 00 00 	mov    %rcx,0x130(%r14)
    16e5:	49 89 86 10 01 00 00 	mov    %rax,0x110(%r14)
    16ec:	48 85 c9             	test   %rcx,%rcx
    16ef:	0f 84 cb 0e 00 00    	je     25c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1120>
    16f5:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    16fc:	49 8b be 70 01 00 00 	mov    0x170(%r14),%rdi
    1703:	89 c1                	mov    %eax,%ecx
    1705:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
    170d:	49 89 56 30          	mov    %rdx,0x30(%r14)
    1711:	48 39 d7             	cmp    %rdx,%rdi
    1714:	0f 84 be 0d 00 00    	je     24d8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1038>
    171a:	49 8d 74 09 68       	lea    0x68(%r9,%rcx,1),%rsi
    171f:	49 8d 4c 09 64       	lea    0x64(%r9,%rcx,1),%rcx
    1724:	48 63 16             	movslq (%rsi),%rdx
    1727:	49 3b be 20 01 00 00 	cmp    0x120(%r14),%rdi
    172e:	0f 84 c4 0d 00 00    	je     24f8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1058>
    1734:	81 e2 00 20 00 00    	and    $0x2000,%edx
    173a:	89 d3                	mov    %edx,%ebx
    173c:	49 89 5e 30          	mov    %rbx,0x30(%r14)
    1740:	0f 84 fa fe ff ff    	je     1640 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1a0>
    1746:	48 63 11             	movslq (%rcx),%rdx
    1749:	48 89 d7             	mov    %rdx,%rdi
    174c:	49 2b be 00 01 00 00 	sub    0x100(%r14),%rdi
    1753:	49 89 56 30          	mov    %rdx,0x30(%r14)
    1757:	49 89 7e 40          	mov    %rdi,0x40(%r14)
    175b:	48 83 fa ff          	cmp    $0xffffffffffffffff,%rdx
    175f:	74 51                	je     17b2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x312>
    1761:	48 89 fe             	mov    %rdi,%rsi
    1764:	c4 c1 79 6e 6e 48    	vmovd  0x48(%r14),%xmm5
    176a:	c4 c3 51 22 4e 4c 01 	vpinsrd $0x1,0x4c(%r14),%xmm5,%xmm1
    1771:	c5 f9 6e ef          	vmovd  %edi,%xmm5
    1775:	48 c1 fe 20          	sar    $0x20,%rsi
    1779:	c4 e3 51 22 c6 01    	vpinsrd $0x1,%esi,%xmm5,%xmm0
    177f:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
    1783:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
    1787:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
    178c:	c4 c1 79 7f 46 30    	vmovdqa %xmm0,0x30(%r14)
    1792:	48 85 d2             	test   %rdx,%rdx
    1795:	0f 84 4d 0d 00 00    	je     24e8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1048>
    179b:	c5 f9 7e 01          	vmovd  %xmm0,(%rcx)
    179f:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
    17a6:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 17ad <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x30d>	17a9: R_X86_64_PC32	g_ee_main_mem-0x4
    17ad:	48 8d 74 02 68       	lea    0x68(%rdx,%rax,1),%rsi
    17b2:	8b 06                	mov    (%rsi),%eax
    17b4:	89 c2                	mov    %eax,%edx
    17b6:	83 e0 bf             	and    $0xffffffbf,%eax
    17b9:	83 e2 40             	and    $0x40,%edx
    17bc:	48 63 c8             	movslq %eax,%rcx
    17bf:	89 d3                	mov    %edx,%ebx
    17c1:	49 89 4e 40          	mov    %rcx,0x40(%r14)
    17c5:	49 89 5e 30          	mov    %rbx,0x30(%r14)
    17c9:	89 06                	mov    %eax,(%rsi)
    17cb:	85 d2                	test   %edx,%edx
    17cd:	74 25                	je     17f4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x354>
    17cf:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
    17d6:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 17dd <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x33d>	17d9: R_X86_64_PC32	g_ee_main_mem-0x4
    17dd:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
    17e2:	49 89 4e 30          	mov    %rcx,0x30(%r14)
    17e6:	48 89 ca             	mov    %rcx,%rdx
    17e9:	41 8b 8e 40 01 00 00 	mov    0x140(%r14),%ecx
    17f0:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
    17f4:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 17fb <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x35b>	17f7: R_X86_64_PC32	g_ee_main_mem-0x4
    17fb:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
    1802:	49 63 4c 01 70       	movslq 0x70(%r9,%rax,1),%rcx
    1807:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
    180e:	85 c9                	test   %ecx,%ecx
    1810:	0f 84 fa 01 00 00    	je     1a10 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
    1816:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
    181f:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    1826:	48 83 e8 50          	sub    $0x50,%rax
    182a:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    1831:	83 e0 f0             	and    $0xfffffff0,%eax
    1834:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    183a:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    1841:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
    184a:	83 c0 10             	add    $0x10,%eax
    184d:	83 e0 f0             	and    $0xfffffff0,%eax
    1850:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1856:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    185d:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
    1866:	83 c0 20             	add    $0x20,%eax
    1869:	83 e0 f0             	and    $0xfffffff0,%eax
    186c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1872:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    1879:	c4 c1 79 6f 86 10 01 00 00 	vmovdqa 0x110(%r14),%xmm0
    1882:	83 c0 30             	add    $0x30,%eax
    1885:	83 e0 f0             	and    $0xfffffff0,%eax
    1888:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    188e:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
    1895:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
    189e:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
    18a5:	49 89 46 40          	mov    %rax,0x40(%r14)
    18a9:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    18b0:	49 89 46 50          	mov    %rax,0x50(%r14)
    18b4:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
    18bb:	49 89 46 60          	mov    %rax,0x60(%r14)
    18bf:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    18c6:	83 c0 40             	add    $0x40,%eax
    18c9:	83 e0 f0             	and    $0xfffffff0,%eax
    18cc:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    18d2:	c4 c1 7a 7e 6e 60    	vmovq  0x60(%r14),%xmm5
    18d8:	c4 c1 7a 7e a6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm4
    18e1:	c4 c3 d9 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm4,%xmm1
    18eb:	c4 c3 d1 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm5,%xmm2
    18f2:	c4 c1 7a 7e a6 80 00 00 00 	vmovq  0x80(%r14),%xmm4
    18fb:	c4 c3 d9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm4,%xmm0
    1905:	c4 c1 7a 7e 66 40    	vmovq  0x40(%r14),%xmm4
    190b:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
    1911:	c4 c3 d9 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm4,%xmm1
    1918:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
    191e:	c5 fd 7f 8d d0 fe ff ff 	vmovdqa %ymm1,-0x130(%rbp)
    1926:	c5 fd 7f 85 f0 fe ff ff 	vmovdqa %ymm0,-0x110(%rbp)
    192e:	85 ff                	test   %edi,%edi
    1930:	0f 84 8a 13 00 00    	je     2cc0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
    1936:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    193d:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    1944:	4c 01 cf             	add    %r9,%rdi
    1947:	31 d2                	xor    %edx,%edx
    1949:	48 8d b5 d0 fe ff ff 	lea    -0x130(%rbp),%rsi
    1950:	c5 f8 77             	vzeroupper
    1953:	e8 00 00 00 00       	call   1958 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4b8>	1954: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    1958:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 195f <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4bf>	195b: R_X86_64_PC32	g_ee_main_mem-0x4
    195f:	49 89 46 20          	mov    %rax,0x20(%r14)
    1963:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    196a:	48 89 c1             	mov    %rax,%rcx
    196d:	83 e1 f0             	and    $0xfffffff0,%ecx
    1970:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    1975:	8d 48 10             	lea    0x10(%rax),%ecx
    1978:	83 e1 f0             	and    $0xfffffff0,%ecx
    197b:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    1984:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    1989:	8d 48 20             	lea    0x20(%rax),%ecx
    198c:	83 e1 f0             	and    $0xfffffff0,%ecx
    198f:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    1998:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    199d:	8d 48 30             	lea    0x30(%rax),%ecx
    19a0:	83 e1 f0             	and    $0xfffffff0,%ecx
    19a3:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    19ac:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    19b1:	8d 48 40             	lea    0x40(%rax),%ecx
    19b4:	48 83 c0 50          	add    $0x50,%rax
    19b8:	83 e1 f0             	and    $0xfffffff0,%ecx
    19bb:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    19c4:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    19c9:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    19d0:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    19d9:	e8 22 e6 ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
    19de:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
    19e5:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 19ec <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x54c>	19e8: R_X86_64_PC32	g_ee_main_mem-0x4
    19ec:	84 c0                	test   %al,%al
    19ee:	89 f0                	mov    %esi,%eax
    19f0:	74 1e                	je     1a10 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
    19f2:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 19f8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x558>	19f4: R_X86_64_PC32	.bss+0x128
    19f8:	81 fa 3f 1f 00 00    	cmp    $0x1f3f,%edx
    19fe:	0f 8e dc 10 00 00    	jle    2ae0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1640>
    1a04:	90                   	nop
    1a05:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
    1a10:	49 63 4c 01 78       	movslq 0x78(%r9,%rax,1),%rcx
    1a15:	49 89 4e 50          	mov    %rcx,0x50(%r14)
    1a19:	48 89 ca             	mov    %rcx,%rdx
    1a1c:	49 8d 4c 01 74       	lea    0x74(%r9,%rax,1),%rcx
    1a21:	48 63 01             	movslq (%rcx),%rax
    1a24:	49 89 46 30          	mov    %rax,0x30(%r14)
    1a28:	49 2b 86 00 01 00 00 	sub    0x100(%r14),%rax
    1a2f:	49 89 46 40          	mov    %rax,0x40(%r14)
    1a33:	85 d2                	test   %edx,%edx
    1a35:	74 13                	je     1a4a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
    1a37:	48 8d 50 ff          	lea    -0x1(%rax),%rdx
    1a3b:	49 89 56 30          	mov    %rdx,0x30(%r14)
    1a3f:	89 01                	mov    %eax,(%rcx)
    1a41:	48 85 d2             	test   %rdx,%rdx
    1a44:	0f 88 46 0c 00 00    	js     2690 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x11f0>
    1a4a:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    1a51:	f6 c2 0f             	test   $0xf,%dl
    1a54:	0f 85 25 12 00 00    	jne    2c7f <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
    1a5a:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1a61 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5c1>	1a5d: R_X86_64_PC32	g_ee_main_mem-0x4
    1a61:	89 d2                	mov    %edx,%edx
    1a63:	4d 8b 96 50 01 00 00 	mov    0x150(%r14),%r10
    1a6a:	c5 7a 7e 04 10       	vmovq  (%rax,%rdx,1),%xmm8
    1a6f:	48 8b 4c 10 08       	mov    0x8(%rax,%rdx,1),%rcx
    1a74:	c4 41 79 d6 86 90 02 00 00 	vmovq  %xmm8,0x290(%r14)
    1a7d:	49 89 8e 98 02 00 00 	mov    %rcx,0x298(%r14)
    1a84:	48 8b 74 10 10       	mov    0x10(%rax,%rdx,1),%rsi
    1a89:	4c 8b 44 10 18       	mov    0x18(%rax,%rdx,1),%r8
    1a8e:	49 89 b6 a0 02 00 00 	mov    %rsi,0x2a0(%r14)
    1a95:	4d 89 86 a8 02 00 00 	mov    %r8,0x2a8(%r14)
    1a9c:	48 8b 74 10 20       	mov    0x20(%rax,%rdx,1),%rsi
    1aa1:	48 8b 7c 10 28       	mov    0x28(%rax,%rdx,1),%rdi
    1aa6:	49 89 b6 b0 02 00 00 	mov    %rsi,0x2b0(%r14)
    1aad:	49 89 be b8 02 00 00 	mov    %rdi,0x2b8(%r14)
    1ab4:	41 f6 c2 0f          	test   $0xf,%r10b
    1ab8:	0f 85 c1 11 00 00    	jne    2c7f <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
    1abe:	45 89 d2             	mov    %r10d,%r10d
    1ac1:	c4 63 b9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm8,%xmm8
    1ac7:	c4 c1 7a 10 b6 18 03 00 00 	vmovss 0x318(%r14),%xmm6
    1ad0:	c4 41 7a 10 a6 1c 03 00 00 	vmovss 0x31c(%r14),%xmm12
    1ad9:	4e 8d 64 10 10       	lea    0x10(%rax,%r10,1),%r12
    1ade:	49 8b 0c 24          	mov    (%r12),%rcx
    1ae2:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
    1ae7:	c5 c8 c6 d6 00       	vshufps $0x0,%xmm6,%xmm6,%xmm2
    1aec:	49 89 8e c0 02 00 00 	mov    %rcx,0x2c0(%r14)
    1af3:	49 89 d5             	mov    %rdx,%r13
    1af6:	49 89 96 c8 02 00 00 	mov    %rdx,0x2c8(%r14)
    1afd:	4e 8b 4c 10 20       	mov    0x20(%rax,%r10,1),%r9
    1b02:	49 c1 ed 20          	shr    $0x20,%r13
    1b06:	4a 8b 5c 10 28       	mov    0x28(%rax,%r10,1),%rbx
    1b0b:	4d 89 8e d0 02 00 00 	mov    %r9,0x2d0(%r14)
    1b12:	49 89 9e d8 02 00 00 	mov    %rbx,0x2d8(%r14)
    1b19:	4e 8b 5c 10 38       	mov    0x38(%rax,%r10,1),%r11
    1b1e:	c4 a1 7a 7e 4c 10 30 	vmovq  0x30(%rax,%r10,1),%xmm1
    1b25:	4d 89 9e e8 02 00 00 	mov    %r11,0x2e8(%r14)
    1b2c:	c4 c1 f9 6e eb       	vmovq  %r11,%xmm5
    1b31:	45 89 df             	mov    %r11d,%r15d
    1b34:	c4 c1 79 d6 8e e0 02 00 00 	vmovq  %xmm1,0x2e0(%r14)
    1b3d:	c4 c3 f1 22 e3 01    	vpinsrq $0x1,%r11,%xmm1,%xmm4
    1b43:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
    1b48:	c4 a1 7a 6f 7c 10 40 	vmovdqu 0x40(%rax,%r10,1),%xmm7
    1b4f:	c4 c1 7a 7e 8e 14 03 00 00 	vmovq  0x314(%r14),%xmm1
    1b58:	c5 79 6f fd          	vmovdqa %xmm5,%xmm15
    1b5c:	c5 e8 59 d7          	vmulps %xmm7,%xmm2,%xmm2
    1b60:	c5 f9 6f ef          	vmovdqa %xmm7,%xmm5
    1b64:	c5 f9 6f df          	vmovdqa %xmm7,%xmm3
    1b68:	c4 c1 7a 7f be f0 02 00 00 	vmovdqu %xmm7,0x2f0(%r14)
    1b71:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
    1b76:	c5 7a 12 d9          	vmovsldup %xmm1,%xmm11
    1b7a:	c5 79 6f ed          	vmovdqa %xmm5,%xmm13
    1b7e:	c5 70 c6 f1 00       	vshufps $0x0,%xmm1,%xmm1,%xmm14
    1b83:	c5 f0 c6 e9 00       	vshufps $0x0,%xmm1,%xmm1,%xmm5
    1b88:	c5 fa 16 c9          	vmovshdup %xmm1,%xmm1
    1b8c:	c4 41 60 14 cd       	vunpcklps %xmm13,%xmm3,%xmm9
    1b91:	c5 f9 6e f9          	vmovd  %ecx,%xmm7
    1b95:	c4 41 7a 7e c9       	vmovq  %xmm9,%xmm9
    1b9a:	48 c1 e9 20          	shr    $0x20,%rcx
    1b9e:	4e 63 54 10 60       	movslq 0x60(%rax,%r10,1),%r10
    1ba3:	c4 43 0d 18 f6 01    	vinsertf128 $0x1,%xmm14,%ymm14,%ymm14
    1ba9:	c5 79 6e d1          	vmovd  %ecx,%xmm10
    1bad:	c4 c1 78 29 96 f0 02 00 00 	vmovaps %xmm2,0x2f0(%r14)
    1bb6:	c5 e8 15 d2          	vunpckhps %xmm2,%xmm2,%xmm2
    1bba:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
    1bbe:	45 89 96 00 02 00 00 	mov    %r10d,0x200(%r14)
    1bc5:	c4 c1 70 59 c9       	vmulps %xmm9,%xmm1,%xmm1
    1bca:	c4 41 40 14 ca       	vunpcklps %xmm10,%xmm7,%xmm9
    1bcf:	4d 89 56 30          	mov    %r10,0x30(%r14)
    1bd3:	c4 41 7a 7e c9       	vmovq  %xmm9,%xmm9
    1bd8:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
    1bdc:	c4 c1 70 58 c9       	vaddps %xmm9,%xmm1,%xmm1
    1be1:	c5 79 6e ca          	vmovd  %edx,%xmm9
    1be5:	c4 c1 6a 58 d1       	vaddss %xmm9,%xmm2,%xmm2
    1bea:	c4 c1 78 13 8e c0 02 00 00 	vmovlps %xmm1,0x2c0(%r14)
    1bf3:	c4 c1 7a 11 96 c8 02 00 00 	vmovss %xmm2,0x2c8(%r14)
    1bfc:	45 85 d2             	test   %r10d,%r10d
    1bff:	0f 85 03 09 00 00    	jne    2508 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1068>
    1c05:	c5 fa 16 f1          	vmovshdup %xmm1,%xmm6
    1c09:	c5 f8 28 d9          	vmovaps %xmm1,%xmm3
    1c0d:	c4 c1 79 6e fd       	vmovd  %r13d,%xmm7
    1c12:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
    1c16:	c4 c1 79 6e c9       	vmovd  %r9d,%xmm1
    1c1b:	49 c1 e9 20          	shr    $0x20,%r9
    1c1f:	c5 d0 59 e4          	vmulps %xmm4,%xmm5,%xmm4
    1c23:	c5 e8 14 d7          	vunpcklps %xmm7,%xmm2,%xmm2
    1c27:	c4 41 7a 7e db       	vmovq  %xmm11,%xmm11
    1c2c:	c5 e0 16 d2          	vmovlhps %xmm2,%xmm3,%xmm2
    1c30:	c5 e8 59 ed          	vmulps %xmm5,%xmm2,%xmm5
    1c34:	c5 f9 6e db          	vmovd  %ebx,%xmm3
    1c38:	48 c1 eb 20          	shr    $0x20,%rbx
    1c3c:	c5 f9 6e f3          	vmovd  %ebx,%xmm6
    1c40:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
    1c44:	c4 c1 79 6e f1       	vmovd  %r9d,%xmm6
    1c49:	c5 f0 14 ce          	vunpcklps %xmm6,%xmm1,%xmm1
    1c4d:	c4 c1 79 6e f7       	vmovd  %r15d,%xmm6
    1c52:	c5 f0 16 cb          	vmovlhps %xmm3,%xmm1,%xmm1
    1c56:	c4 e3 6d 18 c9 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm1
    1c5c:	c4 c1 48 14 c7       	vunpcklps %xmm15,%xmm6,%xmm0
    1c61:	c4 c1 79 6e d8       	vmovd  %r8d,%xmm3
    1c66:	c4 c1 74 59 ce       	vmulps %ymm14,%ymm1,%ymm1
    1c6b:	c4 c1 50 58 e8       	vaddps %xmm8,%xmm5,%xmm5
    1c70:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
    1c74:	49 c1 e8 20          	shr    $0x20,%r8
    1c78:	c4 c1 78 59 c3       	vmulps %xmm11,%xmm0,%xmm0
    1c7d:	c4 c1 79 6e f8       	vmovd  %r8d,%xmm7
    1c82:	c4 c1 78 29 a6 40 03 00 00 	vmovaps %xmm4,0x340(%r14)
    1c8b:	c4 c1 78 29 ae 90 02 00 00 	vmovaps %xmm5,0x290(%r14)
    1c94:	c4 c1 7c 11 8e 20 03 00 00 	vmovups %ymm1,0x320(%r14)
    1c9d:	c4 e3 7d 19 c9 01    	vextractf128 $0x1,%ymm1,%xmm1
    1ca3:	c5 f0 15 e9          	vunpckhps %xmm1,%xmm1,%xmm5
    1ca7:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
    1cab:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
    1cb0:	c5 f2 58 cf          	vaddss %xmm7,%xmm1,%xmm1
    1cb4:	c5 d2 58 eb          	vaddss %xmm3,%xmm5,%xmm5
    1cb8:	c5 f9 6e df          	vmovd  %edi,%xmm3
    1cbc:	48 c1 ef 20          	shr    $0x20,%rdi
    1cc0:	c5 f9 6e f7          	vmovd  %edi,%xmm6
    1cc4:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
    1cc8:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
    1ccc:	c5 d0 14 c9          	vunpcklps %xmm1,%xmm5,%xmm1
    1cd0:	c5 f8 58 c3          	vaddps %xmm3,%xmm0,%xmm0
    1cd4:	c5 f9 6e de          	vmovd  %esi,%xmm3
    1cd8:	48 c1 ee 20          	shr    $0x20,%rsi
    1cdc:	c5 da 58 f3          	vaddss %xmm3,%xmm4,%xmm6
    1ce0:	c5 f9 6e fe          	vmovd  %esi,%xmm7
    1ce4:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
    1ce9:	c5 e0 57 db          	vxorps %xmm3,%xmm3,%xmm3
    1ced:	c5 da 58 e7          	vaddss %xmm7,%xmm4,%xmm4
    1cf1:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
    1cf5:	c5 78 28 c0          	vmovaps %xmm0,%xmm8
    1cf9:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
    1cfd:	c5 ca c2 ff 05       	vcmpnltss %xmm7,%xmm6,%xmm7
    1d02:	c4 e3 61 4a de 70    	vblendvps %xmm7,%xmm6,%xmm3,%xmm3
    1d08:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
    1d0c:	c5 c8 57 f6          	vxorps %xmm6,%xmm6,%xmm6
    1d10:	c5 da c2 ff 05       	vcmpnltss %xmm7,%xmm4,%xmm7
    1d15:	c4 e3 49 4a f4 70    	vblendvps %xmm7,%xmm4,%xmm6,%xmm6
    1d1b:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
    1d1f:	c5 f0 16 cb          	vmovlhps %xmm3,%xmm1,%xmm1
    1d23:	c4 c1 78 11 8e a8 02 00 00 	vmovups %xmm1,0x2a8(%r14)
    1d2c:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
    1d30:	c5 f8 c2 c1 01       	vcmpltps %xmm1,%xmm0,%xmm0
    1d35:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
    1d39:	c4 63 39 4a c1 00    	vblendvps %xmm0,%xmm1,%xmm8,%xmm8
    1d3f:	c4 41 78 13 86 b8 02 00 00 	vmovlps %xmm8,0x2b8(%r14)
    1d48:	c4 c1 78 11 14 24    	vmovups %xmm2,(%r12)
    1d4e:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    1d55:	f6 c2 0f             	test   $0xf,%dl
    1d58:	0f 85 40 0f 00 00    	jne    2c9e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
    1d5e:	c4 c1 79 6f 86 90 02 00 00 	vmovdqa 0x290(%r14),%xmm0
    1d67:	89 d2                	mov    %edx,%edx
    1d69:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    1d6e:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    1d75:	f6 c2 0f             	test   $0xf,%dl
    1d78:	0f 85 20 0f 00 00    	jne    2c9e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
    1d7e:	c4 c1 79 6f 86 a0 02 00 00 	vmovdqa 0x2a0(%r14),%xmm0
    1d87:	89 d2                	mov    %edx,%edx
    1d89:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
    1d8f:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    1d96:	f6 c2 0f             	test   $0xf,%dl
    1d99:	0f 85 ff 0e 00 00    	jne    2c9e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
    1d9f:	c4 c1 79 6f 86 b0 02 00 00 	vmovdqa 0x2b0(%r14),%xmm0
    1da8:	89 d2                	mov    %edx,%edx
    1daa:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
    1db0:	c5 f8 77             	vzeroupper
    1db3:	e8 48 e2 ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
    1db8:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
    1dbf:	84 c0                	test   %al,%al
    1dc1:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1dc8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x928>	1dc4: R_X86_64_PC32	g_ee_main_mem-0x4
    1dc8:	0f 84 b2 00 00 00    	je     1e80 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
    1dce:	8b 0d 00 00 00 00    	mov    0x0(%rip),%ecx        # 1dd4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x934>	1dd0: R_X86_64_PC32	.bss+0x120
    1dd4:	81 f9 3f 1f 00 00    	cmp    $0x1f3f,%ecx
    1dda:	0f 8f a0 00 00 00    	jg     1e80 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
    1de0:	48 8b 7c 10 20       	mov    0x20(%rax,%rdx,1),%rdi
    1de5:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
    1dec:	4c 8b 44 10 28       	mov    0x28(%rax,%rdx,1),%r8
    1df1:	41 89 f2             	mov    %esi,%r10d
    1df4:	c5 79 6e c7          	vmovd  %edi,%xmm8
    1df8:	c5 78 2f 05 00 00 00 00 	vcomiss 0x0(%rip),%xmm8        # 1e00 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x960>	1dfc: R_X86_64_PC32	.LC21-0x4
    1e00:	4e 8b 4c 10 30       	mov    0x30(%rax,%r10,1),%r9
    1e05:	c4 c1 79 6e d0       	vmovd  %r8d,%xmm2
    1e0a:	4e 8b 54 10 38       	mov    0x38(%rax,%r10,1),%r10
    1e0f:	c4 c1 79 6e e1       	vmovd  %r9d,%xmm4
    1e14:	0f 87 a6 0b 00 00    	ja     29c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1520>
    1e1a:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    1e1e:	c5 f8 2e d0          	vucomiss %xmm0,%xmm2
    1e22:	7a 3c                	jp     1e60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    1e24:	75 3a                	jne    1e60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    1e26:	c4 e1 f9 6e f7       	vmovq  %rdi,%xmm6
    1e2b:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
    1e30:	c5 f8 2f 35 00 00 00 00 	vcomiss 0x0(%rip),%xmm6        # 1e38 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x998>	1e34: R_X86_64_PC32	.LC22-0x4
    1e38:	c5 f9 6f ce          	vmovdqa %xmm6,%xmm1
    1e3c:	72 22                	jb     1e60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    1e3e:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # 1e46 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9a6>	1e42: R_X86_64_PC32	.LC23-0x4
    1e46:	c4 c1 78 2f c0       	vcomiss %xmm8,%xmm0
    1e4b:	0f 83 9f 0b 00 00    	jae    29f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1550>
    1e51:	0f 1f 40 00          	nopl   0x0(%rax)
    1e55:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
    1e60:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # 1e68 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c8>	1e64: R_X86_64_PC32	.LC24-0x4
    1e68:	c5 f8 2f c4          	vcomiss %xmm4,%xmm0
    1e6c:	0f 87 3a 0d 00 00    	ja     2bac <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x170c>
    1e72:	0f 1f 00             	nopl   (%rax)
    1e75:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
    1e80:	48 8d 54 10 18       	lea    0x18(%rax,%rdx,1),%rdx
    1e85:	c5 d8 57 e4          	vxorps %xmm4,%xmm4,%xmm4
    1e89:	c5 fa 2c 02          	vcvttss2si (%rdx),%eax
    1e8d:	48 0f bf c8          	movswq %ax,%rcx
    1e91:	98                   	cwtl
    1e92:	c5 da 2a c0          	vcvtsi2ss %eax,%xmm4,%xmm0
    1e96:	49 89 4e 30          	mov    %rcx,0x30(%r14)
    1e9a:	c4 c1 7a 11 86 00 02 00 00 	vmovss %xmm0,0x200(%r14)
    1ea3:	c5 fa 11 02          	vmovss %xmm0,(%rdx)
    1ea7:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    1eae:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1eb5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa15>	1eb1: R_X86_64_PC32	g_ee_main_mem-0x4
    1eb5:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # 1ebc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa1c>	1eb8: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0xc
    1ebc:	89 c2                	mov    %eax,%edx
    1ebe:	49 8d 7c 11 68       	lea    0x68(%r9,%rdx,1),%rdi
    1ec3:	8b 17                	mov    (%rdi),%edx
    1ec5:	81 e2 80 00 00 00    	and    $0x80,%edx
    1ecb:	89 d3                	mov    %edx,%ebx
    1ecd:	49 89 5e 30          	mov    %rbx,0x30(%r14)
    1ed1:	48 63 09             	movslq (%rcx),%rcx
    1ed4:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
    1edb:	0f 84 ff 03 00 00    	je     22e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe40>
    1ee1:	e8 1a e1 ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
    1ee6:	89 c3                	mov    %eax,%ebx
    1ee8:	84 c0                	test   %al,%al
    1eea:	0f 84 d1 01 00 00    	je     20c1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>
    1ef0:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 1ef6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa56>	1ef2: R_X86_64_PC32	.bss+0x11c
    1ef6:	81 fa 9f 86 01 00    	cmp    $0x1869f,%edx
    1efc:	0f 8f d6 0b 00 00    	jg     2ad8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1638>
    1f02:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1f09 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa69>	1f05: R_X86_64_PC32	g_ee_main_mem-0x4
    1f09:	41 8b 8e 50 01 00 00 	mov    0x150(%r14),%ecx
    1f10:	83 c2 01             	add    $0x1,%edx
    1f13:	41 8b be 40 01 00 00 	mov    0x140(%r14),%edi
    1f1a:	89 15 00 00 00 00    	mov    %edx,0x0(%rip)        # 1f20 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa80>	1f1c: R_X86_64_PC32	.bss+0x11c
    1f20:	44 8b 64 08 6c       	mov    0x6c(%rax,%rcx,1),%r12d
    1f25:	89 8d 9c fe ff ff    	mov    %ecx,-0x164(%rbp)
    1f2b:	c5 f9 6e 4c 08 08    	vmovd  0x8(%rax,%rcx,1),%xmm1
    1f31:	c5 79 6e 44 08 0c    	vmovd  0xc(%rax,%rcx,1),%xmm8
    1f37:	45 8d 5c 24 ef       	lea    -0x11(%r12),%r11d
    1f3c:	4c 8b 44 08 10       	mov    0x10(%rax,%rcx,1),%r8
    1f41:	4c 8b 54 08 18       	mov    0x18(%rax,%rcx,1),%r10
    1f46:	4c 8b 4c 08 50       	mov    0x50(%rax,%rcx,1),%r9
    1f4b:	48 8b 54 08 58       	mov    0x58(%rax,%rcx,1),%rdx
    1f50:	4c 8b 6c 38 08       	mov    0x8(%rax,%rdi,1),%r13
    1f55:	48 8b 0c 38          	mov    (%rax,%rdi,1),%rcx
    1f59:	48 8b 74 38 20       	mov    0x20(%rax,%rdi,1),%rsi
    1f5e:	48 8b 7c 38 28       	mov    0x28(%rax,%rdi,1),%rdi
    1f63:	41 81 fb e2 ff ff 07 	cmp    $0x7ffffe2,%r11d
    1f6a:	0f 86 cb 0c 00 00    	jbe    2c3b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x179b>
    1f70:	c4 41 31 57 c9       	vxorpd %xmm9,%xmm9,%xmm9
    1f75:	c5 79 29 ca          	vmovapd %xmm9,%xmm2
    1f79:	c4 41 79 28 d1       	vmovapd %xmm9,%xmm10
    1f7e:	4c 8b 1d 00 00 00 00 	mov    0x0(%rip),%r11        # 1f85 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xae5>	1f81: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
    1f85:	c5 d0 57 ed          	vxorps %xmm5,%xmm5,%xmm5
    1f89:	45 8b 1b             	mov    (%r11),%r11d
    1f8c:	45 8d 7b ef          	lea    -0x11(%r11),%r15d
    1f90:	41 81 ff e6 ff ff 07 	cmp    $0x7ffffe6,%r15d
    1f97:	77 07                	ja     1fa0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb00>
    1f99:	c4 a1 7a 10 6c 18 04 	vmovss 0x4(%rax,%r11,1),%xmm5
    1fa0:	48 83 ec 60          	sub    $0x60,%rsp
    1fa4:	c4 c1 79 6e f1       	vmovd  %r9d,%xmm6
    1fa9:	c4 e1 f9 6e c7       	vmovq  %rdi,%xmm0
    1fae:	c4 41 3a 5a c0       	vcvtss2sd %xmm8,%xmm8,%xmm8
    1fb3:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
    1fb8:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    1fbc:	c5 fb 11 44 24 58    	vmovsd %xmm0,0x58(%rsp)
    1fc2:	c5 f9 6e c7          	vmovd  %edi,%xmm0
    1fc6:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    1fca:	c5 fb 11 44 24 50    	vmovsd %xmm0,0x50(%rsp)
    1fd0:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
    1fd5:	c4 c1 f9 6e e1       	vmovq  %r9,%xmm4
    1fda:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
    1fdf:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    1fe3:	c4 41 79 6e d8       	vmovd  %r8d,%xmm11
    1fe8:	c5 ca 5a f6          	vcvtss2sd %xmm6,%xmm6,%xmm6
    1fec:	c5 fb 11 44 24 48    	vmovsd %xmm0,0x48(%rsp)
    1ff2:	c5 f9 6e c6          	vmovd  %esi,%xmm0
    1ff6:	c4 c1 f9 6e d8       	vmovq  %r8,%xmm3
    1ffb:	8b b5 9c fe ff ff    	mov    -0x164(%rbp),%esi
    2001:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    2005:	c5 fb 11 44 24 40    	vmovsd %xmm0,0x40(%rsp)
    200b:	c4 c1 79 6e c5       	vmovd  %r13d,%xmm0
    2010:	bf 00 00 00 00       	mov    $0x0,%edi	2011: R_X86_64_32	.rodata.str1.8+0x368
    2015:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    2019:	c5 fb 11 44 24 38    	vmovsd %xmm0,0x38(%rsp)
    201f:	c5 d2 5a ed          	vcvtss2sd %xmm5,%xmm5,%xmm5
    2023:	c4 e1 f9 6e c1       	vmovq  %rcx,%xmm0
    2028:	c5 fb 11 54 24 18    	vmovsd %xmm2,0x18(%rsp)
    202e:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
    2033:	c4 e1 f9 6e d2       	vmovq  %rdx,%xmm2
    2038:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    203c:	c5 fb 11 44 24 30    	vmovsd %xmm0,0x30(%rsp)
    2042:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
    2046:	c5 e8 c6 d2 55       	vshufps $0x55,%xmm2,%xmm2,%xmm2
    204b:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
    2050:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    2054:	c5 fb 11 44 24 28    	vmovsd %xmm0,0x28(%rsp)
    205a:	c5 ea 5a c2          	vcvtss2sd %xmm2,%xmm2,%xmm0
    205e:	c5 f9 6f fc          	vmovdqa %xmm4,%xmm7
    2062:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
    2068:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    206c:	c4 c1 79 6e e2       	vmovd  %r10d,%xmm4
    2071:	44 89 e2             	mov    %r12d,%edx
    2074:	c5 7b 11 54 24 20    	vmovsd %xmm10,0x20(%rsp)
    207a:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    207e:	b8 08 00 00 00       	mov    $0x8,%eax
    2083:	c5 e0 c6 db 55       	vshufps $0x55,%xmm3,%xmm3,%xmm3
    2088:	c5 c2 5a ff          	vcvtss2sd %xmm7,%xmm7,%xmm7
    208c:	c5 da 5a e4          	vcvtss2sd %xmm4,%xmm4,%xmm4
    2090:	c5 e2 5a db          	vcvtss2sd %xmm3,%xmm3,%xmm3
    2094:	c4 c1 22 5a d3       	vcvtss2sd %xmm11,%xmm11,%xmm2
    2099:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
    209e:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
    20a2:	c5 f2 5a c9          	vcvtss2sd %xmm1,%xmm1,%xmm1
    20a6:	c5 7b 11 4c 24 10    	vmovsd %xmm9,0x10(%rsp)
    20ac:	e8 00 00 00 00       	call   20b1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc11>	20ad: R_X86_64_PLT32	printf-0x4
    20b1:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 20b8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc18>	20b4: R_X86_64_PC32	stdout-0x4
    20b8:	48 83 c4 60          	add    $0x60,%rsp
    20bc:	e8 00 00 00 00       	call   20c1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>	20bd: R_X86_64_PLT32	fflush-0x4
    20c1:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    20c8:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 20cf <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc2f>	20cb: R_X86_64_PC32	g_ee_main_mem-0x4
    20cf:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
    20d8:	48 83 e8 60          	sub    $0x60,%rax
    20dc:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
    20e3:	83 e0 f0             	and    $0xfffffff0,%eax
    20e6:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    20ec:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    20f3:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
    20fc:	83 c0 10             	add    $0x10,%eax
    20ff:	83 e0 f0             	and    $0xfffffff0,%eax
    2102:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2108:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    210f:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
    2118:	83 c0 20             	add    $0x20,%eax
    211b:	83 e0 f0             	and    $0xfffffff0,%eax
    211e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2124:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    212b:	c4 c1 79 6f 86 10 01 00 00 	vmovdqa 0x110(%r14),%xmm0
    2134:	83 c0 30             	add    $0x30,%eax
    2137:	83 e0 f0             	and    $0xfffffff0,%eax
    213a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2140:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    2147:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
    2150:	83 c0 40             	add    $0x40,%eax
    2153:	83 e0 f0             	and    $0xfffffff0,%eax
    2156:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    215c:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
    2163:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
    216c:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
    2173:	49 89 46 40          	mov    %rax,0x40(%r14)
    2177:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    217e:	49 89 46 50          	mov    %rax,0x50(%r14)
    2182:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
    2189:	49 89 46 60          	mov    %rax,0x60(%r14)
    218d:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
    2194:	83 c0 50             	add    $0x50,%eax
    2197:	83 e0 f0             	and    $0xfffffff0,%eax
    219a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    21a0:	c4 c1 7a 7e 66 60    	vmovq  0x60(%r14),%xmm4
    21a6:	c4 c1 7a 7e ae a0 00 00 00 	vmovq  0xa0(%r14),%xmm5
    21af:	c4 c1 7a 7e 96 80 00 00 00 	vmovq  0x80(%r14),%xmm2
    21b8:	c4 c3 d1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm5,%xmm1
    21c2:	c4 c3 e9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm2,%xmm0
    21cc:	c4 c3 d9 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm4,%xmm2
    21d3:	c4 c1 7a 7e 6e 40    	vmovq  0x40(%r14),%xmm5
    21d9:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
    21df:	c4 c3 d1 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm5,%xmm1
    21e6:	c5 fd 7f 85 70 ff ff ff 	vmovdqa %ymm0,-0x90(%rbp)
    21ee:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
    21f4:	c5 fd 7f 8d 50 ff ff ff 	vmovdqa %ymm1,-0xb0(%rbp)
    21fc:	85 ff                	test   %edi,%edi
    21fe:	0f 84 bc 0a 00 00    	je     2cc0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
    2204:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    220b:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    2212:	4c 01 cf             	add    %r9,%rdi
    2215:	31 d2                	xor    %edx,%edx
    2217:	48 8d b5 50 ff ff ff 	lea    -0xb0(%rbp),%rsi
    221e:	c5 f8 77             	vzeroupper
    2221:	e8 00 00 00 00       	call   2226 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd86>	2222: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    2226:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
    222d:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 2234 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd94>	2230: R_X86_64_PC32	g_ee_main_mem-0x4
    2234:	49 89 46 20          	mov    %rax,0x20(%r14)
    2238:	48 89 d0             	mov    %rdx,%rax
    223b:	8d 4a 10             	lea    0x10(%rdx),%ecx
    223e:	83 e0 f0             	and    $0xfffffff0,%eax
    2241:	83 e1 f0             	and    $0xfffffff0,%ecx
    2244:	c4 c1 7a 6f 04 01    	vmovdqu (%r9,%rax,1),%xmm0
    224a:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    2253:	49 8b 04 09          	mov    (%r9,%rcx,1),%rax
    2257:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
    225c:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
    2263:	8d 4a 20             	lea    0x20(%rdx),%ecx
    2266:	83 e1 f0             	and    $0xfffffff0,%ecx
    2269:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
    2270:	49 8b 34 09          	mov    (%r9,%rcx,1),%rsi
    2274:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
    2279:	49 89 8e 48 01 00 00 	mov    %rcx,0x148(%r14)
    2280:	8d 4a 30             	lea    0x30(%rdx),%ecx
    2283:	83 e1 f0             	and    $0xfffffff0,%ecx
    2286:	49 89 b6 40 01 00 00 	mov    %rsi,0x140(%r14)
    228d:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    2293:	8d 4a 40             	lea    0x40(%rdx),%ecx
    2296:	83 e1 f0             	and    $0xfffffff0,%ecx
    2299:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    22a2:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    22a8:	8d 4a 50             	lea    0x50(%rdx),%ecx
    22ab:	48 83 c2 60          	add    $0x60,%rdx
    22af:	83 e1 f0             	and    $0xfffffff0,%ecx
    22b2:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    22bb:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    22c1:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    22c8:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    22d1:	84 db                	test   %bl,%bl
    22d3:	0f 85 4f 08 00 00    	jne    2b28 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1688>
    22d9:	89 c2                	mov    %eax,%edx
    22db:	49 8d 7c 11 68       	lea    0x68(%r9,%rdx,1),%rdi
    22e0:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    22e7:	8d 4a 20             	lea    0x20(%rdx),%ecx
    22ea:	83 e1 f0             	and    $0xfffffff0,%ecx
    22ed:	4d 8b 04 09          	mov    (%r9,%rcx,1),%r8
    22f1:	49 8b 74 09 08       	mov    0x8(%r9,%rcx,1),%rsi
    22f6:	4d 89 46 30          	mov    %r8,0x30(%r14)
    22fa:	49 89 76 38          	mov    %rsi,0x38(%r14)
    22fe:	48 63 3f             	movslq (%rdi),%rdi
    2301:	49 89 7e 40          	mov    %rdi,0x40(%r14)
    2305:	48 89 f9             	mov    %rdi,%rcx
    2308:	83 e7 04             	and    $0x4,%edi
    230b:	89 fb                	mov    %edi,%ebx
    230d:	49 89 5e 50          	mov    %rbx,0x50(%r14)
    2311:	f6 c1 02             	test   $0x2,%cl
    2314:	74 3e                	je     2354 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xeb4>
    2316:	49 89 f2             	mov    %rsi,%r10
    2319:	41 c7 86 c0 00 00 00 00 00 00 00 	movl   $0x0,0xc0(%r14)
    2324:	49 c1 ea 20          	shr    $0x20,%r10
    2328:	41 89 b6 c4 00 00 00 	mov    %esi,0xc4(%r14)
    232f:	41 c7 86 c8 00 00 00 00 00 00 00 	movl   $0x0,0xc8(%r14)
    233a:	45 89 96 cc 00 00 00 	mov    %r10d,0xcc(%r14)
    2341:	4d 85 c0             	test   %r8,%r8
    2344:	75 0e                	jne    2354 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xeb4>
    2346:	49 83 be c0 00 00 00 00 	cmpq   $0x0,0xc0(%r14)
    234e:	0f 84 ac 00 00 00    	je     2400 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
    2354:	83 e1 01             	and    $0x1,%ecx
    2357:	89 cb                	mov    %ecx,%ebx
    2359:	49 89 5e 40          	mov    %rbx,0x40(%r14)
    235d:	85 ff                	test   %edi,%edi
    235f:	74 35                	je     2396 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xef6>
    2361:	49 c7 86 c8 00 00 00 00 00 00 00 	movq   $0x0,0xc8(%r14)
    236c:	48 89 f7             	mov    %rsi,%rdi
    236f:	48 c1 ef 20          	shr    $0x20,%rdi
    2373:	41 89 b6 c8 00 00 00 	mov    %esi,0xc8(%r14)
    237a:	41 c7 86 c0 00 00 00 00 00 00 00 	movl   $0x0,0xc0(%r14)
    2385:	41 89 be c4 00 00 00 	mov    %edi,0xc4(%r14)
    238c:	49 83 be c0 00 00 00 00 	cmpq   $0x0,0xc0(%r14)
    2394:	7e 6a                	jle    2400 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
    2396:	85 c9                	test   %ecx,%ecx
    2398:	0f 84 12 f3 ff ff    	je     16b0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    239e:	c4 c1 78 28 86 90 02 00 00 	vmovaps 0x290(%r14),%xmm0
    23a7:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
    23ad:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
    23b4:	c4 c1 78 28 86 a0 02 00 00 	vmovaps 0x2a0(%r14),%xmm0
    23bd:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
    23c5:	49 8b 4e 30          	mov    0x30(%r14),%rcx
    23c9:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
    23cf:	48 85 c9             	test   %rcx,%rcx
    23d2:	78 2c                	js     2400 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
    23d4:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
    23dc:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
    23e3:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
    23ea:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
    23f2:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
    23f7:	0f 89 b3 f2 ff ff    	jns    16b0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    23fd:	0f 1f 00             	nopl   (%rax)
    2400:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # 2407 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf67>	2403: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x4
    2407:	49 63 b6 f0 01 00 00 	movslq 0x1f0(%r14),%rsi
    240e:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
    2417:	c4 c1 7a 7e a6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm4
    2420:	c4 c3 d9 22 96 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm4,%xmm2
    242a:	48 63 09             	movslq (%rcx),%rcx
    242d:	49 89 46 60          	mov    %rax,0x60(%r14)
    2431:	c4 c1 7a 7e a6 80 00 00 00 	vmovq  0x80(%r14),%xmm4
    243a:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
    2440:	c4 c3 d9 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm4,%xmm1
    244a:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
    244f:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
    2456:	48 89 cf             	mov    %rcx,%rdi
    2459:	49 8b 8e 10 01 00 00 	mov    0x110(%r14),%rcx
    2460:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
    2466:	c4 e3 d9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm4,%xmm2
    246c:	49 89 56 70          	mov    %rdx,0x70(%r14)
    2470:	c4 e3 f9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm0,%xmm0
    2476:	49 89 4e 50          	mov    %rcx,0x50(%r14)
    247a:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
    2480:	49 89 76 20          	mov    %rsi,0x20(%r14)
    2484:	c5 fd 7f 45 90       	vmovdqa %ymm0,-0x70(%rbp)
    2489:	c5 fd 7f 4d b0       	vmovdqa %ymm1,-0x50(%rbp)
    248e:	85 ff                	test   %edi,%edi
    2490:	0f 84 2a 08 00 00    	je     2cc0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
    2496:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    249d:	89 ff                	mov    %edi,%edi
    249f:	31 d2                	xor    %edx,%edx
    24a1:	48 8d 75 90          	lea    -0x70(%rbp),%rsi
    24a5:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    24ac:	4c 01 cf             	add    %r9,%rdi
    24af:	c5 f8 77             	vzeroupper
    24b2:	e8 00 00 00 00       	call   24b7 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1017>	24b3: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    24b7:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    24be:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 24c5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1025>	24c1: R_X86_64_PC32	g_ee_main_mem-0x4
    24c5:	49 89 46 20          	mov    %rax,0x20(%r14)
    24c9:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    24d0:	e9 db f1 ff ff       	jmp    16b0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    24d5:	0f 1f 00             	nopl   (%rax)
    24d8:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    24df:	e9 cc f1 ff ff       	jmp    16b0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    24e4:	0f 1f 40 00          	nopl   0x0(%rax)
    24e8:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    24ef:	e9 0c ff ff ff       	jmp    2400 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
    24f4:	0f 1f 40 00          	nopl   0x0(%rax)
    24f8:	49 89 56 30          	mov    %rdx,0x30(%r14)
    24fc:	e9 45 f2 ff ff       	jmp    1746 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2a6>
    2501:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    2508:	c4 41 79 6e d2       	vmovd  %r10d,%xmm10
    250d:	4c 89 d2             	mov    %r10,%rdx
    2510:	4d 8b 5e 38          	mov    0x38(%r14),%r11
    2514:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
    2518:	c5 7a 10 0d 00 00 00 00 	vmovss 0x0(%rip),%xmm9        # 2520 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1080>	251c: R_X86_64_PC32	.LC11-0x4
    2520:	c5 ca 59 db          	vmulss %xmm3,%xmm6,%xmm3
    2524:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # 252c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x108c>	2528: R_X86_64_PC32	.LC11-0x4
    252c:	48 c1 ea 20          	shr    $0x20,%rdx
    2530:	c4 c1 4a 59 f5       	vmulss %xmm13,%xmm6,%xmm6
    2535:	c4 41 32 5c ca       	vsubss %xmm10,%xmm9,%xmm9
    253a:	c4 41 1a 59 d2       	vmulss %xmm10,%xmm12,%xmm10
    253f:	c4 41 32 59 cc       	vmulss %xmm12,%xmm9,%xmm9
    2544:	c5 e2 58 df          	vaddss %xmm7,%xmm3,%xmm3
    2548:	c5 f9 6e f9          	vmovd  %ecx,%xmm7
    254c:	c5 ca 58 f7          	vaddss %xmm7,%xmm6,%xmm6
    2550:	c4 41 7a 5c c9       	vsubss %xmm9,%xmm0,%xmm9
    2555:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    2559:	c5 9a 59 c0          	vmulss %xmm0,%xmm12,%xmm0
    255d:	c4 c1 6a 59 d1       	vmulss %xmm9,%xmm2,%xmm2
    2562:	c4 c1 7a 12 f9       	vmovsldup %xmm9,%xmm7
    2567:	c4 c1 62 59 d9       	vmulss %xmm9,%xmm3,%xmm3
    256c:	c4 c1 4a 59 f1       	vmulss %xmm9,%xmm6,%xmm6
    2571:	c5 f9 7e c2          	vmovd  %xmm0,%edx
    2575:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
    257a:	c5 1a 59 e0          	vmulss %xmm0,%xmm12,%xmm12
    257e:	c5 fa 7e ff          	vmovq  %xmm7,%xmm7
    2582:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    2586:	c5 c0 59 c9          	vmulps %xmm1,%xmm7,%xmm1
    258a:	c5 28 14 d0          	vunpcklps %xmm0,%xmm10,%xmm10
    258e:	c4 c1 7a 11 96 c8 02 00 00 	vmovss %xmm2,0x2c8(%r14)
    2597:	c4 41 18 14 e1       	vunpcklps %xmm9,%xmm12,%xmm12
    259c:	c4 c1 78 13 8e c0 02 00 00 	vmovlps %xmm1,0x2c0(%r14)
    25a5:	c4 41 28 16 d4       	vmovlhps %xmm12,%xmm10,%xmm10
    25aa:	c4 41 78 29 96 00 03 00 00 	vmovaps %xmm10,0x300(%r14)
    25b3:	e9 55 f6 ff ff       	jmp    1c0d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x76d>
    25b8:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
    25c0:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
    25c7:	49 89 46 20          	mov    %rax,0x20(%r14)
    25cb:	89 d1                	mov    %edx,%ecx
    25cd:	49 8b 0c 09          	mov    (%r9,%rcx,1),%rcx
    25d1:	49 89 8e f0 01 00 00 	mov    %rcx,0x1f0(%r14)
    25d8:	8d 4a 70             	lea    0x70(%rdx),%ecx
    25db:	83 e1 f0             	and    $0xfffffff0,%ecx
    25de:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    25e4:	8d 4a 60             	lea    0x60(%rdx),%ecx
    25e7:	83 e1 f0             	and    $0xfffffff0,%ecx
    25ea:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    25f3:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    25f9:	8d 4a 50             	lea    0x50(%rdx),%ecx
    25fc:	83 e1 f0             	and    $0xfffffff0,%ecx
    25ff:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    2608:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    260e:	8d 4a 40             	lea    0x40(%rdx),%ecx
    2611:	83 e1 f0             	and    $0xfffffff0,%ecx
    2614:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    261d:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    2623:	8d 4a 30             	lea    0x30(%rdx),%ecx
    2626:	83 e1 f0             	and    $0xfffffff0,%ecx
    2629:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    2632:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    2638:	8d 4a 20             	lea    0x20(%rdx),%ecx
    263b:	83 e1 f0             	and    $0xfffffff0,%ecx
    263e:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    2647:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    264d:	8d 4a 10             	lea    0x10(%rdx),%ecx
    2650:	48 83 ea 80          	sub    $0xffffffffffffff80,%rdx
    2654:	83 e1 f0             	and    $0xfffffff0,%ecx
    2657:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    2660:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    2666:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    266d:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
    2676:	48 8d 65 d0          	lea    -0x30(%rbp),%rsp
    267a:	5b                   	pop    %rbx
    267b:	41 5a                	pop    %r10
    267d:	41 5c                	pop    %r12
    267f:	41 5d                	pop    %r13
    2681:	41 5e                	pop    %r14
    2683:	41 5f                	pop    %r15
    2685:	5d                   	pop    %rbp
    2686:	49 8d 62 f8          	lea    -0x8(%r10),%rsp
    268a:	c3                   	ret
    268b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    2690:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
    2699:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    26a0:	48 8d 50 a0          	lea    -0x60(%rax),%rdx
    26a4:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 26ab <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x120b>	26a7: R_X86_64_PC32	g_ee_main_mem-0x4
    26ab:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    26b2:	83 e2 f0             	and    $0xfffffff0,%edx
    26b5:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    26ba:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    26c1:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
    26ca:	8d 53 10             	lea    0x10(%rbx),%edx
    26cd:	83 e2 f0             	and    $0xfffffff0,%edx
    26d0:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    26d5:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    26dc:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
    26e5:	8d 53 20             	lea    0x20(%rbx),%edx
    26e8:	83 e2 f0             	and    $0xfffffff0,%edx
    26eb:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    26f0:	49 8b be 10 01 00 00 	mov    0x110(%r14),%rdi
    26f7:	49 8b b6 18 01 00 00 	mov    0x118(%r14),%rsi
    26fe:	48 89 bd b0 fe ff ff 	mov    %rdi,-0x150(%rbp)
    2705:	41 8b be d0 01 00 00 	mov    0x1d0(%r14),%edi
    270c:	48 8b 9d b0 fe ff ff 	mov    -0x150(%rbp),%rbx
    2713:	48 89 b5 b8 fe ff ff 	mov    %rsi,-0x148(%rbp)
    271a:	8d 57 30             	lea    0x30(%rdi),%edx
    271d:	83 e2 f0             	and    $0xfffffff0,%edx
    2720:	48 89 9d b0 fe ff ff 	mov    %rbx,-0x150(%rbp)
    2727:	48 89 1c 10          	mov    %rbx,(%rax,%rdx,1)
    272b:	48 89 74 10 08       	mov    %rsi,0x8(%rax,%rdx,1)
    2730:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    2737:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
    2740:	8d 53 40             	lea    0x40(%rbx),%edx
    2743:	83 e2 f0             	and    $0xfffffff0,%edx
    2746:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    274b:	49 8b be 20 01 00 00 	mov    0x120(%r14),%rdi
    2752:	49 8b b6 28 01 00 00 	mov    0x128(%r14),%rsi
    2759:	48 89 bd a0 fe ff ff 	mov    %rdi,-0x160(%rbp)
    2760:	41 8b be d0 01 00 00 	mov    0x1d0(%r14),%edi
    2767:	48 8b 9d a0 fe ff ff 	mov    -0x160(%rbp),%rbx
    276e:	48 89 b5 a8 fe ff ff 	mov    %rsi,-0x158(%rbp)
    2775:	8d 57 50             	lea    0x50(%rdi),%edx
    2778:	83 e2 f0             	and    $0xfffffff0,%edx
    277b:	48 89 9d a0 fe ff ff 	mov    %rbx,-0x160(%rbp)
    2782:	48 89 1c 10          	mov    %rbx,(%rax,%rdx,1)
    2786:	48 89 74 10 08       	mov    %rsi,0x8(%rax,%rdx,1)
    278b:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
    2792:	49 89 46 40          	mov    %rax,0x40(%r14)
    2796:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
    279d:	49 89 46 70          	mov    %rax,0x70(%r14)
    27a1:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    27a8:	49 89 46 60          	mov    %rax,0x60(%r14)
    27ac:	e8 4f d8 ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
    27b1:	89 c3                	mov    %eax,%ebx
    27b3:	84 c0                	test   %al,%al
    27b5:	74 13                	je     27ca <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x132a>
    27b7:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 27bd <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x131d>	27b9: R_X86_64_PC32	.bss+0x124
    27bd:	3d 3f 1f 00 00       	cmp    $0x1f3f,%eax
    27c2:	0f 8e f1 03 00 00    	jle    2bb9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1719>
    27c8:	31 db                	xor    %ebx,%ebx
    27ca:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 27d1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1331>	27cd: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x14
    27d1:	48 63 10             	movslq (%rax),%rdx
    27d4:	49 89 96 90 01 00 00 	mov    %rdx,0x190(%r14)
    27db:	48 89 d0             	mov    %rdx,%rax
    27de:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
    27e5:	49 89 56 20          	mov    %rdx,0x20(%r14)
    27e9:	49 8b 56 40          	mov    0x40(%r14),%rdx
    27ed:	48 89 95 10 ff ff ff 	mov    %rdx,-0xf0(%rbp)
    27f4:	49 8b 56 50          	mov    0x50(%r14),%rdx
    27f8:	48 89 95 18 ff ff ff 	mov    %rdx,-0xe8(%rbp)
    27ff:	49 8b 56 60          	mov    0x60(%r14),%rdx
    2803:	48 89 95 20 ff ff ff 	mov    %rdx,-0xe0(%rbp)
    280a:	49 8b 56 70          	mov    0x70(%r14),%rdx
    280e:	48 89 95 28 ff ff ff 	mov    %rdx,-0xd8(%rbp)
    2815:	49 8b 96 80 00 00 00 	mov    0x80(%r14),%rdx
    281c:	48 89 95 30 ff ff ff 	mov    %rdx,-0xd0(%rbp)
    2823:	49 8b 96 90 00 00 00 	mov    0x90(%r14),%rdx
    282a:	48 89 95 38 ff ff ff 	mov    %rdx,-0xc8(%rbp)
    2831:	49 8b 96 a0 00 00 00 	mov    0xa0(%r14),%rdx
    2838:	48 89 95 40 ff ff ff 	mov    %rdx,-0xc0(%rbp)
    283f:	49 8b 96 b0 00 00 00 	mov    0xb0(%r14),%rdx
    2846:	48 89 95 48 ff ff ff 	mov    %rdx,-0xb8(%rbp)
    284d:	85 c0                	test   %eax,%eax
    284f:	0f 84 6e 04 00 00    	je     2cc3 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1823>
    2855:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 285c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13bc>	2858: R_X86_64_PC32	g_ee_main_mem-0x4
    285c:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    2863:	89 c0                	mov    %eax,%eax
    2865:	48 8d b5 10 ff ff ff 	lea    -0xf0(%rbp),%rsi
    286c:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    2873:	31 d2                	xor    %edx,%edx
    2875:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
    2879:	e8 00 00 00 00       	call   287e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13de>	287a: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    287e:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
    2885:	49 89 46 20          	mov    %rax,0x20(%r14)
    2889:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 2890 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13f0>	288c: R_X86_64_PC32	g_ee_main_mem-0x4
    2890:	48 89 d1             	mov    %rdx,%rcx
    2893:	83 e1 f0             	and    $0xfffffff0,%ecx
    2896:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    289b:	8d 4a 10             	lea    0x10(%rdx),%ecx
    289e:	83 e1 f0             	and    $0xfffffff0,%ecx
    28a1:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    28aa:	48 8b 3c 08          	mov    (%rax,%rcx,1),%rdi
    28ae:	48 8b 4c 08 08       	mov    0x8(%rax,%rcx,1),%rcx
    28b3:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
    28ba:	8d 4a 20             	lea    0x20(%rdx),%ecx
    28bd:	83 e1 f0             	and    $0xfffffff0,%ecx
    28c0:	49 89 be 50 01 00 00 	mov    %rdi,0x150(%r14)
    28c7:	48 8b 34 08          	mov    (%rax,%rcx,1),%rsi
    28cb:	48 8b 4c 08 08       	mov    0x8(%rax,%rcx,1),%rcx
    28d0:	49 89 8e 48 01 00 00 	mov    %rcx,0x148(%r14)
    28d7:	8d 4a 30             	lea    0x30(%rdx),%ecx
    28da:	83 e1 f0             	and    $0xfffffff0,%ecx
    28dd:	49 89 b6 40 01 00 00 	mov    %rsi,0x140(%r14)
    28e4:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    28e9:	8d 4a 40             	lea    0x40(%rdx),%ecx
    28ec:	83 e1 f0             	and    $0xfffffff0,%ecx
    28ef:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    28f8:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    28fd:	8d 4a 50             	lea    0x50(%rdx),%ecx
    2900:	48 83 c2 60          	add    $0x60,%rdx
    2904:	83 e1 f0             	and    $0xfffffff0,%ecx
    2907:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    2910:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    2915:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    291c:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    2925:	84 db                	test   %bl,%bl
    2927:	0f 84 1d f1 ff ff    	je     1a4a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
    292d:	89 f9                	mov    %edi,%ecx
    292f:	89 ff                	mov    %edi,%edi
    2931:	c4 41 01 57 ff       	vxorpd %xmm15,%xmm15,%xmm15
    2936:	89 f6                	mov    %esi,%esi
    2938:	48 8b 54 38 10       	mov    0x10(%rax,%rdi,1),%rdx
    293d:	48 83 ec 10          	sub    $0x10,%rsp
    2941:	c5 82 5a 04 30       	vcvtss2sd (%rax,%rsi,1),%xmm15,%xmm0
    2946:	c5 79 28 c0          	vmovapd %xmm0,%xmm8
    294a:	c5 82 5a 7c 38 10    	vcvtss2sd 0x10(%rax,%rdi,1),%xmm15,%xmm7
    2950:	c5 82 5a 44 38 18    	vcvtss2sd 0x18(%rax,%rdi,1),%xmm15,%xmm0
    2956:	c5 82 5a 74 30 2c    	vcvtss2sd 0x2c(%rax,%rsi,1),%xmm15,%xmm6
    295c:	c5 82 5a 6c 30 28    	vcvtss2sd 0x28(%rax,%rsi,1),%xmm15,%xmm5
    2962:	48 c1 ea 20          	shr    $0x20,%rdx
    2966:	c5 82 5a 64 30 24    	vcvtss2sd 0x24(%rax,%rsi,1),%xmm15,%xmm4
    296c:	c5 82 5a 5c 30 20    	vcvtss2sd 0x20(%rax,%rsi,1),%xmm15,%xmm3
    2972:	c5 82 5a 54 30 08    	vcvtss2sd 0x8(%rax,%rsi,1),%xmm15,%xmm2
    2978:	c5 82 5a 4c 30 04    	vcvtss2sd 0x4(%rax,%rsi,1),%xmm15,%xmm1
    297e:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
    2984:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    2988:	89 ce                	mov    %ecx,%esi
    298a:	bf 00 00 00 00       	mov    $0x0,%edi	298b: R_X86_64_32	.rodata.str1.8+0x2b0
    298f:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    2993:	b8 08 00 00 00       	mov    $0x8,%eax
    2998:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
    299d:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
    29a1:	e8 00 00 00 00       	call   29a6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1506>	29a2: R_X86_64_PLT32	printf-0x4
    29a6:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 29ad <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x150d>	29a9: R_X86_64_PC32	stdout-0x4
    29ad:	59                   	pop    %rcx
    29ae:	5e                   	pop    %rsi
    29af:	e8 00 00 00 00       	call   29b4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1514>	29b0: R_X86_64_PLT32	fflush-0x4
    29b4:	e9 91 f0 ff ff       	jmp    1a4a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
    29b9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    29c0:	c4 e1 f9 6e f7       	vmovq  %rdi,%xmm6
    29c5:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
    29ca:	c5 f8 2f 35 00 00 00 00 	vcomiss 0x0(%rip),%xmm6        # 29d2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1532>	29ce: R_X86_64_PC32	.LC21-0x4
    29d2:	c5 f9 6f ce          	vmovdqa %xmm6,%xmm1
    29d6:	0f 86 84 f4 ff ff    	jbe    1e60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    29dc:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    29e0:	c5 f8 2e d0          	vucomiss %xmm0,%xmm2
    29e4:	0f 8a 76 f4 ff ff    	jp     1e60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    29ea:	0f 85 70 f4 ff ff    	jne    1e60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    29f0:	4c 8b 5c 10 10       	mov    0x10(%rax,%rdx,1),%r11
    29f5:	83 c1 01             	add    $0x1,%ecx
    29f8:	48 83 ec 30          	sub    $0x30,%rsp
    29fc:	c5 d1 57 ed          	vxorpd %xmm5,%xmm5,%xmm5
    2a00:	48 8b 7c 10 08       	mov    0x8(%rax,%rdx,1),%rdi
    2a05:	89 0d 00 00 00 00    	mov    %ecx,0x0(%rip)        # 2a0b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x156b>	2a07: R_X86_64_PC32	.bss+0x120
    2a0b:	c5 d2 5a 44 10 1c    	vcvtss2sd 0x1c(%rax,%rdx,1),%xmm5,%xmm0
    2a11:	c4 c1 f9 6e f2       	vmovq  %r10,%xmm6
    2a16:	48 8b 0c 10          	mov    (%rax,%rdx,1),%rcx
    2a1a:	49 c1 e9 20          	shr    $0x20,%r9
    2a1e:	49 c1 e8 20          	shr    $0x20,%r8
    2a22:	c5 fb 11 44 24 20    	vmovsd %xmm0,0x20(%rsp)
    2a28:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
    2a2d:	c4 c1 79 6e d8       	vmovd  %r8d,%xmm3
    2a32:	c4 41 3a 5a c0       	vcvtss2sd %xmm8,%xmm8,%xmm8
    2a37:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
    2a3c:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    2a40:	c5 f9 6f fe          	vmovdqa %xmm6,%xmm7
    2a44:	c5 fb 11 44 24 18    	vmovsd %xmm0,0x18(%rsp)
    2a4a:	c4 e1 f9 6e e9       	vmovq  %rcx,%xmm5
    2a4f:	c5 f9 6e c7          	vmovd  %edi,%xmm0
    2a53:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
    2a58:	c4 c1 79 6e f2       	vmovd  %r10d,%xmm6
    2a5d:	bf 00 00 00 00       	mov    $0x0,%edi	2a5e: R_X86_64_32	.rodata.str1.8+0x300
    2a62:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    2a66:	c5 c2 5a ff          	vcvtss2sd %xmm7,%xmm7,%xmm7
    2a6a:	c5 ca 5a f6          	vcvtss2sd %xmm6,%xmm6,%xmm6
    2a6e:	c5 da 5a e4          	vcvtss2sd %xmm4,%xmm4,%xmm4
    2a72:	c5 fb 11 44 24 10    	vmovsd %xmm0,0x10(%rsp)
    2a78:	c5 d2 5a c5          	vcvtss2sd %xmm5,%xmm5,%xmm0
    2a7c:	c4 c1 79 6e e9       	vmovd  %r9d,%xmm5
    2a81:	c5 e2 5a db          	vcvtss2sd %xmm3,%xmm3,%xmm3
    2a85:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
    2a8b:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
    2a8f:	c5 d2 5a ed          	vcvtss2sd %xmm5,%xmm5,%xmm5
    2a93:	c5 ea 5a d2          	vcvtss2sd %xmm2,%xmm2,%xmm2
    2a97:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    2a9b:	b8 08 00 00 00       	mov    $0x8,%eax
    2aa0:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
    2aa5:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
    2aa9:	c5 f2 5a c9          	vcvtss2sd %xmm1,%xmm1,%xmm1
    2aad:	e8 00 00 00 00       	call   2ab2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1612>	2aae: R_X86_64_PLT32	printf-0x4
    2ab2:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 2ab9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1619>	2ab5: R_X86_64_PC32	stdout-0x4
    2ab9:	48 83 c4 30          	add    $0x30,%rsp
    2abd:	e8 00 00 00 00       	call   2ac2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1622>	2abe: R_X86_64_PLT32	fflush-0x4
    2ac2:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 2ac9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1629>	2ac5: R_X86_64_PC32	g_ee_main_mem-0x4
    2ac9:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
    2ad0:	e9 ab f3 ff ff       	jmp    1e80 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
    2ad5:	0f 1f 00             	nopl   (%rax)
    2ad8:	31 db                	xor    %ebx,%ebx
    2ada:	e9 e2 f5 ff ff       	jmp    20c1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>
    2adf:	90                   	nop
    2ae0:	83 c2 01             	add    $0x1,%edx
    2ae3:	41 8b 4c 01 74       	mov    0x74(%r9,%rax,1),%ecx
    2ae8:	45 8b 44 01 78       	mov    0x78(%r9,%rax,1),%r8d
    2aed:	bf 00 00 00 00       	mov    $0x0,%edi	2aee: R_X86_64_32	.rodata.str1.8+0x238
    2af2:	89 15 00 00 00 00    	mov    %edx,0x0(%rip)        # 2af8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1658>	2af4: R_X86_64_PC32	.bss+0x128
    2af8:	41 8b 54 01 70       	mov    0x70(%r9,%rax,1),%edx
    2afd:	31 c0                	xor    %eax,%eax
    2aff:	e8 00 00 00 00       	call   2b04 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1664>	2b00: R_X86_64_PLT32	printf-0x4
    2b04:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 2b0b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x166b>	2b07: R_X86_64_PC32	stdout-0x4
    2b0b:	e8 00 00 00 00       	call   2b10 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1670>	2b0c: R_X86_64_PLT32	fflush-0x4
    2b10:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
    2b17:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 2b1e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x167e>	2b1a: R_X86_64_PC32	g_ee_main_mem-0x4
    2b1e:	e9 ed ee ff ff       	jmp    1a10 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
    2b23:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    2b28:	c4 41 09 57 f6       	vxorpd %xmm14,%xmm14,%xmm14
    2b2d:	48 83 ec 10          	sub    $0x10,%rsp
    2b31:	89 c2                	mov    %eax,%edx
    2b33:	89 f6                	mov    %esi,%esi
    2b35:	89 c0                	mov    %eax,%eax
    2b37:	c4 c1 0a 5a 7c 31 04 	vcvtss2sd 0x4(%r9,%rsi,1),%xmm14,%xmm7
    2b3e:	c4 c1 0a 5a 34 31    	vcvtss2sd (%r9,%rsi,1),%xmm14,%xmm6
    2b44:	c4 41 0a 5a 44 31 08 	vcvtss2sd 0x8(%r9,%rsi,1),%xmm14,%xmm8
    2b4b:	c4 c1 0a 5a 6c 01 5c 	vcvtss2sd 0x5c(%r9,%rax,1),%xmm14,%xmm5
    2b52:	c4 c1 0a 5a 64 01 58 	vcvtss2sd 0x58(%r9,%rax,1),%xmm14,%xmm4
    2b59:	89 d6                	mov    %edx,%esi
    2b5b:	c4 c1 0a 5a 5c 01 54 	vcvtss2sd 0x54(%r9,%rax,1),%xmm14,%xmm3
    2b62:	c4 c1 0a 5a 54 01 50 	vcvtss2sd 0x50(%r9,%rax,1),%xmm14,%xmm2
    2b69:	c4 c1 0a 5a 4c 01 08 	vcvtss2sd 0x8(%r9,%rax,1),%xmm14,%xmm1
    2b70:	bf 00 00 00 00       	mov    $0x0,%edi	2b71: R_X86_64_32	.rodata.str1.8+0x3e8
    2b75:	c4 c1 0a 5a 44 01 0c 	vcvtss2sd 0xc(%r9,%rax,1),%xmm14,%xmm0
    2b7c:	c5 7b 11 04 24       	vmovsd %xmm8,(%rsp)
    2b81:	b8 08 00 00 00       	mov    $0x8,%eax
    2b86:	e8 00 00 00 00       	call   2b8b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16eb>	2b87: R_X86_64_PLT32	printf-0x4
    2b8b:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 2b92 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16f2>	2b8e: R_X86_64_PC32	stdout-0x4
    2b92:	58                   	pop    %rax
    2b93:	5a                   	pop    %rdx
    2b94:	e8 00 00 00 00       	call   2b99 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16f9>	2b95: R_X86_64_PLT32	fflush-0x4
    2b99:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    2ba0:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 2ba7 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1707>	2ba3: R_X86_64_PC32	g_ee_main_mem-0x4
    2ba7:	e9 2d f7 ff ff       	jmp    22d9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe39>
    2bac:	48 c1 ef 20          	shr    $0x20,%rdi
    2bb0:	c5 f9 6e cf          	vmovd  %edi,%xmm1
    2bb4:	e9 37 fe ff ff       	jmp    29f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1550>
    2bb9:	83 c0 01             	add    $0x1,%eax
    2bbc:	41 8b 8e 50 01 00 00 	mov    0x150(%r14),%ecx
    2bc3:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
    2bca:	c5 d9 57 e4          	vxorpd %xmm4,%xmm4,%xmm4
    2bce:	89 05 00 00 00 00    	mov    %eax,0x0(%rip)        # 2bd4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1734>	2bd0: R_X86_64_PC32	.bss+0x124
    2bd4:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 2bdb <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x173b>	2bd7: R_X86_64_PC32	g_ee_main_mem-0x4
    2bdb:	c5 f9 28 fc          	vmovapd %xmm4,%xmm7
    2bdf:	8b 74 08 70          	mov    0x70(%rax,%rcx,1),%esi
    2be3:	8b 7c 08 78          	mov    0x78(%rax,%rcx,1),%edi
    2be7:	c5 da 5a 04 10       	vcvtss2sd (%rax,%rdx,1),%xmm4,%xmm0
    2bec:	c5 da 5a 74 10 2c    	vcvtss2sd 0x2c(%rax,%rdx,1),%xmm4,%xmm6
    2bf2:	c5 da 5a 6c 10 28    	vcvtss2sd 0x28(%rax,%rdx,1),%xmm4,%xmm5
    2bf8:	c5 c2 5a 5c 10 20    	vcvtss2sd 0x20(%rax,%rdx,1),%xmm7,%xmm3
    2bfe:	c5 da 5a 64 10 24    	vcvtss2sd 0x24(%rax,%rdx,1),%xmm4,%xmm4
    2c04:	c5 c2 5a 54 10 08    	vcvtss2sd 0x8(%rax,%rdx,1),%xmm7,%xmm2
    2c0a:	c5 c2 5a 4c 10 04    	vcvtss2sd 0x4(%rax,%rdx,1),%xmm7,%xmm1
    2c10:	89 f2                	mov    %esi,%edx
    2c12:	89 f9                	mov    %edi,%ecx
    2c14:	41 8b b6 50 01 00 00 	mov    0x150(%r14),%esi
    2c1b:	bf 00 00 00 00       	mov    $0x0,%edi	2c1c: R_X86_64_32	.rodata.str1.8+0x260
    2c20:	b8 07 00 00 00       	mov    $0x7,%eax
    2c25:	e8 00 00 00 00       	call   2c2a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x178a>	2c26: R_X86_64_PLT32	printf-0x4
    2c2a:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 2c31 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1791>	2c2d: R_X86_64_PC32	stdout-0x4
    2c31:	e8 00 00 00 00       	call   2c36 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1796>	2c32: R_X86_64_PLT32	fflush-0x4
    2c36:	e9 8f fb ff ff       	jmp    27ca <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x132a>
    2c3b:	45 89 e3             	mov    %r12d,%r11d
    2c3e:	c5 e9 57 d2          	vxorpd %xmm2,%xmm2,%xmm2
    2c42:	49 01 c3             	add    %rax,%r11
    2c45:	4d 8b 3b             	mov    (%r11),%r15
    2c48:	45 8b 5b 08          	mov    0x8(%r11),%r11d
    2c4c:	44 89 9d cc fe ff ff 	mov    %r11d,-0x134(%rbp)
    2c53:	4c 89 bd c4 fe ff ff 	mov    %r15,-0x13c(%rbp)
    2c5a:	c5 ea 5a a5 cc fe ff ff 	vcvtss2sd -0x134(%rbp),%xmm2,%xmm4
    2c62:	c5 79 28 d4          	vmovapd %xmm4,%xmm10
    2c66:	c5 f9 28 e2          	vmovapd %xmm2,%xmm4
    2c6a:	c5 5a 5a 8d c4 fe ff ff 	vcvtss2sd -0x13c(%rbp),%xmm4,%xmm9
    2c72:	c5 ea 5a 95 c8 fe ff ff 	vcvtss2sd -0x138(%rbp),%xmm2,%xmm2
    2c7a:	e9 ff f2 ff ff       	jmp    1f7e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xade>
    2c7f:	41 b8 00 00 00 00    	mov    $0x0,%r8d	2c81: R_X86_64_32	.rodata.str1.1+0xe
    2c85:	b9 00 00 00 00       	mov    $0x0,%ecx	2c86: R_X86_64_32	.rodata.str1.8
    2c8a:	ba 58 01 00 00       	mov    $0x158,%edx
    2c8f:	be 00 00 00 00       	mov    $0x0,%esi	2c90: R_X86_64_32	.rodata.str1.8+0x38
    2c94:	bf 00 00 00 00       	mov    $0x0,%edi	2c95: R_X86_64_32	.rodata.str1.8+0x78
    2c99:	e8 00 00 00 00       	call   2c9e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>	2c9a: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2c9e:	41 b8 00 00 00 00    	mov    $0x0,%r8d	2ca0: R_X86_64_32	.rodata.str1.1+0xe
    2ca4:	b9 00 00 00 00       	mov    $0x0,%ecx	2ca5: R_X86_64_32	.rodata.str1.8+0x1d8
    2ca9:	ba c0 01 00 00       	mov    $0x1c0,%edx
    2cae:	be 00 00 00 00       	mov    $0x0,%esi	2caf: R_X86_64_32	.rodata.str1.8+0x38
    2cb3:	bf 00 00 00 00       	mov    $0x0,%edi	2cb4: R_X86_64_32	.rodata.str1.8+0x210
    2cb8:	c5 f8 77             	vzeroupper
    2cbb:	e8 00 00 00 00       	call   2cc0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>	2cbc: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2cc0:	c5 f8 77             	vzeroupper
    2cc3:	41 b8 00 00 00 00    	mov    $0x0,%r8d	2cc5: R_X86_64_32	.rodata.str1.1+0xe
    2cc9:	b9 00 00 00 00       	mov    $0x0,%ecx	2cca: R_X86_64_32	.rodata.str1.8+0xa8
    2cce:	ba 90 01 00 00       	mov    $0x190,%edx
    2cd3:	be 00 00 00 00       	mov    $0x0,%esi	2cd4: R_X86_64_32	.rodata.str1.8+0x38
    2cd8:	bf 00 00 00 00       	mov    $0x0,%edi	2cd9: R_X86_64_32	.rodata.str1.1+0xf
    2cdd:	e8 00 00 00 00       	call   2ce2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1842>	2cde: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2ce2:	0f 1f 00             	nopl   (%rax)
    2ce5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)

0000000000002cf0 <Mips2C::jak1::sp_process_block_3d::link()>:
    2cf0:	53                   	push   %rbx
    2cf1:	bf 00 00 00 00       	mov    $0x0,%edi	2cf2: R_X86_64_32	.rodata.str1.1+0x14
    2cf6:	48 83 ec 20          	sub    $0x20,%rsp
    2cfa:	e8 00 00 00 00       	call   2cff <Mips2C::jak1::sp_process_block_3d::link()+0xf>	2cfb: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2cff:	bf 00 00 00 00       	mov    $0x0,%edi	2d00: R_X86_64_32	.rodata.str1.1+0x24
    2d04:	89 c2                	mov    %eax,%edx
    2d06:	89 c0                	mov    %eax,%eax
    2d08:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2d0f <Mips2C::jak1::sp_process_block_3d::link()+0x1f>	2d0b: R_X86_64_PC32	g_ee_main_mem-0x4
    2d0f:	85 d2                	test   %edx,%edx
    2d11:	ba 00 00 00 00       	mov    $0x0,%edx
    2d16:	48 0f 44 c2          	cmove  %rdx,%rax
    2d1a:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2d21 <Mips2C::jak1::sp_process_block_3d::link()+0x31>	2d1d: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
    2d21:	e8 00 00 00 00       	call   2d26 <Mips2C::jak1::sp_process_block_3d::link()+0x36>	2d22: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2d26:	bf 00 00 00 00       	mov    $0x0,%edi	2d27: R_X86_64_32	.rodata.str1.1+0x31
    2d2b:	89 c2                	mov    %eax,%edx
    2d2d:	89 c0                	mov    %eax,%eax
    2d2f:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2d36 <Mips2C::jak1::sp_process_block_3d::link()+0x46>	2d32: R_X86_64_PC32	g_ee_main_mem-0x4
    2d36:	85 d2                	test   %edx,%edx
    2d38:	ba 00 00 00 00       	mov    $0x0,%edx
    2d3d:	48 0f 44 c2          	cmove  %rdx,%rax
    2d41:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2d48 <Mips2C::jak1::sp_process_block_3d::link()+0x58>	2d44: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
    2d48:	e8 00 00 00 00       	call   2d4d <Mips2C::jak1::sp_process_block_3d::link()+0x5d>	2d49: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2d4d:	bf 00 00 00 00       	mov    $0x0,%edi	2d4e: R_X86_64_32	.rodata.str1.1+0x42
    2d52:	89 c2                	mov    %eax,%edx
    2d54:	89 c0                	mov    %eax,%eax
    2d56:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2d5d <Mips2C::jak1::sp_process_block_3d::link()+0x6d>	2d59: R_X86_64_PC32	g_ee_main_mem-0x4
    2d5d:	85 d2                	test   %edx,%edx
    2d5f:	ba 00 00 00 00       	mov    $0x0,%edx
    2d64:	48 0f 44 c2          	cmove  %rdx,%rax
    2d68:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2d6f <Mips2C::jak1::sp_process_block_3d::link()+0x7f>	2d6b: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
    2d6f:	e8 00 00 00 00       	call   2d74 <Mips2C::jak1::sp_process_block_3d::link()+0x84>	2d70: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2d74:	bf 14 00 00 00       	mov    $0x14,%edi
    2d79:	89 c2                	mov    %eax,%edx
    2d7b:	89 c0                	mov    %eax,%eax
    2d7d:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2d84 <Mips2C::jak1::sp_process_block_3d::link()+0x94>	2d80: R_X86_64_PC32	g_ee_main_mem-0x4
    2d84:	85 d2                	test   %edx,%edx
    2d86:	ba 00 00 00 00       	mov    $0x0,%edx
    2d8b:	48 0f 44 c2          	cmove  %rdx,%rax
    2d8f:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2d96 <Mips2C::jak1::sp_process_block_3d::link()+0xa6>	2d92: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
    2d96:	e8 00 00 00 00       	call   2d9b <Mips2C::jak1::sp_process_block_3d::link()+0xab>	2d97: R_X86_64_PLT32	operator new(unsigned long)-0x4
    2d9b:	c5 f9 6f 05 00 00 00 00 	vmovdqa 0x0(%rip),%xmm0        # 2da3 <Mips2C::jak1::sp_process_block_3d::link()+0xb3>	2d9f: R_X86_64_PC32	.LC32-0x4
    2da3:	48 89 e6             	mov    %rsp,%rsi
    2da6:	b9 00 01 00 00       	mov    $0x100,%ecx
    2dab:	c6 40 13 00          	movb   $0x0,0x13(%rax)
    2daf:	ba 00 00 00 00       	mov    $0x0,%edx	2db0: R_X86_64_32	Mips2C::jak1::sp_process_block_3d::execute(void*)
    2db4:	bf 00 00 00 00       	mov    $0x0,%edi	2db5: R_X86_64_32	Mips2C::gLinkedFunctionTable
    2db9:	c5 fa 7f 00          	vmovdqu %xmm0,(%rax)
    2dbd:	c7 40 0f 6b 2d 33 64 	movl   $0x64332d6b,0xf(%rax)
    2dc4:	48 89 04 24          	mov    %rax,(%rsp)
    2dc8:	48 c7 44 24 10 13 00 00 00 	movq   $0x13,0x10(%rsp)
    2dd1:	48 c7 44 24 08 13 00 00 00 	movq   $0x13,0x8(%rsp)
    2dda:	e8 00 00 00 00       	call   2ddf <Mips2C::jak1::sp_process_block_3d::link()+0xef>	2ddb: R_X86_64_PLT32	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)-0x4
    2ddf:	48 8b 3c 24          	mov    (%rsp),%rdi
    2de3:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
    2de8:	48 39 c7             	cmp    %rax,%rdi
    2deb:	74 0e                	je     2dfb <Mips2C::jak1::sp_process_block_3d::link()+0x10b>
    2ded:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
    2df2:	48 8d 70 01          	lea    0x1(%rax),%rsi
    2df6:	e8 00 00 00 00       	call   2dfb <Mips2C::jak1::sp_process_block_3d::link()+0x10b>	2df7: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
    2dfb:	48 83 c4 20          	add    $0x20,%rsp
    2dff:	5b                   	pop    %rbx
    2e00:	c3                   	ret
    2e01:	48 89 c3             	mov    %rax,%rbx
    2e04:	e9 00 00 00 00       	jmp    2e09 <Mips2C::jak1::sp_process_block_3d::link()+0x119>	2e05: R_X86_64_PC32	.text.unlikely-0x4
    2e09:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)

0000000000002e10 <Mips2C::jak1::sp_process_block_2d::link()>:
    2e10:	53                   	push   %rbx
    2e11:	bf 00 00 00 00       	mov    $0x0,%edi	2e12: R_X86_64_32	.rodata.str1.1+0x14
    2e16:	48 83 ec 20          	sub    $0x20,%rsp
    2e1a:	e8 00 00 00 00       	call   2e1f <Mips2C::jak1::sp_process_block_2d::link()+0xf>	2e1b: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2e1f:	bf 00 00 00 00       	mov    $0x0,%edi	2e20: R_X86_64_32	.rodata.str1.1+0x31
    2e24:	89 c2                	mov    %eax,%edx
    2e26:	89 c0                	mov    %eax,%eax
    2e28:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2e2f <Mips2C::jak1::sp_process_block_2d::link()+0x1f>	2e2b: R_X86_64_PC32	g_ee_main_mem-0x4
    2e2f:	85 d2                	test   %edx,%edx
    2e31:	ba 00 00 00 00       	mov    $0x0,%edx
    2e36:	48 0f 44 c2          	cmove  %rdx,%rax
    2e3a:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2e41 <Mips2C::jak1::sp_process_block_2d::link()+0x31>	2e3d: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
    2e41:	e8 00 00 00 00       	call   2e46 <Mips2C::jak1::sp_process_block_2d::link()+0x36>	2e42: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2e46:	bf 00 00 00 00       	mov    $0x0,%edi	2e47: R_X86_64_32	.rodata.str1.1+0x5a
    2e4b:	89 c2                	mov    %eax,%edx
    2e4d:	89 c0                	mov    %eax,%eax
    2e4f:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2e56 <Mips2C::jak1::sp_process_block_2d::link()+0x46>	2e52: R_X86_64_PC32	g_ee_main_mem-0x4
    2e56:	85 d2                	test   %edx,%edx
    2e58:	ba 00 00 00 00       	mov    $0x0,%edx
    2e5d:	48 0f 44 c2          	cmove  %rdx,%rax
    2e61:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2e68 <Mips2C::jak1::sp_process_block_2d::link()+0x58>	2e64: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x4
    2e68:	e8 00 00 00 00       	call   2e6d <Mips2C::jak1::sp_process_block_2d::link()+0x5d>	2e69: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2e6d:	bf 00 00 00 00       	mov    $0x0,%edi	2e6e: R_X86_64_32	.rodata.str1.1+0x65
    2e72:	89 c2                	mov    %eax,%edx
    2e74:	89 c0                	mov    %eax,%eax
    2e76:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2e7d <Mips2C::jak1::sp_process_block_2d::link()+0x6d>	2e79: R_X86_64_PC32	g_ee_main_mem-0x4
    2e7d:	85 d2                	test   %edx,%edx
    2e7f:	ba 00 00 00 00       	mov    $0x0,%edx
    2e84:	48 0f 44 c2          	cmove  %rdx,%rax
    2e88:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2e8f <Mips2C::jak1::sp_process_block_2d::link()+0x7f>	2e8b: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0xc
    2e8f:	e8 00 00 00 00       	call   2e94 <Mips2C::jak1::sp_process_block_2d::link()+0x84>	2e90: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2e94:	bf 14 00 00 00       	mov    $0x14,%edi
    2e99:	89 c2                	mov    %eax,%edx
    2e9b:	89 c0                	mov    %eax,%eax
    2e9d:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2ea4 <Mips2C::jak1::sp_process_block_2d::link()+0x94>	2ea0: R_X86_64_PC32	g_ee_main_mem-0x4
    2ea4:	85 d2                	test   %edx,%edx
    2ea6:	ba 00 00 00 00       	mov    $0x0,%edx
    2eab:	48 0f 44 c2          	cmove  %rdx,%rax
    2eaf:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2eb6 <Mips2C::jak1::sp_process_block_2d::link()+0xa6>	2eb2: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x14
    2eb6:	e8 00 00 00 00       	call   2ebb <Mips2C::jak1::sp_process_block_2d::link()+0xab>	2eb7: R_X86_64_PLT32	operator new(unsigned long)-0x4
    2ebb:	c5 f9 6f 05 00 00 00 00 	vmovdqa 0x0(%rip),%xmm0        # 2ec3 <Mips2C::jak1::sp_process_block_2d::link()+0xb3>	2ebf: R_X86_64_PC32	.LC32-0x4
    2ec3:	48 89 e6             	mov    %rsp,%rsi
    2ec6:	b9 00 01 00 00       	mov    $0x100,%ecx
    2ecb:	c6 40 13 00          	movb   $0x0,0x13(%rax)
    2ecf:	ba 00 00 00 00       	mov    $0x0,%edx	2ed0: R_X86_64_32	Mips2C::jak1::sp_process_block_2d::execute(void*)
    2ed4:	bf 00 00 00 00       	mov    $0x0,%edi	2ed5: R_X86_64_32	Mips2C::gLinkedFunctionTable
    2ed9:	c5 fa 7f 00          	vmovdqu %xmm0,(%rax)
    2edd:	c7 40 0f 6b 2d 32 64 	movl   $0x64322d6b,0xf(%rax)
    2ee4:	48 89 04 24          	mov    %rax,(%rsp)
    2ee8:	48 c7 44 24 10 13 00 00 00 	movq   $0x13,0x10(%rsp)
    2ef1:	48 c7 44 24 08 13 00 00 00 	movq   $0x13,0x8(%rsp)
    2efa:	e8 00 00 00 00       	call   2eff <Mips2C::jak1::sp_process_block_2d::link()+0xef>	2efb: R_X86_64_PLT32	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)-0x4
    2eff:	48 8b 3c 24          	mov    (%rsp),%rdi
    2f03:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
    2f08:	48 39 c7             	cmp    %rax,%rdi
    2f0b:	74 0e                	je     2f1b <Mips2C::jak1::sp_process_block_2d::link()+0x10b>
    2f0d:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
    2f12:	48 8d 70 01          	lea    0x1(%rax),%rsi
    2f16:	e8 00 00 00 00       	call   2f1b <Mips2C::jak1::sp_process_block_2d::link()+0x10b>	2f17: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
    2f1b:	48 83 c4 20          	add    $0x20,%rsp
    2f1f:	5b                   	pop    %rbx
    2f20:	c3                   	ret
    2f21:	48 89 c3             	mov    %rax,%rbx
    2f24:	e9 00 00 00 00       	jmp    2f29 <Mips2C::jak1::sp_process_block_2d::link()+0x119>	2f25: R_X86_64_PC32	.text.unlikely+0x28

Disassembly of section .text.unlikely:

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

000000000000002c <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]>:
  2c:	48 8b 3c 24          	mov    (%rsp),%rdi
  30:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
  35:	48 39 c7             	cmp    %rax,%rdi
  38:	75 0b                	jne    45 <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x19>
  3a:	c5 f8 77             	vzeroupper
  3d:	48 89 df             	mov    %rbx,%rdi
  40:	e8 00 00 00 00       	call   45 <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x19>	41: R_X86_64_PLT32	_Unwind_Resume-0x4
  45:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
  4a:	48 8d 70 01          	lea    0x1(%rax),%rsi
  4e:	c5 f8 77             	vzeroupper
  51:	e8 00 00 00 00       	call   56 <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x2a>	52: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
  56:	eb e5                	jmp    3d <Mips2C::jak1::sp_process_block_2d::link() [clone .cold]+0x11>

EXIT 0
