
.autoport/reports/perf-mips2c-neon/notes/attempt7/before-x86-same-headers.o:	file format elf64-x86-64

Disassembly of section .text:

0000000000001920 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
    1920: 55                           	pushq	%rbp
    1921: 48 89 e5                     	movq	%rsp, %rbp
    1924: 41 56                        	pushq	%r14
    1926: 41 55                        	pushq	%r13
    1928: 41 54                        	pushq	%r12
    192a: 53                           	pushq	%rbx
    192b: 48 83 e4 e0                  	andq	$-0x20, %rsp
    192f: 48 81 ec 40 01 00 00         	subq	$0x140, %rsp            # imm = 0x140
    1936: 48 8b 87 d0 01 00 00         	movq	0x1d0(%rdi), %rax
    193d: 48 8b 8f f0 01 00 00         	movq	0x1f0(%rdi), %rcx
    1944: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x194b <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2b>
		0000000000001947:  R_X86_64_PC32	g_ee_main_mem-0x4
    194b: 48 2d a0 00 00 00            	subq	$0xa0, %rax
    1951: 48 89 87 d0 01 00 00         	movq	%rax, 0x1d0(%rdi)
    1958: 89 c0                        	movl	%eax, %eax
    195a: 48 89 0c 02                  	movq	%rcx, (%rdx,%rax)
    195e: 48 8b 8f e0 01 00 00         	movq	0x1e0(%rdi), %rcx
    1965: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    196b: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x1972 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x52>
		000000000000196e:  R_X86_64_PC32	g_ee_main_mem-0x4
    1972: 48 89 4c 02 08               	movq	%rcx, 0x8(%rdx,%rax)
    1977: 48 8b 87 90 01 00 00         	movq	0x190(%rdi), %rax
    197e: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x1985 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x65>
		0000000000001981:  R_X86_64_PC32	g_ee_main_mem-0x4
    1985: c5 f9 6f 87 00 01 00 00      	vmovdqa	0x100(%rdi), %xmm0
    198d: 48 89 87 e0 01 00 00         	movq	%rax, 0x1e0(%rdi)
    1994: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    199a: 83 c0 30                     	addl	$0x30, %eax
    199d: 83 e0 f0                     	andl	$-0x10, %eax
    19a0: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    19a6: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    19ac: c5 f9 6f 87 10 01 00 00      	vmovdqa	0x110(%rdi), %xmm0
    19b4: 83 c0 40                     	addl	$0x40, %eax
    19b7: 83 e0 f0                     	andl	$-0x10, %eax
    19ba: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    19c0: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    19c6: c5 f9 6f 87 20 01 00 00      	vmovdqa	0x120(%rdi), %xmm0
    19ce: 83 c0 50                     	addl	$0x50, %eax
    19d1: 83 e0 f0                     	andl	$-0x10, %eax
    19d4: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    19da: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    19e0: c5 f9 6f 87 30 01 00 00      	vmovdqa	0x130(%rdi), %xmm0
    19e8: 83 c0 60                     	addl	$0x60, %eax
    19eb: 83 e0 f0                     	andl	$-0x10, %eax
    19ee: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    19f4: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    19fa: c5 f9 6f 87 40 01 00 00      	vmovdqa	0x140(%rdi), %xmm0
    1a02: 83 c0 70                     	addl	$0x70, %eax
    1a05: 83 e0 f0                     	andl	$-0x10, %eax
    1a08: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1a0e: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    1a14: c5 f9 6f 87 50 01 00 00      	vmovdqa	0x150(%rdi), %xmm0
    1a1c: 83 e8 80                     	subl	$-0x80, %eax
    1a1f: 83 e0 f0                     	andl	$-0x10, %eax
    1a22: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1a28: 8b 87 d0 01 00 00            	movl	0x1d0(%rdi), %eax
    1a2e: c5 f9 6f 87 c0 01 00 00      	vmovdqa	0x1c0(%rdi), %xmm0
    1a36: 05 90 00 00 00               	addl	$0x90, %eax
    1a3b: 83 e0 f0                     	andl	$-0x10, %eax
    1a3e: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1a44: 48 8b 47 40                  	movq	0x40(%rdi), %rax
    1a48: c5 f9 ef c0                  	vpxor	%xmm0, %xmm0, %xmm0
    1a4c: 48 89 87 c0 01 00 00         	movq	%rax, 0x1c0(%rdi)
    1a53: 48 8b 47 50                  	movq	0x50(%rdi), %rax
    1a57: 48 89 87 50 01 00 00         	movq	%rax, 0x150(%rdi)
    1a5e: 48 8b 47 60                  	movq	0x60(%rdi), %rax
    1a62: 48 89 87 40 01 00 00         	movq	%rax, 0x140(%rdi)
    1a69: 48 8b 47 70                  	movq	0x70(%rdi), %rax
    1a6d: 48 89 87 00 01 00 00         	movq	%rax, 0x100(%rdi)
    1a74: 48 8b 87 80 00 00 00         	movq	0x80(%rdi), %rax
    1a7b: 48 89 87 30 01 00 00         	movq	%rax, 0x130(%rdi)
    1a82: 48 8b 87 90 00 00 00         	movq	0x90(%rdi), %rax
    1a89: 48 89 87 20 01 00 00         	movq	%rax, 0x120(%rdi)
    1a90: 48 8b 87 d0 01 00 00         	movq	0x1d0(%rdi), %rax
    1a97: 48 83 c0 10                  	addq	$0x10, %rax
    1a9b: 48 89 87 10 01 00 00         	movq	%rax, 0x110(%rdi)
    1aa2: 83 e0 f0                     	andl	$-0x10, %eax
    1aa5: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1aab: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x1ab2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x192>
		0000000000001aae:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
    1ab2: 48 63 10                     	movslq	(%rax), %rdx
    1ab5: 48 89 57 30                  	movq	%rdx, 0x30(%rdi)
    1ab9: f6 c2 0f                     	testb	$0xf, %dl
    1abc: 0f 85 fe 10 00 00            	jne	0x2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    1ac2: 89 d2                        	movl	%edx, %edx
    1ac4: 48 89 fb                     	movq	%rdi, %rbx
    1ac7: 49 8b 04 11                  	movq	(%r9,%rdx), %rax
    1acb: 49 8b 4c 11 08               	movq	0x8(%r9,%rdx), %rcx
    1ad0: 48 89 87 80 03 00 00         	movq	%rax, 0x380(%rdi)
    1ad7: 0f b6 c0                     	movzbl	%al, %eax
    1ada: 48 89 ca                     	movq	%rcx, %rdx
    1add: 48 89 8f 88 03 00 00         	movq	%rcx, 0x388(%rdi)
    1ae4: 48 89 4f 38                  	movq	%rcx, 0x38(%rdi)
    1ae8: 48 89 47 30                  	movq	%rax, 0x30(%rdi)
    1aec: 8b bf d0 01 00 00            	movl	0x1d0(%rdi), %edi
    1af2: 8d 4f 20                     	leal	0x20(%rdi), %ecx
    1af5: 83 e1 f0                     	andl	$-0x10, %ecx
    1af8: 49 89 04 09                  	movq	%rax, (%r9,%rcx)
    1afc: 49 89 54 09 08               	movq	%rdx, 0x8(%r9,%rcx)
    1b01: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    1b08: e9 b5 00 00 00               	jmp	0x1bc2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2a2>
    1b0d: 0f 1f 00                     	nopl	(%rax)
    1b10: 48 63 09                     	movslq	(%rcx), %rcx
    1b13: 48 c7 43 40 ff ff ff ff      	movq	$-0x1, 0x40(%rbx)
    1b1b: 48 89 4b 30                  	movq	%rcx, 0x30(%rbx)
    1b1f: 85 c9                        	testl	%ecx, %ecx
    1b21: 0f 84 99 0b 00 00            	je	0x26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    1b27: 8b 07                        	movl	(%rdi), %eax
    1b29: 89 c2                        	movl	%eax, %edx
    1b2b: 83 e0 bf                     	andl	$-0x41, %eax
    1b2e: 83 e2 40                     	andl	$0x40, %edx
    1b31: 48 63 c8                     	movslq	%eax, %rcx
    1b34: 89 d6                        	movl	%edx, %esi
    1b36: 48 89 4b 40                  	movq	%rcx, 0x40(%rbx)
    1b3a: 48 89 73 30                  	movq	%rsi, 0x30(%rbx)
    1b3e: 89 07                        	movl	%eax, (%rdi)
    1b40: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x1b47 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x227>
		0000000000001b43:  R_X86_64_PC32	g_ee_main_mem-0x4
    1b47: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    1b4e: 85 d2                        	testl	%edx, %edx
    1b50: 74 2e                        	je	0x1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    1b52: 89 c0                        	movl	%eax, %eax
    1b54: 49 63 54 01 7c               	movslq	0x7c(%r9,%rax), %rdx
    1b59: 48 89 d0                     	movq	%rdx, %rax
    1b5c: 48 89 53 30                  	movq	%rdx, 0x30(%rbx)
    1b60: 8b 93 40 01 00 00            	movl	0x140(%rbx), %edx
    1b66: 41 89 44 11 2c               	movl	%eax, 0x2c(%r9,%rdx)
    1b6b: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    1b72: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x1b79 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x259>
		0000000000001b75:  R_X86_64_PC32	g_ee_main_mem-0x4
    1b79: 0f 1f 80 00 00 00 00         	nopl	(%rax)
    1b80: 48 8b b3 30 01 00 00         	movq	0x130(%rbx), %rsi
    1b87: 48 05 90 00 00 00            	addq	$0x90, %rax
    1b8d: 48 83 83 40 01 00 00 30      	addq	$0x30, 0x140(%rbx)
    1b95: 48 89 83 50 01 00 00         	movq	%rax, 0x150(%rbx)
    1b9c: 48 8d 56 ff                  	leaq	-0x1(%rsi), %rdx
    1ba0: 48 8b b3 00 01 00 00         	movq	0x100(%rbx), %rsi
    1ba7: 48 89 93 30 01 00 00         	movq	%rdx, 0x130(%rbx)
    1bae: 48 8d 4e 01                  	leaq	0x1(%rsi), %rcx
    1bb2: 48 89 8b 00 01 00 00         	movq	%rcx, 0x100(%rbx)
    1bb9: 48 85 d2                     	testq	%rdx, %rdx
    1bbc: 0f 84 2e 0d 00 00            	je	0x28f0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xfd0>
    1bc2: 89 c1                        	movl	%eax, %ecx
    1bc4: 48 8b b3 70 01 00 00         	movq	0x170(%rbx), %rsi
    1bcb: 49 63 94 09 80 00 00 00      	movslq	0x80(%r9,%rcx), %rdx
    1bd3: 48 89 53 30                  	movq	%rdx, 0x30(%rbx)
    1bd7: 48 39 d6                     	cmpq	%rdx, %rsi
    1bda: 74 a4                        	je	0x1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    1bdc: 49 8d 7c 09 68               	leaq	0x68(%r9,%rcx), %rdi
    1be1: 49 8d 4c 09 64               	leaq	0x64(%r9,%rcx), %rcx
    1be6: 48 63 17                     	movslq	(%rdi), %rdx
    1be9: 48 3b b3 20 01 00 00         	cmpq	0x120(%rbx), %rsi
    1bf0: 0f 84 aa 0b 00 00            	je	0x27a0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe80>
    1bf6: 81 e2 00 20 00 00            	andl	$0x2000, %edx           # imm = 0x2000
    1bfc: 89 d6                        	movl	%edx, %esi
    1bfe: 48 89 73 30                  	movq	%rsi, 0x30(%rbx)
    1c02: 0f 84 08 ff ff ff            	je	0x1b10 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1f0>
    1c08: 8b b3 d0 01 00 00            	movl	0x1d0(%rbx), %esi
    1c0e: 4c 63 01                     	movslq	(%rcx), %r8
    1c11: 48 c7 43 40 ff ff ff ff      	movq	$-0x1, 0x40(%rbx)
    1c19: 8d 56 20                     	leal	0x20(%rsi), %edx
    1c1c: 4c 89 43 30                  	movq	%r8, 0x30(%rbx)
    1c20: 83 e2 f0                     	andl	$-0x10, %edx
    1c23: 4d 8b 14 11                  	movq	(%r9,%rdx), %r10
    1c27: 49 8b 74 11 08               	movq	0x8(%r9,%rdx), %rsi
    1c2c: 4c 89 53 40                  	movq	%r10, 0x40(%rbx)
    1c30: 48 89 73 48                  	movq	%rsi, 0x48(%rbx)
    1c34: 49 83 f8 ff                  	cmpq	$-0x1, %r8
    1c38: 74 5d                        	je	0x1c97 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x377>
    1c3a: 4c 89 c2                     	movq	%r8, %rdx
    1c3d: c5 f9 6e f6                  	vmovd	%esi, %xmm6
    1c41: 4c 29 d2                     	subq	%r10, %rdx
    1c44: 49 89 f2                     	movq	%rsi, %r10
    1c47: 48 89 d7                     	movq	%rdx, %rdi
    1c4a: 49 c1 fa 20                  	sarq	$0x20, %r10
    1c4e: c5 f9 6e ea                  	vmovd	%edx, %xmm5
    1c52: 48 89 53 40                  	movq	%rdx, 0x40(%rbx)
    1c56: 48 c1 ff 20                  	sarq	$0x20, %rdi
    1c5a: c4 c3 49 22 ca 01            	vpinsrd	$0x1, %r10d, %xmm6, %xmm1
    1c60: c4 e3 51 22 c7 01            	vpinsrd	$0x1, %edi, %xmm5, %xmm0
    1c66: c5 f9 6c c1                  	vpunpcklqdq	%xmm1, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm1[0]
    1c6a: c5 f1 ef c9                  	vpxor	%xmm1, %xmm1, %xmm1
    1c6e: c4 e2 79 3d c1               	vpmaxsd	%xmm1, %xmm0, %xmm0
    1c73: c5 f9 7f 43 30               	vmovdqa	%xmm0, 0x30(%rbx)
    1c78: 4d 85 c0                     	testq	%r8, %r8
    1c7b: 0f 84 3f 0a 00 00            	je	0x26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    1c81: c5 f9 7e 01                  	vmovd	%xmm0, (%rcx)
    1c85: 8b 83 50 01 00 00            	movl	0x150(%rbx), %eax
    1c8b: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x1c92 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x372>
		0000000000001c8e:  R_X86_64_PC32	g_ee_main_mem-0x4
    1c92: 48 8d 7c 02 68               	leaq	0x68(%rdx,%rax), %rdi
    1c97: 8b 07                        	movl	(%rdi), %eax
    1c99: 89 c2                        	movl	%eax, %edx
    1c9b: 83 e0 bf                     	andl	$-0x41, %eax
    1c9e: 83 e2 40                     	andl	$0x40, %edx
    1ca1: 48 63 c8                     	movslq	%eax, %rcx
    1ca4: 89 d6                        	movl	%edx, %esi
    1ca6: 48 89 4b 40                  	movq	%rcx, 0x40(%rbx)
    1caa: 48 89 73 30                  	movq	%rsi, 0x30(%rbx)
    1cae: 89 07                        	movl	%eax, (%rdi)
    1cb0: 85 d2                        	testl	%edx, %edx
    1cb2: 74 23                        	je	0x1cd7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x3b7>
    1cb4: 8b 93 50 01 00 00            	movl	0x150(%rbx), %edx
    1cba: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x1cc1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x3a1>
		0000000000001cbd:  R_X86_64_PC32	g_ee_main_mem-0x4
    1cc1: 48 63 4c 10 7c               	movslq	0x7c(%rax,%rdx), %rcx
    1cc6: 48 89 4b 30                  	movq	%rcx, 0x30(%rbx)
    1cca: 48 89 ca                     	movq	%rcx, %rdx
    1ccd: 8b 8b 40 01 00 00            	movl	0x140(%rbx), %ecx
    1cd3: 89 54 08 2c                  	movl	%edx, 0x2c(%rax,%rcx)
    1cd7: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x1cde <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x3be>
		0000000000001cda:  R_X86_64_PC32	g_ee_main_mem-0x4
    1cde: 8b 93 50 01 00 00            	movl	0x150(%rbx), %edx
    1ce4: 49 63 44 11 70               	movslq	0x70(%r9,%rdx), %rax
    1ce9: 48 89 c1                     	movq	%rax, %rcx
    1cec: 48 89 83 90 01 00 00         	movq	%rax, 0x190(%rbx)
    1cf3: 48 8b 83 d0 01 00 00         	movq	0x1d0(%rbx), %rax
    1cfa: 85 c9                        	testl	%ecx, %ecx
    1cfc: 0f 84 de 01 00 00            	je	0x1ee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x5c0>
    1d02: c5 f9 6f 83 c0 01 00 00      	vmovdqa	0x1c0(%rbx), %xmm0
    1d0a: 48 83 e8 60                  	subq	$0x60, %rax
    1d0e: 48 89 83 d0 01 00 00         	movq	%rax, 0x1d0(%rbx)
    1d15: 83 e0 f0                     	andl	$-0x10, %eax
    1d18: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1d1e: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    1d24: c5 f9 6f 83 50 01 00 00      	vmovdqa	0x150(%rbx), %xmm0
    1d2c: 83 c0 10                     	addl	$0x10, %eax
    1d2f: 83 e0 f0                     	andl	$-0x10, %eax
    1d32: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1d38: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    1d3e: c5 f9 6f 83 40 01 00 00      	vmovdqa	0x140(%rbx), %xmm0
    1d46: 83 c0 20                     	addl	$0x20, %eax
    1d49: 83 e0 f0                     	andl	$-0x10, %eax
    1d4c: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1d52: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    1d58: c5 f9 6f 83 00 01 00 00      	vmovdqa	0x100(%rbx), %xmm0
    1d60: 83 c0 30                     	addl	$0x30, %eax
    1d63: 83 e0 f0                     	andl	$-0x10, %eax
    1d66: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1d6c: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    1d72: c5 f9 6f 83 30 01 00 00      	vmovdqa	0x130(%rbx), %xmm0
    1d7a: 83 c0 40                     	addl	$0x40, %eax
    1d7d: 83 e0 f0                     	andl	$-0x10, %eax
    1d80: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1d86: 48 8b 83 c0 01 00 00         	movq	0x1c0(%rbx), %rax
    1d8d: c5 f9 6f 83 20 01 00 00      	vmovdqa	0x120(%rbx), %xmm0
    1d95: 8b bb 90 01 00 00            	movl	0x190(%rbx), %edi
    1d9b: 48 89 43 40                  	movq	%rax, 0x40(%rbx)
    1d9f: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    1da6: 48 89 43 50                  	movq	%rax, 0x50(%rbx)
    1daa: 48 8b 83 40 01 00 00         	movq	0x140(%rbx), %rax
    1db1: 48 89 43 60                  	movq	%rax, 0x60(%rbx)
    1db5: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    1dbb: 83 c0 50                     	addl	$0x50, %eax
    1dbe: 83 e0 f0                     	andl	$-0x10, %eax
    1dc1: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    1dc7: c5 fa 7e bb a0 00 00 00      	vmovq	0xa0(%rbx), %xmm7       # xmm7 = mem[0],zero
    1dcf: c5 fa 7e 6b 60               	vmovq	0x60(%rbx), %xmm5       # xmm5 = mem[0],zero
    1dd4: c5 fa 7e b3 80 00 00 00      	vmovq	0x80(%rbx), %xmm6       # xmm6 = mem[0],zero
    1ddc: c4 e3 d1 22 53 70 01         	vpinsrq	$0x1, 0x70(%rbx), %xmm5, %xmm2
    1de3: c4 e3 c1 22 8b b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%rbx), %xmm7, %xmm1
    1ded: c5 fa 7e 7b 40               	vmovq	0x40(%rbx), %xmm7       # xmm7 = mem[0],zero
    1df2: c4 e3 c9 22 83 90 00 00 00 01	vpinsrq	$0x1, 0x90(%rbx), %xmm6, %xmm0
    1dfc: c4 e3 7d 18 c1 01            	vinsertf128	$0x1, %xmm1, %ymm0, %ymm0
    1e02: c4 e3 c1 22 4b 50 01         	vpinsrq	$0x1, 0x50(%rbx), %xmm7, %xmm1
    1e09: c5 fd 7f 44 24 20            	vmovdqa	%ymm0, 0x20(%rsp)
    1e0f: c4 e3 75 18 ca 01            	vinsertf128	$0x1, %xmm2, %ymm1, %ymm1
    1e15: c5 fd 7f 0c 24               	vmovdqa	%ymm1, (%rsp)
    1e1a: 85 ff                        	testl	%edi, %edi
    1e1c: 0f 84 bd 0d 00 00            	je	0x2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    1e22: 48 8b 8b 60 01 00 00         	movq	0x160(%rbx), %rcx
    1e29: 4c 01 cf                     	addq	%r9, %rdi
    1e2c: 31 d2                        	xorl	%edx, %edx
    1e2e: 48 89 e6                     	movq	%rsp, %rsi
    1e31: 4c 8b 83 70 01 00 00         	movq	0x170(%rbx), %r8
    1e38: c5 f8 77                     	vzeroupper
    1e3b: e8 00 00 00 00               	callq	0x1e40 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x520>
		0000000000001e3c:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    1e40: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x1e47 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x527>
		0000000000001e43:  R_X86_64_PC32	g_ee_main_mem-0x4
    1e47: 48 89 43 20                  	movq	%rax, 0x20(%rbx)
    1e4b: 48 8b 83 d0 01 00 00         	movq	0x1d0(%rbx), %rax
    1e52: 48 89 c2                     	movq	%rax, %rdx
    1e55: 8d 48 10                     	leal	0x10(%rax), %ecx
    1e58: 83 e2 f0                     	andl	$-0x10, %edx
    1e5b: 83 e1 f0                     	andl	$-0x10, %ecx
    1e5e: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    1e64: c5 fa 7f 83 c0 01 00 00      	vmovdqu	%xmm0, 0x1c0(%rbx)
    1e6c: 49 8b 14 09                  	movq	(%r9,%rcx), %rdx
    1e70: 49 8b 4c 09 08               	movq	0x8(%r9,%rcx), %rcx
    1e75: 48 89 8b 58 01 00 00         	movq	%rcx, 0x158(%rbx)
    1e7c: 8d 48 20                     	leal	0x20(%rax), %ecx
    1e7f: 83 e1 f0                     	andl	$-0x10, %ecx
    1e82: 48 89 93 50 01 00 00         	movq	%rdx, 0x150(%rbx)
    1e89: 89 d2                        	movl	%edx, %edx
    1e8b: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
    1e91: 8d 48 30                     	leal	0x30(%rax), %ecx
    1e94: 83 e1 f0                     	andl	$-0x10, %ecx
    1e97: c5 fa 7f 83 40 01 00 00      	vmovdqu	%xmm0, 0x140(%rbx)
    1e9f: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
    1ea5: 8d 48 40                     	leal	0x40(%rax), %ecx
    1ea8: 83 e1 f0                     	andl	$-0x10, %ecx
    1eab: c5 fa 7f 83 00 01 00 00      	vmovdqu	%xmm0, 0x100(%rbx)
    1eb3: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
    1eb9: 8d 48 50                     	leal	0x50(%rax), %ecx
    1ebc: 48 83 c0 60                  	addq	$0x60, %rax
    1ec0: 83 e1 f0                     	andl	$-0x10, %ecx
    1ec3: c5 fa 7f 83 30 01 00 00      	vmovdqu	%xmm0, 0x130(%rbx)
    1ecb: c4 c1 7a 6f 04 09            	vmovdqu	(%r9,%rcx), %xmm0
    1ed1: 48 89 83 d0 01 00 00         	movq	%rax, 0x1d0(%rbx)
    1ed8: c5 fa 7f 83 20 01 00 00      	vmovdqu	%xmm0, 0x120(%rbx)
    1ee0: 49 63 74 11 78               	movslq	0x78(%r9,%rdx), %rsi
    1ee5: 83 c0 20                     	addl	$0x20, %eax
    1ee8: 83 e0 f0                     	andl	$-0x10, %eax
    1eeb: 48 89 73 50                  	movq	%rsi, 0x50(%rbx)
    1eef: 48 89 f1                     	movq	%rsi, %rcx
    1ef2: 49 8d 74 11 74               	leaq	0x74(%r9,%rdx), %rsi
    1ef7: 48 63 16                     	movslq	(%rsi), %rdx
    1efa: 48 89 53 30                  	movq	%rdx, 0x30(%rbx)
    1efe: 49 8b 3c 01                  	movq	(%r9,%rax), %rdi
    1f02: 49 8b 44 01 08               	movq	0x8(%r9,%rax), %rax
    1f07: 48 89 7b 40                  	movq	%rdi, 0x40(%rbx)
    1f0b: 48 89 43 48                  	movq	%rax, 0x48(%rbx)
    1f0f: 85 c9                        	testl	%ecx, %ecx
    1f11: 74 0f                        	je	0x1f22 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x602>
    1f13: 48 29 fa                     	subq	%rdi, %rdx
    1f16: 48 89 53 30                  	movq	%rdx, 0x30(%rbx)
    1f1a: 89 16                        	movl	%edx, (%rsi)
    1f1c: 0f 88 a6 0a 00 00            	js	0x29c8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x10a8>
    1f22: 48 8b 93 40 01 00 00         	movq	0x140(%rbx), %rdx
    1f29: f6 c2 0f                     	testb	$0xf, %dl
    1f2c: 0f 85 8e 0c 00 00            	jne	0x2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    1f32: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x1f39 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x619>
		0000000000001f35:  R_X86_64_PC32	g_ee_main_mem-0x4
    1f39: 89 d2                        	movl	%edx, %edx
    1f3b: c5 fa 7e 24 10               	vmovq	(%rax,%rdx), %xmm4      # xmm4 = mem[0],zero
    1f40: 48 8b 7c 10 08               	movq	0x8(%rax,%rdx), %rdi
    1f45: c5 f9 d6 a3 00 03 00 00      	vmovq	%xmm4, 0x300(%rbx)
    1f4d: 48 89 bb 08 03 00 00         	movq	%rdi, 0x308(%rbx)
    1f54: 48 8b 4c 10 10               	movq	0x10(%rax,%rdx), %rcx
    1f59: 4c 8b 44 10 18               	movq	0x18(%rax,%rdx), %r8
    1f5e: 48 89 8b 10 03 00 00         	movq	%rcx, 0x310(%rbx)
    1f65: 4c 89 83 18 03 00 00         	movq	%r8, 0x318(%rbx)
    1f6c: 48 8b 74 10 20               	movq	0x20(%rax,%rdx), %rsi
    1f71: 48 8b 4c 10 28               	movq	0x28(%rax,%rdx), %rcx
    1f76: 48 8b 93 50 01 00 00         	movq	0x150(%rbx), %rdx
    1f7d: 48 89 b3 20 03 00 00         	movq	%rsi, 0x320(%rbx)
    1f84: 48 89 8b 28 03 00 00         	movq	%rcx, 0x328(%rbx)
    1f8b: f6 c2 0f                     	testb	$0xf, %dl
    1f8e: 0f 85 2c 0c 00 00            	jne	0x2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    1f94: 89 d2                        	movl	%edx, %edx
    1f96: c4 e3 d9 22 e7 01            	vpinsrq	$0x1, %rdi, %xmm4, %xmm4
    1f9c: c5 fa 10 bb 88 03 00 00      	vmovss	0x388(%rbx), %xmm7      # xmm7 = mem[0],zero,zero,zero
    1fa4: c4 e2 79 18 93 84 03 00 00   	vbroadcastss	0x384(%rbx), %xmm2
    1fad: 48 8d 7c 10 10               	leaq	0x10(%rax,%rdx), %rdi
    1fb2: c5 7a 10 93 8c 03 00 00      	vmovss	0x38c(%rbx), %xmm10     # xmm10 = mem[0],zero,zero,zero
    1fba: 4c 8b 37                     	movq	(%rdi), %r14
    1fbd: 4c 8b 5f 08                  	movq	0x8(%rdi), %r11
    1fc1: c5 c0 c6 f7 00               	vshufps	$0x0, %xmm7, %xmm7, %xmm6 # xmm6 = xmm7[0,0,0,0]
    1fc6: 4c 89 b3 30 03 00 00         	movq	%r14, 0x330(%rbx)
    1fcd: c4 41 79 6e ee               	vmovd	%r14d, %xmm13
    1fd2: 4c 89 9b 38 03 00 00         	movq	%r11, 0x338(%rbx)
    1fd9: 4c 8b 4c 10 20               	movq	0x20(%rax,%rdx), %r9
    1fde: 4c 8b 64 10 28               	movq	0x28(%rax,%rdx), %r12
    1fe3: 4c 89 8b 40 03 00 00         	movq	%r9, 0x340(%rbx)
    1fea: 4c 89 a3 48 03 00 00         	movq	%r12, 0x348(%rbx)
    1ff1: c5 fa 7e 44 10 30            	vmovq	0x30(%rax,%rdx), %xmm0  # xmm0 = mem[0],zero
    1ff7: 4c 8b 54 10 38               	movq	0x38(%rax,%rdx), %r10
    1ffc: c5 f9 d6 83 50 03 00 00      	vmovq	%xmm0, 0x350(%rbx)
    2004: c4 c3 f9 22 ca 01            	vpinsrq	$0x1, %r10, %xmm0, %xmm1
    200a: c5 fa 7e 83 84 03 00 00      	vmovq	0x384(%rbx), %xmm0      # xmm0 = mem[0],zero
    2012: 4c 89 93 58 03 00 00         	movq	%r10, 0x358(%rbx)
    2019: c5 fa 6f 5c 10 40            	vmovdqu	0x40(%rax,%rdx), %xmm3
    201f: c5 fa 16 c0                  	vmovshdup	%xmm0, %xmm0    # xmm0 = xmm0[1,1,3,3]
    2023: c5 f9 6f eb                  	vmovdqa	%xmm3, %xmm5
    2027: c5 fa 7f 9b 60 03 00 00      	vmovdqu	%xmm3, 0x360(%rbx)
    202f: c5 79 6f cb                  	vmovdqa	%xmm3, %xmm9
    2033: 4c 63 6c 10 60               	movslq	0x60(%rax,%rdx), %r13
    2038: c5 c8 59 f3                  	vmulps	%xmm3, %xmm6, %xmm6
    203c: c5 d0 c6 ed 55               	vshufps	$0x55, %xmm5, %xmm5, %xmm5 # xmm5 = xmm5[1,1,1,1]
    2041: c4 c1 f9 6e de               	vmovq	%r14, %xmm3
    2046: c5 79 6f c5                  	vmovdqa	%xmm5, %xmm8
    204a: c5 e0 c6 db 55               	vshufps	$0x55, %xmm3, %xmm3, %xmm3 # xmm3 = xmm3[1,1,1,1]
    204f: c5 79 6f e3                  	vmovdqa	%xmm3, %xmm12
    2053: c4 c1 30 14 d8               	vunpcklps	%xmm8, %xmm9, %xmm3 # xmm3 = xmm9[0],xmm8[0],xmm9[1],xmm8[1]
    2058: 4c 89 da                     	movq	%r11, %rdx
    205b: c5 fa 7e db                  	vmovq	%xmm3, %xmm3            # xmm3 = xmm3[0],zero
    205f: c5 fa 7e c0                  	vmovq	%xmm0, %xmm0            # xmm0 = xmm0[0],zero
    2063: 4c 89 6b 30                  	movq	%r13, 0x30(%rbx)
    2067: 4d 89 ea                     	movq	%r13, %r10
    206a: c5 f8 59 c3                  	vmulps	%xmm3, %xmm0, %xmm0
    206e: c4 c1 10 14 dc               	vunpcklps	%xmm12, %xmm13, %xmm3 # xmm3 = xmm13[0],xmm12[0],xmm13[1],xmm12[1]
    2073: 44 89 ab 00 02 00 00         	movl	%r13d, 0x200(%rbx)
    207a: 48 c1 ea 20                  	shrq	$0x20, %rdx
    207e: c4 e2 7d 18 ab 84 03 00 00   	vbroadcastss	0x384(%rbx), %ymm5
    2087: c5 fa 7e db                  	vmovq	%xmm3, %xmm3            # xmm3 = xmm3[0],zero
    208b: c5 f8 29 b3 60 03 00 00      	vmovaps	%xmm6, 0x360(%rbx)
    2093: c5 c8 15 f6                  	vunpckhps	%xmm6, %xmm6, %xmm6 # xmm6 = xmm6[2,2,3,3]
    2097: c5 fa 7e c0                  	vmovq	%xmm0, %xmm0            # xmm0 = xmm0[0],zero
    209b: c5 f8 58 db                  	vaddps	%xmm3, %xmm0, %xmm3
    209f: c4 c1 79 6e c3               	vmovd	%r11d, %xmm0
    20a4: c5 ca 58 f0                  	vaddss	%xmm0, %xmm6, %xmm6
    20a8: c5 f8 13 9b 30 03 00 00      	vmovlps	%xmm3, 0x330(%rbx)
    20b0: c5 fa 11 b3 38 03 00 00      	vmovss	%xmm6, 0x338(%rbx)
    20b8: 45 85 ed                     	testl	%r13d, %r13d
    20bb: 0f 85 ef 06 00 00            	jne	0x27b0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe90>
    20c1: c5 fa 16 fb                  	vmovshdup	%xmm3, %xmm7    # xmm7 = xmm3[1,1,3,3]
    20c5: c5 f8 28 c3                  	vmovaps	%xmm3, %xmm0
    20c9: c5 e8 59 c9                  	vmulps	%xmm1, %xmm2, %xmm1
    20cd: c5 f9 6e da                  	vmovd	%edx, %xmm3
    20d1: c5 f8 14 c7                  	vunpcklps	%xmm7, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm7[0],xmm0[1],xmm7[1]
    20d5: 49 c1 e8 20                  	shrq	$0x20, %r8
    20d9: c5 c8 14 f3                  	vunpcklps	%xmm3, %xmm6, %xmm6 # xmm6 = xmm6[0],xmm3[0],xmm6[1],xmm3[1]
    20dd: c5 f8 16 de                  	vmovlhps	%xmm6, %xmm0, %xmm3     # xmm3 = xmm0[0],xmm6[0]
    20e1: c5 e0 59 d2                  	vmulps	%xmm2, %xmm3, %xmm2
    20e5: c4 c1 79 6e f4               	vmovd	%r12d, %xmm6
    20ea: 49 c1 ec 20                  	shrq	$0x20, %r12
    20ee: c4 c1 79 6e c1               	vmovd	%r9d, %xmm0
    20f3: c4 c1 79 6e fc               	vmovd	%r12d, %xmm7
    20f8: 49 c1 e9 20                  	shrq	$0x20, %r9
    20fc: c5 c8 14 f7                  	vunpcklps	%xmm7, %xmm6, %xmm6 # xmm6 = xmm6[0],xmm7[0],xmm6[1],xmm7[1]
    2100: c4 c1 79 6e f9               	vmovd	%r9d, %xmm7
    2105: c5 f8 14 c7                  	vunpcklps	%xmm7, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm7[0],xmm0[1],xmm7[1]
    2109: c5 c0 57 ff                  	vxorps	%xmm7, %xmm7, %xmm7
    210d: c5 f8 29 8b b0 03 00 00      	vmovaps	%xmm1, 0x3b0(%rbx)
    2115: c5 f8 16 c6                  	vmovlhps	%xmm6, %xmm0, %xmm0     # xmm0 = xmm0[0],xmm6[0]
    2119: c4 e3 65 18 c0 01            	vinsertf128	$0x1, %xmm0, %ymm3, %ymm0
    211f: c5 f0 15 f1                  	vunpckhps	%xmm1, %xmm1, %xmm6 # xmm6 = xmm1[2,2,3,3]
    2123: c5 e8 58 d4                  	vaddps	%xmm4, %xmm2, %xmm2
    2127: c5 fc 59 c5                  	vmulps	%ymm5, %ymm0, %ymm0
    212b: c5 f9 6e e6                  	vmovd	%esi, %xmm4
    212f: 48 c1 ee 20                  	shrq	$0x20, %rsi
    2133: c5 f0 c6 e9 55               	vshufps	$0x55, %xmm1, %xmm1, %xmm5 # xmm5 = xmm1[1,1,1,1]
    2138: c5 f8 29 93 00 03 00 00      	vmovaps	%xmm2, 0x300(%rbx)
    2140: c5 f2 58 d4                  	vaddss	%xmm4, %xmm1, %xmm2
    2144: c5 f9 6e e6                  	vmovd	%esi, %xmm4
    2148: c5 f0 c6 c9 ff               	vshufps	$0xff, %xmm1, %xmm1, %xmm1 # xmm1 = xmm1[3,3,3,3]
    214d: c5 d2 58 ec                  	vaddss	%xmm4, %xmm5, %xmm5
    2151: c5 f9 6e e1                  	vmovd	%ecx, %xmm4
    2155: 48 c1 e9 20                  	shrq	$0x20, %rcx
    2159: c5 ca 58 f4                  	vaddss	%xmm4, %xmm6, %xmm6
    215d: c5 f9 6e e1                  	vmovd	%ecx, %xmm4
    2161: c5 fc 11 83 90 03 00 00      	vmovups	%ymm0, 0x390(%rbx)
    2169: c4 e3 7d 19 c0 01            	vextractf128	$0x1, %ymm0, %xmm0
    216f: c5 ea c2 ff 05               	vcmpnltss	%xmm7, %xmm2, %xmm7
    2174: c5 f2 58 cc                  	vaddss	%xmm4, %xmm1, %xmm1
    2178: c4 c1 79 6e e0               	vmovd	%r8d, %xmm4
    217d: c5 f8 c6 c0 ff               	vshufps	$0xff, %xmm0, %xmm0, %xmm0 # xmm0 = xmm0[3,3,3,3]
    2182: c5 fa 58 c4                  	vaddss	%xmm4, %xmm0, %xmm0
    2186: c5 d8 57 e4                  	vxorps	%xmm4, %xmm4, %xmm4
    218a: c4 e3 59 4a e2 70            	vblendvps	%xmm7, %xmm2, %xmm4, %xmm4
    2190: c5 c0 57 ff                  	vxorps	%xmm7, %xmm7, %xmm7
    2194: c5 e8 57 d2                  	vxorps	%xmm2, %xmm2, %xmm2
    2198: c5 d2 c2 ff 05               	vcmpnltss	%xmm7, %xmm5, %xmm7
    219d: c5 f8 14 c4                  	vunpcklps	%xmm4, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm4[0],xmm0[1],xmm4[1]
    21a1: c4 e3 69 4a d5 70            	vblendvps	%xmm7, %xmm5, %xmm2, %xmm2
    21a7: c5 c0 57 ff                  	vxorps	%xmm7, %xmm7, %xmm7
    21ab: c5 d0 57 ed                  	vxorps	%xmm5, %xmm5, %xmm5
    21af: c5 ca c2 ff 05               	vcmpnltss	%xmm7, %xmm6, %xmm7
    21b4: c4 e3 51 4a ee 70            	vblendvps	%xmm7, %xmm6, %xmm5, %xmm5
    21ba: c5 e8 14 d5                  	vunpcklps	%xmm5, %xmm2, %xmm2 # xmm2 = xmm2[0],xmm5[0],xmm2[1],xmm5[1]
    21be: c5 f8 16 c2                  	vmovlhps	%xmm2, %xmm0, %xmm0     # xmm0 = xmm0[0],xmm2[0]
    21c2: c5 e8 57 d2                  	vxorps	%xmm2, %xmm2, %xmm2
    21c6: c5 f8 11 83 1c 03 00 00      	vmovups	%xmm0, 0x31c(%rbx)
    21ce: c5 f8 57 c0                  	vxorps	%xmm0, %xmm0, %xmm0
    21d2: c5 f2 c2 d2 05               	vcmpnltss	%xmm2, %xmm1, %xmm2
    21d7: c4 e3 79 4a c1 20            	vblendvps	%xmm2, %xmm1, %xmm0, %xmm0
    21dd: c5 fa 11 83 2c 03 00 00      	vmovss	%xmm0, 0x32c(%rbx)
    21e5: c5 f8 11 1f                  	vmovups	%xmm3, (%rdi)
    21e9: 48 8b 93 40 01 00 00         	movq	0x140(%rbx), %rdx
    21f0: f6 c2 0f                     	testb	$0xf, %dl
    21f3: 0f 85 08 0a 00 00            	jne	0x2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>
    21f9: c5 f9 6f 83 00 03 00 00      	vmovdqa	0x300(%rbx), %xmm0
    2201: 89 d2                        	movl	%edx, %edx
    2203: c5 fa 7f 04 10               	vmovdqu	%xmm0, (%rax,%rdx)
    2208: 48 8b 93 40 01 00 00         	movq	0x140(%rbx), %rdx
    220f: f6 c2 0f                     	testb	$0xf, %dl
    2212: 0f 85 e9 09 00 00            	jne	0x2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>
    2218: c5 f9 6f 83 10 03 00 00      	vmovdqa	0x310(%rbx), %xmm0
    2220: 89 d2                        	movl	%edx, %edx
    2222: c5 fa 7f 44 10 10            	vmovdqu	%xmm0, 0x10(%rax,%rdx)
    2228: 48 8b 93 40 01 00 00         	movq	0x140(%rbx), %rdx
    222f: f6 c2 0f                     	testb	$0xf, %dl
    2232: 0f 85 c9 09 00 00            	jne	0x2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>
    2238: c5 f9 6f 83 20 03 00 00      	vmovdqa	0x320(%rbx), %xmm0
    2240: 89 d2                        	movl	%edx, %edx
    2242: c5 fa 10 2d 00 00 00 00      	vmovss	(%rip), %xmm5           # xmm5 = mem[0],zero,zero,zero
                                                                        # 0x224a <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x92a>
		0000000000002246:  R_X86_64_PC32	.LC11-0x4
    224a: c5 fa 7f 44 10 20            	vmovdqu	%xmm0, 0x20(%rax,%rdx)
    2250: 48 8b 93 40 01 00 00         	movq	0x140(%rbx), %rdx
    2257: 48 8b 8b 10 01 00 00         	movq	0x110(%rbx), %rcx
    225e: 48 89 53 40                  	movq	%rdx, 0x40(%rbx)
    2262: 89 d2                        	movl	%edx, %edx
    2264: 48 89 4b 30                  	movq	%rcx, 0x30(%rbx)
    2268: 8b 74 10 10                  	movl	0x10(%rax,%rdx), %esi
    226c: 89 c9                        	movl	%ecx, %ecx
    226e: 89 b3 00 02 00 00            	movl	%esi, 0x200(%rbx)
    2274: 8b 7c 10 14                  	movl	0x14(%rax,%rdx), %edi
    2278: 89 bb 04 02 00 00            	movl	%edi, 0x204(%rbx)
    227e: 8b 54 10 18                  	movl	0x18(%rax,%rdx), %edx
    2282: 89 93 0c 02 00 00            	movl	%edx, 0x20c(%rbx)
    2288: 89 34 08                     	movl	%esi, (%rax,%rcx)
    228b: 8b 8b 04 02 00 00            	movl	0x204(%rbx), %ecx
    2291: 8b 43 30                     	movl	0x30(%rbx), %eax
    2294: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x229b <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x97b>
		0000000000002297:  R_X86_64_PC32	g_ee_main_mem-0x4
    229b: 89 4c 02 04                  	movl	%ecx, 0x4(%rdx,%rax)
    229f: 8b 8b 0c 02 00 00            	movl	0x20c(%rbx), %ecx
    22a5: 8b 43 30                     	movl	0x30(%rbx), %eax
    22a8: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x22af <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x98f>
		00000000000022ab:  R_X86_64_PC32	g_ee_main_mem-0x4
    22af: 89 4c 02 08                  	movl	%ecx, 0x8(%rdx,%rax)
    22b3: c5 fa 10 83 0c 02 00 00      	vmovss	0x20c(%rbx), %xmm0      # xmm0 = mem[0],zero,zero,zero
    22bb: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x22c2 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x9a2>
		00000000000022be:  R_X86_64_PC32	g_ee_main_mem-0x4
    22c2: 8b 43 30                     	movl	0x30(%rbx), %eax
    22c5: c5 fa 59 c0                  	vmulss	%xmm0, %xmm0, %xmm0
    22c9: c5 d2 5c c8                  	vsubss	%xmm0, %xmm5, %xmm1
    22cd: c5 fa 11 83 0c 02 00 00      	vmovss	%xmm0, 0x20c(%rbx)
    22d5: c5 fa 10 83 04 02 00 00      	vmovss	0x204(%rbx), %xmm0      # xmm0 = mem[0],zero,zero,zero
    22dd: c5 fa 59 c0                  	vmulss	%xmm0, %xmm0, %xmm0
    22e1: c5 f2 5c c0                  	vsubss	%xmm0, %xmm1, %xmm0
    22e5: c5 f8 14 c9                  	vunpcklps	%xmm1, %xmm0, %xmm1 # xmm1 = xmm0[0],xmm1[0],xmm0[1],xmm1[1]
    22e9: c5 f8 13 8b 04 02 00 00      	vmovlps	%xmm1, 0x204(%rbx)
    22f1: c5 fa 10 8b 00 02 00 00      	vmovss	0x200(%rbx), %xmm1      # xmm1 = mem[0],zero,zero,zero
    22f9: c5 f2 59 c9                  	vmulss	%xmm1, %xmm1, %xmm1
    22fd: c5 fa 5c c1                  	vsubss	%xmm1, %xmm0, %xmm0
    2301: c5 f8 54 05 00 00 00 00      	vandps	(%rip), %xmm0, %xmm0    # 0x2309 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x9e9>
		0000000000002305:  R_X86_64_PC32	.LC22-0x4
    2309: c5 fa 51 c0                  	vsqrtss	%xmm0, %xmm0, %xmm0
    230d: c5 fa 11 83 00 02 00 00      	vmovss	%xmm0, 0x200(%rbx)
    2315: c5 fa 11 44 02 0c            	vmovss	%xmm0, 0xc(%rdx,%rax)
    231b: 48 63 83 00 02 00 00         	movslq	0x200(%rbx), %rax
    2322: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x2329 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa09>
		0000000000002325:  R_X86_64_PC32	g_ee_main_mem-0x4
    2329: 48 89 43 40                  	movq	%rax, 0x40(%rbx)
    232d: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x2334 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa14>
		0000000000002330:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache-0x4
    2334: 48 63 10                     	movslq	(%rax), %rdx
    2337: 89 d0                        	movl	%edx, %eax
    2339: 48 89 53 30                  	movq	%rdx, 0x30(%rbx)
    233d: 41 8b 04 01                  	movl	(%r9,%rax), %eax
    2341: 89 83 00 02 00 00            	movl	%eax, 0x200(%rbx)
    2347: 0f b6 c0                     	movzbl	%al, %eax
    234a: 48 83 e8 0a                  	subq	$0xa, %rax
    234e: 48 89 43 30                  	movq	%rax, 0x30(%rbx)
    2352: 0f 88 c3 00 00 00            	js	0x241b <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xafb>
    2358: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x235f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa3f>
		000000000000235b:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
    235f: c5 fa 7e 93 10 01 00 00      	vmovq	0x110(%rbx), %xmm2      # xmm2 = mem[0],zero
    2367: c5 fa 7e ab a0 00 00 00      	vmovq	0xa0(%rbx), %xmm5       # xmm5 = mem[0],zero
    236f: c5 fa 7e a3 80 00 00 00      	vmovq	0x80(%rbx), %xmm4       # xmm4 = mem[0],zero
    2377: 48 63 08                     	movslq	(%rax), %rcx
    237a: c5 e9 6c ca                  	vpunpcklqdq	%xmm2, %xmm2, %xmm1 # xmm1 = xmm2[0,0]
    237e: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    2385: c5 f9 d6 53 40               	vmovq	%xmm2, 0x40(%rbx)
    238a: c4 e3 d1 22 9b b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%rbx), %xmm5, %xmm3
    2394: 48 63 93 f0 01 00 00         	movslq	0x1f0(%rbx), %rdx
    239b: c5 f9 d6 53 50               	vmovq	%xmm2, 0x50(%rbx)
    23a0: 48 83 c0 50                  	addq	$0x50, %rax
    23a4: 48 89 8b 90 01 00 00         	movq	%rcx, 0x190(%rbx)
    23ab: 48 89 cf                     	movq	%rcx, %rdi
    23ae: c4 e1 f9 6e f0               	vmovq	%rax, %xmm6
    23b3: c4 e3 c9 22 43 70 01         	vpinsrq	$0x1, 0x70(%rbx), %xmm6, %xmm0
    23ba: 48 89 43 60                  	movq	%rax, 0x60(%rbx)
    23be: 48 89 53 20                  	movq	%rdx, 0x20(%rbx)
    23c2: c4 e3 75 18 c8 01            	vinsertf128	$0x1, %xmm0, %ymm1, %ymm1
    23c8: c4 e3 d9 22 83 90 00 00 00 01	vpinsrq	$0x1, 0x90(%rbx), %xmm4, %xmm0
    23d2: c5 fd 7f 8c 24 80 00 00 00   	vmovdqa	%ymm1, 0x80(%rsp)
    23db: c4 e3 7d 18 c3 01            	vinsertf128	$0x1, %xmm3, %ymm0, %ymm0
    23e1: c5 fd 7f 84 24 a0 00 00 00   	vmovdqa	%ymm0, 0xa0(%rsp)
    23ea: 85 c9                        	testl	%ecx, %ecx
    23ec: 0f 84 ed 07 00 00            	je	0x2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    23f2: 48 8b 8b 60 01 00 00         	movq	0x160(%rbx), %rcx
    23f9: 4c 8b 83 70 01 00 00         	movq	0x170(%rbx), %r8
    2400: 89 ff                        	movl	%edi, %edi
    2402: 31 d2                        	xorl	%edx, %edx
    2404: 4c 01 cf                     	addq	%r9, %rdi
    2407: 48 8d b4 24 80 00 00 00      	leaq	0x80(%rsp), %rsi
    240f: c5 f8 77                     	vzeroupper
    2412: e8 00 00 00 00               	callq	0x2417 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xaf7>
		0000000000002413:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    2417: 48 89 43 20                  	movq	%rax, 0x20(%rbx)
    241b: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x2422 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb02>
		000000000000241e:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x4
    2422: c5 fa 7e ab a0 00 00 00      	vmovq	0xa0(%rbx), %xmm5       # xmm5 = mem[0],zero
    242a: c5 fa 7e b3 80 00 00 00      	vmovq	0x80(%rbx), %xmm6       # xmm6 = mem[0],zero
    2432: c5 fa 7e 83 10 01 00 00      	vmovq	0x110(%rbx), %xmm0      # xmm0 = mem[0],zero
    243a: 48 63 00                     	movslq	(%rax), %rax
    243d: 48 63 93 f0 01 00 00         	movslq	0x1f0(%rbx), %rdx
    2444: c4 e3 d1 22 8b b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%rbx), %xmm5, %xmm1
    244e: c5 f9 d6 43 40               	vmovq	%xmm0, 0x40(%rbx)
    2453: c4 e3 c9 22 93 90 00 00 00 01	vpinsrq	$0x1, 0x90(%rbx), %xmm6, %xmm2
    245d: 48 89 83 90 01 00 00         	movq	%rax, 0x190(%rbx)
    2464: 48 89 c7                     	movq	%rax, %rdi
    2467: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    246e: c4 e3 6d 18 d1 01            	vinsertf128	$0x1, %xmm1, %ymm2, %ymm2
    2474: c5 f9 d6 43 50               	vmovq	%xmm0, 0x50(%rbx)
    2479: c5 f9 6c c0                  	vpunpcklqdq	%xmm0, %xmm0, %xmm0 # xmm0 = xmm0[0,0]
    247d: 48 83 c0 50                  	addq	$0x50, %rax
    2481: 48 89 53 20                  	movq	%rdx, 0x20(%rbx)
    2485: c4 e1 f9 6e e8               	vmovq	%rax, %xmm5
    248a: c4 e3 d1 22 4b 70 01         	vpinsrq	$0x1, 0x70(%rbx), %xmm5, %xmm1
    2491: 48 89 43 60                  	movq	%rax, 0x60(%rbx)
    2495: c5 fd 7f 94 24 e0 00 00 00   	vmovdqa	%ymm2, 0xe0(%rsp)
    249e: c4 e3 7d 18 c1 01            	vinsertf128	$0x1, %xmm1, %ymm0, %ymm0
    24a4: c5 fd 7f 84 24 c0 00 00 00   	vmovdqa	%ymm0, 0xc0(%rsp)
    24ad: 85 ff                        	testl	%edi, %edi
    24af: 0f 84 2a 07 00 00            	je	0x2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    24b5: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x24bc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb9c>
		00000000000024b8:  R_X86_64_PC32	g_ee_main_mem-0x4
    24bc: 48 8b 8b 60 01 00 00         	movq	0x160(%rbx), %rcx
    24c3: 89 ff                        	movl	%edi, %edi
    24c5: 31 d2                        	xorl	%edx, %edx
    24c7: 4c 8b 83 70 01 00 00         	movq	0x170(%rbx), %r8
    24ce: 48 8d b4 24 c0 00 00 00      	leaq	0xc0(%rsp), %rsi
    24d6: 4c 01 cf                     	addq	%r9, %rdi
    24d9: c5 f8 77                     	vzeroupper
    24dc: e8 00 00 00 00               	callq	0x24e1 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbc1>
		00000000000024dd:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    24e1: 48 8b 8b 10 01 00 00         	movq	0x110(%rbx), %rcx
    24e8: c5 f0 57 c9                  	vxorps	%xmm1, %xmm1, %xmm1
    24ec: 48 89 43 20                  	movq	%rax, 0x20(%rbx)
    24f0: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x24f7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbd7>
		00000000000024f3:  R_X86_64_PC32	g_ee_main_mem-0x4
    24f7: 48 8b 83 40 01 00 00         	movq	0x140(%rbx), %rax
    24fe: 89 ca                        	movl	%ecx, %edx
    2500: 48 89 4b 30                  	movq	%rcx, 0x30(%rbx)
    2504: 48 89 43 40                  	movq	%rax, 0x40(%rbx)
    2508: c4 c1 79 6e 44 11 0c         	vmovd	0xc(%r9,%rdx), %xmm0    # xmm0 = mem[0],zero,zero,zero
    250f: c7 83 04 02 00 00 00 00 00 00	movl	$0x0, 0x204(%rbx)
    2519: c5 f8 2f c8                  	vcomiss	%xmm0, %xmm1
    251d: c5 f9 7e 83 00 02 00 00      	vmovd	%xmm0, 0x200(%rbx)
    2525: 0f 87 25 03 00 00            	ja	0x2850 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xf30>
    252b: a8 0f                        	testb	$0xf, %al
    252d: 0f 85 8d 06 00 00            	jne	0x2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    2533: 89 c0                        	movl	%eax, %eax
    2535: 83 e1 0f                     	andl	$0xf, %ecx
    2538: 49 8d 7c 01 10               	leaq	0x10(%r9,%rax), %rdi
    253d: 48 8b 07                     	movq	(%rdi), %rax
    2540: 48 8b 77 08                  	movq	0x8(%rdi), %rsi
    2544: 48 89 83 90 02 00 00         	movq	%rax, 0x290(%rbx)
    254b: 48 89 b3 98 02 00 00         	movq	%rsi, 0x298(%rbx)
    2552: 0f 85 68 06 00 00            	jne	0x2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    2558: 49 8b 0c 11                  	movq	(%r9,%rdx), %rcx
    255c: 49 8b 44 11 08               	movq	0x8(%r9,%rdx), %rax
    2561: c5 e8 57 d2                  	vxorps	%xmm2, %xmm2, %xmm2
    2565: 48 c1 ee 20                  	shrq	$0x20, %rsi
    2569: c5 f9 6e fe                  	vmovd	%esi, %xmm7
    256d: 48 89 8b a0 02 00 00         	movq	%rcx, 0x2a0(%rbx)
    2574: c5 f9 6e c1                  	vmovd	%ecx, %xmm0
    2578: 48 c1 e9 20                  	shrq	$0x20, %rcx
    257c: c5 f9 6e e1                  	vmovd	%ecx, %xmm4
    2580: 48 89 83 a8 02 00 00         	movq	%rax, 0x2a8(%rbx)
    2587: c5 f8 14 c4                  	vunpcklps	%xmm4, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm4[0],xmm0[1],xmm4[1]
    258b: c5 fa 7e c0                  	vmovq	%xmm0, %xmm0            # xmm0 = xmm0[0],zero
    258f: c5 f8 58 c2                  	vaddps	%xmm2, %xmm0, %xmm0
    2593: c5 f9 6e d0                  	vmovd	%eax, %xmm2
    2597: c5 ea 58 c9                  	vaddss	%xmm1, %xmm2, %xmm1
    259b: c5 f8 13 83 90 02 00 00      	vmovlps	%xmm0, 0x290(%rbx)
    25a3: c5 fa 11 8b 98 02 00 00      	vmovss	%xmm1, 0x298(%rbx)
    25ab: c5 f0 14 cf                  	vunpcklps	%xmm7, %xmm1, %xmm1 # xmm1 = xmm1[0],xmm7[0],xmm1[1],xmm7[1]
    25af: c5 f8 16 c1                  	vmovlhps	%xmm1, %xmm0, %xmm0     # xmm0 = xmm0[0],xmm1[0]
    25b3: c5 f8 11 07                  	vmovups	%xmm0, (%rdi)
    25b7: 48 8b 83 90 02 00 00         	movq	0x290(%rbx), %rax
    25be: 48 8b 93 98 02 00 00         	movq	0x298(%rbx), %rdx
    25c5: 48 89 43 40                  	movq	%rax, 0x40(%rbx)
    25c9: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    25d0: c5 f8 28 83 20 03 00 00      	vmovaps	0x320(%rbx), %xmm0
    25d8: 48 89 53 48                  	movq	%rdx, 0x48(%rbx)
    25dc: 89 c2                        	movl	%eax, %edx
    25de: c5 f8 11 43 30               	vmovups	%xmm0, 0x30(%rbx)
    25e3: 49 63 4c 11 68               	movslq	0x68(%r9,%rdx), %rcx
    25e8: 48 89 4b 40                  	movq	%rcx, 0x40(%rbx)
    25ec: 48 89 ca                     	movq	%rcx, %rdx
    25ef: 83 e1 04                     	andl	$0x4, %ecx
    25f2: 89 cf                        	movl	%ecx, %edi
    25f4: 48 89 7b 50                  	movq	%rdi, 0x50(%rbx)
    25f8: f6 c2 02                     	testb	$0x2, %dl
    25fb: 74 31                        	je	0x262e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd0e>
    25fd: c4 e1 f9 7e c6               	vmovq	%xmm0, %rsi
    2602: c7 43 60 00 00 00 00         	movl	$0x0, 0x60(%rbx)
    2609: c4 e3 79 16 43 64 02         	vpextrd	$0x2, %xmm0, 0x64(%rbx)
    2610: c4 e3 79 16 43 6c 03         	vpextrd	$0x3, %xmm0, 0x6c(%rbx)
    2617: c7 43 68 00 00 00 00         	movl	$0x0, 0x68(%rbx)
    261e: 48 85 f6                     	testq	%rsi, %rsi
    2621: 75 0b                        	jne	0x262e <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd0e>
    2623: 48 83 7b 60 00               	cmpq	$0x0, 0x60(%rbx)
    2628: 0f 84 92 00 00 00            	je	0x26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    262e: 83 e2 01                     	andl	$0x1, %edx
    2631: 89 d7                        	movl	%edx, %edi
    2633: 48 89 7b 40                  	movq	%rdi, 0x40(%rbx)
    2637: 85 c9                        	testl	%ecx, %ecx
    2639: 74 24                        	je	0x265f <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd3f>
    263b: 48 c7 43 38 00 00 00 00      	movq	$0x0, 0x38(%rbx)
    2643: c4 e3 79 16 43 34 03         	vpextrd	$0x3, %xmm0, 0x34(%rbx)
    264a: c4 e3 79 16 43 38 02         	vpextrd	$0x2, %xmm0, 0x38(%rbx)
    2651: c7 43 30 00 00 00 00         	movl	$0x0, 0x30(%rbx)
    2658: 48 83 7b 30 00               	cmpq	$0x0, 0x30(%rbx)
    265d: 7e 61                        	jle	0x26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    265f: 85 d2                        	testl	%edx, %edx
    2661: 0f 84 19 f5 ff ff            	je	0x1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    2667: c5 f8 28 83 00 03 00 00      	vmovaps	0x300(%rbx), %xmm0
    266f: c5 f8 11 43 30               	vmovups	%xmm0, 0x30(%rbx)
    2674: c4 e3 79 16 43 34 03         	vpextrd	$0x3, %xmm0, 0x34(%rbx)
    267b: c5 f8 28 83 10 03 00 00      	vmovaps	0x310(%rbx), %xmm0
    2683: c7 43 30 00 00 00 00         	movl	$0x0, 0x30(%rbx)
    268a: 48 8b 53 30                  	movq	0x30(%rbx), %rdx
    268e: c5 f8 11 43 30               	vmovups	%xmm0, 0x30(%rbx)
    2693: 48 85 d2                     	testq	%rdx, %rdx
    2696: 78 28                        	js	0x26c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda0>
    2698: 48 c7 43 38 00 00 00 00      	movq	$0x0, 0x38(%rbx)
    26a0: c4 e3 79 16 43 34 03         	vpextrd	$0x3, %xmm0, 0x34(%rbx)
    26a7: c4 e3 79 16 43 38 02         	vpextrd	$0x2, %xmm0, 0x38(%rbx)
    26ae: c7 43 30 00 00 00 00         	movl	$0x0, 0x30(%rbx)
    26b5: 48 83 7b 30 00               	cmpq	$0x0, 0x30(%rbx)
    26ba: 0f 89 c0 f4 ff ff            	jns	0x1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    26c0: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x26c7 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xda7>
		00000000000026c3:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0xc
    26c7: c5 fa 7e 83 c0 01 00 00      	vmovq	0x1c0(%rbx), %xmm0      # xmm0 = mem[0],zero
    26cf: 48 8b 8b 00 01 00 00         	movq	0x100(%rbx), %rcx
    26d6: c5 fa 7e a3 a0 00 00 00      	vmovq	0xa0(%rbx), %xmm4       # xmm4 = mem[0],zero
    26de: 48 63 12                     	movslq	(%rdx), %rdx
    26e1: c5 fa 7e ab 80 00 00 00      	vmovq	0x80(%rbx), %xmm5       # xmm5 = mem[0],zero
    26e9: c5 f9 d6 43 40               	vmovq	%xmm0, 0x40(%rbx)
    26ee: c4 e3 d9 22 93 b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%rbx), %xmm4, %xmm2
    26f8: c4 e1 f9 6e e0               	vmovq	%rax, %xmm4
    26fd: c4 e3 f9 22 c1 01            	vpinsrq	$0x1, %rcx, %xmm0, %xmm0
    2703: 48 63 b3 f0 01 00 00         	movslq	0x1f0(%rbx), %rsi
    270a: 48 89 93 90 01 00 00         	movq	%rdx, 0x190(%rbx)
    2711: 48 89 d7                     	movq	%rdx, %rdi
    2714: 48 8b 93 40 01 00 00         	movq	0x140(%rbx), %rdx
    271b: c4 e3 d1 22 8b 90 00 00 00 01	vpinsrq	$0x1, 0x90(%rbx), %xmm5, %xmm1
    2725: 48 89 4b 50                  	movq	%rcx, 0x50(%rbx)
    2729: 48 89 43 60                  	movq	%rax, 0x60(%rbx)
    272d: c4 e3 75 18 ca 01            	vinsertf128	$0x1, %xmm2, %ymm1, %ymm1
    2733: c4 e3 d9 22 d2 01            	vpinsrq	$0x1, %rdx, %xmm4, %xmm2
    2739: 48 89 53 70                  	movq	%rdx, 0x70(%rbx)
    273d: c4 e3 7d 18 c2 01            	vinsertf128	$0x1, %xmm2, %ymm0, %ymm0
    2743: 48 89 73 20                  	movq	%rsi, 0x20(%rbx)
    2747: c5 fd 7f 84 24 00 01 00 00   	vmovdqa	%ymm0, 0x100(%rsp)
    2750: c5 fd 7f 8c 24 20 01 00 00   	vmovdqa	%ymm1, 0x120(%rsp)
    2759: 85 ff                        	testl	%edi, %edi
    275b: 0f 84 7e 04 00 00            	je	0x2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    2761: 48 8b 8b 60 01 00 00         	movq	0x160(%rbx), %rcx
    2768: 4c 8b 83 70 01 00 00         	movq	0x170(%rbx), %r8
    276f: 89 ff                        	movl	%edi, %edi
    2771: 31 d2                        	xorl	%edx, %edx
    2773: 4c 01 cf                     	addq	%r9, %rdi
    2776: 48 8d b4 24 00 01 00 00      	leaq	0x100(%rsp), %rsi
    277e: c5 f8 77                     	vzeroupper
    2781: e8 00 00 00 00               	callq	0x2786 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe66>
		0000000000002782:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    2786: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x278d <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe6d>
		0000000000002789:  R_X86_64_PC32	g_ee_main_mem-0x4
    278d: 48 89 43 20                  	movq	%rax, 0x20(%rbx)
    2791: 48 8b 83 50 01 00 00         	movq	0x150(%rbx), %rax
    2798: e9 e3 f3 ff ff               	jmp	0x1b80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x260>
    279d: 0f 1f 00                     	nopl	(%rax)
    27a0: 48 89 53 30                  	movq	%rdx, 0x30(%rbx)
    27a4: e9 5f f4 ff ff               	jmp	0x1c08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2e8>
    27a9: 0f 1f 80 00 00 00 00         	nopl	(%rax)
    27b0: c4 c1 79 6e c5               	vmovd	%r13d, %xmm0
    27b5: 4c 8b 73 38                  	movq	0x38(%rbx), %r14
    27b9: 49 c1 ea 20                  	shrq	$0x20, %r10
    27bd: c5 fa 7e db                  	vmovq	%xmm3, %xmm3            # xmm3 = xmm3[0],zero
    27c1: c5 7a 10 35 00 00 00 00      	vmovss	(%rip), %xmm14          # xmm14 = mem[0],zero,zero,zero
                                                                        # 0x27c9 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xea9>
		00000000000027c5:  R_X86_64_PC32	.LC11-0x4
    27c9: c4 41 79 6e fe               	vmovd	%r14d, %xmm15
    27ce: c5 0a 5c d8                  	vsubss	%xmm0, %xmm14, %xmm11
    27d2: c5 aa 59 c0                  	vmulss	%xmm0, %xmm10, %xmm0
    27d6: c4 41 22 59 da               	vmulss	%xmm10, %xmm11, %xmm11
    27db: c4 41 0a 5c db               	vsubss	%xmm11, %xmm14, %xmm11
    27e0: c4 41 79 6e f2               	vmovd	%r10d, %xmm14
    27e5: c4 41 2a 59 f6               	vmulss	%xmm14, %xmm10, %xmm14
    27ea: c4 41 2a 59 d7               	vmulss	%xmm15, %xmm10, %xmm10
    27ef: c4 c1 4a 59 f3               	vmulss	%xmm11, %xmm6, %xmm6
    27f4: c4 c1 78 14 c6               	vunpcklps	%xmm14, %xmm0, %xmm0 # xmm0 = xmm0[0],xmm14[0],xmm0[1],xmm14[1]
    27f9: c4 41 28 14 d3               	vunpcklps	%xmm11, %xmm10, %xmm10 # xmm10 = xmm10[0],xmm11[0],xmm10[1],xmm11[1]
    27fe: c4 c1 78 16 c2               	vmovlhps	%xmm10, %xmm0, %xmm0    # xmm0 = xmm0[0],xmm10[0]
    2803: c5 f8 29 83 70 03 00 00      	vmovaps	%xmm0, 0x370(%rbx)
    280b: c4 c1 42 59 c1               	vmulss	%xmm9, %xmm7, %xmm0
    2810: c4 c1 42 59 f8               	vmulss	%xmm8, %xmm7, %xmm7
    2815: c4 41 7a 12 c3               	vmovsldup	%xmm11, %xmm8   # xmm8 = xmm11[0,0,2,2]
    281a: c5 fa 11 b3 38 03 00 00      	vmovss	%xmm6, 0x338(%rbx)
    2822: c4 41 7a 7e c0               	vmovq	%xmm8, %xmm8            # xmm8 = xmm8[0],zero
    2827: c4 c1 7a 58 c5               	vaddss	%xmm13, %xmm0, %xmm0
    282c: c5 b8 59 db                  	vmulps	%xmm3, %xmm8, %xmm3
    2830: c4 c1 42 58 fc               	vaddss	%xmm12, %xmm7, %xmm7
    2835: c4 c1 7a 59 c3               	vmulss	%xmm11, %xmm0, %xmm0
    283a: c4 c1 42 59 fb               	vmulss	%xmm11, %xmm7, %xmm7
    283f: c5 f8 13 9b 30 03 00 00      	vmovlps	%xmm3, 0x330(%rbx)
    2847: e9 7d f8 ff ff               	jmp	0x20c9 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x7a9>
    284c: 0f 1f 40 00                  	nopl	(%rax)
    2850: a8 0f                        	testb	$0xf, %al
    2852: 0f 85 68 03 00 00            	jne	0x2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    2858: 89 c0                        	movl	%eax, %eax
    285a: 83 e1 0f                     	andl	$0xf, %ecx
    285d: 49 8d 7c 01 10               	leaq	0x10(%r9,%rax), %rdi
    2862: 48 8b 07                     	movq	(%rdi), %rax
    2865: 48 8b 77 08                  	movq	0x8(%rdi), %rsi
    2869: 48 89 83 90 02 00 00         	movq	%rax, 0x290(%rbx)
    2870: 48 89 b3 98 02 00 00         	movq	%rsi, 0x298(%rbx)
    2877: 0f 85 43 03 00 00            	jne	0x2bc0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12a0>
    287d: 49 8b 04 11                  	movq	(%r9,%rdx), %rax
    2881: 49 8b 54 11 08               	movq	0x8(%r9,%rdx), %rdx
    2886: c5 f8 57 c0                  	vxorps	%xmm0, %xmm0, %xmm0
    288a: 48 c1 ee 20                  	shrq	$0x20, %rsi
    288e: c5 f9 6e f6                  	vmovd	%esi, %xmm6
    2892: 48 89 83 a0 02 00 00         	movq	%rax, 0x2a0(%rbx)
    2899: c5 f9 6e d0                  	vmovd	%eax, %xmm2
    289d: 48 c1 e8 20                  	shrq	$0x20, %rax
    28a1: c5 f9 6e e0                  	vmovd	%eax, %xmm4
    28a5: 48 89 93 a8 02 00 00         	movq	%rdx, 0x2a8(%rbx)
    28ac: c5 e8 14 d4                  	vunpcklps	%xmm4, %xmm2, %xmm2 # xmm2 = xmm2[0],xmm4[0],xmm2[1],xmm4[1]
    28b0: c5 fa 7e d2                  	vmovq	%xmm2, %xmm2            # xmm2 = xmm2[0],zero
    28b4: c5 f8 5c c2                  	vsubps	%xmm2, %xmm0, %xmm0
    28b8: c5 f9 6e d2                  	vmovd	%edx, %xmm2
    28bc: c5 f2 5c ca                  	vsubss	%xmm2, %xmm1, %xmm1
    28c0: c5 f8 13 83 90 02 00 00      	vmovlps	%xmm0, 0x290(%rbx)
    28c8: c5 fa 11 8b 98 02 00 00      	vmovss	%xmm1, 0x298(%rbx)
    28d0: c5 f0 14 ce                  	vunpcklps	%xmm6, %xmm1, %xmm1 # xmm1 = xmm1[0],xmm6[0],xmm1[1],xmm6[1]
    28d4: c5 f8 16 c1                  	vmovlhps	%xmm1, %xmm0, %xmm0     # xmm0 = xmm0[0],xmm1[0]
    28d8: c5 f8 11 07                  	vmovups	%xmm0, (%rdi)
    28dc: 48 8b 83 90 02 00 00         	movq	0x290(%rbx), %rax
    28e3: 48 8b 93 98 02 00 00         	movq	0x298(%rbx), %rdx
    28ea: e9 d6 fc ff ff               	jmp	0x25c5 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xca5>
    28ef: 90                           	nop
    28f0: 48 8b 83 d0 01 00 00         	movq	0x1d0(%rbx), %rax
    28f7: 48 89 4b 20                  	movq	%rcx, 0x20(%rbx)
    28fb: 89 c2                        	movl	%eax, %edx
    28fd: 49 8b 34 11                  	movq	(%r9,%rdx), %rsi
    2901: 48 89 b3 f0 01 00 00         	movq	%rsi, 0x1f0(%rbx)
    2908: 49 8b 54 11 08               	movq	0x8(%r9,%rdx), %rdx
    290d: 48 89 93 e0 01 00 00         	movq	%rdx, 0x1e0(%rbx)
    2914: 8d 90 90 00 00 00            	leal	0x90(%rax), %edx
    291a: 83 e2 f0                     	andl	$-0x10, %edx
    291d: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    2923: 8d 90 80 00 00 00            	leal	0x80(%rax), %edx
    2929: 83 e2 f0                     	andl	$-0x10, %edx
    292c: c5 fa 7f 83 c0 01 00 00      	vmovdqu	%xmm0, 0x1c0(%rbx)
    2934: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    293a: 8d 50 70                     	leal	0x70(%rax), %edx
    293d: 83 e2 f0                     	andl	$-0x10, %edx
    2940: c5 fa 7f 83 50 01 00 00      	vmovdqu	%xmm0, 0x150(%rbx)
    2948: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    294e: 8d 50 60                     	leal	0x60(%rax), %edx
    2951: 83 e2 f0                     	andl	$-0x10, %edx
    2954: c5 fa 7f 83 40 01 00 00      	vmovdqu	%xmm0, 0x140(%rbx)
    295c: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    2962: 8d 50 50                     	leal	0x50(%rax), %edx
    2965: 83 e2 f0                     	andl	$-0x10, %edx
    2968: c5 fa 7f 83 30 01 00 00      	vmovdqu	%xmm0, 0x130(%rbx)
    2970: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    2976: 8d 50 40                     	leal	0x40(%rax), %edx
    2979: 83 e2 f0                     	andl	$-0x10, %edx
    297c: c5 fa 7f 83 20 01 00 00      	vmovdqu	%xmm0, 0x120(%rbx)
    2984: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    298a: 8d 50 30                     	leal	0x30(%rax), %edx
    298d: 48 05 a0 00 00 00            	addq	$0xa0, %rax
    2993: 83 e2 f0                     	andl	$-0x10, %edx
    2996: c5 fa 7f 83 10 01 00 00      	vmovdqu	%xmm0, 0x110(%rbx)
    299e: c4 c1 7a 6f 04 11            	vmovdqu	(%r9,%rdx), %xmm0
    29a4: 48 89 83 d0 01 00 00         	movq	%rax, 0x1d0(%rbx)
    29ab: 48 89 c8                     	movq	%rcx, %rax
    29ae: c5 fa 7f 83 00 01 00 00      	vmovdqu	%xmm0, 0x100(%rbx)
    29b6: 48 8d 65 e0                  	leaq	-0x20(%rbp), %rsp
    29ba: 5b                           	popq	%rbx
    29bb: 41 5c                        	popq	%r12
    29bd: 41 5d                        	popq	%r13
    29bf: 41 5e                        	popq	%r14
    29c1: 5d                           	popq	%rbp
    29c2: c3                           	retq
    29c3: 0f 1f 44 00 00               	nopl	(%rax,%rax)
    29c8: 48 8b 83 d0 01 00 00         	movq	0x1d0(%rbx), %rax
    29cf: c5 f9 6f 83 c0 01 00 00      	vmovdqa	0x1c0(%rbx), %xmm0
    29d7: 4c 8b 0d 00 00 00 00         	movq	(%rip), %r9             # 0x29de <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x10be>
		00000000000029da:  R_X86_64_PC32	g_ee_main_mem-0x4
    29de: 48 83 e8 60                  	subq	$0x60, %rax
    29e2: 48 89 83 d0 01 00 00         	movq	%rax, 0x1d0(%rbx)
    29e9: 83 e0 f0                     	andl	$-0x10, %eax
    29ec: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    29f2: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    29f8: c5 f9 6f 83 50 01 00 00      	vmovdqa	0x150(%rbx), %xmm0
    2a00: 83 c0 10                     	addl	$0x10, %eax
    2a03: 83 e0 f0                     	andl	$-0x10, %eax
    2a06: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    2a0c: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    2a12: c5 f9 6f 83 40 01 00 00      	vmovdqa	0x140(%rbx), %xmm0
    2a1a: 83 c0 20                     	addl	$0x20, %eax
    2a1d: 83 e0 f0                     	andl	$-0x10, %eax
    2a20: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    2a26: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    2a2c: c5 f9 6f 83 00 01 00 00      	vmovdqa	0x100(%rbx), %xmm0
    2a34: 83 c0 30                     	addl	$0x30, %eax
    2a37: 83 e0 f0                     	andl	$-0x10, %eax
    2a3a: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    2a40: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    2a46: c5 f9 6f 83 30 01 00 00      	vmovdqa	0x130(%rbx), %xmm0
    2a4e: 83 c0 40                     	addl	$0x40, %eax
    2a51: 83 e0 f0                     	andl	$-0x10, %eax
    2a54: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    2a5a: 8b 83 d0 01 00 00            	movl	0x1d0(%rbx), %eax
    2a60: c5 f9 6f 83 20 01 00 00      	vmovdqa	0x120(%rbx), %xmm0
    2a68: 83 c0 50                     	addl	$0x50, %eax
    2a6b: 83 e0 f0                     	andl	$-0x10, %eax
    2a6e: c4 c1 7a 7f 04 01            	vmovdqu	%xmm0, (%r9,%rax)
    2a74: c5 fa 7e 83 c0 01 00 00      	vmovq	0x1c0(%rbx), %xmm0      # xmm0 = mem[0],zero
    2a7c: 48 8b 93 40 01 00 00         	movq	0x140(%rbx), %rdx
    2a83: c5 fa 7e 93 50 01 00 00      	vmovq	0x150(%rbx), %xmm2      # xmm2 = mem[0],zero
    2a8b: 48 8b 05 00 00 00 00         	movq	(%rip), %rax            # 0x2a92 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1172>
		0000000000002a8e:  R_X86_64_PC32	Mips2C::jak1::sp_process_block_3d::cache+0x14
    2a92: c5 f9 d6 43 40               	vmovq	%xmm0, 0x40(%rbx)
    2a97: c5 fa 7e ab a0 00 00 00      	vmovq	0xa0(%rbx), %xmm5       # xmm5 = mem[0],zero
    2a9f: c5 f9 d6 53 60               	vmovq	%xmm2, 0x60(%rbx)
    2aa4: c4 e3 e9 22 d2 01            	vpinsrq	$0x1, %rdx, %xmm2, %xmm2
    2aaa: 48 89 53 70                  	movq	%rdx, 0x70(%rbx)
    2aae: 48 63 08                     	movslq	(%rax), %rcx
    2ab1: 48 89 8b 90 01 00 00         	movq	%rcx, 0x190(%rbx)
    2ab8: 48 89 c8                     	movq	%rcx, %rax
    2abb: 48 63 8b f0 01 00 00         	movslq	0x1f0(%rbx), %rcx
    2ac2: 48 89 4b 20                  	movq	%rcx, 0x20(%rbx)
    2ac6: c4 e3 d1 22 9b b0 00 00 00 01	vpinsrq	$0x1, 0xb0(%rbx), %xmm5, %xmm3
    2ad0: c5 fa 7e bb 80 00 00 00      	vmovq	0x80(%rbx), %xmm7       # xmm7 = mem[0],zero
    2ad8: c4 e3 f9 22 43 50 01         	vpinsrq	$0x1, 0x50(%rbx), %xmm0, %xmm0
    2adf: c4 e3 c1 22 8b 90 00 00 00 01	vpinsrq	$0x1, 0x90(%rbx), %xmm7, %xmm1
    2ae9: c4 e3 7d 18 c2 01            	vinsertf128	$0x1, %xmm2, %ymm0, %ymm0
    2aef: c4 e3 75 18 cb 01            	vinsertf128	$0x1, %xmm3, %ymm1, %ymm1
    2af5: c5 fd 7f 44 24 40            	vmovdqa	%ymm0, 0x40(%rsp)
    2afb: c5 fd 7f 4c 24 60            	vmovdqa	%ymm1, 0x60(%rsp)
    2b01: 85 c0                        	testl	%eax, %eax
    2b03: 0f 84 d6 00 00 00            	je	0x2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
    2b09: 48 8b 8b 60 01 00 00         	movq	0x160(%rbx), %rcx
    2b10: 89 c0                        	movl	%eax, %eax
    2b12: 31 d2                        	xorl	%edx, %edx
    2b14: 48 8d 74 24 40               	leaq	0x40(%rsp), %rsi
    2b19: 4c 8b 83 70 01 00 00         	movq	0x170(%rbx), %r8
    2b20: 49 8d 3c 01                  	leaq	(%r9,%rax), %rdi
    2b24: c5 f8 77                     	vzeroupper
    2b27: e8 00 00 00 00               	callq	0x2b2c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x120c>
		0000000000002b28:  R_X86_64_PLT32	_call_goal8_asm_systemv-0x4
    2b2c: 48 8b 15 00 00 00 00         	movq	(%rip), %rdx            # 0x2b33 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1213>
		0000000000002b2f:  R_X86_64_PC32	g_ee_main_mem-0x4
    2b33: 48 89 43 20                  	movq	%rax, 0x20(%rbx)
    2b37: 48 8b 83 d0 01 00 00         	movq	0x1d0(%rbx), %rax
    2b3e: 48 89 c1                     	movq	%rax, %rcx
    2b41: 83 e1 f0                     	andl	$-0x10, %ecx
    2b44: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    2b49: 8d 48 10                     	leal	0x10(%rax), %ecx
    2b4c: 83 e1 f0                     	andl	$-0x10, %ecx
    2b4f: c5 fa 7f 83 c0 01 00 00      	vmovdqu	%xmm0, 0x1c0(%rbx)
    2b57: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    2b5c: 8d 48 20                     	leal	0x20(%rax), %ecx
    2b5f: 83 e1 f0                     	andl	$-0x10, %ecx
    2b62: c5 fa 7f 83 50 01 00 00      	vmovdqu	%xmm0, 0x150(%rbx)
    2b6a: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    2b6f: 8d 48 30                     	leal	0x30(%rax), %ecx
    2b72: 83 e1 f0                     	andl	$-0x10, %ecx
    2b75: c5 fa 7f 83 40 01 00 00      	vmovdqu	%xmm0, 0x140(%rbx)
    2b7d: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    2b82: 8d 48 40                     	leal	0x40(%rax), %ecx
    2b85: 83 e1 f0                     	andl	$-0x10, %ecx
    2b88: c5 fa 7f 83 00 01 00 00      	vmovdqu	%xmm0, 0x100(%rbx)
    2b90: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    2b95: 8d 48 50                     	leal	0x50(%rax), %ecx
    2b98: 48 83 c0 60                  	addq	$0x60, %rax
    2b9c: 83 e1 f0                     	andl	$-0x10, %ecx
    2b9f: c5 fa 7f 83 30 01 00 00      	vmovdqu	%xmm0, 0x130(%rbx)
    2ba7: c5 fa 6f 04 0a               	vmovdqu	(%rdx,%rcx), %xmm0
    2bac: 48 89 83 d0 01 00 00         	movq	%rax, 0x1d0(%rbx)
    2bb3: c5 fa 7f 83 20 01 00 00      	vmovdqu	%xmm0, 0x120(%rbx)
    2bbb: e9 62 f3 ff ff               	jmp	0x1f22 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x602>
    2bc0: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		0000000000002bc2:  R_X86_64_32	.rodata.str1.1+0xe
    2bc6: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000002bc7:  R_X86_64_32	.rodata.str1.8
    2bcb: ba 58 01 00 00               	movl	$0x158, %edx            # imm = 0x158
    2bd0: be 00 00 00 00               	movl	$0x0, %esi
		0000000000002bd1:  R_X86_64_32	.rodata.str1.8+0x38
    2bd5: bf 00 00 00 00               	movl	$0x0, %edi
		0000000000002bd6:  R_X86_64_32	.rodata.str1.8+0x78
    2bda: e8 00 00 00 00               	callq	0x2bdf <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12bf>
		0000000000002bdb:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2bdf: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		0000000000002be1:  R_X86_64_32	.rodata.str1.1+0xe
    2be5: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000002be6:  R_X86_64_32	.rodata.str1.8+0xa8
    2bea: ba 90 01 00 00               	movl	$0x190, %edx            # imm = 0x190
    2bef: be 00 00 00 00               	movl	$0x0, %esi
		0000000000002bf0:  R_X86_64_32	.rodata.str1.8+0x38
    2bf4: bf 00 00 00 00               	movl	$0x0, %edi
		0000000000002bf5:  R_X86_64_32	.rodata.str1.1+0xf
    2bf9: c5 f8 77                     	vzeroupper
    2bfc: e8 00 00 00 00               	callq	0x2c01 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x12e1>
		0000000000002bfd:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2c01: 41 b8 00 00 00 00            	movl	$0x0, %r8d
		0000000000002c03:  R_X86_64_32	.rodata.str1.1+0xe
    2c07: b9 00 00 00 00               	movl	$0x0, %ecx
		0000000000002c08:  R_X86_64_32	.rodata.str1.8+0x1a0
    2c0c: ba c0 01 00 00               	movl	$0x1c0, %edx            # imm = 0x1C0
    2c11: be 00 00 00 00               	movl	$0x0, %esi
		0000000000002c12:  R_X86_64_32	.rodata.str1.8+0x38
    2c16: bf 00 00 00 00               	movl	$0x0, %edi
		0000000000002c17:  R_X86_64_32	.rodata.str1.8+0x1d8
    2c1b: c5 f8 77                     	vzeroupper
    2c1e: e8 00 00 00 00               	callq	0x2c23 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x1303>
		0000000000002c1f:  R_X86_64_PLT32	private_assert_failed(char const*, char const*, int, char const*, char const*)-0x4
    2c23: 66 90                        	nop
    2c25: 66 66 2e 0f 1f 84 00 00 00 00 00     	nopw	%cs:(%rax,%rax)
