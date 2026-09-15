
.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-block-parity-x86:     file format elf64-x86-64


Disassembly of section .init:

000000000040033c <_init>:
  40033c:	f3 0f 1e fa          	endbr64
  400340:	48 83 ec 08          	sub    $0x8,%rsp
  400344:	48 8b 05 95 3c 00 00 	mov    0x3c95(%rip),%rax        # 403fe0 <__gmon_start__@Base>
  40034b:	48 85 c0             	test   %rax,%rax
  40034e:	74 02                	je     400352 <_init+0x16>
  400350:	ff d0                	call   *%rax
  400352:	48 83 c4 08          	add    $0x8,%rsp
  400356:	c3                   	ret

Disassembly of section .plt:

0000000000400360 <printf@plt-0x10>:
  400360:	ff 35 8a 3c 00 00    	push   0x3c8a(%rip)        # 403ff0 <_GLOBAL_OFFSET_TABLE_+0x8>
  400366:	ff 25 8c 3c 00 00    	jmp    *0x3c8c(%rip)        # 403ff8 <_GLOBAL_OFFSET_TABLE_+0x10>
  40036c:	0f 1f 40 00          	nopl   0x0(%rax)

0000000000400370 <printf@plt>:
  400370:	ff 25 8a 3c 00 00    	jmp    *0x3c8a(%rip)        # 404000 <printf@GLIBC_2.2.5>
  400376:	68 00 00 00 00       	push   $0x0
  40037b:	e9 e0 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400380 <memcmp@plt>:
  400380:	ff 25 82 3c 00 00    	jmp    *0x3c82(%rip)        # 404008 <memcmp@GLIBC_2.2.5>
  400386:	68 01 00 00 00       	push   $0x1
  40038b:	e9 d0 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400390 <abort@plt>:
  400390:	ff 25 7a 3c 00 00    	jmp    *0x3c7a(%rip)        # 404010 <abort@GLIBC_2.2.5>
  400396:	68 02 00 00 00       	push   $0x2
  40039b:	e9 c0 ff ff ff       	jmp    400360 <_init+0x24>

00000000004003a0 <fprintf@plt>:
  4003a0:	ff 25 72 3c 00 00    	jmp    *0x3c72(%rip)        # 404018 <fprintf@GLIBC_2.2.5>
  4003a6:	68 03 00 00 00       	push   $0x3
  4003ab:	e9 b0 ff ff ff       	jmp    400360 <_init+0x24>

Disassembly of section .text:

