
.autoport/reports/perf-mips2c-neon/notes/attempt8/nan-order-arm-clang:     file format elf64-littleaarch64


Disassembly of section .text:

00000000000107c0 <_start>:
   107c0:	d503201f 	nop
   107c4:	d280001d 	mov	x29, #0x0                   	// #0
   107c8:	d280001e 	mov	x30, #0x0                   	// #0
   107cc:	aa0003e5 	mov	x5, x0
   107d0:	f94003e1 	ldr	x1, [sp]
   107d4:	910023e2 	add	x2, sp, #0x8
   107d8:	910003e6 	mov	x6, sp
   107dc:	d503201f 	nop
   107e0:	100007e0 	adr	x0, 108dc <main>
   107e4:	d2800003 	mov	x3, #0x0                   	// #0
   107e8:	d2800004 	mov	x4, #0x0                   	// #0
   107ec:	940000dd 	bl	10b60 <__libc_start_main@plt>
   107f0:	940000d8 	bl	10b50 <abort@plt>

00000000000107f4 <call_weak_fn>:
   107f4:	90000080 	adrp	x0, 20000 <printf@plt+0xf470>
   107f8:	f946c400 	ldr	x0, [x0, #3464]
   107fc:	b4000040 	cbz	x0, 10804 <call_weak_fn+0x10>
   10800:	140000dc 	b	10b70 <__gmon_start__@plt>
   10804:	d65f03c0 	ret
	...

0000000000010810 <deregister_tm_clones>:
   10810:	d503201f 	nop
   10814:	10102d20 	adr	x0, 30db8 <__TMC_END__>
   10818:	d503201f 	nop
   1081c:	10102ce1 	adr	x1, 30db8 <__TMC_END__>
   10820:	eb00003f 	cmp	x1, x0
   10824:	540000c0 	b.eq	1083c <deregister_tm_clones+0x2c>  // b.none
   10828:	90000081 	adrp	x1, 20000 <printf@plt+0xf470>
   1082c:	f946c821 	ldr	x1, [x1, #3472]
   10830:	b4000061 	cbz	x1, 1083c <deregister_tm_clones+0x2c>
   10834:	aa0103f0 	mov	x16, x1
   10838:	d61f0200 	br	x16
   1083c:	d65f03c0 	ret

0000000000010840 <register_tm_clones>:
   10840:	d503201f 	nop
   10844:	10102ba0 	adr	x0, 30db8 <__TMC_END__>
   10848:	d503201f 	nop
   1084c:	10102b61 	adr	x1, 30db8 <__TMC_END__>
   10850:	cb000021 	sub	x1, x1, x0
   10854:	d37ffc22 	lsr	x2, x1, #63
   10858:	8b810c41 	add	x1, x2, x1, asr #3
   1085c:	9341fc21 	asr	x1, x1, #1
   10860:	b40000c1 	cbz	x1, 10878 <register_tm_clones+0x38>
   10864:	90000082 	adrp	x2, 20000 <printf@plt+0xf470>
   10868:	f946cc42 	ldr	x2, [x2, #3480]
   1086c:	b4000062 	cbz	x2, 10878 <register_tm_clones+0x38>
   10870:	aa0203f0 	mov	x16, x2
   10874:	d61f0200 	br	x16
   10878:	d65f03c0 	ret
   1087c:	d503201f 	nop

0000000000010880 <__do_global_dtors_aux>:
   10880:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
   10884:	910003fd 	mov	x29, sp
   10888:	f9000bf3 	str	x19, [sp, #16]
   1088c:	90000113 	adrp	x19, 30000 <_DYNAMIC+0xf450>
   10890:	3977e260 	ldrb	w0, [x19, #3576]
   10894:	35000140 	cbnz	w0, 108bc <__do_global_dtors_aux+0x3c>
   10898:	90000080 	adrp	x0, 20000 <printf@plt+0xf470>
   1089c:	f946d000 	ldr	x0, [x0, #3488]
   108a0:	b4000080 	cbz	x0, 108b0 <__do_global_dtors_aux+0x30>
   108a4:	90000100 	adrp	x0, 30000 <_DYNAMIC+0xf450>
   108a8:	f946d800 	ldr	x0, [x0, #3504]
   108ac:	940000b5 	bl	10b80 <__cxa_finalize@plt>
   108b0:	97ffffd8 	bl	10810 <deregister_tm_clones>
   108b4:	52800020 	mov	w0, #0x1                   	// #1
   108b8:	3937e260 	strb	w0, [x19, #3576]
   108bc:	f9400bf3 	ldr	x19, [sp, #16]
   108c0:	a8c27bfd 	ldp	x29, x30, [sp], #32
   108c4:	d65f03c0 	ret
   108c8:	d503201f 	nop
   108cc:	d503201f 	nop

00000000000108d0 <frame_dummy>:
   108d0:	17ffffdc 	b	10840 <register_tm_clones>

00000000000108d4 <ordered_mul(float, float)>:
   108d4:	1e210800 	fmul	s0, s0, s1
   108d8:	d65f03c0 	ret

00000000000108dc <main>:
   108dc:	fc1b0fea 	str	d10, [sp, #-80]!
   108e0:	6d00a3e9 	stp	d9, d8, [sp, #8]
   108e4:	a901fbfd 	stp	x29, x30, [sp, #24]
   108e8:	f90017f7 	str	x23, [sp, #40]
   108ec:	a90357f6 	stp	x22, x21, [sp, #48]
   108f0:	a9044ff4 	stp	x20, x19, [sp, #64]
   108f4:	910063fd 	add	x29, sp, #0x18
   108f8:	528468b6 	mov	w22, #0x2345                	// #9029
   108fc:	52aff808 	mov	w8, #0x7fc00000            	// #2143289344
   10900:	72aff836 	movk	w22, #0x7fc1, lsl #16
   10904:	1e27010a 	fmov	s10, w8
   10908:	1e2702c9 	fmov	s9, w22
   1090c:	1e204140 	fmov	s0, s10
   10910:	1e204121 	fmov	s1, s9
   10914:	97fffff0 	bl	108d4 <ordered_mul(float, float)>
   10918:	1e260014 	fmov	w20, s0
   1091c:	1e204120 	fmov	s0, s9
   10920:	1e204141 	fmov	s1, s10
   10924:	97ffffec 	bl	108d4 <ordered_mul(float, float)>
   10928:	1e260004 	fmov	w4, s0
   1092c:	d503201f 	nop
   10930:	10f7e793 	adr	x19, 620 <_IO_stdin_used+0x28>
   10934:	528468a2 	mov	w2, #0x2345                	// #9029
   10938:	aa1303e0 	mov	x0, x19
   1093c:	52aff801 	mov	w1, #0x7fc00000            	// #2143289344
   10940:	72aff822 	movk	w2, #0x7fc1, lsl #16
   10944:	2a1403e3 	mov	w3, w20
   10948:	6b04029f 	cmp	w20, w4
   1094c:	1a9f07f5 	cset	w21, ne	// ne = any
   10950:	2a1503e5 	mov	w5, w21
   10954:	9400008f 	bl	10b90 <printf@plt>
   10958:	52886437 	mov	w23, #0x4321                	// #17185
   1095c:	1e204140 	fmov	s0, s10
   10960:	72bff8b7 	movk	w23, #0xffc5, lsl #16
   10964:	1e2702e8 	fmov	s8, w23
   10968:	1e204101 	fmov	s1, s8
   1096c:	97ffffda 	bl	108d4 <ordered_mul(float, float)>
   10970:	1e260014 	fmov	w20, s0
   10974:	1e204100 	fmov	s0, s8
   10978:	1e204141 	fmov	s1, s10
   1097c:	97ffffd6 	bl	108d4 <ordered_mul(float, float)>
   10980:	1e260004 	fmov	w4, s0
   10984:	52886422 	mov	w2, #0x4321                	// #17185
   10988:	aa1303e0 	mov	x0, x19
   1098c:	52aff801 	mov	w1, #0x7fc00000            	// #2143289344
   10990:	72bff8a2 	movk	w2, #0xffc5, lsl #16
   10994:	2a1403e3 	mov	w3, w20
   10998:	6b04029f 	cmp	w20, w4
   1099c:	1a9f07e5 	cset	w5, ne	// ne = any
   109a0:	1a9506b5 	cinc	w21, w21, ne	// ne = any
   109a4:	9400007b 	bl	10b90 <printf@plt>
   109a8:	1e204120 	fmov	s0, s9
   109ac:	1e204101 	fmov	s1, s8
   109b0:	97ffffc9 	bl	108d4 <ordered_mul(float, float)>
   109b4:	1e260014 	fmov	w20, s0
   109b8:	1e204100 	fmov	s0, s8
   109bc:	1e204121 	fmov	s1, s9
   109c0:	97ffffc5 	bl	108d4 <ordered_mul(float, float)>
   109c4:	1e260004 	fmov	w4, s0
   109c8:	528468a1 	mov	w1, #0x2345                	// #9029
   109cc:	52886422 	mov	w2, #0x4321                	// #17185
   109d0:	aa1303e0 	mov	x0, x19
   109d4:	72aff821 	movk	w1, #0x7fc1, lsl #16
   109d8:	72bff8a2 	movk	w2, #0xffc5, lsl #16
   109dc:	2a1403e3 	mov	w3, w20
   109e0:	6b04029f 	cmp	w20, w4
   109e4:	1a9f07e5 	cset	w5, ne	// ne = any
   109e8:	1a9506b5 	cinc	w21, w21, ne	// ne = any
   109ec:	94000069 	bl	10b90 <printf@plt>
   109f0:	52886428 	mov	w8, #0x4321                	// #17185
   109f4:	1e204120 	fmov	s0, s9
   109f8:	72bff0a8 	movk	w8, #0xff85, lsl #16
   109fc:	1e27010a 	fmov	s10, w8
   10a00:	1e204141 	fmov	s1, s10
   10a04:	97ffffb4 	bl	108d4 <ordered_mul(float, float)>
   10a08:	1e260014 	fmov	w20, s0
   10a0c:	1e204140 	fmov	s0, s10
   10a10:	1e204121 	fmov	s1, s9
   10a14:	97ffffb0 	bl	108d4 <ordered_mul(float, float)>
   10a18:	1e260004 	fmov	w4, s0
   10a1c:	528468a1 	mov	w1, #0x2345                	// #9029
   10a20:	515002e2 	sub	w2, w23, #0x400, lsl #12
   10a24:	aa1303e0 	mov	x0, x19
   10a28:	72aff821 	movk	w1, #0x7fc1, lsl #16
   10a2c:	2a1403e3 	mov	w3, w20
   10a30:	6b04029f 	cmp	w20, w4
   10a34:	1a9f07e5 	cset	w5, ne	// ne = any
   10a38:	1a9506b5 	cinc	w21, w21, ne	// ne = any
   10a3c:	94000055 	bl	10b90 <printf@plt>
   10a40:	528468a8 	mov	w8, #0x2345                	// #9029
   10a44:	1e204101 	fmov	s1, s8
   10a48:	72aff028 	movk	w8, #0x7f81, lsl #16
   10a4c:	1e270109 	fmov	s9, w8
   10a50:	1e204120 	fmov	s0, s9
   10a54:	97ffffa0 	bl	108d4 <ordered_mul(float, float)>
   10a58:	1e260014 	fmov	w20, s0
   10a5c:	1e204100 	fmov	s0, s8
   10a60:	1e204121 	fmov	s1, s9
   10a64:	97ffff9c 	bl	108d4 <ordered_mul(float, float)>
   10a68:	1e260004 	fmov	w4, s0
   10a6c:	52886422 	mov	w2, #0x4321                	// #17185
   10a70:	515002c1 	sub	w1, w22, #0x400, lsl #12
   10a74:	aa1303e0 	mov	x0, x19
   10a78:	72bff8a2 	movk	w2, #0xffc5, lsl #16
   10a7c:	2a1403e3 	mov	w3, w20
   10a80:	6b04029f 	cmp	w20, w4
   10a84:	1a9f07e5 	cset	w5, ne	// ne = any
   10a88:	1a9506b5 	cinc	w21, w21, ne	// ne = any
   10a8c:	94000041 	bl	10b90 <printf@plt>
   10a90:	1e2e1000 	fmov	s0, #1.000000000000000000e+00
   10a94:	1e2c1001 	fmov	s1, #5.000000000000000000e-01
   10a98:	97ffff8f 	bl	108d4 <ordered_mul(float, float)>
   10a9c:	1e260014 	fmov	w20, s0
   10aa0:	1e2c1000 	fmov	s0, #5.000000000000000000e-01
   10aa4:	1e2e1001 	fmov	s1, #1.000000000000000000e+00
   10aa8:	97ffff8b 	bl	108d4 <ordered_mul(float, float)>
   10aac:	1e260004 	fmov	w4, s0
   10ab0:	aa1303e0 	mov	x0, x19
   10ab4:	52a7f001 	mov	w1, #0x3f800000            	// #1065353216
   10ab8:	52a7e002 	mov	w2, #0x3f000000            	// #1056964608
   10abc:	2a1403e3 	mov	w3, w20
   10ac0:	6b04029f 	cmp	w20, w4
   10ac4:	1a9f07e5 	cset	w5, ne	// ne = any
   10ac8:	1a9506b5 	cinc	w21, w21, ne	// ne = any
   10acc:	94000031 	bl	10b90 <printf@plt>
   10ad0:	90ffff80 	adrp	x0, 0 <__abi_tag-0x2c4>
   10ad4:	9117f000 	add	x0, x0, #0x5fc
   10ad8:	2a1503e1 	mov	w1, w21
   10adc:	9400002d 	bl	10b90 <printf@plt>
   10ae0:	2a1f03e0 	mov	w0, wzr
   10ae4:	a9444ff4 	ldp	x20, x19, [sp, #64]
   10ae8:	f94017f7 	ldr	x23, [sp, #40]
   10aec:	a94357f6 	ldp	x22, x21, [sp, #48]
   10af0:	a941fbfd 	ldp	x29, x30, [sp, #24]
   10af4:	6d40a3e9 	ldp	d9, d8, [sp, #8]
   10af8:	fc4507ea 	ldr	d10, [sp], #80
   10afc:	d65f03c0 	ret

Disassembly of section .init:

0000000000010b00 <_init>:
   10b00:	d503201f 	nop
   10b04:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   10b08:	910003fd 	mov	x29, sp
   10b0c:	97ffff3a 	bl	107f4 <call_weak_fn>
   10b10:	a8c17bfd 	ldp	x29, x30, [sp], #16
   10b14:	d65f03c0 	ret

Disassembly of section .fini:

0000000000010b18 <_fini>:
   10b18:	d503201f 	nop
   10b1c:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   10b20:	910003fd 	mov	x29, sp
   10b24:	a8c17bfd 	ldp	x29, x30, [sp], #16
   10b28:	d65f03c0 	ret

Disassembly of section .plt:

0000000000010b30 <abort@plt-0x20>:
   10b30:	a9bf7bf0 	stp	x16, x30, [sp, #-16]!
   10b34:	90000110 	adrp	x16, 30000 <_DYNAMIC+0xf450>
   10b38:	f946e611 	ldr	x17, [x16, #3528]
   10b3c:	91372210 	add	x16, x16, #0xdc8
   10b40:	d61f0220 	br	x17
   10b44:	d503201f 	nop
   10b48:	d503201f 	nop
   10b4c:	d503201f 	nop

0000000000010b50 <abort@plt>:
   10b50:	90000110 	adrp	x16, 30000 <_DYNAMIC+0xf450>
   10b54:	f946ea11 	ldr	x17, [x16, #3536]
   10b58:	91374210 	add	x16, x16, #0xdd0
   10b5c:	d61f0220 	br	x17

0000000000010b60 <__libc_start_main@plt>:
   10b60:	90000110 	adrp	x16, 30000 <_DYNAMIC+0xf450>
   10b64:	f946ee11 	ldr	x17, [x16, #3544]
   10b68:	91376210 	add	x16, x16, #0xdd8
   10b6c:	d61f0220 	br	x17

0000000000010b70 <__gmon_start__@plt>:
   10b70:	90000110 	adrp	x16, 30000 <_DYNAMIC+0xf450>
   10b74:	f946f211 	ldr	x17, [x16, #3552]
   10b78:	91378210 	add	x16, x16, #0xde0
   10b7c:	d61f0220 	br	x17

0000000000010b80 <__cxa_finalize@plt>:
   10b80:	90000110 	adrp	x16, 30000 <_DYNAMIC+0xf450>
   10b84:	f946f611 	ldr	x17, [x16, #3560]
   10b88:	9137a210 	add	x16, x16, #0xde8
   10b8c:	d61f0220 	br	x17

0000000000010b90 <printf@plt>:
   10b90:	90000110 	adrp	x16, 30000 <_DYNAMIC+0xf450>
   10b94:	f946fa11 	ldr	x17, [x16, #3568]
   10b98:	9137c210 	add	x16, x16, #0xdf0
   10b9c:	d61f0220 	br	x17
