$ aarch64-linux-gnu-objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/frontier-arm-clang

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/frontier-arm-clang:     file format elf64-littleaarch64


Disassembly of section .text:

0000000000011900 <_start>:
   11900:	d503201f 	nop
   11904:	d280001d 	mov	x29, #0x0                   	// #0
   11908:	d280001e 	mov	x30, #0x0                   	// #0
   1190c:	aa0003e5 	mov	x5, x0
   11910:	f94003e1 	ldr	x1, [sp]
   11914:	910023e2 	add	x2, sp, #0x8
   11918:	910003e6 	mov	x6, sp
   1191c:	d503201f 	nop
   11920:	10000c20 	adr	x0, 11aa4 <main>
   11924:	d2800003 	mov	x3, #0x0                   	// #0
   11928:	d2800004 	mov	x4, #0x0                   	// #0
   1192c:	94000c75 	bl	14b00 <__libc_start_main@plt>
   11930:	94000c70 	bl	14af0 <abort@plt>

0000000000011934 <call_weak_fn>:
   11934:	f0000080 	adrp	x0, 24000 <__getauxval@plt+0xf3d0>
   11938:	f9473000 	ldr	x0, [x0, #3680]
   1193c:	b4000040 	cbz	x0, 11944 <call_weak_fn+0x10>
   11940:	14000c74 	b	14b10 <__gmon_start__@plt>
   11944:	d65f03c0 	ret
	...

0000000000011950 <deregister_tm_clones>:
   11950:	d503201f 	nop
   11954:	1011aa60 	adr	x0, 34ea0 <__TMC_END__>
   11958:	d503201f 	nop
   1195c:	1011aa21 	adr	x1, 34ea0 <__TMC_END__>
   11960:	eb00003f 	cmp	x1, x0
   11964:	540000c0 	b.eq	1197c <deregister_tm_clones+0x2c>  // b.none
   11968:	f0000081 	adrp	x1, 24000 <__getauxval@plt+0xf3d0>
   1196c:	f9473421 	ldr	x1, [x1, #3688]
   11970:	b4000061 	cbz	x1, 1197c <deregister_tm_clones+0x2c>
   11974:	aa0103f0 	mov	x16, x1
   11978:	d61f0200 	br	x16
   1197c:	d65f03c0 	ret

0000000000011980 <register_tm_clones>:
   11980:	d503201f 	nop
   11984:	1011a8e0 	adr	x0, 34ea0 <__TMC_END__>
   11988:	d503201f 	nop
   1198c:	1011a8a1 	adr	x1, 34ea0 <__TMC_END__>
   11990:	cb000021 	sub	x1, x1, x0
   11994:	d37ffc22 	lsr	x2, x1, #63
   11998:	8b810c41 	add	x1, x2, x1, asr #3
   1199c:	9341fc21 	asr	x1, x1, #1
   119a0:	b40000c1 	cbz	x1, 119b8 <register_tm_clones+0x38>
   119a4:	f0000082 	adrp	x2, 24000 <__getauxval@plt+0xf3d0>
   119a8:	f9473842 	ldr	x2, [x2, #3696]
   119ac:	b4000062 	cbz	x2, 119b8 <register_tm_clones+0x38>
   119b0:	aa0203f0 	mov	x16, x2
   119b4:	d61f0200 	br	x16
   119b8:	d65f03c0 	ret
   119bc:	d503201f 	nop

00000000000119c0 <__do_global_dtors_aux>:
   119c0:	a9be7bfd 	stp	x29, x30, [sp, #-32]!
   119c4:	910003fd 	mov	x29, sp
   119c8:	f9000bf3 	str	x19, [sp, #16]
   119cc:	f0000113 	adrp	x19, 34000 <_DYNAMIC+0xf378>
   119d0:	397de260 	ldrb	w0, [x19, #3960]
   119d4:	35000140 	cbnz	w0, 119fc <__do_global_dtors_aux+0x3c>
   119d8:	f0000080 	adrp	x0, 24000 <__getauxval@plt+0xf3d0>
   119dc:	f9473c00 	ldr	x0, [x0, #3704]
   119e0:	b4000080 	cbz	x0, 119f0 <__do_global_dtors_aux+0x30>
   119e4:	f0000100 	adrp	x0, 34000 <_DYNAMIC+0xf378>
   119e8:	f9475000 	ldr	x0, [x0, #3744]
   119ec:	94000c4d 	bl	14b20 <__cxa_finalize@plt>
   119f0:	97ffffd8 	bl	11950 <deregister_tm_clones>
   119f4:	52800020 	mov	w0, #0x1                   	// #1
   119f8:	393de260 	strb	w0, [x19, #3960]
   119fc:	f9400bf3 	ldr	x19, [sp, #16]
   11a00:	a8c27bfd 	ldp	x29, x30, [sp], #32
   11a04:	d65f03c0 	ret
   11a08:	d503201f 	nop
   11a0c:	d503201f 	nop

0000000000011a10 <frame_dummy>:
   11a10:	17ffffdc 	b	11980 <register_tm_clones>

0000000000011a14 <_call_goal8_asm_systemv>:
   11a14:	d10203ff 	sub	sp, sp, #0x80
   11a18:	a9047bfd 	stp	x29, x30, [sp, #64]
   11a1c:	f9002bf7 	str	x23, [sp, #80]
   11a20:	a90657f6 	stp	x22, x21, [sp, #96]
   11a24:	a9074ff4 	stp	x20, x19, [sp, #112]
   11a28:	910103fd 	add	x29, sp, #0x40
   11a2c:	ad400420 	ldp	q0, q1, [x1]
   11a30:	f0000108 	adrp	x8, 34000 <_DYNAMIC+0xf378>
   11a34:	f947c108 	ldr	x8, [x8, #3968]
   11a38:	aa0403f3 	mov	x19, x4
   11a3c:	aa0303f4 	mov	x20, x3
   11a40:	aa0203f5 	mov	x21, x2
   11a44:	ad0007e0 	stp	q0, q1, [sp]
   11a48:	ad410022 	ldp	q2, q0, [x1, #32]
   11a4c:	eb05011f 	cmp	x8, x5
   11a50:	cb080016 	sub	x22, x0, x8
   11a54:	52800d00 	mov	w0, #0x68                  	// #104
   11a58:	1a9f17f7 	cset	w23, eq	// eq = none
   11a5c:	ad0103e2 	stp	q2, q0, [sp, #32]
   11a60:	94000c34 	bl	14b30 <__cxa_allocate_exception@plt>
   11a64:	ad4007e0 	ldp	q0, q1, [sp]
   11a68:	d503201f 	nop
   11a6c:	10098f61 	adr	x1, 24c58 <vtable for __cxxabiv1::__class_type_info@CXXABI_1.3>
   11a70:	aa1f03e2 	mov	x2, xzr
   11a74:	f9000016 	str	x22, [x0]
   11a78:	a904d015 	stp	x21, x20, [x0, #72]
   11a7c:	3c808000 	stur	q0, [x0, #8]
   11a80:	3c818001 	stur	q1, [x0, #24]
   11a84:	ad4107e0 	ldp	q0, q1, [sp, #32]
   11a88:	f9002c13 	str	x19, [x0, #88]
   11a8c:	39018017 	strb	w23, [x0, #96]
   11a90:	3c828000 	stur	q0, [x0, #40]
   11a94:	3c838001 	stur	q1, [x0, #56]
   11a98:	b806101f 	stur	wzr, [x0, #97]
   11a9c:	b900641f 	str	wzr, [x0, #100]
   11aa0:	94000c28 	bl	14b40 <__cxa_throw@plt>

0000000000011aa4 <main>:
   11aa4:	fc180fea 	str	d10, [sp, #-128]!
   11aa8:	6d0123e9 	stp	d9, d8, [sp, #16]
   11aac:	a9027bfd 	stp	x29, x30, [sp, #32]
   11ab0:	a9036ffc 	stp	x28, x27, [sp, #48]
   11ab4:	a90467fa 	stp	x26, x25, [sp, #64]
   11ab8:	a9055ff8 	stp	x24, x23, [sp, #80]
   11abc:	a90657f6 	stp	x22, x21, [sp, #96]
   11ac0:	a9074ff4 	stp	x20, x19, [sp, #112]
   11ac4:	910083fd 	add	x29, sp, #0x20
   11ac8:	d14013ff 	sub	sp, sp, #0x4, lsl #12
   11acc:	d11443ff 	sub	sp, sp, #0x510
   11ad0:	7100081f 	cmp	w0, #0x2
   11ad4:	540096cb 	b.lt	12dac <main+0x1308>  // b.tstop
   11ad8:	f9400433 	ldr	x19, [x1, #8]
   11adc:	90ffff81 	adrp	x1, 1000 <typeinfo name for Boundary+0x1e0>
   11ae0:	910f9021 	add	x1, x1, #0x3e4
   11ae4:	aa1303e0 	mov	x0, x19
   11ae8:	94000c1a 	bl	14b50 <fopen@plt>
   11aec:	b40096e0 	cbz	x0, 12dc8 <main+0x1324>
   11af0:	aa0003f4 	mov	x20, x0
   11af4:	90ffff80 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   11af8:	9101d800 	add	x0, x0, #0x76
   11afc:	528016a1 	mov	w1, #0xb5                  	// #181
   11b00:	52800022 	mov	w2, #0x1                   	// #1
   11b04:	aa1403e3 	mov	x3, x20
   11b08:	5280003a 	mov	w26, #0x1                   	// #1
   11b0c:	94000c15 	bl	14b60 <fwrite@plt>
   11b10:	52804009 	mov	w9, #0x200                 	// #512
   11b14:	52810008 	mov	w8, #0x800                 	// #2048
   11b18:	b90553ff 	str	wzr, [sp, #1360]
   11b1c:	b9058fff 	str	wzr, [sp, #1420]
   11b20:	d10063aa 	sub	x10, x29, #0x18
   11b24:	91400fe1 	add	x1, sp, #0x3, lsl #12
   11b28:	b90593ff 	str	wzr, [sp, #1424]
   11b2c:	529999b5 	mov	w21, #0xcccd                	// #52429
   11b30:	aa1f03fb 	mov	x27, xzr
   11b34:	f902bfff 	str	xzr, [sp, #1400]
   11b38:	91008021 	add	x1, x1, #0x20
   11b3c:	52800298 	mov	w24, #0x14                  	// #20
   11b40:	b9033bff 	str	wzr, [sp, #824]
   11b44:	d503201f 	nop
   11b48:	10f7c8c3 	adr	x3, 1460 <typeinfo name for Boundary+0x640>
   11b4c:	f902bbff 	str	xzr, [sp, #1392]
   11b50:	d503201f 	nop
   11b54:	10f7c9f3 	adr	x19, 1490 <typeinfo name for Boundary+0x670>
   11b58:	293d27a8 	stp	w8, w9, [x29, #-24]
   11b5c:	f0000089 	adrp	x9, 24000 <__getauxval@plt+0xf3d0>
   11b60:	52810208 	mov	w8, #0x810                 	// #2064
   11b64:	f9474529 	ldr	x9, [x9, #3720]
   11b68:	b81d43a8 	stur	w8, [x29, #-44]
   11b6c:	d10053a8 	sub	x8, x29, #0x14
   11b70:	72b99995 	movk	w21, #0xcccc, lsl #16
   11b74:	a9002928 	stp	x8, x10, [x9]
   11b78:	d100b3a8 	sub	x8, x29, #0x2c
   11b7c:	d100c3aa 	sub	x10, x29, #0x30
   11b80:	a9012928 	stp	x8, x10, [x9, #16]
   11b84:	52810408 	mov	w8, #0x820                 	// #2080
   11b88:	d503201f 	nop
   11b8c:	1011acea 	adr	x10, 35128 <full_after_cache>
   11b90:	b81d03a8 	stur	w8, [x29, #-48]
   11b94:	914013e8 	add	x8, sp, #0x4, lsl #12
   11b98:	91008108 	add	x8, x8, #0x20
   11b9c:	ad400520 	ldp	q0, q1, [x9]
   11ba0:	910a0109 	add	x9, x8, #0x280
   11ba4:	f9019bf4 	str	x20, [sp, #816]
   11ba8:	914013f4 	add	x20, sp, #0x4, lsl #12
   11bac:	f9014fe9 	str	x9, [sp, #664]
   11bb0:	91010109 	add	x9, x8, #0x40
   11bb4:	91008294 	add	x20, x20, #0x20
   11bb8:	f90197e9 	str	x9, [sp, #808]
   11bbc:	91020109 	add	x9, x8, #0x80
   11bc0:	f90193e9 	str	x9, [sp, #800]
   11bc4:	91030109 	add	x9, x8, #0xc0
   11bc8:	f9018fe9 	str	x9, [sp, #792]
   11bcc:	91040109 	add	x9, x8, #0x100
   11bd0:	f9018be9 	str	x9, [sp, #784]
   11bd4:	91050109 	add	x9, x8, #0x140
   11bd8:	f90187e9 	str	x9, [sp, #776]
   11bdc:	91060109 	add	x9, x8, #0x180
   11be0:	91070108 	add	x8, x8, #0x1c0
   11be4:	f90183e9 	str	x9, [sp, #768]
   11be8:	91400be9 	add	x9, sp, #0x2, lsl #12
   11bec:	ad000540 	stp	q0, q1, [x10]
   11bf0:	911a8129 	add	x9, x9, #0x6a0
   11bf4:	91400bea 	add	x10, sp, #0x2, lsl #12
   11bf8:	912d814a 	add	x10, x10, #0xb60
   11bfc:	f9017fe8 	str	x8, [sp, #760]
   11c00:	910a3128 	add	x8, x9, #0x28c
   11c04:	f9014be8 	str	x8, [sp, #656]
   11c08:	910a3148 	add	x8, x10, #0x28c
   11c0c:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11c10:	f90147e8 	str	x8, [sp, #648]
   11c14:	12807fe8 	mov	w8, #0xfffffc00            	// #-1024
   11c18:	528f372a 	mov	w10, #0x79b9                	// #31161
   11c1c:	b9054fe8 	str	w8, [sp, #1356]
   11c20:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11c24:	72b3c6ea 	movk	w10, #0x9e37, lsl #16
   11c28:	3dc35500 	ldr	q0, [x8, #3408]
   11c2c:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11c30:	a93c7fbf 	stp	xzr, xzr, [x29, #-64]
   11c34:	a93b7fbf 	stp	xzr, xzr, [x29, #-80]
   11c38:	3d809be0 	str	q0, [sp, #608]
   11c3c:	3dc35d20 	ldr	q0, [x9, #3440]
   11c40:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11c44:	3d8097e0 	str	q0, [sp, #592]
   11c48:	3dc31d00 	ldr	q0, [x8, #3184]
   11c4c:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11c50:	3d8093e0 	str	q0, [sp, #576]
   11c54:	3dc31100 	ldr	q0, [x8, #3136]
   11c58:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11c5c:	3d808fe0 	str	q0, [sp, #560]
   11c60:	3dc32120 	ldr	q0, [x9, #3200]
   11c64:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11c68:	3d808be0 	str	q0, [sp, #544]
   11c6c:	3dc36500 	ldr	q0, [x8, #3472]
   11c70:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11c74:	3d8087e0 	str	q0, [sp, #528]
   11c78:	3dc30900 	ldr	q0, [x8, #3104]
   11c7c:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11c80:	3d8083e0 	str	q0, [sp, #512]
   11c84:	3dc37d20 	ldr	q0, [x9, #3568]
   11c88:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11c8c:	3d807fe0 	str	q0, [sp, #496]
   11c90:	3dc32500 	ldr	q0, [x8, #3216]
   11c94:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11c98:	3d807be0 	str	q0, [sp, #480]
   11c9c:	3dc37100 	ldr	q0, [x8, #3520]
   11ca0:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11ca4:	3d8077e0 	str	q0, [sp, #464]
   11ca8:	3dc37520 	ldr	q0, [x9, #3536]
   11cac:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11cb0:	3d8073e0 	str	q0, [sp, #448]
   11cb4:	3dc31900 	ldr	q0, [x8, #3168]
   11cb8:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11cbc:	3d806fe0 	str	q0, [sp, #432]
   11cc0:	3dc33900 	ldr	q0, [x8, #3296]
   11cc4:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11cc8:	3d806be0 	str	q0, [sp, #416]
   11ccc:	3dc35920 	ldr	q0, [x9, #3424]
   11cd0:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11cd4:	3d8067e0 	str	q0, [sp, #400]
   11cd8:	3dc31500 	ldr	q0, [x8, #3152]
   11cdc:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11ce0:	3d8063e0 	str	q0, [sp, #384]
   11ce4:	3dc36d00 	ldr	q0, [x8, #3504]
   11ce8:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11cec:	3d805fe0 	str	q0, [sp, #368]
   11cf0:	3dc34120 	ldr	q0, [x9, #3328]
   11cf4:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11cf8:	3d805be0 	str	q0, [sp, #352]
   11cfc:	3dc38500 	ldr	q0, [x8, #3600]
   11d00:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d04:	3d8057e0 	str	q0, [sp, #336]
   11d08:	3dc36100 	ldr	q0, [x8, #3456]
   11d0c:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d10:	3d8053e0 	str	q0, [sp, #320]
   11d14:	3dc33120 	ldr	q0, [x9, #3264]
   11d18:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11d1c:	3d804fe0 	str	q0, [sp, #304]
   11d20:	3dc32900 	ldr	q0, [x8, #3232]
   11d24:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d28:	3d804be0 	str	q0, [sp, #288]
   11d2c:	3dc33d00 	ldr	q0, [x8, #3312]
   11d30:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d34:	3d8047e0 	str	q0, [sp, #272]
   11d38:	3dc34520 	ldr	q0, [x9, #3344]
   11d3c:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11d40:	3d8043e0 	str	q0, [sp, #256]
   11d44:	3dc33500 	ldr	q0, [x8, #3280]
   11d48:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d4c:	3d803fe0 	str	q0, [sp, #240]
   11d50:	3dc34900 	ldr	q0, [x8, #3360]
   11d54:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d58:	3d803be0 	str	q0, [sp, #224]
   11d5c:	3dc37920 	ldr	q0, [x9, #3552]
   11d60:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11d64:	3d8037e0 	str	q0, [sp, #208]
   11d68:	3dc38100 	ldr	q0, [x8, #3584]
   11d6c:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d70:	3d8033e0 	str	q0, [sp, #192]
   11d74:	3dc32d00 	ldr	q0, [x8, #3248]
   11d78:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d7c:	3dc30d01 	ldr	q1, [x8, #3120]
   11d80:	f0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   11d84:	3d802fe0 	str	q0, [sp, #176]
   11d88:	3dc35120 	ldr	q0, [x9, #3392]
   11d8c:	f0ffff69 	adrp	x9, 0 <__abi_tag-0x2c4>
   11d90:	3d802be0 	str	q0, [sp, #160]
   11d94:	4e040d40 	dup	v0.4s, w10
   11d98:	ad0407e0 	stp	q0, q1, [sp, #128]
   11d9c:	3dc34d00 	ldr	q0, [x8, #3376]
   11da0:	3d801fe0 	str	q0, [sp, #112]
   11da4:	3dc36920 	ldr	q0, [x9, #3488]
   11da8:	3d801be0 	str	q0, [sp, #96]
   11dac:	1400000a 	b	11dd4 <main+0x330>
   11db0:	b9454fe8 	ldr	w8, [sp, #1356]
   11db4:	f9413ffb 	ldr	x27, [sp, #632]
   11db8:	11007d08 	add	w8, w8, #0x1f
   11dbc:	f102a37f 	cmp	x27, #0xa8
   11dc0:	b9054fe8 	str	w8, [sp, #1356]
   11dc4:	b94553e8 	ldr	w8, [sp, #1360]
   11dc8:	11007d08 	add	w8, w8, #0x1f
   11dcc:	b90553e8 	str	w8, [sp, #1360]
   11dd0:	54007660 	b.eq	12c9c <main+0x11f8>  // b.none
   11dd4:	9100076c 	add	x12, x27, #0x1
   11dd8:	3dc023e1 	ldr	q1, [sp, #128]
   11ddc:	911403f6 	add	x22, sp, #0x500
   11de0:	4e040d80 	dup	v0.4s, w12
   11de4:	f100537f 	cmp	x27, #0x14
   11de8:	528000e8 	mov	w8, #0x7                   	// #7
   11dec:	1a8833e8 	csel	w8, wzr, w8, cc	// cc = lo, ul, last
   11df0:	5280738a 	mov	w10, #0x39c                 	// #924
   11df4:	92407f6e 	and	x14, x27, #0xffffffff
   11df8:	53196109 	lsl	w9, w8, #7
   11dfc:	1a8a33eb 	csel	w11, wzr, w10, cc	// cc = lo, ul, last
   11e00:	528924aa 	mov	w10, #0x4925                	// #18725
   11e04:	4ea19c00 	mul	v0.4s, v0.4s, v1.4s
   11e08:	3dc09be1 	ldr	q1, [sp, #608]
   11e0c:	72a4924a 	movk	w10, #0x2492, lsl #16
   11e10:	0b1b012f 	add	w15, w9, w27
   11e14:	9baa7dcd 	umull	x13, w14, w10
   11e18:	f9013fec 	str	x12, [sp, #632]
   11e1c:	52801049 	mov	w9, #0x82                  	// #130
   11e20:	12003dec 	and	w12, w15, #0xffff
   11e24:	529999a2 	mov	w2, #0xcccd                	// #52429
   11e28:	1b096d0a 	madd	w10, w8, w9, w27
   11e2c:	2a0803f0 	mov	w16, w8
   11e30:	0b1b0169 	add	w9, w11, w27
   11e34:	4ea18402 	add	v2.4s, v0.4s, v1.4s
   11e38:	ad4f1be1 	ldp	q1, q6, [sp, #480]
   11e3c:	1b027d8b 	mul	w11, w12, w2
   11e40:	33190910 	bfi	w16, w8, #7, #3
   11e44:	5280106c 	mov	w12, #0x83                  	// #131
   11e48:	1b0c6d0c 	madd	w12, w8, w12, w27
   11e4c:	d360fdb2 	lsr	x18, x13, #32
   11e50:	12003d31 	and	w17, w9, #0xffff
   11e54:	4ea18403 	add	v3.4s, v0.4s, v1.4s
   11e58:	3dc077e1 	ldr	q1, [sp, #464]
   11e5c:	4ea68410 	add	v16.4s, v0.4s, v6.4s
   11e60:	0b1b0210 	add	w16, w16, w27
   11e64:	53147d6b 	lsr	w11, w11, #20
   11e68:	1b027e2d 	mul	w13, w17, w2
   11e6c:	4ea18404 	add	v4.4s, v0.4s, v1.4s
   11e70:	ad4d87e6 	ldp	q6, q1, [sp, #432]
   11e74:	12003e11 	and	w17, w16, #0xffff
   11e78:	4b120360 	sub	w0, w27, w18
   11e7c:	1b18bd6b 	msub	w11, w11, w24, w15
   11e80:	1b027e31 	mul	w17, w17, w2
   11e84:	0b400652 	add	w18, w18, w0, lsr #1
   11e88:	12003d40 	and	w0, w10, #0xffff
   11e8c:	4ea18405 	add	v5.4s, v0.4s, v1.4s
   11e90:	4ea68411 	add	v17.4s, v0.4s, v6.4s
   11e94:	12003d8f 	and	w15, w12, #0xffff
   11e98:	1b027c00 	mul	w0, w0, w2
   11e9c:	53147dad 	lsr	w13, w13, #20
   11ea0:	53027e52 	lsr	w18, w18, #2
   11ea4:	1b027def 	mul	w15, w15, w2
   11ea8:	5291c722 	mov	w2, #0x8e39                	// #36409
   11eac:	53147e31 	lsr	w17, w17, #20
   11eb0:	72a71c62 	movk	w2, #0x38e3, lsl #16
   11eb4:	aa1f03e4 	mov	x4, xzr
   11eb8:	4c002ec2 	st1	{v2.2d-v5.2d}, [x22]
   11ebc:	ad4c8be1 	ldp	q1, q2, [sp, #400]
   11ec0:	911303f6 	add	x22, sp, #0x4c0
   11ec4:	9ba27dce 	umull	x14, w14, w2
   11ec8:	53147def 	lsr	w15, w15, #20
   11ecc:	1b18c230 	msub	w16, w17, w24, w16
   11ed0:	53147c11 	lsr	w17, w0, #20
   11ed4:	531f7900 	lsl	w0, w8, #1
   11ed8:	4ea28412 	add	v18.4s, v0.4s, v2.4s
   11edc:	1b18b1ec 	msub	w12, w15, w24, w12
   11ee0:	4b120e4f 	sub	w15, w18, w18, lsl #3
   11ee4:	4ea18413 	add	v19.4s, v0.4s, v1.4s
   11ee8:	ad5007e6 	ldp	q6, q1, [sp, #512]
   11eec:	d361fdce 	lsr	x14, x14, #33
   11ef0:	1b18aa2a 	msub	w10, w17, w24, w10
   11ef4:	0b1b0111 	add	w17, w8, w27
   11ef8:	b902d7f1 	str	w17, [sp, #724]
   11efc:	4ea68402 	add	v2.4s, v0.4s, v6.4s
   11f00:	0b0e0dce 	add	w14, w14, w14, lsl #3
   11f04:	4c002ed0 	st1	{v16.2d-v19.2d}, [x22]
   11f08:	4ea18410 	add	v16.4s, v0.4s, v1.4s
   11f0c:	3dc063e1 	ldr	q1, [sp, #384]
   11f10:	911203f6 	add	x22, sp, #0x480
   11f14:	4b0e036e 	sub	w14, w27, w14
   11f18:	4ea18403 	add	v3.4s, v0.4s, v1.4s
   11f1c:	3dc057e1 	ldr	q1, [sp, #336]
   11f20:	1e03f5ca 	ucvtf	s10, w14, #3
   11f24:	4ea18411 	add	v17.4s, v0.4s, v1.4s
   11f28:	3dc08be1 	ldr	q1, [sp, #544]
   11f2c:	4ea18414 	add	v20.4s, v0.4s, v1.4s
   11f30:	3dc05fe1 	ldr	q1, [sp, #368]
   11f34:	4ea18404 	add	v4.4s, v0.4s, v1.4s
   11f38:	3dc053e1 	ldr	q1, [sp, #320]
   11f3c:	4ea18412 	add	v18.4s, v0.4s, v1.4s
   11f40:	3dc04be1 	ldr	q1, [sp, #288]
   11f44:	4ea18415 	add	v21.4s, v0.4s, v1.4s
   11f48:	3dc05be1 	ldr	q1, [sp, #352]
   11f4c:	4ea18405 	add	v5.4s, v0.4s, v1.4s
   11f50:	3dc04fe1 	ldr	q1, [sp, #304]
   11f54:	4ea18413 	add	v19.4s, v0.4s, v1.4s
   11f58:	4c002ec2 	st1	{v2.2d-v5.2d}, [x22]
   11f5c:	ad480be1 	ldp	q1, q2, [sp, #256]
   11f60:	911103f6 	add	x22, sp, #0x440
   11f64:	4ea28416 	add	v22.4s, v0.4s, v2.4s
   11f68:	4ea18417 	add	v23.4s, v0.4s, v1.4s
   11f6c:	ad5187e6 	ldp	q6, q1, [sp, #560]
   11f70:	4c002ed0 	st1	{v16.2d-v19.2d}, [x22]
   11f74:	911003f6 	add	x22, sp, #0x400
   11f78:	4ea18410 	add	v16.4s, v0.4s, v1.4s
   11f7c:	3dc03fe1 	ldr	q1, [sp, #240]
   11f80:	4ea68402 	add	v2.4s, v0.4s, v6.4s
   11f84:	4ea18403 	add	v3.4s, v0.4s, v1.4s
   11f88:	3dc033e1 	ldr	q1, [sp, #192]
   11f8c:	4c002ed4 	st1	{v20.2d-v23.2d}, [x22]
   11f90:	910f03f6 	add	x22, sp, #0x3c0
   11f94:	4ea18411 	add	v17.4s, v0.4s, v1.4s
   11f98:	3dc097e1 	ldr	q1, [sp, #592]
   11f9c:	4ea18414 	add	v20.4s, v0.4s, v1.4s
   11fa0:	3dc03be1 	ldr	q1, [sp, #224]
   11fa4:	4ea18404 	add	v4.4s, v0.4s, v1.4s
   11fa8:	3dc02fe1 	ldr	q1, [sp, #176]
   11fac:	4ea18412 	add	v18.4s, v0.4s, v1.4s
   11fb0:	3dc027e1 	ldr	q1, [sp, #144]
   11fb4:	4ea18415 	add	v21.4s, v0.4s, v1.4s
   11fb8:	3dc037e1 	ldr	q1, [sp, #208]
   11fbc:	4ea18405 	add	v5.4s, v0.4s, v1.4s
   11fc0:	3dc02be1 	ldr	q1, [sp, #160]
   11fc4:	4ea18413 	add	v19.4s, v0.4s, v1.4s
   11fc8:	4c002ec2 	st1	{v2.2d-v5.2d}, [x22]
   11fcc:	ad430be1 	ldp	q1, q2, [sp, #96]
   11fd0:	910e03f6 	add	x22, sp, #0x380
   11fd4:	4ea28416 	add	v22.4s, v0.4s, v2.4s
   11fd8:	4ea18417 	add	v23.4s, v0.4s, v1.4s
   11fdc:	4c002ed0 	st1	{v16.2d-v19.2d}, [x22]
   11fe0:	910d03f6 	add	x22, sp, #0x340
   11fe4:	4c002ed4 	st1	{v20.2d-v23.2d}, [x22]
   11fe8:	531e7516 	lsl	w22, w8, #2
   11fec:	1b18a5a8 	msub	w8, w13, w24, w9
   11ff0:	12000769 	and	w9, w27, #0x3
   11ff4:	0b0f036d 	add	w13, w27, w15
   11ff8:	1e03f928 	ucvtf	s8, w9, #2
   11ffc:	528f3729 	mov	w9, #0x79b9                	// #31161
   12000:	1e03f1a9 	ucvtf	s9, w13, #4
   12004:	72b3c6e9 	movk	w9, #0x9e37, lsl #16
   12008:	92403d08 	and	x8, x8, #0xffff
   1200c:	4a090369 	eor	w9, w27, w9
   12010:	f90157e8 	str	x8, [sp, #680]
   12014:	0b000228 	add	w8, w17, w0
   12018:	b9033fe9 	str	w9, [sp, #828]
   1201c:	92403d69 	and	x9, x11, #0xffff
   12020:	f90167e9 	str	x9, [sp, #712]
   12024:	92403e09 	and	x9, x16, #0xffff
   12028:	f90163e9 	str	x9, [sp, #704]
   1202c:	92403d49 	and	x9, x10, #0xffff
   12030:	b902a7e8 	str	w8, [sp, #676]
   12034:	0b000368 	add	w8, w27, w0
   12038:	f9015fe9 	str	x9, [sp, #696]
   1203c:	92403d89 	and	x9, x12, #0xffff
   12040:	b902a3e8 	str	w8, [sp, #672]
   12044:	aa0303e8 	mov	x8, x3
   12048:	f9015be9 	str	x9, [sp, #688]
   1204c:	1400000a 	b	12074 <main+0x5d0>
   12050:	f94143e4 	ldr	x4, [sp, #640]
   12054:	d503201f 	nop
   12058:	10f7a043 	adr	x3, 1460 <typeinfo name for Boundary+0x640>
   1205c:	91400fe1 	add	x1, sp, #0x3, lsl #12
   12060:	91002084 	add	x4, x4, #0x8
   12064:	91008021 	add	x1, x1, #0x20
   12068:	f100c09f 	cmp	x4, #0x30
   1206c:	8b040068 	add	x8, x3, x4
   12070:	54ffea00 	b.eq	11db0 <main+0x30c>  // b.none
   12074:	b8646879 	ldr	w25, [x3, x4]
   12078:	b940050a 	ldr	w10, [x8, #4]
   1207c:	f100377f 	cmp	x27, #0xd
   12080:	52800808 	mov	w8, #0x40                  	// #64
   12084:	aa1f03e9 	mov	x9, xzr
   12088:	f90143e4 	str	x4, [sp, #640]
   1208c:	fa480320 	ccmp	x25, x8, #0x0, eq	// eq = none
   12090:	8b0a0028 	add	x8, x1, x10
   12094:	f902cfea 	str	x10, [sp, #1432]
   12098:	f902afe8 	str	x8, [sp, #1368]
   1209c:	1a9f17e8 	cset	w8, eq	// eq = none
   120a0:	b90557e8 	str	w8, [sp, #1364]
   120a4:	f902b3f9 	str	x25, [sp, #1376]
   120a8:	14000076 	b	12280 <main+0x7dc>
   120ac:	f94313e1 	ldr	x1, [sp, #1568]
   120b0:	f94337e3 	ldr	x3, [sp, #1640]
   120b4:	d0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   120b8:	913c8c00 	add	x0, x0, #0xf23
   120bc:	f942d3e2 	ldr	x2, [sp, #1440]
   120c0:	f942f7e4 	ldr	x4, [sp, #1512]
   120c4:	f9433be5 	ldr	x5, [sp, #1648]
   120c8:	f9433fe7 	ldr	x7, [sp, #1656]
   120cc:	f942fbe6 	ldr	x6, [sp, #1520]
   120d0:	f942ffe8 	ldr	x8, [sp, #1528]
   120d4:	395a03e9 	ldrb	w9, [sp, #1664]
   120d8:	395803ea 	ldrb	w10, [sp, #1536]
   120dc:	f94347eb 	ldr	x11, [sp, #1672]
   120e0:	f94307ec 	ldr	x12, [sp, #1544]
   120e4:	b90013ea 	str	w10, [sp, #16]
   120e8:	a901b3eb 	stp	x11, x12, [sp, #24]
   120ec:	b9000be9 	str	w9, [sp, #8]
   120f0:	f90003e8 	str	x8, [sp]
   120f4:	94000a9f 	bl	14b70 <printf@plt>
   120f8:	f94317e2 	ldr	x2, [sp, #1576]
   120fc:	f942d7e3 	ldr	x3, [sp, #1448]
   12100:	d0ffff74 	adrp	x20, 0 <__abi_tag-0x2c4>
   12104:	91392a94 	add	x20, x20, #0xe4a
   12108:	2a1f03e1 	mov	w1, wzr
   1210c:	aa1403e0 	mov	x0, x20
   12110:	94000a98 	bl	14b70 <printf@plt>
   12114:	f9431be2 	ldr	x2, [sp, #1584]
   12118:	f942dbe3 	ldr	x3, [sp, #1456]
   1211c:	aa1403e0 	mov	x0, x20
   12120:	52800021 	mov	w1, #0x1                   	// #1
   12124:	94000a93 	bl	14b70 <printf@plt>
   12128:	f9431fe2 	ldr	x2, [sp, #1592]
   1212c:	f942dfe3 	ldr	x3, [sp, #1464]
   12130:	aa1403e0 	mov	x0, x20
   12134:	52800041 	mov	w1, #0x2                   	// #2
   12138:	94000a8e 	bl	14b70 <printf@plt>
   1213c:	f94323e2 	ldr	x2, [sp, #1600]
   12140:	f942e3e3 	ldr	x3, [sp, #1472]
   12144:	aa1403e0 	mov	x0, x20
   12148:	52800061 	mov	w1, #0x3                   	// #3
   1214c:	94000a89 	bl	14b70 <printf@plt>
   12150:	f94327e2 	ldr	x2, [sp, #1608]
   12154:	f942e7e3 	ldr	x3, [sp, #1480]
   12158:	aa1403e0 	mov	x0, x20
   1215c:	52800081 	mov	w1, #0x4                   	// #4
   12160:	94000a84 	bl	14b70 <printf@plt>
   12164:	f9432be2 	ldr	x2, [sp, #1616]
   12168:	f942ebe3 	ldr	x3, [sp, #1488]
   1216c:	aa1403e0 	mov	x0, x20
   12170:	528000a1 	mov	w1, #0x5                   	// #5
   12174:	94000a7f 	bl	14b70 <printf@plt>
   12178:	f9432fe2 	ldr	x2, [sp, #1624]
   1217c:	f942efe3 	ldr	x3, [sp, #1496]
   12180:	aa1403e0 	mov	x0, x20
   12184:	528000c1 	mov	w1, #0x6                   	// #6
   12188:	94000a7a 	bl	14b70 <printf@plt>
   1218c:	f94333e2 	ldr	x2, [sp, #1632]
   12190:	f942f3e3 	ldr	x3, [sp, #1504]
   12194:	aa1403e0 	mov	x0, x20
   12198:	528000e1 	mov	w1, #0x7                   	// #7
   1219c:	94000a75 	bl	14b70 <printf@plt>
   121a0:	f942b3f9 	ldr	x25, [sp, #1376]
   121a4:	f942c3ee 	ldr	x14, [sp, #1408]
   121a8:	b942f7f1 	ldr	w17, [sp, #756]
   121ac:	b942f3f2 	ldr	w18, [sp, #752]
   121b0:	b942efe0 	ldr	w0, [sp, #748]
   121b4:	b942ebe1 	ldr	w1, [sp, #744]
   121b8:	f94173ea 	ldr	x10, [sp, #736]
   121bc:	b942dfeb 	ldr	w11, [sp, #732]
   121c0:	b942dbec 	ldr	w12, [sp, #728]
   121c4:	b94573f0 	ldr	w16, [sp, #1392]
   121c8:	7100059f 	cmp	w12, #0x1
   121cc:	d503201f 	nop
   121d0:	100954c8 	adr	x8, 24c68 <route_name(unsigned int)::names>
   121d4:	f9419bf7 	ldr	x23, [sp, #816]
   121d8:	b9458ff4 	ldr	w20, [sp, #1420]
   121dc:	0b000210 	add	w16, w16, w0
   121e0:	f86e5907 	ldr	x7, [x8, w14, uxtw #3]
   121e4:	f86a7908 	ldr	x8, [x8, x10, lsl #3]
   121e8:	b90573f0 	str	w16, [sp, #1392]
   121ec:	b94593f0 	ldr	w16, [sp, #1424]
   121f0:	b96e9be9 	ldr	w9, [sp, #11928]
   121f4:	b969dbea 	ldr	w10, [sp, #10712]
   121f8:	1a9f956b 	csinc	w11, w11, wzr, ls	// ls = plast
   121fc:	f94313ec 	ldr	x12, [sp, #1568]
   12200:	f94347ed 	ldr	x13, [sp, #1672]
   12204:	f942d3ee 	ldr	x14, [sp, #1440]
   12208:	0b0b0210 	add	w16, w16, w11
   1220c:	f94307ef 	ldr	x15, [sp, #1544]
   12210:	b94597e6 	ldr	w6, [sp, #1428]
   12214:	2a1403e2 	mov	w2, w20
   12218:	b90023e1 	str	w1, [sp, #32]
   1221c:	d0ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   12220:	9139b821 	add	x1, x1, #0xe6e
   12224:	b9001be0 	str	w0, [sp, #24]
   12228:	aa1703e0 	mov	x0, x23
   1222c:	2a1b03e3 	mov	w3, w27
   12230:	2a1903e4 	mov	w4, w25
   12234:	f942cfe5 	ldr	x5, [sp, #1432]
   12238:	b90593f0 	str	w16, [sp, #1424]
   1223c:	a904bfed 	stp	x13, x15, [sp, #72]
   12240:	b90043ea 	str	w10, [sp, #64]
   12244:	b9003be9 	str	w9, [sp, #56]
   12248:	a902bbec 	stp	x12, x14, [sp, #40]
   1224c:	b90013f2 	str	w18, [sp, #16]
   12250:	b9000bf1 	str	w17, [sp, #8]
   12254:	f90003e8 	str	x8, [sp]
   12258:	94000a4a 	bl	14b80 <fprintf@plt>
   1225c:	f942b7e9 	ldr	x9, [sp, #1384]
   12260:	11000694 	add	w20, w20, #0x1
   12264:	5280003a 	mov	w26, #0x1                   	// #1
   12268:	b9058ff4 	str	w20, [sp, #1420]
   1226c:	914013f4 	add	x20, sp, #0x4, lsl #12
   12270:	91001129 	add	x9, x9, #0x4
   12274:	91008294 	add	x20, x20, #0x20
   12278:	f100613f 	cmp	x9, #0x18
   1227c:	54ffeea0 	b.eq	12050 <main+0x5ac>  // b.none
   12280:	d503201f 	nop
   12284:	10f78e28 	adr	x8, 1448 <typeinfo name for Boundary+0x628>
   12288:	914013e0 	add	x0, sp, #0x4, lsl #12
   1228c:	b8696908 	ldr	w8, [x8, x9]
   12290:	91008000 	add	x0, x0, #0x20
   12294:	2a1f03e1 	mov	w1, wzr
   12298:	52809802 	mov	w2, #0x4c0                 	// #1216
   1229c:	f902b7e9 	str	x9, [sp, #1384]
   122a0:	b90597e8 	str	w8, [sp, #1428]
   122a4:	94000a3b 	bl	14b90 <memset@plt>
   122a8:	f100a37f 	cmp	x27, #0x28
   122ac:	540005e2 	b.cs	12368 <main+0x8c4>  // b.hs, b.nlast
   122b0:	b942d7ea 	ldr	w10, [sp, #724]
   122b4:	b942a3eb 	ldr	w11, [sp, #672]
   122b8:	aa1f03e8 	mov	x8, xzr
   122bc:	b942a7ec 	ldr	w12, [sp, #676]
   122c0:	b9433fed 	ldr	w13, [sp, #828]
   122c4:	2a1b03e9 	mov	w9, w27
   122c8:	f9414fe0 	ldr	x0, [sp, #664]
   122cc:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   122d0:	9bb57d2e 	umull	x14, w9, w21
   122d4:	8b080012 	add	x18, x0, x8
   122d8:	9bb57d4f 	umull	x15, w10, w21
   122dc:	91004108 	add	x8, x8, #0x10
   122e0:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   122e4:	9bb57d70 	umull	x16, w11, w21
   122e8:	f108011f 	cmp	x8, #0x200
   122ec:	9bb57d91 	umull	x17, w12, w21
   122f0:	d364fdce 	lsr	x14, x14, #36
   122f4:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   122f8:	d364fdef 	lsr	x15, x15, #36
   122fc:	d364fe10 	lsr	x16, x16, #36
   12300:	1b18a5ce 	msub	w14, w14, w24, w9
   12304:	0b160129 	add	w9, w9, w22
   12308:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   1230c:	d364fe31 	lsr	x17, x17, #36
   12310:	1b18a9ef 	msub	w15, w15, w24, w10
   12314:	1b18ae10 	msub	w16, w16, w24, w11
   12318:	0b16016b 	add	w11, w11, w22
   1231c:	0b16014a 	add	w10, w10, w22
   12320:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   12324:	1b18b231 	msub	w17, w17, w24, w12
   12328:	b86e5a6e 	ldr	w14, [x19, w14, uxtw #2]
   1232c:	b86f5a6f 	ldr	w15, [x19, w15, uxtw #2]
   12330:	0b16018c 	add	w12, w12, w22
   12334:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   12338:	b8705a70 	ldr	w16, [x19, w16, uxtw #2]
   1233c:	29003e4e 	stp	w14, w15, [x18]
   12340:	b8715a6e 	ldr	w14, [x19, w17, uxtw #2]
   12344:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   12348:	29013a50 	stp	w16, w14, [x18, #8]
   1234c:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   12350:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   12354:	4a0d35ad 	eor	w13, w13, w13, lsl #13
   12358:	4a4d45ad 	eor	w13, w13, w13, lsr #17
   1235c:	4a0d15ad 	eor	w13, w13, w13, lsl #5
   12360:	54fffb61 	b.ne	122cc <main+0x828>  // b.any
   12364:	14000017 	b	123c0 <main+0x91c>
   12368:	b9433fed 	ldr	w13, [sp, #828]
   1236c:	aa1f03e8 	mov	x8, xzr
   12370:	4a0d35a9 	eor	w9, w13, w13, lsl #13
   12374:	8b08028e 	add	x14, x20, x8
   12378:	91004108 	add	x8, x8, #0x10
   1237c:	f108011f 	cmp	x8, #0x200
   12380:	4a494529 	eor	w9, w9, w9, lsr #17
   12384:	4a091529 	eor	w9, w9, w9, lsl #5
   12388:	4a09352a 	eor	w10, w9, w9, lsl #13
   1238c:	b90281c9 	str	w9, [x14, #640]
   12390:	4a4a454a 	eor	w10, w10, w10, lsr #17
   12394:	4a0a154a 	eor	w10, w10, w10, lsl #5
   12398:	4a0a354b 	eor	w11, w10, w10, lsl #13
   1239c:	b90285ca 	str	w10, [x14, #644]
   123a0:	4a4b456b 	eor	w11, w11, w11, lsr #17
   123a4:	4a0b156b 	eor	w11, w11, w11, lsl #5
   123a8:	4a0b356c 	eor	w12, w11, w11, lsl #13
   123ac:	b90289cb 	str	w11, [x14, #648]
   123b0:	4a4c458c 	eor	w12, w12, w12, lsr #17
   123b4:	4a0c158d 	eor	w13, w12, w12, lsl #5
   123b8:	b9028dcd 	str	w13, [x14, #652]
   123bc:	54fffda1 	b.ne	12370 <main+0x8cc>  // b.any
   123c0:	f100a37f 	cmp	x27, #0x28
   123c4:	54000242 	b.cs	1240c <main+0x968>  // b.hs, b.nlast
   123c8:	f94167e8 	ldr	x8, [sp, #712]
   123cc:	f94163e9 	ldr	x9, [sp, #704]
   123d0:	911293eb 	add	x11, sp, #0x4a4
   123d4:	f9415fea 	ldr	x10, [sp, #696]
   123d8:	b8687a68 	ldr	w8, [x19, x8, lsl #2]
   123dc:	b8697a69 	ldr	w9, [x19, x9, lsl #2]
   123e0:	b86a7a6a 	ldr	w10, [x19, x10, lsl #2]
   123e4:	b93ffd68 	str	w8, [x11, #16380]
   123e8:	f9415be8 	ldr	x8, [sp, #688]
   123ec:	b8687a6b 	ldr	w11, [x19, x8, lsl #2]
   123f0:	9112a3e8 	add	x8, sp, #0x4a8
   123f4:	b93ffd09 	str	w9, [x8, #16380]
   123f8:	9112b3e8 	add	x8, sp, #0x4ac
   123fc:	b93ffd0a 	str	w10, [x8, #16380]
   12400:	f94157e8 	ldr	x8, [sp, #680]
   12404:	b8687a68 	ldr	w8, [x19, x8, lsl #2]
   12408:	14000016 	b	12460 <main+0x9bc>
   1240c:	4a0d35a8 	eor	w8, w13, w13, lsl #13
   12410:	911293ed 	add	x13, sp, #0x4a4
   12414:	4a484508 	eor	w8, w8, w8, lsr #17
   12418:	4a081508 	eor	w8, w8, w8, lsl #5
   1241c:	4a083509 	eor	w9, w8, w8, lsl #13
   12420:	b93ffda8 	str	w8, [x13, #16380]
   12424:	4a494529 	eor	w9, w9, w9, lsr #17
   12428:	4a091529 	eor	w9, w9, w9, lsl #5
   1242c:	4a09352a 	eor	w10, w9, w9, lsl #13
   12430:	4a4a454a 	eor	w10, w10, w10, lsr #17
   12434:	4a0a154a 	eor	w10, w10, w10, lsl #5
   12438:	4a0a354b 	eor	w11, w10, w10, lsl #13
   1243c:	4a4b456b 	eor	w11, w11, w11, lsr #17
   12440:	4a0b156b 	eor	w11, w11, w11, lsl #5
   12444:	4a0b356c 	eor	w12, w11, w11, lsl #13
   12448:	4a4c4588 	eor	w8, w12, w12, lsr #17
   1244c:	9112a3ec 	add	x12, sp, #0x4a8
   12450:	b93ffd89 	str	w9, [x12, #16380]
   12454:	9112b3e9 	add	x9, sp, #0x4ac
   12458:	b93ffd2a 	str	w10, [x9, #16380]
   1245c:	4a081508 	eor	w8, w8, w8, lsl #5
   12460:	9112c3e9 	add	x9, sp, #0x4b0
   12464:	911303ea 	add	x10, sp, #0x4c0
   12468:	91400fe0 	add	x0, sp, #0x3, lsl #12
   1246c:	b93ffd2b 	str	w11, [x9, #16380]
   12470:	911403e9 	add	x9, sp, #0x500
   12474:	91008000 	add	x0, x0, #0x20
   12478:	4c402d20 	ld1	{v0.2d-v3.2d}, [x9]
   1247c:	f94197e9 	ldr	x9, [sp, #808]
   12480:	2a1f03e1 	mov	w1, wzr
   12484:	52820002 	mov	w2, #0x1000                	// #4096
   12488:	4c000a80 	st4	{v0.4s-v3.4s}, [x20]
   1248c:	4c402d40 	ld1	{v0.2d-v3.2d}, [x10]
   12490:	911203ea 	add	x10, sp, #0x480
   12494:	4c000920 	st4	{v0.4s-v3.4s}, [x9]
   12498:	4c402d40 	ld1	{v0.2d-v3.2d}, [x10]
   1249c:	f94193e9 	ldr	x9, [sp, #800]
   124a0:	911103ea 	add	x10, sp, #0x440
   124a4:	4c000920 	st4	{v0.4s-v3.4s}, [x9]
   124a8:	4c402d40 	ld1	{v0.2d-v3.2d}, [x10]
   124ac:	f9418fe9 	ldr	x9, [sp, #792]
   124b0:	911003ea 	add	x10, sp, #0x400
   124b4:	4c000920 	st4	{v0.4s-v3.4s}, [x9]
   124b8:	4c402d40 	ld1	{v0.2d-v3.2d}, [x10]
   124bc:	f9418be9 	ldr	x9, [sp, #784]
   124c0:	910f03ea 	add	x10, sp, #0x3c0
   124c4:	4c000920 	st4	{v0.4s-v3.4s}, [x9]
   124c8:	4c402d40 	ld1	{v0.2d-v3.2d}, [x10]
   124cc:	f94187e9 	ldr	x9, [sp, #776]
   124d0:	910e03ea 	add	x10, sp, #0x380
   124d4:	4c000920 	st4	{v0.4s-v3.4s}, [x9]
   124d8:	4c402d40 	ld1	{v0.2d-v3.2d}, [x10]
   124dc:	f94183e9 	ldr	x9, [sp, #768]
   124e0:	4c000920 	st4	{v0.4s-v3.4s}, [x9]
   124e4:	9112d3e9 	add	x9, sp, #0x4b4
   124e8:	b93ffd28 	str	w8, [x9, #16380]
   124ec:	52a7f408 	mov	w8, #0x3fa00000            	// #1067450368
   124f0:	9112e3e9 	add	x9, sp, #0x4b8
   124f4:	b93ffd28 	str	w8, [x9, #16380]
   124f8:	910593e8 	add	x8, sp, #0x164
   124fc:	9105d3e9 	add	x9, sp, #0x174
   12500:	b93ffd19 	str	w25, [x8, #16380]
   12504:	f942cfe8 	ldr	x8, [sp, #1432]
   12508:	b93ffd28 	str	w8, [x9, #16380]
   1250c:	910d03e9 	add	x9, sp, #0x340
   12510:	f9417fe8 	ldr	x8, [sp, #760]
   12514:	4c402d20 	ld1	{v0.2d-v3.2d}, [x9]
   12518:	4c000900 	st4	{v0.4s-v3.4s}, [x8]
   1251c:	9400099d 	bl	14b90 <memset@plt>
   12520:	b94553ea 	ldr	w10, [sp, #1360]
   12524:	b9454feb 	ldr	w11, [sp, #1356]
   12528:	91400fed 	add	x13, sp, #0x3, lsl #12
   1252c:	529f002e 	mov	w14, #0xf801                	// #63489
   12530:	aa1f03e8 	mov	x8, xzr
   12534:	aa1f03e9 	mov	x9, xzr
   12538:	910081ad 	add	x13, x13, #0x20
   1253c:	72a007ee 	movk	w14, #0x3f, lsl #16
   12540:	1400000d 	b	12574 <main+0xad0>
   12544:	9bae7d4c 	umull	x12, w10, w14
   12548:	f107ed3f 	cmp	x9, #0x1fb
   1254c:	d361fd8c 	lsr	x12, x12, #33
   12550:	0b0c2d8c 	add	w12, w12, w12, lsl #11
   12554:	4b0c016c 	sub	w12, w11, w12
   12558:	1e02f580 	scvtf	s0, w12, #3
   1255c:	bc2969a0 	str	s0, [x13, x9]
   12560:	540001e8 	b.hi	1259c <main+0xaf8>  // b.pmore
   12564:	91001129 	add	x9, x9, #0x4
   12568:	91000508 	add	x8, x8, #0x1
   1256c:	1101116b 	add	w11, w11, #0x44
   12570:	1101114a 	add	w10, w10, #0x44
   12574:	f101a37f 	cmp	x27, #0x68
   12578:	54fffe62 	b.cs	12544 <main+0xaa0>  // b.hs, b.nlast
   1257c:	927ced2c 	and	x12, x9, #0xfffffffffffffff0
   12580:	f107f13f 	cmp	x9, #0x1fc
   12584:	8b0c028c 	add	x12, x20, x12
   12588:	b37e050c 	bfi	x12, x8, #2, #2
   1258c:	b942818c 	ldr	w12, [x12, #640]
   12590:	b82969ac 	str	w12, [x13, x9]
   12594:	54fffe83 	b.cc	12564 <main+0xac0>  // b.lo, b.ul, b.last
   12598:	1400000c 	b	125c8 <main+0xb24>
   1259c:	910e93e8 	add	x8, sp, #0x3a4
   125a0:	b93ffd1f 	str	wzr, [x8, #16380]
   125a4:	910ea3e8 	add	x8, sp, #0x3a8
   125a8:	bd3ffd08 	str	s8, [x8, #16380]
   125ac:	910eb3e8 	add	x8, sp, #0x3ac
   125b0:	bd3ffd09 	str	s9, [x8, #16380]
   125b4:	b9433be8 	ldr	w8, [sp, #824]
   125b8:	11000508 	add	w8, w8, #0x1
   125bc:	b9033be8 	str	w8, [sp, #824]
   125c0:	910ec3e8 	add	x8, sp, #0x3b0
   125c4:	bd3ffd0a 	str	s10, [x8, #16380]
   125c8:	f942afea 	ldr	x10, [sp, #1368]
   125cc:	b94597e8 	ldr	w8, [sp, #1428]
   125d0:	91400be0 	add	x0, sp, #0x2, lsl #12
   125d4:	3dc0e280 	ldr	q0, [x20, #896]
   125d8:	914013e1 	add	x1, sp, #0x4, lsl #12
   125dc:	52806009 	mov	w9, #0x300                 	// #768
   125e0:	b9006148 	str	w8, [x10, #96]
   125e4:	f942cfe8 	ldr	x8, [sp, #1432]
   125e8:	912d8000 	add	x0, x0, #0xb60
   125ec:	91008021 	add	x1, x1, #0x20
   125f0:	52809802 	mov	w2, #0x4c0                 	// #1216
   125f4:	f92043f9 	str	x25, [sp, #16512]
   125f8:	f9203be8 	str	x8, [sp, #16496]
   125fc:	52808008 	mov	w8, #0x400                 	// #1024
   12600:	f92033e8 	str	x8, [sp, #16480]
   12604:	52820008 	mov	w8, #0x1000                	// #4096
   12608:	f920fbe8 	str	x8, [sp, #16880]
   1260c:	52806088 	mov	w8, #0x304                 	// #772
   12610:	f9204bff 	str	xzr, [sp, #16528]
   12614:	f92053fa 	str	x26, [sp, #16544]
   12618:	f9205be9 	str	x9, [sp, #16560]
   1261c:	f920cbe9 	str	x9, [sp, #16784]
   12620:	f920c3ff 	str	xzr, [sp, #16768]
   12624:	3d8081a0 	str	q0, [x13, #512]
   12628:	b900715f 	str	wzr, [x10, #112]
   1262c:	b900795f 	str	wzr, [x10, #120]
   12630:	b9008148 	str	w8, [x10, #128]
   12634:	9400095b 	bl	14ba0 <memcpy@plt>
   12638:	91400be0 	add	x0, sp, #0x2, lsl #12
   1263c:	914013e1 	add	x1, sp, #0x4, lsl #12
   12640:	52809802 	mov	w2, #0x4c0                 	// #1216
   12644:	911a8000 	add	x0, x0, #0x6a0
   12648:	91008021 	add	x1, x1, #0x20
   1264c:	94000955 	bl	14ba0 <memcpy@plt>
   12650:	914007e0 	add	x0, sp, #0x1, lsl #12
   12654:	91400fe1 	add	x1, sp, #0x3, lsl #12
   12658:	52820002 	mov	w2, #0x1000                	// #4096
   1265c:	911a8000 	add	x0, x0, #0x6a0
   12660:	91008021 	add	x1, x1, #0x20
   12664:	9400094f 	bl	14ba0 <memcpy@plt>
   12668:	91400fe1 	add	x1, sp, #0x3, lsl #12
   1266c:	911a83e0 	add	x0, sp, #0x6a0
   12670:	52820002 	mov	w2, #0x1000                	// #4096
   12674:	91008021 	add	x1, x1, #0x20
   12678:	9400094a 	bl	14ba0 <memcpy@plt>
   1267c:	6f00e400 	movi	v0.2d, #0x0
   12680:	914007e8 	add	x8, sp, #0x1, lsl #12
   12684:	d0000109 	adrp	x9, 34000 <_DYNAMIC+0xf378>
   12688:	911a8108 	add	x8, x8, #0x6a0
   1268c:	f90347ff 	str	xzr, [sp, #1672]
   12690:	f907c128 	str	x8, [x9, #3968]
   12694:	790d23ff 	strh	wzr, [sp, #1680]
   12698:	3d818be0 	str	q0, [sp, #1568]
   1269c:	3d818fe0 	str	q0, [sp, #1584]
   126a0:	3d8193e0 	str	q0, [sp, #1600]
   126a4:	3d8197e0 	str	q0, [sp, #1616]
   126a8:	3d819be0 	str	q0, [sp, #1632]
   126ac:	3d819fe0 	str	q0, [sp, #1648]
   126b0:	391a03ff 	strb	wzr, [sp, #1664]
   126b4:	91400be0 	add	x0, sp, #0x2, lsl #12
   126b8:	912d8000 	add	x0, x0, #0xb60
   126bc:	940001d6 	bl	12e14 <full_before_execute>
   126c0:	f90347e0 	str	x0, [sp, #1672]
   126c4:	391a43fa 	strb	w26, [sp, #1680]
   126c8:	6f00e400 	movi	v0.2d, #0x0
   126cc:	911a83e8 	add	x8, sp, #0x6a0
   126d0:	d0000109 	adrp	x9, 34000 <_DYNAMIC+0xf378>
   126d4:	f907c128 	str	x8, [x9, #3968]
   126d8:	f90307ff 	str	xzr, [sp, #1544]
   126dc:	790c23ff 	strh	wzr, [sp, #1552]
   126e0:	3d816be0 	str	q0, [sp, #1440]
   126e4:	3d816fe0 	str	q0, [sp, #1456]
   126e8:	3d8173e0 	str	q0, [sp, #1472]
   126ec:	3d8177e0 	str	q0, [sp, #1488]
   126f0:	3d817be0 	str	q0, [sp, #1504]
   126f4:	3d817fe0 	str	q0, [sp, #1520]
   126f8:	391803ff 	strb	wzr, [sp, #1536]
   126fc:	91400be0 	add	x0, sp, #0x2, lsl #12
   12700:	911a8000 	add	x0, x0, #0x6a0
   12704:	94000548 	bl	13c24 <full_after_execute>
   12708:	f90307e0 	str	x0, [sp, #1544]
   1270c:	391843fa 	strb	w26, [sp, #1552]
   12710:	395a43f9 	ldrb	w25, [sp, #1680]
   12714:	340002f9 	cbz	w25, 12770 <main+0xccc>
   12718:	5280006a 	mov	w10, #0x3                   	// #3
   1271c:	1400001f 	b	12798 <main+0xcf4>
   12720:	aa0103f7 	mov	x23, x1
   12724:	94000923 	bl	14bb0 <__cxa_begin_catch@plt>
   12728:	71000aff 	cmp	w23, #0x2
   1272c:	540001a1 	b.ne	12760 <main+0xcbc>  // b.any
   12730:	ad420400 	ldp	q0, q1, [x0, #64]
   12734:	f9403008 	ldr	x8, [x0, #96]
   12738:	f90303e8 	str	x8, [sp, #1536]
   1273c:	3d817be0 	str	q0, [sp, #1504]
   12740:	3d817fe1 	str	q1, [sp, #1520]
   12744:	ad400400 	ldp	q0, q1, [x0]
   12748:	3d816be0 	str	q0, [sp, #1440]
   1274c:	ad410800 	ldp	q0, q2, [x0, #32]
   12750:	3d816fe1 	str	q1, [sp, #1456]
   12754:	3d8177e2 	str	q2, [sp, #1488]
   12758:	3d8173e0 	str	q0, [sp, #1472]
   1275c:	14000002 	b	12764 <main+0xcc0>
   12760:	391847fa 	strb	w26, [sp, #1553]
   12764:	94000917 	bl	14bc0 <__cxa_end_catch@plt>
   12768:	395a43f9 	ldrb	w25, [sp, #1680]
   1276c:	35fffd79 	cbnz	w25, 12718 <main+0xc74>
   12770:	395a47e8 	ldrb	w8, [sp, #1681]
   12774:	5280004a 	mov	w10, #0x2                   	// #2
   12778:	35000108 	cbnz	w8, 12798 <main+0xcf4>
   1277c:	395a03e8 	ldrb	w8, [sp, #1664]
   12780:	340000c8 	cbz	w8, 12798 <main+0xcf4>
   12784:	f94313e8 	ldr	x8, [sp, #1568]
   12788:	f120411f 	cmp	x8, #0x810
   1278c:	1a9a0749 	cinc	w9, w26, ne	// ne = any
   12790:	f120011f 	cmp	x8, #0x800
   12794:	1a8903ea 	csel	w10, wzr, w9, eq	// eq = none
   12798:	395843fa 	ldrb	w26, [sp, #1552]
   1279c:	52800029 	mov	w9, #0x1                   	// #1
   127a0:	3400007a 	cbz	w26, 127ac <main+0xd08>
   127a4:	52800074 	mov	w20, #0x3                   	// #3
   127a8:	1400000b 	b	127d4 <main+0xd30>
   127ac:	395847e8 	ldrb	w8, [sp, #1553]
   127b0:	52800054 	mov	w20, #0x2                   	// #2
   127b4:	35000108 	cbnz	w8, 127d4 <main+0xd30>
   127b8:	395803e8 	ldrb	w8, [sp, #1536]
   127bc:	340000c8 	cbz	w8, 127d4 <main+0xd30>
   127c0:	f942d3e8 	ldr	x8, [sp, #1440]
   127c4:	f120411f 	cmp	x8, #0x810
   127c8:	1a890529 	cinc	w9, w9, ne	// ne = any
   127cc:	f120011f 	cmp	x8, #0x800
   127d0:	1a8903f4 	csel	w20, wzr, w9, eq	// eq = none
   127d4:	d37e7d48 	ubfiz	x8, x10, #2, #32
   127d8:	d37e7e89 	ubfiz	x9, x20, #2, #32
   127dc:	d10103ac 	sub	x12, x29, #0x40
   127e0:	d10143ad 	sub	x13, x29, #0x50
   127e4:	f902c3ea 	str	x10, [sp, #1408]
   127e8:	91400be0 	add	x0, sp, #0x2, lsl #12
   127ec:	b868698a 	ldr	w10, [x12, x8]
   127f0:	b86969ab 	ldr	w11, [x13, x9]
   127f4:	91400be1 	add	x1, sp, #0x2, lsl #12
   127f8:	912d8000 	add	x0, x0, #0xb60
   127fc:	911a8021 	add	x1, x1, #0x6a0
   12800:	52809802 	mov	w2, #0x4c0                 	// #1216
   12804:	1100054a 	add	w10, w10, #0x1
   12808:	b828698a 	str	w10, [x12, x8]
   1280c:	11000568 	add	w8, w11, #0x1
   12810:	b82969a8 	str	w8, [x13, x9]
   12814:	940008ef 	bl	14bd0 <bcmp@plt>
   12818:	2a0003f7 	mov	w23, w0
   1281c:	914007e0 	add	x0, sp, #0x1, lsl #12
   12820:	911a83e1 	add	x1, sp, #0x6a0
   12824:	911a8000 	add	x0, x0, #0x6a0
   12828:	52820002 	mov	w2, #0x1000                	// #4096
   1282c:	940008e9 	bl	14bd0 <bcmp@plt>
   12830:	6b1a033f 	cmp	w25, w26
   12834:	540001a1 	b.ne	12868 <main+0xdc4>  // b.any
   12838:	395a47e8 	ldrb	w8, [sp, #1681]
   1283c:	395847e9 	ldrb	w9, [sp, #1553]
   12840:	f942c3ee 	ldr	x14, [sp, #1408]
   12844:	6b09011f 	cmp	w8, w9
   12848:	54000741 	b.ne	12930 <main+0xe8c>  // b.any
   1284c:	34000159 	cbz	w25, 12874 <main+0xdd0>
   12850:	f94347e8 	ldr	x8, [sp, #1672]
   12854:	f94307e9 	ldr	x9, [sp, #1544]
   12858:	f942b3f9 	ldr	x25, [sp, #1376]
   1285c:	eb09011f 	cmp	x8, x9
   12860:	1a9f17e8 	cset	w8, eq	// eq = none
   12864:	14000035 	b	12938 <main+0xe94>
   12868:	f942b3f9 	ldr	x25, [sp, #1376]
   1286c:	f942c3ee 	ldr	x14, [sp, #1408]
   12870:	14000031 	b	12934 <main+0xe90>
   12874:	f94313e8 	ldr	x8, [sp, #1568]
   12878:	f942d3e9 	ldr	x9, [sp, #1440]
   1287c:	eb09011f 	cmp	x8, x9
   12880:	54000581 	b.ne	12930 <main+0xe8c>  // b.any
   12884:	f942d7e8 	ldr	x8, [sp, #1448]
   12888:	f94317e9 	ldr	x9, [sp, #1576]
   1288c:	f9431bea 	ldr	x10, [sp, #1584]
   12890:	f942dbeb 	ldr	x11, [sp, #1456]
   12894:	f942dfec 	ldr	x12, [sp, #1464]
   12898:	f942e3ed 	ldr	x13, [sp, #1472]
   1289c:	eb08013f 	cmp	x9, x8
   128a0:	f9431fe8 	ldr	x8, [sp, #1592]
   128a4:	f94323e9 	ldr	x9, [sp, #1600]
   128a8:	fa4b0140 	ccmp	x10, x11, #0x0, eq	// eq = none
   128ac:	f942e7ea 	ldr	x10, [sp, #1480]
   128b0:	f9432beb 	ldr	x11, [sp, #1616]
   128b4:	fa4c0100 	ccmp	x8, x12, #0x0, eq	// eq = none
   128b8:	f94327e8 	ldr	x8, [sp, #1608]
   128bc:	f942ebec 	ldr	x12, [sp, #1488]
   128c0:	fa4d0120 	ccmp	x9, x13, #0x0, eq	// eq = none
   128c4:	f942efe9 	ldr	x9, [sp, #1496]
   128c8:	f942f3ed 	ldr	x13, [sp, #1504]
   128cc:	fa4a0100 	ccmp	x8, x10, #0x0, eq	// eq = none
   128d0:	f9432fe8 	ldr	x8, [sp, #1624]
   128d4:	f94333ea 	ldr	x10, [sp, #1632]
   128d8:	fa4c0160 	ccmp	x11, x12, #0x0, eq	// eq = none
   128dc:	f942b3f9 	ldr	x25, [sp, #1376]
   128e0:	fa490100 	ccmp	x8, x9, #0x0, eq	// eq = none
   128e4:	fa4d0140 	ccmp	x10, x13, #0x0, eq	// eq = none
   128e8:	54000261 	b.ne	12934 <main+0xe90>  // b.any
   128ec:	f94337e8 	ldr	x8, [sp, #1640]
   128f0:	f942f7e9 	ldr	x9, [sp, #1512]
   128f4:	eb09011f 	cmp	x8, x9
   128f8:	540001e1 	b.ne	12934 <main+0xe90>  // b.any
   128fc:	f9433be8 	ldr	x8, [sp, #1648]
   12900:	f942fbe9 	ldr	x9, [sp, #1520]
   12904:	eb09011f 	cmp	x8, x9
   12908:	54000161 	b.ne	12934 <main+0xe90>  // b.any
   1290c:	f9433fe8 	ldr	x8, [sp, #1656]
   12910:	f942ffe9 	ldr	x9, [sp, #1528]
   12914:	eb09011f 	cmp	x8, x9
   12918:	540000e1 	b.ne	12934 <main+0xe90>  // b.any
   1291c:	395a03e8 	ldrb	w8, [sp, #1664]
   12920:	395803e9 	ldrb	w9, [sp, #1536]
   12924:	6b09011f 	cmp	w8, w9
   12928:	1a9f17e8 	cset	w8, eq	// eq = none
   1292c:	14000003 	b	12938 <main+0xe94>
   12930:	f942b3f9 	ldr	x25, [sp, #1376]
   12934:	2a1f03e8 	mov	w8, wzr
   12938:	b9457be9 	ldr	w9, [sp, #1400]
   1293c:	710002ff 	cmp	w23, #0x0
   12940:	2a1403ea 	mov	w10, w20
   12944:	1a9f07f1 	cset	w17, ne	// ne = any
   12948:	2a0e014c 	orr	w12, w10, w14
   1294c:	1a890529 	cinc	w9, w9, ne	// ne = any
   12950:	7100001f 	cmp	w0, #0x0
   12954:	b9057be9 	str	w9, [sp, #1400]
   12958:	2a0002e9 	orr	w9, w23, w0
   1295c:	52000100 	eor	w0, w8, #0x1
   12960:	b94577e8 	ldr	w8, [sp, #1396]
   12964:	1a9f07f2 	cset	w18, ne	// ne = any
   12968:	1a880508 	cinc	w8, w8, ne	// ne = any
   1296c:	7100059f 	cmp	w12, #0x1
   12970:	b90577e8 	str	w8, [sp, #1396]
   12974:	b9457fe8 	ldr	w8, [sp, #1404]
   12978:	1a9f97e1 	cset	w1, hi	// hi = pmore
   1297c:	1a889508 	cinc	w8, w8, hi	// hi = pmore
   12980:	7100013f 	cmp	w9, #0x0
   12984:	b9057fe8 	str	w8, [sp, #1404]
   12988:	b94557e8 	ldr	w8, [sp, #1364]
   1298c:	1a9f040b 	csinc	w11, w0, wzr, eq	// eq = none
   12990:	340001e8 	cbz	w8, 129cc <main+0xf28>
   12994:	f942cfe8 	ldr	x8, [sp, #1432]
   12998:	b94597e9 	ldr	w9, [sp, #1428]
   1299c:	7104011f 	cmp	w8, #0x100
   129a0:	528468a8 	mov	w8, #0x2345                	// #9029
   129a4:	72aff828 	movk	w8, #0x7fc1, lsl #16
   129a8:	7a480120 	ccmp	w9, w8, #0x0, eq	// eq = none
   129ac:	1a9f17fa 	cset	w26, eq	// eq = none
   129b0:	3700012b 	tbnz	w11, #0, 129d4 <main+0xf30>
   129b4:	b94593e8 	ldr	w8, [sp, #1424]
   129b8:	7100059f 	cmp	w12, #0x1
   129bc:	7a4c8902 	ccmp	w8, #0xc, #0x2, hi	// hi = pmore
   129c0:	1a9f2748 	csinc	w8, w26, wzr, cs	// cs = hs, nlast
   129c4:	3607c008 	tbz	w8, #0, 121c4 <main+0x720>
   129c8:	14000008 	b	129e8 <main+0xf44>
   129cc:	2a1f03fa 	mov	w26, wzr
   129d0:	3607ff2b 	tbz	w11, #0, 129b4 <main+0xf10>
   129d4:	b94593e8 	ldr	w8, [sp, #1424]
   129d8:	7100311f 	cmp	w8, #0xc
   129dc:	1a9f2748 	csinc	w8, w26, wzr, cs	// cs = hs, nlast
   129e0:	7100051f 	cmp	w8, #0x1
   129e4:	54ffbf01 	b.ne	121c4 <main+0x720>  // b.any
   129e8:	d503201f 	nop
   129ec:	100913e8 	adr	x8, 24c68 <route_name(unsigned int)::names>
   129f0:	b902ebe1 	str	w1, [sp, #744]
   129f4:	f86e5906 	ldr	x6, [x8, w14, uxtw #3]
   129f8:	f86a7907 	ldr	x7, [x8, x10, lsl #3]
   129fc:	b9001be1 	str	w1, [sp, #24]
   12a00:	b9458fe1 	ldr	w1, [sp, #1420]
   12a04:	b94597e5 	ldr	w5, [sp, #1428]
   12a08:	2a1b03e2 	mov	w2, w27
   12a0c:	b902efe0 	str	w0, [sp, #748]
   12a10:	2a1903e3 	mov	w3, w25
   12a14:	f942cfe4 	ldr	x4, [sp, #1432]
   12a18:	b90013e0 	str	w0, [sp, #16]
   12a1c:	f0ffff60 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   12a20:	910ad800 	add	x0, x0, #0x2b6
   12a24:	b902dbec 	str	w12, [sp, #728]
   12a28:	b902dfeb 	str	w11, [sp, #732]
   12a2c:	f90173ea 	str	x10, [sp, #736]
   12a30:	b902f3f2 	str	w18, [sp, #752]
   12a34:	b9000bf2 	str	w18, [sp, #8]
   12a38:	b902f7f1 	str	w17, [sp, #756]
   12a3c:	b90003f1 	str	w17, [sp]
   12a40:	9400084c 	bl	14b70 <printf@plt>
   12a44:	91400bea 	add	x10, sp, #0x2, lsl #12
   12a48:	91400beb 	add	x11, sp, #0x2, lsl #12
   12a4c:	aa1f03f7 	mov	x23, xzr
   12a50:	911a814a 	add	x10, x10, #0x6a0
   12a54:	912d816b 	add	x11, x11, #0xb60
   12a58:	911a83ec 	add	x12, sp, #0x6a0
   12a5c:	38776968 	ldrb	w8, [x11, x23]
   12a60:	38776949 	ldrb	w9, [x10, x23]
   12a64:	6b09011f 	cmp	w8, w9
   12a68:	54000081 	b.ne	12a78 <main+0xfd4>  // b.any
   12a6c:	910006f7 	add	x23, x23, #0x1
   12a70:	f11302ff 	cmp	x23, #0x4c0
   12a74:	54ffff41 	b.ne	12a5c <main+0xfb8>  // b.any
   12a78:	914007ea 	add	x10, sp, #0x1, lsl #12
   12a7c:	aa1f03f9 	mov	x25, xzr
   12a80:	911a814a 	add	x10, x10, #0x6a0
   12a84:	38796948 	ldrb	w8, [x10, x25]
   12a88:	38796989 	ldrb	w9, [x12, x25]
   12a8c:	6b09011f 	cmp	w8, w9
   12a90:	54000081 	b.ne	12aa0 <main+0xffc>  // b.any
   12a94:	91000739 	add	x25, x25, #0x1
   12a98:	f140073f 	cmp	x25, #0x1, lsl #12
   12a9c:	54ffff41 	b.ne	12a84 <main+0xfe0>  // b.any
   12aa0:	91400bfc 	add	x28, sp, #0x2, lsl #12
   12aa4:	91400bf4 	add	x20, sp, #0x2, lsl #12
   12aa8:	f0ffff60 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   12aac:	9104b000 	add	x0, x0, #0x12c
   12ab0:	aa1703e1 	mov	x1, x23
   12ab4:	52809802 	mov	w2, #0x4c0                 	// #1216
   12ab8:	aa1903e3 	mov	x3, x25
   12abc:	912d839c 	add	x28, x28, #0xb60
   12ac0:	911a8294 	add	x20, x20, #0x6a0
   12ac4:	9400082b 	bl	14b70 <printf@plt>
   12ac8:	f112feff 	cmp	x23, #0x4bf
   12acc:	540000c8 	b.hi	12ae4 <main+0x1040>  // b.pmore
   12ad0:	38776b81 	ldrb	w1, [x28, x23]
   12ad4:	38776a82 	ldrb	w2, [x20, x23]
   12ad8:	f0ffff60 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   12adc:	91006800 	add	x0, x0, #0x1a
   12ae0:	94000824 	bl	14b70 <printf@plt>
   12ae4:	f13fff3f 	cmp	x25, #0xfff
   12ae8:	54000128 	b.hi	12b0c <main+0x1068>  // b.pmore
   12aec:	914007e8 	add	x8, sp, #0x1, lsl #12
   12af0:	f0ffff60 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   12af4:	91084000 	add	x0, x0, #0x210
   12af8:	911a8108 	add	x8, x8, #0x6a0
   12afc:	38796901 	ldrb	w1, [x8, x25]
   12b00:	911a83e8 	add	x8, sp, #0x6a0
   12b04:	38796902 	ldrb	w2, [x8, x25]
   12b08:	9400081a 	bl	14b70 <printf@plt>
   12b0c:	f94147f9 	ldr	x25, [sp, #648]
   12b10:	f9414bf4 	ldr	x20, [sp, #656]
   12b14:	aa1f03f7 	mov	x23, xzr
   12b18:	1400001e 	b	12b90 <main+0x10ec>
   12b1c:	d0ffff7c 	adrp	x28, 0 <__abi_tag-0x2c4>
   12b20:	9138ab9c 	add	x28, x28, #0xe2a
   12b24:	2a1703e1 	mov	w1, w23
   12b28:	aa1c03e0 	mov	x0, x28
   12b2c:	2a1f03e2 	mov	w2, wzr
   12b30:	94000810 	bl	14b70 <printf@plt>
   12b34:	b85f8323 	ldur	w3, [x25, #-8]
   12b38:	b85f8284 	ldur	w4, [x20, #-8]
   12b3c:	aa1c03e0 	mov	x0, x28
   12b40:	2a1703e1 	mov	w1, w23
   12b44:	52800022 	mov	w2, #0x1                   	// #1
   12b48:	9400080a 	bl	14b70 <printf@plt>
   12b4c:	b85fc323 	ldur	w3, [x25, #-4]
   12b50:	b85fc284 	ldur	w4, [x20, #-4]
   12b54:	aa1c03e0 	mov	x0, x28
   12b58:	2a1703e1 	mov	w1, w23
   12b5c:	52800042 	mov	w2, #0x2                   	// #2
   12b60:	94000804 	bl	14b70 <printf@plt>
   12b64:	b9400323 	ldr	w3, [x25]
   12b68:	b9400284 	ldr	w4, [x20]
   12b6c:	aa1c03e0 	mov	x0, x28
   12b70:	2a1703e1 	mov	w1, w23
   12b74:	52800062 	mov	w2, #0x3                   	// #3
   12b78:	940007fe 	bl	14b70 <printf@plt>
   12b7c:	910006f7 	add	x23, x23, #0x1
   12b80:	91004294 	add	x20, x20, #0x10
   12b84:	91004339 	add	x25, x25, #0x10
   12b88:	f10082ff 	cmp	x23, #0x20
   12b8c:	54ffa900 	b.eq	120ac <main+0x608>  // b.none
   12b90:	b85f4323 	ldur	w3, [x25, #-12]
   12b94:	b85f4284 	ldur	w4, [x20, #-12]
   12b98:	3707fc3a 	tbnz	w26, #0, 12b1c <main+0x1078>
   12b9c:	6b04007f 	cmp	w3, w4
   12ba0:	540001c1 	b.ne	12bd8 <main+0x1134>  // b.any
   12ba4:	b85f8323 	ldur	w3, [x25, #-8]
   12ba8:	b85f8284 	ldur	w4, [x20, #-8]
   12bac:	6b04007f 	cmp	w3, w4
   12bb0:	54000261 	b.ne	12bfc <main+0x1158>  // b.any
   12bb4:	b85fc323 	ldur	w3, [x25, #-4]
   12bb8:	b85fc284 	ldur	w4, [x20, #-4]
   12bbc:	6b04007f 	cmp	w3, w4
   12bc0:	54000301 	b.ne	12c20 <main+0x117c>  // b.any
   12bc4:	b9400323 	ldr	w3, [x25]
   12bc8:	b9400284 	ldr	w4, [x20]
   12bcc:	6b04007f 	cmp	w3, w4
   12bd0:	54fffd60 	b.eq	12b7c <main+0x10d8>  // b.none
   12bd4:	1400001c 	b	12c44 <main+0x11a0>
   12bd8:	d0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   12bdc:	9138a800 	add	x0, x0, #0xe2a
   12be0:	2a1703e1 	mov	w1, w23
   12be4:	2a1f03e2 	mov	w2, wzr
   12be8:	940007e2 	bl	14b70 <printf@plt>
   12bec:	b85f8323 	ldur	w3, [x25, #-8]
   12bf0:	b85f8284 	ldur	w4, [x20, #-8]
   12bf4:	6b04007f 	cmp	w3, w4
   12bf8:	54fffde0 	b.eq	12bb4 <main+0x1110>  // b.none
   12bfc:	d0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   12c00:	9138a800 	add	x0, x0, #0xe2a
   12c04:	2a1703e1 	mov	w1, w23
   12c08:	52800022 	mov	w2, #0x1                   	// #1
   12c0c:	940007d9 	bl	14b70 <printf@plt>
   12c10:	b85fc323 	ldur	w3, [x25, #-4]
   12c14:	b85fc284 	ldur	w4, [x20, #-4]
   12c18:	6b04007f 	cmp	w3, w4
   12c1c:	54fffd40 	b.eq	12bc4 <main+0x1120>  // b.none
   12c20:	d0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   12c24:	9138a800 	add	x0, x0, #0xe2a
   12c28:	2a1703e1 	mov	w1, w23
   12c2c:	52800042 	mov	w2, #0x2                   	// #2
   12c30:	940007d0 	bl	14b70 <printf@plt>
   12c34:	b9400323 	ldr	w3, [x25]
   12c38:	b9400284 	ldr	w4, [x20]
   12c3c:	6b04007f 	cmp	w3, w4
   12c40:	54fff9e0 	b.eq	12b7c <main+0x10d8>  // b.none
   12c44:	d0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   12c48:	9138a800 	add	x0, x0, #0xe2a
   12c4c:	17ffffc9 	b	12b70 <main+0x10cc>
   12c50:	aa0103f7 	mov	x23, x1
   12c54:	940007d7 	bl	14bb0 <__cxa_begin_catch@plt>
   12c58:	71000aff 	cmp	w23, #0x2
   12c5c:	540001a1 	b.ne	12c90 <main+0x11ec>  // b.any
   12c60:	ad420400 	ldp	q0, q1, [x0, #64]
   12c64:	f9403008 	ldr	x8, [x0, #96]
   12c68:	f90343e8 	str	x8, [sp, #1664]
   12c6c:	3d819be0 	str	q0, [sp, #1632]
   12c70:	3d819fe1 	str	q1, [sp, #1648]
   12c74:	ad400400 	ldp	q0, q1, [x0]
   12c78:	3d818be0 	str	q0, [sp, #1568]
   12c7c:	ad410800 	ldp	q0, q2, [x0, #32]
   12c80:	3d818fe1 	str	q1, [sp, #1584]
   12c84:	3d8197e2 	str	q2, [sp, #1616]
   12c88:	3d8193e0 	str	q0, [sp, #1600]
   12c8c:	14000002 	b	12c94 <main+0x11f0>
   12c90:	391a47fa 	strb	w26, [sp, #1681]
   12c94:	940007cb 	bl	14bc0 <__cxa_end_catch@plt>
   12c98:	17fffe8c 	b	126c8 <main+0xc24>
   12c9c:	aa1703e0 	mov	x0, x23
   12ca0:	940007d0 	bl	14be0 <ferror@plt>
   12ca4:	2a0003f4 	mov	w20, w0
   12ca8:	aa1703e0 	mov	x0, x23
   12cac:	940007d1 	bl	14bf0 <fclose@plt>
   12cb0:	29780fa2 	ldp	w2, w3, [x29, #-64]
   12cb4:	297917a4 	ldp	w4, w5, [x29, #-56]
   12cb8:	29765fb6 	ldp	w22, w23, [x29, #-80]
   12cbc:	29776bb9 	ldp	w25, w26, [x29, #-72]
   12cc0:	2a140013 	orr	w19, w0, w20
   12cc4:	d0ffff74 	adrp	x20, 0 <__abi_tag-0x2c4>
   12cc8:	913e3e94 	add	x20, x20, #0xf8f
   12ccc:	f0ffff61 	adrp	x1, 1000 <typeinfo name for Boundary+0x1e0>
   12cd0:	9109c821 	add	x1, x1, #0x272
   12cd4:	aa1403e0 	mov	x0, x20
   12cd8:	940007a6 	bl	14b70 <printf@plt>
   12cdc:	f0ffff61 	adrp	x1, 1000 <typeinfo name for Boundary+0x1e0>
   12ce0:	910fd421 	add	x1, x1, #0x3f5
   12ce4:	aa1403e0 	mov	x0, x20
   12ce8:	2a1603e2 	mov	w2, w22
   12cec:	2a1703e3 	mov	w3, w23
   12cf0:	2a1903e4 	mov	w4, w25
   12cf4:	2a1a03e5 	mov	w5, w26
   12cf8:	9400079e 	bl	14b70 <printf@plt>
   12cfc:	b94593f4 	ldr	w20, [sp, #1424]
   12d00:	b9457ff5 	ldr	w21, [sp, #1404]
   12d04:	7100027f 	cmp	w19, #0x0
   12d08:	b9458fe1 	ldr	w1, [sp, #1420]
   12d0c:	b9433be2 	ldr	w2, [sp, #824]
   12d10:	1a9f07e8 	cset	w8, ne	// ne = any
   12d14:	b9457be4 	ldr	w4, [sp, #1400]
   12d18:	b94577e5 	ldr	w5, [sp, #1396]
   12d1c:	f0ffff60 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   12d20:	910cdc00 	add	x0, x0, #0x337
   12d24:	b94573e6 	ldr	w6, [sp, #1392]
   12d28:	2a1403e3 	mov	w3, w20
   12d2c:	2a1503e7 	mov	w7, w21
   12d30:	b90003e8 	str	w8, [sp]
   12d34:	9400078f 	bl	14b70 <printf@plt>
   12d38:	2a150268 	orr	w8, w19, w21
   12d3c:	f0ffff69 	adrp	x9, 1000 <typeinfo name for Boundary+0x1e0>
   12d40:	9109e529 	add	x9, x9, #0x279
   12d44:	f0ffff6a 	adrp	x10, 1000 <typeinfo name for Boundary+0x1e0>
   12d48:	910f994a 	add	x10, x10, #0x3e6
   12d4c:	7100029f 	cmp	w20, #0x0
   12d50:	9a890149 	csel	x9, x10, x9, eq	// eq = none
   12d54:	1a9f07ea 	cset	w10, ne	// ne = any
   12d58:	7100011f 	cmp	w8, #0x0
   12d5c:	f0ffff68 	adrp	x8, 1000 <typeinfo name for Boundary+0x1e0>
   12d60:	910fed08 	add	x8, x8, #0x3fb
   12d64:	f0ffff60 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   12d68:	9107a800 	add	x0, x0, #0x1ea
   12d6c:	9a880121 	csel	x1, x9, x8, eq	// eq = none
   12d70:	52800048 	mov	w8, #0x2                   	// #2
   12d74:	1a880153 	csel	w19, w10, w8, eq	// eq = none
   12d78:	9400077e 	bl	14b70 <printf@plt>
   12d7c:	2a1303e0 	mov	w0, w19
   12d80:	914013ff 	add	sp, sp, #0x4, lsl #12
   12d84:	911443ff 	add	sp, sp, #0x510
   12d88:	a9474ff4 	ldp	x20, x19, [sp, #112]
   12d8c:	a94657f6 	ldp	x22, x21, [sp, #96]
   12d90:	a9455ff8 	ldp	x24, x23, [sp, #80]
   12d94:	a94467fa 	ldp	x26, x25, [sp, #64]
   12d98:	a9436ffc 	ldp	x28, x27, [sp, #48]
   12d9c:	a9427bfd 	ldp	x29, x30, [sp, #32]
   12da0:	6d4123e9 	ldp	d9, d8, [sp, #16]
   12da4:	fc4807ea 	ldr	d10, [sp], #128
   12da8:	d65f03c0 	ret
   12dac:	d503201f 	nop
   12db0:	70f70af3 	adr	x19, f0f <typeinfo name for Boundary+0xef>
   12db4:	f0ffff61 	adrp	x1, 1000 <typeinfo name for Boundary+0x1e0>
   12db8:	910f9021 	add	x1, x1, #0x3e4
   12dbc:	aa1303e0 	mov	x0, x19
   12dc0:	94000764 	bl	14b50 <fopen@plt>
   12dc4:	b5ff6960 	cbnz	x0, 11af0 <main+0x4c>
   12dc8:	aa1303e0 	mov	x0, x19
   12dcc:	9400078d 	bl	14c00 <perror@plt>
   12dd0:	52800053 	mov	w19, #0x2                   	// #2
   12dd4:	17ffffea 	b	12d7c <main+0x12d8>

0000000000012dd8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>:
   12dd8:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   12ddc:	910003fd 	mov	x29, sp
   12de0:	d0000088 	adrp	x8, 24000 <__getauxval@plt+0xf3d0>
   12de4:	aa0403e6 	mov	x6, x4
   12de8:	aa0303e5 	mov	x5, x3
   12dec:	f9474d08 	ldr	x8, [x8, #3736]
   12df0:	2a0203e4 	mov	w4, w2
   12df4:	aa0103e3 	mov	x3, x1
   12df8:	aa0003e2 	mov	x2, x0
   12dfc:	d503201f 	nop
   12e00:	10f72901 	adr	x1, 1320 <typeinfo name for Boundary+0x500>
   12e04:	f9400108 	ldr	x8, [x8]
   12e08:	aa0803e0 	mov	x0, x8
   12e0c:	9400075d 	bl	14b80 <fprintf@plt>
   12e10:	94000738 	bl	14af0 <abort@plt>

0000000000012e14 <full_before_execute>:
   12e14:	d10303ff 	sub	sp, sp, #0xc0
   12e18:	fd0023ea 	str	d10, [sp, #64]
   12e1c:	6d0523e9 	stp	d9, d8, [sp, #80]
   12e20:	a9067bfd 	stp	x29, x30, [sp, #96]
   12e24:	a9076ffc 	stp	x28, x27, [sp, #112]
   12e28:	a90867fa 	stp	x26, x25, [sp, #128]
   12e2c:	a9095ff8 	stp	x24, x23, [sp, #144]
   12e30:	a90a57f6 	stp	x22, x21, [sp, #160]
   12e34:	a90b4ff4 	stp	x20, x19, [sp, #176]
   12e38:	910183fd 	add	x29, sp, #0x60
   12e3c:	aa0003f4 	mov	x20, x0
   12e40:	94000774 	bl	14c10 <std::chrono::_V2::steady_clock::now()@plt>
   12e44:	f81e83a0 	stur	x0, [x29, #-24]
   12e48:	d0000101 	adrp	x1, 34000 <_DYNAMIC+0xf378>
   12e4c:	913ea021 	add	x1, x1, #0xfa8
   12e50:	52800020 	mov	w0, #0x1                   	// #1
   12e54:	940006ff 	bl	14a50 <__aarch64_ldadd8_relax>
   12e58:	d0000099 	adrp	x25, 24000 <__getauxval@plt+0xf3d0>
   12e5c:	f940ea88 	ldr	x8, [x20, #464]
   12e60:	aa1403fa 	mov	x26, x20
   12e64:	f9474339 	ldr	x25, [x25, #3712]
   12e68:	f940fa8a 	ldr	x10, [x20, #496]
   12e6c:	f000011c 	adrp	x28, 35000 <full_before_g_spart_prof+0x78>
   12e70:	d1028108 	sub	x8, x8, #0xa0
   12e74:	f9400329 	ldr	x9, [x25]
   12e78:	f900ea88 	str	x8, [x20, #464]
   12e7c:	f828492a 	str	x10, [x9, w8, uxtw]
   12e80:	f9400328 	ldr	x8, [x25]
   12e84:	b941d289 	ldr	w9, [x20, #464]
   12e88:	f940f28a 	ldr	x10, [x20, #480]
   12e8c:	8b090108 	add	x8, x8, x9
   12e90:	f900050a 	str	x10, [x8, #8]
   12e94:	b941d288 	ldr	w8, [x20, #464]
   12e98:	f940ca89 	ldr	x9, [x20, #400]
   12e9c:	f940032a 	ldr	x10, [x25]
   12ea0:	3dc04280 	ldr	q0, [x20, #256]
   12ea4:	1100c108 	add	w8, w8, #0x30
   12ea8:	f900f289 	str	x9, [x20, #480]
   12eac:	927c6d08 	and	x8, x8, #0xfffffff0
   12eb0:	3ca86940 	str	q0, [x10, x8]
   12eb4:	b941d288 	ldr	w8, [x20, #464]
   12eb8:	f9400329 	ldr	x9, [x25]
   12ebc:	3dc04680 	ldr	q0, [x20, #272]
   12ec0:	11010108 	add	w8, w8, #0x40
   12ec4:	927c6d08 	and	x8, x8, #0xfffffff0
   12ec8:	3ca86920 	str	q0, [x9, x8]
   12ecc:	b941d288 	ldr	w8, [x20, #464]
   12ed0:	f9400329 	ldr	x9, [x25]
   12ed4:	3dc04a80 	ldr	q0, [x20, #288]
   12ed8:	11014108 	add	w8, w8, #0x50
   12edc:	927c6d08 	and	x8, x8, #0xfffffff0
   12ee0:	3ca86920 	str	q0, [x9, x8]
   12ee4:	b941d288 	ldr	w8, [x20, #464]
   12ee8:	f9400329 	ldr	x9, [x25]
   12eec:	3dc04e80 	ldr	q0, [x20, #304]
   12ef0:	11018108 	add	w8, w8, #0x60
   12ef4:	927c6d08 	and	x8, x8, #0xfffffff0
   12ef8:	3ca86920 	str	q0, [x9, x8]
   12efc:	b941d288 	ldr	w8, [x20, #464]
   12f00:	f9400329 	ldr	x9, [x25]
   12f04:	3dc05280 	ldr	q0, [x20, #320]
   12f08:	1101c108 	add	w8, w8, #0x70
   12f0c:	927c6d08 	and	x8, x8, #0xfffffff0
   12f10:	3ca86920 	str	q0, [x9, x8]
   12f14:	b941d288 	ldr	w8, [x20, #464]
   12f18:	f9400329 	ldr	x9, [x25]
   12f1c:	3dc05680 	ldr	q0, [x20, #336]
   12f20:	11020108 	add	w8, w8, #0x80
   12f24:	927c6d08 	and	x8, x8, #0xfffffff0
   12f28:	3ca86920 	str	q0, [x9, x8]
   12f2c:	b941d288 	ldr	w8, [x20, #464]
   12f30:	f9400329 	ldr	x9, [x25]
   12f34:	3dc07280 	ldr	q0, [x20, #448]
   12f38:	11024108 	add	w8, w8, #0x90
   12f3c:	927c6d08 	and	x8, x8, #0xfffffff0
   12f40:	3ca86920 	str	q0, [x9, x8]
   12f44:	f8440f48 	ldr	x8, [x26, #64]!
   12f48:	f9400b49 	ldr	x9, [x26, #16]
   12f4c:	f940134a 	ldr	x10, [x26, #32]
   12f50:	f900e288 	str	x8, [x20, #448]
   12f54:	f9401b48 	ldr	x8, [x26, #48]
   12f58:	f900aa89 	str	x9, [x20, #336]
   12f5c:	f9402349 	ldr	x9, [x26, #64]
   12f60:	f900a28a 	str	x10, [x20, #320]
   12f64:	f940ea8a 	ldr	x10, [x20, #464]
   12f68:	f9008288 	str	x8, [x20, #256]
   12f6c:	f9402b48 	ldr	x8, [x26, #80]
   12f70:	f9009a89 	str	x9, [x20, #304]
   12f74:	f9400329 	ldr	x9, [x25]
   12f78:	9100414a 	add	x10, x10, #0x10
   12f7c:	f9009288 	str	x8, [x20, #288]
   12f80:	927c6d48 	and	x8, x10, #0xfffffff0
   12f84:	8b080128 	add	x8, x9, x8
   12f88:	f9008a8a 	str	x10, [x20, #272]
   12f8c:	a9007d1f 	stp	xzr, xzr, [x8]
   12f90:	f9402788 	ldr	x8, [x28, #72]
   12f94:	b9800108 	ldrsw	x8, [x8]
   12f98:	72000d1f 	tst	w8, #0xf
   12f9c:	f81f0348 	stur	x8, [x26, #-16]
   12fa0:	54006221 	b.ne	13be4 <full_before_execute+0xdd0>  // b.any
   12fa4:	f9400329 	ldr	x9, [x25]
   12fa8:	927c6d08 	and	x8, x8, #0xfffffff0
   12fac:	2f00e408 	movi	d8, #0x0
   12fb0:	2f00e409 	movi	d9, #0x0
   12fb4:	1e2e100a 	fmov	s10, #1.000000000000000000e+00
   12fb8:	d0000117 	adrp	x23, 34000 <_DYNAMIC+0xf378>
   12fbc:	913f22f7 	add	x23, x23, #0xfc8
   12fc0:	3ce86920 	ldr	q0, [x9, x8]
   12fc4:	b941d288 	ldr	w8, [x20, #464]
   12fc8:	910b135b 	add	x27, x26, #0x2c4
   12fcc:	92800015 	mov	x21, #0xffffffffffffffff    	// #-1
   12fd0:	f0000116 	adrp	x22, 35000 <full_before_g_spart_prof+0x78>
   12fd4:	3d80e280 	str	q0, [x20, #896]
   12fd8:	11008108 	add	w8, w8, #0x20
   12fdc:	f941c68a 	ldr	x10, [x20, #904]
   12fe0:	394e028b 	ldrb	w11, [x20, #896]
   12fe4:	927c6d08 	and	x8, x8, #0xfffffff0
   12fe8:	8b080128 	add	x8, x9, x8
   12fec:	a9032a8b 	stp	x11, x10, [x20, #48]
   12ff0:	a900290b 	stp	x11, x10, [x8]
   12ff4:	f940aa93 	ldr	x19, [x20, #336]
   12ff8:	1400000e 	b	13030 <full_before_execute+0x21c>
   12ffc:	f9409a88 	ldr	x8, [x20, #304]
   13000:	f940aa89 	ldr	x9, [x20, #336]
   13004:	f940a28a 	ldr	x10, [x20, #320]
   13008:	f940828b 	ldr	x11, [x20, #256]
   1300c:	f1000508 	subs	x8, x8, #0x1
   13010:	91024133 	add	x19, x9, #0x90
   13014:	f9009a88 	str	x8, [x20, #304]
   13018:	9100c148 	add	x8, x10, #0x30
   1301c:	91000578 	add	x24, x11, #0x1
   13020:	f900aa93 	str	x19, [x20, #336]
   13024:	f900a288 	str	x8, [x20, #320]
   13028:	f9008298 	str	x24, [x20, #256]
   1302c:	54005420 	b.eq	13ab0 <full_before_execute+0xc9c>  // b.none
   13030:	52800020 	mov	w0, #0x1                   	// #1
   13034:	aa1703e1 	mov	x1, x23
   13038:	94000686 	bl	14a50 <__aarch64_ldadd8_relax>
   1303c:	f9400325 	ldr	x5, [x25]
   13040:	92407e69 	and	x9, x19, #0xffffffff
   13044:	b941728b 	ldr	w11, [x20, #368]
   13048:	8b0900a8 	add	x8, x5, x9
   1304c:	b980810a 	ldrsw	x10, [x8, #128]
   13050:	6b0b015f 	cmp	w10, w11
   13054:	f9001a8a 	str	x10, [x20, #48]
   13058:	54fffd20 	b.eq	12ffc <full_before_execute+0x1e8>  // b.none
   1305c:	b941228c 	ldr	w12, [x20, #288]
   13060:	b980690a 	ldrsw	x10, [x8, #104]
   13064:	6b0b019f 	cmp	w12, w11
   13068:	f9001a8a 	str	x10, [x20, #48]
   1306c:	54000300 	b.eq	130cc <full_before_execute+0x2b8>  // b.none
   13070:	9273014b 	and	x11, x10, #0x2000
   13074:	f9001a8b 	str	x11, [x20, #48]
   13078:	376802aa 	tbnz	w10, #13, 130cc <full_before_execute+0x2b8>
   1307c:	b9806509 	ldrsw	x9, [x8, #100]
   13080:	f9002295 	str	x21, [x20, #64]
   13084:	f9001a89 	str	x9, [x20, #48]
   13088:	34004d69 	cbz	w9, 13a34 <full_before_execute+0xc20>
   1308c:	b9806909 	ldrsw	x9, [x8, #104]
   13090:	927a012a 	and	x10, x9, #0x40
   13094:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
   13098:	f9001a8a 	str	x10, [x20, #48]
   1309c:	f900228b 	str	x11, [x20, #64]
   130a0:	b900690b 	str	w11, [x8, #104]
   130a4:	3637fac9 	tbz	w9, #6, 12ffc <full_before_execute+0x1e8>
   130a8:	f9400328 	ldr	x8, [x25]
   130ac:	b9415289 	ldr	w9, [x20, #336]
   130b0:	b941428a 	ldr	w10, [x20, #320]
   130b4:	8b090109 	add	x9, x8, x9
   130b8:	8b0a0108 	add	x8, x8, x10
   130bc:	b9807d29 	ldrsw	x9, [x9, #124]
   130c0:	f9001a89 	str	x9, [x20, #48]
   130c4:	b9002d09 	str	w9, [x8, #44]
   130c8:	17ffffcd 	b	12ffc <full_before_execute+0x1e8>
   130cc:	b941d28b 	ldr	w11, [x20, #464]
   130d0:	b980650a 	ldrsw	x10, [x8, #100]
   130d4:	f9002295 	str	x21, [x20, #64]
   130d8:	1100816b 	add	w11, w11, #0x20
   130dc:	f9001a8a 	str	x10, [x20, #48]
   130e0:	3100055f 	cmn	w10, #0x1
   130e4:	927c6d6b 	and	x11, x11, #0xfffffff0
   130e8:	3ceb68a0 	ldr	q0, [x5, x11]
   130ec:	3d800340 	str	q0, [x26]
   130f0:	54000260 	b.eq	1313c <full_before_execute+0x328>  // b.none
   130f4:	f9402289 	ldr	x9, [x20, #64]
   130f8:	6f00e401 	movi	v1.2d, #0x0
   130fc:	cb090149 	sub	x9, x10, x9
   13100:	1e270120 	fmov	s0, w9
   13104:	d360fd2b 	lsr	x11, x9, #32
   13108:	f9002289 	str	x9, [x20, #64]
   1310c:	4e0c1d60 	mov	v0.s[1], w11
   13110:	9101228b 	add	x11, x20, #0x48
   13114:	4d408160 	ld1	{v0.s}[2], [x11]
   13118:	9101328b 	add	x11, x20, #0x4c
   1311c:	4d409160 	ld1	{v0.s}[3], [x11]
   13120:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
   13124:	3d800e80 	str	q0, [x20, #48]
   13128:	3400486a 	cbz	w10, 13a34 <full_before_execute+0xc20>
   1312c:	f9401a89 	ldr	x9, [x20, #48]
   13130:	b9006509 	str	w9, [x8, #100]
   13134:	f9400325 	ldr	x5, [x25]
   13138:	b9415289 	ldr	w9, [x20, #336]
   1313c:	8b0900a8 	add	x8, x5, x9
   13140:	b9806909 	ldrsw	x9, [x8, #104]
   13144:	927a012a 	and	x10, x9, #0x40
   13148:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
   1314c:	f9001a8a 	str	x10, [x20, #48]
   13150:	f900228b 	str	x11, [x20, #64]
   13154:	b900690b 	str	w11, [x8, #104]
   13158:	36300129 	tbz	w9, #6, 1317c <full_before_execute+0x368>
   1315c:	f9400328 	ldr	x8, [x25]
   13160:	b9415289 	ldr	w9, [x20, #336]
   13164:	b941428a 	ldr	w10, [x20, #320]
   13168:	8b090109 	add	x9, x8, x9
   1316c:	8b0a0108 	add	x8, x8, x10
   13170:	b9807d29 	ldrsw	x9, [x9, #124]
   13174:	f9001a89 	str	x9, [x20, #48]
   13178:	b9002d09 	str	w9, [x8, #44]
   1317c:	f9400328 	ldr	x8, [x25]
   13180:	b941528a 	ldr	w10, [x20, #336]
   13184:	8b0a0109 	add	x9, x8, x10
   13188:	b980712b 	ldrsw	x11, [x9, #112]
   1318c:	f940ea89 	ldr	x9, [x20, #464]
   13190:	f900ca8b 	str	x11, [x20, #400]
   13194:	34000b8b 	cbz	w11, 13304 <full_before_execute+0x4f0>
   13198:	d1018129 	sub	x9, x9, #0x60
   1319c:	3dc07280 	ldr	q0, [x20, #448]
   131a0:	f900ea89 	str	x9, [x20, #464]
   131a4:	927c6d29 	and	x9, x9, #0xfffffff0
   131a8:	3ca96900 	str	q0, [x8, x9]
   131ac:	b941d288 	ldr	w8, [x20, #464]
   131b0:	f9400329 	ldr	x9, [x25]
   131b4:	3dc05680 	ldr	q0, [x20, #336]
   131b8:	11004108 	add	w8, w8, #0x10
   131bc:	927c6d08 	and	x8, x8, #0xfffffff0
   131c0:	3ca86920 	str	q0, [x9, x8]
   131c4:	b941d288 	ldr	w8, [x20, #464]
   131c8:	f9400329 	ldr	x9, [x25]
   131cc:	3dc05280 	ldr	q0, [x20, #320]
   131d0:	11008108 	add	w8, w8, #0x20
   131d4:	927c6d08 	and	x8, x8, #0xfffffff0
   131d8:	3ca86920 	str	q0, [x9, x8]
   131dc:	b941d288 	ldr	w8, [x20, #464]
   131e0:	f9400329 	ldr	x9, [x25]
   131e4:	3dc04280 	ldr	q0, [x20, #256]
   131e8:	1100c108 	add	w8, w8, #0x30
   131ec:	927c6d08 	and	x8, x8, #0xfffffff0
   131f0:	3ca86920 	str	q0, [x9, x8]
   131f4:	b941d288 	ldr	w8, [x20, #464]
   131f8:	f9400329 	ldr	x9, [x25]
   131fc:	3dc04e80 	ldr	q0, [x20, #304]
   13200:	11010108 	add	w8, w8, #0x40
   13204:	927c6d08 	and	x8, x8, #0xfffffff0
   13208:	3ca86920 	str	q0, [x9, x8]
   1320c:	f940e288 	ldr	x8, [x20, #448]
   13210:	b941d28a 	ldr	w10, [x20, #464]
   13214:	f940aa89 	ldr	x9, [x20, #336]
   13218:	f940a28b 	ldr	x11, [x20, #320]
   1321c:	f940032c 	ldr	x12, [x25]
   13220:	3dc04a80 	ldr	q0, [x20, #288]
   13224:	f9002288 	str	x8, [x20, #64]
   13228:	11014148 	add	w8, w10, #0x50
   1322c:	f9002a89 	str	x9, [x20, #80]
   13230:	927c6d09 	and	x9, x8, #0xfffffff0
   13234:	b9419288 	ldr	w8, [x20, #400]
   13238:	f900328b 	str	x11, [x20, #96]
   1323c:	3ca96980 	str	q0, [x12, x9]
   13240:	f9402289 	ldr	x9, [x20, #64]
   13244:	f9402a8a 	ldr	x10, [x20, #80]
   13248:	f940328b 	ldr	x11, [x20, #96]
   1324c:	a9002be9 	stp	x9, x10, [sp]
   13250:	f9403a89 	ldr	x9, [x20, #112]
   13254:	f940428a 	ldr	x10, [x20, #128]
   13258:	a90127eb 	stp	x11, x9, [sp, #16]
   1325c:	f9404a8b 	ldr	x11, [x20, #144]
   13260:	f9405289 	ldr	x9, [x20, #160]
   13264:	a9022fea 	stp	x10, x11, [sp, #32]
   13268:	f9405a8a 	ldr	x10, [x20, #176]
   1326c:	a9032be9 	stp	x9, x10, [sp, #48]
   13270:	340049a8 	cbz	w8, 13ba4 <full_before_execute+0xd90>
   13274:	f9400325 	ldr	x5, [x25]
   13278:	f940b283 	ldr	x3, [x20, #352]
   1327c:	f940ba84 	ldr	x4, [x20, #368]
   13280:	8b0800a0 	add	x0, x5, x8
   13284:	910003e1 	mov	x1, sp
   13288:	aa1f03e2 	mov	x2, xzr
   1328c:	97fff9e2 	bl	11a14 <_call_goal8_asm_systemv>
   13290:	f940ea89 	ldr	x9, [x20, #464]
   13294:	f9400328 	ldr	x8, [x25]
   13298:	f9001280 	str	x0, [x20, #32]
   1329c:	927c6d2a 	and	x10, x9, #0xfffffff0
   132a0:	3cea6900 	ldr	q0, [x8, x10]
   132a4:	1100412a 	add	w10, w9, #0x10
   132a8:	927c6d4a 	and	x10, x10, #0xfffffff0
   132ac:	3d807280 	str	q0, [x20, #448]
   132b0:	3cea6900 	ldr	q0, [x8, x10]
   132b4:	1100812a 	add	w10, w9, #0x20
   132b8:	927c6d4a 	and	x10, x10, #0xfffffff0
   132bc:	3d805680 	str	q0, [x20, #336]
   132c0:	3cea6900 	ldr	q0, [x8, x10]
   132c4:	1100c12a 	add	w10, w9, #0x30
   132c8:	927c6d4a 	and	x10, x10, #0xfffffff0
   132cc:	3d805280 	str	q0, [x20, #320]
   132d0:	3cea6900 	ldr	q0, [x8, x10]
   132d4:	1101012a 	add	w10, w9, #0x40
   132d8:	927c6d4a 	and	x10, x10, #0xfffffff0
   132dc:	3d804280 	str	q0, [x20, #256]
   132e0:	3cea6900 	ldr	q0, [x8, x10]
   132e4:	1101412a 	add	w10, w9, #0x50
   132e8:	91018129 	add	x9, x9, #0x60
   132ec:	927c6d4a 	and	x10, x10, #0xfffffff0
   132f0:	3d804e80 	str	q0, [x20, #304]
   132f4:	3cea6900 	ldr	q0, [x8, x10]
   132f8:	b941528a 	ldr	w10, [x20, #336]
   132fc:	f900ea89 	str	x9, [x20, #464]
   13300:	3d804a80 	str	q0, [x20, #288]
   13304:	8b0a010a 	add	x10, x8, x10
   13308:	11008129 	add	w9, w9, #0x20
   1330c:	b980794c 	ldrsw	x12, [x10, #120]
   13310:	927c6d29 	and	x9, x9, #0xfffffff0
   13314:	f9002a8c 	str	x12, [x20, #80]
   13318:	b980754b 	ldrsw	x11, [x10, #116]
   1331c:	f9001a8b 	str	x11, [x20, #48]
   13320:	3ce96900 	ldr	q0, [x8, x9]
   13324:	3d800340 	str	q0, [x26]
   13328:	34000cac 	cbz	w12, 134bc <full_before_execute+0x6a8>
   1332c:	f9402288 	ldr	x8, [x20, #64]
   13330:	eb080168 	subs	x8, x11, x8
   13334:	f9001a88 	str	x8, [x20, #48]
   13338:	b9007548 	str	w8, [x10, #116]
   1333c:	54000c05 	b.pl	134bc <full_before_execute+0x6a8>  // b.nfrst
   13340:	f940ea88 	ldr	x8, [x20, #464]
   13344:	f9400329 	ldr	x9, [x25]
   13348:	3dc07280 	ldr	q0, [x20, #448]
   1334c:	d1018108 	sub	x8, x8, #0x60
   13350:	f900ea88 	str	x8, [x20, #464]
   13354:	927c6d08 	and	x8, x8, #0xfffffff0
   13358:	3ca86920 	str	q0, [x9, x8]
   1335c:	b941d288 	ldr	w8, [x20, #464]
   13360:	f9400329 	ldr	x9, [x25]
   13364:	3dc05680 	ldr	q0, [x20, #336]
   13368:	11004108 	add	w8, w8, #0x10
   1336c:	927c6d08 	and	x8, x8, #0xfffffff0
   13370:	3ca86920 	str	q0, [x9, x8]
   13374:	b941d288 	ldr	w8, [x20, #464]
   13378:	f9400329 	ldr	x9, [x25]
   1337c:	3dc05280 	ldr	q0, [x20, #320]
   13380:	11008108 	add	w8, w8, #0x20
   13384:	927c6d08 	and	x8, x8, #0xfffffff0
   13388:	3ca86920 	str	q0, [x9, x8]
   1338c:	b941d288 	ldr	w8, [x20, #464]
   13390:	f9400329 	ldr	x9, [x25]
   13394:	3dc04280 	ldr	q0, [x20, #256]
   13398:	1100c108 	add	w8, w8, #0x30
   1339c:	927c6d08 	and	x8, x8, #0xfffffff0
   133a0:	3ca86920 	str	q0, [x9, x8]
   133a4:	b941d288 	ldr	w8, [x20, #464]
   133a8:	f9400329 	ldr	x9, [x25]
   133ac:	3dc04e80 	ldr	q0, [x20, #304]
   133b0:	11010108 	add	w8, w8, #0x40
   133b4:	927c6d08 	and	x8, x8, #0xfffffff0
   133b8:	3ca86920 	str	q0, [x9, x8]
   133bc:	b941d288 	ldr	w8, [x20, #464]
   133c0:	f9400329 	ldr	x9, [x25]
   133c4:	3dc04a80 	ldr	q0, [x20, #288]
   133c8:	11014108 	add	w8, w8, #0x50
   133cc:	927c6d08 	and	x8, x8, #0xfffffff0
   133d0:	3ca86920 	str	q0, [x9, x8]
   133d4:	d0000108 	adrp	x8, 35000 <full_before_g_spart_prof+0x78>
   133d8:	f940e289 	ldr	x9, [x20, #448]
   133dc:	f940a28a 	ldr	x10, [x20, #320]
   133e0:	f940aa8b 	ldr	x11, [x20, #336]
   133e4:	f9403108 	ldr	x8, [x8, #96]
   133e8:	b981f28c 	ldrsw	x12, [x20, #496]
   133ec:	f9002289 	str	x9, [x20, #64]
   133f0:	f9003a8a 	str	x10, [x20, #112]
   133f4:	f900328b 	str	x11, [x20, #96]
   133f8:	b9800108 	ldrsw	x8, [x8]
   133fc:	f900128c 	str	x12, [x20, #32]
   13400:	f9402a8c 	ldr	x12, [x20, #80]
   13404:	a9012beb 	stp	x11, x10, [sp, #16]
   13408:	f9404a8b 	ldr	x11, [x20, #144]
   1340c:	f9405a8a 	ldr	x10, [x20, #176]
   13410:	a90033e9 	stp	x9, x12, [sp]
   13414:	f9404289 	ldr	x9, [x20, #128]
   13418:	f900ca88 	str	x8, [x20, #400]
   1341c:	a9022fe9 	stp	x9, x11, [sp, #32]
   13420:	f9405289 	ldr	x9, [x20, #160]
   13424:	a9032be9 	stp	x9, x10, [sp, #48]
   13428:	34003be8 	cbz	w8, 13ba4 <full_before_execute+0xd90>
   1342c:	f9400325 	ldr	x5, [x25]
   13430:	f940b283 	ldr	x3, [x20, #352]
   13434:	92407d08 	and	x8, x8, #0xffffffff
   13438:	f940ba84 	ldr	x4, [x20, #368]
   1343c:	8b0800a0 	add	x0, x5, x8
   13440:	910003e1 	mov	x1, sp
   13444:	aa1f03e2 	mov	x2, xzr
   13448:	97fff973 	bl	11a14 <_call_goal8_asm_systemv>
   1344c:	f940ea88 	ldr	x8, [x20, #464]
   13450:	f9400329 	ldr	x9, [x25]
   13454:	f9001280 	str	x0, [x20, #32]
   13458:	927c6d0a 	and	x10, x8, #0xfffffff0
   1345c:	3cea6920 	ldr	q0, [x9, x10]
   13460:	1100410a 	add	w10, w8, #0x10
   13464:	927c6d4a 	and	x10, x10, #0xfffffff0
   13468:	3d807280 	str	q0, [x20, #448]
   1346c:	3cea6920 	ldr	q0, [x9, x10]
   13470:	1100810a 	add	w10, w8, #0x20
   13474:	927c6d4a 	and	x10, x10, #0xfffffff0
   13478:	3d805680 	str	q0, [x20, #336]
   1347c:	3cea6920 	ldr	q0, [x9, x10]
   13480:	1100c10a 	add	w10, w8, #0x30
   13484:	927c6d4a 	and	x10, x10, #0xfffffff0
   13488:	3d805280 	str	q0, [x20, #320]
   1348c:	3cea6920 	ldr	q0, [x9, x10]
   13490:	1101010a 	add	w10, w8, #0x40
   13494:	927c6d4a 	and	x10, x10, #0xfffffff0
   13498:	3d804280 	str	q0, [x20, #256]
   1349c:	3cea6920 	ldr	q0, [x9, x10]
   134a0:	1101410a 	add	w10, w8, #0x50
   134a4:	91018108 	add	x8, x8, #0x60
   134a8:	927c6d4a 	and	x10, x10, #0xfffffff0
   134ac:	3d804e80 	str	q0, [x20, #304]
   134b0:	3cea6920 	ldr	q0, [x9, x10]
   134b4:	f900ea88 	str	x8, [x20, #464]
   134b8:	3d804a80 	str	q0, [x20, #288]
   134bc:	f940a289 	ldr	x9, [x20, #320]
   134c0:	f2400d3f 	tst	x9, #0xf
   134c4:	54003641 	b.ne	13b8c <full_before_execute+0xd78>  // b.any
   134c8:	f9400328 	ldr	x8, [x25]
   134cc:	927c6d29 	and	x9, x9, #0xfffffff0
   134d0:	8b09010a 	add	x10, x8, x9
   134d4:	f940aa89 	ldr	x9, [x20, #336]
   134d8:	3dc00140 	ldr	q0, [x10]
   134dc:	f2400d3f 	tst	x9, #0xf
   134e0:	3d80c280 	str	q0, [x20, #768]
   134e4:	3dc00540 	ldr	q0, [x10, #16]
   134e8:	3d80c680 	str	q0, [x20, #784]
   134ec:	3dc00940 	ldr	q0, [x10, #32]
   134f0:	3d80ca80 	str	q0, [x20, #800]
   134f4:	540034c1 	b.ne	13b8c <full_before_execute+0xd78>  // b.any
   134f8:	927c6d29 	and	x9, x9, #0xfffffff0
   134fc:	8b090108 	add	x8, x8, x9
   13500:	3dc00500 	ldr	q0, [x8, #16]
   13504:	3d80ce80 	str	q0, [x20, #816]
   13508:	3dc00900 	ldr	q0, [x8, #32]
   1350c:	bd433284 	ldr	s4, [x20, #816]
   13510:	3d80d280 	str	q0, [x20, #832]
   13514:	3dc00d00 	ldr	q0, [x8, #48]
   13518:	3d80d680 	str	q0, [x20, #848]
   1351c:	3dc01100 	ldr	q0, [x8, #64]
   13520:	3d80da80 	str	q0, [x20, #864]
   13524:	bd438a80 	ldr	s0, [x20, #904]
   13528:	bd436281 	ldr	s1, [x20, #864]
   1352c:	fd403362 	ldr	d2, [x27, #96]
   13530:	bd436e83 	ldr	s3, [x20, #876]
   13534:	b9806109 	ldrsw	x9, [x8, #96]
   13538:	1e200821 	fmul	s1, s1, s0
   1353c:	0f809042 	fmul	v2.2s, v2.2s, v0.s[0]
   13540:	1e200863 	fmul	s3, s3, s0
   13544:	fd401b60 	ldr	d0, [x27, #48]
   13548:	b9020289 	str	w9, [x20, #512]
   1354c:	f9001a89 	str	x9, [x20, #48]
   13550:	bd036281 	str	s1, [x20, #864]
   13554:	1e242821 	fadd	s1, s1, s4
   13558:	0e20d440 	fadd	v0.2s, v2.2s, v0.2s
   1355c:	fd003362 	str	d2, [x27, #96]
   13560:	bd438e82 	ldr	s2, [x20, #908]
   13564:	bd036e83 	str	s3, [x20, #876]
   13568:	bd033281 	str	s1, [x20, #816]
   1356c:	fd001b60 	str	d0, [x27, #48]
   13570:	34000269 	cbz	w9, 135bc <full_before_execute+0x7a8>
   13574:	1e270123 	fmov	s3, w9
   13578:	131f7d29 	asr	w9, w9, #31
   1357c:	bd403a85 	ldr	s5, [x20, #56]
   13580:	1e270126 	fmov	s6, w9
   13584:	1e250845 	fmul	s5, s2, s5
   13588:	1e233944 	fsub	s4, s10, s3
   1358c:	1e230843 	fmul	s3, s2, s3
   13590:	bd037a85 	str	s5, [x20, #888]
   13594:	1e240844 	fmul	s4, s2, s4
   13598:	1e260842 	fmul	s2, s2, s6
   1359c:	bd037283 	str	s3, [x20, #880]
   135a0:	1e243944 	fsub	s4, s10, s4
   135a4:	bd037682 	str	s2, [x20, #884]
   135a8:	1e240821 	fmul	s1, s1, s4
   135ac:	0f849000 	fmul	v0.2s, v0.2s, v4.s[0]
   135b0:	bd037e84 	str	s4, [x20, #892]
   135b4:	bd033281 	str	s1, [x20, #816]
   135b8:	fd001b60 	str	d0, [x27, #48]
   135bc:	bd438682 	ldr	s2, [x20, #900]
   135c0:	910d7289 	add	x9, x20, #0x35c
   135c4:	fd41aa84 	ldr	d4, [x20, #848]
   135c8:	bd433e85 	ldr	s5, [x20, #828]
   135cc:	fd402370 	ldr	d16, [x27, #64]
   135d0:	1e26000a 	fmov	w10, s0
   135d4:	4ea21c43 	mov	v3.16b, v2.16b
   135d8:	4ea21c46 	mov	v6.16b, v2.16b
   135dc:	bd434e92 	ldr	s18, [x20, #844]
   135e0:	6e0c0445 	mov	v5.s[1], v2.s[0]
   135e4:	3dc0ca93 	ldr	q19, [x20, #800]
   135e8:	0f829011 	fmul	v17.2s, v0.2s, v2.s[0]
   135ec:	f9419e8b 	ldr	x11, [x20, #824]
   135f0:	0d409123 	ld1	{v3.s}[1], [x9]
   135f4:	910d6289 	add	x9, x20, #0x358
   135f8:	4d408124 	ld1	{v4.s}[2], [x9]
   135fc:	910d0289 	add	x9, x20, #0x340
   13600:	4e0c04a7 	dup	v7.4s, v5.s[1]
   13604:	0d409126 	ld1	{v6.s}[1], [x9]
   13608:	1e260029 	fmov	w9, s1
   1360c:	4e833863 	zip1	v3.4s, v3.4s, v3.4s
   13610:	fd004b71 	str	d17, [x27, #144]
   13614:	6e1c0444 	mov	v4.s[3], v2.s[0]
   13618:	4e8738a5 	zip1	v5.4s, v5.4s, v7.4s
   1361c:	6e180606 	mov	v6.d[1], v16.d[0]
   13620:	bd430287 	ldr	s7, [x20, #768]
   13624:	fd400370 	ldr	d16, [x27]
   13628:	aa0a8129 	orr	x9, x9, x10, lsl #32
   1362c:	6e140443 	mov	v3.s[2], v2.s[0]
   13630:	6e23dc83 	fmul	v3.4s, v4.4s, v3.4s
   13634:	1e220824 	fmul	s4, s1, s2
   13638:	1e320842 	fmul	s2, s2, s18
   1363c:	4e33d472 	fadd	v18.4s, v3.4s, v19.4s
   13640:	1e272887 	fadd	s7, s4, s7
   13644:	bd039284 	str	s4, [x20, #912]
   13648:	6e26dca4 	fmul	v4.4s, v5.4s, v6.4s
   1364c:	0e30d625 	fadd	v5.2s, v17.2s, v16.2s
   13650:	bd431e93 	ldr	s19, [x20, #796]
   13654:	bd430e86 	ldr	s6, [x20, #780]
   13658:	bd03ae82 	str	s2, [x20, #940]
   1365c:	1e222a62 	fadd	s2, s19, s2
   13660:	3d80ee83 	str	q3, [x20, #944]
   13664:	4ea0ea50 	fcmlt	v16.4s, v18.4s, #0.0
   13668:	bd030287 	str	s7, [x20, #768]
   1366c:	fd000365 	str	d5, [x27]
   13670:	1e262885 	fadd	s5, s4, s6
   13674:	3c898364 	stur	q4, [x27, #152]
   13678:	bd031e82 	str	s2, [x20, #796]
   1367c:	4e701e41 	bic	v1.16b, v18.16b, v16.16b
   13680:	bd030e85 	str	s5, [x20, #780]
   13684:	3d80ca81 	str	q1, [x20, #800]
   13688:	a9012d09 	stp	x9, x11, [x8, #16]
   1368c:	f940a288 	ldr	x8, [x20, #320]
   13690:	f2400d1f 	tst	x8, #0xf
   13694:	54002941 	b.ne	13bbc <full_before_execute+0xda8>  // b.any
   13698:	f9400329 	ldr	x9, [x25]
   1369c:	927c6d08 	and	x8, x8, #0xfffffff0
   136a0:	f941828a 	ldr	x10, [x20, #768]
   136a4:	f941868b 	ldr	x11, [x20, #776]
   136a8:	8b080128 	add	x8, x9, x8
   136ac:	a9002d0a 	stp	x10, x11, [x8]
   136b0:	f940a288 	ldr	x8, [x20, #320]
   136b4:	f2400d1f 	tst	x8, #0xf
   136b8:	54002821 	b.ne	13bbc <full_before_execute+0xda8>  // b.any
   136bc:	f9400329 	ldr	x9, [x25]
   136c0:	927c6d08 	and	x8, x8, #0xfffffff0
   136c4:	f9418a8a 	ldr	x10, [x20, #784]
   136c8:	f9418e8b 	ldr	x11, [x20, #792]
   136cc:	8b080128 	add	x8, x9, x8
   136d0:	a9012d0a 	stp	x10, x11, [x8, #16]
   136d4:	f940a288 	ldr	x8, [x20, #320]
   136d8:	f2400d1f 	tst	x8, #0xf
   136dc:	54002701 	b.ne	13bbc <full_before_execute+0xda8>  // b.any
   136e0:	f9400329 	ldr	x9, [x25]
   136e4:	927c6d08 	and	x8, x8, #0xfffffff0
   136e8:	f941928a 	ldr	x10, [x20, #800]
   136ec:	f941968b 	ldr	x11, [x20, #808]
   136f0:	8b080128 	add	x8, x9, x8
   136f4:	a9022d0a 	stp	x10, x11, [x8, #32]
   136f8:	f940a289 	ldr	x9, [x20, #320]
   136fc:	f940032a 	ldr	x10, [x25]
   13700:	f9408a88 	ldr	x8, [x20, #272]
   13704:	8b29414b 	add	x11, x10, w9, uxtw
   13708:	f9001a88 	str	x8, [x20, #48]
   1370c:	f9002289 	str	x9, [x20, #64]
   13710:	b9401169 	ldr	w9, [x11, #16]
   13714:	b9020289 	str	w9, [x20, #512]
   13718:	b940156c 	ldr	w12, [x11, #20]
   1371c:	b902068c 	str	w12, [x20, #516]
   13720:	b940196b 	ldr	w11, [x11, #24]
   13724:	b9020e8b 	str	w11, [x20, #524]
   13728:	b8284949 	str	w9, [x10, w8, uxtw]
   1372c:	f9400328 	ldr	x8, [x25]
   13730:	b9403289 	ldr	w9, [x20, #48]
   13734:	b942068a 	ldr	w10, [x20, #516]
   13738:	8b090108 	add	x8, x8, x9
   1373c:	b900050a 	str	w10, [x8, #4]
   13740:	f9400328 	ldr	x8, [x25]
   13744:	b9403289 	ldr	w9, [x20, #48]
   13748:	b9420e8a 	ldr	w10, [x20, #524]
   1374c:	8b090108 	add	x8, x8, x9
   13750:	b900090a 	str	w10, [x8, #8]
   13754:	bd420e80 	ldr	s0, [x20, #524]
   13758:	bd420681 	ldr	s1, [x20, #516]
   1375c:	bd420283 	ldr	s3, [x20, #512]
   13760:	f9400328 	ldr	x8, [x25]
   13764:	b9403289 	ldr	w9, [x20, #48]
   13768:	1e200800 	fmul	s0, s0, s0
   1376c:	1e210821 	fmul	s1, s1, s1
   13770:	1e230863 	fmul	s3, s3, s3
   13774:	8b090108 	add	x8, x8, x9
   13778:	1e203942 	fsub	s2, s10, s0
   1377c:	bd020e80 	str	s0, [x20, #524]
   13780:	1e213841 	fsub	s1, s2, s1
   13784:	bd020a82 	str	s2, [x20, #520]
   13788:	7ea3d423 	fabd	s3, s1, s3
   1378c:	bd020681 	str	s1, [x20, #516]
   13790:	1e21c063 	fsqrt	s3, s3
   13794:	bd020283 	str	s3, [x20, #512]
   13798:	bd000d03 	str	s3, [x8, #12]
   1379c:	b9820288 	ldrsw	x8, [x20, #512]
   137a0:	f9402789 	ldr	x9, [x28, #72]
   137a4:	f9400325 	ldr	x5, [x25]
   137a8:	f9002288 	str	x8, [x20, #64]
   137ac:	b9400128 	ldr	w8, [x9]
   137b0:	93407d09 	sxtw	x9, w8
   137b4:	f9001a89 	str	x9, [x20, #48]
   137b8:	b86868a8 	ldr	w8, [x5, x8]
   137bc:	92401d09 	and	x9, x8, #0xff
   137c0:	b9020288 	str	w8, [x20, #512]
   137c4:	d1002928 	sub	x8, x9, #0xa
   137c8:	7100293f 	cmp	w9, #0xa
   137cc:	f9001a88 	str	x8, [x20, #48]
   137d0:	540003c3 	b.cc	13848 <full_before_execute+0xa34>  // b.lo, b.ul, b.last
   137d4:	f9402ac8 	ldr	x8, [x22, #80]
   137d8:	f9408a89 	ldr	x9, [x20, #272]
   137dc:	f940aa8a 	ldr	x10, [x20, #336]
   137e0:	b981f28b 	ldrsw	x11, [x20, #496]
   137e4:	b9800108 	ldrsw	x8, [x8]
   137e8:	f9002289 	str	x9, [x20, #64]
   137ec:	9101414a 	add	x10, x10, #0x50
   137f0:	f9002a89 	str	x9, [x20, #80]
   137f4:	a90027e9 	stp	x9, x9, [sp]
   137f8:	f9403a89 	ldr	x9, [x20, #112]
   137fc:	f900128b 	str	x11, [x20, #32]
   13800:	f940428b 	ldr	x11, [x20, #128]
   13804:	a90127ea 	stp	x10, x9, [sp, #16]
   13808:	f9404a89 	ldr	x9, [x20, #144]
   1380c:	f900328a 	str	x10, [x20, #96]
   13810:	f940528a 	ldr	x10, [x20, #160]
   13814:	a90227eb 	stp	x11, x9, [sp, #32]
   13818:	f9405a89 	ldr	x9, [x20, #176]
   1381c:	f900ca88 	str	x8, [x20, #400]
   13820:	a90327ea 	stp	x10, x9, [sp, #48]
   13824:	34001c08 	cbz	w8, 13ba4 <full_before_execute+0xd90>
   13828:	f940b283 	ldr	x3, [x20, #352]
   1382c:	f940ba84 	ldr	x4, [x20, #368]
   13830:	92407d08 	and	x8, x8, #0xffffffff
   13834:	8b0800a0 	add	x0, x5, x8
   13838:	910003e1 	mov	x1, sp
   1383c:	aa1f03e2 	mov	x2, xzr
   13840:	97fff875 	bl	11a14 <_call_goal8_asm_systemv>
   13844:	f9001280 	str	x0, [x20, #32]
   13848:	f9402ac8 	ldr	x8, [x22, #80]
   1384c:	f9408a89 	ldr	x9, [x20, #272]
   13850:	f940aa8a 	ldr	x10, [x20, #336]
   13854:	b981f28b 	ldrsw	x11, [x20, #496]
   13858:	b9800108 	ldrsw	x8, [x8]
   1385c:	f9002289 	str	x9, [x20, #64]
   13860:	9101414a 	add	x10, x10, #0x50
   13864:	f9002a89 	str	x9, [x20, #80]
   13868:	a90027e9 	stp	x9, x9, [sp]
   1386c:	f9403a89 	ldr	x9, [x20, #112]
   13870:	f900128b 	str	x11, [x20, #32]
   13874:	f940428b 	ldr	x11, [x20, #128]
   13878:	a90127ea 	stp	x10, x9, [sp, #16]
   1387c:	f9404a89 	ldr	x9, [x20, #144]
   13880:	f900328a 	str	x10, [x20, #96]
   13884:	f940528a 	ldr	x10, [x20, #160]
   13888:	a90227eb 	stp	x11, x9, [sp, #32]
   1388c:	f9405a89 	ldr	x9, [x20, #176]
   13890:	f900ca88 	str	x8, [x20, #400]
   13894:	a90327ea 	stp	x10, x9, [sp, #48]
   13898:	34001868 	cbz	w8, 13ba4 <full_before_execute+0xd90>
   1389c:	f9400325 	ldr	x5, [x25]
   138a0:	f940b283 	ldr	x3, [x20, #352]
   138a4:	92407d08 	and	x8, x8, #0xffffffff
   138a8:	f940ba84 	ldr	x4, [x20, #368]
   138ac:	8b0800a0 	add	x0, x5, x8
   138b0:	910003e1 	mov	x1, sp
   138b4:	aa1f03e2 	mov	x2, xzr
   138b8:	97fff857 	bl	11a14 <_call_goal8_asm_systemv>
   138bc:	f9408a89 	ldr	x9, [x20, #272]
   138c0:	f940032b 	ldr	x11, [x25]
   138c4:	f940a28a 	ldr	x10, [x20, #320]
   138c8:	f9001280 	str	x0, [x20, #32]
   138cc:	8b294168 	add	x8, x11, w9, uxtw
   138d0:	f900228a 	str	x10, [x20, #64]
   138d4:	f9001a89 	str	x9, [x20, #48]
   138d8:	b9400d0c 	ldr	w12, [x8, #12]
   138dc:	b902069f 	str	wzr, [x20, #516]
   138e0:	1e270180 	fmov	s0, w12
   138e4:	b902028c 	str	w12, [x20, #512]
   138e8:	92400d4c 	and	x12, x10, #0xf
   138ec:	1e202008 	fcmp	s0, #0.0
   138f0:	540001e4 	b.mi	1392c <full_before_execute+0xb18>  // b.first
   138f4:	b50014cc 	cbnz	x12, 13b8c <full_before_execute+0xd78>
   138f8:	927c6d4a 	and	x10, x10, #0xfffffff0
   138fc:	f2400d3f 	tst	x9, #0xf
   13900:	8b0a016a 	add	x10, x11, x10
   13904:	3dc00540 	ldr	q0, [x10, #16]
   13908:	3d80a680 	str	q0, [x20, #656]
   1390c:	54001401 	b.ne	13b8c <full_before_execute+0xd78>  // b.any
   13910:	3dc00100 	ldr	q0, [x8]
   13914:	3d80aa80 	str	q0, [x20, #672]
   13918:	fd415280 	ldr	d0, [x20, #672]
   1391c:	bd42aa82 	ldr	s2, [x20, #680]
   13920:	0e28d401 	fadd	v1.2s, v0.2s, v8.2s
   13924:	1e292840 	fadd	s0, s2, s9
   13928:	1400000e 	b	13960 <full_before_execute+0xb4c>
   1392c:	b500130c 	cbnz	x12, 13b8c <full_before_execute+0xd78>
   13930:	927c6d4a 	and	x10, x10, #0xfffffff0
   13934:	f2400d3f 	tst	x9, #0xf
   13938:	8b0a016a 	add	x10, x11, x10
   1393c:	3dc00540 	ldr	q0, [x10, #16]
   13940:	3d80a680 	str	q0, [x20, #656]
   13944:	54001241 	b.ne	13b8c <full_before_execute+0xd78>  // b.any
   13948:	3dc00100 	ldr	q0, [x8]
   1394c:	3d80aa80 	str	q0, [x20, #672]
   13950:	fd415280 	ldr	d0, [x20, #672]
   13954:	bd42aa82 	ldr	s2, [x20, #680]
   13958:	0ea0d501 	fsub	v1.2s, v8.2s, v0.2s
   1395c:	1e223920 	fsub	s0, s9, s2
   13960:	5e0c0422 	mov	s2, v1.s[1]
   13964:	1e260009 	fmov	w9, s0
   13968:	b9429e8b 	ldr	w11, [x20, #668]
   1396c:	91004148 	add	x8, x10, #0x10
   13970:	1e26002a 	fmov	w10, s1
   13974:	fd014a81 	str	d1, [x20, #656]
   13978:	bd029a80 	str	s0, [x20, #664]
   1397c:	aa0b8129 	orr	x9, x9, x11, lsl #32
   13980:	1e26004b 	fmov	w11, s2
   13984:	aa0b814a 	orr	x10, x10, x11, lsl #32
   13988:	a900250a 	stp	x10, x9, [x8]
   1398c:	f9414e89 	ldr	x9, [x20, #664]
   13990:	f9414a8a 	ldr	x10, [x20, #656]
   13994:	f9400325 	ldr	x5, [x25]
   13998:	f940aa93 	ldr	x19, [x20, #336]
   1399c:	f9419688 	ldr	x8, [x20, #808]
   139a0:	a904268a 	stp	x10, x9, [x20, #64]
   139a4:	f9419289 	ldr	x9, [x20, #800]
   139a8:	8b3340aa 	add	x10, x5, w19, uxtw
   139ac:	a9032289 	stp	x9, x8, [x20, #48]
   139b0:	b980694a 	ldrsw	x10, [x10, #104]
   139b4:	927e014b 	and	x11, x10, #0x4
   139b8:	f900228a 	str	x10, [x20, #64]
   139bc:	f9002a8b 	str	x11, [x20, #80]
   139c0:	360800ea 	tbz	w10, #1, 139dc <full_before_execute+0xbc8>
   139c4:	d360fd0c 	lsr	x12, x8, #32
   139c8:	290c229f 	stp	wzr, w8, [x20, #96]
   139cc:	290d329f 	stp	wzr, w12, [x20, #104]
   139d0:	b5000069 	cbnz	x9, 139dc <full_before_execute+0xbc8>
   139d4:	f9403289 	ldr	x9, [x20, #96]
   139d8:	b40002e9 	cbz	x9, 13a34 <full_before_execute+0xc20>
   139dc:	92400149 	and	x9, x10, #0x1
   139e0:	f9000349 	str	x9, [x26]
   139e4:	b40000eb 	cbz	x11, 13a00 <full_before_execute+0xbec>
   139e8:	d360fd0a 	lsr	x10, x8, #32
   139ec:	29077e88 	stp	w8, wzr, [x20, #56]
   139f0:	29062a9f 	stp	wzr, w10, [x20, #48]
   139f4:	f9401a8a 	ldr	x10, [x20, #48]
   139f8:	f100055f 	cmp	x10, #0x1
   139fc:	540001cb 	b.lt	13a34 <full_before_execute+0xc20>  // b.tstop
   13a00:	b4ffafe9 	cbz	x9, 12ffc <full_before_execute+0x1e8>
   13a04:	b9430e88 	ldr	w8, [x20, #780]
   13a08:	f9418a8a 	ldr	x10, [x20, #784]
   13a0c:	2906229f 	stp	wzr, w8, [x20, #48]
   13a10:	f9418e88 	ldr	x8, [x20, #792]
   13a14:	f9401a89 	ldr	x9, [x20, #48]
   13a18:	a903228a 	stp	x10, x8, [x20, #48]
   13a1c:	b7f800c9 	tbnz	x9, #63, 13a34 <full_before_execute+0xc20>
   13a20:	d360fd09 	lsr	x9, x8, #32
   13a24:	29077e88 	stp	w8, wzr, [x20, #56]
   13a28:	2906269f 	stp	wzr, w9, [x20, #48]
   13a2c:	f9401a89 	ldr	x9, [x20, #48]
   13a30:	b6ffae69 	tbz	x9, #63, 12ffc <full_before_execute+0x1e8>
   13a34:	d0000108 	adrp	x8, 35000 <full_before_g_spart_prof+0x78>
   13a38:	f940e289 	ldr	x9, [x20, #448]
   13a3c:	f940828a 	ldr	x10, [x20, #256]
   13a40:	f9402d08 	ldr	x8, [x8, #88]
   13a44:	f940a28b 	ldr	x11, [x20, #320]
   13a48:	b981f28c 	ldrsw	x12, [x20, #496]
   13a4c:	b9800108 	ldrsw	x8, [x8]
   13a50:	f9002289 	str	x9, [x20, #64]
   13a54:	f9002a8a 	str	x10, [x20, #80]
   13a58:	a9002be9 	stp	x9, x10, [sp]
   13a5c:	f9404289 	ldr	x9, [x20, #128]
   13a60:	f9404a8a 	ldr	x10, [x20, #144]
   13a64:	f9003a8b 	str	x11, [x20, #112]
   13a68:	a9012ff3 	stp	x19, x11, [sp, #16]
   13a6c:	f940528b 	ldr	x11, [x20, #160]
   13a70:	a9022be9 	stp	x9, x10, [sp, #32]
   13a74:	f9405a89 	ldr	x9, [x20, #176]
   13a78:	f9003293 	str	x19, [x20, #96]
   13a7c:	f900ca88 	str	x8, [x20, #400]
   13a80:	f900128c 	str	x12, [x20, #32]
   13a84:	a90327eb 	stp	x11, x9, [sp, #48]
   13a88:	340008e8 	cbz	w8, 13ba4 <full_before_execute+0xd90>
   13a8c:	f940b283 	ldr	x3, [x20, #352]
   13a90:	f940ba84 	ldr	x4, [x20, #368]
   13a94:	92407d08 	and	x8, x8, #0xffffffff
   13a98:	8b0800a0 	add	x0, x5, x8
   13a9c:	910003e1 	mov	x1, sp
   13aa0:	aa1f03e2 	mov	x2, xzr
   13aa4:	97fff7dc 	bl	11a14 <_call_goal8_asm_systemv>
   13aa8:	f9001280 	str	x0, [x20, #32]
   13aac:	17fffd54 	b	12ffc <full_before_execute+0x1e8>
   13ab0:	f9400328 	ldr	x8, [x25]
   13ab4:	f940ea89 	ldr	x9, [x20, #464]
   13ab8:	f9001298 	str	x24, [x20, #32]
   13abc:	8b29410a 	add	x10, x8, w9, uxtw
   13ac0:	f940014b 	ldr	x11, [x10]
   13ac4:	f900fa8b 	str	x11, [x20, #496]
   13ac8:	1102412b 	add	w11, w9, #0x90
   13acc:	f940054a 	ldr	x10, [x10, #8]
   13ad0:	927c6d6b 	and	x11, x11, #0xfffffff0
   13ad4:	f900f28a 	str	x10, [x20, #480]
   13ad8:	1102012a 	add	w10, w9, #0x80
   13adc:	3ceb6900 	ldr	q0, [x8, x11]
   13ae0:	927c6d4a 	and	x10, x10, #0xfffffff0
   13ae4:	3d807280 	str	q0, [x20, #448]
   13ae8:	3cea6900 	ldr	q0, [x8, x10]
   13aec:	1101c12a 	add	w10, w9, #0x70
   13af0:	927c6d4a 	and	x10, x10, #0xfffffff0
   13af4:	3d805680 	str	q0, [x20, #336]
   13af8:	3cea6900 	ldr	q0, [x8, x10]
   13afc:	1101812a 	add	w10, w9, #0x60
   13b00:	927c6d4a 	and	x10, x10, #0xfffffff0
   13b04:	3d805280 	str	q0, [x20, #320]
   13b08:	3cea6900 	ldr	q0, [x8, x10]
   13b0c:	1101412a 	add	w10, w9, #0x50
   13b10:	927c6d4a 	and	x10, x10, #0xfffffff0
   13b14:	3d804e80 	str	q0, [x20, #304]
   13b18:	3cea6900 	ldr	q0, [x8, x10]
   13b1c:	1101012a 	add	w10, w9, #0x40
   13b20:	927c6d4a 	and	x10, x10, #0xfffffff0
   13b24:	3d804a80 	str	q0, [x20, #288]
   13b28:	3cea6900 	ldr	q0, [x8, x10]
   13b2c:	1100c12a 	add	w10, w9, #0x30
   13b30:	927c6d4a 	and	x10, x10, #0xfffffff0
   13b34:	3d804680 	str	q0, [x20, #272]
   13b38:	3cea6900 	ldr	q0, [x8, x10]
   13b3c:	91028128 	add	x8, x9, #0xa0
   13b40:	f900ea88 	str	x8, [x20, #464]
   13b44:	3d804280 	str	q0, [x20, #256]
   13b48:	94000432 	bl	14c10 <std::chrono::_V2::steady_clock::now()@plt>
   13b4c:	f85e83a8 	ldur	x8, [x29, #-24]
   13b50:	d503201f 	nop
   13b54:	1010a1a1 	adr	x1, 34f88 <full_before_g_spart_prof>
   13b58:	cb080000 	sub	x0, x0, x8
   13b5c:	940003bd 	bl	14a50 <__aarch64_ldadd8_relax>
   13b60:	aa1803e0 	mov	x0, x24
   13b64:	a94b4ff4 	ldp	x20, x19, [sp, #176]
   13b68:	fd4023ea 	ldr	d10, [sp, #64]
   13b6c:	a94a57f6 	ldp	x22, x21, [sp, #160]
   13b70:	a9495ff8 	ldp	x24, x23, [sp, #144]
   13b74:	a94867fa 	ldp	x26, x25, [sp, #128]
   13b78:	a9476ffc 	ldp	x28, x27, [sp, #112]
   13b7c:	a9467bfd 	ldp	x29, x30, [sp, #96]
   13b80:	6d4523e9 	ldp	d9, d8, [sp, #80]
   13b84:	910303ff 	add	sp, sp, #0xc0
   13b88:	d65f03c0 	ret
   13b8c:	52802b02 	mov	w2, #0x158                 	// #344
   13b90:	b0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   13b94:	913f3800 	add	x0, x0, #0xfce
   13b98:	b0ffff63 	adrp	x3, 0 <__abi_tag-0x2c4>
   13b9c:	913ac063 	add	x3, x3, #0xeb0
   13ba0:	1400000c 	b	13bd0 <full_before_execute+0xdbc>
   13ba4:	52803202 	mov	w2, #0x190                 	// #400
   13ba8:	b0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   13bac:	913c2800 	add	x0, x0, #0xf0a
   13bb0:	d0ffff63 	adrp	x3, 1000 <typeinfo name for Boundary+0x1e0>
   13bb4:	910eec63 	add	x3, x3, #0x3bb
   13bb8:	14000006 	b	13bd0 <full_before_execute+0xdbc>
   13bbc:	52803802 	mov	w2, #0x1c0                 	// #448
   13bc0:	b0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   13bc4:	913b8c00 	add	x0, x0, #0xee3
   13bc8:	d0ffff63 	adrp	x3, 1000 <typeinfo name for Boundary+0x1e0>
   13bcc:	9108d063 	add	x3, x3, #0x234
   13bd0:	b0ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   13bd4:	913fec21 	add	x1, x1, #0xffb
   13bd8:	d0ffff64 	adrp	x4, 1000 <typeinfo name for Boundary+0x1e0>
   13bdc:	9105f084 	add	x4, x4, #0x17c
   13be0:	97fffc7e 	bl	12dd8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
   13be4:	b0ffff63 	adrp	x3, 0 <__abi_tag-0x2c4>
   13be8:	913ac063 	add	x3, x3, #0xeb0
   13bec:	52802b02 	mov	w2, #0x158                 	// #344
   13bf0:	b0ffff60 	adrp	x0, 0 <__abi_tag-0x2c4>
   13bf4:	913f3800 	add	x0, x0, #0xfce
   13bf8:	17fffff6 	b	13bd0 <full_before_execute+0xdbc>
   13bfc:	14000001 	b	13c00 <full_before_execute+0xdec>
   13c00:	aa0003f4 	mov	x20, x0
   13c04:	94000403 	bl	14c10 <std::chrono::_V2::steady_clock::now()@plt>
   13c08:	f85e83a8 	ldur	x8, [x29, #-24]
   13c0c:	d503201f 	nop
   13c10:	10109bc1 	adr	x1, 34f88 <full_before_g_spart_prof>
   13c14:	cb080000 	sub	x0, x0, x8
   13c18:	9400038e 	bl	14a50 <__aarch64_ldadd8_relax>
   13c1c:	aa1403e0 	mov	x0, x20
   13c20:	94000400 	bl	14c20 <_Unwind_Resume@plt>

0000000000013c24 <full_after_execute>:
   13c24:	d103c3ff 	sub	sp, sp, #0xf0
   13c28:	6d072beb 	stp	d11, d10, [sp, #112]
   13c2c:	6d0823e9 	stp	d9, d8, [sp, #128]
   13c30:	a9097bfd 	stp	x29, x30, [sp, #144]
   13c34:	a90a6ffc 	stp	x28, x27, [sp, #160]
   13c38:	a90b67fa 	stp	x26, x25, [sp, #176]
   13c3c:	a90c5ff8 	stp	x24, x23, [sp, #192]
   13c40:	a90d57f6 	stp	x22, x21, [sp, #208]
   13c44:	a90e4ff4 	stp	x20, x19, [sp, #224]
   13c48:	910243fd 	add	x29, sp, #0x90
   13c4c:	aa0003f4 	mov	x20, x0
   13c50:	940003f0 	bl	14c10 <std::chrono::_V2::steady_clock::now()@plt>
   13c54:	f9000fe0 	str	x0, [sp, #24]
   13c58:	d0000101 	adrp	x1, 35000 <full_before_g_spart_prof+0x78>
   13c5c:	91022021 	add	x1, x1, #0x88
   13c60:	52800020 	mov	w0, #0x1                   	// #1
   13c64:	9400037b 	bl	14a50 <__aarch64_ldadd8_relax>
   13c68:	b0000099 	adrp	x25, 24000 <__getauxval@plt+0xf3d0>
   13c6c:	f940ea88 	ldr	x8, [x20, #464]
   13c70:	aa1403fa 	mov	x26, x20
   13c74:	f9474339 	ldr	x25, [x25, #3712]
   13c78:	f940fa8a 	ldr	x10, [x20, #496]
   13c7c:	d1028108 	sub	x8, x8, #0xa0
   13c80:	f9400329 	ldr	x9, [x25]
   13c84:	f900ea88 	str	x8, [x20, #464]
   13c88:	f828492a 	str	x10, [x9, w8, uxtw]
   13c8c:	f9400328 	ldr	x8, [x25]
   13c90:	b941d289 	ldr	w9, [x20, #464]
   13c94:	f940f28a 	ldr	x10, [x20, #480]
   13c98:	8b090108 	add	x8, x8, x9
   13c9c:	f900050a 	str	x10, [x8, #8]
   13ca0:	b941d288 	ldr	w8, [x20, #464]
   13ca4:	f940ca89 	ldr	x9, [x20, #400]
   13ca8:	f940032a 	ldr	x10, [x25]
   13cac:	3dc04280 	ldr	q0, [x20, #256]
   13cb0:	1100c108 	add	w8, w8, #0x30
   13cb4:	f900f289 	str	x9, [x20, #480]
   13cb8:	927c6d08 	and	x8, x8, #0xfffffff0
   13cbc:	3ca86940 	str	q0, [x10, x8]
   13cc0:	b941d288 	ldr	w8, [x20, #464]
   13cc4:	f9400329 	ldr	x9, [x25]
   13cc8:	3dc04680 	ldr	q0, [x20, #272]
   13ccc:	11010108 	add	w8, w8, #0x40
   13cd0:	927c6d08 	and	x8, x8, #0xfffffff0
   13cd4:	3ca86920 	str	q0, [x9, x8]
   13cd8:	b941d288 	ldr	w8, [x20, #464]
   13cdc:	f9400329 	ldr	x9, [x25]
   13ce0:	3dc04a80 	ldr	q0, [x20, #288]
   13ce4:	11014108 	add	w8, w8, #0x50
   13ce8:	927c6d08 	and	x8, x8, #0xfffffff0
   13cec:	3ca86920 	str	q0, [x9, x8]
   13cf0:	b941d288 	ldr	w8, [x20, #464]
   13cf4:	f9400329 	ldr	x9, [x25]
   13cf8:	3dc04e80 	ldr	q0, [x20, #304]
   13cfc:	11018108 	add	w8, w8, #0x60
   13d00:	927c6d08 	and	x8, x8, #0xfffffff0
   13d04:	3ca86920 	str	q0, [x9, x8]
   13d08:	b941d288 	ldr	w8, [x20, #464]
   13d0c:	f9400329 	ldr	x9, [x25]
   13d10:	3dc05280 	ldr	q0, [x20, #320]
   13d14:	1101c108 	add	w8, w8, #0x70
   13d18:	927c6d08 	and	x8, x8, #0xfffffff0
   13d1c:	3ca86920 	str	q0, [x9, x8]
   13d20:	b941d288 	ldr	w8, [x20, #464]
   13d24:	f9400329 	ldr	x9, [x25]
   13d28:	3dc05680 	ldr	q0, [x20, #336]
   13d2c:	11020108 	add	w8, w8, #0x80
   13d30:	927c6d08 	and	x8, x8, #0xfffffff0
   13d34:	3ca86920 	str	q0, [x9, x8]
   13d38:	b941d288 	ldr	w8, [x20, #464]
   13d3c:	f9400329 	ldr	x9, [x25]
   13d40:	3dc07280 	ldr	q0, [x20, #448]
   13d44:	11024108 	add	w8, w8, #0x90
   13d48:	927c6d08 	and	x8, x8, #0xfffffff0
   13d4c:	3ca86920 	str	q0, [x9, x8]
   13d50:	f8440f48 	ldr	x8, [x26, #64]!
   13d54:	f9400b49 	ldr	x9, [x26, #16]
   13d58:	f940134a 	ldr	x10, [x26, #32]
   13d5c:	f900e288 	str	x8, [x20, #448]
   13d60:	f9401b48 	ldr	x8, [x26, #48]
   13d64:	f900aa89 	str	x9, [x20, #336]
   13d68:	f9402349 	ldr	x9, [x26, #64]
   13d6c:	f900a28a 	str	x10, [x20, #320]
   13d70:	f940ea8a 	ldr	x10, [x20, #464]
   13d74:	f9008288 	str	x8, [x20, #256]
   13d78:	f9402b48 	ldr	x8, [x26, #80]
   13d7c:	f9009a89 	str	x9, [x20, #304]
   13d80:	f9400329 	ldr	x9, [x25]
   13d84:	9100414a 	add	x10, x10, #0x10
   13d88:	f9009288 	str	x8, [x20, #288]
   13d8c:	927c6d48 	and	x8, x10, #0xfffffff0
   13d90:	8b080128 	add	x8, x9, x8
   13d94:	f9008a8a 	str	x10, [x20, #272]
   13d98:	a9007d1f 	stp	xzr, xzr, [x8]
   13d9c:	d0000108 	adrp	x8, 35000 <full_before_g_spart_prof+0x78>
   13da0:	f9409508 	ldr	x8, [x8, #296]
   13da4:	b9800108 	ldrsw	x8, [x8]
   13da8:	72000d1f 	tst	w8, #0xf
   13dac:	f81f0348 	stur	x8, [x26, #-16]
   13db0:	54006261 	b.ne	149fc <full_after_execute+0xdd8>  // b.any
   13db4:	f9400329 	ldr	x9, [x25]
   13db8:	927c6d08 	and	x8, x8, #0xfffffff0
   13dbc:	2f00e408 	movi	d8, #0x0
   13dc0:	2f00e409 	movi	d9, #0x0
   13dc4:	1e2e100a 	fmov	s10, #1.000000000000000000e+00
   13dc8:	d0000117 	adrp	x23, 35000 <full_before_g_spart_prof+0x78>
   13dcc:	9102a2f7 	add	x23, x23, #0xa8
   13dd0:	3ce86920 	ldr	q0, [x9, x8]
   13dd4:	b941d288 	ldr	w8, [x20, #464]
   13dd8:	910bf35c 	add	x28, x26, #0x2fc
   13ddc:	910c4295 	add	x21, x20, #0x310
   13de0:	92800016 	mov	x22, #0xffffffffffffffff    	// #-1
   13de4:	3d80e280 	str	q0, [x20, #896]
   13de8:	11008108 	add	w8, w8, #0x20
   13dec:	d0000113 	adrp	x19, 35000 <full_before_g_spart_prof+0x78>
   13df0:	f941c68a 	ldr	x10, [x20, #904]
   13df4:	394e028b 	ldrb	w11, [x20, #896]
   13df8:	927c6d08 	and	x8, x8, #0xfffffff0
   13dfc:	8b080128 	add	x8, x9, x8
   13e00:	d0ffff69 	adrp	x9, 1000 <typeinfo name for Boundary+0x1e0>
   13e04:	910eed29 	add	x9, x9, #0x3bb
   13e08:	a9032a8b 	stp	x11, x10, [x20, #48]
   13e0c:	a900290b 	stp	x11, x10, [x8]
   13e10:	b0ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   13e14:	913c2908 	add	x8, x8, #0xf0a
   13e18:	f940aa9b 	ldr	x27, [x20, #336]
   13e1c:	a900a3e9 	stp	x9, x8, [sp, #8]
   13e20:	3d800be0 	str	q0, [sp, #32]
   13e24:	1400000e 	b	13e5c <full_after_execute+0x238>
   13e28:	f9409a88 	ldr	x8, [x20, #304]
   13e2c:	f940aa89 	ldr	x9, [x20, #336]
   13e30:	f940a28a 	ldr	x10, [x20, #320]
   13e34:	f940828b 	ldr	x11, [x20, #256]
   13e38:	f1000508 	subs	x8, x8, #0x1
   13e3c:	9102413b 	add	x27, x9, #0x90
   13e40:	f9009a88 	str	x8, [x20, #304]
   13e44:	9100c148 	add	x8, x10, #0x30
   13e48:	91000578 	add	x24, x11, #0x1
   13e4c:	f900aa9b 	str	x27, [x20, #336]
   13e50:	f900a288 	str	x8, [x20, #320]
   13e54:	f9008298 	str	x24, [x20, #256]
   13e58:	54005120 	b.eq	1487c <full_after_execute+0xc58>  // b.none
   13e5c:	52800020 	mov	w0, #0x1                   	// #1
   13e60:	aa1703e1 	mov	x1, x23
   13e64:	940002fb 	bl	14a50 <__aarch64_ldadd8_relax>
   13e68:	f9400325 	ldr	x5, [x25]
   13e6c:	92407f69 	and	x9, x27, #0xffffffff
   13e70:	b941728b 	ldr	w11, [x20, #368]
   13e74:	8b0900a8 	add	x8, x5, x9
   13e78:	b980810a 	ldrsw	x10, [x8, #128]
   13e7c:	6b0b015f 	cmp	w10, w11
   13e80:	f9001a8a 	str	x10, [x20, #48]
   13e84:	54fffd20 	b.eq	13e28 <full_after_execute+0x204>  // b.none
   13e88:	b941228c 	ldr	w12, [x20, #288]
   13e8c:	b980690a 	ldrsw	x10, [x8, #104]
   13e90:	6b0b019f 	cmp	w12, w11
   13e94:	f9001a8a 	str	x10, [x20, #48]
   13e98:	54000300 	b.eq	13ef8 <full_after_execute+0x2d4>  // b.none
   13e9c:	9273014b 	and	x11, x10, #0x2000
   13ea0:	f9001a8b 	str	x11, [x20, #48]
   13ea4:	376802aa 	tbnz	w10, #13, 13ef8 <full_after_execute+0x2d4>
   13ea8:	b9806509 	ldrsw	x9, [x8, #100]
   13eac:	f9002296 	str	x22, [x20, #64]
   13eb0:	f9001a89 	str	x9, [x20, #48]
   13eb4:	34004a69 	cbz	w9, 14800 <full_after_execute+0xbdc>
   13eb8:	b9806909 	ldrsw	x9, [x8, #104]
   13ebc:	927a012a 	and	x10, x9, #0x40
   13ec0:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
   13ec4:	f9001a8a 	str	x10, [x20, #48]
   13ec8:	f900228b 	str	x11, [x20, #64]
   13ecc:	b900690b 	str	w11, [x8, #104]
   13ed0:	3637fac9 	tbz	w9, #6, 13e28 <full_after_execute+0x204>
   13ed4:	f9400328 	ldr	x8, [x25]
   13ed8:	b9415289 	ldr	w9, [x20, #336]
   13edc:	b941428a 	ldr	w10, [x20, #320]
   13ee0:	8b090109 	add	x9, x8, x9
   13ee4:	8b0a0108 	add	x8, x8, x10
   13ee8:	b9807d29 	ldrsw	x9, [x9, #124]
   13eec:	f9001a89 	str	x9, [x20, #48]
   13ef0:	b9002d09 	str	w9, [x8, #44]
   13ef4:	17ffffcd 	b	13e28 <full_after_execute+0x204>
   13ef8:	b941d28b 	ldr	w11, [x20, #464]
   13efc:	b980650a 	ldrsw	x10, [x8, #100]
   13f00:	f9002296 	str	x22, [x20, #64]
   13f04:	1100816b 	add	w11, w11, #0x20
   13f08:	f9001a8a 	str	x10, [x20, #48]
   13f0c:	3100055f 	cmn	w10, #0x1
   13f10:	927c6d6b 	and	x11, x11, #0xfffffff0
   13f14:	3ceb68a0 	ldr	q0, [x5, x11]
   13f18:	3d800340 	str	q0, [x26]
   13f1c:	54000260 	b.eq	13f68 <full_after_execute+0x344>  // b.none
   13f20:	f9402289 	ldr	x9, [x20, #64]
   13f24:	6f00e401 	movi	v1.2d, #0x0
   13f28:	cb090149 	sub	x9, x10, x9
   13f2c:	1e270120 	fmov	s0, w9
   13f30:	d360fd2b 	lsr	x11, x9, #32
   13f34:	f9002289 	str	x9, [x20, #64]
   13f38:	4e0c1d60 	mov	v0.s[1], w11
   13f3c:	9101228b 	add	x11, x20, #0x48
   13f40:	4d408160 	ld1	{v0.s}[2], [x11]
   13f44:	9101328b 	add	x11, x20, #0x4c
   13f48:	4d409160 	ld1	{v0.s}[3], [x11]
   13f4c:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
   13f50:	3d800e80 	str	q0, [x20, #48]
   13f54:	3400456a 	cbz	w10, 14800 <full_after_execute+0xbdc>
   13f58:	f9401a89 	ldr	x9, [x20, #48]
   13f5c:	b9006509 	str	w9, [x8, #100]
   13f60:	f9400325 	ldr	x5, [x25]
   13f64:	b9415289 	ldr	w9, [x20, #336]
   13f68:	8b0900a8 	add	x8, x5, x9
   13f6c:	b9806909 	ldrsw	x9, [x8, #104]
   13f70:	927a012a 	and	x10, x9, #0x40
   13f74:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
   13f78:	f9001a8a 	str	x10, [x20, #48]
   13f7c:	f900228b 	str	x11, [x20, #64]
   13f80:	b900690b 	str	w11, [x8, #104]
   13f84:	36300129 	tbz	w9, #6, 13fa8 <full_after_execute+0x384>
   13f88:	f9400328 	ldr	x8, [x25]
   13f8c:	b9415289 	ldr	w9, [x20, #336]
   13f90:	b941428a 	ldr	w10, [x20, #320]
   13f94:	8b090109 	add	x9, x8, x9
   13f98:	8b0a0108 	add	x8, x8, x10
   13f9c:	b9807d29 	ldrsw	x9, [x9, #124]
   13fa0:	f9001a89 	str	x9, [x20, #48]
   13fa4:	b9002d09 	str	w9, [x8, #44]
   13fa8:	f9400328 	ldr	x8, [x25]
   13fac:	b941528a 	ldr	w10, [x20, #336]
   13fb0:	8b0a0109 	add	x9, x8, x10
   13fb4:	b980712b 	ldrsw	x11, [x9, #112]
   13fb8:	f940ea89 	ldr	x9, [x20, #464]
   13fbc:	f900ca8b 	str	x11, [x20, #400]
   13fc0:	34000b8b 	cbz	w11, 14130 <full_after_execute+0x50c>
   13fc4:	d1018129 	sub	x9, x9, #0x60
   13fc8:	3dc07280 	ldr	q0, [x20, #448]
   13fcc:	f900ea89 	str	x9, [x20, #464]
   13fd0:	927c6d29 	and	x9, x9, #0xfffffff0
   13fd4:	3ca96900 	str	q0, [x8, x9]
   13fd8:	b941d288 	ldr	w8, [x20, #464]
   13fdc:	f9400329 	ldr	x9, [x25]
   13fe0:	3dc05680 	ldr	q0, [x20, #336]
   13fe4:	11004108 	add	w8, w8, #0x10
   13fe8:	927c6d08 	and	x8, x8, #0xfffffff0
   13fec:	3ca86920 	str	q0, [x9, x8]
   13ff0:	b941d288 	ldr	w8, [x20, #464]
   13ff4:	f9400329 	ldr	x9, [x25]
   13ff8:	3dc05280 	ldr	q0, [x20, #320]
   13ffc:	11008108 	add	w8, w8, #0x20
   14000:	927c6d08 	and	x8, x8, #0xfffffff0
   14004:	3ca86920 	str	q0, [x9, x8]
   14008:	b941d288 	ldr	w8, [x20, #464]
   1400c:	f9400329 	ldr	x9, [x25]
   14010:	3dc04280 	ldr	q0, [x20, #256]
   14014:	1100c108 	add	w8, w8, #0x30
   14018:	927c6d08 	and	x8, x8, #0xfffffff0
   1401c:	3ca86920 	str	q0, [x9, x8]
   14020:	b941d288 	ldr	w8, [x20, #464]
   14024:	f9400329 	ldr	x9, [x25]
   14028:	3dc04e80 	ldr	q0, [x20, #304]
   1402c:	11010108 	add	w8, w8, #0x40
   14030:	927c6d08 	and	x8, x8, #0xfffffff0
   14034:	3ca86920 	str	q0, [x9, x8]
   14038:	f940e288 	ldr	x8, [x20, #448]
   1403c:	b941d28a 	ldr	w10, [x20, #464]
   14040:	f940aa89 	ldr	x9, [x20, #336]
   14044:	f940a28b 	ldr	x11, [x20, #320]
   14048:	f940032c 	ldr	x12, [x25]
   1404c:	3dc04a80 	ldr	q0, [x20, #288]
   14050:	f9002288 	str	x8, [x20, #64]
   14054:	11014148 	add	w8, w10, #0x50
   14058:	f9002a89 	str	x9, [x20, #80]
   1405c:	927c6d09 	and	x9, x8, #0xfffffff0
   14060:	b9419288 	ldr	w8, [x20, #400]
   14064:	f900328b 	str	x11, [x20, #96]
   14068:	3ca96980 	str	q0, [x12, x9]
   1406c:	f9402289 	ldr	x9, [x20, #64]
   14070:	f9402a8a 	ldr	x10, [x20, #80]
   14074:	f940328b 	ldr	x11, [x20, #96]
   14078:	a9032be9 	stp	x9, x10, [sp, #48]
   1407c:	f9403a89 	ldr	x9, [x20, #112]
   14080:	f940428a 	ldr	x10, [x20, #128]
   14084:	a90427eb 	stp	x11, x9, [sp, #64]
   14088:	f9404a8b 	ldr	x11, [x20, #144]
   1408c:	f9405289 	ldr	x9, [x20, #160]
   14090:	a9052fea 	stp	x10, x11, [sp, #80]
   14094:	f9405a8a 	ldr	x10, [x20, #176]
   14098:	a9062be9 	stp	x9, x10, [sp, #96]
   1409c:	340045e8 	cbz	w8, 14958 <full_after_execute+0xd34>
   140a0:	f9400325 	ldr	x5, [x25]
   140a4:	f940b283 	ldr	x3, [x20, #352]
   140a8:	f940ba84 	ldr	x4, [x20, #368]
   140ac:	8b0800a0 	add	x0, x5, x8
   140b0:	9100c3e1 	add	x1, sp, #0x30
   140b4:	aa1f03e2 	mov	x2, xzr
   140b8:	97fff657 	bl	11a14 <_call_goal8_asm_systemv>
   140bc:	f940ea89 	ldr	x9, [x20, #464]
   140c0:	f9400328 	ldr	x8, [x25]
   140c4:	f9001280 	str	x0, [x20, #32]
   140c8:	927c6d2a 	and	x10, x9, #0xfffffff0
   140cc:	3cea6900 	ldr	q0, [x8, x10]
   140d0:	1100412a 	add	w10, w9, #0x10
   140d4:	927c6d4a 	and	x10, x10, #0xfffffff0
   140d8:	3d807280 	str	q0, [x20, #448]
   140dc:	3cea6900 	ldr	q0, [x8, x10]
   140e0:	1100812a 	add	w10, w9, #0x20
   140e4:	927c6d4a 	and	x10, x10, #0xfffffff0
   140e8:	3d805680 	str	q0, [x20, #336]
   140ec:	3cea6900 	ldr	q0, [x8, x10]
   140f0:	1100c12a 	add	w10, w9, #0x30
   140f4:	927c6d4a 	and	x10, x10, #0xfffffff0
   140f8:	3d805280 	str	q0, [x20, #320]
   140fc:	3cea6900 	ldr	q0, [x8, x10]
   14100:	1101012a 	add	w10, w9, #0x40
   14104:	927c6d4a 	and	x10, x10, #0xfffffff0
   14108:	3d804280 	str	q0, [x20, #256]
   1410c:	3cea6900 	ldr	q0, [x8, x10]
   14110:	1101412a 	add	w10, w9, #0x50
   14114:	91018129 	add	x9, x9, #0x60
   14118:	927c6d4a 	and	x10, x10, #0xfffffff0
   1411c:	3d804e80 	str	q0, [x20, #304]
   14120:	3cea6900 	ldr	q0, [x8, x10]
   14124:	b941528a 	ldr	w10, [x20, #336]
   14128:	f900ea89 	str	x9, [x20, #464]
   1412c:	3d804a80 	str	q0, [x20, #288]
   14130:	8b0a010a 	add	x10, x8, x10
   14134:	11008129 	add	w9, w9, #0x20
   14138:	b980794c 	ldrsw	x12, [x10, #120]
   1413c:	927c6d29 	and	x9, x9, #0xfffffff0
   14140:	f9002a8c 	str	x12, [x20, #80]
   14144:	b980754b 	ldrsw	x11, [x10, #116]
   14148:	f9001a8b 	str	x11, [x20, #48]
   1414c:	3ce96900 	ldr	q0, [x8, x9]
   14150:	3d800340 	str	q0, [x26]
   14154:	34000cac 	cbz	w12, 142e8 <full_after_execute+0x6c4>
   14158:	f9402288 	ldr	x8, [x20, #64]
   1415c:	eb080168 	subs	x8, x11, x8
   14160:	f9001a88 	str	x8, [x20, #48]
   14164:	b9007548 	str	w8, [x10, #116]
   14168:	54000c05 	b.pl	142e8 <full_after_execute+0x6c4>  // b.nfrst
   1416c:	f940ea88 	ldr	x8, [x20, #464]
   14170:	f9400329 	ldr	x9, [x25]
   14174:	3dc07280 	ldr	q0, [x20, #448]
   14178:	d1018108 	sub	x8, x8, #0x60
   1417c:	f900ea88 	str	x8, [x20, #464]
   14180:	927c6d08 	and	x8, x8, #0xfffffff0
   14184:	3ca86920 	str	q0, [x9, x8]
   14188:	b941d288 	ldr	w8, [x20, #464]
   1418c:	f9400329 	ldr	x9, [x25]
   14190:	3dc05680 	ldr	q0, [x20, #336]
   14194:	11004108 	add	w8, w8, #0x10
   14198:	927c6d08 	and	x8, x8, #0xfffffff0
   1419c:	3ca86920 	str	q0, [x9, x8]
   141a0:	b941d288 	ldr	w8, [x20, #464]
   141a4:	f9400329 	ldr	x9, [x25]
   141a8:	3dc05280 	ldr	q0, [x20, #320]
   141ac:	11008108 	add	w8, w8, #0x20
   141b0:	927c6d08 	and	x8, x8, #0xfffffff0
   141b4:	3ca86920 	str	q0, [x9, x8]
   141b8:	b941d288 	ldr	w8, [x20, #464]
   141bc:	f9400329 	ldr	x9, [x25]
   141c0:	3dc04280 	ldr	q0, [x20, #256]
   141c4:	1100c108 	add	w8, w8, #0x30
   141c8:	927c6d08 	and	x8, x8, #0xfffffff0
   141cc:	3ca86920 	str	q0, [x9, x8]
   141d0:	b941d288 	ldr	w8, [x20, #464]
   141d4:	f9400329 	ldr	x9, [x25]
   141d8:	3dc04e80 	ldr	q0, [x20, #304]
   141dc:	11010108 	add	w8, w8, #0x40
   141e0:	927c6d08 	and	x8, x8, #0xfffffff0
   141e4:	3ca86920 	str	q0, [x9, x8]
   141e8:	b941d288 	ldr	w8, [x20, #464]
   141ec:	f9400329 	ldr	x9, [x25]
   141f0:	3dc04a80 	ldr	q0, [x20, #288]
   141f4:	11014108 	add	w8, w8, #0x50
   141f8:	927c6d08 	and	x8, x8, #0xfffffff0
   141fc:	3ca86920 	str	q0, [x9, x8]
   14200:	b0000108 	adrp	x8, 35000 <full_before_g_spart_prof+0x78>
   14204:	f940e289 	ldr	x9, [x20, #448]
   14208:	f940a28a 	ldr	x10, [x20, #320]
   1420c:	f940aa8b 	ldr	x11, [x20, #336]
   14210:	f940a108 	ldr	x8, [x8, #320]
   14214:	b981f28c 	ldrsw	x12, [x20, #496]
   14218:	f9002289 	str	x9, [x20, #64]
   1421c:	f9003a8a 	str	x10, [x20, #112]
   14220:	f900328b 	str	x11, [x20, #96]
   14224:	b9800108 	ldrsw	x8, [x8]
   14228:	f900128c 	str	x12, [x20, #32]
   1422c:	f9402a8c 	ldr	x12, [x20, #80]
   14230:	a9042beb 	stp	x11, x10, [sp, #64]
   14234:	f9404a8b 	ldr	x11, [x20, #144]
   14238:	f9405a8a 	ldr	x10, [x20, #176]
   1423c:	a90333e9 	stp	x9, x12, [sp, #48]
   14240:	f9404289 	ldr	x9, [x20, #128]
   14244:	f900ca88 	str	x8, [x20, #400]
   14248:	a9052fe9 	stp	x9, x11, [sp, #80]
   1424c:	f9405289 	ldr	x9, [x20, #160]
   14250:	a9062be9 	stp	x9, x10, [sp, #96]
   14254:	34003828 	cbz	w8, 14958 <full_after_execute+0xd34>
   14258:	f9400325 	ldr	x5, [x25]
   1425c:	f940b283 	ldr	x3, [x20, #352]
   14260:	92407d08 	and	x8, x8, #0xffffffff
   14264:	f940ba84 	ldr	x4, [x20, #368]
   14268:	8b0800a0 	add	x0, x5, x8
   1426c:	9100c3e1 	add	x1, sp, #0x30
   14270:	aa1f03e2 	mov	x2, xzr
   14274:	97fff5e8 	bl	11a14 <_call_goal8_asm_systemv>
   14278:	f940ea88 	ldr	x8, [x20, #464]
   1427c:	f9400329 	ldr	x9, [x25]
   14280:	f9001280 	str	x0, [x20, #32]
   14284:	927c6d0a 	and	x10, x8, #0xfffffff0
   14288:	3cea6920 	ldr	q0, [x9, x10]
   1428c:	1100410a 	add	w10, w8, #0x10
   14290:	927c6d4a 	and	x10, x10, #0xfffffff0
   14294:	3d807280 	str	q0, [x20, #448]
   14298:	3cea6920 	ldr	q0, [x9, x10]
   1429c:	1100810a 	add	w10, w8, #0x20
   142a0:	927c6d4a 	and	x10, x10, #0xfffffff0
   142a4:	3d805680 	str	q0, [x20, #336]
   142a8:	3cea6920 	ldr	q0, [x9, x10]
   142ac:	1100c10a 	add	w10, w8, #0x30
   142b0:	927c6d4a 	and	x10, x10, #0xfffffff0
   142b4:	3d805280 	str	q0, [x20, #320]
   142b8:	3cea6920 	ldr	q0, [x9, x10]
   142bc:	1101010a 	add	w10, w8, #0x40
   142c0:	927c6d4a 	and	x10, x10, #0xfffffff0
   142c4:	3d804280 	str	q0, [x20, #256]
   142c8:	3cea6920 	ldr	q0, [x9, x10]
   142cc:	1101410a 	add	w10, w8, #0x50
   142d0:	91018108 	add	x8, x8, #0x60
   142d4:	927c6d4a 	and	x10, x10, #0xfffffff0
   142d8:	3d804e80 	str	q0, [x20, #304]
   142dc:	3cea6920 	ldr	q0, [x9, x10]
   142e0:	f900ea88 	str	x8, [x20, #464]
   142e4:	3d804a80 	str	q0, [x20, #288]
   142e8:	f940a289 	ldr	x9, [x20, #320]
   142ec:	f2400d3f 	tst	x9, #0xf
   142f0:	540035e1 	b.ne	149ac <full_after_execute+0xd88>  // b.any
   142f4:	f9400328 	ldr	x8, [x25]
   142f8:	927c6d29 	and	x9, x9, #0xfffffff0
   142fc:	8b09010a 	add	x10, x8, x9
   14300:	f9400949 	ldr	x9, [x10, #16]
   14304:	3dc00140 	ldr	q0, [x10]
   14308:	f9001be9 	str	x9, [sp, #48]
   1430c:	f940aa89 	ldr	x9, [x20, #336]
   14310:	b940194b 	ldr	w11, [x10, #24]
   14314:	f2400d3f 	tst	x9, #0xf
   14318:	b9003beb 	str	w11, [sp, #56]
   1431c:	540035c1 	b.ne	149d4 <full_after_execute+0xdb0>  // b.any
   14320:	927c6d29 	and	x9, x9, #0xfffffff0
   14324:	bd438a81 	ldr	s1, [x20, #904]
   14328:	bd401d46 	ldr	s6, [x10, #28]
   1432c:	8b090108 	add	x8, x8, x9
   14330:	3dc00951 	ldr	q17, [x10, #32]
   14334:	ad418905 	ldp	q5, q2, [x8, #48]
   14338:	bd401904 	ldr	s4, [x8, #24]
   1433c:	b9806109 	ldrsw	x9, [x8, #96]
   14340:	bd402d07 	ldr	s7, [x8, #44]
   14344:	4f819042 	fmul	v2.4s, v2.4s, v1.s[0]
   14348:	fd400901 	ldr	d1, [x8, #16]
   1434c:	5e140443 	mov	s3, v2.s[2]
   14350:	0e22d421 	fadd	v1.2s, v1.2s, v2.2s
   14354:	1e232890 	fadd	s16, s4, s3
   14358:	3cc1c103 	ldur	q3, [x8, #28]
   1435c:	bd438684 	ldr	s4, [x20, #900]
   14360:	b9020289 	str	w9, [x20, #512]
   14364:	f9001a89 	str	x9, [x20, #48]
   14368:	34000209 	cbz	w9, 143a8 <full_after_execute+0x784>
   1436c:	1e270132 	fmov	s18, w9
   14370:	bd438e93 	ldr	s19, [x20, #908]
   14374:	1e270135 	fmov	s21, w9
   14378:	131f7d2a 	asr	w10, w9, #31
   1437c:	bd403a94 	ldr	s20, [x20, #56]
   14380:	1e323952 	fsub	s18, s10, s18
   14384:	4e0c1d55 	mov	v21.s[1], w10
   14388:	1e340a74 	fmul	s20, s19, s20
   1438c:	1e320a72 	fmul	s18, s19, s18
   14390:	0f9392ab 	fmul	v11.2s, v21.2s, v19.s[0]
   14394:	1e323952 	fsub	s18, s10, s18
   14398:	6e0c0654 	mov	v20.s[1], v18.s[0]
   1439c:	0f929021 	fmul	v1.2s, v1.2s, v18.s[0]
   143a0:	1e300a50 	fmul	s16, s18, s16
   143a4:	3d800bf4 	str	q20, [sp, #32]
   143a8:	0e0c0433 	dup	v19.2s, v1.s[1]
   143ac:	4f8490b2 	fmul	v18.4s, v5.4s, v4.s[0]
   143b0:	1e210894 	fmul	s20, s4, s1
   143b4:	bd033a90 	str	s16, [x20, #824]
   143b8:	f9401bea 	ldr	x10, [sp, #48]
   143bc:	bd034e87 	str	s7, [x20, #844]
   143c0:	f90002aa 	str	x10, [x21]
   143c4:	b9403bea 	ldr	w10, [sp, #56]
   143c8:	6e0c0613 	mov	v19.s[1], v16.s[0]
   143cc:	4e32d635 	fadd	v21.4s, v17.4s, v18.4s
   143d0:	1e270891 	fmul	s17, s4, s7
   143d4:	fd019a81 	str	d1, [x20, #816]
   143d8:	3d800383 	str	q3, [x28]
   143dc:	b9000aaa 	str	w10, [x21, #8]
   143e0:	6e180473 	mov	v19.d[1], v3.d[0]
   143e4:	4ea0eab0 	fcmlt	v16.4s, v21.4s, #0.0
   143e8:	1e3128c6 	fadd	s6, s6, s17
   143ec:	ad1a8a85 	stp	q5, q2, [x20, #848]
   143f0:	4f849273 	fmul	v19.4s, v19.4s, v4.s[0]
   143f4:	4e701ea7 	bic	v7.16b, v21.16b, v16.16b
   143f8:	bd031e86 	str	s6, [x20, #796]
   143fc:	3d80ca87 	str	q7, [x20, #800]
   14400:	6e136016 	ext	v22.16b, v0.16b, v19.16b, #12
   14404:	6e040696 	mov	v22.s[0], v20.s[0]
   14408:	4e36d400 	fadd	v0.4s, v0.4s, v22.4s
   1440c:	3d80c280 	str	q0, [x20, #768]
   14410:	34000089 	cbz	w9, 14420 <full_after_execute+0x7fc>
   14414:	3dc00be0 	ldr	q0, [sp, #32]
   14418:	fd01ba8b 	str	d11, [x20, #880]
   1441c:	fd01be80 	str	d0, [x20, #888]
   14420:	0e0c3c29 	mov	w9, v1.s[1]
   14424:	1e26002a 	fmov	w10, s1
   14428:	f9419e8b 	ldr	x11, [x20, #824]
   1442c:	5f839880 	fmul	s0, s4, v3.s[2]
   14430:	5fa39882 	fmul	s2, s4, v3.s[3]
   14434:	bd039294 	str	s20, [x20, #912]
   14438:	3c858393 	stur	q19, [x28, #88]
   1443c:	bd03ae91 	str	s17, [x20, #940]
   14440:	aa098149 	orr	x9, x10, x9, lsl #32
   14444:	3d80ee92 	str	q18, [x20, #944]
   14448:	bd03a680 	str	s0, [x20, #932]
   1444c:	bd03aa82 	str	s2, [x20, #936]
   14450:	a9012d09 	stp	x9, x11, [x8, #16]
   14454:	f940a288 	ldr	x8, [x20, #320]
   14458:	f2400d1f 	tst	x8, #0xf
   1445c:	54002821 	b.ne	14960 <full_after_execute+0xd3c>  // b.any
   14460:	f9400329 	ldr	x9, [x25]
   14464:	927c6d08 	and	x8, x8, #0xfffffff0
   14468:	f941828a 	ldr	x10, [x20, #768]
   1446c:	f941868b 	ldr	x11, [x20, #776]
   14470:	8b080128 	add	x8, x9, x8
   14474:	a9002d0a 	stp	x10, x11, [x8]
   14478:	f940a288 	ldr	x8, [x20, #320]
   1447c:	f2400d1f 	tst	x8, #0xf
   14480:	54002701 	b.ne	14960 <full_after_execute+0xd3c>  // b.any
   14484:	f9400329 	ldr	x9, [x25]
   14488:	927c6d08 	and	x8, x8, #0xfffffff0
   1448c:	f9418a8a 	ldr	x10, [x20, #784]
   14490:	f9418e8b 	ldr	x11, [x20, #792]
   14494:	8b080128 	add	x8, x9, x8
   14498:	a9012d0a 	stp	x10, x11, [x8, #16]
   1449c:	f940a288 	ldr	x8, [x20, #320]
   144a0:	f2400d1f 	tst	x8, #0xf
   144a4:	540025e1 	b.ne	14960 <full_after_execute+0xd3c>  // b.any
   144a8:	f9400329 	ldr	x9, [x25]
   144ac:	927c6d08 	and	x8, x8, #0xfffffff0
   144b0:	f941928a 	ldr	x10, [x20, #800]
   144b4:	f941968b 	ldr	x11, [x20, #808]
   144b8:	8b080128 	add	x8, x9, x8
   144bc:	a9022d0a 	stp	x10, x11, [x8, #32]
   144c0:	f940a289 	ldr	x9, [x20, #320]
   144c4:	f940032a 	ldr	x10, [x25]
   144c8:	f9408a88 	ldr	x8, [x20, #272]
   144cc:	8b29414b 	add	x11, x10, w9, uxtw
   144d0:	f9001a88 	str	x8, [x20, #48]
   144d4:	f9002289 	str	x9, [x20, #64]
   144d8:	b9401169 	ldr	w9, [x11, #16]
   144dc:	b9020289 	str	w9, [x20, #512]
   144e0:	b940156c 	ldr	w12, [x11, #20]
   144e4:	b902068c 	str	w12, [x20, #516]
   144e8:	b940196b 	ldr	w11, [x11, #24]
   144ec:	b9020e8b 	str	w11, [x20, #524]
   144f0:	b8284949 	str	w9, [x10, w8, uxtw]
   144f4:	f9400328 	ldr	x8, [x25]
   144f8:	b9403289 	ldr	w9, [x20, #48]
   144fc:	b942068a 	ldr	w10, [x20, #516]
   14500:	8b090108 	add	x8, x8, x9
   14504:	b900050a 	str	w10, [x8, #4]
   14508:	f9400328 	ldr	x8, [x25]
   1450c:	b9403289 	ldr	w9, [x20, #48]
   14510:	b9420e8a 	ldr	w10, [x20, #524]
   14514:	8b090108 	add	x8, x8, x9
   14518:	b900090a 	str	w10, [x8, #8]
   1451c:	bd420e80 	ldr	s0, [x20, #524]
   14520:	bd420681 	ldr	s1, [x20, #516]
   14524:	bd420283 	ldr	s3, [x20, #512]
   14528:	f9400328 	ldr	x8, [x25]
   1452c:	b9403289 	ldr	w9, [x20, #48]
   14530:	1e200800 	fmul	s0, s0, s0
   14534:	1e210821 	fmul	s1, s1, s1
   14538:	1e230863 	fmul	s3, s3, s3
   1453c:	8b090108 	add	x8, x8, x9
   14540:	b0000109 	adrp	x9, 35000 <full_before_g_spart_prof+0x78>
   14544:	1e203942 	fsub	s2, s10, s0
   14548:	bd020e80 	str	s0, [x20, #524]
   1454c:	1e213841 	fsub	s1, s2, s1
   14550:	bd020a82 	str	s2, [x20, #520]
   14554:	7ea3d423 	fabd	s3, s1, s3
   14558:	bd020681 	str	s1, [x20, #516]
   1455c:	1e21c063 	fsqrt	s3, s3
   14560:	bd020283 	str	s3, [x20, #512]
   14564:	bd000d03 	str	s3, [x8, #12]
   14568:	b9820288 	ldrsw	x8, [x20, #512]
   1456c:	f9409529 	ldr	x9, [x9, #296]
   14570:	f9400325 	ldr	x5, [x25]
   14574:	f9002288 	str	x8, [x20, #64]
   14578:	b9400128 	ldr	w8, [x9]
   1457c:	93407d09 	sxtw	x9, w8
   14580:	f9001a89 	str	x9, [x20, #48]
   14584:	b86868a8 	ldr	w8, [x5, x8]
   14588:	92401d09 	and	x9, x8, #0xff
   1458c:	b9020288 	str	w8, [x20, #512]
   14590:	d1002928 	sub	x8, x9, #0xa
   14594:	7100293f 	cmp	w9, #0xa
   14598:	f9001a88 	str	x8, [x20, #48]
   1459c:	540003c3 	b.cc	14614 <full_after_execute+0x9f0>  // b.lo, b.ul, b.last
   145a0:	f9409a68 	ldr	x8, [x19, #304]
   145a4:	f9408a89 	ldr	x9, [x20, #272]
   145a8:	f940aa8a 	ldr	x10, [x20, #336]
   145ac:	b981f28b 	ldrsw	x11, [x20, #496]
   145b0:	b9800108 	ldrsw	x8, [x8]
   145b4:	f9002289 	str	x9, [x20, #64]
   145b8:	9101414a 	add	x10, x10, #0x50
   145bc:	f9002a89 	str	x9, [x20, #80]
   145c0:	a90327e9 	stp	x9, x9, [sp, #48]
   145c4:	f9403a89 	ldr	x9, [x20, #112]
   145c8:	f900128b 	str	x11, [x20, #32]
   145cc:	f940428b 	ldr	x11, [x20, #128]
   145d0:	a90427ea 	stp	x10, x9, [sp, #64]
   145d4:	f9404a89 	ldr	x9, [x20, #144]
   145d8:	f900328a 	str	x10, [x20, #96]
   145dc:	f940528a 	ldr	x10, [x20, #160]
   145e0:	a90527eb 	stp	x11, x9, [sp, #80]
   145e4:	f9405a89 	ldr	x9, [x20, #176]
   145e8:	f900ca88 	str	x8, [x20, #400]
   145ec:	a90627ea 	stp	x10, x9, [sp, #96]
   145f0:	34001b48 	cbz	w8, 14958 <full_after_execute+0xd34>
   145f4:	f940b283 	ldr	x3, [x20, #352]
   145f8:	f940ba84 	ldr	x4, [x20, #368]
   145fc:	92407d08 	and	x8, x8, #0xffffffff
   14600:	8b0800a0 	add	x0, x5, x8
   14604:	9100c3e1 	add	x1, sp, #0x30
   14608:	aa1f03e2 	mov	x2, xzr
   1460c:	97fff502 	bl	11a14 <_call_goal8_asm_systemv>
   14610:	f9001280 	str	x0, [x20, #32]
   14614:	f9409a68 	ldr	x8, [x19, #304]
   14618:	f9408a89 	ldr	x9, [x20, #272]
   1461c:	f940aa8a 	ldr	x10, [x20, #336]
   14620:	b981f28b 	ldrsw	x11, [x20, #496]
   14624:	b9800108 	ldrsw	x8, [x8]
   14628:	f9002289 	str	x9, [x20, #64]
   1462c:	9101414a 	add	x10, x10, #0x50
   14630:	f9002a89 	str	x9, [x20, #80]
   14634:	a90327e9 	stp	x9, x9, [sp, #48]
   14638:	f9403a89 	ldr	x9, [x20, #112]
   1463c:	f900128b 	str	x11, [x20, #32]
   14640:	f940428b 	ldr	x11, [x20, #128]
   14644:	a90427ea 	stp	x10, x9, [sp, #64]
   14648:	f9404a89 	ldr	x9, [x20, #144]
   1464c:	f900328a 	str	x10, [x20, #96]
   14650:	f940528a 	ldr	x10, [x20, #160]
   14654:	a90527eb 	stp	x11, x9, [sp, #80]
   14658:	f9405a89 	ldr	x9, [x20, #176]
   1465c:	f900ca88 	str	x8, [x20, #400]
   14660:	a90627ea 	stp	x10, x9, [sp, #96]
   14664:	340017a8 	cbz	w8, 14958 <full_after_execute+0xd34>
   14668:	f9400325 	ldr	x5, [x25]
   1466c:	f940b283 	ldr	x3, [x20, #352]
   14670:	92407d08 	and	x8, x8, #0xffffffff
   14674:	f940ba84 	ldr	x4, [x20, #368]
   14678:	8b0800a0 	add	x0, x5, x8
   1467c:	9100c3e1 	add	x1, sp, #0x30
   14680:	aa1f03e2 	mov	x2, xzr
   14684:	97fff4e4 	bl	11a14 <_call_goal8_asm_systemv>
   14688:	f9408a89 	ldr	x9, [x20, #272]
   1468c:	f940032b 	ldr	x11, [x25]
   14690:	f940a28a 	ldr	x10, [x20, #320]
   14694:	f9001280 	str	x0, [x20, #32]
   14698:	8b294168 	add	x8, x11, w9, uxtw
   1469c:	f900228a 	str	x10, [x20, #64]
   146a0:	f9001a89 	str	x9, [x20, #48]
   146a4:	b9400d0c 	ldr	w12, [x8, #12]
   146a8:	b902069f 	str	wzr, [x20, #516]
   146ac:	1e270180 	fmov	s0, w12
   146b0:	b902028c 	str	w12, [x20, #512]
   146b4:	92400d4c 	and	x12, x10, #0xf
   146b8:	1e202008 	fcmp	s0, #0.0
   146bc:	540001e4 	b.mi	146f8 <full_after_execute+0xad4>  // b.first
   146c0:	b50015ec 	cbnz	x12, 1497c <full_after_execute+0xd58>
   146c4:	927c6d4a 	and	x10, x10, #0xfffffff0
   146c8:	f2400d3f 	tst	x9, #0xf
   146cc:	8b0a016a 	add	x10, x11, x10
   146d0:	3dc00540 	ldr	q0, [x10, #16]
   146d4:	3d80a680 	str	q0, [x20, #656]
   146d8:	54001521 	b.ne	1497c <full_after_execute+0xd58>  // b.any
   146dc:	3dc00100 	ldr	q0, [x8]
   146e0:	3d80aa80 	str	q0, [x20, #672]
   146e4:	fd415280 	ldr	d0, [x20, #672]
   146e8:	bd42aa82 	ldr	s2, [x20, #680]
   146ec:	0e28d401 	fadd	v1.2s, v0.2s, v8.2s
   146f0:	1e292840 	fadd	s0, s2, s9
   146f4:	1400000e 	b	1472c <full_after_execute+0xb08>
   146f8:	b500142c 	cbnz	x12, 1497c <full_after_execute+0xd58>
   146fc:	927c6d4a 	and	x10, x10, #0xfffffff0
   14700:	f2400d3f 	tst	x9, #0xf
   14704:	8b0a016a 	add	x10, x11, x10
   14708:	3dc00540 	ldr	q0, [x10, #16]
   1470c:	3d80a680 	str	q0, [x20, #656]
   14710:	54001361 	b.ne	1497c <full_after_execute+0xd58>  // b.any
   14714:	3dc00100 	ldr	q0, [x8]
   14718:	3d80aa80 	str	q0, [x20, #672]
   1471c:	fd415280 	ldr	d0, [x20, #672]
   14720:	bd42aa82 	ldr	s2, [x20, #680]
   14724:	0ea0d501 	fsub	v1.2s, v8.2s, v0.2s
   14728:	1e223920 	fsub	s0, s9, s2
   1472c:	5e0c0422 	mov	s2, v1.s[1]
   14730:	1e260009 	fmov	w9, s0
   14734:	b9429e8b 	ldr	w11, [x20, #668]
   14738:	91004148 	add	x8, x10, #0x10
   1473c:	1e26002a 	fmov	w10, s1
   14740:	fd014a81 	str	d1, [x20, #656]
   14744:	bd029a80 	str	s0, [x20, #664]
   14748:	aa0b8129 	orr	x9, x9, x11, lsl #32
   1474c:	1e26004b 	fmov	w11, s2
   14750:	aa0b814a 	orr	x10, x10, x11, lsl #32
   14754:	a900250a 	stp	x10, x9, [x8]
   14758:	f9414e89 	ldr	x9, [x20, #664]
   1475c:	f9414a8a 	ldr	x10, [x20, #656]
   14760:	f9400325 	ldr	x5, [x25]
   14764:	f940aa9b 	ldr	x27, [x20, #336]
   14768:	f9419688 	ldr	x8, [x20, #808]
   1476c:	a904268a 	stp	x10, x9, [x20, #64]
   14770:	f9419289 	ldr	x9, [x20, #800]
   14774:	8b3b40aa 	add	x10, x5, w27, uxtw
   14778:	a9032289 	stp	x9, x8, [x20, #48]
   1477c:	b980694a 	ldrsw	x10, [x10, #104]
   14780:	927e014b 	and	x11, x10, #0x4
   14784:	f900228a 	str	x10, [x20, #64]
   14788:	f9002a8b 	str	x11, [x20, #80]
   1478c:	360800ea 	tbz	w10, #1, 147a8 <full_after_execute+0xb84>
   14790:	d360fd0c 	lsr	x12, x8, #32
   14794:	290c229f 	stp	wzr, w8, [x20, #96]
   14798:	290d329f 	stp	wzr, w12, [x20, #104]
   1479c:	b5000069 	cbnz	x9, 147a8 <full_after_execute+0xb84>
   147a0:	f9403289 	ldr	x9, [x20, #96]
   147a4:	b40002e9 	cbz	x9, 14800 <full_after_execute+0xbdc>
   147a8:	92400149 	and	x9, x10, #0x1
   147ac:	f9000349 	str	x9, [x26]
   147b0:	b40000eb 	cbz	x11, 147cc <full_after_execute+0xba8>
   147b4:	d360fd0a 	lsr	x10, x8, #32
   147b8:	29077e88 	stp	w8, wzr, [x20, #56]
   147bc:	29062a9f 	stp	wzr, w10, [x20, #48]
   147c0:	f9401a8a 	ldr	x10, [x20, #48]
   147c4:	f100055f 	cmp	x10, #0x1
   147c8:	540001cb 	b.lt	14800 <full_after_execute+0xbdc>  // b.tstop
   147cc:	b4ffb2e9 	cbz	x9, 13e28 <full_after_execute+0x204>
   147d0:	b9430e88 	ldr	w8, [x20, #780]
   147d4:	f9418a8a 	ldr	x10, [x20, #784]
   147d8:	2906229f 	stp	wzr, w8, [x20, #48]
   147dc:	f9418e88 	ldr	x8, [x20, #792]
   147e0:	f9401a89 	ldr	x9, [x20, #48]
   147e4:	a903228a 	stp	x10, x8, [x20, #48]
   147e8:	b7f800c9 	tbnz	x9, #63, 14800 <full_after_execute+0xbdc>
   147ec:	d360fd09 	lsr	x9, x8, #32
   147f0:	29077e88 	stp	w8, wzr, [x20, #56]
   147f4:	2906269f 	stp	wzr, w9, [x20, #48]
   147f8:	f9401a89 	ldr	x9, [x20, #48]
   147fc:	b6ffb169 	tbz	x9, #63, 13e28 <full_after_execute+0x204>
   14800:	b0000108 	adrp	x8, 35000 <full_before_g_spart_prof+0x78>
   14804:	f940e289 	ldr	x9, [x20, #448]
   14808:	f940828a 	ldr	x10, [x20, #256]
   1480c:	f9409d08 	ldr	x8, [x8, #312]
   14810:	f940a28b 	ldr	x11, [x20, #320]
   14814:	b981f28c 	ldrsw	x12, [x20, #496]
   14818:	b9800108 	ldrsw	x8, [x8]
   1481c:	f9002289 	str	x9, [x20, #64]
   14820:	f9002a8a 	str	x10, [x20, #80]
   14824:	a9032be9 	stp	x9, x10, [sp, #48]
   14828:	f9404289 	ldr	x9, [x20, #128]
   1482c:	f9404a8a 	ldr	x10, [x20, #144]
   14830:	f9003a8b 	str	x11, [x20, #112]
   14834:	a9042ffb 	stp	x27, x11, [sp, #64]
   14838:	f940528b 	ldr	x11, [x20, #160]
   1483c:	a9052be9 	stp	x9, x10, [sp, #80]
   14840:	f9405a89 	ldr	x9, [x20, #176]
   14844:	f900329b 	str	x27, [x20, #96]
   14848:	f900ca88 	str	x8, [x20, #400]
   1484c:	f900128c 	str	x12, [x20, #32]
   14850:	a90627eb 	stp	x11, x9, [sp, #96]
   14854:	34000828 	cbz	w8, 14958 <full_after_execute+0xd34>
   14858:	f940b283 	ldr	x3, [x20, #352]
   1485c:	f940ba84 	ldr	x4, [x20, #368]
   14860:	92407d08 	and	x8, x8, #0xffffffff
   14864:	8b0800a0 	add	x0, x5, x8
   14868:	9100c3e1 	add	x1, sp, #0x30
   1486c:	aa1f03e2 	mov	x2, xzr
   14870:	97fff469 	bl	11a14 <_call_goal8_asm_systemv>
   14874:	f9001280 	str	x0, [x20, #32]
   14878:	17fffd6c 	b	13e28 <full_after_execute+0x204>
   1487c:	f9400328 	ldr	x8, [x25]
   14880:	f940ea89 	ldr	x9, [x20, #464]
   14884:	f9001298 	str	x24, [x20, #32]
   14888:	8b29410a 	add	x10, x8, w9, uxtw
   1488c:	f940014b 	ldr	x11, [x10]
   14890:	f900fa8b 	str	x11, [x20, #496]
   14894:	1102412b 	add	w11, w9, #0x90
   14898:	f940054a 	ldr	x10, [x10, #8]
   1489c:	927c6d6b 	and	x11, x11, #0xfffffff0
   148a0:	f900f28a 	str	x10, [x20, #480]
   148a4:	1102012a 	add	w10, w9, #0x80
   148a8:	3ceb6900 	ldr	q0, [x8, x11]
   148ac:	927c6d4a 	and	x10, x10, #0xfffffff0
   148b0:	3d807280 	str	q0, [x20, #448]
   148b4:	3cea6900 	ldr	q0, [x8, x10]
   148b8:	1101c12a 	add	w10, w9, #0x70
   148bc:	927c6d4a 	and	x10, x10, #0xfffffff0
   148c0:	3d805680 	str	q0, [x20, #336]
   148c4:	3cea6900 	ldr	q0, [x8, x10]
   148c8:	1101812a 	add	w10, w9, #0x60
   148cc:	927c6d4a 	and	x10, x10, #0xfffffff0
   148d0:	3d805280 	str	q0, [x20, #320]
   148d4:	3cea6900 	ldr	q0, [x8, x10]
   148d8:	1101412a 	add	w10, w9, #0x50
   148dc:	927c6d4a 	and	x10, x10, #0xfffffff0
   148e0:	3d804e80 	str	q0, [x20, #304]
   148e4:	3cea6900 	ldr	q0, [x8, x10]
   148e8:	1101012a 	add	w10, w9, #0x40
   148ec:	927c6d4a 	and	x10, x10, #0xfffffff0
   148f0:	3d804a80 	str	q0, [x20, #288]
   148f4:	3cea6900 	ldr	q0, [x8, x10]
   148f8:	1100c12a 	add	w10, w9, #0x30
   148fc:	927c6d4a 	and	x10, x10, #0xfffffff0
   14900:	3d804680 	str	q0, [x20, #272]
   14904:	3cea6900 	ldr	q0, [x8, x10]
   14908:	91028128 	add	x8, x9, #0xa0
   1490c:	f900ea88 	str	x8, [x20, #464]
   14910:	3d804280 	str	q0, [x20, #256]
   14914:	940000bf 	bl	14c10 <std::chrono::_V2::steady_clock::now()@plt>
   14918:	f9400fe8 	ldr	x8, [sp, #24]
   1491c:	d503201f 	nop
   14920:	10103a41 	adr	x1, 35068 <full_after_g_spart_prof>
   14924:	cb080000 	sub	x0, x0, x8
   14928:	9400004a 	bl	14a50 <__aarch64_ldadd8_relax>
   1492c:	aa1803e0 	mov	x0, x24
   14930:	a94e4ff4 	ldp	x20, x19, [sp, #224]
   14934:	a94d57f6 	ldp	x22, x21, [sp, #208]
   14938:	a94c5ff8 	ldp	x24, x23, [sp, #192]
   1493c:	a94b67fa 	ldp	x26, x25, [sp, #176]
   14940:	a94a6ffc 	ldp	x28, x27, [sp, #160]
   14944:	a9497bfd 	ldp	x29, x30, [sp, #144]
   14948:	6d4823e9 	ldp	d9, d8, [sp, #128]
   1494c:	6d472beb 	ldp	d11, d10, [sp, #112]
   14950:	9103c3ff 	add	sp, sp, #0xf0
   14954:	d65f03c0 	ret
   14958:	52803202 	mov	w2, #0x190                 	// #400
   1495c:	1400000e 	b	14994 <full_after_execute+0xd70>
   14960:	90ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   14964:	913b8d09 	add	x9, x8, #0xee3
   14968:	52803802 	mov	w2, #0x1c0                 	// #448
   1496c:	b0ffff68 	adrp	x8, 1000 <typeinfo name for Boundary+0x1e0>
   14970:	9108d108 	add	x8, x8, #0x234
   14974:	a900a7e8 	stp	x8, x9, [sp, #8]
   14978:	14000007 	b	14994 <full_after_execute+0xd70>
   1497c:	90ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   14980:	913f3909 	add	x9, x8, #0xfce
   14984:	52802b02 	mov	w2, #0x158                 	// #344
   14988:	90ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   1498c:	913ac108 	add	x8, x8, #0xeb0
   14990:	a900a7e8 	stp	x8, x9, [sp, #8]
   14994:	a94083e3 	ldp	x3, x0, [sp, #8]
   14998:	90ffff61 	adrp	x1, 0 <__abi_tag-0x2c4>
   1499c:	913fec21 	add	x1, x1, #0xffb
   149a0:	b0ffff64 	adrp	x4, 1000 <typeinfo name for Boundary+0x1e0>
   149a4:	9105f084 	add	x4, x4, #0x17c
   149a8:	97fff90c 	bl	12dd8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
   149ac:	d503201f 	nop
   149b0:	10f646e0 	adr	x0, 128c <typeinfo name for Boundary+0x46c>
   149b4:	b0ffff61 	adrp	x1, 1000 <typeinfo name for Boundary+0x1e0>
   149b8:	91060821 	add	x1, x1, #0x182
   149bc:	b0ffff63 	adrp	x3, 1000 <typeinfo name for Boundary+0x1e0>
   149c0:	9100fc63 	add	x3, x3, #0x3f
   149c4:	b0ffff64 	adrp	x4, 1000 <typeinfo name for Boundary+0x1e0>
   149c8:	9105f084 	add	x4, x4, #0x17c
   149cc:	52801f42 	mov	w2, #0xfa                  	// #250
   149d0:	97fff902 	bl	12dd8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
   149d4:	b0ffff60 	adrp	x0, 1000 <typeinfo name for Boundary+0x1e0>
   149d8:	91107400 	add	x0, x0, #0x41d
   149dc:	b0ffff61 	adrp	x1, 1000 <typeinfo name for Boundary+0x1e0>
   149e0:	91060821 	add	x1, x1, #0x182
   149e4:	b0ffff63 	adrp	x3, 1000 <typeinfo name for Boundary+0x1e0>
   149e8:	9100fc63 	add	x3, x3, #0x3f
   149ec:	b0ffff64 	adrp	x4, 1000 <typeinfo name for Boundary+0x1e0>
   149f0:	9105f084 	add	x4, x4, #0x17c
   149f4:	52802002 	mov	w2, #0x100                 	// #256
   149f8:	97fff8f8 	bl	12dd8 <private_assert_failed(char const*, char const*, int, char const*, char const*)>
   149fc:	90ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   14a00:	913ac109 	add	x9, x8, #0xeb0
   14a04:	52802b02 	mov	w2, #0x158                 	// #344
   14a08:	90ffff68 	adrp	x8, 0 <__abi_tag-0x2c4>
   14a0c:	913f3908 	add	x8, x8, #0xfce
   14a10:	a900a3e9 	stp	x9, x8, [sp, #8]
   14a14:	17ffffe0 	b	14994 <full_after_execute+0xd70>
   14a18:	14000003 	b	14a24 <full_after_execute+0xe00>
   14a1c:	14000002 	b	14a24 <full_after_execute+0xe00>
   14a20:	14000001 	b	14a24 <full_after_execute+0xe00>
   14a24:	aa0003f4 	mov	x20, x0
   14a28:	9400007a 	bl	14c10 <std::chrono::_V2::steady_clock::now()@plt>
   14a2c:	f9400fe8 	ldr	x8, [sp, #24]
   14a30:	d503201f 	nop
   14a34:	101031a1 	adr	x1, 35068 <full_after_g_spart_prof>
   14a38:	cb080000 	sub	x0, x0, x8
   14a3c:	94000005 	bl	14a50 <__aarch64_ldadd8_relax>
   14a40:	aa1403e0 	mov	x0, x20
   14a44:	94000077 	bl	14c20 <_Unwind_Resume@plt>
	...

0000000000014a50 <__aarch64_ldadd8_relax>:
   14a50:	d503245f 	bti	c
   14a54:	b0000110 	adrp	x16, 35000 <full_before_g_spart_prof+0x78>
   14a58:	39452210 	ldrb	w16, [x16, #328]
   14a5c:	34000070 	cbz	w16, 14a68 <__aarch64_ldadd8_relax+0x18>
   14a60:	f8200020 	ldadd	x0, x0, [x1]
   14a64:	d65f03c0 	ret
   14a68:	aa0003f0 	mov	x16, x0
   14a6c:	c85f7c20 	ldxr	x0, [x1]
   14a70:	8b100011 	add	x17, x0, x16
   14a74:	c80f7c31 	stxr	w15, x17, [x1]
   14a78:	35ffffaf 	cbnz	w15, 14a6c <__aarch64_ldadd8_relax+0x1c>
   14a7c:	d65f03c0 	ret

0000000000014a80 <init_have_lse_atomics>:
   14a80:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   14a84:	d2800200 	mov	x0, #0x10                  	// #16
   14a88:	910003fd 	mov	x29, sp
   14a8c:	94000069 	bl	14c30 <__getauxval@plt>
   14a90:	53082000 	ubfx	w0, w0, #8, #1
   14a94:	b0000101 	adrp	x1, 35000 <full_before_g_spart_prof+0x78>
   14a98:	a8c17bfd 	ldp	x29, x30, [sp], #16
   14a9c:	39052020 	strb	w0, [x1, #328]
   14aa0:	d65f03c0 	ret

Disassembly of section .init:

0000000000014aa4 <_init>:
   14aa4:	d503201f 	nop
   14aa8:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   14aac:	910003fd 	mov	x29, sp
   14ab0:	97fff3a1 	bl	11934 <call_weak_fn>
   14ab4:	a8c17bfd 	ldp	x29, x30, [sp], #16
   14ab8:	d65f03c0 	ret

Disassembly of section .fini:

0000000000014abc <_fini>:
   14abc:	d503201f 	nop
   14ac0:	a9bf7bfd 	stp	x29, x30, [sp, #-16]!
   14ac4:	910003fd 	mov	x29, sp
   14ac8:	a8c17bfd 	ldp	x29, x30, [sp], #16
   14acc:	d65f03c0 	ret

Disassembly of section .plt:

0000000000014ad0 <abort@plt-0x20>:
   14ad0:	a9bf7bf0 	stp	x16, x30, [sp, #-16]!
   14ad4:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14ad8:	f9476611 	ldr	x17, [x16, #3784]
   14adc:	913b2210 	add	x16, x16, #0xec8
   14ae0:	d61f0220 	br	x17
   14ae4:	d503201f 	nop
   14ae8:	d503201f 	nop
   14aec:	d503201f 	nop

0000000000014af0 <abort@plt>:
   14af0:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14af4:	f9476a11 	ldr	x17, [x16, #3792]
   14af8:	913b4210 	add	x16, x16, #0xed0
   14afc:	d61f0220 	br	x17

0000000000014b00 <__libc_start_main@plt>:
   14b00:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b04:	f9476e11 	ldr	x17, [x16, #3800]
   14b08:	913b6210 	add	x16, x16, #0xed8
   14b0c:	d61f0220 	br	x17

0000000000014b10 <__gmon_start__@plt>:
   14b10:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b14:	f9477211 	ldr	x17, [x16, #3808]
   14b18:	913b8210 	add	x16, x16, #0xee0
   14b1c:	d61f0220 	br	x17

0000000000014b20 <__cxa_finalize@plt>:
   14b20:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b24:	f9477611 	ldr	x17, [x16, #3816]
   14b28:	913ba210 	add	x16, x16, #0xee8
   14b2c:	d61f0220 	br	x17

0000000000014b30 <__cxa_allocate_exception@plt>:
   14b30:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b34:	f9477a11 	ldr	x17, [x16, #3824]
   14b38:	913bc210 	add	x16, x16, #0xef0
   14b3c:	d61f0220 	br	x17

0000000000014b40 <__cxa_throw@plt>:
   14b40:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b44:	f9477e11 	ldr	x17, [x16, #3832]
   14b48:	913be210 	add	x16, x16, #0xef8
   14b4c:	d61f0220 	br	x17

0000000000014b50 <fopen@plt>:
   14b50:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b54:	f9478211 	ldr	x17, [x16, #3840]
   14b58:	913c0210 	add	x16, x16, #0xf00
   14b5c:	d61f0220 	br	x17

0000000000014b60 <fwrite@plt>:
   14b60:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b64:	f9478611 	ldr	x17, [x16, #3848]
   14b68:	913c2210 	add	x16, x16, #0xf08
   14b6c:	d61f0220 	br	x17

0000000000014b70 <printf@plt>:
   14b70:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b74:	f9478a11 	ldr	x17, [x16, #3856]
   14b78:	913c4210 	add	x16, x16, #0xf10
   14b7c:	d61f0220 	br	x17

0000000000014b80 <fprintf@plt>:
   14b80:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b84:	f9478e11 	ldr	x17, [x16, #3864]
   14b88:	913c6210 	add	x16, x16, #0xf18
   14b8c:	d61f0220 	br	x17

0000000000014b90 <memset@plt>:
   14b90:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14b94:	f9479211 	ldr	x17, [x16, #3872]
   14b98:	913c8210 	add	x16, x16, #0xf20
   14b9c:	d61f0220 	br	x17

0000000000014ba0 <memcpy@plt>:
   14ba0:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14ba4:	f9479611 	ldr	x17, [x16, #3880]
   14ba8:	913ca210 	add	x16, x16, #0xf28
   14bac:	d61f0220 	br	x17

0000000000014bb0 <__cxa_begin_catch@plt>:
   14bb0:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14bb4:	f9479a11 	ldr	x17, [x16, #3888]
   14bb8:	913cc210 	add	x16, x16, #0xf30
   14bbc:	d61f0220 	br	x17

0000000000014bc0 <__cxa_end_catch@plt>:
   14bc0:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14bc4:	f9479e11 	ldr	x17, [x16, #3896]
   14bc8:	913ce210 	add	x16, x16, #0xf38
   14bcc:	d61f0220 	br	x17

0000000000014bd0 <bcmp@plt>:
   14bd0:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14bd4:	f947a211 	ldr	x17, [x16, #3904]
   14bd8:	913d0210 	add	x16, x16, #0xf40
   14bdc:	d61f0220 	br	x17

0000000000014be0 <ferror@plt>:
   14be0:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14be4:	f947a611 	ldr	x17, [x16, #3912]
   14be8:	913d2210 	add	x16, x16, #0xf48
   14bec:	d61f0220 	br	x17

0000000000014bf0 <fclose@plt>:
   14bf0:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14bf4:	f947aa11 	ldr	x17, [x16, #3920]
   14bf8:	913d4210 	add	x16, x16, #0xf50
   14bfc:	d61f0220 	br	x17

0000000000014c00 <perror@plt>:
   14c00:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14c04:	f947ae11 	ldr	x17, [x16, #3928]
   14c08:	913d6210 	add	x16, x16, #0xf58
   14c0c:	d61f0220 	br	x17

0000000000014c10 <std::chrono::_V2::steady_clock::now()@plt>:
   14c10:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14c14:	f947b211 	ldr	x17, [x16, #3936]
   14c18:	913d8210 	add	x16, x16, #0xf60
   14c1c:	d61f0220 	br	x17

0000000000014c20 <_Unwind_Resume@plt>:
   14c20:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14c24:	f947b611 	ldr	x17, [x16, #3944]
   14c28:	913da210 	add	x16, x16, #0xf68
   14c2c:	d61f0220 	br	x17

0000000000014c30 <__getauxval@plt>:
   14c30:	90000110 	adrp	x16, 34000 <_DYNAMIC+0xf378>
   14c34:	f947ba11 	ldr	x17, [x16, #3952]
   14c38:	913dc210 	add	x16, x16, #0xf70
   14c3c:	d61f0220 	br	x17

EXIT 0
