
.autoport/reports/perf-mips2c-neon/notes/attempt8/nan-order-arm-gcc:     file format elf64-littleaarch64


Disassembly of section .init:

0000000000400500 <_init>:
  400500:	d503201f 	nop
  400504:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  400508:	910003fd 	mov	x29, sp
  40050c:	9400005e 	bl	400684 <call_weak_fn>
  400510:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400514:	d65f03c0 	ret

Disassembly of section .plt:

0000000000400520 <.plt>:
  400520:	a9bf7bf0 	stp	x16, x30, [sp, #-16]!
  400524:	f00000f0 	adrp	x16, 41f000 <__abi_tag+0x1e68c>
  400528:	f947fe11 	ldr	x17, [x16, #4088]
  40052c:	913fe210 	add	x16, x16, #0xff8
  400530:	d61f0220 	br	x17
  400534:	d503201f 	nop
  400538:	d503201f 	nop
  40053c:	d503201f 	nop

0000000000400540 <__libc_start_main@plt>:
  400540:	90000110 	adrp	x16, 420000 <__libc_start_main@GLIBC_2.34>
  400544:	f9400211 	ldr	x17, [x16]
  400548:	91000210 	add	x16, x16, #0x0
  40054c:	d61f0220 	br	x17

0000000000400550 <abort@plt>:
  400550:	90000110 	adrp	x16, 420000 <__libc_start_main@GLIBC_2.34>
  400554:	f9400611 	ldr	x17, [x16, #8]
  400558:	91002210 	add	x16, x16, #0x8
  40055c:	d61f0220 	br	x17

0000000000400560 <__gmon_start__@plt>:
  400560:	90000110 	adrp	x16, 420000 <__libc_start_main@GLIBC_2.34>
  400564:	f9400a11 	ldr	x17, [x16, #16]
  400568:	91004210 	add	x16, x16, #0x10
  40056c:	d61f0220 	br	x17

0000000000400570 <printf@plt>:
  400570:	90000110 	adrp	x16, 420000 <__libc_start_main@GLIBC_2.34>
  400574:	f9400e11 	ldr	x17, [x16, #24]
  400578:	91006210 	add	x16, x16, #0x18
  40057c:	d61f0220 	br	x17

Disassembly of section .text:

0000000000400580 <main>:
  400580:	d503245f 	bti	c
  400584:	90000000 	adrp	x0, 400000 <_init-0x500>
  400588:	91202000 	add	x0, x0, #0x808
  40058c:	d503233f 	paciasp
  400590:	a9ba7bfd 	stp	x29, x30, [sp, #-96]!
  400594:	910003fd 	mov	x29, sp
  400598:	3dc0081f 	ldr	q31, [x0, #32]
  40059c:	a90153f3 	stp	x19, x20, [sp, #16]
  4005a0:	9100c3f3 	add	x19, sp, #0x30
  4005a4:	ad40781d 	ldp	q29, q30, [x0]
  4005a8:	f90013f5 	str	x21, [sp, #32]
  4005ac:	90000015 	adrp	x21, 400000 <_init-0x500>
  4005b0:	911e42b5 	add	x21, x21, #0x790
  4005b4:	52800014 	mov	w20, #0x0                   	// #0
  4005b8:	3d8017ff 	str	q31, [sp, #80]
  4005bc:	ad01fbfd 	stp	q29, q30, [sp, #48]
  4005c0:	aa1503e0 	mov	x0, x21
  4005c4:	28c10a61 	ldp	w1, w2, [x19], #8
  4005c8:	1e270041 	fmov	s1, w2
  4005cc:	1e270020 	fmov	s0, w1
  4005d0:	94000064 	bl	400760 <ordered_mul(float, float)>
  4005d4:	1e270021 	fmov	s1, w1
  4005d8:	1e260003 	fmov	w3, s0
  4005dc:	1e270040 	fmov	s0, w2
  4005e0:	94000060 	bl	400760 <ordered_mul(float, float)>
  4005e4:	1e260004 	fmov	w4, s0
  4005e8:	6b04007f 	cmp	w3, w4
  4005ec:	1a940694 	cinc	w20, w20, ne	// ne = any
  4005f0:	1a9f07e5 	cset	w5, ne	// ne = any
  4005f4:	97ffffdf 	bl	400570 <printf@plt>
  4005f8:	910183e0 	add	x0, sp, #0x60
  4005fc:	eb13001f 	cmp	x0, x19
  400600:	54fffe01 	b.ne	4005c0 <main+0x40>  // b.any
  400604:	2a1403e1 	mov	w1, w20
  400608:	90000000 	adrp	x0, 400000 <_init-0x500>
  40060c:	911f8000 	add	x0, x0, #0x7e0
  400610:	97ffffd8 	bl	400570 <printf@plt>
  400614:	f94013f5 	ldr	x21, [sp, #32]
  400618:	52800000 	mov	w0, #0x0                   	// #0
  40061c:	a94153f3 	ldp	x19, x20, [sp, #16]
  400620:	a8c67bfd 	ldp	x29, x30, [sp], #96
  400624:	d50323bf 	autiasp
  400628:	d65f03c0 	ret
  40062c:	d503201f 	nop
  400630:	d503201f 	nop
  400634:	d503201f 	nop
  400638:	d503201f 	nop
  40063c:	d503201f 	nop

0000000000400640 <_start>:
  400640:	d503201f 	nop
  400644:	d280001d 	mov	x29, #0x0                   	// #0
  400648:	d280001e 	mov	x30, #0x0                   	// #0
  40064c:	aa0003e5 	mov	x5, x0
  400650:	f94003e1 	ldr	x1, [sp]
  400654:	910023e2 	add	x2, sp, #0x8
  400658:	910003e6 	mov	x6, sp
  40065c:	90000000 	adrp	x0, 400000 <_init-0x500>
  400660:	9119d000 	add	x0, x0, #0x674
  400664:	d2800003 	mov	x3, #0x0                   	// #0
  400668:	d2800004 	mov	x4, #0x0                   	// #0
  40066c:	97ffffb5 	bl	400540 <__libc_start_main@plt>
  400670:	97ffffb8 	bl	400550 <abort@plt>

0000000000400674 <__wrap_main>:
  400674:	d503201f 	nop
  400678:	17ffffc2 	b	400580 <main>
  40067c:	d503201f 	nop

0000000000400680 <_dl_relocate_static_pie>:
  400680:	d65f03c0 	ret

0000000000400684 <call_weak_fn>:
  400684:	f00000e0 	adrp	x0, 41f000 <__abi_tag+0x1e68c>
  400688:	f947ec00 	ldr	x0, [x0, #4056]
  40068c:	b4000040 	cbz	x0, 400694 <call_weak_fn+0x10>
  400690:	17ffffb4 	b	400560 <__gmon_start__@plt>
  400694:	d65f03c0 	ret
  400698:	d503201f 	nop
  40069c:	d503201f 	nop

00000000004006a0 <deregister_tm_clones>:
  4006a0:	90000100 	adrp	x0, 420000 <__libc_start_main@GLIBC_2.34>
  4006a4:	9100a001 	add	x1, x0, #0x28
  4006a8:	90000100 	adrp	x0, 420000 <__libc_start_main@GLIBC_2.34>
  4006ac:	9100a000 	add	x0, x0, #0x28
  4006b0:	eb00003f 	cmp	x1, x0
  4006b4:	540000c0 	b.eq	4006cc <deregister_tm_clones+0x2c>  // b.none
  4006b8:	f00000e1 	adrp	x1, 41f000 <__abi_tag+0x1e68c>
  4006bc:	f947e821 	ldr	x1, [x1, #4048]
  4006c0:	b4000061 	cbz	x1, 4006cc <deregister_tm_clones+0x2c>
  4006c4:	aa0103f0 	mov	x16, x1
  4006c8:	d61f0200 	br	x16
  4006cc:	d65f03c0 	ret

00000000004006d0 <register_tm_clones>:
  4006d0:	90000100 	adrp	x0, 420000 <__libc_start_main@GLIBC_2.34>
  4006d4:	9100a001 	add	x1, x0, #0x28
  4006d8:	90000100 	adrp	x0, 420000 <__libc_start_main@GLIBC_2.34>
  4006dc:	9100a000 	add	x0, x0, #0x28
  4006e0:	cb000021 	sub	x1, x1, x0
  4006e4:	d37ffc22 	lsr	x2, x1, #63
  4006e8:	8b810c41 	add	x1, x2, x1, asr #3
  4006ec:	9341fc21 	asr	x1, x1, #1
  4006f0:	b40000c1 	cbz	x1, 400708 <register_tm_clones+0x38>
  4006f4:	f00000e2 	adrp	x2, 41f000 <__abi_tag+0x1e68c>
  4006f8:	f947f042 	ldr	x2, [x2, #4064]
  4006fc:	b4000062 	cbz	x2, 400708 <register_tm_clones+0x38>
  400700:	aa0203f0 	mov	x16, x2
  400704:	d61f0200 	br	x16
  400708:	d65f03c0 	ret

000000000040070c <__do_global_dtors_aux>:
  40070c:	d503233f 	paciasp
  400710:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  400714:	910003fd 	mov	x29, sp
  400718:	f9000bf3 	str	x19, [sp, #16]
  40071c:	90000113 	adrp	x19, 420000 <__libc_start_main@GLIBC_2.34>
  400720:	39409260 	ldrb	w0, [x19, #36]
  400724:	37000080 	tbnz	w0, #0, 400734 <__do_global_dtors_aux+0x28>
  400728:	97ffffde 	bl	4006a0 <deregister_tm_clones>
  40072c:	52800020 	mov	w0, #0x1                   	// #1
  400730:	39009260 	strb	w0, [x19, #36]
  400734:	f9400bf3 	ldr	x19, [sp, #16]
  400738:	a8c27bfd 	ldp	x29, x30, [sp], #32
  40073c:	d50323bf 	autiasp
  400740:	d65f03c0 	ret

0000000000400744 <frame_dummy>:
  400744:	d503245f 	bti	c
  400748:	17ffffe2 	b	4006d0 <register_tm_clones>
  40074c:	d503201f 	nop
  400750:	d503201f 	nop
  400754:	d503201f 	nop
  400758:	d503201f 	nop
  40075c:	d503201f 	nop

0000000000400760 <ordered_mul(float, float)>:
  400760:	d503245f 	bti	c
  400764:	1e210800 	fmul	s0, s0, s1
  400768:	d65f03c0 	ret

Disassembly of section .fini:

000000000040076c <_fini>:
  40076c:	d503201f 	nop
  400770:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  400774:	910003fd 	mov	x29, sp
  400778:	a8c17bfd 	ldp	x29, x30, [sp], #16
  40077c:	d65f03c0 	ret
