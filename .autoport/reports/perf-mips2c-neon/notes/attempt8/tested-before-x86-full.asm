$ objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-before-x86.o

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-before-x86.o:     file format elf64-x86-64


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

00000000000000d0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>:
      d0:	4c 8d 54 24 08       	lea    0x8(%rsp),%r10
      d5:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
      d9:	41 ff 72 f8          	push   -0x8(%r10)
      dd:	55                   	push   %rbp
      de:	48 89 e5             	mov    %rsp,%rbp
      e1:	41 57                	push   %r15
      e3:	41 56                	push   %r14
      e5:	41 55                	push   %r13
      e7:	41 54                	push   %r12
      e9:	41 52                	push   %r10
      eb:	53                   	push   %rbx
      ec:	48 81 ec 40 01 00 00 	sub    $0x140,%rsp
      f3:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
      fa:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
     101:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 108 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x38>	104: R_X86_64_PC32	g_ee_main_mem-0x4
     108:	48 83 c0 80          	add    $0xffffffffffffff80,%rax
     10c:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
     113:	89 c0                	mov    %eax,%eax
     115:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
     119:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     11f:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 126 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x56>	122: R_X86_64_PC32	g_ee_main_mem-0x4
     126:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
     12e:	83 c0 10             	add    $0x10,%eax
     131:	83 e0 f0             	and    $0xfffffff0,%eax
     134:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     13a:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     140:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
     148:	83 c0 20             	add    $0x20,%eax
     14b:	83 e0 f0             	and    $0xfffffff0,%eax
     14e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     154:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     15a:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
     162:	83 c0 30             	add    $0x30,%eax
     165:	83 e0 f0             	and    $0xfffffff0,%eax
     168:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     16e:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     174:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
     17c:	83 c0 40             	add    $0x40,%eax
     17f:	83 e0 f0             	and    $0xfffffff0,%eax
     182:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     188:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     18e:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
     196:	83 c0 50             	add    $0x50,%eax
     199:	83 e0 f0             	and    $0xfffffff0,%eax
     19c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     1a2:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     1a8:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
     1b0:	83 c0 60             	add    $0x60,%eax
     1b3:	83 e0 f0             	and    $0xfffffff0,%eax
     1b6:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     1bc:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
     1c2:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
     1ca:	83 c0 70             	add    $0x70,%eax
     1cd:	83 e0 f0             	and    $0xfffffff0,%eax
     1d0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     1d6:	48 8b 47 40          	mov    0x40(%rdi),%rax
     1da:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
     1e1:	48 8b 47 50          	mov    0x50(%rdi),%rax
     1e5:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
     1ec:	48 8b 47 60          	mov    0x60(%rdi),%rax
     1f0:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
     1f7:	48 8b 47 70          	mov    0x70(%rdi),%rax
     1fb:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
     202:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
     209:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
     210:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
     217:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
     21e:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 225 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x155>	221: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
     225:	48 63 10             	movslq (%rax),%rdx
     228:	48 89 57 30          	mov    %rdx,0x30(%rdi)
     22c:	f6 c2 0f             	test   $0xf,%dl
     22f:	0f 85 7a 16 00 00    	jne    18af <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
     235:	89 d0                	mov    %edx,%eax
     237:	49 89 fe             	mov    %rdi,%r14
     23a:	49 8b 14 01          	mov    (%r9,%rax,1),%rdx
     23e:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
     243:	48 89 97 10 03 00 00 	mov    %rdx,0x310(%rdi)
     24a:	48 89 57 30          	mov    %rdx,0x30(%rdi)
     24e:	81 e2 ff 00 00 00    	and    $0xff,%edx
     254:	48 89 87 18 03 00 00 	mov    %rax,0x318(%rdi)
     25b:	48 89 47 38          	mov    %rax,0x38(%rdi)
     25f:	48 89 97 00 01 00 00 	mov    %rdx,0x100(%rdi)
     266:	e9 ba 00 00 00       	jmp    325 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x255>
     26b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
     270:	48 63 09             	movslq (%rcx),%rcx
     273:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
     27b:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     27f:	85 c9                	test   %ecx,%ecx
     281:	0f 84 91 0e 00 00    	je     1118 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1048>
     287:	8b 06                	mov    (%rsi),%eax
     289:	89 c1                	mov    %eax,%ecx
     28b:	83 e0 bf             	and    $0xffffffbf,%eax
     28e:	83 e1 40             	and    $0x40,%ecx
     291:	48 63 d0             	movslq %eax,%rdx
     294:	89 cb                	mov    %ecx,%ebx
     296:	49 89 56 40          	mov    %rdx,0x40(%r14)
     29a:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     29e:	89 06                	mov    %eax,(%rsi)
     2a0:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     2a7:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 2ae <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1de>	2aa: R_X86_64_PC32	g_ee_main_mem-0x4
     2ae:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     2b5:	85 c9                	test   %ecx,%ecx
     2b7:	74 27                	je     2e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
     2b9:	89 c0                	mov    %eax,%eax
     2bb:	89 d2                	mov    %edx,%edx
     2bd:	49 63 4c 01 7c       	movslq 0x7c(%r9,%rax,1),%rcx
     2c2:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     2c6:	41 89 4c 11 2c       	mov    %ecx,0x2c(%r9,%rdx,1)
     2cb:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     2d2:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     2d9:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 2e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>	2dc: R_X86_64_PC32	g_ee_main_mem-0x4
     2e0:	48 05 90 00 00 00    	add    $0x90,%rax
     2e6:	49 8b 9e 30 01 00 00 	mov    0x130(%r14),%rbx
     2ed:	48 83 c2 30          	add    $0x30,%rdx
     2f1:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
     2f8:	49 8b 86 10 01 00 00 	mov    0x110(%r14),%rax
     2ff:	48 8d 4b ff          	lea    -0x1(%rbx),%rcx
     303:	49 89 96 40 01 00 00 	mov    %rdx,0x140(%r14)
     30a:	48 83 c0 01          	add    $0x1,%rax
     30e:	49 89 8e 30 01 00 00 	mov    %rcx,0x130(%r14)
     315:	49 89 86 10 01 00 00 	mov    %rax,0x110(%r14)
     31c:	48 85 c9             	test   %rcx,%rcx
     31f:	0f 84 cb 0e 00 00    	je     11f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1120>
     325:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     32c:	49 8b be 70 01 00 00 	mov    0x170(%r14),%rdi
     333:	89 c1                	mov    %eax,%ecx
     335:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
     33d:	49 89 56 30          	mov    %rdx,0x30(%r14)
     341:	48 39 d7             	cmp    %rdx,%rdi
     344:	0f 84 be 0d 00 00    	je     1108 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1038>
     34a:	49 8d 74 09 68       	lea    0x68(%r9,%rcx,1),%rsi
     34f:	49 8d 4c 09 64       	lea    0x64(%r9,%rcx,1),%rcx
     354:	48 63 16             	movslq (%rsi),%rdx
     357:	49 3b be 20 01 00 00 	cmp    0x120(%r14),%rdi
     35e:	0f 84 c4 0d 00 00    	je     1128 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1058>
     364:	81 e2 00 20 00 00    	and    $0x2000,%edx
     36a:	89 d3                	mov    %edx,%ebx
     36c:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     370:	0f 84 fa fe ff ff    	je     270 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1a0>
     376:	48 63 11             	movslq (%rcx),%rdx
     379:	48 89 d7             	mov    %rdx,%rdi
     37c:	49 2b be 00 01 00 00 	sub    0x100(%r14),%rdi
     383:	49 89 56 30          	mov    %rdx,0x30(%r14)
     387:	49 89 7e 40          	mov    %rdi,0x40(%r14)
     38b:	48 83 fa ff          	cmp    $0xffffffffffffffff,%rdx
     38f:	74 51                	je     3e2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x312>
     391:	48 89 fe             	mov    %rdi,%rsi
     394:	c4 c1 79 6e 6e 48    	vmovd  0x48(%r14),%xmm5
     39a:	c4 c3 51 22 4e 4c 01 	vpinsrd $0x1,0x4c(%r14),%xmm5,%xmm1
     3a1:	c5 f9 6e ef          	vmovd  %edi,%xmm5
     3a5:	48 c1 fe 20          	sar    $0x20,%rsi
     3a9:	c4 e3 51 22 c6 01    	vpinsrd $0x1,%esi,%xmm5,%xmm0
     3af:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
     3b3:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
     3b7:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
     3bc:	c4 c1 79 7f 46 30    	vmovdqa %xmm0,0x30(%r14)
     3c2:	48 85 d2             	test   %rdx,%rdx
     3c5:	0f 84 4d 0d 00 00    	je     1118 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1048>
     3cb:	c5 f9 7e 01          	vmovd  %xmm0,(%rcx)
     3cf:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
     3d6:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 3dd <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x30d>	3d9: R_X86_64_PC32	g_ee_main_mem-0x4
     3dd:	48 8d 74 02 68       	lea    0x68(%rdx,%rax,1),%rsi
     3e2:	8b 06                	mov    (%rsi),%eax
     3e4:	89 c2                	mov    %eax,%edx
     3e6:	83 e0 bf             	and    $0xffffffbf,%eax
     3e9:	83 e2 40             	and    $0x40,%edx
     3ec:	48 63 c8             	movslq %eax,%rcx
     3ef:	89 d3                	mov    %edx,%ebx
     3f1:	49 89 4e 40          	mov    %rcx,0x40(%r14)
     3f5:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     3f9:	89 06                	mov    %eax,(%rsi)
     3fb:	85 d2                	test   %edx,%edx
     3fd:	74 25                	je     424 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x354>
     3ff:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
     406:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 40d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x33d>	409: R_X86_64_PC32	g_ee_main_mem-0x4
     40d:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
     412:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     416:	48 89 ca             	mov    %rcx,%rdx
     419:	41 8b 8e 40 01 00 00 	mov    0x140(%r14),%ecx
     420:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
     424:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 42b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x35b>	427: R_X86_64_PC32	g_ee_main_mem-0x4
     42b:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
     432:	49 63 4c 01 70       	movslq 0x70(%r9,%rax,1),%rcx
     437:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
     43e:	85 c9                	test   %ecx,%ecx
     440:	0f 84 fa 01 00 00    	je     640 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     446:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
     44f:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     456:	48 83 e8 50          	sub    $0x50,%rax
     45a:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     461:	83 e0 f0             	and    $0xfffffff0,%eax
     464:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     46a:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     471:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
     47a:	83 c0 10             	add    $0x10,%eax
     47d:	83 e0 f0             	and    $0xfffffff0,%eax
     480:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     486:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     48d:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
     496:	83 c0 20             	add    $0x20,%eax
     499:	83 e0 f0             	and    $0xfffffff0,%eax
     49c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     4a2:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     4a9:	c4 c1 79 6f 86 10 01 00 00 	vmovdqa 0x110(%r14),%xmm0
     4b2:	83 c0 30             	add    $0x30,%eax
     4b5:	83 e0 f0             	and    $0xfffffff0,%eax
     4b8:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     4be:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
     4c5:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
     4ce:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
     4d5:	49 89 46 40          	mov    %rax,0x40(%r14)
     4d9:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     4e0:	49 89 46 50          	mov    %rax,0x50(%r14)
     4e4:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     4eb:	49 89 46 60          	mov    %rax,0x60(%r14)
     4ef:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     4f6:	83 c0 40             	add    $0x40,%eax
     4f9:	83 e0 f0             	and    $0xfffffff0,%eax
     4fc:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     502:	c4 c1 7a 7e 6e 60    	vmovq  0x60(%r14),%xmm5
     508:	c4 c1 7a 7e a6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm4
     511:	c4 c3 d9 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm4,%xmm1
     51b:	c4 c3 d1 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm5,%xmm2
     522:	c4 c1 7a 7e a6 80 00 00 00 	vmovq  0x80(%r14),%xmm4
     52b:	c4 c3 d9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm4,%xmm0
     535:	c4 c1 7a 7e 66 40    	vmovq  0x40(%r14),%xmm4
     53b:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     541:	c4 c3 d9 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm4,%xmm1
     548:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     54e:	c5 fd 7f 8d d0 fe ff ff 	vmovdqa %ymm1,-0x130(%rbp)
     556:	c5 fd 7f 85 f0 fe ff ff 	vmovdqa %ymm0,-0x110(%rbp)
     55e:	85 ff                	test   %edi,%edi
     560:	0f 84 8a 13 00 00    	je     18f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
     566:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     56d:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     574:	4c 01 cf             	add    %r9,%rdi
     577:	31 d2                	xor    %edx,%edx
     579:	48 8d b5 d0 fe ff ff 	lea    -0x130(%rbp),%rsi
     580:	c5 f8 77             	vzeroupper
     583:	e8 00 00 00 00       	call   588 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4b8>	584: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     588:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 58f <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4bf>	58b: R_X86_64_PC32	g_ee_main_mem-0x4
     58f:	49 89 46 20          	mov    %rax,0x20(%r14)
     593:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     59a:	48 89 c1             	mov    %rax,%rcx
     59d:	83 e1 f0             	and    $0xfffffff0,%ecx
     5a0:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     5a5:	8d 48 10             	lea    0x10(%rax),%ecx
     5a8:	83 e1 f0             	and    $0xfffffff0,%ecx
     5ab:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
     5b4:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     5b9:	8d 48 20             	lea    0x20(%rax),%ecx
     5bc:	83 e1 f0             	and    $0xfffffff0,%ecx
     5bf:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
     5c8:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     5cd:	8d 48 30             	lea    0x30(%rax),%ecx
     5d0:	83 e1 f0             	and    $0xfffffff0,%ecx
     5d3:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
     5dc:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     5e1:	8d 48 40             	lea    0x40(%rax),%ecx
     5e4:	48 83 c0 50          	add    $0x50,%rax
     5e8:	83 e1 f0             	and    $0xfffffff0,%ecx
     5eb:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
     5f4:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
     5f9:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     600:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
     609:	e8 f2 f9 ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
     60e:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
     615:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 61c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x54c>	618: R_X86_64_PC32	g_ee_main_mem-0x4
     61c:	84 c0                	test   %al,%al
     61e:	89 f0                	mov    %esi,%eax
     620:	74 1e                	je     640 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     622:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # 628 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x558>	624: R_X86_64_PC32	.bss+0x128
     628:	81 fa 3f 1f 00 00    	cmp    $0x1f3f,%edx
     62e:	0f 8e dc 10 00 00    	jle    1710 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1640>
     634:	90                   	nop
     635:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
     640:	49 63 4c 01 78       	movslq 0x78(%r9,%rax,1),%rcx
     645:	49 89 4e 50          	mov    %rcx,0x50(%r14)
     649:	48 89 ca             	mov    %rcx,%rdx
     64c:	49 8d 4c 01 74       	lea    0x74(%r9,%rax,1),%rcx
     651:	48 63 01             	movslq (%rcx),%rax
     654:	49 89 46 30          	mov    %rax,0x30(%r14)
     658:	49 2b 86 00 01 00 00 	sub    0x100(%r14),%rax
     65f:	49 89 46 40          	mov    %rax,0x40(%r14)
     663:	85 d2                	test   %edx,%edx
     665:	74 13                	je     67a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
     667:	48 8d 50 ff          	lea    -0x1(%rax),%rdx
     66b:	49 89 56 30          	mov    %rdx,0x30(%r14)
     66f:	89 01                	mov    %eax,(%rcx)
     671:	48 85 d2             	test   %rdx,%rdx
     674:	0f 88 46 0c 00 00    	js     12c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x11f0>
     67a:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     681:	f6 c2 0f             	test   $0xf,%dl
     684:	0f 85 25 12 00 00    	jne    18af <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
     68a:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 691 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5c1>	68d: R_X86_64_PC32	g_ee_main_mem-0x4
     691:	89 d2                	mov    %edx,%edx
     693:	4d 8b 96 50 01 00 00 	mov    0x150(%r14),%r10
     69a:	c5 7a 7e 04 10       	vmovq  (%rax,%rdx,1),%xmm8
     69f:	48 8b 4c 10 08       	mov    0x8(%rax,%rdx,1),%rcx
     6a4:	c4 41 79 d6 86 90 02 00 00 	vmovq  %xmm8,0x290(%r14)
     6ad:	49 89 8e 98 02 00 00 	mov    %rcx,0x298(%r14)
     6b4:	48 8b 74 10 10       	mov    0x10(%rax,%rdx,1),%rsi
     6b9:	4c 8b 44 10 18       	mov    0x18(%rax,%rdx,1),%r8
     6be:	49 89 b6 a0 02 00 00 	mov    %rsi,0x2a0(%r14)
     6c5:	4d 89 86 a8 02 00 00 	mov    %r8,0x2a8(%r14)
     6cc:	48 8b 74 10 20       	mov    0x20(%rax,%rdx,1),%rsi
     6d1:	48 8b 7c 10 28       	mov    0x28(%rax,%rdx,1),%rdi
     6d6:	49 89 b6 b0 02 00 00 	mov    %rsi,0x2b0(%r14)
     6dd:	49 89 be b8 02 00 00 	mov    %rdi,0x2b8(%r14)
     6e4:	41 f6 c2 0f          	test   $0xf,%r10b
     6e8:	0f 85 c1 11 00 00    	jne    18af <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17df>
     6ee:	45 89 d2             	mov    %r10d,%r10d
     6f1:	c4 63 b9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm8,%xmm8
     6f7:	c4 c1 7a 10 b6 18 03 00 00 	vmovss 0x318(%r14),%xmm6
     700:	c4 41 7a 10 a6 1c 03 00 00 	vmovss 0x31c(%r14),%xmm12
     709:	4e 8d 64 10 10       	lea    0x10(%rax,%r10,1),%r12
     70e:	49 8b 0c 24          	mov    (%r12),%rcx
     712:	49 8b 54 24 08       	mov    0x8(%r12),%rdx
     717:	c5 c8 c6 d6 00       	vshufps $0x0,%xmm6,%xmm6,%xmm2
     71c:	49 89 8e c0 02 00 00 	mov    %rcx,0x2c0(%r14)
     723:	49 89 d5             	mov    %rdx,%r13
     726:	49 89 96 c8 02 00 00 	mov    %rdx,0x2c8(%r14)
     72d:	4e 8b 4c 10 20       	mov    0x20(%rax,%r10,1),%r9
     732:	49 c1 ed 20          	shr    $0x20,%r13
     736:	4a 8b 5c 10 28       	mov    0x28(%rax,%r10,1),%rbx
     73b:	4d 89 8e d0 02 00 00 	mov    %r9,0x2d0(%r14)
     742:	49 89 9e d8 02 00 00 	mov    %rbx,0x2d8(%r14)
     749:	4e 8b 5c 10 38       	mov    0x38(%rax,%r10,1),%r11
     74e:	c4 a1 7a 7e 4c 10 30 	vmovq  0x30(%rax,%r10,1),%xmm1
     755:	4d 89 9e e8 02 00 00 	mov    %r11,0x2e8(%r14)
     75c:	c4 c1 f9 6e eb       	vmovq  %r11,%xmm5
     761:	45 89 df             	mov    %r11d,%r15d
     764:	c4 c1 79 d6 8e e0 02 00 00 	vmovq  %xmm1,0x2e0(%r14)
     76d:	c4 c3 f1 22 e3 01    	vpinsrq $0x1,%r11,%xmm1,%xmm4
     773:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
     778:	c4 a1 7a 6f 7c 10 40 	vmovdqu 0x40(%rax,%r10,1),%xmm7
     77f:	c4 c1 7a 7e 8e 14 03 00 00 	vmovq  0x314(%r14),%xmm1
     788:	c5 79 6f fd          	vmovdqa %xmm5,%xmm15
     78c:	c5 e8 59 d7          	vmulps %xmm7,%xmm2,%xmm2
     790:	c5 f9 6f ef          	vmovdqa %xmm7,%xmm5
     794:	c5 f9 6f df          	vmovdqa %xmm7,%xmm3
     798:	c4 c1 7a 7f be f0 02 00 00 	vmovdqu %xmm7,0x2f0(%r14)
     7a1:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
     7a6:	c5 7a 12 d9          	vmovsldup %xmm1,%xmm11
     7aa:	c5 79 6f ed          	vmovdqa %xmm5,%xmm13
     7ae:	c5 70 c6 f1 00       	vshufps $0x0,%xmm1,%xmm1,%xmm14
     7b3:	c5 f0 c6 e9 00       	vshufps $0x0,%xmm1,%xmm1,%xmm5
     7b8:	c5 fa 16 c9          	vmovshdup %xmm1,%xmm1
     7bc:	c4 41 60 14 cd       	vunpcklps %xmm13,%xmm3,%xmm9
     7c1:	c5 f9 6e f9          	vmovd  %ecx,%xmm7
     7c5:	c4 41 7a 7e c9       	vmovq  %xmm9,%xmm9
     7ca:	48 c1 e9 20          	shr    $0x20,%rcx
     7ce:	4e 63 54 10 60       	movslq 0x60(%rax,%r10,1),%r10
     7d3:	c4 43 0d 18 f6 01    	vinsertf128 $0x1,%xmm14,%ymm14,%ymm14
     7d9:	c5 79 6e d1          	vmovd  %ecx,%xmm10
     7dd:	c4 c1 78 29 96 f0 02 00 00 	vmovaps %xmm2,0x2f0(%r14)
     7e6:	c5 e8 15 d2          	vunpckhps %xmm2,%xmm2,%xmm2
     7ea:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     7ee:	45 89 96 00 02 00 00 	mov    %r10d,0x200(%r14)
     7f5:	c4 c1 70 59 c9       	vmulps %xmm9,%xmm1,%xmm1
     7fa:	c4 41 40 14 ca       	vunpcklps %xmm10,%xmm7,%xmm9
     7ff:	4d 89 56 30          	mov    %r10,0x30(%r14)
     803:	c4 41 7a 7e c9       	vmovq  %xmm9,%xmm9
     808:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
     80c:	c4 c1 70 58 c9       	vaddps %xmm9,%xmm1,%xmm1
     811:	c5 79 6e ca          	vmovd  %edx,%xmm9
     815:	c4 c1 6a 58 d1       	vaddss %xmm9,%xmm2,%xmm2
     81a:	c4 c1 78 13 8e c0 02 00 00 	vmovlps %xmm1,0x2c0(%r14)
     823:	c4 c1 7a 11 96 c8 02 00 00 	vmovss %xmm2,0x2c8(%r14)
     82c:	45 85 d2             	test   %r10d,%r10d
     82f:	0f 85 03 09 00 00    	jne    1138 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1068>
     835:	c5 fa 16 f1          	vmovshdup %xmm1,%xmm6
     839:	c5 f8 28 d9          	vmovaps %xmm1,%xmm3
     83d:	c4 c1 79 6e fd       	vmovd  %r13d,%xmm7
     842:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     846:	c4 c1 79 6e c9       	vmovd  %r9d,%xmm1
     84b:	49 c1 e9 20          	shr    $0x20,%r9
     84f:	c5 d0 59 e4          	vmulps %xmm4,%xmm5,%xmm4
     853:	c5 e8 14 d7          	vunpcklps %xmm7,%xmm2,%xmm2
     857:	c4 41 7a 7e db       	vmovq  %xmm11,%xmm11
     85c:	c5 e0 16 d2          	vmovlhps %xmm2,%xmm3,%xmm2
     860:	c5 e8 59 ed          	vmulps %xmm5,%xmm2,%xmm5
     864:	c5 f9 6e db          	vmovd  %ebx,%xmm3
     868:	48 c1 eb 20          	shr    $0x20,%rbx
     86c:	c5 f9 6e f3          	vmovd  %ebx,%xmm6
     870:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     874:	c4 c1 79 6e f1       	vmovd  %r9d,%xmm6
     879:	c5 f0 14 ce          	vunpcklps %xmm6,%xmm1,%xmm1
     87d:	c4 c1 79 6e f7       	vmovd  %r15d,%xmm6
     882:	c5 f0 16 cb          	vmovlhps %xmm3,%xmm1,%xmm1
     886:	c4 e3 6d 18 c9 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm1
     88c:	c4 c1 48 14 c7       	vunpcklps %xmm15,%xmm6,%xmm0
     891:	c4 c1 79 6e d8       	vmovd  %r8d,%xmm3
     896:	c4 c1 74 59 ce       	vmulps %ymm14,%ymm1,%ymm1
     89b:	c4 c1 50 58 e8       	vaddps %xmm8,%xmm5,%xmm5
     8a0:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     8a4:	49 c1 e8 20          	shr    $0x20,%r8
     8a8:	c4 c1 78 59 c3       	vmulps %xmm11,%xmm0,%xmm0
     8ad:	c4 c1 79 6e f8       	vmovd  %r8d,%xmm7
     8b2:	c4 c1 78 29 a6 40 03 00 00 	vmovaps %xmm4,0x340(%r14)
     8bb:	c4 c1 78 29 ae 90 02 00 00 	vmovaps %xmm5,0x290(%r14)
     8c4:	c4 c1 7c 11 8e 20 03 00 00 	vmovups %ymm1,0x320(%r14)
     8cd:	c4 e3 7d 19 c9 01    	vextractf128 $0x1,%ymm1,%xmm1
     8d3:	c5 f0 15 e9          	vunpckhps %xmm1,%xmm1,%xmm5
     8d7:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     8db:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
     8e0:	c5 f2 58 cf          	vaddss %xmm7,%xmm1,%xmm1
     8e4:	c5 d2 58 eb          	vaddss %xmm3,%xmm5,%xmm5
     8e8:	c5 f9 6e df          	vmovd  %edi,%xmm3
     8ec:	48 c1 ef 20          	shr    $0x20,%rdi
     8f0:	c5 f9 6e f7          	vmovd  %edi,%xmm6
     8f4:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     8f8:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
     8fc:	c5 d0 14 c9          	vunpcklps %xmm1,%xmm5,%xmm1
     900:	c5 f8 58 c3          	vaddps %xmm3,%xmm0,%xmm0
     904:	c5 f9 6e de          	vmovd  %esi,%xmm3
     908:	48 c1 ee 20          	shr    $0x20,%rsi
     90c:	c5 da 58 f3          	vaddss %xmm3,%xmm4,%xmm6
     910:	c5 f9 6e fe          	vmovd  %esi,%xmm7
     914:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
     919:	c5 e0 57 db          	vxorps %xmm3,%xmm3,%xmm3
     91d:	c5 da 58 e7          	vaddss %xmm7,%xmm4,%xmm4
     921:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
     925:	c5 78 28 c0          	vmovaps %xmm0,%xmm8
     929:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
     92d:	c5 ca c2 ff 05       	vcmpnltss %xmm7,%xmm6,%xmm7
     932:	c4 e3 61 4a de 70    	vblendvps %xmm7,%xmm6,%xmm3,%xmm3
     938:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
     93c:	c5 c8 57 f6          	vxorps %xmm6,%xmm6,%xmm6
     940:	c5 da c2 ff 05       	vcmpnltss %xmm7,%xmm4,%xmm7
     945:	c4 e3 49 4a f4 70    	vblendvps %xmm7,%xmm4,%xmm6,%xmm6
     94b:	c5 e0 14 de          	vunpcklps %xmm6,%xmm3,%xmm3
     94f:	c5 f0 16 cb          	vmovlhps %xmm3,%xmm1,%xmm1
     953:	c4 c1 78 11 8e a8 02 00 00 	vmovups %xmm1,0x2a8(%r14)
     95c:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
     960:	c5 f8 c2 c1 01       	vcmpltps %xmm1,%xmm0,%xmm0
     965:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
     969:	c4 63 39 4a c1 00    	vblendvps %xmm0,%xmm1,%xmm8,%xmm8
     96f:	c4 41 78 13 86 b8 02 00 00 	vmovlps %xmm8,0x2b8(%r14)
     978:	c4 c1 78 11 14 24    	vmovups %xmm2,(%r12)
     97e:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     985:	f6 c2 0f             	test   $0xf,%dl
     988:	0f 85 40 0f 00 00    	jne    18ce <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
     98e:	c4 c1 79 6f 86 90 02 00 00 	vmovdqa 0x290(%r14),%xmm0
     997:	89 d2                	mov    %edx,%edx
     999:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
     99e:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     9a5:	f6 c2 0f             	test   $0xf,%dl
     9a8:	0f 85 20 0f 00 00    	jne    18ce <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
     9ae:	c4 c1 79 6f 86 a0 02 00 00 	vmovdqa 0x2a0(%r14),%xmm0
     9b7:	89 d2                	mov    %edx,%edx
     9b9:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
     9bf:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     9c6:	f6 c2 0f             	test   $0xf,%dl
     9c9:	0f 85 ff 0e 00 00    	jne    18ce <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>
     9cf:	c4 c1 79 6f 86 b0 02 00 00 	vmovdqa 0x2b0(%r14),%xmm0
     9d8:	89 d2                	mov    %edx,%edx
     9da:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
     9e0:	c5 f8 77             	vzeroupper
     9e3:	e8 18 f6 ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
     9e8:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
     9ef:	84 c0                	test   %al,%al
     9f1:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 9f8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x928>	9f4: R_X86_64_PC32	g_ee_main_mem-0x4
     9f8:	0f 84 b2 00 00 00    	je     ab0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
     9fe:	8b 0d 00 00 00 00    	mov    0x0(%rip),%ecx        # a04 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x934>	a00: R_X86_64_PC32	.bss+0x120
     a04:	81 f9 3f 1f 00 00    	cmp    $0x1f3f,%ecx
     a0a:	0f 8f a0 00 00 00    	jg     ab0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
     a10:	48 8b 7c 10 20       	mov    0x20(%rax,%rdx,1),%rdi
     a15:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
     a1c:	4c 8b 44 10 28       	mov    0x28(%rax,%rdx,1),%r8
     a21:	41 89 f2             	mov    %esi,%r10d
     a24:	c5 79 6e c7          	vmovd  %edi,%xmm8
     a28:	c5 78 2f 05 00 00 00 00 	vcomiss 0x0(%rip),%xmm8        # a30 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x960>	a2c: R_X86_64_PC32	.LC15-0x4
     a30:	4e 8b 4c 10 30       	mov    0x30(%rax,%r10,1),%r9
     a35:	c4 c1 79 6e d0       	vmovd  %r8d,%xmm2
     a3a:	4e 8b 54 10 38       	mov    0x38(%rax,%r10,1),%r10
     a3f:	c4 c1 79 6e e1       	vmovd  %r9d,%xmm4
     a44:	0f 87 a6 0b 00 00    	ja     15f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1520>
     a4a:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
     a4e:	c5 f8 2e d0          	vucomiss %xmm0,%xmm2
     a52:	7a 3c                	jp     a90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
     a54:	75 3a                	jne    a90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
     a56:	c4 e1 f9 6e f7       	vmovq  %rdi,%xmm6
     a5b:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
     a60:	c5 f8 2f 35 00 00 00 00 	vcomiss 0x0(%rip),%xmm6        # a68 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x998>	a64: R_X86_64_PC32	.LC16-0x4
     a68:	c5 f9 6f ce          	vmovdqa %xmm6,%xmm1
     a6c:	72 22                	jb     a90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
     a6e:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # a76 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9a6>	a72: R_X86_64_PC32	.LC17-0x4
     a76:	c4 c1 78 2f c0       	vcomiss %xmm8,%xmm0
     a7b:	0f 83 9f 0b 00 00    	jae    1620 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1550>
     a81:	0f 1f 40 00          	nopl   0x0(%rax)
     a85:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
     a90:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # a98 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c8>	a94: R_X86_64_PC32	.LC18-0x4
     a98:	c5 f8 2f c4          	vcomiss %xmm4,%xmm0
     a9c:	0f 87 3a 0d 00 00    	ja     17dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x170c>
     aa2:	0f 1f 00             	nopl   (%rax)
     aa5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
     ab0:	48 8d 54 10 18       	lea    0x18(%rax,%rdx,1),%rdx
     ab5:	c5 d8 57 e4          	vxorps %xmm4,%xmm4,%xmm4
     ab9:	c5 fa 2c 02          	vcvttss2si (%rdx),%eax
     abd:	48 0f bf c8          	movswq %ax,%rcx
     ac1:	98                   	cwtl
     ac2:	c5 da 2a c0          	vcvtsi2ss %eax,%xmm4,%xmm0
     ac6:	49 89 4e 30          	mov    %rcx,0x30(%r14)
     aca:	c4 c1 7a 11 86 00 02 00 00 	vmovss %xmm0,0x200(%r14)
     ad3:	c5 fa 11 02          	vmovss %xmm0,(%rdx)
     ad7:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     ade:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # ae5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa15>	ae1: R_X86_64_PC32	g_ee_main_mem-0x4
     ae5:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # aec <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa1c>	ae8: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0xc
     aec:	89 c2                	mov    %eax,%edx
     aee:	49 8d 7c 11 68       	lea    0x68(%r9,%rdx,1),%rdi
     af3:	8b 17                	mov    (%rdi),%edx
     af5:	81 e2 80 00 00 00    	and    $0x80,%edx
     afb:	89 d3                	mov    %edx,%ebx
     afd:	49 89 5e 30          	mov    %rbx,0x30(%r14)
     b01:	48 63 09             	movslq (%rcx),%rcx
     b04:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
     b0b:	0f 84 ff 03 00 00    	je     f10 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe40>
     b11:	e8 ea f4 ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
     b16:	89 c3                	mov    %eax,%ebx
     b18:	84 c0                	test   %al,%al
     b1a:	0f 84 d1 01 00 00    	je     cf1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>
     b20:	8b 15 00 00 00 00    	mov    0x0(%rip),%edx        # b26 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa56>	b22: R_X86_64_PC32	.bss+0x11c
     b26:	81 fa 9f 86 01 00    	cmp    $0x1869f,%edx
     b2c:	0f 8f d6 0b 00 00    	jg     1708 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1638>
     b32:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # b39 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa69>	b35: R_X86_64_PC32	g_ee_main_mem-0x4
     b39:	41 8b 8e 50 01 00 00 	mov    0x150(%r14),%ecx
     b40:	83 c2 01             	add    $0x1,%edx
     b43:	41 8b be 40 01 00 00 	mov    0x140(%r14),%edi
     b4a:	89 15 00 00 00 00    	mov    %edx,0x0(%rip)        # b50 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xa80>	b4c: R_X86_64_PC32	.bss+0x11c
     b50:	44 8b 64 08 6c       	mov    0x6c(%rax,%rcx,1),%r12d
     b55:	89 8d 9c fe ff ff    	mov    %ecx,-0x164(%rbp)
     b5b:	c5 f9 6e 4c 08 08    	vmovd  0x8(%rax,%rcx,1),%xmm1
     b61:	c5 79 6e 44 08 0c    	vmovd  0xc(%rax,%rcx,1),%xmm8
     b67:	45 8d 5c 24 ef       	lea    -0x11(%r12),%r11d
     b6c:	4c 8b 44 08 10       	mov    0x10(%rax,%rcx,1),%r8
     b71:	4c 8b 54 08 18       	mov    0x18(%rax,%rcx,1),%r10
     b76:	4c 8b 4c 08 50       	mov    0x50(%rax,%rcx,1),%r9
     b7b:	48 8b 54 08 58       	mov    0x58(%rax,%rcx,1),%rdx
     b80:	4c 8b 6c 38 08       	mov    0x8(%rax,%rdi,1),%r13
     b85:	48 8b 0c 38          	mov    (%rax,%rdi,1),%rcx
     b89:	48 8b 74 38 20       	mov    0x20(%rax,%rdi,1),%rsi
     b8e:	48 8b 7c 38 28       	mov    0x28(%rax,%rdi,1),%rdi
     b93:	41 81 fb e2 ff ff 07 	cmp    $0x7ffffe2,%r11d
     b9a:	0f 86 cb 0c 00 00    	jbe    186b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x179b>
     ba0:	c4 41 31 57 c9       	vxorpd %xmm9,%xmm9,%xmm9
     ba5:	c5 79 29 ca          	vmovapd %xmm9,%xmm2
     ba9:	c4 41 79 28 d1       	vmovapd %xmm9,%xmm10
     bae:	4c 8b 1d 00 00 00 00 	mov    0x0(%rip),%r11        # bb5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xae5>	bb1: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
     bb5:	c5 d0 57 ed          	vxorps %xmm5,%xmm5,%xmm5
     bb9:	45 8b 1b             	mov    (%r11),%r11d
     bbc:	45 8d 7b ef          	lea    -0x11(%r11),%r15d
     bc0:	41 81 ff e6 ff ff 07 	cmp    $0x7ffffe6,%r15d
     bc7:	77 07                	ja     bd0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb00>
     bc9:	c4 a1 7a 10 6c 18 04 	vmovss 0x4(%rax,%r11,1),%xmm5
     bd0:	48 83 ec 60          	sub    $0x60,%rsp
     bd4:	c4 c1 79 6e f1       	vmovd  %r9d,%xmm6
     bd9:	c4 e1 f9 6e c7       	vmovq  %rdi,%xmm0
     bde:	c4 41 3a 5a c0       	vcvtss2sd %xmm8,%xmm8,%xmm8
     be3:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
     be8:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     bec:	c5 fb 11 44 24 58    	vmovsd %xmm0,0x58(%rsp)
     bf2:	c5 f9 6e c7          	vmovd  %edi,%xmm0
     bf6:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     bfa:	c5 fb 11 44 24 50    	vmovsd %xmm0,0x50(%rsp)
     c00:	c4 e1 f9 6e c6       	vmovq  %rsi,%xmm0
     c05:	c4 c1 f9 6e e1       	vmovq  %r9,%xmm4
     c0a:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
     c0f:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     c13:	c4 41 79 6e d8       	vmovd  %r8d,%xmm11
     c18:	c5 ca 5a f6          	vcvtss2sd %xmm6,%xmm6,%xmm6
     c1c:	c5 fb 11 44 24 48    	vmovsd %xmm0,0x48(%rsp)
     c22:	c5 f9 6e c6          	vmovd  %esi,%xmm0
     c26:	c4 c1 f9 6e d8       	vmovq  %r8,%xmm3
     c2b:	8b b5 9c fe ff ff    	mov    -0x164(%rbp),%esi
     c31:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     c35:	c5 fb 11 44 24 40    	vmovsd %xmm0,0x40(%rsp)
     c3b:	c4 c1 79 6e c5       	vmovd  %r13d,%xmm0
     c40:	bf 00 00 00 00       	mov    $0x0,%edi	c41: R_X86_64_32	.rodata.str1.8+0x268
     c45:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     c49:	c5 fb 11 44 24 38    	vmovsd %xmm0,0x38(%rsp)
     c4f:	c5 d2 5a ed          	vcvtss2sd %xmm5,%xmm5,%xmm5
     c53:	c4 e1 f9 6e c1       	vmovq  %rcx,%xmm0
     c58:	c5 fb 11 54 24 18    	vmovsd %xmm2,0x18(%rsp)
     c5e:	c5 f8 c6 c0 55       	vshufps $0x55,%xmm0,%xmm0,%xmm0
     c63:	c4 e1 f9 6e d2       	vmovq  %rdx,%xmm2
     c68:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     c6c:	c5 fb 11 44 24 30    	vmovsd %xmm0,0x30(%rsp)
     c72:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
     c76:	c5 e8 c6 d2 55       	vshufps $0x55,%xmm2,%xmm2,%xmm2
     c7b:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
     c80:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     c84:	c5 fb 11 44 24 28    	vmovsd %xmm0,0x28(%rsp)
     c8a:	c5 ea 5a c2          	vcvtss2sd %xmm2,%xmm2,%xmm0
     c8e:	c5 f9 6f fc          	vmovdqa %xmm4,%xmm7
     c92:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
     c98:	c5 f9 6e c2          	vmovd  %edx,%xmm0
     c9c:	c4 c1 79 6e e2       	vmovd  %r10d,%xmm4
     ca1:	44 89 e2             	mov    %r12d,%edx
     ca4:	c5 7b 11 54 24 20    	vmovsd %xmm10,0x20(%rsp)
     caa:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
     cae:	b8 08 00 00 00       	mov    $0x8,%eax
     cb3:	c5 e0 c6 db 55       	vshufps $0x55,%xmm3,%xmm3,%xmm3
     cb8:	c5 c2 5a ff          	vcvtss2sd %xmm7,%xmm7,%xmm7
     cbc:	c5 da 5a e4          	vcvtss2sd %xmm4,%xmm4,%xmm4
     cc0:	c5 e2 5a db          	vcvtss2sd %xmm3,%xmm3,%xmm3
     cc4:	c4 c1 22 5a d3       	vcvtss2sd %xmm11,%xmm11,%xmm2
     cc9:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
     cce:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
     cd2:	c5 f2 5a c9          	vcvtss2sd %xmm1,%xmm1,%xmm1
     cd6:	c5 7b 11 4c 24 10    	vmovsd %xmm9,0x10(%rsp)
     cdc:	e8 00 00 00 00       	call   ce1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc11>	cdd: R_X86_64_PLT32	printf-0x4
     ce1:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # ce8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc18>	ce4: R_X86_64_PC32	stdout-0x4
     ce8:	48 83 c4 60          	add    $0x60,%rsp
     cec:	e8 00 00 00 00       	call   cf1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>	ced: R_X86_64_PLT32	fflush-0x4
     cf1:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
     cf8:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # cff <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc2f>	cfb: R_X86_64_PC32	g_ee_main_mem-0x4
     cff:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
     d08:	48 83 e8 60          	sub    $0x60,%rax
     d0c:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
     d13:	83 e0 f0             	and    $0xfffffff0,%eax
     d16:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     d1c:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     d23:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
     d2c:	83 c0 10             	add    $0x10,%eax
     d2f:	83 e0 f0             	and    $0xfffffff0,%eax
     d32:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     d38:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     d3f:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
     d48:	83 c0 20             	add    $0x20,%eax
     d4b:	83 e0 f0             	and    $0xfffffff0,%eax
     d4e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     d54:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     d5b:	c4 c1 79 6f 86 10 01 00 00 	vmovdqa 0x110(%r14),%xmm0
     d64:	83 c0 30             	add    $0x30,%eax
     d67:	83 e0 f0             	and    $0xfffffff0,%eax
     d6a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     d70:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     d77:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
     d80:	83 c0 40             	add    $0x40,%eax
     d83:	83 e0 f0             	and    $0xfffffff0,%eax
     d86:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     d8c:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
     d93:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
     d9c:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
     da3:	49 89 46 40          	mov    %rax,0x40(%r14)
     da7:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
     dae:	49 89 46 50          	mov    %rax,0x50(%r14)
     db2:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
     db9:	49 89 46 60          	mov    %rax,0x60(%r14)
     dbd:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
     dc4:	83 c0 50             	add    $0x50,%eax
     dc7:	83 e0 f0             	and    $0xfffffff0,%eax
     dca:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
     dd0:	c4 c1 7a 7e 66 60    	vmovq  0x60(%r14),%xmm4
     dd6:	c4 c1 7a 7e ae a0 00 00 00 	vmovq  0xa0(%r14),%xmm5
     ddf:	c4 c1 7a 7e 96 80 00 00 00 	vmovq  0x80(%r14),%xmm2
     de8:	c4 c3 d1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm5,%xmm1
     df2:	c4 c3 e9 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm2,%xmm0
     dfc:	c4 c3 d9 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm4,%xmm2
     e03:	c4 c1 7a 7e 6e 40    	vmovq  0x40(%r14),%xmm5
     e09:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
     e0f:	c4 c3 d1 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm5,%xmm1
     e16:	c5 fd 7f 85 70 ff ff ff 	vmovdqa %ymm0,-0x90(%rbp)
     e1e:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
     e24:	c5 fd 7f 8d 50 ff ff ff 	vmovdqa %ymm1,-0xb0(%rbp)
     e2c:	85 ff                	test   %edi,%edi
     e2e:	0f 84 bc 0a 00 00    	je     18f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
     e34:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
     e3b:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
     e42:	4c 01 cf             	add    %r9,%rdi
     e45:	31 d2                	xor    %edx,%edx
     e47:	48 8d b5 50 ff ff ff 	lea    -0xb0(%rbp),%rsi
     e4e:	c5 f8 77             	vzeroupper
     e51:	e8 00 00 00 00       	call   e56 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd86>	e52: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     e56:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
     e5d:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # e64 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd94>	e60: R_X86_64_PC32	g_ee_main_mem-0x4
     e64:	49 89 46 20          	mov    %rax,0x20(%r14)
     e68:	48 89 d0             	mov    %rdx,%rax
     e6b:	8d 4a 10             	lea    0x10(%rdx),%ecx
     e6e:	83 e0 f0             	and    $0xfffffff0,%eax
     e71:	83 e1 f0             	and    $0xfffffff0,%ecx
     e74:	c4 c1 7a 6f 04 01    	vmovdqu (%r9,%rax,1),%xmm0
     e7a:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
     e83:	49 8b 04 09          	mov    (%r9,%rcx,1),%rax
     e87:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
     e8c:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
     e93:	8d 4a 20             	lea    0x20(%rdx),%ecx
     e96:	83 e1 f0             	and    $0xfffffff0,%ecx
     e99:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
     ea0:	49 8b 34 09          	mov    (%r9,%rcx,1),%rsi
     ea4:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
     ea9:	49 89 8e 48 01 00 00 	mov    %rcx,0x148(%r14)
     eb0:	8d 4a 30             	lea    0x30(%rdx),%ecx
     eb3:	83 e1 f0             	and    $0xfffffff0,%ecx
     eb6:	49 89 b6 40 01 00 00 	mov    %rsi,0x140(%r14)
     ebd:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     ec3:	8d 4a 40             	lea    0x40(%rdx),%ecx
     ec6:	83 e1 f0             	and    $0xfffffff0,%ecx
     ec9:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
     ed2:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     ed8:	8d 4a 50             	lea    0x50(%rdx),%ecx
     edb:	48 83 c2 60          	add    $0x60,%rdx
     edf:	83 e1 f0             	and    $0xfffffff0,%ecx
     ee2:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
     eeb:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
     ef1:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
     ef8:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
     f01:	84 db                	test   %bl,%bl
     f03:	0f 85 4f 08 00 00    	jne    1758 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1688>
     f09:	89 c2                	mov    %eax,%edx
     f0b:	49 8d 7c 11 68       	lea    0x68(%r9,%rdx,1),%rdi
     f10:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
     f17:	8d 4a 20             	lea    0x20(%rdx),%ecx
     f1a:	83 e1 f0             	and    $0xfffffff0,%ecx
     f1d:	4d 8b 04 09          	mov    (%r9,%rcx,1),%r8
     f21:	49 8b 74 09 08       	mov    0x8(%r9,%rcx,1),%rsi
     f26:	4d 89 46 30          	mov    %r8,0x30(%r14)
     f2a:	49 89 76 38          	mov    %rsi,0x38(%r14)
     f2e:	48 63 3f             	movslq (%rdi),%rdi
     f31:	49 89 7e 40          	mov    %rdi,0x40(%r14)
     f35:	48 89 f9             	mov    %rdi,%rcx
     f38:	83 e7 04             	and    $0x4,%edi
     f3b:	89 fb                	mov    %edi,%ebx
     f3d:	49 89 5e 50          	mov    %rbx,0x50(%r14)
     f41:	f6 c1 02             	test   $0x2,%cl
     f44:	74 3e                	je     f84 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xeb4>
     f46:	49 89 f2             	mov    %rsi,%r10
     f49:	41 c7 86 c0 00 00 00 00 00 00 00 	movl   $0x0,0xc0(%r14)
     f54:	49 c1 ea 20          	shr    $0x20,%r10
     f58:	41 89 b6 c4 00 00 00 	mov    %esi,0xc4(%r14)
     f5f:	41 c7 86 c8 00 00 00 00 00 00 00 	movl   $0x0,0xc8(%r14)
     f6a:	45 89 96 cc 00 00 00 	mov    %r10d,0xcc(%r14)
     f71:	4d 85 c0             	test   %r8,%r8
     f74:	75 0e                	jne    f84 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xeb4>
     f76:	49 83 be c0 00 00 00 00 	cmpq   $0x0,0xc0(%r14)
     f7e:	0f 84 ac 00 00 00    	je     1030 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
     f84:	83 e1 01             	and    $0x1,%ecx
     f87:	89 cb                	mov    %ecx,%ebx
     f89:	49 89 5e 40          	mov    %rbx,0x40(%r14)
     f8d:	85 ff                	test   %edi,%edi
     f8f:	74 35                	je     fc6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xef6>
     f91:	49 c7 86 c8 00 00 00 00 00 00 00 	movq   $0x0,0xc8(%r14)
     f9c:	48 89 f7             	mov    %rsi,%rdi
     f9f:	48 c1 ef 20          	shr    $0x20,%rdi
     fa3:	41 89 b6 c8 00 00 00 	mov    %esi,0xc8(%r14)
     faa:	41 c7 86 c0 00 00 00 00 00 00 00 	movl   $0x0,0xc0(%r14)
     fb5:	41 89 be c4 00 00 00 	mov    %edi,0xc4(%r14)
     fbc:	49 83 be c0 00 00 00 00 	cmpq   $0x0,0xc0(%r14)
     fc4:	7e 6a                	jle    1030 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
     fc6:	85 c9                	test   %ecx,%ecx
     fc8:	0f 84 12 f3 ff ff    	je     2e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
     fce:	c4 c1 78 28 86 90 02 00 00 	vmovaps 0x290(%r14),%xmm0
     fd7:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     fdd:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
     fe4:	c4 c1 78 28 86 a0 02 00 00 	vmovaps 0x2a0(%r14),%xmm0
     fed:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
     ff5:	49 8b 4e 30          	mov    0x30(%r14),%rcx
     ff9:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
     fff:	48 85 c9             	test   %rcx,%rcx
    1002:	78 2c                	js     1030 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
    1004:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
    100c:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
    1013:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
    101a:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
    1022:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
    1027:	0f 89 b3 f2 ff ff    	jns    2e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    102d:	0f 1f 00             	nopl   (%rax)
    1030:	48 8b 0d 00 00 00 00 	mov    0x0(%rip),%rcx        # 1037 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf67>	1033: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x4
    1037:	49 63 b6 f0 01 00 00 	movslq 0x1f0(%r14),%rsi
    103e:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
    1047:	c4 c1 7a 7e a6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm4
    1050:	c4 c3 d9 22 96 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm4,%xmm2
    105a:	48 63 09             	movslq (%rcx),%rcx
    105d:	49 89 46 60          	mov    %rax,0x60(%r14)
    1061:	c4 c1 7a 7e a6 80 00 00 00 	vmovq  0x80(%r14),%xmm4
    106a:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
    1070:	c4 c3 d9 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm4,%xmm1
    107a:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
    107f:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
    1086:	48 89 cf             	mov    %rcx,%rdi
    1089:	49 8b 8e 10 01 00 00 	mov    0x110(%r14),%rcx
    1090:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
    1096:	c4 e3 d9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm4,%xmm2
    109c:	49 89 56 70          	mov    %rdx,0x70(%r14)
    10a0:	c4 e3 f9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm0,%xmm0
    10a6:	49 89 4e 50          	mov    %rcx,0x50(%r14)
    10aa:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
    10b0:	49 89 76 20          	mov    %rsi,0x20(%r14)
    10b4:	c5 fd 7f 45 90       	vmovdqa %ymm0,-0x70(%rbp)
    10b9:	c5 fd 7f 4d b0       	vmovdqa %ymm1,-0x50(%rbp)
    10be:	85 ff                	test   %edi,%edi
    10c0:	0f 84 2a 08 00 00    	je     18f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>
    10c6:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    10cd:	89 ff                	mov    %edi,%edi
    10cf:	31 d2                	xor    %edx,%edx
    10d1:	48 8d 75 90          	lea    -0x70(%rbp),%rsi
    10d5:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    10dc:	4c 01 cf             	add    %r9,%rdi
    10df:	c5 f8 77             	vzeroupper
    10e2:	e8 00 00 00 00       	call   10e7 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1017>	10e3: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    10e7:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    10ee:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 10f5 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1025>	10f1: R_X86_64_PC32	g_ee_main_mem-0x4
    10f5:	49 89 46 20          	mov    %rax,0x20(%r14)
    10f9:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    1100:	e9 db f1 ff ff       	jmp    2e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    1105:	0f 1f 00             	nopl   (%rax)
    1108:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    110f:	e9 cc f1 ff ff       	jmp    2e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x210>
    1114:	0f 1f 40 00          	nopl   0x0(%rax)
    1118:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
    111f:	e9 0c ff ff ff       	jmp    1030 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf60>
    1124:	0f 1f 40 00          	nopl   0x0(%rax)
    1128:	49 89 56 30          	mov    %rdx,0x30(%r14)
    112c:	e9 45 f2 ff ff       	jmp    376 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2a6>
    1131:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    1138:	c4 41 79 6e d2       	vmovd  %r10d,%xmm10
    113d:	4c 89 d2             	mov    %r10,%rdx
    1140:	4d 8b 5e 38          	mov    0x38(%r14),%r11
    1144:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
    1148:	c5 7a 10 0d 00 00 00 00 	vmovss 0x0(%rip),%xmm9        # 1150 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1080>	114c: R_X86_64_PC32	.LC11-0x4
    1150:	c5 ca 59 db          	vmulss %xmm3,%xmm6,%xmm3
    1154:	c5 fa 10 05 00 00 00 00 	vmovss 0x0(%rip),%xmm0        # 115c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x108c>	1158: R_X86_64_PC32	.LC11-0x4
    115c:	48 c1 ea 20          	shr    $0x20,%rdx
    1160:	c4 c1 4a 59 f5       	vmulss %xmm13,%xmm6,%xmm6
    1165:	c4 41 32 5c ca       	vsubss %xmm10,%xmm9,%xmm9
    116a:	c4 41 1a 59 d2       	vmulss %xmm10,%xmm12,%xmm10
    116f:	c4 41 32 59 cc       	vmulss %xmm12,%xmm9,%xmm9
    1174:	c5 e2 58 df          	vaddss %xmm7,%xmm3,%xmm3
    1178:	c5 f9 6e f9          	vmovd  %ecx,%xmm7
    117c:	c5 ca 58 f7          	vaddss %xmm7,%xmm6,%xmm6
    1180:	c4 41 7a 5c c9       	vsubss %xmm9,%xmm0,%xmm9
    1185:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    1189:	c5 9a 59 c0          	vmulss %xmm0,%xmm12,%xmm0
    118d:	c4 c1 6a 59 d1       	vmulss %xmm9,%xmm2,%xmm2
    1192:	c4 c1 7a 12 f9       	vmovsldup %xmm9,%xmm7
    1197:	c4 c1 62 59 d9       	vmulss %xmm9,%xmm3,%xmm3
    119c:	c4 c1 4a 59 f1       	vmulss %xmm9,%xmm6,%xmm6
    11a1:	c5 f9 7e c2          	vmovd  %xmm0,%edx
    11a5:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
    11aa:	c5 1a 59 e0          	vmulss %xmm0,%xmm12,%xmm12
    11ae:	c5 fa 7e ff          	vmovq  %xmm7,%xmm7
    11b2:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    11b6:	c5 c0 59 c9          	vmulps %xmm1,%xmm7,%xmm1
    11ba:	c5 28 14 d0          	vunpcklps %xmm0,%xmm10,%xmm10
    11be:	c4 c1 7a 11 96 c8 02 00 00 	vmovss %xmm2,0x2c8(%r14)
    11c7:	c4 41 18 14 e1       	vunpcklps %xmm9,%xmm12,%xmm12
    11cc:	c4 c1 78 13 8e c0 02 00 00 	vmovlps %xmm1,0x2c0(%r14)
    11d5:	c4 41 28 16 d4       	vmovlhps %xmm12,%xmm10,%xmm10
    11da:	c4 41 78 29 96 00 03 00 00 	vmovaps %xmm10,0x300(%r14)
    11e3:	e9 55 f6 ff ff       	jmp    83d <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x76d>
    11e8:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
    11f0:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
    11f7:	49 89 46 20          	mov    %rax,0x20(%r14)
    11fb:	89 d1                	mov    %edx,%ecx
    11fd:	49 8b 0c 09          	mov    (%r9,%rcx,1),%rcx
    1201:	49 89 8e f0 01 00 00 	mov    %rcx,0x1f0(%r14)
    1208:	8d 4a 70             	lea    0x70(%rdx),%ecx
    120b:	83 e1 f0             	and    $0xfffffff0,%ecx
    120e:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1214:	8d 4a 60             	lea    0x60(%rdx),%ecx
    1217:	83 e1 f0             	and    $0xfffffff0,%ecx
    121a:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    1223:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1229:	8d 4a 50             	lea    0x50(%rdx),%ecx
    122c:	83 e1 f0             	and    $0xfffffff0,%ecx
    122f:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
    1238:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    123e:	8d 4a 40             	lea    0x40(%rdx),%ecx
    1241:	83 e1 f0             	and    $0xfffffff0,%ecx
    1244:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
    124d:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1253:	8d 4a 30             	lea    0x30(%rdx),%ecx
    1256:	83 e1 f0             	and    $0xfffffff0,%ecx
    1259:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    1262:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1268:	8d 4a 20             	lea    0x20(%rdx),%ecx
    126b:	83 e1 f0             	and    $0xfffffff0,%ecx
    126e:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    1277:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    127d:	8d 4a 10             	lea    0x10(%rdx),%ecx
    1280:	48 83 ea 80          	sub    $0xffffffffffffff80,%rdx
    1284:	83 e1 f0             	and    $0xfffffff0,%ecx
    1287:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    1290:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1296:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    129d:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
    12a6:	48 8d 65 d0          	lea    -0x30(%rbp),%rsp
    12aa:	5b                   	pop    %rbx
    12ab:	41 5a                	pop    %r10
    12ad:	41 5c                	pop    %r12
    12af:	41 5d                	pop    %r13
    12b1:	41 5e                	pop    %r14
    12b3:	41 5f                	pop    %r15
    12b5:	5d                   	pop    %rbp
    12b6:	49 8d 62 f8          	lea    -0x8(%r10),%rsp
    12ba:	c3                   	ret
    12bb:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    12c0:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
    12c9:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
    12d0:	48 8d 50 a0          	lea    -0x60(%rax),%rdx
    12d4:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 12db <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x120b>	12d7: R_X86_64_PC32	g_ee_main_mem-0x4
    12db:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    12e2:	83 e2 f0             	and    $0xfffffff0,%edx
    12e5:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    12ea:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    12f1:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
    12fa:	8d 53 10             	lea    0x10(%rbx),%edx
    12fd:	83 e2 f0             	and    $0xfffffff0,%edx
    1300:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    1305:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    130c:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
    1315:	8d 53 20             	lea    0x20(%rbx),%edx
    1318:	83 e2 f0             	and    $0xfffffff0,%edx
    131b:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    1320:	49 8b be 10 01 00 00 	mov    0x110(%r14),%rdi
    1327:	49 8b b6 18 01 00 00 	mov    0x118(%r14),%rsi
    132e:	48 89 bd b0 fe ff ff 	mov    %rdi,-0x150(%rbp)
    1335:	41 8b be d0 01 00 00 	mov    0x1d0(%r14),%edi
    133c:	48 8b 9d b0 fe ff ff 	mov    -0x150(%rbp),%rbx
    1343:	48 89 b5 b8 fe ff ff 	mov    %rsi,-0x148(%rbp)
    134a:	8d 57 30             	lea    0x30(%rdi),%edx
    134d:	83 e2 f0             	and    $0xfffffff0,%edx
    1350:	48 89 9d b0 fe ff ff 	mov    %rbx,-0x150(%rbp)
    1357:	48 89 1c 10          	mov    %rbx,(%rax,%rdx,1)
    135b:	48 89 74 10 08       	mov    %rsi,0x8(%rax,%rdx,1)
    1360:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
    1367:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
    1370:	8d 53 40             	lea    0x40(%rbx),%edx
    1373:	83 e2 f0             	and    $0xfffffff0,%edx
    1376:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    137b:	49 8b be 20 01 00 00 	mov    0x120(%r14),%rdi
    1382:	49 8b b6 28 01 00 00 	mov    0x128(%r14),%rsi
    1389:	48 89 bd a0 fe ff ff 	mov    %rdi,-0x160(%rbp)
    1390:	41 8b be d0 01 00 00 	mov    0x1d0(%r14),%edi
    1397:	48 8b 9d a0 fe ff ff 	mov    -0x160(%rbp),%rbx
    139e:	48 89 b5 a8 fe ff ff 	mov    %rsi,-0x158(%rbp)
    13a5:	8d 57 50             	lea    0x50(%rdi),%edx
    13a8:	83 e2 f0             	and    $0xfffffff0,%edx
    13ab:	48 89 9d a0 fe ff ff 	mov    %rbx,-0x160(%rbp)
    13b2:	48 89 1c 10          	mov    %rbx,(%rax,%rdx,1)
    13b6:	48 89 74 10 08       	mov    %rsi,0x8(%rax,%rdx,1)
    13bb:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
    13c2:	49 89 46 40          	mov    %rax,0x40(%r14)
    13c6:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
    13cd:	49 89 46 70          	mov    %rax,0x70(%r14)
    13d1:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    13d8:	49 89 46 60          	mov    %rax,0x60(%r14)
    13dc:	e8 1f ec ff ff       	call   0 <Mips2C::jak1::geco_spart_dump_armed()>
    13e1:	89 c3                	mov    %eax,%ebx
    13e3:	84 c0                	test   %al,%al
    13e5:	74 13                	je     13fa <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x132a>
    13e7:	8b 05 00 00 00 00    	mov    0x0(%rip),%eax        # 13ed <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x131d>	13e9: R_X86_64_PC32	.bss+0x124
    13ed:	3d 3f 1f 00 00       	cmp    $0x1f3f,%eax
    13f2:	0f 8e f1 03 00 00    	jle    17e9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1719>
    13f8:	31 db                	xor    %ebx,%ebx
    13fa:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1401 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1331>	13fd: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x14
    1401:	48 63 10             	movslq (%rax),%rdx
    1404:	49 89 96 90 01 00 00 	mov    %rdx,0x190(%r14)
    140b:	48 89 d0             	mov    %rdx,%rax
    140e:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
    1415:	49 89 56 20          	mov    %rdx,0x20(%r14)
    1419:	49 8b 56 40          	mov    0x40(%r14),%rdx
    141d:	48 89 95 10 ff ff ff 	mov    %rdx,-0xf0(%rbp)
    1424:	49 8b 56 50          	mov    0x50(%r14),%rdx
    1428:	48 89 95 18 ff ff ff 	mov    %rdx,-0xe8(%rbp)
    142f:	49 8b 56 60          	mov    0x60(%r14),%rdx
    1433:	48 89 95 20 ff ff ff 	mov    %rdx,-0xe0(%rbp)
    143a:	49 8b 56 70          	mov    0x70(%r14),%rdx
    143e:	48 89 95 28 ff ff ff 	mov    %rdx,-0xd8(%rbp)
    1445:	49 8b 96 80 00 00 00 	mov    0x80(%r14),%rdx
    144c:	48 89 95 30 ff ff ff 	mov    %rdx,-0xd0(%rbp)
    1453:	49 8b 96 90 00 00 00 	mov    0x90(%r14),%rdx
    145a:	48 89 95 38 ff ff ff 	mov    %rdx,-0xc8(%rbp)
    1461:	49 8b 96 a0 00 00 00 	mov    0xa0(%r14),%rdx
    1468:	48 89 95 40 ff ff ff 	mov    %rdx,-0xc0(%rbp)
    146f:	49 8b 96 b0 00 00 00 	mov    0xb0(%r14),%rdx
    1476:	48 89 95 48 ff ff ff 	mov    %rdx,-0xb8(%rbp)
    147d:	85 c0                	test   %eax,%eax
    147f:	0f 84 6e 04 00 00    	je     18f3 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1823>
    1485:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 148c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13bc>	1488: R_X86_64_PC32	g_ee_main_mem-0x4
    148c:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
    1493:	89 c0                	mov    %eax,%eax
    1495:	48 8d b5 10 ff ff ff 	lea    -0xf0(%rbp),%rsi
    149c:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
    14a3:	31 d2                	xor    %edx,%edx
    14a5:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
    14a9:	e8 00 00 00 00       	call   14ae <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13de>	14aa: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    14ae:	49 8b 96 d0 01 00 00 	mov    0x1d0(%r14),%rdx
    14b5:	49 89 46 20          	mov    %rax,0x20(%r14)
    14b9:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 14c0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x13f0>	14bc: R_X86_64_PC32	g_ee_main_mem-0x4
    14c0:	48 89 d1             	mov    %rdx,%rcx
    14c3:	83 e1 f0             	and    $0xfffffff0,%ecx
    14c6:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    14cb:	8d 4a 10             	lea    0x10(%rdx),%ecx
    14ce:	83 e1 f0             	and    $0xfffffff0,%ecx
    14d1:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
    14da:	48 8b 3c 08          	mov    (%rax,%rcx,1),%rdi
    14de:	48 8b 4c 08 08       	mov    0x8(%rax,%rcx,1),%rcx
    14e3:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
    14ea:	8d 4a 20             	lea    0x20(%rdx),%ecx
    14ed:	83 e1 f0             	and    $0xfffffff0,%ecx
    14f0:	49 89 be 50 01 00 00 	mov    %rdi,0x150(%r14)
    14f7:	48 8b 34 08          	mov    (%rax,%rcx,1),%rsi
    14fb:	48 8b 4c 08 08       	mov    0x8(%rax,%rcx,1),%rcx
    1500:	49 89 8e 48 01 00 00 	mov    %rcx,0x148(%r14)
    1507:	8d 4a 30             	lea    0x30(%rdx),%ecx
    150a:	83 e1 f0             	and    $0xfffffff0,%ecx
    150d:	49 89 b6 40 01 00 00 	mov    %rsi,0x140(%r14)
    1514:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    1519:	8d 4a 40             	lea    0x40(%rdx),%ecx
    151c:	83 e1 f0             	and    $0xfffffff0,%ecx
    151f:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
    1528:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    152d:	8d 4a 50             	lea    0x50(%rdx),%ecx
    1530:	48 83 c2 60          	add    $0x60,%rdx
    1534:	83 e1 f0             	and    $0xfffffff0,%ecx
    1537:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
    1540:	c5 fa 6f 04 08       	vmovdqu (%rax,%rcx,1),%xmm0
    1545:	49 89 96 d0 01 00 00 	mov    %rdx,0x1d0(%r14)
    154c:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
    1555:	84 db                	test   %bl,%bl
    1557:	0f 84 1d f1 ff ff    	je     67a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
    155d:	89 f9                	mov    %edi,%ecx
    155f:	89 ff                	mov    %edi,%edi
    1561:	c4 41 01 57 ff       	vxorpd %xmm15,%xmm15,%xmm15
    1566:	89 f6                	mov    %esi,%esi
    1568:	48 8b 54 38 10       	mov    0x10(%rax,%rdi,1),%rdx
    156d:	48 83 ec 10          	sub    $0x10,%rsp
    1571:	c5 82 5a 04 30       	vcvtss2sd (%rax,%rsi,1),%xmm15,%xmm0
    1576:	c5 79 28 c0          	vmovapd %xmm0,%xmm8
    157a:	c5 82 5a 7c 38 10    	vcvtss2sd 0x10(%rax,%rdi,1),%xmm15,%xmm7
    1580:	c5 82 5a 44 38 18    	vcvtss2sd 0x18(%rax,%rdi,1),%xmm15,%xmm0
    1586:	c5 82 5a 74 30 2c    	vcvtss2sd 0x2c(%rax,%rsi,1),%xmm15,%xmm6
    158c:	c5 82 5a 6c 30 28    	vcvtss2sd 0x28(%rax,%rsi,1),%xmm15,%xmm5
    1592:	48 c1 ea 20          	shr    $0x20,%rdx
    1596:	c5 82 5a 64 30 24    	vcvtss2sd 0x24(%rax,%rsi,1),%xmm15,%xmm4
    159c:	c5 82 5a 5c 30 20    	vcvtss2sd 0x20(%rax,%rsi,1),%xmm15,%xmm3
    15a2:	c5 82 5a 54 30 08    	vcvtss2sd 0x8(%rax,%rsi,1),%xmm15,%xmm2
    15a8:	c5 82 5a 4c 30 04    	vcvtss2sd 0x4(%rax,%rsi,1),%xmm15,%xmm1
    15ae:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
    15b4:	c5 f9 6e c2          	vmovd  %edx,%xmm0
    15b8:	89 ce                	mov    %ecx,%esi
    15ba:	bf 00 00 00 00       	mov    $0x0,%edi	15bb: R_X86_64_32	.rodata.str1.8+0x150
    15bf:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    15c3:	b8 08 00 00 00       	mov    $0x8,%eax
    15c8:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
    15cd:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
    15d1:	e8 00 00 00 00       	call   15d6 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1506>	15d2: R_X86_64_PLT32	printf-0x4
    15d6:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 15dd <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x150d>	15d9: R_X86_64_PC32	stdout-0x4
    15dd:	59                   	pop    %rcx
    15de:	5e                   	pop    %rsi
    15df:	e8 00 00 00 00       	call   15e4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1514>	15e0: R_X86_64_PLT32	fflush-0x4
    15e4:	e9 91 f0 ff ff       	jmp    67a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x5aa>
    15e9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    15f0:	c4 e1 f9 6e f7       	vmovq  %rdi,%xmm6
    15f5:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
    15fa:	c5 f8 2f 35 00 00 00 00 	vcomiss 0x0(%rip),%xmm6        # 1602 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1532>	15fe: R_X86_64_PC32	.LC15-0x4
    1602:	c5 f9 6f ce          	vmovdqa %xmm6,%xmm1
    1606:	0f 86 84 f4 ff ff    	jbe    a90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    160c:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    1610:	c5 f8 2e d0          	vucomiss %xmm0,%xmm2
    1614:	0f 8a 76 f4 ff ff    	jp     a90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    161a:	0f 85 70 f4 ff ff    	jne    a90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c0>
    1620:	4c 8b 5c 10 10       	mov    0x10(%rax,%rdx,1),%r11
    1625:	83 c1 01             	add    $0x1,%ecx
    1628:	48 83 ec 30          	sub    $0x30,%rsp
    162c:	c5 d1 57 ed          	vxorpd %xmm5,%xmm5,%xmm5
    1630:	48 8b 7c 10 08       	mov    0x8(%rax,%rdx,1),%rdi
    1635:	89 0d 00 00 00 00    	mov    %ecx,0x0(%rip)        # 163b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x156b>	1637: R_X86_64_PC32	.bss+0x120
    163b:	c5 d2 5a 44 10 1c    	vcvtss2sd 0x1c(%rax,%rdx,1),%xmm5,%xmm0
    1641:	c4 c1 f9 6e f2       	vmovq  %r10,%xmm6
    1646:	48 8b 0c 10          	mov    (%rax,%rdx,1),%rcx
    164a:	49 c1 e9 20          	shr    $0x20,%r9
    164e:	49 c1 e8 20          	shr    $0x20,%r8
    1652:	c5 fb 11 44 24 20    	vmovsd %xmm0,0x20(%rsp)
    1658:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
    165d:	c4 c1 79 6e d8       	vmovd  %r8d,%xmm3
    1662:	c4 41 3a 5a c0       	vcvtss2sd %xmm8,%xmm8,%xmm8
    1667:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
    166c:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    1670:	c5 f9 6f fe          	vmovdqa %xmm6,%xmm7
    1674:	c5 fb 11 44 24 18    	vmovsd %xmm0,0x18(%rsp)
    167a:	c4 e1 f9 6e e9       	vmovq  %rcx,%xmm5
    167f:	c5 f9 6e c7          	vmovd  %edi,%xmm0
    1683:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
    1688:	c4 c1 79 6e f2       	vmovd  %r10d,%xmm6
    168d:	bf 00 00 00 00       	mov    $0x0,%edi	168e: R_X86_64_32	.rodata.str1.8+0x200
    1692:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    1696:	c5 c2 5a ff          	vcvtss2sd %xmm7,%xmm7,%xmm7
    169a:	c5 ca 5a f6          	vcvtss2sd %xmm6,%xmm6,%xmm6
    169e:	c5 da 5a e4          	vcvtss2sd %xmm4,%xmm4,%xmm4
    16a2:	c5 fb 11 44 24 10    	vmovsd %xmm0,0x10(%rsp)
    16a8:	c5 d2 5a c5          	vcvtss2sd %xmm5,%xmm5,%xmm0
    16ac:	c4 c1 79 6e e9       	vmovd  %r9d,%xmm5
    16b1:	c5 e2 5a db          	vcvtss2sd %xmm3,%xmm3,%xmm3
    16b5:	c5 fb 11 44 24 08    	vmovsd %xmm0,0x8(%rsp)
    16bb:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
    16bf:	c5 d2 5a ed          	vcvtss2sd %xmm5,%xmm5,%xmm5
    16c3:	c5 ea 5a d2          	vcvtss2sd %xmm2,%xmm2,%xmm2
    16c7:	c5 fa 5a c0          	vcvtss2sd %xmm0,%xmm0,%xmm0
    16cb:	b8 08 00 00 00       	mov    $0x8,%eax
    16d0:	c5 fb 11 04 24       	vmovsd %xmm0,(%rsp)
    16d5:	c5 79 29 c0          	vmovapd %xmm8,%xmm0
    16d9:	c5 f2 5a c9          	vcvtss2sd %xmm1,%xmm1,%xmm1
    16dd:	e8 00 00 00 00       	call   16e2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1612>	16de: R_X86_64_PLT32	printf-0x4
    16e2:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 16e9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1619>	16e5: R_X86_64_PC32	stdout-0x4
    16e9:	48 83 c4 30          	add    $0x30,%rsp
    16ed:	e8 00 00 00 00       	call   16f2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1622>	16ee: R_X86_64_PLT32	fflush-0x4
    16f2:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 16f9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1629>	16f5: R_X86_64_PC32	g_ee_main_mem-0x4
    16f9:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
    1700:	e9 ab f3 ff ff       	jmp    ab0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e0>
    1705:	0f 1f 00             	nopl   (%rax)
    1708:	31 db                	xor    %ebx,%ebx
    170a:	e9 e2 f5 ff ff       	jmp    cf1 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc21>
    170f:	90                   	nop
    1710:	83 c2 01             	add    $0x1,%edx
    1713:	41 8b 4c 01 74       	mov    0x74(%r9,%rax,1),%ecx
    1718:	45 8b 44 01 78       	mov    0x78(%r9,%rax,1),%r8d
    171d:	bf 00 00 00 00       	mov    $0x0,%edi	171e: R_X86_64_32	.rodata.str1.8+0xd8
    1722:	89 15 00 00 00 00    	mov    %edx,0x0(%rip)        # 1728 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1658>	1724: R_X86_64_PC32	.bss+0x128
    1728:	41 8b 54 01 70       	mov    0x70(%r9,%rax,1),%edx
    172d:	31 c0                	xor    %eax,%eax
    172f:	e8 00 00 00 00       	call   1734 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1664>	1730: R_X86_64_PLT32	printf-0x4
    1734:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 173b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x166b>	1737: R_X86_64_PC32	stdout-0x4
    173b:	e8 00 00 00 00       	call   1740 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1670>	173c: R_X86_64_PLT32	fflush-0x4
    1740:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
    1747:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 174e <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x167e>	174a: R_X86_64_PC32	g_ee_main_mem-0x4
    174e:	e9 ed ee ff ff       	jmp    640 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
    1753:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    1758:	c4 41 09 57 f6       	vxorpd %xmm14,%xmm14,%xmm14
    175d:	48 83 ec 10          	sub    $0x10,%rsp
    1761:	89 c2                	mov    %eax,%edx
    1763:	89 f6                	mov    %esi,%esi
    1765:	89 c0                	mov    %eax,%eax
    1767:	c4 c1 0a 5a 7c 31 04 	vcvtss2sd 0x4(%r9,%rsi,1),%xmm14,%xmm7
    176e:	c4 c1 0a 5a 34 31    	vcvtss2sd (%r9,%rsi,1),%xmm14,%xmm6
    1774:	c4 41 0a 5a 44 31 08 	vcvtss2sd 0x8(%r9,%rsi,1),%xmm14,%xmm8
    177b:	c4 c1 0a 5a 6c 01 5c 	vcvtss2sd 0x5c(%r9,%rax,1),%xmm14,%xmm5
    1782:	c4 c1 0a 5a 64 01 58 	vcvtss2sd 0x58(%r9,%rax,1),%xmm14,%xmm4
    1789:	89 d6                	mov    %edx,%esi
    178b:	c4 c1 0a 5a 5c 01 54 	vcvtss2sd 0x54(%r9,%rax,1),%xmm14,%xmm3
    1792:	c4 c1 0a 5a 54 01 50 	vcvtss2sd 0x50(%r9,%rax,1),%xmm14,%xmm2
    1799:	c4 c1 0a 5a 4c 01 08 	vcvtss2sd 0x8(%r9,%rax,1),%xmm14,%xmm1
    17a0:	bf 00 00 00 00       	mov    $0x0,%edi	17a1: R_X86_64_32	.rodata.str1.8+0x2e8
    17a5:	c4 c1 0a 5a 44 01 0c 	vcvtss2sd 0xc(%r9,%rax,1),%xmm14,%xmm0
    17ac:	c5 7b 11 04 24       	vmovsd %xmm8,(%rsp)
    17b1:	b8 08 00 00 00       	mov    $0x8,%eax
    17b6:	e8 00 00 00 00       	call   17bb <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16eb>	17b7: R_X86_64_PLT32	printf-0x4
    17bb:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 17c2 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16f2>	17be: R_X86_64_PC32	stdout-0x4
    17c2:	58                   	pop    %rax
    17c3:	5a                   	pop    %rdx
    17c4:	e8 00 00 00 00       	call   17c9 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x16f9>	17c5: R_X86_64_PLT32	fflush-0x4
    17c9:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
    17d0:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 17d7 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1707>	17d3: R_X86_64_PC32	g_ee_main_mem-0x4
    17d7:	e9 2d f7 ff ff       	jmp    f09 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe39>
    17dc:	48 c1 ef 20          	shr    $0x20,%rdi
    17e0:	c5 f9 6e cf          	vmovd  %edi,%xmm1
    17e4:	e9 37 fe ff ff       	jmp    1620 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1550>
    17e9:	83 c0 01             	add    $0x1,%eax
    17ec:	41 8b 8e 50 01 00 00 	mov    0x150(%r14),%ecx
    17f3:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
    17fa:	c5 d9 57 e4          	vxorpd %xmm4,%xmm4,%xmm4
    17fe:	89 05 00 00 00 00    	mov    %eax,0x0(%rip)        # 1804 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1734>	1800: R_X86_64_PC32	.bss+0x124
    1804:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 180b <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x173b>	1807: R_X86_64_PC32	g_ee_main_mem-0x4
    180b:	c5 f9 28 fc          	vmovapd %xmm4,%xmm7
    180f:	8b 74 08 70          	mov    0x70(%rax,%rcx,1),%esi
    1813:	8b 7c 08 78          	mov    0x78(%rax,%rcx,1),%edi
    1817:	c5 da 5a 04 10       	vcvtss2sd (%rax,%rdx,1),%xmm4,%xmm0
    181c:	c5 da 5a 74 10 2c    	vcvtss2sd 0x2c(%rax,%rdx,1),%xmm4,%xmm6
    1822:	c5 da 5a 6c 10 28    	vcvtss2sd 0x28(%rax,%rdx,1),%xmm4,%xmm5
    1828:	c5 c2 5a 5c 10 20    	vcvtss2sd 0x20(%rax,%rdx,1),%xmm7,%xmm3
    182e:	c5 da 5a 64 10 24    	vcvtss2sd 0x24(%rax,%rdx,1),%xmm4,%xmm4
    1834:	c5 c2 5a 54 10 08    	vcvtss2sd 0x8(%rax,%rdx,1),%xmm7,%xmm2
    183a:	c5 c2 5a 4c 10 04    	vcvtss2sd 0x4(%rax,%rdx,1),%xmm7,%xmm1
    1840:	89 f2                	mov    %esi,%edx
    1842:	89 f9                	mov    %edi,%ecx
    1844:	41 8b b6 50 01 00 00 	mov    0x150(%r14),%esi
    184b:	bf 00 00 00 00       	mov    $0x0,%edi	184c: R_X86_64_32	.rodata.str1.8+0x100
    1850:	b8 07 00 00 00       	mov    $0x7,%eax
    1855:	e8 00 00 00 00       	call   185a <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x178a>	1856: R_X86_64_PLT32	printf-0x4
    185a:	48 8b 3d 00 00 00 00 	mov    0x0(%rip),%rdi        # 1861 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1791>	185d: R_X86_64_PC32	stdout-0x4
    1861:	e8 00 00 00 00       	call   1866 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1796>	1862: R_X86_64_PLT32	fflush-0x4
    1866:	e9 8f fb ff ff       	jmp    13fa <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x132a>
    186b:	45 89 e3             	mov    %r12d,%r11d
    186e:	c5 e9 57 d2          	vxorpd %xmm2,%xmm2,%xmm2
    1872:	49 01 c3             	add    %rax,%r11
    1875:	4d 8b 3b             	mov    (%r11),%r15
    1878:	45 8b 5b 08          	mov    0x8(%r11),%r11d
    187c:	44 89 9d cc fe ff ff 	mov    %r11d,-0x134(%rbp)
    1883:	4c 89 bd c4 fe ff ff 	mov    %r15,-0x13c(%rbp)
    188a:	c5 ea 5a a5 cc fe ff ff 	vcvtss2sd -0x134(%rbp),%xmm2,%xmm4
    1892:	c5 79 28 d4          	vmovapd %xmm4,%xmm10
    1896:	c5 f9 28 e2          	vmovapd %xmm2,%xmm4
    189a:	c5 5a 5a 8d c4 fe ff ff 	vcvtss2sd -0x13c(%rbp),%xmm4,%xmm9
    18a2:	c5 ea 5a 95 c8 fe ff ff 	vcvtss2sd -0x138(%rbp),%xmm2,%xmm2
    18aa:	e9 ff f2 ff ff       	jmp    bae <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xade>
    18af:	41 b8 00 00 00 00    	mov    $0x0,%r8d	18b1: R_X86_64_32	.rodata.str1.1+0xe
    18b5:	b9 00 00 00 00       	mov    $0x0,%ecx	18b6: R_X86_64_32	.rodata.str1.8
    18ba:	ba 58 01 00 00       	mov    $0x158,%edx
    18bf:	be 00 00 00 00       	mov    $0x0,%esi	18c0: R_X86_64_32	.rodata.str1.8+0x38
    18c4:	bf 00 00 00 00       	mov    $0x0,%edi	18c5: R_X86_64_32	.rodata.str1.8+0x78
    18c9:	e8 00 00 00 00       	call   18ce <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x17fe>	18ca: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    18ce:	41 b8 00 00 00 00    	mov    $0x0,%r8d	18d0: R_X86_64_32	.rodata.str1.1+0xe
    18d4:	b9 00 00 00 00       	mov    $0x0,%ecx	18d5: R_X86_64_32	.rodata.str1.8+0x1a0
    18d9:	ba c0 01 00 00       	mov    $0x1c0,%edx
    18de:	be 00 00 00 00       	mov    $0x0,%esi	18df: R_X86_64_32	.rodata.str1.8+0x38
    18e3:	bf 00 00 00 00       	mov    $0x0,%edi	18e4: R_X86_64_32	.rodata.str1.8+0x1d8
    18e8:	c5 f8 77             	vzeroupper
    18eb:	e8 00 00 00 00       	call   18f0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1820>	18ec: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    18f0:	c5 f8 77             	vzeroupper
    18f3:	41 b8 00 00 00 00    	mov    $0x0,%r8d	18f5: R_X86_64_32	.rodata.str1.1+0xe
    18f9:	b9 00 00 00 00       	mov    $0x0,%ecx	18fa: R_X86_64_32	.rodata.str1.8+0xa8
    18fe:	ba 90 01 00 00       	mov    $0x190,%edx
    1903:	be 00 00 00 00       	mov    $0x0,%esi	1904: R_X86_64_32	.rodata.str1.8+0x38
    1908:	bf 00 00 00 00       	mov    $0x0,%edi	1909: R_X86_64_32	.rodata.str1.1+0xf
    190d:	e8 00 00 00 00       	call   1912 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1842>	190e: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    1912:	0f 1f 00             	nopl   (%rax)
    1915:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)

