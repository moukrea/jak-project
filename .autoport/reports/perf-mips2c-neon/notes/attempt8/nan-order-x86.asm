
.autoport/reports/perf-mips2c-neon/notes/attempt8/nan-order-x86:     file format elf64-x86-64


Disassembly of section .init:

000000000040033c <_init>:
  40033c:	f3 0f 1e fa          	endbr64
  400340:	48 83 ec 08          	sub    $0x8,%rsp
  400344:	48 8b 05 95 2c 00 00 	mov    0x2c95(%rip),%rax        # 402fe0 <__gmon_start__@Base>
  40034b:	48 85 c0             	test   %rax,%rax
  40034e:	74 02                	je     400352 <_init+0x16>
  400350:	ff d0                	call   *%rax
  400352:	48 83 c4 08          	add    $0x8,%rsp
  400356:	c3                   	ret

Disassembly of section .plt:

0000000000400360 <printf@plt-0x10>:
  400360:	ff 35 8a 2c 00 00    	push   0x2c8a(%rip)        # 402ff0 <_GLOBAL_OFFSET_TABLE_+0x8>
  400366:	ff 25 8c 2c 00 00    	jmp    *0x2c8c(%rip)        # 402ff8 <_GLOBAL_OFFSET_TABLE_+0x10>
  40036c:	0f 1f 40 00          	nopl   0x0(%rax)

0000000000400370 <printf@plt>:
  400370:	ff 25 8a 2c 00 00    	jmp    *0x2c8a(%rip)        # 403000 <printf@GLIBC_2.2.5>
  400376:	68 00 00 00 00       	push   $0x0
  40037b:	e9 e0 ff ff ff       	jmp    400360 <_init+0x24>

Disassembly of section .text:

0000000000400380 <main>:
  400380:	4c 8d 54 24 08       	lea    0x8(%rsp),%r10
  400385:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
  400389:	41 ff 72 f8          	push   -0x8(%r10)
  40038d:	55                   	push   %rbp
  40038e:	48 89 e5             	mov    %rsp,%rbp
  400391:	41 55                	push   %r13
  400393:	41 54                	push   %r12
  400395:	45 31 e4             	xor    %r12d,%r12d
  400398:	4c 8d 6d c0          	lea    -0x40(%rbp),%r13
  40039c:	41 52                	push   %r10
  40039e:	53                   	push   %rbx
  40039f:	48 8d 5d 90          	lea    -0x70(%rbp),%rbx
  4003a3:	48 83 ec 50          	sub    $0x50,%rsp
  4003a7:	c5 fd 6f 05 91 0e 00 	vmovdqa 0xe91(%rip),%ymm0        # 401240 <__dso_handle+0x98>
  4003ae:	00 
  4003af:	c5 fd 7f 45 90       	vmovdqa %ymm0,-0x70(%rbp)
  4003b4:	c5 f9 6f 05 a4 0e 00 	vmovdqa 0xea4(%rip),%xmm0        # 401260 <__dso_handle+0xb8>
  4003bb:	00 
  4003bc:	c5 f9 7f 45 b0       	vmovdqa %xmm0,-0x50(%rbp)
  4003c1:	c5 f8 77             	vzeroupper
  4003c4:	90                   	nop
  4003c5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  4003cc:	00 00 00 00 
  4003d0:	8b 53 04             	mov    0x4(%rbx),%edx
  4003d3:	8b 33                	mov    (%rbx),%esi
  4003d5:	45 31 c9             	xor    %r9d,%r9d
  4003d8:	bf b0 11 40 00       	mov    $0x4011b0,%edi
  4003dd:	c5 f9 6e ca          	vmovd  %edx,%xmm1
  4003e1:	c5 f9 6e c6          	vmovd  %esi,%xmm0
  4003e5:	e8 46 01 00 00       	call   400530 <ordered_mul(float, float)>
  4003ea:	c5 f9 6e ce          	vmovd  %esi,%xmm1
  4003ee:	c5 f9 7e c1          	vmovd  %xmm0,%ecx
  4003f2:	c5 f9 6e c2          	vmovd  %edx,%xmm0
  4003f6:	e8 35 01 00 00       	call   400530 <ordered_mul(float, float)>
  4003fb:	c4 c1 79 7e c0       	vmovd  %xmm0,%r8d
  400400:	44 39 c1             	cmp    %r8d,%ecx
  400403:	41 0f 95 c1          	setne  %r9b
  400407:	31 c0                	xor    %eax,%eax
  400409:	48 83 c3 08          	add    $0x8,%rbx
  40040d:	45 01 cc             	add    %r9d,%r12d
  400410:	e8 5b ff ff ff       	call   400370 <printf@plt>
  400415:	49 39 dd             	cmp    %rbx,%r13
  400418:	75 b6                	jne    4003d0 <main+0x50>
  40041a:	44 89 e6             	mov    %r12d,%esi
  40041d:	bf 00 12 40 00       	mov    $0x401200,%edi
  400422:	31 c0                	xor    %eax,%eax
  400424:	e8 47 ff ff ff       	call   400370 <printf@plt>
  400429:	48 83 c4 50          	add    $0x50,%rsp
  40042d:	31 c0                	xor    %eax,%eax
  40042f:	5b                   	pop    %rbx
  400430:	41 5a                	pop    %r10
  400432:	41 5c                	pop    %r12
  400434:	41 5d                	pop    %r13
  400436:	5d                   	pop    %rbp
  400437:	49 8d 62 f8          	lea    -0x8(%r10),%rsp
  40043b:	c3                   	ret
  40043c:	0f 1f 40 00          	nopl   0x0(%rax)

