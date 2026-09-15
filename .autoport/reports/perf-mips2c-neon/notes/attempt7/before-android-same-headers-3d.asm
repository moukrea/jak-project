
.autoport/reports/perf-mips2c-neon/notes/attempt7/before-android-same-headers.o:	file format elf64-littleaarch64

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
       0: d10383ff     	sub	sp, sp, #0xe0
       4: fd0033ea     	str	d10, [sp, #0x60]
       8: 6d0723e9     	stp	d9, d8, [sp, #0x70]
       c: a9087bfd     	stp	x29, x30, [sp, #0x80]
      10: a9096ffc     	stp	x28, x27, [sp, #0x90]
      14: a90a67fa     	stp	x26, x25, [sp, #0xa0]
      18: a90b5ff8     	stp	x24, x23, [sp, #0xb0]
      1c: a90c57f6     	stp	x22, x21, [sp, #0xc0]
      20: a90d4ff4     	stp	x20, x19, [sp, #0xd0]
      24: 910203fd     	add	x29, sp, #0x80
      28: d53bd058     	mrs	x24, TPIDR_EL0
      2c: aa0003f4     	mov	x20, x0
      30: f9401708     	ldr	x8, [x24, #0x28]
      34: f81d83a8     	stur	x8, [x29, #-0x28]
      38: 94000000     	bl	0x38 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x38>
		0000000000000038:  R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
      3c: f9000be0     	str	x0, [sp, #0x10]
      40: 90000019     	adrp	x25, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000040:  R_AARCH64_ADR_GOT_PAGE	g_spart_prof
      44: 52800020     	mov	w0, #0x1                // =1
      48: f9400339     	ldr	x25, [x25]
		0000000000000048:  R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
      4c: 91008321     	add	x1, x25, #0x20
      50: 94000000     	bl	0x50 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x50>
		0000000000000050:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
      54: 9000001a     	adrp	x26, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000054:  R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
      58: f940ea88     	ldr	x8, [x20, #0x1d0]
      5c: aa1403fb     	mov	x27, x20
      60: f940035a     	ldr	x26, [x26]
		0000000000000060:  R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
      64: f940fa8a     	ldr	x10, [x20, #0x1f0]
      68: 9000001c     	adrp	x28, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000068:  R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::cache
      6c: d1028108     	sub	x8, x8, #0xa0
      70: f9400349     	ldr	x9, [x26]
      74: f900ea88     	str	x8, [x20, #0x1d0]
      78: f828492a     	str	x10, [x9, w8, uxtw]
      7c: f9400348     	ldr	x8, [x26]
      80: b941d289     	ldr	w9, [x20, #0x1d0]
      84: f940f28a     	ldr	x10, [x20, #0x1e0]
      88: 8b090108     	add	x8, x8, x9
      8c: f900050a     	str	x10, [x8, #0x8]
      90: b941d288     	ldr	w8, [x20, #0x1d0]
      94: f940ca89     	ldr	x9, [x20, #0x190]
      98: f940034a     	ldr	x10, [x26]
      9c: 3dc04280     	ldr	q0, [x20, #0x100]
      a0: 1100c108     	add	w8, w8, #0x30
      a4: f900f289     	str	x9, [x20, #0x1e0]
      a8: 927c6d08     	and	x8, x8, #0xfffffff0
      ac: 3ca86940     	str	q0, [x10, x8]
      b0: b941d288     	ldr	w8, [x20, #0x1d0]
      b4: f9400349     	ldr	x9, [x26]
      b8: 3dc04680     	ldr	q0, [x20, #0x110]
      bc: 11010108     	add	w8, w8, #0x40
      c0: 927c6d08     	and	x8, x8, #0xfffffff0
      c4: 3ca86920     	str	q0, [x9, x8]
      c8: b941d288     	ldr	w8, [x20, #0x1d0]
      cc: f9400349     	ldr	x9, [x26]
      d0: 3dc04a80     	ldr	q0, [x20, #0x120]
      d4: 11014108     	add	w8, w8, #0x50
      d8: 927c6d08     	and	x8, x8, #0xfffffff0
      dc: 3ca86920     	str	q0, [x9, x8]
      e0: b941d288     	ldr	w8, [x20, #0x1d0]
      e4: f9400349     	ldr	x9, [x26]
      e8: 3dc04e80     	ldr	q0, [x20, #0x130]
      ec: 11018108     	add	w8, w8, #0x60
      f0: 927c6d08     	and	x8, x8, #0xfffffff0
      f4: 3ca86920     	str	q0, [x9, x8]
      f8: b941d288     	ldr	w8, [x20, #0x1d0]
      fc: f9400349     	ldr	x9, [x26]
     100: 3dc05280     	ldr	q0, [x20, #0x140]
     104: 1101c108     	add	w8, w8, #0x70
     108: 927c6d08     	and	x8, x8, #0xfffffff0
     10c: 3ca86920     	str	q0, [x9, x8]
     110: b941d288     	ldr	w8, [x20, #0x1d0]
     114: f9400349     	ldr	x9, [x26]
     118: 3dc05680     	ldr	q0, [x20, #0x150]
     11c: 11020108     	add	w8, w8, #0x80
     120: 927c6d08     	and	x8, x8, #0xfffffff0
     124: 3ca86920     	str	q0, [x9, x8]
     128: b941d288     	ldr	w8, [x20, #0x1d0]
     12c: f9400349     	ldr	x9, [x26]
     130: 3dc07280     	ldr	q0, [x20, #0x1c0]
     134: 11024108     	add	w8, w8, #0x90
     138: 927c6d08     	and	x8, x8, #0xfffffff0
     13c: 3ca86920     	str	q0, [x9, x8]
     140: f8440f68     	ldr	x8, [x27, #0x40]!
     144: f9400b69     	ldr	x9, [x27, #0x10]
     148: f940136a     	ldr	x10, [x27, #0x20]
     14c: a901ffff     	stp	xzr, xzr, [sp, #0x18]
     150: f900e288     	str	x8, [x20, #0x1c0]
     154: f9401b68     	ldr	x8, [x27, #0x30]
     158: 3cc183e0     	ldur	q0, [sp, #0x18]
     15c: f900aa89     	str	x9, [x20, #0x150]
     160: f9402369     	ldr	x9, [x27, #0x40]
     164: f9008288     	str	x8, [x20, #0x100]
     168: f940ea88     	ldr	x8, [x20, #0x1d0]
     16c: f900a28a     	str	x10, [x20, #0x140]
     170: f9402b6a     	ldr	x10, [x27, #0x50]
     174: 91004108     	add	x8, x8, #0x10
     178: f9009a89     	str	x9, [x20, #0x130]
     17c: f9400349     	ldr	x9, [x26]
     180: f900928a     	str	x10, [x20, #0x120]
     184: f9008a88     	str	x8, [x20, #0x110]
     188: 927c6d08     	and	x8, x8, #0xfffffff0
     18c: f940039c     	ldr	x28, [x28]
		000000000000018c:  R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
     190: 3ca86920     	str	q0, [x9, x8]
     194: f9400388     	ldr	x8, [x28]
     198: b9800108     	ldrsw	x8, [x8]
     19c: 72000d1f     	tst	w8, #0xf
     1a0: f81f0368     	stur	x8, [x27, #-0x10]
     1a4: 54006481     	b.ne	0xe34 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe34>
     1a8: f9400349     	ldr	x9, [x26]
     1ac: 927c6d08     	and	x8, x8, #0xfffffff0
     1b0: 2f00e408     	movi	d8, #0000000000000000
     1b4: 2f00e409     	movi	d9, #0000000000000000
     1b8: 1e2e100a     	fmov	s10, #1.00000000
     1bc: 910b1375     	add	x21, x27, #0x2c4
     1c0: 3ce86920     	ldr	q0, [x9, x8]
     1c4: b941d288     	ldr	w8, [x20, #0x1d0]
     1c8: 92800016     	mov	x22, #-0x1              // =-1
     1cc: 3d80e280     	str	q0, [x20, #0x380]
     1d0: 11008108     	add	w8, w8, #0x20
     1d4: f941c68a     	ldr	x10, [x20, #0x388]
     1d8: 394e028b     	ldrb	w11, [x20, #0x380]
     1dc: 927c6d08     	and	x8, x8, #0xfffffff0
     1e0: 8b080128     	add	x8, x9, x8
     1e4: a9032a8b     	stp	x11, x10, [x20, #0x30]
     1e8: a900290b     	stp	x11, x10, [x8]
     1ec: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		00000000000001ec:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x316
     1f0: 91000109     	add	x9, x8, #0x0
		00000000000001f0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x316
     1f4: f940aa93     	ldr	x19, [x20, #0x150]
     1f8: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		00000000000001f8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x311
     1fc: 91000108     	add	x8, x8, #0x0
		00000000000001fc:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x311
     200: a90023e9     	stp	x9, x8, [sp]
     204: 1400000e     	b	0x23c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x23c>
     208: f9409a88     	ldr	x8, [x20, #0x130]
     20c: f940aa89     	ldr	x9, [x20, #0x150]
     210: f940a28a     	ldr	x10, [x20, #0x140]
     214: f940828b     	ldr	x11, [x20, #0x100]
     218: f1000508     	subs	x8, x8, #0x1
     21c: 91024133     	add	x19, x9, #0x90
     220: f9009a88     	str	x8, [x20, #0x130]
     224: 9100c148     	add	x8, x10, #0x30
     228: 91000577     	add	x23, x11, #0x1
     22c: f900aa93     	str	x19, [x20, #0x150]
     230: f900a288     	str	x8, [x20, #0x140]
     234: f9008297     	str	x23, [x20, #0x100]
     238: 54005460     	b.eq	0xcc4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcc4>
     23c: 91010321     	add	x1, x25, #0x40
     240: 52800020     	mov	w0, #0x1                // =1
     244: 94000000     	bl	0x244 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x244>
		0000000000000244:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
     248: f9400345     	ldr	x5, [x26]
     24c: 92407e69     	and	x9, x19, #0xffffffff
     250: b941728b     	ldr	w11, [x20, #0x170]
     254: 8b0900a8     	add	x8, x5, x9
     258: b980810a     	ldrsw	x10, [x8, #0x80]
     25c: 6b0b015f     	cmp	w10, w11
     260: f9001a8a     	str	x10, [x20, #0x30]
     264: 54fffd20     	b.eq	0x208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
     268: b941228c     	ldr	w12, [x20, #0x120]
     26c: b980690a     	ldrsw	x10, [x8, #0x68]
     270: 6b0b019f     	cmp	w12, w11
     274: f9001a8a     	str	x10, [x20, #0x30]
     278: 54000300     	b.eq	0x2d8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d8>
     27c: 9273014b     	and	x11, x10, #0x2000
     280: f9001a8b     	str	x11, [x20, #0x30]
     284: 376802aa     	tbnz	w10, #0xd, 0x2d8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d8>
     288: b9806509     	ldrsw	x9, [x8, #0x64]
     28c: f9002296     	str	x22, [x20, #0x40]
     290: f9001a89     	str	x9, [x20, #0x30]
     294: 34004dc9     	cbz	w9, 0xc4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
     298: b9806909     	ldrsw	x9, [x8, #0x68]
     29c: 927a012a     	and	x10, x9, #0x40
     2a0: 9279f92b     	and	x11, x9, #0xffffffffffffffbf
     2a4: f9001a8a     	str	x10, [x20, #0x30]
     2a8: f900228b     	str	x11, [x20, #0x40]
     2ac: b900690b     	str	w11, [x8, #0x68]
     2b0: 3637fac9     	tbz	w9, #0x6, 0x208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
     2b4: f9400348     	ldr	x8, [x26]
     2b8: b9415289     	ldr	w9, [x20, #0x150]
     2bc: b941428a     	ldr	w10, [x20, #0x140]
     2c0: 8b090109     	add	x9, x8, x9
     2c4: 8b0a0108     	add	x8, x8, x10
     2c8: b9807d29     	ldrsw	x9, [x9, #0x7c]
     2cc: f9001a89     	str	x9, [x20, #0x30]
     2d0: b9002d09     	str	w9, [x8, #0x2c]
     2d4: 17ffffcd     	b	0x208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
     2d8: b941d28b     	ldr	w11, [x20, #0x1d0]
     2dc: b980650a     	ldrsw	x10, [x8, #0x64]
     2e0: f9002296     	str	x22, [x20, #0x40]
     2e4: 1100816b     	add	w11, w11, #0x20
     2e8: f9001a8a     	str	x10, [x20, #0x30]
     2ec: 3100055f     	cmn	w10, #0x1
     2f0: 927c6d6b     	and	x11, x11, #0xfffffff0
     2f4: 3ceb68a0     	ldr	q0, [x5, x11]
     2f8: 3d800360     	str	q0, [x27]
     2fc: 54000260     	b.eq	0x348 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x348>
     300: f9402289     	ldr	x9, [x20, #0x40]
     304: 6f00e401     	movi	v1.2d, #0000000000000000
     308: cb090149     	sub	x9, x10, x9
     30c: 1e270120     	fmov	s0, w9
     310: d360fd2b     	lsr	x11, x9, #32
     314: f9002289     	str	x9, [x20, #0x40]
     318: 4e0c1d60     	mov	v0.s[1], w11
     31c: 9101228b     	add	x11, x20, #0x48
     320: 4d408160     	ld1	{ v0.s }[2], [x11]
     324: 9101328b     	add	x11, x20, #0x4c
     328: 4d409160     	ld1	{ v0.s }[3], [x11]
     32c: 4ea16400     	smax	v0.4s, v0.4s, v1.4s
     330: 3d800e80     	str	q0, [x20, #0x30]
     334: 340048ca     	cbz	w10, 0xc4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
     338: f9401a89     	ldr	x9, [x20, #0x30]
     33c: b9006509     	str	w9, [x8, #0x64]
     340: f9400345     	ldr	x5, [x26]
     344: b9415289     	ldr	w9, [x20, #0x150]
     348: 8b0900a8     	add	x8, x5, x9
     34c: b9806909     	ldrsw	x9, [x8, #0x68]
     350: 927a012a     	and	x10, x9, #0x40
     354: 9279f92b     	and	x11, x9, #0xffffffffffffffbf
     358: f9001a8a     	str	x10, [x20, #0x30]
     35c: f900228b     	str	x11, [x20, #0x40]
     360: b900690b     	str	w11, [x8, #0x68]
     364: 36300129     	tbz	w9, #0x6, 0x388 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x388>
     368: f9400348     	ldr	x8, [x26]
     36c: b9415289     	ldr	w9, [x20, #0x150]
     370: b941428a     	ldr	w10, [x20, #0x140]
     374: 8b090109     	add	x9, x8, x9
     378: 8b0a0108     	add	x8, x8, x10
     37c: b9807d29     	ldrsw	x9, [x9, #0x7c]
     380: f9001a89     	str	x9, [x20, #0x30]
     384: b9002d09     	str	w9, [x8, #0x2c]
     388: f9400348     	ldr	x8, [x26]
     38c: b941528a     	ldr	w10, [x20, #0x150]
     390: 8b0a0109     	add	x9, x8, x10
     394: b980712b     	ldrsw	x11, [x9, #0x70]
     398: f940ea89     	ldr	x9, [x20, #0x1d0]
     39c: f900ca8b     	str	x11, [x20, #0x190]
     3a0: 34000b8b     	cbz	w11, 0x510 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x510>
     3a4: d1018129     	sub	x9, x9, #0x60
     3a8: 3dc07280     	ldr	q0, [x20, #0x1c0]
     3ac: f900ea89     	str	x9, [x20, #0x1d0]
     3b0: 927c6d29     	and	x9, x9, #0xfffffff0
     3b4: 3ca96900     	str	q0, [x8, x9]
     3b8: b941d288     	ldr	w8, [x20, #0x1d0]
     3bc: f9400349     	ldr	x9, [x26]
     3c0: 3dc05680     	ldr	q0, [x20, #0x150]
     3c4: 11004108     	add	w8, w8, #0x10
     3c8: 927c6d08     	and	x8, x8, #0xfffffff0
     3cc: 3ca86920     	str	q0, [x9, x8]
     3d0: b941d288     	ldr	w8, [x20, #0x1d0]
     3d4: f9400349     	ldr	x9, [x26]
     3d8: 3dc05280     	ldr	q0, [x20, #0x140]
     3dc: 11008108     	add	w8, w8, #0x20
     3e0: 927c6d08     	and	x8, x8, #0xfffffff0
     3e4: 3ca86920     	str	q0, [x9, x8]
     3e8: b941d288     	ldr	w8, [x20, #0x1d0]
     3ec: f9400349     	ldr	x9, [x26]
     3f0: 3dc04280     	ldr	q0, [x20, #0x100]
     3f4: 1100c108     	add	w8, w8, #0x30
     3f8: 927c6d08     	and	x8, x8, #0xfffffff0
     3fc: 3ca86920     	str	q0, [x9, x8]
     400: b941d288     	ldr	w8, [x20, #0x1d0]
     404: f9400349     	ldr	x9, [x26]
     408: 3dc04e80     	ldr	q0, [x20, #0x130]
     40c: 11010108     	add	w8, w8, #0x40
     410: 927c6d08     	and	x8, x8, #0xfffffff0
     414: 3ca86920     	str	q0, [x9, x8]
     418: f940e288     	ldr	x8, [x20, #0x1c0]
     41c: b941d28a     	ldr	w10, [x20, #0x1d0]
     420: f940aa89     	ldr	x9, [x20, #0x150]
     424: f940a28b     	ldr	x11, [x20, #0x140]
     428: f940034c     	ldr	x12, [x26]
     42c: 3dc04a80     	ldr	q0, [x20, #0x120]
     430: f9002288     	str	x8, [x20, #0x40]
     434: 11014148     	add	w8, w10, #0x50
     438: f9002a89     	str	x9, [x20, #0x50]
     43c: 927c6d09     	and	x9, x8, #0xfffffff0
     440: b9419288     	ldr	w8, [x20, #0x190]
     444: f900328b     	str	x11, [x20, #0x60]
     448: 3ca96980     	str	q0, [x12, x9]
     44c: f9402289     	ldr	x9, [x20, #0x40]
     450: f9402a8a     	ldr	x10, [x20, #0x50]
     454: f940328b     	ldr	x11, [x20, #0x60]
     458: a901abe9     	stp	x9, x10, [sp, #0x18]
     45c: f9403a89     	ldr	x9, [x20, #0x70]
     460: f940428a     	ldr	x10, [x20, #0x80]
     464: a902a7eb     	stp	x11, x9, [sp, #0x28]
     468: f9404a8b     	ldr	x11, [x20, #0x90]
     46c: f9405289     	ldr	x9, [x20, #0xa0]
     470: a903afea     	stp	x10, x11, [sp, #0x38]
     474: f9405a8a     	ldr	x10, [x20, #0xb0]
     478: a904abe9     	stp	x9, x10, [sp, #0x48]
     47c: 34004b08     	cbz	w8, 0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     480: f9400345     	ldr	x5, [x26]
     484: f940b283     	ldr	x3, [x20, #0x160]
     488: f940ba84     	ldr	x4, [x20, #0x170]
     48c: 8b0800a0     	add	x0, x5, x8
     490: 910063e1     	add	x1, sp, #0x18
     494: aa1f03e2     	mov	x2, xzr
     498: 94000000     	bl	0x498 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x498>
		0000000000000498:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     49c: f940ea89     	ldr	x9, [x20, #0x1d0]
     4a0: f9400348     	ldr	x8, [x26]
     4a4: f9001280     	str	x0, [x20, #0x20]
     4a8: 927c6d2a     	and	x10, x9, #0xfffffff0
     4ac: 3cea6900     	ldr	q0, [x8, x10]
     4b0: 1100412a     	add	w10, w9, #0x10
     4b4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4b8: 3d807280     	str	q0, [x20, #0x1c0]
     4bc: 3cea6900     	ldr	q0, [x8, x10]
     4c0: 1100812a     	add	w10, w9, #0x20
     4c4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4c8: 3d805680     	str	q0, [x20, #0x150]
     4cc: 3cea6900     	ldr	q0, [x8, x10]
     4d0: 1100c12a     	add	w10, w9, #0x30
     4d4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4d8: 3d805280     	str	q0, [x20, #0x140]
     4dc: 3cea6900     	ldr	q0, [x8, x10]
     4e0: 1101012a     	add	w10, w9, #0x40
     4e4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4e8: 3d804280     	str	q0, [x20, #0x100]
     4ec: 3cea6900     	ldr	q0, [x8, x10]
     4f0: 1101412a     	add	w10, w9, #0x50
     4f4: 91018129     	add	x9, x9, #0x60
     4f8: 927c6d4a     	and	x10, x10, #0xfffffff0
     4fc: 3d804e80     	str	q0, [x20, #0x130]
     500: 3cea6900     	ldr	q0, [x8, x10]
     504: b941528a     	ldr	w10, [x20, #0x150]
     508: f900ea89     	str	x9, [x20, #0x1d0]
     50c: 3d804a80     	str	q0, [x20, #0x120]
     510: 8b0a010a     	add	x10, x8, x10
     514: 11008129     	add	w9, w9, #0x20
     518: b980794c     	ldrsw	x12, [x10, #0x78]
     51c: 927c6d29     	and	x9, x9, #0xfffffff0
     520: f9002a8c     	str	x12, [x20, #0x50]
     524: b980754b     	ldrsw	x11, [x10, #0x74]
     528: f9001a8b     	str	x11, [x20, #0x30]
     52c: 3ce96900     	ldr	q0, [x8, x9]
     530: 3d800360     	str	q0, [x27]
     534: 34000c8c     	cbz	w12, 0x6c4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6c4>
     538: f9402288     	ldr	x8, [x20, #0x40]
     53c: eb080168     	subs	x8, x11, x8
     540: f9001a88     	str	x8, [x20, #0x30]
     544: b9007548     	str	w8, [x10, #0x74]
     548: 54000be5     	b.pl	0x6c4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6c4>
     54c: f940ea88     	ldr	x8, [x20, #0x1d0]
     550: f9400349     	ldr	x9, [x26]
     554: 3dc07280     	ldr	q0, [x20, #0x1c0]
     558: d1018108     	sub	x8, x8, #0x60
     55c: f900ea88     	str	x8, [x20, #0x1d0]
     560: 927c6d08     	and	x8, x8, #0xfffffff0
     564: 3ca86920     	str	q0, [x9, x8]
     568: b941d288     	ldr	w8, [x20, #0x1d0]
     56c: f9400349     	ldr	x9, [x26]
     570: 3dc05680     	ldr	q0, [x20, #0x150]
     574: 11004108     	add	w8, w8, #0x10
     578: 927c6d08     	and	x8, x8, #0xfffffff0
     57c: 3ca86920     	str	q0, [x9, x8]
     580: b941d288     	ldr	w8, [x20, #0x1d0]
     584: f9400349     	ldr	x9, [x26]
     588: 3dc05280     	ldr	q0, [x20, #0x140]
     58c: 11008108     	add	w8, w8, #0x20
     590: 927c6d08     	and	x8, x8, #0xfffffff0
     594: 3ca86920     	str	q0, [x9, x8]
     598: b941d288     	ldr	w8, [x20, #0x1d0]
     59c: f9400349     	ldr	x9, [x26]
     5a0: 3dc04280     	ldr	q0, [x20, #0x100]
     5a4: 1100c108     	add	w8, w8, #0x30
     5a8: 927c6d08     	and	x8, x8, #0xfffffff0
     5ac: 3ca86920     	str	q0, [x9, x8]
     5b0: b941d288     	ldr	w8, [x20, #0x1d0]
     5b4: f9400349     	ldr	x9, [x26]
     5b8: 3dc04e80     	ldr	q0, [x20, #0x130]
     5bc: 11010108     	add	w8, w8, #0x40
     5c0: 927c6d08     	and	x8, x8, #0xfffffff0
     5c4: 3ca86920     	str	q0, [x9, x8]
     5c8: b941d288     	ldr	w8, [x20, #0x1d0]
     5cc: f9400349     	ldr	x9, [x26]
     5d0: 3dc04a80     	ldr	q0, [x20, #0x120]
     5d4: 11014108     	add	w8, w8, #0x50
     5d8: 927c6d08     	and	x8, x8, #0xfffffff0
     5dc: 3ca86920     	str	q0, [x9, x8]
     5e0: f940e289     	ldr	x9, [x20, #0x1c0]
     5e4: f940a28a     	ldr	x10, [x20, #0x140]
     5e8: f940aa8b     	ldr	x11, [x20, #0x150]
     5ec: f9400f88     	ldr	x8, [x28, #0x18]
     5f0: b981f28c     	ldrsw	x12, [x20, #0x1f0]
     5f4: f9002289     	str	x9, [x20, #0x40]
     5f8: f9003a8a     	str	x10, [x20, #0x70]
     5fc: f900328b     	str	x11, [x20, #0x60]
     600: b9800108     	ldrsw	x8, [x8]
     604: f900128c     	str	x12, [x20, #0x20]
     608: f9402a8c     	ldr	x12, [x20, #0x50]
     60c: a902abeb     	stp	x11, x10, [sp, #0x28]
     610: f9404a8b     	ldr	x11, [x20, #0x90]
     614: f9405a8a     	ldr	x10, [x20, #0xb0]
     618: a901b3e9     	stp	x9, x12, [sp, #0x18]
     61c: f9404289     	ldr	x9, [x20, #0x80]
     620: f900ca88     	str	x8, [x20, #0x190]
     624: a903afe9     	stp	x9, x11, [sp, #0x38]
     628: f9405289     	ldr	x9, [x20, #0xa0]
     62c: a904abe9     	stp	x9, x10, [sp, #0x48]
     630: 34003d68     	cbz	w8, 0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     634: f9400345     	ldr	x5, [x26]
     638: f940b283     	ldr	x3, [x20, #0x160]
     63c: 92407d08     	and	x8, x8, #0xffffffff
     640: f940ba84     	ldr	x4, [x20, #0x170]
     644: 8b0800a0     	add	x0, x5, x8
     648: 910063e1     	add	x1, sp, #0x18
     64c: aa1f03e2     	mov	x2, xzr
     650: 94000000     	bl	0x650 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x650>
		0000000000000650:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     654: f940ea88     	ldr	x8, [x20, #0x1d0]
     658: f9400349     	ldr	x9, [x26]
     65c: f9001280     	str	x0, [x20, #0x20]
     660: 927c6d0a     	and	x10, x8, #0xfffffff0
     664: 3cea6920     	ldr	q0, [x9, x10]
     668: 1100410a     	add	w10, w8, #0x10
     66c: 927c6d4a     	and	x10, x10, #0xfffffff0
     670: 3d807280     	str	q0, [x20, #0x1c0]
     674: 3cea6920     	ldr	q0, [x9, x10]
     678: 1100810a     	add	w10, w8, #0x20
     67c: 927c6d4a     	and	x10, x10, #0xfffffff0
     680: 3d805680     	str	q0, [x20, #0x150]
     684: 3cea6920     	ldr	q0, [x9, x10]
     688: 1100c10a     	add	w10, w8, #0x30
     68c: 927c6d4a     	and	x10, x10, #0xfffffff0
     690: 3d805280     	str	q0, [x20, #0x140]
     694: 3cea6920     	ldr	q0, [x9, x10]
     698: 1101010a     	add	w10, w8, #0x40
     69c: 927c6d4a     	and	x10, x10, #0xfffffff0
     6a0: 3d804280     	str	q0, [x20, #0x100]
     6a4: 3cea6920     	ldr	q0, [x9, x10]
     6a8: 1101410a     	add	w10, w8, #0x50
     6ac: 91018108     	add	x8, x8, #0x60
     6b0: 927c6d4a     	and	x10, x10, #0xfffffff0
     6b4: 3d804e80     	str	q0, [x20, #0x130]
     6b8: 3cea6920     	ldr	q0, [x9, x10]
     6bc: f900ea88     	str	x8, [x20, #0x1d0]
     6c0: 3d804a80     	str	q0, [x20, #0x120]
     6c4: f940a289     	ldr	x9, [x20, #0x140]
     6c8: f2400d3f     	tst	x9, #0xf
     6cc: 54003721     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     6d0: f9400348     	ldr	x8, [x26]
     6d4: 927c6d29     	and	x9, x9, #0xfffffff0
     6d8: 8b09010a     	add	x10, x8, x9
     6dc: f940aa89     	ldr	x9, [x20, #0x150]
     6e0: 3dc00140     	ldr	q0, [x10]
     6e4: f2400d3f     	tst	x9, #0xf
     6e8: 3d80c280     	str	q0, [x20, #0x300]
     6ec: 3dc00540     	ldr	q0, [x10, #0x10]
     6f0: 3d80c680     	str	q0, [x20, #0x310]
     6f4: 3dc00940     	ldr	q0, [x10, #0x20]
     6f8: 3d80ca80     	str	q0, [x20, #0x320]
     6fc: 540035a1     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     700: 927c6d29     	and	x9, x9, #0xfffffff0
     704: 8b090108     	add	x8, x8, x9
     708: 3dc00500     	ldr	q0, [x8, #0x10]
     70c: 3d80ce80     	str	q0, [x20, #0x330]
     710: 3dc00900     	ldr	q0, [x8, #0x20]
     714: bd433284     	ldr	s4, [x20, #0x330]
     718: 3d80d280     	str	q0, [x20, #0x340]
     71c: 3dc00d00     	ldr	q0, [x8, #0x30]
     720: 3d80d680     	str	q0, [x20, #0x350]
     724: 3dc01100     	ldr	q0, [x8, #0x40]
     728: 3d80da80     	str	q0, [x20, #0x360]
     72c: bd438a80     	ldr	s0, [x20, #0x388]
     730: bd436281     	ldr	s1, [x20, #0x360]
     734: fd4032a2     	ldr	d2, [x21, #0x60]
     738: bd436e83     	ldr	s3, [x20, #0x36c]
     73c: b9806109     	ldrsw	x9, [x8, #0x60]
     740: 1e200821     	fmul	s1, s1, s0
     744: 0f809042     	fmul	v2.2s, v2.2s, v0.s[0]
     748: 1e200863     	fmul	s3, s3, s0
     74c: fd401aa0     	ldr	d0, [x21, #0x30]
     750: b9020289     	str	w9, [x20, #0x200]
     754: f9001a89     	str	x9, [x20, #0x30]
     758: bd036281     	str	s1, [x20, #0x360]
     75c: 1e242821     	fadd	s1, s1, s4
     760: 0e20d440     	fadd	v0.2s, v2.2s, v0.2s
     764: fd0032a2     	str	d2, [x21, #0x60]
     768: bd438e82     	ldr	s2, [x20, #0x38c]
     76c: bd036e83     	str	s3, [x20, #0x36c]
     770: bd033281     	str	s1, [x20, #0x330]
     774: fd001aa0     	str	d0, [x21, #0x30]
     778: 34000249     	cbz	w9, 0x7c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x7c0>
     77c: 1e270123     	fmov	s3, w9
     780: f9401e8a     	ldr	x10, [x20, #0x38]
     784: 9e670124     	fmov	d4, x9
     788: f901be8a     	str	x10, [x20, #0x378]
     78c: 1e233943     	fsub	s3, s10, s3
     790: bd437a85     	ldr	s5, [x20, #0x378]
     794: 0f829084     	fmul	v4.2s, v4.2s, v2.s[0]
     798: 1e230843     	fmul	s3, s2, s3
     79c: 1e250842     	fmul	s2, s2, s5
     7a0: fd01ba84     	str	d4, [x20, #0x370]
     7a4: 1e233943     	fsub	s3, s10, s3
     7a8: bd037a82     	str	s2, [x20, #0x378]
     7ac: 1e230821     	fmul	s1, s1, s3
     7b0: 0f839000     	fmul	v0.2s, v0.2s, v3.s[0]
     7b4: bd037e83     	str	s3, [x20, #0x37c]
     7b8: bd033281     	str	s1, [x20, #0x330]
     7bc: fd001aa0     	str	d0, [x21, #0x30]
     7c0: bd438682     	ldr	s2, [x20, #0x384]
     7c4: 910d7289     	add	x9, x20, #0x35c
     7c8: fd41aa84     	ldr	d4, [x20, #0x350]
     7cc: bd433e85     	ldr	s5, [x20, #0x33c]
     7d0: fd4022b0     	ldr	d16, [x21, #0x40]
     7d4: 1e26000a     	fmov	w10, s0
     7d8: 4ea21c43     	mov	v3.16b, v2.16b
     7dc: 4ea21c46     	mov	v6.16b, v2.16b
     7e0: bd434e92     	ldr	s18, [x20, #0x34c]
     7e4: 6e0c0445     	mov	v5.s[1], v2.s[0]
     7e8: 3dc0ca93     	ldr	q19, [x20, #0x320]
     7ec: 0f829011     	fmul	v17.2s, v0.2s, v2.s[0]
     7f0: f9419e8b     	ldr	x11, [x20, #0x338]
     7f4: 0d409123     	ld1	{ v3.s }[1], [x9]
     7f8: 910d6289     	add	x9, x20, #0x358
     7fc: 4d408124     	ld1	{ v4.s }[2], [x9]
     800: 910d0289     	add	x9, x20, #0x340
     804: 4e0c04a7     	dup	v7.4s, v5.s[1]
     808: 0d409126     	ld1	{ v6.s }[1], [x9]
     80c: 1e260029     	fmov	w9, s1
     810: 4e833863     	zip1	v3.4s, v3.4s, v3.4s
     814: fd004ab1     	str	d17, [x21, #0x90]
     818: 6e1c0444     	mov	v4.s[3], v2.s[0]
     81c: 4e8738a5     	zip1	v5.4s, v5.4s, v7.4s
     820: 6e180606     	mov	v6.d[1], v16.d[0]
     824: bd430287     	ldr	s7, [x20, #0x300]
     828: fd4002b0     	ldr	d16, [x21]
     82c: aa0a8129     	orr	x9, x9, x10, lsl #32
     830: 6e140443     	mov	v3.s[2], v2.s[0]
     834: 6e23dc83     	fmul	v3.4s, v4.4s, v3.4s
     838: 1e220824     	fmul	s4, s1, s2
     83c: 1e320842     	fmul	s2, s2, s18
     840: 4e33d472     	fadd	v18.4s, v3.4s, v19.4s
     844: 1e272887     	fadd	s7, s4, s7
     848: bd039284     	str	s4, [x20, #0x390]
     84c: 6e26dca4     	fmul	v4.4s, v5.4s, v6.4s
     850: 0e30d625     	fadd	v5.2s, v17.2s, v16.2s
     854: bd431e93     	ldr	s19, [x20, #0x31c]
     858: bd430e86     	ldr	s6, [x20, #0x30c]
     85c: bd03ae82     	str	s2, [x20, #0x3ac]
     860: 1e222a62     	fadd	s2, s19, s2
     864: 3d80ee83     	str	q3, [x20, #0x3b0]
     868: 4ea0ea50     	fcmlt	v16.4s, v18.4s, #0.0
     86c: bd030287     	str	s7, [x20, #0x300]
     870: fd0002a5     	str	d5, [x21]
     874: 1e262885     	fadd	s5, s4, s6
     878: 3c8982a4     	stur	q4, [x21, #0x98]
     87c: bd031e82     	str	s2, [x20, #0x31c]
     880: 4e701e41     	bic	v1.16b, v18.16b, v16.16b
     884: bd030e85     	str	s5, [x20, #0x30c]
     888: 3d80ca81     	str	q1, [x20, #0x320]
     88c: a9012d09     	stp	x9, x11, [x8, #0x10]
     890: f940a288     	ldr	x8, [x20, #0x140]
     894: f2400d1f     	tst	x8, #0xf
     898: 54002ae1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     89c: f9400349     	ldr	x9, [x26]
     8a0: f941828a     	ldr	x10, [x20, #0x300]
     8a4: 927c6d08     	and	x8, x8, #0xfffffff0
     8a8: f941868b     	ldr	x11, [x20, #0x308]
     8ac: 8b080128     	add	x8, x9, x8
     8b0: a9002d0a     	stp	x10, x11, [x8]
     8b4: f940a288     	ldr	x8, [x20, #0x140]
     8b8: f2400d1f     	tst	x8, #0xf
     8bc: 540029c1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     8c0: f9400349     	ldr	x9, [x26]
     8c4: f9418a8a     	ldr	x10, [x20, #0x310]
     8c8: 927c6d08     	and	x8, x8, #0xfffffff0
     8cc: f9418e8b     	ldr	x11, [x20, #0x318]
     8d0: 8b080128     	add	x8, x9, x8
     8d4: a9012d0a     	stp	x10, x11, [x8, #0x10]
     8d8: f940a288     	ldr	x8, [x20, #0x140]
     8dc: f2400d1f     	tst	x8, #0xf
     8e0: 540028a1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     8e4: f9400349     	ldr	x9, [x26]
     8e8: f941928a     	ldr	x10, [x20, #0x320]
     8ec: 927c6d08     	and	x8, x8, #0xfffffff0
     8f0: f941968b     	ldr	x11, [x20, #0x328]
     8f4: 8b080128     	add	x8, x9, x8
     8f8: a9022d0a     	stp	x10, x11, [x8, #0x20]
     8fc: f940a289     	ldr	x9, [x20, #0x140]
     900: f940034a     	ldr	x10, [x26]
     904: f9408a88     	ldr	x8, [x20, #0x110]
     908: 8b29414b     	add	x11, x10, w9, uxtw
     90c: f9001a88     	str	x8, [x20, #0x30]
     910: f9002289     	str	x9, [x20, #0x40]
     914: b9401169     	ldr	w9, [x11, #0x10]
     918: b9020289     	str	w9, [x20, #0x200]
     91c: b940156c     	ldr	w12, [x11, #0x14]
     920: b902068c     	str	w12, [x20, #0x204]
     924: b940196b     	ldr	w11, [x11, #0x18]
     928: b9020e8b     	str	w11, [x20, #0x20c]
     92c: b8284949     	str	w9, [x10, w8, uxtw]
     930: f9400348     	ldr	x8, [x26]
     934: b9403289     	ldr	w9, [x20, #0x30]
     938: b942068a     	ldr	w10, [x20, #0x204]
     93c: 8b090108     	add	x8, x8, x9
     940: b900050a     	str	w10, [x8, #0x4]
     944: f9400348     	ldr	x8, [x26]
     948: b9403289     	ldr	w9, [x20, #0x30]
     94c: b9420e8a     	ldr	w10, [x20, #0x20c]
     950: 8b090108     	add	x8, x8, x9
     954: b900090a     	str	w10, [x8, #0x8]
     958: bd420e80     	ldr	s0, [x20, #0x20c]
     95c: bd420681     	ldr	s1, [x20, #0x204]
     960: bd420283     	ldr	s3, [x20, #0x200]
     964: f9400348     	ldr	x8, [x26]
     968: b9403289     	ldr	w9, [x20, #0x30]
     96c: 1e200800     	fmul	s0, s0, s0
     970: 1e210821     	fmul	s1, s1, s1
     974: 1e230863     	fmul	s3, s3, s3
     978: 8b090108     	add	x8, x8, x9
     97c: 1e203942     	fsub	s2, s10, s0
     980: bd020e80     	str	s0, [x20, #0x20c]
     984: 1e213841     	fsub	s1, s2, s1
     988: bd020a82     	str	s2, [x20, #0x208]
     98c: 7ea3d423     	fabd	s3, s1, s3
     990: bd020681     	str	s1, [x20, #0x204]
     994: 1e21c063     	fsqrt	s3, s3
     998: bd020283     	str	s3, [x20, #0x200]
     99c: bd000d03     	str	s3, [x8, #0xc]
     9a0: b9820288     	ldrsw	x8, [x20, #0x200]
     9a4: f9400389     	ldr	x9, [x28]
     9a8: f9400345     	ldr	x5, [x26]
     9ac: f9002288     	str	x8, [x20, #0x40]
     9b0: b9400128     	ldr	w8, [x9]
     9b4: 93407d09     	sxtw	x9, w8
     9b8: f9001a89     	str	x9, [x20, #0x30]
     9bc: b86868a8     	ldr	w8, [x5, x8]
     9c0: 92401d09     	and	x9, x8, #0xff
     9c4: b9020288     	str	w8, [x20, #0x200]
     9c8: d1002928     	sub	x8, x9, #0xa
     9cc: 7100293f     	cmp	w9, #0xa
     9d0: f9001a88     	str	x8, [x20, #0x30]
     9d4: 540003c3     	b.lo	0xa4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa4c>
     9d8: f9400788     	ldr	x8, [x28, #0x8]
     9dc: f9408a89     	ldr	x9, [x20, #0x110]
     9e0: f940aa8a     	ldr	x10, [x20, #0x150]
     9e4: b981f28b     	ldrsw	x11, [x20, #0x1f0]
     9e8: b9800108     	ldrsw	x8, [x8]
     9ec: f9002289     	str	x9, [x20, #0x40]
     9f0: 9101414a     	add	x10, x10, #0x50
     9f4: f9002a89     	str	x9, [x20, #0x50]
     9f8: a901a7e9     	stp	x9, x9, [sp, #0x18]
     9fc: f9403a89     	ldr	x9, [x20, #0x70]
     a00: f900128b     	str	x11, [x20, #0x20]
     a04: f940428b     	ldr	x11, [x20, #0x80]
     a08: a902a7ea     	stp	x10, x9, [sp, #0x28]
     a0c: f9404a89     	ldr	x9, [x20, #0x90]
     a10: f900328a     	str	x10, [x20, #0x60]
     a14: f940528a     	ldr	x10, [x20, #0xa0]
     a18: a903a7eb     	stp	x11, x9, [sp, #0x38]
     a1c: f9405a89     	ldr	x9, [x20, #0xb0]
     a20: f900ca88     	str	x8, [x20, #0x190]
     a24: a904a7ea     	stp	x10, x9, [sp, #0x48]
     a28: 34001da8     	cbz	w8, 0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     a2c: f940b283     	ldr	x3, [x20, #0x160]
     a30: f940ba84     	ldr	x4, [x20, #0x170]
     a34: 92407d08     	and	x8, x8, #0xffffffff
     a38: 8b0800a0     	add	x0, x5, x8
     a3c: 910063e1     	add	x1, sp, #0x18
     a40: aa1f03e2     	mov	x2, xzr
     a44: 94000000     	bl	0xa44 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa44>
		0000000000000a44:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     a48: f9001280     	str	x0, [x20, #0x20]
     a4c: f9400788     	ldr	x8, [x28, #0x8]
     a50: f9408a89     	ldr	x9, [x20, #0x110]
     a54: f940aa8a     	ldr	x10, [x20, #0x150]
     a58: b981f28b     	ldrsw	x11, [x20, #0x1f0]
     a5c: b9800108     	ldrsw	x8, [x8]
     a60: f9002289     	str	x9, [x20, #0x40]
     a64: 9101414a     	add	x10, x10, #0x50
     a68: f9002a89     	str	x9, [x20, #0x50]
     a6c: a901a7e9     	stp	x9, x9, [sp, #0x18]
     a70: f9403a89     	ldr	x9, [x20, #0x70]
     a74: f900128b     	str	x11, [x20, #0x20]
     a78: f940428b     	ldr	x11, [x20, #0x80]
     a7c: a902a7ea     	stp	x10, x9, [sp, #0x28]
     a80: f9404a89     	ldr	x9, [x20, #0x90]
     a84: f900328a     	str	x10, [x20, #0x60]
     a88: f940528a     	ldr	x10, [x20, #0xa0]
     a8c: a903a7eb     	stp	x11, x9, [sp, #0x38]
     a90: f9405a89     	ldr	x9, [x20, #0xb0]
     a94: f900ca88     	str	x8, [x20, #0x190]
     a98: a904a7ea     	stp	x10, x9, [sp, #0x48]
     a9c: 34001a08     	cbz	w8, 0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     aa0: f9400345     	ldr	x5, [x26]
     aa4: f940b283     	ldr	x3, [x20, #0x160]
     aa8: 92407d08     	and	x8, x8, #0xffffffff
     aac: f940ba84     	ldr	x4, [x20, #0x170]
     ab0: 8b0800a0     	add	x0, x5, x8
     ab4: 910063e1     	add	x1, sp, #0x18
     ab8: aa1f03e2     	mov	x2, xzr
     abc: 94000000     	bl	0xabc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xabc>
		0000000000000abc:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     ac0: f9408a89     	ldr	x9, [x20, #0x110]
     ac4: f940034b     	ldr	x11, [x26]
     ac8: f940a28a     	ldr	x10, [x20, #0x140]
     acc: f9001280     	str	x0, [x20, #0x20]
     ad0: 8b294168     	add	x8, x11, w9, uxtw
     ad4: f900228a     	str	x10, [x20, #0x40]
     ad8: f9001a89     	str	x9, [x20, #0x30]
     adc: b9400d0c     	ldr	w12, [x8, #0xc]
     ae0: b902069f     	str	wzr, [x20, #0x204]
     ae4: 1e270180     	fmov	s0, w12
     ae8: b902028c     	str	w12, [x20, #0x200]
     aec: 92400d4c     	and	x12, x10, #0xf
     af0: 1e202008     	fcmp	s0, #0.0
     af4: 540001e4     	b.mi	0xb30 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb30>
     af8: b50015cc     	cbnz	x12, 0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     afc: 927c6d4a     	and	x10, x10, #0xfffffff0
     b00: f2400d3f     	tst	x9, #0xf
     b04: 8b0a016a     	add	x10, x11, x10
     b08: 3dc00540     	ldr	q0, [x10, #0x10]
     b0c: 3d80a680     	str	q0, [x20, #0x290]
     b10: 54001501     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     b14: 3dc00100     	ldr	q0, [x8]
     b18: 3d80aa80     	str	q0, [x20, #0x2a0]
     b1c: fd415280     	ldr	d0, [x20, #0x2a0]
     b20: bd42aa82     	ldr	s2, [x20, #0x2a8]
     b24: 0e28d401     	fadd	v1.2s, v0.2s, v8.2s
     b28: 1e292840     	fadd	s0, s2, s9
     b2c: 1400000e     	b	0xb64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb64>
     b30: b500140c     	cbnz	x12, 0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     b34: 927c6d4a     	and	x10, x10, #0xfffffff0
     b38: f2400d3f     	tst	x9, #0xf
     b3c: 8b0a016a     	add	x10, x11, x10
     b40: 3dc00540     	ldr	q0, [x10, #0x10]
     b44: 3d80a680     	str	q0, [x20, #0x290]
     b48: 54001341     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     b4c: 3dc00100     	ldr	q0, [x8]
     b50: 3d80aa80     	str	q0, [x20, #0x2a0]
     b54: fd415280     	ldr	d0, [x20, #0x2a0]
     b58: bd42aa82     	ldr	s2, [x20, #0x2a8]
     b5c: 0ea0d501     	fsub	v1.2s, v8.2s, v0.2s
     b60: 1e223920     	fsub	s0, s9, s2
     b64: 0e0c3c29     	mov	w9, v1.s[1]
     b68: 91004148     	add	x8, x10, #0x10
     b6c: 1e26000a     	fmov	w10, s0
     b70: 1e26002b     	fmov	w11, s1
     b74: b9429e8c     	ldr	w12, [x20, #0x29c]
     b78: fd014a81     	str	d1, [x20, #0x290]
     b7c: bd029a80     	str	s0, [x20, #0x298]
     b80: aa0c814a     	orr	x10, x10, x12, lsl #32
     b84: aa098169     	orr	x9, x11, x9, lsl #32
     b88: a9002909     	stp	x9, x10, [x8]
     b8c: f9414e88     	ldr	x8, [x20, #0x298]
     b90: f9414a89     	ldr	x9, [x20, #0x290]
     b94: f9400345     	ldr	x5, [x26]
     b98: f940aa93     	ldr	x19, [x20, #0x150]
     b9c: 3dc0ca80     	ldr	q0, [x20, #0x320]
     ba0: a9042289     	stp	x9, x8, [x20, #0x40]
     ba4: 8b3340a8     	add	x8, x5, w19, uxtw
     ba8: 3d800e80     	str	q0, [x20, #0x30]
     bac: b9806908     	ldrsw	x8, [x8, #0x68]
     bb0: 927e0109     	and	x9, x8, #0x4
     bb4: f9002288     	str	x8, [x20, #0x40]
     bb8: f9002a89     	str	x9, [x20, #0x50]
     bbc: 36080108     	tbz	w8, #0x1, 0xbdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
     bc0: a9432a8b     	ldp	x11, x10, [x20, #0x30]
     bc4: 290c2a9f     	stp	wzr, w10, [x20, #0x60]
     bc8: d360fd4a     	lsr	x10, x10, #32
     bcc: 290d2a9f     	stp	wzr, w10, [x20, #0x68]
     bd0: b500006b     	cbnz	x11, 0xbdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
     bd4: f940328a     	ldr	x10, [x20, #0x60]
     bd8: b40003aa     	cbz	x10, 0xc4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
     bdc: 92400108     	and	x8, x8, #0x1
     be0: f9000368     	str	x8, [x27]
     be4: b4000109     	cbz	x9, 0xc04 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc04>
     be8: f9401e89     	ldr	x9, [x20, #0x38]
     bec: d360fd2a     	lsr	x10, x9, #32
     bf0: 29077e89     	stp	w9, wzr, [x20, #0x38]
     bf4: 29062a9f     	stp	wzr, w10, [x20, #0x30]
     bf8: f9401a8a     	ldr	x10, [x20, #0x30]
     bfc: f100055f     	cmp	x10, #0x1
     c00: 5400026b     	b.lt	0xc4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
     c04: b4ffb028     	cbz	x8, 0x208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
     c08: f9418288     	ldr	x8, [x20, #0x300]
     c0c: f9418689     	ldr	x9, [x20, #0x308]
     c10: f9418a8a     	ldr	x10, [x20, #0x310]
     c14: a9032688     	stp	x8, x9, [x20, #0x30]
     c18: d360fd28     	lsr	x8, x9, #32
     c1c: 29077e89     	stp	w9, wzr, [x20, #0x38]
     c20: 2906229f     	stp	wzr, w8, [x20, #0x30]
     c24: f9418e88     	ldr	x8, [x20, #0x318]
     c28: f9401a89     	ldr	x9, [x20, #0x30]
     c2c: a903228a     	stp	x10, x8, [x20, #0x30]
     c30: b7f800e9     	tbnz	x9, #0x3f, 0xc4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
     c34: f9401e88     	ldr	x8, [x20, #0x38]
     c38: d360fd09     	lsr	x9, x8, #32
     c3c: 29077e88     	stp	w8, wzr, [x20, #0x38]
     c40: 2906269f     	stp	wzr, w9, [x20, #0x30]
     c44: f9401a89     	ldr	x9, [x20, #0x30]
     c48: b6ffae09     	tbz	x9, #0x3f, 0x208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
     c4c: f9400b88     	ldr	x8, [x28, #0x10]
     c50: f940e289     	ldr	x9, [x20, #0x1c0]
     c54: f940828a     	ldr	x10, [x20, #0x100]
     c58: f940a28b     	ldr	x11, [x20, #0x140]
     c5c: b981f28c     	ldrsw	x12, [x20, #0x1f0]
     c60: b9800108     	ldrsw	x8, [x8]
     c64: f9002289     	str	x9, [x20, #0x40]
     c68: f9002a8a     	str	x10, [x20, #0x50]
     c6c: a901abe9     	stp	x9, x10, [sp, #0x18]
     c70: f9404289     	ldr	x9, [x20, #0x80]
     c74: f9404a8a     	ldr	x10, [x20, #0x90]
     c78: f9003a8b     	str	x11, [x20, #0x70]
     c7c: a902aff3     	stp	x19, x11, [sp, #0x28]
     c80: f940528b     	ldr	x11, [x20, #0xa0]
     c84: a903abe9     	stp	x9, x10, [sp, #0x38]
     c88: f9405a89     	ldr	x9, [x20, #0xb0]
     c8c: f9003293     	str	x19, [x20, #0x60]
     c90: f900ca88     	str	x8, [x20, #0x190]
     c94: f900128c     	str	x12, [x20, #0x20]
     c98: a904a7eb     	stp	x11, x9, [sp, #0x48]
     c9c: 34000a08     	cbz	w8, 0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     ca0: f940b283     	ldr	x3, [x20, #0x160]
     ca4: f940ba84     	ldr	x4, [x20, #0x170]
     ca8: 92407d08     	and	x8, x8, #0xffffffff
     cac: 8b0800a0     	add	x0, x5, x8
     cb0: 910063e1     	add	x1, sp, #0x18
     cb4: aa1f03e2     	mov	x2, xzr
     cb8: 94000000     	bl	0xcb8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcb8>
		0000000000000cb8:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     cbc: f9001280     	str	x0, [x20, #0x20]
     cc0: 17fffd52     	b	0x208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
     cc4: f9400348     	ldr	x8, [x26]
     cc8: f940ea89     	ldr	x9, [x20, #0x1d0]
     ccc: f9001297     	str	x23, [x20, #0x20]
     cd0: 8b29410a     	add	x10, x8, w9, uxtw
     cd4: f940014b     	ldr	x11, [x10]
     cd8: f900fa8b     	str	x11, [x20, #0x1f0]
     cdc: 1102412b     	add	w11, w9, #0x90
     ce0: f940054a     	ldr	x10, [x10, #0x8]
     ce4: 927c6d6b     	and	x11, x11, #0xfffffff0
     ce8: f900f28a     	str	x10, [x20, #0x1e0]
     cec: 1102012a     	add	w10, w9, #0x80
     cf0: 3ceb6900     	ldr	q0, [x8, x11]
     cf4: 927c6d4a     	and	x10, x10, #0xfffffff0
     cf8: 3d807280     	str	q0, [x20, #0x1c0]
     cfc: 3cea6900     	ldr	q0, [x8, x10]
     d00: 1101c12a     	add	w10, w9, #0x70
     d04: 927c6d4a     	and	x10, x10, #0xfffffff0
     d08: 3d805680     	str	q0, [x20, #0x150]
     d0c: 3cea6900     	ldr	q0, [x8, x10]
     d10: 1101812a     	add	w10, w9, #0x60
     d14: 927c6d4a     	and	x10, x10, #0xfffffff0
     d18: 3d805280     	str	q0, [x20, #0x140]
     d1c: 3cea6900     	ldr	q0, [x8, x10]
     d20: 1101412a     	add	w10, w9, #0x50
     d24: 927c6d4a     	and	x10, x10, #0xfffffff0
     d28: 3d804e80     	str	q0, [x20, #0x130]
     d2c: 3cea6900     	ldr	q0, [x8, x10]
     d30: 1101012a     	add	w10, w9, #0x40
     d34: 927c6d4a     	and	x10, x10, #0xfffffff0
     d38: 3d804a80     	str	q0, [x20, #0x120]
     d3c: 3cea6900     	ldr	q0, [x8, x10]
     d40: 1100c12a     	add	w10, w9, #0x30
     d44: 927c6d4a     	and	x10, x10, #0xfffffff0
     d48: 3d804680     	str	q0, [x20, #0x110]
     d4c: 3cea6900     	ldr	q0, [x8, x10]
     d50: 91028128     	add	x8, x9, #0xa0
     d54: f900ea88     	str	x8, [x20, #0x1d0]
     d58: 3d804280     	str	q0, [x20, #0x100]
     d5c: 94000000     	bl	0xd5c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd5c>
		0000000000000d5c:  R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
     d60: f9400be8     	ldr	x8, [sp, #0x10]
     d64: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000d64:  R_AARCH64_ADR_GOT_PAGE	g_spart_prof
     d68: f9400021     	ldr	x1, [x1]
		0000000000000d68:  R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
     d6c: cb080000     	sub	x0, x0, x8
     d70: 94000000     	bl	0xd70 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd70>
		0000000000000d70:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
     d74: f9401708     	ldr	x8, [x24, #0x28]
     d78: f85d83a9     	ldur	x9, [x29, #-0x28]
     d7c: eb09011f     	cmp	x8, x9
     d80: 540008c1     	b.ne	0xe98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
     d84: aa1703e0     	mov	x0, x23
     d88: a94d4ff4     	ldp	x20, x19, [sp, #0xd0]
     d8c: fd4033ea     	ldr	d10, [sp, #0x60]
     d90: a94c57f6     	ldp	x22, x21, [sp, #0xc0]
     d94: a94b5ff8     	ldp	x24, x23, [sp, #0xb0]
     d98: a94a67fa     	ldp	x26, x25, [sp, #0xa0]
     d9c: a9496ffc     	ldp	x28, x27, [sp, #0x90]
     da0: a9487bfd     	ldp	x29, x30, [sp, #0x80]
     da4: 6d4723e9     	ldp	d9, d8, [sp, #0x70]
     da8: 910383ff     	add	sp, sp, #0xe0
     dac: d65f03c0     	ret
     db0: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000db0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x275
     db4: 91000109     	add	x9, x8, #0x0
		0000000000000db4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x275
     db8: 52802b02     	mov	w2, #0x158              // =344
     dbc: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000dbc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2dd
     dc0: 91000108     	add	x8, x8, #0x0
		0000000000000dc0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2dd
     dc4: a90027e8     	stp	x8, x9, [sp]
     dc8: f9401708     	ldr	x8, [x24, #0x28]
     dcc: f85d83a9     	ldur	x9, [x29, #-0x28]
     dd0: eb09011f     	cmp	x8, x9
     dd4: 54000240     	b.eq	0xe1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe1c>
     dd8: 14000030     	b	0xe98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
     ddc: 52803202     	mov	w2, #0x190              // =400
     de0: f9401708     	ldr	x8, [x24, #0x28]
     de4: f85d83a9     	ldur	x9, [x29, #-0x28]
     de8: eb09011f     	cmp	x8, x9
     dec: 54000180     	b.eq	0xe1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe1c>
     df0: 1400002a     	b	0xe98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
     df4: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000df4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x33f
     df8: 91000109     	add	x9, x8, #0x0
		0000000000000df8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x33f
     dfc: 52803802     	mov	w2, #0x1c0              // =448
     e00: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e00:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x366
     e04: 91000108     	add	x8, x8, #0x0
		0000000000000e04:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x366
     e08: a90027e8     	stp	x8, x9, [sp]
     e0c: f9401708     	ldr	x8, [x24, #0x28]
     e10: f85d83a9     	ldur	x9, [x29, #-0x28]
     e14: eb09011f     	cmp	x8, x9
     e18: 54000401     	b.ne	0xe98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
     e1c: a94003e3     	ldp	x3, x0, [sp]
     e20: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e20:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a2
     e24: 91000021     	add	x1, x1, #0x0
		0000000000000e24:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a2
     e28: 90000004     	adrp	x4, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e28:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x310
     e2c: 91000084     	add	x4, x4, #0x0
		0000000000000e2c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x310
     e30: 94000000     	bl	0xe30 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe30>
		0000000000000e30:  R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
     e34: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e34:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2dd
     e38: 91000109     	add	x9, x8, #0x0
		0000000000000e38:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2dd
     e3c: 52802b02     	mov	w2, #0x158              // =344
     e40: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e40:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x275
     e44: 91000108     	add	x8, x8, #0x0
		0000000000000e44:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x275
     e48: a90023e9     	stp	x9, x8, [sp]
     e4c: f9401708     	ldr	x8, [x24, #0x28]
     e50: f85d83a9     	ldur	x9, [x29, #-0x28]
     e54: eb09011f     	cmp	x8, x9
     e58: 54fffe20     	b.eq	0xe1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe1c>
     e5c: 1400000f     	b	0xe98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
     e60: 14000001     	b	0xe64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe64>
     e64: aa0003f4     	mov	x20, x0
     e68: 94000000     	bl	0xe68 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe68>
		0000000000000e68:  R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
     e6c: f9400be8     	ldr	x8, [sp, #0x10]
     e70: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e70:  R_AARCH64_ADR_GOT_PAGE	g_spart_prof
     e74: f9400021     	ldr	x1, [x1]
		0000000000000e74:  R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
     e78: cb080000     	sub	x0, x0, x8
     e7c: 94000000     	bl	0xe7c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe7c>
		0000000000000e7c:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
     e80: f9401708     	ldr	x8, [x24, #0x28]
     e84: f85d83a9     	ldur	x9, [x29, #-0x28]
     e88: eb09011f     	cmp	x8, x9
     e8c: 54000061     	b.ne	0xe98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
     e90: aa1403e0     	mov	x0, x20
     e94: 94000000     	bl	0xe94 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe94>
		0000000000000e94:  R_AARCH64_CALL26	_Unwind_Resume
     e98: 94000000     	bl	0xe98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
		0000000000000e98:  R_AARCH64_CALL26	__stack_chk_fail
