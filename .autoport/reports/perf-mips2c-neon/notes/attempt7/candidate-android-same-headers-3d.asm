
.autoport/reports/perf-mips2c-neon/notes/attempt7/candidate-android-same-headers.o:	file format elf64-littleaarch64

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
       0: d10403ff     	sub	sp, sp, #0x100
       4: 6d082beb     	stp	d11, d10, [sp, #0x80]
       8: 6d0923e9     	stp	d9, d8, [sp, #0x90]
       c: a90a7bfd     	stp	x29, x30, [sp, #0xa0]
      10: a90b6ffc     	stp	x28, x27, [sp, #0xb0]
      14: a90c67fa     	stp	x26, x25, [sp, #0xc0]
      18: a90d5ff8     	stp	x24, x23, [sp, #0xd0]
      1c: a90e57f6     	stp	x22, x21, [sp, #0xe0]
      20: a90f4ff4     	stp	x20, x19, [sp, #0xf0]
      24: 910283fd     	add	x29, sp, #0xa0
      28: d53bd048     	mrs	x8, TPIDR_EL0
      2c: aa0003f4     	mov	x20, x0
      30: f9000fe8     	str	x8, [sp, #0x18]
      34: f9401508     	ldr	x8, [x8, #0x28]
      38: f81d83a8     	stur	x8, [x29, #-0x28]
      3c: 94000000     	bl	0x3c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x3c>
		000000000000003c:  R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
      40: f9000be0     	str	x0, [sp, #0x10]
      44: 90000019     	adrp	x25, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000044:  R_AARCH64_ADR_GOT_PAGE	g_spart_prof
      48: 52800020     	mov	w0, #0x1                // =1
      4c: f9400339     	ldr	x25, [x25]
		000000000000004c:  R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
      50: 91008321     	add	x1, x25, #0x20
      54: 94000000     	bl	0x54 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x54>
		0000000000000054:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
      58: 9000001a     	adrp	x26, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000058:  R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
      5c: f940ea88     	ldr	x8, [x20, #0x1d0]
      60: aa1403fb     	mov	x27, x20
      64: f940035a     	ldr	x26, [x26]
		0000000000000064:  R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
      68: f940fa8a     	ldr	x10, [x20, #0x1f0]
      6c: 9000001c     	adrp	x28, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		000000000000006c:  R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::cache
      70: d1028108     	sub	x8, x8, #0xa0
      74: f9400349     	ldr	x9, [x26]
      78: f900ea88     	str	x8, [x20, #0x1d0]
      7c: f828492a     	str	x10, [x9, w8, uxtw]
      80: f9400348     	ldr	x8, [x26]
      84: b941d289     	ldr	w9, [x20, #0x1d0]
      88: f940f28a     	ldr	x10, [x20, #0x1e0]
      8c: 8b090108     	add	x8, x8, x9
      90: f900050a     	str	x10, [x8, #0x8]
      94: b941d288     	ldr	w8, [x20, #0x1d0]
      98: f940ca89     	ldr	x9, [x20, #0x190]
      9c: f940034a     	ldr	x10, [x26]
      a0: 3dc04280     	ldr	q0, [x20, #0x100]
      a4: 1100c108     	add	w8, w8, #0x30
      a8: f900f289     	str	x9, [x20, #0x1e0]
      ac: 927c6d08     	and	x8, x8, #0xfffffff0
      b0: 3ca86940     	str	q0, [x10, x8]
      b4: b941d288     	ldr	w8, [x20, #0x1d0]
      b8: f9400349     	ldr	x9, [x26]
      bc: 3dc04680     	ldr	q0, [x20, #0x110]
      c0: 11010108     	add	w8, w8, #0x40
      c4: 927c6d08     	and	x8, x8, #0xfffffff0
      c8: 3ca86920     	str	q0, [x9, x8]
      cc: b941d288     	ldr	w8, [x20, #0x1d0]
      d0: f9400349     	ldr	x9, [x26]
      d4: 3dc04a80     	ldr	q0, [x20, #0x120]
      d8: 11014108     	add	w8, w8, #0x50
      dc: 927c6d08     	and	x8, x8, #0xfffffff0
      e0: 3ca86920     	str	q0, [x9, x8]
      e4: b941d288     	ldr	w8, [x20, #0x1d0]
      e8: f9400349     	ldr	x9, [x26]
      ec: 3dc04e80     	ldr	q0, [x20, #0x130]
      f0: 11018108     	add	w8, w8, #0x60
      f4: 927c6d08     	and	x8, x8, #0xfffffff0
      f8: 3ca86920     	str	q0, [x9, x8]
      fc: b941d288     	ldr	w8, [x20, #0x1d0]
     100: f9400349     	ldr	x9, [x26]
     104: 3dc05280     	ldr	q0, [x20, #0x140]
     108: 1101c108     	add	w8, w8, #0x70
     10c: 927c6d08     	and	x8, x8, #0xfffffff0
     110: 3ca86920     	str	q0, [x9, x8]
     114: b941d288     	ldr	w8, [x20, #0x1d0]
     118: f9400349     	ldr	x9, [x26]
     11c: 3dc05680     	ldr	q0, [x20, #0x150]
     120: 11020108     	add	w8, w8, #0x80
     124: 927c6d08     	and	x8, x8, #0xfffffff0
     128: 3ca86920     	str	q0, [x9, x8]
     12c: b941d288     	ldr	w8, [x20, #0x1d0]
     130: f9400349     	ldr	x9, [x26]
     134: 3dc07280     	ldr	q0, [x20, #0x1c0]
     138: 11024108     	add	w8, w8, #0x90
     13c: 927c6d08     	and	x8, x8, #0xfffffff0
     140: 3ca86920     	str	q0, [x9, x8]
     144: f8440f68     	ldr	x8, [x27, #0x40]!
     148: f9400b69     	ldr	x9, [x27, #0x10]
     14c: f940136a     	ldr	x10, [x27, #0x20]
     150: a9037fff     	stp	xzr, xzr, [sp, #0x30]
     154: f900e288     	str	x8, [x20, #0x1c0]
     158: f9401b68     	ldr	x8, [x27, #0x30]
     15c: 3dc00fe0     	ldr	q0, [sp, #0x30]
     160: f900aa89     	str	x9, [x20, #0x150]
     164: f9402369     	ldr	x9, [x27, #0x40]
     168: f9008288     	str	x8, [x20, #0x100]
     16c: f940ea88     	ldr	x8, [x20, #0x1d0]
     170: f900a28a     	str	x10, [x20, #0x140]
     174: f9402b6a     	ldr	x10, [x27, #0x50]
     178: 91004108     	add	x8, x8, #0x10
     17c: f9009a89     	str	x9, [x20, #0x130]
     180: f9400349     	ldr	x9, [x26]
     184: f900928a     	str	x10, [x20, #0x120]
     188: f9008a88     	str	x8, [x20, #0x110]
     18c: 927c6d08     	and	x8, x8, #0xfffffff0
     190: f940039c     	ldr	x28, [x28]
		0000000000000190:  R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
     194: 3ca86920     	str	q0, [x9, x8]
     198: f9400388     	ldr	x8, [x28]
     19c: b9800108     	ldrsw	x8, [x8]
     1a0: 72000d1f     	tst	w8, #0xf
     1a4: f81f0368     	stur	x8, [x27, #-0x10]
     1a8: 54006621     	b.ne	0xe6c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe6c>
     1ac: f9400349     	ldr	x9, [x26]
     1b0: 927c6d08     	and	x8, x8, #0xfffffff0
     1b4: 9000000a     	adrp	x10, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		00000000000001b4:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x40a
     1b8: 9100014a     	add	x10, x10, #0x0
		00000000000001b8:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x40a
     1bc: 2f00e408     	movi	d8, #0000000000000000
     1c0: 2f00e409     	movi	d9, #0000000000000000
     1c4: 3ce86920     	ldr	q0, [x9, x8]
     1c8: b941d288     	ldr	w8, [x20, #0x1d0]
     1cc: f90007ea     	str	x10, [sp, #0x8]
     1d0: 1e2e100a     	fmov	s10, #1.00000000
     1d4: 910bf375     	add	x21, x27, #0x2fc
     1d8: 910c4296     	add	x22, x20, #0x310
     1dc: 3d80e280     	str	q0, [x20, #0x380]
     1e0: 11008108     	add	w8, w8, #0x20
     1e4: 92800013     	mov	x19, #-0x1              // =-1
     1e8: f941c68a     	ldr	x10, [x20, #0x388]
     1ec: 394e028b     	ldrb	w11, [x20, #0x380]
     1f0: 927c6d08     	and	x8, x8, #0xfffffff0
     1f4: 8b080128     	add	x8, x9, x8
     1f8: 3d800be0     	str	q0, [sp, #0x20]
     1fc: a9032a8b     	stp	x11, x10, [x20, #0x30]
     200: a900290b     	stp	x11, x10, [x8]
     204: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000204:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x405
     208: 91000108     	add	x8, x8, #0x0
		0000000000000208:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x405
     20c: f940aa98     	ldr	x24, [x20, #0x150]
     210: f90003e8     	str	x8, [sp]
     214: 1400000e     	b	0x24c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x24c>
     218: f9409a88     	ldr	x8, [x20, #0x130]
     21c: f940aa89     	ldr	x9, [x20, #0x150]
     220: f940a28a     	ldr	x10, [x20, #0x140]
     224: f940828b     	ldr	x11, [x20, #0x100]
     228: f1000508     	subs	x8, x8, #0x1
     22c: 91024138     	add	x24, x9, #0x90
     230: f9009a88     	str	x8, [x20, #0x130]
     234: 9100c148     	add	x8, x10, #0x30
     238: 91000577     	add	x23, x11, #0x1
     23c: f900aa98     	str	x24, [x20, #0x150]
     240: f900a288     	str	x8, [x20, #0x140]
     244: f9008297     	str	x23, [x20, #0x100]
     248: 54005160     	b.eq	0xc74 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc74>
     24c: 91010321     	add	x1, x25, #0x40
     250: 52800020     	mov	w0, #0x1                // =1
     254: 94000000     	bl	0x254 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x254>
		0000000000000254:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
     258: f9400345     	ldr	x5, [x26]
     25c: 92407f09     	and	x9, x24, #0xffffffff
     260: b941728b     	ldr	w11, [x20, #0x170]
     264: 8b0900a8     	add	x8, x5, x9
     268: b980810a     	ldrsw	x10, [x8, #0x80]
     26c: 6b0b015f     	cmp	w10, w11
     270: f9001a8a     	str	x10, [x20, #0x30]
     274: 54fffd20     	b.eq	0x218 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x218>
     278: b941228c     	ldr	w12, [x20, #0x120]
     27c: b980690a     	ldrsw	x10, [x8, #0x68]
     280: 6b0b019f     	cmp	w12, w11
     284: f9001a8a     	str	x10, [x20, #0x30]
     288: 54000300     	b.eq	0x2e8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2e8>
     28c: 9273014b     	and	x11, x10, #0x2000
     290: f9001a8b     	str	x11, [x20, #0x30]
     294: 376802aa     	tbnz	w10, #0xd, 0x2e8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2e8>
     298: b9806509     	ldrsw	x9, [x8, #0x64]
     29c: f9002293     	str	x19, [x20, #0x40]
     2a0: f9001a89     	str	x9, [x20, #0x30]
     2a4: 34004ac9     	cbz	w9, 0xbfc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbfc>
     2a8: b9806909     	ldrsw	x9, [x8, #0x68]
     2ac: 927a012a     	and	x10, x9, #0x40
     2b0: 9279f92b     	and	x11, x9, #0xffffffffffffffbf
     2b4: f9001a8a     	str	x10, [x20, #0x30]
     2b8: f900228b     	str	x11, [x20, #0x40]
     2bc: b900690b     	str	w11, [x8, #0x68]
     2c0: 3637fac9     	tbz	w9, #0x6, 0x218 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x218>
     2c4: f9400348     	ldr	x8, [x26]
     2c8: b9415289     	ldr	w9, [x20, #0x150]
     2cc: b941428a     	ldr	w10, [x20, #0x140]
     2d0: 8b090109     	add	x9, x8, x9
     2d4: 8b0a0108     	add	x8, x8, x10
     2d8: b9807d29     	ldrsw	x9, [x9, #0x7c]
     2dc: f9001a89     	str	x9, [x20, #0x30]
     2e0: b9002d09     	str	w9, [x8, #0x2c]
     2e4: 17ffffcd     	b	0x218 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x218>
     2e8: b941d28b     	ldr	w11, [x20, #0x1d0]
     2ec: b980650a     	ldrsw	x10, [x8, #0x64]
     2f0: f9002293     	str	x19, [x20, #0x40]
     2f4: 1100816b     	add	w11, w11, #0x20
     2f8: f9001a8a     	str	x10, [x20, #0x30]
     2fc: 3100055f     	cmn	w10, #0x1
     300: 927c6d6b     	and	x11, x11, #0xfffffff0
     304: 3ceb68a0     	ldr	q0, [x5, x11]
     308: 3d800360     	str	q0, [x27]
     30c: 54000260     	b.eq	0x358 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x358>
     310: f9402289     	ldr	x9, [x20, #0x40]
     314: 6f00e401     	movi	v1.2d, #0000000000000000
     318: cb090149     	sub	x9, x10, x9
     31c: 1e270120     	fmov	s0, w9
     320: d360fd2b     	lsr	x11, x9, #32
     324: f9002289     	str	x9, [x20, #0x40]
     328: 4e0c1d60     	mov	v0.s[1], w11
     32c: 9101228b     	add	x11, x20, #0x48
     330: 4d408160     	ld1	{ v0.s }[2], [x11]
     334: 9101328b     	add	x11, x20, #0x4c
     338: 4d409160     	ld1	{ v0.s }[3], [x11]
     33c: 4ea16400     	smax	v0.4s, v0.4s, v1.4s
     340: 3d800e80     	str	q0, [x20, #0x30]
     344: 340045ca     	cbz	w10, 0xbfc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbfc>
     348: f9401a89     	ldr	x9, [x20, #0x30]
     34c: b9006509     	str	w9, [x8, #0x64]
     350: f9400345     	ldr	x5, [x26]
     354: b9415289     	ldr	w9, [x20, #0x150]
     358: 8b0900a8     	add	x8, x5, x9
     35c: b9806909     	ldrsw	x9, [x8, #0x68]
     360: 927a012a     	and	x10, x9, #0x40
     364: 9279f92b     	and	x11, x9, #0xffffffffffffffbf
     368: f9001a8a     	str	x10, [x20, #0x30]
     36c: f900228b     	str	x11, [x20, #0x40]
     370: b900690b     	str	w11, [x8, #0x68]
     374: 36300129     	tbz	w9, #0x6, 0x398 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x398>
     378: f9400348     	ldr	x8, [x26]
     37c: b9415289     	ldr	w9, [x20, #0x150]
     380: b941428a     	ldr	w10, [x20, #0x140]
     384: 8b090109     	add	x9, x8, x9
     388: 8b0a0108     	add	x8, x8, x10
     38c: b9807d29     	ldrsw	x9, [x9, #0x7c]
     390: f9001a89     	str	x9, [x20, #0x30]
     394: b9002d09     	str	w9, [x8, #0x2c]
     398: f9400348     	ldr	x8, [x26]
     39c: b941528a     	ldr	w10, [x20, #0x150]
     3a0: 8b0a0109     	add	x9, x8, x10
     3a4: b980712b     	ldrsw	x11, [x9, #0x70]
     3a8: f940ea89     	ldr	x9, [x20, #0x1d0]
     3ac: f900ca8b     	str	x11, [x20, #0x190]
     3b0: 34000b8b     	cbz	w11, 0x520 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x520>
     3b4: d1018129     	sub	x9, x9, #0x60
     3b8: 3dc07280     	ldr	q0, [x20, #0x1c0]
     3bc: f900ea89     	str	x9, [x20, #0x1d0]
     3c0: 927c6d29     	and	x9, x9, #0xfffffff0
     3c4: 3ca96900     	str	q0, [x8, x9]
     3c8: b941d288     	ldr	w8, [x20, #0x1d0]
     3cc: f9400349     	ldr	x9, [x26]
     3d0: 3dc05680     	ldr	q0, [x20, #0x150]
     3d4: 11004108     	add	w8, w8, #0x10
     3d8: 927c6d08     	and	x8, x8, #0xfffffff0
     3dc: 3ca86920     	str	q0, [x9, x8]
     3e0: b941d288     	ldr	w8, [x20, #0x1d0]
     3e4: f9400349     	ldr	x9, [x26]
     3e8: 3dc05280     	ldr	q0, [x20, #0x140]
     3ec: 11008108     	add	w8, w8, #0x20
     3f0: 927c6d08     	and	x8, x8, #0xfffffff0
     3f4: 3ca86920     	str	q0, [x9, x8]
     3f8: b941d288     	ldr	w8, [x20, #0x1d0]
     3fc: f9400349     	ldr	x9, [x26]
     400: 3dc04280     	ldr	q0, [x20, #0x100]
     404: 1100c108     	add	w8, w8, #0x30
     408: 927c6d08     	and	x8, x8, #0xfffffff0
     40c: 3ca86920     	str	q0, [x9, x8]
     410: b941d288     	ldr	w8, [x20, #0x1d0]
     414: f9400349     	ldr	x9, [x26]
     418: 3dc04e80     	ldr	q0, [x20, #0x130]
     41c: 11010108     	add	w8, w8, #0x40
     420: 927c6d08     	and	x8, x8, #0xfffffff0
     424: 3ca86920     	str	q0, [x9, x8]
     428: f940e288     	ldr	x8, [x20, #0x1c0]
     42c: b941d28a     	ldr	w10, [x20, #0x1d0]
     430: f940aa89     	ldr	x9, [x20, #0x150]
     434: f940a28b     	ldr	x11, [x20, #0x140]
     438: f940034c     	ldr	x12, [x26]
     43c: 3dc04a80     	ldr	q0, [x20, #0x120]
     440: f9002288     	str	x8, [x20, #0x40]
     444: 11014148     	add	w8, w10, #0x50
     448: f9002a89     	str	x9, [x20, #0x50]
     44c: 927c6d09     	and	x9, x8, #0xfffffff0
     450: b9419288     	ldr	w8, [x20, #0x190]
     454: f900328b     	str	x11, [x20, #0x60]
     458: 3ca96980     	str	q0, [x12, x9]
     45c: f9402289     	ldr	x9, [x20, #0x40]
     460: f9402a8a     	ldr	x10, [x20, #0x50]
     464: f940328b     	ldr	x11, [x20, #0x60]
     468: a9032be9     	stp	x9, x10, [sp, #0x30]
     46c: f9403a89     	ldr	x9, [x20, #0x70]
     470: f940428a     	ldr	x10, [x20, #0x80]
     474: a90427eb     	stp	x11, x9, [sp, #0x40]
     478: f9404a8b     	ldr	x11, [x20, #0x90]
     47c: f9405289     	ldr	x9, [x20, #0xa0]
     480: a9052fea     	stp	x10, x11, [sp, #0x50]
     484: f9405a8a     	ldr	x10, [x20, #0xb0]
     488: a9062be9     	stp	x9, x10, [sp, #0x60]
     48c: 340046c8     	cbz	w8, 0xd64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd64>
     490: f9400345     	ldr	x5, [x26]
     494: f940b283     	ldr	x3, [x20, #0x160]
     498: f940ba84     	ldr	x4, [x20, #0x170]
     49c: 8b0800a0     	add	x0, x5, x8
     4a0: 9100c3e1     	add	x1, sp, #0x30
     4a4: aa1f03e2     	mov	x2, xzr
     4a8: 94000000     	bl	0x4a8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x4a8>
		00000000000004a8:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     4ac: f940ea89     	ldr	x9, [x20, #0x1d0]
     4b0: f9400348     	ldr	x8, [x26]
     4b4: f9001280     	str	x0, [x20, #0x20]
     4b8: 927c6d2a     	and	x10, x9, #0xfffffff0
     4bc: 3cea6900     	ldr	q0, [x8, x10]
     4c0: 1100412a     	add	w10, w9, #0x10
     4c4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4c8: 3d807280     	str	q0, [x20, #0x1c0]
     4cc: 3cea6900     	ldr	q0, [x8, x10]
     4d0: 1100812a     	add	w10, w9, #0x20
     4d4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4d8: 3d805680     	str	q0, [x20, #0x150]
     4dc: 3cea6900     	ldr	q0, [x8, x10]
     4e0: 1100c12a     	add	w10, w9, #0x30
     4e4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4e8: 3d805280     	str	q0, [x20, #0x140]
     4ec: 3cea6900     	ldr	q0, [x8, x10]
     4f0: 1101012a     	add	w10, w9, #0x40
     4f4: 927c6d4a     	and	x10, x10, #0xfffffff0
     4f8: 3d804280     	str	q0, [x20, #0x100]
     4fc: 3cea6900     	ldr	q0, [x8, x10]
     500: 1101412a     	add	w10, w9, #0x50
     504: 91018129     	add	x9, x9, #0x60
     508: 927c6d4a     	and	x10, x10, #0xfffffff0
     50c: 3d804e80     	str	q0, [x20, #0x130]
     510: 3cea6900     	ldr	q0, [x8, x10]
     514: b941528a     	ldr	w10, [x20, #0x150]
     518: f900ea89     	str	x9, [x20, #0x1d0]
     51c: 3d804a80     	str	q0, [x20, #0x120]
     520: 8b0a010a     	add	x10, x8, x10
     524: 11008129     	add	w9, w9, #0x20
     528: b980794c     	ldrsw	x12, [x10, #0x78]
     52c: 927c6d29     	and	x9, x9, #0xfffffff0
     530: f9002a8c     	str	x12, [x20, #0x50]
     534: b980754b     	ldrsw	x11, [x10, #0x74]
     538: f9001a8b     	str	x11, [x20, #0x30]
     53c: 3ce96900     	ldr	q0, [x8, x9]
     540: 3d800360     	str	q0, [x27]
     544: 34000c8c     	cbz	w12, 0x6d4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6d4>
     548: f9402288     	ldr	x8, [x20, #0x40]
     54c: eb080168     	subs	x8, x11, x8
     550: f9001a88     	str	x8, [x20, #0x30]
     554: b9007548     	str	w8, [x10, #0x74]
     558: 54000be5     	b.pl	0x6d4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6d4>
     55c: f940ea88     	ldr	x8, [x20, #0x1d0]
     560: f9400349     	ldr	x9, [x26]
     564: 3dc07280     	ldr	q0, [x20, #0x1c0]
     568: d1018108     	sub	x8, x8, #0x60
     56c: f900ea88     	str	x8, [x20, #0x1d0]
     570: 927c6d08     	and	x8, x8, #0xfffffff0
     574: 3ca86920     	str	q0, [x9, x8]
     578: b941d288     	ldr	w8, [x20, #0x1d0]
     57c: f9400349     	ldr	x9, [x26]
     580: 3dc05680     	ldr	q0, [x20, #0x150]
     584: 11004108     	add	w8, w8, #0x10
     588: 927c6d08     	and	x8, x8, #0xfffffff0
     58c: 3ca86920     	str	q0, [x9, x8]
     590: b941d288     	ldr	w8, [x20, #0x1d0]
     594: f9400349     	ldr	x9, [x26]
     598: 3dc05280     	ldr	q0, [x20, #0x140]
     59c: 11008108     	add	w8, w8, #0x20
     5a0: 927c6d08     	and	x8, x8, #0xfffffff0
     5a4: 3ca86920     	str	q0, [x9, x8]
     5a8: b941d288     	ldr	w8, [x20, #0x1d0]
     5ac: f9400349     	ldr	x9, [x26]
     5b0: 3dc04280     	ldr	q0, [x20, #0x100]
     5b4: 1100c108     	add	w8, w8, #0x30
     5b8: 927c6d08     	and	x8, x8, #0xfffffff0
     5bc: 3ca86920     	str	q0, [x9, x8]
     5c0: b941d288     	ldr	w8, [x20, #0x1d0]
     5c4: f9400349     	ldr	x9, [x26]
     5c8: 3dc04e80     	ldr	q0, [x20, #0x130]
     5cc: 11010108     	add	w8, w8, #0x40
     5d0: 927c6d08     	and	x8, x8, #0xfffffff0
     5d4: 3ca86920     	str	q0, [x9, x8]
     5d8: b941d288     	ldr	w8, [x20, #0x1d0]
     5dc: f9400349     	ldr	x9, [x26]
     5e0: 3dc04a80     	ldr	q0, [x20, #0x120]
     5e4: 11014108     	add	w8, w8, #0x50
     5e8: 927c6d08     	and	x8, x8, #0xfffffff0
     5ec: 3ca86920     	str	q0, [x9, x8]
     5f0: f940e289     	ldr	x9, [x20, #0x1c0]
     5f4: f940a28a     	ldr	x10, [x20, #0x140]
     5f8: f940aa8b     	ldr	x11, [x20, #0x150]
     5fc: f9400f88     	ldr	x8, [x28, #0x18]
     600: b981f28c     	ldrsw	x12, [x20, #0x1f0]
     604: f9002289     	str	x9, [x20, #0x40]
     608: f9003a8a     	str	x10, [x20, #0x70]
     60c: f900328b     	str	x11, [x20, #0x60]
     610: b9800108     	ldrsw	x8, [x8]
     614: f900128c     	str	x12, [x20, #0x20]
     618: f9402a8c     	ldr	x12, [x20, #0x50]
     61c: a9042beb     	stp	x11, x10, [sp, #0x40]
     620: f9404a8b     	ldr	x11, [x20, #0x90]
     624: f9405a8a     	ldr	x10, [x20, #0xb0]
     628: a90333e9     	stp	x9, x12, [sp, #0x30]
     62c: f9404289     	ldr	x9, [x20, #0x80]
     630: f900ca88     	str	x8, [x20, #0x190]
     634: a9052fe9     	stp	x9, x11, [sp, #0x50]
     638: f9405289     	ldr	x9, [x20, #0xa0]
     63c: a9062be9     	stp	x9, x10, [sp, #0x60]
     640: 34003928     	cbz	w8, 0xd64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd64>
     644: f9400345     	ldr	x5, [x26]
     648: f940b283     	ldr	x3, [x20, #0x160]
     64c: 92407d08     	and	x8, x8, #0xffffffff
     650: f940ba84     	ldr	x4, [x20, #0x170]
     654: 8b0800a0     	add	x0, x5, x8
     658: 9100c3e1     	add	x1, sp, #0x30
     65c: aa1f03e2     	mov	x2, xzr
     660: 94000000     	bl	0x660 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x660>
		0000000000000660:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     664: f940ea88     	ldr	x8, [x20, #0x1d0]
     668: f9400349     	ldr	x9, [x26]
     66c: f9001280     	str	x0, [x20, #0x20]
     670: 927c6d0a     	and	x10, x8, #0xfffffff0
     674: 3cea6920     	ldr	q0, [x9, x10]
     678: 1100410a     	add	w10, w8, #0x10
     67c: 927c6d4a     	and	x10, x10, #0xfffffff0
     680: 3d807280     	str	q0, [x20, #0x1c0]
     684: 3cea6920     	ldr	q0, [x9, x10]
     688: 1100810a     	add	w10, w8, #0x20
     68c: 927c6d4a     	and	x10, x10, #0xfffffff0
     690: 3d805680     	str	q0, [x20, #0x150]
     694: 3cea6920     	ldr	q0, [x9, x10]
     698: 1100c10a     	add	w10, w8, #0x30
     69c: 927c6d4a     	and	x10, x10, #0xfffffff0
     6a0: 3d805280     	str	q0, [x20, #0x140]
     6a4: 3cea6920     	ldr	q0, [x9, x10]
     6a8: 1101010a     	add	w10, w8, #0x40
     6ac: 927c6d4a     	and	x10, x10, #0xfffffff0
     6b0: 3d804280     	str	q0, [x20, #0x100]
     6b4: 3cea6920     	ldr	q0, [x9, x10]
     6b8: 1101410a     	add	w10, w8, #0x50
     6bc: 91018108     	add	x8, x8, #0x60
     6c0: 927c6d4a     	and	x10, x10, #0xfffffff0
     6c4: 3d804e80     	str	q0, [x20, #0x130]
     6c8: 3cea6920     	ldr	q0, [x9, x10]
     6cc: f900ea88     	str	x8, [x20, #0x1d0]
     6d0: 3d804a80     	str	q0, [x20, #0x120]
     6d4: f940a289     	ldr	x9, [x20, #0x140]
     6d8: f2400d3f     	tst	x9, #0xf
     6dc: 540038c1     	b.ne	0xdf4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>
     6e0: f9400348     	ldr	x8, [x26]
     6e4: 927c6d29     	and	x9, x9, #0xfffffff0
     6e8: 8b09010a     	add	x10, x8, x9
     6ec: f9400949     	ldr	x9, [x10, #0x10]
     6f0: 3dc00140     	ldr	q0, [x10]
     6f4: f9001be9     	str	x9, [sp, #0x30]
     6f8: f940aa89     	ldr	x9, [x20, #0x150]
     6fc: b940194b     	ldr	w11, [x10, #0x18]
     700: f2400d3f     	tst	x9, #0xf
     704: b9003beb     	str	w11, [sp, #0x38]
     708: 54003941     	b.ne	0xe30 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe30>
     70c: 927c6d29     	and	x9, x9, #0xfffffff0
     710: bd438a81     	ldr	s1, [x20, #0x388]
     714: bd401d46     	ldr	s6, [x10, #0x1c]
     718: 8b090108     	add	x8, x8, x9
     71c: 3dc00951     	ldr	q17, [x10, #0x20]
     720: ad418905     	ldp	q5, q2, [x8, #0x30]
     724: bd401904     	ldr	s4, [x8, #0x18]
     728: b9806109     	ldrsw	x9, [x8, #0x60]
     72c: bd402d07     	ldr	s7, [x8, #0x2c]
     730: 4f819042     	fmul	v2.4s, v2.4s, v1.s[0]
     734: fd400901     	ldr	d1, [x8, #0x10]
     738: 5e140443     	mov	s3, v2.s[2]
     73c: 0e22d421     	fadd	v1.2s, v1.2s, v2.2s
     740: 1e232890     	fadd	s16, s4, s3
     744: 3cc1c103     	ldur	q3, [x8, #0x1c]
     748: bd438684     	ldr	s4, [x20, #0x384]
     74c: b9020289     	str	w9, [x20, #0x200]
     750: f9001a89     	str	x9, [x20, #0x30]
     754: 34000209     	cbz	w9, 0x794 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x794>
     758: 1e270132     	fmov	s18, w9
     75c: bd438e93     	ldr	s19, [x20, #0x38c]
     760: 1e270134     	fmov	s20, w9
     764: 131f7d2a     	asr	w10, w9, #31
     768: bd403a95     	ldr	s21, [x20, #0x38]
     76c: 1e323952     	fsub	s18, s10, s18
     770: 4e0c1d54     	mov	v20.s[1], w10
     774: 1e350a75     	fmul	s21, s19, s21
     778: 1e320a72     	fmul	s18, s19, s18
     77c: 0f93928b     	fmul	v11.2s, v20.2s, v19.s[0]
     780: 1e323952     	fsub	s18, s10, s18
     784: 6e0c0655     	mov	v21.s[1], v18.s[0]
     788: 0f929021     	fmul	v1.2s, v1.2s, v18.s[0]
     78c: 1e300a50     	fmul	s16, s18, s16
     790: 3d800bf5     	str	q21, [sp, #0x20]
     794: 0e0c0433     	dup	v19.2s, v1.s[1]
     798: 4f8490b2     	fmul	v18.4s, v5.4s, v4.s[0]
     79c: 1e210894     	fmul	s20, s4, s1
     7a0: bd033a90     	str	s16, [x20, #0x338]
     7a4: f9401bea     	ldr	x10, [sp, #0x30]
     7a8: bd034e87     	str	s7, [x20, #0x34c]
     7ac: f90002ca     	str	x10, [x22]
     7b0: b9403bea     	ldr	w10, [sp, #0x38]
     7b4: 6e0c0613     	mov	v19.s[1], v16.s[0]
     7b8: 4e32d635     	fadd	v21.4s, v17.4s, v18.4s
     7bc: 1e270891     	fmul	s17, s4, s7
     7c0: fd019a81     	str	d1, [x20, #0x330]
     7c4: 3d8002a3     	str	q3, [x21]
     7c8: b9000aca     	str	w10, [x22, #0x8]
     7cc: 6e180473     	mov	v19.d[1], v3.d[0]
     7d0: 4ea0eab0     	fcmlt	v16.4s, v21.4s, #0.0
     7d4: 1e3128c6     	fadd	s6, s6, s17
     7d8: ad1a8a85     	stp	q5, q2, [x20, #0x350]
     7dc: 4f849273     	fmul	v19.4s, v19.4s, v4.s[0]
     7e0: 4e701ea7     	bic	v7.16b, v21.16b, v16.16b
     7e4: bd031e86     	str	s6, [x20, #0x31c]
     7e8: 3d80ca87     	str	q7, [x20, #0x320]
     7ec: 6e136016     	ext	v22.16b, v0.16b, v19.16b, #0xc
     7f0: 6e040696     	mov	v22.s[0], v20.s[0]
     7f4: 4e36d400     	fadd	v0.4s, v0.4s, v22.4s
     7f8: 3d80c280     	str	q0, [x20, #0x300]
     7fc: 34000089     	cbz	w9, 0x80c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x80c>
     800: 3dc00be0     	ldr	q0, [sp, #0x20]
     804: fd01ba8b     	str	d11, [x20, #0x370]
     808: fd01be80     	str	d0, [x20, #0x378]
     80c: 0e0c3c29     	mov	w9, v1.s[1]
     810: 1e26002a     	fmov	w10, s1
     814: f9419e8b     	ldr	x11, [x20, #0x338]
     818: 5f839880     	fmul	s0, s4, v3.s[2]
     81c: 5fa39882     	fmul	s2, s4, v3.s[3]
     820: bd039294     	str	s20, [x20, #0x390]
     824: 3c8582b3     	stur	q19, [x21, #0x58]
     828: bd03ae91     	str	s17, [x20, #0x3ac]
     82c: aa098149     	orr	x9, x10, x9, lsl #32
     830: 3d80ee92     	str	q18, [x20, #0x3b0]
     834: bd03a680     	str	s0, [x20, #0x3a4]
     838: bd03aa82     	str	s2, [x20, #0x3a8]
     83c: a9012d09     	stp	x9, x11, [x8, #0x10]
     840: f940a288     	ldr	x8, [x20, #0x140]
     844: f2400d1f     	tst	x8, #0xf
     848: 540029c1     	b.ne	0xd80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd80>
     84c: f9400349     	ldr	x9, [x26]
     850: f941828a     	ldr	x10, [x20, #0x300]
     854: 927c6d08     	and	x8, x8, #0xfffffff0
     858: f941868b     	ldr	x11, [x20, #0x308]
     85c: 8b080128     	add	x8, x9, x8
     860: a9002d0a     	stp	x10, x11, [x8]
     864: f940a288     	ldr	x8, [x20, #0x140]
     868: f2400d1f     	tst	x8, #0xf
     86c: 540028a1     	b.ne	0xd80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd80>
     870: f9400349     	ldr	x9, [x26]
     874: f9418a8a     	ldr	x10, [x20, #0x310]
     878: 927c6d08     	and	x8, x8, #0xfffffff0
     87c: f9418e8b     	ldr	x11, [x20, #0x318]
     880: 8b080128     	add	x8, x9, x8
     884: a9012d0a     	stp	x10, x11, [x8, #0x10]
     888: f940a288     	ldr	x8, [x20, #0x140]
     88c: f2400d1f     	tst	x8, #0xf
     890: 54002781     	b.ne	0xd80 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd80>
     894: f9400349     	ldr	x9, [x26]
     898: f941928a     	ldr	x10, [x20, #0x320]
     89c: 927c6d08     	and	x8, x8, #0xfffffff0
     8a0: f941968b     	ldr	x11, [x20, #0x328]
     8a4: 8b080128     	add	x8, x9, x8
     8a8: a9022d0a     	stp	x10, x11, [x8, #0x20]
     8ac: f940a289     	ldr	x9, [x20, #0x140]
     8b0: f940034a     	ldr	x10, [x26]
     8b4: f9408a88     	ldr	x8, [x20, #0x110]
     8b8: 8b29414b     	add	x11, x10, w9, uxtw
     8bc: f9001a88     	str	x8, [x20, #0x30]
     8c0: f9002289     	str	x9, [x20, #0x40]
     8c4: b9401169     	ldr	w9, [x11, #0x10]
     8c8: b9020289     	str	w9, [x20, #0x200]
     8cc: b940156c     	ldr	w12, [x11, #0x14]
     8d0: b902068c     	str	w12, [x20, #0x204]
     8d4: b940196b     	ldr	w11, [x11, #0x18]
     8d8: b9020e8b     	str	w11, [x20, #0x20c]
     8dc: b8284949     	str	w9, [x10, w8, uxtw]
     8e0: f9400348     	ldr	x8, [x26]
     8e4: b9403289     	ldr	w9, [x20, #0x30]
     8e8: b942068a     	ldr	w10, [x20, #0x204]
     8ec: 8b090108     	add	x8, x8, x9
     8f0: b900050a     	str	w10, [x8, #0x4]
     8f4: f9400348     	ldr	x8, [x26]
     8f8: b9403289     	ldr	w9, [x20, #0x30]
     8fc: b9420e8a     	ldr	w10, [x20, #0x20c]
     900: 8b090108     	add	x8, x8, x9
     904: b900090a     	str	w10, [x8, #0x8]
     908: bd420e80     	ldr	s0, [x20, #0x20c]
     90c: bd420681     	ldr	s1, [x20, #0x204]
     910: bd420283     	ldr	s3, [x20, #0x200]
     914: f9400348     	ldr	x8, [x26]
     918: b9403289     	ldr	w9, [x20, #0x30]
     91c: 1e200800     	fmul	s0, s0, s0
     920: 1e210821     	fmul	s1, s1, s1
     924: 1e230863     	fmul	s3, s3, s3
     928: 8b090108     	add	x8, x8, x9
     92c: 1e203942     	fsub	s2, s10, s0
     930: bd020e80     	str	s0, [x20, #0x20c]
     934: 1e213841     	fsub	s1, s2, s1
     938: bd020a82     	str	s2, [x20, #0x208]
     93c: 7ea3d423     	fabd	s3, s1, s3
     940: bd020681     	str	s1, [x20, #0x204]
     944: 1e21c063     	fsqrt	s3, s3
     948: bd020283     	str	s3, [x20, #0x200]
     94c: bd000d03     	str	s3, [x8, #0xc]
     950: b9820288     	ldrsw	x8, [x20, #0x200]
     954: f9400389     	ldr	x9, [x28]
     958: f9400345     	ldr	x5, [x26]
     95c: f9002288     	str	x8, [x20, #0x40]
     960: b9400128     	ldr	w8, [x9]
     964: 93407d09     	sxtw	x9, w8
     968: f9001a89     	str	x9, [x20, #0x30]
     96c: b86868a8     	ldr	w8, [x5, x8]
     970: 92401d09     	and	x9, x8, #0xff
     974: b9020288     	str	w8, [x20, #0x200]
     978: d1002928     	sub	x8, x9, #0xa
     97c: 7100293f     	cmp	w9, #0xa
     980: f9001a88     	str	x8, [x20, #0x30]
     984: 540003c3     	b.lo	0x9fc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x9fc>
     988: f9400788     	ldr	x8, [x28, #0x8]
     98c: f9408a89     	ldr	x9, [x20, #0x110]
     990: f940aa8a     	ldr	x10, [x20, #0x150]
     994: b981f28b     	ldrsw	x11, [x20, #0x1f0]
     998: b9800108     	ldrsw	x8, [x8]
     99c: f9002289     	str	x9, [x20, #0x40]
     9a0: 9101414a     	add	x10, x10, #0x50
     9a4: f9002a89     	str	x9, [x20, #0x50]
     9a8: a90327e9     	stp	x9, x9, [sp, #0x30]
     9ac: f9403a89     	ldr	x9, [x20, #0x70]
     9b0: f900128b     	str	x11, [x20, #0x20]
     9b4: f940428b     	ldr	x11, [x20, #0x80]
     9b8: a90427ea     	stp	x10, x9, [sp, #0x40]
     9bc: f9404a89     	ldr	x9, [x20, #0x90]
     9c0: f900328a     	str	x10, [x20, #0x60]
     9c4: f940528a     	ldr	x10, [x20, #0xa0]
     9c8: a90527eb     	stp	x11, x9, [sp, #0x50]
     9cc: f9405a89     	ldr	x9, [x20, #0xb0]
     9d0: f900ca88     	str	x8, [x20, #0x190]
     9d4: a90627ea     	stp	x10, x9, [sp, #0x60]
     9d8: 34001c68     	cbz	w8, 0xd64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd64>
     9dc: f940b283     	ldr	x3, [x20, #0x160]
     9e0: f940ba84     	ldr	x4, [x20, #0x170]
     9e4: 92407d08     	and	x8, x8, #0xffffffff
     9e8: 8b0800a0     	add	x0, x5, x8
     9ec: 9100c3e1     	add	x1, sp, #0x30
     9f0: aa1f03e2     	mov	x2, xzr
     9f4: 94000000     	bl	0x9f4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x9f4>
		00000000000009f4:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     9f8: f9001280     	str	x0, [x20, #0x20]
     9fc: f9400788     	ldr	x8, [x28, #0x8]
     a00: f9408a89     	ldr	x9, [x20, #0x110]
     a04: f940aa8a     	ldr	x10, [x20, #0x150]
     a08: b981f28b     	ldrsw	x11, [x20, #0x1f0]
     a0c: b9800108     	ldrsw	x8, [x8]
     a10: f9002289     	str	x9, [x20, #0x40]
     a14: 9101414a     	add	x10, x10, #0x50
     a18: f9002a89     	str	x9, [x20, #0x50]
     a1c: a90327e9     	stp	x9, x9, [sp, #0x30]
     a20: f9403a89     	ldr	x9, [x20, #0x70]
     a24: f900128b     	str	x11, [x20, #0x20]
     a28: f940428b     	ldr	x11, [x20, #0x80]
     a2c: a90427ea     	stp	x10, x9, [sp, #0x40]
     a30: f9404a89     	ldr	x9, [x20, #0x90]
     a34: f900328a     	str	x10, [x20, #0x60]
     a38: f940528a     	ldr	x10, [x20, #0xa0]
     a3c: a90527eb     	stp	x11, x9, [sp, #0x50]
     a40: f9405a89     	ldr	x9, [x20, #0xb0]
     a44: f900ca88     	str	x8, [x20, #0x190]
     a48: a90627ea     	stp	x10, x9, [sp, #0x60]
     a4c: 340018c8     	cbz	w8, 0xd64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd64>
     a50: f9400345     	ldr	x5, [x26]
     a54: f940b283     	ldr	x3, [x20, #0x160]
     a58: 92407d08     	and	x8, x8, #0xffffffff
     a5c: f940ba84     	ldr	x4, [x20, #0x170]
     a60: 8b0800a0     	add	x0, x5, x8
     a64: 9100c3e1     	add	x1, sp, #0x30
     a68: aa1f03e2     	mov	x2, xzr
     a6c: 94000000     	bl	0xa6c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa6c>
		0000000000000a6c:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     a70: f9408a89     	ldr	x9, [x20, #0x110]
     a74: f940034b     	ldr	x11, [x26]
     a78: f940a28a     	ldr	x10, [x20, #0x140]
     a7c: f9001280     	str	x0, [x20, #0x20]
     a80: 8b294168     	add	x8, x11, w9, uxtw
     a84: f900228a     	str	x10, [x20, #0x40]
     a88: f9001a89     	str	x9, [x20, #0x30]
     a8c: b9400d0c     	ldr	w12, [x8, #0xc]
     a90: b902069f     	str	wzr, [x20, #0x204]
     a94: 1e270180     	fmov	s0, w12
     a98: b902028c     	str	w12, [x20, #0x200]
     a9c: 92400d4c     	and	x12, x10, #0xf
     aa0: 1e202008     	fcmp	s0, #0.0
     aa4: 540001e4     	b.mi	0xae0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xae0>
     aa8: b500184c     	cbnz	x12, 0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     aac: 927c6d4a     	and	x10, x10, #0xfffffff0
     ab0: f2400d3f     	tst	x9, #0xf
     ab4: 8b0a016a     	add	x10, x11, x10
     ab8: 3dc00540     	ldr	q0, [x10, #0x10]
     abc: 3d80a680     	str	q0, [x20, #0x290]
     ac0: 54001781     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     ac4: 3dc00100     	ldr	q0, [x8]
     ac8: 3d80aa80     	str	q0, [x20, #0x2a0]
     acc: fd415280     	ldr	d0, [x20, #0x2a0]
     ad0: bd42aa82     	ldr	s2, [x20, #0x2a8]
     ad4: 0e28d401     	fadd	v1.2s, v0.2s, v8.2s
     ad8: 1e292840     	fadd	s0, s2, s9
     adc: 1400000e     	b	0xb14 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb14>
     ae0: b500168c     	cbnz	x12, 0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     ae4: 927c6d4a     	and	x10, x10, #0xfffffff0
     ae8: f2400d3f     	tst	x9, #0xf
     aec: 8b0a016a     	add	x10, x11, x10
     af0: 3dc00540     	ldr	q0, [x10, #0x10]
     af4: 3d80a680     	str	q0, [x20, #0x290]
     af8: 540015c1     	b.ne	0xdb0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
     afc: 3dc00100     	ldr	q0, [x8]
     b00: 3d80aa80     	str	q0, [x20, #0x2a0]
     b04: fd415280     	ldr	d0, [x20, #0x2a0]
     b08: bd42aa82     	ldr	s2, [x20, #0x2a8]
     b0c: 0ea0d501     	fsub	v1.2s, v8.2s, v0.2s
     b10: 1e223920     	fsub	s0, s9, s2
     b14: 0e0c3c29     	mov	w9, v1.s[1]
     b18: 91004148     	add	x8, x10, #0x10
     b1c: 1e26000a     	fmov	w10, s0
     b20: 1e26002b     	fmov	w11, s1
     b24: b9429e8c     	ldr	w12, [x20, #0x29c]
     b28: fd014a81     	str	d1, [x20, #0x290]
     b2c: bd029a80     	str	s0, [x20, #0x298]
     b30: aa0c814a     	orr	x10, x10, x12, lsl #32
     b34: aa098169     	orr	x9, x11, x9, lsl #32
     b38: a9002909     	stp	x9, x10, [x8]
     b3c: f9414e88     	ldr	x8, [x20, #0x298]
     b40: f9414a89     	ldr	x9, [x20, #0x290]
     b44: f9400345     	ldr	x5, [x26]
     b48: f940aa98     	ldr	x24, [x20, #0x150]
     b4c: 3dc0ca80     	ldr	q0, [x20, #0x320]
     b50: a9042289     	stp	x9, x8, [x20, #0x40]
     b54: 8b3840a8     	add	x8, x5, w24, uxtw
     b58: 3d800e80     	str	q0, [x20, #0x30]
     b5c: b9806908     	ldrsw	x8, [x8, #0x68]
     b60: 927e0109     	and	x9, x8, #0x4
     b64: f9002288     	str	x8, [x20, #0x40]
     b68: f9002a89     	str	x9, [x20, #0x50]
     b6c: 36080108     	tbz	w8, #0x1, 0xb8c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb8c>
     b70: a9432a8b     	ldp	x11, x10, [x20, #0x30]
     b74: 290c2a9f     	stp	wzr, w10, [x20, #0x60]
     b78: d360fd4a     	lsr	x10, x10, #32
     b7c: 290d2a9f     	stp	wzr, w10, [x20, #0x68]
     b80: b500006b     	cbnz	x11, 0xb8c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb8c>
     b84: f940328a     	ldr	x10, [x20, #0x60]
     b88: b40003aa     	cbz	x10, 0xbfc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbfc>
     b8c: 92400108     	and	x8, x8, #0x1
     b90: f9000368     	str	x8, [x27]
     b94: b4000109     	cbz	x9, 0xbb4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbb4>
     b98: f9401e89     	ldr	x9, [x20, #0x38]
     b9c: d360fd2a     	lsr	x10, x9, #32
     ba0: 29077e89     	stp	w9, wzr, [x20, #0x38]
     ba4: 29062a9f     	stp	wzr, w10, [x20, #0x30]
     ba8: f9401a8a     	ldr	x10, [x20, #0x30]
     bac: f100055f     	cmp	x10, #0x1
     bb0: 5400026b     	b.lt	0xbfc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbfc>
     bb4: b4ffb328     	cbz	x8, 0x218 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x218>
     bb8: f9418288     	ldr	x8, [x20, #0x300]
     bbc: f9418689     	ldr	x9, [x20, #0x308]
     bc0: f9418a8a     	ldr	x10, [x20, #0x310]
     bc4: a9032688     	stp	x8, x9, [x20, #0x30]
     bc8: d360fd28     	lsr	x8, x9, #32
     bcc: 29077e89     	stp	w9, wzr, [x20, #0x38]
     bd0: 2906229f     	stp	wzr, w8, [x20, #0x30]
     bd4: f9418e88     	ldr	x8, [x20, #0x318]
     bd8: f9401a89     	ldr	x9, [x20, #0x30]
     bdc: a903228a     	stp	x10, x8, [x20, #0x30]
     be0: b7f800e9     	tbnz	x9, #0x3f, 0xbfc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbfc>
     be4: f9401e88     	ldr	x8, [x20, #0x38]
     be8: d360fd09     	lsr	x9, x8, #32
     bec: 29077e88     	stp	w8, wzr, [x20, #0x38]
     bf0: 2906269f     	stp	wzr, w9, [x20, #0x30]
     bf4: f9401a89     	ldr	x9, [x20, #0x30]
     bf8: b6ffb109     	tbz	x9, #0x3f, 0x218 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x218>
     bfc: f9400b88     	ldr	x8, [x28, #0x10]
     c00: f940e289     	ldr	x9, [x20, #0x1c0]
     c04: f940828a     	ldr	x10, [x20, #0x100]
     c08: f940a28b     	ldr	x11, [x20, #0x140]
     c0c: b981f28c     	ldrsw	x12, [x20, #0x1f0]
     c10: b9800108     	ldrsw	x8, [x8]
     c14: f9002289     	str	x9, [x20, #0x40]
     c18: f9002a8a     	str	x10, [x20, #0x50]
     c1c: a9032be9     	stp	x9, x10, [sp, #0x30]
     c20: f9404289     	ldr	x9, [x20, #0x80]
     c24: f9404a8a     	ldr	x10, [x20, #0x90]
     c28: f9003a8b     	str	x11, [x20, #0x70]
     c2c: a9042ff8     	stp	x24, x11, [sp, #0x40]
     c30: f940528b     	ldr	x11, [x20, #0xa0]
     c34: a9052be9     	stp	x9, x10, [sp, #0x50]
     c38: f9405a89     	ldr	x9, [x20, #0xb0]
     c3c: f9003298     	str	x24, [x20, #0x60]
     c40: f900ca88     	str	x8, [x20, #0x190]
     c44: f900128c     	str	x12, [x20, #0x20]
     c48: a90627eb     	stp	x11, x9, [sp, #0x60]
     c4c: 340008c8     	cbz	w8, 0xd64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd64>
     c50: f940b283     	ldr	x3, [x20, #0x160]
     c54: f940ba84     	ldr	x4, [x20, #0x170]
     c58: 92407d08     	and	x8, x8, #0xffffffff
     c5c: 8b0800a0     	add	x0, x5, x8
     c60: 9100c3e1     	add	x1, sp, #0x30
     c64: aa1f03e2     	mov	x2, xzr
     c68: 94000000     	bl	0xc68 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc68>
		0000000000000c68:  R_AARCH64_CALL26	_call_goal8_asm_systemv
     c6c: f9001280     	str	x0, [x20, #0x20]
     c70: 17fffd6a     	b	0x218 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x218>
     c74: f9400348     	ldr	x8, [x26]
     c78: f940ea89     	ldr	x9, [x20, #0x1d0]
     c7c: f9001297     	str	x23, [x20, #0x20]
     c80: 8b29410a     	add	x10, x8, w9, uxtw
     c84: f940014b     	ldr	x11, [x10]
     c88: f900fa8b     	str	x11, [x20, #0x1f0]
     c8c: 1102412b     	add	w11, w9, #0x90
     c90: f940054a     	ldr	x10, [x10, #0x8]
     c94: 927c6d6b     	and	x11, x11, #0xfffffff0
     c98: f900f28a     	str	x10, [x20, #0x1e0]
     c9c: 1102012a     	add	w10, w9, #0x80
     ca0: 3ceb6900     	ldr	q0, [x8, x11]
     ca4: 927c6d4a     	and	x10, x10, #0xfffffff0
     ca8: 3d807280     	str	q0, [x20, #0x1c0]
     cac: 3cea6900     	ldr	q0, [x8, x10]
     cb0: 1101c12a     	add	w10, w9, #0x70
     cb4: 927c6d4a     	and	x10, x10, #0xfffffff0
     cb8: 3d805680     	str	q0, [x20, #0x150]
     cbc: 3cea6900     	ldr	q0, [x8, x10]
     cc0: 1101812a     	add	w10, w9, #0x60
     cc4: 927c6d4a     	and	x10, x10, #0xfffffff0
     cc8: 3d805280     	str	q0, [x20, #0x140]
     ccc: 3cea6900     	ldr	q0, [x8, x10]
     cd0: 1101412a     	add	w10, w9, #0x50
     cd4: 927c6d4a     	and	x10, x10, #0xfffffff0
     cd8: 3d804e80     	str	q0, [x20, #0x130]
     cdc: 3cea6900     	ldr	q0, [x8, x10]
     ce0: 1101012a     	add	w10, w9, #0x40
     ce4: 927c6d4a     	and	x10, x10, #0xfffffff0
     ce8: 3d804a80     	str	q0, [x20, #0x120]
     cec: 3cea6900     	ldr	q0, [x8, x10]
     cf0: 1100c12a     	add	w10, w9, #0x30
     cf4: 927c6d4a     	and	x10, x10, #0xfffffff0
     cf8: 3d804680     	str	q0, [x20, #0x110]
     cfc: 3cea6900     	ldr	q0, [x8, x10]
     d00: 91028128     	add	x8, x9, #0xa0
     d04: f900ea88     	str	x8, [x20, #0x1d0]
     d08: 3d804280     	str	q0, [x20, #0x100]
     d0c: 94000000     	bl	0xd0c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd0c>
		0000000000000d0c:  R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
     d10: f9400be8     	ldr	x8, [sp, #0x10]
     d14: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000d14:  R_AARCH64_ADR_GOT_PAGE	g_spart_prof
     d18: f9400021     	ldr	x1, [x1]
		0000000000000d18:  R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
     d1c: cb080000     	sub	x0, x0, x8
     d20: 94000000     	bl	0xd20 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd20>
		0000000000000d20:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
     d24: f9400fe8     	ldr	x8, [sp, #0x18]
     d28: f9401508     	ldr	x8, [x8, #0x28]
     d2c: f85d83a9     	ldur	x9, [x29, #-0x28]
     d30: eb09011f     	cmp	x8, x9
     d34: 54000d61     	b.ne	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     d38: aa1703e0     	mov	x0, x23
     d3c: a94f4ff4     	ldp	x20, x19, [sp, #0xf0]
     d40: a94e57f6     	ldp	x22, x21, [sp, #0xe0]
     d44: a94d5ff8     	ldp	x24, x23, [sp, #0xd0]
     d48: a94c67fa     	ldp	x26, x25, [sp, #0xc0]
     d4c: a94b6ffc     	ldp	x28, x27, [sp, #0xb0]
     d50: a94a7bfd     	ldp	x29, x30, [sp, #0xa0]
     d54: 6d4923e9     	ldp	d9, d8, [sp, #0x90]
     d58: 6d482beb     	ldp	d11, d10, [sp, #0x80]
     d5c: 910403ff     	add	sp, sp, #0x100
     d60: d65f03c0     	ret
     d64: 52803202     	mov	w2, #0x190              // =400
     d68: f9400fe8     	ldr	x8, [sp, #0x18]
     d6c: f9401508     	ldr	x8, [x8, #0x28]
     d70: f85d83a9     	ldur	x9, [x29, #-0x28]
     d74: eb09011f     	cmp	x8, x9
     d78: 54000320     	b.eq	0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     d7c: 14000059     	b	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     d80: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000d80:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x433
     d84: 91000109     	add	x9, x8, #0x0
		0000000000000d84:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x433
     d88: 52803802     	mov	w2, #0x1c0              // =448
     d8c: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000d8c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x45a
     d90: 91000108     	add	x8, x8, #0x0
		0000000000000d90:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x45a
     d94: a90023e9     	stp	x9, x8, [sp]
     d98: f9400fe8     	ldr	x8, [sp, #0x18]
     d9c: f9401508     	ldr	x8, [x8, #0x28]
     da0: f85d83a9     	ldur	x9, [x29, #-0x28]
     da4: eb09011f     	cmp	x8, x9
     da8: 540001a0     	b.eq	0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     dac: 1400004d     	b	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     db0: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000db0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
     db4: 91000109     	add	x9, x8, #0x0
		0000000000000db4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
     db8: 52802b02     	mov	w2, #0x158              // =344
     dbc: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000dbc:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3d2
     dc0: 91000108     	add	x8, x8, #0x0
		0000000000000dc0:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3d2
     dc4: a90023e9     	stp	x9, x8, [sp]
     dc8: f9400fe8     	ldr	x8, [sp, #0x18]
     dcc: f9401508     	ldr	x8, [x8, #0x28]
     dd0: f85d83a9     	ldur	x9, [x29, #-0x28]
     dd4: eb09011f     	cmp	x8, x9
     dd8: 54000841     	b.ne	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     ddc: a9400fe0     	ldp	x0, x3, [sp]
     de0: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000de0:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x397
     de4: 91000021     	add	x1, x1, #0x0
		0000000000000de4:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x397
     de8: 90000004     	adrp	x4, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000de8:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
     dec: 91000084     	add	x4, x4, #0x0
		0000000000000dec:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
     df0: 94000000     	bl	0xdf0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf0>
		0000000000000df0:  R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
     df4: f9400fe8     	ldr	x8, [sp, #0x18]
     df8: f9401508     	ldr	x8, [x8, #0x28]
     dfc: f85d83a9     	ldur	x9, [x29, #-0x28]
     e00: eb09011f     	cmp	x8, x9
     e04: 540006e1     	b.ne	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     e08: 90000000     	adrp	x0, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e08:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1
     e0c: 91000000     	add	x0, x0, #0x0
		0000000000000e0c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1
     e10: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e10:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a
     e14: 91000021     	add	x1, x1, #0x0
		0000000000000e14:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a
     e18: 90000003     	adrp	x3, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e18:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x92
     e1c: 91000063     	add	x3, x3, #0x0
		0000000000000e1c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x92
     e20: 90000004     	adrp	x4, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e20:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
     e24: 91000084     	add	x4, x4, #0x0
		0000000000000e24:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
     e28: 52801f42     	mov	w2, #0xfa               // =250
     e2c: 94000000     	bl	0xe2c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe2c>
		0000000000000e2c:  R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
     e30: f9400fe8     	ldr	x8, [sp, #0x18]
     e34: f9401508     	ldr	x8, [x8, #0x28]
     e38: f85d83a9     	ldur	x9, [x29, #-0x28]
     e3c: eb09011f     	cmp	x8, x9
     e40: 54000501     	b.ne	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     e44: 90000000     	adrp	x0, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e44:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xca
     e48: 91000000     	add	x0, x0, #0x0
		0000000000000e48:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xca
     e4c: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e4c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a
     e50: 91000021     	add	x1, x1, #0x0
		0000000000000e50:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a
     e54: 90000003     	adrp	x3, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e54:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x92
     e58: 91000063     	add	x3, x3, #0x0
		0000000000000e58:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x92
     e5c: 90000004     	adrp	x4, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e5c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
     e60: 91000084     	add	x4, x4, #0x0
		0000000000000e60:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
     e64: 52802002     	mov	w2, #0x100              // =256
     e68: 94000000     	bl	0xe68 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe68>
		0000000000000e68:  R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
     e6c: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e6c:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3d2
     e70: 91000109     	add	x9, x8, #0x0
		0000000000000e70:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3d2
     e74: 52802b02     	mov	w2, #0x158              // =344
     e78: 90000008     	adrp	x8, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000e78:  R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
     e7c: 91000108     	add	x8, x8, #0x0
		0000000000000e7c:  R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
     e80: a90027e8     	stp	x8, x9, [sp]
     e84: f9400fe8     	ldr	x8, [sp, #0x18]
     e88: f9401508     	ldr	x8, [x8, #0x28]
     e8c: f85d83a9     	ldur	x9, [x29, #-0x28]
     e90: eb09011f     	cmp	x8, x9
     e94: 54fffa40     	b.eq	0xddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
     e98: 14000012     	b	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     e9c: 14000003     	b	0xea8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xea8>
     ea0: 14000002     	b	0xea8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xea8>
     ea4: 14000001     	b	0xea8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xea8>
     ea8: aa0003f4     	mov	x20, x0
     eac: 94000000     	bl	0xeac <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xeac>
		0000000000000eac:  R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
     eb0: f9400be8     	ldr	x8, [sp, #0x10]
     eb4: 90000001     	adrp	x1, 0x0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>
		0000000000000eb4:  R_AARCH64_ADR_GOT_PAGE	g_spart_prof
     eb8: f9400021     	ldr	x1, [x1]
		0000000000000eb8:  R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
     ebc: cb080000     	sub	x0, x0, x8
     ec0: 94000000     	bl	0xec0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xec0>
		0000000000000ec0:  R_AARCH64_CALL26	__aarch64_ldadd8_relax
     ec4: f9400fe8     	ldr	x8, [sp, #0x18]
     ec8: f9401508     	ldr	x8, [x8, #0x28]
     ecc: f85d83a9     	ldur	x9, [x29, #-0x28]
     ed0: eb09011f     	cmp	x8, x9
     ed4: 54000061     	b.ne	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
     ed8: aa1403e0     	mov	x0, x20
     edc: 94000000     	bl	0xedc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xedc>
		0000000000000edc:  R_AARCH64_CALL26	_Unwind_Resume
     ee0: 94000000     	bl	0xee0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xee0>
		0000000000000ee0:  R_AARCH64_CALL26	__stack_chk_fail