0000000000400440 <_start>:
  400440:	f3 0f 1e fa          	endbr64
  400444:	31 ed                	xor    %ebp,%ebp
  400446:	49 89 d1             	mov    %rdx,%r9
  400449:	5e                   	pop    %rsi
  40044a:	48 89 e2             	mov    %rsp,%rdx
  40044d:	48 83 e4 f0          	and    $0xfffffffffffffff0,%rsp
  400451:	50                   	push   %rax
  400452:	54                   	push   %rsp
  400453:	45 31 c0             	xor    %r8d,%r8d
  400456:	31 c9                	xor    %ecx,%ecx
  400458:	48 c7 c7 80 03 40 00 	mov    $0x400380,%rdi
  40045f:	ff 15 73 2b 00 00    	call   *0x2b73(%rip)        # 402fd8 <__libc_start_main@GLIBC_2.34>
  400465:	f4                   	hlt
  400466:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  40046d:	00 00 00 

0000000000400470 <_dl_relocate_static_pie>:
  400470:	f3 0f 1e fa          	endbr64
  400474:	c3                   	ret
  400475:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  40047c:	00 00 00 
  40047f:	90                   	nop

0000000000400480 <deregister_tm_clones>:
  400480:	b8 10 30 40 00       	mov    $0x403010,%eax
  400485:	48 3d 10 30 40 00    	cmp    $0x403010,%rax
  40048b:	74 13                	je     4004a0 <deregister_tm_clones+0x20>
  40048d:	b8 00 00 00 00       	mov    $0x0,%eax
  400492:	48 85 c0             	test   %rax,%rax
  400495:	74 09                	je     4004a0 <deregister_tm_clones+0x20>
  400497:	bf 10 30 40 00       	mov    $0x403010,%edi
  40049c:	ff e0                	jmp    *%rax
  40049e:	66 90                	xchg   %ax,%ax
  4004a0:	c3                   	ret
  4004a1:	0f 1f 40 00          	nopl   0x0(%rax)
  4004a5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  4004ac:	00 00 00 00 

00000000004004b0 <register_tm_clones>:
  4004b0:	be 10 30 40 00       	mov    $0x403010,%esi
  4004b5:	48 81 ee 10 30 40 00 	sub    $0x403010,%rsi
  4004bc:	48 89 f0             	mov    %rsi,%rax
  4004bf:	48 c1 ee 3f          	shr    $0x3f,%rsi
  4004c3:	48 c1 f8 03          	sar    $0x3,%rax
  4004c7:	48 01 c6             	add    %rax,%rsi
  4004ca:	48 d1 fe             	sar    $1,%rsi
  4004cd:	74 11                	je     4004e0 <register_tm_clones+0x30>
  4004cf:	b8 00 00 00 00       	mov    $0x0,%eax
  4004d4:	48 85 c0             	test   %rax,%rax
  4004d7:	74 07                	je     4004e0 <register_tm_clones+0x30>
  4004d9:	bf 10 30 40 00       	mov    $0x403010,%edi
  4004de:	ff e0                	jmp    *%rax
  4004e0:	c3                   	ret
  4004e1:	0f 1f 40 00          	nopl   0x0(%rax)
  4004e5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  4004ec:	00 00 00 00 

00000000004004f0 <__do_global_dtors_aux>:
  4004f0:	f3 0f 1e fa          	endbr64
  4004f4:	80 3d 11 2b 00 00 00 	cmpb   $0x0,0x2b11(%rip)        # 40300c <completed.0>
  4004fb:	75 13                	jne    400510 <__do_global_dtors_aux+0x20>
  4004fd:	55                   	push   %rbp
  4004fe:	48 89 e5             	mov    %rsp,%rbp
  400501:	e8 7a ff ff ff       	call   400480 <deregister_tm_clones>
  400506:	c6 05 ff 2a 00 00 01 	movb   $0x1,0x2aff(%rip)        # 40300c <completed.0>
  40050d:	5d                   	pop    %rbp
  40050e:	c3                   	ret
  40050f:	90                   	nop
  400510:	c3                   	ret
  400511:	0f 1f 40 00          	nopl   0x0(%rax)
  400515:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  40051c:	00 00 00 00 

0000000000400520 <frame_dummy>:
  400520:	f3 0f 1e fa          	endbr64
  400524:	eb 8a                	jmp    4004b0 <register_tm_clones>
  400526:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  40052d:	00 00 00 

0000000000400530 <ordered_mul(float, float)>:
  400530:	c5 fa 59 c1          	vmulss %xmm1,%xmm0,%xmm0
  400534:	c3                   	ret

Disassembly of section .fini:

0000000000400538 <_fini>:
  400538:	f3 0f 1e fa          	endbr64
  40053c:	48 83 ec 08          	sub    $0x8,%rsp
  400540:	48 83 c4 08          	add    $0x8,%rsp
  400544:	c3                   	ret
