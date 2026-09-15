$ aarch64-linux-gnu-objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-before-android.o

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt8/tested-before-android.o:     file format elf64-littleaarch64


Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
   0:	d10383ff 	sub	sp, sp, #0xe0
   4:	fd0033ea 	str	d10, [sp, #96]
   8:	6d0723e9 	stp	d9, d8, [sp, #112]
   c:	a9087bfd 	stp	x29, x30, [sp, #128]
  10:	a9096ffc 	stp	x28, x27, [sp, #144]
  14:	a90a67fa 	stp	x26, x25, [sp, #160]
  18:	a90b5ff8 	stp	x24, x23, [sp, #176]
  1c:	a90c57f6 	stp	x22, x21, [sp, #192]
  20:	a90d4ff4 	stp	x20, x19, [sp, #208]
  24:	910203fd 	add	x29, sp, #0x80
  28:	d53bd058 	mrs	x24, tpidr_el0
  2c:	aa0003f4 	mov	x20, x0
  30:	f9401708 	ldr	x8, [x24, #40]
  34:	f81d83a8 	stur	x8, [x29, #-40]
  38:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	38: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
  3c:	f9000be0 	str	x0, [sp, #16]
  40:	90000019 	adrp	x25, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	40: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
  44:	52800020 	mov	w0, #0x1                   	// #1
  48:	f9400339 	ldr	x25, [x25]	48: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
  4c:	91008321 	add	x1, x25, #0x20
  50:	94000000 	bl	0 <__aarch64_ldadd8_relax>	50: R_AARCH64_CALL26	__aarch64_ldadd8_relax
  54:	9000001a 	adrp	x26, 0 <g_ee_main_mem>	54: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  58:	f940ea88 	ldr	x8, [x20, #464]
  5c:	aa1403fb 	mov	x27, x20
  60:	f940035a 	ldr	x26, [x26]	60: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  64:	f940fa8a 	ldr	x10, [x20, #496]
  68:	9000001c 	adrp	x28, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	68: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::cache
  6c:	d1028108 	sub	x8, x8, #0xa0
  70:	f9400349 	ldr	x9, [x26]
  74:	f900ea88 	str	x8, [x20, #464]
  78:	f828492a 	str	x10, [x9, w8, uxtw]
  7c:	f9400348 	ldr	x8, [x26]
  80:	b941d289 	ldr	w9, [x20, #464]
  84:	f940f28a 	ldr	x10, [x20, #480]
  88:	8b090108 	add	x8, x8, x9
  8c:	f900050a 	str	x10, [x8, #8]
  90:	b941d288 	ldr	w8, [x20, #464]
  94:	f940ca89 	ldr	x9, [x20, #400]
  98:	f940034a 	ldr	x10, [x26]
  9c:	3dc04280 	ldr	q0, [x20, #256]
  a0:	1100c108 	add	w8, w8, #0x30
  a4:	f900f289 	str	x9, [x20, #480]
  a8:	927c6d08 	and	x8, x8, #0xfffffff0
  ac:	3ca86940 	str	q0, [x10, x8]
  b0:	b941d288 	ldr	w8, [x20, #464]
  b4:	f9400349 	ldr	x9, [x26]
  b8:	3dc04680 	ldr	q0, [x20, #272]
  bc:	11010108 	add	w8, w8, #0x40
  c0:	927c6d08 	and	x8, x8, #0xfffffff0
  c4:	3ca86920 	str	q0, [x9, x8]
  c8:	b941d288 	ldr	w8, [x20, #464]
  cc:	f9400349 	ldr	x9, [x26]
  d0:	3dc04a80 	ldr	q0, [x20, #288]
  d4:	11014108 	add	w8, w8, #0x50
  d8:	927c6d08 	and	x8, x8, #0xfffffff0
  dc:	3ca86920 	str	q0, [x9, x8]
  e0:	b941d288 	ldr	w8, [x20, #464]
  e4:	f9400349 	ldr	x9, [x26]
  e8:	3dc04e80 	ldr	q0, [x20, #304]
  ec:	11018108 	add	w8, w8, #0x60
  f0:	927c6d08 	and	x8, x8, #0xfffffff0
  f4:	3ca86920 	str	q0, [x9, x8]
  f8:	b941d288 	ldr	w8, [x20, #464]
  fc:	f9400349 	ldr	x9, [x26]
 100:	3dc05280 	ldr	q0, [x20, #320]
 104:	1101c108 	add	w8, w8, #0x70
 108:	927c6d08 	and	x8, x8, #0xfffffff0
 10c:	3ca86920 	str	q0, [x9, x8]
 110:	b941d288 	ldr	w8, [x20, #464]
 114:	f9400349 	ldr	x9, [x26]
 118:	3dc05680 	ldr	q0, [x20, #336]
 11c:	11020108 	add	w8, w8, #0x80
 120:	927c6d08 	and	x8, x8, #0xfffffff0
 124:	3ca86920 	str	q0, [x9, x8]
 128:	b941d288 	ldr	w8, [x20, #464]
 12c:	f9400349 	ldr	x9, [x26]
 130:	3dc07280 	ldr	q0, [x20, #448]
 134:	11024108 	add	w8, w8, #0x90
 138:	927c6d08 	and	x8, x8, #0xfffffff0
 13c:	3ca86920 	str	q0, [x9, x8]
 140:	f8440f68 	ldr	x8, [x27, #64]!
 144:	f9400b69 	ldr	x9, [x27, #16]
 148:	f940136a 	ldr	x10, [x27, #32]
 14c:	a901ffff 	stp	xzr, xzr, [sp, #24]
 150:	f900e288 	str	x8, [x20, #448]
 154:	f9401b68 	ldr	x8, [x27, #48]
 158:	3cc183e0 	ldur	q0, [sp, #24]
 15c:	f900aa89 	str	x9, [x20, #336]
 160:	f9402369 	ldr	x9, [x27, #64]
 164:	f9008288 	str	x8, [x20, #256]
 168:	f940ea88 	ldr	x8, [x20, #464]
 16c:	f900a28a 	str	x10, [x20, #320]
 170:	f9402b6a 	ldr	x10, [x27, #80]
 174:	91004108 	add	x8, x8, #0x10
 178:	f9009a89 	str	x9, [x20, #304]
 17c:	f9400349 	ldr	x9, [x26]
 180:	f900928a 	str	x10, [x20, #288]
 184:	f9008a88 	str	x8, [x20, #272]
 188:	927c6d08 	and	x8, x8, #0xfffffff0
 18c:	f940039c 	ldr	x28, [x28]	18c: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
 190:	3ca86920 	str	q0, [x9, x8]
 194:	f9400388 	ldr	x8, [x28]
 198:	b9800108 	ldrsw	x8, [x8]
 19c:	72000d1f 	tst	w8, #0xf
 1a0:	f81f0368 	stur	x8, [x27, #-16]
 1a4:	54006481 	b.ne	e34 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe34>  // b.any
 1a8:	f9400349 	ldr	x9, [x26]
 1ac:	927c6d08 	and	x8, x8, #0xfffffff0
 1b0:	2f00e408 	movi	d8, #0x0
 1b4:	2f00e409 	movi	d9, #0x0
 1b8:	1e2e100a 	fmov	s10, #1.000000000000000000e+00
 1bc:	910b1375 	add	x21, x27, #0x2c4
 1c0:	3ce86920 	ldr	q0, [x9, x8]
 1c4:	b941d288 	ldr	w8, [x20, #464]
 1c8:	92800016 	mov	x22, #0xffffffffffffffff    	// #-1
 1cc:	3d80e280 	str	q0, [x20, #896]
 1d0:	11008108 	add	w8, w8, #0x20
 1d4:	f941c68a 	ldr	x10, [x20, #904]
 1d8:	394e028b 	ldrb	w11, [x20, #896]
 1dc:	927c6d08 	and	x8, x8, #0xfffffff0
 1e0:	8b080128 	add	x8, x9, x8
 1e4:	a9032a8b 	stp	x11, x10, [x20, #48]
 1e8:	a900290b 	stp	x11, x10, [x8]
 1ec:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	1ec: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x316
 1f0:	91000109 	add	x9, x8, #0x0	1f0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x316
 1f4:	f940aa93 	ldr	x19, [x20, #336]
 1f8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	1f8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x311
 1fc:	91000108 	add	x8, x8, #0x0	1fc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x311
 200:	a90023e9 	stp	x9, x8, [sp]
 204:	1400000e 	b	23c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x23c>
 208:	f9409a88 	ldr	x8, [x20, #304]
 20c:	f940aa89 	ldr	x9, [x20, #336]
 210:	f940a28a 	ldr	x10, [x20, #320]
 214:	f940828b 	ldr	x11, [x20, #256]
 218:	f1000508 	subs	x8, x8, #0x1
 21c:	91024133 	add	x19, x9, #0x90
 220:	f9009a88 	str	x8, [x20, #304]
 224:	9100c148 	add	x8, x10, #0x30
 228:	91000577 	add	x23, x11, #0x1
 22c:	f900aa93 	str	x19, [x20, #336]
 230:	f900a288 	str	x8, [x20, #320]
 234:	f9008297 	str	x23, [x20, #256]
 238:	54005460 	b.eq	cc4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xcc4>  // b.none
 23c:	91010321 	add	x1, x25, #0x40
 240:	52800020 	mov	w0, #0x1                   	// #1
 244:	94000000 	bl	0 <__aarch64_ldadd8_relax>	244: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 248:	f9400345 	ldr	x5, [x26]
 24c:	92407e69 	and	x9, x19, #0xffffffff
 250:	b941728b 	ldr	w11, [x20, #368]
 254:	8b0900a8 	add	x8, x5, x9
 258:	b980810a 	ldrsw	x10, [x8, #128]
 25c:	6b0b015f 	cmp	w10, w11
 260:	f9001a8a 	str	x10, [x20, #48]
 264:	54fffd20 	b.eq	208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>  // b.none
 268:	b941228c 	ldr	w12, [x20, #288]
 26c:	b980690a 	ldrsw	x10, [x8, #104]
 270:	6b0b019f 	cmp	w12, w11
 274:	f9001a8a 	str	x10, [x20, #48]
 278:	54000300 	b.eq	2d8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d8>  // b.none
 27c:	9273014b 	and	x11, x10, #0x2000
 280:	f9001a8b 	str	x11, [x20, #48]
 284:	376802aa 	tbnz	w10, #13, 2d8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d8>
 288:	b9806509 	ldrsw	x9, [x8, #100]
 28c:	f9002296 	str	x22, [x20, #64]
 290:	f9001a89 	str	x9, [x20, #48]
 294:	34004dc9 	cbz	w9, c4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
 298:	b9806909 	ldrsw	x9, [x8, #104]
 29c:	927a012a 	and	x10, x9, #0x40
 2a0:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
 2a4:	f9001a8a 	str	x10, [x20, #48]
 2a8:	f900228b 	str	x11, [x20, #64]
 2ac:	b900690b 	str	w11, [x8, #104]
 2b0:	3637fac9 	tbz	w9, #6, 208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
 2b4:	f9400348 	ldr	x8, [x26]
 2b8:	b9415289 	ldr	w9, [x20, #336]
 2bc:	b941428a 	ldr	w10, [x20, #320]
 2c0:	8b090109 	add	x9, x8, x9
 2c4:	8b0a0108 	add	x8, x8, x10
 2c8:	b9807d29 	ldrsw	x9, [x9, #124]
 2cc:	f9001a89 	str	x9, [x20, #48]
 2d0:	b9002d09 	str	w9, [x8, #44]
 2d4:	17ffffcd 	b	208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
 2d8:	b941d28b 	ldr	w11, [x20, #464]
 2dc:	b980650a 	ldrsw	x10, [x8, #100]
 2e0:	f9002296 	str	x22, [x20, #64]
 2e4:	1100816b 	add	w11, w11, #0x20
 2e8:	f9001a8a 	str	x10, [x20, #48]
 2ec:	3100055f 	cmn	w10, #0x1
 2f0:	927c6d6b 	and	x11, x11, #0xfffffff0
 2f4:	3ceb68a0 	ldr	q0, [x5, x11]
 2f8:	3d800360 	str	q0, [x27]
 2fc:	54000260 	b.eq	348 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x348>  // b.none
 300:	f9402289 	ldr	x9, [x20, #64]
 304:	6f00e401 	movi	v1.2d, #0x0
 308:	cb090149 	sub	x9, x10, x9
 30c:	1e270120 	fmov	s0, w9
 310:	d360fd2b 	lsr	x11, x9, #32
 314:	f9002289 	str	x9, [x20, #64]
 318:	4e0c1d60 	mov	v0.s[1], w11
 31c:	9101228b 	add	x11, x20, #0x48
 320:	4d408160 	ld1	{v0.s}[2], [x11]
 324:	9101328b 	add	x11, x20, #0x4c
 328:	4d409160 	ld1	{v0.s}[3], [x11]
 32c:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
 330:	3d800e80 	str	q0, [x20, #48]
 334:	340048ca 	cbz	w10, c4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
 338:	f9401a89 	ldr	x9, [x20, #48]
 33c:	b9006509 	str	w9, [x8, #100]
 340:	f9400345 	ldr	x5, [x26]
 344:	b9415289 	ldr	w9, [x20, #336]
 348:	8b0900a8 	add	x8, x5, x9
 34c:	b9806909 	ldrsw	x9, [x8, #104]
 350:	927a012a 	and	x10, x9, #0x40
 354:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
 358:	f9001a8a 	str	x10, [x20, #48]
 35c:	f900228b 	str	x11, [x20, #64]
 360:	b900690b 	str	w11, [x8, #104]
 364:	36300129 	tbz	w9, #6, 388 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x388>
 368:	f9400348 	ldr	x8, [x26]
 36c:	b9415289 	ldr	w9, [x20, #336]
 370:	b941428a 	ldr	w10, [x20, #320]
 374:	8b090109 	add	x9, x8, x9
 378:	8b0a0108 	add	x8, x8, x10
 37c:	b9807d29 	ldrsw	x9, [x9, #124]
 380:	f9001a89 	str	x9, [x20, #48]
 384:	b9002d09 	str	w9, [x8, #44]
 388:	f9400348 	ldr	x8, [x26]
 38c:	b941528a 	ldr	w10, [x20, #336]
 390:	8b0a0109 	add	x9, x8, x10
 394:	b980712b 	ldrsw	x11, [x9, #112]
 398:	f940ea89 	ldr	x9, [x20, #464]
 39c:	f900ca8b 	str	x11, [x20, #400]
 3a0:	34000b8b 	cbz	w11, 510 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x510>
 3a4:	d1018129 	sub	x9, x9, #0x60
 3a8:	3dc07280 	ldr	q0, [x20, #448]
 3ac:	f900ea89 	str	x9, [x20, #464]
 3b0:	927c6d29 	and	x9, x9, #0xfffffff0
 3b4:	3ca96900 	str	q0, [x8, x9]
 3b8:	b941d288 	ldr	w8, [x20, #464]
 3bc:	f9400349 	ldr	x9, [x26]
 3c0:	3dc05680 	ldr	q0, [x20, #336]
 3c4:	11004108 	add	w8, w8, #0x10
 3c8:	927c6d08 	and	x8, x8, #0xfffffff0
 3cc:	3ca86920 	str	q0, [x9, x8]
 3d0:	b941d288 	ldr	w8, [x20, #464]
 3d4:	f9400349 	ldr	x9, [x26]
 3d8:	3dc05280 	ldr	q0, [x20, #320]
 3dc:	11008108 	add	w8, w8, #0x20
 3e0:	927c6d08 	and	x8, x8, #0xfffffff0
 3e4:	3ca86920 	str	q0, [x9, x8]
 3e8:	b941d288 	ldr	w8, [x20, #464]
 3ec:	f9400349 	ldr	x9, [x26]
 3f0:	3dc04280 	ldr	q0, [x20, #256]
 3f4:	1100c108 	add	w8, w8, #0x30
 3f8:	927c6d08 	and	x8, x8, #0xfffffff0
 3fc:	3ca86920 	str	q0, [x9, x8]
 400:	b941d288 	ldr	w8, [x20, #464]
 404:	f9400349 	ldr	x9, [x26]
 408:	3dc04e80 	ldr	q0, [x20, #304]
 40c:	11010108 	add	w8, w8, #0x40
 410:	927c6d08 	and	x8, x8, #0xfffffff0
 414:	3ca86920 	str	q0, [x9, x8]
 418:	f940e288 	ldr	x8, [x20, #448]
 41c:	b941d28a 	ldr	w10, [x20, #464]
 420:	f940aa89 	ldr	x9, [x20, #336]
 424:	f940a28b 	ldr	x11, [x20, #320]
 428:	f940034c 	ldr	x12, [x26]
 42c:	3dc04a80 	ldr	q0, [x20, #288]
 430:	f9002288 	str	x8, [x20, #64]
 434:	11014148 	add	w8, w10, #0x50
 438:	f9002a89 	str	x9, [x20, #80]
 43c:	927c6d09 	and	x9, x8, #0xfffffff0
 440:	b9419288 	ldr	w8, [x20, #400]
 444:	f900328b 	str	x11, [x20, #96]
 448:	3ca96980 	str	q0, [x12, x9]
 44c:	f9402289 	ldr	x9, [x20, #64]
 450:	f9402a8a 	ldr	x10, [x20, #80]
 454:	f940328b 	ldr	x11, [x20, #96]
 458:	a901abe9 	stp	x9, x10, [sp, #24]
 45c:	f9403a89 	ldr	x9, [x20, #112]
 460:	f940428a 	ldr	x10, [x20, #128]
 464:	a902a7eb 	stp	x11, x9, [sp, #40]
 468:	f9404a8b 	ldr	x11, [x20, #144]
 46c:	f9405289 	ldr	x9, [x20, #160]
 470:	a903afea 	stp	x10, x11, [sp, #56]
 474:	f9405a8a 	ldr	x10, [x20, #176]
 478:	a904abe9 	stp	x9, x10, [sp, #72]
 47c:	34004b08 	cbz	w8, ddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
 480:	f9400345 	ldr	x5, [x26]
 484:	f940b283 	ldr	x3, [x20, #352]
 488:	f940ba84 	ldr	x4, [x20, #368]
 48c:	8b0800a0 	add	x0, x5, x8
 490:	910063e1 	add	x1, sp, #0x18
 494:	aa1f03e2 	mov	x2, xzr
 498:	94000000 	bl	0 <_call_goal8_asm_systemv>	498: R_AARCH64_CALL26	_call_goal8_asm_systemv
 49c:	f940ea89 	ldr	x9, [x20, #464]
 4a0:	f9400348 	ldr	x8, [x26]
 4a4:	f9001280 	str	x0, [x20, #32]
 4a8:	927c6d2a 	and	x10, x9, #0xfffffff0
 4ac:	3cea6900 	ldr	q0, [x8, x10]
 4b0:	1100412a 	add	w10, w9, #0x10
 4b4:	927c6d4a 	and	x10, x10, #0xfffffff0
 4b8:	3d807280 	str	q0, [x20, #448]
 4bc:	3cea6900 	ldr	q0, [x8, x10]
 4c0:	1100812a 	add	w10, w9, #0x20
 4c4:	927c6d4a 	and	x10, x10, #0xfffffff0
 4c8:	3d805680 	str	q0, [x20, #336]
 4cc:	3cea6900 	ldr	q0, [x8, x10]
 4d0:	1100c12a 	add	w10, w9, #0x30
 4d4:	927c6d4a 	and	x10, x10, #0xfffffff0
 4d8:	3d805280 	str	q0, [x20, #320]
 4dc:	3cea6900 	ldr	q0, [x8, x10]
 4e0:	1101012a 	add	w10, w9, #0x40
 4e4:	927c6d4a 	and	x10, x10, #0xfffffff0
 4e8:	3d804280 	str	q0, [x20, #256]
 4ec:	3cea6900 	ldr	q0, [x8, x10]
 4f0:	1101412a 	add	w10, w9, #0x50
 4f4:	91018129 	add	x9, x9, #0x60
 4f8:	927c6d4a 	and	x10, x10, #0xfffffff0
 4fc:	3d804e80 	str	q0, [x20, #304]
 500:	3cea6900 	ldr	q0, [x8, x10]
 504:	b941528a 	ldr	w10, [x20, #336]
 508:	f900ea89 	str	x9, [x20, #464]
 50c:	3d804a80 	str	q0, [x20, #288]
 510:	8b0a010a 	add	x10, x8, x10
 514:	11008129 	add	w9, w9, #0x20
 518:	b980794c 	ldrsw	x12, [x10, #120]
 51c:	927c6d29 	and	x9, x9, #0xfffffff0
 520:	f9002a8c 	str	x12, [x20, #80]
 524:	b980754b 	ldrsw	x11, [x10, #116]
 528:	f9001a8b 	str	x11, [x20, #48]
 52c:	3ce96900 	ldr	q0, [x8, x9]
 530:	3d800360 	str	q0, [x27]
 534:	34000c8c 	cbz	w12, 6c4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6c4>
 538:	f9402288 	ldr	x8, [x20, #64]
 53c:	eb080168 	subs	x8, x11, x8
 540:	f9001a88 	str	x8, [x20, #48]
 544:	b9007548 	str	w8, [x10, #116]
 548:	54000be5 	b.pl	6c4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6c4>  // b.nfrst
 54c:	f940ea88 	ldr	x8, [x20, #464]
 550:	f9400349 	ldr	x9, [x26]
 554:	3dc07280 	ldr	q0, [x20, #448]
 558:	d1018108 	sub	x8, x8, #0x60
 55c:	f900ea88 	str	x8, [x20, #464]
 560:	927c6d08 	and	x8, x8, #0xfffffff0
 564:	3ca86920 	str	q0, [x9, x8]
 568:	b941d288 	ldr	w8, [x20, #464]
 56c:	f9400349 	ldr	x9, [x26]
 570:	3dc05680 	ldr	q0, [x20, #336]
 574:	11004108 	add	w8, w8, #0x10
 578:	927c6d08 	and	x8, x8, #0xfffffff0
 57c:	3ca86920 	str	q0, [x9, x8]
 580:	b941d288 	ldr	w8, [x20, #464]
 584:	f9400349 	ldr	x9, [x26]
 588:	3dc05280 	ldr	q0, [x20, #320]
 58c:	11008108 	add	w8, w8, #0x20
 590:	927c6d08 	and	x8, x8, #0xfffffff0
 594:	3ca86920 	str	q0, [x9, x8]
 598:	b941d288 	ldr	w8, [x20, #464]
 59c:	f9400349 	ldr	x9, [x26]
 5a0:	3dc04280 	ldr	q0, [x20, #256]
 5a4:	1100c108 	add	w8, w8, #0x30
 5a8:	927c6d08 	and	x8, x8, #0xfffffff0
 5ac:	3ca86920 	str	q0, [x9, x8]
 5b0:	b941d288 	ldr	w8, [x20, #464]
 5b4:	f9400349 	ldr	x9, [x26]
 5b8:	3dc04e80 	ldr	q0, [x20, #304]
 5bc:	11010108 	add	w8, w8, #0x40
 5c0:	927c6d08 	and	x8, x8, #0xfffffff0
 5c4:	3ca86920 	str	q0, [x9, x8]
 5c8:	b941d288 	ldr	w8, [x20, #464]
 5cc:	f9400349 	ldr	x9, [x26]
 5d0:	3dc04a80 	ldr	q0, [x20, #288]
 5d4:	11014108 	add	w8, w8, #0x50
 5d8:	927c6d08 	and	x8, x8, #0xfffffff0
 5dc:	3ca86920 	str	q0, [x9, x8]
 5e0:	f940e289 	ldr	x9, [x20, #448]
 5e4:	f940a28a 	ldr	x10, [x20, #320]
 5e8:	f940aa8b 	ldr	x11, [x20, #336]
 5ec:	f9400f88 	ldr	x8, [x28, #24]
 5f0:	b981f28c 	ldrsw	x12, [x20, #496]
 5f4:	f9002289 	str	x9, [x20, #64]
 5f8:	f9003a8a 	str	x10, [x20, #112]
 5fc:	f900328b 	str	x11, [x20, #96]
 600:	b9800108 	ldrsw	x8, [x8]
 604:	f900128c 	str	x12, [x20, #32]
 608:	f9402a8c 	ldr	x12, [x20, #80]
 60c:	a902abeb 	stp	x11, x10, [sp, #40]
 610:	f9404a8b 	ldr	x11, [x20, #144]
 614:	f9405a8a 	ldr	x10, [x20, #176]
 618:	a901b3e9 	stp	x9, x12, [sp, #24]
 61c:	f9404289 	ldr	x9, [x20, #128]
 620:	f900ca88 	str	x8, [x20, #400]
 624:	a903afe9 	stp	x9, x11, [sp, #56]
 628:	f9405289 	ldr	x9, [x20, #160]
 62c:	a904abe9 	stp	x9, x10, [sp, #72]
 630:	34003d68 	cbz	w8, ddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
 634:	f9400345 	ldr	x5, [x26]
 638:	f940b283 	ldr	x3, [x20, #352]
 63c:	92407d08 	and	x8, x8, #0xffffffff
 640:	f940ba84 	ldr	x4, [x20, #368]
 644:	8b0800a0 	add	x0, x5, x8
 648:	910063e1 	add	x1, sp, #0x18
 64c:	aa1f03e2 	mov	x2, xzr
 650:	94000000 	bl	0 <_call_goal8_asm_systemv>	650: R_AARCH64_CALL26	_call_goal8_asm_systemv
 654:	f940ea88 	ldr	x8, [x20, #464]
 658:	f9400349 	ldr	x9, [x26]
 65c:	f9001280 	str	x0, [x20, #32]
 660:	927c6d0a 	and	x10, x8, #0xfffffff0
 664:	3cea6920 	ldr	q0, [x9, x10]
 668:	1100410a 	add	w10, w8, #0x10
 66c:	927c6d4a 	and	x10, x10, #0xfffffff0
 670:	3d807280 	str	q0, [x20, #448]
 674:	3cea6920 	ldr	q0, [x9, x10]
 678:	1100810a 	add	w10, w8, #0x20
 67c:	927c6d4a 	and	x10, x10, #0xfffffff0
 680:	3d805680 	str	q0, [x20, #336]
 684:	3cea6920 	ldr	q0, [x9, x10]
 688:	1100c10a 	add	w10, w8, #0x30
 68c:	927c6d4a 	and	x10, x10, #0xfffffff0
 690:	3d805280 	str	q0, [x20, #320]
 694:	3cea6920 	ldr	q0, [x9, x10]
 698:	1101010a 	add	w10, w8, #0x40
 69c:	927c6d4a 	and	x10, x10, #0xfffffff0
 6a0:	3d804280 	str	q0, [x20, #256]
 6a4:	3cea6920 	ldr	q0, [x9, x10]
 6a8:	1101410a 	add	w10, w8, #0x50
 6ac:	91018108 	add	x8, x8, #0x60
 6b0:	927c6d4a 	and	x10, x10, #0xfffffff0
 6b4:	3d804e80 	str	q0, [x20, #304]
 6b8:	3cea6920 	ldr	q0, [x9, x10]
 6bc:	f900ea88 	str	x8, [x20, #464]
 6c0:	3d804a80 	str	q0, [x20, #288]
 6c4:	f940a289 	ldr	x9, [x20, #320]
 6c8:	f2400d3f 	tst	x9, #0xf
 6cc:	54003721 	b.ne	db0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>  // b.any
 6d0:	f9400348 	ldr	x8, [x26]
 6d4:	927c6d29 	and	x9, x9, #0xfffffff0
 6d8:	8b09010a 	add	x10, x8, x9
 6dc:	f940aa89 	ldr	x9, [x20, #336]
 6e0:	3dc00140 	ldr	q0, [x10]
 6e4:	f2400d3f 	tst	x9, #0xf
 6e8:	3d80c280 	str	q0, [x20, #768]
 6ec:	3dc00540 	ldr	q0, [x10, #16]
 6f0:	3d80c680 	str	q0, [x20, #784]
 6f4:	3dc00940 	ldr	q0, [x10, #32]
 6f8:	3d80ca80 	str	q0, [x20, #800]
 6fc:	540035a1 	b.ne	db0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>  // b.any
 700:	927c6d29 	and	x9, x9, #0xfffffff0
 704:	8b090108 	add	x8, x8, x9
 708:	3dc00500 	ldr	q0, [x8, #16]
 70c:	3d80ce80 	str	q0, [x20, #816]
 710:	3dc00900 	ldr	q0, [x8, #32]
 714:	bd433284 	ldr	s4, [x20, #816]
 718:	3d80d280 	str	q0, [x20, #832]
 71c:	3dc00d00 	ldr	q0, [x8, #48]
 720:	3d80d680 	str	q0, [x20, #848]
 724:	3dc01100 	ldr	q0, [x8, #64]
 728:	3d80da80 	str	q0, [x20, #864]
 72c:	bd438a80 	ldr	s0, [x20, #904]
 730:	bd436281 	ldr	s1, [x20, #864]
 734:	fd4032a2 	ldr	d2, [x21, #96]
 738:	bd436e83 	ldr	s3, [x20, #876]
 73c:	b9806109 	ldrsw	x9, [x8, #96]
 740:	1e200821 	fmul	s1, s1, s0
 744:	0f809042 	fmul	v2.2s, v2.2s, v0.s[0]
 748:	1e200863 	fmul	s3, s3, s0
 74c:	fd401aa0 	ldr	d0, [x21, #48]
 750:	b9020289 	str	w9, [x20, #512]
 754:	f9001a89 	str	x9, [x20, #48]
 758:	bd036281 	str	s1, [x20, #864]
 75c:	1e242821 	fadd	s1, s1, s4
 760:	0e20d440 	fadd	v0.2s, v2.2s, v0.2s
 764:	fd0032a2 	str	d2, [x21, #96]
 768:	bd438e82 	ldr	s2, [x20, #908]
 76c:	bd036e83 	str	s3, [x20, #876]
 770:	bd033281 	str	s1, [x20, #816]
 774:	fd001aa0 	str	d0, [x21, #48]
 778:	34000249 	cbz	w9, 7c0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x7c0>
 77c:	1e270123 	fmov	s3, w9
 780:	f9401e8a 	ldr	x10, [x20, #56]
 784:	9e670124 	fmov	d4, x9
 788:	f901be8a 	str	x10, [x20, #888]
 78c:	1e233943 	fsub	s3, s10, s3
 790:	bd437a85 	ldr	s5, [x20, #888]
 794:	0f829084 	fmul	v4.2s, v4.2s, v2.s[0]
 798:	1e230843 	fmul	s3, s2, s3
 79c:	1e250842 	fmul	s2, s2, s5
 7a0:	fd01ba84 	str	d4, [x20, #880]
 7a4:	1e233943 	fsub	s3, s10, s3
 7a8:	bd037a82 	str	s2, [x20, #888]
 7ac:	1e230821 	fmul	s1, s1, s3
 7b0:	0f839000 	fmul	v0.2s, v0.2s, v3.s[0]
 7b4:	bd037e83 	str	s3, [x20, #892]
 7b8:	bd033281 	str	s1, [x20, #816]
 7bc:	fd001aa0 	str	d0, [x21, #48]
 7c0:	bd438682 	ldr	s2, [x20, #900]
 7c4:	910d7289 	add	x9, x20, #0x35c
 7c8:	fd41aa84 	ldr	d4, [x20, #848]
 7cc:	bd433e85 	ldr	s5, [x20, #828]
 7d0:	fd4022b0 	ldr	d16, [x21, #64]
 7d4:	1e26000a 	fmov	w10, s0
 7d8:	4ea21c43 	mov	v3.16b, v2.16b
 7dc:	4ea21c46 	mov	v6.16b, v2.16b
 7e0:	bd434e92 	ldr	s18, [x20, #844]
 7e4:	6e0c0445 	mov	v5.s[1], v2.s[0]
 7e8:	3dc0ca93 	ldr	q19, [x20, #800]
 7ec:	0f829011 	fmul	v17.2s, v0.2s, v2.s[0]
 7f0:	f9419e8b 	ldr	x11, [x20, #824]
 7f4:	0d409123 	ld1	{v3.s}[1], [x9]
 7f8:	910d6289 	add	x9, x20, #0x358
 7fc:	4d408124 	ld1	{v4.s}[2], [x9]
 800:	910d0289 	add	x9, x20, #0x340
 804:	4e0c04a7 	dup	v7.4s, v5.s[1]
 808:	0d409126 	ld1	{v6.s}[1], [x9]
 80c:	1e260029 	fmov	w9, s1
 810:	4e833863 	zip1	v3.4s, v3.4s, v3.4s
 814:	fd004ab1 	str	d17, [x21, #144]
 818:	6e1c0444 	mov	v4.s[3], v2.s[0]
 81c:	4e8738a5 	zip1	v5.4s, v5.4s, v7.4s
 820:	6e180606 	mov	v6.d[1], v16.d[0]
 824:	bd430287 	ldr	s7, [x20, #768]
 828:	fd4002b0 	ldr	d16, [x21]
 82c:	aa0a8129 	orr	x9, x9, x10, lsl #32
 830:	6e140443 	mov	v3.s[2], v2.s[0]
 834:	6e23dc83 	fmul	v3.4s, v4.4s, v3.4s
 838:	1e220824 	fmul	s4, s1, s2
 83c:	1e320842 	fmul	s2, s2, s18
 840:	4e33d472 	fadd	v18.4s, v3.4s, v19.4s
 844:	1e272887 	fadd	s7, s4, s7
 848:	bd039284 	str	s4, [x20, #912]
 84c:	6e26dca4 	fmul	v4.4s, v5.4s, v6.4s
 850:	0e30d625 	fadd	v5.2s, v17.2s, v16.2s
 854:	bd431e93 	ldr	s19, [x20, #796]
 858:	bd430e86 	ldr	s6, [x20, #780]
 85c:	bd03ae82 	str	s2, [x20, #940]
 860:	1e222a62 	fadd	s2, s19, s2
 864:	3d80ee83 	str	q3, [x20, #944]
 868:	4ea0ea50 	fcmlt	v16.4s, v18.4s, #0.0
 86c:	bd030287 	str	s7, [x20, #768]
 870:	fd0002a5 	str	d5, [x21]
 874:	1e262885 	fadd	s5, s4, s6
 878:	3c8982a4 	stur	q4, [x21, #152]
 87c:	bd031e82 	str	s2, [x20, #796]
 880:	4e701e41 	bic	v1.16b, v18.16b, v16.16b
 884:	bd030e85 	str	s5, [x20, #780]
 888:	3d80ca81 	str	q1, [x20, #800]
 88c:	a9012d09 	stp	x9, x11, [x8, #16]
 890:	f940a288 	ldr	x8, [x20, #320]
 894:	f2400d1f 	tst	x8, #0xf
 898:	54002ae1 	b.ne	df4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>  // b.any
 89c:	f9400349 	ldr	x9, [x26]
 8a0:	f941828a 	ldr	x10, [x20, #768]
 8a4:	927c6d08 	and	x8, x8, #0xfffffff0
 8a8:	f941868b 	ldr	x11, [x20, #776]
 8ac:	8b080128 	add	x8, x9, x8
 8b0:	a9002d0a 	stp	x10, x11, [x8]
 8b4:	f940a288 	ldr	x8, [x20, #320]
 8b8:	f2400d1f 	tst	x8, #0xf
 8bc:	540029c1 	b.ne	df4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>  // b.any
 8c0:	f9400349 	ldr	x9, [x26]
 8c4:	f9418a8a 	ldr	x10, [x20, #784]
 8c8:	927c6d08 	and	x8, x8, #0xfffffff0
 8cc:	f9418e8b 	ldr	x11, [x20, #792]
 8d0:	8b080128 	add	x8, x9, x8
 8d4:	a9012d0a 	stp	x10, x11, [x8, #16]
 8d8:	f940a288 	ldr	x8, [x20, #320]
 8dc:	f2400d1f 	tst	x8, #0xf
 8e0:	540028a1 	b.ne	df4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdf4>  // b.any
 8e4:	f9400349 	ldr	x9, [x26]
 8e8:	f941928a 	ldr	x10, [x20, #800]
 8ec:	927c6d08 	and	x8, x8, #0xfffffff0
 8f0:	f941968b 	ldr	x11, [x20, #808]
 8f4:	8b080128 	add	x8, x9, x8
 8f8:	a9022d0a 	stp	x10, x11, [x8, #32]
 8fc:	f940a289 	ldr	x9, [x20, #320]
 900:	f940034a 	ldr	x10, [x26]
 904:	f9408a88 	ldr	x8, [x20, #272]
 908:	8b29414b 	add	x11, x10, w9, uxtw
 90c:	f9001a88 	str	x8, [x20, #48]
 910:	f9002289 	str	x9, [x20, #64]
 914:	b9401169 	ldr	w9, [x11, #16]
 918:	b9020289 	str	w9, [x20, #512]
 91c:	b940156c 	ldr	w12, [x11, #20]
 920:	b902068c 	str	w12, [x20, #516]
 924:	b940196b 	ldr	w11, [x11, #24]
 928:	b9020e8b 	str	w11, [x20, #524]
 92c:	b8284949 	str	w9, [x10, w8, uxtw]
 930:	f9400348 	ldr	x8, [x26]
 934:	b9403289 	ldr	w9, [x20, #48]
 938:	b942068a 	ldr	w10, [x20, #516]
 93c:	8b090108 	add	x8, x8, x9
 940:	b900050a 	str	w10, [x8, #4]
 944:	f9400348 	ldr	x8, [x26]
 948:	b9403289 	ldr	w9, [x20, #48]
 94c:	b9420e8a 	ldr	w10, [x20, #524]
 950:	8b090108 	add	x8, x8, x9
 954:	b900090a 	str	w10, [x8, #8]
 958:	bd420e80 	ldr	s0, [x20, #524]
 95c:	bd420681 	ldr	s1, [x20, #516]
 960:	bd420283 	ldr	s3, [x20, #512]
 964:	f9400348 	ldr	x8, [x26]
 968:	b9403289 	ldr	w9, [x20, #48]
 96c:	1e200800 	fmul	s0, s0, s0
 970:	1e210821 	fmul	s1, s1, s1
 974:	1e230863 	fmul	s3, s3, s3
 978:	8b090108 	add	x8, x8, x9
 97c:	1e203942 	fsub	s2, s10, s0
 980:	bd020e80 	str	s0, [x20, #524]
 984:	1e213841 	fsub	s1, s2, s1
 988:	bd020a82 	str	s2, [x20, #520]
 98c:	7ea3d423 	fabd	s3, s1, s3
 990:	bd020681 	str	s1, [x20, #516]
 994:	1e21c063 	fsqrt	s3, s3
 998:	bd020283 	str	s3, [x20, #512]
 99c:	bd000d03 	str	s3, [x8, #12]
 9a0:	b9820288 	ldrsw	x8, [x20, #512]
 9a4:	f9400389 	ldr	x9, [x28]
 9a8:	f9400345 	ldr	x5, [x26]
 9ac:	f9002288 	str	x8, [x20, #64]
 9b0:	b9400128 	ldr	w8, [x9]
 9b4:	93407d09 	sxtw	x9, w8
 9b8:	f9001a89 	str	x9, [x20, #48]
 9bc:	b86868a8 	ldr	w8, [x5, x8]
 9c0:	92401d09 	and	x9, x8, #0xff
 9c4:	b9020288 	str	w8, [x20, #512]
 9c8:	d1002928 	sub	x8, x9, #0xa
 9cc:	7100293f 	cmp	w9, #0xa
 9d0:	f9001a88 	str	x8, [x20, #48]
 9d4:	540003c3 	b.cc	a4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xa4c>  // b.lo, b.ul, b.last
 9d8:	f9400788 	ldr	x8, [x28, #8]
 9dc:	f9408a89 	ldr	x9, [x20, #272]
 9e0:	f940aa8a 	ldr	x10, [x20, #336]
 9e4:	b981f28b 	ldrsw	x11, [x20, #496]
 9e8:	b9800108 	ldrsw	x8, [x8]
 9ec:	f9002289 	str	x9, [x20, #64]
 9f0:	9101414a 	add	x10, x10, #0x50
 9f4:	f9002a89 	str	x9, [x20, #80]
 9f8:	a901a7e9 	stp	x9, x9, [sp, #24]
 9fc:	f9403a89 	ldr	x9, [x20, #112]
 a00:	f900128b 	str	x11, [x20, #32]
 a04:	f940428b 	ldr	x11, [x20, #128]
 a08:	a902a7ea 	stp	x10, x9, [sp, #40]
 a0c:	f9404a89 	ldr	x9, [x20, #144]
 a10:	f900328a 	str	x10, [x20, #96]
 a14:	f940528a 	ldr	x10, [x20, #160]
 a18:	a903a7eb 	stp	x11, x9, [sp, #56]
 a1c:	f9405a89 	ldr	x9, [x20, #176]
 a20:	f900ca88 	str	x8, [x20, #400]
 a24:	a904a7ea 	stp	x10, x9, [sp, #72]
 a28:	34001da8 	cbz	w8, ddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
 a2c:	f940b283 	ldr	x3, [x20, #352]
 a30:	f940ba84 	ldr	x4, [x20, #368]
 a34:	92407d08 	and	x8, x8, #0xffffffff
 a38:	8b0800a0 	add	x0, x5, x8
 a3c:	910063e1 	add	x1, sp, #0x18
 a40:	aa1f03e2 	mov	x2, xzr
 a44:	94000000 	bl	0 <_call_goal8_asm_systemv>	a44: R_AARCH64_CALL26	_call_goal8_asm_systemv
 a48:	f9001280 	str	x0, [x20, #32]
 a4c:	f9400788 	ldr	x8, [x28, #8]
 a50:	f9408a89 	ldr	x9, [x20, #272]
 a54:	f940aa8a 	ldr	x10, [x20, #336]
 a58:	b981f28b 	ldrsw	x11, [x20, #496]
 a5c:	b9800108 	ldrsw	x8, [x8]
 a60:	f9002289 	str	x9, [x20, #64]
 a64:	9101414a 	add	x10, x10, #0x50
 a68:	f9002a89 	str	x9, [x20, #80]
 a6c:	a901a7e9 	stp	x9, x9, [sp, #24]
 a70:	f9403a89 	ldr	x9, [x20, #112]
 a74:	f900128b 	str	x11, [x20, #32]
 a78:	f940428b 	ldr	x11, [x20, #128]
 a7c:	a902a7ea 	stp	x10, x9, [sp, #40]
 a80:	f9404a89 	ldr	x9, [x20, #144]
 a84:	f900328a 	str	x10, [x20, #96]
 a88:	f940528a 	ldr	x10, [x20, #160]
 a8c:	a903a7eb 	stp	x11, x9, [sp, #56]
 a90:	f9405a89 	ldr	x9, [x20, #176]
 a94:	f900ca88 	str	x8, [x20, #400]
 a98:	a904a7ea 	stp	x10, x9, [sp, #72]
 a9c:	34001a08 	cbz	w8, ddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
 aa0:	f9400345 	ldr	x5, [x26]
 aa4:	f940b283 	ldr	x3, [x20, #352]
 aa8:	92407d08 	and	x8, x8, #0xffffffff
 aac:	f940ba84 	ldr	x4, [x20, #368]
 ab0:	8b0800a0 	add	x0, x5, x8
 ab4:	910063e1 	add	x1, sp, #0x18
 ab8:	aa1f03e2 	mov	x2, xzr
 abc:	94000000 	bl	0 <_call_goal8_asm_systemv>	abc: R_AARCH64_CALL26	_call_goal8_asm_systemv
 ac0:	f9408a89 	ldr	x9, [x20, #272]
 ac4:	f940034b 	ldr	x11, [x26]
 ac8:	f940a28a 	ldr	x10, [x20, #320]
 acc:	f9001280 	str	x0, [x20, #32]
 ad0:	8b294168 	add	x8, x11, w9, uxtw
 ad4:	f900228a 	str	x10, [x20, #64]
 ad8:	f9001a89 	str	x9, [x20, #48]
 adc:	b9400d0c 	ldr	w12, [x8, #12]
 ae0:	b902069f 	str	wzr, [x20, #516]
 ae4:	1e270180 	fmov	s0, w12
 ae8:	b902028c 	str	w12, [x20, #512]
 aec:	92400d4c 	and	x12, x10, #0xf
 af0:	1e202008 	fcmp	s0, #0.0
 af4:	540001e4 	b.mi	b30 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb30>  // b.first
 af8:	b50015cc 	cbnz	x12, db0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
 afc:	927c6d4a 	and	x10, x10, #0xfffffff0
 b00:	f2400d3f 	tst	x9, #0xf
 b04:	8b0a016a 	add	x10, x11, x10
 b08:	3dc00540 	ldr	q0, [x10, #16]
 b0c:	3d80a680 	str	q0, [x20, #656]
 b10:	54001501 	b.ne	db0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>  // b.any
 b14:	3dc00100 	ldr	q0, [x8]
 b18:	3d80aa80 	str	q0, [x20, #672]
 b1c:	fd415280 	ldr	d0, [x20, #672]
 b20:	bd42aa82 	ldr	s2, [x20, #680]
 b24:	0e28d401 	fadd	v1.2s, v0.2s, v8.2s
 b28:	1e292840 	fadd	s0, s2, s9
 b2c:	1400000e 	b	b64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb64>
 b30:	b500140c 	cbnz	x12, db0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>
 b34:	927c6d4a 	and	x10, x10, #0xfffffff0
 b38:	f2400d3f 	tst	x9, #0xf
 b3c:	8b0a016a 	add	x10, x11, x10
 b40:	3dc00540 	ldr	q0, [x10, #16]
 b44:	3d80a680 	str	q0, [x20, #656]
 b48:	54001341 	b.ne	db0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>  // b.any
 b4c:	3dc00100 	ldr	q0, [x8]
 b50:	3d80aa80 	str	q0, [x20, #672]
 b54:	fd415280 	ldr	d0, [x20, #672]
 b58:	bd42aa82 	ldr	s2, [x20, #680]
 b5c:	0ea0d501 	fsub	v1.2s, v8.2s, v0.2s
 b60:	1e223920 	fsub	s0, s9, s2
 b64:	0e0c3c29 	mov	w9, v1.s[1]
 b68:	91004148 	add	x8, x10, #0x10
 b6c:	1e26000a 	fmov	w10, s0
 b70:	1e26002b 	fmov	w11, s1
 b74:	b9429e8c 	ldr	w12, [x20, #668]
 b78:	fd014a81 	str	d1, [x20, #656]
 b7c:	bd029a80 	str	s0, [x20, #664]
 b80:	aa0c814a 	orr	x10, x10, x12, lsl #32
 b84:	aa098169 	orr	x9, x11, x9, lsl #32
 b88:	a9002909 	stp	x9, x10, [x8]
 b8c:	f9414e88 	ldr	x8, [x20, #664]
 b90:	f9414a89 	ldr	x9, [x20, #656]
 b94:	f9400345 	ldr	x5, [x26]
 b98:	f940aa93 	ldr	x19, [x20, #336]
 b9c:	3dc0ca80 	ldr	q0, [x20, #800]
 ba0:	a9042289 	stp	x9, x8, [x20, #64]
 ba4:	8b3340a8 	add	x8, x5, w19, uxtw
 ba8:	3d800e80 	str	q0, [x20, #48]
 bac:	b9806908 	ldrsw	x8, [x8, #104]
 bb0:	927e0109 	and	x9, x8, #0x4
 bb4:	f9002288 	str	x8, [x20, #64]
 bb8:	f9002a89 	str	x9, [x20, #80]
 bbc:	36080108 	tbz	w8, #1, bdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
 bc0:	a9432a8b 	ldp	x11, x10, [x20, #48]
 bc4:	290c2a9f 	stp	wzr, w10, [x20, #96]
 bc8:	d360fd4a 	lsr	x10, x10, #32
 bcc:	290d2a9f 	stp	wzr, w10, [x20, #104]
 bd0:	b500006b 	cbnz	x11, bdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
 bd4:	f940328a 	ldr	x10, [x20, #96]
 bd8:	b40003aa 	cbz	x10, c4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
 bdc:	92400108 	and	x8, x8, #0x1
 be0:	f9000368 	str	x8, [x27]
 be4:	b4000109 	cbz	x9, c04 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc04>
 be8:	f9401e89 	ldr	x9, [x20, #56]
 bec:	d360fd2a 	lsr	x10, x9, #32
 bf0:	29077e89 	stp	w9, wzr, [x20, #56]
 bf4:	29062a9f 	stp	wzr, w10, [x20, #48]
 bf8:	f9401a8a 	ldr	x10, [x20, #48]
 bfc:	f100055f 	cmp	x10, #0x1
 c00:	5400026b 	b.lt	c4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>  // b.tstop
 c04:	b4ffb028 	cbz	x8, 208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
 c08:	f9418288 	ldr	x8, [x20, #768]
 c0c:	f9418689 	ldr	x9, [x20, #776]
 c10:	f9418a8a 	ldr	x10, [x20, #784]
 c14:	a9032688 	stp	x8, x9, [x20, #48]
 c18:	d360fd28 	lsr	x8, x9, #32
 c1c:	29077e89 	stp	w9, wzr, [x20, #56]
 c20:	2906229f 	stp	wzr, w8, [x20, #48]
 c24:	f9418e88 	ldr	x8, [x20, #792]
 c28:	f9401a89 	ldr	x9, [x20, #48]
 c2c:	a903228a 	stp	x10, x8, [x20, #48]
 c30:	b7f800e9 	tbnz	x9, #63, c4c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc4c>
 c34:	f9401e88 	ldr	x8, [x20, #56]
 c38:	d360fd09 	lsr	x9, x8, #32
 c3c:	29077e88 	stp	w8, wzr, [x20, #56]
 c40:	2906269f 	stp	wzr, w9, [x20, #48]
 c44:	f9401a89 	ldr	x9, [x20, #48]
 c48:	b6ffae09 	tbz	x9, #63, 208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
 c4c:	f9400b88 	ldr	x8, [x28, #16]
 c50:	f940e289 	ldr	x9, [x20, #448]
 c54:	f940828a 	ldr	x10, [x20, #256]
 c58:	f940a28b 	ldr	x11, [x20, #320]
 c5c:	b981f28c 	ldrsw	x12, [x20, #496]
 c60:	b9800108 	ldrsw	x8, [x8]
 c64:	f9002289 	str	x9, [x20, #64]
 c68:	f9002a8a 	str	x10, [x20, #80]
 c6c:	a901abe9 	stp	x9, x10, [sp, #24]
 c70:	f9404289 	ldr	x9, [x20, #128]
 c74:	f9404a8a 	ldr	x10, [x20, #144]
 c78:	f9003a8b 	str	x11, [x20, #112]
 c7c:	a902aff3 	stp	x19, x11, [sp, #40]
 c80:	f940528b 	ldr	x11, [x20, #160]
 c84:	a903abe9 	stp	x9, x10, [sp, #56]
 c88:	f9405a89 	ldr	x9, [x20, #176]
 c8c:	f9003293 	str	x19, [x20, #96]
 c90:	f900ca88 	str	x8, [x20, #400]
 c94:	f900128c 	str	x12, [x20, #32]
 c98:	a904a7eb 	stp	x11, x9, [sp, #72]
 c9c:	34000a08 	cbz	w8, ddc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xddc>
 ca0:	f940b283 	ldr	x3, [x20, #352]
 ca4:	f940ba84 	ldr	x4, [x20, #368]
 ca8:	92407d08 	and	x8, x8, #0xffffffff
 cac:	8b0800a0 	add	x0, x5, x8
 cb0:	910063e1 	add	x1, sp, #0x18
 cb4:	aa1f03e2 	mov	x2, xzr
 cb8:	94000000 	bl	0 <_call_goal8_asm_systemv>	cb8: R_AARCH64_CALL26	_call_goal8_asm_systemv
 cbc:	f9001280 	str	x0, [x20, #32]
 cc0:	17fffd52 	b	208 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x208>
 cc4:	f9400348 	ldr	x8, [x26]
 cc8:	f940ea89 	ldr	x9, [x20, #464]
 ccc:	f9001297 	str	x23, [x20, #32]
 cd0:	8b29410a 	add	x10, x8, w9, uxtw
 cd4:	f940014b 	ldr	x11, [x10]
 cd8:	f900fa8b 	str	x11, [x20, #496]
 cdc:	1102412b 	add	w11, w9, #0x90
 ce0:	f940054a 	ldr	x10, [x10, #8]
 ce4:	927c6d6b 	and	x11, x11, #0xfffffff0
 ce8:	f900f28a 	str	x10, [x20, #480]
 cec:	1102012a 	add	w10, w9, #0x80
 cf0:	3ceb6900 	ldr	q0, [x8, x11]
 cf4:	927c6d4a 	and	x10, x10, #0xfffffff0
 cf8:	3d807280 	str	q0, [x20, #448]
 cfc:	3cea6900 	ldr	q0, [x8, x10]
 d00:	1101c12a 	add	w10, w9, #0x70
 d04:	927c6d4a 	and	x10, x10, #0xfffffff0
 d08:	3d805680 	str	q0, [x20, #336]
 d0c:	3cea6900 	ldr	q0, [x8, x10]
 d10:	1101812a 	add	w10, w9, #0x60
 d14:	927c6d4a 	and	x10, x10, #0xfffffff0
 d18:	3d805280 	str	q0, [x20, #320]
 d1c:	3cea6900 	ldr	q0, [x8, x10]
 d20:	1101412a 	add	w10, w9, #0x50
 d24:	927c6d4a 	and	x10, x10, #0xfffffff0
 d28:	3d804e80 	str	q0, [x20, #304]
 d2c:	3cea6900 	ldr	q0, [x8, x10]
 d30:	1101012a 	add	w10, w9, #0x40
 d34:	927c6d4a 	and	x10, x10, #0xfffffff0
 d38:	3d804a80 	str	q0, [x20, #288]
 d3c:	3cea6900 	ldr	q0, [x8, x10]
 d40:	1100c12a 	add	w10, w9, #0x30
 d44:	927c6d4a 	and	x10, x10, #0xfffffff0
 d48:	3d804680 	str	q0, [x20, #272]
 d4c:	3cea6900 	ldr	q0, [x8, x10]
 d50:	91028128 	add	x8, x9, #0xa0
 d54:	f900ea88 	str	x8, [x20, #464]
 d58:	3d804280 	str	q0, [x20, #256]
 d5c:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	d5c: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
 d60:	f9400be8 	ldr	x8, [sp, #16]
 d64:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d64: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
 d68:	f9400021 	ldr	x1, [x1]	d68: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
 d6c:	cb080000 	sub	x0, x0, x8
 d70:	94000000 	bl	0 <__aarch64_ldadd8_relax>	d70: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 d74:	f9401708 	ldr	x8, [x24, #40]
 d78:	f85d83a9 	ldur	x9, [x29, #-40]
 d7c:	eb09011f 	cmp	x8, x9
 d80:	540008c1 	b.ne	e98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>  // b.any
 d84:	aa1703e0 	mov	x0, x23
 d88:	a94d4ff4 	ldp	x20, x19, [sp, #208]
 d8c:	fd4033ea 	ldr	d10, [sp, #96]
 d90:	a94c57f6 	ldp	x22, x21, [sp, #192]
 d94:	a94b5ff8 	ldp	x24, x23, [sp, #176]
 d98:	a94a67fa 	ldp	x26, x25, [sp, #160]
 d9c:	a9496ffc 	ldp	x28, x27, [sp, #144]
 da0:	a9487bfd 	ldp	x29, x30, [sp, #128]
 da4:	6d4723e9 	ldp	d9, d8, [sp, #112]
 da8:	910383ff 	add	sp, sp, #0xe0
 dac:	d65f03c0 	ret
 db0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	db0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x275
 db4:	91000109 	add	x9, x8, #0x0	db4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x275
 db8:	52802b02 	mov	w2, #0x158                 	// #344
 dbc:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	dbc: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2dd
 dc0:	91000108 	add	x8, x8, #0x0	dc0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2dd
 dc4:	a90027e8 	stp	x8, x9, [sp]
 dc8:	f9401708 	ldr	x8, [x24, #40]
 dcc:	f85d83a9 	ldur	x9, [x29, #-40]
 dd0:	eb09011f 	cmp	x8, x9
 dd4:	54000240 	b.eq	e1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe1c>  // b.none
 dd8:	14000030 	b	e98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
 ddc:	52803202 	mov	w2, #0x190                 	// #400
 de0:	f9401708 	ldr	x8, [x24, #40]
 de4:	f85d83a9 	ldur	x9, [x29, #-40]
 de8:	eb09011f 	cmp	x8, x9
 dec:	54000180 	b.eq	e1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe1c>  // b.none
 df0:	1400002a 	b	e98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
 df4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	df4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x33f
 df8:	91000109 	add	x9, x8, #0x0	df8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x33f
 dfc:	52803802 	mov	w2, #0x1c0                 	// #448
 e00:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e00: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x366
 e04:	91000108 	add	x8, x8, #0x0	e04: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x366
 e08:	a90027e8 	stp	x8, x9, [sp]
 e0c:	f9401708 	ldr	x8, [x24, #40]
 e10:	f85d83a9 	ldur	x9, [x29, #-40]
 e14:	eb09011f 	cmp	x8, x9
 e18:	54000401 	b.ne	e98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>  // b.any
 e1c:	a94003e3 	ldp	x3, x0, [sp]
 e20:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e20: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a2
 e24:	91000021 	add	x1, x1, #0x0	e24: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a2
 e28:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e28: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x310
 e2c:	91000084 	add	x4, x4, #0x0	e2c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x310
 e30:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	e30: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
 e34:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e34: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2dd
 e38:	91000109 	add	x9, x8, #0x0	e38: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2dd
 e3c:	52802b02 	mov	w2, #0x158                 	// #344
 e40:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e40: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x275
 e44:	91000108 	add	x8, x8, #0x0	e44: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x275
 e48:	a90023e9 	stp	x9, x8, [sp]
 e4c:	f9401708 	ldr	x8, [x24, #40]
 e50:	f85d83a9 	ldur	x9, [x29, #-40]
 e54:	eb09011f 	cmp	x8, x9
 e58:	54fffe20 	b.eq	e1c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe1c>  // b.none
 e5c:	1400000f 	b	e98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>
 e60:	14000001 	b	e64 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe64>
 e64:	aa0003f4 	mov	x20, x0
 e68:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	e68: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
 e6c:	f9400be8 	ldr	x8, [sp, #16]
 e70:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e70: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
 e74:	f9400021 	ldr	x1, [x1]	e74: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
 e78:	cb080000 	sub	x0, x0, x8
 e7c:	94000000 	bl	0 <__aarch64_ldadd8_relax>	e7c: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 e80:	f9401708 	ldr	x8, [x24, #40]
 e84:	f85d83a9 	ldur	x9, [x29, #-40]
 e88:	eb09011f 	cmp	x8, x9
 e8c:	54000061 	b.ne	e98 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe98>  // b.any
 e90:	aa1403e0 	mov	x0, x20
 e94:	94000000 	bl	0 <_Unwind_Resume>	e94: R_AARCH64_CALL26	_Unwind_Resume
 e98:	94000000 	bl	0 <__stack_chk_fail>	e98: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::link()>:
   0:	d10143ff 	sub	sp, sp, #0x50
   4:	a9027bfd 	stp	x29, x30, [sp, #32]
   8:	f9001bf5 	str	x21, [sp, #48]
   c:	a9044ff4 	stp	x20, x19, [sp, #64]
  10:	910083fd 	add	x29, sp, #0x20
  14:	d53bd054 	mrs	x20, tpidr_el0
  18:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	18: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1
  1c:	91000000 	add	x0, x0, #0x0	1c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1
  20:	f9401688 	ldr	x8, [x20, #40]
  24:	f81f83a8 	stur	x8, [x29, #-8]
  28:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	28: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  2c:	90000013 	adrp	x19, 0 <g_ee_main_mem>	2c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  30:	90000015 	adrp	x21, 0 <Mips2C::jak1::sp_process_block_3d::link()>	30: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::cache
  34:	7100001f 	cmp	w0, #0x0
  38:	f9400273 	ldr	x19, [x19]	38: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  3c:	f9400268 	ldr	x8, [x19]
  40:	f94002b5 	ldr	x21, [x21]	40: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
  44:	8b204108 	add	x8, x8, w0, uxtw
  48:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	48: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x10
  4c:	91000000 	add	x0, x0, #0x0	4c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x10
  50:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  54:	f90002a8 	str	x8, [x21]
  58:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	58: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  5c:	f9400268 	ldr	x8, [x19]
  60:	7100001f 	cmp	w0, #0x0
  64:	8b204108 	add	x8, x8, w0, uxtw
  68:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	68: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x1d
  6c:	91000000 	add	x0, x0, #0x0	6c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x1d
  70:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  74:	f90006a8 	str	x8, [x21, #8]
  78:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	78: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  7c:	f9400268 	ldr	x8, [x19]
  80:	7100001f 	cmp	w0, #0x0
  84:	8b204108 	add	x8, x8, w0, uxtw
  88:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	88: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2e
  8c:	91000000 	add	x0, x0, #0x0	8c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2e
  90:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  94:	f9000aa8 	str	x8, [x21, #16]
  98:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	98: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  9c:	f9400268 	ldr	x8, [x19]
  a0:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_3d::link()>	a0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x46
  a4:	9100016b 	add	x11, x11, #0x0	a4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x46
  a8:	5285ad6a 	mov	w10, #0x2d6b                	// #11627
  ac:	3dc00160 	ldr	q0, [x11]
  b0:	7100001f 	cmp	w0, #0x0
  b4:	8b204108 	add	x8, x8, w0, uxtw
  b8:	528004c9 	mov	w9, #0x26                  	// #38
  bc:	72ac866a 	movk	w10, #0x6433, lsl #16
  c0:	390003e9 	strb	w9, [sp]
  c4:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  c8:	b90013ea 	str	w10, [sp, #16]
  cc:	3c8013e0 	stur	q0, [sp, #1]
  d0:	f9000ea8 	str	x8, [x21, #24]
  d4:	390053ff 	strb	wzr, [sp, #20]
  d8:	90000000 	adrp	x0, 0 <Mips2C::gLinkedFunctionTable>	d8: R_AARCH64_ADR_GOT_PAGE	Mips2C::gLinkedFunctionTable
  dc:	90000002 	adrp	x2, 0 <Mips2C::jak1::sp_process_block_3d::link()>	dc: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_3d::execute(void*)
  e0:	910003e1 	mov	x1, sp
  e4:	f9400000 	ldr	x0, [x0]	e4: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::gLinkedFunctionTable
  e8:	f9400042 	ldr	x2, [x2]	e8: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_3d::execute(void*)
  ec:	52802003 	mov	w3, #0x100                 	// #256
  f0:	94000000 	bl	0 <Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)>	f0: R_AARCH64_CALL26	Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)
  f4:	394003e8 	ldrb	w8, [sp]
  f8:	36000068 	tbz	w8, #0, 104 <Mips2C::jak1::sp_process_block_3d::link()+0x104>
  fc:	f9400be0 	ldr	x0, [sp, #16]
 100:	94000000 	bl	0 <operator delete(void*)>	100: R_AARCH64_CALL26	operator delete(void*)
 104:	f9401688 	ldr	x8, [x20, #40]
 108:	f85f83a9 	ldur	x9, [x29, #-8]
 10c:	eb09011f 	cmp	x8, x9
 110:	54000221 	b.ne	154 <Mips2C::jak1::sp_process_block_3d::link()+0x154>  // b.any
 114:	a9444ff4 	ldp	x20, x19, [sp, #64]
 118:	f9401bf5 	ldr	x21, [sp, #48]
 11c:	a9427bfd 	ldp	x29, x30, [sp, #32]
 120:	910143ff 	add	sp, sp, #0x50
 124:	d65f03c0 	ret
 128:	394003e8 	ldrb	w8, [sp]
 12c:	aa0003f3 	mov	x19, x0
 130:	36000068 	tbz	w8, #0, 13c <Mips2C::jak1::sp_process_block_3d::link()+0x13c>
 134:	f9400be0 	ldr	x0, [sp, #16]
 138:	94000000 	bl	0 <operator delete(void*)>	138: R_AARCH64_CALL26	operator delete(void*)
 13c:	f9401688 	ldr	x8, [x20, #40]
 140:	f85f83a9 	ldur	x9, [x29, #-8]
 144:	eb09011f 	cmp	x8, x9
 148:	54000061 	b.ne	154 <Mips2C::jak1::sp_process_block_3d::link()+0x154>  // b.any
 14c:	aa1303e0 	mov	x0, x19
 150:	94000000 	bl	0 <_Unwind_Resume>	150: R_AARCH64_CALL26	_Unwind_Resume
 154:	94000000 	bl	0 <__stack_chk_fail>	154: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::execute(void*)>:
       0:	d10543ff 	sub	sp, sp, #0x150
       4:	fd006bea 	str	d10, [sp, #208]
       8:	6d0e23e9 	stp	d9, d8, [sp, #224]
       c:	a90f7bfd 	stp	x29, x30, [sp, #240]
      10:	a9106ffc 	stp	x28, x27, [sp, #256]
      14:	a91167fa 	stp	x26, x25, [sp, #272]
      18:	a9125ff8 	stp	x24, x23, [sp, #288]
      1c:	a91357f6 	stp	x22, x21, [sp, #304]
      20:	a9144ff4 	stp	x20, x19, [sp, #320]
      24:	9103c3fd 	add	x29, sp, #0xf0
      28:	d53bd048 	mrs	x8, tpidr_el0
      2c:	aa0003f4 	mov	x20, x0
      30:	f9003fe8 	str	x8, [sp, #120]
      34:	f9401508 	ldr	x8, [x8, #40]
      38:	f81d03a8 	stur	x8, [x29, #-48]
      3c:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	3c: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
      40:	f9003be0 	str	x0, [sp, #112]
      44:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	44: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
      48:	52800020 	mov	w0, #0x1                   	// #1
      4c:	f9400108 	ldr	x8, [x8]	4c: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
      50:	9100a101 	add	x1, x8, #0x28
      54:	94000000 	bl	0 <__aarch64_ldadd8_relax>	54: R_AARCH64_CALL26	__aarch64_ldadd8_relax
      58:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	58: R_AARCH64_ADR_GOT_PAGE	g_perf_2dvec_off
      5c:	9000001b 	adrp	x27, 0 <g_ee_main_mem>	5c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
      60:	aa1403f6 	mov	x22, x20
      64:	f9400108 	ldr	x8, [x8]	64: R_AARCH64_LD64_GOT_LO12_NC	g_perf_2dvec_off
      68:	f940037b 	ldr	x27, [x27]	68: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
      6c:	39400113 	ldrb	w19, [x8]
      70:	f940ea88 	ldr	x8, [x20, #464]
      74:	f9400369 	ldr	x9, [x27]
      78:	f940fa8a 	ldr	x10, [x20, #496]
      7c:	d1020108 	sub	x8, x8, #0x80
      80:	f900ea88 	str	x8, [x20, #464]
      84:	f828492a 	str	x10, [x9, w8, uxtw]
      88:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	88: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
      8c:	b941d288 	ldr	w8, [x20, #464]
      90:	f9400369 	ldr	x9, [x27]
      94:	3dc04280 	ldr	q0, [x20, #256]
      98:	11004108 	add	w8, w8, #0x10
      9c:	927c6d08 	and	x8, x8, #0xfffffff0
      a0:	3ca86920 	str	q0, [x9, x8]
      a4:	b941d288 	ldr	w8, [x20, #464]
      a8:	f9400369 	ldr	x9, [x27]
      ac:	3dc04680 	ldr	q0, [x20, #272]
      b0:	11008108 	add	w8, w8, #0x20
      b4:	927c6d08 	and	x8, x8, #0xfffffff0
      b8:	3ca86920 	str	q0, [x9, x8]
      bc:	b941d288 	ldr	w8, [x20, #464]
      c0:	f9400369 	ldr	x9, [x27]
      c4:	3dc04a80 	ldr	q0, [x20, #288]
      c8:	1100c108 	add	w8, w8, #0x30
      cc:	927c6d08 	and	x8, x8, #0xfffffff0
      d0:	3ca86920 	str	q0, [x9, x8]
      d4:	b941d288 	ldr	w8, [x20, #464]
      d8:	f9400369 	ldr	x9, [x27]
      dc:	3dc04e80 	ldr	q0, [x20, #304]
      e0:	11010108 	add	w8, w8, #0x40
      e4:	927c6d08 	and	x8, x8, #0xfffffff0
      e8:	3ca86920 	str	q0, [x9, x8]
      ec:	b941d288 	ldr	w8, [x20, #464]
      f0:	f9400369 	ldr	x9, [x27]
      f4:	3dc05280 	ldr	q0, [x20, #320]
      f8:	11014108 	add	w8, w8, #0x50
      fc:	927c6d08 	and	x8, x8, #0xfffffff0
     100:	3ca86920 	str	q0, [x9, x8]
     104:	b941d288 	ldr	w8, [x20, #464]
     108:	f9400369 	ldr	x9, [x27]
     10c:	3dc05680 	ldr	q0, [x20, #336]
     110:	11018108 	add	w8, w8, #0x60
     114:	927c6d08 	and	x8, x8, #0xfffffff0
     118:	3ca86920 	str	q0, [x9, x8]
     11c:	b941d288 	ldr	w8, [x20, #464]
     120:	f9400369 	ldr	x9, [x27]
     124:	3dc07280 	ldr	q0, [x20, #448]
     128:	1101c108 	add	w8, w8, #0x70
     12c:	927c6d08 	and	x8, x8, #0xfffffff0
     130:	3ca86920 	str	q0, [x9, x8]
     134:	f9402288 	ldr	x8, [x20, #64]
     138:	f940014a 	ldr	x10, [x10]	138: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     13c:	f9402a89 	ldr	x9, [x20, #80]
     140:	f900e288 	str	x8, [x20, #448]
     144:	f9403288 	ldr	x8, [x20, #96]
     148:	f900aa89 	str	x9, [x20, #336]
     14c:	f9403a89 	ldr	x9, [x20, #112]
     150:	f900a288 	str	x8, [x20, #320]
     154:	f9404288 	ldr	x8, [x20, #128]
     158:	f9008a89 	str	x9, [x20, #272]
     15c:	f9404a89 	ldr	x9, [x20, #144]
     160:	f9009a88 	str	x8, [x20, #304]
     164:	f9400148 	ldr	x8, [x10]
     168:	f9009289 	str	x9, [x20, #288]
     16c:	b9800108 	ldrsw	x8, [x8]
     170:	72000d1f 	tst	w8, #0xf
     174:	f8030ec8 	str	x8, [x22, #48]!
     178:	54008941 	b.ne	12a0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x12a0>  // b.any
     17c:	f9400369 	ldr	x9, [x27]
     180:	927c6d08 	and	x8, x8, #0xfffffff0
     184:	2f00e409 	movi	d9, #0x0
     188:	1e2e1008 	fmov	s8, #1.000000000000000000e+00
     18c:	1e3e100a 	fmov	s10, #-1.000000000000000000e+00
     190:	f940aa9a 	ldr	x26, [x20, #336]
     194:	3ce86920 	ldr	q0, [x9, x8]
     198:	910992d9 	add	x25, x22, #0x264
     19c:	91048298 	add	x24, x20, #0x120
     1a0:	9105029c 	add	x28, x20, #0x140
     1a4:	91054297 	add	x23, x20, #0x150
     1a8:	3d80c680 	str	q0, [x20, #784]
     1ac:	b9431288 	ldr	w8, [x20, #784]
     1b0:	b9431689 	ldr	w9, [x20, #788]
     1b4:	f9418e8a 	ldr	x10, [x20, #792]
     1b8:	92401d0b 	and	x11, x8, #0xff
     1bc:	aa098108 	orr	x8, x8, x9, lsl #32
     1c0:	f900828b 	str	x11, [x20, #256]
     1c4:	a9032a88 	stp	x8, x10, [x20, #48]
     1c8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1c8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x316
     1cc:	91000109 	add	x9, x8, #0x0	1cc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x316
     1d0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1d0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x311
     1d4:	91000108 	add	x8, x8, #0x0	1d4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x311
     1d8:	a90623e9 	stp	x9, x8, [sp, #96]
     1dc:	1400000e 	b	214 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x214>
     1e0:	f9409a88 	ldr	x8, [x20, #304]
     1e4:	f94002e9 	ldr	x9, [x23]
     1e8:	f940038a 	ldr	x10, [x28]
     1ec:	f9408a8b 	ldr	x11, [x20, #272]
     1f0:	f1000508 	subs	x8, x8, #0x1
     1f4:	9102413a 	add	x26, x9, #0x90
     1f8:	f9009a88 	str	x8, [x20, #304]
     1fc:	9100c148 	add	x8, x10, #0x30
     200:	91000575 	add	x21, x11, #0x1
     204:	f90002fa 	str	x26, [x23]
     208:	f9000388 	str	x8, [x28]
     20c:	f9008a95 	str	x21, [x20, #272]
     210:	540078c0 	b.eq	1128 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1128>  // b.none
     214:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	214: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
     218:	52800020 	mov	w0, #0x1                   	// #1
     21c:	f9400108 	ldr	x8, [x8]	21c: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
     220:	91012101 	add	x1, x8, #0x48
     224:	94000000 	bl	0 <__aarch64_ldadd8_relax>	224: R_AARCH64_CALL26	__aarch64_ldadd8_relax
     228:	f9400365 	ldr	x5, [x27]
     22c:	92407f49 	and	x9, x26, #0xffffffff
     230:	b941728b 	ldr	w11, [x20, #368]
     234:	8b0900a8 	add	x8, x5, x9
     238:	b980810a 	ldrsw	x10, [x8, #128]
     23c:	6b0b015f 	cmp	w10, w11
     240:	f9001a8a 	str	x10, [x20, #48]
     244:	54fffce0 	b.eq	1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>  // b.none
     248:	b940030c 	ldr	w12, [x24]
     24c:	b980690a 	ldrsw	x10, [x8, #104]
     250:	6b0b019f 	cmp	w12, w11
     254:	f90002ca 	str	x10, [x22]
     258:	54000320 	b.eq	2bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2bc>  // b.none
     25c:	9273014b 	and	x11, x10, #0x2000
     260:	f90002cb 	str	x11, [x22]
     264:	376802ca 	tbnz	w10, #13, 2bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2bc>
     268:	b9806509 	ldrsw	x9, [x8, #100]
     26c:	9280000a 	mov	x10, #0xffffffffffffffff    	// #-1
     270:	f900228a 	str	x10, [x20, #64]
     274:	f9001a89 	str	x9, [x20, #48]
     278:	34007189 	cbz	w9, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
     27c:	b9806909 	ldrsw	x9, [x8, #104]
     280:	927a012a 	and	x10, x9, #0x40
     284:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
     288:	f9001a8a 	str	x10, [x20, #48]
     28c:	f900228b 	str	x11, [x20, #64]
     290:	b900690b 	str	w11, [x8, #104]
     294:	3637fa69 	tbz	w9, #6, 1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
     298:	f9400368 	ldr	x8, [x27]
     29c:	b94002e9 	ldr	w9, [x23]
     2a0:	b940038a 	ldr	w10, [x28]
     2a4:	8b090109 	add	x9, x8, x9
     2a8:	8b0a0108 	add	x8, x8, x10
     2ac:	b9807d29 	ldrsw	x9, [x9, #124]
     2b0:	f90002c9 	str	x9, [x22]
     2b4:	b9002d09 	str	w9, [x8, #44]
     2b8:	17ffffca 	b	1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
     2bc:	b980650a 	ldrsw	x10, [x8, #100]
     2c0:	f940828b 	ldr	x11, [x20, #256]
     2c4:	cb0b014b 	sub	x11, x10, x11
     2c8:	3100055f 	cmn	w10, #0x1
     2cc:	f9001a8a 	str	x10, [x20, #48]
     2d0:	f900228b 	str	x11, [x20, #64]
     2d4:	54000200 	b.eq	314 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x314>  // b.none
     2d8:	1e270160 	fmov	s0, w11
     2dc:	d360fd69 	lsr	x9, x11, #32
     2e0:	6f00e401 	movi	v1.2d, #0x0
     2e4:	4e0c1d20 	mov	v0.s[1], w9
     2e8:	91012289 	add	x9, x20, #0x48
     2ec:	4d408120 	ld1	{v0.s}[2], [x9]
     2f0:	91013289 	add	x9, x20, #0x4c
     2f4:	4d409120 	ld1	{v0.s}[3], [x9]
     2f8:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
     2fc:	3d800e80 	str	q0, [x20, #48]
     300:	34006d4a 	cbz	w10, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
     304:	f94002c9 	ldr	x9, [x22]
     308:	b9006509 	str	w9, [x8, #100]
     30c:	f9400365 	ldr	x5, [x27]
     310:	b94002e9 	ldr	w9, [x23]
     314:	8b0900a8 	add	x8, x5, x9
     318:	b9806909 	ldrsw	x9, [x8, #104]
     31c:	927a012a 	and	x10, x9, #0x40
     320:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
     324:	f9001a8a 	str	x10, [x20, #48]
     328:	f900228b 	str	x11, [x20, #64]
     32c:	b900690b 	str	w11, [x8, #104]
     330:	36300129 	tbz	w9, #6, 354 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x354>
     334:	f9400368 	ldr	x8, [x27]
     338:	b94002e9 	ldr	w9, [x23]
     33c:	b940038a 	ldr	w10, [x28]
     340:	8b090109 	add	x9, x8, x9
     344:	8b0a0108 	add	x8, x8, x10
     348:	b9807d29 	ldrsw	x9, [x9, #124]
     34c:	f90002c9 	str	x9, [x22]
     350:	b9002d09 	str	w9, [x8, #44]
     354:	f9400368 	ldr	x8, [x27]
     358:	b9415281 	ldr	w1, [x20, #336]
     35c:	8b010109 	add	x9, x8, x1
     360:	b9807129 	ldrsw	x9, [x9, #112]
     364:	f900ca89 	str	x9, [x20, #400]
     368:	34000d69 	cbz	w9, 514 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x514>
     36c:	f940ea89 	ldr	x9, [x20, #464]
     370:	3dc07280 	ldr	q0, [x20, #448]
     374:	d1014129 	sub	x9, x9, #0x50
     378:	f900ea89 	str	x9, [x20, #464]
     37c:	927c6d29 	and	x9, x9, #0xfffffff0
     380:	3ca96900 	str	q0, [x8, x9]
     384:	b941d288 	ldr	w8, [x20, #464]
     388:	f9400369 	ldr	x9, [x27]
     38c:	3dc05680 	ldr	q0, [x20, #336]
     390:	11004108 	add	w8, w8, #0x10
     394:	927c6d08 	and	x8, x8, #0xfffffff0
     398:	3ca86920 	str	q0, [x9, x8]
     39c:	b941d288 	ldr	w8, [x20, #464]
     3a0:	f9400369 	ldr	x9, [x27]
     3a4:	3dc05280 	ldr	q0, [x20, #320]
     3a8:	11008108 	add	w8, w8, #0x20
     3ac:	927c6d08 	and	x8, x8, #0xfffffff0
     3b0:	3ca86920 	str	q0, [x9, x8]
     3b4:	b941d288 	ldr	w8, [x20, #464]
     3b8:	f9400369 	ldr	x9, [x27]
     3bc:	3dc04680 	ldr	q0, [x20, #272]
     3c0:	1100c108 	add	w8, w8, #0x30
     3c4:	927c6d08 	and	x8, x8, #0xfffffff0
     3c8:	3ca86920 	str	q0, [x9, x8]
     3cc:	f940e288 	ldr	x8, [x20, #448]
     3d0:	b941d28a 	ldr	w10, [x20, #464]
     3d4:	f940aa89 	ldr	x9, [x20, #336]
     3d8:	f940a28b 	ldr	x11, [x20, #320]
     3dc:	f940036c 	ldr	x12, [x27]
     3e0:	3dc04e80 	ldr	q0, [x20, #304]
     3e4:	f9002288 	str	x8, [x20, #64]
     3e8:	11010148 	add	w8, w10, #0x40
     3ec:	f9002a89 	str	x9, [x20, #80]
     3f0:	927c6d09 	and	x9, x8, #0xfffffff0
     3f4:	b9419288 	ldr	w8, [x20, #400]
     3f8:	f900328b 	str	x11, [x20, #96]
     3fc:	3ca96980 	str	q0, [x12, x9]
     400:	f9402289 	ldr	x9, [x20, #64]
     404:	f9402a8a 	ldr	x10, [x20, #80]
     408:	f940328b 	ldr	x11, [x20, #96]
     40c:	a9392ba9 	stp	x9, x10, [x29, #-112]
     410:	f9403a89 	ldr	x9, [x20, #112]
     414:	f940428a 	ldr	x10, [x20, #128]
     418:	a93a27ab 	stp	x11, x9, [x29, #-96]
     41c:	f9404a8b 	ldr	x11, [x20, #144]
     420:	f9405289 	ldr	x9, [x20, #160]
     424:	a93b2faa 	stp	x10, x11, [x29, #-80]
     428:	f9405a8a 	ldr	x10, [x20, #176]
     42c:	a93c2ba9 	stp	x9, x10, [x29, #-64]
     430:	34006f08 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
     434:	f9400365 	ldr	x5, [x27]
     438:	f940b283 	ldr	x3, [x20, #352]
     43c:	f940ba84 	ldr	x4, [x20, #368]
     440:	8b0800a0 	add	x0, x5, x8
     444:	d101c3a1 	sub	x1, x29, #0x70
     448:	aa1f03e2 	mov	x2, xzr
     44c:	94000000 	bl	0 <_call_goal8_asm_systemv>	44c: R_AARCH64_CALL26	_call_goal8_asm_systemv
     450:	f940ea88 	ldr	x8, [x20, #464]
     454:	f9400369 	ldr	x9, [x27]
     458:	f9001280 	str	x0, [x20, #32]
     45c:	927c6d0a 	and	x10, x8, #0xfffffff0
     460:	3cea6920 	ldr	q0, [x9, x10]
     464:	1100410a 	add	w10, w8, #0x10
     468:	927c6d4a 	and	x10, x10, #0xfffffff0
     46c:	3d807280 	str	q0, [x20, #448]
     470:	3cea6920 	ldr	q0, [x9, x10]
     474:	1100810a 	add	w10, w8, #0x20
     478:	927c6d4a 	and	x10, x10, #0xfffffff0
     47c:	3d8002e0 	str	q0, [x23]
     480:	3cea6920 	ldr	q0, [x9, x10]
     484:	1100c10a 	add	w10, w8, #0x30
     488:	927c6d4a 	and	x10, x10, #0xfffffff0
     48c:	3d800380 	str	q0, [x28]
     490:	3cea6920 	ldr	q0, [x9, x10]
     494:	1101010a 	add	w10, w8, #0x40
     498:	91014108 	add	x8, x8, #0x50
     49c:	927c6d4a 	and	x10, x10, #0xfffffff0
     4a0:	3d804680 	str	q0, [x20, #272]
     4a4:	3cea6920 	ldr	q0, [x9, x10]
     4a8:	f900ea88 	str	x8, [x20, #464]
     4ac:	3d804e80 	str	q0, [x20, #304]
     4b0:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	4b0: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     4b4:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	4b4: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals
     4b8:	5283e808 	mov	w8, #0x1f40                	// #8000
     4bc:	b94002e1 	ldr	w1, [x23]
     4c0:	b9400169 	ldr	w9, [x11]	4c0: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals
     4c4:	6b08013f 	cmp	w9, w8
     4c8:	1a9fa7e8 	cset	w8, lt	// lt = tstop
     4cc:	0a08000a 	and	w10, w0, w8
     4d0:	f9400368 	ldr	x8, [x27]
     4d4:	7100055f 	cmp	w10, #0x1
     4d8:	540001e1 	b.ne	514 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x514>  // b.any
     4dc:	11000529 	add	w9, w9, #0x1
     4e0:	8b010108 	add	x8, x8, x1
     4e4:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	4e4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x5a
     4e8:	91000000 	add	x0, x0, #0x0	4e8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x5a
     4ec:	b9000169 	str	w9, [x11]	4ec: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals
     4f0:	294e0d02 	ldp	w2, w3, [x8, #112]
     4f4:	b9407904 	ldr	w4, [x8, #120]
     4f8:	94000000 	bl	0 <printf>	4f8: R_AARCH64_CALL26	printf
     4fc:	90000008 	adrp	x8, 0 <stdout>	4fc: R_AARCH64_ADR_GOT_PAGE	stdout
     500:	f9400108 	ldr	x8, [x8]	500: R_AARCH64_LD64_GOT_LO12_NC	stdout
     504:	f9400100 	ldr	x0, [x8]
     508:	94000000 	bl	0 <fflush>	508: R_AARCH64_CALL26	fflush
     50c:	f9400368 	ldr	x8, [x27]
     510:	b94002e1 	ldr	w1, [x23]
     514:	8b010108 	add	x8, x8, x1
     518:	f940828b 	ldr	x11, [x20, #256]
     51c:	b980790a 	ldrsw	x10, [x8, #120]
     520:	f9002a8a 	str	x10, [x20, #80]
     524:	b9807509 	ldrsw	x9, [x8, #116]
     528:	f9001a89 	str	x9, [x20, #48]
     52c:	cb0b0129 	sub	x9, x9, x11
     530:	f9002289 	str	x9, [x20, #64]
     534:	3400154a 	cbz	w10, 7dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x7dc>
     538:	f100052a 	subs	x10, x9, #0x1
     53c:	f90002ca 	str	x10, [x22]
     540:	b9007509 	str	w9, [x8, #116]
     544:	540014c5 	b.pl	7dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x7dc>  // b.nfrst
     548:	f940ea88 	ldr	x8, [x20, #464]
     54c:	f9400369 	ldr	x9, [x27]
     550:	3dc07280 	ldr	q0, [x20, #448]
     554:	d1018108 	sub	x8, x8, #0x60
     558:	f900ea88 	str	x8, [x20, #464]
     55c:	927c6d08 	and	x8, x8, #0xfffffff0
     560:	3ca86920 	str	q0, [x9, x8]
     564:	b941d288 	ldr	w8, [x20, #464]
     568:	f9400369 	ldr	x9, [x27]
     56c:	3dc05680 	ldr	q0, [x20, #336]
     570:	11004108 	add	w8, w8, #0x10
     574:	927c6d08 	and	x8, x8, #0xfffffff0
     578:	3ca86920 	str	q0, [x9, x8]
     57c:	b941d288 	ldr	w8, [x20, #464]
     580:	f9400369 	ldr	x9, [x27]
     584:	3dc05280 	ldr	q0, [x20, #320]
     588:	11008108 	add	w8, w8, #0x20
     58c:	927c6d08 	and	x8, x8, #0xfffffff0
     590:	3ca86920 	str	q0, [x9, x8]
     594:	b941d288 	ldr	w8, [x20, #464]
     598:	f9400369 	ldr	x9, [x27]
     59c:	3dc04680 	ldr	q0, [x20, #272]
     5a0:	1100c108 	add	w8, w8, #0x30
     5a4:	927c6d08 	and	x8, x8, #0xfffffff0
     5a8:	3ca86920 	str	q0, [x9, x8]
     5ac:	b941d288 	ldr	w8, [x20, #464]
     5b0:	f9400369 	ldr	x9, [x27]
     5b4:	3dc04e80 	ldr	q0, [x20, #304]
     5b8:	11010108 	add	w8, w8, #0x40
     5bc:	927c6d08 	and	x8, x8, #0xfffffff0
     5c0:	3ca86920 	str	q0, [x9, x8]
     5c4:	b941d288 	ldr	w8, [x20, #464]
     5c8:	f9400369 	ldr	x9, [x27]
     5cc:	3dc04a80 	ldr	q0, [x20, #288]
     5d0:	11014108 	add	w8, w8, #0x50
     5d4:	927c6d08 	and	x8, x8, #0xfffffff0
     5d8:	3ca86920 	str	q0, [x9, x8]
     5dc:	f940e288 	ldr	x8, [x20, #448]
     5e0:	f940a289 	ldr	x9, [x20, #320]
     5e4:	f9002288 	str	x8, [x20, #64]
     5e8:	f940aa88 	ldr	x8, [x20, #336]
     5ec:	f9003a89 	str	x9, [x20, #112]
     5f0:	f9003288 	str	x8, [x20, #96]
     5f4:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	5f4: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     5f8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	5f8: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x4
     5fc:	5283e809 	mov	w9, #0x1f40                	// #8000
     600:	b9400108 	ldr	w8, [x8]	600: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x4
     604:	6b09011f 	cmp	w8, w9
     608:	1a9fa7e9 	cset	w9, lt	// lt = tstop
     60c:	0a090015 	and	w21, w0, w9
     610:	710006bf 	cmp	w21, #0x1
     614:	540003a1 	b.ne	688 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x688>  // b.any
     618:	f9400369 	ldr	x9, [x27]
     61c:	b940038a 	ldr	w10, [x28]
     620:	11000508 	add	w8, w8, #0x1
     624:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	624: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x4
     628:	f94002e1 	ldr	x1, [x23]
     62c:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	62c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x7f
     630:	91000000 	add	x0, x0, #0x0	630: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x7f
     634:	b9000168 	str	w8, [x11]	634: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x4
     638:	8b0a0128 	add	x8, x9, x10
     63c:	2d400500 	ldp	s0, s1, [x8]
     640:	bd400902 	ldr	s2, [x8, #8]
     644:	2d441103 	ldp	s3, s4, [x8, #32]
     648:	8b214129 	add	x9, x9, w1, uxtw
     64c:	2d451905 	ldp	s5, s6, [x8, #40]
     650:	1e22c042 	fcvt	d2, s2
     654:	1e22c000 	fcvt	d0, s0
     658:	1e22c021 	fcvt	d1, s1
     65c:	b9407122 	ldr	w2, [x9, #112]
     660:	1e22c063 	fcvt	d3, s3
     664:	1e22c084 	fcvt	d4, s4
     668:	b9407923 	ldr	w3, [x9, #120]
     66c:	1e22c0a5 	fcvt	d5, s5
     670:	1e22c0c6 	fcvt	d6, s6
     674:	94000000 	bl	0 <printf>	674: R_AARCH64_CALL26	printf
     678:	90000008 	adrp	x8, 0 <stdout>	678: R_AARCH64_ADR_GOT_PAGE	stdout
     67c:	f9400108 	ldr	x8, [x8]	67c: R_AARCH64_LD64_GOT_LO12_NC	stdout
     680:	f9400100 	ldr	x0, [x8]
     684:	94000000 	bl	0 <fflush>	684: R_AARCH64_CALL26	fflush
     688:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	688: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
     68c:	f9400108 	ldr	x8, [x8]	68c: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     690:	b981f289 	ldrsw	x9, [x20, #496]
     694:	f940228a 	ldr	x10, [x20, #64]
     698:	f9402a8b 	ldr	x11, [x20, #80]
     69c:	f9400d08 	ldr	x8, [x8, #24]
     6a0:	b9800108 	ldrsw	x8, [x8]
     6a4:	f9001289 	str	x9, [x20, #32]
     6a8:	f9403289 	ldr	x9, [x20, #96]
     6ac:	a9392faa 	stp	x10, x11, [x29, #-112]
     6b0:	f9403a8a 	ldr	x10, [x20, #112]
     6b4:	f940428b 	ldr	x11, [x20, #128]
     6b8:	f900ca88 	str	x8, [x20, #400]
     6bc:	a93a2ba9 	stp	x9, x10, [x29, #-96]
     6c0:	f9404a89 	ldr	x9, [x20, #144]
     6c4:	f940528a 	ldr	x10, [x20, #160]
     6c8:	a93b27ab 	stp	x11, x9, [x29, #-80]
     6cc:	f9405a89 	ldr	x9, [x20, #176]
     6d0:	a93c27aa 	stp	x10, x9, [x29, #-64]
     6d4:	340059e8 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
     6d8:	f9400365 	ldr	x5, [x27]
     6dc:	f940b283 	ldr	x3, [x20, #352]
     6e0:	92407d08 	and	x8, x8, #0xffffffff
     6e4:	f940ba84 	ldr	x4, [x20, #368]
     6e8:	8b0800a0 	add	x0, x5, x8
     6ec:	d101c3a1 	sub	x1, x29, #0x70
     6f0:	aa1f03e2 	mov	x2, xzr
     6f4:	94000000 	bl	0 <_call_goal8_asm_systemv>	6f4: R_AARCH64_CALL26	_call_goal8_asm_systemv
     6f8:	f940ea89 	ldr	x9, [x20, #464]
     6fc:	f9400368 	ldr	x8, [x27]
     700:	f9001280 	str	x0, [x20, #32]
     704:	927c6d2a 	and	x10, x9, #0xfffffff0
     708:	3cea6900 	ldr	q0, [x8, x10]
     70c:	1100412a 	add	w10, w9, #0x10
     710:	927c6d4a 	and	x10, x10, #0xfffffff0
     714:	3d807280 	str	q0, [x20, #448]
     718:	3cea6900 	ldr	q0, [x8, x10]
     71c:	1100812a 	add	w10, w9, #0x20
     720:	927c6d4a 	and	x10, x10, #0xfffffff0
     724:	3d8002e0 	str	q0, [x23]
     728:	3cea6900 	ldr	q0, [x8, x10]
     72c:	1100c12a 	add	w10, w9, #0x30
     730:	927c6d4a 	and	x10, x10, #0xfffffff0
     734:	3d800380 	str	q0, [x28]
     738:	3cea6900 	ldr	q0, [x8, x10]
     73c:	1101012a 	add	w10, w9, #0x40
     740:	927c6d4a 	and	x10, x10, #0xfffffff0
     744:	3d804680 	str	q0, [x20, #272]
     748:	3cea6900 	ldr	q0, [x8, x10]
     74c:	1101412a 	add	w10, w9, #0x50
     750:	91018129 	add	x9, x9, #0x60
     754:	927c6d4a 	and	x10, x10, #0xfffffff0
     758:	3d804e80 	str	q0, [x20, #304]
     75c:	3cea6900 	ldr	q0, [x8, x10]
     760:	f900ea89 	str	x9, [x20, #464]
     764:	3d800300 	str	q0, [x24]
     768:	340003b5 	cbz	w21, 7dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x7dc>
     76c:	b9400389 	ldr	w9, [x28]
     770:	f94002e1 	ldr	x1, [x23]
     774:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	774: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xcd
     778:	91000000 	add	x0, x0, #0x0	778: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xcd
     77c:	8b090109 	add	x9, x8, x9
     780:	8b214108 	add	x8, x8, w1, uxtw
     784:	2d400520 	ldp	s0, s1, [x9]
     788:	bd400922 	ldr	s2, [x9, #8]
     78c:	2d441123 	ldp	s3, s4, [x9, #32]
     790:	bd401911 	ldr	s17, [x8, #24]
     794:	2d451925 	ldp	s5, s6, [x9, #40]
     798:	1e22c042 	fcvt	d2, s2
     79c:	2d424107 	ldp	s7, s16, [x8, #16]
     7a0:	1e22c000 	fcvt	d0, s0
     7a4:	1e22c021 	fcvt	d1, s1
     7a8:	1e22c063 	fcvt	d3, s3
     7ac:	1e22c084 	fcvt	d4, s4
     7b0:	1e22c0a5 	fcvt	d5, s5
     7b4:	1e22c0c6 	fcvt	d6, s6
     7b8:	1e22c231 	fcvt	d17, s17
     7bc:	1e22c0e7 	fcvt	d7, s7
     7c0:	1e22c210 	fcvt	d16, s16
     7c4:	6d0047f0 	stp	d16, d17, [sp]
     7c8:	94000000 	bl	0 <printf>	7c8: R_AARCH64_CALL26	printf
     7cc:	90000008 	adrp	x8, 0 <stdout>	7cc: R_AARCH64_ADR_GOT_PAGE	stdout
     7d0:	f9400108 	ldr	x8, [x8]	7d0: R_AARCH64_LD64_GOT_LO12_NC	stdout
     7d4:	f9400100 	ldr	x0, [x8]
     7d8:	94000000 	bl	0 <fflush>	7d8: R_AARCH64_CALL26	fflush
     7dc:	b9400388 	ldr	w8, [x28]
     7e0:	37000833 	tbnz	w19, #0, 8e4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x8e4>
     7e4:	f9400369 	ldr	x9, [x27]
     7e8:	b941528b 	ldr	w11, [x20, #336]
     7ec:	bd431a81 	ldr	s1, [x20, #792]
     7f0:	8b08012a 	add	x10, x9, x8
     7f4:	8b0b0129 	add	x9, x9, x11
     7f8:	f940094c 	ldr	x12, [x10, #16]
     7fc:	3dc00142 	ldr	q2, [x10]
     800:	f81903ac 	stur	x12, [x29, #-112]
     804:	bd404120 	ldr	s0, [x9, #64]
     808:	fc444123 	ldur	d3, [x9, #68]
     80c:	fc414124 	ldur	d4, [x9, #20]
     810:	b940612b 	ldr	w11, [x9, #96]
     814:	1e200820 	fmul	s0, s1, s0
     818:	0f819061 	fmul	v1.2s, v3.2s, v1.s[0]
     81c:	bd401123 	ldr	s3, [x9, #16]
     820:	1e232800 	fadd	s0, s0, s3
     824:	0e24d421 	fadd	v1.2s, v1.2s, v4.2s
     828:	3400010b 	cbz	w11, 848 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x848>
     82c:	1e270163 	fmov	s3, w11
     830:	bd431e84 	ldr	s4, [x20, #796]
     834:	1e233903 	fsub	s3, s8, s3
     838:	1e230883 	fmul	s3, s4, s3
     83c:	1e233903 	fsub	s3, s8, s3
     840:	1e230800 	fmul	s0, s0, s3
     844:	0f839021 	fmul	v1.2s, v1.2s, v3.s[0]
     848:	6e002003 	ext	v3.16b, v0.16b, v0.16b, #4
     84c:	bd401d24 	ldr	s4, [x9, #28]
     850:	bd431685 	ldr	s5, [x20, #788]
     854:	3dc00d26 	ldr	q6, [x9, #48]
     858:	fd401531 	ldr	d17, [x9, #40]
     85c:	fd400d47 	ldr	d7, [x10, #24]
     860:	4e0404b0 	dup	v16.4s, v5.s[0]
     864:	6e016063 	ext	v3.16b, v3.16b, v1.16b, #12
     868:	2e31de10 	fmul	v16.2s, v16.2s, v17.2s
     86c:	6e1c0483 	mov	v3.s[3], v4.s[0]
     870:	4f859063 	fmul	v3.4s, v3.4s, v5.s[0]
     874:	4f8590c5 	fmul	v5.4s, v6.4s, v5.s[0]
     878:	3dc00946 	ldr	q6, [x10, #32]
     87c:	bd001120 	str	s0, [x9, #16]
     880:	fc014121 	stur	d1, [x9, #20]
     884:	bd001d24 	str	s4, [x9, #28]
     888:	4e23d442 	fadd	v2.4s, v2.4s, v3.4s
     88c:	4e25d4c3 	fadd	v3.4s, v6.4s, v5.4s
     890:	f9400369 	ldr	x9, [x27]
     894:	0e30d4e5 	fadd	v5.2s, v7.2s, v16.2s
     898:	3ca86922 	str	q2, [x9, x8]
     89c:	f9400369 	ldr	x9, [x27]
     8a0:	4ea0e866 	fcmlt	v6.4s, v3.4s, #0.0
     8a4:	f85903aa 	ldur	x10, [x29, #-112]
     8a8:	8b080129 	add	x9, x9, x8
     8ac:	f900092a 	str	x10, [x9, #16]
     8b0:	fd000d25 	str	d5, [x9, #24]
     8b4:	4e661c63 	bic	v3.16b, v3.16b, v6.16b
     8b8:	f9400369 	ldr	x9, [x27]
     8bc:	8b080128 	add	x8, x9, x8
     8c0:	3d800903 	str	q3, [x8, #32]
     8c4:	3d80a682 	str	q2, [x20, #656]
     8c8:	f901528a 	str	x10, [x20, #672]
     8cc:	fd015685 	str	d5, [x20, #680]
     8d0:	3d80ae83 	str	q3, [x20, #688]
     8d4:	bd02c280 	str	s0, [x20, #704]
     8d8:	fd001b21 	str	d1, [x25, #48]
     8dc:	bd02ce84 	str	s4, [x20, #716]
     8e0:	14000092 	b	b28 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb28>
     8e4:	f2400d1f 	tst	x8, #0xf
     8e8:	54004ba1 	b.ne	125c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x125c>  // b.any
     8ec:	f9400369 	ldr	x9, [x27]
     8f0:	927c6d08 	and	x8, x8, #0xfffffff0
     8f4:	8b08012a 	add	x10, x9, x8
     8f8:	f94002e8 	ldr	x8, [x23]
     8fc:	3dc00140 	ldr	q0, [x10]
     900:	f2400d1f 	tst	x8, #0xf
     904:	3d80a680 	str	q0, [x20, #656]
     908:	3dc00540 	ldr	q0, [x10, #16]
     90c:	3d80aa80 	str	q0, [x20, #672]
     910:	3dc00940 	ldr	q0, [x10, #32]
     914:	3d80ae80 	str	q0, [x20, #688]
     918:	54004a21 	b.ne	125c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x125c>  // b.any
     91c:	927c6d08 	and	x8, x8, #0xfffffff0
     920:	8b080128 	add	x8, x9, x8
     924:	3dc00500 	ldr	q0, [x8, #16]
     928:	3d80b280 	str	q0, [x20, #704]
     92c:	3dc00900 	ldr	q0, [x8, #32]
     930:	bd42c284 	ldr	s4, [x20, #704]
     934:	3d80b680 	str	q0, [x20, #720]
     938:	3dc00d00 	ldr	q0, [x8, #48]
     93c:	3d80ba80 	str	q0, [x20, #736]
     940:	3dc01100 	ldr	q0, [x8, #64]
     944:	3d80be80 	str	q0, [x20, #752]
     948:	bd431a80 	ldr	s0, [x20, #792]
     94c:	bd42f281 	ldr	s1, [x20, #752]
     950:	fd403322 	ldr	d2, [x25, #96]
     954:	bd42fe83 	ldr	s3, [x20, #764]
     958:	b9806109 	ldrsw	x9, [x8, #96]
     95c:	1e200821 	fmul	s1, s1, s0
     960:	0f809042 	fmul	v2.2s, v2.2s, v0.s[0]
     964:	1e200863 	fmul	s3, s3, s0
     968:	fd401b20 	ldr	d0, [x25, #48]
     96c:	b9020289 	str	w9, [x20, #512]
     970:	f9001a89 	str	x9, [x20, #48]
     974:	bd02f281 	str	s1, [x20, #752]
     978:	1e242821 	fadd	s1, s1, s4
     97c:	0e20d440 	fadd	v0.2s, v2.2s, v0.2s
     980:	fd003322 	str	d2, [x25, #96]
     984:	bd431e82 	ldr	s2, [x20, #796]
     988:	bd02fe83 	str	s3, [x20, #764]
     98c:	bd02c281 	str	s1, [x20, #704]
     990:	fd001b20 	str	d0, [x25, #48]
     994:	34000249 	cbz	w9, 9dc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9dc>
     998:	1e270123 	fmov	s3, w9
     99c:	f9401e8a 	ldr	x10, [x20, #56]
     9a0:	9e670124 	fmov	d4, x9
     9a4:	f901868a 	str	x10, [x20, #776]
     9a8:	1e233903 	fsub	s3, s8, s3
     9ac:	bd430a85 	ldr	s5, [x20, #776]
     9b0:	0f829084 	fmul	v4.2s, v4.2s, v2.s[0]
     9b4:	1e230843 	fmul	s3, s2, s3
     9b8:	1e250842 	fmul	s2, s2, s5
     9bc:	fd018284 	str	d4, [x20, #768]
     9c0:	1e233903 	fsub	s3, s8, s3
     9c4:	bd030a82 	str	s2, [x20, #776]
     9c8:	1e230821 	fmul	s1, s1, s3
     9cc:	0f839000 	fmul	v0.2s, v0.2s, v3.s[0]
     9d0:	bd030e83 	str	s3, [x20, #780]
     9d4:	bd02c281 	str	s1, [x20, #704]
     9d8:	fd001b20 	str	d0, [x25, #48]
     9dc:	bd431682 	ldr	s2, [x20, #788]
     9e0:	910bb289 	add	x9, x20, #0x2ec
     9e4:	fd417284 	ldr	d4, [x20, #736]
     9e8:	bd42d285 	ldr	s5, [x20, #720]
     9ec:	bd42d686 	ldr	s6, [x20, #724]
     9f0:	1e26000a 	fmov	w10, s0
     9f4:	4ea21c43 	mov	v3.16b, v2.16b
     9f8:	bd42da90 	ldr	s16, [x20, #728]
     9fc:	0f829012 	fmul	v18.2s, v0.2s, v2.s[0]
     a00:	1e250845 	fmul	s5, s2, s5
     a04:	1e260846 	fmul	s6, s2, s6
     a08:	bd42ce87 	ldr	s7, [x20, #716]
     a0c:	1e220831 	fmul	s17, s1, s2
     a10:	1e300850 	fmul	s16, s2, s16
     a14:	f941668b 	ldr	x11, [x20, #712]
     a18:	0d409123 	ld1	{v3.s}[1], [x9]
     a1c:	910ba289 	add	x9, x20, #0x2e8
     a20:	1e2208e7 	fmul	s7, s7, s2
     a24:	4d408124 	ld1	{v4.s}[2], [x9]
     a28:	fd004b32 	str	d18, [x25, #144]
     a2c:	1e260029 	fmov	w9, s1
     a30:	bd033285 	str	s5, [x20, #816]
     a34:	3dc0ae85 	ldr	q5, [x20, #688]
     a38:	4e833863 	zip1	v3.4s, v3.4s, v3.4s
     a3c:	bd033686 	str	s6, [x20, #820]
     a40:	fd400326 	ldr	d6, [x25]
     a44:	6e1c0444 	mov	v4.s[3], v2.s[0]
     a48:	bd032291 	str	s17, [x20, #800]
     a4c:	aa0a8129 	orr	x9, x9, x10, lsl #32
     a50:	0e26d646 	fadd	v6.2s, v18.2s, v6.2s
     a54:	bd42aa92 	ldr	s18, [x20, #680]
     a58:	bd033a90 	str	s16, [x20, #824]
     a5c:	bd032e87 	str	s7, [x20, #812]
     a60:	6e140443 	mov	v3.s[2], v2.s[0]
     a64:	1e322a10 	fadd	s16, s16, s18
     a68:	fd000326 	str	d6, [x25]
     a6c:	6e23dc83 	fmul	v3.4s, v4.4s, v3.4s
     a70:	bd42de84 	ldr	s4, [x20, #732]
     a74:	bd02aa90 	str	s16, [x20, #680]
     a78:	1e240842 	fmul	s2, s2, s4
     a7c:	bd429284 	ldr	s4, [x20, #656]
     a80:	4e25d465 	fadd	v5.4s, v3.4s, v5.4s
     a84:	1e242a24 	fadd	s4, s17, s4
     a88:	bd429e91 	ldr	s17, [x20, #668]
     a8c:	3d80d283 	str	q3, [x20, #832]
     a90:	1e3128e7 	fadd	s7, s7, s17
     a94:	bd42ae91 	ldr	s17, [x20, #684]
     a98:	bd033e82 	str	s2, [x20, #828]
     a9c:	4ea0e8b2 	fcmlt	v18.4s, v5.4s, #0.0
     aa0:	1e312842 	fadd	s2, s2, s17
     aa4:	bd029284 	str	s4, [x20, #656]
     aa8:	bd029e87 	str	s7, [x20, #668]
     aac:	4e721ca1 	bic	v1.16b, v5.16b, v18.16b
     ab0:	bd02ae82 	str	s2, [x20, #684]
     ab4:	3d80ae81 	str	q1, [x20, #688]
     ab8:	a9012d09 	stp	x9, x11, [x8, #16]
     abc:	f940a288 	ldr	x8, [x20, #320]
     ac0:	f2400d1f 	tst	x8, #0xf
     ac4:	54003b41 	b.ne	122c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x122c>  // b.any
     ac8:	f9400369 	ldr	x9, [x27]
     acc:	f9414a8a 	ldr	x10, [x20, #656]
     ad0:	927c6d08 	and	x8, x8, #0xfffffff0
     ad4:	f9414e8b 	ldr	x11, [x20, #664]
     ad8:	8b080128 	add	x8, x9, x8
     adc:	a9002d0a 	stp	x10, x11, [x8]
     ae0:	f940a288 	ldr	x8, [x20, #320]
     ae4:	f2400d1f 	tst	x8, #0xf
     ae8:	54003a21 	b.ne	122c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x122c>  // b.any
     aec:	f9400369 	ldr	x9, [x27]
     af0:	f941528a 	ldr	x10, [x20, #672]
     af4:	927c6d08 	and	x8, x8, #0xfffffff0
     af8:	f941568b 	ldr	x11, [x20, #680]
     afc:	8b080128 	add	x8, x9, x8
     b00:	a9012d0a 	stp	x10, x11, [x8, #16]
     b04:	f940a288 	ldr	x8, [x20, #320]
     b08:	f2400d1f 	tst	x8, #0xf
     b0c:	54003901 	b.ne	122c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x122c>  // b.any
     b10:	f9400369 	ldr	x9, [x27]
     b14:	f9415a8a 	ldr	x10, [x20, #688]
     b18:	927c6d08 	and	x8, x8, #0xfffffff0
     b1c:	f9415e8b 	ldr	x11, [x20, #696]
     b20:	8b080128 	add	x8, x9, x8
     b24:	a9022d0a 	stp	x10, x11, [x8, #32]
     b28:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	b28: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     b2c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	b2c: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x8
     b30:	b9400109 	ldr	w9, [x8]	b30: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x8
     b34:	5283e808 	mov	w8, #0x1f40                	// #8000
     b38:	6b08013f 	cmp	w9, w8
     b3c:	1a9fa7e8 	cset	w8, lt	// lt = tstop
     b40:	0a080008 	and	w8, w0, w8
     b44:	7100051f 	cmp	w8, #0x1
     b48:	540007c1 	b.ne	c40 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc40>  // b.any
     b4c:	f940036a 	ldr	x10, [x27]
     b50:	b9400388 	ldr	w8, [x28]
     b54:	52a8690b 	mov	w11, #0x43480000            	// #1128792064
     b58:	f94002e1 	ldr	x1, [x23]
     b5c:	1e270162 	fmov	s2, w11
     b60:	8b080148 	add	x8, x10, x8
     b64:	2d440500 	ldp	s0, s1, [x8, #32]
     b68:	8b21414a 	add	x10, x10, w1, uxtw
     b6c:	2d461544 	ldp	s4, s5, [x10, #48]
     b70:	1e222000 	fcmp	s0, s2
     b74:	2d450d02 	ldp	s2, s3, [x8, #40]
     b78:	2d471d46 	ldp	s6, s7, [x10, #56]
     b7c:	540004cd 	b.le	c14 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc14>
     b80:	52a8690a 	mov	w10, #0x43480000            	// #1128792064
     b84:	1e270150 	fmov	s16, w10
     b88:	1e302020 	fcmp	s1, s16
     b8c:	5400044d 	b.le	c14 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc14>
     b90:	1e202048 	fcmp	s2, #0.0
     b94:	54000401 	b.ne	c14 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc14>  // b.any
     b98:	11000529 	add	w9, w9, #0x1
     b9c:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	b9c: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x8
     ba0:	1e22c000 	fcvt	d0, s0
     ba4:	b9000149 	str	w9, [x10]	ba4: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x8
     ba8:	1e22c021 	fcvt	d1, s1
     bac:	1e22c042 	fcvt	d2, s2
     bb0:	2d404510 	ldp	s16, s17, [x8]
     bb4:	bd400912 	ldr	s18, [x8, #8]
     bb8:	bd401113 	ldr	s19, [x8, #16]
     bbc:	bd401d14 	ldr	s20, [x8, #28]
     bc0:	1e22c063 	fcvt	d3, s3
     bc4:	1e22c084 	fcvt	d4, s4
     bc8:	1e22c0a5 	fcvt	d5, s5
     bcc:	1e22c0c6 	fcvt	d6, s6
     bd0:	1e22c0e7 	fcvt	d7, s7
     bd4:	1e22c210 	fcvt	d16, s16
     bd8:	1e22c231 	fcvt	d17, s17
     bdc:	1e22c252 	fcvt	d18, s18
     be0:	1e22c273 	fcvt	d19, s19
     be4:	1e22c294 	fcvt	d20, s20
     be8:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	be8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x11b
     bec:	91000000 	add	x0, x0, #0x0	bec: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x11b
     bf0:	fd0003f0 	str	d16, [sp]
     bf4:	6d01d3f3 	stp	d19, d20, [sp, #24]
     bf8:	6d00cbf1 	stp	d17, d18, [sp, #8]
     bfc:	94000000 	bl	0 <printf>	bfc: R_AARCH64_CALL26	printf
     c00:	90000008 	adrp	x8, 0 <stdout>	c00: R_AARCH64_ADR_GOT_PAGE	stdout
     c04:	f9400108 	ldr	x8, [x8]	c04: R_AARCH64_LD64_GOT_LO12_NC	stdout
     c08:	f9400100 	ldr	x0, [x8]
     c0c:	94000000 	bl	0 <fflush>	c0c: R_AARCH64_CALL26	fflush
     c10:	1400000c 	b	c40 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc40>
     c14:	52a8590a 	mov	w10, #0x42c80000            	// #1120403456
     c18:	1e270150 	fmov	s16, w10
     c1c:	52a8604a 	mov	w10, #0x43020000            	// #1124204544
     c20:	1e302020 	fcmp	s1, s16
     c24:	1e270150 	fmov	s16, w10
     c28:	1e29a440 	fccmp	s2, s9, #0x0, ge	// ge = tcont
     c2c:	1e300402 	fccmp	s0, s16, #0x2, eq	// eq = none
     c30:	1a9f87ea 	cset	w10, ls	// ls = plast
     c34:	3707fb2a 	tbnz	w10, #0, b98 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb98>
     c38:	1e2a2080 	fcmp	s4, s10
     c3c:	54fffae4 	b.mi	b98 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xb98>  // b.first
     c40:	37000153 	tbnz	w19, #0, c68 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc68>
     c44:	b9400388 	ldr	w8, [x28]
     c48:	f9400369 	ldr	x9, [x27]
     c4c:	11006108 	add	w8, w8, #0x18
     c50:	bc686920 	ldr	s0, [x9, x8]
     c54:	1e38000a 	fcvtzs	w10, s0
     c58:	13003d4a 	sxth	w10, w10
     c5c:	1e220140 	scvtf	s0, w10
     c60:	bc286920 	str	s0, [x9, x8]
     c64:	1400000b 	b	c90 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc90>
     c68:	f9400368 	ldr	x8, [x27]
     c6c:	b9414289 	ldr	w9, [x20, #320]
     c70:	8b090108 	add	x8, x8, x9
     c74:	bd401900 	ldr	s0, [x8, #24]
     c78:	1e380009 	fcvtzs	w9, s0
     c7c:	93403d29 	sxth	x9, w9
     c80:	1e220120 	scvtf	s0, w9
     c84:	f9001a89 	str	x9, [x20, #48]
     c88:	bd020280 	str	s0, [x20, #512]
     c8c:	bd001900 	str	s0, [x8, #24]
     c90:	f9400365 	ldr	x5, [x27]
     c94:	b9415288 	ldr	w8, [x20, #336]
     c98:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	c98: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
     c9c:	8b0800a8 	add	x8, x5, x8
     ca0:	b9406908 	ldr	w8, [x8, #104]
     ca4:	f9400129 	ldr	x9, [x9]	ca4: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     ca8:	92790108 	and	x8, x8, #0x80
     cac:	f9400929 	ldr	x9, [x9, #16]
     cb0:	f9001a88 	str	x8, [x20, #48]
     cb4:	b9800129 	ldrsw	x9, [x9]
     cb8:	f900ca89 	str	x9, [x20, #400]
     cbc:	34001988 	cbz	w8, fec <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfec>
     cc0:	94000000 	bl	0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	cc0: R_AARCH64_CALL26	.text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv
     cc4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	cc4: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0xc
     cc8:	b9400109 	ldr	w9, [x8]	cc8: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0xc
     ccc:	5290d408 	mov	w8, #0x86a0                	// #34464
     cd0:	72a00028 	movk	w8, #0x1, lsl #16
     cd4:	6b08013f 	cmp	w9, w8
     cd8:	1a9fa7e8 	cset	w8, lt	// lt = tstop
     cdc:	0a080015 	and	w21, w0, w8
     ce0:	710006bf 	cmp	w21, #0x1
     ce4:	54000941 	b.ne	e0c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe0c>  // b.any
     ce8:	f9400368 	ldr	x8, [x27]
     cec:	f94002e1 	ldr	x1, [x23]
     cf0:	1100052a 	add	w10, w9, #0x1
     cf4:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	cf4: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0xc
     cf8:	2f00e405 	movi	d5, #0x0
     cfc:	2f00e410 	movi	d16, #0x0
     d00:	8b214109 	add	x9, x8, w1, uxtw
     d04:	b900016a 	str	w10, [x11]	d04: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0xc
     d08:	2f00e411 	movi	d17, #0x0
     d0c:	2f00e412 	movi	d18, #0x0
     d10:	529ffc6b 	mov	w11, #0xffe3                	// #65507
     d14:	b9406d22 	ldr	w2, [x9, #108]
     d18:	72a0ffeb 	movk	w11, #0x7ff, lsl #16
     d1c:	5100444a 	sub	w10, w2, #0x11
     d20:	6b0b015f 	cmp	w10, w11
     d24:	54000082 	b.cs	d34 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd34>  // b.hs, b.nlast
     d28:	8b02010a 	add	x10, x8, x2
     d2c:	2d404552 	ldp	s18, s17, [x10]
     d30:	bd400950 	ldr	s16, [x10, #8]
     d34:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	d34: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
     d38:	1100116b 	add	w11, w11, #0x4
     d3c:	f940014a 	ldr	x10, [x10]	d3c: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     d40:	2d410121 	ldp	s1, s0, [x9, #8]
     d44:	2d420d22 	ldp	s2, s3, [x9, #16]
     d48:	bd401924 	ldr	s4, [x9, #24]
     d4c:	f940014a 	ldr	x10, [x10]
     d50:	2d4a1d26 	ldp	s6, s7, [x9, #80]
     d54:	2d4b6d3a 	ldp	s26, s27, [x9, #88]
     d58:	b940014a 	ldr	w10, [x10]
     d5c:	5100454c 	sub	w12, w10, #0x11
     d60:	6b0b019f 	cmp	w12, w11
     d64:	b940038b 	ldr	w11, [x28]
     d68:	8b0b010b 	add	x11, x8, x11
     d6c:	2d405173 	ldp	s19, s20, [x11]
     d70:	bd400975 	ldr	s21, [x11, #8]
     d74:	2d445d76 	ldp	s22, s23, [x11, #32]
     d78:	2d456578 	ldp	s24, s25, [x11, #40]
     d7c:	54000062 	b.cs	d88 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd88>  // b.hs, b.nlast
     d80:	8b0a0108 	add	x8, x8, x10
     d84:	bd400505 	ldr	s5, [x8, #4]
     d88:	1e22c000 	fcvt	d0, s0
     d8c:	1e22c021 	fcvt	d1, s1
     d90:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	d90: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x17f
     d94:	91000000 	add	x0, x0, #0x0	d94: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x17f
     d98:	1e22c042 	fcvt	d2, s2
     d9c:	1e22c063 	fcvt	d3, s3
     da0:	1e22c084 	fcvt	d4, s4
     da4:	1e22c0a5 	fcvt	d5, s5
     da8:	1e22c0c6 	fcvt	d6, s6
     dac:	1e22c0e7 	fcvt	d7, s7
     db0:	1e22c35a 	fcvt	d26, s26
     db4:	1e22c37b 	fcvt	d27, s27
     db8:	1e22c252 	fcvt	d18, s18
     dbc:	1e22c231 	fcvt	d17, s17
     dc0:	1e22c210 	fcvt	d16, s16
     dc4:	1e22c273 	fcvt	d19, s19
     dc8:	1e22c294 	fcvt	d20, s20
     dcc:	1e22c2b5 	fcvt	d21, s21
     dd0:	1e22c2d6 	fcvt	d22, s22
     dd4:	1e22c2f7 	fcvt	d23, s23
     dd8:	1e22c318 	fcvt	d24, s24
     ddc:	6d006ffa 	stp	d26, d27, [sp]
     de0:	1e22c339 	fcvt	d25, s25
     de4:	6d0147f2 	stp	d18, d17, [sp, #16]
     de8:	6d0357f4 	stp	d20, d21, [sp, #48]
     dec:	6d045ff6 	stp	d22, d23, [sp, #64]
     df0:	6d0567f8 	stp	d24, d25, [sp, #80]
     df4:	6d024ff0 	stp	d16, d19, [sp, #32]
     df8:	94000000 	bl	0 <printf>	df8: R_AARCH64_CALL26	printf
     dfc:	90000008 	adrp	x8, 0 <stdout>	dfc: R_AARCH64_ADR_GOT_PAGE	stdout
     e00:	f9400108 	ldr	x8, [x8]	e00: R_AARCH64_LD64_GOT_LO12_NC	stdout
     e04:	f9400100 	ldr	x0, [x8]
     e08:	94000000 	bl	0 <fflush>	e08: R_AARCH64_CALL26	fflush
     e0c:	f940ea88 	ldr	x8, [x20, #464]
     e10:	f9400369 	ldr	x9, [x27]
     e14:	3dc07280 	ldr	q0, [x20, #448]
     e18:	d1018108 	sub	x8, x8, #0x60
     e1c:	f900ea88 	str	x8, [x20, #464]
     e20:	927c6d08 	and	x8, x8, #0xfffffff0
     e24:	3ca86920 	str	q0, [x9, x8]
     e28:	b941d288 	ldr	w8, [x20, #464]
     e2c:	f9400369 	ldr	x9, [x27]
     e30:	3dc05680 	ldr	q0, [x20, #336]
     e34:	11004108 	add	w8, w8, #0x10
     e38:	927c6d08 	and	x8, x8, #0xfffffff0
     e3c:	3ca86920 	str	q0, [x9, x8]
     e40:	b941d288 	ldr	w8, [x20, #464]
     e44:	f9400369 	ldr	x9, [x27]
     e48:	3dc05280 	ldr	q0, [x20, #320]
     e4c:	11008108 	add	w8, w8, #0x20
     e50:	927c6d08 	and	x8, x8, #0xfffffff0
     e54:	3ca86920 	str	q0, [x9, x8]
     e58:	b941d288 	ldr	w8, [x20, #464]
     e5c:	f9400369 	ldr	x9, [x27]
     e60:	3dc04680 	ldr	q0, [x20, #272]
     e64:	1100c108 	add	w8, w8, #0x30
     e68:	927c6d08 	and	x8, x8, #0xfffffff0
     e6c:	3ca86920 	str	q0, [x9, x8]
     e70:	b941d288 	ldr	w8, [x20, #464]
     e74:	f9400369 	ldr	x9, [x27]
     e78:	3dc04e80 	ldr	q0, [x20, #304]
     e7c:	11010108 	add	w8, w8, #0x40
     e80:	927c6d08 	and	x8, x8, #0xfffffff0
     e84:	3ca86920 	str	q0, [x9, x8]
     e88:	f940e288 	ldr	x8, [x20, #448]
     e8c:	b941d28a 	ldr	w10, [x20, #464]
     e90:	f940aa89 	ldr	x9, [x20, #336]
     e94:	f940a28b 	ldr	x11, [x20, #320]
     e98:	f940036c 	ldr	x12, [x27]
     e9c:	3dc04a80 	ldr	q0, [x20, #288]
     ea0:	f9002288 	str	x8, [x20, #64]
     ea4:	11014148 	add	w8, w10, #0x50
     ea8:	f9002a89 	str	x9, [x20, #80]
     eac:	927c6d09 	and	x9, x8, #0xfffffff0
     eb0:	b9419288 	ldr	w8, [x20, #400]
     eb4:	f900328b 	str	x11, [x20, #96]
     eb8:	3ca96980 	str	q0, [x12, x9]
     ebc:	f9402289 	ldr	x9, [x20, #64]
     ec0:	f9402a8a 	ldr	x10, [x20, #80]
     ec4:	f940328b 	ldr	x11, [x20, #96]
     ec8:	a9392ba9 	stp	x9, x10, [x29, #-112]
     ecc:	f9403a89 	ldr	x9, [x20, #112]
     ed0:	f940428a 	ldr	x10, [x20, #128]
     ed4:	a93a27ab 	stp	x11, x9, [x29, #-96]
     ed8:	f9404a8b 	ldr	x11, [x20, #144]
     edc:	f9405289 	ldr	x9, [x20, #160]
     ee0:	a93b2faa 	stp	x10, x11, [x29, #-80]
     ee4:	f9405a8a 	ldr	x10, [x20, #176]
     ee8:	a93c2ba9 	stp	x9, x10, [x29, #-64]
     eec:	34001928 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
     ef0:	f9400365 	ldr	x5, [x27]
     ef4:	f940b283 	ldr	x3, [x20, #352]
     ef8:	f940ba84 	ldr	x4, [x20, #368]
     efc:	8b0800a0 	add	x0, x5, x8
     f00:	d101c3a1 	sub	x1, x29, #0x70
     f04:	aa1f03e2 	mov	x2, xzr
     f08:	94000000 	bl	0 <_call_goal8_asm_systemv>	f08: R_AARCH64_CALL26	_call_goal8_asm_systemv
     f0c:	f940ea88 	ldr	x8, [x20, #464]
     f10:	f9400365 	ldr	x5, [x27]
     f14:	f9001280 	str	x0, [x20, #32]
     f18:	927c6d09 	and	x9, x8, #0xfffffff0
     f1c:	3ce968a0 	ldr	q0, [x5, x9]
     f20:	11004109 	add	w9, w8, #0x10
     f24:	927c6d29 	and	x9, x9, #0xfffffff0
     f28:	3d807280 	str	q0, [x20, #448]
     f2c:	3ce968a0 	ldr	q0, [x5, x9]
     f30:	11008109 	add	w9, w8, #0x20
     f34:	927c6d29 	and	x9, x9, #0xfffffff0
     f38:	3d8002e0 	str	q0, [x23]
     f3c:	3ce968a0 	ldr	q0, [x5, x9]
     f40:	1100c109 	add	w9, w8, #0x30
     f44:	927c6d29 	and	x9, x9, #0xfffffff0
     f48:	3d800380 	str	q0, [x28]
     f4c:	3ce968a0 	ldr	q0, [x5, x9]
     f50:	11010109 	add	w9, w8, #0x40
     f54:	927c6d29 	and	x9, x9, #0xfffffff0
     f58:	3d804680 	str	q0, [x20, #272]
     f5c:	3ce968a0 	ldr	q0, [x5, x9]
     f60:	11014109 	add	w9, w8, #0x50
     f64:	91018108 	add	x8, x8, #0x60
     f68:	927c6d29 	and	x9, x9, #0xfffffff0
     f6c:	3d804e80 	str	q0, [x20, #304]
     f70:	3ce968a0 	ldr	q0, [x5, x9]
     f74:	f900ea88 	str	x8, [x20, #464]
     f78:	3d800300 	str	q0, [x24]
     f7c:	34000395 	cbz	w21, fec <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfec>
     f80:	f94002e1 	ldr	x1, [x23]
     f84:	b9400388 	ldr	w8, [x28]
     f88:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	f88: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x1fe
     f8c:	91000000 	add	x0, x0, #0x0	f8c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x1fe
     f90:	8b2140a9 	add	x9, x5, w1, uxtw
     f94:	8b0800a8 	add	x8, x5, x8
     f98:	2d401d06 	ldp	s6, s7, [x8]
     f9c:	bd400910 	ldr	s16, [x8, #8]
     fa0:	2d410121 	ldp	s1, s0, [x9, #8]
     fa4:	2d4a0d22 	ldp	s2, s3, [x9, #80]
     fa8:	1e22c210 	fcvt	d16, s16
     fac:	2d4b1524 	ldp	s4, s5, [x9, #88]
     fb0:	1e22c0c6 	fcvt	d6, s6
     fb4:	1e22c000 	fcvt	d0, s0
     fb8:	1e22c021 	fcvt	d1, s1
     fbc:	1e22c0e7 	fcvt	d7, s7
     fc0:	1e22c042 	fcvt	d2, s2
     fc4:	1e22c063 	fcvt	d3, s3
     fc8:	1e22c084 	fcvt	d4, s4
     fcc:	1e22c0a5 	fcvt	d5, s5
     fd0:	fd0003f0 	str	d16, [sp]
     fd4:	94000000 	bl	0 <printf>	fd4: R_AARCH64_CALL26	printf
     fd8:	90000008 	adrp	x8, 0 <stdout>	fd8: R_AARCH64_ADR_GOT_PAGE	stdout
     fdc:	f9400108 	ldr	x8, [x8]	fdc: R_AARCH64_LD64_GOT_LO12_NC	stdout
     fe0:	f9400100 	ldr	x0, [x8]
     fe4:	94000000 	bl	0 <fflush>	fe4: R_AARCH64_CALL26	fflush
     fe8:	f9400365 	ldr	x5, [x27]
     fec:	b9414288 	ldr	w8, [x20, #320]
     ff0:	f940aa9a 	ldr	x26, [x20, #336]
     ff4:	11008108 	add	w8, w8, #0x20
     ff8:	927c6d08 	and	x8, x8, #0xfffffff0
     ffc:	3ce868a0 	ldr	q0, [x5, x8]
    1000:	8b3a40a8 	add	x8, x5, w26, uxtw
    1004:	3d8002c0 	str	q0, [x22]
    1008:	b9806908 	ldrsw	x8, [x8, #104]
    100c:	927e0109 	and	x9, x8, #0x4
    1010:	f9002288 	str	x8, [x20, #64]
    1014:	f9002a89 	str	x9, [x20, #80]
    1018:	36080108 	tbz	w8, #1, 1038 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1038>
    101c:	a9432a8b 	ldp	x11, x10, [x20, #48]
    1020:	29182a9f 	stp	wzr, w10, [x20, #192]
    1024:	d360fd4a 	lsr	x10, x10, #32
    1028:	29192a9f 	stp	wzr, w10, [x20, #200]
    102c:	b500006b 	cbnz	x11, 1038 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1038>
    1030:	f940628a 	ldr	x10, [x20, #192]
    1034:	b40003aa 	cbz	x10, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
    1038:	92400108 	and	x8, x8, #0x1
    103c:	f9002288 	str	x8, [x20, #64]
    1040:	b4000109 	cbz	x9, 1060 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1060>
    1044:	f9401e89 	ldr	x9, [x20, #56]
    1048:	d360fd2a 	lsr	x10, x9, #32
    104c:	29197e89 	stp	w9, wzr, [x20, #200]
    1050:	29182a9f 	stp	wzr, w10, [x20, #192]
    1054:	f940628a 	ldr	x10, [x20, #192]
    1058:	f100055f 	cmp	x10, #0x1
    105c:	5400026b 	b.lt	10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>  // b.tstop
    1060:	b4ff8c08 	cbz	x8, 1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
    1064:	f9414a88 	ldr	x8, [x20, #656]
    1068:	f9414e89 	ldr	x9, [x20, #664]
    106c:	f941528a 	ldr	x10, [x20, #672]
    1070:	a9032688 	stp	x8, x9, [x20, #48]
    1074:	d360fd28 	lsr	x8, x9, #32
    1078:	29077e89 	stp	w9, wzr, [x20, #56]
    107c:	2906229f 	stp	wzr, w8, [x20, #48]
    1080:	f9415688 	ldr	x8, [x20, #680]
    1084:	f9401a89 	ldr	x9, [x20, #48]
    1088:	a903228a 	stp	x10, x8, [x20, #48]
    108c:	b7f800e9 	tbnz	x9, #63, 10a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x10a8>
    1090:	f9401e88 	ldr	x8, [x20, #56]
    1094:	d360fd09 	lsr	x9, x8, #32
    1098:	29077e88 	stp	w8, wzr, [x20, #56]
    109c:	2906269f 	stp	wzr, w9, [x20, #48]
    10a0:	f9401a89 	ldr	x9, [x20, #48]
    10a4:	b6ff89e9 	tbz	x9, #63, 1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
    10a8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	10a8: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
    10ac:	f9400108 	ldr	x8, [x8]	10ac: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
    10b0:	f940e289 	ldr	x9, [x20, #448]
    10b4:	f9408a8a 	ldr	x10, [x20, #272]
    10b8:	f940a28b 	ldr	x11, [x20, #320]
    10bc:	b981f28c 	ldrsw	x12, [x20, #496]
    10c0:	f9400508 	ldr	x8, [x8, #8]
    10c4:	b9800108 	ldrsw	x8, [x8]
    10c8:	f9002289 	str	x9, [x20, #64]
    10cc:	f9002a8a 	str	x10, [x20, #80]
    10d0:	a9392ba9 	stp	x9, x10, [x29, #-112]
    10d4:	f9404289 	ldr	x9, [x20, #128]
    10d8:	f9404a8a 	ldr	x10, [x20, #144]
    10dc:	f9003a8b 	str	x11, [x20, #112]
    10e0:	a93a2fba 	stp	x26, x11, [x29, #-96]
    10e4:	f940528b 	ldr	x11, [x20, #160]
    10e8:	a93b2ba9 	stp	x9, x10, [x29, #-80]
    10ec:	f9405a89 	ldr	x9, [x20, #176]
    10f0:	f900329a 	str	x26, [x20, #96]
    10f4:	f900ca88 	str	x8, [x20, #400]
    10f8:	f900128c 	str	x12, [x20, #32]
    10fc:	a93c27ab 	stp	x11, x9, [x29, #-64]
    1100:	34000888 	cbz	w8, 1210 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1210>
    1104:	f940b283 	ldr	x3, [x20, #352]
    1108:	f940ba84 	ldr	x4, [x20, #368]
    110c:	92407d08 	and	x8, x8, #0xffffffff
    1110:	8b0800a0 	add	x0, x5, x8
    1114:	d101c3a1 	sub	x1, x29, #0x70
    1118:	aa1f03e2 	mov	x2, xzr
    111c:	94000000 	bl	0 <_call_goal8_asm_systemv>	111c: R_AARCH64_CALL26	_call_goal8_asm_systemv
    1120:	f9001280 	str	x0, [x20, #32]
    1124:	17fffc2f 	b	1e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1e0>
    1128:	f9400368 	ldr	x8, [x27]
    112c:	f940ea89 	ldr	x9, [x20, #464]
    1130:	f9001295 	str	x21, [x20, #32]
    1134:	f869490a 	ldr	x10, [x8, w9, uxtw]
    1138:	1101c12b 	add	w11, w9, #0x70
    113c:	f900fa8a 	str	x10, [x20, #496]
    1140:	927c6d6a 	and	x10, x11, #0xfffffff0
    1144:	3cea6900 	ldr	q0, [x8, x10]
    1148:	1101812a 	add	w10, w9, #0x60
    114c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1150:	3d807280 	str	q0, [x20, #448]
    1154:	3cea6900 	ldr	q0, [x8, x10]
    1158:	1101412a 	add	w10, w9, #0x50
    115c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1160:	3d8002e0 	str	q0, [x23]
    1164:	3cea6900 	ldr	q0, [x8, x10]
    1168:	1101012a 	add	w10, w9, #0x40
    116c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1170:	3d800380 	str	q0, [x28]
    1174:	3cea6900 	ldr	q0, [x8, x10]
    1178:	1100c12a 	add	w10, w9, #0x30
    117c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1180:	3d804e80 	str	q0, [x20, #304]
    1184:	3cea6900 	ldr	q0, [x8, x10]
    1188:	1100812a 	add	w10, w9, #0x20
    118c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1190:	3d800300 	str	q0, [x24]
    1194:	3cea6900 	ldr	q0, [x8, x10]
    1198:	1100412a 	add	w10, w9, #0x10
    119c:	927c6d4a 	and	x10, x10, #0xfffffff0
    11a0:	3d804680 	str	q0, [x20, #272]
    11a4:	3cea6900 	ldr	q0, [x8, x10]
    11a8:	91020128 	add	x8, x9, #0x80
    11ac:	f900ea88 	str	x8, [x20, #464]
    11b0:	3d804280 	str	q0, [x20, #256]
    11b4:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	11b4: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
    11b8:	f9403be8 	ldr	x8, [sp, #112]
    11bc:	cb080000 	sub	x0, x0, x8
    11c0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	11c0: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
    11c4:	f9400108 	ldr	x8, [x8]	11c4: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
    11c8:	91002101 	add	x1, x8, #0x8
    11cc:	94000000 	bl	0 <__aarch64_ldadd8_relax>	11cc: R_AARCH64_CALL26	__aarch64_ldadd8_relax
    11d0:	f9403fe8 	ldr	x8, [sp, #120]
    11d4:	f9401508 	ldr	x8, [x8, #40]
    11d8:	f85d03a9 	ldur	x9, [x29, #-48]
    11dc:	eb09011f 	cmp	x8, x9
    11e0:	54000981 	b.ne	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>  // b.any
    11e4:	aa1503e0 	mov	x0, x21
    11e8:	a9544ff4 	ldp	x20, x19, [sp, #320]
    11ec:	fd406bea 	ldr	d10, [sp, #208]
    11f0:	a95357f6 	ldp	x22, x21, [sp, #304]
    11f4:	a9525ff8 	ldp	x24, x23, [sp, #288]
    11f8:	a95167fa 	ldp	x26, x25, [sp, #272]
    11fc:	a9506ffc 	ldp	x28, x27, [sp, #256]
    1200:	a94f7bfd 	ldp	x29, x30, [sp, #240]
    1204:	6d4e23e9 	ldp	d9, d8, [sp, #224]
    1208:	910543ff 	add	sp, sp, #0x150
    120c:	d65f03c0 	ret
    1210:	52803202 	mov	w2, #0x190                 	// #400
    1214:	f9403fe8 	ldr	x8, [sp, #120]
    1218:	f9401508 	ldr	x8, [x8, #40]
    121c:	f85d03a9 	ldur	x9, [x29, #-48]
    1220:	eb09011f 	cmp	x8, x9
    1224:	54000320 	b.eq	1288 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1288>  // b.none
    1228:	1400003a 	b	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>
    122c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	122c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x33f
    1230:	91000109 	add	x9, x8, #0x0	1230: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x33f
    1234:	52803802 	mov	w2, #0x1c0                 	// #448
    1238:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1238: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x366
    123c:	91000108 	add	x8, x8, #0x0	123c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x366
    1240:	a90627e8 	stp	x8, x9, [sp, #96]
    1244:	f9403fe8 	ldr	x8, [sp, #120]
    1248:	f9401508 	ldr	x8, [x8, #40]
    124c:	f85d03a9 	ldur	x9, [x29, #-48]
    1250:	eb09011f 	cmp	x8, x9
    1254:	540001a0 	b.eq	1288 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1288>  // b.none
    1258:	1400002e 	b	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>
    125c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	125c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x275
    1260:	91000109 	add	x9, x8, #0x0	1260: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x275
    1264:	52802b02 	mov	w2, #0x158                 	// #344
    1268:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1268: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2dd
    126c:	91000108 	add	x8, x8, #0x0	126c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2dd
    1270:	a90627e8 	stp	x8, x9, [sp, #96]
    1274:	f9403fe8 	ldr	x8, [sp, #120]
    1278:	f9401508 	ldr	x8, [x8, #40]
    127c:	f85d03a9 	ldur	x9, [x29, #-48]
    1280:	eb09011f 	cmp	x8, x9
    1284:	54000461 	b.ne	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>  // b.any
    1288:	a94603e3 	ldp	x3, x0, [sp, #96]
    128c:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	128c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a2
    1290:	91000021 	add	x1, x1, #0x0	1290: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a2
    1294:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1294: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x310
    1298:	91000084 	add	x4, x4, #0x0	1298: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x310
    129c:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	129c: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
    12a0:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	12a0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2dd
    12a4:	91000109 	add	x9, x8, #0x0	12a4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2dd
    12a8:	52802b02 	mov	w2, #0x158                 	// #344
    12ac:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	12ac: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x275
    12b0:	91000108 	add	x8, x8, #0x0	12b0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x275
    12b4:	a90623e9 	stp	x9, x8, [sp, #96]
    12b8:	f9403fe8 	ldr	x8, [sp, #120]
    12bc:	f9401508 	ldr	x8, [x8, #40]
    12c0:	f85d03a9 	ldur	x9, [x29, #-48]
    12c4:	eb09011f 	cmp	x8, x9
    12c8:	54fffe00 	b.eq	1288 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1288>  // b.none
    12cc:	14000011 	b	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>
    12d0:	14000001 	b	12d4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x12d4>
    12d4:	aa0003f4 	mov	x20, x0
    12d8:	94000000 	bl	0 <std::__ndk1::chrono::steady_clock::now()>	12d8: R_AARCH64_CALL26	std::__ndk1::chrono::steady_clock::now()
    12dc:	f9403be8 	ldr	x8, [sp, #112]
    12e0:	cb080000 	sub	x0, x0, x8
    12e4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	12e4: R_AARCH64_ADR_GOT_PAGE	g_spart_prof
    12e8:	f9400108 	ldr	x8, [x8]	12e8: R_AARCH64_LD64_GOT_LO12_NC	g_spart_prof
    12ec:	91002101 	add	x1, x8, #0x8
    12f0:	94000000 	bl	0 <__aarch64_ldadd8_relax>	12f0: R_AARCH64_CALL26	__aarch64_ldadd8_relax
    12f4:	f9403fe8 	ldr	x8, [sp, #120]
    12f8:	f9401508 	ldr	x8, [x8, #40]
    12fc:	f85d03a9 	ldur	x9, [x29, #-48]
    1300:	eb09011f 	cmp	x8, x9
    1304:	54000061 	b.ne	1310 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1310>  // b.any
    1308:	aa1403e0 	mov	x0, x20
    130c:	94000000 	bl	0 <_Unwind_Resume>	130c: R_AARCH64_CALL26	_Unwind_Resume
    1310:	94000000 	bl	0 <__stack_chk_fail>	1310: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak1L21geco_spart_dump_armedEv:

0000000000000000 <Mips2C::jak1::geco_spart_dump_armed()>:
   0:	d10283ff 	sub	sp, sp, #0xa0
   4:	a9077bfd 	stp	x29, x30, [sp, #112]
   8:	f90043f5 	str	x21, [sp, #128]
   c:	a9094ff4 	stp	x20, x19, [sp, #144]
  10:	9101c3fd 	add	x29, sp, #0x70
  14:	d53bd053 	mrs	x19, tpidr_el0
  18:	90000014 	adrp	x20, 0 <Mips2C::jak1::geco_spart_dump_armed()>	18: R_AARCH64_ADR_PREL_PG_HI21	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  1c:	f9401668 	ldr	x8, [x19, #40]
  20:	f81f83a8 	stur	x8, [x29, #-8]
  24:	f9400288 	ldr	x8, [x20]	24: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  28:	b100091f 	cmn	x8, #0x2
  2c:	540004c1 	b.ne	c4 <Mips2C::jak1::geco_spart_dump_armed()+0xc4>  // b.any
  30:	92800008 	mov	x8, #0xffffffffffffffff    	// #-1
  34:	90000000 	adrp	x0, 0 <Mips2C::jak1::geco_spart_dump_armed()>	34: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x399
  38:	91000000 	add	x0, x0, #0x0	38: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x399
  3c:	f9000288 	str	x8, [x20]	3c: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  40:	94000000 	bl	0 <getenv>	40: R_AARCH64_CALL26	getenv
  44:	6f00e400 	movi	v0.2d, #0x0
  48:	3c84c3e0 	stur	q0, [sp, #76]
  4c:	ad0083e0 	stp	q0, q0, [sp, #16]
  50:	ad0183e0 	stp	q0, q0, [sp, #48]
  54:	3d8003e0 	str	q0, [sp]
  58:	b4000080 	cbz	x0, 68 <Mips2C::jak1::geco_spart_dump_armed()+0x68>
  5c:	39400008 	ldrb	w8, [x0]
  60:	35000188 	cbnz	w8, 90 <Mips2C::jak1::geco_spart_dump_armed()+0x90>
  64:	14000017 	b	c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>
  68:	90000000 	adrp	x0, 0 <Mips2C::jak1::geco_spart_dump_armed()>	68: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3a7
  6c:	91000000 	add	x0, x0, #0x0	6c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3a7
  70:	910003e1 	mov	x1, sp
  74:	94000000 	bl	0 <__system_property_get>	74: R_AARCH64_CALL26	__system_property_get
  78:	2a0003e8 	mov	w8, w0
  7c:	910003e0 	mov	x0, sp
  80:	7100051f 	cmp	w8, #0x1
  84:	540001eb 	b.lt	c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>  // b.tstop
  88:	394003e8 	ldrb	w8, [sp]
  8c:	340001a8 	cbz	w8, c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>
  90:	94000000 	bl	0 <atol>	90: R_AARCH64_CALL26	atol
  94:	f100041f 	cmp	x0, #0x1
  98:	54000061 	b.ne	a4 <Mips2C::jak1::geco_spart_dump_armed()+0xa4>  // b.any
  9c:	aa1f03e8 	mov	x8, xzr
  a0:	14000007 	b	bc <Mips2C::jak1::geco_spart_dump_armed()+0xbc>
  a4:	f100081f 	cmp	x0, #0x2
  a8:	540000cb 	b.lt	c0 <Mips2C::jak1::geco_spart_dump_armed()+0xc0>  // b.tstop
  ac:	aa0003f5 	mov	x21, x0
  b0:	aa1f03e0 	mov	x0, xzr
  b4:	94000000 	bl	0 <time>	b4: R_AARCH64_CALL26	time
  b8:	8b150008 	add	x8, x0, x21
  bc:	f9000288 	str	x8, [x20]	bc: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  c0:	f9400288 	ldr	x8, [x20]	c0: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  c4:	f100051f 	cmp	x8, #0x1
  c8:	5400010b 	b.lt	e8 <Mips2C::jak1::geco_spart_dump_armed()+0xe8>  // b.tstop
  cc:	aa1f03e0 	mov	x0, xzr
  d0:	94000000 	bl	0 <time>	d0: R_AARCH64_CALL26	time
  d4:	f9400288 	ldr	x8, [x20]	d4: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  d8:	eb08001f 	cmp	x0, x8
  dc:	5400006b 	b.lt	e8 <Mips2C::jak1::geco_spart_dump_armed()+0xe8>  // b.tstop
  e0:	aa1f03e8 	mov	x8, xzr
  e4:	f900029f 	str	xzr, [x20]	e4: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
  e8:	f9401669 	ldr	x9, [x19, #40]
  ec:	f85f83aa 	ldur	x10, [x29, #-8]
  f0:	f100011f 	cmp	x8, #0x0
  f4:	1a9f17e0 	cset	w0, eq	// eq = none
  f8:	eb0a013f 	cmp	x9, x10
  fc:	540000c1 	b.ne	114 <Mips2C::jak1::geco_spart_dump_armed()+0x114>  // b.any
 100:	a9494ff4 	ldp	x20, x19, [sp, #144]
 104:	f94043f5 	ldr	x21, [sp, #128]
 108:	a9477bfd 	ldp	x29, x30, [sp, #112]
 10c:	910283ff 	add	sp, sp, #0xa0
 110:	d65f03c0 	ret
 114:	94000000 	bl	0 <__stack_chk_fail>	114: R_AARCH64_CALL26	__stack_chk_fail

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::link()>:
   0:	d10143ff 	sub	sp, sp, #0x50
   4:	a9027bfd 	stp	x29, x30, [sp, #32]
   8:	f9001bf5 	str	x21, [sp, #48]
   c:	a9044ff4 	stp	x20, x19, [sp, #64]
  10:	910083fd 	add	x29, sp, #0x20
  14:	d53bd054 	mrs	x20, tpidr_el0
  18:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	18: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1
  1c:	91000000 	add	x0, x0, #0x0	1c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1
  20:	f9401688 	ldr	x8, [x20, #40]
  24:	f81f83a8 	stur	x8, [x29, #-8]
  28:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	28: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  2c:	90000013 	adrp	x19, 0 <g_ee_main_mem>	2c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  30:	90000015 	adrp	x21, 0 <Mips2C::jak1::sp_process_block_2d::link()>	30: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::cache
  34:	7100001f 	cmp	w0, #0x0
  38:	f9400273 	ldr	x19, [x19]	38: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  3c:	f9400268 	ldr	x8, [x19]
  40:	f94002b5 	ldr	x21, [x21]	40: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
  44:	8b204108 	add	x8, x8, w0, uxtw
  48:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	48: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x1d
  4c:	91000000 	add	x0, x0, #0x0	4c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x1d
  50:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  54:	f90002a8 	str	x8, [x21]
  58:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	58: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  5c:	f9400268 	ldr	x8, [x19]
  60:	7100001f 	cmp	w0, #0x0
  64:	8b204108 	add	x8, x8, w0, uxtw
  68:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	68: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x23e
  6c:	91000000 	add	x0, x0, #0x0	6c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x23e
  70:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  74:	f90006a8 	str	x8, [x21, #8]
  78:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	78: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  7c:	f9400268 	ldr	x8, [x19]
  80:	7100001f 	cmp	w0, #0x0
  84:	8b204108 	add	x8, x8, w0, uxtw
  88:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	88: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x249
  8c:	91000000 	add	x0, x0, #0x0	8c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x249
  90:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  94:	f9000aa8 	str	x8, [x21, #16]
  98:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	98: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  9c:	f9400268 	ldr	x8, [x19]
  a0:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::link()>	a0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x261
  a4:	9100016b 	add	x11, x11, #0x0	a4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x261
  a8:	5285ad6a 	mov	w10, #0x2d6b                	// #11627
  ac:	3dc00160 	ldr	q0, [x11]
  b0:	7100001f 	cmp	w0, #0x0
  b4:	8b204108 	add	x8, x8, w0, uxtw
  b8:	528004c9 	mov	w9, #0x26                  	// #38
  bc:	72ac864a 	movk	w10, #0x6432, lsl #16
  c0:	390003e9 	strb	w9, [sp]
  c4:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  c8:	b90013ea 	str	w10, [sp, #16]
  cc:	3c8013e0 	stur	q0, [sp, #1]
  d0:	f9000ea8 	str	x8, [x21, #24]
  d4:	390053ff 	strb	wzr, [sp, #20]
  d8:	90000000 	adrp	x0, 0 <Mips2C::gLinkedFunctionTable>	d8: R_AARCH64_ADR_GOT_PAGE	Mips2C::gLinkedFunctionTable
  dc:	90000002 	adrp	x2, 0 <Mips2C::jak1::sp_process_block_2d::link()>	dc: R_AARCH64_ADR_GOT_PAGE	Mips2C::jak1::sp_process_block_2d::execute(void*)
  e0:	910003e1 	mov	x1, sp
  e4:	f9400000 	ldr	x0, [x0]	e4: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::gLinkedFunctionTable
  e8:	f9400042 	ldr	x2, [x2]	e8: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::jak1::sp_process_block_2d::execute(void*)
  ec:	52802003 	mov	w3, #0x100                 	// #256
  f0:	94000000 	bl	0 <Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)>	f0: R_AARCH64_CALL26	Mips2C::LinkedFunctionTable::reg(std::__ndk1::basic_string<char, std::__ndk1::char_traits<char>, std::__ndk1::allocator<char> > const&, unsigned long (*)(void*), unsigned int)
  f4:	394003e8 	ldrb	w8, [sp]
  f8:	36000068 	tbz	w8, #0, 104 <Mips2C::jak1::sp_process_block_2d::link()+0x104>
  fc:	f9400be0 	ldr	x0, [sp, #16]
 100:	94000000 	bl	0 <operator delete(void*)>	100: R_AARCH64_CALL26	operator delete(void*)
 104:	f9401688 	ldr	x8, [x20, #40]
 108:	f85f83a9 	ldur	x9, [x29, #-8]
 10c:	eb09011f 	cmp	x8, x9
 110:	54000221 	b.ne	154 <Mips2C::jak1::sp_process_block_2d::link()+0x154>  // b.any
 114:	a9444ff4 	ldp	x20, x19, [sp, #64]
 118:	f9401bf5 	ldr	x21, [sp, #48]
 11c:	a9427bfd 	ldp	x29, x30, [sp, #32]
 120:	910143ff 	add	sp, sp, #0x50
 124:	d65f03c0 	ret
 128:	394003e8 	ldrb	w8, [sp]
 12c:	aa0003f3 	mov	x19, x0
 130:	36000068 	tbz	w8, #0, 13c <Mips2C::jak1::sp_process_block_2d::link()+0x13c>
 134:	f9400be0 	ldr	x0, [sp, #16]
 138:	94000000 	bl	0 <operator delete(void*)>	138: R_AARCH64_CALL26	operator delete(void*)
 13c:	f9401688 	ldr	x8, [x20, #40]
 140:	f85f83a9 	ldur	x9, [x29, #-8]
 144:	eb09011f 	cmp	x8, x9
 148:	54000061 	b.ne	154 <Mips2C::jak1::sp_process_block_2d::link()+0x154>  // b.any
 14c:	aa1303e0 	mov	x0, x19
 150:	94000000 	bl	0 <_Unwind_Resume>	150: R_AARCH64_CALL26	_Unwind_Resume
 154:	94000000 	bl	0 <__stack_chk_fail>	154: R_AARCH64_CALL26	__stack_chk_fail

EXIT 0