0000000000001920 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
    1920:	55                   	push   %rbp
    1921:	48 89 e5             	mov    %rsp,%rbp
    1924:	41 56                	push   %r14
    1926:	41 55                	push   %r13
    1928:	41 54                	push   %r12
    192a:	53                   	push   %rbx
    192b:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
    192f:	48 81 ec 40 01 00 00 	sub    $0x140,%rsp
    1936:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
    193d:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
    1944:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 194b <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2b>	1947: R_X86_64_PC32	g_ee_main_mem-0x4
    194b:	48 2d a0 00 00 00    	sub    $0xa0,%rax
    1951:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
    1958:	89 c0                	mov    %eax,%eax
    195a:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
    195e:	48 8b 8f e0 01 00 00 	mov    0x1e0(%rdi),%rcx
    1965:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    196b:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 1972 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x52>	196e: R_X86_64_PC32	g_ee_main_mem-0x4
    1972:	48 89 4c 02 08       	mov    %rcx,0x8(%rdx,%rax,1)
    1977:	48 8b 87 90 01 00 00 	mov    0x190(%rdi),%rax
    197e:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1985 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x65>	1981: R_X86_64_PC32	g_ee_main_mem-0x4
    1985:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
    198d:	48 89 87 e0 01 00 00 	mov    %rax,0x1e0(%rdi)
    1994:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    199a:	83 c0 30             	add    $0x30,%eax
    199d:	83 e0 f0             	and    $0xfffffff0,%eax
    19a0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    19a6:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    19ac:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
    19b4:	83 c0 40             	add    $0x40,%eax
    19b7:	83 e0 f0             	and    $0xfffffff0,%eax
    19ba:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    19c0:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    19c6:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
    19ce:	83 c0 50             	add    $0x50,%eax
    19d1:	83 e0 f0             	and    $0xfffffff0,%eax
    19d4:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    19da:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    19e0:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
    19e8:	83 c0 60             	add    $0x60,%eax
    19eb:	83 e0 f0             	and    $0xfffffff0,%eax
    19ee:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    19f4:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    19fa:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
    1a02:	83 c0 70             	add    $0x70,%eax
    1a05:	83 e0 f0             	and    $0xfffffff0,%eax
    1a08:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1a0e:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    1a14:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
    1a1c:	83 e8 80             	sub    $0xffffff80,%eax
    1a1f:	83 e0 f0             	and    $0xfffffff0,%eax
    1a22:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1a28:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
    1a2e:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
    1a36:	05 90 00 00 00       	add    $0x90,%eax
    1a3b:	83 e0 f0             	and    $0xfffffff0,%eax
    1a3e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1a44:	48 8b 47 40          	mov    0x40(%rdi),%rax
    1a48:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
    1a4c:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
    1a53:	48 8b 47 50          	mov    0x50(%rdi),%rax
    1a57:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
    1a5e:	48 8b 47 60          	mov    0x60(%rdi),%rax
    1a62:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
    1a69:	48 8b 47 70          	mov    0x70(%rdi),%rax
    1a6d:	48 89 87 00 01 00 00 	mov    %rax,0x100(%rdi)
    1a74:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
    1a7b:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
    1a82:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
    1a89:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
    1a90:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
    1a97:	48 83 c0 10          	add    $0x10,%rax
    1a9b:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
    1aa2:	83 e0 f0             	and    $0xfffffff0,%eax
    1aa5:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1aab:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1ab2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x192>	1aae: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
    1ab2:	48 63 10             	movslq (%rax),%rdx
    1ab5:	48 89 57 30          	mov    %rdx,0x30(%rdi)
    1ab9:	f6 c2 0f             	test   $0xf,%dl
    1abc:	0f 85 fe 10 00 00    	jne    2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    1ac2:	89 d2                	mov    %edx,%edx
    1ac4:	48 89 fb             	mov    %rdi,%rbx
    1ac7:	49 8b 04 11          	mov    (%r9,%rdx,1),%rax
    1acb:	49 8b 4c 11 08       	mov    0x8(%r9,%rdx,1),%rcx
    1ad0:	48 89 87 80 03 00 00 	mov    %rax,0x380(%rdi)
    1ad7:	0f b6 c0             	movzbl %al,%eax
    1ada:	48 89 ca             	mov    %rcx,%rdx
    1add:	48 89 8f 88 03 00 00 	mov    %rcx,0x388(%rdi)
    1ae4:	48 89 4f 38          	mov    %rcx,0x38(%rdi)
    1ae8:	48 89 47 30          	mov    %rax,0x30(%rdi)
    1aec:	8b bf d0 01 00 00    	mov    0x1d0(%rdi),%edi
    1af2:	8d 4f 20             	lea    0x20(%rdi),%ecx
    1af5:	83 e1 f0             	and    $0xfffffff0,%ecx
    1af8:	49 89 04 09          	mov    %rax,(%r9,%rcx,1)
    1afc:	49 89 54 09 08       	mov    %rdx,0x8(%r9,%rcx,1)
    1b01:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    1b08:	e9 b5 00 00 00       	jmp    1bc2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2a2>
    1b0d:	0f 1f 00             	nopl   (%rax)
    1b10:	48 63 09             	movslq (%rcx),%rcx
    1b13:	48 c7 43 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%rbx)
    1b1b:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
    1b1f:	85 c9                	test   %ecx,%ecx
    1b21:	0f 84 99 0b 00 00    	je     26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    1b27:	8b 07                	mov    (%rdi),%eax
    1b29:	89 c2                	mov    %eax,%edx
    1b2b:	83 e0 bf             	and    $0xffffffbf,%eax
    1b2e:	83 e2 40             	and    $0x40,%edx
    1b31:	48 63 c8             	movslq %eax,%rcx
    1b34:	89 d6                	mov    %edx,%esi
    1b36:	48 89 4b 40          	mov    %rcx,0x40(%rbx)
    1b3a:	48 89 73 30          	mov    %rsi,0x30(%rbx)
    1b3e:	89 07                	mov    %eax,(%rdi)
    1b40:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1b47 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x227>	1b43: R_X86_64_PC32	g_ee_main_mem-0x4
    1b47:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    1b4e:	85 d2                	test   %edx,%edx
    1b50:	74 2e                	je     1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    1b52:	89 c0                	mov    %eax,%eax
    1b54:	49 63 54 01 7c       	movslq 0x7c(%r9,%rax,1),%rdx
    1b59:	48 89 d0             	mov    %rdx,%rax
    1b5c:	48 89 53 30          	mov    %rdx,0x30(%rbx)
    1b60:	8b 93 40 01 00 00    	mov    0x140(%rbx),%edx
    1b66:	41 89 44 11 2c       	mov    %eax,0x2c(%r9,%rdx,1)
    1b6b:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    1b72:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1b79 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x259>	1b75: R_X86_64_PC32	g_ee_main_mem-0x4
    1b79:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    1b80:	48 8b b3 30 01 00 00 	mov    0x130(%rbx),%rsi
    1b87:	48 05 90 00 00 00    	add    $0x90,%rax
    1b8d:	48 83 83 40 01 00 00 30 	addq   $0x30,0x140(%rbx)
    1b95:	48 89 83 50 01 00 00 	mov    %rax,0x150(%rbx)
    1b9c:	48 8d 56 ff          	lea    -0x1(%rsi),%rdx
    1ba0:	48 8b b3 00 01 00 00 	mov    0x100(%rbx),%rsi
    1ba7:	48 89 93 30 01 00 00 	mov    %rdx,0x130(%rbx)
    1bae:	48 8d 4e 01          	lea    0x1(%rsi),%rcx
    1bb2:	48 89 8b 00 01 00 00 	mov    %rcx,0x100(%rbx)
    1bb9:	48 85 d2             	test   %rdx,%rdx
    1bbc:	0f 84 2e 0d 00 00    	je     28f0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xfd0>
    1bc2:	89 c1                	mov    %eax,%ecx
    1bc4:	48 8b b3 70 01 00 00 	mov    0x170(%rbx),%rsi
    1bcb:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
    1bd3:	48 89 53 30          	mov    %rdx,0x30(%rbx)
    1bd7:	48 39 d6             	cmp    %rdx,%rsi
    1bda:	74 a4                	je     1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    1bdc:	49 8d 7c 09 68       	lea    0x68(%r9,%rcx,1),%rdi
    1be1:	49 8d 4c 09 64       	lea    0x64(%r9,%rcx,1),%rcx
    1be6:	48 63 17             	movslq (%rdi),%rdx
    1be9:	48 3b b3 20 01 00 00 	cmp    0x120(%rbx),%rsi
    1bf0:	0f 84 aa 0b 00 00    	je     27a0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe80>
    1bf6:	81 e2 00 20 00 00    	and    $0x2000,%edx
    1bfc:	89 d6                	mov    %edx,%esi
    1bfe:	48 89 73 30          	mov    %rsi,0x30(%rbx)
    1c02:	0f 84 08 ff ff ff    	je     1b10 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1f0>
    1c08:	8b b3 d0 01 00 00    	mov    0x1d0(%rbx),%esi
    1c0e:	4c 63 01             	movslq (%rcx),%r8
    1c11:	48 c7 43 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%rbx)
    1c19:	8d 56 20             	lea    0x20(%rsi),%edx
    1c1c:	4c 89 43 30          	mov    %r8,0x30(%rbx)
    1c20:	83 e2 f0             	and    $0xfffffff0,%edx
    1c23:	4d 8b 14 11          	mov    (%r9,%rdx,1),%r10
    1c27:	49 8b 74 11 08       	mov    0x8(%r9,%rdx,1),%rsi
    1c2c:	4c 89 53 40          	mov    %r10,0x40(%rbx)
    1c30:	48 89 73 48          	mov    %rsi,0x48(%rbx)
    1c34:	49 83 f8 ff          	cmp    $0xffffffffffffffff,%r8
    1c38:	74 5d                	je     1c97 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x377>
    1c3a:	4c 89 c2             	mov    %r8,%rdx
    1c3d:	c5 f9 6e f6          	vmovd  %esi,%xmm6
    1c41:	4c 29 d2             	sub    %r10,%rdx
    1c44:	49 89 f2             	mov    %rsi,%r10
    1c47:	48 89 d7             	mov    %rdx,%rdi
    1c4a:	49 c1 fa 20          	sar    $0x20,%r10
    1c4e:	c5 f9 6e ea          	vmovd  %edx,%xmm5
    1c52:	48 89 53 40          	mov    %rdx,0x40(%rbx)
    1c56:	48 c1 ff 20          	sar    $0x20,%rdi
    1c5a:	c4 c3 49 22 ca 01    	vpinsrd $0x1,%r10d,%xmm6,%xmm1
    1c60:	c4 e3 51 22 c7 01    	vpinsrd $0x1,%edi,%xmm5,%xmm0
    1c66:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
    1c6a:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
    1c6e:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
    1c73:	c5 f9 7f 43 30       	vmovdqa %xmm0,0x30(%rbx)
    1c78:	4d 85 c0             	test   %r8,%r8
    1c7b:	0f 84 3f 0a 00 00    	je     26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    1c81:	c5 f9 7e 01          	vmovd  %xmm0,(%rcx)
    1c85:	8b 83 50 01 00 00    	mov    0x150(%rbx),%eax
    1c8b:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 1c92 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x372>	1c8e: R_X86_64_PC32	g_ee_main_mem-0x4
    1c92:	48 8d 7c 02 68       	lea    0x68(%rdx,%rax,1),%rdi
    1c97:	8b 07                	mov    (%rdi),%eax
    1c99:	89 c2                	mov    %eax,%edx
    1c9b:	83 e0 bf             	and    $0xffffffbf,%eax
    1c9e:	83 e2 40             	and    $0x40,%edx
    1ca1:	48 63 c8             	movslq %eax,%rcx
    1ca4:	89 d6                	mov    %edx,%esi
    1ca6:	48 89 4b 40          	mov    %rcx,0x40(%rbx)
    1caa:	48 89 73 30          	mov    %rsi,0x30(%rbx)
    1cae:	89 07                	mov    %eax,(%rdi)
    1cb0:	85 d2                	test   %edx,%edx
    1cb2:	74 23                	je     1cd7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x3b7>
    1cb4:	8b 93 50 01 00 00    	mov    0x150(%rbx),%edx
    1cba:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1cc1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x3a1>	1cbd: R_X86_64_PC32	g_ee_main_mem-0x4
    1cc1:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
    1cc6:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
    1cca:	48 89 ca             	mov    %rcx,%rdx
    1ccd:	8b 8b 40 01 00 00    	mov    0x140(%rbx),%ecx
    1cd3:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
    1cd7:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1cde <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x3be>	1cda: R_X86_64_PC32	g_ee_main_mem-0x4
    1cde:	8b 93 50 01 00 00    	mov    0x150(%rbx),%edx
    1ce4:	49 63 44 11 70       	movslq 0x70(%r9,%rdx,1),%rax
    1ce9:	48 89 c1             	mov    %rax,%rcx
    1cec:	48 89 83 90 01 00 00 	mov    %rax,0x190(%rbx)
    1cf3:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
    1cfa:	85 c9                	test   %ecx,%ecx
    1cfc:	0f 84 de 01 00 00    	je     1ee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x5c0>
    1d02:	c5 f9 6f 83 c0 01 00 00 	vmovdqa 0x1c0(%rbx),%xmm0
    1d0a:	48 83 e8 60          	sub    $0x60,%rax
    1d0e:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
    1d15:	83 e0 f0             	and    $0xfffffff0,%eax
    1d18:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1d1e:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    1d24:	c5 f9 6f 83 50 01 00 00 	vmovdqa 0x150(%rbx),%xmm0
    1d2c:	83 c0 10             	add    $0x10,%eax
    1d2f:	83 e0 f0             	and    $0xfffffff0,%eax
    1d32:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1d38:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    1d3e:	c5 f9 6f 83 40 01 00 00 	vmovdqa 0x140(%rbx),%xmm0
    1d46:	83 c0 20             	add    $0x20,%eax
    1d49:	83 e0 f0             	and    $0xfffffff0,%eax
    1d4c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1d52:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    1d58:	c5 f9 6f 83 00 01 00 00 	vmovdqa 0x100(%rbx),%xmm0
    1d60:	83 c0 30             	add    $0x30,%eax
    1d63:	83 e0 f0             	and    $0xfffffff0,%eax
    1d66:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1d6c:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    1d72:	c5 f9 6f 83 30 01 00 00 	vmovdqa 0x130(%rbx),%xmm0
    1d7a:	83 c0 40             	add    $0x40,%eax
    1d7d:	83 e0 f0             	and    $0xfffffff0,%eax
    1d80:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1d86:	48 8b 83 c0 01 00 00 	mov    0x1c0(%rbx),%rax
    1d8d:	c5 f9 6f 83 20 01 00 00 	vmovdqa 0x120(%rbx),%xmm0
    1d95:	8b bb 90 01 00 00    	mov    0x190(%rbx),%edi
    1d9b:	48 89 43 40          	mov    %rax,0x40(%rbx)
    1d9f:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    1da6:	48 89 43 50          	mov    %rax,0x50(%rbx)
    1daa:	48 8b 83 40 01 00 00 	mov    0x140(%rbx),%rax
    1db1:	48 89 43 60          	mov    %rax,0x60(%rbx)
    1db5:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    1dbb:	83 c0 50             	add    $0x50,%eax
    1dbe:	83 e0 f0             	and    $0xfffffff0,%eax
    1dc1:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    1dc7:	c5 fa 7e bb a0 00 00 00 	vmovq  0xa0(%rbx),%xmm7
    1dcf:	c5 fa 7e 6b 60       	vmovq  0x60(%rbx),%xmm5
    1dd4:	c5 fa 7e b3 80 00 00 00 	vmovq  0x80(%rbx),%xmm6
    1ddc:	c4 e3 d1 22 53 70 01 	vpinsrq $0x1,0x70(%rbx),%xmm5,%xmm2
    1de3:	c4 e3 c1 22 8b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm7,%xmm1
    1ded:	c5 fa 7e 7b 40       	vmovq  0x40(%rbx),%xmm7
    1df2:	c4 e3 c9 22 83 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm6,%xmm0
    1dfc:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
    1e02:	c4 e3 c1 22 4b 50 01 	vpinsrq $0x1,0x50(%rbx),%xmm7,%xmm1
    1e09:	c5 fd 7f 44 24 20    	vmovdqa %ymm0,0x20(%rsp)
    1e0f:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
    1e15:	c5 fd 7f 0c 24       	vmovdqa %ymm1,(%rsp)
    1e1a:	85 ff                	test   %edi,%edi
    1e1c:	0f 84 bd 0d 00 00    	je     2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    1e22:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
    1e29:	4c 01 cf             	add    %r9,%rdi
    1e2c:	31 d2                	xor    %edx,%edx
    1e2e:	48 89 e6             	mov    %rsp,%rsi
    1e31:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
    1e38:	c5 f8 77             	vzeroupper
    1e3b:	e8 00 00 00 00       	call   1e40 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x520>	1e3c: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    1e40:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 1e47 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x527>	1e43: R_X86_64_PC32	g_ee_main_mem-0x4
    1e47:	48 89 43 20          	mov    %rax,0x20(%rbx)
    1e4b:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
    1e52:	48 89 c2             	mov    %rax,%rdx
    1e55:	8d 48 10             	lea    0x10(%rax),%ecx
    1e58:	83 e2 f0             	and    $0xfffffff0,%edx
    1e5b:	83 e1 f0             	and    $0xfffffff0,%ecx
    1e5e:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    1e64:	c5 fa 7f 83 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%rbx)
    1e6c:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
    1e70:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
    1e75:	48 89 8b 58 01 00 00 	mov    %rcx,0x158(%rbx)
    1e7c:	8d 48 20             	lea    0x20(%rax),%ecx
    1e7f:	83 e1 f0             	and    $0xfffffff0,%ecx
    1e82:	48 89 93 50 01 00 00 	mov    %rdx,0x150(%rbx)
    1e89:	89 d2                	mov    %edx,%edx
    1e8b:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1e91:	8d 48 30             	lea    0x30(%rax),%ecx
    1e94:	83 e1 f0             	and    $0xfffffff0,%ecx
    1e97:	c5 fa 7f 83 40 01 00 00 	vmovdqu %xmm0,0x140(%rbx)
    1e9f:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1ea5:	8d 48 40             	lea    0x40(%rax),%ecx
    1ea8:	83 e1 f0             	and    $0xfffffff0,%ecx
    1eab:	c5 fa 7f 83 00 01 00 00 	vmovdqu %xmm0,0x100(%rbx)
    1eb3:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1eb9:	8d 48 50             	lea    0x50(%rax),%ecx
    1ebc:	48 83 c0 60          	add    $0x60,%rax
    1ec0:	83 e1 f0             	and    $0xfffffff0,%ecx
    1ec3:	c5 fa 7f 83 30 01 00 00 	vmovdqu %xmm0,0x130(%rbx)
    1ecb:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
    1ed1:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
    1ed8:	c5 fa 7f 83 20 01 00 00 	vmovdqu %xmm0,0x120(%rbx)
    1ee0:	49 63 74 11 78       	movslq 0x78(%r9,%rdx,1),%rsi
    1ee5:	83 c0 20             	add    $0x20,%eax
    1ee8:	83 e0 f0             	and    $0xfffffff0,%eax
    1eeb:	48 89 73 50          	mov    %rsi,0x50(%rbx)
    1eef:	48 89 f1             	mov    %rsi,%rcx
    1ef2:	49 8d 74 11 74       	lea    0x74(%r9,%rdx,1),%rsi
    1ef7:	48 63 16             	movslq (%rsi),%rdx
    1efa:	48 89 53 30          	mov    %rdx,0x30(%rbx)
    1efe:	49 8b 3c 01          	mov    (%r9,%rax,1),%rdi
    1f02:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
    1f07:	48 89 7b 40          	mov    %rdi,0x40(%rbx)
    1f0b:	48 89 43 48          	mov    %rax,0x48(%rbx)
    1f0f:	85 c9                	test   %ecx,%ecx
    1f11:	74 0f                	je     1f22 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x602>
    1f13:	48 29 fa             	sub    %rdi,%rdx
    1f16:	48 89 53 30          	mov    %rdx,0x30(%rbx)
    1f1a:	89 16                	mov    %edx,(%rsi)
    1f1c:	0f 88 a6 0a 00 00    	js     29c8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x10a8>
    1f22:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
    1f29:	f6 c2 0f             	test   $0xf,%dl
    1f2c:	0f 85 8e 0c 00 00    	jne    2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    1f32:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 1f39 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x619>	1f35: R_X86_64_PC32	g_ee_main_mem-0x4
    1f39:	89 d2                	mov    %edx,%edx
    1f3b:	c5 fa 7e 24 10       	vmovq  (%rax,%rdx,1),%xmm4
    1f40:	48 8b 7c 10 08       	mov    0x8(%rax,%rdx,1),%rdi
    1f45:	c5 f9 d6 a3 00 03 00 00 	vmovq  %xmm4,0x300(%rbx)
    1f4d:	48 89 bb 08 03 00 00 	mov    %rdi,0x308(%rbx)
    1f54:	48 8b 4c 10 10       	mov    0x10(%rax,%rdx,1),%rcx
    1f59:	4c 8b 44 10 18       	mov    0x18(%rax,%rdx,1),%r8
    1f5e:	48 89 8b 10 03 00 00 	mov    %rcx,0x310(%rbx)
    1f65:	4c 89 83 18 03 00 00 	mov    %r8,0x318(%rbx)
    1f6c:	48 8b 74 10 20       	mov    0x20(%rax,%rdx,1),%rsi
    1f71:	48 8b 4c 10 28       	mov    0x28(%rax,%rdx,1),%rcx
    1f76:	48 8b 93 50 01 00 00 	mov    0x150(%rbx),%rdx
    1f7d:	48 89 b3 20 03 00 00 	mov    %rsi,0x320(%rbx)
    1f84:	48 89 8b 28 03 00 00 	mov    %rcx,0x328(%rbx)
    1f8b:	f6 c2 0f             	test   $0xf,%dl
    1f8e:	0f 85 2c 0c 00 00    	jne    2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    1f94:	89 d2                	mov    %edx,%edx
    1f96:	c4 e3 d9 22 e7 01    	vpinsrq $0x1,%rdi,%xmm4,%xmm4
    1f9c:	c5 fa 10 bb 88 03 00 00 	vmovss 0x388(%rbx),%xmm7
    1fa4:	c4 e2 79 18 93 84 03 00 00 	vbroadcastss 0x384(%rbx),%xmm2
    1fad:	48 8d 7c 10 10       	lea    0x10(%rax,%rdx,1),%rdi
    1fb2:	c5 7a 10 93 8c 03 00 00 	vmovss 0x38c(%rbx),%xmm10
    1fba:	4c 8b 37             	mov    (%rdi),%r14
    1fbd:	4c 8b 5f 08          	mov    0x8(%rdi),%r11
    1fc1:	c5 c0 c6 f7 00       	vshufps $0x0,%xmm7,%xmm7,%xmm6
    1fc6:	4c 89 b3 30 03 00 00 	mov    %r14,0x330(%rbx)
    1fcd:	c4 41 79 6e ee       	vmovd  %r14d,%xmm13
    1fd2:	4c 89 9b 38 03 00 00 	mov    %r11,0x338(%rbx)
    1fd9:	4c 8b 4c 10 20       	mov    0x20(%rax,%rdx,1),%r9
    1fde:	4c 8b 64 10 28       	mov    0x28(%rax,%rdx,1),%r12
    1fe3:	4c 89 8b 40 03 00 00 	mov    %r9,0x340(%rbx)
    1fea:	4c 89 a3 48 03 00 00 	mov    %r12,0x348(%rbx)
    1ff1:	c5 fa 7e 44 10 30    	vmovq  0x30(%rax,%rdx,1),%xmm0
    1ff7:	4c 8b 54 10 38       	mov    0x38(%rax,%rdx,1),%r10
    1ffc:	c5 f9 d6 83 50 03 00 00 	vmovq  %xmm0,0x350(%rbx)
    2004:	c4 c3 f9 22 ca 01    	vpinsrq $0x1,%r10,%xmm0,%xmm1
    200a:	c5 fa 7e 83 84 03 00 00 	vmovq  0x384(%rbx),%xmm0
    2012:	4c 89 93 58 03 00 00 	mov    %r10,0x358(%rbx)
    2019:	c5 fa 6f 5c 10 40    	vmovdqu 0x40(%rax,%rdx,1),%xmm3
    201f:	c5 fa 16 c0          	vmovshdup %xmm0,%xmm0
    2023:	c5 f9 6f eb          	vmovdqa %xmm3,%xmm5
    2027:	c5 fa 7f 9b 60 03 00 00 	vmovdqu %xmm3,0x360(%rbx)
    202f:	c5 79 6f cb          	vmovdqa %xmm3,%xmm9
    2033:	4c 63 6c 10 60       	movslq 0x60(%rax,%rdx,1),%r13
    2038:	c5 c8 59 f3          	vmulps %xmm3,%xmm6,%xmm6
    203c:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
    2041:	c4 c1 f9 6e de       	vmovq  %r14,%xmm3
    2046:	c5 79 6f c5          	vmovdqa %xmm5,%xmm8
    204a:	c5 e0 c6 db 55       	vshufps $0x55,%xmm3,%xmm3,%xmm3
    204f:	c5 79 6f e3          	vmovdqa %xmm3,%xmm12
    2053:	c4 c1 30 14 d8       	vunpcklps %xmm8,%xmm9,%xmm3
    2058:	4c 89 da             	mov    %r11,%rdx
    205b:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
    205f:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
    2063:	4c 89 6b 30          	mov    %r13,0x30(%rbx)
    2067:	4d 89 ea             	mov    %r13,%r10
    206a:	c5 f8 59 c3          	vmulps %xmm3,%xmm0,%xmm0
    206e:	c4 c1 10 14 dc       	vunpcklps %xmm12,%xmm13,%xmm3
    2073:	44 89 ab 00 02 00 00 	mov    %r13d,0x200(%rbx)
    207a:	48 c1 ea 20          	shr    $0x20,%rdx
    207e:	c4 e2 7d 18 ab 84 03 00 00 	vbroadcastss 0x384(%rbx),%ymm5
    2087:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
    208b:	c5 f8 29 b3 60 03 00 00 	vmovaps %xmm6,0x360(%rbx)
    2093:	c5 c8 15 f6          	vunpckhps %xmm6,%xmm6,%xmm6
    2097:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
    209b:	c5 f8 58 db          	vaddps %xmm3,%xmm0,%xmm3
    209f:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
    20a4:	c5 ca 58 f0          	vaddss %xmm0,%xmm6,%xmm6
    20a8:	c5 f8 13 9b 30 03 00 00 	vmovlps %xmm3,0x330(%rbx)
    20b0:	c5 fa 11 b3 38 03 00 00 	vmovss %xmm6,0x338(%rbx)
    20b8:	45 85 ed             	test   %r13d,%r13d
    20bb:	0f 85 ef 06 00 00    	jne    27b0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe90>
    20c1:	c5 fa 16 fb          	vmovshdup %xmm3,%xmm7
    20c5:	c5 f8 28 c3          	vmovaps %xmm3,%xmm0
    20c9:	c5 e8 59 c9          	vmulps %xmm1,%xmm2,%xmm1
    20cd:	c5 f9 6e da          	vmovd  %edx,%xmm3
    20d1:	c5 f8 14 c7          	vunpcklps %xmm7,%xmm0,%xmm0
    20d5:	49 c1 e8 20          	shr    $0x20,%r8
    20d9:	c5 c8 14 f3          	vunpcklps %xmm3,%xmm6,%xmm6
    20dd:	c5 f8 16 de          	vmovlhps %xmm6,%xmm0,%xmm3
    20e1:	c5 e0 59 d2          	vmulps %xmm2,%xmm3,%xmm2
    20e5:	c4 c1 79 6e f4       	vmovd  %r12d,%xmm6
    20ea:	49 c1 ec 20          	shr    $0x20,%r12
    20ee:	c4 c1 79 6e c1       	vmovd  %r9d,%xmm0
    20f3:	c4 c1 79 6e fc       	vmovd  %r12d,%xmm7
    20f8:	49 c1 e9 20          	shr    $0x20,%r9
    20fc:	c5 c8 14 f7          	vunpcklps %xmm7,%xmm6,%xmm6
    2100:	c4 c1 79 6e f9       	vmovd  %r9d,%xmm7
    2105:	c5 f8 14 c7          	vunpcklps %xmm7,%xmm0,%xmm0
    2109:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
    210d:	c5 f8 29 8b b0 03 00 00 	vmovaps %xmm1,0x3b0(%rbx)
    2115:	c5 f8 16 c6          	vmovlhps %xmm6,%xmm0,%xmm0
    2119:	c4 e3 65 18 c0 01    	vinsertf128 $0x1,%xmm0,%ymm3,%ymm0
    211f:	c5 f0 15 f1          	vunpckhps %xmm1,%xmm1,%xmm6
    2123:	c5 e8 58 d4          	vaddps %xmm4,%xmm2,%xmm2
    2127:	c5 fc 59 c5          	vmulps %ymm5,%ymm0,%ymm0
    212b:	c5 f9 6e e6          	vmovd  %esi,%xmm4
    212f:	48 c1 ee 20          	shr    $0x20,%rsi
    2133:	c5 f0 c6 e9 55       	vshufps $0x55,%xmm1,%xmm1,%xmm5
    2138:	c5 f8 29 93 00 03 00 00 	vmovaps %xmm2,0x300(%rbx)
    2140:	c5 f2 58 d4          	vaddss %xmm4,%xmm1,%xmm2
    2144:	c5 f9 6e e6          	vmovd  %esi,%xmm4
    2148:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
    214d:	c5 d2 58 ec          	vaddss %xmm4,%xmm5,%xmm5
    2151:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
    2155:	48 c1 e9 20          	shr    $0x20,%rcx
    2159:	c5 ca 58 f4          	vaddss %xmm4,%xmm6,%xmm6
    215d:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
    2161:	c5 fc 11 83 90 03 00 00 	vmovups %ymm0,0x390(%rbx)
    2169:	c4 e3 7d 19 c0 01    	vextractf128 $0x1,%ymm0,%xmm0
    216f:	c5 ea c2 ff 05       	vcmpnltss %xmm7,%xmm2,%xmm7
    2174:	c5 f2 58 cc          	vaddss %xmm4,%xmm1,%xmm1
    2178:	c4 c1 79 6e e0       	vmovd  %r8d,%xmm4
    217d:	c5 f8 c6 c0 ff       	vshufps $0xff,%xmm0,%xmm0,%xmm0
    2182:	c5 fa 58 c4          	vaddss %xmm4,%xmm0,%xmm0
    2186:	c5 d8 57 e4          	vxorps %xmm4,%xmm4,%xmm4
    218a:	c4 e3 59 4a e2 70    	vblendvps %xmm7,%xmm2,%xmm4,%xmm4
    2190:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
    2194:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
    2198:	c5 d2 c2 ff 05       	vcmpnltss %xmm7,%xmm5,%xmm7
    219d:	c5 f8 14 c4          	vunpcklps %xmm4,%xmm0,%xmm0
    21a1:	c4 e3 69 4a d5 70    	vblendvps %xmm7,%xmm5,%xmm2,%xmm2
    21a7:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
    21ab:	c5 d0 57 ed          	vxorps %xmm5,%xmm5,%xmm5
    21af:	c5 ca c2 ff 05       	vcmpnltss %xmm7,%xmm6,%xmm7
    21b4:	c4 e3 51 4a ee 70    	vblendvps %xmm7,%xmm6,%xmm5,%xmm5
    21ba:	c5 e8 14 d5          	vunpcklps %xmm5,%xmm2,%xmm2
    21be:	c5 f8 16 c2          	vmovlhps %xmm2,%xmm0,%xmm0
    21c2:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
    21c6:	c5 f8 11 83 1c 03 00 00 	vmovups %xmm0,0x31c(%rbx)
    21ce:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    21d2:	c5 f2 c2 d2 05       	vcmpnltss %xmm2,%xmm1,%xmm2
    21d7:	c4 e3 79 4a c1 20    	vblendvps %xmm2,%xmm1,%xmm0,%xmm0
    21dd:	c5 fa 11 83 2c 03 00 00 	vmovss %xmm0,0x32c(%rbx)
    21e5:	c5 f8 11 1f          	vmovups %xmm3,(%rdi)
    21e9:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
    21f0:	f6 c2 0f             	test   $0xf,%dl
    21f3:	0f 85 08 0a 00 00    	jne    2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>
    21f9:	c5 f9 6f 83 00 03 00 00 	vmovdqa 0x300(%rbx),%xmm0
    2201:	89 d2                	mov    %edx,%edx
    2203:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
    2208:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
    220f:	f6 c2 0f             	test   $0xf,%dl
    2212:	0f 85 e9 09 00 00    	jne    2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>
    2218:	c5 f9 6f 83 10 03 00 00 	vmovdqa 0x310(%rbx),%xmm0
    2220:	89 d2                	mov    %edx,%edx
    2222:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
    2228:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
    222f:	f6 c2 0f             	test   $0xf,%dl
    2232:	0f 85 c9 09 00 00    	jne    2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>
    2238:	c5 f9 6f 83 20 03 00 00 	vmovdqa 0x320(%rbx),%xmm0
    2240:	89 d2                	mov    %edx,%edx
    2242:	c5 fa 10 2d 00 00 00 00 	vmovss 0x0(%rip),%xmm5        # 224a <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x92a>	2246: R_X86_64_PC32	.LC11-0x4
    224a:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
    2250:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
    2257:	48 8b 8b 10 01 00 00 	mov    0x110(%rbx),%rcx
    225e:	48 89 53 40          	mov    %rdx,0x40(%rbx)
    2262:	89 d2                	mov    %edx,%edx
    2264:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
    2268:	8b 74 10 10          	mov    0x10(%rax,%rdx,1),%esi
    226c:	89 c9                	mov    %ecx,%ecx
    226e:	89 b3 00 02 00 00    	mov    %esi,0x200(%rbx)
    2274:	8b 7c 10 14          	mov    0x14(%rax,%rdx,1),%edi
    2278:	89 bb 04 02 00 00    	mov    %edi,0x204(%rbx)
    227e:	8b 54 10 18          	mov    0x18(%rax,%rdx,1),%edx
    2282:	89 93 0c 02 00 00    	mov    %edx,0x20c(%rbx)
    2288:	89 34 08             	mov    %esi,(%rax,%rcx,1)
    228b:	8b 8b 04 02 00 00    	mov    0x204(%rbx),%ecx
    2291:	8b 43 30             	mov    0x30(%rbx),%eax
    2294:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 229b <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x97b>	2297: R_X86_64_PC32	g_ee_main_mem-0x4
    229b:	89 4c 02 04          	mov    %ecx,0x4(%rdx,%rax,1)
    229f:	8b 8b 0c 02 00 00    	mov    0x20c(%rbx),%ecx
    22a5:	8b 43 30             	mov    0x30(%rbx),%eax
    22a8:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 22af <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x98f>	22ab: R_X86_64_PC32	g_ee_main_mem-0x4
    22af:	89 4c 02 08          	mov    %ecx,0x8(%rdx,%rax,1)
    22b3:	c5 fa 10 83 0c 02 00 00 	vmovss 0x20c(%rbx),%xmm0
    22bb:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 22c2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x9a2>	22be: R_X86_64_PC32	g_ee_main_mem-0x4
    22c2:	8b 43 30             	mov    0x30(%rbx),%eax
    22c5:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
    22c9:	c5 d2 5c c8          	vsubss %xmm0,%xmm5,%xmm1
    22cd:	c5 fa 11 83 0c 02 00 00 	vmovss %xmm0,0x20c(%rbx)
    22d5:	c5 fa 10 83 04 02 00 00 	vmovss 0x204(%rbx),%xmm0
    22dd:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
    22e1:	c5 f2 5c c0          	vsubss %xmm0,%xmm1,%xmm0
    22e5:	c5 f8 14 c9          	vunpcklps %xmm1,%xmm0,%xmm1
    22e9:	c5 f8 13 8b 04 02 00 00 	vmovlps %xmm1,0x204(%rbx)
    22f1:	c5 fa 10 8b 00 02 00 00 	vmovss 0x200(%rbx),%xmm1
    22f9:	c5 f2 59 c9          	vmulss %xmm1,%xmm1,%xmm1
    22fd:	c5 fa 5c c1          	vsubss %xmm1,%xmm0,%xmm0
    2301:	c5 f8 54 05 00 00 00 00 	vandps 0x0(%rip),%xmm0,%xmm0        # 2309 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x9e9>	2305: R_X86_64_PC32	.LC22-0x4
    2309:	c5 fa 51 c0          	vsqrtss %xmm0,%xmm0,%xmm0
    230d:	c5 fa 11 83 00 02 00 00 	vmovss %xmm0,0x200(%rbx)
    2315:	c5 fa 11 44 02 0c    	vmovss %xmm0,0xc(%rdx,%rax,1)
    231b:	48 63 83 00 02 00 00 	movslq 0x200(%rbx),%rax
    2322:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 2329 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa09>	2325: R_X86_64_PC32	g_ee_main_mem-0x4
    2329:	48 89 43 40          	mov    %rax,0x40(%rbx)
    232d:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 2334 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa14>	2330: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
    2334:	48 63 10             	movslq (%rax),%rdx
    2337:	89 d0                	mov    %edx,%eax
    2339:	48 89 53 30          	mov    %rdx,0x30(%rbx)
    233d:	41 8b 04 01          	mov    (%r9,%rax,1),%eax
    2341:	89 83 00 02 00 00    	mov    %eax,0x200(%rbx)
    2347:	0f b6 c0             	movzbl %al,%eax
    234a:	48 83 e8 0a          	sub    $0xa,%rax
    234e:	48 89 43 30          	mov    %rax,0x30(%rbx)
    2352:	0f 88 c3 00 00 00    	js     241b <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xafb>
    2358:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 235f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa3f>	235b: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
    235f:	c5 fa 7e 93 10 01 00 00 	vmovq  0x110(%rbx),%xmm2
    2367:	c5 fa 7e ab a0 00 00 00 	vmovq  0xa0(%rbx),%xmm5
    236f:	c5 fa 7e a3 80 00 00 00 	vmovq  0x80(%rbx),%xmm4
    2377:	48 63 08             	movslq (%rax),%rcx
    237a:	c5 e9 6c ca          	vpunpcklqdq %xmm2,%xmm2,%xmm1
    237e:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    2385:	c5 f9 d6 53 40       	vmovq  %xmm2,0x40(%rbx)
    238a:	c4 e3 d1 22 9b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm5,%xmm3
    2394:	48 63 93 f0 01 00 00 	movslq 0x1f0(%rbx),%rdx
    239b:	c5 f9 d6 53 50       	vmovq  %xmm2,0x50(%rbx)
    23a0:	48 83 c0 50          	add    $0x50,%rax
    23a4:	48 89 8b 90 01 00 00 	mov    %rcx,0x190(%rbx)
    23ab:	48 89 cf             	mov    %rcx,%rdi
    23ae:	c4 e1 f9 6e f0       	vmovq  %rax,%xmm6
    23b3:	c4 e3 c9 22 43 70 01 	vpinsrq $0x1,0x70(%rbx),%xmm6,%xmm0
    23ba:	48 89 43 60          	mov    %rax,0x60(%rbx)
    23be:	48 89 53 20          	mov    %rdx,0x20(%rbx)
    23c2:	c4 e3 75 18 c8 01    	vinsertf128 $0x1,%xmm0,%ymm1,%ymm1
    23c8:	c4 e3 d9 22 83 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm4,%xmm0
    23d2:	c5 fd 7f 8c 24 80 00 00 00 	vmovdqa %ymm1,0x80(%rsp)
    23db:	c4 e3 7d 18 c3 01    	vinsertf128 $0x1,%xmm3,%ymm0,%ymm0
    23e1:	c5 fd 7f 84 24 a0 00 00 00 	vmovdqa %ymm0,0xa0(%rsp)
    23ea:	85 c9                	test   %ecx,%ecx
    23ec:	0f 84 ed 07 00 00    	je     2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    23f2:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
    23f9:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
    2400:	89 ff                	mov    %edi,%edi
    2402:	31 d2                	xor    %edx,%edx
    2404:	4c 01 cf             	add    %r9,%rdi
    2407:	48 8d b4 24 80 00 00 00 	lea    0x80(%rsp),%rsi
    240f:	c5 f8 77             	vzeroupper
    2412:	e8 00 00 00 00       	call   2417 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xaf7>	2413: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    2417:	48 89 43 20          	mov    %rax,0x20(%rbx)
    241b:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 2422 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb02>	241e: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
    2422:	c5 fa 7e ab a0 00 00 00 	vmovq  0xa0(%rbx),%xmm5
    242a:	c5 fa 7e b3 80 00 00 00 	vmovq  0x80(%rbx),%xmm6
    2432:	c5 fa 7e 83 10 01 00 00 	vmovq  0x110(%rbx),%xmm0
    243a:	48 63 00             	movslq (%rax),%rax
    243d:	48 63 93 f0 01 00 00 	movslq 0x1f0(%rbx),%rdx
    2444:	c4 e3 d1 22 8b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm5,%xmm1
    244e:	c5 f9 d6 43 40       	vmovq  %xmm0,0x40(%rbx)
    2453:	c4 e3 c9 22 93 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm6,%xmm2
    245d:	48 89 83 90 01 00 00 	mov    %rax,0x190(%rbx)
    2464:	48 89 c7             	mov    %rax,%rdi
    2467:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    246e:	c4 e3 6d 18 d1 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm2
    2474:	c5 f9 d6 43 50       	vmovq  %xmm0,0x50(%rbx)
    2479:	c5 f9 6c c0          	vpunpcklqdq %xmm0,%xmm0,%xmm0
    247d:	48 83 c0 50          	add    $0x50,%rax
    2481:	48 89 53 20          	mov    %rdx,0x20(%rbx)
    2485:	c4 e1 f9 6e e8       	vmovq  %rax,%xmm5
    248a:	c4 e3 d1 22 4b 70 01 	vpinsrq $0x1,0x70(%rbx),%xmm5,%xmm1
    2491:	48 89 43 60          	mov    %rax,0x60(%rbx)
    2495:	c5 fd 7f 94 24 e0 00 00 00 	vmovdqa %ymm2,0xe0(%rsp)
    249e:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
    24a4:	c5 fd 7f 84 24 c0 00 00 00 	vmovdqa %ymm0,0xc0(%rsp)
    24ad:	85 ff                	test   %edi,%edi
    24af:	0f 84 2a 07 00 00    	je     2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    24b5:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 24bc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb9c>	24b8: R_X86_64_PC32	g_ee_main_mem-0x4
    24bc:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
    24c3:	89 ff                	mov    %edi,%edi
    24c5:	31 d2                	xor    %edx,%edx
    24c7:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
    24ce:	48 8d b4 24 c0 00 00 00 	lea    0xc0(%rsp),%rsi
    24d6:	4c 01 cf             	add    %r9,%rdi
    24d9:	c5 f8 77             	vzeroupper
    24dc:	e8 00 00 00 00       	call   24e1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbc1>	24dd: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    24e1:	48 8b 8b 10 01 00 00 	mov    0x110(%rbx),%rcx
    24e8:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
    24ec:	48 89 43 20          	mov    %rax,0x20(%rbx)
    24f0:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 24f7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbd7>	24f3: R_X86_64_PC32	g_ee_main_mem-0x4
    24f7:	48 8b 83 40 01 00 00 	mov    0x140(%rbx),%rax
    24fe:	89 ca                	mov    %ecx,%edx
    2500:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
    2504:	48 89 43 40          	mov    %rax,0x40(%rbx)
    2508:	c4 c1 79 6e 44 11 0c 	vmovd  0xc(%r9,%rdx,1),%xmm0
    250f:	c7 83 04 02 00 00 00 00 00 00 	movl   $0x0,0x204(%rbx)
    2519:	c5 f8 2f c8          	vcomiss %xmm0,%xmm1
    251d:	c5 f9 7e 83 00 02 00 00 	vmovd  %xmm0,0x200(%rbx)
    2525:	0f 87 25 03 00 00    	ja     2850 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf30>
    252b:	a8 0f                	test   $0xf,%al
    252d:	0f 85 8d 06 00 00    	jne    2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    2533:	89 c0                	mov    %eax,%eax
    2535:	83 e1 0f             	and    $0xf,%ecx
    2538:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
    253d:	48 8b 07             	mov    (%rdi),%rax
    2540:	48 8b 77 08          	mov    0x8(%rdi),%rsi
    2544:	48 89 83 90 02 00 00 	mov    %rax,0x290(%rbx)
    254b:	48 89 b3 98 02 00 00 	mov    %rsi,0x298(%rbx)
    2552:	0f 85 68 06 00 00    	jne    2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    2558:	49 8b 0c 11          	mov    (%r9,%rdx,1),%rcx
    255c:	49 8b 44 11 08       	mov    0x8(%r9,%rdx,1),%rax
    2561:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
    2565:	48 c1 ee 20          	shr    $0x20,%rsi
    2569:	c5 f9 6e fe          	vmovd  %esi,%xmm7
    256d:	48 89 8b a0 02 00 00 	mov    %rcx,0x2a0(%rbx)
    2574:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
    2578:	48 c1 e9 20          	shr    $0x20,%rcx
    257c:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
    2580:	48 89 83 a8 02 00 00 	mov    %rax,0x2a8(%rbx)
    2587:	c5 f8 14 c4          	vunpcklps %xmm4,%xmm0,%xmm0
    258b:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
    258f:	c5 f8 58 c2          	vaddps %xmm2,%xmm0,%xmm0
    2593:	c5 f9 6e d0          	vmovd  %eax,%xmm2
    2597:	c5 ea 58 c9          	vaddss %xmm1,%xmm2,%xmm1
    259b:	c5 f8 13 83 90 02 00 00 	vmovlps %xmm0,0x290(%rbx)
    25a3:	c5 fa 11 8b 98 02 00 00 	vmovss %xmm1,0x298(%rbx)
    25ab:	c5 f0 14 cf          	vunpcklps %xmm7,%xmm1,%xmm1
    25af:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
    25b3:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
    25b7:	48 8b 83 90 02 00 00 	mov    0x290(%rbx),%rax
    25be:	48 8b 93 98 02 00 00 	mov    0x298(%rbx),%rdx
    25c5:	48 89 43 40          	mov    %rax,0x40(%rbx)
    25c9:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    25d0:	c5 f8 28 83 20 03 00 00 	vmovaps 0x320(%rbx),%xmm0
    25d8:	48 89 53 48          	mov    %rdx,0x48(%rbx)
    25dc:	89 c2                	mov    %eax,%edx
    25de:	c5 f8 11 43 30       	vmovups %xmm0,0x30(%rbx)
    25e3:	49 63 4c 11 68       	movslq 0x68(%r9,%rdx,1),%rcx
    25e8:	48 89 4b 40          	mov    %rcx,0x40(%rbx)
    25ec:	48 89 ca             	mov    %rcx,%rdx
    25ef:	83 e1 04             	and    $0x4,%ecx
    25f2:	89 cf                	mov    %ecx,%edi
    25f4:	48 89 7b 50          	mov    %rdi,0x50(%rbx)
    25f8:	f6 c2 02             	test   $0x2,%dl
    25fb:	74 31                	je     262e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd0e>
    25fd:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
    2602:	c7 43 60 00 00 00 00 	movl   $0x0,0x60(%rbx)
    2609:	c4 e3 79 16 43 64 02 	vpextrd $0x2,%xmm0,0x64(%rbx)
    2610:	c4 e3 79 16 43 6c 03 	vpextrd $0x3,%xmm0,0x6c(%rbx)
    2617:	c7 43 68 00 00 00 00 	movl   $0x0,0x68(%rbx)
    261e:	48 85 f6             	test   %rsi,%rsi
    2621:	75 0b                	jne    262e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd0e>
    2623:	48 83 7b 60 00       	cmpq   $0x0,0x60(%rbx)
    2628:	0f 84 92 00 00 00    	je     26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    262e:	83 e2 01             	and    $0x1,%edx
    2631:	89 d7                	mov    %edx,%edi
    2633:	48 89 7b 40          	mov    %rdi,0x40(%rbx)
    2637:	85 c9                	test   %ecx,%ecx
    2639:	74 24                	je     265f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd3f>
    263b:	48 c7 43 38 00 00 00 00 	movq   $0x0,0x38(%rbx)
    2643:	c4 e3 79 16 43 34 03 	vpextrd $0x3,%xmm0,0x34(%rbx)
    264a:	c4 e3 79 16 43 38 02 	vpextrd $0x2,%xmm0,0x38(%rbx)
    2651:	c7 43 30 00 00 00 00 	movl   $0x0,0x30(%rbx)
    2658:	48 83 7b 30 00       	cmpq   $0x0,0x30(%rbx)
    265d:	7e 61                	jle    26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    265f:	85 d2                	test   %edx,%edx
    2661:	0f 84 19 f5 ff ff    	je     1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    2667:	c5 f8 28 83 00 03 00 00 	vmovaps 0x300(%rbx),%xmm0
    266f:	c5 f8 11 43 30       	vmovups %xmm0,0x30(%rbx)
    2674:	c4 e3 79 16 43 34 03 	vpextrd $0x3,%xmm0,0x34(%rbx)
    267b:	c5 f8 28 83 10 03 00 00 	vmovaps 0x310(%rbx),%xmm0
    2683:	c7 43 30 00 00 00 00 	movl   $0x0,0x30(%rbx)
    268a:	48 8b 53 30          	mov    0x30(%rbx),%rdx
    268e:	c5 f8 11 43 30       	vmovups %xmm0,0x30(%rbx)
    2693:	48 85 d2             	test   %rdx,%rdx
    2696:	78 28                	js     26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    2698:	48 c7 43 38 00 00 00 00 	movq   $0x0,0x38(%rbx)
    26a0:	c4 e3 79 16 43 34 03 	vpextrd $0x3,%xmm0,0x34(%rbx)
    26a7:	c4 e3 79 16 43 38 02 	vpextrd $0x2,%xmm0,0x38(%rbx)
    26ae:	c7 43 30 00 00 00 00 	movl   $0x0,0x30(%rbx)
    26b5:	48 83 7b 30 00       	cmpq   $0x0,0x30(%rbx)
    26ba:	0f 89 c0 f4 ff ff    	jns    1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    26c0:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 26c7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda7>	26c3: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
    26c7:	c5 fa 7e 83 c0 01 00 00 	vmovq  0x1c0(%rbx),%xmm0
    26cf:	48 8b 8b 00 01 00 00 	mov    0x100(%rbx),%rcx
    26d6:	c5 fa 7e a3 a0 00 00 00 	vmovq  0xa0(%rbx),%xmm4
    26de:	48 63 12             	movslq (%rdx),%rdx
    26e1:	c5 fa 7e ab 80 00 00 00 	vmovq  0x80(%rbx),%xmm5
    26e9:	c5 f9 d6 43 40       	vmovq  %xmm0,0x40(%rbx)
    26ee:	c4 e3 d9 22 93 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm4,%xmm2
    26f8:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
    26fd:	c4 e3 f9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm0,%xmm0
    2703:	48 63 b3 f0 01 00 00 	movslq 0x1f0(%rbx),%rsi
    270a:	48 89 93 90 01 00 00 	mov    %rdx,0x190(%rbx)
    2711:	48 89 d7             	mov    %rdx,%rdi
    2714:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
    271b:	c4 e3 d1 22 8b 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm5,%xmm1
    2725:	48 89 4b 50          	mov    %rcx,0x50(%rbx)
    2729:	48 89 43 60          	mov    %rax,0x60(%rbx)
    272d:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
    2733:	c4 e3 d9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm4,%xmm2
    2739:	48 89 53 70          	mov    %rdx,0x70(%rbx)
    273d:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
    2743:	48 89 73 20          	mov    %rsi,0x20(%rbx)
    2747:	c5 fd 7f 84 24 00 01 00 00 	vmovdqa %ymm0,0x100(%rsp)
    2750:	c5 fd 7f 8c 24 20 01 00 00 	vmovdqa %ymm1,0x120(%rsp)
    2759:	85 ff                	test   %edi,%edi
    275b:	0f 84 7e 04 00 00    	je     2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    2761:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
    2768:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
    276f:	89 ff                	mov    %edi,%edi
    2771:	31 d2                	xor    %edx,%edx
    2773:	4c 01 cf             	add    %r9,%rdi
    2776:	48 8d b4 24 00 01 00 00 	lea    0x100(%rsp),%rsi
    277e:	c5 f8 77             	vzeroupper
    2781:	e8 00 00 00 00       	call   2786 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe66>	2782: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    2786:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 278d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe6d>	2789: R_X86_64_PC32	g_ee_main_mem-0x4
    278d:	48 89 43 20          	mov    %rax,0x20(%rbx)
    2791:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
    2798:	e9 e3 f3 ff ff       	jmp    1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    279d:	0f 1f 00             	nopl   (%rax)
    27a0:	48 89 53 30          	mov    %rdx,0x30(%rbx)
    27a4:	e9 5f f4 ff ff       	jmp    1c08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2e8>
    27a9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
    27b0:	c4 c1 79 6e c5       	vmovd  %r13d,%xmm0
    27b5:	4c 8b 73 38          	mov    0x38(%rbx),%r14
    27b9:	49 c1 ea 20          	shr    $0x20,%r10
    27bd:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
    27c1:	c5 7a 10 35 00 00 00 00 	vmovss 0x0(%rip),%xmm14        # 27c9 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xea9>	27c5: R_X86_64_PC32	.LC11-0x4
    27c9:	c4 41 79 6e fe       	vmovd  %r14d,%xmm15
    27ce:	c5 0a 5c d8          	vsubss %xmm0,%xmm14,%xmm11
    27d2:	c5 aa 59 c0          	vmulss %xmm0,%xmm10,%xmm0
    27d6:	c4 41 22 59 da       	vmulss %xmm10,%xmm11,%xmm11
    27db:	c4 41 0a 5c db       	vsubss %xmm11,%xmm14,%xmm11
    27e0:	c4 41 79 6e f2       	vmovd  %r10d,%xmm14
    27e5:	c4 41 2a 59 f6       	vmulss %xmm14,%xmm10,%xmm14
    27ea:	c4 41 2a 59 d7       	vmulss %xmm15,%xmm10,%xmm10
    27ef:	c4 c1 4a 59 f3       	vmulss %xmm11,%xmm6,%xmm6
    27f4:	c4 c1 78 14 c6       	vunpcklps %xmm14,%xmm0,%xmm0
    27f9:	c4 41 28 14 d3       	vunpcklps %xmm11,%xmm10,%xmm10
    27fe:	c4 c1 78 16 c2       	vmovlhps %xmm10,%xmm0,%xmm0
    2803:	c5 f8 29 83 70 03 00 00 	vmovaps %xmm0,0x370(%rbx)
    280b:	c4 c1 42 59 c1       	vmulss %xmm9,%xmm7,%xmm0
    2810:	c4 c1 42 59 f8       	vmulss %xmm8,%xmm7,%xmm7
    2815:	c4 41 7a 12 c3       	vmovsldup %xmm11,%xmm8
    281a:	c5 fa 11 b3 38 03 00 00 	vmovss %xmm6,0x338(%rbx)
    2822:	c4 41 7a 7e c0       	vmovq  %xmm8,%xmm8
    2827:	c4 c1 7a 58 c5       	vaddss %xmm13,%xmm0,%xmm0
    282c:	c5 b8 59 db          	vmulps %xmm3,%xmm8,%xmm3
    2830:	c4 c1 42 58 fc       	vaddss %xmm12,%xmm7,%xmm7
    2835:	c4 c1 7a 59 c3       	vmulss %xmm11,%xmm0,%xmm0
    283a:	c4 c1 42 59 fb       	vmulss %xmm11,%xmm7,%xmm7
    283f:	c5 f8 13 9b 30 03 00 00 	vmovlps %xmm3,0x330(%rbx)
    2847:	e9 7d f8 ff ff       	jmp    20c9 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x7a9>
    284c:	0f 1f 40 00          	nopl   0x0(%rax)
    2850:	a8 0f                	test   $0xf,%al
    2852:	0f 85 68 03 00 00    	jne    2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    2858:	89 c0                	mov    %eax,%eax
    285a:	83 e1 0f             	and    $0xf,%ecx
    285d:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
    2862:	48 8b 07             	mov    (%rdi),%rax
    2865:	48 8b 77 08          	mov    0x8(%rdi),%rsi
    2869:	48 89 83 90 02 00 00 	mov    %rax,0x290(%rbx)
    2870:	48 89 b3 98 02 00 00 	mov    %rsi,0x298(%rbx)
    2877:	0f 85 43 03 00 00    	jne    2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    287d:	49 8b 04 11          	mov    (%r9,%rdx,1),%rax
    2881:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
    2886:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
    288a:	48 c1 ee 20          	shr    $0x20,%rsi
    288e:	c5 f9 6e f6          	vmovd  %esi,%xmm6
    2892:	48 89 83 a0 02 00 00 	mov    %rax,0x2a0(%rbx)
    2899:	c5 f9 6e d0          	vmovd  %eax,%xmm2
    289d:	48 c1 e8 20          	shr    $0x20,%rax
    28a1:	c5 f9 6e e0          	vmovd  %eax,%xmm4
    28a5:	48 89 93 a8 02 00 00 	mov    %rdx,0x2a8(%rbx)
    28ac:	c5 e8 14 d4          	vunpcklps %xmm4,%xmm2,%xmm2
    28b0:	c5 fa 7e d2          	vmovq  %xmm2,%xmm2
    28b4:	c5 f8 5c c2          	vsubps %xmm2,%xmm0,%xmm0
    28b8:	c5 f9 6e d2          	vmovd  %edx,%xmm2
    28bc:	c5 f2 5c ca          	vsubss %xmm2,%xmm1,%xmm1
    28c0:	c5 f8 13 83 90 02 00 00 	vmovlps %xmm0,0x290(%rbx)
    28c8:	c5 fa 11 8b 98 02 00 00 	vmovss %xmm1,0x298(%rbx)
    28d0:	c5 f0 14 ce          	vunpcklps %xmm6,%xmm1,%xmm1
    28d4:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
    28d8:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
    28dc:	48 8b 83 90 02 00 00 	mov    0x290(%rbx),%rax
    28e3:	48 8b 93 98 02 00 00 	mov    0x298(%rbx),%rdx
    28ea:	e9 d6 fc ff ff       	jmp    25c5 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xca5>
    28ef:	90                   	nop
    28f0:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
    28f7:	48 89 4b 20          	mov    %rcx,0x20(%rbx)
    28fb:	89 c2                	mov    %eax,%edx
    28fd:	49 8b 34 11          	mov    (%r9,%rdx,1),%rsi
    2901:	48 89 b3 f0 01 00 00 	mov    %rsi,0x1f0(%rbx)
    2908:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
    290d:	48 89 93 e0 01 00 00 	mov    %rdx,0x1e0(%rbx)
    2914:	8d 90 90 00 00 00    	lea    0x90(%rax),%edx
    291a:	83 e2 f0             	and    $0xfffffff0,%edx
    291d:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    2923:	8d 90 80 00 00 00    	lea    0x80(%rax),%edx
    2929:	83 e2 f0             	and    $0xfffffff0,%edx
    292c:	c5 fa 7f 83 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%rbx)
    2934:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    293a:	8d 50 70             	lea    0x70(%rax),%edx
    293d:	83 e2 f0             	and    $0xfffffff0,%edx
    2940:	c5 fa 7f 83 50 01 00 00 	vmovdqu %xmm0,0x150(%rbx)
    2948:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    294e:	8d 50 60             	lea    0x60(%rax),%edx
    2951:	83 e2 f0             	and    $0xfffffff0,%edx
    2954:	c5 fa 7f 83 40 01 00 00 	vmovdqu %xmm0,0x140(%rbx)
    295c:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    2962:	8d 50 50             	lea    0x50(%rax),%edx
    2965:	83 e2 f0             	and    $0xfffffff0,%edx
    2968:	c5 fa 7f 83 30 01 00 00 	vmovdqu %xmm0,0x130(%rbx)
    2970:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    2976:	8d 50 40             	lea    0x40(%rax),%edx
    2979:	83 e2 f0             	and    $0xfffffff0,%edx
    297c:	c5 fa 7f 83 20 01 00 00 	vmovdqu %xmm0,0x120(%rbx)
    2984:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    298a:	8d 50 30             	lea    0x30(%rax),%edx
    298d:	48 05 a0 00 00 00    	add    $0xa0,%rax
    2993:	83 e2 f0             	and    $0xfffffff0,%edx
    2996:	c5 fa 7f 83 10 01 00 00 	vmovdqu %xmm0,0x110(%rbx)
    299e:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
    29a4:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
    29ab:	48 89 c8             	mov    %rcx,%rax
    29ae:	c5 fa 7f 83 00 01 00 00 	vmovdqu %xmm0,0x100(%rbx)
    29b6:	48 8d 65 e0          	lea    -0x20(%rbp),%rsp
    29ba:	5b                   	pop    %rbx
    29bb:	41 5c                	pop    %r12
    29bd:	41 5d                	pop    %r13
    29bf:	41 5e                	pop    %r14
    29c1:	5d                   	pop    %rbp
    29c2:	c3                   	ret
    29c3:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
    29c8:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
    29cf:	c5 f9 6f 83 c0 01 00 00 	vmovdqa 0x1c0(%rbx),%xmm0
    29d7:	4c 8b 0d 00 00 00 00 	mov    0x0(%rip),%r9        # 29de <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x10be>	29da: R_X86_64_PC32	g_ee_main_mem-0x4
    29de:	48 83 e8 60          	sub    $0x60,%rax
    29e2:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
    29e9:	83 e0 f0             	and    $0xfffffff0,%eax
    29ec:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    29f2:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    29f8:	c5 f9 6f 83 50 01 00 00 	vmovdqa 0x150(%rbx),%xmm0
    2a00:	83 c0 10             	add    $0x10,%eax
    2a03:	83 e0 f0             	and    $0xfffffff0,%eax
    2a06:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2a0c:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    2a12:	c5 f9 6f 83 40 01 00 00 	vmovdqa 0x140(%rbx),%xmm0
    2a1a:	83 c0 20             	add    $0x20,%eax
    2a1d:	83 e0 f0             	and    $0xfffffff0,%eax
    2a20:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2a26:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    2a2c:	c5 f9 6f 83 00 01 00 00 	vmovdqa 0x100(%rbx),%xmm0
    2a34:	83 c0 30             	add    $0x30,%eax
    2a37:	83 e0 f0             	and    $0xfffffff0,%eax
    2a3a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2a40:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    2a46:	c5 f9 6f 83 30 01 00 00 	vmovdqa 0x130(%rbx),%xmm0
    2a4e:	83 c0 40             	add    $0x40,%eax
    2a51:	83 e0 f0             	and    $0xfffffff0,%eax
    2a54:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2a5a:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
    2a60:	c5 f9 6f 83 20 01 00 00 	vmovdqa 0x120(%rbx),%xmm0
    2a68:	83 c0 50             	add    $0x50,%eax
    2a6b:	83 e0 f0             	and    $0xfffffff0,%eax
    2a6e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
    2a74:	c5 fa 7e 83 c0 01 00 00 	vmovq  0x1c0(%rbx),%xmm0
    2a7c:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
    2a83:	c5 fa 7e 93 50 01 00 00 	vmovq  0x150(%rbx),%xmm2
    2a8b:	48 8b 05 00 00 00 00 	mov    0x0(%rip),%rax        # 2a92 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1172>	2a8e: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
    2a92:	c5 f9 d6 43 40       	vmovq  %xmm0,0x40(%rbx)
    2a97:	c5 fa 7e ab a0 00 00 00 	vmovq  0xa0(%rbx),%xmm5
    2a9f:	c5 f9 d6 53 60       	vmovq  %xmm2,0x60(%rbx)
    2aa4:	c4 e3 e9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm2,%xmm2
    2aaa:	48 89 53 70          	mov    %rdx,0x70(%rbx)
    2aae:	48 63 08             	movslq (%rax),%rcx
    2ab1:	48 89 8b 90 01 00 00 	mov    %rcx,0x190(%rbx)
    2ab8:	48 89 c8             	mov    %rcx,%rax
    2abb:	48 63 8b f0 01 00 00 	movslq 0x1f0(%rbx),%rcx
    2ac2:	48 89 4b 20          	mov    %rcx,0x20(%rbx)
    2ac6:	c4 e3 d1 22 9b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm5,%xmm3
    2ad0:	c5 fa 7e bb 80 00 00 00 	vmovq  0x80(%rbx),%xmm7
    2ad8:	c4 e3 f9 22 43 50 01 	vpinsrq $0x1,0x50(%rbx),%xmm0,%xmm0
    2adf:	c4 e3 c1 22 8b 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm7,%xmm1
    2ae9:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
    2aef:	c4 e3 75 18 cb 01    	vinsertf128 $0x1,%xmm3,%ymm1,%ymm1
    2af5:	c5 fd 7f 44 24 40    	vmovdqa %ymm0,0x40(%rsp)
    2afb:	c5 fd 7f 4c 24 60    	vmovdqa %ymm1,0x60(%rsp)
    2b01:	85 c0                	test   %eax,%eax
    2b03:	0f 84 d6 00 00 00    	je     2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    2b09:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
    2b10:	89 c0                	mov    %eax,%eax
    2b12:	31 d2                	xor    %edx,%edx
    2b14:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
    2b19:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
    2b20:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
    2b24:	c5 f8 77             	vzeroupper
    2b27:	e8 00 00 00 00       	call   2b2c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x120c>	2b28: R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    2b2c:	48 8b 15 00 00 00 00 	mov    0x0(%rip),%rdx        # 2b33 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1213>	2b2f: R_X86_64_PC32	g_ee_main_mem-0x4
    2b33:	48 89 43 20          	mov    %rax,0x20(%rbx)
    2b37:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
    2b3e:	48 89 c1             	mov    %rax,%rcx
    2b41:	83 e1 f0             	and    $0xfffffff0,%ecx
    2b44:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    2b49:	8d 48 10             	lea    0x10(%rax),%ecx
    2b4c:	83 e1 f0             	and    $0xfffffff0,%ecx
    2b4f:	c5 fa 7f 83 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%rbx)
    2b57:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    2b5c:	8d 48 20             	lea    0x20(%rax),%ecx
    2b5f:	83 e1 f0             	and    $0xfffffff0,%ecx
    2b62:	c5 fa 7f 83 50 01 00 00 	vmovdqu %xmm0,0x150(%rbx)
    2b6a:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    2b6f:	8d 48 30             	lea    0x30(%rax),%ecx
    2b72:	83 e1 f0             	and    $0xfffffff0,%ecx
    2b75:	c5 fa 7f 83 40 01 00 00 	vmovdqu %xmm0,0x140(%rbx)
    2b7d:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    2b82:	8d 48 40             	lea    0x40(%rax),%ecx
    2b85:	83 e1 f0             	and    $0xfffffff0,%ecx
    2b88:	c5 fa 7f 83 00 01 00 00 	vmovdqu %xmm0,0x100(%rbx)
    2b90:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    2b95:	8d 48 50             	lea    0x50(%rax),%ecx
    2b98:	48 83 c0 60          	add    $0x60,%rax
    2b9c:	83 e1 f0             	and    $0xfffffff0,%ecx
    2b9f:	c5 fa 7f 83 30 01 00 00 	vmovdqu %xmm0,0x130(%rbx)
    2ba7:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
    2bac:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
    2bb3:	c5 fa 7f 83 20 01 00 00 	vmovdqu %xmm0,0x120(%rbx)
    2bbb:	e9 62 f3 ff ff       	jmp    1f22 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x602>
    2bc0:	41 b8 00 00 00 00    	mov    $0x0,%r8d	2bc2: R_X86_64_32	.rodata.str1.1+0xe
    2bc6:	b9 00 00 00 00       	mov    $0x0,%ecx	2bc7: R_X86_64_32	.rodata.str1.8
    2bcb:	ba 58 01 00 00       	mov    $0x158,%edx
    2bd0:	be 00 00 00 00       	mov    $0x0,%esi	2bd1: R_X86_64_32	.rodata.str1.8+0x38
    2bd5:	bf 00 00 00 00       	mov    $0x0,%edi	2bd6: R_X86_64_32	.rodata.str1.8+0x78
    2bda:	e8 00 00 00 00       	call   2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>	2bdb: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2bdf:	41 b8 00 00 00 00    	mov    $0x0,%r8d	2be1: R_X86_64_32	.rodata.str1.1+0xe
    2be5:	b9 00 00 00 00       	mov    $0x0,%ecx	2be6: R_X86_64_32	.rodata.str1.8+0xa8
    2bea:	ba 90 01 00 00       	mov    $0x190,%edx
    2bef:	be 00 00 00 00       	mov    $0x0,%esi	2bf0: R_X86_64_32	.rodata.str1.8+0x38
    2bf4:	bf 00 00 00 00       	mov    $0x0,%edi	2bf5: R_X86_64_32	.rodata.str1.1+0xf
    2bf9:	c5 f8 77             	vzeroupper
    2bfc:	e8 00 00 00 00       	call   2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>	2bfd: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2c01:	41 b8 00 00 00 00    	mov    $0x0,%r8d	2c03: R_X86_64_32	.rodata.str1.1+0xe
    2c07:	b9 00 00 00 00       	mov    $0x0,%ecx	2c08: R_X86_64_32	.rodata.str1.8+0x1a0
    2c0c:	ba c0 01 00 00       	mov    $0x1c0,%edx
    2c11:	be 00 00 00 00       	mov    $0x0,%esi	2c12: R_X86_64_32	.rodata.str1.8+0x38
    2c16:	bf 00 00 00 00       	mov    $0x0,%edi	2c17: R_X86_64_32	.rodata.str1.8+0x1d8
    2c1b:	c5 f8 77             	vzeroupper
    2c1e:	e8 00 00 00 00       	call   2c23 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1303>	2c1f: R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2c23:	66 90                	xchg   %ax,%ax
    2c25:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)

