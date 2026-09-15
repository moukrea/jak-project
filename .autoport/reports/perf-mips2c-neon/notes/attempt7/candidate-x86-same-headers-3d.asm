
.autoport/reports/perf-mips2c-neon/notes/attempt7/candidate-x86-same-headers.o:	file format elf64-x86-64

Disassembly of section .text:

00000000000000d0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
      d0: 55                           	pushq	%rbp
      d1: 48 89 e5                     	movq	%rsp, %rbp
      d4: 41 57                        	pushq	%r15
      d6: 41 56                        	pushq	%r14
      d8: 41 55                        	pushq	%r13
      da: 41 54                        	pushq	%r12
      dc: 53                           	pushq	%rbx
      dd: 48 83 e4 e0                  	andq	$-0x20, %rsp
      e1: 48 81 ec 80 01 00 00         	subq	$0x180, %rsp            # imm = 0x180
      e8: 48 8b 87 d0 01 00 00         	movq	0x1d0(%rdi), %rax
      ef: 48 8b 8f f0 01 00 00         	movq	0x1f0(%rdi), %rcx
      f6: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0xfd <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d>
		00000000000000f9:  R_X86_64_PC32	g_ee_main_mem-0x4
      fd: 48 2d a0 00 00 00            	subq	$0xa0, %rax
     103: 48 89 87 d0 01 00 00         	movq	%rax, 0x1d0(%rdi)
     10a: 89 c0                        	movl	%eax, %eax
     10c: 48 89 0c 02                  	movq	%rcx, (%rdx,%rax)
     110: 48 8b 8f e0 01 00 00         	movq	0x1e0(%rdi), %rcx
     117: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     11d: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x124 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x54>
		0000000000000120:  R_X86_64_PC32	g_ee_main_mem-0x4
     124: 48 89 4c 02 08               	movq	%rcx, 0x8(%rdx,%rax)
     129: 48 8b 87 90 01 00 00         	movq	0x190(%rdi), %rax
     130: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x137 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x67>
		0000000000000133:  R_X86_64_PC32	g_ee_main_mem-0x4
     137: c5 f9 6f 87 00 01 00 00      	vmovdqa	0x100(%rdi), %xmm0
     13f: 48 89 87 e0 01 00 00         	movq	%rax, 0x1e0(%rdi)
     146: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     14c: 83 c0 30                     	addl	$0x30, %eax
     14f: 83 e0 f0                     	andl	$-0x10, %eax
     152: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     158: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     15e: c5 f9 6f 87 10 01 00 00      	vmovdqa	0x110(%rdi), %xmm0
     166: 83 c0 40                     	addl	$0x40, %eax
     169: 83 e0 f0                     	andl	$-0x10, %eax
     16c: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     172: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     178: c5 f9 6f 87 20 01 00 00      	vmovdqa	0x120(%rdi), %xmm0
     180: 83 c0 50                     	addl	$0x50, %eax
     183: 83 e0 f0                     	andl	$-0x10, %eax
     186: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     18c: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     192: c5 f9 6f 87 30 01 00 00      	vmovdqa	0x130(%rdi), %xmm0
     19a: 83 c0 60                     	addl	$0x60, %eax
     19d: 83 e0 f0                     	andl	$-0x10, %eax
     1a0: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     1a6: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     1ac: c5 f9 6f 87 40 01 00 00      	vmovdqa	0x140(%rdi), %xmm0
     1b4: 83 c0 70                     	addl	$0x70, %eax
     1b7: 83 e0 f0                     	andl	$-0x10, %eax
     1ba: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     1c0: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     1c6: c5 f9 6f 87 50 01 00 00      	vmovdqa	0x150(%rdi), %xmm0
     1ce: 83 e8 80                     	subl	$-0x80, %eax
     1d1: 83 e0 f0                     	andl	$-0x10, %eax
     1d4: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     1da: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
     1e0: c5 f9 6f 87 c0 01 00 00      	vmovdqa	0x1c0(%rdi), %xmm0
     1e8: 05 90 00 00 00               	addl	$0x90, %eax
     1ed: 83 e0 f0                     	andl	$-0x10, %eax
     1f0: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     1f6: 48 8b 47 40                  	movq	0x40(%rdi), %rax
     1fa: c5 f9 ef c0                  	vpxor	%xmm0, %xmm0, %xmm0
     1fe: 48 89 87 c0 01 00 00         	movq	%rax, 0x1c0(%rdi)
     205: 48 8b 47 50                  	movq	0x50(%rdi), %rax
     209: 48 89 87 50 01 00 00         	movq	%rax, 0x150(%rdi)
     210: 48 8b 47 60                  	movq	0x60(%rdi), %rax
     214: 48 89 87 40 01 00 00         	movq	%rax, 0x140(%rdi)
     21b: 48 8b 47 70                  	movq	0x70(%rdi), %rax
     21f: 48 89 87 00 01 00 00         	movq	%rax, 0x100(%rdi)
     226: 48 8b 87 80 00 00 00         	movq	0x80(%rdi), %rax
     22d: 48 89 87 30 01 00 00         	movq	%rax, 0x130(%rdi)
     234: 48 8b 87 90 00 00 00         	movq	0x90(%rdi), %rax
     23b: 48 89 87 20 01 00 00         	movq	%rax, 0x120(%rdi)
     242: 48 8b 87 d0 01 00 00         	movq	0x1d0(%rdi), %rax
     249: 48 83 c0 10                  	addq	$0x10, %rax
     24d: 48 89 87 10 01 00 00         	movq	%rax, 0x110(%rdi)
     254: 83 e0 f0                     	andl	$-0x10, %eax
     257: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     25d: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x264 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x194>
		0000000000000260:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
     264: 48 63 10                     	movslq	(%rax), %rdx
     267: 48 89 57 30                  	movq	%rdx, 0x30(%rdi)
     26b: f6 c2 0f                     	testb	$0xf, %dl
     26e: 0f 85 dc 11 00 00            	jne	0x1450 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     274: 89 d0                        	movl	%edx, %eax
     276: 8b 9f d0 01 00 00            	movl	0x1d0(%rdi), %ebx
     27c: 49 89 fe                     	movq	%rdi, %r14
     27f: 49 8b 4c 01 08               	movq	0x8(%r9,%rax), %rcx
     284: 49 8b 14 01                  	movq	(%r9,%rax), %rdx
     288: 48 89 8f 88 03 00 00         	movq	%rcx, 0x388(%rdi)
     28f: 0f b6 c2                     	movzbl	%dl, %eax
     292: 48 89 97 80 03 00 00         	movq	%rdx, 0x380(%rdi)
     299: 48 89 ca                     	movq	%rcx, %rdx
     29c: 48 89 4f 38                  	movq	%rcx, 0x38(%rdi)
     2a0: 8d 4b 20                     	leal	0x20(%rbx), %ecx
     2a3: 83 e1 f0                     	andl	$-0x10, %ecx
     2a6: 48 89 47 30                  	movq	%rax, 0x30(%rdi)
     2aa: 49 89 04 09                  	movq	%rax, (%r9,%rcx)
     2ae: 49 89 54 09 08               	movq	%rdx, 0x8(%r9,%rcx)
     2b3: 48 8b 87 50 01 00 00         	movq	0x150(%rdi), %rax
     2ba: e9 b3 00 00 00               	jmp	0x372 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2a2>
     2bf: 90                           	nop
     2c0: 49 63 08                     	movslq	(%r8), %rcx
     2c3: 49 c7 46 40 ff ff ff ff      	movq	$-0x1, 0x40(%r14)
     2cb: 49 89 4e 30                  	movq	%rcx, 0x30(%r14)
     2cf: 85 c9                        	testl	%ecx, %ecx
     2d1: 0f 84 60 01 00 00            	je	0x437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     2d7: 8b 07                        	movl	(%rdi), %eax
     2d9: 89 c2                        	movl	%eax, %edx
     2db: 83 e0 bf                     	andl	$-0x41, %eax
     2de: 83 e2 40                     	andl	$0x40, %edx
     2e1: 48 63 c8                     	movslq	%eax, %rcx
     2e4: 89 d3                        	movl	%edx, %ebx
     2e6: 49 89 4e 40                  	movq	%rcx, 0x40(%r14)
     2ea: 49 89 5e 30                  	movq	%rbx, 0x30(%r14)
     2ee: 89 07                        	movl	%eax, (%rdi)
     2f0: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x2f7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x227>
		00000000000002f3:  R_X86_64_PC32	g_ee_main_mem-0x4
     2f7: 49 8b 86 50 01 00 00         	movq	0x150(%r14), %rax
     2fe: 85 d2                        	testl	%edx, %edx
     300: 74 2e                        	je	0x330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     302: 89 c0                        	movl	%eax, %eax
     304: 49 63 54 01 7c               	movslq	0x7c(%r9,%rax), %rdx
     309: 48 89 d0                     	movq	%rdx, %rax
     30c: 49 89 56 30                  	movq	%rdx, 0x30(%r14)
     310: 41 8b 96 40 01 00 00         	movl	0x140(%r14), %edx
     317: 41 89 44 11 2c               	movl	%eax, 0x2c(%r9,%rdx)
     31c: 49 8b 86 50 01 00 00         	movq	0x150(%r14), %rax
     323: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x32a <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x25a>
		0000000000000326:  R_X86_64_PC32	g_ee_main_mem-0x4
     32a: 66 0f 1f 44 00 00            	nopw	(%rax,%rax)
     330: 49 8b 9e 30 01 00 00         	movq	0x130(%r14), %rbx
     337: 48 05 90 00 00 00            	addq	$0x90, %rax
     33d: 49 83 86 40 01 00 00 30      	addq	$0x30, 0x140(%r14)
     345: 49 89 86 50 01 00 00         	movq	%rax, 0x150(%r14)
     34c: 48 8d 53 ff                  	leaq	-0x1(%rbx), %rdx
     350: 49 8b 9e 00 01 00 00         	movq	0x100(%r14), %rbx
     357: 49 89 96 30 01 00 00         	movq	%rdx, 0x130(%r14)
     35e: 48 8d 4b 01                  	leaq	0x1(%rbx), %rcx
     362: 49 89 8e 00 01 00 00         	movq	%rcx, 0x100(%r14)
     369: 48 85 d2                     	testq	%rdx, %rdx
     36c: 0f 84 be 0f 00 00            	je	0x1330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1260>
     372: 89 c1                        	movl	%eax, %ecx
     374: 49 8b b6 70 01 00 00         	movq	0x170(%r14), %rsi
     37b: 49 63 94 09 80 00 00 00      	movslq	0x80(%r9,%rcx), %rdx
     383: 49 89 56 30                  	movq	%rdx, 0x30(%r14)
     387: 48 39 d6                     	cmpq	%rdx, %rsi
     38a: 74 a4                        	je	0x330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     38c: 49 8d 7c 09 68               	leaq	0x68(%r9,%rcx), %rdi
     391: 4d 8d 44 09 64               	leaq	0x64(%r9,%rcx), %r8
     396: 48 63 17                     	movslq	(%rdi), %rdx
     399: 49 3b b6 20 01 00 00         	cmpq	0x120(%r14), %rsi
     3a0: 0f 84 fa 0b 00 00            	je	0xfa0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xed0>
     3a6: 81 e2 00 20 00 00            	andl	$0x2000, %edx           # imm = 0x2000
     3ac: 89 d3                        	movl	%edx, %ebx
     3ae: 49 89 5e 30                  	movq	%rbx, 0x30(%r14)
     3b2: 0f 84 08 ff ff ff            	je	0x2c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1f0>
     3b8: 41 8b 9e d0 01 00 00         	movl	0x1d0(%r14), %ebx
     3bf: 49 63 30                     	movslq	(%r8), %rsi
     3c2: 49 c7 46 40 ff ff ff ff      	movq	$-0x1, 0x40(%r14)
     3ca: 8d 53 20                     	leal	0x20(%rbx), %edx
     3cd: 49 89 76 30                  	movq	%rsi, 0x30(%r14)
     3d1: 83 e2 f0                     	andl	$-0x10, %edx
     3d4: 4d 8b 14 11                  	movq	(%r9,%rdx), %r10
     3d8: 49 8b 54 11 08               	movq	0x8(%r9,%rdx), %rdx
     3dd: 4d 89 56 40                  	movq	%r10, 0x40(%r14)
     3e1: 49 89 56 48                  	movq	%rdx, 0x48(%r14)
     3e5: 48 83 fe ff                  	cmpq	$-0x1, %rsi
     3e9: 0f 84 49 01 00 00            	je	0x538 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x468>
     3ef: 48 89 f1                     	movq	%rsi, %rcx
     3f2: c5 f9 6e fa                  	vmovd	%edx, %xmm7
     3f6: 4c 29 d1                     	subq	%r10, %rcx
     3f9: 49 89 d2                     	movq	%rdx, %r10
     3fc: 48 89 cf                     	movq	%rcx, %rdi
     3ff: 49 c1 fa 20                  	sarq	$0x20, %r10
     403: c5 f9 6e d9                  	vmovd	%ecx, %xmm3
     407: 49 89 4e 40                  	movq	%rcx, 0x40(%r14)
     40b: 48 c1 ff 20                  	sarq	$0x20, %rdi
     40f: c4 c3 41 22 ca 01            	vpinsrd	$0x1, %r10d, %xmm7, %xmm1
     415: c4 e3 61 22 c7 01            	vpinsrd	$0x1, %edi, %xmm3, %xmm0
     41b: c5 f9 6c c1                  	vpunpcklqdq	%xmm1, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm1[0]
     41f: c5 f1 ef c9                  	vpxor	%xmm1, %xmm1, %xmm1
     423: c4 e2 79 3d c1               	vpmaxsd	%xmm1, %xmm0, %xmm0
     428: c4 c1 79 7f 46 30            	vmovdqa	%xmm0, 0x30(%r14)
     42e: 48 85 f6                     	testq	%rsi, %rsi
     431: 0f 85 e9 00 00 00            	jne	0x520 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x450>
     437: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x43e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x36e>
		000000000000043a:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
     43e: 49 8b 8e 40 01 00 00         	movq	0x140(%r14), %rcx
     445: c4 e1 f9 6e e0               	vmovq	%rax, %xmm4
     44a: c4 c1 7a 7e 86 c0 01 00 00   	vmovq	0x1c0(%r14), %xmm0      # xmm0 = mem[0],zero
     453: 49 63 b6 f0 01 00 00         	movslq	0x1f0(%r14), %rsi
     45a: c4 c1 7a 7e be a0 00 00 00   	vmovq	0xa0(%r14), %xmm7       # xmm7 = mem[0],zero
     463: 48 63 12                     	movslq	(%rdx), %rdx
     466: 49 89 46 60                  	movq	%rax, 0x60(%r14)
     46a: c4 c3 c1 22 96 b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%r14), %xmm7, %xmm2
     474: c4 c1 79 d6 46 40            	vmovq	%xmm0, 0x40(%r14)
     47a: c4 c1 7a 7e 9e 80 00 00 00   	vmovq	0x80(%r14), %xmm3       # xmm3 = mem[0],zero
     483: 49 89 96 90 01 00 00         	movq	%rdx, 0x190(%r14)
     48a: 48 89 d7                     	movq	%rdx, %rdi
     48d: 49 8b 96 00 01 00 00         	movq	0x100(%r14), %rdx
     494: c4 c3 e1 22 8e 90 00 00 00 01	vpinsrq	$0x1, 0x90(%r14), %xmm3, %xmm1
     49e: 49 89 4e 70                  	movq	%rcx, 0x70(%r14)
     4a2: c4 e3 f9 22 c2 01            	vpinsrq	$0x1, %rdx, %xmm0, %xmm0
     4a8: 49 89 56 50                  	movq	%rdx, 0x50(%r14)
     4ac: c4 e3 75 18 ca 01            	vinsertf128	$0x1, %xmm2, %ymm1, %ymm1
     4b2: c4 e3 d9 22 d1 01            	vpinsrq	$0x1, %rcx, %xmm4, %xmm2
     4b8: 49 89 76 20                  	movq	%rsi, 0x20(%r14)
     4bc: c5 fd 7f 8c 24 60 01 00 00   	vmovdqa	%ymm1, 0x160(%rsp)
     4c5: c4 e3 7d 18 c2 01            	vinsertf128	$0x1, %xmm2, %ymm0, %ymm0
     4cb: c5 fd 7f 84 24 40 01 00 00   	vmovdqa	%ymm0, 0x140(%rsp)
     4d4: 85 ff                        	testl	%edi, %edi
     4d6: 0f 84 30 0f 00 00            	je	0x140c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     4dc: 49 8b 8e 60 01 00 00         	movq	0x160(%r14), %rcx
     4e3: 4d 8b 86 70 01 00 00         	movq	0x170(%r14), %r8
     4ea: 89 ff                        	movl	%edi, %edi
     4ec: 31 d2                        	xorl	%edx, %edx
     4ee: 4c 01 cf                     	addq	%r9, %rdi
     4f1: 48 8d b4 24 40 01 00 00      	leaq	0x140(%rsp), %rsi
     4f9: c5 f8 77                     	vzeroupper
     4fc: e8 00 00 00 00               	callq	0x501 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x431>
		00000000000004fd:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     501: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x508 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x438>
		0000000000000504:  R_X86_64_PC32	g_ee_main_mem-0x4
     508: 49 89 46 20                  	movq	%rax, 0x20(%r14)
     50c: 49 8b 86 50 01 00 00         	movq	0x150(%r14), %rax
     513: e9 18 fe ff ff               	jmp	0x330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     518: 0f 1f 84 00 00 00 00 00      	nopl	(%rax,%rax)
     520: c4 c1 79 7e 00               	vmovd	%xmm0, (%r8)
     525: 41 8b 86 50 01 00 00         	movl	0x150(%r14), %eax
     52c: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x533 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x463>
		000000000000052f:  R_X86_64_PC32	g_ee_main_mem-0x4
     533: 48 8d 7c 02 68               	leaq	0x68(%rdx,%rax), %rdi
     538: 8b 07                        	movl	(%rdi), %eax
     53a: 89 c2                        	movl	%eax, %edx
     53c: 83 e0 bf                     	andl	$-0x41, %eax
     53f: 83 e2 40                     	andl	$0x40, %edx
     542: 48 63 c8                     	movslq	%eax, %rcx
     545: 89 d3                        	movl	%edx, %ebx
     547: 49 89 4e 40                  	movq	%rcx, 0x40(%r14)
     54b: 49 89 5e 30                  	movq	%rbx, 0x30(%r14)
     54f: 89 07                        	movl	%eax, (%rdi)
     551: 85 d2                        	testl	%edx, %edx
     553: 74 25                        	je	0x57a <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x4aa>
     555: 41 8b 96 50 01 00 00         	movl	0x150(%r14), %edx
     55c: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x563 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x493>
		000000000000055f:  R_X86_64_PC32	g_ee_main_mem-0x4
     563: 48 63 4c 10 7c               	movslq	0x7c(%rax,%rdx), %rcx
     568: 49 89 4e 30                  	movq	%rcx, 0x30(%r14)
     56c: 48 89 ca                     	movq	%rcx, %rdx
     56f: 41 8b 8e 40 01 00 00         	movl	0x140(%r14), %ecx
     576: 89 54 08 2c                  	movl	%edx, 0x2c(%rax,%rcx)
     57a: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x581 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x4b1>
		000000000000057d:  R_X86_64_PC32	g_ee_main_mem-0x4
     581: 41 8b 96 50 01 00 00         	movl	0x150(%r14), %edx
     588: 49 63 44 11 70               	movslq	0x70(%r9,%rdx), %rax
     58d: 48 89 c1                     	movq	%rax, %rcx
     590: 49 89 86 90 01 00 00         	movq	%rax, 0x190(%r14)
     597: 49 8b 86 d0 01 00 00         	movq	0x1d0(%r14), %rax
     59e: 85 c9                        	testl	%ecx, %ecx
     5a0: 0f 84 f6 01 00 00            	je	0x79c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6cc>
     5a6: c4 c1 79 6f 86 c0 01 00 00   	vmovdqa	0x1c0(%r14), %xmm0
     5af: 48 83 e8 60                  	subq	$0x60, %rax
     5b3: 49 89 86 d0 01 00 00         	movq	%rax, 0x1d0(%r14)
     5ba: 83 e0 f0                     	andl	$-0x10, %eax
     5bd: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     5c3: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
     5ca: c4 c1 79 6f 86 50 01 00 00   	vmovdqa	0x150(%r14), %xmm0
     5d3: 83 c0 10                     	addl	$0x10, %eax
     5d6: 83 e0 f0                     	andl	$-0x10, %eax
     5d9: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     5df: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
     5e6: c4 c1 79 6f 86 40 01 00 00   	vmovdqa	0x140(%r14), %xmm0
     5ef: 83 c0 20                     	addl	$0x20, %eax
     5f2: 83 e0 f0                     	andl	$-0x10, %eax
     5f5: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     5fb: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
     602: c4 c1 79 6f 86 00 01 00 00   	vmovdqa	0x100(%r14), %xmm0
     60b: 83 c0 30                     	addl	$0x30, %eax
     60e: 83 e0 f0                     	andl	$-0x10, %eax
     611: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     617: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
     61e: c4 c1 79 6f 86 30 01 00 00   	vmovdqa	0x130(%r14), %xmm0
     627: 83 c0 40                     	addl	$0x40, %eax
     62a: 83 e0 f0                     	andl	$-0x10, %eax
     62d: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     633: 49 8b 86 c0 01 00 00         	movq	0x1c0(%r14), %rax
     63a: c4 c1 79 6f 86 20 01 00 00   	vmovdqa	0x120(%r14), %xmm0
     643: 41 8b be 90 01 00 00         	movl	0x190(%r14), %edi
     64a: 49 89 46 40                  	movq	%rax, 0x40(%r14)
     64e: 49 8b 86 50 01 00 00         	movq	0x150(%r14), %rax
     655: 49 89 46 50                  	movq	%rax, 0x50(%r14)
     659: 49 8b 86 40 01 00 00         	movq	0x140(%r14), %rax
     660: 49 89 46 60                  	movq	%rax, 0x60(%r14)
     664: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
     66b: 83 c0 50                     	addl	$0x50, %eax
     66e: 83 e0 f0                     	andl	$-0x10, %eax
     671: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
     677: c4 c1 7a 7e 76 60            	vmovq	0x60(%r14), %xmm6       # xmm6 = mem[0],zero
     67d: c4 c1 7a 7e ae a0 00 00 00   	vmovq	0xa0(%r14), %xmm5       # xmm5 = mem[0],zero
     686: c4 c3 d1 22 8e b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%r14), %xmm5, %xmm1
     690: c4 c3 c9 22 56 70 01         	vpinsrq	$0x1, 0x70(%r14), %xmm6, %xmm2
     697: c4 c1 7a 7e ae 80 00 00 00   	vmovq	0x80(%r14), %xmm5       # xmm5 = mem[0],zero
     6a0: c4 c1 7a 7e 7e 40            	vmovq	0x40(%r14), %xmm7       # xmm7 = mem[0],zero
     6a6: c4 c3 d1 22 86 90 00 00 00 01	vpinsrq	$0x1, 0x90(%r14), %xmm5, %xmm0
     6b0: c4 e3 7d 18 c1 01            	vinsertf128	$0x1, %xmm1, %ymm0, %ymm0
     6b6: c4 c3 c1 22 4e 50 01         	vpinsrq	$0x1, 0x50(%r14), %xmm7, %xmm1
     6bd: c5 fd 7f 44 24 60            	vmovdqa	%ymm0, 0x60(%rsp)
     6c3: c4 e3 75 18 ca 01            	vinsertf128	$0x1, %xmm2, %ymm1, %ymm1
     6c9: c5 fd 7f 4c 24 40            	vmovdqa	%ymm1, 0x40(%rsp)
     6cf: 85 ff                        	testl	%edi, %edi
     6d1: 0f 84 35 0d 00 00            	je	0x140c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     6d7: 49 8b 8e 60 01 00 00         	movq	0x160(%r14), %rcx
     6de: 4d 8b 86 70 01 00 00         	movq	0x170(%r14), %r8
     6e5: 4c 01 cf                     	addq	%r9, %rdi
     6e8: 31 d2                        	xorl	%edx, %edx
     6ea: 48 8d 74 24 40               	leaq	0x40(%rsp), %rsi
     6ef: c5 f8 77                     	vzeroupper
     6f2: e8 00 00 00 00               	callq	0x6f7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x627>
		00000000000006f3:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     6f7: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x6fe <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x62e>
		00000000000006fa:  R_X86_64_PC32	g_ee_main_mem-0x4
     6fe: 49 89 46 20                  	movq	%rax, 0x20(%r14)
     702: 49 8b 86 d0 01 00 00         	movq	0x1d0(%r14), %rax
     709: 48 89 c2                     	movq	%rax, %rdx
     70c: 8d 48 10                     	leal	0x10(%rax), %ecx
     70f: 83 e2 f0                     	andl	$-0x10, %edx
     712: 83 e1 f0                     	andl	$-0x10, %ecx
     715: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
     71b: c4 c1 7a 7f 86 c0 01 00 00   	vmovdqu	%xmm0, 0x1c0(%r14)
     724: 49 8b 14 09                  	movq	(%r9,%rcx), %rdx
     728: 49 8b 4c 09 08               	movq	0x8(%r9,%rcx), %rcx
     72d: 49 89 8e 58 01 00 00         	movq	%rcx, 0x158(%r14)
     734: 8d 48 20                     	leal	0x20(%rax), %ecx
     737: 83 e1 f0                     	andl	$-0x10, %ecx
     73a: 49 89 96 50 01 00 00         	movq	%rdx, 0x150(%r14)
     741: 89 d2                        	movl	%edx, %edx
     743: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
     749: 8d 48 30                     	leal	0x30(%rax), %ecx
     74c: 83 e1 f0                     	andl	$-0x10, %ecx
     74f: c4 c1 7a 7f 86 40 01 00 00   	vmovdqu	%xmm0, 0x140(%r14)
     758: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
     75e: 8d 48 40                     	leal	0x40(%rax), %ecx
     761: 83 e1 f0                     	andl	$-0x10, %ecx
     764: c4 c1 7a 7f 86 00 01 00 00   	vmovdqu	%xmm0, 0x100(%r14)
     76d: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
     773: 8d 48 50                     	leal	0x50(%rax), %ecx
     776: 48 83 c0 60                  	addq	$0x60, %rax
     77a: 83 e1 f0                     	andl	$-0x10, %ecx
     77d: c4 c1 7a 7f 86 30 01 00 00   	vmovdqu	%xmm0, 0x130(%r14)
     786: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
     78c: 49 89 86 d0 01 00 00         	movq	%rax, 0x1d0(%r14)
     793: c4 c1 7a 7f 86 20 01 00 00   	vmovdqu	%xmm0, 0x120(%r14)
     79c: 49 63 74 11 78               	movslq	0x78(%r9,%rdx), %rsi
     7a1: 83 c0 20                     	addl	$0x20, %eax
     7a4: 83 e0 f0                     	andl	$-0x10, %eax
     7a7: 49 89 76 50                  	movq	%rsi, 0x50(%r14)
     7ab: 48 89 f1                     	movq	%rsi, %rcx
     7ae: 49 8d 74 11 74               	leaq	0x74(%r9,%rdx), %rsi
     7b3: 48 63 16                     	movslq	(%rsi), %rdx
     7b6: 49 89 56 30                  	movq	%rdx, 0x30(%r14)
     7ba: 49 8b 3c 01                  	movq	(%r9,%rax), %rdi
     7be: 49 8b 44 01 08               	movq	0x8(%r9,%rax), %rax
     7c3: 49 89 7e 40                  	movq	%rdi, 0x40(%r14)
     7c7: 49 89 46 48                  	movq	%rax, 0x48(%r14)
     7cb: 85 c9                        	testl	%ecx, %ecx
     7cd: 74 0f                        	je	0x7de <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x70e>
     7cf: 48 29 fa                     	subq	%rdi, %rdx
     7d2: 49 89 56 30                  	movq	%rdx, 0x30(%r14)
     7d6: 89 16                        	movl	%edx, (%rsi)
     7d8: 0f 88 32 09 00 00            	js	0x1110 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1040>
     7de: 41 8b 96 40 01 00 00         	movl	0x140(%r14), %edx
     7e5: f6 c2 0f                     	testb	$0xf, %dl
     7e8: 0f 85 a0 0c 00 00            	jne	0x148e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13be>
     7ee: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x7f5 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x725>
		00000000000007f1:  R_X86_64_PC32	g_ee_main_mem-0x4
     7f5: 41 8b b6 50 01 00 00         	movl	0x150(%r14), %esi
     7fc: 4c 8b 4c 10 18               	movq	0x18(%rax,%rdx), %r9
     801: 48 8b 5c 10 10               	movq	0x10(%rax,%rdx), %rbx
     806: c5 fa 7e 1c 10               	vmovq	(%rax,%rdx), %xmm3      # xmm3 = mem[0],zero
     80b: 48 8b 4c 10 08               	movq	0x8(%rax,%rdx), %rcx
     810: 48 89 5c 24 20               	movq	%rbx, 0x20(%rsp)
     815: 4c 89 4c 24 28               	movq	%r9, 0x28(%rsp)
     81a: 40 f6 c6 0f                  	testb	$0xf, %sil
     81e: 0f 85 4b 0c 00 00            	jne	0x146f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x139f>
     824: c5 78 10 44 10 20            	vmovups	0x20(%rax,%rdx), %xmm8
     82a: 4d 8b 96 88 03 00 00         	movq	0x388(%r14), %r10
     831: c4 e3 e1 22 d9 01            	vpinsrq	$0x1, %rcx, %xmm3, %xmm3
     837: 48 8b 54 30 10               	movq	0x10(%rax,%rsi), %rdx
     83c: c5 fa 6f 44 30 40            	vmovdqu	0x40(%rax,%rsi), %xmm0
     842: c4 41 79 6e ca               	vmovd	%r10d, %xmm9
     847: 48 8b 4c 30 18               	movq	0x18(%rax,%rsi), %rcx
     84c: c5 7a 7e 54 30 30            	vmovq	0x30(%rax,%rsi), %xmm10 # xmm10 = mem[0],zero
     852: c4 e1 f9 6e ca               	vmovq	%rdx, %xmm1
     857: c5 f9 6f e0                  	vmovdqa	%xmm0, %xmm4
     85b: c5 f9 6f e8                  	vmovdqa	%xmm0, %xmm5
     85f: c4 c1 30 c6 d1 00            	vshufps	$0x0, %xmm9, %xmm9, %xmm2 # xmm2 = xmm9[0,0,0,0]
     865: c5 f0 c6 c9 55               	vshufps	$0x55, %xmm1, %xmm1, %xmm1 # xmm1 = xmm1[1,1,1,1]
     86a: c5 79 6f f1                  	vmovdqa	%xmm1, %xmm14
     86e: c4 c1 7a 12 c9               	vmovsldup	%xmm9, %xmm1    # xmm1 = xmm9[0,0,2,2]
     873: 48 89 cf                     	movq	%rcx, %rdi
     876: c5 d8 c6 e4 55               	vshufps	$0x55, %xmm4, %xmm4, %xmm4 # xmm4 = xmm4[1,1,1,1]
     87b: c5 f9 6f f4                  	vmovdqa	%xmm4, %xmm6
     87f: c5 f9 6e e2                  	vmovd	%edx, %xmm4
     883: c5 79 6e d9                  	vmovd	%ecx, %xmm11
     887: c5 e8 59 d0                  	vmulps	%xmm0, %xmm2, %xmm2
     88b: c5 f8 14 c6                  	vunpcklps	%xmm6, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm6[0],xmm0[1],xmm6[1]
     88f: 4c 8b 7c 30 38               	movq	0x38(%rax,%rsi), %r15
     894: 48 8b 5c 30 20               	movq	0x20(%rax,%rsi), %rbx
     899: c5 fa 7e c0                  	vmovq	%xmm0, %xmm0            # xmm0 = xmm0[0],zero
     89d: 4c 8b 5c 30 28               	movq	0x28(%rax,%rsi), %r11
     8a2: 49 8b b6 50 01 00 00         	movq	0x150(%r14), %rsi
     8a9: 48 ba 00 00 00 00 ff ff ff ff	movabsq	$-0x100000000, %rdx     # imm = 0xFFFFFFFF00000000
     8b3: c5 fa 7e c9                  	vmovq	%xmm1, %xmm1            # xmm1 = xmm1[0],zero
     8b7: 48 21 d7                     	andq	%rdx, %rdi
     8ba: c4 c3 a9 22 ff 01            	vpinsrq	$0x1, %r15, %xmm10, %xmm7
     8c0: c5 f8 59 c1                  	vmulps	%xmm1, %xmm0, %xmm0
     8c4: c4 c1 58 14 ce               	vunpcklps	%xmm14, %xmm4, %xmm1 # xmm1 = xmm4[0],xmm14[0],xmm4[1],xmm14[1]
     8c9: 48 89 74 24 38               	movq	%rsi, 0x38(%rsp)
     8ce: 89 f6                        	movl	%esi, %esi
     8d0: c5 fa 7e c9                  	vmovq	%xmm1, %xmm1            # xmm1 = xmm1[0],zero
     8d4: 48 89 74 24 30               	movq	%rsi, 0x30(%rsp)
     8d9: 48 63 74 30 60               	movslq	0x60(%rax,%rsi), %rsi
     8de: 49 89 f0                     	movq	%rsi, %r8
     8e1: 41 89 b6 00 02 00 00         	movl	%esi, 0x200(%r14)
     8e8: 49 89 76 30                  	movq	%rsi, 0x30(%r14)
     8ec: 49 8b b6 80 03 00 00         	movq	0x380(%r14), %rsi
     8f3: c5 fa 7e c0                  	vmovq	%xmm0, %xmm0            # xmm0 = xmm0[0],zero
     8f7: c5 f8 58 c1                  	vaddps	%xmm1, %xmm0, %xmm0
     8fb: c5 e8 15 ca                  	vunpckhps	%xmm2, %xmm2, %xmm1 # xmm1 = xmm2[2,2,3,3]
     8ff: c4 c1 72 58 cb               	vaddss	%xmm11, %xmm1, %xmm1
     904: c4 c1 f9 7e c4               	vmovq	%xmm0, %r12
     909: c4 62 79 35 f9               	vpmovzxdq	%xmm1, %xmm15   # xmm15 = xmm1[0],zero,xmm1[1],zero
     90e: c4 61 f9 7e fa               	vmovq	%xmm15, %rdx
     913: c5 79 d6 7c 24 18            	vmovq	%xmm15, 0x18(%rsp)
     919: 48 09 d7                     	orq	%rdx, %rdi
     91c: 49 89 fd                     	movq	%rdi, %r13
     91f: 45 85 c0                     	testl	%r8d, %r8d
     922: 0f 85 30 07 00 00            	jne	0x1058 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf88>
     928: c5 7a 16 c8                  	vmovshdup	%xmm0, %xmm9    # xmm9 = xmm0[1,1,3,3]
     92c: c5 f8 28 e8                  	vmovaps	%xmm0, %xmm5
     930: 48 89 df                     	movq	%rbx, %rdi
     933: 48 c1 e9 20                  	shrq	$0x20, %rcx
     937: c4 c1 50 14 e9               	vunpcklps	%xmm9, %xmm5, %xmm5 # xmm5 = xmm5[0],xmm9[0],xmm5[1],xmm9[1]
     93c: c4 e1 f9 6e f6               	vmovq	%rsi, %xmm6
     941: 48 c1 ef 20                  	shrq	$0x20, %rdi
     945: c5 f9 6e e1                  	vmovd	%ecx, %xmm4
     949: c5 c8 c6 f6 55               	vshufps	$0x55, %xmm6, %xmm6, %xmm6 # xmm6 = xmm6[1,1,1,1]
     94e: c5 f9 6f c6                  	vmovdqa	%xmm6, %xmm0
     952: c5 79 6e ef                  	vmovd	%edi, %xmm13
     956: 4c 89 df                     	movq	%r11, %rdi
     959: c5 f0 14 cc                  	vunpcklps	%xmm4, %xmm1, %xmm1 # xmm1 = xmm1[0],xmm4[0],xmm1[1],xmm4[1]
     95d: 49 c1 e9 20                  	shrq	$0x20, %r9
     961: 48 c1 ef 20                  	shrq	$0x20, %rdi
     965: c5 d0 16 e9                  	vmovlhps	%xmm1, %xmm5, %xmm5     # xmm5 = xmm5[0],xmm1[0]
     969: c4 c1 79 6e e3               	vmovd	%r11d, %xmm4
     96e: c5 f9 6e cb                  	vmovd	%ebx, %xmm1
     972: c5 79 6e ff                  	vmovd	%edi, %xmm15
     976: c4 c1 70 14 cd               	vunpcklps	%xmm13, %xmm1, %xmm1 # xmm1 = xmm1[0],xmm13[0],xmm1[1],xmm13[1]
     97b: c5 f8 c6 c0 00               	vshufps	$0x0, %xmm0, %xmm0, %xmm0 # xmm0 = xmm0[0,0,0,0]
     980: c4 e3 7d 18 c0 01            	vinsertf128	$0x1, %xmm0, %ymm0, %ymm0
     986: c4 c1 58 14 e7               	vunpcklps	%xmm15, %xmm4, %xmm4 # xmm4 = xmm4[0],xmm15[0],xmm4[1],xmm15[1]
     98b: c5 c8 c6 f6 00               	vshufps	$0x0, %xmm6, %xmm6, %xmm6 # xmm6 = xmm6[0,0,0,0]
     990: 48 8b 7c 24 28               	movq	0x28(%rsp), %rdi
     995: 48 8b 74 24 20               	movq	0x20(%rsp), %rsi
     99a: c5 f0 16 cc                  	vmovlhps	%xmm4, %xmm1, %xmm1     # xmm1 = xmm1[0],xmm4[0]
     99e: c4 e3 55 18 c9 01            	vinsertf128	$0x1, %xmm1, %ymm5, %ymm1
     9a4: 4d 89 a6 30 03 00 00         	movq	%r12, 0x330(%r14)
     9ab: c5 c8 59 ff                  	vmulps	%xmm7, %xmm6, %xmm7
     9af: 89 fa                        	movl	%edi, %edx
     9b1: 49 89 b6 10 03 00 00         	movq	%rsi, 0x310(%r14)
     9b8: c5 fc 59 c1                  	vmulps	%ymm1, %ymm0, %ymm0
     9bc: 4d 89 ae 38 03 00 00         	movq	%r13, 0x338(%r14)
     9c3: c5 c8 59 f5                  	vmulps	%xmm5, %xmm6, %xmm6
     9c7: 49 89 9e 40 03 00 00         	movq	%rbx, 0x340(%r14)
     9ce: 4d 89 9e 48 03 00 00         	movq	%r11, 0x348(%r14)
     9d5: 4d 89 be 58 03 00 00         	movq	%r15, 0x358(%r14)
     9dc: c4 41 79 d6 96 50 03 00 00   	vmovq	%xmm10, 0x350(%r14)
     9e5: c5 38 58 c7                  	vaddps	%xmm7, %xmm8, %xmm8
     9e9: c4 c1 78 29 96 60 03 00 00   	vmovaps	%xmm2, 0x360(%r14)
     9f2: c4 e3 7d 19 c1 01            	vextractf128	$0x1, %ymm0, %xmm1
     9f8: c5 c8 58 f3                  	vaddps	%xmm3, %xmm6, %xmm6
     9fc: c4 c1 79 6e d9               	vmovd	%r9d, %xmm3
     a01: c5 f0 c6 c9 ff               	vshufps	$0xff, %xmm1, %xmm1, %xmm1 # xmm1 = xmm1[3,3,3,3]
     a06: c5 f2 58 db                  	vaddss	%xmm3, %xmm1, %xmm3
     a0a: c5 f0 57 c9                  	vxorps	%xmm1, %xmm1, %xmm1
     a0e: c4 c1 70 5f c8               	vmaxps	%xmm8, %xmm1, %xmm1
     a13: c4 c1 79 7f b6 00 03 00 00   	vmovdqa	%xmm6, 0x300(%r14)
     a1c: c5 f9 7e d9                  	vmovd	%xmm3, %ecx
     a20: c4 c1 79 7f 8e 20 03 00 00   	vmovdqa	%xmm1, 0x320(%r14)
     a29: 48 c1 e1 20                  	shlq	$0x20, %rcx
     a2d: 48 09 ca                     	orq	%rcx, %rdx
     a30: 49 89 96 18 03 00 00         	movq	%rdx, 0x318(%r14)
     a37: 45 85 c0                     	testl	%r8d, %r8d
     a3a: 74 29                        	je	0xa65 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x995>
     a3c: c5 fa 10 74 24 14            	vmovss	0x14(%rsp), %xmm6       # xmm6 = mem[0],zero,zero,zero
     a42: c5 fa 10 5c 24 08            	vmovss	0x8(%rsp), %xmm3        # xmm3 = mem[0],zero,zero,zero
     a48: c4 e3 49 21 54 24 10 10      	vinsertps	$0x10, 0x10(%rsp), %xmm6, %xmm2 # xmm2 = xmm6[0],mem[0],xmm6[2,3]
     a50: c4 e3 61 21 4c 24 0c 10      	vinsertps	$0x10, 0xc(%rsp), %xmm3, %xmm1 # xmm1 = xmm3[0],mem[0],xmm3[2,3]
     a58: c5 f0 16 ca                  	vmovlhps	%xmm2, %xmm1, %xmm1     # xmm1 = xmm1[0],xmm2[0]
     a5c: c4 c1 78 29 8e 70 03 00 00   	vmovaps	%xmm1, 0x370(%r14)
     a65: c4 c1 7c 11 86 90 03 00 00   	vmovups	%ymm0, 0x390(%r14)
     a6e: c4 c1 78 29 be b0 03 00 00   	vmovaps	%xmm7, 0x3b0(%r14)
     a77: f6 44 24 38 0f               	testb	$0xf, 0x38(%rsp)
     a7c: 0f 85 ac 09 00 00            	jne	0x142e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     a82: 48 8b 5c 24 30               	movq	0x30(%rsp), %rbx
     a87: c5 f8 11 6c 18 10            	vmovups	%xmm5, 0x10(%rax,%rbx)
     a8d: 49 8b 96 40 01 00 00         	movq	0x140(%r14), %rdx
     a94: f6 c2 0f                     	testb	$0xf, %dl
     a97: 0f 85 91 09 00 00            	jne	0x142e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     a9d: c4 c1 79 6f 86 00 03 00 00   	vmovdqa	0x300(%r14), %xmm0
     aa6: 89 d2                        	movl	%edx, %edx
     aa8: c5 fa 7f 04 10               	vmovdqu	%xmm0, (%rax,%rdx)
     aad: 49 8b 96 40 01 00 00         	movq	0x140(%r14), %rdx
     ab4: f6 c2 0f                     	testb	$0xf, %dl
     ab7: 0f 85 71 09 00 00            	jne	0x142e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     abd: c4 c1 79 6f 86 10 03 00 00   	vmovdqa	0x310(%r14), %xmm0
     ac6: 89 d2                        	movl	%edx, %edx
     ac8: c5 fa 7f 44 10 10            	vmovdqu	%xmm0, 0x10(%rax,%rdx)
     ace: 49 8b 96 40 01 00 00         	movq	0x140(%r14), %rdx
     ad5: f6 c2 0f                     	testb	$0xf, %dl
     ad8: 0f 85 50 09 00 00            	jne	0x142e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
     ade: c4 c1 79 6f 86 20 03 00 00   	vmovdqa	0x320(%r14), %xmm0
     ae7: 89 d2                        	movl	%edx, %edx
     ae9: c5 fa 10 2d 00 00 00 00      	vmovss	(%rip), %xmm5           # xmm5 = mem[0],zero,zero,zero
                                                                        # 0xaf1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa21>
		0000000000000aed:  R_X86_64_PC32	.LC11-0x4
     af1: c5 fa 7f 44 10 20            	vmovdqu	%xmm0, 0x20(%rax,%rdx)
     af7: 49 8b 96 40 01 00 00         	movq	0x140(%r14), %rdx
     afe: 49 8b 8e 10 01 00 00         	movq	0x110(%r14), %rcx
     b05: 49 89 56 40                  	movq	%rdx, 0x40(%r14)
     b09: 89 d2                        	movl	%edx, %edx
     b0b: 49 89 4e 30                  	movq	%rcx, 0x30(%r14)
     b0f: 8b 74 10 10                  	movl	0x10(%rax,%rdx), %esi
     b13: 89 c9                        	movl	%ecx, %ecx
     b15: 41 89 b6 00 02 00 00         	movl	%esi, 0x200(%r14)
     b1c: 8b 7c 10 14                  	movl	0x14(%rax,%rdx), %edi
     b20: 41 89 be 04 02 00 00         	movl	%edi, 0x204(%r14)
     b27: 8b 54 10 18                  	movl	0x18(%rax,%rdx), %edx
     b2b: 41 89 96 0c 02 00 00         	movl	%edx, 0x20c(%r14)
     b32: 89 34 08                     	movl	%esi, (%rax,%rcx)
     b35: 41 8b 8e 04 02 00 00         	movl	0x204(%r14), %ecx
     b3c: 41 8b 46 30                  	movl	0x30(%r14), %eax
     b40: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0xb47 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa77>
		0000000000000b43:  R_X86_64_PC32	g_ee_main_mem-0x4
     b47: 89 4c 02 04                  	movl	%ecx, 0x4(%rdx,%rax)
     b4b: 41 8b 8e 0c 02 00 00         	movl	0x20c(%r14), %ecx
     b52: 41 8b 46 30                  	movl	0x30(%r14), %eax
     b56: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0xb5d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa8d>
		0000000000000b59:  R_X86_64_PC32	g_ee_main_mem-0x4
     b5d: 89 4c 02 08                  	movl	%ecx, 0x8(%rdx,%rax)
     b61: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0xb68 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa98>
		0000000000000b64:  R_X86_64_PC32	g_ee_main_mem-0x4
     b68: c4 c1 7a 10 86 0c 02 00 00   	vmovss	0x20c(%r14), %xmm0      # xmm0 = mem[0],zero,zero,zero
     b71: 41 8b 46 30                  	movl	0x30(%r14), %eax
     b75: c5 fa 59 c0                  	vmulss	%xmm0, %xmm0, %xmm0
     b79: c4 c1 7a 11 86 0c 02 00 00   	vmovss	%xmm0, 0x20c(%r14)
     b82: c5 d2 5c c8                  	vsubss	%xmm0, %xmm5, %xmm1
     b86: c4 c1 7a 10 86 04 02 00 00   	vmovss	0x204(%r14), %xmm0      # xmm0 = mem[0],zero,zero,zero
     b8f: c5 fa 59 c0                  	vmulss	%xmm0, %xmm0, %xmm0
     b93: c5 f2 5c c0                  	vsubss	%xmm0, %xmm1, %xmm0
     b97: c5 f8 14 c9                  	vunpcklps	%xmm1, %xmm0, %xmm1 # xmm1 = xmm0[0],xmm1[0],xmm0[1],xmm1[1]
     b9b: c4 c1 78 13 8e 04 02 00 00   	vmovlps	%xmm1, 0x204(%r14)
     ba4: c4 c1 7a 10 8e 00 02 00 00   	vmovss	0x200(%r14), %xmm1      # xmm1 = mem[0],zero,zero,zero
     bad: c5 f2 59 c9                  	vmulss	%xmm1, %xmm1, %xmm1
     bb1: c5 fa 5c c1                  	vsubss	%xmm1, %xmm0, %xmm0
     bb5: c5 f8 54 05 00 00 00 00      	vandps	(%rip), %xmm0, %xmm0    # 0xbbd <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xaed>
		0000000000000bb9:  R_X86_64_PC32	.LC14-0x4
     bbd: c5 fa 51 c0                  	vsqrtss	%xmm0, %xmm0, %xmm0
     bc1: c4 c1 7a 11 86 00 02 00 00   	vmovss	%xmm0, 0x200(%r14)
     bca: c5 fa 11 44 02 0c            	vmovss	%xmm0, 0xc(%rdx,%rax)
     bd0: 49 63 86 00 02 00 00         	movslq	0x200(%r14), %rax
     bd7: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0xbde <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb0e>
		0000000000000bda:  R_X86_64_PC32	g_ee_main_mem-0x4
     bde: 49 89 46 40                  	movq	%rax, 0x40(%r14)
     be2: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0xbe9 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb19>
		0000000000000be5:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
     be9: 48 63 10                     	movslq	(%rax), %rdx
     bec: 89 d0                        	movl	%edx, %eax
     bee: 49 89 56 30                  	movq	%rdx, 0x30(%r14)
     bf2: 41 8b 04 01                  	movl	(%r9,%rax), %eax
     bf6: 41 89 86 00 02 00 00         	movl	%eax, 0x200(%r14)
     bfd: 0f b6 c0                     	movzbl	%al, %eax
     c00: 48 83 e8 0a                  	subq	$0xa, %rax
     c04: 49 89 46 30                  	movq	%rax, 0x30(%r14)
     c08: 0f 88 c8 00 00 00            	js	0xcd6 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc06>
     c0e: 49 8b 86 50 01 00 00         	movq	0x150(%r14), %rax
     c15: 48 8b 0d 00 00 00 00         	movq	(%rip), %rcx            # 0xc1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb4c>
		0000000000000c18:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
     c1c: c4 c1 7a 7e 96 10 01 00 00   	vmovq	0x110(%r14), %xmm2      # xmm2 = mem[0],zero
     c25: 49 63 96 f0 01 00 00         	movslq	0x1f0(%r14), %rdx
     c2c: c4 c1 7a 7e b6 a0 00 00 00   	vmovq	0xa0(%r14), %xmm6       # xmm6 = mem[0],zero
     c35: 48 83 c0 50                  	addq	$0x50, %rax
     c39: 48 63 09                     	movslq	(%rcx), %rcx
     c3c: c4 e1 f9 6e e8               	vmovq	%rax, %xmm5
     c41: c4 c3 d1 22 46 70 01         	vpinsrq	$0x1, 0x70(%r14), %xmm5, %xmm0
     c48: c5 e9 6c ca                  	vpunpcklqdq	%xmm2, %xmm2, %xmm1 # xmm1 = xmm2[0,0]
     c4c: c4 c1 7a 7e be 80 00 00 00   	vmovq	0x80(%r14), %xmm7       # xmm7 = mem[0],zero
     c55: c4 c3 c9 22 9e b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%r14), %xmm6, %xmm3
     c5f: 49 89 8e 90 01 00 00         	movq	%rcx, 0x190(%r14)
     c66: 48 89 cf                     	movq	%rcx, %rdi
     c69: c4 e3 75 18 c8 01            	vinsertf128	$0x1, %xmm0, %ymm1, %ymm1
     c6f: 49 89 46 60                  	movq	%rax, 0x60(%r14)
     c73: c4 c3 c1 22 86 90 00 00 00 01	vpinsrq	$0x1, 0x90(%r14), %xmm7, %xmm0
     c7d: 49 89 56 20                  	movq	%rdx, 0x20(%r14)
     c81: c4 e3 7d 18 c3 01            	vinsertf128	$0x1, %xmm3, %ymm0, %ymm0
     c87: c4 c1 79 d6 56 40            	vmovq	%xmm2, 0x40(%r14)
     c8d: c4 c1 79 d6 56 50            	vmovq	%xmm2, 0x50(%r14)
     c93: c5 fd 7f 8c 24 c0 00 00 00   	vmovdqa	%ymm1, 0xc0(%rsp)
     c9c: c5 fd 7f 84 24 e0 00 00 00   	vmovdqa	%ymm0, 0xe0(%rsp)
     ca5: 85 c9                        	testl	%ecx, %ecx
     ca7: 0f 84 5f 07 00 00            	je	0x140c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     cad: 49 8b 8e 60 01 00 00         	movq	0x160(%r14), %rcx
     cb4: 4d 8b 86 70 01 00 00         	movq	0x170(%r14), %r8
     cbb: 89 ff                        	movl	%edi, %edi
     cbd: 31 d2                        	xorl	%edx, %edx
     cbf: 4c 01 cf                     	addq	%r9, %rdi
     cc2: 48 8d b4 24 c0 00 00 00      	leaq	0xc0(%rsp), %rsi
     cca: c5 f8 77                     	vzeroupper
     ccd: e8 00 00 00 00               	callq	0xcd2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc02>
		0000000000000cce:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     cd2: 49 89 46 20                  	movq	%rax, 0x20(%r14)
     cd6: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0xcdd <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc0d>
		0000000000000cd9:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
     cdd: 49 63 96 f0 01 00 00         	movslq	0x1f0(%r14), %rdx
     ce4: c4 c1 7a 7e be a0 00 00 00   	vmovq	0xa0(%r14), %xmm7       # xmm7 = mem[0],zero
     ced: c4 c1 7a 7e ae 80 00 00 00   	vmovq	0x80(%r14), %xmm5       # xmm5 = mem[0],zero
     cf6: c4 c3 c1 22 8e b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%r14), %xmm7, %xmm1
     d00: 48 63 00                     	movslq	(%rax), %rax
     d03: 49 89 56 20                  	movq	%rdx, 0x20(%r14)
     d07: c4 c3 d1 22 96 90 00 00 00 01	vpinsrq	$0x1, 0x90(%r14), %xmm5, %xmm2
     d11: c4 c1 7a 7e 86 10 01 00 00   	vmovq	0x110(%r14), %xmm0      # xmm0 = mem[0],zero
     d1a: 49 89 86 90 01 00 00         	movq	%rax, 0x190(%r14)
     d21: 48 89 c7                     	movq	%rax, %rdi
     d24: 49 8b 86 50 01 00 00         	movq	0x150(%r14), %rax
     d2b: c4 e3 6d 18 d1 01            	vinsertf128	$0x1, %xmm1, %ymm2, %ymm2
     d31: c4 c1 79 d6 46 40            	vmovq	%xmm0, 0x40(%r14)
     d37: 48 83 c0 50                  	addq	$0x50, %rax
     d3b: c4 c1 79 d6 46 50            	vmovq	%xmm0, 0x50(%r14)
     d41: c5 f9 6c c0                  	vpunpcklqdq	%xmm0, %xmm0, %xmm0 # xmm0 = xmm0[0,0]
     d45: c4 e1 f9 6e f0               	vmovq	%rax, %xmm6
     d4a: c4 c3 c9 22 4e 70 01         	vpinsrq	$0x1, 0x70(%r14), %xmm6, %xmm1
     d51: 49 89 46 60                  	movq	%rax, 0x60(%r14)
     d55: c5 fd 7f 94 24 20 01 00 00   	vmovdqa	%ymm2, 0x120(%rsp)
     d5e: c4 e3 7d 18 c1 01            	vinsertf128	$0x1, %xmm1, %ymm0, %ymm0
     d64: c5 fd 7f 84 24 00 01 00 00   	vmovdqa	%ymm0, 0x100(%rsp)
     d6d: 85 ff                        	testl	%edi, %edi
     d6f: 0f 84 97 06 00 00            	je	0x140c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
     d75: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0xd7c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcac>
		0000000000000d78:  R_X86_64_PC32	g_ee_main_mem-0x4
     d7c: 49 8b 8e 60 01 00 00         	movq	0x160(%r14), %rcx
     d83: 89 ff                        	movl	%edi, %edi
     d85: 31 d2                        	xorl	%edx, %edx
     d87: 4d 8b 86 70 01 00 00         	movq	0x170(%r14), %r8
     d8e: 48 8d b4 24 00 01 00 00      	leaq	0x100(%rsp), %rsi
     d96: 4c 01 cf                     	addq	%r9, %rdi
     d99: c5 f8 77                     	vzeroupper
     d9c: e8 00 00 00 00               	callq	0xda1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcd1>
		0000000000000d9d:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
     da1: 49 8b 96 10 01 00 00         	movq	0x110(%r14), %rdx
     da8: c5 f0 57 c9                  	vxorps	%xmm1, %xmm1, %xmm1
     dac: 49 89 46 20                  	movq	%rax, 0x20(%r14)
     db0: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0xdb7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xce7>
		0000000000000db3:  R_X86_64_PC32	g_ee_main_mem-0x4
     db7: 49 8b 86 40 01 00 00         	movq	0x140(%r14), %rax
     dbe: 89 d1                        	movl	%edx, %ecx
     dc0: 49 89 56 30                  	movq	%rdx, 0x30(%r14)
     dc4: 49 89 46 40                  	movq	%rax, 0x40(%r14)
     dc8: c4 c1 79 6e 44 09 0c         	vmovd	0xc(%r9,%rcx), %xmm0    # xmm0 = mem[0],zero,zero,zero
     dcf: 41 c7 86 04 02 00 00 00 00 00 00     	movl	$0x0, 0x204(%r14)
     dda: c4 c1 79 7e 86 00 02 00 00   	vmovd	%xmm0, 0x200(%r14)
     de3: c5 f8 2f c8                  	vcomiss	%xmm0, %xmm1
     de7: 0f 87 c3 01 00 00            	ja	0xfb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     ded: a8 0f                        	testb	$0xf, %al
     def: 0f 85 5b 06 00 00            	jne	0x1450 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     df5: 89 c0                        	movl	%eax, %eax
     df7: 83 e2 0f                     	andl	$0xf, %edx
     dfa: 49 8d 7c 01 10               	leaq	0x10(%r9,%rax), %rdi
     dff: 48 8b 07                     	movq	(%rdi), %rax
     e02: 48 8b 77 08                  	movq	0x8(%rdi), %rsi
     e06: 49 89 86 90 02 00 00         	movq	%rax, 0x290(%r14)
     e0d: 49 89 b6 98 02 00 00         	movq	%rsi, 0x298(%r14)
     e14: 0f 85 36 06 00 00            	jne	0x1450 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     e1a: 49 8b 14 09                  	movq	(%r9,%rcx), %rdx
     e1e: 49 8b 44 09 08               	movq	0x8(%r9,%rcx), %rax
     e23: c5 e8 57 d2                  	vxorps	%xmm2, %xmm2, %xmm2
     e27: 48 c1 ee 20                  	shrq	$0x20, %rsi
     e2b: 49 89 96 a0 02 00 00         	movq	%rdx, 0x2a0(%r14)
     e32: c5 f9 6e c2                  	vmovd	%edx, %xmm0
     e36: 48 c1 ea 20                  	shrq	$0x20, %rdx
     e3a: c5 f9 6e fa                  	vmovd	%edx, %xmm7
     e3e: 49 89 86 a8 02 00 00         	movq	%rax, 0x2a8(%r14)
     e45: c5 f8 14 c7                  	vunpcklps	%xmm7, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm7[0],xmm0[1],xmm7[1]
     e49: c5 f9 6e fe                  	vmovd	%esi, %xmm7
     e4d: c5 fa 7e c0                  	vmovq	%xmm0, %xmm0            # xmm0 = xmm0[0],zero
     e51: c5 f8 58 c2                  	vaddps	%xmm2, %xmm0, %xmm0
     e55: c5 f9 6e d0                  	vmovd	%eax, %xmm2
     e59: c5 ea 58 c9                  	vaddss	%xmm1, %xmm2, %xmm1
     e5d: c4 c1 78 13 86 90 02 00 00   	vmovlps	%xmm0, 0x290(%r14)
     e66: c4 c1 7a 11 8e 98 02 00 00   	vmovss	%xmm1, 0x298(%r14)
     e6f: c5 f0 14 cf                  	vunpcklps	%xmm7, %xmm1, %xmm1 # xmm1 = xmm1[0],xmm7[0],xmm1[1],xmm7[1]
     e73: c5 f8 16 c1                  	vmovlhps	%xmm1, %xmm0, %xmm0     # xmm0 = xmm0[0],xmm1[0]
     e77: c5 f8 11 07                  	vmovups	%xmm0, (%rdi)
     e7b: 49 8b 86 90 02 00 00         	movq	0x290(%r14), %rax
     e82: 49 8b 96 98 02 00 00         	movq	0x298(%r14), %rdx
     e89: c4 c1 78 28 86 20 03 00 00   	vmovaps	0x320(%r14), %xmm0
     e92: 49 89 46 40                  	movq	%rax, 0x40(%r14)
     e96: 49 8b 86 50 01 00 00         	movq	0x150(%r14), %rax
     e9d: 49 89 56 48                  	movq	%rdx, 0x48(%r14)
     ea1: c4 c1 78 11 46 30            	vmovups	%xmm0, 0x30(%r14)
     ea7: 89 c2                        	movl	%eax, %edx
     ea9: 49 63 4c 11 68               	movslq	0x68(%r9,%rdx), %rcx
     eae: 49 89 4e 40                  	movq	%rcx, 0x40(%r14)
     eb2: 48 89 ca                     	movq	%rcx, %rdx
     eb5: 83 e1 04                     	andl	$0x4, %ecx
     eb8: 89 cb                        	movl	%ecx, %ebx
     eba: 49 89 5e 50                  	movq	%rbx, 0x50(%r14)
     ebe: f6 c2 02                     	testb	$0x2, %dl
     ec1: 74 33                        	je	0xef6 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe26>
     ec3: c4 e1 f9 7e c6               	vmovq	%xmm0, %rsi
     ec8: 41 c7 46 60 00 00 00 00      	movl	$0x0, 0x60(%r14)
     ed0: c4 c3 79 16 46 64 02         	vpextrd	$0x2, %xmm0, 0x64(%r14)
     ed7: c4 c3 79 16 46 6c 03         	vpextrd	$0x3, %xmm0, 0x6c(%r14)
     ede: 41 c7 46 68 00 00 00 00      	movl	$0x0, 0x68(%r14)
     ee6: 48 85 f6                     	testq	%rsi, %rsi
     ee9: 75 0b                        	jne	0xef6 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe26>
     eeb: 49 83 7e 60 00               	cmpq	$0x0, 0x60(%r14)
     ef0: 0f 84 41 f5 ff ff            	je	0x437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     ef6: 83 e2 01                     	andl	$0x1, %edx
     ef9: 89 d3                        	movl	%edx, %ebx
     efb: 49 89 5e 40                  	movq	%rbx, 0x40(%r14)
     eff: 85 c9                        	testl	%ecx, %ecx
     f01: 74 29                        	je	0xf2c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe5c>
     f03: 49 c7 46 38 00 00 00 00      	movq	$0x0, 0x38(%r14)
     f0b: c4 c3 79 16 46 34 03         	vpextrd	$0x3, %xmm0, 0x34(%r14)
     f12: c4 c3 79 16 46 38 02         	vpextrd	$0x2, %xmm0, 0x38(%r14)
     f19: 41 c7 46 30 00 00 00 00      	movl	$0x0, 0x30(%r14)
     f21: 49 83 7e 30 00               	cmpq	$0x0, 0x30(%r14)
     f26: 0f 8e 0b f5 ff ff            	jle	0x437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     f2c: 85 d2                        	testl	%edx, %edx
     f2e: 0f 84 fc f3 ff ff            	je	0x330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     f34: c4 c1 78 28 86 00 03 00 00   	vmovaps	0x300(%r14), %xmm0
     f3d: c4 c1 78 11 46 30            	vmovups	%xmm0, 0x30(%r14)
     f43: c4 c3 79 16 46 34 03         	vpextrd	$0x3, %xmm0, 0x34(%r14)
     f4a: c4 c1 78 28 86 10 03 00 00   	vmovaps	0x310(%r14), %xmm0
     f53: 41 c7 46 30 00 00 00 00      	movl	$0x0, 0x30(%r14)
     f5b: 49 8b 56 30                  	movq	0x30(%r14), %rdx
     f5f: c4 c1 78 11 46 30            	vmovups	%xmm0, 0x30(%r14)
     f65: 48 85 d2                     	testq	%rdx, %rdx
     f68: 0f 88 c9 f4 ff ff            	js	0x437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     f6e: 49 c7 46 38 00 00 00 00      	movq	$0x0, 0x38(%r14)
     f76: c4 c3 79 16 46 34 03         	vpextrd	$0x3, %xmm0, 0x34(%r14)
     f7d: c4 c3 79 16 46 38 02         	vpextrd	$0x2, %xmm0, 0x38(%r14)
     f84: 41 c7 46 30 00 00 00 00      	movl	$0x0, 0x30(%r14)
     f8c: 49 83 7e 30 00               	cmpq	$0x0, 0x30(%r14)
     f91: 0f 88 a0 f4 ff ff            	js	0x437 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x367>
     f97: e9 94 f3 ff ff               	jmp	0x330 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
     f9c: 0f 1f 40 00                  	nopl	(%rax)
     fa0: 49 89 56 30                  	movq	%rdx, 0x30(%r14)
     fa4: e9 0f f4 ff ff               	jmp	0x3b8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2e8>
     fa9: 0f 1f 80 00 00 00 00         	nopl	(%rax)
     fb0: a8 0f                        	testb	$0xf, %al
     fb2: 0f 85 98 04 00 00            	jne	0x1450 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     fb8: 89 c0                        	movl	%eax, %eax
     fba: 83 e2 0f                     	andl	$0xf, %edx
     fbd: 49 8d 7c 01 10               	leaq	0x10(%r9,%rax), %rdi
     fc2: 48 8b 07                     	movq	(%rdi), %rax
     fc5: 48 8b 77 08                  	movq	0x8(%rdi), %rsi
     fc9: 49 89 86 90 02 00 00         	movq	%rax, 0x290(%r14)
     fd0: 49 89 b6 98 02 00 00         	movq	%rsi, 0x298(%r14)
     fd7: 0f 85 73 04 00 00            	jne	0x1450 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
     fdd: 49 8b 04 09                  	movq	(%r9,%rcx), %rax
     fe1: 49 8b 54 09 08               	movq	0x8(%r9,%rcx), %rdx
     fe6: c5 f8 57 c0                  	vxorps	%xmm0, %xmm0, %xmm0
     fea: 48 c1 ee 20                  	shrq	$0x20, %rsi
     fee: c5 f9 6e ee                  	vmovd	%esi, %xmm5
     ff2: 49 89 86 a0 02 00 00         	movq	%rax, 0x2a0(%r14)
     ff9: c5 f9 6e d0                  	vmovd	%eax, %xmm2
     ffd: 48 c1 e8 20                  	shrq	$0x20, %rax
    1001: c5 f9 6e d8                  	vmovd	%eax, %xmm3
    1005: 49 89 96 a8 02 00 00         	movq	%rdx, 0x2a8(%r14)
    100c: c5 e8 14 d3                  	vunpcklps	%xmm3, %xmm2, %xmm2 # xmm2 = xmm2[0],xmm3[0],xmm2[1],xmm3[1]
    1010: c5 fa 7e d2                  	vmovq	%xmm2, %xmm2            # xmm2 = xmm2[0],zero
    1014: c5 f8 5c c2                  	vsubps	%xmm2, %xmm0, %xmm0
    1018: c5 f9 6e d2                  	vmovd	%edx, %xmm2
    101c: c5 f2 5c ca                  	vsubss	%xmm2, %xmm1, %xmm1
    1020: c4 c1 78 13 86 90 02 00 00   	vmovlps	%xmm0, 0x290(%r14)
    1029: c4 c1 7a 11 8e 98 02 00 00   	vmovss	%xmm1, 0x298(%r14)
    1032: c5 f0 14 cd                  	vunpcklps	%xmm5, %xmm1, %xmm1 # xmm1 = xmm1[0],xmm5[0],xmm1[1],xmm5[1]
    1036: c5 f8 16 c1                  	vmovlhps	%xmm1, %xmm0, %xmm0     # xmm0 = xmm0[0],xmm1[0]
    103a: c5 f8 11 07                  	vmovups	%xmm0, (%rdi)
    103e: 49 8b 86 90 02 00 00         	movq	0x290(%r14), %rax
    1045: 49 8b 96 98 02 00 00         	movq	0x298(%r14), %rdx
    104c: e9 38 fe ff ff               	jmp	0xe89 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb9>
    1051: 0f 1f 80 00 00 00 00         	nopl	(%rax)
    1058: 49 8b 7e 30                  	movq	0x30(%r14), %rdi
    105c: 49 c1 ea 20                  	shrq	$0x20, %r10
    1060: 49 8b 56 38                  	movq	0x38(%r14), %rdx
    1064: c5 fa 7e c0                  	vmovq	%xmm0, %xmm0            # xmm0 = xmm0[0],zero
    1068: c5 b2 59 ed                  	vmulss	%xmm5, %xmm9, %xmm5
    106c: c4 41 79 6e da               	vmovd	%r10d, %xmm11
    1071: 49 ba 00 00 00 00 ff ff ff ff	movabsq	$-0x100000000, %r10     # imm = 0xFFFFFFFF00000000
    107b: c5 32 59 ce                  	vmulss	%xmm6, %xmm9, %xmm9
    107f: c5 79 6e e7                  	vmovd	%edi, %xmm12
    1083: 48 c1 ef 20                  	shrq	$0x20, %rdi
    1087: c4 41 1a 59 fb               	vmulss	%xmm11, %xmm12, %xmm15
    108c: c5 d2 58 ec                  	vaddss	%xmm4, %xmm5, %xmm5
    1090: c4 41 32 58 ce               	vaddss	%xmm14, %xmm9, %xmm9
    1095: c5 7a 11 7c 24 08            	vmovss	%xmm15, 0x8(%rsp)
    109b: c5 79 6e ff                  	vmovd	%edi, %xmm15
    109f: c4 41 22 59 ef               	vmulss	%xmm15, %xmm11, %xmm13
    10a4: c5 7a 10 3d 00 00 00 00      	vmovss	(%rip), %xmm15          # xmm15 = mem[0],zero,zero,zero
                                                                        # 0x10ac <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xfdc>
		00000000000010a8:  R_X86_64_PC32	.LC11-0x4
    10ac: c4 41 02 5c e4               	vsubss	%xmm12, %xmm15, %xmm12
    10b1: c4 41 1a 59 e3               	vmulss	%xmm11, %xmm12, %xmm12
    10b6: c5 7a 11 6c 24 0c            	vmovss	%xmm13, 0xc(%rsp)
    10bc: c5 79 6e ea                  	vmovd	%edx, %xmm13
    10c0: 4c 89 ea                     	movq	%r13, %rdx
    10c3: c4 41 22 59 ed               	vmulss	%xmm13, %xmm11, %xmm13
    10c8: 4c 21 d2                     	andq	%r10, %rdx
    10cb: c4 41 02 5c e4               	vsubss	%xmm12, %xmm15, %xmm12
    10d0: c5 7a 11 6c 24 14            	vmovss	%xmm13, 0x14(%rsp)
    10d6: c4 c1 72 59 cc               	vmulss	%xmm12, %xmm1, %xmm1
    10db: c4 c1 7a 12 f4               	vmovsldup	%xmm12, %xmm6   # xmm6 = xmm12[0,0,2,2]
    10e0: c5 7a 11 64 24 10            	vmovss	%xmm12, 0x10(%rsp)
    10e6: c4 c1 52 59 ec               	vmulss	%xmm12, %xmm5, %xmm5
    10eb: c4 41 32 59 cc               	vmulss	%xmm12, %xmm9, %xmm9
    10f0: c5 fa 7e f6                  	vmovq	%xmm6, %xmm6            # xmm6 = xmm6[0],zero
    10f4: c5 c8 59 c0                  	vmulps	%xmm0, %xmm6, %xmm0
    10f8: c5 f9 7e cf                  	vmovd	%xmm1, %edi
    10fc: 48 09 fa                     	orq	%rdi, %rdx
    10ff: 49 89 d5                     	movq	%rdx, %r13
    1102: c4 c1 f9 7e c4               	vmovq	%xmm0, %r12
    1107: e9 24 f8 ff ff               	jmp	0x930 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x860>
    110c: 0f 1f 40 00                  	nopl	(%rax)
    1110: 49 8b 86 d0 01 00 00         	movq	0x1d0(%r14), %rax
    1117: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x111e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x104e>
		000000000000111a:  R_X86_64_PC32	g_ee_main_mem-0x4
    111e: c4 c1 79 6f 86 c0 01 00 00   	vmovdqa	0x1c0(%r14), %xmm0
    1127: 48 83 e8 60                  	subq	$0x60, %rax
    112b: 49 89 86 d0 01 00 00         	movq	%rax, 0x1d0(%r14)
    1132: 83 e0 f0                     	andl	$-0x10, %eax
    1135: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    113b: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
    1142: c4 c1 79 6f 86 50 01 00 00   	vmovdqa	0x150(%r14), %xmm0
    114b: 83 c0 10                     	addl	$0x10, %eax
    114e: 83 e0 f0                     	andl	$-0x10, %eax
    1151: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1157: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
    115e: c4 c1 79 6f 86 40 01 00 00   	vmovdqa	0x140(%r14), %xmm0
    1167: 83 c0 20                     	addl	$0x20, %eax
    116a: 83 e0 f0                     	andl	$-0x10, %eax
    116d: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1173: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
    117a: c4 c1 79 6f 86 00 01 00 00   	vmovdqa	0x100(%r14), %xmm0
    1183: 83 c0 30                     	addl	$0x30, %eax
    1186: 83 e0 f0                     	andl	$-0x10, %eax
    1189: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    118f: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
    1196: c4 c1 79 6f 86 30 01 00 00   	vmovdqa	0x130(%r14), %xmm0
    119f: 83 c0 40                     	addl	$0x40, %eax
    11a2: 83 e0 f0                     	andl	$-0x10, %eax
    11a5: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    11ab: 41 8b 86 d0 01 00 00         	movl	0x1d0(%r14), %eax
    11b2: c4 c1 79 6f 86 20 01 00 00   	vmovdqa	0x120(%r14), %xmm0
    11bb: 83 c0 50                     	addl	$0x50, %eax
    11be: 83 e0 f0                     	andl	$-0x10, %eax
    11c1: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    11c7: 49 8b 96 40 01 00 00         	movq	0x140(%r14), %rdx
    11ce: c4 c1 7a 7e 86 c0 01 00 00   	vmovq	0x1c0(%r14), %xmm0      # xmm0 = mem[0],zero
    11d7: c4 c1 7a 7e 96 50 01 00 00   	vmovq	0x150(%r14), %xmm2      # xmm2 = mem[0],zero
    11e0: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x11e7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1117>
		00000000000011e3:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
    11e7: c4 c1 7a 7e b6 a0 00 00 00   	vmovq	0xa0(%r14), %xmm6       # xmm6 = mem[0],zero
    11f0: c4 c1 79 d6 46 40            	vmovq	%xmm0, 0x40(%r14)
    11f6: c4 c1 79 d6 56 60            	vmovq	%xmm2, 0x60(%r14)
    11fc: c4 e3 e9 22 d2 01            	vpinsrq	$0x1, %rdx, %xmm2, %xmm2
    1202: 49 89 56 70                  	movq	%rdx, 0x70(%r14)
    1206: 48 63 08                     	movslq	(%rax), %rcx
    1209: 49 89 8e 90 01 00 00         	movq	%rcx, 0x190(%r14)
    1210: 48 89 c8                     	movq	%rcx, %rax
    1213: 49 63 8e f0 01 00 00         	movslq	0x1f0(%r14), %rcx
    121a: 49 89 4e 20                  	movq	%rcx, 0x20(%r14)
    121e: c4 c3 c9 22 9e b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%r14), %xmm6, %xmm3
    1228: c4 c1 7a 7e be 80 00 00 00   	vmovq	0x80(%r14), %xmm7       # xmm7 = mem[0],zero
    1231: c4 c3 f9 22 46 50 01         	vpinsrq	$0x1, 0x50(%r14), %xmm0, %xmm0
    1238: c4 c3 c1 22 8e 90 00 00 00 01	vpinsrq	$0x1, 0x90(%r14), %xmm7, %xmm1
    1242: c4 e3 7d 18 c2 01            	vinsertf128	$0x1, %xmm2, %ymm0, %ymm0
    1248: c5 fd 7f 84 24 80 00 00 00   	vmovdqa	%ymm0, 0x80(%rsp)
    1251: c4 e3 75 18 cb 01            	vinsertf128	$0x1, %xmm3, %ymm1, %ymm1
    1257: c5 fd 7f 8c 24 a0 00 00 00   	vmovdqa	%ymm1, 0xa0(%rsp)
    1260: 85 c0                        	testl	%eax, %eax
    1262: 0f 84 a4 01 00 00            	je	0x140c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x133c>
    1268: 49 8b 8e 60 01 00 00         	movq	0x160(%r14), %rcx
    126f: 4d 8b 86 70 01 00 00         	movq	0x170(%r14), %r8
    1276: 89 c0                        	movl	%eax, %eax
    1278: 31 d2                        	xorl	%edx, %edx
    127a: 48 8d b4 24 80 00 00 00      	leaq	0x80(%rsp), %rsi
    1282: 49 8d 3c 01                  	leaq	(%r9,%rax), %rdi
    1286: c5 f8 77                     	vzeroupper
    1289: e8 00 00 00 00               	callq	0x128e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x11be>
		000000000000128a:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    128e: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x1295 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x11c5>
		0000000000001291:  R_X86_64_PC32	g_ee_main_mem-0x4
    1295: 49 89 46 20                  	movq	%rax, 0x20(%r14)
    1299: 49 8b 86 d0 01 00 00         	movq	0x1d0(%r14), %rax
    12a0: 48 89 c1                     	movq	%rax, %rcx
    12a3: 83 e1 f0                     	andl	$-0x10, %ecx
    12a6: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    12ab: 8d 48 10                     	leal	0x10(%rax), %ecx
    12ae: 83 e1 f0                     	andl	$-0x10, %ecx
    12b1: c4 c1 7a 7f 86 c0 01 00 00   	vmovdqu	%xmm0, 0x1c0(%r14)
    12ba: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    12bf: 8d 48 20                     	leal	0x20(%rax), %ecx
    12c2: 83 e1 f0                     	andl	$-0x10, %ecx
    12c5: c4 c1 7a 7f 86 50 01 00 00   	vmovdqu	%xmm0, 0x150(%r14)
    12ce: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    12d3: 8d 48 30                     	leal	0x30(%rax), %ecx
    12d6: 83 e1 f0                     	andl	$-0x10, %ecx
    12d9: c4 c1 7a 7f 86 40 01 00 00   	vmovdqu	%xmm0, 0x140(%r14)
    12e2: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    12e7: 8d 48 40                     	leal	0x40(%rax), %ecx
    12ea: 83 e1 f0                     	andl	$-0x10, %ecx
    12ed: c4 c1 7a 7f 86 00 01 00 00   	vmovdqu	%xmm0, 0x100(%r14)
    12f6: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    12fb: 8d 48 50                     	leal	0x50(%rax), %ecx
    12fe: 48 83 c0 60                  	addq	$0x60, %rax
    1302: 83 e1 f0                     	andl	$-0x10, %ecx
    1305: c4 c1 7a 7f 86 30 01 00 00   	vmovdqu	%xmm0, 0x130(%r14)
    130e: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    1313: 49 89 86 d0 01 00 00         	movq	%rax, 0x1d0(%r14)
    131a: c4 c1 7a 7f 86 20 01 00 00   	vmovdqu	%xmm0, 0x120(%r14)
    1323: e9 b6 f4 ff ff               	jmp	0x7de <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x70e>
    1328: 0f 1f 84 00 00 00 00 00      	nopl	(%rax,%rax)
    1330: 49 8b 86 d0 01 00 00         	movq	0x1d0(%r14), %rax
    1337: 49 89 4e 20                  	movq	%rcx, 0x20(%r14)
    133b: 89 c2                        	movl	%eax, %edx
    133d: 49 8b 34 11                  	movq	(%r9,%rdx), %rsi
    1341: 49 89 b6 f0 01 00 00         	movq	%rsi, 0x1f0(%r14)
    1348: 49 8b 54 11 08               	movq	0x8(%r9,%rdx), %rdx
    134d: 49 89 96 e0 01 00 00         	movq	%rdx, 0x1e0(%r14)
    1354: 8d 90 90 00 00 00            	leal	0x90(%rax), %edx
    135a: 83 e2 f0                     	andl	$-0x10, %edx
    135d: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    1363: 8d 90 80 00 00 00            	leal	0x80(%rax), %edx
    1369: 83 e2 f0                     	andl	$-0x10, %edx
    136c: c4 c1 7a 7f 86 c0 01 00 00   	vmovdqu	%xmm0, 0x1c0(%r14)
    1375: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    137b: 8d 50 70                     	leal	0x70(%rax), %edx
    137e: 83 e2 f0                     	andl	$-0x10, %edx
    1381: c4 c1 7a 7f 86 50 01 00 00   	vmovdqu	%xmm0, 0x150(%r14)
    138a: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    1390: 8d 50 60                     	leal	0x60(%rax), %edx
    1393: 83 e2 f0                     	andl	$-0x10, %edx
    1396: c4 c1 7a 7f 86 40 01 00 00   	vmovdqu	%xmm0, 0x140(%r14)
    139f: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    13a5: 8d 50 50                     	leal	0x50(%rax), %edx
    13a8: 83 e2 f0                     	andl	$-0x10, %edx
    13ab: c4 c1 7a 7f 86 30 01 00 00   	vmovdqu	%xmm0, 0x130(%r14)
    13b4: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    13ba: 8d 50 40                     	leal	0x40(%rax), %edx
    13bd: 83 e2 f0                     	andl	$-0x10, %edx
    13c0: c4 c1 7a 7f 86 20 01 00 00   	vmovdqu	%xmm0, 0x120(%r14)
    13c9: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    13cf: 8d 50 30                     	leal	0x30(%rax), %edx
    13d2: 48 05 a0 00 00 00            	addq	$0xa0, %rax
    13d8: 83 e2 f0                     	andl	$-0x10, %edx
    13db: c4 c1 7a 7f 86 10 01 00 00   	vmovdqu	%xmm0, 0x110(%r14)
    13e4: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    13ea: 49 89 86 d0 01 00 00         	movq	%rax, 0x1d0(%r14)
    13f1: 48 89 c8                     	movq	%rcx, %rax
    13f4: c4 c1 7a 7f 86 00 01 00 00   	vmovdqu	%xmm0, 0x100(%r14)
    13fd: 48 8d 65 d8                  	leaq	-0x28(%rbp), %rsp
    1401: 5b                           	popq	%rbx
    1402: 41 5c                        	popq	%r12
    1404: 41 5d                        	popq	%r13
    1406: 41 5e                        	popq	%r14
    1408: 41 5f                        	popq	%r15
    140a: 5d                           	popq	%rbp
    140b: c3                           	retq
    140c: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		000000000000140e:  R_X86_64_32	.rodata.str1.1+0xe
    1412: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000001413:  R_X86_64_32	.rodata.str1.8+0xa8
    1417: ba 90 01 00 00               	movl	$0x190, %edx            # imm = 0x190
    141c: be 00 00 00 00               	movl	$0x0, %esi
		000000000000141d:  R_X86_64_32	.rodata.str1.8+0x38
    1421: bf 00 00 00 00               	movl	$0x0, %edi
		0000000000001422:  R_X86_64_32	.rodata.str1.1+0xf
    1426: c5 f8 77                     	vzeroupper
    1429: e8 00 00 00 00               	callq	0x142e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x135e>
		000000000000142a:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    142e: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		0000000000001430:  R_X86_64_32	.rodata.str1.1+0xe
    1434: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000001435:  R_X86_64_32	.rodata.str1.8+0x1d8
    1439: ba c0 01 00 00               	movl	$0x1c0, %edx            # imm = 0x1C0
    143e: be 00 00 00 00               	movl	$0x0, %esi
		000000000000143f:  R_X86_64_32	.rodata.str1.8+0x38
    1443: bf 00 00 00 00               	movl	$0x0, %edi
		0000000000001444:  R_X86_64_32	.rodata.str1.8+0x210
    1448: c5 f8 77                     	vzeroupper
    144b: e8 00 00 00 00               	callq	0x1450 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1380>
		000000000000144c:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    1450: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		0000000000001452:  R_X86_64_32	.rodata.str1.1+0xe
    1456: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000001457:  R_X86_64_32	.rodata.str1.8
    145b: ba 58 01 00 00               	movl	$0x158, %edx            # imm = 0x158
    1460: be 00 00 00 00               	movl	$0x0, %esi
		0000000000001461:  R_X86_64_32	.rodata.str1.8+0x38
    1465: bf 00 00 00 00               	movl	$0x0, %edi
		0000000000001466:  R_X86_64_32	.rodata.str1.8+0x78
    146a: e8 00 00 00 00               	callq	0x146f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x139f>
		000000000000146b:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    146f: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		0000000000001471:  R_X86_64_32	.rodata.str1.1+0xe
    1475: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000001476:  R_X86_64_32	.rodata.str1.8+0xd8
    147a: ba 00 01 00 00               	movl	$0x100, %edx            # imm = 0x100
    147f: be 00 00 00 00               	movl	$0x0, %esi
		0000000000001480:  R_X86_64_32	.rodata.str1.8+0x110
    1484: bf 00 00 00 00               	movl	$0x0, %edi
		0000000000001485:  R_X86_64_32	.rodata.str1.8+0x1a8
    1489: e8 00 00 00 00               	callq	0x148e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13be>
		000000000000148a:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    148e: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		0000000000001490:  R_X86_64_32	.rodata.str1.1+0xe
    1494: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000001495:  R_X86_64_32	.rodata.str1.8+0xd8
    1499: ba fa 00 00 00               	movl	$0xfa, %edx
    149e: be 00 00 00 00               	movl	$0x0, %esi
		000000000000149f:  R_X86_64_32	.rodata.str1.8+0x110
    14a3: bf 00 00 00 00               	movl	$0x0, %edi
		00000000000014a4:  R_X86_64_32	.rodata.str1.8+0x178
    14a8: e8 00 00 00 00               	callq	0x14ad <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x13dd>
		00000000000014a9:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    14ad: 0f 1f 00                     	nopl	(%rax)
