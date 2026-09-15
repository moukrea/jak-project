$ objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/frontier-x86

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/frontier-x86:     file format elf64-x86-64


Disassembly of section .init:

000000000040033c <_init>:
  40033c:	f3 0f 1e fa          	endbr64
  400340:	48 83 ec 08          	sub    $0x8,%rsp
  400344:	48 8b 05 95 8c 00 00 	mov    0x8c95(%rip),%rax        # 408fe0 <__gmon_start__@Base>
  40034b:	48 85 c0             	test   %rax,%rax
  40034e:	74 02                	je     400352 <_init+0x16>
  400350:	ff d0                	call   *%rax
  400352:	48 83 c4 08          	add    $0x8,%rsp
  400356:	c3                   	ret

Disassembly of section .plt:

0000000000400360 <printf@plt-0x10>:
  400360:	ff 35 8a 8c 00 00    	push   0x8c8a(%rip)        # 408ff0 <_GLOBAL_OFFSET_TABLE_+0x8>
  400366:	ff 25 8c 8c 00 00    	jmp    *0x8c8c(%rip)        # 408ff8 <_GLOBAL_OFFSET_TABLE_+0x10>
  40036c:	0f 1f 40 00          	nopl   0x0(%rax)

0000000000400370 <printf@plt>:
  400370:	ff 25 8a 8c 00 00    	jmp    *0x8c8a(%rip)        # 409000 <printf@GLIBC_2.2.5>
  400376:	68 00 00 00 00       	push   $0x0
  40037b:	e9 e0 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400380 <__cxa_begin_catch@plt>:
  400380:	ff 25 82 8c 00 00    	jmp    *0x8c82(%rip)        # 409008 <__cxa_begin_catch@CXXABI_1.3>
  400386:	68 01 00 00 00       	push   $0x1
  40038b:	e9 d0 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400390 <memcmp@plt>:
  400390:	ff 25 7a 8c 00 00    	jmp    *0x8c7a(%rip)        # 409010 <memcmp@GLIBC_2.2.5>
  400396:	68 02 00 00 00       	push   $0x2
  40039b:	e9 c0 ff ff ff       	jmp    400360 <_init+0x24>

00000000004003a0 <__cxa_allocate_exception@plt>:
  4003a0:	ff 25 72 8c 00 00    	jmp    *0x8c72(%rip)        # 409018 <__cxa_allocate_exception@CXXABI_1.3>
  4003a6:	68 03 00 00 00       	push   $0x3
  4003ab:	e9 b0 ff ff ff       	jmp    400360 <_init+0x24>

00000000004003b0 <abort@plt>:
  4003b0:	ff 25 6a 8c 00 00    	jmp    *0x8c6a(%rip)        # 409020 <abort@GLIBC_2.2.5>
  4003b6:	68 04 00 00 00       	push   $0x4
  4003bb:	e9 a0 ff ff ff       	jmp    400360 <_init+0x24>

00000000004003c0 <perror@plt>:
  4003c0:	ff 25 62 8c 00 00    	jmp    *0x8c62(%rip)        # 409028 <perror@GLIBC_2.2.5>
  4003c6:	68 05 00 00 00       	push   $0x5
  4003cb:	e9 90 ff ff ff       	jmp    400360 <_init+0x24>

00000000004003d0 <fclose@plt>:
  4003d0:	ff 25 5a 8c 00 00    	jmp    *0x8c5a(%rip)        # 409030 <fclose@GLIBC_2.2.5>
  4003d6:	68 06 00 00 00       	push   $0x6
  4003db:	e9 80 ff ff ff       	jmp    400360 <_init+0x24>

00000000004003e0 <fopen@plt>:
  4003e0:	ff 25 52 8c 00 00    	jmp    *0x8c52(%rip)        # 409038 <fopen@GLIBC_2.2.5>
  4003e6:	68 07 00 00 00       	push   $0x7
  4003eb:	e9 70 ff ff ff       	jmp    400360 <_init+0x24>

00000000004003f0 <fprintf@plt>:
  4003f0:	ff 25 4a 8c 00 00    	jmp    *0x8c4a(%rip)        # 409040 <fprintf@GLIBC_2.2.5>
  4003f6:	68 08 00 00 00       	push   $0x8
  4003fb:	e9 60 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400400 <__cxa_end_catch@plt>:
  400400:	ff 25 42 8c 00 00    	jmp    *0x8c42(%rip)        # 409048 <__cxa_end_catch@CXXABI_1.3>
  400406:	68 09 00 00 00       	push   $0x9
  40040b:	e9 50 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400410 <__gxx_personality_v0@plt>:
  400410:	ff 25 3a 8c 00 00    	jmp    *0x8c3a(%rip)        # 409050 <__gxx_personality_v0@CXXABI_1.3>
  400416:	68 0a 00 00 00       	push   $0xa
  40041b:	e9 40 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400420 <__cxa_throw@plt>:
  400420:	ff 25 32 8c 00 00    	jmp    *0x8c32(%rip)        # 409058 <__cxa_throw@CXXABI_1.3>
  400426:	68 0b 00 00 00       	push   $0xb
  40042b:	e9 30 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400430 <ferror@plt>:
  400430:	ff 25 2a 8c 00 00    	jmp    *0x8c2a(%rip)        # 409060 <ferror@GLIBC_2.2.5>
  400436:	68 0c 00 00 00       	push   $0xc
  40043b:	e9 20 ff ff ff       	jmp    400360 <_init+0x24>

0000000000400440 <fwrite@plt>:
  400440:	ff 25 22 8c 00 00    	jmp    *0x8c22(%rip)        # 409068 <fwrite@GLIBC_2.2.5>
  400446:	68 0d 00 00 00       	push   $0xd
  40044b:	e9 10 ff ff ff       	jmp    400360 <_init+0x24>

Disassembly of section .text:

0000000000400480 <main.cold>:
  400480:	48 89 df             	mov    %rbx,%rdi
  400483:	e8 38 ff ff ff       	call   4003c0 <perror@plt>
  400488:	e9 d6 2d 00 00       	jmp    403263 <main+0x2863>
  40048d:	48 83 ea 01          	sub    $0x1,%rdx
  400491:	0f 84 34 01 00 00    	je     4005cb <main.cold+0x14b>
  400497:	c5 f8 77             	vzeroupper
  40049a:	e8 e1 fe ff ff       	call   400380 <__cxa_begin_catch@plt>
  40049f:	c6 85 81 c1 ff ff 01 	movb   $0x1,-0x3e7f(%rbp)
  4004a6:	e8 55 ff ff ff       	call   400400 <__cxa_end_catch@plt>
  4004ab:	48 8b 85 10 c1 ff ff 	mov    -0x3ef0(%rbp),%rax
  4004b2:	0f b6 b5 70 c1 ff ff 	movzbl -0x3e90(%rbp),%esi
  4004b9:	44 0f b7 8d 80 c1 ff ff 	movzwl -0x3e80(%rbp),%r9d
  4004c1:	0f b6 95 81 c1 ff ff 	movzbl -0x3e7f(%rbp),%edx
  4004c8:	48 89 85 80 bf ff ff 	mov    %rax,-0x4080(%rbp)
  4004cf:	84 db                	test   %bl,%bl
  4004d1:	0f 85 17 01 00 00    	jne    4005ee <main.cold+0x16e>
  4004d7:	44 0f b6 bd 98 bf ff ff 	movzbl -0x4068(%rbp),%r15d
  4004df:	45 84 ff             	test   %r15b,%r15b
  4004e2:	0f 85 2d 01 00 00    	jne    400615 <main.cold+0x195>
  4004e8:	b8 02 00 00 00       	mov    $0x2,%eax
  4004ed:	b9 01 00 00 00       	mov    $0x1,%ecx
  4004f2:	41 bf 01 00 00 00    	mov    $0x1,%r15d
  4004f8:	48 c7 85 b0 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4050(%rbp)
  400503:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  40050d:	83 f2 01             	xor    $0x1,%edx
  400510:	89 d7                	mov    %edx,%edi
  400512:	40 20 f7             	and    %sil,%dil
  400515:	40 88 bd 50 bf ff ff 	mov    %dil,-0x40b0(%rbp)
  40051c:	0f 84 73 01 00 00    	je     400695 <main.cold+0x215>
  400522:	48 8b b5 80 bf ff ff 	mov    -0x4080(%rbp),%rsi
  400529:	45 31 c0             	xor    %r8d,%r8d
  40052c:	4c 89 85 70 bf ff ff 	mov    %r8,-0x4090(%rbp)
  400533:	48 81 fe 00 08 00 00 	cmp    $0x800,%rsi
  40053a:	0f 84 50 03 00 00    	je     400890 <main.cold+0x410>
  400540:	48 81 fe 10 08 00 00 	cmp    $0x810,%rsi
  400547:	0f 84 55 03 00 00    	je     4008a2 <main.cold+0x422>
  40054d:	41 89 ff             	mov    %edi,%r15d
  400550:	b9 01 00 00 00       	mov    $0x1,%ecx
  400555:	ba 02 00 00 00       	mov    $0x2,%edx
  40055a:	48 c7 85 88 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4078(%rbp)
  400565:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  40056f:	e9 4c 14 00 00       	jmp    4019c0 <main+0xfc0>
  400574:	48 83 ea 01          	sub    $0x1,%rdx
  400578:	0f 85 da 02 00 00    	jne    400858 <main.cold+0x3d8>
  40057e:	c5 f8 77             	vzeroupper
  400581:	e8 fa fd ff ff       	call   400380 <__cxa_begin_catch@plt>
  400586:	b9 1a 00 00 00       	mov    $0x1a,%ecx
  40058b:	45 31 ed             	xor    %r13d,%r13d
  40058e:	48 89 c6             	mov    %rax,%rsi
  400591:	48 8d bd 90 c0 ff ff 	lea    -0x3f70(%rbp),%rdi
  400598:	31 db                	xor    %ebx,%ebx
  40059a:	f3 a5                	rep movsl (%rsi),(%rdi)
  40059c:	e8 5f fe ff ff       	call   400400 <__cxa_end_catch@plt>
  4005a1:	0f b6 85 f0 c0 ff ff 	movzbl -0x3f10(%rbp),%eax
  4005a8:	4c 89 ad 58 bf ff ff 	mov    %r13,-0x40a8(%rbp)
  4005af:	45 31 ed             	xor    %r13d,%r13d
  4005b2:	88 85 98 bf ff ff    	mov    %al,-0x4068(%rbp)
  4005b8:	48 8b 85 90 c0 ff ff 	mov    -0x3f70(%rbp),%rax
  4005bf:	48 89 85 78 bf ff ff 	mov    %rax,-0x4088(%rbp)
  4005c6:	e9 39 13 00 00       	jmp    401904 <main+0xf04>
  4005cb:	c5 f8 77             	vzeroupper
  4005ce:	e8 ad fd ff ff       	call   400380 <__cxa_begin_catch@plt>
  4005d3:	48 8d bd 10 c1 ff ff 	lea    -0x3ef0(%rbp),%rdi
  4005da:	b9 1a 00 00 00       	mov    $0x1a,%ecx
  4005df:	48 89 c6             	mov    %rax,%rsi
  4005e2:	f3 a5                	rep movsl (%rsi),(%rdi)
  4005e4:	e8 17 fe ff ff       	call   400400 <__cxa_end_catch@plt>
  4005e9:	e9 bd fe ff ff       	jmp    4004ab <main.cold+0x2b>
  4005ee:	41 89 df             	mov    %ebx,%r15d
  4005f1:	b8 03 00 00 00       	mov    $0x3,%eax
  4005f6:	b9 01 00 00 00       	mov    $0x1,%ecx
  4005fb:	48 c7 85 b0 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4050(%rbp)
  400606:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  400610:	e9 f8 fe ff ff       	jmp    40050d <main.cold+0x8d>
  400615:	48 8b 85 78 bf ff ff 	mov    -0x4088(%rbp),%rax
  40061c:	48 3d 00 08 00 00    	cmp    $0x800,%rax
  400622:	74 2c                	je     400650 <main.cold+0x1d0>
  400624:	48 3d 10 08 00 00    	cmp    $0x810,%rax
  40062a:	74 45                	je     400671 <main.cold+0x1f1>
  40062c:	48 c7 85 b0 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4050(%rbp)
  400637:	b8 02 00 00 00       	mov    $0x2,%eax
  40063c:	b9 01 00 00 00       	mov    $0x1,%ecx
  400641:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  40064b:	e9 bd fe ff ff       	jmp    40050d <main.cold+0x8d>
  400650:	45 31 db             	xor    %r11d,%r11d
  400653:	31 c0                	xor    %eax,%eax
  400655:	45 31 ff             	xor    %r15d,%r15d
  400658:	31 c9                	xor    %ecx,%ecx
  40065a:	48 c7 85 b0 bf ff ff a6 65 40 00 	movq   $0x4065a6,-0x4050(%rbp)
  400665:	44 89 9d f0 bf ff ff 	mov    %r11d,-0x4010(%rbp)
  40066c:	e9 9c fe ff ff       	jmp    40050d <main.cold+0x8d>
  400671:	45 31 d2             	xor    %r10d,%r10d
  400674:	45 31 ff             	xor    %r15d,%r15d
  400677:	b8 01 00 00 00       	mov    $0x1,%eax
  40067c:	31 c9                	xor    %ecx,%ecx
  40067e:	48 c7 85 b0 bf ff ff 94 65 40 00 	movq   $0x406594,-0x4050(%rbp)
  400689:	44 89 95 f0 bf ff ff 	mov    %r10d,-0x4010(%rbp)
  400690:	e9 78 fe ff ff       	jmp    40050d <main.cold+0x8d>
  400695:	31 d2                	xor    %edx,%edx
  400697:	b9 01 00 00 00       	mov    $0x1,%ecx
  40069c:	40 88 b5 50 bf ff ff 	mov    %sil,-0x40b0(%rbp)
  4006a3:	41 bf 01 00 00 00    	mov    $0x1,%r15d
  4006a9:	48 89 95 70 bf ff ff 	mov    %rdx,-0x4090(%rbp)
  4006b0:	ba 02 00 00 00       	mov    $0x2,%edx
  4006b5:	48 c7 85 88 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4078(%rbp)
  4006c0:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  4006ca:	e9 f1 12 00 00       	jmp    4019c0 <main+0xfc0>
  4006cf:	48 83 ea 01          	sub    $0x1,%rdx
  4006d3:	0f 84 34 01 00 00    	je     40080d <main.cold+0x38d>
  4006d9:	c5 f8 77             	vzeroupper
  4006dc:	e8 9f fc ff ff       	call   400380 <__cxa_begin_catch@plt>
  4006e1:	c6 85 81 c1 ff ff 01 	movb   $0x1,-0x3e7f(%rbp)
  4006e8:	e8 13 fd ff ff       	call   400400 <__cxa_end_catch@plt>
  4006ed:	0f b6 85 70 c1 ff ff 	movzbl -0x3e90(%rbp),%eax
  4006f4:	44 0f b7 95 80 c1 ff ff 	movzwl -0x3e80(%rbp),%r10d
  4006fc:	0f b6 95 81 c1 ff ff 	movzbl -0x3e7f(%rbp),%edx
  400703:	88 85 88 bf ff ff    	mov    %al,-0x4078(%rbp)
  400709:	48 8b 85 10 c1 ff ff 	mov    -0x3ef0(%rbp),%rax
  400710:	48 89 85 80 bf ff ff 	mov    %rax,-0x4080(%rbp)
  400717:	45 84 ed             	test   %r13b,%r13b
  40071a:	0f 85 10 01 00 00    	jne    400830 <main.cold+0x3b0>
  400720:	80 bd 70 bf ff ff 00 	cmpb   $0x0,-0x4090(%rbp)
  400727:	0f 85 c6 01 00 00    	jne    4008f3 <main.cold+0x473>
  40072d:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  400733:	b9 01 00 00 00       	mov    $0x1,%ecx
  400738:	b8 02 00 00 00       	mov    $0x2,%eax
  40073d:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  400747:	48 c7 85 98 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4068(%rbp)
  400752:	83 f2 01             	xor    $0x1,%edx
  400755:	22 95 88 bf ff ff    	and    -0x4078(%rbp),%dl
  40075b:	0f 84 f2 01 00 00    	je     400953 <main.cold+0x4d3>
  400761:	48 8b b5 80 bf ff ff 	mov    -0x4080(%rbp),%rsi
  400768:	48 81 fe 00 08 00 00 	cmp    $0x800,%rsi
  40076f:	0f 84 11 02 00 00    	je     400986 <main.cold+0x506>
  400775:	48 81 fe 10 08 00 00 	cmp    $0x810,%rsi
  40077c:	0f 84 25 02 00 00    	je     4009a7 <main.cold+0x527>
  400782:	45 31 c0             	xor    %r8d,%r8d
  400785:	b9 01 00 00 00       	mov    $0x1,%ecx
  40078a:	ba 02 00 00 00       	mov    $0x2,%edx
  40078f:	48 c7 85 90 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4070(%rbp)
  40079a:	4c 89 85 78 bf ff ff 	mov    %r8,-0x4088(%rbp)
  4007a1:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  4007a7:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  4007b1:	e9 d6 09 00 00       	jmp    40118c <main+0x78c>
  4007b6:	48 83 ea 01          	sub    $0x1,%rdx
  4007ba:	0f 85 f7 00 00 00    	jne    4008b7 <main.cold+0x437>
  4007c0:	c5 f8 77             	vzeroupper
  4007c3:	e8 b8 fb ff ff       	call   400380 <__cxa_begin_catch@plt>
  4007c8:	b9 1a 00 00 00       	mov    $0x1a,%ecx
  4007cd:	45 31 f6             	xor    %r14d,%r14d
  4007d0:	48 89 c6             	mov    %rax,%rsi
  4007d3:	48 8d bd 90 c0 ff ff 	lea    -0x3f70(%rbp),%rdi
  4007da:	45 31 ed             	xor    %r13d,%r13d
  4007dd:	f3 a5                	rep movsl (%rsi),(%rdi)
  4007df:	e8 1c fc ff ff       	call   400400 <__cxa_end_catch@plt>
  4007e4:	0f b6 85 f0 c0 ff ff 	movzbl -0x3f10(%rbp),%eax
  4007eb:	88 85 70 bf ff ff    	mov    %al,-0x4090(%rbp)
  4007f1:	48 8b 85 90 c0 ff ff 	mov    -0x3f70(%rbp),%rax
  4007f8:	48 89 85 68 bf ff ff 	mov    %rax,-0x4098(%rbp)
  4007ff:	31 c0                	xor    %eax,%eax
  400801:	48 89 85 40 bf ff ff 	mov    %rax,-0x40c0(%rbp)
  400808:	e9 c6 08 00 00       	jmp    4010d3 <main+0x6d3>
  40080d:	c5 f8 77             	vzeroupper
  400810:	e8 6b fb ff ff       	call   400380 <__cxa_begin_catch@plt>
  400815:	48 8d bd 10 c1 ff ff 	lea    -0x3ef0(%rbp),%rdi
  40081c:	b9 1a 00 00 00       	mov    $0x1a,%ecx
  400821:	48 89 c6             	mov    %rax,%rsi
  400824:	f3 a5                	rep movsl (%rsi),(%rdi)
  400826:	e8 d5 fb ff ff       	call   400400 <__cxa_end_catch@plt>
  40082b:	e9 bd fe ff ff       	jmp    4006ed <main.cold+0x26d>
  400830:	44 89 e9             	mov    %r13d,%ecx
  400833:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  400839:	b8 03 00 00 00       	mov    $0x3,%eax
  40083e:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  400848:	48 c7 85 98 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4068(%rbp)
  400853:	e9 fa fe ff ff       	jmp    400752 <main.cold+0x2d2>
  400858:	c5 f8 77             	vzeroupper
  40085b:	e8 20 fb ff ff       	call   400380 <__cxa_begin_catch@plt>
  400860:	31 db                	xor    %ebx,%ebx
  400862:	c6 85 01 c1 ff ff 01 	movb   $0x1,-0x3eff(%rbp)
  400869:	e8 92 fb ff ff       	call   400400 <__cxa_end_catch@plt>
  40086e:	41 bd 00 01 00 00    	mov    $0x100,%r13d
  400874:	48 89 9d 58 bf ff ff 	mov    %rbx,-0x40a8(%rbp)
  40087b:	48 89 9d 78 bf ff ff 	mov    %rbx,-0x4088(%rbp)
  400882:	31 db                	xor    %ebx,%ebx
  400884:	c6 85 98 bf ff ff 00 	movb   $0x0,-0x4068(%rbp)
  40088b:	e9 74 10 00 00       	jmp    401904 <main+0xf04>
  400890:	48 c7 85 88 bf ff ff a6 65 40 00 	movq   $0x4065a6,-0x4078(%rbp)
  40089b:	31 d2                	xor    %edx,%edx
  40089d:	e9 1e 11 00 00       	jmp    4019c0 <main+0xfc0>
  4008a2:	48 c7 85 88 bf ff ff 94 65 40 00 	movq   $0x406594,-0x4078(%rbp)
  4008ad:	ba 01 00 00 00       	mov    $0x1,%edx
  4008b2:	e9 09 11 00 00       	jmp    4019c0 <main+0xfc0>
  4008b7:	c5 f8 77             	vzeroupper
  4008ba:	e8 c1 fa ff ff       	call   400380 <__cxa_begin_catch@plt>
  4008bf:	45 31 ed             	xor    %r13d,%r13d
  4008c2:	c6 85 01 c1 ff ff 01 	movb   $0x1,-0x3eff(%rbp)
  4008c9:	e8 32 fb ff ff       	call   400400 <__cxa_end_catch@plt>
  4008ce:	31 c0                	xor    %eax,%eax
  4008d0:	4c 89 ad 40 bf ff ff 	mov    %r13,-0x40c0(%rbp)
  4008d7:	45 31 ed             	xor    %r13d,%r13d
  4008da:	48 89 85 68 bf ff ff 	mov    %rax,-0x4098(%rbp)
  4008e1:	41 be 00 01 00 00    	mov    $0x100,%r14d
  4008e7:	c6 85 70 bf ff ff 00 	movb   $0x0,-0x4090(%rbp)
  4008ee:	e9 e0 07 00 00       	jmp    4010d3 <main+0x6d3>
  4008f3:	48 8b 85 68 bf ff ff 	mov    -0x4098(%rbp),%rax
  4008fa:	48 3d 00 08 00 00    	cmp    $0x800,%rax
  400900:	74 30                	je     400932 <main.cold+0x4b2>
  400902:	48 3d 10 08 00 00    	cmp    $0x810,%rax
  400908:	0f 85 1f fe ff ff    	jne    40072d <main.cold+0x2ad>
  40090e:	45 31 c9             	xor    %r9d,%r9d
  400911:	31 c9                	xor    %ecx,%ecx
  400913:	45 31 c0             	xor    %r8d,%r8d
  400916:	b8 01 00 00 00       	mov    $0x1,%eax
  40091b:	44 89 8d b0 bf ff ff 	mov    %r9d,-0x4050(%rbp)
  400922:	48 c7 85 98 bf ff ff 94 65 40 00 	movq   $0x406594,-0x4068(%rbp)
  40092d:	e9 20 fe ff ff       	jmp    400752 <main.cold+0x2d2>
  400932:	45 31 db             	xor    %r11d,%r11d
  400935:	31 c9                	xor    %ecx,%ecx
  400937:	45 31 c0             	xor    %r8d,%r8d
  40093a:	31 c0                	xor    %eax,%eax
  40093c:	44 89 9d b0 bf ff ff 	mov    %r11d,-0x4050(%rbp)
  400943:	48 c7 85 98 bf ff ff a6 65 40 00 	movq   $0x4065a6,-0x4068(%rbp)
  40094e:	e9 ff fd ff ff       	jmp    400752 <main.cold+0x2d2>
  400953:	31 ff                	xor    %edi,%edi
  400955:	b9 01 00 00 00       	mov    $0x1,%ecx
  40095a:	ba 02 00 00 00       	mov    $0x2,%edx
  40095f:	48 c7 85 90 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4070(%rbp)
  40096a:	48 89 bd 78 bf ff ff 	mov    %rdi,-0x4088(%rbp)
  400971:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  400977:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  400981:	e9 06 08 00 00       	jmp    40118c <main+0x78c>
  400986:	31 f6                	xor    %esi,%esi
  400988:	88 95 88 bf ff ff    	mov    %dl,-0x4078(%rbp)
  40098e:	31 d2                	xor    %edx,%edx
  400990:	48 89 b5 78 bf ff ff 	mov    %rsi,-0x4088(%rbp)
  400997:	48 c7 85 90 bf ff ff a6 65 40 00 	movq   $0x4065a6,-0x4070(%rbp)
  4009a2:	e9 e5 07 00 00       	jmp    40118c <main+0x78c>
  4009a7:	88 95 88 bf ff ff    	mov    %dl,-0x4078(%rbp)
  4009ad:	31 d2                	xor    %edx,%edx
  4009af:	48 89 95 78 bf ff ff 	mov    %rdx,-0x4088(%rbp)
  4009b6:	ba 01 00 00 00       	mov    $0x1,%edx
  4009bb:	48 c7 85 90 bf ff ff 94 65 40 00 	movq   $0x406594,-0x4070(%rbp)
  4009c6:	e9 c1 07 00 00       	jmp    40118c <main+0x78c>
  4009cb:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  4009d5:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  4009df:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  4009e9:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  4009f3:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  4009fd:	0f 1f 00             	nopl   (%rax)

0000000000400a00 <main>:
  400a00:	4c 8d 54 24 08       	lea    0x8(%rsp),%r10
  400a05:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
  400a09:	41 ff 72 f8          	push   -0x8(%r10)
  400a0d:	55                   	push   %rbp
  400a0e:	48 89 e5             	mov    %rsp,%rbp
  400a11:	41 57                	push   %r15
  400a13:	41 56                	push   %r14
  400a15:	48 8d 95 0c c0 ff ff 	lea    -0x3ff4(%rbp),%rdx
  400a1c:	48 8d 85 04 c0 ff ff 	lea    -0x3ffc(%rbp),%rax
  400a23:	41 55                	push   %r13
  400a25:	41 54                	push   %r12
  400a27:	41 52                	push   %r10
  400a29:	53                   	push   %rbx
  400a2a:	48 8d 9d 08 c0 ff ff 	lea    -0x3ff8(%rbp),%rbx
  400a31:	c4 e1 f9 6e db       	vmovq  %rbx,%xmm3
  400a36:	48 8d 9d 00 c0 ff ff 	lea    -0x4000(%rbp),%rbx
  400a3d:	c4 e3 e1 22 c2 01    	vpinsrq $0x1,%rdx,%xmm3,%xmm0
  400a43:	c4 e1 f9 6e db       	vmovq  %rbx,%xmm3
  400a48:	bb 80 65 40 00       	mov    $0x406580,%ebx
  400a4d:	c4 e3 e1 22 c8 01    	vpinsrq $0x1,%rax,%xmm3,%xmm1
  400a53:	48 81 ec 40 41 00 00 	sub    $0x4140,%rsp
  400a5a:	c4 e3 75 18 d8 01    	vinsertf128 $0x1,%xmm0,%ymm1,%ymm3
  400a60:	c5 fd 7f 9d d0 bf ff ff 	vmovdqa %ymm3,-0x4030(%rbp)
  400a68:	83 ff 01             	cmp    $0x1,%edi
  400a6b:	7e 04                	jle    400a71 <main+0x71>
  400a6d:	48 8b 5e 08          	mov    0x8(%rsi),%rbx
  400a71:	be b1 65 40 00       	mov    $0x4065b1,%esi
  400a76:	48 89 df             	mov    %rbx,%rdi
  400a79:	c5 f8 77             	vzeroupper
  400a7c:	e8 5f f9 ff ff       	call   4003e0 <fopen@plt>
  400a81:	48 89 85 38 bf ff ff 	mov    %rax,-0x40c8(%rbp)
  400a88:	48 85 c0             	test   %rax,%rax
  400a8b:	0f 84 ef f9 ff ff    	je     400480 <main.cold>
  400a91:	48 89 c1             	mov    %rax,%rcx
  400a94:	ba b5 00 00 00       	mov    $0xb5,%edx
  400a99:	be 01 00 00 00       	mov    $0x1,%esi
  400a9e:	45 31 ed             	xor    %r13d,%r13d
  400aa1:	bf f0 65 40 00       	mov    $0x4065f0,%edi
  400aa6:	4c 8d a5 90 c3 ff ff 	lea    -0x3c70(%rbp),%r12
  400aad:	e8 8e f9 ff ff       	call   400440 <fwrite@plt>
  400ab2:	c5 f9 6f 05 a6 63 00 00 	vmovdqa 0x63a6(%rip),%xmm0        # 406e60 <typeinfo for Boundary+0x50>
  400aba:	48 8b 05 1f 64 00 00 	mov    0x641f(%rip),%rax        # 406ee0 <typeinfo for Boundary+0xd0>
  400ac1:	c7 85 00 c0 ff ff 00 02 00 00 	movl   $0x200,-0x4000(%rbp)
  400acb:	c5 fd 6f 9d d0 bf ff ff 	vmovdqa -0x4030(%rbp),%ymm3
  400ad3:	c7 85 04 c0 ff ff 00 08 00 00 	movl   $0x800,-0x3ffc(%rbp)
  400add:	48 89 85 40 c0 ff ff 	mov    %rax,-0x3fc0(%rbp)
  400ae4:	48 8d 85 90 c1 ff ff 	lea    -0x3e70(%rbp),%rax
  400aeb:	c5 f9 7f 85 30 c0 ff ff 	vmovdqa %xmm0,-0x3fd0(%rbp)
  400af3:	c5 fd 6f 05 05 64 00 00 	vmovdqa 0x6405(%rip),%ymm0        # 406f00 <typeinfo for Boundary+0xf0>
  400afb:	48 89 85 c0 bf ff ff 	mov    %rax,-0x4040(%rbp)
  400b02:	48 8d 85 d0 cf ff ff 	lea    -0x3030(%rbp),%rax
  400b09:	48 89 85 a8 bf ff ff 	mov    %rax,-0x4058(%rbp)
  400b10:	48 8d 85 50 c6 ff ff 	lea    -0x39b0(%rbp),%rax
  400b17:	c5 fd 7f 85 50 c0 ff ff 	vmovdqa %ymm0,-0x3fb0(%rbp)
  400b1f:	c5 f9 6f 05 49 63 00 00 	vmovdqa 0x6349(%rip),%xmm0        # 406e70 <typeinfo for Boundary+0x60>
  400b27:	48 89 85 c8 bf ff ff 	mov    %rax,-0x4038(%rbp)
  400b2e:	48 8d 85 d0 df ff ff 	lea    -0x2030(%rbp),%rax
  400b35:	48 89 85 b8 bf ff ff 	mov    %rax,-0x4048(%rbp)
  400b3c:	b8 b9 79 37 9e       	mov    $0x9e3779b9,%eax
  400b41:	c5 f9 7f 85 70 c0 ff ff 	vmovdqa %xmm0,-0x3f90(%rbp)
  400b49:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
  400b4d:	c5 fe 7f 1d 4b 85 00 00 	vmovdqu %ymm3,0x854b(%rip)        # 4090a0 <full_before_cache>
  400b55:	c5 fe 7f 1d 63 85 00 00 	vmovdqu %ymm3,0x8563(%rip)        # 4090c0 <full_after_cache>
  400b5d:	c5 f9 6e d8          	vmovd  %eax,%xmm3
  400b61:	c5 f9 7f 85 10 c0 ff ff 	vmovdqa %xmm0,-0x3ff0(%rbp)
  400b69:	c5 f9 70 db 00       	vpshufd $0x0,%xmm3,%xmm3
  400b6e:	c5 f9 7f 85 20 c0 ff ff 	vmovdqa %xmm0,-0x3fe0(%rbp)
  400b76:	c5 f9 76 c0          	vpcmpeqd %xmm0,%xmm0,%xmm0
  400b7a:	c7 85 08 c0 ff ff 10 08 00 00 	movl   $0x810,-0x3ff8(%rbp)
  400b84:	c7 85 0c c0 ff ff 20 08 00 00 	movl   $0x820,-0x3ff4(%rbp)
  400b8e:	c7 85 30 bf ff ff 00 00 00 00 	movl   $0x0,-0x40d0(%rbp)
  400b98:	c7 85 34 bf ff ff 00 00 00 00 	movl   $0x0,-0x40cc(%rbp)
  400ba2:	c7 85 48 bf ff ff 00 00 00 00 	movl   $0x0,-0x40b8(%rbp)
  400bac:	c7 85 2c bf ff ff 00 00 00 00 	movl   $0x0,-0x40d4(%rbp)
  400bb6:	c7 85 a4 bf ff ff 00 00 00 00 	movl   $0x0,-0x405c(%rbp)
  400bc0:	c5 f9 7f 9d d0 bf ff ff 	vmovdqa %xmm3,-0x4030(%rbp)
  400bc8:	c5 e1 72 d0 1f       	vpsrld $0x1f,%xmm0,%xmm3
  400bcd:	c5 f9 7f 9d f0 bf ff ff 	vmovdqa %xmm3,-0x4010(%rbp)
  400bd5:	41 83 fd 14          	cmp    $0x14,%r13d
  400bd9:	43 8d 44 ed 00       	lea    0x0(%r13,%r13,8),%eax
  400bde:	ba cd cc cc cc       	mov    $0xcccccccd,%edx
  400be3:	44 89 ad 4c bf ff ff 	mov    %r13d,-0x40b4(%rbp)
  400bea:	19 f6                	sbb    %esi,%esi
  400bec:	8d 1c 85 00 00 00 00 	lea    0x0(,%rax,4),%ebx
  400bf3:	c4 c1 79 6e dd       	vmovd  %r13d,%xmm3
  400bf8:	f7 d6                	not    %esi
  400bfa:	c5 f9 70 db 00       	vpshufd $0x0,%xmm3,%xmm3
  400bff:	41 89 de             	mov    %ebx,%r14d
  400c02:	c5 f9 7f 9d f0 be ff ff 	vmovdqa %xmm3,-0x4110(%rbp)
  400c0a:	83 e6 07             	and    $0x7,%esi
  400c0d:	89 f0                	mov    %esi,%eax
  400c0f:	41 89 f7             	mov    %esi,%r15d
  400c12:	c1 e0 07             	shl    $0x7,%eax
  400c15:	42 8d 0c 28          	lea    (%rax,%r13,1),%ecx
  400c19:	48 89 c8             	mov    %rcx,%rax
  400c1c:	48 0f af ca          	imul   %rdx,%rcx
  400c20:	89 c7                	mov    %eax,%edi
  400c22:	48 c1 e9 24          	shr    $0x24,%rcx
  400c26:	8d 0c 89             	lea    (%rcx,%rcx,4),%ecx
  400c29:	c1 e1 02             	shl    $0x2,%ecx
  400c2c:	29 cf                	sub    %ecx,%edi
  400c2e:	8d 0c 30             	lea    (%rax,%rsi,1),%ecx
  400c31:	48 89 c8             	mov    %rcx,%rax
  400c34:	48 0f af ca          	imul   %rdx,%rcx
  400c38:	89 bd e0 be ff ff    	mov    %edi,-0x4120(%rbp)
  400c3e:	89 c7                	mov    %eax,%edi
  400c40:	48 c1 e9 24          	shr    $0x24,%rcx
  400c44:	8d 0c 89             	lea    (%rcx,%rcx,4),%ecx
  400c47:	c1 e1 02             	shl    $0x2,%ecx
  400c4a:	29 cf                	sub    %ecx,%edi
  400c4c:	8d 0c 30             	lea    (%rax,%rsi,1),%ecx
  400c4f:	48 89 c8             	mov    %rcx,%rax
  400c52:	48 0f af ca          	imul   %rdx,%rcx
  400c56:	89 bd d0 be ff ff    	mov    %edi,-0x4130(%rbp)
  400c5c:	89 c7                	mov    %eax,%edi
  400c5e:	48 c1 e9 24          	shr    $0x24,%rcx
  400c62:	8d 0c 89             	lea    (%rcx,%rcx,4),%ecx
  400c65:	c1 e1 02             	shl    $0x2,%ecx
  400c68:	29 cf                	sub    %ecx,%edi
  400c6a:	8d 0c 30             	lea    (%rax,%rsi,1),%ecx
  400c6d:	48 89 c8             	mov    %rcx,%rax
  400c70:	48 0f af ca          	imul   %rdx,%rcx
  400c74:	89 bd c8 be ff ff    	mov    %edi,-0x4138(%rbp)
  400c7a:	89 c7                	mov    %eax,%edi
  400c7c:	48 c1 e9 24          	shr    $0x24,%rcx
  400c80:	8d 0c 89             	lea    (%rcx,%rcx,4),%ecx
  400c83:	c1 e1 02             	shl    $0x2,%ecx
  400c86:	29 cf                	sub    %ecx,%edi
  400c88:	8d 0c 30             	lea    (%rax,%rsi,1),%ecx
  400c8b:	48 0f af d1          	imul   %rcx,%rdx
  400c8f:	48 89 c8             	mov    %rcx,%rax
  400c92:	89 bd c0 be ff ff    	mov    %edi,-0x4140(%rbp)
  400c98:	48 c1 ea 24          	shr    $0x24,%rdx
  400c9c:	8d 14 92             	lea    (%rdx,%rdx,4),%edx
  400c9f:	c1 e2 02             	shl    $0x2,%edx
  400ca2:	29 d0                	sub    %edx,%eax
  400ca4:	ba 06 00 00 00       	mov    $0x6,%edx
  400ca9:	89 85 00 bf ff ff    	mov    %eax,-0x4100(%rbp)
  400caf:	44 89 e8             	mov    %r13d,%eax
  400cb2:	41 83 c5 01          	add    $0x1,%r13d
  400cb6:	35 b9 79 37 9e       	xor    $0x9e3779b9,%eax
  400cbb:	89 85 bc be ff ff    	mov    %eax,-0x4144(%rbp)
  400cc1:	48 89 d0             	mov    %rdx,%rax
  400cc4:	44 89 b5 28 bf ff ff 	mov    %r14d,-0x40d8(%rbp)
  400ccb:	48 8b 9d a8 bf ff ff 	mov    -0x4058(%rbp),%rbx
  400cd2:	48 f7 d8             	neg    %rax
  400cd5:	44 89 b5 b8 be ff ff 	mov    %r14d,-0x4148(%rbp)
  400cdc:	48 c1 e0 03          	shl    $0x3,%rax
  400ce0:	44 89 ad b0 be ff ff 	mov    %r13d,-0x4150(%rbp)
  400ce7:	48 89 85 08 bf ff ff 	mov    %rax,-0x40f8(%rbp)
  400cee:	48 8d 85 30 c0 ff ff 	lea    -0x3fd0(%rbp),%rax
  400cf5:	48 89 85 50 bf ff ff 	mov    %rax,-0x40b0(%rbp)
  400cfc:	48 89 95 a8 be ff ff 	mov    %rdx,-0x4158(%rbp)
  400d03:	c5 fd 6f 1d 15 62 00 00 	vmovdqa 0x6215(%rip),%ymm3        # 406f20 <typeinfo for Boundary+0x110>
  400d0b:	48 8b 85 50 bf ff ff 	mov    -0x40b0(%rbp),%rax
  400d12:	b9 98 00 00 00       	mov    $0x98,%ecx
  400d17:	48 8b bd c0 bf ff ff 	mov    -0x4040(%rbp),%rdi
  400d1e:	c5 fd 7f 9d d0 ef ff ff 	vmovdqa %ymm3,-0x1030(%rbp)
  400d26:	c5 fd 6f 1d 12 62 00 00 	vmovdqa 0x6212(%rip),%ymm3        # 406f40 <typeinfo for Boundary+0x130>
  400d2e:	8b 00                	mov    (%rax),%eax
  400d30:	c5 fd 7f 9d f0 ef ff ff 	vmovdqa %ymm3,-0x1010(%rbp)
  400d38:	c5 f9 6f 1d 40 61 00 00 	vmovdqa 0x6140(%rip),%xmm3        # 406e80 <typeinfo for Boundary+0x70>
  400d40:	89 85 64 bf ff ff    	mov    %eax,-0x409c(%rbp)
  400d46:	31 c0                	xor    %eax,%eax
  400d48:	f3 48 ab             	rep stos %rax,(%rdi)
  400d4b:	c5 f9 7f 9d 10 f0 ff ff 	vmovdqa %xmm3,-0xff0(%rbp)
  400d53:	83 bd 4c bf ff ff 27 	cmpl   $0x27,-0x40b4(%rbp)
  400d5a:	0f 86 23 12 00 00    	jbe    401f83 <main+0x1583>
  400d60:	8b 85 bc be ff ff    	mov    -0x4144(%rbp),%eax
  400d66:	48 8d 8d 10 c4 ff ff 	lea    -0x3bf0(%rbp),%rcx
  400d6d:	0f 1f 00             	nopl   (%rax)
  400d70:	89 c2                	mov    %eax,%edx
  400d72:	48 83 c1 10          	add    $0x10,%rcx
  400d76:	48 8d bd 10 c6 ff ff 	lea    -0x39f0(%rbp),%rdi
  400d7d:	c1 e2 0d             	shl    $0xd,%edx
  400d80:	31 d0                	xor    %edx,%eax
  400d82:	89 c2                	mov    %eax,%edx
  400d84:	c1 ea 11             	shr    $0x11,%edx
  400d87:	31 c2                	xor    %eax,%edx
  400d89:	89 d0                	mov    %edx,%eax
  400d8b:	c1 e0 05             	shl    $0x5,%eax
  400d8e:	31 d0                	xor    %edx,%eax
  400d90:	89 c6                	mov    %eax,%esi
  400d92:	89 41 f0             	mov    %eax,-0x10(%rcx)
  400d95:	c1 e6 0d             	shl    $0xd,%esi
  400d98:	31 c6                	xor    %eax,%esi
  400d9a:	89 f2                	mov    %esi,%edx
  400d9c:	c1 ea 11             	shr    $0x11,%edx
  400d9f:	31 f2                	xor    %esi,%edx
  400da1:	89 d0                	mov    %edx,%eax
  400da3:	c1 e0 05             	shl    $0x5,%eax
  400da6:	31 d0                	xor    %edx,%eax
  400da8:	89 c2                	mov    %eax,%edx
  400daa:	89 41 f4             	mov    %eax,-0xc(%rcx)
  400dad:	c1 e2 0d             	shl    $0xd,%edx
  400db0:	31 d0                	xor    %edx,%eax
  400db2:	89 c2                	mov    %eax,%edx
  400db4:	c1 ea 11             	shr    $0x11,%edx
  400db7:	31 c2                	xor    %eax,%edx
  400db9:	89 d0                	mov    %edx,%eax
  400dbb:	c1 e0 05             	shl    $0x5,%eax
  400dbe:	31 d0                	xor    %edx,%eax
  400dc0:	89 c2                	mov    %eax,%edx
  400dc2:	89 41 f8             	mov    %eax,-0x8(%rcx)
  400dc5:	c1 e2 0d             	shl    $0xd,%edx
  400dc8:	31 d0                	xor    %edx,%eax
  400dca:	89 c2                	mov    %eax,%edx
  400dcc:	c1 ea 11             	shr    $0x11,%edx
  400dcf:	31 c2                	xor    %eax,%edx
  400dd1:	89 d0                	mov    %edx,%eax
  400dd3:	c1 e0 05             	shl    $0x5,%eax
  400dd6:	31 d0                	xor    %edx,%eax
  400dd8:	89 41 fc             	mov    %eax,-0x4(%rcx)
  400ddb:	48 39 f9             	cmp    %rdi,%rcx
  400dde:	75 90                	jne    400d70 <main+0x370>
  400de0:	89 c2                	mov    %eax,%edx
  400de2:	c1 e2 0d             	shl    $0xd,%edx
  400de5:	31 c2                	xor    %eax,%edx
  400de7:	89 d0                	mov    %edx,%eax
  400de9:	c1 e8 11             	shr    $0x11,%eax
  400dec:	31 d0                	xor    %edx,%eax
  400dee:	41 89 c1             	mov    %eax,%r9d
  400df1:	41 c1 e1 05          	shl    $0x5,%r9d
  400df5:	41 31 c1             	xor    %eax,%r9d
  400df8:	44 89 ca             	mov    %r9d,%edx
  400dfb:	c1 e2 0d             	shl    $0xd,%edx
  400dfe:	44 31 ca             	xor    %r9d,%edx
  400e01:	89 d0                	mov    %edx,%eax
  400e03:	c1 e8 11             	shr    $0x11,%eax
  400e06:	31 d0                	xor    %edx,%eax
  400e08:	41 89 c0             	mov    %eax,%r8d
  400e0b:	41 c1 e0 05          	shl    $0x5,%r8d
  400e0f:	41 31 c0             	xor    %eax,%r8d
  400e12:	44 89 c2             	mov    %r8d,%edx
  400e15:	c1 e2 0d             	shl    $0xd,%edx
  400e18:	44 31 c2             	xor    %r8d,%edx
  400e1b:	89 d0                	mov    %edx,%eax
  400e1d:	c1 e8 11             	shr    $0x11,%eax
  400e20:	31 d0                	xor    %edx,%eax
  400e22:	89 c6                	mov    %eax,%esi
  400e24:	c1 e6 05             	shl    $0x5,%esi
  400e27:	31 c6                	xor    %eax,%esi
  400e29:	89 f2                	mov    %esi,%edx
  400e2b:	c1 e2 0d             	shl    $0xd,%edx
  400e2e:	31 f2                	xor    %esi,%edx
  400e30:	89 d0                	mov    %edx,%eax
  400e32:	c1 e8 11             	shr    $0x11,%eax
  400e35:	31 d0                	xor    %edx,%eax
  400e37:	89 c2                	mov    %eax,%edx
  400e39:	c1 e2 05             	shl    $0x5,%edx
  400e3c:	31 c2                	xor    %eax,%edx
  400e3e:	89 d1                	mov    %edx,%ecx
  400e40:	c1 e1 0d             	shl    $0xd,%ecx
  400e43:	31 d1                	xor    %edx,%ecx
  400e45:	89 c8                	mov    %ecx,%eax
  400e47:	c1 e8 11             	shr    $0x11,%eax
  400e4a:	31 c8                	xor    %ecx,%eax
  400e4c:	41 89 c2             	mov    %eax,%r10d
  400e4f:	41 c1 e2 05          	shl    $0x5,%r10d
  400e53:	41 31 c2             	xor    %eax,%r10d
  400e56:	c5 f9 6f 9d f0 be ff ff 	vmovdqa -0x4110(%rbp),%xmm3
  400e5e:	48 8b 85 c0 bf ff ff 	mov    -0x4040(%rbp),%rax
  400e65:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  400e69:	c5 e1 fe 15 1f 60 00 00 	vpaddd 0x601f(%rip),%xmm3,%xmm2        # 406e90 <typeinfo for Boundary+0x80>
  400e71:	0f 1f 40 00          	nopl   0x0(%rax)
  400e75:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  400e80:	c5 f9 72 f1 02       	vpslld $0x2,%xmm1,%xmm0
  400e85:	48 83 c0 10          	add    $0x10,%rax
  400e89:	c5 f1 fe 8d f0 bf ff ff 	vpaddd -0x4010(%rbp),%xmm1,%xmm1
  400e91:	c5 f9 fe c2          	vpaddd %xmm2,%xmm0,%xmm0
  400e95:	c4 e2 79 40 85 d0 bf ff ff 	vpmulld -0x4030(%rbp),%xmm0,%xmm0
  400e9e:	c5 f9 7f 40 f0       	vmovdqa %xmm0,-0x10(%rax)
  400ea3:	4c 39 e0             	cmp    %r12,%rax
  400ea6:	75 d8                	jne    400e80 <main+0x480>
  400ea8:	48 8b 85 08 bf ff ff 	mov    -0x40f8(%rbp),%rax
  400eaf:	b9 00 02 00 00       	mov    $0x200,%ecx
  400eb4:	8b bc 05 80 c0 ff ff 	mov    -0x3f80(%rbp,%rax,1),%edi
  400ebb:	8b 84 05 84 c0 ff ff 	mov    -0x3f7c(%rbp,%rax,1),%eax
  400ec2:	89 bd 58 bf ff ff    	mov    %edi,-0x40a8(%rbp)
  400ec8:	89 bd d0 c2 ff ff    	mov    %edi,-0x3d30(%rbp)
  400ece:	48 89 df             	mov    %rbx,%rdi
  400ed1:	89 85 60 bf ff ff    	mov    %eax,-0x40a0(%rbp)
  400ed7:	89 85 e0 c2 ff ff    	mov    %eax,-0x3d20(%rbp)
  400edd:	31 c0                	xor    %eax,%eax
  400edf:	f3 48 ab             	rep stos %rax,(%rdi)
  400ee2:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  400eea:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  400ef5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  400f00:	89 c1                	mov    %eax,%ecx
  400f02:	89 c7                	mov    %eax,%edi
  400f04:	c1 e9 02             	shr    $0x2,%ecx
  400f07:	c1 ef 04             	shr    $0x4,%edi
  400f0a:	83 e1 03             	and    $0x3,%ecx
  400f0d:	48 8d 8c b9 a0 00 00 00 	lea    0xa0(%rcx,%rdi,4),%rcx
  400f15:	8b 8c 8d 90 c1 ff ff 	mov    -0x3e70(%rbp,%rcx,4),%ecx
  400f1c:	89 0c 03             	mov    %ecx,(%rbx,%rax,1)
  400f1f:	48 83 c0 04          	add    $0x4,%rax
  400f23:	48 3d 00 02 00 00    	cmp    $0x200,%rax
  400f29:	75 d5                	jne    400f00 <main+0x500>
  400f2b:	8b 8d 60 bf ff ff    	mov    -0x40a0(%rbp),%ecx
  400f31:	8b bd 64 bf ff ff    	mov    -0x409c(%rbp),%edi
  400f37:	89 b5 18 c6 ff ff    	mov    %esi,-0x39e8(%rbp)
  400f3d:	c5 f9 6f 85 10 c5 ff ff 	vmovdqa -0x3af0(%rbp),%xmm0
  400f45:	48 c7 85 d0 c1 ff ff 00 04 00 00 	movq   $0x400,-0x3e30(%rbp)
  400f50:	89 bc 0d 30 d0 ff ff 	mov    %edi,-0x2fd0(%rbp,%rcx,1)
  400f57:	8b bd 58 bf ff ff    	mov    -0x40a8(%rbp),%edi
  400f5d:	c5 f9 7f 85 d0 d1 ff ff 	vmovdqa %xmm0,-0x2e30(%rbp)
  400f65:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
  400f69:	48 8b b5 c0 bf ff ff 	mov    -0x4040(%rbp),%rsi
  400f70:	48 89 8d e0 c1 ff ff 	mov    %rcx,-0x3e20(%rbp)
  400f77:	48 89 bd f0 c1 ff ff 	mov    %rdi,-0x3e10(%rbp)
  400f7e:	48 8b bd c8 bf ff ff 	mov    -0x4038(%rbp),%rdi
  400f85:	48 c7 85 00 c2 ff ff 00 00 00 00 	movq   $0x0,-0x3e00(%rbp)
  400f90:	48 c7 85 10 c2 ff ff 01 00 00 00 	movq   $0x1,-0x3df0(%rbp)
  400f9b:	48 c7 85 20 c2 ff ff 00 03 00 00 	movq   $0x300,-0x3de0(%rbp)
  400fa6:	48 c7 85 00 c3 ff ff 00 03 00 00 	movq   $0x300,-0x3d00(%rbp)
  400fb1:	48 c7 85 60 c3 ff ff 00 10 00 00 	movq   $0x1000,-0x3ca0(%rbp)
  400fbc:	48 c7 85 f0 c2 ff ff 00 00 00 00 	movq   $0x0,-0x3d10(%rbp)
  400fc7:	44 89 8d 10 c6 ff ff 	mov    %r9d,-0x39f0(%rbp)
  400fce:	44 89 85 14 c6 ff ff 	mov    %r8d,-0x39ec(%rbp)
  400fd5:	89 95 1c c6 ff ff    	mov    %edx,-0x39e4(%rbp)
  400fdb:	44 89 95 20 c6 ff ff 	mov    %r10d,-0x39e0(%rbp)
  400fe2:	c7 85 24 c6 ff ff 00 00 a0 3f 	movl   $0x3fa00000,-0x39dc(%rbp)
  400fec:	c7 84 0d 40 d0 ff ff 00 00 00 00 	movl   $0x0,-0x2fc0(%rbp,%rcx,1)
  400ff7:	c7 84 0d 48 d0 ff ff 00 00 00 00 	movl   $0x0,-0x2fb8(%rbp,%rcx,1)
  401002:	c7 84 0d 50 d0 ff ff 04 03 00 00 	movl   $0x304,-0x2fb0(%rbp,%rcx,1)
  40100d:	b9 98 00 00 00       	mov    $0x98,%ecx
  401012:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  401015:	48 8d b5 90 c1 ff ff 	lea    -0x3e70(%rbp),%rsi
  40101c:	48 8d bd 10 cb ff ff 	lea    -0x34f0(%rbp),%rdi
  401023:	b9 98 00 00 00       	mov    $0x98,%ecx
  401028:	48 89 b5 c0 bf ff ff 	mov    %rsi,-0x4040(%rbp)
  40102f:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  401032:	48 8b bd b8 bf ff ff 	mov    -0x4048(%rbp),%rdi
  401039:	48 89 de             	mov    %rbx,%rsi
  40103c:	48 89 c1             	mov    %rax,%rcx
  40103f:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  401042:	48 8d bd d0 ef ff ff 	lea    -0x1030(%rbp),%rdi
  401049:	48 89 de             	mov    %rbx,%rsi
  40104c:	48 89 c1             	mov    %rax,%rcx
  40104f:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  401052:	48 8d 85 d0 df ff ff 	lea    -0x2030(%rbp),%rax
  401059:	c5 fd 7f 85 d0 c0 ff ff 	vmovdqa %ymm0,-0x3f30(%rbp)
  401061:	48 89 85 b8 bf ff ff 	mov    %rax,-0x4048(%rbp)
  401068:	48 89 05 21 80 00 00 	mov    %rax,0x8021(%rip)        # 409090 <g_ee_main_mem>
  40106f:	48 8d 85 50 c6 ff ff 	lea    -0x39b0(%rbp),%rax
  401076:	48 89 85 c8 bf ff ff 	mov    %rax,-0x4038(%rbp)
  40107d:	48 89 c7             	mov    %rax,%rdi
  401080:	c5 fd 7f 85 90 c0 ff ff 	vmovdqa %ymm0,-0x3f70(%rbp)
  401088:	c5 fd 7f 85 b0 c0 ff ff 	vmovdqa %ymm0,-0x3f50(%rbp)
  401090:	c5 fe 7f 85 e8 c0 ff ff 	vmovdqu %ymm0,-0x3f18(%rbp)
  401098:	c5 f8 77             	vzeroupper
  40109b:	e8 d0 23 00 00       	call   403470 <full_before_execute>
  4010a0:	48 89 85 40 bf ff ff 	mov    %rax,-0x40c0(%rbp)
  4010a7:	41 be 01 00 00 00    	mov    $0x1,%r14d
  4010ad:	41 bd 01 00 00 00    	mov    $0x1,%r13d
  4010b3:	48 89 85 f8 c0 ff ff 	mov    %rax,-0x3f08(%rbp)
  4010ba:	c6 85 00 c1 ff ff 01 	movb   $0x1,-0x3f00(%rbp)
  4010c1:	48 c7 85 68 bf ff ff 00 00 00 00 	movq   $0x0,-0x4098(%rbp)
  4010cc:	c6 85 70 bf ff ff 00 	movb   $0x0,-0x4090(%rbp)
  4010d3:	48 8d 85 d0 ef ff ff 	lea    -0x1030(%rbp),%rax
  4010da:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
  4010de:	48 8d bd 10 cb ff ff 	lea    -0x34f0(%rbp),%rdi
  4010e5:	48 89 05 a4 7f 00 00 	mov    %rax,0x7fa4(%rip)        # 409090 <g_ee_main_mem>
  4010ec:	c5 fd 7f 85 50 c1 ff ff 	vmovdqa %ymm0,-0x3eb0(%rbp)
  4010f4:	c5 fd 7f 85 10 c1 ff ff 	vmovdqa %ymm0,-0x3ef0(%rbp)
  4010fc:	c5 fd 7f 85 30 c1 ff ff 	vmovdqa %ymm0,-0x3ed0(%rbp)
  401104:	c5 fe 7f 85 68 c1 ff ff 	vmovdqu %ymm0,-0x3e98(%rbp)
  40110c:	c5 f8 77             	vzeroupper
  40110f:	e8 6c 36 00 00       	call   404780 <full_after_execute>
  401114:	48 89 85 78 bf ff ff 	mov    %rax,-0x4088(%rbp)
  40111b:	48 89 85 78 c1 ff ff 	mov    %rax,-0x3e88(%rbp)
  401122:	c6 85 80 c1 ff ff 01 	movb   $0x1,-0x3e80(%rbp)
  401129:	45 84 ed             	test   %r13b,%r13b
  40112c:	0f 85 49 10 00 00    	jne    40217b <main+0x177b>
  401132:	80 bd 70 bf ff ff 00 	cmpb   $0x0,-0x4090(%rbp)
  401139:	0f 85 50 0f 00 00    	jne    40208f <main+0x168f>
  40113f:	c6 85 88 bf ff ff 00 	movb   $0x0,-0x4078(%rbp)
  401146:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  40114c:	b9 01 00 00 00       	mov    $0x1,%ecx
  401151:	ba 03 00 00 00       	mov    $0x3,%edx
  401156:	48 c7 85 98 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4068(%rbp)
  401161:	b8 02 00 00 00       	mov    $0x2,%eax
  401166:	41 ba 01 00 00 00    	mov    $0x1,%r10d
  40116c:	48 c7 85 90 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4070(%rbp)
  401177:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  401181:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  40118c:	48 8b bd c8 bf ff ff 	mov    -0x4038(%rbp),%rdi
  401193:	83 84 95 20 c0 ff ff 01 	addl   $0x1,-0x3fe0(%rbp,%rdx,4)
  40119b:	48 8d b5 10 cb ff ff 	lea    -0x34f0(%rbp),%rsi
  4011a2:	ba c0 04 00 00       	mov    $0x4c0,%edx
  4011a7:	44 89 85 10 bf ff ff 	mov    %r8d,-0x40f0(%rbp)
  4011ae:	88 8d 18 bf ff ff    	mov    %cl,-0x40e8(%rbp)
  4011b4:	83 84 85 10 c0 ff ff 01 	addl   $0x1,-0x3ff0(%rbp,%rax,4)
  4011bc:	44 89 95 1c bf ff ff 	mov    %r10d,-0x40e4(%rbp)
  4011c3:	e8 c8 f1 ff ff       	call   400390 <memcmp@plt>
  4011c8:	48 8b bd b8 bf ff ff 	mov    -0x4048(%rbp),%rdi
  4011cf:	ba 00 10 00 00       	mov    $0x1000,%edx
  4011d4:	48 8d b5 d0 ef ff ff 	lea    -0x1030(%rbp),%rsi
  4011db:	85 c0                	test   %eax,%eax
  4011dd:	89 85 a0 bf ff ff    	mov    %eax,-0x4060(%rbp)
  4011e3:	0f 95 85 20 bf ff ff 	setne  -0x40e0(%rbp)
  4011ea:	e8 a1 f1 ff ff       	call   400390 <memcmp@plt>
  4011ef:	44 8b 8d a0 bf ff ff 	mov    -0x4060(%rbp),%r9d
  4011f6:	0f b6 8d 18 bf ff ff 	movzbl -0x40e8(%rbp),%ecx
  4011fd:	85 c0                	test   %eax,%eax
  4011ff:	44 8b 85 10 bf ff ff 	mov    -0x40f0(%rbp),%r8d
  401206:	89 c2                	mov    %eax,%edx
  401208:	40 0f 95 c6          	setne  %sil
  40120c:	66 44 39 b5 1c bf ff ff 	cmp    %r14w,-0x40e4(%rbp)
  401214:	0f 84 e6 0e 00 00    	je     402100 <main+0x1700>
  40121a:	c7 85 a0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4060(%rbp)
  401224:	bf 01 00 00 00       	mov    $0x1,%edi
  401229:	b8 01 00 00 00       	mov    $0x1,%eax
  40122e:	44 0f b6 9d 20 bf ff ff 	movzbl -0x40e0(%rbp),%r11d
  401236:	40 0f b6 f6          	movzbl %sil,%esi
  40123a:	44 01 9d 48 bf ff ff 	add    %r11d,-0x40b8(%rbp)
  401241:	01 b5 34 bf ff ff    	add    %esi,-0x40cc(%rbp)
  401247:	01 bd 30 bf ff ff    	add    %edi,-0x40d0(%rbp)
  40124d:	44 01 85 2c bf ff ff 	add    %r8d,-0x40d4(%rbp)
  401254:	44 09 ca             	or     %r9d,%edx
  401257:	44 89 9d 1c bf ff ff 	mov    %r11d,-0x40e4(%rbp)
  40125e:	89 b5 18 bf ff ff    	mov    %esi,-0x40e8(%rbp)
  401264:	0f 84 12 0a 00 00    	je     401c7c <main+0x127c>
  40126a:	83 bd 4c bf ff ff 0d 	cmpl   $0xd,-0x40b4(%rbp)
  401271:	0f 84 a6 14 00 00    	je     40271d <main+0x1d1d>
  401277:	8b 85 a4 bf ff ff    	mov    -0x405c(%rbp),%eax
  40127d:	83 f8 0b             	cmp    $0xb,%eax
  401280:	0f 86 1c 0a 00 00    	jbe    401ca2 <main+0x12a2>
  401286:	83 c0 01             	add    $0x1,%eax
  401289:	89 85 a4 bf ff ff    	mov    %eax,-0x405c(%rbp)
  40128f:	48 83 ec 08          	sub    $0x8,%rsp
  401293:	ff b5 78 bf ff ff    	push   -0x4088(%rbp)
  401299:	be 78 68 40 00       	mov    $0x406878,%esi
  40129e:	ff b5 40 bf ff ff    	push   -0x40c0(%rbp)
  4012a4:	8b 85 48 ce ff ff    	mov    -0x31b8(%rbp),%eax
  4012aa:	50                   	push   %rax
  4012ab:	8b 85 88 c9 ff ff    	mov    -0x3678(%rbp),%eax
  4012b1:	50                   	push   %rax
  4012b2:	8b 85 b0 bf ff ff    	mov    -0x4050(%rbp),%eax
  4012b8:	ff b5 80 bf ff ff    	push   -0x4080(%rbp)
  4012be:	ff b5 68 bf ff ff    	push   -0x4098(%rbp)
  4012c4:	50                   	push   %rax
  4012c5:	8b 85 a0 bf ff ff    	mov    -0x4060(%rbp),%eax
  4012cb:	50                   	push   %rax
  4012cc:	8b 85 18 bf ff ff    	mov    -0x40e8(%rbp),%eax
  4012d2:	50                   	push   %rax
  4012d3:	8b 85 1c bf ff ff    	mov    -0x40e4(%rbp),%eax
  4012d9:	50                   	push   %rax
  4012da:	ff b5 90 bf ff ff    	push   -0x4070(%rbp)
  4012e0:	8b 85 64 bf ff ff    	mov    -0x409c(%rbp),%eax
  4012e6:	44 8b b5 28 bf ff ff 	mov    -0x40d8(%rbp),%r14d
  4012ed:	ff b5 98 bf ff ff    	push   -0x4068(%rbp)
  4012f3:	48 8b bd 38 bf ff ff 	mov    -0x40c8(%rbp),%rdi
  4012fa:	50                   	push   %rax
  4012fb:	31 c0                	xor    %eax,%eax
  4012fd:	44 8b 8d 60 bf ff ff 	mov    -0x40a0(%rbp),%r9d
  401304:	44 8b 85 58 bf ff ff 	mov    -0x40a8(%rbp),%r8d
  40130b:	44 89 f2             	mov    %r14d,%edx
  40130e:	8b 8d 4c bf ff ff    	mov    -0x40b4(%rbp),%ecx
  401314:	e8 d7 f0 ff ff       	call   4003f0 <fprintf@plt>
  401319:	41 8d 46 01          	lea    0x1(%r14),%eax
  40131d:	48 8d bd 48 c0 ff ff 	lea    -0x3fb8(%rbp),%rdi
  401324:	48 83 85 50 bf ff ff 04 	addq   $0x4,-0x40b0(%rbp)
  40132c:	89 85 28 bf ff ff    	mov    %eax,-0x40d8(%rbp)
  401332:	48 8b 85 50 bf ff ff 	mov    -0x40b0(%rbp),%rax
  401339:	48 83 c4 70          	add    $0x70,%rsp
  40133d:	48 39 f8             	cmp    %rdi,%rax
  401340:	0f 85 bd f9 ff ff    	jne    400d03 <main+0x303>
  401346:	44 8b b5 b8 be ff ff 	mov    -0x4148(%rbp),%r14d
  40134d:	48 8b 95 a8 be ff ff 	mov    -0x4158(%rbp),%rdx
  401354:	44 8b ad b0 be ff ff 	mov    -0x4150(%rbp),%r13d
  40135b:	41 83 c6 06          	add    $0x6,%r14d
  40135f:	48 83 ea 01          	sub    $0x1,%rdx
  401363:	0f 85 58 f9 ff ff    	jne    400cc1 <main+0x2c1>
  401369:	41 83 fd 68          	cmp    $0x68,%r13d
  40136d:	0f 85 62 f8 ff ff    	jne    400bd5 <main+0x1d5>
  401373:	48 8d 85 10 c4 ff ff 	lea    -0x3bf0(%rbp),%rax
  40137a:	44 89 eb             	mov    %r13d,%ebx
  40137d:	48 89 85 c8 be ff ff 	mov    %rax,-0x4138(%rbp)
  401384:	48 8d 85 10 c6 ff ff 	lea    -0x39f0(%rbp),%rax
  40138b:	48 89 85 c0 be ff ff 	mov    %rax,-0x4140(%rbp)
  401392:	b8 b9 79 37 9e       	mov    $0x9e3779b9,%eax
  401397:	c5 f9 6e d8          	vmovd  %eax,%xmm3
  40139b:	c5 f9 70 db 00       	vpshufd $0x0,%xmm3,%xmm3
  4013a0:	c5 f9 7f 9d d0 bf ff ff 	vmovdqa %xmm3,-0x4030(%rbp)
  4013a8:	8d 04 db             	lea    (%rbx,%rbx,8),%eax
  4013ab:	89 da                	mov    %ebx,%edx
  4013ad:	89 d9                	mov    %ebx,%ecx
  4013af:	89 9d 1c bf ff ff    	mov    %ebx,-0x40e4(%rbp)
  4013b5:	48 69 f2 25 49 92 24 	imul   $0x24924925,%rdx,%rsi
  4013bc:	c5 e0 57 db          	vxorps %xmm3,%xmm3,%xmm3
  4013c0:	44 8d 34 85 00 00 00 00 	lea    0x0(,%rax,4),%r14d
  4013c8:	89 d8                	mov    %ebx,%eax
  4013ca:	c1 e0 05             	shl    $0x5,%eax
  4013cd:	48 69 d2 39 8e e3 38 	imul   $0x38e38e39,%rdx,%rdx
  4013d4:	41 bd 06 00 00 00    	mov    $0x6,%r13d
  4013da:	29 d8                	sub    %ebx,%eax
  4013dc:	48 c1 ee 20          	shr    $0x20,%rsi
  4013e0:	89 c7                	mov    %eax,%edi
  4013e2:	89 d8                	mov    %ebx,%eax
  4013e4:	29 f0                	sub    %esi,%eax
  4013e6:	48 c1 ea 21          	shr    $0x21,%rdx
  4013ea:	d1 e8                	shr    $1,%eax
  4013ec:	01 f0                	add    %esi,%eax
  4013ee:	c1 e8 02             	shr    $0x2,%eax
  4013f1:	8d 34 c5 00 00 00 00 	lea    0x0(,%rax,8),%esi
  4013f8:	29 c6                	sub    %eax,%esi
  4013fa:	89 d8                	mov    %ebx,%eax
  4013fc:	29 f0                	sub    %esi,%eax
  4013fe:	8d 34 d2             	lea    (%rdx,%rdx,8),%esi
  401401:	89 da                	mov    %ebx,%edx
  401403:	29 f2                	sub    %esi,%edx
  401405:	89 de                	mov    %ebx,%esi
  401407:	83 c3 01             	add    $0x1,%ebx
  40140a:	81 f6 b9 79 37 9e    	xor    $0x9e3779b9,%esi
  401410:	89 b5 10 bf ff ff    	mov    %esi,-0x40f0(%rbp)
  401416:	89 ce                	mov    %ecx,%esi
  401418:	83 e6 03             	and    $0x3,%esi
  40141b:	c5 e2 2a c6          	vcvtsi2ss %esi,%xmm3,%xmm0
  40141f:	c5 fa 59 25 39 5b 00 00 	vmulss 0x5b39(%rip),%xmm0,%xmm4        # 406f60 <typeinfo for Boundary+0x150>
  401427:	c5 e2 2a c0          	vcvtsi2ss %eax,%xmm3,%xmm0
  40142b:	c5 fa 59 2d 31 5b 00 00 	vmulss 0x5b31(%rip),%xmm0,%xmm5        # 406f64 <typeinfo for Boundary+0x154>
  401433:	c5 e2 2a c2          	vcvtsi2ss %edx,%xmm3,%xmm0
  401437:	c5 fa 59 1d 71 5a 00 00 	vmulss 0x5a71(%rip),%xmm0,%xmm3        # 406eb0 <typeinfo for Boundary+0xa0>
  40143f:	c5 fa 11 a5 08 bf ff ff 	vmovss %xmm4,-0x40f8(%rbp)
  401447:	c5 fa 11 ad f0 be ff ff 	vmovss %xmm5,-0x4110(%rbp)
  40144f:	c5 fa 11 9d 18 bf ff ff 	vmovss %xmm3,-0x40e8(%rbp)
  401457:	c5 f9 6e df          	vmovd  %edi,%xmm3
  40145b:	c5 f9 70 db 00       	vpshufd $0x0,%xmm3,%xmm3
  401460:	c5 f9 7f 9d e0 be ff ff 	vmovdqa %xmm3,-0x4120(%rbp)
  401468:	c5 f9 6e d9          	vmovd  %ecx,%xmm3
  40146c:	c5 f9 70 db 00       	vpshufd $0x0,%xmm3,%xmm3
  401471:	c5 f9 7f 9d d0 be ff ff 	vmovdqa %xmm3,-0x4130(%rbp)
  401479:	4c 89 e8             	mov    %r13,%rax
  40147c:	89 9d bc be ff ff    	mov    %ebx,-0x4144(%rbp)
  401482:	48 f7 d8             	neg    %rax
  401485:	4c 89 ad b0 be ff ff 	mov    %r13,-0x4150(%rbp)
  40148c:	48 c1 e0 03          	shl    $0x3,%rax
  401490:	44 89 b5 4c bf ff ff 	mov    %r14d,-0x40b4(%rbp)
  401497:	48 89 85 00 bf ff ff 	mov    %rax,-0x4100(%rbp)
  40149e:	48 8d 85 30 c0 ff ff 	lea    -0x3fd0(%rbp),%rax
  4014a5:	48 89 85 90 bf ff ff 	mov    %rax,-0x4070(%rbp)
  4014ac:	44 89 b5 b8 be ff ff 	mov    %r14d,-0x4148(%rbp)
  4014b3:	4c 8b b5 c0 be ff ff 	mov    -0x4140(%rbp),%r14
  4014ba:	48 8b 85 90 bf ff ff 	mov    -0x4070(%rbp),%rax
  4014c1:	48 8b bd c0 bf ff ff 	mov    -0x4040(%rbp),%rdi
  4014c8:	b9 98 00 00 00       	mov    $0x98,%ecx
  4014cd:	8b 00                	mov    (%rax),%eax
  4014cf:	89 85 60 bf ff ff    	mov    %eax,-0x40a0(%rbp)
  4014d5:	31 c0                	xor    %eax,%eax
  4014d7:	f3 48 ab             	rep stos %rax,(%rdi)
  4014da:	48 8b 8d c8 be ff ff 	mov    -0x4138(%rbp),%rcx
  4014e1:	8b 85 10 bf ff ff    	mov    -0x40f0(%rbp),%eax
  4014e7:	66 0f 1f 84 00 00 00 00 00 	nopw   0x0(%rax,%rax,1)
  4014f0:	89 c2                	mov    %eax,%edx
  4014f2:	48 83 c1 10          	add    $0x10,%rcx
  4014f6:	c1 e2 0d             	shl    $0xd,%edx
  4014f9:	31 d0                	xor    %edx,%eax
  4014fb:	89 c2                	mov    %eax,%edx
  4014fd:	c1 ea 11             	shr    $0x11,%edx
  401500:	31 c2                	xor    %eax,%edx
  401502:	89 d0                	mov    %edx,%eax
  401504:	c1 e0 05             	shl    $0x5,%eax
  401507:	31 d0                	xor    %edx,%eax
  401509:	89 c6                	mov    %eax,%esi
  40150b:	89 41 f0             	mov    %eax,-0x10(%rcx)
  40150e:	c1 e6 0d             	shl    $0xd,%esi
  401511:	31 c6                	xor    %eax,%esi
  401513:	89 f2                	mov    %esi,%edx
  401515:	c1 ea 11             	shr    $0x11,%edx
  401518:	31 f2                	xor    %esi,%edx
  40151a:	89 d0                	mov    %edx,%eax
  40151c:	c1 e0 05             	shl    $0x5,%eax
  40151f:	31 d0                	xor    %edx,%eax
  401521:	89 c2                	mov    %eax,%edx
  401523:	89 41 f4             	mov    %eax,-0xc(%rcx)
  401526:	c1 e2 0d             	shl    $0xd,%edx
  401529:	31 d0                	xor    %edx,%eax
  40152b:	89 c2                	mov    %eax,%edx
  40152d:	c1 ea 11             	shr    $0x11,%edx
  401530:	31 c2                	xor    %eax,%edx
  401532:	89 d0                	mov    %edx,%eax
  401534:	c1 e0 05             	shl    $0x5,%eax
  401537:	31 d0                	xor    %edx,%eax
  401539:	89 c2                	mov    %eax,%edx
  40153b:	89 41 f8             	mov    %eax,-0x8(%rcx)
  40153e:	c1 e2 0d             	shl    $0xd,%edx
  401541:	31 d0                	xor    %edx,%eax
  401543:	89 c2                	mov    %eax,%edx
  401545:	c1 ea 11             	shr    $0x11,%edx
  401548:	31 c2                	xor    %eax,%edx
  40154a:	89 d0                	mov    %edx,%eax
  40154c:	c1 e0 05             	shl    $0x5,%eax
  40154f:	31 d0                	xor    %edx,%eax
  401551:	89 41 fc             	mov    %eax,-0x4(%rcx)
  401554:	4c 39 f1             	cmp    %r14,%rcx
  401557:	75 97                	jne    4014f0 <main+0xaf0>
  401559:	89 c2                	mov    %eax,%edx
  40155b:	c5 f9 6f 9d d0 be ff ff 	vmovdqa -0x4130(%rbp),%xmm3
  401563:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  401567:	c5 e1 fe 15 21 59 00 00 	vpaddd 0x5921(%rip),%xmm3,%xmm2        # 406e90 <typeinfo for Boundary+0x80>
  40156f:	c1 e2 0d             	shl    $0xd,%edx
  401572:	31 c2                	xor    %eax,%edx
  401574:	89 d0                	mov    %edx,%eax
  401576:	c1 e8 11             	shr    $0x11,%eax
  401579:	31 d0                	xor    %edx,%eax
  40157b:	41 89 c1             	mov    %eax,%r9d
  40157e:	41 c1 e1 05          	shl    $0x5,%r9d
  401582:	41 31 c1             	xor    %eax,%r9d
  401585:	44 89 ca             	mov    %r9d,%edx
  401588:	c1 e2 0d             	shl    $0xd,%edx
  40158b:	44 31 ca             	xor    %r9d,%edx
  40158e:	89 d0                	mov    %edx,%eax
  401590:	c1 e8 11             	shr    $0x11,%eax
  401593:	31 d0                	xor    %edx,%eax
  401595:	41 89 c0             	mov    %eax,%r8d
  401598:	41 c1 e0 05          	shl    $0x5,%r8d
  40159c:	41 31 c0             	xor    %eax,%r8d
  40159f:	44 89 c2             	mov    %r8d,%edx
  4015a2:	c1 e2 0d             	shl    $0xd,%edx
  4015a5:	44 31 c2             	xor    %r8d,%edx
  4015a8:	89 d0                	mov    %edx,%eax
  4015aa:	c1 e8 11             	shr    $0x11,%eax
  4015ad:	31 d0                	xor    %edx,%eax
  4015af:	89 c6                	mov    %eax,%esi
  4015b1:	c1 e6 05             	shl    $0x5,%esi
  4015b4:	31 c6                	xor    %eax,%esi
  4015b6:	89 f2                	mov    %esi,%edx
  4015b8:	c1 e2 0d             	shl    $0xd,%edx
  4015bb:	31 f2                	xor    %esi,%edx
  4015bd:	89 d0                	mov    %edx,%eax
  4015bf:	c1 e8 11             	shr    $0x11,%eax
  4015c2:	31 d0                	xor    %edx,%eax
  4015c4:	89 c2                	mov    %eax,%edx
  4015c6:	c1 e2 05             	shl    $0x5,%edx
  4015c9:	31 c2                	xor    %eax,%edx
  4015cb:	89 d1                	mov    %edx,%ecx
  4015cd:	c1 e1 0d             	shl    $0xd,%ecx
  4015d0:	31 d1                	xor    %edx,%ecx
  4015d2:	89 c8                	mov    %ecx,%eax
  4015d4:	c1 e8 11             	shr    $0x11,%eax
  4015d7:	31 c8                	xor    %ecx,%eax
  4015d9:	41 89 c2             	mov    %eax,%r10d
  4015dc:	41 c1 e2 05          	shl    $0x5,%r10d
  4015e0:	41 31 c2             	xor    %eax,%r10d
  4015e3:	48 8d 85 90 c1 ff ff 	lea    -0x3e70(%rbp),%rax
  4015ea:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  4015f5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  401600:	c5 f9 72 f1 02       	vpslld $0x2,%xmm1,%xmm0
  401605:	48 83 c0 10          	add    $0x10,%rax
  401609:	c5 f1 fe 0d 8f 58 00 00 	vpaddd 0x588f(%rip),%xmm1,%xmm1        # 406ea0 <typeinfo for Boundary+0x90>
  401611:	c5 f9 fe c2          	vpaddd %xmm2,%xmm0,%xmm0
  401615:	c4 e2 79 40 85 d0 bf ff ff 	vpmulld -0x4030(%rbp),%xmm0,%xmm0
  40161e:	c5 f9 7f 40 f0       	vmovdqa %xmm0,-0x10(%rax)
  401623:	49 39 c4             	cmp    %rax,%r12
  401626:	75 d8                	jne    401600 <main+0xc00>
  401628:	48 8b 85 00 bf ff ff 	mov    -0x4100(%rbp),%rax
  40162f:	48 8b bd a8 bf ff ff 	mov    -0x4058(%rbp),%rdi
  401636:	c5 d1 76 ed          	vpcmpeqd %xmm5,%xmm5,%xmm5
  40163a:	b9 00 02 00 00       	mov    $0x200,%ecx
  40163f:	c5 f9 6f 15 09 58 00 00 	vmovdqa 0x5809(%rip),%xmm2        # 406e50 <typeinfo for Boundary+0x40>
  401647:	c5 f9 6f b5 e0 be ff ff 	vmovdqa -0x4120(%rbp),%xmm6
  40164f:	c5 d1 72 f5 0a       	vpslld $0xa,%xmm5,%xmm5
  401654:	8b 9c 05 80 c0 ff ff 	mov    -0x3f80(%rbp,%rax,1),%ebx
  40165b:	8b 84 05 84 c0 ff ff 	mov    -0x3f7c(%rbp,%rax,1),%eax
  401662:	89 85 a0 bf ff ff    	mov    %eax,-0x4060(%rbp)
  401668:	89 85 e0 c2 ff ff    	mov    %eax,-0x3d20(%rbp)
  40166e:	31 c0                	xor    %eax,%eax
  401670:	f3 48 ab             	rep stos %rax,(%rdi)
  401673:	48 8d 85 d0 cf ff ff 	lea    -0x3030(%rbp),%rax
  40167a:	bf 01 f8 3f 00       	mov    $0x3ff801,%edi
  40167f:	89 9d 64 bf ff ff    	mov    %ebx,-0x409c(%rbp)
  401685:	48 89 85 a8 bf ff ff 	mov    %rax,-0x4058(%rbp)
  40168c:	c5 f9 6e df          	vmovd  %edi,%xmm3
  401690:	89 9d d0 c2 ff ff    	mov    %ebx,-0x3d30(%rbp)
  401696:	bb 10 00 00 00       	mov    $0x10,%ebx
  40169b:	c5 f9 70 db 00       	vpshufd $0x0,%xmm3,%xmm3
  4016a0:	c5 f9 6e e3          	vmovd  %ebx,%xmm4
  4016a4:	c5 f9 70 e4 00       	vpshufd $0x0,%xmm4,%xmm4
  4016a9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  4016b0:	c5 f9 72 f2 04       	vpslld $0x4,%xmm2,%xmm0
  4016b5:	48 83 c0 10          	add    $0x10,%rax
  4016b9:	48 8d 9d d0 d1 ff ff 	lea    -0x2e30(%rbp),%rbx
  4016c0:	c5 f9 fe c2          	vpaddd %xmm2,%xmm0,%xmm0
  4016c4:	c5 e9 fe d4          	vpaddd %xmm4,%xmm2,%xmm2
  4016c8:	c5 f9 fe c6          	vpaddd %xmm6,%xmm0,%xmm0
  4016cc:	c5 f9 f4 fb          	vpmuludq %xmm3,%xmm0,%xmm7
  4016d0:	c5 f1 73 d0 20       	vpsrlq $0x20,%xmm0,%xmm1
  4016d5:	c5 f1 f4 cb          	vpmuludq %xmm3,%xmm1,%xmm1
  4016d9:	c5 f9 70 ff f5       	vpshufd $0xf5,%xmm7,%xmm7
  4016de:	c4 e3 71 0e cf 33    	vpblendw $0x33,%xmm7,%xmm1,%xmm1
  4016e4:	c5 f1 72 d1 01       	vpsrld $0x1,%xmm1,%xmm1
  4016e9:	c5 c1 72 f1 0b       	vpslld $0xb,%xmm1,%xmm7
  4016ee:	c5 c1 fe c9          	vpaddd %xmm1,%xmm7,%xmm1
  4016f2:	c5 f9 fa c1          	vpsubd %xmm1,%xmm0,%xmm0
  4016f6:	c5 f9 fe c5          	vpaddd %xmm5,%xmm0,%xmm0
  4016fa:	c5 f8 5b c0          	vcvtdq2ps %xmm0,%xmm0
  4016fe:	c5 f8 59 05 aa 57 00 00 	vmulps 0x57aa(%rip),%xmm0,%xmm0        # 406eb0 <typeinfo for Boundary+0xa0>
  401706:	c5 f8 29 40 f0       	vmovaps %xmm0,-0x10(%rax)
  40170b:	48 39 d8             	cmp    %rbx,%rax
  40170e:	75 a0                	jne    4016b0 <main+0xcb0>
  401710:	c5 fa 10 9d 08 bf ff ff 	vmovss -0x40f8(%rbp),%xmm3
  401718:	8b 85 a0 bf ff ff    	mov    -0x4060(%rbp),%eax
  40171e:	c7 85 10 c5 ff ff 00 00 00 00 	movl   $0x0,-0x3af0(%rbp)
  401728:	b9 98 00 00 00       	mov    $0x98,%ecx
  40172d:	8b bd 60 bf ff ff    	mov    -0x40a0(%rbp),%edi
  401733:	8b 9d 64 bf ff ff    	mov    -0x409c(%rbp),%ebx
  401739:	48 c7 85 d0 c1 ff ff 00 04 00 00 	movq   $0x400,-0x3e30(%rbp)
  401744:	c5 fa 11 9d 14 c5 ff ff 	vmovss %xmm3,-0x3aec(%rbp)
  40174c:	c5 fa 10 9d f0 be ff ff 	vmovss -0x4110(%rbp),%xmm3
  401754:	89 bc 05 30 d0 ff ff 	mov    %edi,-0x2fd0(%rbp,%rax,1)
  40175b:	48 8b bd c8 bf ff ff 	mov    -0x4038(%rbp),%rdi
  401762:	c5 fa 11 9d 18 c5 ff ff 	vmovss %xmm3,-0x3ae8(%rbp)
  40176a:	c5 fa 10 9d 18 bf ff ff 	vmovss -0x40e8(%rbp),%xmm3
  401772:	48 89 85 e0 c1 ff ff 	mov    %rax,-0x3e20(%rbp)
  401779:	c5 fa 11 9d 1c c5 ff ff 	vmovss %xmm3,-0x3ae4(%rbp)
  401781:	c5 f9 6f 85 10 c5 ff ff 	vmovdqa -0x3af0(%rbp),%xmm0
  401789:	48 89 9d f0 c1 ff ff 	mov    %rbx,-0x3e10(%rbp)
  401790:	c5 f9 7f 85 d0 d1 ff ff 	vmovdqa %xmm0,-0x2e30(%rbp)
  401798:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
  40179c:	c7 84 05 40 d0 ff ff 00 00 00 00 	movl   $0x0,-0x2fc0(%rbp,%rax,1)
  4017a7:	c7 84 05 48 d0 ff ff 00 00 00 00 	movl   $0x0,-0x2fb8(%rbp,%rax,1)
  4017b2:	c7 84 05 50 d0 ff ff 04 03 00 00 	movl   $0x304,-0x2fb0(%rbp,%rax,1)
  4017bd:	48 8d 85 d0 df ff ff 	lea    -0x2030(%rbp),%rax
  4017c4:	48 c7 85 00 c2 ff ff 00 00 00 00 	movq   $0x0,-0x3e00(%rbp)
  4017cf:	48 c7 85 10 c2 ff ff 01 00 00 00 	movq   $0x1,-0x3df0(%rbp)
  4017da:	48 c7 85 20 c2 ff ff 00 03 00 00 	movq   $0x300,-0x3de0(%rbp)
  4017e5:	48 c7 85 00 c3 ff ff 00 03 00 00 	movq   $0x300,-0x3d00(%rbp)
  4017f0:	48 c7 85 60 c3 ff ff 00 10 00 00 	movq   $0x1000,-0x3ca0(%rbp)
  4017fb:	48 c7 85 f0 c2 ff ff 00 00 00 00 	movq   $0x0,-0x3d10(%rbp)
  401806:	44 89 8d 10 c6 ff ff 	mov    %r9d,-0x39f0(%rbp)
  40180d:	44 89 85 14 c6 ff ff 	mov    %r8d,-0x39ec(%rbp)
  401814:	89 b5 18 c6 ff ff    	mov    %esi,-0x39e8(%rbp)
  40181a:	89 95 1c c6 ff ff    	mov    %edx,-0x39e4(%rbp)
  401820:	44 89 95 20 c6 ff ff 	mov    %r10d,-0x39e0(%rbp)
  401827:	c7 85 24 c6 ff ff 00 00 a0 3f 	movl   $0x3fa00000,-0x39dc(%rbp)
  401831:	48 8b b5 c0 bf ff ff 	mov    -0x4040(%rbp),%rsi
  401838:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  40183b:	48 8d b5 90 c1 ff ff 	lea    -0x3e70(%rbp),%rsi
  401842:	48 8d bd 10 cb ff ff 	lea    -0x34f0(%rbp),%rdi
  401849:	b9 98 00 00 00       	mov    $0x98,%ecx
  40184e:	48 89 b5 c0 bf ff ff 	mov    %rsi,-0x4040(%rbp)
  401855:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  401858:	48 8b bd b8 bf ff ff 	mov    -0x4048(%rbp),%rdi
  40185f:	48 8b b5 a8 bf ff ff 	mov    -0x4058(%rbp),%rsi
  401866:	b9 00 02 00 00       	mov    $0x200,%ecx
  40186b:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  40186e:	48 8d b5 d0 cf ff ff 	lea    -0x3030(%rbp),%rsi
  401875:	48 8d bd d0 ef ff ff 	lea    -0x1030(%rbp),%rdi
  40187c:	b9 00 02 00 00       	mov    $0x200,%ecx
  401881:	48 89 b5 a8 bf ff ff 	mov    %rsi,-0x4058(%rbp)
  401888:	f3 48 a5             	rep movsq (%rsi),(%rdi)
  40188b:	48 89 85 b8 bf ff ff 	mov    %rax,-0x4048(%rbp)
  401892:	48 89 05 f7 77 00 00 	mov    %rax,0x77f7(%rip)        # 409090 <g_ee_main_mem>
  401899:	48 8d 85 50 c6 ff ff 	lea    -0x39b0(%rbp),%rax
  4018a0:	48 89 85 c8 bf ff ff 	mov    %rax,-0x4038(%rbp)
  4018a7:	48 89 c7             	mov    %rax,%rdi
  4018aa:	c5 fd 7f 85 d0 c0 ff ff 	vmovdqa %ymm0,-0x3f30(%rbp)
  4018b2:	c5 fd 7f 85 90 c0 ff ff 	vmovdqa %ymm0,-0x3f70(%rbp)
  4018ba:	c5 fd 7f 85 b0 c0 ff ff 	vmovdqa %ymm0,-0x3f50(%rbp)
  4018c2:	c5 fe 7f 85 e8 c0 ff ff 	vmovdqu %ymm0,-0x3f18(%rbp)
  4018ca:	c5 f8 77             	vzeroupper
  4018cd:	e8 9e 1b 00 00       	call   403470 <full_before_execute>
  4018d2:	48 89 85 58 bf ff ff 	mov    %rax,-0x40a8(%rbp)
  4018d9:	bb 01 00 00 00       	mov    $0x1,%ebx
  4018de:	41 bd 01 00 00 00    	mov    $0x1,%r13d
  4018e4:	48 89 85 f8 c0 ff ff 	mov    %rax,-0x3f08(%rbp)
  4018eb:	c6 85 00 c1 ff ff 01 	movb   $0x1,-0x3f00(%rbp)
  4018f2:	48 c7 85 78 bf ff ff 00 00 00 00 	movq   $0x0,-0x4088(%rbp)
  4018fd:	c6 85 98 bf ff ff 00 	movb   $0x0,-0x4068(%rbp)
  401904:	48 8d 85 d0 ef ff ff 	lea    -0x1030(%rbp),%rax
  40190b:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
  40190f:	48 8d bd 10 cb ff ff 	lea    -0x34f0(%rbp),%rdi
  401916:	48 89 05 73 77 00 00 	mov    %rax,0x7773(%rip)        # 409090 <g_ee_main_mem>
  40191d:	c5 fd 7f 85 50 c1 ff ff 	vmovdqa %ymm0,-0x3eb0(%rbp)
  401925:	c5 fd 7f 85 10 c1 ff ff 	vmovdqa %ymm0,-0x3ef0(%rbp)
  40192d:	c5 fd 7f 85 30 c1 ff ff 	vmovdqa %ymm0,-0x3ed0(%rbp)
  401935:	c5 fe 7f 85 68 c1 ff ff 	vmovdqu %ymm0,-0x3e98(%rbp)
  40193d:	c5 f8 77             	vzeroupper
  401940:	e8 3b 2e 00 00       	call   404780 <full_after_execute>
  401945:	48 89 85 70 bf ff ff 	mov    %rax,-0x4090(%rbp)
  40194c:	48 89 85 78 c1 ff ff 	mov    %rax,-0x3e88(%rbp)
  401953:	c6 85 80 c1 ff ff 01 	movb   $0x1,-0x3e80(%rbp)
  40195a:	84 db                	test   %bl,%bl
  40195c:	0f 85 93 17 00 00    	jne    4030f5 <main+0x26f5>
  401962:	44 0f b6 bd 98 bf ff ff 	movzbl -0x4068(%rbp),%r15d
  40196a:	45 84 ff             	test   %r15b,%r15b
  40196d:	0f 85 9d 16 00 00    	jne    403010 <main+0x2610>
  401973:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  40197e:	b9 01 00 00 00       	mov    $0x1,%ecx
  401983:	41 bf 01 00 00 00    	mov    $0x1,%r15d
  401989:	ba 03 00 00 00       	mov    $0x3,%edx
  40198e:	c6 85 50 bf ff ff 00 	movb   $0x0,-0x40b0(%rbp)
  401995:	b8 02 00 00 00       	mov    $0x2,%eax
  40199a:	41 b9 01 00 00 00    	mov    $0x1,%r9d
  4019a0:	48 c7 85 b0 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4050(%rbp)
  4019ab:	48 c7 85 88 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4078(%rbp)
  4019b6:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  4019c0:	48 8b bd c8 bf ff ff 	mov    -0x4038(%rbp),%rdi
  4019c7:	83 84 95 20 c0 ff ff 01 	addl   $0x1,-0x3fe0(%rbp,%rdx,4)
  4019cf:	48 8d b5 10 cb ff ff 	lea    -0x34f0(%rbp),%rsi
  4019d6:	ba c0 04 00 00       	mov    $0x4c0,%edx
  4019db:	89 8d 20 bf ff ff    	mov    %ecx,-0x40e0(%rbp)
  4019e1:	83 84 85 10 c0 ff ff 01 	addl   $0x1,-0x3ff0(%rbp,%rax,4)
  4019e9:	44 89 8d 28 bf ff ff 	mov    %r9d,-0x40d8(%rbp)
  4019f0:	e8 9b e9 ff ff       	call   400390 <memcmp@plt>
  4019f5:	48 8b bd b8 bf ff ff 	mov    -0x4048(%rbp),%rdi
  4019fc:	ba 00 10 00 00       	mov    $0x1000,%edx
  401a01:	48 8d b5 d0 ef ff ff 	lea    -0x1030(%rbp),%rsi
  401a08:	85 c0                	test   %eax,%eax
  401a0a:	89 85 68 bf ff ff    	mov    %eax,-0x4098(%rbp)
  401a10:	0f 95 85 40 bf ff ff 	setne  -0x40c0(%rbp)
  401a17:	e8 74 e9 ff ff       	call   400390 <memcmp@plt>
  401a1c:	44 8b 95 68 bf ff ff 	mov    -0x4098(%rbp),%r10d
  401a23:	8b 8d 20 bf ff ff    	mov    -0x40e0(%rbp),%ecx
  401a29:	85 c0                	test   %eax,%eax
  401a2b:	89 c2                	mov    %eax,%edx
  401a2d:	40 0f 95 c6          	setne  %sil
  401a31:	66 44 39 ad 28 bf ff ff 	cmp    %r13w,-0x40d8(%rbp)
  401a39:	0f 84 3c 16 00 00    	je     40307b <main+0x267b>
  401a3f:	c7 85 68 bf ff ff 01 00 00 00 	movl   $0x1,-0x4098(%rbp)
  401a49:	bf 01 00 00 00       	mov    $0x1,%edi
  401a4e:	b8 01 00 00 00       	mov    $0x1,%eax
  401a53:	0f b6 9d 40 bf ff ff 	movzbl -0x40c0(%rbp),%ebx
  401a5a:	40 0f b6 f6          	movzbl %sil,%esi
  401a5e:	01 9d 48 bf ff ff    	add    %ebx,-0x40b8(%rbp)
  401a64:	01 b5 34 bf ff ff    	add    %esi,-0x40cc(%rbp)
  401a6a:	01 bd 30 bf ff ff    	add    %edi,-0x40d0(%rbp)
  401a70:	01 8d 2c bf ff ff    	add    %ecx,-0x40d4(%rbp)
  401a76:	44 09 d2             	or     %r10d,%edx
  401a79:	89 9d 40 bf ff ff    	mov    %ebx,-0x40c0(%rbp)
  401a7f:	89 b5 28 bf ff ff    	mov    %esi,-0x40d8(%rbp)
  401a85:	0f 85 f7 0d 00 00    	jne    402882 <main+0x1e82>
  401a8b:	45 84 ff             	test   %r15b,%r15b
  401a8e:	0f 85 ee 0d 00 00    	jne    402882 <main+0x1e82>
  401a94:	84 c0                	test   %al,%al
  401a96:	0f 85 e6 0d 00 00    	jne    402882 <main+0x1e82>
  401a9c:	48 83 ec 08          	sub    $0x8,%rsp
  401aa0:	ff b5 70 bf ff ff    	push   -0x4090(%rbp)
  401aa6:	be 78 68 40 00       	mov    $0x406878,%esi
  401aab:	ff b5 58 bf ff ff    	push   -0x40a8(%rbp)
  401ab1:	8b 85 48 ce ff ff    	mov    -0x31b8(%rbp),%eax
  401ab7:	50                   	push   %rax
  401ab8:	8b 85 88 c9 ff ff    	mov    -0x3678(%rbp),%eax
  401abe:	50                   	push   %rax
  401abf:	8b 85 f0 bf ff ff    	mov    -0x4010(%rbp),%eax
  401ac5:	ff b5 80 bf ff ff    	push   -0x4080(%rbp)
  401acb:	ff b5 78 bf ff ff    	push   -0x4088(%rbp)
  401ad1:	50                   	push   %rax
  401ad2:	8b 85 68 bf ff ff    	mov    -0x4098(%rbp),%eax
  401ad8:	50                   	push   %rax
  401ad9:	8b 85 28 bf ff ff    	mov    -0x40d8(%rbp),%eax
  401adf:	50                   	push   %rax
  401ae0:	8b 85 40 bf ff ff    	mov    -0x40c0(%rbp),%eax
  401ae6:	50                   	push   %rax
  401ae7:	ff b5 88 bf ff ff    	push   -0x4078(%rbp)
  401aed:	8b 85 60 bf ff ff    	mov    -0x40a0(%rbp),%eax
  401af3:	8b 9d 4c bf ff ff    	mov    -0x40b4(%rbp),%ebx
  401af9:	ff b5 b0 bf ff ff    	push   -0x4050(%rbp)
  401aff:	44 8b 8d a0 bf ff ff 	mov    -0x4060(%rbp),%r9d
  401b06:	50                   	push   %rax
  401b07:	31 c0                	xor    %eax,%eax
  401b09:	44 8b 85 64 bf ff ff 	mov    -0x409c(%rbp),%r8d
  401b10:	8b 8d 1c bf ff ff    	mov    -0x40e4(%rbp),%ecx
  401b16:	89 da                	mov    %ebx,%edx
  401b18:	48 8b bd 38 bf ff ff 	mov    -0x40c8(%rbp),%rdi
  401b1f:	e8 cc e8 ff ff       	call   4003f0 <fprintf@plt>
  401b24:	8d 43 01             	lea    0x1(%rbx),%eax
  401b27:	48 8d 9d 48 c0 ff ff 	lea    -0x3fb8(%rbp),%rbx
  401b2e:	48 83 85 90 bf ff ff 04 	addq   $0x4,-0x4070(%rbp)
  401b36:	89 85 4c bf ff ff    	mov    %eax,-0x40b4(%rbp)
  401b3c:	48 8b 85 90 bf ff ff 	mov    -0x4070(%rbp),%rax
  401b43:	48 83 c4 70          	add    $0x70,%rsp
  401b47:	48 39 d8             	cmp    %rbx,%rax
  401b4a:	0f 85 6a f9 ff ff    	jne    4014ba <main+0xaba>
  401b50:	44 8b b5 b8 be ff ff 	mov    -0x4148(%rbp),%r14d
  401b57:	4c 8b ad b0 be ff ff 	mov    -0x4150(%rbp),%r13
  401b5e:	8b 9d bc be ff ff    	mov    -0x4144(%rbp),%ebx
  401b64:	41 83 c6 06          	add    $0x6,%r14d
  401b68:	49 83 ed 01          	sub    $0x1,%r13
  401b6c:	0f 85 07 f9 ff ff    	jne    401479 <main+0xa79>
  401b72:	81 fb a8 00 00 00    	cmp    $0xa8,%ebx
  401b78:	0f 85 2a f8 ff ff    	jne    4013a8 <main+0x9a8>
  401b7e:	4c 8b b5 38 bf ff ff 	mov    -0x40c8(%rbp),%r14
  401b85:	4c 89 f7             	mov    %r14,%rdi
  401b88:	e8 a3 e8 ff ff       	call   400430 <ferror@plt>
  401b8d:	4c 89 f7             	mov    %r14,%rdi
  401b90:	89 c3                	mov    %eax,%ebx
  401b92:	e8 39 e8 ff ff       	call   4003d0 <fclose@plt>
  401b97:	8b 8d 14 c0 ff ff    	mov    -0x3fec(%rbp),%ecx
  401b9d:	be b3 65 40 00       	mov    $0x4065b3,%esi
  401ba2:	44 8b 8d 1c c0 ff ff 	mov    -0x3fe4(%rbp),%r9d
  401ba9:	44 8b 85 18 c0 ff ff 	mov    -0x3fe8(%rbp),%r8d
  401bb0:	8b 95 10 c0 ff ff    	mov    -0x3ff0(%rbp),%edx
  401bb6:	09 c3                	or     %eax,%ebx
  401bb8:	bf c0 68 40 00       	mov    $0x4068c0,%edi
  401bbd:	31 c0                	xor    %eax,%eax
  401bbf:	e8 ac e7 ff ff       	call   400370 <printf@plt>
  401bc4:	44 8b 8d 2c c0 ff ff 	mov    -0x3fd4(%rbp),%r9d
  401bcb:	be ba 65 40 00       	mov    $0x4065ba,%esi
  401bd0:	31 c0                	xor    %eax,%eax
  401bd2:	44 8b 85 28 c0 ff ff 	mov    -0x3fd8(%rbp),%r8d
  401bd9:	8b 8d 24 c0 ff ff    	mov    -0x3fdc(%rbp),%ecx
  401bdf:	bf c0 68 40 00       	mov    $0x4068c0,%edi
  401be4:	8b 95 20 c0 ff ff    	mov    -0x3fe0(%rbp),%edx
  401bea:	e8 81 e7 ff ff       	call   400370 <printf@plt>
  401bef:	48 83 ec 08          	sub    $0x8,%rsp
  401bf3:	31 c0                	xor    %eax,%eax
  401bf5:	85 db                	test   %ebx,%ebx
  401bf7:	0f 95 c0             	setne  %al
  401bfa:	44 8b b5 2c bf ff ff 	mov    -0x40d4(%rbp),%r14d
  401c01:	44 8b 8d 34 bf ff ff 	mov    -0x40cc(%rbp),%r9d
  401c08:	ba 00 09 00 00       	mov    $0x900,%edx
  401c0d:	50                   	push   %rax
  401c0e:	8b 85 30 bf ff ff    	mov    -0x40d0(%rbp),%eax
  401c14:	be a0 17 00 00       	mov    $0x17a0,%esi
  401c19:	bf 00 69 40 00       	mov    $0x406900,%edi
  401c1e:	44 8b 85 48 bf ff ff 	mov    -0x40b8(%rbp),%r8d
  401c25:	8b 8d a4 bf ff ff    	mov    -0x405c(%rbp),%ecx
  401c2b:	41 56                	push   %r14
  401c2d:	50                   	push   %rax
  401c2e:	31 c0                	xor    %eax,%eax
  401c30:	e8 3b e7 ff ff       	call   400370 <printf@plt>
  401c35:	48 83 c4 20          	add    $0x20,%rsp
  401c39:	44 09 f3             	or     %r14d,%ebx
  401c3c:	0f 85 10 16 00 00    	jne    403252 <main+0x2852>
  401c42:	83 bd a4 bf ff ff 00 	cmpl   $0x0,-0x405c(%rbp)
  401c49:	0f 84 1e 16 00 00    	je     40326d <main+0x286d>
  401c4f:	be c3 65 40 00       	mov    $0x4065c3,%esi
  401c54:	bf 88 69 40 00       	mov    $0x406988,%edi
  401c59:	31 c0                	xor    %eax,%eax
  401c5b:	bb 01 00 00 00       	mov    $0x1,%ebx
  401c60:	e8 0b e7 ff ff       	call   400370 <printf@plt>
  401c65:	48 8d 65 d0          	lea    -0x30(%rbp),%rsp
  401c69:	89 d8                	mov    %ebx,%eax
  401c6b:	5b                   	pop    %rbx
  401c6c:	41 5a                	pop    %r10
  401c6e:	41 5c                	pop    %r12
  401c70:	41 5d                	pop    %r13
  401c72:	41 5e                	pop    %r14
  401c74:	41 5f                	pop    %r15
  401c76:	5d                   	pop    %rbp
  401c77:	49 8d 62 f8          	lea    -0x8(%r10),%rsp
  401c7b:	c3                   	ret
  401c7c:	09 c1                	or     %eax,%ecx
  401c7e:	83 bd 4c bf ff ff 0d 	cmpl   $0xd,-0x40b4(%rbp)
  401c85:	0f 84 40 05 00 00    	je     4021cb <main+0x17cb>
  401c8b:	84 c9                	test   %cl,%cl
  401c8d:	0f 84 fc f5 ff ff    	je     40128f <main+0x88f>
  401c93:	8b 85 a4 bf ff ff    	mov    -0x405c(%rbp),%eax
  401c99:	83 f8 0b             	cmp    $0xb,%eax
  401c9c:	0f 87 e4 f5 ff ff    	ja     401286 <main+0x886>
  401ca2:	c7 85 20 bf ff ff 01 00 00 00 	movl   $0x1,-0x40e0(%rbp)
  401cac:	45 31 ed             	xor    %r13d,%r13d
  401caf:	8b 85 b0 bf ff ff    	mov    -0x4050(%rbp),%eax
  401cb5:	44 8b 8d 64 bf ff ff 	mov    -0x409c(%rbp),%r9d
  401cbc:	45 31 f6             	xor    %r14d,%r14d
  401cbf:	bf b0 66 40 00       	mov    $0x4066b0,%edi
  401cc4:	44 8b 85 60 bf ff ff 	mov    -0x40a0(%rbp),%r8d
  401ccb:	8b 8d 58 bf ff ff    	mov    -0x40a8(%rbp),%ecx
  401cd1:	8b 95 4c bf ff ff    	mov    -0x40b4(%rbp),%edx
  401cd7:	8b b5 28 bf ff ff    	mov    -0x40d8(%rbp),%esi
  401cdd:	50                   	push   %rax
  401cde:	8b 85 a0 bf ff ff    	mov    -0x4060(%rbp),%eax
  401ce4:	50                   	push   %rax
  401ce5:	8b 85 18 bf ff ff    	mov    -0x40e8(%rbp),%eax
  401ceb:	50                   	push   %rax
  401cec:	8b 85 1c bf ff ff    	mov    -0x40e4(%rbp),%eax
  401cf2:	50                   	push   %rax
  401cf3:	31 c0                	xor    %eax,%eax
  401cf5:	ff b5 90 bf ff ff    	push   -0x4070(%rbp)
  401cfb:	ff b5 98 bf ff ff    	push   -0x4068(%rbp)
  401d01:	e8 6a e6 ff ff       	call   400370 <printf@plt>
  401d06:	b8 10 00 00 00       	mov    $0x10,%eax
  401d0b:	48 83 c4 30          	add    $0x30,%rsp
  401d0f:	c5 f9 6f 0d 09 51 00 00 	vmovdqa 0x5109(%rip),%xmm1        # 406e20 <typeinfo for Boundary+0x10>
  401d17:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
  401d1c:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
  401d23:	c5 f9 6f 15 05 51 00 00 	vmovdqa 0x5105(%rip),%xmm2        # 406e30 <typeinfo for Boundary+0x20>
  401d2b:	c5 d1 ef ed          	vpxor  %xmm5,%xmm5,%xmm5
  401d2f:	c4 e1 f9 6e d8       	vmovq  %rax,%xmm3
  401d34:	48 8b 85 c8 bf ff ff 	mov    -0x4038(%rbp),%rax
  401d3b:	c5 d9 6c e4          	vpunpcklqdq %xmm4,%xmm4,%xmm4
  401d3f:	c5 e1 6c db          	vpunpcklqdq %xmm3,%xmm3,%xmm3
  401d43:	c4 c1 79 6f 04 06    	vmovdqa (%r14,%rax,1),%xmm0
  401d49:	c4 c1 79 74 84 2e 10 cb ff ff 	vpcmpeqb -0x34f0(%r14,%rbp,1),%xmm0,%xmm0
  401d53:	c5 f9 74 c5          	vpcmpeqb %xmm5,%xmm0,%xmm0
  401d57:	c4 e2 79 17 c0       	vptest %xmm0,%xmm0
  401d5c:	0f 85 10 07 00 00    	jne    402472 <main+0x1a72>
  401d62:	49 83 c6 10          	add    $0x10,%r14
  401d66:	c5 e9 d4 d4          	vpaddq %xmm4,%xmm2,%xmm2
  401d6a:	c5 f1 d4 cb          	vpaddq %xmm3,%xmm1,%xmm1
  401d6e:	49 81 fe c0 04 00 00 	cmp    $0x4c0,%r14
  401d75:	75 cc                	jne    401d43 <main+0x1343>
  401d77:	bf 10 00 00 00       	mov    $0x10,%edi
  401d7c:	48 c7 c6 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rsi
  401d83:	c5 f9 6f 0d b5 50 00 00 	vmovdqa 0x50b5(%rip),%xmm1        # 406e40 <typeinfo for Boundary+0x30>
  401d8b:	c5 f9 6f 15 9d 50 00 00 	vmovdqa 0x509d(%rip),%xmm2        # 406e30 <typeinfo for Boundary+0x20>
  401d93:	c4 e1 f9 6e e7       	vmovq  %rdi,%xmm4
  401d98:	c4 e1 f9 6e de       	vmovq  %rsi,%xmm3
  401d9d:	c5 d1 ef ed          	vpxor  %xmm5,%xmm5,%xmm5
  401da1:	31 c0                	xor    %eax,%eax
  401da3:	48 8b 95 b8 bf ff ff 	mov    -0x4048(%rbp),%rdx
  401daa:	c5 d9 6c e4          	vpunpcklqdq %xmm4,%xmm4,%xmm4
  401dae:	c5 e1 6c db          	vpunpcklqdq %xmm3,%xmm3,%xmm3
  401db2:	c5 f9 6f 04 02       	vmovdqa (%rdx,%rax,1),%xmm0
  401db7:	c5 f9 74 84 05 d0 ef ff ff 	vpcmpeqb -0x1030(%rbp,%rax,1),%xmm0,%xmm0
  401dc0:	c5 f9 74 c5          	vpcmpeqb %xmm5,%xmm0,%xmm0
  401dc4:	c4 e2 79 17 c0       	vptest %xmm0,%xmm0
  401dc9:	0f 85 3f 04 00 00    	jne    40220e <main+0x180e>
  401dcf:	48 83 c0 10          	add    $0x10,%rax
  401dd3:	c5 e9 d4 d4          	vpaddq %xmm4,%xmm2,%xmm2
  401dd7:	c5 f1 d4 cb          	vpaddq %xmm3,%xmm1,%xmm1
  401ddb:	48 3d 00 10 00 00    	cmp    $0x1000,%rax
  401de1:	75 cf                	jne    401db2 <main+0x13b2>
  401de3:	b9 00 10 00 00       	mov    $0x1000,%ecx
  401de8:	ba c0 04 00 00       	mov    $0x4c0,%edx
  401ded:	4c 89 f6             	mov    %r14,%rsi
  401df0:	31 c0                	xor    %eax,%eax
  401df2:	bf 20 67 40 00       	mov    $0x406720,%edi
  401df7:	e8 74 e5 ff ff       	call   400370 <printf@plt>
  401dfc:	b9 00 10 00 00       	mov    $0x1000,%ecx
  401e01:	49 81 fe c0 04 00 00 	cmp    $0x4c0,%r14
  401e08:	74 51                	je     401e5b <main+0x145b>
  401e0a:	42 0f b6 94 35 10 cb ff ff 	movzbl -0x34f0(%rbp,%r14,1),%edx
  401e13:	bf 70 67 40 00       	mov    $0x406770,%edi
  401e18:	31 c0                	xor    %eax,%eax
  401e1a:	48 89 8d 10 bf ff ff 	mov    %rcx,-0x40f0(%rbp)
  401e21:	42 0f b6 b4 35 50 c6 ff ff 	movzbl -0x39b0(%rbp,%r14,1),%esi
  401e2a:	e8 41 e5 ff ff       	call   400370 <printf@plt>
  401e2f:	48 8b 8d 10 bf ff ff 	mov    -0x40f0(%rbp),%rcx
  401e36:	48 81 f9 00 10 00 00 	cmp    $0x1000,%rcx
  401e3d:	74 1c                	je     401e5b <main+0x145b>
  401e3f:	0f b6 94 0d d0 ef ff ff 	movzbl -0x1030(%rbp,%rcx,1),%edx
  401e47:	0f b6 b4 0d d0 df ff ff 	movzbl -0x2030(%rbp,%rcx,1),%esi
  401e4f:	bf 98 67 40 00       	mov    $0x406798,%edi
  401e54:	31 c0                	xor    %eax,%eax
  401e56:	e8 15 e5 ff ff       	call   400370 <printf@plt>
  401e5b:	45 84 ed             	test   %r13b,%r13b
  401e5e:	0f 85 51 08 00 00    	jne    4026b5 <main+0x1cb5>
  401e64:	44 89 bd 10 bf ff ff 	mov    %r15d,-0x40f0(%rbp)
  401e6b:	4c 8b b5 c8 bf ff ff 	mov    -0x4038(%rbp),%r14
  401e72:	4c 8d ad 10 cb ff ff 	lea    -0x34f0(%rbp),%r13
  401e79:	48 89 9d a0 be ff ff 	mov    %rbx,-0x4160(%rbp)
  401e80:	31 db                	xor    %ebx,%ebx
  401e82:	0f 1f 00             	nopl   (%rax)
  401e85:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  401e90:	45 31 ff             	xor    %r15d,%r15d
  401e93:	43 8b 8c be 80 02 00 00 	mov    0x280(%r14,%r15,4),%ecx
  401e9b:	47 8b 84 bd 80 02 00 00 	mov    0x280(%r13,%r15,4),%r8d
  401ea3:	41 39 c8             	cmp    %ecx,%r8d
  401ea6:	74 11                	je     401eb9 <main+0x14b9>
  401ea8:	44 89 fa             	mov    %r15d,%edx
  401eab:	89 de                	mov    %ebx,%esi
  401ead:	bf c0 67 40 00       	mov    $0x4067c0,%edi
  401eb2:	31 c0                	xor    %eax,%eax
  401eb4:	e8 b7 e4 ff ff       	call   400370 <printf@plt>
  401eb9:	49 83 c7 01          	add    $0x1,%r15
  401ebd:	49 83 ff 04          	cmp    $0x4,%r15
  401ec1:	75 d0                	jne    401e93 <main+0x1493>
  401ec3:	83 c3 01             	add    $0x1,%ebx
  401ec6:	49 83 c6 10          	add    $0x10,%r14
  401eca:	49 83 c5 10          	add    $0x10,%r13
  401ece:	83 fb 20             	cmp    $0x20,%ebx
  401ed1:	75 bd                	jne    401e90 <main+0x1490>
  401ed3:	0f b6 85 88 bf ff ff 	movzbl -0x4078(%rbp),%eax
  401eda:	48 83 ec 08          	sub    $0x8,%rsp
  401ede:	44 8b bd 10 bf ff ff 	mov    -0x40f0(%rbp),%r15d
  401ee5:	bf e0 67 40 00       	mov    $0x4067e0,%edi
  401eea:	48 8b 9d a0 be ff ff 	mov    -0x4160(%rbp),%rbx
  401ef1:	ff b5 78 bf ff ff    	push   -0x4088(%rbp)
  401ef7:	45 31 ed             	xor    %r13d,%r13d
  401efa:	48 8b 95 80 bf ff ff 	mov    -0x4080(%rbp),%rdx
  401f01:	ff b5 40 bf ff ff    	push   -0x40c0(%rbp)
  401f07:	48 8b b5 68 bf ff ff 	mov    -0x4098(%rbp),%rsi
  401f0e:	50                   	push   %rax
  401f0f:	0f b6 85 70 bf ff ff 	movzbl -0x4090(%rbp),%eax
  401f16:	50                   	push   %rax
  401f17:	31 c0                	xor    %eax,%eax
  401f19:	ff b5 68 c1 ff ff    	push   -0x3e98(%rbp)
  401f1f:	ff b5 e8 c0 ff ff    	push   -0x3f18(%rbp)
  401f25:	ff b5 60 c1 ff ff    	push   -0x3ea0(%rbp)
  401f2b:	4c 8b 8d e0 c0 ff ff 	mov    -0x3f20(%rbp),%r9
  401f32:	4c 8b 85 58 c1 ff ff 	mov    -0x3ea8(%rbp),%r8
  401f39:	48 8b 8d d8 c0 ff ff 	mov    -0x3f28(%rbp),%rcx
  401f40:	e8 2b e4 ff ff       	call   400370 <printf@plt>
  401f45:	48 83 c4 40          	add    $0x40,%rsp
  401f49:	4a 8b 8c ed 18 c1 ff ff 	mov    -0x3ee8(%rbp,%r13,8),%rcx
  401f51:	44 89 ee             	mov    %r13d,%esi
  401f54:	bf 50 68 40 00       	mov    $0x406850,%edi
  401f59:	31 c0                	xor    %eax,%eax
  401f5b:	4a 8b 94 ed 98 c0 ff ff 	mov    -0x3f68(%rbp,%r13,8),%rdx
  401f63:	49 83 c5 01          	add    $0x1,%r13
  401f67:	e8 04 e4 ff ff       	call   400370 <printf@plt>
  401f6c:	49 83 fd 08          	cmp    $0x8,%r13
  401f70:	75 d7                	jne    401f49 <main+0x1549>
  401f72:	8b b5 20 bf ff ff    	mov    -0x40e0(%rbp),%esi
  401f78:	01 b5 a4 bf ff ff    	add    %esi,-0x405c(%rbp)
  401f7e:	e9 0c f3 ff ff       	jmp    40128f <main+0x88f>
  401f83:	8b 95 4c bf ff ff    	mov    -0x40b4(%rbp),%edx
  401f89:	48 8d bd 10 c4 ff ff 	lea    -0x3bf0(%rbp),%rdi
  401f90:	be cd cc cc cc       	mov    $0xcccccccd,%esi
  401f95:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  401fa0:	89 d0                	mov    %edx,%eax
  401fa2:	46 8d 04 3a          	lea    (%rdx,%r15,1),%r8d
  401fa6:	48 83 c7 10          	add    $0x10,%rdi
  401faa:	48 0f af c6          	imul   %rsi,%rax
  401fae:	47 8d 0c 07          	lea    (%r15,%r8,1),%r9d
  401fb2:	43 8d 0c 0f          	lea    (%r15,%r9,1),%ecx
  401fb6:	41 89 ca             	mov    %ecx,%r10d
  401fb9:	48 c1 e8 24          	shr    $0x24,%rax
  401fbd:	8d 04 80             	lea    (%rax,%rax,4),%eax
  401fc0:	c1 e0 02             	shl    $0x2,%eax
  401fc3:	29 c2                	sub    %eax,%edx
  401fc5:	44 89 c0             	mov    %r8d,%eax
  401fc8:	c5 f9 6e 84 95 d0 ef ff ff 	vmovd  -0x1030(%rbp,%rdx,4),%xmm0
  401fd1:	48 0f af c6          	imul   %rsi,%rax
  401fd5:	41 8d 14 0f          	lea    (%r15,%rcx,1),%edx
  401fd9:	48 c1 e8 24          	shr    $0x24,%rax
  401fdd:	8d 04 80             	lea    (%rax,%rax,4),%eax
  401fe0:	c1 e0 02             	shl    $0x2,%eax
  401fe3:	41 29 c0             	sub    %eax,%r8d
  401fe6:	44 89 c8             	mov    %r9d,%eax
  401fe9:	c4 a3 79 22 84 85 d0 ef ff ff 01 	vpinsrd $0x1,-0x1030(%rbp,%r8,4),%xmm0,%xmm0
  401ff4:	48 0f af c6          	imul   %rsi,%rax
  401ff8:	48 c1 e8 24          	shr    $0x24,%rax
  401ffc:	8d 04 80             	lea    (%rax,%rax,4),%eax
  401fff:	c1 e0 02             	shl    $0x2,%eax
  402002:	41 29 c1             	sub    %eax,%r9d
  402005:	89 c8                	mov    %ecx,%eax
  402007:	c4 a1 79 6e 8c 8d d0 ef ff ff 	vmovd  -0x1030(%rbp,%r9,4),%xmm1
  402011:	48 0f af c6          	imul   %rsi,%rax
  402015:	48 c1 e8 24          	shr    $0x24,%rax
  402019:	8d 04 80             	lea    (%rax,%rax,4),%eax
  40201c:	c1 e0 02             	shl    $0x2,%eax
  40201f:	41 29 c2             	sub    %eax,%r10d
  402022:	48 8d 85 10 c6 ff ff 	lea    -0x39f0(%rbp),%rax
  402029:	c4 a3 71 22 8c 95 d0 ef ff ff 01 	vpinsrd $0x1,-0x1030(%rbp,%r10,4),%xmm1,%xmm1
  402034:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
  402038:	c5 f9 7f 47 f0       	vmovdqa %xmm0,-0x10(%rdi)
  40203d:	48 39 c7             	cmp    %rax,%rdi
  402040:	0f 85 5a ff ff ff    	jne    401fa0 <main+0x15a0>
  402046:	8b 85 e0 be ff ff    	mov    -0x4120(%rbp),%eax
  40204c:	44 8b 8c 85 d0 ef ff ff 	mov    -0x1030(%rbp,%rax,4),%r9d
  402054:	8b 85 d0 be ff ff    	mov    -0x4130(%rbp),%eax
  40205a:	44 8b 84 85 d0 ef ff ff 	mov    -0x1030(%rbp,%rax,4),%r8d
  402062:	8b 85 c8 be ff ff    	mov    -0x4138(%rbp),%eax
  402068:	8b b4 85 d0 ef ff ff 	mov    -0x1030(%rbp,%rax,4),%esi
  40206f:	8b 85 c0 be ff ff    	mov    -0x4140(%rbp),%eax
  402075:	8b 94 85 d0 ef ff ff 	mov    -0x1030(%rbp,%rax,4),%edx
  40207c:	8b 85 00 bf ff ff    	mov    -0x4100(%rbp),%eax
  402082:	44 8b 94 85 d0 ef ff ff 	mov    -0x1030(%rbp,%rax,4),%r10d
  40208a:	e9 c7 ed ff ff       	jmp    400e56 <main+0x456>
  40208f:	48 8b 85 68 bf ff ff 	mov    -0x4098(%rbp),%rax
  402096:	48 3d 00 08 00 00    	cmp    $0x800,%rax
  40209c:	0f 84 31 07 00 00    	je     4027d3 <main+0x1dd3>
  4020a2:	48 3d 10 08 00 00    	cmp    $0x810,%rax
  4020a8:	0f 84 d1 06 00 00    	je     40277f <main+0x1d7f>
  4020ae:	c6 85 88 bf ff ff 00 	movb   $0x0,-0x4078(%rbp)
  4020b5:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  4020bb:	b9 01 00 00 00       	mov    $0x1,%ecx
  4020c0:	ba 03 00 00 00       	mov    $0x3,%edx
  4020c5:	48 c7 85 98 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4068(%rbp)
  4020d0:	b8 02 00 00 00       	mov    $0x2,%eax
  4020d5:	41 ba 01 00 00 00    	mov    $0x1,%r10d
  4020db:	48 c7 85 90 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4070(%rbp)
  4020e6:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  4020f0:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  4020fb:	e9 8c f0 ff ff       	jmp    40118c <main+0x78c>
  402100:	45 84 ed             	test   %r13b,%r13b
  402103:	0f 85 52 06 00 00    	jne    40275b <main+0x1d5b>
  402109:	48 8b bd 68 bf ff ff 	mov    -0x4098(%rbp),%rdi
  402110:	48 39 bd 80 bf ff ff 	cmp    %rdi,-0x4080(%rbp)
  402117:	0f 85 fd f0 ff ff    	jne    40121a <main+0x81a>
  40211d:	c5 fe 6f 85 98 c0 ff ff 	vmovdqu -0x3f68(%rbp),%ymm0
  402125:	c5 fc 57 85 18 c1 ff ff 	vxorps -0x3ee8(%rbp),%ymm0,%ymm0
  40212d:	c4 e2 7d 17 c0       	vptest %ymm0,%ymm0
  402132:	75 2b                	jne    40215f <main+0x175f>
  402134:	c5 fe 6f 85 b8 c0 ff ff 	vmovdqu -0x3f48(%rbp),%ymm0
  40213c:	c5 fc 57 85 38 c1 ff ff 	vxorps -0x3ec8(%rbp),%ymm0,%ymm0
  402144:	c4 e2 7d 17 c0       	vptest %ymm0,%ymm0
  402149:	75 14                	jne    40215f <main+0x175f>
  40214b:	48 8b 85 58 c1 ff ff 	mov    -0x3ea8(%rbp),%rax
  402152:	48 39 85 d8 c0 ff ff 	cmp    %rax,-0x3f28(%rbp)
  402159:	0f 84 d5 06 00 00    	je     402834 <main+0x1e34>
  40215f:	c7 85 a0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4060(%rbp)
  402169:	bf 01 00 00 00       	mov    $0x1,%edi
  40216e:	b8 01 00 00 00       	mov    $0x1,%eax
  402173:	c5 f8 77             	vzeroupper
  402176:	e9 b3 f0 ff ff       	jmp    40122e <main+0x82e>
  40217b:	48 c7 85 98 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4068(%rbp)
  402186:	44 89 e9             	mov    %r13d,%ecx
  402189:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  40218f:	ba 03 00 00 00       	mov    $0x3,%edx
  402194:	48 c7 85 90 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4070(%rbp)
  40219f:	b8 03 00 00 00       	mov    $0x3,%eax
  4021a4:	41 ba 01 00 00 00    	mov    $0x1,%r10d
  4021aa:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  4021b4:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  4021bf:	c6 85 88 bf ff ff 00 	movb   $0x0,-0x4078(%rbp)
  4021c6:	e9 c1 ef ff ff       	jmp    40118c <main+0x78c>
  4021cb:	83 bd 58 bf ff ff 40 	cmpl   $0x40,-0x40a8(%rbp)
  4021d2:	0f 94 c2             	sete   %dl
  4021d5:	81 bd 60 bf ff ff 00 01 00 00 	cmpl   $0x100,-0x40a0(%rbp)
  4021df:	0f 94 c0             	sete   %al
  4021e2:	84 c2                	test   %al,%dl
  4021e4:	0f 84 a1 fa ff ff    	je     401c8b <main+0x128b>
  4021ea:	81 bd 64 bf ff ff 45 23 c1 7f 	cmpl   $0x7fc12345,-0x409c(%rbp)
  4021f4:	0f 85 91 fa ff ff    	jne    401c8b <main+0x128b>
  4021fa:	0f b6 c1             	movzbl %cl,%eax
  4021fd:	89 85 20 bf ff ff    	mov    %eax,-0x40e0(%rbp)
  402203:	41 bd 01 00 00 00    	mov    $0x1,%r13d
  402209:	e9 a1 fa ff ff       	jmp    401caf <main+0x12af>
  40220e:	c4 e1 f9 7e d0       	vmovq  %xmm2,%rax
  402213:	0f b6 b4 05 d0 df ff ff 	movzbl -0x2030(%rbp,%rax,1),%esi
  40221b:	40 38 b4 05 d0 ef ff ff 	cmp    %sil,-0x1030(%rbp,%rax,1)
  402223:	0f 85 fb 05 00 00    	jne    402824 <main+0x1e24>
  402229:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
  40222e:	48 83 fa 01          	cmp    $0x1,%rdx
  402232:	0f 84 ab fb ff ff    	je     401de3 <main+0x13e3>
  402238:	0f b6 bc 05 d1 ef ff ff 	movzbl -0x102f(%rbp,%rax,1),%edi
  402240:	48 8d 48 01          	lea    0x1(%rax),%rcx
  402244:	40 38 bc 05 d1 df ff ff 	cmp    %dil,-0x202f(%rbp,%rax,1)
  40224c:	0f 85 ec 01 00 00    	jne    40243e <main+0x1a3e>
  402252:	48 83 fa 02          	cmp    $0x2,%rdx
  402256:	0f 84 87 fb ff ff    	je     401de3 <main+0x13e3>
  40225c:	0f b6 b4 05 d2 ef ff ff 	movzbl -0x102e(%rbp,%rax,1),%esi
  402264:	48 8d 48 02          	lea    0x2(%rax),%rcx
  402268:	40 38 b4 05 d2 df ff ff 	cmp    %sil,-0x202e(%rbp,%rax,1)
  402270:	0f 85 c8 01 00 00    	jne    40243e <main+0x1a3e>
  402276:	48 83 fa 03          	cmp    $0x3,%rdx
  40227a:	0f 84 63 fb ff ff    	je     401de3 <main+0x13e3>
  402280:	0f b6 bc 05 d3 ef ff ff 	movzbl -0x102d(%rbp,%rax,1),%edi
  402288:	48 8d 48 03          	lea    0x3(%rax),%rcx
  40228c:	40 38 bc 05 d3 df ff ff 	cmp    %dil,-0x202d(%rbp,%rax,1)
  402294:	0f 85 a4 01 00 00    	jne    40243e <main+0x1a3e>
  40229a:	48 83 fa 04          	cmp    $0x4,%rdx
  40229e:	0f 84 3f fb ff ff    	je     401de3 <main+0x13e3>
  4022a4:	0f b6 b4 05 d4 ef ff ff 	movzbl -0x102c(%rbp,%rax,1),%esi
  4022ac:	48 8d 48 04          	lea    0x4(%rax),%rcx
  4022b0:	40 38 b4 05 d4 df ff ff 	cmp    %sil,-0x202c(%rbp,%rax,1)
  4022b8:	0f 85 80 01 00 00    	jne    40243e <main+0x1a3e>
  4022be:	48 83 fa 05          	cmp    $0x5,%rdx
  4022c2:	0f 84 1b fb ff ff    	je     401de3 <main+0x13e3>
  4022c8:	0f b6 bc 05 d5 ef ff ff 	movzbl -0x102b(%rbp,%rax,1),%edi
  4022d0:	48 8d 48 05          	lea    0x5(%rax),%rcx
  4022d4:	40 38 bc 05 d5 df ff ff 	cmp    %dil,-0x202b(%rbp,%rax,1)
  4022dc:	0f 85 5c 01 00 00    	jne    40243e <main+0x1a3e>
  4022e2:	48 83 fa 06          	cmp    $0x6,%rdx
  4022e6:	0f 84 f7 fa ff ff    	je     401de3 <main+0x13e3>
  4022ec:	0f b6 b4 05 d6 ef ff ff 	movzbl -0x102a(%rbp,%rax,1),%esi
  4022f4:	48 8d 48 06          	lea    0x6(%rax),%rcx
  4022f8:	40 38 b4 05 d6 df ff ff 	cmp    %sil,-0x202a(%rbp,%rax,1)
  402300:	0f 85 38 01 00 00    	jne    40243e <main+0x1a3e>
  402306:	48 83 fa 07          	cmp    $0x7,%rdx
  40230a:	0f 84 d3 fa ff ff    	je     401de3 <main+0x13e3>
  402310:	0f b6 bc 05 d7 ef ff ff 	movzbl -0x1029(%rbp,%rax,1),%edi
  402318:	48 8d 48 07          	lea    0x7(%rax),%rcx
  40231c:	40 38 bc 05 d7 df ff ff 	cmp    %dil,-0x2029(%rbp,%rax,1)
  402324:	0f 85 14 01 00 00    	jne    40243e <main+0x1a3e>
  40232a:	48 83 fa 08          	cmp    $0x8,%rdx
  40232e:	0f 84 af fa ff ff    	je     401de3 <main+0x13e3>
  402334:	0f b6 b4 05 d8 ef ff ff 	movzbl -0x1028(%rbp,%rax,1),%esi
  40233c:	48 8d 48 08          	lea    0x8(%rax),%rcx
  402340:	40 38 b4 05 d8 df ff ff 	cmp    %sil,-0x2028(%rbp,%rax,1)
  402348:	0f 85 f0 00 00 00    	jne    40243e <main+0x1a3e>
  40234e:	48 83 fa 09          	cmp    $0x9,%rdx
  402352:	0f 84 8b fa ff ff    	je     401de3 <main+0x13e3>
  402358:	0f b6 bc 05 d9 ef ff ff 	movzbl -0x1027(%rbp,%rax,1),%edi
  402360:	48 8d 48 09          	lea    0x9(%rax),%rcx
  402364:	40 38 bc 05 d9 df ff ff 	cmp    %dil,-0x2027(%rbp,%rax,1)
  40236c:	0f 85 cc 00 00 00    	jne    40243e <main+0x1a3e>
  402372:	48 83 fa 0a          	cmp    $0xa,%rdx
  402376:	0f 84 67 fa ff ff    	je     401de3 <main+0x13e3>
  40237c:	0f b6 b4 05 da ef ff ff 	movzbl -0x1026(%rbp,%rax,1),%esi
  402384:	48 8d 48 0a          	lea    0xa(%rax),%rcx
  402388:	40 38 b4 05 da df ff ff 	cmp    %sil,-0x2026(%rbp,%rax,1)
  402390:	0f 85 a8 00 00 00    	jne    40243e <main+0x1a3e>
  402396:	48 83 fa 0b          	cmp    $0xb,%rdx
  40239a:	0f 84 43 fa ff ff    	je     401de3 <main+0x13e3>
  4023a0:	0f b6 bc 05 db ef ff ff 	movzbl -0x1025(%rbp,%rax,1),%edi
  4023a8:	48 8d 48 0b          	lea    0xb(%rax),%rcx
  4023ac:	40 38 bc 05 db df ff ff 	cmp    %dil,-0x2025(%rbp,%rax,1)
  4023b4:	0f 85 84 00 00 00    	jne    40243e <main+0x1a3e>
  4023ba:	48 83 fa 0c          	cmp    $0xc,%rdx
  4023be:	0f 84 1f fa ff ff    	je     401de3 <main+0x13e3>
  4023c4:	0f b6 b4 05 dc ef ff ff 	movzbl -0x1024(%rbp,%rax,1),%esi
  4023cc:	48 8d 48 0c          	lea    0xc(%rax),%rcx
  4023d0:	40 38 b4 05 dc df ff ff 	cmp    %sil,-0x2024(%rbp,%rax,1)
  4023d8:	75 64                	jne    40243e <main+0x1a3e>
  4023da:	48 83 fa 0d          	cmp    $0xd,%rdx
  4023de:	0f 84 ff f9 ff ff    	je     401de3 <main+0x13e3>
  4023e4:	0f b6 bc 05 dd ef ff ff 	movzbl -0x1023(%rbp,%rax,1),%edi
  4023ec:	48 8d 48 0d          	lea    0xd(%rax),%rcx
  4023f0:	40 38 bc 05 dd df ff ff 	cmp    %dil,-0x2023(%rbp,%rax,1)
  4023f8:	75 44                	jne    40243e <main+0x1a3e>
  4023fa:	48 83 fa 0e          	cmp    $0xe,%rdx
  4023fe:	0f 84 df f9 ff ff    	je     401de3 <main+0x13e3>
  402404:	0f b6 b4 05 de ef ff ff 	movzbl -0x1022(%rbp,%rax,1),%esi
  40240c:	48 8d 48 0e          	lea    0xe(%rax),%rcx
  402410:	40 38 b4 05 de df ff ff 	cmp    %sil,-0x2022(%rbp,%rax,1)
  402418:	75 24                	jne    40243e <main+0x1a3e>
  40241a:	48 83 fa 0f          	cmp    $0xf,%rdx
  40241e:	0f 84 bf f9 ff ff    	je     401de3 <main+0x13e3>
  402424:	0f b6 bc 05 df ef ff ff 	movzbl -0x1021(%rbp,%rax,1),%edi
  40242c:	48 8d 48 0f          	lea    0xf(%rax),%rcx
  402430:	40 38 bc 05 df df ff ff 	cmp    %dil,-0x2021(%rbp,%rax,1)
  402438:	0f 84 a5 f9 ff ff    	je     401de3 <main+0x13e3>
  40243e:	31 c0                	xor    %eax,%eax
  402440:	ba c0 04 00 00       	mov    $0x4c0,%edx
  402445:	4c 89 f6             	mov    %r14,%rsi
  402448:	bf 20 67 40 00       	mov    $0x406720,%edi
  40244d:	48 89 8d 10 bf ff ff 	mov    %rcx,-0x40f0(%rbp)
  402454:	e8 17 df ff ff       	call   400370 <printf@plt>
  402459:	49 81 fe c0 04 00 00 	cmp    $0x4c0,%r14
  402460:	48 8b 8d 10 bf ff ff 	mov    -0x40f0(%rbp),%rcx
  402467:	0f 84 d2 f9 ff ff    	je     401e3f <main+0x143f>
  40246d:	e9 98 f9 ff ff       	jmp    401e0a <main+0x140a>
  402472:	c4 e1 f9 7e d0       	vmovq  %xmm2,%rax
  402477:	0f b6 b4 05 10 cb ff ff 	movzbl -0x34f0(%rbp,%rax,1),%esi
  40247f:	40 38 b4 05 50 c6 ff ff 	cmp    %sil,-0x39b0(%rbp,%rax,1)
  402487:	0f 85 9f 03 00 00    	jne    40282c <main+0x1e2c>
  40248d:	c4 e1 f9 7e ca       	vmovq  %xmm1,%rdx
  402492:	48 83 fa 01          	cmp    $0x1,%rdx
  402496:	0f 84 0e 02 00 00    	je     4026aa <main+0x1caa>
  40249c:	0f b6 bc 05 11 cb ff ff 	movzbl -0x34ef(%rbp,%rax,1),%edi
  4024a4:	4c 8d 70 01          	lea    0x1(%rax),%r14
  4024a8:	40 38 bc 05 51 c6 ff ff 	cmp    %dil,-0x39af(%rbp,%rax,1)
  4024b0:	0f 85 c1 f8 ff ff    	jne    401d77 <main+0x1377>
  4024b6:	48 83 fa 02          	cmp    $0x2,%rdx
  4024ba:	0f 84 ea 01 00 00    	je     4026aa <main+0x1caa>
  4024c0:	0f b6 b4 05 12 cb ff ff 	movzbl -0x34ee(%rbp,%rax,1),%esi
  4024c8:	4c 8d 70 02          	lea    0x2(%rax),%r14
  4024cc:	40 38 b4 05 52 c6 ff ff 	cmp    %sil,-0x39ae(%rbp,%rax,1)
  4024d4:	0f 85 9d f8 ff ff    	jne    401d77 <main+0x1377>
  4024da:	48 83 fa 03          	cmp    $0x3,%rdx
  4024de:	0f 84 c6 01 00 00    	je     4026aa <main+0x1caa>
  4024e4:	0f b6 bc 05 13 cb ff ff 	movzbl -0x34ed(%rbp,%rax,1),%edi
  4024ec:	4c 8d 70 03          	lea    0x3(%rax),%r14
  4024f0:	40 38 bc 05 53 c6 ff ff 	cmp    %dil,-0x39ad(%rbp,%rax,1)
  4024f8:	0f 85 79 f8 ff ff    	jne    401d77 <main+0x1377>
  4024fe:	48 83 fa 04          	cmp    $0x4,%rdx
  402502:	0f 84 a2 01 00 00    	je     4026aa <main+0x1caa>
  402508:	0f b6 b4 05 14 cb ff ff 	movzbl -0x34ec(%rbp,%rax,1),%esi
  402510:	4c 8d 70 04          	lea    0x4(%rax),%r14
  402514:	40 38 b4 05 54 c6 ff ff 	cmp    %sil,-0x39ac(%rbp,%rax,1)
  40251c:	0f 85 55 f8 ff ff    	jne    401d77 <main+0x1377>
  402522:	48 83 fa 05          	cmp    $0x5,%rdx
  402526:	0f 84 7e 01 00 00    	je     4026aa <main+0x1caa>
  40252c:	0f b6 bc 05 15 cb ff ff 	movzbl -0x34eb(%rbp,%rax,1),%edi
  402534:	4c 8d 70 05          	lea    0x5(%rax),%r14
  402538:	40 38 bc 05 55 c6 ff ff 	cmp    %dil,-0x39ab(%rbp,%rax,1)
  402540:	0f 85 31 f8 ff ff    	jne    401d77 <main+0x1377>
  402546:	48 83 fa 06          	cmp    $0x6,%rdx
  40254a:	0f 84 5a 01 00 00    	je     4026aa <main+0x1caa>
  402550:	0f b6 b4 05 16 cb ff ff 	movzbl -0x34ea(%rbp,%rax,1),%esi
  402558:	4c 8d 70 06          	lea    0x6(%rax),%r14
  40255c:	40 38 b4 05 56 c6 ff ff 	cmp    %sil,-0x39aa(%rbp,%rax,1)
  402564:	0f 85 0d f8 ff ff    	jne    401d77 <main+0x1377>
  40256a:	48 83 fa 07          	cmp    $0x7,%rdx
  40256e:	0f 84 36 01 00 00    	je     4026aa <main+0x1caa>
  402574:	0f b6 bc 05 17 cb ff ff 	movzbl -0x34e9(%rbp,%rax,1),%edi
  40257c:	4c 8d 70 07          	lea    0x7(%rax),%r14
  402580:	40 38 bc 05 57 c6 ff ff 	cmp    %dil,-0x39a9(%rbp,%rax,1)
  402588:	0f 85 e9 f7 ff ff    	jne    401d77 <main+0x1377>
  40258e:	48 83 fa 08          	cmp    $0x8,%rdx
  402592:	0f 84 12 01 00 00    	je     4026aa <main+0x1caa>
  402598:	0f b6 b4 05 18 cb ff ff 	movzbl -0x34e8(%rbp,%rax,1),%esi
  4025a0:	4c 8d 70 08          	lea    0x8(%rax),%r14
  4025a4:	40 38 b4 05 58 c6 ff ff 	cmp    %sil,-0x39a8(%rbp,%rax,1)
  4025ac:	0f 85 c5 f7 ff ff    	jne    401d77 <main+0x1377>
  4025b2:	48 83 fa 09          	cmp    $0x9,%rdx
  4025b6:	0f 84 ee 00 00 00    	je     4026aa <main+0x1caa>
  4025bc:	0f b6 bc 05 19 cb ff ff 	movzbl -0x34e7(%rbp,%rax,1),%edi
  4025c4:	4c 8d 70 09          	lea    0x9(%rax),%r14
  4025c8:	40 38 bc 05 59 c6 ff ff 	cmp    %dil,-0x39a7(%rbp,%rax,1)
  4025d0:	0f 85 a1 f7 ff ff    	jne    401d77 <main+0x1377>
  4025d6:	48 83 fa 0a          	cmp    $0xa,%rdx
  4025da:	0f 84 ca 00 00 00    	je     4026aa <main+0x1caa>
  4025e0:	0f b6 b4 05 1a cb ff ff 	movzbl -0x34e6(%rbp,%rax,1),%esi
  4025e8:	4c 8d 70 0a          	lea    0xa(%rax),%r14
  4025ec:	40 38 b4 05 5a c6 ff ff 	cmp    %sil,-0x39a6(%rbp,%rax,1)
  4025f4:	0f 85 7d f7 ff ff    	jne    401d77 <main+0x1377>
  4025fa:	48 83 fa 0b          	cmp    $0xb,%rdx
  4025fe:	0f 84 a6 00 00 00    	je     4026aa <main+0x1caa>
  402604:	0f b6 bc 05 1b cb ff ff 	movzbl -0x34e5(%rbp,%rax,1),%edi
  40260c:	4c 8d 70 0b          	lea    0xb(%rax),%r14
  402610:	40 38 bc 05 5b c6 ff ff 	cmp    %dil,-0x39a5(%rbp,%rax,1)
  402618:	0f 85 59 f7 ff ff    	jne    401d77 <main+0x1377>
  40261e:	48 83 fa 0c          	cmp    $0xc,%rdx
  402622:	0f 84 82 00 00 00    	je     4026aa <main+0x1caa>
  402628:	0f b6 b4 05 1c cb ff ff 	movzbl -0x34e4(%rbp,%rax,1),%esi
  402630:	4c 8d 70 0c          	lea    0xc(%rax),%r14
  402634:	40 38 b4 05 5c c6 ff ff 	cmp    %sil,-0x39a4(%rbp,%rax,1)
  40263c:	0f 85 35 f7 ff ff    	jne    401d77 <main+0x1377>
  402642:	48 83 fa 0d          	cmp    $0xd,%rdx
  402646:	74 62                	je     4026aa <main+0x1caa>
  402648:	0f b6 bc 05 1d cb ff ff 	movzbl -0x34e3(%rbp,%rax,1),%edi
  402650:	4c 8d 70 0d          	lea    0xd(%rax),%r14
  402654:	40 38 bc 05 5d c6 ff ff 	cmp    %dil,-0x39a3(%rbp,%rax,1)
  40265c:	0f 85 15 f7 ff ff    	jne    401d77 <main+0x1377>
  402662:	48 83 fa 0e          	cmp    $0xe,%rdx
  402666:	74 42                	je     4026aa <main+0x1caa>
  402668:	0f b6 b4 05 1e cb ff ff 	movzbl -0x34e2(%rbp,%rax,1),%esi
  402670:	4c 8d 70 0e          	lea    0xe(%rax),%r14
  402674:	40 38 b4 05 5e c6 ff ff 	cmp    %sil,-0x39a2(%rbp,%rax,1)
  40267c:	0f 85 f5 f6 ff ff    	jne    401d77 <main+0x1377>
  402682:	48 83 fa 0f          	cmp    $0xf,%rdx
  402686:	74 22                	je     4026aa <main+0x1caa>
  402688:	0f b6 bc 05 1f cb ff ff 	movzbl -0x34e1(%rbp,%rax,1),%edi
  402690:	4c 8d 70 0f          	lea    0xf(%rax),%r14
  402694:	40 38 bc 05 5f c6 ff ff 	cmp    %dil,-0x39a1(%rbp,%rax,1)
  40269c:	b8 c0 04 00 00       	mov    $0x4c0,%eax
  4026a1:	4c 0f 44 f0          	cmove  %rax,%r14
  4026a5:	e9 cd f6 ff ff       	jmp    401d77 <main+0x1377>
  4026aa:	41 be c0 04 00 00    	mov    $0x4c0,%r14d
  4026b0:	e9 c2 f6 ff ff       	jmp    401d77 <main+0x1377>
  4026b5:	4c 8b ad c8 bf ff ff 	mov    -0x4038(%rbp),%r13
  4026bc:	44 89 bd 10 bf ff ff 	mov    %r15d,-0x40f0(%rbp)
  4026c3:	48 89 9d a0 be ff ff 	mov    %rbx,-0x4160(%rbp)
  4026ca:	48 8d 9d 10 cb ff ff 	lea    -0x34f0(%rbp),%rbx
  4026d1:	4d 89 ef             	mov    %r13,%r15
  4026d4:	45 31 ed             	xor    %r13d,%r13d
  4026d7:	45 31 f6             	xor    %r14d,%r14d
  4026da:	43 8b 8c b7 80 02 00 00 	mov    0x280(%r15,%r14,4),%ecx
  4026e2:	44 89 f2             	mov    %r14d,%edx
  4026e5:	44 89 ee             	mov    %r13d,%esi
  4026e8:	31 c0                	xor    %eax,%eax
  4026ea:	46 8b 84 b3 80 02 00 00 	mov    0x280(%rbx,%r14,4),%r8d
  4026f2:	bf c0 67 40 00       	mov    $0x4067c0,%edi
  4026f7:	49 83 c6 01          	add    $0x1,%r14
  4026fb:	e8 70 dc ff ff       	call   400370 <printf@plt>
  402700:	49 83 fe 04          	cmp    $0x4,%r14
  402704:	75 d4                	jne    4026da <main+0x1cda>
  402706:	41 83 c5 01          	add    $0x1,%r13d
  40270a:	49 83 c7 10          	add    $0x10,%r15
  40270e:	48 83 c3 10          	add    $0x10,%rbx
  402712:	41 83 fd 20          	cmp    $0x20,%r13d
  402716:	75 bf                	jne    4026d7 <main+0x1cd7>
  402718:	e9 b6 f7 ff ff       	jmp    401ed3 <main+0x14d3>
  40271d:	83 bd 58 bf ff ff 40 	cmpl   $0x40,-0x40a8(%rbp)
  402724:	0f 94 c2             	sete   %dl
  402727:	81 bd 60 bf ff ff 00 01 00 00 	cmpl   $0x100,-0x40a0(%rbp)
  402731:	0f 94 c0             	sete   %al
  402734:	84 c2                	test   %al,%dl
  402736:	0f 84 3b eb ff ff    	je     401277 <main+0x877>
  40273c:	81 bd 64 bf ff ff 45 23 c1 7f 	cmpl   $0x7fc12345,-0x409c(%rbp)
  402746:	0f 85 2b eb ff ff    	jne    401277 <main+0x877>
  40274c:	c7 85 20 bf ff ff 01 00 00 00 	movl   $0x1,-0x40e0(%rbp)
  402756:	e9 a8 fa ff ff       	jmp    402203 <main+0x1803>
  40275b:	48 8b bd 78 bf ff ff 	mov    -0x4088(%rbp),%rdi
  402762:	48 39 bd 40 bf ff ff 	cmp    %rdi,-0x40c0(%rbp)
  402769:	40 0f 95 c7          	setne  %dil
  40276d:	0f 95 c0             	setne  %al
  402770:	40 0f b6 ff          	movzbl %dil,%edi
  402774:	89 bd a0 bf ff ff    	mov    %edi,-0x4060(%rbp)
  40277a:	e9 af ea ff ff       	jmp    40122e <main+0x82e>
  40277f:	c6 85 88 bf ff ff 00 	movb   $0x0,-0x4078(%rbp)
  402786:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  40278c:	0f b6 8d 70 bf ff ff 	movzbl -0x4090(%rbp),%ecx
  402793:	ba 03 00 00 00       	mov    $0x3,%edx
  402798:	48 c7 85 98 bf ff ff 94 65 40 00 	movq   $0x406594,-0x4068(%rbp)
  4027a3:	b8 01 00 00 00       	mov    $0x1,%eax
  4027a8:	41 ba 01 00 00 00    	mov    $0x1,%r10d
  4027ae:	48 c7 85 90 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4070(%rbp)
  4027b9:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  4027c3:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  4027ce:	e9 b9 e9 ff ff       	jmp    40118c <main+0x78c>
  4027d3:	c6 85 88 bf ff ff 00 	movb   $0x0,-0x4078(%rbp)
  4027da:	41 b8 01 00 00 00    	mov    $0x1,%r8d
  4027e0:	0f b6 8d 70 bf ff ff 	movzbl -0x4090(%rbp),%ecx
  4027e7:	ba 03 00 00 00       	mov    $0x3,%edx
  4027ec:	48 c7 85 98 bf ff ff a6 65 40 00 	movq   $0x4065a6,-0x4068(%rbp)
  4027f7:	31 c0                	xor    %eax,%eax
  4027f9:	41 ba 01 00 00 00    	mov    $0x1,%r10d
  4027ff:	48 c7 85 90 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4070(%rbp)
  40280a:	c7 85 b0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4050(%rbp)
  402814:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  40281f:	e9 68 e9 ff ff       	jmp    40118c <main+0x78c>
  402824:	48 89 c1             	mov    %rax,%rcx
  402827:	e9 12 fc ff ff       	jmp    40243e <main+0x1a3e>
  40282c:	49 89 c6             	mov    %rax,%r14
  40282f:	e9 43 f5 ff ff       	jmp    401d77 <main+0x1377>
  402834:	48 8b 85 60 c1 ff ff 	mov    -0x3ea0(%rbp),%rax
  40283b:	48 39 85 e0 c0 ff ff 	cmp    %rax,-0x3f20(%rbp)
  402842:	0f 85 17 f9 ff ff    	jne    40215f <main+0x175f>
  402848:	48 8b 85 68 c1 ff ff 	mov    -0x3e98(%rbp),%rax
  40284f:	48 39 85 e8 c0 ff ff 	cmp    %rax,-0x3f18(%rbp)
  402856:	44 0f b6 9d 70 bf ff ff 	movzbl -0x4090(%rbp),%r11d
  40285e:	0f 94 c0             	sete   %al
  402861:	44 38 9d 88 bf ff ff 	cmp    %r11b,-0x4078(%rbp)
  402868:	40 0f 94 c7          	sete   %dil
  40286c:	21 f8                	and    %edi,%eax
  40286e:	83 f0 01             	xor    $0x1,%eax
  402871:	0f b6 f8             	movzbl %al,%edi
  402874:	89 bd a0 bf ff ff    	mov    %edi,-0x4060(%rbp)
  40287a:	c5 f8 77             	vzeroupper
  40287d:	e9 ac e9 ff ff       	jmp    40122e <main+0x82e>
  402882:	8b 85 a4 bf ff ff    	mov    -0x405c(%rbp),%eax
  402888:	83 f8 0b             	cmp    $0xb,%eax
  40288b:	76 0e                	jbe    40289b <main+0x1e9b>
  40288d:	83 c0 01             	add    $0x1,%eax
  402890:	89 85 a4 bf ff ff    	mov    %eax,-0x405c(%rbp)
  402896:	e9 01 f2 ff ff       	jmp    401a9c <main+0x109c>
  40289b:	8b 85 f0 bf ff ff    	mov    -0x4010(%rbp),%eax
  4028a1:	44 8b 8d 60 bf ff ff 	mov    -0x40a0(%rbp),%r9d
  4028a8:	31 db                	xor    %ebx,%ebx
  4028aa:	bf b0 66 40 00       	mov    $0x4066b0,%edi
  4028af:	44 8b 85 a0 bf ff ff 	mov    -0x4060(%rbp),%r8d
  4028b6:	8b 8d 64 bf ff ff    	mov    -0x409c(%rbp),%ecx
  4028bc:	8b 95 1c bf ff ff    	mov    -0x40e4(%rbp),%edx
  4028c2:	8b b5 4c bf ff ff    	mov    -0x40b4(%rbp),%esi
  4028c8:	50                   	push   %rax
  4028c9:	8b 85 68 bf ff ff    	mov    -0x4098(%rbp),%eax
  4028cf:	50                   	push   %rax
  4028d0:	8b 85 28 bf ff ff    	mov    -0x40d8(%rbp),%eax
  4028d6:	50                   	push   %rax
  4028d7:	8b 85 40 bf ff ff    	mov    -0x40c0(%rbp),%eax
  4028dd:	50                   	push   %rax
  4028de:	31 c0                	xor    %eax,%eax
  4028e0:	ff b5 88 bf ff ff    	push   -0x4078(%rbp)
  4028e6:	ff b5 b0 bf ff ff    	push   -0x4050(%rbp)
  4028ec:	e8 7f da ff ff       	call   400370 <printf@plt>
  4028f1:	b8 10 00 00 00       	mov    $0x10,%eax
  4028f6:	48 83 c4 30          	add    $0x30,%rsp
  4028fa:	c5 f9 6f 15 1e 45 00 00 	vmovdqa 0x451e(%rip),%xmm2        # 406e20 <typeinfo for Boundary+0x10>
  402902:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
  402907:	48 c7 c0 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rax
  40290e:	c5 f9 6f 0d 1a 45 00 00 	vmovdqa 0x451a(%rip),%xmm1        # 406e30 <typeinfo for Boundary+0x20>
  402916:	c5 d1 ef ed          	vpxor  %xmm5,%xmm5,%xmm5
  40291a:	c4 e1 f9 6e d8       	vmovq  %rax,%xmm3
  40291f:	48 8b 85 c8 bf ff ff 	mov    -0x4038(%rbp),%rax
  402926:	c5 d9 6c e4          	vpunpcklqdq %xmm4,%xmm4,%xmm4
  40292a:	c5 e1 6c db          	vpunpcklqdq %xmm3,%xmm3,%xmm3
  40292e:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  402935:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  402940:	c5 f9 6f 04 03       	vmovdqa (%rbx,%rax,1),%xmm0
  402945:	c5 f9 74 84 2b 10 cb ff ff 	vpcmpeqb -0x34f0(%rbx,%rbp,1),%xmm0,%xmm0
  40294e:	c5 f9 74 c5          	vpcmpeqb %xmm5,%xmm0,%xmm0
  402952:	c4 e2 79 17 c0       	vptest %xmm0,%xmm0
  402957:	0f 85 70 04 00 00    	jne    402dcd <main+0x23cd>
  40295d:	48 83 c3 10          	add    $0x10,%rbx
  402961:	c5 f1 d4 cc          	vpaddq %xmm4,%xmm1,%xmm1
  402965:	c5 e9 d4 d3          	vpaddq %xmm3,%xmm2,%xmm2
  402969:	48 81 fb c0 04 00 00 	cmp    $0x4c0,%rbx
  402970:	75 ce                	jne    402940 <main+0x1f40>
  402972:	be 10 00 00 00       	mov    $0x10,%esi
  402977:	48 c7 c7 f0 ff ff ff 	mov    $0xfffffffffffffff0,%rdi
  40297e:	c5 f9 6f 15 ba 44 00 00 	vmovdqa 0x44ba(%rip),%xmm2        # 406e40 <typeinfo for Boundary+0x30>
  402986:	c5 f9 6f 0d a2 44 00 00 	vmovdqa 0x44a2(%rip),%xmm1        # 406e30 <typeinfo for Boundary+0x20>
  40298e:	c4 e1 f9 6e e6       	vmovq  %rsi,%xmm4
  402993:	c4 e1 f9 6e df       	vmovq  %rdi,%xmm3
  402998:	c5 d1 ef ed          	vpxor  %xmm5,%xmm5,%xmm5
  40299c:	31 c0                	xor    %eax,%eax
  40299e:	48 8b 95 b8 bf ff ff 	mov    -0x4048(%rbp),%rdx
  4029a5:	c5 d9 6c e4          	vpunpcklqdq %xmm4,%xmm4,%xmm4
  4029a9:	c5 e1 6c db          	vpunpcklqdq %xmm3,%xmm3,%xmm3
  4029ad:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  4029b5:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  4029c0:	c5 f9 6f 04 02       	vmovdqa (%rdx,%rax,1),%xmm0
  4029c5:	c5 f9 74 84 05 d0 ef ff ff 	vpcmpeqb -0x1030(%rbp,%rax,1),%xmm0,%xmm0
  4029ce:	c5 f9 74 c5          	vpcmpeqb %xmm5,%xmm0,%xmm0
  4029d2:	c4 e2 79 17 c0       	vptest %xmm0,%xmm0
  4029d7:	0f 85 97 01 00 00    	jne    402b74 <main+0x2174>
  4029dd:	48 83 c0 10          	add    $0x10,%rax
  4029e1:	c5 f1 d4 cc          	vpaddq %xmm4,%xmm1,%xmm1
  4029e5:	c5 e9 d4 d3          	vpaddq %xmm3,%xmm2,%xmm2
  4029e9:	48 3d 00 10 00 00    	cmp    $0x1000,%rax
  4029ef:	75 cf                	jne    4029c0 <main+0x1fc0>
  4029f1:	b9 00 10 00 00       	mov    $0x1000,%ecx
  4029f6:	ba c0 04 00 00       	mov    $0x4c0,%edx
  4029fb:	48 89 de             	mov    %rbx,%rsi
  4029fe:	31 c0                	xor    %eax,%eax
  402a00:	bf 20 67 40 00       	mov    $0x406720,%edi
  402a05:	41 bd 00 10 00 00    	mov    $0x1000,%r13d
  402a0b:	e8 60 d9 ff ff       	call   400370 <printf@plt>
  402a10:	48 81 fb c0 04 00 00 	cmp    $0x4c0,%rbx
  402a17:	74 43                	je     402a5c <main+0x205c>
  402a19:	0f b6 94 1d 10 cb ff ff 	movzbl -0x34f0(%rbp,%rbx,1),%edx
  402a21:	0f b6 b4 1d 50 c6 ff ff 	movzbl -0x39b0(%rbp,%rbx,1),%esi
  402a29:	31 c0                	xor    %eax,%eax
  402a2b:	bf 70 67 40 00       	mov    $0x406770,%edi
  402a30:	e8 3b d9 ff ff       	call   400370 <printf@plt>
  402a35:	49 81 fd 00 10 00 00 	cmp    $0x1000,%r13
  402a3c:	74 1e                	je     402a5c <main+0x205c>
  402a3e:	42 0f b6 94 2d d0 ef ff ff 	movzbl -0x1030(%rbp,%r13,1),%edx
  402a47:	bf 98 67 40 00       	mov    $0x406798,%edi
  402a4c:	31 c0                	xor    %eax,%eax
  402a4e:	42 0f b6 b4 2d d0 df ff ff 	movzbl -0x2030(%rbp,%r13,1),%esi
  402a57:	e8 14 d9 ff ff       	call   400370 <printf@plt>
  402a5c:	4c 8b ad c8 bf ff ff 	mov    -0x4038(%rbp),%r13
  402a63:	4c 89 b5 20 bf ff ff 	mov    %r14,-0x40e0(%rbp)
  402a6a:	45 31 ff             	xor    %r15d,%r15d
  402a6d:	4d 89 ee             	mov    %r13,%r14
  402a70:	4c 8d ad 10 cb ff ff 	lea    -0x34f0(%rbp),%r13
  402a77:	66 0f 1f 84 00 00 00 00 00 	nopw   0x0(%rax,%rax,1)
  402a80:	31 db                	xor    %ebx,%ebx
  402a82:	41 8b 8c 9e 80 02 00 00 	mov    0x280(%r14,%rbx,4),%ecx
  402a8a:	45 8b 84 9d 80 02 00 00 	mov    0x280(%r13,%rbx,4),%r8d
  402a92:	44 39 c1             	cmp    %r8d,%ecx
  402a95:	74 11                	je     402aa8 <main+0x20a8>
  402a97:	89 da                	mov    %ebx,%edx
  402a99:	44 89 fe             	mov    %r15d,%esi
  402a9c:	bf c0 67 40 00       	mov    $0x4067c0,%edi
  402aa1:	31 c0                	xor    %eax,%eax
  402aa3:	e8 c8 d8 ff ff       	call   400370 <printf@plt>
  402aa8:	48 83 c3 01          	add    $0x1,%rbx
  402aac:	48 83 fb 04          	cmp    $0x4,%rbx
  402ab0:	75 d0                	jne    402a82 <main+0x2082>
  402ab2:	41 83 c7 01          	add    $0x1,%r15d
  402ab6:	49 83 c6 10          	add    $0x10,%r14
  402aba:	49 83 c5 10          	add    $0x10,%r13
  402abe:	41 83 ff 20          	cmp    $0x20,%r15d
  402ac2:	75 bc                	jne    402a80 <main+0x2080>
  402ac4:	0f b6 85 50 bf ff ff 	movzbl -0x40b0(%rbp),%eax
  402acb:	48 83 ec 08          	sub    $0x8,%rsp
  402acf:	31 db                	xor    %ebx,%ebx
  402ad1:	4c 8b b5 20 bf ff ff 	mov    -0x40e0(%rbp),%r14
  402ad8:	ff b5 70 bf ff ff    	push   -0x4090(%rbp)
  402ade:	48 8b 95 80 bf ff ff 	mov    -0x4080(%rbp),%rdx
  402ae5:	bf e0 67 40 00       	mov    $0x4067e0,%edi
  402aea:	48 8b b5 78 bf ff ff 	mov    -0x4088(%rbp),%rsi
  402af1:	ff b5 58 bf ff ff    	push   -0x40a8(%rbp)
  402af7:	50                   	push   %rax
  402af8:	0f b6 85 98 bf ff ff 	movzbl -0x4068(%rbp),%eax
  402aff:	50                   	push   %rax
  402b00:	31 c0                	xor    %eax,%eax
  402b02:	ff b5 68 c1 ff ff    	push   -0x3e98(%rbp)
  402b08:	ff b5 e8 c0 ff ff    	push   -0x3f18(%rbp)
  402b0e:	ff b5 60 c1 ff ff    	push   -0x3ea0(%rbp)
  402b14:	4c 8b 8d e0 c0 ff ff 	mov    -0x3f20(%rbp),%r9
  402b1b:	4c 8b 85 58 c1 ff ff 	mov    -0x3ea8(%rbp),%r8
  402b22:	48 8b 8d d8 c0 ff ff 	mov    -0x3f28(%rbp),%rcx
  402b29:	e8 42 d8 ff ff       	call   400370 <printf@plt>
  402b2e:	48 83 c4 40          	add    $0x40,%rsp
  402b32:	0f 1f 00             	nopl   (%rax)
  402b35:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)
  402b40:	48 8b 8c dd 18 c1 ff ff 	mov    -0x3ee8(%rbp,%rbx,8),%rcx
  402b48:	89 de                	mov    %ebx,%esi
  402b4a:	bf 50 68 40 00       	mov    $0x406850,%edi
  402b4f:	31 c0                	xor    %eax,%eax
  402b51:	48 8b 94 dd 98 c0 ff ff 	mov    -0x3f68(%rbp,%rbx,8),%rdx
  402b59:	48 83 c3 01          	add    $0x1,%rbx
  402b5d:	e8 0e d8 ff ff       	call   400370 <printf@plt>
  402b62:	48 83 fb 08          	cmp    $0x8,%rbx
  402b66:	75 d8                	jne    402b40 <main+0x2140>
  402b68:	83 85 a4 bf ff ff 01 	addl   $0x1,-0x405c(%rbp)
  402b6f:	e9 28 ef ff ff       	jmp    401a9c <main+0x109c>
  402b74:	c4 e1 f9 7e c8       	vmovq  %xmm1,%rax
  402b79:	0f b6 b4 05 d0 df ff ff 	movzbl -0x2030(%rbp,%rax,1),%esi
  402b81:	40 38 b4 05 d0 ef ff ff 	cmp    %sil,-0x1030(%rbp,%rax,1)
  402b89:	0f 85 66 06 00 00    	jne    4031f5 <main+0x27f5>
  402b8f:	c4 e1 f9 7e d2       	vmovq  %xmm2,%rdx
  402b94:	48 83 fa 01          	cmp    $0x1,%rdx
  402b98:	0f 84 53 fe ff ff    	je     4029f1 <main+0x1ff1>
  402b9e:	0f b6 bc 05 d1 ef ff ff 	movzbl -0x102f(%rbp,%rax,1),%edi
  402ba6:	4c 8d 68 01          	lea    0x1(%rax),%r13
  402baa:	40 38 bc 05 d1 df ff ff 	cmp    %dil,-0x202f(%rbp,%rax,1)
  402bb2:	0f 85 ec 01 00 00    	jne    402da4 <main+0x23a4>
  402bb8:	48 83 fa 02          	cmp    $0x2,%rdx
  402bbc:	0f 84 2f fe ff ff    	je     4029f1 <main+0x1ff1>
  402bc2:	0f b6 b4 05 d2 ef ff ff 	movzbl -0x102e(%rbp,%rax,1),%esi
  402bca:	4c 8d 68 02          	lea    0x2(%rax),%r13
  402bce:	40 38 b4 05 d2 df ff ff 	cmp    %sil,-0x202e(%rbp,%rax,1)
  402bd6:	0f 85 c8 01 00 00    	jne    402da4 <main+0x23a4>
  402bdc:	48 83 fa 03          	cmp    $0x3,%rdx
  402be0:	0f 84 0b fe ff ff    	je     4029f1 <main+0x1ff1>
  402be6:	0f b6 bc 05 d3 ef ff ff 	movzbl -0x102d(%rbp,%rax,1),%edi
  402bee:	4c 8d 68 03          	lea    0x3(%rax),%r13
  402bf2:	40 38 bc 05 d3 df ff ff 	cmp    %dil,-0x202d(%rbp,%rax,1)
  402bfa:	0f 85 a4 01 00 00    	jne    402da4 <main+0x23a4>
  402c00:	48 83 fa 04          	cmp    $0x4,%rdx
  402c04:	0f 84 e7 fd ff ff    	je     4029f1 <main+0x1ff1>
  402c0a:	0f b6 b4 05 d4 ef ff ff 	movzbl -0x102c(%rbp,%rax,1),%esi
  402c12:	4c 8d 68 04          	lea    0x4(%rax),%r13
  402c16:	40 38 b4 05 d4 df ff ff 	cmp    %sil,-0x202c(%rbp,%rax,1)
  402c1e:	0f 85 80 01 00 00    	jne    402da4 <main+0x23a4>
  402c24:	48 83 fa 05          	cmp    $0x5,%rdx
  402c28:	0f 84 c3 fd ff ff    	je     4029f1 <main+0x1ff1>
  402c2e:	0f b6 bc 05 d5 df ff ff 	movzbl -0x202b(%rbp,%rax,1),%edi
  402c36:	4c 8d 68 05          	lea    0x5(%rax),%r13
  402c3a:	40 38 bc 05 d5 ef ff ff 	cmp    %dil,-0x102b(%rbp,%rax,1)
  402c42:	0f 85 5c 01 00 00    	jne    402da4 <main+0x23a4>
  402c48:	48 83 fa 06          	cmp    $0x6,%rdx
  402c4c:	0f 84 9f fd ff ff    	je     4029f1 <main+0x1ff1>
  402c52:	0f b6 b4 05 d6 ef ff ff 	movzbl -0x102a(%rbp,%rax,1),%esi
  402c5a:	4c 8d 68 06          	lea    0x6(%rax),%r13
  402c5e:	40 38 b4 05 d6 df ff ff 	cmp    %sil,-0x202a(%rbp,%rax,1)
  402c66:	0f 85 38 01 00 00    	jne    402da4 <main+0x23a4>
  402c6c:	48 83 fa 07          	cmp    $0x7,%rdx
  402c70:	0f 84 7b fd ff ff    	je     4029f1 <main+0x1ff1>
  402c76:	0f b6 bc 05 d7 df ff ff 	movzbl -0x2029(%rbp,%rax,1),%edi
  402c7e:	4c 8d 68 07          	lea    0x7(%rax),%r13
  402c82:	40 38 bc 05 d7 ef ff ff 	cmp    %dil,-0x1029(%rbp,%rax,1)
  402c8a:	0f 85 14 01 00 00    	jne    402da4 <main+0x23a4>
  402c90:	48 83 fa 08          	cmp    $0x8,%rdx
  402c94:	0f 84 57 fd ff ff    	je     4029f1 <main+0x1ff1>
  402c9a:	0f b6 b4 05 d8 ef ff ff 	movzbl -0x1028(%rbp,%rax,1),%esi
  402ca2:	4c 8d 68 08          	lea    0x8(%rax),%r13
  402ca6:	40 38 b4 05 d8 df ff ff 	cmp    %sil,-0x2028(%rbp,%rax,1)
  402cae:	0f 85 f0 00 00 00    	jne    402da4 <main+0x23a4>
  402cb4:	48 83 fa 09          	cmp    $0x9,%rdx
  402cb8:	0f 84 33 fd ff ff    	je     4029f1 <main+0x1ff1>
  402cbe:	0f b6 bc 05 d9 ef ff ff 	movzbl -0x1027(%rbp,%rax,1),%edi
  402cc6:	4c 8d 68 09          	lea    0x9(%rax),%r13
  402cca:	40 38 bc 05 d9 df ff ff 	cmp    %dil,-0x2027(%rbp,%rax,1)
  402cd2:	0f 85 cc 00 00 00    	jne    402da4 <main+0x23a4>
  402cd8:	48 83 fa 0a          	cmp    $0xa,%rdx
  402cdc:	0f 84 0f fd ff ff    	je     4029f1 <main+0x1ff1>
  402ce2:	0f b6 b4 05 da ef ff ff 	movzbl -0x1026(%rbp,%rax,1),%esi
  402cea:	4c 8d 68 0a          	lea    0xa(%rax),%r13
  402cee:	40 38 b4 05 da df ff ff 	cmp    %sil,-0x2026(%rbp,%rax,1)
  402cf6:	0f 85 a8 00 00 00    	jne    402da4 <main+0x23a4>
  402cfc:	48 83 fa 0b          	cmp    $0xb,%rdx
  402d00:	0f 84 eb fc ff ff    	je     4029f1 <main+0x1ff1>
  402d06:	0f b6 bc 05 db ef ff ff 	movzbl -0x1025(%rbp,%rax,1),%edi
  402d0e:	4c 8d 68 0b          	lea    0xb(%rax),%r13
  402d12:	40 38 bc 05 db df ff ff 	cmp    %dil,-0x2025(%rbp,%rax,1)
  402d1a:	0f 85 84 00 00 00    	jne    402da4 <main+0x23a4>
  402d20:	48 83 fa 0c          	cmp    $0xc,%rdx
  402d24:	0f 84 c7 fc ff ff    	je     4029f1 <main+0x1ff1>
  402d2a:	0f b6 b4 05 dc ef ff ff 	movzbl -0x1024(%rbp,%rax,1),%esi
  402d32:	4c 8d 68 0c          	lea    0xc(%rax),%r13
  402d36:	40 38 b4 05 dc df ff ff 	cmp    %sil,-0x2024(%rbp,%rax,1)
  402d3e:	75 64                	jne    402da4 <main+0x23a4>
  402d40:	48 83 fa 0d          	cmp    $0xd,%rdx
  402d44:	0f 84 a7 fc ff ff    	je     4029f1 <main+0x1ff1>
  402d4a:	0f b6 bc 05 dd df ff ff 	movzbl -0x2023(%rbp,%rax,1),%edi
  402d52:	4c 8d 68 0d          	lea    0xd(%rax),%r13
  402d56:	40 38 bc 05 dd ef ff ff 	cmp    %dil,-0x1023(%rbp,%rax,1)
  402d5e:	75 44                	jne    402da4 <main+0x23a4>
  402d60:	48 83 fa 0e          	cmp    $0xe,%rdx
  402d64:	0f 84 87 fc ff ff    	je     4029f1 <main+0x1ff1>
  402d6a:	0f b6 b4 05 de df ff ff 	movzbl -0x2022(%rbp,%rax,1),%esi
  402d72:	4c 8d 68 0e          	lea    0xe(%rax),%r13
  402d76:	40 38 b4 05 de ef ff ff 	cmp    %sil,-0x1022(%rbp,%rax,1)
  402d7e:	75 24                	jne    402da4 <main+0x23a4>
  402d80:	48 83 fa 0f          	cmp    $0xf,%rdx
  402d84:	0f 84 67 fc ff ff    	je     4029f1 <main+0x1ff1>
  402d8a:	0f b6 bc 05 df df ff ff 	movzbl -0x2021(%rbp,%rax,1),%edi
  402d92:	4c 8d 68 0f          	lea    0xf(%rax),%r13
  402d96:	40 38 bc 05 df ef ff ff 	cmp    %dil,-0x1021(%rbp,%rax,1)
  402d9e:	0f 84 4d fc ff ff    	je     4029f1 <main+0x1ff1>
  402da4:	31 c0                	xor    %eax,%eax
  402da6:	4c 89 e9             	mov    %r13,%rcx
  402da9:	ba c0 04 00 00       	mov    $0x4c0,%edx
  402dae:	48 89 de             	mov    %rbx,%rsi
  402db1:	bf 20 67 40 00       	mov    $0x406720,%edi
  402db6:	e8 b5 d5 ff ff       	call   400370 <printf@plt>
  402dbb:	48 81 fb c0 04 00 00 	cmp    $0x4c0,%rbx
  402dc2:	0f 84 76 fc ff ff    	je     402a3e <main+0x203e>
  402dc8:	e9 4c fc ff ff       	jmp    402a19 <main+0x2019>
  402dcd:	c4 e1 f9 7e c8       	vmovq  %xmm1,%rax
  402dd2:	0f b6 9c 05 10 cb ff ff 	movzbl -0x34f0(%rbp,%rax,1),%ebx
  402dda:	38 9c 05 50 c6 ff ff 	cmp    %bl,-0x39b0(%rbp,%rax,1)
  402de1:	0f 85 16 04 00 00    	jne    4031fd <main+0x27fd>
  402de7:	c4 e1 f9 7e d2       	vmovq  %xmm2,%rdx
  402dec:	48 83 fa 01          	cmp    $0x1,%rdx
  402df0:	0f 84 4e 03 00 00    	je     403144 <main+0x2744>
  402df6:	0f b6 b4 05 11 cb ff ff 	movzbl -0x34ef(%rbp,%rax,1),%esi
  402dfe:	48 8d 58 01          	lea    0x1(%rax),%rbx
  402e02:	40 38 b4 05 51 c6 ff ff 	cmp    %sil,-0x39af(%rbp,%rax,1)
  402e0a:	0f 85 62 fb ff ff    	jne    402972 <main+0x1f72>
  402e10:	48 83 fa 02          	cmp    $0x2,%rdx
  402e14:	0f 84 2a 03 00 00    	je     403144 <main+0x2744>
  402e1a:	0f b6 b4 05 12 cb ff ff 	movzbl -0x34ee(%rbp,%rax,1),%esi
  402e22:	48 8d 58 02          	lea    0x2(%rax),%rbx
  402e26:	40 38 b4 05 52 c6 ff ff 	cmp    %sil,-0x39ae(%rbp,%rax,1)
  402e2e:	0f 85 3e fb ff ff    	jne    402972 <main+0x1f72>
  402e34:	48 83 fa 03          	cmp    $0x3,%rdx
  402e38:	0f 84 06 03 00 00    	je     403144 <main+0x2744>
  402e3e:	0f b6 bc 05 13 cb ff ff 	movzbl -0x34ed(%rbp,%rax,1),%edi
  402e46:	48 8d 58 03          	lea    0x3(%rax),%rbx
  402e4a:	40 38 bc 05 53 c6 ff ff 	cmp    %dil,-0x39ad(%rbp,%rax,1)
  402e52:	0f 85 1a fb ff ff    	jne    402972 <main+0x1f72>
  402e58:	48 83 fa 04          	cmp    $0x4,%rdx
  402e5c:	0f 84 e2 02 00 00    	je     403144 <main+0x2744>
  402e62:	0f b6 b4 05 14 cb ff ff 	movzbl -0x34ec(%rbp,%rax,1),%esi
  402e6a:	48 8d 58 04          	lea    0x4(%rax),%rbx
  402e6e:	40 38 b4 05 54 c6 ff ff 	cmp    %sil,-0x39ac(%rbp,%rax,1)
  402e76:	0f 85 f6 fa ff ff    	jne    402972 <main+0x1f72>
  402e7c:	48 83 fa 05          	cmp    $0x5,%rdx
  402e80:	0f 84 be 02 00 00    	je     403144 <main+0x2744>
  402e86:	0f b6 bc 05 15 cb ff ff 	movzbl -0x34eb(%rbp,%rax,1),%edi
  402e8e:	48 8d 58 05          	lea    0x5(%rax),%rbx
  402e92:	40 38 bc 05 55 c6 ff ff 	cmp    %dil,-0x39ab(%rbp,%rax,1)
  402e9a:	0f 85 d2 fa ff ff    	jne    402972 <main+0x1f72>
  402ea0:	48 83 fa 06          	cmp    $0x6,%rdx
  402ea4:	0f 84 9a 02 00 00    	je     403144 <main+0x2744>
  402eaa:	0f b6 b4 05 16 cb ff ff 	movzbl -0x34ea(%rbp,%rax,1),%esi
  402eb2:	48 8d 58 06          	lea    0x6(%rax),%rbx
  402eb6:	40 38 b4 05 56 c6 ff ff 	cmp    %sil,-0x39aa(%rbp,%rax,1)
  402ebe:	0f 85 ae fa ff ff    	jne    402972 <main+0x1f72>
  402ec4:	48 83 fa 07          	cmp    $0x7,%rdx
  402ec8:	0f 84 76 02 00 00    	je     403144 <main+0x2744>
  402ece:	0f b6 bc 05 17 cb ff ff 	movzbl -0x34e9(%rbp,%rax,1),%edi
  402ed6:	48 8d 58 07          	lea    0x7(%rax),%rbx
  402eda:	40 38 bc 05 57 c6 ff ff 	cmp    %dil,-0x39a9(%rbp,%rax,1)
  402ee2:	0f 85 8a fa ff ff    	jne    402972 <main+0x1f72>
  402ee8:	48 83 fa 08          	cmp    $0x8,%rdx
  402eec:	0f 84 52 02 00 00    	je     403144 <main+0x2744>
  402ef2:	0f b6 b4 05 58 c6 ff ff 	movzbl -0x39a8(%rbp,%rax,1),%esi
  402efa:	48 8d 58 08          	lea    0x8(%rax),%rbx
  402efe:	40 38 b4 05 18 cb ff ff 	cmp    %sil,-0x34e8(%rbp,%rax,1)
  402f06:	0f 85 66 fa ff ff    	jne    402972 <main+0x1f72>
  402f0c:	48 83 fa 09          	cmp    $0x9,%rdx
  402f10:	0f 84 2e 02 00 00    	je     403144 <main+0x2744>
  402f16:	0f b6 bc 05 19 cb ff ff 	movzbl -0x34e7(%rbp,%rax,1),%edi
  402f1e:	48 8d 58 09          	lea    0x9(%rax),%rbx
  402f22:	40 38 bc 05 59 c6 ff ff 	cmp    %dil,-0x39a7(%rbp,%rax,1)
  402f2a:	0f 85 42 fa ff ff    	jne    402972 <main+0x1f72>
  402f30:	48 83 fa 0a          	cmp    $0xa,%rdx
  402f34:	0f 84 0a 02 00 00    	je     403144 <main+0x2744>
  402f3a:	0f b6 b4 05 5a c6 ff ff 	movzbl -0x39a6(%rbp,%rax,1),%esi
  402f42:	48 8d 58 0a          	lea    0xa(%rax),%rbx
  402f46:	40 38 b4 05 1a cb ff ff 	cmp    %sil,-0x34e6(%rbp,%rax,1)
  402f4e:	0f 85 1e fa ff ff    	jne    402972 <main+0x1f72>
  402f54:	48 83 fa 0b          	cmp    $0xb,%rdx
  402f58:	0f 84 e6 01 00 00    	je     403144 <main+0x2744>
  402f5e:	0f b6 bc 05 5b c6 ff ff 	movzbl -0x39a5(%rbp,%rax,1),%edi
  402f66:	48 8d 58 0b          	lea    0xb(%rax),%rbx
  402f6a:	40 38 bc 05 1b cb ff ff 	cmp    %dil,-0x34e5(%rbp,%rax,1)
  402f72:	0f 85 fa f9 ff ff    	jne    402972 <main+0x1f72>
  402f78:	48 83 fa 0c          	cmp    $0xc,%rdx
  402f7c:	0f 84 c2 01 00 00    	je     403144 <main+0x2744>
  402f82:	0f b6 b4 05 5c c6 ff ff 	movzbl -0x39a4(%rbp,%rax,1),%esi
  402f8a:	48 8d 58 0c          	lea    0xc(%rax),%rbx
  402f8e:	40 38 b4 05 1c cb ff ff 	cmp    %sil,-0x34e4(%rbp,%rax,1)
  402f96:	0f 85 d6 f9 ff ff    	jne    402972 <main+0x1f72>
  402f9c:	48 83 fa 0d          	cmp    $0xd,%rdx
  402fa0:	0f 84 9e 01 00 00    	je     403144 <main+0x2744>
  402fa6:	0f b6 bc 05 5d c6 ff ff 	movzbl -0x39a3(%rbp,%rax,1),%edi
  402fae:	48 8d 58 0d          	lea    0xd(%rax),%rbx
  402fb2:	40 38 bc 05 1d cb ff ff 	cmp    %dil,-0x34e3(%rbp,%rax,1)
  402fba:	0f 85 b2 f9 ff ff    	jne    402972 <main+0x1f72>
  402fc0:	48 83 fa 0e          	cmp    $0xe,%rdx
  402fc4:	0f 84 7a 01 00 00    	je     403144 <main+0x2744>
  402fca:	0f b6 b4 05 5e c6 ff ff 	movzbl -0x39a2(%rbp,%rax,1),%esi
  402fd2:	48 8d 58 0e          	lea    0xe(%rax),%rbx
  402fd6:	40 38 b4 05 1e cb ff ff 	cmp    %sil,-0x34e2(%rbp,%rax,1)
  402fde:	0f 85 8e f9 ff ff    	jne    402972 <main+0x1f72>
  402fe4:	48 83 fa 0f          	cmp    $0xf,%rdx
  402fe8:	0f 84 56 01 00 00    	je     403144 <main+0x2744>
  402fee:	0f b6 bc 05 1f cb ff ff 	movzbl -0x34e1(%rbp,%rax,1),%edi
  402ff6:	48 8d 58 0f          	lea    0xf(%rax),%rbx
  402ffa:	40 38 bc 05 5f c6 ff ff 	cmp    %dil,-0x39a1(%rbp,%rax,1)
  403002:	b8 c0 04 00 00       	mov    $0x4c0,%eax
  403007:	48 0f 44 d8          	cmove  %rax,%rbx
  40300b:	e9 62 f9 ff ff       	jmp    402972 <main+0x1f72>
  403010:	48 8b 85 78 bf ff ff 	mov    -0x4088(%rbp),%rax
  403017:	48 3d 00 08 00 00    	cmp    $0x800,%rax
  40301d:	0f 84 89 01 00 00    	je     4031ac <main+0x27ac>
  403023:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  40302e:	c6 85 50 bf ff ff 00 	movb   $0x0,-0x40b0(%rbp)
  403035:	48 3d 10 08 00 00    	cmp    $0x810,%rax
  40303b:	0f 84 31 01 00 00    	je     403172 <main+0x2772>
  403041:	b9 01 00 00 00       	mov    $0x1,%ecx
  403046:	ba 03 00 00 00       	mov    $0x3,%edx
  40304b:	b8 02 00 00 00       	mov    $0x2,%eax
  403050:	48 c7 85 b0 bf ff ff a0 65 40 00 	movq   $0x4065a0,-0x4050(%rbp)
  40305b:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  403065:	41 b9 01 00 00 00    	mov    $0x1,%r9d
  40306b:	48 c7 85 88 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4078(%rbp)
  403076:	e9 45 e9 ff ff       	jmp    4019c0 <main+0xfc0>
  40307b:	84 db                	test   %bl,%bl
  40307d:	0f 85 cb 00 00 00    	jne    40314e <main+0x274e>
  403083:	48 8b 9d 80 bf ff ff 	mov    -0x4080(%rbp),%rbx
  40308a:	48 39 9d 78 bf ff ff 	cmp    %rbx,-0x4088(%rbp)
  403091:	0f 85 a8 e9 ff ff    	jne    401a3f <main+0x103f>
  403097:	c5 fe 6f 85 98 c0 ff ff 	vmovdqu -0x3f68(%rbp),%ymm0
  40309f:	c5 fc 57 85 18 c1 ff ff 	vxorps -0x3ee8(%rbp),%ymm0,%ymm0
  4030a7:	c4 e2 7d 17 c0       	vptest %ymm0,%ymm0
  4030ac:	75 2b                	jne    4030d9 <main+0x26d9>
  4030ae:	c5 fe 6f 85 b8 c0 ff ff 	vmovdqu -0x3f48(%rbp),%ymm0
  4030b6:	c5 fc 57 85 38 c1 ff ff 	vxorps -0x3ec8(%rbp),%ymm0,%ymm0
  4030be:	c4 e2 7d 17 c0       	vptest %ymm0,%ymm0
  4030c3:	75 14                	jne    4030d9 <main+0x26d9>
  4030c5:	48 8b 85 58 c1 ff ff 	mov    -0x3ea8(%rbp),%rax
  4030cc:	48 39 85 d8 c0 ff ff 	cmp    %rax,-0x3f28(%rbp)
  4030d3:	0f 84 2c 01 00 00    	je     403205 <main+0x2805>
  4030d9:	c7 85 68 bf ff ff 01 00 00 00 	movl   $0x1,-0x4098(%rbp)
  4030e3:	bf 01 00 00 00       	mov    $0x1,%edi
  4030e8:	b8 01 00 00 00       	mov    $0x1,%eax
  4030ed:	c5 f8 77             	vzeroupper
  4030f0:	e9 5e e9 ff ff       	jmp    401a53 <main+0x1053>
  4030f5:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  403100:	41 89 df             	mov    %ebx,%r15d
  403103:	b9 01 00 00 00       	mov    $0x1,%ecx
  403108:	ba 03 00 00 00       	mov    $0x3,%edx
  40310d:	48 c7 85 b0 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4050(%rbp)
  403118:	b8 03 00 00 00       	mov    $0x3,%eax
  40311d:	41 b9 01 00 00 00    	mov    $0x1,%r9d
  403123:	48 c7 85 88 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4078(%rbp)
  40312e:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  403138:	c6 85 50 bf ff ff 00 	movb   $0x0,-0x40b0(%rbp)
  40313f:	e9 7c e8 ff ff       	jmp    4019c0 <main+0xfc0>
  403144:	bb c0 04 00 00       	mov    $0x4c0,%ebx
  403149:	e9 24 f8 ff ff       	jmp    402972 <main+0x1f72>
  40314e:	48 8b 9d 70 bf ff ff 	mov    -0x4090(%rbp),%rbx
  403155:	48 39 9d 58 bf ff ff 	cmp    %rbx,-0x40a8(%rbp)
  40315c:	40 0f 95 c7          	setne  %dil
  403160:	0f 95 c0             	setne  %al
  403163:	40 0f b6 ff          	movzbl %dil,%edi
  403167:	89 bd 68 bf ff ff    	mov    %edi,-0x4098(%rbp)
  40316d:	e9 e1 e8 ff ff       	jmp    401a53 <main+0x1053>
  403172:	b9 01 00 00 00       	mov    $0x1,%ecx
  403177:	ba 03 00 00 00       	mov    $0x3,%edx
  40317c:	b8 01 00 00 00       	mov    $0x1,%eax
  403181:	48 c7 85 b0 bf ff ff 94 65 40 00 	movq   $0x406594,-0x4050(%rbp)
  40318c:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  403196:	41 b9 01 00 00 00    	mov    $0x1,%r9d
  40319c:	48 c7 85 88 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4078(%rbp)
  4031a7:	e9 14 e8 ff ff       	jmp    4019c0 <main+0xfc0>
  4031ac:	c6 85 50 bf ff ff 00 	movb   $0x0,-0x40b0(%rbp)
  4031b3:	31 c0                	xor    %eax,%eax
  4031b5:	b9 01 00 00 00       	mov    $0x1,%ecx
  4031ba:	ba 03 00 00 00       	mov    $0x3,%edx
  4031bf:	c7 85 f0 bf ff ff 01 00 00 00 	movl   $0x1,-0x4010(%rbp)
  4031c9:	41 b9 01 00 00 00    	mov    $0x1,%r9d
  4031cf:	48 c7 85 80 bf ff ff 00 00 00 00 	movq   $0x0,-0x4080(%rbp)
  4031da:	48 c7 85 b0 bf ff ff a6 65 40 00 	movq   $0x4065a6,-0x4050(%rbp)
  4031e5:	48 c7 85 88 bf ff ff 99 65 40 00 	movq   $0x406599,-0x4078(%rbp)
  4031f0:	e9 cb e7 ff ff       	jmp    4019c0 <main+0xfc0>
  4031f5:	49 89 c5             	mov    %rax,%r13
  4031f8:	e9 a7 fb ff ff       	jmp    402da4 <main+0x23a4>
  4031fd:	48 89 c3             	mov    %rax,%rbx
  403200:	e9 6d f7 ff ff       	jmp    402972 <main+0x1f72>
  403205:	48 8b 85 60 c1 ff ff 	mov    -0x3ea0(%rbp),%rax
  40320c:	48 39 85 e0 c0 ff ff 	cmp    %rax,-0x3f20(%rbp)
  403213:	0f 85 c0 fe ff ff    	jne    4030d9 <main+0x26d9>
  403219:	48 8b 85 68 c1 ff ff 	mov    -0x3e98(%rbp),%rax
  403220:	48 39 85 e8 c0 ff ff 	cmp    %rax,-0x3f18(%rbp)
  403227:	0f b6 bd 98 bf ff ff 	movzbl -0x4068(%rbp),%edi
  40322e:	0f 94 c0             	sete   %al
  403231:	40 38 bd 50 bf ff ff 	cmp    %dil,-0x40b0(%rbp)
  403238:	40 0f 94 c7          	sete   %dil
  40323c:	21 f8                	and    %edi,%eax
  40323e:	83 f0 01             	xor    $0x1,%eax
  403241:	0f b6 f8             	movzbl %al,%edi
  403244:	89 bd 68 bf ff ff    	mov    %edi,-0x4098(%rbp)
  40324a:	c5 f8 77             	vzeroupper
  40324d:	e9 01 e8 ff ff       	jmp    401a53 <main+0x1053>
  403252:	be b0 69 40 00       	mov    $0x4069b0,%esi
  403257:	bf 88 69 40 00       	mov    $0x406988,%edi
  40325c:	31 c0                	xor    %eax,%eax
  40325e:	e8 0d d1 ff ff       	call   400370 <printf@plt>
  403263:	bb 02 00 00 00       	mov    $0x2,%ebx
  403268:	e9 f8 e9 ff ff       	jmp    401c65 <main+0x1265>
  40326d:	be c0 65 40 00       	mov    $0x4065c0,%esi
  403272:	bf 88 69 40 00       	mov    $0x406988,%edi
  403277:	31 c0                	xor    %eax,%eax
  403279:	e8 f2 d0 ff ff       	call   400370 <printf@plt>
  40327e:	e9 e2 e9 ff ff       	jmp    401c65 <main+0x1265>
  403283:	48 89 c7             	mov    %rax,%rdi
  403286:	e9 02 d2 ff ff       	jmp    40048d <main.cold+0xd>
  40328b:	48 89 c7             	mov    %rax,%rdi
  40328e:	e9 e1 d2 ff ff       	jmp    400574 <main.cold+0xf4>
  403293:	48 89 c7             	mov    %rax,%rdi
  403296:	e9 34 d4 ff ff       	jmp    4006cf <main.cold+0x24f>
  40329b:	48 89 c7             	mov    %rax,%rdi
  40329e:	e9 13 d5 ff ff       	jmp    4007b6 <main.cold+0x336>
  4032a3:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  4032ad:	0f 1f 00             	nopl   (%rax)

00000000004032b0 <_start>:
  4032b0:	f3 0f 1e fa          	endbr64
  4032b4:	31 ed                	xor    %ebp,%ebp
  4032b6:	49 89 d1             	mov    %rdx,%r9
  4032b9:	5e                   	pop    %rsi
  4032ba:	48 89 e2             	mov    %rsp,%rdx
  4032bd:	48 83 e4 f0          	and    $0xfffffffffffffff0,%rsp
  4032c1:	50                   	push   %rax
  4032c2:	54                   	push   %rsp
  4032c3:	45 31 c0             	xor    %r8d,%r8d
  4032c6:	31 c9                	xor    %ecx,%ecx
  4032c8:	48 c7 c7 00 0a 40 00 	mov    $0x400a00,%rdi
  4032cf:	ff 15 03 5d 00 00    	call   *0x5d03(%rip)        # 408fd8 <__libc_start_main@GLIBC_2.34>
  4032d5:	f4                   	hlt
  4032d6:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)

00000000004032e0 <_dl_relocate_static_pie>:
  4032e0:	f3 0f 1e fa          	endbr64
  4032e4:	c3                   	ret
  4032e5:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  4032ef:	90                   	nop

00000000004032f0 <deregister_tm_clones>:
  4032f0:	b8 70 90 40 00       	mov    $0x409070,%eax
  4032f5:	48 3d 70 90 40 00    	cmp    $0x409070,%rax
  4032fb:	74 13                	je     403310 <deregister_tm_clones+0x20>
  4032fd:	b8 00 00 00 00       	mov    $0x0,%eax
  403302:	48 85 c0             	test   %rax,%rax
  403305:	74 09                	je     403310 <deregister_tm_clones+0x20>
  403307:	bf 70 90 40 00       	mov    $0x409070,%edi
  40330c:	ff e0                	jmp    *%rax
  40330e:	66 90                	xchg   %ax,%ax
  403310:	c3                   	ret
  403311:	0f 1f 40 00          	nopl   0x0(%rax)
  403315:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)

0000000000403320 <register_tm_clones>:
  403320:	be 70 90 40 00       	mov    $0x409070,%esi
  403325:	48 81 ee 70 90 40 00 	sub    $0x409070,%rsi
  40332c:	48 89 f0             	mov    %rsi,%rax
  40332f:	48 c1 ee 3f          	shr    $0x3f,%rsi
  403333:	48 c1 f8 03          	sar    $0x3,%rax
  403337:	48 01 c6             	add    %rax,%rsi
  40333a:	48 d1 fe             	sar    $1,%rsi
  40333d:	74 11                	je     403350 <register_tm_clones+0x30>
  40333f:	b8 00 00 00 00       	mov    $0x0,%eax
  403344:	48 85 c0             	test   %rax,%rax
  403347:	74 07                	je     403350 <register_tm_clones+0x30>
  403349:	bf 70 90 40 00       	mov    $0x409070,%edi
  40334e:	ff e0                	jmp    *%rax
  403350:	c3                   	ret
  403351:	0f 1f 40 00          	nopl   0x0(%rax)
  403355:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)

0000000000403360 <__do_global_dtors_aux>:
  403360:	f3 0f 1e fa          	endbr64
  403364:	80 3d 1d 5d 00 00 00 	cmpb   $0x0,0x5d1d(%rip)        # 409088 <completed.0>
  40336b:	75 13                	jne    403380 <__do_global_dtors_aux+0x20>
  40336d:	55                   	push   %rbp
  40336e:	48 89 e5             	mov    %rsp,%rbp
  403371:	e8 7a ff ff ff       	call   4032f0 <deregister_tm_clones>
  403376:	c6 05 0b 5d 00 00 01 	movb   $0x1,0x5d0b(%rip)        # 409088 <completed.0>
  40337d:	5d                   	pop    %rbp
  40337e:	c3                   	ret
  40337f:	90                   	nop
  403380:	c3                   	ret
  403381:	0f 1f 40 00          	nopl   0x0(%rax)
  403385:	66 66 2e 0f 1f 84 00 00 00 00 00 	data16 cs nopw 0x0(%rax,%rax,1)

0000000000403390 <frame_dummy>:
  403390:	f3 0f 1e fa          	endbr64
  403394:	eb 8a                	jmp    403320 <register_tm_clones>
  403396:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)

00000000004033a0 <_call_goal8_asm_systemv>:
  4033a0:	55                   	push   %rbp
  4033a1:	48 89 e5             	mov    %rsp,%rbp
  4033a4:	48 83 ec 70          	sub    $0x70,%rsp
  4033a8:	48 8b 05 e1 5c 00 00 	mov    0x5ce1(%rip),%rax        # 409090 <g_ee_main_mem>
  4033af:	c5 fe 6f 06          	vmovdqu (%rsi),%ymm0
  4033b3:	48 89 54 24 48       	mov    %rdx,0x48(%rsp)
  4033b8:	48 29 c7             	sub    %rax,%rdi
  4033bb:	48 89 4c 24 50       	mov    %rcx,0x50(%rsp)
  4033c0:	4c 39 c8             	cmp    %r9,%rax
  4033c3:	4c 89 44 24 58       	mov    %r8,0x58(%rsp)
  4033c8:	c7 44 24 61 00 00 00 00 	movl   $0x0,0x61(%rsp)
  4033d0:	48 89 3c 24          	mov    %rdi,(%rsp)
  4033d4:	bf 68 00 00 00       	mov    $0x68,%edi
  4033d9:	c5 fe 7f 44 24 08    	vmovdqu %ymm0,0x8(%rsp)
  4033df:	c5 fe 6f 46 20       	vmovdqu 0x20(%rsi),%ymm0
  4033e4:	c7 44 24 64 00 00 00 00 	movl   $0x0,0x64(%rsp)
  4033ec:	0f 94 44 24 60       	sete   0x60(%rsp)
  4033f1:	c5 fe 7f 44 24 28    	vmovdqu %ymm0,0x28(%rsp)
  4033f7:	c5 f8 77             	vzeroupper
  4033fa:	e8 a1 cf ff ff       	call   4003a0 <__cxa_allocate_exception@plt>
  4033ff:	c5 fe 6f 04 24       	vmovdqu (%rsp),%ymm0
  403404:	48 8b 54 24 60       	mov    0x60(%rsp),%rdx
  403409:	be 10 6e 40 00       	mov    $0x406e10,%esi
  40340e:	48 89 c7             	mov    %rax,%rdi
  403411:	c5 fe 7f 00          	vmovdqu %ymm0,(%rax)
  403415:	c5 fe 6f 44 24 20    	vmovdqu 0x20(%rsp),%ymm0
  40341b:	48 89 50 60          	mov    %rdx,0x60(%rax)
  40341f:	31 d2                	xor    %edx,%edx
  403421:	c5 fe 7f 40 20       	vmovdqu %ymm0,0x20(%rax)
  403426:	c5 fe 6f 44 24 40    	vmovdqu 0x40(%rsp),%ymm0
  40342c:	c5 fe 7f 40 40       	vmovdqu %ymm0,0x40(%rax)
  403431:	c5 f8 77             	vzeroupper
  403434:	e8 e7 cf ff ff       	call   400420 <__cxa_throw@plt>
  403439:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)

0000000000403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>:
  403440:	48 83 ec 10          	sub    $0x10,%rsp
  403444:	49 89 c9             	mov    %rcx,%r9
  403447:	31 c0                	xor    %eax,%eax
  403449:	48 89 f1             	mov    %rsi,%rcx
  40344c:	41 50                	push   %r8
  40344e:	41 89 d0             	mov    %edx,%r8d
  403451:	48 89 fa             	mov    %rdi,%rdx
  403454:	48 8b 3d 25 5c 00 00 	mov    0x5c25(%rip),%rdi        # 409080 <stderr@GLIBC_2.2.5>
  40345b:	be cf 65 40 00       	mov    $0x4065cf,%esi
  403460:	e8 8b cf ff ff       	call   4003f0 <fprintf@plt>
  403465:	e8 46 cf ff ff       	call   4003b0 <abort@plt>
  40346a:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)

0000000000403470 <full_before_execute>:
  403470:	55                   	push   %rbp
  403471:	48 89 e5             	mov    %rsp,%rbp
  403474:	41 56                	push   %r14
  403476:	41 55                	push   %r13
  403478:	41 54                	push   %r12
  40347a:	53                   	push   %rbx
  40347b:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
  40347f:	48 81 ec 40 01 00 00 	sub    $0x140,%rsp
  403486:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
  40348d:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
  403494:	48 8b 15 f5 5b 00 00 	mov    0x5bf5(%rip),%rdx        # 409090 <g_ee_main_mem>
  40349b:	48 2d a0 00 00 00    	sub    $0xa0,%rax
  4034a1:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
  4034a8:	89 c0                	mov    %eax,%eax
  4034aa:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
  4034ae:	48 8b 8f e0 01 00 00 	mov    0x1e0(%rdi),%rcx
  4034b5:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  4034bb:	48 8b 15 ce 5b 00 00 	mov    0x5bce(%rip),%rdx        # 409090 <g_ee_main_mem>
  4034c2:	48 89 4c 02 08       	mov    %rcx,0x8(%rdx,%rax,1)
  4034c7:	48 8b 87 90 01 00 00 	mov    0x190(%rdi),%rax
  4034ce:	4c 8b 0d bb 5b 00 00 	mov    0x5bbb(%rip),%r9        # 409090 <g_ee_main_mem>
  4034d5:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
  4034dd:	48 89 87 e0 01 00 00 	mov    %rax,0x1e0(%rdi)
  4034e4:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  4034ea:	83 c0 30             	add    $0x30,%eax
  4034ed:	83 e0 f0             	and    $0xfffffff0,%eax
  4034f0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4034f6:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  4034fc:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
  403504:	83 c0 40             	add    $0x40,%eax
  403507:	83 e0 f0             	and    $0xfffffff0,%eax
  40350a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  403510:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  403516:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
  40351e:	83 c0 50             	add    $0x50,%eax
  403521:	83 e0 f0             	and    $0xfffffff0,%eax
  403524:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40352a:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  403530:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
  403538:	83 c0 60             	add    $0x60,%eax
  40353b:	83 e0 f0             	and    $0xfffffff0,%eax
  40353e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  403544:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  40354a:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
  403552:	83 c0 70             	add    $0x70,%eax
  403555:	83 e0 f0             	and    $0xfffffff0,%eax
  403558:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40355e:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  403564:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
  40356c:	83 e8 80             	sub    $0xffffff80,%eax
  40356f:	83 e0 f0             	and    $0xfffffff0,%eax
  403572:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  403578:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  40357e:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
  403586:	05 90 00 00 00       	add    $0x90,%eax
  40358b:	83 e0 f0             	and    $0xfffffff0,%eax
  40358e:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  403594:	48 8b 47 40          	mov    0x40(%rdi),%rax
  403598:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
  40359c:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
  4035a3:	48 8b 47 50          	mov    0x50(%rdi),%rax
  4035a7:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
  4035ae:	48 8b 47 60          	mov    0x60(%rdi),%rax
  4035b2:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
  4035b9:	48 8b 47 70          	mov    0x70(%rdi),%rax
  4035bd:	48 89 87 00 01 00 00 	mov    %rax,0x100(%rdi)
  4035c4:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
  4035cb:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
  4035d2:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
  4035d9:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
  4035e0:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
  4035e7:	48 83 c0 10          	add    $0x10,%rax
  4035eb:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
  4035f2:	83 e0 f0             	and    $0xfffffff0,%eax
  4035f5:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4035fb:	48 8b 05 9e 5a 00 00 	mov    0x5a9e(%rip),%rax        # 4090a0 <full_before_cache>
  403602:	48 63 10             	movslq (%rax),%rdx
  403605:	48 89 57 30          	mov    %rdx,0x30(%rdi)
  403609:	f6 c2 0f             	test   $0xf,%dl
  40360c:	0f 85 fe 10 00 00    	jne    404710 <full_before_execute+0x12a0>
  403612:	89 d2                	mov    %edx,%edx
  403614:	48 89 fb             	mov    %rdi,%rbx
  403617:	49 8b 04 11          	mov    (%r9,%rdx,1),%rax
  40361b:	49 8b 4c 11 08       	mov    0x8(%r9,%rdx,1),%rcx
  403620:	48 89 87 80 03 00 00 	mov    %rax,0x380(%rdi)
  403627:	0f b6 c0             	movzbl %al,%eax
  40362a:	48 89 ca             	mov    %rcx,%rdx
  40362d:	48 89 8f 88 03 00 00 	mov    %rcx,0x388(%rdi)
  403634:	48 89 4f 38          	mov    %rcx,0x38(%rdi)
  403638:	48 89 47 30          	mov    %rax,0x30(%rdi)
  40363c:	8b bf d0 01 00 00    	mov    0x1d0(%rdi),%edi
  403642:	8d 4f 20             	lea    0x20(%rdi),%ecx
  403645:	83 e1 f0             	and    $0xfffffff0,%ecx
  403648:	49 89 04 09          	mov    %rax,(%r9,%rcx,1)
  40364c:	49 89 54 09 08       	mov    %rdx,0x8(%r9,%rcx,1)
  403651:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  403658:	e9 b5 00 00 00       	jmp    403712 <full_before_execute+0x2a2>
  40365d:	0f 1f 00             	nopl   (%rax)
  403660:	48 63 09             	movslq (%rcx),%rcx
  403663:	48 c7 43 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%rbx)
  40366b:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
  40366f:	85 c9                	test   %ecx,%ecx
  403671:	0f 84 99 0b 00 00    	je     404210 <full_before_execute+0xda0>
  403677:	8b 07                	mov    (%rdi),%eax
  403679:	89 c2                	mov    %eax,%edx
  40367b:	83 e0 bf             	and    $0xffffffbf,%eax
  40367e:	83 e2 40             	and    $0x40,%edx
  403681:	48 63 c8             	movslq %eax,%rcx
  403684:	89 d6                	mov    %edx,%esi
  403686:	48 89 4b 40          	mov    %rcx,0x40(%rbx)
  40368a:	48 89 73 30          	mov    %rsi,0x30(%rbx)
  40368e:	89 07                	mov    %eax,(%rdi)
  403690:	4c 8b 0d f9 59 00 00 	mov    0x59f9(%rip),%r9        # 409090 <g_ee_main_mem>
  403697:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  40369e:	85 d2                	test   %edx,%edx
  4036a0:	74 2e                	je     4036d0 <full_before_execute+0x260>
  4036a2:	89 c0                	mov    %eax,%eax
  4036a4:	49 63 54 01 7c       	movslq 0x7c(%r9,%rax,1),%rdx
  4036a9:	48 89 d0             	mov    %rdx,%rax
  4036ac:	48 89 53 30          	mov    %rdx,0x30(%rbx)
  4036b0:	8b 93 40 01 00 00    	mov    0x140(%rbx),%edx
  4036b6:	41 89 44 11 2c       	mov    %eax,0x2c(%r9,%rdx,1)
  4036bb:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  4036c2:	4c 8b 0d c7 59 00 00 	mov    0x59c7(%rip),%r9        # 409090 <g_ee_main_mem>
  4036c9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  4036d0:	48 8b b3 30 01 00 00 	mov    0x130(%rbx),%rsi
  4036d7:	48 05 90 00 00 00    	add    $0x90,%rax
  4036dd:	48 83 83 40 01 00 00 30 	addq   $0x30,0x140(%rbx)
  4036e5:	48 89 83 50 01 00 00 	mov    %rax,0x150(%rbx)
  4036ec:	48 8d 56 ff          	lea    -0x1(%rsi),%rdx
  4036f0:	48 8b b3 00 01 00 00 	mov    0x100(%rbx),%rsi
  4036f7:	48 89 93 30 01 00 00 	mov    %rdx,0x130(%rbx)
  4036fe:	48 8d 4e 01          	lea    0x1(%rsi),%rcx
  403702:	48 89 8b 00 01 00 00 	mov    %rcx,0x100(%rbx)
  403709:	48 85 d2             	test   %rdx,%rdx
  40370c:	0f 84 2e 0d 00 00    	je     404440 <full_before_execute+0xfd0>
  403712:	89 c1                	mov    %eax,%ecx
  403714:	48 8b b3 70 01 00 00 	mov    0x170(%rbx),%rsi
  40371b:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
  403723:	48 89 53 30          	mov    %rdx,0x30(%rbx)
  403727:	48 39 d6             	cmp    %rdx,%rsi
  40372a:	74 a4                	je     4036d0 <full_before_execute+0x260>
  40372c:	49 8d 7c 09 68       	lea    0x68(%r9,%rcx,1),%rdi
  403731:	49 8d 4c 09 64       	lea    0x64(%r9,%rcx,1),%rcx
  403736:	48 63 17             	movslq (%rdi),%rdx
  403739:	48 3b b3 20 01 00 00 	cmp    0x120(%rbx),%rsi
  403740:	0f 84 aa 0b 00 00    	je     4042f0 <full_before_execute+0xe80>
  403746:	81 e2 00 20 00 00    	and    $0x2000,%edx
  40374c:	89 d6                	mov    %edx,%esi
  40374e:	48 89 73 30          	mov    %rsi,0x30(%rbx)
  403752:	0f 84 08 ff ff ff    	je     403660 <full_before_execute+0x1f0>
  403758:	8b b3 d0 01 00 00    	mov    0x1d0(%rbx),%esi
  40375e:	4c 63 01             	movslq (%rcx),%r8
  403761:	48 c7 43 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%rbx)
  403769:	8d 56 20             	lea    0x20(%rsi),%edx
  40376c:	4c 89 43 30          	mov    %r8,0x30(%rbx)
  403770:	83 e2 f0             	and    $0xfffffff0,%edx
  403773:	4d 8b 14 11          	mov    (%r9,%rdx,1),%r10
  403777:	49 8b 74 11 08       	mov    0x8(%r9,%rdx,1),%rsi
  40377c:	4c 89 53 40          	mov    %r10,0x40(%rbx)
  403780:	48 89 73 48          	mov    %rsi,0x48(%rbx)
  403784:	49 83 f8 ff          	cmp    $0xffffffffffffffff,%r8
  403788:	74 5d                	je     4037e7 <full_before_execute+0x377>
  40378a:	4c 89 c2             	mov    %r8,%rdx
  40378d:	c5 f9 6e f6          	vmovd  %esi,%xmm6
  403791:	4c 29 d2             	sub    %r10,%rdx
  403794:	49 89 f2             	mov    %rsi,%r10
  403797:	48 89 d7             	mov    %rdx,%rdi
  40379a:	49 c1 fa 20          	sar    $0x20,%r10
  40379e:	c5 f9 6e ea          	vmovd  %edx,%xmm5
  4037a2:	48 89 53 40          	mov    %rdx,0x40(%rbx)
  4037a6:	48 c1 ff 20          	sar    $0x20,%rdi
  4037aa:	c4 c3 49 22 ca 01    	vpinsrd $0x1,%r10d,%xmm6,%xmm1
  4037b0:	c4 e3 51 22 c7 01    	vpinsrd $0x1,%edi,%xmm5,%xmm0
  4037b6:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
  4037ba:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  4037be:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
  4037c3:	c5 f9 7f 43 30       	vmovdqa %xmm0,0x30(%rbx)
  4037c8:	4d 85 c0             	test   %r8,%r8
  4037cb:	0f 84 3f 0a 00 00    	je     404210 <full_before_execute+0xda0>
  4037d1:	c5 f9 7e 01          	vmovd  %xmm0,(%rcx)
  4037d5:	8b 83 50 01 00 00    	mov    0x150(%rbx),%eax
  4037db:	48 8b 15 ae 58 00 00 	mov    0x58ae(%rip),%rdx        # 409090 <g_ee_main_mem>
  4037e2:	48 8d 7c 02 68       	lea    0x68(%rdx,%rax,1),%rdi
  4037e7:	8b 07                	mov    (%rdi),%eax
  4037e9:	89 c2                	mov    %eax,%edx
  4037eb:	83 e0 bf             	and    $0xffffffbf,%eax
  4037ee:	83 e2 40             	and    $0x40,%edx
  4037f1:	48 63 c8             	movslq %eax,%rcx
  4037f4:	89 d6                	mov    %edx,%esi
  4037f6:	48 89 4b 40          	mov    %rcx,0x40(%rbx)
  4037fa:	48 89 73 30          	mov    %rsi,0x30(%rbx)
  4037fe:	89 07                	mov    %eax,(%rdi)
  403800:	85 d2                	test   %edx,%edx
  403802:	74 23                	je     403827 <full_before_execute+0x3b7>
  403804:	8b 93 50 01 00 00    	mov    0x150(%rbx),%edx
  40380a:	48 8b 05 7f 58 00 00 	mov    0x587f(%rip),%rax        # 409090 <g_ee_main_mem>
  403811:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
  403816:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
  40381a:	48 89 ca             	mov    %rcx,%rdx
  40381d:	8b 8b 40 01 00 00    	mov    0x140(%rbx),%ecx
  403823:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
  403827:	4c 8b 0d 62 58 00 00 	mov    0x5862(%rip),%r9        # 409090 <g_ee_main_mem>
  40382e:	8b 93 50 01 00 00    	mov    0x150(%rbx),%edx
  403834:	49 63 44 11 70       	movslq 0x70(%r9,%rdx,1),%rax
  403839:	48 89 c1             	mov    %rax,%rcx
  40383c:	48 89 83 90 01 00 00 	mov    %rax,0x190(%rbx)
  403843:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
  40384a:	85 c9                	test   %ecx,%ecx
  40384c:	0f 84 de 01 00 00    	je     403a30 <full_before_execute+0x5c0>
  403852:	c5 f9 6f 83 c0 01 00 00 	vmovdqa 0x1c0(%rbx),%xmm0
  40385a:	48 83 e8 60          	sub    $0x60,%rax
  40385e:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
  403865:	83 e0 f0             	and    $0xfffffff0,%eax
  403868:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40386e:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  403874:	c5 f9 6f 83 50 01 00 00 	vmovdqa 0x150(%rbx),%xmm0
  40387c:	83 c0 10             	add    $0x10,%eax
  40387f:	83 e0 f0             	and    $0xfffffff0,%eax
  403882:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  403888:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  40388e:	c5 f9 6f 83 40 01 00 00 	vmovdqa 0x140(%rbx),%xmm0
  403896:	83 c0 20             	add    $0x20,%eax
  403899:	83 e0 f0             	and    $0xfffffff0,%eax
  40389c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4038a2:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  4038a8:	c5 f9 6f 83 00 01 00 00 	vmovdqa 0x100(%rbx),%xmm0
  4038b0:	83 c0 30             	add    $0x30,%eax
  4038b3:	83 e0 f0             	and    $0xfffffff0,%eax
  4038b6:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4038bc:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  4038c2:	c5 f9 6f 83 30 01 00 00 	vmovdqa 0x130(%rbx),%xmm0
  4038ca:	83 c0 40             	add    $0x40,%eax
  4038cd:	83 e0 f0             	and    $0xfffffff0,%eax
  4038d0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4038d6:	48 8b 83 c0 01 00 00 	mov    0x1c0(%rbx),%rax
  4038dd:	c5 f9 6f 83 20 01 00 00 	vmovdqa 0x120(%rbx),%xmm0
  4038e5:	8b bb 90 01 00 00    	mov    0x190(%rbx),%edi
  4038eb:	48 89 43 40          	mov    %rax,0x40(%rbx)
  4038ef:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  4038f6:	48 89 43 50          	mov    %rax,0x50(%rbx)
  4038fa:	48 8b 83 40 01 00 00 	mov    0x140(%rbx),%rax
  403901:	48 89 43 60          	mov    %rax,0x60(%rbx)
  403905:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  40390b:	83 c0 50             	add    $0x50,%eax
  40390e:	83 e0 f0             	and    $0xfffffff0,%eax
  403911:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  403917:	c5 fa 7e bb a0 00 00 00 	vmovq  0xa0(%rbx),%xmm7
  40391f:	c5 fa 7e 6b 60       	vmovq  0x60(%rbx),%xmm5
  403924:	c5 fa 7e b3 80 00 00 00 	vmovq  0x80(%rbx),%xmm6
  40392c:	c4 e3 d1 22 53 70 01 	vpinsrq $0x1,0x70(%rbx),%xmm5,%xmm2
  403933:	c4 e3 c1 22 8b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm7,%xmm1
  40393d:	c5 fa 7e 7b 40       	vmovq  0x40(%rbx),%xmm7
  403942:	c4 e3 c9 22 83 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm6,%xmm0
  40394c:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
  403952:	c4 e3 c1 22 4b 50 01 	vpinsrq $0x1,0x50(%rbx),%xmm7,%xmm1
  403959:	c5 fd 7f 44 24 20    	vmovdqa %ymm0,0x20(%rsp)
  40395f:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
  403965:	c5 fd 7f 0c 24       	vmovdqa %ymm1,(%rsp)
  40396a:	85 ff                	test   %edi,%edi
  40396c:	0f 84 bd 0d 00 00    	je     40472f <full_before_execute+0x12bf>
  403972:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
  403979:	4c 01 cf             	add    %r9,%rdi
  40397c:	31 d2                	xor    %edx,%edx
  40397e:	48 89 e6             	mov    %rsp,%rsi
  403981:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
  403988:	c5 f8 77             	vzeroupper
  40398b:	e8 10 fa ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  403990:	4c 8b 0d f9 56 00 00 	mov    0x56f9(%rip),%r9        # 409090 <g_ee_main_mem>
  403997:	48 89 43 20          	mov    %rax,0x20(%rbx)
  40399b:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
  4039a2:	48 89 c2             	mov    %rax,%rdx
  4039a5:	8d 48 10             	lea    0x10(%rax),%ecx
  4039a8:	83 e2 f0             	and    $0xfffffff0,%edx
  4039ab:	83 e1 f0             	and    $0xfffffff0,%ecx
  4039ae:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  4039b4:	c5 fa 7f 83 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%rbx)
  4039bc:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
  4039c0:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
  4039c5:	48 89 8b 58 01 00 00 	mov    %rcx,0x158(%rbx)
  4039cc:	8d 48 20             	lea    0x20(%rax),%ecx
  4039cf:	83 e1 f0             	and    $0xfffffff0,%ecx
  4039d2:	48 89 93 50 01 00 00 	mov    %rdx,0x150(%rbx)
  4039d9:	89 d2                	mov    %edx,%edx
  4039db:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  4039e1:	8d 48 30             	lea    0x30(%rax),%ecx
  4039e4:	83 e1 f0             	and    $0xfffffff0,%ecx
  4039e7:	c5 fa 7f 83 40 01 00 00 	vmovdqu %xmm0,0x140(%rbx)
  4039ef:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  4039f5:	8d 48 40             	lea    0x40(%rax),%ecx
  4039f8:	83 e1 f0             	and    $0xfffffff0,%ecx
  4039fb:	c5 fa 7f 83 00 01 00 00 	vmovdqu %xmm0,0x100(%rbx)
  403a03:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  403a09:	8d 48 50             	lea    0x50(%rax),%ecx
  403a0c:	48 83 c0 60          	add    $0x60,%rax
  403a10:	83 e1 f0             	and    $0xfffffff0,%ecx
  403a13:	c5 fa 7f 83 30 01 00 00 	vmovdqu %xmm0,0x130(%rbx)
  403a1b:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  403a21:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
  403a28:	c5 fa 7f 83 20 01 00 00 	vmovdqu %xmm0,0x120(%rbx)
  403a30:	49 63 74 11 78       	movslq 0x78(%r9,%rdx,1),%rsi
  403a35:	83 c0 20             	add    $0x20,%eax
  403a38:	83 e0 f0             	and    $0xfffffff0,%eax
  403a3b:	48 89 73 50          	mov    %rsi,0x50(%rbx)
  403a3f:	48 89 f1             	mov    %rsi,%rcx
  403a42:	49 8d 74 11 74       	lea    0x74(%r9,%rdx,1),%rsi
  403a47:	48 63 16             	movslq (%rsi),%rdx
  403a4a:	48 89 53 30          	mov    %rdx,0x30(%rbx)
  403a4e:	49 8b 3c 01          	mov    (%r9,%rax,1),%rdi
  403a52:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
  403a57:	48 89 7b 40          	mov    %rdi,0x40(%rbx)
  403a5b:	48 89 43 48          	mov    %rax,0x48(%rbx)
  403a5f:	85 c9                	test   %ecx,%ecx
  403a61:	74 0f                	je     403a72 <full_before_execute+0x602>
  403a63:	48 29 fa             	sub    %rdi,%rdx
  403a66:	48 89 53 30          	mov    %rdx,0x30(%rbx)
  403a6a:	89 16                	mov    %edx,(%rsi)
  403a6c:	0f 88 a6 0a 00 00    	js     404518 <full_before_execute+0x10a8>
  403a72:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
  403a79:	f6 c2 0f             	test   $0xf,%dl
  403a7c:	0f 85 8e 0c 00 00    	jne    404710 <full_before_execute+0x12a0>
  403a82:	48 8b 05 07 56 00 00 	mov    0x5607(%rip),%rax        # 409090 <g_ee_main_mem>
  403a89:	89 d2                	mov    %edx,%edx
  403a8b:	c5 fa 7e 24 10       	vmovq  (%rax,%rdx,1),%xmm4
  403a90:	48 8b 7c 10 08       	mov    0x8(%rax,%rdx,1),%rdi
  403a95:	c5 f9 d6 a3 00 03 00 00 	vmovq  %xmm4,0x300(%rbx)
  403a9d:	48 89 bb 08 03 00 00 	mov    %rdi,0x308(%rbx)
  403aa4:	48 8b 4c 10 10       	mov    0x10(%rax,%rdx,1),%rcx
  403aa9:	4c 8b 44 10 18       	mov    0x18(%rax,%rdx,1),%r8
  403aae:	48 89 8b 10 03 00 00 	mov    %rcx,0x310(%rbx)
  403ab5:	4c 89 83 18 03 00 00 	mov    %r8,0x318(%rbx)
  403abc:	48 8b 74 10 20       	mov    0x20(%rax,%rdx,1),%rsi
  403ac1:	48 8b 4c 10 28       	mov    0x28(%rax,%rdx,1),%rcx
  403ac6:	48 8b 93 50 01 00 00 	mov    0x150(%rbx),%rdx
  403acd:	48 89 b3 20 03 00 00 	mov    %rsi,0x320(%rbx)
  403ad4:	48 89 8b 28 03 00 00 	mov    %rcx,0x328(%rbx)
  403adb:	f6 c2 0f             	test   $0xf,%dl
  403ade:	0f 85 2c 0c 00 00    	jne    404710 <full_before_execute+0x12a0>
  403ae4:	89 d2                	mov    %edx,%edx
  403ae6:	c4 e3 d9 22 e7 01    	vpinsrq $0x1,%rdi,%xmm4,%xmm4
  403aec:	c5 fa 10 bb 88 03 00 00 	vmovss 0x388(%rbx),%xmm7
  403af4:	c4 e2 79 18 93 84 03 00 00 	vbroadcastss 0x384(%rbx),%xmm2
  403afd:	48 8d 7c 10 10       	lea    0x10(%rax,%rdx,1),%rdi
  403b02:	c5 7a 10 93 8c 03 00 00 	vmovss 0x38c(%rbx),%xmm10
  403b0a:	4c 8b 37             	mov    (%rdi),%r14
  403b0d:	4c 8b 5f 08          	mov    0x8(%rdi),%r11
  403b11:	c5 c0 c6 f7 00       	vshufps $0x0,%xmm7,%xmm7,%xmm6
  403b16:	4c 89 b3 30 03 00 00 	mov    %r14,0x330(%rbx)
  403b1d:	c4 41 79 6e ee       	vmovd  %r14d,%xmm13
  403b22:	4c 89 9b 38 03 00 00 	mov    %r11,0x338(%rbx)
  403b29:	4c 8b 4c 10 20       	mov    0x20(%rax,%rdx,1),%r9
  403b2e:	4c 8b 64 10 28       	mov    0x28(%rax,%rdx,1),%r12
  403b33:	4c 89 8b 40 03 00 00 	mov    %r9,0x340(%rbx)
  403b3a:	4c 89 a3 48 03 00 00 	mov    %r12,0x348(%rbx)
  403b41:	c5 fa 7e 44 10 30    	vmovq  0x30(%rax,%rdx,1),%xmm0
  403b47:	4c 8b 54 10 38       	mov    0x38(%rax,%rdx,1),%r10
  403b4c:	c5 f9 d6 83 50 03 00 00 	vmovq  %xmm0,0x350(%rbx)
  403b54:	c4 c3 f9 22 ca 01    	vpinsrq $0x1,%r10,%xmm0,%xmm1
  403b5a:	c5 fa 7e 83 84 03 00 00 	vmovq  0x384(%rbx),%xmm0
  403b62:	4c 89 93 58 03 00 00 	mov    %r10,0x358(%rbx)
  403b69:	c5 fa 6f 5c 10 40    	vmovdqu 0x40(%rax,%rdx,1),%xmm3
  403b6f:	c5 fa 16 c0          	vmovshdup %xmm0,%xmm0
  403b73:	c5 f9 6f eb          	vmovdqa %xmm3,%xmm5
  403b77:	c5 fa 7f 9b 60 03 00 00 	vmovdqu %xmm3,0x360(%rbx)
  403b7f:	c5 79 6f cb          	vmovdqa %xmm3,%xmm9
  403b83:	4c 63 6c 10 60       	movslq 0x60(%rax,%rdx,1),%r13
  403b88:	c5 c8 59 f3          	vmulps %xmm3,%xmm6,%xmm6
  403b8c:	c5 d0 c6 ed 55       	vshufps $0x55,%xmm5,%xmm5,%xmm5
  403b91:	c4 c1 f9 6e de       	vmovq  %r14,%xmm3
  403b96:	c5 79 6f c5          	vmovdqa %xmm5,%xmm8
  403b9a:	c5 e0 c6 db 55       	vshufps $0x55,%xmm3,%xmm3,%xmm3
  403b9f:	c5 79 6f e3          	vmovdqa %xmm3,%xmm12
  403ba3:	c4 c1 30 14 d8       	vunpcklps %xmm8,%xmm9,%xmm3
  403ba8:	4c 89 da             	mov    %r11,%rdx
  403bab:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
  403baf:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  403bb3:	4c 89 6b 30          	mov    %r13,0x30(%rbx)
  403bb7:	4d 89 ea             	mov    %r13,%r10
  403bba:	c5 f8 59 c3          	vmulps %xmm3,%xmm0,%xmm0
  403bbe:	c4 c1 10 14 dc       	vunpcklps %xmm12,%xmm13,%xmm3
  403bc3:	44 89 ab 00 02 00 00 	mov    %r13d,0x200(%rbx)
  403bca:	48 c1 ea 20          	shr    $0x20,%rdx
  403bce:	c4 e2 7d 18 ab 84 03 00 00 	vbroadcastss 0x384(%rbx),%ymm5
  403bd7:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
  403bdb:	c5 f8 29 b3 60 03 00 00 	vmovaps %xmm6,0x360(%rbx)
  403be3:	c5 c8 15 f6          	vunpckhps %xmm6,%xmm6,%xmm6
  403be7:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  403beb:	c5 f8 58 db          	vaddps %xmm3,%xmm0,%xmm3
  403bef:	c4 c1 79 6e c3       	vmovd  %r11d,%xmm0
  403bf4:	c5 ca 58 f0          	vaddss %xmm0,%xmm6,%xmm6
  403bf8:	c5 f8 13 9b 30 03 00 00 	vmovlps %xmm3,0x330(%rbx)
  403c00:	c5 fa 11 b3 38 03 00 00 	vmovss %xmm6,0x338(%rbx)
  403c08:	45 85 ed             	test   %r13d,%r13d
  403c0b:	0f 85 ef 06 00 00    	jne    404300 <full_before_execute+0xe90>
  403c11:	c5 fa 16 fb          	vmovshdup %xmm3,%xmm7
  403c15:	c5 f8 28 c3          	vmovaps %xmm3,%xmm0
  403c19:	c5 e8 59 c9          	vmulps %xmm1,%xmm2,%xmm1
  403c1d:	c5 f9 6e da          	vmovd  %edx,%xmm3
  403c21:	c5 f8 14 c7          	vunpcklps %xmm7,%xmm0,%xmm0
  403c25:	49 c1 e8 20          	shr    $0x20,%r8
  403c29:	c5 c8 14 f3          	vunpcklps %xmm3,%xmm6,%xmm6
  403c2d:	c5 f8 16 de          	vmovlhps %xmm6,%xmm0,%xmm3
  403c31:	c5 e0 59 d2          	vmulps %xmm2,%xmm3,%xmm2
  403c35:	c4 c1 79 6e f4       	vmovd  %r12d,%xmm6
  403c3a:	49 c1 ec 20          	shr    $0x20,%r12
  403c3e:	c4 c1 79 6e c1       	vmovd  %r9d,%xmm0
  403c43:	c4 c1 79 6e fc       	vmovd  %r12d,%xmm7
  403c48:	49 c1 e9 20          	shr    $0x20,%r9
  403c4c:	c5 c8 14 f7          	vunpcklps %xmm7,%xmm6,%xmm6
  403c50:	c4 c1 79 6e f9       	vmovd  %r9d,%xmm7
  403c55:	c5 f8 14 c7          	vunpcklps %xmm7,%xmm0,%xmm0
  403c59:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
  403c5d:	c5 f8 29 8b b0 03 00 00 	vmovaps %xmm1,0x3b0(%rbx)
  403c65:	c5 f8 16 c6          	vmovlhps %xmm6,%xmm0,%xmm0
  403c69:	c4 e3 65 18 c0 01    	vinsertf128 $0x1,%xmm0,%ymm3,%ymm0
  403c6f:	c5 f0 15 f1          	vunpckhps %xmm1,%xmm1,%xmm6
  403c73:	c5 e8 58 d4          	vaddps %xmm4,%xmm2,%xmm2
  403c77:	c5 fc 59 c5          	vmulps %ymm5,%ymm0,%ymm0
  403c7b:	c5 f9 6e e6          	vmovd  %esi,%xmm4
  403c7f:	48 c1 ee 20          	shr    $0x20,%rsi
  403c83:	c5 f0 c6 e9 55       	vshufps $0x55,%xmm1,%xmm1,%xmm5
  403c88:	c5 f8 29 93 00 03 00 00 	vmovaps %xmm2,0x300(%rbx)
  403c90:	c5 f2 58 d4          	vaddss %xmm4,%xmm1,%xmm2
  403c94:	c5 f9 6e e6          	vmovd  %esi,%xmm4
  403c98:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
  403c9d:	c5 d2 58 ec          	vaddss %xmm4,%xmm5,%xmm5
  403ca1:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
  403ca5:	48 c1 e9 20          	shr    $0x20,%rcx
  403ca9:	c5 ca 58 f4          	vaddss %xmm4,%xmm6,%xmm6
  403cad:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
  403cb1:	c5 fc 11 83 90 03 00 00 	vmovups %ymm0,0x390(%rbx)
  403cb9:	c4 e3 7d 19 c0 01    	vextractf128 $0x1,%ymm0,%xmm0
  403cbf:	c5 ea c2 ff 05       	vcmpnltss %xmm7,%xmm2,%xmm7
  403cc4:	c5 f2 58 cc          	vaddss %xmm4,%xmm1,%xmm1
  403cc8:	c4 c1 79 6e e0       	vmovd  %r8d,%xmm4
  403ccd:	c5 f8 c6 c0 ff       	vshufps $0xff,%xmm0,%xmm0,%xmm0
  403cd2:	c5 fa 58 c4          	vaddss %xmm4,%xmm0,%xmm0
  403cd6:	c5 d8 57 e4          	vxorps %xmm4,%xmm4,%xmm4
  403cda:	c4 e3 59 4a e2 70    	vblendvps %xmm7,%xmm2,%xmm4,%xmm4
  403ce0:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
  403ce4:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
  403ce8:	c5 d2 c2 ff 05       	vcmpnltss %xmm7,%xmm5,%xmm7
  403ced:	c5 f8 14 c4          	vunpcklps %xmm4,%xmm0,%xmm0
  403cf1:	c4 e3 69 4a d5 70    	vblendvps %xmm7,%xmm5,%xmm2,%xmm2
  403cf7:	c5 c0 57 ff          	vxorps %xmm7,%xmm7,%xmm7
  403cfb:	c5 d0 57 ed          	vxorps %xmm5,%xmm5,%xmm5
  403cff:	c5 ca c2 ff 05       	vcmpnltss %xmm7,%xmm6,%xmm7
  403d04:	c4 e3 51 4a ee 70    	vblendvps %xmm7,%xmm6,%xmm5,%xmm5
  403d0a:	c5 e8 14 d5          	vunpcklps %xmm5,%xmm2,%xmm2
  403d0e:	c5 f8 16 c2          	vmovlhps %xmm2,%xmm0,%xmm0
  403d12:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
  403d16:	c5 f8 11 83 1c 03 00 00 	vmovups %xmm0,0x31c(%rbx)
  403d1e:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  403d22:	c5 f2 c2 d2 05       	vcmpnltss %xmm2,%xmm1,%xmm2
  403d27:	c4 e3 79 4a c1 20    	vblendvps %xmm2,%xmm1,%xmm0,%xmm0
  403d2d:	c5 fa 11 83 2c 03 00 00 	vmovss %xmm0,0x32c(%rbx)
  403d35:	c5 f8 11 1f          	vmovups %xmm3,(%rdi)
  403d39:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
  403d40:	f6 c2 0f             	test   $0xf,%dl
  403d43:	0f 85 08 0a 00 00    	jne    404751 <full_before_execute+0x12e1>
  403d49:	c5 f9 6f 83 00 03 00 00 	vmovdqa 0x300(%rbx),%xmm0
  403d51:	89 d2                	mov    %edx,%edx
  403d53:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
  403d58:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
  403d5f:	f6 c2 0f             	test   $0xf,%dl
  403d62:	0f 85 e9 09 00 00    	jne    404751 <full_before_execute+0x12e1>
  403d68:	c5 f9 6f 83 10 03 00 00 	vmovdqa 0x310(%rbx),%xmm0
  403d70:	89 d2                	mov    %edx,%edx
  403d72:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
  403d78:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
  403d7f:	f6 c2 0f             	test   $0xf,%dl
  403d82:	0f 85 c9 09 00 00    	jne    404751 <full_before_execute+0x12e1>
  403d88:	c5 f9 6f 83 20 03 00 00 	vmovdqa 0x320(%rbx),%xmm0
  403d90:	89 d2                	mov    %edx,%edx
  403d92:	c5 fa 10 2d ce 31 00 00 	vmovss 0x31ce(%rip),%xmm5        # 406f68 <typeinfo for Boundary+0x158>
  403d9a:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
  403da0:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
  403da7:	48 8b 8b 10 01 00 00 	mov    0x110(%rbx),%rcx
  403dae:	48 89 53 40          	mov    %rdx,0x40(%rbx)
  403db2:	89 d2                	mov    %edx,%edx
  403db4:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
  403db8:	8b 74 10 10          	mov    0x10(%rax,%rdx,1),%esi
  403dbc:	89 c9                	mov    %ecx,%ecx
  403dbe:	89 b3 00 02 00 00    	mov    %esi,0x200(%rbx)
  403dc4:	8b 7c 10 14          	mov    0x14(%rax,%rdx,1),%edi
  403dc8:	89 bb 04 02 00 00    	mov    %edi,0x204(%rbx)
  403dce:	8b 54 10 18          	mov    0x18(%rax,%rdx,1),%edx
  403dd2:	89 93 0c 02 00 00    	mov    %edx,0x20c(%rbx)
  403dd8:	89 34 08             	mov    %esi,(%rax,%rcx,1)
  403ddb:	8b 8b 04 02 00 00    	mov    0x204(%rbx),%ecx
  403de1:	8b 43 30             	mov    0x30(%rbx),%eax
  403de4:	48 8b 15 a5 52 00 00 	mov    0x52a5(%rip),%rdx        # 409090 <g_ee_main_mem>
  403deb:	89 4c 02 04          	mov    %ecx,0x4(%rdx,%rax,1)
  403def:	8b 8b 0c 02 00 00    	mov    0x20c(%rbx),%ecx
  403df5:	8b 43 30             	mov    0x30(%rbx),%eax
  403df8:	48 8b 15 91 52 00 00 	mov    0x5291(%rip),%rdx        # 409090 <g_ee_main_mem>
  403dff:	89 4c 02 08          	mov    %ecx,0x8(%rdx,%rax,1)
  403e03:	c5 fa 10 83 0c 02 00 00 	vmovss 0x20c(%rbx),%xmm0
  403e0b:	48 8b 15 7e 52 00 00 	mov    0x527e(%rip),%rdx        # 409090 <g_ee_main_mem>
  403e12:	8b 43 30             	mov    0x30(%rbx),%eax
  403e15:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
  403e19:	c5 d2 5c c8          	vsubss %xmm0,%xmm5,%xmm1
  403e1d:	c5 fa 11 83 0c 02 00 00 	vmovss %xmm0,0x20c(%rbx)
  403e25:	c5 fa 10 83 04 02 00 00 	vmovss 0x204(%rbx),%xmm0
  403e2d:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
  403e31:	c5 f2 5c c0          	vsubss %xmm0,%xmm1,%xmm0
  403e35:	c5 f8 14 c9          	vunpcklps %xmm1,%xmm0,%xmm1
  403e39:	c5 f8 13 8b 04 02 00 00 	vmovlps %xmm1,0x204(%rbx)
  403e41:	c5 fa 10 8b 00 02 00 00 	vmovss 0x200(%rbx),%xmm1
  403e49:	c5 f2 59 c9          	vmulss %xmm1,%xmm1,%xmm1
  403e4d:	c5 fa 5c c1          	vsubss %xmm1,%xmm0,%xmm0
  403e51:	c5 f8 54 05 67 30 00 00 	vandps 0x3067(%rip),%xmm0,%xmm0        # 406ec0 <typeinfo for Boundary+0xb0>
  403e59:	c5 fa 51 c0          	vsqrtss %xmm0,%xmm0,%xmm0
  403e5d:	c5 fa 11 83 00 02 00 00 	vmovss %xmm0,0x200(%rbx)
  403e65:	c5 fa 11 44 02 0c    	vmovss %xmm0,0xc(%rdx,%rax,1)
  403e6b:	48 63 83 00 02 00 00 	movslq 0x200(%rbx),%rax
  403e72:	4c 8b 0d 17 52 00 00 	mov    0x5217(%rip),%r9        # 409090 <g_ee_main_mem>
  403e79:	48 89 43 40          	mov    %rax,0x40(%rbx)
  403e7d:	48 8b 05 1c 52 00 00 	mov    0x521c(%rip),%rax        # 4090a0 <full_before_cache>
  403e84:	48 63 10             	movslq (%rax),%rdx
  403e87:	89 d0                	mov    %edx,%eax
  403e89:	48 89 53 30          	mov    %rdx,0x30(%rbx)
  403e8d:	41 8b 04 01          	mov    (%r9,%rax,1),%eax
  403e91:	89 83 00 02 00 00    	mov    %eax,0x200(%rbx)
  403e97:	0f b6 c0             	movzbl %al,%eax
  403e9a:	48 83 e8 0a          	sub    $0xa,%rax
  403e9e:	48 89 43 30          	mov    %rax,0x30(%rbx)
  403ea2:	0f 88 c3 00 00 00    	js     403f6b <full_before_execute+0xafb>
  403ea8:	48 8b 05 f9 51 00 00 	mov    0x51f9(%rip),%rax        # 4090a8 <full_before_cache+0x8>
  403eaf:	c5 fa 7e 93 10 01 00 00 	vmovq  0x110(%rbx),%xmm2
  403eb7:	c5 fa 7e ab a0 00 00 00 	vmovq  0xa0(%rbx),%xmm5
  403ebf:	c5 fa 7e a3 80 00 00 00 	vmovq  0x80(%rbx),%xmm4
  403ec7:	48 63 08             	movslq (%rax),%rcx
  403eca:	c5 e9 6c ca          	vpunpcklqdq %xmm2,%xmm2,%xmm1
  403ece:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  403ed5:	c5 f9 d6 53 40       	vmovq  %xmm2,0x40(%rbx)
  403eda:	c4 e3 d1 22 9b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm5,%xmm3
  403ee4:	48 63 93 f0 01 00 00 	movslq 0x1f0(%rbx),%rdx
  403eeb:	c5 f9 d6 53 50       	vmovq  %xmm2,0x50(%rbx)
  403ef0:	48 83 c0 50          	add    $0x50,%rax
  403ef4:	48 89 8b 90 01 00 00 	mov    %rcx,0x190(%rbx)
  403efb:	48 89 cf             	mov    %rcx,%rdi
  403efe:	c4 e1 f9 6e f0       	vmovq  %rax,%xmm6
  403f03:	c4 e3 c9 22 43 70 01 	vpinsrq $0x1,0x70(%rbx),%xmm6,%xmm0
  403f0a:	48 89 43 60          	mov    %rax,0x60(%rbx)
  403f0e:	48 89 53 20          	mov    %rdx,0x20(%rbx)
  403f12:	c4 e3 75 18 c8 01    	vinsertf128 $0x1,%xmm0,%ymm1,%ymm1
  403f18:	c4 e3 d9 22 83 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm4,%xmm0
  403f22:	c5 fd 7f 8c 24 80 00 00 00 	vmovdqa %ymm1,0x80(%rsp)
  403f2b:	c4 e3 7d 18 c3 01    	vinsertf128 $0x1,%xmm3,%ymm0,%ymm0
  403f31:	c5 fd 7f 84 24 a0 00 00 00 	vmovdqa %ymm0,0xa0(%rsp)
  403f3a:	85 c9                	test   %ecx,%ecx
  403f3c:	0f 84 ed 07 00 00    	je     40472f <full_before_execute+0x12bf>
  403f42:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
  403f49:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
  403f50:	89 ff                	mov    %edi,%edi
  403f52:	31 d2                	xor    %edx,%edx
  403f54:	4c 01 cf             	add    %r9,%rdi
  403f57:	48 8d b4 24 80 00 00 00 	lea    0x80(%rsp),%rsi
  403f5f:	c5 f8 77             	vzeroupper
  403f62:	e8 39 f4 ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  403f67:	48 89 43 20          	mov    %rax,0x20(%rbx)
  403f6b:	48 8b 05 36 51 00 00 	mov    0x5136(%rip),%rax        # 4090a8 <full_before_cache+0x8>
  403f72:	c5 fa 7e ab a0 00 00 00 	vmovq  0xa0(%rbx),%xmm5
  403f7a:	c5 fa 7e b3 80 00 00 00 	vmovq  0x80(%rbx),%xmm6
  403f82:	c5 fa 7e 83 10 01 00 00 	vmovq  0x110(%rbx),%xmm0
  403f8a:	48 63 00             	movslq (%rax),%rax
  403f8d:	48 63 93 f0 01 00 00 	movslq 0x1f0(%rbx),%rdx
  403f94:	c4 e3 d1 22 8b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm5,%xmm1
  403f9e:	c5 f9 d6 43 40       	vmovq  %xmm0,0x40(%rbx)
  403fa3:	c4 e3 c9 22 93 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm6,%xmm2
  403fad:	48 89 83 90 01 00 00 	mov    %rax,0x190(%rbx)
  403fb4:	48 89 c7             	mov    %rax,%rdi
  403fb7:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  403fbe:	c4 e3 6d 18 d1 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm2
  403fc4:	c5 f9 d6 43 50       	vmovq  %xmm0,0x50(%rbx)
  403fc9:	c5 f9 6c c0          	vpunpcklqdq %xmm0,%xmm0,%xmm0
  403fcd:	48 83 c0 50          	add    $0x50,%rax
  403fd1:	48 89 53 20          	mov    %rdx,0x20(%rbx)
  403fd5:	c4 e1 f9 6e e8       	vmovq  %rax,%xmm5
  403fda:	c4 e3 d1 22 4b 70 01 	vpinsrq $0x1,0x70(%rbx),%xmm5,%xmm1
  403fe1:	48 89 43 60          	mov    %rax,0x60(%rbx)
  403fe5:	c5 fd 7f 94 24 e0 00 00 00 	vmovdqa %ymm2,0xe0(%rsp)
  403fee:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
  403ff4:	c5 fd 7f 84 24 c0 00 00 00 	vmovdqa %ymm0,0xc0(%rsp)
  403ffd:	85 ff                	test   %edi,%edi
  403fff:	0f 84 2a 07 00 00    	je     40472f <full_before_execute+0x12bf>
  404005:	4c 8b 0d 84 50 00 00 	mov    0x5084(%rip),%r9        # 409090 <g_ee_main_mem>
  40400c:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
  404013:	89 ff                	mov    %edi,%edi
  404015:	31 d2                	xor    %edx,%edx
  404017:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
  40401e:	48 8d b4 24 c0 00 00 00 	lea    0xc0(%rsp),%rsi
  404026:	4c 01 cf             	add    %r9,%rdi
  404029:	c5 f8 77             	vzeroupper
  40402c:	e8 6f f3 ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  404031:	48 8b 8b 10 01 00 00 	mov    0x110(%rbx),%rcx
  404038:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  40403c:	48 89 43 20          	mov    %rax,0x20(%rbx)
  404040:	4c 8b 0d 49 50 00 00 	mov    0x5049(%rip),%r9        # 409090 <g_ee_main_mem>
  404047:	48 8b 83 40 01 00 00 	mov    0x140(%rbx),%rax
  40404e:	89 ca                	mov    %ecx,%edx
  404050:	48 89 4b 30          	mov    %rcx,0x30(%rbx)
  404054:	48 89 43 40          	mov    %rax,0x40(%rbx)
  404058:	c4 c1 79 6e 44 11 0c 	vmovd  0xc(%r9,%rdx,1),%xmm0
  40405f:	c7 83 04 02 00 00 00 00 00 00 	movl   $0x0,0x204(%rbx)
  404069:	c5 f8 2f c8          	vcomiss %xmm0,%xmm1
  40406d:	c5 f9 7e 83 00 02 00 00 	vmovd  %xmm0,0x200(%rbx)
  404075:	0f 87 25 03 00 00    	ja     4043a0 <full_before_execute+0xf30>
  40407b:	a8 0f                	test   $0xf,%al
  40407d:	0f 85 8d 06 00 00    	jne    404710 <full_before_execute+0x12a0>
  404083:	89 c0                	mov    %eax,%eax
  404085:	83 e1 0f             	and    $0xf,%ecx
  404088:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
  40408d:	48 8b 07             	mov    (%rdi),%rax
  404090:	48 8b 77 08          	mov    0x8(%rdi),%rsi
  404094:	48 89 83 90 02 00 00 	mov    %rax,0x290(%rbx)
  40409b:	48 89 b3 98 02 00 00 	mov    %rsi,0x298(%rbx)
  4040a2:	0f 85 68 06 00 00    	jne    404710 <full_before_execute+0x12a0>
  4040a8:	49 8b 0c 11          	mov    (%r9,%rdx,1),%rcx
  4040ac:	49 8b 44 11 08       	mov    0x8(%r9,%rdx,1),%rax
  4040b1:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
  4040b5:	48 c1 ee 20          	shr    $0x20,%rsi
  4040b9:	c5 f9 6e fe          	vmovd  %esi,%xmm7
  4040bd:	48 89 8b a0 02 00 00 	mov    %rcx,0x2a0(%rbx)
  4040c4:	c5 f9 6e c1          	vmovd  %ecx,%xmm0
  4040c8:	48 c1 e9 20          	shr    $0x20,%rcx
  4040cc:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
  4040d0:	48 89 83 a8 02 00 00 	mov    %rax,0x2a8(%rbx)
  4040d7:	c5 f8 14 c4          	vunpcklps %xmm4,%xmm0,%xmm0
  4040db:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  4040df:	c5 f8 58 c2          	vaddps %xmm2,%xmm0,%xmm0
  4040e3:	c5 f9 6e d0          	vmovd  %eax,%xmm2
  4040e7:	c5 ea 58 c9          	vaddss %xmm1,%xmm2,%xmm1
  4040eb:	c5 f8 13 83 90 02 00 00 	vmovlps %xmm0,0x290(%rbx)
  4040f3:	c5 fa 11 8b 98 02 00 00 	vmovss %xmm1,0x298(%rbx)
  4040fb:	c5 f0 14 cf          	vunpcklps %xmm7,%xmm1,%xmm1
  4040ff:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
  404103:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
  404107:	48 8b 83 90 02 00 00 	mov    0x290(%rbx),%rax
  40410e:	48 8b 93 98 02 00 00 	mov    0x298(%rbx),%rdx
  404115:	48 89 43 40          	mov    %rax,0x40(%rbx)
  404119:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  404120:	c5 f8 28 83 20 03 00 00 	vmovaps 0x320(%rbx),%xmm0
  404128:	48 89 53 48          	mov    %rdx,0x48(%rbx)
  40412c:	89 c2                	mov    %eax,%edx
  40412e:	c5 f8 11 43 30       	vmovups %xmm0,0x30(%rbx)
  404133:	49 63 4c 11 68       	movslq 0x68(%r9,%rdx,1),%rcx
  404138:	48 89 4b 40          	mov    %rcx,0x40(%rbx)
  40413c:	48 89 ca             	mov    %rcx,%rdx
  40413f:	83 e1 04             	and    $0x4,%ecx
  404142:	89 cf                	mov    %ecx,%edi
  404144:	48 89 7b 50          	mov    %rdi,0x50(%rbx)
  404148:	f6 c2 02             	test   $0x2,%dl
  40414b:	74 31                	je     40417e <full_before_execute+0xd0e>
  40414d:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
  404152:	c7 43 60 00 00 00 00 	movl   $0x0,0x60(%rbx)
  404159:	c4 e3 79 16 43 64 02 	vpextrd $0x2,%xmm0,0x64(%rbx)
  404160:	c4 e3 79 16 43 6c 03 	vpextrd $0x3,%xmm0,0x6c(%rbx)
  404167:	c7 43 68 00 00 00 00 	movl   $0x0,0x68(%rbx)
  40416e:	48 85 f6             	test   %rsi,%rsi
  404171:	75 0b                	jne    40417e <full_before_execute+0xd0e>
  404173:	48 83 7b 60 00       	cmpq   $0x0,0x60(%rbx)
  404178:	0f 84 92 00 00 00    	je     404210 <full_before_execute+0xda0>
  40417e:	83 e2 01             	and    $0x1,%edx
  404181:	89 d7                	mov    %edx,%edi
  404183:	48 89 7b 40          	mov    %rdi,0x40(%rbx)
  404187:	85 c9                	test   %ecx,%ecx
  404189:	74 24                	je     4041af <full_before_execute+0xd3f>
  40418b:	48 c7 43 38 00 00 00 00 	movq   $0x0,0x38(%rbx)
  404193:	c4 e3 79 16 43 34 03 	vpextrd $0x3,%xmm0,0x34(%rbx)
  40419a:	c4 e3 79 16 43 38 02 	vpextrd $0x2,%xmm0,0x38(%rbx)
  4041a1:	c7 43 30 00 00 00 00 	movl   $0x0,0x30(%rbx)
  4041a8:	48 83 7b 30 00       	cmpq   $0x0,0x30(%rbx)
  4041ad:	7e 61                	jle    404210 <full_before_execute+0xda0>
  4041af:	85 d2                	test   %edx,%edx
  4041b1:	0f 84 19 f5 ff ff    	je     4036d0 <full_before_execute+0x260>
  4041b7:	c5 f8 28 83 00 03 00 00 	vmovaps 0x300(%rbx),%xmm0
  4041bf:	c5 f8 11 43 30       	vmovups %xmm0,0x30(%rbx)
  4041c4:	c4 e3 79 16 43 34 03 	vpextrd $0x3,%xmm0,0x34(%rbx)
  4041cb:	c5 f8 28 83 10 03 00 00 	vmovaps 0x310(%rbx),%xmm0
  4041d3:	c7 43 30 00 00 00 00 	movl   $0x0,0x30(%rbx)
  4041da:	48 8b 53 30          	mov    0x30(%rbx),%rdx
  4041de:	c5 f8 11 43 30       	vmovups %xmm0,0x30(%rbx)
  4041e3:	48 85 d2             	test   %rdx,%rdx
  4041e6:	78 28                	js     404210 <full_before_execute+0xda0>
  4041e8:	48 c7 43 38 00 00 00 00 	movq   $0x0,0x38(%rbx)
  4041f0:	c4 e3 79 16 43 34 03 	vpextrd $0x3,%xmm0,0x34(%rbx)
  4041f7:	c4 e3 79 16 43 38 02 	vpextrd $0x2,%xmm0,0x38(%rbx)
  4041fe:	c7 43 30 00 00 00 00 	movl   $0x0,0x30(%rbx)
  404205:	48 83 7b 30 00       	cmpq   $0x0,0x30(%rbx)
  40420a:	0f 89 c0 f4 ff ff    	jns    4036d0 <full_before_execute+0x260>
  404210:	48 8b 15 99 4e 00 00 	mov    0x4e99(%rip),%rdx        # 4090b0 <full_before_cache+0x10>
  404217:	c5 fa 7e 83 c0 01 00 00 	vmovq  0x1c0(%rbx),%xmm0
  40421f:	48 8b 8b 00 01 00 00 	mov    0x100(%rbx),%rcx
  404226:	c5 fa 7e a3 a0 00 00 00 	vmovq  0xa0(%rbx),%xmm4
  40422e:	48 63 12             	movslq (%rdx),%rdx
  404231:	c5 fa 7e ab 80 00 00 00 	vmovq  0x80(%rbx),%xmm5
  404239:	c5 f9 d6 43 40       	vmovq  %xmm0,0x40(%rbx)
  40423e:	c4 e3 d9 22 93 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm4,%xmm2
  404248:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
  40424d:	c4 e3 f9 22 c1 01    	vpinsrq $0x1,%rcx,%xmm0,%xmm0
  404253:	48 63 b3 f0 01 00 00 	movslq 0x1f0(%rbx),%rsi
  40425a:	48 89 93 90 01 00 00 	mov    %rdx,0x190(%rbx)
  404261:	48 89 d7             	mov    %rdx,%rdi
  404264:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
  40426b:	c4 e3 d1 22 8b 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm5,%xmm1
  404275:	48 89 4b 50          	mov    %rcx,0x50(%rbx)
  404279:	48 89 43 60          	mov    %rax,0x60(%rbx)
  40427d:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
  404283:	c4 e3 d9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm4,%xmm2
  404289:	48 89 53 70          	mov    %rdx,0x70(%rbx)
  40428d:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
  404293:	48 89 73 20          	mov    %rsi,0x20(%rbx)
  404297:	c5 fd 7f 84 24 00 01 00 00 	vmovdqa %ymm0,0x100(%rsp)
  4042a0:	c5 fd 7f 8c 24 20 01 00 00 	vmovdqa %ymm1,0x120(%rsp)
  4042a9:	85 ff                	test   %edi,%edi
  4042ab:	0f 84 7e 04 00 00    	je     40472f <full_before_execute+0x12bf>
  4042b1:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
  4042b8:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
  4042bf:	89 ff                	mov    %edi,%edi
  4042c1:	31 d2                	xor    %edx,%edx
  4042c3:	4c 01 cf             	add    %r9,%rdi
  4042c6:	48 8d b4 24 00 01 00 00 	lea    0x100(%rsp),%rsi
  4042ce:	c5 f8 77             	vzeroupper
  4042d1:	e8 ca f0 ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  4042d6:	4c 8b 0d b3 4d 00 00 	mov    0x4db3(%rip),%r9        # 409090 <g_ee_main_mem>
  4042dd:	48 89 43 20          	mov    %rax,0x20(%rbx)
  4042e1:	48 8b 83 50 01 00 00 	mov    0x150(%rbx),%rax
  4042e8:	e9 e3 f3 ff ff       	jmp    4036d0 <full_before_execute+0x260>
  4042ed:	0f 1f 00             	nopl   (%rax)
  4042f0:	48 89 53 30          	mov    %rdx,0x30(%rbx)
  4042f4:	e9 5f f4 ff ff       	jmp    403758 <full_before_execute+0x2e8>
  4042f9:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  404300:	c4 c1 79 6e c5       	vmovd  %r13d,%xmm0
  404305:	4c 8b 73 38          	mov    0x38(%rbx),%r14
  404309:	49 c1 ea 20          	shr    $0x20,%r10
  40430d:	c5 fa 7e db          	vmovq  %xmm3,%xmm3
  404311:	c5 7a 10 35 4f 2c 00 00 	vmovss 0x2c4f(%rip),%xmm14        # 406f68 <typeinfo for Boundary+0x158>
  404319:	c4 41 79 6e fe       	vmovd  %r14d,%xmm15
  40431e:	c5 0a 5c d8          	vsubss %xmm0,%xmm14,%xmm11
  404322:	c5 aa 59 c0          	vmulss %xmm0,%xmm10,%xmm0
  404326:	c4 41 22 59 da       	vmulss %xmm10,%xmm11,%xmm11
  40432b:	c4 41 0a 5c db       	vsubss %xmm11,%xmm14,%xmm11
  404330:	c4 41 79 6e f2       	vmovd  %r10d,%xmm14
  404335:	c4 41 2a 59 f6       	vmulss %xmm14,%xmm10,%xmm14
  40433a:	c4 41 2a 59 d7       	vmulss %xmm15,%xmm10,%xmm10
  40433f:	c4 c1 4a 59 f3       	vmulss %xmm11,%xmm6,%xmm6
  404344:	c4 c1 78 14 c6       	vunpcklps %xmm14,%xmm0,%xmm0
  404349:	c4 41 28 14 d3       	vunpcklps %xmm11,%xmm10,%xmm10
  40434e:	c4 c1 78 16 c2       	vmovlhps %xmm10,%xmm0,%xmm0
  404353:	c5 f8 29 83 70 03 00 00 	vmovaps %xmm0,0x370(%rbx)
  40435b:	c4 c1 42 59 c1       	vmulss %xmm9,%xmm7,%xmm0
  404360:	c4 c1 42 59 f8       	vmulss %xmm8,%xmm7,%xmm7
  404365:	c4 41 7a 12 c3       	vmovsldup %xmm11,%xmm8
  40436a:	c5 fa 11 b3 38 03 00 00 	vmovss %xmm6,0x338(%rbx)
  404372:	c4 41 7a 7e c0       	vmovq  %xmm8,%xmm8
  404377:	c4 c1 7a 58 c5       	vaddss %xmm13,%xmm0,%xmm0
  40437c:	c5 b8 59 db          	vmulps %xmm3,%xmm8,%xmm3
  404380:	c4 c1 42 58 fc       	vaddss %xmm12,%xmm7,%xmm7
  404385:	c4 c1 7a 59 c3       	vmulss %xmm11,%xmm0,%xmm0
  40438a:	c4 c1 42 59 fb       	vmulss %xmm11,%xmm7,%xmm7
  40438f:	c5 f8 13 9b 30 03 00 00 	vmovlps %xmm3,0x330(%rbx)
  404397:	e9 7d f8 ff ff       	jmp    403c19 <full_before_execute+0x7a9>
  40439c:	0f 1f 40 00          	nopl   0x0(%rax)
  4043a0:	a8 0f                	test   $0xf,%al
  4043a2:	0f 85 68 03 00 00    	jne    404710 <full_before_execute+0x12a0>
  4043a8:	89 c0                	mov    %eax,%eax
  4043aa:	83 e1 0f             	and    $0xf,%ecx
  4043ad:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
  4043b2:	48 8b 07             	mov    (%rdi),%rax
  4043b5:	48 8b 77 08          	mov    0x8(%rdi),%rsi
  4043b9:	48 89 83 90 02 00 00 	mov    %rax,0x290(%rbx)
  4043c0:	48 89 b3 98 02 00 00 	mov    %rsi,0x298(%rbx)
  4043c7:	0f 85 43 03 00 00    	jne    404710 <full_before_execute+0x12a0>
  4043cd:	49 8b 04 11          	mov    (%r9,%rdx,1),%rax
  4043d1:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
  4043d6:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  4043da:	48 c1 ee 20          	shr    $0x20,%rsi
  4043de:	c5 f9 6e f6          	vmovd  %esi,%xmm6
  4043e2:	48 89 83 a0 02 00 00 	mov    %rax,0x2a0(%rbx)
  4043e9:	c5 f9 6e d0          	vmovd  %eax,%xmm2
  4043ed:	48 c1 e8 20          	shr    $0x20,%rax
  4043f1:	c5 f9 6e e0          	vmovd  %eax,%xmm4
  4043f5:	48 89 93 a8 02 00 00 	mov    %rdx,0x2a8(%rbx)
  4043fc:	c5 e8 14 d4          	vunpcklps %xmm4,%xmm2,%xmm2
  404400:	c5 fa 7e d2          	vmovq  %xmm2,%xmm2
  404404:	c5 f8 5c c2          	vsubps %xmm2,%xmm0,%xmm0
  404408:	c5 f9 6e d2          	vmovd  %edx,%xmm2
  40440c:	c5 f2 5c ca          	vsubss %xmm2,%xmm1,%xmm1
  404410:	c5 f8 13 83 90 02 00 00 	vmovlps %xmm0,0x290(%rbx)
  404418:	c5 fa 11 8b 98 02 00 00 	vmovss %xmm1,0x298(%rbx)
  404420:	c5 f0 14 ce          	vunpcklps %xmm6,%xmm1,%xmm1
  404424:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
  404428:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
  40442c:	48 8b 83 90 02 00 00 	mov    0x290(%rbx),%rax
  404433:	48 8b 93 98 02 00 00 	mov    0x298(%rbx),%rdx
  40443a:	e9 d6 fc ff ff       	jmp    404115 <full_before_execute+0xca5>
  40443f:	90                   	nop
  404440:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
  404447:	48 89 4b 20          	mov    %rcx,0x20(%rbx)
  40444b:	89 c2                	mov    %eax,%edx
  40444d:	49 8b 34 11          	mov    (%r9,%rdx,1),%rsi
  404451:	48 89 b3 f0 01 00 00 	mov    %rsi,0x1f0(%rbx)
  404458:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
  40445d:	48 89 93 e0 01 00 00 	mov    %rdx,0x1e0(%rbx)
  404464:	8d 90 90 00 00 00    	lea    0x90(%rax),%edx
  40446a:	83 e2 f0             	and    $0xfffffff0,%edx
  40446d:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  404473:	8d 90 80 00 00 00    	lea    0x80(%rax),%edx
  404479:	83 e2 f0             	and    $0xfffffff0,%edx
  40447c:	c5 fa 7f 83 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%rbx)
  404484:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  40448a:	8d 50 70             	lea    0x70(%rax),%edx
  40448d:	83 e2 f0             	and    $0xfffffff0,%edx
  404490:	c5 fa 7f 83 50 01 00 00 	vmovdqu %xmm0,0x150(%rbx)
  404498:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  40449e:	8d 50 60             	lea    0x60(%rax),%edx
  4044a1:	83 e2 f0             	and    $0xfffffff0,%edx
  4044a4:	c5 fa 7f 83 40 01 00 00 	vmovdqu %xmm0,0x140(%rbx)
  4044ac:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  4044b2:	8d 50 50             	lea    0x50(%rax),%edx
  4044b5:	83 e2 f0             	and    $0xfffffff0,%edx
  4044b8:	c5 fa 7f 83 30 01 00 00 	vmovdqu %xmm0,0x130(%rbx)
  4044c0:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  4044c6:	8d 50 40             	lea    0x40(%rax),%edx
  4044c9:	83 e2 f0             	and    $0xfffffff0,%edx
  4044cc:	c5 fa 7f 83 20 01 00 00 	vmovdqu %xmm0,0x120(%rbx)
  4044d4:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  4044da:	8d 50 30             	lea    0x30(%rax),%edx
  4044dd:	48 05 a0 00 00 00    	add    $0xa0,%rax
  4044e3:	83 e2 f0             	and    $0xfffffff0,%edx
  4044e6:	c5 fa 7f 83 10 01 00 00 	vmovdqu %xmm0,0x110(%rbx)
  4044ee:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  4044f4:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
  4044fb:	48 89 c8             	mov    %rcx,%rax
  4044fe:	c5 fa 7f 83 00 01 00 00 	vmovdqu %xmm0,0x100(%rbx)
  404506:	48 8d 65 e0          	lea    -0x20(%rbp),%rsp
  40450a:	5b                   	pop    %rbx
  40450b:	41 5c                	pop    %r12
  40450d:	41 5d                	pop    %r13
  40450f:	41 5e                	pop    %r14
  404511:	5d                   	pop    %rbp
  404512:	c3                   	ret
  404513:	0f 1f 44 00 00       	nopl   0x0(%rax,%rax,1)
  404518:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
  40451f:	c5 f9 6f 83 c0 01 00 00 	vmovdqa 0x1c0(%rbx),%xmm0
  404527:	4c 8b 0d 62 4b 00 00 	mov    0x4b62(%rip),%r9        # 409090 <g_ee_main_mem>
  40452e:	48 83 e8 60          	sub    $0x60,%rax
  404532:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
  404539:	83 e0 f0             	and    $0xfffffff0,%eax
  40453c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404542:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  404548:	c5 f9 6f 83 50 01 00 00 	vmovdqa 0x150(%rbx),%xmm0
  404550:	83 c0 10             	add    $0x10,%eax
  404553:	83 e0 f0             	and    $0xfffffff0,%eax
  404556:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40455c:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  404562:	c5 f9 6f 83 40 01 00 00 	vmovdqa 0x140(%rbx),%xmm0
  40456a:	83 c0 20             	add    $0x20,%eax
  40456d:	83 e0 f0             	and    $0xfffffff0,%eax
  404570:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404576:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  40457c:	c5 f9 6f 83 00 01 00 00 	vmovdqa 0x100(%rbx),%xmm0
  404584:	83 c0 30             	add    $0x30,%eax
  404587:	83 e0 f0             	and    $0xfffffff0,%eax
  40458a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404590:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  404596:	c5 f9 6f 83 30 01 00 00 	vmovdqa 0x130(%rbx),%xmm0
  40459e:	83 c0 40             	add    $0x40,%eax
  4045a1:	83 e0 f0             	and    $0xfffffff0,%eax
  4045a4:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4045aa:	8b 83 d0 01 00 00    	mov    0x1d0(%rbx),%eax
  4045b0:	c5 f9 6f 83 20 01 00 00 	vmovdqa 0x120(%rbx),%xmm0
  4045b8:	83 c0 50             	add    $0x50,%eax
  4045bb:	83 e0 f0             	and    $0xfffffff0,%eax
  4045be:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4045c4:	c5 fa 7e 83 c0 01 00 00 	vmovq  0x1c0(%rbx),%xmm0
  4045cc:	48 8b 93 40 01 00 00 	mov    0x140(%rbx),%rdx
  4045d3:	c5 fa 7e 93 50 01 00 00 	vmovq  0x150(%rbx),%xmm2
  4045db:	48 8b 05 d6 4a 00 00 	mov    0x4ad6(%rip),%rax        # 4090b8 <full_before_cache+0x18>
  4045e2:	c5 f9 d6 43 40       	vmovq  %xmm0,0x40(%rbx)
  4045e7:	c5 fa 7e ab a0 00 00 00 	vmovq  0xa0(%rbx),%xmm5
  4045ef:	c5 f9 d6 53 60       	vmovq  %xmm2,0x60(%rbx)
  4045f4:	c4 e3 e9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm2,%xmm2
  4045fa:	48 89 53 70          	mov    %rdx,0x70(%rbx)
  4045fe:	48 63 08             	movslq (%rax),%rcx
  404601:	48 89 8b 90 01 00 00 	mov    %rcx,0x190(%rbx)
  404608:	48 89 c8             	mov    %rcx,%rax
  40460b:	48 63 8b f0 01 00 00 	movslq 0x1f0(%rbx),%rcx
  404612:	48 89 4b 20          	mov    %rcx,0x20(%rbx)
  404616:	c4 e3 d1 22 9b b0 00 00 00 01 	vpinsrq $0x1,0xb0(%rbx),%xmm5,%xmm3
  404620:	c5 fa 7e bb 80 00 00 00 	vmovq  0x80(%rbx),%xmm7
  404628:	c4 e3 f9 22 43 50 01 	vpinsrq $0x1,0x50(%rbx),%xmm0,%xmm0
  40462f:	c4 e3 c1 22 8b 90 00 00 00 01 	vpinsrq $0x1,0x90(%rbx),%xmm7,%xmm1
  404639:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
  40463f:	c4 e3 75 18 cb 01    	vinsertf128 $0x1,%xmm3,%ymm1,%ymm1
  404645:	c5 fd 7f 44 24 40    	vmovdqa %ymm0,0x40(%rsp)
  40464b:	c5 fd 7f 4c 24 60    	vmovdqa %ymm1,0x60(%rsp)
  404651:	85 c0                	test   %eax,%eax
  404653:	0f 84 d6 00 00 00    	je     40472f <full_before_execute+0x12bf>
  404659:	48 8b 8b 60 01 00 00 	mov    0x160(%rbx),%rcx
  404660:	89 c0                	mov    %eax,%eax
  404662:	31 d2                	xor    %edx,%edx
  404664:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
  404669:	4c 8b 83 70 01 00 00 	mov    0x170(%rbx),%r8
  404670:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
  404674:	c5 f8 77             	vzeroupper
  404677:	e8 24 ed ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  40467c:	48 8b 15 0d 4a 00 00 	mov    0x4a0d(%rip),%rdx        # 409090 <g_ee_main_mem>
  404683:	48 89 43 20          	mov    %rax,0x20(%rbx)
  404687:	48 8b 83 d0 01 00 00 	mov    0x1d0(%rbx),%rax
  40468e:	48 89 c1             	mov    %rax,%rcx
  404691:	83 e1 f0             	and    $0xfffffff0,%ecx
  404694:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  404699:	8d 48 10             	lea    0x10(%rax),%ecx
  40469c:	83 e1 f0             	and    $0xfffffff0,%ecx
  40469f:	c5 fa 7f 83 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%rbx)
  4046a7:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  4046ac:	8d 48 20             	lea    0x20(%rax),%ecx
  4046af:	83 e1 f0             	and    $0xfffffff0,%ecx
  4046b2:	c5 fa 7f 83 50 01 00 00 	vmovdqu %xmm0,0x150(%rbx)
  4046ba:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  4046bf:	8d 48 30             	lea    0x30(%rax),%ecx
  4046c2:	83 e1 f0             	and    $0xfffffff0,%ecx
  4046c5:	c5 fa 7f 83 40 01 00 00 	vmovdqu %xmm0,0x140(%rbx)
  4046cd:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  4046d2:	8d 48 40             	lea    0x40(%rax),%ecx
  4046d5:	83 e1 f0             	and    $0xfffffff0,%ecx
  4046d8:	c5 fa 7f 83 00 01 00 00 	vmovdqu %xmm0,0x100(%rbx)
  4046e0:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  4046e5:	8d 48 50             	lea    0x50(%rax),%ecx
  4046e8:	48 83 c0 60          	add    $0x60,%rax
  4046ec:	83 e1 f0             	and    $0xfffffff0,%ecx
  4046ef:	c5 fa 7f 83 30 01 00 00 	vmovdqu %xmm0,0x130(%rbx)
  4046f7:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  4046fc:	48 89 83 d0 01 00 00 	mov    %rax,0x1d0(%rbx)
  404703:	c5 fa 7f 83 20 01 00 00 	vmovdqu %xmm0,0x120(%rbx)
  40470b:	e9 62 f3 ff ff       	jmp    403a72 <full_before_execute+0x602>
  404710:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  404716:	b9 d8 69 40 00       	mov    $0x4069d8,%ecx
  40471b:	ba 58 01 00 00       	mov    $0x158,%edx
  404720:	be 10 6a 40 00       	mov    $0x406a10,%esi
  404725:	bf 50 6a 40 00       	mov    $0x406a50,%edi
  40472a:	e8 11 ed ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  40472f:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  404735:	b9 80 6a 40 00       	mov    $0x406a80,%ecx
  40473a:	ba 90 01 00 00       	mov    $0x190,%edx
  40473f:	be 10 6a 40 00       	mov    $0x406a10,%esi
  404744:	bf e6 65 40 00       	mov    $0x4065e6,%edi
  404749:	c5 f8 77             	vzeroupper
  40474c:	e8 ef ec ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  404751:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  404757:	b9 78 6b 40 00       	mov    $0x406b78,%ecx
  40475c:	ba c0 01 00 00       	mov    $0x1c0,%edx
  404761:	be 10 6a 40 00       	mov    $0x406a10,%esi
  404766:	bf b0 6b 40 00       	mov    $0x406bb0,%edi
  40476b:	c5 f8 77             	vzeroupper
  40476e:	e8 cd ec ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  404773:	66 2e 0f 1f 84 00 00 00 00 00 	cs nopw 0x0(%rax,%rax,1)
  40477d:	0f 1f 00             	nopl   (%rax)

0000000000404780 <full_after_execute>:
  404780:	55                   	push   %rbp
  404781:	48 89 e5             	mov    %rsp,%rbp
  404784:	41 57                	push   %r15
  404786:	41 56                	push   %r14
  404788:	41 55                	push   %r13
  40478a:	41 54                	push   %r12
  40478c:	53                   	push   %rbx
  40478d:	48 83 e4 e0          	and    $0xffffffffffffffe0,%rsp
  404791:	48 81 ec 80 01 00 00 	sub    $0x180,%rsp
  404798:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
  40479f:	48 8b 8f f0 01 00 00 	mov    0x1f0(%rdi),%rcx
  4047a6:	48 8b 15 e3 48 00 00 	mov    0x48e3(%rip),%rdx        # 409090 <g_ee_main_mem>
  4047ad:	48 2d a0 00 00 00    	sub    $0xa0,%rax
  4047b3:	48 89 87 d0 01 00 00 	mov    %rax,0x1d0(%rdi)
  4047ba:	89 c0                	mov    %eax,%eax
  4047bc:	48 89 0c 02          	mov    %rcx,(%rdx,%rax,1)
  4047c0:	48 8b 8f e0 01 00 00 	mov    0x1e0(%rdi),%rcx
  4047c7:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  4047cd:	48 8b 15 bc 48 00 00 	mov    0x48bc(%rip),%rdx        # 409090 <g_ee_main_mem>
  4047d4:	48 89 4c 02 08       	mov    %rcx,0x8(%rdx,%rax,1)
  4047d9:	48 8b 87 90 01 00 00 	mov    0x190(%rdi),%rax
  4047e0:	4c 8b 0d a9 48 00 00 	mov    0x48a9(%rip),%r9        # 409090 <g_ee_main_mem>
  4047e7:	c5 f9 6f 87 00 01 00 00 	vmovdqa 0x100(%rdi),%xmm0
  4047ef:	48 89 87 e0 01 00 00 	mov    %rax,0x1e0(%rdi)
  4047f6:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  4047fc:	83 c0 30             	add    $0x30,%eax
  4047ff:	83 e0 f0             	and    $0xfffffff0,%eax
  404802:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404808:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  40480e:	c5 f9 6f 87 10 01 00 00 	vmovdqa 0x110(%rdi),%xmm0
  404816:	83 c0 40             	add    $0x40,%eax
  404819:	83 e0 f0             	and    $0xfffffff0,%eax
  40481c:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404822:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  404828:	c5 f9 6f 87 20 01 00 00 	vmovdqa 0x120(%rdi),%xmm0
  404830:	83 c0 50             	add    $0x50,%eax
  404833:	83 e0 f0             	and    $0xfffffff0,%eax
  404836:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40483c:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  404842:	c5 f9 6f 87 30 01 00 00 	vmovdqa 0x130(%rdi),%xmm0
  40484a:	83 c0 60             	add    $0x60,%eax
  40484d:	83 e0 f0             	and    $0xfffffff0,%eax
  404850:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404856:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  40485c:	c5 f9 6f 87 40 01 00 00 	vmovdqa 0x140(%rdi),%xmm0
  404864:	83 c0 70             	add    $0x70,%eax
  404867:	83 e0 f0             	and    $0xfffffff0,%eax
  40486a:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404870:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  404876:	c5 f9 6f 87 50 01 00 00 	vmovdqa 0x150(%rdi),%xmm0
  40487e:	83 e8 80             	sub    $0xffffff80,%eax
  404881:	83 e0 f0             	and    $0xfffffff0,%eax
  404884:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40488a:	8b 87 d0 01 00 00    	mov    0x1d0(%rdi),%eax
  404890:	c5 f9 6f 87 c0 01 00 00 	vmovdqa 0x1c0(%rdi),%xmm0
  404898:	05 90 00 00 00       	add    $0x90,%eax
  40489d:	83 e0 f0             	and    $0xfffffff0,%eax
  4048a0:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4048a6:	48 8b 47 40          	mov    0x40(%rdi),%rax
  4048aa:	c5 f9 ef c0          	vpxor  %xmm0,%xmm0,%xmm0
  4048ae:	48 89 87 c0 01 00 00 	mov    %rax,0x1c0(%rdi)
  4048b5:	48 8b 47 50          	mov    0x50(%rdi),%rax
  4048b9:	48 89 87 50 01 00 00 	mov    %rax,0x150(%rdi)
  4048c0:	48 8b 47 60          	mov    0x60(%rdi),%rax
  4048c4:	48 89 87 40 01 00 00 	mov    %rax,0x140(%rdi)
  4048cb:	48 8b 47 70          	mov    0x70(%rdi),%rax
  4048cf:	48 89 87 00 01 00 00 	mov    %rax,0x100(%rdi)
  4048d6:	48 8b 87 80 00 00 00 	mov    0x80(%rdi),%rax
  4048dd:	48 89 87 30 01 00 00 	mov    %rax,0x130(%rdi)
  4048e4:	48 8b 87 90 00 00 00 	mov    0x90(%rdi),%rax
  4048eb:	48 89 87 20 01 00 00 	mov    %rax,0x120(%rdi)
  4048f2:	48 8b 87 d0 01 00 00 	mov    0x1d0(%rdi),%rax
  4048f9:	48 83 c0 10          	add    $0x10,%rax
  4048fd:	48 89 87 10 01 00 00 	mov    %rax,0x110(%rdi)
  404904:	83 e0 f0             	and    $0xfffffff0,%eax
  404907:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40490d:	48 8b 05 ac 47 00 00 	mov    0x47ac(%rip),%rax        # 4090c0 <full_after_cache>
  404914:	48 63 10             	movslq (%rax),%rdx
  404917:	48 89 57 30          	mov    %rdx,0x30(%rdi)
  40491b:	f6 c2 0f             	test   $0xf,%dl
  40491e:	0f 85 dc 11 00 00    	jne    405b00 <full_after_execute+0x1380>
  404924:	89 d0                	mov    %edx,%eax
  404926:	8b 9f d0 01 00 00    	mov    0x1d0(%rdi),%ebx
  40492c:	49 89 fe             	mov    %rdi,%r14
  40492f:	49 8b 4c 01 08       	mov    0x8(%r9,%rax,1),%rcx
  404934:	49 8b 14 01          	mov    (%r9,%rax,1),%rdx
  404938:	48 89 8f 88 03 00 00 	mov    %rcx,0x388(%rdi)
  40493f:	0f b6 c2             	movzbl %dl,%eax
  404942:	48 89 97 80 03 00 00 	mov    %rdx,0x380(%rdi)
  404949:	48 89 ca             	mov    %rcx,%rdx
  40494c:	48 89 4f 38          	mov    %rcx,0x38(%rdi)
  404950:	8d 4b 20             	lea    0x20(%rbx),%ecx
  404953:	83 e1 f0             	and    $0xfffffff0,%ecx
  404956:	48 89 47 30          	mov    %rax,0x30(%rdi)
  40495a:	49 89 04 09          	mov    %rax,(%r9,%rcx,1)
  40495e:	49 89 54 09 08       	mov    %rdx,0x8(%r9,%rcx,1)
  404963:	48 8b 87 50 01 00 00 	mov    0x150(%rdi),%rax
  40496a:	e9 b3 00 00 00       	jmp    404a22 <full_after_execute+0x2a2>
  40496f:	90                   	nop
  404970:	49 63 08             	movslq (%r8),%rcx
  404973:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
  40497b:	49 89 4e 30          	mov    %rcx,0x30(%r14)
  40497f:	85 c9                	test   %ecx,%ecx
  404981:	0f 84 60 01 00 00    	je     404ae7 <full_after_execute+0x367>
  404987:	8b 07                	mov    (%rdi),%eax
  404989:	89 c2                	mov    %eax,%edx
  40498b:	83 e0 bf             	and    $0xffffffbf,%eax
  40498e:	83 e2 40             	and    $0x40,%edx
  404991:	48 63 c8             	movslq %eax,%rcx
  404994:	89 d3                	mov    %edx,%ebx
  404996:	49 89 4e 40          	mov    %rcx,0x40(%r14)
  40499a:	49 89 5e 30          	mov    %rbx,0x30(%r14)
  40499e:	89 07                	mov    %eax,(%rdi)
  4049a0:	4c 8b 0d e9 46 00 00 	mov    0x46e9(%rip),%r9        # 409090 <g_ee_main_mem>
  4049a7:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
  4049ae:	85 d2                	test   %edx,%edx
  4049b0:	74 2e                	je     4049e0 <full_after_execute+0x260>
  4049b2:	89 c0                	mov    %eax,%eax
  4049b4:	49 63 54 01 7c       	movslq 0x7c(%r9,%rax,1),%rdx
  4049b9:	48 89 d0             	mov    %rdx,%rax
  4049bc:	49 89 56 30          	mov    %rdx,0x30(%r14)
  4049c0:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
  4049c7:	41 89 44 11 2c       	mov    %eax,0x2c(%r9,%rdx,1)
  4049cc:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
  4049d3:	4c 8b 0d b6 46 00 00 	mov    0x46b6(%rip),%r9        # 409090 <g_ee_main_mem>
  4049da:	66 0f 1f 44 00 00    	nopw   0x0(%rax,%rax,1)
  4049e0:	49 8b 9e 30 01 00 00 	mov    0x130(%r14),%rbx
  4049e7:	48 05 90 00 00 00    	add    $0x90,%rax
  4049ed:	49 83 86 40 01 00 00 30 	addq   $0x30,0x140(%r14)
  4049f5:	49 89 86 50 01 00 00 	mov    %rax,0x150(%r14)
  4049fc:	48 8d 53 ff          	lea    -0x1(%rbx),%rdx
  404a00:	49 8b 9e 00 01 00 00 	mov    0x100(%r14),%rbx
  404a07:	49 89 96 30 01 00 00 	mov    %rdx,0x130(%r14)
  404a0e:	48 8d 4b 01          	lea    0x1(%rbx),%rcx
  404a12:	49 89 8e 00 01 00 00 	mov    %rcx,0x100(%r14)
  404a19:	48 85 d2             	test   %rdx,%rdx
  404a1c:	0f 84 be 0f 00 00    	je     4059e0 <full_after_execute+0x1260>
  404a22:	89 c1                	mov    %eax,%ecx
  404a24:	49 8b b6 70 01 00 00 	mov    0x170(%r14),%rsi
  404a2b:	49 63 94 09 80 00 00 00 	movslq 0x80(%r9,%rcx,1),%rdx
  404a33:	49 89 56 30          	mov    %rdx,0x30(%r14)
  404a37:	48 39 d6             	cmp    %rdx,%rsi
  404a3a:	74 a4                	je     4049e0 <full_after_execute+0x260>
  404a3c:	49 8d 7c 09 68       	lea    0x68(%r9,%rcx,1),%rdi
  404a41:	4d 8d 44 09 64       	lea    0x64(%r9,%rcx,1),%r8
  404a46:	48 63 17             	movslq (%rdi),%rdx
  404a49:	49 3b b6 20 01 00 00 	cmp    0x120(%r14),%rsi
  404a50:	0f 84 fa 0b 00 00    	je     405650 <full_after_execute+0xed0>
  404a56:	81 e2 00 20 00 00    	and    $0x2000,%edx
  404a5c:	89 d3                	mov    %edx,%ebx
  404a5e:	49 89 5e 30          	mov    %rbx,0x30(%r14)
  404a62:	0f 84 08 ff ff ff    	je     404970 <full_after_execute+0x1f0>
  404a68:	41 8b 9e d0 01 00 00 	mov    0x1d0(%r14),%ebx
  404a6f:	49 63 30             	movslq (%r8),%rsi
  404a72:	49 c7 46 40 ff ff ff ff 	movq   $0xffffffffffffffff,0x40(%r14)
  404a7a:	8d 53 20             	lea    0x20(%rbx),%edx
  404a7d:	49 89 76 30          	mov    %rsi,0x30(%r14)
  404a81:	83 e2 f0             	and    $0xfffffff0,%edx
  404a84:	4d 8b 14 11          	mov    (%r9,%rdx,1),%r10
  404a88:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
  404a8d:	4d 89 56 40          	mov    %r10,0x40(%r14)
  404a91:	49 89 56 48          	mov    %rdx,0x48(%r14)
  404a95:	48 83 fe ff          	cmp    $0xffffffffffffffff,%rsi
  404a99:	0f 84 49 01 00 00    	je     404be8 <full_after_execute+0x468>
  404a9f:	48 89 f1             	mov    %rsi,%rcx
  404aa2:	c5 f9 6e fa          	vmovd  %edx,%xmm7
  404aa6:	4c 29 d1             	sub    %r10,%rcx
  404aa9:	49 89 d2             	mov    %rdx,%r10
  404aac:	48 89 cf             	mov    %rcx,%rdi
  404aaf:	49 c1 fa 20          	sar    $0x20,%r10
  404ab3:	c5 f9 6e d9          	vmovd  %ecx,%xmm3
  404ab7:	49 89 4e 40          	mov    %rcx,0x40(%r14)
  404abb:	48 c1 ff 20          	sar    $0x20,%rdi
  404abf:	c4 c3 41 22 ca 01    	vpinsrd $0x1,%r10d,%xmm7,%xmm1
  404ac5:	c4 e3 61 22 c7 01    	vpinsrd $0x1,%edi,%xmm3,%xmm0
  404acb:	c5 f9 6c c1          	vpunpcklqdq %xmm1,%xmm0,%xmm0
  404acf:	c5 f1 ef c9          	vpxor  %xmm1,%xmm1,%xmm1
  404ad3:	c4 e2 79 3d c1       	vpmaxsd %xmm1,%xmm0,%xmm0
  404ad8:	c4 c1 79 7f 46 30    	vmovdqa %xmm0,0x30(%r14)
  404ade:	48 85 f6             	test   %rsi,%rsi
  404ae1:	0f 85 e9 00 00 00    	jne    404bd0 <full_after_execute+0x450>
  404ae7:	48 8b 15 e2 45 00 00 	mov    0x45e2(%rip),%rdx        # 4090d0 <full_after_cache+0x10>
  404aee:	49 8b 8e 40 01 00 00 	mov    0x140(%r14),%rcx
  404af5:	c4 e1 f9 6e e0       	vmovq  %rax,%xmm4
  404afa:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
  404b03:	49 63 b6 f0 01 00 00 	movslq 0x1f0(%r14),%rsi
  404b0a:	c4 c1 7a 7e be a0 00 00 00 	vmovq  0xa0(%r14),%xmm7
  404b13:	48 63 12             	movslq (%rdx),%rdx
  404b16:	49 89 46 60          	mov    %rax,0x60(%r14)
  404b1a:	c4 c3 c1 22 96 b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm7,%xmm2
  404b24:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
  404b2a:	c4 c1 7a 7e 9e 80 00 00 00 	vmovq  0x80(%r14),%xmm3
  404b33:	49 89 96 90 01 00 00 	mov    %rdx,0x190(%r14)
  404b3a:	48 89 d7             	mov    %rdx,%rdi
  404b3d:	49 8b 96 00 01 00 00 	mov    0x100(%r14),%rdx
  404b44:	c4 c3 e1 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm3,%xmm1
  404b4e:	49 89 4e 70          	mov    %rcx,0x70(%r14)
  404b52:	c4 e3 f9 22 c2 01    	vpinsrq $0x1,%rdx,%xmm0,%xmm0
  404b58:	49 89 56 50          	mov    %rdx,0x50(%r14)
  404b5c:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
  404b62:	c4 e3 d9 22 d1 01    	vpinsrq $0x1,%rcx,%xmm4,%xmm2
  404b68:	49 89 76 20          	mov    %rsi,0x20(%r14)
  404b6c:	c5 fd 7f 8c 24 60 01 00 00 	vmovdqa %ymm1,0x160(%rsp)
  404b75:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
  404b7b:	c5 fd 7f 84 24 40 01 00 00 	vmovdqa %ymm0,0x140(%rsp)
  404b84:	85 ff                	test   %edi,%edi
  404b86:	0f 84 30 0f 00 00    	je     405abc <full_after_execute+0x133c>
  404b8c:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
  404b93:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
  404b9a:	89 ff                	mov    %edi,%edi
  404b9c:	31 d2                	xor    %edx,%edx
  404b9e:	4c 01 cf             	add    %r9,%rdi
  404ba1:	48 8d b4 24 40 01 00 00 	lea    0x140(%rsp),%rsi
  404ba9:	c5 f8 77             	vzeroupper
  404bac:	e8 ef e7 ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  404bb1:	4c 8b 0d d8 44 00 00 	mov    0x44d8(%rip),%r9        # 409090 <g_ee_main_mem>
  404bb8:	49 89 46 20          	mov    %rax,0x20(%r14)
  404bbc:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
  404bc3:	e9 18 fe ff ff       	jmp    4049e0 <full_after_execute+0x260>
  404bc8:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  404bd0:	c4 c1 79 7e 00       	vmovd  %xmm0,(%r8)
  404bd5:	41 8b 86 50 01 00 00 	mov    0x150(%r14),%eax
  404bdc:	48 8b 15 ad 44 00 00 	mov    0x44ad(%rip),%rdx        # 409090 <g_ee_main_mem>
  404be3:	48 8d 7c 02 68       	lea    0x68(%rdx,%rax,1),%rdi
  404be8:	8b 07                	mov    (%rdi),%eax
  404bea:	89 c2                	mov    %eax,%edx
  404bec:	83 e0 bf             	and    $0xffffffbf,%eax
  404bef:	83 e2 40             	and    $0x40,%edx
  404bf2:	48 63 c8             	movslq %eax,%rcx
  404bf5:	89 d3                	mov    %edx,%ebx
  404bf7:	49 89 4e 40          	mov    %rcx,0x40(%r14)
  404bfb:	49 89 5e 30          	mov    %rbx,0x30(%r14)
  404bff:	89 07                	mov    %eax,(%rdi)
  404c01:	85 d2                	test   %edx,%edx
  404c03:	74 25                	je     404c2a <full_after_execute+0x4aa>
  404c05:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
  404c0c:	48 8b 05 7d 44 00 00 	mov    0x447d(%rip),%rax        # 409090 <g_ee_main_mem>
  404c13:	48 63 4c 10 7c       	movslq 0x7c(%rax,%rdx,1),%rcx
  404c18:	49 89 4e 30          	mov    %rcx,0x30(%r14)
  404c1c:	48 89 ca             	mov    %rcx,%rdx
  404c1f:	41 8b 8e 40 01 00 00 	mov    0x140(%r14),%ecx
  404c26:	89 54 08 2c          	mov    %edx,0x2c(%rax,%rcx,1)
  404c2a:	4c 8b 0d 5f 44 00 00 	mov    0x445f(%rip),%r9        # 409090 <g_ee_main_mem>
  404c31:	41 8b 96 50 01 00 00 	mov    0x150(%r14),%edx
  404c38:	49 63 44 11 70       	movslq 0x70(%r9,%rdx,1),%rax
  404c3d:	48 89 c1             	mov    %rax,%rcx
  404c40:	49 89 86 90 01 00 00 	mov    %rax,0x190(%r14)
  404c47:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
  404c4e:	85 c9                	test   %ecx,%ecx
  404c50:	0f 84 f6 01 00 00    	je     404e4c <full_after_execute+0x6cc>
  404c56:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
  404c5f:	48 83 e8 60          	sub    $0x60,%rax
  404c63:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
  404c6a:	83 e0 f0             	and    $0xfffffff0,%eax
  404c6d:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404c73:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  404c7a:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
  404c83:	83 c0 10             	add    $0x10,%eax
  404c86:	83 e0 f0             	and    $0xfffffff0,%eax
  404c89:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404c8f:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  404c96:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
  404c9f:	83 c0 20             	add    $0x20,%eax
  404ca2:	83 e0 f0             	and    $0xfffffff0,%eax
  404ca5:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404cab:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  404cb2:	c4 c1 79 6f 86 00 01 00 00 	vmovdqa 0x100(%r14),%xmm0
  404cbb:	83 c0 30             	add    $0x30,%eax
  404cbe:	83 e0 f0             	and    $0xfffffff0,%eax
  404cc1:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404cc7:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  404cce:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
  404cd7:	83 c0 40             	add    $0x40,%eax
  404cda:	83 e0 f0             	and    $0xfffffff0,%eax
  404cdd:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404ce3:	49 8b 86 c0 01 00 00 	mov    0x1c0(%r14),%rax
  404cea:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
  404cf3:	41 8b be 90 01 00 00 	mov    0x190(%r14),%edi
  404cfa:	49 89 46 40          	mov    %rax,0x40(%r14)
  404cfe:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
  404d05:	49 89 46 50          	mov    %rax,0x50(%r14)
  404d09:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
  404d10:	49 89 46 60          	mov    %rax,0x60(%r14)
  404d14:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  404d1b:	83 c0 50             	add    $0x50,%eax
  404d1e:	83 e0 f0             	and    $0xfffffff0,%eax
  404d21:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  404d27:	c4 c1 7a 7e 76 60    	vmovq  0x60(%r14),%xmm6
  404d2d:	c4 c1 7a 7e ae a0 00 00 00 	vmovq  0xa0(%r14),%xmm5
  404d36:	c4 c3 d1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm5,%xmm1
  404d40:	c4 c3 c9 22 56 70 01 	vpinsrq $0x1,0x70(%r14),%xmm6,%xmm2
  404d47:	c4 c1 7a 7e ae 80 00 00 00 	vmovq  0x80(%r14),%xmm5
  404d50:	c4 c1 7a 7e 7e 40    	vmovq  0x40(%r14),%xmm7
  404d56:	c4 c3 d1 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm5,%xmm0
  404d60:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
  404d66:	c4 c3 c1 22 4e 50 01 	vpinsrq $0x1,0x50(%r14),%xmm7,%xmm1
  404d6d:	c5 fd 7f 44 24 60    	vmovdqa %ymm0,0x60(%rsp)
  404d73:	c4 e3 75 18 ca 01    	vinsertf128 $0x1,%xmm2,%ymm1,%ymm1
  404d79:	c5 fd 7f 4c 24 40    	vmovdqa %ymm1,0x40(%rsp)
  404d7f:	85 ff                	test   %edi,%edi
  404d81:	0f 84 35 0d 00 00    	je     405abc <full_after_execute+0x133c>
  404d87:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
  404d8e:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
  404d95:	4c 01 cf             	add    %r9,%rdi
  404d98:	31 d2                	xor    %edx,%edx
  404d9a:	48 8d 74 24 40       	lea    0x40(%rsp),%rsi
  404d9f:	c5 f8 77             	vzeroupper
  404da2:	e8 f9 e5 ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  404da7:	4c 8b 0d e2 42 00 00 	mov    0x42e2(%rip),%r9        # 409090 <g_ee_main_mem>
  404dae:	49 89 46 20          	mov    %rax,0x20(%r14)
  404db2:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
  404db9:	48 89 c2             	mov    %rax,%rdx
  404dbc:	8d 48 10             	lea    0x10(%rax),%ecx
  404dbf:	83 e2 f0             	and    $0xfffffff0,%edx
  404dc2:	83 e1 f0             	and    $0xfffffff0,%ecx
  404dc5:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  404dcb:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
  404dd4:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
  404dd8:	49 8b 4c 09 08       	mov    0x8(%r9,%rcx,1),%rcx
  404ddd:	49 89 8e 58 01 00 00 	mov    %rcx,0x158(%r14)
  404de4:	8d 48 20             	lea    0x20(%rax),%ecx
  404de7:	83 e1 f0             	and    $0xfffffff0,%ecx
  404dea:	49 89 96 50 01 00 00 	mov    %rdx,0x150(%r14)
  404df1:	89 d2                	mov    %edx,%edx
  404df3:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  404df9:	8d 48 30             	lea    0x30(%rax),%ecx
  404dfc:	83 e1 f0             	and    $0xfffffff0,%ecx
  404dff:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
  404e08:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  404e0e:	8d 48 40             	lea    0x40(%rax),%ecx
  404e11:	83 e1 f0             	and    $0xfffffff0,%ecx
  404e14:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
  404e1d:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  404e23:	8d 48 50             	lea    0x50(%rax),%ecx
  404e26:	48 83 c0 60          	add    $0x60,%rax
  404e2a:	83 e1 f0             	and    $0xfffffff0,%ecx
  404e2d:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
  404e36:	c4 c1 7a 6f 04 09    	vmovdqu (%r9,%rcx,1),%xmm0
  404e3c:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
  404e43:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
  404e4c:	49 63 74 11 78       	movslq 0x78(%r9,%rdx,1),%rsi
  404e51:	83 c0 20             	add    $0x20,%eax
  404e54:	83 e0 f0             	and    $0xfffffff0,%eax
  404e57:	49 89 76 50          	mov    %rsi,0x50(%r14)
  404e5b:	48 89 f1             	mov    %rsi,%rcx
  404e5e:	49 8d 74 11 74       	lea    0x74(%r9,%rdx,1),%rsi
  404e63:	48 63 16             	movslq (%rsi),%rdx
  404e66:	49 89 56 30          	mov    %rdx,0x30(%r14)
  404e6a:	49 8b 3c 01          	mov    (%r9,%rax,1),%rdi
  404e6e:	49 8b 44 01 08       	mov    0x8(%r9,%rax,1),%rax
  404e73:	49 89 7e 40          	mov    %rdi,0x40(%r14)
  404e77:	49 89 46 48          	mov    %rax,0x48(%r14)
  404e7b:	85 c9                	test   %ecx,%ecx
  404e7d:	74 0f                	je     404e8e <full_after_execute+0x70e>
  404e7f:	48 29 fa             	sub    %rdi,%rdx
  404e82:	49 89 56 30          	mov    %rdx,0x30(%r14)
  404e86:	89 16                	mov    %edx,(%rsi)
  404e88:	0f 88 32 09 00 00    	js     4057c0 <full_after_execute+0x1040>
  404e8e:	41 8b 96 40 01 00 00 	mov    0x140(%r14),%edx
  404e95:	f6 c2 0f             	test   $0xf,%dl
  404e98:	0f 85 a0 0c 00 00    	jne    405b3e <full_after_execute+0x13be>
  404e9e:	48 8b 05 eb 41 00 00 	mov    0x41eb(%rip),%rax        # 409090 <g_ee_main_mem>
  404ea5:	41 8b b6 50 01 00 00 	mov    0x150(%r14),%esi
  404eac:	4c 8b 4c 10 18       	mov    0x18(%rax,%rdx,1),%r9
  404eb1:	48 8b 5c 10 10       	mov    0x10(%rax,%rdx,1),%rbx
  404eb6:	c5 fa 7e 1c 10       	vmovq  (%rax,%rdx,1),%xmm3
  404ebb:	48 8b 4c 10 08       	mov    0x8(%rax,%rdx,1),%rcx
  404ec0:	48 89 5c 24 20       	mov    %rbx,0x20(%rsp)
  404ec5:	4c 89 4c 24 28       	mov    %r9,0x28(%rsp)
  404eca:	40 f6 c6 0f          	test   $0xf,%sil
  404ece:	0f 85 4b 0c 00 00    	jne    405b1f <full_after_execute+0x139f>
  404ed4:	c5 78 10 44 10 20    	vmovups 0x20(%rax,%rdx,1),%xmm8
  404eda:	4d 8b 96 88 03 00 00 	mov    0x388(%r14),%r10
  404ee1:	c4 e3 e1 22 d9 01    	vpinsrq $0x1,%rcx,%xmm3,%xmm3
  404ee7:	48 8b 54 30 10       	mov    0x10(%rax,%rsi,1),%rdx
  404eec:	c5 fa 6f 44 30 40    	vmovdqu 0x40(%rax,%rsi,1),%xmm0
  404ef2:	c4 41 79 6e ca       	vmovd  %r10d,%xmm9
  404ef7:	48 8b 4c 30 18       	mov    0x18(%rax,%rsi,1),%rcx
  404efc:	c5 7a 7e 54 30 30    	vmovq  0x30(%rax,%rsi,1),%xmm10
  404f02:	c4 e1 f9 6e ca       	vmovq  %rdx,%xmm1
  404f07:	c5 f9 6f e0          	vmovdqa %xmm0,%xmm4
  404f0b:	c5 f9 6f e8          	vmovdqa %xmm0,%xmm5
  404f0f:	c4 c1 30 c6 d1 00    	vshufps $0x0,%xmm9,%xmm9,%xmm2
  404f15:	c5 f0 c6 c9 55       	vshufps $0x55,%xmm1,%xmm1,%xmm1
  404f1a:	c5 79 6f f1          	vmovdqa %xmm1,%xmm14
  404f1e:	c4 c1 7a 12 c9       	vmovsldup %xmm9,%xmm1
  404f23:	48 89 cf             	mov    %rcx,%rdi
  404f26:	c5 d8 c6 e4 55       	vshufps $0x55,%xmm4,%xmm4,%xmm4
  404f2b:	c5 f9 6f f4          	vmovdqa %xmm4,%xmm6
  404f2f:	c5 f9 6e e2          	vmovd  %edx,%xmm4
  404f33:	c5 79 6e d9          	vmovd  %ecx,%xmm11
  404f37:	c5 e8 59 d0          	vmulps %xmm0,%xmm2,%xmm2
  404f3b:	c5 f8 14 c6          	vunpcklps %xmm6,%xmm0,%xmm0
  404f3f:	4c 8b 7c 30 38       	mov    0x38(%rax,%rsi,1),%r15
  404f44:	48 8b 5c 30 20       	mov    0x20(%rax,%rsi,1),%rbx
  404f49:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  404f4d:	4c 8b 5c 30 28       	mov    0x28(%rax,%rsi,1),%r11
  404f52:	49 8b b6 50 01 00 00 	mov    0x150(%r14),%rsi
  404f59:	48 ba 00 00 00 00 ff ff ff ff 	movabs $0xffffffff00000000,%rdx
  404f63:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
  404f67:	48 21 d7             	and    %rdx,%rdi
  404f6a:	c4 c3 a9 22 ff 01    	vpinsrq $0x1,%r15,%xmm10,%xmm7
  404f70:	c5 f8 59 c1          	vmulps %xmm1,%xmm0,%xmm0
  404f74:	c4 c1 58 14 ce       	vunpcklps %xmm14,%xmm4,%xmm1
  404f79:	48 89 74 24 38       	mov    %rsi,0x38(%rsp)
  404f7e:	89 f6                	mov    %esi,%esi
  404f80:	c5 fa 7e c9          	vmovq  %xmm1,%xmm1
  404f84:	48 89 74 24 30       	mov    %rsi,0x30(%rsp)
  404f89:	48 63 74 30 60       	movslq 0x60(%rax,%rsi,1),%rsi
  404f8e:	49 89 f0             	mov    %rsi,%r8
  404f91:	41 89 b6 00 02 00 00 	mov    %esi,0x200(%r14)
  404f98:	49 89 76 30          	mov    %rsi,0x30(%r14)
  404f9c:	49 8b b6 80 03 00 00 	mov    0x380(%r14),%rsi
  404fa3:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  404fa7:	c5 f8 58 c1          	vaddps %xmm1,%xmm0,%xmm0
  404fab:	c5 e8 15 ca          	vunpckhps %xmm2,%xmm2,%xmm1
  404faf:	c4 c1 72 58 cb       	vaddss %xmm11,%xmm1,%xmm1
  404fb4:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
  404fb9:	c4 62 79 35 f9       	vpmovzxdq %xmm1,%xmm15
  404fbe:	c4 61 f9 7e fa       	vmovq  %xmm15,%rdx
  404fc3:	c5 79 d6 7c 24 18    	vmovq  %xmm15,0x18(%rsp)
  404fc9:	48 09 d7             	or     %rdx,%rdi
  404fcc:	49 89 fd             	mov    %rdi,%r13
  404fcf:	45 85 c0             	test   %r8d,%r8d
  404fd2:	0f 85 30 07 00 00    	jne    405708 <full_after_execute+0xf88>
  404fd8:	c5 7a 16 c8          	vmovshdup %xmm0,%xmm9
  404fdc:	c5 f8 28 e8          	vmovaps %xmm0,%xmm5
  404fe0:	48 89 df             	mov    %rbx,%rdi
  404fe3:	48 c1 e9 20          	shr    $0x20,%rcx
  404fe7:	c4 c1 50 14 e9       	vunpcklps %xmm9,%xmm5,%xmm5
  404fec:	c4 e1 f9 6e f6       	vmovq  %rsi,%xmm6
  404ff1:	48 c1 ef 20          	shr    $0x20,%rdi
  404ff5:	c5 f9 6e e1          	vmovd  %ecx,%xmm4
  404ff9:	c5 c8 c6 f6 55       	vshufps $0x55,%xmm6,%xmm6,%xmm6
  404ffe:	c5 f9 6f c6          	vmovdqa %xmm6,%xmm0
  405002:	c5 79 6e ef          	vmovd  %edi,%xmm13
  405006:	4c 89 df             	mov    %r11,%rdi
  405009:	c5 f0 14 cc          	vunpcklps %xmm4,%xmm1,%xmm1
  40500d:	49 c1 e9 20          	shr    $0x20,%r9
  405011:	48 c1 ef 20          	shr    $0x20,%rdi
  405015:	c5 d0 16 e9          	vmovlhps %xmm1,%xmm5,%xmm5
  405019:	c4 c1 79 6e e3       	vmovd  %r11d,%xmm4
  40501e:	c5 f9 6e cb          	vmovd  %ebx,%xmm1
  405022:	c5 79 6e ff          	vmovd  %edi,%xmm15
  405026:	c4 c1 70 14 cd       	vunpcklps %xmm13,%xmm1,%xmm1
  40502b:	c5 f8 c6 c0 00       	vshufps $0x0,%xmm0,%xmm0,%xmm0
  405030:	c4 e3 7d 18 c0 01    	vinsertf128 $0x1,%xmm0,%ymm0,%ymm0
  405036:	c4 c1 58 14 e7       	vunpcklps %xmm15,%xmm4,%xmm4
  40503b:	c5 c8 c6 f6 00       	vshufps $0x0,%xmm6,%xmm6,%xmm6
  405040:	48 8b 7c 24 28       	mov    0x28(%rsp),%rdi
  405045:	48 8b 74 24 20       	mov    0x20(%rsp),%rsi
  40504a:	c5 f0 16 cc          	vmovlhps %xmm4,%xmm1,%xmm1
  40504e:	c4 e3 55 18 c9 01    	vinsertf128 $0x1,%xmm1,%ymm5,%ymm1
  405054:	4d 89 a6 30 03 00 00 	mov    %r12,0x330(%r14)
  40505b:	c5 c8 59 ff          	vmulps %xmm7,%xmm6,%xmm7
  40505f:	89 fa                	mov    %edi,%edx
  405061:	49 89 b6 10 03 00 00 	mov    %rsi,0x310(%r14)
  405068:	c5 fc 59 c1          	vmulps %ymm1,%ymm0,%ymm0
  40506c:	4d 89 ae 38 03 00 00 	mov    %r13,0x338(%r14)
  405073:	c5 c8 59 f5          	vmulps %xmm5,%xmm6,%xmm6
  405077:	49 89 9e 40 03 00 00 	mov    %rbx,0x340(%r14)
  40507e:	4d 89 9e 48 03 00 00 	mov    %r11,0x348(%r14)
  405085:	4d 89 be 58 03 00 00 	mov    %r15,0x358(%r14)
  40508c:	c4 41 79 d6 96 50 03 00 00 	vmovq  %xmm10,0x350(%r14)
  405095:	c5 38 58 c7          	vaddps %xmm7,%xmm8,%xmm8
  405099:	c4 c1 78 29 96 60 03 00 00 	vmovaps %xmm2,0x360(%r14)
  4050a2:	c4 e3 7d 19 c1 01    	vextractf128 $0x1,%ymm0,%xmm1
  4050a8:	c5 c8 58 f3          	vaddps %xmm3,%xmm6,%xmm6
  4050ac:	c4 c1 79 6e d9       	vmovd  %r9d,%xmm3
  4050b1:	c5 f0 c6 c9 ff       	vshufps $0xff,%xmm1,%xmm1,%xmm1
  4050b6:	c5 f2 58 db          	vaddss %xmm3,%xmm1,%xmm3
  4050ba:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  4050be:	c4 c1 70 5f c8       	vmaxps %xmm8,%xmm1,%xmm1
  4050c3:	c4 c1 79 7f b6 00 03 00 00 	vmovdqa %xmm6,0x300(%r14)
  4050cc:	c5 f9 7e d9          	vmovd  %xmm3,%ecx
  4050d0:	c4 c1 79 7f 8e 20 03 00 00 	vmovdqa %xmm1,0x320(%r14)
  4050d9:	48 c1 e1 20          	shl    $0x20,%rcx
  4050dd:	48 09 ca             	or     %rcx,%rdx
  4050e0:	49 89 96 18 03 00 00 	mov    %rdx,0x318(%r14)
  4050e7:	45 85 c0             	test   %r8d,%r8d
  4050ea:	74 29                	je     405115 <full_after_execute+0x995>
  4050ec:	c5 fa 10 74 24 14    	vmovss 0x14(%rsp),%xmm6
  4050f2:	c5 fa 10 5c 24 08    	vmovss 0x8(%rsp),%xmm3
  4050f8:	c4 e3 49 21 54 24 10 10 	vinsertps $0x10,0x10(%rsp),%xmm6,%xmm2
  405100:	c4 e3 61 21 4c 24 0c 10 	vinsertps $0x10,0xc(%rsp),%xmm3,%xmm1
  405108:	c5 f0 16 ca          	vmovlhps %xmm2,%xmm1,%xmm1
  40510c:	c4 c1 78 29 8e 70 03 00 00 	vmovaps %xmm1,0x370(%r14)
  405115:	c4 c1 7c 11 86 90 03 00 00 	vmovups %ymm0,0x390(%r14)
  40511e:	c4 c1 78 29 be b0 03 00 00 	vmovaps %xmm7,0x3b0(%r14)
  405127:	f6 44 24 38 0f       	testb  $0xf,0x38(%rsp)
  40512c:	0f 85 ac 09 00 00    	jne    405ade <full_after_execute+0x135e>
  405132:	48 8b 5c 24 30       	mov    0x30(%rsp),%rbx
  405137:	c5 f8 11 6c 18 10    	vmovups %xmm5,0x10(%rax,%rbx,1)
  40513d:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
  405144:	f6 c2 0f             	test   $0xf,%dl
  405147:	0f 85 91 09 00 00    	jne    405ade <full_after_execute+0x135e>
  40514d:	c4 c1 79 6f 86 00 03 00 00 	vmovdqa 0x300(%r14),%xmm0
  405156:	89 d2                	mov    %edx,%edx
  405158:	c5 fa 7f 04 10       	vmovdqu %xmm0,(%rax,%rdx,1)
  40515d:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
  405164:	f6 c2 0f             	test   $0xf,%dl
  405167:	0f 85 71 09 00 00    	jne    405ade <full_after_execute+0x135e>
  40516d:	c4 c1 79 6f 86 10 03 00 00 	vmovdqa 0x310(%r14),%xmm0
  405176:	89 d2                	mov    %edx,%edx
  405178:	c5 fa 7f 44 10 10    	vmovdqu %xmm0,0x10(%rax,%rdx,1)
  40517e:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
  405185:	f6 c2 0f             	test   $0xf,%dl
  405188:	0f 85 50 09 00 00    	jne    405ade <full_after_execute+0x135e>
  40518e:	c4 c1 79 6f 86 20 03 00 00 	vmovdqa 0x320(%r14),%xmm0
  405197:	89 d2                	mov    %edx,%edx
  405199:	c5 fa 10 2d c7 1d 00 00 	vmovss 0x1dc7(%rip),%xmm5        # 406f68 <typeinfo for Boundary+0x158>
  4051a1:	c5 fa 7f 44 10 20    	vmovdqu %xmm0,0x20(%rax,%rdx,1)
  4051a7:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
  4051ae:	49 8b 8e 10 01 00 00 	mov    0x110(%r14),%rcx
  4051b5:	49 89 56 40          	mov    %rdx,0x40(%r14)
  4051b9:	89 d2                	mov    %edx,%edx
  4051bb:	49 89 4e 30          	mov    %rcx,0x30(%r14)
  4051bf:	8b 74 10 10          	mov    0x10(%rax,%rdx,1),%esi
  4051c3:	89 c9                	mov    %ecx,%ecx
  4051c5:	41 89 b6 00 02 00 00 	mov    %esi,0x200(%r14)
  4051cc:	8b 7c 10 14          	mov    0x14(%rax,%rdx,1),%edi
  4051d0:	41 89 be 04 02 00 00 	mov    %edi,0x204(%r14)
  4051d7:	8b 54 10 18          	mov    0x18(%rax,%rdx,1),%edx
  4051db:	41 89 96 0c 02 00 00 	mov    %edx,0x20c(%r14)
  4051e2:	89 34 08             	mov    %esi,(%rax,%rcx,1)
  4051e5:	41 8b 8e 04 02 00 00 	mov    0x204(%r14),%ecx
  4051ec:	41 8b 46 30          	mov    0x30(%r14),%eax
  4051f0:	48 8b 15 99 3e 00 00 	mov    0x3e99(%rip),%rdx        # 409090 <g_ee_main_mem>
  4051f7:	89 4c 02 04          	mov    %ecx,0x4(%rdx,%rax,1)
  4051fb:	41 8b 8e 0c 02 00 00 	mov    0x20c(%r14),%ecx
  405202:	41 8b 46 30          	mov    0x30(%r14),%eax
  405206:	48 8b 15 83 3e 00 00 	mov    0x3e83(%rip),%rdx        # 409090 <g_ee_main_mem>
  40520d:	89 4c 02 08          	mov    %ecx,0x8(%rdx,%rax,1)
  405211:	48 8b 15 78 3e 00 00 	mov    0x3e78(%rip),%rdx        # 409090 <g_ee_main_mem>
  405218:	c4 c1 7a 10 86 0c 02 00 00 	vmovss 0x20c(%r14),%xmm0
  405221:	41 8b 46 30          	mov    0x30(%r14),%eax
  405225:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
  405229:	c4 c1 7a 11 86 0c 02 00 00 	vmovss %xmm0,0x20c(%r14)
  405232:	c5 d2 5c c8          	vsubss %xmm0,%xmm5,%xmm1
  405236:	c4 c1 7a 10 86 04 02 00 00 	vmovss 0x204(%r14),%xmm0
  40523f:	c5 fa 59 c0          	vmulss %xmm0,%xmm0,%xmm0
  405243:	c5 f2 5c c0          	vsubss %xmm0,%xmm1,%xmm0
  405247:	c5 f8 14 c9          	vunpcklps %xmm1,%xmm0,%xmm1
  40524b:	c4 c1 78 13 8e 04 02 00 00 	vmovlps %xmm1,0x204(%r14)
  405254:	c4 c1 7a 10 8e 00 02 00 00 	vmovss 0x200(%r14),%xmm1
  40525d:	c5 f2 59 c9          	vmulss %xmm1,%xmm1,%xmm1
  405261:	c5 fa 5c c1          	vsubss %xmm1,%xmm0,%xmm0
  405265:	c5 f8 54 05 53 1c 00 00 	vandps 0x1c53(%rip),%xmm0,%xmm0        # 406ec0 <typeinfo for Boundary+0xb0>
  40526d:	c5 fa 51 c0          	vsqrtss %xmm0,%xmm0,%xmm0
  405271:	c4 c1 7a 11 86 00 02 00 00 	vmovss %xmm0,0x200(%r14)
  40527a:	c5 fa 11 44 02 0c    	vmovss %xmm0,0xc(%rdx,%rax,1)
  405280:	49 63 86 00 02 00 00 	movslq 0x200(%r14),%rax
  405287:	4c 8b 0d 02 3e 00 00 	mov    0x3e02(%rip),%r9        # 409090 <g_ee_main_mem>
  40528e:	49 89 46 40          	mov    %rax,0x40(%r14)
  405292:	48 8b 05 27 3e 00 00 	mov    0x3e27(%rip),%rax        # 4090c0 <full_after_cache>
  405299:	48 63 10             	movslq (%rax),%rdx
  40529c:	89 d0                	mov    %edx,%eax
  40529e:	49 89 56 30          	mov    %rdx,0x30(%r14)
  4052a2:	41 8b 04 01          	mov    (%r9,%rax,1),%eax
  4052a6:	41 89 86 00 02 00 00 	mov    %eax,0x200(%r14)
  4052ad:	0f b6 c0             	movzbl %al,%eax
  4052b0:	48 83 e8 0a          	sub    $0xa,%rax
  4052b4:	49 89 46 30          	mov    %rax,0x30(%r14)
  4052b8:	0f 88 c8 00 00 00    	js     405386 <full_after_execute+0xc06>
  4052be:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
  4052c5:	48 8b 0d fc 3d 00 00 	mov    0x3dfc(%rip),%rcx        # 4090c8 <full_after_cache+0x8>
  4052cc:	c4 c1 7a 7e 96 10 01 00 00 	vmovq  0x110(%r14),%xmm2
  4052d5:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
  4052dc:	c4 c1 7a 7e b6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm6
  4052e5:	48 83 c0 50          	add    $0x50,%rax
  4052e9:	48 63 09             	movslq (%rcx),%rcx
  4052ec:	c4 e1 f9 6e e8       	vmovq  %rax,%xmm5
  4052f1:	c4 c3 d1 22 46 70 01 	vpinsrq $0x1,0x70(%r14),%xmm5,%xmm0
  4052f8:	c5 e9 6c ca          	vpunpcklqdq %xmm2,%xmm2,%xmm1
  4052fc:	c4 c1 7a 7e be 80 00 00 00 	vmovq  0x80(%r14),%xmm7
  405305:	c4 c3 c9 22 9e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm6,%xmm3
  40530f:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
  405316:	48 89 cf             	mov    %rcx,%rdi
  405319:	c4 e3 75 18 c8 01    	vinsertf128 $0x1,%xmm0,%ymm1,%ymm1
  40531f:	49 89 46 60          	mov    %rax,0x60(%r14)
  405323:	c4 c3 c1 22 86 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm7,%xmm0
  40532d:	49 89 56 20          	mov    %rdx,0x20(%r14)
  405331:	c4 e3 7d 18 c3 01    	vinsertf128 $0x1,%xmm3,%ymm0,%ymm0
  405337:	c4 c1 79 d6 56 40    	vmovq  %xmm2,0x40(%r14)
  40533d:	c4 c1 79 d6 56 50    	vmovq  %xmm2,0x50(%r14)
  405343:	c5 fd 7f 8c 24 c0 00 00 00 	vmovdqa %ymm1,0xc0(%rsp)
  40534c:	c5 fd 7f 84 24 e0 00 00 00 	vmovdqa %ymm0,0xe0(%rsp)
  405355:	85 c9                	test   %ecx,%ecx
  405357:	0f 84 5f 07 00 00    	je     405abc <full_after_execute+0x133c>
  40535d:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
  405364:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
  40536b:	89 ff                	mov    %edi,%edi
  40536d:	31 d2                	xor    %edx,%edx
  40536f:	4c 01 cf             	add    %r9,%rdi
  405372:	48 8d b4 24 c0 00 00 00 	lea    0xc0(%rsp),%rsi
  40537a:	c5 f8 77             	vzeroupper
  40537d:	e8 1e e0 ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  405382:	49 89 46 20          	mov    %rax,0x20(%r14)
  405386:	48 8b 05 3b 3d 00 00 	mov    0x3d3b(%rip),%rax        # 4090c8 <full_after_cache+0x8>
  40538d:	49 63 96 f0 01 00 00 	movslq 0x1f0(%r14),%rdx
  405394:	c4 c1 7a 7e be a0 00 00 00 	vmovq  0xa0(%r14),%xmm7
  40539d:	c4 c1 7a 7e ae 80 00 00 00 	vmovq  0x80(%r14),%xmm5
  4053a6:	c4 c3 c1 22 8e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm7,%xmm1
  4053b0:	48 63 00             	movslq (%rax),%rax
  4053b3:	49 89 56 20          	mov    %rdx,0x20(%r14)
  4053b7:	c4 c3 d1 22 96 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm5,%xmm2
  4053c1:	c4 c1 7a 7e 86 10 01 00 00 	vmovq  0x110(%r14),%xmm0
  4053ca:	49 89 86 90 01 00 00 	mov    %rax,0x190(%r14)
  4053d1:	48 89 c7             	mov    %rax,%rdi
  4053d4:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
  4053db:	c4 e3 6d 18 d1 01    	vinsertf128 $0x1,%xmm1,%ymm2,%ymm2
  4053e1:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
  4053e7:	48 83 c0 50          	add    $0x50,%rax
  4053eb:	c4 c1 79 d6 46 50    	vmovq  %xmm0,0x50(%r14)
  4053f1:	c5 f9 6c c0          	vpunpcklqdq %xmm0,%xmm0,%xmm0
  4053f5:	c4 e1 f9 6e f0       	vmovq  %rax,%xmm6
  4053fa:	c4 c3 c9 22 4e 70 01 	vpinsrq $0x1,0x70(%r14),%xmm6,%xmm1
  405401:	49 89 46 60          	mov    %rax,0x60(%r14)
  405405:	c5 fd 7f 94 24 20 01 00 00 	vmovdqa %ymm2,0x120(%rsp)
  40540e:	c4 e3 7d 18 c1 01    	vinsertf128 $0x1,%xmm1,%ymm0,%ymm0
  405414:	c5 fd 7f 84 24 00 01 00 00 	vmovdqa %ymm0,0x100(%rsp)
  40541d:	85 ff                	test   %edi,%edi
  40541f:	0f 84 97 06 00 00    	je     405abc <full_after_execute+0x133c>
  405425:	4c 8b 0d 64 3c 00 00 	mov    0x3c64(%rip),%r9        # 409090 <g_ee_main_mem>
  40542c:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
  405433:	89 ff                	mov    %edi,%edi
  405435:	31 d2                	xor    %edx,%edx
  405437:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
  40543e:	48 8d b4 24 00 01 00 00 	lea    0x100(%rsp),%rsi
  405446:	4c 01 cf             	add    %r9,%rdi
  405449:	c5 f8 77             	vzeroupper
  40544c:	e8 4f df ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  405451:	49 8b 96 10 01 00 00 	mov    0x110(%r14),%rdx
  405458:	c5 f0 57 c9          	vxorps %xmm1,%xmm1,%xmm1
  40545c:	49 89 46 20          	mov    %rax,0x20(%r14)
  405460:	4c 8b 0d 29 3c 00 00 	mov    0x3c29(%rip),%r9        # 409090 <g_ee_main_mem>
  405467:	49 8b 86 40 01 00 00 	mov    0x140(%r14),%rax
  40546e:	89 d1                	mov    %edx,%ecx
  405470:	49 89 56 30          	mov    %rdx,0x30(%r14)
  405474:	49 89 46 40          	mov    %rax,0x40(%r14)
  405478:	c4 c1 79 6e 44 09 0c 	vmovd  0xc(%r9,%rcx,1),%xmm0
  40547f:	41 c7 86 04 02 00 00 00 00 00 00 	movl   $0x0,0x204(%r14)
  40548a:	c4 c1 79 7e 86 00 02 00 00 	vmovd  %xmm0,0x200(%r14)
  405493:	c5 f8 2f c8          	vcomiss %xmm0,%xmm1
  405497:	0f 87 c3 01 00 00    	ja     405660 <full_after_execute+0xee0>
  40549d:	a8 0f                	test   $0xf,%al
  40549f:	0f 85 5b 06 00 00    	jne    405b00 <full_after_execute+0x1380>
  4054a5:	89 c0                	mov    %eax,%eax
  4054a7:	83 e2 0f             	and    $0xf,%edx
  4054aa:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
  4054af:	48 8b 07             	mov    (%rdi),%rax
  4054b2:	48 8b 77 08          	mov    0x8(%rdi),%rsi
  4054b6:	49 89 86 90 02 00 00 	mov    %rax,0x290(%r14)
  4054bd:	49 89 b6 98 02 00 00 	mov    %rsi,0x298(%r14)
  4054c4:	0f 85 36 06 00 00    	jne    405b00 <full_after_execute+0x1380>
  4054ca:	49 8b 14 09          	mov    (%r9,%rcx,1),%rdx
  4054ce:	49 8b 44 09 08       	mov    0x8(%r9,%rcx,1),%rax
  4054d3:	c5 e8 57 d2          	vxorps %xmm2,%xmm2,%xmm2
  4054d7:	48 c1 ee 20          	shr    $0x20,%rsi
  4054db:	49 89 96 a0 02 00 00 	mov    %rdx,0x2a0(%r14)
  4054e2:	c5 f9 6e c2          	vmovd  %edx,%xmm0
  4054e6:	48 c1 ea 20          	shr    $0x20,%rdx
  4054ea:	c5 f9 6e fa          	vmovd  %edx,%xmm7
  4054ee:	49 89 86 a8 02 00 00 	mov    %rax,0x2a8(%r14)
  4054f5:	c5 f8 14 c7          	vunpcklps %xmm7,%xmm0,%xmm0
  4054f9:	c5 f9 6e fe          	vmovd  %esi,%xmm7
  4054fd:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  405501:	c5 f8 58 c2          	vaddps %xmm2,%xmm0,%xmm0
  405505:	c5 f9 6e d0          	vmovd  %eax,%xmm2
  405509:	c5 ea 58 c9          	vaddss %xmm1,%xmm2,%xmm1
  40550d:	c4 c1 78 13 86 90 02 00 00 	vmovlps %xmm0,0x290(%r14)
  405516:	c4 c1 7a 11 8e 98 02 00 00 	vmovss %xmm1,0x298(%r14)
  40551f:	c5 f0 14 cf          	vunpcklps %xmm7,%xmm1,%xmm1
  405523:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
  405527:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
  40552b:	49 8b 86 90 02 00 00 	mov    0x290(%r14),%rax
  405532:	49 8b 96 98 02 00 00 	mov    0x298(%r14),%rdx
  405539:	c4 c1 78 28 86 20 03 00 00 	vmovaps 0x320(%r14),%xmm0
  405542:	49 89 46 40          	mov    %rax,0x40(%r14)
  405546:	49 8b 86 50 01 00 00 	mov    0x150(%r14),%rax
  40554d:	49 89 56 48          	mov    %rdx,0x48(%r14)
  405551:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
  405557:	89 c2                	mov    %eax,%edx
  405559:	49 63 4c 11 68       	movslq 0x68(%r9,%rdx,1),%rcx
  40555e:	49 89 4e 40          	mov    %rcx,0x40(%r14)
  405562:	48 89 ca             	mov    %rcx,%rdx
  405565:	83 e1 04             	and    $0x4,%ecx
  405568:	89 cb                	mov    %ecx,%ebx
  40556a:	49 89 5e 50          	mov    %rbx,0x50(%r14)
  40556e:	f6 c2 02             	test   $0x2,%dl
  405571:	74 33                	je     4055a6 <full_after_execute+0xe26>
  405573:	c4 e1 f9 7e c6       	vmovq  %xmm0,%rsi
  405578:	41 c7 46 60 00 00 00 00 	movl   $0x0,0x60(%r14)
  405580:	c4 c3 79 16 46 64 02 	vpextrd $0x2,%xmm0,0x64(%r14)
  405587:	c4 c3 79 16 46 6c 03 	vpextrd $0x3,%xmm0,0x6c(%r14)
  40558e:	41 c7 46 68 00 00 00 00 	movl   $0x0,0x68(%r14)
  405596:	48 85 f6             	test   %rsi,%rsi
  405599:	75 0b                	jne    4055a6 <full_after_execute+0xe26>
  40559b:	49 83 7e 60 00       	cmpq   $0x0,0x60(%r14)
  4055a0:	0f 84 41 f5 ff ff    	je     404ae7 <full_after_execute+0x367>
  4055a6:	83 e2 01             	and    $0x1,%edx
  4055a9:	89 d3                	mov    %edx,%ebx
  4055ab:	49 89 5e 40          	mov    %rbx,0x40(%r14)
  4055af:	85 c9                	test   %ecx,%ecx
  4055b1:	74 29                	je     4055dc <full_after_execute+0xe5c>
  4055b3:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
  4055bb:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
  4055c2:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
  4055c9:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
  4055d1:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
  4055d6:	0f 8e 0b f5 ff ff    	jle    404ae7 <full_after_execute+0x367>
  4055dc:	85 d2                	test   %edx,%edx
  4055de:	0f 84 fc f3 ff ff    	je     4049e0 <full_after_execute+0x260>
  4055e4:	c4 c1 78 28 86 00 03 00 00 	vmovaps 0x300(%r14),%xmm0
  4055ed:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
  4055f3:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
  4055fa:	c4 c1 78 28 86 10 03 00 00 	vmovaps 0x310(%r14),%xmm0
  405603:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
  40560b:	49 8b 56 30          	mov    0x30(%r14),%rdx
  40560f:	c4 c1 78 11 46 30    	vmovups %xmm0,0x30(%r14)
  405615:	48 85 d2             	test   %rdx,%rdx
  405618:	0f 88 c9 f4 ff ff    	js     404ae7 <full_after_execute+0x367>
  40561e:	49 c7 46 38 00 00 00 00 	movq   $0x0,0x38(%r14)
  405626:	c4 c3 79 16 46 34 03 	vpextrd $0x3,%xmm0,0x34(%r14)
  40562d:	c4 c3 79 16 46 38 02 	vpextrd $0x2,%xmm0,0x38(%r14)
  405634:	41 c7 46 30 00 00 00 00 	movl   $0x0,0x30(%r14)
  40563c:	49 83 7e 30 00       	cmpq   $0x0,0x30(%r14)
  405641:	0f 88 a0 f4 ff ff    	js     404ae7 <full_after_execute+0x367>
  405647:	e9 94 f3 ff ff       	jmp    4049e0 <full_after_execute+0x260>
  40564c:	0f 1f 40 00          	nopl   0x0(%rax)
  405650:	49 89 56 30          	mov    %rdx,0x30(%r14)
  405654:	e9 0f f4 ff ff       	jmp    404a68 <full_after_execute+0x2e8>
  405659:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  405660:	a8 0f                	test   $0xf,%al
  405662:	0f 85 98 04 00 00    	jne    405b00 <full_after_execute+0x1380>
  405668:	89 c0                	mov    %eax,%eax
  40566a:	83 e2 0f             	and    $0xf,%edx
  40566d:	49 8d 7c 01 10       	lea    0x10(%r9,%rax,1),%rdi
  405672:	48 8b 07             	mov    (%rdi),%rax
  405675:	48 8b 77 08          	mov    0x8(%rdi),%rsi
  405679:	49 89 86 90 02 00 00 	mov    %rax,0x290(%r14)
  405680:	49 89 b6 98 02 00 00 	mov    %rsi,0x298(%r14)
  405687:	0f 85 73 04 00 00    	jne    405b00 <full_after_execute+0x1380>
  40568d:	49 8b 04 09          	mov    (%r9,%rcx,1),%rax
  405691:	49 8b 54 09 08       	mov    0x8(%r9,%rcx,1),%rdx
  405696:	c5 f8 57 c0          	vxorps %xmm0,%xmm0,%xmm0
  40569a:	48 c1 ee 20          	shr    $0x20,%rsi
  40569e:	c5 f9 6e ee          	vmovd  %esi,%xmm5
  4056a2:	49 89 86 a0 02 00 00 	mov    %rax,0x2a0(%r14)
  4056a9:	c5 f9 6e d0          	vmovd  %eax,%xmm2
  4056ad:	48 c1 e8 20          	shr    $0x20,%rax
  4056b1:	c5 f9 6e d8          	vmovd  %eax,%xmm3
  4056b5:	49 89 96 a8 02 00 00 	mov    %rdx,0x2a8(%r14)
  4056bc:	c5 e8 14 d3          	vunpcklps %xmm3,%xmm2,%xmm2
  4056c0:	c5 fa 7e d2          	vmovq  %xmm2,%xmm2
  4056c4:	c5 f8 5c c2          	vsubps %xmm2,%xmm0,%xmm0
  4056c8:	c5 f9 6e d2          	vmovd  %edx,%xmm2
  4056cc:	c5 f2 5c ca          	vsubss %xmm2,%xmm1,%xmm1
  4056d0:	c4 c1 78 13 86 90 02 00 00 	vmovlps %xmm0,0x290(%r14)
  4056d9:	c4 c1 7a 11 8e 98 02 00 00 	vmovss %xmm1,0x298(%r14)
  4056e2:	c5 f0 14 cd          	vunpcklps %xmm5,%xmm1,%xmm1
  4056e6:	c5 f8 16 c1          	vmovlhps %xmm1,%xmm0,%xmm0
  4056ea:	c5 f8 11 07          	vmovups %xmm0,(%rdi)
  4056ee:	49 8b 86 90 02 00 00 	mov    0x290(%r14),%rax
  4056f5:	49 8b 96 98 02 00 00 	mov    0x298(%r14),%rdx
  4056fc:	e9 38 fe ff ff       	jmp    405539 <full_after_execute+0xdb9>
  405701:	0f 1f 80 00 00 00 00 	nopl   0x0(%rax)
  405708:	49 8b 7e 30          	mov    0x30(%r14),%rdi
  40570c:	49 c1 ea 20          	shr    $0x20,%r10
  405710:	49 8b 56 38          	mov    0x38(%r14),%rdx
  405714:	c5 fa 7e c0          	vmovq  %xmm0,%xmm0
  405718:	c5 b2 59 ed          	vmulss %xmm5,%xmm9,%xmm5
  40571c:	c4 41 79 6e da       	vmovd  %r10d,%xmm11
  405721:	49 ba 00 00 00 00 ff ff ff ff 	movabs $0xffffffff00000000,%r10
  40572b:	c5 32 59 ce          	vmulss %xmm6,%xmm9,%xmm9
  40572f:	c5 79 6e e7          	vmovd  %edi,%xmm12
  405733:	48 c1 ef 20          	shr    $0x20,%rdi
  405737:	c4 41 1a 59 fb       	vmulss %xmm11,%xmm12,%xmm15
  40573c:	c5 d2 58 ec          	vaddss %xmm4,%xmm5,%xmm5
  405740:	c4 41 32 58 ce       	vaddss %xmm14,%xmm9,%xmm9
  405745:	c5 7a 11 7c 24 08    	vmovss %xmm15,0x8(%rsp)
  40574b:	c5 79 6e ff          	vmovd  %edi,%xmm15
  40574f:	c4 41 22 59 ef       	vmulss %xmm15,%xmm11,%xmm13
  405754:	c5 7a 10 3d 0c 18 00 00 	vmovss 0x180c(%rip),%xmm15        # 406f68 <typeinfo for Boundary+0x158>
  40575c:	c4 41 02 5c e4       	vsubss %xmm12,%xmm15,%xmm12
  405761:	c4 41 1a 59 e3       	vmulss %xmm11,%xmm12,%xmm12
  405766:	c5 7a 11 6c 24 0c    	vmovss %xmm13,0xc(%rsp)
  40576c:	c5 79 6e ea          	vmovd  %edx,%xmm13
  405770:	4c 89 ea             	mov    %r13,%rdx
  405773:	c4 41 22 59 ed       	vmulss %xmm13,%xmm11,%xmm13
  405778:	4c 21 d2             	and    %r10,%rdx
  40577b:	c4 41 02 5c e4       	vsubss %xmm12,%xmm15,%xmm12
  405780:	c5 7a 11 6c 24 14    	vmovss %xmm13,0x14(%rsp)
  405786:	c4 c1 72 59 cc       	vmulss %xmm12,%xmm1,%xmm1
  40578b:	c4 c1 7a 12 f4       	vmovsldup %xmm12,%xmm6
  405790:	c5 7a 11 64 24 10    	vmovss %xmm12,0x10(%rsp)
  405796:	c4 c1 52 59 ec       	vmulss %xmm12,%xmm5,%xmm5
  40579b:	c4 41 32 59 cc       	vmulss %xmm12,%xmm9,%xmm9
  4057a0:	c5 fa 7e f6          	vmovq  %xmm6,%xmm6
  4057a4:	c5 c8 59 c0          	vmulps %xmm0,%xmm6,%xmm0
  4057a8:	c5 f9 7e cf          	vmovd  %xmm1,%edi
  4057ac:	48 09 fa             	or     %rdi,%rdx
  4057af:	49 89 d5             	mov    %rdx,%r13
  4057b2:	c4 c1 f9 7e c4       	vmovq  %xmm0,%r12
  4057b7:	e9 24 f8 ff ff       	jmp    404fe0 <full_after_execute+0x860>
  4057bc:	0f 1f 40 00          	nopl   0x0(%rax)
  4057c0:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
  4057c7:	4c 8b 0d c2 38 00 00 	mov    0x38c2(%rip),%r9        # 409090 <g_ee_main_mem>
  4057ce:	c4 c1 79 6f 86 c0 01 00 00 	vmovdqa 0x1c0(%r14),%xmm0
  4057d7:	48 83 e8 60          	sub    $0x60,%rax
  4057db:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
  4057e2:	83 e0 f0             	and    $0xfffffff0,%eax
  4057e5:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  4057eb:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  4057f2:	c4 c1 79 6f 86 50 01 00 00 	vmovdqa 0x150(%r14),%xmm0
  4057fb:	83 c0 10             	add    $0x10,%eax
  4057fe:	83 e0 f0             	and    $0xfffffff0,%eax
  405801:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  405807:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  40580e:	c4 c1 79 6f 86 40 01 00 00 	vmovdqa 0x140(%r14),%xmm0
  405817:	83 c0 20             	add    $0x20,%eax
  40581a:	83 e0 f0             	and    $0xfffffff0,%eax
  40581d:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  405823:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  40582a:	c4 c1 79 6f 86 00 01 00 00 	vmovdqa 0x100(%r14),%xmm0
  405833:	83 c0 30             	add    $0x30,%eax
  405836:	83 e0 f0             	and    $0xfffffff0,%eax
  405839:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40583f:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  405846:	c4 c1 79 6f 86 30 01 00 00 	vmovdqa 0x130(%r14),%xmm0
  40584f:	83 c0 40             	add    $0x40,%eax
  405852:	83 e0 f0             	and    $0xfffffff0,%eax
  405855:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  40585b:	41 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%eax
  405862:	c4 c1 79 6f 86 20 01 00 00 	vmovdqa 0x120(%r14),%xmm0
  40586b:	83 c0 50             	add    $0x50,%eax
  40586e:	83 e0 f0             	and    $0xfffffff0,%eax
  405871:	c4 c1 7a 7f 04 01    	vmovdqu %xmm0,(%r9,%rax,1)
  405877:	49 8b 96 40 01 00 00 	mov    0x140(%r14),%rdx
  40587e:	c4 c1 7a 7e 86 c0 01 00 00 	vmovq  0x1c0(%r14),%xmm0
  405887:	c4 c1 7a 7e 96 50 01 00 00 	vmovq  0x150(%r14),%xmm2
  405890:	48 8b 05 41 38 00 00 	mov    0x3841(%rip),%rax        # 4090d8 <full_after_cache+0x18>
  405897:	c4 c1 7a 7e b6 a0 00 00 00 	vmovq  0xa0(%r14),%xmm6
  4058a0:	c4 c1 79 d6 46 40    	vmovq  %xmm0,0x40(%r14)
  4058a6:	c4 c1 79 d6 56 60    	vmovq  %xmm2,0x60(%r14)
  4058ac:	c4 e3 e9 22 d2 01    	vpinsrq $0x1,%rdx,%xmm2,%xmm2
  4058b2:	49 89 56 70          	mov    %rdx,0x70(%r14)
  4058b6:	48 63 08             	movslq (%rax),%rcx
  4058b9:	49 89 8e 90 01 00 00 	mov    %rcx,0x190(%r14)
  4058c0:	48 89 c8             	mov    %rcx,%rax
  4058c3:	49 63 8e f0 01 00 00 	movslq 0x1f0(%r14),%rcx
  4058ca:	49 89 4e 20          	mov    %rcx,0x20(%r14)
  4058ce:	c4 c3 c9 22 9e b0 00 00 00 01 	vpinsrq $0x1,0xb0(%r14),%xmm6,%xmm3
  4058d8:	c4 c1 7a 7e be 80 00 00 00 	vmovq  0x80(%r14),%xmm7
  4058e1:	c4 c3 f9 22 46 50 01 	vpinsrq $0x1,0x50(%r14),%xmm0,%xmm0
  4058e8:	c4 c3 c1 22 8e 90 00 00 00 01 	vpinsrq $0x1,0x90(%r14),%xmm7,%xmm1
  4058f2:	c4 e3 7d 18 c2 01    	vinsertf128 $0x1,%xmm2,%ymm0,%ymm0
  4058f8:	c5 fd 7f 84 24 80 00 00 00 	vmovdqa %ymm0,0x80(%rsp)
  405901:	c4 e3 75 18 cb 01    	vinsertf128 $0x1,%xmm3,%ymm1,%ymm1
  405907:	c5 fd 7f 8c 24 a0 00 00 00 	vmovdqa %ymm1,0xa0(%rsp)
  405910:	85 c0                	test   %eax,%eax
  405912:	0f 84 a4 01 00 00    	je     405abc <full_after_execute+0x133c>
  405918:	49 8b 8e 60 01 00 00 	mov    0x160(%r14),%rcx
  40591f:	4d 8b 86 70 01 00 00 	mov    0x170(%r14),%r8
  405926:	89 c0                	mov    %eax,%eax
  405928:	31 d2                	xor    %edx,%edx
  40592a:	48 8d b4 24 80 00 00 00 	lea    0x80(%rsp),%rsi
  405932:	49 8d 3c 01          	lea    (%r9,%rax,1),%rdi
  405936:	c5 f8 77             	vzeroupper
  405939:	e8 62 da ff ff       	call   4033a0 <_call_goal8_asm_systemv>
  40593e:	48 8b 15 4b 37 00 00 	mov    0x374b(%rip),%rdx        # 409090 <g_ee_main_mem>
  405945:	49 89 46 20          	mov    %rax,0x20(%r14)
  405949:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
  405950:	48 89 c1             	mov    %rax,%rcx
  405953:	83 e1 f0             	and    $0xfffffff0,%ecx
  405956:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  40595b:	8d 48 10             	lea    0x10(%rax),%ecx
  40595e:	83 e1 f0             	and    $0xfffffff0,%ecx
  405961:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
  40596a:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  40596f:	8d 48 20             	lea    0x20(%rax),%ecx
  405972:	83 e1 f0             	and    $0xfffffff0,%ecx
  405975:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
  40597e:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  405983:	8d 48 30             	lea    0x30(%rax),%ecx
  405986:	83 e1 f0             	and    $0xfffffff0,%ecx
  405989:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
  405992:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  405997:	8d 48 40             	lea    0x40(%rax),%ecx
  40599a:	83 e1 f0             	and    $0xfffffff0,%ecx
  40599d:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
  4059a6:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  4059ab:	8d 48 50             	lea    0x50(%rax),%ecx
  4059ae:	48 83 c0 60          	add    $0x60,%rax
  4059b2:	83 e1 f0             	and    $0xfffffff0,%ecx
  4059b5:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
  4059be:	c5 fa 6f 04 0a       	vmovdqu (%rdx,%rcx,1),%xmm0
  4059c3:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
  4059ca:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
  4059d3:	e9 b6 f4 ff ff       	jmp    404e8e <full_after_execute+0x70e>
  4059d8:	0f 1f 84 00 00 00 00 00 	nopl   0x0(%rax,%rax,1)
  4059e0:	49 8b 86 d0 01 00 00 	mov    0x1d0(%r14),%rax
  4059e7:	49 89 4e 20          	mov    %rcx,0x20(%r14)
  4059eb:	89 c2                	mov    %eax,%edx
  4059ed:	49 8b 34 11          	mov    (%r9,%rdx,1),%rsi
  4059f1:	49 89 b6 f0 01 00 00 	mov    %rsi,0x1f0(%r14)
  4059f8:	49 8b 54 11 08       	mov    0x8(%r9,%rdx,1),%rdx
  4059fd:	49 89 96 e0 01 00 00 	mov    %rdx,0x1e0(%r14)
  405a04:	8d 90 90 00 00 00    	lea    0x90(%rax),%edx
  405a0a:	83 e2 f0             	and    $0xfffffff0,%edx
  405a0d:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  405a13:	8d 90 80 00 00 00    	lea    0x80(%rax),%edx
  405a19:	83 e2 f0             	and    $0xfffffff0,%edx
  405a1c:	c4 c1 7a 7f 86 c0 01 00 00 	vmovdqu %xmm0,0x1c0(%r14)
  405a25:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  405a2b:	8d 50 70             	lea    0x70(%rax),%edx
  405a2e:	83 e2 f0             	and    $0xfffffff0,%edx
  405a31:	c4 c1 7a 7f 86 50 01 00 00 	vmovdqu %xmm0,0x150(%r14)
  405a3a:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  405a40:	8d 50 60             	lea    0x60(%rax),%edx
  405a43:	83 e2 f0             	and    $0xfffffff0,%edx
  405a46:	c4 c1 7a 7f 86 40 01 00 00 	vmovdqu %xmm0,0x140(%r14)
  405a4f:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  405a55:	8d 50 50             	lea    0x50(%rax),%edx
  405a58:	83 e2 f0             	and    $0xfffffff0,%edx
  405a5b:	c4 c1 7a 7f 86 30 01 00 00 	vmovdqu %xmm0,0x130(%r14)
  405a64:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  405a6a:	8d 50 40             	lea    0x40(%rax),%edx
  405a6d:	83 e2 f0             	and    $0xfffffff0,%edx
  405a70:	c4 c1 7a 7f 86 20 01 00 00 	vmovdqu %xmm0,0x120(%r14)
  405a79:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  405a7f:	8d 50 30             	lea    0x30(%rax),%edx
  405a82:	48 05 a0 00 00 00    	add    $0xa0,%rax
  405a88:	83 e2 f0             	and    $0xfffffff0,%edx
  405a8b:	c4 c1 7a 7f 86 10 01 00 00 	vmovdqu %xmm0,0x110(%r14)
  405a94:	c4 c1 7a 6f 04 11    	vmovdqu (%r9,%rdx,1),%xmm0
  405a9a:	49 89 86 d0 01 00 00 	mov    %rax,0x1d0(%r14)
  405aa1:	48 89 c8             	mov    %rcx,%rax
  405aa4:	c4 c1 7a 7f 86 00 01 00 00 	vmovdqu %xmm0,0x100(%r14)
  405aad:	48 8d 65 d8          	lea    -0x28(%rbp),%rsp
  405ab1:	5b                   	pop    %rbx
  405ab2:	41 5c                	pop    %r12
  405ab4:	41 5d                	pop    %r13
  405ab6:	41 5e                	pop    %r14
  405ab8:	41 5f                	pop    %r15
  405aba:	5d                   	pop    %rbp
  405abb:	c3                   	ret
  405abc:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  405ac2:	b9 80 6a 40 00       	mov    $0x406a80,%ecx
  405ac7:	ba 90 01 00 00       	mov    $0x190,%edx
  405acc:	be 10 6a 40 00       	mov    $0x406a10,%esi
  405ad1:	bf e6 65 40 00       	mov    $0x4065e6,%edi
  405ad6:	c5 f8 77             	vzeroupper
  405ad9:	e8 62 d9 ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  405ade:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  405ae4:	b9 78 6b 40 00       	mov    $0x406b78,%ecx
  405ae9:	ba c0 01 00 00       	mov    $0x1c0,%edx
  405aee:	be 10 6a 40 00       	mov    $0x406a10,%esi
  405af3:	bf b0 6b 40 00       	mov    $0x406bb0,%edi
  405af8:	c5 f8 77             	vzeroupper
  405afb:	e8 40 d9 ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  405b00:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  405b06:	b9 d8 69 40 00       	mov    $0x4069d8,%ecx
  405b0b:	ba 58 01 00 00       	mov    $0x158,%edx
  405b10:	be 10 6a 40 00       	mov    $0x406a10,%esi
  405b15:	bf 50 6a 40 00       	mov    $0x406a50,%edi
  405b1a:	e8 21 d9 ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  405b1f:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  405b25:	b9 00 6d 40 00       	mov    $0x406d00,%ecx
  405b2a:	ba 00 01 00 00       	mov    $0x100,%edx
  405b2f:	be 38 6d 40 00       	mov    $0x406d38,%esi
  405b34:	bf d0 6d 40 00       	mov    $0x406dd0,%edi
  405b39:	e8 02 d9 ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  405b3e:	41 b8 e5 65 40 00    	mov    $0x4065e5,%r8d
  405b44:	b9 00 6d 40 00       	mov    $0x406d00,%ecx
  405b49:	ba fa 00 00 00       	mov    $0xfa,%edx
  405b4e:	be 38 6d 40 00       	mov    $0x406d38,%esi
  405b53:	bf a0 6d 40 00       	mov    $0x406da0,%edi
  405b58:	e8 e3 d8 ff ff       	call   403440 <private_assert_failed(char const*, char const*, int, char const*, char const*)>

Disassembly of section .fini:

0000000000405b60 <_fini>:
  405b60:	f3 0f 1e fa          	endbr64
  405b64:	48 83 ec 08          	sub    $0x8,%rsp
  405b68:	48 83 c4 08          	add    $0x8,%rsp
  405b6c:	c3                   	ret

EXIT 0
