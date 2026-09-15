
.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-block-parity-arm-gcc:     file format elf64-littleaarch64


Disassembly of section .init:

0000000000400620 <_init>:
  400620:	d503201f 	nop
  400624:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  400628:	910003fd 	mov	x29, sp
  40062c:	940002f6 	bl	401204 <call_weak_fn>
  400630:	a8c17bfd 	ldp	x29, x30, [sp], #16
  400634:	d65f03c0 	ret

Disassembly of section .plt:

0000000000400640 <.plt>:
  400640:	a9bf7bf0 	stp	x16, x30, [sp, #-16]!
  400644:	f00000f0 	adrp	x16, 41f000 <__abi_tag+0x1d278>
  400648:	f947fe11 	ldr	x17, [x16, #4088]
  40064c:	913fe210 	add	x16, x16, #0xff8
  400650:	d61f0220 	br	x17
  400654:	d503201f 	nop
  400658:	d503201f 	nop
  40065c:	d503201f 	nop

0000000000400660 <memcpy@plt>:
  400660:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  400664:	f9400211 	ldr	x17, [x16]
  400668:	91000210 	add	x16, x16, #0x0
  40066c:	d61f0220 	br	x17

0000000000400670 <fprintf@plt>:
  400670:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  400674:	f9400611 	ldr	x17, [x16, #8]
  400678:	91002210 	add	x16, x16, #0x8
  40067c:	d61f0220 	br	x17

0000000000400680 <memcmp@plt>:
  400680:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  400684:	f9400a11 	ldr	x17, [x16, #16]
  400688:	91004210 	add	x16, x16, #0x10
  40068c:	d61f0220 	br	x17

0000000000400690 <memset@plt>:
  400690:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  400694:	f9400e11 	ldr	x17, [x16, #24]
  400698:	91006210 	add	x16, x16, #0x18
  40069c:	d61f0220 	br	x17

00000000004006a0 <__libc_start_main@plt>:
  4006a0:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  4006a4:	f9401211 	ldr	x17, [x16, #32]
  4006a8:	91008210 	add	x16, x16, #0x20
  4006ac:	d61f0220 	br	x17

00000000004006b0 <abort@plt>:
  4006b0:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  4006b4:	f9401611 	ldr	x17, [x16, #40]
  4006b8:	9100a210 	add	x16, x16, #0x28
  4006bc:	d61f0220 	br	x17

00000000004006c0 <__gmon_start__@plt>:
  4006c0:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  4006c4:	f9401a11 	ldr	x17, [x16, #48]
  4006c8:	9100c210 	add	x16, x16, #0x30
  4006cc:	d61f0220 	br	x17

00000000004006d0 <printf@plt>:
  4006d0:	90000110 	adrp	x16, 420000 <memcpy@GLIBC_2.17>
  4006d4:	f9401e11 	ldr	x17, [x16, #56]
  4006d8:	9100e210 	add	x16, x16, #0x38
  4006dc:	d61f0220 	br	x17

Disassembly of section .text:

0000000000400700 <main>:
  400700:	d503233f 	paciasp
  400704:	d282b40c 	mov	x12, #0x15a0                	// #5536
  400708:	cb2c63ff 	sub	sp, sp, x12
  40070c:	528f3723 	mov	w3, #0x79b9                	// #31161
  400710:	90000100 	adrp	x0, 420000 <memcpy@GLIBC_2.17>
  400714:	72b3c6e3 	movk	w3, #0x9e37, lsl #16
  400718:	91018000 	add	x0, x0, #0x60
  40071c:	a9007bfd 	stp	x29, x30, [sp]
  400720:	910003fd 	mov	x29, sp
  400724:	d2821c0a 	mov	x10, #0x10e0                	// #4320
  400728:	a90363f7 	stp	x23, x24, [sp, #48]
  40072c:	b0000017 	adrp	x23, 401000 <main+0x900>
  400730:	912c02f7 	add	x23, x23, #0xb00
  400734:	6d073fee 	stp	d14, d15, [sp, #112]
  400738:	1e27006f 	fmov	s15, w3
  40073c:	910803e3 	add	x3, sp, #0x200
  400740:	3cc182fd 	ldur	q29, [x23, #24]
  400744:	529999b8 	mov	w24, #0xcccd                	// #52429
  400748:	3cc282fe 	ldur	q30, [x23, #40]
  40074c:	a90153f3 	stp	x19, x20, [sp, #16]
  400750:	912583f4 	add	x20, sp, #0x960
  400754:	3cc382ff 	ldur	q31, [x23, #56]
  400758:	a9025bf5 	stp	x21, x22, [sp, #32]
  40075c:	8b2a63f5 	add	x21, sp, x10
  400760:	f9400ae2 	ldr	x2, [x23, #16]
  400764:	912f83f6 	add	x22, sp, #0xbe0
  400768:	a9046bf9 	stp	x25, x26, [sp, #64]
  40076c:	72b99998 	movk	w24, #0xcccc, lsl #16
  400770:	52800019 	mov	w25, #0x0                   	// #0
  400774:	a90573fb 	stp	x27, x28, [sp, #80]
  400778:	911d83fc 	add	x28, sp, #0x760
  40077c:	6d0637ec 	stp	d12, d13, [sp, #96]
  400780:	f90043e0 	str	x0, [sp, #128]
  400784:	a94006e0 	ldp	x0, x1, [x23]
  400788:	29127fff 	stp	wzr, wzr, [sp, #144]
  40078c:	ad09fbfd 	stp	q29, q30, [sp, #304]
  400790:	a9318460 	stp	x0, x1, [x3, #-232]
  400794:	b900a3ff 	str	wzr, [sp, #160]
  400798:	f90097e2 	str	x2, [sp, #296]
  40079c:	3d8057ff 	str	q31, [sp, #336]
  4007a0:	71004f3f 	cmp	w25, #0x13
  4007a4:	1e2601e0 	fmov	w0, s15
  4007a8:	528000e5 	mov	w5, #0x7                   	// #7
  4007ac:	1a8593f3 	csel	w19, wzr, w5, ls	// ls = plast
  4007b0:	2a1903e1 	mov	w1, w25
  4007b4:	2a1303fa 	mov	w26, w19
  4007b8:	9104c3eb 	add	x11, sp, #0x130
  4007bc:	0b131f23 	add	w3, w25, w19, lsl #7
  4007c0:	4e040c3d 	dup	v29.4s, w1
  4007c4:	0b130064 	add	w4, w3, w19
  4007c8:	4a000320 	eor	w0, w25, w0
  4007cc:	0b130086 	add	w6, w4, w19
  4007d0:	b9010be0 	str	w0, [sp, #264]
  4007d4:	0b1300c0 	add	w0, w6, w19
  4007d8:	9bb87c67 	umull	x7, w3, w24
  4007dc:	0b13000c 	add	w12, w0, w19
  4007e0:	9bb87c89 	umull	x9, w4, w24
  4007e4:	9bb87cca 	umull	x10, w6, w24
  4007e8:	11000739 	add	w25, w25, #0x1
  4007ec:	9bb87c02 	umull	x2, w0, w24
  4007f0:	d364fce7 	lsr	x7, x7, #36
  4007f4:	9bb87d88 	umull	x8, w12, w24
  4007f8:	d364fd29 	lsr	x9, x9, #36
  4007fc:	d364fd4a 	lsr	x10, x10, #36
  400800:	0b0708e7 	add	w7, w7, w7, lsl #2
  400804:	d364fc42 	lsr	x2, x2, #36
  400808:	0b090929 	add	w9, w9, w9, lsl #2
  40080c:	d364fd08 	lsr	x8, x8, #36
  400810:	0b0a094a 	add	w10, w10, w10, lsl #2
  400814:	0b020842 	add	w2, w2, w2, lsl #2
  400818:	4b090889 	sub	w9, w4, w9, lsl #2
  40081c:	0b080908 	add	w8, w8, w8, lsl #2
  400820:	4b0a08ca 	sub	w10, w6, w10, lsl #2
  400824:	4b020802 	sub	w2, w0, w2, lsl #2
  400828:	b0000000 	adrp	x0, 401000 <main+0x900>
  40082c:	4b070867 	sub	w7, w3, w7, lsl #2
  400830:	4b080988 	sub	w8, w12, w8, lsl #2
  400834:	3dc2b81f 	ldr	q31, [x0, #2784]
  400838:	f9004feb 	str	x11, [sp, #152]
  40083c:	4ebf87bd 	add	v29.4s, v29.4s, v31.4s
  400840:	2a1a03fb 	mov	w27, w26
  400844:	910463e0 	add	x0, sp, #0x118
  400848:	f90047e0 	str	x0, [sp, #136]
  40084c:	b900a7e1 	str	w1, [sp, #164]
  400850:	f90057eb 	str	x11, [sp, #168]
  400854:	291e9fe8 	stp	w8, w7, [sp, #244]
  400858:	291fabe9 	stp	w9, w10, [sp, #252]
  40085c:	b90107e2 	str	w2, [sp, #260]
  400860:	b9010ff9 	str	w25, [sp, #268]
  400864:	3d802ffd 	str	q29, [sp, #176]
  400868:	d2809802 	mov	x2, #0x4c0                 	// #1216
  40086c:	f94047e0 	ldr	x0, [sp, #136]
  400870:	52800001 	mov	w1, #0x0                   	// #0
  400874:	b9400000 	ldr	w0, [x0]
  400878:	b900e3e0 	str	w0, [sp, #224]
  40087c:	aa1c03e0 	mov	x0, x28
  400880:	97ffff84 	bl	400690 <memset@plt>
  400884:	3cc482ff 	ldur	q31, [x23, #72]
  400888:	3cc582fc 	ldur	q28, [x23, #88]
  40088c:	3cc682fe 	ldur	q30, [x23, #104]
  400890:	ad0072bf 	stp	q31, q28, [x21]
  400894:	3cc782fc 	ldur	q28, [x23, #120]
  400898:	3cc882ff 	ldur	q31, [x23, #136]
  40089c:	ad0172be 	stp	q30, q28, [x21, #32]
  4008a0:	b940a7e0 	ldr	w0, [sp, #164]
  4008a4:	3d8012bf 	str	q31, [x21, #64]
  4008a8:	71009c1f 	cmp	w0, #0x27
  4008ac:	54003809 	b.ls	400fac <main+0x8ac>  // b.plast
  4008b0:	b9410be0 	ldr	w0, [sp, #264]
  4008b4:	912783e2 	add	x2, sp, #0x9e0
  4008b8:	d503201f 	nop
  4008bc:	d503201f 	nop
  4008c0:	4a003401 	eor	w1, w0, w0, lsl #13
  4008c4:	91004042 	add	x2, x2, #0x10
  4008c8:	4a414421 	eor	w1, w1, w1, lsr #17
  4008cc:	4a011421 	eor	w1, w1, w1, lsl #5
  4008d0:	4a013420 	eor	w0, w1, w1, lsl #13
  4008d4:	4a404400 	eor	w0, w0, w0, lsr #17
  4008d8:	4a001400 	eor	w0, w0, w0, lsl #5
  4008dc:	293e0041 	stp	w1, w0, [x2, #-16]
  4008e0:	4a003401 	eor	w1, w0, w0, lsl #13
  4008e4:	4a414421 	eor	w1, w1, w1, lsr #17
  4008e8:	4a011421 	eor	w1, w1, w1, lsl #5
  4008ec:	4a013420 	eor	w0, w1, w1, lsl #13
  4008f0:	4a404400 	eor	w0, w0, w0, lsr #17
  4008f4:	4a001400 	eor	w0, w0, w0, lsl #5
  4008f8:	293f0041 	stp	w1, w0, [x2, #-8]
  4008fc:	eb0202df 	cmp	x22, x2
  400900:	54fffe01 	b.ne	4008c0 <main+0x1c0>  // b.any
  400904:	4a003403 	eor	w3, w0, w0, lsl #13
  400908:	4a434463 	eor	w3, w3, w3, lsr #17
  40090c:	4a031463 	eor	w3, w3, w3, lsl #5
  400910:	4a033467 	eor	w7, w3, w3, lsl #13
  400914:	4a4744e7 	eor	w7, w7, w7, lsr #17
  400918:	4a0714e7 	eor	w7, w7, w7, lsl #5
  40091c:	4a0734e6 	eor	w6, w7, w7, lsl #13
  400920:	4a4644c6 	eor	w6, w6, w6, lsr #17
  400924:	4a0614c6 	eor	w6, w6, w6, lsl #5
  400928:	4a0634c4 	eor	w4, w6, w6, lsl #13
  40092c:	4a444484 	eor	w4, w4, w4, lsr #17
  400930:	4a041484 	eor	w4, w4, w4, lsl #5
  400934:	4a043488 	eor	w8, w4, w4, lsl #13
  400938:	4a484508 	eor	w8, w8, w8, lsr #17
  40093c:	4a081508 	eor	w8, w8, w8, lsl #5
  400940:	3dc02ffd 	ldr	q29, [sp, #176]
  400944:	aa1c03e0 	mov	x0, x28
  400948:	4f00041e 	movi	v30.4s, #0x0
  40094c:	4f00043c 	movi	v28.4s, #0x1
  400950:	4f2257df 	shl	v31.4s, v30.4s, #2
  400954:	4ebc87de 	add	v30.4s, v30.4s, v28.4s
  400958:	4ebd87ff 	add	v31.4s, v31.4s, v29.4s
  40095c:	4f8f83ff 	mul	v31.4s, v31.4s, v15.s[0]
  400960:	3c81041f 	str	q31, [x0], #16
  400964:	eb14001f 	cmp	x0, x20
  400968:	54ffff41 	b.ne	400950 <main+0x250>  // b.any
  40096c:	f94057e0 	ldr	x0, [sp, #168]
  400970:	b900c3e3 	str	w3, [sp, #192]
  400974:	b900d3e6 	str	w6, [sp, #208]
  400978:	d2804002 	mov	x2, #0x200                 	// #512
  40097c:	291ca3e7 	stp	w7, w8, [sp, #228]
  400980:	52800001 	mov	w1, #0x0                   	// #0
  400984:	b900f3e4 	str	w4, [sp, #240]
  400988:	29404c19 	ldp	w25, w19, [x0]
  40098c:	910583e0 	add	x0, sp, #0x160
  400990:	b908a3f9 	str	w25, [sp, #2208]
  400994:	b908b3f3 	str	w19, [sp, #2224]
  400998:	97ffff3e 	bl	400690 <memset@plt>
  40099c:	b940c3e3 	ldr	w3, [sp, #192]
  4009a0:	910583e2 	add	x2, sp, #0x160
  4009a4:	b940d3e6 	ldr	w6, [sp, #208]
  4009a8:	52800000 	mov	w0, #0x0                   	// #0
  4009ac:	295ca3e7 	ldp	w7, w8, [sp, #228]
  4009b0:	b940f3e4 	ldr	w4, [sp, #240]
  4009b4:	d503201f 	nop
  4009b8:	d503201f 	nop
  4009bc:	d503201f 	nop
  4009c0:	927e7401 	and	x1, x0, #0xfffffffc
  4009c4:	11001000 	add	w0, w0, #0x4
  4009c8:	910a0021 	add	x1, x1, #0x280
  4009cc:	b8616b81 	ldr	w1, [x28, x1]
  4009d0:	b8004441 	str	w1, [x2], #4
  4009d4:	7108001f 	cmp	w0, #0x200
  4009d8:	54ffff41 	b.ne	4009c0 <main+0x2c0>  // b.any
  4009dc:	910703e0 	add	x0, sp, #0x1c0
  4009e0:	912fa3e9 	add	x9, sp, #0xbe8
  4009e4:	b940e3e1 	ldr	w1, [sp, #224]
  4009e8:	1e2e901f 	fmov	s31, #1.250000000000000000e+00
  4009ec:	d2809802 	mov	x2, #0x4c0                 	// #1216
  4009f0:	b8334801 	str	w1, [x0, w19, uxtw]
  4009f4:	aa1c03e1 	mov	x1, x28
  4009f8:	293f1d23 	stp	w3, w7, [x9, #-8]
  4009fc:	913083e0 	add	x0, sp, #0xc20
  400a00:	29001126 	stp	w6, w4, [x9]
  400a04:	b90bf3e8 	str	w8, [sp, #3056]
  400a08:	bd0bf7ff 	str	s31, [sp, #3060]
  400a0c:	97ffff15 	bl	400660 <memcpy@plt>
  400a10:	aa1c03e1 	mov	x1, x28
  400a14:	d2809802 	mov	x2, #0x4c0                 	// #1216
  400a18:	aa1503e0 	mov	x0, x21
  400a1c:	97ffff11 	bl	400660 <memcpy@plt>
  400a20:	910583e1 	add	x1, sp, #0x160
  400a24:	d2804002 	mov	x2, #0x200                 	// #512
  400a28:	910d83e0 	add	x0, sp, #0x360
  400a2c:	97ffff0d 	bl	400660 <memcpy@plt>
  400a30:	910583e1 	add	x1, sp, #0x160
  400a34:	d2804002 	mov	x2, #0x200                 	// #512
  400a38:	911583e0 	add	x0, sp, #0x560
  400a3c:	97ffff09 	bl	400660 <memcpy@plt>
  400a40:	f94043e1 	ldr	x1, [sp, #128]
  400a44:	910d83e2 	add	x2, sp, #0x360
  400a48:	913083e0 	add	x0, sp, #0xc20
  400a4c:	f9000022 	str	x2, [x1]
  400a50:	94000224 	bl	4012e0 <before(Mips2C::ExecutionContext*)>
  400a54:	f94043e1 	ldr	x1, [sp, #128]
  400a58:	911583e2 	add	x2, sp, #0x560
  400a5c:	12001c1a 	and	w26, w0, #0xff
  400a60:	aa1503e0 	mov	x0, x21
  400a64:	f9000022 	str	x2, [x1]
  400a68:	940002a6 	bl	401500 <after(Mips2C::ExecutionContext*)>
  400a6c:	12001c00 	and	w0, w0, #0xff
  400a70:	3600211a 	tbz	w26, #0, 400e90 <main+0x790>
  400a74:	b94097e1 	ldr	w1, [sp, #148]
  400a78:	11000421 	add	w1, w1, #0x1
  400a7c:	b90097e1 	str	w1, [sp, #148]
  400a80:	6b00035f 	cmp	w26, w0
  400a84:	54002100 	b.eq	400ea4 <main+0x7a4>  // b.none
  400a88:	b94093e0 	ldr	w0, [sp, #144]
  400a8c:	71002c1f 	cmp	w0, #0xb
  400a90:	54002249 	b.ls	400ed8 <main+0x7d8>  // b.plast
  400a94:	b94093e0 	ldr	w0, [sp, #144]
  400a98:	11000400 	add	w0, w0, #0x1
  400a9c:	b90093e0 	str	w0, [sp, #144]
  400aa0:	f94047e0 	ldr	x0, [sp, #136]
  400aa4:	f9404fe1 	ldr	x1, [sp, #152]
  400aa8:	91001000 	add	x0, x0, #0x4
  400aac:	f90047e0 	str	x0, [sp, #136]
  400ab0:	eb00003f 	cmp	x1, x0
  400ab4:	54ffeda1 	b.ne	400868 <main+0x168>  // b.any
  400ab8:	f94057eb 	ldr	x11, [sp, #168]
  400abc:	910583e0 	add	x0, sp, #0x160
  400ac0:	3dc02ffd 	ldr	q29, [sp, #176]
  400ac4:	9100216b 	add	x11, x11, #0x8
  400ac8:	b940a7e1 	ldr	w1, [sp, #164]
  400acc:	2a1b03fa 	mov	w26, w27
  400ad0:	295e9fe8 	ldp	w8, w7, [sp, #244]
  400ad4:	295fabe9 	ldp	w9, w10, [sp, #252]
  400ad8:	b94107e2 	ldr	w2, [sp, #260]
  400adc:	b9410ff9 	ldr	w25, [sp, #268]
  400ae0:	eb00017f 	cmp	x11, x0
  400ae4:	54ffeae1 	b.ne	400840 <main+0x140>  // b.any
  400ae8:	7101a33f 	cmp	w25, #0x68
  400aec:	54ffe5a1 	b.ne	4007a0 <main+0xa0>  // b.any
  400af0:	9112039b 	add	x27, x28, #0x480
  400af4:	2a1903f6 	mov	w22, w25
  400af8:	52a7b000 	mov	w0, #0x3d800000            	// #1031798784
  400afc:	1e27000c 	fmov	s12, w0
  400b00:	5291c720 	mov	w0, #0x8e39                	// #36409
  400b04:	528000e3 	mov	w3, #0x7                   	// #7
  400b08:	72a71c60 	movk	w0, #0x38e3, lsl #16
  400b0c:	120006c2 	and	w2, w22, #0x3
  400b10:	1ac30ac3 	udiv	w3, w22, w3
  400b14:	4e040edc 	dup	v28.4s, w22
  400b18:	9ba07ec0 	umull	x0, w22, w0
  400b1c:	1e02f84d 	scvtf	s13, w2, #2
  400b20:	531b6ac4 	lsl	w4, w22, #5
  400b24:	528f3739 	mov	w25, #0x79b9                	// #31161
  400b28:	4b160084 	sub	w4, w4, w22
  400b2c:	72b3c6f9 	movk	w25, #0x9e37, lsl #16
  400b30:	d361fc00 	lsr	x0, x0, #33
  400b34:	531d7062 	lsl	w2, w3, #3
  400b38:	4b030042 	sub	w2, w2, w3
  400b3c:	4e040c98 	dup	v24.4s, w4
  400b40:	0b000c00 	add	w0, w0, w0, lsl #3
  400b44:	4b0202c2 	sub	w2, w22, w2
  400b48:	4b0002c0 	sub	w0, w22, w0
  400b4c:	4a1902c3 	eor	w3, w22, w25
  400b50:	1e22004e 	scvtf	s14, w2
  400b54:	2a1603e1 	mov	w1, w22
  400b58:	1e02f40f 	scvtf	s15, w0, #3
  400b5c:	b0000000 	adrp	x0, 401000 <main+0x900>
  400b60:	aa1b03f9 	mov	x25, x27
  400b64:	110006d6 	add	w22, w22, #0x1
  400b68:	3dc2b81f 	ldr	q31, [x0, #2784]
  400b6c:	1e2c09ce 	fmul	s14, s14, s12
  400b70:	9104c3fb 	add	x27, sp, #0x130
  400b74:	b900e7e3 	str	w3, [sp, #228]
  400b78:	b0000003 	adrp	x3, 401000 <main+0x900>
  400b7c:	9127a060 	add	x0, x3, #0x9e8
  400b80:	4ebf879c 	add	v28.4s, v28.4s, v31.4s
  400b84:	f90077e0 	str	x0, [sp, #232]
  400b88:	b94093f7 	ldr	w23, [sp, #144]
  400b8c:	910463f3 	add	x19, sp, #0x118
  400b90:	f9005bfb 	str	x27, [sp, #176]
  400b94:	291e5be1 	stp	w1, w22, [sp, #240]
  400b98:	ad0663fc 	stp	q28, q24, [sp, #192]
  400b9c:	d2809802 	mov	x2, #0x4c0                 	// #1216
  400ba0:	52800001 	mov	w1, #0x0                   	// #0
  400ba4:	b9400278 	ldr	w24, [x19]
  400ba8:	aa1c03e0 	mov	x0, x28
  400bac:	97fffeb9 	bl	400690 <memset@plt>
  400bb0:	b0000001 	adrp	x1, 401000 <main+0x900>
  400bb4:	b940e7e0 	ldr	w0, [sp, #228]
  400bb8:	910a0382 	add	x2, x28, #0x280
  400bbc:	3dc2b03b 	ldr	q27, [x1, #2752]
  400bc0:	4a003401 	eor	w1, w0, w0, lsl #13
  400bc4:	91004042 	add	x2, x2, #0x10
  400bc8:	4a414421 	eor	w1, w1, w1, lsr #17
  400bcc:	4a011421 	eor	w1, w1, w1, lsl #5
  400bd0:	4a013420 	eor	w0, w1, w1, lsl #13
  400bd4:	4a404400 	eor	w0, w0, w0, lsr #17
  400bd8:	4a001400 	eor	w0, w0, w0, lsl #5
  400bdc:	293e0041 	stp	w1, w0, [x2, #-16]
  400be0:	4a003401 	eor	w1, w0, w0, lsl #13
  400be4:	4a414421 	eor	w1, w1, w1, lsr #17
  400be8:	4a011421 	eor	w1, w1, w1, lsl #5
  400bec:	4a013420 	eor	w0, w1, w1, lsl #13
  400bf0:	4a404400 	eor	w0, w0, w0, lsr #17
  400bf4:	4a001400 	eor	w0, w0, w0, lsl #5
  400bf8:	293f0041 	stp	w1, w0, [x2, #-8]
  400bfc:	eb02033f 	cmp	x25, x2
  400c00:	54fffe01 	b.ne	400bc0 <main+0x4c0>  // b.any
  400c04:	4f00041e 	movi	v30.4s, #0x0
  400c08:	4a003403 	eor	w3, w0, w0, lsl #13
  400c0c:	3dc033fc 	ldr	q28, [sp, #192]
  400c10:	4a434463 	eor	w3, w3, w3, lsr #17
  400c14:	4f00043d 	movi	v29.4s, #0x1
  400c18:	aa1c03e0 	mov	x0, x28
  400c1c:	4a031463 	eor	w3, w3, w3, lsl #5
  400c20:	4a033467 	eor	w7, w3, w3, lsl #13
  400c24:	4a4744e7 	eor	w7, w7, w7, lsr #17
  400c28:	4a0714e7 	eor	w7, w7, w7, lsl #5
  400c2c:	4a0734e6 	eor	w6, w7, w7, lsl #13
  400c30:	4a4644c6 	eor	w6, w6, w6, lsr #17
  400c34:	4a0614c6 	eor	w6, w6, w6, lsl #5
  400c38:	4a0634c4 	eor	w4, w6, w6, lsl #13
  400c3c:	4a444484 	eor	w4, w4, w4, lsr #17
  400c40:	4a041484 	eor	w4, w4, w4, lsl #5
  400c44:	4a043481 	eor	w1, w4, w4, lsl #13
  400c48:	4a414421 	eor	w1, w1, w1, lsr #17
  400c4c:	4a011428 	eor	w8, w1, w1, lsl #5
  400c50:	4f2257df 	shl	v31.4s, v30.4s, #2
  400c54:	4ebd87de 	add	v30.4s, v30.4s, v29.4s
  400c58:	4ebc87ff 	add	v31.4s, v31.4s, v28.4s
  400c5c:	4ebb9fff 	mul	v31.4s, v31.4s, v27.4s
  400c60:	3c81041f 	str	q31, [x0], #16
  400c64:	eb00029f 	cmp	x20, x0
  400c68:	54ffff41 	b.ne	400c50 <main+0x550>  // b.any
  400c6c:	f9405be0 	ldr	x0, [sp, #176]
  400c70:	b9008be8 	str	w8, [sp, #136]
  400c74:	b90093e4 	str	w4, [sp, #144]
  400c78:	d2804002 	mov	x2, #0x200                 	// #512
  400c7c:	29148fe6 	stp	w6, w3, [sp, #164]
  400c80:	52800001 	mov	w1, #0x0                   	// #0
  400c84:	b900e3e7 	str	w7, [sp, #224]
  400c88:	2940581a 	ldp	w26, w22, [x0]
  400c8c:	910583e0 	add	x0, sp, #0x160
  400c90:	b908a3fa 	str	w26, [sp, #2208]
  400c94:	b908b3f6 	str	w22, [sp, #2224]
  400c98:	97fffe7e 	bl	400690 <memset@plt>
  400c9c:	b0000000 	adrp	x0, 401000 <main+0x900>
  400ca0:	b0000002 	adrp	x2, 401000 <main+0x900>
  400ca4:	3dc037f8 	ldr	q24, [sp, #208]
  400ca8:	3dc2bc1d 	ldr	q29, [x0, #2800]
  400cac:	910583e0 	add	x0, sp, #0x160
  400cb0:	6f00c475 	mvni	v21.4s, #0x3, msl #8
  400cb4:	b9408be8 	ldr	w8, [sp, #136]
  400cb8:	4f02f416 	fmov	v22.4s, #1.250000000000000000e-01
  400cbc:	b94093e4 	ldr	w4, [sp, #144]
  400cc0:	4f000617 	movi	v23.4s, #0x10
  400cc4:	b940e3e7 	ldr	w7, [sp, #224]
  400cc8:	3dc2b45a 	ldr	q26, [x2, #2768]
  400ccc:	91080001 	add	x1, x0, #0x200
  400cd0:	29548fe6 	ldp	w6, w3, [sp, #164]
  400cd4:	d503201f 	nop
  400cd8:	d503201f 	nop
  400cdc:	d503201f 	nop
  400ce0:	4f2457bf 	shl	v31.4s, v29.4s, #4
  400ce4:	4ebd87ff 	add	v31.4s, v31.4s, v29.4s
  400ce8:	4eb787bd 	add	v29.4s, v29.4s, v23.4s
  400cec:	4eb887ff 	add	v31.4s, v31.4s, v24.4s
  400cf0:	2ebac3fe 	umull	v30.2d, v31.2s, v26.2s
  400cf4:	6ebac3f9 	umull2	v25.2d, v31.4s, v26.4s
  400cf8:	4e995bde 	uzp2	v30.4s, v30.4s, v25.4s
  400cfc:	6f3f07de 	ushr	v30.4s, v30.4s, #1
  400d00:	4f2b57dc 	shl	v28.4s, v30.4s, #11
  400d04:	4ebe879e 	add	v30.4s, v28.4s, v30.4s
  400d08:	6ebe87ff 	sub	v31.4s, v31.4s, v30.4s
  400d0c:	4eb587ff 	add	v31.4s, v31.4s, v21.4s
  400d10:	4e21dbff 	scvtf	v31.4s, v31.4s
  400d14:	6e36dfff 	fmul	v31.4s, v31.4s, v22.4s
  400d18:	3c81041f 	str	q31, [x0], #16
  400d1c:	eb00003f 	cmp	x1, x0
  400d20:	54fffe01 	b.ne	400ce0 <main+0x5e0>  // b.any
  400d24:	910703e0 	add	x0, sp, #0x1c0
  400d28:	912fa3e5 	add	x5, sp, #0xbe8
  400d2c:	b90ae3ff 	str	wzr, [sp, #2784]
  400d30:	1e2e901f 	fmov	s31, #1.250000000000000000e+00
  400d34:	bd0ae7ed 	str	s13, [sp, #2788]
  400d38:	aa1c03e1 	mov	x1, x28
  400d3c:	b8364818 	str	w24, [x0, w22, uxtw]
  400d40:	d2809802 	mov	x2, #0x4c0                 	// #1216
  400d44:	bd0aebee 	str	s14, [sp, #2792]
  400d48:	913083e0 	add	x0, sp, #0xc20
  400d4c:	bd0aefef 	str	s15, [sp, #2796]
  400d50:	293f1ca3 	stp	w3, w7, [x5, #-8]
  400d54:	290010a6 	stp	w6, w4, [x5]
  400d58:	b90bf3e8 	str	w8, [sp, #3056]
  400d5c:	bd0bf7ff 	str	s31, [sp, #3060]
  400d60:	97fffe40 	bl	400660 <memcpy@plt>
  400d64:	aa1c03e1 	mov	x1, x28
  400d68:	d2809802 	mov	x2, #0x4c0                 	// #1216
  400d6c:	aa1503e0 	mov	x0, x21
  400d70:	97fffe3c 	bl	400660 <memcpy@plt>
  400d74:	910583e1 	add	x1, sp, #0x160
  400d78:	d2804002 	mov	x2, #0x200                 	// #512
  400d7c:	910d83e0 	add	x0, sp, #0x360
  400d80:	97fffe38 	bl	400660 <memcpy@plt>
  400d84:	910583e1 	add	x1, sp, #0x160
  400d88:	d2804002 	mov	x2, #0x200                 	// #512
  400d8c:	911583e0 	add	x0, sp, #0x560
  400d90:	97fffe34 	bl	400660 <memcpy@plt>
  400d94:	f94043e1 	ldr	x1, [sp, #128]
  400d98:	910d83e2 	add	x2, sp, #0x360
  400d9c:	913083e0 	add	x0, sp, #0xc20
  400da0:	f9000022 	str	x2, [x1]
  400da4:	9400014f 	bl	4012e0 <before(Mips2C::ExecutionContext*)>
  400da8:	f94043e1 	ldr	x1, [sp, #128]
  400dac:	911583e2 	add	x2, sp, #0x560
  400db0:	12001c1b 	and	w27, w0, #0xff
  400db4:	aa1503e0 	mov	x0, x21
  400db8:	f9000022 	str	x2, [x1]
  400dbc:	940001d1 	bl	401500 <after(Mips2C::ExecutionContext*)>
  400dc0:	12001c00 	and	w0, w0, #0xff
  400dc4:	36001b3b 	tbz	w27, #0, 401128 <main+0xa28>
  400dc8:	b94097e1 	ldr	w1, [sp, #148]
  400dcc:	11000421 	add	w1, w1, #0x1
  400dd0:	b90097e1 	str	w1, [sp, #148]
  400dd4:	6b00037f 	cmp	w27, w0
  400dd8:	54001b20 	b.eq	40113c <main+0xa3c>  // b.none
  400ddc:	71002eff 	cmp	w23, #0xb
  400de0:	54001409 	b.ls	401060 <main+0x960>  // b.plast
  400de4:	110006f7 	add	w23, w23, #0x1
  400de8:	f9404fe0 	ldr	x0, [sp, #152]
  400dec:	91001273 	add	x19, x19, #0x4
  400df0:	eb13001f 	cmp	x0, x19
  400df4:	54ffed41 	b.ne	400b9c <main+0x49c>  // b.any
  400df8:	f9405bfb 	ldr	x27, [sp, #176]
  400dfc:	910583e0 	add	x0, sp, #0x160
  400e00:	b90093f7 	str	w23, [sp, #144]
  400e04:	9100237b 	add	x27, x27, #0x8
  400e08:	295e5be1 	ldp	w1, w22, [sp, #240]
  400e0c:	ad4663fc 	ldp	q28, q24, [sp, #192]
  400e10:	eb00037f 	cmp	x27, x0
  400e14:	54ffeba1 	b.ne	400b88 <main+0x488>  // b.any
  400e18:	aa1903fb 	mov	x27, x25
  400e1c:	7102a2df 	cmp	w22, #0xa8
  400e20:	54ffe701 	b.ne	400b00 <main+0x400>  // b.any
  400e24:	b94097e4 	ldr	w4, [sp, #148]
  400e28:	b0000000 	adrp	x0, 401000 <main+0x900>
  400e2c:	b940a3e3 	ldr	w3, [sp, #160]
  400e30:	2a1703e5 	mov	w5, w23
  400e34:	9128c000 	add	x0, x0, #0xa30
  400e38:	52812002 	mov	w2, #0x900                 	// #2304
  400e3c:	5282f401 	mov	w1, #0x17a0                	// #6048
  400e40:	97fffe24 	bl	4006d0 <printf@plt>
  400e44:	34001937 	cbz	w23, 401168 <main+0xa68>
  400e48:	b0000001 	adrp	x1, 401000 <main+0x900>
  400e4c:	b0000000 	adrp	x0, 401000 <main+0x900>
  400e50:	912a2021 	add	x1, x1, #0xa88
  400e54:	912a4000 	add	x0, x0, #0xa90
  400e58:	97fffe1e 	bl	4006d0 <printf@plt>
  400e5c:	52800020 	mov	w0, #0x1                   	// #1
  400e60:	a9407bfd 	ldp	x29, x30, [sp]
  400e64:	d282b40c 	mov	x12, #0x15a0                	// #5536
  400e68:	a94153f3 	ldp	x19, x20, [sp, #16]
  400e6c:	a9425bf5 	ldp	x21, x22, [sp, #32]
  400e70:	a94363f7 	ldp	x23, x24, [sp, #48]
  400e74:	a9446bf9 	ldp	x25, x26, [sp, #64]
  400e78:	a94573fb 	ldp	x27, x28, [sp, #80]
  400e7c:	6d4637ec 	ldp	d12, d13, [sp, #96]
  400e80:	6d473fee 	ldp	d14, d15, [sp, #112]
  400e84:	8b2c63ff 	add	sp, sp, x12
  400e88:	d50323bf 	autiasp
  400e8c:	d65f03c0 	ret
  400e90:	b940a3e1 	ldr	w1, [sp, #160]
  400e94:	11000421 	add	w1, w1, #0x1
  400e98:	b900a3e1 	str	w1, [sp, #160]
  400e9c:	6b00035f 	cmp	w26, w0
  400ea0:	54ffdf41 	b.ne	400a88 <main+0x388>  // b.any
  400ea4:	aa1503e1 	mov	x1, x21
  400ea8:	913083e0 	add	x0, sp, #0xc20
  400eac:	d2809802 	mov	x2, #0x4c0                 	// #1216
  400eb0:	97fffdf4 	bl	400680 <memcmp@plt>
  400eb4:	35ffdea0 	cbnz	w0, 400a88 <main+0x388>
  400eb8:	911583e1 	add	x1, sp, #0x560
  400ebc:	910d83e0 	add	x0, sp, #0x360
  400ec0:	d2804002 	mov	x2, #0x200                 	// #512
  400ec4:	97fffdef 	bl	400680 <memcmp@plt>
  400ec8:	34ffdec0 	cbz	w0, 400aa0 <main+0x3a0>
  400ecc:	b94093e0 	ldr	w0, [sp, #144]
  400ed0:	71002c1f 	cmp	w0, #0xb
  400ed4:	54ffde08 	b.hi	400a94 <main+0x394>  // b.pmore
  400ed8:	b940a7e1 	ldr	w1, [sp, #164]
  400edc:	2a1303e3 	mov	w3, w19
  400ee0:	b940e3e4 	ldr	w4, [sp, #224]
  400ee4:	2a1903e2 	mov	w2, w25
  400ee8:	b0000000 	adrp	x0, 401000 <main+0x900>
  400eec:	9127a000 	add	x0, x0, #0x9e8
  400ef0:	913a83f9 	add	x25, sp, #0xea0
  400ef4:	52800013 	mov	w19, #0x0                   	// #0
  400ef8:	97fffdf6 	bl	4006d0 <printf@plt>
  400efc:	b900e3fb 	str	w27, [sp, #224]
  400f00:	b0000007 	adrp	x7, 401000 <main+0x900>
  400f04:	d2826c06 	mov	x6, #0x1360                	// #4960
  400f08:	912840fa 	add	x26, x7, #0xa10
  400f0c:	8b2663fb 	add	x27, sp, x6
  400f10:	b9400323 	ldr	w3, [x25]
  400f14:	2a1303e1 	mov	w1, w19
  400f18:	b9400364 	ldr	w4, [x27]
  400f1c:	aa1a03e0 	mov	x0, x26
  400f20:	52800002 	mov	w2, #0x0                   	// #0
  400f24:	6b03009f 	cmp	w4, w3
  400f28:	54000040 	b.eq	400f30 <main+0x830>  // b.none
  400f2c:	97fffde9 	bl	4006d0 <printf@plt>
  400f30:	b9400723 	ldr	w3, [x25, #4]
  400f34:	2a1303e1 	mov	w1, w19
  400f38:	b9400764 	ldr	w4, [x27, #4]
  400f3c:	aa1a03e0 	mov	x0, x26
  400f40:	52800022 	mov	w2, #0x1                   	// #1
  400f44:	6b03009f 	cmp	w4, w3
  400f48:	54000040 	b.eq	400f50 <main+0x850>  // b.none
  400f4c:	97fffde1 	bl	4006d0 <printf@plt>
  400f50:	b9400b23 	ldr	w3, [x25, #8]
  400f54:	2a1303e1 	mov	w1, w19
  400f58:	b9400b64 	ldr	w4, [x27, #8]
  400f5c:	aa1a03e0 	mov	x0, x26
  400f60:	52800042 	mov	w2, #0x2                   	// #2
  400f64:	6b04007f 	cmp	w3, w4
  400f68:	54000040 	b.eq	400f70 <main+0x870>  // b.none
  400f6c:	97fffdd9 	bl	4006d0 <printf@plt>
  400f70:	b9400f23 	ldr	w3, [x25, #12]
  400f74:	2a1303e1 	mov	w1, w19
  400f78:	b9400f64 	ldr	w4, [x27, #12]
  400f7c:	aa1a03e0 	mov	x0, x26
  400f80:	52800062 	mov	w2, #0x3                   	// #3
  400f84:	6b04007f 	cmp	w3, w4
  400f88:	54000040 	b.eq	400f90 <main+0x890>  // b.none
  400f8c:	97fffdd1 	bl	4006d0 <printf@plt>
  400f90:	11000673 	add	w19, w19, #0x1
  400f94:	91004339 	add	x25, x25, #0x10
  400f98:	9100437b 	add	x27, x27, #0x10
  400f9c:	7100827f 	cmp	w19, #0x20
  400fa0:	54fffb81 	b.ne	400f10 <main+0x810>  // b.any
  400fa4:	b940e3fb 	ldr	w27, [sp, #224]
  400fa8:	17fffebb 	b	400a94 <main+0x394>
  400fac:	b940a7e4 	ldr	w4, [sp, #164]
  400fb0:	912783e6 	add	x6, sp, #0x9e0
  400fb4:	d503201f 	nop
  400fb8:	d503201f 	nop
  400fbc:	d503201f 	nop
  400fc0:	0b040368 	add	w8, w27, w4
  400fc4:	9bb87c83 	umull	x3, w4, w24
  400fc8:	0b080367 	add	w7, w27, w8
  400fcc:	910040c6 	add	x6, x6, #0x10
  400fd0:	0b070365 	add	w5, w27, w7
  400fd4:	9bb87d02 	umull	x2, w8, w24
  400fd8:	d364fc63 	lsr	x3, x3, #36
  400fdc:	9bb87ce0 	umull	x0, w7, w24
  400fe0:	9bb87ca1 	umull	x1, w5, w24
  400fe4:	0b030863 	add	w3, w3, w3, lsl #2
  400fe8:	d364fc42 	lsr	x2, x2, #36
  400fec:	d364fc00 	lsr	x0, x0, #36
  400ff0:	4b030884 	sub	w4, w4, w3, lsl #2
  400ff4:	0b020842 	add	w2, w2, w2, lsl #2
  400ff8:	d364fc21 	lsr	x1, x1, #36
  400ffc:	0b000800 	add	w0, w0, w0, lsl #2
  401000:	4b020903 	sub	w3, w8, w2, lsl #2
  401004:	0b010821 	add	w1, w1, w1, lsl #2
  401008:	b8647aa4 	ldr	w4, [x21, x4, lsl #2]
  40100c:	4b0108a2 	sub	w2, w5, w1, lsl #2
  401010:	4b0008e1 	sub	w1, w7, w0, lsl #2
  401014:	b8637aa0 	ldr	w0, [x21, x3, lsl #2]
  401018:	293e00c4 	stp	w4, w0, [x6, #-16]
  40101c:	0b050364 	add	w4, w27, w5
  401020:	b8627aa2 	ldr	w2, [x21, x2, lsl #2]
  401024:	b8617aa0 	ldr	w0, [x21, x1, lsl #2]
  401028:	293f08c0 	stp	w0, w2, [x6, #-8]
  40102c:	eb1600df 	cmp	x6, x22
  401030:	54fffc81 	b.ne	400fc0 <main+0x8c0>  // b.any
  401034:	b940fbe0 	ldr	w0, [sp, #248]
  401038:	b8605aa3 	ldr	w3, [x21, w0, uxtw #2]
  40103c:	b940ffe0 	ldr	w0, [sp, #252]
  401040:	b8605aa7 	ldr	w7, [x21, w0, uxtw #2]
  401044:	b94103e0 	ldr	w0, [sp, #256]
  401048:	b8605aa6 	ldr	w6, [x21, w0, uxtw #2]
  40104c:	b94107e0 	ldr	w0, [sp, #260]
  401050:	b8605aa4 	ldr	w4, [x21, w0, uxtw #2]
  401054:	b940f7e0 	ldr	w0, [sp, #244]
  401058:	b8605aa8 	ldr	w8, [x21, w0, uxtw #2]
  40105c:	17fffe39 	b	400940 <main+0x240>
  401060:	d2826c00 	mov	x0, #0x1360                	// #4960
  401064:	2a1803e4 	mov	w4, w24
  401068:	b940f3e1 	ldr	w1, [sp, #240]
  40106c:	8b2063f8 	add	x24, sp, x0
  401070:	f94077e0 	ldr	x0, [sp, #232]
  401074:	2a1603e3 	mov	w3, w22
  401078:	2a1a03e2 	mov	w2, w26
  40107c:	913a83fa 	add	x26, sp, #0xea0
  401080:	52800016 	mov	w22, #0x0                   	// #0
  401084:	97fffd93 	bl	4006d0 <printf@plt>
  401088:	90000006 	adrp	x6, 401000 <main+0x900>
  40108c:	912840db 	add	x27, x6, #0xa10
  401090:	b9400304 	ldr	w4, [x24]
  401094:	2a1603e1 	mov	w1, w22
  401098:	b9400343 	ldr	w3, [x26]
  40109c:	aa1b03e0 	mov	x0, x27
  4010a0:	52800002 	mov	w2, #0x0                   	// #0
  4010a4:	6b04007f 	cmp	w3, w4
  4010a8:	54000040 	b.eq	4010b0 <main+0x9b0>  // b.none
  4010ac:	97fffd89 	bl	4006d0 <printf@plt>
  4010b0:	b9400704 	ldr	w4, [x24, #4]
  4010b4:	2a1603e1 	mov	w1, w22
  4010b8:	b9400743 	ldr	w3, [x26, #4]
  4010bc:	aa1b03e0 	mov	x0, x27
  4010c0:	52800022 	mov	w2, #0x1                   	// #1
  4010c4:	6b04007f 	cmp	w3, w4
  4010c8:	54000040 	b.eq	4010d0 <main+0x9d0>  // b.none
  4010cc:	97fffd81 	bl	4006d0 <printf@plt>
  4010d0:	b9400b04 	ldr	w4, [x24, #8]
  4010d4:	2a1603e1 	mov	w1, w22
  4010d8:	b9400b43 	ldr	w3, [x26, #8]
  4010dc:	aa1b03e0 	mov	x0, x27
  4010e0:	52800042 	mov	w2, #0x2                   	// #2
  4010e4:	6b04007f 	cmp	w3, w4
  4010e8:	54000040 	b.eq	4010f0 <main+0x9f0>  // b.none
  4010ec:	97fffd79 	bl	4006d0 <printf@plt>
  4010f0:	b9400f04 	ldr	w4, [x24, #12]
  4010f4:	2a1603e1 	mov	w1, w22
  4010f8:	b9400f43 	ldr	w3, [x26, #12]
  4010fc:	aa1b03e0 	mov	x0, x27
  401100:	52800062 	mov	w2, #0x3                   	// #3
  401104:	6b04007f 	cmp	w3, w4
  401108:	54000040 	b.eq	401110 <main+0xa10>  // b.none
  40110c:	97fffd71 	bl	4006d0 <printf@plt>
  401110:	110006d6 	add	w22, w22, #0x1
  401114:	9100435a 	add	x26, x26, #0x10
  401118:	91004318 	add	x24, x24, #0x10
  40111c:	710082df 	cmp	w22, #0x20
  401120:	54fffb81 	b.ne	401090 <main+0x990>  // b.any
  401124:	17ffff30 	b	400de4 <main+0x6e4>
  401128:	b940a3e1 	ldr	w1, [sp, #160]
  40112c:	11000421 	add	w1, w1, #0x1
  401130:	b900a3e1 	str	w1, [sp, #160]
  401134:	6b00037f 	cmp	w27, w0
  401138:	54ffe521 	b.ne	400ddc <main+0x6dc>  // b.any
  40113c:	aa1503e1 	mov	x1, x21
  401140:	913083e0 	add	x0, sp, #0xc20
  401144:	d2809802 	mov	x2, #0x4c0                 	// #1216
  401148:	97fffd4e 	bl	400680 <memcmp@plt>
  40114c:	35ffe480 	cbnz	w0, 400ddc <main+0x6dc>
  401150:	911583e1 	add	x1, sp, #0x560
  401154:	910d83e0 	add	x0, sp, #0x360
  401158:	d2804002 	mov	x2, #0x200                 	// #512
  40115c:	97fffd49 	bl	400680 <memcmp@plt>
  401160:	34ffe440 	cbz	w0, 400de8 <main+0x6e8>
  401164:	17ffff1e 	b	400ddc <main+0x6dc>
  401168:	90000001 	adrp	x1, 401000 <main+0x900>
  40116c:	90000000 	adrp	x0, 401000 <main+0x900>
  401170:	912a8021 	add	x1, x1, #0xaa0
  401174:	912a4000 	add	x0, x0, #0xa90
  401178:	97fffd56 	bl	4006d0 <printf@plt>
  40117c:	52800000 	mov	w0, #0x0                   	// #0
  401180:	17ffff38 	b	400e60 <main+0x760>
  401184:	d503201f 	nop
  401188:	d503201f 	nop
  40118c:	d503201f 	nop
  401190:	d503201f 	nop
  401194:	d503201f 	nop
  401198:	d503201f 	nop
  40119c:	d503201f 	nop
  4011a0:	d503201f 	nop
  4011a4:	d503201f 	nop
  4011a8:	d503201f 	nop
  4011ac:	d503201f 	nop
  4011b0:	d503201f 	nop
  4011b4:	d503201f 	nop
  4011b8:	d503201f 	nop
  4011bc:	d503201f 	nop

00000000004011c0 <_start>:
  4011c0:	d503201f 	nop
  4011c4:	d280001d 	mov	x29, #0x0                   	// #0
  4011c8:	d280001e 	mov	x30, #0x0                   	// #0
  4011cc:	aa0003e5 	mov	x5, x0
  4011d0:	f94003e1 	ldr	x1, [sp]
  4011d4:	910023e2 	add	x2, sp, #0x8
  4011d8:	910003e6 	mov	x6, sp
  4011dc:	90000000 	adrp	x0, 401000 <main+0x900>
  4011e0:	9107d000 	add	x0, x0, #0x1f4
  4011e4:	d2800003 	mov	x3, #0x0                   	// #0
  4011e8:	d2800004 	mov	x4, #0x0                   	// #0
  4011ec:	97fffd2d 	bl	4006a0 <__libc_start_main@plt>
  4011f0:	97fffd30 	bl	4006b0 <abort@plt>

00000000004011f4 <__wrap_main>:
  4011f4:	d503201f 	nop
  4011f8:	17fffd42 	b	400700 <main>
  4011fc:	d503201f 	nop

0000000000401200 <_dl_relocate_static_pie>:
  401200:	d65f03c0 	ret

0000000000401204 <call_weak_fn>:
  401204:	d00000e0 	adrp	x0, 41f000 <__abi_tag+0x1d278>
  401208:	f947ec00 	ldr	x0, [x0, #4056]
  40120c:	b4000040 	cbz	x0, 401214 <call_weak_fn+0x10>
  401210:	17fffd2c 	b	4006c0 <__gmon_start__@plt>
  401214:	d65f03c0 	ret
  401218:	d503201f 	nop
  40121c:	d503201f 	nop

0000000000401220 <deregister_tm_clones>:
  401220:	f00000e0 	adrp	x0, 420000 <memcpy@GLIBC_2.17>
  401224:	91012001 	add	x1, x0, #0x48
  401228:	f00000e0 	adrp	x0, 420000 <memcpy@GLIBC_2.17>
  40122c:	91012000 	add	x0, x0, #0x48
  401230:	eb00003f 	cmp	x1, x0
  401234:	540000c0 	b.eq	40124c <deregister_tm_clones+0x2c>  // b.none
  401238:	d00000e1 	adrp	x1, 41f000 <__abi_tag+0x1d278>
  40123c:	f947e821 	ldr	x1, [x1, #4048]
  401240:	b4000061 	cbz	x1, 40124c <deregister_tm_clones+0x2c>
  401244:	aa0103f0 	mov	x16, x1
  401248:	d61f0200 	br	x16
  40124c:	d65f03c0 	ret

0000000000401250 <register_tm_clones>:
  401250:	f00000e0 	adrp	x0, 420000 <memcpy@GLIBC_2.17>
  401254:	91012001 	add	x1, x0, #0x48
  401258:	f00000e0 	adrp	x0, 420000 <memcpy@GLIBC_2.17>
  40125c:	91012000 	add	x0, x0, #0x48
  401260:	cb000021 	sub	x1, x1, x0
  401264:	d37ffc22 	lsr	x2, x1, #63
  401268:	8b810c41 	add	x1, x2, x1, asr #3
  40126c:	9341fc21 	asr	x1, x1, #1
  401270:	b40000c1 	cbz	x1, 401288 <register_tm_clones+0x38>
  401274:	d00000e2 	adrp	x2, 41f000 <__abi_tag+0x1d278>
  401278:	f947f042 	ldr	x2, [x2, #4064]
  40127c:	b4000062 	cbz	x2, 401288 <register_tm_clones+0x38>
  401280:	aa0203f0 	mov	x16, x2
  401284:	d61f0200 	br	x16
  401288:	d65f03c0 	ret

000000000040128c <__do_global_dtors_aux>:
  40128c:	d503233f 	paciasp
  401290:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
  401294:	910003fd 	mov	x29, sp
  401298:	f9000bf3 	str	x19, [sp, #16]
  40129c:	f00000f3 	adrp	x19, 420000 <memcpy@GLIBC_2.17>
  4012a0:	39416260 	ldrb	w0, [x19, #88]
  4012a4:	37000080 	tbnz	w0, #0, 4012b4 <__do_global_dtors_aux+0x28>
  4012a8:	97ffffde 	bl	401220 <deregister_tm_clones>
  4012ac:	52800020 	mov	w0, #0x1                   	// #1
  4012b0:	39016260 	strb	w0, [x19, #88]
  4012b4:	f9400bf3 	ldr	x19, [sp, #16]
  4012b8:	a8c27bfd 	ldp	x29, x30, [sp], #32
  4012bc:	d50323bf 	autiasp
  4012c0:	d65f03c0 	ret

00000000004012c4 <frame_dummy>:
  4012c4:	d503245f 	bti	c
  4012c8:	17ffffe2 	b	401250 <register_tm_clones>
  4012cc:	d503201f 	nop
  4012d0:	d503201f 	nop
  4012d4:	d503201f 	nop
  4012d8:	d503201f 	nop
  4012dc:	d503201f 	nop

00000000004012e0 <before(Mips2C::ExecutionContext*)>:
  4012e0:	d503233f 	paciasp
  4012e4:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  4012e8:	910003fd 	mov	x29, sp
  4012ec:	f940a002 	ldr	x2, [x0, #320]
  4012f0:	f2400c5f 	tst	x2, #0xf
  4012f4:	54000dc1 	b.ne	4014ac <before(Mips2C::ExecutionContext*)+0x1cc>  // b.any
  4012f8:	f00000e3 	adrp	x3, 420000 <memcpy@GLIBC_2.17>
  4012fc:	91100001 	add	x1, x0, #0x400
  401300:	f9403064 	ldr	x4, [x3, #96]
  401304:	8b224082 	add	x2, x4, w2, uxtw
  401308:	3dc00058 	ldr	q24, [x2]
  40130c:	3c900038 	stur	q24, [x1, #-256]
  401310:	a9411443 	ldp	x3, x5, [x2, #16]
  401314:	a9311423 	stp	x3, x5, [x1, #-240]
  401318:	3dc0085e 	ldr	q30, [x2, #32]
  40131c:	3c92003e 	stur	q30, [x1, #-224]
  401320:	f940a802 	ldr	x2, [x0, #336]
  401324:	f2400c5f 	tst	x2, #0xf
  401328:	54000c21 	b.ne	4014ac <before(Mips2C::ExecutionContext*)+0x1cc>  // b.any
  40132c:	92407c42 	and	x2, x2, #0xffffffff
  401330:	91004043 	add	x3, x2, #0x10
  401334:	8b020082 	add	x2, x4, x2
  401338:	8b030087 	add	x7, x4, x3
  40133c:	fc63689f 	ldr	d31, [x4, x3]
  401340:	f94004e3 	ldr	x3, [x7, #8]
  401344:	9e6603e6 	fmov	x6, d31
  401348:	7f6007fb 	ushr	d27, d31, #32
  40134c:	0ebf1ffd 	mov	v29.8b, v31.8b
  401350:	a9330c26 	stp	x6, x3, [x1, #-208]
  401354:	53007c63 	lsr	w3, w3, #0
  401358:	6e0c077d 	mov	v29.s[1], v27.s[0]
  40135c:	3dc0085c 	ldr	q28, [x2, #32]
  401360:	3c94003c 	stur	q28, [x1, #-192]
  401364:	9e67007b 	fmov	d27, x3
  401368:	3dc00c5a 	ldr	q26, [x2, #48]
  40136c:	3c95003a 	stur	q26, [x1, #-176]
  401370:	3dc01056 	ldr	q22, [x2, #64]
  401374:	3c960036 	stur	q22, [x1, #-160]
  401378:	bd43881f 	ldr	s31, [x0, #904]
  40137c:	b9406043 	ldr	w3, [x2, #96]
  401380:	b9020003 	str	w3, [x0, #512]
  401384:	4f9f92d6 	fmul	v22.4s, v22.4s, v31.s[0]
  401388:	bd43841f 	ldr	s31, [x0, #900]
  40138c:	93407c62 	sxtw	x2, w3
  401390:	f9001802 	str	x2, [x0, #48]
  401394:	bd438c15 	ldr	s21, [x0, #908]
  401398:	5e1406d9 	mov	s25, v22.s[2]
  40139c:	3d80d816 	str	q22, [x0, #864]
  4013a0:	0e36d7bd 	fadd	v29.2s, v29.2s, v22.2s
  4013a4:	1e392b7b 	fadd	s27, s27, s25
  4013a8:	fd01981d 	str	d29, [x0, #816]
  4013ac:	bd03381b 	str	s27, [x0, #824]
  4013b0:	340002c3 	cbz	w3, 401408 <before(Mips2C::ExecutionContext*)+0x128>
  4013b4:	f9401c06 	ldr	x6, [x0, #56]
  4013b8:	1e2e1017 	fmov	s23, #1.000000000000000000e+00
  4013bc:	53007c48 	lsr	w8, w2, #0
  4013c0:	9e670056 	fmov	d22, x2
  4013c4:	9e670119 	fmov	d25, x8
  4013c8:	a9371822 	stp	x2, x6, [x1, #-144]
  4013cc:	7f6006d6 	ushr	d22, d22, #32
  4013d0:	1e393af4 	fsub	s20, s23, s25
  4013d4:	53007cc6 	lsr	w6, w6, #0
  4013d8:	4e0c1cd9 	mov	v25.s[1], w6
  4013dc:	6e0c0696 	mov	v22.s[1], v20.s[0]
  4013e0:	4e963b39 	zip1	v25.4s, v25.4s, v22.4s
  4013e4:	4f959339 	fmul	v25.4s, v25.4s, v21.s[0]
  4013e8:	5e1c0736 	mov	s22, v25.s[3]
  4013ec:	3d80dc19 	str	q25, [x0, #880]
  4013f0:	1e363af9 	fsub	s25, s23, s22
  4013f4:	0f9993bd 	fmul	v29.2s, v29.2s, v25.s[0]
  4013f8:	1e390b7b 	fmul	s27, s27, s25
  4013fc:	bd037c19 	str	s25, [x0, #892]
  401400:	fd01981d 	str	d29, [x0, #816]
  401404:	bd03381b 	str	s27, [x0, #824]
  401408:	3dc0cc19 	ldr	q25, [x0, #816]
  40140c:	9e6700bd 	fmov	d29, x5
  401410:	4f9f935a 	fmul	v26.4s, v26.4s, v31.s[0]
  401414:	4f9f939c 	fmul	v28.4s, v28.4s, v31.s[0]
  401418:	7f6007bb 	ushr	d27, d29, #32
  40141c:	4f9f933f 	fmul	v31.4s, v25.4s, v31.s[0]
  401420:	4e3ed75e 	fadd	v30.4s, v26.4s, v30.4s
  401424:	3d80ec1a 	str	q26, [x0, #944]
  401428:	5e1c079d 	mov	s29, v28.s[3]
  40142c:	ad1cf01f 	stp	q31, q28, [x0, #912]
  401430:	4ea0ebdc 	fcmlt	v28.4s, v30.4s, #0.0
  401434:	4e38d7ff 	fadd	v31.4s, v31.4s, v24.4s
  401438:	1e3b2bbd 	fadd	s29, s29, s27
  40143c:	4e7c1fde 	bic	v30.16b, v30.16b, v28.16b
  401440:	3d80c01f 	str	q31, [x0, #768]
  401444:	bd031c1d 	str	s29, [x0, #796]
  401448:	3d80c81e 	str	q30, [x0, #800]
  40144c:	3d8000f9 	str	q25, [x7]
  401450:	f940a002 	ldr	x2, [x0, #320]
  401454:	f2400c5f 	tst	x2, #0xf
  401458:	540003e1 	b.ne	4014d4 <before(Mips2C::ExecutionContext*)+0x1f4>  // b.any
  40145c:	8b224082 	add	x2, x4, w2, uxtw
  401460:	a9701c26 	ldp	x6, x7, [x1, #-256]
  401464:	a9001c46 	stp	x6, x7, [x2]
  401468:	f940a002 	ldr	x2, [x0, #320]
  40146c:	f2400c5f 	tst	x2, #0xf
  401470:	54000321 	b.ne	4014d4 <before(Mips2C::ExecutionContext*)+0x1f4>  // b.any
  401474:	8b224082 	add	x2, x4, w2, uxtw
  401478:	a9711c26 	ldp	x6, x7, [x1, #-240]
  40147c:	a9011c46 	stp	x6, x7, [x2, #16]
  401480:	f940a000 	ldr	x0, [x0, #320]
  401484:	f2400c1f 	tst	x0, #0xf
  401488:	54000261 	b.ne	4014d4 <before(Mips2C::ExecutionContext*)+0x1f4>  // b.any
  40148c:	8b204082 	add	x2, x4, w0, uxtw
  401490:	7100007f 	cmp	w3, #0x0
  401494:	a9721424 	ldp	x4, x5, [x1, #-224]
  401498:	1a9f17e0 	cset	w0, eq	// eq = none
  40149c:	a9021444 	stp	x4, x5, [x2, #32]
  4014a0:	a8c17bfd 	ldp	x29, x30, [sp], #16
  4014a4:	d50323bf 	autiasp
  4014a8:	d65f03c0 	ret
  4014ac:	90000004 	adrp	x4, 401000 <main+0x900>
  4014b0:	90000003 	adrp	x3, 401000 <main+0x900>
  4014b4:	90000001 	adrp	x1, 401000 <main+0x900>
  4014b8:	90000000 	adrp	x0, 401000 <main+0x900>
  4014bc:	91260084 	add	x4, x4, #0x980
  4014c0:	91204063 	add	x3, x3, #0x810
  4014c4:	91212021 	add	x1, x1, #0x848
  4014c8:	9121a000 	add	x0, x0, #0x868
  4014cc:	52802b02 	mov	w2, #0x158                 	// #344
  4014d0:	940000b4 	bl	4017a0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  4014d4:	90000004 	adrp	x4, 401000 <main+0x900>
  4014d8:	90000003 	adrp	x3, 401000 <main+0x900>
  4014dc:	90000001 	adrp	x1, 401000 <main+0x900>
  4014e0:	90000000 	adrp	x0, 401000 <main+0x900>
  4014e4:	91260084 	add	x4, x4, #0x980
  4014e8:	91226063 	add	x3, x3, #0x898
  4014ec:	91212021 	add	x1, x1, #0x848
  4014f0:	91234000 	add	x0, x0, #0x8d0
  4014f4:	52803802 	mov	w2, #0x1c0                 	// #448
  4014f8:	940000aa 	bl	4017a0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  4014fc:	d503201f 	nop

0000000000401500 <after(Mips2C::ExecutionContext*)>:
  401500:	d503233f 	paciasp
  401504:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  401508:	910003fd 	mov	x29, sp
  40150c:	b9414002 	ldr	w2, [x0, #320]
  401510:	f2400c5f 	tst	x2, #0xf
  401514:	54001281 	b.ne	401764 <after(Mips2C::ExecutionContext*)+0x264>  // b.any
  401518:	f00000e1 	adrp	x1, 420000 <memcpy@GLIBC_2.17>
  40151c:	b9415004 	ldr	w4, [x0, #336]
  401520:	f9403025 	ldr	x5, [x1, #96]
  401524:	8b2240a2 	add	x2, x5, w2, uxtw
  401528:	a9413051 	ldp	x17, x12, [x2, #16]
  40152c:	3dc0005a 	ldr	q26, [x2]
  401530:	aa0c03f0 	mov	x16, x12
  401534:	f2400c9f 	tst	x4, #0xf
  401538:	54001021 	b.ne	40173c <after(Mips2C::ExecutionContext*)+0x23c>  // b.any
  40153c:	f940a80f 	ldr	x15, [x0, #336]
  401540:	8b2440a4 	add	x4, x5, w4, uxtw
  401544:	91100001 	add	x1, x0, #0x400
  401548:	3dc0085e 	ldr	q30, [x2, #32]
  40154c:	8b2f40ae 	add	x14, x5, w15, uxtw
  401550:	a9411887 	ldp	x7, x6, [x4, #16]
  401554:	b94061ca 	ldr	w10, [x14, #96]
  401558:	3dc0109c 	ldr	q28, [x4, #64]
  40155c:	ad416096 	ldp	q22, q24, [x4, #32]
  401560:	9e6700ff 	fmov	d31, x7
  401564:	93407d47 	sxtw	x7, w10
  401568:	f9001807 	str	x7, [x0, #48]
  40156c:	b902000a 	str	w10, [x0, #512]
  401570:	53007ccb 	lsr	w11, w6, #0
  401574:	9e67017d 	fmov	d29, x11
  401578:	aa0603e3 	mov	x3, x6
  40157c:	a9782c24 	ldp	x4, x11, [x1, #-128]
  401580:	93407d66 	sxtw	x6, w11
  401584:	9e6700db 	fmov	d27, x6
  401588:	4f9b939c 	fmul	v28.4s, v28.4s, v27.s[0]
  40158c:	5e14079b 	mov	s27, v28.s[2]
  401590:	0e3fd79f 	fadd	v31.2s, v28.2s, v31.2s
  401594:	9e660386 	fmov	x6, d28
  401598:	9eae0387 	fmov	x7, v28.d[1]
  40159c:	1e3b2bbc 	fadd	s28, s29, s27
  4015a0:	4e083fe2 	mov	x2, v31.d[0]
  4015a4:	1e26038d 	fmov	w13, s28
  4015a8:	b3407da3 	bfxil	x3, x13, #0, #32
  4015ac:	3400038a 	cbz	w10, 40161c <after(Mips2C::ExecutionContext*)+0x11c>
  4015b0:	a943480d 	ldp	x13, x18, [x0, #48]
  4015b4:	1e2e101b 	fmov	s27, #1.000000000000000000e+00
  4015b8:	a9330c22 	stp	x2, x3, [x1, #-208]
  4015bc:	d360fd6b 	lsr	x11, x11, #32
  4015c0:	1e27017d 	fmov	s29, w11
  4015c4:	aa0d03e8 	mov	x8, x13
  4015c8:	53007dad 	lsr	w13, w13, #0
  4015cc:	9e6701b9 	fmov	d25, x13
  4015d0:	aa1203e9 	mov	x9, x18
  4015d4:	1e393b79 	fsub	s25, s27, s25
  4015d8:	9e660322 	fmov	x2, d25
  4015dc:	9e670119 	fmov	d25, x8
  4015e0:	b3607c49 	bfi	x9, x2, #32, #32
  4015e4:	4e181d39 	mov	v25.d[1], x9
  4015e8:	4f9d933d 	fmul	v29.4s, v25.4s, v29.s[0]
  4015ec:	5e1c07b9 	mov	s25, v29.s[3]
  4015f0:	9e6603a8 	fmov	x8, d29
  4015f4:	9eae03a9 	fmov	x9, v29.d[1]
  4015f8:	1e393b7d 	fsub	s29, s27, s25
  4015fc:	1e2603a2 	fmov	w2, s29
  401600:	0f9d93ff 	fmul	v31.2s, v31.2s, v29.s[0]
  401604:	1e3c0bbc 	fmul	s28, s29, s28
  401608:	b3607c49 	bfi	x9, x2, #32, #32
  40160c:	a9372428 	stp	x8, x9, [x1, #-144]
  401610:	fd01981f 	str	d31, [x0, #816]
  401614:	bd03381c 	str	s28, [x0, #824]
  401618:	a9730c22 	ldp	x2, x3, [x1, #-208]
  40161c:	d360fc84 	lsr	x4, x4, #32
  401620:	1e27009f 	fmov	s31, w4
  401624:	9e67019d 	fmov	d29, x12
  401628:	a9361c26 	stp	x6, x7, [x1, #-160]
  40162c:	7f6007bd 	ushr	d29, d29, #32
  401630:	4f9f931c 	fmul	v28.4s, v24.4s, v31.s[0]
  401634:	a9330c22 	stp	x2, x3, [x1, #-208]
  401638:	4f9f92db 	fmul	v27.4s, v22.4s, v31.s[0]
  40163c:	ad3a6036 	stp	q22, q24, [x1, #-192]
  401640:	4e3ed79e 	fadd	v30.4s, v28.4s, v30.4s
  401644:	9e66038c 	fmov	x12, d28
  401648:	9eae038d 	fmov	x13, v28.d[1]
  40164c:	9e660366 	fmov	x6, d27
  401650:	9eae0367 	fmov	x7, v27.d[1]
  401654:	5e1c077c 	mov	s28, v27.s[3]
  401658:	9e67005b 	fmov	d27, x2
  40165c:	4e181c7b 	mov	v27.d[1], x3
  401660:	1e3d2b9d 	fadd	s29, s28, s29
  401664:	4f9f937f 	fmul	v31.4s, v27.4s, v31.s[0]
  401668:	4ea0ebdb 	fcmlt	v27.4s, v30.4s, #0.0
  40166c:	9e6603a4 	fmov	x4, d29
  401670:	4e3ad7fa 	fadd	v26.4s, v31.4s, v26.4s
  401674:	4e7b1fde 	bic	v30.16b, v30.16b, v27.16b
  401678:	b3607c90 	bfi	x16, x4, #32, #32
  40167c:	a9314031 	stp	x17, x16, [x1, #-240]
  401680:	9e6603e2 	fmov	x2, d31
  401684:	3c90003a 	stur	q26, [x1, #-256]
  401688:	9eae03e3 	fmov	x3, v31.d[1]
  40168c:	3c92003e 	stur	q30, [x1, #-224]
  401690:	350003ea 	cbnz	w10, 40170c <after(Mips2C::ExecutionContext*)+0x20c>
  401694:	a9390c22 	stp	x2, x3, [x1, #-112]
  401698:	a93a1c26 	stp	x6, x7, [x1, #-96]
  40169c:	a93b342c 	stp	x12, x13, [x1, #-80]
  4016a0:	f2400dff 	tst	x15, #0xf
  4016a4:	54000381 	b.ne	401714 <after(Mips2C::ExecutionContext*)+0x214>  // b.any
  4016a8:	a9730c22 	ldp	x2, x3, [x1, #-208]
  4016ac:	a9010dc2 	stp	x2, x3, [x14, #16]
  4016b0:	f940a002 	ldr	x2, [x0, #320]
  4016b4:	f2400c5f 	tst	x2, #0xf
  4016b8:	540002e1 	b.ne	401714 <after(Mips2C::ExecutionContext*)+0x214>  // b.any
  4016bc:	8b2240a2 	add	x2, x5, w2, uxtw
  4016c0:	a9701c26 	ldp	x6, x7, [x1, #-256]
  4016c4:	a9001c46 	stp	x6, x7, [x2]
  4016c8:	f940a002 	ldr	x2, [x0, #320]
  4016cc:	f2400c5f 	tst	x2, #0xf
  4016d0:	54000221 	b.ne	401714 <after(Mips2C::ExecutionContext*)+0x214>  // b.any
  4016d4:	8b2240a2 	add	x2, x5, w2, uxtw
  4016d8:	a9711c26 	ldp	x6, x7, [x1, #-240]
  4016dc:	a9011c46 	stp	x6, x7, [x2, #16]
  4016e0:	f940a000 	ldr	x0, [x0, #320]
  4016e4:	f2400c1f 	tst	x0, #0xf
  4016e8:	54000161 	b.ne	401714 <after(Mips2C::ExecutionContext*)+0x214>  // b.any
  4016ec:	8b2040a2 	add	x2, x5, w0, uxtw
  4016f0:	7100015f 	cmp	w10, #0x0
  4016f4:	a9721424 	ldp	x4, x5, [x1, #-224]
  4016f8:	1a9f17e0 	cset	w0, eq	// eq = none
  4016fc:	a9021444 	stp	x4, x5, [x2, #32]
  401700:	a8c17bfd 	ldp	x29, x30, [sp], #16
  401704:	d50323bf 	autiasp
  401708:	d65f03c0 	ret
  40170c:	a9372428 	stp	x8, x9, [x1, #-144]
  401710:	17ffffe1 	b	401694 <after(Mips2C::ExecutionContext*)+0x194>
  401714:	90000004 	adrp	x4, 401000 <main+0x900>
  401718:	90000003 	adrp	x3, 401000 <main+0x900>
  40171c:	90000001 	adrp	x1, 401000 <main+0x900>
  401720:	90000000 	adrp	x0, 401000 <main+0x900>
  401724:	91260084 	add	x4, x4, #0x980
  401728:	91226063 	add	x3, x3, #0x898
  40172c:	91212021 	add	x1, x1, #0x848
  401730:	91234000 	add	x0, x0, #0x8d0
  401734:	52803802 	mov	w2, #0x1c0                 	// #448
  401738:	9400001a 	bl	4017a0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  40173c:	90000004 	adrp	x4, 401000 <main+0x900>
  401740:	90000003 	adrp	x3, 401000 <main+0x900>
  401744:	90000001 	adrp	x1, 401000 <main+0x900>
  401748:	90000000 	adrp	x0, 401000 <main+0x900>
  40174c:	91260084 	add	x4, x4, #0x980
  401750:	9123e063 	add	x3, x3, #0x8f8
  401754:	91248021 	add	x1, x1, #0x920
  401758:	9126e000 	add	x0, x0, #0x9b8
  40175c:	52800762 	mov	w2, #0x3b                  	// #59
  401760:	94000010 	bl	4017a0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  401764:	90000004 	adrp	x4, 401000 <main+0x900>
  401768:	90000003 	adrp	x3, 401000 <main+0x900>
  40176c:	90000001 	adrp	x1, 401000 <main+0x900>
  401770:	90000000 	adrp	x0, 401000 <main+0x900>
  401774:	91260084 	add	x4, x4, #0x980
  401778:	9123e063 	add	x3, x3, #0x8f8
  40177c:	91248021 	add	x1, x1, #0x920
  401780:	91262000 	add	x0, x0, #0x988
  401784:	528006a2 	mov	w2, #0x35                  	// #53
  401788:	94000006 	bl	4017a0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
  40178c:	d503201f 	nop
  401790:	d503201f 	nop
  401794:	d503201f 	nop
  401798:	d503201f 	nop
  40179c:	d503201f 	nop

00000000004017a0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>:
  4017a0:	d503245f 	bti	c
  4017a4:	f00000e6 	adrp	x6, 420000 <memcpy@GLIBC_2.17>
  4017a8:	d503233f 	paciasp
  4017ac:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  4017b0:	2a0203e7 	mov	w7, w2
  4017b4:	910003fd 	mov	x29, sp
  4017b8:	aa0003e2 	mov	x2, x0
  4017bc:	f94028c0 	ldr	x0, [x6, #80]
  4017c0:	aa0303e5 	mov	x5, x3
  4017c4:	aa0403e6 	mov	x6, x4
  4017c8:	aa0103e3 	mov	x3, x1
  4017cc:	2a0703e4 	mov	w4, w7
  4017d0:	90000001 	adrp	x1, 401000 <main+0x900>
  4017d4:	912aa021 	add	x1, x1, #0xaa8
  4017d8:	97fffba6 	bl	400670 <fprintf@plt>
  4017dc:	97fffbb5 	bl	4006b0 <abort@plt>

Disassembly of section .fini:

00000000004017e0 <_fini>:
  4017e0:	d503201f 	nop
  4017e4:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
  4017e8:	910003fd 	mov	x29, sp
  4017ec:	a8c17bfd 	ldp	x29, x30, [sp], #16
  4017f0:	d65f03c0 	ret
