$ aarch64-linux-gnu-objdump -drwC /home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/arm-clang-after.o

/home/emeric/code/jak-project/.autoport/reports/perf-mips2c-neon/notes/attempt9/arm-clang-after.o:     file format elf64-littleaarch64


Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::execute(void*)>:
   0:	d103c3ff 	sub	sp, sp, #0xf0
   4:	6d072beb 	stp	d11, d10, [sp, #112]
   8:	6d0823e9 	stp	d9, d8, [sp, #128]
   c:	a9097bfd 	stp	x29, x30, [sp, #144]
  10:	a90a6ffc 	stp	x28, x27, [sp, #160]
  14:	a90b67fa 	stp	x26, x25, [sp, #176]
  18:	a90c5ff8 	stp	x24, x23, [sp, #192]
  1c:	a90d57f6 	stp	x22, x21, [sp, #208]
  20:	a90e4ff4 	stp	x20, x19, [sp, #224]
  24:	910243fd 	add	x29, sp, #0x90
  28:	aa0003f4 	mov	x20, x0
  2c:	94000000 	bl	0 <std::chrono::_V2::steady_clock::now()>	2c: R_AARCH64_CALL26	std::chrono::_V2::steady_clock::now()
  30:	f9000fe0 	str	x0, [sp, #24]
  34:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	34: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof+0x20
  38:	91000021 	add	x1, x1, #0x0	38: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof+0x20
  3c:	52800020 	mov	w0, #0x1                   	// #1
  40:	94000000 	bl	0 <__aarch64_ldadd8_relax>	40: R_AARCH64_CALL26	__aarch64_ldadd8_relax
  44:	90000019 	adrp	x25, 0 <g_ee_main_mem>	44: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  48:	f940ea88 	ldr	x8, [x20, #464]
  4c:	aa1403fa 	mov	x26, x20
  50:	f9400339 	ldr	x25, [x25]	50: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  54:	f940fa8a 	ldr	x10, [x20, #496]
  58:	d1028108 	sub	x8, x8, #0xa0
  5c:	f9400329 	ldr	x9, [x25]
  60:	f900ea88 	str	x8, [x20, #464]
  64:	f828492a 	str	x10, [x9, w8, uxtw]
  68:	f9400328 	ldr	x8, [x25]
  6c:	b941d289 	ldr	w9, [x20, #464]
  70:	f940f28a 	ldr	x10, [x20, #480]
  74:	8b090108 	add	x8, x8, x9
  78:	f900050a 	str	x10, [x8, #8]
  7c:	b941d288 	ldr	w8, [x20, #464]
  80:	f940ca89 	ldr	x9, [x20, #400]
  84:	f940032a 	ldr	x10, [x25]
  88:	3dc04280 	ldr	q0, [x20, #256]
  8c:	1100c108 	add	w8, w8, #0x30
  90:	f900f289 	str	x9, [x20, #480]
  94:	927c6d08 	and	x8, x8, #0xfffffff0
  98:	3ca86940 	str	q0, [x10, x8]
  9c:	b941d288 	ldr	w8, [x20, #464]
  a0:	f9400329 	ldr	x9, [x25]
  a4:	3dc04680 	ldr	q0, [x20, #272]
  a8:	11010108 	add	w8, w8, #0x40
  ac:	927c6d08 	and	x8, x8, #0xfffffff0
  b0:	3ca86920 	str	q0, [x9, x8]
  b4:	b941d288 	ldr	w8, [x20, #464]
  b8:	f9400329 	ldr	x9, [x25]
  bc:	3dc04a80 	ldr	q0, [x20, #288]
  c0:	11014108 	add	w8, w8, #0x50
  c4:	927c6d08 	and	x8, x8, #0xfffffff0
  c8:	3ca86920 	str	q0, [x9, x8]
  cc:	b941d288 	ldr	w8, [x20, #464]
  d0:	f9400329 	ldr	x9, [x25]
  d4:	3dc04e80 	ldr	q0, [x20, #304]
  d8:	11018108 	add	w8, w8, #0x60
  dc:	927c6d08 	and	x8, x8, #0xfffffff0
  e0:	3ca86920 	str	q0, [x9, x8]
  e4:	b941d288 	ldr	w8, [x20, #464]
  e8:	f9400329 	ldr	x9, [x25]
  ec:	3dc05280 	ldr	q0, [x20, #320]
  f0:	1101c108 	add	w8, w8, #0x70
  f4:	927c6d08 	and	x8, x8, #0xfffffff0
  f8:	3ca86920 	str	q0, [x9, x8]
  fc:	b941d288 	ldr	w8, [x20, #464]
 100:	f9400329 	ldr	x9, [x25]
 104:	3dc05680 	ldr	q0, [x20, #336]
 108:	11020108 	add	w8, w8, #0x80
 10c:	927c6d08 	and	x8, x8, #0xfffffff0
 110:	3ca86920 	str	q0, [x9, x8]
 114:	b941d288 	ldr	w8, [x20, #464]
 118:	f9400329 	ldr	x9, [x25]
 11c:	3dc07280 	ldr	q0, [x20, #448]
 120:	11024108 	add	w8, w8, #0x90
 124:	927c6d08 	and	x8, x8, #0xfffffff0
 128:	3ca86920 	str	q0, [x9, x8]
 12c:	f8440f48 	ldr	x8, [x26, #64]!
 130:	f9400b49 	ldr	x9, [x26, #16]
 134:	f940134a 	ldr	x10, [x26, #32]
 138:	f900e288 	str	x8, [x20, #448]
 13c:	f9401b48 	ldr	x8, [x26, #48]
 140:	f900aa89 	str	x9, [x20, #336]
 144:	f9402349 	ldr	x9, [x26, #64]
 148:	f900a28a 	str	x10, [x20, #320]
 14c:	f940ea8a 	ldr	x10, [x20, #464]
 150:	f9008288 	str	x8, [x20, #256]
 154:	f9402b48 	ldr	x8, [x26, #80]
 158:	f9009a89 	str	x9, [x20, #304]
 15c:	f9400329 	ldr	x9, [x25]
 160:	9100414a 	add	x10, x10, #0x10
 164:	f9009288 	str	x8, [x20, #288]
 168:	927c6d48 	and	x8, x10, #0xfffffff0
 16c:	8b080128 	add	x8, x9, x8
 170:	f9008a8a 	str	x10, [x20, #272]
 174:	a9007d1f 	stp	xzr, xzr, [x8]
 178:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	178: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_3d::cache
 17c:	f9400108 	ldr	x8, [x8]	17c: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
 180:	b9800108 	ldrsw	x8, [x8]
 184:	72000d1f 	tst	w8, #0xf
 188:	f81f0348 	stur	x8, [x26, #-16]
 18c:	54006261 	b.ne	dd8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdd8>  // b.any
 190:	f9400329 	ldr	x9, [x25]
 194:	927c6d08 	and	x8, x8, #0xfffffff0
 198:	2f00e408 	movi	d8, #0x0
 19c:	2f00e409 	movi	d9, #0x0
 1a0:	1e2e100a 	fmov	s10, #1.000000000000000000e+00
 1a4:	90000017 	adrp	x23, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	1a4: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof+0x40
 1a8:	910002f7 	add	x23, x23, #0x0	1a8: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof+0x40
 1ac:	3ce86920 	ldr	q0, [x9, x8]
 1b0:	b941d288 	ldr	w8, [x20, #464]
 1b4:	910bf35c 	add	x28, x26, #0x2fc
 1b8:	910c4295 	add	x21, x20, #0x310
 1bc:	92800016 	mov	x22, #0xffffffffffffffff    	// #-1
 1c0:	3d80e280 	str	q0, [x20, #896]
 1c4:	11008108 	add	w8, w8, #0x20
 1c8:	90000013 	adrp	x19, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	1c8: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_3d::cache+0x8
 1cc:	f941c68a 	ldr	x10, [x20, #904]
 1d0:	394e028b 	ldrb	w11, [x20, #896]
 1d4:	927c6d08 	and	x8, x8, #0xfffffff0
 1d8:	8b080128 	add	x8, x9, x8
 1dc:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	1dc: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3ee
 1e0:	91000129 	add	x9, x9, #0x0	1e0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3ee
 1e4:	a9032a8b 	stp	x11, x10, [x20, #48]
 1e8:	a900290b 	stp	x11, x10, [x8]
 1ec:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	1ec: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3e9
 1f0:	91000108 	add	x8, x8, #0x0	1f0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3e9
 1f4:	f940aa9b 	ldr	x27, [x20, #336]
 1f8:	a900a3e9 	stp	x9, x8, [sp, #8]
 1fc:	3d800be0 	str	q0, [sp, #32]
 200:	1400000e 	b	238 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x238>
 204:	f9409a88 	ldr	x8, [x20, #304]
 208:	f940aa89 	ldr	x9, [x20, #336]
 20c:	f940a28a 	ldr	x10, [x20, #320]
 210:	f940828b 	ldr	x11, [x20, #256]
 214:	f1000508 	subs	x8, x8, #0x1
 218:	9102413b 	add	x27, x9, #0x90
 21c:	f9009a88 	str	x8, [x20, #304]
 220:	9100c148 	add	x8, x10, #0x30
 224:	91000578 	add	x24, x11, #0x1
 228:	f900aa9b 	str	x27, [x20, #336]
 22c:	f900a288 	str	x8, [x20, #320]
 230:	f9008298 	str	x24, [x20, #256]
 234:	54005120 	b.eq	c58 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xc58>  // b.none
 238:	52800020 	mov	w0, #0x1                   	// #1
 23c:	aa1703e1 	mov	x1, x23
 240:	94000000 	bl	0 <__aarch64_ldadd8_relax>	240: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 244:	f9400325 	ldr	x5, [x25]
 248:	92407f69 	and	x9, x27, #0xffffffff
 24c:	b941728b 	ldr	w11, [x20, #368]
 250:	8b0900a8 	add	x8, x5, x9
 254:	b980810a 	ldrsw	x10, [x8, #128]
 258:	6b0b015f 	cmp	w10, w11
 25c:	f9001a8a 	str	x10, [x20, #48]
 260:	54fffd20 	b.eq	204 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x204>  // b.none
 264:	b941228c 	ldr	w12, [x20, #288]
 268:	b980690a 	ldrsw	x10, [x8, #104]
 26c:	6b0b019f 	cmp	w12, w11
 270:	f9001a8a 	str	x10, [x20, #48]
 274:	54000300 	b.eq	2d4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d4>  // b.none
 278:	9273014b 	and	x11, x10, #0x2000
 27c:	f9001a8b 	str	x11, [x20, #48]
 280:	376802aa 	tbnz	w10, #13, 2d4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x2d4>
 284:	b9806509 	ldrsw	x9, [x8, #100]
 288:	f9002296 	str	x22, [x20, #64]
 28c:	f9001a89 	str	x9, [x20, #48]
 290:	34004a69 	cbz	w9, bdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
 294:	b9806909 	ldrsw	x9, [x8, #104]
 298:	927a012a 	and	x10, x9, #0x40
 29c:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
 2a0:	f9001a8a 	str	x10, [x20, #48]
 2a4:	f900228b 	str	x11, [x20, #64]
 2a8:	b900690b 	str	w11, [x8, #104]
 2ac:	3637fac9 	tbz	w9, #6, 204 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x204>
 2b0:	f9400328 	ldr	x8, [x25]
 2b4:	b9415289 	ldr	w9, [x20, #336]
 2b8:	b941428a 	ldr	w10, [x20, #320]
 2bc:	8b090109 	add	x9, x8, x9
 2c0:	8b0a0108 	add	x8, x8, x10
 2c4:	b9807d29 	ldrsw	x9, [x9, #124]
 2c8:	f9001a89 	str	x9, [x20, #48]
 2cc:	b9002d09 	str	w9, [x8, #44]
 2d0:	17ffffcd 	b	204 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x204>
 2d4:	b941d28b 	ldr	w11, [x20, #464]
 2d8:	b980650a 	ldrsw	x10, [x8, #100]
 2dc:	f9002296 	str	x22, [x20, #64]
 2e0:	1100816b 	add	w11, w11, #0x20
 2e4:	f9001a8a 	str	x10, [x20, #48]
 2e8:	3100055f 	cmn	w10, #0x1
 2ec:	927c6d6b 	and	x11, x11, #0xfffffff0
 2f0:	3ceb68a0 	ldr	q0, [x5, x11]
 2f4:	3d800340 	str	q0, [x26]
 2f8:	54000260 	b.eq	344 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x344>  // b.none
 2fc:	f9402289 	ldr	x9, [x20, #64]
 300:	6f00e401 	movi	v1.2d, #0x0
 304:	cb090149 	sub	x9, x10, x9
 308:	1e270120 	fmov	s0, w9
 30c:	d360fd2b 	lsr	x11, x9, #32
 310:	f9002289 	str	x9, [x20, #64]
 314:	4e0c1d60 	mov	v0.s[1], w11
 318:	9101228b 	add	x11, x20, #0x48
 31c:	4d408160 	ld1	{v0.s}[2], [x11]
 320:	9101328b 	add	x11, x20, #0x4c
 324:	4d409160 	ld1	{v0.s}[3], [x11]
 328:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
 32c:	3d800e80 	str	q0, [x20, #48]
 330:	3400456a 	cbz	w10, bdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
 334:	f9401a89 	ldr	x9, [x20, #48]
 338:	b9006509 	str	w9, [x8, #100]
 33c:	f9400325 	ldr	x5, [x25]
 340:	b9415289 	ldr	w9, [x20, #336]
 344:	8b0900a8 	add	x8, x5, x9
 348:	b9806909 	ldrsw	x9, [x8, #104]
 34c:	927a012a 	and	x10, x9, #0x40
 350:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
 354:	f9001a8a 	str	x10, [x20, #48]
 358:	f900228b 	str	x11, [x20, #64]
 35c:	b900690b 	str	w11, [x8, #104]
 360:	36300129 	tbz	w9, #6, 384 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x384>
 364:	f9400328 	ldr	x8, [x25]
 368:	b9415289 	ldr	w9, [x20, #336]
 36c:	b941428a 	ldr	w10, [x20, #320]
 370:	8b090109 	add	x9, x8, x9
 374:	8b0a0108 	add	x8, x8, x10
 378:	b9807d29 	ldrsw	x9, [x9, #124]
 37c:	f9001a89 	str	x9, [x20, #48]
 380:	b9002d09 	str	w9, [x8, #44]
 384:	f9400328 	ldr	x8, [x25]
 388:	b941528a 	ldr	w10, [x20, #336]
 38c:	8b0a0109 	add	x9, x8, x10
 390:	b980712b 	ldrsw	x11, [x9, #112]
 394:	f940ea89 	ldr	x9, [x20, #464]
 398:	f900ca8b 	str	x11, [x20, #400]
 39c:	34000b8b 	cbz	w11, 50c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x50c>
 3a0:	d1018129 	sub	x9, x9, #0x60
 3a4:	3dc07280 	ldr	q0, [x20, #448]
 3a8:	f900ea89 	str	x9, [x20, #464]
 3ac:	927c6d29 	and	x9, x9, #0xfffffff0
 3b0:	3ca96900 	str	q0, [x8, x9]
 3b4:	b941d288 	ldr	w8, [x20, #464]
 3b8:	f9400329 	ldr	x9, [x25]
 3bc:	3dc05680 	ldr	q0, [x20, #336]
 3c0:	11004108 	add	w8, w8, #0x10
 3c4:	927c6d08 	and	x8, x8, #0xfffffff0
 3c8:	3ca86920 	str	q0, [x9, x8]
 3cc:	b941d288 	ldr	w8, [x20, #464]
 3d0:	f9400329 	ldr	x9, [x25]
 3d4:	3dc05280 	ldr	q0, [x20, #320]
 3d8:	11008108 	add	w8, w8, #0x20
 3dc:	927c6d08 	and	x8, x8, #0xfffffff0
 3e0:	3ca86920 	str	q0, [x9, x8]
 3e4:	b941d288 	ldr	w8, [x20, #464]
 3e8:	f9400329 	ldr	x9, [x25]
 3ec:	3dc04280 	ldr	q0, [x20, #256]
 3f0:	1100c108 	add	w8, w8, #0x30
 3f4:	927c6d08 	and	x8, x8, #0xfffffff0
 3f8:	3ca86920 	str	q0, [x9, x8]
 3fc:	b941d288 	ldr	w8, [x20, #464]
 400:	f9400329 	ldr	x9, [x25]
 404:	3dc04e80 	ldr	q0, [x20, #304]
 408:	11010108 	add	w8, w8, #0x40
 40c:	927c6d08 	and	x8, x8, #0xfffffff0
 410:	3ca86920 	str	q0, [x9, x8]
 414:	f940e288 	ldr	x8, [x20, #448]
 418:	b941d28a 	ldr	w10, [x20, #464]
 41c:	f940aa89 	ldr	x9, [x20, #336]
 420:	f940a28b 	ldr	x11, [x20, #320]
 424:	f940032c 	ldr	x12, [x25]
 428:	3dc04a80 	ldr	q0, [x20, #288]
 42c:	f9002288 	str	x8, [x20, #64]
 430:	11014148 	add	w8, w10, #0x50
 434:	f9002a89 	str	x9, [x20, #80]
 438:	927c6d09 	and	x9, x8, #0xfffffff0
 43c:	b9419288 	ldr	w8, [x20, #400]
 440:	f900328b 	str	x11, [x20, #96]
 444:	3ca96980 	str	q0, [x12, x9]
 448:	f9402289 	ldr	x9, [x20, #64]
 44c:	f9402a8a 	ldr	x10, [x20, #80]
 450:	f940328b 	ldr	x11, [x20, #96]
 454:	a9032be9 	stp	x9, x10, [sp, #48]
 458:	f9403a89 	ldr	x9, [x20, #112]
 45c:	f940428a 	ldr	x10, [x20, #128]
 460:	a90427eb 	stp	x11, x9, [sp, #64]
 464:	f9404a8b 	ldr	x11, [x20, #144]
 468:	f9405289 	ldr	x9, [x20, #160]
 46c:	a9052fea 	stp	x10, x11, [sp, #80]
 470:	f9405a8a 	ldr	x10, [x20, #176]
 474:	a9062be9 	stp	x9, x10, [sp, #96]
 478:	340045e8 	cbz	w8, d34 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd34>
 47c:	f9400325 	ldr	x5, [x25]
 480:	f940b283 	ldr	x3, [x20, #352]
 484:	f940ba84 	ldr	x4, [x20, #368]
 488:	8b0800a0 	add	x0, x5, x8
 48c:	9100c3e1 	add	x1, sp, #0x30
 490:	aa1f03e2 	mov	x2, xzr
 494:	94000000 	bl	0 <_call_goal8_asm_systemv>	494: R_AARCH64_CALL26	_call_goal8_asm_systemv
 498:	f940ea89 	ldr	x9, [x20, #464]
 49c:	f9400328 	ldr	x8, [x25]
 4a0:	f9001280 	str	x0, [x20, #32]
 4a4:	927c6d2a 	and	x10, x9, #0xfffffff0
 4a8:	3cea6900 	ldr	q0, [x8, x10]
 4ac:	1100412a 	add	w10, w9, #0x10
 4b0:	927c6d4a 	and	x10, x10, #0xfffffff0
 4b4:	3d807280 	str	q0, [x20, #448]
 4b8:	3cea6900 	ldr	q0, [x8, x10]
 4bc:	1100812a 	add	w10, w9, #0x20
 4c0:	927c6d4a 	and	x10, x10, #0xfffffff0
 4c4:	3d805680 	str	q0, [x20, #336]
 4c8:	3cea6900 	ldr	q0, [x8, x10]
 4cc:	1100c12a 	add	w10, w9, #0x30
 4d0:	927c6d4a 	and	x10, x10, #0xfffffff0
 4d4:	3d805280 	str	q0, [x20, #320]
 4d8:	3cea6900 	ldr	q0, [x8, x10]
 4dc:	1101012a 	add	w10, w9, #0x40
 4e0:	927c6d4a 	and	x10, x10, #0xfffffff0
 4e4:	3d804280 	str	q0, [x20, #256]
 4e8:	3cea6900 	ldr	q0, [x8, x10]
 4ec:	1101412a 	add	w10, w9, #0x50
 4f0:	91018129 	add	x9, x9, #0x60
 4f4:	927c6d4a 	and	x10, x10, #0xfffffff0
 4f8:	3d804e80 	str	q0, [x20, #304]
 4fc:	3cea6900 	ldr	q0, [x8, x10]
 500:	b941528a 	ldr	w10, [x20, #336]
 504:	f900ea89 	str	x9, [x20, #464]
 508:	3d804a80 	str	q0, [x20, #288]
 50c:	8b0a010a 	add	x10, x8, x10
 510:	11008129 	add	w9, w9, #0x20
 514:	b980794c 	ldrsw	x12, [x10, #120]
 518:	927c6d29 	and	x9, x9, #0xfffffff0
 51c:	f9002a8c 	str	x12, [x20, #80]
 520:	b980754b 	ldrsw	x11, [x10, #116]
 524:	f9001a8b 	str	x11, [x20, #48]
 528:	3ce96900 	ldr	q0, [x8, x9]
 52c:	3d800340 	str	q0, [x26]
 530:	34000cac 	cbz	w12, 6c4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6c4>
 534:	f9402288 	ldr	x8, [x20, #64]
 538:	eb080168 	subs	x8, x11, x8
 53c:	f9001a88 	str	x8, [x20, #48]
 540:	b9007548 	str	w8, [x10, #116]
 544:	54000c05 	b.pl	6c4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x6c4>  // b.nfrst
 548:	f940ea88 	ldr	x8, [x20, #464]
 54c:	f9400329 	ldr	x9, [x25]
 550:	3dc07280 	ldr	q0, [x20, #448]
 554:	d1018108 	sub	x8, x8, #0x60
 558:	f900ea88 	str	x8, [x20, #464]
 55c:	927c6d08 	and	x8, x8, #0xfffffff0
 560:	3ca86920 	str	q0, [x9, x8]
 564:	b941d288 	ldr	w8, [x20, #464]
 568:	f9400329 	ldr	x9, [x25]
 56c:	3dc05680 	ldr	q0, [x20, #336]
 570:	11004108 	add	w8, w8, #0x10
 574:	927c6d08 	and	x8, x8, #0xfffffff0
 578:	3ca86920 	str	q0, [x9, x8]
 57c:	b941d288 	ldr	w8, [x20, #464]
 580:	f9400329 	ldr	x9, [x25]
 584:	3dc05280 	ldr	q0, [x20, #320]
 588:	11008108 	add	w8, w8, #0x20
 58c:	927c6d08 	and	x8, x8, #0xfffffff0
 590:	3ca86920 	str	q0, [x9, x8]
 594:	b941d288 	ldr	w8, [x20, #464]
 598:	f9400329 	ldr	x9, [x25]
 59c:	3dc04280 	ldr	q0, [x20, #256]
 5a0:	1100c108 	add	w8, w8, #0x30
 5a4:	927c6d08 	and	x8, x8, #0xfffffff0
 5a8:	3ca86920 	str	q0, [x9, x8]
 5ac:	b941d288 	ldr	w8, [x20, #464]
 5b0:	f9400329 	ldr	x9, [x25]
 5b4:	3dc04e80 	ldr	q0, [x20, #304]
 5b8:	11010108 	add	w8, w8, #0x40
 5bc:	927c6d08 	and	x8, x8, #0xfffffff0
 5c0:	3ca86920 	str	q0, [x9, x8]
 5c4:	b941d288 	ldr	w8, [x20, #464]
 5c8:	f9400329 	ldr	x9, [x25]
 5cc:	3dc04a80 	ldr	q0, [x20, #288]
 5d0:	11014108 	add	w8, w8, #0x50
 5d4:	927c6d08 	and	x8, x8, #0xfffffff0
 5d8:	3ca86920 	str	q0, [x9, x8]
 5dc:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	5dc: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_3d::cache+0x18
 5e0:	f940e289 	ldr	x9, [x20, #448]
 5e4:	f940a28a 	ldr	x10, [x20, #320]
 5e8:	f940aa8b 	ldr	x11, [x20, #336]
 5ec:	f9400108 	ldr	x8, [x8]	5ec: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache+0x18
 5f0:	b981f28c 	ldrsw	x12, [x20, #496]
 5f4:	f9002289 	str	x9, [x20, #64]
 5f8:	f9003a8a 	str	x10, [x20, #112]
 5fc:	f900328b 	str	x11, [x20, #96]
 600:	b9800108 	ldrsw	x8, [x8]
 604:	f900128c 	str	x12, [x20, #32]
 608:	f9402a8c 	ldr	x12, [x20, #80]
 60c:	a9042beb 	stp	x11, x10, [sp, #64]
 610:	f9404a8b 	ldr	x11, [x20, #144]
 614:	f9405a8a 	ldr	x10, [x20, #176]
 618:	a90333e9 	stp	x9, x12, [sp, #48]
 61c:	f9404289 	ldr	x9, [x20, #128]
 620:	f900ca88 	str	x8, [x20, #400]
 624:	a9052fe9 	stp	x9, x11, [sp, #80]
 628:	f9405289 	ldr	x9, [x20, #160]
 62c:	a9062be9 	stp	x9, x10, [sp, #96]
 630:	34003828 	cbz	w8, d34 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd34>
 634:	f9400325 	ldr	x5, [x25]
 638:	f940b283 	ldr	x3, [x20, #352]
 63c:	92407d08 	and	x8, x8, #0xffffffff
 640:	f940ba84 	ldr	x4, [x20, #368]
 644:	8b0800a0 	add	x0, x5, x8
 648:	9100c3e1 	add	x1, sp, #0x30
 64c:	aa1f03e2 	mov	x2, xzr
 650:	94000000 	bl	0 <_call_goal8_asm_systemv>	650: R_AARCH64_CALL26	_call_goal8_asm_systemv
 654:	f940ea88 	ldr	x8, [x20, #464]
 658:	f9400329 	ldr	x9, [x25]
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
 6cc:	540035e1 	b.ne	d88 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd88>  // b.any
 6d0:	f9400328 	ldr	x8, [x25]
 6d4:	927c6d29 	and	x9, x9, #0xfffffff0
 6d8:	8b09010a 	add	x10, x8, x9
 6dc:	f9400949 	ldr	x9, [x10, #16]
 6e0:	3dc00140 	ldr	q0, [x10]
 6e4:	f9001be9 	str	x9, [sp, #48]
 6e8:	f940aa89 	ldr	x9, [x20, #336]
 6ec:	b940194b 	ldr	w11, [x10, #24]
 6f0:	f2400d3f 	tst	x9, #0xf
 6f4:	b9003beb 	str	w11, [sp, #56]
 6f8:	540035c1 	b.ne	db0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xdb0>  // b.any
 6fc:	927c6d29 	and	x9, x9, #0xfffffff0
 700:	bd438a81 	ldr	s1, [x20, #904]
 704:	bd401d46 	ldr	s6, [x10, #28]
 708:	8b090108 	add	x8, x8, x9
 70c:	3dc00951 	ldr	q17, [x10, #32]
 710:	ad418905 	ldp	q5, q2, [x8, #48]
 714:	bd401904 	ldr	s4, [x8, #24]
 718:	b9806109 	ldrsw	x9, [x8, #96]
 71c:	bd402d07 	ldr	s7, [x8, #44]
 720:	4f819042 	fmul	v2.4s, v2.4s, v1.s[0]
 724:	fd400901 	ldr	d1, [x8, #16]
 728:	5e140443 	mov	s3, v2.s[2]
 72c:	0e22d421 	fadd	v1.2s, v1.2s, v2.2s
 730:	1e232890 	fadd	s16, s4, s3
 734:	3cc1c103 	ldur	q3, [x8, #28]
 738:	bd438684 	ldr	s4, [x20, #900]
 73c:	b9020289 	str	w9, [x20, #512]
 740:	f9001a89 	str	x9, [x20, #48]
 744:	34000209 	cbz	w9, 784 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x784>
 748:	1e270132 	fmov	s18, w9
 74c:	bd438e93 	ldr	s19, [x20, #908]
 750:	1e270135 	fmov	s21, w9
 754:	131f7d2a 	asr	w10, w9, #31
 758:	bd403a94 	ldr	s20, [x20, #56]
 75c:	1e323952 	fsub	s18, s10, s18
 760:	4e0c1d55 	mov	v21.s[1], w10
 764:	1e340a74 	fmul	s20, s19, s20
 768:	1e320a72 	fmul	s18, s19, s18
 76c:	0f9392ab 	fmul	v11.2s, v21.2s, v19.s[0]
 770:	1e323952 	fsub	s18, s10, s18
 774:	6e0c0654 	mov	v20.s[1], v18.s[0]
 778:	0f929021 	fmul	v1.2s, v1.2s, v18.s[0]
 77c:	1e300a50 	fmul	s16, s18, s16
 780:	3d800bf4 	str	q20, [sp, #32]
 784:	0e0c0433 	dup	v19.2s, v1.s[1]
 788:	4f8490b2 	fmul	v18.4s, v5.4s, v4.s[0]
 78c:	1e210894 	fmul	s20, s4, s1
 790:	bd033a90 	str	s16, [x20, #824]
 794:	f9401bea 	ldr	x10, [sp, #48]
 798:	bd034e87 	str	s7, [x20, #844]
 79c:	f90002aa 	str	x10, [x21]
 7a0:	b9403bea 	ldr	w10, [sp, #56]
 7a4:	6e0c0613 	mov	v19.s[1], v16.s[0]
 7a8:	4e32d635 	fadd	v21.4s, v17.4s, v18.4s
 7ac:	1e270891 	fmul	s17, s4, s7
 7b0:	fd019a81 	str	d1, [x20, #816]
 7b4:	3d800383 	str	q3, [x28]
 7b8:	b9000aaa 	str	w10, [x21, #8]
 7bc:	6e180473 	mov	v19.d[1], v3.d[0]
 7c0:	4ea0eab0 	fcmlt	v16.4s, v21.4s, #0.0
 7c4:	1e3128c6 	fadd	s6, s6, s17
 7c8:	ad1a8a85 	stp	q5, q2, [x20, #848]
 7cc:	4f849273 	fmul	v19.4s, v19.4s, v4.s[0]
 7d0:	4e701ea7 	bic	v7.16b, v21.16b, v16.16b
 7d4:	bd031e86 	str	s6, [x20, #796]
 7d8:	3d80ca87 	str	q7, [x20, #800]
 7dc:	6e136016 	ext	v22.16b, v0.16b, v19.16b, #12
 7e0:	6e040696 	mov	v22.s[0], v20.s[0]
 7e4:	4e36d400 	fadd	v0.4s, v0.4s, v22.4s
 7e8:	3d80c280 	str	q0, [x20, #768]
 7ec:	34000089 	cbz	w9, 7fc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x7fc>
 7f0:	3dc00be0 	ldr	q0, [sp, #32]
 7f4:	fd01ba8b 	str	d11, [x20, #880]
 7f8:	fd01be80 	str	d0, [x20, #888]
 7fc:	0e0c3c29 	mov	w9, v1.s[1]
 800:	1e26002a 	fmov	w10, s1
 804:	f9419e8b 	ldr	x11, [x20, #824]
 808:	5f839880 	fmul	s0, s4, v3.s[2]
 80c:	5fa39882 	fmul	s2, s4, v3.s[3]
 810:	bd039294 	str	s20, [x20, #912]
 814:	3c858393 	stur	q19, [x28, #88]
 818:	bd03ae91 	str	s17, [x20, #940]
 81c:	aa098149 	orr	x9, x10, x9, lsl #32
 820:	3d80ee92 	str	q18, [x20, #944]
 824:	bd03a680 	str	s0, [x20, #932]
 828:	bd03aa82 	str	s2, [x20, #936]
 82c:	a9012d09 	stp	x9, x11, [x8, #16]
 830:	f940a288 	ldr	x8, [x20, #320]
 834:	f2400d1f 	tst	x8, #0xf
 838:	54002821 	b.ne	d3c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd3c>  // b.any
 83c:	f9400329 	ldr	x9, [x25]
 840:	927c6d08 	and	x8, x8, #0xfffffff0
 844:	f941828a 	ldr	x10, [x20, #768]
 848:	f941868b 	ldr	x11, [x20, #776]
 84c:	8b080128 	add	x8, x9, x8
 850:	a9002d0a 	stp	x10, x11, [x8]
 854:	f940a288 	ldr	x8, [x20, #320]
 858:	f2400d1f 	tst	x8, #0xf
 85c:	54002701 	b.ne	d3c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd3c>  // b.any
 860:	f9400329 	ldr	x9, [x25]
 864:	927c6d08 	and	x8, x8, #0xfffffff0
 868:	f9418a8a 	ldr	x10, [x20, #784]
 86c:	f9418e8b 	ldr	x11, [x20, #792]
 870:	8b080128 	add	x8, x9, x8
 874:	a9012d0a 	stp	x10, x11, [x8, #16]
 878:	f940a288 	ldr	x8, [x20, #320]
 87c:	f2400d1f 	tst	x8, #0xf
 880:	540025e1 	b.ne	d3c <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd3c>  // b.any
 884:	f9400329 	ldr	x9, [x25]
 888:	927c6d08 	and	x8, x8, #0xfffffff0
 88c:	f941928a 	ldr	x10, [x20, #800]
 890:	f941968b 	ldr	x11, [x20, #808]
 894:	8b080128 	add	x8, x9, x8
 898:	a9022d0a 	stp	x10, x11, [x8, #32]
 89c:	f940a289 	ldr	x9, [x20, #320]
 8a0:	f940032a 	ldr	x10, [x25]
 8a4:	f9408a88 	ldr	x8, [x20, #272]
 8a8:	8b29414b 	add	x11, x10, w9, uxtw
 8ac:	f9001a88 	str	x8, [x20, #48]
 8b0:	f9002289 	str	x9, [x20, #64]
 8b4:	b9401169 	ldr	w9, [x11, #16]
 8b8:	b9020289 	str	w9, [x20, #512]
 8bc:	b940156c 	ldr	w12, [x11, #20]
 8c0:	b902068c 	str	w12, [x20, #516]
 8c4:	b940196b 	ldr	w11, [x11, #24]
 8c8:	b9020e8b 	str	w11, [x20, #524]
 8cc:	b8284949 	str	w9, [x10, w8, uxtw]
 8d0:	f9400328 	ldr	x8, [x25]
 8d4:	b9403289 	ldr	w9, [x20, #48]
 8d8:	b942068a 	ldr	w10, [x20, #516]
 8dc:	8b090108 	add	x8, x8, x9
 8e0:	b900050a 	str	w10, [x8, #4]
 8e4:	f9400328 	ldr	x8, [x25]
 8e8:	b9403289 	ldr	w9, [x20, #48]
 8ec:	b9420e8a 	ldr	w10, [x20, #524]
 8f0:	8b090108 	add	x8, x8, x9
 8f4:	b900090a 	str	w10, [x8, #8]
 8f8:	bd420e80 	ldr	s0, [x20, #524]
 8fc:	bd420681 	ldr	s1, [x20, #516]
 900:	bd420283 	ldr	s3, [x20, #512]
 904:	f9400328 	ldr	x8, [x25]
 908:	b9403289 	ldr	w9, [x20, #48]
 90c:	1e200800 	fmul	s0, s0, s0
 910:	1e210821 	fmul	s1, s1, s1
 914:	1e230863 	fmul	s3, s3, s3
 918:	8b090108 	add	x8, x8, x9
 91c:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	91c: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_3d::cache
 920:	1e203942 	fsub	s2, s10, s0
 924:	bd020e80 	str	s0, [x20, #524]
 928:	1e213841 	fsub	s1, s2, s1
 92c:	bd020a82 	str	s2, [x20, #520]
 930:	7ea3d423 	fabd	s3, s1, s3
 934:	bd020681 	str	s1, [x20, #516]
 938:	1e21c063 	fsqrt	s3, s3
 93c:	bd020283 	str	s3, [x20, #512]
 940:	bd000d03 	str	s3, [x8, #12]
 944:	b9820288 	ldrsw	x8, [x20, #512]
 948:	f9400129 	ldr	x9, [x9]	948: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
 94c:	f9400325 	ldr	x5, [x25]
 950:	f9002288 	str	x8, [x20, #64]
 954:	b9400128 	ldr	w8, [x9]
 958:	93407d09 	sxtw	x9, w8
 95c:	f9001a89 	str	x9, [x20, #48]
 960:	b86868a8 	ldr	w8, [x5, x8]
 964:	92401d09 	and	x9, x8, #0xff
 968:	b9020288 	str	w8, [x20, #512]
 96c:	d1002928 	sub	x8, x9, #0xa
 970:	7100293f 	cmp	w9, #0xa
 974:	f9001a88 	str	x8, [x20, #48]
 978:	540003c3 	b.cc	9f0 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x9f0>  // b.lo, b.ul, b.last
 97c:	f9400268 	ldr	x8, [x19]	97c: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache+0x8
 980:	f9408a89 	ldr	x9, [x20, #272]
 984:	f940aa8a 	ldr	x10, [x20, #336]
 988:	b981f28b 	ldrsw	x11, [x20, #496]
 98c:	b9800108 	ldrsw	x8, [x8]
 990:	f9002289 	str	x9, [x20, #64]
 994:	9101414a 	add	x10, x10, #0x50
 998:	f9002a89 	str	x9, [x20, #80]
 99c:	a90327e9 	stp	x9, x9, [sp, #48]
 9a0:	f9403a89 	ldr	x9, [x20, #112]
 9a4:	f900128b 	str	x11, [x20, #32]
 9a8:	f940428b 	ldr	x11, [x20, #128]
 9ac:	a90427ea 	stp	x10, x9, [sp, #64]
 9b0:	f9404a89 	ldr	x9, [x20, #144]
 9b4:	f900328a 	str	x10, [x20, #96]
 9b8:	f940528a 	ldr	x10, [x20, #160]
 9bc:	a90527eb 	stp	x11, x9, [sp, #80]
 9c0:	f9405a89 	ldr	x9, [x20, #176]
 9c4:	f900ca88 	str	x8, [x20, #400]
 9c8:	a90627ea 	stp	x10, x9, [sp, #96]
 9cc:	34001b48 	cbz	w8, d34 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd34>
 9d0:	f940b283 	ldr	x3, [x20, #352]
 9d4:	f940ba84 	ldr	x4, [x20, #368]
 9d8:	92407d08 	and	x8, x8, #0xffffffff
 9dc:	8b0800a0 	add	x0, x5, x8
 9e0:	9100c3e1 	add	x1, sp, #0x30
 9e4:	aa1f03e2 	mov	x2, xzr
 9e8:	94000000 	bl	0 <_call_goal8_asm_systemv>	9e8: R_AARCH64_CALL26	_call_goal8_asm_systemv
 9ec:	f9001280 	str	x0, [x20, #32]
 9f0:	f9400268 	ldr	x8, [x19]	9f0: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache+0x8
 9f4:	f9408a89 	ldr	x9, [x20, #272]
 9f8:	f940aa8a 	ldr	x10, [x20, #336]
 9fc:	b981f28b 	ldrsw	x11, [x20, #496]
 a00:	b9800108 	ldrsw	x8, [x8]
 a04:	f9002289 	str	x9, [x20, #64]
 a08:	9101414a 	add	x10, x10, #0x50
 a0c:	f9002a89 	str	x9, [x20, #80]
 a10:	a90327e9 	stp	x9, x9, [sp, #48]
 a14:	f9403a89 	ldr	x9, [x20, #112]
 a18:	f900128b 	str	x11, [x20, #32]
 a1c:	f940428b 	ldr	x11, [x20, #128]
 a20:	a90427ea 	stp	x10, x9, [sp, #64]
 a24:	f9404a89 	ldr	x9, [x20, #144]
 a28:	f900328a 	str	x10, [x20, #96]
 a2c:	f940528a 	ldr	x10, [x20, #160]
 a30:	a90527eb 	stp	x11, x9, [sp, #80]
 a34:	f9405a89 	ldr	x9, [x20, #176]
 a38:	f900ca88 	str	x8, [x20, #400]
 a3c:	a90627ea 	stp	x10, x9, [sp, #96]
 a40:	340017a8 	cbz	w8, d34 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd34>
 a44:	f9400325 	ldr	x5, [x25]
 a48:	f940b283 	ldr	x3, [x20, #352]
 a4c:	92407d08 	and	x8, x8, #0xffffffff
 a50:	f940ba84 	ldr	x4, [x20, #368]
 a54:	8b0800a0 	add	x0, x5, x8
 a58:	9100c3e1 	add	x1, sp, #0x30
 a5c:	aa1f03e2 	mov	x2, xzr
 a60:	94000000 	bl	0 <_call_goal8_asm_systemv>	a60: R_AARCH64_CALL26	_call_goal8_asm_systemv
 a64:	f9408a89 	ldr	x9, [x20, #272]
 a68:	f940032b 	ldr	x11, [x25]
 a6c:	f940a28a 	ldr	x10, [x20, #320]
 a70:	f9001280 	str	x0, [x20, #32]
 a74:	8b294168 	add	x8, x11, w9, uxtw
 a78:	f900228a 	str	x10, [x20, #64]
 a7c:	f9001a89 	str	x9, [x20, #48]
 a80:	b9400d0c 	ldr	w12, [x8, #12]
 a84:	b902069f 	str	wzr, [x20, #516]
 a88:	1e270180 	fmov	s0, w12
 a8c:	b902028c 	str	w12, [x20, #512]
 a90:	92400d4c 	and	x12, x10, #0xf
 a94:	1e202008 	fcmp	s0, #0.0
 a98:	540001e4 	b.mi	ad4 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xad4>  // b.first
 a9c:	b50015ec 	cbnz	x12, d58 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd58>
 aa0:	927c6d4a 	and	x10, x10, #0xfffffff0
 aa4:	f2400d3f 	tst	x9, #0xf
 aa8:	8b0a016a 	add	x10, x11, x10
 aac:	3dc00540 	ldr	q0, [x10, #16]
 ab0:	3d80a680 	str	q0, [x20, #656]
 ab4:	54001521 	b.ne	d58 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd58>  // b.any
 ab8:	3dc00100 	ldr	q0, [x8]
 abc:	3d80aa80 	str	q0, [x20, #672]
 ac0:	fd415280 	ldr	d0, [x20, #672]
 ac4:	bd42aa82 	ldr	s2, [x20, #680]
 ac8:	0e28d401 	fadd	v1.2s, v0.2s, v8.2s
 acc:	1e292840 	fadd	s0, s2, s9
 ad0:	1400000e 	b	b08 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb08>
 ad4:	b500142c 	cbnz	x12, d58 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd58>
 ad8:	927c6d4a 	and	x10, x10, #0xfffffff0
 adc:	f2400d3f 	tst	x9, #0xf
 ae0:	8b0a016a 	add	x10, x11, x10
 ae4:	3dc00540 	ldr	q0, [x10, #16]
 ae8:	3d80a680 	str	q0, [x20, #656]
 aec:	54001361 	b.ne	d58 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd58>  // b.any
 af0:	3dc00100 	ldr	q0, [x8]
 af4:	3d80aa80 	str	q0, [x20, #672]
 af8:	fd415280 	ldr	d0, [x20, #672]
 afc:	bd42aa82 	ldr	s2, [x20, #680]
 b00:	0ea0d501 	fsub	v1.2s, v8.2s, v0.2s
 b04:	1e223920 	fsub	s0, s9, s2
 b08:	5e0c0422 	mov	s2, v1.s[1]
 b0c:	1e260009 	fmov	w9, s0
 b10:	b9429e8b 	ldr	w11, [x20, #668]
 b14:	91004148 	add	x8, x10, #0x10
 b18:	1e26002a 	fmov	w10, s1
 b1c:	fd014a81 	str	d1, [x20, #656]
 b20:	bd029a80 	str	s0, [x20, #664]
 b24:	aa0b8129 	orr	x9, x9, x11, lsl #32
 b28:	1e26004b 	fmov	w11, s2
 b2c:	aa0b814a 	orr	x10, x10, x11, lsl #32
 b30:	a900250a 	stp	x10, x9, [x8]
 b34:	f9414e89 	ldr	x9, [x20, #664]
 b38:	f9414a8a 	ldr	x10, [x20, #656]
 b3c:	f9400325 	ldr	x5, [x25]
 b40:	f940aa9b 	ldr	x27, [x20, #336]
 b44:	f9419688 	ldr	x8, [x20, #808]
 b48:	a904268a 	stp	x10, x9, [x20, #64]
 b4c:	f9419289 	ldr	x9, [x20, #800]
 b50:	8b3b40aa 	add	x10, x5, w27, uxtw
 b54:	a9032289 	stp	x9, x8, [x20, #48]
 b58:	b980694a 	ldrsw	x10, [x10, #104]
 b5c:	927e014b 	and	x11, x10, #0x4
 b60:	f900228a 	str	x10, [x20, #64]
 b64:	f9002a8b 	str	x11, [x20, #80]
 b68:	360800ea 	tbz	w10, #1, b84 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb84>
 b6c:	d360fd0c 	lsr	x12, x8, #32
 b70:	290c229f 	stp	wzr, w8, [x20, #96]
 b74:	290d329f 	stp	wzr, w12, [x20, #104]
 b78:	b5000069 	cbnz	x9, b84 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xb84>
 b7c:	f9403289 	ldr	x9, [x20, #96]
 b80:	b40002e9 	cbz	x9, bdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
 b84:	92400149 	and	x9, x10, #0x1
 b88:	f9000349 	str	x9, [x26]
 b8c:	b40000eb 	cbz	x11, ba8 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xba8>
 b90:	d360fd0a 	lsr	x10, x8, #32
 b94:	29077e88 	stp	w8, wzr, [x20, #56]
 b98:	29062a9f 	stp	wzr, w10, [x20, #48]
 b9c:	f9401a8a 	ldr	x10, [x20, #48]
 ba0:	f100055f 	cmp	x10, #0x1
 ba4:	540001cb 	b.lt	bdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>  // b.tstop
 ba8:	b4ffb2e9 	cbz	x9, 204 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x204>
 bac:	b9430e88 	ldr	w8, [x20, #780]
 bb0:	f9418a8a 	ldr	x10, [x20, #784]
 bb4:	2906229f 	stp	wzr, w8, [x20, #48]
 bb8:	f9418e88 	ldr	x8, [x20, #792]
 bbc:	f9401a89 	ldr	x9, [x20, #48]
 bc0:	a903228a 	stp	x10, x8, [x20, #48]
 bc4:	b7f800c9 	tbnz	x9, #63, bdc <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xbdc>
 bc8:	d360fd09 	lsr	x9, x8, #32
 bcc:	29077e88 	stp	w8, wzr, [x20, #56]
 bd0:	2906269f 	stp	wzr, w9, [x20, #48]
 bd4:	f9401a89 	ldr	x9, [x20, #48]
 bd8:	b6ffb169 	tbz	x9, #63, 204 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x204>
 bdc:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	bdc: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_3d::cache+0x10
 be0:	f940e289 	ldr	x9, [x20, #448]
 be4:	f940828a 	ldr	x10, [x20, #256]
 be8:	f9400108 	ldr	x8, [x8]	be8: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache+0x10
 bec:	f940a28b 	ldr	x11, [x20, #320]
 bf0:	b981f28c 	ldrsw	x12, [x20, #496]
 bf4:	b9800108 	ldrsw	x8, [x8]
 bf8:	f9002289 	str	x9, [x20, #64]
 bfc:	f9002a8a 	str	x10, [x20, #80]
 c00:	a9032be9 	stp	x9, x10, [sp, #48]
 c04:	f9404289 	ldr	x9, [x20, #128]
 c08:	f9404a8a 	ldr	x10, [x20, #144]
 c0c:	f9003a8b 	str	x11, [x20, #112]
 c10:	a9042ffb 	stp	x27, x11, [sp, #64]
 c14:	f940528b 	ldr	x11, [x20, #160]
 c18:	a9052be9 	stp	x9, x10, [sp, #80]
 c1c:	f9405a89 	ldr	x9, [x20, #176]
 c20:	f900329b 	str	x27, [x20, #96]
 c24:	f900ca88 	str	x8, [x20, #400]
 c28:	f900128c 	str	x12, [x20, #32]
 c2c:	a90627eb 	stp	x11, x9, [sp, #96]
 c30:	34000828 	cbz	w8, d34 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd34>
 c34:	f940b283 	ldr	x3, [x20, #352]
 c38:	f940ba84 	ldr	x4, [x20, #368]
 c3c:	92407d08 	and	x8, x8, #0xffffffff
 c40:	8b0800a0 	add	x0, x5, x8
 c44:	9100c3e1 	add	x1, sp, #0x30
 c48:	aa1f03e2 	mov	x2, xzr
 c4c:	94000000 	bl	0 <_call_goal8_asm_systemv>	c4c: R_AARCH64_CALL26	_call_goal8_asm_systemv
 c50:	f9001280 	str	x0, [x20, #32]
 c54:	17fffd6c 	b	204 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0x204>
 c58:	f9400328 	ldr	x8, [x25]
 c5c:	f940ea89 	ldr	x9, [x20, #464]
 c60:	f9001298 	str	x24, [x20, #32]
 c64:	8b29410a 	add	x10, x8, w9, uxtw
 c68:	f940014b 	ldr	x11, [x10]
 c6c:	f900fa8b 	str	x11, [x20, #496]
 c70:	1102412b 	add	w11, w9, #0x90
 c74:	f940054a 	ldr	x10, [x10, #8]
 c78:	927c6d6b 	and	x11, x11, #0xfffffff0
 c7c:	f900f28a 	str	x10, [x20, #480]
 c80:	1102012a 	add	w10, w9, #0x80
 c84:	3ceb6900 	ldr	q0, [x8, x11]
 c88:	927c6d4a 	and	x10, x10, #0xfffffff0
 c8c:	3d807280 	str	q0, [x20, #448]
 c90:	3cea6900 	ldr	q0, [x8, x10]
 c94:	1101c12a 	add	w10, w9, #0x70
 c98:	927c6d4a 	and	x10, x10, #0xfffffff0
 c9c:	3d805680 	str	q0, [x20, #336]
 ca0:	3cea6900 	ldr	q0, [x8, x10]
 ca4:	1101812a 	add	w10, w9, #0x60
 ca8:	927c6d4a 	and	x10, x10, #0xfffffff0
 cac:	3d805280 	str	q0, [x20, #320]
 cb0:	3cea6900 	ldr	q0, [x8, x10]
 cb4:	1101412a 	add	w10, w9, #0x50
 cb8:	927c6d4a 	and	x10, x10, #0xfffffff0
 cbc:	3d804e80 	str	q0, [x20, #304]
 cc0:	3cea6900 	ldr	q0, [x8, x10]
 cc4:	1101012a 	add	w10, w9, #0x40
 cc8:	927c6d4a 	and	x10, x10, #0xfffffff0
 ccc:	3d804a80 	str	q0, [x20, #288]
 cd0:	3cea6900 	ldr	q0, [x8, x10]
 cd4:	1100c12a 	add	w10, w9, #0x30
 cd8:	927c6d4a 	and	x10, x10, #0xfffffff0
 cdc:	3d804680 	str	q0, [x20, #272]
 ce0:	3cea6900 	ldr	q0, [x8, x10]
 ce4:	91028128 	add	x8, x9, #0xa0
 ce8:	f900ea88 	str	x8, [x20, #464]
 cec:	3d804280 	str	q0, [x20, #256]
 cf0:	94000000 	bl	0 <std::chrono::_V2::steady_clock::now()>	cf0: R_AARCH64_CALL26	std::chrono::_V2::steady_clock::now()
 cf4:	f9400fe8 	ldr	x8, [sp, #24]
 cf8:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	cf8: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof
 cfc:	91000021 	add	x1, x1, #0x0	cfc: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof
 d00:	cb080000 	sub	x0, x0, x8
 d04:	94000000 	bl	0 <__aarch64_ldadd8_relax>	d04: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 d08:	aa1803e0 	mov	x0, x24
 d0c:	a94e4ff4 	ldp	x20, x19, [sp, #224]
 d10:	a94d57f6 	ldp	x22, x21, [sp, #208]
 d14:	a94c5ff8 	ldp	x24, x23, [sp, #192]
 d18:	a94b67fa 	ldp	x26, x25, [sp, #176]
 d1c:	a94a6ffc 	ldp	x28, x27, [sp, #160]
 d20:	a9497bfd 	ldp	x29, x30, [sp, #144]
 d24:	6d4823e9 	ldp	d9, d8, [sp, #128]
 d28:	6d472beb 	ldp	d11, d10, [sp, #112]
 d2c:	9103c3ff 	add	sp, sp, #0xf0
 d30:	d65f03c0 	ret
 d34:	52803202 	mov	w2, #0x190                 	// #400
 d38:	1400000e 	b	d70 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd70>
 d3c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d3c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x417
 d40:	91000109 	add	x9, x8, #0x0	d40: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x417
 d44:	52803802 	mov	w2, #0x1c0                 	// #448
 d48:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d48: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x43e
 d4c:	91000108 	add	x8, x8, #0x0	d4c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x43e
 d50:	a900a7e8 	stp	x8, x9, [sp, #8]
 d54:	14000007 	b	d70 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd70>
 d58:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d58: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
 d5c:	91000109 	add	x9, x8, #0x0	d5c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
 d60:	52802b02 	mov	w2, #0x158                 	// #344
 d64:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d64: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3b6
 d68:	91000108 	add	x8, x8, #0x0	d68: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3b6
 d6c:	a900a7e8 	stp	x8, x9, [sp, #8]
 d70:	a94083e3 	ldp	x3, x0, [sp, #8]
 d74:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d74: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x397
 d78:	91000021 	add	x1, x1, #0x0	d78: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x397
 d7c:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d7c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
 d80:	91000084 	add	x4, x4, #0x0	d80: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
 d84:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	d84: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
 d88:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d88: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1
 d8c:	91000000 	add	x0, x0, #0x0	d8c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1
 d90:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d90: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a
 d94:	91000021 	add	x1, x1, #0x0	d94: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a
 d98:	90000003 	adrp	x3, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	d98: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x92
 d9c:	91000063 	add	x3, x3, #0x0	d9c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x92
 da0:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	da0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
 da4:	91000084 	add	x4, x4, #0x0	da4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
 da8:	52801f42 	mov	w2, #0xfa                  	// #250
 dac:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	dac: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
 db0:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	db0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xca
 db4:	91000000 	add	x0, x0, #0x0	db4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xca
 db8:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	db8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2a
 dbc:	91000021 	add	x1, x1, #0x0	dbc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2a
 dc0:	90000003 	adrp	x3, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	dc0: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x92
 dc4:	91000063 	add	x3, x3, #0x0	dc4: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x92
 dc8:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	dc8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
 dcc:	91000084 	add	x4, x4, #0x0	dcc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
 dd0:	52802002 	mov	w2, #0x100                 	// #256
 dd4:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	dd4: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
 dd8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	dd8: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3b6
 ddc:	91000109 	add	x9, x8, #0x0	ddc: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3b6
 de0:	52802b02 	mov	w2, #0x158                 	// #344
 de4:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	de4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
 de8:	91000108 	add	x8, x8, #0x0	de8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
 dec:	a900a3e9 	stp	x9, x8, [sp, #8]
 df0:	17ffffe0 	b	d70 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xd70>
 df4:	14000003 	b	e00 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe00>
 df8:	14000002 	b	e00 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe00>
 dfc:	14000001 	b	e00 <Mips2C::jak1::sp_process_block_3d::execute(void*)+0xe00>
 e00:	aa0003f4 	mov	x20, x0
 e04:	94000000 	bl	0 <std::chrono::_V2::steady_clock::now()>	e04: R_AARCH64_CALL26	std::chrono::_V2::steady_clock::now()
 e08:	f9400fe8 	ldr	x8, [sp, #24]
 e0c:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_3d::execute(void*)>	e0c: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof
 e10:	91000021 	add	x1, x1, #0x0	e10: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof
 e14:	cb080000 	sub	x0, x0, x8
 e18:	94000000 	bl	0 <__aarch64_ldadd8_relax>	e18: R_AARCH64_CALL26	__aarch64_ldadd8_relax
 e1c:	aa1403e0 	mov	x0, x20
 e20:	94000000 	bl	0 <_Unwind_Resume>	e20: R_AARCH64_CALL26	_Unwind_Resume

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_3d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_3d::link()>:
   0:	d10103ff 	sub	sp, sp, #0x40
   4:	a9027bfd 	stp	x29, x30, [sp, #32]
   8:	a9034ff4 	stp	x20, x19, [sp, #48]
   c:	910083fd 	add	x29, sp, #0x20
  10:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	10: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xf5
  14:	91000000 	add	x0, x0, #0x0	14: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xf5
  18:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	18: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  1c:	90000013 	adrp	x19, 0 <g_ee_main_mem>	1c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  20:	7100001f 	cmp	w0, #0x0
  24:	90000014 	adrp	x20, 0 <Mips2C::jak1::sp_process_block_3d::link()>	24: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_3d::cache
  28:	91000294 	add	x20, x20, #0x0	28: R_AARCH64_ADD_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::cache
  2c:	f9400273 	ldr	x19, [x19]	2c: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  30:	f9400268 	ldr	x8, [x19]
  34:	8b204108 	add	x8, x8, w0, uxtw
  38:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	38: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x105
  3c:	91000000 	add	x0, x0, #0x0	3c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x105
  40:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  44:	f9000288 	str	x8, [x20]
  48:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	48: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  4c:	f9400268 	ldr	x8, [x19]
  50:	7100001f 	cmp	w0, #0x0
  54:	8b204108 	add	x8, x8, w0, uxtw
  58:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	58: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x112
  5c:	91000000 	add	x0, x0, #0x0	5c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x112
  60:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  64:	f9000688 	str	x8, [x20, #8]
  68:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	68: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  6c:	f9400268 	ldr	x8, [x19]
  70:	7100001f 	cmp	w0, #0x0
  74:	8b204108 	add	x8, x8, w0, uxtw
  78:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_3d::link()>	78: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x123
  7c:	91000000 	add	x0, x0, #0x0	7c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x123
  80:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  84:	f9000a88 	str	x8, [x20, #16]
  88:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	88: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  8c:	f9400268 	ldr	x8, [x19]
  90:	7100001f 	cmp	w0, #0x0
  94:	910003e9 	mov	x9, sp
  98:	91004133 	add	x19, x9, #0x10
  9c:	8b204108 	add	x8, x8, w0, uxtw
  a0:	52800280 	mov	w0, #0x14                  	// #20
  a4:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  a8:	f9000e88 	str	x8, [x20, #24]
  ac:	94000000 	bl	0 <operator new(unsigned long)>	ac: R_AARCH64_CALL26	operator new(unsigned long)
  b0:	5280026a 	mov	w10, #0x13                  	// #19
  b4:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_3d::link()>	b4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x13b
  b8:	91000129 	add	x9, x9, #0x0	b8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x13b
  bc:	4e080d41 	dup	v1.2d, x10
  c0:	5285ad68 	mov	w8, #0x2d6b                	// #11627
  c4:	3dc00120 	ldr	q0, [x9]
  c8:	72ac8668 	movk	w8, #0x6433, lsl #16
  cc:	f90003e0 	str	x0, [sp]
  d0:	b800f008 	stur	w8, [x0, #15]
  d4:	3d800000 	str	q0, [x0]
  d8:	3c8083e1 	stur	q1, [sp, #8]
  dc:	39004c1f 	strb	wzr, [x0, #19]
  e0:	90000000 	adrp	x0, 0 <Mips2C::gLinkedFunctionTable>	e0: R_AARCH64_ADR_GOT_PAGE	Mips2C::gLinkedFunctionTable
  e4:	90000002 	adrp	x2, 0 <Mips2C::jak1::sp_process_block_3d::link()>	e4: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_3d::execute(void*)
  e8:	91000042 	add	x2, x2, #0x0	e8: R_AARCH64_ADD_ABS_LO12_NC	Mips2C::jak1::sp_process_block_3d::execute(void*)
  ec:	f9400000 	ldr	x0, [x0]	ec: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::gLinkedFunctionTable
  f0:	910003e1 	mov	x1, sp
  f4:	52802003 	mov	w3, #0x100                 	// #256
  f8:	94000000 	bl	0 <Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)>	f8: R_AARCH64_CALL26	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)
  fc:	f94003e0 	ldr	x0, [sp]
 100:	eb13001f 	cmp	x0, x19
 104:	54000040 	b.eq	10c <Mips2C::jak1::sp_process_block_3d::link()+0x10c>  // b.none
 108:	94000000 	bl	0 <operator delete(void*)>	108: R_AARCH64_CALL26	operator delete(void*)
 10c:	a9434ff4 	ldp	x20, x19, [sp, #48]
 110:	a9427bfd 	ldp	x29, x30, [sp, #32]
 114:	910103ff 	add	sp, sp, #0x40
 118:	d65f03c0 	ret
 11c:	f94003e8 	ldr	x8, [sp]
 120:	eb13011f 	cmp	x8, x19
 124:	aa0003f3 	mov	x19, x0
 128:	54000060 	b.eq	134 <Mips2C::jak1::sp_process_block_3d::link()+0x134>  // b.none
 12c:	aa0803e0 	mov	x0, x8
 130:	94000000 	bl	0 <operator delete(void*)>	130: R_AARCH64_CALL26	operator delete(void*)
 134:	aa1303e0 	mov	x0, x19
 138:	94000000 	bl	0 <_Unwind_Resume>	138: R_AARCH64_CALL26	_Unwind_Resume

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d7executeEPv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::execute(void*)>:
       0:	d10503ff 	sub	sp, sp, #0x140
       4:	6d0d23e9 	stp	d9, d8, [sp, #208]
       8:	a90e7bfd 	stp	x29, x30, [sp, #224]
       c:	a90f6ffc 	stp	x28, x27, [sp, #240]
      10:	a91067fa 	stp	x26, x25, [sp, #256]
      14:	a9115ff8 	stp	x24, x23, [sp, #272]
      18:	a91257f6 	stp	x22, x21, [sp, #288]
      1c:	a9134ff4 	stp	x20, x19, [sp, #304]
      20:	910383fd 	add	x29, sp, #0xe0
      24:	aa0003f4 	mov	x20, x0
      28:	94000000 	bl	0 <std::chrono::_V2::steady_clock::now()>	28: R_AARCH64_CALL26	std::chrono::_V2::steady_clock::now()
      2c:	f9003be0 	str	x0, [sp, #112]
      30:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	30: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof+0x28
      34:	91000021 	add	x1, x1, #0x0	34: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof+0x28
      38:	52800020 	mov	w0, #0x1                   	// #1
      3c:	94000000 	bl	0 <__aarch64_ldadd8_relax>	3c: R_AARCH64_CALL26	__aarch64_ldadd8_relax
      40:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	40: R_AARCH64_ADR_PREL_PG_HI21	g_perf_2dvec_off
      44:	9000001b 	adrp	x27, 0 <g_ee_main_mem>	44: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
      48:	aa1403f8 	mov	x24, x20
      4c:	f940037b 	ldr	x27, [x27]	4c: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
      50:	39400108 	ldrb	w8, [x8]	50: R_AARCH64_LDST8_ABS_LO12_NC	g_perf_2dvec_off
      54:	f940fa8a 	ldr	x10, [x20, #496]
      58:	b819c3a8 	stur	w8, [x29, #-100]
      5c:	f940ea88 	ldr	x8, [x20, #464]
      60:	f9400369 	ldr	x9, [x27]
      64:	d1020108 	sub	x8, x8, #0x80
      68:	f900ea88 	str	x8, [x20, #464]
      6c:	f828492a 	str	x10, [x9, w8, uxtw]
      70:	b941d288 	ldr	w8, [x20, #464]
      74:	f9400369 	ldr	x9, [x27]
      78:	3dc04280 	ldr	q0, [x20, #256]
      7c:	11004108 	add	w8, w8, #0x10
      80:	927c6d08 	and	x8, x8, #0xfffffff0
      84:	3ca86920 	str	q0, [x9, x8]
      88:	b941d288 	ldr	w8, [x20, #464]
      8c:	f9400369 	ldr	x9, [x27]
      90:	3dc04680 	ldr	q0, [x20, #272]
      94:	11008108 	add	w8, w8, #0x20
      98:	927c6d08 	and	x8, x8, #0xfffffff0
      9c:	3ca86920 	str	q0, [x9, x8]
      a0:	b941d288 	ldr	w8, [x20, #464]
      a4:	f9400369 	ldr	x9, [x27]
      a8:	3dc04a80 	ldr	q0, [x20, #288]
      ac:	1100c108 	add	w8, w8, #0x30
      b0:	927c6d08 	and	x8, x8, #0xfffffff0
      b4:	3ca86920 	str	q0, [x9, x8]
      b8:	b941d288 	ldr	w8, [x20, #464]
      bc:	f9400369 	ldr	x9, [x27]
      c0:	3dc04e80 	ldr	q0, [x20, #304]
      c4:	11010108 	add	w8, w8, #0x40
      c8:	927c6d08 	and	x8, x8, #0xfffffff0
      cc:	3ca86920 	str	q0, [x9, x8]
      d0:	b941d288 	ldr	w8, [x20, #464]
      d4:	f9400369 	ldr	x9, [x27]
      d8:	3dc05280 	ldr	q0, [x20, #320]
      dc:	11014108 	add	w8, w8, #0x50
      e0:	927c6d08 	and	x8, x8, #0xfffffff0
      e4:	3ca86920 	str	q0, [x9, x8]
      e8:	b941d288 	ldr	w8, [x20, #464]
      ec:	f9400369 	ldr	x9, [x27]
      f0:	3dc05680 	ldr	q0, [x20, #336]
      f4:	11018108 	add	w8, w8, #0x60
      f8:	927c6d08 	and	x8, x8, #0xfffffff0
      fc:	3ca86920 	str	q0, [x9, x8]
     100:	b941d288 	ldr	w8, [x20, #464]
     104:	f9400369 	ldr	x9, [x27]
     108:	3dc07280 	ldr	q0, [x20, #448]
     10c:	1101c108 	add	w8, w8, #0x70
     110:	927c6d08 	and	x8, x8, #0xfffffff0
     114:	3ca86920 	str	q0, [x9, x8]
     118:	f9402288 	ldr	x8, [x20, #64]
     11c:	f9402a89 	ldr	x9, [x20, #80]
     120:	f940328a 	ldr	x10, [x20, #96]
     124:	f900e288 	str	x8, [x20, #448]
     128:	f9403a88 	ldr	x8, [x20, #112]
     12c:	f900aa89 	str	x9, [x20, #336]
     130:	f9404289 	ldr	x9, [x20, #128]
     134:	f900a28a 	str	x10, [x20, #320]
     138:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	138: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_2d::cache
     13c:	f9008a88 	str	x8, [x20, #272]
     140:	f9404a88 	ldr	x8, [x20, #144]
     144:	f9009a89 	str	x9, [x20, #304]
     148:	f9400149 	ldr	x9, [x10]	148: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     14c:	f9009288 	str	x8, [x20, #288]
     150:	b9800128 	ldrsw	x8, [x9]
     154:	72000d1f 	tst	w8, #0xf
     158:	f8030f08 	str	x8, [x24, #48]!
     15c:	54009861 	b.ne	1468 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1468>  // b.any
     160:	f9400369 	ldr	x9, [x27]
     164:	927c6d08 	and	x8, x8, #0xfffffff0
     168:	9104828a 	add	x10, x20, #0x120
     16c:	1e2e1008 	fmov	s8, #1.000000000000000000e+00
     170:	1e3e1009 	fmov	s9, #-1.000000000000000000e+00
     174:	f81a03aa 	stur	x10, [x29, #-96]
     178:	3ce86920 	ldr	q0, [x9, x8]
     17c:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	17c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3ee
     180:	91000129 	add	x9, x9, #0x0	180: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3ee
     184:	f90037e9 	str	x9, [sp, #104]
     188:	f940aa9c 	ldr	x28, [x20, #336]
     18c:	91099317 	add	x23, x24, #0x264
     190:	3d80c680 	str	q0, [x20, #784]
     194:	91050293 	add	x19, x20, #0x140
     198:	91054299 	add	x25, x20, #0x150
     19c:	b9431288 	ldr	w8, [x20, #784]
     1a0:	b9431689 	ldr	w9, [x20, #788]
     1a4:	f9418e8a 	ldr	x10, [x20, #792]
     1a8:	9000001a 	adrp	x26, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1a8: R_AARCH64_ADR_PREL_PG_HI21	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     1ac:	92401d0b 	and	x11, x8, #0xff
     1b0:	aa098108 	orr	x8, x8, x9, lsl #32
     1b4:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1b4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3e9
     1b8:	91000129 	add	x9, x9, #0x0	1b8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3e9
     1bc:	f900828b 	str	x11, [x20, #256]
     1c0:	f90033e9 	str	x9, [sp, #96]
     1c4:	a9032a88 	stp	x8, x10, [x20, #48]
     1c8:	1400000e 	b	200 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x200>
     1cc:	f9409a88 	ldr	x8, [x20, #304]
     1d0:	f9400329 	ldr	x9, [x25]
     1d4:	f940026a 	ldr	x10, [x19]
     1d8:	f9408a8b 	ldr	x11, [x20, #272]
     1dc:	f1000508 	subs	x8, x8, #0x1
     1e0:	9102413c 	add	x28, x9, #0x90
     1e4:	f9009a88 	str	x8, [x20, #304]
     1e8:	9100c148 	add	x8, x10, #0x30
     1ec:	91000576 	add	x22, x11, #0x1
     1f0:	f900033c 	str	x28, [x25]
     1f4:	f9000268 	str	x8, [x19]
     1f8:	f9008a96 	str	x22, [x20, #272]
     1fc:	54008a40 	b.eq	1344 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1344>  // b.none
     200:	52800020 	mov	w0, #0x1                   	// #1
     204:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	204: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof+0x48
     208:	91000021 	add	x1, x1, #0x0	208: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof+0x48
     20c:	94000000 	bl	0 <__aarch64_ldadd8_relax>	20c: R_AARCH64_CALL26	__aarch64_ldadd8_relax
     210:	f9400376 	ldr	x22, [x27]
     214:	92407f89 	and	x9, x28, #0xffffffff
     218:	b941728b 	ldr	w11, [x20, #368]
     21c:	8b0902c8 	add	x8, x22, x9
     220:	b980810a 	ldrsw	x10, [x8, #128]
     224:	6b0b015f 	cmp	w10, w11
     228:	f9001a8a 	str	x10, [x20, #48]
     22c:	54fffd00 	b.eq	1cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1cc>  // b.none
     230:	f85a03aa 	ldur	x10, [x29, #-96]
     234:	b940014c 	ldr	w12, [x10]
     238:	b980690a 	ldrsw	x10, [x8, #104]
     23c:	6b0b019f 	cmp	w12, w11
     240:	f900030a 	str	x10, [x24]
     244:	54000320 	b.eq	2a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2a8>  // b.none
     248:	9273014b 	and	x11, x10, #0x2000
     24c:	f900030b 	str	x11, [x24]
     250:	376802ca 	tbnz	w10, #13, 2a8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x2a8>
     254:	b9806509 	ldrsw	x9, [x8, #100]
     258:	9280000a 	mov	x10, #0xffffffffffffffff    	// #-1
     25c:	f900228a 	str	x10, [x20, #64]
     260:	f9001a89 	str	x9, [x20, #48]
     264:	34007fe9 	cbz	w9, 1260 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1260>
     268:	b9806909 	ldrsw	x9, [x8, #104]
     26c:	927a012a 	and	x10, x9, #0x40
     270:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
     274:	f9001a8a 	str	x10, [x20, #48]
     278:	f900228b 	str	x11, [x20, #64]
     27c:	b900690b 	str	w11, [x8, #104]
     280:	3637fa69 	tbz	w9, #6, 1cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1cc>
     284:	f9400368 	ldr	x8, [x27]
     288:	b9400329 	ldr	w9, [x25]
     28c:	b940026a 	ldr	w10, [x19]
     290:	8b090109 	add	x9, x8, x9
     294:	8b0a0108 	add	x8, x8, x10
     298:	b9807d29 	ldrsw	x9, [x9, #124]
     29c:	f9000309 	str	x9, [x24]
     2a0:	b9002d09 	str	w9, [x8, #44]
     2a4:	17ffffca 	b	1cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1cc>
     2a8:	b980650a 	ldrsw	x10, [x8, #100]
     2ac:	f940828b 	ldr	x11, [x20, #256]
     2b0:	cb0b014b 	sub	x11, x10, x11
     2b4:	3100055f 	cmn	w10, #0x1
     2b8:	f9001a8a 	str	x10, [x20, #48]
     2bc:	f900228b 	str	x11, [x20, #64]
     2c0:	54000200 	b.eq	300 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x300>  // b.none
     2c4:	1e270160 	fmov	s0, w11
     2c8:	d360fd69 	lsr	x9, x11, #32
     2cc:	6f00e401 	movi	v1.2d, #0x0
     2d0:	4e0c1d20 	mov	v0.s[1], w9
     2d4:	91012289 	add	x9, x20, #0x48
     2d8:	4d408120 	ld1	{v0.s}[2], [x9]
     2dc:	91013289 	add	x9, x20, #0x4c
     2e0:	4d409120 	ld1	{v0.s}[3], [x9]
     2e4:	4ea16400 	smax	v0.4s, v0.4s, v1.4s
     2e8:	3d800e80 	str	q0, [x20, #48]
     2ec:	34007baa 	cbz	w10, 1260 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1260>
     2f0:	f9400309 	ldr	x9, [x24]
     2f4:	b9006509 	str	w9, [x8, #100]
     2f8:	f9400376 	ldr	x22, [x27]
     2fc:	b9400329 	ldr	w9, [x25]
     300:	8b0902c8 	add	x8, x22, x9
     304:	b9806909 	ldrsw	x9, [x8, #104]
     308:	927a012a 	and	x10, x9, #0x40
     30c:	9279f92b 	and	x11, x9, #0xffffffffffffffbf
     310:	f9001a8a 	str	x10, [x20, #48]
     314:	f900228b 	str	x11, [x20, #64]
     318:	b900690b 	str	w11, [x8, #104]
     31c:	36300129 	tbz	w9, #6, 340 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x340>
     320:	f9400368 	ldr	x8, [x27]
     324:	b9400329 	ldr	w9, [x25]
     328:	b940026a 	ldr	w10, [x19]
     32c:	8b090109 	add	x9, x8, x9
     330:	8b0a0108 	add	x8, x8, x10
     334:	b9807d29 	ldrsw	x9, [x9, #124]
     338:	f9000309 	str	x9, [x24]
     33c:	b9002d09 	str	w9, [x8, #44]
     340:	f9400375 	ldr	x21, [x27]
     344:	b9415288 	ldr	w8, [x20, #336]
     348:	8b0802a8 	add	x8, x21, x8
     34c:	b9807108 	ldrsw	x8, [x8, #112]
     350:	f900ca88 	str	x8, [x20, #400]
     354:	340010e8 	cbz	w8, 570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     358:	f940ea88 	ldr	x8, [x20, #464]
     35c:	3dc07280 	ldr	q0, [x20, #448]
     360:	d1014108 	sub	x8, x8, #0x50
     364:	f900ea88 	str	x8, [x20, #464]
     368:	927c6d08 	and	x8, x8, #0xfffffff0
     36c:	3ca86aa0 	str	q0, [x21, x8]
     370:	b941d288 	ldr	w8, [x20, #464]
     374:	f9400369 	ldr	x9, [x27]
     378:	3dc05680 	ldr	q0, [x20, #336]
     37c:	11004108 	add	w8, w8, #0x10
     380:	927c6d08 	and	x8, x8, #0xfffffff0
     384:	3ca86920 	str	q0, [x9, x8]
     388:	b941d288 	ldr	w8, [x20, #464]
     38c:	f9400369 	ldr	x9, [x27]
     390:	3dc05280 	ldr	q0, [x20, #320]
     394:	11008108 	add	w8, w8, #0x20
     398:	927c6d08 	and	x8, x8, #0xfffffff0
     39c:	3ca86920 	str	q0, [x9, x8]
     3a0:	b941d288 	ldr	w8, [x20, #464]
     3a4:	f9400369 	ldr	x9, [x27]
     3a8:	3dc04680 	ldr	q0, [x20, #272]
     3ac:	1100c108 	add	w8, w8, #0x30
     3b0:	927c6d08 	and	x8, x8, #0xfffffff0
     3b4:	3ca86920 	str	q0, [x9, x8]
     3b8:	f940e288 	ldr	x8, [x20, #448]
     3bc:	b941d28a 	ldr	w10, [x20, #464]
     3c0:	f940aa89 	ldr	x9, [x20, #336]
     3c4:	f940a28b 	ldr	x11, [x20, #320]
     3c8:	f940036c 	ldr	x12, [x27]
     3cc:	3dc04e80 	ldr	q0, [x20, #304]
     3d0:	f9002288 	str	x8, [x20, #64]
     3d4:	11010148 	add	w8, w10, #0x40
     3d8:	f9002a89 	str	x9, [x20, #80]
     3dc:	927c6d09 	and	x9, x8, #0xfffffff0
     3e0:	b9419288 	ldr	w8, [x20, #400]
     3e4:	f900328b 	str	x11, [x20, #96]
     3e8:	3ca96980 	str	q0, [x12, x9]
     3ec:	f9402289 	ldr	x9, [x20, #64]
     3f0:	f9402a8a 	ldr	x10, [x20, #80]
     3f4:	f940328b 	ldr	x11, [x20, #96]
     3f8:	a93aaba9 	stp	x9, x10, [x29, #-88]
     3fc:	f9403a89 	ldr	x9, [x20, #112]
     400:	f940428a 	ldr	x10, [x20, #128]
     404:	a93ba7ab 	stp	x11, x9, [x29, #-72]
     408:	f9404a8b 	ldr	x11, [x20, #144]
     40c:	f9405289 	ldr	x9, [x20, #160]
     410:	a93cafaa 	stp	x10, x11, [x29, #-56]
     414:	f9405a8a 	ldr	x10, [x20, #176]
     418:	a93daba9 	stp	x9, x10, [x29, #-40]
     41c:	34007fc8 	cbz	w8, 1414 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1414>
     420:	f9400365 	ldr	x5, [x27]
     424:	f940b283 	ldr	x3, [x20, #352]
     428:	f940ba84 	ldr	x4, [x20, #368]
     42c:	8b0800a0 	add	x0, x5, x8
     430:	d10163a1 	sub	x1, x29, #0x58
     434:	aa1f03e2 	mov	x2, xzr
     438:	94000000 	bl	0 <_call_goal8_asm_systemv>	438: R_AARCH64_CALL26	_call_goal8_asm_systemv
     43c:	f940ea89 	ldr	x9, [x20, #464]
     440:	f9400375 	ldr	x21, [x27]
     444:	f9001280 	str	x0, [x20, #32]
     448:	927c6d28 	and	x8, x9, #0xfffffff0
     44c:	3ce86aa0 	ldr	q0, [x21, x8]
     450:	11004128 	add	w8, w9, #0x10
     454:	927c6d08 	and	x8, x8, #0xfffffff0
     458:	3d807280 	str	q0, [x20, #448]
     45c:	3ce86aa0 	ldr	q0, [x21, x8]
     460:	11008128 	add	w8, w9, #0x20
     464:	927c6d08 	and	x8, x8, #0xfffffff0
     468:	3d800320 	str	q0, [x25]
     46c:	3ce86aa0 	ldr	q0, [x21, x8]
     470:	1100c128 	add	w8, w9, #0x30
     474:	927c6d08 	and	x8, x8, #0xfffffff0
     478:	3d800260 	str	q0, [x19]
     47c:	3ce86aa0 	ldr	q0, [x21, x8]
     480:	11010128 	add	w8, w9, #0x40
     484:	91014129 	add	x9, x9, #0x50
     488:	927c6d08 	and	x8, x8, #0xfffffff0
     48c:	3d804680 	str	q0, [x20, #272]
     490:	3ce86aa0 	ldr	q0, [x21, x8]
     494:	f9400348 	ldr	x8, [x26]	494: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     498:	f900ea89 	str	x9, [x20, #464]
     49c:	b100091f 	cmn	x8, #0x2
     4a0:	3d804e80 	str	q0, [x20, #304]
     4a4:	54000281 	b.ne	4f4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4f4>  // b.any
     4a8:	92800008 	mov	x8, #0xffffffffffffffff    	// #-1
     4ac:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	4ac: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x471
     4b0:	91000000 	add	x0, x0, #0x0	4b0: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x471
     4b4:	f9000348 	str	x8, [x26]	4b4: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     4b8:	94000000 	bl	0 <getenv>	4b8: R_AARCH64_CALL26	getenv
     4bc:	b40005a0 	cbz	x0, 570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     4c0:	39400008 	ldrb	w8, [x0]
     4c4:	34000568 	cbz	w8, 570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     4c8:	aa1f03e1 	mov	x1, xzr
     4cc:	52800142 	mov	w2, #0xa                   	// #10
     4d0:	94000000 	bl	0 <strtol>	4d0: R_AARCH64_CALL26	strtol
     4d4:	f100041f 	cmp	x0, #0x1
     4d8:	540001c0 	b.eq	510 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x510>  // b.none
     4dc:	540071cd 	b.le	1314 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1314>
     4e0:	aa0003f5 	mov	x21, x0
     4e4:	aa1f03e0 	mov	x0, xzr
     4e8:	94000000 	bl	0 <time>	4e8: R_AARCH64_CALL26	time
     4ec:	8b150008 	add	x8, x0, x21
     4f0:	f9000348 	str	x8, [x26]	4f0: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     4f4:	f100051f 	cmp	x8, #0x1
     4f8:	5400010b 	b.lt	518 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x518>  // b.tstop
     4fc:	aa1f03e0 	mov	x0, xzr
     500:	94000000 	bl	0 <time>	500: R_AARCH64_CALL26	time
     504:	f9400348 	ldr	x8, [x26]	504: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     508:	eb08001f 	cmp	x0, x8
     50c:	5400006b 	b.lt	518 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x518>  // b.tstop
     510:	aa1f03e8 	mov	x8, xzr
     514:	f900035f 	str	xzr, [x26]	514: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     518:	f9400375 	ldr	x21, [x27]
     51c:	b50002a8 	cbnz	x8, 570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     520:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	520: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals
     524:	5283e7e9 	mov	w9, #0x1f3f                	// #7999
     528:	b9400108 	ldr	w8, [x8]	528: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals
     52c:	6b09011f 	cmp	w8, w9
     530:	5400020c 	b.gt	570 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x570>
     534:	f9400321 	ldr	x1, [x25]
     538:	11000508 	add	w8, w8, #0x1
     53c:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	53c: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals
     540:	b9000148 	str	w8, [x10]	540: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals
     544:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	544: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x14f
     548:	91000000 	add	x0, x0, #0x0	548: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x14f
     54c:	8b2142a9 	add	x9, x21, w1, uxtw
     550:	294e0d22 	ldp	w2, w3, [x9, #112]
     554:	b9407924 	ldr	w4, [x9, #120]
     558:	94000000 	bl	0 <printf>	558: R_AARCH64_CALL26	printf
     55c:	90000008 	adrp	x8, 0 <stdout>	55c: R_AARCH64_ADR_GOT_PAGE	stdout
     560:	f9400108 	ldr	x8, [x8]	560: R_AARCH64_LD64_GOT_LO12_NC	stdout
     564:	f9400100 	ldr	x0, [x8]
     568:	94000000 	bl	0 <fflush>	568: R_AARCH64_CALL26	fflush
     56c:	f9400375 	ldr	x21, [x27]
     570:	b9415288 	ldr	w8, [x20, #336]
     574:	f940828b 	ldr	x11, [x20, #256]
     578:	8b0802a8 	add	x8, x21, x8
     57c:	b980790a 	ldrsw	x10, [x8, #120]
     580:	f9002a8a 	str	x10, [x20, #80]
     584:	b9807509 	ldrsw	x9, [x8, #116]
     588:	f9001a89 	str	x9, [x20, #48]
     58c:	cb0b0129 	sub	x9, x9, x11
     590:	f9002289 	str	x9, [x20, #64]
     594:	3400194a 	cbz	w10, 8bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x8bc>
     598:	f100052a 	subs	x10, x9, #0x1
     59c:	f900030a 	str	x10, [x24]
     5a0:	b9007509 	str	w9, [x8, #116]
     5a4:	540018c5 	b.pl	8bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x8bc>  // b.nfrst
     5a8:	f940ea88 	ldr	x8, [x20, #464]
     5ac:	f9400369 	ldr	x9, [x27]
     5b0:	3dc07280 	ldr	q0, [x20, #448]
     5b4:	d1018108 	sub	x8, x8, #0x60
     5b8:	f900ea88 	str	x8, [x20, #464]
     5bc:	927c6d08 	and	x8, x8, #0xfffffff0
     5c0:	3ca86920 	str	q0, [x9, x8]
     5c4:	b941d288 	ldr	w8, [x20, #464]
     5c8:	f9400369 	ldr	x9, [x27]
     5cc:	3dc05680 	ldr	q0, [x20, #336]
     5d0:	11004108 	add	w8, w8, #0x10
     5d4:	927c6d08 	and	x8, x8, #0xfffffff0
     5d8:	3ca86920 	str	q0, [x9, x8]
     5dc:	b941d288 	ldr	w8, [x20, #464]
     5e0:	f9400369 	ldr	x9, [x27]
     5e4:	3dc05280 	ldr	q0, [x20, #320]
     5e8:	11008108 	add	w8, w8, #0x20
     5ec:	927c6d08 	and	x8, x8, #0xfffffff0
     5f0:	3ca86920 	str	q0, [x9, x8]
     5f4:	b941d288 	ldr	w8, [x20, #464]
     5f8:	f9400369 	ldr	x9, [x27]
     5fc:	3dc04680 	ldr	q0, [x20, #272]
     600:	1100c108 	add	w8, w8, #0x30
     604:	927c6d08 	and	x8, x8, #0xfffffff0
     608:	3ca86920 	str	q0, [x9, x8]
     60c:	b941d288 	ldr	w8, [x20, #464]
     610:	f9400369 	ldr	x9, [x27]
     614:	3dc04e80 	ldr	q0, [x20, #304]
     618:	11010108 	add	w8, w8, #0x40
     61c:	927c6d08 	and	x8, x8, #0xfffffff0
     620:	3ca86920 	str	q0, [x9, x8]
     624:	b941d288 	ldr	w8, [x20, #464]
     628:	f9400369 	ldr	x9, [x27]
     62c:	3dc04a80 	ldr	q0, [x20, #288]
     630:	11014108 	add	w8, w8, #0x50
     634:	927c6d08 	and	x8, x8, #0xfffffff0
     638:	3ca86920 	str	q0, [x9, x8]
     63c:	f9400348 	ldr	x8, [x26]	63c: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     640:	f940e289 	ldr	x9, [x20, #448]
     644:	f940a28a 	ldr	x10, [x20, #320]
     648:	b100091f 	cmn	x8, #0x2
     64c:	f9002289 	str	x9, [x20, #64]
     650:	f940aa89 	ldr	x9, [x20, #336]
     654:	f9003a8a 	str	x10, [x20, #112]
     658:	f9003289 	str	x9, [x20, #96]
     65c:	54000281 	b.ne	6ac <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x6ac>  // b.any
     660:	92800008 	mov	x8, #0xffffffffffffffff    	// #-1
     664:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	664: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x471
     668:	91000000 	add	x0, x0, #0x0	668: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x471
     66c:	f9000348 	str	x8, [x26]	66c: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     670:	94000000 	bl	0 <getenv>	670: R_AARCH64_CALL26	getenv
     674:	b4000780 	cbz	x0, 764 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x764>
     678:	39400008 	ldrb	w8, [x0]
     67c:	34000748 	cbz	w8, 764 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x764>
     680:	aa1f03e1 	mov	x1, xzr
     684:	52800142 	mov	w2, #0xa                   	// #10
     688:	94000000 	bl	0 <strtol>	688: R_AARCH64_CALL26	strtol
     68c:	f100041f 	cmp	x0, #0x1
     690:	540001c0 	b.eq	6c8 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x6c8>  // b.none
     694:	5400650d 	b.le	1334 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1334>
     698:	aa0003f5 	mov	x21, x0
     69c:	aa1f03e0 	mov	x0, xzr
     6a0:	94000000 	bl	0 <time>	6a0: R_AARCH64_CALL26	time
     6a4:	8b150008 	add	x8, x0, x21
     6a8:	f9000348 	str	x8, [x26]	6a8: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     6ac:	f100051f 	cmp	x8, #0x1
     6b0:	5400010b 	b.lt	6d0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x6d0>  // b.tstop
     6b4:	aa1f03e0 	mov	x0, xzr
     6b8:	94000000 	bl	0 <time>	6b8: R_AARCH64_CALL26	time
     6bc:	f9400348 	ldr	x8, [x26]	6bc: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     6c0:	eb08001f 	cmp	x0, x8
     6c4:	5400006b 	b.lt	6d0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x6d0>  // b.tstop
     6c8:	aa1f03e8 	mov	x8, xzr
     6cc:	f900035f 	str	xzr, [x26]	6cc: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     6d0:	2a1f03f5 	mov	w21, wzr
     6d4:	b50004a8 	cbnz	x8, 768 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x768>
     6d8:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	6d8: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x4
     6dc:	5283e7e9 	mov	w9, #0x1f3f                	// #7999
     6e0:	b9400108 	ldr	w8, [x8]	6e0: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x4
     6e4:	6b09011f 	cmp	w8, w9
     6e8:	5400040c 	b.gt	768 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x768>
     6ec:	f9400369 	ldr	x9, [x27]
     6f0:	b940026a 	ldr	w10, [x19]
     6f4:	11000508 	add	w8, w8, #0x1
     6f8:	9000000b 	adrp	x11, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	6f8: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x4
     6fc:	f9400321 	ldr	x1, [x25]
     700:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	700: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x174
     704:	91000000 	add	x0, x0, #0x0	704: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x174
     708:	b9000168 	str	w8, [x11]	708: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x4
     70c:	8b0a0128 	add	x8, x9, x10
     710:	2d400500 	ldp	s0, s1, [x8]
     714:	bd400902 	ldr	s2, [x8, #8]
     718:	2d441103 	ldp	s3, s4, [x8, #32]
     71c:	8b214129 	add	x9, x9, w1, uxtw
     720:	2d451905 	ldp	s5, s6, [x8, #40]
     724:	1e22c042 	fcvt	d2, s2
     728:	1e22c000 	fcvt	d0, s0
     72c:	1e22c021 	fcvt	d1, s1
     730:	b9407122 	ldr	w2, [x9, #112]
     734:	1e22c063 	fcvt	d3, s3
     738:	1e22c084 	fcvt	d4, s4
     73c:	b9407923 	ldr	w3, [x9, #120]
     740:	1e22c0a5 	fcvt	d5, s5
     744:	1e22c0c6 	fcvt	d6, s6
     748:	94000000 	bl	0 <printf>	748: R_AARCH64_CALL26	printf
     74c:	90000008 	adrp	x8, 0 <stdout>	74c: R_AARCH64_ADR_GOT_PAGE	stdout
     750:	f9400108 	ldr	x8, [x8]	750: R_AARCH64_LD64_GOT_LO12_NC	stdout
     754:	f9400100 	ldr	x0, [x8]
     758:	94000000 	bl	0 <fflush>	758: R_AARCH64_CALL26	fflush
     75c:	52800035 	mov	w21, #0x1                   	// #1
     760:	14000002 	b	768 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x768>
     764:	2a1f03f5 	mov	w21, wzr
     768:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	768: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_2d::cache+0x18
     76c:	b981f289 	ldrsw	x9, [x20, #496]
     770:	f940228a 	ldr	x10, [x20, #64]
     774:	f9400108 	ldr	x8, [x8]	774: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache+0x18
     778:	f9402a8b 	ldr	x11, [x20, #80]
     77c:	b9800108 	ldrsw	x8, [x8]
     780:	f9001289 	str	x9, [x20, #32]
     784:	f9403289 	ldr	x9, [x20, #96]
     788:	a93aafaa 	stp	x10, x11, [x29, #-88]
     78c:	f9403a8a 	ldr	x10, [x20, #112]
     790:	f940428b 	ldr	x11, [x20, #128]
     794:	f900ca88 	str	x8, [x20, #400]
     798:	a93baba9 	stp	x9, x10, [x29, #-72]
     79c:	f9404a89 	ldr	x9, [x20, #144]
     7a0:	f940528a 	ldr	x10, [x20, #160]
     7a4:	a93ca7ab 	stp	x11, x9, [x29, #-56]
     7a8:	f9405a89 	ldr	x9, [x20, #176]
     7ac:	a93da7aa 	stp	x10, x9, [x29, #-40]
     7b0:	34006328 	cbz	w8, 1414 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1414>
     7b4:	f9400365 	ldr	x5, [x27]
     7b8:	f940b283 	ldr	x3, [x20, #352]
     7bc:	92407d08 	and	x8, x8, #0xffffffff
     7c0:	f940ba84 	ldr	x4, [x20, #368]
     7c4:	8b0800a0 	add	x0, x5, x8
     7c8:	d10163a1 	sub	x1, x29, #0x58
     7cc:	aa1f03e2 	mov	x2, xzr
     7d0:	94000000 	bl	0 <_call_goal8_asm_systemv>	7d0: R_AARCH64_CALL26	_call_goal8_asm_systemv
     7d4:	f940ea89 	ldr	x9, [x20, #464]
     7d8:	f9400368 	ldr	x8, [x27]
     7dc:	f9001280 	str	x0, [x20, #32]
     7e0:	927c6d2a 	and	x10, x9, #0xfffffff0
     7e4:	3cea6900 	ldr	q0, [x8, x10]
     7e8:	1100412a 	add	w10, w9, #0x10
     7ec:	927c6d4a 	and	x10, x10, #0xfffffff0
     7f0:	3d807280 	str	q0, [x20, #448]
     7f4:	3cea6900 	ldr	q0, [x8, x10]
     7f8:	1100812a 	add	w10, w9, #0x20
     7fc:	927c6d4a 	and	x10, x10, #0xfffffff0
     800:	3d800320 	str	q0, [x25]
     804:	3cea6900 	ldr	q0, [x8, x10]
     808:	1100c12a 	add	w10, w9, #0x30
     80c:	927c6d4a 	and	x10, x10, #0xfffffff0
     810:	3d800260 	str	q0, [x19]
     814:	3cea6900 	ldr	q0, [x8, x10]
     818:	1101012a 	add	w10, w9, #0x40
     81c:	927c6d4a 	and	x10, x10, #0xfffffff0
     820:	3d804680 	str	q0, [x20, #272]
     824:	3cea6900 	ldr	q0, [x8, x10]
     828:	1101412a 	add	w10, w9, #0x50
     82c:	91018129 	add	x9, x9, #0x60
     830:	927c6d4a 	and	x10, x10, #0xfffffff0
     834:	3d804e80 	str	q0, [x20, #304]
     838:	3cea6900 	ldr	q0, [x8, x10]
     83c:	f85a03aa 	ldur	x10, [x29, #-96]
     840:	f900ea89 	str	x9, [x20, #464]
     844:	3d800140 	str	q0, [x10]
     848:	340003b5 	cbz	w21, 8bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x8bc>
     84c:	b9400269 	ldr	w9, [x19]
     850:	f9400321 	ldr	x1, [x25]
     854:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	854: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x1c2
     858:	91000000 	add	x0, x0, #0x0	858: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x1c2
     85c:	8b090109 	add	x9, x8, x9
     860:	8b214108 	add	x8, x8, w1, uxtw
     864:	2d400520 	ldp	s0, s1, [x9]
     868:	bd400922 	ldr	s2, [x9, #8]
     86c:	2d441123 	ldp	s3, s4, [x9, #32]
     870:	bd401911 	ldr	s17, [x8, #24]
     874:	2d451925 	ldp	s5, s6, [x9, #40]
     878:	1e22c042 	fcvt	d2, s2
     87c:	2d424107 	ldp	s7, s16, [x8, #16]
     880:	1e22c000 	fcvt	d0, s0
     884:	1e22c021 	fcvt	d1, s1
     888:	1e22c063 	fcvt	d3, s3
     88c:	1e22c084 	fcvt	d4, s4
     890:	1e22c0a5 	fcvt	d5, s5
     894:	1e22c0c6 	fcvt	d6, s6
     898:	1e22c231 	fcvt	d17, s17
     89c:	1e22c0e7 	fcvt	d7, s7
     8a0:	1e22c210 	fcvt	d16, s16
     8a4:	6d0047f0 	stp	d16, d17, [sp]
     8a8:	94000000 	bl	0 <printf>	8a8: R_AARCH64_CALL26	printf
     8ac:	90000008 	adrp	x8, 0 <stdout>	8ac: R_AARCH64_ADR_GOT_PAGE	stdout
     8b0:	f9400108 	ldr	x8, [x8]	8b0: R_AARCH64_LD64_GOT_LO12_NC	stdout
     8b4:	f9400100 	ldr	x0, [x8]
     8b8:	94000000 	bl	0 <fflush>	8b8: R_AARCH64_CALL26	fflush
     8bc:	b9400268 	ldr	w8, [x19]
     8c0:	b859c3a9 	ldur	w9, [x29, #-100]
     8c4:	37000909 	tbnz	w9, #0, 9e4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9e4>
     8c8:	b9415289 	ldr	w9, [x20, #336]
     8cc:	f940036a 	ldr	x10, [x27]
     8d0:	bd431a81 	ldr	s1, [x20, #792]
     8d4:	8b090149 	add	x9, x10, x9
     8d8:	bd404920 	ldr	s0, [x9, #72]
     8dc:	fd402122 	ldr	d2, [x9, #64]
     8e0:	bd401924 	ldr	s4, [x9, #24]
     8e4:	0f819043 	fmul	v3.2s, v2.2s, v1.s[0]
     8e8:	1e210801 	fmul	s1, s0, s1
     8ec:	fd400920 	ldr	d0, [x9, #16]
     8f0:	bd406122 	ldr	s2, [x9, #96]
     8f4:	1e26004b 	fmov	w11, s2
     8f8:	0e23d400 	fadd	v0.2s, v0.2s, v3.2s
     8fc:	1e212881 	fadd	s1, s4, s1
     900:	340000eb 	cbz	w11, 91c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x91c>
     904:	1e223902 	fsub	s2, s8, s2
     908:	bd431e83 	ldr	s3, [x20, #796]
     90c:	1e230842 	fmul	s2, s2, s3
     910:	1e223902 	fsub	s2, s8, s2
     914:	0f829000 	fmul	v0.2s, v0.2s, v2.s[0]
     918:	1e220821 	fmul	s1, s1, s2
     91c:	4ea01c02 	mov	v2.16b, v0.16b
     920:	bd401d23 	ldr	s3, [x9, #28]
     924:	bd431684 	ldr	s4, [x20, #788]
     928:	3dc00d25 	ldr	q5, [x9, #48]
     92c:	8b08014a 	add	x10, x10, x8
     930:	4e040486 	dup	v6.4s, v4.s[0]
     934:	3dc00147 	ldr	q7, [x10]
     938:	3dc00951 	ldr	q17, [x10, #32]
     93c:	6e140422 	mov	v2.s[2], v1.s[0]
     940:	f940094b 	ldr	x11, [x10, #16]
     944:	fd400d50 	ldr	d16, [x10, #24]
     948:	fd000920 	str	d0, [x9, #16]
     94c:	bd001921 	str	s1, [x9, #24]
     950:	6e1c0462 	mov	v2.s[3], v3.s[0]
     954:	4f849042 	fmul	v2.4s, v2.4s, v4.s[0]
     958:	4f8490a4 	fmul	v4.4s, v5.4s, v4.s[0]
     95c:	fd401525 	ldr	d5, [x9, #40]
     960:	f9400369 	ldr	x9, [x27]
     964:	2e26dca5 	fmul	v5.2s, v5.2s, v6.2s
     968:	4e22d4e2 	fadd	v2.4s, v7.4s, v2.4s
     96c:	4e24d624 	fadd	v4.4s, v17.4s, v4.4s
     970:	0e25d605 	fadd	v5.2s, v16.2s, v5.2s
     974:	3ca86922 	str	q2, [x9, x8]
     978:	f9400369 	ldr	x9, [x27]
     97c:	4ea0e886 	fcmlt	v6.4s, v4.4s, #0.0
     980:	8b080129 	add	x9, x9, x8
     984:	f900092b 	str	x11, [x9, #16]
     988:	fd000d25 	str	d5, [x9, #24]
     98c:	4e661c84 	bic	v4.16b, v4.16b, v6.16b
     990:	f9400369 	ldr	x9, [x27]
     994:	8b080128 	add	x8, x9, x8
     998:	3d800904 	str	q4, [x8, #32]
     99c:	3d80a682 	str	q2, [x20, #656]
     9a0:	f901528b 	str	x11, [x20, #672]
     9a4:	fd015685 	str	d5, [x20, #680]
     9a8:	3d80ae84 	str	q4, [x20, #688]
     9ac:	fd016280 	str	d0, [x20, #704]
     9b0:	bd02ca81 	str	s1, [x20, #712]
     9b4:	bd02ce83 	str	s3, [x20, #716]
     9b8:	f9400348 	ldr	x8, [x26]	9b8: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     9bc:	b100091f 	cmn	x8, #0x2
     9c0:	540013c0 	b.eq	c38 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc38>  // b.none
     9c4:	f100051f 	cmp	x8, #0x1
     9c8:	5400156b 	b.lt	c74 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc74>  // b.tstop
     9cc:	aa1f03e0 	mov	x0, xzr
     9d0:	94000000 	bl	0 <time>	9d0: R_AARCH64_CALL26	time
     9d4:	f9400348 	ldr	x8, [x26]	9d4: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     9d8:	eb08001f 	cmp	x0, x8
     9dc:	540014cb 	b.lt	c74 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc74>  // b.tstop
     9e0:	140000a3 	b	c6c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc6c>
     9e4:	f2400d1f 	tst	x8, #0xf
     9e8:	54005281 	b.ne	1438 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1438>  // b.any
     9ec:	f9400369 	ldr	x9, [x27]
     9f0:	927c6d08 	and	x8, x8, #0xfffffff0
     9f4:	8b08012a 	add	x10, x9, x8
     9f8:	f9400328 	ldr	x8, [x25]
     9fc:	3dc00140 	ldr	q0, [x10]
     a00:	f2400d1f 	tst	x8, #0xf
     a04:	3d80a680 	str	q0, [x20, #656]
     a08:	3dc00540 	ldr	q0, [x10, #16]
     a0c:	3d80aa80 	str	q0, [x20, #672]
     a10:	3dc00940 	ldr	q0, [x10, #32]
     a14:	3d80ae80 	str	q0, [x20, #688]
     a18:	54005101 	b.ne	1438 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1438>  // b.any
     a1c:	927c6d08 	and	x8, x8, #0xfffffff0
     a20:	8b080128 	add	x8, x9, x8
     a24:	3dc00500 	ldr	q0, [x8, #16]
     a28:	3d80b280 	str	q0, [x20, #704]
     a2c:	3dc00900 	ldr	q0, [x8, #32]
     a30:	bd42c284 	ldr	s4, [x20, #704]
     a34:	3d80b680 	str	q0, [x20, #720]
     a38:	3dc00d00 	ldr	q0, [x8, #48]
     a3c:	3d80ba80 	str	q0, [x20, #736]
     a40:	3dc01100 	ldr	q0, [x8, #64]
     a44:	3d80be80 	str	q0, [x20, #752]
     a48:	bd431a80 	ldr	s0, [x20, #792]
     a4c:	bd42f281 	ldr	s1, [x20, #752]
     a50:	fd4032e2 	ldr	d2, [x23, #96]
     a54:	bd42fe83 	ldr	s3, [x20, #764]
     a58:	b9806109 	ldrsw	x9, [x8, #96]
     a5c:	1e200821 	fmul	s1, s1, s0
     a60:	0f809042 	fmul	v2.2s, v2.2s, v0.s[0]
     a64:	1e200863 	fmul	s3, s3, s0
     a68:	fd401ae0 	ldr	d0, [x23, #48]
     a6c:	b9020289 	str	w9, [x20, #512]
     a70:	f9001a89 	str	x9, [x20, #48]
     a74:	bd02f281 	str	s1, [x20, #752]
     a78:	1e242821 	fadd	s1, s1, s4
     a7c:	0e20d440 	fadd	v0.2s, v2.2s, v0.2s
     a80:	fd0032e2 	str	d2, [x23, #96]
     a84:	bd431e82 	ldr	s2, [x20, #796]
     a88:	bd02fe83 	str	s3, [x20, #764]
     a8c:	bd02c281 	str	s1, [x20, #704]
     a90:	fd001ae0 	str	d0, [x23, #48]
     a94:	34000269 	cbz	w9, ae0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xae0>
     a98:	1e270123 	fmov	s3, w9
     a9c:	131f7d29 	asr	w9, w9, #31
     aa0:	bd403a85 	ldr	s5, [x20, #56]
     aa4:	1e270126 	fmov	s6, w9
     aa8:	1e250845 	fmul	s5, s2, s5
     aac:	1e233904 	fsub	s4, s8, s3
     ab0:	1e230843 	fmul	s3, s2, s3
     ab4:	bd030a85 	str	s5, [x20, #776]
     ab8:	1e240844 	fmul	s4, s2, s4
     abc:	1e260842 	fmul	s2, s2, s6
     ac0:	bd030283 	str	s3, [x20, #768]
     ac4:	1e243904 	fsub	s4, s8, s4
     ac8:	bd030682 	str	s2, [x20, #772]
     acc:	1e240821 	fmul	s1, s1, s4
     ad0:	0f849000 	fmul	v0.2s, v0.2s, v4.s[0]
     ad4:	bd030e84 	str	s4, [x20, #780]
     ad8:	bd02c281 	str	s1, [x20, #704]
     adc:	fd001ae0 	str	d0, [x23, #48]
     ae0:	bd431682 	ldr	s2, [x20, #788]
     ae4:	910bb289 	add	x9, x20, #0x2ec
     ae8:	fd417284 	ldr	d4, [x20, #736]
     aec:	bd42d285 	ldr	s5, [x20, #720]
     af0:	bd42d686 	ldr	s6, [x20, #724]
     af4:	1e26000a 	fmov	w10, s0
     af8:	4ea21c43 	mov	v3.16b, v2.16b
     afc:	bd42da90 	ldr	s16, [x20, #728]
     b00:	0f829012 	fmul	v18.2s, v0.2s, v2.s[0]
     b04:	1e250845 	fmul	s5, s2, s5
     b08:	1e260846 	fmul	s6, s2, s6
     b0c:	bd42ce87 	ldr	s7, [x20, #716]
     b10:	1e220831 	fmul	s17, s1, s2
     b14:	1e300850 	fmul	s16, s2, s16
     b18:	f941668b 	ldr	x11, [x20, #712]
     b1c:	0d409123 	ld1	{v3.s}[1], [x9]
     b20:	910ba289 	add	x9, x20, #0x2e8
     b24:	1e2208e7 	fmul	s7, s7, s2
     b28:	4d408124 	ld1	{v4.s}[2], [x9]
     b2c:	fd004af2 	str	d18, [x23, #144]
     b30:	1e260029 	fmov	w9, s1
     b34:	bd033285 	str	s5, [x20, #816]
     b38:	3dc0ae85 	ldr	q5, [x20, #688]
     b3c:	4e833863 	zip1	v3.4s, v3.4s, v3.4s
     b40:	bd033686 	str	s6, [x20, #820]
     b44:	fd4002e6 	ldr	d6, [x23]
     b48:	6e1c0444 	mov	v4.s[3], v2.s[0]
     b4c:	bd032291 	str	s17, [x20, #800]
     b50:	aa0a8129 	orr	x9, x9, x10, lsl #32
     b54:	0e26d646 	fadd	v6.2s, v18.2s, v6.2s
     b58:	bd42aa92 	ldr	s18, [x20, #680]
     b5c:	bd033a90 	str	s16, [x20, #824]
     b60:	bd032e87 	str	s7, [x20, #812]
     b64:	6e140443 	mov	v3.s[2], v2.s[0]
     b68:	1e322a10 	fadd	s16, s16, s18
     b6c:	fd0002e6 	str	d6, [x23]
     b70:	6e23dc83 	fmul	v3.4s, v4.4s, v3.4s
     b74:	bd42de84 	ldr	s4, [x20, #732]
     b78:	bd02aa90 	str	s16, [x20, #680]
     b7c:	1e240842 	fmul	s2, s2, s4
     b80:	bd429284 	ldr	s4, [x20, #656]
     b84:	4e25d465 	fadd	v5.4s, v3.4s, v5.4s
     b88:	1e242a24 	fadd	s4, s17, s4
     b8c:	bd429e91 	ldr	s17, [x20, #668]
     b90:	3d80d283 	str	q3, [x20, #832]
     b94:	1e3128e7 	fadd	s7, s7, s17
     b98:	bd42ae91 	ldr	s17, [x20, #684]
     b9c:	bd033e82 	str	s2, [x20, #828]
     ba0:	4ea0e8b2 	fcmlt	v18.4s, v5.4s, #0.0
     ba4:	1e312842 	fadd	s2, s2, s17
     ba8:	bd029284 	str	s4, [x20, #656]
     bac:	bd029e87 	str	s7, [x20, #668]
     bb0:	4e721ca1 	bic	v1.16b, v5.16b, v18.16b
     bb4:	bd02ae82 	str	s2, [x20, #684]
     bb8:	3d80ae81 	str	q1, [x20, #688]
     bbc:	a9012d09 	stp	x9, x11, [x8, #16]
     bc0:	f940a288 	ldr	x8, [x20, #320]
     bc4:	f2400d1f 	tst	x8, #0xf
     bc8:	540042a1 	b.ne	141c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x141c>  // b.any
     bcc:	f9400369 	ldr	x9, [x27]
     bd0:	927c6d08 	and	x8, x8, #0xfffffff0
     bd4:	f9414a8a 	ldr	x10, [x20, #656]
     bd8:	f9414e8b 	ldr	x11, [x20, #664]
     bdc:	8b080128 	add	x8, x9, x8
     be0:	a9002d0a 	stp	x10, x11, [x8]
     be4:	f940a288 	ldr	x8, [x20, #320]
     be8:	f2400d1f 	tst	x8, #0xf
     bec:	54004181 	b.ne	141c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x141c>  // b.any
     bf0:	f9400369 	ldr	x9, [x27]
     bf4:	927c6d08 	and	x8, x8, #0xfffffff0
     bf8:	f941528a 	ldr	x10, [x20, #672]
     bfc:	f941568b 	ldr	x11, [x20, #680]
     c00:	8b080128 	add	x8, x9, x8
     c04:	a9012d0a 	stp	x10, x11, [x8, #16]
     c08:	f940a288 	ldr	x8, [x20, #320]
     c0c:	f2400d1f 	tst	x8, #0xf
     c10:	54004061 	b.ne	141c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x141c>  // b.any
     c14:	f9400369 	ldr	x9, [x27]
     c18:	927c6d08 	and	x8, x8, #0xfffffff0
     c1c:	f9415a8a 	ldr	x10, [x20, #688]
     c20:	f9415e8b 	ldr	x11, [x20, #696]
     c24:	8b080128 	add	x8, x9, x8
     c28:	a9022d0a 	stp	x10, x11, [x8, #32]
     c2c:	f9400348 	ldr	x8, [x26]	c2c: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     c30:	b100091f 	cmn	x8, #0x2
     c34:	54ffec81 	b.ne	9c4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9c4>  // b.any
     c38:	92800008 	mov	x8, #0xffffffffffffffff    	// #-1
     c3c:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	c3c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x471
     c40:	91000000 	add	x0, x0, #0x0	c40: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x471
     c44:	f9000348 	str	x8, [x26]	c44: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     c48:	94000000 	bl	0 <getenv>	c48: R_AARCH64_CALL26	getenv
     c4c:	b4000580 	cbz	x0, cfc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xcfc>
     c50:	39400008 	ldrb	w8, [x0]
     c54:	34000548 	cbz	w8, cfc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xcfc>
     c58:	aa1f03e1 	mov	x1, xzr
     c5c:	52800142 	mov	w2, #0xa                   	// #10
     c60:	94000000 	bl	0 <strtol>	c60: R_AARCH64_CALL26	strtol
     c64:	f100041f 	cmp	x0, #0x1
     c68:	540033c1 	b.ne	12e0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x12e0>  // b.any
     c6c:	aa1f03e8 	mov	x8, xzr
     c70:	f900035f 	str	xzr, [x26]	c70: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     c74:	b5000448 	cbnz	x8, cfc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xcfc>
     c78:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	c78: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x8
     c7c:	b9400109 	ldr	w9, [x8]	c7c: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x8
     c80:	5283e7e8 	mov	w8, #0x1f3f                	// #7999
     c84:	6b08013f 	cmp	w9, w8
     c88:	540003ac 	b.gt	cfc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xcfc>
     c8c:	f940036a 	ldr	x10, [x27]
     c90:	b9400268 	ldr	w8, [x19]
     c94:	52a8690b 	mov	w11, #0x43480000            	// #1128792064
     c98:	1e270162 	fmov	s2, w11
     c9c:	52a8590c 	mov	w12, #0x42c80000            	// #1120403456
     ca0:	52a8604d 	mov	w13, #0x43020000            	// #1124204544
     ca4:	8b080148 	add	x8, x10, x8
     ca8:	1e270183 	fmov	s3, w12
     cac:	b9400321 	ldr	w1, [x25]
     cb0:	2d440500 	ldp	s0, s1, [x8, #32]
     cb4:	8b01014a 	add	x10, x10, x1
     cb8:	bd403144 	ldr	s4, [x10, #48]
     cbc:	1e222020 	fcmp	s1, s2
     cc0:	1e22c404 	fccmp	s0, s2, #0x4, gt
     cc4:	bd402902 	ldr	s2, [x8, #40]
     cc8:	1a9fd7eb 	cset	w11, gt
     ccc:	1e202048 	fcmp	s2, #0.0
     cd0:	1a9f17ec 	cset	w12, eq	// eq = none
     cd4:	1e232020 	fcmp	s1, s3
     cd8:	1e2701a3 	fmov	s3, w13
     cdc:	1a8cb3ed 	csel	w13, wzr, w12, lt	// lt = tstop
     ce0:	1e232000 	fcmp	s0, s3
     ce4:	0a0c016c 	and	w12, w11, w12
     ce8:	1a8d83eb 	csel	w11, wzr, w13, hi	// hi = pmore
     cec:	370001ec 	tbnz	w12, #0, d28 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd28>
     cf0:	370001cb 	tbnz	w11, #0, d28 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd28>
     cf4:	1e292080 	fcmp	s4, s9
     cf8:	54000184 	b.mi	d28 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd28>  // b.first
     cfc:	b859c3a8 	ldur	w8, [x29, #-100]
     d00:	370005a8 	tbnz	w8, #0, db4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xdb4>
     d04:	b9400268 	ldr	w8, [x19]
     d08:	f9400369 	ldr	x9, [x27]
     d0c:	11006108 	add	w8, w8, #0x18
     d10:	bc686920 	ldr	s0, [x9, x8]
     d14:	1e38000a 	fcvtzs	w10, s0
     d18:	13003d4a 	sxth	w10, w10
     d1c:	1e220140 	scvtf	s0, w10
     d20:	bc286920 	str	s0, [x9, x8]
     d24:	1400002e 	b	ddc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xddc>
     d28:	2d471d46 	ldp	s6, s7, [x10, #56]
     d2c:	11000529 	add	w9, w9, #0x1
     d30:	bd403545 	ldr	s5, [x10, #52]
     d34:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	d34: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0x8
     d38:	bd402d03 	ldr	s3, [x8, #44]
     d3c:	b9000149 	str	w9, [x10]	d3c: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0x8
     d40:	1e22c000 	fcvt	d0, s0
     d44:	1e22c021 	fcvt	d1, s1
     d48:	2d404510 	ldp	s16, s17, [x8]
     d4c:	bd400912 	ldr	s18, [x8, #8]
     d50:	bd401113 	ldr	s19, [x8, #16]
     d54:	bd401d14 	ldr	s20, [x8, #28]
     d58:	1e22c042 	fcvt	d2, s2
     d5c:	1e22c063 	fcvt	d3, s3
     d60:	1e22c084 	fcvt	d4, s4
     d64:	1e22c0a5 	fcvt	d5, s5
     d68:	1e22c0c6 	fcvt	d6, s6
     d6c:	1e22c0e7 	fcvt	d7, s7
     d70:	1e22c210 	fcvt	d16, s16
     d74:	1e22c231 	fcvt	d17, s17
     d78:	1e22c252 	fcvt	d18, s18
     d7c:	1e22c273 	fcvt	d19, s19
     d80:	1e22c294 	fcvt	d20, s20
     d84:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	d84: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x210
     d88:	91000000 	add	x0, x0, #0x0	d88: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x210
     d8c:	fd0003f0 	str	d16, [sp]
     d90:	6d00cbf1 	stp	d17, d18, [sp, #8]
     d94:	6d01d3f3 	stp	d19, d20, [sp, #24]
     d98:	94000000 	bl	0 <printf>	d98: R_AARCH64_CALL26	printf
     d9c:	90000008 	adrp	x8, 0 <stdout>	d9c: R_AARCH64_ADR_GOT_PAGE	stdout
     da0:	f9400108 	ldr	x8, [x8]	da0: R_AARCH64_LD64_GOT_LO12_NC	stdout
     da4:	f9400100 	ldr	x0, [x8]
     da8:	94000000 	bl	0 <fflush>	da8: R_AARCH64_CALL26	fflush
     dac:	b859c3a8 	ldur	w8, [x29, #-100]
     db0:	3607faa8 	tbz	w8, #0, d04 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xd04>
     db4:	f9400368 	ldr	x8, [x27]
     db8:	b9414289 	ldr	w9, [x20, #320]
     dbc:	8b090108 	add	x8, x8, x9
     dc0:	bd401900 	ldr	s0, [x8, #24]
     dc4:	1e380009 	fcvtzs	w9, s0
     dc8:	93403d29 	sxth	x9, w9
     dcc:	1e220120 	scvtf	s0, w9
     dd0:	f9001a89 	str	x9, [x20, #48]
     dd4:	bd020280 	str	s0, [x20, #512]
     dd8:	bd001900 	str	s0, [x8, #24]
     ddc:	f9400376 	ldr	x22, [x27]
     de0:	f940aa9c 	ldr	x28, [x20, #336]
     de4:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	de4: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_2d::cache+0x10
     de8:	f9400129 	ldr	x9, [x9]	de8: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache+0x10
     dec:	8b3c42c8 	add	x8, x22, w28, uxtw
     df0:	b9406908 	ldr	w8, [x8, #104]
     df4:	92790108 	and	x8, x8, #0x80
     df8:	f9001a88 	str	x8, [x20, #48]
     dfc:	b9800129 	ldrsw	x9, [x9]
     e00:	f900ca89 	str	x9, [x20, #400]
     e04:	34001dc8 	cbz	w8, 11bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x11bc>
     e08:	f9400348 	ldr	x8, [x26]	e08: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     e0c:	b100091f 	cmn	x8, #0x2
     e10:	54000281 	b.ne	e60 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe60>  // b.any
     e14:	92800008 	mov	x8, #0xffffffffffffffff    	// #-1
     e18:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	e18: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x471
     e1c:	91000000 	add	x0, x0, #0x0	e1c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x471
     e20:	f9000348 	str	x8, [x26]	e20: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     e24:	94000000 	bl	0 <getenv>	e24: R_AARCH64_CALL26	getenv
     e28:	b4000d40 	cbz	x0, fd0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfd0>
     e2c:	39400008 	ldrb	w8, [x0]
     e30:	34000d08 	cbz	w8, fd0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfd0>
     e34:	aa1f03e1 	mov	x1, xzr
     e38:	52800142 	mov	w2, #0xa                   	// #10
     e3c:	94000000 	bl	0 <strtol>	e3c: R_AARCH64_CALL26	strtol
     e40:	f100041f 	cmp	x0, #0x1
     e44:	540001c0 	b.eq	e7c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe7c>  // b.none
     e48:	540026ed 	b.le	1324 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1324>
     e4c:	aa0003f5 	mov	x21, x0
     e50:	aa1f03e0 	mov	x0, xzr
     e54:	94000000 	bl	0 <time>	e54: R_AARCH64_CALL26	time
     e58:	8b150008 	add	x8, x0, x21
     e5c:	f9000348 	str	x8, [x26]	e5c: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     e60:	f100051f 	cmp	x8, #0x1
     e64:	5400010b 	b.lt	e84 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe84>  // b.tstop
     e68:	aa1f03e0 	mov	x0, xzr
     e6c:	94000000 	bl	0 <time>	e6c: R_AARCH64_CALL26	time
     e70:	f9400348 	ldr	x8, [x26]	e70: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     e74:	eb08001f 	cmp	x0, x8
     e78:	5400006b 	b.lt	e84 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe84>  // b.tstop
     e7c:	aa1f03e8 	mov	x8, xzr
     e80:	f900035f 	str	xzr, [x26]	e80: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
     e84:	f9400376 	ldr	x22, [x27]
     e88:	2a1f03f5 	mov	w21, wzr
     e8c:	b5000a48 	cbnz	x8, fd4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfd4>
     e90:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	e90: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0xc
     e94:	5290d3e9 	mov	w9, #0x869f                	// #34463
     e98:	b9400108 	ldr	w8, [x8]	e98: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0xc
     e9c:	72a00029 	movk	w9, #0x1, lsl #16
     ea0:	6b09011f 	cmp	w8, w9
     ea4:	5400098c 	b.gt	fd4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfd4>
     ea8:	f9400321 	ldr	x1, [x25]
     eac:	11000509 	add	w9, w8, #0x1
     eb0:	9000000a 	adrp	x10, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	eb0: R_AARCH64_ADR_PREL_PG_HI21	.bss..L_MergedGlobals+0xc
     eb4:	b9000149 	str	w9, [x10]	eb4: R_AARCH64_LDST32_ABS_LO12_NC	.bss..L_MergedGlobals+0xc
     eb8:	2f00e405 	movi	d5, #0x0
     ebc:	2f00e410 	movi	d16, #0x0
     ec0:	8b2142c8 	add	x8, x22, w1, uxtw
     ec4:	2f00e411 	movi	d17, #0x0
     ec8:	2f00e412 	movi	d18, #0x0
     ecc:	529ffc6a 	mov	w10, #0xffe3                	// #65507
     ed0:	b9406d02 	ldr	w2, [x8, #108]
     ed4:	72a0ffea 	movk	w10, #0x7ff, lsl #16
     ed8:	51004449 	sub	w9, w2, #0x11
     edc:	6b0a013f 	cmp	w9, w10
     ee0:	54000082 	b.cs	ef0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xef0>  // b.hs, b.nlast
     ee4:	8b0202c9 	add	x9, x22, x2
     ee8:	2d404530 	ldp	s16, s17, [x9]
     eec:	bd400932 	ldr	s18, [x9, #8]
     ef0:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	ef0: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_2d::cache
     ef4:	1100114a 	add	w10, w10, #0x4
     ef8:	bd401904 	ldr	s4, [x8, #24]
     efc:	f9400129 	ldr	x9, [x9]	efc: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
     f00:	2d410101 	ldp	s1, s0, [x8, #8]
     f04:	2d420d02 	ldp	s2, s3, [x8, #16]
     f08:	b9400129 	ldr	w9, [x9]
     f0c:	2d4a1d06 	ldp	s6, s7, [x8, #80]
     f10:	2d4b6d1a 	ldp	s26, s27, [x8, #88]
     f14:	5100452b 	sub	w11, w9, #0x11
     f18:	6b0a017f 	cmp	w11, w10
     f1c:	b940026a 	ldr	w10, [x19]
     f20:	8b0a02ca 	add	x10, x22, x10
     f24:	2d405153 	ldp	s19, s20, [x10]
     f28:	bd400955 	ldr	s21, [x10, #8]
     f2c:	2d445d56 	ldp	s22, s23, [x10, #32]
     f30:	2d456558 	ldp	s24, s25, [x10, #40]
     f34:	54000062 	b.cs	f40 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xf40>  // b.hs, b.nlast
     f38:	8b0902c8 	add	x8, x22, x9
     f3c:	bd400505 	ldr	s5, [x8, #4]
     f40:	1e22c000 	fcvt	d0, s0
     f44:	1e22c021 	fcvt	d1, s1
     f48:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	f48: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x274
     f4c:	91000000 	add	x0, x0, #0x0	f4c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x274
     f50:	1e22c042 	fcvt	d2, s2
     f54:	1e22c063 	fcvt	d3, s3
     f58:	1e22c084 	fcvt	d4, s4
     f5c:	1e22c0a5 	fcvt	d5, s5
     f60:	1e22c0c6 	fcvt	d6, s6
     f64:	1e22c0e7 	fcvt	d7, s7
     f68:	1e22c35a 	fcvt	d26, s26
     f6c:	1e22c37b 	fcvt	d27, s27
     f70:	1e22c210 	fcvt	d16, s16
     f74:	1e22c231 	fcvt	d17, s17
     f78:	1e22c252 	fcvt	d18, s18
     f7c:	1e22c273 	fcvt	d19, s19
     f80:	1e22c294 	fcvt	d20, s20
     f84:	1e22c2b5 	fcvt	d21, s21
     f88:	1e22c2d6 	fcvt	d22, s22
     f8c:	1e22c2f7 	fcvt	d23, s23
     f90:	1e22c318 	fcvt	d24, s24
     f94:	6d006ffa 	stp	d26, d27, [sp]
     f98:	1e22c339 	fcvt	d25, s25
     f9c:	6d0147f0 	stp	d16, d17, [sp, #16]
     fa0:	6d0357f4 	stp	d20, d21, [sp, #48]
     fa4:	6d045ff6 	stp	d22, d23, [sp, #64]
     fa8:	6d0567f8 	stp	d24, d25, [sp, #80]
     fac:	6d024ff2 	stp	d18, d19, [sp, #32]
     fb0:	94000000 	bl	0 <printf>	fb0: R_AARCH64_CALL26	printf
     fb4:	90000008 	adrp	x8, 0 <stdout>	fb4: R_AARCH64_ADR_GOT_PAGE	stdout
     fb8:	f9400108 	ldr	x8, [x8]	fb8: R_AARCH64_LD64_GOT_LO12_NC	stdout
     fbc:	f9400100 	ldr	x0, [x8]
     fc0:	94000000 	bl	0 <fflush>	fc0: R_AARCH64_CALL26	fflush
     fc4:	f9400376 	ldr	x22, [x27]
     fc8:	52800035 	mov	w21, #0x1                   	// #1
     fcc:	14000002 	b	fd4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xfd4>
     fd0:	2a1f03f5 	mov	w21, wzr
     fd4:	f940ea88 	ldr	x8, [x20, #464]
     fd8:	3dc07280 	ldr	q0, [x20, #448]
     fdc:	d1018108 	sub	x8, x8, #0x60
     fe0:	f900ea88 	str	x8, [x20, #464]
     fe4:	927c6d08 	and	x8, x8, #0xfffffff0
     fe8:	3ca86ac0 	str	q0, [x22, x8]
     fec:	b941d288 	ldr	w8, [x20, #464]
     ff0:	f9400369 	ldr	x9, [x27]
     ff4:	3dc05680 	ldr	q0, [x20, #336]
     ff8:	11004108 	add	w8, w8, #0x10
     ffc:	927c6d08 	and	x8, x8, #0xfffffff0
    1000:	3ca86920 	str	q0, [x9, x8]
    1004:	b941d288 	ldr	w8, [x20, #464]
    1008:	f9400369 	ldr	x9, [x27]
    100c:	3dc05280 	ldr	q0, [x20, #320]
    1010:	11008108 	add	w8, w8, #0x20
    1014:	927c6d08 	and	x8, x8, #0xfffffff0
    1018:	3ca86920 	str	q0, [x9, x8]
    101c:	b941d288 	ldr	w8, [x20, #464]
    1020:	f9400369 	ldr	x9, [x27]
    1024:	3dc04680 	ldr	q0, [x20, #272]
    1028:	1100c108 	add	w8, w8, #0x30
    102c:	927c6d08 	and	x8, x8, #0xfffffff0
    1030:	3ca86920 	str	q0, [x9, x8]
    1034:	b941d288 	ldr	w8, [x20, #464]
    1038:	f9400369 	ldr	x9, [x27]
    103c:	3dc04e80 	ldr	q0, [x20, #304]
    1040:	11010108 	add	w8, w8, #0x40
    1044:	927c6d08 	and	x8, x8, #0xfffffff0
    1048:	3ca86920 	str	q0, [x9, x8]
    104c:	f940e288 	ldr	x8, [x20, #448]
    1050:	b941d28a 	ldr	w10, [x20, #464]
    1054:	f940aa89 	ldr	x9, [x20, #336]
    1058:	f940a28b 	ldr	x11, [x20, #320]
    105c:	f940036c 	ldr	x12, [x27]
    1060:	3dc04a80 	ldr	q0, [x20, #288]
    1064:	f9002288 	str	x8, [x20, #64]
    1068:	11014148 	add	w8, w10, #0x50
    106c:	f9002a89 	str	x9, [x20, #80]
    1070:	927c6d09 	and	x9, x8, #0xfffffff0
    1074:	b9419288 	ldr	w8, [x20, #400]
    1078:	f900328b 	str	x11, [x20, #96]
    107c:	3ca96980 	str	q0, [x12, x9]
    1080:	f9402289 	ldr	x9, [x20, #64]
    1084:	f9402a8a 	ldr	x10, [x20, #80]
    1088:	f940328b 	ldr	x11, [x20, #96]
    108c:	a93aaba9 	stp	x9, x10, [x29, #-88]
    1090:	f9403a89 	ldr	x9, [x20, #112]
    1094:	f940428a 	ldr	x10, [x20, #128]
    1098:	a93ba7ab 	stp	x11, x9, [x29, #-72]
    109c:	f9404a8b 	ldr	x11, [x20, #144]
    10a0:	f9405289 	ldr	x9, [x20, #160]
    10a4:	a93cafaa 	stp	x10, x11, [x29, #-56]
    10a8:	f9405a8a 	ldr	x10, [x20, #176]
    10ac:	a93daba9 	stp	x9, x10, [x29, #-40]
    10b0:	34001b28 	cbz	w8, 1414 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1414>
    10b4:	f9400365 	ldr	x5, [x27]
    10b8:	f940b283 	ldr	x3, [x20, #352]
    10bc:	f940ba84 	ldr	x4, [x20, #368]
    10c0:	8b0800a0 	add	x0, x5, x8
    10c4:	d10163a1 	sub	x1, x29, #0x58
    10c8:	aa1f03e2 	mov	x2, xzr
    10cc:	94000000 	bl	0 <_call_goal8_asm_systemv>	10cc: R_AARCH64_CALL26	_call_goal8_asm_systemv
    10d0:	f940ea88 	ldr	x8, [x20, #464]
    10d4:	f9400376 	ldr	x22, [x27]
    10d8:	f9001280 	str	x0, [x20, #32]
    10dc:	927c6d09 	and	x9, x8, #0xfffffff0
    10e0:	3ce96ac0 	ldr	q0, [x22, x9]
    10e4:	11004109 	add	w9, w8, #0x10
    10e8:	927c6d29 	and	x9, x9, #0xfffffff0
    10ec:	3d807280 	str	q0, [x20, #448]
    10f0:	3ce96ac0 	ldr	q0, [x22, x9]
    10f4:	11008109 	add	w9, w8, #0x20
    10f8:	927c6d29 	and	x9, x9, #0xfffffff0
    10fc:	3d800320 	str	q0, [x25]
    1100:	3ce96ac0 	ldr	q0, [x22, x9]
    1104:	1100c109 	add	w9, w8, #0x30
    1108:	f940aa9c 	ldr	x28, [x20, #336]
    110c:	927c6d29 	and	x9, x9, #0xfffffff0
    1110:	3d800260 	str	q0, [x19]
    1114:	3ce96ac0 	ldr	q0, [x22, x9]
    1118:	11010109 	add	w9, w8, #0x40
    111c:	927c6d29 	and	x9, x9, #0xfffffff0
    1120:	3d804680 	str	q0, [x20, #272]
    1124:	3ce96ac0 	ldr	q0, [x22, x9]
    1128:	11014109 	add	w9, w8, #0x50
    112c:	91018108 	add	x8, x8, #0x60
    1130:	927c6d29 	and	x9, x9, #0xfffffff0
    1134:	3d804e80 	str	q0, [x20, #304]
    1138:	3ce96ac0 	ldr	q0, [x22, x9]
    113c:	f85a03a9 	ldur	x9, [x29, #-96]
    1140:	f900ea88 	str	x8, [x20, #464]
    1144:	3d800120 	str	q0, [x9]
    1148:	340003b5 	cbz	w21, 11bc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x11bc>
    114c:	b9400268 	ldr	w8, [x19]
    1150:	8b3c42c9 	add	x9, x22, w28, uxtw
    1154:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1154: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x2f3
    1158:	91000000 	add	x0, x0, #0x0	1158: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x2f3
    115c:	2a1c03e1 	mov	w1, w28
    1160:	8b0802c8 	add	x8, x22, x8
    1164:	2d410121 	ldp	s1, s0, [x9, #8]
    1168:	2d4a0d22 	ldp	s2, s3, [x9, #80]
    116c:	bd400910 	ldr	s16, [x8, #8]
    1170:	2d4b1524 	ldp	s4, s5, [x9, #88]
    1174:	2d401d06 	ldp	s6, s7, [x8]
    1178:	1e22c000 	fcvt	d0, s0
    117c:	1e22c021 	fcvt	d1, s1
    1180:	1e22c042 	fcvt	d2, s2
    1184:	1e22c063 	fcvt	d3, s3
    1188:	1e22c084 	fcvt	d4, s4
    118c:	1e22c0a5 	fcvt	d5, s5
    1190:	1e22c210 	fcvt	d16, s16
    1194:	1e22c0c6 	fcvt	d6, s6
    1198:	1e22c0e7 	fcvt	d7, s7
    119c:	fd0003f0 	str	d16, [sp]
    11a0:	94000000 	bl	0 <printf>	11a0: R_AARCH64_CALL26	printf
    11a4:	90000008 	adrp	x8, 0 <stdout>	11a4: R_AARCH64_ADR_GOT_PAGE	stdout
    11a8:	f9400108 	ldr	x8, [x8]	11a8: R_AARCH64_LD64_GOT_LO12_NC	stdout
    11ac:	f9400100 	ldr	x0, [x8]
    11b0:	94000000 	bl	0 <fflush>	11b0: R_AARCH64_CALL26	fflush
    11b4:	f9400376 	ldr	x22, [x27]
    11b8:	f940033c 	ldr	x28, [x25]
    11bc:	b9414288 	ldr	w8, [x20, #320]
    11c0:	11008108 	add	w8, w8, #0x20
    11c4:	927c6d08 	and	x8, x8, #0xfffffff0
    11c8:	3ce86ac0 	ldr	q0, [x22, x8]
    11cc:	8b3c42c8 	add	x8, x22, w28, uxtw
    11d0:	3d800300 	str	q0, [x24]
    11d4:	b9806908 	ldrsw	x8, [x8, #104]
    11d8:	927e0109 	and	x9, x8, #0x4
    11dc:	f9002288 	str	x8, [x20, #64]
    11e0:	f9002a89 	str	x9, [x20, #80]
    11e4:	36080108 	tbz	w8, #1, 1204 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1204>
    11e8:	a9432a8b 	ldp	x11, x10, [x20, #48]
    11ec:	29182a9f 	stp	wzr, w10, [x20, #192]
    11f0:	d360fd4a 	lsr	x10, x10, #32
    11f4:	29192a9f 	stp	wzr, w10, [x20, #200]
    11f8:	b500006b 	cbnz	x11, 1204 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1204>
    11fc:	f940628a 	ldr	x10, [x20, #192]
    1200:	b400030a 	cbz	x10, 1260 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1260>
    1204:	92400108 	and	x8, x8, #0x1
    1208:	f9002288 	str	x8, [x20, #64]
    120c:	b4000109 	cbz	x9, 122c <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x122c>
    1210:	f9401e89 	ldr	x9, [x20, #56]
    1214:	d360fd2a 	lsr	x10, x9, #32
    1218:	29197e89 	stp	w9, wzr, [x20, #200]
    121c:	29182a9f 	stp	wzr, w10, [x20, #192]
    1220:	f940628a 	ldr	x10, [x20, #192]
    1224:	f100055f 	cmp	x10, #0x1
    1228:	540001cb 	b.lt	1260 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1260>  // b.tstop
    122c:	b4ff7d08 	cbz	x8, 1cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1cc>
    1230:	b9429e88 	ldr	w8, [x20, #668]
    1234:	f941528a 	ldr	x10, [x20, #672]
    1238:	2906229f 	stp	wzr, w8, [x20, #48]
    123c:	f9415688 	ldr	x8, [x20, #680]
    1240:	f9401a89 	ldr	x9, [x20, #48]
    1244:	a903228a 	stp	x10, x8, [x20, #48]
    1248:	b7f800c9 	tbnz	x9, #63, 1260 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1260>
    124c:	d360fd09 	lsr	x9, x8, #32
    1250:	29077e88 	stp	w8, wzr, [x20, #56]
    1254:	2906269f 	stp	wzr, w9, [x20, #48]
    1258:	f9401a89 	ldr	x9, [x20, #48]
    125c:	b6ff7b89 	tbz	x9, #63, 1cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1cc>
    1260:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1260: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_2d::cache+0x8
    1264:	f940e289 	ldr	x9, [x20, #448]
    1268:	f9408a8a 	ldr	x10, [x20, #272]
    126c:	f9400108 	ldr	x8, [x8]	126c: R_AARCH64_LDST64_ABS_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache+0x8
    1270:	f940a28b 	ldr	x11, [x20, #320]
    1274:	b981f28c 	ldrsw	x12, [x20, #496]
    1278:	b9800108 	ldrsw	x8, [x8]
    127c:	f9002289 	str	x9, [x20, #64]
    1280:	f9002a8a 	str	x10, [x20, #80]
    1284:	a93aaba9 	stp	x9, x10, [x29, #-88]
    1288:	f9404289 	ldr	x9, [x20, #128]
    128c:	f9404a8a 	ldr	x10, [x20, #144]
    1290:	f9003a8b 	str	x11, [x20, #112]
    1294:	a93bafbc 	stp	x28, x11, [x29, #-72]
    1298:	f940528b 	ldr	x11, [x20, #160]
    129c:	a93caba9 	stp	x9, x10, [x29, #-56]
    12a0:	f9405a89 	ldr	x9, [x20, #176]
    12a4:	f900329c 	str	x28, [x20, #96]
    12a8:	f900ca88 	str	x8, [x20, #400]
    12ac:	f900128c 	str	x12, [x20, #32]
    12b0:	a93da7ab 	stp	x11, x9, [x29, #-40]
    12b4:	34000b08 	cbz	w8, 1414 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1414>
    12b8:	f940b283 	ldr	x3, [x20, #352]
    12bc:	f940ba84 	ldr	x4, [x20, #368]
    12c0:	92407d08 	and	x8, x8, #0xffffffff
    12c4:	8b0802c0 	add	x0, x22, x8
    12c8:	d10163a1 	sub	x1, x29, #0x58
    12cc:	aa1f03e2 	mov	x2, xzr
    12d0:	aa1603e5 	mov	x5, x22
    12d4:	94000000 	bl	0 <_call_goal8_asm_systemv>	12d4: R_AARCH64_CALL26	_call_goal8_asm_systemv
    12d8:	f9001280 	str	x0, [x20, #32]
    12dc:	17fffbbc 	b	1cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1cc>
    12e0:	5400012d 	b.le	1304 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1304>
    12e4:	aa0003f5 	mov	x21, x0
    12e8:	aa1f03e0 	mov	x0, xzr
    12ec:	94000000 	bl	0 <time>	12ec: R_AARCH64_CALL26	time
    12f0:	8b150008 	add	x8, x0, x21
    12f4:	f9000348 	str	x8, [x26]	12f4: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
    12f8:	f100051f 	cmp	x8, #0x1
    12fc:	54ffb68a 	b.ge	9cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9cc>  // b.tcont
    1300:	17fffe5d 	b	c74 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc74>
    1304:	f9400348 	ldr	x8, [x26]	1304: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
    1308:	f100051f 	cmp	x8, #0x1
    130c:	54ffb60a 	b.ge	9cc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x9cc>  // b.tcont
    1310:	17fffe59 	b	c74 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xc74>
    1314:	f9400348 	ldr	x8, [x26]	1314: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
    1318:	f100051f 	cmp	x8, #0x1
    131c:	54ff8f0a 	b.ge	4fc <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x4fc>  // b.tcont
    1320:	17fffc7e 	b	518 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x518>
    1324:	f9400348 	ldr	x8, [x26]	1324: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
    1328:	f100051f 	cmp	x8, #0x1
    132c:	54ffd9ea 	b.ge	e68 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe68>  // b.tcont
    1330:	17fffed5 	b	e84 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0xe84>
    1334:	f9400348 	ldr	x8, [x26]	1334: R_AARCH64_LDST64_ABS_LO12_NC	.data._ZZN6Mips2C4jak1L21geco_spart_dump_armedEvE7s_delay
    1338:	f100051f 	cmp	x8, #0x1
    133c:	54ff9bca 	b.ge	6b4 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x6b4>  // b.tcont
    1340:	17fffce4 	b	6d0 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x6d0>
    1344:	f9400368 	ldr	x8, [x27]
    1348:	f940ea89 	ldr	x9, [x20, #464]
    134c:	f9001296 	str	x22, [x20, #32]
    1350:	f869490a 	ldr	x10, [x8, w9, uxtw]
    1354:	1101c12b 	add	w11, w9, #0x70
    1358:	f900fa8a 	str	x10, [x20, #496]
    135c:	927c6d6a 	and	x10, x11, #0xfffffff0
    1360:	f85a03ab 	ldur	x11, [x29, #-96]
    1364:	3cea6900 	ldr	q0, [x8, x10]
    1368:	1101812a 	add	w10, w9, #0x60
    136c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1370:	3d807280 	str	q0, [x20, #448]
    1374:	3cea6900 	ldr	q0, [x8, x10]
    1378:	1101412a 	add	w10, w9, #0x50
    137c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1380:	3d800320 	str	q0, [x25]
    1384:	3cea6900 	ldr	q0, [x8, x10]
    1388:	1101012a 	add	w10, w9, #0x40
    138c:	927c6d4a 	and	x10, x10, #0xfffffff0
    1390:	3d800260 	str	q0, [x19]
    1394:	3cea6900 	ldr	q0, [x8, x10]
    1398:	1100c12a 	add	w10, w9, #0x30
    139c:	927c6d4a 	and	x10, x10, #0xfffffff0
    13a0:	3d804e80 	str	q0, [x20, #304]
    13a4:	3cea6900 	ldr	q0, [x8, x10]
    13a8:	1100812a 	add	w10, w9, #0x20
    13ac:	927c6d4a 	and	x10, x10, #0xfffffff0
    13b0:	3d800160 	str	q0, [x11]
    13b4:	3cea6900 	ldr	q0, [x8, x10]
    13b8:	1100412a 	add	w10, w9, #0x10
    13bc:	927c6d4a 	and	x10, x10, #0xfffffff0
    13c0:	3d804680 	str	q0, [x20, #272]
    13c4:	3cea6900 	ldr	q0, [x8, x10]
    13c8:	91020128 	add	x8, x9, #0x80
    13cc:	f900ea88 	str	x8, [x20, #464]
    13d0:	3d804280 	str	q0, [x20, #256]
    13d4:	94000000 	bl	0 <std::chrono::_V2::steady_clock::now()>	13d4: R_AARCH64_CALL26	std::chrono::_V2::steady_clock::now()
    13d8:	f9403be8 	ldr	x8, [sp, #112]
    13dc:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	13dc: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof+0x8
    13e0:	91000021 	add	x1, x1, #0x0	13e0: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof+0x8
    13e4:	cb080000 	sub	x0, x0, x8
    13e8:	94000000 	bl	0 <__aarch64_ldadd8_relax>	13e8: R_AARCH64_CALL26	__aarch64_ldadd8_relax
    13ec:	aa1603e0 	mov	x0, x22
    13f0:	a9534ff4 	ldp	x20, x19, [sp, #304]
    13f4:	a95257f6 	ldp	x22, x21, [sp, #288]
    13f8:	a9515ff8 	ldp	x24, x23, [sp, #272]
    13fc:	a95067fa 	ldp	x26, x25, [sp, #256]
    1400:	a94f6ffc 	ldp	x28, x27, [sp, #240]
    1404:	a94e7bfd 	ldp	x29, x30, [sp, #224]
    1408:	6d4d23e9 	ldp	d9, d8, [sp, #208]
    140c:	910503ff 	add	sp, sp, #0x140
    1410:	d65f03c0 	ret
    1414:	52803202 	mov	w2, #0x190                 	// #400
    1418:	1400000e 	b	1450 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1450>
    141c:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	141c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x417
    1420:	91000109 	add	x9, x8, #0x0	1420: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x417
    1424:	52803802 	mov	w2, #0x1c0                 	// #448
    1428:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1428: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x43e
    142c:	91000108 	add	x8, x8, #0x0	142c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x43e
    1430:	a90623e9 	stp	x9, x8, [sp, #96]
    1434:	14000007 	b	1450 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1450>
    1438:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1438: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
    143c:	91000109 	add	x9, x8, #0x0	143c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
    1440:	52802b02 	mov	w2, #0x158                 	// #344
    1444:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1444: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3b6
    1448:	91000108 	add	x8, x8, #0x0	1448: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3b6
    144c:	a90623e9 	stp	x9, x8, [sp, #96]
    1450:	a9460fe0 	ldp	x0, x3, [sp, #96]
    1454:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1454: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x397
    1458:	91000021 	add	x1, x1, #0x0	1458: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x397
    145c:	90000004 	adrp	x4, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	145c: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xc9
    1460:	91000084 	add	x4, x4, #0x0	1460: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xc9
    1464:	94000000 	bl	0 <private_assert_failed(char const*, char const*, int, char const*, char const*)>	1464: R_AARCH64_CALL26	private_assert_failed(char const*, char const*, int, char const*, char const*)
    1468:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1468: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x3b6
    146c:	91000109 	add	x9, x8, #0x0	146c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x3b6
    1470:	52802b02 	mov	w2, #0x158                 	// #344
    1474:	90000008 	adrp	x8, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1474: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x36a
    1478:	91000108 	add	x8, x8, #0x0	1478: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x36a
    147c:	a90627e8 	stp	x8, x9, [sp, #96]
    1480:	17fffff4 	b	1450 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1450>
    1484:	14000001 	b	1488 <Mips2C::jak1::sp_process_block_2d::execute(void*)+0x1488>
    1488:	aa0003f4 	mov	x20, x0
    148c:	94000000 	bl	0 <std::chrono::_V2::steady_clock::now()>	148c: R_AARCH64_CALL26	std::chrono::_V2::steady_clock::now()
    1490:	f9403be8 	ldr	x8, [sp, #112]
    1494:	90000001 	adrp	x1, 0 <Mips2C::jak1::sp_process_block_2d::execute(void*)>	1494: R_AARCH64_ADR_PREL_PG_HI21	g_spart_prof+0x8
    1498:	91000021 	add	x1, x1, #0x0	1498: R_AARCH64_ADD_ABS_LO12_NC	g_spart_prof+0x8
    149c:	cb080000 	sub	x0, x0, x8
    14a0:	94000000 	bl	0 <__aarch64_ldadd8_relax>	14a0: R_AARCH64_CALL26	__aarch64_ldadd8_relax
    14a4:	aa1403e0 	mov	x0, x20
    14a8:	94000000 	bl	0 <_Unwind_Resume>	14a8: R_AARCH64_CALL26	_Unwind_Resume

Disassembly of section .text._ZN6Mips2C4jak119sp_process_block_2d4linkEv:

0000000000000000 <Mips2C::jak1::sp_process_block_2d::link()>:
   0:	d10103ff 	sub	sp, sp, #0x40
   4:	a9027bfd 	stp	x29, x30, [sp, #32]
   8:	a9034ff4 	stp	x20, x19, [sp, #48]
   c:	910083fd 	add	x29, sp, #0x20
  10:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	10: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0xf5
  14:	91000000 	add	x0, x0, #0x0	14: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0xf5
  18:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	18: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  1c:	90000013 	adrp	x19, 0 <g_ee_main_mem>	1c: R_AARCH64_ADR_GOT_PAGE	g_ee_main_mem
  20:	7100001f 	cmp	w0, #0x0
  24:	90000014 	adrp	x20, 0 <Mips2C::jak1::sp_process_block_2d::link()>	24: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_2d::cache
  28:	91000294 	add	x20, x20, #0x0	28: R_AARCH64_ADD_ABS_LO12_NC	Mips2C::jak1::sp_process_block_2d::cache
  2c:	f9400273 	ldr	x19, [x19]	2c: R_AARCH64_LD64_GOT_LO12_NC	g_ee_main_mem
  30:	f9400268 	ldr	x8, [x19]
  34:	8b204108 	add	x8, x8, w0, uxtw
  38:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	38: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x112
  3c:	91000000 	add	x0, x0, #0x0	3c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x112
  40:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  44:	f9000288 	str	x8, [x20]
  48:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	48: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  4c:	f9400268 	ldr	x8, [x19]
  50:	7100001f 	cmp	w0, #0x0
  54:	8b204108 	add	x8, x8, w0, uxtw
  58:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	58: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x333
  5c:	91000000 	add	x0, x0, #0x0	5c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x333
  60:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  64:	f9000688 	str	x8, [x20, #8]
  68:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	68: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  6c:	f9400268 	ldr	x8, [x19]
  70:	7100001f 	cmp	w0, #0x0
  74:	8b204108 	add	x8, x8, w0, uxtw
  78:	90000000 	adrp	x0, 0 <Mips2C::jak1::sp_process_block_2d::link()>	78: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x33e
  7c:	91000000 	add	x0, x0, #0x0	7c: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x33e
  80:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  84:	f9000a88 	str	x8, [x20, #16]
  88:	94000000 	bl	0 <jak1::intern_from_c(char const*)>	88: R_AARCH64_CALL26	jak1::intern_from_c(char const*)
  8c:	f9400268 	ldr	x8, [x19]
  90:	7100001f 	cmp	w0, #0x0
  94:	910003e9 	mov	x9, sp
  98:	91004133 	add	x19, x9, #0x10
  9c:	8b204108 	add	x8, x8, w0, uxtw
  a0:	52800280 	mov	w0, #0x14                  	// #20
  a4:	9a8803e8 	csel	x8, xzr, x8, eq	// eq = none
  a8:	f9000e88 	str	x8, [x20, #24]
  ac:	94000000 	bl	0 <operator new(unsigned long)>	ac: R_AARCH64_CALL26	operator new(unsigned long)
  b0:	5280026a 	mov	w10, #0x13                  	// #19
  b4:	90000009 	adrp	x9, 0 <Mips2C::jak1::sp_process_block_2d::link()>	b4: R_AARCH64_ADR_PREL_PG_HI21	.rodata.str1.1+0x356
  b8:	91000129 	add	x9, x9, #0x0	b8: R_AARCH64_ADD_ABS_LO12_NC	.rodata.str1.1+0x356
  bc:	4e080d41 	dup	v1.2d, x10
  c0:	5285ad68 	mov	w8, #0x2d6b                	// #11627
  c4:	3dc00120 	ldr	q0, [x9]
  c8:	72ac8648 	movk	w8, #0x6432, lsl #16
  cc:	f90003e0 	str	x0, [sp]
  d0:	b800f008 	stur	w8, [x0, #15]
  d4:	3d800000 	str	q0, [x0]
  d8:	3c8083e1 	stur	q1, [sp, #8]
  dc:	39004c1f 	strb	wzr, [x0, #19]
  e0:	90000000 	adrp	x0, 0 <Mips2C::gLinkedFunctionTable>	e0: R_AARCH64_ADR_GOT_PAGE	Mips2C::gLinkedFunctionTable
  e4:	90000002 	adrp	x2, 0 <Mips2C::jak1::sp_process_block_2d::link()>	e4: R_AARCH64_ADR_PREL_PG_HI21	Mips2C::jak1::sp_process_block_2d::execute(void*)
  e8:	91000042 	add	x2, x2, #0x0	e8: R_AARCH64_ADD_ABS_LO12_NC	Mips2C::jak1::sp_process_block_2d::execute(void*)
  ec:	f9400000 	ldr	x0, [x0]	ec: R_AARCH64_LD64_GOT_LO12_NC	Mips2C::gLinkedFunctionTable
  f0:	910003e1 	mov	x1, sp
  f4:	52802003 	mov	w3, #0x100                 	// #256
  f8:	94000000 	bl	0 <Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)>	f8: R_AARCH64_CALL26	Mips2C::LinkedFunctionTable::reg(std::__cxx11::basic_string<char, std::char_traits<char>, std::allocator<char> > const&, unsigned long (*)(void*), unsigned int)
  fc:	f94003e0 	ldr	x0, [sp]
 100:	eb13001f 	cmp	x0, x19
 104:	54000040 	b.eq	10c <Mips2C::jak1::sp_process_block_2d::link()+0x10c>  // b.none
 108:	94000000 	bl	0 <operator delete(void*)>	108: R_AARCH64_CALL26	operator delete(void*)
 10c:	a9434ff4 	ldp	x20, x19, [sp, #48]
 110:	a9427bfd 	ldp	x29, x30, [sp, #32]
 114:	910103ff 	add	sp, sp, #0x40
 118:	d65f03c0 	ret
 11c:	f94003e8 	ldr	x8, [sp]
 120:	eb13011f 	cmp	x8, x19
 124:	aa0003f3 	mov	x19, x0
 128:	54000060 	b.eq	134 <Mips2C::jak1::sp_process_block_2d::link()+0x134>  // b.none
 12c:	aa0803e0 	mov	x0, x8
 130:	94000000 	bl	0 <operator delete(void*)>	130: R_AARCH64_CALL26	operator delete(void*)
 134:	aa1303e0 	mov	x0, x19
 138:	94000000 	bl	0 <_Unwind_Resume>	138: R_AARCH64_CALL26	_Unwind_Resume

EXIT 0