0000000000002c30 <Mips2C::jak1::sp_process_block_3d::link()>:
    2c30:	53                   	push   %rbx
    2c31:	bf 00 00 00 00       	mov    $0x0,%edi	2c32: R_X86_64_32	.rodata.str1.1+0x14
    2c36:	48 83 ec 20          	sub    $0x20,%rsp
    2c3a:	e8 00 00 00 00       	call   2c3f <Mips2C::jak1::sp_process_block_3d::link()+0xf>	2c3b: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2c3f:	bf 00 00 00 00       	mov    $0x0,%edi	2c40: R_X86_64_32	.rodata.str1.1+0x24
    2c44:	89 c2                	mov    %eax,%edx
    2c46:	89 c0                	mov    %eax,%eax
    2c48:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2c4f <Mips2C::jak1::sp_process_block_3d::link()+0x1f>	2c4b: R_X86_64_PC32	g_ee_main_mem-0x4
    2c4f:	85 d2                	test   %edx,%edx
    2c51:	ba 00 00 00 00       	mov    $0x0,%edx
    2c56:	48 0f 44 c2          	cmove  %rdx,%rax
    2c5a:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2c61 <Mips2C::jak1::sp_process_block_3d::link()+0x31>	2c5d: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
    2c61:	e8 00 00 00 00       	call   2c66 <Mips2C::jak1::sp_process_block_3d::link()+0x36>	2c62: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2c66:	bf 00 00 00 00       	mov    $0x0,%edi	2c67: R_X86_64_32	.rodata.str1.1+0x31
    2c6b:	89 c2                	mov    %eax,%edx
    2c6d:	89 c0                	mov    %eax,%eax
    2c6f:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2c76 <Mips2C::jak1::sp_process_block_3d::link()+0x46>	2c72: R_X86_64_PC32	g_ee_main_mem-0x4
    2c76:	85 d2                	test   %edx,%edx
    2c78:	ba 00 00 00 00       	mov    $0x0,%edx
    2c7d:	48 0f 44 c2          	cmove  %rdx,%rax
    2c81:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2c88 <Mips2C::jak1::sp_process_block_3d::link()+0x58>	2c84: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
    2c88:	e8 00 00 00 00       	call   2c8d <Mips2C::jak1::sp_process_block_3d::link()+0x5d>	2c89: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2c8d:	bf 00 00 00 00       	mov    $0x0,%edi	2c8e: R_X86_64_32	.rodata.str1.1+0x42
    2c92:	89 c2                	mov    %eax,%edx
    2c94:	89 c0                	mov    %eax,%eax
    2c96:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2c9d <Mips2C::jak1::sp_process_block_3d::link()+0x6d>	2c99: R_X86_64_PC32	g_ee_main_mem-0x4
    2c9d:	85 d2                	test   %edx,%edx
    2c9f:	ba 00 00 00 00       	mov    $0x0,%edx
    2ca4:	48 0f 44 c2          	cmove  %rdx,%rax
    2ca8:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2caf <Mips2C::jak1::sp_process_block_3d::link()+0x7f>	2cab: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
    2caf:	e8 00 00 00 00       	call   2cb4 <Mips2C::jak1::sp_process_block_3d::link()+0x84>	2cb0: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2cb4:	bf 14 00 00 00       	mov    $0x14,%edi
    2cb9:	89 c2                	mov    %eax,%edx
    2cbb:	89 c0                	mov    %eax,%eax
    2cbd:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2cc4 <Mips2C::jak1::sp_process_block_3d::link()+0x94>	2cc0: R_X86_64_PC32	g_ee_main_mem-0x4
    2cc4:	85 d2                	test   %edx,%edx
    2cc6:	ba 00 00 00 00       	mov    $0x0,%edx
    2ccb:	48 0f 44 c2          	cmove  %rdx,%rax
    2ccf:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2cd6 <Mips2C::jak1::sp_process_block_3d::link()+0xa6>	2cd2: R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
    2cd6:	e8 00 00 00 00       	call   2cdb <Mips2C::jak1::sp_process_block_3d::link()+0xab>	2cd7: R_X86_64_PLT32	operator new(unsigned long)-0x4
    2cdb:	c5 f9 6f 05 00 00 00 00 	vmovdqa 0x0(%rip),%xmm0        # 2ce3 <Mips2C::jak1::sp_process_block_3d::link()+0xb3>	2cdf: R_X86_64_PC32	.LC28-0x4
    2ce3:	48 89 e6             	mov    %rsp,%rsi
    2ce6:	b9 00 01 00 00       	mov    $0x100,%ecx
    2ceb:	c6 40 13 00          	movb   $0x0,0x13(%rax)
    2cef:	ba 00 00 00 00       	mov    $0x0,%edx	2cf0: R_X86_64_32	Mips2C::jak1::sp_process_block_3d::execute(void*)
    2cf4:	bf 00 00 00 00       	mov    $0x0,%edi	2cf5: R_X86_64_32	Mips2C::gLinkedFunctionTable
    2cf9:	c5 fa 7f 00          	vmovdqu %xmm0,(%rax)
    2cfd:	c7 40 0f 6b 2d 33 64 	movl   $0x64332d6b,0xf(%rax)
    2d04:	48 89 04 24          	mov    %rax,(%rsp)
    2d08:	48 c7 44 24 10 13 00 00 00 	movq   $0x13,0x10(%rsp)
    2d11:	48 c7 44 24 08 13 00 00 00 	movq   $0x13,0x8(%rsp)
    2d1a:	e8 00 00 00 00       	call   2d1f <Mips2C::jak1::sp_process_block_3d::link()+0xef>	2d1b: R_X86_64_PLT32	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)-0x4
    2d1f:	48 8b 3c 24          	mov    (%rsp),%rdi
    2d23:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
    2d28:	48 39 c7             	cmp    %rax,%rdi
    2d2b:	74 0e                	je     2d3b <Mips2C::jak1::sp_process_block_3d::link()+0x10b>
    2d2d:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
    2d32:	48 8d 70 01          	lea    0x1(%rax),%rsi
    2d36:	e8 00 00 00 00       	call   2d3b <Mips2C::jak1::sp_process_block_3d::link()+0x10b>	2d37: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
    2d3b:	48 83 c4 20          	add    $0x20,%rsp
    2d3f:	5b                   	pop    %rbx
    2d40:	c3                   	ret
    2d41:	48 89 c3             	mov    %rax,%rbx
    2d44:	e9 00 00 00 00       	jmp    2d49 <Mips2C::jak1::sp_process_block_3d::link()+0x119>	2d45: R_X86_64_PC32	.text.unlikely-0x4
    2d49:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)