00000000004003c0 <main>:
  4003c0:	55                   	push   %rbp
  4003c1:	48 89 e5             	mov    %rsp,%rbp
  4003c4:	41 57                	push   %r15
  4003c6:	41 56                	push   %r14
  4003c8:	45 31 f6             	xor    %r14d,%r14d
  4003cb:	41 55                	push   %r13
  4003cd:	41 54                	push   %r12
  4003cf:	41 bc cd cc cc cc    	mov    $0xcccccccd,%r12d
  4003d5:	53                   	push   %rbx
  4003d6:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
  4003da:	48 81 ec 60 15 00 00 	sub    $0x1560,%rsp
  4003e1:	c5 f9 6f 05 67 21 00 	vmovdqa 0x2167(%rip),%xmm0        # 402550 <__dso_handle+0x2c0>
  4003e8:	00 
  4003e9:	48 8b 05 d0 21 00 00 	mov    0x21d0(%rip),%rax        # 4025c0 <__dso_handle+0x330>
  4003f0:	c7 44 24 5c 00 00 00 	movl   $0x0,0x5c(%rsp)
  4003f7:	00 
  4003f8:	4c 8d bc 24 a0 0b 00 	lea    0xba0(%rsp),%r15
  4003ff:	00 
  400400:	48 8d 9c 24 20 09 00 	lea    0x920(%rsp),%rbx
  400407:	00 
  400408:	48 89 84 24 d0 00 00 	mov    %rax,0xd0(%rsp)
  40040f:	00 
  400410:	48 8d 84 24 20 07 00 	lea    0x720(%rsp),%rax
  400417:	00 
  400418:	4c 8d ac 24 20 01 00 	lea    0x120(%rsp),%r13
  40041f:	00 
  400420:	c5 f9 7f 84 24 c0 00 	vmovdqa %xmm0,0xc0(%rsp)
  400427:	00 00 
  400429:	c5 fd 6f 05 af 21 00 	vmovdqa 0x21af(%rip),%ymm0        # 4025e0 <__dso_handle+0x350>
  400430:	00 
  400431:	48 89 84 24 a8 00 00 	mov    %rax,0xa8(%rsp)
  400438:	00 
  400439:	48 8d 84 24 e0 0b 00 	lea    0xbe0(%rsp),%rax
  400440:	00 
  400441:	c5 fd 7f 84 24 e0 00 	vmovdqa %ymm0,0xe0(%rsp)
  400448:	00 00 
  40044a:	c5 f9 6f 05 0e 21 00 	vmovdqa 0x210e(%rip),%xmm0        # 402560 <__dso_handle+0x2d0>
  400451:	00 
  400452:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  400459:	00 
  40045a:	48 8d 84 24 a0 10 00 	lea    0x10a0(%rsp),%rax
  400461:	00 
  400462:	c7 84 24 88 00 00 00 	movl   $0x0,0x88(%rsp)
  400469:	00 00 00 00 
  40046d:	c7 84 24 8c 00 00 00 	movl   $0x0,0x8c(%rsp)
  400474:	00 00 00 00 
  400478:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
  40047f:	00 
  400480:	b8 b9 79 37 9e       	mov    $0x9e3779b9,%eax
  400485:	c5 f9 7f 84 24 00 01 	vmovdqa %xmm0,0x100(%rsp)
  40048c:	00 00 
  40048e:	c5 f9 76 c0          	vpcmpeqd %xmm0,%xmm0,%xmm0
  400492:	c5 f9 6e f0          	vmovd  %eax,%xmm6
  400496:	c5 e1 72 d0 1f       	vpsrld $0x1f,%xmm0,%xmm3
  40049b:	c5 f9 70 e6 00       	vpshufd $0x0,%xmm6,%xmm4
  4004a0:	41 83 fe 14          	cmp    $0x14,%r14d
  4004a4:	c4 c1 79 6e fe       	vmovd  %r14d,%xmm7
  4004a9:	44 89 b4 24 80 00 00 	mov    %r14d,0x80(%rsp)
  4004b0:	00 
  4004b1:	4d 89 ea             	mov    %r13,%r10
  4004b4:	45 19 db             	sbb    %r11d,%r11d
  4004b7:	c5 f9 70 ff 00       	vpshufd $0x0,%xmm7,%xmm7
  4004bc:	41 bd 06 00 00 00    	mov    $0x6,%r13d
  4004c2:	c5 f9 7f 7c 24 40    	vmovdqa %xmm7,0x40(%rsp)
  4004c8:	41 f7 d3             	not    %r11d
  4004cb:	41 83 e3 07          	and    $0x7,%r11d
  4004cf:	44 89 d8             	mov    %r11d,%eax
  4004d2:	c1 e0 07             	shl    $0x7,%eax
  4004d5:	42 8d 14 30          	lea    (%rax,%r14,1),%edx
  4004d9:	48 89 d0             	mov    %rdx,%rax
  4004dc:	49 0f af d4          	imul   %r12,%rdx
  4004e0:	89 c7                	mov    %eax,%edi
  4004e2:	48 c1 ea 24          	shr    $0x24,%rdx
  4004e6:	8d 14 92             	lea    (%rdx,%rdx,4),%edx
  4004e9:	c1 e2 02             	shl    $0x2,%edx
  4004ec:	29 d7                	sub    %edx,%edi
  4004ee:	42 8d 14 18          	lea    (%rax,%r11,1),%edx
  4004f2:	48 89 d0             	mov    %rdx,%rax
  4004f5:	49 0f af d4          	imul   %r12,%rdx
  4004f9:	89 7c 24 30          	mov    %edi,0x30(%rsp)
  4004fd:	89 c6                	mov    %eax,%esi
  4004ff:	48 c1 ea 24          	shr    $0x24,%rdx
  400503:	8d 14 92             	lea    (%rdx,%rdx,4),%edx
  400506:	c1 e2 02             	shl    $0x2,%edx
  400509:	29 d6                	sub    %edx,%esi
  40050b:	42 8d 14 18          	lea    (%rax,%r11,1),%edx
  40050f:	48 89 d0             	mov    %rdx,%rax
  400512:	49 0f af d4          	imul   %r12,%rdx
  400516:	89 74 24 20          	mov    %esi,0x20(%rsp)
  40051a:	89 c7                	mov    %eax,%edi
  40051c:	48 c1 ea 24          	shr    $0x24,%rdx
  400520:	8d 14 92             	lea    (%rdx,%rdx,4),%edx
  400523:	c1 e2 02             	shl    $0x2,%edx
  400526:	29 d7                	sub    %edx,%edi
  400528:	42 8d 14 18          	lea    (%rax,%r11,1),%edx
  40052c:	48 89 d0             	mov    %rdx,%rax
  40052f:	49 0f af d4          	imul   %r12,%rdx
  400533:	89 7c 24 18          	mov    %edi,0x18(%rsp)
  400537:	89 c6                	mov    %eax,%esi
  400539:	48 c1 ea 24          	shr    $0x24,%rdx
  40053d:	8d 14 92             	lea    (%rdx,%rdx,4),%edx
  400540:	c1 e2 02             	shl    $0x2,%edx
  400543:	29 d6                	sub    %edx,%esi
  400545:	42 8d 14 18          	lea    (%rax,%r11,1),%edx
  400549:	48 89 d0             	mov    %rdx,%rax
  40054c:	49 0f af d4          	imul   %r12,%rdx
  400550:	89 74 24 38          	mov    %esi,0x38(%rsp)
  400554:	48 c1 ea 24          	shr    $0x24,%rdx
  400558:	8d 14 92             	lea    (%rdx,%rdx,4),%edx
  40055b:	c1 e2 02             	shl    $0x2,%edx
  40055e:	29 d0                	sub    %edx,%eax
  400560:	89 44 24 3c          	mov    %eax,0x3c(%rsp)
  400564:	44 89 f0             	mov    %r14d,%eax
  400567:	41 83 c6 01          	add    $0x1,%r14d
  40056b:	35 b9 79 37 9e       	xor    $0x9e3779b9,%eax
  400570:	89 44 24 14          	mov    %eax,0x14(%rsp)
  400574:	4c 89 e8             	mov    %r13,%rax
  400577:	44 89 74 24 08       	mov    %r14d,0x8(%rsp)
  40057c:	48 f7 d8             	neg    %rax
  40057f:	4c 89 2c 24          	mov    %r13,(%rsp)
  400583:	45 89 dd             	mov    %r11d,%r13d
  400586:	48 c1 e0 03          	shl    $0x3,%rax
  40058a:	48 89 44 24 50       	mov    %rax,0x50(%rsp)
  40058f:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  400596:	00 
  400597:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  40059e:	00 
  40059f:	c5 fd 6f 35 59 20 00 	vmovdqa 0x2059(%rip),%ymm6        # 402600 <__dso_handle+0x370>
  4005a6:	00 
  4005a7:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
  4005ae:	00 
  4005af:	b9 98 00 00 00       	mov    $0x98,%ecx
  4005b4:	48 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%rdi
  4005bb:	00 
  4005bc:	c5 fd 7f b4 24 a0 10 	vmovdqa %ymm6,0x10a0(%rsp)
  4005c3:	00 00 
  4005c5:	8b 00                	mov    (%rax),%eax
  4005c7:	c5 fd 6f 35 51 20 00 	vmovdqa 0x2051(%rip),%ymm6        # 402620 <__dso_handle+0x390>
  4005ce:	00 
  4005cf:	c5 fd 7f b4 24 c0 10 	vmovdqa %ymm6,0x10c0(%rsp)
  4005d6:	00 00 
  4005d8:	c5 f9 6f 35 90 1f 00 	vmovdqa 0x1f90(%rip),%xmm6        # 402570 <__dso_handle+0x2e0>
  4005df:	00 
  4005e0:	89 84 24 b0 00 00 00 	mov    %eax,0xb0(%rsp)
  4005e7:	31 c0                	xor    %eax,%eax
  4005e9:	f3 48 ab             	rep stos %rax,(%rdi)
  4005ec:	c5 f9 7f b4 24 e0 10 	vmovdqa %xmm6,0x10e0(%rsp)
  4005f3:	00 00 
  4005f5:	83 bc 24 80 00 00 00 	cmpl   $0x27,0x80(%rsp)
  4005fc:	27 
  4005fd:	0f 86 bc 0d 00 00    	jbe    4013bf <main+0xfff>
  400603:	8b 44 24 14          	mov    0x14(%rsp),%eax
  400607:	48 8d 8c 24 a0 09 00 	lea    0x9a0(%rsp),%rcx
  40060e:	00 
  40060f:	90                   	nop
  400610:	89 c2                	mov    %eax,%edx
  400612:	48 83 c1 10          	add    $0x10,%rcx
  400616:	c1 e2 0d             	shl    $0xd,%edx
  400619:	31 d0                	xor    %edx,%eax
  40061b:	89 c2                	mov    %eax,%edx
  40061d:	c1 ea 11             	shr    $0x11,%edx
  400620:	31 c2                	xor    %eax,%edx
  400622:	89 d0                	mov    %edx,%eax
  400624:	c1 e0 05             	shl    $0x5,%eax
  400627:	31 d0                	xor    %edx,%eax
  400629:	89 c6                	mov    %eax,%esi
  40062b:	89 41 f0             	mov    %eax,-0x10(%rcx)
  40062e:	c1 e6 0d             	shl    $0xd,%esi
  400631:	31 c6                	xor    %eax,%esi
  400633:	89 f2                	mov    %esi,%edx
  400635:	c1 ea 11             	shr    $0x11,%edx
  400638:	31 f2                	xor    %esi,%edx
  40063a:	89 d0                	mov    %edx,%eax
  40063c:	c1 e0 05             	shl    $0x5,%eax
  40063f:	31 d0                	xor    %edx,%eax
  400641:	89 c2                	mov    %eax,%edx
  400643:	89 41 f4             	mov    %eax,-0xc(%rcx)
  400646:	c1 e2 0d             	shl    $0xd,%edx
  400649:	31 d0                	xor    %edx,%eax
  40064b:	89 c2                	mov    %eax,%edx
  40064d:	c1 ea 11             	shr    $0x11,%edx
  400650:	31 c2                	xor    %eax,%edx
  400652:	89 d0                	mov    %edx,%eax
  400654:	c1 e0 05             	shl    $0x5,%eax
  400657:	31 d0                	xor    %edx,%eax
  400659:	89 c2                	mov    %eax,%edx
  40065b:	89 41 f8             	mov    %eax,-0x8(%rcx)
  40065e:	c1 e2 0d             	shl    $0xd,%edx
  400661:	31 d0                	xor    %edx,%eax
  400663:	89 c2                	mov    %eax,%edx
  400665:	c1 ea 11             	shr    $0x11,%edx
  400668:	31 c2                	xor    %eax,%edx
  40066a:	89 d0                	mov    %edx,%eax
  40066c:	c1 e0 05             	shl    $0x5,%eax
  40066f:	31 d0                	xor    %edx,%eax
  400671:	89 41 fc             	mov    %eax,-0x4(%rcx)
  400674:	49 39 cf             	cmp    %rcx,%r15
  400677:	75 97                	jne    400610 <main+0x250>
  400679:	89 c2                	mov    %eax,%edx
  40067b:	c1 e2 0d             	shl    $0xd,%edx
  40067e:	31 c2                	xor    %eax,%edx
  400680:	89 d0                	mov    %edx,%eax
  400682:	c1 e8 11             	shr    $0x11,%eax
  400685:	31 d0                	xor    %edx,%eax
  400687:	41 89 c1             	mov    %eax,%r9d
  40068a:	41 c1 e1 05          	shl    $0x5,%r9d
  40068e:	41 31 c1             	xor    %eax,%r9d
  400691:	44 89 ca             	mov    %r9d,%edx
  400694:	c1 e2 0d             	shl    $0xd,%edx
  400697:	44 31 ca             	xor    %r9d,%edx
  40069a:	89 d0                	mov    %edx,%eax
  40069c:	c1 e8 11             	shr    $0x11,%eax
  40069f:	31 d0                	xor    %edx,%eax
  4006a1:	41 89 c0             	mov    %eax,%r8d
  4006a4:	41 c1 e0 05          	shl    $0x5,%r8d
  4006a8:	41 31 c0             	xor    %eax,%r8d
  4006ab:	44 89 c2             	mov    %r8d,%edx
  4006ae:	c1 e2 0d             	shl    $0xd,%edx
  4006b1:	44 31 c2             	xor    %r8d,%edx
  4006b4:	89 d0                	mov    %edx,%eax
  4006b6:	c1 e8 11             	shr    $0x11,%eax
  4006b9:	31 d0                	xor    %edx,%eax
  4006bb:	89 c6                	mov    %eax,%esi
  4006bd:	c1 e6 05             	shl    $0x5,%esi
  4006c0:	31 c6                	xor    %eax,%esi
  4006c2:	89 f2                	mov    %esi,%edx
  4006c4:	c1 e2 0d             	shl    $0xd,%edx
  4006c7:	31 f2                	xor    %esi,%edx
  4006c9:	89 d0                	mov    %edx,%eax
  4006cb:	c1 e8 11             	shr    $0x11,%eax
  4006ce:	31 d0                	xor    %edx,%eax
  4006d0:	89 c2                	mov    %eax,%edx
  4006d2:	c1 e2 05             	shl    $0x5,%edx
  4006d5:	31 c2                	xor    %eax,%edx
  4006d7:	89 d1                	mov    %edx,%ecx
  4006d9:	c1 e1 0d             	shl    $0xd,%ecx
  4006dc:	31 d1                	xor    %edx,%ecx
  4006de:	89 c8                	mov    %ecx,%eax
  4006e0:	c1 e8 11             	shr    $0x11,%eax
  4006e3:	31 c8                	xor    %ecx,%eax
  4006e5:	89 c1                	mov    %eax,%ecx
  4006e7:	c1 e1 05             	shl    $0x5,%ecx
  4006ea:	31 c1                	xor    %eax,%ecx
  4006ec:	41 89 cb             	mov    %ecx,%r11d
  4006ef:	c5 f9 6f 74 24 40    	vmovdqa 0x40(%rsp),%xmm6
  4006f5:	48 8b 84 24 a8 00 00 	mov    0xa8(%rsp),%rax
  4006fc:	00 
  4006fd:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  400701:	c5 c9 fe 15 77 1e 00 	vpaddd 0x1e77(%rip),%xmm6,%xmm2        # 402580 <__dso_handle+0x2f0>
  400708:	00 
  400709:	90                   	nop
  40070a:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  400711:	00 00 00 00 
  400715:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  40071c:	00 00 00 00 
  400720:	c5 f9 72 f1 02       	vpslld $0x2,%xmm1,%xmm0
  400725:	48 83 c0 10          	add    $0x10,%rax
  400729:	c5 f1 fe cb          	vpaddd %xmm3,%xmm1,%xmm1
  40072d:	c5 f9 fe c2          	vpaddd %xmm2,%xmm0,%xmm0
  400731:	c4 e2 79 40 c4       	vpmulld %xmm4,%xmm0,%xmm0
  400736:	c5 f9 7f 40 f0       	vmovdqa %xmm0,-0x10(%rax)
  40073b:	48 39 d8             	cmp    %rbx,%rax
  40073e:	75 e0                	jne    400720 <main+0x360>
  400740:	48 8b 44 24 50       	mov    0x50(%rsp),%rax
  400745:	b9 40 00 00 00       	mov    $0x40,%ecx
  40074a:	8b bc 04 10 01 00 00 	mov    0x110(%rsp,%rax,1),%edi
  400751:	44 8b b4 04 14 01 00 	mov    0x114(%rsp,%rax,1),%r14d
  400758:	00 
  400759:	31 c0                	xor    %eax,%eax
  40075b:	89 7c 24 58          	mov    %edi,0x58(%rsp)
  40075f:	89 bc 24 60 08 00 00 	mov    %edi,0x860(%rsp)
  400766:	4c 89 d7             	mov    %r10,%rdi
  400769:	f3 48 ab             	rep stos %rax,(%rdi)
  40076c:	44 89 b4 24 70 08 00 	mov    %r14d,0x870(%rsp)
  400773:	00 
  400774:	90                   	nop
  400775:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  40077c:	00 00 00 00 
  400780:	89 c1                	mov    %eax,%ecx
  400782:	89 c7                	mov    %eax,%edi
  400784:	c1 e9 02             	shr    $0x2,%ecx
  400787:	c1 ef 04             	shr    $0x4,%edi
  40078a:	83 e1 03             	and    $0x3,%ecx
  40078d:	48 8d 8c b9 a0 00 00 	lea    0xa0(%rcx,%rdi,4),%rcx
  400794:	00 
  400795:	8b 8c 8c 20 07 00 00 	mov    0x720(%rsp,%rcx,4),%ecx
  40079c:	41 89 0c 02          	mov    %ecx,(%r10,%rax,1)
  4007a0:	48 83 c0 04          	add    $0x4,%rax
  4007a4:	48 3d 00 02 00 00    	cmp    $0x200,%rax
  4007aa:	75 d4                	jne    400780 <main+0x3c0>
  4007ac:	8b bc 24 b0 00 00 00 	mov    0xb0(%rsp),%edi
  4007b3:	44 89 f0             	mov    %r14d,%eax
  4007b6:	89 94 24 ac 0b 00 00 	mov    %edx,0xbac(%rsp)
  4007bd:	b9 98 00 00 00       	mov    $0x98,%ecx
  4007c2:	44 89 8c 24 a0 0b 00 	mov    %r9d,0xba0(%rsp)
  4007c9:	00 
  4007ca:	89 bc 04 80 01 00 00 	mov    %edi,0x180(%rsp,%rax,1)
  4007d1:	48 8b bc 24 90 00 00 	mov    0x90(%rsp),%rdi
  4007d8:	00 
  4007d9:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  4007e0:	00 
  4007e1:	c5 7d 6f bc 24 20 01 	vmovdqa 0x120(%rsp),%ymm15
  4007e8:	00 00 
  4007ea:	89 b4 24 a8 0b 00 00 	mov    %esi,0xba8(%rsp)
  4007f1:	c5 7d 6f b4 24 40 01 	vmovdqa 0x140(%rsp),%ymm14
  4007f8:	00 00 
  4007fa:	4c 89 54 24 60       	mov    %r10,0x60(%rsp)
  4007ff:	c5 7d 6f ac 24 60 01 	vmovdqa 0x160(%rsp),%ymm13
  400806:	00 00 
  400808:	c5 7d 6f a4 24 80 01 	vmovdqa 0x180(%rsp),%ymm12
  40080f:	00 00 
  400811:	44 89 84 24 a4 0b 00 	mov    %r8d,0xba4(%rsp)
  400818:	00 
  400819:	c5 7d 6f 9c 24 a0 01 	vmovdqa 0x1a0(%rsp),%ymm11
  400820:	00 00 
  400822:	c5 7d 6f 94 24 c0 01 	vmovdqa 0x1c0(%rsp),%ymm10
  400829:	00 00 
  40082b:	44 89 9c 24 b0 0b 00 	mov    %r11d,0xbb0(%rsp)
  400832:	00 
  400833:	c5 7d 6f 8c 24 e0 01 	vmovdqa 0x1e0(%rsp),%ymm9
  40083a:	00 00 
  40083c:	48 8b b4 24 a8 00 00 	mov    0xa8(%rsp),%rsi
  400843:	00 
  400844:	c7 84 24 b4 0b 00 00 	movl   $0x3fa00000,0xbb4(%rsp)
  40084b:	00 00 a0 3f 
  40084f:	c5 7d 6f 84 24 00 02 	vmovdqa 0x200(%rsp),%ymm8
  400856:	00 00 
  400858:	c5 7d 7f bc 24 20 03 	vmovdqa %ymm15,0x320(%rsp)
  40085f:	00 00 
  400861:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  400864:	b9 98 00 00 00       	mov    $0x98,%ecx
  400869:	48 8d b4 24 20 07 00 	lea    0x720(%rsp),%rsi
  400870:	00 
  400871:	c5 7d 7f b4 24 40 03 	vmovdqa %ymm14,0x340(%rsp)
  400878:	00 00 
  40087a:	c5 7d 7f ac 24 60 03 	vmovdqa %ymm13,0x360(%rsp)
  400881:	00 00 
  400883:	48 8b bc 24 98 00 00 	mov    0x98(%rsp),%rdi
  40088a:	00 
  40088b:	c5 7d 7f a4 24 80 03 	vmovdqa %ymm12,0x380(%rsp)
  400892:	00 00 
  400894:	c5 7d 7f 9c 24 a0 03 	vmovdqa %ymm11,0x3a0(%rsp)
  40089b:	00 00 
  40089d:	c5 7d 7f 94 24 c0 03 	vmovdqa %ymm10,0x3c0(%rsp)
  4008a4:	00 00 
  4008a6:	c5 7d 7f 8c 24 e0 03 	vmovdqa %ymm9,0x3e0(%rsp)
  4008ad:	00 00 
  4008af:	48 89 b4 24 a8 00 00 	mov    %rsi,0xa8(%rsp)
  4008b6:	00 
  4008b7:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  4008ba:	c5 7d 7f 84 24 00 04 	vmovdqa %ymm8,0x400(%rsp)
  4008c1:	00 00 
  4008c3:	c5 fd 6f 9c 24 c0 02 	vmovdqa 0x2c0(%rsp),%ymm3
  4008ca:	00 00 
  4008cc:	c5 fd 6f a4 24 e0 02 	vmovdqa 0x2e0(%rsp),%ymm4
  4008d3:	00 00 
  4008d5:	c5 fd 6f bc 24 20 02 	vmovdqa 0x220(%rsp),%ymm7
  4008dc:	00 00 
  4008de:	c5 fd 6f b4 24 40 02 	vmovdqa 0x240(%rsp),%ymm6
  4008e5:	00 00 
  4008e7:	c5 7d 7f bc 24 20 05 	vmovdqa %ymm15,0x520(%rsp)
  4008ee:	00 00 
  4008f0:	c5 fd 6f ac 24 60 02 	vmovdqa 0x260(%rsp),%ymm5
  4008f7:	00 00 
  4008f9:	c5 fd 6f 94 24 80 02 	vmovdqa 0x280(%rsp),%ymm2
  400900:	00 00 
  400902:	c5 fd 7f 9c 24 c0 04 	vmovdqa %ymm3,0x4c0(%rsp)
  400909:	00 00 
  40090b:	c5 fd 6f 8c 24 a0 02 	vmovdqa 0x2a0(%rsp),%ymm1
  400912:	00 00 
  400914:	c5 fd 6f 84 24 00 03 	vmovdqa 0x300(%rsp),%ymm0
  40091b:	00 00 
  40091d:	c5 fd 7f a4 24 e0 04 	vmovdqa %ymm4,0x4e0(%rsp)
  400924:	00 00 
  400926:	c5 fd 7f 9c 24 c0 06 	vmovdqa %ymm3,0x6c0(%rsp)
  40092d:	00 00 
  40092f:	c5 fd 7f a4 24 e0 06 	vmovdqa %ymm4,0x6e0(%rsp)
  400936:	00 00 
  400938:	c5 fd 7f bc 24 20 04 	vmovdqa %ymm7,0x420(%rsp)
  40093f:	00 00 
  400941:	c5 fd 7f b4 24 40 04 	vmovdqa %ymm6,0x440(%rsp)
  400948:	00 00 
  40094a:	c5 fd 7f ac 24 60 04 	vmovdqa %ymm5,0x460(%rsp)
  400951:	00 00 
  400953:	c5 fd 7f 94 24 80 04 	vmovdqa %ymm2,0x480(%rsp)
  40095a:	00 00 
  40095c:	c5 fd 7f 8c 24 a0 04 	vmovdqa %ymm1,0x4a0(%rsp)
  400963:	00 00 
  400965:	c5 fd 7f 84 24 00 05 	vmovdqa %ymm0,0x500(%rsp)
  40096c:	00 00 
  40096e:	c5 7d 7f b4 24 40 05 	vmovdqa %ymm14,0x540(%rsp)
  400975:	00 00 
  400977:	c5 7d 7f ac 24 60 05 	vmovdqa %ymm13,0x560(%rsp)
  40097e:	00 00 
  400980:	c5 7d 7f a4 24 80 05 	vmovdqa %ymm12,0x580(%rsp)
  400987:	00 00 
  400989:	c5 7d 7f 9c 24 a0 05 	vmovdqa %ymm11,0x5a0(%rsp)
  400990:	00 00 
  400992:	c5 7d 7f 94 24 c0 05 	vmovdqa %ymm10,0x5c0(%rsp)
  400999:	00 00 
  40099b:	c5 7d 7f 8c 24 e0 05 	vmovdqa %ymm9,0x5e0(%rsp)
  4009a2:	00 00 
  4009a4:	c5 7d 7f 84 24 00 06 	vmovdqa %ymm8,0x600(%rsp)
  4009ab:	00 00 
  4009ad:	c5 fd 7f bc 24 20 06 	vmovdqa %ymm7,0x620(%rsp)
  4009b4:	00 00 
  4009b6:	c5 fd 7f b4 24 40 06 	vmovdqa %ymm6,0x640(%rsp)
  4009bd:	00 00 
  4009bf:	c5 fd 7f ac 24 60 06 	vmovdqa %ymm5,0x660(%rsp)
  4009c6:	00 00 
  4009c8:	c5 fd 7f 94 24 80 06 	vmovdqa %ymm2,0x680(%rsp)
  4009cf:	00 00 
  4009d1:	c5 fd 7f 8c 24 a0 06 	vmovdqa %ymm1,0x6a0(%rsp)
  4009d8:	00 00 
  4009da:	c5 fd 7f 84 24 00 07 	vmovdqa %ymm0,0x700(%rsp)
  4009e1:	00 00 
  4009e3:	48 89 05 66 36 00 00 	mov    %rax,0x3666(%rip)        # 404050 <g_ee_main_mem>
  4009ea:	48 8d 84 24 e0 0b 00 	lea    0xbe0(%rsp),%rax
  4009f1:	00 
  4009f2:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  4009f9:	00 
  4009fa:	48 89 c7             	mov    %rax,%rdi
  4009fd:	c5 f8 77             	vzeroupper
  400a00:	e8 7b 0d 00 00       	call   401780 <before(Mips2C::ExecutionContext*)>
  400a05:	88 44 24 70          	mov    %al,0x70(%rsp)
  400a09:	48 8d 84 24 20 05 00 	lea    0x520(%rsp),%rax
  400a10:	00 
  400a11:	48 89 05 38 36 00 00 	mov    %rax,0x3638(%rip)        # 404050 <g_ee_main_mem>
  400a18:	48 8d 84 24 a0 10 00 	lea    0x10a0(%rsp),%rax
  400a1f:	00 
  400a20:	48 89 c7             	mov    %rax,%rdi
  400a23:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
  400a2a:	00 
  400a2b:	e8 40 10 00 00       	call   401a70 <after(Mips2C::ExecutionContext*)>
  400a30:	0f b6 54 24 70       	movzbl 0x70(%rsp),%edx
  400a35:	4c 8b 54 24 60       	mov    0x60(%rsp),%r10
  400a3a:	c5 f9 6f 25 4e 1b 00 	vmovdqa 0x1b4e(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  400a41:	00 
  400a42:	c5 f9 6f 1d 56 1b 00 	vmovdqa 0x1b56(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  400a49:	00 
  400a4a:	84 d2                	test   %dl,%dl
  400a4c:	0f 84 80 07 00 00    	je     4011d2 <main+0xe12>
  400a52:	83 84 24 88 00 00 00 	addl   $0x1,0x88(%rsp)
  400a59:	01 
  400a5a:	38 c2                	cmp    %al,%dl
  400a5c:	0f 84 7d 07 00 00    	je     4011df <main+0xe1f>
  400a62:	83 bc 24 8c 00 00 00 	cmpl   $0xb,0x8c(%rsp)
  400a69:	0b 
  400a6a:	0f 86 f0 07 00 00    	jbe    401260 <main+0xea0>
  400a70:	83 84 24 8c 00 00 00 	addl   $0x1,0x8c(%rsp)
  400a77:	01 
  400a78:	48 83 84 24 a0 00 00 	addq   $0x4,0xa0(%rsp)
  400a7f:	00 04 
  400a81:	48 8d b4 24 d8 00 00 	lea    0xd8(%rsp),%rsi
  400a88:	00 
  400a89:	48 39 b4 24 a0 00 00 	cmp    %rsi,0xa0(%rsp)
  400a90:	00 
  400a91:	0f 85 08 fb ff ff    	jne    40059f <main+0x1df>
  400a97:	45 89 eb             	mov    %r13d,%r11d
  400a9a:	4c 8b 2c 24          	mov    (%rsp),%r13
  400a9e:	44 8b 74 24 08       	mov    0x8(%rsp),%r14d
  400aa3:	49 83 ed 01          	sub    $0x1,%r13
  400aa7:	0f 85 c7 fa ff ff    	jne    400574 <main+0x1b4>
  400aad:	4d 89 d5             	mov    %r10,%r13
  400ab0:	41 83 fe 68          	cmp    $0x68,%r14d
  400ab4:	0f 85 e6 f9 ff ff    	jne    4004a0 <main+0xe0>
  400aba:	48 8d 84 24 a0 09 00 	lea    0x9a0(%rsp),%rax
  400ac1:	00 
  400ac2:	4c 89 94 24 80 00 00 	mov    %r10,0x80(%rsp)
  400ac9:	00 
  400aca:	4c 8d ac 24 a0 0b 00 	lea    0xba0(%rsp),%r13
  400ad1:	00 
  400ad2:	48 89 44 24 18       	mov    %rax,0x18(%rsp)
  400ad7:	b8 b9 79 37 9e       	mov    $0x9e3779b9,%eax
  400adc:	c5 f9 6e f0          	vmovd  %eax,%xmm6
  400ae0:	b8 01 f8 3f 00       	mov    $0x3ff801,%eax
  400ae5:	c5 f9 6e e0          	vmovd  %eax,%xmm4
  400ae9:	c5 79 70 c6 00       	vpshufd $0x0,%xmm6,%xmm8
  400aee:	c5 c9 76 f6          	vpcmpeqd %xmm6,%xmm6,%xmm6
  400af2:	c5 f9 70 dc 00       	vpshufd $0x0,%xmm4,%xmm3
  400af7:	c5 c1 72 d6 1f       	vpsrld $0x1f,%xmm6,%xmm7
  400afc:	c5 f9 7f 9c 24 b0 00 	vmovdqa %xmm3,0xb0(%rsp)
  400b03:	00 00 
  400b05:	44 89 f1             	mov    %r14d,%ecx
  400b08:	44 89 f2             	mov    %r14d,%edx
  400b0b:	44 89 f0             	mov    %r14d,%eax
  400b0e:	44 89 74 24 38       	mov    %r14d,0x38(%rsp)
  400b13:	c1 e2 05             	shl    $0x5,%edx
  400b16:	35 b9 79 37 9e       	xor    $0x9e3779b9,%eax
  400b1b:	c5 c8 57 f6          	vxorps %xmm6,%xmm6,%xmm6
  400b1f:	4d 89 ec             	mov    %r13,%r12
  400b22:	48 69 f1 25 49 92 24 	imul   $0x24924925,%rcx,%rsi
  400b29:	89 d7                	mov    %edx,%edi
  400b2b:	44 89 f2             	mov    %r14d,%edx
  400b2e:	89 44 24 58          	mov    %eax,0x58(%rsp)
  400b32:	48 69 c9 39 8e e3 38 	imul   $0x38e38e39,%rcx,%rcx
  400b39:	44 89 f0             	mov    %r14d,%eax
  400b3c:	44 29 f7             	sub    %r14d,%edi
  400b3f:	41 bf 06 00 00 00    	mov    $0x6,%r15d
  400b45:	48 c1 ee 20          	shr    $0x20,%rsi
  400b49:	29 f2                	sub    %esi,%edx
  400b4b:	48 c1 e9 21          	shr    $0x21,%rcx
  400b4f:	d1 ea                	shr    $1,%edx
  400b51:	01 f2                	add    %esi,%edx
  400b53:	c1 ea 02             	shr    $0x2,%edx
  400b56:	8d 34 d5 00 00 00 00 	lea    0x0(,%rdx,8),%esi
  400b5d:	29 d6                	sub    %edx,%esi
  400b5f:	44 89 f2             	mov    %r14d,%edx
  400b62:	29 f2                	sub    %esi,%edx
  400b64:	8d 34 c9             	lea    (%rcx,%rcx,8),%esi
  400b67:	44 89 f1             	mov    %r14d,%ecx
  400b6a:	41 83 c6 01          	add    $0x1,%r14d
  400b6e:	29 f1                	sub    %esi,%ecx
  400b70:	89 c6                	mov    %eax,%esi
  400b72:	83 e6 03             	and    $0x3,%esi
  400b75:	c5 ca 2a c6          	vcvtsi2ss %esi,%xmm6,%xmm0
  400b79:	c5 fa 59 1d 03 17 00 	vmulss 0x1703(%rip),%xmm0,%xmm3        # 402284 <_IO_stdin_used+0x4>
  400b80:	00 
  400b81:	c5 ca 2a c2          	vcvtsi2ss %edx,%xmm6,%xmm0
  400b85:	c5 fa 59 25 fb 16 00 	vmulss 0x16fb(%rip),%xmm0,%xmm4        # 402288 <_IO_stdin_used+0x8>
  400b8c:	00 
  400b8d:	c5 ca 2a c1          	vcvtsi2ss %ecx,%xmm6,%xmm0
  400b91:	c5 fa 59 35 17 1a 00 	vmulss 0x1a17(%rip),%xmm0,%xmm6        # 4025b0 <__dso_handle+0x320>
  400b98:	00 
  400b99:	c5 fa 11 5c 24 50    	vmovss %xmm3,0x50(%rsp)
  400b9f:	c5 fa 11 64 24 40    	vmovss %xmm4,0x40(%rsp)
  400ba5:	c5 f9 6e e0          	vmovd  %eax,%xmm4
  400ba9:	c5 fa 11 74 24 3c    	vmovss %xmm6,0x3c(%rsp)
  400baf:	c5 f9 70 dc 00       	vpshufd $0x0,%xmm4,%xmm3
  400bb4:	c5 f9 6e f7          	vmovd  %edi,%xmm6
  400bb8:	c5 f9 7f 5c 24 20    	vmovdqa %xmm3,0x20(%rsp)
  400bbe:	c5 f9 70 f6 00       	vpshufd $0x0,%xmm6,%xmm6
  400bc3:	4c 89 f8             	mov    %r15,%rax
  400bc6:	44 89 74 24 14       	mov    %r14d,0x14(%rsp)
  400bcb:	4d 89 e5             	mov    %r12,%r13
  400bce:	48 f7 d8             	neg    %rax
  400bd1:	4c 89 7c 24 08       	mov    %r15,0x8(%rsp)
  400bd6:	48 c1 e0 03          	shl    $0x3,%rax
  400bda:	48 89 44 24 30       	mov    %rax,0x30(%rsp)
  400bdf:	48 8d 84 24 c0 00 00 	lea    0xc0(%rsp),%rax
  400be6:	00 
  400be7:	48 89 84 24 a0 00 00 	mov    %rax,0xa0(%rsp)
  400bee:	00 
  400bef:	48 8b 84 24 a0 00 00 	mov    0xa0(%rsp),%rax
  400bf6:	00 
  400bf7:	48 8b bc 24 a8 00 00 	mov    0xa8(%rsp),%rdi
  400bfe:	00 
  400bff:	b9 98 00 00 00       	mov    $0x98,%ecx
  400c04:	44 8b 38             	mov    (%rax),%r15d
  400c07:	31 c0                	xor    %eax,%eax
  400c09:	f3 48 ab             	rep stos %rax,(%rdi)
  400c0c:	48 8b 4c 24 18       	mov    0x18(%rsp),%rcx
  400c11:	8b 44 24 58          	mov    0x58(%rsp),%eax
  400c15:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  400c1c:	00 00 00 00 
  400c20:	89 c2                	mov    %eax,%edx
  400c22:	48 83 c1 10          	add    $0x10,%rcx
  400c26:	c1 e2 0d             	shl    $0xd,%edx
  400c29:	31 d0                	xor    %edx,%eax
  400c2b:	89 c2                	mov    %eax,%edx
  400c2d:	c1 ea 11             	shr    $0x11,%edx
  400c30:	31 c2                	xor    %eax,%edx
  400c32:	89 d0                	mov    %edx,%eax
  400c34:	c1 e0 05             	shl    $0x5,%eax
  400c37:	31 d0                	xor    %edx,%eax
  400c39:	89 c6                	mov    %eax,%esi
  400c3b:	89 41 f0             	mov    %eax,-0x10(%rcx)
  400c3e:	c1 e6 0d             	shl    $0xd,%esi
  400c41:	31 c6                	xor    %eax,%esi
  400c43:	89 f2                	mov    %esi,%edx
  400c45:	c1 ea 11             	shr    $0x11,%edx
  400c48:	31 f2                	xor    %esi,%edx
  400c4a:	89 d0                	mov    %edx,%eax
  400c4c:	c1 e0 05             	shl    $0x5,%eax
  400c4f:	31 d0                	xor    %edx,%eax
  400c51:	89 c2                	mov    %eax,%edx
  400c53:	89 41 f4             	mov    %eax,-0xc(%rcx)
  400c56:	c1 e2 0d             	shl    $0xd,%edx
  400c59:	31 d0                	xor    %edx,%eax
  400c5b:	89 c2                	mov    %eax,%edx
  400c5d:	c1 ea 11             	shr    $0x11,%edx
  400c60:	31 c2                	xor    %eax,%edx
  400c62:	89 d0                	mov    %edx,%eax
  400c64:	c1 e0 05             	shl    $0x5,%eax
  400c67:	31 d0                	xor    %edx,%eax
  400c69:	89 c2                	mov    %eax,%edx
  400c6b:	89 41 f8             	mov    %eax,-0x8(%rcx)
  400c6e:	c1 e2 0d             	shl    $0xd,%edx
  400c71:	31 d0                	xor    %edx,%eax
  400c73:	89 c2                	mov    %eax,%edx
  400c75:	c1 ea 11             	shr    $0x11,%edx
  400c78:	31 c2                	xor    %eax,%edx
  400c7a:	89 d0                	mov    %edx,%eax
  400c7c:	c1 e0 05             	shl    $0x5,%eax
  400c7f:	31 d0                	xor    %edx,%eax
  400c81:	89 41 fc             	mov    %eax,-0x4(%rcx)
  400c84:	49 39 cd             	cmp    %rcx,%r13
  400c87:	75 97                	jne    400c20 <main+0x860>
  400c89:	89 c2                	mov    %eax,%edx
  400c8b:	c5 f9 6f 5c 24 20    	vmovdqa 0x20(%rsp),%xmm3
  400c91:	c5 e1 fe 15 e7 18 00 	vpaddd 0x18e7(%rip),%xmm3,%xmm2        # 402580 <__dso_handle+0x2f0>
  400c98:	00 
  400c99:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  400c9d:	c1 e2 0d             	shl    $0xd,%edx
  400ca0:	31 c2                	xor    %eax,%edx
  400ca2:	89 d0                	mov    %edx,%eax
  400ca4:	c1 e8 11             	shr    $0x11,%eax
  400ca7:	31 d0                	xor    %edx,%eax
  400ca9:	41 89 c2             	mov    %eax,%r10d
  400cac:	41 c1 e2 05          	shl    $0x5,%r10d
  400cb0:	41 31 c2             	xor    %eax,%r10d
  400cb3:	44 89 d2             	mov    %r10d,%edx
  400cb6:	c1 e2 0d             	shl    $0xd,%edx
  400cb9:	44 31 d2             	xor    %r10d,%edx
  400cbc:	89 d0                	mov    %edx,%eax
  400cbe:	c1 e8 11             	shr    $0x11,%eax
  400cc1:	31 d0                	xor    %edx,%eax
  400cc3:	41 89 c0             	mov    %eax,%r8d
  400cc6:	41 c1 e0 05          	shl    $0x5,%r8d
  400cca:	41 31 c0             	xor    %eax,%r8d
  400ccd:	44 89 c2             	mov    %r8d,%edx
  400cd0:	c1 e2 0d             	shl    $0xd,%edx
  400cd3:	44 31 c2             	xor    %r8d,%edx
  400cd6:	89 d0                	mov    %edx,%eax
  400cd8:	c1 e8 11             	shr    $0x11,%eax
  400cdb:	31 d0                	xor    %edx,%eax
  400cdd:	89 c6                	mov    %eax,%esi
  400cdf:	c1 e6 05             	shl    $0x5,%esi
  400ce2:	31 c6                	xor    %eax,%esi
  400ce4:	89 f2                	mov    %esi,%edx
  400ce6:	c1 e2 0d             	shl    $0xd,%edx
  400ce9:	31 f2                	xor    %esi,%edx
  400ceb:	89 d0                	mov    %edx,%eax
  400ced:	c1 e8 11             	shr    $0x11,%eax
  400cf0:	31 d0                	xor    %edx,%eax
  400cf2:	89 c2                	mov    %eax,%edx
  400cf4:	c1 e2 05             	shl    $0x5,%edx
  400cf7:	31 c2                	xor    %eax,%edx
  400cf9:	89 d1                	mov    %edx,%ecx
  400cfb:	c1 e1 0d             	shl    $0xd,%ecx
  400cfe:	31 d1                	xor    %edx,%ecx
  400d00:	89 c8                	mov    %ecx,%eax
  400d02:	c1 e8 11             	shr    $0x11,%eax
  400d05:	31 c8                	xor    %ecx,%eax
  400d07:	41 89 c3             	mov    %eax,%r11d
  400d0a:	41 c1 e3 05          	shl    $0x5,%r11d
  400d0e:	41 31 c3             	xor    %eax,%r11d
  400d11:	48 8d 84 24 20 07 00 	lea    0x720(%rsp),%rax
  400d18:	00 
  400d19:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  400d20:	c5 f9 72 f1 02       	vpslld $0x2,%xmm1,%xmm0
  400d25:	48 83 c0 10          	add    $0x10,%rax
  400d29:	c5 f1 fe cf          	vpaddd %xmm7,%xmm1,%xmm1
  400d2d:	c5 f9 fe c2          	vpaddd %xmm2,%xmm0,%xmm0
  400d31:	c4 c2 79 40 c0       	vpmulld %xmm8,%xmm0,%xmm0
  400d36:	c5 f9 7f 40 f0       	vmovdqa %xmm0,-0x10(%rax)
  400d3b:	48 39 d8             	cmp    %rbx,%rax
  400d3e:	75 e0                	jne    400d20 <main+0x960>
  400d40:	48 8b 44 24 30       	mov    0x30(%rsp),%rax
  400d45:	48 8b bc 24 80 00 00 	mov    0x80(%rsp),%rdi
  400d4c:	00 
  400d4d:	c5 d9 76 e4          	vpcmpeqd %xmm4,%xmm4,%xmm4
  400d51:	b9 40 00 00 00       	mov    $0x40,%ecx
  400d56:	c5 f9 6f 15 e2 17 00 	vmovdqa 0x17e2(%rip),%xmm2        # 402540 <__dso_handle+0x2b0>
  400d5d:	00 
  400d5e:	c5 d9 72 f4 0a       	vpslld $0xa,%xmm4,%xmm4
  400d63:	44 8b a4 04 10 01 00 	mov    0x110(%rsp,%rax,1),%r12d
  400d6a:	00 
  400d6b:	44 8b b4 04 14 01 00 	mov    0x114(%rsp,%rax,1),%r14d
  400d72:	00 
  400d73:	31 c0                	xor    %eax,%eax
  400d75:	f3 48 ab             	rep stos %rax,(%rdi)
  400d78:	48 8d 84 24 20 01 00 	lea    0x120(%rsp),%rax
  400d7f:	00 
  400d80:	bf 10 00 00 00       	mov    $0x10,%edi
  400d85:	44 89 a4 24 60 08 00 	mov    %r12d,0x860(%rsp)
  400d8c:	00 
  400d8d:	c5 f9 6e df          	vmovd  %edi,%xmm3
  400d91:	44 89 b4 24 70 08 00 	mov    %r14d,0x870(%rsp)
  400d98:	00 
  400d99:	c5 f9 70 db 00       	vpshufd $0x0,%xmm3,%xmm3
  400d9e:	48 89 84 24 80 00 00 	mov    %rax,0x80(%rsp)
  400da5:	00 
  400da6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  400dad:	00 00 00 
  400db0:	c5 f9 72 f2 04       	vpslld $0x4,%xmm2,%xmm0
  400db5:	48 83 c0 10          	add    $0x10,%rax
  400db9:	48 8d bc 24 20 03 00 	lea    0x320(%rsp),%rdi
  400dc0:	00 
  400dc1:	c5 f9 fe c2          	vpaddd %xmm2,%xmm0,%xmm0
  400dc5:	c5 e9 fe d3          	vpaddd %xmm3,%xmm2,%xmm2
  400dc9:	c5 f9 fe c6          	vpaddd %xmm6,%xmm0,%xmm0
  400dcd:	c5 f9 f4 ac 24 b0 00 	vpmuludq 0xb0(%rsp),%xmm0,%xmm5
  400dd4:	00 00 
  400dd6:	c5 f9 70 ed f5       	vpshufd $0xf5,%xmm5,%xmm5
  400ddb:	c5 f1 73 d0 20       	vpsrlq $0x20,%xmm0,%xmm1
  400de0:	c5 f1 f4 8c 24 b0 00 	vpmuludq 0xb0(%rsp),%xmm1,%xmm1
  400de7:	00 00 
  400de9:	c4 e3 71 0e cd 33    	vpblendw $0x33,%xmm5,%xmm1,%xmm1
  400def:	c5 f1 72 d1 01       	vpsrld $0x1,%xmm1,%xmm1
  400df4:	c5 d1 72 f1 0b       	vpslld $0xb,%xmm1,%xmm5
  400df9:	c5 d1 fe c9          	vpaddd %xmm1,%xmm5,%xmm1
  400dfd:	c5 f9 fa c1          	vpsubd %xmm1,%xmm0,%xmm0
  400e01:	c5 f9 fe c4          	vpaddd %xmm4,%xmm0,%xmm0
  400e05:	c5 f8 5b c0          	vcvtdq2ps %xmm0,%xmm0
  400e09:	c5 f8 59 05 9f 17 00 	vmulps 0x179f(%rip),%xmm0,%xmm0        # 4025b0 <__dso_handle+0x320>
  400e10:	00 
  400e11:	c5 f8 29 40 f0       	vmovaps %xmm0,-0x10(%rax)
  400e16:	48 39 f8             	cmp    %rdi,%rax
  400e19:	75 95                	jne    400db0 <main+0x9f0>
  400e1b:	c5 f9 7f 74 24 60    	vmovdqa %xmm6,0x60(%rsp)
  400e21:	44 89 f0             	mov    %r14d,%eax
  400e24:	c5 fa 10 74 24 50    	vmovss 0x50(%rsp),%xmm6
  400e2a:	48 8b bc 24 90 00 00 	mov    0x90(%rsp),%rdi
  400e31:	00 
  400e32:	44 89 bc 04 80 01 00 	mov    %r15d,0x180(%rsp,%rax,1)
  400e39:	00 
  400e3a:	b9 98 00 00 00       	mov    $0x98,%ecx
  400e3f:	c5 7d 6f bc 24 20 01 	vmovdqa 0x120(%rsp),%ymm15
  400e46:	00 00 
  400e48:	48 8d 84 24 20 03 00 	lea    0x320(%rsp),%rax
  400e4f:	00 
  400e50:	c5 7d 6f b4 24 40 01 	vmovdqa 0x140(%rsp),%ymm14
  400e57:	00 00 
  400e59:	89 94 24 ac 0b 00 00 	mov    %edx,0xbac(%rsp)
  400e60:	c5 7d 6f ac 24 60 01 	vmovdqa 0x160(%rsp),%ymm13
  400e67:	00 00 
  400e69:	89 b4 24 a8 0b 00 00 	mov    %esi,0xba8(%rsp)
  400e70:	44 89 94 24 a0 0b 00 	mov    %r10d,0xba0(%rsp)
  400e77:	00 
  400e78:	48 8b b4 24 a8 00 00 	mov    0xa8(%rsp),%rsi
  400e7f:	00 
  400e80:	c5 fa 11 b4 24 a4 0a 	vmovss %xmm6,0xaa4(%rsp)
  400e87:	00 00 
  400e89:	c5 fa 10 74 24 40    	vmovss 0x40(%rsp),%xmm6
  400e8f:	c5 7d 6f a4 24 80 01 	vmovdqa 0x180(%rsp),%ymm12
  400e96:	00 00 
  400e98:	c5 7d 6f 9c 24 a0 01 	vmovdqa 0x1a0(%rsp),%ymm11
  400e9f:	00 00 
  400ea1:	44 89 84 24 a4 0b 00 	mov    %r8d,0xba4(%rsp)
  400ea8:	00 
  400ea9:	c5 fa 11 b4 24 a8 0a 	vmovss %xmm6,0xaa8(%rsp)
  400eb0:	00 00 
  400eb2:	c5 fa 10 74 24 3c    	vmovss 0x3c(%rsp),%xmm6
  400eb8:	44 89 9c 24 b0 0b 00 	mov    %r11d,0xbb0(%rsp)
  400ebf:	00 
  400ec0:	c5 fa 11 b4 24 ac 0a 	vmovss %xmm6,0xaac(%rsp)
  400ec7:	00 00 
  400ec9:	c7 84 24 a0 0a 00 00 	movl   $0x0,0xaa0(%rsp)
  400ed0:	00 00 00 00 
  400ed4:	c7 84 24 b4 0b 00 00 	movl   $0x3fa00000,0xbb4(%rsp)
  400edb:	00 00 a0 3f 
  400edf:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  400ee2:	b9 98 00 00 00       	mov    $0x98,%ecx
  400ee7:	48 8d b4 24 20 07 00 	lea    0x720(%rsp),%rsi
  400eee:	00 
  400eef:	c5 7d 7f bc 24 20 03 	vmovdqa %ymm15,0x320(%rsp)
  400ef6:	00 00 
  400ef8:	48 89 b4 24 a8 00 00 	mov    %rsi,0xa8(%rsp)
  400eff:	00 
  400f00:	48 8b bc 24 98 00 00 	mov    0x98(%rsp),%rdi
  400f07:	00 
  400f08:	c5 7d 7f b4 24 40 03 	vmovdqa %ymm14,0x340(%rsp)
  400f0f:	00 00 
  400f11:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  400f14:	c5 7d 7f ac 24 60 03 	vmovdqa %ymm13,0x360(%rsp)
  400f1b:	00 00 
  400f1d:	c5 7d 7f a4 24 80 03 	vmovdqa %ymm12,0x380(%rsp)
  400f24:	00 00 
  400f26:	c5 7d 7f 9c 24 a0 03 	vmovdqa %ymm11,0x3a0(%rsp)
  400f2d:	00 00 
  400f2f:	c5 fd 6f b4 24 80 02 	vmovdqa 0x280(%rsp),%ymm6
  400f36:	00 00 
  400f38:	c5 7d 6f 94 24 c0 01 	vmovdqa 0x1c0(%rsp),%ymm10
  400f3f:	00 00 
  400f41:	c5 7d 6f 8c 24 e0 01 	vmovdqa 0x1e0(%rsp),%ymm9
  400f48:	00 00 
  400f4a:	c5 fd 6f ac 24 00 02 	vmovdqa 0x200(%rsp),%ymm5
  400f51:	00 00 
  400f53:	c5 7d 7f bc 24 20 05 	vmovdqa %ymm15,0x520(%rsp)
  400f5a:	00 00 
  400f5c:	c5 fd 7f b4 24 80 04 	vmovdqa %ymm6,0x480(%rsp)
  400f63:	00 00 
  400f65:	c5 fd 6f b4 24 a0 02 	vmovdqa 0x2a0(%rsp),%ymm6
  400f6c:	00 00 
  400f6e:	c5 fd 6f a4 24 20 02 	vmovdqa 0x220(%rsp),%ymm4
  400f75:	00 00 
  400f77:	c5 fd 6f 9c 24 40 02 	vmovdqa 0x240(%rsp),%ymm3
  400f7e:	00 00 
  400f80:	c5 fd 6f 8c 24 e0 02 	vmovdqa 0x2e0(%rsp),%ymm1
  400f87:	00 00 
  400f89:	c5 7d 7f 94 24 c0 03 	vmovdqa %ymm10,0x3c0(%rsp)
  400f90:	00 00 
  400f92:	c5 fd 6f 84 24 00 03 	vmovdqa 0x300(%rsp),%ymm0
  400f99:	00 00 
  400f9b:	c5 fd 6f 94 24 60 02 	vmovdqa 0x260(%rsp),%ymm2
  400fa2:	00 00 
  400fa4:	c5 fd 7f b4 24 a0 04 	vmovdqa %ymm6,0x4a0(%rsp)
  400fab:	00 00 
  400fad:	c5 fd 6f b4 24 c0 02 	vmovdqa 0x2c0(%rsp),%ymm6
  400fb4:	00 00 
  400fb6:	c5 7d 7f 8c 24 e0 03 	vmovdqa %ymm9,0x3e0(%rsp)
  400fbd:	00 00 
  400fbf:	c5 fd 7f ac 24 00 04 	vmovdqa %ymm5,0x400(%rsp)
  400fc6:	00 00 
  400fc8:	c5 fd 7f a4 24 20 04 	vmovdqa %ymm4,0x420(%rsp)
  400fcf:	00 00 
  400fd1:	c5 fd 7f 9c 24 40 04 	vmovdqa %ymm3,0x440(%rsp)
  400fd8:	00 00 
  400fda:	c5 fd 7f 94 24 60 04 	vmovdqa %ymm2,0x460(%rsp)
  400fe1:	00 00 
  400fe3:	c5 fd 7f 8c 24 e0 04 	vmovdqa %ymm1,0x4e0(%rsp)
  400fea:	00 00 
  400fec:	c5 fd 7f 84 24 00 05 	vmovdqa %ymm0,0x500(%rsp)
  400ff3:	00 00 
  400ff5:	c5 7d 7f b4 24 40 05 	vmovdqa %ymm14,0x540(%rsp)
  400ffc:	00 00 
  400ffe:	c5 7d 7f ac 24 60 05 	vmovdqa %ymm13,0x560(%rsp)
  401005:	00 00 
  401007:	c5 7d 7f a4 24 80 05 	vmovdqa %ymm12,0x580(%rsp)
  40100e:	00 00 
  401010:	c5 7d 7f 9c 24 a0 05 	vmovdqa %ymm11,0x5a0(%rsp)
  401017:	00 00 
  401019:	c5 7d 7f 94 24 c0 05 	vmovdqa %ymm10,0x5c0(%rsp)
  401020:	00 00 
  401022:	c5 7d 7f 8c 24 e0 05 	vmovdqa %ymm9,0x5e0(%rsp)
  401029:	00 00 
  40102b:	c5 fd 7f ac 24 00 06 	vmovdqa %ymm5,0x600(%rsp)
  401032:	00 00 
  401034:	c5 fd 7f a4 24 20 06 	vmovdqa %ymm4,0x620(%rsp)
  40103b:	00 00 
  40103d:	c5 fd 7f 9c 24 40 06 	vmovdqa %ymm3,0x640(%rsp)
  401044:	00 00 
  401046:	c5 fd 7f b4 24 c0 04 	vmovdqa %ymm6,0x4c0(%rsp)
  40104d:	00 00 
  40104f:	c5 fd 7f 94 24 60 06 	vmovdqa %ymm2,0x660(%rsp)
  401056:	00 00 
  401058:	c5 fd 6f b4 24 80 02 	vmovdqa 0x280(%rsp),%ymm6
  40105f:	00 00 
  401061:	48 89 05 e8 2f 00 00 	mov    %rax,0x2fe8(%rip)        # 404050 <g_ee_main_mem>
  401068:	48 8d 84 24 e0 0b 00 	lea    0xbe0(%rsp),%rax
  40106f:	00 
  401070:	c5 fd 7f b4 24 80 06 	vmovdqa %ymm6,0x680(%rsp)
  401077:	00 00 
  401079:	48 89 c7             	mov    %rax,%rdi
  40107c:	c5 fd 6f b4 24 a0 02 	vmovdqa 0x2a0(%rsp),%ymm6
  401083:	00 00 
  401085:	48 89 84 24 90 00 00 	mov    %rax,0x90(%rsp)
  40108c:	00 
  40108d:	c5 fd 7f b4 24 a0 06 	vmovdqa %ymm6,0x6a0(%rsp)
  401094:	00 00 
  401096:	c5 fd 6f b4 24 c0 02 	vmovdqa 0x2c0(%rsp),%ymm6
  40109d:	00 00 
  40109f:	c5 fd 7f 8c 24 e0 06 	vmovdqa %ymm1,0x6e0(%rsp)
  4010a6:	00 00 
  4010a8:	c5 fd 7f b4 24 c0 06 	vmovdqa %ymm6,0x6c0(%rsp)
  4010af:	00 00 
  4010b1:	c5 fd 7f 84 24 00 07 	vmovdqa %ymm0,0x700(%rsp)
  4010b8:	00 00 
  4010ba:	c5 f8 77             	vzeroupper
  4010bd:	e8 be 06 00 00       	call   401780 <before(Mips2C::ExecutionContext*)>
  4010c2:	88 44 24 70          	mov    %al,0x70(%rsp)
  4010c6:	48 8d 84 24 20 05 00 	lea    0x520(%rsp),%rax
  4010cd:	00 
  4010ce:	48 89 05 7b 2f 00 00 	mov    %rax,0x2f7b(%rip)        # 404050 <g_ee_main_mem>
  4010d5:	48 8d 84 24 a0 10 00 	lea    0x10a0(%rsp),%rax
  4010dc:	00 
  4010dd:	48 89 c7             	mov    %rax,%rdi
  4010e0:	48 89 84 24 98 00 00 	mov    %rax,0x98(%rsp)
  4010e7:	00 
  4010e8:	e8 83 09 00 00       	call   401a70 <after(Mips2C::ExecutionContext*)>
  4010ed:	0f b6 54 24 70       	movzbl 0x70(%rsp),%edx
  4010f2:	c5 f9 6f 74 24 60    	vmovdqa 0x60(%rsp),%xmm6
  4010f8:	c5 79 6f 05 90 14 00 	vmovdqa 0x1490(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  4010ff:	00 
  401100:	c5 f9 6f 3d 98 14 00 	vmovdqa 0x1498(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  401107:	00 
  401108:	84 d2                	test   %dl,%dl
  40110a:	0f 84 a0 03 00 00    	je     4014b0 <main+0x10f0>
  401110:	83 84 24 88 00 00 00 	addl   $0x1,0x88(%rsp)
  401117:	01 
  401118:	38 c2                	cmp    %al,%dl
  40111a:	0f 84 9d 03 00 00    	je     4014bd <main+0x10fd>
  401120:	83 bc 24 8c 00 00 00 	cmpl   $0xb,0x8c(%rsp)
  401127:	0b 
  401128:	0f 86 13 04 00 00    	jbe    401541 <main+0x1181>
  40112e:	83 84 24 8c 00 00 00 	addl   $0x1,0x8c(%rsp)
  401135:	01 
  401136:	48 83 84 24 a0 00 00 	addq   $0x4,0xa0(%rsp)
  40113d:	00 04 
  40113f:	48 8d bc 24 d8 00 00 	lea    0xd8(%rsp),%rdi
  401146:	00 
  401147:	48 39 bc 24 a0 00 00 	cmp    %rdi,0xa0(%rsp)
  40114e:	00 
  40114f:	0f 85 9a fa ff ff    	jne    400bef <main+0x82f>
  401155:	4c 8b 7c 24 08       	mov    0x8(%rsp),%r15
  40115a:	44 8b 74 24 14       	mov    0x14(%rsp),%r14d
  40115f:	4d 89 ec             	mov    %r13,%r12
  401162:	49 83 ef 01          	sub    $0x1,%r15
  401166:	0f 85 57 fa ff ff    	jne    400bc3 <main+0x803>
  40116c:	41 81 fe a8 00 00 00 	cmp    $0xa8,%r14d
  401173:	0f 85 8c f9 ff ff    	jne    400b05 <main+0x745>
  401179:	8b 4c 24 5c          	mov    0x5c(%rsp),%ecx
  40117d:	31 c0                	xor    %eax,%eax
  40117f:	ba 00 09 00 00       	mov    $0x900,%edx
  401184:	be a0 17 00 00       	mov    $0x17a0,%esi
  401189:	8b 9c 24 8c 00 00 00 	mov    0x8c(%rsp),%ebx
  401190:	44 8b 84 24 88 00 00 	mov    0x88(%rsp),%r8d
  401197:	00 
  401198:	bf e8 24 40 00       	mov    $0x4024e8,%edi
  40119d:	41 89 d9             	mov    %ebx,%r9d
  4011a0:	e8 cb f1 ff ff       	call   400370 <printf@plt>
  4011a5:	85 db                	test   %ebx,%ebx
  4011a7:	0f 84 c7 04 00 00    	je     401674 <main+0x12b4>
  4011ad:	be 98 22 40 00       	mov    $0x402298,%esi
  4011b2:	bf 9d 22 40 00       	mov    $0x40229d,%edi
  4011b7:	31 c0                	xor    %eax,%eax
  4011b9:	e8 b2 f1 ff ff       	call   400370 <printf@plt>
  4011be:	b8 01 00 00 00       	mov    $0x1,%eax
  4011c3:	48 8d 65 d8          	lea    -0x28(%rbp),%rsp
  4011c7:	5b                   	pop    %rbx
  4011c8:	41 5c                	pop    %r12
  4011ca:	41 5d                	pop    %r13
  4011cc:	41 5e                	pop    %r14
  4011ce:	41 5f                	pop    %r15
  4011d0:	5d                   	pop    %rbp
  4011d1:	c3                   	ret
  4011d2:	83 44 24 5c 01       	addl   $0x1,0x5c(%rsp)
  4011d7:	38 c2                	cmp    %al,%dl
  4011d9:	0f 85 83 f8 ff ff    	jne    400a62 <main+0x6a2>
  4011df:	48 8b b4 24 98 00 00 	mov    0x98(%rsp),%rsi
  4011e6:	00 
  4011e7:	ba c0 04 00 00       	mov    $0x4c0,%edx
  4011ec:	4c 89 54 24 70       	mov    %r10,0x70(%rsp)
  4011f1:	48 8b bc 24 90 00 00 	mov    0x90(%rsp),%rdi
  4011f8:	00 
  4011f9:	e8 82 f1 ff ff       	call   400380 <memcmp@plt>
  4011fe:	c5 f9 6f 25 8a 13 00 	vmovdqa 0x138a(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  401205:	00 
  401206:	4c 8b 54 24 70       	mov    0x70(%rsp),%r10
  40120b:	85 c0                	test   %eax,%eax
  40120d:	c5 f9 6f 1d 8b 13 00 	vmovdqa 0x138b(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  401214:	00 
  401215:	0f 85 47 f8 ff ff    	jne    400a62 <main+0x6a2>
  40121b:	ba 00 02 00 00       	mov    $0x200,%edx
  401220:	48 8d b4 24 20 05 00 	lea    0x520(%rsp),%rsi
  401227:	00 
  401228:	48 8d bc 24 20 03 00 	lea    0x320(%rsp),%rdi
  40122f:	00 
  401230:	e8 4b f1 ff ff       	call   400380 <memcmp@plt>
  401235:	c5 f9 6f 25 53 13 00 	vmovdqa 0x1353(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  40123c:	00 
  40123d:	4c 8b 54 24 70       	mov    0x70(%rsp),%r10
  401242:	85 c0                	test   %eax,%eax
  401244:	c5 f9 6f 1d 54 13 00 	vmovdqa 0x1354(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  40124b:	00 
  40124c:	0f 84 26 f8 ff ff    	je     400a78 <main+0x6b8>
  401252:	83 bc 24 8c 00 00 00 	cmpl   $0xb,0x8c(%rsp)
  401259:	0b 
  40125a:	0f 87 10 f8 ff ff    	ja     400a70 <main+0x6b0>
  401260:	8b b4 24 80 00 00 00 	mov    0x80(%rsp),%esi
  401267:	8b 54 24 58          	mov    0x58(%rsp),%edx
  40126b:	44 89 f1             	mov    %r14d,%ecx
  40126e:	31 c0                	xor    %eax,%eax
  401270:	44 8b 84 24 b0 00 00 	mov    0xb0(%rsp),%r8d
  401277:	00 
  401278:	bf a0 24 40 00       	mov    $0x4024a0,%edi
  40127d:	4c 89 54 24 60       	mov    %r10,0x60(%rsp)
  401282:	4c 8d b4 24 60 0e 00 	lea    0xe60(%rsp),%r14
  401289:	00 
  40128a:	e8 e1 f0 ff ff       	call   400370 <printf@plt>
  40128f:	c5 f9 6f 1d 09 13 00 	vmovdqa 0x1309(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  401296:	00 
  401297:	44 89 6c 24 70       	mov    %r13d,0x70(%rsp)
  40129c:	31 f6                	xor    %esi,%esi
  40129e:	c5 f9 6f 25 ea 12 00 	vmovdqa 0x12ea(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  4012a5:	00 
  4012a6:	4c 8d ac 24 20 13 00 	lea    0x1320(%rsp),%r13
  4012ad:	00 
  4012ae:	66 90                	xchg   %ax,%ax
  4012b0:	41 8b 0e             	mov    (%r14),%ecx
  4012b3:	45 8b 45 00          	mov    0x0(%r13),%r8d
  4012b7:	41 39 c8             	cmp    %ecx,%r8d
  4012ba:	74 2c                	je     4012e8 <main+0xf28>
  4012bc:	31 d2                	xor    %edx,%edx
  4012be:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  4012c3:	31 c0                	xor    %eax,%eax
  4012c5:	89 b4 24 b0 00 00 00 	mov    %esi,0xb0(%rsp)
  4012cc:	e8 9f f0 ff ff       	call   400370 <printf@plt>
  4012d1:	c5 f9 6f 1d c7 12 00 	vmovdqa 0x12c7(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  4012d8:	00 
  4012d9:	c5 f9 6f 25 af 12 00 	vmovdqa 0x12af(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  4012e0:	00 
  4012e1:	8b b4 24 b0 00 00 00 	mov    0xb0(%rsp),%esi
  4012e8:	41 8b 4e 04          	mov    0x4(%r14),%ecx
  4012ec:	45 8b 45 04          	mov    0x4(%r13),%r8d
  4012f0:	41 39 c8             	cmp    %ecx,%r8d
  4012f3:	74 2f                	je     401324 <main+0xf64>
  4012f5:	ba 01 00 00 00       	mov    $0x1,%edx
  4012fa:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  4012ff:	31 c0                	xor    %eax,%eax
  401301:	89 b4 24 b0 00 00 00 	mov    %esi,0xb0(%rsp)
  401308:	e8 63 f0 ff ff       	call   400370 <printf@plt>
  40130d:	c5 f9 6f 1d 8b 12 00 	vmovdqa 0x128b(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  401314:	00 
  401315:	c5 f9 6f 25 73 12 00 	vmovdqa 0x1273(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  40131c:	00 
  40131d:	8b b4 24 b0 00 00 00 	mov    0xb0(%rsp),%esi
  401324:	41 8b 4e 08          	mov    0x8(%r14),%ecx
  401328:	45 8b 45 08          	mov    0x8(%r13),%r8d
  40132c:	44 39 c1             	cmp    %r8d,%ecx
  40132f:	74 2f                	je     401360 <main+0xfa0>
  401331:	ba 02 00 00 00       	mov    $0x2,%edx
  401336:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  40133b:	31 c0                	xor    %eax,%eax
  40133d:	89 b4 24 b0 00 00 00 	mov    %esi,0xb0(%rsp)
  401344:	e8 27 f0 ff ff       	call   400370 <printf@plt>
  401349:	c5 f9 6f 1d 4f 12 00 	vmovdqa 0x124f(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  401350:	00 
  401351:	c5 f9 6f 25 37 12 00 	vmovdqa 0x1237(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  401358:	00 
  401359:	8b b4 24 b0 00 00 00 	mov    0xb0(%rsp),%esi
  401360:	41 8b 4e 0c          	mov    0xc(%r14),%ecx
  401364:	45 8b 45 0c          	mov    0xc(%r13),%r8d
  401368:	44 39 c1             	cmp    %r8d,%ecx
  40136b:	74 2f                	je     40139c <main+0xfdc>
  40136d:	ba 03 00 00 00       	mov    $0x3,%edx
  401372:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  401377:	31 c0                	xor    %eax,%eax
  401379:	89 b4 24 b0 00 00 00 	mov    %esi,0xb0(%rsp)
  401380:	e8 eb ef ff ff       	call   400370 <printf@plt>
  401385:	c5 f9 6f 1d 13 12 00 	vmovdqa 0x1213(%rip),%xmm3        # 4025a0 <__dso_handle+0x310>
  40138c:	00 
  40138d:	c5 f9 6f 25 fb 11 00 	vmovdqa 0x11fb(%rip),%xmm4        # 402590 <__dso_handle+0x300>
  401394:	00 
  401395:	8b b4 24 b0 00 00 00 	mov    0xb0(%rsp),%esi
  40139c:	83 c6 01             	add    $0x1,%esi
  40139f:	49 83 c6 10          	add    $0x10,%r14
  4013a3:	49 83 c5 10          	add    $0x10,%r13
  4013a7:	83 fe 20             	cmp    $0x20,%esi
  4013aa:	0f 85 00 ff ff ff    	jne    4012b0 <main+0xef0>
  4013b0:	44 8b 6c 24 70       	mov    0x70(%rsp),%r13d
  4013b5:	4c 8b 54 24 60       	mov    0x60(%rsp),%r10
  4013ba:	e9 b1 f6 ff ff       	jmp    400a70 <main+0x6b0>
  4013bf:	8b 94 24 80 00 00 00 	mov    0x80(%rsp),%edx
  4013c6:	48 8d bc 24 a0 09 00 	lea    0x9a0(%rsp),%rdi
  4013cd:	00 
  4013ce:	66 90                	xchg   %ax,%ax
  4013d0:	89 d0                	mov    %edx,%eax
  4013d2:	41 8d 4c 15 00       	lea    0x0(%r13,%rdx,1),%ecx
  4013d7:	48 83 c7 10          	add    $0x10,%rdi
  4013db:	49 0f af c4          	imul   %r12,%rax
  4013df:	45 8d 44 0d 00       	lea    0x0(%r13,%rcx,1),%r8d
  4013e4:	43 8d 74 05 00       	lea    0x0(%r13,%r8,1),%esi
  4013e9:	41 89 f1             	mov    %esi,%r9d
  4013ec:	48 c1 e8 24          	shr    $0x24,%rax
  4013f0:	8d 04 80             	lea    (%rax,%rax,4),%eax
  4013f3:	c1 e0 02             	shl    $0x2,%eax
  4013f6:	29 c2                	sub    %eax,%edx
  4013f8:	89 c8                	mov    %ecx,%eax
  4013fa:	c5 f9 6e 84 94 a0 10 	vmovd  0x10a0(%rsp,%rdx,4),%xmm0
  401401:	00 00 
  401403:	49 0f af c4          	imul   %r12,%rax
  401407:	41 8d 54 35 00       	lea    0x0(%r13,%rsi,1),%edx
  40140c:	48 c1 e8 24          	shr    $0x24,%rax
  401410:	8d 04 80             	lea    (%rax,%rax,4),%eax
  401413:	c1 e0 02             	shl    $0x2,%eax
  401416:	29 c1                	sub    %eax,%ecx
  401418:	44 89 c0             	mov    %r8d,%eax
  40141b:	c4 e3 79 22 84 8c a0 	vpinsrd $0x1,0x10a0(%rsp,%rcx,4),%xmm0,%xmm0
  401422:	10 00 00 01 
  401426:	49 0f af c4          	imul   %r12,%rax
  40142a:	48 c1 e8 24          	shr    $0x24,%rax
  40142e:	8d 04 80             	lea    (%rax,%rax,4),%eax
  401431:	c1 e0 02             	shl    $0x2,%eax
  401434:	41 29 c0             	sub    %eax,%r8d
  401437:	89 f0                	mov    %esi,%eax
  401439:	c4 a1 79 6e 8c 84 a0 	vmovd  0x10a0(%rsp,%r8,4),%xmm1
  401440:	10 00 00 
  401443:	49 0f af c4          	imul   %r12,%rax
  401447:	48 c1 e8 24          	shr    $0x24,%rax
  40144b:	8d 04 80             	lea    (%rax,%rax,4),%eax
  40144e:	c1 e0 02             	shl    $0x2,%eax
  401451:	41 29 c1             	sub    %eax,%r9d
  401454:	c4 a3 71 22 8c 8c a0 	vpinsrd $0x1,0x10a0(%rsp,%r9,4),%xmm1,%xmm1
  40145b:	10 00 00 01 
  40145f:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
  401463:	c5 f9 7f 47 f0       	vmovdqa %xmm0,-0x10(%rdi)
  401468:	49 39 ff             	cmp    %rdi,%r15
  40146b:	0f 85 5f ff ff ff    	jne    4013d0 <main+0x1010>
  401471:	8b 44 24 30          	mov    0x30(%rsp),%eax
  401475:	44 8b 8c 84 a0 10 00 	mov    0x10a0(%rsp,%rax,4),%r9d
  40147c:	00 
  40147d:	8b 44 24 20          	mov    0x20(%rsp),%eax
  401481:	44 8b 84 84 a0 10 00 	mov    0x10a0(%rsp,%rax,4),%r8d
  401488:	00 
  401489:	8b 44 24 18          	mov    0x18(%rsp),%eax
  40148d:	8b b4 84 a0 10 00 00 	mov    0x10a0(%rsp,%rax,4),%esi
  401494:	8b 44 24 38          	mov    0x38(%rsp),%eax
  401498:	8b 94 84 a0 10 00 00 	mov    0x10a0(%rsp,%rax,4),%edx
  40149f:	8b 44 24 3c          	mov    0x3c(%rsp),%eax
  4014a3:	44 8b 9c 84 a0 10 00 	mov    0x10a0(%rsp,%rax,4),%r11d
  4014aa:	00 
  4014ab:	e9 3f f2 ff ff       	jmp    4006ef <main+0x32f>
  4014b0:	83 44 24 5c 01       	addl   $0x1,0x5c(%rsp)
  4014b5:	38 c2                	cmp    %al,%dl
  4014b7:	0f 85 63 fc ff ff    	jne    401120 <main+0xd60>
  4014bd:	48 8b b4 24 98 00 00 	mov    0x98(%rsp),%rsi
  4014c4:	00 
  4014c5:	48 8b bc 24 90 00 00 	mov    0x90(%rsp),%rdi
  4014cc:	00 
  4014cd:	ba c0 04 00 00       	mov    $0x4c0,%edx
  4014d2:	c5 f9 7f 74 24 70    	vmovdqa %xmm6,0x70(%rsp)
  4014d8:	e8 a3 ee ff ff       	call   400380 <memcmp@plt>
  4014dd:	c5 79 6f 05 ab 10 00 	vmovdqa 0x10ab(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  4014e4:	00 
  4014e5:	c5 f9 6f 3d b3 10 00 	vmovdqa 0x10b3(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  4014ec:	00 
  4014ed:	85 c0                	test   %eax,%eax
  4014ef:	c5 f9 6f 74 24 70    	vmovdqa 0x70(%rsp),%xmm6
  4014f5:	0f 85 25 fc ff ff    	jne    401120 <main+0xd60>
  4014fb:	ba 00 02 00 00       	mov    $0x200,%edx
  401500:	48 8d b4 24 20 05 00 	lea    0x520(%rsp),%rsi
  401507:	00 
  401508:	48 8d bc 24 20 03 00 	lea    0x320(%rsp),%rdi
  40150f:	00 
  401510:	e8 6b ee ff ff       	call   400380 <memcmp@plt>
  401515:	c5 79 6f 05 73 10 00 	vmovdqa 0x1073(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  40151c:	00 
  40151d:	c5 f9 6f 3d 7b 10 00 	vmovdqa 0x107b(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  401524:	00 
  401525:	85 c0                	test   %eax,%eax
  401527:	c5 f9 6f 74 24 70    	vmovdqa 0x70(%rsp),%xmm6
  40152d:	0f 84 03 fc ff ff    	je     401136 <main+0xd76>
  401533:	83 bc 24 8c 00 00 00 	cmpl   $0xb,0x8c(%rsp)
  40153a:	0b 
  40153b:	0f 87 ed fb ff ff    	ja     40112e <main+0xd6e>
  401541:	8b 74 24 38          	mov    0x38(%rsp),%esi
  401545:	45 89 f8             	mov    %r15d,%r8d
  401548:	44 89 f1             	mov    %r14d,%ecx
  40154b:	44 89 e2             	mov    %r12d,%edx
  40154e:	bf a0 24 40 00       	mov    $0x4024a0,%edi
  401553:	31 c0                	xor    %eax,%eax
  401555:	c5 f9 7f 74 24 70    	vmovdqa %xmm6,0x70(%rsp)
  40155b:	45 31 ff             	xor    %r15d,%r15d
  40155e:	e8 0d ee ff ff       	call   400370 <printf@plt>
  401563:	c5 f9 6f 3d 35 10 00 	vmovdqa 0x1035(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  40156a:	00 
  40156b:	c5 79 6f 05 1d 10 00 	vmovdqa 0x101d(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  401572:	00 
  401573:	4c 8d b4 24 60 0e 00 	lea    0xe60(%rsp),%r14
  40157a:	00 
  40157b:	4c 8d a4 24 20 13 00 	lea    0x1320(%rsp),%r12
  401582:	00 
  401583:	66 90                	xchg   %ax,%ax
  401585:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  40158c:	00 00 00 00 
  401590:	41 8b 0e             	mov    (%r14),%ecx
  401593:	45 8b 04 24          	mov    (%r12),%r8d
  401597:	44 39 c1             	cmp    %r8d,%ecx
  40159a:	74 21                	je     4015bd <main+0x11fd>
  40159c:	31 d2                	xor    %edx,%edx
  40159e:	44 89 fe             	mov    %r15d,%esi
  4015a1:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  4015a6:	31 c0                	xor    %eax,%eax
  4015a8:	e8 c3 ed ff ff       	call   400370 <printf@plt>
  4015ad:	c5 f9 6f 3d eb 0f 00 	vmovdqa 0xfeb(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  4015b4:	00 
  4015b5:	c5 79 6f 05 d3 0f 00 	vmovdqa 0xfd3(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  4015bc:	00 
  4015bd:	41 8b 4e 04          	mov    0x4(%r14),%ecx
  4015c1:	45 8b 44 24 04       	mov    0x4(%r12),%r8d
  4015c6:	44 39 c1             	cmp    %r8d,%ecx
  4015c9:	74 24                	je     4015ef <main+0x122f>
  4015cb:	ba 01 00 00 00       	mov    $0x1,%edx
  4015d0:	44 89 fe             	mov    %r15d,%esi
  4015d3:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  4015d8:	31 c0                	xor    %eax,%eax
  4015da:	e8 91 ed ff ff       	call   400370 <printf@plt>
  4015df:	c5 f9 6f 3d b9 0f 00 	vmovdqa 0xfb9(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  4015e6:	00 
  4015e7:	c5 79 6f 05 a1 0f 00 	vmovdqa 0xfa1(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  4015ee:	00 
  4015ef:	41 8b 4e 08          	mov    0x8(%r14),%ecx
  4015f3:	45 8b 44 24 08       	mov    0x8(%r12),%r8d
  4015f8:	44 39 c1             	cmp    %r8d,%ecx
  4015fb:	74 24                	je     401621 <main+0x1261>
  4015fd:	ba 02 00 00 00       	mov    $0x2,%edx
  401602:	44 89 fe             	mov    %r15d,%esi
  401605:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  40160a:	31 c0                	xor    %eax,%eax
  40160c:	e8 5f ed ff ff       	call   400370 <printf@plt>
  401611:	c5 f9 6f 3d 87 0f 00 	vmovdqa 0xf87(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  401618:	00 
  401619:	c5 79 6f 05 6f 0f 00 	vmovdqa 0xf6f(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  401620:	00 
  401621:	41 8b 4e 0c          	mov    0xc(%r14),%ecx
  401625:	45 8b 44 24 0c       	mov    0xc(%r12),%r8d
  40162a:	44 39 c1             	cmp    %r8d,%ecx
  40162d:	74 24                	je     401653 <main+0x1293>
  40162f:	ba 03 00 00 00       	mov    $0x3,%edx
  401634:	44 89 fe             	mov    %r15d,%esi
  401637:	bf c8 24 40 00       	mov    $0x4024c8,%edi
  40163c:	31 c0                	xor    %eax,%eax
  40163e:	e8 2d ed ff ff       	call   400370 <printf@plt>
  401643:	c5 f9 6f 3d 55 0f 00 	vmovdqa 0xf55(%rip),%xmm7        # 4025a0 <__dso_handle+0x310>
  40164a:	00 
  40164b:	c5 79 6f 05 3d 0f 00 	vmovdqa 0xf3d(%rip),%xmm8        # 402590 <__dso_handle+0x300>
  401652:	00 
  401653:	41 83 c7 01          	add    $0x1,%r15d
  401657:	49 83 c6 10          	add    $0x10,%r14
  40165b:	49 83 c4 10          	add    $0x10,%r12
  40165f:	41 83 ff 20          	cmp    $0x20,%r15d
  401663:	0f 85 27 ff ff ff    	jne    401590 <main+0x11d0>
  401669:	c5 f9 6f 74 24 70    	vmovdqa 0x70(%rsp),%xmm6
  40166f:	e9 ba fa ff ff       	jmp    40112e <main+0xd6e>
  401674:	be a8 22 40 00       	mov    $0x4022a8,%esi
  401679:	bf 9d 22 40 00       	mov    $0x40229d,%edi
  40167e:	31 c0                	xor    %eax,%eax
  401680:	e8 eb ec ff ff       	call   400370 <printf@plt>
  401685:	31 c0                	xor    %eax,%eax
  401687:	e9 37 fb ff ff       	jmp    4011c3 <main+0xe03>
  40168c:	0f 1f 40 00          	nopl   0x0(%rax)

0000000000401690 <_start>:
  401690:	f3 0f 1e fa          	endbr64
  401694:	31 ed                	xor    %ebp,%ebp
  401696:	49 89 d1             	mov    %rdx,%r9
  401699:	5e                   	pop    %rsi
  40169a:	48 89 e2             	mov    %rsp,%rdx
  40169d:	48 83 e4 f0          	and    $0xfffffffffffffff0,%rsp
  4016a1:	50                   	push   %rax
  4016a2:	54                   	push   %rsp
  4016a3:	45 31 c0             	xor    %r8d,%r8d
  4016a6:	31 c9                	xor    %ecx,%ecx
  4016a8:	48 c7 c7 c0 03 40 00 	mov    $0x4003c0,%rdi
  4016af:	ff 15 23 29 00 00    	call   *0x2923(%rip)        # 403fd8 <__libc_start_main@GLIBC_2.34>
  4016b5:	f4                   	hlt
  4016b6:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  4016bd:	00 00 00 

00000000004016c0 <_dl_relocate_static_pie>:
  4016c0:	f3 0f 1e fa          	endbr64
  4016c4:	c3                   	ret
  4016c5:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  4016cc:	00 00 00 
  4016cf:	90                   	nop

00000000004016d0 <deregister_tm_clones>:
  4016d0:	b8 28 40 40 00       	mov    $0x404028,%eax
  4016d5:	48 3d 28 40 40 00    	cmp    $0x404028,%rax
  4016db:	74 13                	je     4016f0 <deregister_tm_clones+0x20>
  4016dd:	b8 00 00 00 00       	mov    $0x0,%eax
  4016e2:	48 85 c0             	test   %rax,%rax
  4016e5:	74 09                	je     4016f0 <deregister_tm_clones+0x20>
  4016e7:	bf 28 40 40 00       	mov    $0x404028,%edi
  4016ec:	ff e0                	jmp    *%rax
  4016ee:	66 90                	xchg   %ax,%ax
  4016f0:	c3                   	ret
  4016f1:	0f 1f 40 00          	nopl   0x0(%rax)
  4016f5:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  4016fc:	00 00 00 00 

0000000000401700 <register_tm_clones>:
  401700:	be 28 40 40 00       	mov    $0x404028,%esi
  401705:	48 81 ee 28 40 40 00 	sub    $0x404028,%rsi
  40170c:	48 89 f0             	mov    %rsi,%rax
  40170f:	48 c1 ee 3f          	shr    $0x3f,%rsi
  401713:	48 c1 f8 03          	sar    $0x3,%rax
  401717:	48 01 c6             	add    %rax,%rsi
  40171a:	48 d1 fe             	sar    $1,%rsi
  40171d:	74 11                	je     401730 <register_tm_clones+0x30>
  40171f:	b8 00 00 00 00       	mov    $0x0,%eax
  401724:	48 85 c0             	test   %rax,%rax
  401727:	74 07                	je     401730 <register_tm_clones+0x30>
  401729:	bf 28 40 40 00       	mov    $0x404028,%edi
  40172e:	ff e0                	jmp    *%rax
  401730:	c3                   	ret
  401731:	0f 1f 40 00          	nopl   0x0(%rax)
  401735:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  40173c:	00 00 00 00 

0000000000401740 <__do_global_dtors_aux>:
  401740:	f3 0f 1e fa          	endbr64
  401744:	80 3d fd 28 00 00 00 	cmpb   $0x0,0x28fd(%rip)        # 404048 <completed.0>
  40174b:	75 13                	jne    401760 <__do_global_dtors_aux+0x20>
  40174d:	55                   	push   %rbp
  40174e:	48 89 e5             	mov    %rsp,%rbp
  401751:	e8 7a ff ff ff       	call   4016d0 <deregister_tm_clones>
  401756:	c6 05 eb 28 00 00 01 	movb   $0x1,0x28eb(%rip)        # 404048 <completed.0>
  40175d:	5d                   	pop    %rbp
  40175e:	c3                   	ret
  40175f:	90                   	nop
  401760:	c3                   	ret
  401761:	0f 1f 40 00          	nopl   0x0(%rax)
  401765:	66 66 2e 0f 1f 84 00 	data16 cs nopw 0x0(%rax,%rax,1)
  40176c:	00 00 00 00 

0000000000401770 <frame_dummy>:
  401770:	f3 0f 1e fa          	endbr64
  401774:	eb 8a                	jmp    401700 <register_tm_clones>
  401776:	66 2e 0f 1f 84 00 00 	cs nopw 0x0(%rax,%rax,1)
  40177d:	00 00 00 

0000000000401780 <before(Mips2C::ExecutionContext*)>:
  401780:	48 83 ec 08          	sub    $0x8,%rsp
  401784:	48 8b 97 40 01 00 00 	mov    0x140(%rdi),%rdx
  40178b:	f6 c2 0f             	test   $0xf,%dl
  40178e:	0f 85 9a 02 00 00    	jne    401a2e <before(Mips2C::ExecutionContext*)+0x2ae>
  401794:	48 8b 05 b5 28 00 00 	mov    0x28b5(%rip),%rax        # 404050 <g_ee_main_mem>
  40179b:	89 d2                	mov    %edx,%edx
  40179d:	c5 fa 7e 2c 10       	vmovq  (%rax,%rdx,1),%xmm5
  4017a2:	4c 8b 44 10 08       	mov    0x8(%rax,%rdx,1),%r8
  4017a7:	c5 f9 d6 af 00 03 00 	vmovq  %xmm5,0x300(%rdi)
  4017ae:	00 
  4017af:	4c 89 87 08 03 00 00 	mov    %r8,0x308(%rdi)
  4017b6:	48 8b 74 10 10       	mov    0x10(%rax,%rdx,1),%rsi
  4017bb:	48 8b 4c 10 18       	mov    0x18(%rax,%rdx,1),%rcx
  4017c0:	48 89 b7 10 03 00 00 	mov    %rsi,0x310(%rdi)
  4017c7:	48 89 8f 18 03 00 00 	mov    %rcx,0x318(%rdi)
  4017ce:	c5 fa 7e 64 10 20    	vmovq  0x20(%rax,%rdx,1),%xmm4
  4017d4:	48 8b 74 10 28       	mov    0x28(%rax,%rdx,1),%rsi
  4017d9:	48 8b 97 50 01 00 00 	mov    0x150(%rdi),%rdx
  4017e0:	c5 f9 d6 a7 20 03 00 	vmovq  %xmm4,0x320(%rdi)
  4017e7:	00 
  4017e8:	48 89 b7 28 03 00 00 	mov    %rsi,0x328(%rdi)
  4017ef:	f6 c2 0f             	test   $0xf,%dl
  4017f2:	0f 85 36 02 00 00    	jne    401a2e <before(Mips2C::ExecutionContext*)+0x2ae>
  4017f8:	89 d2                	mov    %edx,%edx
  4017fa:	c4 e3 d9 22 e6 01    	vpinsrq $0x1,%rsi,%xmm4,%xmm4
  401800:	c4 c3 d1 22 e8 01    	vpinsrq $0x1,%r8,%xmm5,%xmm5
  401806:	c4 e2 79 18 97 88 03 	vbroadcastss 0x388(%rdi),%xmm2
  40180d:	00 00 
  40180f:	4c 8d 4c 10 10       	lea    0x10(%rax,%rdx,1),%r9
  401814:	c5 7a 10 97 8c 03 00 	vmovss 0x38c(%rdi),%xmm10
  40181b:	00 
  40181c:	49 8b 31             	mov    (%r9),%rsi
  40181f:	4d 8b 59 08          	mov    0x8(%r9),%r11
  401823:	48 89 b7 30 03 00 00 	mov    %rsi,0x330(%rdi)
  40182a:	4c 89 9f 38 03 00 00 	mov    %r11,0x338(%rdi)
  401831:	c5 fa 7e 44 10 20    	vmovq  0x20(%rax,%rdx,1),%xmm0
  401837:	4c 8b 44 10 28       	mov    0x28(%rax,%rdx,1),%r8
  40183c:	c5 f9 d6 87 40 03 00 	vmovq  %xmm0,0x340(%rdi)
  401843:	00 
  401844:	4c 89 87 48 03 00 00 	mov    %r8,0x348(%rdi)
  40184b:	c4 c3 f9 22 c8 01    	vpinsrq $0x1,%r8,%xmm0,%xmm1
  401851:	c5 fa 7e 44 10 30    	vmovq  0x30(%rax,%rdx,1),%xmm0
  401857:	4c 8b 44 10 38       	mov    0x38(%rax,%rdx,1),%r8
  40185c:	c5 f9 d6 87 50 03 00 	vmovq  %xmm0,0x350(%rdi)
  401863:	00 
  401864:	4c 89 87 58 03 00 00 	mov    %r8,0x358(%rdi)
  40186b:	c5 fa 6f 5c 10 40    	vmovdqu 0x40(%rax,%rdx,1),%xmm3
  401871:	c4 c3 f9 22 f0 01    	vpinsrq $0x1,%r8,%xmm0,%xmm6
  401877:	c5 fa 10 87 84 03 00 	vmovss 0x384(%rdi),%xmm0
  40187e:	00 
  40187f:	c5 e8 59 d3          	vmulps %xmm3,%xmm2,%xmm2
  401883:	c5 fa 7f 9f 60 03 00 	vmovdqu %xmm3,0x360(%rdi)
  40188a:	00 
  40188b:	c5 f9 6e de          	vmovd  %esi,%xmm3
  40188f:	48 c1 ee 20          	shr    $0x20,%rsi
  401893:	c5 f9 6e fe          	vmovd  %esi,%xmm7
  401897:	4c 63 54 10 60       	movslq 0x60(%rax,%rdx,1),%r10
  40189c:	c5 e0 14 df          	vunpcklps %xmm7,%xmm3,%xmm3
  4018a0:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
  4018a4:	44 89 97 00 02 00 00 	mov    %r10d,0x200(%rdi)
  4018ab:	4d 89 d0             	mov    %r10,%r8
  4018ae:	4c 89 57 30          	mov    %r10,0x30(%rdi)
  4018b2:	c5 fa 7e fa          	vmovq  %xmm2,%xmm7
  4018b6:	c5 f8 29 97 60 03 00 	vmovaps %xmm2,0x360(%rdi)
  4018bd:	00 
  4018be:	c5 e8 15 d2          	vunpckhps %xmm2,%xmm2,%xmm2
  4018c2:	c5 e0 58 df          	vaddps %xmm7,%xmm3,%xmm3
  4018c6:	c4 c1 79 6e fb       	vmovd  %r11d,%xmm7
  4018cb:	c5 ea 58 ff          	vaddss %xmm7,%xmm2,%xmm7
  4018cf:	c5 f8 13 9f 30 03 00 	vmovlps %xmm3,0x330(%rdi)
  4018d6:	00 
  4018d7:	c5 fa 11 bf 38 03 00 	vmovss %xmm7,0x338(%rdi)
  4018de:	00 
  4018df:	45 85 d2             	test   %r10d,%r10d
  4018e2:	74 7d                	je     401961 <before(Mips2C::ExecutionContext*)+0x1e1>
  4018e4:	c4 c1 79 6e d2       	vmovd  %r10d,%xmm2
  4018e9:	4c 8b 5f 38          	mov    0x38(%rdi),%r11
  4018ed:	4c 89 d6             	mov    %r10,%rsi
  4018f0:	c5 7a 10 05 28 0d 00 	vmovss 0xd28(%rip),%xmm8        # 402620 <__dso_handle+0x390>
  4018f7:	00 
  4018f8:	48 c1 ee 20          	shr    $0x20,%rsi
  4018fc:	c4 41 28 c6 d2 00    	vshufps $0x0,%xmm10,%xmm10,%xmm10
  401902:	c5 3a 5c ca          	vsubss %xmm2,%xmm8,%xmm9
  401906:	c4 41 79 6e db       	vmovd  %r11d,%xmm11
  40190b:	c5 79 6e e6          	vmovd  %esi,%xmm12
  40190f:	c4 c1 68 14 d4       	vunpcklps %xmm12,%xmm2,%xmm2
  401914:	c4 41 20 14 c9       	vunpcklps %xmm9,%xmm11,%xmm9
  401919:	c4 c1 68 16 d1       	vmovlhps %xmm9,%xmm2,%xmm2
  40191e:	c4 c1 68 59 d2       	vmulps %xmm10,%xmm2,%xmm2
  401923:	c5 7a 7e cb          	vmovq  %xmm3,%xmm9
  401927:	c5 f8 29 97 70 03 00 	vmovaps %xmm2,0x370(%rdi)
  40192e:	00 
  40192f:	c5 e8 c6 d2 ff       	vshufps $0xff,%xmm2,%xmm2,%xmm2
  401934:	c5 ba 5c d2          	vsubss %xmm2,%xmm8,%xmm2
  401938:	c5 c2 59 fa          	vmulss %xmm2,%xmm7,%xmm7
  40193c:	c5 7a 12 c2          	vmovsldup %xmm2,%xmm8
  401940:	c5 fa 11 97 7c 03 00 	vmovss %xmm2,0x37c(%rdi)
  401947:	00 
  401948:	c5 79 d6 c3          	vmovq  %xmm8,%xmm3
  40194c:	c4 c1 60 59 d9       	vmulps %xmm9,%xmm3,%xmm3
  401951:	c5 fa 11 bf 38 03 00 	vmovss %xmm7,0x338(%rdi)
  401958:	00 
  401959:	c5 f8 13 9f 30 03 00 	vmovlps %xmm3,0x330(%rdi)
  401960:	00 
  401961:	c5 f8 28 9f 30 03 00 	vmovaps 0x330(%rdi),%xmm3
  401968:	00 
  401969:	c5 f8 c6 c0 00       	vshufps $0x0,%xmm0,%xmm0,%xmm0
  40196e:	c5 f8 59 c9          	vmulps %xmm1,%xmm0,%xmm1
  401972:	48 c1 e9 20          	shr    $0x20,%rcx
  401976:	c5 e0 59 d0          	vmulps %xmm0,%xmm3,%xmm2
  40197a:	c5 f8 59 c6          	vmulps %xmm6,%xmm0,%xmm0
  40197e:	c5 f9 6e f1          	vmovd  %ecx,%xmm6
  401982:	c5 f8 29 8f a0 03 00 	vmovaps %xmm1,0x3a0(%rdi)
  401989:	00 
  40198a:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
  40198f:	c5 f2 58 ce          	vaddss %xmm6,%xmm1,%xmm1
  401993:	c5 f8 29 97 90 03 00 	vmovaps %xmm2,0x390(%rdi)
  40199a:	00 
  40199b:	c5 e8 58 d5          	vaddps %xmm5,%xmm2,%xmm2
  40199f:	c5 f8 29 87 b0 03 00 	vmovaps %xmm0,0x3b0(%rdi)
  4019a6:	00 
  4019a7:	c5 f8 58 c4          	vaddps %xmm4,%xmm0,%xmm0
  4019ab:	c5 fa 11 8f 1c 03 00 	vmovss %xmm1,0x31c(%rdi)
  4019b2:	00 
  4019b3:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  4019b7:	c5 f8 29 97 00 03 00 	vmovaps %xmm2,0x300(%rdi)
  4019be:	00 
  4019bf:	c5 f0 5f c0          	vmaxps %xmm0,%xmm1,%xmm0
  4019c3:	c5 f8 29 87 20 03 00 	vmovaps %xmm0,0x320(%rdi)
  4019ca:	00 
  4019cb:	c4 c1 78 11 19       	vmovups %xmm3,(%r9)
  4019d0:	48 8b 97 40 01 00 00 	mov    0x140(%rdi),%rdx
  4019d7:	f6 c2 0f             	test   $0xf,%dl
  4019da:	75 71                	jne    401a4d <before(Mips2C::ExecutionContext*)+0x2cd>
  4019dc:	c5 f9 6f 87 00 03 00 	vmovdqa 0x300(%rdi),%xmm0
  4019e3:	00 
  4019e4:	89 d2                	mov    %edx,%edx
  4019e6:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
  4019eb:	48 8b 97 40 01 00 00 	mov    0x140(%rdi),%rdx
  4019f2:	f6 c2 0f             	test   $0xf,%dl
  4019f5:	75 56                	jne    401a4d <before(Mips2C::ExecutionContext*)+0x2cd>
  4019f7:	c5 f9 6f 87 10 03 00 	vmovdqa 0x310(%rdi),%xmm0
  4019fe:	00 
  4019ff:	89 d2                	mov    %edx,%edx
  401a01:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
  401a07:	48 8b 97 40 01 00 00 	mov    0x140(%rdi),%rdx
  401a0e:	f6 c2 0f             	test   $0xf,%dl
  401a11:	75 3a                	jne    401a4d <before(Mips2C::ExecutionContext*)+0x2cd>
  401a13:	c5 f9 6f 87 20 03 00 	vmovdqa 0x320(%rdi),%xmm0
  401a1a:	00 
  401a1b:	45 85 c0             	test   %r8d,%r8d
  401a1e:	89 d2                	mov    %edx,%edx
  401a20:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
  401a26:	0f 94 c0             	sete   %al
  401a29:	48 83 c4 08          	add    $0x8,%rsp
  401a2d:	c3                   	ret
  401a2e:	41 b8 a7 22 40 00    	mov    $0x4022a7,%r8d
  401a34:	b9 c8 22 40 00       	mov    $0x4022c8,%ecx
  401a39:	ba 58 01 00 00       	mov    $0x158,%edx
  401a3e:	be 00 23 40 00       	mov    $0x402300,%esi
  401a43:	bf 20 23 40 00       	mov    $0x402320,%edi
  401a48:	e8 83 03 00 00       	call   401dd0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  401a4d:	41 b8 a7 22 40 00    	mov    $0x4022a7,%r8d
  401a53:	b9 50 23 40 00       	mov    $0x402350,%ecx
  401a58:	ba c0 01 00 00       	mov    $0x1c0,%edx
  401a5d:	be 00 23 40 00       	mov    $0x402300,%esi
  401a62:	bf 88 23 40 00       	mov    $0x402388,%edi
  401a67:	e8 64 03 00 00       	call   401dd0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  401a6c:	0f 1f 40 00          	nopl   0x0(%rax)

0000000000401a70 <after(Mips2C::ExecutionContext*)>:
  401a70:	55                   	push   %rbp
  401a71:	48 89 e5             	mov    %rsp,%rbp
  401a74:	41 56                	push   %r14
  401a76:	41 55                	push   %r13
  401a78:	41 54                	push   %r12
  401a7a:	53                   	push   %rbx
  401a7b:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
  401a7f:	48 83 ec 40          	sub    $0x40,%rsp
  401a83:	8b 8f 40 01 00 00    	mov    0x140(%rdi),%ecx
  401a89:	f6 c1 0f             	test   $0xf,%cl
  401a8c:	0f 85 1f 03 00 00    	jne    401db1 <after(Mips2C::ExecutionContext*)+0x341>
  401a92:	48 8b 05 b7 25 00 00 	mov    0x25b7(%rip),%rax        # 404050 <g_ee_main_mem>
  401a99:	8b 97 50 01 00 00    	mov    0x150(%rdi),%edx
  401a9f:	48 8b 5c 08 18       	mov    0x18(%rax,%rcx,1),%rbx
  401aa4:	c5 fa 6f 34 08       	vmovdqu (%rax,%rcx,1),%xmm6
  401aa9:	4c 8b 44 08 10       	mov    0x10(%rax,%rcx,1),%r8
  401aae:	49 89 d9             	mov    %rbx,%r9
  401ab1:	f6 c2 0f             	test   $0xf,%dl
  401ab4:	0f 85 d8 02 00 00    	jne    401d92 <after(Mips2C::ExecutionContext*)+0x322>
  401aba:	c5 fa 6f 5c 08 20    	vmovdqu 0x20(%rax,%rcx,1),%xmm3
  401ac0:	48 8b 8f 88 03 00 00 	mov    0x388(%rdi),%rcx
  401ac7:	49 be 00 00 00 00 ff 	movabs $0xffffffff00000000,%r14
  401ace:	ff ff ff 
  401ad1:	c5 fa 6f 4c 10 40    	vmovdqu 0x40(%rax,%rdx,1),%xmm1
  401ad7:	c5 fa 7e 44 10 10    	vmovq  0x10(%rax,%rdx,1),%xmm0
  401add:	c5 f9 6e d1          	vmovd  %ecx,%xmm2
  401ae1:	4c 8b 64 10 18       	mov    0x18(%rax,%rdx,1),%r12
  401ae6:	4c 8b 9f 50 01 00 00 	mov    0x150(%rdi),%r11
  401aed:	c5 e8 c6 d2 00       	vshufps $0x0,%xmm2,%xmm2,%xmm2
  401af2:	c5 e8 59 d1          	vmulps %xmm1,%xmm2,%xmm2
  401af6:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  401afa:	c5 fa 6f 6c 10 20    	vmovdqu 0x20(%rax,%rdx,1),%xmm5
  401b00:	4c 89 64 24 38       	mov    %r12,0x38(%rsp)
  401b05:	45 89 da             	mov    %r11d,%r10d
  401b08:	c5 fa 6f 64 10 30    	vmovdqu 0x30(%rax,%rdx,1),%xmm4
  401b0e:	4a 63 54 10 60       	movslq 0x60(%rax,%r10,1),%rdx
  401b13:	48 89 d6             	mov    %rdx,%rsi
  401b16:	89 97 00 02 00 00    	mov    %edx,0x200(%rdi)
  401b1c:	c5 fa 7e ca          	vmovq  %xmm2,%xmm1
  401b20:	c5 e8 15 fa          	vunpckhps %xmm2,%xmm2,%xmm7
  401b24:	48 89 57 30          	mov    %rdx,0x30(%rdi)
  401b28:	48 8b 97 80 03 00 00 	mov    0x380(%rdi),%rdx
  401b2f:	c5 f8 58 c1          	vaddps %xmm1,%xmm0,%xmm0
  401b33:	c4 c1 79 6e cc       	vmovd  %r12d,%xmm1
  401b38:	4c 8b 64 24 38       	mov    0x38(%rsp),%r12
  401b3d:	c5 c2 58 f9          	vaddss %xmm1,%xmm7,%xmm7
  401b41:	4d 21 f4             	and    %r14,%r12
  401b44:	c5 f8 13 44 24 30    	vmovlps %xmm0,0x30(%rsp)
  401b4a:	c4 c1 79 7e fd       	vmovd  %xmm7,%r13d
  401b4f:	4d 09 ec             	or     %r13,%r12
  401b52:	4c 89 64 24 38       	mov    %r12,0x38(%rsp)
  401b57:	85 f6                	test   %esi,%esi
  401b59:	0f 84 cf 00 00 00    	je     401c2e <after(Mips2C::ExecutionContext*)+0x1be>
  401b5f:	4c 8b 67 30          	mov    0x30(%rdi),%r12
  401b63:	4c 8b 6f 38          	mov    0x38(%rdi),%r13
  401b67:	48 c1 e9 20          	shr    $0x20,%rcx
  401b6b:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  401b6f:	c5 fa 10 0d a9 0a 00 	vmovss 0xaa9(%rip),%xmm1        # 402620 <__dso_handle+0x390>
  401b76:	00 
  401b77:	c5 79 6e d9          	vmovd  %ecx,%xmm11
  401b7b:	c5 79 6f 7c 24 30    	vmovdqa 0x30(%rsp),%xmm15
  401b81:	c4 41 79 6e c4       	vmovd  %r12d,%xmm8
  401b86:	4c 89 6c 24 28       	mov    %r13,0x28(%rsp)
  401b8b:	44 8b 6c 24 28       	mov    0x28(%rsp),%r13d
  401b90:	c4 41 72 5c d0       	vsubss %xmm8,%xmm1,%xmm10
  401b95:	4c 89 64 24 20       	mov    %r12,0x20(%rsp)
  401b9a:	c4 41 20 c6 c3 00    	vshufps $0x0,%xmm11,%xmm11,%xmm8
  401ba0:	c5 79 7f bf 30 03 00 	vmovdqa %xmm15,0x330(%rdi)
  401ba7:	00 
  401ba8:	c4 41 79 7e d4       	vmovd  %xmm10,%r12d
  401bad:	49 c1 e4 20          	shl    $0x20,%r12
  401bb1:	4d 09 ec             	or     %r13,%r12
  401bb4:	4c 89 64 24 28       	mov    %r12,0x28(%rsp)
  401bb9:	c5 38 59 64 24 20    	vmulps 0x20(%rsp),%xmm8,%xmm12
  401bbf:	c4 41 18 c6 c4 ff    	vshufps $0xff,%xmm12,%xmm12,%xmm8
  401bc5:	c4 c1 72 5c c8       	vsubss %xmm8,%xmm1,%xmm1
  401bca:	c5 78 29 64 24 10    	vmovaps %xmm12,0x10(%rsp)
  401bd0:	8b 4c 24 18          	mov    0x18(%rsp),%ecx
  401bd4:	c5 79 6f 6c 24 10    	vmovdqa 0x10(%rsp),%xmm13
  401bda:	c5 7a 12 c1          	vmovsldup %xmm1,%xmm8
  401bde:	c4 c1 79 7e cc       	vmovd  %xmm1,%r12d
  401be3:	c5 79 d6 6c 24 20    	vmovq  %xmm13,0x20(%rsp)
  401be9:	c5 f2 59 cf          	vmulss %xmm7,%xmm1,%xmm1
  401bed:	49 c1 e4 20          	shl    $0x20,%r12
  401bf1:	4c 09 e1             	or     %r12,%rcx
  401bf4:	48 89 4c 24 28       	mov    %rcx,0x28(%rsp)
  401bf9:	c5 79 6f 54 24 20    	vmovdqa 0x20(%rsp),%xmm10
  401bff:	c4 41 7a 7e c0       	vmovq  %xmm8,%xmm8
  401c04:	c5 b8 59 c0          	vmulps %xmm0,%xmm8,%xmm0
  401c08:	c5 79 7f 97 70 03 00 	vmovdqa %xmm10,0x370(%rdi)
  401c0f:	00 
  401c10:	c5 fa 11 8f 38 03 00 	vmovss %xmm1,0x338(%rdi)
  401c17:	00 
  401c18:	c5 f8 13 87 30 03 00 	vmovlps %xmm0,0x330(%rdi)
  401c1f:	00 
  401c20:	c5 f9 6f bf 30 03 00 	vmovdqa 0x330(%rdi),%xmm7
  401c27:	00 
  401c28:	c5 f9 7f 7c 24 30    	vmovdqa %xmm7,0x30(%rsp)
  401c2e:	48 c1 ea 20          	shr    $0x20,%rdx
  401c32:	48 c1 eb 20          	shr    $0x20,%rbx
  401c36:	4c 89 87 10 03 00 00 	mov    %r8,0x310(%rdi)
  401c3d:	c5 f9 6e fa          	vmovd  %edx,%xmm7
  401c41:	c5 79 6e cb          	vmovd  %ebx,%xmm9
  401c45:	44 89 ca             	mov    %r9d,%edx
  401c48:	c5 f9 7f af 40 03 00 	vmovdqa %xmm5,0x340(%rdi)
  401c4f:	00 
  401c50:	c5 c0 c6 c7 00       	vshufps $0x0,%xmm7,%xmm7,%xmm0
  401c55:	c5 f8 59 fd          	vmulps %xmm5,%xmm0,%xmm7
  401c59:	c5 f9 7f a7 50 03 00 	vmovdqa %xmm4,0x350(%rdi)
  401c60:	00 
  401c61:	c5 78 59 44 24 30    	vmulps 0x30(%rsp),%xmm0,%xmm8
  401c67:	c5 f9 7f 97 60 03 00 	vmovdqa %xmm2,0x360(%rdi)
  401c6e:	00 
  401c6f:	c5 f8 59 c4          	vmulps %xmm4,%xmm0,%xmm0
  401c73:	c5 c0 c6 cf ff       	vshufps $0xff,%xmm7,%xmm7,%xmm1
  401c78:	c4 c1 72 58 c9       	vaddss %xmm9,%xmm1,%xmm1
  401c7d:	c5 b8 58 f6          	vaddps %xmm6,%xmm8,%xmm6
  401c81:	c5 f8 58 db          	vaddps %xmm3,%xmm0,%xmm3
  401c85:	c5 f9 7e c9          	vmovd  %xmm1,%ecx
  401c89:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  401c8d:	48 c1 e1 20          	shl    $0x20,%rcx
  401c91:	c5 f9 7f b7 00 03 00 	vmovdqa %xmm6,0x300(%rdi)
  401c98:	00 
  401c99:	c5 f0 5f cb          	vmaxps %xmm3,%xmm1,%xmm1
  401c9d:	c5 f9 6f 5c 24 30    	vmovdqa 0x30(%rsp),%xmm3
  401ca3:	48 09 ca             	or     %rcx,%rdx
  401ca6:	48 89 97 18 03 00 00 	mov    %rdx,0x318(%rdi)
  401cad:	c5 f9 7f 9f 30 03 00 	vmovdqa %xmm3,0x330(%rdi)
  401cb4:	00 
  401cb5:	c5 f9 7f 8f 20 03 00 	vmovdqa %xmm1,0x320(%rdi)
  401cbc:	00 
  401cbd:	85 f6                	test   %esi,%esi
  401cbf:	0f 85 9b 00 00 00    	jne    401d60 <after(Mips2C::ExecutionContext*)+0x2f0>
  401cc5:	41 83 e3 0f          	and    $0xf,%r11d
  401cc9:	c5 79 7f 87 90 03 00 	vmovdqa %xmm8,0x390(%rdi)
  401cd0:	00 
  401cd1:	c5 f9 7f bf a0 03 00 	vmovdqa %xmm7,0x3a0(%rdi)
  401cd8:	00 
  401cd9:	c5 f9 7f 87 b0 03 00 	vmovdqa %xmm0,0x3b0(%rdi)
  401ce0:	00 
  401ce1:	0f 85 8c 00 00 00    	jne    401d73 <after(Mips2C::ExecutionContext*)+0x303>
  401ce7:	c5 f9 6f 87 30 03 00 	vmovdqa 0x330(%rdi),%xmm0
  401cee:	00 
  401cef:	c4 a1 7a 7f 44 10 10 	vmovdqu %xmm0,0x10(%rax,%r10,1)
  401cf6:	48 8b 97 40 01 00 00 	mov    0x140(%rdi),%rdx
  401cfd:	f6 c2 0f             	test   $0xf,%dl
  401d00:	75 71                	jne    401d73 <after(Mips2C::ExecutionContext*)+0x303>
  401d02:	c5 f9 6f 87 00 03 00 	vmovdqa 0x300(%rdi),%xmm0
  401d09:	00 
  401d0a:	89 d2                	mov    %edx,%edx
  401d0c:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
  401d11:	48 8b 97 40 01 00 00 	mov    0x140(%rdi),%rdx
  401d18:	f6 c2 0f             	test   $0xf,%dl
  401d1b:	75 56                	jne    401d73 <after(Mips2C::ExecutionContext*)+0x303>
  401d1d:	c5 f9 6f 87 10 03 00 	vmovdqa 0x310(%rdi),%xmm0
  401d24:	00 
  401d25:	89 d2                	mov    %edx,%edx
  401d27:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
  401d2d:	48 8b 97 40 01 00 00 	mov    0x140(%rdi),%rdx
  401d34:	f6 c2 0f             	test   $0xf,%dl
  401d37:	75 3a                	jne    401d73 <after(Mips2C::ExecutionContext*)+0x303>
  401d39:	c5 f9 6f 87 20 03 00 	vmovdqa 0x320(%rdi),%xmm0
  401d40:	00 
  401d41:	85 f6                	test   %esi,%esi
  401d43:	89 d2                	mov    %edx,%edx
  401d45:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
  401d4b:	0f 94 c0             	sete   %al
  401d4e:	48 8d 65 e0          	lea    -0x20(%rbp),%rsp
  401d52:	5b                   	pop    %rbx
  401d53:	41 5c                	pop    %r12
  401d55:	41 5d                	pop    %r13
  401d57:	41 5e                	pop    %r14
  401d59:	5d                   	pop    %rbp
  401d5a:	c3                   	ret
  401d5b:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
  401d60:	c5 f9 6f 64 24 20    	vmovdqa 0x20(%rsp),%xmm4
  401d66:	c5 f9 7f a7 70 03 00 	vmovdqa %xmm4,0x370(%rdi)
  401d6d:	00 
  401d6e:	e9 52 ff ff ff       	jmp    401cc5 <after(Mips2C::ExecutionContext*)+0x255>
  401d73:	41 b8 a7 22 40 00    	mov    $0x4022a7,%r8d
  401d79:	b9 50 23 40 00       	mov    $0x402350,%ecx
  401d7e:	ba c0 01 00 00       	mov    $0x1c0,%edx
  401d83:	be 00 23 40 00       	mov    $0x402300,%esi
  401d88:	bf 88 23 40 00       	mov    $0x402388,%edi
  401d8d:	e8 3e 00 00 00       	call   401dd0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  401d92:	41 b8 a7 22 40 00    	mov    $0x4022a7,%r8d
  401d98:	b9 b0 23 40 00       	mov    $0x4023b0,%ecx
  401d9d:	ba 3b 00 00 00       	mov    $0x3b,%edx
  401da2:	be d8 23 40 00       	mov    $0x4023d8,%esi
  401da7:	bf 70 24 40 00       	mov    $0x402470,%edi
  401dac:	e8 1f 00 00 00       	call   401dd0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  401db1:	41 b8 a7 22 40 00    	mov    $0x4022a7,%r8d
  401db7:	b9 b0 23 40 00       	mov    $0x4023b0,%ecx
  401dbc:	ba 35 00 00 00       	mov    $0x35,%edx
  401dc1:	be d8 23 40 00       	mov    $0x4023d8,%esi
  401dc6:	bf 40 24 40 00       	mov    $0x402440,%edi
  401dcb:	e8 00 00 00 00       	call   401dd0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>

0000000000401dd0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>:
  401dd0:	48 83 ec 10          	sub    $0x10,%rsp
  401dd4:	49 89 c9             	mov    %rcx,%r9
  401dd7:	31 c0                	xor    %eax,%eax
  401dd9:	48 89 f1             	mov    %rsi,%rcx
  401ddc:	41 50                	push   %r8
  401dde:	41 89 d0             	mov    %edx,%r8d
  401de1:	48 89 fa             	mov    %rdi,%rdx
  401de4:	48 8b 3d 55 22 00 00 	mov    0x2255(%rip),%rdi        # 404040 <stderr@GLIBC_2.2.5>
  401deb:	be ad 22 40 00       	mov    $0x4022ad,%esi
  401df0:	e8 ab e5 ff ff       	call   4003a0 <fprintf@plt>
  401df5:	e8 96 e5 ff ff       	call   400390 <abort@plt>

Disassembly of section .fini:

0000000000401dfc <_fini>:
  401dfc:	f3 0f 1e fa          	endbr64
  401e00:	48 83 ec 08          	sub    $0x8,%rsp
  401e04:	48 83 c4 08          	add    $0x8,%rsp
  401e08:	c3                   	ret