0000000000002d50 <Mips2C::jak1::sp_process_block_2d::link()>:
    2d50:	53                   	push   %rbx
    2d51:	bf 00 00 00 00       	mov    $0x0,%edi	2d52: R_X86_64_32	.rodata.str1.1+0x14
    2d56:	48 83 ec 20          	sub    $0x20,%rsp
    2d5a:	e8 00 00 00 00       	call   2d5f <Mips2C::jak1::sp_process_block_2d::link()+0xf>	2d5b: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2d5f:	bf 00 00 00 00       	mov    $0x0,%edi	2d60: R_X86_64_32	.rodata.str1.1+0x31
    2d64:	89 c2                	mov    %eax,%edx
    2d66:	89 c0                	mov    %eax,%eax
    2d68:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2d6f <Mips2C::jak1::sp_process_block_2d::link()+0x1f>	2d6b: R_X86_64_PC32	g_ee_main_mem-0x4
    2d6f:	85 d2                	test   %edx,%edx
    2d71:	ba 00 00 00 00       	mov    $0x0,%edx
    2d76:	48 0f 44 c2          	cmove  %rdx,%rax
    2d7a:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2d81 <Mips2C::jak1::sp_process_block_2d::link()+0x31>	2d7d: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache-0x4
    2d81:	e8 00 00 00 00       	call   2d86 <Mips2C::jak1::sp_process_block_2d::link()+0x36>	2d82: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2d86:	bf 00 00 00 00       	mov    $0x0,%edi	2d87: R_X86_64_32	.rodata.str1.1+0x5a
    2d8b:	89 c2                	mov    %eax,%edx
    2d8d:	89 c0                	mov    %eax,%eax
    2d8f:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2d96 <Mips2C::jak1::sp_process_block_2d::link()+0x46>	2d92: R_X86_64_PC32	g_ee_main_mem-0x4
    2d96:	85 d2                	test   %edx,%edx
    2d98:	ba 00 00 00 00       	mov    $0x0,%edx
    2d9d:	48 0f 44 c2          	cmove  %rdx,%rax
    2da1:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2da8 <Mips2C::jak1::sp_process_block_2d::link()+0x58>	2da4: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x4
    2da8:	e8 00 00 00 00       	call   2dad <Mips2C::jak1::sp_process_block_2d::link()+0x5d>	2da9: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2dad:	bf 00 00 00 00       	mov    $0x0,%edi	2dae: R_X86_64_32	.rodata.str1.1+0x65
    2db2:	89 c2                	mov    %eax,%edx
    2db4:	89 c0                	mov    %eax,%eax
    2db6:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2dbd <Mips2C::jak1::sp_process_block_2d::link()+0x6d>	2db9: R_X86_64_PC32	g_ee_main_mem-0x4
    2dbd:	85 d2                	test   %edx,%edx
    2dbf:	ba 00 00 00 00       	mov    $0x0,%edx
    2dc4:	48 0f 44 c2          	cmove  %rdx,%rax
    2dc8:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2dcf <Mips2C::jak1::sp_process_block_2d::link()+0x7f>	2dcb: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0xc
    2dcf:	e8 00 00 00 00       	call   2dd4 <Mips2C::jak1::sp_process_block_2d::link()+0x84>	2dd0: R_X86_64_PLT32	jak1::intern_from_c(char const*)-0x4
    2dd4:	bf 14 00 00 00       	mov    $0x14,%edi
    2dd9:	89 c2                	mov    %eax,%edx
    2ddb:	89 c0                	mov    %eax,%eax
    2ddd:	48 03 05 00 00 00 00 	add    0x0(%rip),%rax        # 2de4 <Mips2C::jak1::sp_process_block_2d::link()+0x94>	2de0: R_X86_64_PC32	g_ee_main_mem-0x4
    2de4:	85 d2                	test   %edx,%edx
    2de6:	ba 00 00 00 00       	mov    $0x0,%edx
    2deb:	48 0f 44 c2          	cmove  %rdx,%rax
    2def:	48 89 05 00 00 00 00 	mov    %rax,0x0(%rip)        # 2df6 <Mips2C::jak1::sp_process_block_2d::link()+0xa6>	2df2: R_X86_64_PC32	Mips2C::jak1::sp_process_block_2d::cache+0x14
    2df6:	e8 00 00 00 00       	call   2dfb <Mips2C::jak1::sp_process_block_2d::link()+0xab>	2df7: R_X86_64_PLT32	operator new(unsigned long)-0x4
    2dfb:	c5 f9 6f 05 00 00 00 00 	vmovdqa 0x0(%rip),%xmm0        # 2e03 <Mips2C::jak1::sp_process_block_2d::link()+0xb3>	2dff: R_X86_64_PC32	.LC28-0x4
    2e03:	48 89 e6             	mov    %rsp,%rsi
    2e06:	b9 00 01 00 00       	mov    $0x100,%ecx
    2e0b:	c6 40 13 00          	movb   $0x0,0x13(%rax)
    2e0f:	ba 00 00 00 00       	mov    $0x0,%edx	2e10: R_X86_64_32	Mips2C::jak1::sp_process_block_2d::execute(void*)
    2e14:	bf 00 00 00 00       	mov    $0x0,%edi	2e15: R_X86_64_32	Mips2C::gLinkedFunctionTable
    2e19:	c5 fa 7f 00          	vmovdqu %xmm0,(%rax)
    2e1d:	c7 40 0f 6b 2d 32 64 	movl   $0x64322d6b,0xf(%rax)
    2e24:	48 89 04 24          	mov    %rax,(%rsp)
    2e28:	48 c7 44 24 10 13 00 00 00 	movq   $0x13,0x10(%rsp)
    2e31:	48 c7 44 24 08 13 00 00 00 	movq   $0x13,0x8(%rsp)
    2e3a:	e8 00 00 00 00       	call   2e3f <Mips2C::jak1::sp_process_block_2d::link()+0xef>	2e3b: R_X86_64_PLT32	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)-0x4
    2e3f:	48 8b 3c 24          	mov    (%rsp),%rdi
    2e43:	48 8d 44 24 10       	lea    0x10(%rsp),%rax
    2e48:	48 39 c7             	cmp    %rax,%rdi
    2e4b:	74 0e                	je     2e5b <Mips2C::jak1::sp_process_block_2d::link()+0x10b>
    2e4d:	48 8b 44 24 10       	mov    0x10(%rsp),%rax
    2e52:	48 8d 70 01          	lea    0x1(%rax),%rsi
    2e56:	e8 00 00 00 00       	call   2e5b <Mips2C::jak1::sp_process_block_2d::link()+0x10b>	2e57: R_X86_64_PLT32	operator delete(void*, unsigned long)-0x4
    2e5b:	48 83 c4 20          	add    $0x20,%rsp
    2e5f:	5b                   	pop    %rbx
    2e60:	c3                   	ret
    2e61:	48 89 c3             	mov    %rax,%rbx
    2e64:	e9 00 00 00 00       	jmp    2e69 <Mips2C::jak1::sp_process_block_2d::link()+0x119>	2e65: R_X86_64_PC32	.text.unlikely+0x28

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
